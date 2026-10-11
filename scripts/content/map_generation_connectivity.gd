## map_generation_connectivity.gd — 统一生成期连通查询（M1a T4 ROAD-03 重定义版；
##   执行方案 docs/M1a-terrain-T2-T5-execution-plan.md §5 ROAD-03 + §2.2 双口径 +
##   §2.3 横切机器定义）
## 职责：**边级通行图**的单一入口——生成侧（本批验收 fixture + T5 WORLD-05 自动
##   路网 / WORLD-04 可玩校验）共用的可达性查询：格 passable × 有河 link（无
##   crossing 认领 = 不可渡）× CrossingData.traversable 认领表。显式命名「生成期」
##   与 M3 规则层 TraversalPolicy 概念隔离（查询属生成器内部口径**不进数据**，
##   草案 §7 禁止项原文）。
## 语义（§2.2 双口径对账）：
## - 湖/海 = 格语义水体：占格、passable=false 结算面在 MapData 上——查询天然把
##   湖格当墙（is_passable 拦截，寻路 M1b-T4 同口径）；
## - 河 = 边语义水体：两侧格保持 passable——河的通行影响**只落在 link 上**：
##   无 crossing 认领的有河 link 不可渡（禁渡），认领（=桥）即可渡。两套语义
##   各自闭合、互不改写（§2.2 禁令行「有意设计」）。
## - 高程/地形修正不参与（沿 MapConnectivity「高程差在本期不阻碍移动」现状口径；
##   TraversalPolicy 属 M3 门）。道路本体不改变通行性（路是表现/网络层，通行
##   只看格 + 河）。
## 纯函数：RefCounted、零场景节点、不写任何数据（ADR-2）。回退口径：无河世界
## 本查询与 MapConnectivity 的格 passable 连通等价（tests 锚）。
class_name MapGenerationConnectivity
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")

## 单边通行判定（边级通行图的原子）：a→b 可通行 ⇔ 两格界内互为邻居 ∧ 双方
## passable ∧（无河 ∨ 有河且被 CrossingData 认领）。
## 返回 {"ok": bool, "reason": String, "link": Vector2i（a/b 可规范化时）,
##   "reach": int（河阻挡时 = 所属河段 id，否则 ID_NONE）}——失败原因串指向
## 具体格/河段（最小诊断输出；禁渡原因含 link 与 reach，供上层错误指向河段）。
static func edge_open(map: MapDataClass, world: WorldDataClass,
		a: Vector2i, b: Vector2i) -> Dictionary:
	var no_link := {"ok": false, "reason": "", "link": WorldDataClass.NO_LINK,
		"reach": WorldDataClass.ID_NONE}
	if not map.has_cell(a) or not map.has_cell(b) or Hex.dir_between(a, b) < 0:
		no_link["reason"] = "%s→%s 不互为界内邻居（边不存在）" % [str(a), str(b)]
		return no_link
	var link := WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
	if not map.is_passable(a):
		no_link["link"] = link
		no_link["reason"] = "格 %s 不可通行（格语义水体/显式标记——湖格当墙）" % str(a)
		return no_link
	if not map.is_passable(b):
		no_link["link"] = link
		no_link["reason"] = "格 %s 不可通行（格语义水体/显式标记——湖格当墙）" % str(b)
		return no_link
	if world != null:
		var river_idx := world.river_edge_index()
		if river_idx.has(link):
			var claims := world.crossing_index()
			if not claims.has(link):
				no_link["link"] = link
				no_link["reach"] = int(river_idx[link]["reach"])
				no_link["reason"] = "有河边 %s（reach %d）无 crossing 认领——禁渡（河是边语义阻挡，过河须桥）" \
					% [str(link), int(river_idx[link]["reach"])]
				return no_link
	return {"ok": true, "reason": "", "link": link, "reach": WorldDataClass.ID_NONE}


## 自 start 的可达集（BFS 沿边级通行图；同图恒同值——行主序邻居展开，可作回归锚）。
## 返回 {"cells": Dictionary（Vector2i → true 可达集）,
##   "blocked_river": Array[Dictionary]——扩张前沿撞上的**有河未认领边**逐条
##   {"link", "reach", "from_cell"}（错误指向具体河段的最小诊断输出：无桥过
##   阻挡河边失败时，blocked_river 非空且含具体 link/reach）}。
## start 界外或不可通行 → 空可达集（不报错——调用方按「无可玩格」口径处理）。
static func reachable_set(map: MapDataClass, world: WorldDataClass,
		start: Vector2i) -> Dictionary:
	var visited := {}
	var blocked: Array[Dictionary] = []
	if not map.has_cell(start) or not map.is_passable(start):
		return {"cells": visited, "blocked_river": blocked}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var seen_blocked := {}  # link → true（同一河边只报一次——BFS 多格可撞同一边）
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb) or visited.has(nb):
				continue
			var edge := edge_open(map, world, cell, nb)
			if edge["ok"]:
				visited[nb] = true
				queue.append(nb)
			elif int(edge["reach"]) != WorldDataClass.ID_NONE \
					and not seen_blocked.has(edge["link"]):
				seen_blocked[edge["link"]] = true
				blocked.append({"link": edge["link"], "reach": edge["reach"],
					"from_cell": cell})
	return {"cells": visited, "blocked_river": blocked}


## 必需端点连通（T4 验收入口 / T5 WORLD-05/WORLD-04 复用）：from→to 在边级通行图
## 上是否连通。返回 {"ok": bool, "blocked_river": Array（同 reachable_set——ok=false
## 且非空 = 败因指向具体河段；ok=false 且空 = 败因在格（不可通行/湖墙），不是河）}。
static func required_connected(map: MapDataClass, world: WorldDataClass,
		from_cell: Vector2i, to_cell: Vector2i) -> Dictionary:
	var reach := reachable_set(map, world, from_cell)
	return {"ok": reach["cells"].has(to_cell), "blocked_river": reach["blocked_river"]}


## 回退口径对账（回退 = 查询退回格 passable 连通）：无河世界（rivers 空）本查询
## 的可达划分与 MapConnectivity.check 的连通分量逐格一致——「边级图不改变无河
## 世界的通行语义」的机器表达（ROAD-03 风险与回退条 + tests 锚）。
## 返回 true = 一致（无河世界恒 true；本函数即测试/工具的对账入口）。
static func matches_cell_connectivity(map: MapDataClass, world: WorldDataClass) -> bool:
	if world != null and not world.rivers.is_empty():
		return false  # 有河世界两者口径不同（河在边上）——对账只定义无河世界
	var report := MapConnectivity.check(map)
	var covered := {}
	for comp in report["components"]:
		var start: Vector2i = comp[0]
		var reach := reachable_set(map, world, start)
		var cells: Dictionary = reach["cells"]
		if cells.size() != comp.size():
			return false
		for cell in comp:
			if not cells.has(cell):
				return false
			covered[cell] = true
	for cell in map.cells():
		if map.is_passable(cell) and not covered.has(cell):
			return false  # 通行格未被任何分量对账覆盖 = 两口径划分不一致
	return true
