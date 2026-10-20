extends TestCase
## Capture the Flag: flags on each base, taking the other side's, the carrier slowed and
## dropping it when knocked out, returns (touched or timed), captures only with your own
## flag home, first to the target, sudden death, 4 a side, rollback, and CPU teams that
## defend, attack and capture.

const TEAMS := [["cairn", "sno", "pete", "craglash"], ["culvert", "digby", "hissy", "barkley"]]


func _ctf(size := 1, over := {}) -> TeamSim:
	var r := TeamSim.load_rules(TeamSim.CTF_PATH)
	for k in over:
		r[k] = over[k]
	var t := TeamSim.new(TEAMS, size, r)
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _idle(t: TeamSim, ticks: int) -> void:
	for i in ticks:
		t.step(PackedInt32Array())
		for c in t.sim.creatures:
			c.walk_vel = Vector2.ZERO


func _mid(t: TeamSim) -> Vector2:
	return t.sim.terrain.nearest_solid(t.sim.floor_rect().get_center())


func test_a_big_map_with_a_flag_on_each_base() -> void:
	var t := _ctf()
	assert_true(t.ctf, "ctf rules")
	assert_eq(t.sim.arena_id, "twin_keeps", "its own map:")
	var fr := t.sim.floor_rect()
	assert_gt(fr.size.x * fr.size.y, SimDefs.floor_rect().size.x * SimDefs.floor_rect().size.y * 3.0, "over 3x the stadium's floor")
	for side in 2:
		assert_eq(int(t.flag_state[side]), TeamSim.FLAG_HOME, "flag %d home" % side)
		assert_eq(t.flag_pos[side], t.base_of(side), "on its base")


func test_taking_carrying_and_capturing() -> void:
	var t := _ctf(1)
	var red := t.sim.creatures[0]
	var blue := t.sim.creatures[1]
	blue.pos = _mid(t)
	red.pos = t.base_of(1)
	_idle(t, 2)
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_CARRIED, "red took blue's flag")
	assert_eq(int(t.flag_carrier[1]), red.id, "red carries it")
	assert_gt(red.slow, 0, "the carrier is slowed")
	red.pos = t.base_of(0)
	_idle(t, 2)
	assert_eq(int(t.score[0]), 1, "a capture at home:")
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_HOME, "blue's flag went back")


func test_no_capture_while_your_own_flag_is_away() -> void:
	var t := _ctf(1)
	var red := t.sim.creatures[0]
	var blue := t.sim.creatures[1]
	red.pos = t.base_of(1)
	blue.pos = t.base_of(0)
	_idle(t, 2)
	assert_eq(int(t.flag_state[0]), TeamSim.FLAG_CARRIED, "blue has red's flag")
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_CARRIED, "red has blue's flag")
	red.pos = t.base_of(0)
	blue.pos = _mid(t)
	_idle(t, 10)
	assert_eq(int(t.score[0]), 0, "red can't score while its own flag is out")


func test_a_knocked_out_carrier_drops_it_and_it_goes_home() -> void:
	var t := _ctf(1)
	var red := t.sim.creatures[0]
	var blue := t.sim.creatures[1]
	blue.pos = _mid(t) + Vector2(0, 80)
	red.pos = t.base_of(1)
	_idle(t, 2)
	red.pos = _mid(t)
	red.hp = 0.0
	red.state = CreatureSim.State.KO
	_idle(t, 2)
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_DROPPED, "dropped where red went down")
	assert_lt(Vector2(t.flag_pos[1]).distance_to(_mid(t)), 12.0, "right there:")
	blue.pos = t.flag_pos[1]
	_idle(t, 2)
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_HOME, "blue touched it: home")
	# left alone, a dropped flag goes home by itself
	var t2 := _ctf(1)
	var r2 := t2.sim.creatures[0]
	t2.sim.creatures[1].pos = _mid(t2) + Vector2(0, 80)
	r2.pos = t2.base_of(1)
	_idle(t2, 2)
	r2.pos = _mid(t2)
	r2.hp = 0.0
	r2.state = CreatureSim.State.KO
	_idle(t2, 2)
	t2.sim.creatures[1].pos = t2.base_of(1)
	_idle(t2, int(float(t2.rules["return_seconds"]) * 60.0) + 2)
	assert_eq(int(t2.flag_state[1]), TeamSim.FLAG_HOME, "after return_seconds it's home again")


func test_first_to_three_and_sudden_death() -> void:
	var t := _ctf(1)
	t.score[0] = 2
	var red := t.sim.creatures[0]
	t.sim.creatures[1].pos = _mid(t)
	red.pos = t.base_of(1)
	_idle(t, 2)
	red.pos = t.base_of(0)
	_idle(t, 2)
	assert_eq(t.phase, TeamSim.Phase.OVER, "the third capture wins")
	assert_eq(t.winner, 0, "red")
	var t2 := _ctf(1)
	t2.score = [1, 1]
	t2.timer = 1
	t2.sim.creatures[0].pos = _mid(t2)
	t2.sim.creatures[1].pos = _mid(t2) + Vector2(0, 60)
	_idle(t2, 3)
	assert_true(t2.overtime, "a tie at time: sudden death")
	assert_eq(t2.phase, TeamSim.Phase.FIGHT, "still playing")


func test_four_a_side() -> void:
	var t := _ctf(4)
	assert_eq(t.size, 4, "4 v 4:")
	assert_eq(t.slot_count(), 8, "eight fighters")
	for c in t.sim.creatures:
		assert_true(t.sim.floor_rect().has_point(c.pos), "everyone starts on the floor")


func test_it_all_rolls_back() -> void:
	var t := _ctf(2)
	t.sim.creatures[0].pos = t.base_of(1)
	var snap := t.snapshot()
	var d := t.state_digest()
	_idle(t, 200)
	var after := t.state_digest()
	t.restore(snap)
	assert_eq(t.state_digest(), d, "restored")
	_idle(t, 200)
	assert_eq(t.state_digest(), after, "and replays the same")


func test_cpu_teams_take_flags_and_capture() -> void:
	var t := TeamSim.new(TEAMS, 3, TeamSim.load_rules(TeamSim.CTF_PATH))
	var cpus: Array = []
	for i in t.slot_count():
		cpus.append(CpuController.new(i, 2, 90 + i))
	var takes := 0
	var defended := 0
	for tick in 14000:
		var ins := PackedInt32Array()
		for i in t.slot_count():
			ins.append((cpus[i] as CpuController).bits(t.sim))
		t.step(ins)
		for e in t.sim.events:
			if e["type"] == "flag_take":
				takes += 1
		if tick % 60 == 0:
			for side in 2:
				for c in t.members(side):
					if (c as CreatureSim).pos.distance_to(t.base_of(side)) < 90.0:
						defended += 1
						break
		if t.phase == TeamSim.Phase.OVER or int(t.score[0]) + int(t.score[1]) > 0:
			break
	assert_gt(float(takes), 0.0, "the CPUs went and took a flag (%d takes)" % takes)
	assert_gt(float(defended), 20.0, "and someone stayed home to guard (%d checks)" % defended)
	assert_gt(float(t.score[0]) + float(t.score[1]), 0.0, "and someone captured one")
