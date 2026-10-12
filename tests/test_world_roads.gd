## test_world_roads.gd — T5 WORLD-05 道路骨架与绕行自动生成单测（执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-05 + §5 ROAD-02 桥放置规则
##   格边转译 + 修订记录三之 6（本卡自 T4 ROAD-03 上移））
## 覆盖锚（卡表「测试锚」逐条）：
##   - 必需聚落全连通：骨架生成后 ROAD_NETWORK_DISCONNECTED 必须为零；
##   - 禁桥失败明确：错误串指向具体聚落对与河段（最小诊断输出锚）；
##   - 可选回路不破硬约束：加回路后可达性/footprint 冲突全量重验；
##   - 修复/定线不动 locked 约束（模板锁定区先验——道路绕开锁定格）；
##   - 附加面：MST 结构（3 聚落 = 2 干线）、桥认领语义（crossing.river_edge ∈
##     reach.edges、两岸 = link 两端、link 表 road_id 对账）、路径权重不进数据、
##     同 seed 确定性。
## oracle 原则：连通判定 = 测试内独立并查集（不复制生成器 MST）；桥事实 =
## WorldData 公开合同（reach.edges/crossing_index/link 对账）；河链 fixture 沿
## tools/river_fixtures.gd 几何构造先例（与本文件独立拼装）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const WorldTemplateClass := preload("res://scripts/core/data/world_template.gd")
const WorldPipeline := preload("res://scripts/content/world_pipeline.gd")
const RoadGen := preload("res://scripts/content/road_network_generator.gd")
const WorldValidator := preload("res://scripts/content/world_validator.gd")
const RiverFix := preload("res://tools/river_fixtures.gd")

const T_WATER := 3

func _cell_of(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))

## 小模板生成世界（24×16；九阶段全开）
func _generated(template: WorldTemplateClass = null, seed_value := 7) -> Dictionary:
	var t := template if template != null else _small_template()
	return WorldPipeline.generate_validated(t, seed_value)


func _small_template() -> WorldTemplateClass:
	var t := WorldTemplateClass.new()
	t.width = 24
	t.height = 16
	return t


## 连通 oracle：并查集（聚落 = 节点；一条路含两聚落锚 = 连边）。
func _settlements_connected(world: WorldDataClass) -> bool:
	var settlements := world.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT)
	if settlements.size() < 2:
		return true
	var comp := {}
	var anchor_idx := {}
	for i in settlements.size():
		comp[i] = i
		anchor_idx[settlements[i].cell_id] = i
	for r in world.roads:
		var members: Array[int] = []
		for cid in r.cells:
			if anchor_idx.has(cid):
				members.append(int(anchor_idx[cid]))
		for k in range(1, members.size()):
			var a := members[0]
			while comp[a] != a:
				a = comp[a]
			var b := members[k]
			while comp[b] != b:
				b = comp[b]
			comp[a] = b
	var root := 0
	while comp[root] != root:
		root = comp[root]
	for i in settlements.size():
		var ri := i
		while comp[ri] != ri:
			ri = comp[ri]
		if ri != root:
			return false
	return true

# ================= 必需聚落全连通 =================

func test_mst_connects_all_settlements_zero_disconnected() -> void:
	var r := _generated()
	expect(r["ok"], "生成应成功：%s" % r.get("error", ""))
	if not r["ok"]:
		return
	var world: WorldDataClass = r["world"]
	var settlements := world.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT)
	expect(settlements.size() >= 2, "≥2 聚落（骨架对象存在）")
	expect(_settlements_connected(world), "必需聚落全连通（并查集 oracle）")
	# 校验器路网面（require_road_network）：ROAD_NETWORK_DISCONNECTED 必须为零
	var report := WorldValidator.validate_report(r["map"], world, {
		"water_terrain_id": T_WATER, "max_road_delta": 1,
		"max_bridge_bank_delta": 2, "require_road_network": true,
	})
	var first_code := ""
	if not report["ok"]:
		first_code = String((report["errors"] as Array)[0]["code"])
	expect(report["ok"], "require_road_network 校验零错误（got %s）" % first_code)
	# MST 结构：3 聚落 = 恰 2 条干线（无环——可选回路默认 0）
	expect_eq(world.roads.size(), 2, "3 聚落 MST = 2 干线（road_loop_count 默认 0）")
	# 道路满足 Δ 硬上限（独立逐对复查——ROAD-01 生成配置口径）
	for rd in world.roads:
		for k in rd.cells.size() - 1:
			var delta := absi(r["map"].elevation_at(_cell_of(r["map"], rd.cells[k]))
				- r["map"].elevation_at(_cell_of(r["map"], rd.cells[k + 1])))
			var link := WorldDataClass.link_id_of(rd.cells[k], rd.cells[k + 1])
			var bridged := world.crossing_index().has(link)
			expect(delta <= 1 or bridged,
				"road %d 段 %d→%d Δ=%d ≤ max_road_delta=1（桥段豁免——桥址校验管辖）"
				% [rd.road_id, rd.cells[k], rd.cells[k + 1], delta])

# ================= 桥认领语义（河分离场景）=================

## 手工河分离场景（make_fixed_maps 河链先例的测试内拼装）：17×13 全陆图 +
## 南北直河（greedy_chain 目标列 8）+ 河口湖 + 两岸聚落。
## 返回 {"map", "world", "chain"}——世界含 rivers/water_bodies/links/pois。
func _river_separated_world() -> Dictionary:
	var W := 17
	var H := 13
	var map := MapDataClass.new(W, H)
	for cell in map.cells():
		map.set_elevation(cell, 1)
		map.set_terrain(cell, 0)
		map.set_passable(cell, true)
	var links := RiverFix.all_links(map)
	var start := Vector2i(-1, -1)
	for lk in links:
		var a := RiverFix.cell_of_id(map, lk.x)
		var b := RiverFix.cell_of_id(map, lk.y)
		var ra := Hex.offset_of(a)
		var rb := Hex.offset_of(b)
		if mini(ra.y, rb.y) == 0 and maxi(ra.x, rb.x) == 8 and mini(ra.x, rb.x) == 7:
			start = lk
			break
	if start.x < 0:
		return {}
	var chain := RiverFix.greedy_chain(map, links, start, 64, _column_eight)
	var term: Vector2i = chain[chain.size() - 1]
	var lake_members: Array[int] = [term.x]
	var member_cell := RiverFix.cell_of_id(map, term.x)
	for d in 6:
		var nb := Hex.neighbor(member_cell, d)
		if map.has_cell(nb) and nb != RiverFix.cell_of_id(map, term.y):
			var nb_id := map.index_of(nb)
			if not lake_members.has(nb_id):
				lake_members.append(nb_id)
	lake_members.sort()
	for cid in lake_members:
		var c := RiverFix.cell_of_id(map, cid)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
	var world := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.flow_level = 1
	reach.water_levels = []
	for i in chain.size():
		reach.water_levels.append(0)
	reach.bed_level = -1
	reach.water_body_id = 0
	world.rivers.append(reach)
	var body := WorldDataClass.WaterBodyData.new()
	body.water_body_id = 0
	body.kind = WorldDataClass.WaterBodyData.Kind.LAKE
	body.water_level = 0
	body.member_cells = lake_members
	body.inlet_links = [term]
	body.terminal = true
	world.water_bodies.append(body)
	for e in chain:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = e
		lk.river_reach_id = 0
		world.links.append(lk)
	for col in [2, 14]:
		var cell_id := map.index_of(Hex.axial_of(Vector2i(col, 6)))
		var p := WorldDataClass.POIData.new()
		p.poi_id = world.pois.size()
		p.kind = WorldDataClass.POIData.Kind.SETTLEMENT
		p.cell_id = cell_id
		p.footprint_cells = [cell_id]
		p.role = "probe_capital"
		world.pois.append(p)
		var z := WorldDataClass.POIData.new()
		z.poi_id = world.pois.size()
		z.kind = WorldDataClass.POIData.Kind.SPAWN_ZONE
		z.cell_id = cell_id
		z.footprint_cells = [cell_id]
		for d in 6:
			z.footprint_cells.append(map.index_of(Hex.neighbor(_cell_of(map, cell_id), d)))
		z.footprint_cells.sort()
		z.role = "spawn_zone"
		world.pois.append(z)
	return {"map": map, "world": world, "chain": chain}


static func _column_eight(_row: int) -> int:
	return 8


func test_bridge_created_and_claimed_when_river_separates() -> void:
	var fix := _river_separated_world()
	expect(not fix.is_empty(), "河分离场景应可构造")
	if fix.is_empty():
		return
	var map: MapDataClass = fix["map"]
	var world: WorldDataClass = fix["world"]
	var cfg := {"water_terrain_id": T_WATER, "max_road_delta": 1,
		"max_bridge_bank_delta": 2, "road_loop_count": 0,
		"sea_level": 0.25, "elevation_levels": 4}
	var r := RoadGen.generate(map, world, cfg)
	expect(r["ok"], "跨河连接应成功（合法桥址存在）：%s" % r.get("error", ""))
	if not r["ok"]:
		return
	var roads: Array = r["roads"]
	var crossings: Array = r["crossings"]
	expect(roads.size() >= 1, "东西干线路产出")
	expect(crossings.size() >= 1, "河分离场景必建桥（无桥即失败的正面样本）")
	var chain: Array[Vector2i] = fix["chain"]
	var river_idx := world.river_edge_index()
	for c in crossings:
		expect(chain.has(c.river_edge), "桥认领边 ∈ reach.edges（有河才有桥）")
		expect_eq(c.bank_a, c.river_edge.x, "两岸格 = river_edge 两端（bank_a）")
		expect_eq(c.bank_b, c.river_edge.y, "两岸格 = river_edge 两端（bank_b）")
	# 认领边 = 道路实际跨接的河边（两岸都有路）+ link 表 road_id 对账
	var scratch := WorldDataClass.empty()
	scratch.rivers = world.rivers
	scratch.water_bodies = world.water_bodies
	scratch.pois = world.pois
	scratch.roads = r["roads"]
	scratch.crossings = r["crossings"]
	scratch.links = r["links"]
	var verdict := scratch.validate(map, T_WATER, 1, 2)
	expect_eq(verdict, "", "跨河路网全量校验通过（含 link.road_id 对账与桥址）")
	if verdict != "":
		return
	for c in crossings:
		var claimed: Variant = null
		for lk in scratch.links:
			if lk.link_id == c.river_edge:
				claimed = lk.road_id
		expect(claimed != null and int(claimed) >= 0,
			"桥认领边在 link 表挂 road_id（河在下、路在上——拍板⑤）")

func test_no_legal_bridge_site_fails_pointing_at_pair_and_reach() -> void:
	# 禁桥失败样本：河水位 5 > 全部两岸高程（1）→ 净空不满足 = **每条边**都无
	# 合法桥址（桥头 Δ 抬升法会被链的锯齿共享端格破坏——部分边仍 Δ=0；净空法
	# 与端格分布无关，确定性全禁）→ 具名失败指向聚落对与河段
	# （WORLD-05 测试锚「禁桥失败明确」）
	var fix := _river_separated_world()
	if fix.is_empty():
		fail("河分离场景构造失败")
		return
	var map: MapDataClass = fix["map"]
	var world: WorldDataClass = fix["world"]
	var reach: WorldDataClass.RiverReachData = world.rivers[0]
	for i in reach.water_levels.size():
		reach.water_levels[i] = 5  # 水位抬高：净空 max(两岸 1) < 5 → 全边无址
	(world.water_bodies[0] as WorldDataClass.WaterBodyData).water_level = 5
	var cfg := {"water_terrain_id": T_WATER, "max_road_delta": 1,
		"max_bridge_bank_delta": 2, "road_loop_count": 0,
		"sea_level": 0.25, "elevation_levels": 4}
	var r := RoadGen.generate(map, world, cfg)
	expect(not r["ok"], "无合法桥址应具名失败（不删河/不压山伪造达标）")
	if r["ok"]:
		return
	var err := str(r["error"])
	expect(err.contains("ROAD_NETWORK_DISCONNECTED"), "错误码 = ROAD_NETWORK_DISCONNECTED")
	# 指向具体聚落对与河段：两聚落格 id 与 reach id 均 in 错误串
	var west := world.pois[0].cell_id
	var east := world.pois[2].cell_id
	expect(err.contains(str(west)) and err.contains(str(east)),
		"错误串含聚落对格 id（%d / %d）：%s" % [west, east, err.substr(0, 160)])
	expect(err.contains("reach") and err.contains("[0]"),
		"错误串含阻挡河段 reach id：%s" % err.substr(0, 160))

# ================= 可选回路（加路后全量重验）=================

func test_optional_loops_added_and_hard_constraints_hold() -> void:
	var t := _small_template()
	t.road_loop_count = 2
	var r := _generated(t)
	expect(r["ok"], "回路配置生成应成功：%s" % r.get("error", ""))
	if not r["ok"]:
		return
	var world: WorldDataClass = r["world"]
	# 3 聚落全对 = 3 条连接；MST 2 + 回路 ≤ 2
	expect(world.roads.size() >= 2 and world.roads.size() <= 4,
		"干线 2 + 回路 ≤ 2（got %d 条）" % world.roads.size())
	expect(_settlements_connected(world), "加回路后聚落仍全连通")
	# 全量重验（可达性/footprint）：生成器每次加路后已重验，此处外部复核
	var report := WorldValidator.validate_report(r["map"], world, {
		"water_terrain_id": T_WATER, "max_road_delta": 1,
		"max_bridge_bank_delta": 2, "require_road_network": true,
		"resource_budget": 10,
	})
	var first_exp := ""
	if not report["ok"]:
		first_exp = String((report["errors"] as Array)[0]["explanation"])
	expect(report["ok"], "加回路后可达性/footprint 全量重验通过（got %s）" % first_exp)
	# 一 link 至多一路（独立复查——回路弃路回滚不留脏 road_id）
	var seen := {}
	for rd in world.roads:
		for k in rd.cells.size() - 1:
			var link := WorldDataClass.link_id_of(rd.cells[k], rd.cells[k + 1])
			expect(not seen.has(link), "link %s 不被两条路复用（先见 road %d）"
				% [str(link), int(seen.get(link, -1))])
			seen[link] = rd.road_id

# ================= 修复/定线不动 locked（模板锁定区先验）=================

func test_roads_avoid_locked_cells() -> void:
	# 先验：无锁跑一次 → 取首条路中段格为锁定区 → 有锁重跑 → 道路全部绕开
	var base := _generated(null, 7)
	expect(base["ok"], "无锁基线生成应成功")
	if not base["ok"]:
		return
	var base_world: WorldDataClass = base["world"]
	expect(base_world.roads.size() >= 1, "基线有路")
	if base_world.roads.is_empty():
		return
	var road0: WorldDataClass.RoadData = base_world.roads[0]
	var mid := road0.cells[road0.cells.size() / 2]
	var t := _small_template()
	t.locked = ["cell:%d" % mid]
	var r := WorldPipeline.generate_validated(t, 7)
	expect(r["ok"], "锁定格重跑应成功（绕行）：%s" % r.get("error", ""))
	if not r["ok"]:
		return
	var world: WorldDataClass = r["world"]
	for rd in world.roads:
		expect(not rd.cells.has(mid), "道路 %d 绕开锁定格 %d（修复/定线不动 locked）"
			% [rd.road_id, mid])
	var report := WorldValidator.validate_report(r["map"], world, {
		"water_terrain_id": T_WATER, "max_road_delta": 1,
		"max_bridge_bank_delta": 2, "require_road_network": true,
		"locked_cells": [mid],
	})
	expect(report["ok"], "锁定约束校验零错误（LOCKED_CONSTRAINT_CONFLICT 为零）")

# ================= 路径权重不进数据 + 确定性 =================

func test_path_weights_not_in_world_data_and_deterministic() -> void:
	var r1 := _generated(null, 5)
	var r2 := _generated(null, 5)
	expect(r1["ok"] and r2["ok"], "两次生成应成功")
	if not (r1["ok"] and r2["ok"]):
		return
	# 生成器内部路径成本不落世界事实（草案 §7 禁止项）：道路对象仅五键面
	var facts: Dictionary = (r1["world"] as WorldDataClass).to_dict()
	for rd in facts["roads"]:
		var keys := (rd as Dictionary).keys()
		keys.sort()
		expect_eq(str(keys), str(["cells", "connects_pois", "is_loop", "road_class", "road_id"]),
			"道路序列化键集 = 草案 §7 五键（无成本字段）")
	# 同 seed 确定性：道路/桥事实逐字节一致
	expect_eq(JSON.stringify(facts["roads"]), JSON.stringify((r2["world"] as WorldDataClass).to_dict()["roads"]),
		"同 seed 道路事实一致")
	expect_eq(JSON.stringify(facts["crossings"]),
		JSON.stringify((r2["world"] as WorldDataClass).to_dict()["crossings"]),
		"同 seed 桥事实一致")
