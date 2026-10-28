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


func _team_inputs(threaded: bool, ids := [["craglash", "crease", "pete"], ["culvert", "cerebro", "digby"]]) -> PackedInt32Array:
	TeamIntent.reset()
	CpuController.threaded = threaded
	var t := TeamSim.new(ids, 3)
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


# --- Engage state, front line, peel, isolated (the rest of piece 3) ---------------------

func test_the_engage_state_counts_the_members_votes() -> void:
	assert_eq(TeamIntent.engage_of(0, 0), TeamIntent.POKE, "nobody committing: poke:")
	assert_eq(TeamIntent.engage_of(1, 0), TeamIntent.POKE, "one alone doesn't commit the team:")
	assert_eq(TeamIntent.engage_of(2, 0), TeamIntent.COMMIT, "two commit:")
	assert_eq(TeamIntent.engage_of(0, 2), TeamIntent.RETREAT, "two retreat:")
	assert_eq(TeamIntent.engage_of(2, 2), TeamIntent.COMMIT, "a tie goes to the fight:")
	assert_eq(TeamIntent.engage_of(2, 3), TeamIntent.RETREAT, "more backing off than going in:")
	assert_eq(TeamIntent.engage_of(1, 1), TeamIntent.POKE, "one each way: poke:")


func test_the_engage_state_follows_last_ticks_notes_of_the_living() -> void:
	TeamIntent.reset()
	var m := _two_v_two()
	var ti := TeamIntent.of(m, 0)
	assert_eq(ti.engage, TeamIntent.POKE, "before any note: poke:")
	ti.note_engage(0, TeamIntent.COMMIT)
	ti.note_engage(1, TeamIntent.COMMIT)
	m.tick += 1
	ti = TeamIntent.of(m, 0)
	assert_eq(ti.engage, TeamIntent.COMMIT, "both committed last tick:")
	assert_eq(ti.member_engage[0], -1, "this tick's notes start empty:")
	ti.note_engage(0, TeamIntent.RETREAT)
	ti.note_engage(1, TeamIntent.RETREAT)
	m.tick += 1
	ti = TeamIntent.of(m, 0)
	assert_eq(ti.engage, TeamIntent.RETREAT, "both backed off:")
	ti.note_engage(0, TeamIntent.RETREAT)
	ti.note_engage(1, TeamIntent.RETREAT)
	m.creatures[1].state = CreatureSim.State.KO
	m.tick += 1
	assert_eq(TeamIntent.of(m, 0).engage, TeamIntent.POKE, "a knocked-out member's note doesn't count:")
	assert_eq(TeamIntent.of(m, 1).engage, TeamIntent.POKE, "and the other team's notes are its own:")


func test_the_front_line_stands_at_the_tank_facing_the_focus() -> void:
	TeamIntent.reset()
	var m := _two_v_two()
	var ti := TeamIntent.of(m, 0)
	assert_eq(ti.focus, 2, "")
	assert_eq(ti.front_slot, 0, "Craglash, the tank, makes the line:")
	assert_eq(ti.front, m.creatures[0].pos, "at the tank:")
	assert_near(ti.front_dir.dot((m.creatures[2].pos - m.creatures[0].pos).normalized()), 1.0, 0.001,
		"facing the focus:")
	# No tank: the nearest melee that holds ground (a bruiser, a fighter); never a mage or an
	# assassin.
	TeamIntent.reset()
	var b := _match([["crease", 0, Vector2(150, 200)], ["pete", 0, Vector2(250, 180)],
		["sno", 0, Vector2(200, 260)], ["culvert", 1, Vector2(300, 180)]])
	ti = TeamIntent.of(b, 0)
	assert_eq(ti.front_slot, 2, "Sno, the bruiser, makes it:")
	TeamIntent.reset()
	var none := _match([["crease", 0, Vector2(150, 200)], ["pete", 0, Vector2(250, 180)],
		["culvert", 1, Vector2(300, 180)]])
	ti = TeamIntent.of(none, 0)
	assert_eq(ti.front_slot, -1, "a mage and an assassin make no line:")
	assert_eq(ti.front, Vector2.INF, "no line point:")
	# The tank down, a mage alone makes none.
	m.creatures[0].state = CreatureSim.State.KO
	m.tick += 1
	assert_eq(TeamIntent.of(m, 0).front_slot, -1, "Crease alone makes none:")


func test_a_mage_falls_back_behind_the_line_only_while_its_team_retreats() -> void:
	TeamIntent.reset()
	# Crease stands level with Craglash (the line), both on the focus Culvert ahead.
	var m := _match([["craglash", 0, Vector2(200, 180)], ["crease", 0, Vector2(200, 240)],
		["culvert", 1, Vector2(250, 190)], ["cerebro", 1, Vector2(520, 300)]])
	var crease := CpuController.new(1, RAGE, 4)
	crease.bits(m)
	var foe := m.creatures[2]
	assert_eq(crease._target, foe, "on the focus:")
	var keep := CpuController.kite_band(m.creatures[1], foe).y
	assert_eq(crease._line_pull(m, m.creatures[1], foe, keep), Vector2.ZERO, "poking: no pull:")
	crease._team.engage = TeamIntent.RETREAT
	var pull := crease._line_pull(m, m.creatures[1], foe, keep)
	assert_lt(pull.dot(crease._team.front_dir), -0.5, "retreating: back behind the line:")
	# Already far enough behind it: no pull.
	m.creatures[1].pos = Vector2(100, 240)
	assert_eq(crease._line_pull(m, m.creatures[1], foe, keep), Vector2.ZERO, "already behind it:")
	# The tank itself is never pulled behind its own line.
	var crag := CpuController.new(0, RAGE, 5)
	crag._team = crease._team
	crag._target = foe
	assert_eq(crag._line_pull(m, m.creatures[0], foe, 200.0), Vector2.ZERO, "the line's own maker:")


func test_rage_cpus_note_their_engage_state_in_a_match() -> void:
	TeamIntent.reset()
	var t := TeamSim.new([["craglash", "crease", "pete"], ["culvert", "cerebro", "digby"]], 3)
	var cpus: Array = []
	for i in 6:
		cpus.append(CpuController.new(i, RAGE, 40 + i))
	var seen := {}
	for tick in 900:
		var ins := PackedInt32Array()
		for i in 6:
			ins.append((cpus[i] as CpuController).bits(t.sim))
		for team in 2:
			var ti := TeamIntent.current(t.sim, team)
			seen[ti.engage] = true
			for i in 6:
				if t.sim.creatures[i].team == team and t.sim.creatures[i].state != CreatureSim.State.KO:
					assert_true(ti.member_engage[i] >= 0, "tick %d: member %d noted its state" % [tick, i])
		t.step(ins)
	assert_true(seen.has(TeamIntent.POKE) and seen.has(TeamIntent.COMMIT), "teams poke and commit: %s" % [seen])
	# Below Rage nobody notes one: the engage state stays poke.
	TeamIntent.reset()
	var n := TeamSim.new([["craglash", "crease", "pete"], ["culvert", "cerebro", "digby"]], 3)
	var normal: Array = []
	for i in 6:
		normal.append(CpuController.new(i, 1, 40 + i))
	for tick in 300:
		var ins := PackedInt32Array()
		for i in 6:
			ins.append((normal[i] as CpuController).bits(n.sim))
		assert_eq(TeamIntent.current(n.sim, 0).engage, TeamIntent.POKE, "Normal: no engage notes:")
		n.step(ins)


func test_f_peel_at_none_half_and_full() -> void:
	var m := _match([["crease", 0, Vector2(200, 200)], ["pete", 1, Vector2(200, 200)],
		["craglash", 0, Vector2(200, 300)]])
	var mage := m.creatures[0]
	var foe := m.creatures[1]
	var tank := m.creatures[2]
	var reach := CpuController._reach_of(foe, mage)
	mage.hp = mage.max_hp * 0.3
	assert_near(CpuController.f_peel(mage, foe), 1.0, 0.001, "a mage at 30% in the foe's reach: 1:")
	mage.hp = mage.max_hp * 0.9
	assert_near(CpuController.f_peel(mage, foe), 0.0, 0.001, "at 90% health: 0:")
	mage.hp = mage.max_hp * 0.6
	assert_near(CpuController.f_peel(mage, foe), 0.5, 0.001, "at 60%: half:")
	mage.hp = mage.max_hp * 0.3
	foe.pos = mage.pos + Vector2(reach + 32.0, 0)
	assert_near(CpuController.f_peel(mage, foe), 0.5, 0.001, "32 px past its reach: half:")
	foe.pos = mage.pos + Vector2(reach + 64.0, 0)
	assert_near(CpuController.f_peel(mage, foe), 0.0, 0.001, "64 px past it: 0:")
	foe.pos = tank.pos
	tank.hp = tank.max_hp * 0.3
	assert_near(CpuController.f_peel(tank, foe), 0.0, 0.001, "a melee ally fights back: 0:")


func test_f_isolated_at_none_half_and_full() -> void:
	assert_near(CpuController.f_isolated(INF, 80.0), 1.0, 0.001, "no teammate at all: 1:")
	assert_near(CpuController.f_isolated(80.0, 80.0), 1.0, 0.001, "two reaches off: 1:")
	assert_near(CpuController.f_isolated(60.0, 80.0), 0.5, 0.001, "half way: half:")
	assert_near(CpuController.f_isolated(40.0, 80.0), 0.0, 0.001, "within one reach: 0:")
	assert_near(CpuController.f_isolated(10.0, 80.0), 0.0, 0.001, "right next to it: 0:")


func test_with_the_tank_down_anyone_peels_for_a_hurt_ranged_ally() -> void:
	TeamIntent.reset()
	# Craglash (the tank) is down; Digby is on Crease, who is hurt. Sno (a bruiser) is
	# nearer Culvert, the team's focus, but turns on Digby.
	var spec := [["craglash", 0, Vector2(120, 120)], ["crease", 0, Vector2(150, 300)],
		["sno", 0, Vector2(300, 200)], ["culvert", 1, Vector2(380, 200)],
		["digby", 1, Vector2(170, 300)]]
	var m := _match(spec)
	m.creatures[0].state = CreatureSim.State.KO
	m.creatures[1].hp = m.creatures[1].max_hp * 0.3
	m.creatures[3].hp = m.creatures[3].max_hp * 0.5  # (so Culvert is the team's focus)
	var sno := CpuController.new(2, RAGE, 4)
	sno.bits(m)
	assert_true(TeamIntent.current(m, 0).focus == 3 or TeamIntent.current(m, 0).focus == 4, "a focus:")
	assert_eq(sno._target, m.creatures[4], "Sno peels Digby off Crease:")
	# With the tank standing, the tank peels and Sno keeps to the team's plan.
	TeamIntent.reset()
	var m2 := _match(spec)
	m2.creatures[1].hp = m2.creatures[1].max_hp * 0.3
	m2.creatures[3].hp = m2.creatures[3].max_hp * 0.5
	var sno2 := CpuController.new(2, RAGE, 4)
	assert_eq(sno2._peel_target(m2, m2.creatures[2], "nearest"), null, "the tank is up: no peel from Sno:")
	# Intent off: no peel either.
	TeamIntent.reset()
	var m3 := _match(spec)
	m3.creatures[0].state = CreatureSim.State.KO
	m3.creatures[1].hp = m3.creatures[1].max_hp * 0.3
	var alone := CpuController.new(2, RAGE, 4)
	alone.intent = false
	alone.bits(m3)
	assert_eq(alone._target, m3.creatures[3], "intent off: its nearest:")


func test_an_assassin_goes_for_the_foe_standing_alone() -> void:
	TeamIntent.reset()
	# Cerebro stands next to Digby by Craglash (the team's focus is one of them); Crease, a
	# little further from Pete, stands alone. Pete takes the lone one; with intent off, the
	# one his old score liked (the nearer).
	var spec := [["craglash", 0, Vector2(380, 260)], ["pete", 0, Vector2(300, 200)],
		["cerebro", 1, Vector2(400, 220)], ["digby", 1, Vector2(410, 235)],
		["crease", 1, Vector2(300, 60)], ["culvert", 1, Vector2(100, 400)]]
	var m := _match(spec)
	var pete := CpuController.new(1, RAGE, 4)
	var reach := 2.0 * CpuController._reach_of(m.creatures[1], m.creatures[1])
	assert_near(pete._isolation(m, m.creatures[4], reach), 1.0, 0.001, "Crease stands alone:")
	assert_near(pete._isolation(m, m.creatures[2], reach), 0.0, 0.001, "Cerebro has Digby beside him:")
	pete.bits(m)
	var focus := TeamIntent.current(m, 0).focus
	assert_true(focus == 2 or focus == 3, "the team is on the pair by Craglash (focus %d)" % focus)
	assert_eq(pete._target, m.creatures[4], "Pete takes the lone foe:")
	TeamIntent.reset()
	var m2 := _match(spec)
	var off := CpuController.new(1, RAGE, 4)
	off.intent = false
	off.bits(m2)
	assert_eq(off._target, m2.creatures[2], "intent off: his old pick, Cerebro, the nearer:")


func test_threaded_and_sequential_agree_with_peel_and_a_line() -> void:
	# A bruiser, a skirmisher and a mage a side (no tank: the bruiser makes the line and
	# anyone may peel), on the threads and one by one.
	var was := CpuController.threaded
	var ids := [["sno", "gillbert", "crease"], ["barkley", "hissy", "cerebro"]]
	var a := _team_inputs(true, ids)
	var b := _team_inputs(false, ids)
	CpuController.threaded = was
	assert_eq(a.size(), b.size(), "same length:")
	assert_true(a == b, "threaded and sequential inputs match")
