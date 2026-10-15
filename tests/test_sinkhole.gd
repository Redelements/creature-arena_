extends TestCase
## Sinkhole: the floor falls away from the edges, ring by ring, with a cracked warning
## first; a fall is a knockout; the last side standing wins; the CPU gets off the edge.

const TEAMS := [["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]]


func _sink(size := 1) -> TeamSim:
	var t := TeamSim.new(TEAMS, size, TeamSim.load_rules(TeamSim.SINKHOLE_PATH))
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _idle(t: TeamSim, ticks: int) -> void:
	for i in ticks:
		t.step(PackedInt32Array())


func _every() -> int:
	return int(TeamSim.load_rules(TeamSim.SINKHOLE_PATH)["shrink_every"])


func _warn() -> int:
	return int(TeamSim.load_rules(TeamSim.SINKHOLE_PATH)["shrink_warn"])


func test_the_rules_load_and_a_fall_is_a_knockout() -> void:
	var t := _sink()
	assert_true(t.sinkhole, "sinkhole rules")
	assert_true(t.sim.fall_ko, "a fall knocks out")
	assert_eq(t.size, 1, "1v1:")
	var plain := TeamSim.new(TEAMS, 2)
	assert_false(plain.sinkhole, "a team battle keeps its floor")
	assert_false(plain.sim.fall_ko, "and its falls only hurt")


func test_the_outer_ring_cracks_then_falls_for_good() -> void:
	var t := _sink()
	var corner := Vector2i(0, 0)
	var inner := Vector2i(1, 1)
	_idle(t, _every())
	assert_eq(t.sim.terrain.get_cell(corner), TerrainGrid.CRACKED, "the edge cracks as a warning:")
	assert_eq(t.sim.sink_ring, 0, "the doomed ring is known:")
	assert_eq(t.sim.terrain.get_cell(inner), TerrainGrid.INTACT, "the next ring is untouched:")
	_idle(t, _warn())
	assert_eq(t.sim.terrain.get_cell(corner), TerrainGrid.CHASM, "then falls:")
	assert_eq(t.sim.terrain.get_cell(Vector2i(40, 0)), TerrainGrid.CHASM, "the whole ring:")
	assert_eq(t.sim.terrain.get_cell(Vector2i(83, 35)), TerrainGrid.CHASM, "to the far corner:")
	assert_eq(t.ring, 1, "one ring down:")
	assert_eq(t.sim.sink_ring, -1, "no warning until the next:")
	for i in TerrainGrid.HEAL_TICKS * 2:
		t.sim.terrain.tick()
	assert_eq(t.sim.terrain.get_cell(corner), TerrainGrid.CHASM, "never heals:")


func test_whoever_stands_on_the_edge_goes_down_and_the_other_side_wins() -> void:
	var t := _sink()
	# A body's centre can't reach the outermost cells (the floor clamp keeps a radius
	# off the wall), so ring 0 is a pure warning: ring 1 is the first that takes anyone.
	var edge := t.sim.creatures[1]
	edge.pos = t.sim.terrain.cell_center(Vector2i(1, 18))
	t.sim.creatures[0].pos = t.sim.terrain.cell_center(Vector2i(42, 18))
	_idle(t, (_every() + _warn()) * 2 + 2)
	assert_eq(edge.state, CreatureSim.State.FALLING, "the edge fell from under it:")
	_idle(t, CreatureSim.FALL_TICKS + 2)
	assert_eq(edge.state, CreatureSim.State.KO, "a fall is a knockout:")
	assert_eq(t.phase, TeamSim.Phase.OVER, "the match is over:")
	assert_eq(t.winner, 0, "the other side wins:")


func test_it_all_rolls_back() -> void:
	var t := _sink(2)
	_idle(t, _every() - 5)
	var s := t.snapshot()
	var d := t.state_digest()
	_idle(t, 40)
	assert_true(t.state_digest() != d, "time moved on")
	t.restore(s)
	assert_eq(t.state_digest(), d, "restore puts the floor and the countdown back:")


func test_the_cpu_steps_off_the_doomed_edge() -> void:
	var t := _sink()
	var cpu := CpuController.new(0, 1, 9)
	var me := t.sim.creatures[0]
	var foe := t.sim.creatures[1]
	me.pos = t.sim.terrain.cell_center(Vector2i(2, 2))
	foe.pos = t.sim.terrain.cell_center(Vector2i(5, 1))  # the foe idles on ring 1
	var survived_first := false
	for i in _every() * 2 + _warn() * 2 + CreatureSim.FALL_TICKS + 10:
		if foe.state != CreatureSim.State.KO:
			foe.hp = foe.max_hp  # the idle foe only goes down with the floor
		t.step(PackedInt32Array([cpu.bits(t.sim), 0]))
		if t.ring == 1 and t.sim.sink_ring < 0:
			survived_first = survived_first or me.state != CreatureSim.State.KO
		if t.phase == TeamSim.Phase.OVER:
			break
	assert_true(survived_first, "the CPU was still up after the first ring fell")
	assert_eq(t.phase, TeamSim.Phase.OVER, "the idle foe went down with ring 1:")
	assert_eq(t.winner, 0, "the CPU won:")
