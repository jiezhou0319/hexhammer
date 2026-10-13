## suitability_profile.gd — 派系适宜度 profile 资源（T6 S6 第一刀：适宜度与候选落点；
##   docs/M1a-terrain-T6-stylized-execution-plan.md §8 + 提案
##   docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md §派系适配
##   :136-166（两阶段选址）与 §数据与确定性合同 :208-211 FactionSuitability——
##   「名称可与现有工程适配」授权下的配置面）
## 职责：把「这一类聚落偏好什么地形、必需什么条件」钉成一个资源（.tres，检查器
##   可换——沿 TerrainStyle/WorldTemplate 资源化先例）：**profile_id 与派系名解耦**
##   （提案 :146 红线「不把派系名称写进基础地貌生成代码」——矮人/人类只是两类
##   偏好的示例读法，资源本身只描述地形偏好与硬条件）。字段两组：
##   - **偏好权重（软目标，提案 :121/:153 评分项）**：landform_affinity（地貌偏好
##     锚点——0=平原极、1=群山极，评分 = 锚点与格群山权重场的接近度）+
##     weight_landform/weight_expansion/weight_water 三项加权（v1 三项：地貌偏好/
##     可扩展空间/水资源；提案的「资源条件/战略位置」两项待玩法确认后随 M2/M3
##     扩，本版不杜撰数值面）；
##   - **必需硬条件（提案 :121 硬约束「面积、通达、水与资源规则中的必需项」）**：
##     min_area_cells（最小可用面积——锚点 district_radius 半径内通行陆格数下限）
##     + require_access（通达——锚点通行连通片须跨 ≥2 个地貌区域，WorldValidator
##     谷地对外通路同口径）+ require_water/water_range（水——最近水源格 BFS 距离
##     ≤ water_range；水源 = 水地形格 ∪ 河岸格）；
##   - **间距与产出面**：min_spacing（同 profile 候选间最小六边形环距；0 = 不查）+
##     max_candidates（候选数上限——事实表有界）。
## 语义边界：本资源是**生成器配置**不进世界事实（草案 §1.2 边界维持——世界事实侧
##   只有 WorldData.FactionSuitability 的 profile_id/候选/拒绝原因）；「偏好只表示
##   适合度，不表示整个区域的归属」（提案 :140）——不预设永久派系领土。**改
##   profile 参数不改基础地形**：适宜度阶段只读地形/水系事实（提案 :140「派系
##   名单变化不应直接改变同一配置下的基础高度」的机器面——profile 数值进模板
##   config_digest，地形各阶段不读它）。
## 维护方式（ADR-3 编辑器原生编辑，TerrainStyle/WorldTemplate 同款）：双击 .tres
##   在检查器改参数即可；代码内默认（make_mountain/make_plain）与 .tres 同源，
##   tests 锚定两者口径一致（防漂移）。**全部数值 = 未验证起调值**（提案 :166
##   「最小可用面积、候选数量、通达目标和资源需求目前均待后续玩法确认。本阶段
##   提供配置入口，不杜撰最终平衡数值」），调参走模板版本/GENERATOR_VERSION。
## 非目标（本刀不做，后续批次）：聚落阶段按 profile 接线（T6 S6 范围⑤——现
##   SettlementGenerator 适居度公式不动）、开局保证模式（T6 S6 范围④——配置
##   入口亦未开，须进 config_hash 的要求随该批次落字）、资源条件/战略位置两项
##   评分（M2/M3 门后）。
## 纯 Resource：零场景节点、不写任何数据（ADR-2；删 scripts/ui/** 不影响本文件
##   与 tests/）。
class_name SuitabilityProfile
extends Resource

## 山地偏好 profile（.tres）路径——提案 :144 矮人示例的读法（倾向群山内部的
## 谷地/盆地/山口附近——机器面 = landform_affinity 高锚点；资源本身不写派系名）
const MOUNTAIN_PATH := "res://resources/world/suitability/suitability_profile_mountain.tres"

## 平原偏好 profile（.tres）路径——提案 :145 人类示例的读法（倾向连贯平原与
## 宽河谷——机器面 = landform_affinity 低锚点）
const PLAIN_PATH := "res://resources/world/suitability/suitability_profile_plain.tres"

# ---- 身份 ----

## profile 身份 id（进 WorldData.FactionSuitability.profile_id 与模板 config_digest
## ——与派系名解耦：仅描述偏好类型，如 mountain_preferring/plain_preferring）
@export var profile_id: String = ""

# ---- 偏好权重组（软目标——评分三件 v1）----

## 地貌偏好锚点（[0,1]：0 = 平原极、1 = 群山极；评分项 = 1 − |格群山权重 − 锚点|，
## 越接近偏好地貌分越高——提案 :153「地貌偏好」项）
@export var landform_affinity: float = 0.5
## 地貌偏好项权重（≥0；三项权重归一后加权和 → 千分整数分数）
@export var weight_landform: float = 0.5
## 可扩展空间项权重（评分项 = district 半径内通行陆格占比——谷地/平原开阔分高、
## 破碎临水分低；提案 :153「可扩展空间」项）
@export var weight_expansion: float = 0.3
## 水资源项权重（评分项 = 距最近水源的衰减——临水满分、超 water_range 零分；
## 提案 :153「水资源」项）
@export var weight_water: float = 0.2

# ---- 硬条件组（必需——不满足即拒绝，具名原因进 rejection_reasons）----

## 最小可用面积（≥1：锚点 district_radius 半径内**通行陆格数**下限——「满足最低
## 可用面积」，提案 :23/:121；7 = 中心+六邻的落兵区形状起调）
@export var min_area_cells: int = 7
## 片区半径（[1,4]：可用面积/可扩展空间的计量盘半径，六边形环距）
@export var district_radius: int = 2
## 通达硬条件（true = 锚点通行连通片须跨 ≥2 个地貌区域——「保留必要可用谷地及
## **对外通路**」的候选面，提案 :117/:121；WorldValidator 谷地对外通路同口径）
@export var require_access: bool = true
## 水硬条件（true = 距最近水源格 ≤ water_range 才合格——「水与资源规则中的
## 必需项」的水面，提案 :121）
@export var require_water: bool = true
## 水源距离上限（≥1 环——水硬条件与水评分项共用的量程；水源 = 水地形格 ∪ 河岸格）
@export var water_range: int = 3

# ---- 间距与产出面 ----

## 同 profile 候选间最小六边形环距（0 = 不设间距；间距只筛候选不拒合格——
## 被间距让位的格仍计入 qualified_count，提案 :153「评分与间距规则共同决定」）
@export var min_spacing: int = 6
## 候选数上限（[1,64]——事实表有界；按（分数降序，cell_id 升序）贪心选取）
@export var max_candidates: int = 4


## 载入 profile .tres；路径不存在/类型不符 → null（显式失败，调用方判空——
## WorldTemplate.load_at 同款契约）。
static func load_at(path: String) -> SuitabilityProfile:
	var res: Variant = load(path)
	if res is SuitabilityProfile:
		return res as SuitabilityProfile
	return null


## 山地偏好代码内默认（suitability_profile_mountain.tres 的对账基准——同源纪律，
## TerrainStyle.make_default_* 同款）。数值 = 未验证起调值：affinity 0.85（群山
## 权重 0.85 处的谷地/山口最合意——权重场不随谷地下切变化，谷底与山脊同权重，
## 山脊陡峭由可扩展空间项拉开的余地在调参中观察）；面积 7 = 七格落兵区形状；
## 间距 6/上限 4 与河间距/候选带起调同族。
static func make_mountain() -> SuitabilityProfile:
	var p := new()
	p.profile_id = "mountain_preferring"
	p.landform_affinity = 0.85
	p.weight_landform = 0.55
	p.weight_expansion = 0.25
	p.weight_water = 0.20
	p.min_area_cells = 7
	p.district_radius = 2
	p.require_access = true
	p.require_water = true
	p.water_range = 3
	p.min_spacing = 6
	p.max_candidates = 4
	return p


## 平原偏好代码内默认（suitability_profile_plain.tres 的对账基准）。数值 = 未验证
## 起调值：affinity 0.15（连贯平原格权重 ~0..0.3 最合意）；可扩展空间权重略高于
## 山地档（平原发展空间优先，提案 :145「道路扩展条件好的位置」）。
static func make_plain() -> SuitabilityProfile:
	var p := new()
	p.profile_id = "plain_preferring"
	p.landform_affinity = 0.15
	p.weight_landform = 0.45
	p.weight_expansion = 0.35
	p.weight_water = 0.20
	p.min_area_cells = 7
	p.district_radius = 2
	p.require_access = true
	p.require_water = true
	p.water_range = 3
	p.min_spacing = 6
	p.max_candidates = 4
	return p


## 硬边界校验：合法返回 ""，非法返回原因串（模板 validate 汇总消费——WorldTemplate
## 同款契约）。边界是能力面不是口味面：权重非负且和 > 0（全零 = 无意义评分）、
## affinity ∈ [0,1]、面积 ≥1、半径 ∈[1,4]（半径过大 = 计量盘失义，上界防呆）、
## 水量程 ≥1（require_water 时；0 距离对陆格恒不可达 = 恒拒绝的伪配置）、
## 候选上限 ∈[1,64]。
func validate() -> String:
	if profile_id.is_empty():
		return "profile_id 为空（与派系名解耦 ≠ 无身份——进事实表与 config_digest 的锚）"
	if landform_affinity < 0.0 or landform_affinity > 1.0:
		return "profile %s landform_affinity=%s 非法（∈[0,1]——0=平原极 1=群山极）" \
			% [profile_id, str(landform_affinity)]
	for weight_field in [["weight_landform", weight_landform],
			["weight_expansion", weight_expansion], ["weight_water", weight_water]]:
		var v: float = weight_field[1]
		if v < 0.0:
			return "profile %s %s=%s 非法（≥0——负权重无意义）" % [profile_id, weight_field[0], str(v)]
	if weight_landform + weight_expansion + weight_water <= 0.0:
		return "profile %s 三项偏好权重全零（评分无意义——至少一项 >0）" % profile_id
	if min_area_cells < 1:
		return "profile %s min_area_cells=%d 非法（≥1——零面积候选 = 伪合格）" \
			% [profile_id, min_area_cells]
	if district_radius < 1 or district_radius > 4:
		return "profile %s district_radius=%d 非法（∈[1,4]——计量盘半径上界防呆）" \
			% [profile_id, district_radius]
	if require_water and water_range < 1:
		return "profile %s require_water 时 water_range=%d 非法（≥1 环——陆格距水源 0 环不可达，恒拒绝的伪配置）" \
			% [profile_id, water_range]
	if water_range < 0:
		return "profile %s water_range=%d 非法（≥0）" % [profile_id, water_range]
	if min_spacing < 0:
		return "profile %s min_spacing=%d 非法（≥0——0 = 不设间距合法）" % [profile_id, min_spacing]
	if max_candidates < 1 or max_candidates > 64:
		return "profile %s max_candidates=%d 非法（∈[1,64]——事实表有界）" \
			% [profile_id, max_candidates]
	return ""


## 全参数落 dict（固定键序——模板 config_digest 与「.tres 与代码默认同源」锚的
## 载体；WorldTemplate.to_dict 同纪律）。
func to_dict() -> Dictionary:
	return {
		"profile_id": profile_id,
		"landform_affinity": landform_affinity,
		"weight_landform": weight_landform,
		"weight_expansion": weight_expansion,
		"weight_water": weight_water,
		"min_area_cells": min_area_cells,
		"district_radius": district_radius,
		"require_access": require_access,
		"require_water": require_water,
		"water_range": water_range,
		"min_spacing": min_spacing,
		"max_candidates": max_candidates,
	}
