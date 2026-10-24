extends TestCase
## Team intent (TeamIntent, piece 3 of docs/plans/ai-utility-and-teamplay.md): a CPU team
## shares one focus target, built once a tick before the CPUs think, kept until a rival
## clearly outscores it or nobody has seen it for a while; a CPU plays to it only with a
## living teammate, its class can outvote it, and the foe in its face comes first. The
## threads and the one-by-one path choose exactly the same inputs.

const RAGE := CpuController.RAGE


## A bare match: `spec` is [[id, team, pos], ...]; everyone faces right.
func _match(spec: Array) -> MatchSim:
	var m := MatchSim.new()
	for s in spec:
		var c := m.add_creature(MatchFactory.load_def(String(s[0])), s[2])
		c.team = int(s[1])
		c.facing = Vector2.RIGHT
	return m


## A 2v2 with the foes at different distances: the near one is the natural focus.
func _two_v_two() -> MatchSim:
	return _match([["craglash", 0, Vector2(200, 180)], ["crease", 0, Vector2(160, 220)],
		["culvert", 1, Vector2(260, 180)], ["cerebro", 1, Vector2(420, 260)]])


func test_the_nearer_foe_is_the_focus_and_scores_are_per_foe() -> void:
	TeamIntent.reset()
	var m := _two_v_two()
	var ti := TeamIntent.of(m, 0)
	assert_eq(ti.focus, 2, "the near foe is the focus:")
	assert_eq(ti.scores.size(), 2, "both living foes scored:")
	assert_gt(float(ti.scores[2]), float(ti.scores[3]), "the near one scores more")
	var theirs := TeamIntent.of(m, 1)
	assert_eq(theirs.focus, 0, "the other team focuses its near foe:")
	assert_eq(TeamIntent.of(m, 0), ti, "the same tick gives the same object")
	assert_eq(TeamIntent.current(m, 0), ti, "current never builds, it reads:")


func test_a_knocked_out_foe_is_never_the_focus() -> void:
	TeamIntent.reset()
	var m := _two_v_two()
	m.creatures[2].state = CreatureSim.State.KO
	assert_eq(TeamIntent.of(m, 0).focus, 3, "the one still standing:")
	m.creatures[3].state = CreatureSim.State.KO
	m.tick += 1
	assert_eq(TeamIntent.of(m, 0).focus, -1, "nobody left: no focus:")


func test_the_focus_holds_until_a_rival_clearly_outscores_it() -> void:
	TeamIntent.reset()
	var m := _two_v_two()
	assert_eq(TeamIntent.of(m, 0).focus, 2, "")
	# Bring the far foe in so it scores a little more than the focus, but under the margin.
	var far := m.creatures[3]
	var x := 420.0
	while x > 200.0:
		far.pos = Vector2(x, 180)
		for k in 40:  # the running score takes a few ticks to follow a move
			m.tick += 1
			var ti := TeamIntent.of(m, 0)
			var rival := float(ti.scores[3])
			if ti.focus == 3:
				assert_gt(rival, float(ti.scores[2]) * TeamIntent.SWITCH_MARGIN - 0.001, "it switched only past the margin")
				assert_lt(x, 300.0, "and only once the rival was well inside")
				return
			assert_eq(ti.focus, 2, "under the margin it holds:")
			assert_true(rival <= ti.focus_score * TeamIntent.SWITCH_MARGIN + 0.001,
				"held because the rival (%.2f) is under the margin on %.2f" % [rival, ti.focus_score])
		x -= 10.0
	fail("the rival never got close enough to test the switch")


func test_the_votes_of_members_already_on_a_foe_count() -> void:
	TeamIntent.reset()
	var m := _two_v_two()
	var ti := TeamIntent.of(m, 0)
	var before := float(ti.scores[3])
	ti.note(0, 3, 0b1100)
	ti.note(1, 3, 0b1100)
	m.tick += 1
	var next := TeamIntent.of(m, 0)
	# Nothing moved, so the raw score is `before` plus the two votes, run in by SMOOTH.
	assert_near(float(next.scores[3]), before + TeamIntent.SMOOTH * 2 * TeamIntent.VOTE, 0.001, "two votes added:")
	# A target forced on a member (a foe in its face) is not its vote.
	next.note(0, 3, 0b1100, -1)
	next.note(1, 3, 0b1100, -1)
	m.tick += 1
	var third := TeamIntent.of(m, 0)
	assert_lt(float(third.scores[3]), float(next.scores[3]) + 0.001, "no votes: the score falls back")


func test_a_focus_nobody_sees_is_let_go_after_a_while() -> void:
	TeamIntent.reset()
	var m := _two_v_two()
	var ti := TeamIntent.of(m, 0)
	assert_eq(ti.focus, 2, "")
	# From now on the members report they see only the far foe.
	var seen_score := float(ti.scores[2])
	for k in TeamIntent.UNSEEN_TICKS + 2:
		ti.note(0, 2, 0b1000)
		ti.note(1, 2, 0b1000)
		m.tick += 1
		ti = TeamIntent.of(m, 0)
		if k < TeamIntent.UNSEEN_TICKS - 2:
			assert_eq(ti.focus, 2, "tick %d: a focus that just slipped out of sight is kept:" % k)
			assert_lt(float(ti.scores[2]), seen_score, "though its score drains unseen")
			seen_score = float(ti.scores[2])
	assert_eq(ti.focus, 3, "after UNSEEN_TICKS it moves to the foe in sight:")


func test_a_rebuild_of_the_same_tick_gives_the_same_focus() -> void:
	TeamIntent.reset()
	var m := _two_v_two()
	TeamIntent.build_all(m)
	m.tick += 1
	TeamIntent.build_all(m)
	var a := TeamIntent.current(m, 0)
	TeamIntent.build_all(m)  # the game re-thinks a tick after a training option
	var b := TeamIntent.current(m, 0)
	assert_eq(a.focus, b.focus, "same focus:")
	assert_eq(a.focus_t, b.focus_t, "same hold:")


func test_a_cpu_with_a_teammate_takes_the_focus_but_alone_picks_for_itself() -> void:
	TeamIntent.reset()
	# Crease (a mage, "nearest") stands nearer Cerebro (outside his kite band) than the
	# team's focus Culvert.
	var m := _match([["craglash", 0, Vector2(200, 180)], ["crease", 0, Vector2(300, 300)],
		["culvert", 1, Vector2(240, 180)], ["cerebro", 1, Vector2(330, 420)]])
	var crease := CpuController.new(1, RAGE, 4)
	crease.bits(m)
	assert_eq(TeamIntent.current(m, 0).focus, 2, "the team's focus is Culvert:")
	assert_eq(crease._target, m.creatures[2], "Crease plays to it:")
	var alone := CpuController.new(1, RAGE, 4)
	alone.intent = false
	alone.bits(m)
	assert_eq(alone._target, m.creatures[3], "with intent off it takes its nearest:")
	m.creatures[0].state = CreatureSim.State.KO
	m.tick += 1
	var last := CpuController.new(1, RAGE, 4)
	last.bits(m)
	assert_eq(last._target, m.creatures[3], "the last one standing picks for itself:")


func test_the_foe_in_my_face_comes_before_the_focus() -> void:
	TeamIntent.reset()
	var m := _match([["craglash", 0, Vector2(230, 180)], ["crease", 0, Vector2(300, 300)],
		["culvert", 1, Vector2(250, 180)], ["cerebro", 1, Vector2(318, 300)]])
	m.creatures[2].hp = m.creatures[2].max_hp * 0.5  # the hurt one the team is on
	var crease := CpuController.new(1, RAGE, 4)
	crease.bits(m)
	assert_eq(TeamIntent.current(m, 0).focus, 2, "the focus is Culvert:")
	assert_eq(crease._target, m.creatures[3], "but Cerebro is in reach, so Cerebro it is:")


func test_an_assassin_still_takes_a_much_weaker_foe() -> void:
	TeamIntent.reset()
	var m := _match([["craglash", 0, Vector2(200, 180)], ["pete", 0, Vector2(220, 260)],
		["culvert", 1, Vector2(250, 180)], ["cerebro", 1, Vector2(330, 300)]])
	m.creatures[3].hp = m.creatures[3].max_hp * 0.2
	var pete := CpuController.new(1, RAGE, 4)
	pete.bits(m)
	var focus := TeamIntent.current(m, 0).focus
	if focus == 3:
		assert_eq(pete._target, m.creatures[3], "the weak one is the focus too:")
		return
	assert_eq(pete._target, m.creatures[3], "the assassin outvotes the focus for a foe at 20%:")


func test_members_note_their_target_and_what_they_saw() -> void:
	TeamIntent.reset()
	var t := TeamSim.new([["craglash", "crease", "pete"], ["culvert", "cerebro", "digby"]], 3)
	var cpus: Array = []
	for i in 6:
		cpus.append(CpuController.new(i, RAGE, 40 + i))
	for tick in 120:
		var ins := PackedInt32Array()
		for i in 6:
			ins.append((cpus[i] as CpuController).bits(t.sim))
		if tick == 119:
			for team in 2:
				var ti := TeamIntent.current(t.sim, team)
				assert_true(ti != null, "team %d has an intent this tick" % team)
				assert_true(ti.focus >= 0 and t.sim.creatures[ti.focus].team != team, "team %d focuses a foe" % team)
				for i in 6:
					if t.sim.creatures[i].team == team:
						assert_true(ti.member_target[i] >= 0, "member %d noted a target" % i)
						assert_true(ti.member_saw[i] != 0, "member %d noted what it saw" % i)
		t.step(ins)


func test_cpus_on_threads_and_one_by_one_agree_with_a_team_focus() -> void:
	TeamIntent.reset()
	var was := CpuController.threaded
	var a := _team_inputs(true)
	var b := _team_inputs(false)
	CpuController.threaded = was
	assert_eq(a.size(), b.size(), "same length:")
	assert_true(a == b, "threaded and sequential inputs match")


func _team_inputs(threaded: bool) -> PackedInt32Array:
	TeamIntent.reset()
	CpuController.threaded = threaded
	var t := TeamSim.new([["craglash", "crease", "pete"], ["culvert", "cerebro", "digby"]], 3)
	var cpus := []
	for i in t.slot_count():
		cpus.append(CpuController.new(i, RAGE, 70 + i))
	var out := PackedInt32Array()
	for tick in 900:
		CpuController.think_all(cpus, t.sim)
		var ins := PackedInt32Array()
		for c in cpus:
			ins.append((c as CpuController).last_bits)
		out.append_array(ins)
		t.step(ins)
	return out
