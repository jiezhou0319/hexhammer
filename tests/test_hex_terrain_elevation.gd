## test_hex_terrain_elevation.gd — M1a-T4 高程分层与连续连接单测（headless 断言几何不变量）
## 逐条覆盖 04 任务卡 M1a-T4「验收 + 细化新增」的可自动化部分：
##   - 交汇组合测试矩阵：三格角落组合 0/0/0、0/0/1、0/1/1、0/1/2、0/0/2（+0/2/2、
##     负层、排列变体）各 ≥1 测——角落三角三顶点 y = 各格高程、三条边带分类正确、
##     顶点 = 全局公式、绕序朝上；
##   - 归属规则防重复面：共享边带由两格稳定 ID 较小者生成；共享角以三格 ID 为 key
##     定唯一生成者（归属格视角的角编号由"邻居集合匹配"独立推导，不复制 builder 枚举）；
##   - 跨 chunk 接缝 1 测：高差跨缝（斜坡+陡面）、跨界边带/角落归属唯一、
##     顶点逐位来自同一全局格心/边参数；
##   - 地图外沿 1 测：界外无边带/角落（无悬空连接）+ 焊接流形（每边恰 1/2 面引用）
##     + 1 面边界边 = 期望外沿边集（顶面外沿边 + 缺角暴露的边带侧边）；
##   - 随机高程图无破面/无 z-fighting：无重复面 key（焊接顶点三元组全图唯一）、
##     边引用闭合、无共面重叠面（共享焊接顶点且共面且重叠面积 > 阈值的面对）、
##     全部面法线 y > 0（无翻转面）。
## 「高差处连接符合设计图示意」为主创目测项（scenes/m1a_sandbox.tscn 铺三档高程），
##   不在本文件——见任务卡。
## oracle 原则：期望几何一律由 HexMath.inner_vertex/bridge_xz（全局参数源）独立拼装，
##   同路径逐位比对；跨格视角同一物理点（不同数学表达式）容差 1e-5 对账；
##   面数/边界边由 MapData 邻接原语组合计数，不复制 builder 归属实现。
## 焊接口径：WELD_EPS = 1e-3 聚类（最近不同物理点距 ≈ (1−solid)·size ≥ 0.1，
##   两条计算路径浮点差 ≤ ~1e-5——安全余量两个数量级）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")

const SIZE := 1.0
const STEP := 1.0
const SOLID := 0.8  # = Builder.DEFAULT_SOLID_FACTOR（默认路径 oracle 参数）
const WELD_EPS := 1e-3
const CROSS_PATH_EPS := 1e-5

# ================= 交汇组合测试矩阵（细化新增）=================

func test_matrix_corner_0_0_0() -> void:
	_run_corner_matrix(0, 0, 0)

func test_matrix_corner_0_0_1() -> void:
	_run_corner_matrix(0, 0, 1)

func test_matrix_corner_0_1_1() -> void:
	_run_corner_matrix(0, 1, 1)

func test_matrix_corner_0_1_2() -> void:
	_run_corner_matrix(0, 1, 2)

func test_matrix_corner_0_0_2() -> void:
	_run_corner_matrix(0, 0, 2)

func test_matrix_corner_0_2_2() -> void:
	_run_corner_matrix(0, 2, 2)

func test_matrix_corner_negative_and_permutations() -> void:
	# 负层（T9 噪声量化会产负值——值域口径须提前验证）+ 高低排列变体
	_run_corner_matrix(-1, 0, 1)
	_run_corner_matrix(2, 0, 1)
	_run_corner_matrix(1, 2, 3)

# ================= 归属规则（防重复面）=================

func test_edge_bridge_owner_is_smaller_stable_id() -> void:
	# 5×3 图全量核对：每条边带面的 cell 恒为该物理边两格中稳定 ID 较小者
	var m := MapDataClass.new(5, 3)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_elevation(cell, (cr.x + cr.y) % 3)
	var r := _build_ok(m)
	for f in _collect_faces(r):
		if f["kind"] != "edge":
			continue
		var cell: Vector2i = f["cell"]
		var nb := Hex.neighbor(cell, f["dir"])
		expect(m.has_cell(nb), "边带面邻格须界内 %s" % str(f))
		expect(m.index_of(cell) < m.index_of(nb),
			"边带归属 = 稳定 ID 较小者：%s(%d) vs %s(%d)" % [cell, m.index_of(cell), nb, m.index_of(nb)])

func test_corner_owner_is_smallest_of_three_ids() -> void:
	var m := MapDataClass.new(3, 3)
	var r := _build_ok(m)
	for f in _collect_faces(r):
		if f["kind"] != "corner":
			continue
		var cell: Vector2i = f["cell"]
		var k: int = f["dir"]
		var nb_k := Hex.neighbor(cell, k)
		var nb_k1 := Hex.neighbor(cell, k - 1)
		expect(m.has_cell(nb_k) and m.has_cell(nb_k1), "角落三格须界内 %s" % str(f))
		expect(m.index_of(cell) < m.index_of(nb_k) and m.index_of(cell) < m.index_of(nb_k1),
			"角落归属 = 三格稳定 ID 最小者：%s(%d) vs %s(%d)/%s(%d)"
			% [cell, m.index_of(cell), nb_k, m.index_of(nb_k), nb_k1, m.index_of(nb_k1)])

# ================= 跨 chunk 接缝（细化新增：1 测）=================

func test_cross_chunk_seam_with_elevation() -> void:
	# 20×10 / 10×10 = 左右两 chunk；高程随列变化 → 接缝处同时有斜坡(Δ1)与陡面(Δ2)
	var m := MapDataClass.new(20, 10)
	for cell in m.cells():
		var col := Hex.offset_of(cell).x
		m.set_elevation(cell, (col % 2) if col < 10 else 2 + ((col + Hex.offset_of(cell).y) % 2))
	var r := _build_ok(m)
	expect_eq((r["chunks"] as Array).size(), 2, "20×10 → 两 chunk")
	var faces := _collect_faces(r)
	# ① 全图物理边/角恰好一次（跨 chunk 归属唯一——重复即破面/z-fighting 源头）
	var edge_faces := {}
	var corner_count := {}
	for f in faces:
		if f["kind"] == "edge":
			var k := _edge_key(f["cell"], f["dir"])
			if not edge_faces.has(k):
				edge_faces[k] = [] as Array[Dictionary]
			(edge_faces[k] as Array[Dictionary]).append(f)
		elif f["kind"] == "corner":
			var k2 := _corner_key(f["cell"], f["dir"])
			corner_count[k2] = int(corner_count.get(k2, 0)) + 1
	expect_eq(edge_faces.size(), _interior_edge_count(m), "物理边总数 = oracle")
	for k in edge_faces:
		expect_eq((edge_faces[k] as Array).size(), 2, "每条内部边恰一 quad %s" % k)
	expect_eq(corner_count.size(), _interior_corner_count(m), "物理角总数 = oracle")
	for k in corner_count:
		expect_eq(corner_count[k], 1, "每个内部角恰一面 %s" % k)
	# ② 跨缝边带：顶点逐位 = 归属格全局公式 + 分类正确 + 缝两侧高差核对
	var rects: Array = r["chunk_rects"]
	var seam := 0
	var seam_types := {}
	for k in edge_faces:
		var pair: Array[Dictionary] = edge_faces[k]
		var f0: Dictionary = pair[0]
		var cell: Vector2i = f0["cell"]
		var d: int = f0["dir"]
		var nb := Hex.neighbor(cell, d)
		if _rect_of(rects, cell) == _rect_of(rects, nb):
			continue
		seam += 1
		var dh := m.elevation_at(cell) - m.elevation_at(nb)
		seam_types[Builder.classify_edge(dh)] = true
		var want := Builder.classify_edge(dh)
		for f in pair:
			expect_eq(f["edge_type"], want, "跨缝边带分类 = 高差分类 %s Δ=%d" % [k, dh])
		# 顶点逐位（归属格视角；含 y = 两格高程）
		var h0 := float(m.elevation_at(cell)) * STEP
		var h1 := float(m.elevation_at(nb)) * STEP
		var v1 := Hex.inner_vertex(cell, d, SIZE, SOLID, h0)
		var v2 := Hex.inner_vertex(cell, (d + 1) % 6, SIZE, SOLID, h0)
		var br := Hex.bridge_xz(cell, d, SIZE, SOLID)
		var v3 := v1 + Vector3(br.x, 0.0, br.y)
		var v4 := v2 + Vector3(br.x, 0.0, br.y)
		v3.y = h1
		v4.y = h1
		expect_eq(f0["v0"], v1, "跨缝边带 v0 逐位 = 全局公式（同参数源）%s" % k)
		expect_eq(f0["v1"], v3, "跨缝边带 v1（y=对面高程）%s" % k)
		expect_eq(f0["v2"], v4, "跨缝边带 v2 %s" % k)
		var f1: Dictionary = pair[1]
		expect_eq(f1["v0"], v1, "跨缝边带第二面 v0 %s" % k)
		expect_eq(f1["v1"], v4, "跨缝边带第二面 v1 %s" % k)
		expect_eq(f1["v2"], v2, "跨缝边带第二面 v2 %s" % k)
		# 绕序朝上（高差不翻转绕序）
		for f in pair:
			expect((f["v1"] - f["v0"]).cross(f["v2"] - f["v0"]).y > 0.0, "跨缝边带绕序朝上 %s" % k)
	expect(seam >= 10, "跨缝边带 ≥ 10 条（20×10 中缝），got %d" % seam)
	expect(seam_types.has(Builder.EDGE_SLOPE), "跨缝含斜坡（Δ1）")
	expect(seam_types.has(Builder.EDGE_CLIFF), "跨缝含陡面（Δ2）")
	# ③ 跨缝角落抽查：四块共享角的顶点 = 三格高程（含 chunk 边界两侧格）
	var checked_corner := false
	for f in faces:
		if f["kind"] != "corner":
			continue
		var cell: Vector2i = f["cell"]
		var k: int = f["dir"]
		var n1 := Hex.neighbor(cell, k)
		var n2 := Hex.neighbor(cell, k - 1)
		if _rect_of(rects, cell) == _rect_of(rects, n1) and _rect_of(rects, cell) == _rect_of(rects, n2):
			continue
		var p1 := Hex.inner_vertex(cell, k, SIZE, SOLID, float(m.elevation_at(cell)) * STEP)
		var br_k := Hex.bridge_xz(cell, k, SIZE, SOLID)
		var br_k1 := Hex.bridge_xz(cell, k - 1, SIZE, SOLID)
		var p2 := p1 + Vector3(br_k.x, 0.0, br_k.y)
		var p3 := p1 + Vector3(br_k1.x, 0.0, br_k1.y)
		p2.y = float(m.elevation_at(n1)) * STEP
		p3.y = float(m.elevation_at(n2)) * STEP
		expect_eq(f["v0"], p1, "跨缝角落 v0 %s" % str(f))
		expect_eq(f["v1"], p3, "跨缝角落 v1 %s" % str(f))
		expect_eq(f["v2"], p2, "跨缝角落 v2 %s" % str(f))
		checked_corner = true
		break
	expect(checked_corner, "20×10 两 chunk 图应存在跨缝角落")

# ================= 地图外沿（细化新增：1 测）=================

func test_map_outer_rim_no_dangling_connections() -> void:
	# 5×4 小图、高程含负值：界外不生成连接 + 焊接流形 + 边界边 = 期望外沿集
	var m := MapDataClass.new(5, 4)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_elevation(cell, (cr.x * 2 + cr.y * 3) % 5 - 2)  # −2..2 含负层
	var r := _build_ok(m)
	var faces := _collect_faces(r)
	# ① 界外无悬空连接：每条边带/角落引用的格全界内
	for f in faces:
		if f["kind"] == "edge":
			expect(m.has_cell(Hex.neighbor(f["cell"], f["dir"])), "边带不得连向界外 %s" % str(f))
		elif f["kind"] == "corner":
			expect(m.has_cell(Hex.neighbor(f["cell"], f["dir"])), "角落三格须界内 %s" % str(f))
			expect(m.has_cell(Hex.neighbor(f["cell"], f["dir"] - 1)), "角落三格须界内（第二邻）%s" % str(f))
	_expect_full_invariants(faces, m, "外沿图")

# ================= 随机高程图：无破面 / 无 z-fighting（验收可自动化面）=================

func test_random_elevation_map_no_broken_faces_no_zfighting() -> void:
	# 固定种子随机高程 0..4（覆盖三档连接；60×40 = T3 终验尺寸口径）
	var m := MapDataClass.new(60, 40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	var class_counts := {}
	for cell in m.cells():
		var h := rng.randi_range(0, 4)
		m.set_elevation(cell, h)
	for cell in m.cells():
		for d in 3:
			var nb := Hex.neighbor(cell, d)
			if m.has_cell(nb):
				class_counts[Builder.classify_edge(m.elevation_at(cell) - m.elevation_at(nb))] = true
	for t in [Builder.EDGE_FLAT, Builder.EDGE_SLOPE, Builder.EDGE_CLIFF]:
		expect(class_counts.has(t), "随机图须含三档连接（%s）" % t)
	var r := _build_ok(m)
	expect_eq((r["chunks"] as Array).size(), 24, "60×40 / 10×10 = 24 chunk")
	_expect_full_invariants(_collect_faces(r), m, "随机图 60×40")

# ================= 参数化（elevation_step / solid_factor）=================

func test_elevation_step_and_solid_factor_params() -> void:
	# step=2.5：格 (1,1) 高程 2 → 顶面 y=5.0；与邻格 (h=0) 的边带两端 y = 5.0 / 0.0
	var m := MapDataClass.new(3, 3)
	var a := Hex.axial_of(Vector2i(1, 1))
	m.set_elevation(a, 2)
	var r := _build_ok(m, 10, 10, {}, SIZE, 2.5)
	expect_eq(r["elevation_step"], 2.5, "构建结果回显 elevation_step")
	var top_y := {}
	for f in _collect_faces(r):
		if f["kind"] == "top" and f["cell"] == a:
			top_y[f["dir"]] = f["v0"].y
	expect_eq(top_y.size(), 6, "格 a 顶面 6 面")
	for k in top_y:
		expect_eq(top_y[k], 5.0, "顶面 y = h×step（2×2.5）")
	# solid=0.5：内顶点距格心 = 0.5（半缩进——参数生效锚；step 保持默认 1.0，y=2.0）
	var r2 := _build_ok(m, 10, 10, {}, SIZE, STEP, 0.5)
	var a_center := Hex.axial_to_world(a, SIZE, 2.0)
	for f in _collect_faces(r2):
		if f["kind"] == "top" and f["cell"] == a and f["dir"] == 2:
			expect_almost_eq((Hex.inner_vertex(a, 2, SIZE, 0.5, 2.0) - a_center).length(),
				0.5, 1e-6, "solid_factor=0.5：内顶点距格心 = 0.5")
			expect_eq(f["v1"], Hex.inner_vertex(a, 2, SIZE, 0.5, 2.0), "solid_factor 透传到顶面顶点")
			break
	# 非法参数 → 显式失败（builder 文件已测 null；此处核默认回显）
	var r3 := _build_ok(MapDataClass.new(2, 2))
	expect_eq(r3["elevation_step"], Builder.DEFAULT_ELEVATION_STEP, "默认 elevation_step 回显")
	expect_eq(r3["solid_factor"], Builder.DEFAULT_SOLID_FACTOR, "默认 solid_factor 回显")

# ================= 矩阵驱动（oracle 独立推导，不复制 builder 枚举）=================

## 三格角落组合矩阵：a=中心格 (1,1)（角 k=2 正北顶点）、b=N(a,2)、c=N(a,1)。
## 断言：角落恰一面且归属三格 ID 最小者；三顶点 y = 各格高程×step；
## 位置逐位 = HexMath 全局公式（归属格视角）+ 跨格视角容差对账；绕序朝上；
## 三条边带（a-b、a-c、b-c）各恰一 quad、分类正确、归属正确。
func _run_corner_matrix(ha: int, hb: int, hc: int) -> void:
	var m := MapDataClass.new(5, 5)
	var a := Hex.axial_of(Vector2i(1, 1))
	var b := Hex.neighbor(a, 2)
	var c := Hex.neighbor(a, 1)
	expect(m.has_cell(a) and m.has_cell(b) and m.has_cell(c), "矩阵三格须界内")
	m.set_elevation(a, ha)
	m.set_elevation(b, hb)
	m.set_elevation(c, hc)
	var r := _build_ok(m)
	var faces := _collect_faces(r)
	# 全图角落物理 key 恰一面（5×5 小图顺带全量）
	var corner_counts := {}
	for f in faces:
		if f["kind"] == "corner":
			var key := _corner_key(f["cell"], f["dir"])
			corner_counts[key] = int(corner_counts.get(key, 0)) + 1
	for key in corner_counts:
		expect_eq(corner_counts[key], 1, "每个物理角恰一角落面（组合 %d/%d/%d）%s" % [ha, hb, hc, key])
	# 归属 = 三格稳定 ID 最小者；角编号由"邻居集合匹配"独立推导
	var trio: Array[Vector2i] = [a, b, c]
	var owner: Vector2i = a
	for cell in trio:
		if m.index_of(cell) < m.index_of(owner):
			owner = cell
	var others: Array[Vector2i] = []
	for cell in trio:
		if cell != owner:
			others.append(cell)
	var j := _vertex_index_facing_pair(m, owner, others)
	expect(j >= 0, "owner 视角角编号可推导（组合 %d/%d/%d）" % [ha, hb, hc])
	# 目标角落面：恰一面，(cell,dir) = (owner, j)
	var target: Array[Dictionary] = []
	for f in faces:
		if f["kind"] == "corner" and f["cell"] == owner and f["dir"] == j:
			target.append(f)
	expect_eq(target.size(), 1, "目标角落恰一面被 owner 生成（组合 %d/%d/%d）" % [ha, hb, hc])
	if target.is_empty():
		return
	var f: Dictionary = target[0]
	# 位置 oracle（同路径逐位）：p1 = owner.inner_j；p2 = +bridge_j（N(owner,j) 侧）；
	# p3 = +bridge_{j-1}（N(owner,j-1) 侧）；面序 (p1, p3, p2)
	var n_j := Hex.neighbor(owner, j)
	var n_j1 := Hex.neighbor(owner, j - 1)
	var p1 := Hex.inner_vertex(owner, j, SIZE, SOLID, float(m.elevation_at(owner)) * STEP)
	var br_j := Hex.bridge_xz(owner, j, SIZE, SOLID)
	var br_j1 := Hex.bridge_xz(owner, j - 1, SIZE, SOLID)
	var p2 := p1 + Vector3(br_j.x, 0.0, br_j.y)
	var p3 := p1 + Vector3(br_j1.x, 0.0, br_j1.y)
	p2.y = float(m.elevation_at(n_j)) * STEP
	p3.y = float(m.elevation_at(n_j1)) * STEP
	expect_eq(f["v0"], p1, "角落 v0 = owner.inner_j（组合 %d/%d/%d）" % [ha, hb, hc])
	expect_eq(f["v1"], p3, "角落 v1 = N(owner,j-1) 侧端点（组合 %d/%d/%d）" % [ha, hb, hc])
	expect_eq(f["v2"], p2, "角落 v2 = N(owner,j) 侧端点（组合 %d/%d/%d）" % [ha, hb, hc])
	# y 显式锚：三顶点 y = 三格高程（step=1）
	expect_eq(f["v0"].y, float(m.elevation_at(owner)), "角落 v0 y = owner 高程")
	expect_eq(f["v1"].y, float(m.elevation_at(n_j1)), "角落 v1 y = N(owner,j-1) 高程")
	expect_eq(f["v2"].y, float(m.elevation_at(n_j)), "角落 v2 y = N(owner,j) 高程")
	# 跨路径对账：三格各自视角的同一物理内顶点（1e-5）
	for cell in trio:
		var rest: Array[Vector2i] = []
		for x in trio:
			if x != cell:
				rest.append(x)
		var jx := _vertex_index_facing_pair(m, cell, rest)
		expect(jx >= 0, "三格视角角编号均可推导 %s" % cell)
		if jx < 0:
			continue
		var expect_pt := Hex.inner_vertex(cell, jx, SIZE, SOLID, float(m.elevation_at(cell)) * STEP)
		var best := 1e9
		for v in [f["v0"], f["v1"], f["v2"]]:
			best = minf(best, v.distance_to(expect_pt))
		expect(best <= CROSS_PATH_EPS,
			"角落顶点 = %s 视角同一物理点（组合 %d/%d/%d）" % [cell, ha, hb, hc])
	# 绕序朝上（任意高程组合不翻转）
	expect((f["v1"] - f["v0"]).cross(f["v2"] - f["v0"]).y > 0.0,
		"角落面绕序朝上（组合 %d/%d/%d）" % [ha, hb, hc])
	# 三条边带：各恰一 quad、归属/分类/顶点正确
	_expect_matrix_edge(faces, m, a, b, ha, hb, hc)
	_expect_matrix_edge(faces, m, a, c, ha, hb, hc)
	_expect_matrix_edge(faces, m, b, c, ha, hb, hc)
	# 顶面 y 锚：三格各自顶面恒平（首版不扰动）
	for cell in trio:
		for g in faces:
			if g["kind"] == "top" and g["cell"] == cell:
				expect_eq(g["v0"].y, float(m.elevation_at(cell)) * STEP,
					"顶面格心 y = 本格高程 %s" % cell)

## 一对格的边带 oracle：归属 = min ID、方向 = dir_between、分类 = classify(Δh)、
## 两面顶点逐位 = (v1,v3,v4)+(v1,v4,v2)、跨路径对账、绕序。
func _expect_matrix_edge(faces: Array[Dictionary], m, x: Vector2i, y: Vector2i,
		ha: int, hb: int, hc: int) -> void:
	var owner: Vector2i = x if m.index_of(x) < m.index_of(y) else y
	var other: Vector2i = y if owner == x else x
	var d := Hex.dir_between(owner, other)
	expect(d >= 0, "格对应相邻 %s %s" % [x, y])
	var want_type := Builder.classify_edge(m.elevation_at(x) - m.elevation_at(y))
	var found: Array[Dictionary] = []
	for f in faces:
		if f["kind"] == "edge" and f["cell"] == owner and f["dir"] == d:
			found.append(f)
	expect_eq(found.size(), 2, "边带恰 2 面（%s-%s，组合 %d/%d/%d）" % [x, y, ha, hb, hc])
	if found.size() != 2:
		return
	for f in found:
		expect_eq(f["edge_type"], want_type, "边带分类 = classify(Δh)（%s-%s）" % [x, y])
	var h0 := float(m.elevation_at(owner)) * STEP
	var h1 := float(m.elevation_at(other)) * STEP
	var v1 := Hex.inner_vertex(owner, d, SIZE, SOLID, h0)
	var v2 := Hex.inner_vertex(owner, (d + 1) % 6, SIZE, SOLID, h0)
	var br := Hex.bridge_xz(owner, d, SIZE, SOLID)
	var v3 := v1 + Vector3(br.x, 0.0, br.y)
	var v4 := v2 + Vector3(br.x, 0.0, br.y)
	v3.y = h1
	v4.y = h1
	expect_eq(found[0]["v0"], v1, "边带面0 v0（%s-%s）" % [x, y])
	expect_eq(found[0]["v1"], v3, "边带面0 v1 = 对面侧端点（%s-%s）" % [x, y])
	expect_eq(found[0]["v2"], v4, "边带面0 v2（%s-%s）" % [x, y])
	expect_eq(found[1]["v0"], v1, "边带面1 v0（%s-%s）" % [x, y])
	expect_eq(found[1]["v1"], v4, "边带面1 v1（%s-%s）" % [x, y])
	expect_eq(found[1]["v2"], v2, "边带面1 v2（%s-%s）" % [x, y])
	# 跨路径对账：远端两顶点 = other 视角自己的内顶点（编号 = 共享顶点换算）
	_expect_vec3_eq_eps(v3, Hex.inner_vertex(other, (d + 4) % 6, SIZE, SOLID, h1),
		CROSS_PATH_EPS, "边带 v3 = other.inner_{(d+4)%%6}（%s-%s）" % [x, y])
	_expect_vec3_eq_eps(v4, Hex.inner_vertex(other, (d + 3) % 6, SIZE, SOLID, h1),
		CROSS_PATH_EPS, "边带 v4 = other.inner_{(d+3)%%6}（%s-%s）" % [x, y])
	for f in found:
		expect((f["v1"] - f["v0"]).cross(f["v2"] - f["v0"]).y > 0.0, "边带绕序朝上（%s-%s）" % [x, y])

## 独立推导：cell 的哪个顶点 k 恰面向"邻居对 {others[0], others[1]}"
##（即 N(cell,k)、N(cell,k−1) 与 others 集合相等）——不复制 builder 的枚举方向。
func _vertex_index_facing_pair(m, cell: Vector2i, others: Array[Vector2i]) -> int:
	for cand in 6:
		var n1 := Hex.neighbor(cell, cand)
		var n2 := Hex.neighbor(cell, cand - 1)
		if _same_set([n1, n2], others):
			return cand
	return -1

func _same_set(x: Array, y: Array) -> bool:
	if x.size() != y.size():
		return false
	for e in x:
		if not y.has(e):
			return false
	return true

# ================= 全量不变量（焊接流形 / 重复面 key / 共面重叠 / 法线）=================

## 输入全图 faces（含 v0/v1/v2），断言：
##   ① 面数 = oracle（顶面 6N / 边带 2E / 角落 C）；
##   ② 焊接后无重复面 key（同三元组面 = 归属规则破坏）；
##   ③ 每条焊接边恰 1 或 2 面引用（>2 = 重复面；0 中断不可能——边来自面）；
##   ④ 1 面边界边集合 = 期望外沿边（顶面外沿边 + 缺角暴露的边带侧边——焊接联合求解）；
##   ⑤ 全部面法线 y > 0（无翻转面 = 破面的另一形态）；
##   ⑥ 无共面重叠面（共享焊接顶点 + 法线近平行 + 共面 + 重叠面积 > 阈 → z-fighting）。
func _expect_full_invariants(faces: Array[Dictionary], m, label: String) -> void:
	# ① 面数 oracle
	var top := 0
	var edge := 0
	var corner := 0
	for f in faces:
		match f["kind"]:
			"top": top += 1
			"edge": edge += 1
			"corner": corner += 1
	expect_eq(top, m.cell_count() * 6, "%s：顶面 = 6×格数" % label)
	expect_eq(edge, _interior_edge_count(m) * 2, "%s：边带面 = 2×内部边 oracle" % label)
	expect_eq(corner, _interior_corner_count(m), "%s：角落面 = 内部角 oracle" % label)
	# 焊接（mesh 顶点 + 期望边界边端点同批聚类——期望端点与实际顶点同物理点必同簇）
	var verts := _flat_verts(faces)
	var boundary_expected := _expected_boundary_edges(m)
	for e in boundary_expected:
		verts.append(e[0])
		verts.append(e[1])
	var ids := _weld(verts)
	var mesh_face_count := faces.size()
	# ② 无重复面 key
	var seen_tris := {}
	for fi in mesh_face_count:
		var triple: Array[int] = [ids[fi * 3], ids[fi * 3 + 1], ids[fi * 3 + 2]]
		triple.sort()
		var key := "%d|%d|%d" % [triple[0], triple[1], triple[2]]
		expect(not seen_tris.has(key), "%s：重复面 key（同一焊接三角形出现两次）%s" % [label, key])
		seen_tris[key] = true
	# ③ 边引用闭合：恰 1 或 2 面
	var edge_counts := {}
	for fi in mesh_face_count:
		var a: int = ids[fi * 3]
		var b: int = ids[fi * 3 + 1]
		var c: int = ids[fi * 3 + 2]
		_bump_edge(edge_counts, a, b)
		_bump_edge(edge_counts, b, c)
		_bump_edge(edge_counts, c, a)
	for key in edge_counts:
		expect(edge_counts[key] <= 2, "%s：边被 >2 面引用（重复面）%s = %d" % [label, key, edge_counts[key]])
		expect(edge_counts[key] >= 1, "%s：边引用为 0 %s" % [label, key])
	# ④ 1 面边界边 = 期望外沿边（双向：集合相等；期望边端点与实际顶点联合焊接，
	#    同物理点必落同簇——key 精确匹配，无量化跨桶风险）
	var actual_boundary := {}
	for key in edge_counts:
		if edge_counts[key] == 1:
			actual_boundary[key] = true
	var expected_boundary := {}
	for i in boundary_expected.size():
		var base: int = mesh_face_count * 3 + i * 2
		var k := "%d_%d" % [mini(ids[base], ids[base + 1]), maxi(ids[base], ids[base + 1])]
		expected_boundary[k] = true
		expect(actual_boundary.has(k), "%s：期望外沿边未被恰好 1 面引用（边 #%d）" % [label, i])
	var only_actual := 0
	for key in actual_boundary:
		if not expected_boundary.has(key):
			only_actual += 1
			fail("%s：出现未预期的 1 面边（破面/缺角）weld key %s" % [label, key])
	expect_eq(only_actual, 0, "%s：1 面边集合 ⊆ 期望外沿" % label)
	expect_eq(expected_boundary.size() > 0, true, "%s：期望外沿非空" % label)
	# ⑤ 法线恒朝上侧
	for f in faces:
		expect(_normal_y(f) > 0.0, "%s：面法线 y > 0（无翻转）%s" % [label, str(f["cell"])])
	# ⑥ 共面重叠面（z-fighting）
	_expect_no_coplanar_overlap(faces, ids, label)

func _flat_verts(faces: Array[Dictionary]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.resize(faces.size() * 3)
	for fi in faces.size():
		out[fi * 3] = faces[fi]["v0"]
		out[fi * 3 + 1] = faces[fi]["v1"]
		out[fi * 3 + 2] = faces[fi]["v2"]
	return out

## 期望外沿边（物理位置对，y = 各格高程——顶点 y 参与焊接 key，漏高程会错配簇）：
## ① 无邻居方向的顶面外沿边 (inner_d, inner_{d+1})（同高 y=h(cell)）；
## ② 邻居存在但相邻角缺失时暴露的边带侧边 (inner_k, inner_k + bridge)
##   （两端 y = h(cell) / h(nb)——侧边连接两格各自内顶点）。
## 从任意格视角枚举（同一物理边会被两侧各数一次——焊接后按 key 去重，见调用方）。
func _expected_boundary_edges(m) -> Array:
	var out: Array = []
	for cell in m.cells():
		var h := float(m.elevation_at(cell)) * STEP
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			var v1 := Hex.inner_vertex(cell, d, SIZE, SOLID, h)
			var v2 := Hex.inner_vertex(cell, (d + 1) % 6, SIZE, SOLID, h)
			if not m.has_cell(nb):
				out.append([v1, v2])
				continue
			var br := Hex.bridge_xz(cell, d, SIZE, SOLID)
			var hnb := float(m.elevation_at(nb)) * STEP
			if not m.has_cell(Hex.neighbor(cell, d - 1)):
				var far1 := v1 + Vector3(br.x, 0.0, br.y)
				far1.y = hnb
				out.append([v1, far1])
			if not m.has_cell(Hex.neighbor(cell, d + 1)):
				var far2 := v2 + Vector3(br.x, 0.0, br.y)
				far2.y = hnb
				out.append([v2, far2])
	return out

func _bump_edge(counts: Dictionary, u: int, v: int) -> void:
	var key := "%d_%d" % [mini(u, v), maxi(u, v)]
	counts[key] = int(counts.get(key, 0)) + 1

func _normal_y(f: Dictionary) -> float:
	return (f["v1"] - f["v0"]).cross(f["v2"] - f["v0"]).y

## 空间哈希聚类焊接（WELD_EPS 半径；最近不同物理点距 ≈ 0.1——无错误合并风险）。
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

## 共面重叠面检测：只查共享 ≥1 焊接顶点的面对（z-fighting 的实际来源；不相邻的
## 重叠对必然伴随大面积悬垂/破面，已被边闭合检查覆盖）。投影到面法线正交基后
## Sutherland-Hodgman 裁剪求交集面积（陡面同样适用——不投 xz）。
func _expect_no_coplanar_overlap(faces: Array[Dictionary], ids: Array[int], label: String) -> void:
	var vert_faces := {}
	for fi in faces.size():
		for w in [ids[fi * 3], ids[fi * 3 + 1], ids[fi * 3 + 2]]:
			if not vert_faces.has(w):
				vert_faces[w] = [] as Array[int]
			(vert_faces[w] as Array[int]).append(fi)
	var checked := {}
	for w in vert_faces:
		var fl: Array[int] = vert_faces[w]
		for i in fl.size():
			for j in range(i + 1, fl.size()):
				var fa: int = fl[i]
				var fb: int = fl[j]
				var pk := "%d_%d" % [mini(fa, fb), maxi(fa, fb)]
				if checked.has(pk):
					continue
				checked[pk] = true
				var na := _face_normal(faces[fa])
				var nb := _face_normal(faces[fb])
				if na.dot(nb) < 0.9999:
					continue
				var off: float = absf(na.dot(faces[fb]["v0"] - faces[fa]["v0"]))
				if off > 1e-4:
					continue
				var area := _overlap_area(faces[fa], faces[fb], na)
				# 阈值口径：两路计算（归属格/邻格视角）的共享边端点有 ≤~1ulp 的 float32 差，
				# 共面相邻面因此产生 ~1e-6·边长 量级的微条带（视觉不可见、非 z-fighting）；
				# 真重叠（重复面/错位面）面积与面本身同量级（≥1e-2）。阈 1e-4 隔开三个数量级。
				if area > 1e-4:
					fail("%s：共面重叠面（z-fighting）面#%d × 面#%d，交叠面积 %s"
						% [label, fa, fb, str(area)])

func _face_normal(f: Dictionary) -> Vector3:
	return (f["v1"] - f["v0"]).cross(f["v2"] - f["v0"]).normalized()

## 面交叠面积：fb 投影到 fa 平面基底，被 fa 三边裁剪（保留 fa 内部侧）后鞋带面积。
func _overlap_area(fa: Dictionary, fb: Dictionary, n: Vector3) -> float:
	var u: Vector3
	if absf(n.y) < 0.9:
		u = n.cross(Vector3.UP).normalized()
	else:
		u = n.cross(Vector3.RIGHT).normalized()
	var w := n.cross(u).normalized()
	var pa := [_proj2(fa["v0"], u, w), _proj2(fa["v1"], u, w), _proj2(fa["v2"], u, w)]
	var poly := [_proj2(fb["v0"], u, w), _proj2(fb["v1"], u, w), _proj2(fb["v2"], u, w)]
	for e in 3:
		poly = _clip_keep_side(poly, pa[e], pa[(e + 1) % 3], pa[(e + 2) % 3])
		if poly.is_empty():
			return 0.0
	return _poly_area(poly)

func _proj2(p: Vector3, u: Vector3, w: Vector3) -> Vector2:
	return Vector2(p.dot(u), p.dot(w))

## 半平面裁剪：保留与 ref 同侧（含线上）的部分。
func _clip_keep_side(poly: Array, e1: Vector2, e2: Vector2, ref: Vector2) -> Array:
	var out: Array = []
	var n := poly.size()
	if n == 0:
		return out
	var sr := _side2(e1, e2, ref)
	for i in n:
		var cur: Vector2 = poly[i]
		var nxt: Vector2 = poly[(i + 1) % n]
		var sc := _side2(e1, e2, cur)
		var sn := _side2(e1, e2, nxt)
		var cur_in := sc * sr >= 0.0
		var nxt_in := sn * sr >= 0.0
		if cur_in:
			out.append(cur)
		if cur_in != nxt_in and absf(sc - sn) > 1e-18:
			var t := sc / (sc - sn)
			out.append(cur + (nxt - cur) * t)
	return out

func _side2(e1: Vector2, e2: Vector2, p: Vector2) -> float:
	return (e2.x - e1.x) * (p.y - e1.y) - (e2.y - e1.y) * (p.x - e1.x)

func _poly_area(poly: Array) -> float:
	var n := poly.size()
	if n < 3:
		return 0.0
	var s := 0.0
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5

# ================= 公共辅助（与 test_hex_terrain_builder.gd 同口径）=================

func _build_ok(m, chunk_cols := 10, chunk_rows := 10, colors := {}, size := SIZE,
		elevation_step := STEP, solid_factor := SOLID) -> Dictionary:
	var r: Variant = Builder.build_map(m, chunk_cols, chunk_rows, colors, size, elevation_step, solid_factor)
	expect(r is Dictionary, "build_map 应成功（返回 Dictionary）")
	if r is Dictionary:
		return r as Dictionary
	return {"chunks": [], "chunk_rects": [], "materials": {}}

func _interior_edge_count(m) -> int:
	var n := 0
	for cell in m.cells():
		for d in 3:
			if m.has_cell(Hex.neighbor(cell, d)):
				n += 1
	return n

func _interior_corner_count(m) -> int:
	var n := 0
	for cell in m.cells():
		for k in 6:
			if m.has_cell(Hex.neighbor(cell, k)) and m.has_cell(Hex.neighbor(cell, k - 1)):
				n += 1
	return n / 3

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

func _edge_key(cell: Vector2i, dir: int) -> String:
	var b := Hex.neighbor(cell, dir)
	var pa := cell
	var pb := b
	if pb.x < pa.x or (pb.x == pa.x and pb.y < pa.y):
		var t := pa
		pa = pb
		pb = t
	return "e|%d,%d|%d,%d" % [pa.x, pa.y, pb.x, pb.y]

func _corner_key(cell: Vector2i, k: int) -> String:
	var ids := ["%d,%d" % [cell.x, cell.y]]
	for nb in [Hex.neighbor(cell, k), Hex.neighbor(cell, k - 1)]:
		ids.append("%d,%d" % [nb.x, nb.y])
	ids.sort()
	return "c|" + "|".join(ids)

func _rect_of(rects: Array, cell: Vector2i) -> Rect2i:
	var off := Hex.offset_of(cell)
	for rect in rects:
		if (rect as Rect2i).has_point(off):
			return rect
	return Rect2i()

func _expect_vec3_eq_eps(a: Vector3, b: Vector3, eps: float, msg: String) -> void:
	_checks += 1
	if a.distance_to(b) > eps:
		_fails.append("%s：got=%s want=%s eps=%s" % [msg, str(a), str(b), str(eps)])
