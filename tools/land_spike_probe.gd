## land_spike_probe.gd — LAND-S 七格测试场 spike 探针（T2-SPIKE 附卡，2026-10-11）
## 目的（执行方案 §3 LAND-S）：在全量阶地/真崖几何（LAND-02）动工前，用**实验性**
## 几何低成本验证「连接带宽 ≈0.35·size 下阶地可读性」，产出步数档（5 vs 3）与
## cliff 纵横比档（竖直夸张 ×1.0/×1.5）的对比截图供主创目检拍板。
## 定位与边界：
##   - **spike 件不进 addons/hexhammer 合同**——阶地/真崖 emitter 为本文件内一次性
##     实验实现（顶点派生复用 HexMath 全局参数，几何公式 = 执行方案 LAND-02 落字版：
##     terrace 水平 a.lerp(b, s/S)、竖直 v_step = 1/ceil(steps/2)；真崖 = 共享崖线 XZ
##     上同 XZ 墙顶/墙底 + 高低平台裙边——修订记录三之 3 口径）；
##   - 只求可读性目检：不做角落补面（角点留针孔——混合角目检口径 = 三边带汇聚，
##     角几何补面属 LAND-01/LAND-02）、不做流形/拾取/碰撞合同；
##   - 角落矩阵完备性属 LAND-01 矩阵图，不在本 spike。
## 产物：docs/evidence/m1a/land_spike/ 六张截图 + summary txt——
##   overview_steps5/3（七格俯视：中心 e0 + 六邻 e=[1,2,3,2,1,0]，Δ 全档 0/1/2/3）
##   section_d2_steps5/3（两格 Δ2 断面 = 阶地每级步数直读）
##   section_d3_ar100/150（两格 Δ3 断面 = cliff_threshold=3 真垂直崖 + 高低裙边，
##   纵横比候选档 = 竖直夸张系数 ×1.0/×1.5——「cliff 纵横比取向」拍板对比素材）
## 固定图布局 = tools/land_spike_fixtures.gd（LAND-S 测试锚：make_fixed_maps 特征
## 常量区先例的固定小图 fixture，可复用为 LAND-01 矩阵图子集/子域）。
## 用法（非 headless 真渲染；探针自 quit(0/1)）：
##   "E:/Godot/Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tools/land_spike_probe.gd
## 修订（2026-10-11 收尾批）：① 断面相机由「沿边切向正对」改为低位斜视——初版视线恰沿
##   边带长轴，每级台阶被压成 ~15px 细线、零 d-延展的真垂直崖完全侧视退化不可见（像素
##   列审计实证：图上仅剩两块互不相连的平台）；② 新增帧结构 CHECK（空帧 + 断面列跨度
##   两道闸，拦的正是上述失败模式——防 exit 0 但证据废）。
## 修订（2026-10-11 评审修复批）：③ cliff 纵横比候选档补齐——设计行「步数候选档
##   （5/3）与 cliff 纵横比档并列可切换」原只落了单一 Δ3 墙观感，纵横比取向拍板缺
##   对比素材；④ 固定图布局抽为 land_spike_fixtures.gd 独立件（原探针内字典直建，
##   复用性仅停留在布局概念，未按测试锚落 fixture）。
extends SceneTree

const WINDOW_SIZE := Vector2i(1280, 720)
const EVIDENCE_DIR := "res://docs/evidence/m1a/land_spike"
const WATCHDOG_SEC := 60.0
## 实验几何参数（spike 档；LAND-02 落地时进 LandformProfile）
const STEPS_CANDIDATES := [5, 3]  # 每爬一级的阶地步数候选（Catlike 5 步 / 紧凑 3 步）
## cliff 纵横比候选档（执行方案 §3 LAND-S 设计行「步数候选档（5/3）与 cliff 纵横比
## 档并列可切换」+ 卡内拍板项「grimdark 垂直夸张的 cliff 纵横比取向（docs/12 §1
## 定调参考）」）：纵横比 = 崖墙高 ÷ 连接带宽——横轴 ≈0.35·size 是 T2 连接合同
## 钉死常量、真垂直崖墙面无横轴自由度（拍板：崖壁暂保留真垂直），故唯一可调档 =
## 竖直夸张系数（每级高程的墙高倍率）：写实 ×1.0 / 垂直夸张 ×1.5 两档并列出图。
const CLIFF_AR_CANDIDATES := [1.0, 1.5]
const CLIFF_THRESHOLD := 3        # Δ≥3 走真垂直崖（执行方案默认档）
const ELEV_STEP := 1.0            # 竖直夸张基准（纵横比候选档按倍率缩放本值）
const SOLID := 0.8
## 断面取景参数（spike 档，非合同）：偏航自走廊起 38°/俯角 20°——沿边切向正对（偏航 90°）
## 时边带长轴沿视线，台阶压成细线、真垂直崖侧视退化不可见（2026-10-11 首跑废弃）；
## 走廊正对（偏航 0°）则 riser 满幅但 tread 被压没、两平台正对重叠。38°/20° 为兼顾
## riser 正对分量与 tread 俯角分量的取景档，理由同上修订条。
const SECTION_YAW_DEG := 38.0
const SECTION_ELEV_DEG := 20.0
## CHECK 阈值（健全帧实测校准，2026-10-11 收尾跑：overview ≈42.8k 非背景 px、断面
## 列跨度 525-534px；阈值留足渲染抖动余量，只拦「空/黑帧」与「断面结构退化」两类
## 失败模式——初版退化 d3 实测列跨度仅 ~107px 即被 0.30 档拦下。不做美学判断，
## 拍板权在主创目检，探针只保证证据非废片）
const NON_BG_FLOOR := 12000
const SECTION_SPAN_RATIO := 0.30
## 高程→颜色（垂直可读性：低草绿→高雪白）
const ELEV_COLORS: Array = [
	Color(0.33, 0.48, 0.28), Color(0.48, 0.42, 0.30), Color(0.52, 0.52, 0.56),
	Color(0.85, 0.86, 0.90), Color(0.95, 0.96, 0.98), Color(1.0, 1.0, 1.0)]

func _init() -> void:
	print("[LAND-S] init（spike 探针；实验几何，非合同实现）")
	_boot.call_deferred()

func _boot() -> void:
	root.size = WINDOW_SIZE
	root.move_to_center()
	if root.world_3d == null:
		root.world_3d = World3D.new()
	var c := Spike.new()
	c.name = "LandSpike"
	root.add_child(c)

class Spike extends Node:
	const Hex := preload("res://addons/hexhammer/hex_math.gd")
	const Fixtures := preload("res://tools/land_spike_fixtures.gd")

	var _cam: Camera3D = null

	## Catlike 竖直档（一组 steps 步内的归一化爬升剖面；j=0..steps，端点恰 0→1）
	static func _vert_profile(j: int, steps: int) -> float:
		if j <= 0:
			return 0.0
		var v_step := 1.0 / ceilf(float(steps) / 2.0)
		return float((j + 1) / 2) * v_step  # int 除法向零取整 = 竖直仅奇数步动

	func _ready() -> void:
		_arm_watchdog()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.16, 0.17, 0.2)
		var we := WorldEnvironment.new()
		we.environment = env
		add_child(we)
		_cam = Camera3D.new()
		_cam.fov = 50.0
		_cam.near = 0.1
		_cam.far = 200.0
		_cam.current = true
		add_child(_cam)

		# ---- 固定图（land_spike_fixtures.gd 特征常量 fixture——LAND-S 测试锚
		# make_fixed_maps 先例；spike 仍不经 MapData/builder）----
		var overview_cells := Fixtures.overview_cells()
		var section_d2 := Fixtures.section_cells(Fixtures.SECTION_TERRACE_DELTA)
		var section_d3 := Fixtures.section_cells(Fixtures.SECTION_CLIFF_DELTA)

		# ---- 六张出图：步数族 ×4（overview+section_d2 各档）+ 纵横比族 ×2，
		# 两族候选并列（各变量一次只动一个自由度，目检归因不混淆）----
		var shots := []  # {name, cells, steps, elev_step, view}
		for st in STEPS_CANDIDATES:
			shots.append({"name": "overview_steps%d" % st, "cells": overview_cells,
				"steps": st, "elev_step": ELEV_STEP, "view": "top"})
			shots.append({"name": "section_d2_steps%d" % st, "cells": section_d2,
				"steps": st, "elev_step": ELEV_STEP, "view": "side"})
		for ar in CLIFF_AR_CANDIDATES:
			shots.append({"name": "section_d3_ar%d" % int(round(float(ar) * 100.0)),
				"cells": section_d3, "steps": 5,
				"elev_step": ELEV_STEP * float(ar), "view": "side"})

		var saved: Array[String] = []
		if DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path(EVIDENCE_DIR)) != OK:
			_fail("证据目录创建失败：%s" % EVIDENCE_DIR)
			return
		for shot in shots:
			_place_scene(shot)
			await _frames(8)
			var img := await _capture()
			if img == null:
				return
			var p := "%s/land_spike_%s.png" % [EVIDENCE_DIR, shot["name"]]
			if (img.save_png(p) != OK):
				_fail("截图写入失败：%s" % p)
				return
			saved.append(p)
			# 先留档再 CHECK：失败帧也落在盘上，主创可复核废片长什么样
			if not _check_shot(str(shot["name"]), img):
				return
		_write_summary(saved)
		print("LAND-S PROBE OK — %d 张对比图已留档（步数默认值与 cliff 纵横比取向待主创目检拍板）" % saved.size())
		get_tree().quit(0)

	# ---------------- 实验几何（一次性 spike 实现，不进 addons 合同）----------------

	func _place_scene(shot: Dictionary) -> void:
		for ch in get_children():
			if ch is MeshInstance3D:
				ch.queue_free()
		var mesh := _build_mesh(shot["cells"], int(shot["steps"]), float(shot["elev_step"]))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
		var bounds := _cells_bounds(shot["cells"])
		var c := bounds.get_center()
		if shot["view"] == "top":
			_cam.fov = 50.0
			_cam.global_transform = Transform3D(
				Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)),
				Vector3(c.x, 16.0, c.y))
		else:
			# 断面斜视（低侧仰拍）：相机在低格延长线上、绕走廊偏 SECTION_YAW_DEG、俯角
			# SECTION_ELEV_DEG——riser 正对分量与 tread 俯角分量同帧可见，台阶剖面直读，
			# 真垂直崖墙面入画。初版沿边切向正对（视线 = 边带长轴）时台阶压成细线、
			# 真崖完全退化不可见，见文件头修订条。
			var cells: Dictionary = shot["cells"]
			var keys := cells.keys()
			var a := Hex.axial_to_world(keys[0], 1.0)
			var b := Hex.axial_to_world(keys[1], 1.0)
			var mid := (a + b) * 0.5
			var d := (b - a).normalized()
			var n := Vector3(-d.z, 0.0, d.x)
			var maxh := maxf(float(cells[keys[0]]), float(cells[keys[1]])) * float(shot["elev_step"])
			# 低侧方向（keys 插入序不承载语义，按两格高程现判；d3 断面即崖下仰拍）
			var d_lo := -d if float(cells[keys[0]]) < float(cells[keys[1]]) else d
			var yaw := deg_to_rad(SECTION_YAW_DEG)
			var dir := (d_lo * cos(yaw) + n * sin(yaw)).normalized()
			var target := mid + Vector3(0.0, maxh * 0.5, 0.0)
			# 距离按高差自适应（fov30 可见高度 ≈ 0.536×距离；高差大要退远否则拍丢）
			var dist := maxf(4.2, (maxh + 1.2) * 2.2)
			var elev := deg_to_rad(SECTION_ELEV_DEG)
			_cam.global_position = target + (dir * cos(elev) + Vector3.UP * sin(elev)) * dist
			_cam.fov = 30.0
			_cam.look_at(target, Vector3.UP)

	## spike mesh：格顶面扇 + 边带（平/阶地/真崖三种模式）。角落不补面（针孔 = spike
	## 已知取舍，混合角目检口径 = 三边带汇聚）；材质 UNSHADED + 顶点色（纯几何可读性，
	## 无光照噪声）。elev_step = 本景竖直夸张系数（cliff 纵横比候选档按倍率缩放）。
	func _build_mesh(cells: Dictionary, steps: int, elev_step: float) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # spike：绕序容错优先
		# 格顶面（内六边形扇）
		for cell in cells:
			var e: int = cells[cell]
			var col: Color = ELEV_COLORS[clampi(e, 0, ELEV_COLORS.size() - 1)]
			var c3 := Hex.axial_to_world(cell, 1.0)
			c3.y = float(e) * elev_step
			for k in 6:
				var v1 := Hex.inner_vertex(cell, k, 1.0, SOLID)
				var v2 := Hex.inner_vertex(cell, (k + 1) % 6, 1.0, SOLID)
				v1.y = c3.y
				v2.y = c3.y
				_tri(st, c3, v1, v2, col, col, col)
		# 边带：稳定 ID 较小者生成（builder 先例）
		for cell in cells:
			for d in 6:
				var nb := Hex.neighbor(cell, d)
				if not cells.has(nb):
					continue
				if _key_less(nb, cell):
					continue
				_emit_band(st, cells, cell, d, steps, elev_step)
		st.set_material(mat)
		return st.commit()

	## 单条边带：Δ=0 平带；Δ<threshold 阶地（Δn = n 组×steps 步，竖直 Catlike 剖面）；
	## Δ≥threshold 真垂直崖（共享崖线 XZ 同 XZ 墙顶/墙底 + 高低平台裙边，修订记录三之 3）
	func _emit_band(st: SurfaceTool, cells: Dictionary, a: Vector2i, d: int, steps: int,
			elev_step: float) -> void:
		var b := Hex.neighbor(a, d)
		var ea: int = cells[a]
		var eb: int = cells[b]
		var col_a: Color = ELEV_COLORS[clampi(ea, 0, ELEV_COLORS.size() - 1)]
		var col_b: Color = ELEV_COLORS[clampi(eb, 0, ELEV_COLORS.size() - 1)]
		var h_a := float(ea) * elev_step
		var h_b := float(eb) * elev_step
		var br := Hex.bridge_xz(a, d, 1.0, SOLID)
		var v1 := Hex.inner_vertex(a, d, 1.0, SOLID)
		var v2 := Hex.inner_vertex(a, (d + 1) % 6, 1.0, SOLID)
		var v3 := v1 + Vector3(br.x, 0.0, br.y)
		var v4 := v2 + Vector3(br.x, 0.0, br.y)
		v1.y = h_a
		v2.y = h_a
		v3.y = h_b
		v4.y = h_b
		var n := absi(ea - eb)
		if n == 0:
			_quad(st, v1, v2, v4, v3, col_a, col_a, col_b, col_b)
			return
		# 统一为 lo→hi 方向（t=0 在低侧）
		var lo1 := v1; var lo2 := v2; var hi1 := v3; var hi2 := v4
		var c_lo := col_a; var c_hi := col_b
		if h_a > h_b:
			lo1 = v3; lo2 = v4; hi1 = v1; hi2 = v2
			c_lo = col_b; c_hi = col_a
		if n >= CLIFF_THRESHOLD:
			# 真垂直崖：带中点 XZ（t=0.5）= 共享崖线；墙顶/墙底同 XZ；高低裙边水平
			var h_hi := maxf(h_a, h_b)
			var h_lo := minf(h_a, h_b)
			var m1 := lo1.lerp(hi1, 0.5); m1.y = 0.0
			var m2 := lo2.lerp(hi2, 0.5); m2.y = 0.0
			var wt1 := Vector3(m1.x, h_hi, m1.z)
			var wt2 := Vector3(m2.x, h_hi, m2.z)
			var wb1 := Vector3(m1.x, h_lo, m1.z)
			var wb2 := Vector3(m2.x, h_lo, m2.z)
			var wall_col := c_hi.darkened(0.25)
			_quad(st, hi1, hi2, wt2, wt1, c_hi, c_hi, wall_col, wall_col)   # 高侧裙边
			_quad(st, wt1, wt2, wb2, wb1, wall_col, wall_col, wall_col, wall_col)  # 竖直墙
			_quad(st, wb1, wb2, lo2, lo1, wall_col, wall_col, c_lo, c_lo)   # 低侧裙边
			return
		# 阶地：Δn = n 组 × steps 步；水平 t=s/S 均分、竖直走 Catlike 剖面（平台-短坡-平台）
		# 配色（目检可读性优先）：踏面 = 所在高程档色（离散跳档 → 平台读得出）、
		# 竖面 = 档色加深 0.2（riser/tread 对比）——spike 取舍，非 LAND-02 合同
		var total := n * steps
		var prev1 := lo1
		var prev2 := lo2
		var prev_y := minf(h_a, h_b)
		for s in range(1, total + 1):
			var t := float(s) / float(total)
			var g := (s - 1) / steps  # 组序（int 除法）
			var j := (s - 1) % steps + 1
			var vf := (float(g) + _vert_profile(j, steps)) / float(n)
			var y := lerpf(minf(h_a, h_b), maxf(h_a, h_b), vf)
			var r1 := lo1.lerp(hi1, t); r1.y = y
			var r2 := lo2.lerp(hi2, t); r2.y = y
			var tread_col := _elev_color_for_y(y, elev_step)
			var riser_col := tread_col.darkened(0.2)
			var c_prev := _elev_color_for_y(prev_y, elev_step)
			_quad(st, prev1, prev2, r2, r1,
				c_prev.darkened(0.2) if is_equal_approx(prev_y, y) == false else c_prev,
				c_prev.darkened(0.2) if is_equal_approx(prev_y, y) == false else c_prev,
				riser_col if is_equal_approx(prev_y, y) == false else tread_col,
				riser_col if is_equal_approx(prev_y, y) == false else tread_col)
			prev1 = r1
			prev2 = r2
			prev_y = y
		return

	## y → 所在高程档颜色（踏面离散跳档；除以本景竖直夸张系数还原高程层号——
	## 纵横比候选档只改墙高不改配色档）
	func _elev_color_for_y(y: float, elev_step: float) -> Color:
		var lvl := clampi(int(roundf(y / elev_step)), 0, ELEV_COLORS.size() - 1)
		return ELEV_COLORS[lvl]

	func _key_less(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y)

	func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
			ca: Color, cb: Color, cc: Color) -> void:
		st.set_color(ca); st.add_vertex(a)
		st.set_color(cb); st.add_vertex(b)
		st.set_color(cc); st.add_vertex(c)

	func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
			ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		_tri(st, a, b, c, ca, cb, cc)
		_tri(st, a, c, d, ca, cc, cd)

	func _cells_bounds(cells: Dictionary) -> Rect2:
		var r := Rect2()
		var first := true
		for cell in cells:
			var w := Hex.axial_to_world(cell, 1.0)
			var p := Vector2(w.x, w.z)
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
		return r.grow(0.6)

	# ---------------- 截图与通用 ----------------

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func _capture() -> Image:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null or img.is_empty():
			_fail("渲染帧捕获失败")
			return null
		if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		return img

	## 帧结构 CHECK（2026-10-11 收尾批新增，完成标准「探针 CHECK 已扩」的落点）：
	## ① 非背景像素下限——拦空/黑帧；② 断面列跨度下限——列跨度 = 逐列非背景像素的
	## y 跨度最大值，健全断面（平台+台阶/崖墙）必有竖贯大结构，初版退化 d3 图实测仅
	## ~15% 帧高（墙不可见），故 0.30 档只放行真正立得住的断面。过闸返回 true。
	func _check_shot(name: String, img: Image) -> bool:
		var scan := _scan_frame(img)
		if int(scan["non_bg"]) < NON_BG_FLOOR:
			_fail("CHECK %s 非背景像素 %d < 下限 %d（空/黑帧）" % [name, scan["non_bg"], NON_BG_FLOOR])
			return false
		if name.begins_with("section"):
			var want := int(float(img.get_height()) * SECTION_SPAN_RATIO)
			if int(scan["span"]) < want:
				_fail("CHECK %s 列跨度 %d < 下限 %d（断面结构退化）" % [name, scan["span"], want])
				return false
		print("[LAND-S] CHECK %s 通过（非背景 px=%d，列跨度 %dpx）" % [name, scan["non_bg"], scan["span"]])
		return true

	## 一遍扫描同时取非背景像素数与逐列 y 跨度最大值（get_pixel 逐像素调用不便宜，
	## 两个 CHECK 共享一次遍历）。背景判定 = 环境色 Color(0.16,0.17,0.2) 的 8bit 值
	## 逐通道差 ≤14（沿初版 _count_non_bg 口径，改判定须同步改注释防失真）。
	func _scan_frame(img: Image) -> Dictionary:
		var non_bg := 0
		var best_span := 0
		for x in img.get_width():
			var top := -1
			var bottom := -1
			for y in img.get_height():
				var c := img.get_pixel(x, y)
				var is_bg := absi(int(c.r8) - 41) <= 14 and absi(int(c.g8) - 43) <= 14 \
						and absi(int(c.b8) - 51) <= 14
				if not is_bg:
					non_bg += 1
					if top < 0:
						top = y
					bottom = y
			best_span = maxi(best_span, bottom - top)
		return {"non_bg": non_bg, "span": best_span}

	func _write_summary(saved: Array[String]) -> void:
		var dir_abs := ProjectSettings.globalize_path(EVIDENCE_DIR)
		if DirAccess.make_dir_recursive_absolute(dir_abs) != OK:
			_fail("证据目录创建失败")
			return
		var f := FileAccess.open("%s/land_spike_summary.txt" % EVIDENCE_DIR, FileAccess.WRITE)
		if f == null:
			_fail("summary 写入失败")
			return
		var rt := RenderingServer.get_current_rendering_method()
		f.store_string("LAND-S 七格测试场 spike（T2-SPIKE 附卡；2026-10-11）\n"
			+ "引擎：Godot %s；渲染器（实际运行时）：%s\n" % [Engine.get_version_info().get("string", "?"), rt]
			+ "实验几何：terrace 水平均分 + Catlike 竖直剖面（v_step=1/ceil(steps/2)）；"
			+ "真崖 = 带 t=0.5 共享崖线同 XZ 墙顶/墙底 + 高低裙边（Δ≥%d）\n" % CLIFF_THRESHOLD
			+ "固定图（tools/land_spike_fixtures.gd，LAND-S 测试锚 fixture）："
			+ "七格 = 中心 e0 + 六邻 e=[1,2,3,2,1,0]（Δ 全档 0/1/2/3）；断面 = 两格 Δ2 / Δ3\n"
			+ "已知取舍：角落不补面（针孔）——混合角目检口径 = 三边带汇聚，角几何补面属 LAND-01/LAND-02；"
			+ "材质 UNSHADED+CULL_DISABLED（绕序容错）——均非合同实现\n"
			+ "待主创目检拍板（执行方案 §3 LAND-S 卡内拍板项：spike 后与 LAND-02 合并拍）：\n"
			+ "  ① 阶地步数默认（5 vs 3——对比 overview/section_d2 两档）；\n"
			+ "  ② cliff 纵横比取向 = 竖直夸张系数（×1.0 vs ×1.5——对比 section_d3_ar100/ar150；"
			+ "横轴连接带宽 ≈0.35·size 为合同常量，docs/12 §1「垂直夸张」定调参考）\n"
			+ "截图：\n" + "\n".join(saved) + "\n")
		f.close()

	func _fail(reason: String) -> void:
		print("[LAND-S] PROBE FAIL — %s" % reason)
		get_tree().quit(1)

	func _arm_watchdog() -> void:
		var t := Timer.new()
		t.wait_time = WATCHDOG_SEC
		t.one_shot = true
		t.timeout.connect(func() -> void:
			print("[LAND-S] PROBE FAIL — 看门狗超时")
			get_tree().quit(1))
		add_child(t)
		t.start()
