## 冲锋：移动阶段声明，距离上限 = 2xM，成功后与目标贴身进入交战。
## 冲锋响应（stand & shoot / flee / hold）目前默认 hold，TODO。
class_name ChargeCommand
extends Command

var unit_id: int
var target_id: int

func _init(p_unit_id: int, p_target_id: int) -> void:
	unit_id = p_unit_id
	target_id = p_target_id

func execute(engine) -> bool:
	var err: String = engine.apply_charge(unit_id, target_id)
	engine.last_error = err
	return err.is_empty()

func describe() -> String:
	return "Charge #%d -> #%d" % [unit_id, target_id]
