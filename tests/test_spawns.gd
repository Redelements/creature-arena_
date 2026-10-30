extends TestCase
## Spawn fairness at tick 0 and on respawn, for every mode family on every map that allows
## it, with the most fighters it takes: nobody overlaps, nobody stands on a pit / wall /
## outside the floor, team sides start nearer their own anchor and clear of each other
## (MARGIN), a Brawl's seats are MARGIN apart. Respawn points are checked against the
## standing fighters. Centre tests only; footprints are the pit tests' job.

const CELL_MARGIN := 4.0  # cells between the nearest pair of opposing fighters at the start
const MAPS := ["stadium", "quarry", "floodgate", "greenhouse"]
# mixed radii: culvert 13, digby 9, the rest 10-12
const ROSTER_A := ["culvert", "digby", "cairn", "barkley"]
const ROSTER_B := ["culvert", "culvert", "culvert", "culvert"]
const ROSTER_C := ["craglash", "digby", "hissy", "pete"]
const ROSTER_D := ["digby", "sno", "gillbert", "cerebro"]


func _teams(a: Array, b: Array) -> Array:
	return [a.duplicate(), b.duplicate()]


func _check_bodies(cs: Array, sim: MatchSim, tag: String, margin := 0.0) -> void:
	var fl := sim.floor_rect()
	for i in cs.size():
		var a: CreatureSim = cs[i]
		assert_true(fl.has_point(a.pos), "%s: %s outside the floor at %s" % [tag, a.id, str(a.pos)])
		assert_false(sim.terrain.is_hole_at(a.pos), "%s: %s stands on a pit at %s" % [tag, a.id, str(a.pos)])
		assert_false(sim.terrain.solid_at(a.pos), "%s: %s stands in a solid at %s" % [tag, a.id, str(a.pos)])
		for j in range(i + 1, cs.size()):
			var b: CreatureSim = cs[j]
			var d := a.pos.distance_to(b.pos)
			assert_true(d >= a.radius + b.radius + margin,
				"%s: slots %d and %d overlap (%.1f < %.1f)" % [tag, i, j, d, a.radius + b.radius + margin])


func _check_team(t: TeamSim, tag: String) -> void:
	var s := t.sim
	_check_bodies(s.creatures, s, tag)
	var cell := float(SimDefs.CELL)
	var near := INF
	for a in s.creatures:
		var own := a.pos.distance_to(s.spawn(a.team))
		var other := a.pos.distance_to(s.spawn(1 - a.team))
		assert_true(own < other, "%s: %s (side %d) starts nearer the other side's anchor" % [tag, a.id, a.team])
		for b in s.creatures:
			if b.team != a.team:
				near = minf(near, a.pos.distance_to(b.pos))
	assert_true(near >= CELL_MARGIN * cell, "%s: sides start only %.0f px apart (< %d cells)" % [tag, near, int(CELL_MARGIN)])
	# respawn points (pads / checkpoint / keep) against the standing fighters' start spots
	for side in 2:
		var pts: Array = []
		for k in t.size:
			pts.append(s.terrain.nearest_solid(t.pad_point(side, k)))
		for k in pts.size():
			var p: Vector2 = pts[k]
			assert_true(s.floor_rect().has_point(p), "%s: respawn %d/%d off the floor" % [tag, side, k])
			assert_false(s.terrain.is_hole_at(p) or s.terrain.solid_at(p), "%s: respawn %d/%d on a pit or solid at %s" % [tag, side, k, str(p)])
			for c in s.creatures:
				if c.team != side:  # the own side's standing fighters have long left their start spots
					assert_true(p.distance_to(c.pos) >= c.radius + 13.0, "%s: respawn %d/%d lands on foe %s" % [tag, side, k, c.id])
			for k2 in range(k + 1, pts.size()):
				assert_true(p.distance_to(pts[k2]) >= 26.0, "%s: respawns %d/%d and %d overlap" % [tag, side, k, k2])


func _team_cell(rules_path: String, map: String, size: int, a: Array, b: Array) -> void:
	var saved := MatchFactory.arena
	if map != "":
		MatchFactory.arena = map
	var r := TeamSim.load_rules(rules_path)
	var t := TeamSim.new(_teams(a, b), size, r)
	MatchFactory.arena = saved
	_check_team(t, "%s/%s x%d %s" % [rules_path.get_file(), t.sim.arena.get("name", map), size, str(a[0])])


func test_team_modes_on_pickable_maps() -> void:
	for path in [TeamSim.RULES_PATH, TeamSim.DEATHMATCH_PATH, TeamSim.SINKHOLE_PATH, TeamSim.CRATER_PATH]:
		for m in MAPS:
			for pair in [[ROSTER_A, ROSTER_C], [ROSTER_B, ROSTER_D]]:
				_team_cell(path, m, 4, pair[0], pair[1])


func test_ctf_twin_keeps_4v4() -> void:
	for pair in [[ROSTER_A, ROSTER_C], [ROSTER_B, ROSTER_D]]:
		_team_cell(TeamSim.CTF_PATH, "", 4, pair[0], pair[1])


func test_caravan_pass_3v3() -> void:
	for pair in [[ROSTER_A, ROSTER_C], [ROSTER_B, ROSTER_D]]:
		_team_cell(TeamSim.CARAVAN_PATH, "", 3, pair[0], pair[1])
	# the second round puts everyone back on the spawn rows
	var t := TeamSim.new(_teams(ROSTER_A, ROSTER_C), 3, TeamSim.load_rules(TeamSim.CARAVAN_PATH))
	t._cv_start_round(1)
	_check_bodies(t.sim.creatures, t.sim, "caravan round 2")


func test_brawl_four_seats() -> void:
	var saved := MatchFactory.arena
	for m in MAPS:
		MatchFactory.arena = m
		for ids in [ROSTER_A, ROSTER_B, ROSTER_C, ROSTER_D]:
			var b := BrawlSim.new(ids, BrawlSim.load_rules())
			var tag := "brawl/%s %s" % [m, str(ids[0])]
			_check_bodies(b.sim.creatures, b.sim, tag)
			var cs := b.sim.creatures
			for i in cs.size():
				for j in range(i + 1, cs.size()):
					assert_true(cs[i].pos.distance_to(cs[j].pos) >= CELL_MARGIN * SimDefs.CELL,
						"%s: seats %d and %d only %.0f px apart" % [tag, i, j, cs[i].pos.distance_to(cs[j].pos)])
	MatchFactory.arena = saved


func test_duel_and_versus_two_fighters() -> void:
	var saved := MatchFactory.arena
	for m in MAPS:
		MatchFactory.arena = m
		var d := DuelSim.new(_teams(ROSTER_A.slice(0, 3), ROSTER_B.slice(0, 3)))
		_check_bodies(d.sim.creatures, d.sim, "duel/" + m)
		var v := MatchFactory.versus("culvert", "culvert")
		_check_bodies(v.creatures, v, "versus/" + m)
	MatchFactory.arena = saved
