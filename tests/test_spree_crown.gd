extends TestCase
## Team Deathmatch's killing spree and shutdown, and the Brawl crown (data/rules/deathmatch.json,
## brawl.json): KO credit to the last hitter within credit_seconds, a spree at spree_at KOs and
## its level, shutdown points (capped) that can win the match, the killer's Surge meter, a
## spree ending on death; the crown to the first credited KO, taken by whoever KOs the holder,
## loose after a fall with nobody's hit behind it, crown points, crown points breaking a near tie on health at time;
## both rolling back; the CPU preferring the marked foe.

const TEAMS := [["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]]
const FOUR := ["cairn", "culvert", "craglash", "barkley"]


func _tdm(size := 2) -> TeamSim:
	var t := TeamSim.new(TEAMS, size, TeamSim.load_rules(TeamSim.DEATHMATCH_PATH))
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _brawl(ids: Array = FOUR) -> BrawlSim:
	var b := BrawlSim.new(ids, {}, {}, 3)
	while b.phase == BrawlSim.Phase.INTRO:
		b.step(PackedInt32Array())
	return b


## Steps `game` `ticks` times with no input, gathering the events.
func _idle(game: Object, ticks: int) -> Array:
	var out: Array = []
	for i in ticks:
		game.step(PackedInt32Array())
		out.append_array(game.sim.events)
	return out


func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e): return String(e["type"]) == kind)


## `killer` landed the last hit on `victim` just now, and `victim` goes down.
func _ko_by(game: Object, victim: int, killer: int) -> Array:
	game.hit_by[victim] = killer
	game.hit_at[victim] = game.sim.tick
	var c: CreatureSim = game.sim.creatures[victim]
	c.hp = 0.0
	c._set_state(CreatureSim.State.KO)
	return _idle(game, 1)


func _wait_respawn(t: TeamSim) -> void:
	_idle(t, int(float(t.rules["respawn_seconds"]) * 60) + 2)


# ------------------------------------------------------------------ credit

func test_a_hit_credits_its_attacker_for_a_while() -> void:
	var t := _tdm()
	t.sim.events = [{"type": "hit", "target": 2, "attacker": 0}, {"type": "poison", "who": 3, "by": 1}]
	t.sim.note_credit(t.hit_by, t.hit_at)
	assert_eq(t.hit_by[2], 0, "the hitter is noted:")
	assert_eq(t.hit_by[3], 1, "a poison tick counts too:")
	var window := int(float(t.rules["credit_seconds"]) * 60)
	assert_eq(MatchSim.credit_of(t.hit_by, t.hit_at, 2, t.sim.tick + window, window), 0, "within credit_seconds:")
	assert_eq(MatchSim.credit_of(t.hit_by, t.hit_at, 2, t.sim.tick + window + 1, window), -1, "not after:")


# ------------------------------------------------------------------ spree

func test_a_spree_starts_at_three_kos_and_its_level_rises() -> void:
	var t := _tdm()
	assert_true(t.spree, "Team Deathmatch has sprees")
	assert_eq(_of(_ko_by(t, 2, 0), "spree").size(), 0, "one KO is no spree:")
	_of(_ko_by(t, 3, 0), "spree")
	assert_eq(t.spree_level(0), 0, "two KOs: still none:")
	_wait_respawn(t)
	var ev := _of(_ko_by(t, 2, 0), "spree")
	assert_eq(ev.size(), 1, "the third KO starts a spree:")
	assert_eq(int(ev[0]["level"]), 1, "at level 1:")
	assert_eq(int(ev[0]["who"]), 0, "for the killer:")
	assert_eq(t.spree_level(0), 1, "level 1:")
	assert_gt(float(t.sim.marks[0]), 0.0, "marked for the CPU:")
	ev = _of(_ko_by(t, 3, 0), "spree")
	assert_eq(int(ev[0]["level"]), 2, "a fourth KO: level 2:")
	assert_eq(t.score, [4, 0], "plain points for each KO:")


func test_a_ko_without_a_recent_hit_credits_nobody() -> void:
	var t := _tdm()
	t.streak[0] = 2
	t.hit_by[2] = 0
	t.hit_at[2] = t.sim.tick - int(float(t.rules["credit_seconds"]) * 60) - 5  # long ago
	var c := t.sim.creatures[2]
	c.hp = 0.0
	c._set_state(CreatureSim.State.KO)
	_idle(t, 1)
	assert_eq(t.streak[0], 2, "a pit or a hazard isn't the old hitter's KO:")
	assert_eq(t.score, [1, 0], "the team still scores, as before:")


func test_a_shutdown_scores_a_point_a_level_capped() -> void:
	var t := _tdm()
	t.streak[2] = 3  # right team's first, level 1
	var ev := _ko_by(t, 2, 0)
	assert_eq(_of(ev, "shutdown").size(), 1, "a shutdown event:")
	assert_eq(int(_of(ev, "shutdown")[0]["bonus"]), 1, "level 1: +1:")
	assert_eq(t.score, [2, 0], "the KO plus the bonus:")
	t.streak[3] = 9  # level 7: capped
	ev = _ko_by(t, 3, 1)
	assert_eq(int(_of(ev, "shutdown")[0]["bonus"]), int(t.rules["shutdown_cap"]), "capped:")
	assert_eq(t.score, [2 + 1 + 3, 0], "one more KO and +3:")


func test_a_shutdown_gives_the_killer_surge_meter() -> void:
	var t := _tdm()
	var k := t.sim.creatures[0]
	k.energy = 10.0
	t.streak[2] = 4
	_ko_by(t, 2, 0)
	assert_near(k.energy, 10.0 + float(t.rules["shutdown_energy"]), 0.001, "shutdown_energy for the killer:")


func test_the_spree_ends_on_death_however_it_comes() -> void:
	var t := _tdm()
	t.streak[0] = 5
	var c := t.sim.creatures[0]
	c.hp = 0.0
	c._set_state(CreatureSim.State.KO)  # nobody's hit: a fall
	var ev := _idle(t, 1)
	assert_eq(t.streak[0], 0, "down: the spree is over:")
	assert_eq(_of(ev, "shutdown").size(), 0, "no killer, no shutdown:")
	assert_eq(t.spree_level(0), 0, "no level:")
	_idle(t, 1)
	assert_eq(float(t.sim.marks[0]), 0.0, "no longer marked:")


func test_a_shutdown_can_win_the_match() -> void:
	var t := _tdm()
	t.score = [t.score_to_win() - 3, 0]
	t.streak[2] = 4  # level 2: the KO and +2 reach the target exactly
	_ko_by(t, 2, 0)
	assert_eq(t.phase, TeamSim.Phase.OVER, "the shutdown wins:")
	assert_eq(t.winner, 0, "for the killer's team:")


func test_sudden_death_still_ends_on_any_ko() -> void:
	var t := _tdm()
	t.score = [2, 2]
	t.timer = 1
	_idle(t, 2)
	assert_true(t.overtime, "sudden death at a tie")
	_ko_by(t, 0, 2)
	assert_eq(t.winner, 1, "the next KO wins:")


func test_the_spree_rolls_back() -> void:
	var t := _tdm()
	_ko_by(t, 2, 0)
	_ko_by(t, 3, 0)
	var snap := t.snapshot()
	var d0 := t.state_digest()
	_wait_respawn(t)
	_ko_by(t, 2, 0)
	var d1 := t.state_digest()
	assert_eq(t.spree_level(0), 1, "on a spree after")
	t.restore(snap)
	assert_eq(t.state_digest(), d0, "restored exactly:")
	assert_eq(t.streak[0], 2, "two KOs again:")
	assert_eq(float(t.sim.marks[0]), 0.0, "not marked yet:")
	_wait_respawn(t)
	_ko_by(t, 2, 0)
	assert_eq(t.state_digest(), d1, "replays the same:")


func test_other_team_modes_have_no_spree() -> void:
	assert_false(TeamSim.new(TEAMS, 2).spree, "team battle:")
	assert_false(TeamSim.new(TEAMS, 2, TeamSim.rules_by_id("crater")).spree, "the Crater:")
	assert_false(TeamSim.new(TEAMS, 3, TeamSim.rules_by_id("ctf")).spree, "CTF:")
	assert_true(TeamSim.new(TEAMS, 2).sim.marks.is_empty(), "nothing marked")


# ------------------------------------------------------------------ crown

func test_the_first_ko_gives_the_killer_the_crown() -> void:
	var b := _brawl()
	assert_true(b.crown_on, "Brawl has the crown")
	assert_eq(b.crown, -1, "nobody wears it at the start:")
	var ev := _of(_ko_by(b, 1, 0), "crown")
	assert_eq(b.crown, 0, "the killer has it:")
	assert_eq(ev.size(), 1, "a crown event:")
	assert_eq(int(ev[0]["who"]), 0, "naming the holder:")
	assert_eq(int(ev[0]["from"]), -1, "from nobody:")
	assert_gt(float(b.sim.marks[0]), 0.0, "marked for the CPU:")


func test_koing_the_holder_takes_the_crown() -> void:
	var b := _brawl()
	_ko_by(b, 1, 0)
	var ev := _of(_ko_by(b, 0, 2), "crown")
	assert_eq(b.crown, 2, "the holder's killer wears it:")
	assert_eq(int(ev[0]["from"]), 0, "taken from the holder:")
	assert_eq(float(b.sim.marks[0]), 0.0, "the old holder isn't marked:")


func test_another_ko_leaves_the_crown_where_it_is() -> void:
	var b := _brawl()
	_ko_by(b, 1, 0)
	_ko_by(b, 3, 2)
	assert_eq(b.crown, 0, "only KOing the holder moves it:")


func test_the_holder_scores_crown_points() -> void:
	var b := _brawl()
	_ko_by(b, 1, 0)
	_idle(b, 180)
	assert_eq(b.crown_points(0), 3 * int(b.rules["crown_points_per_second"]), "a point a second:")
	assert_eq(b.crown_points(2), 0, "nobody else:")


func test_a_holder_who_falls_with_nobody_behind_it_drops_the_crown() -> void:
	var b := _brawl()
	_ko_by(b, 1, 0)
	var c := b.sim.creatures[0]
	c.hp = 0.0
	c._set_state(CreatureSim.State.KO)  # a pit, a hazard: no hit within credit_seconds
	var ev := _of(_idle(b, 1), "crown")
	assert_eq(b.crown, -1, "loose:")
	assert_eq(int(ev[0]["who"]), -1, "the event says so:")
	assert_eq(b.phase, BrawlSim.Phase.FIGHT, "two still fight")
	_ko_by(b, 3, 2)
	assert_eq(b.crown, 2, "the next credited KO takes it:")


func test_at_time_crown_points_break_a_near_tie_on_health() -> void:
	var b := _brawl()
	_ko_by(b, 1, 0)
	_idle(b, 120)
	for i in [0, 2, 3]:
		b.sim.creatures[i].hp = b.sim.creatures[i].max_hp
	b.sim.creatures[0].hp = b.sim.creatures[0].max_hp * 0.95  # the holder, a little behind
	b.timer = 1
	_idle(b, 1)
	assert_eq(b.phase, BrawlSim.Phase.OVER, "time")
	assert_eq(b.winner, 0, "within crown_tie_margin of the healthiest: the crown decides:")


func test_at_time_the_healthiest_still_beats_the_crown() -> void:
	var b := _brawl()
	_ko_by(b, 1, 0)
	_idle(b, 120)
	b.sim.creatures[0].hp = b.sim.creatures[0].max_hp * 0.5  # the holder, well behind
	b.sim.creatures[2].hp = b.sim.creatures[2].max_hp
	b.sim.creatures[3].hp = b.sim.creatures[3].max_hp * 0.6
	b.timer = 1
	_idle(b, 1)
	assert_eq(b.winner, 2, "crown points are only a tie-break:")
	var plain := _brawl()
	plain.sim.creatures[2].hp = plain.sim.creatures[2].max_hp * 0.5
	plain.sim.creatures[0].hp = 1.0
	plain.sim.creatures[1].hp = 1.0
	plain.sim.creatures[3].hp = 1.0
	plain.timer = 1
	_idle(plain, 1)
	assert_eq(plain.winner, 2, "nobody crowned: the healthiest:")


func test_crown_points_to_win_ends_the_match() -> void:
	var r := BrawlSim.load_rules()
	r["crown_points_to_win"] = 2
	var b := BrawlSim.new(FOUR, r, {}, 3)
	while b.phase == BrawlSim.Phase.INTRO:
		b.step(PackedInt32Array())
	_ko_by(b, 1, 0)
	_idle(b, 130)
	assert_eq(b.phase, BrawlSim.Phase.OVER, "two points: over:")
	assert_eq(b.winner, 0, "the holder wins:")


func test_the_crown_rolls_back() -> void:
	var b := _brawl()
	_ko_by(b, 1, 0)
	_idle(b, 30)
	var snap := b.snapshot()
	var d0 := b.state_digest()
	_ko_by(b, 0, 3)
	_idle(b, 30)
	var d1 := b.state_digest()
	assert_eq(b.crown, 3, "moved on")
	b.restore(snap)
	assert_eq(b.state_digest(), d0, "restored exactly:")
	assert_eq(b.crown, 0, "back on the first holder:")
	assert_gt(float(b.sim.marks[0]), 0.0, "marked again:")
	_ko_by(b, 0, 3)
	_idle(b, 30)
	assert_eq(b.state_digest(), d1, "replays the same:")


# ------------------------------------------------------------------ the CPU

## A Rage CPU in slot 0 with two foes: `near` closer, `far` further; returns its target.
func _cpu_target(sim: MatchSim, near: int, far: int) -> int:
	var me := sim.creatures[0]
	me.pos = Vector2(200, 150)
	sim.creatures[near].pos = me.pos + Vector2(70, 0)
	sim.creatures[far].pos = me.pos + Vector2(-110, 0)
	var cpu := CpuController.new(0, CpuController.RAGE, 7)
	cpu.bits(sim)
	return cpu._target.id if cpu._target != null else -1


func test_the_cpu_goes_for_the_crown() -> void:
	var b := _brawl(["cairn", "cairn", "cairn"])
	assert_eq(_cpu_target(b.sim, 1, 2), 1, "no crown: the nearer foe:")
	var b2 := _brawl(["cairn", "cairn", "cairn"])
	b2.crown = 2
	_idle(b2, 1)
	assert_eq(_cpu_target(b2.sim, 1, 2), 2, "the crown holder, a bit further off:")


func test_the_cpu_goes_for_a_spree() -> void:
	var t := TeamSim.new([["cairn", "cairn"], ["cairn", "cairn"]], 2, TeamSim.load_rules(TeamSim.DEATHMATCH_PATH))
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	t.sim.creatures[1].pos = Vector2(200, 250)  # the teammate, behind
	assert_eq(_cpu_target(t.sim, 2, 3), 2, "no spree: the nearer foe:")
	var t2 := TeamSim.new([["cairn", "cairn"], ["cairn", "cairn"]], 2, TeamSim.load_rules(TeamSim.DEATHMATCH_PATH))
	while t2.phase == TeamSim.Phase.INTRO:
		t2.step(PackedInt32Array())
	t2.streak[3] = 3
	_idle(t2, 1)
	t2.sim.creatures[1].pos = Vector2(200, 250)
	assert_eq(_cpu_target(t2.sim, 2, 3), 3, "the fighter on a spree:")
