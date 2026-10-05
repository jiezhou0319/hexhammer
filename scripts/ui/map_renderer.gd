## 战场绘制：程序画六边形与棋子，零美术依赖。
## 只读 BattleState 渲染；高亮数据由 InputController 推送。
## 以后接美术资产时，替换本类为 TileMapLayer + 单位场景即可，接口不变。
class_name MapRenderer
extends Node2D

const HEX_SIZE := 34.0

const TERRAIN_COLORS := {
	HexMap.Terrain.PLAIN: Color(0.30, 0.42, 0.24),
	HexMap.Terrain.FOREST: Color(0.13, 0.30, 0.15),
	HexMap.Terrain.HILL: Color(0.45, 0.40, 0.22),
	HexMap.Terrain.MARSH: Color(0.22, 0.32, 0.38),
	HexMap.Terrain.RUIN: Color(0.38, 0.36, 0.34),
}

const EDGE_COLOR := Color(0, 0, 0, 0.25)
const REACH_COLOR := Color(0.35, 0.62, 0.95, 0.30)
const HOVER_COLOR := Color.WHITE
const SELECT_COLOR := Color(1.0, 0.85, 0.2)
const SHOOT_MARK := Color(0.95, 0.2, 0.2)
const CHARGE_MARK := Color(1.0, 0.5, 0.1)

var map: HexMap
var state: BattleState
var engine: BattleEngine

var hover_hex: Variant = null
var selected: UnitState = null
var reachable := {}
var shoot_targets: Array = []
var charge_targets: Array = []

func setup(p_engine: BattleEngine) -> void:
	engine = p_engine
	map = p_engine.state.map
	state = p_engine.state

func world_to_hex(p: Vector2) -> Vector2i:
	return Hex.from_pixel(p, HEX_SIZE)

func set_selection(
	p_selected: UnitState, p_reachable: Dictionary, p_shoot: Array, p_charge: Array
) -> void:
	selected = p_selected
	reachable = p_reachable
	shoot_targets = p_shoot
	charge_targets = p_charge
	queue_redraw()

func set_hover(hex: Variant) -> void:
	if hover_hex != hex:
		hover_hex = hex
		queue_redraw()

func _draw() -> void:
	if map == null:
		return
	for hex in map.terrain:
		_draw_hex(hex, TERRAIN_COLORS[map.get_terrain(hex)], 1.0)
	for hex in reachable:
		_draw_hex(hex, REACH_COLOR, 1.0)
	for u in state.units.values():
		_draw_unit(u)
	if hover_hex != null and map.in_bounds(hover_hex):
		_draw_hex_outline(hover_hex, HOVER_COLOR, 2.0)
	if selected != null and selected.alive():
		_draw_hex_outline(selected.pos, SELECT_COLOR, 3.0)
	for t in shoot_targets:
		_draw_hex_outline(t.pos, SHOOT_MARK, 3.0)
	for t in charge_targets:
		_draw_hex_outline(t.pos, CHARGE_MARK, 3.0)

func _draw_hex(hex: Vector2i, color: Color, _scale: float) -> void:
	var c := Hex.to_pixel(hex, HEX_SIZE)
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(Hex.corner(c, HEX_SIZE * 0.96, i))
	draw_colored_polygon(pts, color)
	_draw_hex_outline(hex, EDGE_COLOR, 1.0)

func _draw_hex_outline(hex: Vector2i, color: Color, width: float) -> void:
	var c := Hex.to_pixel(hex, HEX_SIZE)
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(Hex.corner(c, HEX_SIZE * 0.96, i))
	pts.append(pts[0])
	draw_polyline(pts, color, width)

func _draw_unit(u: UnitState) -> void:
	var fac := state.factions[u.faction_id]
	var base: Color = fac.color()
	var is_active := u.faction_id == engine.turn.active_faction()
	var color := base.lerp(Color(0.3, 0.3, 0.3), 0.0 if is_active else 0.55)
	if u.fleeing:
		color = color.lerp(Color(0.85, 0.8, 0.7), 0.6)
	var c := Hex.to_pixel(u.pos, HEX_SIZE)
	var r := HEX_SIZE * (0.48 if u.is_hero() else 0.36)
	draw_circle(c, r, color)
	draw_arc(c, r, 0, TAU, 24, Color(0, 0, 0, 0.6), 2.0)
	if u.is_hero():
		draw_arc(c, r + 4.0, 0, TAU, 24, Color(1, 1, 1, 0.9), 1.5)
	# 血条：当前势力回合外的暗一些
	var w := u.wounds_left
	var max_w := u.profile.wounds
	if max_w > 1 or w < max_w:
		var bar_w := 26.0
		var frac := float(w) / float(max_w)
		var y := c.y + r + 5.0
		draw_rect(Rect2(c.x - bar_w / 2, y, bar_w, 4), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(c.x - bar_w / 2, y, bar_w * frac, 4), Color(0.8, 0.15, 0.15))
	if u.fleeing:
		var font := ThemeDB.fallback_font
		draw_string(font, c + Vector2(-6, -r - 4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 0.3))
