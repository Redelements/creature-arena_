extends TestCase
## The Quarry Bowl on bought tiles (the "rock" set: Mountains scree and its tan cliff face, Set 1
## tan dirt and cobbles, Desert v2 packed earth, ledge and rock stacks): the cut has its fills,
## the lane blob and the earth blob9, the scene has ragged lanes and a rounded middle as
## terrains with a ledge along its south side, cobbled corners as patches, rock-stack walls
## with rubble, and the map plays as it did: ArenaView is tiled there, a smashed wall tile
## shows its rocks, a crack sets an overlay cell.

const MANIFEST := "res://assets/tiles/rock_manifest.json"
const GROUND := "res://assets/tiles/rock_ground.tres"
const SCENE := "res://assets/arenas/quarry.tscn"


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _at(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


func _terrain_id(ts: TileSet, name: String) -> int:
	for i in ts.get_terrains_count(0):
		if ts.get_terrain_name(0, i) == name:
			return i
	return -1


func test_the_rock_cut_has_its_fills_terrains_and_overlay() -> void:
	var man := _manifest()
	assert_eq(man["set"], "rock")
	assert_eq(man["ground"]["fills"]["stone"].size(), 16, "a 4 x 4 stone fill")
	assert_eq(man["ground"]["fills"]["cobble"].size(), 4, "a 2 x 2 cobble fill")
	var terrains: Dictionary = man["ground"]["terrains"]
	var lane := {}
	for t in terrains["lane"]:
		lane[str(t["sides"].map(func(x): return int(x)))] = true
	assert_eq(lane.size(), 16, "the lane blob covers every side combination")
	assert_eq(terrains["patch"].size(), 9, "the middle patch is a blob9: corners, edges, middle")
	assert_eq(man["walls"]["rock"]["roles"]["rubble"].size(), 4, "rock heaps for smashed wall tiles")
	for k in ["ledge_l", "ledge_r"]:
		assert_true(man["decor"].has(k), "the middle's south ledge: %s" % k)
	assert_false(man["pieces"].has("boulder"), "no loose boulder tiles on the walls")
	assert_eq(int(man["overlay"]["ids"]["wall_top"]), ArenaView.OV_WALL_TOP, "the overlay ids are ArenaView's")
	var ts: TileSet = load(GROUND)
	assert_eq(ts.tile_size, Vector2i(32, 32))
	assert_eq(ts.get_terrains_count(0), 2, "the lane and the patch")
	assert_true(ResourceLoader.exists("res://assets/tiles/rock_overlay.tres"), "the overlay set exists")


func test_the_quarry_scene_has_lanes_a_raised_middle_and_rock_walls() -> void:
	var scene: PackedScene = load(SCENE)
	var root := scene.instantiate()
	var ground := root.get_node("Ground") as TileMapLayer
	assert_eq(ground.get_used_cells().size(), 42 * 18, "the fill: 42 x 18 tiles of floor, no ring")
	var man := _manifest()
	var fills: Dictionary = man["ground"]["fills"]
	var stone: Array = fills["stone"].map(_at)
	var cobble: Array = fills["cobble"].map(_at)
	assert_true(ground.get_cell_atlas_coords(Vector2i(20, 3)) in stone, "the open floor is sandstone")
	assert_true(ground.get_cell_atlas_coords(Vector2i(20, 8)) in stone, "scree under the middle patch: its ragged edge shows it")
	assert_eq(ground.get_cell_source_id(Vector2i(-1, 9)), -1, "no ring: the stands' hoardings sit past the floor")
	assert_true(ground.get_cell_atlas_coords(Vector2i(1, 1)) in cobble, "a cobbled corner")
	assert_true(ground.get_cell_atlas_coords(Vector2i(40, 16)) in cobble, "and the opposite one")
	assert_eq((root.get_node("Grass") as TileMapLayer).get_used_cells().size(), 0, "no grass in the quarry")
	var ts: TileSet = load(GROUND)
	var lane := root.get_node("Lane") as TileMapLayer
	assert_eq(lane.get_used_cells().size(), 2 * 2 * 18, "two lanes, two tiles wide, top to bottom")
	for c in [Vector2i(11, 9), Vector2i(12, 0), Vector2i(29, 17), Vector2i(30, 2)]:
		assert_eq(lane.get_cell_tile_data(c).terrain, _terrain_id(ts, "lane"), "a ragged lane at %s" % c)
	var patch := root.get_node("Patch") as TileMapLayer
	assert_eq(patch.get_used_cells().size(), 24, "the middle patch over the old rect [18, 7, 6, 4]")
	assert_eq(patch.get_cell_tile_data(Vector2i(20, 8)).terrain, _terrain_id(ts, "patch"), "the trampled middle")
	var corner: Array = man["ground"]["terrains"]["patch"].filter(func(t): return t["sides"].map(func(x): return int(x)) == [0, 1, 0, 1])
	assert_eq(patch.get_cell_atlas_coords(Vector2i(18, 7)), _at(corner[0]["at"]), "a rounded top-left corner")
	var decor := root.get_node("Decor")
	assert_eq(decor.get_child_count(), 2, "the ledge in two runs along the patch's south side")
	for s in decor.get_children():
		var sp := s as Sprite2D
		assert_true(sp.position.y > 10 * 32 and sp.position.y < 11 * 32, "%s overlaps the patch's bottom row" % sp.name)
	assert_eq((root.get_node("Pieces") as TileMapLayer).get_used_cells().size(), 0, "no boulder tiles: the walls are sprites")
	# the walls at cells [20, 5, 2, 26] and [62, 5, 2, 26]: tile columns 10 and 31, rows 2..15,
	# and four 4 x 2 outcrops (two tiles each)
	var walls := root.get_node("Walls")
	assert_true(walls.y_sort_enabled, "a run's near stacks overlap the far ones")
	assert_eq(walls.get_child_count(), 28 + 4 * 2, "a rock stack on every wall tile")
	assert_eq(root.get_node("Rubble").get_child_count(), 28 + 4 * 2, "and its rubble under it")
	root.free()


func test_the_quarry_plays_as_before_and_breaks_over_the_tiles() -> void:
	var was: String = MatchFactory.arena
	MatchFactory.arena = "quarry"
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	assert_eq(sim.terrain.get_cell(Vector2i(20, 10)), TerrainGrid.WALL, "the left wall still stands in the sim")
	assert_eq(sim.terrain.get_cell(Vector2i(63, 30)), TerrainGrid.WALL, "and the right one")
	var v := ArenaView.new()
	v.ground = "stone"
	v.arena_id = "quarry"
	v.set_terrain(sim.terrain)
	assert_true(v.tiled(), "the Quarry draws from tiles")
	assert_eq(v.ground, "stone", "its ground stays stone (pit palette, dust)")
	assert_false(v._markings, "no court lines in a quarry")
	var stack: Sprite2D = null
	var heap: Sprite2D = null
	for s in v._tiles.get_node("Walls").get_children():
		if (s.get_meta("cells") as Rect2i).has_point(Vector2i(20, 10)):
			stack = s
	for s in v._tiles.get_node("Rubble").get_children():
		if (s.get_meta("cells") as Rect2i).has_point(Vector2i(20, 10)):
			heap = s
	assert_true(stack != null and heap != null, "a stack and a heap over cell (20, 10)")
	assert_true(stack.visible and not heap.visible, "the wall stands")
	assert_true(sim.terrain.smash(Vector2i(20, 10)), "the wall's cell smashed")
	v.refresh()
	assert_true(heap.visible and not stack.visible, "the smashed tile shows its rocks, not its stack")
	sim.terrain.crack_cell(Vector2i(40, 18))
	v.refresh()
	var at := v._overlay.get_cell_atlas_coords(Vector2i(40, 18))
	assert_true((at.x + at.y * ArenaView.OV_COLS) in ArenaView.OV_CRACK, "a crack over the sandstone")
	v.free()
