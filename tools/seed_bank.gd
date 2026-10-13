## seed_bank.gd — seed 银行批跑工具（T5 WORLD-04 ③；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-04——「按模板 × 尺寸分组的
##   固定 seed 清单 + 批跑验收工具（tools/ 沿 make_fixed_maps/generate_map 先例）；
##   发布银行与探索性新 seed 分开统计」；提交级只跑 smoke seeds、完整银行跑
##   定期回归（提案提交级别口径）」；T6 S5 扩 regions 模板银行组——提案
##   §验收与评估 :263「固定的 20 个 seed，覆盖小、中、大三档地图尺寸」）
## 银行结构：BANK = {组名: {"template_id": String, "size": "WxH", "seeds": Array[int],
##   "make": String（可选——"regions" = 以 WorldTemplate.make_regions 为基座，
##   regions 路线 + 验收组起调值随 .tres 同源）}}
##   ——组名 = 模板 × 尺寸（分组即验收口径）；seeds 前段 = 发布银行（smoke 提交级
##   份额），全量 = 完整银行（定期回归）。指标数值悬置（拍板⑤）：本工具照做批跑、
##   数字留档不设门——退出码只反映「跑完」与工具错误，银行质量看报告（除非
##   --strict 把失败率过半也当异常——默认关）。regions 组的失败行（REGION_* 错误
##   码 + 不合格区域编号）是 T6 S5 的**合法产物**：区域验收面首落，阈值 = 未验证
##   起调值，失败分布本身是 S6/S7 调参输入（小图档占比普遍出带 = 已知信号）。
## 产物：
##   - 失败样例 → FAILED_FIXTURE_DIR/world/ 子目录（世界生成失败样例与连通性
##     失败样例分流——tests/test_map_source.gd 的失败图断言只扫 FAILED_FIXTURE_DIR
##     顶层，子目录由本工具的专属断言面（tests/test_world_validator.gd）覆盖）；
##     每例三件：map_fail_<组>_<seed>.json + .meta.json + .world.json（可加载复验）
##   - 银行样图（每组首个通过 seed）→ resources/maps/bank/<组>_sample.json 全件套
##     ——render_probe -- --map=<路径> 的留档入口（渲染器标注取运行时值口径）
## 用法（用户参数在 -- 之后，key=value）：
##   godot --headless --path . --script res://tools/seed_bank.gd -- mode=smoke
##   可选：mode=full|smoke（默认 smoke）；group=<名>（默认全组）；strict=true
## 退出码：用法错误 → 1；跑完（含失败 seed——那是合法产物并已留证）→ 0。
extends SceneTree

const WorldTemplateClass := preload("res://scripts/core/data/world_template.gd")
const WorldPipeline := preload("res://scripts/content/world_pipeline.gd")
const MapIOClass := preload("res://scripts/content/map_io.gd")

## 提交级 smoke 份额（每组跑前 N 个 seed——完整银行定期回归）
const SMOKE_COUNT := 3

## 银行清单（模板 × 尺寸分组；seed 为固定 authored 值——增删 = 银行版本变更，
## 报告留档对照）。default_terraces@60x40 = 默认模板全开面（九阶段）。
## regions_mountains 三档（T6 S5，提案 :263 二十 seed）= make_regions() 基座
## （regions 路线 + 侵蚀开 + 验收组起调值，与 world_template_regions.tres 同源）；
## 档值 24x16 / 60x40 / 96x64 = 未验证起调值（§10 默认答案①——沿现有两组档距
## 补第三档大图）。seed 分布为 authored 混样（含通过/不通过两态——报告对照面）。
const BANK := {
	"default_terraces@60x40": {
		"template_id": "default_terraces",
		"size": "60x40",
		"seeds": [7, 42, 7301, 20261011, 1234567, 90210],
	},
	"default_terraces@24x16": {
		"template_id": "default_terraces",
		"size": "24x16",
		"seeds": [7, 42, 7301, 11, 23],
	},
	"regions_mountains@24x16": {
		"template_id": "regions_mountains",
		"make": "regions",
		"size": "24x16",
		"seeds": [7, 42, 7301, 11, 23, 5, 20261013],
	},
	"regions_mountains@60x40": {
		"template_id": "regions_mountains",
		"make": "regions",
		"size": "60x40",
		"seeds": [7, 42, 7301, 11, 23, 5, 55],
	},
	"regions_mountains@96x64": {
		"template_id": "regions_mountains",
		"make": "regions",
		"size": "96x64",
		"seeds": [7, 42, 7301, 5, 101, 31337],
	},
}

## 失败样例目录（世界生成失败分流——与连通性失败样例 FAILED_FIXTURE_DIR 并列）
const FAILED_WORLD_DIR := MapIOClass.FAILED_FIXTURE_DIR + "/world"

## 银行样图输出目录
const BANK_SAMPLE_DIR := "res://resources/maps/bank"

func _init() -> void:
	var cli := _parse_args(OS.get_cmdline_user_args())
	if cli.is_empty():
		return  # 用法错误已打印并 quit(1)
	var report := run_bank(cli["mode"], cli["group"])
	print("")
	print("======== seed 银行汇总 ========")
	for line in report["lines"]:
		print(line)
	if cli["strict"]:
		quit(1 if int(report["failed"]) > 0 else 0)
	else:
		quit(0)

## 批跑一组或全组。返回 {"lines": Array[String], "passed": int, "failed": int,
##   "first_pass": int}（首次通过单独计——防重试隐藏生成器质量，§8.4）。
static func run_bank(mode: String, only_group := "") -> Dictionary:
	var lines: Array[String] = []
	var passed := 0
	var failed := 0
	var first_pass := 0
	for group_name in BANK:
		if only_group != "" and group_name != only_group:
			continue
		var spec: Dictionary = BANK[group_name]
		var template := _template_of(spec)
		if template == null:
			lines.append("FAIL %s：模板载入失败（先跑 --import？）" % group_name)
			failed += 1
			continue
		var seeds: Array = spec["seeds"]
		var count := seeds.size() if mode == "full" else mini(seeds.size(), SMOKE_COUNT)
		var group_pass := 0
		var group_first := 0
		for i in count:
			var seed_value := int(seeds[i])
			var t0 := Time.get_ticks_msec()
			var r := WorldPipeline.generate_validated(template, seed_value)
			var ms := Time.get_ticks_msec() - t0
			if r["ok"]:
				group_pass += 1
				if bool(r["world"].meta["first_pass_valid"]):
					group_first += 1
				lines.append("PASS %s seed=%d attempts=%d repairs=%d first_pass=%s (%dms)" % [
					group_name, seed_value, int(r["world"].meta["attempt_count"]),
					int(r["world"].meta["repair_count"]),
					str(r["world"].meta["first_pass_valid"]), ms])
				if group_pass == 1:
					_save_sample(group_name, seed_value, r)
			else:
				_save_failure(group_name, seed_value, r)
				var codes := PackedStringArray()
				for e in r["validation"]["errors"]:
					codes.append(String(e["code"]))
				lines.append("FAIL %s seed=%d attempts=%d err=%s codes=[%s] (%dms)" % [
					group_name, seed_value, (r["attempts_trace"] as Array).size(),
					str(r["error"]).substr(0, 120), ",".join(codes), ms])
		passed += group_pass
		first_pass += group_first
		failed += count - group_pass
		lines.append("---- %s：%d/%d 通过（首过 %d）——mode=%s" % [
			group_name, group_pass, count, group_first, mode])
	lines.append("======== 银行 %s：通过 %d / 失败 %d（首过 %d）========" % [
		mode, passed, failed, first_pass])
	return {"lines": lines, "passed": passed, "failed": failed, "first_pass": first_pass}

## 组规格 → 模板实例（default 组 = 代码默认模板 + 组规格尺寸覆盖——.tres 同源
## 锚在 tests；尺寸覆盖即「模板 × 尺寸分组」的尺寸面。make="regions" 组 =
## WorldTemplate.make_regions() 基座 + 尺寸覆盖——world_template_regions.tres
## 的同源锚（tests/test_world_pipeline.gd 锚定两者 to_dict 一致），regions 路线
## 与 S5 验收组起调值随之带上）。
static func _template_of(spec: Dictionary) -> WorldTemplateClass:
	var t := WorldTemplateClass.make_regions() \
		if String(spec.get("make", "")) == "regions" else WorldTemplateClass.new()
	t.template_id = String(spec["template_id"])
	var size_parts := String(spec["size"]).split("x")
	if size_parts.size() != 2 or not size_parts[0].is_valid_int() or not size_parts[1].is_valid_int():
		return null
	t.width = int(size_parts[0])
	t.height = int(size_parts[1])
	if t.validate() != "":
		return null
	return t

## 失败样例三件套入库（可加载复验——WORLD-04 测试锚「失败图入库」的数据面；
## 恒落盘：失败样例保留是任务卡交付项）。
static func _save_failure(group_name: String, seed_value: int, r: Dictionary) -> void:
	if r["map"] == null or r["world"] == null:
		return  # 管线硬失败（配置错）无半图可落——报告已具名
	var base := FAILED_WORLD_DIR.path_join("worldfail_%s_%d" % [group_name, seed_value])
	MapIOClass.write_map(r["map"], base + ".json")
	MapIOClass.write_world(r["world"], base + ".world.json")
	MapIOClass.write_meta({
		"kind": "seed_bank_failure",
		"group": group_name,
		"seed": seed_value,
		"generator_version": WorldPipeline.GENERATOR_VERSION,
		"attempt_count": (r["attempts_trace"] as Array).size(),
		"repair_count": (r["repair_actions"] as Array).size(),
		"error": r["error"],
		"world_digest": r["world"].world_digest(r["map"]),
		"digest": r["map"].digest(),
	}, base + ".meta.json")

## 银行样图（每组首个通过 seed）全件套落盘——render_probe --map 留档入口。
static func _save_sample(group_name: String, seed_value: int, r: Dictionary) -> void:
	var base := BANK_SAMPLE_DIR.path_join("%s_sample" % group_name.replace("@", "_"))
	MapIOClass.write_map(r["map"], base + ".json")
	MapIOClass.write_world(r["world"], base + ".world.json")
	MapIOClass.write_meta({
		"kind": "seed_bank_sample",
		"group": group_name,
		"seed": seed_value,
		"generator_version": r["world"].meta["generator_version"],
		"world_digest": r["world"].meta["world_digest"],
		"digest": r["map"].digest(),
	}, base + ".meta.json")

## key=value 用户参数 → {mode, group, strict}；未知键/值非法 → 打印用法并
## quit(1)（返回空 dict 供 _init 短路）。
func _parse_args(args: PackedStringArray) -> Dictionary:
	var cli := {"mode": "smoke", "group": "", "strict": false}
	for arg in args:
		var kv := arg.split("=", true, 1)
		if kv.size() != 2:
			_usage("参数须为 key=value 形式：%s" % arg)
			return {}
		match kv[0]:
			"mode":
				if kv[1] != "smoke" and kv[1] != "full":
					_usage("mode 须为 smoke/full：%s" % kv[1])
					return {}
				cli["mode"] = kv[1]
			"group":
				cli["group"] = kv[1]
			"strict":
				if kv[1] != "true" and kv[1] != "false":
					_usage("strict 须为 true/false：%s" % kv[1])
					return {}
				cli["strict"] = kv[1] == "true"
			_:
				_usage("未知参数 %s" % kv[0])
				return {}
	if cli["group"] != "" and not BANK.has(cli["group"]):
		_usage("未知组 %s（可选：%s）" % [cli["group"], ", ".join(BANK.keys())])
		return {}
	return cli


func _usage(reason: String) -> void:
	print("[银行] !!! ", reason)
	print("用法：godot --headless --path . --script res://tools/seed_bank.gd -- "
		+ "mode=smoke group=default_terraces@60x40 strict=false")
	print("  mode=smoke 每组前 %d 个 seed（提交级）；mode=full 全量（定期回归）" % SMOKE_COUNT)
	print("  失败样例 → %s；样图 → %s" % [FAILED_WORLD_DIR, BANK_SAMPLE_DIR])
	quit(1)
