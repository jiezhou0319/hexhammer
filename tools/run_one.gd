## run_one.gd — 单文件测试 runner（2026-10-10 S-1/S-2 加固新增）
## 用法（由 tools/run_tests.gd 以子进程逐文件调用，也可手动跑单文件）：
##   <godot> --headless --path <proj> --script res://tools/run_one.gd -- res://tests/test_xxx.gd
## 行为（相对旧单进程 runner 的加固）：
##   - 零断言用例 = **失败**（S-2：断言计数随用例重置后逐用例判定）；
##   - 有参 test_* 方法 = **失败**（S-2：拼错签名 = 隐形删测，不得静默跳过）；
##   - 文件无任何 test_* 方法 = 失败；
##   - 用例内 GDScript 运行时错误（SCRIPT ERROR）本进程**无法自检**（只中止被调
##     函数、不冒泡——S-1），由父进程扫描本进程 stdout 检出（ASCII 标记不受
##     Windows 管道编码影响）。
## 输出双通道（Windows OS.execute 捕获 stdout 会把非 ASCII 解码成乱码——父进程
##   不能扫中文标记）：
##   - stdout：人类可读 FAIL 行 + 「=== 单文件汇总 ===」（手动跑时看）；
##   - user://gate_child_report.txt：UTF-8 报告文件（父进程读回打印与解析），
##     末行 ASCII 机器标记 SUMMARY cases=N fails=F（父进程的解析锚）。
## 退出码：任一失败 1，全绿 0。
extends SceneTree

const REPORT_PATH := "user://gate_child_report.txt"

func _init() -> void:
	var user_args := OS.get_cmdline_user_args()
	var path := user_args[0] if user_args.size() > 0 else ""
	if path == "" or not path.begins_with("res://") or not path.ends_with(".gd"):
		print("FAIL run_one : 需要 res:// 测试文件参数（-- res://tests/test_x.gd）")
		quit(1)
		return
	var file_name := path.get_file()
	var lines: Array[String] = []

	var script: GDScript = load(path)
	if script == null:
		lines.append("FAIL %s : 脚本加载失败（编译错误？）" % file_name)
		_finish(lines, 0, 1)
		return
	var suite = script.new()
	if suite == null or not suite.has_method("_begin_case"):
		lines.append("FAIL %s : 未继承 res://tests/test_case.gd（缺 runner 协议）" % file_name)
		_finish(lines, 0, 1)
		return

	var methods: Array[String] = []
	var bad_param: Array[String] = []
	for m in suite.get_method_list():
		var mname := String(m["name"])
		if mname.begins_with("test_"):
			if (m["args"] as Array).is_empty():
				methods.append(mname)
			else:
				bad_param.append(mname)
	methods.sort()
	bad_param.sort()

	var case_total := 0
	var fail_total := 0
	for mname in bad_param:
		lines.append("FAIL %s:%s : 有参 test_* 方法（隐形删测防护，S-2）" % [file_name, mname])
		fail_total += 1
	for method in methods:
		case_total += 1
		suite._begin_case()
		suite.setup()
		suite.call(method)
		if suite._check_count() == 0:
			lines.append("FAIL %s:%s : 用例没有任何断言（零断言 = 失败，S-2）" % [file_name, method])
			fail_total += 1
			continue
		var fails: Array[String] = suite._case_failures()
		if not fails.is_empty():
			for reason in fails:
				lines.append("FAIL %s:%s : %s" % [file_name, method, reason])
			fail_total += 1
	if methods.is_empty() and bad_param.is_empty():
		lines.append("FAIL %s : 未发现任何 test_* 方法" % file_name)
		fail_total += 1

	_finish(lines, case_total, fail_total)

## stdout 人类可读 + UTF-8 报告文件（ASCII 机器标记行）+ 退出码
func _finish(lines: Array[String], cases: int, fails: int) -> void:
	var summary := "=== 单文件汇总：%d 用例 / %d 失败 ===" % [cases, fails]
	for l in lines:
		print(l)
	print(summary)
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		for l in lines:
			f.store_line(l)
		f.store_line(summary)
		f.store_line("SUMMARY cases=%d fails=%d" % [cases, fails])
		f.close()
	quit(1 if fails > 0 else 0)
