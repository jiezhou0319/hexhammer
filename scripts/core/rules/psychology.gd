## 心理学测试：崩溃、恐慌、恐惧——战锤的灵魂。
## 2d6 <= Ld(+修正) 即通过；双 1 恰好通过、双 6 恰好失败由数值自然成立。
class_name Psychology
extends RefCounted

class TestResult:
	extends RefCounted
	var rolls: Array[int] = []
	var total: int = 0
	var target: int = 0
	var passed: bool = false

	func describe(label: String) -> String:
		return "%s test: Ld %d -> rolled %s = %d (%s)" % [
			label, target, str(rolls), total, ("PASSED" if passed else "FAILED")
		]

## 通用 Leadership 测试。mods 为正 = 更容易。
static func leadership_test(ld: int, mods: int, rng: BattleRNG) -> TestResult:
	var r := TestResult.new()
	r.rolls = rng.d6s(2)
	r.total = r.rolls[0] + r.rolls[1]
	r.target = ld + mods
	r.passed = r.total <= r.target
	return r

## 近战崩溃测试（输掉近战时，败方掷）。
## mods 常见来源：恐惧 -1、败方每差 1 点战斗分 -1（战斗分系统 TODO）。
static func break_test(ld: int, mods: int, rng: BattleRNG) -> TestResult:
	return leadership_test(ld, mods, rng)

## 恐惧测试：面对带 Fear 规则的单位时掷，失败则本回合近战按 WS1 处理。
static func fear_test(ld: int, rng: BattleRNG) -> TestResult:
	return leadership_test(ld, 0, rng)

## 恐慌测试（25% 伤亡、友军逃离穿队等触发；greybox 预留）。
static func panic_test(ld: int, rng: BattleRNG) -> TestResult:
	return leadership_test(ld, 0, rng)
