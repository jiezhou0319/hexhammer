## 结束当前阶段：射击/移动阶段 -> 下一阶段；
## 近战阶段结束时自动解算交战，然后轮到下一个势力。
class_name EndPhaseCommand
extends Command

func execute(engine) -> bool:
	return engine.apply_end_phase()
