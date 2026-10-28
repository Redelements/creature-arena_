extends TestCase
## The performance overlay (Settings > Video, F9 in a fight): off by default, three modes
## kept across launches, F9 cycles them mid-match, and it measures without touching the
## match (a CPU match plays the same with it on).

const MAIN := preload("res://src/game/main.gd")
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


func test_fights_default_to_60_fps_on_mobile_and_144_elsewhere() -> void:
	# The Odin 3's release build holds 60 clean; at 120 the tick frames don't fit.
	var main_script: GDScript = load("res://src/game/main.gd")
	assert_eq(main_script.default_fps(true), 60, "mobile:")
	assert_eq(main_script.default_fps(false), 144, "desktop:")
	assert_true(main_script.default_fps(true) in main_script.FPS_CHOICES, "a choice the setting offers")
	var g := _game()
	assert_eq(g.fight_fps, main_script.default_fps(), "this platform's default:")
	g.free()


func test_the_fight_cap_row_says_when_the_screen_is_60_hz() -> void:
	var g := _game()
	var desc: Callable = g.settings_ctl.fps_desc
	assert_true("refreshes 60 times a second" in desc.call(120, 60.0, true), "120 on a 60 Hz phone: " + desc.call(120, 60.0, true))
	assert_true("display settings" in desc.call(120, 60.0, true), "a phone gets the pointer to its own setting")
	assert_false("display settings" in desc.call(120, 60.0, false), "a PC doesn't")
	assert_true("refreshes 60 times" in desc.call(0, 59.94, false), "Unlimited on 59.94 Hz (rounded)")
	assert_true("refreshes 50 times" in desc.call(60, 50.0, false), "the measured rate")
	for quiet in [[60, 60.0], [120, 120.0], [120, 0.0], [144, 144.0]]:
		assert_false("refreshes" in desc.call(quiet[0], quiet[1], true), "no hint at cap %d on %.0f Hz" % quiet)
	assert_eq(MAIN.default_fps(true), 60, "the mobile default stays 60:")
	# The row itself, on a stubbed 60 Hz screen: the hint follows the chosen cap.
	g._refresh = 60.0
	g._set_setting("fps", MAIN.FPS_CHOICES.find(120))
	assert_true("refreshes 60 times" in String(g._setting("fps")["desc"]), "120 chosen: the hint")
	g._set_setting("fps", MAIN.FPS_CHOICES.find(60))
	assert_false("refreshes" in String(g._setting("fps")["desc"]), "60 chosen: no hint")
	g.free()


func test_the_perf_setup_line_names_the_warmup() -> void:
	var g := _game()
	assert_true(String(g._perf_setup()).ends_with("warmup off"), "headless: no warm-up: " + g._perf_setup())
	var w := ShaderWarmup.new()
	_root().add_child(w)
	g.shader_warmup = w
	assert_true("warmup running (0 of " in String(g._perf_setup()), "before it ends: " + g._perf_setup())
	while not w.done:
		w.step()
	assert_true(" draws in " in String(g._perf_setup()), "after: " + g._perf_setup())
	w.free()
	g.free()
	var log := PerfLog.new()
	var frames := PackedFloat32Array([41.0, 8.0, 9.0])
	assert_eq(PerfLog.first_frames(frames), "PERF first 3 fight frames (left out above) ms: first 41.0, avg 19.33, slowest 41.0 at frame 1", "")
	assert_true("first fight frames" in log.report(60) or "PERF first fight frames: no samples" in log.report(60), "in the report")


func test_rematch_after_presses_rematch_on_the_results_screen() -> void:
	# --rematch-after=N (soak runs, tools/odin_perf.py --soak): back-to-back offline fights.
	var g := _game()
	g._skip_select = true
	g._rematch_after = 30
	g._start_match(2)
	for i in 5:
		g._physics_process(1.0 / 60.0)
	g.flow = g.Flow.MATCH_OVER
	g.show_ctl._show_match_over()
	assert_eq(g._rematch_at, g.frame_count + 30, "pending:")
	var seed: int = g.seed_base
	g.frame_count += 29
	g._capture()
	assert_eq(g.flow, g.Flow.MATCH_OVER, "not yet:")
	g.frame_count += 1
	g._capture()
	assert_true(g.flow != g.Flow.MATCH_OVER, "a new match started")
	assert_eq(g.seed_base, seed + 1, "a new seed, as the Rematch button:")
	assert_eq(g._rematch_at, 0, "")
	g.free()
	var off := _game()
	off._skip_select = true
	off._start_match(2)
	off.flow = off.Flow.MATCH_OVER
	off.show_ctl._show_match_over()
	assert_eq(off._rematch_at, 0, "off by default:")
	off.free()
