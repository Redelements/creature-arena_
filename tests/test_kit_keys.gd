extends TestCase
## Kit-pass data keys any fighter can use: "stagger_if" (a no_flinch hit that staggers a
## target carrying a mark: Chef Cerebro's Mallet Toss on a tenderized foe), a projectile's
## "bounce" (on to a second foe once, weaker: Cleaver Toss) and a light's "branches" (a
## button pressed at that point of the string starts another move in place of the usual
## rank cancel). Keys in docs/MECHANICS.md.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1


func _duel(left := "cairn", right := "culvert", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


func _hit(extra := {}) -> Dictionary:
	var h := {
		"attacker": 0, "move_id": "light_3", "type": "light", "serial": 1,
		"damage": 5.0, "knockback": 0.0, "hitstun": 20.0, "hitstop": 0.0,
		"launch": 0.0, "crumple": 0.0, "knockdown": 0.0,
		"guard_break": false, "grab": false, "juggle": false, "stack_bonus": 0.0,
		"no_flinch": true, "stagger_if": "tenderized",
	}
	h.merge(extra, true)
	return h


func _count(sim: MatchSim, kind: String, key := "", value = null) -> int:
	var n := 0
	for e in sim.events:
		if String(e["type"]) == kind and (key == "" or e.get(key) == value):
			n += 1
	return n


# ------------------------------------------------------------------ stagger_if

func test_a_stagger_if_hit_doesnt_stagger_a_foe_without_the_mark() -> void:
	var sim := _duel()
	var d := sim.creatures[1]
	sim._apply_hit(sim.creatures[0], d, _hit(), Vector2.RIGHT, d.pos)
	assert_false(d.is_stunned(), "not tenderized: damage only, like any no_flinch hit")
	assert_eq(d.combo_hits, 0, "and no combo starts on a free foe:")


func test_a_stagger_if_hit_staggers_a_marked_foe_and_starts_a_combo() -> void:
	var sim := _duel()
	var d := sim.creatures[1]
	d.vuln = 120
	d.vuln_mult = 1.2
	sim._apply_hit(sim.creatures[0], d, _hit(), Vector2.RIGHT, d.pos)
	assert_eq(d.state, CreatureSim.State.HITSTUN, "tenderized: the hit staggers")
	assert_eq(d.stun, 20, "for its own hitstun:")
	assert_eq(d.combo_hits, 1, "and starts a combo:")
	var paid := false
	for e in sim.events:
		if String(e["type"]) == "hit":
			paid = bool(e.get("stagger_if", false))
	assert_true(paid, "the hit event says the setup paid off (the view's STAGGERED!)")
	sim._apply_hit(sim.creatures[0], d, _hit({"no_flinch": false, "stagger_if": "", "type": "skill",
		"move_id": "skill_1", "serial": 2}), Vector2.RIGHT, d.pos)
	assert_eq(d.combo_hits, 2, "the next hit continues it:")


func test_marks_a_hit_can_name() -> void:
	var sim := _duel()
	var d := sim.creatures[1]
	for mark in ["tenderized", "poisoned", "bleeding", "slowed", "rooted", "blinded", "nonsense", ""]:
		assert_false(d.has_mark(mark), "a fresh fighter isn't %s" % mark)
	d.vuln = 5
	d.poison = 5
	d.slow = 5
	d.root = 5
	d.blind = 5
	for mark in ["tenderized", "poisoned", "slowed", "rooted", "blinded"]:
		assert_true(d.has_mark(mark), "marked: %s" % mark)
	assert_false(d.has_mark("bleeding"), "venom isn't bleeding")
	d.poison_look = "bleed"
	assert_true(d.has_mark("bleeding"), "a bleed is")


## The whole setup with real inputs: Tenderize, then Flick, Flick, Mallet. The Mallet
## staggers the tenderized foe, and a Cleaver Toss cancelled out of it is the same combo.
func test_cerebro_tenderize_then_the_mallet_staggers() -> void:
	var sim := _duel("cerebro", "cairn", 4.0)
	var chef := sim.creatures[0]
	var foe := sim.creatures[1]
	run_until(sim, func(): return foe.vuln > 0, 60, H)
	assert_gt(foe.vuln, 0, "Tenderize lands")
	run_until(sim, func(): return chef.state == CreatureSim.State.IDLE and not foe.is_stunned() \
		and foe.state != CreatureSim.State.KNOCKDOWN and foe.invuln <= 0, 200)
	foe.pos = chef.pos + Vector2(70, 0)  # stood up: knives from range
	chef.facing = Vector2.RIGHT
	assert_gt(foe.vuln, 0, "still tenderized")
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S1, "skill_1"]])
	assert_eq(errors.size(), 0, "every step comes out")
	assert_gt(dmg, 5.0 + 8.0, "damage dealt:")
	# The cleaver landed as hit 2 of a combo (the mallet staggered).
	var sim2 := _duel("cerebro", "cairn", 70.0)
	sim2.creatures[1].vuln = 200
	sim2.creatures[1].vuln_mult = 1.2
	var best := 0
	var stunned_by_mallet := false
	var steps := [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S1, "skill_1"]]
	for s in steps:
		var serial := sim2.creatures[0].attack_serial
		for i in 120:
			sim2.step(PackedInt32Array([int(s[0]) if i % 2 == 0 else 0, 0]))
			for e in sim2.events:
				if String(e["type"]) == "hit":
					best = maxi(best, int(e["combo"]))
					if bool(e.get("stagger_if", false)):
						stunned_by_mallet = sim2.creatures[1].is_stunned()
			if sim2.creatures[0].attack_serial != serial and sim2.creatures[0].move_id == String(s[1]):
				break
	for i in 60:
		sim2.step(PackedInt32Array([0, 0]))
		for e in sim2.events:
			if String(e["type"]) == "hit":
				best = maxi(best, int(e["combo"]))
	assert_true(stunned_by_mallet, "the mallet staggers the tenderized foe")
	assert_eq(best, 2, "and the cleaver is the second hit of that combo:")


# ------------------------------------------------------------------ bounce

## Cerebro, Cairn in front, and Culvert `gap2` px beyond Cairn.
func _bounce_sim(gap2: float) -> MatchSim:
	var sim := _duel("cerebro", "cairn", 30.0)
	var second := sim.add_creature(MatchFactory.load_def("culvert"), sim.creatures[1].pos + Vector2(0, gap2))
	second.facing = Vector2.LEFT
	return sim


func _throw_cleaver(sim: MatchSim) -> Array:
	var hits := [0, 0, 0]
	var dmg := [0.0, 0.0, 0.0]
	var bounces := 0
	sim.step(PackedInt32Array([S1, 0, 0]))
	for i in 90:
		sim.step(PackedInt32Array([0, 0, 0]))
		bounces += _count(sim, "projectile_bounce")
		for e in sim.events:
			if String(e["type"]) == "hit" and int(e["attacker"]) == 0:
				hits[int(e["target"])] += 1
				dmg[int(e["target"])] += float(e["dealt"])
	return [hits, dmg, bounces]


func test_the_cleaver_bounces_to_a_second_foe_once_weaker() -> void:
	var sim := _bounce_sim(50.0)
	var mv: Dictionary = sim.creatures[0].def["moves"]["skill_1"]
	var b: Dictionary = mv["projectile"]["bounce"]
	var r := _throw_cleaver(sim)
	assert_eq(r[0][1], 1, "the first foe is hit once:")
	assert_eq(r[0][2], 1, "the second foe once, on the bounce:")
	assert_eq(r[2], 1, "one bounce event:")
	assert_near(r[1][1], float(mv["damage"]), 0.01, "the first takes the full cleaver:")
	assert_near(r[1][2], float(mv["damage"]) * float(b["damage_mult"]), 0.01, "the second x damage_mult:")


func test_the_cleaver_doesnt_bounce_past_its_range() -> void:
	var sim := _bounce_sim(0.0)
	var b: Dictionary = sim.creatures[0].def["moves"]["skill_1"]["projectile"]["bounce"]
	sim.creatures[2].pos = sim.creatures[1].pos + Vector2(0, float(b["range"]) + sim.creatures[2].radius + 20.0)
	var r := _throw_cleaver(sim)
	assert_eq(r[0][1], 1, "the first foe is hit:")
	assert_eq(r[0][2], 0, "one out of range isn't:")
	assert_eq(r[2], 0, "no bounce:")


func test_the_cleaver_ends_on_its_hit_with_nobody_to_bounce_to() -> void:
	var sim := _duel("cerebro", "cairn", 30.0)
	var ended := false
	sim.step(PackedInt32Array([S1, 0]))
	for i in 60:
		sim.step(PackedInt32Array([0, 0]))
		ended = ended or _count(sim, "projectile_end", "who", 0) > 0
		assert_eq(_count(sim, "projectile_bounce"), 0, "no bounce in a 1v1")
	assert_true(ended, "the cleaver ends on its hit")
	assert_eq(sim.projectiles.size(), 0, "and is gone:")


func test_a_bounce_skips_teammates() -> void:
	var t := TeamSim.new([["cerebro", "pete"], ["cairn", "culvert"]], 2)
	var sim := t.sim  # stepped directly: no intro
	var chef := sim.creatures[0]
	var mate := sim.creatures[1]
	var foe := sim.creatures[2]
	chef.pos = Vector2(220, 164)
	chef.facing = Vector2.RIGHT
	foe.pos = chef.pos + Vector2(chef.radius + foe.radius + 30.0, 0)
	mate.pos = foe.pos + Vector2(0, 40)
	sim.creatures[3].pos = Vector2(600, 260)  # the other foe, far out of range
	var bounced := 0
	sim.step(PackedInt32Array([S1, 0, 0, 0]))
	for i in 60:
		sim.step(PackedInt32Array([0, 0, 0, 0]))
		bounced += _count(sim, "projectile_bounce")
	assert_lt(foe.hp, foe.max_hp, "the cleaver hits the foe")
	assert_eq(bounced, 0, "and never turns on a teammate:")
	assert_eq(mate.hp, mate.max_hp, "untouched:")


func test_rollback_with_a_bounce_in_flight() -> void:
	var sim := _bounce_sim(60.0)
	sim.step(PackedInt32Array([S1, 0, 0]))
	run_until(sim, func(): return _count(sim, "projectile_bounce") > 0, 60)
	var snap := sim.snapshot()
	for i in 30:
		sim.step(PackedInt32Array([0, 0, 0]))
	var once := sim.state_digest()
	sim.restore(snap)
	for i in 30:
		sim.step(PackedInt32Array([0, 0, 0]))
	assert_eq(sim.state_digest(), once, "replaying from mid-bounce gives the same state:")


# ------------------------------------------------------------------ branches

## Cairn with a branch on his second light: Heavy there starts "heavy_alt" (a copy of his
## heavy) instead of the heavy.
func _branch_sim() -> MatchSim:
	var def: Dictionary = MatchFactory.load_def("cairn").duplicate(true)
	var alt: Dictionary = (def["moves"]["heavy"] as Dictionary).duplicate(true)
	alt["name"] = "Branch"
	alt.erase("windup")
	def["moves"]["heavy_alt"] = alt
	def["moves"]["light_2"]["branches"] = {"heavy": "heavy_alt"}
	var sim := MatchSim.new()
	sim.set_arena(MatchFactory.arena)
	sim.add_creature(def, Vector2(220, 164))
	var foe := sim.add_creature(MatchFactory.load_def("culvert"), Vector2.ZERO)
	foe.pos = Vector2(220 + sim.creatures[0].radius + foe.radius + 2.0, 164)
	foe.facing = Vector2.LEFT
	return sim


func test_heavy_at_the_branch_starts_the_branch_move() -> void:
	var sim := _branch_sim()
	route(sim, 0, [[L, "light_1"], [L, "light_2"], [H, "heavy_alt"]])
	assert_eq(errors.size(), 0, "light, light, Heavy: the branch move")


func test_heavy_elsewhere_in_the_string_is_the_usual_rank_cancel() -> void:
	var sim := _branch_sim()
	route(sim, 0, [[L, "light_1"], [H, "heavy"]])
	assert_eq(errors.size(), 0, "light, Heavy: the heavy as always")


func test_a_branch_on_cooldown_falls_back_to_the_usual_cancel() -> void:
	var sim := _branch_sim()
	sim.creatures[0].def["moves"]["heavy_alt"]["cooldown"] = 600
	sim.creatures[0].cooldowns["heavy_alt"] = 600
	route(sim, 0, [[L, "light_1"], [L, "light_2"], [H, "heavy"]])
	assert_eq(errors.size(), 0, "the branch is cooling: the heavy instead")


func test_a_branch_needs_contact_like_any_rank_cancel() -> void:
	var sim := _branch_sim()
	var a := sim.creatures[0]
	sim.creatures[1].pos.x += 200.0  # out of reach: the string whiffs
	run(sim, L, 1)
	run(sim, 0, 12)
	run(sim, L, 1)
	for i in 30:
		run(sim, H if i % 2 == 0 else 0, 1)
		assert_true(a.move_id != "heavy_alt" or a.state != CreatureSim.State.ATTACK, "no branch out of a whiff")
