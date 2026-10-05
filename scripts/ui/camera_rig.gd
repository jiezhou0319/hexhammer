## 大地图相机：WASD/方向键平移，滚轮缩放，限制在地图范围内。
class_name CameraRig
extends Camera2D

const SPEED := 700.0
const ZOOM_MIN := 0.45
const ZOOM_MAX := 2.2

var _map: HexMap

func setup(p_map: HexMap) -> void:
	_map = p_map
	position = _map_center()
	zoom = Vector2(0.8, 0.8)
	make_current()

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * SPEED * delta / zoom.x
	_clamp_to_map()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = (zoom * 1.12).clamp(Vector2.ONE * ZOOM_MIN, Vector2.ONE * ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = (zoom / 1.12).clamp(Vector2.ONE * ZOOM_MIN, Vector2.ONE * ZOOM_MAX)

func _map_center() -> Vector2:
	if _map == null or _map.terrain.is_empty():
		return Vector2.ZERO
	var min_p := Vector2(1e9, 1e9)
	var max_p := Vector2(-1e9, -1e9)
	for hex in _map.terrain:
		var p := Hex.to_pixel(hex, MapRenderer.HEX_SIZE)
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	return (min_p + max_p) / 2.0

func _clamp_to_map() -> void:
	if _map == null or _map.terrain.is_empty():
		return
	var min_p := Vector2(1e9, 1e9)
	var max_p := Vector2(-1e9, -1e9)
	for hex in _map.terrain:
		var p := Hex.to_pixel(hex, MapRenderer.HEX_SIZE)
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var margin := 400.0
	position.x = clampf(position.x, min_p.x - margin, max_p.x + margin)
	position.y = clampf(position.y, min_p.y - margin, max_p.y + margin)
