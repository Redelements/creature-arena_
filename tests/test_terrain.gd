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


func test_healing_walks_only_the_damaged_cells_and_survives_a_restore() -> void:
	# tick() keeps the cells that differ from the base and walks only those, found again
	# whenever version moves: damage added later heals too, and a grid restored wholesale
	# (as rollback does: cells, timers, base and a version bump) heals exactly the same.
	var a := TerrainGrid.new()
	a.crack_circle(a.cell_center(Vector2i(20, 10)), 20.0)
	for i in 100:
		a.tick()
	a.set_cell(Vector2i(40, 20), TerrainGrid.HOLE)  # fresh damage after the walk began
	var b := TerrainGrid.new()
	b.cells = a.cells.duplicate()
	b.timers = a.timers.duplicate()
	b.base = a.base.duplicate()
	b.version = a.version + 1
	for i in TerrainGrid.HEAL_TICKS + 1:
		a.tick()
		b.tick()
	assert_eq(a.get_cell(Vector2i(20, 10)), TerrainGrid.INTACT, "the cracks healed:")
	assert_eq(a.get_cell(Vector2i(40, 20)), TerrainGrid.CRACKED, "the later hole healed a step:")
	assert_true(a.cells == b.cells and a.timers == b.timers, "the restored grid healed the same")
	assert_eq(a._damaged.size(), 1, "one damaged cell left to walk:")


func test_a_sunk_cell_stays_a_chasm_but_is_not_the_map_s_own() -> void:
	# Sinkhole's rings and the Floor of pits mutator sink cells for the match: `base` turns
	# CHASM so healing never refills them, while `map_base` keeps what the map (and its
	# art) put there, so the view knows to draw them.
	var t := TerrainGrid.new()
	t.load_map({"pieces": [{"kind": "chasm", "rect": [0, 0, 2, 2]}]})
	var map_pit := Vector2i(1, 1)
	var sunk := Vector2i(10, 10)
	t.sink(sunk)
	assert_eq(t.get_cell(sunk), TerrainGrid.CHASM, "sunk:")
	assert_eq(int(t.base[sunk.y * t.cols + sunk.x]), TerrainGrid.CHASM, "it heals back to a chasm (never refills):")
	assert_eq(int(t.map_base[sunk.y * t.cols + sunk.x]), TerrainGrid.INTACT, "but the map had floor there:")
	assert_eq(int(t.map_base[map_pit.y * t.cols + map_pit.x]), TerrainGrid.CHASM, "the map's own chasm is the map's:")
	for i in 2000:
		t.tick()
	assert_eq(t.get_cell(sunk), TerrainGrid.CHASM, "still sunk after a long heal:")


## After a fall a fighter is put down with floor all round it, not at the pit's lip.
func test_nearest_solid_can_ask_for_clear_floor_round_it() -> void:
	var t := TerrainGrid.new()
	for x in range(18, 23):
		for y in range(10, 15):
			t.set_cell(Vector2i(x, y), TerrainGrid.HOLE)
	var p := t.cell_center(Vector2i(22, 12))
	assert_eq(t.world_to_cell(t.nearest_solid(p)), Vector2i(23, 12), "the lip, when any floor will do:")
	assert_eq(t.world_to_cell(t.nearest_solid(p, 1)), Vector2i(24, 12), "one cell in, with room all round:")
	# Nowhere has room: the closest walkable cell is still the answer.
	var tiny := TerrainGrid.new()
	for x in range(0, tiny.cols):
		for y in range(0, tiny.rows):
			if (x + y) % 2 == 0:
				tiny.set_cell(Vector2i(x, y), TerrainGrid.HOLE)
	var q := tiny.cell_center(Vector2i(4, 4))
	assert_eq(tiny.nearest_solid(q, 1), tiny.nearest_solid(q), "falls back to any floor")
