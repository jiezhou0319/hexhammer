## m1a_sandbox.gd — M1a 沙盒场景脚本（T3 起供主创目检；T4 起含高程分层与连续连接目检；
##   T6 起挂策略相机 rig——固定俯角/边缘+拖拽平移/滚轮档位缩放/焦点钳制；
##   T7 起挂高亮层——hover 单格高亮 / 左键选择集合 + 路径描线；
##   T9 起地图来源可选——默认 FIXED：运行场景即出「一键可玩测试图」）
## 用法：编辑器打开 scenes/m1a_sandbox.tscn → 运行当前场景（F6）。
## 项目约定**无主场景**（project.godot 不设 run/main_scene）——不要为本沙盒改变该约定。
## 地图来源（M1a-T9，检查器 map_source 切换）：
##   - FIXED（默认）：resources/maps/fixed/playable_60x40.json——手工固定图
##     （tools/make_fixed_maps.gd 落盘，无噪声无随机），六地形 + 三档连接 + 连通可玩；
##   - RANDOM：MapGenerator（scripts/content/map_generator.gd）按下方 random_* 参数
##     生成——同 seed 同参数逐格复现（限定固定生成器版本与引擎构建）；
##   - PATTERN：T3/T4 时代的确定性公式图（保留作几何对照）。
## FIXED/RANDOM 图自带尺寸与数据（map_width/map_height 仅用于 PATTERN/RANDOM）；
## 灯为场景内固定摆位；相机 = StrategyCamera rig（M1a-T6，_ready 里 setup 建钳制域，
##   初始焦点 = 图中心、档位 = 表中位——位姿由 rig 自行落位，场景文件不再预摆）。
## M1a-T7 高亮目检（「高亮/取消无感知延迟、不闪、不穿山」的实操载体）：
##   - 鼠标移动 = hover 层单格高亮（暖黄半透明，贴合内顶面）；
##   - 左键点击地形 = 选择层高亮该格 + 界内 6 邻（蓝色），并从上次选中格描一条
##     直线路径（橙色贴地带）——路径为演示用直线采样，真寻路 M1b-T4 落地。
## 改分块/高程步长：选中根节点在检查器改导出参数后重跑场景即可。
extends Node3D

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const HexHighlight := preload("res://addons/hexhammer/hex_highlight.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const TerrainMaterialLibraryClass := preload("res://scripts/core/data/terrain_material_library.gd")
const MapViewClass := preload("res://scripts/ui/map_view.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const MapPickerClass := preload("res://scripts/ui/map_picker.gd")
const StrategyCameraClass := preload("res://scripts/ui/strategy_camera.gd")
const HighlightLayerClass := preload("res://scripts/ui/highlight_layer.gd")
const MapIOClass := preload("res://scripts/content/map_io.gd")
const MapGeneratorClass := preload("res://scripts/content/map_generator.gd")
const MapGenParamsClass := preload("res://scripts/content/map_gen_params.gd")

## 地图来源（M1a-T9）：FIXED = 手工固定测试图（默认，一键可玩）；RANDOM = 种子随机；
## PATTERN = 确定性公式图（T3/T4 几何对照）
enum MapSource { PATTERN, FIXED, RANDOM }

@export var map_source: MapSource = MapSource.FIXED
## 固定测试图路径（MapIO.FIXED_MAP_PATH；缺文件/损坏 → 显式报错不渲染）
@export var fixed_map_path := MapIOClass.FIXED_MAP_PATH
## RANDOM 来源参数（MapGenerator；同 seed 同参数逐格复现）
@export var random_seed := 7
@export var random_sea_level := 0.25
@export var random_elevation_levels := 4
@export var random_frequency := 0.05
## PATTERN/RANDOM 尺寸（FIXED 图自带 60×40）
@export var map_width := 60
@export var map_height := 40
@export var chunk_cols := 10
@export var chunk_rows := 10
@export var elevation_step := 1.0
## 材质槽表（M1a-T8）：检查器可直接指认任意 .tres 库——换库即换观感、零代码改动；
## 留空 = 载入主线默认色块库（TerrainMaterialLibrary.DEFAULT_PATH）。
@export var material_library: TerrainMaterialLibraryClass

## M1a-T7 高亮状态（hover 格状态 + 上次选中格；选择走 cell_selected 回执——M-1）
var _map: MapDataClass = null
var _hover_layer: HighlightLayerClass = null
var _selection_layer: HighlightLayerClass = null
var _hover_cell := Vector2i.ZERO
var _has_hover := false
var _prev_selected := Vector2i.ZERO
var _has_prev := false

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var map := _build_map()
	if map == null:
		return  # 来源构建失败已打印原因（显式失败，无静默兜底）
	_map = map
	# M1a-T8 材质槽：渲染管线走 .tres 映射表（检查器可换库；留空 = 主线默认色块库）
	if material_library == null:
		material_library = TerrainMaterialLibraryClass.load_default()
	if material_library == null:
		print("[M1a 沙盒] 材质库载入失败：", TerrainMaterialLibraryClass.DEFAULT_PATH,
			"（缺文件/类型不符——主线默认表不可缺，见 docs/notes/m1a-t8-art-branch.md）")
		return
	var missing: Array[int] = material_library.missing_ids(map)
	if not missing.is_empty():
		print("[M1a 沙盒] 材质表缺图内地形 id：", missing, "（补 terrain_materials_default.tres 槽位）")
		return
	var view: MapViewClass = MapViewClass.new()
	view.name = "MapView"
	add_child(view)
	var ok := view.build(map, chunk_cols, chunk_rows, material_library.materials, 1.0, elevation_step)
	var elapsed := Time.get_ticks_msec() - t0
	if not ok:
		print("[M1a 沙盒] 构建失败：材质表缺图内地形 id / 参数非法")
		return
	# M1a-T5 拾取挂接（目检载体）：左键/移动 → 物理回调内解析 → 格子
	var picker: MapPickerClass = MapPickerClass.new()
	picker.name = "MapPicker"
	view.add_child(picker)  # 地图根（MapView）之下：世界↔局部转换随根变换
	var pick_ok := picker.setup(view.build_info, map)
	picker.cell_picked.connect(_on_cell_picked)
	picker.cell_selected.connect(_on_cell_selected)
	picker.pick_missed.connect(_on_pick_missed)
	print(pick_ok if pick_ok else "[M1a 沙盒] 拾取挂接失败")
	# M1a-T7 高亮挂接（目检载体）：hover 层（暖黄单格）+ 选择层（蓝多格 + 橙路径）。
	# lift 档位：选择层 = 基准档（tier 0）、hover 层 = tier 1——跨层同格双扇面错开
	# 一档不共面；选择层描线带 = 本层 lift + 半档 extra（高于两层扇面且不与任何
	# 整档共面，见 hex_highlight.gd 头注「共面治理」——「不闪」的几何面）。
	var hover_lift := HexHighlight.lift_for_tier(1)
	_hover_layer = HighlightLayerClass.new()
	_hover_layer.name = "HoverHighlight"
	view.add_child(_hover_layer)
	_selection_layer = HighlightLayerClass.new()
	_selection_layer.name = "SelectionHighlight"
	view.add_child(_selection_layer)
	var hover_ok: bool = _hover_layer.setup(map, 1.0, elevation_step, 0.8,
		HexHighlight.DEFAULT_COLOR, HexHighlight.DEFAULT_PATH_COLOR, -1.0, hover_lift)
	var sel_ok: bool = _selection_layer.setup(map, 1.0, elevation_step, 0.8,
		Color(0.30, 0.55, 1.0, 0.40), Color(0.25, 0.75, 1.0, 1.0))
	if not hover_ok or not sel_ok:
		print("[M1a 沙盒] 高亮层挂接失败（空图？）")
	# M1a-T6 策略相机挂接（主创实操载体）：钳制域按本图建立，初始焦点 = 图中心
	var camera := get_node_or_null("StrategyCamera") as StrategyCameraClass
	if camera == null:
		print("[M1a 沙盒] 策略相机：场景缺 StrategyCamera 节点（检查 scenes/m1a_sandbox.tscn）")
	elif camera.setup(map, 1.0):
		print("[M1a 沙盒] 策略相机已挂接（M1a-T6）：滚轮=档位缩放 / 中键=拖拽 / 鼠标移至屏幕边缘=持续平移 / 焦点不出地图外沿")
	else:
		print("[M1a 沙盒] 策略相机挂接失败（空图？）")
	var chunks: Array = view.build_info["chunks"]
	var tris := 0
	var surfaces := 0
	for c in chunks:
		for s in c["surfaces"]:
			tris += s["index_count"] / 3
			surfaces += 1
	print("[M1a 沙盒] %d×%d 高程图：%d chunk / %d surface / %d 三角形 / 构建+挂载 %d ms"
		% [_map.width, _map.height, chunks.size(), surfaces, tris, elapsed])
	print("[M1a 沙盒] 地形分布：", _type_counts(map))
	print("[M1a 沙盒] 高程分布：", _elevation_counts(map))
	print("[M1a 沙盒] 连接分布：", _edge_class_counts(map))
	print("[M1a 沙盒] 材质库（M1a-T8）：%s（%d 槽）——检查器 material_library 可换 .tres 即换观感"
		% [material_library.resource_path if material_library.resource_path != "" else "（内存表）",
			material_library.materials.size()])
	print("[M1a 沙盒] 拾取已启用（M1a-T5）：移动=hover 高亮 / 左键=选择集合+路径描线（M1a-T7）")

## 按来源建图（M1a-T9）：失败打印原因并返回 null（_ready 显式短路，无静默兜底）
func _build_map() -> MapDataClass:
	match map_source:
		MapSource.FIXED:
			var map: MapDataClass = MapIOClass.read_map(fixed_map_path)
			if map == null:
				print("[M1a 沙盒] 固定测试图载入失败：", fixed_map_path,
					"（缺文件/损坏——重跑 tools/make_fixed_maps.gd 落盘）")
				return null
			print("[M1a 沙盒] 地图来源（M1a-T9 固定测试图）：", fixed_map_path,
				" digest=", map.digest())
			return map
		MapSource.RANDOM:
			var p := MapGenParamsClass.new()
			p.seed = random_seed
			p.width = map_width
			p.height = map_height
			p.sea_level = random_sea_level
			p.elevation_levels = random_elevation_levels
			p.frequency = random_frequency
			var result := MapGeneratorClass.generate(p)
			if not result["ok"]:
				print("[M1a 沙盒] 随机图生成失败：", result["error"])
				return null
			var conn: Dictionary = result["connectivity"]
			print("[M1a 沙盒] 地图来源（M1a-T9 随机图）：seed=", p.seed,
				" digest=", result["meta"]["digest"],
				" 连通=", conn["ok"])
			return result["map"]
		_:
			var pmap := MapDataClass.new(map_width, map_height)
			_fill_pattern(pmap)
			_fill_elevation(pmap)
			print("[M1a 沙盒] 地图来源：PATTERN 公式图（T3/T4 几何对照）")
			return pmap

## 目检地貌（确定性公式；水 3 正弦河 + 沙 4 岸 / 岩 2 / 林 5 / 泥 1 / 草 0 底）
func _fill_pattern(map) -> void:
	for cell in map.cells():
		var cr := Hex.offset_of(cell)
		var col := cr.x
		var row := cr.y
		var river := absf(float(col) - (18.0 + 8.0 * sin(float(row) * 0.22)))
		var terrain := 0
		if river < 1.7:
			terrain = 3
		elif river < 3.4:
			terrain = 4
		elif _dist2(col, row, 46, 11) < 52.0:
			terrain = 2
		elif _dist2(col, row, 13, 27) < 40.0:
			terrain = 5
		elif _dist2(col, row, 31, 33) < 26.0:
			terrain = 1
		map.set_terrain(cell, terrain)

## 目检高程（确定性公式，分区构造三档连接——是否成真以 _ready 打印的连接分布为准）：
##   · 缓波台地 2..4 层：相邻原始高差 < 1 → 量化后 |Δh| ∈ {0,1} = 等高平连 + ±1 斜坡；
##   · 正弦河谷（与 _fill_pattern 水系同线）：谷底 0 层 / 岸带 1 层，与台地 2..4 相接
##     → 沿河岸出现 |Δh| ≥ 2 的 Catlike 式陡连接面（微决策 1 的目检载体）。
func _fill_elevation(map) -> void:
	for cell in map.cells():
		var cr := Hex.offset_of(cell)
		var col := cr.x
		var row := cr.y
		var h := 3.0 + 1.1 * sin(float(col) * 0.23) * cos(float(row) * 0.19)
		var river := absf(float(col) - (18.0 + 8.0 * sin(float(row) * 0.22)))
		if river < 2.0:
			h = 0.0
		elif river < 3.2:
			h = 1.0
		map.set_elevation(cell, clampi(int(round(h)), 0, 5))

func _dist2(col: int, row: int, cx: int, cy: int) -> float:
	var dx := float(col - cx)
	var dy := float(row - cy)
	return dx * dx + dy * dy

## 拾取请求（M1a-T5/T7 目检）：只入队，物理回调内查询（map_picker.gd 纪律）。
## 鼠标移动 = hover 高亮更新；左键 = 选择请求（经物理回调解析后回 cell_selected——
## 点击格即选中格；M-1 修复 2026-10-10：不再读 motion 的陈旧 hover）。
func _unhandled_input(event: InputEvent) -> void:
	var picker := get_node_or_null("MapView/MapPicker")
	if picker == null:
		return
	if event is InputEventMouseMotion:
		picker.request_pick_at((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		picker.request_select_at((event as InputEventMouseButton).position)

## hover 更新（M1a-T7）：单格高亮切换走集合差异（同格重复 → 零操作不闪）。
func _on_cell_picked(cell: Vector2i) -> void:
	_hover_cell = cell
	_has_hover = true
	if _hover_layer != null:
		_hover_layer.highlight([cell])

## 左键选择回执（M-1 修复 2026-10-10）：点击请求解析到的格 = 选中格；
## 点空（miss）不改选择。
func _on_cell_selected(cell: Vector2i) -> void:
	_confirm_selection_at(cell)

func _on_pick_missed() -> void:
	_has_hover = false
	if _hover_layer != null:
		_hover_layer.clear()

## 左键选择（M1a-T7 目检）：目标格 + 界内 6 邻入选择层，从上次选中格描直线路径。
func _confirm_selection_at(cell: Vector2i) -> void:
	if _selection_layer == null:
		return
	var cells: Array = [cell]
	for nb in _map.neighbors_existing(cell):
		cells.append(nb)
	_selection_layer.highlight(cells)
	if _has_prev and _prev_selected != cell:
		_selection_layer.show_path(_line_cells(_prev_selected, cell))
	else:
		_selection_layer.clear_path()
	_prev_selected = cell
	_has_prev = true

## 演示用直线路径采样（格心连线 → cube rounding；真寻路 M1b-T4 落地后替换）。
func _line_cells(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	var wa := Hex.axial_to_world(a, 1.0)
	var wb := Hex.axial_to_world(b, 1.0)
	var steps := maxi(1, int(ceil((wb - wa).length() / 0.45)))
	var last := Vector2i(9999, 9999)
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := wa + (wb - wa) * t
		var c := Hex.world_to_axial(Vector3(p.x, 0.0, p.z), 1.0)
		if c != last:
			out.append(c)
			last = c
	return out

func _type_counts(map) -> Dictionary:
	var counts := {}
	for cell in map.cells():
		var t: int = map.terrain_at(cell)
		counts[t] = int(counts.get(t, 0)) + 1
	return counts

func _elevation_counts(map) -> Dictionary:
	var counts := {}
	for cell in map.cells():
		var h: int = map.elevation_at(cell)
		counts[h] = int(counts.get(h, 0)) + 1
	return counts

## 连接分类分布（headless 冒烟即可核对三档连接是否存在——「高差处连接符合设计示意」
## 目检项的数据支撑，不再只看高程值分布推断）。每条无向边数一次：方向 0/1/2 与
## 3/4/5 是同一条边的两个朝向（同 tests 的内部边 oracle 口径）。
func _edge_class_counts(map) -> Dictionary:
	var counts := {}
	for cell in map.cells():
		for d in 3:
			var nb := Hex.neighbor(cell, d)
			if map.has_cell(nb):
				var t := Builder.classify_edge(map.elevation_at(cell) - map.elevation_at(nb))
				counts[t] = int(counts.get(t, 0)) + 1
	return counts
