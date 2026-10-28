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
			if av.tiled():
				# a tiled map draws its own chasms from the overlay tiles, not from the picture
				var cell := Vector2i(k % keeps.terrain.cols, k / keeps.terrain.cols)
				assert_false(av._in_art(k), "tiles, not the picture, draw the map's own chasm:")
				assert_true(av._overlay.get_cell_source_id(cell) != -1, "a chasm tile over it:")
			else:
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


func test_cpus_thinking_in_the_frame_between_ticks_choose_what_they_would_in_the_tick() -> void:
	# Gap mode (the default on mobile): the next tick's CPU inputs are worked out on the main
	# thread in a frame that steps no tick. Here each tick is followed by such a frame; the
	# match must play out input for input as when the CPUs think in the tick, and the tick
	# must have used the gap's answers.
	var frames := []
	var used := 0
	var split := 0
	for gap in [true, false, true]:
		var g := _game()
		g._cpus_early = gap
		g.cpu_think = "gap"
		if gap and frames.size() == 2:
			g.gap_budget_us = 0  # one CPU in the gap, the other five in the tick
		g._cpu_vs_cpu = true
		g._start_match(32)  # Team Deathmatch 3v3, every slot a CPU
		g._on_teams_chosen([["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]])
		for i in 400:
			g._physics_process(1.0 / 60.0)
			if gap:
				g._think_in_gap()  # the same frame as the tick: must not think yet
				assert_true(g._cpu_ahead.is_empty() or i == 0, "not in the tick's own frame")
				g._gap_process_frame = -2  # the next frame, with no tick in between
				g._think_in_gap()
				if not g._cpu_ahead.is_empty():
					used += 1
				if g._gap_done == 1:
					split += 1
		assert_gt(float(g.replay.frames.size()), 200.0, "the fight ran:")
		frames.append(var_to_str(g.replay.frames))
		g.free()
	assert_gt(float(used), 600.0, "the ticks took the gap's answers:")
	assert_gt(float(split), 300.0, "with no budget, the gap thought for one CPU and the tick the rest:")
	assert_true(frames[0] == frames[1], "thinking in the gap gives the same inputs, tick for tick")
	assert_true(frames[2] == frames[1], "and so does a gap that runs out of time")


## The water surface as it was painted before the fast path (WaterView._paint_surface up to
## Oct 2026, per pixel, every hash and lookup on the spot), as the same 4-int runs.
func _water_specks_plain(w: WaterView, view: Rect2, step: int, tick: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var phase := tick / 28
	var x0 := floori(view.position.x)
	var x1 := ceili(view.end.x)
	var y0 := floori(view.position.y)
	var y1 := ceili(view.end.y)
	var lat := WaterView.LATTICE
	for k in range(floori((y0 - step) / float(lat.y)) - 1, floori((y1 - step) / float(lat.y)) + 2):
		for g in range(floori(x0 / float(lat.x)) - 1, floori(x1 / float(lat.x)) + 2):
			var h := WaterView._hash(g, k)
			if h % 100 >= 46:
				continue
			var ln := 2 + (h >> 7) % 3
			var x := g * lat.x + (h >> 11) % (lat.x - 3) + (k & 1) * 3
			var y := k * lat.y + step + (h >> 17) % 3
			if y < y0 or y > y1 or x < x0 or x > x1:
				continue
			if not w._deep(x, y) or not w._deep(x + ln, y):
				continue
			var tone := ((h >> 3) + phase) % 4
			if tone == 3:
				continue
			out.append_array([x, y, ln, 6 if tone == 0 else 5])
			if ln > 2:
				out.append_array([x + 1, y + 1, ln - 2, 1])
	var inset := roundi(w._bank)
	var far := inset + (2 if inset > 0 else 0)
	for e in w._edges:
		var ex := int(e[0])
		var ey := int(e[1])
		if ex + 8 < x0 or ex > x1 or ey + 8 < y0 or ey > y1:
			continue
		for u in 8:
			var px := ex + int(e[2]) * u
			var py := ey + int(e[3]) * u
			var h0 := WaterView._hash(px * 5 + int(e[4]) * 11, py * 5 + int(e[5]) * 11)
			var t := (tick + h0 % WaterView.FOAM_TICKS) / WaterView.FOAM_TICKS
			var h2 := WaterView._hash(px * 3 + int(e[4]) * 7, py * 3 + int(e[5]) * 7 + t * 1009)
			var depth := -1
			if h2 % 7 < 2:
				depth = 1 + (h2 >> 5) % WaterView.EDGE_DEPTH
			elif h2 % 7 == 2:
				depth = 0
			if depth < 0:
				continue
			var qx := px + int(e[4]) * (depth + (far if int(e[5]) == 1 else inset))
			var qy := py + int(e[5]) * (depth + (far if int(e[5]) == 1 else inset))
			if inset > 0 and not w._clear_of_bank(qx, qy, inset, far):
				continue
			out.append_array([qx, qy, 1, 6 if depth <= 1 else 5])
	return out


## The water surface redraws with its fixed parts worked out once per floor and its lookups
## inlined (it cost 3-6 ms a redraw on Twin Keeps): every run it paints is the one the plain
## per-pixel version painted, on both water maps, with and without a drawn bank, at many
## flow steps and ticks, over the whole water and over a corner of it.
func test_the_water_surface_paints_what_the_plain_version_did() -> void:
	for arena in ["floodgate", "twin_keeps"]:
		var was: String = MatchFactory.arena
		MatchFactory.arena = arena
		var sim := MatchFactory.versus("cairn", "culvert")
		MatchFactory.arena = was
		for bank in [0.0, ArenaView.WATER_BANK]:
			var w := WaterView.new()
			w.set_sim(sim, bank, ArtScale.TILE_CELLS)
			assert_true(w._any_water, "%s has water" % arena)
			var corner := Rect2(w._bounds.position, w._bounds.size * 0.4)
			for tick: int in [0, 9, 10, 57, 333, 1234, 4000]:
				var step := tick / WaterView.STEP_TICKS
				for view: Rect2 in [w._bounds, corner]:
					var fast := w.surface_specks(view, step, tick)
					var plain := _water_specks_plain(w, view, step, tick)
					assert_gt(plain.size(), 40, "%s paints something" % arena)
					assert_eq(fast, plain, "%s bank %s tick %d %s:" % [arena, bank, tick, view])
			w.free()


## A tiled map's overlay, edge and corner tiles, worked out cell by cell the plain way
## (ArenaView._retile up to Oct 2026), against what the layers hold.
func _tiles_mismatch(v: ArenaView) -> String:
	var t := v.terrain
	for cy in t.rows:
		for cx in t.cols:
			var c := t.cells[cy * t.cols + cx]
			var pit := v._pit_at(cx, cy)
			var id := -1
			if pit:
				id = ArenaView.overlay_tile(c, v._pit_depth(cx, cy), c == TerrainGrid.CHASM, 0, cx % 2 == 1)
			elif c == TerrainGrid.CRACKED:
				var joins := (1 if v._crack_link(cx - 1, cy, cx, cy) else 0) | (2 if v._crack_link(cx, cy, cx + 1, cy) else 0) \
					| (4 if v._crack_link(cx, cy - 1, cx, cy) else 0) | (8 if v._crack_link(cx, cy, cx, cy + 1) else 0)
				id = ArenaView.overlay_tile(c, 0, false, ArenaView._h(cx, cy, 3), false, joins)
			var eid := ArenaView.edge_tile(v._pit_at(cx - 1, cy), v._pit_at(cx + 1, cy), v._pit_at(cx, cy + 1)) if pit else -1
			var kid := -1
			if pit:
				var l := v._pit_at(cx - 1, cy)
				var r := v._pit_at(cx + 1, cy)
				var u := v._pit_at(cx, cy - 1)
				var d := v._pit_at(cx, cy + 1)
				kid = ArenaView.corner_tile(l and u and not v._pit_at(cx - 1, cy - 1), r and u and not v._pit_at(cx + 1, cy - 1),
					l and d and not v._pit_at(cx - 1, cy + 1), r and d and not v._pit_at(cx + 1, cy + 1))
			var at := Vector2i(cx, cy)
			var want := [id, eid, kid]
			var layers := [v._overlay, v._edges, v._corners]
			for w in 3:
				var layer: TileMapLayer = layers[w]
				var got := -1 if layer.get_cell_source_id(at) == -1 else layer.get_cell_atlas_coords(at).x + ArenaView.OV_COLS * layer.get_cell_atlas_coords(at).y
				if got != int(want[w]):
					return "cell %s layer %d: %d, the plain way %d" % [at, w, got, want[w]]
	return ""


## A tiled map sets only the tiles that changed, with the pits of the rows looked up once and
## each run of dirty bands retiled at once (a pit opening cost 2-7 ms in 4v4 CTF): after
## cracks, pits, a chasm and healing, every cell's tiles are the ones the plain way gives.
func test_a_tiled_floor_change_sets_the_tiles_the_plain_way_did() -> void:
	for arena in ["stadium", "twin_keeps", "floodgate"]:
		var was: String = MatchFactory.arena
		MatchFactory.arena = arena
		var sim := MatchFactory.versus("cairn", "culvert")
		MatchFactory.arena = was
		var v := ArenaView.new()
		v.ground = String(sim.arena.get("ground", "dirt"))
		v.arena_id = arena
		v.set_terrain(sim.terrain)
		assert_true(v.tiled(), "%s is tiled" % arena)
		assert_eq(_tiles_mismatch(v), "", "%s at the start:" % arena)
		var t := sim.terrain
		var mid := sim.floor_rect().get_center()
		t.crack_circle(mid + Vector2(-60, 0), 30.0)
		t.damage_circle(mid + Vector2(40, 10), 26.0, 14.0)
		for x in range(-3, 4):
			t.sink(t.world_to_cell(mid + Vector2(x * 8, -50)))
		v.refresh()
		assert_gt(v._overlay.get_used_cells().size(), 20, "%s: cracks and pits have tiles" % arena)
		assert_gt(v._edges.get_used_cells().size(), 2, "%s: and the pits edges" % arena)
		assert_eq(_tiles_mismatch(v), "", "%s broken:" % arena)
		for k in 400:
			t.tick()
		v.refresh()
		assert_eq(_tiles_mismatch(v), "", "%s partly healed:" % arena)
		for k in 4000:
			t.tick()
		v.refresh()
		assert_eq(_tiles_mismatch(v), "", "%s healed:" % arena)
		v.free()


## The bloom's two half-size viewports render once a tick (the emitters redraw then), when
## the camera moves or the window resizes, never again for the frames between ticks, which
## show the same state (no interpolation): the picture they hold is the same one.
func test_the_bloom_renders_on_a_tick_not_every_frame() -> void:
	var b := BloomView.new()
	_root().add_child(b)
	b.set_on(true)
	var vp := _root().get_viewport()
	var was := vp.canvas_transform
	b.frame(vp)
	var n := b.renders
	for i in 10:
		b.frame(vp)
	assert_eq(b.renders, n, "frames between ticks render nothing:")
	assert_eq(b._vp_a.render_target_update_mode, SubViewport.UPDATE_ONCE, "the last render is still to come")
	b.advance()
	assert_eq(b.renders, n + 1, "a tick renders once:")
	for i in 3:
		b.frame(vp)
	assert_eq(b.renders, n + 1, "and the frames after it don't:")
	vp.canvas_transform = was.translated(Vector2(3, 0))
	b.frame(vp)
	assert_eq(b.renders, n + 2, "the camera moving renders:")
	vp.canvas_transform = was
	b.set_on(false)
	assert_eq(b._vp_a.render_target_update_mode, SubViewport.UPDATE_DISABLED, "off: nothing renders")
	b.advance()
	b.frame(vp)
	assert_eq(b.renders, n + 2, "nor on a tick:")
	b.out.free()  # main puts it on the screen layer; here it was never in the tree
	b.free()
