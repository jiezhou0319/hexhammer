## suitability_generator.gd — 派系适宜度两阶段选址生成器（T6 S6 第一刀；执行方案
##   docs/M1a-terrain-T6-stylized-execution-plan.md §8 范围①②③ + 提案
##   docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md §派系适配
##   :148-156「两阶段选址」与 :136-146「默认关系」）
## 职责（纯函数，两阶段——「先执行硬筛选，再评分，避免高风格分覆盖不可用条件」，
##   提案 :150 原文）：
##   ① **硬筛选**（不满足 = 具名拒绝原因，绝不产伪合格——提案 :162「没有合格候选
##      时返回明确失败原因……不能放宽不可通达等硬条件后仍称为合格」）：逐锚格按
##      固定评估序查三项——面积（district_radius 盘内**通行格** ≥ min_area_cells →
##      AREA_BELOW_MIN）、通达（require_access 时锚点通行连通片须跨 ≥2 地貌区域 →
##      NO_REGION_ACCESS；WorldValidator 谷地对外通路同口径——is_passable 通行面
##      + BFS 触达异区格）、
##      水（require_water 时距最近水源格 BFS 距离 ≤ water_range → NO_WATER_IN_RANGE；
##      水源 = 水地形格 ∪ 河岸格）。每格计**首个**失败原因一次（不重复计）；
##   ② **评分与间距**（合格者才评分——软偏好只在可用性成立后参与）：分数 = 千分
##      整数 0..1000 的三项加权归一分（地貌偏好 1−|群山权重−affinity| + 可扩展空间
##      盘内通行格占比 + 水 距水源线性衰减）；再按（分数降序，cell_id 升序）贪心
##      选取，同 profile 候选两两六边形环距 ≥ min_spacing，至多 max_candidates 个
##      ——「最终落点 = 候选集合内评分与间距规则共同决定的结果」的候选面（真实
##      落点/出生区接线属后续批次，本刀不消费）。
## 数据合同：产物 FactionSuitability 三件（profile_id/candidate_sites/
##   rejection_reasons + qualified_count）经管线组装进 WorldData（缺键合法，旧图
##   零迁移）；profile 是生成器配置不进世界事实（草案 §1.2）。
## 只读合同：不写 MapData 任何字段（生成前后 summary 逐字节一致——测试锚）；
##   只读 WorldData 的分区权重场/区域归属/河段（水源面）。
## 确定性：**零随机消耗**（并列一律取 cell_id 升序钉死——SettlementGenerator 同
##   纪律；间距贪心的遍历序 = 排序序，与格遍历序无关）。管线侧通道声明 = poi
##   （settlement 族，提案 :221 八通道无独立适宜度通道——通道传入仅为签名统一，
##   rng 序列不消耗；**若后续选址引入随机（并列随机化），须开具名通道**，沿
##   CHANNEL_SEED_OFFSETS 追加纪律）。
## 非目标（本刀不做，后续批次）：聚落阶段 profile 接线、开局保证模式（含修复
##   循环）、资源条件/战略位置评分项（M2/M3 门后——本版评分只有提案 :153 的
##   前三项）。
## 纯逻辑类：RefCounted、零场景节点（ADR-2；删 scripts/ui/** 不影响本文件与
##   tests/）。
class_name SuitabilityGenerator
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const SuitabilityProfileClass := preload("res://scripts/core/data/suitability_profile.gd")

## 硬筛选拒绝原因码（固定评估序 = 码序：面积 → 通达 → 水；进 rejection_reasons
## 的 {code, count}——「具名原因，不产伪合格」的码表面）
const REJECT_AREA := "AREA_BELOW_MIN"
const REJECT_ACCESS := "NO_REGION_ACCESS"
const REJECT_WATER := "NO_WATER_IN_RANGE"
const REJECT_ORDER: Array[String] = [REJECT_AREA, REJECT_ACCESS, REJECT_WATER]

## 生成配置键集（管线侧投影；water_terrain_id 与水系/聚落阶段同源——内容层
## 3 号水槽约定，核心层不硬编码）
const CFG_KEYS := ["water_terrain_id"]


## 两阶段选址主入口（逐 profile 求值，共享图级预计算——水源距离场与通行连通片
## 跨区标记只算一次）。profiles 出现序 = 事实表序（模板清单序）。返回
##   {"ok", "error", "results": Array[WorldData.FactionSuitability],
##    "stats": {"profiles": int, "candidates": Array[int]（逐 profile 候选数）,
##      "qualified": Array[int], "rejections": Array[Dictionary]（逐 profile 码→数）}}。
## 失败仅配置面（profile 非法/区域事实缺失——调用方管线在跳过/配置阶段已拦，
## 此处显式具名防御）；**无合格候选不是失败**（空候选 + 拒绝原因 = 合法产出）。
static func evaluate_profiles(map: MapDataClass, world: WorldDataClass,
		profiles: Array, cfg: Dictionary) -> Dictionary:
	var water_terrain_id := int(cfg.get("water_terrain_id", 3))
	if world.terrain_regions.is_empty():
		return {"ok": false, "error": "区域事实为空（适宜度消费分区/权重事实——regions 路线才产；调用方应先跳过）",
			"results": [], "stats": {}}
	for p in profiles:
		if not (p is SuitabilityProfileClass):
			return {"ok": false, "error": "profile 清单含非 SuitabilityProfile 项（资源槽未解析？）",
				"results": [], "stats": {}}
		var perr: String = (p as SuitabilityProfileClass).validate()
		if perr != "":
			return {"ok": false, "error": perr, "results": [], "stats": {}}
	# ---- 图级预计算（跨 profile 共享；一次线性扫 + 两 BFS）----
	# 水源距离场：多源 BFS（源 = 水地形格 ∪ 河岸格；全格图邻接——距离 = 格图步数，
	# 与通行无关：水在边上的河岸格按 0 计「临水」）。无水源图 → 全程 -1（require_
	# water profile 全拒 NO_WATER_IN_RANGE；评分水项恒 0）
	var water_dist := _water_distance_field(map, world, water_terrain_id)
	# 通行连通片 → 跨区标记（片内 distinct cell_regions ≥2 = 有对外通路——
	# WorldValidator 谷地对外通路同口径的图级一次性版本）
	var has_access := _component_access_flags(map, world)
	# ---- 逐 profile 两阶段 ----
	var results: Array[WorldDataClass.FactionSuitability] = []
	var candidates_stat: Array[int] = []
	var qualified_stat: Array[int] = []
	var rejection_stat: Array = []
	for p in profiles:
		var profile := p as SuitabilityProfileClass
		var fs := _evaluate_one(map, world, profile, water_dist, has_access)
		results.append(fs)
		candidates_stat.append(fs.candidate_sites.size())
		qualified_stat.append(fs.qualified_count)
		var rejections := {}
		for rr in fs.rejection_reasons:
			rejections[rr["code"]] = int(rr["count"])
		rejection_stat.append(rejections)
	return {"ok": true, "error": "", "results": results, "stats": {
		"profiles": results.size(),
		"candidates": candidates_stat,
		"qualified": qualified_stat,
		"rejections": rejection_stat,
	}}


## 单 profile 两阶段选址（evaluate_profiles 的逐 profile 面——独立暴露供测试
## 直接驱动；共享预计算项由调用方传入，单 profile 便利入口见
## evaluate_profile_standalone）。
static func _evaluate_one(map: MapDataClass, world: WorldDataClass,
		profile: SuitabilityProfileClass, water_dist: PackedInt32Array,
		has_access: PackedFloat32Array) -> WorldDataClass.FactionSuitability:
	var fs := WorldDataClass.FactionSuitability.new()
	fs.profile_id = profile.profile_id
	# ---- 阶段①：硬筛选（固定评估序：面积 → 通达 → 水；首个失败即计因出局）----
	var rejection_counts := {}
	for code in REJECT_ORDER:
		rejection_counts[code] = 0
	# 合格候选（锚格 → 分数）——行主序收集，排序在阶段②统一做（确定性）
	var qualified_cells: Array[int] = []
	var qualified_scores: Array[int] = []
	var cells := map.cells()
	var disc := _disc_cells(profile.district_radius)  # 相对偏移盘（一次枚举，
	# 逐锚平移复用——盘内界内过滤逐锚做）
	for i in cells.size():
		if not map.is_passable(cells[i]):
			continue  # 非通行格（水/悬崖等）不是候选锚——通行性是独立字段
			#（map_data.gd「不随地形/高程自动推导」合同；非锚格不计拒绝原因）
		# 面积：盘内通行格数 ≥ min_area_cells（is_passable 口径——与
		# WorldValidator 谷地/连通片判定同一通行面）
		var usable := 0
		for offset in disc:
			var nb: Vector2i = cells[i] + offset
			if map.has_cell(nb) and map.is_passable(nb):
				usable += 1
		if usable < profile.min_area_cells:
			rejection_counts[REJECT_AREA] = int(rejection_counts[REJECT_AREA]) + 1
			continue
		# 通达：锚点通行连通片跨 ≥2 地貌区域
		if profile.require_access and has_access[i] < 0.5:
			rejection_counts[REJECT_ACCESS] = int(rejection_counts[REJECT_ACCESS]) + 1
			continue
		# 水：距最近水源格 ≤ water_range（water_dist ≥0 为可达；水格自身 0 不会
		# 出现——锚是陆格；河岸格 = 0 计临水）
		if profile.require_water \
				and (water_dist[i] < 0 or water_dist[i] > profile.water_range):
			rejection_counts[REJECT_WATER] = int(rejection_counts[REJECT_WATER]) + 1
			continue
		qualified_cells.append(i)
		qualified_scores.append(_score_of(map, world, profile, i, water_dist, disc, usable))
	fs.qualified_count = qualified_cells.size()
	# ---- 阶段②：评分排序 + 间距贪心 + 上限（（分数降序，cell_id 升序）——
	# 并列取 cell_id 升序钉死，SettlementGenerator「并列一律取 cell_id 升序」同款）----
	var order: Array = []
	for k in qualified_cells.size():
		order.append(k)
	order.sort_custom(func(a: int, b: int) -> bool:
		if qualified_scores[a] != qualified_scores[b]:
			return qualified_scores[a] > qualified_scores[b]
		return qualified_cells[a] < qualified_cells[b])
	var taken: Array[int] = []
	for k in order:
		if taken.size() >= profile.max_candidates:
			break  # 上限尽（被间距/上限让位的合格格不进候选——但 qualified_count 已计）
		var cell_id := qualified_cells[k]
		var ok_spacing := true
		if profile.min_spacing > 0:
			for t in taken:
				if Hex.distance(cells[cell_id], cells[t]) < profile.min_spacing:
					ok_spacing = false
					break
		if not ok_spacing:
			continue
		taken.append(cell_id)
	# taken 已是（分数降序，cell_id 升序）序——candidate_sites 规范序即此序
	for cell_id in taken:
		var cs := WorldDataClass.CandidateSite.new()
		cs.cell_id = cell_id
		for k in qualified_cells.size():
			if qualified_cells[k] == cell_id:
				cs.score = qualified_scores[k]
				break
		fs.candidate_sites.append(cs)
	# 拒绝原因（固定码序、零计数不落——「没有候选时输出原因」的可读面：只列
	# 实际发生的原因）
	for code in REJECT_ORDER:
		if int(rejection_counts[code]) > 0:
			fs.rejection_reasons.append({"code": code, "count": int(rejection_counts[code])})
	return fs


## 单 profile 便利入口（无共享预计算——测试/预览直接驱动单 profile 用；管线走
## evaluate_profiles 共享面）。
static func evaluate_profile_standalone(map: MapDataClass, world: WorldDataClass,
		profile: SuitabilityProfileClass, water_terrain_id: int) -> WorldDataClass.FactionSuitability:
	var water_dist := _water_distance_field(map, world, water_terrain_id)
	var has_access := _component_access_flags(map, world)
	return _evaluate_one(map, world, profile, water_dist, has_access)


## 评分（阶段②的分数面——千分整数 0..1000）：三项加权归一分 =
##   (wl·landform + we·expansion + ww·water) / (wl+we+ww)，各项 ∈[0,1]——
##   · landform = 1 − |w − affinity|（w = 群山权重千分/1000——「尽可能体现该
##     派系地貌偏好」，提案 :121 软目标）；
##   · expansion = 盘内通行格 / 盘内界内格（开阔可扩展计高——临水/贴界的
##     破碎盘计低；提案 :153「可扩展空间」项）；
##   · water = 1 − (d−1)/range（d = 水源距离，[1, range] 线性衰减到 1/range、
##     超程 0；河岸格 d=0 按 1 计——提案 :153「水资源」项）。
static func _score_of(map: MapDataClass, world: WorldDataClass,
		profile: SuitabilityProfileClass, i: int, water_dist: PackedInt32Array,
		disc: Array[Vector2i], usable_in_disc: int) -> int:
	var cells := map.cells()
	var w := float(world.cell_mountain_weights[i]) / 1000.0 \
			if i < world.cell_mountain_weights.size() else 0.0
	var landform := clampf(1.0 - absf(w - profile.landform_affinity), 0.0, 1.0)
	var inbounds := 0
	for offset in disc:
		if map.has_cell(cells[i] + offset):
			inbounds += 1
	var expansion := clampf(float(usable_in_disc) / float(maxi(inbounds, 1)), 0.0, 1.0)
	var water := 0.0
	if water_dist[i] >= 0:
		water = clampf(1.0 - float(water_dist[i] - 1) / float(maxi(profile.water_range, 1)), 0.0, 1.0)
	var total_weight := profile.weight_landform + profile.weight_expansion + profile.weight_water
	var combined := (profile.weight_landform * landform
		+ profile.weight_expansion * expansion
		+ profile.weight_water * water) / total_weight
	return clampi(int(round(combined * 1000.0)), 0, 1000)


## 相对偏移盘（半径 R 的六边形盘全部轴向偏移，一次枚举——逐锚平移复用；
## 原点含，嵌套循环序即固定序）。盘形状由轴向距离口径唯一决定（cube 约束
## |dq|≤R ∧ |dr|≤R ∧ |dq+dr|≤R；测试独立拼装 oracle 同锚——test_world_
## suitability 的间距/盘 oracle 面）。
static func _disc_cells(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			out.append(Vector2i(dq, dr))
	return out


## 水源距离场（多源 BFS，格图步数——与通行无关）：源 = terrain == water_terrain_id
## 的格 ∪ 河岸格（river_flank_cells——格边河的「临河」格级代理，WORLD-03 ⑤ 同
## 口径）；不可达 = -1。BFS 序确定且最短距离与序无关——确定性。
static func _water_distance_field(map: MapDataClass, world: WorldDataClass,
		water_terrain_id: int) -> PackedInt32Array:
	var n := map.cell_count()
	var dist := PackedInt32Array()
	dist.resize(n)
	for i in n:
		dist[i] = -1
	var queue: Array[int] = []
	var cells := map.cells()
	for i in n:
		if map.terrain_at(cells[i]) == water_terrain_id:
			dist[i] = 0
			queue.append(i)
	for flank_cid in world.river_flank_cells():
		if dist[flank_cid] < 0:
			dist[flank_cid] = 0
			queue.append(flank_cid)
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nb in map.neighbors_existing(cells[cur]):
			var j := map.index_of(nb)
			if dist[j] >= 0:
				continue
			dist[j] = dist[cur] + 1
			queue.append(j)
	return dist


## 通行连通片跨区标记（图级一次计算）：BFS 划分**通行格**连通片（is_passable
## 口径——map_data.gd「通行性是独立字段」合同，与 WorldValidator 谷地连通/
## 出口判定同一通行面），片内 distinct cell_regions 值数 ≥2 → 片内格
## access=1（「对外通路」——WorldValidator 谷地出口 valley_outlet 的图级泛化：
## 谷地候选与平原候选同一口径，不按区域类型分叉）。行主序种子序确定——片
## 划分与区域集合均与遍历序无关，确定性。
static func _component_access_flags(map: MapDataClass,
		world: WorldDataClass) -> PackedFloat32Array:
	var n := map.cell_count()
	var access := PackedFloat32Array()
	access.resize(n)
	for i in n:
		access[i] = 0.0
	var cells := map.cells()
	var visited := {}
	for seed_i in n:
		if visited.has(seed_i) or not map.is_passable(cells[seed_i]):
			continue
		# BFS 收集片 + 片内 distinct 区域集
		var component: Array[int] = [seed_i]
		var regions_seen := {}
		visited[seed_i] = true
		var head := 0
		while head < component.size():
			var cur: int = component[head]
			head += 1
			if cur < world.cell_regions.size() and world.cell_regions[cur] >= 0:
				regions_seen[world.cell_regions[cur]] = true
			for nb in map.neighbors_existing(cells[cur]):
				var j := map.index_of(nb)
				if visited.has(j) or not map.is_passable(nb):
					continue
				visited[j] = true
				component.append(j)
		var spans := 1.0 if regions_seen.size() >= 2 else 0.0
		for cid in component:
			access[cid] = spans
	return access
