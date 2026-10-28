extends TestCase
## Team battles (2v2, 3v3; TeamSim): teammates never hurt or hinder each other, moves
## that pick a foe skip teammates, the last team standing wins, time out goes to health
## share, and the whole thing rolls back exactly.

const L := SimDefs.IN_LIGHT


## A bare match: `spec` is [[id, team, pos], ...]; everyone faces right.
func _match(spec: Array) -> MatchSim:
	var m := MatchSim.new()
	for s in spec:
		var c := m.add_creature(MatchFactory.load_def(String(s[0])), s[2])
		c.team = int(s[1])
		c.facing = Vector2.RIGHT
	return m


func _step(m: MatchSim, first: int, ticks: int) -> void:
	for t in ticks:
		var ins := PackedInt32Array()
		ins.resize(m.creatures.size())
		ins[0] = first
		m.step(ins)


func _team_battle(per_side: int) -> TeamSim:
	var t := TeamSim.new([["cairn", "culvert", "craglash"], ["culvert", "cairn", "barkley"]], per_side)
	var zero := PackedInt32Array()
	zero.resize(t.slot_count())
	while t.phase == TeamSim.Phase.INTRO:
		t.step(zero)
	return t


func test_a_1v1_is_two_teams_of_one() -> void:
	var m := MatchFactory.versus("cairn", "culvert")
	assert_eq(m.creatures[0].team, 0, "left team:")
	assert_eq(m.creatures[1].team, 1, "right team:")
	assert_true(m.creatures[0].is_foe(m.creatures[1]), "the two are foes")
	assert_false(m.creatures[0].is_foe(m.creatures[0]), "never its own foe")


func test_team_sim_lines_up_both_sides() -> void:
	for n in [2, 3]:
		var t := TeamSim.new([["cairn", "culvert", "craglash"], ["culvert", "cairn", "barkley"]], n)
		assert_eq(t.sim.creatures.size(), n * 2, "%d per side:" % n)
		for i in t.slot_count():
			assert_eq(t.side_of(i), 0 if i < n else 1, "slot %d's side:" % i)
		assert_lt(t.sim.creatures[0].pos.x, t.sim.creatures[n].pos.x, "left team on the left")
		assert_true(t.sim.creatures[0].pos.y != t.sim.creatures[1].pos.y, "teammates spread up and down")


func test_teammates_cant_hit_each_other() -> void:
	var m := _match([["cairn", 0, Vector2(300, 200)], ["culvert", 0, Vector2(322, 200)],
		["cairn", 1, Vector2(420, 200)]])
	var ally := m.creatures[1]
	for i in 6:
		_step(m, L, 2)
		_step(m, 0, 14)
	assert_near(ally.hp, ally.max_hp, 0.001, "the teammate in reach takes nothing:")
	assert_eq(ally.state != CreatureSim.State.HITSTUN, true, "and never flinches")
	# The same swings on a foe standing there land.
	var m2 := _match([["cairn", 0, Vector2(300, 200)], ["culvert", 1, Vector2(322, 200)]])
	for i in 6:
		_step(m2, L, 2)
		_step(m2, 0, 14)
	assert_lt(m2.creatures[1].hp, m2.creatures[1].max_hp, "a foe in the same spot is hit")


func test_projectiles_fly_past_teammates_to_foes() -> void:
	var m := _match([["cerebro", 0, Vector2(250, 200)], ["culvert", 0, Vector2(285, 200)],
		["culvert", 1, Vector2(330, 200)]])
	_step(m, L, 2)
	_step(m, 0, 40)
	assert_near(m.creatures[1].hp, m.creatures[1].max_hp, 0.001, "the knife passes the teammate:")
	assert_lt(m.creatures[2].hp, m.creatures[2].max_hp, "and hits the foe behind")


func test_ice_puddle_slows_only_foes() -> void:
	var m := _match([["sno", 0, Vector2(300, 200)], ["culvert", 0, Vector2(322, 188)],
		["culvert", 1, Vector2(322, 212)]])
	_step(m, SimDefs.IN_SKILL1, 2)
	var slowed_ally := false
	var slowed_foe := false
	for t in 60:
		_step(m, 0, 1)
		slowed_ally = slowed_ally or m.creatures[1].slow > 0
		slowed_foe = slowed_foe or m.creatures[2].slow > 0
	assert_false(m.zones.is_empty(), "the puddle is down")
	assert_false(slowed_ally, "the teammate in the puddle isn't slowed")
	assert_true(slowed_foe, "the foe in it is")


func test_taunt_pulls_only_foes() -> void:
	var m := _match([["craglash", 0, Vector2(300, 200)], ["culvert", 0, Vector2(340, 200)],
		["culvert", 1, Vector2(260, 200)]])
	# Bedrock is Craglash's Surge: it needs a full meter, and its freeze and windup come first.
	m.creatures[0].energy = 100.0
	_step(m, SimDefs.IN_SURGE, 2)
	_step(m, 0, 40)
	assert_eq(m.creatures[1].taunt, 0, "the teammate isn't taunted:")
	assert_gt(m.creatures[2].taunt, 0, "the foe is")


func test_nearest_opponent_skips_teammates() -> void:
	var m := _match([["cairn", 0, Vector2(300, 200)], ["culvert", 0, Vector2(310, 200)],
		["cairn", 1, Vector2(450, 200)], ["culvert", 1, Vector2(500, 200)]])
	assert_eq(m.nearest_opponent(m.creatures[0]), m.creatures[2], "the closest foe, not the teammate beside:")
	m.creatures[2].state = CreatureSim.State.KO
	assert_eq(m.nearest_opponent(m.creatures[0]), m.creatures[3], "a knocked-out foe is skipped:")


func test_intro_holds_everyone_still() -> void:
	var t := TeamSim.new([["cairn", "culvert"], ["culvert", "cairn"]], 2)
	var start := t.sim.creatures[0].pos
	var ins := PackedInt32Array([SimDefs.IN_RIGHT | L, 0, 0, 0])
	for i in 30:
		t.step(ins)
	assert_eq(t.phase, TeamSim.Phase.INTRO, "still in the intro:")
	assert_near(t.sim.creatures[0].pos.x, start.x, 0.001, "no moving during the intro:")


func test_one_ko_doesnt_end_it_the_last_one_does() -> void:
	var t := _team_battle(2)
	var zero := PackedInt32Array([0, 0, 0, 0])
	t.sim.creatures[2].hp = 0.0
	t.sim.creatures[2].state = CreatureSim.State.KO
	t.step(zero)
	assert_eq(t.phase, TeamSim.Phase.FIGHT, "one of two down: the fight goes on:")
	assert_eq(t.alive_count(1), 1, "one left on the right:")
	t.sim.creatures[3].hp = 0.0
	t.sim.creatures[3].state = CreatureSim.State.KO
	t.step(zero)
	assert_eq(t.phase, TeamSim.Phase.OVER, "both down:")
	assert_eq(t.winner, 0, "the left team wins:")
	var over := t.sim.events.filter(func(e): return e["type"] == "duel_over")
	assert_eq(over.size(), 1, "a duel_over event for the views:")


func test_time_out_goes_to_health_share() -> void:
	var t := _team_battle(3)
	t.sim.creatures[0].hp = t.sim.creatures[0].max_hp * 0.2  # left lost most of one fighter
	t.timer = 1
	t.step(PackedInt32Array([0, 0, 0, 0, 0, 0]))
	assert_eq(t.phase, TeamSim.Phase.OVER, "time ran out:")
	assert_eq(t.winner, 1, "the healthier team wins:")


func test_cpu_team_battle_finishes_and_rolls_back() -> void:
	var t := _team_battle(2)
	var cpus: Array = []
	for i in t.slot_count():
		cpus.append(CpuController.new(i, 2, 50 + i))
	var saved := {}
	var digest := ""
	var log: Array = []
	var ally_hits := 0
	for tick in 8000:
		if tick == 300:
			saved = t.snapshot()
		var ins := PackedInt32Array()
		for i in t.slot_count():
			ins.append((cpus[i] as CpuController).bits(t.sim))
		var logging := tick >= 300 and digest == ""
		if logging:
			log.append(ins)
		t.step(ins)
		if logging and (log.size() == 400 or t.phase == TeamSim.Phase.OVER):
			digest = t.state_digest()
		for e in t.sim.events:
			if e["type"] == "hit":
				if t.sim.creatures[int(e["attacker"])].team == t.sim.creatures[int(e["target"])].team:
					ally_hits += 1
		if t.phase == TeamSim.Phase.OVER:
			break
	assert_eq(ally_hits, 0, "nobody ever hit a teammate:")
	assert_eq(t.phase, TeamSim.Phase.OVER, "the CPUs finish the match:")
	assert_gt(log.size(), 100, "the match ran past the snapshot")
	# Replay from the snapshot: the same state, exactly.
	var t2 := TeamSim.new([["cairn", "culvert", "craglash"], ["culvert", "cairn", "barkley"]], 2)
	t2.restore(saved)
	for ins in log:
		t2.step(ins)
	assert_eq(t2.state_digest(), digest, "restored and replayed, the same match:")


## The team intent pin (piece 3 of docs/plans/ai-utility-and-teamplay.md): Rage 3v3 on the
## Stadium, a tank, a mage and an assassin a side, the two picks of each class swapped each
## seed, both sides played (`bench_cpu.gd --teams=3 --a=3 --seeds=6 --intent=a`, the same
## seeds): the side playing to its team's intent (focus, engage state, front line, peel,
## isolated targets) against the side picking alone. The plan hoped for 65%; measured Oct 27
## the coordinated side wins 4 of these 12 (as with the shared focus alone, before the rest of
## piece 3) and 22 of 48 at --seeds=24 (24 before; 27 of 48 with nobody coordinated, the
## noise floor): the class picks decide these fights (the Culvert, Cerebro, Digby side wins
## about two in three either way), not the coordination. So the pin holds what is measured,
## and moves only with a reason in the PR.
const PIN_TEAM_WINS := 4


func test_coordinated_rage_holds_its_own_in_a_3v3() -> void:
	var picks := [["craglash", "culvert"], ["crease", "cerebro"], ["pete", "digby"]]
	var won := 0
	for s in 6:
		for side in 2:
			TeamIntent.reset()
			var ids := [[], []]
			for k in 3:
				ids[side].append(picks[k][s % 2])
				ids[1 - side].append(picks[k][(s + 1) % 2])
			var t := TeamSim.new(ids, 3)
			var cpus: Array = []
			for i in t.slot_count():
				var cpu := CpuController.new(i, CpuController.RAGE, 700 + s * 31 + side * 7 + i)
				cpu.intent = t.side_of(i) == side
				cpus.append(cpu)
			var ticks := 0
			while t.phase != TeamSim.Phase.OVER and ticks < 7200:
				var ins := PackedInt32Array()
				for c in cpus:
					ins.append((c as CpuController).bits(t.sim))
				t.step(ins)
				ticks += 1
			won += 1 if t.winner == side else 0
	assert_true(won >= PIN_TEAM_WINS, "the coordinated side won %d of 12 (pin %d)" % [won, PIN_TEAM_WINS])
