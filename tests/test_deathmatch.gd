extends TestCase
## Team Deathmatch: unlimited respawns on each team's pad, spawn protection, KOs score,
## first to the target wins, a tie at time is sudden death, and it all rolls back.

const TEAMS := [["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]]


func _tdm(size := 2) -> TeamSim:
	var t := TeamSim.new(TEAMS, size, TeamSim.load_rules(TeamSim.DEATHMATCH_PATH))
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _idle(t: TeamSim, ticks: int) -> void:
	for i in ticks:
		t.step(PackedInt32Array())


func _knock_out(t: TeamSim, slot: int) -> void:
	var c := t.sim.creatures[slot]
	c.hp = 0.0
	c._set_state(CreatureSim.State.KO)


func test_the_rules_load_and_a_normal_team_battle_is_unchanged() -> void:
	var t := _tdm()
	assert_true(t.deathmatch, "deathmatch rules")
	assert_eq(t.score_to_win(), 12, "2v2 plays to 12:")
	assert_eq(_tdm(3).score_to_win(), 15, "3v3 to 15:")
	var plain := TeamSim.new(TEAMS, 2)
	assert_false(plain.deathmatch, "the ordinary team battle has one life each")


func test_a_ko_scores_for_the_other_team_and_respawns_on_its_pad() -> void:
	var t := _tdm()
	var c := t.sim.creatures[0]  # left team
	c.energy = 70.0
	_knock_out(t, 0)
	_idle(t, 1)
	assert_eq(t.score, [0, 1], "a point for the right team:")
	var wait := int(t.respawn_t[0])
	assert_eq(wait, int(t.rules["respawn_seconds"]) * 60, "back in about four seconds:")
	_idle(t, wait - 2)
	assert_eq(c.state, CreatureSim.State.KO, "still down just before:")
	_idle(t, 4)
	assert_true(c.state != CreatureSim.State.KO, "back up")
	assert_near(c.hp, c.max_hp, 0.001, "at full health:")
	assert_near(c.energy, 70.0, 0.001, "keeping its Surge energy:")
	var fl := SimDefs.floor_rect()
	assert_lt(c.pos.x, fl.position.x + 80.0, "on the left team's pad, against its own wall:")
	assert_gt(float(c.invuln), 60.0, "and invulnerable for a moment:")
	assert_eq(t.score, [0, 1], "coming back doesn't score:")


func test_the_right_team_respawns_on_the_right() -> void:
	var t := _tdm()
	var c := t.sim.creatures[2]  # first of the right team
	_knock_out(t, 2)
	_idle(t, 4 * 60 + 2)
	assert_gt(c.pos.x, SimDefs.floor_rect().end.x - 80.0, "against the right wall:")
	assert_eq(c.facing, Vector2.LEFT, "facing into the arena:")


func test_spawn_protection_ends_when_you_attack() -> void:
	var t := _tdm()
	var c := t.sim.creatures[0]
	_knock_out(t, 0)
	_idle(t, 4 * 60 + 2)
	assert_gt(float(c.invuln), 0.0, "protected after respawning")
	var ins := PackedInt32Array()
	ins.resize(t.slot_count())
	ins[0] = SimDefs.IN_LIGHT
	t.step(ins)
	_idle(t, 1)
	assert_eq(c.invuln, 0, "an attack ends the protection:")


func test_first_to_the_target_wins() -> void:
	var t := _tdm()
	t.score = [0, t.score_to_win() - 1]
	_knock_out(t, 1)
	_idle(t, 1)
	assert_eq(t.phase, TeamSim.Phase.OVER, "the match ends on the winning KO:")
	assert_eq(t.winner, 1, "the right team wins:")


func test_time_out_goes_to_the_higher_score() -> void:
	var t := _tdm()
	t.score = [3, 2]
	t.timer = 1
	_idle(t, 2)
	assert_eq(t.phase, TeamSim.Phase.OVER, "time:")
	assert_eq(t.winner, 0, "the left team led:")


func test_a_tie_at_time_is_sudden_death() -> void:
	var t := _tdm()
	t.score = [4, 4]
	t.timer = 1
	_idle(t, 3)
	assert_true(t.overtime, "sudden death")
	assert_eq(t.phase, TeamSim.Phase.FIGHT, "the fight goes on:")
	_knock_out(t, 3)
	_idle(t, 1)
	assert_eq(t.phase, TeamSim.Phase.OVER, "the next KO ends it:")
	assert_eq(t.winner, 0, "and wins it for the team that scored:")


func test_it_rolls_back_exactly() -> void:
	var t := _tdm()
	_knock_out(t, 0)
	_idle(t, 30)
	var snap := t.snapshot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var inputs: Array = []
	for i in 300:
		var ins := PackedInt32Array()
		ins.resize(t.slot_count())
		for k in t.slot_count():
			ins[k] = rng.randi() & (SimDefs.IN_ALL & ~SimDefs.IN_TAG)
		inputs.append(ins)
	for ins in inputs:
		t.step(ins)
	var first := t.state_digest()
	var first_score: Array = t.score.duplicate()
	t.restore(snap)
	assert_eq(int(t.respawn_t[0]) > 0, true, "restored to waiting for the respawn")
	for ins in inputs:
		t.step(ins)
	assert_eq(t.state_digest(), first, "the same 300 frames replay to the same state")
	assert_eq(t.score, first_score, "and the same score:")


func test_the_menus_offer_it_with_pads_on_each_side() -> void:
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = "user://test_settings_tdm.cfg"
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	var found := false
	for row in g.MENU_ROWS:
		if String(row["label"]).begins_with("Team Deathmatch"):
			found = true
	assert_true(found, "Single player lists Team Deathmatch")
	g._start_match(32)  # Team Deathmatch 3v3 vs CPU
	g._on_teams_chosen(TEAMS.duplicate(true))
	assert_true(g.team_battle != null and g.team_battle.deathmatch, "a deathmatch starts")
	assert_eq(g.fx.pads.size(), 6, "a pad for every fighter:")
	var left := 0
	for pd in g.fx.pads:
		if Vector2(pd["pos"]).x < SimDefs.floor_rect().get_center().x:
			left += 1
	assert_eq(left, 3, "three on each side:")
	g.free()
