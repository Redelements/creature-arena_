extends TestCase
## Sno Mercy's kit: Cold Cross slows, Shaved Ice Spray hits a cone in front of him,
## Syrup Slick leaves a puddle that slows foes standing in it, Slush Slide knocks down the
## first foe it hits, and Flavor Blast freezes everyone around him solid (the next clean
## hit shatters the ice).

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE


func _duel(foe := "cairn", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus("sno", foe)
	sim.creatures[0].pos = Vector2(200, 164)
	sim.creatures[1].pos = Vector2(200 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


func _count(sim: MatchSim, kind: String, ticks: int, p0 := 0, p1 := 0) -> int:
	var n := 0
	for i in ticks:
		sim.step(PackedInt32Array([p0, p1]))
		for e in sim.events:
			if String(e["type"]) == kind:
				n += 1
	return n


func test_cold_cross_slows() -> void:
	var sim := _duel()
	var foe := sim.creatures[1]
	run_until(sim, func(): return foe.slow > 0, 20, L)
	assert_lt(foe.slow_mult, 1.0, "a frosty jab slows:")


func test_shaved_ice_spray_hits_a_cone_in_front_only() -> void:
	var sim := _duel("cairn", 24.0)
	var foe := sim.creatures[1]
	assert_true(run_until(sim, func(): return foe.is_stunned(), 60, H), "the spray reaches a foe 24 px in front")
	var sim2 := _duel("cairn", 24.0)
	sim2.creatures[0].facing = Vector2.LEFT  # looking the other way
	sim2.creatures[0].prev_buttons = 0
	run(sim2, SimDefs.IN_LEFT, 1)
	run(sim2, H, 60)
	assert_false(sim2.creatures[1].is_stunned(), "nothing behind him is hit")


func test_syrup_slick_slows_foes_standing_in_it() -> void:
	var sim := _duel("cairn", 10.0)
	var sno := sim.creatures[0]
	var foe := sim.creatures[1]
	assert_eq(_count(sim, "zone", 20, S1), 1, "a puddle is left:")
	assert_eq(sim.zones.size(), 1, "on the floor")
	run(sim, 0, 2)
	assert_gt(float(foe.slow), 0.0, "Cairn standing in it is slowed")
	assert_lt(foe.walk_speed(), float(foe.def["speed"]) * 0.6, "a lot:")
	assert_eq(sno.slow, 0, "Sno Mercy himself isn't")
	foe.pos = Vector2(200 + 120, 164)  # out of the puddle
	run(sim, 0, 20)
	assert_eq(foe.slow, 0, "out of it, the slow wears off quickly:")
	run(sim, 0, int(sno.def["moves"]["skill_1"]["zone"]["ticks"]))
	assert_eq(sim.zones.size(), 0, "and the puddle dries up")


func test_slush_slide_knocks_down() -> void:
	var sim := _duel("cairn", 50.0)
	var foe := sim.creatures[1]
	var down := run_until(sim, func(): return foe.state == CreatureSim.State.KNOCKDOWN, 60, S2)
	assert_true(down, "the sliding kick knocks Cairn down from 50 px away")


func test_flavor_blast_freezes_and_a_hit_shatters_the_ice() -> void:
	var sim := _duel("cairn", 20.0)
	var sno := sim.creatures[0]
	var foe := sim.creatures[1]
	sno.energy = 100.0
	assert_eq(_count(sim, "freeze", 80, SU), 1, "frozen solid:")
	assert_true(foe.stone_ice, "in ice")
	assert_eq(foe.state, CreatureSim.State.CRUMPLE, "stunned")
	run_until(sim, func(): return sno.state == CreatureSim.State.IDLE, 60)
	assert_gt(float(foe.stone), 0.0, "still frozen when he can act")
	foe.pos = sno.pos + Vector2(sno.radius + foe.radius + 2, 0)
	assert_eq(_count(sim, "shatter", 30, L), 1, "the next clean hit shatters the ice")


func test_flavor_blast_hits_all_around() -> void:
	var sim := _duel("cairn", 20.0)
	var sno := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.pos = sno.pos + Vector2(-(sno.radius + foe.radius + 20.0), 0)  # behind him
	sno.energy = 100.0
	assert_eq(_count(sim, "freeze", 80, SU), 1, "it freezes a foe behind him too:")


func test_rollback_with_zones_and_ice() -> void:
	var sim := _duel("culvert", 6.0)
	var foe := sim.creatures[1]
	foe.stone = 40
	foe.stone_ice = true
	foe.state = CreatureSim.State.CRUMPLE
	foe.stun = 40
	run(sim, S1, 1)
	run(sim, 0, 14)
	var snap := sim.snapshot()
	run(sim, 0, 80, L)
	var once := sim.state_digest()
	sim.restore(snap)
	run(sim, 0, 80, L)
	assert_eq(sim.state_digest(), once, "replaying from the snapshot gives the same state:")


func test_flavor_blast_freezes_75_px_away_and_leaves_a_slow_puddle() -> void:
	var sim := _duel("cairn", 20.0)
	var sno := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.pos = sno.pos + Vector2(75, 0)
	sno.energy = 100.0
	assert_eq(_count(sim, "freeze", 80, SU), 1, "frozen from 75 px away")
	assert_eq(sim.zones.size(), 1, "a puddle at his feet")
	assert_near(float(sim.zones[0]["radius"]), 60.0, 0.5, "60 px wide:")
	assert_eq(foe.state, CreatureSim.State.CRUMPLE, "stunned")
