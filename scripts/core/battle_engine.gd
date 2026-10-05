## 战斗引擎：校验并执行命令、推进回合、解算近战与心理学、发信号。
## 逻辑中枢——表现层只许调它，不许直接改 BattleState。
class_name BattleEngine
extends RefCounted

signal state_changed
signal logged(text: String)
signal battle_over(winner_name: String)

var state: BattleState
var rng := BattleRNG.new()
var turn := TurnMachine.new()

## 最近一次命令失败的原因（UI 提示用）
var last_error := ""

func start_battle(p_state: BattleState, p_seed: int = 0) -> void:
	state = p_state
	rng = BattleRNG.new(p_seed)
	turn = TurnMachine.new()
	for i in state.factions.size():
		turn.faction_order.append(i)
	_log("— The battle begins —")
	_begin_faction_turn()

# ============================================================
# 命令原语（命令对象调用；返回 "" = 成功，否则为失败原因）
# ============================================================

func apply_move(unit_id: int, dest: Vector2i) -> String:
	var err := _common_check(unit_id, TurnMachine.Phase.MOVE)
	if err != "":
		return err
	var u := state.unit_by_id(unit_id)
	if u.moved_this_turn or u.charged_this_turn:
		return "already moved this turn"
	if state.is_engaged(u):
		return "engaged in combat — cannot walk away"
	if not state.map.in_bounds(dest):
		return "out of bounds"
	if state.unit_at(dest) != null:
		return "hex occupied"
	if not _raw_reachable(u).has(dest):
		return "out of move range"
	if _enemy_adjacent_at(dest, u.faction_id):
		return "may not move adjacent to an enemy (charge instead)"
	state.move_unit(u, dest)
	u.moved_this_turn = true
	_log("%s moves to (%d,%d)" % [u.display_name(), dest.x, dest.y])
	state_changed.emit()
	return ""

func apply_charge(unit_id: int, target_id: int) -> String:
	var err := _common_check(unit_id, TurnMachine.Phase.MOVE)
	if err != "":
		return err
	var u := state.unit_by_id(unit_id)
	var t := state.unit_by_id(target_id)
	if t == null or not t.alive():
		return "no such target"
	if t.faction_id == u.faction_id:
		return "not an enemy"
	if u.moved_this_turn or u.charged_this_turn:
		return "already moved this turn"
	if state.is_engaged(u):
		return "engaged in combat — cannot charge"
	var max_d := float(u.profile.movement * 2)
	var dist := Hex.distance(u.pos, t.pos)
	if float(dist) > max_d:
		return "out of charge range"
	if t.fleeing:
		# 冲溃逃者：直接斩杀（8 版 skirmish 简化）
		state.move_unit(u, t.pos)
		u.charged_this_turn = true
		u.moved_this_turn = true
		_log("%s runs down the fleeing %s!" % [u.display_name(), t.display_name()])
		state.remove_unit(t)
		_check_victory()
		state_changed.emit()
		return ""
	var landing: Variant = _charge_landing(u, t, max_d)
	if landing == null:
		return "no room to engage"
	var land_hex := landing as Vector2i
	state.move_unit(u, land_hex)
	u.charged_this_turn = true
	u.moved_this_turn = true
	u.engaged_with.append(t.id)
	t.engaged_with.append(u.id)
	_log("%s charges %s!" % [u.display_name(), t.display_name()])
	# 恐惧：被冲方带 Fear，冲方（非狂暴）测 Ld
	if t.has_rule(&"fear") and not u.has_rule(&"frenzy"):
		var fr := Psychology.fear_test(_effective_ld(u), rng)
		_log(fr.describe("Fear"))
		if not fr.passed:
			u.fear_failed_this_turn = true
			_log("%s is terrified — WS1 this turn" % u.display_name())
	state_changed.emit()
	return ""

func apply_shot(unit_id: int, target_id: int) -> String:
	var err := _common_check(unit_id, TurnMachine.Phase.SHOOTING)
	if err != "":
		return err
	var u := state.unit_by_id(unit_id)
	var t := state.unit_by_id(target_id)
	if t == null or not t.alive() or t.faction_id == u.faction_id:
		return "invalid target"
	if u.fired_this_turn:
		return "already fired this turn"
	if state.is_engaged(u):
		return "engaged in combat — cannot shoot"
	if not u.can_shoot():
		return "no ranged weapon"
	var w := u.profile.ranged_weapon
	if w.move_or_fire and (u.moved_this_turn or u.charged_this_turn):
		return "moved this turn — move-or-fire weapon cannot fire"
	var dist := Hex.distance(u.pos, t.pos)
	if dist > w.range_hex:
		return "out of range"
	var res := CombatResolver.resolve_attacks(
		rng,
		CombatResolver.ranged_hit_target(u.profile.ballistic_skill),
		u.shot_strength(),
		1,
		t.profile.toughness,
		t.profile.armor_save,
		t.profile.ward_save,
		w.armor_piercing,
		u.display_name(),
		t.display_name(),
	)
	for line in res.log_lines:
		_log(line)
	u.fired_this_turn = true
	_apply_wounds(t, res.unsaved_wounds)
	_check_victory()
	state_changed.emit()
	return ""

func apply_end_phase() -> bool:
	if state == null or state.winner_faction_id != -1:
		return false
	if turn.current_phase() == TurnMachine.Phase.COMBAT:
		resolve_combat_phase()
	var info := turn.advance()
	if info.faction_changed:
		_skip_dead_factions()
		_begin_faction_turn()
	_check_victory()
	state_changed.emit()
	return true

# ============================================================
# UI 查询
# ============================================================

## 当前可选单位（该势力回合内还没行动完的）
func active_units() -> Array:
	if state == null or state.winner_faction_id != -1:
		return []
	return state.living_units(turn.active_faction())

func is_unit_active(u: UnitState) -> bool:
	return u.faction_id == turn.active_faction() and u.alive()

## 移动阶段可走的格 {hex: cost}；不满足前提返回空
func reachable_hexes(u: UnitState) -> Dictionary:
	if turn.current_phase() != TurnMachine.Phase.MOVE:
		return {}
	if u.faction_id != turn.active_faction() or u.moved_this_turn or u.charged_this_turn:
		return {}
	if u.fleeing or state.is_engaged(u):
		return {}
	var out := {}
	for hex in _raw_reachable(u):
		if state.unit_at(hex) != null:
			continue
		if _enemy_adjacent_at(hex, u.faction_id):
			continue
		out[hex] = _raw_reachable(u)[hex]
	return out

## 射击阶段当前可射的目标
func shootable_targets(u: UnitState) -> Array:
	if turn.current_phase() != TurnMachine.Phase.SHOOTING:
		return []
	if u.faction_id != turn.active_faction() or u.fired_this_turn or not u.can_shoot():
		return []
	if u.fleeing or state.is_engaged(u):
		return []
	var w := u.profile.ranged_weapon
	if w.move_or_fire and (u.moved_this_turn or u.charged_this_turn):
		return []
	var out := []
	for other in state.units.values():
		if other.alive() and other.faction_id != u.faction_id and Hex.distance(u.pos, other.pos) <= w.range_hex:
			out.append(other)
	return out

## 移动阶段当前可冲的目标
func chargeable_targets(u: UnitState) -> Array:
	if turn.current_phase() != TurnMachine.Phase.MOVE:
		return []
	if u.faction_id != turn.active_faction() or u.moved_this_turn or u.charged_this_turn:
		return []
	if u.fleeing or state.is_engaged(u):
		return []
	var out := []
	for other in state.units.values():
		if other.alive() and other.faction_id != u.faction_id:
			if Hex.distance(u.pos, other.pos) <= u.profile.movement * 2:
				out.append(other)
	return out

# ============================================================
# 近战阶段
# ============================================================

func resolve_combat_phase() -> void:
	var fid := turn.active_faction()
	var pairs := {}
	for u in state.living_units(fid):
		for e in state.enemies_adjacent(u):
			var key: int = mini(u.id, e.id) * 100000 + maxi(u.id, e.id)
			pairs[key] = [u, e]
	if pairs.is_empty():
		_log("No engagements to resolve.")
		return
	for key in pairs:
		var pair: Array = pairs[key]
		var a: UnitState = pair[0]
		var b: UnitState = pair[1]
		if not a.alive() or not b.alive():
			continue
		_resolve_melee_pair(a, b)

func _resolve_melee_pair(a: UnitState, b: UnitState) -> void:
	_log("— %s vs %s —" % [a.display_name(), b.display_name()])
	var a_first := false
	if a.charged_this_turn and not b.charged_this_turn:
		a_first = true
	elif b.charged_this_turn and not a.charged_this_turn:
		a_first = false
	else:
		a_first = a.profile.initiative >= b.profile.initiative
	var dealt_by_a := 0
	var dealt_by_b := 0
	if a_first:
		dealt_by_a = _strike(a, b)
		if b.alive():
			dealt_by_b = _strike(b, a)
	else:
		dealt_by_b = _strike(b, a)
		if a.alive():
			dealt_by_a = _strike(a, b)
	if not a.alive() or not b.alive():
		return
	var diff := dealt_by_a - dealt_by_b
	if diff == 0:
		_log("Stalemate — nobody breaks.")
		return
	var loser := b if diff > 0 else a
	var winner := a if diff > 0 else b
	var bt := Psychology.break_test(_effective_ld(loser), -absi(diff), rng)
	_log(bt.describe("Break"))
	if bt.passed:
		_log("%s holds the line!" % loser.display_name())
		return
	_log("%s breaks and flees!" % loser.display_name())
	var flee := _do_flee(loser, winner)
	_do_pursue(winner, loser, flee)

func _strike(attacker: UnitState, target: UnitState) -> int:
	var res := CombatResolver.resolve_attacks(
		rng,
		CombatResolver.melee_hit_target(attacker.effective_ws(), target.effective_ws()),
		attacker.melee_strength(),
		attacker.attack_count(),
		target.profile.toughness,
		target.profile.armor_save,
		target.profile.ward_save,
		attacker.melee_ap(),
		attacker.display_name(),
		target.display_name(),
	)
	for line in res.log_lines:
		_log(line)
	_apply_wounds(target, res.unsaved_wounds)
	return res.unsaved_wounds

# ============================================================
# 溃逃 / 追击
# ============================================================

## 返回 {dist: 实际跑的格数, dir: 方向}；出界时 dist = -1
func _do_flee(u: UnitState, threat: UnitState) -> Dictionary:
	u.fleeing = true
	u.engaged_with.clear()
	var dir := _flee_direction(u, threat.pos)
	var dist := rng.d6()
	var stepped := 0
	for i in dist:
		var nxt := u.pos + dir
		if not state.map.in_bounds(nxt):
			_log("%s runs off the field!" % u.display_name())
			state.remove_unit(u)
			return {"dist": -1, "dir": dir}
		if state.unit_at(nxt) != null:
			break
		state.move_unit(u, nxt)
		stepped += 1
	_log("%s flees %d hex(es)" % [u.display_name(), stepped])
	return {"dist": stepped, "dir": dir}

func _do_pursue(winner: UnitState, loser: UnitState, flee: Dictionary) -> void:
	if not winner.alive():
		return
	var fd: int = flee.dist
	if fd < 0:
		return
	var dir: Vector2i = flee.dir
	var pd := rng.d6()
	var stepped := 0
	for i in pd:
		var nxt := winner.pos + dir
		if not state.map.in_bounds(nxt) or state.unit_at(nxt) != null:
			break
		state.move_unit(winner, nxt)
		stepped += 1
	if pd >= fd:
		_log("%s pursues (%d vs %d) — quarry caught and cut down!" % [
			winner.display_name(), pd, fd
		])
		state.remove_unit(loser)
	else:
		_log("%s pursues %d hex(es) — quarry escapes" % [winner.display_name(), stepped])

func _flee_direction(u: UnitState, threat_pos: Vector2i) -> Vector2i:
	var best_dir := Hex.DIRECTIONS[0]
	var best_gain := -1000000
	for d in Hex.DIRECTIONS:
		var nxt := u.pos + d
		if not state.map.in_bounds(nxt):
			continue
		var gain := Hex.distance(nxt, threat_pos) - Hex.distance(u.pos, threat_pos)
		if gain > best_gain:
			best_gain = gain
			best_dir = d
	return best_dir

# ============================================================
# 内部
# ============================================================

func _begin_faction_turn() -> void:
	var fid := turn.active_faction()
	var fac := state.factions[fid]
	_log("Round %d — %s's turn" % [turn.round_no, fac.display_name()])
	for u in state.living_units(fid):
		u.moved_this_turn = false
		u.charged_this_turn = false
		u.fired_this_turn = false
		u.fear_failed_this_turn = false
		if u.fleeing:
			var threat := state.nearest_enemy(u)
			if threat == null:
				u.fleeing = false
				_log("%s rallies." % u.display_name())
			else:
				_do_flee(u, threat)
	_check_victory()

func _skip_dead_factions() -> void:
	if state.factions.size() <= 1:
		return
	var guard := 0
	while not state.any_living_units(turn.active_faction()) and guard < 100:
		_log("%s is wiped out." % state.factions[turn.active_faction()].display_name())
		turn.skip_faction()
		guard += 1

func _check_victory() -> void:
	if state.winner_faction_id != -1:
		return
	var alive := []
	for i in state.factions.size():
		if state.any_living_units(i):
			alive.append(i)
	if alive.size() == 1:
		state.winner_faction_id = alive[0]
		var wname := state.factions[alive[0]].display_name()
		_log(">>> %s wins the field! <<<" % wname)
		battle_over.emit(wname)
	elif alive.is_empty():
		state.winner_faction_id = -2
		_log(">>> Mutual annihilation — the crows feast tonight <<<")
		battle_over.emit("Nobody")

## 英雄光环：8 格内友军英雄在场时，Ld 测试用英雄的 Ld
func _effective_ld(u: UnitState) -> int:
	var best := u.profile.leadership
	for f in state.living_units(u.faction_id):
		if f.is_hero() and f.id != u.id and Hex.distance(u.pos, f.pos) <= 8:
			best = maxi(best, f.profile.leadership)
	return best

func _apply_wounds(u: UnitState, n: int) -> void:
	if n <= 0:
		return
	u.wounds_left -= n
	if u.wounds_left > 0:
		_log("%s has %d wound(s) left" % [u.display_name(), u.wounds_left])
	else:
		_log("%s is slain!" % u.display_name())
		state.remove_unit(u)

func _common_check(unit_id: int, phase: int) -> String:
	if state.winner_faction_id != -1:
		return "battle is over"
	if turn.current_phase() != phase:
		return "not in %s phase" % TurnMachine.PHASE_NAMES[phase]
	var u := state.unit_by_id(unit_id)
	if u == null or not u.alive():
		return "no such unit"
	if u.faction_id != turn.active_faction():
		return "not this faction's turn"
	return ""

func _raw_reachable(u: UnitState) -> Dictionary:
	return HexPathfinding.reachable(
		state.map, _blocked_for(u), u.pos, float(u.profile.movement)
	)

## 敌方占据的格子不可穿越；友军可穿不可停
func _blocked_for(u: UnitState) -> Dictionary:
	var blocked := {}
	for other in state.units.values():
		if other.alive() and other.faction_id != u.faction_id:
			blocked[other.pos] = true
	return blocked

func _enemy_adjacent_at(pos: Vector2i, faction_id: int) -> bool:
	for n in Hex.neighbors(pos):
		var other := state.unit_at(n)
		if other != null and other.alive() and other.faction_id != faction_id:
			return true
	return false

## 冲锋落点：目标邻格中"空且冲锋者可达"的最近一个
func _charge_landing(u: UnitState, t: UnitState, max_cost: float) -> Variant:
	var reach := HexPathfinding.reachable(state.map, _blocked_for(u), u.pos, max_cost)
	var best: Variant = null
	var best_cost := 1e9
	for n in Hex.neighbors(t.pos):
		if not state.map.in_bounds(n) or state.unit_at(n) != null:
			continue
		if reach.has(n) and float(reach[n]) < best_cost:
			best_cost = float(reach[n])
			best = n
	return best

func _log(text: String) -> void:
	logged.emit(text)
