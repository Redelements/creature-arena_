extends TestCase
## Caravan: a caravan on the map's track that attackers push, defenders stop or roll back,
## checkpoints that add time and hold it, two rounds with the sides swapped, a second
## round that stops once decided, the winner by time or distance, rollback, and CPU teams
## that escort it.

const TEAMS := [["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]]


func _caravan(size := 1, over := {}) -> TeamSim:
	var r := TeamSim.load_rules(TeamSim.CARAVAN_PATH)
	for k in over:
		r[k] = over[k]
	var t := TeamSim.new(TEAMS, size, r)
	_to_fight(t)
	return t


func _to_fight(t: TeamSim) -> void:
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())


func _idle(t: TeamSim, ticks: int) -> void:
	for i in ticks:
		t.step(PackedInt32Array())
		for c in t.sim.creatures:
			c.walk_vel = Vector2.ZERO


## `ticks` ticks with the creatures in `with` walking along at the caravan.
func _escort(t: TeamSim, with: Array, ticks: int) -> void:
	for i in ticks:
		for c in with:
			(c as CreatureSim).pos = t.caravan_pos()
		_idle(t, 1)


## Puts creature `c` right at the caravan, or far from it.
func _at(t: TeamSim, c: CreatureSim) -> void:
	c.pos = t.caravan_pos()


func _away(t: TeamSim, c: CreatureSim) -> void:
	c.pos = t.sim.terrain.nearest_solid(t.caravan_pos() + Vector2(0.0, 120.0 if t.caravan_pos().y < 220.0 else -120.0))


func test_the_caravan_starts_at_the_attackers_end_of_a_long_track() -> void:
	var t := _caravan()
	assert_true(t.caravan, "caravan rules")
	assert_eq(t.sim.arena_id, "caravan_pass", "its own map:")
	assert_gt(t.track_length(), 1500.0, "a long track:")
	assert_lt(t.caravan_pos().distance_to(t.sim.spawn(0)), 60.0, "round 1: at red's end")
	assert_eq(t.cv_attacker(), 0, "red attacks first")


func test_attackers_push_contested_stops_defenders_roll_it_back() -> void:
	var t := _caravan(1)
	var att := t.sim.creatures[0]
	var dfn := t.sim.creatures[1]
	_away(t, dfn)
	_escort(t, [att], 300)
	var pushed := t.cv_p
	assert_gt(pushed, 60.0, "one attacker alone pushes it (%.0f px):" % pushed)
	assert_eq(t.cv_state, 1, "pushing")
	_at(t, att)
	_at(t, dfn)
	_idle(t, 120)
	assert_lt(absf(t.cv_p - pushed), 0.01, "both sides there: it stops")
	assert_eq(t.cv_state, 2, "contested")
	_away(t, att)
	_at(t, dfn)
	_idle(t, 120)
	assert_lt(t.cv_p, pushed - 5.0, "defenders alone roll it back:")
	assert_eq(t.cv_state, -1, "rolling back")
	assert_gt(t.cv_p, pushed - 0.1 * 120 - 1.0, "slowly")


func test_more_attackers_push_faster() -> void:
	var one := _caravan(3)
	for k in range(1, 6):
		_away(one, one.sim.creatures[k])
	_escort(one, [one.sim.creatures[0]], 200)
	var three := _caravan(3)
	for k in range(3, 6):
		_away(three, three.sim.creatures[k])
	_escort(three, [three.sim.creatures[0], three.sim.creatures[1], three.sim.creatures[2]], 200)
	assert_gt(three.cv_p, one.cv_p * 1.25, "three push faster than one (%.0f vs %.0f):" % [three.cv_p, one.cv_p])


func test_a_checkpoint_adds_time_holds_the_caravan_and_moves_the_respawn() -> void:
	var t := _caravan(1)
	var att := t.sim.creatures[0]
	var dfn := t.sim.creatures[1]
	_away(t, dfn)
	t.cv_p = t.checkpoint_at(0) - 1.0
	var before := t.timer
	_at(t, att)
	_idle(t, 20)
	assert_eq(t.cv_cp, 1, "passed the first checkpoint")
	assert_gt(t.timer, before + 25 * SimDefs.TICK_RATE, "it adds time:")
	_away(t, att)
	_at(t, dfn)
	_idle(t, 600)
	assert_gt(t.cv_p, t.checkpoint_at(0) - 0.01, "it never rolls back past a checkpoint")
	var spawn := t.pad_point(0, 0)
	assert_lt(spawn.distance_to(t.caravan_pos()), 160.0, "the attackers now respawn up at the checkpoint:")


func test_a_finished_push_starts_round_two_with_the_sides_swapped() -> void:
	var t := _caravan(1)
	var att := t.sim.creatures[0]
	_away(t, t.sim.creatures[1])
	t.cv_p = t.track_length() - 2.0
	_at(t, att)
	_idle(t, 30)
	assert_gt(int(t.cv_time[0]), 0, "red's push is timed")
	assert_eq(t.cv_round, 1, "round two")
	assert_eq(t.cv_attacker(), 1, "blue attacks")
	assert_eq(t.phase, TeamSim.Phase.INTRO, "after a countdown")
	assert_lt(t.caravan_pos().distance_to(t.sim.spawn(1)), 60.0, "from blue's end")
	assert_lt(att.pos.distance_to(t.sim.spawn(0)), 80.0, "everyone back at their own end")


func test_round_two_ends_once_it_passes_round_ones_push() -> void:
	var t := _caravan(1)
	t.cv_best[0] = 300.0
	t.timer = 2
	_away(t, t.sim.creatures[0])
	_away(t, t.sim.creatures[1])
	_idle(t, 5)
	assert_eq(t.cv_round, 1, "time ran out on red: round two")
	_to_fight(t)
	t.cv_p = 299.0
	_away(t, t.sim.creatures[0])
	_at(t, t.sim.creatures[1])
	_idle(t, 30)
	assert_eq(t.phase, TeamSim.Phase.OVER, "past red's push: decided")
	assert_eq(t.winner, 1, "blue wins")


func test_the_faster_finish_wins() -> void:
	var t := _caravan(1)
	t.cv_time[0] = 4000
	t.cv_best[0] = t.track_length()
	t.cv_round = 1
	t.cv_t = 3999
	_away(t, t.sim.creatures[0])
	_away(t, t.sim.creatures[1])
	_idle(t, 3)
	assert_eq(t.phase, TeamSim.Phase.OVER, "already slower than red's finish: decided")
	assert_eq(t.winner, 0, "red's faster finish wins")


func test_overtime_while_an_attacker_is_on_it() -> void:
	var t := _caravan(1)
	t.timer = 1
	_at(t, t.sim.creatures[0])
	_at(t, t.sim.creatures[1])
	_idle(t, 120)
	assert_eq(t.cv_round, 0, "still round one in overtime")
	assert_gt(t.cv_ot, 100, "counting overtime")
	assert_eq(t.goal_text(), "OVERTIME", "says so")


func test_it_all_rolls_back() -> void:
	var t := _caravan(2)
	_at(t, t.sim.creatures[0])
	var snap := t.snapshot()
	var d := t.state_digest()
	_idle(t, 200)
	var after := t.state_digest()
	t.restore(snap)
	assert_eq(t.state_digest(), d, "restored")
	_idle(t, 200)
	assert_eq(t.state_digest(), after, "and replays the same")


func test_cpu_teams_escort_and_contest_the_caravan() -> void:
	var t := TeamSim.new(TEAMS, 3, TeamSim.load_rules(TeamSim.CARAVAN_PATH))
	var cpus: Array = []
	for i in t.slot_count():
		cpus.append(CpuController.new(i, 2, 70 + i))
	var contested := 0
	for tick in 9000:
		var ins := PackedInt32Array()
		for i in t.slot_count():
			ins.append((cpus[i] as CpuController).bits(t.sim))
		t.step(ins)
		if t.cv_state == 2:
			contested += 1
		if t.cv_round == 1 or t.phase == TeamSim.Phase.OVER:
			break
	assert_gt(float(t.cv_best[0]), 200.0, "the CPU attackers pushed it (%.0f px)" % float(t.cv_best[0]))
	assert_gt(float(contested), 60.0, "and the CPU defenders came to stop it (%d ticks contested)" % contested)
