## fixture_crash.gd — runner 变异自检：子进程在写报告前死亡（必须被**拦截**，N-2）
## 复现 N-2 注入：子进程于 _finish 落盘前死亡——v2 父进程不清理共享报告文件，
## 会读到上一个子进程的陈旧 SUMMARY，把陈旧 FAIL 行当本文件结果、崩溃文件名
## 缺席；v3 报告按子进程唯一 + 「无报告 = 拦截」，本样本即回归锚。
## 用 OS.kill 自杀而非 OS.crash：确定性秒死，无崩溃转储/WER 弹窗副作用。
extends "res://tests/test_case.gd"

func test_die_before_report() -> void:
	expect(true, "这条断言落账后进程即消失——报告文件永远不会写出")
	OS.kill(OS.get_process_id())
	expect(false, "不可达：若被执行说明自杀未遂")
