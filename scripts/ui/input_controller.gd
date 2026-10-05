## 输入控制：把鼠标/键盘翻译成命令对象交给引擎。
## 选中状态与高亮数据也在这里维护（推送给 renderer/hud）。
##
## 操作：左键选择/行动，右键或 Esc 取消，E / 回车结束阶段。
class_name InputController
extends Node

var engine: BattleEngine
var renderer: MapRenderer
var hud: BattleHUD

var selected: UnitState = null

func setup(p_engine: BattleEngine, p_renderer: MapRenderer, p_hud: BattleHUD) -> void:
	engine = p_engine
	renderer = p_renderer
	hud = p_hud

func _unhandled_input(event: InputEvent) -> void:
	if engine.state == null or engine.state.winner_faction_id != -1:
		return
	if event is InputEventMouseMotion:
		renderer.set_hover(renderer.world_to_hex(renderer.get_global_mouse_position()))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var world := renderer.get_global_mouse_position()
			_click(renderer.world_to_hex(world))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_select(null)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_select(null)
		elif event.keycode == KEY_E or event.keycode == KEY_KP_ENTER or event.keycode == KEY_ENTER:
			_run(EndPhaseCommand.new())

## 引擎状态变化后重算选中单位的高亮
func refresh() -> void:
	if selected != null and (not selected.alive() or selected.faction_id != engine.turn.active_faction()):
		selected = null
	var reach := {}
	var shoot: Array = []
	var charge: Array = []
	if selected != null and engine.is_unit_active(selected):
		reach = engine.reachable_hexes(selected)
		shoot = engine.shootable_targets(selected)
		charge = engine.chargeable_targets(selected)
	renderer.set_selection(selected, reach, shoot, charge)
	hud.set_selected(selected)
	hud.refresh(engine)

func _click(hex: Vector2i) -> void:
	var clicked := engine.state.unit_at(hex)
	var phase := engine.turn.current_phase()
	if clicked != null and clicked.faction_id == engine.turn.active_faction() and clicked.alive():
		_select(clicked)
		return
	if selected == null:
		return
	if phase == TurnMachine.Phase.MOVE:
		for t in engine.chargeable_targets(selected):
			if t == clicked:
				_run(ChargeCommand.new(selected.id, clicked.id))
				return
		if engine.reachable_hexes(selected).has(hex):
			_run(MoveCommand.new(selected.id, hex))
	elif phase == TurnMachine.Phase.SHOOTING:
		for t in engine.shootable_targets(selected):
			if t == clicked:
				_run(ShootCommand.new(selected.id, clicked.id))
				return

func _select(u: UnitState) -> void:
	selected = u
	refresh()

func _run(cmd: Command) -> void:
	if not cmd.execute(engine):
		if engine.last_error != "":
			hud.flash(engine.last_error)
	refresh()
