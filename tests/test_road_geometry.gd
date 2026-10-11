## test_road_geometry.gd — T4 ROAD-01 ②③/ROAD-02 ③ 路面/桥面几何单测（执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §5 ROAD-01/02 + 修订记录三之 2 桥走向）
## 覆盖锚（卡表「测试锚」几何面）：
##   - 构型等价类穷举的面数解析预言：每方向子集 |D| → 路面 = 4|D| 面
##     （格心扇区 2 + 连接带 2 × 每方向），同一公式覆盖 63 子集；
##   - 宽度调制（Catlike 通式字面移植）：相邻方向有路 = 格心端全宽、孤悬端收窄；
##   - chunk 无关铁律：三种划分（单块/行切/每格一块）顶点集合逐位一致；
##   - 贴地不共面：路面 y 恒 = 地表 + lift（档位表 tier 3；与地形面差一档）；
##   - 桥面（修订记录三之 2）：**长轴 = 跨岸方向 n ⊥ 河流方向 t
##     （abs(dot(t,n)) ≤ 容差）**；**桥头落地（端点 y == 本岸顶面 + 桥面 lift，
##     无悬空）**；中段 y = max(两岸)+lift 且恒于水面之上；面候选 = bank 两格；
##   - 桥面碰撞汤：deck_collision 与 deck_face_table 逐索引对应（桥面拾取通道）。
## oracle 原则：期望顶点由 HexMath 全局参数独立拼装（axial_to_world / inner_vertex /
##   edge_tangent_world——与实现共用参数源但独立推导坐标，不读实现内部函数）；
##   ⊥ 断言的 n 取两岸格心连线、t 取 edge_tangent——两向量各路独立计算。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const RoadBuilder := preload("res://addons/hexhammer/road_geometry_builder.gd")
const WaterGeom := preload("res://addons/hexhammer/water_geometry_builder.gd")
const HexHighlightLib := preload("res://addons/hexhammer/hex_highlight.gd")
const HexPickingLib := preload("res://addons/hexhammer/hex_picking.gd")

const MAP_W := 9
const MAP_H := 7

func _base_map() -> MapDataClass:
	return MapDataClass.new(MAP_W, MAP_H)


## 中心格 → 方向子集 dirs 的多路世界（每方向一条 2 格路；link 表投影 + 升序）。
func _junction_world(map: MapDataClass, center: Vector2i,
		dirs: Array[int]) -> WorldDataClass:
	var w := WorldDataClass.empty()
	for i in dirs.size():
		var road := WorldDataClass.RoadData.new()
		road.road_id = i
		road.cells = [map.index_of(center), map.index_of(Hex.neighbor(center, dirs[i]))]
		w.roads.append(road)
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = WorldDataClass.link_id_of(road.cells[0], road.cells[1])
		lk.road_id = road.road_id
		w.links.append(lk)
	w.links.sort_custom(func(a: WorldDataClass.NeighborLinkData,
			b: WorldDataClass.NeighborLinkData) -> bool:
		return a.link_id.x < b.link_id.x or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y))
	return w


## 构建结果（默认参数）→ Dictionary；失败 fail 并返回 {}。
func _build(map: MapDataClass, world: WorldDataClass) -> Dictionary:
	var r: Variant = RoadBuilder.build_map(map, world, 10, 10,
		RoadBuilder.make_road_material())
	if not (r is Dictionary):
		fail("路面层构建失败（参数非法？）")
		return {}
	return r

## ---- 顶点/三角提取（读引擎数组；faces 序 = 三角序 = surface 序）----

## 全部三角（每项 {"face": Dictionary, "verts": Array[Vector3]}）——沿 mesh surface
## 顺序消费 3 顶点/面（与 faces 元数据一一对应）。
func _tris_of(chunk: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mesh: ArrayMesh = chunk["mesh"]
	var vi := 0
	for face in (chunk["faces"] as Array):
		var surface_i := 0 if vi < _surface_vertex_count(mesh, 0) else 1
		var verts: PackedVector3Array = mesh.surface_get_arrays(surface_i)[Mesh.ARRAY_VERTEX]
		var local := vi if surface_i == 0 else vi - _surface_vertex_count(mesh, 0)
		var tri: Array[Vector3] = [verts[local], verts[local + 1], verts[local + 2]]
		out.append({"face": face, "verts": tri})
		vi += 3
	return out

func _surface_vertex_count(mesh: ArrayMesh, i: int) -> int:
	if mesh.get_surface_count() <= i:
		return 0
	return mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size()

# ================= 面数解析预言 + 宽度调制 =================

func test_face_count_oracle_all_configs() -> void:
	# 每（中心格 × 方向 d）：格心扇区 2 面 + 连接带 2 面 → 4 面；63 子集全覆盖
	var map := _base_map()
	var center := Hex.axial_of(Vector2i(4, 3))
	for mask in 64:
		var dirs: Array[int] = []
		for d in 6:
			if mask & (1 << d) != 0:
				dirs.append(d)
		if dirs.is_empty():
			continue
		var w := _junction_world(map, center, dirs)
		var built := _build(map, w)
		if built.is_empty():
			return
		var total := 0
		for chunk in (built["chunks"] as Array):
			var fc: Dictionary = (chunk as Dictionary)["face_counts"]
			total += int(fc["road"]) + int(fc["road_band"]) + int(fc["bridge_deck"])
		# 解析预言：每方向 = 两端格各一格心扇区（2×2 面）+ 一条连接带（2 面）= 6 面
		expect_eq(total, 6 * dirs.size(),
			"面数解析预言：6×|D|（mask %d，|D|=%d）" % [mask, dirs.size()])

func test_center_width_modulation() -> void:
	# Catlike 通式字面移植：相邻（d±1）有路 → 格心端全宽；孤悬（含纯对向）收窄
	expect_almost_eq(RoadBuilder.center_width_factor(0, [0, 1]), 1.0, 1e-9, "相邻有路 = 全宽")
	expect_almost_eq(RoadBuilder.center_width_factor(0, [0, 5]), 1.0, 1e-9, "另一侧相邻 = 全宽")
	expect_almost_eq(RoadBuilder.center_width_factor(0, [0]), RoadBuilder.LONE_END_WIDTH_FACTOR,
		1e-9, "孤悬端收窄")
	expect_almost_eq(RoadBuilder.center_width_factor(0, [0, 3]), RoadBuilder.LONE_END_WIDTH_FACTOR,
		1e-9, "纯对向不算相邻（直路中段不加宽）")
	expect_almost_eq(RoadBuilder.center_width_factor(0, [0, 2]), RoadBuilder.LONE_END_WIDTH_FACTOR,
		1e-9, "隔一格不算相邻")

func test_platform_strip_geometry_oracle() -> void:
	# 单方向路：格心扇区两端点位 oracle——格心端 ± 全宽调制 × t、内边端 ± 全宽 × t、
	# 内边端中心 = 两内顶点中点；y = 高程×step + 路面 lift
	var map := _base_map()
	map.set_elevation(Hex.axial_of(Vector2i(4, 3)), 2)  # 非零高程验证 y 公式
	var center := Hex.axial_of(Vector2i(4, 3))
	var only_east: Array[int] = [0]
	var w := _junction_world(map, center, only_east)
	var built := _build(map, w)
	if built.is_empty():
		return
	var tris := _tris_of((built["chunks"] as Array)[0])
	var road_tris: Array[Dictionary] = []
	for t in tris:
		var f: Dictionary = t["face"]
		if String(f["kind"]) == "road" and f["cell"] == center:
			road_tris.append(t)  # 只取中心格的扇区（对端格扇区朝向相反、另锚）
	expect_eq(road_tris.size(), 2, "单方向格心扇区 = 2 面")
	if road_tris.size() != 2:
		return
	var lift := HexHighlightLib.lift_for_tier(HexHighlightLib.TIER_ROAD)
	var y := 2.0 + lift
	var t_vec := Hex.edge_tangent_world(0)
	var c := Hex.axial_to_world(center, 1.0)
	var v1 := Hex.inner_vertex(center, 0, 1.0, 0.8)
	var v2 := Hex.inner_vertex(center, 1, 1.0, 0.8)
	var edge_mid := (v1 + v2) * 0.5
	var w_c := RoadBuilder.DEFAULT_HALF_WIDTH * RoadBuilder.LONE_END_WIDTH_FACTOR
	var w_e := RoadBuilder.DEFAULT_HALF_WIDTH
	var expected: Array[Vector3] = [
		Vector3(c.x + t_vec.x * w_c, y, c.z + t_vec.z * w_c),
		Vector3(c.x - t_vec.x * w_c, y, c.z - t_vec.z * w_c),
		Vector3(edge_mid.x + t_vec.x * w_e, y, edge_mid.z + t_vec.z * w_e),
		Vector3(edge_mid.x - t_vec.x * w_e, y, edge_mid.z - t_vec.z * w_e)]
	for t in road_tris:
		for v in (t["verts"] as Array):
			var matched := false
			for e in expected:
				if v.distance_to(e) < 1e-6:
					matched = true
					break
			expect(matched, "格心扇区顶点 ∈ oracle 四角集（got %s）" % str(v))

func test_band_strip_slopes_with_delta1() -> void:
	# 连接带条带贴坡：Δ1 时 owner 侧 y = 2+lift、对端 y = 1+lift（两侧各自格面）；
	# 每条有路 link 恰一带（全图计数断言）
	var map := _base_map()
	var a := Hex.axial_of(Vector2i(3, 3))
	var b := Hex.neighbor(a, 0)
	map.set_elevation(a, 2)
	map.set_elevation(b, 1)  # 显式 Δ1（默认 0——两侧高程由本行钉死）
	var dirs_east: Array[int] = [0]
	var w := _junction_world(map, a, dirs_east)  # road [a→b]，road_id 0
	var built := _build(map, w)
	if built.is_empty():
		return
	var band_tris: Array[Dictionary] = []
	for chunk in (built["chunks"] as Array):
		for t in _tris_of(chunk):
			if String((t["face"] as Dictionary)["kind"]) == "road_band":
				band_tris.append(t)
	expect_eq(band_tris.size(), 2, "恰一有路 link → 恰一带（2 三角，全图计数）")
	var lift := HexHighlightLib.lift_for_tier(HexHighlightLib.TIER_ROAD)
	# mesh 顶点是 float32（GDScript 标量 float 是 64 位）——期望值按容差匹配
	var ys := {}
	for t in band_tris:
		for v in (t["verts"] as Array):
			ys[v.y] = true
	var has_a := false
	var has_b := false
	for y_key in ys:
		if absf(float(y_key) - (2.0 + lift)) < 1e-6:
			has_a = true
		if absf(float(y_key) - (1.0 + lift)) < 1e-6:
			has_b = true
	expect(has_a and has_b,
		"Δ1 带两侧 y = 各自格面 + lift（贴坡不悬空，got %s）" % str(ys.keys()))

func test_chunk_invariance_three_splits() -> void:
	# chunk 无关铁律：单块 / 行切 / 每格一块——路面/桥面全部顶点逐位一致
	#（沿 test_water_geometry.gd 划分矩阵先例：排序后 == 精确比较）
	var map := _base_map()
	var center := Hex.axial_of(Vector2i(4, 3))
	var three_way: Array[int] = [0, 2, 4]
	var w := _junction_world(map, center, three_way)  # 三叉
	var bridge_fix := _bridge_fixture()
	var parts_to_verts := {}
	for parts in [[MAP_W, MAP_H], [5, 3], [1, 1]]:
		var r: Variant = RoadBuilder.build_map(map, w, parts[0], parts[1],
			RoadBuilder.make_road_material())
		if not (r is Dictionary):
			fail("划分 %s 构建失败" % str(parts))
			return
		parts_to_verts["junction:" + str(parts)] = _sorted_verts(r as Dictionary)
		var rb: Variant = RoadBuilder.build_map(bridge_fix["map"], bridge_fix["world"],
			parts[0], parts[1], RoadBuilder.make_road_material())
		if not (rb is Dictionary):
			fail("桥 fixture 划分 %s 构建失败" % str(parts))
			return
		parts_to_verts["bridge:" + str(parts)] = _sorted_verts(rb as Dictionary)
	var keys := ["junction:" + str([MAP_W, MAP_H]), "junction:" + str([5, 3]),
		"junction:" + str([1, 1]), "bridge:" + str([MAP_W, MAP_H]),
		"bridge:" + str([5, 3]), "bridge:" + str([1, 1])]
	expect_eq(parts_to_verts[keys[0]], parts_to_verts[keys[1]],
		"三叉路面顶点：单块 vs 行切 逐位一致")
	expect_eq(parts_to_verts[keys[0]], parts_to_verts[keys[2]],
		"三叉路面顶点：单块 vs 每格一块 逐位一致")
	expect_eq(parts_to_verts[keys[3]], parts_to_verts[keys[4]],
		"桥面顶点：单块 vs 行切 逐位一致")
	expect_eq(parts_to_verts[keys[3]], parts_to_verts[keys[5]],
		"桥面顶点：单块 vs 每格一块 逐位一致")


## 构建结果的全部顶点（faces 序 = 三角序；排序后比较——划分无关性断言载体）。
func _sorted_verts(build: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for chunk in (build["chunks"] as Array):
		var mesh: ArrayMesh = (chunk as Dictionary)["mesh"]
		for si in mesh.get_surface_count():
			for v in mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				out.append(v)
	out.sort()
	return out

# ================= 桥面几何锚（修订记录三之 2）=================

## 桥 fixture：3×3 图，a=(1,1) 与东邻 b 之间单边河（水位 1、床 0、两岸高程 1 →
## Δ0 平桥）+ 跨接路 + 认领桥。**builder 级 fixture**：路面/桥面几何只读
## rivers/roads/crossings/links，不设河口湖（世界事实合法性归 WorldData.validate，
## 本文件测几何——builder 信任已验世界的合同面）；完整合法世界见 test_bridges.gd。
## 返回 {"map","world","link","a","b"}。
func _bridge_fixture() -> Dictionary:
	var map := MapDataClass.new(3, 3)
	for cell in map.cells():
		map.set_elevation(cell, 1)
	var a := Hex.axial_of(Vector2i(1, 1))
	var b := Hex.neighbor(a, 0)
	var w := WorldDataClass.empty()
	var link := WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = [link]
	reach.water_levels = [1]
	reach.bed_level = 0
	reach.water_body_id = 0
	w.rivers.append(reach)
	var road := WorldDataClass.RoadData.new()
	road.road_id = 0
	road.cells = [link.x, link.y]
	w.roads.append(road)
	var crossing := WorldDataClass.CrossingData.new()
	crossing.crossing_id = 0
	crossing.river_edge = link
	crossing.bank_a = link.x
	crossing.bank_b = link.y
	w.crossings.append(crossing)
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = link
	lk.river_reach_id = 0
	lk.road_id = 0
	w.links.append(lk)
	return {"map": map, "world": w, "link": link, "a": a, "b": b}

func test_bridge_deck_axis_perp_and_landing() -> void:
	# 修订记录三之 2 三断言：长轴 n ⊥ 河流方向 t（abs(dot) ≤ 容差）；桥头落地
	# （端点 y == 本岸顶面 + 桥面 lift，无悬空）；中段 y = max(两岸)+lift > 水面
	var fix := _bridge_fixture()
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	var a: Vector2i = fix["a"]
	var b: Vector2i = fix["b"]
	var built := _build(map, w)
	if built.is_empty():
		return
	var deck_tris: Array[Dictionary] = []
	for chunk in (built["chunks"] as Array):
		for t in _tris_of(chunk):
			if String((t["face"] as Dictionary)["kind"]) == "bridge_deck":
				deck_tris.append(t)
	expect_eq(deck_tris.size(), 10, "桥面 = 5 段 × 2 三角")
	# ① 长轴 ⊥ 河流方向：n = 两岸格心连线、t = edge_tangent（两路独立计算）
	var ca := Hex.axial_to_world(a, 1.0)
	var cb := Hex.axial_to_world(b, 1.0)
	var n := Vector3(cb.x - ca.x, 0.0, cb.z - ca.z).normalized()
	var t_river := Hex.edge_tangent_world(Hex.dir_between(a, b))
	expect_almost_eq(absf(n.dot(t_river)), 0.0, 1e-6,
		"桥面长轴 = 跨岸方向 n ⊥ 河流方向 t（abs(dot(t,n)) ≤ 容差——沿 edge_tangent=顺河禁止）")
	# ② 桥头落地：deck 端点（a 格心/b 格心两角）y == 本岸顶面 + 桥面 lift
	var lift := HexHighlightLib.lift_for_tier(HexHighlightLib.TIER_BRIDGE_DECK)
	var y_a := float(map.elevation_at(a)) + lift
	var y_b := float(map.elevation_at(b)) + lift
	var half_w := RoadBuilder.DEFAULT_HALF_WIDTH
	var a_corners := [Vector3(ca.x + t_river.x * half_w, y_a, ca.z + t_river.z * half_w),
		Vector3(ca.x - t_river.x * half_w, y_a, ca.z - t_river.z * half_w)]
	var b_corners := [Vector3(cb.x + t_river.x * half_w, y_b, cb.z + t_river.z * half_w),
		Vector3(cb.x - t_river.x * half_w, y_b, cb.z - t_river.z * half_w)]
	for side in [["a 岸桥头", a_corners, y_a], ["b 岸桥头", b_corners, y_b]]:
		var label: String = side[0]
		var corners: Array = side[1]
		for corner in corners:
			var found := false
			for t in deck_tris:
				for v in (t["verts"] as Array):
					if v.distance_to(corner) < 1e-6:
						found = true
			expect(found, "%s 端点逐位存在（y = 本岸顶面 + 桥面 lift = %s——桥头落地无悬空）" % [label, str(corner.y)])
	# ③ 中段 y = max(两岸) + lift 且恒于水面之上；任意桥面点 y ≤ 中段高
	#（整桥不得抬高过中段——「不得整桥抬高留悬空桥头」的几何面）
	var y_mid := maxf(y_a, y_b)
	var water_y := WaterGeom.water_surface_y(1, 1.0)
	expect(y_mid > water_y, "桥面中段 %s > 水面 %s（河在下路在上）" % [str(y_mid), str(water_y)])
	for t in deck_tris:
		for v in (t["verts"] as Array):
			expect(v.y <= y_mid + 1e-9, "桥面任意点 y ≤ 中段高（got %s）" % str(v.y))
	# face 元数据：候选 = bank 两格（拾取通道）
	for t in deck_tris:
		var deck_face: Dictionary = t["face"]
		expect(deck_face["bank_a"] == a and deck_face["bank_b"] == b, "桥面 face 带 bank 两格候选")

func test_deck_collision_and_resolve() -> void:
	# deck_collision 与 deck_face_table 逐索引对应（3 顶点/面）；bridge_deck 归属 =
	# 最近格心 + ID 决胜（拾取候选 = bank 两格）
	var fix := _bridge_fixture()
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	var a: Vector2i = fix["a"]
	var b: Vector2i = fix["b"]
	var built := _build(map, w)
	if built.is_empty():
		return
	for chunk in (built["chunks"] as Array):
		var cd: Dictionary = chunk
		var soup: PackedVector3Array = cd["deck_collision"]
		var table: Array = cd["deck_face_table"]
		expect_eq(soup.size(), table.size() * 3, "碰撞汤顶点数 = 3×桥面面数（逐索引对应）")
	var face := {"kind": "bridge_deck", "bank_a": a, "bank_b": b, "link": fix["link"]}
	var mid_a := Hex.axial_to_world(a, 1.0)
	var mid_b := Hex.axial_to_world(b, 1.0)
	# t=0.45（偏 a 侧）→ a；t=0.55 → b；t=0.5 平局 → ID 小者
	var at_45 := Vector3(mid_a.x + (mid_b.x - mid_a.x) * 0.45, 0.0, mid_a.z + (mid_b.z - mid_a.z) * 0.45)
	var at_55 := Vector3(mid_a.x + (mid_b.x - mid_a.x) * 0.55, 0.0, mid_a.z + (mid_b.z - mid_a.z) * 0.55)
	var at_50 := Vector3(mid_a.x + (mid_b.x - mid_a.x) * 0.5, 0.0, mid_a.z + (mid_b.z - mid_a.z) * 0.5)
	expect_eq(HexPickingLib.resolve_face(at_45, face, map, 1.0), a, "t=0.45 归 a 岸（最近格心）")
	expect_eq(HexPickingLib.resolve_face(at_55, face, map, 1.0), b, "t=0.55 归 b 岸（最近格心）")
	var tie_want := a if map.index_of(a) < map.index_of(b) else b
	expect_eq(HexPickingLib.resolve_face(at_50, face, map, 1.0), tie_want, "t=0.5 平局 ID 决胜")

func test_params_invalid_return_null() -> void:
	var map := _base_map()
	var east_only: Array[int] = [0]
	var w := _junction_world(map, Hex.axial_of(Vector2i(4, 3)), east_only)
	expect(RoadBuilder.build_map(map, null, 10, 10, RoadBuilder.make_road_material()) == null,
		"world 为空 → null")
	expect(RoadBuilder.build_map(map, w, 10, 10, null) == null, "材质非 Material → null")
	expect(RoadBuilder.build_map(map, w, 0, 10, RoadBuilder.make_road_material()) == null,
		"chunk 参数 ≤0 → null")
	expect(RoadBuilder.build_map(map, w, 10, 10, RoadBuilder.make_road_material(), -1.0) == null,
		"size ≤0 → null")
	# 无路世界 → 全空 chunk mesh（合法态，face_counts 全 0）
	var empty_built: Variant = RoadBuilder.build_map(map, WorldDataClass.empty(), 10, 10,
		RoadBuilder.make_road_material())
	expect(empty_built is Dictionary, "无路世界构建成功（空态合法）")
	if empty_built is Dictionary:
		var total := 0
		for chunk in ((empty_built as Dictionary)["chunks"] as Array):
			var cd: Dictionary = chunk
			for k in (cd["face_counts"] as Dictionary):
				total += int((cd["face_counts"] as Dictionary)[k])
			expect_eq((cd["mesh"] as ArrayMesh).get_surface_count(), 0, "空 chunk 零 surface")
		expect_eq(total, 0, "无路世界 face_counts 全 0")
