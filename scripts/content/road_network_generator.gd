## road_network_generator.gd — 道路骨架与绕行自动生成器（T5 WORLD-05；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-05——自 T4 ROAD-03 上移
##   （修订记录三之 6）+ §1 Azgaar routes-generator 连通加成思路 + §5 ROAD-02
##   桥放置规则三条的格边转译）
## 算法（固定顺序——卡表风险栏「桥址搜索与定线互相依赖」的对策面）：
##   ① 桥址枚举（先于一切定线）：逐 reach 枚举有河 link——硬合法 = 桥头 Δ ≤
##      max_bridge_bank_delta ∧ 净空（max 两岸高程 ≥ 该边水位）；偏好排除 = 急弯
##      中边（edge[k] 与 edge[k+2] 不平行 ⇒ 中边急弯，拍板⑩走向几何版）与 reach
##      首尾边（源/终点不设桥）——ROAD-02 ③「降为候选偏好非硬约束」：tier1 =
##      硬∧偏好，tier2 = 仅硬（tier1 不足以连通才启用）；桥端落点另须避开锁定格/
##      资源 footprint/出生区 footprint（桥端是路面的事实先验）；
##   ② 骨架拓扑：聚落对两两 Dijkstra（生成器内部路径成本：步进 1 + 高差分级
##      Δ×ROAD_DELTA_COST + 地形带费 平原低/丘中/山高 + 绕水 = 水格不入图 +
##      河界加成 = 过开放河 link +ROAD_RIVER_COST——Azgaar getHeightCost 地形版
##      结构沿用，§6 WORLD-05 ①；路径权重是生成器内部口径**不进数据**，草案 §7
##      禁止项）→ 聚落图 MST（Kruskal，并列取聚落对字典序——确定性）；
##   ③ 定线与桥：按 MST 边逐条落路（已用 link 禁复用——ROAD_LINK_REUSE 的构造期
##      保证）；路径跨过未认领河 link = 在该桥址建 CrossingData（认领语义，拍板⑤
##      「路是格中心与格中心之间，河是单纯沿着边，交叉时就是桥」）；每条落路后
##      即时全量重验；
##   ④ 可选回路：非 MST 对按成本升序补路（road_loop_count 上限），**每次加路后
##      可达性/footprint 全量重验**（复用 WORLD-04 校验器，§6 WORLD-05 ③）；
##      重验不过 = 弃回路回滚（不破硬约束）；
##   ⑤ 失败两出路（提案明示）：必需连接（MST 对）无法连通 → 具名失败
##      ROAD_NETWORK_DISCONNECTED（指向聚落对与阻挡河段）——不删河/不压山伪造
##      达标；候选回路不可行 → 放弃该候选（合法出路之二）。
## 只读合同：不写 MapData；道路/桥产出经调用侧（WorldPipeline 道路阶段）组装进
##   WorldData 并全量校验（link 表 road_id 面在此更新——river link 上桥 = 「河在
##   下、路在上」认领）。确定性 = 同 map 同 world 同 cfg 同 rng 序列 → 同产出；
##   rng（可选）只消费**等成本路径并列**（50% 重挂 parent 的改道面——roads 通道
##   的唯一消耗点，WORLD-04 roads_reconnect 修复重跑的实现载体：bump roads 通道
##   → 并列改道变 → 路网事实可变；rng=null = 零消耗的确定性路网，手工 fixture
##   直连面沿用）。MST 并列取聚落对字典序钉死（不经 rng——骨架拓扑稳定）。
class_name RoadNetworkGenerator
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const SettlementGen := preload("res://scripts/content/settlement_generator.gd")
const WorldValidator := preload("res://scripts/content/world_validator.gd")

## 生成配置键集（WorldTemplate infrastructure 组投影 + 调用侧补充量化链与锁定面）
const CFG_KEYS := ["water_terrain_id", "max_road_delta", "max_bridge_bank_delta",
	"road_loop_count", "sea_level", "elevation_levels"]

## 路径成本表（生成器内部口径不进数据；Azgaar getHeightCost 结构沿用：平原低费/
## 丘中费/山高费/水极高费——水格不入图即「绕水」；数值未拍板随模板重定，变更 =
## GENERATOR_VERSION+1）
const ROAD_COST_PLAIN := 1
const ROAD_COST_HILL := 4
const ROAD_COST_MOUNTAIN := 12
## 每级高差的路径加费（高差分级；硬上限 max_road_delta 由生成配置拒绝——
## ROAD-01 ③ Δ 超限不修路）
const ROAD_DELTA_COST := 2
## 河界加成（过开放河 link 的路径加费——桥址与路径共用该口径）
const ROAD_RIVER_COST := 20
## 等成本并列改道概率（rng 在场时，WORLD-04 roads_reconnect 的改道强度：0.5 =
## 每次并列半数改挂——bump 通道后路形显著可变、又不过度抖动；数值属生成器
## 口径，变更 = GENERATOR_VERSION+1）
const REROUTE_TIE_P := 0.5

## 生成入口。rng（可选，缺省 null = 零消耗）= roads 通道注入面：等成本路径并列
##   处 50% 重挂 parent（改道面——见类头注）。返回 {"ok", "error", "roads":
##   Array[RoadData], "crossings": Array[CrossingData], "links":
##   Array[NeighborLinkData]（river 表全量 + road_id 面——含桥认领边的
##   river_reach_id 原样保留；条目全部新建，不共享既有对象——回路回滚不污染
##   river 表）, "stats": {…}}。
## settlements < 2 → 合法空产出（单聚落无路可连——「必需聚落全连通」平凡成立）。
static func generate(map: MapDataClass, world: WorldDataClass, cfg: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var fail := {"ok": false, "error": "", "roads": [], "crossings": [],
		"links": [], "stats": {}}
	if not cfg.has_all(CFG_KEYS):
		fail["error"] = "路网生成配置缺键：%s（got %s）" % [str(CFG_KEYS), str(cfg.keys())]
		return fail
	var settlements := world.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT)
	if settlements.size() < 2:
		return {"ok": true, "error": "", "roads": [], "crossings": [],
			"links": _copy_links(world), "stats": {
				"settlements": settlements.size(), "trunk": 0, "loops": 0,
				"crossings": 0, "tier2_used": false}}

	var hill_level := SettlementGen.level_of_h(SettlementGen.H_HILL,
		float(cfg["sea_level"]), int(cfg["elevation_levels"]))
	var mountain_level := SettlementGen.level_of_h(SettlementGen.H_MOUNTAIN,
		float(cfg["sea_level"]), int(cfg["elevation_levels"]))
	var river_idx := world.river_edge_index()
	var claims := world.crossing_index()

	# ---- 禁入面（道路格不得落入）：锁定格（修复不动 locked）+ 资源 footprint +
	# 出生区 footprint——连接 A/B 的路可穿 A/B 两区（validator 同款豁免口径），
	# 穿第三区 = footprint 冲突（§9 footprint 冲突约束）----
	var locked := {}
	for cid in cfg.get("locked_cells", []):
		locked[int(cid)] = true
	var base_forbidden := locked.duplicate()
	var zone_of_anchor := {}  # 主城格 → SPAWN_ZONE POI（逐对放行的查表面）
	for p in world.pois:
		if p.kind == WorldDataClass.POIData.Kind.RESOURCE:
			base_forbidden[p.cell_id] = true
		elif p.kind == WorldDataClass.POIData.Kind.SPAWN_ZONE:
			for cid in p.footprint_cells:
				base_forbidden[cid] = true
			zone_of_anchor[p.cell_id] = p

	# ---- ① 桥址枚举（tier1 = 硬合法∧偏好；tier2 = 仅硬合法的兜底档）----
	var sites := _bridge_sites(map, world, int(cfg["max_bridge_bank_delta"]),
		base_forbidden)
	var claims_open := {}
	for link in claims:
		claims_open[link] = true  # 既有认领边即可渡（无需新桥址）
	var open1 := claims_open.duplicate()
	for link in sites["tier1"]:
		open1[link] = true

	# ---- ② 骨架拓扑：两两 Dijkstra（tier1 图）→ 不可达对放开 tier2 重算 ----
	var n := settlements.size()
	var pair_cost := {}
	for a in n:
		var res := _dijkstra(map, settlements[a].cell_id, open1, river_idx,
			_forbidden_for(base_forbidden, zone_of_anchor, settlements, a, -1),
			int(cfg["max_road_delta"]), hill_level, mountain_level, {}, rng)
		for b in range(a + 1, n):
			pair_cost[[a, b]] = res["cost"][settlements[b].cell_id]
	var tier2_used := false
	var blocked: Array = []
	for key in pair_cost:
		if pair_cost[key] >= INF:
			blocked.append(key)
	var routing_open := open1
	if not blocked.is_empty():
		# tier2 兜底（「相隔两边平行」等偏好让位于连通——偏好非硬约束，ROAD-02 ③）
		tier2_used = true
		routing_open = open1.duplicate()
		for link in sites["tier2"]:
			routing_open[link] = true
		for key in blocked:
			var a: int = key[0]
			var b: int = key[1]
			var res := _dijkstra(map, settlements[a].cell_id, routing_open, river_idx,
				_forbidden_for(base_forbidden, zone_of_anchor, settlements, a, b),
				int(cfg["max_road_delta"]), hill_level, mountain_level, {}, rng)
			pair_cost[key] = res["cost"][settlements[b].cell_id]
			if pair_cost[key] >= INF:
				return _disconnected_fail(map, settlements, key, routing_open,
					river_idx, fail)
	# Kruskal MST（边按 (cost, 聚落对字典序) 排序——确定性）
	var edges: Array = []
	for key in pair_cost:
		if pair_cost[key] < INF:
			edges.append({"pair": key, "cost": pair_cost[key]})
	edges.sort_custom(_pair_edge_order)
	var mst_pairs: Array = []
	var comp := {}
	for i in n:
		comp[i] = i
	for e in edges:
		var pair: Array = e["pair"]
		var ra := _find_comp(comp, pair[0])
		var rb := _find_comp(comp, pair[1])
		if ra == rb:
			continue
		comp[ra] = rb
		mst_pairs.append(pair)
		if mst_pairs.size() == n - 1:
			break

	# ---- ③ 定线与桥（tier1/tier2 统一在 routing_open 图上——拓扑与定线同一张
	#      开放图，避免「拓扑可达、定线不可达」的口径分裂）----
	var roads: Array[WorldDataClass.RoadData] = []
	var crossings: Array[WorldDataClass.CrossingData] = []
	var used_links := {}
	var next_road := 0
	var next_crossing := 0
	for pair in mst_pairs:
		var a: int = pair[0]
		var b: int = pair[1]
		var res := _dijkstra(map, settlements[a].cell_id, routing_open, river_idx,
			_forbidden_for(base_forbidden, zone_of_anchor, settlements, a, b),
			int(cfg["max_road_delta"]), hill_level, mountain_level, used_links, rng)
		var path := _trace_path(res["parent"], settlements[a].cell_id,
			settlements[b].cell_id)
		if path.is_empty():
			return _disconnected_fail(map, settlements, pair, routing_open,
				river_idx, fail)
		var placed := _place_road(roads, crossings, used_links, path, river_idx,
			next_road, next_crossing)
		next_road = placed["next_road"]
		next_crossing = placed["next_crossing"]
		var verdict := _revalidate(map, world, roads, crossings, cfg)
		if verdict != "":
			fail["error"] = "ROAD_NETWORK_DISCONNECTED：必需连接（聚落 %d ↔ %d，poi %d/%d）定线后全量重验失败：%s" \
				% [settlements[a].cell_id, settlements[b].cell_id,
					settlements[a].poi_id, settlements[b].poi_id, verdict]
			return fail

	# ---- ④ 可选回路：非 MST 对升序补路；重验不过 = 回滚弃路（不破硬约束）----
	var loops := 0
	for e in edges:
		if loops >= int(cfg["road_loop_count"]):
			break
		var pair: Array = e["pair"]
		var in_mst := false
		for m in mst_pairs:
			if m[0] == pair[0] and m[1] == pair[1]:
				in_mst = true
				break
		if in_mst:
			continue
		var a: int = pair[0]
		var b: int = pair[1]
		var res := _dijkstra(map, settlements[a].cell_id, routing_open, river_idx,
			_forbidden_for(base_forbidden, zone_of_anchor, settlements, a, b),
			int(cfg["max_road_delta"]), hill_level, mountain_level, used_links, rng)
		var path := _trace_path(res["parent"], settlements[a].cell_id,
			settlements[b].cell_id)
		if path.is_empty():
			continue  # 放弃候选回路（合法出路之二，提案明示）
		var road_count := roads.size()
		var cross_count := crossings.size()
		var placed := _place_road(roads, crossings, used_links, path, river_idx,
			next_road, next_crossing)
		if _revalidate(map, world, roads, crossings, cfg) != "":
			# 回路破硬约束 → 回滚该路（「可选回路不能突破硬约束」，§6 WORLD-05 ①）
			roads.resize(road_count)
			crossings.resize(cross_count)
			for link in placed["new_links"]:
				used_links.erase(link)
			continue
		next_road = placed["next_road"]
		next_crossing = placed["next_crossing"]
		loops += 1

	return {"ok": true, "error": "", "roads": roads, "crossings": crossings,
		"links": _links_with_roads(world, roads), "stats": {
			"settlements": n, "trunk": mst_pairs.size(), "loops": loops,
			"crossings": crossings.size(), "tier2_used": tier2_used}}

# ---------------- ① 桥址枚举 ----------------

## 逐 reach 枚举合法桥址：硬合法（桥头 Δ ≤ max_bridge_bank_delta ∧ 净空
## max(两岸) ≥ 水位——world_data 校验同口径）∧ 桥端不入禁入面；偏好排除
## （急弯中边 + reach 首尾边 + 已认领边）后 = tier1，仅硬合法 = tier2。
## 返回 {"tier1": {link: true}, "tier2": {link: true}}（tier2 ⊇ tier1）。
static func _bridge_sites(map: MapDataClass, world: WorldDataClass,
		max_bridge_bank_delta: int, forbidden: Dictionary) -> Dictionary:
	var claims := world.crossing_index()
	var tier1 := {}
	var tier2 := {}
	for r in world.rivers:
		for k in r.edges.size():
			var link := r.edges[k]
			if claims.has(link):
				continue  # 已认领边即可渡——无需新桥址
			var ea := map.elevation_at(SettlementGen.cell_of_id(map, link.x))
			var eb := map.elevation_at(SettlementGen.cell_of_id(map, link.y))
			# 硬合法两件（ROAD-02 ③ 首版桥址合法性）：桥头 Δ 与净空
			if max_bridge_bank_delta >= 0 and absi(ea - eb) > max_bridge_bank_delta:
				continue
			if maxi(ea, eb) < r.water_levels[k]:
				continue
			# 桥端落点 = 河岸锚点格——禁入面同道路（锁定格/资源/出生区 footprint）
			if forbidden.has(link.x) or forbidden.has(link.y):
				continue
			tier2[link] = true
			# 偏好排除：首尾边（源/终点不设桥）；急弯中边 = 存在 kk 使 edge[kk] 与
			# edge[kk+2] 不平行且本边居中（k ∈ {kk+1, kk+2} 覆盖两向——拍板⑩走向
			# 几何版，判据复用 WorldData 公开合同；首尾索引越界 = 非急弯，判据自带）
			if k == 0 or k == r.edges.size() - 1:
				continue
			var sharp := false
			for kk in [k - 2, k - 1]:
				if WorldDataClass.river_bend_is_sharp(map, r, kk):
					sharp = true
					break
			if sharp:
				continue
			tier1[link] = true
	return {"tier1": tier1, "tier2": tier2}

# ---------------- ② Dijkstra（生成器内部路径成本）----------------

## 单源 Dijkstra：成本 = 步进 1 + 地形带费(目的格) + Δ×ROAD_DELTA_COST + 过开放
## 河 link +ROAD_RIVER_COST；边禁 = Δ > max_road_delta / 水格 / 禁入格 / 未开放
## 河 link / used_links（一 link 至多一路）。返回 {"cost": Array[float],
## "parent": Array[int]}（不可达 cost=INF）。
## 并列处置（成本全为整值和 → 浮点 == 恒精确）：严格更优必更新；**等成本并列**
## rng=null 时先见者胜（堆数组结构序——非 cell_id 序，仅确定性成立）、rng 在场时
## 50% 概率重挂 parent（等成本改道：roads 通道消耗点，WORLD-04 roads_reconnect
## 修复重跑的实现载体）。同输入同 rng 序列 → 同产出（复现口径保持）。
static func _dijkstra(map: MapDataClass, start: int, open_links: Dictionary,
		river_idx: Dictionary, forbidden: Dictionary, max_road_delta: int,
		hill_level: int, mountain_level: int, used_links := {},
		rng: RandomNumberGenerator = null) -> Dictionary:
	var n := map.cell_count()
	var cost: Array[float] = []
	var parent: Array[int] = []
	cost.resize(n)
	parent.resize(n)
	for i in n:
		cost[i] = INF
		parent[i] = -1
	cost[start] = 0.0
	var heap := SettlementGen.MinHeap.new()
	heap.push(0.0, 0, start)
	while heap.size() > 0:
		var top := heap.pop()
		var u: int = top[2]
		if top[0] > cost[u]:
			continue
		var uc := SettlementGen.cell_of_id(map, u)
		var eu := map.elevation_at(uc)
		for d in 6:
			var nb := Hex.neighbor(uc, d)
			if not map.has_cell(nb):
				continue
			var v := map.index_of(nb)
			if forbidden.has(v):
				continue
			# 绕水：水格不入图（passable=false 结算面 + elevation 0 双保险）
			if map.elevation_at(nb) == 0 or not map.is_passable(nb):
				continue
			var ev := map.elevation_at(nb)
			# 高差分级：软费恒计、硬上限拒边（Δ 超限不修路——ROAD-01 ③ 生成配置口径）
			var delta := absi(eu - ev)
			if delta > max_road_delta:
				continue
			var link := WorldDataClass.link_id_of(u, v)
			if used_links.has(link):
				continue
			var step := 1.0 + float(_road_band_cost(ev, hill_level, mountain_level)) \
				+ float(delta) * float(ROAD_DELTA_COST)
			if river_idx.has(link):
				if not open_links.has(link):
					continue  # 未开放（无桥址/无认领）的有河 link = 禁渡
				step += float(ROAD_RIVER_COST)  # 河界加成（有桥也要付——过河贵）
			var nd: float = cost[u] + step
			if nd < cost[v]:
				cost[v] = nd
				parent[v] = u
				heap.push(nd, 0, v)
			elif nd == cost[v] and rng != null and rng.randf() < REROUTE_TIE_P:
				# 等成本改道：cost 不变、parent 换路（roads 通道唯一消耗点——
				# 不入堆：等价堆项已在队，过期项判定按 cost 依然有效）
				parent[v] = u
	return {"cost": cost, "parent": parent}

## 地形带费（进入格）：平原低费/丘中费/山高费（水不入图——「水极高费」的绕行表达）。
static func _road_band_cost(level: int, hill_level: int, mountain_level: int) -> int:
	if level >= mountain_level:
		return ROAD_COST_MOUNTAIN
	if level >= hill_level:
		return ROAD_COST_HILL
	return ROAD_COST_PLAIN

## parent 链回溯：start→goal 格序列（不可达 → 空）。
static func _trace_path(parent: Array[int], start: int, goal: int) -> Array[int]:
	if goal < 0 or (parent[goal] < 0 and goal != start):
		return []
	var out: Array[int] = []
	var cur := goal
	while cur >= 0:
		out.append(cur)
		if cur == start:
			break
		cur = parent[cur]
	if out.is_empty() or out[out.size() - 1] != start:
		return []
	out.reverse()
	return out

# ---------------- ③ 落路与桥认领 ----------------

## 一条路径 → RoadData + 沿途未认领河 link → CrossingData；used_links 登记。
## 返回 {"next_road", "next_crossing", "new_links": Array[Vector2i]（本路新占
## link——回路回滚用）}。
static func _place_road(roads: Array[WorldDataClass.RoadData],
		crossings: Array[WorldDataClass.CrossingData], used_links: Dictionary,
		path: Array[int], river_idx: Dictionary, next_road: int,
		next_crossing: int) -> Dictionary:
	var road := WorldDataClass.RoadData.new()
	road.road_id = next_road
	road.cells = path.duplicate()
	road.is_loop = false
	road.road_class = 0
	roads.append(road)
	var new_links: Array[Vector2i] = []
	for k in path.size() - 1:
		var link := WorldDataClass.link_id_of(path[k], path[k + 1])
		used_links[link] = next_road
		new_links.append(link)
		# 横切机器定义（§2.3）：道路跨有河 link 必须被 crossing 认领——在此建桥
		if river_idx.has(link):
			var c := WorldDataClass.CrossingData.new()
			c.crossing_id = next_crossing
			c.kind = WorldDataClass.CrossingData.Kind.BRIDGE
			c.river_edge = link
			c.bank_a = link.x
			c.bank_b = link.y
			crossings.append(c)
			next_crossing += 1
	return {"next_road": next_road + 1, "next_crossing": next_crossing,
		"new_links": new_links}

## 全量重验（§6 WORLD-05 ③：每次加路后可达性/footprint 全量重验——复用
## WORLD-04 校验器）：拼装草稿世界（现有 river/body/poi/state 事实 + 当前
## roads/crossings/link 表）跑 WorldValidator；返回 ""=过、否则首错串。
## require_road_network=false——逐路增量重验；网络连通由骨架拓扑保证、终验在管线
## 可玩校验阶段。
static func _revalidate(map: MapDataClass, world: WorldDataClass,
		roads: Array[WorldDataClass.RoadData],
		crossings: Array[WorldDataClass.CrossingData], cfg: Dictionary) -> String:
	var scratch := WorldDataClass.empty()
	scratch.rivers = world.rivers
	scratch.water_bodies = world.water_bodies
	scratch.pois = world.pois
	scratch.states = world.states
	scratch.cell_owners = world.cell_owners
	scratch.roads = roads
	scratch.crossings = crossings
	scratch.links = _links_with_roads(world, roads)
	var report := WorldValidator.validate_report(map, scratch, {
		"water_terrain_id": int(cfg["water_terrain_id"]),
		"max_road_delta": int(cfg["max_road_delta"]),
		"max_bridge_bank_delta": int(cfg["max_bridge_bank_delta"]),
		"require_road_network": false,
		"locked_cells": cfg.get("locked_cells", []),
	})
	if report["ok"]:
		return ""
	var first: Dictionary = report["errors"][0]
	return first["explanation"]

# ---------------- 失败归因 ----------------

## 具名失败（提案明示出路之一）：聚落对 + 阻挡河段。归因 = 自 A 的 BFS 前沿
## 撞上的**未开放**有河 link 所属 reach 集合；空集 = 非河阻挡（高差/禁入面）。
## 错误串指向具体聚落对（格 + poi id）与河段（reach id 表）——WORLD-05 测试锚
## 「禁桥失败明确」的落点；不删河/不压山伪造达标。
static func _disconnected_fail(map: MapDataClass, settlements: Array,
		pair: Array, open_links: Dictionary, river_idx: Dictionary,
		fail: Dictionary) -> Dictionary:
	var a_cell := SettlementGen.cell_of_id(map, settlements[pair[0]].cell_id)
	var blocked_reaches := {}
	var visited := {}
	var queue: Array[Vector2i] = [a_cell]
	visited[a_cell] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb) or visited.has(nb):
				continue
			if map.elevation_at(nb) == 0 or not map.is_passable(nb):
				continue
			var link := WorldDataClass.link_id_of(map.index_of(cell), map.index_of(nb))
			if river_idx.has(link) and not open_links.has(link):
				blocked_reaches[int(river_idx[link]["reach"])] = true
				continue
			visited[nb] = true
			queue.append(nb)
	var reaches := blocked_reaches.keys()
	reaches.sort()
	if reaches.is_empty():
		fail["error"] = "ROAD_NETWORK_DISCONNECTED：必需聚落对（格 %d ↔ %d，poi %d/%d）无法连接——阻挡为地形（高差/禁入面），无河段涉入" \
			% [settlements[pair[0]].cell_id, settlements[pair[1]].cell_id,
				settlements[pair[0]].poi_id, settlements[pair[1]].poi_id]
	else:
		fail["error"] = "ROAD_NETWORK_DISCONNECTED：必需聚落对（格 %d ↔ %d，poi %d/%d）无法连接——阻挡河段 reach %s 无合法桥址（桥头Δ/净空/桥端禁入全排除；不删河不压山伪造达标）" \
			% [settlements[pair[0]].cell_id, settlements[pair[1]].cell_id,
				settlements[pair[0]].poi_id, settlements[pair[1]].poi_id, str(reaches)]
	return fail

# ---------------- link 表组装 ----------------

## river link 表**复制** + 本批道路逐 link 补 road_id（桥认领边 = river_reach_id
## 原样保留 + road_id 叠加——「河在下、路在上」）；条目全部新建（不共享既有
## 对象——回路回滚后重建不残留脏 road_id）；升序规范序。
static func _links_with_roads(world: WorldDataClass,
		roads: Array[WorldDataClass.RoadData]) -> Array[WorldDataClass.NeighborLinkData]:
	var road_of_link := {}
	for r in roads:
		for k in r.cells.size() - 1:
			road_of_link[WorldDataClass.link_id_of(r.cells[k], r.cells[k + 1])] = r.road_id
	var existing := {}
	for lk in world.links:
		existing[lk.link_id] = true
	var out: Array[WorldDataClass.NeighborLinkData] = []
	for lk in world.links:
		var nlk := WorldDataClass.NeighborLinkData.new()
		nlk.link_id = lk.link_id
		nlk.river_reach_id = lk.river_reach_id
		nlk.road_id = int(road_of_link.get(lk.link_id, WorldDataClass.ID_NONE))
		out.append(nlk)
	for link in road_of_link:
		# 既有条目（river 面 / 手工世界 road 面）只叠加 road_id，不重复建条目
		if not existing.has(link):
			var nlk := WorldDataClass.NeighborLinkData.new()
			nlk.link_id = link
			nlk.road_id = int(road_of_link[link])
			out.append(nlk)
	out.sort_custom(_link_order)
	return out

static func _copy_links(world: WorldDataClass) -> Array[WorldDataClass.NeighborLinkData]:
	var out: Array[WorldDataClass.NeighborLinkData] = []
	for lk in world.links:
		var nlk := WorldDataClass.NeighborLinkData.new()
		nlk.link_id = lk.link_id
		nlk.river_reach_id = lk.river_reach_id
		nlk.road_id = lk.road_id
		out.append(nlk)
	return out

## 逐对禁入面：base（锁定/资源/全部出生区）摘出 A、B 两区（服务聚落的路可穿
## 自家区——validator 同款豁免口径）。
static func _forbidden_for(base: Dictionary, zone_of_anchor: Dictionary,
		settlements: Array, a: int, b: int) -> Dictionary:
	var out := base.duplicate()
	for idx in [a, b]:
		var anchor: int = settlements[idx].cell_id
		if zone_of_anchor.has(anchor):
			var zone: WorldDataClass.POIData = zone_of_anchor[anchor]
			for cid in zone.footprint_cells:
				out.erase(cid)
	return out

static func _find_comp(comp: Dictionary, i: int) -> int:
	var root := i
	while comp[root] != root:
		root = comp[root]
	var cur := i
	while comp[cur] != root:
		var nxt: int = comp[cur]
		comp[cur] = root
		cur = nxt
	return root

## MST 边排序：成本升序、并列取聚落对字典序（确定性钉死）。
static func _pair_edge_order(a: Dictionary, b: Dictionary) -> bool:
	if a["cost"] != b["cost"]:
		return a["cost"] < b["cost"]
	var pa: Array = a["pair"]
	var pb: Array = b["pair"]
	if pa[0] != pb[0]:
		return pa[0] < pb[0]
	return pa[1] < pb[1]

static func _link_order(a: WorldDataClass.NeighborLinkData,
		b: WorldDataClass.NeighborLinkData) -> bool:
	return a.link_id.x < b.link_id.x \
		or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y)
