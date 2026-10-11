## test_landform_terraces.gd — T2 LAND-01/02 单测（阶地高程与真垂直崖；执行方案 §3
##   LAND-01「连接矩阵」+ LAND-02「阶地与 cliff 交汇」的可 headless 锚定面）
## 覆盖锚（逐卡测试锚原文）：
##   - classify_edge 四分类 + cliff_threshold 参数化（Δ0..5 默认档 / threshold=4 扩档）；
##   - terrace_lerp / terrace_vfrac 公式锚（水平均分 + 竖直 v_step=1/ceil(steps/2) 的
##     Catlike 剖面；端点原位 = 同高程端点不移位）；
##   - 步数-Δ 绑定（每爬一级一组、组边界环恰落高程整数层）+ 阶地环带位置/面数解析
##     预言（Δn 面数 = n·steps·2）；
##   - 真垂直崖（修订记录三之 3）：墙顶/墙底**同 XZ 逐位一致**断言 + 面数 6/edge_type
##     cliff_wall + 裙边水平/墙竖直；
##   - 退回开关：profile 全关 = 不传 profile（null）的基线几何**逐位一致**（mesh 数组
##     + faces 元数据）+ 非法 profile 显式拒绝；
##   - LAND-01 矩阵图（tools/land_matrix_fixtures.gd 固定小图）：全档穷举 × 焊接流形
##     （重复面 0 / 边引用 ≤2 / 开边 ⊆ 基线外沿 / 全顶点有限 / 绕序 y ≥ 0）+ 每物理
##     边/角恰一生成者 + 角面数 = 环点数−2 解析预言；threshold=4 扩档同步覆盖；
##   - blend 承接（LAND-02 ⑤）：阶地/崖壁/角填充每个新顶点 COLOR 由同一
##     edge_weights(t)/corner_weights(u,v) 显式求值（逐点 is_valid + 端点纯色）；
##   - UV 选型（LAND-02 ⑦）：tread/裙边 = 平面、riser/墙 = 侧面（T8 公式不改）；
##   - 几何档不变量（§8.1 分档表）：换 profile 不改 MapData.summary/digest/连通性。
## oracle 原则：期望几何一律由方案公式（terrace 剖面/墙中点）+ HexMath 全局参数独立
##   拼装，不复制 builder 发射代码；面数由分类×解析式组合计数；角面数 = 环点数−2
##   （耳切三角化的不变量）。焊接口径 WELD_EPS=1e-3（沿 test_hex_terrain_elevation.gd）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Lib := preload("res://scripts/core/data/terrain_material_library.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const Blend := preload("res://addons/hexhammer/hex_terrain_blend.gd")
const Conn := preload("res://scripts/content/map_connectivity.gd")
const ProfileClass := preload("res://scripts/core/data/landform_profile.gd")
const Fixtures := preload("res://tools/land_matrix_fixtures.gd")

const SIZE := 1.0
const STEP := 1.0
const SOLID := 0.8
const WELD_EPS := 1e-3

# ================= 分类与剖面公式（LAND-01 ① / LAND-02 ①）=================

func test_classify_edge_four_way_and_threshold_param() -> void:
	expect_eq(Builder.classify_edge(0), Builder.EDGE_FLAT, "Δ0 = flat")
	expect_eq(Builder.classify_edge(1), Builder.EDGE_SLOPE, "±Δ1 = slope")
	expect_eq(Builder.classify_edge(-1), Builder.EDGE_SLOPE, "负向 Δ1 同 slope（|Δ| 口径）")
	expect_eq(Builder.classify_edge(2), Builder.EDGE_TERRACE, "默认档（threshold=3）Δ2 = terrace")
	expect_eq(Builder.classify_edge(3), Builder.EDGE_CLIFF, "Δ3 = cliff（Δ≥threshold，修订记录一）")
	expect_eq(Builder.classify_edge(5), Builder.EDGE_CLIFF, "Δ5 = cliff")
	# profile 调档：threshold=4 → 阶地档 [2,4)、崖=Δ≥4（LAND-01 ② 矩阵同步扩）
	expect_eq(Builder.classify_edge(3, 4), Builder.EDGE_TERRACE, "threshold=4：Δ3 = terrace")
	expect_eq(Builder.classify_edge(4, 4), Builder.EDGE_CLIFF, "threshold=4：Δ4 = cliff")

func test_terrace_vfrac_catlike_profile() -> void:
	# v_step = 1/ceil(steps/2)；(step+1)/2 int 除法 = 竖直仅奇数步动（LAND-02 ① 原式）
	# 5 步序列 0,1/3,1/3,2/3,2/3,1（2 平台 + 3 短坡）；3 步 0,1/2,1/2,1（修订记录三之 3）
	var steps := 5
	var v_step := 1.0 / ceilf(float(steps) / 2.0)
	expect_almost_eq(v_step, 1.0 / 3.0, 1e-9, "5 步 v_step = 1/3")
	var fracs := []
	for s in steps + 1:
		fracs.append(Builder.terrace_vfrac(s, steps))
	expect_almost_eq(float(fracs[0]), 0.0, 1e-9, "步 0 → 0（端点原位）")
	expect_almost_eq(float(fracs[steps]), 1.0, 1e-9, "步 steps → 1（端点原位）")
	var want5 := [0.0, 1.0 / 3.0, 1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1.0]
	for s in steps + 1:
		expect_almost_eq(float(fracs[s]), want5[s], 1e-9, "5 步剖面 s=%d" % s)
	var fracs3 := []
	for s in 4:
		fracs3.append(Builder.terrace_vfrac(s, 3))
	var want3 := [0.0, 0.5, 0.5, 1.0]
	for s in 4:
		expect_almost_eq(float(fracs3[s]), want3[s], 1e-9, "3 步剖面（紧凑档）s=%d" % s)

func test_terrace_lerp_horizontal_uniform_vertical_profile() -> void:
	var a := Vector3(0.0, 0.0, 0.0)
	var b := Vector3(10.0, 4.0, 0.0)
	var p2 := Builder.terrace_lerp(a, b, 2, 5)
	expect_almost_eq(p2.x, 4.0, 1e-6, "水平 = a.lerp(b, step/steps) 均分（s=2/5 → x=4）")
	expect_almost_eq(p2.y, 4.0 / 3.0, 1e-6, "竖直 = 剖面（s=2 → 1/3）")
	var p0 := Builder.terrace_lerp(a, b, 0, 5)
	expect_eq(p0, a, "step=0 → 恰为 a（同高程端点不移位的公式保证）")
	var p5 := Builder.terrace_lerp(a, b, 5, 5)
	expect_eq(p5, b, "step=steps → 恰为 b")

func test_terrace_ring_group_boundary_at_integer_levels() -> void:
	# 步数-Δ 绑定（LAND-02 ①/修订记录二 ③）：Δn = n 组串联；组边界环（S=k·steps）
	# 的竖直分数 = k/n → y 恰落高程整数层（平台对齐整数层的机器表达）
	for s in 11:
		var vf := Builder.terrace_ring_vfrac(s, 2, 5)
		var y := 0.0 + 2.0 * vf  # Δ2、elevation_step=1
		if s % 5 == 0:
			expect_almost_eq(y, float(s / 5), 1e-9,
				"组边界环 S=%d 恰在高程整数层 %d" % [s, s / 5])
	# Δ3（threshold=4 档）= 3 组
	for s in 16:
		if s % 5 == 0:
			var vf3 := Builder.terrace_ring_vfrac(s, 3, 5)
			expect_almost_eq(3.0 * vf3, float(s / 5), 1e-9, "Δ3 组边界 S=%d 整数层" % s)

# ================= 阶地环带几何（LAND-02 ②）=================

## 测试侧独立拼装的环点公式（方案原文：XZ 水平均分 + 竖直剖面，方向 owner→nb）。
func _ring_point(v_from: Vector3, v_to: Vector3, s: int, n: int, steps: int,
		e_from: int, e_to: int) -> Vector3:
	var t := float(s) / float(n * steps)
	var vf := Builder.terrace_ring_vfrac(s, n, steps)
	var p := v_from.lerp(v_to, t)
	p.y = lerpf(float(e_from) * STEP, float(e_to) * STEP, vf)
	return p

func test_terrace_band_positions_and_face_count() -> void:
	# 2×1 对图 Δ2（默认档阶地）：面数 = 2·n·steps（解析式预言，LAND-01 测试锚）
	var m := MapDataClass.new(2, 1)
	var a := Hex.axial_of(Vector2i(0, 0))
	var b := Hex.neighbor(a, 0)
	m.set_elevation(a, 0)
	m.set_elevation(b, 2)
	var r := _build_ok(m, _default_profile())
	var faces := _edge_faces(r, a, 0)
	expect_eq(faces.size(), 2 * 2 * 5, "Δ2 × steps5 → 2·n·steps = 20 面解析预言")
	# 顶点 = 测试侧独立拼装环点（owner a 为低侧：剖面 ascending 0→2）
	var v1 := Hex.inner_vertex(a, 0, SIZE, SOLID, 0.0)
	var v2 := Hex.inner_vertex(a, 1, SIZE, SOLID, 0.0)
	var v3 := Hex.inner_vertex(b, 4, SIZE, SOLID, 2.0)
	var v4 := Hex.inner_vertex(b, 3, SIZE, SOLID, 2.0)
	var expect_pts: Array[Vector3] = []
	for s in 11:
		expect_pts.append(_ring_point(v1, v3, s, 2, 5, 0, 2))
	var verts := _face_verts(r, faces)
	var missing := 0
	for ep in expect_pts:
		var found := false
		for v in verts:
			if v.distance_to(ep) <= 1e-6:
				found = true
				break
		if not found:
			missing += 1
	expect_eq(missing, 0, "全部 11 环点（侧 1）逐位 = 独立拼装公式")
	# owner 高侧对照（Δ2 反向）：剖面 descending 2→0，端点仍原位
	var m2 := MapDataClass.new(2, 1)
	m2.set_elevation(a, 2)
	m2.set_elevation(b, 0)
	var r2 := _build_ok(m2, _default_profile())
	var faces2 := _edge_faces(r2, a, 0)
	expect_eq(faces2.size(), 20, "反向 Δ2 面数同（分类只看 |Δ|）")
	var v1h := Hex.inner_vertex(a, 0, SIZE, SOLID, 2.0)
	var v3h := Hex.inner_vertex(b, 4, SIZE, SOLID, 0.0)
	var verts2 := _face_verts(r2, faces2)
	var ok_high := true
	for s in 11:
		var ep := _ring_point(v1h, v3h, s, 2, 5, 2, 0)
		var found := false
		for v in verts2:
			if v.distance_to(ep) <= 1e-6:
				found = true
				break
		if not found:
			ok_high = false
	expect(ok_high, "owner 高侧：环点剖面沿 owner→nb 方向（descending），端点原位")

func test_flat_and_slope_bands_bit_identical_under_profile() -> void:
	# 「同高程端点不移位」+ Δ1 不受 profile 影响：flat/slope 边带与基线逐位一致
	var m := MapDataClass.new(3, 2)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_elevation(cell, cr.x % 2)
	var r_base := _build_ok(m, null)
	var r_prof := _build_ok(m, _default_profile())
	for f_base in _collect_edge_faces(r_base):
		var matched := false
		for f_prof in _collect_edge_faces(r_prof):
			if f_prof["cell"] == f_base["cell"] and f_prof["dir"] == f_base["dir"] \
					and f_prof["v0"] == f_base["v0"] and f_prof["v1"] == f_base["v1"] \
					and f_prof["v2"] == f_base["v2"]:
				matched = true
				break
		expect(matched, "flat/slope 边带在 profile 下逐位保持 %s d%d"
			% [str(f_base["cell"]), int(f_base["dir"])])

# ================= 退回开关（LAND-02 ⑥）=================

func test_retreat_switch_bit_identical_with_baseline() -> void:
	# 全关 profile = null = 基线：mesh 数组 + faces 元数据逐位一致（回退锚）
	var m := Fixtures.build_matrix(3)
	var r_null := _build_ok(m, null)
	var off := ProfileClass.new()
	off.terrace_enabled = false
	off.cliff_vertical = false
	var r_off := _build_ok(m, off)
	expect_eq(_all_mesh_arrays(r_null), _all_mesh_arrays(r_off),
		"全关 profile 与不传 profile 的 mesh 数组逐位一致（回退锚）")
	expect_eq(_all_faces_meta(r_null), _all_faces_meta(r_off),
		"faces 元数据逐位一致（face 表/碰撞合同不随回退档改变）")

func test_retreat_switch_nondefault_threshold_geometry_identical() -> void:
	# 全关 + 非默认 threshold（landform_profile.gd 退回档合同的精确化锚，T2 评审
	# 修复）：几何逐位一致（同一基线分支——UV 只分 Δ0/非Δ0，阈值不进几何），
	# faces 元数据 edge_type 在档位边界切换标签（Δ3：null 档 cliff、4 档 terrace
	# ——LAND-01 ② 分类随阈值切换，非违约）。归属/面数/序均不变。
	var m := Fixtures.build_matrix(4)  # 边带 Δ0..Δ4（含 Δ3 切换样本）
	var r_null := _build_ok(m, null)
	var off := ProfileClass.new()
	off.terrace_enabled = false
	off.cliff_vertical = false
	off.cliff_threshold = 4
	var r_off := _build_ok(m, off)
	expect_eq(_all_mesh_arrays(r_null), _all_mesh_arrays(r_off),
		"全关 threshold=4 与基线 mesh 数组逐位一致（几何不吃阈值）")
	var edges_null := _collect_edge_faces(r_null)
	var edges_off := _collect_edge_faces(r_off)
	expect_eq(edges_null.size(), edges_off.size(), "边带面数一致")
	var switched := 0
	for i in edges_null.size():
		expect_eq(edges_null[i]["cell"], edges_off[i]["cell"],
			"边带归属与序一致（%d——归属只看稳定 ID）" % i)
		expect_eq(edges_null[i]["dir"], edges_off[i]["dir"], "边带方向一致（%d）" % i)
		if edges_null[i]["edge_type"] != edges_off[i]["edge_type"]:
			switched += 1
			expect_eq(edges_null[i]["edge_type"], Builder.EDGE_CLIFF,
				"切换边基线标签 = cliff（Δ3 ≥ 默认 3）")
			expect_eq(edges_off[i]["edge_type"], Builder.EDGE_TERRACE,
				"切换边 4 档标签 = terrace（Δ3 < 4）")
	expect(switched > 0, "Δ3 边存在且标签切换被实际覆盖（矩阵 4 档含 Δ3 对）")

func test_invalid_profile_rejected() -> void:
	var m := MapDataClass.new(3, 3)
	var bad_steps := ProfileClass.new()
	bad_steps.terrace_steps = 1
	expect(Builder.build_map(m, 10, 10, _mats(), SIZE, STEP, SOLID, bad_steps) == null,
		"terrace_steps=1 → null（步数 1 无阶地语义，显式拒绝）")
	expect(bad_steps.problems().size() > 0, "problems() 报 steps 问题（人读面）")
	var bad_threshold := ProfileClass.new()
	bad_threshold.cliff_threshold = 1
	expect(Builder.build_map(m, 10, 10, _mats(), SIZE, STEP, SOLID, bad_threshold) == null,
		"cliff_threshold=1 → null（阶地档空集）")
	expect(_build_ok(m, _default_profile()) is Dictionary, "合法档仍可构建（回归）")
	# .tres 与代码默认对账（TerrainStyle 同纪律）
	var tres: Variant = ProfileClass.load_default()
	expect(tres is ProfileClass, "默认 .tres 可载入")
	if tres is ProfileClass:
		var p: ProfileClass = tres
		expect_eq(p.terrace_enabled, true, ".tres terrace_enabled = true（阶地默认）")
		expect_eq(p.terrace_steps, ProfileClass.DEFAULT_TERRACE_STEPS, ".tres steps = 默认 5")
		expect_eq(p.cliff_vertical, true, ".tres cliff_vertical = true（真崖默认）")
		expect_eq(p.cliff_threshold, ProfileClass.DEFAULT_CLIFF_THRESHOLD, ".tres threshold = 3")

# ================= 真垂直崖（LAND-02 ③，修订记录三之 3）=================

func test_cliff_wall_top_bottom_share_xz() -> void:
	# Δ3 对图：墙顶/墙底同 XZ 逐位一致断言（只查高差不算数——修订记录三之 3 原文）
	for high_owner in [false, true]:
		var m := MapDataClass.new(2, 1)
		var a := Hex.axial_of(Vector2i(0, 0))
		var b := Hex.neighbor(a, 0)
		m.set_elevation(a, 3 if high_owner else 0)
		m.set_elevation(b, 0 if high_owner else 3)
		var r := _build_ok(m, _default_profile())
		var faces := _edge_faces(r, a, 0)
		expect_eq(faces.size(), 6, "崖壁 = 裙边×2 + 墙 = 6 面（owner 高侧=%s）" % str(high_owner))
		for f in faces:
			expect_eq(String(f["edge_type"]), Builder.EDGE_CLIFF_WALL,
				"面级 edge_type = cliff_wall（owner 高侧=%s）" % str(high_owner))
		var verts := _face_verts(r, faces)
		var v1 := Hex.inner_vertex(a, 0, SIZE, SOLID, float(m.elevation_at(a)))
		var v2 := Hex.inner_vertex(a, 1, SIZE, SOLID, float(m.elevation_at(a)))
		var br := Hex.bridge_xz(a, 0, SIZE, SOLID)
		var h_hi := maxf(m.elevation_at(a), m.elevation_at(b)) * STEP
		var h_lo := minf(m.elevation_at(a), m.elevation_at(b)) * STEP
		for vm in [v1, v2]:
			# 共享崖线 XZ = 两格内边中点线（t=0.5）：墙顶/墙底各恰一顶点、XZ 逐位一致
			#（T2 评审修复：found 标志取代「!= Vector3.ZERO or h_lo == 0.0」——后者在
			#低侧高程 0 的测试图恒真短路，存在性面失锚）
			var mv: Vector3 = vm
			var mpt := mv.lerp(mv + Vector3(br.x, 0.0, br.y), 0.5)
			var found_hi := false
			var found_lo := false
			var at_hi := Vector3()
			var at_lo := Vector3()
			for v in verts:
				if absf(v.x - mpt.x) <= 1e-6 and absf(v.z - mpt.z) <= 1e-6:
					if absf(v.y - h_hi) <= 1e-6:
						at_hi = v
						found_hi = true
					elif absf(v.y - h_lo) <= 1e-6:
						at_lo = v
						found_lo = true
			expect(found_hi, "墙顶点存在于共享崖线 XZ（owner 高=%s）" % str(high_owner))
			expect(found_lo, "墙底点存在于同 XZ（owner 高=%s）" % str(high_owner))
			if found_hi and found_lo:
				expect_eq(at_hi.x, at_lo.x, "墙顶/墙底 XZ 逐位一致 x（owner 高=%s）" % str(high_owner))
				expect_eq(at_hi.z, at_lo.z, "墙顶/墙底 XZ 逐位一致 z（owner 高=%s）" % str(high_owner))
				expect_eq(at_hi.y, h_hi, "墙顶 y = 高侧高程")
				expect_eq(at_lo.y, h_lo, "墙底 y = 低侧高程")
		# 墙面竖直：cross.y ≈ 0 的面恰 2 个（每墙 2 三角）；裙边水平（三顶点同 y）
		var vertical := 0
		var low_cell := a if m.elevation_at(a) < m.elevation_at(b) else b
		var low_ctr := Hex.axial_to_world(low_cell, SIZE)
		for f in faces:
			var v1c: Vector3 = f["v1"]
			var v0c: Vector3 = f["v0"]
			var v2c: Vector3 = f["v2"]
			var cy: float = (v1c - v0c).cross(v2c - v0c).y
			if absf(cy) <= 1e-6:
				vertical += 1
				# 竖直墙法线水平 + **朝低侧**（T2 评审补锚——类头注「测试对竖直面改查
				#水平朝向」的落字：owner 高/低两种归属下墙 raw cross 都须朝低侧，
				#低处玩家看崖壁；朝高侧 = 低侧见洞）
				var n: Vector3 = f["norms"][0]
				expect(absf(n.y) <= 1e-3, "竖直墙面法线水平（owner 高=%s）" % str(high_owner))
				var mid: Vector3 = (f["v0"] + f["v1"] + f["v2"]) / 3.0
				expect(n.x * (low_ctr.x - mid.x) + n.z * (low_ctr.z - mid.z) > 0.0,
					"竖直墙法线朝低侧（owner 高=%s）" % str(high_owner))
		expect_eq(vertical, 2, "恰 2 竖直墙面（owner 高=%s）" % str(high_owner))

# ================= 角落情形分派（LAND-02 ④）=================

func test_corner_all_equal_single_flat_triangle() -> void:
	var m := MapDataClass.new(3, 3)
	var r := _build_ok(m, _default_profile())
	for f in _collect_corner_faces(r):
		var verts := [f["v0"], f["v1"], f["v2"]]
		expect_eq(f["v0"].y, f["v1"].y, "等高角落 = 单平三角（三顶点同 y）")
		expect_eq(f["v1"].y, f["v2"].y, "等高角落 v1/v2 同 y")
		for v in verts:
			expect_eq(v.y, 0.0, "等高角落 y = 高程 0")

func _expected_corner_face_count(eo: int, ea: int, eb: int, steps: int,
		terrace_on := true, wall_on := true, threshold := 3) -> int:
	# 角面数 = 环点数 − 2（耳切三角化不变量）；环点数 = 三侧折线长度和 − 3（p1/p2/p3
	# 相邻两侧各共享一次）。侧长：flat/slope = 2、terrace = |Δ|·steps+1、cliff 墙 = 4。
	var lens := []
	for pair in [[eo, eb], [eb, ea], [ea, eo]]:
		var et := Builder.classify_edge(pair[0] - pair[1], threshold)
		if et == Builder.EDGE_TERRACE and terrace_on:
			lens.append(absi(pair[0] - pair[1]) * steps + 1)
		elif et == Builder.EDGE_CLIFF and wall_on:
			lens.append(4)
		else:
			lens.append(2)
	return lens[0] + lens[1] + lens[2] - 3 - 2

func test_corner_face_count_formula_across_classes() -> void:
	# 三格组合抽样（含等高/两低一高阶地扇/含崖坍缩扇/崖×阶地混合角）：面数 = 解析式
	var combos := [
		[0, 0, 0], [1, 1, 1], [0, 0, 1], [0, 1, 1],
		[0, 0, 2], [0, 2, 2], [0, 1, 2], [2, 1, 0],
		[0, 0, 3], [0, 3, 3], [3, 0, 0], [1, 3, 0],
		[0, 1, 3], [0, 2, 3], [3, 3, 3], [2, 2, 3],
	]
	for combo in combos:
		var m := MapDataClass.new(5, 5)
		var a := Hex.axial_of(Vector2i(1, 1))
		var b := Hex.neighbor(a, 2)
		var c := Hex.neighbor(a, 1)
		m.set_elevation(a, combo[0])
		m.set_elevation(b, combo[1])
		m.set_elevation(c, combo[2])
		var r := _build_ok(m, _default_profile())
		# 归属 = 三格最小 ID（沿用 builder 规则）；角编号由邻居对匹配独立推导
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
		expect(j >= 0, "角编号可推导（组合 %s）" % str(combo))
		if j < 0:
			continue
		var count := 0
		for f in _collect_corner_faces(r):
			if f["cell"] == owner and int(f["dir"]) == j:
				count += 1
		var want := _expected_corner_face_count(combo[0], combo[1], combo[2], 5)
		expect_eq(count, want, "角面数 = 环点数−2 解析预言（组合 %s：got %d want %d）"
			% [str(combo), count, want])

# ================= LAND-01 矩阵图：穷举 + 焊接流形 =================

func test_matrix_default_threshold_exhaustive_manifold() -> void:
	var profile := _default_profile()
	var map := Fixtures.build_matrix(3)
	_expect_matrix_invariants(map, profile, 3, "默认档矩阵")

func test_matrix_threshold4_extended() -> void:
	# 角矩阵值域随 cliff_threshold 同步扩（修订记录三之 8）：上界 = max(3, threshold)
	var profile := ProfileClass.new()
	profile.cliff_threshold = 4
	var map := Fixtures.build_matrix(4)
	# Δ3 在 threshold=4 下为阶地（3 组）；Δ4 为崖——两类都须出现
	_expect_matrix_invariants(map, profile, 4, "threshold=4 扩档矩阵")

func _expect_matrix_invariants(map: MapDataClass, profile: ProfileClass,
		threshold: int, label: String) -> void:
	var r := _build_ok(map, profile)
	var faces := _collect_all_faces(r)
	# ① 每物理边恰一归属 + 面数 = 分类解析式（flat/slope=2、terrace=2·n·steps、cliff 墙=6）
	var edge_counts := {}
	var edge_types := {}
	for f in faces:
		if f["kind"] != "edge":
			continue
		var k := "%s|%d" % [str(f["cell"]), int(f["dir"])]
		edge_counts[k] = int(edge_counts.get(k, 0)) + 1
		edge_types[String(f["edge_type"])] = true
	var total_edge_oracle := 0
	var checked_edges := 0
	for cell in map.cells():
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb) or map.index_of(nb) < map.index_of(cell):
				continue
			var dh := absi(map.elevation_at(cell) - map.elevation_at(nb))
			var et := Builder.classify_edge(map.elevation_at(cell) - map.elevation_at(nb), threshold)
			var want := 2
			if et == Builder.EDGE_TERRACE:
				want = dh * profile.terrace_steps * 2
			elif et == Builder.EDGE_CLIFF:
				want = 6 if profile.cliff_vertical else 2
			var k := "%s|%d" % [str(cell), d]
			expect_eq(int(edge_counts.get(k, 0)), want,
				"%s：边面数 = 解析预言 %s d%d Δ%d（got %d want %d）" % [label, str(cell), d, dh, edge_counts.get(k, 0), want])
			total_edge_oracle += want
			checked_edges += 1
	expect(checked_edges > 100, "%s：覆盖边数足够（got %d）" % [label, checked_edges])
	# 分类全覆盖（平/坡/阶地/崖壁——「平/坡/崖全部闭合并可见」+ Δ2 阶地）
	expect(edge_types.has(Builder.EDGE_FLAT), "%s：含平连" % label)
	expect(edge_types.has(Builder.EDGE_SLOPE), "%s：含斜坡" % label)
	expect(edge_types.has(Builder.EDGE_TERRACE), "%s：含阶地" % label)
	expect(edge_types.has(Builder.EDGE_CLIFF_WALL), "%s：含崖壁" % label)
	# ② 每物理角恰一归属 + 面数 = 环点数−2；等价类全集覆盖（0..max(3,threshold)）
	var corner_counts := {}
	var classes_seen := {}
	for f in faces:
		if f["kind"] != "corner":
			continue
		var k := "%s|%d" % [str(f["cell"]), int(f["dir"])]
		corner_counts[k] = int(corner_counts.get(k, 0)) + 1
	var class_total := 0
	for cell in map.cells():
		for k in 6:
			var nbk := Hex.neighbor(cell, k)
			var nbk1 := Hex.neighbor(cell, k - 1)
			if not map.has_cell(nbk) or not map.has_cell(nbk1):
				continue
			if map.index_of(nbk) < map.index_of(cell) or map.index_of(nbk1) < map.index_of(cell):
				continue
			var eo: int = map.elevation_at(cell)
			var ek: int = map.elevation_at(nbk)
			var ek1: int = map.elevation_at(nbk1)
			var trio := [eo, ek, ek1]
			trio.sort()
			classes_seen[str(trio)] = true
			var want := _expected_corner_face_count(eo, ek, ek1, profile.terrace_steps,
				profile.terrace_enabled, profile.cliff_vertical, threshold)
			var kk := "%s|%d" % [str(cell), k]
			expect_eq(int(corner_counts.get(kk, 0)), want,
				"%s：角面数 = 环点数−2 %s k%d（got %d want %d）" % [label, str(cell), k, corner_counts.get(kk, 0), want])
			class_total += 1
	var want_classes := 0
	var dmax := maxi(3, threshold)
	for a2 in dmax + 1:
		for b2 in range(a2, dmax + 1):
			for c2 in range(b2, dmax + 1):
				want_classes += 1
	expect_eq(classes_seen.size(), want_classes,
		"%s：角等价类全集覆盖（got %d want %d——值域随 threshold 扩）" % [label, classes_seen.size(), want_classes])
	# ③ 焊接流形（LAND-01/02 测试锚）：无重复面 / 边引用 ≤2 / 开边 ⊆ 基线外沿 /
	#    全顶点有限 / 绕序 y ≥ 0（竖直面 |cy| ≤ 1e-6）
	var verts := _flat_verts(faces)
	for v in verts:
		expect(is_finite(v.x) and is_finite(v.y) and is_finite(v.z), "%s：无非有限顶点" % label)
	var ids := _weld(verts)
	var centers := _weld_centers(verts, ids)
	var seen_tris := {}
	var edge_ref := {}
	for fi in faces.size():
		var triple: Array[int] = [ids[fi * 3], ids[fi * 3 + 1], ids[fi * 3 + 2]]
		triple.sort()
		var key := "%d|%d|%d" % [triple[0], triple[1], triple[2]]
		expect(not seen_tris.has(key), "%s：重复面 key %s" % [label, key])
		seen_tris[key] = true
		_bump(edge_ref, ids[fi * 3], ids[fi * 3 + 1])
		_bump(edge_ref, ids[fi * 3 + 1], ids[fi * 3 + 2])
		_bump(edge_ref, ids[fi * 3 + 2], ids[fi * 3])
	var over := 0
	for k in edge_ref:
		expect(int(edge_ref[k]) <= 2, "%s：边被 >2 面引用 %s" % [label, k])
		if int(edge_ref[k]) > 2:
			over += 1
	expect_eq(over, 0, "%s：>2 引用边数 = 0" % label)
	# 开边 ⊆ 基线外沿（位置级：T2 外沿 = 基线外沿的细分，两端点落在基线 1-ref 边上）
	var rim := _legacy_rim(map)
	var not_on_rim := 0
	for k in edge_ref:
		if int(edge_ref[k]) != 1:
			continue
		var pr := (String(k)).split("_")
		var pa: Vector3 = centers[int(pr[0])]
		var pb: Vector3 = centers[int(pr[1])]
		if not _segment_on_any(pa, pb, rim):
			not_on_rim += 1
	expect_eq(not_on_rim, 0, "%s：内部开边 = 0（开边全部落在地图外沿，焊接流形闭合）" % label)
	# 绕序：非竖直面 cross.y > 1e-6；竖直面（崖墙/角竖直耳）|cy| ≤ 1e-6
	for f in faces:
		var v1w: Vector3 = f["v1"]
		var v0w: Vector3 = f["v0"]
		var v2w: Vector3 = f["v2"]
		var cy: float = (v1w - v0w).cross(v2w - v0w).y
		expect(cy > 1e-6 or absf(cy) <= 1e-6, "%s：面绕序不翻转（cy=%s）" % [label, str(cy)])
	# ④ 总面数 = 解析式总和（LAND-01「每档面数 = 解析式预言」）
	var total_oracle := map.cell_count() * 6 + total_edge_oracle
	for cell in map.cells():
		for k in 6:
			var nbk := Hex.neighbor(cell, k)
			var nbk1 := Hex.neighbor(cell, k - 1)
			if not map.has_cell(nbk) or not map.has_cell(nbk1):
				continue
			if map.index_of(nbk) < map.index_of(cell) or map.index_of(nbk1) < map.index_of(cell):
				continue
			total_oracle += _expected_corner_face_count(map.elevation_at(cell),
				map.elevation_at(nbk), map.elevation_at(nbk1), profile.terrace_steps,
				profile.terrace_enabled, profile.cliff_vertical, threshold)
	expect_eq(faces.size(), total_oracle,
		"%s：总面数 = 全解析式总和（got %d want %d）" % [label, faces.size(), total_oracle])

# ================= blend 承接（LAND-02 ⑤ / §8.1 扩档）=================

func test_blend_weights_on_terraces_walls_and_corners() -> void:
	# 混合高程小图 blend + profile：每个新顶点 COLOR 由同一 edge_weights(t) /
	# corner_weights(u,v) 显式求值（卡表锚：逐点 is_valid_weights/is_valid_weights3
	# 通过 + 端点 (1,0)/(0,1) 不变）。oracle 独立拼装：t/(u,v) 由顶点位置在合同
	# 参数域（边带两条侧边线 / 角区仿射基）上反解，期望色 = 权重函数显式求值
	# ——不复制 builder 发射代码（环带/崖壁/角扇的顶点全部落在这些参数域上，
	# 位置错挂的权重色在此逐点暴露）。
	var m := MapDataClass.new(5, 4)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_terrain(cell, cr.x % 2)
		m.set_elevation(cell, (cr.x + cr.y) % 4)  # 0..3：flat/slope/terrace/cliff 全档
	var palette := {0: Color(0.9, 0.1, 0.1), 1: Color(0.1, 0.1, 0.9)}
	var r: Variant = Builder.build_map_blend(m, palette, 10, 10, Blend.make_blend_material(),
		SIZE, STEP, SOLID, _default_profile())
	expect(r is Dictionary, "blend + profile 构建成功")
	if not (r is Dictionary):
		return
	var rd: Dictionary = r
	var endpoints_owner := 0
	var endpoints_nb := 0
	for cd in rd["chunks"]:
		var mesh: ArrayMesh = cd["mesh"]
		for si in (cd["surfaces"] as Array).size():
			var sd: Dictionary = (cd["surfaces"] as Array)[si]
			var arrays: Array = mesh.surface_get_arrays(si)
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var faces: Array = sd["faces"]
			expect_eq(cols.size(), faces.size() * 3, "COLOR 逐顶点齐备（surface %d）" % si)
			for fi in faces.size():
				var f: Dictionary = faces[fi]
				var kind := String(f["kind"])
				expect(kind == "top" or kind == "edge" or kind == "corner",
					"kind 三值合同（blend 承接不改 face 表 schema）")
				var cell: Vector2i = f["cell"]
				var c_owner: Color = palette[m.terrain_at(cell)]
				for vi in 3:
					var p: Vector3 = vv[fi * 3 + vi]
					var got: Color = cols[fi * 3 + vi]
					var want: Color = got
					if kind == "top":
						# 顶面全顶点 = 本格纯色（中心主地形纯度）
						want = c_owner
					elif kind == "edge":
						# t = 顶点在 owner→nb 侧边线（HexMath 现算）上的参数
						var t := _edge_param_of(p, cell, int(f["dir"]))
						var w := Blend.edge_weights(t)
						expect(Blend.is_valid_weights(w),
							"edge 权重逐点合法（有限非负和 1；面 %d 顶点 %d t=%s）"
							% [fi, vi, str(t)])
						if t <= 1e-5:
							expect_almost_eq(w.x, 1.0, 2e-5, "t=0 端点 owner 权重 = 1（(1,0) 不变）")
							expect_almost_eq(w.y, 0.0, 2e-5, "t=0 端点 nb 权重 = 0")
							endpoints_owner += 1
						elif t >= 1.0 - 1e-5:
							expect_almost_eq(w.x, 0.0, 2e-5, "t=1 端点 owner 权重 = 0（(0,1) 不变）")
							expect_almost_eq(w.y, 1.0, 2e-5, "t=1 端点 nb 权重 = 1")
							endpoints_nb += 1
						var nb := Hex.neighbor(cell, int(f["dir"]))
						want = Blend.blend_color(c_owner, palette[m.terrain_at(nb)], w.x)
					elif kind == "corner":
						# (u,v) = 顶点在角区仿射参数域（p1 原点、bridge_k/bridge_{k−1} 基）
						# 的坐标——hex_terrain_blend.gd 合同域定义的测试侧独立求解；
						# 合法性窗口 1e-5 = 反解测量噪声级（u+v≤1 边界的钳后残差 ~2e-6，
						# 真违约权重分量差 0.1 量级——隔四个数量级）
						var uv := _corner_params_of(p, cell, int(f["dir"]))
						var w3 := Blend.corner_weights(uv.x, uv.y)
						expect(Blend.is_valid_weights3(w3, 1e-5),
							"corner 权重逐点合法（有限非负和 1；面 %d 顶点 %d u=%s v=%s）"
							% [fi, vi, str(uv.x), str(uv.y)])
						want = Blend.blend_color3(c_owner,
							palette[m.terrain_at(Hex.neighbor(cell, int(f["dir"])))],
							palette[m.terrain_at(Hex.neighbor(cell, int(f["dir"]) - 1))], w3)
					_expect_color_eq8(got, want,
						"逐点权重 oracle（%s 面 %d 顶点 %d：COLOR = 权重显式求值）"
						% [kind, fi, vi])
	expect(endpoints_owner > 0, "t=0 端点顶点被实际覆盖（owner 纯色锚存在性）")
	expect(endpoints_nb > 0, "t=1 端点顶点被实际覆盖（nb 纯色锚存在性）")


## 边带合同参数 t 的 oracle 反解：边带（基线 quad / 阶地环 / 崖壁裙边-墙线）全部
## blend 顶点都落在两条侧边线（owner 内边端点 → nb 内边端点，HexMath 现算）上；
## 两线平行同参数（同一 t 两侧），按顶点到线的距离取所在侧。float32 mesh 顶点
## 量化的反解噪声 ~1e-6 会在端点跨出合同域 [0,1]——钳回边界再验（权重合同的
## 域外值属测量误差非实现行为；真正错挂权重的 t 偏差 0.1 量级，不受钳制影响）。
func _edge_param_of(p: Vector3, cell: Vector2i, dir: int) -> float:
	var v1 := Hex.inner_vertex(cell, dir, SIZE, SOLID, 0.0)
	var v2 := Hex.inner_vertex(cell, (dir + 1) % 6, SIZE, SOLID, 0.0)
	var br := Hex.bridge_xz(cell, dir, SIZE, SOLID)
	var v3 := v1 + Vector3(br.x, 0.0, br.y)
	var v4 := v2 + Vector3(br.x, 0.0, br.y)
	var t1 := _proj_line_param(p, v1, v3)
	var t2 := _proj_line_param(p, v2, v4)
	var t := t1 if _line_dist(p, v1, v3) <= _line_dist(p, v2, v4) else t2
	return clampf(t, 0.0, 1.0)


func _proj_line_param(p: Vector3, a: Vector3, b: Vector3) -> float:
	var d := Vector2(b.x - a.x, b.z - a.z)
	return ((p.x - a.x) * d.x + (p.z - a.z) * d.y) / d.length_squared()


func _line_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var t := clampf(_proj_line_param(p, a, b), 0.0, 1.0)
	return Vector2(p.x - (a.x + d.x * t), p.z - (a.z + d.y * t)).length()


## 角区合同参数 (u,v) 的 oracle 反解：corner_weights 参数域 = p1 + u·bridge_k +
## v·bridge_{k−1}（hex_terrain_blend.gd 合同定义）——对 XZ 解 2×2 线性系。
## 反解噪声钳域同 _edge_param_of（域 = u,v ≥ 0；u+v≤1 侧的 ~1e-8 残差由
## is_valid_weights3 的 −eps 窗口覆盖，与合同浮点口径一致）。
func _corner_params_of(p: Vector3, cell: Vector2i, k: int) -> Vector2:
	var p1 := Hex.inner_vertex(cell, k, SIZE, SOLID, 0.0)
	var br_k := Hex.bridge_xz(cell, k, SIZE, SOLID)
	var br_k1 := Hex.bridge_xz(cell, k - 1, SIZE, SOLID)
	var e1 := Vector2(br_k.x, br_k.y)
	var e2 := Vector2(br_k1.x, br_k1.y)
	var d := Vector2(p.x - p1.x, p.z - p1.z)
	var den := e1.x * e2.y - e1.y * e2.x
	var u := clampf((d.x * e2.y - d.y * e2.x) / den, 0.0, 1.0)
	var v := clampf((e1.x * d.y - e1.y * d.x) / den, 0.0, 1.0)
	return Vector2(u, v)

func _expect_color_eq8(got: Color, want: Color, msg: String) -> void:
	_checks += 1
	var eps := 1.0 / 255.0 + 1e-4
	if absf(got.r - want.r) > eps or absf(got.g - want.g) > eps \
			or absf(got.b - want.b) > eps or absf(got.a - want.a) > eps:
		_fails.append("%s：got=%s want=%s（8-bit 量化容差）" % [msg, str(got), str(want)])

# ================= UV 选型（LAND-02 ⑦）=================

func test_uv_tread_planar_riser_and_wall_side() -> void:
	# Δ2 阶地带：tread 面（环对等高）三顶点 UV = 平面映射；riser 面 = 侧面映射
	var m := MapDataClass.new(2, 1)
	var a := Hex.axial_of(Vector2i(0, 0))
	m.set_elevation(Hex.neighbor(a, 0), 2)
	var r := _build_ok(m, _default_profile())
	var treads := 0
	var risers := 0
	for f in _edge_faces(r, a, 0):
		var flat := absf(f["v0"].y - f["v1"].y) <= 1e-9 and absf(f["v1"].y - f["v2"].y) <= 1e-9
		for vi in 3:
			var v: Vector3 = [f["v0"], f["v1"], f["v2"]][vi]
			var uv: Vector2 = f["uvs"][vi]
			if flat:
				expect_almost_eq(uv.x, v.x / (2.0 * SIZE), 1e-6, "tread UV u = x/2R（平面）")
				expect_almost_eq(uv.y, -v.z / (2.0 * SIZE), 1e-6, "tread UV v = −z/2R")
			else:
				expect_almost_eq(uv.y, -v.y / (2.0 * SIZE), 1e-6, "riser UV v = −y/2R（竖向跟高程）")
		if flat:
			treads += 1
		else:
			risers += 1
	expect(treads > 0, "阶地带含 tread 面（2 平台 ×2 组）")
	expect(risers > 0, "阶地带含 riser 面（3 短坡 ×2 组）")
	# 崖壁：墙面 UV 走侧面（v 跨度 = 墙高 = Δ·step/2R）
	var m2 := MapDataClass.new(2, 1)
	m2.set_elevation(Hex.neighbor(a, 0), 3)
	var r2 := _build_ok(m2, _default_profile())
	var wall_v := []
	for f in _edge_faces(r2, a, 0):
		var v1q: Vector3 = f["v1"]
		var v0q: Vector3 = f["v0"]
		var v2q: Vector3 = f["v2"]
		var cy: float = (v1q - v0q).cross(v2q - v0q).y
		if absf(cy) <= 1e-6:
			for vi in 3:
				wall_v.append((f["uvs"] as Array)[vi].y)
	expect(wall_v.size() > 0, "Δ3 崖壁含竖直墙面")
	if wall_v.size() > 0:
		var vmax := 0.0
		var vmin := 0.0
		for v in wall_v:
			vmax = maxf(vmax, v)
			vmin = minf(vmin, v)
		expect_almost_eq(vmin, -3.0 / 2.0, 1e-6, "墙面 UV v 下沿 = −Δ·step/2R")
		expect_almost_eq(vmax, 0.0, 1e-6, "墙面 UV v 上沿 = 0")

# ================= 几何档不变量（§8.1 分档表）=================

func test_mapdata_invariants_across_profiles() -> void:
	# 换几何 profile：MapData.summary/digest/连通性逐位一致（mesh 允许变——不变量分档）
	var map := Fixtures.build_matrix(3)
	var summary := map.summary()
	var digest := map.digest()
	var dict := map.to_dict()
	var conn := Conn.check(map)
	var off := ProfileClass.new()
	off.terrace_enabled = false
	off.cliff_vertical = false
	var t4 := ProfileClass.new()
	t4.cliff_threshold = 4
	for p in [null, off, _default_profile(), t4]:
		var r := _build_ok(map, p)
		expect(r is Dictionary, "各档均可构建")
	expect_eq(map.summary(), summary, "summary 跨档逐位一致")
	expect_eq(map.digest(), digest, "digest 跨档一致")
	expect_eq(map.to_dict(), dict, "to_dict 跨档一致（含 mods——几何档不写世界事实）")
	expect_eq(Conn.check(map), conn, "连通性跨档一致")
	expect_eq(map.mods.size(), 0, "mods 保持空")

# ---- 辅助 ----

func _default_profile() -> ProfileClass:
	return ProfileClass.make_default()

func _mats() -> Dictionary:
	return Lib.materials_from_colors(Lib.DEFAULT_PALETTE)

func _build_ok(m, profile) -> Dictionary:
	var r: Variant = Builder.build_map(m, 10, 10, _mats(), SIZE, STEP, SOLID, profile)
	expect(r is Dictionary, "build_map 应成功（profile=%s）" % str(profile))
	if r is Dictionary:
		return r as Dictionary
	return {"chunks": [], "chunk_rects": [], "materials": {}}

## 全图面收集（含顶点/UV/法线——faces 序 = 三角序）。
func _collect_all_faces(r: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cd in r["chunks"]:
		var mesh: ArrayMesh = cd["mesh"]
		for si in (cd["surfaces"] as Array).size():
			var sd: Dictionary = (cd["surfaces"] as Array)[si]
			var arrays: Array = mesh.surface_get_arrays(si)
			var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var faces: Array = sd["faces"]
			for fi in faces.size():
				var f: Dictionary = faces[fi]
				out.append({
					"kind": f["kind"], "cell": f["cell"], "dir": f["dir"],
					"edge_type": String(f.get("edge_type", "")),
					"v0": vv[fi * 3], "v1": vv[fi * 3 + 1], "v2": vv[fi * 3 + 2],
					"uvs": arrays[Mesh.ARRAY_TEX_UV].slice(fi * 3, fi * 3 + 3),
					"norms": arrays[Mesh.ARRAY_NORMAL].slice(fi * 3, fi * 3 + 3),
				})
	return out

func _collect_edge_faces(r: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in _collect_all_faces(r):
		if f["kind"] == "edge":
			out.append(f)
	return out

func _collect_corner_faces(r: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in _collect_all_faces(r):
		if f["kind"] == "corner":
			out.append(f)
	return out

func _edge_faces(r: Dictionary, owner: Vector2i, dir: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in _collect_edge_faces(r):
		if f["cell"] == owner and int(f["dir"]) == dir:
			out.append(f)
	return out

func _face_verts(r: Dictionary, faces: Array[Dictionary]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for f in faces:
		out.append(f["v0"])
		out.append(f["v1"])
		out.append(f["v2"])
	return out

func _flat_verts(faces: Array[Dictionary]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.resize(faces.size() * 3)
	for fi in faces.size():
		out[fi * 3] = faces[fi]["v0"]
		out[fi * 3 + 1] = faces[fi]["v1"]
		out[fi * 3 + 2] = faces[fi]["v2"]
	return out

func _all_mesh_arrays(r: Dictionary) -> Array:
	var out: Array = []
	for cd in r["chunks"]:
		var mesh: ArrayMesh = cd["mesh"]
		for si in mesh.get_surface_count():
			out.append(mesh.surface_get_arrays(si))
	return out

func _all_faces_meta(r: Dictionary) -> Array:
	var out: Array = []
	for cd in r["chunks"]:
		for sd in cd["surfaces"]:
			out.append(sd["faces"])
	return out

## 空间哈希聚类焊接（WELD_EPS；沿 test_hex_terrain_elevation.gd 口径）。
func _weld(verts: Array[Vector3]) -> Array[int]:
	var ids: Array[int] = []
	ids.resize(verts.size())
	var grid := {}
	var centers: Array[Vector3] = []
	for i in verts.size():
		var p: Vector3 = verts[i]
		var cid := _find_cluster(grid, centers, p)
		if cid < 0:
			cid = centers.size()
			centers.append(p)
			var key := Vector3i(int(floor(p.x / WELD_EPS)), int(floor(p.y / WELD_EPS)), int(floor(p.z / WELD_EPS)))
			if not grid.has(key):
				grid[key] = []
			(grid[key] as Array).append(cid)
		ids[i] = cid
	return ids

func _find_cluster(grid: Dictionary, centers: Array[Vector3], p: Vector3) -> int:
	var cx := int(floor(p.x / WELD_EPS))
	var cy := int(floor(p.y / WELD_EPS))
	var cz := int(floor(p.z / WELD_EPS))
	for dx in 3:
		for dy in 3:
			for dz in 3:
				var key := Vector3i(cx + dx - 1, cy + dy - 1, cz + dz - 1)
				if grid.has(key):
					for cid in grid[key]:
						if centers[cid].distance_to(p) <= WELD_EPS:
							return cid
	return -1

func _weld_centers(verts: Array[Vector3], ids: Array[int]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.resize(ids.max() + 1)
	for i in verts.size():
		out[ids[i]] = verts[i]
	return out

func _bump(counts: Dictionary, u: int, v: int) -> void:
	var key := "%d_%d" % [mini(u, v), maxi(u, v)]
	counts[key] = int(counts.get(key, 0)) + 1

## 基线（无 profile）构建的 1-ref 边线段集合——T2 外沿的「位置基准」。
func _legacy_rim(map: MapDataClass) -> Array:
	var r := _build_ok(map, null)
	var faces := _collect_all_faces(r)
	var verts := _flat_verts(faces)
	var ids := _weld(verts)
	var centers := _weld_centers(verts, ids)
	var edge_ref := {}
	for fi in faces.size():
		_bump(edge_ref, ids[fi * 3], ids[fi * 3 + 1])
		_bump(edge_ref, ids[fi * 3 + 1], ids[fi * 3 + 2])
		_bump(edge_ref, ids[fi * 3 + 2], ids[fi * 3])
	var out: Array = []
	for k in edge_ref:
		if int(edge_ref[k]) == 1:
			var pr := (String(k)).split("_")
			out.append([centers[int(pr[0])], centers[int(pr[1])]])
	return out

func _segment_on_any(pa: Vector3, pb: Vector3, segs: Array) -> bool:
	for seg in segs:
		if _point_on_seg(pa, seg[0], seg[1]) and _point_on_seg(pb, seg[0], seg[1]):
			return true
	return false

func _point_on_seg(p: Vector3, s: Vector3, e: Vector3, eps := 2e-3) -> bool:
	var d := Vector2(e.x - s.x, e.z - s.z)
	var len2 := d.length_squared()
	if len2 < 1e-18:
		return false
	var t := clampf(((p.x - s.x) * d.x + (p.z - s.z) * d.y) / len2, 0.0, 1.0)
	var px := s.x + d.x * t
	var pz := s.z + d.y * t
	return Vector2(p.x - px, p.z - pz).length() <= eps
