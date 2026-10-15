extends TestCase
## King of the Crater: a zone to hold that moves, the floor breaking round it, a hold
## that scores a tick a tick, KOs that respawn without scoring, and a CPU that goes
## for the zone.

const TEAMS := [["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]]


func _rules() -> Dictionary:
	return TeamSim.load_rules(TeamSim.CRATER_PATH)


func _crater(size := 1) -> TeamSim:
	var t := TeamSim.new(TEAMS, size, _rules())
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _idle(t: TeamSim, ticks: int) -> void:
	for i in ticks:
		t.step(PackedInt32Array())


func _far(t: TeamSim, c: CreatureSim) -> void:
	c.pos = t.sim.terrain.nearest_solid(t.sim.zone_pos + Vector2(0.0, -140.0))


func test_the_zone_opens_in_the_middle_and_only_a_lone_side_scores() -> void:
	var t := _crater()
	assert_true(t.crater, "crater rules")
	assert_true(t.deathmatch, "with deathmatch respawns")
	assert_gt(t.sim.zone_r, 0.0, "a zone exists")
	assert_lt(t.sim.zone_pos.distance_to(SimDefs.floor_rect().get_center()), 1.0, "it opens in the middle:")
	var a := t.sim.creatures[0]
	var b := t.sim.creatures[1]
	a.pos = t.sim.zone_pos
	_far(t, b)
	_idle(t, 60)
	assert_eq(int(t.score[0]), 60, "alone inside: a tick a tick:")
	assert_eq(int(t.score[1]), 0, "the other side nothing:")
	b.pos = t.sim.zone_pos + Vector2(20, 0)
	var was := int(t.score[0])
	_idle(t, 30)
	assert_eq(int(t.score[0]), was, "contested: nobody scores:")
	assert_eq(int(t.score[1]), 0, "either way:")


func test_the_zone_moves_and_breaks_the_floor_round_it() -> void:
	var t := _crater()
	var first := t.sim.zone_pos
	var a := t.sim.creatures[0]
	a.pos = first
	_far(t, t.sim.creatures[1])
	assert_true(t.sim.terrain.count(TerrainGrid.CRACKED) > 0, "the rim cracked when the zone opened")
	var holes_before := t.sim.terrain.count(TerrainGrid.HOLE)
	_idle(t, int(_rules()["crack_every"]) * 3 + 2)
	assert_gt(float(t.sim.terrain.count(TerrainGrid.HOLE)), float(holes_before), "holding it chips the cracked rim into holes")
	_idle(t, int(_rules()["zone_move_every"]))
	assert_gt(t.sim.zone_pos.distance_to(first), 40.0, "the zone moved on")
	var fr := SimDefs.floor_rect()
	assert_true(fr.grow(-float(t.sim.zone_r)).has_point(t.sim.zone_pos), "and stays on the floor")
	assert_true(t.sim.terrain.count(TerrainGrid.CRACKED) > 0, "its rim cracked where it landed")


func test_the_first_to_the_hold_wins_and_a_ko_scores_nothing() -> void:
	var r := _rules()
	r["score_to_win"] = 120
	var t := TeamSim.new(TEAMS, 1, r)
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	var a := t.sim.creatures[0]
	var b := t.sim.creatures[1]
	_far(t, a)
	_far(t, b)
	b.hp = 0.0
	b._set_state(CreatureSim.State.KO)
	_idle(t, 2)
	assert_eq(int(t.score[0]), 0, "a KO scores nothing here:")
	assert_true(int(t.respawn_t[1]) > 0, "but the fallen one comes back")
	a.pos = t.sim.zone_pos
	_idle(t, 130)
	assert_eq(t.phase, TeamSim.Phase.OVER, "held long enough:")
	assert_eq(t.winner, 0, "the holder wins:")


func test_it_all_rolls_back() -> void:
	var t := _crater(2)
	t.sim.creatures[0].pos = t.sim.zone_pos
	_idle(t, 50)
	var s := t.snapshot()
	var d := t.state_digest()
	_idle(t, 40)
	assert_true(t.state_digest() != d, "time moved on")
	t.restore(s)
	assert_eq(t.state_digest(), d, "restore puts the zone, the hold and the floor back:")


func test_the_cpu_goes_to_the_zone() -> void:
	var t := _crater()
	var cpu := CpuController.new(0, 1, 3)
	var me := t.sim.creatures[0]
	var foe := t.sim.creatures[1]
	_far(t, me)
	foe.pos = t.sim.terrain.nearest_solid(t.sim.zone_pos + Vector2(200.0, 100.0))
	var reached := -1
	for i in 600:
		t.step(PackedInt32Array([cpu.bits(t.sim), 0]))
		if me.pos.distance_to(t.sim.zone_pos) < t.sim.zone_r:
			reached = i
			break
	assert_true(reached >= 0, "the CPU went and stood in the zone")
	_idle(t, 0)
	for i in 60:
		t.step(PackedInt32Array([cpu.bits(t.sim), 0]))
	assert_gt(float(t.score[0]), 30.0, "and holds it (%d ticks)" % int(t.score[0]))
