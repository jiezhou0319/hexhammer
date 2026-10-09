## test_hex_picking.gd — M1a-T5 拾取链路单测 · 纯逻辑层（hex_picking.gd 重点覆盖）
## 覆盖 04 M1a-T5「验收 + 细化新增」的纯规则面：
##   - 顶面归本格（微决策 3）+ 顶面 rounding 链一致性（局部 XZ → 浮点 axial → cube
##     rounding 恒回本格——内六边形整块在 hex Voronoi 内）；
##   - 边带归属：flat/slope = 局部 XZ 最近逻辑格心、距离相等按棋盘固定 ID
##     （index_of）决胜（正反用例 + 全 6 方向对称）；cliff = 高地侧（含「XZ 更近的
##     低格不得截胡」反例与「ID 决胜偏向低格仍归高格」反例）；
##   - 角落归属（三格，微决策 3 对角落的泛化口径，见 hex_picking.gd 头注）：
##     max−min ≥ 2 → 最高格（含并列最高 ID 决胜与「面归属格 ≠ 结果格」判别例）；
##     否则 → 最近格心（含共享外顶点三向精确平局 → 最小 ID）；
##   - face→格映射数据层：碰撞三角形汤 = mesh surface 顶点数组按构建序拼接（逐位）、
##     face 表逐索引对应、ConcavePolygonShape3D set/get_faces 往返保序
##     （引擎 face_index 语义的小场景校验在 tools/picking_scene_check.gd，见其头注）；
##   - resolve_hit/resolve_face 契约：越界 face_index / 未知 kind → null（无静默兜底）；
##   - 地图根平移的纯数学回归：Transform3D 往返 + 归属不变（节点级 to_local 同数学，
##     射线级回归在 test_hex_picking_ray.gd）。
## oracle 原则：期望值由测试内独立算术（距离比较 / index_of 比较 / 手算锚点）推导，
##   不复制 pick_* 实现的内部顺序；锚点用例（东向对 (0,0)-(1,0)）手工展开。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Lib := preload("res://scripts/core/data/terrain_material_library.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const Picking := preload("res://addons/hexhammer/hex_picking.gd")

const SIZE := 1.0
const SOLID := 0.8  # = Builder.DEFAULT_SOLID_FACTOR（连接带 t∈(0.4,0.6) 的参数源）

# ================= 顶面：归本格 + rounding 链一致性 =================

func test_top_face_resolves_to_own_cell() -> void:
	var m := MapDataClass.new(5, 5)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_elevation(cell, (cr.x * 2 + cr.y * 3) % 5 - 2)  # −2..2 含负层
	for cell in m.cells():
		var h := float(m.elevation_at(cell))
		# 顶面扇区 k 的命中点：格心与两内顶点重心（严格在顶面上）
		for k in 6:
			var a := Hex.axial_to_world(cell, SIZE, h)
			var b := Hex.inner_vertex(cell, k, SIZE, SOLID, h)
			var c := Hex.inner_vertex(cell, (k + 1) % 6, SIZE, SOLID, h)
			var hit := (a + b + c) / 3.0
			var face := {"kind": "top", "cell": cell, "dir": k}
			expect_eq(Picking.resolve_face(hit, face, m, SIZE), cell,
				"顶面归本格 %s 扇区 %d" % [str(cell), k])

func test_top_face_rounding_chain_consistency() -> void:
	# 内六边形内的点经「局部 XZ → 浮点 axial → cube rounding」恒回本格
	#（含负坐标格：offset (0,2) → axial (−1,2)）
	var m := MapDataClass.new(5, 5)
	var center_cell := Hex.axial_of(Vector2i(2, 2))
	var neg_cell := Hex.axial_of(Vector2i(0, 2))
	expect_eq(neg_cell.x < 0, true, "样本须含负坐标格")
	for cell in [center_cell, neg_cell]:
		var center := Hex.axial_to_world(cell, SIZE)
		for k in 6:
			var v := Hex.vertex_xz(cell, k, SIZE)
			var p := Vector3(center.x + (v.x - center.x) * 0.75, 0.0, center.z + (v.y - center.z) * 0.75)
			expect_eq(Hex.world_to_axial(p, SIZE), cell,
				"内六边形点 rounding 回本格 %s 方向 %d" % [str(cell), k])
		expect_eq(Hex.world_to_axial(center, SIZE), cell, "格心 rounding 回本格")

# ================= 边带：flat / slope = 最近格心 + ID 决胜 =================

func _lerp_centers(a: Vector2i, b: Vector2i, t: float) -> Vector3:
	var ca := Hex.axial_to_world(a, SIZE)
	var cb := Hex.axial_to_world(b, SIZE)
	return ca + (cb - ca) * t  # y=0：XZ 归属比较与高程无关

func test_flat_edge_nearest_center() -> void:
	# 等高平连：最近格心（无高程可偏袒——纯 XZ 归属的基线）
	var m := MapDataClass.new(7, 7)
	var a := Hex.axial_of(Vector2i(3, 3))
	var b := Hex.neighbor(a, 0)
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.45), a, 0, m, SIZE), a,
		"flat：近 a 侧归 a")
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.55), a, 0, m, SIZE), b,
		"flat：近 b 侧归 b（不为面归属格所偏袒）")

func test_slope_edge_nearest_center_all_dirs() -> void:
	# |Δh|=1 斜坡：全 6 方向对称——期望由测试侧独立距离算术推导；
	# t=0.45/0.55 落在连接带 (0.4,0.6) 内（solid=0.8 ⇒ 带 = 中心连线中段 20%×2）
	var m := MapDataClass.new(7, 7)
	var a := Hex.axial_of(Vector2i(3, 3))
	for d in 6:
		var b := Hex.neighbor(a, d)
		m.set_elevation(a, 0)
		m.set_elevation(b, 1)
		for t in [0.45, 0.55]:
			var tt: float = t
			var p := _lerp_centers(a, b, tt)
			var da := Vector2(p.x, p.z).distance_to(Vector2(Hex.axial_to_world(a, SIZE).x, Hex.axial_to_world(a, SIZE).z))
			var db := Vector2(p.x, p.z).distance_to(Vector2(Hex.axial_to_world(b, SIZE).x, Hex.axial_to_world(b, SIZE).z))
			var want: Vector2i = a if da < db else b
			var got := Picking.pick_edge_band(p, a, d, m, SIZE)
			expect_eq(got, want, "slope 方向 %d t=%s：最近格心（测试侧独立推导）" % [d, str(tt)])
			# 反例锚：结果不得是无关于距离的另一格
			expect(got == a or got == b, "slope 结果必为边带两格之一")

func test_slope_edge_hand_computed_anchor() -> void:
	# 手算锚点（东向对）：a=(0,0) 心 x=0、b=(1,0) 心 x=√3 ⇒ t=0.45 → a、t=0.55 → b
	var m := MapDataClass.new(3, 3)
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	m.set_elevation(a, 0)
	m.set_elevation(b, 1)
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.45), a, 0, m, SIZE), a, "slope 锚：t=0.45 → (0,0)")
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.55), a, 0, m, SIZE), b, "slope 锚：t=0.55 → (1,0)")

func test_slope_tie_breaks_by_smaller_stable_id() -> void:
	# t=0.5 = 两格心连线中点：距离精确相等 → index_of 小者（全 6 方向）
	var m := MapDataClass.new(7, 7)
	var a := Hex.axial_of(Vector2i(3, 3))
	for d in 6:
		var b := Hex.neighbor(a, d)
		m.set_elevation(a, 0)
		m.set_elevation(b, 1)
		var p := _lerp_centers(a, b, 0.5)
		var want: Vector2i = a if m.index_of(a) < m.index_of(b) else b
		expect_eq(Picking.pick_edge_band(p, a, d, m, SIZE), want,
			"slope 平局：方向 %d 归稳定 ID 小者（index %d vs %d）" % [d, m.index_of(a), m.index_of(b)])
	# 反例：ID 决胜不得越权代替距离——近侧大 ID 格仍胜（t=0.45 时若 b ID 小仍须归 a）
	m = MapDataClass.new(7, 7)
	a = Hex.axial_of(Vector2i(3, 3))
	var b2 := Hex.neighbor(a, 1)  # 东北邻：index_of(b2) < index_of(a)（行更小）
	expect(m.index_of(b2) < m.index_of(a), "构造前提：b2 稳定 ID 更小")
	m.set_elevation(a, 0)
	m.set_elevation(b2, 1)
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b2, 0.45), a, 1, m, SIZE), a,
		"ID 决胜仅在平局：近侧大 ID 格仍归本格")

# ================= 边带：cliff = 高地侧 =================

func test_cliff_goes_to_high_side_all_dirs() -> void:
	# |Δh|=3 陡面：全 6 方向。低格在近侧（t 靠低格）仍归高格；高低反转亦然
	var m := MapDataClass.new(7, 7)
	var a := Hex.axial_of(Vector2i(3, 3))
	for d in 6:
		var b := Hex.neighbor(a, d)
		m.set_elevation(a, 0)
		m.set_elevation(b, 3)
		for t in [0.45, 0.5, 0.55]:
			var tt: float = t
			expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, tt), a, d, m, SIZE), b,
				"cliff 方向 %d t=%s：归高地侧 b（XZ 更近 a 也不得截胡）" % [d, str(tt)])
		# 反例：不为 ID 决胜/最近格心所动
		expect(Picking.pick_edge_band(_lerp_centers(a, b, 0.45), a, d, m, SIZE) != a,
			"cliff 反例：近侧低格 a 不得截获")
		m.set_elevation(a, 3)
		m.set_elevation(b, 0)
		expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.55), a, d, m, SIZE), a,
			"cliff 方向 %d 反转：a 高且远侧命中仍归 a" % d)

func test_cliff_vs_slope_classification_boundary() -> void:
	# |Δh|=2 即 cliff（Catlike 口径 ≥2）；|Δh|=1 是 slope——分类边界两侧规则切换
	var m := MapDataClass.new(5, 5)
	var a := Hex.axial_of(Vector2i(2, 2))
	var b := Hex.neighbor(a, 0)
	m.set_elevation(a, 0)
	m.set_elevation(b, 2)
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.45), a, 0, m, SIZE), b,
		"|Δh|=2 = cliff：归高地侧")
	m.set_elevation(b, 1)
	expect_eq(Picking.pick_edge_band(_lerp_centers(a, b, 0.45), a, 0, m, SIZE), a,
		"|Δh|=1 = slope：归最近格心（近 a 侧）")

# ================= 角落：三格归属（微决策 3 泛化口径）=================

## 三格角落矩阵：trio = {a=(1,1), b=N(a,2), c=N(a,1)}，返回 [owner（ID 最小者）,
## owner 视角角编号 j]（由「邻居对匹配」独立推导，不复制 builder 枚举）。
func _owner_and_corner(m, a: Vector2i, b: Vector2i, c: Vector2i) -> Array:
	var trio: Array[Vector2i] = [a, b, c]
	var owner := trio[0]
	for cell in trio:
		if m.index_of(cell) < m.index_of(owner):
			owner = cell
	var others: Array[Vector2i] = []
	for cell in trio:
		if cell != owner:
			others.append(cell)
	for j in 6:
		if others.has(Hex.neighbor(owner, j)) and others.has(Hex.neighbor(owner, j - 1)):
			return [owner, j]
	return [Vector2i(), -1]

## 角落三角重心（oracle 顶点：owner.inner_j / +bridge_j / +bridge_{j-1}，HexMath 全局公式）
func _corner_centroid(m, owner: Vector2i, j: int) -> Vector3:
	var p1 := Hex.inner_vertex(owner, j, SIZE, SOLID, float(m.elevation_at(owner)))
	var br_j := Hex.bridge_xz(owner, j, SIZE, SOLID)
	var br_j1 := Hex.bridge_xz(owner, j - 1, SIZE, SOLID)
	var p2 := p1 + Vector3(br_j.x, 0.0, br_j.y)
	var p3 := p1 + Vector3(br_j1.x, 0.0, br_j1.y)
	p2.y = 0.0
	p3.y = 0.0
	return (p1 + p2 + p3) / 3.0

func test_corner_cliff_goes_to_highest() -> void:
	# max−min ≥ 2（悬崖形角落）→ 最高格：含 (0,0,2)/(0,1,2)/(0,2,1)/负层组合
	var combos := [[0, 0, 2], [0, 1, 2], [0, 2, 1], [-1, 0, 2], [2, 2, 0]]
	for combo in combos:
		var ha: int = combo[0]
		var hb: int = combo[1]
		var hc: int = combo[2]
		var m := MapDataClass.new(5, 5)
		var a := Hex.axial_of(Vector2i(1, 1))
		var b := Hex.neighbor(a, 2)
		var c := Hex.neighbor(a, 1)
		m.set_elevation(a, ha)
		m.set_elevation(b, hb)
		m.set_elevation(c, hc)
		var oc := _owner_and_corner(m, a, b, c)
		var owner: Vector2i = oc[0]
		var j: int = oc[1]
		expect(j >= 0, "角编号可推导（组合 %d/%d/%d）" % [ha, hb, hc])
		if j < 0:
			continue
		# oracle：最高格；并列最高 → 稳定 ID 小者（与 pick_highest 同规格独立实现）
		var trio: Array[Vector2i] = [a, b, c]
		var want := trio[0]
		for cell in trio:
			if m.elevation_at(cell) > m.elevation_at(want) \
					or (m.elevation_at(cell) == m.elevation_at(want) and m.index_of(cell) < m.index_of(want)):
				want = cell
		var p := _corner_centroid(m, owner, j)
		var got := Picking.pick_corner(p, owner, j, m, SIZE)
		expect_eq(got, want, "悬崖形角落归最高格（组合 %d/%d/%d）" % [ha, hb, hc])
		expect(got != owner or want == owner,
			"归属格不得截胡最高格（组合 %d/%d/%d）" % [ha, hb, hc])
		# face 分发路径同结果（真实 builder 元数据形状）
		var face := {"kind": "corner", "cell": owner, "dir": j}
		expect_eq(Picking.resolve_face(p, face, m, SIZE), want,
			"resolve_face 角落分发（组合 %d/%d/%d）" % [ha, hb, hc])

func test_corner_highest_tie_breaks_by_id() -> void:
	# (2,0,2)：并列最高 {a,c} → index_of 小者 c——与面归属格（owner）解耦的判别例
	var m := MapDataClass.new(5, 5)
	var a := Hex.axial_of(Vector2i(1, 1))
	var b := Hex.neighbor(a, 2)
	var c := Hex.neighbor(a, 1)
	m.set_elevation(a, 2)
	m.set_elevation(b, 0)
	m.set_elevation(c, 2)
	var oc := _owner_and_corner(m, a, b, c)
	var owner: Vector2i = oc[0]
	var j: int = oc[1]
	expect_eq(Picking.pick_corner(_corner_centroid(m, owner, j), owner, j, m, SIZE), c,
		"并列最高取稳定 ID 小者（c=%d < a=%d）" % [m.index_of(c), m.index_of(a)])
	expect(owner != c, "判别前提：面归属格 owner ≠ 期望结果格 c")

func test_corner_slope_like_nearest_center() -> void:
	# max−min ≤ 1（等高/差一级）→ 最近格心：期望由测试侧独立距离算术推导
	var combos := [[0, 0, 1], [0, 1, 1], [1, 1, 1], [0, 0, 0], [-1, 0, 0]]
	for combo in combos:
		var ha: int = combo[0]
		var hb: int = combo[1]
		var hc: int = combo[2]
		var m := MapDataClass.new(5, 5)
		var a := Hex.axial_of(Vector2i(1, 1))
		var b := Hex.neighbor(a, 2)
		var c := Hex.neighbor(a, 1)
		m.set_elevation(a, ha)
		m.set_elevation(b, hb)
		m.set_elevation(c, hc)
		var oc := _owner_and_corner(m, a, b, c)
		var owner: Vector2i = oc[0]
		var j: int = oc[1]
		var p := _corner_centroid(m, owner, j)
		# 测试侧独立推导：三格最近格心（距离用各自格心现算；相等窗口 1e-6 内取 ID 小者）
		var trio: Array[Vector2i] = [a, b, c]
		var want := trio[0]
		var best_d := INF
		for cell in trio:
			var ctr := Hex.axial_to_world(cell, SIZE)
			var d := Vector2(p.x - ctr.x, p.z - ctr.z).length()
			if d < best_d - 1e-6:
				best_d = d
				want = cell
			elif absf(d - best_d) <= 1e-6 and m.index_of(cell) < m.index_of(want):
				best_d = mini(d, best_d)
				want = cell
		var got := Picking.pick_corner(p, owner, j, m, SIZE)
		expect_eq(got, want, "角落最近格心（组合 %d/%d/%d）" % [ha, hb, hc])
		# 全等高组合反例：不得走「最高格」分支（三格同高无高低可言）
		if ha == hb and hb == hc:
			expect(got == want, "全等高角落 = 最近格心而非任意最高")

func test_corner_three_way_tie_at_shared_vertex() -> void:
	# 共享外顶点到三格心等距（六边形外接圆半径，几何精确相等）→ 三向平局 → 最小 ID
	var m := MapDataClass.new(5, 5)
	var a := Hex.axial_of(Vector2i(1, 1))
	var b := Hex.neighbor(a, 2)
	var c := Hex.neighbor(a, 1)
	var oc := _owner_and_corner(m, a, b, c)
	var owner: Vector2i = oc[0]
	var j: int = oc[1]
	var v2 := Hex.vertex_xz(owner, j, SIZE)
	var p := Vector3(v2.x, 0.0, v2.y)
	for cell in [a, b, c]:
		var ctr := Hex.axial_to_world(cell, SIZE)
		# float32 几何噪声 ~1e-7（顶点经 cos/sin 现算）——构造前提按 1e-5 核对；
		# 规则平局窗口 1e-6 已覆盖该噪声（见 hex_picking.gd TIE_EPS 注）
		expect_almost_eq(Vector2(p.x - ctr.x, p.z - ctr.z).length(), SIZE, 1e-5,
			"构造前提：共享外顶点到 %s 心距 = size" % str(cell))
	var trio: Array[Vector2i] = [a, b, c]
	var want := trio[0]
	for cell in trio:
		if m.index_of(cell) < m.index_of(want):
			want = cell
	expect_eq(Picking.pick_corner(p, owner, j, m, SIZE), want,
		"三向精确平局 → 稳定 ID 最小者 %s" % str(want))

# ================= face→格映射（自提交碰撞三角形顺序，数据层）=================

func test_face_table_alignment_with_mesh_and_shape() -> void:
	# 5×5 混合高程：soup 三角形顺序 = mesh surface 构建序（face 表逐索引对应）；
	# 顶点序逐面翻转 (a,c,b)（Godot 正面 = 顺时针——引擎凹形状射线实测口径，
	# 见 hex_picking.gd chunk_collision_faces 注）；ConcavePolygonShape3D
	# set/get_faces 往返保序（face_index 语义的数据层前提；引擎级校验见
	# tools/picking_scene_check.gd）
	var m := MapDataClass.new(5, 5)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_elevation(cell, (cr.x * 2 + cr.y * 3) % 5 - 2)
	var r := _build_ok(m)
	var chunks: Array = r["chunks"]
	expect(chunks.size() > 0, "构建产出非空")
	var total_faces := 0
	for chunk_info in chunks:
		var cd: Dictionary = chunk_info
		var mesh: ArrayMesh = cd["mesh"]
		var pd: Dictionary = Picking.chunk_pick_data(cd)
		var soup: PackedVector3Array = pd["collision_faces"]
		var table: Array[Dictionary] = pd["face_table"]
		expect_eq(soup.size() % 3, 0, "三角形汤顶点数为 3 的倍数")
		expect_eq(table.size() * 3, soup.size(), "face 表与三角形逐索引对应（自提交顺序）")
		# 逐位对账：soup 三角形 = mesh 顶点三角按构建序、每面翻转 (a,c,b)
		var manual := PackedVector3Array()
		var manual_faces: Array[Dictionary] = []
		for si in (cd["surfaces"] as Array).size():
			var arrays: Array = mesh.surface_get_arrays(si)
			manual.append_array(arrays[Mesh.ARRAY_VERTEX])
			var sd: Dictionary = (cd["surfaces"] as Array)[si]
			manual_faces.append_array(sd["faces"])
		expect_eq(soup.size(), manual.size(), "soup 与 mesh 顶点数一致")
		var flip_ok := true
		for t in soup.size() / 3:
			if not (soup[t * 3] == manual[t * 3] and soup[t * 3 + 1] == manual[t * 3 + 2] \
					and soup[t * 3 + 2] == manual[t * 3 + 1]):
				flip_ok = false
				break
		expect(flip_ok, "soup 每三角 = mesh 三角翻转 (a,c,b)（Godot 正面=顺时针）")
		expect_eq(table, manual_faces, "face 表 = surfaces faces 按构建序拼接（逐项）")
		# 引擎形状保序
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(soup)
		expect_eq(shape.get_faces(), soup, "ConcavePolygonShape3D 往返保序（set_faces 原样保存）")
		total_faces += table.size()
	expect(total_faces > 0, "face 表非空")

func test_resolve_hit_dispatch_and_null_contract() -> void:
	# 真实 face 表上的分发 + 越界/未知 → null（无静默兜底）
	var m := MapDataClass.new(3, 3)
	var a := Hex.axial_of(Vector2i(1, 1))
	m.set_elevation(a, 2)
	var r := _build_ok(m)
	var cd: Dictionary = (r["chunks"] as Array)[0]
	var pd: Dictionary = Picking.chunk_pick_data(cd)
	var table: Array[Dictionary] = pd["face_table"]
	# 找 a 的顶面面号：格心直查
	var a_center := Hex.axial_to_world(a, SIZE, 2.0)
	var top_fi := -1
	for fi in table.size():
		if String(table[fi]["kind"]) == "top" and table[fi]["cell"] == a:
			top_fi = fi
			break
	expect(top_fi >= 0, "a 的顶面在 face 表中可寻")
	if top_fi >= 0:
		expect_eq(Picking.resolve_hit(a_center, top_fi, table, m, SIZE), a,
			"resolve_hit：有效 face_index 分发到顶面归本格")
	expect(Picking.resolve_hit(a_center, -1, table, m, SIZE) == null,
		"face_index=-1 → null（非凹形状语义/未知面）")
	expect(Picking.resolve_hit(a_center, table.size(), table, m, SIZE) == null,
		"face_index 越界 → null")
	expect(Picking.resolve_face(a_center, {"kind": "decoration"}, m, SIZE) == null,
		"未知 kind → null")
	expect(Picking.resolve_face(a_center, {"dir": 0}, m, SIZE) == null,
		"缺 kind 字段 → null")

# ================= 碰撞层常量（射线 mask 纪律的契约面）=================

func test_collision_layer_mask_constants() -> void:
	expect_eq(Picking.LAYER_TERRAIN, 1, "地形层 = 层 1（写死约定）")
	expect_eq(Picking.MASK_TERRAIN_ONLY, 1 << (Picking.LAYER_TERRAIN - 1),
		"mask = 地形层单一位")
	expect(Picking.LAYER_TERRAIN != Picking.LAYER_PICKABLE, "地形层与棋子/装饰层不得同位")
	expect(Picking.LAYER_TERRAIN >= 1 and Picking.LAYER_TERRAIN <= 32, "层号 ∈ [1,32]")
	expect(Picking.LAYER_PICKABLE >= 1 and Picking.LAYER_PICKABLE <= 32, "层号 ∈ [1,32]")
	expect(Picking.MASK_TERRAIN_ONLY & (1 << (Picking.LAYER_PICKABLE - 1)) == 0,
		"拾取 mask 不含棋子/高亮/装饰层（不得截获）")

# ================= 地图根平移（纯数学回归；射线级见 test_hex_picking_ray.gd）=================

func test_local_transform_roundtrip_resolution_stable() -> void:
	# 世界 ↔ 局部（纯平移）：Transform3D 往返逐位、归属不变——view 层 to_local 的数学
	var m := MapDataClass.new(3, 3)
	var a := Hex.axial_of(Vector2i(1, 1))
	m.set_elevation(a, 2)
	var face := {"kind": "top", "cell": a, "dir": 0}
	var p := Hex.axial_to_world(a, SIZE, 2.0)
	for t in [Vector3(37.5, -12.25, 8.0), Vector3(-13.0, 4.0, 21.0), Vector3.ZERO]:
		var tv: Vector3 = t
		var xf := Transform3D(Basis(), tv)
		var world := xf * p
		var back := xf.affine_inverse() * world
		# float32 精度：大平移量下 xform 往返误差 ~|T|·2^-23（37.5 → ~5e-6）——按 1e-4 核
		expect(back.distance_to(p) <= 1e-4, "平移往返逐位（T=%s）" % str(tv))
		expect_eq(Picking.resolve_face(back, face, m, SIZE), a,
			"局部命中点归属不随地图根平移改变（T=%s）" % str(tv))
		# 斜坡规则同样只吃局部坐标：平移后世界点先转回局部再解析，结果一致
		var nb := Hex.neighbor(a, 0)
		m.set_elevation(nb, 1)
		var sp := _lerp_centers(a, nb, 0.45)
		var xf2 := Transform3D(Basis(), tv)
		var sp_back := xf2.affine_inverse() * (xf2 * sp)
		expect_eq(Picking.pick_edge_band(sp_back, a, 0, m, SIZE), a, "斜坡归属平移不变")

# ================= 辅助 =================

## 单类型材质表（M1a-T8 起 builder 只认 {terrain_id: Material}）
func _mats() -> Dictionary:
	return Lib.materials_from_colors({0: Color(0.5, 0.5, 0.5)})

func _build_ok(m, chunk_cols := 10, chunk_rows := 10) -> Dictionary:
	var r: Variant = Builder.build_map(m, chunk_cols, chunk_rows, _mats(), SIZE, 1.0, SOLID)
	expect(r is Dictionary, "build_map 应成功（返回 Dictionary）")
	if r is Dictionary:
		return r as Dictionary
	return {"chunks": [], "chunk_rects": [], "materials": {}}
