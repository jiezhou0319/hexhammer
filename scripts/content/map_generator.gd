## map_generator.gd — 随机地图生成器门面（M1a-T9 建立 → T5 WORLD-01 管线化重构；
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-01：「MapGenerator 现单遍
##   代码重构为第一阶段序列的退化特例（行为不变、同 seed 同图锚住）」）
## 职责变化：v1 的单遍直行管线（双噪声采样 → 归一化 → 量化+分类 → 连通检查，
##   四步全在本文件）已整体迁入 WorldPipeline 的九阶段序列——本文件降为
##   **门面**：generate(params) = WorldPipeline.generate_legacy(params)（模板 =
##   legacy 退化特例：噪声地理骨架 + 量化 + 可玩校验三段实做，其余六段按模板
##   跳过）。行为不变合同：同 seed 同参数 → 逐格同图、meta 键集与旧版逐键一致
##   （tests/test_world_pipeline.gd 独立 oracle 锚 + tests/test_map_source.gd
##   既有复现锚；GENERATOR_VERSION 随管线化 +1 = 复现口径的显式登记）。
## 历史口径保留（M1a-T9 头注要义，全文见 git 历史）：归一化而非假定 ±1 界内
##   （cellular 超界可归一）；地形→通行性映射 = 仅水不可通行（内容层显式落表，
##   MapData 不做自动推导）。
## 纯逻辑类：RefCounted、零场景节点（ADR-2；删 scripts/ui/** 不影响本文件与 tests/）。
class_name MapGenerator
extends RefCounted

const WorldPipelineClass := preload("res://scripts/content/world_pipeline.gd")
const MapGenParamsClass := preload("res://scripts/content/map_gen_params.gd")

## 生成器版本锚（复现口径——meta 落盘）：真源驻 WorldPipeline（管线变更的策源
## 地），此处再导出保持 MapGenerator.GENERATOR_VERSION 的历史引用面（tests/
## docs 均按此名引用，map_generator.gd:31 v1 先例）。v2 = WORLD-01 管线化 +
## 湿度通道改名「植被/地表掩码」（修订记录三之 7——通道保留、seed 偏移值
## 1013 原样继承，输出不漂移）。
const GENERATOR_VERSION := WorldPipelineClass.GENERATOR_VERSION

## 生成一张随机图（退化特例入口——详见类头注）。params = MapGenParams。
## 返回 { "ok": bool, "error": String（ok 时为 ""）,
##        "map": MapData（ok 时非空）, "meta": Dictionary（ok 时非空）,
##        "connectivity": Dictionary（MapConnectivity.check 报告，ok 时非空）,
##        "world": WorldData（恒空集合——退化特例无世界生成阶段）,
##        "stages": Array（逐阶段诊断，v2 新增只读面）}。
## 参数非法 → ok=false + error 原因（无隐式兜底；不产出半张图）。
static func generate(params: MapGenParamsClass) -> Dictionary:
	return WorldPipelineClass.generate_legacy(params)
