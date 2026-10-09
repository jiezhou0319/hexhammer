## strategy_camera.gd — 策略相机 rig（M1a-T6 view 层节点；ADR-13「固定俯角策略相机
##   （平移/缩放/边界钳制）」；M1a 实现调研最小架构位 CameraRig）
## view 层纪律：本文件属 scripts/ui/**，可被整体删除——tests/ 与 addons/hexhammer/
##   hex_camera.gd 纯逻辑层均不感知本文件（「删 scripts/ui/** 后 tests 全绿」，02 §3）。
## 行为（04 M1a-T6；三个拍板约定的完整表述见 hex_camera.gd 头注）：
## - 固定俯角（pitch_deg，默认 55°）：恒定、与缩放档位无关（参考工程「随缩放插值
##   俯角」的逻辑不抄）；位姿 = 焦点 + HexCamera.camera_offset 后 look_at(注视点)。
## - 平移：① 屏幕边缘持续平移（鼠标进入 edge_margin 像素带触发，速度 ∝ 当前档位
##   距离 × edge_speed；窗口失焦/鼠标离窗不触发——陈旧坐标不得永动平移）；
##   ② 拖拽（drag_button，默认中键——左键留给 T5 拾取、右键留给后续指令 UI）：
##   锚点与命中均与 y = plane_y **固定参考平面**求交（不与地形 mesh 求交，跨高程
##   拖拽镜头不跳）；平移量 = 锚点 − 当前命中（锚点跟随光标）。
## - 缩放：滚轮上/下 = 拉近/拉远一档（离散档位表，最近/最远档钳制）。
## - 边界钳制：**钳「相机焦点」**（XZ ∈ 地图外沿包围盒 + focus_padding；
##   语义拍板见 hex_camera.gd 头注约定 1）。
## 使用：场景内 Camera3D + 本脚本，宿主 _ready 调 setup(map, hex_size) 建钳制域并
##   落位（焦点 = 图中心、档位 = 表中位、current = true）；未 setup 前不响应任何
##   输入（无钳制域的相机不擅自动）。
## 手感项（档位表/边缘速度/边距/平滑/俯角）全部 export 供主创实操调整；
## 「缩放档位/边界手感顺手」= 04 M1a-T6 主创实操确认项（不属 headless 验收）。
class_name StrategyCamera
extends Camera3D

const HexCameraLib := preload("res://addons/hexhammer/hex_camera.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 固定俯角（度；恒不随缩放变化——见类头注）
@export_range(15.0, 89.0, 0.5) var pitch_deg: float = HexCameraLib.DEFAULT_PITCH_DEG
## 缩放档位表（焦点→相机距离，升序；空 = 用 HexCameraLib.DEFAULT_ZOOM_DISTANCES）
@export var zoom_distances: Array[float] = []
## 焦点钳制域四边外扩（世界单位；0 = 钳到地图外沿顶点包络）
@export var focus_padding := 0.0
## 拖拽/注视固定参考平面高度（世界 y；0 = 地图基准面）
@export var plane_y := 0.0
## 拖拽平移鼠标键（默认中键；左键留给拾取、右键留给后续指令 UI）
@export var drag_button: MouseButton = MOUSE_BUTTON_MIDDLE
## 边缘平移触发带宽（像素）
@export var edge_margin := 20.0
## 边缘平移速度（世界单位/秒 · 每档位距离单位——拉远更快，跨图不换挡）
@export var edge_speed := 0.9
## 平滑趋近系数（指数；≤ 0 = 立即落位）。只作用于渲染位姿，纯逻辑焦点/档位即时生效。
@export var smooth_speed := 12.0

## 纯逻辑状态（焦点/档位/钳制域；setup 后非空）
var _core: HexCameraLib
var _view_focus := Vector2.ZERO  # 渲染焦点（平滑跟随 _core.focus）
var _view_distance := 0.0        # 渲染距离（平滑跟随 _core.distance()）
var _dragging := false
var _grab_xz := Vector2.ZERO     # 拖拽锚点（固定参考平面命中点）


## 建钳制域并落位：焦点 = 图中心、档位 = 表中位、current = true。
## 空图 → false（无格子即无钳制域——按头注纪律保持不响应输入）。
func setup(map: MapDataClass, hex_size := 1.0) -> bool:
	if map == null or map.cell_count() == 0:
		return false
	var bounds: Rect2 = HexCameraLib.map_focus_bounds(map, hex_size, focus_padding)
	_core = HexCameraLib.new(
		zoom_distances if zoom_distances.size() > 0 else HexCameraLib.DEFAULT_ZOOM_DISTANCES,
		bounds, bounds.get_center(), -1)
	_core.pitch_deg = pitch_deg
	_core.plane_y = plane_y
	_core.hex_size = hex_size
	_view_focus = _core.focus
	_view_distance = _core.distance()
	current = true
	_apply_transform()
	return true


func _process(delta: float) -> void:
	if _core == null:
		return
	if not _dragging:
		_edge_pan(delta)
	var k := 1.0 if smooth_speed <= 0.0 else 1.0 - exp(-smooth_speed * delta)
	_view_focus = _view_focus.lerp(_core.focus, k)
	_view_distance = lerpf(_view_distance, _core.distance(), k)
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if _core == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == drag_button:
			if mb.pressed and not _dragging:
				var grab: Variant = _plane_hit(mb.position)
				if grab != null:
					_grab_xz = grab as Vector2
					_dragging = true
			elif not mb.pressed:
				_dragging = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_core.zoom_in()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_core.zoom_out()
	elif _dragging and event is InputEventMouseMotion:
		var hit: Variant = _plane_hit((event as InputEventMouseMotion).position)
		if hit != null:
			# 相机平移量 = 锚点 − 当前命中（固定参考平面 ⇒ 跨高程不跳，见类头注）
			_core.pan_world(_grab_xz - (hit as Vector2))

# ---------------- 内部 ----------------

## 屏幕点 → 固定参考平面命中 XZ（拖拽锚点；平行/背向 → null）
func _plane_hit(screen_pos: Vector2) -> Variant:
	return HexCameraLib.drag_plane_xz(
		project_ray_origin(screen_pos), project_ray_normal(screen_pos), _core.plane_y)


## 边缘平移：屏幕方向 → 世界 XZ（相机右向/前向的水平投影），速度 ∝ 档位距离
func _edge_pan(delta: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if DisplayServer.get_name() != "headless":
		# 失焦守卫仅限有窗口环境（headless 无焦点概念，合成事件校验须走通完整链路）
		var window := get_window()
		if window != null and not window.has_focus():
			return  # 失焦：鼠标位置是陈旧值，不得永动平移
	var mouse := vp.get_mouse_position()
	var vsize := vp.get_visible_rect().size
	if mouse.x < -2.0 or mouse.x > vsize.x + 2.0 \
			or mouse.y < -2.0 or mouse.y > vsize.y + 2.0:
		return  # 鼠标已离窗（多显示器/窗外），陈旧坐标不得触发
	var dir := Vector2.ZERO  # 屏幕方向：x 右正、y 下正
	if mouse.x <= edge_margin:
		dir.x = -1.0
	elif mouse.x >= vsize.x - edge_margin:
		dir.x = 1.0
	if mouse.y <= edge_margin:
		dir.y = -1.0
	elif mouse.y >= vsize.y - edge_margin:
		dir.y = 1.0
	if dir == Vector2.ZERO:
		return
	dir = dir.normalized()
	var b := global_transform.basis
	var right := Vector2(b.x.x, b.x.z)  # 相机右向的水平投影（屏幕 +x）
	var fwd := Vector2(-b.z.x, -b.z.z)  # 相机前向的水平投影（屏幕上方）
	if right.length_squared() < 1e-12 or fwd.length_squared() < 1e-12:
		return
	var world := right.normalized() * dir.x - fwd.normalized() * dir.y
	_core.pan_world(world * (edge_speed * _core.distance() * delta))


## 位姿落位：注视点 = (渲染焦点, plane_y)；相机位置 = HexCamera.camera_position；
## look_at 只取位姿——俯角已由 offset 构造保证（固定俯角，不随缩放/距离变化）。
func _apply_transform() -> void:
	if _core == null:
		return
	var target := Vector3(_view_focus.x, _core.plane_y, _view_focus.y)
	global_position = HexCameraLib.camera_position(
		_view_focus, _core.plane_y, _view_distance, _core.pitch_deg, _core.yaw_deg)
	if is_inside_tree():
		look_at(target)
	else:
		rotation_degrees = Vector3(-_core.pitch_deg, _core.yaw_deg, 0.0)
