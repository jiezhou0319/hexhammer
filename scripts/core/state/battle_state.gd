## 整场战斗的快照：地图、单位、势力、回合数。
## 纯数据零信号——信号在 BattleEngine 上，方便测试与换皮。
class_name BattleState
extends RefCounted

var map: HexMap
var factions: Array[FactionState] = []

## id -> UnitState / Vector2i -> id 两张索引表，移动必须走 move_unit 保持一致
var units := {}
var units_by_pos := {}
var next_unit_id := 1

var round_no := 1
var winner_faction_id := -1   # -1 = 战斗进行中

func add_faction(def: FactionDef) -> FactionState:
	var fs := FactionState.new()
	fs.id = factions.size()
	fs.def = def
	factions.append(fs)
	return fs

func add_unit(profile: UnitProfile, faction_id: int, pos: Vector2i) -> UnitState:
	var u := UnitState.new()
	u.id = next_unit_id
	next_unit_id += 1
	u.profile = profile
	u.faction_id = faction_id
	u.wounds_left = profile.wounds
	u.pos = pos
	units[u.id] = u
	units_by_pos[pos] = u.id
	factions[faction_id].unit_ids.append(u.id)
	return u

func remove_unit(u: UnitState) -> void:
	units.erase(u.id)
	if units_by_pos.get(u.pos) == u.id:
		units_by_pos.erase(u.pos)
	u.engaged_with.clear()

func move_unit(u: UnitState, new_pos: Vector2i) -> void:
	if units_by_pos.get(u.pos) == u.id:
		units_by_pos.erase(u.pos)
	u.pos = new_pos
	units_by_pos[new_pos] = u.id

func unit_at(pos: Vector2i) -> UnitState:
	if not units_by_pos.has(pos):
		return null
	return units[units_by_pos[pos]]

func unit_by_id(uid: int) -> UnitState:
	return units.get(uid)

func living_units(faction_id: int) -> Array:
	var out := []
	for uid in factions[faction_id].unit_ids:
		var u: UnitState = units.get(uid)
		if u != null and u.alive():
			out.append(u)
	return out

func any_living_units(faction_id: int) -> bool:
	return living_units(faction_id).size() > 0

## 与 u 相邻的所有敌方存活单位
func enemies_adjacent(u: UnitState) -> Array:
	var out := []
	for n in Hex.neighbors(u.pos):
		var other := unit_at(n)
		if other != null and other.alive() and other.faction_id != u.faction_id:
			out.append(other)
	return out

func is_engaged(u: UnitState) -> bool:
	return enemies_adjacent(u).size() > 0

## 距离 u 最近的敌方存活单位（溃逃方向用），无敌人返回 null
func nearest_enemy(u: UnitState) -> UnitState:
	var best: UnitState = null
	var best_d := 1 << 30
	for other in units.values():
		if not other.alive() or other.faction_id == u.faction_id:
			continue
		var d := Hex.distance(u.pos, other.pos)
		if d < best_d:
			best_d = d
			best = other
	return best
