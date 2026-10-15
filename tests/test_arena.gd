extends TestCase
## Arena maps: fixed pieces on the terrain grid. Walls stop walking, dashes and shots
## and bounce knockback; fences stop bodies only; chasms never heal; shallows slow
## walking; a smashed wall rebuilds (not under anyone); it all survives a rollback.

const R := SimDefs.IN_RIGHT
const L := SimDefs.IN_LEFT


func _on(map: String, left := "cairn", right := "culvert") -> MatchSim:
	var was: String = MatchFactory.arena
	MatchFactory.arena = map
	var sim := MatchFactory.versus(left, right)
	MatchFactory.arena = was
	return sim


## A match on a map built here: pieces laid straight on the stadium's grid.
func _with(pieces: Array, left := "cairn", right := "culvert") -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.terrain.load_map({"pieces": pieces})
	return sim


func _saw(sim: MatchSim, kind: String) -> bool:
	for e in sim.events:
		if e["type"] == kind:
			return true
	return false


func test_quarry_lays_two_rubble_walls_and_the_stadium_none() -> void:
	var sim := _on("quarry")
	assert_eq(sim.arena_id, "quarry", "arena id:")
	assert_eq(sim.terrain.get_cell(Vector2i(20, 10)), TerrainGrid.WALL, "left wall:")
	assert_eq(sim.terrain.get_cell(Vector2i(63, 30)), TerrainGrid.WALL, "right wall:")
	assert_eq(sim.terrain.get_cell(Vector2i(20, 2)), TerrainGrid.INTACT, "gap above the wall:")
	assert_eq(sim.terrain.get_base(Vector2i(20, 10)), TerrainGrid.WALL, "the wall is the map's own state:")
	assert_eq(sim.terrain.count(TerrainGrid.WALL), 2 * 2 * 26, "wall cells:")
	var plain := _on("stadium")
	assert_eq(plain.terrain.count(TerrainGrid.WALL), 0, "the stadium has no walls")
	assert_true(sim.terrain.is_walkable(sim.terrain.get_cell(sim.terrain.world_to_cell(sim.spawn(0)))),
		"the left spawn is on open floor")


func test_rows_lay_pieces_by_character() -> void:
	var t := TerrainGrid.new()
	t.load_map({"rows": ["..#F", "X~*."]})
	assert_eq(t.get_cell(Vector2i(2, 0)), TerrainGrid.WALL, "#:")
	assert_eq(t.get_cell(Vector2i(3, 0)), TerrainGrid.FENCE, "F:")
	assert_eq(t.get_cell(Vector2i(0, 1)), TerrainGrid.CHASM, "X:")
	assert_eq(t.get_cell(Vector2i(1, 1)), TerrainGrid.SHALLOWS, "~:")
	assert_eq(t.get_cell(Vector2i(2, 1)), TerrainGrid.BRUSH, "*:")
	assert_eq(t.get_cell(Vector2i(0, 0)), TerrainGrid.INTACT, ".:")


func test_walking_stops_at_a_wall_and_slides_along_it() -> void:
	var sim := _on("quarry")
	var c := sim.creatures[0]
	var wall_x := sim.terrain.cell_rect(Vector2i(20, 10)).position.x  # the wall is cells 20-21
	c.pos = Vector2(wall_x + 16.0 + 40.0, sim.terrain.cell_center(Vector2i(20, 15)).y)
	run(sim, L, 90)
	assert_true(c.pos.x < wall_x + 16.0 + 40.0 - 1.0, "walked toward the wall")
	assert_lt(absf(c.pos.x - (wall_x + 16.0 + c.radius)), 1.0, "stopped against the wall's right face:")
	var y0 := c.pos.y
	run(sim, L | SimDefs.IN_UP, 30)
	assert_lt(c.pos.y, y0 - 10.0, "slides up along the wall while pushing into it:")
	assert_true(c.pos.x >= wall_x + 16.0 + c.radius - 0.01, "still outside the wall")


func test_walking_never_ends_inside_a_wall_from_any_side() -> void:
	var sim := _on("quarry")
	var c := sim.creatures[0]
	var wall := sim.terrain.cell_rect(Vector2i(20, 5)).merge(sim.terrain.cell_rect(Vector2i(21, 30)))
	for dir_bits in [R, L, SimDefs.IN_UP, SimDefs.IN_DOWN, R | SimDefs.IN_UP, L | SimDefs.IN_DOWN]:
		c.pos = wall.get_center() + Vector2(-30, 0) if dir_bits & R else wall.get_center() + Vector2(30, 0)
		if dir_bits & SimDefs.IN_UP and not dir_bits & R:
			c.pos = Vector2(wall.get_center().x, wall.end.y + 30)
		if dir_bits & SimDefs.IN_DOWN and not dir_bits & L:
			c.pos = Vector2(wall.get_center().x, wall.position.y - 30)
		run(sim, dir_bits, 120)
		var inside := wall.grow(-0.5).has_point(c.pos)
		assert_false(inside, "ended inside the wall walking with bits %d" % dir_bits)


func test_knockback_bounces_off_a_wall_like_the_arena_edge() -> void:
	var sim := _on("quarry")
	var c := sim.creatures[0]
	var wall_x := sim.terrain.cell_rect(Vector2i(20, 10)).position.x
	c.pos = Vector2(wall_x + 60.0, sim.terrain.cell_center(Vector2i(20, 15)).y)
	c._set_state(CreatureSim.State.HITSTUN)
	c.stun = 40
	c.knock_vel = Vector2(-9.0, 0.0)
	var bounced := false
	for i in 12:
		run(sim, 0, 1)
		bounced = bounced or _saw(sim, "bounce")
	assert_true(bounced, "a hard knockback into the wall bounces")
	assert_true(c.knock_vel.x > 0.0 or c.pos.x > wall_x + 16.0 + c.radius - 0.5, "came back off the wall")


func test_a_dash_stops_at_a_wall() -> void:
	var sim := _on("quarry")
	var c := sim.creatures[0]
	var wall_x := sim.terrain.cell_rect(Vector2i(20, 10)).position.x
	c.pos = Vector2(wall_x + 40.0, sim.terrain.cell_center(Vector2i(20, 15)).y)
	c.facing = Vector2.LEFT
	tap(sim, SimDefs.IN_DODGE | L, 40)
	assert_true(c.pos.x >= wall_x + 16.0 + c.radius - 0.5, "the dodge roll stops at the wall's face")


func test_a_shot_stops_at_a_wall_but_not_at_a_fence() -> void:
	var walls := _with([{"kind": "wall", "rect": [50, 0, 2, 36]}], "hissy", "cairn")
	var fences := _with([{"kind": "fence", "rect": [50, 0, 2, 36]}], "hissy", "cairn")
	for sim: MatchSim in [walls, fences]:
		var h: CreatureSim = sim.creatures[0]
		var foe: CreatureSim = sim.creatures[1]
		h.pos = sim.terrain.cell_center(Vector2i(45, 18))
		foe.pos = sim.terrain.cell_center(Vector2i(55, 18))
		h.facing = Vector2.RIGHT
		foe.hp = foe.max_hp
	var spit: Dictionary = walls.creatures[0].def["moves"]["skill_1"]
	assert_true(spit.has("projectile"), "Venom Spit is a projectile")
	for sim: MatchSim in [walls, fences]:
		tap(sim, SimDefs.IN_SKILL1, 90)
	assert_eq(walls.creatures[1].hp, walls.creatures[1].max_hp, "the wall took the spit:")
	assert_lt(fences.creatures[1].hp, fences.creatures[1].max_hp, "the spit flew over the fence:")


func test_a_lob_flies_over_a_wall() -> void:
	var sim := _with([{"kind": "wall", "rect": [50, 0, 2, 36]}], "barkley", "cairn")
	var b := sim.creatures[0]
	var foe := sim.creatures[1]
	b.pos = sim.terrain.cell_center(Vector2i(47, 18))
	foe.pos = sim.terrain.cell_center(Vector2i(52, 18))
	b.facing = Vector2.RIGHT
	var bomb: Dictionary = b.def["moves"]["skill_2"]
	assert_true(bool(bomb["projectile"].get("lob", false)), "Pinecone Bomb is a lob")
	tap(sim, SimDefs.IN_SKILL2, 120)
	assert_lt(foe.hp, foe.max_hp, "the pinecone landed past the wall:")


func test_a_chasm_swallows_walkers_pushed_in_and_never_heals() -> void:
	var sim := _with([{"kind": "chasm", "rect": [40, 10, 4, 4]}])
	var c := sim.creatures[0]
	var pit := sim.terrain.cell_center(Vector2i(41, 11))
	c.pos = pit + Vector2(-30, 0)
	run(sim, R, 60)
	assert_true(c.pos.x < pit.x - 11.0, "walking refuses to step into the chasm (stops at its edge)")
	c.pos = pit
	run(sim, 0, 1)
	assert_eq(c.state, CreatureSim.State.FALLING, "standing over the chasm falls:")
	run(sim, 0, CreatureSim.FALL_TICKS + 5)
	assert_true(sim.terrain.is_walkable(sim.terrain.get_cell(sim.terrain.world_to_cell(c.pos))),
		"respawned on walkable ground")
	for i in TerrainGrid.HEAL_TICKS * 2 + 5:
		sim.terrain.tick()
	assert_eq(sim.terrain.get_cell(Vector2i(41, 11)), TerrainGrid.CHASM, "a chasm never heals:")


func test_shallows_slow_walking() -> void:
	var dry := MatchFactory.versus("cairn", "culvert")
	var wet := _with([{"kind": "shallows", "rect": [0, 0, 84, 36]}])
	for sim: MatchSim in [dry, wet]:
		sim.creatures[0].pos = sim.terrain.cell_center(Vector2i(20, 18))
		run(sim, R, 60)
	var d_dry := dry.creatures[0].pos.x - dry.terrain.cell_center(Vector2i(20, 18)).x
	var d_wet := wet.creatures[0].pos.x - wet.terrain.cell_center(Vector2i(20, 18)).x
	assert_lt(d_wet, d_dry * 0.75, "shallows: wet %.1f vs dry %.1f" % [d_wet, d_dry])
	assert_gt(d_wet, d_dry * 0.4, "but still walking")


func test_a_smashed_wall_rebuilds_after_the_heal_time_but_not_under_a_body() -> void:
	var sim := _on("quarry")
	var c := sim.creatures[0]
	var cell := Vector2i(20, 15)
	assert_true(sim.terrain.smash(cell), "smashes a wall cell")
	assert_eq(sim.terrain.get_cell(cell), TerrainGrid.CRACKED, "a smashed wall is cracked floor:")
	assert_false(sim.terrain.smash(cell), "only a wall smashes")
	c.pos = sim.terrain.cell_center(cell)
	for i in TerrainGrid.HEAL_TICKS + 5:
		sim.terrain.tick(sim.cell_occupied)
	assert_eq(sim.terrain.get_cell(cell), TerrainGrid.CRACKED, "waits while someone stands there:")
	c.pos = sim.terrain.cell_center(Vector2i(40, 15))
	sim.terrain.tick(sim.cell_occupied)
	assert_eq(sim.terrain.get_cell(cell), TerrainGrid.WALL, "rebuilds once they leave:")


func test_a_body_inside_a_wall_is_pushed_out() -> void:
	var sim := _on("quarry")
	var c := sim.creatures[0]
	var wall := sim.terrain.cell_rect(Vector2i(20, 15))
	c.pos = wall.get_center() + Vector2(2, 0)
	run(sim, 0, 1)
	assert_false(sim.terrain.solid_at(c.pos), "pushed out of the wall")
	assert_false(sim.terrain.cell_rect(Vector2i(20, 15)).merge(sim.terrain.cell_rect(Vector2i(21, 15))).grow(c.radius - 0.5).has_point(c.pos),
		"and clear of it")


func test_the_map_survives_a_rollback() -> void:
	var sim := _on("quarry")
	sim.terrain.smash(Vector2i(20, 15))
	run(sim, R, 5, L)
	var s := sim.snapshot()
	var d := sim.state_digest()
	run(sim, L, 30, R)
	sim.restore(s)
	assert_eq(sim.state_digest(), d, "restore puts the map back:")
	assert_eq(sim.terrain.get_cell(Vector2i(20, 15)), TerrainGrid.CRACKED, "the smashed cell:")
	assert_eq(sim.terrain.get_cell(Vector2i(20, 16)), TerrainGrid.WALL, "and its neighbour:")
	var other := _on("stadium")
	run(other, R, 5, L)
	assert_true(other.state_digest() != d, "a different arena is a different state")


func test_every_map_loads_with_walkable_spawns_and_pads() -> void:
	for id in ArenaMap.IDS:
		var sim := _on(id)
		assert_eq(sim.arena_id, id, "arena id:")
		for side in 2:
			var sp := sim.spawn(side)
			assert_true(sim.terrain.is_walkable(sim.terrain.get_cell(sim.terrain.world_to_cell(sp))),
				"%s: spawn %d on walkable floor" % [id, side])
			assert_false(sim.terrain.body_blocked(sp, 10.0), "%s: spawn %d clear of pieces" % [id, side])
		var was: String = MatchFactory.arena
		MatchFactory.arena = id
		var t := TeamSim.new([["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]], 3,
			TeamSim.load_rules(TeamSim.DEATHMATCH_PATH))
		MatchFactory.arena = was
		for side in 2:
			for k in 3:
				var pad := t.pad_point(side, k)
				assert_true(t.sim.terrain.is_walkable(t.sim.terrain.get_cell(t.sim.terrain.world_to_cell(pad))),
					"%s: pad %d/%d on walkable floor" % [id, side, k])
		for c in t.sim.creatures:
			assert_false(t.sim.terrain.body_blocked(c.pos, c.radius), "%s: a fighter starts clear of pieces" % id)


func test_the_same_inputs_on_quarry_give_the_same_match() -> void:
	var a := SimCheck._quarry(7, 600)
	var b := SimCheck._quarry(7, 600)
	assert_eq(a, b, "quarry fingerprint:")
