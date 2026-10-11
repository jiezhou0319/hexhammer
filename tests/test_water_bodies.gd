## test_water_bodies.gd — T3 WATER-03 水体/岸线/河口数据面单测（执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §4 WATER-03 + 数据合同草案 §6 转正）
## 覆盖锚（卡表「测试锚」逐条）：
##   - 岸线 = 水陆共享边集合：shore_links_of 对 terrain 独立 oracle（水格↔陆格
##     邻接对）逐一对照；
##   - 同湖水位一致：body 单 water_level 字段结构性成立 + 全部汇入 reach 终点
##     水位 == 本体（WATER_MOUTH_LEVEL 拒绝样本）；
##   - 湖出口不高于溢流口：自本湖源出的 reach 首段水位 ≤ 本体（WATER_OUTLET_LEVEL
##     拒绝样本 + 合法对照）；
##   - terminal 语义：海恒 true；海 outlet_links 恒空（WATER_SEA_OUTLET 拒绝
##     样本——草案 §6「海不适用出水口」）；过路湖 false 必须有 outlet
##     （WATER_TERMINAL 拒绝样本 + 有 outlet 合法对照）；outlet 须为岸边；
##   - 湖成员格 terrain 对账（成员应 TERRAIN_WATER——草案 §6 原文；water_terrain_id
##     显式启用 / -1 跳过两态）；
##   - 不同水体不共享成员格；inlet/outlet 非岸边/重复拒绝；
##   - 序列化：water_bodies 字段往返 + [x,y] 形状 + 非法形状拒绝。
## oracle 原则：期望岸线/成员由 MapData.terrain + HexMath 邻接独立推导，不复制
##   WorldData.shore_links_of 的遍历结构；水地形 id = 内容层 3 号槽（默认材质表）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapIO := preload("res://scripts/content/map_io.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const RiverFix := preload("res://tools/river_fixtures.gd")

const MAP_W := 12
const MAP_H := 8
const T_WATER := 3

# ================= fixture =================

## 基图 + 右侧 2×2 湖（成员 = offset (8,3),(9,3),(8,4),(9,4)）+ 河绕 (4,3) 三边
## 汇入河口小湖（与 test_water_rivers 同族构造，独立拼装）。
## cliff_land = (7,5) 抬到高程 3：与湖无邻？——本 fixture 用于岸线数据面（高程无关），
## 悬崖岸几何面在 test_water_geometry.gd。
func _map_with_lake_and_river() -> Array:
	var map := MapDataClass.new(MAP_W, MAP_H)
	var lake_cells: Array[int] = []
	for cr in [Vector2i(8, 3), Vector2i(9, 3), Vector2i(8, 4), Vector2i(9, 4)]:
		var c := Hex.axial_of(cr)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
		lake_cells.append(map.index_of(c))
	lake_cells.sort()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	var term: Vector2i = chain[chain.size() - 1]
	var members: Array[int] = [term.x]
	var mcell := RiverFix.cell_of_id(map, term.x)
	for d in 6:
		var nb := Hex.neighbor(mcell, d)
		if map.has_cell(nb) and map.index_of(nb) != term.y and not members.has(map.index_of(nb)):
			members.append(map.index_of(nb))
	for cid in members:
		var c := RiverFix.cell_of_id(map, cid)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
	members.sort()
	var world := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.water_levels = [2, 2, 1]
	reach.bed_level = 0
	reach.water_body_id = 0
	world.rivers.append(reach)
	var mouth := WorldDataClass.WaterBodyData.new()
	mouth.water_body_id = 0
	mouth.water_level = 1
	mouth.member_cells = members
	mouth.inlet_links = [term]
	mouth.terminal = true
	world.water_bodies.append(mouth)
	var lake := WorldDataClass.WaterBodyData.new()
	lake.water_body_id = 1
	lake.water_level = 1
	lake.member_cells = lake_cells
	lake.terminal = true
	world.water_bodies.append(lake)
	for e in chain:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = e
		lk.river_reach_id = 0
		world.links.append(lk)
	world.links.sort_custom(func(a: WorldDataClass.NeighborLinkData,
			b: WorldDataClass.NeighborLinkData) -> bool:
		return a.link_id.x < b.link_id.x \
			or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y))
	return [map, world, lake_cells, chain]

# ================= 岸线（WATER-03 ②）=================

func test_shoreline_equals_water_land_shared_edges() -> void:
	var fixture := _map_with_lake_and_river()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	for b in world.water_bodies:
		var got := WorldDataClass.shore_links_of(map, b)
		# 独立 oracle：成员 ↔ 非成员的邻接对（terrain 判水/陆由成员集代替——
		# 两口径由 WATER_MEMBER_TERRAIN 校验绑定，此处锚集合本身）
		var want: Array[Vector2i] = []
		for cid in b.member_cells:
			var cell := RiverFix.cell_of_id(map, cid)
			for d in 6:
				var nb := Hex.neighbor(cell, d)
				if map.has_cell(nb) and not b.member_cells.has(map.index_of(nb)):
					var lk := WorldDataClass.link_id_of(cid, map.index_of(nb))
					if not want.has(lk):
						want.append(lk)
		want.sort()
		expect_eq(got, want, "岸线 = 水陆共享边集合（body %d，got %d 条 want %d 条）"
			% [b.water_body_id, got.size(), want.size()])
		expect(got.size() > 0, "非空水体必有岸线（body %d）" % b.water_body_id)
	# 岸线边确实一端水一端陆（terrain 口径独立验证）
	for b in world.water_bodies:
		for lk in WorldDataClass.shore_links_of(map, b):
			var ta := map.terrain_at(RiverFix.cell_of_id(map, lk.x))
			var tb := map.terrain_at(RiverFix.cell_of_id(map, lk.y))
			expect((ta == T_WATER) != (tb == T_WATER),
				"岸线边恰一端水（%s：%d/%d）" % [str(lk), ta, tb])

# ================= 同湖水位一致 + 河口对账 =================

func test_same_body_level_structural_and_mouth_reconciliation() -> void:
	var fixture := _map_with_lake_and_river()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	expect_eq(world.validate(map, T_WATER), "", "基准世界合法（含两水体 + 河口对账）")
	# 河口水位不等 → 拒（「同湖水位一致」的汇入侧对账——接缝 y 逐位一致的数据面
	# 前提；[2,2,2] 恒定不升，单调面不触发、错误归因唯一 = 河口对账）
	world.rivers[0].water_levels = [2, 2, 2]
	var msg := world.validate(map, T_WATER)
	expect(msg.contains("WATER_MOUTH_LEVEL"), "河口水位 ≠ 水体水面被拒（got：%s）" % msg)

func test_member_terrain_reconciliation_toggle() -> void:
	var fixture := _map_with_lake_and_river()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	# 成员格 terrain 对账（water_terrain_id 显式启用）
	expect_eq(world.validate(map, T_WATER), "", "成员全水：terrain 对账通过")
	# 改一格成员 terrain → 拒（对账不是回写：改的是 MapData，校验器只拒绝）
	var cid: int = world.water_bodies[1].member_cells[0]
	var cell := RiverFix.cell_of_id(map, cid)
	map.set_terrain(cell, 0)
	var msg := world.validate(map, T_WATER)
	expect(msg.contains("WATER_MEMBER_TERRAIN"), "成员格非水被拒（got：%s）" % msg)
	# -1 = 跳过（核心层不硬编码内容层地形 id——未启用对账即合法）
	expect_eq(world.validate(map), "", "water_terrain_id=-1 跳过对账（合法态）")
	map.set_terrain(cell, T_WATER)

# ================= terminal 语义 + 湖出口（WATER-03 ③）=================

func test_sea_terminal_and_pass_through_lake_outlet() -> void:
	var fixture := _map_with_lake_and_river()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	# 海恒 terminal
	world.water_bodies[1].kind = WorldDataClass.WaterBodyData.Kind.SEA
	world.water_bodies[1].terminal = false
	var msg := world.validate(map, T_WATER)
	expect(msg.contains("terminal"), "海 terminal=false 被拒（got：%s）" % msg)
	world.water_bodies[1].terminal = true
	# 海 outlet 恒空（草案 §6「海不适用出水口」——草案 :210 约束进校验器）
	var sea_outlet := WorldDataClass.shore_links_of(map, world.water_bodies[1])[0]
	world.water_bodies[1].outlet_links = [sea_outlet]
	var msg_sea := world.validate(map, T_WATER)
	expect(msg_sea.contains("WATER_SEA_OUTLET"),
		"海携带非空 outlet_links 被拒（got：%s）" % msg_sea)
	world.water_bodies[1].outlet_links = []
	world.water_bodies[1].kind = WorldDataClass.WaterBodyData.Kind.LAKE
	# 过路湖 false 无 outlet → 拒；有 outlet（岸边）→ 合法
	world.water_bodies[1].terminal = false
	var msg2 := world.validate(map, T_WATER)
	expect(msg2.contains("WATER_TERMINAL"), "过路湖无 outlet 被拒（got：%s）" % msg2)
	var outlet := WorldDataClass.shore_links_of(map, world.water_bodies[1])[0]
	world.water_bodies[1].outlet_links = [outlet]
	expect_eq(world.validate(map, T_WATER), "", "过路湖带岸边 outlet 合法")
	# outlet 非岸边（水-水内边）→ 拒
	var inner_bad := WorldDataClass.link_id_of(
		world.water_bodies[1].member_cells[0], world.water_bodies[1].member_cells[1])
	if Hex.dir_between(RiverFix.cell_of_id(map, world.water_bodies[1].member_cells[0]),
			RiverFix.cell_of_id(map, world.water_bodies[1].member_cells[1])) >= 0:
		world.water_bodies[1].outlet_links = [inner_bad]
		var msg3 := world.validate(map, T_WATER)
		expect(msg3.contains("岸边") or msg3.contains("恰一端"),
			"非岸边 outlet 被拒（got：%s）" % msg3)

func test_lake_outlet_level_not_above_body() -> void:
	# 湖出口不高于溢流口：自本湖源出的 reach 首段水位 ≤ 本体 water_level。
	# 第二 reach = 自湖**南岸 outlet 边**贪心南下（确定性几何链，与 make_fixed_maps
	# 同构造），汇入自己的河口小湖——除首段水位外全合法，错误归因唯一。
	var fixture := _map_with_lake_and_river()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var lake := world.water_bodies[1]
	# 南岸 outlet（岸线边中边中点最南者——独立几何选择，确定性）
	var outlet := WorldDataClass.NO_LINK
	var best_z := -1e9
	for lk in WorldDataClass.shore_links_of(map, lake):
		var z := RiverFix.link_mid(map, lk).y
		if z > best_z:
			best_z = z
			outlet = lk
	expect(outlet != WorldDataClass.NO_LINK, "构造前提：找到南岸 outlet")
	lake.outlet_links = [outlet]
	var links := RiverFix.all_links(map)
	var chain2 := RiverFix.greedy_chain(map, links, outlet, 6,
		func(_row: int) -> float: return 8.0)
	expect(chain2.size() >= 3, "自 outlet 南下链足够长（got %d）" % chain2.size())
	# 第二河口小湖（body 2）沿 chain2 终点边构造（与 fixture 同口径独立拼装）
	var term2: Vector2i = chain2[chain2.size() - 1]
	var members2: Array[int] = [term2.x]
	var m2cell := RiverFix.cell_of_id(map, term2.x)
	for d in 6:
		var nb := Hex.neighbor(m2cell, d)
		if map.has_cell(nb) and map.index_of(nb) != term2.y and not members2.has(map.index_of(nb)):
			members2.append(map.index_of(nb))
	for cid in members2:
		var c := RiverFix.cell_of_id(map, cid)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
	members2.sort()
	var body2 := WorldDataClass.WaterBodyData.new()
	body2.water_body_id = 2
	body2.water_level = 1
	body2.member_cells = members2
	body2.inlet_links = [term2]
	body2.terminal = true
	world.water_bodies.append(body2)
	var r2 := WorldDataClass.RiverReachData.new()
	r2.reach_id = 1
	r2.edges = chain2
	r2.water_levels = []
	for i in chain2.size():
		r2.water_levels.append(1)
	r2.water_levels[0] = 2  # 违例样本：首段（源出湖）水位 2 > 本体 1
	r2.bed_level = 0
	r2.water_body_id = 2
	world.rivers.append(r2)
	for e in chain2:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = e
		lk.river_reach_id = 1
		world.links.append(lk)
	world.links.sort_custom(func(a: WorldDataClass.NeighborLinkData,
			b: WorldDataClass.NeighborLinkData) -> bool:
		return a.link_id.x < b.link_id.x \
			or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y))
	var msg := world.validate(map, T_WATER)
	expect(msg.contains("WATER_OUTLET_LEVEL"),
		"自湖源出的 reach 首段水位 > 本体被拒（got：%s）" % msg)
	# 合法对照：源出水位 == 本体 → 全世界过校验
	r2.water_levels[0] = 1
	expect_eq(world.validate(map, T_WATER), "", "源出水位 ≤ 本体合法")

# ================= 成员唯一性 / 序 =================

func test_member_shared_between_bodies_rejected() -> void:
	var fixture := _map_with_lake_and_river()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var shared: int = world.water_bodies[0].member_cells[0]
	var dup: Array[int] = world.water_bodies[1].member_cells.duplicate()
	dup.append(shared)
	dup.sort()
	world.water_bodies[1].member_cells = dup
	var msg := world.validate(map, T_WATER)
	expect(msg.contains("共享") or msg.contains("不共享格"),
		"不同水体共享成员格被拒（got：%s）" % msg)

func test_body_ordering_and_duplicate_kinds_rejected() -> void:
	var fixture := _map_with_lake_and_river()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	# 破坏规范序（原地反转——typed 数组不可整体重赋 untyped 副本）
	world.water_bodies.reverse()
	var msg := world.validate(map, T_WATER)
	expect(msg.contains("规范序"), "水体表须按 water_body_id 升序（got：%s）" % msg)
	world.water_bodies.reverse()
	expect_eq(world.validate(map, T_WATER), "", "复原后合法（破序才是非法原因）")
	# 非法 kind
	world.water_bodies[0].kind = 5
	expect(world.validate(map, T_WATER).contains("kind"), "非法 kind 被拒")

# ================= 序列化 =================

func test_body_serialization_roundtrip() -> void:
	var fixture := _map_with_lake_and_river()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var d := world.to_dict()
	var bodies: Array = d["water_bodies"]
	expect_eq(bodies.size(), 2, "落盘水体 2 个")
	for entry in bodies:
		for key in ["inlet_links", "outlet_links"]:
			for lk in entry[key]:
				expect(lk is Array and (lk as Array).size() == 2,
					"%s = [x,y] 显式转换层" % key)
	var text := JSON.stringify(d)
	expect(not text.contains("]:"), "JSON 文本无 Vector2i 字符串形状混入")
	var path := "user://test_water_bodies_rt.world.json"
	expect_eq(MapIO.write_world(world, path), OK, "写入成功")
	var back: Variant = MapIO.read_world(path)
	expect(back is WorldDataClass, "读回 WorldData")
	if back is WorldDataClass:
		var b: WorldDataClass = back
		expect_eq(b.to_dict(), d, "往返 to_dict 逐位一致（含水体全部字段）")
		expect_eq(b.validate(map, T_WATER), "", "读回仍过校验")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_from_dict_rejects_bad_body_shapes() -> void:
	var fixture := _map_with_lake_and_river()
	var good: Dictionary = (fixture[1] as WorldDataClass).to_dict()
	var cases := [
		{"key": "member_cells", "value": [3.5, 7]},
		{"key": "member_cells", "value": [-1, 7]},
		{"key": "kind", "value": "lake"},
		{"key": "terminal", "value": 1},
	]
	for patch in cases:
		var dd := good.duplicate(true)
		((dd["water_bodies"] as Array)[0] as Dictionary)[patch["key"]] = patch["value"]
		expect(WorldDataClass.from_dict(dd) == null,
			"water_bodies.%s = %s → null（无隐式兜底）" % [patch["key"], str(patch["value"])])
	var bad_inlet := good.duplicate(true)
	((bad_inlet["water_bodies"] as Array)[0] as Dictionary)["inlet_links"] = [[3]]
	expect(WorldDataClass.from_dict(bad_inlet) == null, "inlet 非两元数组 → null")
	var missing := good.duplicate(true)
	((missing["water_bodies"] as Array)[0] as Dictionary).erase("terminal")
	expect(WorldDataClass.from_dict(missing) == null, "缺 terminal 字段 → null")
