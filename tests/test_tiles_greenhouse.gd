extends TestCase
## The Greenhouse Dome on tiles (the grassland set: Set 1 turf and grass blobs, GrassLand's
## kerb and cliff face, Decorative Props fences): the set's terrains cover the 16 side
## combinations, the scene draws a fence tile on every tile of every fence line (a post
## line down or across, in the half of the tile the one-cell fence lies in) and tall grass
## on every brush bed, the map draws from tiles, and a flattened brush cell loses its tuft
## until it grows back. The map's pieces and play are unchanged (no sim change).

const MANIFEST := "res://assets/tiles/grassland_manifest.json"
const GROUND := "res://assets/tiles/grassland_ground.tres"
const SCENE := "res://assets/arenas/greenhouse.tscn"


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _tiles_of(r: Array) -> Array:
	var out := []
	var per := ArtScale.TILE_CELLS
	for ty in range(floori(float(r[1]) / per), ceili(float(int(r[1]) + int(r[3])) / per)):
		for tx in range(floori(float(r[0]) / per), ceili(float(int(r[0]) + int(r[2])) / per)):
			out.append(Vector2i(tx, ty))
	return out


func _coords(list: Array) -> Array:
	return list.map(func(a): return Vector2i(int(a[0]), int(a[1])))


func test_the_grassland_cut_covers_every_side_combination() -> void:
	var man := _manifest()
	for name in ["grass", "water"]:
		var block := {}
		for t in man["ground"]["terrains"][name]:
			if float(t["prob"]) >= 1.0:
				block[str(t["sides"])] = true
		assert_eq(block.size(), 16, "%s: all 16 combinations of connected sides" % name)
	for fill in ["turf", "moss", "meadow", "turf_grassland"]:
		assert_eq(man["ground"]["fills"][fill].size(), 16, "a 4 x 4 %s fill" % fill)
	for kind in ["fence_h", "fence_v_l", "fence_v_r", "tuft", "sprig"]:
		assert_gt(man["pieces"][kind].size(), 0, "%s tiles were cut" % kind)
	var ts: TileSet = load(GROUND)
	assert_eq(ts.get_terrain_name(0, 0), "grass")
	assert_eq(ts.get_terrain_set_mode(0), TileSet.TERRAIN_MODE_MATCH_SIDES)


func test_the_scene_fences_every_fence_line_and_plants_every_bed() -> void:
	var man := _manifest()
	var p: Dictionary = man["pieces"]
	var root := (load(SCENE) as PackedScene).instantiate()
	var pieces := root.get_node("Pieces") as TileMapLayer
	var map := ArenaMap.get_map("greenhouse")
	var expected := 0
	var brush := root.get_node("Brush")
	var beds := 0
	for piece in map["pieces"]:
		var r: Array = piece["rect"]
		var kind := String(piece["kind"])
		if kind == "brush":
			# a bed of bush clumps (a nine-slice of canopy clumps), not tuft tiles
			beds += 1
			var bed := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
			var inside := 0
			for s in brush.get_children():
				var cells: Rect2i = s.get_meta("cells")
				if bed.encloses(cells):
					inside += 1
			assert_gt(inside, 5, "bed %s: corners, edges and a middle (%d clumps)" % [bed, inside])
			continue
		for c in _tiles_of(r):
			expected += 1
			assert_eq(pieces.get_cell_source_id(c), 1, "%s at %s has a piece tile" % [kind, c])
			var at := pieces.get_cell_atlas_coords(c)
			var vertical: bool = int(r[3]) > int(r[2])
			var pool: Array = _coords(p["fence_h"]) if not vertical else _coords(p["fence_v_l" if int(r[0]) % 2 == 0 else "fence_v_r"])
			assert_true(at in pool, "%s: a fence tile the right way round, in the right half (%s)" % [c, at])
	assert_eq(pieces.get_used_cells().size(), expected, "a piece tile on every fence tile and nowhere else")
	assert_eq(beds, 5, "five beds")
	for s in brush.get_children():
		assert_true(s is AnimatedSprite2D and (s as AnimatedSprite2D).sprite_frames.get_frame_count(s.animation) == 5, "%s sways over 5 frames" % s.name)
	var ground := root.get_node("Ground") as TileMapLayer
	assert_true(ground.get_cell_atlas_coords(Vector2i(20, 9)) in _coords(man["ground"]["fills"]["turf"]), "turf under the floor")
	assert_eq(ground.get_cell_source_id(Vector2i(-1, 9)), -1, "no ring: the stands' hoardings sit past the floor")
	assert_gt((root.get_node("Grass") as TileMapLayer).get_used_cells().size(), 100, "grass blobs round the beds")
	assert_gt(root.get_node("Decor").get_child_count(), 10, "pots, barrels and crates in the margins")
	for d in root.get_node("Decor").get_children():
		var s := d as Sprite2D
		var feet := s.position + Vector2(s.texture.get_width() * 0.5, s.texture.get_height())
		var fx := feet.x / ArtScale.PX_PER_UNIT
		var fy := feet.y / ArtScale.PX_PER_UNIT
		var on_floor := fx > 0.0 and fx < SimDefs.GRID_COLS * SimDefs.CELL and fy > 0.0 and fy < SimDefs.GRID_ROWS * SimDefs.CELL
		assert_false(on_floor, "%s stands in the margins, never on the floor" % s.name)
	root.free()


func test_the_greenhouse_is_tiled_and_flattened_brush_loses_its_tuft() -> void:
	var was: String = MatchFactory.arena
	MatchFactory.arena = "greenhouse"
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = "grass"
	v.arena_id = "greenhouse"
	v.set_terrain(sim.terrain)
	assert_true(v.tiled(), "the Greenhouse draws from tiles")
	assert_false(v._markings, "no court lines under the glass")
	var brush := v._tiles.get_node("Brush")
	var over: Array = []  # the clumps over cell (8, 4), the bed's corner
	for s in brush.get_children():
		if (s.get_meta("cells") as Rect2i).has_point(Vector2i(8, 4)):
			over.append(s)
	assert_gt(over.size(), 0, "a clump covers the bed's corner cell")
	for s in over:
		assert_true(s.visible, "the bush stands")
	assert_true(sim.terrain.flatten(Vector2i(8, 4)), "a dash flattens a brush cell")
	v.refresh()
	for s in over:
		assert_false(s.visible, "%s hides while the brush under it lies flat" % s.name)
	sim.terrain.set_cell(Vector2i(8, 4), TerrainGrid.BRUSH)
	v.refresh()
	for s in over:
		assert_true(s.visible, "and shows again when it grows")
	assert_eq(sim.terrain.get_cell(Vector2i(26, 3)), TerrainGrid.FENCE, "the fence lines still stand in the sim")
	v.free()
