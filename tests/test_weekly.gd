extends TestCase
## The Weekly Challenge (src/game/weekly.gd) and the play streak (Progress.streak_days):
## the ISO week seed (the same all week, another the next, 2027-01-01 in 2026's week 53),
## three distinct mutators, a map and a look it allows; the mode started in the game,
## headless, to a scored end with its best kept; the best and the streak round-tripping
## through progress.json; the streak counting days in a row, resetting after a gap and
## paying its bonus from the data's day count; and Off: no row, no streak.

const MAIN := preload("res://src/game/main.gd")


func _fresh(on := true) -> String:
	var p := "user://test_weekly_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(p)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Progress.set_enabled(on)
	Progress.day_override = 0
	return p


func _done() -> void:
	Progress.set_enabled(false)
	Progress.day_override = 0
	Progress.reset_for_tests(Progress.PATH)


func _fight(won := true) -> Dictionary:
	return {"kind": "cpu", "cpu_level": 1, "players": [{"slot": 0, "fighters": ["cairn"], "won": won, "kos": 0}]}


func test_the_week_is_the_iso_week() -> void:
	assert_eq(Weekly.week_of(20261026), 202644, "a Monday:")
	assert_eq(Weekly.week_of(20261101), 202644, "its Sunday, the same week:")
	assert_eq(Weekly.week_of(20261102), 202645, "the next Monday, the next week:")
	assert_eq(Weekly.week_of(20270101), 202653, "a Friday in January can be the old year's week 53:")
	assert_eq(Weekly.week_of(20270104), 202701, "")
	assert_eq(Weekly.week_of(20251229), 202601, "a Monday in December can be the new year's week 1:")
	assert_eq(Weekly.week_of(20201231), 202053, "")
	assert_eq(Daily.date_of_day(Daily.day_number(20261028)), 20261028, "day numbers round-trip")
	assert_eq(Daily.day_number(20261101) - Daily.day_number(20261031), 1, "one day apart")


func test_the_draw_is_the_same_all_week_and_changes_with_the_week() -> void:
	var mon := Weekly.new("pete", 20261026)
	var sun := Weekly.new("cairn", 20261101)
	var next := Weekly.new("pete", 20261102)
	assert_eq(mon.week, 202644, "")
	assert_eq(mon.opponent(), sun.opponent(), "same opponent all week:")
	assert_eq(mon.picks, sun.picks, "same mutators:")
	assert_eq(mon.level, sun.level, "same level:")
	assert_eq(mon.arena_id, sun.arena_id, "same map:")
	assert_eq(mon.look(), sun.look(), "same look:")
	assert_true(mon.opponent() != next.opponent() or mon.picks != next.picks or mon.arena_id != next.arena_id,
		"another week, another fight")
	assert_eq(sun.fighter, "cairn", "your fighter is yours")
	assert_true(mon.stage_label().contains("2026 WEEK 44"), mon.stage_label())


func test_every_week_draws_three_distinct_mutators_on_a_map_it_allows() -> void:
	var table := Daily.mutator_table()
	var arenas := {}
	var foes := {}
	var day := Daily.day_number(20261026)
	for k in 30:
		var w := Weekly.new("cairn", Daily.date_of_day(day + 7 * k))
		assert_eq(w.picks.size(), Weekly.WEEK_PICKS, "three mutators: %s" % [w.picks])
		var seen := {}
		for id in w.picks:
			assert_true(table.has(id), "a mutator of the table: " + String(id))
			assert_false(seen.has(id), "distinct: %s" % [w.picks])
			seen[id] = true
		assert_true(w.arena_id in ArenaMap.IDS, w.arena_id)
		var map := ArenaMap.get_map(w.arena_id)
		assert_true(w.time_id in WeatherView.times_of(map), "%s allows %s" % [w.arena_id, w.time_id])
		assert_true(w.weather_id in WeatherView.weathers_of(map), "%s allows %s" % [w.arena_id, w.weather_id])
		assert_true(w.level >= 1 and w.level <= 2, "Normal or Hard")
		assert_eq(w.mutator_names_list().size(), 3, "")
		arenas[w.arena_id] = true
		foes[w.opponent()] = true
	assert_gt(float(arenas.size()), 2.0, "the maps vary: %s" % [arenas.keys()])
	assert_gt(float(foes.size()), 4.0, "the opponents vary: %s" % [foes.keys()])
	var sim := Weekly.new("cairn", 20261026).build()
	var w := Weekly.new("cairn", 20261026)
	assert_eq(String(sim.arena.get("id", "")), w.arena_id, "built on the week's map")
	assert_eq(Daily.mutator_names(sim.mutators).size(), 3, "with its three mutators: %s" % [sim.mutators])


func test_the_best_and_the_streak_round_trip() -> void:
	var p := _fresh()
	assert_eq(Progress.weekly_best(202644), 0, "nothing yet")
	assert_true(Progress.record_weekly(202644, 900), "a first score is a best")
	assert_false(Progress.record_weekly(202644, 700), "a lower one isn't")
	assert_true(Progress.record_weekly(202644, 1100), "")
	Progress.record_weekly(202645, 300)
	Progress.day_override = 20261027
	Progress.award(_fight())
	Progress.reset_for_tests(p)  # read back from the file
	assert_eq(Progress.weekly_best(202644), 1100, "the best per week is saved:")
	assert_eq(Progress.weekly_best(202645), 300, "each week its own:")
	assert_eq(Progress.streak_days(), 1, "the streak is saved:")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(p))
	assert_eq(int(saved["weekly"]["202644"]), 1100, "under `weekly`")
	assert_eq(int(saved["streak"]["last_day"]), 20261027, "and `streak`")
	# An old file without the keys still loads.
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"daily": {"20261020": 900}, "xp": 50}))
	f.close()
	Progress.reset_for_tests(p)
	assert_eq(Progress.weekly_best(202644), 0, "")
	assert_eq(Progress.streak_days(), 0, "")
	assert_eq(Progress.daily_best(20261020), 900, "")
	_done()


func test_the_streak_counts_days_in_a_row_and_resets_after_a_gap() -> void:
	_fresh()
	var x: Dictionary = Progress.table()["xp"]
	var mult := float(x["streak_mult"])
	var min_days := int(x["streak_min_days"])
	assert_gt(mult, 1.0, "a bonus")
	assert_lt(mult, 1.25, "kept small")
	var plain := Progress.xp_for(_fight(), _fight()["players"][0])
	Progress.day_override = 20261029
	var r := Progress.award(_fight())
	assert_eq(Progress.streak_days(), 1, "the first paid fight starts it")
	assert_false(bool(r["streak_up"]), "starting is no news")
	assert_eq(Progress.result_lines(r).filter(func(l): return String(l).begins_with("Streak")).size(), 0, "no row")
	r = Progress.award(_fight())
	assert_eq(Progress.streak_days(), 1, "a second fight the same day: still one day")
	Progress.day_override = 20261030
	r = Progress.award(_fight(false))
	assert_eq(Progress.streak_days(), 2, "the next day: two")
	assert_true(bool(r["streak_up"]), "extended")
	assert_true("Streak: 2 days" in Progress.result_lines(r), "the results row: %s" % [Progress.result_lines(r)])
	Progress.day_override = 20261031
	r = Progress.award(_fight())
	assert_eq(Progress.streak_days(), min_days, "three days")
	assert_eq(int(r["xp"]), roundi(plain * mult), "pays the bonus from %d days:" % min_days)
	assert_true(String(Progress.result_lines(r).back()).contains("+%d%% XP" % roundi((mult - 1.0) * 100.0)),
		"and says so: %s" % [Progress.result_lines(r)])
	Progress.day_override = 20261101  # across a month's end
	Progress.award(_fight())
	assert_eq(Progress.streak_days(), 4, "")
	Progress.day_override = 20261102
	assert_eq(Progress.streak_days(), 4, "alive until a whole day is missed")
	Progress.day_override = 20261103
	assert_eq(Progress.streak_days(), 0, "a day missed: gone")
	assert_eq(Progress.streak_bonus(), 1.0, "and its bonus")
	r = Progress.award(_fight())
	assert_eq(Progress.streak_days(), 1, "and it starts again")
	assert_eq(int(r["xp"]), plain, "without the bonus")
	var before := Progress.account_xp()
	Progress.day_override = 20261104
	Progress.award({"kind": "none", "players": [{"slot": 0, "fighters": ["cairn"], "won": true, "kos": 0}]})
	assert_eq(Progress.streak_days(), 1, "a fight that pays nothing keeps no streak")
	assert_eq(Progress.account_xp(), before, "")
	_done()


func test_a_clock_set_back_keeps_the_streak() -> void:
	_fresh()
	for day in [20261027, 20261028, 20261029, 20261030]:
		Progress.day_override = day
		Progress.award(_fight())
	assert_eq(Progress.streak_days(), 4, "four days in a row:")
	Progress.day_override = 20261029  # the clock a day back (or a trip west across midnight)
	assert_eq(Progress.streak_days(), 4, "a day behind the last fight still counts as its day:")
	Progress.award(_fight())
	assert_eq(Progress.streak_days(), 4, "a fight then changes nothing:")
	assert_eq(int(Progress._data["streak"]["last_day"]), 20261030, "the last day never moves back:")
	Progress.day_override = 20261031
	Progress.award(_fight())
	assert_eq(Progress.streak_days(), 5, "and the next real day goes on:")
	Progress.day_override = 20261020  # far off: the streak starts again, as after a gap
	assert_eq(Progress.streak_days(), 0, "")
	_done()


func test_the_weekly_clear_pays_on_top_of_the_score() -> void:
	_fresh()
	var x: Dictionary = Progress.table()["xp"]
	var p: Dictionary = _fight()["players"][0]
	var base := Progress.xp_for(_fight().merged({"daily_score": 1200}), p)
	assert_eq(base, roundi(float(x["fight"]) + float(x["win"]) + 12 * float(x["daily_score_mult"])), "the Daily's rate:")
	assert_eq(Progress.xp_for(_fight().merged({"daily_score": 1200, "weekly_clear": true}), p),
		roundi(base + float(x["weekly_clear"])), "and the week's first clear on top:")
	_done()


func test_off_there_is_no_row_and_no_streak() -> void:
	_fresh(false)
	Progress.day_override = 20261029
	assert_true(Progress.award(_fight()).is_empty(), "Off pays nothing")
	assert_eq(Progress.streak_days(), 0, "and keeps no streak")
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = "user://test_weekly.cfg"
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	Progress.set_enabled(false)
	assert_false("Weekly Challenge" in _labels(g), "Off: no Weekly row")
	assert_true("Daily Challenge" in _labels(g), "the Daily stays")
	g._open_single()
	var hub: UiScreen = g.ui.top()
	for c in hub.rows():
		if c is CardButton and (c as Button).text == "Challenges":
			assert_true(hub.card(c).facts.is_empty(), "Off: no today card")
	Progress.set_enabled(true)
	assert_true("Weekly Challenge" in _labels(g), "On: the row, under the Daily")
	assert_eq(_labels(g).find("Weekly Challenge"), _labels(g).find("Daily Challenge") + 1, "next to it")
	g._open_single()
	hub = g.ui.top()
	var facts: Array = []
	for c in hub.rows():
		if c is CardButton and (c as Button).text == "Challenges":
			assert_true((c as CardButton).subtitle.contains("Weekly"), "the card names it: " + (c as CardButton).subtitle)
			facts = hub.card(c).facts
	assert_eq(facts.size(), 2 + Weekly.WEEK_PICKS, "On: the today card, the Daily, the Weekly and its mutators: %s" % [facts])
	assert_true(String(facts[0]).begins_with("Daily:") and String(facts[1]).begins_with("Weekly:"), str(facts))
	g.free()
	_done()


func _labels(g: Node) -> Array:
	g._open_single_group("challenge")
	var out: Array = []
	for c in (g.ui.top() as UiScreen).rows():
		out.append((c as OptionRow).label if c is OptionRow else ((c as Button).text if c is Button else ""))
	g._close_ui()
	return out


## The mode in the game, headless: a Rage CPU in the player's seat against the week's CPU,
## to a scored end; a win keeps its score as the week's best and pays the first clear.
func test_the_weekly_plays_in_the_game_to_a_score() -> void:
	_fresh()
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = "user://test_weekly_game.cfg"
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	Progress.set_enabled(true)
	g._online_server = ""
	g._cpu_vs_cpu = true
	g.level = 3
	var m: int = MAIN.mode_index("Weekly Challenge")
	assert_eq(m, MAIN.MODES.size() - 1, "appended: no mode renumbered")
	g._start_match(m)
	assert_true(g.arcade is Weekly, "a Weekly")
	var w: Weekly = g.arcade
	assert_eq(String(g.sim.arena_id), w.arena_id, "on the week's map")
	assert_eq(g._match_look(g.sim), w.look(), "in the week's look")
	assert_eq(Daily.mutator_names(g.sim.mutators).size(), 3, "under its three mutators")
	for i in Daily.max_frames() + 400:
		g._physics_process(1.0 / 60.0)
		if g.flow == g.Flow.MATCH_OVER:
			break
	assert_eq(g.flow, g.Flow.MATCH_OVER, "the fight ends")
	assert_true(String(g.hud.banner).begins_with("SCORE") or g.hud.banner == "NO SCORE", g.hud.banner)
	var best := 0
	if String(g.hud.banner).begins_with("SCORE"):
		best = int(String(g.hud.banner).split(" ", false)[1])
	assert_eq(Progress.weekly_best(w.week), best, "a win's score is the week's best")
	assert_true(g._progress_shown.is_empty(), "CPU vs CPU pays nothing")
	assert_false(DirAccess.dir_exists_absolute("user://weekly"), "nothing kept for a server")
	# Again with the player's seat a player who never presses anything: a loss, paid as a fight.
	g._cpu_vs_cpu = false
	g._start_match(m)
	for i in Daily.max_frames() + 400:
		g._physics_process(1.0 / 60.0)
		if g.flow == g.Flow.MATCH_OVER:
			break
	assert_eq(g.flow, g.Flow.MATCH_OVER, "the second fight ends")
	assert_eq(g.hud.banner, "NO SCORE", "standing still loses")
	var got: Dictionary = g._progress_shown
	assert_gt(float(got.get("xp", 0)), 0.0, "a played Weekly pays a fight")
	assert_lt(float(got.get("xp", 0)), float(Progress.table()["xp"]["weekly_clear"]), "but no clear")
	assert_eq(Progress.weekly_best(w.week), best, "a loss keeps the best")
	assert_eq(Progress.streak_days(), 1, "and starts the streak")
	g.free()
	_done()
