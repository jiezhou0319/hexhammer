## 战斗场景组装点：引擎（逻辑）+ 渲染/输入/HUD（表现）在这里接线。
## 逻辑层完全不知道这些 UI 类的存在。
class_name BattleScene
extends Node2D

const MAP_COLS := 40
const MAP_ROWS := 30
const MAP_SEED := 20261005

var engine: BattleEngine
var renderer: MapRenderer
var camera: CameraRig
var hud: BattleHUD
var input_ctl: InputController

func _ready() -> void:
	engine = BattleEngine.new()
	engine.start_battle(DemoBattle.build(MAP_COLS, MAP_ROWS, MAP_SEED))

	renderer = MapRenderer.new()
	renderer.name = "MapRenderer"
	renderer.setup(engine)
	add_child(renderer)

	camera = CameraRig.new()
	camera.name = "CameraRig"
	add_child(camera)
	camera.setup(engine.state.map)

	hud = BattleHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(engine)

	input_ctl = InputController.new()
	input_ctl.name = "InputController"
	add_child(input_ctl)
	input_ctl.setup(engine, renderer, hud)

	engine.state_changed.connect(_on_state_changed)
	_on_state_changed()

func _on_state_changed() -> void:
	renderer.queue_redraw()
	input_ctl.refresh()
