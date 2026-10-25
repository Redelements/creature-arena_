extends TestCase
## Playtest tuning: a blocked third light can be punished, Surges don't charge the next
## Surge, Gillbert's The One That Got Away homes in on the foe, and Chef Cerebro's Knife
## Flurry aims at the foe instead of only along the 8 directions.

const L := SimDefs.IN_LIGHT
const S1 := SimDefs.IN_SKILL1
const SU := SimDefs.IN_SURGE
const GUARD := SimDefs.IN_GUARD


func _duel(left: String, right: String, gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.creatures[0].pos = Vector2(200, 164)
	sim.creatures[1].pos = Vector2(200 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


## Attacker 0 mashes its lights into Cairn's guard until its third light is blocked.
## Returns the tick the block happened, or -1.
func _block_third_light(sim: MatchSim) -> int:
	var a := sim.creatures[0]
	for i in 160:
		sim.step(PackedInt32Array([L if i % 2 == 0 and a.move_id != "light_3" else 0, GUARD]))
		for e in sim.events:
			if String(e["type"]) == "block" and a.move_id == "light_3":
				return i
	return -1


func test_a_blocked_third_light_leaves_every_fighter_open() -> void:
	for id in MatchFactory.FIGHTERS:
		if not MatchFactory.load_def(id)["moves"].has("light_3"):
			continue  # Craglash: a single Rake on a 2 s cooldown, no string to block
		var gap := 2.0
		var lt: Dictionary = MatchFactory.load_def(id)["moves"]["light_3"]
		if lt.has("projectile"):
			gap = 30.0  # a thrown light: block it from a little way off
		var sim := _duel(id, "cairn", gap)
		var a := sim.creatures[0]
		var d := sim.creatures[1]
		if _block_third_light(sim) < 0:
			fail("%s: the third light was never blocked" % id)
			continue
		var t := 0
		var d_free := -1
		var a_free := -1
		while t < 200 and (d_free < 0 or a_free < 0):
			sim.step(PackedInt32Array([0, GUARD]))
			t += 1
			if d_free < 0 and d.state == CreatureSim.State.GUARD and d.stun <= 0:
				d_free = t
			if a_free < 0 and a.state != CreatureSim.State.ATTACK:
				a_free = t
		assert_true(a_free - d_free >= MatchSim.BLOCKED_ENDER_DISADVANTAGE - 1,
			"%s: blocked third light leaves him %d ticks behind (want %d)" % [id, a_free - d_free,
				MatchSim.BLOCKED_ENDER_DISADVANTAGE])


func test_a_blocked_third_light_can_be_punished_with_a_jab() -> void:
	var sim := _duel("cairn", "cairn")
	assert_true(_block_third_light(sim) >= 0, "Cairn's Cross is blocked")
	var punished := false
	for i in 40:
		var p1 := GUARD if sim.creatures[1].stun > 0 else (L if i % 2 == 0 else 0)
		sim.step(PackedInt32Array([0, p1]))
		for e in sim.events:
			if String(e["type"]) == "hit" and int(e["attacker"]) == 1:
				punished = true
	assert_true(punished, "the blocker's jab lands before the attacker recovers")


func test_a_blocked_third_light_cant_be_cancelled_into_a_skill() -> void:
	var sim := _duel("cairn", "cairn")
	var a := sim.creatures[0]
	assert_true(_block_third_light(sim) >= 0, "blocked")
	run(sim, S1, 1, GUARD)
	run(sim, 0, 4, GUARD)
	assert_eq(a.move_id, "light_3", "no Skill out of a blocked third light:")


func test_a_hit_third_light_still_cancels() -> void:
	var sim := _duel("cairn", "culvert")
	var a := sim.creatures[0]
	var started := false
	for i in 80:
		var bit := L if a.move_id != "light_3" else S1
		sim.step(PackedInt32Array([bit if i % 2 == 0 else 0, 0]))
		if a.move_id == "skill_1":
			started = true
			break
	assert_true(started, "on hit, the third light still cancels into a Skill")


func test_surge_hits_dont_charge_the_next_surge() -> void:
	for id in ["cairn", "cerebro", "gillbert", "hissy"]:
		var sim := _duel(id, "culvert", 4.0)
		var a := sim.creatures[0]
		a.energy = 100.0
		var hits := 0
		for i in 160:
			sim.step(PackedInt32Array([SU if i < 3 else 0, 0]))
			for e in sim.events:
				if String(e["type"]) == "hit" and int(e["attacker"]) == 0:
					hits += 1
		assert_gt(float(hits), 0.0, "%s's Surge lands" % id)
		assert_near(a.energy, 0.0, 0.001, "%s: no energy from its own Surge's hits:" % id)


func test_gillbert_surge_homes_in_on_a_foe_off_to_the_side() -> void:
	var sim := _duel("gillbert", "cairn", 50.0)
	var g := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.pos += Vector2(10, 34)  # not where he's facing, and further than he'd go
	g.energy = 100.0
	var landed := false
	for i in 90:
		sim.step(PackedInt32Array([SU if i < 3 else 0, 0]))
		for e in sim.events:
			if String(e["type"]) == "hit" and int(e["attacker"]) == 0:
				landed = true
	assert_true(landed, "the belly-flop finds Cairn")


func test_gillbert_surge_can_still_be_dodged() -> void:
	var sim := _duel("gillbert", "cairn", 40.0)
	var g := sim.creatures[0]
	var foe := sim.creatures[1]
	g.energy = 100.0
	var landed := false
	var dodged := false
	for i in 120:
		var p1 := 0
		# A dodge timed for the landing: its invulnerable frames cover the belly-flop.
		if not dodged and g.move_id == "surge" and g.state_t == int(g.def["moves"]["surge"]["startup"]) - 2:
			p1 = SimDefs.IN_DODGE | SimDefs.IN_DOWN
			dodged = true
		sim.step(PackedInt32Array([SU if i < 3 else 0, p1]))
		for e in sim.events:
			if String(e["type"]) == "hit" and int(e["attacker"]) == 0:
				landed = true
	assert_true(dodged, "Cairn dodged")
	assert_false(landed, "a dodge on the landing still beats it")
	assert_near(foe.hp, foe.max_hp, 0.001, "")


func test_cerebro_flurry_aims_at_a_foe_off_the_8_directions() -> void:
	var sim := _duel("cerebro", "cairn", 60.0)
	var c := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.pos += Vector2(0, 32)  # about 23 degrees below his line: between two directions
	c.energy = 100.0
	var hits := 0
	for i in 90:
		sim.step(PackedInt32Array([SU if i < 3 else 0, 0]))
		for e in sim.events:
			if String(e["type"]) == "hit" and int(e["attacker"]) == 0:
				hits += 1
	assert_gt(float(hits), 5.0, "the knives fly at Cairn, not along the row:")


func test_cerebro_flurry_doesnt_aim_behind_him() -> void:
	var sim := _duel("cerebro", "cairn", 60.0)
	var c := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.pos = c.pos + Vector2(-90, 10)  # behind him
	c.energy = 100.0
	run(sim, SU, 3)
	run(sim, 0, 60)
	assert_true(foe.hp == foe.max_hp, "a foe behind him isn't tracked")
