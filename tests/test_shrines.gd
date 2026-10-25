extends TestCase
## Shrines in every mode (src/sim/shrines.gd, data/rules/shrines.json): the modes whose rules
## turn them on get a shrine (a map without spots gets a central one), claims by any number
## of teams (a Brawl's fighters each claim alone), wearing an enemy claim down, a contested
## shrine holding, the announcement 10 s before it's ready, rollback in the middle of a
## claim, Capture the Flag's three shrines, the CPU going for a ready shrine (one fighter a
## team, not the whole team), and King of the Crater's shrine: opposite the zone and moving
## with it, a permanent buff drawn by the match seed for whoever claims it (kept through a
## respawn, capped, rolled back), the buffs' effects, and the CPU sending someone only when
## its side can spare them.

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
	assert_eq(dm.sim.shrines.size(), 0, "Team Deathmatch has none (a killing-spree shutdown comes instead)")
	var b := BrawlSim.new(["cairn", "sno", "pete"])
	assert_gt(float(b.sim.shrines.size()), 0.0, "Brawl has a shrine")
	var s := TeamSim.new(TEAMS, 2, TeamSim.rules_by_id("sinkhole"))
	assert_eq(s.sim.shrines.size(), 0, "Sinkhole has none (its floor falls in round it)")
	var c := TeamSim.new(TEAMS, 2, TeamSim.rules_by_id("caravan"))
	assert_eq(c.sim.shrines.size(), 0, "Caravan has none")
	var k := TeamSim.new(TEAMS, 2, TeamSim.rules_by_id("crater"))
	assert_eq(k.sim.shrines.size(), 1, "King of the Crater has one")
	assert_eq(Shrines.kind(k.sim, 0), "boost", "a permanent-buff shrine")
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


func test_capture_the_flag_has_three_shrines() -> void:
	var r := TeamSim.load_rules(TeamSim.CTF_PATH)
	var t := TeamSim.new([["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]], 3, r)
	assert_eq(t.shrines.size(), 3, "a home shrine each side and one in the middle")
	assert_eq([t.shrine_kind(0), t.shrine_kind(1), t.shrine_kind(2)], ["haste", "might", "haste"], "corners haste, middle might")
	var mid := t.sim.floor_rect().get_center()
	assert_lt(t.shrine_pos(1).distance_to(mid), 1.0, "the middle one in the middle (on the bridge)")
	assert_lt((t.shrine_pos(0) + t.shrine_pos(2) - mid * 2.0).length(), 1.0, "the corners turn into each other through the middle")
	assert_lt(t.shrine_pos(0).distance_to(t.base_of(0)), t.shrine_pos(0).distance_to(t.base_of(1)), "the top-left one is red's home shrine")
	for i in 3:
		var cell := t.sim.terrain.world_to_cell(t.shrine_pos(i))
		assert_eq(t.sim.terrain.get_cell(cell), TerrainGrid.INTACT, "shrine %d stands on floor (not water, a wall or a pit)" % i)
	assert_eq(t.shrine_radius(0), 20.0, "the map's radius")
	assert_eq(int(t.shrines[0][2]), 15 * 60, "ready after ctf.json's 15 s")
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	_idle(t, int(t.shrines[0][2]) + 1)
	_clear(t.sim)
	t.sim.creatures[0].pos = t.shrine_pos(0)
	var ev := _idle(t, t.shrine_claim_ticks() + 1)
	assert_eq(int(_of(ev, "shrine")[0]["power"]), 20 * 60, "ctf's 20 s buff (temporary)")
	assert_eq(t.shrine_kind(0), "haste", "a map's kind never cycles")
	assert_eq(int(t.shrines[0][2]), 45 * 60 - 1, "ctf's 45 s rest")
	assert_true(t.sim.creatures[0].boost_ids.is_empty(), "no permanent buffs in CTF")
	# The CPU goal stays the last fighter's (3v3), not a goal per side.
	var lasts := 0
	for c in t.sim.creatures:
		var g: Array = t.sim.goals[c.id]
		if not g.is_empty() and ((g[0] as Vector2) == t.shrine_pos(1) or (g[0] as Vector2) == t.shrine_pos(2)):
			lasts += 1
			assert_eq(c.id % 3, 2, "only a side's last fighter goes for one (%d)" % c.id)
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


# ------------------------------------------------------------------ King of the Crater


func _crater(seed_ := 0) -> TeamSim:
	var t := TeamSim.new(TEAMS, 2, TeamSim.rules_by_id("crater"), seed_)
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


## Stands fighter `slot` alone in the Crater's shrine (the rest well away) until it's claimed.
func _claim_crater(t: TeamSim, slot: int) -> Array:
	_ready_now(t)
	var me := t.sim.creatures[slot]
	for c in t.sim.creatures:
		if c != me:
			c.pos = t.sim.terrain.nearest_solid(t.sim.zone_pos)  # in the zone, far from the shrine
	me.pos = Shrines.pos(t.sim, 0)
	return _idle(t, Shrines.claim_ticks(t.sim) + 2)


func test_the_crater_shrine_stands_opposite_the_zone_and_moves_with_it() -> void:
	var t := _crater()
	var fr := t.sim.floor_rect()
	var gap := t.sim.zone_r + Shrines.radius(t.sim, 0)
	# The first zone is the middle: the shrine goes straight up from it, clear of it.
	assert_gt(Shrines.pos(t.sim, 0).distance_to(t.sim.zone_pos), gap, "never on the zone")
	assert_lt(absf(Shrines.pos(t.sim, 0).x - t.sim.zone_pos.x), 9.0, "straight up from a zone in the middle (fair to both sides)")
	assert_true(fr.has_point(Shrines.pos(t.sim, 0)), "on the floor")
	for k in range(1, 5):
		t.zone_i = k
		t._place_zone(true)
		var want := fr.get_center() * 2.0 - t.sim.zone_pos
		assert_lt(Shrines.pos(t.sim, 0).distance_to(want), 16.0, "zone %d: mirrored through the middle" % k)
		assert_gt(Shrines.pos(t.sim, 0).distance_to(t.sim.zone_pos), gap, "zone %d: clear of the zone" % k)
		var cell := t.sim.terrain.world_to_cell(Shrines.pos(t.sim, 0))
		assert_true(t.sim.terrain.get_cell(cell) != TerrainGrid.HOLE and t.sim.terrain.get_cell(cell) != TerrainGrid.CHASM,
			"zone %d: on solid floor" % k)


func test_a_crater_claim_gives_the_claimer_a_permanent_buff() -> void:
	var t := _crater(5)
	var me := t.sim.creatures[0]
	var mate := t.sim.creatures[1]
	var ev := _claim_crater(t, 0)
	var got := _of(ev, "shrine_boost")
	assert_eq(got.size(), 1, "one buff, for the one in it")
	assert_eq(int(got[0]["who"]), 0, "the claimer's")
	assert_false(bool(got[0]["capped"]), "not capped")
	assert_true(String(got[0]["text"]).begins_with("+"), "a toast's words (%s)" % got[0]["text"])
	assert_eq(me.boost_ids.size(), 1, "the claimer has it")
	assert_true(mate.boost_ids.is_empty(), "not its teammate outside")
	assert_eq(int(_of(ev, "shrine")[0]["power"]), 0, "no timed buff")
	assert_eq(int(t.sim.shrines[0][2]), 30 * 60 - 2, "rests 30 s (claimed 2 ticks ago)")


func test_the_draws_follow_the_match_seed() -> void:
	var seqs: Array = []
	for seed_ in [1, 1, 2]:
		var t := _crater(seed_)
		var ids: Array = []
		for k in 3:
			_claim_crater(t, 0)
			ids.append(String(t.sim.creatures[0].boost_ids[k]))
		seqs.append(ids)
	assert_eq(seqs[0], seqs[1], "the same seed draws the same buffs")
	var differ := false
	for seed_ in range(3, 12):
		var t := _crater(seed_)
		_claim_crater(t, 0)
		_claim_crater(t, 0)
		if t.sim.creatures[0].boost_ids != seqs[0].slice(0, 2):
			differ = true
	assert_true(differ, "other seeds draw other buffs")


func test_buffs_are_capped_and_a_capped_claim_only_denies() -> void:
	var t := _crater()
	var me := t.sim.creatures[0]
	for k in Shrines.max_boosts(t.sim):
		me.add_boost({"id": "speed", "speed": 1.08})
	var ev := _claim_crater(t, 0)
	var got := _of(ev, "shrine_boost")
	assert_eq(got.size(), 1, "it says so")
	assert_true(bool(got[0]["capped"]), "capped")
	assert_eq(me.boost_ids.size(), 3, "no fourth")
	assert_gt(float(t.sim.shrines[0][2]), 0.0, "but the shrine is spent (denied)")


func test_buffs_last_through_a_respawn() -> void:
	var t := _crater()
	var me := t.sim.creatures[0]
	me.add_boost({"id": "hp", "hp": 1.1})
	me.add_boost({"id": "damage", "damage": 1.08})
	var full := me.max_hp
	assert_near(full, float(me.def["max_hp"]) * 1.1, 0.001, "+10% max HP")
	me.hp = 0.0
	_idle(t, int(float(t.rules.get("respawn_seconds", 4)) * 60) + 10)
	assert_eq(me.boost_ids, ["hp", "damage"], "kept")
	assert_near(me.max_hp, full, 0.001, "max HP kept")
	assert_near(me.hp, full, 0.001, "back at the boosted full health")
	assert_near(me.boost_dmg, 1.08, 0.0001, "damage kept")


## A jab from fighter 0 into fighter 1 standing just in front: the damage it does.
func _jab(sim: MatchSim) -> float:
	sim.creatures[1].pos = sim.creatures[0].pos + Vector2(24, 0)
	sim.creatures[0].facing = Vector2.RIGHT
	var dmg := 0.0
	for k in 30:
		sim.step(PackedInt32Array([SimDefs.IN_LIGHT if k == 0 else 0, 0]))
		dmg += hit_damage(sim, 0, 1)
	return dmg


func test_what_each_buff_does() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var a := sim.creatures[0]
	var base_speed := a.walk_speed()
	var base_hit := _jab(sim)
	assert_gt(base_hit, 0.0, "the jab lands")
	var sim2 := MatchFactory.versus("cairn", "culvert")
	var b := sim2.creatures[0]
	b.add_boost({"id": "damage", "damage": 1.08})
	b.add_boost({"id": "speed", "speed": 1.08})
	b.add_boost({"id": "regen", "regen": 1.15})
	assert_near(b.walk_speed(), base_speed * 1.08, 0.0001, "+8% walking")
	assert_near(_jab(sim2), base_hit * 1.08, 0.01, "+8% damage")
	sim = MatchFactory.versus("cairn", "culvert")
	a = sim.creatures[0]
	var before := b.hp
	b.hp = before - 20.0
	b.add_boost({"id": "hp", "hp": 1.1})
	assert_near(b.max_hp, float(b.def["max_hp"]) * 1.1, 0.001, "+10% max HP")
	assert_near(b.hp, before - 20.0 + float(b.def["max_hp"]) * 0.1, 0.001, "and heals that much")
	a.stamina = 10.0
	b.stamina = 10.0
	a.step(0, sim)
	b.step(0, sim2)
	assert_near(b.stamina - 10.0, (a.stamina - 10.0) * 1.15, 0.0001, "+15% stamina regen")


func test_buffs_roll_back_and_are_in_the_digest() -> void:
	var t := _crater(3)
	_ready_now(t)
	var me := t.sim.creatures[0]
	me.pos = Shrines.pos(t.sim, 0)
	_idle(t, Shrines.claim_ticks(t.sim) - 5)
	var snap := t.snapshot()
	var d0 := t.state_digest()
	var hp0 := me.max_hp
	_idle(t, 10)
	assert_eq(me.boost_ids.size(), 1, "claimed")
	var after := t.state_digest()
	t.restore(snap)
	assert_eq(t.state_digest(), d0, "restored before the claim")
	assert_true(me.boost_ids.is_empty(), "the buff is gone again")
	assert_near(me.max_hp, hp0, 0.0001, "and the max HP it gave")
	_idle(t, 10)
	assert_eq(t.state_digest(), after, "replays to the same buff")
	me.boost_dmg = 1.5
	assert_true(t.state_digest() != after, "the buffs are in the digest")


func test_the_crater_cpu_sends_someone_only_when_its_side_can_spare_them() -> void:
	var t := _crater()
	t.score = [600, 0]
	assert_eq(t._shrine_allow(), [true, false], "the side ahead on zone time may go")
	t.score = [0, 0]
	_clear(t.sim)
	t.sim.creatures[2].pos = t.sim.zone_pos  # blue holds the zone alone
	assert_eq(t._shrine_allow(), [true, false], "a side losing the zone may go")
	t.sim.creatures[0].pos = t.sim.zone_pos + Vector2(6, 0)
	assert_eq(t._shrine_allow(), [false, false], "level and contested: everyone holds the zone")
