## test_hex_terrain_builder.gd — M1a-T3 平地网格渲染几何单测（headless 断言几何不变量）
## 逐条覆盖 04 任务卡 M1a-T3「验收 + 细化新增」的可自动化部分：
##   - 小图阶段核对顶点顺序/法线/UV（单格锚 + 小图全量）；
##   - 相邻 chunk 接缝顶点无错位（接缝顶点来自同一全局格心/边参数——对 HexMath 全局
##     公式 oracle + 跨块共享边端点逐位相等双重核对）；
##   - 60×40 生成成功（24 chunk / 全覆盖恰好一次 / 三角与顶点总数 / 全局坐标 / 平地 y=0）；
##   - 换类型即换色（材质槽映射被使用的断言：surface 材质 = 色表中该类型色/实例）；
##   - 每 chunk 按地形类型组织 surface（不每格一个 surface）；构建确定性；缺色表显式
##     失败；构建器纯逻辑（无场景节点）。
## 「60×40 平地渲染流畅」为目测项（主创），不在本文件——见任务卡。
## oracle 原则：几何期望值一律由 T1 HexMath（axial_to_world/cell_vertex/vertex_xz）独立
##   重算对账，不复制 builder 内部实现；两套来源不一致即 bug。
## 浮点断言口径（2026-10-09 实测定标，引擎 4.7.2 实测行为）：
##   - 同路径比对（mesh 读回值 vs 同一格同一顶点号的 HexMath 现算）逐位相等——保留精确
##     expect_eq，是最强锚：证明顶点来自同一全局公式、无 chunk 局部偏移/扰动；
##   - 跨路径比对（相邻两格各自算出同一物理共享顶点）：数学同点、浮点表达式不同
##     （A心+u(θ) vs B心+u(θ')），float32 截断差 ≤1 ulp（x≈17 处实测 ≤2e-6）→ 用容差
##     1e-5。T4 按任务卡「共享边由两格稳定 ID 较小者生成、接缝顶点从同一全局格心/边
##     参数计算」实现共享边参数后，此差自然消除、可收紧回精确比对；
##   - 法线：引擎在 mesh 提交链路对法线做 16-bit 量化（实测读回 (0,1,−1.5e-5)≈−1/65536）
##     → 容差 1e-3（仍能抓任何朝向级错误）；
##   - UV：存储为 float32（0.93 处 ulp≈6e-8，断言端为 double）→ 容差 1e-6。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
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

# ================= 单格几何锚（顶点顺序 / 法线 / UV） =================

func test_single_cell_vertex_order_normal_uv_anchor() -> void:
	var m := MapDataClass.new(1, 1)
	var r: Variant = Builder.build_map(m)
	expect(r is Dictionary, "1×1 图应可构建")
	if not (r is Dictionary):
		return
	var rd: Dictionary = r
	expect_eq((rd["chunks"] as Array).size(), 1, "单 chunk")
	var chunk: Dictionary = rd["chunks"][0]
	expect_eq((chunk["surfaces"] as Array).size(), 1, "同地形单 surface")
	var mesh: ArrayMesh = chunk["mesh"]
	expect_eq(mesh.get_surface_count(), 1, "ArrayMesh surface 数 = 1")
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	expect_eq(verts.size(), Builder.VERTS_PER_CELL, "单格顶点数 = 7")
	expect_eq(idx.size(), Builder.INDICES_PER_CELL, "单格索引数 = 18")
	# 顶点顺序锚：v0 = 格心；v1..v6 = HexMath.cell_vertex(0..5)（同一全局参数）
	var cell := Vector2i(0, 0)
	expect_eq(verts[0], Hex.axial_to_world(cell), "v0 = 格心")
	for k in 6:
		expect_eq(verts[1 + k], Hex.cell_vertex(cell, k),
			"顶点顺序：v%d 应 = HexMath.cell_vertex(cell,%d)" % [1 + k, k])
	# 索引顺序锚（六三角扇全显式——顶点顺序验收的定死锚，格式变更须显式改本锚）
	expect_eq(idx, PackedInt32Array([0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 5, 0, 5, 6, 0, 6, 1]),
		"索引序 = 三角扇 (格心, v_i, v_i+1)")
	# 法线：朝 +Y（平顶硬法线；引擎提交链路 16-bit 量化 → 容差比对，见头注）
	for i in norms.size():
		_expect_vec3_eq_eps(norms[i], Vector3(0, 1, 0), 1e-3, "法线恒 +Y（顶点 %d）" % i)
	# UV 锚：格心 (0.5,0.5)；顶点 k = u=0.5+x/2s、v=0.5−z/2s（格心在原点；float32 粒度 → 1e-6）
	expect_eq(uvs[0], Vector2(0.5, 0.5), "格心 UV = (0.5, 0.5)")
	for k in 6:
		var vx := Hex.vertex_xz(cell, k)
		expect_almost_eq(uvs[1 + k].x, 0.5 + vx.x / 2.0, 1e-6, "UV u 约定 v%d" % k)
		expect_almost_eq(uvs[1 + k].y, 0.5 - vx.y / 2.0, 1e-6, "UV v 约定（北零）v%d" % k)
	# 绕序：每三角 cross(B−A, C−A).y > 0（正面朝上）
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		expect((b - a).cross(c - a).y > 0.0, "三角形 %d 绕序应朝上" % t)

# ================= surface 按地形类型组织（不每格一个 surface） =================

func test_surfaces_grouped_by_terrain_type() -> void:
	var m := MapDataClass.new(10, 10)
	_fill_terrain(m, 4)
	var r := _build_ok(m)
	var chunk: Dictionary = r["chunks"][0]
	var mesh: ArrayMesh = chunk["mesh"]
	expect_eq(mesh.get_surface_count(), 4, "10×10 单 chunk、4 地形 → 4 surface（不每格一 surface）")
	var total := 0
	var seen_cells := {}
	for i in (chunk["surfaces"] as Array).size():
		var s: Dictionary = chunk["surfaces"][i]
		var cells: Array = s["cells"]
		total += cells.size()
		for cell in cells:
			expect_eq(m.terrain_at(cell), s["terrain"], "surface 分组应与地形一致 %s" % cell)
			expect(not seen_cells.has(cell), "格不得重复入组 %s" % cell)
			seen_cells[cell] = true
		# 元数据与 mesh 数组一致 + 每格固定 7 顶点 / 18 索引
		var arrays: Array = mesh.surface_get_arrays(i)
		expect_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), s["vertex_count"],
			"元数据 vertex_count 与 mesh 一致（surface %d）" % i)
		expect_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), s["index_count"],
			"元数据 index_count 与 mesh 一致（surface %d）" % i)
		expect_eq(s["vertex_count"], cells.size() * 7, "每格 7 顶点（surface %d）" % i)
		expect_eq(s["index_count"], cells.size() * 18, "每格 18 索引（surface %d）" % i)
	expect_eq(total, 100, "分组覆盖全部 100 格")
	# surface 序 = 地形首次出现序（chunk 行主序——MapData.cells 同序）
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
	# 顶点基址 = 7 × surface 内格序（连续无洞）
	for s in chunk["surfaces"]:
		var sd: Dictionary = s
		var cells: Array = sd["cells"]
		for ci in cells.size():
			expect_eq((sd["vertex_base"] as Dictionary)[cells[ci]], ci * 7,
				"顶点基址 = 7×格序 %s" % cells[ci])

# ================= 材质槽（换类型即换色） =================

func test_material_slots_color_by_terrain_type() -> void:
	var colors := {0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9)}
	var m := MapDataClass.new(4, 2)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_terrain(cell, 0 if cr.x < 2 else 1)
	var r := _build_ok(m, 10, 10, colors)
	var chunk: Dictionary = r["chunks"][0]
	var mesh: ArrayMesh = chunk["mesh"]
	expect_eq(mesh.get_surface_count(), 2, "两类型 → 两 surface")
	for i in (chunk["surfaces"] as Array).size():
		var s: Dictionary = chunk["surfaces"][i]
		var mat: Material = mesh.surface_get_material(i)
		expect(mat is StandardMaterial3D, "surface 材质为 StandardMaterial3D（surface %d）" % i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			expect_eq(sm.albedo_color, colors[s["terrain"]],
				"surface 材质色 = 色表中该类型色（类型 %d——换类型即换色）" % s["terrain"])
			# 本路线不用顶点色显示地形：材质保持 vertex_color_use_as_albedo=false。
			# 04 M1a-T3 细化：若日后改顶点色路线，须显式开该属性（默认 false）——
			# 此断言把「当前走材质槽路线」定死，翻路线时随同显式改本锚。
			expect_eq(sm.vertex_color_use_as_albedo, false,
				"材质槽路线不开顶点色 albedo（surface %d）" % i)

func test_material_slots_shared_across_chunks() -> void:
	var colors := {
		0: Color(0.9, 0.1, 0.1),
		1: Color(0.1, 0.1, 0.9),
		2: Color(0.1, 0.9, 0.1),
	}
	var m := MapDataClass.new(20, 10)
	_fill_terrain(m, 3)
	var r := _build_ok(m, 10, 10, colors)
	expect_eq((r["chunks"] as Array).size(), 2, "20×10 → 两 chunk")
	var mats: Dictionary = r["materials"]
	expect_eq(mats.size(), 3, "材质表恰好覆盖被用到的类型（映射被使用才建槽）")
	for chunk_info in r["chunks"]:
		var cd: Dictionary = chunk_info
		var mesh: ArrayMesh = cd["mesh"]
		for i in (cd["surfaces"] as Array).size():
			var s: Dictionary = cd["surfaces"][i]
			var tid: int = s["terrain"]
			expect(mesh.surface_get_material(i) == mats[tid],
				"surface 用的是材质表中该类型的共享实例（chunk %s 类型 %d）" % [str(cd["chunk"]), tid])
			var sm := mats[tid] as StandardMaterial3D
			expect_eq(sm.albedo_color, colors[tid], "跨 chunk 同类型同色（类型 %d）" % tid)

func test_retype_changes_surface_membership() -> void:
	var colors := {0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9)}
	var m := MapDataClass.new(2, 1)
	var a := Hex.axial_of(Vector2i(0, 0))
	var b := Hex.axial_of(Vector2i(1, 0))
	m.set_terrain(a, 0)
	m.set_terrain(b, 1)
	var r1 := _build_ok(m, 10, 10, colors)
	m.set_terrain(a, 1)
	m.set_terrain(b, 0)
	var r2 := _build_ok(m, 10, 10, colors)
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

func test_missing_color_mapping_fails_explicitly() -> void:
	var m := MapDataClass.new(4, 3)
	m.set_terrain(Hex.axial_of(Vector2i(1, 1)), 9)
	expect(Builder.build_map(m) == null, "默认色板缺类型 9 → 显式 null（无隐式兜底色）")
	var custom := {0: Color(1, 1, 1)}
	var m2 := MapDataClass.new(2, 2)
	m2.set_terrain(Hex.axial_of(Vector2i(0, 0)), 1)
	expect(Builder.build_map(m2, 10, 10, custom) == null, "自定义色板缺类型 1 → 显式 null")
	var empty_rect: Rect2i = Rect2i(100, 100, 5, 5)
	var m3 := MapDataClass.new(4, 4)
	var full: Variant = Builder.build_map(m3)
	expect(full is Dictionary, "4×4 默认图应可构建")
	if full is Dictionary:
		expect(Builder.build_chunk(m3, empty_rect, (full as Dictionary)["materials"]) == null,
			"空矩形（图外 chunk）→ null")

# ================= 相邻 chunk 接缝顶点无错位 =================

func test_seam_aligned_two_chunks_horizontal() -> void:
	var m := MapDataClass.new(20, 10)
	_fill_terrain(m, 3)
	var r := _build_ok(m, 10, 10, _three_colors())
	expect_eq((r["chunks"] as Array).size(), 2, "20×10 → 左右两 chunk")
	var pairs := _expect_seam_aligned(r, m, 0, 1)
	expect(pairs >= 10, "水平接缝相邻格对应 ≥ 10，got %d" % pairs)

func test_seam_aligned_two_chunks_vertical() -> void:
	var m := MapDataClass.new(10, 20)
	_fill_terrain(m, 3)
	var r := _build_ok(m, 10, 10, _three_colors())
	expect_eq((r["chunks"] as Array).size(), 2, "10×20 → 上下两 chunk")
	var pairs := _expect_seam_aligned(r, m, 0, 1)
	expect(pairs >= 10, "垂直接缝相邻格对应 ≥ 10，got %d" % pairs)

func test_seam_aligned_four_chunks_with_coverage() -> void:
	var m := MapDataClass.new(20, 20)
	_fill_terrain(m, 3)
	var r := _build_ok(m, 10, 10, _three_colors())
	expect_eq((r["chunks"] as Array).size(), 4, "20×20 → 2×2 chunk")
	# 四对相邻块全部核对（含四块交汇处两侧接缝线）
	var pairs := 0
	pairs += _expect_seam_aligned(r, m, 0, 1)
	pairs += _expect_seam_aligned(r, m, 0, 2)
	pairs += _expect_seam_aligned(r, m, 1, 3)
	pairs += _expect_seam_aligned(r, m, 2, 3)
	expect(pairs >= 40, "四块接缝相邻格对应 ≥ 40，got %d" % pairs)
	# 顺带核对：2×2 分块恰好覆盖 400 格一次（每格只属一个 chunk/surface）
	var owner := {}
	for chunk_info in r["chunks"]:
		for s in chunk_info["surfaces"]:
			for cell in s["cells"]:
				expect(not owner.has(cell), "格被重复覆盖 %s" % cell)
				owner[cell] = true
	expect_eq(owner.size(), 400, "四 chunk 恰好覆盖 20×20")

# ================= 60×40 生成成功（全量不变量） =================

func test_60x40_build_full_invariants() -> void:
	var m := MapDataClass.new(60, 40)
	_fill_terrain(m, 5)
	var r := _build_ok(m)
	expect_eq((r["chunks"] as Array).size(), 24, "60×40 / 10×10 = 24 chunk")
	var cell_owner := {}
	var tris := 0
	var verts_total := 0
	for chunk_info in r["chunks"]:
		var cd: Dictionary = chunk_info
		var mesh: ArrayMesh = cd["mesh"]
		var surfaces: Array = cd["surfaces"]
		expect_eq(mesh.get_surface_count(), surfaces.size(), "mesh surface 数与元数据一致 %s" % str(cd["chunk"]))
		for si in surfaces.size():
			var s: Dictionary = surfaces[si]
			var arrays: Array = mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idxa: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			expect_eq(verts.size(), s["vertex_count"], "数组顶点数与元数据一致 %s" % str(cd["chunk"]))
			expect_eq(idxa.size(), s["index_count"], "数组索引数与元数据一致 %s" % str(cd["chunk"]))
			tris += idxa.size() / 3
			verts_total += verts.size()
			var cells: Array = s["cells"]
			var vbase: Dictionary = s["vertex_base"]
			for cell in cells:
				expect(not cell_owner.has(cell), "格被多 chunk/surface 重复覆盖 %s" % cell)
				cell_owner[cell] = true
			# 全局坐标 oracle + 平地 y=0 + 法线 + UV（全量逐顶点核对；口径见头注）
			for cell in cells:
				var base: int = vbase[cell]
				var center := Hex.axial_to_world(cell)
				expect_eq(verts[base], center, "格心 = 全局格心（chunk 不做局部偏移）%s" % cell)
				expect_eq(verts[base].y, 0.0, "平地 y=0（T3 不读高程）%s" % cell)
				for k in 6:
					expect_eq(verts[base + 1 + k], Hex.cell_vertex(cell, k),
						"顶点 = 全局公式现算 %s v%d" % [cell, k])
					var vx := Hex.vertex_xz(cell, k)
					expect_almost_eq(uvs[base + 1 + k].x, 0.5 + (vx.x - center.x) / 2.0, 1e-6,
						"UV u 约定 %s v%d" % [cell, k])
					expect_almost_eq(uvs[base + 1 + k].y, 0.5 - (vx.y - center.z) / 2.0, 1e-6,
						"UV v 约定（北零）%s v%d" % [cell, k])
				for k in 7:
					_expect_vec3_eq_eps(norms[base + k], Vector3(0, 1, 0), 1e-3, "法线 +Y %s" % cell)
					expect_eq(verts[base + k].y, 0.0, "平地 y=0 %s v%d" % [cell, k])
	expect_eq(cell_owner.size(), 2400, "全图 2400 格恰好覆盖一次")
	expect_eq(tris, 2400 * 6, "总三角 = 14400（每格 6）")
	expect_eq(verts_total, 2400 * 7, "总顶点 = 16800（每格 7）")

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

# ================= 纯逻辑（分层纪律） =================

func test_builder_pure_logic_no_nodes() -> void:
	var inst: Variant = Builder.new()
	expect(inst is RefCounted, "构建器实例为 RefCounted（ADR-2）")
	expect(not (inst is Node), "构建器不得为 Node")
	var m := MapDataClass.new(2, 2)
	var r: Variant = Builder.build_map(m)
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

## build_map 断言成功并返回 Dictionary；失败时回占位结构（后续断言优雅失败，不崩 runner）。
func _build_ok(m, chunk_cols := 10, chunk_rows := 10, colors := {}) -> Dictionary:
	var r: Variant = Builder.build_map(m, chunk_cols, chunk_rows, colors)
	expect(r is Dictionary, "build_map 应成功（返回 Dictionary）")
	if r is Dictionary:
		return r as Dictionary
	return {"chunks": [], "chunk_rects": [], "materials": {}}

## chunk 内格子的顶点坐标（k = −1 → 格心；k = 0..5 → 顶点 k）。
func _vertex_at(chunk_info: Dictionary, cell: Vector2i, k: int) -> Vector3:
	var surfaces: Array = chunk_info["surfaces"]
	var mesh: ArrayMesh = chunk_info["mesh"]
	for i in surfaces.size():
		var s: Dictionary = surfaces[i]
		var vbase: Dictionary = s["vertex_base"]
		if vbase.has(cell):
			var verts: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			return verts[vbase[cell] + 1 + k]
	return Vector3(NAN, NAN, NAN)

## 核对 chunk ia / ib 接缝：A 的界内邻居落在 ib 时，共享边两端顶点比对。
## 双重口径（见头注「浮点断言口径」）：
##   ① 相互比对容差 1e-5——两侧浮点表达式不同，差 ≤1 ulp（T4 共享边参数后消除）；
##   ② 各侧 vs HexMath 全局公式逐位精确——证明每侧顶点都逐位来自同一全局公式
##      （同一全局格心/边参数、无 chunk 局部扰动——错位类 bug 在此被抓）。
## 共享边端点配对（由平移不变性推导，见头注）：A.v[d] ↔ B.v[(d+4)%6]、A.v[d+1] ↔ B.v[(d+3)%6]。
func _expect_seam_aligned(r: Dictionary, m, ia: int, ib: int) -> int:
	var ca: Dictionary = r["chunks"][ia]
	var cb: Dictionary = r["chunks"][ib]
	var rect_b: Rect2i = cb["chunk"]
	var checked := 0
	for s in ca["surfaces"]:
		for cell in s["cells"]:
			for d in 6:
				var n := Hex.neighbor(cell, d)
				if not m.has_cell(n) or not rect_b.has_point(Hex.offset_of(n)):
					continue
				var va1 := _vertex_at(ca, cell, d)
				var va2 := _vertex_at(ca, cell, (d + 1) % 6)
				var vb1 := _vertex_at(cb, n, (d + 4) % 6)
				var vb2 := _vertex_at(cb, n, (d + 3) % 6)
				_expect_vec3_eq_eps(va1, vb1, 1e-5, "接缝顶点错位：A=%s d=%d 端点1" % [cell, d])
				_expect_vec3_eq_eps(va2, vb2, 1e-5, "接缝顶点错位：A=%s d=%d 端点2" % [cell, d])
				expect_eq(va1, Hex.cell_vertex(cell, d),
					"A 侧接缝端点 ≠ HexMath 全局公式 %s v%d" % [cell, d])
				expect_eq(va2, Hex.cell_vertex(cell, (d + 1) % 6),
					"A 侧接缝端点 ≠ HexMath 全局公式 %s v%d" % [cell, (d + 1) % 6])
				expect_eq(vb1, Hex.cell_vertex(n, (d + 4) % 6),
					"B 侧接缝端点 ≠ HexMath 全局公式 %s v%d" % [n, (d + 4) % 6])
				expect_eq(vb2, Hex.cell_vertex(n, (d + 3) % 6),
					"B 侧接缝端点 ≠ HexMath 全局公式 %s v%d" % [n, (d + 3) % 6])
				checked += 1
	return checked

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
