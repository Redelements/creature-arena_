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


func test_ending_and_challenge_titles_say_so_and_are_new_until_the_account_page() -> void:
	_fresh()
	var g := _game()
	_clear(g, "sno", 1)
	g.flow_t = 0
	_tick(g, g.MATCH_OVER_MENU_AT + 1)
	var card: UiScreen = g.ui.top()
	assert_true(card is EndingScreen, "the ending card")
	var said: Array = card.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	var words := "Title unlocked: \"%s\"" % Progress.title_text("title:sno_ending")
	assert_true(said.has(words), "the card says the title it gave: %s" % [said])
	assert_true(Progress.is_new("title:sno_ending") and Progress.new_anywhere(), "and it is New! on the Profile")
	assert_true(Progress.new_of("").has("title:sno_ending"), "on the Account row")
	(card as EndingScreen).continue_button.pressed.emit()
	assert_true((g._progress_shown["unlocked"] as Array).has("title:sno_ending"), "the results' Unlocked: row counts it")
	Progress.grant_unlock("title:centurion")
	assert_true(Progress.new_of("").has("title:centurion"), "a challenge's title is New! too")
	g._open_menu("profile:account")
	var picker: OptionRow = null
	for r in g.ui.top().rows():
		if r is OptionRow and (r as OptionRow).label == "Title":
			picker = r
	assert_true(picker != null and picker.values.has(Progress.title_text("title:sno_ending")), "the Account picker offers ending titles")
	assert_false(Progress.new_anywhere(), "opening the Account page sees them")
	_done(g)


func test_a_cpu_vs_cpu_demo_pays_nothing_offline_or_online() -> void:
	_fresh()
	var g := _game()
	g._skip_select = true
	g._start_match(0)
	_tick(g, 5)
	assert_eq(String(g.show_ctl.progress_report(true)["kind"]), "cpu", "a fight against the CPU pays:")
	g._cpu_vs_cpu = true  # --cpu-vs-cpu: online the local slot stays a human side, so the flag itself is checked
	assert_eq(String(g.show_ctl.progress_report(true)["kind"]), "none", "the demo flag pays nothing:")
	g._cpu_vs_cpu = false
	_done(g)


func test_a_daily_retry_pays_its_score_only_on_a_new_best() -> void:
	_fresh()
	var daily := "user://daily/daily_%d.json" % Daily.today()
	var kept: Variant = FileAccess.get_file_as_string(daily) if FileAccess.file_exists(daily) else null
	var g := _game()
	var old_best := Progress.daily_best(Daily.today())
	var paid: Array = []
	for i in 2:
		g._arcade_fighter = "cairn"
		g._skip_select = true
		g._start_match(g.mode_index("Daily Challenge"))
		_tick(g, 10)
		g.wins = [1, 0]
		g._arcade_result(true)
		paid.append(int(g._progress_shown.get("xp", 0)))
	var r: Dictionary = g.show_ctl.progress_report(true, {"daily_score": 0})
	assert_true(bool(r["ladder"]), "a Daily fight is a ladder stage")
	assert_eq(paid[1], Progress.xp_for(r, r["players"][0]), "the same score again pays the fight alone:")
	if Progress.daily_best(Daily.today()) > old_best:
		assert_gt(float(paid[0]), float(paid[1]), "the first, a new best, paid its score too")
	_done(g)
	Progress.set_enabled(false)
	if kept == null:
		DirAccess.remove_absolute(daily)
	else:
		var f := FileAccess.open(daily, FileAccess.WRITE)
		f.store_string(String(kept))
		f.close()


func test_two_local_players_against_cpus_are_paid_at_the_cpu_level() -> void:
	_fresh()
	var g := _game()
	g.level = 0  # Easy CPUs
	g._skip_select = true
	g._start_match(g.mode_index("Brawl: 2 players"))
	_tick(g, 5)
	var r: Dictionary = g.show_ctl.progress_report(false)
	assert_eq(String(r["kind"]), "local", "two humans:")
	assert_true(bool(r.get("cpus", false)), "and CPUs in the match")
	var x: Dictionary = Progress.table()["xp"]
	assert_eq(Progress.xp_for(r, r["players"][0]), roundi((float(x["fight"]) + float(r["players"][0]["kos"]) * float(x["ko"])) * float(x["level_mult"][0])),
		"paid at the Easy rate, not full:")
	g._start_match(g.mode_index("Versus: 2 players"))
	_tick(g, 5)
	r = g.show_ctl.progress_report(false)
	assert_false(bool(r.get("cpus", false)), "two players alone: no CPU, paid fully")
	_done(g)


func test_the_hud_names_the_level_a_ladder_stages_cpu_plays_at() -> void:
	_fresh()
	var g := _game()
	g.level = 1
	g._arcade_fighter = "cairn"
	g._skip_select = true
	g._start_match(g.mode_index("Arcade"))
	g.arcade.stage = Arcade.STAGES - 1
	g._start_arcade_stage()
	_tick(g, 2)
	assert_eq(String(g.hud.tags[1]), "CPU " + String(g.LEVEL_NAMES[2]), "the boss plays Hard on a Normal run, and says so:")
	g._start_match(0)
	_tick(g, 2)
	assert_eq(String(g.hud.tags[1]), "CPU " + String(g.LEVEL_NAMES[1]), "a plain fight: the setting's level:")
	_done(g)


func test_the_worn_palette_reaches_the_hud_portrait_and_the_results_pose() -> void:
	_fresh()
	var g := _game()
	Progress.record_clear("cairn", 0)  # palette 2 is Cairn's
	Progress.set_palette("cairn", 1)
	g._skip_select = true
	g._start_match(0)  # Cairn vs CPU Culvert
	_tick(g, 5)
	assert_eq(int(g.views[0].palette), 1, "the fighter wears it:")
	assert_eq(int(g.hud.palettes.get(0, 0)), 1, "so does its HUD portrait:")
	assert_eq(int(g.hud.palettes.get(1, 0)), 0, "the CPU's keeps its own:")
	g.wins = [2, 0]
	g.sim.creatures[1].state = CreatureSim.State.KO  # Cairn stands over the CPU: the pose
	g.flow = g.Flow.MATCH_OVER
	g.flow_t = 0
	g.hud.banner = "CAIRN WINS!"
	_tick(g, g.MATCH_OVER_MENU_AT + 1)
	assert_eq(int(g.show_ctl.results_data()["palette"]), 1, "and the results' pose:")
	var panels: Array = g.ui.top().find_children("*", "ResultsPanel", true, false)
	assert_true(not panels.is_empty() and (panels[0] as ResultsPanel).preview.palette == 1, "drawn in it")
	_done(g)
