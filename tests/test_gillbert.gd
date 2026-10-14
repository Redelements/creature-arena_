extends TestCase
## Gillbert's kit: Cast Line reels him in to whoever it hooks, Splash Zone slows, Flop
## Dash dashes in, and The One That Got Away leaps out of reach and lands on a spot.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE
const GUARD := SimDefs.IN_GUARD


## Gillbert on the left, `foe` on the right with `gap` pixels between their bodies.
func _duel(foe := "cairn", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus("gillbert", foe)
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


func _gap(sim: MatchSim) -> float:
	var a := sim.creatures[0]
	var b := sim.creatures[1]
	return a.pos.distance_to(b.pos) - a.radius - b.radius


func _events(sim: MatchSim, kind: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e["type"]) == kind:
			out.append(e)
	return out


func test_cast_line_reels_gillbert_in_to_the_target() -> void:
	var sim := _duel("cairn", 90.0)
	var gill := sim.creatures[0]
	var foe_x := sim.creatures[1].pos.x
	var reeled := run_until(sim, func(): return not _events(sim, "reel").is_empty(), 60, S2)
	assert_true(reeled, "the thrown rod should hook Cairn from 90 px away")
	# Hauled in at a steady speed, not flung: no tick moves him more than reel_speed.
	var speed := float(gill.def["moves"]["skill_2"]["reel_speed"])
	var arrived := false
	for i in 40:
		var before := gill.pos
		run(sim, 0, 1)
		assert_lt(gill.pos.distance_to(before), speed + 0.01, "steady reel speed:")
		if not _events(sim, "reeled_in").is_empty():
			arrived = true
			break
	assert_true(arrived, "he arrives")
	var want := float(gill.def["moves"]["skill_2"]["reel"])
	assert_lt(_gap(sim), want + 0.5, "Gillbert reeled in to point-blank:")
	assert_lt(absf(sim.creatures[1].pos.x - foe_x), 3.0, "the target stays where it was")
	assert_eq(gill.state, CreatureSim.State.IDLE, "arriving ends the cast, so he can act at once:")
	assert_true(sim.creatures[1].is_stunned(), "and the target is still stunned")


func test_a_whiffed_cast_reels_nobody() -> void:
	var sim := _duel("cairn", 160.0)
	var start := sim.creatures[0].pos.x
	tap(sim, S2, 60)
	assert_true(_events(sim, "reel").is_empty(), "out of range: nothing hooked")
	assert_lt(sim.creatures[0].pos.x - start, 1.0, "and he stays put")


func test_the_reel_does_not_drop_him_in_a_pit() -> void:
	var sim := _duel("cairn", 80.0)
	var gill := sim.creatures[0]
	for x in range(int(gill.pos.x) + 24, int(gill.pos.x) + 60, 4):
		sim.terrain.damage_circle(Vector2(x, gill.pos.y), 4.0, 4.0)
	var arrived := run_until(sim, func(): return not _events(sim, "reeled_in").is_empty(), 80, S2)
	assert_true(arrived, "hooked and reeled across the pit")
	run(sim, 0, 2)
	assert_true(gill.state != CreatureSim.State.FALLING, "the line carries him over it")


func test_cast_line_links_into_his_string() -> void:
	var sim := _duel("cairn", 80.0)
	var dmg := route(sim, 0, [[S2, "skill_2"], [L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"]])
	assert_gt(dmg, 24.0, "Cast Line, the light string and Splash Zone should all connect")


func test_a_guarded_cast_line_reels_nobody() -> void:
	var sim := _duel("cairn", 60.0)
	var start := sim.creatures[0].pos
	var blocked := run_until(sim, func(): return not _events(sim, "block").is_empty(), 60, S2, GUARD)
	assert_true(blocked, "Cairn blocks the hook")
	run(sim, 0, 20, GUARD)
	assert_lt(sim.creatures[0].pos.x - start.x, 3.0, "a blocked line doesn't haul him over")


func test_splash_zone_slows_everyone_around_him() -> void:
	var sim := _duel("cairn", 2.0)
	sim.creatures[1].pos.x = sim.creatures[0].pos.x - 22.0  # behind him
	var slowed := run_until(sim, func(): return not _events(sim, "slow").is_empty(), 60, H)
	assert_true(slowed, "the tail slap reaches behind him too")
	var mult := float(sim.creatures[0].def["moves"]["heavy"]["slow_mult"])
	assert_near(sim.creatures[1].slow_mult, mult, 0.001, "soaked and slowed:")


func test_flop_dash_covers_ground() -> void:
	var sim := _duel("cairn", 40.0)
	var start := sim.creatures[0].pos.x
	var hit := run_until(sim, func(): return not _events(sim, "hit").is_empty(), 60, S1)
	assert_true(hit, "Flop Dash reaches a foe 40 px away")
	assert_gt(sim.creatures[0].pos.x - start, 30.0, "and gets there by dashing:")


func test_the_one_that_got_away_is_out_of_reach_then_lands() -> void:
	var sim := _duel("cairn", 2.0)
	var gill := sim.creatures[0]
	gill.energy = 100.0
	var start := gill.pos.x
	var lp: Dictionary = gill.def["moves"]["surge"]["leap"]
	run_until(sim, func(): return gill.is_leaping(), 40, SU)
	assert_true(gill.is_leaping(), "he leaps")
	assert_true(gill.is_invulnerable(), "out of reach while in the air")
	assert_false(gill.is_solid(), "and passes over bodies")
	# Cairn swings at him the whole time he's up: nothing lands.
	var hp := gill.hp
	for i in int(lp["to"]) - int(lp["from"]) - 2:
		run(sim, 0, 1, L if i % 2 == 0 else 0)
	assert_near(gill.hp, hp, 0.001, "nothing hits him in the air:")
	var landed := run_until(sim, func(): return not _events(sim, "hit").is_empty(), 30)
	assert_true(landed, "the belly-flop lands on Cairn")
	assert_gt(gill.pos.x - start, 15.0, "he came down ahead, on Cairn:")


func test_the_leap_sails_over_a_pit() -> void:
	var sim := _duel("cairn", 60.0)
	var gill := sim.creatures[0]
	gill.energy = 100.0
	# A pit right in front of him: walking would stop at its edge.
	for x in range(int(gill.pos.x) + 14, int(gill.pos.x) + 30, 4):
		sim.terrain.damage_circle(Vector2(x, gill.pos.y), 4.0, 4.0)
	run_until(sim, func(): return gill.state != CreatureSim.State.ATTACK and gill.state_t > 2, 120, SU)
	assert_true(gill.state != CreatureSim.State.FALLING, "he doesn't fall in")
	assert_gt(gill.pos.x, 220.0 + 30.0, "he lands on the far side")


func test_rollback_through_a_leap() -> void:
	var sim := _duel("culvert", 6.0)
	sim.creatures[0].energy = 100.0
	run_until(sim, func(): return sim.creatures[0].is_leaping(), 40, SU)
	run(sim, 0, 4)
	assert_true(sim.creatures[0].is_leaping(), "in the air")
	var snap := sim.snapshot()
	run(sim, 0, 40, L)
	var once := sim.state_digest()
	sim.restore(snap)
	run(sim, 0, 40, L)
	assert_eq(sim.state_digest(), once, "replaying from the snapshot gives the same state:")


func test_reel_without_reel_speed_uses_the_default() -> void:
	var sim := _duel("cairn", 90.0)
	var gill := sim.creatures[0]
	gill.def = gill.def.duplicate(true)  # the factory caches defs; don't edit the shared one
	gill.def["moves"]["skill_2"].erase("reel_speed")
	var reeled := run_until(sim, func(): return not _events(sim, "reel").is_empty(), 60, S2)
	assert_true(reeled, "hooked")
	var fastest := 0.0
	for i in 20:
		var before := gill.pos
		run(sim, 0, 1)
		fastest = maxf(fastest, gill.pos.distance_to(before))
	assert_near(fastest, MatchSim.REEL_SPEED_DEFAULT, 0.05, "reeled at the default speed, not 1 px a tick:")
