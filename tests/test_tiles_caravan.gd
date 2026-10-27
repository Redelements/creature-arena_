extends TestCase
## Dustwind Pass on the Desert set (tools/tile_recipes/desert.json): the cut's opaque 5 x 5
## blobs give nine side combinations a terrain, the scene is the 110 x 20 floor and its
## ring, the walls stand as boulder tiles, the fences as oriented fence tiles, the road and
## scrub are painted, the margins carry the spires and palms, and the map draws as tiles
## with its runtime rockslide rubble still handled (a WALL the sim adds is not a piece).

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
	for fill in ["sand", "gravel", "scrub_fill"]:
		assert_eq(man["ground"]["fills"][fill].size(), 16, "a 4 x 4 %s fill" % fill)
	assert_eq(man["ground"]["fills"]["earth_fill"].size(), 9, "a 3 x 3 packed-earth fill")
	for kind in ["boulder", "tuft", "sprig", "fence_h", "fence_v"]:
		assert_true(man["pieces"].get(kind, []).size() >= 2, "%s pieces" % kind)
	for d in ["spire", "stack", "agave"]:
		assert_true(man["decor"].has(d), "decor " + d)
	assert_eq(int(man["anim"]["palm"]["frames"]), 10, "the palm strip's ten frames")
	assert_eq(int(man["anim"]["palm"]["frame"][0]), 64, "64 px wide each")


func test_the_desert_tileset_names_its_terrains() -> void:
	var ts: TileSet = load(GROUND)
	var names := []
	for i in ts.get_terrains_count(0):
		names.append(ts.get_terrain_name(0, i))
	assert_eq(names, ["earth", "scrub"])
	assert_eq(ts.get_terrain_set_mode(0), TileSet.TERRAIN_MODE_MATCH_SIDES)
	var pieces := ts.get_source(1) as TileSetAtlasSource
	assert_true(pieces != null and pieces.get_tiles_count() == 14, "4 boulders, 3 tufts, 2 sprigs, 3 + 2 fence tiles")


func test_the_pass_scene_has_road_walls_fences_and_margins() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var ground := root.get_node("Ground") as TileMapLayer
	assert_eq(ground.get_used_cells().size(), 112 * 22, "the 110 x 20 floor and a tile round it")
	var man := _manifest()
	var sand: Array = man["ground"]["fills"]["sand"].map(func(a): return Vector2i(int(a[0]), int(a[1])))
	var gravel: Array = man["ground"]["fills"]["gravel"].map(func(a): return Vector2i(int(a[0]), int(a[1])))
	assert_true(ground.get_cell_atlas_coords(Vector2i(50, 3)) in sand, "the floor is sand")
	assert_true(ground.get_cell_atlas_coords(Vector2i(50, -1)) in gravel, "the ring is the gravel verge")
	var earth := root.get_node("Earth") as TileMapLayer
	var scrub := root.get_node("Scrub") as TileMapLayer
	assert_gt(earth.get_used_cells().size(), 100, "the packed-earth road under the track")
	assert_gt(scrub.get_used_cells().size(), 100, "scrub round the brush beds")
	for c in [Vector2i(10, 10), Vector2i(30, 5), Vector2i(55, 12), Vector2i(100, 10)]:
		assert_true(earth.get_cell_source_id(c) == 0 and earth.get_cell_tile_data(c).terrain == 0, "road under the track at %s" % c)
	var pieces := root.get_node("Pieces") as TileMapLayer
	var p: Dictionary = man["pieces"]
	var boulders: Array = p["boulder"].map(func(a): return Vector2i(int(a[0]), int(a[1])))
	var fh: Array = p["fence_h"].map(func(a): return Vector2i(int(a[0]), int(a[1])))
	# the wall at cells [30, 2, 2, 6] is tiles (15, 1..3); the fence at [38, 30, 10, 1] tiles (19..23, 15)
	for ty in range(1, 4):
		assert_true(pieces.get_cell_atlas_coords(Vector2i(15, ty)) in boulders, "a boulder on the wall at row %d" % ty)
	for tx in range(19, 24):
		assert_true(pieces.get_cell_atlas_coords(Vector2i(tx, 15)) in fh, "a horizontal fence tile at %d" % tx)
	assert_true(pieces.get_cell_source_id(Vector2i(50, 8)) == -1, "nothing on the open road")
	var decor := root.get_node("Decor")
	var anim := root.get_node("Anim")
	assert_eq(decor.get_child_count(), 12, "the margins' spires and agave")
	assert_eq(anim.get_child_count(), 5, "five palms")
	for s in decor.get_children():
		var sp := s as Sprite2D
		# the sprite's bottom (its feet plus a shadow of a few px) is above the floor or below it
		var bottom := sp.position.y + sp.texture.get_height()
		assert_true(bottom <= 12.0 or bottom >= 20 * 32, "decor stands off the floor: %s, bottom at %s" % [sp.name, bottom])
	for s in anim.get_children():
		assert_true((s as AnimatedSprite2D).autoplay == "default", "palms sway on their own")
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
	assert_eq(before, 94, "the map's walls, fences and brush as pieces")
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
