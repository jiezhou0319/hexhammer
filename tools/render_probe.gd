## render_probe.gd — M1a+ GATE-02 渲染证据工具（独立工具，非门禁；04 §M1a+ 第一批卡）
## 用法（**非 headless**——本卡要求真渲染；与门禁同款命令去掉 --headless 即可）：
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" \
##     --path C:/code/hexhammer --script res://tools/render_probe.gd
##   （跑真渲染帧，沿 picking_scene_check.gd / camera_scene_check.gd 的独立小场景先例：
##   探针跑若干帧后自行 quit(0/1)，退出码 0 = 全部可见性检查通过。）
## 定位与边界（卡 4/5 条）：
##   - 本工具**只加证据、不改任何渲染代码**——F-1 修复（2026-10-10 渲染索引翻为俯视
##     顺时针 = Godot 正面）的直接证据化：若绕序回归（索引三角俯视逆时针 = 背面），
##     默认 CULL_BACK 下俯视地形/高亮/描线全部 0 像素 → 本探针 FAIL（exit 1）上报，
##     不在本工具里修（那说明 F-1 修复有问题）；
##   - 探针**不进 headless 套件**（run_tests.gd 只收集 tests/test_*.gd，不感知本文件）。
## 校验项（卡 2 条：默认 CULL_BACK 下俯视可见像素数 > 阈值；俯视 = 相机正下直视）：
##   CHECK-1 地形顶面：与背景色相异的像素数 > 总像素 × TERRAIN_MIN_FRACTION；
##   CHECK-2 高亮扇面：HighlightLayer.highlight(7 格) 后与前一帧图的差分像素数 > HIGHLIGHT_MIN_PX；
##   CHECK-3 描线带：HighlightLayer.show_path(12 格直线) 后与前一帧图的差分像素数 > PATH_MIN_PX。
## 固定条件（GATE-02「给定旧固定图和规定相机」）：
##   - 图 = 沙盒同源 FIXED 手工固定图（resources/maps/fixed/playable_60x40.json，digest 入统计）；
##   - 相机 = 图包络中心正上方 y=CAM_HEIGHT 直视下（basis 显式：屏幕上 = 世界 −Z 北），
##     fov=70 / near=0.5 / far=600 与 scenes/m1a_sandbox.tscn 相机同参；
##   - 环境/太阳 = m1a_sandbox.tscn 数值的代码复刻（背景/环境光/日光转角能量阴影）；
##   - 地形 = MapView（view 层，沙盒同路径）→ Builder → 每 chunk MeshInstance3D；
##   - 窗口 = 1280×720（实际渲染尺寸以读回为准，写入统计与文件名——设备 DPI 差异不破坏证据）。
## 证据留档（卡 3 条）：docs/evidence/m1a/ 三张截图（terrain/highlight/path）+ 像素统计 txt，
##   文件名带渲染器/尺寸标识（如 render_probe_terrain_forwardplus_1280x720.png）；
##   统计注明 Forward+ 实测、其余渲染器（Compatibility/Mobile）未测。
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
	print("[渲染探针] init（deferred 启动，等待主循环；非 headless = Forward+ 真渲染）")
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

	# ---- 规定相机（数值写死并进统计——「规定相机」的可复现口径）----
	## 相机高度（世界单位；图上方直视下。60×40/size=1 图包络约 105×61，
	## 64 高度下 y=4 顶面视野 ≈ 84×149（fov70/16:9），上下左右余量 ≥38%）
	const CAM_HEIGHT := 64.0
	const CAM_FOV := 70.0
	const CAM_NEAR := 0.5
	const CAM_FAR := 600.0

	# ---- 阈值（实测首报后按余量 ≥3× 定档；见统计 txt 实测值）----
	## 地形可见像素下限 = 帧总像素 × 15%（整图入画预期 ~50%）
	const TERRAIN_MIN_FRACTION := 0.15
	## 高亮扇面（7 格内顶面扇形，实测见统计）像素下限
	const HIGHLIGHT_MIN_PX := 300
	## 描线带（12 格直线、宽 0.18）像素下限
	const PATH_MIN_PX := 80

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
	var _layer: HighlightLayerClass = null
	var _cam: Camera3D = null

	func _ready() -> void:
		_arm_watchdog()
		var err := _build_scene()
		if err != "":
			_fail("场景构建失败：%s" % err)
			return
		_run()

	# ---------------- 场景（沙盒同源：FIXED 图 + 沙盒环境/相机参数复刻）----------------

	func _build_scene() -> String:
		_map = MapIOClass.read_map(MapIOClass.FIXED_MAP_PATH)
		if _map == null:
			return "固定图载入失败 %s（重跑 tools/make_fixed_maps.gd 落盘？）" % MapIOClass.FIXED_MAP_PATH
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
		if not view.build(_map, 10, 10, lib.materials, 1.0, 1.0):
			return "地形构建失败（材质缺槽/参数非法）"
		# 规定相机：图包络中心正上方直视下（屏幕上 = 世界 −Z 北；basis 显式免 look_at 依赖）
		var bounds: Rect2 = HexCameraLib.map_focus_bounds(_map, 1.0)
		var c := bounds.get_center()
		_cam = Camera3D.new()
		_cam.name = "ProbeCamera"
		_cam.fov = CAM_FOV
		_cam.near = CAM_NEAR
		_cam.far = CAM_FAR
		_cam.current = true
		add_child(_cam)
		_cam.global_transform = Transform3D(
			Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
			Vector3(c.x, CAM_HEIGHT, c.y))
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
		var hl_cells: Array = [Hex.axial_of(HIGHLIGHT_COL_ROW)]
		for d in 6:
			hl_cells.append(Hex.neighbor(Hex.axial_of(HIGHLIGHT_COL_ROW), d))
		_layer.highlight(hl_cells)
		await _frames(SETTLE_LAYER_FRAMES)
		var img_hl: Image = await _capture()
		if img_hl == null:
			return
		var hl_r := _count_diff(img_hl, img_terrain)
		var highlight_px: int = hl_r["count"]
		# ---- CHECK-3 描线带（差分 vs 高亮帧）----
		var path_cells: Array = []
		for col in range(PATH_COL_FROM, PATH_COL_TO + 1):
			path_cells.append(Hex.axial_of(Vector2i(col, PATH_ROW)))
		_layer.show_path(path_cells)
		await _frames(SETTLE_LAYER_FRAMES)
		var img_path: Image = await _capture()
		if img_path == null:
			return
		var path_r := _count_diff(img_path, img_hl)
		var path_px: int = path_r["count"]

		# ---- 判定 ----
		var ok1 := terrain_px > terrain_min
		var ok2 := highlight_px > HIGHLIGHT_MIN_PX
		var ok3 := path_px > PATH_MIN_PX
		var pct := 100.0 * float(terrain_px) / float(maxi(total, 1))
		_print_check(ok1, "CHECK-1 地形顶面：俯视可见 px=%d/%d（%.1f%%），阈值=%d（%.0f%%）"
			% [terrain_px, total, pct, terrain_min, TERRAIN_MIN_FRACTION * 100.0])
		_print_check(ok2, "CHECK-2 高亮扇面（7 格）：差分可见 px=%d，阈值=%d，变化区 bbox=%s"
			% [highlight_px, HIGHLIGHT_MIN_PX, str(hl_r["bbox"])])
		_print_check(ok3, "CHECK-3 描线带（12 格直线）：差分可见 px=%d，阈值=%d，变化区 bbox=%s"
			% [path_px, PATH_MIN_PX, str(path_r["bbox"])])

		# ---- 留档（截图 + 统计 txt；写入失败按 FAIL——证据是本卡交付物）----
		var saved := _save_evidence(img_terrain, img_hl, img_path, {
			"total": total, "terrain_px": terrain_px, "terrain_min": terrain_min,
			"terrain_pct": pct, "highlight_px": highlight_px, "path_px": path_px,
			"ok": [ok1, ok2, ok3], "bg": bg, "hl_bbox": hl_r["bbox"], "path_bbox": path_r["bbox"]})
		if saved == "":
			_fail("证据文件写入失败（见上方输出）")
			return
		print("[渲染探针] 证据已留档：%s" % saved)
		var all_ok := ok1 and ok2 and ok3
		if all_ok:
			print("PROBE OK — 3/3 可见性检查通过（F-1 修复在 Forward+ 俯视下成立：默认 CULL_BACK 全可见）")
		else:
			print("PROBE FAIL — 可见性回归：CULL_BACK 下俯视有图层像素不足阈值（F-1 修复存疑，须上报）")
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

	## 三张截图 + 统计 txt 落 docs/evidence/m1a/（文件名带渲染器/尺寸标识）；
	## 返回统计文件 res:// 路径，失败返回 ""（原因已打印）。
	func _save_evidence(img_terrain: Image, img_hl: Image, img_path: Image, r: Dictionary) -> String:
		var renderer := String(ProjectSettings.get_setting_with_override(
			"rendering/renderer/rendering_method"))
		var tag := "%s_%dx%d" % [renderer.replace("_", ""), img_terrain.get_width(), img_terrain.get_height()]
		var dir_abs := ProjectSettings.globalize_path(EVIDENCE_DIR)
		var mk := DirAccess.make_dir_recursive_absolute(dir_abs)
		if mk != OK:
			print("[渲染探针] FAIL 证据目录创建失败：%s（%d）" % [EVIDENCE_DIR, mk])
			return ""
		var shots := [
			["terrain", img_terrain], ["highlight", img_hl], ["path", img_path]]
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
		f.store_string(_stats_text(renderer, tag, shot_paths, r))
		f.close()
		return stats_path

	## 统计文本（构建/设备/尺寸/像素统计——GATE-02 卡面要求的留档字段）
	func _stats_text(renderer: String, tag: String, shot_paths: Array, r: Dictionary) -> String:
		var ver: Dictionary = Engine.get_version_info()
		var oks: Array = r["ok"]
		var L: Array[String] = []
		L.append("Hexhammer M1a+ GATE-02 渲染探针 · 像素统计（04 §M1a+ 第一批卡；方案「T0 与 T1 的第一批任务卡」）")
		L.append("时间(UTC)：%s" % Time.get_datetime_string_from_system(true))
		L.append("引擎：Godot %s" % String(ver.get("string", "?")))
		L.append("渲染器：%s（Forward+ 本机实测；Compatibility / Mobile 未测）" % renderer)
		L.append("设备：adapter=%s vendor=%s；OS=%s %s；DisplayServer=%s" % [
			RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
			OS.get_name(), OS.get_version(), DisplayServer.get_name()])
		L.append("图像尺寸：%d×%d（窗口请求 %d×%d，读回为准）" % [
			_cam.get_viewport().get_visible_rect().size.x,
			_cam.get_viewport().get_visible_rect().size.y,
			WINDOW_SIZE.x, WINDOW_SIZE.y])
		L.append("图（沙盒同源 FIXED）：%s digest=%s（%d×%d）" % [
			MapIOClass.FIXED_MAP_PATH, _map.digest(), _map.width, _map.height])
		L.append("相机（规定）：图包络中心正上方直视下 pos=%s fov=%.0f near=%.1f far=%.0f（屏幕上=世界−Z 北；Transform basis x=(1,0,0) y=(0,0,-1) z=(0,1,0)）" % [
			str(_cam.global_position), CAM_FOV, CAM_NEAR, CAM_FAR])
		L.append("环境/光照：m1a_sandbox.tscn 数值复刻（背景 0.16/0.17/0.2；环境光 0.55/0.57/0.62×0.9；太阳转角 −52/−32 能量 1.2 阴影开）")
		L.append("材质剔除：默认 CULL_BACK（地形 = StandardMaterial3D 默认；高亮/描线 = hex_highlight.gd 显式 CULL_BACK）")
		L.append("判定容差：单通道 8 位差 > %d；背景色 = 截图四角采样（%s）" % [
			CHANNEL_TOL, str(r["bg"].to_html(false))])
		L.append("")
		L.append("CHECK-1 地形顶面：俯视可见 px=%d / %d（%.1f%%），阈值=%d（帧像素 %.0f%%）→ %s" % [
			r["terrain_px"], r["total"], r["terrain_pct"], r["terrain_min"],
			TERRAIN_MIN_FRACTION * 100.0, "PASS" if oks[0] else "FAIL"])
		L.append("CHECK-2 高亮扇面（7 格 = 中心+6 邻，offset %s）：差分可见 px=%d，阈值=%d，变化区 bbox=%s → %s" % [
			str(HIGHLIGHT_COL_ROW), r["highlight_px"], HIGHLIGHT_MIN_PX, str(r["hl_bbox"]),
			"PASS" if oks[1] else "FAIL"])
		L.append("CHECK-3 描线带（12 格直线，offset 行 %d 列 %d..%d）：差分可见 px=%d，阈值=%d，变化区 bbox=%s → %s" % [
			PATH_ROW, PATH_COL_FROM, PATH_COL_TO, r["path_px"], PATH_MIN_PX, str(r["path_bbox"]),
			"PASS" if oks[2] else "FAIL"])
		L.append("")
		L.append("F-1 语义：默认 CULL_BACK 下俯视三图层可见像素均超阈值 = 渲染索引俯视顺时针（Godot 正面）仍成立；")
		L.append("若任一为 0/不足 = 可见性回归（F-1 修复存疑，须上报，不在本工具内修）。")
		L.append("口径：Forward+ 实测（如上）；其余渲染器未测（Compatibility / Mobile）。")
		L.append("截图（同目录）：%s" % "、".join(shot_paths))
		L.append("标识：%s" % tag)
		if oks[0] and oks[1] and oks[2]:
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
