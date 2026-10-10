## fixture_runtime_error.gd — runner 变异自检：断言后运行时错误（必须被**拦截**，S-1）
## 复现 Fable 注入：一次成功断言后访问不存在的字典键——运行时错误中止本用例，
## v1 单进程 runner 会把它计为"通过"；v2 由父进程从子进程输出检出 SCRIPT ERROR。
extends "res://tests/test_case.gd"

func test_runtime_error_after_assertion() -> void:
	expect(true, "先来一条会通过的断言")
	var d := {}
	var _x = d.missing_key  # 运行时错误：后续断言永远到不了
	expect(false, "这行不可达——若被执行说明运行时错误未发生")
