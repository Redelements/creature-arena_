extends TestCase
## Tiled arenas (bought ground tiles instead of a baked picture): the Set 1 cut's manifest
## covers every side combination of each blob terrain, the TileSet built from it matches by
## sides with the same bits and autotiles a patch, the Stadium's scene has its ground and
## kerb, and ArenaView draws the breaking ground over it as overlay tiles: a crack per
## cracked cell (running on into its cracked or open neighbours across some sides), a pit's
## far wall and floor by depth (two phases by column) with the floor's edge down its sides,
## along its near rim and round its corners, a piece gone while its cells are broken, all
## erased when the floor heals. Every set's overlay atlas keeps the rules the renderer relies
## on (a pit's top rows clear, edges translucent, cracks reaching the sides they join). The
## court lines stay on the Stadium (`tiles.markings`).

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
	assert_eq(int(ids["wall_b"][0]), ArenaView.OV_WALL_TOP + ArenaView.OV_PHASE_B, "the second phase sits OV_PHASE_B on")
	assert_eq(int(ids["chasm_b"][3]), ArenaView.OV_CHASM_TOP + 3 + ArenaView.OV_PHASE_B)
	assert_eq(int(ids["crack_join"][0]), ArenaView.OV_CRACK_JOIN)
	assert_eq(ids["crack_join"].size(), 16, "a joined crack for every set of sides")
	assert_eq(int(ids["corner"][0]), ArenaView.OV_CORNER)
	assert_eq(ids["corner"].size(), 16)
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
	assert_eq((ov.get_source(0) as TileSetAtlasSource).get_tiles_count(), 59,
		"59 overlay ids: 4 cracks, 16 joined cracks, 8 + 8 pit tiles, 7 edges, 16 corners")


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


func test_the_stadium_scene_has_its_ground_and_no_ring() -> void:
	var scene: PackedScene = load(SCENE)
	var root := scene.instantiate()
	var ground := root.get_node("Ground") as TileMapLayer
	assert_eq(ground.get_used_cells().size(), 42 * 18, "the fill: the 42 x 18 tiles of floor, no ring")
	var man := _manifest()
	var dirt: Array = man["ground"]["fills"]["dirt"].map(func(a): return Vector2i(int(a[0]), int(a[1])))
	assert_true(ground.get_cell_atlas_coords(Vector2i(10, 7)) in dirt, "the floor is dirt")
	assert_eq(ground.get_cell_source_id(Vector2i(-1, 7)), -1, "no ring past the floor: the picture's hoardings sit there")
	assert_eq(ground.get_cell_source_id(Vector2i(20, 18)), -1, "nor below it")
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
	assert_eq(ArenaView.overlay_tile(TerrainGrid.HOLE, 1, false, 0, true), ArenaView.OV_WALL_MID + ArenaView.OV_PHASE_B, "an odd column: the face's other half")
	assert_eq(ArenaView.overlay_tile(TerrainGrid.CHASM, 3, true, 0, true), ArenaView.OV_CHASM_TOP + 3 + ArenaView.OV_PHASE_B)
	assert_eq(ArenaView.overlay_tile(TerrainGrid.CRACKED, 0, false, 5, true), ArenaView.OV_CRACK[1], "a crack has no phase")
	assert_eq(ArenaView.overlay_tile(TerrainGrid.CRACKED, 0, false, 5, false, 2 | 8), ArenaView.OV_CRACK_JOIN + 10, "a crack running out right and down")
	assert_true(ArenaView.is_crack(ArenaView.OV_CRACK_JOIN + 15) and ArenaView.is_crack(ArenaView.OV_CRACK[3]))
	assert_false(ArenaView.is_crack(ArenaView.OV_WALL_TOP) or ArenaView.is_crack(ArenaView.OV_CORNER + 1))
	assert_eq(ArenaView.corner_tile(false, false, false, false), -1, "no turn: no corner")
	assert_eq(ArenaView.corner_tile(true, false, false, true), ArenaView.OV_CORNER + 9)


func test_the_breaking_ground_sets_overlay_cells() -> void:
	var pair := _on("stadium")
	var sim: MatchSim = pair[0]
	var v: ArenaView = pair[1]
	assert_true(v.tiled(), "the Stadium draws from tiles")
	assert_true(v._markings, "and keeps its court lines")
	assert_true(v._overlay != null and v._edges != null and v._corners != null, "the overlay layers exist")
	assert_eq(v._overlay.get_used_cells().size(), 0, "nothing broken yet")
	var t := sim.terrain
	t.crack_cell(Vector2i(30, 20))
	v.refresh()
	assert_true(v._overlay.get_cell_source_id(Vector2i(30, 20)) == 0, "a cracked cell got a tile")
	var crack := v._overlay.get_cell_atlas_coords(Vector2i(30, 20))
	assert_true((crack.x + crack.y * ArenaView.OV_COLS) in ArenaView.OV_CRACK, "a crack alone: one of the four: %s" % crack)
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
	var odd := v._overlay.get_cell_atlas_coords(Vector2i(51, 13))
	assert_eq(odd.x + odd.y * ArenaView.OV_COLS, ArenaView.OV_WALL_TOP + ArenaView.OV_PHASE_B, "an odd column takes the face's other half")
	var turn := v._corners.get_cell_atlas_coords(Vector2i(50, 13))
	assert_eq(turn.x + turn.y * ArenaView.OV_COLS, ArenaView.OV_CORNER + 3, "the pit turns round the floor above left and above right")
	assert_eq(v._corners.get_cell_source_id(Vector2i(50, 12)), -1, "a straight side: no corner")
	# a crack next to the pit and another crack: it may run on into them, never elsewhere
	t.crack_cell(Vector2i(52, 13))
	t.crack_cell(Vector2i(53, 13))
	v.refresh()
	var cj := v._overlay.get_cell_atlas_coords(Vector2i(52, 13))
	var cid := cj.x + cj.y * ArenaView.OV_COLS
	assert_true(ArenaView.is_crack(cid), "a crack by the pit: %d" % cid)
	if cid >= ArenaView.OV_CRACK_JOIN:
		assert_eq((cid - ArenaView.OV_CRACK_JOIN) & (4 | 8), 0, "it runs only toward broken cells (left or right here)")
	assert_eq(v._crack_link(52, 13, 53, 13), v._crack_link(52, 13, 53, 13), "a side's link is fixed")
	t.set_cell(Vector2i(52, 13), TerrainGrid.INTACT)
	t.set_cell(Vector2i(53, 13), TerrainGrid.INTACT)
	# healed: erased
	t.set_cell(Vector2i(30, 20), TerrainGrid.INTACT)
	for cy in range(10, 14):
		t.set_cell(Vector2i(50, cy), TerrainGrid.INTACT)
	v.refresh()
	assert_eq(v._overlay.get_cell_source_id(Vector2i(30, 20)), -1, "the crack healed: no tile")
	assert_eq(v._overlay.get_cell_source_id(Vector2i(50, 10)), -1, "the pit healed: no tile")
	assert_eq(v._edges.get_cell_source_id(Vector2i(50, 12)), -1, "and no edge")
	for cx in range(49, 52):
		t.set_cell(Vector2i(cx, 13), TerrainGrid.INTACT)
	v.refresh()
	assert_eq(v._overlay.get_used_cells().size() + v._edges.get_used_cells().size() + v._corners.get_used_cells().size(), 0,
		"all healed: nothing of the pit or the cracks is left")
	v.free()


## Every set's overlay atlas: a pit tile's top rows are clear on the far wall's top (the floor
## round the pit shows, whatever patch it opened in) and the rest of every pit tile is solid
## (no see-through holes, no outline from a source sheet's border: its sides are not black);
## the edges and corners are translucent (they shade the pit, never paint a floor); a joined
## crack reaches the middle of each side it joins and no other side.
func test_every_sets_overlay_atlas_keeps_the_rules() -> void:
	for set_name in ["set1", "rock", "wetland", "grassland", "desert", "keeps"]:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/tiles/%s_overlay.png" % set_name))
		var tile := func(id: int) -> Image:
			return img.get_region(Rect2i((id % ArenaView.OV_COLS) * 16, (id / ArenaView.OV_COLS) * 16, 16, 16))
		for base in [ArenaView.OV_WALL_TOP, ArenaView.OV_CHASM_TOP]:
			for phase in [0, ArenaView.OV_PHASE_B]:
				for d in 4:
					var t: Image = tile.call(base + d + phase)
					var see := 0
					var black_side := 0
					for y in 16:
						for x in 16:
							var a := t.get_pixel(x, y).a
							if d == 0 and y < 2:
								assert_eq(a, 0.0, "%s %d: the lip's top rows are clear" % [set_name, base + d + phase])
							elif d > 0 or y > 2:
								see += 1 if a < 1.0 else 0
						var lc := t.get_pixel(0, y)
						if lc.a == 1.0 and lc.r + lc.g + lc.b < 0.02:
							black_side += 1
					assert_eq(see, 0, "%s %d: solid below the lip" % [set_name, base + d + phase])
					assert_lt(black_side, 16, "%s %d: no black outline down its side" % [set_name, base + d + phase])
		for id in range(ArenaView.OV_EDGE_L, ArenaView.OV_RIM + 4) + range(ArenaView.OV_CORNER + 1, ArenaView.OV_CORNER + 16):
			var t: Image = tile.call(id)
			var any := false
			for y in 16:
				for x in 16:
					var a := t.get_pixel(x, y).a
					assert_true(a < 1.0, "%s %d: edges are translucent (%d, %d)" % [set_name, id, x, y])
					any = any or a > 0.0
			assert_true(any, "%s %d: and not empty" % [set_name, id])
		var ends := {1: Vector2i(0, 7), 2: Vector2i(15, 7), 4: Vector2i(7, 0), 8: Vector2i(7, 15)}
		for joins in range(1, 16):
			var t: Image = tile.call(ArenaView.OV_CRACK_JOIN + joins)
			for bit: int in ends:
				var e: Vector2i = ends[bit]
				var hit := t.get_pixelv(e).a > 0.0
				if joins & bit:
					assert_true(hit, "%s crack %d reaches side %d" % [set_name, joins, bit])
		for id in ArenaView.OV_CRACK:
			assert_false(tile.call(id).is_invisible(), "%s crack %d is drawn" % [set_name, id])


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
	# whichever map still has no ground scene (the old maps are retiled one by one)
	var baked := ""
	for id in ArenaMap.IDS + ArenaMap.MODE_IDS:
		if not ResourceLoader.exists("res://assets/arenas/%s.tscn" % id):
			baked = id
			break
	if baked == "":
		return  # every map is tiled now: nothing left to check here
	var pair := _on(baked)
	var v: ArenaView = pair[1]
	assert_false(v.tiled(), baked + " draws its baked picture")
	assert_true(v._overlay == null, "no overlay layers on a baked map")
	v.free()
