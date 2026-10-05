## 移动：移动阶段，把单位走到移动范围内的可达空格。
## （行军/转向不占机制：六边形上转向无意义，行军 TODO）
class_name MoveCommand
extends Command

var unit_id: int
var dest: Vector2i

func _init(p_unit_id: int, p_dest: Vector2i) -> void:
	unit_id = p_unit_id
	dest = p_dest

func execute(engine) -> bool:
	var err: String = engine.apply_move(unit_id, dest)
	engine.last_error = err
	return err.is_empty()

func describe() -> String:
	return "Move #%d -> (%d,%d)" % [unit_id, dest.x, dest.y]
