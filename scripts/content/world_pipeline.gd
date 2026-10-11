## world_pipeline.gd — 世界生成管线编排器（T5 WORLD-01；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-01 + 主创拍板⑧
##   「WORLD 侧按 Azgaar 思路重构」+ 拍板④「不造气候」）
## 职责：Azgaar 管线骨架的**去气候九阶段**编排——配置校验 → 地理骨架（双噪声）
##   → 地貌整形（量化）→ 河网与水体（WORLD-02 河口反向生长）→ 聚落与占点
##   （WORLD-03 未解锁）→ 势力归属（WORLD-03 未解锁）→ 道路骨架（WORLD-05
##   未解锁）→ 可玩校验（连通性；全量 WorldValidator 属 WORLD-04）→ 表现派生
##   （未解锁，首产物随 WORLD-03 国界线）。每阶段 = 独立纯函数
##   `stage(state, rng_channel) -> {ok, error, diagnostics}`（纯 = 无全局可变
##   状态、无隐藏随机源，跨阶段数据经显式 state 传递）；WorldPipeline 持固定
##   阶段序列 + 逐阶段诊断（Azgaar「无阶段诊断产物」反面教训的补丁，§6 ⑧）。
## 两条入口：
##   - generate_legacy(params)：MapGenerator 旧单遍直行代码的**退化特例**
##     （噪声地理骨架 + 量化 + 可玩校验三段实做，其余六段按模板跳过）——
##     行为不变：同 seed 同参数逐格同图（tests/test_world_pipeline.gd 独立
##     oracle 锚 + tests/test_map_source.gd 既有复现锚）；
##   - generate_world(template, seed, channel_overrides)：九阶段全开面
##     （已实现段实做、未解锁段显式跳过——「关闭一个尚未实现能力不产生伪
##     字段」：跳过阶段的 WorldData 对应集合恒空）。
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

## 生成器版本：管线步骤、分类表、参数语义任一变更时 +1（meta 落盘，复现口径
## 的锚）。v2 = WORLD-01 管线化（单遍 → 九阶段退化特例）+ 湿度通道改名
## 「植被/地表掩码」（修订记录三之 7；通道 seed 偏移值原样继承，输出不漂移——
## 版本 +1 是管线结构变更的显式登记，同 map_generator.gd:31 先例纪律）。
const GENERATOR_VERSION := 2

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
	"settlement",    # ⑤ 聚落与占点（WORLD-03 未解锁——恒跳过）
	"allegiance",    # ⑥ 势力归属（WORLD-03 未解锁——恒跳过）
	"roads",         # ⑦ 道路骨架（WORLD-05 未解锁——恒跳过）
	"playability",   # ⑧ 可玩校验（连通性；全量 WorldValidator 属 WORLD-04）
	"presentation",  # ⑨ 表现派生（未解锁——首产物随 WORLD-03 国界线）
]

## 阶段版本（独立于 GENERATOR_VERSION 的逐阶段算法版本——阶段输出规范序摘要
## 的可 diff 前提；阶段算法变更时 +1，Azgaar 复现性破坏教训的细粒度锚）
const STAGE_VERSIONS := {
	"config": 1, "geography": 1, "quantize": 1, "hydrology": 1,
	"settlement": 1, "allegiance": 1, "roads": 1, "playability": 1,
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
## 随机：地理/量化 = 确定性噪声与数学，通道传入仅为签名统一）
const STAGE_CHANNEL := {
	"config": "geography", "geography": "geography", "quantize": "geography",
	"hydrology": "hydrology", "settlement": "poi", "allegiance": "poi",
	"roads": "roads", "playability": "geography", "presentation": "decoration",
}

## 未解锁阶段的跳过原因（配置校验拒绝「开而未解锁」——显式失败不产伪字段）
const UNLOCKED_STAGES := {"settlement": "WORLD-03", "allegiance": "WORLD-03", "roads": "WORLD-05"}


## 跨阶段显式状态（阶段间数据传递的唯一通道——「跨阶段状态耦合」的对策面：
## 一切共享数据在此显式声明，无隐藏全局）。阶段函数只读入参、只经本对象与
## 返回值产出（纯函数口径：同 state 同 rng → 同结果）。
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
	var seed_value := 0                    # root seed（通道派生源）


# ---------------- 入口 ----------------

## 九阶段全开面入口：模板 → 运行参数（apply_to_params 唯一投射线）→ 逐阶段
## 执行。channel_overrides: {通道名: int}——单通道 seed 显式覆盖（通道独立性
## 测试锚的抓手：改 decoration 不应动 hydrology 输出）。
## 返回 {"ok", "error", "map", "world", "meta"（WorldData.meta 同源 dict）,
##   "connectivity", "stages"（Array[Dictionary] 逐阶段诊断，序 = STAGES）}。
static func generate_world(template: WorldTemplateClass, seed_value: int,
		channel_overrides := {}) -> Dictionary:
	if template == null:
		return _fail("模板为 null（generate_world 须持 WorldTemplate）")
	var params := template.apply_to_params(seed_value)
	return _run(params, template, seed_value, channel_overrides, false)


## 退化特例入口：MapGenerator.generate 的管线面（行为不变锚——同 seed 同参数
## 逐格同图；meta 键集与旧单遍版逐键一致）。模板 = legacy（一切可选阶段关），
## 参数直入（不经模板投影——旧 API 的参数即事实源）。
static func generate_legacy(params: MapGenParamsClass) -> Dictionary:
	return _run(params, WorldTemplateClass.make_legacy(), params.seed, {}, true)


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
		seed_value: int, channel_overrides: Dictionary, legacy: bool) -> Dictionary:
	var state := GenState.new()
	state.params = params
	state.template = template
	state.seed_value = seed_value
	state.world = WorldDataClass.empty()

	var channels := {}
	for ch in CHANNELS:
		var rng := RandomNumberGenerator.new()
		rng.seed = channel_seed(seed_value, ch, channel_overrides)
		channels[ch] = rng

	var stages_out: Array = []
	for stage_name in STAGES:
		var result: Dictionary = _run_stage(stage_name, state, channels[STAGE_CHANNEL[stage_name]])
		stages_out.append(result["diagnostics"])
		if not result["ok"]:
			var fail := _fail(result["error"])
			fail["stages"] = stages_out
			return fail
	if legacy:
		return _legacy_result(state, stages_out)
	return _world_result(state, stages_out)


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
		"settlement", "allegiance", "roads":
			# 配置校验已拒绝「开而未解锁」，此处到达即未开——跳过原因指明解锁卡
			return _skip(stage_name, "未启用（%s 未解锁——没有能力就没有数据）"
				% UNLOCKED_STAGES[stage_name])
		"playability":
			return _stage_playability(state, rng)
		"presentation":
			return _skip(stage_name, "表现派生产物未解锁（首产物随 WORLD-03 国界线）")
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

## 参数硬边界（MapGenParams.validate）+ 模板硬边界（WorldTemplate.validate）+
## 冲突全列（开而未解锁的阶段逐条点名——不产半图；冲突串全列是 WORLD-01
## 测试锚「配置冲突显式失败」的落点）。本阶段无随机消耗（确定性校验）。
static func _stage_config(state: GenState, _rng: RandomNumberGenerator) -> Dictionary:
	var problems: Array[String] = []
	var perr := state.params.validate()
	if perr != "":
		problems.append("参数非法：%s" % perr)
	var terr := state.template.validate()
	if terr != "":
		problems.append(terr)
	var stage_toggles := {
		"settlement": state.template.settlement_enabled,
		"allegiance": state.template.allegiance_enabled,
		"roads": state.template.roads_enabled,
	}
	for stage_name in UNLOCKED_STAGES:
		if stage_toggles[stage_name]:
			problems.append("模板 %s 开启了未解锁阶段 %s（%s——没有能力就没有数据；"
				% [state.template.template_id, stage_name, UNLOCKED_STAGES[stage_name]]
				+ "置 false 或等该卡落地）")
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


# ---------------- ⑧ 可玩校验 ----------------

## 可玩校验首版 = 连通性检查（断路/孤岛不改图，只进报告与 meta——旧行为口径
## 继承；连通性失败不判管线失败：那是合法产物并留证，generate_map CLI 分流）。
## 全量 WorldValidator（错误码/修复循环/attempt 上限）属 WORLD-04。
static func _stage_playability(state: GenState, _rng: RandomNumberGenerator) -> Dictionary:
	state.connectivity = MapConnectivityClass.check(state.map)
	var conn: Dictionary = state.connectivity
	return {"ok": true, "error": "", "diagnostics": {
		"stage": "playability", "version": STAGE_VERSIONS["playability"],
		"summary": "ok=%s passable=%d components=%d largest=%d(%d%%)" % [
			str(conn["ok"]), conn["passable_total"], conn["component_count"],
			conn["largest_size"], int(round(float(conn["largest_fraction"]) * 100.0))],
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
		"connectivity": state.connectivity, "world": state.world, "stages": stages_out}


## 九阶段产物：WorldData.meta 按 §10 字段集落码（world_digest 只覆盖世界事实、
## 不含 meta——先算后填）；attempt/repair/first_pass 三字段本版取直通值
## （修复循环属 WORLD-04——first_pass_valid = 校验+连通一次过）。
static func _world_result(state: GenState, stages_out: Array) -> Dictionary:
	var config_digest := ("%s|%s" % [JSON.stringify(state.template.to_dict()),
		JSON.stringify(state.params.to_dict())]).sha256_text()
	var world_valid := state.world.validate(state.map, TERRAIN_WATER, -1, -1)
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
		"first_pass_valid": world_valid == "" and conn_ok,
	}
	return {"ok": true, "error": "", "map": state.map, "world": state.world,
		"meta": state.world.meta.duplicate(), "connectivity": state.connectivity,
		"stages": stages_out}


# ---------------- 内部 ----------------

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "map": null, "meta": {}, "connectivity": {},
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
