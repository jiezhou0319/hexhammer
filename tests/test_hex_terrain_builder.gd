## test_hex_terrain_builder.gd — M1a-T3 平地网格 + M1a-T4 几何重构后的单测（headless 断言几何不变量）
## 覆盖 04 任务卡 M1a-T3「验收 + 细化新增」在 T4 几何下的对应物：
##   - chunk 划分恰好覆盖（60×40=24 块 / 尾块裁剪 / 非法参数显式空）；
##   - 单格几何锚（顶面三角扇顶点顺序/法线/UV——T4 起顶点 = 内顶点，外圈留给连接带；
##     UV = T8 世界平面约定，侧面/角落/换表不变量锚见 test_hex_terrain_materials.gd）；
##   - 每 chunk 按地形类型组织 surface（不每格一个 surface）+ faces 元数据与 mesh 一一对应；
##   - 材质槽（M1a-T8 资源化：{terrain_id: Material} 表、表内共享实例、缺槽显式失败——
##     契约专项见 test_hex_terrain_materials.gd）；
##   - 相邻 chunk 接缝无错位（T4 口径：跨 chunk 边带/角落归属唯一 + 顶点逐位 = 全局公式）；
##   - 60×40 平地全量不变量（面数 oracle / 全顶点 y=0 / 绕序朝上 / 恰好覆盖一次）；
##   - 构建确定性；构建器纯逻辑（无场景节点）；缺色表/非法参数显式失败。
## 高程组合矩阵/归属规则/随机图流形不变量见 test_hex_terrain_elevation.gd（T4 专项）。
## oracle 原则：几何期望值一律由 T1 HexMath（inner_vertex/bridge_xz）独立拼装对账；
##   面数期望由 MapData 邻接原语组合计数（内部边 = 每格只数方向 0/1/2 的界内邻居——
##   方向 d 与 d+3 是同一条无向边，故恰数一次；内部角 = 三格各计一次后除 3），
##   不复制 builder 的稳定 ID 归属实现。
## 浮点断言口径（T3 实测定标沿用）：同路径比对逐位相等（顶点来自同一全局公式、
##   无 chunk 局部偏移/扰动）；跨路径（不同格视角同一物理点，表达式不同）容差 1e-5；
##   法线 16-bit 量化容差 1e-3；UV float32 容差 1e-6。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Lib := preload("res://scripts/core/data/terrain_material_library.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")

# ================= chunk 划分 =================

func test_chunk_partition_exact_cover_60x40() -> void:
	var rects := Builder.chunk_rects_for(60, 40, 10, 10)
	expect_eq(rects.size(), 24, "60×40 / 10×10 = 24 chunk")
	var covered := {}
	for rect in rects:
		expect(rect.position.x >= 0 and rect.position.y >= 0, "chunk 原点非负 %s" % rect)
		expect(rect.position.x + rect.size.x <= 60, "chunk 右界 ≤ 60 %s" % rect)
		expect(rect.position.y + rect.size.y <= 40, "chunk 下界 ≤ 40 %s" % rect)
		for row in range(rect.position.y, rect.position.y + rect.size.y):
			for col in range(rect.position.x, rect.position.x + rect.size.x):
				var key := Vector2i(col, row)
				expect(not covered.has(key), "chunk 划分重叠 %s" % key)
				covered[key] = true
	expect_eq(covered.size(), 2400, "划分恰好无遗漏覆盖全图")

func test_chunk_partition_clipped_remainder() -> void:
	var rects := Builder.chunk_rects_for(25, 13, 10, 10)
	expect_eq(rects.size(), 6, "25×13 / 10×10 = 3×2 chunk（尾块裁剪）")
	var covered := {}
	for rect in rects:
		for row in range(rect.position.y, rect.position.y + rect.size.y):
			for col in range(rect.position.x, rect.position.x + rect.size.x):
				covered[Vector2i(col, row)] = true
	expect_eq(covered.size(), 325, "尾块裁剪后恰好覆盖")
	var last := rects[rects.size() - 1]
	expect_eq(last.position, Vector2i(20, 10), "尾块起点 (20,10)")
	expect_eq(last.size, Vector2i(5, 3), "尾块尺寸 5×3（右/下裁剪）")

func test_chunk_partition_empty_when_invalid() -> void:
	expect_eq(Builder.chunk_rects_for(0, 40, 10, 10).size(), 0, "空图无划分")
	expect_eq(Builder.chunk_rects_for(60, 40, 0, 10).size(), 0, "chunk 宽 ≤0 无划分（显式空，不出半张图）")
	expect_eq(Builder.chunk_rects_for(60, 40, 10, -1).size(), 0, "chunk 高 ≤0 无划分")

# ================= 单格几何锚（顶面三角扇：顶点顺序 / 法线 / UV）=================

func test_single_cell_top_fan_anchor() -> void:
	var m := MapDataClass.new(1, 1)
	var r: Variant = Builder.build_map(m, 10, 10, _default_table())
	expect(r is Dictionary, "1×1 图应可构建")
	if not (r is Dictionary):
		return
	var rd: Dictionary = r
	expect_eq((rd["chunks"] as Array).size(), 1, "单 chunk")
	var chunk: Dictionary = rd["chunks"][0]
	expect_eq((chunk["surfaces"] as Array).size(), 1, "同地形单 surface")
	var s: Dictionary = chunk["surfaces"][0]
	expect_eq(s["face_counts"], {"top": 6, "edge": 0, "corner": 0},
		"1×1 无邻居：只有顶面 6 面，无边带无角落（T2 界外无连接）")
	var mesh: ArrayMesh = chunk["mesh"]
	expect_eq(mesh.get_surface_count(), 1, "ArrayMesh surface 数 = 1")
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	expect_eq(verts.size(), 18, "6 面 × 3 顶点（逐面 emit）")
	expect_eq(idx.size(), 18, "6 面 × 3 索引")
	# 索引 = 逐面 (3f, 3f+2, 3f+1) 翻转（F-1 修复 2026-10-10：索引三角 = 俯视顺时针
	# = Godot 正面；faces 序 = raw soup 三角序不变——T5 face_index→格映射的地基）
	expect_eq(idx, _flipped_indices(6), "索引序 = 逐面翻转（Godot 正面口径）")
	var cell := Vector2i(0, 0)
	var center := Hex.axial_to_world(cell)
	# 面 k 顶点锚：(格心, inner_k, inner_{k+1})——逐位 = HexMath 全局公式（同一参数路径）
	for k in 6:
		expect_eq(verts[k * 3 + 0], center, "面%d v0 = 格心" % k)
		expect_eq(verts[k * 3 + 1], Hex.inner_vertex(cell, k),
			"面%d v1 = 内顶点 k（顶点向格心缩进）" % k)
		expect_eq(verts[k * 3 + 2], Hex.inner_vertex(cell, (k + 1) % 6),
			"面%d v2 = 内顶点 k+1（三角扇）" % k)
	# 内顶点距格心 = solid_factor·size（内六边形口径锚）
	var sf: float = Builder.DEFAULT_SOLID_FACTOR
	for k in 6:
		expect_almost_eq((Hex.inner_vertex(cell, k) - center).length(), sf, 1e-6,
			"内顶点距格心 = solid_factor·size v%d" % k)
	# 法线恒 +Y（平顶；引擎提交链路 16-bit 量化 → 容差比对，见头注）
	for i in norms.size():
		_expect_vec3_eq_eps(norms[i], Vector3(0, 1, 0), 1e-3, "法线恒 +Y（顶点 %d）" % i)
	# UV 锚（T8 世界平面映射）：u = x/2R、v = −z/2R——1×1 图格心 = 世界原点 → (0,0)
	#（旧 T3「格心 (0.5,0.5)」口径随 T8 定约作废；逐类型侧面/角落锚在
	#  test_hex_terrain_materials.gd）
	for k in 6:
		expect_eq(uvs[k * 3], Vector2(0.0, 0.0), "面%d 格心（世界原点）UV = (0,0)" % k)
	for k in 6:
		var iv := Hex.inner_vertex(cell, k)
		expect_almost_eq(uvs[k * 3 + 1].x, iv.x / 2.0, 1e-6, "UV u = x/2R 面%d" % k)
		expect_almost_eq(uvs[k * 3 + 1].y, -iv.z / 2.0, 1e-6, "UV v = −z/2R 面%d" % k)
	# 绕序双层口径（F-1 修复 2026-10-10）：
	# ① raw 顶点 soup 几何序：每面 cross(B−A,C−A).y > 0（俯视逆时针——碰撞汤翻转
	#   与 face 表都锚 raw 序）；② 渲染索引三角：cross.y < 0（俯视顺时针 = Godot
	#   正面，CULL_BACK 下俯视可见——测试锚引擎语义而非实现巧合）
	for f in 6:
		var a := verts[f * 3]
		var b := verts[f * 3 + 1]
		var c := verts[f * 3 + 2]
		expect((b - a).cross(c - a).y > 0.0, "面 %d raw 几何序绕序朝上" % f)
		var ia := verts[idx[f * 3]]
		var ib := verts[idx[f * 3 + 1]]
		var ic := verts[idx[f * 3 + 2]]
		expect((ib - ia).cross(ic - ia).y < 0.0, "面 %d 索引三角 = Godot 正面（俯视顺时针）" % f)

# ================= 双格：唯一共享边带的归属与形状 =================

func test_two_cells_flat_bridge_owned_by_smaller_id() -> void:
	var m := MapDataClass.new(2, 1)
	var a := Hex.axial_of(Vector2i(0, 0))  # 稳定 ID 0
	var b := Hex.axial_of(Vector2i(1, 0))  # 稳定 ID 1
	var r := _build_ok(m)
	var faces := _collect_faces(r)
	var s: Dictionary = r["chunks"][0]["surfaces"][0]
	expect_eq(s["face_counts"], {"top": 12, "edge": 2, "corner": 0},
		"2×1：顶面 2×6；内部边 1 条 → 边带 2 面；无三格角 → 无角落面")
	var d_ab := Hex.dir_between(a, b)
	expect_eq(d_ab, 0, "a→b 为方向 0（东）")
	var edge_faces: Array[Dictionary] = []
	for f in faces:
		if f["kind"] == "edge":
			edge_faces.append(f)
	expect_eq(edge_faces.size(), 2, "恰 2 个边带面")
	for f in edge_faces:
		expect_eq(f["cell"], a, "边带归属 = 稳定 ID 较小者（a）")
		expect_eq(f["dir"], d_ab, "边带方向 = dir_between(a,b)")
		expect_eq(f["edge_type"], Builder.EDGE_FLAT, "等高 → 平连")
	# 边带顶点锚（同路径逐位）：v1/v2 = a 的内顶点，v3/v4 = +bridge（对面侧内顶点）
	var v1 := Hex.inner_vertex(a, d_ab)
	var v2 := Hex.inner_vertex(a, (d_ab + 1) % 6)
	var br := Hex.bridge_xz(a, d_ab, 1.0, Builder.DEFAULT_SOLID_FACTOR)
	var v3 := v1 + Vector3(br.x, 0.0, br.y)
	var v4 := v2 + Vector3(br.x, 0.0, br.y)
	expect_eq(edge_faces[0]["v0"], v1, "边带面0 v0 = a.inner_d")
	expect_eq(edge_faces[0]["v1"], v3, "边带面0 v1 = a.inner_d + bridge（b 侧端点）")
	expect_eq(edge_faces[0]["v2"], v4, "边带面0 v2 = a.inner_{d+1} + bridge")
	expect_eq(edge_faces[1]["v0"], v1, "边带面1 v0 = a.inner_d")
	expect_eq(edge_faces[1]["v1"], v4, "边带面1 v1 = b 侧端点")
	expect_eq(edge_faces[1]["v2"], v2, "边带面1 v2 = a.inner_{d+1}")
	# 跨路径对账（容差 1e-5，见头注）：v3/v4 数学上 = b 自己视角的内顶点
	_expect_vec3_eq_eps(v3, Hex.inner_vertex(b, (d_ab + 4) % 6), 1e-5, "v3 = b.inner_{(d+4)%6}")
	_expect_vec3_eq_eps(v4, Hex.inner_vertex(b, (d_ab + 3) % 6), 1e-5, "v4 = b.inner_{(d+3)%6}")
	for f in edge_faces:
		expect((f["v1"] - f["v0"]).cross(f["v2"] - f["v0"]).y > 0.0, "边带面绕序朝上")

# ================= surface 按地形类型组织（不每格一个 surface）=================

func test_surfaces_grouped_by_terrain_type() -> void:
	var m := MapDataClass.new(10, 10)
	_fill_terrain(m, 4)
	var r := _build_ok(m)
	var chunk: Dictionary = r["chunks"][0]
	var mesh: ArrayMesh = chunk["mesh"]
	expect_eq(mesh.get_surface_count(), 4, "10×10 单 chunk、4 地形 → 4 surface（不每格一 surface）")
	var total := 0
	var seen_cells := {}
	var e_oracle := _interior_edge_count(m)
	var c_oracle := _interior_corner_count(m)
	var top := 0
	var edge := 0
	var corner := 0
	for i in (chunk["surfaces"] as Array).size():
		var s: Dictionary = chunk["surfaces"][i]
		var cells: Array = s["cells"]
		total += cells.size()
		for cell in cells:
			expect_eq(m.terrain_at(cell), s["terrain"], "surface 分组应与地形一致 %s" % cell)
			expect(not seen_cells.has(cell), "格不得重复入组 %s" % cell)
			seen_cells[cell] = true
		# 元数据与 mesh 数组一致 + faces 序 = 三角序
		var arrays: Array = mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idxa: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var fc: Dictionary = s["face_counts"]
		top += fc["top"]
		edge += fc["edge"]
		corner += fc["corner"]
		expect_eq(verts.size(), s["vertex_count"], "元数据 vertex_count 与 mesh 一致（surface %d）" % i)
		expect_eq(idxa.size(), s["index_count"], "元数据 index_count 与 mesh 一致（surface %d）" % i)
		expect_eq(s["vertex_count"], (s["faces"] as Array).size() * 3,
			"逐面 emit：顶点数 = 3×面数（surface %d）" % i)
		expect_eq(idxa, _flipped_indices(idxa.size() / 3), "索引 = 逐面翻转（Godot 正面口径；surface %d）" % i)
		expect_eq(fc["top"] + fc["edge"] + fc["corner"], (s["faces"] as Array).size(),
			"面分类计数之和 = faces 总数（surface %d）" % i)
	expect_eq(total, 100, "分组覆盖全部 100 格")
	expect_eq(top, 600, "顶面 = 6×100")
	expect_eq(edge, e_oracle * 2, "边带面 = 2×内部边数 oracle（%d 条）" % e_oracle)
	expect_eq(corner, c_oracle, "角落面 = 内部角数 oracle（%d 个）" % c_oracle)
	# surface 序 = 地形首次出现序（chunk 行主序——MapData.cells 同序；T3 口径沿用）
	var first_order: Array = []
	var seen_types := {}
	for cell in m.cells():
		var t := m.terrain_at(cell)
		if not seen_types.has(t):
			seen_types[t] = true
			first_order.append(t)
	var got_order: Array = []
	for s in chunk["surfaces"]:
		got_order.append(s["terrain"])
	expect_eq(got_order, first_order, "surface 序 = 地形首次出现序")

# ================= 材质槽（表驱动；T8 资源化——契约专项见 test_hex_terrain_materials.gd）=================

func test_material_slots_from_table_by_terrain_type() -> void:
	var table := Lib.materials_from_colors({0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9)})
	var m := MapDataClass.new(4, 2)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_terrain(cell, 0 if cr.x < 2 else 1)
	var r := _build_ok(m, 10, 10, table)
	var chunk: Dictionary = r["chunks"][0]
	var mesh: ArrayMesh = chunk["mesh"]
	expect_eq(mesh.get_surface_count(), 2, "两类型 → 两 surface")
	for i in (chunk["surfaces"] as Array).size():
		var s: Dictionary = chunk["surfaces"][i]
		var tid: int = s["terrain"]
		var mat: Material = mesh.surface_get_material(i)
		expect(mat is StandardMaterial3D, "surface 材质为 StandardMaterial3D（surface %d）" % i)
		expect(mat == table[tid],
			"surface 材质 = 表内该类型实例（类型 %d——换类型即换槽、换表即换观感）" % tid)
		# 本路线不用顶点色显示地形：材质保持 vertex_color_use_as_albedo=false。
		# 04 M1a-T3 细化：若日后改顶点色路线，须显式开该属性（默认 false）——
		# 此断言把「当前走材质槽路线」定死，翻路线时随同显式改本锚。
		if mat is StandardMaterial3D:
			expect_eq((mat as StandardMaterial3D).vertex_color_use_as_albedo, false,
				"材质槽路线不开顶点色 albedo（surface %d）" % i)

func test_material_slots_shared_across_chunks() -> void:
	var table := Lib.materials_from_colors(_three_colors())
	var m := MapDataClass.new(20, 10)
	_fill_terrain(m, 3)
	var r := _build_ok(m, 10, 10, table)
	expect_eq((r["chunks"] as Array).size(), 2, "20×10 → 两 chunk")
	var mats: Dictionary = r["materials"]
	expect_eq(mats.size(), 3, "结果表恰好覆盖被用到的类型（echo 不混入未用槽）")
	for tid in mats:
		expect(mats[tid] == table[tid], "结果表 echo 输入表实例（类型 %d）" % tid)
	for chunk_info in r["chunks"]:
		var cd: Dictionary = chunk_info
		var mesh: ArrayMesh = cd["mesh"]
		for i in (cd["surfaces"] as Array).size():
			var s: Dictionary = cd["surfaces"][i]
			var tid: int = s["terrain"]
			expect(mesh.surface_get_material(i) == table[tid],
				"surface 用的是表内该类型的共享实例（chunk %s 类型 %d）" % [str(cd["chunk"]), tid])

func test_retype_changes_surface_membership() -> void:
	var table := Lib.materials_from_colors({0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9)})
	var m := MapDataClass.new(2, 1)
	var a := Hex.axial_of(Vector2i(0, 0))
	var b := Hex.axial_of(Vector2i(1, 0))
	m.set_terrain(a, 0)
	m.set_terrain(b, 1)
	var r1 := _build_ok(m, 10, 10, table)
	m.set_terrain(a, 1)
	m.set_terrain(b, 0)
	var r2 := _build_ok(m, 10, 10, table)
	var want_a: Array[Vector2i] = [a]
	var want_b: Array[Vector2i] = [b]
	# 换前：surface 序随类型首次出现 → [类型0(a), 类型1(b)]
	expect_eq(r1["chunks"][0]["surfaces"][0]["terrain"], 0, "首 surface = 首现类型 0")
	expect_eq(r1["chunks"][0]["surfaces"][0]["cells"], want_a, "类型 0 的格 = a")
	expect_eq(r1["chunks"][0]["surfaces"][1]["cells"], want_b, "类型 1 的格 = b")
	# 换后：同两格类型互换 → 分组跟着类型走（不是跟着位置走）
	expect_eq(r2["chunks"][0]["surfaces"][0]["terrain"], 1, "换类型后首 surface = 类型 1")
	expect_eq(r2["chunks"][0]["surfaces"][0]["cells"], want_a, "a 换到类型 1 组")
	expect_eq(r2["chunks"][0]["surfaces"][1]["cells"], want_b, "b 换到类型 0 组")

func test_missing_material_and_invalid_params_fail_explicitly() -> void:
	var table := _default_table()
	var m := MapDataClass.new(4, 3)
	m.set_terrain(Hex.axial_of(Vector2i(1, 1)), 9)
	expect(Builder.build_map(m, 10, 10, table) == null, "表缺图内地形 9 → 显式 null（无隐式兜底槽）")
	var m2 := MapDataClass.new(2, 2)
	m2.set_terrain(Hex.axial_of(Vector2i(0, 0)), 1)
	expect(Builder.build_map(m2, 10, 10, Lib.materials_from_colors({0: Color(1, 1, 1)})) == null,
		"单槽表缺类型 1 → 显式 null")
	expect(Builder.build_map(m2, 10, 10, {}) == null, "空表 + 非空图 → null（T8 起表是唯一来源）")
	expect(Builder.build_map(m2, 10, 10, {0: Color(1, 1, 1)}) == null, "表值非 Material → null")
	# T4 几何参数非法 → 显式失败（不静默出退化几何；表合法——失败归因明确）
	var ok := MapDataClass.new(4, 4)
	expect(Builder.build_map(ok, 10, 10, table, 1.0, 0.0) == null, "elevation_step ≤ 0 → null")
	expect(Builder.build_map(ok, 10, 10, table, 0.0) == null, "size ≤ 0 → null")
	expect(Builder.build_map(ok, 10, 10, table, 1.0, 1.0, 1.0) == null, "solid_factor ≥ 1（全六边形无连接带）→ null")
	expect(Builder.build_map(ok, 10, 10, table, 1.0, 1.0, 0.0) == null, "solid_factor ≤ 0（顶面退化为点）→ null")
	var full: Variant = Builder.build_map(ok, 10, 10, table)
	expect(full is Dictionary, "4×4 默认图应可构建")
	if full is Dictionary:
		expect(Builder.build_chunk(ok, Rect2i(100, 100, 5, 5), (full as Dictionary)["materials"]) == null,
			"空矩形（图外 chunk）→ null")

# ================= 相邻 chunk 接缝（T4 口径：归属唯一 + 同一全局参数）=================

func test_seam_unique_and_bitwise_two_chunks_horizontal() -> void:
	var m := MapDataClass.new(20, 10)
	_fill_terrain(m, 3)
	var r := _build_ok(m, 10, 10, Lib.materials_from_colors(_three_colors()))
	expect_eq((r["chunks"] as Array).size(), 2, "20×10 → 左右两 chunk")
	var seam_faces := _expect_inventory_and_return_seam_faces(r, m)
	expect(seam_faces >= 16, "水平接缝跨块边带面 ≥ 16（每行 ≥2 条跨界边 ×2 面 ×10 行），got %d" % seam_faces)

func test_seam_unique_and_bitwise_two_chunks_vertical() -> void:
	var m := MapDataClass.new(10, 20)
	_fill_terrain(m, 3)
	var r := _build_ok(m, 10, 10, Lib.materials_from_colors(_three_colors()))
	expect_eq((r["chunks"] as Array).size(), 2, "10×20 → 上下两 chunk")
	var seam_faces := _expect_inventory_and_return_seam_faces(r, m)
	expect(seam_faces >= 16, "垂直接缝跨块边带面 ≥ 16，got %d" % seam_faces)

func test_seam_unique_and_bitwise_four_chunks() -> void:
	var m := MapDataClass.new(20, 20)
	_fill_terrain(m, 3)
	var r := _build_ok(m, 10, 10, Lib.materials_from_colors(_three_colors()))
	expect_eq((r["chunks"] as Array).size(), 4, "20×20 → 2×2 chunk")
	var seam_faces := _expect_inventory_and_return_seam_faces(r, m)
	expect(seam_faces >= 32, "四块交汇接缝跨块边带面 ≥ 32，got %d" % seam_faces)
	# 顺带核对：2×2 分块恰好覆盖 400 格一次（每格只属一个 chunk/surface）
	var owner := {}
	for chunk_info in r["chunks"]:
		for s in chunk_info["surfaces"]:
			for cell in s["cells"]:
				expect(not owner.has(cell), "格被重复覆盖 %s" % cell)
				owner[cell] = true
	expect_eq(owner.size(), 400, "四 chunk 恰好覆盖 20×20")

# ================= 60×40 平地全量不变量 =================

func test_60x40_flat_build_full_invariants() -> void:
	var m := MapDataClass.new(60, 40)
	_fill_terrain(m, 5)
	var r := _build_ok(m)
	expect_eq((r["chunks"] as Array).size(), 24, "60×40 / 10×10 = 24 chunk")
	var e_oracle := _interior_edge_count(m)
	var c_oracle := _interior_corner_count(m)
	var cell_owner := {}
	var top := 0
	var edge := 0
	var corner := 0
	var per_cell_top := {}
	for chunk_info in r["chunks"]:
		var cd: Dictionary = chunk_info
		var mesh: ArrayMesh = cd["mesh"]
		var surfaces: Array = cd["surfaces"]
		expect_eq(mesh.get_surface_count(), surfaces.size(), "mesh surface 数与元数据一致 %s" % str(cd["chunk"]))
		for si in surfaces.size():
			var s: Dictionary = surfaces[si]
			var arrays: Array = mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var fc: Dictionary = s["face_counts"]
			top += fc["top"]
			edge += fc["edge"]
			corner += fc["corner"]
			var cells: Array = s["cells"]
			for cell in cells:
				expect(not cell_owner.has(cell), "格被多 chunk/surface 重复覆盖 %s" % cell)
				cell_owner[cell] = true
			# 平地：全顶点 y=0 + 法线 +Y（全量逐顶点）+ 每面绕序朝上
			for vi in verts.size():
				expect_eq(verts[vi].y, 0.0, "平地 y=0（T3 验收沿用）%s" % str(cd["chunk"]))
				_expect_vec3_eq_eps(norms[vi], Vector3(0, 1, 0), 1e-3, "平地法线 +Y %s" % str(cd["chunk"]))
			for fi in (s["faces"] as Array).size():
				var a := verts[fi * 3]
				var b := verts[fi * 3 + 1]
				var c := verts[fi * 3 + 2]
				expect((b - a).cross(c - a).y > 0.0, "面绕序朝上 %s 面%d" % [str(cd["chunk"]), fi])
			# 每格顶面恰 6 面（faces 元数据逐格核对）
			for f in s["faces"]:
				if f["kind"] == "top":
					per_cell_top[f["cell"]] = int(per_cell_top.get(f["cell"], 0)) + 1
	expect_eq(cell_owner.size(), 2400, "全图 2400 格恰好覆盖一次")
	expect_eq(per_cell_top.size(), 2400, "每格都有顶面")
	for cell in per_cell_top:
		expect_eq(per_cell_top[cell], 6, "每格顶面恰 6 面 %s" % cell)
	expect_eq(top, 2400 * 6, "顶面总面数 = 14400")
	expect_eq(edge, e_oracle * 2, "边带总面数 = 2×内部边 oracle（%d）" % e_oracle)
	expect_eq(corner, c_oracle, "角落总面数 = 内部角 oracle（%d）" % c_oracle)

func test_build_deterministic_same_arrays() -> void:
	var m := MapDataClass.new(30, 20)
	_fill_terrain(m, 4)
	var r1 := _build_ok(m)
	var r2 := _build_ok(m)
	expect_eq((r1["chunks"] as Array).size(), (r2["chunks"] as Array).size(), "两次构建 chunk 数一致")
	for i in (r1["chunks"] as Array).size():
		var mesh1: ArrayMesh = r1["chunks"][i]["mesh"]
		var mesh2: ArrayMesh = r2["chunks"][i]["mesh"]
		expect_eq(mesh1.get_surface_count(), mesh2.get_surface_count(), "两次构建 surface 数一致")
		for si in mesh1.get_surface_count():
			var arr1: Array = mesh1.surface_get_arrays(si)
			var arr2: Array = mesh2.surface_get_arrays(si)
			expect_eq(arr1[Mesh.ARRAY_VERTEX], arr2[Mesh.ARRAY_VERTEX],
				"两次构建顶点数组逐位一致（chunk %d surface %d）" % [i, si])
			expect_eq(arr1[Mesh.ARRAY_INDEX], arr2[Mesh.ARRAY_INDEX],
				"两次构建索引数组一致（chunk %d surface %d）" % [i, si])
			expect_eq(arr1[Mesh.ARRAY_TEX_UV], arr2[Mesh.ARRAY_TEX_UV],
				"两次构建 UV 一致（chunk %d surface %d）" % [i, si])
			expect_eq(r1["chunks"][i]["surfaces"][si]["faces"],
				r2["chunks"][i]["surfaces"][si]["faces"],
				"两次构建 faces 元数据一致（chunk %d surface %d）" % [i, si])

# ================= 纯逻辑（分层纪律）=================

func test_builder_pure_logic_no_nodes() -> void:
	var inst: Variant = Builder.new()
	expect(inst is RefCounted, "构建器实例为 RefCounted（ADR-2）")
	expect(not (inst is Node), "构建器不得为 Node")
	var m := MapDataClass.new(2, 2)
	var r: Variant = Builder.build_map(m, 10, 10, _default_table())
	expect(r is Dictionary, "小图可构建")
	if r is Dictionary:
		_walk_no_nodes(r, 0)

# ---- 辅助 ----

## 固定模式铺类型：(col·3 + row·5) mod types（确定性、行主序无关）。
func _fill_terrain(m, types: int) -> void:
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_terrain(cell, (cr.x * 3 + cr.y * 5) % types)

func _three_colors() -> Dictionary:
	return {
		0: Color(0.9, 0.1, 0.1),
		1: Color(0.1, 0.1, 0.9),
		2: Color(0.1, 0.9, 0.1),
	}

## 默认材质表（与主线默认 .tres 同源——测试自建、不读文件，保持纯逻辑口径）。
func _default_table() -> Dictionary:
	return Lib.materials_from_colors(Lib.DEFAULT_PALETTE)

## 逐面翻转索引的期望数组（F-1 口径：每面 (3f, 3f+2, 3f+1)——索引三角俯视顺时针
## = Godot 正面；faces 序 = raw soup 三角序不变）。
func _flipped_indices(face_count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(face_count * 3)
	for f in face_count:
		out[f * 3] = f * 3
		out[f * 3 + 1] = f * 3 + 2
		out[f * 3 + 2] = f * 3 + 1
	return out

## build_map 断言成功并返回 Dictionary（第 4 参 = 材质表 {terrain_id: Material}，
## 缺省 = 默认表）；失败时回占位结构（后续断言优雅失败，不崩 runner）。
func _build_ok(m, chunk_cols := 10, chunk_rows := 10, materials := {}) -> Dictionary:
	var table := materials if not materials.is_empty() else _default_table()
	var r: Variant = Builder.build_map(m, chunk_cols, chunk_rows, table)
	expect(r is Dictionary, "build_map 应成功（返回 Dictionary）")
	if r is Dictionary:
		return r as Dictionary
	return {"chunks": [], "chunk_rects": [], "materials": {}}

## 内部边数 oracle（独立于 builder 归属实现）：方向 d 与 d+3 是同一条无向边，
## 每格只数方向 0/1/2 的界内邻居 → 每条无向内部边恰数一次。
func _interior_edge_count(m) -> int:
	var n := 0
	for cell in m.cells():
		for d in 3:
			if m.has_cell(Hex.neighbor(cell, d)):
				n += 1
	return n

## 内部角数 oracle：顶点 k 的三格（cell、N_k、N_{k-1}）全界内则计一次——
## 每个物理角落被三格各计一次，除 3。
func _interior_corner_count(m) -> int:
	var n := 0
	for cell in m.cells():
		for k in 6:
			if m.has_cell(Hex.neighbor(cell, k)) and m.has_cell(Hex.neighbor(cell, k - 1)):
				n += 1
	return n / 3

## 全局面记录（含顶点，faces 序 = 三角序）。
func _collect_faces(r: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ci in (r["chunks"] as Array).size():
		var cd: Dictionary = r["chunks"][ci]
		var mesh: ArrayMesh = cd["mesh"]
		for si in (cd["surfaces"] as Array).size():
			var sd: Dictionary = cd["surfaces"][si]
			var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var faces: Array = sd["faces"]
			for fi in faces.size():
				var f: Dictionary = faces[fi]
				out.append({
					"chunk": ci, "surface": si, "face": fi,
					"kind": f["kind"], "cell": f["cell"], "dir": f["dir"],
					"edge_type": f.get("edge_type", ""),
					"v0": verts[fi * 3], "v1": verts[fi * 3 + 1], "v2": verts[fi * 3 + 2],
				})
	return out

## 无向边 key（两格 axial 排序——归属无关的物理标识）。
func _edge_key(cell: Vector2i, dir: int) -> String:
	var b := Hex.neighbor(cell, dir)
	var pa := cell
	var pb := b
	if pb.x < pa.x or (pb.x == pa.x and pb.y < pa.y):
		var t := pa
		pa = pb
		pb = t
	return "e|%d,%d|%d,%d" % [pa.x, pa.y, pb.x, pb.y]

## 物理角 key（三格 axial 排序——归属无关的物理标识）。
func _corner_key(cell: Vector2i, k: int) -> String:
	var ids := ["%d,%d" % [cell.x, cell.y]]
	for nb in [Hex.neighbor(cell, k), Hex.neighbor(cell, k - 1)]:
		ids.append("%d,%d" % [nb.x, nb.y])
	ids.sort()
	return "c|" + "|".join(ids)

## 接缝三重断言（平地）：① 全图边/角物理 key 恰好一次（含跨 chunk——归属规则防重复面）；
## ② 跨块边带顶点逐位 = 全局公式（同一 HexMath 参数，无 chunk 局部扰动）；
## ③ 返回跨块边带面数（调用方据此断言接缝规模）。
func _expect_inventory_and_return_seam_faces(r: Dictionary, m) -> int:
	var faces := _collect_faces(r)
	var edge_faces := {}
	var corner_faces := {}
	for f in faces:
		if f["kind"] == "edge":
			var k := _edge_key(f["cell"], f["dir"])
			if not edge_faces.has(k):
				edge_faces[k] = [] as Array[Dictionary]
			(edge_faces[k] as Array[Dictionary]).append(f)
		elif f["kind"] == "corner":
			var k2 := _corner_key(f["cell"], f["dir"])
			if not corner_faces.has(k2):
				corner_faces[k2] = 0
			corner_faces[k2] = int(corner_faces[k2]) + 1
	# ① 恰好一次（边 = 恰 2 面，角 = 恰 1 面）+ 总数 = oracle
	expect_eq(edge_faces.size(), _interior_edge_count(m), "物理边总数 = oracle（跨 chunk 无缺无重）")
	for k in edge_faces:
		expect_eq((edge_faces[k] as Array).size(), 2, "每条内部边恰一条边带（2 面）%s" % k)
	expect_eq(corner_faces.size(), _interior_corner_count(m), "物理角总数 = oracle")
	for k in corner_faces:
		expect_eq(corner_faces[k], 1, "每个内部角恰一角落面 %s" % k)
	# ② 跨块边带顶点逐位锚
	var rects: Array = r["chunk_rects"]
	var seam := 0
	for k in edge_faces:
		var pair: Array[Dictionary] = edge_faces[k]
		var f0: Dictionary = pair[0]
		var cell: Vector2i = f0["cell"]
		var d: int = f0["dir"]
		var nb := Hex.neighbor(cell, d)
		var rect_a := _rect_of(rects, cell)
		var rect_b := _rect_of(rects, nb)
		if rect_a == rect_b:
			continue
		seam += 2
		# 顶点逐位 = 归属格视角全局公式（跨 chunk 同一参数源）
		var v1 := Hex.inner_vertex(cell, d)
		var v2 := Hex.inner_vertex(cell, (d + 1) % 6)
		var br := Hex.bridge_xz(cell, d, 1.0, Builder.DEFAULT_SOLID_FACTOR)
		var v3 := v1 + Vector3(br.x, 0.0, br.y)
		var v4 := v2 + Vector3(br.x, 0.0, br.y)
		expect_eq(f0["v0"], v1, "跨块边带 v0 = 全局公式 %s" % k)
		expect_eq(f0["v1"], v3, "跨块边带 v1 = 全局公式 %s" % k)
		expect_eq(f0["v2"], v4, "跨块边带 v2 = 全局公式 %s" % k)
		var f1: Dictionary = pair[1]
		expect_eq(f1["v0"], v1, "跨块边带第二面 v0 %s" % k)
		expect_eq(f1["v1"], v4, "跨块边带第二面 v1 %s" % k)
		expect_eq(f1["v2"], v2, "跨块边带第二面 v2 %s" % k)
	return seam

func _rect_of(rects: Array, cell: Vector2i) -> Rect2i:
	var off := Hex.offset_of(cell)
	for rect in rects:
		if (rect as Rect2i).has_point(off):
			return rect
	return Rect2i()

## Vector3 容差比对（欧氏距离）。
func _expect_vec3_eq_eps(a: Vector3, b: Vector3, eps: float, msg: String) -> void:
	_checks += 1
	if a.distance_to(b) > eps:
		_fails.append("%s：got=%s want=%s eps=%s" % [msg, str(a), str(b), str(eps)])

## 递归检查构建结果不含任何 Node（材质/mesh 均为 Resource）。
func _walk_no_nodes(v: Variant, depth: int) -> void:
	if v == null or depth > 8:
		return
	if v is Node:
		fail("构建结果含 Node：%s" % str(v))
	elif v is Dictionary:
		for x in (v as Dictionary).values():
			_walk_no_nodes(x, depth + 1)
	elif v is Array:
		for x in v:
			_walk_no_nodes(x, depth + 1)
