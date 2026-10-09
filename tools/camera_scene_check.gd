## camera_scene_check.gd — M1a-T6 策略相机引擎级小场景校验（独立工具，非门禁）
## 用法（跑真渲染/输入帧，与门禁命令分开执行）：
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless \
##     --path hexhammer --script res://tools/camera_scene_check.gd
## 为什么独立（沿 picking_scene_check.gd 先例）：门禁 run_tests.gd 在 SceneTree._init
##   内同步执行并 quit，主循环从不迭代；rig 的输入处理/每帧位姿落位只能跑帧验证。
##   headless 无真实窗口输入，用 Input.parse_input_event 注入合成事件走完整分发链
##   （_unhandled_input 与生产同路径）。数学证明不重复——钳制/档位/映射的纯逻辑
##   证明在 tests/test_hex_camera.gd，本工具只取「引擎侧跑得起来且行为方向正确」。
## 校验内容（04 M1a-T6 验收的引擎侧证据）：
##   A. 沙盒场景加载+实例化：场景/脚本无编译错误，StrategyCamera 存在且 setup 生效
##      （current = true）；
##   B. 初始位姿：焦点 = 图中心（oracle = 同尺寸空图的 map_focus_bounds 中心——域只
##      依赖尺寸/size）、相机在南（+z）、俯角 55°（前向 y = −sin55）、
##      高度 = 中位档距离·sin55（默认表 6 档 → 第 3 档 48）；
##   C. 缩放档位极值（引擎侧）：注入滚轮连拉远 → 收敛最远档 78·sin55；
##      连拉近 → 收敛最近档 18·sin55（平滑 12 → 60 帧 ≈ 99.98% 收敛）；
##   D. 中键拖拽：press → motion → release 全链无错、焦点位移、焦点仍在钳制域内
##      （焦点从相机位姿反解：focus = pos − offset，yaw0 时 offset = (0, d·cos55)）；
##   E. 边缘平移：motion 到屏幕左边缘带 → 焦点西移（速度 ∝ 档位距离）。
##   手感项（档位/边界顺手、全图实操可达）不在本工具——主创 F6 实操确认。
## 退出码：全部通过 0，任一失败 1。
extends SceneTree

func _init() -> void:
	print("[相机小场景校验] init（deferred 启动，等待主循环）")
	_boot.call_deferred()

func _boot() -> void:
	if root.world_3d == null:
		root.world_3d = World3D.new()
	var checker := Checker.new()
	root.add_child(checker)

## 校验节点：_process 推阶段，注入合成输入，按阶段断言
class Checker extends Node:
	const CamLib := preload("res://addons/hexhammer/hex_camera.gd")
	const MapData := preload("res://scripts/core/data/map_data.gd")
	const StrategyCameraScript := preload("res://scripts/ui/strategy_camera.gd")

	const MAP_W := 60
	const MAP_H := 40
	const SIZE := 1.0
	const PITCH := 55.0
	const SETTLE_FRAMES := 60
	const QUICK_FRAMES := 5
	const POS_EPS := 0.5
	const WATCHDOG_FRAMES := 1200

	var phase := -1
	var settle := 0
	var ticks := 0
	var pass_count := 0
	var fail_count := 0
	var sandbox: Node = null
	var camera: StrategyCameraScript = null
	var bounds: Rect2
	var focus_before := Vector2.ZERO

	func _ready() -> void:
		# oracle：钳制域只依赖图尺寸/size —— 同尺寸空图即得（不复制沙盒地貌）
		bounds = CamLib.map_focus_bounds(MapData.new(MAP_W, MAP_H), SIZE)
		var packed: Variant = load("res://scenes/m1a_sandbox.tscn")
		if not (packed is PackedScene):
			_fail_hard("A：沙盒场景加载失败（tscn/脚本编译错误？）")
			return
		sandbox = (packed as PackedScene).instantiate()
		get_tree().root.add_child(sandbox)
		camera = sandbox.get_node_or_null("StrategyCamera") as StrategyCameraScript
		if camera == null:
			_fail_hard("A：场景缺 StrategyCamera 节点")
			return
		# headless 鼠标初始在 (0,0)＝边缘带内（margin=0 也不禁用：0 ≤ 0 成立），
		# 注入的居中 motion 要到下一帧输入阶段才生效——B/C/D 期间直接置
		# edge_speed=0（零速度＝零位移，确定性禁用边缘平移），E 阶段恢复再验证。
		camera.edge_speed = 0.0
		_motion(_viewport_center())
		phase = 0
		settle = QUICK_FRAMES

	func _process(_delta: float) -> void:
		ticks += 1
		if ticks > WATCHDOG_FRAMES:
			print("[相机小场景校验] FAIL 看门狗超时（phase=%d）" % phase)
			get_tree().quit(1)
			set_process(false)
			return
		if settle > 0:
			settle -= 1
			return
		match phase:
			0:
				_check_ab_initial_pose()
				_stage_zoom_out()
			1:
				_check_c("C2. 滚轮连拉远 → 收敛最远档 78·sin55（最大极值，引擎侧）",
					78.0 * sin(deg_to_rad(PITCH)))
				_stage_zoom_in()
			2:
				_check_c("C1. 滚轮连拉近 → 收敛最近档 18·sin55（最小极值，引擎侧）",
					18.0 * sin(deg_to_rad(PITCH)))
				_stage_drag()
			3:
				_check_d_drag()
				_stage_edge()
			4:
				_check_e_edge_pan()
				_finish()

	# ---------------- 阶段推进 ----------------

	func _stage_zoom_out() -> void:
		for i in 10:
			_wheel(false)
		phase = 1
		settle = SETTLE_FRAMES

	func _stage_zoom_in() -> void:
		for i in 20:
			_wheel(true)
		phase = 2
		settle = SETTLE_FRAMES

	func _stage_drag() -> void:
		var center := _viewport_center()
		_button(MOUSE_BUTTON_MIDDLE, true, center)
		for i in 5:
			_motion(center + Vector2(30.0 * float(i), 40.0 * float(i)))
		_button(MOUSE_BUTTON_MIDDLE, false, center + Vector2(120.0, 160.0))
		phase = 3
		settle = QUICK_FRAMES + 10

	func _stage_edge() -> void:
		camera.edge_speed = 0.9  # 恢复边缘平移（E 专项验证）
		focus_before = _focus_from_pose()
		var vsize := get_viewport().get_visible_rect().size
		_motion(Vector2(0.0, vsize.y * 0.5))  # 左边缘带内
		phase = 4
		settle = 30

	# ---------------- 检查 ----------------

	func _check_ab_initial_pose() -> void:
		_check(camera.current, "A. 沙盒实例化成功，StrategyCamera.setup 生效（current）")
		var want_d := float(CamLib.DEFAULT_ZOOM_DISTANCES[CamLib.DEFAULT_ZOOM_DISTANCES.size() / 2])
		var ctr := bounds.get_center()
		var p := camera.global_position
		_check(absf(p.y - want_d * sin(deg_to_rad(PITCH))) < POS_EPS,
			"B1. 初始高度 = 中位档 %.0f·sin55（got %.2f）" % [want_d, p.y])
		_check(absf(p.x - ctr.x) < POS_EPS, "B2. 初始焦点 x = 图中心（got %.2f want %.2f）" % [p.x, ctr.x])
		_check(absf(p.z - (ctr.y + want_d * cos(deg_to_rad(PITCH)))) < POS_EPS,
			"B3. 初始相机在焦点南侧 +z（got %.2f want %.2f）" % [p.z, ctr.y + want_d * cos(deg_to_rad(PITCH))])
		var fwd := -camera.global_transform.basis.z
		_check(absf(fwd.y + sin(deg_to_rad(PITCH))) < 0.01,
			"B4. 固定俯角 55°（前向 y = −sin55，got %.4f）——与缩放无关" % fwd.y)
		_check(absf(fwd.x) < 0.01 and fwd.z < 0.0, "B5. 朝北看（yaw 0）")

	func _check_c(label: String, want_y: float) -> void:
		_check(absf(camera.global_position.y - want_y) < POS_EPS,
			"%s（got %.2f want %.2f）" % [label, camera.global_position.y, want_y])

	func _check_d_drag() -> void:
		var focus := _focus_from_pose()
		var moved := focus.distance_to(bounds.get_center())
		_check(moved > 1.0, "D1. 中键拖拽链路无错且焦点位移（moved %.2f）" % moved)
		_check(focus.x >= bounds.position.x - POS_EPS
			and focus.x <= bounds.position.x + bounds.size.x + POS_EPS
			and focus.y >= bounds.position.y - POS_EPS
			and focus.y <= bounds.position.y + bounds.size.y + POS_EPS,
			"D2. 拖拽后焦点仍在钳制域内（focus %s，域 %s）" % [str(focus), str(bounds)])

	func _check_e_edge_pan() -> void:
		var focus := _focus_from_pose()
		_check(focus.x < focus_before.x - 1.0,
			"E. 左边缘注入 → 焦点西移（%.2f → %.2f）" % [focus_before.x, focus.x])
		_motion(_viewport_center())  # 归位中心，停边缘平移

	# ---------------- 合成输入（走 Input 单例完整分发链）----------------

	func _wheel(up: bool) -> void:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		e.position = _viewport_center()
		Input.parse_input_event(e)

	func _button(index: int, pressed: bool, pos: Vector2) -> void:
		var e := InputEventMouseButton.new()
		e.button_index = index
		e.pressed = pressed
		e.position = pos
		e.button_mask = MOUSE_BUTTON_MASK_MIDDLE if pressed else 0
		Input.parse_input_event(e)

	func _motion(pos: Vector2) -> void:
		var e := InputEventMouseMotion.new()
		e.position = pos
		e.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		Input.parse_input_event(e)

	func _viewport_center() -> Vector2:
		var vsize := get_viewport().get_visible_rect().size
		return vsize * 0.5

	## 焦点反解：focus = pos − offset；最近档（18）时 offset = (0, 18·cos55)（yaw0）
	func _focus_from_pose() -> Vector2:
		var d := float(CamLib.DEFAULT_ZOOM_DISTANCES[0])
		var p := camera.global_position
		return Vector2(p.x, p.z - d * cos(deg_to_rad(PITCH)))

	func _check(cond: bool, label: String) -> void:
		if cond:
			pass_count += 1
			print("[相机小场景校验] PASS %s" % label)
		else:
			fail_count += 1
			print("[相机小场景校验] FAIL %s" % label)

	func _fail_hard(label: String) -> void:
		print("[相机小场景校验] FAIL %s" % label)
		get_tree().quit(1)
		set_process(false)

	func _finish() -> void:
		set_process(false)
		print("[相机小场景校验] === %d 通过 / %d 失败 ===" % [pass_count, fail_count])
		get_tree().quit(1 if fail_count > 0 else 0)
