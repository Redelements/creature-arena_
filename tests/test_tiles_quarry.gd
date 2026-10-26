extends TestCase
## The Quarry Bowl on bought tiles (the "rock" set: Mountains sandstone and cliff faces, Set 1
## dirt, cobbles and boulders): the cut has its fills and no blob terrain, the scene has the
## floor, the kerb, the dirt lanes and cobbled corners as patches, boulders on both rubble
## walls, and the map plays as it did: ArenaView is tiled there, the walls still stand, a
## crack sets an overlay cell.

const MANIFEST := "res://assets/tiles/rock_manifest.json"
const GROUND := "res://assets/tiles/rock_ground.tres"
const SCENE := "res://assets/arenas/quarry.tscn"


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _at(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


func test_the_rock_cut_has_its_fills_and_overlay() -> void:
	var man := _manifest()
	assert_eq(man["set"], "rock")
	for fill in ["stone", "rock_dark", "dirt"]:
		assert_eq(man["ground"]["fills"][fill].size(), 16, "a 4 x 4 %s fill" % fill)
	assert_eq(man["ground"]["fills"]["cobble"].size(), 4, "a 2 x 2 cobble fill")
	assert_true(man["ground"]["terrains"].is_empty(), "no blob terrain in the Mountains sheet: variety is patches")
	for name in man["ground"]["terrains"]:  # if one is ever added, it must be the full 16-tile set
		var block := {}
		for t in man["ground"]["terrains"][name]:
			if float(t["prob"]) >= 1.0:
				block[str(t["sides"])] = true
		assert_eq(block.size(), 16, "%s covers every side combination" % name)
	assert_eq(man["pieces"]["boulder"].size(), 4, "four boulders for the walls")
	assert_eq(int(man["overlay"]["ids"]["wall_top"]), ArenaView.OV_WALL_TOP, "the overlay ids are ArenaView's")
	var ts: TileSet = load(GROUND)
	assert_eq(ts.tile_size, Vector2i(32, 32))
	assert_eq(ts.get_terrains_count(0), 0, "no terrains in the set")
	assert_true(ResourceLoader.exists("res://assets/tiles/rock_overlay.tres"), "the overlay set exists")


func test_the_quarry_scene_has_floor_kerb_patches_and_boulders() -> void:
	var scene: PackedScene = load(SCENE)
	var root := scene.instantiate()
	var ground := root.get_node("Ground") as TileMapLayer
	assert_eq(ground.get_used_cells().size(), 44 * 20, "the fill: 42 x 18 tiles of floor and the ring")
	var man := _manifest()
	var fills: Dictionary = man["ground"]["fills"]
	var stone: Array = fills["stone"].map(_at)
	var kerb: Array = fills["rock_dark"].map(_at)
	var dirt: Array = fills["dirt"].map(_at)
	var cobble: Array = fills["cobble"].map(_at)
	assert_true(ground.get_cell_atlas_coords(Vector2i(20, 3)) in stone, "the open floor is sandstone")
	assert_true(ground.get_cell_atlas_coords(Vector2i(-1, 9)) in kerb, "the ring is the darker rock")
	assert_true(ground.get_cell_atlas_coords(Vector2i(11, 9)) in dirt, "a worn lane inside the left wall")
	assert_true(ground.get_cell_atlas_coords(Vector2i(30, 2)) in dirt, "and inside the right wall")
	assert_true(ground.get_cell_atlas_coords(Vector2i(20, 8)) in dirt, "the trampled middle")
	assert_true(ground.get_cell_atlas_coords(Vector2i(1, 1)) in cobble, "a cobbled corner")
	assert_true(ground.get_cell_atlas_coords(Vector2i(40, 16)) in cobble, "and the opposite one")
	assert_eq((root.get_node("Grass") as TileMapLayer).get_used_cells().size(), 0, "no grass in the quarry")
	var pieces := root.get_node("Pieces") as TileMapLayer
	# the walls at cells [20, 5, 2, 26] and [62, 5, 2, 26]: tile columns 10 and 31, rows 2..15
	assert_eq(pieces.get_used_cells().size(), 28, "a boulder on every wall tile")
	var boulders: Array = man["pieces"]["boulder"].map(_at)
	for ty in range(2, 16):
		for tx in [10, 31]:
			var c := Vector2i(tx, ty)
			assert_eq(pieces.get_cell_source_id(c), 1, "%s is a piece" % c)
			assert_true(pieces.get_cell_atlas_coords(c) in boulders, "%s is a boulder" % c)
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
	var pieces := v._tiles.get_node("Pieces") as TileMapLayer
	assert_eq(pieces.get_cell_source_id(Vector2i(10, 5)), 1, "a boulder on the wall")
	assert_true(sim.terrain.smash(Vector2i(20, 10)), "the wall's cell smashed")
	v.refresh()
	assert_eq(pieces.get_cell_source_id(Vector2i(10, 5)), -1, "the boulder is gone while the wall is rubble")
	sim.terrain.crack_cell(Vector2i(40, 18))
	v.refresh()
	var at := v._overlay.get_cell_atlas_coords(Vector2i(40, 18))
	assert_true((at.x + at.y * ArenaView.OV_COLS) in ArenaView.OV_CRACK, "a crack over the sandstone")
	v.free()
