extends TestCase
## The performance overlay (Settings > Video, F9 in a fight): off by default, three modes
## kept across launches, F9 cycles them mid-match, and it measures without touching the
## match (a CPU match plays the same with it on).

const TEST_SETTINGS := "user://test_perf_overlay.cfg"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _game(keep := false) -> Node:
	if not keep and FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	return g


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_root().push_input(ev)


func test_the_setting_is_kept_and_on_the_video_page() -> void:
	var g := _game()
	assert_eq(g.perf_overlay.mode, PerfOverlay.Mode.OFF, "off by default:")
	assert_false(g.perf_overlay.visible, "")
	assert_true("perf_overlay" in g.SETTING_PAGES["video"], "a row on the Video page")
	assert_eq(g._setting("perf_overlay")["values"], PerfOverlay.MODE_NAMES, "its choices:")
	g._set_setting("perf_overlay", PerfOverlay.Mode.GRAPH)
	assert_true(g.perf_overlay.visible, "on shows it")
	g.free()
	var again := _game(true)
	assert_eq(again.perf_overlay.mode, PerfOverlay.Mode.GRAPH, "kept after a restart:")
	again.free()


func test_f9_cycles_it_mid_match() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(0)
	for i in 5:
		g._physics_process(1.0 / 60.0)
	assert_eq(Controls.binding_text("debug_perf", g.player_input.layout), "F9", "F9 by default:")
	for want in [PerfOverlay.Mode.FPS, PerfOverlay.Mode.GRAPH, PerfOverlay.Mode.OFF]:
		_press("debug_perf")
		assert_eq(g.perf_overlay.mode, want, "F9 steps to")
	assert_true(KEY_F9 in RemapScreen.RESERVED_KEYS, "can't be bound to a fight key")
	g.free()


func test_it_measures_frames_and_ticks() -> void:
	var o := PerfOverlay.new()
	_root().add_child(o)
	o.mode = PerfOverlay.Mode.GRAPH
	for i in 30:
		o._process(0.0)
		OS.delay_usec(2000)
	o.tick(1500)
	o._update_text()
	assert_true(o._line1.contains("fps   1% low"), "an fps readout: " + o._line1)
	var fps := int(o._line1.get_slice(" ", 0))
	assert_true(fps > 50 and fps < 600, "about one frame each 2 ms (sleep is coarse): %d" % fps)
	assert_true(o._line2.begins_with("tick 1.5 ms"), "the tick's cost: " + o._line2)
	o.free()


func test_the_match_plays_the_same_with_it_on() -> void:
	var digests := []
	for mode in [PerfOverlay.Mode.OFF, PerfOverlay.Mode.GRAPH]:
		var g := _game()
		g._set_setting("perf_overlay", mode)
		g._skip_select = true
		g._start_match(2)  # CPU vs CPU
		for i in 240:
			g._physics_process(1.0 / 60.0)
			g.perf_overlay._process(1.0 / 60.0)
		digests.append(g.sim.state_digest())
		g.free()
	assert_eq(digests[0], digests[1], "the same match:")
