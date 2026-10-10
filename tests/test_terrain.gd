extends TestCase
## Terrain grid: damage steps, healing, and finding solid ground.


func test_damage_steps_intact_to_cracked_to_hole() -> void:
	var t := TerrainGrid.new()
	var c := Vector2i(10, 10)
	t.damage_cell(c, 1)
	assert_eq(t.get_cell(c), TerrainGrid.CRACKED, "after one hit:")
	t.damage_cell(c, 1)
	assert_eq(t.get_cell(c), TerrainGrid.HOLE, "after two hits:")
	t.damage_cell(c, 5)
	assert_eq(t.get_cell(c), TerrainGrid.HOLE, "holes don't go deeper:")


func test_cells_heal_one_step_at_a_time() -> void:
	var t := TerrainGrid.new()
	var c := Vector2i(3, 4)
	t.set_cell(c, TerrainGrid.HOLE)
	for i in TerrainGrid.HEAL_TICKS:
		t.tick()
	assert_eq(t.get_cell(c), TerrainGrid.CRACKED, "hole heals to cracked:")
	for i in TerrainGrid.HEAL_TICKS:
		t.tick()
	assert_eq(t.get_cell(c), TerrainGrid.INTACT, "cracked heals to intact:")


func test_fresh_damage_restarts_healing() -> void:
	var t := TerrainGrid.new()
	var c := Vector2i(5, 5)
	t.damage_cell(c, 1)
	for i in TerrainGrid.HEAL_TICKS - 10:
		t.tick()
	t.damage_cell(c, 0)  # no-op amounts are ignored
	t.damage_cell(c, 1)  # turns it into a hole and restarts the clock
	for i in 20:
		t.tick()
	assert_eq(t.get_cell(c), TerrainGrid.HOLE, "still a hole:")


func test_damage_circle_core_becomes_holes() -> void:
	var t := TerrainGrid.new()
	var center := t.cell_center(Vector2i(20, 12))
	t.damage_circle(center, 26.0, 10.0)
	assert_eq(t.get_cell(Vector2i(20, 12)), TerrainGrid.HOLE, "centre:")
	assert_eq(t.get_cell(Vector2i(22, 12)), TerrainGrid.CRACKED, "ring:")
	assert_eq(t.get_cell(Vector2i(30, 12)), TerrainGrid.INTACT, "outside:")


func test_nearest_solid_finds_the_closest_edge() -> void:
	var t := TerrainGrid.new()
	for x in range(18, 23):
		for y in range(10, 15):
			t.set_cell(Vector2i(x, y), TerrainGrid.HOLE)
	var p := t.cell_center(Vector2i(22, 12))
	var out := t.nearest_solid(p)
	assert_eq(t.world_to_cell(out), Vector2i(23, 12), "nearest solid cell:")


func test_out_of_bounds_reads_as_solid() -> void:
	var t := TerrainGrid.new()
	assert_eq(t.get_cell(Vector2i(-1, 0)), TerrainGrid.INTACT, "left of grid:")
	assert_eq(t.get_cell(Vector2i(0, 999)), TerrainGrid.INTACT, "below grid:")
