extends TestCase
## Maps of any size: a map's "size" [cols, rows] sets the grid, the floor's edges, the
## default spawns and the projectiles' walls, and a match on one saves and restores exactly.

const BIG := {"id": "test_big", "name": "Test Big", "ground": "dirt", "size": [252, 48],
	"pieces": [{"kind": "wall", "rect": [200, 10, 2, 20]}]}


func _big_sim() -> MatchSim:
	ArenaMap._cache["test_big"] = BIG
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.set_arena("test_big")
	sim.creatures[0].pos = sim.spawn(0)
	sim.creatures[1].pos = sim.spawn(1)
	return sim


func test_the_grid_and_floor_follow_the_map_size() -> void:
	var sim := _big_sim()
	assert_eq(sim.terrain.cols, 252, "cols:")
	assert_eq(sim.terrain.rows, 48, "rows:")
	var fr := sim.floor_rect()
	assert_eq(fr.size, Vector2(252 * 8, 48 * 8), "floor size:")
	assert_eq(sim.arena_size(), SimDefs.arena_size_of(252, 48), "stadium size:")
	assert_eq(sim.terrain.get_cell(Vector2i(200, 12)), TerrainGrid.WALL, "a piece far out on the big grid")
	# the stadium-sized maps are untouched
	var small := MatchFactory.versus("cairn", "culvert")
	assert_eq(small.floor_rect(), SimDefs.floor_rect(), "the stadium keeps its floor")


func test_spawns_sit_at_each_end_of_a_big_map() -> void:
	var sim := _big_sim()
	var fr := sim.floor_rect()
	assert_lt(sim.spawn(0).x, fr.position.x + 100.0, "left side starts at the left end:")
	assert_gt(sim.spawn(1).x, fr.end.x - 100.0, "right side starts at the right end:")


func test_fighters_walk_the_whole_big_floor() -> void:
	var sim := _big_sim()
	var c := sim.creatures[1]
	c.pos = Vector2(sim.floor_rect().end.x - 300.0, sim.floor_rect().get_center().y)
	run(sim, 0, 400, SimDefs.IN_RIGHT)
	assert_gt(c.pos.x, SimDefs.floor_rect().end.x + 200.0, "past where the stadium's wall would be:")
	assert_lt(c.pos.x, sim.floor_rect().end.x, "but not past this map's wall:")


func test_a_big_map_match_rolls_back_exactly() -> void:
	var sim := _big_sim()
	sim.creatures[0].pos = Vector2(1200, 200)
	sim.creatures[1].pos = Vector2(1240, 200)
	var snap := sim.snapshot()
	var digest := sim.state_digest()
	var inputs: Array = []
	for i in 240:
		inputs.append(PackedInt32Array([SimDefs.IN_LIGHT if i % 9 == 0 else SimDefs.IN_RIGHT, SimDefs.IN_HEAVY if i % 30 == 0 else 0]))
	for b in inputs:
		sim.step(b)
	var after := sim.state_digest()
	sim.restore(snap)
	assert_eq(sim.state_digest(), digest, "restored to the start")
	for b in inputs:
		sim.step(b)
	assert_eq(sim.state_digest(), after, "and the same match plays out again")


func test_team_battles_play_on_a_big_map() -> void:
	ArenaMap._cache["test_big"] = BIG
	var t := TeamSim.new([["cairn", "culvert", "craglash"], ["culvert", "cairn", "barkley"]], 3, {"arena": "test_big", "time_seconds": 30})
	assert_eq(t.sim.terrain.cols, 252, "the team battle's grid is the map's:")
	for c in t.sim.creatures:
		assert_true(t.sim.floor_rect().has_point(c.pos), "everyone starts on the floor")
	for i in 120:
		t.step(PackedInt32Array([0, 0, 0, 0, 0, 0]))
