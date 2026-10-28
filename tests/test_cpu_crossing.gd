extends TestCase
## The CPU crosses a chasm with a crossing move (a `leap` over a straight `dash`: Digby's
## Burrow; `CpuController._gap_cross`, `_cross_through`): over a chasm too wide to roll when
## the far side can't be walked to, or the walk round is much longer, never ending in a pit;
## not with the move on cooldown, nor with `ai.cross_pits` false; and threaded thinking
## matches sequential on a map of pits.

const CELL := 8.0


## Digby (left, a Normal CPU) and a Cairn standing still across a chasm `cols` cells wide
## at column 40, the full height of the floor unless `gap_rows` rows are left open at the top.
func _setup(cols := 10, gap_rows := 0) -> MatchSim:
	var sim := MatchFactory.versus("digby", "cairn")
	sim.terrain.load_map({"pieces": [{"kind": "chasm", "rect": [40, gap_rows, cols, 36 - gap_rows]}]})
	var lip := sim.terrain.cell_rect(Vector2i(40, 0)).position.x
	var y := sim.terrain.cell_center(Vector2i(40, 24)).y
	sim.creatures[0].pos = Vector2(lip - 40.0, y)
	sim.creatures[1].pos = Vector2(lip + float(cols) * CELL + 210.0, y)
	return sim


## Plays `ticks` with Digby's CPU and Cairn idle; returns [crossed (came down past the
## chasm), fell, leaps over the chasm]. `each` runs before every tick.
func _play(sim: MatchSim, cpu: CpuController, ticks: int, cols := 10, each := Callable()) -> Array:
	var d := sim.creatures[0]
	var far := sim.terrain.cell_rect(Vector2i(40 + cols, 0)).position.x
	var fell := false
	var leaps := 0
	var over := false
	for i in ticks:
		if each.is_valid():
			each.call()
		sim.step(PackedInt32Array([cpu.bits(sim), 0]))
		sim.creatures[1].walk_vel = Vector2.ZERO
		if d.state == CreatureSim.State.FALLING:
			fell = true
		var now := d.is_leaping() and sim.terrain.is_hole_at(d.pos)
		if now and not over:
			leaps += 1
		over = now
	return [d.pos.x > far + 4.0 and not d.is_leaping(), fell, leaps]


func test_burrow_crosses_a_chasm_too_wide_to_roll_when_there_is_no_way_round() -> void:
	var sim := _setup()
	var r := _play(sim, CpuController.new(0, 1, 3), 420)
	assert_true(bool(r[0]), "Digby came up on the far side")
	assert_false(bool(r[1]), "and never fell")
	assert_gt(float(r[2]), 0.0, "by Burrow, over the chasm")


func test_not_with_burrow_on_cooldown() -> void:
	var sim := _setup()
	var d := sim.creatures[0]
	var r := _play(sim, CpuController.new(0, 1, 3), 420, 10, func() -> void: d.cooldowns["skill_2"] = 999)
	assert_false(bool(r[0]), "no crossing move ready: it stays on its side")
	assert_false(bool(r[1]), "and doesn't fall")


func test_not_with_ai_cross_pits_false() -> void:
	var sim := _setup()
	var d := sim.creatures[0]
	d.def = d.def.duplicate(true)
	(d.def["ai"] as Dictionary)["cross_pits"] = false
	var r := _play(sim, CpuController.new(0, 1, 3), 420)
	assert_eq(int(r[2]), 0, "ai.cross_pits false: no Burrow over the chasm")
	assert_false(bool(r[1]), "and no fall")


func test_burrow_over_a_chasm_rather_than_the_long_walk_round() -> void:
	# The chasm leaves a way round across the top of the floor: far longer than straight.
	var sim := _setup(10, 4)
	var r := _play(sim, CpuController.new(0, 1, 3), 420, 10)
	assert_gt(float(r[2]), 0.0, "Digby burrowed over the chasm instead of walking round")
	assert_true(bool(r[0]), "and came up on the far side")
	assert_false(bool(r[1]), "without a fall")


func test_the_crossing_reach_is_data() -> void:
	var digby: Dictionary = MatchFactory.load_def("digby")
	assert_gt(CpuController._cross_reach(digby["moves"]["skill_2"]), 100.0, "Burrow carries over pits")
	assert_eq(CpuController._cross_reach(digby["moves"]["skill_1"]), 0.0, "a move without a leap doesn't")
	var gill: Dictionary = MatchFactory.load_def("gillbert")
	assert_eq(CpuController._cross_reach(gill["moves"]["surge"]), 0.0, "nor a Surge, nor a homing dash")


func test_threaded_cpus_on_a_floor_of_pits_choose_what_they_do_one_by_one() -> void:
	var was := CpuController.threaded
	var a := _pit_inputs(true)
	var b := _pit_inputs(false)
	CpuController.threaded = was
	assert_eq(a.size(), b.size(), "same length:")
	assert_true(a == b, "threaded and sequential CPU inputs match")


func _pit_inputs(threaded: bool) -> PackedInt32Array:
	CpuController.threaded = threaded
	var t := TeamSim.new([["digby", "digby", "sno"], ["cairn", "digby", "pete"]], 3, TeamSim.load_rules(TeamSim.DEATHMATCH_PATH))
	t.sim.apply_mutators({"pit_floor": 0.22}, 4)
	var cpus := []
	for i in t.slot_count():
		cpus.append(CpuController.new(i, 1, 20 + i))
	var out := PackedInt32Array()
	for tick in 900:
		CpuController.think_all(cpus, t.sim)
		var ins := PackedInt32Array()
		for c in cpus:
			ins.append((c as CpuController).last_bits)
		out.append_array(ins)
		t.step(ins)
	return out
