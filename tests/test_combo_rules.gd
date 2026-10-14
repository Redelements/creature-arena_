extends TestCase
## The combo rules one at a time: variety bonus, stale moves, hitstun decay, juggle cap,
## cancels only on contact, stacks, energy, cooldowns, breakaway, grabs, Slip, Runoff.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE
const G := SimDefs.IN_GUARD
const D := SimDefs.IN_DODGE


func _duel(left := "cairn", right := "culvert", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


## A synthetic hit for exercising MatchSim._apply_hit directly.
func _hit(type: String, move_id: String, serial: int, damage := 10.0, extra := {}) -> Dictionary:
	var h := {
		"attacker": 0, "move_id": move_id, "type": type, "serial": serial,
		"damage": damage, "knockback": 0.0, "hitstun": 20.0, "hitstop": 0.0,
		"launch": 0.0, "crumple": 0.0, "knockdown": 0.0,
		"guard_break": false, "grab": false, "juggle": false, "stack_bonus": 0.0,
	}
	h.merge(extra, true)
	return h


func test_variety_bonus_grows_with_each_new_type() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	a.stack = 0
	var hp0 := d.hp
	sim._apply_hit(a, d, _hit("light", "light_1", 1), Vector2.RIGHT, d.pos)
	assert_near(hp0 - d.hp, 10.0, 0.001, "1 type:")
	hp0 = d.hp
	sim._apply_hit(a, d, _hit("heavy", "heavy", 2), Vector2.RIGHT, d.pos)
	assert_near(hp0 - d.hp, 11.5, 0.001, "2 types:")
	hp0 = d.hp
	sim._apply_hit(a, d, _hit("skill", "skill_2", 3), Vector2.RIGHT, d.pos)
	assert_near(hp0 - d.hp, 13.0, 0.001, "3 types:")
	hp0 = d.hp
	sim._apply_hit(a, d, _hit("surge", "surge", 4), Vector2.RIGHT, d.pos)
	assert_near(hp0 - d.hp, 15.0, 0.001, "4 types:")


func test_repeated_move_is_stale() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	sim._apply_hit(a, d, _hit("light", "light_1", 1), Vector2.RIGHT, d.pos)
	var hp0 := d.hp
	sim._apply_hit(a, d, _hit("light", "light_1", 1), Vector2.RIGHT, d.pos)
	assert_near(hp0 - d.hp, 10.0, 0.001, "second hit of the same move instance is not stale:")
	hp0 = d.hp
	sim._apply_hit(a, d, _hit("light", "light_1", 2), Vector2.RIGHT, d.pos)
	assert_near(hp0 - d.hp, 5.0, 0.001, "same move used again in the combo:")


func test_hitstun_decays_over_a_long_combo() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	for i in 8:
		sim._apply_hit(a, d, _hit("light", "move_%d" % i, i + 1, 1.0), Vector2.RIGHT, d.pos)
	sim._apply_hit(a, d, _hit("light", "move_9", 99, 1.0), Vector2.RIGHT, d.pos)
	assert_eq(d.combo_hits, 9, "hits:")
	assert_eq(d.stun, 9, "9th hit stun (20 x 0.44):")
	for i in 5:
		sim._apply_hit(a, d, _hit("light", "late_%d" % i, 200 + i, 1.0), Vector2.RIGHT, d.pos)
	assert_eq(d.stun, 8, "stun never drops below 40%:")


func test_juggle_cap_is_three_moves() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	sim._apply_hit(a, d, _hit("heavy", "heavy", 1, 9.0, {"launch": 40.0}), Vector2.RIGHT, d.pos)
	assert_true(d.is_airborne(), "launched")
	for i in 3:
		var jh := _hit("light", "j_%d" % i, 10 + i, 1.0, {"juggle": true})
		assert_true(sim._hittable(d, jh), "juggle %d allowed" % (i + 1))
		sim._apply_hit(a, d, jh, Vector2.RIGHT, d.pos)
		# a second hit of the same move doesn't spend another point
		assert_true(sim._hittable(d, jh), "multi-hit move %d keeps hitting" % (i + 1))
	assert_eq(d.juggles, 3, "juggle points:")
	assert_false(sim._hittable(d, _hit("light", "j_4", 20, 1.0, {"juggle": true})), "4th juggle move")
	assert_false(sim._hittable(d, _hit("light", "x", 21, 1.0)), "non-juggle move vs airborne")


func test_cancel_needs_contact() -> void:
	var sim := _duel("cairn", "culvert", 80.0)  # far apart: the jab whiffs
	var a := sim.creatures[0]
	tap(sim, L, 2)
	tap(sim, S2, 0)
	var rushed := run_until(sim, func(): return a.move_id == "skill_2", 30)
	assert_false(rushed, "a whiffed jab can't cancel into Rockslide Rush")


func test_cancel_into_higher_rank_on_hit() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	tap(sim, L, 6)
	assert_true(a.connected, "jab connected")
	tap(sim, S2, 4)
	assert_eq(a.move_id, "skill_2", "cancelled into Rush:")


func test_no_cancel_down_the_ranks() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	tap(sim, L, 6)
	tap(sim, S2, 8)
	assert_eq(a.move_id, "skill_2", "rush:")
	tap(sim, H, 0)
	run(sim, 0, 5)
	assert_eq(a.move_id, "skill_2", "a skill can't cancel back into a heavy:")


func test_stack_builds_on_lights_and_is_spent() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"]])
	assert_eq(a.stack, 3, "stones after three lights:")
	var sim2 := _duel()
	var a2 := sim2.creatures[0]
	route(sim2, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S2, "skill_2"]])
	assert_eq(a2.stack, 0, "Rush spends the stack:")


func test_stack_empties_after_timeout() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	tap(sim, L, 20)
	assert_eq(a.stack, 1, "one stone:")
	run(sim, 0, 200)
	assert_eq(a.stack, 0, "stack expired:")


func test_energy_fills_from_damage() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	tap(sim, L, 20)
	assert_near(a.energy, 4.5, 0.001, "attacker energy:")
	assert_near(d.energy, 3.0, 0.001, "defender energy:")


func test_surge_needs_a_full_bar() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	a.energy = 60.0
	tap(sim, SU, 5)
	assert_true(a.state != CreatureSim.State.ATTACK, "no Surge at 60 energy")
	a.energy = 100.0
	tap(sim, SU, 0)
	assert_eq(a.move_id, "surge", "Surge at full energy:")
	assert_near(a.energy, 0.0, 0.001, "energy spent:")


func test_skills_have_cooldowns() -> void:
	var sim := _duel("cairn", "culvert", 120.0)
	var a := sim.creatures[0]
	tap(sim, S2, 40)
	assert_false(a.can_use("skill_2"), "Rush on cooldown")
	tap(sim, S2, 5)
	assert_true(a.state != CreatureSim.State.ATTACK, "can't Rush again yet")
	run(sim, 0, 150)
	assert_true(a.can_use("skill_2"), "Rush ready after 3 s")


func test_breakaway_escapes_a_combo() -> void:
	var sim := _duel("culvert", "cairn")
	var d := sim.creatures[1]
	d.energy = 60.0
	var press := true
	for i in 80:  # mash lights until the third hit lands
		run(sim, L if press else 0, 1)
		press = not press
		if d.combo_hits >= 3:
			break
	assert_eq(d.combo_hits, 3, "combo reached 3 hits:")
	assert_true(d.is_stunned(), "stunned")
	var energy_before := d.energy
	run(sim, 0, 1, G | D)
	assert_eq(d.state, CreatureSim.State.IDLE, "free:")
	assert_eq(d.invuln, CreatureSim.BREAKAWAY_INVULN, "invulnerable:")
	assert_near(d.energy, energy_before - 50.0, 0.001, "energy spent:")
	assert_eq(d.combo_hits, 0, "combo reset:")


func test_breakaway_not_on_the_first_hits() -> void:
	var sim := _duel("culvert", "cairn")
	var d := sim.creatures[1]
	d.energy = 100.0
	tap(sim, L, 6)
	assert_eq(d.combo_hits, 1, "one hit:")
	run(sim, 0, 1, G | D)
	assert_true(d.is_stunned(), "still stunned after one hit")


func test_gulp_ignores_guard() -> void:
	var sim := _duel("culvert", "cairn")
	var c := sim.creatures[0]
	var d := sim.creatures[1]
	run(sim, 0, 2, G)
	assert_eq(d.state, CreatureSim.State.GUARD, "guarding:")
	run(sim, S1, 1, G)
	var grabbed := run_until(sim, func(): return d.state == CreatureSim.State.KNOCKDOWN, 20, 0, G)
	assert_true(grabbed, "Gulp should grab through guard")
	assert_near(d.max_hp - d.hp, 12.0, 0.001, "grab damage:")
	assert_lt(d.pos.x, c.pos.x, "spat out behind Culvert:")


func test_slip_counters_strikes_but_not_grabs() -> void:
	var sim := _duel("cairn", "culvert")
	var cairn := sim.creatures[0]
	var culvert := sim.creatures[1]
	sim.step(PackedInt32Array([S1, S1]))  # Slip vs Gulp
	run(sim, 0, 20)
	assert_true(cairn.state == CreatureSim.State.KNOCKDOWN or cairn.hp < cairn.max_hp, "grab beats Slip")
	assert_true(cairn.move_id != "slip_counter", "no counter against a grab")
	assert_near(culvert.hp, culvert.max_hp, 0.001, "Culvert untouched:")


func test_slip_counter_crumples() -> void:
	var sim := _duel("cairn", "culvert")
	var cairn := sim.creatures[0]
	var culvert := sim.creatures[1]
	sim.step(PackedInt32Array([S1, L]))
	var crumpled := run_until(sim, func(): return culvert.state == CreatureSim.State.CRUMPLE, 30)
	assert_true(crumpled, "counter should crumple the attacker")
	assert_near(cairn.hp, cairn.max_hp, 0.001, "Cairn took no damage:")


func test_runoff_washes_the_target_back_without_launching() -> void:
	var sim := _duel("culvert", "cairn", 24.0)
	var d := sim.creatures[1]
	var x0 := d.pos.x
	tap(sim, S2, 0)
	var hit := run_until(sim, func(): return d.hp < d.max_hp, 60)
	assert_true(hit, "the wave hits a foe in front")
	assert_false(d.is_airborne(), "it pushes rather than pops up")
	run(sim, 0, 30)
	assert_gt(d.pos.x - x0, 12.0, "washed back a little:")
	assert_eq(sim.terrain.count(TerrainGrid.HOLE), 0, "the wave never opens holes:")


func test_storm_drain_rings_culvert_with_pits() -> void:
	var sim := _duel("culvert", "cairn", 120.0)
	var c := sim.creatures[0]
	c.energy = 100.0
	tap(sim, SU, 60)
	assert_gt(sim.terrain.count(TerrainGrid.HOLE), 20, "pit ring:")
	assert_false(sim.terrain.is_hole_at(c.pos), "Culvert stands on the island")


func test_launch_ends_in_knockdown() -> void:
	var sim := _duel()
	var d := sim.creatures[1]
	tap(sim, H, 0)
	var up := run_until(sim, func(): return d.is_airborne(), 20)
	assert_true(up, "Haymaker launches")
	var down := run_until(sim, func(): return d.state == CreatureSim.State.KNOCKDOWN, 80)
	assert_true(down, "lands in a knockdown")
	var back := run_until(sim, func(): return d.state == CreatureSim.State.IDLE, 60)
	assert_true(back, "gets back up")
	assert_eq(d.combo_hits, 0, "combo over:")
