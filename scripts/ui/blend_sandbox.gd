## blend_sandbox.gd — M1a+ BLEND-01 过渡测试场（表现层目检载体；docs/04-tasks-m1.md §M1a+）
## 用法：编辑器打开 scenes/blend_sandbox.tscn → 运行当前场景（F6）。
##   项目约定**无主场景**（project.godot 不设 run/main_scene）——不要为本场景改变该约定。
## 看什么（BLEND-01 验收的目检面）：
##   - 草-泥边带：两端贴各自纯色、带内连续渐变（几何中点 ≈ 两纯色均权 0.5/0.5 混合）、
##     格心区域保持本格纯色（顶面扇面不参与混合——「避免一张地图全变成泥色」）；
##   - 检查器 render_style 切 SLOTS 重跑 = 旧单材质 fallback（边带整条画归属格材质，
##     草-泥硬切对照）——同一张图两种 style，证明 blend 只是表现层切片；
##   - 拾取/高亮在 blend 网格上照常工作（移动 = 暖黄 hover；左键 = 蓝色选择集）：
##     顶点 COLOR 不动几何/face 表/碰撞（单元测试另以逐位一致性锚定）。
## 数据路径：TerrainMaterialLibrary 默认 .tres（与 m1a_sandbox 同源、检查器可换库）→
##   HexTerrainBlend.palette_from_materials 提色板 → MapView.build_blend（mesh 顶点 COLOR）
##   + HexTerrainBlend.make_blend_material（顶点色 albedo 导管）。换 .tres 即两风格
##   同时换观感（材质槽读 Material、blend 提 albedo_color）。
## 地图：6×4 手工固定图（col<3 = 草 0，否则 = 泥 1；全平高程——本卡只验材质过渡，
##   高程连接混合不掺目检变量；odd-r 奇数行偏移使草-泥边界锯齿化，六个方向的边带
##   都有目检样本）。
extends Node3D

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const HexBlend := preload("res://addons/hexhammer/hex_terrain_blend.gd")
const HexHighlight := preload("res://addons/hexhammer/hex_highlight.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const TerrainMaterialLibraryClass := preload("res://scripts/core/data/terrain_material_library.gd")
const MapViewClass := preload("res://scripts/ui/map_view.gd")
const MapPickerClass := preload("res://scripts/ui/map_picker.gd")
const StrategyCameraClass := preload("res://scripts/ui/strategy_camera.gd")
const HighlightLayerClass := preload("res://scripts/ui/highlight_layer.gd")

## 渲染 style（BLEND-01 双路线）：BLEND = 色板权重混合（顶点色）；SLOTS = 旧单材质
## fallback（材质槽，边带硬切）——检查器切换后重跑场景对照。
enum RenderStyle { BLEND, SLOTS }

@export var render_style: RenderStyle = RenderStyle.BLEND
## 材质槽/色板共同来源（留空 = 载入主线默认色块库；换 .tres 即换观感）。
@export var material_library: TerrainMaterialLibraryClass

var _map: MapDataClass = null
var _hover_layer: HighlightLayerClass = null
var _selection_layer: HighlightLayerClass = null

func _ready() -> void:
	var map := _build_map()
	_map = map
	if material_library == null:
		material_library = TerrainMaterialLibraryClass.load_default()
	if material_library == null:
		print("[过渡测试场] 材质库载入失败：", TerrainMaterialLibraryClass.DEFAULT_PATH)
		return
	var missing: Array[int] = material_library.missing_ids(map)
	if not missing.is_empty():
		print("[过渡测试场] 材质表缺图内地形 id：", missing)
		return
	var view: MapViewClass = MapViewClass.new()
	view.name = "MapView"
	add_child(view)
	var ok := false
	if render_style == RenderStyle.BLEND:
		# BLEND-01 主路线：色板（.tres 提色）→ 顶点 COLOR + 顶点色 albedo 导管
		var palette: Variant = HexBlend.palette_from_materials(material_library.materials)
		if not (palette is Dictionary):
			print("[过渡测试场] 色板提取失败：材质库含非 StandardMaterial3D 槽（取不到 albedo_color）")
			return
		ok = view.build_blend(map, palette, 10, 10, HexBlend.make_blend_material(), 1.0, 1.0)
	else:
		ok = view.build(map, 10, 10, material_library.materials, 1.0, 1.0)
	if not ok:
		print("[过渡测试场] 构建失败：材质表/色板缺图内地形 id 或参数非法")
		return
	# 拾取 + 高亮挂接（与 m1a_sandbox 同构——证明 blend 网格上拾取/高亮合同不变）
	var picker: MapPickerClass = MapPickerClass.new()
	picker.name = "MapPicker"
	view.add_child(picker)
	var pick_ok := picker.setup(view.build_info, map)
	picker.cell_picked.connect(_on_cell_picked)
	picker.cell_selected.connect(_on_cell_selected)
	picker.pick_missed.connect(_on_pick_missed)
	print(pick_ok if pick_ok else "[过渡测试场] 拾取挂接失败")
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
		print("[过渡测试场] 高亮层挂接失败（空图？）")
	var camera := get_node_or_null("StrategyCamera") as StrategyCameraClass
	if camera == null:
		print("[过渡测试场] 场景缺 StrategyCamera 节点（检查 scenes/blend_sandbox.tscn）")
	elif camera.setup(map, 1.0):
		print("[过渡测试场] 策略相机已挂接：滚轮=档位缩放 / 中键=拖拽 / 边缘=平移")
	else:
		print("[过渡测试场] 策略相机挂接失败（空图？）")
	var style_name := "BLEND（色板权重混合，M1a+ BLEND-01）" if render_style == RenderStyle.BLEND \
		else "SLOTS（旧单材质 fallback——检查器切 render_style=BLEND 看过渡）"
	print("[过渡测试场] 6×4 草-泥固定图 / style=%s / 拾取+高亮已挂接" % style_name)
	print("[过渡测试场] 权重合同：边带端点 (1,0)/(0,1)、中点 (0.5,0.5)、和恒 1——"
		+ "格心顶面恒纯色（headless 锚 = tests/test_hex_terrain_blend.gd）")

## 手工固定图：col<3 = 草(0)、否则 = 泥(1)；全平高程（本卡只验材质过渡）。
func _build_map() -> MapDataClass:
	var map := MapDataClass.new(6, 4)
	for cell in map.cells():
		var cr := Hex.offset_of(cell)
		map.set_terrain(cell, 0 if cr.x < 3 else 1)
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
