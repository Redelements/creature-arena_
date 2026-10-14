extends TestCase
## The class balance pass: the kit changes that came out of it (an armored Stomp, the
## stealth ambush, guard-breakers for the fighters that had none) and the matchups it
## targeted, measured with Rage CPUs on both sides (deterministic seeds, so these are
## exact, not flaky).

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const G := SimDefs.IN_GUARD
const RAGE := CpuController.RAGE


func _duel(left: String, right: String, gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


func _events(sim: MatchSim, kind: String) -> int:
	var n := 0
	for e in sim.events:
		if String(e["type"]) == kind:
			n += 1
	return n


## Rage vs Rage, both sides, `seeds` games a side: wins for `a`.
func _wins(a: String, b: String, seeds := 5) -> Array:
	var w := 0
	var n := 0
	for s in seeds:
		for side in 2:
			var sim := MatchFactory.versus(a, b) if side == 0 else MatchFactory.versus(b, a)
			var cpus := [CpuController.new(0, RAGE, 900 + s * 7 + side), CpuController.new(1, RAGE, 950 + s * 13 + side)]
			for t in 5400:
				sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
				if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
					break
			var me := sim.creatures[side]
			var foe := sim.creatures[1 - side]
			w += 1 if me.hp / me.max_hp > foe.hp / foe.max_hp else 0
			n += 1
	return [w, n]


# ------------------------------------------------------------------ kit changes

func test_rockslide_stomp_is_armored_once_its_windup_is_over() -> void:
	# Out of Bedrock (no windup) the Stomp can't be jabbed out of its startup: the jab
	# only chips it, and the Stomp lands.
	var sim := _duel("craglash", "cairn", 6.0)
	var crag := sim.creatures[0]
	var rel := int(crag.moves()["skill_2"]["armor"]["release_from"])
	tap(sim, S2, rel + 1)
	tap(sim, H, 1)
	assert_eq(crag.move_id, "heavy", "the Stomp answers out of Bedrock:")
	var armored := false
	var landed := false
	for t in 16:
		sim.step(PackedInt32Array([0, L if t == 1 else 0]))
		armored = armored or _events(sim, "armor") > 0
		for e in sim.events:
			if e["type"] == "hit" and int(e["attacker"]) == 0:
				landed = true
	assert_true(armored, "Cairn's jab only chips the armored Stomp")
	assert_eq(crag.move_id, "heavy", "and doesn't interrupt it:")
	assert_true(landed, "the Stomp lands")
	# Thrown raw, its windup is still open: a jab interrupts it.
	var sim2 := _duel("craglash", "cairn", 6.0)
	tap(sim2, H, 1)
	run(sim2, 0, 4, L)
	run(sim2, 0, 6)
	assert_eq(sim2.creatures[0].state, CreatureSim.State.HITSTUN, "a raw Stomp's tell can be jabbed:")


func test_a_strike_out_of_stealth_is_hidden_until_it_comes_out_and_hits_harder() -> void:
	var sim := _duel("pete", "cairn", 2.0)
	var pete := sim.creatures[0]
	var foe := sim.creatures[1]
	var base := float(pete.def["moves"]["light_1"]["damage"])
	pete.stealth = 100
	var hp := foe.hp
	tap(sim, L, 2)
	assert_gt(pete.stealth, 0, "still hidden through the jab's startup:")
	run_until(sim, func(): return foe.hp < hp, 20)
	assert_eq(pete.stealth, 0, "revealed as it lands:")
	assert_near(hp - foe.hp, base * float(pete.def["ambush"]), 0.05, "the sneak attack lands harder (x%.2f):" % float(pete.def["ambush"]))
	hp = foe.hp
	run(sim, 0, 30)
	tap(sim, L, 2)
	run_until(sim, func(): return foe.hp < hp, 20)
	assert_near(hp - foe.hp, base, 0.05, "the next jab is an ordinary one:")


func test_a_knife_flick_doesnt_blow_petes_cover_but_a_mallet_does() -> void:
	var sim := _duel("cerebro", "pete", 60.0)
	var pete := sim.creatures[1]
	pete.stealth = 300
	pete.facing = Vector2.LEFT
	tap(sim, L, 30)  # a flick flies and hits
	assert_lt(pete.hp, pete.max_hp, "the flick hit")
	assert_gt(pete.stealth, 0, "but he stays hidden")
	tap(sim, L, 2)
	tap(sim, L, 2)
	run(sim, 0, 20)
	tap(sim, L, 40)  # the third throw is the Mallet, which staggers
	assert_eq(pete.stealth, 0, "a staggering hit gives him away:")


func test_pickpocket_homes_in_and_runs_on_through() -> void:
	var sim := _duel("pete", "cairn", 30.0)
	var pete := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.pos.y += 20  # off the line Pete faces
	var x0 := foe.pos.x
	var stole := false
	tap(sim, S2, 1)
	for t in 40:
		sim.step(PackedInt32Array([0, 0]))
		stole = stole or _events(sim, "steal") > 0
	assert_true(stole, "the dash steers onto a foe standing off-line")
	assert_gt(pete.pos.x, x0, "and runs on past him")


func test_every_fighter_has_a_guard_answer() -> void:
	# A grab or a guard-breaker, so a turtle can always be opened; the pass gave one to
	# the fighters that had none. Three stay without on purpose: Gillbert's hook and
	# Barkley's Branch Grab are meant to be blockable, and Cairn opens people with his
	# Slip counter.
	for id in MatchFactory.FIGHTERS:
		if id in ["gillbert", "cairn", "barkley"]:
			continue
		var moves: Dictionary = MatchFactory.load_def(id)["moves"]
		var has := false
		for mid in moves:
			var mv: Dictionary = moves[mid]
			if bool(mv.get("grab", false)) or bool(mv.get("guard_break", false)):
				has = true
		assert_true(has, id + " can open a guard")


func test_the_new_guard_breakers_break_guards() -> void:
	for pair in [["hissy", H, 4.0], ["pete", H, 4.0], ["sno", S2, 30.0]]:
		var sim := _duel(String(pair[0]), "cairn", float(pair[2]))
		var broke := false
		for t in 60:
			sim.step(PackedInt32Array([int(pair[1]) if t == 0 else 0, G]))
			broke = broke or _events(sim, "guard_break") > 0
		assert_true(broke, "%s breaks a guard" % pair[0])


# ------------------------------------------------------------------ matchups (Rage vs Rage)

func test_assassins_beat_the_mage() -> void:
	var d := _wins("digby", "cerebro")
	var p := _wins("pete", "cerebro")
	assert_gt(float(d[0]), d[1] * 0.5, "Digby beats Chef Cerebro (%d of %d):" % d)
	assert_gt(float(p[0]), p[1] * 0.4, "Sneaky Pete holds his own against Chef Cerebro (%d of %d):" % p)


func test_the_mage_beats_fighters_and_tanks() -> void:
	for foe in ["cairn", "hissy", "craglash", "culvert"]:
		var r := _wins("cerebro", foe, 4)
		assert_gt(float(r[0]), r[1] * 0.5, "Chef Cerebro beats %s (%d of %d):" % [foe, r[0], r[1]])


func test_fighters_beat_assassins() -> void:
	for pair in [["cairn", "digby"], ["cairn", "pete"], ["hissy", "digby"], ["hissy", "pete"]]:
		var r := _wins(String(pair[0]), String(pair[1]), 4)
		assert_gt(float(r[0]), r[1] * 0.5, "%s beats %s (%d of %d):" % [pair[0], pair[1], r[0], r[1]])


func test_class_mirrors_are_close() -> void:
	# Tank, assassin and fighter mirrors land between 30% and 70% over 10 games.
	for pair in [["craglash", "culvert"], ["digby", "pete"], ["hissy", "cairn"]]:
		var r := _wins(String(pair[0]), String(pair[1]), 5)
		var share := float(r[0]) / float(r[1])
		assert_true(share >= 0.3 and share <= 0.7, "%s vs %s is close (%d of %d)" % [pair[0], pair[1], r[0], r[1]])
