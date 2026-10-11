## river_network_generator.gd — 河口反向生长河网生成器（T5 WORLD-02；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-02 + 主创拍板第二批④
##   「河网生成路线 = 河口反向生长（Red Blob x/1723 思路格边化）」+ 修订记录三之
##   4/5——角点级无环候选、简单链不汇合、水位随生长构造单调）
## 职责：在**已量化**的 MapData 上生成河网与水体的世界事实侧产出（直接落
##   RiverReachData.edges 边序列——终态事实；生长过程与偏好参数 = 生成中间产物
##   不落盘，§6 WORLD-02 数据合同影响行）。算法三件：
##   ① 水体声明：水格（terrain = water_terrain_id）六邻连通分量 → WaterBodyData
##      ——贴图界分量 = SEA、内陆分量 = LAKE（WORLD-02 ③「量化后洼地格集 →
##      声明 WaterBodyData」的默认出路）；成员水位不齐 = 具名失败（WATER_BODY_
##      LEVEL——量化口径破坏，不静默重塑整图高程，方案 ① 停止处置纪律）；
##   ② 河口选择：各水体岸边（成员↔非成员共享边）为河口水域候选，岸侧格作
##      间距锚——**河口间最小六边形环距**约束（方案 ②，Azgaar burgs 间距同族）
##      + 候选边/角点全局预留查重；随机消耗 = 本生成器唯一随机源（具名通道
##      hydrology，WorldPipeline 传入——通道独立性的锚面）；
##   ③ 反向生长：从河口边在**边图**上逐边上溯——当前上游端角点处的延续边为
##      候选，**已用边 + 已访问角点永不再入候选**（无环须角点级——边不复用 ≠
##      不复用角点，修订记录三之 4；角点预留跨链全局 → 河间不汇合/不交叉）；
##      首版 = 彼此不汇合的简单链（无分叉，汇流随拍板⑨第二版开）；候选偏好
##      低高程（量化高程直接驱动）**且须同时验证**出口（角点延续存在）/河床
##      深度（bed < 水位）/水位（上溯不减）/两岸容纳（双岸陆地且 min(岸高)−1
##      ≥ 当前水位）；无合法候选 / 长度预算尽 / 抵图界 = 源（三种停止具名入
##      stats，不静默重塑整图高程）；水位随生长构造单调：河口边 = 水体
##      water_level，每上溯一边取 min(两岸高)−1 且 ≥ 前值（禁上坡由构造保证，
##      WATER-01 校验器仍断言——双保险）；量化后二次验证由调用侧（WorldPipeline
##      水系阶段）执行。
## 只读合同：本生成器不写 MapData 任何字段（生成前后 summary 逐字节一致——
##   测试锚）；产出经调用侧组装进 WorldData 并跑全量 validate（草案 §11）。
## 纯函数：RefCounted、零场景节点（ADR-2）；确定性 = 同 map 同 cfg 同 rng 序列
##   → 同产出（偏好函数并列取 link_id 字典序小者钉死）。
class_name RiverNetworkGenerator
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")

## 停止原因枚举（诊断具名——「无候选时停止/缩短/换候选或具名失败」的可观测面）
const STOP_NO_CANDIDATE := "no_candidate"
const STOP_BUDGET := "budget"
const STOP_MAP_EDGE := "map_edge"

## 生成配置键集（WorldTemplate hydrology 组投影 + 调用侧补充 water_terrain_id）
const CFG_KEYS := ["river_count", "river_max_edges", "min_mouth_spacing",
	"river_flow_level", "water_terrain_id"]

## 生成入口。map = 已量化图（水格 terrain=water_terrain_id、成员高程均匀）；
## rng = 具名 hydrology 通道（唯一随机源：河口水序挑选）；cfg = CFG_KEYS 键集。
## 返回 {"ok": bool, "error": String,
##   "rivers": Array（RiverReachData，reach_id = 河口接纳序 0..，升序规范序）,
##   "water_bodies": Array（WaterBodyData，含无河水体——声明即合法）,
##   "links": Array（NeighborLinkData，link_id 升序，river_reach_id 面）,
##   "stats": {"bodies"/"sea"/"lake"/"reaches"/"total_edges": int,
##     "mouths": Array[Vector2i]（河口径，接纳序）,
##     "stop_reasons": {STOP_*: int}}}。
## 失败只出自水体声明（成员水位不齐）与 cfg 缺键——生长永不失败（停止即缩短）。
static func generate(map: MapDataClass, rng: RandomNumberGenerator, cfg: Dictionary) -> Dictionary:
	var fail := {"ok": false, "error": "", "rivers": [], "water_bodies": [],
		"links": [], "stats": {}}
	if not cfg.has_all(CFG_KEYS):
		fail["error"] = "河网生成配置缺键：%s（got %s）" % [str(CFG_KEYS), str(cfg.keys())]
		return fail

	var bodies_result := _declare_water_bodies(map, int(cfg["water_terrain_id"]))
	if not bodies_result["ok"]:
		fail["error"] = str(bodies_result["error"])
		return fail
	var bodies: Array = bodies_result["bodies"]

	var used_edges := {}    # link_id → true（跨链全局——候选边去重）
	var used_corners := {}  # 角点稳定 ID → true（跨链全局——河间不汇合/不交叉）
	var mouths := _select_mouths(map, bodies, int(cfg["river_count"]),
		int(cfg["min_mouth_spacing"]), int(cfg["water_terrain_id"]),
		used_edges, used_corners, rng)

	var rivers: Array = []
	var links_out: Array = []
	var stop_reasons := {STOP_NO_CANDIDATE: 0, STOP_BUDGET: 0, STOP_MAP_EDGE: 0}
	var total_edges := 0
	for mi in mouths.size():
		var mouth: Vector2i = mouths[mi]
		var body: WorldDataClass.WaterBodyData = _body_of_link(bodies, mouth)
		var grown := _grow_reach(map, body, mouth, int(cfg["river_max_edges"]),
			int(cfg["river_flow_level"]), int(cfg["water_terrain_id"]),
			used_edges, used_corners)
		var reach: WorldDataClass.RiverReachData = grown["reach"]
		reach.reach_id = mi
		rivers.append(reach)
		body.inlet_links.append(mouth)
		total_edges += reach.edges.size()
		var stop := String(grown["stop_reason"])
		stop_reasons[stop] = int(stop_reasons[stop]) + 1
		for e in reach.edges:
			var lk := WorldDataClass.NeighborLinkData.new()
			lk.link_id = e
			lk.river_reach_id = mi
			links_out.append(lk)
	for b in bodies:
		(b as WorldDataClass.WaterBodyData).inlet_links.sort()

	var sea := 0
	for b in bodies:
		if (b as WorldDataClass.WaterBodyData).kind == WorldDataClass.WaterBodyData.Kind.SEA:
			sea += 1
	links_out.sort_custom(_link_order)
	return {
		"ok": true,
		"error": "",
		"rivers": rivers,
		"water_bodies": bodies,
		"links": links_out,
		"stats": {
			"bodies": bodies.size(),
			"sea": sea,
			"lake": bodies.size() - sea,
			"reaches": rivers.size(),
			"total_edges": total_edges,
			"mouths": mouths,
			"stop_reasons": stop_reasons,
		},
	}


# ---------------- ① 水体声明 ----------------

## 水格连通分量 → WaterBodyData（发现序 = 行主序首格序，water_body_id 依此递增
## ——确定性钉死）；贴图界 → SEA、内陆 → LAKE；成员高程须全齐（量化产物恒 0——
## 不齐 = 具名失败，绝不静默改图）。
static func _declare_water_bodies(map: MapDataClass, water_terrain_id: int) -> Dictionary:
	var visited := {}
	var bodies: Array = []
	var next_id := 0
	for cell in map.cells():
		if visited.has(cell) or map.terrain_at(cell) != water_terrain_id:
			continue
		# BFS 六邻连通分量（neighbors_existing 方向 0..5 固定序——确定性）
		var members: Array[int] = []
		var queue: Array[Vector2i] = [cell]
		visited[cell] = true
		var touches_border := false
		while not queue.is_empty():
			var c: Vector2i = queue.pop_front()
			members.append(map.index_of(c))
			var cr := Hex.offset_of(c)
			if cr.x == 0 or cr.y == 0 or cr.x == map.width - 1 or cr.y == map.height - 1:
				touches_border = true
			for nb in map.neighbors_existing(c):
				if not visited.has(nb) and map.terrain_at(nb) == water_terrain_id:
					visited[nb] = true
					queue.append(nb)
		members.sort()
		var level := map.elevation_at(_cell_of_id(map, members[0]))
		for cid in members:
			var e := map.elevation_at(_cell_of_id(map, cid))
			if e != level:
				return {"ok": false, "bodies": [],
					"error": "WATER_BODY_LEVEL：水体 %d 成员格 %d 高程 %d ≠ %d（成员水位须全齐——"
						% [next_id, cid, e, level]
						+ "量化口径破坏，具名失败；不静默重塑高程）"}
		var b := WorldDataClass.WaterBodyData.new()
		b.water_body_id = next_id
		b.kind = WorldDataClass.WaterBodyData.Kind.SEA if touches_border \
			else WorldDataClass.WaterBodyData.Kind.LAKE
		b.water_level = level
		b.member_cells = members
		b.terminal = true  # 海恒 true；湖首版同为终点湖（outlet 属 WATER-03 后续面）
		bodies.append(b)
		next_id += 1
	return {"ok": true, "error": "", "bodies": bodies}


# ---------------- ② 河口选择（唯一随机消耗点）----------------

## 全图河口挑选：岸边（成员↔陆）且岸侧格可站（通行 + 非水 + 高于本体水位）+
## 河口边两角点未被预留（跨链角点查重——河间不交叉的河口侧保证）+ 距已接纳
## 河口锚（岸侧格）环距 ≥ min_spacing；满足者按 rng 挑序至 river_count 个。
## 候选池逐接纳收缩（间距/角点过滤对已接纳集合动态判定），确定性 = rng 通道序。
static func _select_mouths(map: MapDataClass, bodies: Array, river_count: int,
		min_spacing: int, water_terrain_id: int, used_edges: Dictionary,
		used_corners: Dictionary, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var mouths: Array[Vector2i] = []
	if river_count <= 0:
		return mouths
	# 全体候选（水体发现序 × 岸边升序——确定性底序）；锚 = 岸侧陆格
	var pool: Array = []
	for b in bodies:
		var body: WorldDataClass.WaterBodyData = b
		for lk in WorldDataClass.shore_links_of(map, body):
			var land_id := _land_flank_of(body, lk)
			if land_id < 0:
				continue
			var land_cell := _cell_of_id(map, land_id)
			if not map.is_passable(land_cell) \
					or map.terrain_at(land_cell) == water_terrain_id \
					or map.elevation_at(land_cell) <= body.water_level:
				continue
			pool.append({"link": lk, "body": body, "anchor": land_cell})
	var anchors: Array[Vector2i] = []  # 已接纳河口的岸侧格（间距锚）
	while mouths.size() < river_count and not pool.is_empty():
		# 间距 + 角点预留过滤（对当前已接纳集合动态判定）
		var feasible: Array[int] = []
		for i in pool.size():
			var cand: Dictionary = pool[i]
			var spaced := true
			for a in anchors:
				if Hex.distance(cand["anchor"], a) < min_spacing:
					spaced = false
					break
			if spaced and not _corner_reserved(map, cand["link"], used_corners):
				feasible.append(i)
		if feasible.is_empty():
			break
		var pick: int = feasible[rng.randi_range(0, feasible.size() - 1)]
		var chosen: Dictionary = pool[pick]
		var mouth: Vector2i = chosen["link"]
		anchors.append(chosen["anchor"])
		# 接纳即预留：河口边入已用边、两角点入已访问集（链自身的链首角点，
		# 同时挡住他链借道——跨链不汇合的完整保证）
		used_edges[mouth] = true
		for rep in _link_corner_reps(map, mouth):
			used_corners[WorldDataClass.corner_id_of(map, rep[0], rep[1])] = true
		mouths.append(mouth)
		pool.remove_at(pick)
	return mouths


# ---------------- ③ 河口反向生长（简单链）----------------

## 单链生长：从河口边向上游逐边延伸。返回 {"reach": RiverReachData,
##   "stop_reason": String}（stop_reason 属生成期中间产物——调用侧读入 stats，
##   不留驻数据对象）。
## 链方向：growth 序 = 河口→上游；RiverReachData.edges = 其**反序**（源在前、
## 终点边=河口水口在后，WATER-01 合同序），water_levels 同步反序 → 沿序列单调
## 不升（禁上坡由构造保证）。
static func _grow_reach(map: MapDataClass, body: WorldDataClass.WaterBodyData,
		mouth: Vector2i, max_edges: int, flow_level: int, water_terrain_id: int,
		used_edges: Dictionary, used_corners: Dictionary) -> Dictionary:
	var reach := WorldDataClass.RiverReachData.new()
	var growth_edges: Array[Vector2i] = [mouth]
	var growth_levels: Array[int] = [body.water_level]
	# 链首两端角点（(a, d)/(a, d+1) = 河口边两角点）：起步上游端未定——先试
	# 一侧角点池、空则试另一侧（哪侧有候选哪侧即上游端；两侧都过偏好打分，
	# 取舍仍在单链内——无分叉）
	var head := _cell_of_id(map, mouth.x)
	var d := Hex.dir_between(head, _cell_of_id(map, mouth.y))
	var head_v := d
	var stop := ""
	while true:
		if growth_edges.size() >= max_edges:
			stop = STOP_BUDGET
			break
		var cand: Variant = _best_candidate(map, head, head_v,
			growth_edges[growth_edges.size() - 1], growth_levels[growth_levels.size() - 1],
			body, water_terrain_id, used_edges, used_corners)
		if cand == null and growth_edges.size() == 1:
			# 起步时上游端未定：另一侧角点再试一次（两池皆空才停——起步端
			# 选择不构成分叉，只是把「哪端是上游」交给偏好函数）
			head_v = d + 1
			cand = _best_candidate(map, head, head_v, mouth, growth_levels[0],
				body, water_terrain_id, used_edges, used_corners)
		if cand == null:
			if growth_edges.size() == 1:
				# 起步双侧归类：两侧角点都无界内延续 → 抵图界；任一侧有界内
				# 延续（但全被验证拒绝）→ 无合法候选
				var s1 := _stop_reason_at(map, head, d, growth_edges[0])
				var s2 := _stop_reason_at(map, head, d + 1, growth_edges[0])
				stop = STOP_MAP_EDGE if s1 == STOP_MAP_EDGE and s2 == STOP_MAP_EDGE \
					else STOP_NO_CANDIDATE
			else:
				stop = _stop_reason_at(map, head, head_v,
					growth_edges[growth_edges.size() - 1])
				stop = STOP_NO_CANDIDATE if stop == "" else stop
			break
		growth_edges.append(cand["link"])
		growth_levels.append(cand["level"])
		used_edges[cand["link"]] = true
		used_corners[cand["far_corner_id"]] = true
		head = cand["far_cell"]
		head_v = int(cand["far_v"])
	reach.edges = growth_edges.duplicate()
	reach.edges.reverse()
	reach.water_levels = growth_levels.duplicate()
	reach.water_levels.reverse()
	reach.bed_level = body.water_level - 1  # 恒 < 逐段水位（水位 ≥ 河口 = 本体水位）
	reach.flow_level = flow_level
	reach.water_body_id = body.water_body_id
	return {"reach": reach, "stop_reason": stop}


## 角点延续候选中的最优者：偏好 = 双岸最低高程小者优先（量化高程直接驱动，
## 方案 ①），并列取 link_id 字典序小者（确定性钉死）。
## 候选验证四件（须**同时**满足，方案 ①：出口/河床深度/水位/两岸容纳）：
##   出口 = 与当前上游端角点共角点的界内延续边；已用边/已访问角点永不再入候选；
##   两岸容纳 = 双岸陆地（通行且非水）且 min(岸高)−1 ≥ 当前水位（水面不淹岸、
##   且新水位不降——上溯单调）；水位/河床：新水位 ≥ 当前 ≥ 本体水位 > bed
##   （结构恒真，显式校验保具名失败纪律——失败即生成器 bug，宁缺勿滥）。
## 返回 null = 该角点无合法候选。
static func _best_candidate(map: MapDataClass, head: Vector2i, head_v: int,
		cur_edge: Vector2i, cur_level: int, body: WorldDataClass.WaterBodyData,
		water_terrain_id: int, used_edges: Dictionary, used_corners: Dictionary) -> Variant:
	var best: Variant = null
	for pair in _corner_cell_pairs(map, head, head_v):
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var link := WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
		if link == cur_edge or used_edges.has(link):
			continue
		# 两岸容纳（陆地侧）：双岸通行且非水（河是边语义水体——两侧格保持陆地；
		# 水判定按声明口径 terrain == water_terrain_id——**任何**水体的水格都算，
		# 不只本链汇入的水体：贴着他湖岸边走 = 岸不成立）
		if not map.is_passable(a) or not map.is_passable(b):
			continue
		if map.terrain_at(a) == water_terrain_id or map.terrain_at(b) == water_terrain_id:
			continue
		var mb := mini(map.elevation_at(a), map.elevation_at(b))
		var new_level := mb - 1
		if new_level < cur_level:
			continue  # 上溯水位不减（禁上坡）——低岸容不下当前水位的候选拒绝
		if body.water_level - 1 >= new_level:
			continue  # 河床深度：bed(< 本体水位) 须 < 新水位（结构恒真的显式断言）
		# 无环（角点级）：候选边的「新端角点」不得已访问（本链 + 他链全局）
		var far: Variant = _far_corner(map, link, head, head_v)
		if far == null or used_corners.has(far["id"]):
			continue
		var score := mb
		if best == null or score < int(best["score"]) \
				or (score == int(best["score"]) and link < (best["link"] as Vector2i)):
			best = {
				"link": link,
				"level": new_level,
				"score": score,
				"far_cell": far["cell"],
				"far_v": far["v"],
				"far_corner_id": far["id"],
			}
	return best


## 角点 (cell, v) 周界三格的两两配对（三格 = cell、N_v(cell)、N_{v−1}(cell)——
## WorldData.corner_id_of 三表示同族）；界内对 = 候选边（出界对自然缺席——
## 角点局部枚举即「出口」检查，不遍历全图边表）。
static func _corner_cell_pairs(map: MapDataClass, cell: Vector2i, v: int) -> Array:
	var cells3 := [
		cell,
		Hex.neighbor(cell, v),
		Hex.neighbor(cell, v - 1),
	]
	var out: Array = []
	for i in 3:
		for j in range(i + 1, 3):
			var a: Vector2i = cells3[i]
			var b: Vector2i = cells3[j]
			if map.has_cell(a) and map.has_cell(b):
				out.append([a, b])
	return out


## 停止原因归类：给定角点处若连**界内**延续边都不存在（当前边之外）= 抵图界
## （返回 STOP_MAP_EDGE——上游端顶在图边界上）；返回 "" = 界内延续存在但全被
## 候选验证拒绝（调用方归类 STOP_NO_CANDIDATE——界内有无是两类停止的分界）。
static func _stop_reason_at(map: MapDataClass, head: Vector2i, head_v: int,
		cur_edge: Vector2i) -> String:
	var in_bounds_count := 0
	for pair in _corner_cell_pairs(map, head, head_v):
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var link := WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
		if link == cur_edge:
			continue
		in_bounds_count += 1
	return STOP_MAP_EDGE if in_bounds_count == 0 else ""


## link 的两角点表示（[(cell, v), (cell, v+1)]，v = dir_between(端格)）。
static func _link_corner_reps(map: MapDataClass, link: Vector2i) -> Array:
	var a := _cell_of_id(map, link.x)
	var d := Hex.dir_between(a, _cell_of_id(map, link.y))
	return [[a, d], [a, d + 1]]


## link 相对给定角点的「远端角点」：两角点表示中规范 ID ≠ 给定角点者。
## 返回 {"cell", "v", "id"}；给定点不在该边两角点上（调用 bug）→ null。
static func _far_corner(map: MapDataClass, link: Vector2i, head: Vector2i, head_v: int) -> Variant:
	var head_id := WorldDataClass.corner_id_of(map, head, head_v)
	for rep in _link_corner_reps(map, link):
		var cell: Vector2i = rep[0]
		var v: int = rep[1]
		var cid := WorldDataClass.corner_id_of(map, cell, v)
		if cid != head_id:
			return {"cell": cell, "v": v, "id": cid}
	return null


## link 两角点是否已被预留（河口接纳查重用）。
static func _corner_reserved(map: MapDataClass, link: Vector2i, used_corners: Dictionary) -> bool:
	for rep in _link_corner_reps(map, link):
		if used_corners.has(WorldDataClass.corner_id_of(map, rep[0], rep[1])):
			return true
	return false


# ---------------- 小查询 ----------------

## cell 稳定 ID → axial 格（WorldData._cell_of_id 同式；RiverFixtures.cell_of_id
## 公开先例——生成器侧自持一份只读版，避免 preload 工具件）。
static func _cell_of_id(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))


## 岸边的陆侧端（恰一端为成员格；两端皆成员/皆非成员 → -1——岸边口径由
## shore_links_of 保证，此处防御性复核）。
static func _land_flank_of(body: WorldDataClass.WaterBodyData, link: Vector2i) -> int:
	var in_a := body.member_cells.has(link.x)
	var in_b := body.member_cells.has(link.y)
	if in_a == in_b:
		return -1
	return link.y if in_a else link.x


## link（河口水口）所属水体（成员侧格 ∈ 哪个 body；无匹配 → null = 调用 bug）。
static func _body_of_link(bodies: Array, link: Vector2i) -> WorldDataClass.WaterBodyData:
	for b in bodies:
		var body: WorldDataClass.WaterBodyData = b
		if body.member_cells.has(link.x) or body.member_cells.has(link.y):
			return body
	return null


static func _link_order(a: WorldDataClass.NeighborLinkData,
		b: WorldDataClass.NeighborLinkData) -> bool:
	return a.link_id.x < b.link_id.x \
		or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y)
