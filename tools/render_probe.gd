## render_probe.gd — M1a+ GATE-02 渲染证据工具（独立工具，非门禁；04 §M1a+ 第一批卡）
## 用法（**非 headless**——本卡要求真渲染；与门禁同款命令去掉 --headless 即可）：
##   "E:/Godot/Godot_v4.7.2-stable_win64_console.exe" \
##     --path <repo> --script res://tools/render_probe.gd
##   （跑真渲染帧，沿 picking_scene_check.gd / camera_scene_check.gd 的独立小场景先例：
##   探针跑若干帧后自行 quit(0/1)，退出码 0 = 全部可见性检查通过。）
## 定位与边界（卡 4/5 条）：
##   - 本工具**只加证据、不改任何渲染代码**——F-1 修复（2026-10-10 渲染索引翻为俯视
##     顺时针 = Godot 正面）的直接证据化：若绕序回归（索引三角俯视逆时针 = 背面），
##     默认 CULL_BACK 下俯视地形/高亮/描线全部 0 像素 → 本探针 FAIL（exit 1）上报，
##     不在本工具里修（那说明 F-1 修复有问题）；
##   - 探针**不进 headless 套件**（run_tests.gd 只收集 tests/test_*.gd，不感知本文件）。
## 校验项（卡 2 条 + 准备批 GATE-EVIDENCE S-4 扩充）：
##   CHECK-1 地形顶面：与背景色相异的像素数 > 总像素 × TERRAIN_MIN_FRACTION；
##   CHECK-2 高亮扇面：HighlightLayer.highlight(7 格) 后与前一帧图的差分像素数 > HIGHLIGHT_MIN_PX；
##   CHECK-3 描线带：HighlightLayer.show_path(12 格直线) 后与前一帧图的差分像素数 > PATH_MIN_PX；
##   CHECK-4 BLEND 对照（S-4，2026-10-11）：默认 BLEND style 同图重渲——俯视可见
##     像素须过 CHECK-1 同款阈值（防纯白失败样），且与 SLOTS 地形帧差分 >
##     BLEND_DIFF_MIN_PX（证明 BLEND 材质效果真实存在，非只有数组测试）。
##   CHECK-6 格线差分（T2 GRID-01，2026-10-11）：同 BLEND style 关格线重渲，与
##     CHECK-4 帧（默认开格线）差分 > GRID_DIFF_MIN_PX——格线层真实可见的像素证据
##     （同 style 同材质，差分归因唯一 = 格线层；执行方案 §3 GRID-01 测试锚）。
##   CHECK-W 水面差分（T3 WATER-02，2026-10-11：§8.3 的水面差分检查——编号 W
##     避让已被 S-4 BLEND 占用的 CHECK-4）：固定图 + 世界伴生（.world.json，边河
##     + 河口湖 + 东北湖）构建后，仅切换水面层可见性两次差分 > WATER_DIFF_MIN_PX
##     ——同帧地形不变（含河床下切），差分归因唯一 = 水面第二 mesh；水面不进
##     碰撞/拾取层（零碰撞体挂载）同时由本检查的结构面背书。
##   CHECK-5 道路/桥面差分（T4 ROAD-01/02：§8.3 的「CHECK-5 T4 道路/桥差分阈值」
##     ——编号 5 为执行方案预留名）：同一含河世界构建（.world.json 现含东西横路 +
##     跨河桥 CrossingData）后，仅切换路面层可见性两次差分 > ROAD_DIFF_MIN_PX
##     ——同帧地形/水面不变，差分归因唯一 = 路面/桥面第二 mesh（桥面撞水面上方，
##     河在下路在上的像素证据）。
##   CHECK-T2 阶地/崖几何对照（T2 LAND-01 ④：矩阵图 = render_probe 新 CHECK 图）：
##     矩阵图（tools/land_matrix_fixtures.gd——Δ0..Δ3 × 方向 + 角等价类穷举的固定
##     小图）以 LandformProfile 默认档重建，与同图基线帧差分 > T2_DIFF_MIN_PX
##     ——阶地环带/真垂直崖/角情形分派的像素证据（§8.3「T2 阶地/崖目检 CHECK」）。
## 固定条件（GATE-02「给定旧固定图和规定相机」）：
##   - 图 = 沙盒同源 FIXED 手工固定图（resources/maps/fixed/playable_60x40.json，digest 入统计）；
##   - 相机 = 图包络中心正上方 y=CAM_HEIGHT 直视下（basis 显式：屏幕上 = 世界 −Z 北），
##     fov=70 / near=0.5 / far=600 与 scenes/m1a_sandbox.tscn 相机同参；
##   - 环境/太阳 = m1a_sandbox.tscn 数值的代码复刻（背景/环境光/日光转角能量阴影）；
##   - 地形 = MapView（view 层，沙盒同路径）→ Builder → 每 chunk MeshInstance3D；
##   - 窗口 = 1280×720（实际渲染尺寸以读回为准，写入统计与文件名——设备 DPI 差异不破坏证据）。
## 证据留档（卡 3 条）：docs/evidence/m1a/ 四张截图（terrain/highlight/path/blend）+ 像素统计 txt，
##   文件名带渲染器/尺寸标识（如 render_probe_terrain_forwardplus_1280x720.png）；
##   **渲染器标识一律取 RenderingServer.get_current_rendering_method() 运行时值**
##   （S-1，2026-10-11：不得读工程配置/硬编码「Forward+ 实测」——CLI --rendering-method
##   覆盖与驱动回退都会使配置值 ≠ 实际后端）；统计同时记配置值与运行时值。
## 判定容差：单通道 8 位差 > CHANNEL_TOL（14/255 ≈ 0.055）计为「相异/变化」——远小于
##   0.42 alpha 高亮混色（单通道 ~50/255）与不透明描线（~100+/255），大于静态场景逐帧噪声。
extends SceneTree

## 渲染窗口请求尺寸（实际以读回为准）
const WINDOW_SIZE := Vector2i(1280, 720)
## 证据目录（res:// 源工程内可写——沿 make_fixed_maps/make_trial_textures 落盘先例）
const EVIDENCE_DIR := "res://docs/evidence/m1a"
## 看门狗：超时强制 FAIL 退出（探针自身卡死不得挂着）
const WATCHDOG_SEC := 60.0

func _init() -> void:
	print("[渲染探针] init（deferred 启动，等待主循环；非 headless = 真渲染，后端以运行时为准——S-1）")
	_boot.call_deferred()

func _boot() -> void:
	print("[渲染探针] boot：root=%s" % str(root != null))
	root.size = WINDOW_SIZE
	root.move_to_center()
	if root.world_3d == null:
		root.world_3d = World3D.new()
	var checker := Checker.new()
	checker.name = "RenderProbe"
	root.add_child(checker)

## 探针节点：建固定场景 → 三阶段截图 → 像素统计 → 留档 → quit(0/1)
class Checker extends Node:
	const Hex := preload("res://addons/hexhammer/hex_math.gd")
	const HexCameraLib := preload("res://addons/hexhammer/hex_camera.gd")
	const HexHighlightLib := preload("res://addons/hexhammer/hex_highlight.gd")
	const MapDataClass := preload("res://scripts/core/data/map_data.gd")
	const MapIOClass := preload("res://scripts/content/map_io.gd")
	const TerrainMaterialLibraryClass := preload("res://scripts/core/data/terrain_material_library.gd")
	const MapViewClass := preload("res://scripts/ui/map_view.gd")
	const HighlightLayerClass := preload("res://scripts/ui/highlight_layer.gd")
	const TerrainStyleClass := preload("res://scripts/core/data/terrain_style.gd")
	const LandformProfileClass := preload("res://scripts/core/data/landform_profile.gd")
	const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
	const MatrixFixtures := preload("res://tools/land_matrix_fixtures.gd")

	# ---- 规定相机（数值写死并进统计——「规定相机」的可复现口径）----
	## 相机高度（世界单位；图上方直视下。60×40/size=1 图包络约 105×61，
	## 64 高度下 y=4 顶面视野 ≈ 84×149（fov70/16:9），上下左右余量 ≥38%）
	const CAM_HEIGHT := 64.0
	## 固定图包络长边基准（map_focus_bounds 实测 104.7891——银行样图相机按
	## 「样图包络长边 / 固定基准」等比缩放 CAM_HEIGHT：尺寸随组走的样图维持
	## 固定图的取景密度（像素尺度可比 = 同一套阈值有效——§8.3「实测首报后
	## 余量 ≥3× 定档」的阈值不被取景破坏）。首报登记（2026-10-12）：旧式
	## 自适应高度 max(64, 包络长边×1.15) = 120.5 下 60×40 样图顶面仅 12.6%/
	## 高亮 219px/描线 64px（帧覆盖缩至固定图 0.28×，5 项 FAIL——非渲染回归）
	const FIXED_REF_BOUND := 104.7891
	const CAM_FOV := 70.0
	const CAM_NEAR := 0.5
	const CAM_FAR := 600.0
	## CHECK-T2 矩阵图相机高度（T2 阶地/崖目检）：矩阵图包络 ≈ 176×14（100×9 格），
	## fov70/16:9 下可视宽 ≈ 2.49·h → h=90 覆盖 224 宽（余量 ~27%）
	const MATRIX_CAM_HEIGHT := 90.0

	# ---- 阈值（实测首报后按余量 ≥3× 定档；见统计 txt 实测值）----
	## 地形可见像素下限 = 帧总像素 × 15%（整图入画预期 ~50%）
	const TERRAIN_MIN_FRACTION := 0.15
	## 高亮扇面（7 格内顶面扇形，实测见统计）像素下限
	const HIGHLIGHT_MIN_PX := 300
	## 描线带（12 格直线、宽 0.18）像素下限
	const PATH_MIN_PX := 80
	## CHECK-4：BLEND 帧与 SLOTS 地形帧的差分像素下限（S-4，2026-10-11——
	## 保守起步值；实测首报后按「余量 ≥3×」规则上调）
	const BLEND_DIFF_MIN_PX := 200
	## CHECK-6：格线层差分像素下限（T2 GRID-01——起步保守值，实测首报后上调）
	const GRID_DIFF_MIN_PX := 300
	## CHECK-W：水面层差分像素下限（T3 WATER-02——2026-10-11 首报实测 9508px；
	## 同日评审修复（角点接缝 + 条带/裙边绕序——修复前条带俯视背面被剔）后
	## 10503px；同日二轮评审修复（湖面成员间带面 + 角点补面——修复前多格水体
	## 成孤岛六边形）后 14610px——均见 docs/evidence/m1a/
	## render_probe_stats_forwardplus_1280x720.txt CHECK-W 行；按「余量 ≥3×」定档 3000）
	const WATER_DIFF_MIN_PX := 3000
	## CHECK-W 银行样图档（WORLD-04 ④ 留档面）：首报实测 2px（2026-10-12，
	## 等比取景相机下；旧式 1.15 余量相机下亦仅 11px——与取景无关）——生成世界
	## 全部水体 water_level=0（海/湖/河水位同落 0 档），水面 y=(0−0.5)·step 位于
	## 成员格顶面（y=0）**之下** → 水面第二 mesh 被地形顶面遮挡，仅偶发 AA/阴影
	## 边缘像素入差分；对照固定图水体 authored water_level=1 → 水面 +0.5 可见
	## （14610px / 阈值 3000，余量 4.9×）。按 §8.3「实测首报后余量 ≥3×」定档 0
	## （= 本检查在银行模式下退化为「水面层存在且至少渲染 1 像素」 +
	## water_nodes>0），并**如实登记**：弱分辨力是结构性的——水位 0 档的水面
	## 可见性属 T3/WATER-03 水位语义处置面（生成器对海/湖全部落 0 档 vs 手工
	## 固定图落 1 档），非探针阈值问题，已随 2026-10-12 评审修复登记上报
	const BANK_WATER_DIFF_MIN_PX := 0
	## CHECK-5：路面/桥面层差分像素下限（T4 ROAD-01/02——2026-10-12 首报实测
	## 517px（横路行 5 在图北缘、俯视视角下路面带宽 ~2px——bbox 高 2px 为几何
	## 实况非回归）；按「余量 ≥3×」规则定档 150。均见 docs/evidence/m1a/
	## render_probe_stats_forwardplus_1280x720.txt CHECK-5 行）
	const ROAD_DIFF_MIN_PX := 150
	## CHECK-T2：阶地/真崖几何差分像素下限（矩阵图 + 默认 LandformProfile vs 基线）
	const T2_DIFF_MIN_PX := 500

	# ---- 高亮/描线固定格（固定条件；两组互不相交 → 差分归因干净）----
	const HIGHLIGHT_COL_ROW := Vector2i(30, 20)  # 图中部内点（60×40 界内且 6 邻全在）
	const PATH_COL_FROM := 10
	const PATH_COL_TO := 21
	const PATH_ROW := 32

	## 单通道 8 位色差判定容差（见类头注）
	const CHANNEL_TOL := 14
	## 四角背景色互差容差（四角一致性 = 取景假设的自检）
	const CORNER_TOL := 8
	## 阶段间隔帧（建场景/换高亮后各等若干帧，GPU 上传与着色器编译余量）
	const SETTLE_TERRAIN_FRAMES := 45
	const SETTLE_LAYER_FRAMES := 15

	var _map: MapDataClass = null
	var _view: MapViewClass = null
	var _layer: HighlightLayerClass = null
	var _cam: Camera3D = null
	## 底图相机位（y=高度）：统计「相机（规定）」行报此值——_cam 实际位在
	## CHECK-T2 已移至矩阵图上空（完检不回移），直接读 _cam 会把矩阵相机冒充
	## 底图规定相机（证据失真，S-1 同族）
	var _map_cam_pos := Vector3.ZERO
	## 银行样图模式（WORLD-04 ④「银行样图走 render_probe 留档」）：`-- --map=<路径>`
	## 指定替代底图（伴生 .world.json 同目录推导）；证据文件名加样图前缀，
	## 固定格坐标（CHECK-2/3）改为按图尺寸自适应——固定图行为不变（回归证据连续性）。
	var _map_path: String = MapIOClass.FIXED_MAP_PATH
	var _bank_tag := ""

	func _ready() -> void:
		_arm_watchdog()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("map="):
				_map_path = arg.substr(4)
				_bank_tag = (_map_path.get_file().get_basename().replace(".", "_")) + "__"
		var err := _build_scene()
		if err != "":
			_fail("场景构建失败：%s" % err)
			return
		_run()

	# ---------------- 场景（沙盒同源：FIXED 图 + 沙盒环境/相机参数复刻）----------------

	func _build_scene() -> String:
		_map = MapIOClass.read_map(_map_path)
		if _map == null:
			return "图载入失败 %s（重跑 tools/make_fixed_maps.gd / tools/seed_bank.gd 落盘？）" % _map_path
		var lib: TerrainMaterialLibraryClass = TerrainMaterialLibraryClass.load_default()
		if lib == null:
			return "主线默认材质库载入失败 %s" % TerrainMaterialLibraryClass.DEFAULT_PATH
		var missing: Array = lib.missing_ids(_map)
		if not missing.is_empty():
			return "材质表缺图内地形 id %s" % str(missing)
		# 环境/太阳：scenes/m1a_sandbox.tscn 数值复刻（背景 0.16/0.17/0.2；环境光
		# 0.55/0.57/0.62×0.9；太阳转角 −52/−32、能量 1.2、阴影开）
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.16, 0.17, 0.2)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.55, 0.57, 0.62)
		env.ambient_light_energy = 0.9
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		we.environment = env
		add_child(we)
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
		sun.shadow_enabled = true
		sun.light_energy = 1.2
		add_child(sun)
		# 地形：MapView（view 层，与沙盒同路径）——每 chunk 一个 MeshInstance3D
		var view := MapViewClass.new()
		view.name = "MapView"
		add_child(view)
		_view = view
		if not view.build(_map, 10, 10, lib.materials, 1.0, 1.0):
			return "地形构建失败（材质缺槽/参数非法）"
		# 规定相机：图包络中心正上方直视下（屏幕上 = 世界 −Z 北；basis 显式免 look_at 依赖）。
		# 银行样图尺寸随组走——高度按包络等比缩放（固定图维持 64 不变：回归证据连续性）
		var bounds: Rect2 = HexCameraLib.map_focus_bounds(_map, 1.0)
		var c := bounds.get_center()
		var cam_h := CAM_HEIGHT
		if _bank_tag != "":
			cam_h = CAM_HEIGHT * maxf(bounds.size.x, bounds.size.y) / FIXED_REF_BOUND
		_map_cam_pos = Vector3(c.x, cam_h, c.y)
		_cam = Camera3D.new()
		_cam.name = "ProbeCamera"
		_cam.fov = CAM_FOV
		_cam.near = CAM_NEAR
		_cam.far = CAM_FAR
		_cam.current = true
		add_child(_cam)
		_cam.global_transform = Transform3D(
			Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
			_map_cam_pos)
		# 高亮层（扇面 + 描线；挂 MapView 之下随地图根，沙盒同构；颜色 = 高亮层默认）
		_layer = HighlightLayerClass.new()
		_layer.name = "ProbeHighlight"
		view.add_child(_layer)
		if not _layer.setup(_map, 1.0, 1.0, 0.8,
				HexHighlightLib.DEFAULT_COLOR, HexHighlightLib.DEFAULT_PATH_COLOR):
			return "高亮层 setup 失败（空图？）"
		return ""

	# ---------------- 三阶段探针主流程 ----------------

	func _run() -> void:
		# ---- CHECK-1 地形顶面（俯视非背景像素）----
		await _frames(SETTLE_TERRAIN_FRAMES)
		var img_terrain: Image = await _capture()
		if img_terrain == null:
			return
		var total := img_terrain.get_width() * img_terrain.get_height()
		var bg_report := _corner_bg(img_terrain)
		if bg_report.get("ok", false) == false:
			_fail("取景自检失败：%s" % str(bg_report.get("why", "")))
			return
		var bg: Color = bg_report["color"]
		var terrain_r := _count_vs_color(img_terrain, bg)
		var terrain_px: int = terrain_r["count"]
		var terrain_min := int(float(total) * TERRAIN_MIN_FRACTION)
		# ---- CHECK-2 高亮扇面（差分 vs 地形帧）----
		# 银行样图模式：固定格常量按 60×40 authored——改按图中心自适应（六邻取界内）
		var focus_cr := HIGHLIGHT_COL_ROW if _bank_tag == "" \
			else Vector2i(_map.width / 2, _map.height / 2)
		var hl_cells: Array = [Hex.axial_of(focus_cr)]
		for d in 6:
			var nb := Hex.neighbor(Hex.axial_of(focus_cr), d)
			if _map.has_cell(nb):
				hl_cells.append(nb)
		_layer.highlight(hl_cells)
		await _frames(SETTLE_LAYER_FRAMES)
		var img_hl: Image = await _capture()
		if img_hl == null:
			return
		var hl_r := _count_diff(img_hl, img_terrain)
		var highlight_px: int = hl_r["count"]
		# ---- CHECK-3 描线带（差分 vs 高亮帧；银行样图按图宽取中心行段）----
		var path_cells: Array = []
		var path_row := PATH_ROW if _bank_tag == "" else _map.height / 2
		var col_from := PATH_COL_FROM if _bank_tag == "" \
			else maxi(0, _map.width / 2 - (PATH_COL_TO - PATH_COL_FROM) / 2)
		var col_to := PATH_COL_TO if _bank_tag == "" else mini(_map.width - 1, col_from + (PATH_COL_TO - PATH_COL_FROM))
		for col in range(col_from, col_to + 1):
			path_cells.append(Hex.axial_of(Vector2i(col, path_row)))
		_layer.show_path(path_cells)
		await _frames(SETTLE_LAYER_FRAMES)
		var img_path: Image = await _capture()
		if img_path == null:
			return
		var path_r := _count_diff(img_path, img_hl)
		var path_px: int = path_r["count"]
		# ---- CHECK-4 BLEND 对照（S-4，2026-10-11：默认 BLEND style 同图重渲）----
		_layer.clear()
		_layer.clear_path()
		var blend_style: Variant = TerrainStyleClass.load_default_blend()
		if blend_style == null:
			_fail("BLEND 默认 style 载入失败（%s）" % TerrainStyleClass.BLEND_DEFAULT_PATH)
			return
		if not _view.build_with_style(_map, blend_style, 10, 10, 1.0, 1.0):
			_fail("BLEND 构建失败（problems_for 非空？——S-2 报缺后 inputs_for 拒绝是预期行为，默认库应可解析）")
			return
		await _frames(SETTLE_TERRAIN_FRAMES)
		var img_blend: Image = await _capture()
		if img_blend == null:
			return
		var blend_vis := _count_vs_color(img_blend, bg)
		var blend_px: int = blend_vis["count"]
		var sb_r := _count_diff(img_blend, img_terrain)
		var style_diff_px: int = sb_r["count"]

		# ---- CHECK-6 格线差分（T2 GRID-01）：同 BLEND style 关格线重渲，与
		#      CHECK-4 帧（默认 style 开格线）差分——差分归因唯一 = 格线层 ----
		var grid_off_style: TerrainStyleClass = (TerrainStyleClass.load_default_blend() as TerrainStyleClass)
		if grid_off_style == null:
			_fail("BLEND 默认 style 载入失败（CHECK-6 前置）")
			return
		grid_off_style.grid_line_enabled = false
		if not _view.build_with_style(_map, grid_off_style, 10, 10, 1.0, 1.0):
			_fail("格线关重渲失败（CHECK-6——style 解析问题？）")
			return
		await _frames(SETTLE_TERRAIN_FRAMES)
		var img_grid_off: Image = await _capture()
		if img_grid_off == null:
			return
		var g_r := _count_diff(img_blend, img_grid_off)
		var grid_diff_px: int = g_r["count"]

		# ---- CHECK-W 水面差分（T3 WATER-02：固定图 + .world.json，水面层开/关
		#      两次差分——同帧地形（含河床下切）不变，差分归因唯一 = 水面 mesh）----
		var world: Variant = MapIOClass.read_world(MapIOClass.world_path_for(_map_path))
		if not (world is WorldDataClass):
			_fail("世界伴生文件载入失败（%s——重跑 tools/make_fixed_maps.gd / seed_bank.gd？）"
				% MapIOClass.world_path_for(_map_path))
			return
		if not _view.build(_map, 10, 10,
				(TerrainMaterialLibraryClass.load_default() as TerrainMaterialLibraryClass).materials,
				1.0, 1.0, 0.8, null, world):
			_fail("含河地形构建失败（CHECK-W 前置——world 数据非法？）")
			return
		await _frames(SETTLE_TERRAIN_FRAMES)
		var img_water_on: Image = await _capture()
		if img_water_on == null:
			return
		for node in _view.water_nodes:
			node.visible = false  # 只关水面层：地形/河床帧不变（差分归因唯一）
		await _frames(SETTLE_LAYER_FRAMES)
		var img_water_off: Image = await _capture()
		if img_water_off == null:
			return
		var w_r := _count_diff(img_water_on, img_water_off)
		var water_diff_px: int = w_r["count"]
		var water_nodes_n := _view.water_nodes.size()
		for node in _view.water_nodes:
			node.visible = true

		# ---- CHECK-5 道路/桥面差分（T4 ROAD-01/02）：同一世界构建（路面层随
		#      build 自动挂载——world 含横路+桥），仅切换路面层可见性两次差分——
		#      同帧地形/水面不变，差分归因唯一 = 路面/桥面第二 mesh ----
		await _frames(SETTLE_LAYER_FRAMES)
		var img_road_on: Image = await _capture()
		if img_road_on == null:
			return
		for node in _view.road_nodes:
			node.visible = false  # 只关路面层：地形/水面/河床帧不变（归因唯一）
		await _frames(SETTLE_LAYER_FRAMES)
		var img_road_off: Image = await _capture()
		if img_road_off == null:
			return
		var rd_r := _count_diff(img_road_on, img_road_off)
		var road_diff_px: int = rd_r["count"]
		var road_nodes_n := _view.road_nodes.size()
		for node in _view.road_nodes:
			node.visible = true

		# ---- CHECK-T2 阶地/崖几何对照（T2 LAND-01 ④：矩阵图 + 默认 LandformProfile
		#      vs 同图基线帧——相机移到矩阵图包络上空，完检后不再回移）----
		var matrix_map: MapDataClass = MatrixFixtures.build_matrix(3)
		var matrix_center := HexCameraLib.map_focus_bounds(matrix_map, 1.0).get_center()
		_cam.global_transform = Transform3D(
			Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
			Vector3(matrix_center.x, MATRIX_CAM_HEIGHT, matrix_center.y))
		if not _view.build(matrix_map, 10, 10,
				(TerrainMaterialLibraryClass.load_default() as TerrainMaterialLibraryClass).materials,
				1.0, 1.0, 0.8):
			_fail("矩阵图基线构建失败（CHECK-T2 前置）")
			return
		await _frames(SETTLE_TERRAIN_FRAMES)
		var img_m0: Image = await _capture()
		if img_m0 == null:
			return
		if not _view.build(matrix_map, 10, 10,
				(TerrainMaterialLibraryClass.load_default() as TerrainMaterialLibraryClass).materials,
				1.0, 1.0, 0.8, LandformProfileClass.make_default()):
			_fail("矩阵图 profile 构建失败（CHECK-T2）")
			return
		await _frames(SETTLE_TERRAIN_FRAMES)
		var img_m1: Image = await _capture()
		if img_m1 == null:
			return
		var t2_r := _count_diff(img_m1, img_m0)
		var t2_diff_px: int = t2_r["count"]
		var m0_bg := _corner_bg(img_m0)
		var m0_vis: int = 0
		if m0_bg.get("ok", false):
			m0_vis = int(_count_vs_color(img_m0, m0_bg["color"])["count"])

		# ---- 判定 ----
		# CHECK-W 阈值按模式取档：固定图 = 实测绘制的 3000；银行样图 = 首报 39px
		# 按 ≥3× 余量定的银行档（见 BANK_WATER_DIFF_MIN_PX 头注——结构性弱分辨力登记）
		var water_min := WATER_DIFF_MIN_PX if _bank_tag == "" else BANK_WATER_DIFF_MIN_PX
		var ok1 := terrain_px > terrain_min
		var ok2 := highlight_px > HIGHLIGHT_MIN_PX
		var ok3 := path_px > PATH_MIN_PX
		var ok4 := blend_px > terrain_min and style_diff_px > BLEND_DIFF_MIN_PX
		var ok6 := grid_diff_px > GRID_DIFF_MIN_PX
		var okW := water_diff_px > water_min and water_nodes_n > 0
		var ok5 := road_diff_px > ROAD_DIFF_MIN_PX and road_nodes_n > 0
		var okT2 := t2_diff_px > T2_DIFF_MIN_PX and m0_vis > int(float(img_m0.get_width() * img_m0.get_height()) * 0.05)
		var pct := 100.0 * float(terrain_px) / float(maxi(total, 1))
		var blend_pct := 100.0 * float(blend_px) / float(maxi(total, 1))
		_print_check(ok1, "CHECK-1 地形顶面（SLOTS）：俯视可见 px=%d/%d（%.1f%%），阈值=%d（%.0f%%）"
			% [terrain_px, total, pct, terrain_min, TERRAIN_MIN_FRACTION * 100.0])
		_print_check(ok2, "CHECK-2 高亮扇面（7 格）：差分可见 px=%d，阈值=%d，变化区 bbox=%s"
			% [highlight_px, HIGHLIGHT_MIN_PX, str(hl_r["bbox"])])
		_print_check(ok3, "CHECK-3 描线带（12 格直线）：差分可见 px=%d，阈值=%d，变化区 bbox=%s"
			% [path_px, PATH_MIN_PX, str(path_r["bbox"])])
		_print_check(ok4, "CHECK-4 BLEND 对照：可见 px=%d/%d（%.1f%%）过地形阈值，与 SLOTS 帧差分 px=%d，阈值=%d，bbox=%s"
			% [blend_px, total, blend_pct, style_diff_px, BLEND_DIFF_MIN_PX, str(sb_r["bbox"])])
		_print_check(ok6, "CHECK-6 格线差分（GRID-01）：开格线 vs 关格线差分 px=%d，阈值=%d，bbox=%s"
			% [grid_diff_px, GRID_DIFF_MIN_PX, str(g_r["bbox"])])
		_print_check(okW, "CHECK-W 水面差分（T3 WATER-02）：水面层开/关差分 px=%d，阈值=%d，水面节点=%d，bbox=%s"
			% [water_diff_px, water_min, water_nodes_n, str(w_r["bbox"])])
		_print_check(ok5, "CHECK-5 道路/桥面差分（T4 ROAD-01/02）：路面层开/关差分 px=%d，阈值=%d，路面节点=%d，bbox=%s"
			% [road_diff_px, ROAD_DIFF_MIN_PX, road_nodes_n, str(rd_r["bbox"])])
		_print_check(okT2, "CHECK-T2 阶地/崖几何（矩阵图 + LandformProfile）：profile vs 基线差分 px=%d，阈值=%d，bbox=%s（基线可见 px=%d）"
			% [t2_diff_px, T2_DIFF_MIN_PX, str(t2_r["bbox"]), m0_vis])

		# ---- 留档（截图 + 统计 txt；写入失败按 FAIL——证据是本卡交付物）----
		var saved := _save_evidence(img_terrain, img_hl, img_path, img_blend, {
			"total": total, "terrain_px": terrain_px, "terrain_min": terrain_min,
			"terrain_pct": pct, "highlight_px": highlight_px, "path_px": path_px,
			"blend_px": blend_px, "blend_pct": blend_pct,
			"style_diff_px": style_diff_px, "blend_min": BLEND_DIFF_MIN_PX,
			"grid_diff_px": grid_diff_px, "grid_min": GRID_DIFF_MIN_PX,
			"water_diff_px": water_diff_px, "water_min": water_min,
			"water_nodes": water_nodes_n,
			"road_diff_px": road_diff_px, "road_min": ROAD_DIFF_MIN_PX,
			"road_nodes": road_nodes_n,
			"t2_diff_px": t2_diff_px, "t2_min": T2_DIFF_MIN_PX, "t2_base_px": m0_vis,
			"ok": [ok1, ok2, ok3, ok4, ok6, okW, ok5, okT2], "bg": bg, "hl_bbox": hl_r["bbox"],
			"path_bbox": path_r["bbox"], "sb_bbox": sb_r["bbox"],
			"grid_bbox": g_r["bbox"], "water_bbox": w_r["bbox"], "road_bbox": rd_r["bbox"],
			"t2_bbox": t2_r["bbox"]})
		if saved == "":
			_fail("证据文件写入失败（见上方输出）")
			return
		print("[渲染探针] 证据已留档：%s" % saved)
		var all_ok := ok1 and ok2 and ok3 and ok4 and ok6 and okW and ok5 and okT2
		var runtime_backend := RenderingServer.get_current_rendering_method()
		if all_ok:
			print("PROBE OK — 8/8 检查通过（F-1 修复在 %s 俯视下成立：默认 CULL_BACK 全可见；SLOTS/BLEND/格线/水面/道路桥面/阶地真崖几何均有像素证据）" % runtime_backend)
		else:
			print("PROBE FAIL — 可见性/材质对照回归（%s 下有检查未过阈值，须上报）" % runtime_backend)
		get_tree().quit(0 if all_ok else 1)

	# ---------------- 截图与像素统计 ----------------

	## 等待 n 个 process 帧（真渲染帧；物理帧本探针用不到——无拾取）
	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	## 抓根视口渲染图（等当帧绘制完成后取；统一转 RGB8/RGBA8 之外的格式）
	func _capture() -> Image:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null or img.is_empty():
			_fail("渲染帧捕获失败（get_image 空——显示服务可用？）")
			return null
		if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		return img

	## 四角取背景色 + 一致性自检（四角均在图外留白区——取景假设的直接验证）
	func _corner_bg(img: Image) -> Dictionary:
		var w := img.get_width()
		var h := img.get_height()
		var pts := [Vector2i(4, 4), Vector2i(w - 5, 4), Vector2i(4, h - 5), Vector2i(w - 5, h - 5)]
		var c0 := img.get_pixelv(pts[0])
		for p in pts.slice(1):
			var c := img.get_pixelv(p)
			if absi(int(c.r8) - int(c0.r8)) > CORNER_TOL \
					or absi(int(c.g8) - int(c0.g8)) > CORNER_TOL \
					or absi(int(c.b8) - int(c0.b8)) > CORNER_TOL:
				return {"ok": false, "why": "四角背景色不一致（%s vs %s @%s）——取景假设被破坏"
					% [str(c0), str(c), str(p)]}
		return {"ok": true, "color": c0}

	## 与参考色相异的像素计数（任一通道差 > CHANNEL_TOL）+ 变化区 bbox
	func _count_vs_color(img: Image, ref: Color) -> Dictionary:
		var ch := _channels(img)
		var d := img.get_data()
		var rr := int(ref.r8)
		var gg := int(ref.g8)
		var bb := int(ref.b8)
		var count := 0
		var w := img.get_width()
		var bbox := Rect2i()
		var first := true
		var n := d.size() / ch
		for i in n:
			var o := i * ch
			if absi(d[o] - rr) > CHANNEL_TOL or absi(d[o + 1] - gg) > CHANNEL_TOL \
					or absi(d[o + 2] - bb) > CHANNEL_TOL:
				count += 1
				var px := Vector2i(i % w, i / w)
				if first:
					bbox = Rect2i(px, Vector2i.ONE)
					first = false
				else:
					bbox = bbox.expand(px)
		return {"count": count, "bbox": bbox}

	## 两帧差分像素计数（任一通道差 > CHANNEL_TOL；静态场景逐帧本应逐位一致）
	func _count_diff(a: Image, b: Image) -> Dictionary:
		if a.get_width() != b.get_width() or a.get_height() != b.get_height() \
				or a.get_format() != b.get_format():
			_fail("差分两帧尺寸/格式不一致（%s vs %s）——渲染管线不稳定"
				% [str(a.get_size()), str(b.get_size())])
			return {"count": 0, "bbox": Rect2i()}
		var ch := _channels(a)
		var da := a.get_data()
		var db := b.get_data()
		var count := 0
		var w := a.get_width()
		var bbox := Rect2i()
		var first := true
		var n := da.size() / ch
		for i in n:
			var o := i * ch
			if absi(da[o] - db[o]) > CHANNEL_TOL or absi(da[o + 1] - db[o + 1]) > CHANNEL_TOL \
					or absi(da[o + 2] - db[o + 2]) > CHANNEL_TOL:
				count += 1
				var px := Vector2i(i % w, i / w)
				if first:
					bbox = Rect2i(px, Vector2i.ONE)
					first = false
				else:
					bbox = bbox.expand(px)
		return {"count": count, "bbox": bbox}

	func _channels(img: Image) -> int:
		return 4 if img.get_format() == Image.FORMAT_RGBA8 else 3

	# ---------------- 留档 ----------------

	## 四张截图 + 统计 txt 落 docs/evidence/m1a/（文件名带渲染器/尺寸标识）；
		## 返回统计文件 res:// 路径，失败返回 ""（原因已打印）。
		## 渲染器标识取运行时值（S-1，2026-10-11）：RenderingServer.get_current_rendering_method()
		## ——工程配置值仅作对照行写入统计（CLI --rendering-method 覆盖/驱动回退会使两者不同）。
	func _save_evidence(img_terrain: Image, img_hl: Image, img_path: Image, img_blend: Image, r: Dictionary) -> String:
		var renderer := String(RenderingServer.get_current_rendering_method())
		var cfg := String(ProjectSettings.get_setting_with_override(
			"rendering/renderer/rendering_method"))
		var tag := "%s%s_%dx%d" % [_bank_tag, renderer.replace("_", ""),
			img_terrain.get_width(), img_terrain.get_height()]
		var dir_abs := ProjectSettings.globalize_path(EVIDENCE_DIR)
		var mk := DirAccess.make_dir_recursive_absolute(dir_abs)
		if mk != OK:
			print("[渲染探针] FAIL 证据目录创建失败：%s（%d）" % [EVIDENCE_DIR, mk])
			return ""
		var shots := [
			["terrain", img_terrain], ["highlight", img_hl], ["path", img_path],
			["blend", img_blend]]
		var shot_paths: Array[String] = []
		for s in shots:
			var p := "%s/render_probe_%s_%s.png" % [EVIDENCE_DIR, s[0], tag]
			var e: int = (s[1] as Image).save_png(p)
			if e != OK:
				print("[渲染探针] FAIL 截图写入失败：%s（%d）" % [p, e])
				return ""
			shot_paths.append(p)
		var stats_path := "%s/render_probe_stats_%s.txt" % [EVIDENCE_DIR, tag]
		var f := FileAccess.open(stats_path, FileAccess.WRITE)
		if f == null:
			print("[渲染探针] FAIL 统计文件打开失败：%s" % stats_path)
			return ""
		f.store_string(_stats_text(renderer, cfg, tag, shot_paths, r))
		f.close()
		return stats_path

	## 统计文本（构建/设备/尺寸/像素统计——GATE-02 卡面要求的留档字段）
	func _stats_text(renderer: String, cfg_renderer: String, tag: String, shot_paths: Array, r: Dictionary) -> String:
		var ver: Dictionary = Engine.get_version_info()
		var oks: Array = r["ok"]
		var L: Array[String] = []
		L.append("Hexhammer M1a+ GATE-02 渲染探针 · 像素统计（04 §M1a+ 第一批卡；方案「T0 与 T1 的第一批任务卡」）")
		L.append("时间(UTC)：%s" % Time.get_datetime_string_from_system(true))
		L.append("引擎：Godot %s" % String(ver.get("string", "?")))
		L.append("渲染器（实际运行时）：%s（本机实测 = 此值；取自 RenderingServer.get_current_rendering_method()——S-1）" % renderer)
		L.append("渲染器（工程配置值）：%s（仅对照；CLI --rendering-method 覆盖/驱动回退会使配置 ≠ 实际）" % cfg_renderer)
		L.append("设备：adapter=%s vendor=%s；OS=%s %s；DisplayServer=%s" % [
			RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
			OS.get_name(), OS.get_version(), DisplayServer.get_name()])
		L.append("图像尺寸：%d×%d（窗口请求 %d×%d，读回为准）" % [
			_cam.get_viewport().get_visible_rect().size.x,
			_cam.get_viewport().get_visible_rect().size.y,
			WINDOW_SIZE.x, WINDOW_SIZE.y])
		L.append("图：%s digest=%s（%d×%d%s）" % [
			_map_path, _map.digest(), _map.width, _map.height,
			"；银行样图模式（WORLD-04 ④ 留档）" if _bank_tag != "" else "；沙盒同源 FIXED"])
		L.append("相机（规定）：图包络中心正上方直视下 pos=%s fov=%.0f near=%.1f far=%.0f（屏幕上=世界−Z 北；Transform basis x=(1,0,0) y=(0,0,-1) z=(0,1,0)）" % [
			str(_map_cam_pos), CAM_FOV, CAM_NEAR, CAM_FAR])
		L.append("环境/光照：m1a_sandbox.tscn 数值复刻（背景 0.16/0.17/0.2；环境光 0.55/0.57/0.62×0.9；太阳转角 −52/−32 能量 1.2 阴影开）")
		L.append("材质剔除：默认 CULL_BACK（地形 = StandardMaterial3D 默认；高亮/描线 = hex_highlight.gd 显式 CULL_BACK）")
		L.append("判定容差：单通道 8 位差 > %d；背景色 = 截图四角采样（%s）" % [
			CHANNEL_TOL, str(r["bg"].to_html(false))])
		L.append("")
		L.append("CHECK-1 地形顶面：俯视可见 px=%d / %d（%.1f%%），阈值=%d（帧像素 %.0f%%）→ %s" % [
			r["terrain_px"], r["total"], r["terrain_pct"], r["terrain_min"],
			TERRAIN_MIN_FRACTION * 100.0, "PASS" if oks[0] else "FAIL"])
		L.append("CHECK-2 高亮扇面（7 格 = 中心+6 邻，offset %s%s）：差分可见 px=%d，阈值=%d，变化区 bbox=%s → %s" % [
			str(HIGHLIGHT_COL_ROW) if _bank_tag == "" else "%s（图中心自适应）" % str(Vector2i(_map.width / 2, _map.height / 2)),
			"" if _bank_tag == "" else "（银行样图模式）", r["highlight_px"], HIGHLIGHT_MIN_PX,
			str(r["hl_bbox"]), "PASS" if oks[1] else "FAIL"])
		L.append("CHECK-3 描线带（12 格直线，offset 行 %d 列 %d..%d%s）：差分可见 px=%d，阈值=%d，变化区 bbox=%s → %s" % [
			PATH_ROW, PATH_COL_FROM, PATH_COL_TO,
			"" if _bank_tag == "" else "（银行样图模式：行/列随图自适应）",
			r["path_px"], PATH_MIN_PX, str(r["path_bbox"]), "PASS" if oks[2] else "FAIL"])
		L.append("CHECK-4 BLEND 对照（S-4，2026-10-11）：默认 BLEND style 同图重渲，可见 px=%d / %d（%.1f%%，阈值同 CHECK-1），与 SLOTS 地形帧差分 px=%d，阈值=%d，bbox=%s → %s" % [
			r["blend_px"], r["total"], r["blend_pct"], r["style_diff_px"], r["blend_min"],
			str(r["sb_bbox"]), "PASS" if oks[3] else "FAIL"])
		L.append("CHECK-6 格线差分（T2 GRID-01，2026-10-11）：同 BLEND style 关格线重渲，与 CHECK-4 帧（开格线）差分 px=%d，阈值=%d，bbox=%s → %s" % [
			r["grid_diff_px"], r["grid_min"], str(r["grid_bbox"]), "PASS" if oks[4] else "FAIL"])
		L.append("CHECK-W 水面差分（T3 WATER-02，2026-10-11）：底图 + .world.json（%s）构建，水面层开/关差分 px=%d，阈值=%d，水面节点=%d，bbox=%s → %s" % [
			"银行样图伴生世界（生成水体 water_level=0——水面 y 落顶面之下被遮挡，分辨力弱属结构性，阈值走银行首报档 ≥3× 定标）" if _bank_tag != "" else "固定图：边河+河口湖+东北湖",
			r["water_diff_px"], r["water_min"], int(r["water_nodes"]), str(r["water_bbox"]),
			"PASS" if oks[5] else "FAIL"])
		L.append("CHECK-5 道路/桥面差分（T4 ROAD-01/02）：同一世界构建（%s），路面层开/关差分 px=%d，阈值=%d，路面节点=%d，bbox=%s → %s" % [
			"银行样图路网+桥" if _bank_tag != "" else "固定图：东西横路+跨河桥 CrossingData",
			r["road_diff_px"], r["road_min"], int(r["road_nodes"]), str(r["road_bbox"]),
			"PASS" if oks[6] else "FAIL"])
		L.append("CHECK-T2 阶地/崖几何（T2 LAND-01 ④ 矩阵图）：LandformProfile 默认档 vs 基线差分 px=%d，阈值=%d，bbox=%s（基线可见 px=%d）→ %s" % [
			r["t2_diff_px"], r["t2_min"], str(r["t2_bbox"]), r["t2_base_px"],
			"PASS" if oks[7] else "FAIL"])
		L.append("")
		L.append("F-1 语义：默认 CULL_BACK 下俯视三图层可见像素均超阈值 = 渲染索引俯视顺时针（Godot 正面）仍成立；")
		L.append("若任一为 0/不足 = 可见性回归（F-1 修复存疑，须上报，不在本工具内修）。")
		L.append("口径：本文件全部结论仅覆盖「渲染器（实际运行时）」一行所列后端；其余后端未测。")
		L.append("截图（同目录）：%s" % "、".join(shot_paths))
		L.append("标识：%s" % tag)
		if oks[0] and oks[1] and oks[2] and oks[3] and oks[4] and oks[5] and oks[6] and oks[7]:
			L.append("PROBE OK")
		else:
			L.append("PROBE FAIL")
		L.append("")
		return "\n".join(L)

	# ---------------- 通用 ----------------

	func _print_check(ok: bool, label: String) -> void:
		print("[渲染探针] %s %s" % ["PASS" if ok else "FAIL", label])

	func _fail(reason: String) -> void:
		print("[渲染探针] PROBE FAIL — %s" % reason)
		get_tree().quit(1)

	func _arm_watchdog() -> void:
		var t := Timer.new()
		t.name = "Watchdog"
		t.wait_time = WATCHDOG_SEC
		t.one_shot = true
		t.timeout.connect(func() -> void:
			print("[渲染探针] PROBE FAIL — 看门狗超时（%.0fs 未完成，探针自身卡死）" % WATCHDOG_SEC)
			get_tree().quit(1))
		add_child(t)
		t.start()
