extends TestCase
## Tiled arenas (bought ground tiles instead of a baked picture): the Set 1 cut's manifest
## covers every side combination of the grass blob, the TileSet built from it matches by
## sides with the same bits, the Meadow's scene has its ground, grass and pieces, and
## ArenaView draws the breaking ground over it as overlay tiles: a crack per cracked cell, a
## pit's far wall and floor by depth with the floor's edge down its sides and along its
## near rim, a boulder gone while its wall is smashed, all erased when the floor heals.

const MANIFEST := "res://assets/tiles/set1_manifest.json"
const GROUND := "res://assets/tiles/set1_ground.tres"
const OVERLAY := "res://assets/tiles/set1_overlay.tres"
const SCENE := "res://assets/arenas/meadow.tscn"


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _on(id: String) -> Array:
	var was: String = MatchFactory.arena
	MatchFactory.arena = id
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = String(sim.arena.get("ground", "dirt"))
	v.arena_id = id
	v.set_terrain(sim.terrain)
	return [sim, v]


func test_the_cut_covers_every_side_combination_once() -> void:
	var man := _manifest()
	var block := {}
	var variants := 0
	for t in man["ground"]["terrains"]["grass"]:
		var key := str(t["sides"])
		if float(t["prob"]) >= 1.0:
			assert_false(block.has(key), "one block tile per side combination: " + key)
			block[key] = t["at"]
		else:
			variants += 1
			assert_true(key != str([0, 0, 0, 0]), "a variant is never the lone island")
	assert_eq(block.size(), 16, "all 16 combinations of connected sides:")
	assert_gt(variants, 20, "and the sheet's variants came along")
	assert_eq(man["ground"]["fills"]["dirt"].size(), 16, "a 4 x 4 dirt fill")
	assert_eq(man["ground"]["fills"]["grass"].size(), 16, "a 4 x 4 grass fill")
	var ids: Dictionary = man["overlay"]["ids"]
	assert_eq(Array(ids["crack"]).map(func(x): return int(x)), ArenaView.OV_CRACK, "crack ids as ArenaView draws them")
	assert_eq(int(ids["wall_top"]), ArenaView.OV_WALL_TOP)
	assert_eq(int(ids["wall_mid"]), ArenaView.OV_WALL_MID)
	assert_eq(int(ids["wall_bottom"]), ArenaView.OV_WALL_BOTTOM)
	assert_eq(int(ids["floor"]), ArenaView.OV_FLOOR)
	assert_eq(int(ids["chasm_top"]), ArenaView.OV_CHASM_TOP)
	assert_eq(int(ids["chasm_floor"]), ArenaView.OV_CHASM_TOP + 3)
	assert_eq(int(ids["edge_l"]), ArenaView.OV_EDGE_L)
	assert_eq(int(ids["edge_r"]), ArenaView.OV_EDGE_R)
	assert_eq(int(ids["edge_lr"]), ArenaView.OV_EDGE_LR)
	assert_eq(int(ids["rim"]), ArenaView.OV_RIM)
	assert_eq(int(ids["rim_lr"]), ArenaView.OV_RIM + 3)
	assert_eq(int(man["overlay"]["columns"]), ArenaView.OV_COLS)
	assert_eq(int(man["ground"]["tile"]), ArtScale.TILE_PX, "a ground tile is the 32 px tile")
	assert_eq(int(man["overlay"]["tile"]), ArtScale.CELL_PX, "an overlay tile is one cell")


func test_the_ground_tileset_matches_by_sides_with_the_cut_bits() -> void:
	var ts: TileSet = load(GROUND)
	assert_eq(ts.tile_size, Vector2i(32, 32))
	assert_eq(ts.get_terrain_sets_count(), 1)
	assert_eq(ts.get_terrain_set_mode(0), TileSet.TERRAIN_MODE_MATCH_SIDES, "a 16-tile set: sides only")
	assert_eq(ts.get_terrain_name(0, 0), "grass")
	var src := ts.get_source(0) as TileSetAtlasSource
	assert_true(src != null, "source 0 is the ground atlas")
	var man := _manifest()
	var bits := [TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE]
	for t in man["ground"]["terrains"]["grass"]:
		var at := Vector2i(int(t["at"][0]), int(t["at"][1]))
		assert_true(src.has_tile(at), "tile %s exists" % at)
		var td := src.get_tile_data(at, 0)
		assert_eq(td.terrain, 0, "%s is grass" % at)
		for k in 4:
			assert_eq(td.get_terrain_peering_bit(bits[k]), 0 if int(t["sides"][k]) == 1 else -1,
				"%s side %d as cut" % [at, k])
	var pieces := ts.get_source(1) as TileSetAtlasSource
	assert_true(pieces != null and pieces.get_tiles_count() == 10, "source 1: four boulders, three tufts, three sprigs")
	var ov: TileSet = load(OVERLAY)
	assert_eq(ov.tile_size, Vector2i(16, 16), "overlay tiles are one cell")
	assert_eq((ov.get_source(0) as TileSetAtlasSource).get_tiles_count(), 19, "19 overlay ids: 4 cracks, 8 pit tiles, 7 edges")


func test_the_meadow_scene_has_its_ground_grass_and_pieces() -> void:
	var scene: PackedScene = load(SCENE)
	var root := scene.instantiate()
	var ground := root.get_node("Ground") as TileMapLayer
	var grass := root.get_node("Grass") as TileMapLayer
	var pieces := root.get_node("Pieces") as TileMapLayer
	assert_eq(ground.get_used_cells().size(), 44 * 20, "the dirt fill: the 42 x 18 tiles of floor and a tile round it")
	var map := ArenaMap.get_map("meadow")
	var want := {}
	for r in map["tiles"]["grass"]:
		for ty in range(int(r[1]), int(r[1]) + int(r[3])):
			for tx in range(int(r[0]), int(r[0]) + int(r[2])):
				want[Vector2i(tx, ty)] = true
	assert_eq(grass.get_used_cells().size(), want.size(), "every grass tile of the map's rects")
	for c in grass.get_used_cells():
		assert_true(want.has(c), "grass only where the map says: %s" % c)
		assert_eq(grass.get_cell_source_id(c), 0, "from the ground atlas")
		var td := grass.get_cell_tile_data(c)
		assert_eq(td.terrain, 0, "an autotiled grass tile at %s" % c)
		# its sides agree with its neighbours (what autotiling is for)
		assert_eq(td.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_LEFT_SIDE), 0 if want.has(c + Vector2i.LEFT) else -1,
			"%s: left side" % c)
		assert_eq(td.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_SIDE), 0 if want.has(c + Vector2i.UP) else -1,
			"%s: top side" % c)
	assert_eq(pieces.get_used_cells().size(), 32, "four boulders, a 2 x 2 of them, two 3 x 4 brush beds")
	root.free()


func test_overlay_and_edge_tiles_follow_depth_and_neighbours() -> void:
	assert_eq(ArenaView.overlay_tile(TerrainGrid.INTACT, 0, false), -1, "plain floor: nothing")
	assert_eq(ArenaView.overlay_tile(TerrainGrid.CRACKED, 0, false, 5), ArenaView.OV_CRACK[1], "a crack by hash")
	assert_eq(ArenaView.overlay_tile(TerrainGrid.HOLE, 0, false), ArenaView.OV_WALL_TOP)
	assert_eq(ArenaView.overlay_tile(TerrainGrid.HOLE, 1, false), ArenaView.OV_WALL_MID)
	assert_eq(ArenaView.overlay_tile(TerrainGrid.HOLE, 2, false), ArenaView.OV_WALL_BOTTOM)
	assert_eq(ArenaView.overlay_tile(TerrainGrid.HOLE, 3, false), ArenaView.OV_FLOOR)
	assert_eq(ArenaView.overlay_tile(TerrainGrid.HOLE, 9, false), ArenaView.OV_FLOOR, "no deeper than the floor")
	assert_eq(ArenaView.overlay_tile(TerrainGrid.CHASM, 0, true), ArenaView.OV_CHASM_TOP)
	assert_eq(ArenaView.overlay_tile(TerrainGrid.CHASM, 3, true), ArenaView.OV_CHASM_TOP + 3)
	assert_eq(ArenaView.edge_tile(true, true, true), -1, "open all round: no edge")
	assert_eq(ArenaView.edge_tile(false, true, true), ArenaView.OV_EDGE_L)
	assert_eq(ArenaView.edge_tile(true, false, true), ArenaView.OV_EDGE_R)
	assert_eq(ArenaView.edge_tile(false, false, true), ArenaView.OV_EDGE_LR)
	assert_eq(ArenaView.edge_tile(true, true, false), ArenaView.OV_RIM)
	assert_eq(ArenaView.edge_tile(false, true, false), ArenaView.OV_RIM + 1)
	assert_eq(ArenaView.edge_tile(true, false, false), ArenaView.OV_RIM + 2)
	assert_eq(ArenaView.edge_tile(false, false, false), ArenaView.OV_RIM + 3)


func test_the_breaking_ground_sets_overlay_cells() -> void:
	var pair := _on("meadow")
	var sim: MatchSim = pair[0]
	var v: ArenaView = pair[1]
	assert_true(v.tiled(), "the Meadow draws from tiles")
	assert_true(v._overlay != null and v._edges != null, "the overlay layers exist")
	assert_eq(v._overlay.get_used_cells().size(), 0, "nothing broken yet")
	var t := sim.terrain
	t.crack_cell(Vector2i(30, 20))
	v.refresh()
	assert_true(v._overlay.get_cell_source_id(Vector2i(30, 20)) == 0, "a cracked cell got a tile")
	var crack := v._overlay.get_cell_atlas_coords(Vector2i(30, 20))
	assert_true((crack.x + crack.y * ArenaView.OV_COLS) in ArenaView.OV_CRACK, "a crack tile: %s" % crack)
	# a pit one cell wide and four tall: far wall by depth, then the floor; the floor's edge on both sides
	for cy in range(10, 14):
		t.set_cell(Vector2i(50, cy), TerrainGrid.HOLE)
	v.refresh()
	var want := [ArenaView.OV_WALL_TOP, ArenaView.OV_WALL_MID, ArenaView.OV_WALL_BOTTOM, ArenaView.OV_FLOOR]
	for k in 4:
		var c := Vector2i(50, 10 + k)
		var at := v._overlay.get_cell_atlas_coords(c)
		assert_eq(at.x + at.y * ArenaView.OV_COLS, want[k], "row %d of the pit" % k)
		var e := v._edges.get_cell_atlas_coords(c)
		var eid := e.x + e.y * ArenaView.OV_COLS
		assert_eq(eid, ArenaView.OV_EDGE_LR if k < 3 else ArenaView.OV_RIM + 3, "row %d: both sides%s" % [k, "" if k < 3 else " and the near rim"])
	# a wider pit: the middle cell of the bottom row has the rim alone
	for cx in range(49, 52):
		t.set_cell(Vector2i(cx, 13), TerrainGrid.HOLE)
	v.refresh()
	var mid := v._edges.get_cell_atlas_coords(Vector2i(50, 13))
	assert_eq(mid.x + mid.y * ArenaView.OV_COLS, ArenaView.OV_RIM, "a floor below, open to both sides: the rim alone")
	# healed: erased
	t.set_cell(Vector2i(30, 20), TerrainGrid.INTACT)
	for cy in range(10, 14):
		t.set_cell(Vector2i(50, cy), TerrainGrid.INTACT)
	v.refresh()
	assert_eq(v._overlay.get_cell_source_id(Vector2i(30, 20)), -1, "the crack healed: no tile")
	assert_eq(v._overlay.get_cell_source_id(Vector2i(50, 10)), -1, "the pit healed: no tile")
	assert_eq(v._edges.get_cell_source_id(Vector2i(50, 12)), -1, "and no edge")
	v.free()


func test_a_smashed_wall_loses_its_boulder_until_it_heals() -> void:
	var pair := _on("meadow")
	var sim: MatchSim = pair[0]
	var v: ArenaView = pair[1]
	var pieces := v._tiles.get_node("Pieces") as TileMapLayer
	var tile := Vector2i(6, 3)  # the wall at cells [12, 6, 2, 2]
	assert_eq(pieces.get_cell_source_id(tile), 1, "a boulder stands on the wall")
	assert_true(sim.terrain.smash(Vector2i(12, 6)), "the wall's corner smashed")
	v.refresh()
	assert_eq(pieces.get_cell_source_id(tile), -1, "the boulder is gone while any of its cells is rubble")
	sim.terrain.set_cell(Vector2i(12, 6), TerrainGrid.WALL)
	v.refresh()
	assert_eq(pieces.get_cell_source_id(tile), 1, "and back once the wall rebuilt")
	v.free()


func test_a_baked_map_is_not_tiled() -> void:
	var pair := _on("stadium")
	var v: ArenaView = pair[1]
	assert_false(v.tiled())
	assert_true(v._overlay == null, "no overlay layers on a baked map")
	v.free()
