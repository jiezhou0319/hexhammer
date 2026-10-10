## test_hex_terrain_blend.gd — M1a+ BLEND-01 单测（相邻两格颜色权重——过渡合同首证）
## 覆盖 docs/04-tasks-m1.md §M1a+ BLEND-01 验收（Given/When/Then）的 headless 锚：
##   - 权重合同（纯逻辑，hex_terrain_blend.gd）：边带端点 (1,0)/(0,1)、中点 (0.5,0.5)、
##     权重和恒 1（有限、非负；密集采样 + 非法权重拒绝）；
##   - 色板→颜色映射：blend_color 端点纯色 / 中点均权；{terrain_id: Material}→色板
##     提取往返一致、非 StandardMaterial3D 槽显式拒绝；blend 通道材质开顶点色 albedo；
##   - mesh 顶点色锚（builder *_blend）：草-泥边带两端 = 对应纯色（owner 侧/邻侧）、
##     格心与顶面扇面恒本格纯色（中心主地形纯度）、角落端点 = 所在格纯色；
##     中点 0.5 权重经「端点纯色 + 仿射线性行插值」链路锚定（mesh 不设中点顶点——
##     改面数会动 face 表/碰撞合同，表现层切片不许，见任务卡实现要点 5）；
##   - 表现层切片不变量：blend 与 fallback（材质槽）几何/UV/法线/索引/faces 元数据
##     逐位一致、碰撞汤与 face 表逐位一致、fallback 无 COLOR 通道（旧路线零改动）；
##     flat/slope/cliff 三类边带同色规则；
##   - 构建确定性、纯逻辑（无场景节点）、非法输入显式失败（缺色板 id/非法色值/
##     参数非法/空矩形）。
## oracle 原则：几何期望一律由 HexMath（inner_vertex/bridge_xz）独立拼装对账（沿用
##   test_hex_terrain_builder.gd 口径），不复制 builder 归属实现。
## 色比较口径（2026-10-10 实测）：引擎标准 ARRAY_COLOR 通道按 8-bit 归一化存储
##   （0.9 → 229/255 ≈ 0.898）——mesh 顶点色 vs 色板纯色比较用 1/255 级容差
##   （_expect_color_eq8）；纯色语义锚在权重合同/色板层（浮点精确），mesh 层只差
##   量化步。mesh↔mesh（同管线两次产出）仍逐位精确比较。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Lib := preload("res://scripts/core/data/terrain_material_library.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const Blend := preload("res://addons/hexhammer/hex_terrain_blend.gd")
const Picking := preload("res://addons/hexhammer/hex_picking.gd")

# ================= 权重合同（纯逻辑） =================

func test_edge_weights_contract_anchor_points() -> void:
	expect_eq(Blend.edge_weights(0.0), Vector2(1.0, 0.0), "t=0（归属格内边）→ owner 权重 1")
	expect_eq(Blend.edge_weights(1.0), Vector2(0.0, 1.0), "t=1（邻格内边）→ 邻格权重 1")
	expect_eq(Blend.edge_weights(0.5), Vector2(0.5, 0.5), "t=0.5（边带中点）→ 权重各 0.5")
	for t in [0.0, 0.5, 1.0]:
		var w := Blend.edge_weights(t)
		expect(Blend.is_valid_weights(w), "锚点权重合法（有限、非负、和为 1）t=%s" % str(t))

func test_edge_weights_contract_dense_invariants() -> void:
	# Vector2 分量为 float32：(1−t)+t 的和有 ~1e-8 量级舍入——容差与
	# is_valid_weights 默认窗口（1e-6）同口径，合同语义仍是「和恒 1」
	for i in 101:
		var t := float(i) / 100.0
		var w := Blend.edge_weights(t)
		expect_almost_eq(w.x + w.y, 1.0, 1e-6, "权重和恒 1（t=%s）" % str(t))
		expect(w.x >= 0.0 and w.y >= 0.0, "权重非负（t=%s）" % str(t))
		expect(Blend.is_valid_weights(w), "合同域 [0,1] 内权重全部合法（t=%s）" % str(t))

func test_is_valid_weights_rejects_invalid() -> void:
	expect(Blend.is_valid_weights(Vector2(-0.1, 1.1)) == false, "负权重拒绝")
	expect(Blend.is_valid_weights(Vector2(0.5, 0.4)) == false, "和 ≠ 1 拒绝")
	expect(Blend.is_valid_weights(Vector2(NAN, 1.0)) == false, "NaN 拒绝")
	expect(Blend.is_valid_weights(Vector2(1.0, INF)) == false, "无穷拒绝")
	expect(Blend.is_valid_weights(Vector2(1.0, 0.0)), "端点 (1,0) 合法")
	expect(Blend.is_valid_weights(Vector2(0.5, 0.5)), "中点 (0.5,0.5) 合法")

# ================= 色板 → 颜色映射 =================

func test_blend_color_pure_ends_and_midpoint() -> void:
	var grass := Color(0.36, 0.54, 0.30)
	var mud := Color(0.55, 0.45, 0.30)
	expect_eq(Blend.blend_color(grass, mud, 1.0), grass, "w=1 → owner 纯色（端点）")
	expect_eq(Blend.blend_color(grass, mud, 0.0), mud, "w=0 → 邻格纯色（端点）")
	var mid := Blend.blend_color(grass, mud, 0.5)
	expect_almost_eq(mid.r, (grass.r + mud.r) * 0.5, 1e-9, "中点 r = 两纯色均值")
	expect_almost_eq(mid.g, (grass.g + mud.g) * 0.5, 1e-9, "中点 g = 两纯色均值")
	expect_almost_eq(mid.b, (grass.b + mud.b) * 0.5, 1e-9, "中点 b = 两纯色均值")
	# 合同链路：中点权重 0.5 → 映射恰为均权混合（mesh 端点纯色线性插值同一口径）
	expect_eq(Blend.blend_color(grass, mud, Blend.edge_weights(0.5).x), mid,
		"blend_color(…, edge_weights(0.5).x) = 中点均权混合（权重→颜色一一对应）")

func test_palette_from_materials_roundtrip_and_reject() -> void:
	var colors := {0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9), 2: Color(0.1, 0.9, 0.1)}
	var palette: Variant = Blend.palette_from_materials(Lib.materials_from_colors(colors))
	expect(palette is Dictionary, "StandardMaterial3D 表可提色板")
	if palette is Dictionary:
		for tid in colors:
			expect_eq((palette as Dictionary)[tid], colors[tid], "色板往返逐槽同色（类型 %s）" % str(tid))
	var bad := Lib.materials_from_colors({0: Color(1, 1, 1)})
	bad[1] = ShaderMaterial.new()  # 非 StandardMaterial3D：取不到 albedo_color
	expect(Blend.palette_from_materials(bad) == null, "表含非 StandardMaterial3D 槽 → null（显式失败）")
	expect_eq((Blend.palette_from_materials({}) as Dictionary).size(), 0, "空表 → 空色板（无槽可提）")

func test_make_blend_material_vertex_color_conduit() -> void:
	var mat := Blend.make_blend_material()
	expect(mat is StandardMaterial3D, "blend 通道材质为 StandardMaterial3D")
	expect_eq(mat.vertex_color_use_as_albedo, true, "开顶点色 albedo（顶点 COLOR = 权重结果可见的前提）")
	expect_eq(mat.albedo_color, Color(1.0, 1.0, 1.0, 1.0), "白 albedo（不污染顶点色）")

# ================= mesh 顶点色锚（BLEND-01 验收核心） =================

## 卡片场景：2×1 草-泥邻格（a=草 id0、b=泥 id1，等高 flat 边带）。
## 返回 {chunk, mesh, surfaces, faces 与 mesh 联合视图}——失败时返回空字典（后续断言优雅失败）。
func _build_grass_mud_pair(delta_elevation := 0) -> Dictionary:
	var m := MapDataClass.new(2, 1)
	var a := Hex.axial_of(Vector2i(0, 0))
	var b := Hex.axial_of(Vector2i(1, 0))
	m.set_terrain(a, 0)
	m.set_terrain(b, 1)
	if delta_elevation != 0:
		m.set_elevation(b, delta_elevation)
	var palette := {0: Lib.DEFAULT_PALETTE[0], 1: Lib.DEFAULT_PALETTE[1]}
	var r: Variant = Builder.build_map_blend(m, palette, 10, 10, Blend.make_blend_material())
	expect(r is Dictionary, "草-泥 2×1 blend 构建应成功（delta=%d）" % delta_elevation)
	if not (r is Dictionary):
		return {}
	var rd: Dictionary = r
	expect_eq((rd["chunks"] as Array).size(), 1, "单 chunk")
	expect_eq(rd["style"], "blend", "结果带 style 标记")
	expect_eq((rd["palette"] as Dictionary).size(), 2, "色板 echo 恰好覆盖被用类型")
	return rd["chunks"][0]

func test_grass_mud_band_pure_colors_at_both_ends() -> void:
	var chunk: Dictionary = _build_grass_mud_pair(0)
	if chunk.is_empty():
		return
	var grass: Color = Lib.DEFAULT_PALETTE[0]
	var mud: Color = Lib.DEFAULT_PALETTE[1]
	var a := Hex.axial_of(Vector2i(0, 0))
	var d := Hex.dir_between(a, Hex.axial_of(Vector2i(1, 0)))
	# 边带两面在归属格（a，稳定 ID 较小）的 surface 里；faces 序 = 三角序
	var found := _find_edge_faces(chunk, a, d)
	expect_eq(found.size(), 2, "恰 2 个边带面（一条共享边 × 2 三角）")
	if found.size() != 2:
		return
	var mesh: ArrayMesh = chunk["mesh"]
	var si: int = found[0]["surface"]
	var cols: PackedColorArray = mesh.surface_get_arrays(si)[Mesh.ARRAY_COLOR]
	expect_eq(cols.size(), (chunk["surfaces"][si]["faces"] as Array).size() * 3,
		"COLOR 通道逐顶点齐备（blend 路线）")
	var f0: int = found[0]["face"]
	var f1: int = found[1]["face"]
	expect_eq(f1, f0 + 1, "边带两面相邻（发射序）")
	# 几何锚（沿用 test_hex_terrain_builder 口径）：v1/v2 = a 的内顶点（owner 侧端），
	# v3/v4 = +bridge（邻格侧端）——先钉顶点再钉色，防「色对顶点错位」的假绿
	var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
	var v1 := Hex.inner_vertex(a, d)
	var v2 := Hex.inner_vertex(a, (d + 1) % 6)
	var br := Hex.bridge_xz(a, d, 1.0, Builder.DEFAULT_SOLID_FACTOR)
	var v3 := v1 + Vector3(br.x, 0.0, br.y)
	var v4 := v2 + Vector3(br.x, 0.0, br.y)
	expect_eq(verts[f0 * 3], v1, "面0 v0 = a.inner_d（owner 侧端点）")
	expect_eq(verts[f0 * 3 + 1], v3, "面0 v1 = 邻格侧端点")
	expect_eq(verts[f0 * 3 + 2], v4, "面0 v2 = 邻格侧端点")
	# Then ①：两端为对应纯色（owner 侧 = 草、邻侧 = 泥；8-bit 量化容差见头注）
	_expect_color_eq8(cols[f0 * 3], grass, "面0 owner 侧端 = 草纯色（权重 (1,0)）")
	_expect_color_eq8(cols[f0 * 3 + 1], mud, "面0 邻格侧端 = 泥纯色（权重 (0,1)）")
	_expect_color_eq8(cols[f0 * 3 + 2], mud, "面0 邻格侧端 = 泥纯色")
	_expect_color_eq8(cols[f1 * 3], grass, "面1 owner 侧端 = 草纯色")
	_expect_color_eq8(cols[f1 * 3 + 1], mud, "面1 邻格侧端 = 泥纯色")
	_expect_color_eq8(cols[f1 * 3 + 2], grass, "面1 owner 侧端 = 草纯色")
	# Then ②：中点权重各 0.5 —— mesh 不设中点顶点（face 表不变），中点 = 端点纯色的
	# 线性插值（边带 = 仿射参数 v3 = v1+bridge），用权重合同→颜色映射链路锚定等价
	var w_mid := Blend.edge_weights(0.5)
	expect_eq(w_mid, Vector2(0.5, 0.5), "中点权重各 0.5")
	expect_almost_eq(w_mid.x + w_mid.y, 1.0, 1e-9, "中点权重和为 1")
	var realized_mid := Blend.blend_color(cols[f0 * 3], cols[f0 * 3 + 1], w_mid.x)
	_expect_color_eq8(realized_mid, Blend.blend_color(grass, mud, 0.5),
		"带内线性插值在几何中点 = 0.5 权重混合色（端点纯色 → 中点均权）")
	# 几何中点 = 半桥位移（t=0.5 ↔ bridge×0.5，权重参数与几何参数同一仿射）
	var mid := (verts[f0 * 3] + verts[f0 * 3 + 1]) * 0.5
	_expect_vec3_eq_eps(mid - verts[f0 * 3], Vector3(br.x, 0.0, br.y) * 0.5, 1e-9,
		"边带中点 = owner 端 + 半桥（t=0.5 的几何对应）")

func test_grass_mud_band_colors_across_edge_types() -> void:
	# 权重/颜色规则与高差分类正交：flat/slope/cliff 三类边带端点同为纯色
	for delta in [1, 2]:
		var chunk: Dictionary = _build_grass_mud_pair(delta)
		if chunk.is_empty():
			return
		var grass: Color = Lib.DEFAULT_PALETTE[0]
		var mud: Color = Lib.DEFAULT_PALETTE[1]
		var a := Hex.axial_of(Vector2i(0, 0))
		var d := Hex.dir_between(a, Hex.axial_of(Vector2i(1, 0)))
		var found := _find_edge_faces(chunk, a, d)
		expect_eq(found.size(), 2, "|Δh|=%d 恰 2 个边带面" % delta)
		if found.size() != 2:
			return
		var want_type := "slope" if delta == 1 else "cliff"
		var faces: Array = chunk["surfaces"][found[0]["surface"]]["faces"]
		expect_eq(faces[found[0]["face"]]["edge_type"], want_type, "|Δh|=%d 边带分类" % delta)
		var mesh: ArrayMesh = chunk["mesh"]
		var cols: PackedColorArray = mesh.surface_get_arrays(found[0]["surface"])[Mesh.ARRAY_COLOR]
		var f0: int = found[0]["face"]
		var f1: int = found[1]["face"]
		_expect_color_eq8(cols[f0 * 3], grass, "|Δh|=%d owner 侧端 = 草纯色" % delta)
		_expect_color_eq8(cols[f0 * 3 + 1], mud, "|Δh|=%d 邻格侧端 = 泥纯色" % delta)
		_expect_color_eq8(cols[f1 * 3 + 2], grass, "|Δh|=%d owner 侧端 = 草纯色" % delta)
		_expect_color_eq8(cols[f1 * 3 + 1], mud, "|Δh|=%d 邻格侧端 = 泥纯色" % delta)

func test_cell_center_and_top_fan_stay_pure() -> void:
	var chunk: Dictionary = _build_grass_mud_pair(0)
	if chunk.is_empty():
		return
	var grass: Color = Lib.DEFAULT_PALETTE[0]
	var mud: Color = Lib.DEFAULT_PALETTE[1]
	var a := Hex.axial_of(Vector2i(0, 0))
	var b := Hex.axial_of(Vector2i(1, 0))
	var mesh: ArrayMesh = chunk["mesh"]
	for si in (chunk["surfaces"] as Array).size():
		var s: Dictionary = chunk["surfaces"][si]
		var cells: Array = s["cells"]
		expect_eq(cells.size(), 1, "2×1 每类型一格（surface %d）" % si)
		var want: Color = grass if cells[0] == a else mud
		var cols: PackedColorArray = mesh.surface_get_arrays(si)[Mesh.ARRAY_COLOR]
		var faces: Array = s["faces"]
		var top_count := 0
		for fi in faces.size():
			if faces[fi]["kind"] != "top":
				continue
			top_count += 1
			for vi in 3:
				_expect_color_eq8(cols[fi * 3 + vi], want,
					"顶面全顶点 = 本格纯色（格 %s 面 %d 顶点 %d）" % [str(cells[0]), fi, vi])
		expect_eq(top_count, 6, "每格顶面恰 6 面（surface %d）" % si)
	# 格心顶点专项：顶面扇面 v0 = 格心（test_hex_terrain_builder 已锚几何），色恒纯
	var cols0: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	_expect_color_eq8(cols0[0], grass, "格心（首顶面 v0）= 草纯色——中心主地形纯度")

func test_all_face_colors_follow_endpoint_rule() -> void:
	# 一般不变量（含角落与跨地形边带）：5×4 三类型 + 三档高程混合图，逐面核对
	#   top → 全顶点 = 本格纯色；edge → (owner,nb,nb)/(owner,nb,owner)；corner →
	#   (owner, N(k−1) 侧, N(k) 侧)——端点色 = 端点所在格的纯色（与边带端点规则同构）
	var m := MapDataClass.new(5, 4)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_terrain(cell, (cr.x * 3 + cr.y * 5) % 3)
		m.set_elevation(cell, (cr.x + cr.y) % 3 - 1)  # −1..1：flat/slope/cliff 混合
	var palette := {0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9), 2: Color(0.1, 0.9, 0.1)}
	var r := _blend_ok(m, palette)
	if r.is_empty():
		return
	var mesh: ArrayMesh = r["chunks"][0]["mesh"]
	for si in (r["chunks"][0]["surfaces"] as Array).size():
		var s: Dictionary = r["chunks"][0]["surfaces"][si]
		var faces: Array = s["faces"]
		var cols: PackedColorArray = mesh.surface_get_arrays(si)[Mesh.ARRAY_COLOR]
		expect_eq(cols.size(), faces.size() * 3, "COLOR 逐顶点齐备（surface %d）" % si)
		var fi := 0
		while fi < faces.size():
			var f: Dictionary = faces[fi]
			var kind := String(f["kind"])
			if kind == "edge":
				var owner: Vector2i = f["cell"]
				var nb := Hex.neighbor(owner, int(f["dir"]))
				var co: Color = palette[m.terrain_at(owner)]
				var cn: Color = palette[m.terrain_at(nb)]
				_expect_color_eq8(cols[fi * 3], co, "边带 owner 侧端 = 所在格纯色")
				_expect_color_eq8(cols[fi * 3 + 1], cn, "边带邻侧端 = 邻格纯色")
				_expect_color_eq8(cols[fi * 3 + 2], cn, "边带邻侧端 = 邻格纯色")
				_expect_color_eq8(cols[(fi + 1) * 3], co, "边带第二面 owner 侧端 = 所在格纯色")
				_expect_color_eq8(cols[(fi + 1) * 3 + 1], cn, "边带第二面邻侧端 = 邻格纯色")
				_expect_color_eq8(cols[(fi + 1) * 3 + 2], co, "边带第二面 owner 侧端 = 所在格纯色")
				fi += 2  # 边带面成对发射
				continue
			if kind == "corner":
				var owner2: Vector2i = f["cell"]
				var k := int(f["dir"])
				var nb_k := Hex.neighbor(owner2, k)
				var nb_k1 := Hex.neighbor(owner2, k - 1)
				# 发射序 (p1, p3, p2)：p1 = 归属格端、p3 = N(k−1) 侧端、p2 = N(k) 侧端
				_expect_color_eq8(cols[fi * 3], palette[m.terrain_at(owner2)], "角落 p1 = 归属格纯色")
				_expect_color_eq8(cols[fi * 3 + 1], palette[m.terrain_at(nb_k1)], "角落 p3 = N(k−1) 侧所在格纯色")
				_expect_color_eq8(cols[fi * 3 + 2], palette[m.terrain_at(nb_k)], "角落 p2 = N(k) 侧所在格纯色")
			else:  # top
				var want: Color = palette[m.terrain_at(f["cell"])]
				for vi in 3:
					_expect_color_eq8(cols[fi * 3 + vi], want, "顶面顶点 = 本格纯色")
			fi += 1

# ================= 表现层切片不变量（blend ↔ fallback） =================

func test_blend_geometry_and_face_table_equal_fallback() -> void:
	var m := MapDataClass.new(5, 4)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_terrain(cell, (cr.x * 3 + cr.y * 5) % 3)
		m.set_elevation(cell, (cr.x + cr.y) % 3 - 1)
	var palette := {0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9), 2: Color(0.1, 0.9, 0.1)}
	var table := Lib.materials_from_colors(palette)
	var blend_mat := Blend.make_blend_material()
	var fb: Variant = Builder.build_map(m, 3, 2, table)  # 跨 chunk 口径（5×4 / 3×2 → 多块）
	var bl: Variant = Builder.build_map_blend(m, palette, 3, 2, blend_mat)
	expect(fb is Dictionary and bl is Dictionary, "两 style 均可构建")
	if not (fb is Dictionary) or not (bl is Dictionary):
		return
	expect_eq((bl as Dictionary)["style"], "blend", "blend 结果 style 标记")
	expect_eq(((bl as Dictionary)["chunks"] as Array).size(),
		((fb as Dictionary)["chunks"] as Array).size(), "两 style chunk 数一致")
	for ci in ((bl as Dictionary)["chunks"] as Array).size():
		var cbl: Dictionary = (bl as Dictionary)["chunks"][ci]
		var cfb: Dictionary = (fb as Dictionary)["chunks"][ci]
		var mbl: ArrayMesh = cbl["mesh"]
		var mfb: ArrayMesh = cfb["mesh"]
		expect_eq(mbl.get_surface_count(), mfb.get_surface_count(), "surface 数一致（chunk %d）" % ci)
		expect_eq((cbl["surfaces"] as Array).size(), (cfb["surfaces"] as Array).size(),
			"surfaces 元数据数一致（chunk %d）" % ci)
		for si in mbl.get_surface_count():
			var abl: Array = mbl.surface_get_arrays(si)
			var afb: Array = mfb.surface_get_arrays(si)
			expect_eq(abl[Mesh.ARRAY_VERTEX], afb[Mesh.ARRAY_VERTEX], "顶点逐位一致（%d/%d）" % [ci, si])
			expect_eq(abl[Mesh.ARRAY_NORMAL], afb[Mesh.ARRAY_NORMAL], "法线逐位一致（%d/%d）" % [ci, si])
			expect_eq(abl[Mesh.ARRAY_TEX_UV], afb[Mesh.ARRAY_TEX_UV], "UV 逐位一致（%d/%d）" % [ci, si])
			expect_eq(abl[Mesh.ARRAY_INDEX], afb[Mesh.ARRAY_INDEX], "索引逐位一致（%d/%d）" % [ci, si])
			expect_eq(cbl["surfaces"][si]["faces"], cfb["surfaces"][si]["faces"],
				"faces 元数据逐位一致（%d/%d）——face 表合同不随 style 改变" % [ci, si])
			expect_eq(cbl["surfaces"][si]["face_counts"], cfb["surfaces"][si]["face_counts"],
				"面分类计数一致（%d/%d）" % [ci, si])
			expect_eq((abl[Mesh.ARRAY_COLOR] as PackedColorArray).size(),
				(abl[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
				"blend COLOR 逐顶点齐备（%d/%d）" % [ci, si])
			expect_eq(_color_count(afb), 0,
				"fallback 无 COLOR 通道（%d/%d）——旧路线零改动" % [ci, si])
			expect(mbl.surface_get_material(si) == blend_mat,
				"blend surface 材质统一 = 共享导管材质（%d/%d）" % [ci, si])
			expect(mfb.surface_get_material(si) == table[cfb["surfaces"][si]["terrain"]],
				"fallback surface 材质 = 表内该类型实例（%d/%d，回归）" % [ci, si])
		# 拾取/碰撞合同：soup 与 face 表逐位一致（顶点色不动 raw 顶点与映射顺序）
		expect_eq(Picking.chunk_collision_faces(cbl), Picking.chunk_collision_faces(cfb),
			"碰撞三角形汤逐位一致（chunk %d）" % ci)
		expect_eq(Picking.chunk_face_table(cbl), Picking.chunk_face_table(cfb),
			"face→格映射表逐位一致（chunk %d）" % ci)

func test_blend_build_deterministic() -> void:
	var m := MapDataClass.new(5, 4)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_terrain(cell, (cr.x + cr.y) % 2)
	var palette := {0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9)}
	var r1 := _blend_ok(m, palette)
	var r2 := _blend_ok(m, palette)
	if r1.is_empty() or r2.is_empty():
		return
	for ci in (r1["chunks"] as Array).size():
		var m1: ArrayMesh = r1["chunks"][ci]["mesh"]
		var m2: ArrayMesh = r2["chunks"][ci]["mesh"]
		for si in m1.get_surface_count():
			expect_eq(m1.surface_get_arrays(si)[Mesh.ARRAY_COLOR],
				m2.surface_get_arrays(si)[Mesh.ARRAY_COLOR],
				"两次构建 COLOR 逐位一致（chunk %d surface %d）" % [ci, si])
			expect_eq(r1["chunks"][ci]["surfaces"][si]["faces"],
				r2["chunks"][ci]["surfaces"][si]["faces"],
				"两次构建 faces 一致（chunk %d surface %d）" % [ci, si])

func test_blend_invalid_inputs_fail_explicitly() -> void:
	var m := MapDataClass.new(2, 1)
	var a := Hex.axial_of(Vector2i(0, 0))
	var b := Hex.axial_of(Vector2i(1, 0))
	m.set_terrain(a, 0)
	m.set_terrain(b, 1)
	var mat := Blend.make_blend_material()
	var ok_palette := {0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9)}
	expect(Builder.build_map_blend(m, {0: Color(0.9, 0.1, 0.1)}, 10, 10, mat) == null,
		"色板缺图内类型 1 → null（无隐式兜底）")
	expect(Builder.build_map_blend(m, {0: Color(0.9, 0.1, 0.1), 1: "mud"}, 10, 10, mat) == null,
		"色板槽值非 Color → null")
	expect(Builder.build_map_blend(m, {0: Color(NAN, 0.0, 0.0), 1: Color(0.1, 0.1, 0.9)}, 10, 10, mat) == null,
		"色板通道 NaN → null")
	expect(Builder.build_map_blend(m, {0: Color(-0.1, 0.0, 0.0), 1: Color(0.1, 0.1, 0.9)}, 10, 10, mat) == null,
		"色板通道负值 → null")
	expect(Builder.build_map_blend(m, ok_palette, 10, 10, null) == null,
		"blend_material 缺失（null）→ null（顶点色导管是合同一部分）")
	expect(Builder.build_map_blend(m, ok_palette, 0, 10, mat) == null, "chunk_cols ≤ 0 → null")
	expect(Builder.build_map_blend(m, ok_palette, 10, 10, mat, 0.0) == null, "size ≤ 0 → null")
	expect(Builder.build_map_blend(m, ok_palette, 10, 10, mat, 1.0, 0.0) == null,
		"elevation_step ≤ 0 → null")
	expect(Builder.build_map_blend(m, ok_palette, 10, 10, mat, 1.0, 1.0, 1.0) == null,
		"solid_factor ≥ 1 → null")
	expect(Builder.build_map_blend(m, ok_palette, 10, 10, mat, 1.0, 1.0, 0.0) == null,
		"solid_factor ≤ 0 → null")
	expect(Builder.build_chunk_blend(m, Rect2i(100, 100, 5, 5), ok_palette, mat) == null,
		"空矩形（图外 chunk）→ null")
	expect(Builder.build_map_blend(m, ok_palette, 10, 10, mat) is Dictionary, "合法参数仍构建成功（回归）")

func test_blend_layer_pure_logic_no_nodes() -> void:
	var inst: Variant = Blend.new()
	expect(inst is RefCounted, "HexTerrainBlend 实例为 RefCounted（ADR-2）")
	expect(not (inst is Node), "HexTerrainBlend 不得为 Node")
	var m := MapDataClass.new(3, 2)
	for cell in m.cells():
		m.set_terrain(cell, 0)
	var r := _blend_ok(m, {0: Color(0.5, 0.5, 0.5)})
	if r.is_empty():
		return
	_walk_no_nodes(r, 0)

func test_fallback_build_has_no_vertex_colors() -> void:
	# 回归锚：fallback（材质槽）路线不设 COLOR 通道、材质不开顶点色 albedo
	#（04 M1a-T3 细化；test_hex_terrain_builder 亦锚材质标志，这里补 mesh 通道面）
	var m := MapDataClass.new(3, 2)
	for cell in m.cells():
		m.set_terrain(cell, 0)
	var r: Variant = Builder.build_map(m, 10, 10, Lib.materials_from_colors({0: Color(0.5, 0.5, 0.5)}))
	expect(r is Dictionary, "fallback 构建成功")
	if not (r is Dictionary):
		return
	var mesh: ArrayMesh = (r as Dictionary)["chunks"][0]["mesh"]
	for si in mesh.get_surface_count():
		expect_eq(_color_count(mesh.surface_get_arrays(si)), 0,
			"fallback surface 无 COLOR 通道（surface %d）" % si)

# ---- 辅助 ----

## build_map_blend 断言成功并返回 Dictionary；失败返回空字典（后续断言优雅失败）。
func _blend_ok(m, palette: Dictionary) -> Dictionary:
	var r: Variant = Builder.build_map_blend(m, palette, 10, 10, Blend.make_blend_material())
	expect(r is Dictionary, "build_map_blend 应成功（返回 Dictionary）")
	if r is Dictionary:
		return r as Dictionary
	return {}

## 全 chunk 搜索指定边带面（kind=edge、cell=归属格、dir=方向）——返回
## [{"surface": si, "face": fi}, …]（faces 序 = 三角序，本测试不假设固定下标）。
func _find_edge_faces(chunk: Dictionary, owner: Vector2i, dir: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for si in (chunk["surfaces"] as Array).size():
		var s: Dictionary = chunk["surfaces"][si]
		var faces: Array = s["faces"]
		for fi in faces.size():
			var f: Dictionary = faces[fi]
			if f["kind"] == "edge" and f["cell"] == owner and int(f["dir"]) == dir:
				out.append({"surface": si, "face": fi})
	return out

## surface 数组的 COLOR 顶点数（缺通道时引擎回空容器、类型不定——按实际类型取数，
## 不做强转：fallback = 0、blend = 顶点数）。
func _color_count(arrays: Array) -> int:
	var v: Variant = arrays[Mesh.ARRAY_COLOR]
	if v is PackedColorArray:
		return (v as PackedColorArray).size()
	return 0

## mesh 顶点色 vs 期望色（8-bit 量化容差，见文件头注「色比较口径」）。
func _expect_color_eq8(got: Color, want: Color, msg: String) -> void:
	_checks += 1
	var eps := 1.0 / 255.0 + 1e-4
	if absf(got.r - want.r) > eps or absf(got.g - want.g) > eps \
			or absf(got.b - want.b) > eps or absf(got.a - want.a) > eps:
		_fails.append("%s：got=%s want=%s（8-bit 量化容差 %s）" % [msg, str(got), str(want), str(eps)])

## Vector3 容差比对（欧氏距离；沿用 test_hex_terrain_builder 口径）。
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
