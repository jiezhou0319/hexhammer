## fixture_parameterized.gd — runner 变异自检：有参 test_* 方法（必须被**拦截**，S-2）
## 复现 Fable 注入：拼错签名（误带参数）的 test_* 在 v1 被静默跳过 = 隐形删测；
## v2 直接判失败。
extends "res://tests/test_case.gd"

func test_with_wrong_signature(a: int) -> void:
	expect_eq(a, a, "这条永远不会被执行（runner 不调用有参用例）")
