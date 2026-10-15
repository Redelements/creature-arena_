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
	g._start_match(49)  # Chaos Cup: a Brawl with mutators, the hardest setup to rebuild
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
