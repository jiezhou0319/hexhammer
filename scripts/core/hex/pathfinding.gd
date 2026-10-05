## 寻路与移动范围（Dijkstra）。六边形地图不必用 AStar2D，
## 自写 Dijkstra 顺便把"范围"和"路径"一次算完，纯逻辑可单测。
##
## 穿越规则（战锤风）：敌军占据的格子不可穿；
## 友军格子可穿但不可停留——由调用方对终点过滤。
class_name HexPathfinding
extends RefCounted

## 返回 {hex: 最低代价}，含 origin。blocked: {hex: true}（不可进入）。
static func reachable(map: HexMap, blocked: Dictionary, origin: Vector2i, max_cost: float) -> Dictionary:
	var cost_so_far := {origin: 0.0}
	var frontier: Array = [[0.0, origin]]
	while not frontier.is_empty():
		frontier.sort_custom(func(a, b): return a[0] < b[0])
		var cur: Array = frontier.pop_front()
		var cur_cost: float = cur[0]
		var cur_hex: Vector2i = cur[1]
		if cur_cost > cost_so_far.get(cur_hex, 1e9):
			continue
		for nxt in Hex.neighbors(cur_hex):
			if not map.in_bounds(nxt) or blocked.get(nxt, false):
				continue
			var step := cur_cost + map.move_cost(nxt)
			if step > max_cost or step >= cost_so_far.get(nxt, 1e9):
				continue
			cost_so_far[nxt] = step
			frontier.append([step, nxt])
	return cost_so_far

## 返回从 origin 到 dest 的格子序列（含两端）；不可达返回空数组。
static func find_path(
	map: HexMap, blocked: Dictionary, origin: Vector2i, dest: Vector2i, max_cost: float
) -> Array[Vector2i]:
	if not map.in_bounds(dest) or blocked.get(dest, false):
		return []
	var cost_so_far := {origin: 0.0}
	var came_from := {}
	var frontier: Array = [[0.0, origin]]
	while not frontier.is_empty():
		frontier.sort_custom(func(a, b): return a[0] < b[0])
		var cur: Array = frontier.pop_front()
		var cur_hex: Vector2i = cur[1]
		if cur_hex == dest:
			break
		var cur_cost: float = cost_so_far[cur_hex]
		for nxt in Hex.neighbors(cur_hex):
			if not map.in_bounds(nxt) or blocked.get(nxt, false):
				continue
			var step := cur_cost + map.move_cost(nxt)
			if step > max_cost or step >= cost_so_far.get(nxt, 1e9):
				continue
			cost_so_far[nxt] = step
			came_from[nxt] = cur_hex
			frontier.append([step, nxt])
	if not cost_so_far.has(dest):
		return []
	var path: Array[Vector2i] = [dest]
	var node := dest
	while node != origin:
		node = came_from[node]
		path.push_front(node)
	return path
