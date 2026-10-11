extends SceneTree
## Headless test runner. From the repo root:
##   godot --headless --path . --import
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 when any test fails, so CI can gate on it. A script error inside a
## test (a crash, a bad call) also counts as a failure. TEST_ONLY=digby,combos (an
## environment variable) runs only the files whose names contain one of those words.

const TEST_DIR := "res://tests/"


## Counts engine and script errors so a test that crashes can't pass silently.
class ErrorCatcher extends Logger:
	var count := 0
	var last := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1
		last = "%s (%s:%d)" % [rationale if rationale != "" else code, file, line]

	func _log_message(message: String, error: bool) -> void:
		pass


func _initialize() -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var files: Array[String] = []
	for f in DirAccess.get_files_at(TEST_DIR):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var only := OS.get_environment("TEST_ONLY")
	if only != "":
		var keep: Array[String] = []
		for f in files:
			for w in only.split(","):
				if w != "" and f.contains(w):
					keep.append(f)
					break
		files = keep

	var passed := 0
	var failed := 0
	for f in files:
		var errors_before := catcher.count
		var script: GDScript = load(TEST_DIR + f)
		print("\n", f)
		if script == null or not script.can_instantiate() or catcher.count > errors_before:
			failed += 1
			print("  FAIL  (could not load: %s)" % catcher.last)
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var before := catcher.count
			var suite: TestCase = script.new()
			suite.call(name)
			if catcher.count > before:
				suite.errors.append("script error: " + catcher.last)
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
