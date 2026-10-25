extends TestCase
## Shrines in every mode (src/sim/shrines.gd, data/rules/shrines.json): the modes whose rules
## turn them on get a shrine (a map without spots gets a central one), claims by any number
## of teams (a Brawl's fighters each claim alone), wearing an enemy claim down, a contested
## shrine holding, the announcement 10 s before it's ready, rollback in the middle of a
## claim, Capture the Flag's shrines unchanged, and the CPU going for a ready shrine
## (one fighter a team, not the whole team).

const TEAMS := [["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]]
const ON := {"kinds": ["haste", "might"], "first_seconds": 20}


func _team(id := "", size := 2, block := ON) -> TeamSim:
	var r := TeamSim.load_rules() if id == "" else TeamSim.rules_by_id(id)
	r["shrines"] = block.duplicate(true)
	var t := TeamSim.new(TEAMS, size, r)
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _brawl(n := 3, block := ON) -> BrawlSim:
	var r := BrawlSim.load_rules()
	r["shrines"] = block.duplicate(true)
	var b := BrawlSim.new(["cairn", "sno", "pete", "culvert"].slice(0, n), r)
	while b.phase == BrawlSim.Phase.INTRO:
		b.step(PackedInt32Array())
	return b


## Steps a match with nobody pressing anything (and nobody drifting), collecting events.
func _idle(g: Object, ticks: int) -> Array:
	var seen: Array = []
	for i in ticks:
		g.step(PackedInt32Array())
		var sim: MatchSim = g.sim
		for c in sim.creatures:
			c.walk_vel = Vector2.ZERO
		seen.append_array(sim.events)
	return seen


func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e): return String(e["type"]) == kind)


## Everyone well away from the shrine, in the floor's corners.
func _clear(sim: MatchSim) -> void:
	var fr := sim.floor_rect().grow(-40.0)
	var corners := [fr.position, Vector2(fr.end.x, fr.position.y), Vector2(fr.position.x, fr.end.y), fr.end]
	for c in sim.creatures:
		c.pos = sim.terrain.nearest_solid(corners[c.id % corners.size()])


func _ready_now(g: Object) -> void:
	var sim: MatchSim = g.sim
	_clear(sim)
	for st in sim.shrines:
		st[2] = 1
	_idle(g, 1)


func test_modes_turn_shrines_on_from_their_rules() -> void:
	var dm := TeamSim.new(TEAMS, 2, TeamSim.rules_by_id("deathmatch"))
	assert_eq(dm.sim.shrines.size(), 1, "Team Deathmatch has one")
	var b := BrawlSim.new(["cairn", "sno", "pete"])
	assert_gt(float(b.sim.shrines.size()), 0.0, "Brawl has a shrine")
	var s := TeamSim.new(TEAMS, 2, TeamSim.rules_by_id("sinkhole"))
	assert_eq(s.sim.shrines.size(), 0, "Sinkhole has none (its floor falls in round it)")
	var c := TeamSim.new(TEAMS, 2, TeamSim.rules_by_id("caravan"))
	assert_eq(c.sim.shrines.size(), 0, "Caravan has none")
	var k := TeamSim.new(TEAMS, 2, TeamSim.rules_by_id("crater"))
	assert_eq(k.sim.shrines.size(), 0, "King of the Crater has none (its zone is the objective)")
	var t0 := TeamSim.new(TEAMS, 2, TeamSim.load_rules())
	assert_eq(t0.sim.shrines.size(), 0, "the one-life team battle has none (they fed the side ahead)")
	assert_true(t0.sim.goals.is_empty(), "and no CPU goals")


func test_a_map_without_spots_gets_a_central_shrine() -> void:
	var t := _team()
	assert_eq(t.sim.shrines.size(), 1, "one shrine")
	assert_lt(Shrines.pos(t.sim, 0).distance_to(t.sim.floor_rect().get_center()), 16.0, "in the middle of the floor")
	assert_eq(int(t.sim.shrines[0][2]), 20 * 60 - 1, "ready after first_seconds (counted from the fight's first tick)")
	assert_eq(Shrines.radius(t.sim, 0), float(Shrines.defaults()["radius"]), "the default radius")


func test_the_announcement_comes_ten_seconds_early() -> void:
	var t := _team()
	var ev := _idle(t, 20 * 60 + 2)
	var soon := _of(ev, "shrine_soon")
	var ready := _of(ev, "shrine_ready")
	assert_eq(soon.size(), 1, "one announcement")
	assert_eq(ready.size(), 1, "then ready")
	assert_eq(int(ready[0]["tick"]) - int(soon[0]["tick"]), 600, "10 s before it's ready")
	assert_eq(int(soon[0]["ticks"]), 600, "it says how long")
	assert_eq(String(soon[0]["kind"]), "haste", "and what it gives")


func test_a_brawl_fighter_alone_claims_it_for_itself() -> void:
	var b := _brawl(3)
	_ready_now(b)
	var me := b.sim.creatures[1]
	me.pos = Shrines.pos(b.sim, 0)
	var ev := _idle(b, Shrines.claim_ticks(b.sim) + 2)
	var got := _of(ev, "shrine")
	assert_eq(got.size(), 1, "claimed")
	assert_eq(int(got[0]["team"]), 1, "by fighter 1's team (itself)")
	assert_gt(float(me.haste), 0.0, "it's hasted")
	for c in b.sim.creatures:
		if c != me:
			assert_eq(c.haste, 0, "nobody else is (%d)" % c.id)
	assert_gt(float(b.sim.shrines[0][2]), 0.0, "and it rests")
	assert_eq(Shrines.kind(b.sim, 0), "might", "the next one gives might")


func test_another_team_wears_a_claim_down_first() -> void:
	var b := _brawl(4)
	_ready_now(b)
	var a := b.sim.creatures[0]
	var c := b.sim.creatures[2]
	a.pos = Shrines.pos(b.sim, 0)
	_idle(b, 60)
	assert_eq(int(b.sim.shrines[0][0]), 0, "fighter 0 is claiming")
	assert_near(float(b.sim.shrines[0][1]), 60.0, 0.01, "a second in")
	_clear(b.sim)
	c.pos = Shrines.pos(b.sim, 0)
	_idle(b, 20)
	assert_eq(int(b.sim.shrines[0][0]), 0, "still 0's claim while 2 wears it down")
	assert_near(float(b.sim.shrines[0][1]), 20.0, 0.01, "twice as fast")
	_idle(b, 15)
	assert_eq(int(b.sim.shrines[0][0]), 2, "worn out: now 2 claims it")
	var ev := _idle(b, Shrines.claim_ticks(b.sim))
	assert_eq(int(_of(ev, "shrine")[0]["team"]), 2, "and takes it")


func test_two_or_more_teams_in_it_hold_the_claim() -> void:
	var b := _brawl(3)
	_ready_now(b)
	b.sim.creatures[0].pos = Shrines.pos(b.sim, 0)
	_idle(b, 30)
	b.sim.creatures[1].pos = Shrines.pos(b.sim, 0) + Vector2(8, 0)
	_idle(b, 90)
	assert_near(float(b.sim.shrines[0][1]), 30.0, 0.01, "held with two in")
	b.sim.creatures[2].pos = Shrines.pos(b.sim, 0) + Vector2(-8, 0)
	_idle(b, 90)
	assert_near(float(b.sim.shrines[0][1]), 30.0, 0.01, "and with three")
	assert_eq(int(b.sim.shrines[0][0]), 0, "still 0's")
	_clear(b.sim)
	_idle(b, 10)
	assert_near(float(b.sim.shrines[0][1]), 20.0, 0.01, "nobody in: it fades")


func test_a_team_claim_buffs_the_whole_side_in_deathmatch() -> void:
	var t := _team("deathmatch", 2)
	_ready_now(t)
	t.sim.creatures[2].pos = Shrines.pos(t.sim, 0)  # blue's first
	var ev := _idle(t, Shrines.claim_ticks(t.sim) + 2)
	assert_eq(int(_of(ev, "shrine")[0]["team"]), 1, "blue claimed it")
	for c in t.sim.creatures:
		assert_eq(c.haste > 0, c.team == 1, "haste on blue only (%d)" % c.id)


func test_rollback_in_the_middle_of_a_claim() -> void:
	var t := _team("", 2)
	_ready_now(t)
	t.sim.creatures[0].pos = Shrines.pos(t.sim, 0)
	_idle(t, 70)
	var snap := t.snapshot()
	var d0 := t.state_digest()
	var ev := _idle(t, Shrines.claim_ticks(t.sim))
	assert_eq(_of(ev, "shrine").size(), 1, "the claim finishes")
	var after := t.state_digest()
	t.restore(snap)
	assert_eq(t.state_digest(), d0, "restored mid-claim")
	assert_near(float(t.sim.shrines[0][1]), 70.0, 0.01, "the claim's progress is back")
	_idle(t, Shrines.claim_ticks(t.sim))
	assert_eq(t.state_digest(), after, "and replays the same")
	t.sim.shrines[0][1] = 10.0
	assert_true(t.state_digest() != after, "the claim is in the digest")


func test_capture_the_flag_shrines_are_as_before() -> void:
	var r := TeamSim.load_rules(TeamSim.CTF_PATH)
	var t := TeamSim.new([["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]], 3, r)
	assert_eq(t.shrines.size(), 2, "the map's two")
	assert_eq(t.shrine_kind(0), "haste", "fixed kinds")
	assert_eq(t.shrine_kind(1), "might", "fixed kinds")
	assert_eq(t.shrine_radius(0), 20.0, "the map's radius")
	assert_eq(int(t.shrines[0][2]), 15 * 60, "ready after ctf.json's 15 s")
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	_idle(t, int(t.shrines[0][2]) + 1)
	_clear(t.sim)
	t.sim.creatures[0].pos = t.shrine_pos(0)
	var ev := _idle(t, t.shrine_claim_ticks() + 1)
	assert_eq(int(_of(ev, "shrine")[0]["power"]), 20 * 60, "ctf's 20 s buff")
	assert_eq(t.shrine_kind(0), "haste", "a map's kind never cycles")
	assert_eq(int(t.shrines[0][2]), 45 * 60 - 1, "ctf's 45 s rest")
	# The CPU goal stays the last fighter's (3v3), not a goal per side.
	var lasts := 0
	for c in t.sim.creatures:
		var g: Array = t.sim.goals[c.id]
		if not g.is_empty() and (g[0] as Vector2) == t.shrine_pos(1):
			lasts += 1
			assert_eq(c.id % 3, 2, "only a side's last fighter goes for it (%d)" % c.id)
	assert_eq(lasts, 2, "each side's last fighter")


func test_one_fighter_a_team_goes_for_a_ready_shrine() -> void:
	var t := _team("", 3)
	_ready_now(t)
	# Red's slot 1 a little off the shrine, the rest of red and blue in the corners.
	var near := t.sim.creatures[1]
	near.pos = Shrines.pos(t.sim, 0) + Vector2(-120, 0)
	t.sim.creatures[4].pos = Shrines.pos(t.sim, 0) + Vector2(150, 0)
	_idle(t, 1)
	var per_side := [0, 0]
	for c in t.sim.creatures:
		if not (t.sim.goals[c.id] as Array).is_empty():
			per_side[c.team] += 1
	assert_eq(per_side, [1, 1], "one fighter a side")
	assert_false((t.sim.goals[near.id] as Array).is_empty(), "red's nearest goes")
	assert_false((t.sim.goals[4] as Array).is_empty(), "blue's nearest goes")
	# Mid-fight (a foe right on it) nobody leaves for it.
	t.sim.creatures[3].pos = near.pos + Vector2(20, 0)
	_idle(t, 1)
	assert_true((t.sim.goals[near.id] as Array).is_empty(), "not with a foe on you")


func test_cpus_walk_to_a_ready_shrine_and_claim_it() -> void:
	var b := _brawl(3)
	_ready_now(b)
	var me := b.sim.creatures[0]
	me.pos = b.sim.terrain.nearest_solid(Shrines.pos(b.sim, 0) + Vector2(-110, -30))
	var cpus: Array = []
	for i in b.slot_count():
		cpus.append(CpuController.new(i, 2, 77 + i))
	var claimed := -1
	for k in 600:
		var ins := PackedInt32Array()
		for i in b.slot_count():
			ins.append((cpus[i] as CpuController).bits(b.sim) if i == 0 else 0)
		b.step(ins)
		for e in b.sim.events:
			if String(e["type"]) == "shrine":
				claimed = int(e["team"])
		if claimed >= 0:
			break
	assert_eq(claimed, 0, "the CPU went to the shrine and claimed it")
