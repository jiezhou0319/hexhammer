## test_hex_camera.gd — M1a-T6 策略相机单测（headless；被测对象 = addons/hexhammer/
##   hex_camera.gd 纯逻辑层——「删 scripts/ui/** 后 tests 全绿」口径下不感知 rig 节点）
## 逐条覆盖 04 任务卡 M1a-T6「验收 + 细化新增」的可自动化部分：
##   - 最大/最小缩放极值：zoom_in/zoom_out 越界钳档、距离取档位表端值、set_zoom_index
##     越界钳制、空/单档表回退与恒定；
##   - 四角+中心焦点边界（边界语义拍板 = 钳「相机焦点」，见 hex_camera.gd 头注约定 1）：
##     NW/NE/SW/SE 四角外推 → 钳回包围盒对应角、角落格心原位保留、任意缩放档位下
##     四角焦点可达（「全图可达」的焦点口径）；图心原位保留 + 随机远点钳后必在域内；
##   - 相机辅助的 axial↔世界映射与 T1 数学一致性：cell_focus_xz/focus_to_cell 与
##     HexMath.axial_to_world/world_to_axial 逐位对表、全图往返、y（高程）不参与；
##   - 固定俯角不变量（「不抄参考工程随缩放插值俯角」的回归锚）：每档位 × 多偏航
##     的 offset 俯角恒等于 pitch、模长 = 档位距离；yaw=0 相机在焦点南侧；
##   - 拖拽固定参考平面求交：直下/斜向/非归一化方向命中、平行/背向/平面下方 → null；
##   - 地图钳制域：闭式 oracle（格心极值 ± 顶点偏移：x ±√3/2·size、z ±size）对表
##     vertex_xz 展开实现；padding 外扩；空图退化不崩。
## 「缩放档位/边界手感顺手」「全图可达不出界（实机操作）」为主创实操确认项，不在本文件。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Cam := preload("res://addons/hexhammer/hex_camera.gd")

const SIZE := 1.0
const EPS := 1e-6
## 俯角重建容差：offset 经 Vector3（引擎 real_t = float32）存储 + atan2 双参重建，
## 实测最大偏差 ~3.4e-6°（见 2026-10-09 首跑），窗口放宽 >1 个数量级。
const PITCH_EPS_DEG := 1e-4
## 钳制域闭式 oracle 容差：实现路径顶点存 Vector2（float32），oracle 为纯 double
## 闭式；实测最大差 ~4.9e-6（60×40 东界，|x|≈104 × float32 相对误差 1.2e-7 量级；
## z 向格心为 1.5 的倍数可精确表示故无差），窗口放宽 >1 个数量级。
const BOUNDS_EPS := 1e-4
const SQRT3_2 := sqrt(3.0) / 2.0  # pointy-top 顶点 x 偏移峰值（闭式 oracle 用）

# ================= 最大/最小缩放极值 =================

func test_zoom_extremes_clamped() -> void:
	var c := Cam.new(Cam.DEFAULT_ZOOM_DISTANCES, Cam.UNBOUNDED, Vector2.ZERO, 2)
	expect_eq(c.zoom_index, 2, "初始档 = 构造给定")
	for i in 10:
		c.zoom_in()
	expect_eq(c.zoom_index, 0, "连续拉近越界 → 钳在最近档")
	expect_almost_eq(c.distance(), float(Cam.DEFAULT_ZOOM_DISTANCES[0]), EPS,
		"最近档距离 = 档位表首值（最小极值）")
	var min_d := c.distance()
	c.zoom_in()
	expect_eq(c.distance(), min_d, "最近档再拉近不动")
	for i in 10:
		c.zoom_out()
	var last: int = Cam.DEFAULT_ZOOM_DISTANCES.size() - 1
	expect_eq(c.zoom_index, last, "连续拉远越界 → 钳在最远档")
	expect_almost_eq(c.distance(), float(Cam.DEFAULT_ZOOM_DISTANCES[last]), EPS,
		"最远档距离 = 档位表末值（最大极值）")
	var max_d := c.distance()
	c.zoom_out()
	expect_eq(c.distance(), max_d, "最远档再拉远不动")

func test_set_zoom_index_and_table_fallback() -> void:
	var c := Cam.new([], Cam.UNBOUNDED)  # 空档位表 → 回退默认表
	expect_eq(c.zoom_distances.size(), Cam.DEFAULT_ZOOM_DISTANCES.size(), "空档位表回退默认表")
	c.set_zoom_index(-7)
	expect_eq(c.zoom_index, 0, "设负档 → 钳 0")
	c.set_zoom_index(99)
	expect_eq(c.zoom_index, c.zoom_distances.size() - 1, "设超档 → 钳末档")
	var single := Cam.new([30.0], Cam.UNBOUNDED)
	expect_eq(single.zoom_in(), 0, "单档表拉近恒 0")
	expect_eq(single.zoom_out(), 0, "单档表拉远恒 0")
	expect_almost_eq(single.distance(), 30.0, EPS, "单档表距离恒定")

# ================= 四角 + 中心焦点边界（边界语义 = 钳「相机焦点」）=================

func _new_cam(w := 12, h := 9) -> Cam:
	var m := MapDataClass.new(w, h)
	var bounds := Cam.map_focus_bounds(m, SIZE)
	return Cam.new(Cam.DEFAULT_ZOOM_DISTANCES, bounds, bounds.get_center())

func _bounds_of(w := 12, h := 9) -> Rect2:
	return Cam.map_focus_bounds(MapDataClass.new(w, h), SIZE)

## 角落外推通用：角落格心 + 外向大位移 → 钳回包围盒对应角；角格心原位保留；
## 最远档位下角焦点仍可达（「全图可达」的焦点口径——钳制不因缩放档位收紧）。
func _check_corner(col: int, row: int, outward: Vector2, label: String) -> void:
	var m := MapDataClass.new(12, 9)
	var bounds := Cam.map_focus_bounds(m, SIZE)
	var c := Cam.new(Cam.DEFAULT_ZOOM_DISTANCES, bounds, bounds.get_center())
	c.set_zoom_index(99)  # 最远档：钳焦点语义下四角仍须可达
	var corner := Cam.cell_focus_xz(Hex.axial_of(Vector2i(col, row)), SIZE)
	expect_eq(c.set_focus_world(corner), corner, "%s：角格心在域内 → 原位保留" % label)
	var clamped := c.set_focus_world(corner + outward)
	expect_almost_eq(clamped.x, clampf(corner.x + outward.x,
		bounds.position.x, bounds.position.x + bounds.size.x), EPS,
		"%s：x 钳回域界" % label)
	expect_almost_eq(clamped.y, clampf(corner.y + outward.y,
		bounds.position.y, bounds.position.y + bounds.size.y), EPS,
		"%s：z 钳回域界" % label)
	expect(_in_bounds_inclusive(c.focus, bounds), "%s：钳后焦点在域内" % label)

func test_focus_clamp_nw_corner() -> void:
	_check_corner(0, 0, Vector2(-1000.0, -1000.0), "NW 角")
	# oracle：双向外推 → 恰为包围盒 min 角（独立于 clamp 实现给出）
	var c := _new_cam()
	var b := _bounds_of()
	var got := c.set_focus_world(Vector2(-5000.0, -5000.0))
	expect_almost_eq(got.distance_to(b.position), 0.0, EPS, "NW 双向外推 → 域 min 角")

func test_focus_clamp_ne_corner() -> void:
	_check_corner(11, 0, Vector2(1000.0, -1000.0), "NE 角")
	var c := _new_cam()
	var b := _bounds_of()
	var got := c.set_focus_world(Vector2(5000.0, -5000.0))
	expect_almost_eq(got.distance_to(Vector2(b.position.x + b.size.x, b.position.y)), 0.0, EPS,
		"NE 双向外推 → 域东北角")

func test_focus_clamp_sw_corner() -> void:
	_check_corner(0, 8, Vector2(-1000.0, 1000.0), "SW 角")
	var c := _new_cam()
	var b := _bounds_of()
	var got := c.set_focus_world(Vector2(-5000.0, 5000.0))
	expect_almost_eq(got.distance_to(Vector2(b.position.x, b.position.y + b.size.y)), 0.0, EPS,
		"SW 双向外推 → 域西南角")

func test_focus_clamp_se_corner() -> void:
	_check_corner(11, 8, Vector2(1000.0, 1000.0), "SE 角")
	var c := _new_cam()
	var b := _bounds_of()
	var got := c.set_focus_world(Vector2(5000.0, 5000.0))
	expect_almost_eq(got.distance_to(Vector2(b.position.x + b.size.x, b.position.y + b.size.y)),
		0.0, EPS, "SE 双向外推 → 域 max 角")

func test_focus_clamp_center() -> void:
	var b := _bounds_of()
	var c := _new_cam()
	var ctr := b.get_center()
	expect_eq(c.set_focus_world(ctr), ctr, "图心焦点原位保留")
	var got := c.set_focus_world(ctr + Vector2(0.0, -1000.0))  # 只向北推
	expect_almost_eq(got.x, ctr.x, EPS, "只推北：x 不动")
	expect_almost_eq(got.y, b.position.y, EPS, "只推北：钳回北界")
	# 性质测试：随机远点钳后必在域内（含端点）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	for i in 200:
		var p := ctr + Vector2(rng.randf_range(-5000.0, 5000.0), rng.randf_range(-5000.0, 5000.0))
		var q := c.set_focus_world(p)
		if not _in_bounds_inclusive(q, b):
			fail("随机远点钳后出域：%s → %s（域 %s）" % [str(p), str(q), str(b)])
			return
	expect(true, "200 随机远点钳后均在域内")

# ================= axial↔世界映射与 T1 数学一致性 =================

func test_axial_world_mapping_matches_hex_math() -> void:
	for s in [1.0, 0.7]:
		var size: float = s
		var m := MapDataClass.new(9, 7)
		for cell in m.cells():
			var w := Hex.axial_to_world(cell, size)
			var f := Cam.cell_focus_xz(cell, size)
			expect_almost_eq(f.x, w.x, EPS, "cell_focus_xz.x = axial_to_world.x（%s）" % str(cell))
			expect_almost_eq(f.y, w.z, EPS, "cell_focus_xz.y = axial_to_world.z（%s）" % str(cell))
			expect_eq(Cam.focus_to_cell(f, size), cell,
				"焦点辅助往返：cell→XZ→cell（%s）" % str(cell))
			expect_eq(Cam.focus_to_cell(f, size),
				Hex.world_to_axial(Vector3(f.x, 0.0, f.y), size),
				"focus_to_cell 与 T1 world_to_axial 同值（%s）" % str(cell))
			expect_eq(Hex.world_to_axial(Vector3(f.x, 0.0, f.y), size),
				Hex.world_to_axial(Vector3(f.x, 5.5, f.y), size),
				"y（高程）不参与格子换算——T1 口径（%s）" % str(cell))

func test_focus_on_cell_roundtrip_on_instance() -> void:
	var m := MapDataClass.new(10, 8)
	var bounds := Cam.map_focus_bounds(m, SIZE)
	var c := Cam.new([20.0, 30.0, 40.0], bounds, bounds.get_center(), 1)
	# 平移越界：大幅 pan 后焦点仍在域内（钳制语义）
	c.pan_world(Vector2(10000.0, 10000.0))
	expect(_in_bounds_inclusive(c.focus, bounds), "大幅平移后焦点仍在域内")
	# 构造焦点即钳制
	var c2 := Cam.new([20.0], bounds, Vector2(-9999.0, 9999.0))
	expect(_in_bounds_inclusive(c2.focus, bounds), "构造焦点即钳制")
	# 格心焦点往返（经 T1 rounding；角落格也在域内——外沿顶点包络保证）
	for cr in [Vector2i(0, 0), Vector2i(9, 7), Vector2i(4, 3)]:
		var cell := Hex.axial_of(cr)
		c.focus_on_cell(cell)
		expect_eq(c.focus_cell(), cell, "focus_on_cell/focus_cell 往返（%s）" % str(cell))
		expect(_in_bounds_inclusive(c.focus, bounds), "格心焦点在域内（%s）" % str(cell))

# ================= 固定俯角不变量（不抄「随缩放插值俯角」的回归锚）=================

func test_fixed_pitch_invariant_across_zoom() -> void:
	for dv in Cam.DEFAULT_ZOOM_DISTANCES:
		var d: float = dv
		for yv in [0.0, 90.0, -35.0]:
			var yaw: float = yv
			var off := Cam.camera_offset(d, 55.0, yaw)
			expect_almost_eq(off.length(), d, EPS,
				"offset 模长 = 档位距离（d=%s yaw=%s）" % [str(d), str(yaw)])
			var horiz := Vector2(off.x, off.z).length()
			expect_almost_eq(rad_to_deg(atan2(off.y, horiz)), 55.0, PITCH_EPS_DEG,
				"俯角恒 55°——与缩放档位无关（d=%s yaw=%s）" % [str(d), str(yaw)])
	# yaw=0：相机在焦点南侧（+z）、高度 = d·sin55、x 对齐焦点
	var pos := Cam.camera_position(Vector2(10.0, 20.0), 0.0, 40.0, 55.0, 0.0)
	expect_almost_eq(pos.x, 10.0, EPS, "yaw0：相机 x 对齐焦点")
	expect_almost_eq(pos.z, 20.0 + 40.0 * cos(deg_to_rad(55.0)), EPS,
		"yaw0：相机在南（+z 偏 cos55·d）")
	expect_almost_eq(pos.y, 40.0 * sin(deg_to_rad(55.0)), EPS, "相机高度 = d·sin55")

# ================= 拖拽固定参考平面求交 =================

func test_drag_plane_intersection() -> void:
	# 直下：命中保持 x/z
	var hit: Variant = Cam.drag_plane_xz(Vector3(3.0, 10.0, 4.0), Vector3(0.0, -1.0, 0.0), 0.0)
	expect(hit != null and (hit as Vector2).distance_to(Vector2(3.0, 4.0)) < EPS,
		"直下射线命中 (3,4)")
	# 55° 俯角口径斜射线：从 (0,8,5.6) 指向原点 → 命中平面原点（拖拽锚点同款几何）
	var dir := (-Vector3(0.0, 8.0, 5.6)).normalized()
	hit = Cam.drag_plane_xz(Vector3(0.0, 8.0, 5.6), dir, 0.0)
	expect(hit != null and (hit as Vector2).distance_to(Vector2.ZERO) < 1e-5,
		"55° 斜射线命中参考平面原点")
	# 抬高参考平面：y=3，从 y=10 直下 → x/z 保持
	hit = Cam.drag_plane_xz(Vector3(2.0, 10.0, 3.0), Vector3(0.0, -1.0, 0.0), 3.0)
	expect(hit != null and (hit as Vector2).distance_to(Vector2(2.0, 3.0)) < EPS,
		"y=3 参考平面命中 (2,3)")
	# 非归一化方向（t 语义对任意长度成立）：origin (0,4,0)、dir (1,−1,0.5) → (4,2)
	hit = Cam.drag_plane_xz(Vector3(0.0, 4.0, 0.0), Vector3(1.0, -1.0, 0.5), 0.0)
	expect(hit != null and absf((hit as Vector2).x - 4.0) < EPS
		and absf((hit as Vector2).y - 2.0) < EPS, "非归一化 dir 命中 (4,2)")
	# 无交三态：平行 / 背向（向上）/ 起点在平面下方再向下 → null
	expect(Cam.drag_plane_xz(Vector3(0.0, 5.0, 0.0), Vector3(1.0, 0.0, 0.0), 0.0) == null,
		"水平平行 → null")
	expect(Cam.drag_plane_xz(Vector3(0.0, 5.0, 0.0), Vector3(0.0, 1.0, 0.0), 0.0) == null,
		"背向（向上）→ null")
	expect(Cam.drag_plane_xz(Vector3(0.0, -5.0, 0.0), Vector3(0.0, -1.0, 0.0), 0.0) == null,
		"平面下方再向下 → null")

# ================= 地图钳制域（闭式 oracle）=================

func test_map_focus_bounds_closed_form_oracle() -> void:
	# oracle（独立闭式，不用 vertex_xz）：pointy-top 顶点角 30°−60i
	#   → x 偏移 ∈ ±cos30°·size = ±√3/2·size、z 偏移 ∈ ±size；
	#   域界 = 全部格心极值 ± 上述偏移。
	for whv in [[12, 9], [60, 40], [1, 1]]:
		var w: int = whv[0]
		var h: int = whv[1]
		var m := MapDataClass.new(w, h)
		var b := Cam.map_focus_bounds(m, SIZE)
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		for cell in m.cells():
			var ctr := Hex.axial_to_world(cell, SIZE)
			min_x = minf(min_x, ctr.x)
			max_x = maxf(max_x, ctr.x)
			min_z = minf(min_z, ctr.z)
			max_z = maxf(max_z, ctr.z)
		expect_almost_eq(b.position.x, min_x - SQRT3_2, BOUNDS_EPS,
			"西界 = 格心最小 x − √3/2·size（%dx%d）" % [w, h])
		expect_almost_eq(b.position.x + b.size.x, max_x + SQRT3_2, BOUNDS_EPS,
			"东界 = 格心最大 x + √3/2·size（%dx%d）" % [w, h])
		expect_almost_eq(b.position.y, min_z - 1.0, BOUNDS_EPS,
			"北界 = 格心最小 z − size（%dx%d）" % [w, h])
		expect_almost_eq(b.position.y + b.size.y, max_z + 1.0, BOUNDS_EPS,
			"南界 = 格心最大 z + size（%dx%d）" % [w, h])
	# padding 四边外扩
	var b0 := Cam.map_focus_bounds(MapDataClass.new(5, 5), SIZE)
	var b2 := Cam.map_focus_bounds(MapDataClass.new(5, 5), SIZE, 2.0)
	expect_almost_eq(b2.position.x, b0.position.x - 2.0, EPS, "padding 外扩西界")
	expect_almost_eq(b2.position.y, b0.position.y - 2.0, EPS, "padding 外扩北界")
	expect_almost_eq(b2.position.x + b2.size.x, b0.position.x + b0.size.x + 2.0, EPS,
		"padding 外扩东界")
	expect_almost_eq(b2.position.y + b2.size.y, b0.position.y + b0.size.y + 2.0, EPS,
		"padding 外扩南界")
	# 空图：退化域不崩（调用方 setup 侧显式拒绝空图）
	expect_eq(Cam.map_focus_bounds(MapDataClass.new(0, 0), SIZE).size, Vector2.ZERO,
		"空图 → 退化域（零尺寸）")

# ---- 辅助 ----

## 域内判定（含端点——Rect2.has_point 不含 max 边，钳制语义须含端点）
func _in_bounds_inclusive(p: Vector2, r: Rect2) -> bool:
	return p.x >= r.position.x - EPS and p.x <= r.position.x + r.size.x + EPS \
		and p.y >= r.position.y - EPS and p.y <= r.position.y + r.size.y + EPS
