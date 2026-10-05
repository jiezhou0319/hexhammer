extends RefCounted

class ScriptedRNG:
	extends BattleRNG
	var queue: Array[int] = []

	func d6() -> int:
		rolls_made += 1
		if queue.size() > 0:
			return queue.pop_front()
		return 6

func _rng(rolls: Array[int]) -> ScriptedRNG:
	var r := ScriptedRNG.new()
	r.queue = rolls
	return r

## 空白战场：全平原、两势力，各放一个角落单位（避免开局判全灭）
func _engine(cols: int = 14, rows: int = 12) -> BattleEngine:
	var st := BattleState.new()
	st.map = HexMap.new(cols, rows, 7)
	for hex in st.map.terrain:
		st.map.terrain[hex] = HexMap.Terrain.PLAIN
	st.add_faction(FactionDef.new())
	st.add_faction(FactionDef.new())
	st.add_unit(_profile({"name": "Anchor0"}), 0, Hex.offset_to_axial(0, 0))
	st.add_unit(_profile({"name": "Anchor1"}), 1, Hex.offset_to_axial(cols - 1, rows - 1))
	var e := BattleEngine.new()
	e.start_battle(st, 42)
	return e

func _profile(opts: Dictionary = {}) -> UnitProfile:
	var p := UnitProfile.new()
	p.display_name = String(opts.get("name", "Grunt"))
	p.movement = int(opts.get("m", 4))
	p.weapon_skill = int(opts.get("ws", 3))
	p.ballistic_skill = int(opts.get("bs", 3))
	p.strength = int(opts.get("s", 3))
	p.toughness = int(opts.get("t", 3))
	p.wounds = int(opts.get("w", 1))
	p.initiative = int(opts.get("i", 3))
	p.attacks = int(opts.get("a", 1))
	p.leadership = int(opts.get("ld", 7))
	p.armor_save = int(opts.get("save", 7))
	if opts.get("hero", false):
		p.role = UnitProfile.Role.HERO
	return p

# ---------------- 回合结构 ----------------

func test_turn_rotation() -> String:
	var e := _engine()
	if e.turn.active_faction() != 0 or e.turn.current_phase() != TurnMachine.Phase.MOVE:
		return "faction 0 / movement should start"
	e.apply_end_phase()
	if e.turn.current_phase() != TurnMachine.Phase.SHOOTING:
		return "phase 2 should be shooting"
	e.apply_end_phase()
	if e.turn.current_phase() != TurnMachine.Phase.COMBAT:
		return "phase 3 should be combat"
	e.apply_end_phase()
	if e.turn.active_faction() != 1 or e.turn.current_phase() != TurnMachine.Phase.MOVE:
		return "faction 1 should start moving now"
	e.apply_end_phase()
	e.apply_end_phase()
	e.apply_end_phase()
	if e.turn.active_faction() != 0 or e.turn.round_no != 2:
		return "round 2 / faction 0 expected, got round %d faction %d" % [
			e.turn.round_no, e.turn.active_faction()
		]
	return ""

func test_dead_faction_is_skipped() -> String:
	var e := _engine()
	# 把势力 1 的所有单位清掉
	for u in e.state.living_units(1):
		e.state.remove_unit(u)
	# 推完势力 0 的一整轮，轮转时应发现势力 1 全灭并判胜
	e.apply_end_phase()
	e.apply_end_phase()
	e.apply_end_phase()  # combat -> advance -> victory check
	if e.state.winner_faction_id != 0:
		return "faction 0 should have won, got %d" % e.state.winner_faction_id
	return ""

# ---------------- 移动 ----------------

func test_move_validation_and_success() -> String:
	var e := _engine()
	var u := e.state.add_unit(_profile(), 0, Hex.offset_to_axial(2, 2))
	var other := e.state.add_unit(_profile(), 1, Hex.offset_to_axial(5, 2))
	if not e.apply_shot(u.id, other.id).contains("not in"):
		return "shooting in movement phase should be rejected"
	if not e.apply_move(u.id, Vector2i(999, 999)).contains("out of"):
		return "moving out of bounds should be rejected"
	if not e.apply_move(u.id, other.pos).contains("occupied"):
		return "moving onto a unit should be rejected"
	if not e.apply_move(u.id, Vector2i(2, 2) + Vector2i(8, 0)).contains("out of"):
		return "moving beyond range should be rejected"
	var dest := Hex.offset_to_axial(2, 4)
	var err := e.apply_move(u.id, dest)
	if err != "":
		return "valid move rejected: " + err
	if u.pos != dest or not u.moved_this_turn:
		return "move did not apply"
	var err2 := e.apply_move(u.id, Hex.offset_to_axial(4, 3))
	if not err2.contains("already moved"):
		return "second move should be rejected, got: " + err2
	return ""

func test_move_cannot_hug_enemy() -> String:
	var e := _engine()
	var u := e.state.add_unit(_profile(), 0, Hex.offset_to_axial(2, 2))
	var enemy := e.state.add_unit(_profile(), 1, Hex.offset_to_axial(4, 2))
	# 敌人旁边那格（3,2）不可进入，只能冲锋
	var beside := Hex.offset_to_axial(3, 2)
	var err := e.apply_move(u.id, beside)
	if not err.contains("adjacent"):
		return "moving adjacent to enemy should be rejected, got: " + err
	return ""

# ---------------- 冲锋 ----------------

func test_charge_engages_target() -> String:
	var e := _engine()
	var u := e.state.add_unit(_profile({"ws": 4}), 0, Hex.offset_to_axial(2, 2))
	var t := e.state.add_unit(_profile(), 1, Hex.offset_to_axial(5, 2))
	var err := e.apply_charge(u.id, t.id)
	if err != "":
		return "charge rejected: " + err
	if not Hex.are_neighbors(u.pos, t.pos):
		return "charger should end adjacent to target"
	if not u.charged_this_turn:
		return "charge flag not set"
	if not u.engaged_with.has(t.id):
		return "engagement not recorded"
	if not e.apply_move(u.id, Hex.offset_to_axial(2, 2)).contains("already moved"):
		return "moving after charge should be rejected"
	return ""

func test_charge_out_of_range() -> String:
	var e := _engine()
	var u := e.state.add_unit(_profile({"m": 3}), 0, Hex.offset_to_axial(2, 2))
	var t := e.state.add_unit(_profile(), 1, Hex.offset_to_axial(9, 2))
	if not e.apply_charge(u.id, t.id).contains("range"):
		return "charge beyond 2xM should be rejected"
	return ""

func test_charge_sweeps_fleeing_unit() -> String:
	var e := _engine()
	var u := e.state.add_unit(_profile(), 0, Hex.offset_to_axial(2, 2))
	var t := e.state.add_unit(_profile(), 1, Hex.offset_to_axial(4, 2))
	t.fleeing = true
	var err := e.apply_charge(u.id, t.id)
	if err != "":
		return "sweep charge rejected: " + err
	if e.state.unit_by_id(t.id) != null:
		return "fleeing unit should be cut down"
	return ""

# ---------------- 射击 ----------------

func test_shooting_kills_and_wins() -> String:
	var e := _engine()
	e.rng = _rng([])  # 全 6
	var shooter := e.state.add_unit(_profile({"bs": 3}), 0, Hex.offset_to_axial(2, 2))
	var bow := WeaponProfile.new()
	bow.display_name = "Bow"
	bow.range_hex = 10
	shooter.profile.ranged_weapon = bow
	var target := e.state.add_unit(_profile({"w": 1}), 1, Hex.offset_to_axial(6, 2))
	e.apply_end_phase()  # -> shooting
	var err := e.apply_shot(shooter.id, target.id)
	if err != "":
		return "shot rejected: " + err
	if e.state.unit_by_id(target.id) != null:
		return "all-6 shooting vs armorless 1W unit should kill"
	return ""

func test_move_or_fire_weapon() -> String:
	var e := _engine()
	var u := e.state.add_unit(_profile(), 0, Hex.offset_to_axial(2, 2))
	var xbow := WeaponProfile.new()
	xbow.display_name = "Crossbow"
	xbow.range_hex = 10
	xbow.move_or_fire = true
	u.profile.ranged_weapon = xbow
	var target := e.state.add_unit(_profile(), 1, Hex.offset_to_axial(6, 2))
	e.apply_move(u.id, Hex.offset_to_axial(3, 2))
	e.apply_end_phase()  # -> shooting
	var err := e.apply_shot(u.id, target.id)
	if not err.contains("move-or-fire"):
		return "moved crossbow should not fire, got: " + err
	return ""

# ---------------- 近战与心理学 ----------------

func test_melee_break_flee_pursuit() -> String:
	var e := _engine()
	var a := e.state.add_unit(
		_profile({"name": "Champ", "ws": 5, "s": 4, "i": 5}), 0, Hex.offset_to_axial(3, 3)
	)
	var b := e.state.add_unit(
		_profile({"name": "Loser", "ws": 3, "s": 3, "i": 3, "w": 2, "ld": 5}), 1,
		Hex.offset_to_axial(4, 3)
	)
	# 队列：A命中(6) A致伤(6)【无甲】B反击(1 失手) 崩溃(6,6 必败) 溃逃(1) 追击(1>=1 追上)
	e.rng = _rng([6, 6, 1, 6, 6, 1, 1])
	e.apply_end_phase()  # move -> shoot
	e.apply_end_phase()  # shoot -> combat
	e.apply_end_phase()  # combat 解算 + 轮转
	if e.state.unit_by_id(b.id) != null:
		return "loser should have been caught while fleeing"
	return ""

func test_melee_stalemate_no_break() -> String:
	var e := _engine()
	var a := e.state.add_unit(_profile({"name": "A"}), 0, Hex.offset_to_axial(3, 3))
	var b := e.state.add_unit(_profile({"name": "B"}), 1, Hex.offset_to_axial(4, 3))
	e.rng = _rng([1, 1, 1, 1])  # 双方全失手
	e.apply_end_phase()
	e.apply_end_phase()
	e.apply_end_phase()
	if not a.alive() or not b.alive():
		return "both units should survive a stalemate"
	return ""

# ---------------- 英雄光环 ----------------

func test_hero_leadership_aura() -> String:
	var e := _engine()
	var hero := e.state.add_unit(
		_profile({"name": "Captain", "hero": true, "ld": 9}), 0, Hex.offset_to_axial(3, 3)
	)
	var grunt := e.state.add_unit(_profile({"ld": 6}), 0, Hex.offset_to_axial(8, 3))
	# 距离 5，在 8 格光环内
	if e._effective_ld(grunt) != 9:
		return "grunt should use hero Ld 9, got %d" % e._effective_ld(grunt)
	# 把英雄挪远（距离 10 > 8，光环失效）
	e.state.move_unit(hero, Hex.offset_to_axial(0, 0))
	if e._effective_ld(grunt) != 6:
		return "grunt far from hero should use own Ld 6, got %d" % e._effective_ld(grunt)
	return ""
