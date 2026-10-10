## fixture_nan.gd — runner 变异自检：NaN 浮点断言（必须被**拦截**，S-4）
## 复现 Fable 注入：expect_almost_eq(NAN, 1.0) 在 v1 的 absf(got-want) > eps 比较下
## 恒"通过"（NaN 参与比较恒假）；v2 先验证有限数再比误差。
extends "res://tests/test_case.gd"

func test_nan_passes_v1() -> void:
	expect_almost_eq(NAN, 1.0, 0.001, "NaN 不得被当作相等")

func test_negative_eps_rejected() -> void:
	expect_almost_eq(1.0, 1.0, -0.5, "负容差不得被接受")
