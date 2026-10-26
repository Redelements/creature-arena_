extends TestCase
## Tiled arenas (bought ground tiles instead of a baked picture): the Set 1 cut's manifest
## covers every side combination of each blob terrain, the TileSet built from it matches by
## sides with the same bits and autotiles a patch, the Stadium's scene has its ground and
## kerb, and ArenaView draws the breaking ground over it as overlay tiles: a crack per
## cracked cell, a pit's far wall and floor by depth with the floor's edge down its sides and
## along its near rim, a piece gone while its cells are broken, all erased when the floor
## heals. The court lines stay on the Stadium (`tiles.markings`).

const MANIFEST := "res://assets/tiles/set1_manifest.json"
const GROUND := "res://assets/tiles/set1_ground.tres"
const OVERLAY := "res://assets/tiles/set1_overlay.tres"
const SCENE := "res://assets/arenas/stadium.tscn"


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
	for name in ["grass", "water"]:
		var block := {}
		var variants := 0
		for t in man["ground"]["terrains"][name]:
			var key := str(t["sides"])
			if float(t["prob"]) >= 1.0:
				assert_false(block.has(key), "%s: one block tile per side combination: %s" % [name, key])
				block[key] = t["at"]
			else:
				variants += 1
				assert_true(key != str([0, 0, 0, 0]), "a variant is never the lone island")
		assert_eq(block.size(), 16, "%s: all 16 combinations of connected sides:" % name)
		assert_gt(variants, 20, "%s: and the sheet's variants came along" % name)
	for fill in ["dirt", "grass", "water"]:
		assert_eq(man["ground"]["fills"][fill].size(), 16, "a 4 x 4 %s fill" % fill)
	assert_eq(man["ground"]["fills"]["cobble"].size(), 4, "a 2 x 2 cobble fill")
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
	assert_true(man["decor"].has("oak") and man["anim"].has("waterfall"), "the trees and the waterfall were cut")


func test_the_ground_tileset_matches_by_sides_with_the_cut_bits() -> void:
	var ts: TileSet = load(GROUND)
	assert_eq(ts.tile_size, Vector2i(32, 32))
	assert_eq(ts.get_terrain_sets_count(), 1)
	assert_eq(ts.get_terrain_set_mode(0), TileSet.TERRAIN_MODE_MATCH_SIDES, "16-tile sets: sides only")
	var names := []
	for i in ts.get_terrains_count(0):
		names.append(ts.get_terrain_name(0, i))
	assert_eq(names, ["grass", "water"])
	var src := ts.get_source(0) as TileSetAtlasSource
	assert_true(src != null, "source 0 is the ground atlas")
	var man := _manifest()
	var bits := [TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE]
	for name in ["grass", "water"]:
		var ti := names.find(name)
		for t in man["ground"]["terrains"][name]:
			var at := Vector2i(int(t["at"][0]), int(t["at"][1]))
			assert_true(src.has_tile(at), "tile %s exists" % at)
			var td := src.get_tile_data(at, 0)
			assert_eq(td.terrain, ti, "%s is %s" % [at, name])
			for k in 4:
				assert_eq(td.get_terrain_peering_bit(bits[k]), ti if int(t["sides"][k]) == 1 else -1,
					"%s side %d as cut" % [at, k])
	var pieces := ts.get_source(1) as TileSetAtlasSource
	assert_true(pieces != null and pieces.get_tiles_count() == 10, "source 1: four boulders, three tufts, three sprigs")
	var ov: TileSet = load(OVERLAY)
	assert_eq(ov.tile_size, Vector2i(16, 16), "overlay tiles are one cell")
	assert_eq((ov.get_source(0) as TileSetAtlasSource).get_tiles_count(), 19, "19 overlay ids: 4 cracks, 8 pit tiles, 7 edges")


func test_a_patch_autotiles_by_its_neighbours() -> void:
	var ts: TileSet = load(GROUND)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	var cells: Array[Vector2i] = []
	for ty in 2:
		for tx in 3:
			cells.append(Vector2i(tx, ty))
	cells.append(Vector2i(5, 5))  # a lone island
	layer.set_cells_terrain_connect(cells, 0, 0, false)
	for c in cells:
		var td := layer.get_cell_tile_data(c)
		assert_true(td != null and td.terrain == 0, "%s got a grass tile" % c)
		assert_eq(td.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_LEFT_SIDE), 0 if (c + Vector2i.LEFT) in cells else -1, "%s: left" % c)
		assert_eq(td.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_RIGHT_SIDE), 0 if (c + Vector2i.RIGHT) in cells else -1, "%s: right" % c)
		assert_eq(td.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_SIDE), 0 if (c + Vector2i.UP) in cells else -1, "%s: top" % c)
		assert_eq(td.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE), 0 if (c + Vector2i.DOWN) in cells else -1, "%s: bottom" % c)
	layer.free()


func test_the_stadium_scene_has_its_ground_and_kerb() -> void:
	var scene: PackedScene = load(SCENE)
	var root := scene.instantiate()
	var ground := root.get_node("Ground") as TileMapLayer
	assert_eq(ground.get_used_cells().size(), 44 * 20, "the fill: the 42 x 18 tiles of floor and a tile round it")
	var man := _manifest()
	var dirt: Array = man["ground"]["fills"]["dirt"].map(func(a): return Vector2i(int(a[0]), int(a[1])))
	var cobble: Array = man["ground"]["fills"]["cobble"].map(func(a): return Vector2i(int(a[0]), int(a[1])))
	assert_true(ground.get_cell_atlas_coords(Vector2i(10, 7)) in dirt, "the floor is dirt")
	assert_true(ground.get_cell_atlas_coords(Vector2i(-1, 7)) in cobble, "the ring round it is the cobble kerb")
	assert_true(ground.get_cell_atlas_coords(Vector2i(20, 18)) in cobble, "below the floor too")
	assert_eq((root.get_node("Grass") as TileMapLayer).get_used_cells().size(), 0, "no grass on the stadium")
	assert_eq((root.get_node("Pieces") as TileMapLayer).get_used_cells().size(), 0, "no pieces on the stadium")
	assert_true(root.has_node("Decor") and root.has_node("Anim"), "the decor and anim groups exist")
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
	var pair := _on("stadium")
	var sim: MatchSim = pair[0]
	var v: ArenaView = pair[1]
	assert_true(v.tiled(), "the Stadium draws from tiles")
	assert_true(v._markings, "and keeps its court lines")
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


func test_a_piece_is_cleared_while_its_cells_are_broken() -> void:
	var pair := _on("stadium")
	var sim: MatchSim = pair[0]
	var v: ArenaView = pair[1]
	var pieces := v._tiles.get_node("Pieces") as TileMapLayer
	# a boulder put on tile (6, 3) as the scene builder would for a wall at cells [12, 6, 2, 2]
	var tile := Vector2i(6, 3)
	v._piece_cells[tile] = [1, Vector2i(0, 0)]
	v._retile(6, 8)
	assert_eq(pieces.get_cell_source_id(tile), 1, "the piece stands while its cells are as the map made them")
	sim.terrain.crack_cell(Vector2i(12, 6))
	v.refresh()
	assert_eq(pieces.get_cell_source_id(tile), -1, "gone while any of its cells is broken")
	sim.terrain.set_cell(Vector2i(12, 6), TerrainGrid.INTACT)
	v.refresh()
	assert_eq(pieces.get_cell_source_id(tile), 1, "and back once they heal")
	v.free()


func test_a_baked_map_is_not_tiled() -> void:
	var pair := _on("quarry")
	var v: ArenaView = pair[1]
	assert_false(v.tiled())
	assert_true(v._overlay == null, "no overlay layers on a baked map")
	v.free()
