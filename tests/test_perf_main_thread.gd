extends TestCase
## The main thread's work per tick, kept small: FxView draws only what's near the screen, a
## floor change repaints its bands over a few frames, the crowd's camera flashes don't
## redraw the seats, a Surge aura skips a fighter off screen, PerfLog ignores a worker
## thread (the CPU players' probes once stalled the game before its first tick), and main
## joins the CPU threads at the next tick, or first on a press (never on mouse motion).
## The --perf report reads the frames as fps: the 1% and 0.1% lows, missed refreshes, the
## slowest second.

const TEST_SETTINGS := "user://test_perf_main_thread.cfg"


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


func test_particles_off_screen_are_not_drawn() -> void:
	var view := Rect2(0, 0, 480, 270).grow(FxView.CULL_PAD)
	assert_true(FxView._in_view({"pos": Vector2(100, 100)}, view), "on screen")
	assert_true(FxView._in_view({"pos": Vector2(-100, 100)}, view), "just off, within the pad")
	assert_false(FxView._in_view({"pos": Vector2(-1000, 100)}, view), "far off")
	assert_true(FxView._in_view({"kind": "rain"}, view), "one without a position always draws")
	var loose := Node2D.new()
	assert_true(FxView._view_rect(loose, 0.0).has_point(Vector2(1e8, -1e8)), "no screen: everything is in view")
	_root().add_child(loose)
	var on := FxView._view_rect(loose, 0.0)
	assert_true(on.has_point(Vector2(10, 10)), "on screen, in the tree")
	assert_false(on.has_point(Vector2(-1000, 10)), "off screen, in the tree")
	loose.free()


func test_a_floor_change_repaints_its_bands_over_a_few_frames() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var av := ArenaView.new()
	_root().add_child(av)
	av.set_terrain(sim.terrain)
	av.refresh()
	assert_true(av._pending.is_empty(), "nothing to repaint at the start")
	sim.terrain.crack_circle(sim.floor_rect().get_center(), 40.0)
	av.refresh()
	var bands := av._pending.size()
	assert_gt(float(bands), 1.0, "a 40 px circle dirties more than one band (%d)" % bands)
	av.refresh()
	assert_eq(av._pending.size(), bands, "the same change doesn't queue them twice:")
	for i in ArenaView.SPREAD_FRAMES:
		av._process(0.0)
	assert_true(av._pending.is_empty(), "all repainted within SPREAD_FRAMES frames")
	av.free()


func test_crowd_flashes_have_their_own_layer() -> void:
	var crowd := CrowdView.new()
	_root().add_child(crowd)
	assert_true(crowd._flash_layer != null and crowd._flash_layer.get_parent() == crowd, "a flash layer over the seats")
	crowd.advance()
	crowd.advance()  # the seats' key is settled for a few ticks now
	var keys := crowd._blocks.map(func(b): return [b.drawn, b.drawn_version])
	crowd._flashes.append({"pos": Vector2(10, 10), "t": 3})
	crowd.advance()
	assert_eq(crowd._blocks.map(func(b): return [b.drawn, b.drawn_version]), keys, "a flash doesn't re-key the seats:")
	assert_true(crowd._drawn_flashes, "the flash layer is what redraws")
	crowd.free()


func test_an_aura_off_screen_is_not_drawn() -> void:
	var a := SurgeAura.new()
	_root().add_child(a)
	a.position = Vector2(100, 100)
	assert_true(a._on_screen(), "on screen")
	a.position = Vector2(-2000, 100)
	assert_false(a._on_screen(), "far off")
	a.free()


func test_perf_log_ignores_worker_threads() -> void:
	var log := PerfLog.new()
	PerfLog.current = log
	var t0 := PerfLog.now()
	assert_gt(t0, 0, "main records")
	PerfLog.since("main part", t0)
	var task := WorkerThreadPool.add_task(func() -> void:
		var t := PerfLog.now()
		PerfLog.since("worker part", t))
	WorkerThreadPool.wait_for_task_completion(task)
	PerfLog.current = null
	assert_true(log._part_us.has("main part"), "the main thread's probe counted")
	assert_false(log._part_us.has("worker part"), "a worker thread's didn't")


func test_main_joins_the_cpu_threads_on_a_press_not_on_mouse_motion() -> void:
	var g := _game()
	g._cpus_early = true
	g._cpu_vs_cpu = true
	g._start_match(32)  # Team Deathmatch 3v3, every slot a CPU
	g._on_teams_chosen([["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]])
	_tick(g, 5)
	assert_true(g._cpu_task >= 0, "the CPUs are thinking ahead after a tick")
	g._input(InputEventMouseMotion.new())
	assert_true(g._cpu_task >= 0, "mouse motion leaves them to it")
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	g._input(key)
	assert_eq(g._cpu_task, -1, "a press joins them first:")
	_tick(g, 1)
	assert_true(g._cpu_task >= 0, "and they go again")
	g.free()


func test_sunk_floor_is_drawn_over_the_arena_art() -> void:
	# Sinkhole's fallen rings and the Floor of pits mutator used to be invisible on a map
	# with art: the view took every chasm whose heal target is a chasm for one of the map's
	# own, already in the picture. Only the map's own chasms (`map_base`) are in it.
	var sim := MatchFactory.versus("cairn", "culvert")
	var av := ArenaView.new()
	_root().add_child(av)
	av.arena_id = "stadium"
	assert_true(av._art != null, "the stadium has art")
	av.set_terrain(sim.terrain)
	var c := sim.terrain.world_to_cell(sim.floor_rect().get_center())
	var i := c.y * sim.terrain.cols + c.x
	assert_false(av._in_art(i), "floor is not a chasm in the picture")
	sim.terrain.sink(c)
	assert_false(av._in_art(i), "a cell sunk during the match is drawn, not left to the art:")
	var keeps := MatchSim.new()
	keeps.set_arena("twin_keeps")
	av.arena_id = "twin_keeps"
	av.set_terrain(keeps.terrain)
	var found := false
	for k in keeps.terrain.cells.size():
		if keeps.terrain.cells[k] == TerrainGrid.CHASM:
			assert_true(av._in_art(k) or av._art == null, "the map's own chasm is in its art:")
			found = true
			break
	assert_true(found, "twin_keeps has a chasm")
	av.free()


func test_a_smaller_map_after_a_big_one_never_draws_the_old_bands() -> void:
	# Capture the Flag on Twin Keeps, then the menu's stadium: the old bands were only
	# queue_free'd, so they drew once more that frame with Twin Keeps' rows over the
	# stadium's smaller grid (index out of bounds in _paint_pit_band).
	var av := ArenaView.new()
	_root().add_child(av)
	var keeps := MatchSim.new()
	keeps.set_arena("twin_keeps")
	av.arena_id = "twin_keeps"
	av.set_terrain(keeps.terrain)
	var sim := MatchFactory.versus("cairn", "culvert")
	assert_true(sim.terrain.rows < keeps.terrain.rows, "the stadium is the smaller map")
	av.arena_id = "stadium"
	av.set_terrain(sim.terrain)
	for b in av.get_children():
		if b is ArenaView.Band:
			assert_true(b.row1 <= sim.terrain.rows, "every band in the tree fits the new map:")
	av.free()


func test_the_report_gives_the_lows_missed_frames_and_the_slowest_second() -> void:
	# 2000 frames at 120 fps with two missed refreshes (each shown for two frames) close
	# together, so one second of the fight holds both.
	var f := PackedFloat32Array()
	for i in 2000:
		f.append(1000.0 / 120.0)
	f[1500] = 2000.0 / 120.0
	f[1530] = 2000.0 / 120.0
	var line := PerfLog.lows(f, 120, 0)
	assert_true(line.contains("missed 2 of 2000"), line)
	assert_true(line.contains("0.1% low 60.0"), "the slowest 2 frames are 60 fps: " + line)
	assert_true(line.contains("1% low 109.1"), "20 frames, 2 of them doubled: " + line)
	assert_true(line.contains("slowest second 118.0"), "120 refreshes hold 118 frames: " + line)


func test_fps_pacing_vsync_paces_a_cap_at_the_screens_rate() -> void:
	var M := preload("res://src/game/main.gd")
	assert_eq(M.pace_cap(120, 120.0, true), 120, "by default the limiter, as before")
	assert_eq(M.pace_cap(120, 120.0, true, "vsync"), 0, "120 on a 120 Hz screen: vsync paces it")
	assert_eq(M.pace_cap(120, 119.88, true, "vsync"), 0, "a screen a hair under 120 too")
	assert_eq(M.pace_cap(120, 120.0, false, "vsync"), 120, "no vsync: the limiter")
	assert_eq(M.pace_cap(144, 360.0, true, "vsync"), 144, "under the screen's rate: the limiter")
	assert_eq(M.pace_cap(60, 0.0, true, "vsync"), 60, "a rate the screen doesn't report: the limiter")
