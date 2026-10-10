## style_sandbox.gd — M1a+ BLEND-03 换 style 测试场（表现层目检载体；docs/04-tasks-m1.md §M1a+）
## 用法：编辑器打开 scenes/style_sandbox.tscn → 运行当前场景（F6）。
##   项目约定**无主场景**（project.godot 不设 run/main_scene）——不要为本场景改变该约定。
## 看什么（BLEND-03 验收的目检面）：
##   - terrain_style 是 TerrainStyle .tres（检查器可换）——两套入库默认：
##     resources/terrain/styles/terrain_style_blend_default.tres（混合过渡：草-泥-岩
##     边带/角落连续渐变，M1a+ BLEND-01/02 过渡合同）与 terrain_style_slots_default.tres
##     （默认色块：边带按归属格单材质硬切，旧 fallback 对照档）。**同一张图**换
##     style 重跑 = 只换观感：拓扑/可达性/拾取全部不变（headless 锚 =
##     tests/test_terrain_style.gd：summary/ARRAY_INDEX/face 表逐位一致、连通性一致、
##     材质实例不同）；
##   - 换观感的另一条路 = 改 style 指向的材质库 .tres（两风格同源，换库即同换观感
##     ——M1a-T8 先例）；
##   - 拾取/高亮在两 style 下照常（移动 = 暖黄 hover；左键 = 蓝色选择集）。
## 地图：8×5 手工固定图（地形 = (col*2 + row*3) % 3 → 草/泥/岩交错，odd-r 奇数行
##   偏移使边界锯齿化、六方向边带与三格角落都有目检样本；全平高程——本卡只验
##   换 style，高程不掺目检变量）。
extends Node3D

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const HexHighlight := preload("res://addons/hexhammer/hex_highlight.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const TerrainStyleClass := preload("res://scripts/core/data/terrain_style.gd")
const MapViewClass := preload("res://scripts/ui/map_view.gd")
const MapPickerClass := preload("res://scripts/ui/map_picker.gd")
const StrategyCameraClass := preload("res://scripts/ui/strategy_camera.gd")
const HighlightLayerClass := preload("res://scripts/ui/highlight_layer.gd")

## 渲染 style（BLEND-03 配置载体，检查器可换 .tres）。留空 = 载入混合过渡默认档。
@export var terrain_style: TerrainStyleClass

var _map: MapDataClass = null
var _hover_layer: HighlightLayerClass = null
var _selection_layer: HighlightLayerClass = null

func _ready() -> void:
	var map := _build_map()
	_map = map
	if terrain_style == null:
		terrain_style = TerrainStyleClass.load_default_blend()
	if terrain_style == null:
		print("[换 style 测试场] style 载入失败：", TerrainStyleClass.BLEND_DEFAULT_PATH)
		return
	var problems: Array = terrain_style.problems_for(map)
	if not problems.is_empty():
		print("[换 style 测试场] style 对本图不可解析（不静默换路线）：", problems)
		return
	var view: MapViewClass = MapViewClass.new()
	view.name = "MapView"
	add_child(view)
	if not view.build_with_style(map, terrain_style, 10, 10, 1.0, 1.0, 0.8):
		print("[换 style 测试场] 构建失败：style 解析通过但 builder 拒绝（参数非法？）")
		return
	# 拾取 + 高亮挂接（与 blend_sandbox 同构——证明两 style 网格上拾取/高亮合同不变）
	var picker: MapPickerClass = MapPickerClass.new()
	picker.name = "MapPicker"
	view.add_child(picker)
	var pick_ok := picker.setup(view.build_info, map)
	picker.cell_picked.connect(_on_cell_picked)
	picker.cell_selected.connect(_on_cell_selected)
	picker.pick_missed.connect(_on_pick_missed)
	print(pick_ok if pick_ok else "[换 style 测试场] 拾取挂接失败")
	_hover_layer = HighlightLayerClass.new()
	_hover_layer.name = "HoverHighlight"
	view.add_child(_hover_layer)
	_selection_layer = HighlightLayerClass.new()
	_selection_layer.name = "SelectionHighlight"
	view.add_child(_selection_layer)
	var hover_lift := HexHighlight.lift_for_tier(1)
	var hover_ok: bool = _hover_layer.setup(map, 1.0, 1.0, 0.8,
		HexHighlight.DEFAULT_COLOR, HexHighlight.DEFAULT_PATH_COLOR, -1.0, hover_lift)
	var sel_ok: bool = _selection_layer.setup(map, 1.0, 1.0, 0.8,
		Color(0.30, 0.55, 1.0, 0.40), Color(0.25, 0.75, 1.0, 1.0))
	if not hover_ok or not sel_ok:
		print("[换 style 测试场] 高亮层挂接失败（空图？）")
	var camera := get_node_or_null("StrategyCamera") as StrategyCameraClass
	if camera == null:
		print("[换 style 测试场] 场景缺 StrategyCamera 节点（检查 scenes/style_sandbox.tscn）")
	elif camera.setup(map, 1.0):
		print("[换 style 测试场] 策略相机已挂接：滚轮=档位缩放 / 中键=拖拽 / 边缘=平移")
	else:
		print("[换 style 测试场] 策略相机挂接失败（空图？）")
	print("[换 style 测试场] 8×5 草-泥-岩固定图 / style=%s" % terrain_style.label())
	print("[换 style 测试场] 检查器把 terrain_style 换成另一套 .tres 重跑 = 同图换观感；"
		+ "世界事实不变（headless 锚 = tests/test_terrain_style.gd）")

## 手工固定图：地形 = (col*2 + row*3) % 3（草/泥/岩交错）；全平高程。
func _build_map() -> MapDataClass:
	var map := MapDataClass.new(8, 5)
	for cell in map.cells():
		var cr := Hex.offset_of(cell)
		map.set_terrain(cell, (cr.x * 2 + cr.y * 3) % 3)
	return map

func _unhandled_input(event: InputEvent) -> void:
	var picker := get_node_or_null("MapView/MapPicker")
	if picker == null:
		return
	if event is InputEventMouseMotion:
		picker.request_pick_at((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
		and (event as InputEventMouseButton).pressed:
		picker.request_select_at((event as InputEventMouseButton).position)

func _on_cell_picked(cell: Vector2i) -> void:
	if _hover_layer != null:
		_hover_layer.highlight([cell])

func _on_cell_selected(cell: Vector2i) -> void:
	if _selection_layer == null:
		return
	var cells: Array = [cell]
	for nb in _map.neighbors_existing(cell):
		cells.append(nb)
	_selection_layer.highlight(cells)

func _on_pick_missed() -> void:
	if _hover_layer != null:
		_hover_layer.clear()
