## test_water_rivers.gd — T3 WATER-01 单河数据与校验器单测（执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §4 WATER-01 + §2.2 重写表 +
##   数据合同草案 §5（已按 ADR-14 转正））
## 覆盖锚（卡表「测试锚」逐条）：
##   - 单河 fixture 枚举（具体形状、不命名转向，拍板⑩）：走廊样（连续两步走向
##     相反 = edge[k] 与 edge[k+2] 平行，贪心南向走产出）/ 弯样（绕格边界三条边）/
##     源（单端点边 = 单边链）/ 终点（汇入水体边 = 河口边）各一；
##   - 拒绝锚：上坡（单调违例）/ 角点级环（**六条不同边绕同一格闭合成环——
##     两条不同边经同一角点二次成环**，修订记录三之 4）/ 非法邻格（link 两端
##     非邻居）/ 断链 / bed ≥ water / 边跨 reach 复用；
##   - 终点对账：终点边 ∈ 声明水体 inlet_links（双向）+ 河口边岸边口径 +
##     河口水位相等 + link↔reach 双向对账；
##   - 序列化往返 + Vector2i [x,y] + 缺 .world.json → empty()（旧图零迁移）；
##   - 固定图（resources/maps/fixed）数据化面：世界文件可加载、可校验。
## oracle 原则：链的连续性/共角点由世界坐标 vertex_xz 几何判定（tools/river_fixtures.gd
##   独立于 WorldData.corner_id_of——构造用几何、校验用 ID，两路互证）；
##   期望邻接由 MapData/HexMath 原语独立推导，不复制 WorldData 内部比较器。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapIO := preload("res://scripts/content/map_io.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const RiverFix := preload("res://tools/river_fixtures.gd")

const MAP_W := 12
const MAP_H := 8
const T_GRASS := 0
const T_WATER := 3

# ================= fixture 构造（几何 oracle 驱动）=================

## 测试基图：全草/高程 1/可通行（河在边上——两侧格保持陆地，ADR-14）
func _base_map() -> MapDataClass:
	return MapDataClass.new(MAP_W, MAP_H)

## 河口（终点边）成员侧格 + 邻格 − 对岸格（对 make_fixed_maps 同款口径的测试侧
## 独立实现）；**涂格**：成员 → 水/高程 0/不可通行（格语义水体）。
## 返回 {"members": Array[int](升序), "bank": int}。
func _paint_mouth_body(map: MapDataClass, term: Vector2i) -> Dictionary:
	var member := term.x
	var bank := term.y
	var members: Array[int] = [member]
	var mcell := RiverFix.cell_of_id(map, member)
	for d in 6:
		var nb := Hex.neighbor(mcell, d)
		if map.has_cell(nb) and map.index_of(nb) != bank:
			var id := map.index_of(nb)
			if not members.has(id):
				members.append(id)
	for cid in members:
		var c := RiverFix.cell_of_id(map, cid)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
	members.sort()
	return {"members": members, "bank": bank}

## 标准样本世界：chain 边序列 + 河口湖（body 0）+ link 引用面。
## levels 逐段 profile（单调不升、终点 = 河口湖水位）。
func _world_for_chain(map: MapDataClass, chain: Array[Vector2i],
		levels: Array[int], bed := 0) -> WorldDataClass:
	var mouth := _paint_mouth_body(map, chain[chain.size() - 1])
	var world := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain.duplicate()
	reach.water_levels = levels.duplicate()
	reach.bed_level = bed
	reach.water_body_id = 0
	world.rivers.append(reach)
	var body := WorldDataClass.WaterBodyData.new()
	body.water_body_id = 0
	body.kind = WorldDataClass.WaterBodyData.Kind.LAKE
	body.water_level = levels[levels.size() - 1]
	body.member_cells = mouth["members"]
	body.inlet_links = [chain[chain.size() - 1]]
	body.terminal = true
	world.water_bodies.append(body)
	for e in chain:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = e
		lk.river_reach_id = 0
		world.links.append(lk)
	world.links.sort_custom(_link_order)
	return world

func _link_order(a: WorldDataClass.NeighborLinkData,
		b: WorldDataClass.NeighborLinkData) -> bool:
	return a.link_id.x < b.link_id.x \
		or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y)

# ================= fixture 形状枚举（拍板⑩：具体边序列、不命名转向）=================

func test_corridor_shape_edges_k_and_k2_parallel() -> void:
	# 长走廊样：贪心南向走——连续两步走向相反 ⇔ edge[k] 与 edge[k+2] 平行
	#（方向向量由两端角点差独立算出，cross ≈ 0 判平行——几何 oracle）
	var map := _base_map()
	var links := RiverFix.all_links(map)
	var start := WorldDataClass.link_id_of(
		map.index_of(Hex.axial_of(Vector2i(5, 1))), map.index_of(Hex.axial_of(Vector2i(6, 1))))
	var chain := RiverFix.greedy_chain(map, links, start, 10,
		func(_row: int) -> float: return 5.5)
	expect(chain.size() >= 6, "贪心南向走应产出走廊（got %d 边）" % chain.size())
	for i in chain.size() - 1:
		expect(RiverFix.links_share_corner(map, chain[i], chain[i + 1]),
			"相邻边共角点（序列连续，几何判定）i=%d" % i)
	var parallel := 0
	for k in chain.size() - 2:
		var d1 := _edge_dir(map, chain[k])
		var d2 := _edge_dir(map, chain[k + 2])
		if absf(d1.cross(d2)) < 1e-9:
			parallel += 1
	expect(parallel >= chain.size() - 4,
		"走廊样：edge[k] ∥ edge[k+2] 占绝对多数（got %d/%d）" % [parallel, chain.size() - 2])

func test_bend_shape_and_source_single_edge() -> void:
	# 弯样：绕格边界三条边（自然转折——每步换角点）；源 = 单端点边（单边链）
	var map := _base_map()
	var x := Hex.axial_of(Vector2i(4, 3))
	var bend := RiverFix.around_cell_chain(map, x, 3)
	expect_eq(bend.size(), 3, "弯样 = 绕格三条边")
	for i in bend.size() - 1:
		expect(RiverFix.links_share_corner(map, bend[i], bend[i + 1]),
			"弯样相邻边共角点 i=%d" % i)
	# 单边链 = 源与终点同边（源端点边）——校验合法
	var single := RiverFix.around_cell_chain(map, x, 1)
	expect_eq(single.size(), 1, "源样本 = 单端点边（单边链）")
	var m := _base_map()
	var w := _world_for_chain(m, single, [1])
	expect_eq(w.validate(m, T_WATER), "", "单边链（源=终点）过校验——河段至少一条边")

func _edge_dir(map: MapDataClass, link: Vector2i) -> Vector2:
	var cs := RiverFix.link_corners(map, link)
	return cs[1] - cs[0]

# ================= 角点级判定（修订记录三之 4）=================

func test_corner_id_independent_of_representation() -> void:
	# 稳定角点 ID：同一物理角点的三个 (格, 顶点) 表示同值；不同角点不同值。
	# oracle = vertex_xz 世界坐标相等性（几何），不复制 WorldData 的 ID 派生。
	var map := _base_map()
	var x := Hex.axial_of(Vector2i(4, 3))
	var ids := {}
	for k in 6:
		var id := WorldDataClass.corner_id_of(map, x, k)
		ids[id] = true
		# 同角点的另两个表示（数值验证过的公式：N_k 侧 (k+4)%6、N_{k−1} 侧 (k+2)%6）
		var id2 := WorldDataClass.corner_id_of(map, Hex.neighbor(x, k), (k + 4) % 6)
		var id3 := WorldDataClass.corner_id_of(map, Hex.neighbor(x, k - 1), (k + 2) % 6)
		expect_eq(id, id2, "角点 ID 与表示无关（N_k 侧）k=%d" % k)
		expect_eq(id, id3, "角点 ID 与表示无关（N_{k−1} 侧）k=%d" % k)
	expect_eq(ids.size(), 6, "格六角点 ID 互异")

func test_rejects_corner_level_cycle() -> void:
	# 角点级环：绕格**六条不同边**闭环——每条边只出现一次（边不复用），
	# 但首尾经同一角点接回（两条不同边经同一角点二次成环）→ RIVER_CYCLE。
	# 仅查边复用的旧口径对本案失明（修订记录三之 4 的拒绝样本）。
	var map := _base_map()
	var x := Hex.axial_of(Vector2i(4, 3))
	var ring := RiverFix.around_cell_chain(map, x, 6)
	expect_eq(ring.size(), 6, "环样本 = 六条不同边")
	var uniq := {}
	for e in ring:
		uniq[e] = true
	expect_eq(uniq.size(), 6, "六条边互不相同（边不复用——环靠角点闭合）")
	var w := _world_for_chain(map, ring, [1, 1, 1, 1, 1, 1])
	var msg := w.validate(map, T_WATER)
	expect(msg.contains("RIVER_CYCLE"), "角点级环被拒（got：%s）" % msg)

# ================= 校验器四条（WATER-01 ②）=================

func test_validate_accepts_valid_river_and_zero_writeback() -> void:
	var map := _base_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	var w := _world_for_chain(map, chain, [2, 2, 1])
	expect_eq(w.validate(map, T_WATER), "",
		"合法单河（弯样 + 逐段 profile [2,2,1] + 河口湖）过校验")
	# 零回写（草案 §11 全局项）：validate 只读——对照基线取**涂写后**摘要
	#（河口湖涂格发生在 _world_for_chain 构造期）
	var painted := map.summary()
	expect_eq(w.validate(map, T_WATER), "", "二次校验一致（只读）")
	expect_eq(map.summary(), painted, "validate 前后 summary 逐字节不变（零回写）")
	expect_eq(map.mods.size(), 0, "mods 保持空（WorldData 永不写入）")

func test_rejects_upstream_rise() -> void:
	var map := _base_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	var w := _world_for_chain(map, chain, [1, 2, 1])
	var msg := w.validate(map, T_WATER)
	expect(msg.contains("RIVER_LEVEL_RISE"), "水位沿边序列上坡被拒（got：%s）" % msg)

func test_rejects_bed_not_below_water() -> void:
	var map := _base_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	# bed = 1：最后一段水位 1 → bed 不低于水（恒 < 逐段 water_level 违例）
	var w := _world_for_chain(map, chain, [2, 2, 1], 1)
	var msg := w.validate(map, T_WATER)
	expect(msg.contains("RIVER_BED"), "bed_level ≥ 逐段 water_level 被拒（got：%s）" % msg)

func test_rejects_non_neighbor_and_disconnected() -> void:
	var map := _base_map()
	# 非法邻格：(0,0) 与 (2,1) 不相邻（dir_between 独立验证前提）
	var a := Hex.axial_of(Vector2i(0, 0))
	var b := Hex.axial_of(Vector2i(2, 1))
	expect(Hex.dir_between(a, b) < 0, "构造前提：两格不互为邻居")
	var w1 := _world_for_chain(map, [WorldDataClass.link_id_of(
		map.index_of(a), map.index_of(b))], [1])
	var m1 := w1.validate(map, T_WATER)
	expect(m1.contains("不互为界内邻居"), "非法邻格边被拒（got：%s）" % m1)
	# 断链：同格两条对向边（不共角点）
	var x := Hex.axial_of(Vector2i(4, 3))
	var e1 := WorldDataClass.link_id_of(map.index_of(x),
		map.index_of(Hex.neighbor(x, 0)))
	var e2 := WorldDataClass.link_id_of(map.index_of(x),
		map.index_of(Hex.neighbor(x, 3)))
	expect(not RiverFix.links_share_corner(map, e1, e2), "构造前提：对向边不共角点")
	var w2 := _world_for_chain(map, [e1, e2], [1, 1])
	var m2 := w2.validate(map, T_WATER)
	expect(m2.contains("不共角点") or m2.contains("不连续"),
		"断链被拒（got：%s）" % m2)

func test_rejects_edge_reuse_across_reaches() -> void:
	var map := _base_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 2)
	var w := _world_for_chain(map, chain, [1, 1])
	# 第二 reach 复用第一 reach 的边（汇流第二版前的结构性拒绝面）
	var r2 := WorldDataClass.RiverReachData.new()
	r2.reach_id = 1
	r2.edges = [chain[0]]
	r2.water_levels = [1]
	r2.bed_level = 0
	r2.water_body_id = 0
	w.rivers.append(r2)
	var msg := w.validate(map, T_WATER)
	expect(msg.contains("RIVER_EDGE_REUSE") or msg.contains("复用"),
		"边跨 reach 复用被拒（got：%s）" % msg)

# ================= 终点/河口/link 对账 =================

func test_rejects_outlet_reconciliation_failures() -> void:
	var map := _base_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	# ① 水体引用不可解析（v1 每河必汇入声明水体）
	var w1 := _world_for_chain(map, chain, [2, 2, 1])
	w1.rivers[0].water_body_id = WorldDataClass.ID_NONE
	var m1 := w1.validate(map, T_WATER)
	expect(m1.contains("NO_RIVER_OUTLET"), "无终点水体被拒（got：%s）" % m1)
	# ② 终点边 ∉ inlet_links（置空——放非岸边边会先撞岸边口径，错归因）
	var w2 := _world_for_chain(map, chain, [2, 2, 1])
	w2.water_bodies[0].inlet_links = []
	var m2 := w2.validate(map, T_WATER)
	expect(m2.contains("NO_RIVER_OUTLET"), "终点边不在 inlet_links 被拒（got：%s）" % m2)
	# ③ 河口水位不等于水体水面
	var w3 := _world_for_chain(map, chain, [2, 2, 1])
	w3.water_bodies[0].water_level = 2
	var m3 := w3.validate(map, T_WATER)
	expect(m3.contains("WATER_MOUTH_LEVEL"), "河口水位 ≠ 水体水面被拒（got：%s）" % m3)

func test_rejects_inlet_without_reach_mirror() -> void:
	# inlet 镜像：水体声明了无河段终点对账的入水口（双向对账的镜像侧）
	var map := _base_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	var w := _world_for_chain(map, chain, [2, 2, 1])
	# 取成员集外一格与成员格构成的岸边 link（非终点边）
	var b := w.water_bodies[0]
	var extra: Vector2i = WorldDataClass.NO_LINK
	var mcell := RiverFix.cell_of_id(map, b.member_cells[0])
	for d in 6:
		var nb := Hex.neighbor(mcell, d)
		if map.has_cell(nb) and not b.member_cells.has(map.index_of(nb)):
			var lk := WorldDataClass.link_id_of(map.index_of(mcell), map.index_of(nb))
			if not b.inlet_links.has(lk):
				extra = lk
				break
	expect(extra != WorldDataClass.NO_LINK, "构造前提：找到非终点的岸边 link")
	if extra != WorldDataClass.NO_LINK:
		b.inlet_links.append(extra)
		var msg := w.validate(map, T_WATER)
		expect(msg.contains("WATER_INLET"), "无河段对账的 inlet 被拒（got：%s）" % msg)

func test_rejects_terminal_edge_not_shore() -> void:
	# 河口边 = 岸边（恰一端成员）——两侧全水 = 内部边接不上缝（WATER-03 ④ 前提）
	var map := _base_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	var w := _world_for_chain(map, chain, [2, 2, 1])
	var term: Vector2i = chain[chain.size() - 1]
	var bank_id := term.y
	var members: Array[int] = w.water_bodies[0].member_cells.duplicate()
	members.append(bank_id)
	members.sort()
	w.water_bodies[0].member_cells = members
	# 对岸格按成员语义涂水（否则先撞 WATER_MEMBER_TERRAIN，错归因）
	map.set_terrain(RiverFix.cell_of_id(map, bank_id), T_WATER)
	map.set_elevation(RiverFix.cell_of_id(map, bank_id), 0)
	map.set_passable(RiverFix.cell_of_id(map, bank_id), false)
	var msg := w.validate(map, T_WATER)
	expect(msg.contains("岸边") or msg.contains("恰一端"),
		"河口边两侧全成员被拒（got：%s）" % msg)

func test_link_river_bidirectional_reconciliation() -> void:
	var map := _base_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	# ① 缺 link 条目
	var w1 := _world_for_chain(map, chain, [2, 2, 1])
	w1.links.remove_at(1)
	var m1 := w1.validate(map, T_WATER)
	expect(m1.contains("LINK_RIVER_MISMATCH"), "reach 边缺 link 条目被拒（got：%s）" % m1)
	# ② link 声明与 reach 不符
	var w2 := _world_for_chain(map, chain, [2, 2, 1])
	w2.links[0].river_reach_id = 7
	var m2 := w2.validate(map, T_WATER)
	expect(m2.contains("LINK_RIVER_MISMATCH"), "link river_reach_id 指错 reach 被拒（got：%s）" % m2)
	# ③ link 声明有河但无 reach 含此边
	var w3 := _world_for_chain(map, chain, [2, 2, 1])
	var pair_a := Hex.axial_of(Vector2i(1, 6))
	var pair_b := Hex.axial_of(Vector2i(2, 6))
	expect(Hex.dir_between(pair_a, pair_b) >= 0, "构造前提：(1,6)-(2,6) 相邻")
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(map.index_of(pair_a), map.index_of(pair_b))
	lk.river_reach_id = 0
	w3.links.append(lk)
	w3.links.sort_custom(_link_order)
	var m3 := w3.validate(map, T_WATER)
	expect(m3.contains("LINK_RIVER_MISMATCH"), "无 reach 含此边的有河 link 被拒（got：%s）" % m3)

# ================= 序列化（Vector2i [x,y] 转换层 + 往返 + 旧图零迁移）=================

func test_river_serialization_roundtrip_and_shapes() -> void:
	var map := _base_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	var w := _world_for_chain(map, chain, [2, 2, 1])
	var d := w.to_dict()
	expect_eq((d["rivers"] as Array).size(), 1, "落盘河流 1 条")
	var entry: Dictionary = (d["rivers"] as Array)[0]
	expect(entry["edges"] is Array, "edges 落盘形状 = 数组")
	for e in entry["edges"]:
		expect(e is Array and (e as Array).size() == 2, "每边 = [x, y] 两元数组（显式转换层）")
	var text := JSON.stringify(d)
	expect(not text.contains("(") or _no_vector2i_strings(entry["edges"]),
		"边序列落盘不得含 \"(x, y)\" 字符串形状（引擎实测坑）")
	# JSON 文件往返（真实文件，user:// 临时件）
	var path := "user://test_water_rivers_rt.world.json"
	expect_eq(MapIO.write_world(w, path), OK, "世界伴生文件写入成功")
	var back: Variant = MapIO.read_world(path)
	expect(back is WorldDataClass, "读回 WorldData")
	if back is WorldDataClass:
		var b: WorldDataClass = back
		expect_eq(b.to_dict(), w.to_dict(), "往返 to_dict 逐位一致")
		expect_eq(b.rivers.size(), 1, "河段数保持")
		expect_eq(b.rivers[0].edges, chain, "边序列重建一致")
		expect_eq(b.rivers[0].water_levels, [2, 2, 1], "逐段水位 profile 重建一致")
		expect_eq(b.water_bodies[0].inlet_links, [chain[2]], "inlet_links 重建一致")
		expect_eq(b.validate(map, T_WATER), "", "读回世界仍过校验（保存→重载同验）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## edges 落盘条目全部为两元 int 数组（无字符串形状——直写 Vector2i 会落 "(x, y)"）。
func _no_vector2i_strings(edges: Variant) -> bool:
	for e in edges:
		if not (e is Array) or (e as Array).size() != 2:
			return false
	return true

func test_missing_world_file_still_empty_legal() -> void:
	# 旧图零迁移（T3 面复锚）：缺 .world.json → empty() 无河合法态
	var path := "user://test_water_rivers_missing_9d2.world.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var w: Variant = MapIO.read_world(path)
	expect(w is WorldDataClass, "缺伴生文件 → empty()")
	if w is WorldDataClass:
		var e: WorldDataClass = w
		expect_eq(e.rivers.size(), 0, "无河（rivers 空 = 合法态——渲染/查询走无河分支）")
		expect_eq(e.links.size(), 0, "无 link")
		expect_eq(e.validate(_base_map()), "", "empty() 合法（不需要水体）")

func test_from_dict_rejects_bad_river_shapes() -> void:
	var map := _base_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	var good := _world_for_chain(map, chain, [2, 2, 1]).to_dict()
	# water_levels 与 edges 长度不齐
	var mismatched := good.duplicate(true)
	((mismatched["rivers"] as Array)[0] as Dictionary)["water_levels"] = [2, 2]
	expect(WorldDataClass.from_dict(mismatched) == null, "profile 长度不齐 → null")
	# 边形状非 [x,y]
	for bad_edge in [[3], [3, 17, 5], [-1, 17], [17, 3], "nope"]:
		var dd := good.duplicate(true)
		((dd["rivers"] as Array)[0] as Dictionary)["edges"] = [bad_edge, [3, 17]]
		expect(WorldDataClass.from_dict(dd) == null,
			"边形状 %s → null（无隐式兜底）" % str(bad_edge))
	# 主键/流量非法
	for patch in [{"reach_id": -1}, {"flow_level": 0}]:
		var d2 := good.duplicate(true)
		for k in patch:
			((d2["rivers"] as Array)[0] as Dictionary)[k] = patch[k]
		expect(WorldDataClass.from_dict(d2) == null, "%s 非法 → null" % str(patch))
	# roads 形状非法仍拒（T4 起解析路/桥——条目缺字段走形状层拒绝）
	var roads := good.duplicate(true)
	roads["roads"] = [{"any": 1}]
	expect(WorldDataClass.from_dict(roads) == null, "roads 条目缺字段 → null（形状层拒绝）")

# ================= 固定图数据化面（WATER-01 ③）=================

func test_fixed_map_world_loads_and_validates() -> void:
	var map := MapIO.read_map(MapIO.FIXED_MAP_PATH)
	expect(map != null, "固定图应可加载")
	if map == null:
		return
	var world: Variant = MapIO.read_world(MapIO.world_path_for(MapIO.FIXED_MAP_PATH))
	expect(world is WorldDataClass, "固定图世界伴生文件应可加载（RIVER_* 常量数据化）")
	if not (world is WorldDataClass):
		return
	var w: WorldDataClass = world
	expect(w.rivers.size() >= 1, "固定图至少一条河（手工图数据化不再写死格序列）")
	expect(w.water_bodies.size() >= 2, "固定图至少两个水体（河口小湖 + 东北湖）")
	expect_eq(w.validate(map, T_WATER), "", "固定图世界过全量校验（含河口对账）")
	# link 引用面：河边序列全部有条目且一一对应
	var river_edges := {}
	for r in w.rivers:
		for e in r.edges:
			river_edges[e] = true
	var claimed := {}
	for lk in w.links:
		if lk.river_reach_id != WorldDataClass.ID_NONE:
			claimed[lk.link_id] = true
	expect_eq(claimed.size(), river_edges.size(), "河边序列与 link 引用面一一对应")
	# 渡口 hack 退场：河不占格——河边格要么是水体成员（不可通行）要么保持可通行
	# 陆地（河的通行影响走规则层 M3，渲染/数据都不改 passable——§2.2 禁令行）
	var membership := w.water_membership()
	for r in w.rivers:
		for e in r.edges:
			for cid in [e.x, e.y]:
				var is_member: bool = membership.has(cid)
				expect_eq(map.is_passable(RiverFix.cell_of_id(map, cid)), not is_member,
					"河边格通行性：成员=不可通行 / 岸=可通行（渡口 hack 退场）cell %d" % cid)
