## 势力运行时状态。
class_name FactionState
extends RefCounted

var id: int = 0
var def: FactionDef
var unit_ids: Array[int] = []

## 热座混战：默认全部玩家操控；以后 AI 势力置 false
var is_player_controlled := true

func display_name() -> String:
	return def.display_name

func color() -> Color:
	return def.color
