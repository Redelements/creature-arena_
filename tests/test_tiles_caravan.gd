extends TestCase
## Dustwind Pass on the Desert set (tools/tile_recipes/desert.json): the cut's opaque 5 x 5
## blobs give nine side combinations a terrain, the scene is the 110 x 20 floor and its
## ring, the walls stand as runs of stacked rock (one tall sprite a tile, a wide-footed end,
## rubble hidden under each), the brush as beds of sage bushes, the fences as oriented
## fence tiles, the road and scrub are painted, the margins carry low rocks and palms, and
## the map draws as tiles: a smashed wall shows its rubble, and runtime rockslide rubble is
## still handled (a WALL the sim adds is not a piece).

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
	for kind in ["fence_h", "fence_v"]:
		assert_true(man["pieces"].get(kind, []).size() >= 2, "%s pieces" % kind)
	var roles: Dictionary = man["walls"]["rock"]["roles"]
	assert_eq(roles["mid"].size(), 4, "four rock pillars (two, and each mirrored) for a run's middle")
	for role in ["bottom", "left", "right", "rubble"]:
		assert_gt(roles.get(role, []).size(), 0, "a wall %s sprite" % role)
	for sp in roles["mid"]:
		assert_gt(int(sp["size"][1]), 32, "a pillar stands taller than its tile, so a run overlaps into one wall")
	assert_eq(man["bushes"]["sage"]["clumps"].size(), 9, "the sage bush is a nine-slice")
	for d in ["rocks", "rocks_b", "agave"]:
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
	# the wall at cells [30, 2, 2, 6] is tiles (15, 1..3): a pillar on each, the wide foot last
	var walls := root.get_node("Walls")
	var rubble := root.get_node("Rubble")
	assert_true(walls.y_sort_enabled, "a run's near pillars overlap the far ones")
	assert_eq(walls.get_child_count(), 24, "a sprite on every wall tile (3 + 4 + 5, twice)")
	assert_eq(rubble.get_child_count(), 24, "and its rubble under it")
	var run: Array = []
	for s in walls.get_children():
		if Rect2i(30, 2, 2, 6).encloses(s.get_meta("cells")):
			run.append(s)
	assert_eq(run.size(), 3, "the wall at [30, 2, 2, 6] stands as three pillars")
	run.sort_custom(func(a, b): return a.position.y < b.position.y)
	var foot: Vector2 = -(run[2] as Sprite2D).offset
	var bottoms: Array = man["walls"]["rock"]["roles"]["bottom"].map(func(sp): return Vector2(float(sp["feet"][0]), float(sp["feet"][1])))
	assert_true(foot in bottoms, "the run's near end is a wide-footed stack")
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
	assert_eq(decor.get_child_count(), 12, "the margins' rocks and agave")
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
	assert_eq(before, 10, "the map's fences as pieces (walls and brush are sprites)")
	# a smashed wall tile shows its rubble, and its pillar again once the floor heals
	var pillar: Sprite2D = null
	var heap: Sprite2D = null
	for s in v._tiles.get_node("Walls").get_children():
		if (s.get_meta("cells") as Rect2i).has_point(Vector2i(30, 6)):
			pillar = s
	for s in v._tiles.get_node("Rubble").get_children():
		if (s.get_meta("cells") as Rect2i).has_point(Vector2i(30, 6)):
			heap = s
	assert_true(pillar != null and heap != null, "a pillar and a heap over cell (30, 6)")
	assert_true(pillar.visible and not heap.visible, "the wall stands")
	assert_true(sim.terrain.smash(Vector2i(30, 6)), "a charge smashes a wall cell")
	v.refresh()
	assert_true(heap.visible and not pillar.visible, "the smashed tile shows loose rocks, not its pillar")
	sim.terrain.set_cell(Vector2i(30, 6), TerrainGrid.WALL)
	v.refresh()
	assert_true(pillar.visible and not heap.visible, "and stands again when it rebuilds")
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
