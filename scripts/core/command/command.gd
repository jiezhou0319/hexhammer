## 命令基类：玩家输入、AI、录像回放、网络同步都产出命令对象，
## 全部经 cmd.execute(engine) 落地。引擎本身不知道命令从哪来。
class_name Command
extends RefCounted

## 返回是否执行成功；失败原因会走 engine.log_error
func execute(_engine) -> bool:
	return false

func describe() -> String:
	return "Command"
