## terrain_debug_views.gd — 地形调试预览与灰度对照工具（T6 S2「调试预览」前置 harness；
##   docs/M1a-terrain-T6-stylized-execution-plan.md §4——**先于生成器改动落地**：
##   验收 harness 先行，S3 分区骨架起每阶段的证据通道，沿 render_probe「只加证据
##   不改渲染代码」纪律；提案（docs/evidence/风格化地图生成方案_群山平原与派系适配_
##   修订版.md）§实施分期 P0「调试预览」（:236）与「固定对照」（:237）的工具面）
## 用法（**非 headless**——真渲染需短暂弹窗，沿 tools/render_probe.gd 先例；与门禁
##   同款命令去掉 --headless）：
##   "E:/Godot/Godot_v4.7.2-stable_win64_console.exe" --path hexhammer \
##     --script res://tools/terrain_debug_views.gd -- map=res://resources/maps/bank/default_terraces_60x40_sample.json
##   ... -- seeds=7,42 template=default_terraces width=60 height=40 \
##         views=height,slope,passability out=res://docs/evidence/t6
## 参数表（key=value，`--` 之后；沿 tools/generate_map.gd CLI 先例）：
##   map=<res://路径.json>   银行样图/固定图模式（MapIO.read_map + .world.json
##                           伴生自动读取——region/skeleton 视图的数据源）
##   seeds=<int[,int…]>      即时生成模式 seed 清单（批量 = 逐 seed 全套渲染；与 map 互斥）
##   template=<名>           生成模板（default_terraces 双噪声 / regions_mountains
##                           T6 S3 分区骨架路线——S3 落地扩）
##   width=<int> height=<int> 尺寸覆盖（默认模板自带 60×40）
##   views=<csv|all>         视图清单（默认 height,slope,passability；region/
##                           skeleton 已随 S3 实做——无区域数据时显式报「无数据」
##                           不产图、不计失败）
##   out=<dir>               输出目录（默认 res://docs/evidence/t6——m1a evidence 先例）
## 渲染口径（提案「固定对照」的可复现面）：
##   - 相机（规定）：正交俯视**数据面**——图包络（map_focus_bounds）中心正上方直视下，
##     basis 显式 x=(1,0,0) y=(0,0,-1) z=(0,1,0)（屏幕上 = 世界 −Z 北，与 render_probe
##     规定相机同 basis）；正交 size = 包络按视口纵横比放行 + 8% 边距（无透视畸变——
##     不同尺寸图的取景规则同一，跨版本（旧版/分区骨架版/+侵蚀版）帧帧可比）；
##   - 窗口统一 1280×720（读回为准入文件名与统计——设备 DPI 差异不破坏证据）；
##   - 数据面 = 每格整六边形（HexMath.vertex_xz 外顶点，相邻格边恰共点——无缝平面）
##     按视图值着顶点色；材质 UNSHADED + 顶点色 albedo（灰度值 = 数据本身，不受光照
##     影响）；绕序沿 hex_terrain_builder F-1 双层口径：raw 顶点序俯视逆时针、渲染索引
##     翻 (base, base+2, base+1) 俯视顺时针 = Godot 正面（默认 CULL_BACK 下俯视可见）；
##   - 背景 = 深蓝黑（灰度数据 r=g=b 恒不撞色；四角一致性自检沿 render_probe）。
## 视图数据派生 = tools/terrain_view_data.gd（纯逻辑件，tests/test_terrain_view_data.gd
##   逐行为锚定）：高度灰度 / 坡度 / 可用通行连通片（MapConnectivity 口径分级着色）
##   三种实做 + region/skeleton 挂点。
## 像素自检（沿 render_probe 差分/像素证据先例；**本工具是证据 harness 非门禁**——
##   不进 headless 套件，run_tests.gd 只收集 tests/test_*.gd 不感知本文件）：
##   CHECK-A 四角背景色一致性（取景假设自检）；CHECK-B 每视图非背景像素占比 >
##   取景期望填充 × 0.6（纵横比自适应，见 NONBG_SLACK 头注）；CHECK-C 实做视图
##   两两差分 > VIEW_DIFF_MIN_PX（各视图真实独立派生，非同图重复落盘）。
##   全过 → quit(0)，任一失败 → quit(1)。
## 基线留档（提案 :237 三路对照的「旧版」基准）：银行样图跑本工具即产出双噪声现役
##   路线的参照帧——S3/S4 落地后以同参数（同 seed/模板 + 同相机口径）重渲对照。
## 渲染器标识一律取 RenderingServer.get_current_rendering_method() 运行时值（S-1 口径），
##   写入统计与文件名；工程配置值仅作对照行。
## 退出码：用法/参数错误、图载入/生成失败、渲染或自检失败 → 1；全部通过 → 0。
extends SceneTree

## 渲染窗口请求尺寸（实际以读回为准——统一尺寸口径）
const WINDOW_SIZE := Vector2i(1280, 720)
## 证据目录（res:// 源工程内可写——render_probe 落盘先例；T6 批次独立子目录）
const EVIDENCE_DIR := "res://docs/evidence/t6"
## 看门狗：超时强制 FAIL 退出（批量 seed 模式生成耗时上限余量——探针不得挂死）
const WATCHDOG_SEC := 300.0

func _init() -> void:
	print("[调试视图] init（deferred 启动；非 headless = 真渲染，后端以运行时为准——S-1 口径）")
	_boot.call_deferred()

func _boot() -> void:
	print("[调试视图] boot：root=%s" % str(root != null))
	root.size = WINDOW_SIZE
	root.move_to_center()
	if root.world_3d == null:
		root.world_3d = World3D.new()
	var runner := Runner.new()
	runner.name = "TerrainDebugViews"
	root.add_child(runner)

## 渲染节点：解析参数 → 建作业清单（样图/即时生成）→ 逐图逐视图渲染 + 像素自检 →
## 留档 → quit(0/1)
class Runner extends Node:
	const Hex := preload("res://addons/hexhammer/hex_math.gd")
	const HexCameraLib := preload("res://addons/hexhammer/hex_camera.gd")
	const MapDataClass := preload("res://scripts/core/data/map_data.gd")
	const MapIOClass := preload("res://scripts/content/map_io.gd")
	const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")
	const WorldTemplateClass := preload("res://scripts/core/data/world_template.gd")
	const WorldPipelineClass := preload("res://scripts/content/world_pipeline.gd")
	const TerrainViewDataClass := preload("res://tools/terrain_view_data.gd")

	# ---- 规定相机（数值写死并进统计——「固定对照」的可复现口径）----
	## 正交边距（包络外留白比例：六边形数据面占帧约 ~83%，余量充足且四角留白可采样）
	const CAM_MARGIN := 0.08
	## 相机高度（正交下不影响取景，只须落在 near/far 之间——数据面 y=0）
	const CAM_Y := 100.0
	const CAM_NEAR := 0.5
	const CAM_FAR := 1000.0

	# ---- 像素自检阈值 ----
	## 非背景下限 = 取景期望填充 × 0.6（**纵横比自适应**：期望填充 = min/max(图包络、
	## 视口二者的纵横比) ÷ (1+边距)²——极端狭长图（如 100×10）合法填充可低至 ~15%，
	## 平档阈值会误报；0.6 松弛 = 六边形与 AABB 角差 + 外缘锯齿余量。首报实测
	## 2026-10-13：24×16 银行样图期望 83.5%、实测 80.1% → 阈值 50.1%，余量 1.6×）
	const NONBG_SLACK := 0.6
	## 实做视图两两差分像素下限（防同图重复落盘/派生退化为同值；首报实测
	## 682872~734769px——阈值保守起步，本检查是防呆不是分辨力）
	const VIEW_DIFF_MIN_PX := 500

	## 判定容差（render_probe 同款：单通道 8 位差 > 14 计相异；四角互差 > 8 判取景破坏）
	const CHANNEL_TOL := 14
	const CORNER_TOL := 8
	## 阶段间隔帧（首帧建场景多等——GPU 上传与着色器编译余量，render_probe 同思路）
	const SETTLE_FIRST_FRAMES := 30
	const SETTLE_VIEW_FRAMES := 15

	## 背景 = 深蓝黑（r=g=b 的灰度数据与蓝分量差 ≥ 41/255——slope=0/水格 0 档纯黑
	## 数据格也与背景可分辨，图幅范围恒可读）
	const BG_COLOR := Color(0.02, 0.05, 0.16)

	var _cam: Camera3D = null
	var _mesh_node: MeshInstance3D = null
	var _material: StandardMaterial3D = null

	func _ready() -> void:
		_arm_watchdog()
		var cli := _parse_args(OS.get_cmdline_user_args())
		if cli.is_empty():
			return  # 用法错误已打印，_parse_args 内 quit(1)
		_run_jobs(cli)

	# ---------------- 参数 ----------------

	## key=value 用户参数 → {map, seeds, template, width, height, views, out}；
	## 未知键/值非法/模式互斥 → 打印用法并 quit(1)（返回空 dict 供 _ready 短路）。
	func _parse_args(args: PackedStringArray) -> Dictionary:
		var cli := {"map": "", "seeds": [] as Array, "template": "default_terraces",
			"width": -1, "height": -1, "views": [] as Array, "out": EVIDENCE_DIR}
		for arg in args:
			var kv := arg.split("=", true, 1)
			if kv.size() != 2:
				_usage("参数须为 key=value 形式：%s" % arg)
				return {}
			var key := String(kv[0])
			var value := String(kv[1])
			match key:
				"map":
					cli["map"] = value
				"seeds":
					var seeds: Array = cli["seeds"]
					for s in value.split(","):
						var t := String(s).strip_edges()
						if not t.is_valid_int():
							_usage("seeds 须为逗号分隔整数清单：%s" % value)
							return {}
						seeds.append(int(t))
				"template":
					if value != "default_terraces" and value != "regions_mountains":
						_usage("template 现支持 default_terraces（双噪声）与 regions_mountains"
							+ "（T6 S3 分区骨架路线）：%s" % value)
						return {}
					cli["template"] = value
				"width":
					if not value.is_valid_int() or int(value) <= 0:
						_usage("width 须为 ≥1 整数：%s" % value)
						return {}
					cli["width"] = int(value)
				"height":
					if not value.is_valid_int() or int(value) <= 0:
						_usage("height 须为 ≥1 整数：%s" % value)
						return {}
					cli["height"] = int(value)
				"views":
					var views: Array = cli["views"]
					if value == "all":
						views.assign(TerrainViewDataClass.VIEW_ORDER)
					else:
						for v in value.split(","):
							var name_ := String(v).strip_edges()
							if not TerrainViewDataClass.VIEW_ORDER.has(name_):
								_usage("未知视图 %s（可选：%s 或 all）"
									% [name_, ", ".join(TerrainViewDataClass.VIEW_ORDER)])
								return {}
							if not views.has(name_):
								views.append(name_)
				"out":
					cli["out"] = value
				_:
					_usage("未知参数 %s" % key)
					return {}
		var seeds: Array = cli["seeds"]
		if String(cli["map"]) == "" and seeds.is_empty():
			_usage("须指定 map=<图路径>（银行样图/固定图）或 seeds=<清单>（即时生成）——二选一")
			return {}
		if String(cli["map"]) != "" and not seeds.is_empty():
			_usage("map= 与 seeds= 互斥（单进程单模式；批量走 seeds= 逗号清单）")
			return {}
		var views: Array = cli["views"]
		if views.is_empty():
			views.assign(TerrainViewDataClass.IMPLEMENTED_VIEWS)  # 默认三实做视图
		return cli

	func _usage(reason: String) -> void:
		print("[调试视图] !!! ", reason)
		print("用法：godot --path hexhammer --script res://tools/terrain_debug_views.gd -- "
			+ "map=res://resources/maps/bank/default_terraces_60x40_sample.json "
			+ "views=height,slope,passability out=res://docs/evidence/t6")
		print("  或：... -- seeds=7,42 template=regions_mountains width=60 height=40（即时生成批量）")
		print("  views 可选：%s（region/skeleton 随 S3 实做——无区域数据时显式报无数据）或 all"
			% ", ".join(TerrainViewDataClass.VIEW_ORDER))
		get_tree().quit(1)

	# ---------------- 作业编排 ----------------

	func _run_jobs(cli: Dictionary) -> void:
		var jobs: Array = []
		if String(cli["map"]) != "":
			var map := MapIOClass.read_map(String(cli["map"]))
			if map == null:
				_fail("图载入失败：%s（重跑 tools/seed_bank.gd 落盘样图？）" % cli["map"])
				return
			# 世界伴生文件（region/skeleton 视图数据源；缺失 = 旧图合法空——
			# WorldData.empty()，两视图走「无区域数据」显式态）
			var world := MapIOClass.read_world(MapIOClass.world_path_for(String(cli["map"])))
			jobs.append({
				"tag": _tag_of_map_path(String(cli["map"])),
				"map": map,
				"world": world,
				"source": "银行样图/固定图：%s" % cli["map"],
			})
		else:
			var seeds: Array = cli["seeds"]
			var template := _template_of(String(cli["template"]),
				int(cli["width"]), int(cli["height"]))
			if template == null:
				_fail("模板构建失败（width/height 越界？——WorldTemplate.validate 拒绝）")
				return
			for seed_value in seeds:
				var r := WorldPipelineClass.generate_validated(template, int(seed_value))
				if not r["ok"]:
					# 生成失败 = 作业失败（具名错误上报），不中断其余 seed——批量语义
					print("[调试视图] FAIL seed=%d 即时生成失败：%s" % [int(seed_value), str(r["error"])])
					continue
				var map: MapDataClass = r["map"]
				jobs.append({
					"tag": "gen_%s_%dx%d_seed%d" % [cli["template"], template.width,
						template.height, int(seed_value)],
					"map": map,
					"world": r["world"],
					"source": "即时生成：template=%s seed=%d（GENERATOR_VERSION=%d）"
						% [cli["template"], int(seed_value), WorldPipelineClass.GENERATOR_VERSION],
				})
		if jobs.is_empty():
			_fail("零作业（生成全部失败？——见上方 FAIL 行）")
			return
		var all_ok := true
		for job in jobs:
			var ok := await _run_job(job, cli)
			all_ok = all_ok and ok
		if all_ok:
			print("[调试视图] VIEWS OK — %d 张图全部视图渲染与像素自检通过（证据见 %s）"
				% [jobs.size(), String(cli["out"])])
		else:
			print("[调试视图] VIEWS FAIL — 有视图未过自检（见上方 FAIL 行，须上报）")
		get_tree().quit(0 if all_ok else 1)

	## 样图路径 → 文件名标签（render_probe _bank_tag 同法，去尾缀分隔）
	func _tag_of_map_path(path: String) -> String:
		return path.get_file().get_basename().replace(".", "_")

	## 模板构建（seed_bank._template_of 同法：代码默认 + 尺寸覆盖——.tres 同源锚在
	## tests；regions_mountains = make_regions 代码默认（terrain_route=regions），
	## T6 S3 分区骨架路线的即时生成入口）
	func _template_of(template_id: String, width: int, height: int) -> WorldTemplateClass:
		var t := WorldTemplateClass.new() if template_id == "default_terraces" 				else WorldTemplateClass.make_regions()
		t.template_id = template_id
		if width > 0:
			t.width = width
		if height > 0:
			t.height = height
		if t.validate() != "":
			return null
		return t

	# ---------------- 单图渲染 + 自检 + 留档 ----------------

	## 返回 true = 本图全部实做视图过自检且证据落盘成功
	func _run_job(job: Dictionary, cli: Dictionary) -> bool:
		var map: MapDataClass = job["map"]
		if map.cell_count() == 0:
			print("[调试视图] FAIL 空图（0 格）：%s" % job["source"])
			return false
		var cam_spec := _build_scene(map)
		# CHECK-B 阈值 = 取景期望填充 × 松弛（纵横比自适应——见 NONBG_SLACK 头注）
		var bounds: Rect2 = cam_spec["bounds"]
		var map_a := bounds.size.x / maxf(bounds.size.y, 0.001)
		var vp_a: float = cam_spec["aspect"]
		var fill_cap := minf(map_a, vp_a) / maxf(map_a, vp_a) \
			/ ((1.0 + CAM_MARGIN) * (1.0 + CAM_MARGIN))
		var min_fraction := fill_cap * NONBG_SLACK
		cam_spec["fill_cap"] = fill_cap
		cam_spec["min_fraction"] = min_fraction
		var views: Array = cli["views"]
		var records: Array = []
		var ok := true
		var first_settle := true
		for view_name in views:
			var data: Dictionary = TerrainViewDataClass.derive(String(view_name), map,
				job.get("world", null))
			if not bool(data.get("implemented", false)):
				# 未实现视图：显式报「未实现」，不产图、不计失败（不冒充）
				print("[调试视图] [未实现] 视图 %s：%s（不产图、不计失败）"
					% [view_name, str(data.get("reason", ""))])
				records.append({"view": String(view_name), "state": "未实现",
					"note": str(data.get("reason", ""))})
				continue
			if not bool(data.get("has_data", true)):
				# 数据面视图（region/skeleton）无事实：显式报「无数据」不产图不计失败
				#（dual_noise 路线/旧图的合法态——S2 合同「无区域数据」显式态）
				print("[调试视图] [无数据] 视图 %s：%s（不产图、不计失败）"
					% [view_name, str(data.get("reason", ""))])
				records.append({"view": String(view_name), "state": "无数据",
					"note": str(data.get("reason", ""))})
				continue
			_rebuild_mesh(map, data["colors"])
			await _frames(SETTLE_FIRST_FRAMES if first_settle else SETTLE_VIEW_FRAMES)
			first_settle = false
			var img := await _capture()
			if img == null:
				return false  # _capture 内已 _fail（quit 1）
			var bg_report := _corner_bg(img)
			var view_ok := true
			var bg := Color.BLACK
			if not bg_report.get("ok", false):
				print("[调试视图] FAIL CHECK-A %s 视图四角背景不一致：%s"
					% [view_name, str(bg_report.get("why", ""))])
				view_ok = false
			else:
				bg = bg_report["color"]
			var total := img.get_width() * img.get_height()
			var nonbg: int = _count_vs_color(img, bg)
			var fraction := float(nonbg) / float(maxi(total, 1))
			if fraction <= min_fraction:
				print("[调试视图] FAIL CHECK-B %s 视图非背景占比 %.1f%% ≤ 阈值 %.1f%%（期望填充 %.1f%%×%.0f%%——取景/渲染回归？）"
					% [view_name, fraction * 100.0, min_fraction * 100.0, fill_cap * 100.0,
						NONBG_SLACK * 100.0])
				view_ok = false
			records.append({"view": String(view_name), "state": "渲染", "img": img,
				"nonbg": nonbg, "total": total, "fraction": fraction,
				"bg_ok": bool(bg_report.get("ok", false)), "data": data})
			ok = ok and view_ok
		# CHECK-C：实做视图两两差分（>0 对即查——防同图重复落盘/派生退化同值）
		var rendered: Array = []
		for r in records:
			if r["state"] == "渲染":
				rendered.append(r)
		for i in rendered.size():
			for j in range(i + 1, rendered.size()):
				var a: Image = rendered[i]["img"]
				var b: Image = rendered[j]["img"]
				var diff: int = _count_diff(a, b)
				var pair_ok := diff > VIEW_DIFF_MIN_PX
				if not pair_ok:
					print("[调试视图] FAIL CHECK-C %s↔%s 差分 px=%d ≤ 阈值 %d（两视图疑似同帧——派生或落盘回归）"
						% [rendered[i]["view"], rendered[j]["view"], diff, VIEW_DIFF_MIN_PX])
				rendered[i]["diff_%s" % rendered[j]["view"]] = diff
				ok = ok and pair_ok
		# 同视图双捕获稳定性（留档不设门：静态场景两次捕获应逐位一致；AA/驱动噪声面）
		var stability_px := -1
		if not rendered.is_empty():
			await _frames(SETTLE_VIEW_FRAMES)
			var again := await _capture()
			if again == null:
				return false
			var last: Image = rendered[rendered.size() - 1]["img"]
			stability_px = _count_diff(last, again)
		# 留档（PNG + 统计 txt；写入失败按 FAIL——证据是本工具交付物）
		var saved := _save_evidence(job, cli, records, cam_spec, stability_px)
		if saved == "":
			return false
		print("[调试视图] 证据已留档：%s" % saved)
		return ok

	# ---------------- 场景（正交俯视数据面）----------------

	## 建环境 + 规定相机 + 空 mesh 节点；返回相机口径描述（进统计）
	func _build_scene(map: MapDataClass) -> Dictionary:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = BG_COLOR
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		we.environment = env
		add_child(we)
		var bounds: Rect2 = HexCameraLib.map_focus_bounds(map, 1.0)
		var c := bounds.get_center()
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		var aspect := vp_size.x / maxf(vp_size.y, 1.0)
		var ortho_size := maxf(bounds.size.y, bounds.size.x / aspect) * (1.0 + CAM_MARGIN)
		_cam = Camera3D.new()
		_cam.name = "DebugViewsCamera"
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = ortho_size
		_cam.near = CAM_NEAR
		_cam.far = CAM_FAR
		_cam.current = true
		add_child(_cam)
		_cam.global_transform = Transform3D(
			Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
			Vector3(c.x, CAM_Y, c.y))
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_mesh_node = MeshInstance3D.new()
		_mesh_node.name = "DebugViewsDataPlane"
		_mesh_node.material_override = _material
		add_child(_mesh_node)
		return {"bounds": bounds, "ortho_size": ortho_size, "aspect": aspect}

	## 按视图色重建数据面 mesh：每格整六边形（中心 + 6 外顶点），顶点色 = 视图色；
	## raw 顶点序俯视逆时针、渲染索引 (base, v_{k+1}, v_k) 俯视顺时针 = Godot 正面
	##（hex_terrain_builder F-1 绕序双层口径——默认 CULL_BACK 下俯视可见）
	func _rebuild_mesh(map: MapDataClass, colors: PackedColorArray) -> void:
		var cells := map.cells()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in cells.size():
			var cell: Vector2i = cells[i]
			var col: Color = colors[i]
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(Hex.axial_to_world(cell, 1.0, 0.0))
			for k in 6:
				st.set_color(col)
				st.set_normal(Vector3.UP)
				st.add_vertex(Hex.cell_vertex(cell, k, 1.0, 0.0))
			var base := i * 7
			for k in 6:
				var v0 := base + 1 + k
				var v1 := base + 1 + (k + 1) % 6
				st.add_index(base)
				st.add_index(v1)  # 索引翻转：俯视顺时针 = 正面（F-1）
				st.add_index(v0)
		var mesh := ArrayMesh.new()
		st.commit(mesh)
		_mesh_node.mesh = mesh

	# ---------------- 截图与像素统计（render_probe 同款口径）----------------

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

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

	## 与参考色相异的像素计数（任一通道差 > CHANNEL_TOL）——render_probe 同款
	func _count_vs_color(img: Image, ref: Color) -> int:
		var ch := _channels(img)
		var d := img.get_data()
		var rr := int(ref.r8)
		var gg := int(ref.g8)
		var bb := int(ref.b8)
		var count := 0
		var n := d.size() / ch
		for i in n:
			var o := i * ch
			if absi(d[o] - rr) > CHANNEL_TOL or absi(d[o + 1] - gg) > CHANNEL_TOL \
					or absi(d[o + 2] - bb) > CHANNEL_TOL:
				count += 1
		return count

	## 两帧差分像素计数（任一通道差 > CHANNEL_TOL）
	func _count_diff(a: Image, b: Image) -> int:
		if a.get_width() != b.get_width() or a.get_height() != b.get_height() \
				or a.get_format() != b.get_format():
			_fail("差分两帧尺寸/格式不一致（%s vs %s）——渲染管线不稳定"
				% [str(a.get_size()), str(b.get_size())])
			return 0
		var ch := _channels(a)
		var da := a.get_data()
		var db := b.get_data()
		var count := 0
		var n := da.size() / ch
		for i in n:
			var o := i * ch
			if absi(da[o] - db[o]) > CHANNEL_TOL or absi(da[o + 1] - db[o + 1]) > CHANNEL_TOL \
					or absi(da[o + 2] - db[o + 2]) > CHANNEL_TOL:
				count += 1
		return count

	func _channels(img: Image) -> int:
		return 4 if img.get_format() == Image.FORMAT_RGBA8 else 3

	# ---------------- 留档 ----------------

	## 各视图 PNG + 单图统计 txt 落 out 目录（文件名带渲染器运行时值与读回尺寸——S-1 口径）；
	## 返回统计文件路径，失败返回 ""（原因已打印）
	func _save_evidence(job: Dictionary, cli: Dictionary, records: Array,
			cam_spec: Dictionary, stability_px: int) -> String:
		var renderer := String(RenderingServer.get_current_rendering_method())
		var cfg := String(ProjectSettings.get_setting_with_override(
			"rendering/renderer/rendering_method"))
		var any_img: Image = null
		for r in records:
			if r["state"] == "渲染":
				any_img = r["img"]
				break
		if any_img == null:
			print("[调试视图] FAIL 零实做视图渲染产物（views 全为挂点？）——无证据可落")
			return ""
		var tag := "%s_%s_%dx%d" % [job["tag"], renderer.replace("_", ""),
			any_img.get_width(), any_img.get_height()]
		var dir := String(cli["out"])
		var dir_abs := ProjectSettings.globalize_path(dir)
		var mk := DirAccess.make_dir_recursive_absolute(dir_abs)
		if mk != OK and not DirAccess.dir_exists_absolute(dir_abs):
			print("[调试视图] FAIL 证据目录创建失败：%s（%d）" % [dir, mk])
			return ""
		var shot_paths: Array[String] = []
		for r in records:
			if r["state"] != "渲染":
				continue
			var p := "%s/terrain_debug_%s_%s.png" % [dir, r["view"], tag]
			var e: int = (r["img"] as Image).save_png(p)
			if e != OK:
				print("[调试视图] FAIL 截图写入失败：%s（%d）" % [p, e])
				return ""
			shot_paths.append(p)
		var stats_path := "%s/terrain_debug_stats_%s.txt" % [dir, tag]
		var f := FileAccess.open(stats_path, FileAccess.WRITE)
		if f == null:
			print("[调试视图] FAIL 统计文件打开失败：%s" % stats_path)
			return ""
		f.store_string(_stats_text(job, records, cam_spec, stability_px, renderer, cfg,
			shot_paths, tag))
		f.close()
		return stats_path

	## 统计文本（构建/设备/相机口径/逐视图像素统计/派生元数据——固定对照的可复现面）
	func _stats_text(job: Dictionary, records: Array, cam_spec: Dictionary,
			stability_px: int, renderer: String, cfg_renderer: String,
			shot_paths: Array, tag: String) -> String:
		var ver: Dictionary = Engine.get_version_info()
		var map: MapDataClass = job["map"]
		var L: Array[String] = []
		var all_ok := true
		L.append("Hexhammer T6 调试预览 terrain_debug_views · 像素统计（S2 前置 harness——验收先于生成器改动；提案 §实施分期 P0「调试预览」「固定对照」）")
		L.append("时间(UTC)：%s" % Time.get_datetime_string_from_system(true))
		L.append("引擎：Godot %s" % String(ver.get("string", "?")))
		L.append("渲染器（实际运行时）：%s（取自 RenderingServer.get_current_rendering_method()——S-1 口径）" % renderer)
		L.append("渲染器（工程配置值）：%s（仅对照；CLI --rendering-method 覆盖/驱动回退会使配置 ≠ 实际）" % cfg_renderer)
		L.append("设备：adapter=%s vendor=%s；OS=%s %s；DisplayServer=%s" % [
			RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
			OS.get_name(), OS.get_version(), DisplayServer.get_name()])
		var any_img: Image = null
		for r in records:
			if r["state"] == "渲染":
				any_img = r["img"]
				break
		L.append("图像尺寸：%d×%d（窗口请求 %d×%d，读回为准）" % [
			any_img.get_width(), any_img.get_height(), WINDOW_SIZE.x, WINDOW_SIZE.y])
		L.append("图：%s digest=%s（%d×%d）" % [job["source"], map.digest(), map.width, map.height])
		var bounds: Rect2 = cam_spec["bounds"]
		L.append("相机（规定）：正交俯视数据面——包络 %.1f×%.1f 中心上方直视下，正交 size=%.2f（纵横比 %.3f + 边距 %.0f%%），near=%.1f far=%.0f；basis x=(1,0,0) y=(0,0,-1) z=(0,1,0)（屏幕上=世界−Z 北，render_probe 规定相机同 basis）" % [
			bounds.size.x, bounds.size.y, float(cam_spec["ortho_size"]),
			float(cam_spec["aspect"]), CAM_MARGIN * 100.0, CAM_NEAR, CAM_FAR])
		L.append("数据面：每格整六边形（vertex_xz 外顶点）顶点色；材质 UNSHADED + vertex_color albedo（灰度值=数据本身不受光照影响；8 位读回经色彩空间转换，比对用容差判定 > %d）" % CHANNEL_TOL)
		L.append("像素自检阈值：非背景占比 > 取景期望填充 %.1f%% × %.0f%% = %.1f%%（纵横比自适应——极端狭长图不误报）；视图两两差分 > %dpx（防呆阈值，首报实测见 DIFF 行）" % [
			float(cam_spec["fill_cap"]) * 100.0, NONBG_SLACK * 100.0,
			float(cam_spec["min_fraction"]) * 100.0, VIEW_DIFF_MIN_PX])
		L.append("")
		for r in records:
			if r["state"] == "未实现":
				L.append("VIEW %s：[未实现] %s（不产图不计失败）" % [
					r["view"], r["note"]])
				continue
			if r["state"] == "无数据":
				L.append("VIEW %s：[无数据] %s（dual_noise 路线/旧图合法态；不产图不计失败）" % [
					r["view"], r["note"]])
				continue
			var ok_view := bool(r["bg_ok"]) and float(r["fraction"]) > float(cam_spec["min_fraction"])
			all_ok = all_ok and ok_view
			L.append("VIEW %s：非背景 px=%d/%d（%.1f%%），四角背景自检 %s → %s" % [
				r["view"], int(r["nonbg"]), int(r["total"]), float(r["fraction"]) * 100.0,
				"过" if bool(r["bg_ok"]) else "FAIL", "PASS" if ok_view else "FAIL"])
			var data: Dictionary = r["data"]
			match String(r["view"]):
				"height":
					L.append("  高度灰度：高程 min=%d max=%d range=%d（水格 0 档参与归一——水=最暗）" % [
						int(data["min_elevation"]), int(data["max_elevation"]), int(data["range"])])
				"slope":
					L.append("  坡度：max_slope=%d（逐格最大界内邻差归一）" % int(data["max_slope"]))
				"passability":
					L.append("  可用通行连通片（MapConnectivity 口径）：通行=%d格 分量=%d 最大片=%d（%.1f%%）判定 ok=%s 孤岛=%d；分级大小=%s（秩0=亮灰基准，余按秩取色板）" % [
						int(data["passable_total"]), int(data["component_count"]),
						int(data["largest_size"]), float(data["largest_fraction"]) * 100.0,
						str(data["ok"]), int(data["isolated_count"]),
						str(data["component_sizes"])])
				"region":
					L.append("  区域（群山权重连续场灰度）：区域=%d（群山=%d 平原=%d）；权重 w≥0.7=%d格 w≤0.3=%d格（两档主导在场——提案「宏观可读性」的机器面）；灰度=lerp(平原%.2f,群山%.2f,w)" % [
						int(data["region_count"]), int(data["mountain_regions"]),
						int(data["plain_regions"]), int(data["high_cells"]),
						int(data["low_cells"]), TerrainViewDataClass.REGION_PLAIN_GRAY,
						TerrainViewDataClass.REGION_MOUNTAIN_GRAY])
				"skeleton":
					L.append("  骨架（四级灰度）：主山系=%d 支脉=%d 宽谷=%d（谷底格=%d）；灰度档 背景%.2f/谷底%.2f/支脉%.2f/主脊%.2f（孤峰层 S4 预留）" % [
						int(data["ranges"]), int(data["branches"]), int(data["valleys"]),
						int(data["valley_cells"]), TerrainViewDataClass.SKELETON_BG_GRAY,
						TerrainViewDataClass.SKELETON_VALLEY_GRAY,
						TerrainViewDataClass.SKELETON_BRANCH_GRAY,
						TerrainViewDataClass.SKELETON_SPINE_GRAY])
		var rendered: Array = []
		for r in records:
			if r["state"] == "渲染":
				rendered.append(r)
		for i in rendered.size():
			for j in range(i + 1, rendered.size()):
				var key := "diff_%s" % rendered[j]["view"]
				var diff: int = int(rendered[i].get(key, -1))
				var pair_ok := diff > VIEW_DIFF_MIN_PX
				all_ok = all_ok and pair_ok
				L.append("DIFF %s↔%s：px=%d，阈值=%d → %s" % [
					rendered[i]["view"], rendered[j]["view"], diff, VIEW_DIFF_MIN_PX,
					"PASS" if pair_ok else "FAIL"])
		if stability_px >= 0:
			L.append("同视图双捕获稳定性（末视图两次捕获差分）：px=%d（静态场景应≈0；留档不设门）" % stability_px)
		L.append("")
		L.append("口径：三路对照「旧版」基准 = 双噪声现役路线（银行样图即产物）；「分区骨架版」= regions_mountains 模板（S3 起可渲）；「+侵蚀版」随 S4。同 seed/模板 + 同相机口径跨版本帧帧可比。")
		L.append("本文件全部结论仅覆盖「渲染器（实际运行时）」一行所列后端；其余后端未测。")
		L.append("截图（同目录）：%s" % "、".join(shot_paths))
		L.append("标识：%s" % tag)
		L.append("VIEWS OK" if all_ok else "VIEWS FAIL")
		L.append("")
		return "\n".join(L)

	# ---------------- 通用 ----------------

	func _fail(reason: String) -> void:
		print("[调试视图] VIEWS FAIL — %s" % reason)
		get_tree().quit(1)

	func _arm_watchdog() -> void:
		var t := Timer.new()
		t.name = "Watchdog"
		t.wait_time = WATCHDOG_SEC
		t.one_shot = true
		t.timeout.connect(func() -> void:
			print("[调试视图] VIEWS FAIL — 看门狗超时（%.0fs 未完成，工具自身卡死）" % WATCHDOG_SEC)
			get_tree().quit(1))
		add_child(t)
		t.start()
