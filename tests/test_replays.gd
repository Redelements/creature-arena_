extends TestCase
## Replay theater: a saved fight carries its setup, and watching it rebuilds the same
## match and plays the same inputs, slot by slot, until they run out.

const TEST_SETTINGS := "user://test_settings_replays.cfg"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


func test_a_saved_brawl_plays_back_the_same() -> void:
	var g := _game()
	g._skip_select = true  # (like --mode=N: no pick screen)
	g._start_match(g.mode_index("Chaos Cup"))  # Chaos Cup: a Brawl with mutators, the hardest setup to rebuild
	_tick(g, 240)
	assert_true(g.brawl != null, "a Brawl is on")
	var digest: String = g.sim.state_digest()
	var frames: int = g.replay.frames.size()
	assert_eq(frames, 240, "every tick recorded:")
	var setup = g.replay.setup
	assert_true(setup is Dictionary and setup["kind"] == "brawl", "the setup names the mode")
	assert_eq((setup["mutators"] as Dictionary).size() > 0, true, "and its mutators")
	var path := "user://replays/replay_test_%d.json" % Time.get_ticks_usec()
	assert_eq(g.replay.save(path), OK, "saved:")
	g._play_replay(path)
	assert_eq(g.mode, g.REPLAY_MODE, "watching:")
	for s in g.sides:
		assert_eq(s, g.Side.REPLAY, "every side plays the recording:")
	assert_true(g.brawl != null and g.brawl != null, "a Brawl again")
	_tick(g, 240)
	assert_eq(g.sim.state_digest(), digest, "the same fight, tick for tick:")
	_tick(g, 3)
	assert_eq(g.flow, g.Flow.MATCH_OVER, "out of inputs: over:")
	assert_eq(g.hud.banner, "END OF REPLAY", "and says so:")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	g.free()


func test_a_replay_of_a_removed_mode_is_refused() -> void:
	# Showtime was removed: its replays would rebuild as a plain team battle and desync.
	var setup := {"kind": "team", "ids": ["cairn", "culvert"], "teams": [["cairn"], ["culvert"]],
		"size": 1, "rules": "showtime", "arena": "stadium"}
	assert_eq(ReplayBuilder.unsupported(setup), ReplayBuilder.REMOVED_MODE, "a removed rules id:")
	for id in TeamSim.RULE_IDS:
		var ok := setup.duplicate()
		ok["rules"] = id
		assert_eq(ReplayBuilder.unsupported(ok), "", "%s still plays:" % id)
	assert_eq(ReplayBuilder.unsupported({"kind": "brawl"}), "", "other kinds play")
	var g := _game()
	g._open_menu("single")
	var rep := Replay.new()
	rep.setup = setup
	rep.record(PackedInt32Array([0, 0]))
	var path := "user://replays/replay_test_removed_%d.json" % Time.get_ticks_usec()
	assert_eq(rep.save(path), OK, "saved:")
	g._play_replay(path)
	assert_true(g.mode != g.REPLAY_MODE, "the theater doesn't start it")
	assert_true(g.team_battle == null, "no team battle built")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	g.free()


func test_the_menu_rows_start_the_modes_they_name() -> void:
	var g := _game()
	for name in ["Arcade", "Gauntlet", "Daily Challenge", "Chaos Cup"]:
		var row: Dictionary = g.MENU_ROWS.filter(func(r): return r["label"] == name)[0]
		assert_eq(int(row["modes"][0]), g.mode_index(name), "%s row:" % name)
	var brawl: Dictionary = g.MENU_ROWS.filter(func(r): return r["label"] == "Brawl")[0]
	assert_eq(brawl["modes"], [g.mode_index("Brawl: you vs 3 CPUs"), g.mode_index("Brawl: 2 players"),
		g.mode_index("Brawl: 3 players"), g.mode_index("Brawl: 4 players")], "Brawl rows:")
	assert_eq(g.REPLAY_MODE, g.mode_index("Replay"), "the replay mode:")
	assert_eq(g.ONLINE_MODE, g.mode_index("Online 1v1"), "the online mode:")
	for row in g.MENU_ROWS:
		for m in row.get("modes", []):
			assert_true(int(m) >= 0 and int(m) < g.MODES.size(), "%s: a real mode" % row["label"])
	g.free()


func test_the_theater_lists_saved_replays() -> void:
	var g := _game()
	g._start_match(2)  # CPU vs CPU versus
	_tick(g, 30)
	var path := "user://replays/replay_2099-01-01T00-00-00.json"
	g.replay.save(path)
	g._open_menu("single")
	g._open_replays()
	var scr: UiScreen = g.ui.top()
	var found := false
	for r in scr.rows():
		if r is Button and String((r as Button).text).contains("2099-01-01"):
			found = true
			assert_true(String((r as Button).text).contains("versus"), "the row names the kind")
	assert_true(found, "the saved replay is listed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	g.free()


## An offline round that starts with energy carried over (60 / 40) plays back the same, headless
## and through the theater. (A Versus round's sim idles through the 90-tick intro, and a replay
## side reads its frame by sim.tick, so the intro is recorded too.)
func test_a_replay_of_a_round_with_carried_energy_plays_back_the_same() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(0)
	g._carried_energy = [60.0, 40.0]
	g._start_round()
	assert_eq(g.replay.setup["energy"], [60.0, 40.0], "the setup keeps the starting meters:")
	_tick(g, 300)  # the intro, then 210 fight ticks
	var digest: String = g.sim.state_digest()
	assert_eq(g.replay.frames.size(), 300, "every tick recorded, the intro's included:")
	assert_eq(ReplayBuilder.play(g.replay), digest, "the rebuilt round reaches the same state:")
	var path := "user://replays/replay_test_%d.json" % Time.get_ticks_usec()
	assert_eq(g.replay.save(path), OK, "saved:")
	g._play_replay(path)
	assert_eq(g.sim.creatures[0].energy, 60.0, "the rebuilt round starts with the carried meter:")
	_tick(g, 300)
	assert_eq(g.sim.state_digest(), digest, "the same round, meters included:")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	g.free()
