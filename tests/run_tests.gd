## 零依赖测试 runner（headless 跑法）：
##   "E:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd
## 约定：tests/test_*.gd 的每个 test_ 方法返回 ""（或 null）为通过，返回非空字符串为失败信息。
extends SceneTree


func _init() -> void:
	var total := 0
	var failed := 0
	var dir := DirAccess.open("res://tests")
	if dir == null:
		push_error("tests/ 目录不存在")
		quit(1)
		return

	for file in dir.get_files():
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load("res://tests/" + file)
		var inst = script.new()
		for method in script.get_script_method_list():
			if not method.name.begins_with("test_"):
				continue
			total += 1
			var result = inst.call(method.name)
			if result == null or result == "":
				pass
			else:
				failed += 1
				print("  FAIL %s :: %s — %s" % [file, method.name, result])

	print("==== %d tests, %d failed ====" % [total, failed])
	quit(1 if failed > 0 else 0)
