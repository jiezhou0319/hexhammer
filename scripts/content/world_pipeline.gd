## world_pipeline.gd — 世界生成管线编排器（T5 WORLD-01；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-01 + 主创拍板⑧
##   「WORLD 侧按 Azgaar 思路重构」+ 拍板④「不造气候」）
## 职责：Azgaar 管线骨架的**去气候九阶段**编排——配置校验 → 地理骨架（双噪声）
##   → 地貌整形（量化）→ 河网与水体（WORLD-02 河口反向生长）→ 聚落与占点
##   （WORLD-03 SettlementGenerator）→ 势力归属（WORLD-03 多源 Dijkstra +
##   normalize）→ 道路骨架（WORLD-05 MST + 桥址搜索 + 加路重验）→ 可玩校验
##   （WorldValidator 结构化错误报告——WORLD-04 落码；修复循环见
##   generate_validated）→ 表现派生（未解锁，首产物随国界线 mesh）。每阶段 =
##   独立纯函数 `stage(state, rng_channel) -> {ok, error, diagnostics}`（纯 =
##   无全局可变状态、无隐藏随机源，跨阶段数据经显式 state 传递）；WorldPipeline
##   持固定阶段序列 + 逐阶段诊断（Azgaar「无阶段诊断产物」反面教训的补丁，§6 ⑧）。
## 三条入口：
##   - generate_legacy(params)：MapGenerator 旧单遍直行代码的**退化特例**
##     （噪声地理骨架 + 量化 + 可玩校验三段实做，其余六段按模板跳过）——
##     行为不变：同 seed 同参数逐格同图（tests/test_world_pipeline.gd 独立
##     oracle 锚 + tests/test_map_source.gd 既有复现锚）；
##   - generate_world(template, seed, channel_overrides, repair_ctx)：九阶段
##     全开面（已实现段实做、未解锁段显式跳过——「关闭一个尚未实现能力不产生
##     伪字段」：跳过阶段的 WorldData 对应集合恒空）；repair_ctx = 修复循环的
##     上下文注入（锁定格归属锚定/锚定 POI 原样重发——WORLD-04 ②）；
##   - generate_validated(template, seed)：**生成-校验-有限修复循环**（WORLD-04：
##     最多 4 次 attempt、修复动作按首错固定顺序选通道 bump、每次后全量重验、
##     只动非 locked；attempt_count/repair_count/first_pass_valid 落 WorldMeta；
##     第 5 次尝试拒绝）。
## 随机性纪律（提案具名通道）：root seed + 具名偏移扩 geography/hydrology/poi/
##   roads/decoration 五通道（biome 通道删除——拍板④）；**通道互相独立**：
##   新增一棵树（decoration）不消耗前面阶段 RNG（测试锚）；连续场另有双噪声
##   ——高度场 seed = params.seed、植被/地表掩码场 seed+VEGETATION_SEED_OFFSET
##   （~~湿度场~~ 改名保留，修订记录三之 7：林/泥地表分类在用，生态语义删除、
##   用途不变；旧 MOISTURE_SEED_OFFSET 值 1013 原样继承 = 通道输出不漂移）。
## 高程事实唯一来源 = 双噪声 + 量化（~~海岸距离 BFS 高程重写/无局部极小~~ 已
##   移除——修订记录三之 5；日后作候选打分须改名并显式声明不改高程）。
## 纯逻辑类：RefCounted、零场景节点（ADR-2；删 scripts/ui/** 不影响本文件与
##   tests/）。生成器配置（模板）不进世界事实（草案 §1.2 边界维持）。
class_name WorldPipeline
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapGenParamsClass := preload("res://scripts/content/map_gen_params.gd")
const MapConnectivityClass := preload("res://scripts/content/map_connectivity.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const WorldTemplateClass := preload("res://scripts/core/data/world_template.gd")
const RiverGenClass := preload("res://scripts/content/river_network_generator.gd")
const SettlementGenClass := preload("res://scripts/content/settlement_generator.gd")
const RoadGenClass := preload("res://scripts/content/road_network_generator.gd")
const WorldValidatorClass := preload("res://scripts/content/world_validator.gd")

## 生成器版本：管线步骤、分类表、参数语义任一变更时 +1（meta 落盘，复现口径
## 的锚）。v2 = WORLD-01 管线化（单遍 → 九阶段退化特例）+ 湿度通道改名
## 「植被/地表掩码」（修订记录三之 7）；v3 = T5 完整管线（WORLD-03 聚落/势力 +
## WORLD-05 自动路网 + WORLD-04 WorldValidator/修复循环——三阶段从占位转实做、
## playability 升结构化报告，世界事实面新增 pois/states/cell_owners）；v4 =
## WORLD-04 修复面修订（出生锚定改槽序号落位——非首槽锚定不再翻阵营；
## roads 阶段接入 roads 通道等成本改道——roads_reconnect 修复重跑从同输入空转
## 变真重试，同 seed 道路事实较 v3 可变）。
const GENERATOR_VERSION := 4

## 植被/地表掩码场 seed 偏移（与高度场同 seed 时错开通道；值 = 旧
## MOISTURE_SEED_OFFSET 原样继承——改名不改值，通道输出不漂移；写死常量
## 保证复现）
const VEGETATION_SEED_OFFSET := 1013

## 植被/地表掩码场固定配置（不参数化：植被动动脉，口味项收进生成器版本管理）
const VEGETATION_NOISE_TYPE := FastNoiseLite.TYPE_SIMPLEX
const VEGETATION_OCTAVES := 2

## 地形 id（与 TerrainMaterialLibrary.DEFAULT_PALETTE 槽位同源；语义由内容层定义）
const TERRAIN_GRASS := 0
const TERRAIN_MUD := 1
const TERRAIN_ROCK := 2
const TERRAIN_WATER := 3
const TERRAIN_SAND := 4
const TERRAIN_FOREST := 5

## 植被/地表掩码分类阈值（归一化掩码值；分类表变更 = GENERATOR_VERSION+1）：
## 中档陆地掩码高于 FOREST 阈值 → 林替草；第 1 档陆地高于 MUD 阈值 → 泥替沙
## （~~湿度阈值~~ 改名保留——语义 = 地表覆盖分类，非生态湿度，修订记录三之 7）
const VEGETATION_FOREST_THRESHOLD := 0.60
const VEGETATION_MUD_THRESHOLD := 0.70

## 九阶段固定序（执行顺序即依赖图——Azgaar 可定位性正面纪律的沿用；顺序是
## 合同：后段消费前段产出，测试锚定顺序不可变）
const STAGES: Array[String] = [
	"config",        # ① 配置校验（模板 × 参数硬边界 + 冲突全列）
	"geography",     # ② 地理骨架（双噪声连续场采样——拍板①双噪声唯一路线）
	"quantize",      # ③ 地貌整形（归一化 → 量化整数高程 → 地表分类 → 写 MapData）
	"hydrology",     # ④ 河网与水体（WORLD-02 河口反向生长；模板可关）
	"settlement",    # ⑤ 聚落与占点（WORLD-03 实做；模板可关）
	"allegiance",    # ⑥ 势力归属（WORLD-03 实做；模板可关）
	"roads",         # ⑦ 道路骨架（WORLD-05 实做；模板可关）
	"playability",   # ⑧ 可玩校验（连通性 + WorldValidator 结构化报告——WORLD-04）
	"presentation",  # ⑨ 表现派生（未解锁——首产物随国界线 mesh）
]

## 阶段版本（独立于 GENERATOR_VERSION 的逐阶段算法版本——阶段输出规范序摘要
## 的可 diff 前提；阶段算法变更时 +1，Azgaar 复现性破坏教训的细粒度锚。
## playability v2 = WORLD-04 WorldValidator 结构化报告接入（连通性裸查 → 报告）；
## roads v2 = roads 通道等成本改道接入（rng 并列消耗——roads_reconnect 修复面）
const STAGE_VERSIONS := {
	"config": 1, "geography": 1, "quantize": 1, "hydrology": 1,
	"settlement": 1, "allegiance": 1, "roads": 2, "playability": 2,
	"presentation": 1,
}

## 具名随机通道（提案随机性纪律：五通道互相独立——「新增一棵树不消耗前面
## 阶段 RNG」；biome 通道删除，拍板④）
const CHANNELS: Array[String] = ["geography", "hydrology", "poi", "roads", "decoration"]

## 通道 seed 偏移（写死质数保证复现——MOISTURE_SEED_OFFSET 先例；五值互异且
## 与植被场偏移 1013 错开：通道间独立、与连续场独立，两层不串流）
const CHANNEL_SEED_OFFSETS := {
	"geography": 101,
	"hydrology": 211,
	"poi": 307,
	"roads": 401,
	"decoration": 503,
}

## 阶段 → 通道声明式映射（rng_channel 参数的来源；未被消耗 = 该阶段无离散
## 随机：地理/量化/势力 = 确定性算法，通道传入仅为签名统一——聚落阶段的
## 偏置抽取是 poi 通道的唯一抽取消耗点；道路阶段消费 roads 通道的**等成本
## 改道**（并列重挂——roads_reconnect 修复重跑的实现载体，v4 起））
const STAGE_CHANNEL := {
	"config": "geography", "geography": "geography", "quantize": "geography",
	"hydrology": "hydrology", "settlement": "poi", "allegiance": "poi",
	"roads": "roads", "playability": "geography", "presentation": "decoration",
}


## 跨阶段显式状态（阶段间数据传递的唯一通道——「跨阶段状态耦合」的对策面：
## 一切共享数据在此显式声明，无隐藏全局）。阶段函数只读入参、只经本对象与
## 返回值产出（纯函数口径：同 state 同 rng → 同结果）。repair_ctx = 修复循环
## 注入面（{locked_cells, owner_pins, pinned}——generate_validated 专用，
## 直跑入口恒空 dict = 零修复口径）。
class GenState:
	extends RefCounted

	var params: MapGenParamsClass          # 运行参数（legacy 直入 / world 由模板投影）
	var template: WorldTemplateClass       # 模板（阶段开关与阶段参数组）
	var map: MapDataClass = null           # ② 建载体、③ 写格子事实
	var world: WorldDataClass = null       # ④ 建世界事实（rivers/bodies/links）
	var heights := PackedFloat32Array()    # ② 产：高度场原始采样（③ 消）
	var mask := PackedFloat32Array()       # ② 产：植被/地表掩码原始采样（③ 消）
	var h_min := INF                       # ② 产：高度场极值（③ 归一化用）
	var h_max := -INF
	var m_min := INF                       # ② 产：掩码场极值
	var m_max := -INF
	var connectivity := {}                 # ⑧ 产：连通性报告（meta/诊断用）
	var validation := {}                   # ⑧ 产：WorldValidator 报告（WORLD-04）
	var repair_ctx := {}                   # 修复循环注入（锁定格/归属锚定/锚定 POI）
	var seed_value := 0                    # root seed（通道派生源）


# ---------------- 入口 ----------------

## 九阶段全开面入口：模板 → 运行参数（apply_to_params 唯一投射线）→ 逐阶段
## 执行。channel_overrides: {通道名: int}——单通道 seed 显式覆盖（通道独立性
## 测试锚的抓手：改 decoration 不应动 hydrology 输出）。repair_ctx =
## {locked_cells: Array[int], owner_pins: {cell: owner}, pinned: {…}}——
## generate_validated 修复循环的注入面（直跑缺省 = 零修复口径）。
## 返回 {"ok", "error", "map", "world", "meta"（WorldData.meta 同源 dict）,
##   "connectivity", "validation"（WorldValidator 报告）,
##   "stages"（Array[Dictionary] 逐阶段诊断，序 = STAGES）,
##   "generation_ms_by_stage"（{阶段: int ms} 逐阶段耗时——诊断通道不进 meta，§8.4）}。
static func generate_world(template: WorldTemplateClass, seed_value: int,
		channel_overrides := {}, repair_ctx := {}) -> Dictionary:
	if template == null:
		return _fail("模板为 null（generate_world 须持 WorldTemplate）")
	var params := template.apply_to_params(seed_value)
	return _run(params, template, seed_value, channel_overrides, false, repair_ctx)


## 退化特例入口：MapGenerator.generate 的管线面（行为不变锚——同 seed 同参数
## 逐格同图；meta 键集与旧单遍版逐键一致）。模板 = legacy（一切可选阶段关），
## 参数直入（不经模板投影——旧 API 的参数即事实源）。
static func generate_legacy(params: MapGenParamsClass) -> Dictionary:
	return _run(params, WorldTemplateClass.make_legacy(), params.seed, {}, true, {})


## **生成-校验-有限修复循环**（WORLD-04 ②；提案验收原文「最多 4 次尝试」）：
##   attempt 1 = 直跑 generate_world → WorldValidator 全量报告；有错 → 按固定
##   顺序选修复动作（河 → 聚落 → 道路——「修复动作互相打架」的固定顺序对策，
##   卡表风险栏），对相应**具名通道**做确定性 bump（attempt 序号 × 质数偏移）
##   重跑（地理/量化事实不动——bump 不触 geography/hydrology 之外的下游消费面
##   语义），锁定格经 repair_ctx 锚定注入（只动非 locked）；每次后全量重验。
##   attempt 上限 4——第 5 次尝试拒绝（返回末次产物 + 汇总错误 + meta）。
##   attempt_count/repair_count/first_pass_valid 落 WorldMeta（§10）。
## 返回 = generate_world 键集 + {"attempts_trace"（逐次 {map, world, errors}——
##   「修复不动 locked：锁定区修复前后逐位一致」断言的数据面）,
##   "repair_actions"（逐次动作名）}。
static func generate_validated(template: WorldTemplateClass, seed_value: int,
		max_attempts := 4) -> Dictionary:
	var overrides := {}
	var repair_ctx := {}
	var actions: Array[String] = []
	var trace: Array = []
	var r: Dictionary = {}
	for attempt in max_attempts:
		r = generate_world(template, seed_value, overrides, repair_ctx)
		if not r["ok"]:
			# 阶段硬失败（具名失败：NO_VALID_SPAWN / ROAD_NETWORK_DISCONNECTED …）：
			# 三个生成阶段的失败可修复（换出生候选带/重连道路/重画河段——卡表
			# 修复动作面）；config/量化/校验段失败 = 确定性错误，重试无意义即返
			var failed_stage := _failed_stage_of(r)
			if failed_stage == "" or failed_stage == "config" or failed_stage == "geography" \
					or failed_stage == "quantize" or failed_stage == "playability":
				r["attempts_trace"] = trace
				r["repair_actions"] = actions.duplicate()
				return r
			trace.append({"attempt": attempt + 1, "map": r["map"], "world": r["world"],
				"stages": r["stages"], "errors": [], "error": r["error"]})
			if attempt + 1 >= max_attempts:
				break  # attempt 上限尽——第 5 次尝试拒绝（循环即止，不再起生成）
			var hard_action := _stage_repair_action(failed_stage)
			actions.append(hard_action)
			overrides = _bump_channels(seed_value, overrides, hard_action, attempt + 1)
			# 修复锚定：锁定格的既有事实带入（部分世界也带——没有的面自然为空）
			if r["world"] != null:
				repair_ctx = _repair_ctx_of(template, r["world"])
			continue
		var errors: Array = r["validation"]["errors"]
		trace.append({"attempt": attempt + 1, "map": r["map"],
			"world": r["world"], "errors": errors.duplicate()})
		if errors.is_empty():
			_fill_repair_meta(r, attempt + 1, actions.size(), attempt == 0)
			r["attempts_trace"] = trace
			r["repair_actions"] = actions.duplicate()
			return r
		if attempt + 1 >= max_attempts:
			break  # attempt 上限尽——第 5 次尝试拒绝（循环即止，不再起生成）
		var action := _repair_action_for(errors)
		actions.append(action)
		overrides = _bump_channels(seed_value, overrides, action, attempt + 1)
		# 修复锚定：锁定格的归属/POI 事实从前次尝试带入（「修复不动 locked」）
		repair_ctx = _repair_ctx_of(template, r["world"])
	# 上限尽：末次产物 + 全部错误明确失败（不伪造达标——提案红线）
	var final_errors: Array = r.get("validation", {}).get("errors", [])
	if r["world"] != null:
		_fill_repair_meta(r, max_attempts, actions.size(), false)
	r["ok"] = false
	r["error"] = "修复上限尽：%d 次 attempt 仍失败：%s（第 5 次尝试拒绝，WORLD-04 ②）" \
		% [max_attempts, str(r.get("error", "")).substr(0, 160)
			if r.get("error", "") != "" else "校验错误 %d 项（首错 %s）" % [
				final_errors.size(),
				str(final_errors[0]["code"]) if not final_errors.is_empty() else "?"]]
	r["attempts_trace"] = trace
	r["repair_actions"] = actions.duplicate()
	return r


## 失败产物的失败阶段名（stages 尾段 = 失败段；空 = 非阶段失败）。
static func _failed_stage_of(r: Dictionary) -> String:
	var stages: Array = r.get("stages", [])
	if stages.is_empty():
		return ""
	return String(stages[stages.size() - 1].get("stage", ""))


## 失败阶段 → 修复动作（换出生候选带/重连道路/重画河段——卡表修复动作三件；
## 河段重画连带下游全部重算）。
static func _stage_repair_action(stage_name: String) -> String:
	match stage_name:
		"hydrology":
			return "hydrology_redraw"
		"settlement":
			return "settlement_repick"
		"roads":
			return "roads_reconnect"
	return "settlement_repick"


## 修复动作选择（固定顺序：河 → 聚落 → 道路——下游顺序，修河必连带重算下游，
## 故河错优先；未知码默认 settlement 重抽）。返回动作名（通道 bump 的键）。
static func _repair_action_for(errors: Array) -> String:
	for e in errors:
		var code := String(e["code"])
		if code.begins_with("RIVER_") or code.begins_with("NO_RIVER") \
				or code.begins_with("WATER_") or code == "WORLD_DATA_INVALID":
			return "hydrology_redraw"
	for e in errors:
		var code2 := String(e["code"])
		if code2 == "NO_VALID_SPAWN" or code2 == "NO_RESOURCE_SITE" \
				or code2.begins_with("POI_") or code2 == "STATE_CAPITAL":
			return "settlement_repick"
	for e in errors:
		var code3 := String(e["code"])
		if code3 == "ROAD_NETWORK_DISCONNECTED" or code3.begins_with("ROAD_") \
				or code3.begins_with("BRIDGE_") or code3.begins_with("CROSSING_") \
				or code3 == "RIVER_FORD_FORBIDDEN" or code3.begins_with("POI_FOOTPRINT"):
			return "roads_reconnect"
	# RESOURCE_UNREACHABLE = 资源点位重抽（settlement 面产物）；LOCKED 归冲突
	# settlement/roads 视锚定情况——默认重抽出生/资源带（卡表「换出生候选带」）
	return "settlement_repick"


## 修复动作 → 具名通道 bump（确定性：base + attempt × 质数步长——同 seed 同
## 错误序列恒同 bump，复现口径保持）。hydrology_redraw 连带下游（聚落/道路随
## 全管线重跑自然重算）；settlement 只 bump poi（河事实不动）；roads_reconnect
## 只 bump roads——道路阶段消费等成本改道（v4 起），bump 即换一套并列取舍 →
## 路网事实可变（修复重跑不再是同输入空转）。
static func _bump_channels(root_seed: int, overrides: Dictionary,
		action: String, attempt: int) -> Dictionary:
	var out := overrides.duplicate()
	var step := attempt * 7919  # 质数步长（写死保证复现——CHANNEL_SEED_OFFSETS 同纪律）
	match action:
		"hydrology_redraw":
			out["hydrology"] = channel_seed(root_seed, "hydrology", overrides) + step
			out["poi"] = channel_seed(root_seed, "poi", overrides) + step
			out["roads"] = channel_seed(root_seed, "roads", overrides) + step
		"settlement_repick":
			out["poi"] = channel_seed(root_seed, "poi", overrides) + step
		"roads_reconnect":
			out["roads"] = channel_seed(root_seed, "roads", overrides) + step
	return out


## 前次世界 → 修复注入面：锁定格的归属锚定 + 锚定 POI（footprint 触及锁定格的
## 出生槽/锁定格上的资源原样重发——槽位/格/格序保持）。出生槽序号 = 前次
## SETTLEMENT POI 在 pois 表中的出现序（与 poi_id 编号解耦——计数派生不依赖
## 2si/2si+1 编号约定）。
static func _repair_ctx_of(template: WorldTemplateClass,
		world: WorldDataClass) -> Dictionary:
	var locked := template.locked_cells()
	if locked.is_empty():
		return {}
	var locked_set := {}
	for cid in locked:
		locked_set[cid] = true
	var owner_pins := {}
	for cid in locked:
		if cid >= 0 and cid < world.cell_owners.size():
			owner_pins[cid] = world.cell_owners[cid]
	var spawn_anchor_slots := {}
	var settlement_slot := -1
	var resource_cells: Array[int] = []
	for p in world.pois:
		if p.kind == WorldDataClass.POIData.Kind.SETTLEMENT:
			settlement_slot += 1
			continue
		if p.kind == WorldDataClass.POIData.Kind.SPAWN_ZONE:
			var touches := false
			for cid in p.footprint_cells:
				if locked_set.has(cid):
					touches = true
					break
			# 锚定槽记 {槽序号: 锚格}——settlement_generator 按槽落位重发（role/poi_id
			# 由槽序号派生，非首槽锚定不得翻阵营）；槽号 <0 = SPAWN_ZONE 先于任何
			# SETTLEMENT 出现（管线产物不会发生），防御性跳过
			if touches and settlement_slot >= 0:
				spawn_anchor_slots[settlement_slot] = p.cell_id
		elif p.kind == WorldDataClass.POIData.Kind.RESOURCE and locked_set.has(p.cell_id):
			resource_cells.append(p.cell_id)
	return {"locked_cells": locked, "owner_pins": owner_pins,
		"pinned": {"spawn_anchor_slots": spawn_anchor_slots,
			"resource_cells": resource_cells}}


## meta 三字段回填（WORLD-04 ②：attempt_count/repair_count/first_pass_valid
## 落 WorldMeta——r["world"].meta 与 r["meta"] 同步改写）。
static func _fill_repair_meta(r: Dictionary, attempt_count: int,
		repair_count: int, first_pass: bool) -> void:
	var world: WorldDataClass = r["world"]
	world.meta["attempt_count"] = attempt_count
	world.meta["repair_count"] = repair_count
	world.meta["first_pass_valid"] = first_pass
	r["meta"] = world.meta.duplicate()


## 通道 seed 派生（root + 写死偏移；overrides 命中即整值替换）。未知通道名 →
## -1 哨兵（调用方 bug 的显式面，不静默归零）。
static func channel_seed(root_seed: int, channel: String, overrides := {}) -> int:
	if overrides.has(channel):
		return int(overrides[channel])
	if not CHANNEL_SEED_OFFSETS.has(channel):
		return -1
	return root_seed + int(CHANNEL_SEED_OFFSETS[channel])


# ---------------- 编排 ----------------

## 统一九阶段执行器。任一实做阶段失败 → 即返（stages 带已跑段的诊断——错误
## 可定位到阶段，Azgaar 反面教训的补丁）；跳过段产出 skipped 诊断（空集合
## 合法，不产伪字段）。
static func _run(params: MapGenParamsClass, template: WorldTemplateClass,
		seed_value: int, channel_overrides: Dictionary, legacy: bool,
		repair_ctx: Dictionary) -> Dictionary:
	var state := GenState.new()
	state.params = params
	state.template = template
	state.seed_value = seed_value
	state.world = WorldDataClass.empty()
	state.repair_ctx = repair_ctx

	var channels := {}
	for ch in CHANNELS:
		var rng := RandomNumberGenerator.new()
		rng.seed = channel_seed(seed_value, ch, channel_overrides)
		channels[ch] = rng

	var stages_out: Array = []
	var ms_by_stage := {}
	for stage_name in STAGES:
		var t0 := Time.get_ticks_msec()
		var result: Dictionary = _run_stage(stage_name, state, channels[STAGE_CHANNEL[stage_name]])
		ms_by_stage[stage_name] = Time.get_ticks_msec() - t0
		stages_out.append(result["diagnostics"])
		if not result["ok"]:
			var fail := _fail(result["error"])
			# 部分产物保留（失败样例入库面——WORLD-04 ④）。config 段失败时 map 恒
			# null → world 同置 null（「不产半图」口径维持——空 WorldData 也不给，
			# 配置错误的调用方只应见错误）；中段失败 = 已成事实落盘留证
			fail["map"] = state.map
			fail["world"] = state.world if state.map != null else null
			fail["stages"] = stages_out
			fail["generation_ms_by_stage"] = ms_by_stage.duplicate()
			return fail
	if legacy:
		return _legacy_result(state, stages_out)
	return _world_result(state, stages_out, ms_by_stage)


## 单阶段分派（跳过判定 + 实做调用）。跳过原因具名进诊断。
static func _run_stage(stage_name: String, state: GenState,
		rng: RandomNumberGenerator) -> Dictionary:
	match stage_name:
		"config":
			return _stage_config(state, rng)
		"geography":
			return _stage_geography(state, rng)
		"quantize":
			return _stage_quantize(state, rng)
		"hydrology":
			if not state.template.hydrology_enabled:
				return _skip(stage_name, "模板未启用水系阶段（无河世界合法态——WorldData 对应集合恒空）")
			return _stage_hydrology(state, rng)
		"settlement":
			if not state.template.settlement_enabled:
				return _skip(stage_name, "模板未启用聚落阶段（无 POI 世界合法态——WorldData.pois 恒空）")
			return _stage_settlement(state, rng)
		"allegiance":
			if not state.template.allegiance_enabled:
				return _skip(stage_name, "模板未启用势力阶段（归属层关的回退态——states/cell_owners 恒空）")
			return _stage_allegiance(state, rng)
		"roads":
			if not state.template.roads_enabled:
				return _skip(stage_name, "模板未启用道路阶段（无路世界合法态——roads/crossings 恒空）")
			return _stage_roads(state, rng)
		"playability":
			return _stage_playability(state, rng)
		"presentation":
			return _skip(stage_name, "表现派生产物未解锁（首产物随国界线 mesh——格级 owner 与跳变边数据已就绪）")
	var bad := _fail("未知阶段名 %s（STAGES 合同被破坏——生成器 bug）" % stage_name)
	bad["diagnostics"] = {"stage": stage_name, "version": -1, "summary": "unknown"}
	return bad


## 跳过段诊断（空集合合法的显式面——「关闭一个尚未实现能力不产生伪字段」）。
static func _skip(stage_name: String, reason: String) -> Dictionary:
	return {"ok": true, "error": "", "diagnostics": {
		"stage": stage_name,
		"version": STAGE_VERSIONS[stage_name],
		"skipped": true,
		"reason": reason,
		"summary": "skipped",
	}}


# ---------------- ① 配置校验 ----------------

## 参数硬边界（MapGenParams.validate）+ 模板硬边界（WorldTemplate.validate，
## 含 locked 格式）全列——不产半图；冲突串全列是 WORLD-01 测试锚「配置冲突
## 显式失败」的落点。本阶段无随机消耗（确定性校验）。
static func _stage_config(state: GenState, _rng: RandomNumberGenerator) -> Dictionary:
	var problems: Array[String] = []
	var perr := state.params.validate()
	if perr != "":
		problems.append("参数非法：%s" % perr)
	var terr := state.template.validate()
	if terr != "":
		problems.append(terr)
	# 依赖序声明：势力/道路阶段消费聚落产物——聚落关而势力/路开 = 配置冲突
	# （不产半图；Azgaar「执行顺序即依赖图」的配置面）
	if state.template.allegiance_enabled and not state.template.settlement_enabled:
		problems.append("模板 %s 势力阶段开启但聚落阶段关闭（allegiance 依赖 settlement 产物——请同时开启或关闭）"
			% state.template.template_id)
	if state.template.roads_enabled and not state.template.settlement_enabled:
		problems.append("模板 %s 道路阶段开启但聚落阶段关闭（roads 依赖 settlement 产物——请同时开启或关闭）"
			% state.template.template_id)
	if not problems.is_empty():
		return {"ok": false, "error": "；".join(problems), "diagnostics": {
			"stage": "config", "version": STAGE_VERSIONS["config"],
			"summary": "invalid（%d 项，全列见 error）" % problems.size(),
		}}
	return {"ok": true, "error": "", "diagnostics": {
		"stage": "config", "version": STAGE_VERSIONS["config"],
		"summary": "template=%s seed=%d %dx%d" % [state.template.template_id,
			state.seed_value, state.params.width, state.params.height],
	}}


# ---------------- ② 地理骨架（双噪声）----------------

## 双噪声连续场采样（拍板①：不做抬升/下挖，frontier 排除——双噪声唯一路线）：
## 高度场 = params.noise_type/frequency/octaves；植被/地表掩码场 = simplex
## 第二通道（seed+VEGETATION_SEED_OFFSET，修订记录三之 7 改名保留）。采样点 =
## 格心世界 XZ（空间连贯随六边形几何走）；遍历序 = MapData 固定遍历序（确定性）。
## rng 通道不消耗（连续场即随机源；通道传入仅为签名统一——离散随机的独立性
## 由通道结构保证，与本阶段无关）。
static func _stage_geography(state: GenState, _rng: RandomNumberGenerator) -> Dictionary:
	var params := state.params
	var height_noise := FastNoiseLite.new()
	height_noise.seed = params.seed
	height_noise.noise_type = params.noise_type
	height_noise.frequency = params.frequency
	height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	height_noise.fractal_octaves = params.fractal_octaves

	var vegetation_noise := FastNoiseLite.new()
	vegetation_noise.seed = params.seed + VEGETATION_SEED_OFFSET
	vegetation_noise.noise_type = VEGETATION_NOISE_TYPE
	vegetation_noise.frequency = params.vegetation_frequency
	vegetation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	vegetation_noise.fractal_octaves = VEGETATION_OCTAVES

	state.map = MapDataClass.new(params.width, params.height)
	var cells := state.map.cells()
	state.heights.resize(cells.size())
	state.mask.resize(cells.size())
	for i in cells.size():
		var w := Hex.axial_to_world(cells[i], 1.0)
		var h := float(height_noise.get_noise_2d(w.x, w.z))
		var mv := float(vegetation_noise.get_noise_2d(w.x, w.z))
		state.heights[i] = h
		state.mask[i] = mv
		state.h_min = minf(state.h_min, h)
		state.h_max = maxf(state.h_max, h)
		state.m_min = minf(state.m_min, mv)
		state.m_max = maxf(state.m_max, mv)
	return {"ok": true, "error": "", "diagnostics": {
		"stage": "geography", "version": STAGE_VERSIONS["geography"],
		"summary": "cells=%d h=[%s,%s] mask=[%s,%s]" % [cells.size(),
			"%f" % state.h_min, "%f" % state.h_max,
			"%f" % state.m_min, "%f" % state.m_max],
	}}


# ---------------- ③ 地貌整形（量化）----------------

## 归一化 → 量化整数高程 → 地表分类 → 写 MapData。归一化而非假定 ±1 界内：
## 部分 cellular 噪声输出可超 ±1，任何噪声类型一律以本图实际值域归一（04
## M1a-T9 细化）。分母为零（噪声恒定输出，理论罕见）→ 全部取中值 0.5（行为
## 确定，不构成隐性随机）。分类表 = 内容层口味（变更 = GENERATOR_VERSION+1）。
## 高程唯一来源 = 双噪声 + 量化（修订记录三之 5：无 BFS 重写、无局部极小整形）。
static func _stage_quantize(state: GenState, _rng: RandomNumberGenerator) -> Dictionary:
	var params := state.params
	var map := state.map
	var cells := map.cells()
	var h_range := state.h_max - state.h_min
	var m_range := state.m_max - state.m_min
	var write_failures := 0
	for i in cells.size():
		var cell := cells[i]
		var n := (float(state.heights[i]) - state.h_min) / h_range if h_range > 0.0 else 0.5
		var level := 0
		var terrain := TERRAIN_WATER
		var passable := false
		if n >= params.sea_level:
			var t := (n - params.sea_level) / (1.0 - params.sea_level)
			level = clampi(int(t * float(params.elevation_levels)), 0, params.elevation_levels - 1) + 1
			var m := (float(state.mask[i]) - state.m_min) / m_range if m_range > 0.0 else 0.5
			terrain = _classify_terrain(level, params.elevation_levels, m)
			passable = true
		if not map.set_elevation(cell, level):
			write_failures += 1
		if not map.set_terrain(cell, terrain):
			write_failures += 1
		if not map.set_passable(cell, passable):
			write_failures += 1
	if write_failures > 0:
		return {"ok": false, "error": "写入失败 %d 次（界内格写入不应失败，生成器 bug）"
			% write_failures, "diagnostics": {"stage": "quantize",
			"version": STAGE_VERSIONS["quantize"], "summary": "write_failures=%d" % write_failures}}
	return {"ok": true, "error": "", "diagnostics": {
		"stage": "quantize", "version": STAGE_VERSIONS["quantize"],
		"summary": "terrain=%s elevation=%s" % [
			_canonical_counts(_value_counts(map, "terrain")),
			_canonical_counts(_value_counts(map, "elevation"))],
	}}


## 地表分类表（内容层口味；变更 = GENERATOR_VERSION+1）：顶档 → 岩；第 1 档 →
## 沙/泥（掩码）；中档 → 草/林（掩码）。
static func _classify_terrain(level: int, levels: int, vegetation: float) -> int:
	if level >= levels:
		return TERRAIN_ROCK
	if level == 1:
		return TERRAIN_MUD if vegetation > VEGETATION_MUD_THRESHOLD else TERRAIN_SAND
	return TERRAIN_FOREST if vegetation > VEGETATION_FOREST_THRESHOLD else TERRAIN_GRASS


# ---------------- ④ 河网与水体（WORLD-02）----------------

## 河口反向生长河网（RiverNetworkGenerator）：产出直接落 reach.edges 边序列
## （终态事实）；**量化后二次验证**（离散高程上全量 WorldData.validate——
## 水面单调/河床容纳/河口对账/角点级无环的重验，方案 ⑤；构造已保证合法，
## 此处失败即生成器 bug，具名失败不静默放行）。随机消耗 = hydrology 通道
## （河口水序挑选——通道独立性的消费面）。
static func _stage_hydrology(state: GenState, rng: RandomNumberGenerator) -> Dictionary:
	var cfg := {
		"river_count": state.template.river_count,
		"river_max_edges": state.template.river_max_edges,
		"min_mouth_spacing": state.template.min_mouth_spacing,
		"river_flow_level": state.template.river_flow_level,
		"water_terrain_id": TERRAIN_WATER,
	}
	var result := RiverGenClass.generate(state.map, rng, cfg)
	if not result["ok"]:
		return {"ok": false, "error": "河网生成失败：%s" % result["error"],
			"diagnostics": {"stage": "hydrology", "version": STAGE_VERSIONS["hydrology"],
			"summary": "failed：%s" % result["error"]}}
	# 逐元素转类型化集合（生成器返回 Array——WorldData 字段是 typed Array，
	# 元素级搬运即形状核对，不做整引用赋值）
	var rivers: Array[WorldDataClass.RiverReachData] = []
	for r in result["rivers"]:
		rivers.append(r)
	var bodies: Array[WorldDataClass.WaterBodyData] = []
	for b in result["water_bodies"]:
		bodies.append(b)
	var links: Array[WorldDataClass.NeighborLinkData] = []
	for lk in result["links"]:
		links.append(lk)
	state.world.rivers = rivers
	state.world.water_bodies = bodies
	state.world.links = links
	# 量化后二次验证（water_terrain_id = 3 号水槽对账；阈值面未启用 = -1 不查）
	var verdict := state.world.validate(state.map, TERRAIN_WATER, -1, -1)
	if verdict != "":
		return {"ok": false, "error": "量化后二次验证失败：%s" % verdict,
			"diagnostics": {"stage": "hydrology", "version": STAGE_VERSIONS["hydrology"],
			"summary": "post_quantum_invalid：%s" % verdict}}
	var stats: Dictionary = result["stats"]
	var stops: Dictionary = stats["stop_reasons"]
	return {"ok": true, "error": "", "diagnostics": {
		"stage": "hydrology", "version": STAGE_VERSIONS["hydrology"],
		"summary": "bodies=%d(sea=%d,lake=%d) reaches=%d edges=%d stop=no_candidate:%d,budget:%d,map_edge:%d"
			% [stats["bodies"], stats["sea"], stats["lake"], stats["reaches"],
				stats["total_edges"], stops[RiverGenClass.STOP_NO_CANDIDATE],
				stops[RiverGenClass.STOP_BUDGET], stops[RiverGenClass.STOP_MAP_EDGE]],
		"post_quantum_valid": true,
	}}


# ---------------- ⑤ 聚落与占点（WORLD-03）----------------

## SettlementGenerator.place_settlements：适居度前列带偏置抽取 + 最小环距 +
## 7 格落兵区 + 资源占位。随机消耗 = poi 通道（偏置抽取唯一消耗点——通道独立
## 性锚面）。失败具名（NO_VALID_SPAWN / NO_RESOURCE_SITE）→ 阶段失败即管线
## 失败（修复循环在 generate_validated 层接管）。
static func _stage_settlement(state: GenState, rng: RandomNumberGenerator) -> Dictionary:
	var t := state.template
	var cfg := {
		"water_terrain_id": TERRAIN_WATER,
		"spawn_count": t.spawn_count,
		"resource_count": t.resource_count,
		"resource_budget": t.resource_budget,
		"expansionism": t.state_expansionism,
		"state_river_cost": t.state_river_cost,
		"sea_level": t.sea_level,
		"elevation_levels": t.elevation_levels,
		# 修复注入面（直跑 = 空——零修复口径；generate_validated 传入锁定锚定）
		"locked_cells": state.repair_ctx.get("locked_cells", []),
		"pinned": state.repair_ctx.get("pinned", {}),
	}
	var result := SettlementGenClass.place_settlements(state.map, state.world, rng, cfg)
	if not result["ok"]:
		return {"ok": false, "error": "聚落生成失败：%s" % result["error"],
			"diagnostics": {"stage": "settlement",
			"version": STAGE_VERSIONS["settlement"],
			"summary": "failed：%s" % result["error"]}}
	var pois: Array[WorldDataClass.POIData] = []
	for p in result["pois"]:
		pois.append(p)
	state.world.pois = pois
	var stats: Dictionary = result["stats"]
	return {"ok": true, "error": "", "diagnostics": {
		"stage": "settlement", "version": STAGE_VERSIONS["settlement"],
		"summary": "pois=%d(spawn=%d,resource=%d) anchors=%s spacing=%s" % [
			pois.size(), t.spawn_count, int(stats["resources"].size()),
			str(stats["spawn_anchors"]), str(stats["spawn_spacings"])],
		# 结构化档距（测试锚消费面：组间环距 ≥ 实际使用档距的断言取数处——与
		# hydrology 段 post_quantum_valid 同款「摘要串 + 结构化键」先例）
		"spawn_spacings": (stats["spawn_spacings"] as Array).duplicate(),
	}}


# ---------------- ⑥ 势力归属（WORLD-03）----------------

## SettlementGenerator.grow_states：主城多源 Dijkstra（§7 states 版成本表 +
## 河界加成）+ normalize 多数滤波。确定性阶段（无随机消耗）；水格恒中立。
static func _stage_allegiance(state: GenState, _rng: RandomNumberGenerator) -> Dictionary:
	var t := state.template
	var cfg := {
		"water_terrain_id": TERRAIN_WATER,
		"spawn_count": t.spawn_count,
		"resource_count": t.resource_count,
		"resource_budget": t.resource_budget,
		"expansionism": t.state_expansionism,
		"state_river_cost": t.state_river_cost,
		"sea_level": t.sea_level,
		"elevation_levels": t.elevation_levels,
		"locked_cells": state.repair_ctx.get("locked_cells", []),
		"owner_pins": state.repair_ctx.get("owner_pins", {}),
	}
	var result := SettlementGenClass.grow_states(state.map, state.world, cfg)
	if not result["ok"]:
		return {"ok": false, "error": "势力生成失败：%s" % result["error"],
			"diagnostics": {"stage": "allegiance",
			"version": STAGE_VERSIONS["allegiance"],
			"summary": "failed：%s" % result["error"]}}
	var states_out: Array[WorldDataClass.StateData] = []
	for s in result["states"]:
		states_out.append(s)
	state.world.states = states_out
	state.world.cell_owners = result["cell_owners"]
	var stats: Dictionary = result["stats"]
	return {"ok": true, "error": "", "diagnostics": {
		"stage": "allegiance", "version": STAGE_VERSIONS["allegiance"],
		"summary": "states=%d owned=%d neutral=%d flips=%d passes=%d" % [
			states_out.size(), stats["owned_cells"], stats["neutral_cells"],
			stats["normalize_flips"], stats["normalize_passes"]],
	}}


# ---------------- ⑦ 道路骨架（WORLD-05）----------------

## RoadNetworkGenerator：聚落图 MST + 桥址搜索 + 可选回路（每次加路后全量重验
## 在生成器内部逐路执行）。随机消耗 = roads 通道（等成本改道并列——v4 起的唯一
## 消耗点：拓扑/桥址仍是确定性算法，通道只影响并列路径取舍）；失败具名
## （ROAD_NETWORK_DISCONNECTED 指向聚落对与河段）→ 管线失败（修复循环接管）。
static func _stage_roads(state: GenState, rng: RandomNumberGenerator) -> Dictionary:
	var t := state.template
	var cfg := {
		"water_terrain_id": TERRAIN_WATER,
		"max_road_delta": t.max_road_delta,
		"max_bridge_bank_delta": t.max_bridge_bank_delta,
		"road_loop_count": t.road_loop_count,
		"sea_level": t.sea_level,
		"elevation_levels": t.elevation_levels,
		"locked_cells": state.repair_ctx.get("locked_cells", []),
	}
	var result := RoadGenClass.generate(state.map, state.world, cfg, rng)
	if not result["ok"]:
		return {"ok": false, "error": "路网生成失败：%s" % result["error"],
			"diagnostics": {"stage": "roads", "version": STAGE_VERSIONS["roads"],
			"summary": "failed：%s" % result["error"]}}
	var roads: Array[WorldDataClass.RoadData] = []
	for r in result["roads"]:
		roads.append(r)
	var crossings: Array[WorldDataClass.CrossingData] = []
	for c in result["crossings"]:
		crossings.append(c)
	var links: Array[WorldDataClass.NeighborLinkData] = []
	for lk in result["links"]:
		links.append(lk)
	state.world.roads = roads
	state.world.crossings = crossings
	state.world.links = links
	var stats: Dictionary = result["stats"]
	return {"ok": true, "error": "", "diagnostics": {
		"stage": "roads", "version": STAGE_VERSIONS["roads"],
		"summary": "roads=%d(trunk=%d,loop=%d) crossings=%d tier2=%s links=%d" % [
			roads.size(), stats["trunk"], stats["loops"], crossings.size(),
			str(stats["tier2_used"]), links.size()],
	}}


# ---------------- ⑧ 可玩校验（WORLD-04）----------------

## 可玩校验 = MapConnectivity 连通性（旧行为继承——断路/孤岛只进报告）+
## WorldValidator 结构化报告（WORLD-04 落码：错误 {code, cell_ids, link_ids,
## constraint_id, explanation} 指向具体对象）。**报告通道不判管线失败**：失败
## 产物仍产出并留证（连通性口径沿旧行为；修复/拒绝在 generate_validated 与
## seed 银行侧消费本报告——「校验失败即明确失败，不伪造达标」的分流点）。
## 模板阈值面（Δ/桥端/预算/路网要求/锁定格）全量透传——生成配置口径。
static func _stage_playability(state: GenState, _rng: RandomNumberGenerator) -> Dictionary:
	state.connectivity = MapConnectivityClass.check(state.map)
	var t := state.template
	state.validation = WorldValidatorClass.validate_report(state.map, state.world, {
		"water_terrain_id": TERRAIN_WATER,
		"max_road_delta": t.max_road_delta if t.roads_enabled else -1,
		"max_bridge_bank_delta": t.max_bridge_bank_delta if t.roads_enabled else -1,
		"require_road_network": t.roads_enabled,
		"resource_budget": t.resource_budget if t.settlement_enabled else 0,
		"locked_cells": t.locked_cells(),
	})
	var conn: Dictionary = state.connectivity
	var errors: Array = state.validation["errors"]
	var codes := PackedStringArray()
	for e in errors:
		codes.append(String(e["code"]))
	return {"ok": true, "error": "", "diagnostics": {
		"stage": "playability", "version": STAGE_VERSIONS["playability"],
		"summary": "conn_ok=%s passable=%d components=%d largest=%d(%d%%) errors=%d[%s]" % [
			str(conn["ok"]), conn["passable_total"], conn["component_count"],
			conn["largest_size"], int(round(float(conn["largest_fraction"]) * 100.0)),
			errors.size(), ",".join(codes)],
	}}


# ---------------- 产物组装 ----------------

## 退化特例产物：键集与旧单遍 map_generator 逐键一致（行为不变锚的一部分——
## CLI/tests 消费面零感知）；world/stages 为新增只读面。
static func _legacy_result(state: GenState, stages_out: Array) -> Dictionary:
	var meta := {
		"kind": "random",
		"generator_version": GENERATOR_VERSION,
		"params": state.params.to_dict(),
		"digest": state.map.digest(),
		"engine_version": String(Engine.get_version_info()["string"]),
		"reproducibility_note": "same seed+params reproduces only with generator_version %d "
			% GENERATOR_VERSION + "on the same engine build (FastNoiseLite output may change "
			+ "across Godot versions)",
		"connectivity": MapConnectivityClass.summary_of(state.connectivity),
		"terrain_counts": _value_counts(state.map, "terrain"),
		"elevation_counts": _value_counts(state.map, "elevation"),
	}
	return {"ok": true, "error": "", "map": state.map, "meta": meta,
		"connectivity": state.connectivity, "validation": state.validation,
		"world": state.world, "stages": stages_out}


## 九阶段产物：WorldData.meta 按 §10 字段集落码（world_digest 只覆盖世界事实、
## 不含 meta——先算后填）；first_pass_valid = 校验报告 + 连通性一次过；
## attempt/repair 在 generate_validated 成功路径回填（直跑 = 1/0 基线值）。
## generation_ms_by_stage = 逐阶段耗时（ms）走**诊断通道**（§8.4/§10 禁止项：
## 生成耗时类不进 WorldMeta——与 stages 诊断分离、独立键，阶段诊断 dict 保持
## 同 seed 可 diff）。legacy 产物不带此键（键集与旧单遍 map_generator 逐键一致
## 的行为不变锚）。
static func _world_result(state: GenState, stages_out: Array,
		ms_by_stage: Dictionary) -> Dictionary:
	var config_digest := ("%s|%s" % [JSON.stringify(state.template.to_dict()),
		JSON.stringify(state.params.to_dict())]).sha256_text()
	var world_valid: bool = state.validation["ok"]
	var conn_ok: bool = state.connectivity["ok"]
	state.world.meta = {
		"schema_version": WorldDataClass.SCHEMA_VERSION,
		"seed": state.seed_value,
		"generator_version": GENERATOR_VERSION,
		"rules_version": 0,
		"engine_version": String(Engine.get_version_info()["string"]),
		"config_digest": config_digest,
		"world_digest": state.world.world_digest(state.map),
		"attempt_count": 1,
		"repair_count": 0,
		"first_pass_valid": world_valid and conn_ok,
	}
	return {"ok": true, "error": "", "map": state.map, "world": state.world,
		"meta": state.world.meta.duplicate(), "connectivity": state.connectivity,
		"validation": state.validation, "stages": stages_out,
		"generation_ms_by_stage": ms_by_stage.duplicate()}


# ---------------- 内部 ----------------

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "map": null, "meta": {}, "connectivity": {},
		"validation": {"ok": false, "errors": [{"code": "PIPELINE_FAILED",
			"cell_ids": [], "link_ids": [], "constraint_id": "",
			"explanation": error}]},
		"world": null, "stages": []}


## 分布计数的规范序串（键升序——阶段摘要可 diff 的前提）。
static func _canonical_counts(counts: Dictionary) -> String:
	var parts := PackedStringArray()
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		parts.append("%d:%d" % [int(k), int(counts[k])])
	return ",".join(parts)


static func _value_counts(map: MapDataClass, field: String) -> Dictionary:
	var counts := {}
	for cell in map.cells():
		var v: int = map.terrain_at(cell) if field == "terrain" else map.elevation_at(cell)
		counts[v] = int(counts.get(v, 0)) + 1
	return counts
