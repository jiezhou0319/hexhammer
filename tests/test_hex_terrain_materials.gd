## test_hex_terrain_materials.gd — M1a-T8 材质槽体系契约单测（headless）
## 逐条覆盖 04 任务卡 M1a-T8「验收 + 细化」的可自动化部分：
##   - 映射表 ↔ 渲染管线契约：表缺图内地形 id / 表值非 Material → 显式 null（无隐式
##     兜底）；surface 材质 = 表内共享实例（跨 chunk/surface 同类型同实例）；
##     结果 materials 表 = 恰好被用到的类型（echo 输入表实例，不合成新材质）；
##   - 资源化（.tres）：默认库可载入、覆盖 DEFAULT_PALETTE 全部 id、逐类型与
##     build_default() 同色（.tres 与代码默认口径同源——防口径漂移）；贴图试验库
##     可载入且 0/1/2 槽带贴图（美术分支载体的 headless 冒烟）；
##   - 「换贴图不改主线」接口断言：同一图、两张表（色块 vs 贴图）两次构建，
##     全部 chunk/surface 的顶点/法线/UV/索引逐位一致、faces 元数据一致，
##     仅材质引用不同——换库若动了几何/UV 即红线（美术并行分支的合并门）；
##   - UV 约定锚（T8 定死，细则见 hex_terrain_builder.gd 头注与
##     docs/notes/m1a-t8-art-branch.md）：水平面（顶面/平连边带/等高角落）= 世界平面
##     映射 u=x/2R、v=−z/2R；侧面（|Δh|≥1 边带）u=边切向投影/2R、v=−y/2R；
##     非等高角落 u=x/2R、v=−y/2R；
##   - 法线硬边策略：面内三顶点法线逐位一致（全 flat shading 全硬边，无平滑）。
## oracle 原则：UV 期望值一律由 HexMath 世界坐标 + 约定公式独立重算（不复制
##   builder 的 _uv_* 实现）；面法线期望 = cross 归一（16-bit 量化容差 1e-3）。
## 浮点断言口径（沿用 test_hex_terrain_builder.gd 头注）：UV float32 容差 1e-6。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Lib := preload("res://scripts/core/data/terrain_material_library.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")

const SIZE := 1.0
const UV_EPS := 1e-6
const NORMAL_EPS := 1e-3

# ================= 默认 .tres 库 ↔ 代码默认口径同源 =================

func test_default_library_resource_matches_palette() -> void:
	var lib := Lib.load_default()
	expect(lib != null, "主线默认库 .tres 应可载入（resources/terrain/terrain_materials_default.tres）")
	if lib == null:
		return
	var code := Lib.build_default()
	for tid in Lib.DEFAULT_PALETTE:
		var mat := lib.material_for(tid)
		expect(mat is StandardMaterial3D, "默认库类型 %s 应为 StandardMaterial3D（色块起步）" % tid)
		if mat is StandardMaterial3D:
			expect_eq((mat as StandardMaterial3D).albedo_color, Lib.DEFAULT_PALETTE[tid],
				"默认库颜色 = DEFAULT_PALETTE（%s）" % tid)
			expect_eq((mat as StandardMaterial3D).vertex_color_use_as_albedo, false,
				"色块路线不开顶点色 albedo（%s）" % tid)
		var code_mat := code.material_for(tid)
		expect(code_mat != null, "build_default() 应含类型 %s 槽" % tid)
		if mat is StandardMaterial3D and code_mat is StandardMaterial3D:
			expect_eq((mat as StandardMaterial3D).albedo_color, (code_mat as StandardMaterial3D).albedo_color,
				".tres 与 build_default() 逐类型同色（%s——防两处默认口径漂移）" % tid)

func test_textured_trial_library_loads() -> void:
	var lib := Lib.load_at(Lib.TRIAL_TEXTURED_PATH)
	expect(lib != null, "贴图试验库 .tres 应可载入（美术分支产物示例）")
	if lib == null:
		return
	for tid in [0, 1, 2, 3, 4, 5]:
		expect(lib.has_material(tid), "贴图试验库应含类型 %d 槽" % tid)
	for tid in [0, 1, 2]:
		var mat := lib.material_for(tid)
		if mat is StandardMaterial3D:
			var tex: Texture2D = (mat as StandardMaterial3D).albedo_texture
			expect(tex != null, "贴图试验库类型 %d 应带 albedo_texture（换贴图即所见的载体）" % tid)
			if tex != null:
				expect(String(tex.resource_path).begins_with("res://art_tests/"),
					"类型 %d 贴图指向 art_tests 试验素材（got %s）" % [tid, tex.resource_path])
	for tid in [3, 4, 5]:
		var mat2 := lib.material_for(tid)
		if mat2 is StandardMaterial3D:
			expect((mat2 as StandardMaterial3D).albedo_texture == null,
				"贴图试验库类型 %d 保持色块（同表混用贴图/色块合法）" % tid)

# ================= 映射表 ↔ 渲染管线契约 =================

func test_material_table_missing_id_fails_explicitly() -> void:
	var m := MapDataClass.new(4, 3)
	m.set_terrain(Hex.axial_of(Vector2i(1, 1)), 9)
	expect(Builder.build_map(m, 10, 10, _default_table()) == null,
		"表缺图内地形 9 → 显式 null（无隐式兜底槽）")
	expect(Builder.build_map(m, 10, 10, {}) == null,
		"空表 + 非空图 → null（管线不再自带默认色板——T8 起表是唯一来源）")

func test_material_table_non_material_value_fails() -> void:
	var ok := MapDataClass.new(2, 2)
	expect(Builder.build_map(ok, 10, 10, {0: Color(1, 1, 1)}) == null,
		"表值非 Material（Color）→ null")

func test_surface_materials_shared_from_table() -> void:
	var table := Lib.materials_from_colors({
		0: Color(0.9, 0.1, 0.1),
		1: Color(0.1, 0.1, 0.9),
		2: Color(0.1, 0.9, 0.1),
	})
	var m := MapDataClass.new(20, 10)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_terrain(cell, (cr.x * 3 + cr.y * 5) % 3)
	var r: Variant = Builder.build_map(m, 10, 10, table)
	expect(r is Dictionary, "build_map 应成功")
	if not (r is Dictionary):
		return
	var rd: Dictionary = r
	expect_eq((rd["chunks"] as Array).size(), 2, "20×10 → 两 chunk")
	var used := {}
	for chunk_info in rd["chunks"]:
		var cd: Dictionary = chunk_info
		var mesh: ArrayMesh = cd["mesh"]
		for i in (cd["surfaces"] as Array).size():
			var s: Dictionary = cd["surfaces"][i]
			var tid: int = s["terrain"]
			used[tid] = true
			expect(mesh.surface_get_material(i) == table[tid],
				"surface 材质 = 表内该类型共享实例（chunk %s 类型 %d）" % [str(cd["chunk"]), tid])
	var echo: Dictionary = rd["materials"]
	expect_eq(echo.size(), used.size(), "结果表 = 恰好被用到的类型数（不混入未用槽）")
	for tid in echo:
		expect(echo[tid] == table[tid], "结果表 echo 输入表实例（类型 %d）" % tid)
	# 未用槽不进结果表（6 槽全表只用到 3 类）
	var full := Lib.materials_from_colors({0: Color(1, 1, 1), 1: Color(0, 0, 0),
		2: Color(0.5, 0.5, 0.5), 7: Color(0.2, 0.2, 0.2)})
	var m2 := MapDataClass.new(4, 2)
	for cell in m2.cells():
		var cr := Hex.offset_of(cell)
		m2.set_terrain(cell, 0 if cr.x < 2 else 2)
	var r2: Variant = Builder.build_map(m2, 10, 10, full)
	expect(r2 is Dictionary, "带未用槽的表应可构建")
	if r2 is Dictionary:
		var echo2: Dictionary = (r2 as Dictionary)["materials"]
		expect_eq(echo2.size(), 2, "只 echo 被用到的 2 类（未用槽 1/7 不进结果）")
		expect(not echo2.has(7), "未用槽 7 不在结果表")

func test_retype_changes_surface_membership() -> void:
	var table := Lib.materials_from_colors({0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9)})
	var m := MapDataClass.new(2, 1)
	var a := Hex.axial_of(Vector2i(0, 0))
	var b := Hex.axial_of(Vector2i(1, 0))
	m.set_terrain(a, 0)
	m.set_terrain(b, 1)
	var r1 := _build_table_ok(m, table)
	m.set_terrain(a, 1)
	m.set_terrain(b, 0)
	var r2 := _build_table_ok(m, table)
	var want_a: Array[Vector2i] = [a]
	var want_b: Array[Vector2i] = [b]
	expect_eq(r1["chunks"][0]["surfaces"][0]["terrain"], 0, "首 surface = 首现类型 0")
	expect_eq(r1["chunks"][0]["surfaces"][0]["cells"], want_a, "类型 0 的格 = a")
	expect_eq(r1["chunks"][0]["surfaces"][1]["cells"], want_b, "类型 1 的格 = b")
	expect_eq(r2["chunks"][0]["surfaces"][0]["terrain"], 1, "换类型后首 surface = 类型 1")
	expect_eq(r2["chunks"][0]["surfaces"][0]["cells"], want_a, "a 换到类型 1 组")
	expect_eq(r2["chunks"][0]["surfaces"][1]["cells"], want_b, "b 换到类型 0 组")

# ================= 换表不变量（「换贴图不改主线」的接口断言）=================

func test_swap_material_table_geometry_bitwise_identical() -> void:
	var m := MapDataClass.new(6, 4)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_terrain(cell, (cr.x + cr.y) % 3)
		m.set_elevation(cell, (cr.x * 2 + cr.y * 3) % 3 - 1)  # −1..1：平/坡混合
	var color_table := Lib.materials_from_colors({
		0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9), 2: Color(0.1, 0.9, 0.1),
	})
	var tex_lib := Lib.load_at(Lib.TRIAL_TEXTURED_PATH)
	expect(tex_lib != null, "贴图试验库应可载入")
	if tex_lib == null:
		return
	for tid in [0, 1, 2]:
		expect(tex_lib.material_for(tid) != color_table[tid],
			"前置：两张表类型 %d 材质为不同实例（断言有意义的前提）" % tid)
	var r1 := _build_table_ok(m, color_table, 4, 3)
	var r2 := _build_table_ok(m, tex_lib.materials, 4, 3)
	expect_eq((r1["chunks"] as Array).size(), (r2["chunks"] as Array).size(), "chunk 数一致")
	for i in (r1["chunks"] as Array).size():
		var mesh1: ArrayMesh = r1["chunks"][i]["mesh"]
		var mesh2: ArrayMesh = r2["chunks"][i]["mesh"]
		expect_eq(mesh1.get_surface_count(), mesh2.get_surface_count(), "surface 数一致（chunk %d）" % i)
		for si in mesh1.get_surface_count():
			var a1: Array = mesh1.surface_get_arrays(si)
			var a2: Array = mesh2.surface_get_arrays(si)
			expect_eq(a1[Mesh.ARRAY_VERTEX], a2[Mesh.ARRAY_VERTEX],
				"换表后顶点逐位一致（chunk %d surface %d——换贴图不得动几何）" % [i, si])
			expect_eq(a1[Mesh.ARRAY_NORMAL], a2[Mesh.ARRAY_NORMAL],
				"换表后法线逐位一致（chunk %d surface %d）" % [i, si])
			expect_eq(a1[Mesh.ARRAY_TEX_UV], a2[Mesh.ARRAY_TEX_UV],
				"换表后 UV 逐位一致（chunk %d surface %d——UV 约定与材质表解耦）" % [i, si])
			expect_eq(a1[Mesh.ARRAY_INDEX], a2[Mesh.ARRAY_INDEX],
				"换表后索引逐位一致（chunk %d surface %d）" % [i, si])
			expect_eq(r1["chunks"][i]["surfaces"][si]["faces"], r2["chunks"][i]["surfaces"][si]["faces"],
				"换表后 faces 元数据一致（chunk %d surface %d——T5 拾取面表不受换表影响）" % [i, si])
			var tid: int = r1["chunks"][i]["surfaces"][si]["terrain"]
			expect(mesh1.surface_get_material(si) == color_table[tid],
				"色块构建的 surface 材质 = 色块表实例（chunk %d surface %d）" % [i, si])
			expect(mesh2.surface_get_material(si) == tex_lib.material_for(tid),
				"贴图构建的 surface 材质 = 贴图表实例（chunk %d surface %d——唯一差异面）" % [i, si])
			expect(mesh1.surface_get_material(si) != mesh2.surface_get_material(si),
				"两次构建材质不同（chunk %d surface %d）" % [i, si])

# ================= UV 约定锚（T8 定死）=================

func test_uv_top_face_world_planar_anchor() -> void:
	var m := MapDataClass.new(3, 2)
	var cell := Hex.axial_of(Vector2i(2, 1))  # 非原点格：锚定「世界」平面而非格心平面
	var r := _build_table_ok(m, _default_table())
	var top_faces := _faces_of(r, func(f): return f["kind"] == "top" and f["cell"] == cell)
	expect_eq(top_faces.size(), 6, "该格顶面 6 面")
	var checked := 0
	for f in top_faces:
		for j in 3:
			var v: Vector3 = f["verts"][j]
			var uv: Vector2 = f["uvs"][j]
			expect_almost_eq(uv.x, v.x / (2.0 * SIZE), UV_EPS, "顶面 UV u = x/2R（世界平面）")
			expect_almost_eq(uv.y, -v.z / (2.0 * SIZE), UV_EPS, "顶面 UV v = −z/2R")
			checked += 1
	expect_eq(checked, 18, "18 顶点全核")
	# 单格原点锚：1×1 图格心 = 世界原点 → 格心 UV 恰 (0,0)（旧 T3 格心 (0.5,0.5) 口径作废）
	var m1 := MapDataClass.new(1, 1)
	var r1 := _build_table_ok(m1, _default_table())
	var arr: Array = (r1["chunks"][0]["mesh"] as ArrayMesh).surface_get_arrays(0)
	var uvs1: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	for k in 6:
		expect_eq(uvs1[k * 3], Vector2(0.0, 0.0), "原点格心 UV = (0,0)（世界平面锚）")

func test_uv_flat_band_planar_anchor() -> void:
	var m := MapDataClass.new(2, 1)
	var r := _build_table_ok(m, _default_table())
	var bands := _faces_of(r, func(f): return f["kind"] == "edge")
	expect_eq(bands.size(), 2, "2×1 恰 2 边带面（等高 → 平连）")
	for f in bands:
		expect_eq(f["edge_type"], Builder.EDGE_FLAT, "等高 → 平连")
		for j in 3:
			var v: Vector3 = f["verts"][j]
			var uv: Vector2 = f["uvs"][j]
			expect_almost_eq(uv.x, v.x / (2.0 * SIZE), UV_EPS, "平连带 UV u = x/2R（与顶面同轴）")
			expect_almost_eq(uv.y, -v.z / (2.0 * SIZE), UV_EPS, "平连带 UV v = −z/2R（整图连续平铺）")

func test_uv_slope_band_side_anchor() -> void:
	var m := MapDataClass.new(2, 1)
	var a := Hex.axial_of(Vector2i(0, 0))
	m.set_elevation(Hex.neighbor(a, 0), 1)  # Δ1 → 斜坡
	var r := _build_table_ok(m, _default_table())
	var slopes := _faces_of(r, func(f): return f["kind"] == "edge" and f["edge_type"] == Builder.EDGE_SLOPE)
	expect_eq(slopes.size(), 2, "恰 2 斜坡面")
	var tangent := Hex.edge_tangent_world(0)
	for f in slopes:
		expect_eq(f["dir"], 0, "斜坡带方向 = 0（a→b 东）")
		for j in 3:
			var v: Vector3 = f["verts"][j]
			var uv: Vector2 = f["uvs"][j]
			expect_almost_eq(uv.x, (v.x * tangent.x + v.z * tangent.z) / (2.0 * SIZE), UV_EPS,
				"斜坡 UV u = 边切向投影/2R（HexMath.edge_tangent_world）")
			expect_almost_eq(uv.y, -v.y / (2.0 * SIZE), UV_EPS, "斜坡 UV v = −y/2R（竖向跟高程）")
	# v 跨度锚：低端 y=0 → v=0；高端 y=1 → v=−0.5（Δ1 半纹）
	var vs := []
	for f in slopes:
		for j in 3:
			vs.append(f["verts"][j].y)
	expect_almost_eq(vs.max(), 1.0, 1e-6, "斜坡高端 y=1")
	expect_almost_eq(vs.min(), 0.0, 1e-6, "斜坡低端 y=0")

func test_uv_cliff_band_side_anchor() -> void:
	var m := MapDataClass.new(2, 1)
	var a := Hex.axial_of(Vector2i(0, 0))
	m.set_elevation(Hex.neighbor(a, 0), 2)  # Δ2 → 陡面
	var r := _build_table_ok(m, _default_table())
	var cliffs := _faces_of(r, func(f): return f["kind"] == "edge" and f["edge_type"] == Builder.EDGE_CLIFF)
	expect_eq(cliffs.size(), 2, "恰 2 陡面")
	var tangent := Hex.edge_tangent_world(0)
	for f in cliffs:
		for j in 3:
			var v: Vector3 = f["verts"][j]
			var uv: Vector2 = f["uvs"][j]
			expect_almost_eq(uv.x, (v.x * tangent.x + v.z * tangent.z) / (2.0 * SIZE), UV_EPS,
				"陡面 UV u = 边切向投影/2R")
			expect_almost_eq(uv.y, -v.y / (2.0 * SIZE), UV_EPS,
				"陡面 UV v = −y/2R（Δ2 = 恰一整纹 [−1,0]）")
	# v 跨度锚：Δ2 陡壁竖向恰一个 [0,−1] 纹理域
	var v_min := 1e9
	var v_max := -1e9
	for f in cliffs:
		for j in 3:
			v_min = minf(v_min, f["uvs"][j].y)
			v_max = maxf(v_max, f["uvs"][j].y)
	expect_almost_eq(v_max, 0.0, UV_EPS, "陡壁上沿 v = 0")
	expect_almost_eq(v_min, -1.0, UV_EPS, "陡壁下沿 v = −1（一整纹）")

func test_uv_corner_flat_planar_and_mixed_side_anchor() -> void:
	var m := MapDataClass.new(3, 3)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_elevation(cell, 1 if (cr.x == 1 and cr.y == 1) else 0)  # 中心抬 1 层
	var r := _build_table_ok(m, _default_table())
	var flat_checked := 0
	var mixed_checked := 0
	for f in _all_faces(r):
		if f["kind"] != "corner":
			continue
		var cell: Vector2i = f["cell"]
		var k: int = f["dir"]
		var trio := [m.elevation_at(cell), m.elevation_at(Hex.neighbor(cell, k)),
			m.elevation_at(Hex.neighbor(cell, k - 1))]
		var flat_corner: bool = trio[0] == trio[1] and trio[0] == trio[2]
		for j in 3:
			var v: Vector3 = f["verts"][j]
			var uv: Vector2 = f["uvs"][j]
			if flat_corner:
				expect_almost_eq(uv.x, v.x / (2.0 * SIZE), UV_EPS, "等高角落 UV u = x/2R（平面）")
				expect_almost_eq(uv.y, -v.z / (2.0 * SIZE), UV_EPS, "等高角落 UV v = −z/2R（平面）")
				flat_checked += 1
			else:
				expect_almost_eq(uv.x, v.x / (2.0 * SIZE), UV_EPS, "非等高角落 UV u = x/2R（平面 u）")
				expect_almost_eq(uv.y, -v.y / (2.0 * SIZE), UV_EPS, "非等高角落 UV v = −y/2R（跟高程）")
				mixed_checked += 1
	expect(flat_checked > 0, "应有等高角落样本（got %d）" % flat_checked)
	expect(mixed_checked > 0, "应有非等高角落样本（got %d）" % mixed_checked)

# ================= 法线硬边策略（全 flat shading、无平滑）=================

func test_hard_edge_face_normals_within_face() -> void:
	var m := MapDataClass.new(5, 4)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_elevation(cell, (cr.x * 2 + cr.y * 3) % 5 - 2)  # −2..2：三档连接齐备
	var r := _build_table_ok(m, _default_table())
	var faces := 0
	var tilted := 0
	for f in _all_faces(r):
		var n0: Vector3 = f["norms"][0]
		expect_eq(f["norms"][1], n0, "面内三顶点法线逐位一致（硬边：同面同法线）%s" % _face_label(f))
		expect_eq(f["norms"][2], n0, "面内三顶点法线逐位一致（顶点 2）%s" % _face_label(f))
		# 显式类型：Variant 表达式不可推断（项目口径，见 map_data.gd 同注）
		var expected: Vector3 = (f["verts"][1] - f["verts"][0]).cross(f["verts"][2] - f["verts"][0]).normalized()
		_expect_vec3_eq_eps(n0, expected, NORMAL_EPS, "面法线 = cross 归一（不平滑、不平均）%s" % _face_label(f))
		if f["kind"] == "top":
			_expect_vec3_eq_eps(n0, Vector3(0, 1, 0), NORMAL_EPS, "顶面法线恒 +Y（平整不扰动）")
		elif String(f.get("edge_type", "")) != Builder.EDGE_FLAT and f["kind"] == "edge":
			expect(n0.y < 1.0, "斜坡/陡面法线应倾斜（独立面法线，未被顶面平滑拉平）%s" % _face_label(f))
			tilted += 1
		faces += 1
	expect(faces > 100, "样本量足够（got %d）" % faces)
	expect(tilted > 0, "应有斜坡/陡面样本（got %d）" % tilted)

# ---- 辅助 ----

func _default_table() -> Dictionary:
	return Lib.materials_from_colors(Lib.DEFAULT_PALETTE)

## build_map 断言成功（直传材质表——保持实例身份供共享断言）并返回 Dictionary。
func _build_table_ok(m, table: Dictionary, chunk_cols := 10, chunk_rows := 10) -> Dictionary:
	var r: Variant = Builder.build_map(m, chunk_cols, chunk_rows, table)
	expect(r is Dictionary, "build_map 应成功（返回 Dictionary）")
	if r is Dictionary:
		return r as Dictionary
	return {"chunks": [], "chunk_rects": [], "materials": {}}

## 全局面记录（顶点/UV/法线三元组 + 面元数据；faces 序 = 三角序 = 顶点序）。
func _all_faces(r: Dictionary) -> Array[Dictionary]:
	return _faces_of(r, func(_f): return true)

## 按谓词过滤的面记录。
func _faces_of(r: Dictionary, pred: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ci in (r["chunks"] as Array).size():
		var cd: Dictionary = r["chunks"][ci]
		var mesh: ArrayMesh = cd["mesh"]
		for si in (cd["surfaces"] as Array).size():
			var sd: Dictionary = cd["surfaces"][si]
			var arrays: Array = mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var faces: Array = sd["faces"]
			for fi in faces.size():
				var f: Dictionary = faces[fi]
				var rec := {
					"chunk": ci, "surface": si, "face": fi,
					"kind": f["kind"], "cell": f["cell"], "dir": f["dir"],
					"edge_type": f.get("edge_type", ""),
					"verts": [verts[fi * 3], verts[fi * 3 + 1], verts[fi * 3 + 2]],
					"uvs": [uvs[fi * 3], uvs[fi * 3 + 1], uvs[fi * 3 + 2]],
					"norms": [norms[fi * 3], norms[fi * 3 + 1], norms[fi * 3 + 2]],
				}
				if pred.call(rec):
					out.append(rec)
	return out

func _face_label(f: Dictionary) -> String:
	return "%s|%s|dir%s" % [f["kind"], str(f["cell"]), str(f["dir"])]

## Vector3 容差比对（欧氏距离；16-bit 法线量化 → 1e-3）。
func _expect_vec3_eq_eps(a: Vector3, b: Vector3, eps: float, msg: String) -> void:
	_checks += 1
	if a.distance_to(b) > eps:
		_fails.append("%s：got=%s want=%s eps=%s" % [msg, str(a), str(b), str(eps)])
