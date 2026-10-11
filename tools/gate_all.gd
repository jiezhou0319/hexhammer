## gate_all.gd — 统一门禁入口（准备批 GATE-ENTRY，2026-10-11；04 §M1a+ 准备批登记）
## 单命令按序执行全链，退出码正确聚合（任一步失败 → exit 1；图形检查失败不得被
## 单测成功覆盖）；图形环境缺失/未请求时探针报「未验证」，不冒充全绿。
## 用法（与门禁同款二进制；自身建议 --headless 跑前四步）：
##   "E:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . \
##     --script res://tools/gate_all.gd
## 带渲染探针（真渲染子进程会短暂弹窗；无桌面环境勿传）：
##   ... --script res://tools/gate_all.gd -- --with-probe
## 步骤（顺序固定——前步失败不阻断后续，汇总逐项列退出码）：
##   1. 干净工作树导入（--import）
##   2. 单测 + 故障自检（tools/run_tests.gd，v3.1）
##   3. 场景检查 ×3（picking / highlight / camera，各自独立子进程）
##   4. 渲染探针（tools/render_probe.gd，非 headless 真渲染；渲染器标识取运行时值）
## 三态口径（沿 runner v3.1）：正常输出转发 / 故意故障 FAIL 行（变异自检预期）/
## 非预期引擎 ERROR = 异常须排查。汇总写明引擎版本、各步退出码、探针实际渲染器。
extends SceneTree

const PROBE_SCRIPT := "res://tools/render_probe.gd"
## 头四步（headless 子进程，顺序执行）
const STEPS_HEADLESS: Array = [
	["1/5 干净导入", ["--headless", "--path", ".", "--import"]],
	["2/5 单测+故障自检（runner v3.1）", ["--headless", "--path", ".", "--script", "res://tools/run_tests.gd"]],
	["3/5 场景检查·拾取", ["--headless", "--path", ".", "--script", "res://tools/picking_scene_check.gd"]],
	["4/5 场景检查·高亮", ["--headless", "--path", ".", "--script", "res://tools/highlight_scene_check.gd"]],
	["5/5 场景检查·相机", ["--headless", "--path", ".", "--script", "res://tools/camera_scene_check.gd"]],
]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var exe := OS.get_executable_path()
	var results: Array = []  # {label, code}
	for step in STEPS_HEADLESS:
		results.append(await _run_step(exe, step[0], step[1], false))
	# 渲染探针：显式请求（-- --with-probe）或本进程非 headless 时才跑——
	# 否则报「未验证」（真渲染需要桌面环境；不得静默跳过也不得当全绿）
	var want_probe := "--with-probe" in OS.get_cmdline_user_args() \
		or DisplayServer.get_name() != "headless"
	var probe_state := "未验证（未请求——传 -- --with-probe 或在桌面环境跑）"
	if want_probe:
		var r := await _run_step(exe, "渲染探针（实际渲染器，S-1 口径）", ["--path", ".", "--script", PROBE_SCRIPT], true)
		results.append(r)
		probe_state = "exit=%d" % int(r["code"])
	# ---- 汇总：逐项退出码 + 引擎版本 + 探针口径；任一失败 → exit 1 ----
	var fails := 0
	print("")
	print("======== GATE-ALL 汇总 ========")
	var ver: Dictionary = Engine.get_version_info()
	print("引擎：Godot %s（%s）" % [String(ver.get("string", "?")), exe])
	for r in results:
		var code := int(r["code"])
		if code != 0:
			fails += 1
		print("%s %s — exit=%d" % ["FAIL" if code != 0 else "PASS", r["label"], code])
	print("渲染探针：%s" % probe_state)
	if fails > 0:
		print("GATE FAIL — %d 个步骤失败（图形检查失败不被单测成功覆盖）" % fails)
	else:
		print("GATE OK — 全链通过（探针状态见上；「未验证」≠ 全绿，须单独跑探针取证）")
	quit(1 if fails > 0 else 0)

## 跑一个阻塞子步骤：转发输出（截尾防刷屏——完整日志由各工具自身留档）、
## 返回 {label, code}。探针步（非 headless）在桌面环境会短暂弹窗，看门狗兜底。
func _run_step(exe: String, label: String, args: PackedStringArray, probe: bool) -> Dictionary:
	print("")
	print("======== 步骤：%s ========" % label)
	var out: Array = []
	var code := OS.execute(exe, args, out, true)
	var text := "\n".join(PackedStringArray(out))
	# 注：Windows 下 OS.execute 捕获的子进程 UTF-8 输出可能被按 ANSI/GBK 码页解码，
	# 转发显示为乱码（GBK 型误解不可逆）——判定与退出码聚合不受影响；需要人读
	# 中文日志时直接跑该工具（各工具直跑输出正常）。
	if OS.get_name() == "Windows":
		print("（子进程输出经管道转发，中文可能显示乱码——以各行 PASS/FAIL 与退出码为准）")
	# 转发尾部 40 行（门禁/探针的判定与汇总恒在尾部；头部逐用例明细不重复刷屏）
	var lines := text.split("\n")
	var head := 0
	if lines.size() > 40:
		head = lines.size() - 40
		print("……（前 %d 行省略，全量输出重跑该工具可见）" % head)
	for i in range(head, lines.size()):
		print(lines[i])
	if probe and code != 0:
		print("[gate_all] 探针步失败——渲染证据不齐，视同门禁失败（不得只看单测绿）")
	return {"label": label, "code": code}
