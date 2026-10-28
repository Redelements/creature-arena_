extends TestCase
## The CPU's Caravan plan: the rules give each fighter a job (TeamSim._cv_goals: attackers
## "push" at the caravan, defenders "hold" the road just ahead of it), an attacker with no
## foe near walks to the caravan, a defender to the road ahead of it, an attacker fighting
## a foe outside the push radius doesn't follow it out (`_cv_tether`), a fighter whose
## `ai.caravan` is false plays the caravan as a plain zone, threaded thinking matches
## sequential, and every other mode's CPU inputs are the same with the plan on or off.

const TEAMS := [["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]]


func _caravan(size := 1) -> TeamSim:
	var t := TeamSim.new(TEAMS, size, TeamSim.load_rules(TeamSim.CARAVAN_PATH))
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


## Floor `px` from the caravan, along `dir` (moved to the nearest solid floor).
func _off(t: TeamSim, dir: Vector2, px: float) -> Vector2:
	return t.sim.terrain.nearest_solid(t.caravan_pos() + dir * px)


## Steps the match with only `slot`'s CPU pressing buttons (everyone else stands still),
## calling `each` after every tick.
func _drive(t: TeamSim, cpu: CpuController, slot: int, ticks: int, each := Callable()) -> void:
	for i in ticks:
		var ins := PackedInt32Array()
		ins.resize(t.slot_count())
		ins[slot] = cpu.bits(t.sim)
		t.step(ins)
		if each.is_valid():
			each.call()


func test_the_rules_give_attackers_the_caravan_and_defenders_the_road_ahead() -> void:
	var t := _caravan()
	var att: Array = t.sim.goals[0]
	var def: Array = t.sim.goals[1]
	var r := float(t.rules["radius"])
	assert_eq(String(att[4]), "push", "red attacks in round 1")
	assert_eq(String(def[4]), "hold", "blue defends")
	assert_lt((att[0] as Vector2).distance_to(t.caravan_pos()), 0.01, "the attacker's goal is the caravan")
	assert_lt(float(att[1]), r, "inside the push radius")
	var ahead := (def[0] as Vector2) - t.caravan_pos()
	assert_gt(ahead.dot(t.caravan_heading()), 10.0, "the defender's is ahead of it, on its way")
	assert_lt(ahead.length() + float(def[1]), r + 0.01, "and still inside the radius (it contests the push)")
	assert_true(CpuController._is_caravan_goal(att) and CpuController._is_caravan_goal(def), "tagged as Caravan jobs")


func test_an_attacker_with_no_foe_near_walks_to_the_caravan() -> void:
	var t := _caravan()
	var me := t.sim.creatures[0]
	var foe := t.sim.creatures[1]
	foe.pos = _off(t, t.caravan_heading(), 260.0)  # far up the road
	me.pos = _off(t, Vector2(0.0, 1.0 if t.caravan_pos().y < 300.0 else -1.0), 150.0)
	var cpu := CpuController.new(0, 1, 5)
	_drive(t, cpu, 0, 300)
	assert_lt(me.pos.distance_to(t.caravan_pos()), float(t.rules["radius"]),
		"the attacker came to the caravan (%.0f px off)" % me.pos.distance_to(t.caravan_pos()))
	assert_gt(float(t.cv_p), 1.0, "and pushed it")


func test_a_defender_heads_for_the_road_ahead_of_the_caravan() -> void:
	var t := _caravan()
	var att := t.sim.creatures[0]
	var me := t.sim.creatures[1]
	att.pos = _off(t, -t.caravan_heading(), 220.0)  # far back down the road
	me.pos = _off(t, Vector2(0.0, 1.0 if t.caravan_pos().y < 300.0 else -1.0), 150.0)
	var cpu := CpuController.new(1, 1, 5)
	_drive(t, cpu, 1, 300)
	var off := me.pos - t.caravan_pos()
	assert_lt(off.length(), float(t.rules["radius"]), "the defender came to the caravan (%.0f px off)" % off.length())
	assert_gt(off.dot(t.caravan_heading()), 0.0, "on the road ahead of it")


func test_an_attacker_does_not_follow_a_foe_out_of_the_push_radius() -> void:
	# A foe standing off the caravan: the attacker walks to it as far as the rim and no
	# further (the walk slides along the rim); with the plan off it walks out to fight.
	var inside := [_rim_share(true), _rim_share(false)]
	assert_gt(float(inside[0]), 0.95, "plan on: inside the push radius %.0f%% of the time" % (100.0 * float(inside[0])))
	assert_lt(float(inside[1]), 0.8, "plan off: it walked out to the foe (%.0f%% inside)" % (100.0 * float(inside[1])))


func _rim_share(plan: bool) -> float:
	var t := _caravan()
	var me := t.sim.creatures[0]
	var foe := t.sim.creatures[1]
	me.pos = t.caravan_pos()
	foe.pos = _off(t, Vector2(0.0, 1.0 if t.caravan_pos().y < 300.0 else -1.0), 110.0)
	var cpu := CpuController.new(0, 1, 9)
	cpu.caravan = plan
	var n := [0, 0]
	var r := float(t.rules["radius"])
	_drive(t, cpu, 0, 240, func() -> void:
		foe.pos = _off(t, Vector2(0.0, 1.0 if t.caravan_pos().y < 300.0 else -1.0), 110.0)  # it stays put, off the caravan
		n[1] += 1
		if me.pos.distance_to(t.caravan_pos()) <= r:
			n[0] += 1)
	return float(n[0]) / float(n[1])


func test_ai_caravan_false_plays_the_caravan_as_a_zone() -> void:
	var t := _caravan()
	var me := t.sim.creatures[0]
	var cpu := CpuController.new(0, 1, 5)
	assert_eq(cpu._caravan_job(t.sim, me), "push", "on by default")
	me.def = me.def.duplicate(true)
	(me.def["ai"] as Dictionary)["caravan"] = false
	assert_eq(cpu._caravan_job(t.sim, me), "", "ai.caravan false: no job")
	var off := CpuController.new(0, 1, 5)
	off.caravan = false
	me.def["ai"]["caravan"] = true
	assert_eq(off._caravan_job(t.sim, me), "", "a controller with the plan off: no job")


func test_threaded_caravan_cpus_choose_what_they_do_one_by_one() -> void:
	var was := CpuController.threaded
	var a := _caravan_inputs(true)
	var b := _caravan_inputs(false)
	CpuController.threaded = was
	assert_eq(a.size(), b.size(), "same length:")
	assert_true(a == b, "threaded and sequential Caravan CPU inputs match")


func _caravan_inputs(threaded: bool) -> PackedInt32Array:
	CpuController.threaded = threaded
	var t := TeamSim.new(TEAMS, 3, TeamSim.load_rules(TeamSim.CARAVAN_PATH))
	var cpus := []
	for i in t.slot_count():
		cpus.append(CpuController.new(i, 1, 40 + i))
	var out := PackedInt32Array()
	for tick in 900:
		CpuController.think_all(cpus, t.sim)
		var ins := PackedInt32Array()
		for c in cpus:
			ins.append((c as CpuController).last_bits)
		out.append_array(ins)
		t.step(ins)
	return out


func test_other_modes_play_the_same_with_the_plan_on_or_off() -> void:
	for path in [TeamSim.DEATHMATCH_PATH, TeamSim.CRATER_PATH, TeamSim.CTF_PATH, TeamSim.SINKHOLE_PATH]:
		var on := _mode_inputs(path, true)
		var off := _mode_inputs(path, false)
		assert_true(on == off, "%s: the same CPU inputs with the Caravan plan on or off" % path)


func _mode_inputs(path: String, plan: bool) -> PackedInt32Array:
	var t := TeamSim.new(TEAMS, 3, TeamSim.load_rules(path))
	var cpus := []
	for i in t.slot_count():
		var c := CpuController.new(i, 1, 60 + i)
		c.caravan = plan
		cpus.append(c)
	var out := PackedInt32Array()
	for tick in 600:
		var ins := PackedInt32Array()
		for c in cpus:
			ins.append((c as CpuController).bits(t.sim))
		out.append_array(ins)
		t.step(ins)
	return out
