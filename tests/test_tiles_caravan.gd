extends TestCase
## Dustwind Pass on the Desert set (tools/tile_recipes/desert.json): the cut's opaque 5 x 5
## blobs give nine side combinations a terrain, the scene is the 110 x 20 floor and its
## ring, the walls stand as raised sandstone plateaus on their own cells (styles.wall
## "raised:sandstone": a top, the plateau's ledge as a face on a run's south end, rubble
## hidden under each tile), the brush as beds of the Desert's own scrub shrubs, the fences
## as oriented fence tiles, the road and scrub are painted with worn verges and gravel, the
## margins carry low rocks and palms, the caravan stops braziers and goods on the walls'
## tops just behind their faces and the side walkways banner racks and braziers, pebbles and
## dry tufts lie by the walls and along the road's edges, and the map draws as tiles: a
## smashed wall shows its rubble and drops what stood on it, and runtime rockslide rubble
## is still handled (a WALL the sim adds is not a piece).

const MANIFEST := "res://assets/tiles/desert_manifest.json"
const GROUND := "res://assets/tiles/desert_ground.tres"
const SCENE := "res://assets/arenas/caravan_pass.tscn"


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func test_the_desert_cut_has_its_terrains_pieces_and_props() -> void:
	var man := _manifest()
	for name in ["earth", "scrub"]:
		var seen := {}
		for t in man["ground"]["terrains"][name]:
			seen[str(Array(t["sides"]).map(func(x): return int(x)))] = true
		assert_eq(seen.size(), 9, "%s: a 5 x 5 opaque blob gives nine side combinations" % name)
		assert_true(seen.has(str([1, 1, 1, 1])), "%s: with a middle" % name)
		assert_true(seen.has(str([0, 1, 0, 1])), "%s: and a top-left corner" % name)
	for fill in ["sand", "gravel", "scrub_fill", "sand_dirt"]:
		assert_eq(man["ground"]["fills"][fill].size(), 16, "a 4 x 4 %s fill" % fill)
	assert_eq(man["ground"]["fills"]["earth_fill"].size(), 9, "a 3 x 3 packed-earth fill")
	var rz: Dictionary = man["raised"]["sandstone"]
	assert_eq(int(rz["cells"]), 3, "the plateau's 1.4-tile ledge: a face three cells tall at most")
	assert_eq(int(rz["variants"]), 10, "five sand blocks for the top, each also mirrored")
	assert_eq(String(rz["rubble"]), "rock", "a smashed tile shows the rock wall's loose rocks")
	for kind in ["pebbles", "clods", "dry_tufts"]:
		assert_gt(man["scatter"]["kinds"].get(kind, []).size(), 2, "scatter %s in several looks" % kind)
	for kind in ["fence_h", "fence_v"]:
		assert_true(man["pieces"].get(kind, []).size() >= 2, "%s pieces" % kind)
	var roles: Dictionary = man["walls"]["rock"]["roles"]
	assert_eq(roles["mid"].size(), 4, "four rock pillars (two, and each mirrored) for a run's middle")
	for role in ["bottom", "left", "right", "rubble"]:
		assert_gt(roles.get(role, []).size(), 0, "a wall %s sprite" % role)
	for sp in roles["mid"]:
		assert_gt(int(sp["size"][1]), 32, "a pillar stands taller than its tile, so a run overlaps into one wall")
	var scrub: Dictionary = man["bushes"]["scrub"]
	assert_true(scrub.get("blobs", false), "the scrub bush is a set of whole shrubs a bed scatters")
	assert_eq(scrub["clumps"].size(), 5, "five shrubs")
	assert_false(man["bushes"].has("sage"), "the borrowed Wetland canopy is gone")
	for d in ["rocks", "rocks_b", "agave", "rack_red", "rack_grey", "rack_green", "goods_a", "goods_b"]:
		assert_true(man["decor"].has(d), "decor " + d)
	for d in ["rack_red", "rack_grey", "rack_green"]:
		assert_eq(Array(man["decor"][d]["size"]).map(func(x): return int(x)), [32, 59], "%s: a narrow rack, one tile wide" % d)
	assert_eq(int(man["anim"]["palm"]["frames"]), 10, "the palm strip's ten frames")
	assert_eq(int(man["anim"]["palm"]["frame"][0]), 64, "64 px wide each")
	for a in ["brazier", "tripod"]:
		assert_eq(int(man["anim"][a]["frames"]), 6, "%s: six flame frames" % a)


## The scene px a decor or anim sprite draws its opaque pixels over (positioned by its top
## left, or, on a wall, by its foot with an offset).
func _drawn_box(s: Node) -> Rect2:
	var tex: Texture2D = (s as Sprite2D).texture if s is Sprite2D else (s as AnimatedSprite2D).sprite_frames.get_frame_texture("default", 0)
	var used := tex.get_image().get_used_rect()
	var at: Vector2 = (s as Node2D).position + Vector2(s.get("offset"))
	return Rect2(at + Vector2(used.position), Vector2(used.size))


func test_the_desert_tileset_names_its_terrains() -> void:
	var ts: TileSet = load(GROUND)
	var names := []
	for i in ts.get_terrains_count(0):
		names.append(ts.get_terrain_name(0, i))
	assert_eq(names, ["earth", "scrub", "trodden", "sand_pale", "gravel_patch", "dry_grass"], "the map's two, then the dressing's four (tests/test_dressing_caravan.gd)")
	assert_eq(ts.get_terrain_set_mode(0), TileSet.TERRAIN_MODE_MATCH_SIDES)
	var pieces := ts.get_source(1) as TileSetAtlasSource
	assert_true(pieces != null and pieces.get_tiles_count() == 5, "3 + 2 fence tiles (walls and brush are sprites)")


func test_the_pass_scene_has_road_walls_fences_and_margins() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var ground := root.get_node("Ground") as TileMapLayer
	assert_eq(ground.get_used_cells().size(), 110 * 20, "the 110 x 20 floor, no ring")
	var man := _manifest()
	var sand: Array = man["ground"]["fills"]["sand"].map(func(a): return Vector2i(int(a[0]), int(a[1])))
	assert_true(ground.get_cell_atlas_coords(Vector2i(50, 3)) in sand, "the floor is sand")
	assert_eq(ground.get_cell_source_id(Vector2i(50, -1)), -1, "no ring: the stands' hoardings sit past the floor")
	var earth := root.get_node("Earth") as TileMapLayer
	var scrub := root.get_node("Scrub") as TileMapLayer
	assert_gt(earth.get_used_cells().size(), 100, "the packed-earth road under the track")
	assert_gt(scrub.get_used_cells().size(), 50, "dry scrub patches in the margins")
	for c in [Vector2i(10, 10), Vector2i(30, 5), Vector2i(55, 12), Vector2i(100, 10)]:
		assert_true(earth.get_cell_source_id(c) == 0 and earth.get_cell_tile_data(c).terrain == 0, "road under the track at %s" % c)
	var pieces := root.get_node("Pieces") as TileMapLayer
	var p: Dictionary = man["pieces"]
	var fh: Array = p["fence_h"].map(func(a): return Vector2i(int(a[0]), int(a[1])))
	# the walls are raised plateaus: a 16 px tile on each wall cell, a face on a run's last
	# three cells, no pillar sprites; each 2 x 2-cell tile keeps its rubble, hidden
	var walls := root.get_node("Walls")
	var rubble := root.get_node("Rubble")
	assert_true(walls.y_sort_enabled, "what stands on the walls is y-sorted")
	assert_eq(walls.get_children().filter(func(s): return String(s.name).begins_with("rock_")).size(), 0, "no rock pillars")
	var raised := root.get_node("Raised") as TileMapLayer
	var info: Dictionary = raised.get_meta("raised")
	var map := ArenaMap.get_map("caravan_pass")
	var grid := TerrainGrid.new(220, 40)
	grid.load_map(map)
	var wall_n := 0
	for i in grid.map_base.size():
		if grid.map_base[i] == TerrainGrid.WALL:
			wall_n += 1
	assert_eq(wall_n, 96, "the map's walls (6 + 8 + 10 cells tall, two wide, twice)")
	assert_eq(raised.get_used_cells().size(), wall_n, "a raised tile on every wall cell")
	var face := {}
	for key in info["tiles"]:
		if String(key).begins_with("f"):
			face[Vector2i(int(info["tiles"][key][0]), int(info["tiles"][key][1]))] = true
	for cy in range(2, 8):
		assert_eq(face.has(raised.get_cell_atlas_coords(Vector2i(30, cy))), cy >= 5, "the run [30, 2, 2, 6]: a top, then its face on rows 5-7 (row %d)" % cy)
	assert_true(root.get_node("RaisedShadow").get_used_cells().size() > 0, "a contact shadow beside the walls")
	assert_eq(rubble.get_child_count(), 24, "a rubble heap on every wall tile (3 + 4 + 5, twice)")
	var scatter := root.get_node("Scatter") as TileMapLayer
	assert_true(scatter.get_used_cells().size() >= 30, "pebbles and tufts by the walls and the road (%d)" % scatter.get_used_cells().size())
	for s in rubble.get_children():
		assert_false(s.visible, "rubble hides while its wall stands: %s" % s.name)
		assert_true(s.get_meta("broken", false), "and is marked as the broken look")
	for ty in range(1, 4):
		assert_eq(pieces.get_cell_source_id(Vector2i(15, ty)), -1, "no tile piece under the pillars at row %d" % ty)
	var brush := root.get_node("Brush")
	for r in [Rect2i(66, 26, 10, 6), Rect2i(98, 30, 10, 6), Rect2i(112, 30, 10, 6), Rect2i(144, 26, 10, 6)]:
		var inside := 0
		for s in brush.get_children():
			if r.encloses(s.get_meta("cells")):
				inside += 1
		assert_gt(inside, 5, "bed %s is a clump of bushes" % r)
	for tx in range(19, 24):
		assert_true(pieces.get_cell_atlas_coords(Vector2i(tx, 15)) in fh, "a horizontal fence tile at %d" % tx)
	assert_true(pieces.get_cell_source_id(Vector2i(50, 8)) == -1, "nothing on the open road")
	var decor := root.get_node("Decor")
	var anim := root.get_node("Anim")
	assert_eq(decor.get_child_count(), 16, "the margins' rocks and agave, the walkways' racks and goods")
	assert_eq(anim.get_child_count(), 9, "five palms and the walkways' four braziers")
	for s in decor.get_children() + anim.get_children():
		# the drawn box (its feet plus a shadow of a few px) is above the floor or below it, or
		# past its left or right end (the side walkways)
		var box := _drawn_box(s)
		assert_true(box.end.y <= 12.0 or box.end.y >= 20 * 32 or box.end.x <= 0.0 or box.position.x >= 110 * 32,
			"decor stands off the floor: %s, %s" % [s.name, box])
	for s in anim.get_children():
		assert_true((s as AnimatedSprite2D).autoplay == "default", "palms and braziers move on their own")
	# the stops' pieces stand on the walls' tops just behind the face (the map puts them on a
	# run's near end; build_tiles moves a piece off the face), y-sorted, inside the run's cells
	var on_walls := walls.get_children().filter(func(n): return n.name != "Dressing")  # the hand dressing: tests/test_dressing_caravan.gd
	assert_eq(on_walls.size(), 6, "a brazier, goods or a tripod on each run")
	var up := func(c: Vector2i) -> bool: return grid.get_base(c) == TerrainGrid.WALL
	var runs := [Rect2i(30, 2, 2, 6), Rect2i(52, 22, 2, 8), Rect2i(90, 2, 2, 10), Rect2i(188, 2, 2, 6), Rect2i(166, 22, 2, 8), Rect2i(128, 2, 2, 10)]
	# (its feet row lands on the tile's bottom edge, as every decor's does: 2 px of slack)
	for s in on_walls:
		var cells: Rect2i = s.get_meta("cells")
		var inside: Array = runs.filter(func(r): return r.encloses(cells))
		assert_eq(inside.size(), 1, "%s covers wall cells only: %s" % [s.name, cells])
		var r: Rect2i = inside[0]
		var box := _drawn_box(s)
		assert_true(box.position.x >= r.position.x * 16 and box.end.x <= r.end.x * 16,
			"%s stands within its wall's width: %s in %s" % [s.name, box, r])
		var foot := Vector2i(floori((s as Node2D).position.x / 16.0), floori(((s as Node2D).position.y - 1.0) / 16.0))
		assert_true(r.has_point(foot), "%s stands on its wall: %s" % [s.name, foot])
		assert_eq(RaisedTiles._face_row(foot, up, 3), Vector2i.ZERO, "%s stands on the top, not the face: %s" % [s.name, foot])
		assert_eq(RaisedTiles._face_row(foot + Vector2i.DOWN, up, 3).y, 0, "%s: just behind the face's first row" % s.name)
		assert_eq(cells.end.y, r.end.y, "%s goes when the face in front of it is smashed" % s.name)
	root.free()


func test_the_pass_is_tiled_and_a_rockslide_still_draws() -> void:
	var was: String = MatchFactory.arena
	MatchFactory.arena = "caravan_pass"
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = "dirt"
	v.arena_id = "caravan_pass"
	v.set_terrain(sim.terrain)
	assert_true(v.tiled(), "Dustwind Pass draws from tiles")
	assert_false(v._markings, "no court lines in a canyon")
	var pieces := v._tiles.get_node("Pieces") as TileMapLayer
	var before := pieces.get_used_cells().size()
	assert_eq(before, 10, "the map's fences as pieces (walls are raised tiles, brush sprites)")
	# a smashed wall cell drops its raised tile and shows its rubble; both come back
	var raised := v._tiles.get_node("Raised") as TileMapLayer
	var heap: Sprite2D = null
	for s in v._tiles.get_node("Rubble").get_children():
		if (s.get_meta("cells") as Rect2i).has_point(Vector2i(30, 6)):
			heap = s
	assert_true(heap != null, "a heap over cell (30, 6)")
	assert_true(raised.get_cell_source_id(Vector2i(30, 6)) >= 0 and not heap.visible, "the wall stands")
	assert_true(sim.terrain.smash(Vector2i(30, 6)), "a charge smashes a wall cell")
	v.refresh()
	assert_true(heap.visible and raised.get_cell_source_id(Vector2i(30, 6)) == -1, "the smashed cell shows loose rocks, not the plateau")
	sim.terrain.set_cell(Vector2i(30, 6), TerrainGrid.WALL)
	v.refresh()
	assert_true(raised.get_cell_source_id(Vector2i(30, 6)) >= 0 and not heap.visible, "and stands again when it rebuilds")
	# the brazier on the tall run's top goes with the wall under it (or the face in front of
	# it), and comes back
	var brazier: AnimatedSprite2D = null
	for s in v._tiles.get_node("Walls").get_children():
		if String(s.name).begins_with("brazier") and (s.get_meta("cells") as Rect2i).has_point(Vector2i(90, 11)):
			brazier = s
	assert_true(brazier != null, "a brazier stands on the wall [90, 2, 2, 10]")
	assert_true(brazier.visible, "lit while the wall stands")
	assert_true(sim.terrain.smash(Vector2i(90, 11)), "a charge smashes the wall under it")
	v.refresh()
	assert_false(brazier.visible, "a smashed wall drops its brazier: nothing floats over the rubble")
	sim.terrain.set_cell(Vector2i(90, 11), TerrainGrid.WALL)
	v.refresh()
	assert_true(brazier.visible, "and it stands again with the wall")
	var bc: Rect2i = brazier.get_meta("cells")
	assert_true(bc.position.y < 9, "it stands on the top, behind the face (rows 9-11): %s" % bc)
	assert_true(sim.terrain.smash(Vector2i(91, 11)), "a charge smashes the face's foot in front of it")
	v.refresh()
	assert_false(brazier.visible, "it goes: it would hang on the face the wall grows over the gap")
	sim.terrain.set_cell(Vector2i(91, 11), TerrainGrid.WALL)
	v.refresh()
	assert_true(brazier.visible, "and comes back with the face")
	# a rockslide's rubble: WALL cells the map didn't lay; the sim's own kind of change
	for cx in range(60, 64):
		sim.terrain.set_cell(Vector2i(cx, 12), TerrainGrid.WALL)
	v.refresh()
	assert_eq(pieces.get_used_cells().size(), before, "runtime rubble is no scene piece")
	assert_eq(v._overlay.get_cell_source_id(Vector2i(61, 12)), -1, "and no pit or crack tile either (the bands draw its heap)")
	sim.terrain.smash(Vector2i(61, 12))
	v.refresh()
	var at := v._overlay.get_cell_atlas_coords(Vector2i(61, 12))
	assert_true(ArenaView.is_crack(at.x + at.y * ArenaView.OV_COLS), "smashed rubble is cracked floor")
	v.free()
