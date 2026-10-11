extends TestCase
## Every game script parses and compiles. The views and the game flow aren't loaded by the
## simulation tests, so a typo there would otherwise only show when the game runs.


func _scripts(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)


func test_every_game_script_compiles() -> void:
	var all: Array = []
	_scripts("res://src", all)
	assert_gt(float(all.size()), 20.0, "found the game's scripts")
	for path in all:
		var s: GDScript = load(path)
		assert_true(s != null and s.can_instantiate(), "%s should compile" % path)
