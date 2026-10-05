## 轻量测试跑器（零依赖）：godot --headless --path . --script res://tests/run_tests.gd
## 约定：测试类里 test_ 开头、无参、返回 String；"" = 通过，否则为失败描述。
extends SceneTree

func _init() -> void:
	var suites: Array = [
		load("res://tests/test_hex.gd").new(),
		load("res://tests/test_rules.gd").new(),
		load("res://tests/test_engine.gd").new(),
	]
	var passed := 0
	var failed := 0
	for suite in suites:
		var sname: String = suite.get_script().resource_path.get_file()
		for m in suite.get_method_list():
			if not String(m.name).begins_with("test_") or m.args.size() > 0:
				continue
			var err: String = suite.call(m.name)
			if err == "":
				passed += 1
				print("PASS  %s :: %s" % [sname, m.name])
			else:
				failed += 1
				printerr("FAIL  %s :: %s\n      %s" % [sname, m.name, err])
	print("\n===== %d passed, %d failed =====" % [passed, failed])
	quit(1 if failed > 0 else 0)
