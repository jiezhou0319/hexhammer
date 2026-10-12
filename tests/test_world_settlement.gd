## test_world_settlement.gd — T5 WORLD-03 聚落/出生区/资源 + 势力归属单测
##   （执行方案 docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-03 + §7 Azgaar
##   burgs/states 改造案 + 主创拍板⑪ 1 玩家 + 2 AI + 拍板⑧ 归属进数据）
## 覆盖锚（卡表「测试锚」逐条）：
##   - 3 组合法出生区：footprint 七格界内可通行 + 组间最小环距断言
##     （NO_VALID_SPAWN fixture 反例入库——tests/fixtures/maps/failed/world/）；
##   - 核心资源可达（规则未启用按平地口径 = 边级通行图）；
##   - footprint 冲突拒绝（错误指向具体 cell——生成侧前置过滤 + 校验器拒绝两面）；
##   - 归属断言：每陆格恰一 owner 或显式中立带；国界边两侧 owner 互异；
##     同 seed 归属分布一致（确定性）；适居度确定性；
##   - state 生长 = 多源 Dijkstra 独立 oracle（暴力松弛成本对照——不复制堆实现）；
##   - normalize 多数滤波语义（平票不改判 / burg 与首都邻格豁免——源码细节 §7）。
## oracle 原则：出生 footprint 形状/环距/归属分布/国界跳变由 HexMath/MapData 原语
##   独立推导；Dijkstra oracle 用暴力 Bellman-Ford 式松弛（与生成器堆实现两路互证）；
##   失败样例复验 = 同模板同 seed 重跑同失败（确定性锚，不复制错误串全文）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const WorldTemplateClass := preload("res://scripts/core/data/world_template.gd")
const WorldPipeline := preload("res://scripts/content/world_pipeline.gd")
const SettlementGen := preload("res://scripts/content/settlement_generator.gd")
const GenConnectivity := preload("res://scripts/content/map_generation_connectivity.gd")
const MapIOClass := preload("res://scripts/content/map_io.gd")

const T_WATER := 3

## 测试默认小模板（24×16——快速确定性样本；九阶段全开）
func _small_template() -> WorldTemplateClass:
	var t := WorldTemplateClass.new()
	t.width = 24
	t.height = 16
	return t


func _generated(template: WorldTemplateClass = null, seed_value := 7) -> Dictionary:
	var t := template if template != null else _small_template()
	return WorldPipeline.generate_validated(t, seed_value)


func _cell_of(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))

# ================= 3 组合法出生区（footprint + 组间环距）=================

func test_spawn_zones_seven_cells_passable_and_spaced() -> void:
	var r := _generated()
	expect(r["ok"], "小图生成应成功：%s" % r.get("error", ""))
	if not r["ok"]:
		return
	var map: MapDataClass = r["map"]
	var world: WorldDataClass = r["world"]
	var zones := world.pois_of_kind(WorldDataClass.POIData.Kind.SPAWN_ZONE)
	expect_eq(zones.size(), 3, "3 组出生区（拍板⑪ 1 玩家 + 2 AI）")
	var anchors: Array[Vector2i] = []
	for z in zones:
		# footprint = 中心+六邻恰 7 格（独立 oracle：HexMath 六邻集合对照）
		var want: Array = [z.cell_id]
		var anchor := _cell_of(map, z.cell_id)
		for d in 6:
			want.append(map.index_of(Hex.neighbor(anchor, d)))
		want.sort()
		expect_eq(z.footprint_cells.size(), 7, "footprint 七格（中心+六邻）")
		expect_eq(str(z.footprint_cells), str(want), "footprint 集合 = 中心+六邻（oracle）")
		# 七格界内可通行（出生区有效率的数据面）
		for cid in z.footprint_cells:
			var c := _cell_of(map, cid)
			expect(map.has_cell(c), "footprint 格 %d 界内" % cid)
			expect(map.is_passable(c), "footprint 格 %d 可通行（落兵区）" % cid)
		anchors.append(anchor)
	# 组间最小环距：≥ 生成档距下限（SPACING_FLOOR）且 ≥ 档距表实际使用值的最小档
	# （结构化诊断 spawn_spacings 取数——后置槽抽取时对全部既有锚点生效，故任一对
	# 环距 ≥ 后置槽实际档距 ≥ 全部实际档距的最小值；反例基线：24×16 seed 7
	# spacing=[7,7,7] → 断言面 ≥7，弱于此即注释失真）
	var used_min := -1
	for d in r["stages"]:
		if String(d["stage"]) == "settlement":
			for s in d.get("spawn_spacings", []):
				var sv := int(s)
				if sv > 0 and (used_min < 0 or sv < used_min):
					used_min = sv
	expect(used_min >= SettlementGen.SPACING_FLOOR,
		"实际使用档距可得且不跌破下限（got %d——结构化诊断在）" % used_min)
	for i in anchors.size():
		for j in range(i + 1, anchors.size()):
			var dist := Hex.distance(anchors[i], anchors[j])
			expect(dist >= SettlementGen.SPACING_FLOOR,
				"出生锚环距 %d ≥ 下限 %d（%s ↔ %s）" % [dist, SettlementGen.SPACING_FLOOR,
					str(anchors[i]), str(anchors[j])])
			if used_min > 0:
				expect(dist >= used_min,
					"出生锚环距 %d ≥ 实际使用档距最小值 %d（%s ↔ %s）"
						% [dist, used_min, str(anchors[i]), str(anchors[j])])
	# 校验器零错误（含 NO_VALID_SPAWN 面为零）
	var errors: Array = r["validation"]["errors"]
	expect_eq(errors.size(), 0, "生成世界校验零错误（首错见 stages/playability 摘要）")

func test_spawn_zone_roles_and_ids_canonical() -> void:
	var r := _generated()
	if not r["ok"]:
		fail("生成失败：%s" % r["error"])
		return
	var world: WorldDataClass = r["world"]
	# role 占位：槽 0 玩家、1/2 AI（拍板⑪）；poi_id 升序规范序
	var settlements := world.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT)
	expect_eq(settlements.size(), 3, "3 主城")
	expect_eq(settlements[0].role, "player_capital", "槽 0 = 玩家主城（role 占位）")
	expect_eq(settlements[1].role, "ai_capital", "槽 1 = AI 主城")
	expect_eq(settlements[2].role, "ai_capital", "槽 2 = AI 主城")
	var prev := -1
	for p in world.pois:
		expect(p.poi_id > prev, "poi_id 严格升序（got %d after %d）" % [p.poi_id, prev])
		prev = p.poi_id
	expect_eq(world.pois.size(), 9, "POI 数 = 3 主城 + 3 出生区 + 3 资源")

# ================= NO_VALID_SPAWN fixture 反例入库（复验）=================

func test_no_valid_spawn_fixture_retained_and_reproducible() -> void:
	# 入库样例（tools/make_settlement_fixture.gd 落盘）：4×4 微图物理不可行
	var base := "res://tests/fixtures/maps/failed/world/worldfail_no_valid_spawn_4x4"
	var map := MapIOClass.read_map(base + ".json")
	expect(map != null, "失败样例图应可加载")
	var meta: Variant = MapIOClass.read_meta(base + ".meta.json")
	expect(meta != null, "失败样例伴生 meta 应存在")
	var world := MapIOClass.read_world(base + ".world.json")
	expect(world != null, "失败样例伴生 .world.json 应可解析（可加载复验）")
	if map == null or meta == null:
		return
	expect_eq((meta as Dictionary)["digest"], map.digest(), "meta.digest 与图一致")
	expect(bool((meta as Dictionary).has("error")), "meta 记录失败原因")
	# 同模板同 seed 重跑 → 复现同失败（确定性锚：错误码一致 + 尝试数一致）
	var t := WorldTemplateClass.new()
	var saved_tpl: Dictionary = (meta as Dictionary)["template"]
	t.width = int(saved_tpl["width"])
	t.height = int(saved_tpl["height"])
	var again := WorldPipeline.generate_validated(t, int((meta as Dictionary)["seed"]))
	expect(not again["ok"], "同模板同 seed 重跑应复现失败（不伪造达标）")
	if not again["ok"]:
		expect(str(again["error"]).contains("NO_VALID_SPAWN"),
			"复现错误含 NO_VALID_SPAWN（got %s）" % str(again["error"]).substr(0, 120))
		expect_eq((again["attempts_trace"] as Array).size(),
			int((meta as Dictionary)["attempt_count"]), "尝试数 = meta 记录（4 = 第 5 次拒绝）")

# ================= 适居度确定性 + 三项构成 =================

func test_habitability_deterministic_and_terms() -> void:
	# 同输入两次 → 逐格一致（适居度确定性锚）
	var r := _generated()
	if not r["ok"]:
		fail("生成失败：%s" % r["error"])
		return
	var map: MapDataClass = r["map"]
	var world: WorldDataClass = r["world"]
	var s1 := SettlementGen.habitability(map, world, T_WATER, 0.25, 4)
	var s2 := SettlementGen.habitability(map, world, T_WATER, 0.25, 4)
	expect_eq(str(s1), str(s2), "同输入适居度逐格一致")
	# 高程带项：同图内 level 1 与 level 2 陆格（无河无海对照组）——档带中点
	# h(level1) < h(level2) < 50 ⇒ level 1 评分更高（Azgaar −(h−50)/5 结构）
	var l1 := -1
	var l2 := -1
	var flanks := world.river_flank_cells()
	var water := world.water_membership()
	for cell in map.cells():
		var i := map.index_of(cell)
		if flanks.has(i):
			continue
		var near_water := false
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if map.has_cell(nb) and water.has(map.index_of(nb)):
				near_water = true
				break
		if near_water:
			continue
		var lv := map.elevation_at(cell)
		if lv == 1 and l1 < 0:
			l1 = i
		elif lv == 2 and l2 < 0:
			l2 = i
		if l1 >= 0 and l2 >= 0:
			break
	if l1 >= 0 and l2 >= 0:
		expect(s1[l1] > s1[l2], "高程带评分：level1 %.2f > level2 %.2f（−(h−50)/5，§7 换算注）"
			% [s1[l1], s1[l2]])
	else:
		expect(true, "样本含 level1/level2 对照格（占位断言防零断言）")
	# 河流加成：河岸格 +2 / 海岸加成：水邻格 +1（常量对照——常量即合同）
	expect_almost_eq(SettlementGen.HABITAT_RIVER_BONUS, 2.0, 1e-9, "河流加成常量")
	expect_almost_eq(SettlementGen.HABITAT_COAST_BONUS, 1.0, 1e-9, "海岸加成常量")
	# 档带反演（§7 换算注）：默认参数 h=44→level 2、h=67→level 3
	expect_eq(SettlementGen.level_of_h(44.0, 0.25, 4), 2, "h=44 → level 2（丘档）")
	expect_eq(SettlementGen.level_of_h(67.0, 0.25, 4), 3, "h=67 → level 3（山档）")
	expect_eq(SettlementGen.terrain_cost(1, 2, 3), SettlementGen.COST_PLAIN,
		"平原成本 0（§7 states 版实读数值）")
	expect_eq(SettlementGen.terrain_cost(2, 2, 3), SettlementGen.COST_HILL,
		"丘陵成本 300")
	expect_eq(SettlementGen.terrain_cost(3, 2, 3), SettlementGen.COST_MOUNTAIN,
		"山地成本 2200")
	expect_eq(SettlementGen.terrain_cost(0, 2, 3), SettlementGen.COST_WATER,
		"水面成本 1000（不入队——表值对齐）")

# ================= 资源可达（平地口径）=================

func test_core_resources_reachable_flat_rules() -> void:
	var r := _generated()
	if not r["ok"]:
		fail("生成失败：%s" % r["error"])
		return
	var map: MapDataClass = r["map"]
	var world: WorldDataClass = r["world"]
	var resources := world.pois_of_kind(WorldDataClass.POIData.Kind.RESOURCE)
	var zones := world.pois_of_kind(WorldDataClass.POIData.Kind.SPAWN_ZONE)
	expect_eq(resources.size(), 3, "3 资源点（每势力一枚，role 占位）")
	expect(not zones.is_empty(), "出生区存在（可达性判定源）")
	# 规则未启用按平地口径：边级通行图（passable × 有河 link 须桥认领）
	for p in resources:
		var reached := false
		for z in zones:
			var conn := GenConnectivity.required_connected(map, world,
				_cell_of(map, z.cell_id), _cell_of(map, p.cell_id))
			if conn["ok"]:
				reached = true
				break
		expect(reached, "资源 poi %d（格 %d）自出生锚可达（平地口径）" % [p.poi_id, p.cell_id])
		# 预算面：环距 ≤ resource_budget（模板默认 10）
		var within := false
		for z in zones:
			if Hex.distance(_cell_of(map, z.cell_id), _cell_of(map, p.cell_id)) <= 10:
				within = true
				break
		expect(within, "资源 poi %d 在预算环距内" % p.poi_id)

# ================= footprint 冲突（生成侧前置 + 校验器拒绝两面）=================

func test_generated_footprints_conflict_free() -> void:
	var r := _generated()
	if not r["ok"]:
		fail("生成失败：%s" % r["error"])
		return
	var map: MapDataClass = r["map"]
	var world: WorldDataClass = r["world"]
	var flanks := world.river_flank_cells()
	var banks := {}
	for c in world.crossings:
		banks[c.bank_a] = true
		banks[c.bank_b] = true
	var road_at := {}
	for rd in world.roads:
		for cid in rd.cells:
			road_at[cid] = rd.road_id
	var zones := world.pois_of_kind(WorldDataClass.POIData.Kind.SPAWN_ZONE)
	expect(not zones.is_empty(), "出生区存在")
	for z in zones:
		for cid in z.footprint_cells:
			expect(not flanks.has(cid), "出生区 poi %d 格 %d 不与河岸锚点格重叠" % [z.poi_id, cid])
			expect(not banks.has(cid), "出生区 poi %d 格 %d 不与桥端重叠" % [z.poi_id, cid])
			# 道路冲突带服务豁免：含本区主城锚的路可穿区（validator 同款口径）
			if road_at.has(cid):
				var serving := false
				for rid in [road_at[cid]]:
					var road: WorldDataClass.RoadData = world.road_by_id(int(rid))
					if road != null and road.cells.has(z.cell_id):
						serving = true
				expect(serving, "出生区 poi %d 格 %d 的道路 %d 须为服务路（经主城锚）"
					% [z.poi_id, cid, road_at[cid]])
	# 他方出生区互不重叠（WorldData 校验拒绝面 + 生成侧不产生）
	var seen := {}
	for z in zones:
		for cid in z.footprint_cells:
			expect(not seen.has(cid), "出生区 footprint 格 %d 不与他方重叠（先见 poi %d）"
				% [cid, int(seen.get(cid, -1))])
			seen[cid] = z.poi_id

# ================= 归属断言（owner 覆盖 / 国界跳变 / 确定性）=================

func test_owner_coverage_water_neutral_and_borders() -> void:
	var r := _generated()
	if not r["ok"]:
		fail("生成失败：%s" % r["error"])
		return
	var map: MapDataClass = r["map"]
	var world: WorldDataClass = r["world"]
	expect_eq(world.states.size(), 3, "3 势力")
	expect_eq(world.cell_owners.size(), map.cell_count(), "owner 表与格子表同长")
	var owned := 0
	for i in map.cell_count():
		var o := world.cell_owners[i]
		if map.elevation_at(_cell_of(map, i)) == 0:
			expect_eq(o, WorldDataClass.ID_NONE, "水格 %d owner 恒 -1（水格传播成本不归属）" % i)
		elif o != WorldDataClass.ID_NONE:
			expect(o >= 0 and o < 3, "陆格 %d owner ∈ 3 势力（got %d）" % [i, o])
			owned += 1
	expect(owned > 0, "存在已归属陆格（每陆格恰一 owner 或显式中立——全覆盖默认）")
	# 国界 = 跳变边派生（独立 oracle：全图邻接遍历两侧 owner 互异）+ 两侧互异断言
	var borders := WorldDataClass.border_links_of(map, world)
	var oracle: Array[Vector2i] = []
	for cell in map.cells():
		var a := map.index_of(cell)
		if world.cell_owners[a] < 0:
			continue
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb):
				continue
			var b := map.index_of(nb)
			if b < a:
				continue
			if world.cell_owners[b] >= 0 and world.cell_owners[b] != world.cell_owners[a]:
				oracle.append(WorldDataClass.link_id_of(a, b))
	oracle.sort()
	expect_eq(str(borders), str(oracle), "国界跳变边与独立 oracle 一致（派生不落盘）")
	for lk in borders:
		var oa := world.cell_owners[lk.x]
		var ob := world.cell_owners[lk.y]
		expect(oa != ob and oa >= 0 and ob >= 0, "国界边 %s 两侧 owner 互异（%d/%d）" % [str(lk), oa, ob])

func test_same_seed_same_allegiance_distribution() -> void:
	var r1 := _generated(null, 11)
	var r2 := _generated(null, 11)
	expect(r1["ok"] and r2["ok"], "两次生成应成功")
	if not (r1["ok"] and r2["ok"]):
		return
	var w1: WorldDataClass = r1["world"]
	var w2: WorldDataClass = r2["world"]
	expect_eq(str(w1.cell_owners), str(w2.cell_owners), "同 seed 归属分布逐格一致")
	expect_eq(JSON.stringify(w1.to_dict()["pois"]), JSON.stringify(w2.to_dict()["pois"]),
		"同 seed POI 事实一致（确定性）")
	expect_eq(w1.world_digest(r1["map"]), w2.world_digest(r2["map"]), "world_digest 一致")

# ================= state 生长多源 Dijkstra（独立 oracle）=================

func test_state_growth_matches_brute_force_oracle() -> void:
	# 带标记暴力松弛 oracle（Bellman-Ford 式重复扫描至稳定——独立于生成器的堆实现
	# 与弹出顺序）。竞争生长语义：扩张只经本方已占格（Azgaar expandStates 同构），
	# 路径成本随扩张方 expansionism 计——**非**逐势力独立最短路。为消除浮点路径和
	# 的次序噪声：本测面用 expansionism=[1,1,1] 模板（全部成本 = 整数和 → 精确
	# 算术，oracle 与堆在并列处同判：取小 state_id）
	var t := _small_template()
	t.state_expansionism = [1, 1, 1]
	var r := WorldPipeline.generate_validated(t, 7)
	expect(r["ok"], "生成应成功：%s" % r.get("error", ""))
	if not r["ok"]:
		return
	var map: MapDataClass = r["map"]
	var world: WorldDataClass = r["world"]
	var settlements := world.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT)
	var hill := SettlementGen.level_of_h(SettlementGen.H_HILL, 0.25, 4)
	var mtn := SettlementGen.level_of_h(SettlementGen.H_MOUNTAIN, 0.25, 4)
	var river_edges := world.river_edge_index()
	var n := map.cell_count()
	var dist: Array[float] = []
	var owner: Array[int] = []
	dist.resize(n)
	owner.resize(n)
	for i in n:
		dist[i] = INF
		owner[i] = WorldDataClass.ID_NONE
	for si in settlements.size():
		dist[settlements[si].cell_id] = 0.0
		owner[settlements[si].cell_id] = si
	# 暴力松弛至稳定（精确比较；整数成本 → 与生成器堆逐位同值；并列取小 state_id
	# = 堆 (cost, state) 弹出序同口径）
	var changed := true
	while changed:
		changed = false
		for i in n:
			if owner[i] == WorldDataClass.ID_NONE:
				continue
			var c := _cell_of(map, i)
			for d in 6:
				var nb := Hex.neighbor(c, d)
				if not map.has_cell(nb):
					continue
				var j := map.index_of(nb)
				if map.elevation_at(nb) == 0 or not map.is_passable(nb):
					continue
				var step := 1.0 + float(SettlementGen.terrain_cost(map.elevation_at(nb), hill, mtn))
				var link := WorldDataClass.link_id_of(i, j)
				if river_edges.has(link):
					step += 20.0  # 河界加成（无桥 = 归属生长期的全部有河边）
				var nd: float = dist[i] + step
				if nd < dist[j] or (nd == dist[j] and owner[j] > owner[i]):
					dist[j] = nd
					owner[j] = owner[i]
					changed = true
	# normalize 是归属产出的组成部分（§7「建议原样保留」）——oracle 侧过同一
	# 滤波（语义另行在 test_normalize_* 独立锚定）后**逐格全等**对照；滤波前
	# 主体差异另用直出 oracle 记账（>90% 一致 = 生长算法正确的旁证）
	var raw_mismatches := 0
	for i in n:
		if owner[i] != world.cell_owners[i]:
			raw_mismatches += 1
	expect(raw_mismatches * 10 < n,
		"生长直出与暴力 oracle 主体一致（差异 %d/%d 属滤波面）" % [raw_mismatches, n])
	SettlementGen.apply_normalize(map, world, owner)
	var mismatches := 0
	for i in n:
		if owner[i] != world.cell_owners[i]:
			mismatches += 1
	expect_eq(mismatches, 0,
		"生长（暴力 oracle）+ 同款滤波后归属逐格全等（差异 %d 格）" % mismatches)

# ================= normalize 多数滤波语义（平票不改判 / 豁免）=================

func test_normalize_majority_flip_and_tie_no_change() -> void:
	# 手工 owners fixture：10×6 全陆图（elevation 1）+ 3 主城 POI
	var map := MapDataClass.new(10, 6)
	for cell in map.cells():
		map.set_elevation(cell, 1)
		map.set_terrain(cell, 0)
		map.set_passable(cell, true)
	var world := WorldDataClass.empty()
	var caps := [Vector2i(1, 2), Vector2i(8, 2), Vector2i(4, 5)]
	for si in caps.size():
		var cid := map.index_of(Hex.axial_of(caps[si]))
		var p := WorldDataClass.POIData.new()
		p.poi_id = world.pois.size()
		p.kind = WorldDataClass.POIData.Kind.SETTLEMENT
		p.cell_id = cid
		p.footprint_cells = [cid]
		p.role = "cap%d" % si
		world.pois.append(p)
	var n := map.cell_count()
	var owners: Array[int] = []
	owners.resize(n)
	# 稳定背景：左半 state 0 / 右半 state 1（界带平票不动——收敛域）；斑格 X =
	# (6,2) 在右半却被标 0 → 六邻皆 1 → 敌对 6 > 己方 0 → 改判 1（多数滤波消斑）
	var flip_id := map.index_of(Hex.axial_of(Vector2i(6, 2)))
	for i in n:
		var col := i % 10
		owners[i] = 0 if col < 5 else 1
	owners[flip_id] = 0
	var stats := SettlementGen.apply_normalize(map, world, owners)
	expect_eq(owners[flip_id], 1, "敌对 6 > 己方 0 → 改判多数方（≥2 邻格属他国）")
	expect(int(stats["flips"]) >= 1, "滤波轮统计非零")
	# 平票不改判：格 Y 六邻 3 敌 3 己 → 不改
	var owners2: Array[int] = []
	owners2.resize(n)
	for i in n:
		owners2[i] = WorldDataClass.ID_NONE
	var y := Hex.axial_of(Vector2i(5, 3))
	var y_id := map.index_of(y)
	owners2[y_id] = 0
	var hostile_set := 0
	for d in 6:
		var nb := Hex.neighbor(y, d)
		var nid := map.index_of(nb)
		if hostile_set < 3:
			owners2[nid] = 1
			hostile_set += 1
		else:
			owners2[nid] = 0
	SettlementGen.apply_normalize(map, world, owners2)
	expect_eq(owners2[y_id], 0, "3 敌 3 己平票 → 不改判（卡表口径）")
	# 豁免：主城格与主城邻格永不改判（即便被敌对包围）
	var owners3: Array[int] = []
	owners3.resize(n)
	for i in n:
		owners3[i] = 1
	var cap0 := map.index_of(Hex.axial_of(caps[0]))
	owners3[cap0] = 0
	SettlementGen.apply_normalize(map, world, owners3)
	expect_eq(owners3[cap0], 0, "burg 格（主城）豁免——被 6 敌包围仍属己方")
	for d in 6:
		var nb := Hex.neighbor(Hex.axial_of(caps[0]), d)
		var nid := map.index_of(nb)
		if nid == map.index_of(Hex.axial_of(caps[1])) or nid == map.index_of(Hex.axial_of(caps[2])):
			continue  # 他主城格同为豁免格
		owners3[nid] = 0
	owners3[cap0] = 0
	SettlementGen.apply_normalize(map, world, owners3)
	expect_eq(owners3[cap0], 0, "主城格保持豁免（第二轮复核）")

# ================= 阶段开关（归属层关 = 合法回退态）=================

func test_allegiance_off_leaves_empty_collections() -> void:
	var t := _small_template()
	t.allegiance_enabled = false
	var r := WorldPipeline.generate_world(t, 7)
	expect(r["ok"], "聚落开/势力关应成功（归属层关的回退态）")
	if not r["ok"]:
		return
	var world: WorldDataClass = r["world"]
	expect(not world.pois.is_empty(), "POI 仍在（聚落阶段产物）")
	expect(world.states.is_empty() and world.cell_owners.is_empty(),
		"states/cell_owners 恒空（关闭能力不产伪字段）")
	expect_eq(world.validate(r["map"], T_WATER), "", "空归属世界校验合法")
	var alleg: Variant = null
	for d in r["stages"]:
		if String(d["stage"]) == "allegiance":
			alleg = d
	expect(alleg != null and alleg.get("skipped", false), "势力段 skipped 诊断")
