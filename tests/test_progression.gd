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


## Hand-edited and damaged saves (the QC's crafted files): every getter reads them as the
## right type (no script error: the runner fails a test on any), an award still pays and
## saves, and the numbers go back as whole numbers.
const ODD_SAVES := {
	"old": "{\"arcade\": {\"cairn\": 1}, \"palette\": {\"cairn\": 2}, \"gauntlet\": {\"cairn\": 3}, \"daily\": {\"20261027\": 500}}",
	"xp_text": "{\"xp\": \"abc\"}",
	"xp_negative": "{\"xp\": -50}",
	"xp_huge": "{\"xp\": 1000000000000.0}",
	"unlocked_mixed": "{\"xp\": 500, \"unlocked\": [\"title:bogus\", 5, null, {\"a\": 1}, \"palette:cairn:9\", \"palette:nobody:1\", \"line:zzz\", \"title:rookie\"]}",
	"equipped_odd": "{\"xp\": 500, \"unlocked\": [\"title:rookie\"], \"equipped\": {\"cairn\": {\"palette\": 99, \"title\": \"title:legend\", \"line\": \"line:cairn_2\"}}, \"palette\": {\"cairn\": 99}, \"account_title\": \"title:legend\"}",
	"equipped_not_dicts": "{\"equipped\": {\"cairn\": \"title:rookie\", \"culvert\": 5, \"sno\": {\"title\": 5, \"line\": null}}, \"palette\": {\"cairn\": \"abc\", \"culvert\": {\"x\": 1}}}",
	"challenges_list": "{\"challenges\": [1, 2, 3]}",
	"counts_list": "{\"challenges\": {\"counts\": [1, 2], \"done\": \"first_fight\"}}",
	"counts_odd": "{\"challenges\": {\"counts\": {\"bogus_stat\": 5, \"fights\": 2.5, \"wins\": \"x\", \"kos\": null, \"wins_on:storm_drain\": {\"a\": 1}}, \"done\": [\"nope\", 3, \"first_fight\"]}}",
	"streak_text": "{\"streak\": {\"days\": \"x\", \"last_day\": \"y\"}}",
	"streak_future": "{\"streak\": {\"days\": 5, \"last_day\": 20991231}}",
	"weekly_odd": "{\"weekly\": {\"garbage\": \"x\", \"202644\": \"abc\", \"999999\": -5}}",
	"endings_odd": "{\"endings\": [\"nobody\", 7, null, \"cairn\"]}",
	"mastery_odd": "{\"mastery\": {\"cairn\": \"lots\", \"culvert\": -100, \"nobody\": 500, \"digby\": 1000000000000000.0, \"sno\": 1e30}}",
	"seen_text": "{\"seen\": \"x\", \"arcade\": {\"cairn\": \"hard\"}, \"gauntlet\": {\"cairn\": [1]}}",
	"arcade_dicts": "{\"arcade\": {\"cairn\": {\"x\": 1}}, \"daily\": {\"20261028\": {\"y\": 2}}}",
	"top_level_array": "[1, 2, 3]",
	"empty": "",
	"cut_off": "{\"xp\": 5, \"unlocked\": [",
}


func _read_everything() -> void:
	Progress.account_xp()
	Progress.account_level()
	Progress.level_progress()
	Progress.account_title()
	Progress.new_anywhere()
	Progress.streak_days()
	Progress.streak_bonus()
	Progress.weekly_best(202644)
	Progress.daily_best(20261028)
	for f in MatchFactory.FIGHTERS:
		var fs := String(f)
		assert_true(Progress.mastery_xp(fs) >= 0, "%s's mastery XP is never below 0" % fs)
		Progress.mastery_progress(fs)
		Progress.arcade_best(fs)
		Progress.gauntlet_best(fs)
		assert_true(Progress.palette(fs) >= 0 and Progress.palette(fs) < Progress.PALETTES, "")
		Progress.equipped(fs)
		Progress.shown_title(fs)
		Progress.shown_line(fs)
		Progress.unlocks_of(fs)
		Progress.ending_seen(fs)
	for g in Challenges.goals():
		Challenges.progress(String(g["id"]))
	Challenges.done_count()
	Challenges.count("maps_won")


func test_odd_and_damaged_saves_read_as_the_right_types() -> void:
	for name in ODD_SAVES:
		var p := _fresh()
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(String(ODD_SAVES[name]))
		f.close()
		Progress.reset_for_tests(p)
		_read_everything()
		assert_true(Progress.account_xp() >= 0 and Progress.account_xp() <= Progress.XP_MAX, "%s: the XP is in range (%d)" % [name, Progress.account_xp()])
		assert_false(Progress.award(_cpu(true, 1)).is_empty(), "%s: a fight still pays" % name)
		Progress.reset_for_tests(p)
		_read_everything()
		var text := FileAccess.get_file_as_string(p)
		assert_false(RegEx.create_from_string(r"\d\.0\b").search(text) != null, "%s: whole numbers are saved whole:\n%s" % [name, text])
		_cleanup(p)
	_done()


func test_the_saves_numbers_stay_whole_after_a_load_and_a_save() -> void:
	var p := _fresh()
	Progress.award(_cpu(true, 2))
	Progress.record_daily(20261028, 900)
	Progress.reset_for_tests(p)
	Progress.award(_cpu(true, 2))
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
	assert_false(FileAccess.get_file_as_string(p).contains(".0"), "no 4.0 for 4 in the file")
	assert_true(Progress.clean(d)["xp"] is int, "")
	_cleanup(p)
	_done()


## The save and its side files (.bak, .tmp, a moved-aside .corrupt-<time>).
func _cleanup(p: String) -> void:
	var dir := ProjectSettings.globalize_path(p).get_base_dir()
	var base := p.get_file()
	for n in DirAccess.get_files_at(dir):
		if String(n).begins_with(base):
			DirAccess.remove_absolute(dir.path_join(n))
