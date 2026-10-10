## fixture_hang.gd — runner 变异自检：用例死循环（必须被**超时拦截**，N-3）
## 复现 N-3 注入：v2 的 OS.execute 阻塞且无超时，本样本会把门禁永久挂起；
## v3 父进程轮询超时 kill 并判失败（FAIL 行含文件名与「超时」），本样本即回归锚。
## 自检表给本样本 3s 短超时档——门禁总耗时只多等 3s，不吃 20s 默认档。
extends "res://tests/test_case.gd"

func test_infinite_loop() -> void:
	expect(true, "先有一条断言，随后进入死循环（引擎冻结，等待父进程超时处决）")
	while true:
		pass
	expect(false, "不可达：若被执行说明死循环退出了")
