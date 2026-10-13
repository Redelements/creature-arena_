extends TestCase
## Barkley's kit: Branch Grab's pull, Pinecone Bomb's lob and burst, Timber Twister's
## spin and late cancel, Root Eruption's rings, and rollback through a lob in flight.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE
const GUARD := SimDefs.IN_GUARD


## Barkley on the left, `foe` on the right with `gap` pixels between their bodies.
func _duel(foe := "cairn", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus("barkley", foe)
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


func test_branch_grab_pulls_the_target_in() -> void:
	var sim := _duel("cairn", 24.0)
	var pulled := run_until(sim, func(): return not _events(sim, "pull").is_empty(), 60, S1)
	assert_true(pulled, "Branch Grab should snag Cairn from 24 px away")
	run(sim, 0, 30)
	var want := float(sim.creatures[0].def["moves"]["skill_1"]["pull"])
	assert_lt(_gap(sim), want + 1.5, "reeled in to point-blank:")
	assert_true(sim.creatures[1].is_stunned(), "still stunned after the pull, so a light can follow")


func test_branch_grab_links_into_lights() -> void:
	var sim := _duel("cairn", 22.0)
	var dmg := route(sim, 0, [[S1, "skill_1"], [L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"]])
	assert_gt(dmg, 35.0, "Branch Grab, then the light string and Timber Twister, should all connect")


func test_a_guarded_branch_grab_does_not_pull() -> void:
	var sim := _duel("cairn", 22.0)
	var start := sim.creatures[1].pos
	var blocked := run_until(sim, func(): return not _events(sim, "block").is_empty(), 60, S1, GUARD)
	assert_true(blocked, "Cairn should block the grab")
	run(sim, 0, 20, GUARD)
	assert_lt(start.x - sim.creatures[1].pos.x, 3.0, "a blocked grab doesn't reel anyone in")


func test_pinecone_flies_over_a_close_foe_and_bursts_where_it_lands() -> void:
	var sim := _duel("cairn", 2.0)
	var barkley := sim.creatures[0]
	var mv: Dictionary = barkley.def["moves"]["skill_2"]
	var pr: Dictionary = mv["projectile"]
	tap(sim, S2, int(mv["startup"]) + 1)
	assert_eq(sim.projectiles.size(), 1, "a pinecone in the air")
	var hp := sim.creatures[1].hp
	var burst := run_until(sim, func(): return not _events(sim, "burst").is_empty(), int(pr["time"]) + 5)
	assert_true(burst, "it lands and bursts")
	var at: Vector2 = _events(sim, "burst")[0]["pos"]
	var expect := barkley.pos.x + float(pr["offset"]) + float(pr["range"])
	assert_near(at.x, expect, 1.5, "lands range + offset ahead:")
	assert_near(sim.creatures[1].hp, hp, 0.001, "a foe right next to Barkley is under the arc, not hit:")


func test_pinecone_burst_hits_a_foe_at_the_landing_spot() -> void:
	var sim := _duel("cairn", 2.0)
	var pr: Dictionary = sim.creatures[0].def["moves"]["skill_2"]["projectile"]
	sim.creatures[1].pos.x = sim.creatures[0].pos.x + float(pr["offset"]) + float(pr["range"]) - 6.0
	var hp := sim.creatures[1].hp
	run(sim, S2, 1)  # a tap: the shortest throw
	var burst := run_until(sim, func(): return not _events(sim, "burst").is_empty(), 60)
	assert_true(burst, "it bursts")
	assert_eq(int(_events(sim, "burst")[0]["landed"]), 1, "one foe in the burst:")
	assert_lt(sim.creatures[1].hp, hp, "the burst hurts")
	assert_true(sim.creatures[1].is_airborne(), "and pops the target up")


func test_timber_twister_hits_three_times_and_holds_its_cancel_to_the_last() -> void:
	var sim := _duel("cairn", 2.0)
	var hits := 0
	# Mash Branch Grab the whole time: it may only come out after the last spin hit.
	tap(sim, H, 1)
	for i in 80:
		run(sim, S1 if i % 2 == 0 else 0, 1)
		hits += _events(sim, "hit").size()
		if sim.creatures[0].move_id == "skill_1":
			break
	assert_eq(hits, 3, "all three spin hits land before the cancel:")
	assert_eq(sim.creatures[0].move_id, "skill_1", "then it cancels into Branch Grab")


func test_timber_twister_hits_all_around() -> void:
	var sim := _duel("cairn", 2.0)
	# Cairn stands behind Barkley: the spin reaches him anyway.
	sim.creatures[1].pos.x = sim.creatures[0].pos.x - 20.0
	var hit := run_until(sim, func(): return not _events(sim, "hit").is_empty(), 40, H)
	assert_true(hit, "Timber Twister hits behind him too")


func test_root_eruption_reaches_out_in_rings_and_cracks_without_holes() -> void:
	var sim := _duel("cairn", 34.0)
	sim.creatures[0].energy = 100.0
	sim.creatures[1].pos = sim.creatures[0].pos + Vector2(0, -44)  # above him, well away
	var holes := sim.terrain.count(TerrainGrid.HOLE)
	var hit := run_until(sim, func(): return not _events(sim, "hit").is_empty(), 80, SU)
	assert_true(hit, "the outer ring reaches 44 px away")
	run(sim, 0, 40)
	assert_gt(float(sim.terrain.count(TerrainGrid.CRACKED)), 10.0, "the floor cracks around him")
	assert_eq(sim.terrain.count(TerrainGrid.HOLE), holes, "but no pits open:")


func test_rollback_through_a_pinecone_in_flight() -> void:
	var sim := _duel("culvert", 30.0)
	tap(sim, S2, int(sim.creatures[0].def["moves"]["skill_2"]["startup"]) + 4)
	assert_eq(sim.projectiles.size(), 1, "pinecone in the air")
	var snap := sim.snapshot()
	run(sim, 0, 40, L)
	var once := sim.state_digest()
	sim.restore(snap)
	run(sim, 0, 40, L)
	assert_eq(sim.state_digest(), once, "replaying from the snapshot gives the same state:")


func test_holding_the_pinecone_throws_it_further() -> void:
	var sim := _duel("cairn", 140.0)
	var barkley := sim.creatures[0]
	var mv: Dictionary = barkley.def["moves"]["skill_2"]
	var pr: Dictionary = mv["projectile"]
	run(sim, S2, int(mv["charge_max"]) + 2)  # held all the way
	var burst := run_until(sim, func(): return not _events(sim, "burst").is_empty(), 60)
	assert_true(burst, "it bursts")
	var at: Vector2 = _events(sim, "burst")[0]["pos"]
	assert_gt(at.x - barkley.pos.x, float(pr["range_charged"]) - 4.0, "a full hold throws it the furthest:")


func test_the_pinecone_snaps_to_a_foe_roughly_ahead() -> void:
	var sim := _duel("cairn", 30.0)
	var barkley := sim.creatures[0]
	var foe := sim.creatures[1]
	var pr: Dictionary = barkley.def["moves"]["skill_2"]["projectile"]
	foe.pos = barkley.pos + Vector2(float(pr["range"]) + float(pr["offset"]), 22.0)  # ahead but off his line
	var hp := foe.hp
	run(sim, S2, 1)
	run_until(sim, func(): return not _events(sim, "burst").is_empty(), 60)
	assert_lt(foe.hp, hp, "the throw turns toward Cairn and lands on him")


func test_timber_twister_has_a_cooldown() -> void:
	var sim := _duel("cairn", 60.0)
	var barkley := sim.creatures[0]
	tap(sim, H, 70)
	assert_false(barkley.can_use("heavy"), "the spin can't be thrown again straight away")
