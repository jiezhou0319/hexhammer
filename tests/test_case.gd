## test_case.gd — 测试断言基类（M1a-T1 建立；2026-10-10 按 Fable 审查 S-2/S-4 加固）
## 测试文件约定（接口冻结口径随加固升 v2——runner 与本文件同步改，测试文件不受影响）：
##   1. 放 res://tests/ 下（子目录亦可）、文件名 test_*.gd；
##   2. extends "res://tests/test_case.gd"（路径继承，不依赖 class_name 注册时序，
##      先 --import 与否均可运行）；
##   3. **零参**方法名以 test_ 开头 = 用例（按名排序执行；有参 test_* = 隐形删测，
##      runner 直接判失败——S-2）；可覆写 setup()（每用例前调用）；
##   4. 断言一律用 expect*（失败记录后继续跑完本用例）；禁止裸 assert（中止行为不可控）；
##   5. 每用例**至少一条断言**（零断言 = 失败——S-2，防测试空转恒绿）；
##   6. 浮点断言拒绝 NaN/无穷与负容差（S-4——浮点 oracle 不得放行非法值）。
## 失败由 runner 统一以「文件:用例:原因」打印；用例内 GDScript 运行时错误由
## 父进程 runner（tools/run_tests.gd 子进程隔离）从输出检出（S-1——本进程内
## 运行时错误只中止被调函数、不冒泡，无法自检）。
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
	# S-4（2026-10-10）：NaN 参与比较恒假 → absf(got-want) > eps 永不触发、恒"通过"；
	# 无穷/负容差同样拒绝——浮点断言先验证实参合法再比误差
	if not is_finite(got) or not is_finite(want) or not is_finite(eps) or eps < 0.0:
		var bad := msg if msg != "" else "非法浮点断言"
		_fails.append("%s：got=%s want=%s eps=%s（须为有限数、容差非负——S-4）"
			% [bad, str(got), str(want), str(eps)])
		return false
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
	_checks = 0  # S-2（2026-10-10）：断言计数随用例重置——零断言判定逐用例有效

func _case_failures() -> Array[String]:
	return _fails

func _check_count() -> int:
	return _checks
