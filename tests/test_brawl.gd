extends TestCase
## Brawl: a free-for-all of up to four, each their own team, last standing wins or the
## healthiest at time; Chaos Cup stacks mutators on it; a replay's setup rebuilds the
## match it was recorded on.

const FOUR := ["cairn", "culvert", "craglash", "barkley"]


func _brawl(ids: Array = FOUR, muts := {}) -> BrawlSim:
	var b := BrawlSim.new(ids, {}, muts, 3)
	while b.phase == BrawlSim.Phase.INTRO:
		b.step(PackedInt32Array())
	return b


func _idle(b: BrawlSim, ticks: int) -> void:
	for i in ticks:
		b.step(PackedInt32Array())


func _ko(b: BrawlSim, slot: int) -> void:
	b.sim.creatures[slot].hp = 0.0
	b.sim.creatures[slot]._set_state(CreatureSim.State.KO)


func test_everyone_is_their_own_team_and_the_last_standing_wins() -> void:
	var b := _brawl()
	assert_eq(b.slot_count(), 4, "four in:")
	for i in 4:
		assert_eq(b.sim.creatures[i].team, i, "slot %d is its own team:" % i)
		for j in 4:
			if i != j:
				assert_true(b.sim.creatures[i].is_foe(b.sim.creatures[j]), "%d and %d are foes" % [i, j])
	for c in b.sim.creatures:
		assert_false(b.sim.terrain.body_blocked(c.pos, c.radius), "a clear spawn")
	_ko(b, 0)
	_ko(b, 2)
	_idle(b, 1)
	assert_eq(b.phase, BrawlSim.Phase.FIGHT, "two left: on it goes")
	_ko(b, 3)
	_idle(b, 1)
	assert_eq(b.phase, BrawlSim.Phase.OVER, "one left: over")
	assert_eq(b.winner, 1, "the last standing:")


func test_at_time_the_healthiest_wins_and_a_tie_is_a_draw() -> void:
	var b := _brawl(["cairn", "culvert", "pete"])
	b.sim.creatures[0].hp = b.sim.creatures[0].max_hp * 0.5
	b.sim.creatures[1].hp = b.sim.creatures[1].max_hp * 0.8
	b.sim.creatures[2].hp = b.sim.creatures[2].max_hp * 0.3
	b.timer = 1
	_idle(b, 2)
	assert_eq(b.phase, BrawlSim.Phase.OVER, "time:")
	assert_eq(b.winner, 1, "the healthiest:")
	var d := _brawl(["cairn", "culvert"])
	d.timer = 1
	_idle(d, 2)
	assert_eq(d.winner, -1, "both full: a draw:")


func test_chaos_cup_stacks_mutators_and_it_all_rolls_back() -> void:
	var b := _brawl(FOUR, {"speed_mult": 1.3, "surge_every": 50})
	assert_near(b.sim.creatures[2].speed_mult, 1.3, 0.001, "haste on everyone:")
	_idle(b, 50)
	assert_near(b.sim.creatures[3].energy, CreatureSim.MAX_ENERGY, 0.01, "surge rush:")
	var s := b.snapshot()
	var dg := b.state_digest()
	_ko(b, 1)
	_idle(b, 30)
	b.restore(s)
	assert_eq(b.state_digest(), dg, "restore:")


func test_a_replay_setup_rebuilds_the_match_it_was_recorded_on() -> void:
	var setup := {"kind": "brawl", "ids": FOUR, "arena": "quarry", "mutators": {"damage_mult": 1.5}, "mut_seed": 9}
	var built := ReplayBuilder.build(setup)
	var b: BrawlSim = built["game"]
	assert_eq(b.sim.arena_id, "quarry", "the arena:")
	assert_near(b.sim.creatures[0].damage_mult, 1.5, 0.001, "the mutators:")
	var rep := Replay.new()
	rep.setup = setup
	var cpus := []
	for i in 4:
		cpus.append(CpuController.new(i, 1, 10 + i))
	for t in 400:
		var ins := PackedInt32Array()
		for i in 4:
			ins.append((cpus[i] as CpuController).bits(b.sim))
		rep.record(ins)
		b.step(ins)
	var d := b.sim.state_digest()
	var again := Replay.from_dict(rep.to_dict())
	assert_true(again.setup is Dictionary, "the setup survives the file")
	assert_eq(ReplayBuilder.play(again), d, "the replay reproduces the fight:")
	var v := ReplayBuilder.build({"kind": "versus", "ids": ["hissy", "sno"], "arena": "floodgate"})
	assert_eq((v["sim"] as MatchSim).arena_id, "floodgate", "a versus setup:")
	assert_eq(String((v["sim"] as MatchSim).creatures[1].def["id"]), "sno", "with its fighters:")
	assert_eq(MatchFactory.arena, ArenaMap.DEFAULT, "and the menu's arena is left alone")
