## world_template.gd — 世界生成模板 Resource（T5 WORLD-01；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-01 ③ + 提案 yaml 模板结构
##   去气候重定；TerrainStyle 资源化先例 terrain_style.gd——「换 .tres = 换生成
##   口径，世界事实判定只认 seed+模板+版本」）
## 职责：把「这张图按什么口径生成」钉成一个资源（.tres，检查器可换）——
##   template_id 身份 + terrain_route 地形路线开关（T6 拍板 2026-10-13：regions
##   并列路线；~~双噪声唯一路线~~ 排他表述已被 T6 执行方案取代注作废——本组
##   默认仍双噪声 = 既有模板零漂移）+ dimensions 尺寸组 + geography 地理组
##   （双噪声数值）+ regions 宏观分区组（T6 S3 分区骨架 + S4 孤峰/侵蚀子组 +
##   S5 验收子组——WorldValidator 区域检查码的阈值面，未验证起调值）+ hydrology 水系组
##   （WORLD-02 河口反向生长参数）+ scenario 组（聚落/势力，WORLD-03 解锁：出生
##   区/资源/扩张参数/河界加成；**适宜度子组 T6 S6 第一刀解锁**——与派系名解耦的
##   profile 清单（SuitabilityProfile 子资源，首版山地/平原两内置）+ 阶段开关；
##   聚落阶段 profile 接线与开局保证模式入口 = 后续批次）+ infrastructure 组（道路骨架，
##   WORLD-05 解锁：回路数/高差阈值）+ locked/preferred 约束名列表（**locked v1
##   格式 "cell:<id>"**——WORLD-04 修复循环消费：修复动作不得触碰锁定格）。
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

## regions 路线模板（.tres）路径——T6 S3 宏观分区+地貌骨架路线的 authored 面
##（地形路线开关 + regions 参数组；数值 = 未验证起调值，T6 方案 §10）
const REGIONS_PATH := "res://resources/world/templates/world_template_regions.tres"

# ---- 身份 ----

## 模板身份 id（进 config_digest 与阶段诊断——同 seed 不同模板必须可分辨）
@export var template_id: String = "default_terraces"

# ---- dimensions 组：尺寸（odd-r 矩形口径与 MapData 一致）----

@export var width: int = 60   # 列数
@export var height: int = 40  # 行数

# ---- geography 组：双噪声数值（语义/值域与 MapGenParams 同名字段一致）+ 地形
#      路线开关（T6 拍板 2026-10-13：regions 模板路线为并列路线——默认 dual_noise
#      = 现有模板行为零漂移；legacy 模板钉死 dual_noise 不接 regions 参数组）----

## 地形生成路线（T6 S3）：dual_noise = 现有 FastNoiseLite 双噪声直出（默认——
## 既有模板行为零漂移）；regions = 宏观分区 + 骨架 + 连续高度混合（composition
## 阶段实做，WorldPipeline STAGES ③'）。默认值不变 = 未显式选路线的模板与全部
## 既有 .tres 行为逐格一致
@export var terrain_route: String = "dual_noise"
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

# ---- regions 组：宏观分区与地貌骨架（T6 S3 解锁；仅 terrain_route == "regions"
#      时被 composition 阶段消费——dual_noise 路线不读不验语义外的硬边界。
#      **全部数值 = 未验证起调值**（提案 §首期调参起点 :127-133 起调参考 +
#      T6 方案 §10 默认答案②），调参走模板版本/GENERATOR_VERSION，不是平衡承诺）----

## 目标地貌区域数（宏观分区上限；实际可少于——最小核心面积约束合并小区域，
## 小图不机械套用大图数量，提案 :63；≥2 保证群山/平原两类主导都在）
@export var region_count: int = 4
## 区域最小核心面积（格数下限——低于此值的分区合并进邻域，提案 :63「最小可用
## 区域面积」的分区面）
@export var region_min_core_cells: int = 24
## 过渡宽度档（0..1，相对区域特征尺寸的比例——乘 sqrt(格数/区域数) 得过渡半径
## 格数，钳 [2,16]；提案 :132「相邻较小区域特征尺寸的 10%~20% 起调」）
@export var region_transition_width: float = 0.15
## 每个群山主导区的主山系数上限（有走向的主脊，提案 :67；0 = 该区无主山系——
## 退化为纯基础场抬升，合法但无骨架结构）
@export var mountain_range_count: int = 2
## 每条主山系的支脉数上限（支脉自主脊长出的短脊，提案 :77）
@export var mountain_branch_count: int = 3

# ---- regions 组·孤峰子组（T6 S4 解锁；仅 terrain_route == "regions" 时被
#      composition 阶段消费。**全部数值 = 未验证起调值**（提案 :131 孤峰预算
#      5% 起调 + T6 方案 §10 默认答案④「首版圆锥/岩峰轮廓」），调参走模板版本/
#      GENERATOR_VERSION，不是平衡承诺）----

## 孤峰影响面积预算比例（总影响面积 ≤ 有效平原面积 × 此值；有效平原 = 群山权重
## ≤300‰ 的陆格；0 = 恒零孤峰——小图自然零座合法，提案 :82/:131）
@export var peak_area_budget_ratio: float = 0.05
## 孤峰影响半径（六边形环距——山脚格集 = 距中心 ≤ 此值；峰体横向尺度）
@export var peak_influence_radius: int = 2
## 孤峰峰高（千分整数 1..1000——连续域高度增益；圆锥轮廓顶点增益）
@export var peak_height: int = 550
## 最小间距相对影响半径的倍数（峰间距/避让主山系间距 = ceil(半径 × 此值)，
## 提案 :131「相对于峰体半径的最小间距」；出生落点避让同距——S4 落点侧禁入面）
@export var peak_spacing_radius_scale: float = 2.0

# ---- regions 组·侵蚀子组（T6 S4 解锁；仅 terrain_route == "regions" 且
#      erosion_enabled 时被 erosion 阶段消费——作用于连续高度、投影前；关闭 =
#      阶段跳过、输出与无侵蚀版逐格一致（回退锚）。**全部数值 = 未验证起调值**
#      （提案 :100-109 选择性侵蚀 + §首期调参起点；平原默认关 = 提案 :106
#      「平原：弱侵蚀或关闭侵蚀」的起调档）----

## 侵蚀阶段总开关（false = 跳过阶段——回退态；dual_noise 路线下本开关无效：
## 侵蚀是 regions 路线专属阶段）
@export var erosion_enabled: bool = false
## 群山坡面侵蚀强度（沟壑刻蚀——mw ≥700‰ 档，提案 :104「允许更明显的沟壑」）
@export var erosion_mountain_slope: float = 0.30
## 宽谷/盆地侵蚀强度上限（谷底格取 min(档强度, 此值)——「限制侵蚀造成的割裂，
## 维护可用面积」，提案 :105）
@export var erosion_valley: float = 0.06
## 平原侵蚀强度（默认 0 = 关——大片连贯性优先，提案 :106）
@export var erosion_plain: float = 0.0
## 过渡带侵蚀强度（300‰ < mw < 700‰ 档，提案 :107「分别控制细节强度」）
@export var erosion_transition: float = 0.12
## 海岸带侵蚀强度上限（贴海陆格取 min(档强度, 此值)——「保护整体轮廓」，提案 :107）
@export var erosion_coast: float = 0.10
## 侵蚀差分邻差预算（相邻格侵蚀量之差超过此值 = 破坏坡面连续的局部结果，按
## 确定性规则减弱/回退——复查判据之一，提案 :109）
@export var erosion_max_step: float = 0.15
## 平原起伏预算（侵蚀后平原区连续起伏较侵蚀前最多增长此值——复查判据之二，
## 提案 :109 起伏复查的平原面）
@export var erosion_plain_relief_budget: float = 0.06

# ---- regions 组·验收子组（T6 S5 解锁；WorldValidator 区域验收五码的阈值面——
#      「有配置才判」沿 ROAD-01 先例，管线把本组透传校验器；dual_noise 路线区域
#      事实恒空 = 整组零消费。**全部数值 = 未验证起调值**（提案 §首期调参起点
#      :127-133 起调区间 + §尚待确认②「分类阈值首版自定并进模板」，T6 方案 §10
#      默认答案②），调参走模板版本/GENERATOR_VERSION，不是平衡承诺）----

## 群山区核心地貌占比下限（山地类格数 / 核心格数 ≥ 此值——提案 :129 起调 60%）
@export var mountains_core_ratio_min: float = 0.60
## 群山区核心地貌占比上限（「山地与丘陵合计」≤ 此值——为谷地/盆地留出非山地
## 份额；提案 :129 起调 80%）
@export var mountains_core_ratio_max: float = 0.80
## 平原区核心地貌占比下限（平原类格数 / 核心格数 ≥ 此值——提案 :130 起调 70%）
@export var plains_core_ratio_min: float = 0.70
## 平原区核心地貌占比上限（「平原与缓丘合计」≤ 此值；提案 :130 起调 90%）
@export var plains_core_ratio_max: float = 0.90
## 山地类分类阈值（群山权重 ≥ 此值的陆格计山地/丘陵类——§尚待确认② 分类阈值
## 的模板面；与 regions 视图「群山主导档」同阈起调）
@export var region_mountain_class_weight: float = 0.70
## 山地类高程档下限（陆格高程 / elevation_levels ≥ 此值才计山地类——**分类的
## 高程面**：宽谷/盆地经骨架下切后高程落低档，归非山地类，提案 :129「山地与
## 丘陵合计 60%~80% + 独立保证谷地最小可用面积」的占比/谷地二分靠它成立；
## 0.5 起调 = elevation_levels=4 下高程 ≥2 档）
@export var region_mountain_class_elev_min: float = 0.50
## 平原类分类阈值（群山权重 ≤ 此值的陆格计平原/缓丘类——与孤峰有效平原判档
## TerrainComposition.EFFECTIVE_PLAIN_WEIGHT_MAX 同阈起调）
@export var region_plain_class_weight: float = 0.30
## 区域核心最大可用连通片下限（核心通行格的最大连通片占比 ≥ 此值——提案 :130
## 「主要通行空间必须形成配置要求的大片连通区域」的机器面）
@export var region_largest_component_ratio: float = 0.60
## 分区边界高程差上限（异区相邻对量化高程差 ≤ 此值——「无区域编号导致的高度
## 断缝」；与 S3 验收锚 Δ≤2 同口径起调）
@export var region_boundary_max_step: int = 2
## 群山区可用谷地下限（通行谷底格数 ≥ 此值；0 = 面积不查但对外通路仍查——
## 通路是布尔硬约束，提案 :272 山地可用性）
@export var region_min_valley_cells: int = 4

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

# ---- scenario 组·适宜度子组（T6 S6 第一刀解锁；关闭 = 跳过阶段，
#      WorldData.faction_suitability 恒空——无候选世界合法态。**profile 参数 =
#      未验证起调值**（提案 :166「本阶段提供配置入口，不杜撰最终平衡数值」），
#      调参走模板版本/GENERATOR_VERSION；**开局保证模式入口未开**（须进
#      config_hash 的要求随该批次落字——聚落接线/开局保证 = 后续批次）----

## 派系适宜度阶段总开关（false = 跳过；faction_suitability 空集合合法。仅
## regions 路线产分区/权重事实——dual_noise 路线下开启也在阶段内按「无区域
## 事实」显式跳过，零漂移）
@export var suitability_enabled: bool = false
## 适宜度 profile 清单（SuitabilityProfile 子资源——与派系名解耦的偏好配置，
## 提案 :146/:254；出现序 = 事实表序。启用阶段时须非空（validate 查）；
## profile 参数进 to_dict/config_digest——「改偏好配置不改基础地形」由地形
## 各阶段不读本组结构性保证，config_digest 可分辨候选事实口径）
@export var suitability_profiles: Array[SuitabilityProfile] = []

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


static func load_regions() -> WorldTemplate:
	return load_at(REGIONS_PATH)


## 代码内默认模板（.tres 的再生成/对账基准——tests 锚定两者口径一致，
## TerrainStyle.make_default_* 同纪律）：可选阶段全开（水系/聚落/势力/道路）。
static func make_default() -> WorldTemplate:
	return new()


## 代码内 regions 路线模板（world_template_regions.tres 的对账基准——同源纪律）：
## 地形路线 = regions + 侵蚀开（composition 阶段实做 + erosion 阶段实做——S4 起
## regions 路线的完整形态）+ **适宜度开（T6 S6 第一刀：山地/平原两个内置
## profile——faction_suitability 事实的 authored 入口）**，九阶段其余开关与默认
## 模板一致；regions/孤峰/侵蚀/适宜度参数组数值 = 未验证起调值（T6 方案 §10
## 默认答案②④ + 提案 :166）。
static func make_regions() -> WorldTemplate:
	var t := new()
	t.template_id = "regions_mountains"
	t.terrain_route = "regions"
	# 以下为 regions 路线起调值（未验证——与 world_template_regions.tres 同源锚）：
	# sea_level 下调 = 骨架增益拉宽值域后补偿有效海面（否则平原半数沉水、陆块
	# 破碎）；max_road_delta 2 = 山口/谷地路线的高差档（双噪声默认图 Δ1 档在
	# 山区不可修路）；erosion_enabled = S4 起调开（关态 = regions_no_erosion 对照
	# 形态，预览工具三路对照的「分区骨架版」入口）；suitability = S6 两内置
	# profile（山地偏好/平原偏好——提案 :144/:145 矮人/人类示例的读法）
	t.sea_level = 0.18
	t.max_road_delta = 2
	t.erosion_enabled = true
	t.suitability_enabled = true
	t.suitability_profiles = [SuitabilityProfile.make_mountain(),
		SuitabilityProfile.make_plain()]
	return t


## 代码内退化特例模板：一切可选阶段关闭——MapGenerator.generate 旧单遍行为的
## 模板面（无河无聚落无路 = §0「段独立可交付」的合法态）。terrain_route 钉死
## "dual_noise"（T6 拍板③：legacy 模板不接 regions 路线，逐格输出字节级不变）；
## 适宜度同关（faction_suitability 恒空——legacy 零漂移面）。
static func make_legacy() -> WorldTemplate:
	var t := new()
	t.template_id = "legacy_single_pass"
	t.terrain_route = "dual_noise"
	t.hydrology_enabled = false
	t.settlement_enabled = false
	t.allegiance_enabled = false
	t.roads_enabled = false
	t.suitability_enabled = false
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
	if terrain_route != "dual_noise" and terrain_route != "regions":
		return "模板 %s terrain_route=%s 非法（dual_noise | regions 两值——T6 并列路线）" \
			% [template_id, terrain_route]
	var err := apply_to_params(1).validate()
	if err != "":
		return "模板 %s 地理参数非法：%s" % [template_id, err]
	# ---- regions 组硬边界（T6 S3；值未验证起调值，边界是能力面不是口味面）----
	if region_count < 2 or region_count > 16:
		return "模板 %s region_count=%d 非法（∈[2,16]——≥2 保证两类主导都在；上限防小图机械套用）" \
			% [template_id, region_count]
	if region_min_core_cells < 1:
		return "模板 %s region_min_core_cells=%d 非法（≥1）" % [template_id, region_min_core_cells]
	if region_transition_width <= 0.0 or region_transition_width > 1.0:
		return "模板 %s region_transition_width=%s 非法（∈(0,1] 相对特征尺寸比例）" \
			% [template_id, str(region_transition_width)]
	if mountain_range_count < 0 or mountain_range_count > 8:
		return "模板 %s mountain_range_count=%d 非法（∈[0,8]）" % [template_id, mountain_range_count]
	if mountain_branch_count < 0 or mountain_branch_count > 8:
		return "模板 %s mountain_branch_count=%d 非法（∈[0,8]）" % [template_id, mountain_branch_count]
	# ---- regions 组·孤峰/侵蚀子组硬边界（T6 S4；值未验证起调值，边界是能力面）----
	if peak_area_budget_ratio < 0.0 or peak_area_budget_ratio > 1.0:
		return "模板 %s peak_area_budget_ratio=%s 非法（∈[0,1]——0 = 恒零孤峰合法态）" \
			% [template_id, str(peak_area_budget_ratio)]
	if peak_influence_radius < 1 or peak_influence_radius > 8:
		return "模板 %s peak_influence_radius=%d 非法（∈[1,8]）" % [template_id, peak_influence_radius]
	if peak_height < 1 or peak_height > 1000:
		return "模板 %s peak_height=%d 非法（千分整数 ∈[1,1000]，WorldData.IsolatedPeakData 同纲）" \
			% [template_id, peak_height]
	if peak_spacing_radius_scale < 1.0:
		return "模板 %s peak_spacing_radius_scale=%s 非法（≥1——间距不小于影响半径）" \
			% [template_id, str(peak_spacing_radius_scale)]
	for strength_field in [["erosion_mountain_slope", erosion_mountain_slope],
			["erosion_valley", erosion_valley], ["erosion_plain", erosion_plain],
			["erosion_transition", erosion_transition], ["erosion_coast", erosion_coast]]:
		var v: float = strength_field[1]
		if v < 0.0 or v > 1.0:
			return "模板 %s %s=%s 非法（侵蚀强度 ∈[0,1]）" % [template_id, strength_field[0], str(v)]
	if erosion_max_step <= 0.0 or erosion_max_step > 1.0:
		return "模板 %s erosion_max_step=%s 非法（∈(0,1] 侵蚀差分邻差预算）" \
			% [template_id, str(erosion_max_step)]
	if erosion_plain_relief_budget < 0.0 or erosion_plain_relief_budget > 1.0:
		return "模板 %s erosion_plain_relief_budget=%s 非法（∈[0,1] 平原起伏预算）" \
			% [template_id, str(erosion_plain_relief_budget)]
	# ---- regions 组·验收子组硬边界（T6 S5；-1 = 显式关闭该界，其余查区间）----
	for ratio_field in [["mountains_core_ratio_min", mountains_core_ratio_min],
			["mountains_core_ratio_max", mountains_core_ratio_max],
			["plains_core_ratio_min", plains_core_ratio_min],
			["plains_core_ratio_max", plains_core_ratio_max],
			["region_largest_component_ratio", region_largest_component_ratio]]:
		var rv: float = ratio_field[1]
		if rv < -1.0 or rv > 1.0:
			return "模板 %s %s=%s 非法（∈[-1,1]——-1 = 不查该界）" \
				% [template_id, ratio_field[0], str(rv)]
	if mountains_core_ratio_min >= 0.0 and mountains_core_ratio_max >= 0.0 \
			and mountains_core_ratio_min > mountains_core_ratio_max:
		return "模板 %s mountains_core_ratio 区间倒置（min %s > max %s）" \
			% [template_id, str(mountains_core_ratio_min), str(mountains_core_ratio_max)]
	if plains_core_ratio_min >= 0.0 and plains_core_ratio_max >= 0.0 \
			and plains_core_ratio_min > plains_core_ratio_max:
		return "模板 %s plains_core_ratio 区间倒置（min %s > max %s）" \
			% [template_id, str(plains_core_ratio_min), str(plains_core_ratio_max)]
	for class_field in [["region_mountain_class_weight", region_mountain_class_weight],
			["region_plain_class_weight", region_plain_class_weight],
			["region_mountain_class_elev_min", region_mountain_class_elev_min]]:
		var cv: float = class_field[1]
		if cv <= 0.0 or cv >= 1.0:
			return "模板 %s %s=%s 非法（∈(0,1) 地貌分类档）" \
				% [template_id, class_field[0], str(cv)]
	if region_plain_class_weight >= region_mountain_class_weight:
		return "模板 %s 分类阈值倒置（plain %s ≥ mountain %s——平原档须低于山地档）" \
			% [template_id, str(region_plain_class_weight), str(region_mountain_class_weight)]
	if region_boundary_max_step < -1 or region_boundary_max_step == 0:
		return "模板 %s region_boundary_max_step=%d 非法（≥1 或 -1 = 不查）" \
			% [template_id, region_boundary_max_step]
	if region_min_valley_cells < -1:
		return "模板 %s region_min_valley_cells=%d 非法（≥0 或 -1 = 不查；0 = 面积不查通路仍查）" \
			% [template_id, region_min_valley_cells]
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
	# ---- scenario 组·适宜度子组（T6 S6 第一刀：启用须有 profile，profile 硬边界
	# 与 id 唯一性在此拦——配置错误不产半图）----
	if suitability_enabled and suitability_profiles.is_empty():
		return "模板 %s suitability_enabled=true 但 profile 清单为空（与派系名解耦 ≠ 无配置——启用即至少一个 profile）" % template_id
	var profile_ids := {}
	for p in suitability_profiles:
		if p == null:
			return "模板 %s suitability_profiles 含 null（.tres 资源槽未解析——显式失败不静默跳过）" % template_id
		var perr: String = p.validate()
		if perr != "":
			return "模板 %s %s" % [template_id, perr]
		if profile_ids.has(p.profile_id):
			return "模板 %s profile_id「%s」重复（同图同 profile 只评一次）" % [template_id, p.profile_id]
		profile_ids[p.profile_id] = true
	if suitability_profiles.size() > 8:
		return "模板 %s suitability_profiles %d 项 > 8（上界防呆——首版两类偏好）" % [template_id, suitability_profiles.size()]
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
		"terrain_route": terrain_route,
		"width": width,
		"height": height,
		"noise_type": noise_type,
		"frequency": frequency,
		"fractal_octaves": fractal_octaves,
		"sea_level": sea_level,
		"elevation_levels": elevation_levels,
		"vegetation_frequency": vegetation_frequency,
		"region_count": region_count,
		"region_min_core_cells": region_min_core_cells,
		"region_transition_width": region_transition_width,
		"mountain_range_count": mountain_range_count,
		"mountain_branch_count": mountain_branch_count,
		"peak_area_budget_ratio": peak_area_budget_ratio,
		"peak_influence_radius": peak_influence_radius,
		"peak_height": peak_height,
		"peak_spacing_radius_scale": peak_spacing_radius_scale,
		"erosion_enabled": erosion_enabled,
		"erosion_mountain_slope": erosion_mountain_slope,
		"erosion_valley": erosion_valley,
		"erosion_plain": erosion_plain,
		"erosion_transition": erosion_transition,
		"erosion_coast": erosion_coast,
	"erosion_max_step": erosion_max_step,
	"erosion_plain_relief_budget": erosion_plain_relief_budget,
	"mountains_core_ratio_min": mountains_core_ratio_min,
	"mountains_core_ratio_max": mountains_core_ratio_max,
	"plains_core_ratio_min": plains_core_ratio_min,
	"plains_core_ratio_max": plains_core_ratio_max,
	"region_mountain_class_weight": region_mountain_class_weight,
	"region_mountain_class_elev_min": region_mountain_class_elev_min,
	"region_plain_class_weight": region_plain_class_weight,
	"region_largest_component_ratio": region_largest_component_ratio,
	"region_boundary_max_step": region_boundary_max_step,
	"region_min_valley_cells": region_min_valley_cells,
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
		"suitability_enabled": suitability_enabled,
		"suitability_profiles": _profiles_to_dicts(),
		"locked": locked.duplicate(),
		"preferred": preferred.duplicate(),
	}


## profile 清单 → dict 清单（config_digest 面：子资源参数全量进哈希——同 seed
## 改 profile 时候选事实口径可分辨；固定键序沿 SuitabilityProfile.to_dict）。
func _profiles_to_dicts() -> Array:
	var out: Array = []
	for p in suitability_profiles:
		out.append(p.to_dict() if p != null else {})
	return out
