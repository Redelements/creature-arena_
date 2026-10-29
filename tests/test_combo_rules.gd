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
	assert_near(a.energy, 3.0 * MatchSim.energy_rate_dealt() * _rule("light") * _var_energy(1), 0.001, "attacker energy (a light: x the light mult):")
	assert_near(d.energy, 1.5, 0.001, "defender energy:")


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
	var sim := _duel("craglash", "cairn")  # every hit of his staggers
	var d := sim.creatures[1]
	d.energy = 60.0
	var press := true
	for i in 160:  # Rake > Rockslide Stomp > Landslide Charge, mashed, until the third hit lands
		var bit: int = [L, H, S1][mini(d.combo_hits, 2)]
		run(sim, bit if press else 0, 1)
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
	var sim := _duel("craglash", "cairn")  # his lights stagger on every hit
	var d := sim.creatures[1]
	d.energy = 100.0
	tap(sim, L, 1)  # his Rake is slow: wait for it to land
	run_until(sim, func(): return d.combo_hits >= 1, 40)
	run(sim, 0, 2)
	assert_eq(d.combo_hits, 1, "one hit:")
	run(sim, 0, 1, G | D)
	assert_true(d.is_stunned(), "still stunned after one hit")


func test_gulp_ignores_guard() -> void:
	# Tapped: the tongue hooks a guarding foe and hauls them in.
	var sim := _duel("culvert", "cairn")
	var c := sim.creatures[0]
	var d := sim.creatures[1]
	run(sim, 0, 2, G)
	assert_eq(d.state, CreatureSim.State.GUARD, "guarding:")
	run(sim, S1, 1, G)
	var hooked := run_until(sim, func(): return d.state == CreatureSim.State.HITSTUN, 30, 0, G)
	assert_true(hooked, "the tongue should hook through guard")
	assert_near(d.max_hp - d.hp, 6.0, 0.001, "hook damage:")
	# Held: swallowed and spat out behind him.
	sim = _duel("culvert", "cairn")
	c = sim.creatures[0]
	d = sim.creatures[1]
	run(sim, 0, 2, G)
	var grabbed := run_until(sim, func(): return d.state == CreatureSim.State.AIRBORNE, 50, S1, G)
	assert_true(grabbed, "a held Gulp should swallow through guard")
	assert_near(d.max_hp - d.hp, 12.0, 0.001, "swallow damage:")
	run(sim, 0, 40)
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


func test_runoff_tapped_is_a_short_shove() -> void:
	var sim := _duel("culvert", "cairn", 6.0)
	var d := sim.creatures[1]
	var x0 := d.pos.x
	tap(sim, S2, 0)
	var hit := run_until(sim, func(): return d.hp < d.max_hp, 60)
	assert_true(hit, "the shove hits a foe up close")
	assert_false(d.is_airborne(), "it pushes rather than pops up")
	run(sim, 0, 40)
	assert_gt(d.pos.x - x0, 30.0, "shoved well back:")
	assert_eq(d.slow, 0, "a tap doesn't slow")
	var mid := _duel("culvert", "cairn", 45.0)
	tap(mid, S2, 0)
	run(mid, 0, 60)
	assert_lt(mid.creatures[1].hp, mid.creatures[1].max_hp, "twice the old reach: 45 px away it hits")
	var far := _duel("culvert", "cairn", 65.0)
	tap(far, S2, 0)
	run(far, 0, 60)
	assert_eq(far.creatures[1].hp, far.creatures[1].max_hp, "still short: 65 px away it misses")


func test_runoff_held_sends_the_wave_that_slows() -> void:
	var sim := _duel("culvert", "cairn", 100.0)
	var d := sim.creatures[1]
	var x0 := d.pos.x
	run(sim, S2, 24)  # held through the charge
	var hit := run_until(sim, func(): return d.hp < d.max_hp, 60)
	assert_true(hit, "the wave reaches a foe 100 px away")
	assert_near(d.max_hp - d.hp, 9.0, 0.001, "and does real damage:")
	assert_gt(d.slow, 0, "it slows")
	assert_near(d.slow_mult, 0.6, 0.001, "to 60% walking speed:")
	assert_false(d.is_airborne(), "it pushes rather than pops up")
	run(sim, 0, 40)
	assert_gt(d.pos.x - x0, 18.0, "washed back, as before:")
	assert_eq(sim.terrain.count(TerrainGrid.HOLE), 0, "the wave never opens holes:")
	var far := _duel("culvert", "cairn", 125.0)
	run(far, S2, 24)
	run(far, 0, 60)
	assert_eq(far.creatures[1].hp, far.creatures[1].max_hp, "125 px away it misses")


func test_storm_drain_rings_culvert_with_pits() -> void:
	var sim := _duel("culvert", "cairn", 120.0)
	var c := sim.creatures[0]
	c.energy = 100.0
	tap(sim, SU, 60)
	assert_gt(sim.terrain.count(TerrainGrid.HOLE), 40, "pit ring:")
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


func test_only_the_last_hit_of_each_light_string_staggers() -> void:
	# Every fighter's light string: the hits before the last only deal damage; the last
	# staggers. Craglash is the exception: one Rake on a cooldown, no string (Oct 25 2026), and it staggers.
	# Chef Cerebro is the other: none of his thrown string staggers, the Mallet Toss included (Oct 25 2026).
	for id in MatchFactory.FIGHTERS:
		var moves: Dictionary = MatchFactory.load_def(id)["moves"]
		var chain: Array = []
		var mv := "light_1"
		while mv != "" and moves.has(mv):
			chain.append(mv)
			mv = String(moves[mv].get("next", ""))
		if id == "craglash":
			assert_eq(chain.size(), 1, "Craglash has a single light:")
			assert_false(bool(moves["light_1"].get("no_flinch", false)), "Craglash's Rake staggers")
			continue
		assert_gt(float(chain.size()), 1.0, id + " has a light string")
		for k in chain.size():
			var nf := bool(moves[chain[k]].get("no_flinch", false))
			var last := k == chain.size() - 1
			if id == "craglash":
				assert_false(nf, "Craglash's %s staggers" % chain[k])
			elif id == "cerebro":
				assert_true(nf, "Chef Cerebro's %s only deals damage" % chain[k])
			elif last:
				assert_false(nf, "%s's last light (%s) staggers" % [id, chain[k]])
			else:
				assert_true(nf, "%s's %s only deals damage" % [id, chain[k]])


## data/rules/energy.json: one jab charges the attacker by damage x per_damage_dealt x the
## light mult and the defender by damage x per_damage_taken (0.8 and 0.5 since the
## combo meter, Oct 2026).
func test_energy_rules_file_sets_the_rates() -> void:
	assert_near(MatchSim.energy_rate_dealt(), 0.8, 0.0001, "dealt rate:")
	assert_near(MatchSim.energy_rate_taken(), 0.5, 0.0001, "taken rate:")
	assert_true(MatchSim.energy_carries(), "the meter carries between rounds")
	var sim := _duel()
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	a.energy = 0.0
	d.energy = 0.0
	var hp0 := d.hp
	sim.step(PackedInt32Array([L, 0]))
	for i in 30:
		if d.hp < hp0:
			break
		sim.step(PackedInt32Array([0, 0]))
	var dmg := hp0 - d.hp
	assert_gt(dmg, 0.0, "the jab landed")
	assert_near(a.energy, dmg * 0.8 * _rule("light") * _var_energy(1), 0.001, "attacker gains damage x 0.8 x the light mult:")
	assert_near(d.energy, dmg * 0.5, 0.001, "defender gains damage x 0.5:")


## A hand-built move of two hit segments, both reaching the foe. `skip` sets skip_struck
## on the second one. Returns how many hits landed.
func _two_segment_hits(skip: bool) -> int:
	var sim := _duel()
	var a := sim.creatures[0]
	var seg2 := {"at": 10, "active": 2}
	if skip:
		seg2["skip_struck"] = true
	var mv := {"type": "skill", "startup": 4, "recovery": 12, "reach": 14, "hit_radius": 20,
		"damage": 3.0, "hitstun": 6, "knockback": 0.0, "hitstop": 0,
		"hits": [{"at": 5, "active": 2}, seg2]}
	CreatureSim._normalize_move("test_two", mv)
	a.moves()["test_two"] = mv
	a._start_attack("test_two", sim)
	var hits := 0
	for i in 30:
		sim.step(PackedInt32Array([0, 0]))
		for e in sim.events:
			if e["type"] == "hit":
				hits += 1
	return hits


func test_skip_struck_passes_over_a_foe_an_earlier_segment_hit() -> void:
	assert_eq(_two_segment_hits(false), 2, "both segments hit without the flag:")
	assert_eq(_two_segment_hits(true), 1, "the flagged segment skips the foe already struck:")


## --- The Surge meter fills from combos (data/rules/energy.json: per_type_mult, variety_energy)

## Runs `body` with MatchSim's energy rules swapped for `rules`, then puts the file's back.
func _with_energy_rules(rules: Dictionary, body: Callable) -> void:
	var saved := MatchSim.energy_rules()
	MatchSim._energy_rules = rules
	body.call()
	MatchSim._energy_rules = saved


## Lands `hits` ([type, move_id] pairs) one after another on the foe through _apply_hit
## (each 10 damage before the variety bonus). Returns [energy the attacker gained, damage dealt].
func _combo_energy(hits: Array) -> Array:
	var sim := _duel()
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	a.energy = 0.0
	a.stack = 0
	var hp0 := d.hp
	var serial := 1
	for h in hits:
		sim._apply_hit(a, d, _hit(String(h[0]), String(h[1]), serial), Vector2.RIGHT, d.pos)
		serial += 1
	return [a.energy, hp0 - d.hp]


func _rule(type: String) -> float:
	return float((MatchSim.energy_rules().get("per_type_mult", {}) as Dictionary).get(type, 1.0))


func _var_energy(n: int) -> float:
	return float(MatchSim.energy_rules()["variety_energy"][n])


func test_the_energy_file_sets_type_mults_and_a_variety_table() -> void:
	assert_lt(_rule("light"), 0.5, "lights charge the meter far less:")
	assert_near(_rule("heavy"), 1.0, 0.0001, "heavies in full:")
	assert_near(_rule("skill"), 1.0, 0.0001, "skills in full:")
	var t: Array = MatchSim.energy_rules().get("variety_energy", [])
	assert_eq(t.size(), 5, "a factor for 0..4 move types:")
	for i in range(1, t.size()):
		assert_true(float(t[i]) >= float(t[i - 1]), "more types never earn less (%d types):" % i)


func test_a_light_alone_charges_by_the_light_mult() -> void:
	var got := _combo_energy([["light", "light_1"]])
	assert_near(float(got[1]), 10.0, 0.001, "the jab dealt its damage:")
	assert_near(float(got[0]), 10.0 * MatchSim.energy_rate_dealt() * _rule("light") * _var_energy(1), 0.001,
		"energy = damage x per_damage_dealt x light mult x variety_energy[1]:")


func test_a_mixed_combo_charges_more_per_damage_than_lights_alone() -> void:
	var lights := _combo_energy([["light", "light_1"], ["light", "light_2"], ["light", "light_3"]])
	var mixed := _combo_energy([["light", "light_1"], ["heavy", "heavy"], ["skill", "skill_1"]])
	var per_l := float(lights[0]) / float(lights[1])
	var per_m := float(mixed[0]) / float(mixed[1])
	assert_gt(per_m, per_l * 2.0, "light > heavy > skill earns over twice the energy a damage of three lights (%.3f vs %.3f):" % [per_m, per_l])
	# Each hit counts the types the combo has used so far, itself included: the skill ender
	# (the third type) earns damage x rate x skill mult x variety_energy[3].
	var two := _combo_energy([["light", "light_1"], ["heavy", "heavy"]])
	assert_near(float(mixed[0]) - float(two[0]),
		(float(mixed[1]) - float(two[1])) * MatchSim.energy_rate_dealt() * _rule("skill") * _var_energy(3), 0.001,
		"the third type's hit earns at variety_energy[3]:")


func test_a_surge_still_charges_nothing() -> void:
	var got := _combo_energy([["light", "light_1"], ["surge", "surge"]])
	var only_light := _combo_energy([["light", "light_1"]])
	assert_near(float(got[0]), float(only_light[0]), 0.001, "the Surge hit added no energy:")
	assert_near(MatchSim.energy_dealt(_duel().creatures[1], "surge", 50.0), 0.0, 0.0001, "nor would any Surge damage:")


func test_a_blocked_hit_deals_and_charges_nothing() -> void:
	var sim := _duel()
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	d.facing = Vector2.LEFT
	d._set_state(CreatureSim.State.GUARD)
	a.energy = 0.0
	var hp0 := d.hp
	assert_eq(sim._apply_hit(a, d, _hit("light", "light_1", 1), Vector2.RIGHT, d.pos), "block", "blocked:")
	assert_near(d.hp, hp0, 0.001, "no chip:")
	assert_lt(d.stamina, d.max_stamina, "the guard paid in stamina")
	assert_near(a.energy, 0.0, 0.001, "and no meter from it:")


func test_without_the_new_keys_every_hit_charges_alike() -> void:
	_with_energy_rules({"per_damage_dealt": 0.75, "per_damage_taken": 0.5}, func():
		var l := _combo_energy([["light", "light_1"]])
		assert_near(float(l[0]), float(l[1]) * 0.75, 0.001, "a light: damage x 0.75, as before:")
		var m := _combo_energy([["light", "light_1"], ["heavy", "heavy"], ["skill", "skill_1"]])
		assert_near(float(m[0]), float(m[1]) * 0.75, 0.001, "a mixed combo: damage x 0.75, as before:")
		var s := _combo_energy([["surge", "surge"]])
		assert_near(float(s[0]), 0.0, 0.0001, "a Surge: nothing, as before:"))
