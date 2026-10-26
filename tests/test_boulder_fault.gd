extends TestCase
## The rolling boulder and the fault line (src/sim/hazards.gd shapes "boulder" and "fault",
## data/rules/hazards.json): warnings long enough to read and nothing happening during them,
## several boulders a roll from different edges, each one's lane and roll, its hit (a share
## of max HP by role, a knockdown, a push along its path), a heavy sending it back with the
## KO credit to the striker, boulders ricocheting off each other (deterministic, through a
## rollback, keeping the sender's credit) and off walls until they shatter, where they go
## away (the far edge, a pit), the fault opening into chasm and closing back to exactly the
## map, never on the map's own pieces, seeded placement, rollback mid-roll and mid-open, and
## CPUs that step out of a boulder's way (its lane, or its new way after a ricochet) and off
## the crack.

const BOULDER := {"hazards": ["rolling_boulder"]}
const FAULT := {"hazards": ["fault_line"]}


func _sim(m: Dictionary, seed_ := 7, a := "cairn", b := "culvert") -> MatchSim:
	var sim := MatchFactory.versus(a, b)
	sim.apply_mutators(m, seed_)
	return sim


func _state(sim: MatchSim, shape: String) -> Dictionary:
	for st in sim.hazards:
		if String(sim.hazard_defs[String(st["id"])]["shape"]) == shape:
			return st
	return {}


func _steps(sim: MatchSim, n: int, out: Array = [], p0 := 0, p1 := 0) -> Array:
	for i in n:
		sim.step(PackedInt32Array([p0, p1]))
		out.append_array(sim.events)
	return out


func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e): return String(e["type"]) == kind)


func _bdef(sim: MatchSim) -> Dictionary:
	return sim.hazard_defs["rolling_boulder"]


## Puts boulders rolling (no warning), one per [pos, dir] in `rocks`, with nothing scheduled
## after; returns the boulders' dictionaries.
func _roll_many(sim: MatchSim, rocks: Array) -> Array:
	var st := _state(sim, "boulder")
	st["next"] = 1 << 30
	st["phase"] = Hazards.ACTIVE
	st["t"] = 0
	st["pairs"] = {}
	var fr := sim.floor_rect()
	var r := float(_bdef(sim)["radius"])
	var out: Array = []
	for pd in rocks:
		var dir: Vector2 = pd[1]
		var side := 0 if dir.x > 0.0 else (1 if dir.x < 0.0 else (2 if dir.y > 0.0 else 3))
		var lane: float = (pd[0].y - fr.position.y) if side < 2 else (pd[0].x - fr.position.x)
		var rk := Hazards._new_rock(fr, side, lane, r, float(_bdef(sim)["speed"]))
		rk["pos"] = pd[0]
		rk["dir"] = dir
		out.append(rk)
	st["rocks"] = out
	return out


## One boulder rolling at `pos` going `dir`; returns its dictionary.
func _roll(sim: MatchSim, pos: Vector2, dir: Vector2) -> Dictionary:
	return _roll_many(sim, [[pos, dir]])[0]


## Both fighters well apart on one row, the foe out of the way unless placed.
func _place(sim: MatchSim, a: Vector2, b: Vector2) -> void:
	sim.creatures[0].pos = a
	sim.creatures[1].pos = b


func test_the_boulders_warn_together_then_roll_down_their_lanes() -> void:
	var sim := _sim(BOULDER)
	var d := _bdef(sim)
	var st := _state(sim, "boulder")
	var n := int(d["count"])
	assert_true(n >= 2, "several boulders a roll (%d)" % n)
	assert_eq(int(st["next"]), Hazards.ticks_of(d["first_seconds"]), "the first warning at first_seconds:")
	st["next"] = sim.tick + 1
	var ev := _steps(sim, 1)
	var warn := _of(ev, "hazard_warn")
	assert_eq(warn.size(), n, "every boulder warns, all at once:")
	var ticks := Hazards.ticks_of(d["warn_seconds"])
	for w in warn:
		assert_eq(int(w["ticks"]), ticks, "each for warn_seconds:")
	assert_true(ticks >= 90, "1.5 s or more to step out (%d ticks)" % ticks)
	assert_eq(int(st["next"]), sim.tick - 1 + Hazards.ticks_of(d["every_seconds"]) + 1, "the next roll every_seconds on:")
	var fr := sim.floor_rect()
	var rocks: Array = st["rocks"]
	assert_eq(rocks.size(), n, "")
	var edges := {}
	for rk in rocks:
		var lane := float(rk["lane"])
		var span := fr.size.y if int(rk["side"]) < 2 else fr.size.x
		assert_true(lane >= float(d["inset"]) and lane <= span - float(d["inset"]), "each lane is inset from the sides: %s" % lane)
		edges[int(rk["side"])] = true
	assert_eq(edges.size(), mini(n, (d["sides"] as Array).size()), "from different edges, so the lanes cross:")
	var bl: Array = Hazards.boulders_now(sim)
	var hp0 := sim.creatures[0].hp
	ev = _steps(sim, ticks - 2)
	assert_eq(_of(ev, "hazard_hit").size(), 0, "nothing hits during the warning:")
	assert_eq(int(st["phase"]), Hazards.WARN, "still warning:")
	ev = _steps(sim, 2)
	assert_eq(_of(ev, "hazard_strike").size(), n, "then they all roll:")
	assert_eq(int(st["phase"]), Hazards.ACTIVE, "rolling:")
	var p0: Vector2 = rocks[0]["pos"]
	_steps(sim, 10)
	var moved: Vector2 = Vector2(rocks[0]["pos"]) - p0
	assert_near(moved.length(), float(d["speed"]) * 10.0, 0.01, "at speed px a tick:")
	assert_near(moved.normalized().dot(bl[0]["dir"]), 1.0, 0.001, "straight down the lane:")
	assert_near(sim.creatures[0].hp, hp0, 0.001, "")


func test_a_boulder_hit_scales_by_role_knocks_down_and_pushes_along() -> void:
	for who in ["cairn", "culvert"]:
		var sim := _sim(BOULDER, 7, who, "cairn")
		var c := sim.creatures[0]
		var fr := sim.floor_rect()
		_place(sim, Vector2(fr.get_center().x, fr.position.y + 100), Vector2(fr.get_center().x, fr.end.y - 30))
		_roll(sim, c.pos - Vector2(60, 0), Vector2.RIGHT)
		var hp := c.hp
		var ev := _steps(sim, 25)
		var hits := _of(ev, "hazard_hit")
		assert_eq(hits.size(), 1, "%s struck once:" % who)
		var d := _bdef(sim)
		var want := c.max_hp * float(d["damage_pct"]) * float((d["role_mult"] as Dictionary).get(TeamSim.role_of(c), 1.0))
		assert_near(hp - c.hp, want, 0.01, "%s takes damage_pct of max HP x its role:" % who)
		assert_eq(int(hits[0]["by"]), -1, "nobody's hit:")
		assert_eq(c.state, CreatureSim.State.KNOCKDOWN, "%s knocked down:" % who)
		var sim2 := _sim(BOULDER, 7, who, "cairn")
		var c2 := sim2.creatures[0]
		_place(sim2, Vector2(fr.get_center().x, fr.position.y + 100), Vector2(fr.get_center().x, fr.end.y - 30))
		var x0 := c2.pos.x
		_roll(sim2, c2.pos - Vector2(60, 0), Vector2.RIGHT)
		var y0 := c2.pos.y
		_steps(sim2, 40)
		assert_gt(c2.pos.x - x0, 10.0, "%s pushed along its path" % who)
		assert_near(c2.pos.y, y0, 0.5, "and not sideways:")
	# Leaping or in the air: it rolls under.
	var sim3 := _sim(BOULDER)
	var a := sim3.creatures[0]
	var fr3 := sim3.floor_rect()
	_place(sim3, Vector2(fr3.get_center().x, fr3.position.y + 100), Vector2(fr3.get_center().x, fr3.end.y - 30))
	a.enter_air(60, Vector2.ZERO)
	_roll(sim3, a.pos - Vector2(40, 0), Vector2.RIGHT)
	var ev3 := _steps(sim3, 30)
	assert_eq(_of(ev3, "hazard_hit").size(), 0, "an airborne fighter isn't hit:")


func test_it_pushes_into_a_pit() -> void:
	var sim := _sim(BOULDER)
	var c := sim.creatures[0]
	var fr := sim.floor_rect()
	_place(sim, Vector2(fr.get_center().x, fr.position.y + 100), Vector2(fr.get_center().x, fr.end.y - 30))
	# A pit ahead of the fighter, along the boulder's path (not on its lane: it would sink).
	for dx in range(3, 9):
		for dy in range(-1, 2):
			sim.terrain.set_cell(sim.terrain.world_to_cell(c.pos) + Vector2i(dx, dy), TerrainGrid.HOLE)
	_roll(sim, c.pos - Vector2(60, 0), Vector2.RIGHT)
	var ev := _steps(sim, 60)
	assert_true(_of(ev, "fall").any(func(e): return int(e["who"]) == 0), "knocked into the pit")
	assert_true(_of(ev, "hazard_end").any(func(e): return String(e["how"]) == "pit"), "and the boulder fell in after")


func test_a_heavy_sends_it_back_at_the_others_with_the_credit() -> void:
	var sim := _sim(BOULDER, 7, "cairn", "culvert")
	var a := sim.creatures[0]
	var b := sim.creatures[1]
	var fr := sim.floor_rect()
	var row := fr.position.y + 100
	_place(sim, Vector2(fr.position.x + 200, row), Vector2(fr.position.x + 420, row))
	a.facing = Vector2.RIGHT
	# Rolling left at the striker from just past where its heavy will reach.
	var st := _roll(sim, Vector2(a.pos.x + 98, row), Vector2.LEFT)  # (the boulder)
	b.pos = Vector2(a.pos.x + 200, row)  # behind the boulder: it has already passed
	var by: Array = [-1, -1]
	var at: Array = [0, 0]
	var ev: Array = []
	sim.step(PackedInt32Array([SimDefs.IN_HEAVY, 0]))
	ev.append_array(sim.events)
	sim.note_credit(by, at)
	for i in 120:
		sim.step(PackedInt32Array([0, 0]))
		ev.append_array(sim.events)
		sim.note_credit(by, at)
	var rev := _of(ev, "hazard_reverse")
	assert_eq(rev.size(), 1, "the heavy sent it back:")
	assert_eq(int(rev[0]["by"]), 0, "the striker's:")
	assert_eq(_of(ev, "hazard_hit").filter(func(e): return int(e["who"]) == 0).size(), 0, "it spared the striker:")
	var on_b := _of(ev, "hazard_hit").filter(func(e): return int(e["who"]) == 1)
	assert_eq(on_b.size(), 1, "and struck the other:")
	if not on_b.is_empty():
		assert_eq(int(on_b[0]["by"]), 0, "credited to the striker:")
	assert_eq(int(by[1]), 0, "MatchSim.note_credit gives the striker the KO credit:")
	assert_gt(float(st["speed"]), float(_bdef(sim)["speed"]), "it comes back faster")


func test_a_light_doesnt_send_it_back() -> void:
	var sim := _sim(BOULDER, 7, "cairn", "culvert")
	var a := sim.creatures[0]
	var fr := sim.floor_rect()
	var row := fr.position.y + 100
	_place(sim, Vector2(fr.position.x + 200, row), Vector2(fr.position.x + 420, fr.end.y - 30))
	a.facing = Vector2.RIGHT
	_roll(sim, Vector2(a.pos.x + 40, row), Vector2.LEFT)
	var ev := _steps(sim, 1, [], SimDefs.IN_LIGHT)
	_steps(sim, 30, ev)
	assert_eq(_of(ev, "hazard_reverse").size(), 0, "a light can't:")
	assert_eq(_of(ev, "hazard_hit").filter(func(e): return int(e["who"]) == 0).size(), 1, "it rolls on over the jabber")


func test_it_goes_away_at_the_far_edge_and_bounces_off_walls_until_it_shatters() -> void:
	var sim := _sim(BOULDER)
	var fr := sim.floor_rect()
	var d := _bdef(sim)
	_place(sim, Vector2(fr.get_center().x, fr.end.y - 20), Vector2(fr.get_center().x + 40, fr.end.y - 20))
	var st := _state(sim, "boulder")
	_roll(sim, Vector2(fr.end.x - 30, fr.position.y + 60), Vector2.RIGHT)
	var ev := _steps(sim, 30)
	var end := _of(ev, "hazard_end")
	assert_eq(end.size(), 1, "gone past the far edge:")
	assert_eq(String(end[0]["how"]), "edge", "")
	assert_eq(int(st["phase"]), Hazards.IDLE, "and the roll is over:")
	# Two rubble walls across its lane: it bounces between them wall_bounces times, then shatters.
	var row := fr.position.y + 60
	var left := sim.terrain.world_to_cell(Vector2(fr.get_center().x - 100, row))
	var right := sim.terrain.world_to_cell(Vector2(fr.get_center().x + 100, row))
	for dy in range(-4, 5):
		sim.terrain.set_cell(left + Vector2i(0, dy), TerrainGrid.WALL)
		sim.terrain.set_cell(right + Vector2i(0, dy), TerrainGrid.WALL)
	var rk := _roll(sim, Vector2(fr.get_center().x, row), Vector2.RIGHT)
	var speed0 := float(rk["speed"])
	ev = _steps(sim, 600)
	var bounces := _of(ev, "hazard_ricochet").filter(func(e): return int(e["other"]) == -1)
	assert_eq(bounces.size(), int(d["wall_bounces"]), "it bounces off rubble wall_bounces times:")
	if not bounces.is_empty():
		assert_near(Vector2(bounces[0]["dir"]).x, -1.0, 0.001, "straight back off a wall across its way:")
	end = _of(ev, "hazard_end")
	assert_eq(end.size(), 1, "then it's gone:")
	if not end.is_empty():
		assert_eq(String(end[0]["how"]), "wall", "it shattered on the next one:")
		var x := Vector2(end[0]["pos"]).x
		assert_true(x > fr.get_center().x - 100 and x < fr.get_center().x + 100, "between the walls")
	assert_lt(float(rk["speed"]), speed0, "each bounce slows it (ricochet_speed_mult)")


func test_the_lanes_are_seeded() -> void:
	var seen := {}
	for s in [3, 4, 5, 6, 9]:
		var sim := _sim(BOULDER, s)
		_state(sim, "boulder")["next"] = 1
		_steps(sim, 1)
		var out: Array = []
		for rk in _state(sim, "boulder")["rocks"]:
			out.append([int(rk["side"]), float(rk["lane"])])
		seen[s] = out
	var a := _sim(BOULDER, 3)
	var b := _sim(BOULDER, 3)
	for sim: MatchSim in [a, b]:
		_state(sim, "boulder")["next"] = 1
		_steps(sim, 1)
	assert_eq(_state(a, "boulder")["rocks"], _state(b, "boulder")["rocks"], "same seed, same lanes:")
	var distinct := {}
	for s in seen:
		distinct[str(seen[s])] = true
	assert_gt(distinct.size(), 2, "seeds pick different lanes: %s" % str(seen))


# ------------------------------------------------------------------ ricochets

## Two boulders head on down one lane: they meet, bounce straight back, each its own way.
func test_two_boulders_ricochet_off_each_other() -> void:
	var sim := _sim(BOULDER)
	var fr := sim.floor_rect()
	var d := _bdef(sim)
	_place(sim, Vector2(fr.position.x + 30, fr.end.y - 20), Vector2(fr.end.x - 30, fr.end.y - 20))
	var row := fr.position.y + 80
	var mid := fr.get_center().x
	var rocks := _roll_many(sim, [[Vector2(mid - 60, row), Vector2.RIGHT], [Vector2(mid + 60, row), Vector2.LEFT]])
	var ev := _steps(sim, 30)
	var ric := _of(ev, "hazard_ricochet").filter(func(e): return int(e["other"]) >= 0)
	assert_eq(ric.size(), 2, "one bounce, told for each:")
	assert_near(Vector2(rocks[0]["dir"]).x, -1.0, 0.001, "the first goes back left:")
	assert_near(Vector2(rocks[1]["dir"]).x, 1.0, 0.001, "the second back right:")
	assert_near(float(rocks[0]["speed"]), float(d["speed"]) * float(d["ricochet_speed_mult"]), 0.001, "a little slower:")
	assert_gt(Vector2(rocks[1]["pos"]).distance_to(rocks[0]["pos"]), 2.0 * float(d["radius"]), "and apart")
	# A glancing blow: one across the other's way. Both turn, both keep their own speed.
	var sim2 := _sim(BOULDER)
	_place(sim2, Vector2(fr.position.x + 30, fr.end.y - 20), Vector2(fr.end.x - 30, fr.end.y - 20))
	var c := fr.get_center()
	var r2 := _roll_many(sim2, [[c + Vector2(-60, 0), Vector2.RIGHT], [c + Vector2(4, -60), Vector2.DOWN]])
	ev = _steps(sim2, 40)
	assert_eq(_of(ev, "hazard_ricochet").filter(func(e): return int(e["other"]) >= 0).size(), 2, "they meet:")
	for rk in r2:
		assert_near(Vector2(rk["dir"]).length(), 1.0, 0.0001, "a unit way:")
	assert_true(Vector2(r2[0]["dir"]) != Vector2.RIGHT and Vector2(r2[1]["dir"]) != Vector2.DOWN, "both turned")
	# The pair can't bounce again straight away (no sticking).
	var pairs: Dictionary = _state(sim2, "boulder")["pairs"]
	assert_eq(pairs.size(), 1, "the pair's cooldown is noted:")


func test_ricochets_are_deterministic_and_roll_back() -> void:
	var hashes: Array = []
	for k in 2:
		var sim := _sim(BOULDER, 11)
		var fr := sim.floor_rect()
		var c := fr.get_center()
		_roll_many(sim, [[c + Vector2(-90, -10), Vector2.RIGHT], [c + Vector2(90, 10), Vector2.LEFT],
			[c + Vector2(6, -100), Vector2.DOWN]])
		_steps(sim, 120)
		hashes.append(sim.state_digest())
	assert_eq(hashes[0], hashes[1], "the same bounces every time:")
	# Rollback across the moment they meet.
	var sim := _sim(BOULDER, 11)
	var c2 := sim.floor_rect().get_center()
	_roll_many(sim, [[c2 + Vector2(-90, -10), Vector2.RIGHT], [c2 + Vector2(90, 10), Vector2.LEFT],
		[c2 + Vector2(6, -100), Vector2.DOWN]])
	_steps(sim, 15)
	_roll_check(sim, 60)


func test_a_ricochet_keeps_the_credit_with_who_sent_it_back() -> void:
	var sim := _sim(BOULDER, 7, "cairn", "culvert")
	var fr := sim.floor_rect()
	var c := fr.get_center()
	var b := sim.creatures[1]
	_place(sim, Vector2(fr.position.x + 30, fr.end.y - 20), c + Vector2(-110, 0))
	# Boulder 0 was sent back by fighter 0 (it spares team 0 now); it meets boulder 1 head on
	# and bounces straight back into fighter 1.
	var rocks := _roll_many(sim, [[c + Vector2(-60, 0), Vector2.RIGHT], [c + Vector2(30, 0), Vector2.LEFT]])
	rocks[0]["by"] = 0
	rocks[0]["by_team"] = sim.creatures[0].team
	rocks[0]["rev"] = 1
	var by: Array = [-1, -1]
	var at: Array = [0, 0]
	var ev: Array = []
	for i in 60:
		sim.step(PackedInt32Array([0, 0]))
		ev.append_array(sim.events)
		sim.note_credit(by, at)
	assert_true(_of(ev, "hazard_ricochet").any(func(e): return int(e["rock"]) == 0 and int(e["by"]) == 0), "it bounced, still the sender's")
	var on_b := _of(ev, "hazard_hit").filter(func(e): return int(e["who"]) == 1 and int(e["by"]) == 0)
	assert_eq(on_b.size(), 1, "it struck the other fighter, credited to the sender:")
	assert_eq(int(by[1]), 0, "note_credit gives the sender the KO credit:")
	assert_gt(b.max_hp, b.hp, "")


# ------------------------------------------------------------------ the fault line

func _start_fault(sim: MatchSim) -> Array:
	var st := _state(sim, "fault")
	st["next"] = sim.tick + 1
	return _steps(sim, 1)


func test_the_fault_cracks_then_opens_then_closes_to_exactly_the_map() -> void:
	var sim := _sim(FAULT)
	var d: Dictionary = sim.hazard_defs["fault_line"]
	var st := _state(sim, "fault")
	assert_eq(int(st["next"]), Hazards.ticks_of(d["first_seconds"]), "the first crack at first_seconds:")
	var cells0 := sim.terrain.cells.duplicate()
	var ev := _start_fault(sim)
	var warn := _of(ev, "hazard_warn")
	assert_eq(warn.size(), 1, "it warns:")
	var ticks := Hazards.ticks_of(d["warn_seconds"])
	assert_eq(int(warn[0]["ticks"]), ticks, "")
	assert_true(ticks >= 60, "a second or more (%d ticks)" % ticks)
	var plan: PackedInt32Array = st["cells"]
	assert_gt(plan.size(), 0, "a line is planned")
	# A fighter standing on the line: nothing falls during the warning.
	var c := sim.creatures[0]
	c.pos = sim.terrain.cell_center(Vector2i(plan[plan.size() / 2] % sim.terrain.cols, plan[plan.size() / 2] / sim.terrain.cols))
	ev = _steps(sim, ticks - 2)
	assert_eq(sim.terrain.cells, cells0, "the floor is the same while it cracks:")
	assert_eq(_of(ev, "fall").size(), 0, "nobody falls during the warning:")
	ev = _steps(sim, 3)
	assert_eq(_of(ev, "hazard_strike").size(), 1, "then it opens:")
	for i in plan:
		assert_eq(sim.terrain.cells[i], TerrainGrid.CHASM, "every planned cell is chasm:")
		if sim.terrain.cells[i] != TerrainGrid.CHASM:
			break
	assert_true(_of(ev, "fall").any(func(e): return int(e["who"]) == 0 and String(e["pit"]) == "chasm"), "the one on it falls in")
	# It splits the floor in two across its whole length.
	var axis := int(st["axis"])
	var t := sim.terrain
	var along := t.rows if axis == 0 else t.cols
	for k in along:
		var any := false
		for i in plan:
			if (i / t.cols if axis == 0 else i % t.cols) == k:
				any = true
				break
		assert_true(any, "the line crosses line %d of the floor" % k)
		if not any:
			break
	ev = _steps(sim, Hazards.ticks_of(d["open_seconds"]) - 2)
	assert_eq(_of(ev, "hazard_end").size(), 0, "open for open_seconds:")
	ev = _steps(sim, 3)
	assert_eq(_of(ev, "hazard_end").size(), 1, "then it closes:")
	assert_eq(sim.terrain.cells, sim.terrain.base, "back to exactly the map:")
	assert_eq(sim.terrain.cells, cells0, "")


func test_the_fault_leaves_the_maps_pieces_and_the_spawns_alone() -> void:
	for s in [1, 2, 3, 4, 5, 6, 7, 8]:
		var sim := _sim(FAULT, s)
		var t := sim.terrain
		# Map pieces everywhere along the middle rows and columns: walls, a chasm, shallows.
		for k in t.cols:
			t.cells[18 * t.cols + k] = TerrainGrid.WALL
			t.base[18 * t.cols + k] = TerrainGrid.WALL
		for k in t.rows:
			t.cells[k * t.cols + 42] = TerrainGrid.CHASM
			t.base[k * t.cols + 42] = TerrainGrid.CHASM
			t.cells[k * t.cols + 30] = TerrainGrid.SHALLOWS
			t.base[k * t.cols + 30] = TerrainGrid.SHALLOWS
		t.version += 1
		var base0 := t.base.duplicate()
		_start_fault(sim)
		var st := _state(sim, "fault")
		var d: Dictionary = sim.hazard_defs["fault_line"]
		for i in (st["cells"] as PackedInt32Array):
			assert_true(t.base[i] != TerrainGrid.WALL and t.base[i] != TerrainGrid.CHASM, "never on the map's walls or chasms")
			var at := t.cell_center(Vector2i(i % t.cols, i / t.cols))
			for side in 2:
				assert_gt(at.distance_to(sim.spawn(side)), float(d["spawn_clear"]) - 0.01, "clear of the spawns")
		_steps(sim, Hazards.ticks_of(d["warn_seconds"]) + Hazards.ticks_of(d["open_seconds"]) + 2)
		assert_eq(t.base, base0, "the map's base never changes:")
		assert_eq(t.cells, t.base, "seed %d: closed back to the map (shallows too):" % s)


func test_the_fault_is_seeded() -> void:
	var a := _sim(FAULT, 21)
	var b := _sim(FAULT, 21)
	var c := _sim(FAULT, 22)
	for sim: MatchSim in [a, b, c]:
		_start_fault(sim)
	assert_eq(_state(a, "fault")["cells"], _state(b, "fault")["cells"], "same seed, same line:")
	assert_true(_state(a, "fault")["cells"] != _state(c, "fault")["cells"], "another seed, another")


# ------------------------------------------------------------------ rollback

func _roll_check(sim: MatchSim, ticks: int) -> void:
	var snap := sim.snapshot()
	var hashes: Array = []
	for i in ticks:
		sim.step(PackedInt32Array([SimDefs.IN_RIGHT if i % 20 < 10 else SimDefs.IN_HEAVY, SimDefs.IN_LEFT]))
		hashes.append(sim.state_hash())
	sim.restore(snap)
	for i in ticks:
		sim.step(PackedInt32Array([SimDefs.IN_RIGHT if i % 20 < 10 else SimDefs.IN_HEAVY, SimDefs.IN_LEFT]))
		assert_eq(sim.state_hash(), hashes[i], "tick %d after the restore:" % i)
		if sim.state_hash() != hashes[i]:
			return


func test_rollback_mid_roll_and_mid_open() -> void:
	var sim := _sim({"hazards": ["rolling_boulder", "fault_line"]})
	_state(sim, "boulder")["next"] = sim.tick + 1
	_steps(sim, 60)
	_roll_check(sim, 200)  # the warning ends, it rolls, hits, goes
	_start_fault(sim)
	_steps(sim, 100)
	_roll_check(sim, 200)  # it opens, someone may fall
	_steps(sim, 400)
	_roll_check(sim, 200)  # it closes inside the window
	var digest_a := sim.state_digest()
	var plain := MatchFactory.versus("cairn", "culvert")
	assert_true(plain.hazards.is_empty(), "no hazard state without the mutator")
	assert_true(digest_a != "", "")


func test_the_same_seed_plays_the_same_match() -> void:
	var hashes: Array = []
	for k in 2:
		var sim := _sim({"hazards": ["rolling_boulder", "fault_line"]}, 5)
		for st in sim.hazards:
			st["next"] = 30
		for i in 1200:
			sim.step(PackedInt32Array([SimDefs.IN_RIGHT if (i / 30) % 2 == 0 else SimDefs.IN_HEAVY, SimDefs.IN_LEFT]))
		hashes.append(sim.state_digest())
	assert_eq(hashes[0], hashes[1], "same seed, same match:")


# ------------------------------------------------------------------ the CPU

func test_cpu_steps_out_of_the_boulder_lane() -> void:
	for level in [-1, 0, 1]:  # -1: a control that stands still
		var sim := _sim(BOULDER)
		var cpu := CpuController.new(0, maxi(level, 0), 3)
		var c := sim.creatures[0]
		var fr := sim.floor_rect()
		_place(sim, Vector2(fr.get_center().x, fr.position.y + 120), Vector2(fr.end.x - 30, fr.end.y - 20))
		var st := _state(sim, "boulder")
		st["next"] = 1 << 30
		st["phase"] = Hazards.WARN
		st["t"] = 0
		st["rocks"] = [Hazards._new_rock(fr, 0, c.pos.y - fr.position.y, float(_bdef(sim)["radius"]), float(_bdef(sim)["speed"]))]
		var ev: Array = []
		for i in 400:
			sim.step(PackedInt32Array([cpu.bits(sim) if level >= 0 else 0, 0]))
			ev.append_array(sim.events)
			if int(st["phase"]) == Hazards.IDLE and i > 100:
				break
		var hit := _of(ev, "hazard_hit").filter(func(e): return int(e["who"]) == 0).size()
		if level < 0:
			assert_eq(hit, 1, "standing still in the lane, it's struck:")
		else:
			assert_eq(hit, 0, "level %d stepped out of the lane" % level)


## After a ricochet a boulder's way is its new one: a CPU in that new way steps out of it.
func test_cpu_steps_out_of_a_turned_boulders_new_way() -> void:
	for level in [-1, 1, 3]:  # -1: a control that stands still
		var sim := _sim(BOULDER)
		var cpu := CpuController.new(0, maxi(level, 0), 5)
		var c := sim.creatures[0]
		var fr := sim.floor_rect()
		_place(sim, fr.get_center() + Vector2(-40, 30), Vector2(fr.end.x - 30, fr.position.y + 20))
		# Coming at it on a diagonal, having just bounced (no lane was ever shown on this way).
		var way := Vector2(1, 1).normalized()
		var rk := _roll(sim, c.pos - way * 150.0, way)
		rk["turned"] = sim.tick
		rk["bounces"] = 1
		var ev: Array = []
		for i in 120:
			sim.step(PackedInt32Array([cpu.bits(sim) if level >= 0 else 0, 0]))
			ev.append_array(sim.events)
		var hit := _of(ev, "hazard_hit").filter(func(e): return int(e["who"]) == 0).size()
		if level < 0:
			assert_eq(hit, 1, "standing still in its new way, it's struck:")
		elif level == 1:
			assert_eq(hit, 0, "Normal stepped out of its new way")
		else:
			var sent := _of(ev, "hazard_reverse").size()
			assert_true(hit == 0 or sent > 0, "Rage stepped out or sent it back (hit %d, sent %d)" % [hit, sent])


func test_hard_cpu_sends_the_boulder_back() -> void:
	var sent := 0
	for k in 3:
		var sim := _sim(BOULDER, 7 + k)
		var cpu := CpuController.new(0, 3, 3 + k)
		var c := sim.creatures[0]
		var fr := sim.floor_rect()
		_place(sim, Vector2(fr.position.x + 200, fr.position.y + 120), Vector2(fr.position.x + 40, fr.end.y - 20))
		_roll(sim, Vector2(c.pos.x + 220, c.pos.y), Vector2.LEFT)
		var ev: Array = []
		for i in 200:
			sim.step(PackedInt32Array([cpu.bits(sim), 0]))
			ev.append_array(sim.events)
		if _of(ev, "hazard_reverse").any(func(e): return int(e["by"]) == 0):
			sent += 1
	assert_gt(sent, 0, "a Rage CPU meets a boulder with a heavy (%d of 3)" % sent)


func test_cpu_gets_off_the_crack() -> void:
	for level in [0, 3]:
		var sim := _sim(FAULT, 7)
		var cpu := CpuController.new(0, level, 3)
		var c := sim.creatures[0]
		_start_fault(sim)
		var st := _state(sim, "fault")
		var plan: PackedInt32Array = st["cells"]
		var mid := plan[plan.size() / 2]
		c.pos = sim.terrain.cell_center(Vector2i(mid % sim.terrain.cols, mid / sim.terrain.cols))
		sim.creatures[1].pos = sim.floor_rect().end - Vector2(20, 20)
		var ev: Array = []
		for i in Hazards.ticks_of(sim.hazard_defs["fault_line"]["warn_seconds"]) + 30:
			sim.step(PackedInt32Array([cpu.bits(sim), 0]))
			ev.append_array(sim.events)
		assert_eq(_of(ev, "fall").filter(func(e): return int(e["who"]) == 0).size(), 0,
			"level %d off the crack before it opens" % level)


# ------------------------------------------------------------------ the menus

func test_both_are_mutators_and_arena_option_rows() -> void:
	var table := Daily.mutator_table()
	for id in ["rolling_boulder", "fault_line"]:
		assert_true(table.has(id), "%s is a mutator" % id)
		assert_eq(table[id]["hazards"], [id], "")
		assert_true(id in Hazards.ids(), "%s gets an Arena options row" % id)
		assert_true(String(Hazards.table()[id].get("desc", "")) != "", "and a description")
	var m := {}
	MatchSim.merge_mutator(m, table["rolling_boulder"])
	MatchSim.merge_mutator(m, table["fault_line"])
	var names := Daily.mutator_names(m)
	assert_true("Rolling boulder" in names and "Fault line" in names, "named: " + str(names))
