extends TestCase
## Digby's kit: Headlamp Flash blinds (the next attack misses), Burrow tunnels out of
## reach where you steer and pops up under the foe, Pickaxe Pop-Up launches from a
## distance, and Cave-In roots everyone it catches.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE
const GUARD := SimDefs.IN_GUARD


## Digby on the left, `foe` on the right with `gap` pixels between their bodies.
func _duel(foe := "cairn", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus("digby", foe)
	sim.creatures[0].pos = Vector2(200, 164)
	sim.creatures[1].pos = Vector2(200 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


## Steps `ticks` ticks with these inputs and counts events of `kind`.
func _count(sim: MatchSim, kind: String, ticks: int, p0 := 0, p1 := 0) -> int:
	var n := 0
	for i in ticks:
		sim.step(PackedInt32Array([p0, p1]))
		for e in sim.events:
			if String(e["type"]) == kind:
				n += 1
	return n


func test_headlamp_flash_makes_the_next_attack_miss() -> void:
	var sim := _duel("cairn", 8.0)
	var dig := sim.creatures[0]
	var foe := sim.creatures[1]
	assert_eq(_count(sim, "blinded", 20, S1), 1, "the flash blinds Cairn:")
	assert_gt(float(foe.blind), 0.0, "blinded")
	run_until(sim, func(): return not foe.is_stunned(), 60)
	run_until(sim, func(): return dig.state == CreatureSim.State.IDLE, 60)
	var hp := dig.hp
	var misses := _count(sim, "miss", 40, 0, L)
	assert_eq(misses, 1, "Cairn's jab misses:")
	assert_eq(dig.hp, hp, "Digby takes nothing")
	assert_eq(foe.blind, 0, "the blind is used up")
	run(sim, 0, 30)
	var hits := _count(sim, "hit", 40, 0, L)
	assert_gt(float(hits), 0.0, "and the attack after that lands")


func test_blindness_wears_off() -> void:
	var sim := _duel("cairn", 8.0)
	var foe := sim.creatures[1]
	tap(sim, S1, 20)
	var ticks := int(sim.creatures[0].def["moves"]["skill_1"]["blind_ticks"])
	run(sim, 0, ticks)
	assert_eq(foe.blind, 0, "the blind wears off if they wait it out:")


func test_guarding_the_flash_stops_the_blind() -> void:
	var sim := _duel("cairn", 8.0)
	run(sim, 0, 2, GUARD)
	assert_eq(_count(sim, "blinded", 30, S1, GUARD), 0, "a guarded flash blinds no one:")


func test_burrow_is_out_of_reach_and_pops_up_under_the_foe() -> void:
	var sim := _duel("cairn", 96.0)
	var dig := sim.creatures[0]
	var foe := sim.creatures[1]
	tap(sim, S2, 12)
	assert_true(dig.is_invulnerable(), "underground: nothing can touch him")
	assert_false(dig.is_solid(), "and he passes under bodies")
	var launched := run_until(sim, func(): return foe.state == CreatureSim.State.AIRBORNE, 60)
	assert_true(launched, "he pops up under Cairn and knocks him up")


func test_burrow_steers() -> void:
	var sim := _duel("cairn", 160.0)
	var dig := sim.creatures[0]
	var y0 := dig.pos.y
	run(sim, S2, 1)
	run(sim, SimDefs.IN_DOWN, 40)
	assert_gt(dig.pos.y, y0 + 20.0, "holding down turns the tunnel down the arena:")


func test_burrow_crosses_pits() -> void:
	var sim := _duel("cairn", 160.0)
	var dig := sim.creatures[0]
	for x in range(30, 90, 4):
		sim.terrain.set_cell(sim.terrain.world_to_cell(dig.pos + Vector2(x, 0)), TerrainGrid.HOLE)
	tap(sim, S2, 50)
	assert_true(dig.state != CreatureSim.State.FALLING, "he tunnels under the pit")
	assert_gt(dig.pos.x, 290.0, "and comes out the far side:")


func test_pickaxe_pop_up_reaches_a_foe_away_from_him() -> void:
	var sim := _duel("cairn", 26.0)
	var foe := sim.creatures[1]
	var launched := run_until(sim, func(): return foe.state == CreatureSim.State.AIRBORNE, 60, H)
	assert_true(launched, "the pickaxe bursts up under a foe 26 px away")


func test_cave_in_roots() -> void:
	var sim := _duel("cairn", 6.0)
	var foe := sim.creatures[1]
	sim.creatures[0].energy = 100.0
	var rooted := run_until(sim, func(): return foe.root > 0, 60, SU)
	assert_true(rooted, "Cave-In roots Cairn")
	run_until(sim, func(): return not foe.is_stunned(), 80)
	assert_gt(float(foe.root), 0.0, "still rooted once he can act")
	var x := foe.pos.x
	run(sim, 0, 10, SimDefs.IN_RIGHT)
	assert_near(foe.pos.x, x, 0.01, "rooted: he can't walk away:")
	run(sim, 0, 2, SimDefs.IN_DODGE)
	assert_true(foe.state != CreatureSim.State.DODGE, "or dodge")
	run(sim, 0, foe.root + 1)
	run(sim, 0, 10, SimDefs.IN_RIGHT)
	assert_gt(foe.pos.x, x + 1.0, "and then he can move again:")


func test_rollback_with_blind_root_and_burrow() -> void:
	var sim := _duel("culvert", 40.0)
	var foe := sim.creatures[1]
	foe.blind = 100
	foe.root = 60
	run(sim, S2, 1)
	run(sim, 0, 10)
	var snap := sim.snapshot()
	run(sim, 0, 80, L)
	var once := sim.state_digest()
	sim.restore(snap)
	run(sim, 0, 80, L)
	assert_eq(sim.state_digest(), once, "replaying from the snapshot gives the same state:")


func test_cave_in_roots_a_foe_95_px_ahead_and_cracks_the_floor() -> void:
	var sim := _duel("cairn", 95.0)
	var digby := sim.creatures[0]
	var foe := sim.creatures[1]
	digby.energy = 100.0
	var cracked := sim.terrain.count(TerrainGrid.CRACKED)
	var rooted := run_until(sim, func(): return foe.root > 0, 80, SU)
	assert_true(rooted, "Cave-In roots a foe 95 px ahead of him")
	assert_gt(sim.terrain.count(TerrainGrid.CRACKED), cracked, "and the floor cracks where it lands")
