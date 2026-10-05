## 战场地图：地形表 + 程序化生成（Voronoi 撒种子，出大陆感）。
## 纯逻辑层，只管地形；单位占用表在 BattleState 里。
class_name HexMap
extends RefCounted

enum Terrain { PLAIN, FOREST, HILL, MARSH, RUIN }

## 移动代价（点）：战锤"难渡地形"的味道
const MOVE_COST := {
	Terrain.PLAIN: 1.0,
	Terrain.FOREST: 2.0,
	Terrain.HILL: 2.0,
	Terrain.MARSH: 3.0,
	Terrain.RUIN: 2.0,
}

## 地形名（日志用）
const TERRAIN_NAMES := {
	Terrain.PLAIN: "plain",
	Terrain.FOREST: "forest",
	Terrain.HILL: "hill",
	Terrain.MARSH: "marsh",
	Terrain.RUIN: "ruin",
}

var cols: int
var rows: int
## Vector2i(axial) -> Terrain
var terrain := {}

func _init(p_cols: int = 40, p_rows: int = 30, seed_value: int = 20261005) -> void:
	cols = p_cols
	rows = p_rows
	_generate(seed_value)

func in_bounds(hex: Vector2i) -> bool:
	return terrain.has(hex)

func get_terrain(hex: Vector2i) -> int:
	return terrain.get(hex, Terrain.PLAIN)

func move_cost(hex: Vector2i) -> float:
	return MOVE_COST[get_terrain(hex)]

func all_hexes() -> Array:
	return terrain.keys()

func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return in_bounds(a) and in_bounds(b) and Hex.are_neighbors(a, b)

## 找出距离 hex 不超过 radius 的所有在图内格子（含自身）
func hexes_in_range(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in terrain.keys():
		if Hex.distance(center, h) <= radius:
			out.append(h)
	return out

## 生成矩形战场（odd-r offset 铺满），Voronoi 种子决定地形。
## 战锤桌面是手摆地形板，这里先用程序生成，以后可换手工 MapDef。
func _generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	terrain.clear()
	for row in rows:
		for col in cols:
			terrain[Hex.offset_to_axial(col, row)] = Terrain.PLAIN
	# 撒地形种子：森林/丘陵多一些，沼泽废墟点缀
	var sites: Array = []
	var site_count := int(cols * rows / 22.0)
	var weights := {
		Terrain.PLAIN: 4.0,
		Terrain.FOREST: 3.0,
		Terrain.HILL: 2.0,
		Terrain.MARSH: 1.0,
		Terrain.RUIN: 1.0,
	}
	for i in site_count:
		var t := _weighted_pick(rng, weights)
		sites.append([Vector2(rng.randf() * cols, rng.randf() * rows), t])
	for hex in terrain.keys():
		var off := Hex.axial_to_offset(hex)
		var best: Array = sites[0]
		var best_d := 1e9
		for site in sites:
			var d: float = (Vector2(off) - site[0]).length_squared()
			if d < best_d:
				best_d = d
				best = site
		if best_d < 1e9:
			terrain[hex] = best[1]

static func _weighted_pick(rng: RandomNumberGenerator, weights: Dictionary) -> int:
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := rng.randf() * total
	for key in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return key
	return weights.keys()[0]
