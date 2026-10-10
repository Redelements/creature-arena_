extends SceneTree
## Headless test runner. From the repo root:
##   godot --headless --path . --import
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 when any test fails, so CI can gate on it.

const TEST_DIR := "res://tests/"


func _initialize() -> void:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(TEST_DIR):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()

	var passed := 0
	var failed := 0
	for f in files:
		var script: GDScript = load(TEST_DIR + f)
		print("\n", f)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var suite: TestCase = script.new()
			suite.call(name)
			if suite.errors.is_empty():
				passed += 1
				print("  PASS  ", name)
			else:
				failed += 1
				print("  FAIL  ", name)
				for e in suite.errors:
					print("        ", e)

	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
