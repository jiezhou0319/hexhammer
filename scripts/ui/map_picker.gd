## map_picker.gd — 地形拾取 view 层（M1a-T5；调研架构位 MapPicker）
## view 层纪律：本文件属 scripts/ui/**，可被整体删除——tests/ 与 addons/hex_picking.gd
##   均不感知本文件（「删 scripts/ui/** 后 tests 全绿」的分层验收口径，02 §3）。
## 链路（04 M1a-T5）：屏幕点 → 入队 request_pick_at → **物理回调内**（_physics_process，
##   其他时机物理空间可能被锁定——官方 ray-casting 教程口径）unproject 相机射线
##   → intersect_ray（mask 只查地形层：棋子/高亮/装饰在 LAYER_PICKABLE，恒不截获）
##   → 命中世界坐标 → map_root.to_local（地图根局部坐标——根整体平移后仍正确）
##   → face_index 查 face 表（ConcavePolygonShape3D 专属语义；表按自提交碰撞三角形
##   顺序建映射，构建与规则全在 addons/hex_picking.gd 纯逻辑层，引擎级小场景校验见
##   tools/picking_scene_check.gd）→ 微决策 3 归属规则 → cell_picked 信号。
## 碰撞体：每 chunk 一个 StaticBody3D（挂 map_root 下、局部零偏移——跟随地图根
##   变换）+ ConcavePolygonShape3D（静态关卡几何适用形状；不挪作棋子碰撞体）。
class_name MapPicker
extends Node3D

## hover 解析结果（motion 持续请求）；M-1 修复（2026-10-10）前选择直接读沙盒侧
## 陈旧 hover 格——现在点击走独立请求通道，命中经 cell_selected 分派
signal cell_picked(cell: Vector2i)
## 选择解析结果（request_select_at 的回执）——点击格即选中格
signal cell_selected(cell: Vector2i)
signal pick_missed()

const HexPickingLib := preload("res://addons/hexhammer/hex_picking.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 拾取射线 mask：只查地形层（HexPickingLib.LAYER_TERRAIN 单一位；
## 棋子/高亮/装饰挂 LAYER_PICKABLE——mask 恒不含，不得截获地形拾取）
@export var collision_mask: int = HexPickingLib.MASK_TERRAIN_ONLY
## 射线长度（世界单位；60×40 图对角 + 高程余量足够）
@export var ray_length := 500.0

var size := 1.0
var map: MapDataClass
## 地图根（世界↔局部转换参照；默认取父节点——本节点须挂在地图根下）
var map_root: Node3D

var _tables := {}  # body instance_id → 该 chunk face 表（Array[Dictionary]）
var _bodies: Array[StaticBody3D] = []
var _pending: Array = []  # {"pos": Vector2, "select": bool}（同点同类型去重）

## 挂碰撞体并建 face 表。map_root 省略 = get_parent()（MeshView/MapView 等地图根）；
## 要求地图根的局部坐标 = builder 产出的地图全局坐标（T3 挂载约定）。
func setup(build_info: Dictionary, map_data: MapDataClass, root: Node3D = null,
		hex_size := 1.0) -> bool:
	clear()
	if root == null:
		root = get_parent() as Node3D
	if root == null or not (build_info is Dictionary) or (build_info as Dictionary).is_empty():
		return false
	map_root = root
	map = map_data
	size = hex_size
	var chunks: Array = build_info["chunks"]
	if chunks.is_empty():
		return false
	for chunk_info in chunks:
		var cd: Dictionary = chunk_info
		var pd: Dictionary = HexPickingLib.chunk_pick_data(cd)
		var soup: PackedVector3Array = pd["collision_faces"]
		if soup.size() == 0:
			return false
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(soup)  # 自提交三角形顺序 = face 表顺序（face_index 映射依据）
		var body := StaticBody3D.new()
		body.name = "TerrainCollision_c%d_r%d" % [(pd["chunk"] as Rect2i).position.x, (pd["chunk"] as Rect2i).position.y]
		body.collision_layer = 1 << (HexPickingLib.LAYER_TERRAIN - 1)
		body.collision_mask = 0  # 静态地形不主动撞任何层（棋子层后续自行向地形投影）
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		map_root.add_child(body)  # 局部零偏移：世界变换随地图根
		_tables[body.get_instance_id()] = pd["face_table"]
		_bodies.append(body)
	return true

## 屏幕点拾取请求：**只入队**——物理查询统一挪到 _physics_process（其他时机物理
## 空间可能被锁定；04 M1a-T5 细化）。同帧多次同点请求去重。
func request_pick_at(screen_pos: Vector2) -> void:
	_enqueue(screen_pos, false)

## 选择请求（M-1 修复 2026-10-10）：与 hover 同队列、同物理回调解析，命中经
## cell_selected 信号分派——调用方不读 hover 状态，点击格即选中格。
func request_select_at(screen_pos: Vector2) -> void:
	_enqueue(screen_pos, true)

func _enqueue(screen_pos: Vector2, select: bool) -> void:
	for e in _pending:
		var req: Dictionary = e
		if req["pos"] == screen_pos and req["select"] == select:
			return
	_pending.append({"pos": screen_pos, "select": select})

## 世界射线拾取（公开 API：查询 + 局部转换 + face 表 + 归属规则）。
## **物理回调内调用**（_physics_process / 物理信号），返回格坐标；未命中/非地形面 → null。
func pick_world_ray(origin: Vector3, dir: Vector3) -> Variant:
	if map == null or map_root == null:
		return null
	var space := map_root.get_world_3d().direct_space_state
	var to := origin + dir.normalized() * ray_length
	var query := PhysicsRayQueryParameters3D.create(origin, to, collision_mask)
	var hit := space.intersect_ray(query)  # face_index 仅 ConcavePolygonShape3D 有效
	if hit.is_empty():
		return null
	var table: Array = _tables.get(hit["collider_id"], [])
	return HexPickingLib.resolve_hit(map_root.to_local(hit["position"]),
		int(hit["face_index"]), table, map, size)

func clear() -> void:
	for body in _bodies:
		body.queue_free()
	_bodies.clear()
	_tables.clear()
	_pending.clear()
	map = null
	map_root = null

func _physics_process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return  # 无相机：请求留队，相机可用后再查
	while not _pending.is_empty():
		var req: Dictionary = _pending.pop_front()
		var screen_pos: Vector2 = req["pos"]
		var cell: Variant = pick_world_ray(
			camera.project_ray_origin(screen_pos),
			camera.project_ray_normal(screen_pos))
		if cell == null:
			pick_missed.emit()
		elif req["select"]:
			cell_selected.emit(cell)
		else:
			cell_picked.emit(cell)
