## map_connectivity.gd — 地图连通性检查（M1a-T9；docs/04-tasks-m1.md M1a-T9 细化
##   「生成管线：… → 连通性检查」+ M1a 实现调研「随机地图：… 连通性检查，断路/孤岛」）
## 语义（「可玩」的可执行定义）：棋子只落在可通行格上，故连通对象 = **通行格**，
## 邻接 = MapData.neighbors_existing（界内邻居；高程差在本期不阻碍移动——地形/高程
## 修正值 M1b-T4 起才挂 mods、M3 拍板后才填）。水/悬崖在 M1a 数据层同属「不可通行
## = 无连接的结算面」，由生成器显式标记（水体），不在此二次推导。
## 判定：ok = 通行格数 > 0 且最大连通片占比 ≥ min_largest_fraction（默认 1.0 =
## 全部通行格连成一片；断路/孤岛 → ok=false，分量明细进报告供落盘留证）。
## 纯函数：RefCounted、零场景节点、不改入参地图（ADR-2）。
class_name MapConnectivity
extends RefCounted

const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 检查一张图的通行格连通性。
## 返回 {
##   "ok": bool,                    # 判定结果（见类头注）
##   "passable_total": int,         # 通行格总数
##   "component_count": int,        # 连通分量数
##   "largest_size": int,           # 最大分量格数
##   "largest_fraction": float,     # 最大分量 / 通行格总数（通行格为 0 时 = 0.0）
##   "components": Array[Array],    # 各分量格子表（Vector2i；按固定遍历序的首次发现序，
##                                  #   分量内序 = BFS 访问序——同图恒同值，可作回归锚）
##   "isolated_cells": Array,       # 孤立单格分量（分量大小 = 1 的格，调试面）
## }
static func check(map: MapDataClass, min_largest_fraction := 1.0) -> Dictionary:
	var components: Array[Array] = []
	var isolated: Array = []
	var visited := {}
	for start in map.cells():
		if visited.has(start) or not map.is_passable(start):
			continue
		var comp: Array = []
		var queue: Array = [start]
		visited[start] = true
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			comp.append(cell)
			for nb in map.neighbors_existing(cell):
				if not visited.has(nb) and map.is_passable(nb):
					visited[nb] = true
					queue.append(nb)
		components.append(comp)
		if comp.size() == 1:
			isolated.append(comp[0])

	var total := 0
	var largest := 0
	for comp in components:
		total += comp.size()
		largest = maxi(largest, comp.size())
	var fraction := float(largest) / float(total) if total > 0 else 0.0
	return {
		"ok": total > 0 and fraction >= min_largest_fraction,
		"passable_total": total,
		"component_count": components.size(),
		"largest_size": largest,
		"largest_fraction": fraction,
		"components": components,
		"isolated_cells": isolated,
	}


## 报告的落盘摘要（不含分量全表——格子表本体在地图 JSON 里，这里只留可读指标；
## 与 MapGenerator.meta 的 connectivity 字段同键集，失败图留证用）。
static func summary_of(report: Dictionary) -> Dictionary:
	return {
		"ok": report["ok"],
		"passable_total": report["passable_total"],
		"component_count": report["component_count"],
		"largest_size": report["largest_size"],
		"largest_fraction": report["largest_fraction"],
	}
