## 回合状态机：多势力 IGO-UGO。
## 每个势力按序走完 phase 序列（默认 移动->射击->近战），
## 全势力走完一轮 = 一个 battle round，可以再开始。
##
## 魔法阶段：Phase.MAGIC 枚举已留位，实现风魔/施法/驱散时
## 把它插回 phases 数组即可，引擎不需要改结构。
class_name TurnMachine
extends RefCounted

enum Phase { MOVE, MAGIC, SHOOTING, COMBAT }

const PHASE_NAMES := {
	Phase.MOVE: "Movement",
	Phase.MAGIC: "Magic",
	Phase.SHOOTING: "Shooting",
	Phase.COMBAT: "Combat",
}

## 出场顺序里的势力 id
var faction_order: Array[int] = []
var faction_index := 0
var phase_index := 0
var round_no := 1

## 当前启用的阶段序列（魔法阶段暂未实现，故默认关闭）
var phases: Array[int] = [Phase.MOVE, Phase.SHOOTING, Phase.COMBAT]

func active_faction() -> int:
	return faction_order[faction_index]

func current_phase() -> int:
	return phases[phase_index]

func phase_name() -> String:
	return PHASE_NAMES[current_phase()]

func faction_name(state: BattleState) -> String:
	return state.factions[active_faction()].display_name()

## 推进一格：phase 尽 -> 下一个势力；势力尽 -> wrap 并 round+1。
## 返回 {faction_changed: bool, round_incremented: bool}
func advance() -> Dictionary:
	phase_index += 1
	if phase_index >= phases.size():
		phase_index = 0
		faction_index += 1
		var round_up := false
		if faction_index >= faction_order.size():
			faction_index = 0
			round_no += 1
			round_up = true
		return {"faction_changed": true, "round_incremented": round_up}
	return {"faction_changed": false, "round_incremented": false}

## 跳到下一个势力（用于势力全灭时跳过空回合）
func skip_faction() -> void:
	phase_index = 0
	faction_index += 1
	if faction_index >= faction_order.size():
		faction_index = 0
		round_no += 1
