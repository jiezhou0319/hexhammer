## 战场上的一个单位实例：Profile 数据 + 当前状态（位置、血量、回合旗标）。
## 纯数据，不动场景树；恢复/存档序列化它即可。
class_name UnitState
extends RefCounted

var id: int = 0
var profile: UnitProfile
var faction_id: int = 0
var pos: Vector2i = Vector2i.ZERO

var wounds_left: int = 1

## 每回合旗标（回合开始统一清）
var moved_this_turn := false
var charged_this_turn := false
var fired_this_turn := false
var fear_failed_this_turn := false
var engaged_with: Array[int] = []   # 交战中对手 unit id

## 状态：溃逃中
var fleeing := false

func alive() -> bool:
	return wounds_left > 0

func display_name() -> String:
	return profile.display_name

func is_hero() -> bool:
	return profile.role == UnitProfile.Role.HERO

func has_rule(rule_id: StringName) -> bool:
	for r in profile.special_rules:
		if r.rule_id == rule_id:
			return true
	return false

## 恐惧测试失败的本回合按 WS1 挥砍
func effective_ws() -> int:
	return 1 if fear_failed_this_turn else profile.weapon_skill

## 狂暴 +1 攻击（仅近战时由 attack_count 使用）
func attack_count() -> int:
	var n := profile.attacks
	if profile.melee_weapon != null:
		n += profile.melee_weapon.attacks_bonus
	if has_rule(&"frenzy"):
		n += 1
	return maxi(n, 1)

func melee_strength() -> int:
	var s := profile.strength
	if profile.melee_weapon != null:
		var w := profile.melee_weapon
		if w.strength_override > 0:
			s = w.strength_override
		s += w.strength_bonus
	return s

func melee_ap() -> int:
	return profile.melee_weapon.armor_piercing if profile.melee_weapon != null else 0

func shot_strength() -> int:
	var w := profile.ranged_weapon
	if w == null:
		return 0
	return w.strength_override if w.strength_override > 0 else profile.strength

func can_shoot() -> bool:
	return profile.ranged_weapon != null and profile.ranged_weapon.range_hex > 0
