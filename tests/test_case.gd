## test_case.gd — 测试断言基类（M1a-T1 建立，M1a 全程沿用的测试基建）
## 测试文件约定（接口冻结——后续任务只加测试文件、不改 runner）：
##   1. 放 res://tests/ 下（子目录亦可）、文件名 test_*.gd；
##   2. extends "res://tests/test_case.gd"（路径继承，不依赖 class_name 注册时序，
##      先 --import 与否均可运行）；
##   3. 零参方法名以 test_ 开头 = 用例（按名排序执行）；可覆写 setup()（每用例前调用）；
##   4. 断言一律用 expect*（失败记录后继续跑完本用例）；禁止裸 assert（中止行为不可控）。
## 失败由 runner 统一以「文件:用例:原因」打印。
extends RefCounted

var _fails: Array[String] = []
var _checks := 0

## 每用例前由 runner 调用；测试类可覆写做公共准备
func setup() -> void:
	pass

func expect(cond: bool, msg: String) -> bool:
	_checks += 1
	if not cond:
		_fails.append(msg)
	return cond

func expect_eq(got, want, msg: String = "") -> bool:
	_checks += 1
	if got != want:
		var label := msg if msg != "" else "不等"
		_fails.append("%s：got=%s want=%s" % [label, str(got), str(want)])
		return false
	return true

func expect_almost_eq(got: float, want: float, eps: float = 1e-6, msg: String = "") -> bool:
	_checks += 1
	if absf(got - want) > eps:
		var label := msg if msg != "" else "浮点不等"
		# 注意：Godot 的 % 格式化不支持 %.9f 精度修饰符，一律 %s + str()
		_fails.append("%s：got=%s want=%s eps=%s" % [label, str(got), str(want), str(eps)])
		return false
	return true

func fail(msg: String) -> void:
	_checks += 1
	_fails.append(msg)

# ---- runner 协议（勿覆写、勿在测试中调用）----

func _begin_case() -> void:
	_fails.clear()

func _case_failures() -> Array[String]:
	return _fails

func _check_count() -> int:
	return _checks
