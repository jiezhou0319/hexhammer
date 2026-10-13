## world_validator.gd — 可玩校验器（T5 WORLD-04；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-04 + 数据合同草案 §11；
##   T6 S5 增区域验收面——docs/M1a-terrain-T6-stylized-execution-plan.md §7 +
##   提案 §区域限制 :111-134 / §验收与评估 :261-276）
## 职责：**结构化错误报告**的单一入口——错误 {code, cell_ids, link_ids,
##   constraint_id, explanation} 指向具体对象（草案 §11 错误码清单落码：
##   NO_VALID_SPAWN / RESOURCE_UNREACHABLE / RIVER_CYCLE / NO_RIVER_OUTLET /
##   BRIDGE_ENDPOINT_INVALID / ROAD_NETWORK_DISCONNECTED /
##   LOCKED_CONSTRAINT_CONFLICT；清单「先包括」= 可扩格——本文件另落
##   POI_FOOTPRINT_CONFLICT 与 WORLD_DATA_INVALID 两个结构性扩格码 + T6 S5
##   区域验收五码，全部在类头 ERROR_CODES 登记）。Azgaar「无阶段诊断产物」
##   反面教训的补丁：失败必带错误码 + 对象定位，不许只报「地图无效」
##   （§8.4 可诊断性指标）。
## 分层：WorldData.validate 管数据形状/拓扑/对账（首错返回串——数据层口径）；
##   本校验器消费其串并**另查可玩面**（出生 footprint 通行/冲突、资源可达、
##   路网连通、锁定约束、区域验收）——全部错误**收集不短路**（修复循环需要
##   全清单）。
## opts（全部可选，默认 = 不查该面）：
##   - water_terrain_id / max_road_delta / max_bridge_bank_delta：透传
##     WorldData.validate 的生成配置口径（-1 = 无配置不查，§7 禁止项）；
##   - require_road_network: bool——必需聚落全连通检查的开关（道路阶段开启时置
##     true；跳过阶段 = 无该能力即无该约束）；
##   - resource_budget: int——资源点距出生锚的最大六边形环距（0 = 不查预算只查
##     可达；模板 scenario 组投影）；
##   - locked_cells: Array[int]——锁定格（WORLD-04 修复循环「修复不动 locked」的
##     校验面：道路格不得落入锁定格）；
##   - **T6 S5 区域验收组**（REGION_* 五码的阈值面——「有配置才判」沿 ROAD-01
##     先例：opts 不带 = 全不查；模板 WorldTemplate regions 验收组是唯一投影源）：
##     mountains/plains_core_ratio_min/max（区域核心地貌占比区间——分母 = 区域
##     核心范围，过渡带单独统计只进 region_metrics 不判罚，提案 :123）、
##     region_mountain/plain_class_weight（地貌分类阈值 mw 档，§尚待确认② 的
##     「首版自定」面）、region_largest_component_ratio（区域核心内最大可用
##     连通片占核心通行格比下限）、region_boundary_max_step（异区相邻对高程差
##     上限——「无区域编号导致的高度断缝」，与 S3 量化图验收同口径）、
##     region_min_valley_cells（群山区可用谷地下限 + 对外通路开关——0 = 面积
##     不查但通路仍查）、peak_area_budget_ratio（孤峰影响面积预算比例，分母 =
##     有效平原陆格——与 TerrainComposition.EFFECTIVE_PLAIN_WEIGHT_MAX 同阈）。
##     全部阈值 = 未验证起调值（T6 方案 §10）。区域事实为空（dual_noise/legacy
##     路线）时整面零触发——既有路线逐格输出与校验报告零漂移。
## 纯函数：RefCounted、零场景节点（ADR-2）；不预加载任何生成器（被
##   RoadNetworkGenerator 增量重验与 WorldPipeline 修复循环消费——依赖方向单向）。
class_name WorldValidator
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const GenConnectivity := preload("res://scripts/content/map_generation_connectivity.gd")

## §11 错误码清单（「先包括」七码 + 本文件结构性扩格码——评审面）。T6 S5
## 追加区域验收五码（提案 §验收与评估 :265-276 机器面：区域主导性/
## 平原完整性/边界过渡/山地可用性/孤峰稀疏性——群山结构面由骨架事实 +
## 占比联合表达）：
##   REGION_DOMINANCE      区域核心地貌占比出区间（不合格区域编号进 explanation）
##   REGION_CONNECTIVITY   区域核心最大可用连通片不足（平原硬约束面）
##   REGION_BOUNDARY_STEP  异区相邻对高程差越阶（区域编号导致的高度断缝）
##   MOUNTAIN_VALLEY       群山区可用谷地面积不足 / 无对外通路
##   PEAK_AREA_BUDGET      孤峰影响面积超预算（分母 = 有效平原陆格）
const ERROR_CODES := ["NO_VALID_SPAWN", "RESOURCE_UNREACHABLE", "RIVER_CYCLE",
	"NO_RIVER_OUTLET", "BRIDGE_ENDPOINT_INVALID", "ROAD_NETWORK_DISCONNECTED",
	"LOCKED_CONSTRAINT_CONFLICT", "POI_FOOTPRINT_CONFLICT", "WORLD_DATA_INVALID",
	"REGION_DOMINANCE", "REGION_CONNECTIVITY", "REGION_BOUNDARY_STEP",
	"MOUNTAIN_VALLEY", "PEAK_AREA_BUDGET"]

## 校验入口：返回 {"ok": bool, "errors": Array[Dictionary]}——每个错误
##   {code: String, cell_ids: Array[int], link_ids: Array[Vector2i],
##    constraint_id: String, explanation: String}（explanation 恒含对象定位——
##   cell/link/reach/poi id；WORLD-04 测试锚「每个错误码至少一个 fixture 断言
##   explanation 含定位」的落点）。
static func validate_report(map: MapDataClass, world: WorldDataClass,
		opts := {}) -> Dictionary:
	var errors: Array[Dictionary] = []
	# ---- ① 结构面（WorldData.validate 首错串 → 结构化；错误码取串首「全大写
	#      下划线」token——world_data 各分支的具名码，无码形状错误归
	#      WORLD_DATA_INVALID）----
	var verdict := world.validate(map, int(opts.get("water_terrain_id", -1)),
		int(opts.get("max_road_delta", -1)),
		int(opts.get("max_bridge_bank_delta", -1)))
	if verdict != "":
		errors.append(_error(_code_of(verdict), [], [], "", verdict))
	# ---- ② 出生区可玩面（§11 POI 行：footprint 界内可通行 = NO_VALID_SPAWN；
	#      设施冲突 = POI_FOOTPRINT_CONFLICT——冲突对象逐格指向）----
	var flanks := world.river_flank_cells()
	var banks := {}
	for c in world.crossings:
		banks[c.bank_a] = true
		banks[c.bank_b] = true
	var road_at := {}  # cell_id → 使用该格的 road_id 集（路口重数合法）
	for r in world.roads:
		for cid in r.cells:
			if not road_at.has(cid):
				road_at[cid] = {}
			road_at[cid][r.road_id] = true
	var zones := world.pois_of_kind(WorldDataClass.POIData.Kind.SPAWN_ZONE)
	for z in zones:
		var bad_pass: Array[int] = []
		for cid in z.footprint_cells:
			var cell := _cell_of(map, cid)
			if not map.is_passable(cell):
				bad_pass.append(cid)
		if not bad_pass.is_empty():
			errors.append(_error("NO_VALID_SPAWN", bad_pass, [], "",
				"出生区 poi %d（锚 %d）footprint 含不可通行格 %s（中心+六邻须全可通行——落兵区有效性，§11）"
				% [z.poi_id, z.cell_id, str(bad_pass)]))
		# 设施冲突：河岸锚点格 / 桥端 / 道路格（本区主城服务的路除外）/ 他方出生区
		# （他方区重叠已由 WorldData.POIS 规范序查重面拒绝，此处防御性复核）
		for cid in z.footprint_cells:
			if flanks.has(cid):
				errors.append(_error("POI_FOOTPRINT_CONFLICT", [cid], [],
					"poi:%d" % z.poi_id,
					"出生区 poi %d footprint 格 %d 与河岸锚点格重叠（有河 link 两岸格——格边口径「河床占格」的格级代理，§9 footprint 冲突约束）"
					% [z.poi_id, cid]))
				break
			if banks.has(cid):
				errors.append(_error("POI_FOOTPRINT_CONFLICT", [cid], [],
					"poi:%d" % z.poi_id,
					"出生区 poi %d footprint 格 %d 与桥端格重叠（bank_a/bank_b，§9）"
					% [z.poi_id, cid]))
				break
		# 道路冲突（带服务豁免：含本区主城锚的路可穿本区——WORLD-05 生成侧同款
		# 口径；两端 = 道路骨架的出发/终点必然入区）
		for cid in z.footprint_cells:
			if not road_at.has(cid):
				continue
			var serving := false
			for rid in road_at[cid]:
				var road: WorldDataClass.RoadData = world.road_by_id(int(rid))
				if road != null and road.cells.has(z.cell_id):
					serving = true
					break
			if not serving:
				errors.append(_error("POI_FOOTPRINT_CONFLICT", [cid], [],
					"poi:%d" % z.poi_id,
					"出生区 poi %d footprint 格 %d 与道路 %s 重叠且该路不经本区主城（非服务路不得穿出生区，§9）"
					% [z.poi_id, cid, str(road_at[cid].keys())]))
				break
	# ---- ③ 资源可达面（§11：必需资源可达——规则未启用按平地通行口径 =
	#      边级通行图（passable + Crossing 认领），草案 §11 原文；预算面
	#      resource_budget > 0 时加查环距）----
	var budget := int(opts.get("resource_budget", 0))
	if not zones.is_empty():
		for p in world.pois_of_kind(WorldDataClass.POIData.Kind.RESOURCE):
			var reached := false
			var over_budget_only := true
			var best_anchor := -1
			for z in zones:
				var anchor := _cell_of(map, z.cell_id)
				var conn := GenConnectivity.required_connected(map, world, anchor,
					_cell_of(map, p.cell_id))
				if conn["ok"]:
					over_budget_only = false
					if budget <= 0 or Hex.distance(anchor,
							_cell_of(map, p.cell_id)) <= budget:
						reached = true
						best_anchor = z.cell_id
						break
			if not reached and not over_budget_only:
				errors.append(_error("RESOURCE_UNREACHABLE", [p.cell_id], [],
					"poi:%d" % p.poi_id,
					"资源点 poi %d（格 %d）超出任一出生锚的预算（环距 > %d——可达但过远）"
					% [p.poi_id, p.cell_id, budget]))
			elif not reached:
				# 无任何出生锚可达：指向资源格 + 最近的被阻河段（blocked_river 非空时）
				var links: Array[Vector2i] = []
				var detail := ""
				for z in zones:
					var anchor := _cell_of(map, z.cell_id)
					var reach: Dictionary = GenConnectivity.reachable_set(map, world,
						anchor)["cells"]
					if reach.has(_cell_of(map, p.cell_id)):
						continue
					var blocked: Array = GenConnectivity.reachable_set(map, world,
						anchor)["blocked_river"]
					if not blocked.is_empty():
						var b0: Dictionary = blocked[0]
						links.append(b0["link"])
						detail = "，前沿被河段 reach %d 的边 %s 阻挡（无桥认领）" \
							% [int(b0["reach"]), str(b0["link"])]
				errors.append(_error("RESOURCE_UNREACHABLE", [p.cell_id], links,
					"poi:%d" % p.poi_id,
					"资源点 poi %d（格 %d）自任一出生锚均不可达（平地通行口径：格 passable × 有河 link 须桥认领）%s"
					% [p.poi_id, p.cell_id, detail]))
	# ---- ④ 路网连通面（§11 道路行：必需聚落全连通——聚落图经道路共享格成连通）----
	if bool(opts.get("require_road_network", false)):
		var settlements := world.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT)
		if settlements.size() >= 2:
			var comp := {}
			var idx_of_anchor := {}
			for i in settlements.size():
				comp[i] = i
				idx_of_anchor[settlements[i].cell_id] = i
			for r in world.roads:
				var members: Array[int] = []
				for cid in r.cells:
					if idx_of_anchor.has(cid):
						members.append(int(idx_of_anchor[cid]))
				for k in range(1, members.size()):
					var ra := _find(comp, members[0])
					var rb := _find(comp, members[k])
					if ra != rb:
						comp[ra] = rb
			var roots := {}
			for i in settlements.size():
				var root := _find(comp, i)
				roots[root] = true
			if roots.size() > 1:
				var comps := {}
				for i in settlements.size():
					var root := _find(comp, i)
					if not comps.has(root):
						comps[root] = []
					(comps[root] as Array).append(settlements[i].cell_id)
				var parts: Array = comps.values()
				var cell_ids: Array[int] = []
				for i in settlements.size():
					cell_ids.append(settlements[i].cell_id)
				errors.append(_error("ROAD_NETWORK_DISCONNECTED", cell_ids, [], "",
					"必需聚落未全连通：%d 个聚落分裂为 %d 个道路连通分量 %s（骨架/桥缺失——聚落图 MST 不完整）"
					% [settlements.size(), roots.size(), str(parts)]))
	# ---- ⑤ 锁定约束面（WORLD-04「修复不动 locked」的校验面：道路格禁入锁定格；
	#      豁免 = SETTLEMENT 锚定格——主城锚是路网**必经端点**（连接主城的路必然
	#      含锚格），锁定语义在此 = 主城不动 + 服务性道路到达，绕行面由其余锁定
	#      格承担；锚定出生/资源的保持由修复循环 pins 结构性保证）----
	var locked := {}
	for cid in opts.get("locked_cells", []):
		locked[int(cid)] = true
	if not locked.is_empty():
		var anchors := {}
		for p in world.pois:
			if p.kind == WorldDataClass.POIData.Kind.SETTLEMENT:
				anchors[p.cell_id] = true
		for r in world.roads:
			for cid in r.cells:
				if locked.has(cid) and not anchors.has(cid):
					errors.append(_error("LOCKED_CONSTRAINT_CONFLICT", [cid], [],
						"cell:%d" % cid,
						"道路 %d 的格 %d 落入锁定格（修复/定线不得触碰 locked 约束——WORLD-04 ②）"
						% [r.road_id, cid]))
	# ---- ⑥ 区域验收面（T6 S5；提案 §区域限制 硬约束表 :115-122 的机器面）：
	#      区域事实为空 = 整面零触发（dual_noise/legacy 路线零漂移）；阈值沿
	#      ROAD-01「有配置才判」——opts 缺键 = 不查（-1 哨兵同理）。指标统一由
	#      region_metrics 计算（诊断与判罚同源，不两算）----
	if not world.terrain_regions.is_empty():
		var metrics := region_metrics(map, world, opts)
		_validate_region_dominance(map, world, opts, metrics, errors)
		_validate_region_connectivity(map, world, opts, metrics, errors)
		_validate_region_boundary(map, world, opts, metrics, errors)
		_validate_mountain_valley(map, world, opts, metrics, errors)
		_validate_peak_budget(map, world, opts, metrics, errors)
	return {"ok": errors.is_empty(), "errors": errors}

# ---------------- 区域指标（T6 S5）----------------

## 区域指标（纯函数——playability 阶段诊断与区域判罚的**同源**计算面：一次计算、
##   两处消费，判罚与诊断永不各说各话）。分类阈值从 opts 取（缺省 = 0.7/0.3
##   千分档 + 高程档 0.5×elevation_levels，与既有 regions 视图/有效平原判档
##   同阈——T6 §10 默认答案②「首版自定并进模板」的机器面）。区域事实为空 →
##   返回 {}（调用方不落伪字段）。
## 返回（固定键序、region_id 升序、比率一律 4 位小数——同 seed 可 diff）：
##   {"region_count": int,
##    "regions": [{region_id, landform("mountains"/"plains"), core_cells,
##      core_land, core_passable, mountain_class, plain_class,
##      dominant_ratio（群山区 = 山地类占比 / 平原区 = 平原类占比——分母恒 =
##      核心格数，提案 :123「统计分母 = 区域核心范围」）,
##      passable_components, largest_component, largest_ratio（分母 = 核心通行格）,
##      valley_usable, valley_outlet}],
##    "transition": {cells, mountain_class, plain_class, mid_class, water}
##      ——过渡带（不属任何核心的格）单独统计、只报不判（提案 :123）,
##    "peaks": {count, influence_cells, effective_plain_cells, budget_ratio},
##    "boundary": {boundary_pairs, boundary_max_elev_delta}}
static func region_metrics(map: MapDataClass, world: WorldDataClass,
		opts := {}) -> Dictionary:
	if world.terrain_regions.is_empty():
		return {}
	var mcw := int(round(float(opts.get("region_mountain_class_weight", 0.70)) * 1000.0))
	var pcw := int(round(float(opts.get("region_plain_class_weight", 0.30)) * 1000.0))
	# 山地类高程档下限（分类的高程面：宽谷/盆地下切落低档 → 非山地类——占比区间
	# 的「山地丘陵 vs 谷地」二分由权重 × 高程两维构成，提案 :129）
	var levels := maxi(1, int(opts.get("elevation_levels", 4)))
	var elev_floor := int(ceil(clampf(
		float(opts.get("region_mountain_class_elev_min", 0.50)), 0.0, 1.0) * float(levels)))
	var cell_n := map.cell_count()
	# 核心归属表（cell → region_id）——过渡带 = 不属任何核心的格
	var core_of := {}
	for rg in world.terrain_regions:
		for cid in rg.core_cells:
			core_of[cid] = rg.region_id
	# 逐格类属（一次线性扫，全区域共用）：水 / 山地类（陆 ∧ mw ≥ mcw ∧ 高程 ≥
	# elev_floor）/ 平原类（陆 ∧ mw ≤ pcw）/ 中间类（陆 ∧ 其余）
	var cells := map.cells()
	var is_water := {}
	var mountain_class := {}
	var plain_class := {}
	for i in cell_n:
		var cell: Vector2i = cells[i]
		var water := map.elevation_at(cell) == 0
		is_water[i] = water
		if water:
			continue
		var w := world.cell_mountain_weights[i] if i < world.cell_mountain_weights.size() else 0
		if w >= mcw and map.elevation_at(cell) >= elev_floor:
			mountain_class[i] = true
		elif w <= pcw:
			plain_class[i] = true
	# 宽谷 → 所属区域的可用（通行）格集（谷底可能被海/湖吞没——只计可用面）
	var valley_by_region := {}
	var range_region := {}
	for mr in world.mountain_ranges:
		range_region[mr.range_id] = mr.region_id
	for vl in world.valleys:
		var rid: int = int(range_region.get(vl.range_id, -1))
		if rid < 0:
			continue
		if not valley_by_region.has(rid):
			valley_by_region[rid] = {}
		for cid in vl.cells:
			if map.is_passable(_cell_of(map, cid)):
				(valley_by_region[rid] as Dictionary)[cid] = true
	# 逐区域指标（terrain_regions 已按 region_id 升序——规范序即输出序）
	var regions_out: Array = []
	for rg in world.terrain_regions:
		var core_set := {}
		for cid in rg.core_cells:
			core_set[cid] = true
		var core_n := rg.core_cells.size()
		var land_n := 0
		var passable_n := 0
		var m_class := 0
		var p_class := 0
		for cid in rg.core_cells:
			if not is_water[cid]:
				land_n += 1
			if map.is_passable(_cell_of(map, cid)):
				passable_n += 1
			if mountain_class.has(cid):
				m_class += 1
			if plain_class.has(cid):
				p_class += 1
		var is_mountains := rg.dominant_landform \
			== WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS
		var dominant := m_class if is_mountains else p_class
		# 核心内通行格连通片（边只计两端都在核心内的——「区域核心范围的
		# 可用连通」；边界外的过渡带格不计入本区片）
		var visited := {}
		var components := 0
		var largest := 0
		for cid in rg.core_cells:
			if visited.has(cid) or not map.is_passable(_cell_of(map, cid)):
				continue
			components += 1
			var size := 0
			var queue: Array[int] = [cid]
			visited[cid] = true
			var head := 0
			while head < queue.size():
				var cur: int = queue[head]
				head += 1
				size += 1
				for nb in map.neighbors_existing(_cell_of(map, cur)):
					var j := map.index_of(nb)
					if visited.has(j) or not core_set.has(j) \
							or not map.is_passable(nb):
						continue
					visited[j] = true
					queue.append(j)
			largest = maxi(largest, size)
		# 谷地对外通路：自本区可用谷底格沿通行图 BFS，抵达任一异区格 = 有通路
		#（「群山不仅有山峰，也有满足通达要求的谷地」的机器表达——全图 BFS，
		# 只看格 passable，与 MapConnectivity 口径同族）
		var valley_usable := 0
		var valley_outlet := false
		if valley_by_region.has(rg.region_id):
			var usable: Dictionary = valley_by_region[rg.region_id]
			valley_usable = usable.size()
			var seen := {}
			var vq: Array[int] = []
			for cid in usable:
				vq.append(int(cid))
				seen[cid] = true
			var vhead := 0
			while vhead < vq.size() and not valley_outlet:
				var cur: int = vq[vhead]
				vhead += 1
				for nb in map.neighbors_existing(_cell_of(map, cur)):
					var j := map.index_of(nb)
					if not map.is_passable(nb) or seen.has(j):
						continue
					var rj: int = world.cell_regions[j] if j < world.cell_regions.size() else -1
					if rj != rg.region_id:
						valley_outlet = true
						break
					seen[j] = true
					vq.append(j)
		regions_out.append({
			"region_id": rg.region_id,
			"landform": "mountains" if is_mountains else "plains",
			"core_cells": core_n,
			"core_land": land_n,
			"core_passable": passable_n,
			"mountain_class": m_class,
			"plain_class": p_class,
			"dominant_ratio": _round4(float(dominant) / float(core_n)) if core_n > 0 else 0.0,
			"passable_components": components,
			"largest_component": largest,
			"largest_ratio": _round4(float(largest) / float(passable_n)) if passable_n > 0 else 0.0,
			"valley_usable": valley_usable,
			"valley_outlet": valley_outlet,
		})
	# 过渡带单独统计（只报不判——提案 :123；分类口径与核心一致）
	var t_cells := 0
	var t_mountain := 0
	var t_plain := 0
	var t_mid := 0
	var t_water := 0
	for i in cell_n:
		if core_of.has(i):
			continue
		t_cells += 1
		if is_water[i]:
			t_water += 1
		elif mountain_class.has(i):
			t_mountain += 1
		elif plain_class.has(i):
			t_plain += 1
		else:
			t_mid += 1
	# 孤峰面：影响格并集（距任一峰中心 ≤ 影响半径，去重）+ 有效平原分母
	#（陆 ∧ mw ≤ pcw——与 TerrainComposition.EFFECTIVE_PLAIN_WEIGHT_MAX 同阈；
	# 预算口径 = 并集而非 Σ 各峰——重叠山脚不重复计面积）
	var influence := {}
	for pk in world.isolated_peaks:
		var center := _cell_of(map, pk.cell_id)
		for other in cells:
			if Hex.distance(center, other) <= pk.influence_radius:
				influence[map.index_of(other)] = true
	var effective_plain := 0
	for i in cell_n:
		if not is_water[i] and plain_class.has(i):
			effective_plain += 1
	# 边界面：异区相邻对（cell_region 不同）高程差——量化图口径（与 S3 验收
	# 「异区相邻对 Δ ≤ 2」同轴；无向边只查一次）
	var boundary_pairs := 0
	var boundary_max_delta := 0
	for i in cell_n:
		var ri: int = world.cell_regions[i] if i < world.cell_regions.size() else -1
		for nb in map.neighbors_existing(cells[i]):
			var j := map.index_of(nb)
			if j <= i:
				continue
			var rj: int = world.cell_regions[j] if j < world.cell_regions.size() else -1
			if ri == rj:
				continue
			boundary_pairs += 1
			boundary_max_delta = maxi(boundary_max_delta,
				absi(map.elevation_at(cells[i]) - map.elevation_at(nb)))
	return {
		"region_count": world.terrain_regions.size(),
		"regions": regions_out,
		"transition": {"cells": t_cells, "mountain_class": t_mountain,
			"plain_class": t_plain, "mid_class": t_mid, "water": t_water},
		"peaks": {"count": world.isolated_peaks.size(),
			"influence_cells": influence.size(),
			"effective_plain_cells": effective_plain,
			"budget_ratio": _round4(float(influence.size()) / float(effective_plain)) \
				if effective_plain > 0 else 0.0},
		"boundary": {"boundary_pairs": boundary_pairs,
			"boundary_max_elev_delta": boundary_max_delta},
	}

# ---------------- 内部 ----------------

## cell 稳定 ID → axial 格（WorldData._cell_of_id 同式；校验器侧自持只读版——
## 避免跨文件私有依赖，SettlementGenerator.cell_of_id / RiverNetworkGenerator
## 同款先例）。
static func _cell_of(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))

## 错误对象构造（固定键序——报告可 diff）。
static func _error(code: String, cell_ids: Array[int], link_ids: Array[Vector2i],
		constraint_id: String, explanation: String) -> Dictionary:
	return {"code": code, "cell_ids": cell_ids, "link_ids": link_ids,
		"constraint_id": constraint_id, "explanation": explanation}

## world_data 校验串 → 错误码（串首「：」前 token 且全部字符 ∈ [A-Z0-9_] 才认码
## ——RIVER_CYCLE / WATER_SEA_OUTLET 等；无码形状错误 → WORLD_DATA_INVALID，
## 仍带全文 explanation 定位）。
static func _code_of(verdict: String) -> String:
	var head := verdict.split("：")[0]
	var ok := not head.is_empty()
	for ch in head:
		if not (ch == "_" or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			ok = false
			break
	return head if ok else "WORLD_DATA_INVALID"

static func _find(comp: Dictionary, i: int) -> int:
	var root := i
	while comp[root] != root:
		root = comp[root]
	return root

# ---------------- 区域验收判罚（T6 S5 内部件）----------------

## 比率规范 4 位小数（阶段诊断/报告可 diff 的浮点纪律——直接落 float 会带
## 全精度尾差）。
static func _round4(v: float) -> float:
	return roundf(v * 10000.0) / 10000.0

## opts 阈值取数（缺键 / 负哨兵 = 该界不查——「有配置才判」的统一取数面）。
static func _opt_threshold(opts: Dictionary, key: String) -> float:
	var v := float(opts.get(key, -1.0))
	return v if v >= 0.0 else -1.0

## ① 区域主导性（提案验收表 :267 + 硬约束表占比行）：群山区山地类占比 /
##   平原区平原类占比落在模板区间内（分母 = 区域核心格数）。不合格区域逐个
##   报错——explanation 恒含区域编号（提案 :267「输出不合格区域编号」）。
static func _validate_region_dominance(map: MapDataClass, world: WorldDataClass,
		opts: Dictionary, metrics: Dictionary, errors: Array) -> void:
	var m_min := _opt_threshold(opts, "mountains_core_ratio_min")
	var m_max := _opt_threshold(opts, "mountains_core_ratio_max")
	var p_min := _opt_threshold(opts, "plains_core_ratio_min")
	var p_max := _opt_threshold(opts, "plains_core_ratio_max")
	if m_min < 0.0 and m_max < 0.0 and p_min < 0.0 and p_max < 0.0:
		return  # 无配置不判（ROAD-01 先例）
	for m in metrics["regions"]:
		var rm: Dictionary = m
		var is_mountains := String(rm["landform"]) == "mountains"
		var lo := m_min if is_mountains else p_min
		var hi := m_max if is_mountains else p_max
		var ratio := float(rm["dominant_ratio"])
		if (lo < 0.0 or ratio >= lo) and (hi < 0.0 or ratio <= hi):
			continue
		var rg := world.region_by_id(int(rm["region_id"]))
		var sample := _sample_cells(rg.core_cells if rg != null else [], 8)
		errors.append(_error("REGION_DOMINANCE", sample, [],
			"region:%d" % int(rm["region_id"]),
			"区域 %d（%s）核心地貌占比 %s 出区间[%s, %s]（山地类 %d/平原类 %d / 核心 %d 格——提案 :123 分母=核心范围，%s 起调带）"
			% [int(rm["region_id"]), "群山主导" if is_mountains else "平原主导",
				str(ratio), str(lo), str(hi), int(rm["mountain_class"]),
				int(rm["plain_class"]), int(rm["core_cells"]),
				"60%~80%" if is_mountains else "70%~90%"]))

## ② 区域连通性（提案硬约束表平原行「最大可用连通片达到配置要求」：268）：
##   区域核心通行格的最大连通片占核心通行格比 ≥ 下限（「可用」= 格 passable，
##   MapConnectivity 同口径；边只计两端都在核心内——跨过渡带的连接不冒充
##   区内可用）。
static func _validate_region_connectivity(map: MapDataClass, world: WorldDataClass,
		opts: Dictionary, metrics: Dictionary, errors: Array) -> void:
	var need := _opt_threshold(opts, "region_largest_component_ratio")
	if need < 0.0:
		return
	for m in metrics["regions"]:
		var rm: Dictionary = m
		var ratio := float(rm["largest_ratio"])
		if ratio >= need:
			continue
		var rg := world.region_by_id(int(rm["region_id"]))
		var sample := _sample_cells(rg.core_cells if rg != null else [], 8)
		errors.append(_error("REGION_CONNECTIVITY", sample, [],
			"region:%d" % int(rm["region_id"]),
			"区域 %d（%s）核心最大可用连通片占比 %s < %s（%d 个连通片，最大 %d / 通行 %d 格——核心被水/断带切碎）"
			% [int(rm["region_id"]), String(rm["landform"]), str(ratio), str(need),
				int(rm["passable_components"]), int(rm["largest_component"]),
				int(rm["core_passable"])]))

## ③ 边界过渡（提案验收表 :271「无分区编号导致的高度断缝」）：异区相邻对
##   （cell_region 不同）量化高程差 ≤ 上限（与 S3 验收锚「Δ ≤ 2」同口径——
##   阶跃的机器表达取量化图而非连续场：连续场留证在 composition 诊断，此处是
##   投影后的终态判罚）。首个越阶对起报、最多 4 对（定位足够，不刷屏）。
static func _validate_region_boundary(map: MapDataClass, world: WorldDataClass,
		opts: Dictionary, metrics: Dictionary, errors: Array) -> void:
	var max_step := _opt_threshold(opts, "region_boundary_max_step")
	if max_step < 0.0:
		return
	var limit := int(floor(max_step))
	var cells := map.cells()
	var reported := 0
	var worst_pairs: Array[int] = []
	var worst_delta := 0
	for i in cells.size():
		var ri: int = world.cell_regions[i] if i < world.cell_regions.size() else -1
		for nb in map.neighbors_existing(cells[i]):
			var j := map.index_of(nb)
			if j <= i:
				continue
			var rj: int = world.cell_regions[j] if j < world.cell_regions.size() else -1
			if ri == rj:
				continue
			var delta := absi(map.elevation_at(cells[i]) - map.elevation_at(nb))
			if delta <= limit:
				continue
			worst_delta = maxi(worst_delta, delta)
			if reported < 4:
				worst_pairs.append(i)
				worst_pairs.append(j)
			reported += 1
	if reported > 0:
		var sample: Array[int] = []
		for cid in worst_pairs:
			sample.append(int(cid))
		errors.append(_error("REGION_BOUNDARY_STEP", sample, [], "",
			"分区边界高度断缝：异区相邻对高程差 %d > %d 的对子共 %d 处（首例格 %s——区域编号不得制造阶跃，提案 :271）"
			% [worst_delta, limit, reported, str(worst_pairs)]))

## ④ 山地可用性（提案验收表 :272 + 硬约束表群山行「保留必要可用谷地及对外
##   通路」）：每个群山区可用（通行）谷底格 ≥ 下限，且谷地沿通行图可达任一
##   异区格（对外通路）。下限 0 = 面积不查（通路仍查——通路是布尔硬约束）。
static func _validate_mountain_valley(map: MapDataClass, world: WorldDataClass,
		opts: Dictionary, metrics: Dictionary, errors: Array) -> void:
	var need := _opt_threshold(opts, "region_min_valley_cells")
	if need < 0.0:
		return
	var limit := int(floor(need))
	for m in metrics["regions"]:
		var rm: Dictionary = m
		if String(rm["landform"]) != "mountains":
			continue
		var usable := int(rm["valley_usable"])
		var outlet := bool(rm["valley_outlet"])
		if usable >= limit and outlet:
			continue
		var rg := world.region_by_id(int(rm["region_id"]))
		var sample: Array[int] = []
		if rg != null:
			sample = _sample_cells(rg.core_cells, 8)
		var reason := "可用谷地格 %d < %d（谷地面积不足）" % [usable, limit] \
			if usable < limit else "谷地无对外通路（通行图抵达不了任何异区格）"
		errors.append(_error("MOUNTAIN_VALLEY", sample, [],
			"region:%d" % int(rm["region_id"]),
			"群山区 %d 山地可用性不合格：%s（提案 :272 最小谷地面积与通达要求）"
			% [int(rm["region_id"]), reason]))

## ⑤ 孤峰预算（提案 :131「总影响面积 ≤ 有效平原面积 × 预算比例」）：并集
##   影响格数 > ⌊有效平原 × ratio⌋ = 超预算（0 = 零峰合法态——任何影响格
##   都算超）。生成侧构造保证（TerrainComposition.place_isolated_peaks），
##   此处按终态事实独立复查——「构造保证 + 校验器双断言」沿 WORLD-02 先例。
static func _validate_peak_budget(map: MapDataClass, world: WorldDataClass,
		opts: Dictionary, metrics: Dictionary, errors: Array) -> void:
	var ratio := _opt_threshold(opts, "peak_area_budget_ratio")
	if ratio < 0.0:
		return
	var pk: Dictionary = metrics["peaks"]
	var effective := int(pk["effective_plain_cells"])
	var budget := int(floor(float(effective) * ratio))
	var influence := int(pk["influence_cells"])
	if influence <= budget:
		return
	var centers: Array[int] = []
	for p in world.isolated_peaks:
		centers.append(p.cell_id)
	errors.append(_error("PEAK_AREA_BUDGET", _sample_cells(centers, 8), [], "peaks:budget",
		"孤峰影响面积超预算：并集 %d 格 > ⌊有效平原 %d × %s⌋ = %d（峰 %d 座——提案 :131 起调 5%%）"
		% [influence, effective, str(ratio), budget, int(pk["count"])]))

## 升序格列表取样前 n 格（错误定位样本——控制报文体积，不搬运全量核心）。
static func _sample_cells(cells_src: Array[int], n: int) -> Array[int]:
	var out: Array[int] = []
	for i in mini(cells_src.size(), n):
		out.append(cells_src[i])
	return out
