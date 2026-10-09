## run_tests.gd — 零依赖测试 runner（M1a-T1 建立，M1a 全程沿用；模式参照 tools/combat_sim.gd）
## 用法（门禁同命令——先 --import 再跑）：
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless --path hexhammer --import
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless --path hexhammer --script res://tools/run_tests.gd
## 行为：
##   - 自动发现 res://tests/ 下（含子目录）全部 test_*.gd，按路径排序稳定执行
##     （唯一例外：tests/test_case.gd 是断言基类，显式跳过）；
##   - 每文件 new() 后反射执行全部零参 test_* 方法（可选 setup() 先行）；
##   - 失败打印「文件:用例:原因」；末尾汇总；任一失败 quit(1)、全绿 quit(0)。
##   - 接口约定见 tests/test_case.gd 头注；后续任务只加测试文件、不改本文件。
extends SceneTree

const TESTS_ROOT := "res://tests"
const BASE_CASE_NAME := "test_case.gd"  # 断言基类（非测试文件，跳过）

func _init() -> void:
	var files: Array[String] = []
	_collect(TESTS_ROOT, files)
	files.sort()

	if files.is_empty():
		print("!!! %s 下未发现任何 test_*.gd（测试基类除外）" % TESTS_ROOT)
		quit(1)
		return

	var file_total := 0
	var case_total := 0
	var fail_total := 0

	for path in files:
		var file_name := path.trim_prefix(TESTS_ROOT + "/")
		var script: GDScript = load(path)
		if script == null:
			print("FAIL %s : 脚本加载失败（编译错误？）" % file_name)
			fail_total += 1
			continue
		var suite = script.new()
		if suite == null or not suite.has_method("_begin_case"):
			print("FAIL %s : 未继承 res://tests/test_case.gd（缺 runner 协议）" % file_name)
			fail_total += 1
			continue

		var methods: Array[String] = []
		for m in suite.get_method_list():
			if String(m["name"]).begins_with("test_") and (m["args"] as Array).is_empty():
				methods.append(m["name"])
		methods.sort()
		if methods.is_empty():
			print("WARN %s : 未发现任何零参 test_* 用例" % file_name)
			continue

		file_total += 1
		for method in methods:
			case_total += 1
			suite._begin_case()
			suite.setup()
			suite.call(method)
			var fails: Array[String] = suite._case_failures()
			if fails.is_empty():
				if suite._check_count() == 0:
					print("WARN %s:%s : 用例没有任何断言" % [file_name, method])
				continue
			for reason in fails:
				print("FAIL %s:%s : %s" % [file_name, method, reason])
			fail_total += 1

	print("")
	print("=== 测试汇总：%d 文件 / %d 用例 / %d 失败 ===" % [file_total, case_total, fail_total])
	quit(1 if fail_total > 0 else 0)

## 递归收集 test_*.gd（跳过隐藏目录与断言基类）
func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect(dir_path.path_join(entry), out)
		elif entry.begins_with("test_") and entry.ends_with(".gd") and entry != BASE_CASE_NAME:
			out.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
