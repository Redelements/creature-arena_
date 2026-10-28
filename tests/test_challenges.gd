extends TestCase
## Challenges (src/game/challenges.gd, data/challenges.json; Settings > Game > Progression):
## the data loads with unique snake_case ids, groups it names, and only stats the tracker
## counts (a goal naming an unknown counter fails here); the per-fighter goal expands for
## every fighter; a real match against the CPU completes first_fight and first_win and pays
## their XP onto the results rows; the events count what they should for the account's
## player only (guard breaks, Surge KOs, ring-outs, dodge cancels, meteors, boulders, the
## caravan); the save round-trips and an old or odd file reads as empty; Off and a match of
## kind "none" count nothing. Phone fit of Profile > Challenges and the results row:
## tests/test_ui_fit.gd.

const TEST_SETTINGS := "user://test_challenges.cfg"

var _save := ""


func _fresh() -> String:
	_save = "user://test_challenges_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(_save)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save))
	Progress.set_enabled(true)
	Challenges.begin_match()
	return _save


func _done() -> void:
	Progress.set_enabled(false)
	Challenges.begin_match()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save))
	Progress.reset_for_tests(Progress.PATH)


func _report(won: bool, kind := "cpu", fighters: Array = ["cairn"], slot := 0) -> Dictionary:
	return {"kind": kind, "cpu_level": 1, "players": [{"slot": slot, "fighters": fighters, "won": won, "kos": 0}]}


func _rows(slot := 0, kos := 0, combo := 0, blocks := 0) -> Dictionary:
	return {slot: {"damage": 0.0, "hits": 0, "kos": kos, "combo": combo, "blocks": blocks, "surges": 0}}


func test_the_data_loads_with_unique_snake_case_ids_and_known_stats() -> void:
	var goals := Challenges.goals()
	assert_true(goals.size() >= 45 and goals.size() <= 55, "about fifty goals (%d)" % goals.size())
	var snake := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	var seen := {}
	for g in goals:
		var id := String(g.get("id", ""))
		assert_true(snake.search(id) != null, "'%s' is lowercase snake_case" % id)
		assert_false(seen.has(id), "'%s' is unique" % id)
		seen[id] = true
		assert_true(String(g.get("stat", "")) in Challenges.STATS, "%s's stat '%s' is one the tracker counts" % [id, g.get("stat")])
		assert_true(String(g.get("group", "")) in Challenges.groups(), "%s's group '%s' is a heading" % [id, g.get("group")])
		assert_true(int(g.get("target", 0)) > 0, "%s has a target" % id)
		assert_true(String(g.get("name", "")) != "" and String(g.get("desc", "")) != "", "%s has words" % id)
		assert_false(String(g["name"]).contains("{") or String(g["desc"]).contains("{"), "%s: no template left" % id)
		var rw: Dictionary = g.get("reward", {})
		assert_true(int(rw.get("xp", 0)) > 0 or String(rw.get("id", "")) != "", "%s pays something" % id)
		var rid := String(rw.get("id", ""))
		if rid != "":
			assert_true(rid.begins_with("title:"), "%s's reward is a title" % id)
			assert_true(Progress.title_text(rid) != rid.trim_prefix("title:"), "%s's title has words in progression.json" % rid)
	# Every stat the tracker lists is used by a goal (no dead counters).
	var used := {}
	for g in goals:
		used[String(g["stat"])] = true
	for s in Challenges.STATS:
		assert_true(used.has(s), "a goal uses '%s'" % s)
	# The map tour's target is every map.
	var maps := 0
	for f in DirAccess.get_files_at("res://data/arenas"):
		if String(f).ends_with(".json"):
			maps += 1
	for g in goals:
		if String(g["stat"]) == "maps_won":
			assert_eq(int(g["target"]), maps, "World Tour wants every map:")


func test_the_per_fighter_goal_expands_for_every_fighter() -> void:
	var per: Array = []
	for g in Challenges.goals():
		if String(g["stat"]) == "wins_as":
			per.append(g)
	assert_eq(per.size(), MatchFactory.FIGHTERS.size(), "one per fighter:")
	assert_eq(per.size(), 11, "eleven:")
	for f in MatchFactory.FIGHTERS:
		var g := Challenges.goal("%s_wins_5" % f)
		assert_false(g.is_empty(), "%s has its goal" % f)
		assert_eq(String(g.get("fighter", "")), String(f), "")
		assert_eq(Challenges.counter_of(g), "wins_as:" + String(f), "")
		var name := String(MatchFactory.load_def(String(f))["name"])
		assert_true(String(g["desc"]).contains(name), "%s's goal names it: %s" % [f, g["desc"]])


func test_a_won_match_completes_first_win_and_pays_its_xp() -> void:
	_fresh()
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	Progress.set_enabled(true)  # (after the settings load, which reads it Off)
	g._skip_select = true
	g._start_match(0)  # Cairn vs CPU Culvert
	for i in 30:
		g._physics_process(1.0 / 60.0)
	g.wins = [2, 0]
	g.sim.creatures[0].hp = g.sim.creatures[0].max_hp * 0.5  # (not a flawless win)
	g.flow = g.Flow.MATCH_OVER
	g.flow_t = 0
	g.hud.banner = "CAIRN WINS!"
	var award := Progress.xp_for(g.show_ctl.progress_report(), g.show_ctl.progress_report()["players"][0])
	g._physics_process(1.0 / 60.0)
	assert_true(Challenges.done("first_win"), "first_win is done")
	assert_true(Challenges.done("first_fight"), "and first_fight")
	assert_eq(Challenges.progress("first_win"), [1, 1], "")
	assert_eq(Challenges.progress("wins_10"), [1, 10], "the count is shared by the same stat's goals:")
	assert_eq(Challenges.progress("cairn_wins_5"), [1, 5], "Cairn's own goal counts:")
	assert_eq(Challenges.progress("culvert_wins_5"), [0, 5], "the CPU's fighter doesn't:")
	var paid := int(Challenges.goal("first_win")["reward"]["xp"]) + int(Challenges.goal("first_fight")["reward"]["xp"])
	assert_eq(Progress.account_xp(), award + paid, "the match's XP plus the two goals':")
	assert_eq(Challenges.completed_this_match().size(), 2, "")
	var lines: Array = g.show_ctl.progress_lines()
	assert_eq(String(lines[0]).get_slice(" ", 0), "+%d" % (award + paid), "the results' XP row has the goals' XP: %s" % [lines])
	assert_eq(String(lines.back()), "+2 challenges", "and a row for them:")
	# A second tick of the same match pays nothing more.
	var xp := Progress.account_xp()
	g._physics_process(1.0 / 60.0)
	assert_eq(Progress.account_xp(), xp, "once per match:")
	assert_eq(Challenges.result_line(["first_win"]), "Challenge: First Win", "one is named:")
	g.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	_done()


func test_the_events_count_for_the_accounts_player_only() -> void:
	_fresh()
	var evs := [
		# Slot 0 breaks slot 1's guard, then Surges it out.
		{"type": "guard_break", "who": 1},
		{"type": "hit", "attacker": 0, "target": 1, "move_type": "heavy", "dealt": 10.0, "power": 10.0},
		{"type": "hit", "attacker": 0, "target": 1, "move_type": "surge", "dealt": 30.0, "power": 30.0},
		{"type": "ko", "who": 1},
		# Slot 1 hits slot 2 and knocks it into a pit (slot 1's ring-out, not slot 0's).
		{"type": "hit", "attacker": 1, "target": 2, "move_type": "light", "dealt": 3.0, "power": 3.0},
		{"type": "fall", "who": 2, "pit": "chasm"},
		# Slot 0 knocks slot 3 into a pit.
		{"type": "hit", "attacker": 0, "target": 3, "move_type": "light", "dealt": 3.0, "power": 3.0},
		{"type": "fall", "who": 3, "pit": "hole"},
		{"type": "dodge", "who": 0, "cancel": true},
		{"type": "dodge", "who": 0, "cancel": false},
		{"type": "breakaway", "who": 1},
		{"type": "hazard_strike", "shape": "meteors", "hazard": "meteor_shower"},
		{"type": "hazard_hit", "who": 1, "shape": "meteors", "damage": 5.0, "by": -1},
		{"type": "hazard_reverse", "by": 0, "hazard": "boulder"},
		{"type": "hazard_hit", "who": 3, "shape": "boulder", "damage": 9.0, "by": 0},
		{"type": "hazard_hit", "who": 2, "shape": "boulder", "damage": 9.0, "by": 0},  # a teammate
		{"type": "caravan_done", "team": 0},
		{"type": "capture", "who": 0, "team": 0},
	]
	for e in evs:
		Challenges.note_event(e)
	var ctx := {"mode": "caravan", "arena": "caravan_pass", "hp": 1.0, "team": 0, "teams": {0: 0, 1: 1, 2: 0, 3: 1}}
	Challenges.note_match(_report(true, "cpu", ["cairn"]), _rows(0, 2, 6, 3), ctx)
	var want := {"guard_breaks": 1, "surge_kos": 1, "ring_outs": 1, "dodge_cancels": 1, "breakaways": 0,
		"meteor_untouched": 1, "boulders_sent_back": 1, "boulder_hits": 1, "caravan_finishes": 1,
		"flag_captures": 1, "kos": 2, "blocks": 3, "combo_5": 1, "combo_10": 0, "flawless_wins": 1,
		"clutch_wins": 0, "wins_on:caravan_pass": 1, "maps_won": 1}
	for c in want:
		assert_eq(Challenges.count(String(c)), int(want[c]), "%s:" % c)
	for id in ["guard_break", "surge_ko", "ring_out", "dodge_cancel", "meteor_untouched", "boulder_back",
			"boulder_hit", "caravan_finish", "flag_capture", "combo_5", "flawless_win", "first_ko"]:
		assert_true(Challenges.done(id), "%s is done" % id)
	assert_false(Challenges.done("breakaway"), "slot 1's breakaway isn't ours")
	# A Chaos Cup won with a sliver of health, hurt along the way.
	Challenges.begin_match()
	Challenges.note_event({"type": "hit", "attacker": 1, "target": 0, "move_type": "light", "dealt": 50.0, "power": 50.0})
	Challenges.note_match(_report(true), _rows(), {"mode": "chaos", "arena": "stadium", "hp": 0.05})
	assert_true(Challenges.done("clutch_win") and Challenges.done("chaos_cup_win") and Challenges.done("brawl_win"),
		"a clutch Chaos Cup win (a Brawl too)")
	assert_eq(Challenges.count("flawless_wins"), 1, "hurt: no flawless win:")
	# An Arcade clear on Hard counts for Easy, Normal and Hard; local play counts player 1 only.
	Challenges.begin_match()
	var r := _report(true)
	r["clear_arcade"] = true
	r["cpu_level"] = 2
	Challenges.note_match(r, _rows(), {"mode": "arcade"})
	assert_true(Challenges.done("arcade_easy") and Challenges.done("arcade_normal") and Challenges.done("arcade_hard"), "")
	assert_false(Challenges.done("arcade_rage"), "")
	Challenges.begin_match()
	var before := Challenges.count("wins_as:pete")
	Challenges.note_match({"kind": "local", "players": [
		{"slot": 0, "fighters": ["digby"], "won": false, "kos": 0},
		{"slot": 1, "fighters": ["pete"], "won": true, "kos": 0}]}, _rows(), {"mode": "versus"})
	assert_eq(Challenges.count("wins_as:pete"), before, "player 2's win isn't the account's:")
	_done()


func test_the_save_round_trips_and_an_old_or_odd_file_reads_empty() -> void:
	var p := _fresh()
	Challenges.note_match(_report(true, "cpu", ["sno"]), _rows(0, 3), {"mode": "versus", "arena": "quarry"})
	var counts := {"fights": Challenges.count("fights"), "wins_as:sno": Challenges.count("wins_as:sno"),
		"kos": Challenges.count("kos"), "maps_won": Challenges.count("maps_won")}
	assert_eq(counts["kos"], 3, "")
	Progress.reset_for_tests(p)  # read it back from the file
	for c in counts:
		assert_eq(Challenges.count(String(c)), int(counts[c]), "%s survives a reload:" % c)
	assert_true(Challenges.done("first_win") and Challenges.done("first_ko"), "and what's done")
	# An old file (no "challenges" key) and an odd one (wrong types) read as empty.
	for text in ['{"xp": 120, "arcade": {"cairn": 1}}', '{"challenges": "nope"}',
			'{"challenges": {"counts": [1, 2], "done": "first_win"}}', '{"challenges": {"counts": {"fights": "x"}}}']:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		Progress.reset_for_tests(p)
		assert_eq(Challenges.count("fights"), 0, "%s: no fights" % text)
		assert_false(Challenges.done("first_win"), "%s: nothing done" % text)
		assert_eq(Challenges.done_count(), 0, "")
	assert_eq(Progress.account_xp(), 0, "")
	Progress.reset_for_tests(p)
	var f2 := FileAccess.open(p, FileAccess.WRITE)
	f2.store_string('{"xp": 120}')
	f2.close()
	Progress.reset_for_tests(p)
	assert_eq(Progress.account_xp(), 120, "the old file's XP is still there")
	_done()


func test_off_and_unpaid_matches_count_nothing() -> void:
	var p := _fresh()
	Progress.set_enabled(false)
	Challenges.note_event({"type": "dodge", "who": 0, "cancel": true})
	assert_true(Challenges.note_match(_report(true), _rows(0, 5, 12), {"mode": "brawl"}).is_empty(), "Off: nothing paid")
	assert_eq(Challenges.completed_this_match(), [], "")
	Progress.set_enabled(true)
	assert_eq(Challenges.count("fights"), 0, "Off: no fights counted:")
	assert_eq(Challenges.count("dodge_cancels"), 0, "nor events:")
	assert_false(FileAccess.file_exists(p), "and the save isn't written")
	Challenges.begin_match()
	Challenges.note_match(_report(true, "none"), _rows(0, 5), {"mode": "versus"})
	assert_eq(Challenges.count("fights"), 0, "training, showcases, replays, CPU vs CPU: nothing:")
	assert_eq(Progress.grant_xp(0, "x"), {}, "no XP for nothing")
	Progress.set_enabled(false)
	assert_eq(Progress.grant_xp(100, "x"), {}, "Off: grant_xp gives nothing")
	assert_false(Progress.grant_unlock("title:champion"), "nor grant_unlock")
	Progress.set_enabled(true)
	assert_eq(Progress.account_xp(), 0, "")
	_done()


func test_the_challenges_page_lists_every_goal_by_group_with_done_ones_last() -> void:
	_fresh()
	Challenges.note_match(_report(true, "cpu", ["crease"]), _rows(0, 1, 5), {"mode": "versus", "arena": "stadium", "hp": 0.5})
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	Progress.set_enabled(true)
	g._open_menu("profile:challenges")
	var top := g.ui.top() as ProfileScreen
	assert_true(top != null and top.page == "challenges", "--menu=profile:challenges opens it")
	assert_eq(top.subtitle, "%d of %d done" % [Challenges.done_count(), Challenges.goals().size()], "the header:")
	var rows: Array = []
	for r in top.rows():
		if r is OptionRow:
			rows.append(r)
	assert_eq(rows.size(), Challenges.goals().size(), "a row per goal:")
	# Within a group the done ones come last; each row's name and tick end before its bar.
	var by_name := {}
	for gl in Challenges.goals():
		by_name[String(gl["name"])] = gl
	var last_group := ""
	var seen_done := false
	for o in rows:
		var row := o as OptionRow
		var gl: Dictionary = by_name[row.label]
		if String(gl["group"]) != last_group:
			last_group = String(gl["group"])
			seen_done = false
		var d := Challenges.done(String(gl["id"]))
		assert_false(seen_done and not d, "%s: an open goal after a done one" % row.label)
		seen_done = seen_done or d
		assert_eq(row.ticked, d, "%s ticked when done:" % row.label)
		assert_true(row.bar >= 0.0, "%s has a bar" % row.label)
		var font := row.get_theme_font("font")
		var fs := row.get_theme_font_size("font_size")
		var end := row.get_theme_stylebox("normal").get_margin(SIDE_LEFT) \
			+ font.get_string_size(row.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0
		assert_true(end <= row.bar_rect().position.x, "%s's name and tick end before its bar (%d > %d)" % [
			row.label, end, row.bar_rect().position.x])
		assert_true(row.bar_rect().end.x <= row._value_rect().position.x, "%s's bar ends before its count" % row.label)
	g.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	_done()
