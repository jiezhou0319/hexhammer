## settlement_generator.gd — 聚落/出生区/资源 + 势力归属生成器（T5 WORLD-03；
##   执行方案 docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-03 + §7 Azgaar
##   burgs/states 改造案（气候绕开版，拍板④⑧）+ 主创拍板⑪「出生区暂按
##   1 玩家 + 2 AI 流程」）
## 职责（Azgaar burgs + states 的六边形格边改造，四件）：
##   ① 适居度（burg 放置的地形版）：纯地形评分 = 高程带评分（Azgaar −(h−50)/5，
##      h 取本作量化链反演的档带中点——删 habitability 后公式自洽，§7 换算注与
##      「气候依赖绕开」行 ②）+ 河流加成（河岸格独立计分）+ 海岸加成（水邻格独立
##      计分）——三项均不依赖群系；主城/出生区 = 适居度前列带偏置随机抽取
##      （biased(0,max,5) 模式，§7 burg→占点行）+ 强制最小六边形环距（首都间距
##      (W+H)/2/国家数 距离版；不够则收缩间距重试——Azgaar「不够则重来并收缩
##      间距」同款）；每城 7 格落兵区 = 中心 + 六邻（拍板⑩，POIData SPAWN_ZONE
##      footprint 形态）；
##   ② 势力归属（state 生长，§7 上移进卡）：3 主城为种子的多源 Dijkstra，
##      totalCost = 距离项 + 纯地形成本表/expansionism（states 版源码实读数值：
##      海 1000 / 丘 300 / 山 2200 / 平原 0——§7「气候依赖绕开」行 ③；档带阈值由
##      量化链反演 h=44→丘、h=67→山，§7 换算注）+ 河界加成（有河无桥 link
##      +state_river_cost——「有河 link 天然河界」，§7 边界绘制行）；水格不入队
##      不归属（§7「水格传播成本不归属」）；expansionism 3 势力各一档（模板参数）；
##   ③ normalize() 多数滤波消斑（源码细节 §7 势力生长行 + 修订记录二 5 补全）：
##      某陆格 ≥2 个邻格属他国 且 敌对邻格数 > 己方邻格数 → 改判敌对多数方；
##      **平票不改判**（两种平票：敌对==己方 与 多数方并列——均不改）；burg 格与
##      首都邻格豁免；卡表「己方邻格 >2 豁免」由「敌对 > 己方」在六邻上限下结构性
##      蕴含（己方 ≥3 ⇒ 敌对 ≤3 ≤ 己方），不另设分支；
##   ④ 资源点 role 占位：M2 前不编产出/储量/成本（§6 WORLD-03 ④）——每势力一枚，
##      放置即预验可达（边级通行图；桥只会随后续道路阶段增加——可达只增不减，
##      预验口径保守）。
## 只读合同：不写 MapData 任何字段（生成前后 summary 逐字节一致——测试锚）；
##   产出经调用侧（WorldPipeline 聚落/势力阶段）组装进 WorldData 并全量校验。
## 修复面（WORLD-04 修复循环消费）：cfg.locked_cells = 锁定格（一切放置禁入——
##   「修复不动 locked」）；cfg.owner_pins = {cell: owner} 锚定（重跑保持锁定格
##   归属不变）；cfg.pinned = 前次尝试产物的原样重发面——{"spawn_anchor_slots":
##   {槽序号: 锚格}（footprint 触及锁定格的出生槽——**槽位保持**：槽序号即
##   role/poi_id 派生序，非首槽锚定不翻阵营）, "resource_cells": [格]}。
## 孤峰避让面（T6 S4）：cfg.avoid_cells = 出生候选禁入格集（管线注入 = 距孤峰
##   中心 < 最小间距的格——出生落点避让孤峰，提案 :78；缺省/空 = 行为不变）。
## 纯函数：RefCounted、零场景节点（ADR-2）；确定性 = 同 map 同 cfg 同 rng 序列
##   → 同产出（并列一律取 cell_id 升序钉死；Dijkstra 并列成本取小 state_id）。
class_name SettlementGenerator
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const GenConnectivity := preload("res://scripts/content/map_generation_connectivity.gd")

## 纯地形成本表（§7「气候依赖绕开」行 ③，2026-10-11 raw.githubusercontent.com
## 复核 states-generator.ts getHeightCost 实读数值；生成器版本纪律：数值变更 =
## WorldPipeline.GENERATOR_VERSION+1。「分档数值全部未拍板、随模板重定」§7 换算注）
const COST_PLAIN := 0
const COST_HILL := 300
const COST_MOUNTAIN := 2200
const COST_WATER := 1000

## Azgaar 高度阈值（h∈[0,100]——经量化链反演求档带，§7 换算注）
const H_HILL := 44.0
const H_MOUNTAIN := 67.0

## 适居度公式参数（§7「气候依赖绕开」行 ②：三项均不依赖群系，删 habitability
## 后自洽）：高程评分中心 50、斜率 1/5（Azgaar −(h−50)/5 原式）；河流/海岸加成
## 为独立计分项（数值未拍板、随模板重定——首版档）
const HABITAT_MID := 50.0
const HABITAT_SLOPE := 5.0
const HABITAT_RIVER_BONUS := 2.0
const HABITAT_COAST_BONUS := 1.0

## 偏置随机强度（Azgaar biased(0, max, 5)：pow(rand, 5)·size——强烈偏向适居度前列带）
const PICK_BIAS := 5.0

## 出生区间距收缩步长与下限（Azgaar「不够则重来并收缩间距」；下限 3 环 =
## 3 主城互不贴脸的最小语义）
const SPACING_STEP := 2
const SPACING_FLOOR := 3

## normalize() 滤波轮数上限（多数滤波有限步收敛；上限是防御性护栏——正常图
## 1~3 轮即稳定，触顶说明斑噪声异常密集，交由诊断面观察）
const NORMALIZE_MAX_PASSES := 10

## 生成配置键集（WorldTemplate scenario 组投影 + 调用侧补充量化链参数与修复面；
## min_spacing 不作键——档距表由 spawn_spacing_schedule 从尺寸折算）。
const CFG_KEYS := ["water_terrain_id", "spawn_count", "resource_count",
	"resource_budget", "expansionism", "state_river_cost", "sea_level",
	"elevation_levels"]

# ---------------- 档带反演（§7 换算注）----------------

## Azgaar h → 本作量化档 level：量化链（map_generator 步骤 3）n=h/100 过
## sea_level 门后 level = int(t·levels)+1 的逆用——默认参数下 h=44→level 2（丘）、
## h=67→level 3（山），与换算注实测一致。
static func level_of_h(h: float, sea_level: float, elevation_levels: int) -> int:
	var n := h / 100.0
	if n < sea_level:
		return 0
	var t := (n - sea_level) / (1.0 - sea_level)
	return clampi(int(t * float(elevation_levels)), 0, elevation_levels - 1) + 1

## 档带中点（Azgaar h 单位——适居度高程评分的自变量）；纯函数、确定。
static func band_mid_h(level: int, sea_level: float, elevation_levels: int) -> float:
	var t := (float(level) - 0.5) / float(elevation_levels)
	return (sea_level + t * (1.0 - sea_level)) * 100.0

## 纯地形成本（进入格成本，档带阈值由量化链反演）：level 0 水 = COST_WATER
## （Dijkstra 不入队——表值供诊断/测试对齐 §7 数值）；< 丘档 = 平原 0；
## 丘档..山档 = 丘 300；≥ 山档 = 山 2200。
static func terrain_cost(level: int, hill_level: int, mountain_level: int) -> int:
	if level <= 0:
		return COST_WATER
	if level >= mountain_level:
		return COST_MOUNTAIN
	if level >= hill_level:
		return COST_HILL
	return COST_PLAIN

## 出生区间距档距表：起档 = (W+H)/2/国家数（§7 burg→占点行「首都间距 (W+H)/2/国家数」
## 距离版），逐档收缩 SPACING_STEP 至 SPACING_FLOOR——「不够则重来并收缩间距」。
static func spawn_spacing_schedule(width: int, height: int, spawn_count: int) -> Array[int]:
	var start := maxi(int(round(float(width + height) / 2.0
		/ float(maxi(spawn_count, 1)))), SPACING_FLOOR)
	var out: Array[int] = []
	var s := start
	while s >= SPACING_FLOOR:
		out.append(s)
		s -= SPACING_STEP
	if out.is_empty():
		out.append(SPACING_FLOOR)
	return out

# ---------------- ① 适居度 ----------------

## 全图适居度（land 格 = 高程带 + 河流加成 + 海岸加成；水格 0 不参与排名）。
## 行主序 index 对齐的 PackedFloat32Array；纯函数于 (map, world)——确定性锚。
static func habitability(map: MapDataClass, world: WorldDataClass,
		water_terrain_id: int, sea_level: float, elevation_levels: int) -> PackedFloat32Array:
	var scores := PackedFloat32Array()
	scores.resize(map.cell_count())
	var river_flanks := world.river_flank_cells()
	var water_cells := world.water_membership()
	for cell in map.cells():
		var i := map.index_of(cell)
		if map.elevation_at(cell) == 0:
			scores[i] = 0.0
			continue
		var elev := -(band_mid_h(map.elevation_at(cell), sea_level, elevation_levels)
			- HABITAT_MID) / HABITAT_SLOPE
		var bonus := 0.0
		# 河流加成：河岸格（有河 link 两岸格——格边口径的「临河」，独立计分）
		if river_flanks.has(i):
			bonus += HABITAT_RIVER_BONUS
		# 海岸加成：邻接声明水体的水格（湖/海 = 格语义水体，成员邻接即海岸）；
		# 一次命中即止（加成是「是否临海」布尔面，非逐边累加）
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if map.has_cell(nb) and water_cells.has(map.index_of(nb)):
				bonus += HABITAT_COAST_BONUS
				break
		scores[i] = elev + bonus
	return scores

# ---------------- ② 聚落与出生区 ----------------

## 聚落与占点生成入口：产出 POI 表（每势力 SETTLEMENT + SPAWN_ZONE 成对，其后
## RESOURCE 逐槽）——势力阶段（grow_states）消费 pois 再长归属。
## footprint 冲突前置过滤（§6 WORLD-03 ⑤）：候选 7 格 footprint 全界内可通行且
## 不触 河岸锚点格（有河 link 两岸格——格边口径下「河床占格」的格级代理）/
## 桥端/道路格/他方出生区/锁定格。返回 {"ok", "error", "pois", "stats"}。
static func place_settlements(map: MapDataClass, world: WorldDataClass,
		rng: RandomNumberGenerator, cfg: Dictionary) -> Dictionary:
	var fail := {"ok": false, "error": "", "pois": [], "stats": {}}
	if not cfg.has_all(CFG_KEYS):
		fail["error"] = "聚落生成配置缺键：%s（got %s）" % [str(CFG_KEYS), str(cfg.keys())]
		return fail
	var spawn_count := int(cfg["spawn_count"])
	var scores := habitability(map, world, int(cfg["water_terrain_id"]),
		float(cfg["sea_level"]), int(cfg["elevation_levels"]))

	# 冲突面（放置期禁入；手工世界可能预置桥/路——一并避开）。avoid_cells =
	# 孤峰避让格集（T6 S4：距峰中心 < 最小间距的格不作出生候选——出生落点避让
	# 孤峰，提案 :78；dual_noise/零孤峰世界恒空 = 行为不变）
	var river_flanks := world.river_flank_cells()
	var bridge_banks := {}
	for c in world.crossings:
		bridge_banks[c.bank_a] = true
		bridge_banks[c.bank_b] = true
	var road_cells := world.road_cells()
	var locked := {}
	for cid in cfg.get("locked_cells", []):
		locked[int(cid)] = true
	var avoid := {}
	for cid in cfg.get("avoid_cells", []):
		avoid[int(cid)] = true

	# 候选池：中心 + 六邻全界内、全可通行、零冲突；适居度降序、并列 cell_id 升序
	var candidates: Array = []
	for cell in map.cells():
		var i := map.index_of(cell)
		if map.elevation_at(cell) == 0 or not map.is_passable(cell):
			continue
		if river_flanks.has(i) or bridge_banks.has(i) or road_cells.has(i) or locked.has(i) \
				or avoid.has(i):
			continue
		var foot := spawn_footprint_of(map, i)
		if foot.is_empty():
			continue  # 图边界格六邻不全——出生中心须 6 邻全界内
		var bad := false
		for cid in foot:
			if not map.is_passable(cell_of_id(map, int(cid))) or river_flanks.has(cid) \
					or bridge_banks.has(cid) or road_cells.has(cid) or locked.has(cid):
				bad = true
				break
		if bad:
			continue
		candidates.append({"id": i, "score": scores[i]})
	candidates.sort_custom(_cand_order)
	if candidates.size() < spawn_count:
		fail["error"] = "NO_VALID_SPAWN：可行出生候选 %d < %d（7 格 footprint 零冲突的陆格不足——图过小/水过多/冲突面过密）" \
			% [candidates.size(), spawn_count]
		return fail

	# 修复锚定：前次尝试 footprint 触及锁定格的出生槽原样重发（槽位/格/格序不变——
	# 槽序号 = 前次 SETTLEMENT POI 的出现序，role（si==0 → 玩家，拍板⑪）与 poi_id
	# （2si/2si+1）均由槽序号派生，故**必须落回原槽**而非压到队首——否则锁定非首槽
	# 出生区时该主城阵营翻转 AI→玩家）。锚定格**豁免锁定排除**（锁定挡新放置、
	# 不挡锚定重发——否则锚定槽永远不可行）
	var pinned: Dictionary = cfg.get("pinned", {})
	var anchor_slots: Dictionary = pinned.get("spawn_anchor_slots", {})
	var anchors: Array[int] = []
	anchors.resize(spawn_count)
	anchors.fill(-1)
	for slot_key in anchor_slots:
		var slot := int(slot_key)
		if slot < 0 or slot >= spawn_count:
			fail["error"] = "NO_VALID_SPAWN：修复锚定槽号 %d 越界（spawn_count=%d——修复器 bug）" \
				% [slot, spawn_count]
			return fail
		var anchor := int(anchor_slots[slot_key])
		if not _spawn_feasible(map, anchor, river_flanks, bridge_banks, road_cells):
			fail["error"] = "NO_VALID_SPAWN：修复锚定出生点 %d 可行性复核失败（锁定格事实被破坏——修复器 bug）" % anchor
			return fail
		anchors[slot] = anchor

	# 逐槽抽取：间距档距从起档逐档收缩（每档一次偏置抽取 + 顺扫——确定性 = rng 序）。
	# 锚定槽占位后其余槽照常重抽（间距约束对全体锚点生效——含锚定槽）
	var schedule := spawn_spacing_schedule(map.width, map.height, spawn_count)
	var achieved: Array[int] = []
	for si in spawn_count:
		if anchors[si] >= 0:
			achieved.append(-1)  # 锚定槽无新抽取
			continue
		var picked := -1
		var used_spacing := -1
		for s in schedule:
			picked = _pick_anchor(candidates, anchors, s, rng, map)
			if picked >= 0:
				used_spacing = s
				break
		if picked < 0:
			fail["error"] = "NO_VALID_SPAWN：第 %d 个主城放置失败（档距全档 %s 收缩后仍无可行组合）" \
				% [si + 1, str(schedule)]
			return fail
		anchors[si] = picked
		achieved.append(used_spacing)

	# POI 组装：每势力 SETTLEMENT（id=2s）+ SPAWN_ZONE（id=2s+1），资源随后逐槽
	var poi_out: Array[WorldDataClass.POIData] = []
	var next_poi := 0
	for si in anchors.size():
		var anchor := anchors[si]
		var settlement := WorldDataClass.POIData.new()
		settlement.poi_id = next_poi
		settlement.kind = WorldDataClass.POIData.Kind.SETTLEMENT
		settlement.cell_id = anchor
		settlement.footprint_cells = [anchor]
		# 拍板⑪：1 玩家 + 2 AI——槽 0 = 玩家（role 占位，数据层不解释）
		settlement.role = "player_capital" if si == 0 else "ai_capital"
		poi_out.append(settlement)
		next_poi += 1
		var zone := WorldDataClass.POIData.new()
		zone.poi_id = next_poi
		zone.kind = WorldDataClass.POIData.Kind.SPAWN_ZONE
		zone.cell_id = anchor
		zone.footprint_cells = spawn_footprint_of(map, anchor)
		zone.footprint_cells.sort()
		zone.role = "spawn_zone"
		poi_out.append(zone)
		next_poi += 1

	var resource_result := _place_resources(map, world, rng, cfg, scores, poi_out,
		next_poi, river_flanks, bridge_banks, road_cells, locked, anchors)
	if not resource_result["ok"]:
		fail["error"] = str(resource_result["error"])
		return fail
	return {"ok": true, "error": "", "pois": poi_out, "stats": {
		"spawn_anchors": anchors.duplicate(),
		"spawn_spacings": achieved,
		"resources": resource_result["cells"],
	}}

## 偏置抽取一个与既有锚点环距 ≥ spacing 的候选：biased 起点向后顺扫（Azgaar
## 前列带偏置；并列序 = 候选池 cell_id 升序）。锚点表含未抽取槽占位（-1——修复
## 锚定路径的槽位数组），间距只对已落锚槽生效。候选尽 → -1（由档距收缩兜底）。
static func _pick_anchor(candidates: Array, anchors: Array[int],
		spacing: int, rng: RandomNumberGenerator, map: MapDataClass) -> int:
	if candidates.is_empty():
		return -1
	var start := clampi(int(pow(rng.randf(), PICK_BIAS) * float(candidates.size())),
		0, candidates.size() - 1)
	for offset in candidates.size():
		var idx := (start + offset) % candidates.size()
		var cand_id := int(candidates[idx]["id"])
		var ok := true
		for a in anchors:
			if a < 0:
				continue  # 未抽取槽占位（非锚点）
			if Hex.distance(cell_of_id(map, cand_id), cell_of_id(map, a)) < spacing:
				ok = false
				break
		if ok:
			return cand_id
	return -1

# ---------------- ③ 资源点（role 占位）----------------

## 每势力一枚资源点：候选 = 自本势力主城边级可达（桥未建 = 保守口径，后续只增）
## ∧ 环距 ≤ resource_budget ∧ 零冲突 ∧ 不入任何既有 footprint；适居度降序偏置抽取。
## 无可行格 = 具名失败（NO_RESOURCE_SITE——§11 清单「先包括」外的显式扩格，
## 错误指向势力主城与预算）。
static func _place_resources(map: MapDataClass, world: WorldDataClass,
		rng: RandomNumberGenerator, cfg: Dictionary, scores: PackedFloat32Array,
		poi_out: Array[WorldDataClass.POIData], next_poi: int,
		river_flanks: Dictionary, bridge_banks: Dictionary, road_cells: Dictionary,
		locked: Dictionary, anchors: Array[int]) -> Dictionary:
	var count := int(cfg["resource_count"])
	if count <= 0:
		return {"ok": true, "cells": []}
	var budget := int(cfg["resource_budget"])
	var used_foot := {}
	for p in poi_out:
		for cid in p.footprint_cells:
			used_foot[cid] = true
	# 修复锚定：锁定格上的资源原样重发（槽位/格保持）
	var pinned: Dictionary = cfg.get("pinned", {})
	var out_cells: Array[int] = []
	for rc in pinned.get("resource_cells", []):
		var cell := int(rc)
		var res := WorldDataClass.POIData.new()
		res.poi_id = next_poi
		res.kind = WorldDataClass.POIData.Kind.RESOURCE
		res.cell_id = cell
		res.footprint_cells = [cell]
		res.role = "core_resource"
		poi_out.append(res)
		next_poi += 1
		used_foot[cell] = true
		out_cells.append(cell)
	var remaining := count - out_cells.size()
	if remaining <= 0:
		return {"ok": true, "cells": out_cells}
	# 轮转势力槽放置（每轮从该势力主城的可达集抽取一枚）
	var si := 0
	while out_cells.size() < count:
		var anchor := anchors[si % anchors.size()]
		si += 1
		var reach: Dictionary = GenConnectivity.reachable_set(map, world,
			cell_of_id(map, anchor))["cells"]
		var pool: Array = []
		for cell in reach:
			var i := map.index_of(cell)
			if map.elevation_at(cell) == 0 or not map.is_passable(cell):
				continue
			if Hex.distance(cell, cell_of_id(map, anchor)) > budget:
				continue
			if river_flanks.has(i) or bridge_banks.has(i) or road_cells.has(i) \
					or locked.has(i) or used_foot.has(i):
				continue
			pool.append({"id": i, "score": scores[i]})
		if pool.is_empty():
			return {"ok": false, "cells": out_cells,
				"error": "NO_RESOURCE_SITE：势力主城 %d 周围（可达 ∧ 环距 ≤ %d ∧ 零冲突）无可行资源点位" \
					% [anchor, budget]}
		pool.sort_custom(_cand_order)
		var pick := int(pool[_biased_index(rng, pool.size())]["id"])
		var res := WorldDataClass.POIData.new()
		res.poi_id = next_poi
		res.kind = WorldDataClass.POIData.Kind.RESOURCE
		res.cell_id = pick
		res.footprint_cells = [pick]
		res.role = "core_resource"
		poi_out.append(res)
		next_poi += 1
		used_foot[pick] = true
		out_cells.append(pick)
	return {"ok": true, "cells": out_cells}

## 偏置随机下标（biased(0, n, PICK_BIAS)——Azgaar pow(rand, shift)·n 模式）。
static func _biased_index(rng: RandomNumberGenerator, pool_size: int) -> int:
	return clampi(int(pow(rng.randf(), PICK_BIAS) * float(pool_size)), 0, pool_size - 1)

# ---------------- ④ 势力归属（state 生长 + normalize）----------------

## 归属生成入口：主城多源 Dijkstra + normalize 多数滤波。返回 {"ok", "error",
##   "states", "cell_owners": Array[int], "stats"}。
## 进入格成本 = 1（距离项）+ terrain_cost(目的格)/expansionism[扩张方]
##   +（有河无桥边 +state_river_cost——河界加成不分摊：河界是天然边界，§7）；
## 并列成本取小 state_id（确定性）；水格不入队不归属；无随机消耗（确定性生长）。
static func grow_states(map: MapDataClass, world: WorldDataClass,
		cfg: Dictionary) -> Dictionary:
	var fail := {"ok": false, "error": "", "states": [], "cell_owners": [], "stats": {}}
	if not cfg.has_all(CFG_KEYS):
		fail["error"] = "势力生成配置缺键：%s（got %s）" % [str(CFG_KEYS), str(cfg.keys())]
		return fail
	var settlements := world.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT)
	var spawn_count := int(cfg["spawn_count"])
	if settlements.size() < spawn_count:
		fail["error"] = "ALLEGIANCE_NO_CAPITALS：SETTLEMENT POI %d 个 < spawn_count %d（势力阶段依赖聚落阶段产物）" \
			% [settlements.size(), spawn_count]
		return fail
	var expansionism: Array = cfg["expansionism"]
	var hill_level := level_of_h(H_HILL, float(cfg["sea_level"]), int(cfg["elevation_levels"]))
	var mountain_level := level_of_h(H_MOUNTAIN, float(cfg["sea_level"]), int(cfg["elevation_levels"]))
	var river_edges := world.river_edge_index()
	var claims := world.crossing_index()  # 循环外缓存——认领表是静态事实

	# states 表：主城 = SETTLEMENT POI 升序前 spawn_count 个（槽 0 = 玩家，拍板⑪）
	var states: Array[WorldDataClass.StateData] = []
	for si in spawn_count:
		var s := WorldDataClass.StateData.new()
		s.state_id = si
		s.capital_poi_id = settlements[si].poi_id
		s.expansionism = int(expansionism[si]) if si < expansionism.size() else 1
		states.append(s)

	# 多源 Dijkstra（Array[float] = float64——成本累加远超 float32 精度）
	var n := map.cell_count()
	var dist: Array[float] = []
	dist.resize(n)
	for i in n:
		dist[i] = INF
	var owner := PackedInt32Array()
	owner.resize(n)
	for i in n:
		owner[i] = WorldDataClass.ID_NONE
	var heap := MinHeap.new()
	for si in spawn_count:
		var cap := settlements[si].cell_id
		dist[cap] = 0.0
		owner[cap] = si
		heap.push(0.0, si, cap)
	while heap.size() > 0:
		var top := heap.pop()
		var u: int = top[2]
		if top[0] > dist[u] or owner[u] != top[1]:
			continue  # 过期堆项（已被更优路径抢占）
		var ou: int = owner[u]
		var uc := cell_of_id(map, u)
		for d in 6:
			var nb := Hex.neighbor(uc, d)
			if not map.has_cell(nb):
				continue
			var v := map.index_of(nb)
			# 水格不入队不归属（§7「水格传播成本不归属」；水恒 elevation 0）
			if map.elevation_at(nb) == 0 or not map.is_passable(nb):
				continue
			var step := 1.0 + float(terrain_cost(map.elevation_at(nb), hill_level,
				mountain_level)) / float(maxi(states[ou].expansionism, 1))
			var link := WorldDataClass.link_id_of(u, v)
			if river_edges.has(link) and not claims.has(link):
				step += float(cfg["state_river_cost"])  # 河界加成（无桥边——势力的天然河界）
			var nd: float = dist[u] + step
			if nd < dist[v]:
				dist[v] = nd
				owner[v] = ou
				heap.push(nd, ou, v)
	# 归属落地（未达陆格保持 -1 = 显式中立带——孤岛等不可达陆格的合法归宿）
	var owners: Array[int] = []
	for i in n:
		owners.append(owner[i])
	# 修复锚定：锁定格 owner 保持前次尝试值（「修复不动 locked」的归属面）
	var pins: Dictionary = cfg.get("owner_pins", {})
	for cell_id in pins:
		var cid := int(cell_id)
		if cid >= 0 and cid < n:
			owners[cid] = int(pins[cid])
	var norm_stats := _normalize(map, world, owners, pins)
	var owned := 0
	for o in owners:
		if o != WorldDataClass.ID_NONE:
			owned += 1
	return {"ok": true, "error": "", "states": states, "cell_owners": owners, "stats": {
		"owned_cells": owned,
		"neutral_cells": n - owned,
		"normalize_flips": norm_stats["flips"],
		"normalize_passes": norm_stats["passes"],
	}}

## normalize() 的公开只读面（测试/工具消费——对给定 owners 原地多数滤波；
## grow_states 内部同款）。豁免/平票/锚定语义见 _normalize 头注。
static func apply_normalize(map: MapDataClass, world: WorldDataClass,
		owners: Array[int], pins := {}) -> Dictionary:
	return _normalize(map, world, owners, pins)

## normalize() 多数滤波（§7 势力生长行 + 修订记录二 5）：某陆格 ≥2 个邻格属他国
## 且 敌对邻格数 > 己方邻格数 → 改判为敌对多数方；平票不改判（敌对==己方、或
## 多数方并列，均不改）；豁免 = burg 格（SETTLEMENT 锚定格——本作唯一 burg 面）
## + 首都邻格 + owner_pins 修复锚定格。迭代至稳定（≤ NORMALIZE_MAX_PASSES）。
## 行主序单趟扫描内改判即时生效（同趟后续格见新值——Azgaar 同款单趟语义）。
static func _normalize(map: MapDataClass, world: WorldDataClass,
		owners: Array[int], pins: Dictionary) -> Dictionary:
	var exempt := {}
	for p in world.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT):
		exempt[p.cell_id] = true  # burg 格
		var cap := cell_of_id(map, p.cell_id)
		for d in 6:
			var nb := Hex.neighbor(cap, d)
			if map.has_cell(nb):
				exempt[map.index_of(nb)] = true  # 首都邻格（落兵区不被清洗）
	for cell_id in pins:
		exempt[int(cell_id)] = true
	var flips := 0
	var passes := 0
	while passes < NORMALIZE_MAX_PASSES:
		passes += 1
		var changed := false
		for i in map.cell_count():
			var o := owners[i]
			if o == WorldDataClass.ID_NONE or exempt.has(i):
				continue
			if map.elevation_at(cell_of_id(map, i)) == 0:
				continue
			# 邻格投票：只计已归属陆格（水/中立邻格缺席——「敌对 ≥ 己方」的分母
			# 是全部六邻，缺席票天然保守）
			var votes := {}
			var own_count := 0
			var hostile_count := 0
			var ci := cell_of_id(map, i)
			for d in 6:
				var nb := Hex.neighbor(ci, d)
				if not map.has_cell(nb):
					continue
				var oj := owners[map.index_of(nb)]
				if oj == WorldDataClass.ID_NONE:
					continue
				if oj == o:
					own_count += 1
				else:
					hostile_count += 1
					votes[oj] = int(votes.get(oj, 0)) + 1
			if hostile_count < 2 or hostile_count <= own_count:
				continue  # <2 敌对 或 平票/少数（含卡表「己方邻格 >2」蕴含面）→ 不改判
			var best_state := -1
			var best_votes := 0
			var tie := false
			for st in votes:
				var v: int = votes[st]
				if v > best_votes:
					best_votes = v
					best_state = int(st)
					tie = false
				elif v == best_votes:
					tie = true
			if tie or best_state < 0:
				continue  # 多数方并列 = 平票不改判
			owners[i] = best_state
			flips += 1
			changed = true
		if not changed:
			break
	return {"flips": flips, "passes": passes}

# ---------------- 内部 ----------------

## 出生锚可行性复核（修复锚定槽专用——不含锁定排除：锚定格豁免；其余冲突面
## 全查：7 格 footprint 界内可通行、锚与 footprint 不触河岸/桥端/道路）。
static func _spawn_feasible(map: MapDataClass, cell_id: int,
		river_flanks: Dictionary, bridge_banks: Dictionary,
		road_cells: Dictionary) -> bool:
	var cell := cell_of_id(map, cell_id)
	if map.elevation_at(cell) == 0 or not map.is_passable(cell):
		return false
	if river_flanks.has(cell_id) or bridge_banks.has(cell_id) or road_cells.has(cell_id):
		return false
	var foot := spawn_footprint_of(map, cell_id)
	if foot.is_empty():
		return false
	for cid in foot:
		if not map.is_passable(cell_of_id(map, int(cid))):
			return false
		if river_flanks.has(cid) or bridge_banks.has(cid) or road_cells.has(cid):
			return false
	return true

## 出生中心 → 中心 + 六邻 cell_id 集（任一邻格出界 → 空 = 不可作出生中心；
## 顺序 = 中心、方向 0..5——调用侧自行 sort 成行主序规范序）。
static func spawn_footprint_of(map: MapDataClass, cell_id: int) -> Array[int]:
	var cell := cell_of_id(map, cell_id)
	var out: Array[int] = [cell_id]
	for d in 6:
		var nb := Hex.neighbor(cell, d)
		if not map.has_cell(nb):
			return []
		out.append(map.index_of(nb))
	return out

## 候选排序：适居度降序、并列 cell_id 升序（确定性钉死）。
static func _cand_order(a: Dictionary, b: Dictionary) -> bool:
	if a["score"] != b["score"]:
		return a["score"] > b["score"]
	return int(a["id"]) < int(b["id"])

## cell 稳定 ID → axial 格（WorldData._cell_of_id 同式；生成器侧自持只读版，
## RiverNetworkGenerator 同款先例——避免跨文件私有依赖）。
static func cell_of_id(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))

## 二叉小根堆（(cost, state, cell) 三元组；GDScript 无内建优先队列——Dijkstra
## 规模 ≤ 数千格，数组堆足够；比较 = cost 优先、state 次之（并列取小 state_id
## 的确定性落点）。pop 返回 [cost, state, cell]。
class MinHeap:
	var _costs: Array[float] = []
	var _states: Array[int] = []
	var _cells: Array[int] = []

	func size() -> int:
		return _costs.size()

	func push(cost: float, state: int, cell: int) -> void:
		_costs.append(cost)
		_states.append(state)
		_cells.append(cell)
		var i := _costs.size() - 1
		while i > 0:
			var p := (i - 1) / 2
			if _less(i, p):
				_swap(i, p)
				i = p
			else:
				break

	func pop() -> Array:
		var out := [_costs[0], _states[0], _cells[0]]
		var last := _costs.size() - 1
		_swap(0, last)
		_costs.remove_at(last)
		_states.remove_at(last)
		_cells.remove_at(last)
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := 2 * i + 2
			var m := i
			if l < _costs.size() and _less(l, m):
				m = l
			if r < _costs.size() and _less(r, m):
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return out

	func _less(a: int, b: int) -> bool:
		if _costs[a] != _costs[b]:
			return _costs[a] < _costs[b]
		return _states[a] < _states[b]

	func _swap(a: int, b: int) -> void:
		var tc: float = _costs[a]
		_costs[a] = _costs[b]
		_costs[b] = tc
		var ts: int = _states[a]
		_states[a] = _states[b]
		_states[b] = ts
		var td: int = _cells[a]
		_cells[a] = _cells[b]
		_cells[b] = td
