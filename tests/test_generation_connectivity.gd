## test_generation_connectivity.gd — T4 ROAD-03 生成期连通查询单测（执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §5 ROAD-03 重定义版 + §2.2 双口径 +
##   §2.3 横切机器定义；拍板⑤ 认领语义）
## 覆盖锚（卡表「测试锚」逐条）：
##   - 无桥过阻挡河边 = 失败（错误指向具体河段——blocked_river 含 link/reach）；
##   - 有合法桥 = 通过；
##   - 与 MapData.passable 口径对账：湖格仍当墙（格语义水体在格上、河在边上
##     ——双口径各自闭合）；边级通行图不改变无河世界的格连通（回退口径锚）；
##   - 全套手工 fixture 驱动（手工端点/手工聚落小图，零 T5 依赖）。
## oracle 原则：期望阻挡边/可达集由测试侧独立 BFS（只读 MapData.passable +
##   RiverFixtures 几何判链）或手算小图给出，不复制查询的边判定实现。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const GenConn := preload("res://scripts/content/map_generation_connectivity.gd")
const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")
const RiverFix := preload("res://tools/river_fixtures.gd")

const MAP_W := 12
const MAP_H := 8
const T_WATER := 3

# ================= 手工 fixture（河 + 河口湖，沿 test_bridges 先例）=================

## 端点/桥边索引：河链早段第 2 条边（非源边；远离终点侧河口湖涂格——湖成员
## 不可通行/高程 0，端点或桥在其上会错归因）。链短则钳到倒数第二条。
func _safe_index(chain: Array[Vector2i]) -> int:
	return clampi(2, 1, chain.size() - 2)

## 标准样本：12×8 全草，贪心南向河（约 col 5-6 分东西），河口湖涂在终点侧。
## 返回 {"map","world","chain"}。
func _river_world() -> Dictionary:
	var map := MapDataClass.new(MAP_W, MAP_H)
	for cell in map.cells():
		map.set_elevation(cell, 1)  # 陆地基高程 1（默认 0 会让桥撞净空检查）
	var links := RiverFix.all_links(map)
	# 源边取**行 0**（北图界）：河须从图界长到图界——行 1 起步会留北端绕行通道
	var start := WorldDataClass.link_id_of(
		map.index_of(Hex.axial_of(Vector2i(5, 0))), map.index_of(Hex.axial_of(Vector2i(6, 0))))
	# 步数给足（40 > 图高两倍边数）：贪心南向走直到图界候选耗尽——河须贯穿
	# 南北，否则西东连通会绕过河尾（12×8 图对角 ~20 边）
	var chain := RiverFix.greedy_chain(map, links, start, 40,
		func(_row: int) -> float: return 5.5)
	var w := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.water_levels = []
	for i in chain.size():
		reach.water_levels.append(1)
	reach.bed_level = 0
	reach.water_body_id = 0
	w.rivers.append(reach)
	var term: Vector2i = chain[chain.size() - 1]
	var members: Array[int] = [term.x]
	var mcell := RiverFix.cell_of_id(map, term.x)
	for d in 6:
		var nb := Hex.neighbor(mcell, d)
		if map.has_cell(nb) and map.index_of(nb) != term.y and not members.has(map.index_of(nb)):
			members.append(map.index_of(nb))
	for cid in members:
		var c := RiverFix.cell_of_id(map, cid)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
	members.sort()
	var body := WorldDataClass.WaterBodyData.new()
	body.water_body_id = 0
	body.water_level = 1
	body.member_cells = members
	body.inlet_links = [term]
	body.terminal = true
	w.water_bodies.append(body)
	for e in chain:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = e
		lk.river_reach_id = 0
		w.links.append(lk)
	w.links.sort_custom(func(a: WorldDataClass.NeighborLinkData,
			b: WorldDataClass.NeighborLinkData) -> bool:
		return a.link_id.x < b.link_id.x or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y))
	return {"map": map, "world": w, "chain": chain}


## 在河边 k 加桥 + 跨接路（两岸都有路；合法横切）。
func _add_bridge(fix: Dictionary, k: int) -> Vector2i:
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	var chain: Array[Vector2i] = fix["chain"]
	var link: Vector2i = chain[k]
	var road := WorldDataClass.RoadData.new()
	road.road_id = 0
	road.cells = [link.x, link.y]
	w.roads.append(road)
	var crossing := WorldDataClass.CrossingData.new()
	crossing.crossing_id = 0
	crossing.river_edge = link
	crossing.bank_a = link.x
	crossing.bank_b = link.y
	w.crossings.append(crossing)
	for lk in w.links:
		if lk.link_id == link:
			lk.road_id = 0
	return link

# ================= 边级通行图原子 =================

func test_edge_open_units() -> void:
	var map := MapDataClass.new(4, 3)
	var a := Hex.axial_of(Vector2i(1, 1))
	var b := Hex.neighbor(a, 0)
	var w := WorldDataClass.empty()
	# ① 双通行 + 无河 → ok
	var ok_case := GenConn.edge_open(map, w, a, b)
	expect(bool(ok_case["ok"]), "通行格 × 无河 → 边可通行")
	# ② 湖格当墙：b 不可通行 → 拒（原因指向格）
	map.set_passable(b, false)
	var lake := GenConn.edge_open(map, w, a, b)
	expect(not bool(lake["ok"]), "不可通行格 → 边不通（湖格仍当墙——格语义水体在格上）")
	expect(String(lake["reason"]).contains("不可通行"), "原因指向格")
	# ③ 有河未认领 → 禁渡（原因指向河段）
	map.set_passable(b, true)
	var wr := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 3
	reach.edges = [WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))]
	reach.water_levels = [1]
	reach.bed_level = 0
	reach.water_body_id = 0
	wr.rivers.append(reach)
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = reach.edges[0]
	lk.river_reach_id = 3
	wr.links.append(lk)
	var forded := GenConn.edge_open(map, wr, a, b)
	expect(not bool(forded["ok"]), "有河无桥 → 禁渡")
	expect(int(forded["reach"]) == 3, "禁渡原因指向具体河段（reach 3）")
	# ④ 认领 → 可渡（traversable = 认领表）
	var road := WorldDataClass.RoadData.new()
	road.road_id = 0
	road.cells = [map.index_of(a), map.index_of(b)]
	wr.roads.append(road)
	lk.road_id = 0
	var crossing := WorldDataClass.CrossingData.new()
	crossing.crossing_id = 0
	crossing.river_edge = reach.edges[0]
	crossing.bank_a = reach.edges[0].x
	crossing.bank_b = reach.edges[0].y
	wr.crossings.append(crossing)
	var bridged := GenConn.edge_open(map, wr, a, b)
	expect(bool(bridged["ok"]), "有河有桥（crossing 认领）→ 可渡")

# ================= 无桥失败指向河段 / 有桥通过（手工端点）=================

func test_no_bridge_blocked_points_at_river_reach() -> void:
	var fix := _river_world()
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	var chain: Array[Vector2i] = fix["chain"]
	# 手工端点：河两侧同行的西/东格（贪心走廊 → 中段任一河边两侧即手工端点对）
	var mid_link: Vector2i = chain[_safe_index(chain)]
	var west := RiverFix.cell_of_id(map, mini(mid_link.x, mid_link.y))
	var east := RiverFix.cell_of_id(map, maxi(mid_link.x, mid_link.y))
	expect(map.is_passable(west) and map.is_passable(east), "构造前提：两端点均通行（河在边上不占格）")
	var result := GenConn.required_connected(map, w, west, east)
	expect(not bool(result["ok"]), "无桥过阻挡河边 = 失败")
	var blocked: Array = result["blocked_river"]
	expect(not blocked.is_empty(), "失败报告非空（败因不是格）")
	# 错误指向具体河段：blocked 含河段 id 与具体 link；端点对所在的边必在其中
	var hit_endpoint_edge := false
	for entry in blocked:
		expect(int(entry["reach"]) == 0, "阻挡条目指向 reach 0（具体河段）")
		if entry["link"] == mid_link:
			hit_endpoint_edge = true
	expect(hit_endpoint_edge, "端点对所在河边 %s 在阻挡清单（错误指向河段）" % str(mid_link))
	# 手工聚落小图口径：两岸各取同侧小片（**按可达集过滤**——河弯处的邻格可能
	# 已在对岸，不过滤会假绿），无桥时任一对必需连接都失败
	var west_reach: Dictionary = GenConn.reachable_set(map, w, west)["cells"]
	var east_reach: Dictionary = GenConn.reachable_set(map, w, east)["cells"]
	var west_hamlet: Array[Vector2i] = [west]
	var east_hamlet: Array[Vector2i] = [east]
	for d in [4, 5]:
		var nb := Hex.neighbor(west, d)
		if map.has_cell(nb) and west_reach.has(nb):
			west_hamlet.append(nb)
	for d in [0, 1]:
		var nb2 := Hex.neighbor(east, d)
		if map.has_cell(nb2) and east_reach.has(nb2):
			east_hamlet.append(nb2)
	expect(west_hamlet.size() >= 2 and east_hamlet.size() >= 2,
		"构造前提：两岸聚落各 ≥2 格（同侧过滤后，got %d/%d）" % [west_hamlet.size(), east_hamlet.size()])
	var any_connected := false
	for wc in west_hamlet:
		for ec in east_hamlet:
			if bool(GenConn.required_connected(map, w, wc, ec)["ok"]):
				any_connected = true
	expect(not any_connected, "手工聚落（西 %d 格 × 东 %d 格）无桥全部不可达" % [west_hamlet.size(), east_hamlet.size()])

func test_with_legal_bridge_connected() -> void:
	var fix := _river_world()
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	var chain: Array[Vector2i] = fix["chain"]
	var mid_link := _add_bridge(fix, _safe_index(chain))
	expect_eq(w.validate(map, T_WATER), "", "加桥后世界过全量校验（合法横切）")
	var west := RiverFix.cell_of_id(map, mini(mid_link.x, mid_link.y))
	var east := RiverFix.cell_of_id(map, maxi(mid_link.x, mid_link.y))
	var result := GenConn.required_connected(map, w, west, east)
	expect(bool(result["ok"]), "有合法桥 = 通过（认领边可渡）")
	# 逆向同过（无向边）
	expect(bool(GenConn.required_connected(map, w, east, west)["ok"]), "东西双向均连通")

func test_river_banks_passable_but_not_crossable_lake_is_wall() -> void:
	# §2.2 双口径对账：河 = 边语义（两侧格保持 passable——单侧可达、跨边不通）；
	# 湖 = 格语义（成员格 passable=false——天然墙，无关查询口径）
	var fix := _river_world()
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	var chain: Array[Vector2i] = fix["chain"]
	var mid_link: Vector2i = chain[_safe_index(chain)]
	var west := RiverFix.cell_of_id(map, mini(mid_link.x, mid_link.y))
	var east := RiverFix.cell_of_id(map, maxi(mid_link.x, mid_link.y))
	# ① 河畔格本身可达（河不占格——从西端出发可达 west，west 的西邻也可达）
	var reach := GenConn.reachable_set(map, w, west)
	expect((reach["cells"] as Dictionary).has(west), "河畔格自身可达（边语义水体不占格）")
	expect(not (reach["cells"] as Dictionary).has(east), "对岸不可达（无桥禁渡）")
	# ② 湖格仍当墙：河口湖成员（passable=false）不进任何可达集
	var members: Array[int] = w.water_bodies[0].member_cells
	for cid in members:
		var cell := RiverFix.cell_of_id(map, cid)
		expect(not map.is_passable(cell), "湖成员格不可通行（格语义结算面）cid=%d" % cid)
		expect(not (reach["cells"] as Dictionary).has(cell), "湖成员格不可达（湖格当墙）cid=%d" % cid)

func test_riverless_world_equivalent_to_map_connectivity() -> void:
	# 回退口径锚：无河世界边级通行图 = 格 passable 连通（划分逐格一致）；
	# 断路小图（col2 全水）与全通图两样本
	var split := MapDataClass.new(5, 5)
	for cell in split.cells():
		if Hex.offset_of(cell).x == 2:
			split.set_terrain(cell, 3)
			split.set_passable(cell, false)
	expect(GenConn.matches_cell_connectivity(split, null), "断路小图：查询划分 = MapConnectivity 分量")
	var plain := MapDataClass.new(6, 4)
	expect(GenConn.matches_cell_connectivity(plain, WorldDataClass.empty()),
		"全通图 + empty() 世界：查询划分 = MapConnectivity 分量")
	# 有河世界对账口径显式不适用（河在边上——两口径定义域不同）
	var fix := _river_world()
	expect(not GenConn.matches_cell_connectivity(fix["map"], fix["world"]),
		"有河世界不适用回退对账（定义域 = 无河世界）")

func test_query_is_read_only_and_deterministic() -> void:
	var fix := _river_world()
	var map: MapDataClass = fix["map"]
	var w: WorldDataClass = fix["world"]
	var before := map.summary()
	var west := RiverFix.cell_of_id(map, (fix["chain"] as Array[Vector2i])[0].x)
	var r1 := GenConn.reachable_set(map, w, west)
	var r2 := GenConn.reachable_set(map, w, west)
	expect_eq(str(r1["cells"]), str(r2["cells"]), "同图两次查询可达集一致（确定性/回归锚）")
	expect_eq(map.summary(), before, "查询零回写 MapData（summary 不变）")
	# 界外/不可通行起点 → 空可达集（不报错）
	var void_start := GenConn.reachable_set(map, w, Hex.axial_of(Vector2i(99, 99)))
	expect((void_start["cells"] as Dictionary).is_empty(), "界外起点 → 空可达集")
