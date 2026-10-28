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
	assert_gt(dmg, 30.0, "Branch Grab, then the light string and Timber Twister, should all connect")


## Branch Grab is a grab (Oct 2026): a guard doesn't stop it, so a turtling foe is reeled
## in all the same.
func test_branch_grab_reels_in_a_guarding_foe() -> void:
	var sim := _duel("cairn", 22.0)
	var start := sim.creatures[1].pos
	var pulled := run_until(sim, func(): return not _events(sim, "pull").is_empty(), 60, S1, GUARD)
	assert_true(pulled, "the guard doesn't stop the grab")
	assert_true(_events(sim, "block").is_empty(), "not blocked")
	run(sim, 0, 20, GUARD)
	assert_gt(start.x - sim.creatures[1].pos.x, 10.0, "reeled in through the guard:")


func test_timber_twister_is_armored_while_it_spins() -> void:
	var sim := _duel("cairn", 10.0)
	var bark := sim.creatures[0]
	var ar: Dictionary = bark.def["moves"]["heavy"]["armor"]
	run(sim, H, 1)
	var armored := run_until(sim, func(): return bark.is_armored(), 30, H)
	assert_true(armored, "armored once the windup is over")
	assert_true(bark.state_t <= int(ar["to"]), "while it spins")


## The burst is 32 px since his buff (Oct 2026): a foe right next to him is no longer
## under the arc but at the edge of the burst, so this only checks where it lands.
func test_pinecone_bursts_where_it_lands() -> void:
	var sim := _duel("cairn", 2.0)
	var barkley := sim.creatures[0]
	var mv: Dictionary = barkley.def["moves"]["skill_2"]
	var pr: Dictionary = mv["projectile"]
	tap(sim, S2, int(mv["startup"]) + 1)
	assert_eq(sim.projectiles.size(), 1, "a pinecone in the air")
	var burst := run_until(sim, func(): return not _events(sim, "burst").is_empty(), int(pr["time"]) + 5)
	assert_true(burst, "it lands and bursts")
	var at: Vector2 = _events(sim, "burst")[0]["pos"]
	var expect := barkley.pos.x + float(pr["offset"]) + float(pr["range"])
	assert_near(at.x, expect, 1.5, "lands range + offset ahead:")
	assert_eq(float(_events(sim, "burst")[0]["power"]), float(pr["burst"]), "its burst radius:")


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
	assert_false(sim.creatures[1].is_airborne(), "no pop-up any more (the Oct 27 rework)")
	var want := int(sim.creatures[0].def["moves"]["skill_2"]["root_ticks"])
	assert_eq(sim.creatures[1].root, want, "it roots the foe for the throw's root_ticks:")
	assert_eq(sim.plants.size(), 0, "a hit never plants a seed")
	run(sim, 0, want + 20)  # (plus the hitstop, which holds everything)
	assert_eq(sim.creatures[1].root, 0, "the root wears off")


## Pinecone Bomb (Oct 27 rework): a 12 s cooldown, a throw 20% further, a root on a hit
## and a seed on a miss that grows a plant, a tree and a healing apple (Plants).
func test_pinecone_has_a_12_second_cooldown() -> void:
	var sim := _duel("cairn", 2.0)
	var barkley := sim.creatures[0]
	assert_eq(int(barkley.def["moves"]["skill_2"]["cooldown"]), 720, "the tunable cooldown, in ticks (12 s):")
	tap(sim, S2, 60)
	assert_false(barkley.can_use("skill_2"), "not ready a second after the throw")
	run(sim, 0, 720 - 60 - 40)
	assert_false(barkley.can_use("skill_2"), "nor just before 12 s")
	run(sim, 0, 60)
	assert_true(barkley.can_use("skill_2"), "ready after 12 s")


func test_pinecone_flies_20_percent_further_than_before() -> void:
	var pr: Dictionary = MatchFactory.load_def("barkley")["moves"]["skill_2"]["projectile"]
	assert_near(float(pr["range"]), 48.0 * 1.2, 0.01, "a tap (was 48):")
	assert_near(float(pr["range_charged"]), 110.0 * 1.2, 0.01, "a full hold (was 110):")


## Barkley 2 px from Cairn, a tapped pinecone thrown past him at nobody.
func _miss(sim: MatchSim) -> Vector2:
	run(sim, S2, 1)  # a tap: the shortest throw
	var burst := run_until(sim, func(): return not _events(sim, "burst").is_empty(), 60)
	assert_true(burst, "it bursts")
	assert_eq(int(_events(sim, "burst")[0]["landed"]), 0, "on nobody:")
	return _events(sim, "burst")[0]["pos"]


func test_a_pinecone_that_misses_plants_a_seed_where_it_lands() -> void:
	var sim := _duel("cairn", 2.0)
	sim.creatures[1].pos = sim.creatures[0].pos + Vector2(0, -120)  # out of the throw's way
	var at := _miss(sim)
	assert_eq(sim.plants.size(), 1, "one plant:")
	var pl: Dictionary = sim.plants[0]
	assert_near(Vector2(pl["pos"]).distance_to(at), 0.0, 0.01, "where the pinecone fell")
	assert_eq(int(pl["owner"]), 0, "Barkley's")
	assert_eq(float(pl["hp"]), 10.0, "10 HP:")
	assert_eq(int(pl["stage"]), Plants.PLANT, "a sprout")
	assert_eq(int(pl["root"]), int(sim.creatures[0].def["moves"]["skill_2"]["root_ticks"]) / 2,
		"it roots for half the throw's root (derived, not written down):")


func test_a_foe_who_treads_on_the_plant_is_rooted_and_springs_it() -> void:
	var sim := _duel("cairn", 2.0)
	var foe := sim.creatures[1]
	foe.pos = sim.creatures[0].pos + Vector2(0, -120)
	var at := _miss(sim)
	run(sim, 0, 30)
	foe.pos = at + Vector2(4, 0)  # steps onto it
	sim.step(PackedInt32Array([0, 0]))
	assert_eq(foe.root, int(sim.creatures[0].def["moves"]["skill_2"]["root_ticks"]) / 2, "rooted for 0.75 s:")
	assert_false(_events(sim, "plant_root").is_empty(), "the plant_root event")
	assert_eq(sim.plants.size(), 0, "and the plant is spent (one spring, then gone)")
	foe.pos = at + Vector2(4, 0)
	run(sim, 0, 60)
	assert_eq(foe.root, 0, "the root wears off")


func test_barkleys_own_side_walks_over_the_plant() -> void:
	var sim := _duel("cairn", 2.0)
	sim.creatures[1].pos = sim.creatures[0].pos + Vector2(0, -120)
	var at := _miss(sim)
	run(sim, 0, 30)
	sim.creatures[0].pos = at
	run(sim, 0, 10)
	assert_eq(sim.creatures[0].root, 0, "Barkley isn't rooted by his own plant")
	assert_eq(sim.plants.size(), 1, "and it stays")


func test_a_foe_can_hit_the_plant_down() -> void:
	var sim := _duel("cairn", 2.0)
	var foe := sim.creatures[1]
	foe.pos = sim.creatures[0].pos + Vector2(0, -120)
	var at := _miss(sim)
	run(sim, 0, 30)
	# Cairn stands a step outside the sprout (his jab's lunge mustn't carry him onto it)
	# and jabs it: 10 HP goes in a few lights.
	var pl: Dictionary = sim.plants[0]
	foe.pos = at + Vector2(float(pl["radius"]) + foe.radius + 14.0, 0)
	foe.facing = Vector2.LEFT
	var hits := 0
	for i in 200:
		sim.step(PackedInt32Array([0, L if i % 2 == 0 else 0]))
		hits += _events(sim, "plant_hit").size()
		foe.pos.x = maxf(foe.pos.x, at.x + float(pl["radius"]) + foe.radius + 2.0)  # the lunge doesn't tread on it
		if sim.plants.is_empty():
			break
	assert_gt(hits, 0, "the jabs land on the plant:")
	assert_eq(sim.plants.size(), 0, "and kill it")
	assert_eq(String(_events(sim, "plant_gone")[0]["how"]), "killed", "how it went:")
	assert_eq(foe.root, 0, "without being rooted")


func test_a_foes_shots_hurt_the_plant_and_fly_on() -> void:
	var sim := _duel("cerebro", 2.0)
	var chef := sim.creatures[1]
	chef.pos = sim.creatures[0].pos + Vector2(0, -120)
	var at := _miss(sim)
	run(sim, 0, 30)
	chef.pos = at + Vector2(50, 0)
	chef.facing = Vector2.LEFT
	var hits := 0
	var ended_past := false
	for i in 200:
		sim.step(PackedInt32Array([0, L if i % 2 == 0 else 0]))
		hits += _events(sim, "plant_hit").size()
		for e in _events(sim, "projectile_end"):
			if Vector2(e["pos"]).x < at.x - 5.0:
				ended_past = true  # a knife went on past the plant
		if sim.plants.is_empty():
			break
	assert_gt(hits, 1, "the knives hit the plant:")
	assert_true(ended_past, "and fly on past it")
	assert_eq(sim.plants.size(), 0, "three flicks and a mallet kill it")


func test_barkley_cannot_hurt_his_own_plant() -> void:
	var sim := _duel("cairn", 2.0)
	sim.creatures[1].pos = sim.creatures[0].pos + Vector2(0, -120)
	var at := _miss(sim)
	run(sim, 0, 30)
	sim.creatures[0].pos = at + Vector2(-20, 0)
	for i in 40:
		sim.step(PackedInt32Array([L if i % 2 == 0 else 0, 0]))
	assert_eq(sim.plants.size(), 1, "his swings pass his own sprout")
	assert_eq(float(sim.plants[0]["hp"]), 10.0, "untouched:")


## Lets a sprout sit `grow_seconds` with nobody near it.
func _grown(sim: MatchSim) -> Vector2:
	sim.creatures[1].pos = sim.creatures[0].pos + Vector2(0, -120)
	var at := _miss(sim)
	var seed: Dictionary = sim.creatures[0].def["moves"]["skill_2"]["projectile"]["seed"]
	run(sim, 0, int(seed["grow_seconds"]) * SimDefs.TICK_RATE + 2)
	return at


func test_a_plant_left_35_seconds_grows_into_a_tree_that_bears_an_apple() -> void:
	var sim := _duel("cairn", 2.0)
	var grow_ticks := 35 * SimDefs.TICK_RATE
	sim.creatures[1].pos = sim.creatures[0].pos + Vector2(0, -120)
	_miss(sim)
	run(sim, 0, grow_ticks - 10)
	assert_eq(int(sim.plants[0]["stage"]), Plants.PLANT, "still a sprout before 35 s")
	run(sim, 0, 12)
	assert_eq(int(sim.plants[0]["stage"]), Plants.TREE, "a tree after 35 s")
	assert_false(bool(sim.plants[0]["apple"]), "no apple yet")
	run(sim, 0, 2 * SimDefs.TICK_RATE + 2)
	assert_true(bool(sim.plants[0]["apple"]), "an apple two seconds later")


func test_a_hurt_ally_who_takes_the_apple_heals_15_percent_of_their_max_hp() -> void:
	var sim := _duel("cairn", 2.0)
	var barkley := sim.creatures[0]
	var at := _grown(sim)
	run(sim, 0, 2 * SimDefs.TICK_RATE + 2)
	barkley.hp = barkley.max_hp * 0.5
	barkley.pos = at
	sim.step(PackedInt32Array([0, 0]))
	assert_near(barkley.hp, barkley.max_hp * 0.65, 0.01, "half, plus 15% of his own max:")
	assert_near(float(_events(sim, "apple_eaten")[0]["power"]), barkley.max_hp * 0.15, 0.01, "the event says how much:")
	assert_eq(sim.plants.size(), 0, "one apple, then the tree is gone")


func test_a_full_ally_walks_past_the_apple() -> void:
	var sim := _duel("cairn", 2.0)
	var at := _grown(sim)
	run(sim, 0, 2 * SimDefs.TICK_RATE + 2)
	sim.creatures[0].pos = at
	run(sim, 0, 5)
	assert_eq(sim.plants.size(), 1, "at full health he doesn't take it")


func test_a_foe_who_takes_the_apple_spoils_it() -> void:
	var sim := _duel("cairn", 2.0)
	var foe := sim.creatures[1]
	var at := _grown(sim)
	run(sim, 0, 2 * SimDefs.TICK_RATE + 2)
	foe.hp = foe.max_hp * 0.5
	foe.pos = at
	sim.step(PackedInt32Array([0, 0]))
	assert_near(foe.hp, foe.max_hp * 0.5, 0.01, "heals nothing:")
	assert_false(_events(sim, "apple_spoiled").is_empty(), "spoiled")
	assert_eq(sim.plants.size(), 0, "and the tree is gone")


func test_a_tree_cannot_be_hit_and_does_not_root() -> void:
	var sim := _duel("cairn", 2.0)
	var foe := sim.creatures[1]
	var at := _grown(sim)
	foe.pos = at + Vector2(4, 0)
	for i in 40:
		sim.step(PackedInt32Array([0, L if i % 2 == 0 else 0]))
	assert_eq(foe.root, 0, "a tree roots nobody")
	assert_eq(sim.plants.size(), 1, "and can't be cut down")


func test_rollback_through_a_growing_plant() -> void:
	var sim := _duel("cairn", 2.0)
	sim.creatures[1].pos = sim.creatures[0].pos + Vector2(0, -120)
	var at := _miss(sim)
	run(sim, 0, 20)
	var snap := sim.snapshot()
	sim.creatures[1].pos = at + Vector2(4, 0)  # treads on it after the snapshot
	run(sim, 0, 40, L)
	var once := sim.state_digest()
	assert_eq(sim.plants.size(), 0, "sprung in the first run")
	sim.restore(snap)
	assert_eq(sim.plants.size(), 1, "the snapshot has the plant back")
	sim.creatures[1].pos = at + Vector2(4, 0)
	run(sim, 0, 40, L)
	assert_eq(sim.state_digest(), once, "replaying from the snapshot gives the same state:")


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


func test_root_eruption_last_ring_roots_a_foe_85_px_away() -> void:
	var sim := _duel("cairn", 34.0)
	sim.creatures[0].energy = 100.0
	var foe := sim.creatures[1]
	foe.pos = sim.creatures[0].pos + Vector2(0, -85)  # only the third ring reaches
	var hit := run_until(sim, func(): return not _events(sim, "hit").is_empty(), 80, SU)
	assert_true(hit, "the outer ring reaches 85 px away")
	assert_eq(foe.state, CreatureSim.State.HITSTUN, "the last ring staggers (no crumple since the Oct 27 rework)")
	assert_eq(foe.root, 60, "and roots for 1 s:")
	run_until(sim, func(): return not foe.is_stunned(), 120)
	assert_gt(foe.root, 0, "the roots still hold after the stun: no walking, no rolling away")
	run(sim, 0, 60)
	assert_eq(foe.root, 0, "and let go a second after the hit")


## Root Eruption's block rule (Oct 27 rework): the root is unblockable, the damage isn't.
## Cairn 85 px above him (only the last ring reaches), facing him. (Every ring roots: a
## closer foe is rooted from the first, and the later rings refresh it.)
func _eruption_on_a_guard(stamina: float, guard: bool) -> Array:
	var sim := _duel("cairn", 34.0)
	sim.creatures[0].energy = 100.0
	var foe := sim.creatures[1]
	foe.pos = sim.creatures[0].pos + Vector2(0, -85)
	foe.facing = Vector2.DOWN  # toward Barkley: a guard has to face the hit
	foe.stamina = stamina
	foe.regen_wait = 100000  # no regen meanwhile
	var hp := foe.hp
	var seen := {}
	var root_peak := 0  # the root as it was set (it ticks down after)
	for i in 110:  # the Surge's freeze, the windup, the three rings
		sim.step(PackedInt32Array([SU if i == 0 else 0, GUARD if guard else 0]))
		for e in sim.events:
			seen[String(e["type"])] = e
		root_peak = maxi(root_peak, foe.root)
	return [sim, foe, hp, seen, root_peak]


func test_eruption_on_a_guard_with_stamina_roots_but_does_no_damage() -> void:
	var r := _eruption_on_a_guard(100.0, true)
	var foe: CreatureSim = r[1]
	var seen: Dictionary = r[3]
	assert_true(seen.has("block"), "the ring is blocked")
	assert_false(seen.has("hit"), "no clean hit")
	assert_eq(foe.hp, float(r[2]), "no damage through the guard:")
	assert_lt(foe.stamina, 100.0, "the guard pays stamina as any block does:")
	assert_eq(int(r[4]), 60, "but is rooted for the full second:")
	assert_true(bool(seen["rooted"].get("blocked", false)), "the rooted event says it came through a guard")


func test_eruption_on_a_guard_with_no_stamina_lands_in_full_and_roots() -> void:
	# Stamina too low for the ring's drain: the guard drops ("EXHAUSTED") and the ring lands clean.
	var r := _eruption_on_a_guard(1.0, true)
	var foe: CreatureSim = r[1]
	var seen: Dictionary = r[3]
	assert_true(seen.has("guard_break") and bool(seen["guard_break"].get("drained", false)), "the guard is drained")
	assert_true(seen.has("hit"), "the ring lands clean")
	assert_near(float(r[2]) - foe.hp, 16.8, 0.01, "full damage:")
	assert_eq(int(r[4]), 60, "and rooted for 1 s:")
	# And at exactly zero stamina there is no guard to raise at all: the same result.
	var r0 := _eruption_on_a_guard(0.0, true)
	var foe0: CreatureSim = r0[1]
	assert_false((r0[3] as Dictionary).has("block"), "nothing to block with at 0 stamina")
	assert_near(float(r0[2]) - foe0.hp, 16.8, 0.01, "full damage:")
	assert_eq(int(r0[4]), 60, "rooted:")


func test_eruption_on_a_foe_not_blocking_lands_in_full_and_roots() -> void:
	var r := _eruption_on_a_guard(100.0, false)
	var foe: CreatureSim = r[1]
	var seen: Dictionary = r[3]
	assert_true(seen.has("hit"), "a clean hit")
	assert_near(float(r[2]) - foe.hp, 16.8, 0.01, "full damage:")
	assert_eq(int(r[4]), 60, "and rooted for 1 s:")
	assert_false(foe.state == CreatureSim.State.CRUMPLE, "no crumple any more")


func test_three_blocked_rings_do_not_exhaust_a_full_guard() -> void:
	var sim := _duel("cairn", 20.0)
	sim.creatures[0].energy = 100.0
	var foe := sim.creatures[1]
	run_until(sim, func(): return sim.creatures[0].move_id == "surge", 10, SU)
	for i in 70:
		sim.step(PackedInt32Array([0, GUARD]))
	# The rings hit 40% harder since Oct 2026 (area Surges x1.4), so the guard ends nearly
	# spent (about 16 of 100) but holds.
	assert_gt(foe.stamina, 0.0, "a full guard holds through the three rings:")
	assert_true(foe.state != CreatureSim.State.CRUMPLE, "and isn't broken")


func test_every_ring_of_root_eruption_roots() -> void:
	var sim := _duel("cairn", 34.0)
	sim.creatures[0].energy = 100.0
	var foe := sim.creatures[1]
	foe.pos = sim.creatures[0].pos + Vector2(0, -30)  # inside the first ring
	var hit := run_until(sim, func(): return not _events(sim, "hit").is_empty(), 80, SU)
	assert_true(hit, "the first ring lands")
	assert_eq(foe.root, 60, "and roots at once (Kevin's ruling: every ring, not just the last):")
	var hits := 1
	var peak := 0
	for i in 40:
		sim.step(PackedInt32Array([0, 0]))
		hits += _events(sim, "hit").size()
		peak = maxi(peak, foe.root)
	assert_eq(hits, 3, "all three rings land on a close foe:")
	assert_eq(peak, 60, "the later rings refresh the root to a full second, never stack past it:")
