## highlight_layer.gd — 高亮层 view 节点（M1a-T7；调研架构位 HighlightLayer）
## view 层纪律：本文件属 scripts/ui/**，可被整体删除——tests/ 与 addons/hexhammer/
##   hex_highlight.gd 纯逻辑层均不感知本文件（「删 scripts/ui/** 后 tests 全绿」，
##   02 §3）。节点侧行为证据（缓存复用/差异切换/地形 mesh 不重建）见
##   tools/highlight_scene_check.gd 引擎级小场景校验（独立命令，非门禁）。
## API（04 M1a-T7「API：highlight(cells) / clear()，支持路径描线」）：
## - highlight(cells)：集合切换 = State 算差异 → 只对 added 现显节点、removed 隐藏；
##   **节点按格缓存复用**（首次高亮建、此后 visible 开关，不反复创建/销毁——
##   「鼠标移动不重建地形 mesh、不闪」的节点面）；
## - clear()：全部隐藏（缓存保留——下次高亮同格零创建）；
## - show_path(cells) / clear_path()：路径描线（M1b 移动范围/路径预铺）；
##   同路径重复调用跳过重建，换路径才重画（仍是单节点换 mesh，不碰格节点与地形）。
## 几何/材质纪律（细则见 addons/hexhammer/hex_highlight.gd 头注）：
## - 扇形 mesh 全层共享 1 实例（形状与格无关），节点 y = 内顶面 + lift（微决策 2）；
## - 共面治理：同场景多层须各取不同 lift 档（HexHighlightLib.lift_for_tier，
##   跨层同格双扇面错开）；本层描线带 y = 本层 lift + path_lift_extra（默认半档，
##   带永不在任何整档扇面平面上）——不共面即无远近缩放下的缝合纹/闪；
## - 透明材质深度测试保持开启（no_depth_test=false，不靠关深度测试掩盖穿山）；
## - 无碰撞体：MeshInstance3D 不入物理空间 → 拾取射线（mask 只查地形层）恒不被
##   高亮截获（hex_picking.gd LAYER_PICKABLE 语义面向带碰撞体的占位物，高亮不占层）。
## 界外格防御：highlight/show_path 静默跳过界外格（view 层薄防御；纯逻辑层
##   path_points 对界外显式返回空——两层口径分层担责）。
class_name HighlightLayer
extends Node3D

const HexHighlightLib := preload("res://addons/hexhammer/hex_highlight.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

var map: MapDataClass = null
var size := 1.0
var elevation_step := 1.0
var solid_factor := 0.8
var lift := HexHighlightLib.DEFAULT_LIFT            # 本层扇面 lift（跨层错开用）
var _path_lift := HexHighlightLib.DEFAULT_LIFT + HexHighlightLib.DEFAULT_PATH_LIFT_EXTRA

var _state: HexHighlightLib.State = null
var _fan_mesh: ArrayMesh = null
var _material: StandardMaterial3D = null
var _path_material: StandardMaterial3D = null
var _nodes: Dictionary = {}  # Vector2i → MeshInstance3D（缓存复用；visible 开关增删）
var _path_node: MeshInstance3D = null
var _path_mesh: ArrayMesh = null
var _last_path: Array = []  # 上次描线格序（同序跳过重建）
var _path_width := 0.18  # setup 按 DEFAULT_PATH_WIDTH_FACTOR × size 落定

## 建共享 mesh/材质与状态机。空图 / map 为空 / 非法参数 → false（与 MapView/
## MapPicker 同口径）。lift = 本层扇面档（同场景多层用 HexHighlightLib.lift_for_tier
## 各错一档）；path_lift_extra = 描线带相对本层扇面的抬升（默认半档，见头注共面治理）。
func setup(map_data: MapDataClass, hex_size := 1.0, elev_step := 1.0,
		solid := 0.8, highlight_color: Color = HexHighlightLib.DEFAULT_COLOR,
		path_color: Color = HexHighlightLib.DEFAULT_PATH_COLOR,
		path_width := -1.0, layer_lift := -1.0,
		path_lift_extra := -1.0) -> bool:
	clear()
	clear_path()
	# 重入防护（M-2 修复 2026-10-10）：setup 再调用 = 换图/换尺寸/换参数——旧图
	# 节点缓存（position/mesh/material_override 均旧值，_node_for 命中即复用旧值）
	# 与描线节点**先摘下树再延迟释放**：立即释放名字占位（否则同格新节点会被
	# 引擎改名 @MeshInstance3D@N，按名查找/校验失效），queue_free 保证安全时点。
	for node in _nodes.values():
		var old := node as MeshInstance3D
		remove_child(old)
		old.queue_free()
	_nodes.clear()
	if _path_node != null:
		remove_child(_path_node)
		_path_node.queue_free()
		_path_node = null
		_path_mesh = null
		_last_path = []
	if map_data == null or map_data.cell_count() == 0 or hex_size <= 0.0 or elev_step <= 0.0 \
			or solid <= 0.0 or solid >= 1.0:
		return false
	map = map_data
	size = hex_size
	elevation_step = elev_step
	solid_factor = solid
	if layer_lift >= 0.0:
		lift = layer_lift
	# 描线恒 = 本层 lift + extra（显式或默认半档）——layer_lift 换档时跟随，不失联
	_path_lift = lift + (path_lift_extra if path_lift_extra >= 0.0
		else HexHighlightLib.DEFAULT_PATH_LIFT_EXTRA)
	_state = HexHighlightLib.State.new()
	_fan_mesh = HexHighlightLib.inner_fan_mesh(size, solid_factor)
	_material = HexHighlightLib.highlight_material(highlight_color)
	_path_material = HexHighlightLib.path_material(path_color)
	if path_width < 0.0:
		path_width = HexHighlightLib.DEFAULT_PATH_WIDTH_FACTOR * size
	_path_width = path_width
	return true

## 高亮集合切换（04 M1a-T7 主 API）：差异增删——只对 added/removed 动节点。
func highlight(cells: Array) -> void:
	if _state == null:
		return
	var diff: Dictionary = _state.set_cells(cells)
	var added: Array = diff["added"]
	for c in added:
		var cell: Vector2i = c
		var node := _node_for(cell)
		if node != null:
			node.visible = true
	var removed: Array = diff["removed"]
	for c in removed:
		var cell: Vector2i = c
		_hide_cell(cell)

## 清空高亮（04 M1a-T7 主 API）：全部隐藏，节点缓存保留（复用）。
func clear() -> void:
	if _state == null:
		return
	var diff: Dictionary = _state.clear_cells()
	var removed: Array = diff["removed"]
	for c in removed:
		var cell: Vector2i = c
		_hide_cell(cell)

## 当前高亮集合快照（查询面；顺序无合同意义）。
func highlighted_cells() -> Array[Vector2i]:
	if _state == null:
		return []
	return _state.cells()

## 高亮节点是否已在缓存（引擎级校验「缓存复用」的探针）。
func has_cached_node(cell: Vector2i) -> bool:
	return _nodes.has(cell)

## 路径描线（04 M1a-T7「支持路径描线」）：界内格 < 2 → 清空并返回 false；
## 同路径重复调用 → 跳过重建返回 true。换路径才重画（单节点换 mesh）。
func show_path(cells: Array) -> bool:
	if _state == null:
		return false
	var in_bounds: Array = []
	for c in cells:
		if c is Vector2i and map.has_cell(c):
			in_bounds.append(c)
	if in_bounds == _last_path and _path_node != null:
		return true  # 同路径：不重建（描线不闪烁的节流面）
	if in_bounds.size() < 2:
		clear_path()
		return false
	var points := HexHighlightLib.path_points(in_bounds, map, size, elevation_step, _path_lift)
	var built: Variant = HexHighlightLib.path_strip_mesh(points, _path_width)
	if built == null:
		clear_path()
		return false
	if _path_node == null:
		_path_node = MeshInstance3D.new()
		_path_node.name = "PathStrip"
		_path_node.material_override = _path_material
		add_child(_path_node)
	_path_mesh = built as ArrayMesh
	_path_node.mesh = _path_mesh
	_path_node.visible = true
	_last_path = in_bounds.duplicate()
	return true

func clear_path() -> void:
	if _path_node != null:
		_path_node.visible = false
	_last_path = []

# ---------------- 内部 ----------------

## 取/建格节点（缓存复用核心）：缓存命中直接返回；未命中建节点入缓存。
## 界外格 → null（防御；调用方跳过）。
func _node_for(cell: Vector2i) -> MeshInstance3D:
	if _nodes.has(cell):
		return _nodes[cell]
	if not map.has_cell(cell):
		return null
	var node := MeshInstance3D.new()
	node.name = "HL_%d_%d" % [cell.x, cell.y]
	node.mesh = _fan_mesh  # 共享形状（几何与放置分离，见类头注）
	node.material_override = _material
	node.position = HexHighlightLib.cell_anchor(map, cell, size, elevation_step, lift)
	add_child(node)
	_nodes[cell] = node
	return node

func _hide_cell(cell: Vector2i) -> void:
	if _nodes.has(cell):
		(_nodes[cell] as MeshInstance3D).visible = false
