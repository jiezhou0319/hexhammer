## run_tests.gd — 零依赖测试门禁 v3（M1a-T1 建立；v2 按 Fable 审查 S-1/S-2/S-4 加固；
##   v3 按 runner 鲁棒性外审 N-1..N-4 加固，见 docs/retro/M1a.md 补记二）
## 用法（门禁同命令——先 --import 再跑）：
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless --path hexhammer --import
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless --path hexhammer --script res://tools/run_tests.gd
## v2 行为（继承）：逐文件子进程隔离（SCRIPT ERROR 从子进程输出检出，S-1）；
##   零断言/有参 test_*/空文件 = 失败（S-2）；NaN/无穷/负容差断言 = 失败（S-4）；
##   门禁变异自检（应拦尽拦、应放尽放）。
## v3 行为（相对 v2 的加固）：
##   - **报告文件按子进程隔离**（N-2）：每个子进程写唯一报告
##     （父 PID + 序号），执行前必删、读后即删——子进程崩溃/被杀都不可能读到
##     上一个子进程的陈旧报告；两份门禁并行跑也不再互踩同一文件；
##   - **无报告 = 失败**（N-2）：不再用「退出码≠0 且无 SUMMARY」推断崩溃——
##     有陈旧 SUMMARY 也不算数；崩溃文件名必出现在 FAIL 行；
##   - **子进程超时**（N-3）：OS.execute_with_pipe 非阻塞 + 轮询，默认 20s，
##     超时 OS.kill 并判失败（FAIL 行含文件名与「超时」）——死循环用例卡死
##     门禁不再可能；子进程 stdout/stderr 分管道累计后按 UTF-8 解码；
##   - **汇总口径回到用例级**（N-4）：总「失败」= Σ 各文件 SUMMARY fails；
##     文件级失败（崩溃/超时/SCRIPT ERROR/加载失败）在 SUMMARY fails=0 时
##     至少计 1——「N 文件 / M 用例 / F 失败」的 F 与 v1 用例数口径一致；
##   - **SCRIPT ERROR 正文转发**（N-4）：该行及其后一行（at: 定位）随判定打印，
##     排错不必手动重跑 run_one；
##   - **变异自检钉死原因与用例数**（N-1）：fixture 期望 = {拦截, 原因标记,
##     用例数, 超时档}——样本被删/改名/语法坏造成的「加载失败式假拦截」
##     （原因标记缺失 / 用例数不符）一律判自检失败；
##   - 新增 crash / hang 故意故障样本 = N-2/N-3 的回归锚（crash 用 OS.kill 自杀
##     ——确定性秒死、无崩溃转储副作用；hang 吃 3s 短超时档，门禁只多等 3s）。
## 失败打印「文件:用例:原因」（子进程报告原样转发，格式与 v1/v2 一致）。
extends SceneTree

const TESTS_ROOT := "res://tests"
const RUN_ONE := "res://tools/run_one.gd"
const FIXTURES_ROOT := "res://tools/runner_fixtures"
## 子进程单文件超时（N-3）：含引擎启动；正常单文件 ≤ 数秒，20s 为宽松上限
const CHILD_TIMEOUT_MS := 20000
## 轮询间隔（秒）：进程存活/超时/管道排空的最小检查粒度
const POLL_SEC := 0.025

## 变异自检期望表（N-1 钉死）：
##   blocked = 该 fixture 必须被拦截（子进程判失败）；marker = 拦截证据必须包含
##   的原因标记（""= 不检查）；cases = SUMMARY 用例数（-1 = 不检查——崩溃/超时
##   无 SUMMARY）；timeout_ms = 0 用默认超时档，否则用指定档（hang 样本专用短档）。
## fixture 是**故意故障**样本（勿入 tests/——正常套件不发现它们，由本表点名跑）。
const FIXTURE_EXPECT := {
	"fixture_ok.gd": {"blocked": false, "marker": "", "cases": 2, "timeout_ms": 0},
	"fixture_runtime_error.gd": {"blocked": true, "marker": "SCRIPT ERROR", "cases": 1, "timeout_ms": 0},
	"fixture_zero_assert.gd": {"blocked": true, "marker": "S-2", "cases": 2, "timeout_ms": 0},
	"fixture_nan.gd": {"blocked": true, "marker": "S-4", "cases": 2, "timeout_ms": 0},
	"fixture_parameterized.gd": {"blocked": true, "marker": "S-2", "cases": 0, "timeout_ms": 0},
	"fixture_crash.gd": {"blocked": true, "marker": "未写报告", "cases": -1, "timeout_ms": 0},
	"fixture_hang.gd": {"blocked": true, "marker": "超时", "cases": -1, "timeout_ms": 3000},
}

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
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
	var seq := 0
	for path in files:
		seq += 1
		var result := await _run_child(exe, proj, path, 0, seq)
		file_total += 1
		case_total += int(result["cases"])
		var fails := int(result["fails"])
		if not result["ok"] and fails == 0:
			fails = 1  # 文件级失败（崩溃/超时/SCRIPT ERROR）至少计 1（N-4 口径）
		fail_total += fails

	# ---- 门禁变异自检（S-1/S-2/S-4 + N-1..N-3 加固的持续证据）----
	print("")
	print("---- runner 变异自检（fixtures 应拦尽拦、应放尽放；原因/用例数钉死，N-1）----")
	for fixture in FIXTURE_EXPECT:
		var want: Dictionary = FIXTURE_EXPECT[fixture]
		seq += 1
		var r := await _run_child(exe, proj, FIXTURES_ROOT + "/" + fixture,
			int(want["timeout_ms"]), seq)
		var blocked: bool = not r["ok"]
		var problems: Array[String] = []
		if blocked != bool(want["blocked"]):
			problems.append("期望%s，实际%s" % [
				"被拦截" if bool(want["blocked"]) else "通过",
				"被拦截" if blocked else "通过"])
		var marker := String(want["marker"])
		if marker != "" and not String(r["evidence"]).contains(marker):
			problems.append("拦截证据缺原因标记「%s」（样本被删/改名/坏掉 = 加载失败式假拦截？）" % marker)
		var want_cases := int(want["cases"])
		if want_cases >= 0 and int(r["cases"]) != want_cases:
			problems.append("用例数 %d ≠ 期望 %d" % [int(r["cases"]), want_cases])
		for p in problems:
			print("FAIL 变异自检 %s : %s（runner 加固失效）" % [fixture, p])
			fail_total += 1

	print("")
	print("=== 测试汇总：%d 文件 / %d 用例 / %d 失败 ===" % [file_total, case_total, fail_total])
	quit(1 if fail_total > 0 else 0)

## 跑一个子进程并判定（v3）：
##   - 报告文件按子进程唯一（父 PID + seq；N-2），执行前必删、读后即删；
##   - execute_with_pipe 非阻塞起进程（4.7 返回 {stdio, stderr, pid}），轮询存活
##     与超时（N-3），stdout/stderr 分管道累计、进程结束后按 UTF-8 一次解码——
##     SCRIPT ERROR（ASCII 标记，S-1）与 at: 定位行照原文转发（N-4）；
##   - 判定：有报告 SUMMARY 且退出码 0 且无 SCRIPT ERROR 且未超时 = 通过；
##     无报告必出 FAIL 行（崩溃文件名不缺席，N-2）。
func _run_child(exe: String, proj: String, script_path: String,
		timeout_ms := 0, seq := 1) -> Dictionary:
	var effective_timeout := timeout_ms if timeout_ms > 0 else CHILD_TIMEOUT_MS
	var file_name := script_path.get_file()
	var report := "user://gate_child_report_%d_%d.txt" % [OS.get_process_id(), seq]
	var report_global := ProjectSettings.globalize_path(report)
	DirAccess.remove_absolute(report_global)  # 执行前必删（读后也删，双保险）

	var args := PackedStringArray([
		"--headless", "--path", proj, "--script", RUN_ONE, "--", script_path, report])
	var proc: Variant = OS.execute_with_pipe(exe, args, false)
	var pid: int = proc["pid"]
	var stdio: FileAccess = proc["stdio"]
	var stderr_pipe: FileAccess = proc["stderr"]

	var deadline := Time.get_ticks_msec() + effective_timeout
	var timed_out := false
	var out_buf := PackedByteArray()
	var err_buf := PackedByteArray()
	await create_timer(0.05).timeout  # 首查前稍候：避开 spawn 瞬间的存活误判
	while OS.is_process_running(pid):
		_drain(stdio, out_buf)
		_drain(stderr_pipe, err_buf)
		if Time.get_ticks_msec() > deadline:
			timed_out = true
			OS.kill(pid)
			break
		await create_timer(POLL_SEC).timeout
	_drain(stdio, out_buf)
	_drain(stderr_pipe, err_buf)
	stdio.close()
	stderr_pipe.close()
	var exit_code := OS.get_process_exit_code(pid)

	var out_text := out_buf.get_string_from_utf8()
	var err_text := err_buf.get_string_from_utf8()
	var has_script_error := out_text.contains("SCRIPT ERROR") or err_text.contains("SCRIPT ERROR")

	var report_lines: Array[String] = []
	var cases := 0
	var fails := 0
	var has_summary := false
	var f := FileAccess.open(report, FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var l := f.get_line()
			if l.begins_with("SUMMARY cases="):
				has_summary = true
				cases = int(l.get_slice("=", 1).get_slice(" ", 0))
				fails = int(l.get_slice("fails=", 1))
				continue  # 机器标记行不转发
			if l != "":
				report_lines.append(l)
		f.close()
	for l in report_lines:
		print(l)
	DirAccess.remove_absolute(report_global)  # 读后即删（N-2）

	# SCRIPT ERROR 正文转发（N-4）：该行 + 其后一行（at: 定位）；两管道去重
	var seen := {}
	for src in [out_text, err_text]:
		var ls := String(src).split("\n")
		for i in ls.size():
			var line := String(ls[i])
			if line.contains("SCRIPT ERROR") and not seen.has(line):
				seen[line] = true
				print("  | " + line)
				if i + 1 < ls.size() and String(ls[i + 1]).strip_edges() != "":
					print("  | " + String(ls[i + 1]))

	var ok := has_summary and exit_code == 0 and not has_script_error and not timed_out
	var synth := ""
	if timed_out:
		synth = "FAIL %s : 子进程超时被杀（>%dms，N-3 拦截——死循环/卡死用例不得挂死门禁）" \
			% [file_name, effective_timeout]
	elif not has_summary:
		synth = "FAIL %s : 子进程未写报告（exit=%d）——崩溃/加载失败（N-2 拦截：陈旧报告不顶数）" \
			% [file_name, exit_code]
	elif has_script_error:
		synth = "FAIL %s : 输出含 SCRIPT ERROR（用例内运行时错误，S-1 拦截）" % file_name
	elif exit_code != 0 and fails == 0:
		# fails>0 的文件退出码 1 是 run_one 的正常语义；「自称全绿却退出码非 0」才是怪状态
		synth = "FAIL %s : 退出码 %d 但有汇总且 0 失败（须排查）" % [file_name, exit_code]
	if synth != "":
		print(synth)

	var evidence := "\n".join(report_lines)
	if synth != "":
		evidence += "\n" + synth
	if has_script_error:
		evidence += "\nSCRIPT ERROR"  # S-1 样本的原因标记在子输出里
	return {"ok": ok, "cases": cases, "fails": fails, "evidence": evidence}

## 非阻塞管道排空：把当前已到达的字节追加进缓冲（不阻塞、不假设分块边界）
func _drain(f: FileAccess, buf: PackedByteArray) -> void:
	if f == null:
		return
	var chunk := f.get_buffer(65536)
	if chunk.size() > 0:
		buf.append_array(chunk)

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
