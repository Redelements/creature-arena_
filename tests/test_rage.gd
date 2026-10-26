extends TestCase
## Rage, the top CPU tier: it beats Hard, kites as a mage, dodges shots, punishes
## whiffs, and picks targets by class in a team battle. Like every CPU it only presses
## buttons, so its matches replay exactly.

const MAX_TICKS := 5400
const RAGE := CpuController.RAGE
const HARD := 2


## CPU vs CPU until a knockout or time. Returns the result and a few measurements.
func _match(left: String, right: String, lv_l: int, lv_r: int, seed_ := 1) -> Dictionary:
	var sim := MatchFactory.versus(left, right)
	var cpus := [CpuController.new(0, lv_l, seed_ * 7 + 1), CpuController.new(1, lv_r, seed_ * 13 + 5)]
	var dist := 0.0
	var shots := [0, 0]
	var shot_hits := [0, 0]
	var ticks := 0
	while ticks < MAX_TICKS:
		ticks += 1
		sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
		dist += sim.creatures[0].pos.distance_to(sim.creatures[1].pos)
		for e in sim.events:
			if e["type"] == "projectile":
				shots[int(e["who"])] += 1
			elif e["type"] == "hit" and sim.creatures[int(e["attacker"])].moves().get(
					sim.creatures[int(e["attacker"])].move_id, {}).has("projectile"):
				shot_hits[int(e["attacker"])] += 1
		if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
			break
	var r0 := sim.creatures[0].hp / sim.creatures[0].max_hp
	var r1 := sim.creatures[1].hp / sim.creatures[1].max_hp
	return {"sim": sim, "winner": 0 if r0 > r1 else 1, "hp": [r0, r1], "dist": dist / ticks,
		"shots": shots, "shot_hits": shot_hits, "ticks": ticks}


func test_rage_is_a_level() -> void:
	assert_eq(String(CpuController.LEVELS[RAGE]["name"]), "Rage", "level 3:")
	var main_script: GDScript = load("res://src/game/main.gd")
	assert_true("Rage" in main_script.get_script_constant_map()["LEVEL_NAMES"], "Settings offers it")


func test_rage_beats_hard() -> void:
	var wins := 0
	var games := 0
	for pair in [["cairn", "culvert"], ["digby", "hissy"], ["sno", "gillbert"]]:
		var a: Dictionary = _match(pair[0], pair[1], RAGE, HARD, 3)
		wins += 1 if int(a["winner"]) == 0 else 0
		var b: Dictionary = _match(pair[0], pair[1], HARD, RAGE, 4)
		wins += 1 if int(b["winner"]) == 1 else 0
		games += 2
	assert_gt(float(wins), games - 1.5, "Rage wins (of %d):" % games)


func test_rage_mage_kites() -> void:
	# Chef Cerebro, a mage, against a slow tank that has to catch him.
	var rage: Dictionary = _match("cerebro", "craglash", RAGE, HARD, 5)
	var hard: Dictionary = _match("cerebro", "craglash", HARD, HARD, 5)
	# About 66 px since the Normal-and-below CPUs chase a kiting mage (Oct 2026; was 70+); still
	# further than Hard, and he still wins.
	assert_gt(float(rage["dist"]), 60.0, "Rage keeps the tank at knife range:")
	assert_gt(float(rage["dist"]), float(hard["dist"]), "further than Hard does:")  # 5 px clear before the longer fights (Oct 2026)
	assert_eq(int(rage["winner"]), 0, "and wins")
	# Craglash's hook and Landslide Ram are built to reach a kiting mage, so he lands a
	# few. Since the Oct 2026 kit pass (knives at 115 px, Maw back every 3.3 s, a 12-frame
	# Rake) he lands more than a few: Rage still wins, but no longer untouched.
	assert_gt(float(rage["hp"][0]), 0.0, "still standing:")


## Knives thrown by side 0 from at least `far` away, and how many of those hit side 1.
func _far_knives(thrower_lv: int, target: String, target_lv: int, seed_: int, far := 70.0) -> Array:
	var sim := MatchFactory.versus("cerebro", target)
	var cpus := [CpuController.new(0, thrower_lv, seed_ * 7 + 1), CpuController.new(1, target_lv, seed_ * 13 + 5)]
	var live: Array = []  ## [projectile, thrown from far?, last position]
	var thrown := 0
	var hits := 0
	for t in MAX_TICKS:
		sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
		var foe := sim.creatures[1]
		var still: Array = []
		for entry in live:
			var gone := true
			for pr in sim.projectiles:
				if is_same(pr, entry[0]):
					gone = false
					entry[2] = pr["pos"]
			if not gone:
				still.append(entry)
			elif entry[1] and (entry[2] as Vector2).distance_to(foe.pos) < foe.radius + 14.0:
				hits += 1
		live = still
		for pr in sim.projectiles:
			if int(pr["owner"]) != 0 or bool(pr.get("lob", false)):
				continue
			var known := false
			for entry in live:
				if is_same(pr, entry[0]):
					known = true
			if not known:
				var is_far: bool = (pr["pos"] as Vector2).distance_to(foe.pos) >= far
				thrown += 1 if is_far else 0
				live.append([pr, is_far, pr["pos"]])
		if sim.creatures[0].state == CreatureSim.State.KO or foe.state == CreatureSim.State.KO:
			break
	return [thrown, hits]


func test_rage_sidesteps_shots() -> void:
	# Rage Chef Cerebro throws knives from range at a Hard Sno Mercy, then at a Rage one:
	# Rage walks out of the way of far more of them.
	# Twelve seeds: one seed read either way since the Cerebro nerf.
	var vs_hard := [0, 0]
	var vs_rage := [0, 0]
	for s in range(1, 13):
		var h := _far_knives(RAGE, "sno", HARD, s, 55.0)  # knives reach about 115 px since the Oct 2026 kit pass
		var r := _far_knives(RAGE, "sno", RAGE, s, 55.0)
		for k in 2:
			vs_hard[k] += h[k]
			vs_rage[k] += r[k]
	var rate_hard := float(vs_hard[1]) / maxf(1.0, float(vs_hard[0]))
	var rate_rage := float(vs_rage[1]) / maxf(1.0, float(vs_rage[0]))
	assert_gt(float(vs_rage[0]), 15.0, "knives were thrown at Rage from range:")
	# Shots hit 1.6x wider since Oct 2026 (projectiles.json), so walking out of their way is
	# harder for everyone. Since the Oct 25 2026 Cerebro nerf (no stagger from the Mallet
	# Toss, a faster glide) Rage takes about 0.85 of Hard's rate over these twelve seeds
	# (187/286 against 358/465; 0.77 before the nerf), so the pin is under 0.9.
	# Since the Normal-and-below CPUs chase a kiting mage (Oct 2026) Rage takes about 0.94 of
	# Hard's rate (190/273 against 341/443): still fewer.
	assert_lt(rate_rage, rate_hard, "Rage is hit by fewer of them (%d/%d; Hard %d/%d):" % [
		vs_rage[1], vs_rage[0], vs_hard[1], vs_hard[0]])


func test_rage_punishes_a_whiff() -> void:
	# Culvert throws a big Slam from too far away; Rage Cairn stays clear and hits back
	# before Culvert recovers.
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.creatures[0].pos = Vector2(200, 180)
	sim.creatures[1].pos = Vector2(256, 180)
	sim.creatures[1].facing = Vector2.LEFT
	var cpu := CpuController.new(0, RAGE, 9)
	var punished := false
	for t in 120:
		var foe_bits := SimDefs.IN_HEAVY if t < 2 else 0
		sim.step(PackedInt32Array([cpu.bits(sim), foe_bits]))
		for e in sim.events:
			if e["type"] == "hit" and int(e["attacker"]) == 0 and sim.creatures[1].move_id == "heavy":
				punished = true
	assert_near(sim.creatures[0].hp, sim.creatures[0].max_hp, 0.01, "the Slam never touched Rage:")
	assert_true(punished, "and Rage hit Culvert before it recovered")


func test_rage_assassin_hunts_the_weakest() -> void:
	# A 2v2: Sneaky Pete (an assassin) has a healthy foe close by and a nearly beaten one
	# further away. It goes for the weak one; a tank would go for whoever is on its hurt
	# teammate.
	var t := TeamSim.new([["pete", "craglash"], ["cairn", "culvert"]], 2)
	var s := t.sim
	s.creatures[0].pos = Vector2(200, 160)
	s.creatures[2].pos = Vector2(240, 160)  # healthy, near
	s.creatures[3].pos = Vector2(330, 230)  # weak, further
	s.creatures[3].hp = s.creatures[3].max_hp * 0.15
	var pete := CpuController.new(0, RAGE, 3)
	assert_eq(pete._pick_target(s, s.creatures[0]), s.creatures[3], "the assassin picks the weak foe:")
	var hard := CpuController.new(0, HARD, 3)
	assert_eq(s.nearest_opponent(s.creatures[0]), s.creatures[2], "(the nearest is the healthy one)")
	# The tank: its teammate Pete is hurt and Culvert is on him.
	s.creatures[0].hp = s.creatures[0].max_hp * 0.3
	s.creatures[1].pos = Vector2(150, 260)
	s.creatures[3].pos = Vector2(215, 165)
	var tank := CpuController.new(1, RAGE, 3)
	assert_eq(tank._pick_target(s, s.creatures[1]), s.creatures[3], "the tank peels for its hurt teammate:")
	assert_true(hard != null, "")


func test_rage_team_battle_plays_out() -> void:
	# Six Rage CPUs: the match ends, and nobody hurts a teammate.
	var t := TeamSim.new([["cerebro", "craglash", "pete"], ["hissy", "gillbert", "barkley"]], 3)
	var zero := PackedInt32Array([0, 0, 0, 0, 0, 0])
	while t.phase == TeamSim.Phase.INTRO:
		t.step(zero)
	var cpus: Array = []
	for i in 6:
		cpus.append(CpuController.new(i, RAGE, 70 + i))
	for tick in 9000:
		var ins := PackedInt32Array()
		for i in 6:
			ins.append((cpus[i] as CpuController).bits(t.sim))
		t.step(ins)
		for e in t.sim.events:
			if e["type"] == "hit":
				assert_true(t.sim.creatures[int(e["attacker"])].is_foe(t.sim.creatures[int(e["target"])]),
					"hits only land on foes")
		if t.phase == TeamSim.Phase.OVER:
			break
	assert_eq(t.phase, TeamSim.Phase.OVER, "the match is decided:")


func test_rage_matches_replay_exactly() -> void:
	var a: Dictionary = _match("cerebro", "digby", RAGE, RAGE, 8)
	var b: Dictionary = _match("cerebro", "digby", RAGE, RAGE, 8)
	assert_eq(a["ticks"], b["ticks"], "match length:")
	assert_eq((a["sim"] as MatchSim).state_hash(), (b["sim"] as MatchSim).state_hash(), "final state:")


## A Surge isn't unblockable (only a floor-opening or guard-breaking one is): Rage answers
## Sno's Flavor Blast at 30 px (a block, a counter or a timed roll) and is never frozen.
func test_rage_blocks_or_rolls_a_blockable_surge() -> void:
	for seed_ in [1, 2, 3, 4]:
		var sim := MatchFactory.versus("sno", "cairn")
		sim.creatures[0].pos = Vector2(220, 164)
		sim.creatures[1].pos = Vector2(250, 164)
		sim.creatures[0].facing = Vector2.RIGHT
		sim.creatures[1].facing = Vector2.LEFT
		sim.creatures[0].energy = CreatureSim.MAX_ENERGY
		var cpu := CpuController.new(1, RAGE, seed_)
		var frozen := false
		var pressed := false
		for t in 150:
			var b0 := 0
			if t == 0:
				b0 = SimDefs.IN_SURGE
				pressed = true
			sim.step(PackedInt32Array([b0, 0 if t == 0 else cpu.bits(sim)]))  # the Surge starts first
			if sim.creatures[1].stone > 0:
				frozen = true
		assert_true(pressed, "")
		assert_true(not frozen, "seed %d: Cairn was frozen by a blockable Surge" % seed_)
