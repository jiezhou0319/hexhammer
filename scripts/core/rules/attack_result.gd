## 一次攻击序列（A 次挥砍）的结构化结果。
## 表现层拿 log_lines 直接显示骰子过程——战锤玩家要看每一颗骰。
class_name AttackResult
extends RefCounted

var attack_count: int = 0
var hits: int = 0
var wounds: int = 0
var unsaved_wounds: int = 0

var hit_target: int = 0
var hit_rolls: Array[int] = []
var wound_target: int = 0
var wound_rolls: Array[int] = []
var save_target: int = 0     # 7+ = 无有效护甲
var save_rolls: Array[int] = []
var ward_target: int = 0     # 0 = 无神器
var ward_rolls: Array[int] = []

var log_lines: Array[String] = []

func summary() -> String:
	return "%d attacks -> %d hits -> %d wounds -> %d unsaved" % [
		attack_count, hits, wounds, unsaved_wounds
	]
