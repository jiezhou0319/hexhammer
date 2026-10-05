## 战斗解算：纯函数，无状态无副作用，输入属性和骰子源，输出 AttackResult。
## 数值口径参考 WHFB 简化版，边界值见单元测试。
class_name CombatResolver
extends RefCounted

## 近战命中需 X+（WS 对照）：
## 攻方 WS 不低于守方两倍 -> 3+；攻高 -> 3+；持平或略低 -> 4+；
## 守方 WS 不低于攻方两倍 -> 5+
static func melee_hit_target(atk_ws: int, def_ws: int) -> int:
	if atk_ws >= def_ws * 2:
		return 3
	if atk_ws > def_ws:
		return 3
	if def_ws >= atk_ws * 2:
		return 5
	return 4

## 射击命中需 X+（简化 BS 表：need = 7 - BS，封顶 2+/6+）
static func ranged_hit_target(bs: int) -> int:
	return clampi(7 - bs, 2, 6)

## 致伤需 X+（S vs T：平 4+，每差一级 ±1，封顶 2+/6+）
static func wound_target(strength: int, toughness: int) -> int:
	return clampi(4 - (strength - toughness), 2, 6)

## 护甲需 X+（含破甲与 S 减甲：S>3 时每点 S 再 -1 甲）。
## 返回 7 表示没有有效护甲。
static func armor_target(base_save: int, armor_piercing: int, strength: int) -> int:
	if base_save >= 7:
		return 7
	var t := base_save + armor_piercing + maxi(0, strength - 3)
	# 7+ 视为没有有效护甲
	return mini(t, 7)

## 解算一整轮攻击（近战或射击共用）。
## 命名参数调用：CombatResolver.resolve_attacks(hit_target=3, strength=4, ...)
static func resolve_attacks(
	rng: BattleRNG,
	hit_target: int,
	strength: int,
	attack_count: int,
	defender_toughness: int,
	defender_save: int,
	ward_save: int,
	armor_piercing: int = 0,
	attacker_label: String = "attacker",
	defender_label: String = "defender",
) -> AttackResult:
	var res := AttackResult.new()
	res.attack_count = attack_count
	res.hit_target = hit_target
	res.wound_target = wound_target(strength, defender_toughness)
	res.save_target = armor_target(defender_save, armor_piercing, strength)
	res.ward_target = ward_save
	res.log_lines.append(
		"%s: %d attack(s), hit on %d+" % [attacker_label, attack_count, hit_target]
	)

	res.hit_rolls = rng.d6s(attack_count)
	for roll in res.hit_rolls:
		if roll >= hit_target:
			res.hits += 1

	var wound_needed := res.hits
	var wound_rolls := rng.d6s(maxi(wound_needed, 0))
	for roll in wound_rolls:
		res.wound_rolls.append(roll)
		if roll >= res.wound_target:
			res.wounds += 1
	res.log_lines.append(
		"hits %d/%d (rolls %s), wound on %d+ vs T%d"
		% [res.hits, attack_count, str(res.hit_rolls), res.wound_target, defender_toughness]
	)

	if res.wounds > 0:
		res.log_lines.append(
			"wounds %d/%d (rolls %s), armor save %s"
			% [
				res.wounds,
				wound_needed,
				str(res.wound_rolls),
				("none" if res.save_target >= 7 else "%d+" % res.save_target),
			]
		)
	# 护甲：每记未豁免致伤掷一颗
	var after_armor := 0
	for i in res.wounds:
		if res.save_target >= 7:
			after_armor += 1
			continue
		var roll := rng.d6()
		res.save_rolls.append(roll)
		if roll < res.save_target:
			after_armor += 1
	# 神器守护：不可被破甲，固定需 ward_save+
	if res.ward_target > 0 and after_armor > 0:
		res.log_lines.append("ward save %d+" % res.ward_target)
		for i in after_armor:
			var roll := rng.d6()
			res.ward_rolls.append(roll)
			if roll < res.ward_target:
				res.unsaved_wounds += 1
	else:
		res.unsaved_wounds = after_armor
	res.log_lines.append("%s takes %d unsaved wound(s)" % [defender_label, res.unsaved_wounds])
	return res
