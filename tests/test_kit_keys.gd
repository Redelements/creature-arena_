extends TestCase
## Kit-pass data keys any fighter can use: "stagger_if" (a no_flinch hit that staggers a
## target carrying a mark: Chef Cerebro's Mallet Toss on a tenderized foe), a projectile's
## "bounce" (on to a second foe once, weaker: Cleaver Toss) and a light's "branches" (a
## button pressed at that point of the string starts another move in place of the usual
## rank cancel), and "lock_on" on a "dash.home" or a "blink" (an aimed dive: Sneaky Pete goes
## for the foe he aims at, else the nearest). Keys in docs/MECHANICS.md.

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


# ------------------------------------------------------------------ lock_on on dash.home and blink
# Sneaky Pete's aimed dives: Pickpocket's homing dash and The Big Heist's blink go for the
# foe the held aim points at (within the cone), else the nearest as before.

const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE


## The attacker on team 0 at (200, 164); Culvert (team 1) right in front of it, the nearest
## foe; Cerebro (team 1) further off, up and to the right at 45 degrees.
func _dive_sim(attacker = "pete") -> MatchSim:
	var def: Dictionary = MatchFactory.load_def(attacker) if attacker is String else attacker
	var sim := MatchSim.new()
	sim.set_arena(MatchFactory.arena)
	var a := sim.add_creature(def, Vector2(200, 164))
	a.team = 0
	var tank := sim.add_creature(MatchFactory.load_def("culvert"), Vector2.ZERO)
	tank.pos = Vector2(200 + a.radius + tank.radius + 4.0, 164)
	tank.facing = Vector2.LEFT
	tank.team = 1
	var mage := sim.add_creature(MatchFactory.load_def("cerebro"), Vector2(250, 114))
	mage.facing = Vector2.LEFT
	mage.team = 1
	return sim


## Presses `button` with the aim held toward `aim` (zero: no aim, no stick) for the first
## 4 ticks, then holds only the aim, for `ticks`. Returns who the attacker hit, the
## first blink's landing spot and where the move ended (a Surge on a crowded field winds
## up first, so give those time).
func _dive(sim: MatchSim, button: int, aim: Vector2, ticks: int) -> Dictionary:
	var aim_b := SimDefs.aim_bits(aim)
	var hit := {}
	var landed := Vector2.INF
	var ended := Vector2.INF
	var a := sim.creatures[0]
	var started := false
	var gaps := {1: INF, 2: INF}
	for i in ticks:
		sim.step(PackedInt32Array([(button if i < 4 else 0) | aim_b, 0, 0]))
		if a.state == CreatureSim.State.ATTACK:
			started = true
		elif started and ended == Vector2.INF:
			ended = a.pos
		for e in sim.events:
			if String(e["type"]) == "hit" and int(e.get("attacker", -1)) == 0:
				hit[int(e["target"])] = true
			elif String(e["type"]) == "blink" and landed == Vector2.INF:
				landed = e["pos"]
				for j in [1, 2]:  # how far the landing is from each foe, as they stand then
					gaps[j] = landed.distance_to(sim.creatures[j].pos) - float(sim.creatures[j].radius + a.radius)
	return {"hit": hit, "landed": landed, "ended": ended, "gaps": gaps}


func test_lock_on_pickpocket_dives_past_the_tank_onto_the_aimed_mage() -> void:
	var sim := _dive_sim()
	var pete := sim.creatures[0]
	var r := _dive(sim, S2, sim.creatures[2].pos - pete.pos, 70)
	assert_true(r["hit"].has(2), "Pickpocket homes onto Cerebro, the one he aims at")
	assert_lt(r["ended"].distance_to(sim.creatures[2].pos), r["ended"].distance_to(sim.creatures[1].pos),
		"and runs on past Culvert")


func test_lock_on_big_heist_blinks_to_the_aimed_mage() -> void:
	var sim := _dive_sim()
	var pete := sim.creatures[0]
	pete.energy = 100.0
	var r := _dive(sim, SU, sim.creatures[2].pos - pete.pos, 90)
	assert_true(r["landed"] != Vector2.INF, "he blinks")
	assert_lt(r["gaps"][2], 4.0, "beside Cerebro")


func test_lock_on_with_no_foe_in_the_cone_takes_the_nearest() -> void:
	for aim in [Vector2.DOWN, Vector2.ZERO]:
		var sim := _dive_sim()
		var r := _dive(sim, S2, aim, 70)
		assert_true(r["hit"].has(1), "aimed at nobody (%s): Pickpocket takes Culvert, the nearest" % aim)
		assert_false(r["hit"].has(2), "not Cerebro (%s)" % aim)
		sim = _dive_sim()
		sim.creatures[0].energy = 100.0
		r = _dive(sim, SU, aim, 90)
		assert_lt(r["gaps"][1], 4.0, "and The Big Heist blinks to Culvert (%s)" % aim)


func test_lock_on_skips_a_stealthed_foe_in_the_cone() -> void:
	var sim := _dive_sim()
	var pete := sim.creatures[0]
	sim.creatures[2].stealth = 600
	assert_eq(sim.aimed_opponent(pete, (sim.creatures[2].pos - pete.pos).normalized(), 0.92), null,
		"hidden Cerebro doesn't count")
	var r := _dive(sim, S2, sim.creatures[2].pos - pete.pos, 70)
	assert_true(r["hit"].has(1), "Pickpocket falls back to the nearest, Culvert")
	assert_false(r["hit"].has(2), "not the hidden Cerebro")
	sim = _dive_sim()
	sim.creatures[2].stealth = 600
	sim.creatures[0].energy = 100.0
	r = _dive(sim, SU, sim.creatures[2].pos - sim.creatures[0].pos, 90)
	assert_lt(r["gaps"][1], 4.0, "and The Big Heist blinks to Culvert")


func test_lock_on_picks_the_foe_closest_to_the_aim_line() -> void:
	var sim := _dive_sim()
	var pete := sim.creatures[0]
	# Both in a wide cone: the one nearer the aim line wins, not the nearer one.
	var aim := (sim.creatures[2].pos - pete.pos).normalized()
	assert_eq(sim.aimed_opponent(pete, aim, 0.5), sim.creatures[2], "Cerebro is on the aim line")
	assert_eq(sim.aimed_opponent(pete, Vector2.RIGHT, 0.5), sim.creatures[1], "Culvert is on this one")


func test_a_homing_dash_without_lock_on_still_takes_the_nearest() -> void:
	var sim := _dive_sim("gillbert")
	var g := sim.creatures[0]
	assert_false((g.def["moves"]["surge"]["dash"]["home"] as Dictionary).has("lock_on"), "Gillbert's has none")
	g.energy = 100.0
	var r := _dive(sim, SU, sim.creatures[2].pos - g.pos, 120)
	assert_true(r["hit"].has(1), "The One That Got Away lands on Culvert, the nearest, aim or not")
	assert_lt(r["ended"].distance_to(sim.creatures[1].pos), r["ended"].distance_to(sim.creatures[2].pos),
		"its landing is by Culvert")


func test_lock_on_works_on_any_homing_dash() -> void:
	var def: Dictionary = MatchFactory.load_def("gillbert").duplicate(true)
	def["moves"]["surge"]["dash"]["home"]["lock_on"] = {"dot": 0.92}
	var sim := _dive_sim(def)
	var g := sim.creatures[0]
	g.energy = 100.0
	var r := _dive(sim, SU, sim.creatures[2].pos - g.pos, 120)
	assert_lt(r["ended"].distance_to(sim.creatures[2].pos), r["ended"].distance_to(sim.creatures[1].pos),
		"with the key, Gillbert's dash steers for the aimed foe instead")
