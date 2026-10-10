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
	for s in 3:
		var m: Dictionary = _cpu_match("cairn", "culvert", 1, 1, 10 + s)
		for i in 2:
			used[i].merge(m["moves"][i])
			combos[i] = maxi(combos[i], int(m["best_combo"][i]))
		if int(m["ticks"]) < MAX_TICKS:
			kos += 1
	for i in 2:
		var who := "Cairn" if i == 0 else "Culvert"
		assert_true(used[i].has("light_1"), who + " uses lights")
		assert_true(used[i].has("skill_1") or used[i].has("slip_counter"), who + " uses Skill 1")
		assert_true(used[i].has("skill_2"), who + " uses Skill 2")
		assert_gt(combos[i], 2, who + " lands 3+ hit combos:")
	assert_gt(kos, 1, "matches that end in a knockout (of 3):")


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
