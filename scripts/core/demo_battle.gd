## Demo 混战：三势力、各一英雄带四杂兵、三角布阵。
## 以后换成正式的军队表（Army List .tres）时，只需替换这个工厂。
class_name DemoBattle
extends RefCounted

const FACTION_CRIMSON := preload("res://resources/factions/crimson_host.tres")
const FACTION_IRONBOUND := preload("res://resources/factions/ironbound_clan.tres")
const FACTION_VERDANT := preload("res://resources/factions/verdant_wardens.tres")

const CAPTAIN := preload("res://resources/units/war_captain.tres")
const WARDEN := preload("res://resources/units/blade_warden.tres")
const HUNTER := preload("res://resources/units/hunter.tres")
const RAIDER := preload("res://resources/units/iron_raider.tres")
const WILDBLOOD := preload("res://resources/units/wildblood.tres")

static func build(cols: int = 40, rows: int = 30, map_seed: int = 20261005) -> BattleState:
	var st := BattleState.new()
	st.map = HexMap.new(cols, rows, map_seed)

	var crimson := st.add_faction(FACTION_CRIMSON)
	var ironbound := st.add_faction(FACTION_IRONBOUND)
	var verdant := st.add_faction(FACTION_VERDANT)

	_deploy(st, crimson.id, Hex.offset_to_axial(5, 5), [
		[CAPTAIN, 1], [WARDEN, 2], [HUNTER, 2],
	])
	_deploy(st, ironbound.id, Hex.offset_to_axial(cols - 6, 5), [
		[CAPTAIN, 1], [RAIDER, 3], [HUNTER, 1],
	])
	_deploy(st, verdant.id, Hex.offset_to_axial(cols / 2, rows - 6), [
		[CAPTAIN, 1], [WILDBLOOD, 2], [WARDEN, 1], [HUNTER, 1],
	])
	return st

## 在锚点附近螺旋找空格放置 n 个单位
static func _deploy(st: BattleState, faction_id: int, anchor: Vector2i, roster: Array) -> void:
	for entry in roster:
		var profile: UnitProfile = entry[0]
		for i in entry[1]:
			var spot: Variant = _find_free_hex(st, anchor)
			if spot == null:
				push_warning("no free hex near %s" % str(anchor))
				return
			st.add_unit(profile, faction_id, spot as Vector2i)

static func _find_free_hex(st: BattleState, anchor: Vector2i) -> Variant:
	if st.map.in_bounds(anchor) and st.unit_at(anchor) == null:
		return anchor
	for radius in range(1, 6):
		for hex in st.map.hexes_in_range(anchor, radius):
			if st.unit_at(hex) == null:
				return hex
	return null
