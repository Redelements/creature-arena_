extends TestCase
## Progression (Progress, data/progression.json; Settings > Game > Progression): the data's
## curves, what a match pays (Normal win, Easy loss, two local players, online, nothing for
## training), level-ups and unlocks, an old progress.json loading with defaults, palettes
## unlocked by an Arcade clear or by mastery, and Off paying nothing and changing nothing.


func _fresh() -> String:
	var p := "user://test_progression_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(p)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Progress.set_enabled(true)
	return p


func _done() -> void:
	Progress.set_enabled(false)
	Progress.reset_for_tests(Progress.PATH)


func _cpu(won: bool, kos: int, level := 1, fighter := "cairn") -> Dictionary:
	return {"kind": "cpu", "cpu_level": level, "players": [{"slot": 0, "fighters": [fighter], "won": won, "kos": kos}]}


func test_the_data_loads_and_its_curves_climb_to_their_caps() -> void:
	var t := Progress.table()
	assert_true(t.has("xp") and t.has("account") and t.has("mastery"), "data/progression.json loads")
	for key in ["account_curve", "mastery_curve"]:
		var c: Dictionary = t[key]
		var last := 0
		for lvl in range(1, int(c["cap"])):
			var cost := Progress.level_cost(c, lvl)
			assert_true(cost >= last and cost > 0, "%s level %d costs %d, no less than the one before" % [key, lvl, cost])
			last = cost
			assert_eq(Progress.level_of(c, Progress.xp_for_level(c, lvl)), lvl, "%s: the XP for level %d is level %d:" % [key, lvl, lvl])
		assert_eq(Progress.level_of(c, 10000000), int(c["cap"]), "%s stops at its cap:" % key)
	assert_eq(int(t["account_curve"]["cap"]), 50, "the account caps at 50:")
	assert_eq(int(t["mastery_curve"]["cap"]), 10, "mastery at 10:")
	# The pacing the plan asks for: a two-minute fight at Normal, won half the time with
	# one or two KOs, pays about fight + win / 2 + 1.5 KOs.
	var x: Dictionary = t["xp"]
	var per_fight := float(x["fight"]) + 0.5 * float(x["win"]) + 1.5 * float(x["ko"])
	var per_hour := per_fight * 30.0
	var acc_hours := Progress.xp_for_level(t["account_curve"], 50) / per_hour
	var mas_hours := Progress.xp_for_level(t["mastery_curve"], 10) / per_hour
	assert_true(acc_hours > 35.0 and acc_hours < 45.0, "the account cap takes about 40 hours (%.1f)" % acc_hours)
	assert_true(mas_hours > 3.0 and mas_hours < 5.0, "a fighter's mastery about 4 (%.1f)" % mas_hours)
	var first := Progress.level_cost(t["account_curve"], 1)
	var win := Progress.xp_for(_cpu(true, 1), _cpu(true, 1)["players"][0])
	var loss := Progress.xp_for(_cpu(false, 0), _cpu(false, 0)["players"][0])
	assert_true(2 * win >= first, "two Normal wins reach level 2")
	assert_true(win + 2 * loss >= first, "so does a win and two losses at Normal")
	for row in Progress.account_rewards() + Progress.mastery_rewards("cairn"):
		assert_true(Progress.reward_text(String(row["id"])) != String(row["id"]), "%s has words" % row["id"])


func test_a_normal_win_an_easy_loss_two_local_players_and_online_pay_as_the_data_says() -> void:
	_fresh()
	var x: Dictionary = Progress.table()["xp"]
	var mult: Array = x["level_mult"]
	var r := Progress.award(_cpu(true, 2))
	var normal_win := roundi((float(x["fight"]) + float(x["win"]) + 2 * float(x["ko"])) * float(mult[1]))
	assert_eq(int(r["xp"]), normal_win, "a Normal win with two KOs:")
	assert_eq(Progress.account_xp(), normal_win, "the account has it:")
	assert_eq(Progress.mastery_xp("cairn"), normal_win, "so does the fighter's mastery:")
	r = Progress.award(_cpu(false, 0, 0, "sno"))
	assert_eq(int(r["xp"]), roundi(float(x["fight"]) * float(mult[0])), "an Easy loss: the fight, halved:")
	var kos := Progress.award(_cpu(false, 40))
	assert_eq(int(kos["xp"]), roundi(float(x["fight"]) + float(x["ko_cap"]) * float(x["ko"])), "KOs count up to the cap:")
	var before := Progress.account_xp()
	r = Progress.award({"kind": "local", "cpu_level": 0, "players": [
		{"slot": 0, "fighters": ["digby"], "won": true, "kos": 2},
		{"slot": 1, "fighters": ["pete"], "won": false, "kos": 1}]})
	var w := roundi(float(x["fight"]) + float(x["win"]) + 2 * float(x["ko"]))
	var l := roundi(float(x["fight"]) + float(x["ko"]))
	assert_eq(Progress.mastery_xp("digby"), w, "two local players: each paid fully, no CPU multiplier:")
	assert_eq(Progress.mastery_xp("pete"), l, "")
	assert_eq(Progress.account_xp() - before, w, "the one account takes the better of the two:")
	before = Progress.account_xp()
	r = Progress.award({"kind": "online", "cpu_level": 0, "players": [{"slot": 1, "fighters": ["hissy"], "won": true, "kos": 0}]})
	assert_eq(int(r["xp"]), roundi(float(x["fight"]) + float(x["win"])), "online pays fully:")
	r = Progress.award({"kind": "cpu", "cpu_level": 1, "players": [{"slot": 0, "fighters": ["cairn", "sno", "pete"], "won": true, "kos": 0}]})
	var share := ceili((float(x["fight"]) + float(x["win"])) / 3.0)
	assert_eq(int(r["mastery"]["sno"]["xp"]), share, "a Duel's three split the XP for mastery:")
	before = Progress.account_xp()
	assert_true(Progress.award({"kind": "none", "players": [{"slot": 0, "fighters": ["cairn"], "won": true, "kos": 3}]}).is_empty(),
		"training, showcases, replays and CPU vs CPU pay nothing")
	assert_true(Progress.award({"kind": "cpu", "cpu_level": 1, "players": []}).is_empty(), "nor a match with no human")
	assert_eq(Progress.account_xp(), before, "")
	var arcade := Progress.award({"kind": "cpu", "cpu_level": 1, "clear_arcade": true, "waves": 0,
		"players": [{"slot": 0, "fighters": ["cairn"], "won": true, "kos": 0}]})
	assert_eq(int(arcade["xp"]), roundi(float(x["fight"]) + float(x["win"]) + float(x["clear_arcade"])), "an Arcade clear on top:")
	var daily := Progress.award({"kind": "cpu", "cpu_level": 1, "daily_score": 1200,
		"players": [{"slot": 0, "fighters": ["cairn"], "won": true, "kos": 0}]})
	assert_eq(int(daily["xp"]), roundi(float(x["fight"]) + float(x["win"]) + 12 * float(x["daily_score_mult"])), "the Daily's score:")
	_done()


func test_level_ups_and_unlocks_are_reported_once() -> void:
	_fresh()
	var acc: Dictionary = Progress.table()["account_curve"]
	var mc: Dictionary = Progress.table()["mastery_curve"]
	assert_eq(Progress.account_level(), 1, "a new save is level 1:")
	assert_eq(Progress.level_progress(), [0, Progress.level_cost(acc, 1)], "with nothing into it:")
	assert_eq(Progress.mastery_level("cairn"), 1, "")
	var r := {}
	var n := 0
	while Progress.mastery_level("cairn") < 2 and n < 100:
		r = Progress.merge_results(r, Progress.award(_cpu(true, 2)))
		n += 1
	assert_true(int(r["level_to"]) > int(r["level_from"]), "the account levelled on the way")
	assert_true("title:rookie" in r["unlocked"], "level 2's title unlocked: %s" % [r["unlocked"]])
	assert_true(Progress.unlocked("title:rookie"), "and is kept")
	assert_eq(int(r["mastery"]["cairn"]["to"]), 2, "Cairn's mastery is 2:")
	assert_true("palette:cairn:1" in r["unlocked"], "with its second palette:")
	assert_eq(Progress.palettes_unlocked("cairn"), 2, "which it can now wear:")
	assert_true("palette:cairn:1" in Progress.unlocks_of("cairn"), "")
	var lines := Progress.result_lines(r)
	assert_true(String(lines[0]).begins_with("+%d XP" % int(r["xp"])), "the results say the XP: %s" % [lines])
	assert_true("Level up! Level" in String(lines[0]), "and the level-up:")
	assert_true("Mastery up! Cairn 2" in String(lines[1]), "the mastery-up:")
	assert_true(String(lines[2]).begins_with("Unlocked: "), "and what unlocked:")
	var again := Progress.award(_cpu(false, 0))
	assert_false("title:rookie" in again["unlocked"], "an unlock is news only once")
	assert_eq(Progress.mastery_progress("cairn")[1], Progress.level_cost(mc, 2), "the next mastery level's cost:")
	assert_eq(Progress.equipped("cairn"), {"palette": 0, "title": "", "line": ""}, "nothing equipped by default:")
	assert_true(Progress.set_equipped("cairn", "title", "title:rookie"), "an unlocked title can be worn")
	assert_false(Progress.set_equipped("cairn", "line", "line:cairn_1"), "a locked line can't")
	Progress.reset_for_tests(Progress.path)  # from disk
	assert_eq(Progress.equipped("cairn")["title"], "title:rookie", "what's worn is saved:")
	assert_true(Progress.unlocked("title:rookie"), "so are the unlocks:")
	_done()


func test_an_old_progress_file_loads_with_defaults() -> void:
	var p := _fresh()
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"arcade": {"sno": 1}, "palette": {"sno": 2}, "gauntlet": {"pete": 4}, "daily": {"20261020": 900}}))
	f.close()
	Progress.reset_for_tests(p)
	assert_eq(Progress.account_xp(), 0, "no XP yet:")
	assert_eq(Progress.account_level(), 1, "")
	assert_eq(Progress.mastery_level("sno"), 1, "")
	assert_eq(Progress.arcade_best("sno"), 1, "the old keys are kept:")
	assert_eq(Progress.palette("sno"), 2, "")
	assert_eq(Progress.gauntlet_best("pete"), 4, "")
	assert_eq(Progress.daily_best(20261020), 900, "")
	assert_false(Progress.award(_cpu(true, 1, 1, "sno")).is_empty(), "and it takes XP")
	Progress.reset_for_tests(p)
	assert_true(Progress.account_xp() > 0, "saved beside the old keys:")
	assert_eq(Progress.arcade_best("sno"), 1, "")
	_done()


func test_palettes_unlock_by_an_arcade_clear_or_by_mastery() -> void:
	_fresh()
	Progress.record_clear("sno", 0)
	assert_eq(Progress.palettes_unlocked("sno"), 2, "an Easy clear: two palettes, as before:")
	assert_true(Progress.unlocked("palette:sno:1"), "")
	assert_false(Progress.unlocked("palette:sno:2"), "")
	var r := {}
	var n := 0
	while Progress.mastery_level("sno") < 5 and n < 200:
		r = Progress.merge_results(r, Progress.award(_cpu(true, 0, 1, "sno")))
		n += 1
	assert_eq(Progress.palettes_unlocked("sno"), 3, "mastery 5 adds the third:")
	assert_false("palette:sno:1" in r["unlocked"], "the palette the clear gave is no news")
	assert_true("palette:sno:2" in r["unlocked"], "the one mastery gave is:")
	Progress.set_palette("sno", 2)
	assert_eq(Progress.palette("sno"), 2, "and it can be worn:")
	Progress.set_enabled(false)
	assert_eq(Progress.palettes_unlocked("sno"), 2, "Off: the Arcade's rule alone, as today:")
	Progress.record_clear("sno", 2)
	assert_eq(Progress.palettes_unlocked("sno"), 4, "a Hard clear still gives the lot:")
	_done()


func test_off_pays_nothing_and_changes_nothing() -> void:
	var p := _fresh()
	Progress.set_enabled(false)
	assert_false(Progress.enabled(), "")
	assert_true(Progress.award(_cpu(true, 3)).is_empty(), "Off: no award")
	assert_eq(Progress.account_xp(), 0, "no XP:")
	assert_eq(Progress.mastery_xp("cairn"), 0, "no mastery:")
	assert_false(FileAccess.file_exists(p), "and the save isn't written")
	_done()


func test_the_setting_is_off_by_default_and_saved() -> void:
	var cfg_path := "user://test_progression_settings.cfg"
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	_fresh()
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = cfg_path
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	assert_false(Progress.enabled(), "Progression starts Off")
	assert_true("progression" in g.SETTING_PAGES["game"], "a row on Settings > Game")
	assert_eq(g.settings_ctl._setting("progression")["index"], 0, "")
	g.settings_ctl._set_setting("progression", 1)
	assert_true(Progress.enabled(), "On")
	g.settings_ctl._save_settings()
	Progress.set_enabled(false)
	g.settings_ctl._load_settings()
	assert_true(Progress.enabled(), "and saved")
	g.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	_done()
