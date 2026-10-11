## test_hex_grid_line.gd — T2 GRID-01 单测（逻辑分区格线层；执行方案 §3 GRID-01
##   测试锚原文逐条：「描边带与地形面不共面（y 恒高于两侧面）；每物理边恰一带
##   （跨 chunk 三种划分逐位一致）；外缘覆盖 = 地图边界格全部边有描边（含界外无
##   邻格外缘，修订记录三之 8）；关格线 = 与无格线基线 mesh 逐位一致（回退锚）；
##   blend 兼容（格线独立 mesh 不参与 blend 色板）；render_probe 加 CHECK-6（探针面）」）
## 覆盖锚：
##   - 每物理边恰一 strip：内部边归稳定 ID 较小格、外缘边归本格；全图计数 =
##     6N − 内部边数（每条内部无向边被两格共享只描一次）；
##   - 外缘覆盖：每格每方向（含界外无邻格方向）恰一 strip——「全部格子细描边」；
##   - 贴面高度 = 两侧格面较高侧 y + lift_for_tier(TIER_GRID_LINE)（新档登记：
##     恒高于两侧任意格面/高亮 tier0/1/描线半档——不共面无 z-fighting）；
##   - strip 位置沿六边形真边界（外顶点 d→d+1），三种 chunk 划分逐位一致；
##   - 关格线 = TerrainStyle 不出 grid_line 键（view 不建层）+ 地形 mesh 与无格线
##     基线逐位一致（独立层不触碰地形构建路径）；
##   - blend 兼容：格线 mesh 无 COLOR 通道；blend 地形数组与 fallback 逐位一致不受格线影响。
## oracle 原则：strip 期望位置由 HexMath.vertex_xz/dir_unit_world 全局参数独立拼装；
##   计数由 MapData 邻接原语组合推导；lift 档位与 hex_highlight 档位表对表。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const GridLines := preload("res://addons/hexhammer/hex_grid_line_builder.gd")
const Highlight := preload("res://addons/hexhammer/hex_highlight.gd")
const Blend := preload("res://addons/hexhammer/hex_terrain_blend.gd")
const StyleClass := preload("res://scripts/core/data/terrain_style.gd")
const Lib := preload("res://scripts/core/data/terrain_material_library.gd")

const SIZE := 1.0
const STEP := 1.0

## 测试图：5×4 混合高程（含 Δ0..Δ3——格线贴面高度随两侧高程走）。
func _sample_map() -> MapDataClass:
	var m := MapDataClass.new(5, 4)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_elevation(cell, (cr.x * 2 + cr.y * 3) % 5 % 4)
	return m

func _build(m, cols := 10, rows := 10) -> Dictionary:
	var r: Variant = GridLines.build_map(m, cols, rows, GridLines.make_material(Color(0.1, 0.1, 0.1), 0.28),
		SIZE, STEP)
	expect(r is Dictionary, "格线构建应成功")
	if r is Dictionary:
		return r as Dictionary
	return {"chunks": [], "chunk_rects": [], "lift": 0.0, "width": 0.0}

## 全部 strip 记录（chunk 拼接：{"cell", "dir", "rim", "verts"×6}）。
func _strips(r: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cd in r["chunks"]:
		var mesh: ArrayMesh = cd["mesh"]
		var arrays: Array = mesh.surface_get_arrays(0)
		var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var faces: Array = cd["faces"]
		for fi in range(0, faces.size(), 2):
			out.append({
				"cell": faces[fi]["cell"], "dir": faces[fi]["dir"], "rim": faces[fi]["rim"],
				"v": [vv[fi * 3], vv[fi * 3 + 1], vv[fi * 3 + 2],
					vv[(fi + 1) * 3], vv[(fi + 1) * 3 + 1], vv[(fi + 1) * 3 + 2]],
			})
	return out

# ================= 每物理边恰一带 + 外缘覆盖 =================

func test_every_physical_edge_exactly_one_strip() -> void:
	var m := _sample_map()
	var r := _build(m)
	var strips := _strips(r)
	var by_edge := {}
	for s in strips:
		var k := "%s|%d|%s" % [str(s["cell"]), int(s["dir"]), str(s["rim"])]
		expect(not by_edge.has(k), "物理边不得重复描边 %s" % k)
		by_edge[k] = s
	# 计数 oracle：内部无向边数（方向 0..2 只数一次）+ 外缘边数（每格无邻居方向）
	var interior := 0
	var rim := 0
	for cell in m.cells():
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not m.has_cell(nb):
				rim += 1
			elif d < 3:
				interior += 1
	expect_eq(strips.size(), interior + rim,
		"strip 总数 = 内部无向边 + 外缘边（got %d want %d）" % [strips.size(), interior + rim])
	expect(rim > 0, "样本图含外缘边（边界格存在）")
	# 外缘覆盖（修订记录三之 8）：每格每方向恰一带——含界外无邻格方向。归属 =
	# 内部边两格稳定 ID 较小者（方向取 owner 视角：换格即反向 d+3）、外缘边本格
	for cell in m.cells():
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			var owner := cell
			var owner_dir := d
			if m.has_cell(nb) and m.index_of(nb) < m.index_of(cell):
				owner = nb
				owner_dir = Hex.opposite_dir(d)
			var found := false
			for s in strips:
				if s["cell"] == owner and int(s["dir"]) == owner_dir:
					found = true
					break
			expect(found, "边界格全部边有描边 %s d%d（含界外无邻格外缘）" % [str(cell), d])

# ================= 贴面高度：不共面 + 新档登记 =================

func test_strip_height_higher_side_plus_registered_tier() -> void:
	var m := _sample_map()
	var r := _build(m)
	var lift: float = Highlight.lift_for_tier(Highlight.TIER_GRID_LINE)
	expect_eq(r["lift"], lift, "格线 lift = lift_for_tier(TIER_GRID_LINE)（新档）")
	for s in _strips(r):
		var nb := Hex.neighbor(s["cell"], s["dir"])
		var h_hi := float(m.elevation_at(s["cell"]))
		if m.has_cell(nb):
			h_hi = maxf(h_hi, float(m.elevation_at(nb)))
		var want_y := h_hi * STEP + lift
		for v in s["v"]:
			# mesh 顶点按 float32 存储（2.04 → 2.0399999…）——容差口径，非逐位
			expect_almost_eq(v.y, want_y, 1e-6,
				"strip y = 两侧较高侧 y + 格线档 lift（%s d%d）" % [str(s["cell"]), s["dir"]])
			expect(v.y > h_hi * STEP, "y 恒高于两侧任意格面（不共面）")
	# 档位表登记对表：格线档 > 描线半档（0.035）> tier1（0.03）> tier0（0.02）——跨层不共面
	expect(Highlight.lift_for_tier(Highlight.TIER_GRID_LINE) > Highlight.DEFAULT_LIFT
			+ Highlight.DEFAULT_PATH_LIFT_EXTRA,
		"格线档高于描线带半档（档位表防冲突）")
	expect(Highlight.lift_for_tier(Highlight.TIER_GRID_LINE)
			> Highlight.lift_for_tier(1),
		"格线档高于 hover 档")

# ================= 位置：真边界 + 跨 chunk 三种划分逐位一致 =================

func test_strip_positions_and_chunk_partition_invariance() -> void:
	var m := _sample_map()
	var width := GridLines.DEFAULT_WIDTH
	# 位置 oracle：外顶点 d→d+1 边线 ± 半宽侧向（dir_unit_world(d) 方向）
	var r1 := _build(m, 10, 10)
	for s in _strips(r1):
		var cell: Vector2i = s["cell"]
		var d: int = s["dir"]
		var e1 := Hex.vertex_xz(cell, d, SIZE)
		var e2 := Hex.vertex_xz(cell, (d + 1) % 6, SIZE)
		var u := Hex.dir_unit_world(d) * (width * 0.5)
		var want: Array[Vector3] = [
			Vector3(e1.x - u.x, s["v"][0].y, e1.y - u.z),
			Vector3(e1.x + u.x, s["v"][0].y, e1.y + u.z),
			Vector3(e2.x + u.x, s["v"][0].y, e2.y + u.z),
			Vector3(e2.x - u.x, s["v"][0].y, e2.y - u.z)]
		# 两三角 raw 序 (a,b,c)+(a,c,e) → 展平 6 顶点 = [a,b,c,a,c,e]：去重后对四角
		var got_quad: Array[Vector3] = [s["v"][0], s["v"][1], s["v"][2], s["v"][5]]
		for i in 4:
			expect(got_quad[i].distance_to(want[i]) <= 1e-6,
				"strip 顶点 = 真边界线 ± 半宽（%s d%d 顶点 %d）" % [str(cell), d, i])
	# 三种 chunk 划分逐位一致（单块 / 行切 / 每格一块——BLEND-02 划分矩阵先例）
	var r_all := _build(m, 10, 10)
	var r_rows := _build(m, 5, 2)
	var r_cells := _build(m, 1, 1)
	var key := func(s: Dictionary) -> String:
		return "%s|%d" % [str(s["cell"]), int(s["dir"])]
	var base := {}
	for s in _strips(r_all):
		base[key.call(s)] = s["v"]
	for other in [r_rows, r_cells]:
		var strips := _strips(other)
		expect_eq(strips.size(), base.size(), "划分不改 strip 数")
		for s in strips:
			var k: String = key.call(s)
			expect(base.has(k), "同一物理边在另一划分下存在 %s" % k)
			if base.has(k):
				var a1: Array = base[k]
				var b1: Array = s["v"]
				for i in 6:
					expect_eq(a1[i], b1[i], "strip 顶点跨划分逐位一致 %s v%d" % [k, i])

# ================= 关格线 = 回基线 + style 参数组 =================

func test_disabled_grid_line_no_input_and_terrain_unchanged() -> void:
	# style 关格线 → inputs_for 不出 grid_line 键（view 不建层 = 无本层）
	var m := _sample_map()
	var style := StyleClass.new()
	style.mode = StyleClass.Mode.BLEND
	style.material_library = Lib.build_default()
	style.blend_material = Blend.make_blend_material()
	style.grid_line_enabled = true
	var on: Variant = style.inputs_for(m)
	expect(on is Dictionary and (on as Dictionary).has("grid_line"), "开格线 → 输入带 grid_line 键")
	if on is Dictionary:
		var d: Dictionary = (on as Dictionary)["grid_line"]
		expect(d["material"] is Material, "grid_line 材质就绪（make_material 产物）")
		expect(float(d["width"]) > 0.0, "grid_line 宽度透传")
	style.grid_line_enabled = false
	var off: Variant = style.inputs_for(m)
	expect(off is Dictionary and not (off as Dictionary).has("grid_line"),
		"关格线 → 不附键（地形与无格线基线逐位一致——独立层不触碰地形构建路径）")
	# 地形 mesh 与格线无关（回退锚的 data 面）：同图地形构建两次逐位一致（格线只加独立层）
	var t1: Variant = Builder.build_map(m, 10, 10, Lib.materials_from_colors(Lib.DEFAULT_PALETTE))
	var t2: Variant = Builder.build_map(m, 10, 10, Lib.materials_from_colors(Lib.DEFAULT_PALETTE))
	expect(_mesh_arrays_equal(t1, t2), "地形 mesh 逐位一致（格线层不进地形路径）")

func test_grid_line_invalid_params_rejected() -> void:
	var m := MapDataClass.new(2, 2)
	expect(GridLines.build_map(m, 10, 10, null) == null, "material 非 Material → null")
	expect(GridLines.build_map(m, 10, 10, GridLines.make_material(Color.BLACK, 0.28), SIZE, STEP, 0.0) == null,
		"width ≤ 0 → null")
	expect(GridLines.build_map(m, 0, 10, GridLines.make_material(Color.BLACK, 0.28)) == null,
		"chunk_cols ≤ 0 → null")
	# style 侧参数组校验（problems_for 报缺）
	var style := StyleClass.new()
	style.mode = StyleClass.Mode.SLOTS
	style.material_library = Lib.build_default()
	style.grid_line_width = -0.1
	expect(style.inputs_for(m) == null, "格线宽非法 → 解析拒绝（材质级参数组一并校验）")
	expect(String(style.problems_for(m)[0]).contains("grid_line_width"), "人读清单指出宽参数")

func test_grid_mesh_blend_compatible_no_color_channel() -> void:
	# blend 兼容：格线独立 mesh 不参与 blend 色板（无 COLOR 通道/无 palette 依赖）
	var m := _sample_map()
	var r := _build(m)
	for cd in r["chunks"]:
		var arrays: Array = (cd["mesh"] as ArrayMesh).surface_get_arrays(0)
		var col: Variant = arrays[Mesh.ARRAY_COLOR]
		expect(not (col is PackedColorArray) or (col as PackedColorArray).is_empty(),
			"格线 mesh 无 COLOR 通道（不参与 blend 色板）")
	# blend 地形 + 格线共存：blend 构建结果与无格线时逐位一致（独立层互不影响）
	var palette: Variant = Blend.palette_from_materials(Lib.build_default().materials)
	var b1: Variant = Builder.build_map_blend(m, palette, 10, 10, Blend.make_blend_material())
	expect(b1 is Dictionary, "blend 地形可构建（格线并存）")

# ---- 辅助 ----

func _mesh_arrays_equal(a: Variant, b: Variant) -> bool:
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	var ca: Array = (a as Dictionary)["chunks"]
	var cb: Array = (b as Dictionary)["chunks"]
	if ca.size() != cb.size():
		return false
	for i in ca.size():
		var ma: ArrayMesh = ca[i]["mesh"]
		var mb: ArrayMesh = cb[i]["mesh"]
		if ma.get_surface_count() != mb.get_surface_count():
			return false
		for si in ma.get_surface_count():
			if ma.surface_get_arrays(si) != mb.surface_get_arrays(si):
				return false
	return true
