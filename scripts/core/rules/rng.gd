## 战斗骰子源。种子可注入 → 同种子同战局 → 支持回放与测试。
## 所有规则代码只准从这里拿随机数，禁止散落 randi()。
class_name BattleRNG
extends RefCounted

var seed_value: int
var rolls_made: int = 0

var _rng := RandomNumberGenerator.new()

func _init(p_seed: int = 0) -> void:
	if p_seed == 0:
		p_seed = randi()
	seed_value = p_seed
	_rng.seed = p_seed

func d6() -> int:
	rolls_made += 1
	return _rng.randi_range(1, 6)

## 掷 n 颗 d6，返回保持掷出顺序的数组
func d6s(n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(d6())
	return out

func d6_total(n: int) -> int:
	var t := 0
	for i in n:
		t += d6()
	return t
