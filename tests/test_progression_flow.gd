extends TestCase
## Progression through real matches in main (the QC findings of 2026-10-28): an Easy Arcade
## clear counts as an Easy clear (the boss plays one level up), the boss Duel pays the run's
## own fighter only, a ladder win shows the winner's title and line, local play against CPUs
## pays at the CPU level, an online CPU-vs-CPU demo pays nothing, the HUD names the ladder
## stage's CPU level, the worn palette reaches the HUD portrait and the results figure, and
## an online match's end says what it paid in a toast.

const TEST_SETTINGS := "user://test_progression_flow.cfg"

var _save := ""


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _fresh() -> void:
	_save = "user://test_progression_flow_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(_save)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save))
	Challenges.begin_match()


func _done(g: Node) -> void:
	if g != null:
		g.free()
	Progress.set_enabled(false)
	Challenges.begin_match()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	Progress.reset_for_tests(Progress.PATH)


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	Progress.set_enabled(true)
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


## An Arcade run on `level` up to the boss, the boss down.
func _clear(g: Node, fighter: String, level: int) -> void:
	g.level = level
	g._arcade_fighter = fighter
	g._skip_select = true
	g._start_match(g.mode_index("Arcade"))
	g.arcade.stage = Arcade.STAGES - 1
	g._start_arcade_stage()
	_tick(g, 10)
	assert_true(g._arcade_result(true), "the boss falls")


func test_an_easy_arcade_clear_is_an_easy_clear() -> void:
	_fresh()
	var g := _game()
	_clear(g, "cairn", 0)
	assert_eq(g._cpu_level_override, 1, "the boss played one level up (Normal):")
	assert_true(Challenges.done("arcade_easy"), "the Easy clear is counted")
	assert_false(Challenges.done("arcade_normal"), "and not as a Normal one")
	var r: Dictionary = g.show_ctl.progress_report(true, {"clear_arcade": true})
	assert_eq(int(r["arcade_level"]), 0, "the report carries the run's level:")
	assert_eq(int(r["cpu_level"]), 0, "and pays at it:")
	_done(g)
	_fresh()
	g = _game()
	_clear(g, "cairn", 2)
	assert_true(Challenges.done("arcade_hard"), "a Hard clear is Hard")
	assert_false(Challenges.done("arcade_rage"), "not Rage")
	assert_false(Progress.unlocked("title:unstoppable"), "so no Rage title")
	_done(g)


func test_the_boss_duel_pays_the_runs_fighter_not_its_allies() -> void:
	_fresh()
	var g := _game()
	_clear(g, "cairn", 1)
	var allies: Array = g.arcade.allies
	assert_true(Progress.mastery_xp("cairn") > 0, "Cairn's mastery grew")
	for a in allies:
		assert_eq(Progress.mastery_xp(String(a)), 0, "the ally %s earned no mastery:" % a)
		assert_eq(Challenges.count("wins_as:" + String(a)), 0, "nor a win as itself:")
	assert_eq(Challenges.count("wins_as:cairn"), 1, "the win is Cairn's:")
	_done(g)
	# A plain Duel still splits a team's XP three ways.
	_fresh()
	g = _game()
	g._skip_select = true
	g._start_match(g.mode_index("Duel: you vs CPU  (3v3 tag)"))
	_tick(g, 5)
	var fs: Array = g.show_ctl.progress_report(true)["players"][0]["fighters"]
	assert_eq(fs.size(), 3, "a Duel's three share: %s" % [fs])
	_done(g)


func test_a_ladder_win_shows_the_winners_title_and_line() -> void:
	_fresh()
	var daily := "user://daily/daily_%d.json" % Daily.today()
	var kept: Variant = FileAccess.get_file_as_string(daily) if FileAccess.file_exists(daily) else null
	var g := _game()
	Progress.grant_unlock("title:rookie")
	Progress.grant_unlock("line:cairn_1")
	Progress.set_account_title("title:rookie")
	Progress.set_equipped("cairn", "line", "line:cairn_1")
	g._arcade_fighter = "cairn"
	g._skip_select = true
	g._start_match(g.mode_index("Daily Challenge"))
	_tick(g, 10)
	g.wins = [1, 0]
	g._arcade_result(true)
	var d: Dictionary = g.show_ctl.results_data()
	assert_eq(String(d["badge"]), Progress.title_text("title:rookie"), "a Daily win shows the title:")
	assert_eq(String(d["line"]), Progress.line_text("line:cairn_1"), "and the line:")
	# A first Arcade stage won (one round) is a win too.
	g._start_match(g.mode_index("Arcade"))
	_tick(g, 10)
	g.wins = [1, 0]
	assert_true(g.show_ctl._slot_won(0), "one won round wins a ladder stage")
	_done(g)
	if kept == null:  # (the Daily saved its fight: leave the folder as it was)
		DirAccess.remove_absolute(daily)
	else:
		var f := FileAccess.open(daily, FileAccess.WRITE)
		f.store_string(String(kept))
		f.close()
