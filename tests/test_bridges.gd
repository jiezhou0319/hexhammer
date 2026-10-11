## test_bridges.gd — T4 ROAD-02 横切河道的桥单测（执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §5 ROAD-02 + §2.3 格边重写表 +
##   §2.4 连带对账；拍板⑤ 认领语义正典）
## 覆盖锚（卡表「测试锚」逐条）：
##   - 桥端合法锚点：bank_a/bank_b == river_edge 两端格断言；
##   - 横切判定两用例：合法横切过校验 / 禁渡拒绝（RIVER_FORD_FORBIDDEN 与
##     BRIDGE_ENDPOINT_INVALID 分开报）；
##   - 「同 link 河和路不得无认领共存」校验器用例（§2.3 反转的机器面）；
##   - traversable 查询 = CrossingData 认领表（crossing_index，跨河可达唯一入口）；
##   - Kind.FERRY 拒绝开启；桥头 Δ 超配置 / 净空不足 → BRIDGE_ENDPOINT_INVALID；
##     急弯判据（edge[k] 与 edge[k+2] 不平行，含首尾索引边界，拍板⑩）；
##   - 序列化往返 + river_edge 显式 [x,y]。
## oracle 原则：急弯平行性由 RiverFixtures.link_corners 世界坐标独立判定（几何
##   oracle——构造用几何、校验用切向点积，两路互证）；河 fixture 沿
##   tools/river_fixtures.gd 先例，不复制 WorldData 内部判定。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapIO := preload("res://scripts/content/map_io.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const RiverFix := preload("res://tools/river_fixtures.gd")

const MAP_W := 12
const MAP_H := 8
const T_WATER := 3

# ================= fixture 构造（沿 test_water_rivers.gd 先例）=================

func _base_map() -> MapDataClass:
	return MapDataClass.new(MAP_W, MAP_H)


## 河口（终点边）成员侧水体涂格 + 标准样本世界（单河 + 河口湖 + link 引用面）。
## 返回 {"map": 涂写后的 map, "world": WorldData, "chain": Array[Vector2i]}。
func _river_world(paint_mouth := true) -> Dictionary:
	var map := _base_map()
	for cell in map.cells():
		map.set_elevation(cell, 1)  # 陆地基高程 1（默认 0 会让一切桥撞净空检查）
	var links := RiverFix.all_links(map)
	var start := WorldDataClass.link_id_of(
		map.index_of(Hex.axial_of(Vector2i(5, 1))), map.index_of(Hex.axial_of(Vector2i(6, 1))))
	var chain := RiverFix.greedy_chain(map, links, start, 10,
		func(_row: int) -> float: return 5.5)
	var w := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.water_levels = []
	for i in chain.size():
		reach.water_levels.append(1)
	reach.bed_level = 0
	reach.water_body_id = 0
	w.rivers.append(reach)
	if paint_mouth:
		var term: Vector2i = chain[chain.size() - 1]
		var members: Array[int] = [term.x]
		var mcell := RiverFix.cell_of_id(map, term.x)
		for d in 6:
			var nb := Hex.neighbor(mcell, d)
			if map.has_cell(nb) and map.index_of(nb) != term.y \
					and not members.has(map.index_of(nb)):
				members.append(map.index_of(nb))
		for cid in members:
			var c := RiverFix.cell_of_id(map, cid)
			map.set_elevation(c, 0)
			map.set_terrain(c, T_WATER)
			map.set_passable(c, false)
		members.sort()
		var body := WorldDataClass.WaterBodyData.new()
		body.water_body_id = 0
		body.water_level = 1
		body.member_cells = members
		body.inlet_links = [term]
		body.terminal = true
		w.water_bodies.append(body)
	for e in chain:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = e
		lk.river_reach_id = 0
		w.links.append(lk)
	w.links.sort_custom(func(a: WorldDataClass.NeighborLinkData,
			b: WorldDataClass.NeighborLinkData) -> bool:
		return a.link_id.x < b.link_id.x or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y))
	return {"map": map, "world": w, "chain": chain}


## 桥边索引：取河链**早段**第 2 条边（非源边 0；远离终点侧河口湖涂格——
## 湖成员被涂高程 0，桥在其上会先撞净空/高差检查、错归因）。链长不足时钳到
## 倒数第二条（终点边除外）。
func _safe_bridge_index(chain: Array[Vector2i]) -> int:
	return clampi(2, 1, chain.size() - 2)


## 在河的第 k 条边上建跨河桥 + 跨接该边的路（两岸都有路的最小机器表达：
## a、b 互为邻居（河边定义），2 格路 [a, b] 即跨接）。bank_delta ≠ 0 时抬 a 侧
## 高程造两岸高差样本。修改 world（加 road/crossing/link 投影）；返回
## {"crossing": CrossingData, "link": Vector2i}。
func _add_bridge_with_road(fix: Dictionary, k: int, bank_delta := 0) -> Dictionary:
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	var chain: Array[Vector2i] = fix["chain"]
	var link: Vector2i = chain[k]
	if bank_delta != 0:
		map.set_elevation(RiverFix.cell_of_id(map, link.x), 1 + bank_delta)
	var road := WorldDataClass.RoadData.new()
	road.road_id = 0
	road.cells = [link.x, link.y]
	w.roads.append(road)
	var crossing := WorldDataClass.CrossingData.new()
	crossing.crossing_id = 0
	crossing.kind = WorldDataClass.CrossingData.Kind.BRIDGE
	crossing.river_edge = link
	crossing.bank_a = link.x
	crossing.bank_b = link.y
	w.crossings.append(crossing)
	for lk in w.links:
		if lk.link_id == link:
			lk.road_id = 0  # 跨河边同 link 河和路共存（被认领 = 合法态，§2.3 反转）
	return {"crossing": crossing, "link": link}

# ================= 桥端锚点 / 认领表 / kind =================

func test_crossing_contract_and_claim_table() -> void:
	var fix := _river_world()
	# 取河中段一条边（非源/终点）建桥
	var chain: Array[Vector2i] = fix["chain"]
	var k := _safe_bridge_index(chain)
	var added := _add_bridge_with_road(fix, k)
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	expect_eq(w.validate(map, T_WATER), "", "合法横切（路跨河 + crossing 认领）过全量校验")
	var c: WorldDataClass.CrossingData = added["crossing"]
	# 桥端合法锚点：bank == river_edge 两端格（卡表断言原文）
	expect(c.bank_a == c.river_edge.x and c.bank_b == c.river_edge.y,
		"bank_a/bank_b == river_edge 两端格")
	var link: Vector2i = added["link"]
	# traversable 查询 = 认领表（跨河可达唯一入口）：认领边恰一、其余有河边不在表
	var claims := w.crossing_index()
	expect(claims.has(link) and (claims[link] as WorldDataClass.CrossingData).crossing_id == 0,
		"认领表含跨河边 → traversable（桥 = 跨河可达唯一查询入口）")
	for e in chain:
		if e != link:
			expect(not claims.has(e), "非认领有河边不在认领表（无桥 = 不可渡）")
	# 同 link 河和路共存（§2.3 反转）：该 link 条目同时有河与路且被认领 = 合法态
	for lk in w.links:
		if lk.link_id == link:
			expect(lk.river_reach_id == 0 and lk.road_id == 0,
				"跨河边同 link 河和路共存且被认领（合法态——草案 §4 禁令的格边反转）")

func test_ford_refused_separately_from_endpoint_invalid() -> void:
	# 横切判定两用例 + 分开报：未认领跨接 = RIVER_FORD_FORBIDDEN（禁渡）；
	# 桥头 Δ 超配置 = BRIDGE_ENDPOINT_INVALID——两错误码互不混淆
	var fix := _river_world()
	var chain: Array[Vector2i] = fix["chain"]
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	# ① 禁渡：只建路（跨河）不建桥
	var k := _safe_bridge_index(chain)
	var link := chain[k]
	var a := RiverFix.cell_of_id(map, link.x)
	var b := RiverFix.cell_of_id(map, link.y)
	var road := WorldDataClass.RoadData.new()
	road.road_id = 0
	road.cells = [map.index_of(a), map.index_of(b)]
	w.roads.append(road)
	for lk in w.links:
		if lk.link_id == link:
			lk.road_id = 0
	var msg := w.validate(map, T_WATER)
	expect(msg.contains("RIVER_FORD_FORBIDDEN"), "未认领跨接被拒（禁渡，got：%s）" % msg)
	expect(not msg.contains("BRIDGE_ENDPOINT_INVALID"), "禁渡拒绝 ≠ 桥端错误（分开报锚）")
	# ② 桥端：合法认领 + 两岸 Δ3、配置 1 → BRIDGE_ENDPOINT_INVALID
	var fix2 := _river_world()
	var added := _add_bridge_with_road(fix2, _safe_bridge_index(fix2["chain"]), 3)
	var map2: MapDataClass = fix2["map"]
	var w2: WorldDataClass = fix2["world"]
	var msg2 := w2.validate(map2, T_WATER, -1, 1)
	expect(msg2.contains("BRIDGE_ENDPOINT_INVALID"), "桥头 Δ3 > 配置 1 被拒（got：%s）" % msg2)
	expect(not msg2.contains("RIVER_FORD_FORBIDDEN"), "桥端错误 ≠ 禁渡（分开报锚）")
	expect_eq(w2.validate(map2, T_WATER, -1, 3), "", "配置 3 时 Δ3 桥合法（接坡档）")
	expect(added["crossing"].crossing_id == 0, "桥构造前提保持")

func test_crossing_rejects_structural_violations() -> void:
	# ① 两岸格 ≠ river_edge 两端格 → BRIDGE_ENDPOINT_INVALID（桥端锚点断言的拒绝面）
	var fix := _river_world()
	var added := _add_bridge_with_road(fix, _safe_bridge_index(fix["chain"]))
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	var wrong := WorldDataClass.CrossingData.new()
	wrong.crossing_id = 1
	wrong.kind = WorldDataClass.CrossingData.Kind.BRIDGE
	wrong.river_edge = (added["link"] as Vector2i)
	wrong.bank_a = (added["link"] as Vector2i).x
	wrong.bank_b = (added["link"] as Vector2i).x  # ≠ y（同格两岸）
	w.crossings.append(wrong)
	expect(w.validate(map, T_WATER).contains("BRIDGE_ENDPOINT_INVALID"),
		"两岸格 ≠ link 两端格被拒（桥端锚点）")
	w.crossings.remove_at(w.crossings.size() - 1)
	# ② river_edge 无河（有河才有桥）
	var map2 := _base_map()
	var w2 := WorldDataClass.empty()
	var x := Hex.axial_of(Vector2i(4, 3))
	var y := Hex.neighbor(x, 0)
	var road := WorldDataClass.RoadData.new()
	road.road_id = 0
	road.cells = [map2.index_of(x), map2.index_of(y)]
	w2.roads.append(road)
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(road.cells[0], road.cells[1])
	lk.road_id = 0
	w2.links.append(lk)
	var no_river := WorldDataClass.CrossingData.new()
	no_river.crossing_id = 0
	no_river.river_edge = lk.link_id
	no_river.bank_a = lk.link_id.x
	no_river.bank_b = lk.link_id.y
	w2.crossings.append(no_river)
	expect(w2.validate(map2).contains("CROSSING_NO_RIVER"), "无河边的桥被拒（有河才有桥）")
	# ③ 桥无路跨接（两岸都有路）
	var fix3 := _river_world()
	var w3: WorldDataClass = fix3["world"]
	var map3: MapDataClass = fix3["map"]
	var chain3: Array[Vector2i] = fix3["chain"]
	var orphan := WorldDataClass.CrossingData.new()
	orphan.crossing_id = 0
	orphan.river_edge = chain3[_safe_bridge_index(chain3)]
	orphan.bank_a = orphan.river_edge.x
	orphan.bank_b = orphan.river_edge.y
	w3.crossings.append(orphan)
	expect(w3.validate(map3, T_WATER).contains("CROSSING_NO_ROAD"),
		"桥无路跨接被拒（两岸都有路才设桥）")
	# ④ 一 link 至多一 crossing
	var fix4 := _river_world()
	var added4 := _add_bridge_with_road(fix4, _safe_bridge_index(fix4["chain"]))
	var w4: WorldDataClass = fix4["world"]
	var dup := WorldDataClass.CrossingData.new()
	dup.crossing_id = 1
	dup.river_edge = added4["link"]
	dup.bank_a = dup.river_edge.x
	dup.bank_b = dup.river_edge.y
	w4.crossings.append(dup)
	expect(w4.validate(fix4["map"], T_WATER).contains("CROSSING_DUP"),
		"一 link 至多一 crossing（方向所有权去重的格边版——结构性约束）")

func test_ferry_refused_and_clearance() -> void:
	# Kind.FERRY 枚举存在但拒绝开启：validate 拒 + from_dict 形状层拒（双拒绝）
	var fix := _river_world()
	var added := _add_bridge_with_road(fix, _safe_bridge_index(fix["chain"]))
	var w: WorldDataClass = fix["world"]
	var map: MapDataClass = fix["map"]
	expect(w.crossings[0].kind == WorldDataClass.CrossingData.Kind.BRIDGE, "构造前提：BRIDGE")
	w.crossings[0].kind = WorldDataClass.CrossingData.Kind.FERRY
	var msg := w.validate(map, T_WATER)
	expect(msg.contains("CROSSING_FERRY"), "Kind.FERRY 被拒（枚举存在 ≠ 能力开放，got：%s）" % msg)
	# from_dict 侧：kind=FERRY → null
	var d := WorldDataClass.empty().to_dict()
	d["crossings"] = [{"crossing_id": 0,
		"kind": WorldDataClass.CrossingData.Kind.FERRY,
		"river_edge": [(added["link"] as Vector2i).x, (added["link"] as Vector2i).y],
		"bank_a": 1, "bank_b": 2}]
	expect(WorldDataClass.from_dict(d) == null, "kind=FERRY 落盘形状 → null（双拒绝）")
	# 净空：两岸高程 0 < 河水位 1 → 桥面将不高于水面（BRIDGE_ENDPOINT_INVALID）
	w.crossings[0].kind = WorldDataClass.CrossingData.Kind.BRIDGE
	var a_cell := RiverFix.cell_of_id(map, (added["link"] as Vector2i).x)
	var b_cell := RiverFix.cell_of_id(map, (added["link"] as Vector2i).y)
	map.set_elevation(a_cell, 0)
	map.set_elevation(b_cell, 0)
	var clearance := w.validate(map, T_WATER)
	expect(clearance.contains("BRIDGE_ENDPOINT_INVALID") and clearance.contains("净空"),
		"两岸低于河水位被拒（净空不足，got：%s）" % clearance)

# ================= 急弯判据（拍板⑩走向几何版 + 首尾索引边界）=================

## 几何 oracle：两条边的方向向量（link_corners 世界坐标差）是否平行（|cross|≈0）。
func _edges_parallel(map: MapDataClass, l1: Vector2i, l2: Vector2i) -> bool:
	var d1 := _edge_vec(map, l1)
	var d2 := _edge_vec(map, l2)
	return absf(d1.cross(d2)) < 1e-6

func _edge_vec(map: MapDataClass, link: Vector2i) -> Vector2:
	var cs := RiverFix.link_corners(map, link)
	return cs[1] - cs[0]

func test_sharp_bend_predicate_and_boundaries() -> void:
	# 走廊样（贪心南向走）：edge[k] ∥ edge[k+2] 占绝对多数 → 非急弯；
	# 弯样（绕格三条边）：三边两两不平行 → 全部急弯；
	# 首尾索引边界：k<0 或 k+2 越界 → 恒非急弯（判据含边界，序列首尾勿漏）
	var map := _base_map()
	var links := RiverFix.all_links(map)
	var start := WorldDataClass.link_id_of(
		map.index_of(Hex.axial_of(Vector2i(5, 1))), map.index_of(Hex.axial_of(Vector2i(6, 1))))
	var corridor := RiverFix.greedy_chain(map, links, start, 10,
		func(_row: int) -> float: return 5.5)
	var reach := WorldDataClass.RiverReachData.new()
	reach.edges = corridor
	var sharp_count := 0
	for k in corridor.size() - 2:
		var got := WorldDataClass.river_bend_is_sharp(map, reach, k)
		var want := not _edges_parallel(map, corridor[k], corridor[k + 2])
		expect_eq(got, want, "急弯判据与几何 oracle 一致（走廊 k=%d）" % k)
		if want:
			sharp_count += 1
	expect(sharp_count <= corridor.size() / 2,
		"走廊样急弯占少数（got %d/%d）" % [sharp_count, corridor.size() - 2])
	# 边界：越界索引恒非急弯
	expect(not WorldDataClass.river_bend_is_sharp(map, reach, -1), "k=-1 → 非急弯（首边界）")
	expect(not WorldDataClass.river_bend_is_sharp(map, reach, corridor.size() - 2),
		"k+2 越界 → 非急弯（尾边界）")
	expect(not WorldDataClass.river_bend_is_sharp(map, reach, corridor.size() - 1),
		"k = 末边 → 非急弯（尾边界）")
	# 弯样：绕格三条边两两不平行（六边形三边切向互差 60°/120°）→ k=0 急弯
	var x := Hex.axial_of(Vector2i(4, 3))
	var bend := RiverFix.around_cell_chain(map, x, 3)
	var reach2 := WorldDataClass.RiverReachData.new()
	reach2.edges = bend
	expect(not _edges_parallel(map, bend[0], bend[2]), "构造前提：弯样首尾边不平行")
	expect(WorldDataClass.river_bend_is_sharp(map, reach2, 0), "弯样 k=0 急弯（不平行）")
	expect(not WorldDataClass.river_bend_is_sharp(map, reach2, 1), "弯样 k=1 尾边界（k+2 越界）→ 非急弯")

# ================= 序列化（river_edge 显式 [x,y] + 往返）=================

func test_crossing_serialization_roundtrip() -> void:
	var fix := _river_world()
	var added := _add_bridge_with_road(fix, _safe_bridge_index(fix["chain"]))
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	var d := w.to_dict()
	var entry: Dictionary = (d["crossings"] as Array)[0]
	expect(entry["river_edge"] is Array and (entry["river_edge"] as Array).size() == 2,
		"river_edge 落盘 = [x, y] 两元数组（显式转换层）")
	var text := JSON.stringify(d)
	expect(not text.contains("(324, 325)"), "JSON 文本不含 Vector2i 字符串形状")
	var path := "user://test_bridges_rt.world.json"
	expect_eq(MapIO.write_world(w, path), OK, "世界伴生文件写入成功")
	var back: Variant = MapIO.read_world(path)
	expect(back is WorldDataClass, "读回 WorldData")
	if back is WorldDataClass:
		var b: WorldDataClass = back
		expect_eq(b.to_dict(), w.to_dict(), "往返 to_dict 逐位一致")
		expect_eq(b.crossings[0].river_edge, added["link"], "river_edge 重建一致")
		expect_eq(b.validate(map, T_WATER), "", "读回世界仍过校验（保存→重载同验）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# river_edge 形状非法 → from_dict null
	var bad := w.to_dict()
	((bad["crossings"] as Array)[0] as Dictionary)["river_edge"] = [5]
	expect(WorldDataClass.from_dict(bad) == null, "river_edge [5] 单元 → null（无隐式兜底）")
