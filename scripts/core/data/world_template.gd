## world_template.gd — 世界生成模板 Resource（T5 WORLD-01；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-01 ③ + 提案 yaml 模板结构
##   去气候重定；TerrainStyle 资源化先例 terrain_style.gd——「换 .tres = 换生成
##   口径，世界事实判定只认 seed+模板+版本」）
## 职责：把「这张图按什么口径生成」钉成一个资源（.tres，检查器可换）——
##   template_id 身份 + dimensions 尺寸组 + geography 地理组（双噪声数值——拍板①
##   「不做抬升/下挖，双噪声唯一路线」，故本组无路线开关）+ hydrology 水系组
##   （WORLD-02 河口反向生长参数）+ scenario 组（聚落/势力，WORLD-03 解锁：出生
##   区/资源/扩张参数/河界加成）+ infrastructure 组（道路骨架，WORLD-05 解锁：
##   回路数/高差阈值）+ locked/preferred 约束名列表（**locked v1 格式
##   "cell:<id>"**——WORLD-04 修复循环消费：修复动作不得触碰锁定格）。
## 参数事实源：模板的 geography/dimensions 数值是**authored 默认**，运行时经
##   apply_to_params(seed) 落成 MapGenParams（唯一运行载体）——MapGenParams 不
##   再另有模板层，避免双事实源；scenario/infrastructure 数值（成本表/预算/阈值）
##   均未拍板、随模板重定（§6 WORLD-03 卡内拍板项 + §7 换算注——数值档变更走
##   生成器版本纪律）。
## 与表现层的边界：本资源是**生成器配置**，不是世界事实（草案 §1.2 边界维持——
##   生成器配置不进 WorldData）也不是表现配置（表现派生参数组随其首个产物
##   ——国界线 mesh——再开，届时此处扩 presentation 组）。
## 维护方式（ADR-3 编辑器原生编辑，TerrainStyle 同款）：双击 .tres 在检查器改
##   参数即可；代码内默认（make_default/make_legacy）与 .tres 同源，tests 锚定
##   两者口径一致（防漂移）。纯 Resource：零场景节点、不写任何数据（ADR-2）。
class_name WorldTemplate
extends Resource

const MapGenParamsClass := preload("res://scripts/content/map_gen_params.gd")

## 默认模板（.tres）路径——九阶段全开（水系/聚落/势力/道路四组 enabled；表现
## 派生未解锁恒关——T5 完整管线口径）
const DEFAULT_PATH := "res://resources/world/templates/world_template_default.tres"

## 退化特例模板（.tres）路径——MapGenerator.generate 旧单遍行为的模板面：
## 一切可选阶段关闭（无河无聚落无路世界 = WorldData 空集合的合法态，§0）
const LEGACY_PATH := "res://resources/world/templates/world_template_legacy.tres"

# ---- 身份 ----

## 模板身份 id（进 config_digest 与阶段诊断——同 seed 不同模板必须可分辨）
@export var template_id: String = "default_terraces"

# ---- dimensions 组：尺寸（odd-r 矩形口径与 MapData 一致）----

@export var width: int = 60   # 列数
@export var height: int = 40  # 行数

# ---- geography 组：双噪声数值（语义/值域与 MapGenParams 同名字段一致；无路线
#      开关——拍板①抬升/下挖已排除，frontier 不存在可选面）----

## 高度场噪声类型（FastNoiseLite 枚举；「类型」参数——不同类型直接改地貌形态）
@export var noise_type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX
## 高度场频率（世界单位；低频 → 平缓连绵地貌）
@export var frequency: float = 0.05
## 高度场 FBM 倍频数（越大细节越多、越碎）
@export var fractal_octaves: int = 3
## 归一化高度海面阈值：n < sea_level → 水（值域 [0,1)）
@export var sea_level: float = 0.25
## 陆地高程档数（陆地层 = 1..levels，水体恒 0）
@export var elevation_levels: int = 4
## 植被/地表掩码场频率（第二噪声通道——修订记录三之 7：~~湿度场~~ 改名保留，
## 林/泥地表分类在用；生态语义删除、用途不变；独立通道 seed 偏移见
## WorldPipeline.VEGETATION_SEED_OFFSET）
@export var vegetation_frequency: float = 0.12

# ---- hydrology 组：河网与水体（WORLD-02 河口反向生长；生长偏好参数 = 卡内
#      拍板项「spike 后定默认值」——本版默认为首版实现档，调档 = 改模板不改码）----

## 水系阶段总开关（false = 跳过阶段，WorldData.rivers/water_bodies/links 空——
## 跳过阶段的空集合合法锚）
@export var hydrology_enabled: bool = true
## 目标河数（多次独立生长的上限；实际可少于——无合法河口的图不伪造）
@export var river_count: int = 3
## 单河长度预算（边数上限；预算尽 = 源，WORLD-02 ①停止条件之一）
@export var river_max_edges: int = 24
## 河口间最小六边形环距（多河间距约束——Azgaar burgs 间距思路同族，方案 ②）
@export var min_mouth_spacing: int = 6
## 流量等级（int ≥1）：首版**固定等级**、不依赖汇流分档（简单链无汇流——
## Strahler 随汇流留第二版，修订记录三之 5；等级→河宽属表现参数不进数据）
@export var river_flow_level: int = 1

# ---- scenario 组：聚落/势力（WORLD-03 解锁；关闭 = 跳过阶段，WorldData.pois/
#      states/cell_owners 空——空集合合法态）----

## 聚落阶段总开关（false = 跳过；POI 空集合合法）
@export var settlement_enabled: bool = true
## 势力归属阶段总开关（false = 跳过；states/cell_owners 空——归属层关的回退态）
@export var allegiance_enabled: bool = true
## 出生区数（拍板⑪：1 玩家 + 2 AI——值域单点 3；槽 0 = 玩家）
@export var spawn_count: int = 3
## 资源点数（role 占位——M2 前不编产出/储量/成本；0 = 无资源世界合法）
@export var resource_count: int = 3
## 资源点距出生锚的最大六边形环距（核心资源「允许预算内可达」的预算面，§6
## WORLD-03 目标行；0 = 不查预算只查可达）
@export var resource_budget: int = 10
## 3 势力扩张参数档（§7 文化层裁剪行：「山地势力不下平原」类个性 = 扩张参数
## 差异；进入成本 = cellCost/expansionism；数值未拍板、随模板重定）
@export var state_expansionism: Array[int] = [5, 4, 6]
## 河界加成（无桥有河 link 的归属生长加费——「有河 link 天然河界」§7；数值
## 未拍板、随模板重定）
@export var state_river_cost: int = 20

# ---- infrastructure 组：道路骨架（WORLD-05 解锁；关闭 = 跳过，roads/crossings
#      空 + link 表 road_id 面恒 ID_NONE）----

@export var roads_enabled: bool = true
## 可选回路数上限（§6 WORLD-05 ①「按配置加少量可选回路」；0 = 只建 MST 骨架）
@export var road_loop_count: int = 0
## 修路高差硬上限（Δ > 此值不修路——ROAD-01 ③ 生成配置口径，不进数据；-1 = 不查）
@export var max_road_delta: int = 1
## 桥头两岸高差上限（ROAD-02 ③ 桥址合法性首版 = 桥头/净空；-1 = 不查）
@export var max_bridge_bank_delta: int = 2

# ---- locked/preferred 约束（WORLD-04 修复循环消费面：locked = 修复不得触碰）----

## 锁定约束 id 列表（**v1 格式 = "cell:<id>"**——修复循环解析为锁定格：道路/新
## 放置禁入、归属生长锚定、锚定出生区/资源原样重发；其他前缀 = 模板校验显式
## 拒绝。reach/road 级锁随第二版汇流/修复粒度扩展再开）
@export var locked: Array[String] = []
## 偏好约束 id 列表（软约束——生成侧打分参考，违例不判失败；v1 只承载不消费）
@export var preferred: Array[String] = []


## 载入模板 .tres；路径不存在 / 类型不符 → null（显式失败，调用方判空）。
static func load_at(path: String) -> WorldTemplate:
	var res: Variant = load(path)
	if res is WorldTemplate:
		return res as WorldTemplate
	return null


static func load_default() -> WorldTemplate:
	return load_at(DEFAULT_PATH)


static func load_legacy() -> WorldTemplate:
	return load_at(LEGACY_PATH)


## 代码内默认模板（.tres 的再生成/对账基准——tests 锚定两者口径一致，
## TerrainStyle.make_default_* 同纪律）：可选阶段全开（水系/聚落/势力/道路）。
static func make_default() -> WorldTemplate:
	return new()


## 代码内退化特例模板：一切可选阶段关闭——MapGenerator.generate 旧单遍行为的
## 模板面（无河无聚落无路 = §0「段独立可交付」的合法态）。
static func make_legacy() -> WorldTemplate:
	var t := new()
	t.template_id = "legacy_single_pass"
	t.hydrology_enabled = false
	t.settlement_enabled = false
	t.allegiance_enabled = false
	t.roads_enabled = false
	return t


## locked 列表 → 锁定格集（v1 格式 "cell:<id>"；非法条目 → 空 Array = 调用方
## 应先经 validate() 拒绝——防御性解析，修复循环消费面）。
func locked_cells() -> Array[int]:
	var out: Array[int] = []
	for entry in locked:
		var parts := entry.split(":")
		if parts.size() == 2 and parts[0] == "cell" and parts[1].is_valid_int():
			out.append(int(parts[1]))
	return out


## 模板 → 运行时参数载体（geography/dimensions 数值的唯一投射线；seed 由调用方
## 给——模板不含 seed，同模板不同 seed 是复现验收的对照组）。
func apply_to_params(seed_value: int) -> MapGenParamsClass:
	var p := MapGenParamsClass.new()
	p.seed = seed_value
	p.width = width
	p.height = height
	p.noise_type = noise_type
	p.frequency = frequency
	p.fractal_octaves = fractal_octaves
	p.sea_level = sea_level
	p.elevation_levels = elevation_levels
	p.vegetation_frequency = vegetation_frequency
	return p


## 模板校验：合法返回 ""，非法返回原因串（管线配置校验阶段消费；冲突全列由
## 管线侧汇总，本函数只查硬边界）。数值边界与 MapGenParams.validate 同源
## （经 apply_to_params 走一遍），另查水系/聚落/道路组专属边界与 locked 格式。
func validate() -> String:
	var err := apply_to_params(1).validate()
	if err != "":
		return "模板 %s 地理参数非法：%s" % [template_id, err]
	if river_count < 0:
		return "模板 %s river_count=%d 非法（≥0——0 = 无河世界合法态）" % [template_id, river_count]
	if river_max_edges < 1:
		return "模板 %s river_max_edges=%d 非法（≥1——河口边本身占 1）" % [template_id, river_max_edges]
	if min_mouth_spacing < 0:
		return "模板 %s min_mouth_spacing=%d 非法（≥0）" % [template_id, min_mouth_spacing]
	if river_flow_level < 1:
		return "模板 %s river_flow_level=%d 非法（≥1，§2.2）" % [template_id, river_flow_level]
	# ---- scenario 组（WORLD-03 解锁后的硬边界）----
	if spawn_count != 3:
		return "模板 %s spawn_count=%d 非法（值域单点 3——拍板⑪ 1 玩家 + 2 AI；改动须翻案拍板）" \
			% [template_id, spawn_count]
	if resource_count < 0:
		return "模板 %s resource_count=%d 非法（≥0——0 = 无资源世界合法态）" % [template_id, resource_count]
	if resource_budget < 0:
		return "模板 %s resource_budget=%d 非法（≥0——0 = 不查预算只查可达）" % [template_id, resource_budget]
	if state_expansionism.size() < spawn_count:
		return "模板 %s state_expansionism %d 档 < spawn_count %d（3 势力各一档，§6 WORLD-03 ②）" \
			% [template_id, state_expansionism.size(), spawn_count]
	for e in state_expansionism:
		if e < 1:
			return "模板 %s state_expansionism 含 %d（≥1——成本分母为 0 无意义）" % [template_id, e]
	if state_river_cost < 0:
		return "模板 %s state_river_cost=%d 非法（≥0）" % [template_id, state_river_cost]
	# ---- infrastructure 组（WORLD-05 解锁后的硬边界）----
	if road_loop_count < 0:
		return "模板 %s road_loop_count=%d 非法（≥0——0 = 只建 MST 骨架）" % [template_id, road_loop_count]
	if max_road_delta < -1:
		return "模板 %s max_road_delta=%d 非法（≥0 或 -1 = 不查）" % [template_id, max_road_delta]
	if max_bridge_bank_delta < -1:
		return "模板 %s max_bridge_bank_delta=%d 非法（≥0 或 -1 = 不查）" % [template_id, max_bridge_bank_delta]
	# ---- locked 格式（v1 = "cell:<id>"；其他前缀显式拒绝——能力边界诚实面）----
	for entry in locked:
		var parts := entry.split(":")
		if parts.size() != 2 or parts[0] != "cell" or not parts[1].is_valid_int() or int(parts[1]) < 0:
			return "模板 %s locked 条目「%s」非法（v1 格式 = cell:<非负 int>；reach/road 级锁未开）" \
				% [template_id, entry]
	return ""


## 全参数落 dict（固定键序——config_digest 与「.tres 与代码默认同源」锚的载体）。
func to_dict() -> Dictionary:
	return {
		"template_id": template_id,
		"width": width,
		"height": height,
		"noise_type": noise_type,
		"frequency": frequency,
		"fractal_octaves": fractal_octaves,
		"sea_level": sea_level,
		"elevation_levels": elevation_levels,
		"vegetation_frequency": vegetation_frequency,
		"hydrology_enabled": hydrology_enabled,
		"river_count": river_count,
		"river_max_edges": river_max_edges,
		"min_mouth_spacing": min_mouth_spacing,
		"river_flow_level": river_flow_level,
		"settlement_enabled": settlement_enabled,
		"allegiance_enabled": allegiance_enabled,
		"spawn_count": spawn_count,
		"resource_count": resource_count,
		"resource_budget": resource_budget,
		"state_expansionism": state_expansionism.duplicate(),
		"state_river_cost": state_river_cost,
		"roads_enabled": roads_enabled,
		"road_loop_count": road_loop_count,
		"max_road_delta": max_road_delta,
		"max_bridge_bank_delta": max_bridge_bank_delta,
		"locked": locked.duplicate(),
		"preferred": preferred.duplicate(),
	}
