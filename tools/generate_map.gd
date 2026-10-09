## generate_map.gd — 随机地图生成 CLI（M1a-T9；docs/04-tasks-m1.md M1a-T9
##   「简单随机生成脚本（tools/ 下，参数化尺寸/类型/高程分布）」）
## 用法（用户参数在 `--` 之后，key=value 形式；Windows cmd 免引号友好）：
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless \
##     --path hexhammer --script res://tools/generate_map.gd -- seed=42 count=5 sea=0.25
## 参数表（默认值 = MapGenParams 默认；语义见 map_gen_params.gd 头注）：
##   seed=<int>            起始种子（count>1 时扫 seed..seed+count-1）
##   width=<int> height=<int>   尺寸（列×行）
##   noise=<名>            高度场噪声类型：simplex / simplex_smooth / cellular /
##                         perlin / value_cubic / value
##   freq=<float>          高度场频率（越低越平缓连绵）
##   octaves=<int>         高度场 FBM 倍频数
##   mfreq=<float>         湿度场频率
##   sea=<float>           海面阈值 [0,1)——水占比主旋钮
##   levels=<int>          陆地高程档数
##   count=<int>           连续生成张数（默认 1）
##   out=<dir>             通过图输出目录（默认 resources/maps/generated）
##   failed_dir=<dir>      失败图（断路/孤岛）输出目录（默认 tests/fixtures/maps/failed，
##                         **入库作回归样例**，tests/test_map_source.gd 引用）
##   save=<bool>           通过图是否落盘（默认 true；失败图恒落盘——任务卡交付项）
## 产物（每张图三件套，见 map_io.gd 头注）：<seed>.json / <seed>.meta.json / <seed>.summary.txt
##   通过图名 = map_<seed>，失败图名 = map_fail_<seed>。
## 退出码：用法/参数错误 → 1；正常生成（含连通性失败的图——那是合法产物并已留证）→ 0。
## 复现口径：同 seed+同参数仅在同一生成器版本与引擎构建下逐格一致（meta 落盘备查）。
extends SceneTree

const MapGenerator := preload("res://scripts/content/map_generator.gd")
const MapGenParamsClass := preload("res://scripts/content/map_gen_params.gd")
const MapIO := preload("res://scripts/content/map_io.gd")

func _init() -> void:
	var cli := _parse_args(OS.get_cmdline_user_args())
	if cli.is_empty():
		return  # 用法错误已打印，_parse_args 内 quit(1)
	var params: MapGenParamsClass = cli["params"]
	var out_dir: String = cli["out"]
	var failed_dir: String = cli["failed_dir"]
	var count: int = cli["count"]
	var save: bool = cli["save"]

	print("[生成器] 参数：", params.to_dict())
	var pass_count := 0
	var fail_count := 0
	for i in count:
		params.seed = cli["seed"] + i
		var result := MapGenerator.generate(params)
		if not result["ok"]:
			print("[生成器] !!! seed=", params.seed, " 生成失败：", result["error"])
			quit(1)
			return
		var map = result["map"]
		var meta: Dictionary = result["meta"]
		var conn: Dictionary = meta["connectivity"]
		var verdict := "通过" if conn["ok"] else "失败(断路/孤岛)"
		print("[生成器] seed=%d digest=%s" % [params.seed, meta["digest"]])
		print("        水=%d格 通行=%d格 连通分量=%d 最大片=%d(%d%%) → %s"
			% [meta["terrain_counts"].get(3, 0), conn["passable_total"],
				conn["component_count"], conn["largest_size"],
				int(round(float(conn["largest_fraction"]) * 100.0)), verdict])
		# 失败图恒落盘（回归样例）；通过图按 save 开关
		var base_dir := failed_dir if not conn["ok"] else out_dir
		var name_prefix := "map_fail_" if not conn["ok"] else "map_"
		if conn["ok"] and not save:
			continue
		var base := base_dir.path_join("%s%d" % [name_prefix, params.seed])
		var e1 := MapIO.write_map(map, base + ".json")
		var e2 := MapIO.write_meta(meta, base + ".meta.json")
		var e3 := MapIO.write_summary(map, base + ".summary.txt")
		if e1 != OK or e2 != OK or e3 != OK:
			print("[生成器] !!! seed=", params.seed, " 落盘失败：map=", e1, " meta=", e2, " summary=", e3)
			quit(1)
			return
		print("        已落盘 ", base, ".json(+meta+summary)")
		if conn["ok"]:
			pass_count += 1
		else:
			fail_count += 1
	print("[生成器] 汇总：%d 张（通过 %d / 失败 %d）——失败图见 %s（回归样例）"
		% [count, pass_count, fail_count, failed_dir])
	quit(0)


## key=value 用户参数 → {params, seed, count, out, failed_dir, save}；
## 未知键/值非法 → 打印用法并 quit(1)（返回空 dict 供 _init 短路）。
func _parse_args(args: PackedStringArray) -> Dictionary:
	var params := MapGenParamsClass.new()
	var cli := {
		"seed": params.seed,
		"count": 1,
		"out": MapIO.GENERATED_DIR,
		"failed_dir": MapIO.FAILED_FIXTURE_DIR,
		"save": true,
	}
	var int_keys := {"width": "width", "height": "height", "octaves": "fractal_octaves",
		"levels": "elevation_levels"}
	var float_keys := {"freq": "frequency", "mfreq": "moisture_frequency", "sea": "sea_level"}
	for arg in args:
		var kv := arg.split("=", true, 1)
		if kv.size() != 2:
			_usage("参数须为 key=value 形式：%s" % arg)
			return {}
		var key := kv[0]
		var value := kv[1]
		match key:
			"seed":
				if not value.is_valid_int():
					_usage("seed 须为整数：%s" % value)
					return {}
				cli["seed"] = int(value)
			"count":
				if not value.is_valid_int() or int(value) < 1:
					_usage("count 须为 ≥1 整数：%s" % value)
					return {}
				cli["count"] = int(value)
			"noise":
				if not MapGenParamsClass.NOISE_TYPE_NAMES.has(value):
					_usage("noise 未知类型 %s（可选：%s）"
						% [value, ", ".join(MapGenParamsClass.NOISE_TYPE_NAMES.keys())])
					return {}
				params.noise_type = MapGenParamsClass.NOISE_TYPE_NAMES[value]
			"out":
				cli["out"] = value
			"failed_dir":
				cli["failed_dir"] = value
			"save":
				if value != "true" and value != "false":
					_usage("save 须为 true/false：%s" % value)
					return {}
				cli["save"] = value == "true"
			_:
				if int_keys.has(key):
					if not value.is_valid_int():
						_usage("%s 须为整数：%s" % [key, value])
						return {}
					params.set(int_keys[key], int(value))
				elif float_keys.has(key):
					if not value.is_valid_float():
						_usage("%s 须为数值：%s" % [key, value])
						return {}
					params.set(float_keys[key], float(value))
				else:
					_usage("未知参数 %s" % key)
					return {}
	var err := params.validate()
	if err != "":
		_usage("参数组合非法：%s" % err)
		return {}
	cli["params"] = params
	return cli


func _usage(reason: String) -> void:
	print("[生成器] !!! ", reason)
	print("用法：godot --headless --path hexhammer --script res://tools/generate_map.gd -- "
		+ "seed=42 count=5 width=60 height=40 noise=simplex freq=0.05 octaves=3 "
		+ "sea=0.25 levels=4 mfreq=0.12 out=<dir> failed_dir=<dir> save=true")
	quit(1)
