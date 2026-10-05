## HUD：阶段信息条、单位卡、战斗日志、错误提示。全代码构建，无场景依赖。
class_name BattleHUD
extends CanvasLayer

var phase_label: Label
var hint_label: Label
var unit_label: Label
var log_text: RichTextLabel
var toast_label: Label
var end_phase_btn: Button
var over_label: Label

var engine: BattleEngine

func _ready() -> void:
	layer = 10
	_build()

func bind(p_engine: BattleEngine) -> void:
	engine = p_engine
	engine.logged.connect(_on_log)
	engine.battle_over.connect(_on_over)
	refresh(engine)

# ---------------- 构建 ----------------

func _build() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 44
	add_child(top)
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 16)
	top.add_child(hbox)

	phase_label = Label.new()
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(phase_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	end_phase_btn = Button.new()
	end_phase_btn.text = "End Phase [E]"
	end_phase_btn.pressed.connect(_on_end_phase)
	hbox.add_child(end_phase_btn)

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -30
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.text = "LMB select/act | RMB/Esc cancel | E end phase | WASD pan | wheel zoom"
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	add_child(hint_label)

	var unit_panel := PanelContainer.new()
	unit_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	unit_panel.offset_left = 10
	unit_panel.offset_top = -240
	unit_panel.offset_right = 300
	unit_panel.offset_bottom = -38
	add_child(unit_panel)
	unit_label = Label.new()
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_panel.add_child(unit_label)

	var log_panel := PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	log_panel.offset_left = -430
	log_panel.offset_right = -8
	log_panel.offset_top = 54
	log_panel.offset_bottom = -40
	add_child(log_panel)
	log_text = RichTextLabel.new()
	log_text.scroll_following = true
	log_text.scroll_active = true
	log_text.bbcode_enabled = false
	log_panel.add_child(log_text)

	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_top = 60
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.hide()
	add_child(toast_label)

	over_label = Label.new()
	over_label.set_anchors_preset(Control.PRESET_CENTER)
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_label.add_theme_font_size_override("font_size", 42)
	over_label.hide()
	add_child(over_label)

# ---------------- 更新 ----------------

func refresh(p_engine: BattleEngine) -> void:
	engine = p_engine
	if engine.state == null:
		return
	var fac := engine.state.factions[engine.turn.active_faction()]
	if engine.state.winner_faction_id != -1:
		phase_label.text = "BATTLE OVER — %s" % ("nobody" if engine.state.winner_faction_id == -2 else engine.state.factions[engine.state.winner_faction_id].display_name())
	else:
		phase_label.text = "Round %d   |   %s   |   %s" % [
			engine.turn.round_no, fac.display_name(), engine.turn.phase_name()
		]

func set_selected(u: UnitState) -> void:
	if u == null:
		unit_label.text = ""
		return
	var p := u.profile
	var lines := [
		"%s%s" % ["" if not u.is_hero() else "HERO: ", p.display_name],
		"M %d  WS %d  BS %d  S %d  T %d" % [p.movement, p.weapon_skill, p.ballistic_skill, p.strength, p.toughness],
		"W %d/%d  I %d  A %d  Ld %d" % [u.wounds_left, p.wounds, p.initiative, p.attacks, p.leadership],
		"Armor %s  Ward %s" % [
			("none" if p.armor_save >= 7 else "%d+" % p.armor_save),
			("none" if p.ward_save <= 0 else "%d+" % p.ward_save),
		],
		"Weapons: %s%s" % [
			p.melee_weapon.display_name if p.melee_weapon != null else "bare hands",
			(" + %s (%d hex)" % [p.ranged_weapon.display_name, p.ranged_weapon.range_hex]) if p.ranged_weapon != null else "",
		],
	]
	var rules := []
	for r in p.special_rules:
		rules.append(r.display_name)
	if not rules.is_empty():
		lines.append("Rules: " + ", ".join(rules))
	var status := []
	if u.fleeing:
		status.append("FLEEING")
	if u.charged_this_turn:
		status.append("charged")
	if status.size() > 0:
		lines.append("Status: " + " ".join(status))
	unit_label.text = "\n".join(lines)

func flash(text: String) -> void:
	toast_label.text = text
	toast_label.show()
	get_tree().create_timer(1.6).timeout.connect(toast_label.hide)

# ---------------- 回调 ----------------

func _on_end_phase() -> void:
	if engine != null:
		EndPhaseCommand.new().execute(engine)
		refresh(engine)

func _on_log(text: String) -> void:
	log_text.add_text(text + "\n")

func _on_over(winner_name: String) -> void:
	over_label.text = "%s\nholds the field!" % winner_name
	over_label.show()
