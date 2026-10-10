## fixture_zero_assert.gd — runner 变异自检：零断言用例（必须被**拦截**，S-2）
## 复现 Fable 注入：第二条用例零断言——v1 的 WARN 只对文件内第一条零断言用例生效
##（_checks 跨用例累计）；v2 逐用例重置后零断言 = 失败。
extends "res://tests/test_case.gd"

func test_with_assert() -> void:
	expect_eq(2, 2, "有用例的断言")

func test_without_any_assert() -> void:
	var sum := 0
	for i in 10:
		sum += i
	# 算了一堆，一条断言都没有——测试空转，必须判失败
