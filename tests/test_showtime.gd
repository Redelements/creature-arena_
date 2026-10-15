extends TestCase
## Showtime: hype, not damage, decides it. Hits, combos, Surges, counters, knockouts,
## ring-outs and close escapes add to the side that made the moment; first to the
## target or the most at time wins; KOs respawn so the show goes on.

const TEAMS := [["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]]


func _rules() -> Dictionary:
	return TeamSim.load_rules(TeamSim.SHOWTIME_PATH)


func _show(size := 1, rules := {}) -> TeamSim:
	var t := TeamSim.new(TEAMS, size, _rules() if rules.is_empty() else rules)
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _idle(t: TeamSim, ticks: int) -> void:
	for i in ticks:
		t.step(PackedInt32Array())


func _hype_events(t: TeamSim) -> Array:
	return t.sim.events.filter(func(e): return e["type"] == "hype")


func test_the_rules_load_and_a_hit_adds_hype_to_the_hitter() -> void:
	var t := _show()
	assert_true(t.showtime, "showtime rules")
	assert_true(t.deathmatch, "with respawns")
	var a := t.sim.creatures[0]
	var b := t.sim.creatures[1]
	b.pos = a.pos + Vector2(24, 0)
	a.facing = Vector2.RIGHT
	var landed := false
	for i in 40:
		t.step(PackedInt32Array([SimDefs.IN_LIGHT if i % 12 == 0 else 0, 0]))
		for e in t.sim.events:
			if e["type"] == "hit":
				landed = true
	assert_true(landed, "a jab landed")
	assert_gt(float(t.score[0]), 0.0, "the hitter's side has hype")
	assert_eq(int(t.score[1]), 0, "the one hit has none:")


## A jab from `a` finishes `b`, who is left at a sliver of health.
func _finish_with_a_jab(t: TeamSim, a: CreatureSim, b: CreatureSim) -> void:
	b.hp = 1.0
	b.invuln = 0  # fresh off the pad it would still be protected
	b.pos = a.pos + Vector2(24, 0)
	a.facing = Vector2.RIGHT
	for i in 40:
		t.step(PackedInt32Array([SimDefs.IN_LIGHT if i % 12 == 0 else 0, 0]))
		if b.state == CreatureSim.State.KO:
			return


func test_a_knockout_and_a_ring_out_pay_the_other_side() -> void:
	var t := _show()
	var a := t.sim.creatures[0]
	var b := t.sim.creatures[1]
	_finish_with_a_jab(t, a, b)
	assert_eq(b.state, CreatureSim.State.KO, "knocked out:")
	assert_true(int(t.score[0]) >= int(_rules()["hype"]["ko"]), "a KO is worth its hype to the other side (%d)" % int(t.score[0]))
	assert_true(int(t.score[0]) < int(_rules()["hype"]["ko"]) + 20, "and not a deathmatch point on top")
	_idle(t, 2)
	assert_true(int(t.respawn_t[1]) > 0, "and the fallen comes back")
	var u := _show()
	var faller := u.sim.creatures[0]
	faller.pos = u.sim.terrain.cell_center(Vector2i(40, 18))
	u.sim.terrain.set_cell(Vector2i(40, 18), TerrainGrid.HOLE)
	_idle(u, 2)
	assert_eq(faller.state, CreatureSim.State.FALLING, "fell in:")
	assert_eq(int(u.score[1]), int(_rules()["hype"]["fall"]), "a ring-out pays the other side:")


func test_a_breakaway_is_a_close_escape() -> void:
	var t := _show()
	var a := t.sim.creatures[0]
	a._set_state(CreatureSim.State.HITSTUN)
	a.stun = 30
	a.combo_hits = 3
	a.energy = 60.0
	t.step(PackedInt32Array([SimDefs.IN_GUARD | SimDefs.IN_DODGE, 0]))
	assert_eq(int(t.score[0]), int(_rules()["hype"]["breakaway"]), "the escape's hype:")


func test_first_to_the_target_wins_and_the_crowd_hears_about_it() -> void:
	var r := _rules()
	r["hype_to_win"] = 100
	var t := _show(1, r)
	var a := t.sim.creatures[0]
	var b := t.sim.creatures[1]
	_finish_with_a_jab(t, a, b)
	assert_true(_hype_events(t).size() > 0, "a hype event for the views")
	assert_eq(t.phase, TeamSim.Phase.FIGHT, "about 80 of 100: not yet")
	_idle(t, int(r["respawn_seconds"]) * 60 + 20)
	_finish_with_a_jab(t, a, b)
	assert_eq(t.phase, TeamSim.Phase.OVER, "over the target:")
	assert_eq(t.winner, 0, "the showier side wins:")


func test_it_all_rolls_back() -> void:
	var t := _show(2)
	t.sim.creatures[1].hp = 0.0
	t.sim.creatures[1]._set_state(CreatureSim.State.KO)
	_idle(t, 10)
	var s := t.snapshot()
	var d := t.state_digest()
	_idle(t, 30)
	t.restore(s)
	assert_eq(t.state_digest(), d, "restore puts the hype back:")
