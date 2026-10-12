## make_settlement_fixture.gd — WORLD-03 聚落失败样例入库工具（T5；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-03 测试锚「NO_VALID_SPAWN
##   fixture 反例入库」+ §6 WORLD-04「失败图入库（FAILED_FIXTURE_DIR 先例）」）
## 样本：4×4 微图（16 格，**零内点**——出生中心须 6 邻全界内，候选池恒空）
## + 默认模板（spawn_count=3、七格落兵区）——物理不可行 → NO_VALID_SPAWN
## 全部 4 次 attempt 尽 → 明确失败；末次产物三件套落 seed_bank 同款失败目录
## （tests/fixtures/maps/failed/world/，与连通性失败样例分流——顶层由
## test_map_source 断言「必须连通不通过」，世界失败样本未必断路，故置子目录
## 由 tests/test_world_validator.gd 专属断言：可加载 + meta 记录失败原因 +
## 同模板同 seed 重跑复现同失败（确定性锚））。
## 确定性：同 seed 同模板恒同样本（生成器版本纪律）——重跑覆盖落盘。
## 用法：godot --headless --path . --script res://tools/make_settlement_fixture.gd
## 退出码：0 = 样本落盘且确为 NO_VALID_SPAWN 失败；1 = 意外（样本竟然通过——
## 生成器行为漂移，须排查模板/生成器变更）。
extends SceneTree

const WorldTemplateClass := preload("res://scripts/core/data/world_template.gd")
const WorldPipeline := preload("res://scripts/content/world_pipeline.gd")
const MapIOClass := preload("res://scripts/content/map_io.gd")

const FIXTURE_SEED := 7
const FIXTURE_OUT := "res://tests/fixtures/maps/failed/world/worldfail_no_valid_spawn_4x4"

func _init() -> void:
	var t := WorldTemplateClass.new()
	t.template_id = "default_terraces"
	t.width = 4
	t.height = 4
	var r := WorldPipeline.generate_validated(t, FIXTURE_SEED)
	if r["ok"]:
		print("[样例] !!! 4×4 微图竟然生成通过（NO_VALID_SPAWN 前置失效——生成器行为漂移？）")
		quit(1)
		return
	var codes := PackedStringArray()
	for e in r["validation"]["errors"]:
		codes.append(String(e["code"]))
	var first_error := str(r["error"])
	print("[样例] 4×4 失败（预期）：", first_error.substr(0, 120))
	print("[样例] 错误码：", ",".join(codes), " attempts=", (r["attempts_trace"] as Array).size())
	if not first_error.contains("NO_VALID_SPAWN") and not codes.has("NO_VALID_SPAWN"):
		print("[样例] !!! 失败原因不是 NO_VALID_SPAWN（样本失真——须排查）")
		quit(1)
		return
	var base := FIXTURE_OUT
	var e1 := MapIOClass.write_map(r["map"], base + ".json")
	var e2 := MapIOClass.write_world(r["world"], base + ".world.json")
	var e3 := MapIOClass.write_meta({
		"kind": "settlement_failure_fixture",
		"source": "tools/make_settlement_fixture.gd",
		"seed": FIXTURE_SEED,
		"template": t.to_dict(),
		"generator_version": WorldPipeline.GENERATOR_VERSION,
		"attempt_count": (r["attempts_trace"] as Array).size(),
		"repair_count": (r["repair_actions"] as Array).size(),
		"first_pass_valid": false,
		"error": first_error,
		"world_digest": r["world"].world_digest(r["map"]),
		"digest": r["map"].digest(),
	}, base + ".meta.json")
	if e1 != OK or e2 != OK or e3 != OK:
		print("[样例] !!! 落盘失败：", e1, e2, e3)
		quit(1)
		return
	print("[样例] 已落盘三件套：", base, ".json/.meta.json/.world.json")
	quit(0)
