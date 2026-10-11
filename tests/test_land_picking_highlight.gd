## test_land_picking_highlight.gd — T2 LAND-03 单测（geometry→picking→highlight 合同；
##   执行方案 §3 LAND-03 测试锚原文：「每类新面（platform/riser/cliff_wall）真实
##   raycast 与 resolve_face 归属一致（picking_scene_check 扩用例 + tests/test_hex_picking.gd
##   face 表对齐锚扩新面型）；face_index 越界→null 合同在新面数下保持；高亮贴合断言
##   （footprint 口径：扇 y 高于其覆盖位置地表高度，修订记录三之 8）；碰撞汤/face 表
##   逐索引对应在新面数下保持」——本文件覆盖纯逻辑面，引擎级 raycast 在
##   tools/picking_scene_check.gd 扩用例）
## 覆盖锚：
##   - 边带归属随四分类切换：terrace（Δ2）→ 最近格心 + ID 决胜（阶地 riser 沿
##     slope 口径泛化）；cliff（Δ≥threshold）→ 高地侧（cliff_wall 同现规则）；
##     threshold 参数化（4 档下 Δ3 转 terrace、Δ4 转 cliff）+ **管线接线**
##     （chunk_pick_data/resolve_hit/resolve_face 透传阈值——T2 评审修复锚）；
##   - 角落归属：spread ≥ threshold → 最高格；spread ∈ [2, threshold)（阶地形角）
##     → 最近格心 + ID 决胜；
##   - face 表对齐：profile 构建下 chunk_collision_faces / chunk_face_table 与 mesh
##     逐索引对应（新面数下保持）+ face 记录 kind 三值不变、edge_type 含
##     terrace/cliff_wall；resolve_hit 越界 → null；
##   - 高亮贴合（footprint 口径，修订记录三之 8）：矩阵图 profile 构建下每格顶面
##     恒平（y = elevation×step）→ cell_surface_anchor 恒等于顶面平面；扇面 y =
##     顶面 + lift 恒**高于其覆盖位置地表**；riser/崖壁顶点不进入任何格的
##     inner hexagon XZ 内部（扇 footprint 之上无他面穿插）。
## oracle 原则：归属期望由测试侧独立距离/高程算术推导（不复制 pick_* 内部顺序）；
##   顶面平面由 HexMath 全局参数对表。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Lib := preload("res://scripts/core/data/terrain_material_library.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const Picking := preload("res://addons/hexhammer/hex_picking.gd")
const Highlight := preload("res://addons/hexhammer/hex_highlight.gd")
const ProfileClass := preload("res://scripts/core/data/landform_profile.gd")
const Fixtures := preload("res://tools/land_matrix_fixtures.gd")

const SIZE := 1.0
const SOLID := 0.8

# ================= 边带归属：四分类 × threshold 参数化 =================

func test_terrace_edge_resolves_nearest_center() -> void:
	# Δ2（默认档阶地）：最近格心（t=0.45/0.55）+ 平局 ID 决胜——riser 归属沿
	# slope 口径泛化（LAND-03 ①「edge 口径沿用最近格心+ID 决胜」）
	var m := MapDataClass.new(7, 7)
	var a := Hex.axial_of(Vector2i(3, 3))
	var b := Hex.neighbor(a, 0)
	m.set_elevation(a, 0)
	m.set_elevation(b, 2)
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.45), a, 0, m, SIZE), a,
		"Δ2 阶地：近 a 侧归 a（不因高差偏袒高格）")
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.55), a, 0, m, SIZE), b,
		"Δ2 阶地：近 b 侧归 b")
	var want_tie: Vector2i = a if m.index_of(a) < m.index_of(b) else b
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.5), a, 0, m, SIZE), want_tie,
		"Δ2 平局 → ID 小者（与 flat/slope 同一决胜）")

func test_cliff_edge_goes_high_side_and_threshold_param() -> void:
	# Δ3（默认档崖，含 cliff_wall 真垂直墙）：归高地侧（现规则——只有 cliff_wall 走本档）
	var m := MapDataClass.new(7, 7)
	var a := Hex.axial_of(Vector2i(3, 3))
	var b := Hex.neighbor(a, 0)
	m.set_elevation(a, 0)
	m.set_elevation(b, 3)
	for t in [0.45, 0.5, 0.55]:
		var tt: float = t
		expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, tt), a, 0, m, SIZE), b,
			"Δ3 cliff_wall：t=%s 归高地侧（XZ 更近低格也不截胡）" % str(tt))
	# threshold=4：Δ3 转 terrace（最近格心）、Δ4 转 cliff（高地侧）——分类随档切换
	m.set_elevation(b, 3)
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.45), a, 0, m, SIZE, 4), a,
		"threshold=4：Δ3 = 阶地 → 最近格心")
	m.set_elevation(b, 4)
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.55), a, 0, m, SIZE, 4), b,
		"threshold=4：Δ4 = 崖 → 高地侧")

func test_threshold_pipeline_through_resolve_hit() -> void:
	# 管线接线锚（T2 评审修复）：chunk_pick_data / resolve_hit / resolve_face 透传
	# cliff_threshold——此前只在 pick_edge_band 签名层成立，threshold=4 档 Δ3 边
	# face 表记 terrace 而拾取仍按默认档归高侧（面几何语义与归属规则脱钩）。
	# 期望值两侧独立推导：terrace（4 档）→ 最近格心（近低侧 → 低格 a）；
	# 默认档同面按 cliff → 高地侧 b（档位真实生效的对照，非硬编码）
	var m := MapDataClass.new(7, 7)
	var a := Hex.axial_of(Vector2i(3, 3))
	var b := Hex.neighbor(a, 0)
	m.set_elevation(a, 0)
	m.set_elevation(b, 3)
	var profile := ProfileClass.new()
	profile.cliff_threshold = 4
	var r: Variant = Builder.build_map(m, 10, 10,
		Lib.materials_from_colors(Lib.DEFAULT_PALETTE), SIZE, 1.0, SOLID, profile)
	expect(r is Dictionary, "threshold=4 构建成功")
	if not (r is Dictionary):
		return
	var hit := _lerp_centers(a, b, 0.45)  # 近低格 a 侧
	var found := false
	for cd in (r as Dictionary)["chunks"]:
		var pd: Dictionary = Picking.chunk_pick_data(cd, 4)
		expect_eq(pd["cliff_threshold"], 4, "chunk_pick_data 携带阈值（echo）")
		var table: Array[Dictionary] = pd["face_table"]
		for fi in table.size():
			var f: Dictionary = table[fi]
			if f["kind"] != "edge" or f["cell"] != a or int(f["dir"]) != 0:
				continue
			found = true
			expect_eq(String(f["edge_type"]), Builder.EDGE_TERRACE,
				"Δ3 边在 4 档面表记 terrace（几何分类权威）")
			expect_eq(Picking.resolve_hit(hit, fi, table, m, SIZE, 4), a,
				"resolve_hit 透传阈值：terrace 归最近格心（低格，与几何分类同语义）")
			expect_eq(Picking.resolve_face(hit, f, m, SIZE, 4), a,
				"resolve_face 透传阈值：同上")
			expect_eq(Picking.resolve_face(hit, f, m, SIZE), b,
				"不传阈值（默认 3）同面按 cliff 归高侧——档位对照证明接线必要")
			break
		if found:
			break
	expect(found, "a→b 东边带面在 face 表中（构造前提）")

# ================= 角落归属：spread 与 threshold =================

func test_corner_spread_threshold_boundary() -> void:
	# spread=2（默认档 < 3，阶地形角）→ 最近格心；spread=3（悬崖形）→ 最高格
	#（并列最高 ID 小者——现规则随 threshold 泛化）
	var combos_nearest := [[0, 1, 2], [0, 2, 2], [2, 0, 2]]
	for combo in combos_nearest:
		var got := _pick_corner_with(combo)
		expect_eq(got["got"], got["want_nearest"],
			"spread=2 角 = 最近格心（组合 %s——阶地形角不走高格分支）" % str(combo))
	var combos_highest := [[0, 0, 3], [0, 1, 3], [3, 3, 0], [1, 3, 0]]
	for combo in combos_highest:
		var got := _pick_corner_with(combo)
		expect_eq(got["got"], got["want_highest"],
			"spread≥3 角 = 最高格（组合 %s——坍缩扇归高侧）" % str(combo))

## 构造 (a,b,c) 三格角并返回 {got, want_nearest, want_highest}——oracle 两侧独立推导。
func _pick_corner_with(combo: Array) -> Dictionary:
	var m := MapDataClass.new(5, 5)
	var a := Hex.axial_of(Vector2i(1, 1))
	var b := Hex.neighbor(a, 2)
	var c := Hex.neighbor(a, 1)
	m.set_elevation(a, combo[0])
	m.set_elevation(b, combo[1])
	m.set_elevation(c, combo[2])
	# owner（三格最小 ID）+ 角编号（邻居对匹配独立推导）
	var owner := a
	for cell in [a, b, c]:
		if m.index_of(cell) < m.index_of(owner):
			owner = cell
	var j := -1
	for cand in 6:
		var n1 := Hex.neighbor(owner, cand)
		var n2 := Hex.neighbor(owner, cand - 1)
		var others := []
		for cell in [a, b, c]:
			if cell != owner:
				others.append(cell)
		if others.has(n1) and others.has(n2):
			j = cand
			break
	if j < 0:
		return {"got": Vector2i(99, 99), "want_nearest": Vector2i(), "want_highest": Vector2i()}
	# 命中点 = 角三角重心（HexMath 全局参数对表）
	var p1 := Hex.inner_vertex(owner, j, SIZE, SOLID, float(m.elevation_at(owner)))
	var br_j := Hex.bridge_xz(owner, j, SIZE, SOLID)
	var br_j1 := Hex.bridge_xz(owner, j - 1, SIZE, SOLID)
	var p2 := p1 + Vector3(br_j.x, 0.0, br_j.y)
	var p3 := p1 + Vector3(br_j1.x, 0.0, br_j1.y)
	p2.y = 0.0
	p3.y = 0.0
	var hit := (p1 + p2 + p3) / 3.0
	var got := Picking.pick_corner(hit, owner, j, m, SIZE)
	# oracle A：最近格心（距离独立算术 + ID 决胜）
	var trio := [a, b, c]
	var want_near: Vector2i = trio[0]
	var best_d := INF
	for cell in trio:
		var ctr := Hex.axial_to_world(cell, SIZE)
		var d := Vector2(hit.x - ctr.x, hit.z - ctr.z).length()
		if d < best_d - 1e-6:
			best_d = d
			want_near = cell
		elif absf(d - best_d) <= 1e-6 and m.index_of(cell) < m.index_of(want_near):
			best_d = mini(d, best_d)
			want_near = cell
	# oracle B：最高格（并列 ID 小者）
	var want_high: Vector2i = trio[0]
	for cell in trio:
		if m.elevation_at(cell) > m.elevation_at(want_high) \
				or (m.elevation_at(cell) == m.elevation_at(want_high) and m.index_of(cell) < m.index_of(want_high)):
			want_high = cell
	return {"got": got, "want_nearest": want_near, "want_highest": want_high}

# ================= face 表对齐（新面数下保持）=================

func test_face_table_alignment_with_profile_mesh() -> void:
	# 矩阵图 + 默认 profile：碰撞汤/face 表与 mesh 逐索引对应（自提交三角形顺序合同
	# 在新面数下保持——LAND-03 ③「三角序合同自动覆盖新面型」）
	var map := Fixtures.build_matrix(3)
	var r: Variant = Builder.build_map(map, 5, 5, Lib.materials_from_colors(Lib.DEFAULT_PALETTE),
		SIZE, 1.0, SOLID, ProfileClass.make_default())
	expect(r is Dictionary, "profile 构建成功")
	if not (r is Dictionary):
		return
	var types := {}
	for cd in (r as Dictionary)["chunks"]:
		var mesh: ArrayMesh = cd["mesh"]
		var pd: Dictionary = Picking.chunk_pick_data(cd)
		var soup: PackedVector3Array = pd["collision_faces"]
		var table: Array[Dictionary] = pd["face_table"]
		expect_eq(table.size() * 3, soup.size(), "face 表与三角形逐索引对应")
		# 逐位对账：soup 三角 = mesh 顶点三角按构建序、每面翻转 (a,c,b)
		var manual := PackedVector3Array()
		var manual_faces: Array[Dictionary] = []
		for si in (cd["surfaces"] as Array).size():
			manual.append_array(mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
			manual_faces.append_array((cd["surfaces"] as Array)[si]["faces"])
		expect_eq(soup.size(), manual.size(), "soup 与 mesh 顶点数一致")
		var flip_ok := true
		for t in soup.size() / 3:
			if not (soup[t * 3] == manual[t * 3] and soup[t * 3 + 1] == manual[t * 3 + 2] \
					and soup[t * 3 + 2] == manual[t * 3 + 1]):
				flip_ok = false
				break
		expect(flip_ok, "soup 每三角 = mesh 三角翻转 (a,c,b)（Godot 正面口径）")
		expect_eq(table, manual_faces, "face 表 = surfaces faces 按构建序拼接")
		for f in table:
			types[String(f.get("edge_type", ""))] = true
			# kind 三值合同不随 profile 改变（resolve_face 三分支路由的前提）
			expect(f["kind"] == "top" or f["kind"] == "edge" or f["kind"] == "corner",
				"kind 恒三值（新面型只细化 edge_type）")
	expect(types.has(Builder.EDGE_TERRACE), "face 表含 terrace 面型")
	expect(types.has(Builder.EDGE_CLIFF_WALL), "face 表含 cliff_wall 面型")
	# resolve_hit 越界 → null（新面数下保持）
	var cd0: Dictionary = (r as Dictionary)["chunks"][0]
	var pd0: Dictionary = Picking.chunk_pick_data(cd0)
	var table0: Array[Dictionary] = pd0["face_table"]
	expect(Picking.resolve_hit(Vector3.ZERO, table0.size(), table0, map, SIZE) == null,
		"face_index 越界 → null（新面数下合同保持）")
	expect(Picking.resolve_hit(Vector3.ZERO, -1, table0, map, SIZE) == null,
		"face_index=-1 → null")

# ================= 高亮贴合（footprint 口径，修订记录三之 8）=================

func test_highlight_footprint_fit_on_terraced_map() -> void:
	# 矩阵图 + profile：① 每格顶面恒平（拍板不扰动 → 采样锚点公式不变的地基）；
	# ② cell_surface_anchor = 格心 + elevation×step（恰在顶面平面）；
	# ③ 扇面 y = 顶面 + lift 恒高于 footprint 覆盖位置地表（中心顶面口径——高亮
	#   只盖内顶面）；④ 无非顶面顶点进入任何格 inner hexagon XZ 内部（riser/崖壁
	#   不上探扇 footprint——「扇 y 高于其覆盖位置地表」的几何面）。
	var map := Fixtures.build_matrix(3)
	var r: Variant = Builder.build_map(map, 10, 10, Lib.materials_from_colors(Lib.DEFAULT_PALETTE),
		SIZE, 1.0, SOLID, ProfileClass.make_default())
	expect(r is Dictionary, "profile 构建成功")
	if not (r is Dictionary):
		return
	var tops_by_cell := {}
	for cd in (r as Dictionary)["chunks"]:
		var mesh: ArrayMesh = cd["mesh"]
		for si in (cd["surfaces"] as Array).size():
			var sd: Dictionary = (cd["surfaces"] as Array)[si]
			var vv: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var faces: Array = sd["faces"]
			for fi in faces.size():
				var f: Dictionary = faces[fi]
				if f["kind"] == "top":
					for vi in 3:
						var y := vv[fi * 3 + vi].y
						var key: Vector2i = f["cell"]
						if not tops_by_cell.has(key):
							tops_by_cell[key] = y
						elif absf(float(tops_by_cell[key]) - y) > 1e-9:
							fail("顶面不恒平 %s（拍板不扰动 → 锚点公式不变的前提被破坏）" % str(key))
	expect_eq(tops_by_cell.size(), map.cell_count(), "每格都有顶面")
	for cell in map.cells():
		var want := float(map.elevation_at(cell))
		expect_almost_eq(float(tops_by_cell[cell]), want, 1e-9,
			"格 %s 顶面 y = elevation×step" % str(cell))
		# ② CellSurfaceSampler 最小版合同（LAND-03 ②）：格心 + elevation×step（无 lift）
		var anchor := Highlight.cell_surface_anchor(map, cell, SIZE, 1.0)
		expect_almost_eq(anchor.y, want, 1e-9, "cell_surface_anchor 恰在顶面平面")
		# ③ 高亮扇 y（cell_top_y）恒高于 footprint 覆盖位置地表（= 本格顶面）
		var fan_y := Highlight.cell_top_y(map, cell, 1.0)
		expect(fan_y > want, "扇面 y 恒高于其覆盖位置地表（%s）" % str(cell))
	# ④ inner hexagon 内无非顶面顶点（riser/崖壁/角面不进扇 footprint）——定位失败
	# 样本以便归因（首个入侵点）
	var offender: Variant = null
	for cd in (r as Dictionary)["chunks"]:
		var mesh: ArrayMesh = cd["mesh"]
		for si in (cd["surfaces"] as Array).size():
			var sd: Dictionary = (cd["surfaces"] as Array)[si]
			var vv: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var faces: Array = sd["faces"]
			for fi in faces.size():
				var f: Dictionary = faces[fi]
				if f["kind"] == "top":
					continue
				for vi in 3:
					if _inside_any_inner_hexagon(map, vv[fi * 3 + vi]):
						offender = {"face": f, "p": vv[fi * 3 + vi]}
	expect(offender == null,
		"riser/崖壁/角面顶点不进入任何格 inner hexagon XZ 内部（footprint 无穿插；首个入侵 %s）" % str(offender))

## 点是否**实质位于某格 inner hexagon（solid_factor 内六边形）XZ 内部**。定位口径：
## 内六边形 ⊂ 该格 Voronoi 域 → world_to_axial 圆整格即唯一候选。边距余量 1e-3：
## 跨视角同物理点（内顶点）在 float32 大坐标下有 ~1e-5 路径差（170 → 2^-23·170），
## 贴合不属入侵；真实穿插（riser 切入顶面）为 0.1 量级——隔两个数量级。
func _inside_any_inner_hexagon(map: MapDataClass, p: Vector3) -> bool:
	var cell := Hex.world_to_axial(Vector3(p.x, 0.0, p.z), SIZE)
	if not map.has_cell(cell):
		return false
	var ctr := Hex.axial_to_world(cell, SIZE)
	for d in 6:
		var a := Hex.inner_vertex(cell, d, SIZE, SOLID, 0.0)
		var b := Hex.inner_vertex(cell, (d + 1) % 6, SIZE, SOLID, 0.0)
		var e := Vector2(b.x - a.x, b.z - a.z)
		var n := Vector2(ctr.x - a.x, ctr.z - a.z)  # 格心在内部侧
		var s := Vector2(p.x - a.x, p.z - a.z)
		var cross_s := e.x * s.y - e.y * s.x
		var cross_n := e.x * n.y - e.y * n.x
		var signed_dist := cross_s * signf(cross_n) / maxf(e.length(), 1e-9)
		if signed_dist <= 1e-3:
			return false  # 在该边上/外侧（含贴合容差）→ 非实质内部
	return true

# ---- 辅助 ----

func _lerp_centers(a: Vector2i, b: Vector2i, t: float) -> Vector3:
	var ca := Hex.axial_to_world(a, SIZE)
	var cb := Hex.axial_to_world(b, SIZE)
	return ca + (cb - ca) * t
