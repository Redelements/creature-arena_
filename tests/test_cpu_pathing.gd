extends TestCase
## The CPU finds its way round walls, fences and chasms: a coarse nav grid with
## integer costs (deterministic), consulted only when the straight line is blocked.


func _on(map: String, left := "cairn", right := "culvert") -> MatchSim:
	var was: String = MatchFactory.arena
	MatchFactory.arena = map
	var sim := MatchFactory.versus(left, right)
	MatchFactory.arena = was
	return sim


func _with(pieces: Array, left := "cairn", right := "culvert") -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.terrain.load_map({"pieces": pieces})
	return sim


func test_a_path_goes_round_the_quarry_wall() -> void:
	var sim := _on("quarry")
	var nav := NavGrid.new()
	nav.update(sim.terrain)
	var from := sim.terrain.cell_center(Vector2i(10, 18))  # left lane
	var to := sim.terrain.cell_center(Vector2i(42, 18))  # middle lane
	assert_false(NavGrid.clear_line(sim.terrain, from, to, 10.0), "the wall is in the way")
	sim.terrain.set_cell(Vector2i(10, 24), TerrainGrid.HOLE)
	var past_hole := sim.terrain.cell_center(Vector2i(10, 30))
	assert_false(NavGrid.clear_line(sim.terrain, from, past_hole, 10.0), "a hole blocks the line")
	assert_true(NavGrid.clear_line(sim.terrain, from, past_hole, 10.0, false), "unless holes are left to the steering")
	sim.terrain.set_cell(Vector2i(10, 24), TerrainGrid.INTACT)
	assert_true(NavGrid.clear_line(sim.terrain, from, sim.terrain.cell_center(Vector2i(10, 30)), 10.0), "open floor is clear")
	var path := nav.path(from, to)
	assert_true(path.size() > 0, "a path exists")
	var straight := from.distance_to(to)
	var length := 0.0
	var prev := from
	for p in path:
		length += prev.distance_to(p)
		prev = p
		assert_false(nav.is_blocked(nav.node_of(p)), "waypoint on open floor")
		assert_false(sim.terrain.solid_at(p), "waypoint not in a wall")
	assert_gt(length, straight * 1.2, "it goes round, not through")
	assert_lt(path[path.size() - 1].distance_to(to), 12.0, "ends at the goal's node:")


func test_the_same_path_twice() -> void:
	var sim := _on("quarry")
	var nav := NavGrid.new()
	nav.update(sim.terrain)
	var a := nav.path(sim.terrain.cell_center(Vector2i(5, 5)), sim.terrain.cell_center(Vector2i(70, 33)))
	var b := nav.path(sim.terrain.cell_center(Vector2i(5, 5)), sim.terrain.cell_center(Vector2i(70, 33)))
	assert_eq(a, b, "deterministic:")


func test_no_path_when_walled_in() -> void:
	var sim := _with([{"kind": "wall", "rect": [40, 0, 2, 36]}])
	var nav := NavGrid.new()
	nav.update(sim.terrain)
	var path := nav.path(sim.terrain.cell_center(Vector2i(10, 18)), sim.terrain.cell_center(Vector2i(70, 18)))
	assert_eq(path.size(), 0, "a wall across the whole floor cannot be passed:")


func _cpu_reaches(sim: MatchSim, level: int, limit: int) -> int:
	var cpu := CpuController.new(0, level, 5)
	var me := sim.creatures[0]
	var foe := sim.creatures[1]
	for t in limit:
		var bits := cpu.bits(sim)
		sim.step(PackedInt32Array([bits, 0]))
		if me.pos.distance_to(foe.pos) < 44.0:
			return t
	return -1


func test_every_cpu_level_walks_round_the_wall_to_the_foe() -> void:
	for level in [0, 1, 2, 3]:
		var sim := _on("quarry", "cairn", "culvert")
		sim.creatures[0].pos = sim.terrain.cell_center(Vector2i(8, 18))  # left lane
		sim.creatures[1].pos = sim.terrain.cell_center(Vector2i(42, 18))  # middle lane
		sim.creatures[1].facing = Vector2.LEFT
		var t := _cpu_reaches(sim, level, 900)
		assert_true(t >= 0, "level %d reached the foe round the wall" % level)
		assert_eq(sim.terrain.count(TerrainGrid.WALL), 2 * 2 * 26 + 4 * 8, "level %d: without smashing anything" % level)


func test_the_cpu_goes_round_a_chasm_and_through_a_gap_in_a_fence() -> void:
	var chasm := _with([{"kind": "chasm", "rect": [30, 0, 3, 30]}], "culvert", "cairn")  # a gap at the bottom
	chasm.creatures[0].pos = chasm.terrain.cell_center(Vector2i(10, 10))
	chasm.creatures[1].pos = chasm.terrain.cell_center(Vector2i(50, 10))
	assert_true(_cpu_reaches(chasm, 2, 900) >= 0, "round the chasm")
	assert_true(chasm.creatures[0].hp == chasm.creatures[0].max_hp, "without falling in")
	var fence := _with([{"kind": "fence", "rect": [30, 0, 1, 16]}, {"kind": "fence", "rect": [30, 20, 1, 16]}], "sno", "cairn")
	fence.creatures[0].pos = fence.terrain.cell_center(Vector2i(10, 4))
	fence.creatures[1].pos = fence.terrain.cell_center(Vector2i(50, 4))
	assert_true(_cpu_reaches(fence, 1, 900) >= 0, "through the gap in the fence")


func test_the_cpu_reaches_the_foe_from_the_spawns_on_every_map() -> void:
	for id in ArenaMap.IDS:
		var sim := _on(id, "digby", "barkley")
		sim.creatures[1].facing = Vector2.LEFT
		assert_true(_cpu_reaches(sim, 1, 900) >= 0, "%s: Normal reaches the foe" % id)


func test_the_stadium_cpu_match_is_unchanged_by_pathing() -> void:
	# On open floor the straight line is clear, so the CPU never consults the grid:
	# the seeded match plays exactly as before pathing existed.
	var a := _seeded_match()
	var b := _seeded_match()
	assert_eq(a, b, "seeded CPU match fingerprint:")


func _seeded_match() -> String:
	var sim := MatchFactory.versus("cairn", "culvert")
	var cpus := [CpuController.new(0, 2, 11), CpuController.new(1, 2, 12)]
	for t in 600:
		sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
	return sim.state_digest()


func test_the_shared_grid_keeps_up_with_holes_and_matches_a_fresh_build() -> void:
	# NavGrid.shared rebuilds only the node rows whose cells changed, and labels regions
	# only after a blocked node changed: it must always equal a grid built from scratch.
	var sim := _on("quarry")
	var g := NavGrid.shared(sim.terrain)
	var from := sim.terrain.cell_center(Vector2i(10, 18))
	var to := sim.terrain.cell_center(Vector2i(42, 18))
	assert_true(g.path(from, to).size() > 0, "a path round the wall")
	for k in 6:
		sim.terrain.set_cell(Vector2i(20 + k, 10 + k * 3), TerrainGrid.HOLE)
		g = NavGrid.shared(sim.terrain)
		var fresh := NavGrid.new()
		fresh.update(sim.terrain)
		assert_eq(g.blocked, fresh.blocked, "blocked nodes after hole %d:" % k)
		assert_eq(g.path(from, to), fresh.path(from, to), "the same path after hole %d:" % k)
	var walled := _with([{"kind": "wall", "rect": [40, 0, 2, 36]}])
	var w := NavGrid.shared(walled.terrain)
	assert_eq(w.path(walled.terrain.cell_center(Vector2i(10, 18)), walled.terrain.cell_center(Vector2i(70, 18))).size(),
		0, "regions: no path through a wall across the floor")
	walled.terrain.smash(Vector2i(40, 18))
	walled.terrain.smash(Vector2i(41, 18))
	walled.terrain.smash(Vector2i(40, 19))
	walled.terrain.smash(Vector2i(41, 19))
	w = NavGrid.shared(walled.terrain)
	assert_true(w.path(walled.terrain.cell_center(Vector2i(10, 18)), walled.terrain.cell_center(Vector2i(70, 18))).size() > 0,
		"once a gap is smashed, the regions join")


func test_cpus_thinking_on_threads_choose_exactly_what_they_do_one_by_one() -> void:
	# CpuController.think_all spreads a 4v4's CPUs over the worker threads: the inputs
	# must be the same as calling bits() one after another, tick for tick.
	var was := CpuController.threaded
	var a := _ctf_inputs(true)
	var b := _ctf_inputs(false)
	CpuController.threaded = was
	assert_eq(a.size(), b.size(), "same length:")
	assert_true(a == b, "threaded and sequential CPU inputs match")


func _ctf_inputs(threaded: bool) -> PackedInt32Array:
	CpuController.threaded = threaded
	var teams := [["cairn", "sno", "pete", "craglash"], ["culvert", "digby", "hissy", "barkley"]]
	var t := TeamSim.new(teams, 4, TeamSim.load_rules(TeamSim.CTF_PATH))
	var cpus := []
	for i in t.slot_count():
		cpus.append(CpuController.new(i, 3, 70 + i))
	var out := PackedInt32Array()
	for tick in 900:
		CpuController.think_all(cpus, t.sim)
		var ins := PackedInt32Array()
		for c in cpus:
			ins.append((c as CpuController).last_bits)
		out.append_array(ins)
		t.step(ins)
	return out


func test_one_pit_cell_leaves_a_node_open_two_block_it() -> void:
	# Scattered pits (Floor of Pits) cut the map into islands that weren't there when any
	# pit cell blocked its 16 px node: a body walks past a lone cell.
	var sim := _with([])
	var nav := NavGrid.new()
	sim.terrain.sink(Vector2i(20, 10))
	nav.update(sim.terrain)
	assert_false(nav.is_blocked(Vector2i(10, 5)), "one pit cell: the node stays open")
	sim.terrain.sink(Vector2i(21, 10))
	nav.update(sim.terrain)
	assert_true(nav.is_blocked(Vector2i(10, 5)), "two pit cells block it")


func test_roll_end_is_where_the_roll_ends() -> void:
	# CpuController.roll_end replays the sim's dodge: over a chasm, along a wall, a blink.
	# (A ram, Craglash's, ends on an impact or smashes the wall: only its lip stop counts,
	# so it's checked for never ending in the chasm instead.)
	var pieces := [{"kind": "chasm", "rect": [30, 10, 3, 16]}, {"kind": "wall", "rect": [20, 4, 2, 6]}]
	var starts := [[Vector2i(27, 18), Vector2.RIGHT], [Vector2i(17, 8), Vector2(1, -0.3)],
		[Vector2i(40, 30), Vector2(-1, -1)], [Vector2i(10, 20), Vector2.DOWN]]
	for id in ["cairn", "culvert", "cerebro", "crease", "craglash"]:
		for s in starts:
			var sim := _with(pieces, id, "cairn")
			var me := sim.creatures[0]
			sim.creatures[1].pos = sim.terrain.cell_center(Vector2i(80, 2))
			me.pos = sim.terrain.cell_center(s[0])
			var want := CpuController.roll_end(sim, me, s[1])
			run(sim, SimDefs.move_bits(s[1]) | SimDefs.IN_DODGE, 1)
			assert_eq(me.state, CreatureSim.State.DODGE, "%s rolls" % id)
			run_until(sim, func(): return me.state != CreatureSim.State.DODGE, 60)
			if id == "craglash":
				assert_false(sim.terrain.is_hole_at(me.pos), "the ram from %s stays out of the chasm" % s[0])
				continue
			assert_lt(me.pos.distance_to(want), 0.01, "%s from %s: ends at %s, predicted %s:" % [id, s[0], me.pos, want])


func test_a_cpu_cut_off_by_a_chasm_rolls_over_it() -> void:
	# A chasm from wall to wall: no walking round. Normal rolls over it, lands on floor
	# and reaches the foe; Craglash's ram stops at the lip, so he waits there unharmed.
	var pieces := [{"kind": "chasm", "rect": [30, 0, 4, 36]}]
	for id in ["cairn", "hissy", "culvert", "pete"]:
		var sim := _with(pieces, id, "cairn")
		sim.creatures[0].pos = sim.terrain.cell_center(Vector2i(20, 18))
		sim.creatures[1].pos = sim.terrain.cell_center(Vector2i(50, 18))
		assert_true(_cpu_reaches(sim, 1, 900) >= 0, "%s rolls over to the foe" % id)
		assert_eq(sim.creatures[0].hp, sim.creatures[0].max_hp, "%s didn't fall in:" % id)
	var ram := _with(pieces, "craglash", "cairn")
	ram.creatures[0].pos = ram.terrain.cell_center(Vector2i(20, 18))
	ram.creatures[1].pos = ram.terrain.cell_center(Vector2i(50, 18))
	_cpu_reaches(ram, 1, 600)
	assert_eq(ram.creatures[0].hp, ram.creatures[0].max_hp, "Craglash stays out of the chasm:")


func test_a_dodge_never_ends_in_a_pit() -> void:
	# Backing off toward a pit that a roll would end in: the dodge turns to a way that
	# lands on floor; one that carries clean over the pit is kept.
	var sim := _with([{"kind": "chasm", "rect": [24, 0, 4, 36]}], "cairn", "culvert")
	var me := sim.creatures[0]
	var into := Vector2.LEFT
	me.pos = sim.terrain.cell_center(Vector2i(32, 18))
	assert_true(sim.terrain.is_hole_at(CpuController.roll_end(sim, me, into)), "straight back lands in it")
	var d := CpuController._safe_roll_dir(sim, me, into)
	assert_true(d != Vector2.ZERO and CpuController._lands_safe(sim.terrain, CpuController.roll_end(sim, me, d)),
		"turned to floor: %s" % d)
	me.pos = sim.terrain.cell_center(Vector2i(28, 18))
	assert_true(CpuController._lands_safe(sim.terrain, CpuController.roll_end(sim, me, into)), "from the lip it clears it")
	assert_eq(CpuController._safe_roll_dir(sim, me, into), into, "so it keeps that way:")
