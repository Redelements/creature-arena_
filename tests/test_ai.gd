extends TestCase
## The CPU opponent: deterministic, actually fights, and difficulty matters.

const MAX_TICKS := 5400  # 90 seconds


## Plays CPU vs CPU until a knockout or the time limit. Returns a summary.
func _cpu_match(left: String, right: String, lv_l: int, lv_r: int, seed_ := 1) -> Dictionary:
	var sim := MatchFactory.versus(left, right)
	var cpus := [CpuController.new(0, lv_l, seed_ * 7 + 1), CpuController.new(1, lv_r, seed_ * 13 + 5)]
	var moves_used := [{}, {}]
	var best_combo := [0, 0]
	var ticks := 0
	while ticks < MAX_TICKS:
		ticks += 1
		sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
		for i in 2:
			var c := sim.creatures[i]
			if c.state == CreatureSim.State.ATTACK:
				moves_used[i][c.move_id] = true
		for e in sim.events:
			if e["type"] == "hit":
				var a := int(e["attacker"])
				best_combo[a] = maxi(best_combo[a], int(e["combo"]))
		if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
			break
	var r0 := sim.creatures[0].hp / sim.creatures[0].max_hp
	var r1 := sim.creatures[1].hp / sim.creatures[1].max_hp
	return {
		"sim": sim, "ticks": ticks, "winner": 0 if r0 > r1 else 1,
		"hp": [r0, r1], "moves": moves_used, "best_combo": best_combo,
	}


func test_cpu_matches_are_reproducible() -> void:
	var a: Dictionary = _cpu_match("cairn", "culvert", 1, 1, 3)
	var b: Dictionary = _cpu_match("cairn", "culvert", 1, 1, 3)
	assert_eq(a["ticks"], b["ticks"], "match length:")
	assert_eq((a["sim"] as MatchSim).state_hash(), (b["sim"] as MatchSim).state_hash(), "final state:")


func test_cpu_fights_with_its_whole_kit() -> void:
	var used := [{}, {}]
	var combos := [0, 0]
	var kos := 0
	# A skill can sit out a match or two; over twenty, the whole kit comes out. (A Normal
	# Culvert finishes a 3+ hit combo in about one match in five, so five matches missed it
	# about a third of the time.)
	for s in 20:
		var m: Dictionary = _cpu_match("cairn", "culvert", 1, 1, 10 + s)
		for i in 2:
			used[i].merge(m["moves"][i])
			combos[i] = maxi(combos[i], int(m["best_combo"][i]))
		if int(m["ticks"]) < MAX_TICKS:
			kos += 1
	for i in 2:
		var who := "Cairn" if i == 0 else "Culvert"
		assert_true(used[i].has("light_1"), who + " uses lights")
		if i == 1:
			assert_true(used[i].has("skill_1"), who + " uses Skill 1")
		assert_true(used[i].has("skill_2"), who + " uses Skill 2")
		assert_gt(combos[i], 2, who + " lands 3+ hit combos:")
	assert_gt(kos, 2, "matches that end in a knockout (of 5):")
	# Cairn's Skill 1 is a counter, so it needs a foe who winds up big moves at close
	# range: Craglash (Culvert's Runoff is a cone now, not the slow shockwave it was).
	var slipped := false
	for s in 5:
		var m: Dictionary = _cpu_match("cairn", "craglash", 1, 1, 30 + s)
		slipped = slipped or m["moves"][0].has("skill_1") or m["moves"][0].has("slip_counter")
	assert_true(slipped, "Cairn uses Slip against a fighter who winds up")


func test_hard_beats_easy() -> void:
	var hard_wins := 0
	var games := 0
	for s in 3:
		var m: Dictionary = _cpu_match("cairn", "culvert", 2, 0, 20 + s)
		hard_wins += 1 if int(m["winner"]) == 0 else 0
		var n: Dictionary = _cpu_match("cairn", "culvert", 0, 2, 40 + s)
		hard_wins += 1 if int(n["winner"]) == 1 else 0
		games += 2
	assert_gt(hard_wins, games * 0.66, "Hard wins (of %d):" % games)


func test_cpu_tags_out_a_badly_hurt_creature_in_a_duel() -> void:
	var d := DuelSim.new([["cairn", "culvert", "cairn"], ["culvert", "cairn", "culvert"]])
	var cpu := CpuController.new(1, 2, 7)
	cpu.duel = d
	var hurt := d.active_creature(1)
	hurt.hp = hurt.max_hp * 0.2
	var tagged := false
	for i in 1200:
		d.step(PackedInt32Array([0, cpu.bits(d.sim)]))
		if d.active_creature(1) != hurt:
			tagged = true
			break
	assert_true(tagged, "a Hard CPU should tag out a creature on 20% health")


func test_craglash_cpu_uses_its_whole_kit() -> void:
	var used := {}
	for s in 6:
		var m: Dictionary = _cpu_match("craglash", "cairn", 1, 1, 60 + s)
		for mid in m["moves"][0]:
			used[mid] = true
	for mid in ["light_1", "heavy", "skill_1", "skill_2"]:
		assert_true(used.has(mid), "the Craglash CPU should use %s" % mid)


func test_barkley_cpu_uses_its_whole_kit() -> void:
	var used := {}
	for s in 6:
		var m: Dictionary = _cpu_match("barkley", "cairn", 1, 1, 80 + s)
		for mid in m["moves"][0]:
			used[mid] = true
	for mid in ["light_1", "light_3", "heavy", "skill_1", "skill_2"]:
		assert_true(used.has(mid), "the Barkley CPU should use %s" % mid)


func test_gillbert_cpu_uses_its_whole_kit() -> void:
	var used := {}
	for s in 6:
		var m: Dictionary = _cpu_match("gillbert", "cairn", 1, 1, 100 + s)
		for mid in m["moves"][0]:
			used[mid] = true
	for mid in ["light_1", "light_3", "heavy", "skill_1", "skill_2"]:
		assert_true(used.has(mid), "the Gillbert CPU should use %s" % mid)


func test_cerebro_cpu_uses_its_whole_kit() -> void:
	var used := {}
	for s in 6:
		var m: Dictionary = _cpu_match("cerebro", "cairn", 1, 1, 100 + s)
		for mid in m["moves"][0]:
			used[mid] = true
	for mid in ["light_1", "light_3", "heavy", "skill_1", "skill_2"]:
		assert_true(used.has(mid), "the Chef Cerebro CPU should use %s" % mid)


func test_hissy_cpu_uses_its_whole_kit() -> void:
	var used := {}
	for s in 6:
		var m: Dictionary = _cpu_match("hissy", "cairn", 1, 1, 100 + s)
		for mid in m["moves"][0]:
			used[mid] = true
	for mid in ["light_1", "light_3", "heavy", "skill_1", "skill_2"]:
		assert_true(used.has(mid), "the Hissy Fitz CPU should use %s" % mid)


func test_digby_cpu_uses_its_whole_kit() -> void:
	var used := {}
	for s in 6:
		var m: Dictionary = _cpu_match("digby", "cairn", 1, 1, 100 + s)
		for mid in m["moves"][0]:
			used[mid] = true
	for mid in ["light_1", "light_3", "heavy", "skill_1", "skill_2"]:
		assert_true(used.has(mid), "the Digby CPU should use %s" % mid)


func test_pete_cpu_uses_its_whole_kit() -> void:
	var used := {}
	for s in 6:
		var m: Dictionary = _cpu_match("pete", "cairn", 1, 1, 100 + s)
		for mid in m["moves"][0]:
			used[mid] = true
	for mid in ["light_1", "light_3", "heavy", "skill_1", "skill_2"]:
		assert_true(used.has(mid), "the Sneaky Pete CPU should use %s" % mid)


func test_sno_cpu_uses_its_whole_kit() -> void:
	var used := {}
	for s in 6:
		var m: Dictionary = _cpu_match("sno", "cairn", 1, 1, 100 + s)
		for mid in m["moves"][0]:
			used[mid] = true
	for mid in ["light_1", "light_3", "heavy", "skill_1", "skill_2"]:
		assert_true(used.has(mid), "the Sno Mercy CPU should use %s" % mid)


## A foe's threat range comes from its move's widest hit segment (Barkley's last Timber
## Twister ring), not just the move-level radius.
func test_threat_range_uses_the_widest_segment() -> void:
	var sim := MatchFactory.versus("barkley", "cairn")
	var barkley := sim.creatures[0]
	var me := sim.creatures[1]
	barkley.move_id = "surge"
	barkley.moves()["surge"]["hit_radius"] = 10  # the move-level radius alone would say 10
	var cpu := CpuController.new(1, 3, 1)
	assert_near(cpu._threat_range(barkley, me), 90.0 + 1.0 + me.radius + 6.0, 0.001, "widest ring (90):")
	assert_near(barkley.move_range("surge"), 90.0, 0.001, "move_range is the per-segment max")


## A Surge with no surge_range in the JSON, no projectile and no armor gets one from its reach.
func test_surge_range_defaults_from_the_move() -> void:
	var sim := MatchFactory.versus("barkley", "cairn")
	var cpu := CpuController.new(0, 3, 1)
	var b := sim.creatures[0]
	var ai := {}
	assert_near(cpu._surge_range(b, ai), b.move_range("surge") - 10.0, 0.001, "default:")
	assert_near(cpu._surge_range(b, {"surge_range": 77}), 77.0, 0.001, "the JSON wins:")
	var cerebro := MatchFactory.versus("cerebro", "cairn").creatures[0]
	assert_eq(cpu._surge_range(cerebro, ai), 0.0, "a projectile Surge has none:")


## A roll carries about 50 px: the CPU's open-floor check looks that far, so a sideways
## roll under a Surge never lands in a pit 45 px away.
func test_a_roll_direction_keeps_clear_of_pits_at_roll_distance() -> void:
	var sim := MatchFactory.versus("cairn", "sno")
	var me := sim.creatures[0]
	me.pos = Vector2(220, 164)
	for cx in range(32, 36):  # a strip of pits 45 px to the right (x 256-288), every row
		for cy in sim.terrain.rows:
			sim.terrain.set_cell(Vector2i(cx, cy), TerrainGrid.HOLE)
	sim.terrain.version += 1
	var cpu := CpuController.new(0, 3, 1)
	var roll := CpuController._roll_distance(me)
	assert_near(roll, 50.0, 6.0, "about 50 px for Cairn:")
	var d := cpu._open_dir(sim, me, Vector2.RIGHT, roll)
	assert_true(not sim.terrain.is_hole_at(me.pos + d * (me.radius + roll)), "the roll doesn't end in the pits")
	assert_true(not sim.terrain.is_hole_at(me.pos + d * roll), "(nor at its plain distance)")


## An assassin on an arena with brush lurks in it: the Rage CPU walks into a patch within
## burst range of the foe and waits there out of sight, then strikes from cover. On the
## Stadium there is none, so it circles as before.
func test_an_assassin_lurks_in_brush_when_the_arena_has_it() -> void:
	var was: String = MatchFactory.arena
	MatchFactory.arena = "greenhouse"
	var sim := MatchFactory.versus("digby", "cerebro")
	MatchFactory.arena = was
	var cpus := [CpuController.new(0, CpuController.RAGE, 5), CpuController.new(1, CpuController.RAGE, 6)]
	var covered := 0
	for t in 900:
		sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
		if sim.creatures[0].covered:
			covered += 1
		if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
			break
	assert_gt(covered, 30, "Rage Digby spends time hidden in the Greenhouse brush (%d ticks)" % covered)
	var plain := MatchFactory.versus("digby", "cerebro")
	var cpu := CpuController.new(0, CpuController.RAGE, 5)
	var foe := CpuController.new(1, CpuController.RAGE, 6)
	for t in 120:
		plain.step(PackedInt32Array([cpu.bits(plain), foe.bits(plain)]))
	assert_eq(cpu._cover, Vector2.INF, "no brush on the Stadium: nothing to lurk in")


## A landed pop-up out of Burrow is an opener: the route that starts with skill_2 carries
## on into the juggle string instead of steering a tunnel that is over.
func test_rage_digby_juggles_after_a_landed_pop_up() -> void:
	var sim := MatchFactory.versus("digby", "cerebro")
	var dig := sim.creatures[0]
	var foe := sim.creatures[1]
	var cpu := CpuController.new(0, CpuController.RAGE, 11)
	var popped := -1
	var followed := false
	for t in 1800:
		sim.step(PackedInt32Array([cpu.bits(sim), 0]))
		if popped < 0:
			for e in sim.events:
				if e["type"] == "hit" and int(e["attacker"]) == 0 and dig.move_id == "skill_2":
					popped = t
		elif dig.state == CreatureSim.State.ATTACK and dig.move_id.begins_with("light") and foe.is_airborne():
			followed = true
			break
		if popped >= 0 and t > popped + 60:
			break
	assert_true(popped >= 0, "the pop-up landed on the standing Chef")
	assert_true(followed, "and a light followed it while he was still in the air")


## The scored kit's considerations (piece 2 of docs/plans/ai-utility-and-teamplay.md):
## each 0 to 1, at its ends and in between.
func test_scored_kit_factors() -> void:
	assert_eq(CpuController.f_band(50.0, 40.0, 60.0, 20.0), 1.0, "inside the band:")
	assert_eq(CpuController.f_band(70.0, 40.0, 60.0, 20.0), 0.5, "half the fall past it:")
	assert_eq(CpuController.f_band(100.0, 40.0, 60.0, 20.0), 0.0, "far past it:")
	var sim := MatchFactory.versus("crease", "pete")
	var me := sim.creatures[0]
	var foe := sim.creatures[1]
	var to_foe := foe.pos - me.pos
	foe.walk_vel = Vector2.ZERO
	assert_eq(CpuController.f_closing(foe, to_foe), 0.0, "standing still isn't closing:")
	foe.walk_vel = -to_foe.normalized() * 2.0
	assert_eq(CpuController.f_closing(foe, to_foe), 1.0, "walking straight in:")
	foe.walk_vel = to_foe.normalized() * 2.0
	assert_eq(CpuController.f_closing(foe, to_foe), 0.0, "walking away:")
	foe.facing = -to_foe.normalized()
	assert_eq(CpuController.f_facing(foe, to_foe), 1.0, "facing me:")
	foe.facing = to_foe.normalized()
	assert_eq(CpuController.f_facing(foe, to_foe), 0.0, "facing away:")
	assert_eq(CpuController.f_matchup(me, foe), 0.0, "a mage loses to an assassin:")
	assert_eq(CpuController.f_matchup(foe, me), 1.0, "an assassin beats a mage:")
	assert_eq(CpuController.f_matchup(me, me), 0.5, "a mirror is even:")
	assert_eq(CpuController.f_hp_edge(me, foe), 0.5, "even health:")
	foe.hp = 0.0
	assert_eq(CpuController.f_hp_edge(me, foe), 1.0, "all the health on my side:")
	assert_eq(CpuController.compensate(1.0, 3), 1.0, "a full score stays full:")
	assert_eq(CpuController.compensate(0.0, 3), 0.0, "a zero stays zero:")
	assert_true(CpuController.compensate(0.25, 2) > 0.25, "more factors are made up for:")
	assert_eq(CpuController.f_safe(foe, 8), 1.0, "a foe that isn't striking is safe to start on:")


## The scored kit plays, and one seed replays the same match.
func test_scored_kit_is_reproducible_and_fights() -> void:
	var runs: Array = []
	for k in 2:
		var sim := MatchFactory.versus("crease", "hissy")
		var cpus := [CpuController.new(0, 3, 11), CpuController.new(1, 3, 19)]
		cpus[0].scored = true
		var kit := 0
		for t in 1800:
			sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
			if sim.creatures[0].state == CreatureSim.State.ATTACK and sim.creatures[0].move_id.begins_with("skill"):
				kit += 1
		runs.append([sim.state_hash(), kit])
	assert_eq(runs[0][0], runs[1][0], "same seed, same match:")
	assert_true(int(runs[0][1]) > 0, "it throws its kit")
