## fixture_ok.gd — runner 变异自检：正常样本（必须**通过**）
## 故意放在 tests/ 之外（正常套件不发现它），由 tools/run_tests.gd 点名执行。
extends "res://tests/test_case.gd"

func test_normal_pass() -> void:
	expect_eq(1 + 1, 2, "正常断言应通过")
	expect_almost_eq(0.1 + 0.2, 0.3, 1e-9, "正常浮点断言应通过")

func test_second_case_also_zero_assert_free() -> void:
	expect(true, "第二条用例也有断言（S-2 逐用例判定）")
