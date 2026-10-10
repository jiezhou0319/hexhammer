## blend_corner_sandbox.gd — M1a+ BLEND-02 三格交汇过渡测试场（表现层目检载体；docs/04-tasks-m1.md §M1a+）
## 用法：编辑器打开 scenes/blend_corner_sandbox.tscn → 运行当前场景（F6）。
##   项目约定**无主场景**（project.godot 不设 run/main_scene）——不要为本场景改变该约定。
## 看什么（BLEND-02 验收的目检面）：
##   - 草-泥-岩三格共享角：地图按**行**切 chunk（chunk_rows=1，共 5 块），行 0 与
##     行 1 之间的 chunk 缝正好从三格交汇角中间穿过——角面三端各贴所在格纯色、
##     角面内连续过渡（几何重心 ≈ 三色各 1/3 权重混合、权重和恒 1）；
##   - 跨 chunk 无裂缝/无重复角面：缝两侧边带/角面只生成一次、锚点从同一全局参数
##     计算（跨块接缝逐位无错位；headless 锚 = tests/test_hex_terrain_blend_corner.gd
##     ——「单 chunk / 行切 / 每格一 chunk」三种划分角面位置+顶点色逐位一致）；
##   - 检查器 render_style 切 SLOTS 重跑 = 旧单材质 fallback（三色硬切对照）——
##     同一张图两种 style，证明 blend 只是表现层切片；
##   - 拾取/高亮在 blend 网格上照常工作（移动 = 暖黄 hover、左键 = 蓝色选择集）：
##     顶点 COLOR 不动几何/face 表/碰撞（单元测试另以逐位一致性锚定）。
## 数据路径：TerrainMaterialLibrary 默认 .tres（检查器可换库）→
##   HexTerrainBlend.palette_from_materials 提色板 → MapView.build_blend
##   （chunk 划分 6×1——按行切，保证三格交汇角跨块）+ make_blend_material
##   （顶点色 albedo 导管）。角面顶点 = 三格权重合同（HexTerrainBlend.corner_weights）
##   的单位权重锚点，面内三色过渡 = 顶点 COLOR 线性插值。
## 地图：6×5 手工固定图（草底 + 泥区左下 + 岩带首行右段；全平高程——本卡只验
##   三格材质过渡，高程连接混合不掺目检变量）。
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

## 渲染 style（与 BLEND-01 双路线同构）：BLEND = 色板权重混合（顶点色）；
## SLOTS = 旧单材质 fallback（材质槽，三色硬切）——检查器切换后重跑场景对照。
enum RenderStyle { BLEND, SLOTS }

@export var render_style: RenderStyle = RenderStyle.BLEND
## 材质槽/色板共同来源（留空 = 载入主线默认色块库；换 .tres 即换观感）。
@export var material_library: TerrainMaterialLibraryClass

## chunk 划分固定按行切（列 = 图宽 → 每行一块）：三格交汇角必跨 chunk。
const CHUNK_COLS := 6
const CHUNK_ROWS := 1

var _map: MapDataClass = null
var _hover_layer: HighlightLayerClass = null
var _selection_layer: HighlightLayerClass = null

func _ready() -> void:
	var map := _build_map()
	_map = map
	if material_library == null:
		material_library = TerrainMaterialLibraryClass.load_default()
	if material_library == null:
		print("[三格交汇测试场] 材质库载入失败：", TerrainMaterialLibraryClass.DEFAULT_PATH)
		return
	var missing: Array[int] = material_library.missing_ids(map)
	if not missing.is_empty():
		print("[三格交汇测试场] 材质表缺图内地形 id：", missing)
		return
	var view: MapViewClass = MapViewClass.new()
	view.name = "MapView"
	add_child(view)
	var ok := false
	if render_style == RenderStyle.BLEND:
		# BLEND-02 主路线：色板（.tres 提色）→ 顶点 COLOR + 顶点色 albedo 导管；
		# chunk 6×1 = 按行切——草-泥-岩交汇角横跨 chunk 缝
		var palette: Variant = HexBlend.palette_from_materials(material_library.materials)
		if not (palette is Dictionary):
			print("[三格交汇测试场] 色板提取失败：材质库含非 StandardMaterial3D 槽（取不到 albedo_color）")
			return
		ok = view.build_blend(map, palette, CHUNK_COLS, CHUNK_ROWS,
			HexBlend.make_blend_material(), 1.0, 1.0)
	else:
		ok = view.build(map, CHUNK_COLS, CHUNK_ROWS, material_library.materials, 1.0, 1.0)
	if not ok:
		print("[三格交汇测试场] 构建失败：材质表/色板缺图内地形 id 或参数非法")
		return
	# 拾取 + 高亮挂接（与 blend_sandbox 同构——blend 网格上拾取/高亮合同不变）
	var picker: MapPickerClass = MapPickerClass.new()
	picker.name = "MapPicker"
	view.add_child(picker)
	var pick_ok := picker.setup(view.build_info, map)
	picker.cell_picked.connect(_on_cell_picked)
	picker.cell_selected.connect(_on_cell_selected)
	picker.pick_missed.connect(_on_pick_missed)
	print(pick_ok if pick_ok else "[三格交汇测试场] 拾取挂接失败")
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
		print("[三格交汇测试场] 高亮层挂接失败（空图？）")
	var camera := get_node_or_null("StrategyCamera") as StrategyCameraClass
	if camera == null:
		print("[三格交汇测试场] 场景缺 StrategyCamera 节点（检查 scenes/blend_corner_sandbox.tscn）")
	elif camera.setup(map, 1.0):
		print("[三格交汇测试场] 策略相机已挂接：滚轮=档位缩放 / 中键=拖拽 / 边缘=平移")
	else:
		print("[三格交汇测试场] 相机挂接失败（空图？）")
	var style_name := "BLEND（三格权重混合，M1a+ BLEND-02）" if render_style == RenderStyle.BLEND \
		else "SLOTS（旧单材质 fallback——检查器切 render_style=BLEND 看过渡）"
	print("[三格交汇测试场] 6×5 草-泥-岩固定图 / chunk 按行切（%d×%d，%d 块）/ style=%s / 拾取+高亮已挂接"
		% [CHUNK_COLS, CHUNK_ROWS, map.height, style_name])
	print("[三格交汇测试场] 三格权重合同：角面顶点 = 单位权重 (1,0,0)/(0,1,0)/(0,0,1)、"
		+ "重心 (1/3,1/3,1/3)、和恒 1——跨 chunk 角面位置/颜色不随划分改变"
		+ "（headless 锚 = tests/test_hex_terrain_blend_corner.gd）")

## 手工固定图（6×5，全平高程）：草底；泥区 = col ≤ 1 且 row ≥ 1；岩带 = row 0 且 col ≥ 2。
## 草-泥-岩共享角样本：offset (1,1)泥 / (1,0)草 / (2,0)岩 的共享顶点等
## 一批三格交汇角，全部压在 row0/row1 的 chunk 缝上。
func _build_map() -> MapDataClass:
	var map := MapDataClass.new(6, 5)
	for cell in map.cells():
		var cr := Hex.offset_of(cell)
		if cr.y >= 1 and cr.x <= 1:
			map.set_terrain(cell, 1)  # 泥
		elif cr.y == 0 and cr.x >= 2:
			map.set_terrain(cell, 2)  # 岩
		else:
			map.set_terrain(cell, 0)  # 草
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
