## 战旗相机：WASD/方向键平移，滚轮沿视线缩放（表现层，无游戏逻辑）
extends Node3D

const PAN_SPEED := 10.0
const ZOOM_MIN := 5.0
const ZOOM_MAX := 26.0
const ZOOM_STEP := 2.0
const PITCH_DEG := 52.0

@onready var cam: Camera3D = $Camera3D

var _view_dir := Vector3.BACK


func _ready() -> void:
	cam.rotation_degrees = Vector3(-PITCH_DEG, 0, 0)
	_view_dir = -cam.global_transform.basis.z  # 指向地面的视线方向
	cam.position = -_view_dir * 14.0           # 沿视线反向抬到空中俯瞰


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if dir != Vector2.ZERO:
		position.x += dir.x * PAN_SPEED * delta
		position.z += dir.y * PAN_SPEED * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var dist := cam.position.length()
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				cam.position = -_view_dir * clampf(dist - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				cam.position = -_view_dir * clampf(dist + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


## 自动化验收用：直接设定距离
func test_zoom(dist: float) -> void:
	cam.position = -_view_dir * dist
