## run_tests.gd — 零依赖测试门禁 v2（M1a-T1 建立；2026-10-10 按 Fable 审查 S-1/S-2/S-4 加固）
## 用法（门禁同命令——先 --import 再跑）：
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless --path hexhammer --import
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless --path hexhammer --script res://tools/run_tests.gd
## v2 行为（相对 v1 单进程口径的加固）：
##   - **逐文件子进程隔离**：每测试文件以独立引擎进程跑 tools/run_one.gd——
##     ① 用例内运行时 SCRIPT ERROR 从子进程输出被父进程扫描检出（S-1：GDScript
##     运行时错误只中止被调函数不冒泡，单进程内无法自检）；② 单文件崩溃/编译错
##     只毁该子进程，门禁仍能给出完整汇总；
##   - 零断言用例 / 有参 test_* / 空文件 = 失败（S-2，run_one 落实）；
##   - NaN/无穷/负容差浮点断言 = 失败（S-4，tests/test_case.gd 落实）；
##   - **门禁变异自检**：对 tools/runner_fixtures/ 的故意故障逐个验证会被拦截
##     （应拦截却通过、应通过却拦截 → 门禁失败）——加固本身持续有证据；
##   - 汇总口径不变：「N 文件 / M 用例 / F 失败」，任一失败 quit(1)、全绿 quit(0)。
## 失败打印「文件:用例:原因」（子进程原样转发，格式与 v1 一致）。
extends SceneTree

const TESTS_ROOT := "res://tests"
const RUN_ONE := "res://tools/run_one.gd"
const FIXTURES_ROOT := "res://tools/runner_fixtures"
## 子进程报告文件（run_one 写、本进程读——绕开 Windows 管道编码问题，见 _run_child）
const REPORT_PATH := "user://gate_child_report.txt"

## 变异自检期望：true = 该 fixture 必须被拦截（子进程判失败）；false = 必须通过。
## fixture 是**故意故障**样本（勿入 tests/——正常套件不发现它们，由本表点名跑）。
const FIXTURE_EXPECT := {
	"fixture_ok.gd": false,
	"fixture_runtime_error.gd": true,
	"fixture_zero_assert.gd": true,
	"fixture_nan.gd": true,
	"fixture_parameterized.gd": true,
}

func _init() -> void:
	var files: Array[String] = []
	_collect(TESTS_ROOT, files)
	files.sort()

	if files.is_empty():
		print("!!! %s 下未发现任何 test_*.gd（测试基类除外）" % TESTS_ROOT)
		quit(1)
		return

	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")

	var file_total := 0
	var case_total := 0
	var fail_total := 0
	for path in files:
		var result := _run_child(exe, proj, path)
		file_total += 1
		case_total += result["cases"]
		if not result["ok"]:
			fail_total += 1

	# ---- 门禁变异自检（S-1/S-2/S-4 加固的持续证据）----
	print("")
	print("---- runner 变异自检（fixtures 应拦尽拦、应放尽放）----")
	for fixture in FIXTURE_EXPECT:
		var want_blocked: bool = FIXTURE_EXPECT[fixture]
		var r := _run_child(exe, proj, FIXTURES_ROOT + "/" + fixture)
		var blocked: bool = not r["ok"]
		if blocked != want_blocked:
			print("FAIL 变异自检 %s : 期望%s，实际%s（runner 加固失效）" % [
				fixture, "被拦截" if want_blocked else "通过", "被拦截" if blocked else "通过"])
			fail_total += 1

	print("")
	print("=== 测试汇总：%d 文件 / %d 用例 / %d 失败 ===" % [file_total, case_total, fail_total])
	quit(1 if fail_total > 0 else 0)

## 跑一个子进程并判定：
##   - 结果行从子进程写的 UTF-8 报告文件（user://gate_child_report.txt）读回——
##     Windows 下 OS.execute 捕获的 stdout 会把非 ASCII 解码成乱码，中文 FAIL/
##     汇总行不可靠（解析锚 = 文件末行 ASCII「SUMMARY cases=N fails=F」）；
##   - SCRIPT ERROR 为 ASCII 标记，stdout 直扫（S-1：运行时错误只进引擎日志）；
##   - 判定：exit=0 且报告含 SUMMARY 行且 stdout 无 SCRIPT ERROR = 通过。
func _run_child(exe: String, proj: String, script_path: String) -> Dictionary:
	var args := PackedStringArray([
		"--headless", "--path", proj, "--script", RUN_ONE, "--", script_path])
	var output: Array = []
	var code := OS.execute(exe, args, output, true, true)
	var stdout_text := "\n".join(PackedStringArray(output))

	var report_lines: Array[String] = []
	var cases := 0
	var has_summary := false
	var f := FileAccess.open(REPORT_PATH, FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var l := f.get_line()
			if l.begins_with("SUMMARY cases="):
				has_summary = true
				cases = int(l.get_slice("=", 1).get_slice(" ", 0))
				continue  # 机器标记行不转发
			if l != "":
				report_lines.append(l)
		f.close()
	for l in report_lines:
		print(l)

	var ok := code == 0 and has_summary and not stdout_text.contains("SCRIPT ERROR")
	if code != 0 and not has_summary:
		print("FAIL %s : 子进程异常退出（code=%d，无汇总行——崩溃/加载失败）" % [script_path.get_file(), code])
	elif stdout_text.contains("SCRIPT ERROR"):
		print("FAIL %s : 输出含 SCRIPT ERROR（用例内运行时错误，S-1 拦截）" % script_path.get_file())
	return {"ok": ok, "cases": cases}

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
		elif entry.begins_with("test_") and entry.ends_with(".gd") and entry != "test_case.gd":
			out.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
