## test_hex_math.gd — M1a-T1 hex 数学单测
## 逐条覆盖 04 任务卡「验收 + 细化新增」：
##   邻居/边界判定、邻居反向对称、距离对称、axial↔世界坐标往返、
##   负坐标与 cube rounding（修正最大误差轴，不许两轴各自四舍五入——Red Blob 口径）；
##   另覆盖交付项「顶点与朝向」的几何一致性（T4 边带几何的拓扑基）。
## 精度口径：Godot 的 Vector2/Vector3 分量为 float32，凡经向量中转的比较统一 eps=1e-4
##（远小于任何有意义的几何量，如半格 0.5）；纯标量路径可用更小 eps。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")

const SQRT3 := 1.7320508075688772      # √3（与实现各自独立写死，防公式同源漂移）
const SQRT3_HALF := 0.8660254037844386  # √3/2（内切圆半径系数）
const EPS := 1e-4                       # Vector(float32) 中转统一容差

# ================= 邻居 =================

func test_direction_table_fixed() -> void:
	# 方向编号 0~5 写死（04 微决策）：逐项与约定表核对，防静默改约定
	expect_eq(Hex.DIRS[0], Vector2i(1, 0), "方向0=东")
	expect_eq(Hex.DIRS[1], Vector2i(1, -1), "方向1=东北")
	expect_eq(Hex.DIRS[2], Vector2i(0, -1), "方向2=西北")
	expect_eq(Hex.DIRS[3], Vector2i(-1, 0), "方向3=西")
	expect_eq(Hex.DIRS[4], Vector2i(-1, 1), "方向4=西南")
	expect_eq(Hex.DIRS[5], Vector2i(0, 1), "方向5=东南")
	expect_eq(Hex.DIRS.size(), 6, "恰好 6 方向")

func test_dirs_distinct_and_sum_zero() -> void:
	var seen := {}
	var sum := Vector2i.ZERO
	for d in Hex.DIRS:
		expect(not seen.has(d), "方向向量 %s 重复" % d)
		seen[d] = true
		sum += d
	expect_eq(sum, Vector2i.ZERO, "六方向向量总和应为零")

func test_neighbor_reverse_symmetry() -> void:
	# 细化新增：邻居反向对称——任意方向走一步再走反向必回原格（含负坐标样本）
	var cells := [Vector2i(0, 0), Vector2i(5, -3), Vector2i(-7, 2), Vector2i(20, 20), Vector2i(-13, -9)]
	for c in cells:
		for i in 6:
			var n := Hex.neighbor(c, i)
			expect_eq(Hex.neighbor(n, Hex.opposite_dir(i)), c,
				"(%d,%d) 方向%d 反向不回原格" % [c.x, c.y, i])
			expect_eq(Hex.opposite_dir(Hex.opposite_dir(i)), i, "反向的反向应还原")
			expect_eq(Hex.dir_between(c, n), i, "dir_between 与 neighbor 不一致")
			expect_eq(Hex.dir_between(n, c), Hex.opposite_dir(i), "dir_between 反向不对称")

func test_neighbors_all_adjacent() -> void:
	for c in [Vector2i(0, 0), Vector2i(-4, 6), Vector2i(11, -2)]:
		var ns := Hex.neighbors(c)
		expect_eq(ns.size(), 6, "邻居数应恒为 6")
		for n in ns:
			expect_eq(Hex.distance(c, n), 1, "邻居距离应为 1")
			expect_eq(Hex.dir_between(c, n) >= 0, true, "邻居必有方向编号")

# ================= 边界判定 / 矩形外形 =================

func test_offset_axial_roundtrip() -> void:
	# 含负坐标与 odd-r 奇偶行偏移（负数行同样成立）
	for r in range(-10, 11):
		for q in range(-10, 11):
			var cell := Vector2i(q, r)
			expect_eq(Hex.axial_of(Hex.offset_of(cell)), cell,
				"axial→offset→axial 往返失败 (%d,%d)" % [q, r])

func test_offset_odd_r_semantics() -> void:
	# odd-r：奇数行（含负奇数行）整体向 +x 偏半格——体现在世界 x，而非 col 数值
	expect_eq(Hex.offset_of(Vector2i(0, 0)), Vector2i(0, 0), "row0: col=q")
	expect_eq(Hex.offset_of(Vector2i(0, 1)), Vector2i(0, 1), "row1: col=q（右移体现在世界 x）")
	expect_eq(Hex.offset_of(Vector2i(0, -1)), Vector2i(-1, -1), "row−1: col=q−1（负奇数行同样右偏）")
	expect_eq(Hex.offset_of(Vector2i(0, 2)), Vector2i(1, 2), "row2: col=q+r/2（偶行对齐）")
	# 世界层验证：同 col 相邻行格心 x 差 = √3/2（奇行右偏半格）、z 差 = 1.5
	var w0 := Hex.axial_to_world(Hex.axial_of(Vector2i(0, 0)), 1.0)
	var w1 := Hex.axial_to_world(Hex.axial_of(Vector2i(0, 1)), 1.0)
	expect_almost_eq(w1.x - w0.x, SQRT3_HALF, EPS, "同列相邻行格心 x 差应 = √3/2")
	expect_almost_eq(w1.z - w0.z, 1.5, EPS, "同列相邻行格心 z 差应 = 1.5")

func test_rect_map_shape_unique_full() -> void:
	# 外形 = row/column 矩形：w×h 的 offset 格转 axial 后互异、总数 = w×h（无折叠无缺格）
	var w := 60
	var h := 40
	var seen := {}
	for row in h:
		for col in w:
			var cell := Hex.axial_of(Vector2i(col, row))
			expect(not seen.has(cell), "矩形格折叠重复 col=%d row=%d" % [col, row])
			seen[cell] = true
	expect_eq(seen.size(), w * h, "60×40 矩形格总数应 = 2400")

func test_in_bounds_rect() -> void:
	# 邻居/边界判定：界内全真、矩形外圈全假
	var w := 4
	var h := 3
	for row in h:
		for col in w:
			expect(Hex.in_bounds(Hex.axial_of(Vector2i(col, row)), w, h),
				"界内被判外 col=%d row=%d" % [col, row])
	for row in range(-1, h + 1):
		for col in range(-1, w + 1):
			var inside: bool = row >= 0 and row < h and col >= 0 and col < w
			if not inside:
				expect(not Hex.in_bounds(Hex.axial_of(Vector2i(col, row)), w, h),
					"界外被判内 col=%d row=%d" % [col, row])

func test_in_bounds_direct_axial() -> void:
	expect(Hex.in_bounds(Vector2i(0, 0), 4, 3), "(0,0) 界内")
	expect(not Hex.in_bounds(Vector2i(0, -1), 4, 3), "axial(0,−1)→offset(−1,−1) 应界外")
	expect(not Hex.in_bounds(Vector2i(-1, 0), 4, 3), "axial(−1,0)→offset(−1,0) 应界外")
	expect(Hex.in_bounds(Vector2i(0, 0), 1, 1), "1×1 图只有原点格")
	for i in 6:
		expect(not Hex.in_bounds(Hex.neighbor(Vector2i(0, 0), i), 1, 1), "1×1 图全邻居界外")

# ================= 距离 =================

func test_distance_known_values() -> void:
	expect_eq(Hex.distance(Vector2i(0, 0), Vector2i(0, 0)), 0, "自距 0")
	expect_eq(Hex.distance(Vector2i(0, 0), Vector2i(1, 0)), 1, "东邻 1")
	expect_eq(Hex.distance(Vector2i(0, 0), Vector2i(1, -1)), 1, "东北邻 1")
	expect_eq(Hex.distance(Vector2i(0, 0), Vector2i(2, -2)), 2, "沿东北两格 = 2")
	expect_eq(Hex.distance(Vector2i(0, 0), Vector2i(3, 1)), 4, "(0,0)-(3,1)=4")
	expect_eq(Hex.distance(Vector2i(-5, 2), Vector2i(4, -7)), 9, "负坐标距离 (9+9+0)/2=9")

func test_distance_symmetry() -> void:
	# 细化新增：距离对称 + 三角不等式（度量性质），固定种子可复现
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	for i in range(500):
		var a := Vector2i(rng.randi_range(-100, 100), rng.randi_range(-100, 100))
		var b := Vector2i(rng.randi_range(-100, 100), rng.randi_range(-100, 100))
		expect_eq(Hex.distance(a, b), Hex.distance(b, a), "距离不对称 %s %s" % [a, b])
	for i in range(200):
		var a := Vector2i(rng.randi_range(-50, 50), rng.randi_range(-50, 50))
		var b := Vector2i(rng.randi_range(-50, 50), rng.randi_range(-50, 50))
		var c := Vector2i(rng.randi_range(-50, 50), rng.randi_range(-50, 50))
		expect(Hex.distance(a, c) <= Hex.distance(a, b) + Hex.distance(b, c),
			"三角不等式破裂 %s %s %s" % [a, b, c])

func test_cube_third_axis_computed() -> void:
	# cube 第三轴 s = −q−r 现算约定
	for c in [Vector2i(0, 0), Vector2i(3, -7), Vector2i(-12, 5), Vector2i(9, 9)]:
		var cube := Hex.to_cube(c)
		expect_eq(cube.x + cube.y + cube.z, 0, "cube 三轴和应为 0（s 现算保证）")
		expect_eq(cube.z, -c.x - c.y, "s 应 = −q−r")

func test_cube_distance_matches_axial() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in range(300):
		var a := Vector2i(rng.randi_range(-50, 50), rng.randi_range(-50, 50))
		var b := Vector2i(rng.randi_range(-50, 50), rng.randi_range(-50, 50))
		expect_eq(Hex.cube_distance(Hex.to_cube(a), Hex.to_cube(b)), Hex.distance(a, b),
			"cube/axial 距离不一致 %s %s" % [a, b])

# ================= axial ↔ 世界坐标往返 =================

func test_world_mapping_known_values() -> void:
	# 公式锚点（size=1）：x = √3·(q + r/2)、z = 1.5·r —— 写死防公式漂移
	var o := Hex.axial_to_world(Vector2i(0, 0), 1.0)
	expect_almost_eq(o.x, 0.0, EPS, "原点 x")
	expect_almost_eq(o.z, 0.0, EPS, "原点 z")
	var e := Hex.axial_to_world(Vector2i(1, 0), 1.0)
	expect_almost_eq(e.x, SQRT3, EPS, "东邻格心 x = √3")
	expect_almost_eq(e.z, 0.0, EPS, "东邻格心 z = 0")
	var s := Hex.axial_to_world(Vector2i(0, 1), 1.0)
	expect_almost_eq(s.x, SQRT3_HALF, EPS, "南邻格心 x = √3/2")
	expect_almost_eq(s.z, 1.5, EPS, "南邻格心 z = 1.5")

func test_neighbor_center_spacing() -> void:
	# 六邻居格心间距恒 = √3·size（外接圆半径口径）
	for size in [1.0, 0.7, 10.0]:
		for c in [Vector2i(0, 0), Vector2i(-6, 4), Vector2i(13, -8)]:
			for i in 6:
				var a := Hex.axial_to_world(c, size)
				var b := Hex.axial_to_world(Hex.neighbor(c, i), size)
				expect_almost_eq((b - a).length(), SQRT3 * size, EPS,
					"格心间距 ≠ √3·size size=%s cell=%s dir=%d" % [str(size), c, i])

func test_axial_world_roundtrip() -> void:
	# 细化新增：axial↔世界坐标往返——格心精确还原（含负坐标，非整数 size 同验）
	for size in [1.0, 0.7, 10.0]:
		for r in range(-20, 21):
			for q in range(-20, 21):
				var cell := Vector2i(q, r)
				var back := Hex.world_to_axial(Hex.axial_to_world(cell, size), size)
				expect_eq(back, cell, "axial→world→axial 失败 size=%s (%d,%d)" % [str(size), q, r])

func test_world_axial_float_inverse() -> void:
	# 浮点层往返（未取整）：float32 分量量化下的绝对误差上界 ~ |q|·1.2e-6，eps=1e-4
	for cell in [Vector2i(0, 0), Vector2i(-8, 3), Vector2i(17, -11), Vector2i(5, 5)]:
		var f := Hex.world_to_axial_f(Hex.axial_to_world(cell, 1.0), 1.0)
		expect_almost_eq(f.x, float(cell.x), EPS, "浮点 q 往返漂移")
		expect_almost_eq(f.y, float(cell.y), EPS, "浮点 r 往返漂移")

func test_world_y_passthrough() -> void:
	# XZ 地面 + Y 高程：y 透传、不参与格子换算
	var w := Hex.axial_to_world(Vector2i(2, -3), 1.0, 5.5)
	expect_almost_eq(w.y, 5.5, EPS, "y 应原样透传")
	expect_eq(Hex.world_to_axial(w, 1.0), Vector2i(2, -3), "带 y 世界点的格子换算不应受 y 影响")

func test_world_to_axial_near_center_jitter() -> void:
	# 格心邻域小扰动（< 内切圆半径 √3/2）不改变归属
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in range(300):
		var cell := Vector2i(rng.randi_range(-12, 12), rng.randi_range(-12, 12))
		var c0 := Hex.axial_to_world(cell, 1.0)
		var jitter := Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-2.0, 9.0), rng.randf_range(-0.4, 0.4))
		expect_eq(Hex.world_to_axial(c0 + jitter, 1.0), cell,
			"格心邻域扰动错格 cell=%s" % cell)

# ================= cube rounding（Red Blob 口径） =================

func test_round_axial_exact_and_negative() -> void:
	# 负坐标：无歧义点直接命中
	expect_eq(Hex.round_axial(Vector2(-2.4, -3.6)), Vector2i(-2, -4), "负数舍入")
	expect_eq(Hex.round_axial(Vector2(-7.0, 4.0)), Vector2i(-7, 4), "精确负格")
	expect_eq(Hex.round_axial(Vector2(0.0, 0.0)), Vector2i(0, 0), "原点")
	expect_eq(Hex.world_to_axial(Hex.axial_to_world(Vector2i(-9, -12), 1.0), 1.0),
		Vector2i(-9, -12), "负格世界往返")

func test_round_axial_fixes_max_error_axis() -> void:
	# 细化新增（核心）：三轴各自 round 后必须修正误差最大轴，不许两轴各自四舍五入。
	# 反例 A：(0.4, 0.4)（s=−0.8）——两轴各自四舍五入得 (0,0)，但 q/r 误差 0.6 > s 误差 0.2，
	# 最大误差轴在 r，正确结果 (0,1)；朴素结果的 cube (0,0,0) 对应的 s=0 距 −0.8 误差 0.8，非法。
	var got := Hex.round_axial(Vector2(0.4, 0.4))
	expect_eq(got, Vector2i(0, 1), "(0.4,0.4) 朴素两轴舍入得 (0,0) 是错格，应为 (0,1)")
	expect(_axial_f_dist_to_cell(Vector2(0.4, 0.4), Vector2i(0, 1))
		< _axial_f_dist_to_cell(Vector2(0.4, 0.4), Vector2i(0, 0)),
		"修正结果应比朴素两轴舍入结果更近，否则反例不成立")
	# 反例 B：(0.5, −0.2)（s=−0.3）——两轴各自舍入得 (1,0)，其 cube (1,0,−1) 虽合法但错格：
	# dq=0.5 > ds=0.3，最大误差轴在 q，修 q → (0,0)
	var got2 := Hex.round_axial(Vector2(0.5, -0.2))
	expect_eq(got2, Vector2i(0, 0), "(0.5,−0.2) 应修最大误差轴 q 得 (0,0)")
	expect(_axial_f_dist_to_cell(Vector2(0.5, -0.2), Vector2i(0, 0))
		< _axial_f_dist_to_cell(Vector2(0.5, -0.2), Vector2i(1, 0)),
		"修正结果应比朴素两轴舍入结果更近，否则反例不成立")

func test_round_axial_nearest_center_random() -> void:
	# 随机浮点轴向（含负）：rounding 结果到输入点的世界距离 = 邻域内最近格心距离
	# （用「不劣于最近 + 容差」口径，天然容忍精确平手边界的归属二义）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	for i in range(400):
		var f := Vector2(rng.randf_range(-15.0, 15.0), rng.randf_range(-15.0, 15.0))
		var cell := Hex.round_axial(f)
		var d_round := _axial_f_dist_to_cell(f, cell)
		var d_min := _min_center_dist(f)
		expect(d_round <= d_min + EPS,
			"rounding 非最近格心 f=%s got=%s d=%s min=%s" % [f, cell, str(d_round), str(d_min)])

func test_round_axial_deterministic() -> void:
	# 边界半点（如 (−0.5,0.5) 两格等距平手）：结果须确定（两次调用一致）且为输入点附近合法格
	for f in [Vector2(-0.5, 0.5), Vector2(1.5, -0.5), Vector2(0.5, 1.5)]:
		var a := Hex.round_axial(f)
		var b := Hex.round_axial(f)
		expect_eq(a, b, "同一输入两次 rounding 不一致 f=%s" % f)
		expect(Hex.distance(Vector2i(0, 0), a) <= 2, "平手点结果应为输入点附近合法格 f=%s" % f)

# ================= 顶点与朝向 =================

func test_vertex_geometry() -> void:
	# 顶点距格心 = size（外接圆半径）；相邻顶点距 = size（正六边形边长 = 外接圆半径）
	var size := 1.3
	var c := Vector2i(3, -4)
	var center := Hex.axial_to_world(c, size)
	var cz := Vector2(center.x, center.z)
	var verts: Array[Vector2] = []
	for i in 6:
		var v := Hex.vertex_xz(c, i, size)
		verts.append(v)
		expect_almost_eq((v - cz).length(), size, EPS, "顶点 %d 距格心应 = size" % i)
	for i in 6:
		expect_almost_eq(verts[i].distance_to(verts[(i + 1) % 6]), size, EPS,
			"相邻顶点 %d-%d 距应 = size" % [i, (i + 1) % 6])

func test_vertex_known_positions() -> void:
	# pointy-top 锚点（size=1、原点格）：顶点角 = 30°−60°·i
	# 顶点 0=东偏南30°、顶点 2=正北（−z）、顶点 5=正南（+z）→ pointy 沿 z 轴
	expect_almost_eq(Hex.vertex_xz(Vector2i(0, 0), 0, 1.0).x, SQRT3_HALF, EPS, "顶点0 x=cos(30°)")
	expect_almost_eq(Hex.vertex_xz(Vector2i(0, 0), 0, 1.0).y, 0.5, EPS, "顶点0 z=sin(30°)")
	expect_almost_eq(Hex.vertex_xz(Vector2i(0, 0), 2, 1.0).x, 0.0, EPS, "顶点2 x=0")
	expect_almost_eq(Hex.vertex_xz(Vector2i(0, 0), 2, 1.0).y, -1.0, EPS, "顶点2 z=−1（正北 −z 有顶点 → pointy 沿 z）")
	expect_almost_eq(Hex.vertex_xz(Vector2i(0, 0), 5, 1.0).y, 1.0, EPS, "顶点5 z=+1（正南亦有顶点）")
	var v3 := Hex.cell_vertex(Vector2i(0, 0), 2, 1.0, 7.0)
	expect_almost_eq(v3.y, 7.0, EPS, "cell_vertex 的 y 透传")

func test_vertex_and_direction_alignment() -> void:
	# 边 i（顶点 i 与 i+1 的连线）中点方向 = 方向 i 的单位向量；边距 = 内切圆半径 √3/2·size
	# —— 这是 T4「两格边带几何」与「共享边归属」的拓扑基
	var c := Vector2i(-2, 5)
	var center := Hex.axial_to_world(c, 1.0)
	var cz := Vector2(center.x, center.z)
	for i in 6:
		var a := Hex.vertex_xz(c, i, 1.0)
		var b := Hex.vertex_xz(c, (i + 1) % 6, 1.0)
		var mid := (a + b) * 0.5
		var normal := (mid - cz).normalized()
		var dirv := Hex.dir_unit_world(i)
		expect_almost_eq(normal.x, dirv.x, EPS, "边%d 法向 x 与方向%d 不一致" % [i, i])
		expect_almost_eq(normal.y, dirv.z, EPS, "边%d 法向 z 与方向%d 不一致" % [i, i])
		expect_almost_eq((mid - cz).length(), SQRT3_HALF, EPS, "边%d 中点距格心 = √3/2·size" % i)
		# 共享边：对面格（方向 i 的邻格）的 6 顶点中必存在与本边两顶点重合者
		# （两侧格各自独立计算、误差 < eps → T4 接缝顶点从同一公式取得、不漂移）
		var n := Hex.neighbor(c, i)
		var best_a := INF
		var best_b := INF
		for k in 6:
			var nv := Hex.vertex_xz(n, k, 1.0)
			best_a = min(best_a, nv.distance_to(a))
			best_b = min(best_b, nv.distance_to(b))
		expect_almost_eq(best_a, 0.0, EPS, "共享边顶点 a 不在对面格顶点集合 dir=%d" % i)
		expect_almost_eq(best_b, 0.0, EPS, "共享边顶点 b 不在对面格顶点集合 dir=%d" % i)

func test_dir_unit_vectors() -> void:
	expect_almost_eq(Hex.dir_angle_rad(0), 0.0, 1e-12, "方向0=正东=0rad")
	var e := Hex.dir_unit_world(0)
	expect_almost_eq(e.x, 1.0, 1e-12, "东单位 x")
	expect_almost_eq(e.z, 0.0, 1e-12, "东单位 z")
	var ne := Hex.dir_unit_world(1)
	expect_almost_eq(ne.x, 0.5, EPS, "东北单位 x=cos(60°)")
	expect_almost_eq(ne.z, -SQRT3_HALF, EPS, "东北单位 z=−sin(60°)")
	for i in 6:
		expect_almost_eq(Hex.dir_unit_world(i).length(), 1.0, EPS, "方向%d 单位向量模长" % i)

func test_dir_between_non_neighbor() -> void:
	expect_eq(Hex.dir_between(Vector2i(0, 0), Vector2i(2, 0)), -1, "隔一格应 −1")
	expect_eq(Hex.dir_between(Vector2i(0, 0), Vector2i(0, 0)), -1, "自身应 −1")
	expect_eq(Hex.dir_between(Vector2i(1, 1), Vector2i(0, 0)), -1, "(1,1) 与原点距离 2，非邻居")

# ---- 辅助：浮点轴向 ↔ 最近格心（暴力基准，与实现独立成式） ----

func _axial_f_to_world(f: Vector2) -> Vector2:
	return Vector2(SQRT3 * (f.x + f.y * 0.5), 1.5 * f.y)

func _cell_to_world_xz(c: Vector2i) -> Vector2:
	return Vector2(SQRT3 * (float(c.x) + float(c.y) * 0.5), 1.5 * float(c.y))

func _axial_f_dist_to_cell(f: Vector2, c: Vector2i) -> float:
	return _axial_f_to_world(f).distance_to(_cell_to_world_xz(c))

func _min_center_dist(f: Vector2) -> float:
	var wf := _axial_f_to_world(f)
	var best := INF
	for r in range(int(floor(f.y)) - 2, int(ceil(f.y)) + 3):
		for q in range(int(floor(f.x)) - 2, int(ceil(f.x)) + 3):
			var d := wf.distance_to(_cell_to_world_xz(Vector2i(q, r)))
			if d < best:
				best = d
	return best
