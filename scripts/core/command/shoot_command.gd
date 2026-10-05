## 射击：射击阶段，对射程内目标解算命中/致伤/豁免。
## 视线遮挡（森林/丘陵）TODO；误伤友军不做。
class_name ShootCommand
extends Command

var unit_id: int
var target_id: int

func _init(p_unit_id: int, p_target_id: int) -> void:
	unit_id = p_unit_id
	target_id = p_target_id

func execute(engine) -> bool:
	var err: String = engine.apply_shot(unit_id, target_id)
	engine.last_error = err
	return err.is_empty()

func describe() -> String:
	return "Shoot #%d -> #%d" % [unit_id, target_id]
