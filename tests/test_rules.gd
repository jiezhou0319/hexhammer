extends RefCounted

## 脚本化骰子：按队列出骰，队列空则永远出 6
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

# ---------------- 命中/致伤/豁免表 ----------------

func test_melee_hit_target() -> String:
	var cases := [
		[10, 5, 3],   # 攻方 WS 翻倍 -> 3+
		[5, 10, 5],   # 守方 WS 翻倍 -> 5+
		[4, 4, 4],    # 持平 -> 4+
		[4, 3, 3],    # 攻高 -> 3+
		[3, 4, 4],    # 攻略低 -> 4+
		[6, 3, 3],    # 恰好两倍 -> 3+
	]
	for c in cases:
		var got := CombatResolver.melee_hit_target(c[0], c[1])
		if got != c[2]:
			return "melee_hit(%d,%d)=%d want %d" % [c[0], c[1], got, c[2]]
	return ""

func test_ranged_hit_target() -> String:
	var cases := [
		[1, 6], [2, 5], [3, 4], [4, 3], [5, 2], [6, 2], [9, 2],
	]
	for c in cases:
		var got := CombatResolver.ranged_hit_target(c[0])
		if got != c[1]:
			return "ranged_hit(%d)=%d want %d" % [c[0], got, c[1]]
	return ""

func test_wound_target() -> String:
	var cases := [
		[3, 3, 4], [4, 3, 3], [5, 3, 2], [6, 3, 2], [7, 3, 2],
		[3, 4, 5], [3, 5, 6], [3, 6, 6], [2, 3, 5],
	]
	for c in cases:
		var got := CombatResolver.wound_target(c[0], c[1])
		if got != c[2]:
			return "wound(%d,%d)=%d want %d" % [c[0], c[1], got, c[2]]
	return ""

func test_armor_target() -> String:
	var cases := [
		[5, 0, 3, 5],   # 无修正
		[4, 0, 6, 7],   # S6 减 3 甲 -> 无效
		[5, 1, 3, 6],   # 破甲 1
		[7, 0, 3, 7],   # 本来无甲
	]
	for c in cases:
		var got := CombatResolver.armor_target(c[0], c[1], c[2])
		if got != c[3]:
			return "armor(%d,%d,%d)=%d want %d" % [c[0], c[1], c[2], got, c[3]]
	return ""

# ---------------- 攻击序列 ----------------

func test_resolve_attack_misses() -> String:
	var res := CombatResolver.resolve_attacks(
		_rng([1, 1, 1]), 4, 3, 3, 3, 7, 0, 0, "A", "B"
	)
	if res.hits != 0 or res.unsaved_wounds != 0:
		return "all 1s should miss everything"
	return ""

func test_resolve_attack_kills_unarmored() -> String:
	# 命中 4+（掷4），致伤 4+（掷4），无甲无守护 -> 1 个未豁免致伤
	var res := CombatResolver.resolve_attacks(
		_rng([4, 4]), 4, 3, 1, 3, 7, 0, 0, "A", "B"
	)
	if res.hits != 1 or res.wounds != 1 or res.unsaved_wounds != 1:
		return "hit/wound/unsaved = %d/%d/%d, want 1/1/1" % [res.hits, res.wounds, res.unsaved_wounds]
	return ""

func test_resolve_attack_armor_blocks() -> String:
	# 命中(6) 致伤(6) 护甲 4+ 掷 5 -> 保住
	var res := CombatResolver.resolve_attacks(
		_rng([6, 6, 5]), 2, 4, 1, 3, 4, 0, 0, "A", "B"
	)
	if res.unsaved_wounds != 0:
		return "armor 4+ with roll 5 should block, unsaved=%d" % res.unsaved_wounds
	return ""

func test_resolve_attack_ward_blocks() -> String:
	# 无甲但神器 4+：掷 4 保住
	var res := CombatResolver.resolve_attacks(
		_rng([6, 6, 4]), 2, 4, 1, 3, 7, 4, 0, "A", "B"
	)
	if res.unsaved_wounds != 0:
		return "ward 4+ with roll 4 should block, unsaved=%d" % res.unsaved_wounds
	return ""

func test_resolve_attack_ap_removes_armor() -> String:
	# 护甲 4+ 但被破甲 2 推到 6+：掷 5 -> 失败
	var res := CombatResolver.resolve_attacks(
		_rng([6, 6, 5]), 2, 3, 1, 3, 4, 0, 2, "A", "B"
	)
	if res.unsaved_wounds != 1:
		return "AP2 vs save 4+ should need 6+, roll 5 fails, unsaved=%d" % res.unsaved_wounds
	return ""

# ---------------- 心理学 ----------------

func test_leadership_pass_fail() -> String:
	var r := Psychology.leadership_test(8, 0, _rng([4, 4]))
	if not r.passed:
		return "Ld8 vs total 8 should pass"
	var r2 := Psychology.leadership_test(8, 0, _rng([6, 6]))
	if r2.passed:
		return "Ld8 vs total 12 should fail"
	var r3 := Psychology.leadership_test(8, -2, _rng([4, 4]))
	if r3.passed:
		return "Ld8-2 vs total 8 should fail"
	return ""

func test_snake_eyes_and_boxcars() -> String:
	var r := Psychology.leadership_test(2, 0, _rng([1, 1]))
	if not r.passed:
		return "double 1 on Ld2 should pass"
	var r2 := Psychology.leadership_test(10, 0, _rng([6, 6]))
	if r2.passed:
		return "double 6 on Ld10 should fail"
	return ""

func test_rng_determinism() -> String:
	var a := BattleRNG.new(12345)
	var b := BattleRNG.new(12345)
	for i in 100:
		if a.d6() != b.d6():
			return "same seed diverged at roll %d" % i
	return ""
