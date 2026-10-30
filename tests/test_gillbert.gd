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
	var sim := _duel("cairn", 260.0)
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


## Kevin, Oct 29: Cast Line is a grab. A guard doesn't stop it: the guarding foe is hooked
## and Gillbert reels in to him like on a clean hit.
func test_a_guarding_foe_is_hooked_and_reeled_anyway() -> void:
	var sim := _duel("cairn", 120.0)
	var gill := sim.creatures[0]
	var cairn := sim.creatures[1]
	var hooked := run_until(sim, func(): return not _events(sim, "reel").is_empty(), 60, S2, GUARD)
	assert_true(hooked, "a guarding Cairn 120 px away is hooked")
	assert_true(_events(sim, "block").is_empty(), "not blocked")
	assert_eq(cairn.state, CreatureSim.State.HITSTUN, "the guard is gone: hitstun")
	assert_lt(cairn.hp, cairn.max_hp, "the hook's damage lands")
	var arrived := run_until(sim, func(): return not _events(sim, "reeled_in").is_empty(), 40, 0, GUARD)
	assert_true(arrived, "and Gillbert is reeled in to him")
	assert_lt(_gap(sim), float(gill.def["moves"]["skill_2"]["reel"]) + 0.5, "to point-blank:")
	assert_true(cairn.is_stunned(), "with the target still stunned")


func test_armor_doesnt_stop_the_hook() -> void:
	var sim := _duel("craglash", 120.0)
	var crag := sim.creatures[1]
	crag.energy = 100.0
	var armored := run_until(sim, func(): return crag.is_armored(), 80, 0, SU)
	assert_true(armored, "Craglash sets Bedrock")
	var hooked := run_until(sim, func(): return not _events(sim, "reel").is_empty(), 60, S2)
	assert_true(hooked, "Cast Line hooks Craglash through Bedrock's armor")
	assert_true(_events(sim, "armor").is_empty(), "not soaked by the armor")
	assert_eq(crag.state, CreatureSim.State.HITSTUN, "hooked out of the stance:")


func test_a_dodge_beats_the_hook() -> void:
	var sim := _duel("cairn", 100.0)
	var cairn := sim.creatures[1]
	var dodged := false
	for i in 80:
		var p1 := 0
		if not dodged and not sim.projectiles.is_empty():
			if Vector2(sim.projectiles[0]["pos"]).distance_to(cairn.pos) < 70.0:
				p1 = SimDefs.IN_DODGE | SimDefs.IN_DOWN
				dodged = true
		sim.step(PackedInt32Array([S2 if i < 3 else 0, p1]))
		assert_true(_events(sim, "reel").is_empty(), "nothing reeled")
	assert_true(dodged, "Cairn dodged")
	assert_near(cairn.hp, cairn.max_hp, 0.001, "the dodge is the answer now, not the block:")


## Still a skill shot: the hook takes the first body in its path, so a tank standing in
## the lane takes it, not the mage behind him.
func test_the_hook_bites_the_first_body_in_its_path() -> void:
	var sim := _duel("cairn", 50.0)
	var tank := sim.creatures[1]
	var mage := sim.add_creature(MatchFactory.load_def("cerebro"), tank.pos + Vector2(tank.radius + 60.0, 0))
	mage.team = tank.team
	mage.facing = Vector2.LEFT
	var hooked := run_until(sim, func(): return not _events(sim, "reel").is_empty(), 60, S2)
	assert_true(hooked, "the hook bites")
	assert_eq(int(_events(sim, "reel")[0]["target"]), tank.id, "the tank in the lane takes it:")
	assert_near(mage.hp, mage.max_hp, 0.001, "the mage behind is untouched:")


## R5 (grab_air, with juggle): a juggled foe can still be snagged out of the air.
func test_the_hook_snags_an_airborne_foe() -> void:
	var sim := _duel("cairn", 90.0)
	var cairn := sim.creatures[1]
	cairn.enter_air(60, Vector2.ZERO)
	var hooked := run_until(sim, func(): return not _events(sim, "reel").is_empty(), 40, S2)
	assert_true(hooked, "a foe in the air is hooked too")


## Kevin, Oct 29: a thicker head, so an aimed cast lands. It widens along the flight like
## the other two hooks (Gulp, Mountain Maw): the aim's error grows with the distance.
func test_the_head_is_thicker_than_the_old_rod() -> void:
	var p: Dictionary = MatchFactory.load_def("gillbert")["moves"]["skill_2"]["projectile"]
	assert_gt(float(p["radius"]), 8.0, "wider than the old 8 at the start:")
	assert_gt(float(p.get("radius_end", 0.0)), float(p["radius"]), "and wider still at full reach:")
	var mv: Dictionary = MatchFactory.load_def("gillbert")["moves"]["skill_2"]
	assert_true(bool(mv.get("grab", false)), "a grab:")
	assert_eq(String(mv.get("tell", "")), "unblockable", "with the red tell:")


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


func test_the_landing_leaves_a_slowing_pool() -> void:
	var sim := _duel("cairn", 2.0)
	var gill := sim.creatures[0]
	gill.energy = 100.0
	var landed := run_until(sim, func(): return not _events(sim, "hit").is_empty(), 60, SU)
	assert_true(landed, "he comes down on Cairn")
	run(sim, 0, 4)
	assert_false(sim.zones.is_empty(), "a pool is left where he landed")
	var z = sim.zones[0]
	assert_near(float(z["radius"]), 50.0, 0.01, "50 px wide:")
	assert_near(float(z["slow_mult"]), 0.7, 0.001, "slowing:")
