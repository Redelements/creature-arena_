extends TestCase
## The Greenhouse Dome on tiles (the grassland set: GrassLand's bright meadow and cliff face,
## Set 1 grass blobs, Decorative Props fences): the set's terrains cover the 16 side
## combinations, the scene draws every fence line as one joined line (each tile a post in
## the half of the tile the one-cell fence lies in, rails to the line's next tiles, none
## past its ends) and a hedge of swaying clumps on every brush bed, the margin decor stays
## off the floor and under the stand wall, the map draws from tiles, and a flattened brush
## cell loses its clumps until it grows back. The map's pieces and play are unchanged (no sim change).
## The art pass: swaying DecorativeProps flowers stand on the beds' edge cells, and potted
## herbs (Houses smallobj) and GrassLand's tiny bushes join the pots in the side margins.

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
	for fill in ["turf", "meadow", "meadow_bright"]:
		assert_eq(man["ground"]["fills"][fill].size(), 16, "a 4 x 4 %s fill" % fill)
	for kind in ["tuft", "sprig"]:
		assert_gt(man["pieces"][kind].size(), 0, "%s tiles were cut" % kind)
	var fl: Dictionary = man["fencelines"]["wood"]
	assert_eq(Vector2i(int(fl["cell"][0]), int(fl["cell"][1])), Vector2i(32, 64), "a fence line's tiles rise a tile over their cell")
	assert_eq(fl["spots"].size(), 9, "a post spot per half and middle, across and down")
	var bush: Dictionary = man["bushes"]["green"]
	assert_true(bush.get("blobs", false), "the beds are round clumps scattered, not a nine-slice")
	assert_gt(bush["clumps"].size(), 5, "enough clump shapes that neighbours differ")
	var ts: TileSet = load(GROUND)
	assert_eq(ts.get_terrain_name(0, 0), "grass")
	assert_eq(ts.get_terrain_set_mode(0), TileSet.TERRAIN_MODE_MATCH_SIDES)


func test_the_scene_fences_every_fence_line_and_plants_every_bed() -> void:
	var man := _manifest()
	var spots: Array = man["fencelines"]["wood"]["spots"]
	var root := (load(SCENE) as PackedScene).instantiate()
	var pieces := root.get_node("Pieces") as TileMapLayer
	var fence_src := 16  # build_tiles.gd SRC_FENCE: the first fence line
	var src := pieces.tile_set.get_source(fence_src) as TileSetAtlasSource
	assert_eq(src.texture_region_size, Vector2i(32, 64), "fence tiles carry the post rising over the tile")
	assert_eq(src.get_tile_data(Vector2i(0, 0), 0).texture_origin, Vector2i(0, 16), "lifted so the lower 32 px sit on the cell")
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
		var vertical: bool = int(r[3]) > int(r[2])
		var tiles := _tiles_of(r)
		for i in tiles.size():
			var c: Vector2i = tiles[i]
			expected += 1
			assert_eq(pieces.get_cell_source_id(c), fence_src, "%s at %s is a fence line tile" % [kind, c])
			var at := pieces.get_cell_atlas_coords(c)
			# arms to the line's next tiles: none past its ends (a post the rail stops at)
			var arms := 0
			if i > 0:
				arms |= 4 if vertical else 1
			if i < tiles.size() - 1:
				arms |= 8 if vertical else 2
			assert_eq(at.x, arms, "%s: rails to its neighbours only (arm mask %d)" % [c, at.x])
			# the post in the half of the tile the one-cell line lies in
			var spot := Vector2i(int(spots[at.y][0]), int(spots[at.y][1]))
			if vertical:
				assert_eq(spot.x, 8 if int(r[0]) % 2 == 0 else 24, "%s: the post in the line's half across" % c)
			else:
				assert_eq(spot.y, 8 if int(r[1]) % 2 == 0 else 24, "%s: the post in the line's half down" % c)
	assert_eq(pieces.get_used_cells().size(), expected, "a piece tile on every fence tile and nowhere else")
	assert_eq(beds, 5, "five beds")
	for s in brush.get_children():
		assert_true(s is AnimatedSprite2D and (s as AnimatedSprite2D).sprite_frames.get_frame_count(s.animation) == 5, "%s sways over 5 frames" % s.name)
	var ground := root.get_node("Ground") as TileMapLayer
	assert_true(ground.get_cell_atlas_coords(Vector2i(20, 9)) in _coords(man["ground"]["fills"]["meadow_bright"]), "the bright meadow under the floor")
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
		if fy < 0.0 and fy > -SimDefs.CELL * ArtScale.TILE_CELLS:
			# in the top margin (one tile): its top stays under the stand wall
			var top := s.position.y / ArtScale.PX_PER_UNIT
			assert_true(top >= -SimDefs.CELL * ArtScale.TILE_CELLS, "%s stands in the margin, not up the wall (top %.1f)" % [s.name, top])
	root.free()


func test_flowers_on_the_beds_edges_and_herbs_in_the_side_margins() -> void:
	var man := _manifest()
	for kind in ["flower_pink", "flower_yellow", "spike_pink", "spike_orange"]:
		var a: Dictionary = man["anim"][kind]
		assert_eq(Vector2i(int(a["frame"][0]), int(a["frame"][1])), Vector2i(32, 32), "%s: 32 px frames" % kind)
		assert_eq(int(a["frames"]), 4, "%s: four frames" % kind)
		var img := (load("res://assets/tiles/" + String(a["source"])) as Texture2D).get_image()
		var rooted := false
		for dx in range(-3, 4):
			rooted = rooted or img.get_pixel(int(a["feet"][0]) + dx, int(a["feet"][1])).a > 0.5
		assert_true(rooted, "%s: its feet on its roots, not floating" % kind)
	var brush := {}
	for piece in ArenaMap.get_map("greenhouse").get("pieces", []):
		if String(piece.get("kind", "")) == "brush":
			var r: Array = piece["rect"]
			for cy in range(int(r[1]), int(r[1]) + int(r[3])):
				for cx in range(int(r[0]), int(r[0]) + int(r[2])):
					brush[Vector2i(cx, cy)] = true
	var root := (load(SCENE) as PackedScene).instantiate()
	var anim := root.get_node("Anim")
	assert_eq(anim.get_child_count(), 10, "flowers round the five beds")
	for s in anim.get_children():
		var kind := String(s.name).rsplit("_", true, 1)[0]
		var feet: Vector2 = (s.position + Vector2(man["anim"][kind]["feet"][0], man["anim"][kind]["feet"][1])) / ArtScale.PX_PER_UNIT
		var cell := Vector2i(floori(feet.x / SimDefs.CELL), floori(feet.y / SimDefs.CELL))
		assert_true(brush.has(cell), "%s stands on a brush cell (%s)" % [s.name, cell])
		var edge := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			edge = edge or not brush.has(cell + d)
		assert_true(edge, "%s on a bed's edge, not inside it (%s)" % [s.name, cell])
	var kinds := {}
	for d in root.get_node("Decor").get_children():
		var s := d as Sprite2D
		var kind := String(s.name).rsplit("_", true, 1)[0]
		if kind.begins_with("herb_") or kind.begins_with("shrub_"):
			kinds[kind] = true
			var fx := (s.position.x + float(man["decor"][kind]["feet"][0])) / ArtScale.PX_PER_UNIT
			var fy := (s.position.y + float(man["decor"][kind]["feet"][1])) / ArtScale.PX_PER_UNIT
			assert_true(fx < 0.0 or fx > SimDefs.GRID_COLS * SimDefs.CELL, "%s in a side margin (x %.1f)" % [s.name, fx])
			assert_true(fy > 0.0 and fy < SimDefs.GRID_ROWS * SimDefs.CELL, "%s beside the floor, not in the top margin (y %.1f)" % [s.name, fy])
	assert_gt(kinds.size(), 5, "herbs and tiny bushes of several kinds: %s" % [kinds.keys()])
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


## The hand dressing (assets/arenas/greenhouse_dressing.tscn, as Twin Keeps': assets/README.md
## "Dressing"): the ground scene instances it; props stand only on the four fence lines (their
## feet on a fence cell), each with a contact shadow unless it hangs on the rail; worn paths,
## damp earth, shady and sunlit meadow, flagstones and flower detail lie on plain floor only;
## every lantern has its lamp in the arena's `lights`, burning by day; two crowns hang over the
## corner beds and fade over a fighter we see.
const DRESSING := "res://assets/arenas/greenhouse_dressing.tscn"
const PPU := 2.0  ## ArtScale.PX_PER_UNIT


func _grid() -> TerrainGrid:
	var map := ArenaMap.get_map("greenhouse")
	var size := ArenaMap.size_of(map)
	var grid := TerrainGrid.new(size.x, size.y)
	grid.load_map(map)
	return grid


static func _kind(n: Node) -> String:
	return String(n.get_meta("kind", String(n.name).rsplit("_", true, 1)[0]))


func test_the_dressing_is_instanced_and_props_stand_on_the_fences() -> void:
	var map := ArenaMap.get_map("greenhouse")
	assert_eq(String(map["tiles"].get("dressing", "")), DRESSING, "the map names its dressing scene")
	var root := (load(SCENE) as PackedScene).instantiate()
	var d := root.get_node_or_null("Walls/Dressing") as Node2D
	assert_true(d != null and d.scene_file_path == DRESSING, "instanced in the wall run, not copied")
	var grid := _grid()
	var props := d.get_node("Props")
	assert_true(props.get_child_count() >= 30, "every fence dressed (%d props)" % props.get_child_count())
	var kinds := {}
	var runs := {}
	for p: Node2D in props.get_children():
		kinds[_kind(p)] = true
		var foot := Vector2i(floori(p.position.x / (8 * PPU)), floori((p.position.y - 1.0) / (8 * PPU)))
		assert_eq(grid.get_base(foot), TerrainGrid.FENCE, "%s stands on a fence cell (%s)" % [p.name, foot])
		runs[Vector2i(foot.x / 20, foot.y / 12)] = true
		var sh := p.get_node_or_null("Shadow") as Sprite2D
		if sh != null:
			assert_true(sh.show_behind_parent, "%s: its contact shadow under it" % p.name)
	assert_true(runs.size() >= 4, "on all four fence lines")
	for k in ["lantern", "barrel_open", "bucket", "sack_seed_a", "basket_carrot", "sheaf", "ivy", "pot_clay", "crate_small"]:
		assert_true(kinds.has(k), "a %s among the props" % k)
	var paths := d.get_node("Paths") as TileMapLayer
	assert_true(paths.get_used_cells().size() >= 80, "worn paths between the beds (%d tiles)" % paths.get_used_cells().size())
	for layer in d.get_children():
		if layer is TileMapLayer and layer.name != "Detail":
			for t in (layer as TileMapLayer).get_used_cells():
				for dy in 2:
					for dx in 2:
						assert_eq(grid.get_base(t * 2 + Vector2i(dx, dy)), TerrainGrid.INTACT, "%s tile on plain floor: %s" % [layer.name, t])
	var detail := d.get_node("Detail") as TileMapLayer
	assert_true(detail.get_used_cells().size() >= 150, "moss, flowers, clover, leaves, stones (%d)" % detail.get_used_cells().size())
	for c in detail.get_used_cells():
		assert_eq(grid.get_base(c), TerrainGrid.INTACT, "flat detail on plain floor: %s" % c)
	for f: Node2D in d.get_node("Flat").get_children():
		var s := f as Sprite2D
		var mid := ((s.position + s.offset + s.texture.get_size() * 0.5) / PPU / 8.0).floor()
		assert_eq(grid.get_base(Vector2i(mid)), TerrainGrid.INTACT, "%s lies flat on the floor" % f.name)
	root.free()


func test_every_lantern_has_a_lamp_that_burns_by_day() -> void:
	var map := ArenaMap.get_map("greenhouse")
	var lights: Array = map.get("lights", [])
	assert_true(lights.size() <= Light2DView.MAX_DAY_LAMPS, "at most %d day lamps" % Light2DView.MAX_DAY_LAMPS)
	assert_true(Light2DView.lamps_by_day(map, "day") and Light2DView.lamps_by_day(map, "sunset"), "they burn by day and at sunset")
	var d: Node = (load(DRESSING) as PackedScene).instantiate()
	var origin := Vector2(SimDefs.GRID_X, SimDefs.GRID_Y)
	var n := 0
	for p: Node2D in d.get_node("Props").get_children():
		if _kind(p) != "lantern":
			continue
		n += 1
		var an := p as AnimatedSprite2D
		var pic := Rect2((p.position + an.offset) / PPU, an.sprite_frames.get_frame_texture(an.animation, 0).get_size() / PPU).grow(4.0)
		pic.position += origin
		var lit := false
		for e in lights:
			if bool(e.get("lamp", false)) and float(e.get("day", 0.0)) > 0.0 and pic.has_point(Vector2(e["pos"][0], e["pos"][1])):
				lit = true
		assert_true(lit, "%s has its lamp on its flame" % p.name)
	assert_eq(n, lights.size(), "a lamp a lantern, no more")
	d.free()


func test_crowns_over_the_corner_beds_fade_over_a_fighter_we_see() -> void:
	var was: String = MatchFactory.arena
	MatchFactory.arena = "greenhouse"
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = "grass"
	v.arena_id = "greenhouse"
	v.set_terrain(sim.terrain)
	assert_eq(v.canopy_count(), 2, "a crown over each corner bed")
	for i in v.canopy_count():
		assert_true((v._canopies[i][2] as Rect2i).size != Vector2i.ZERO, "crown %d hangs over brush (it thins when the bed is flattened)" % i)
	var rect: Rect2 = v._canopies[0][1]
	sim.creatures[0].pos = rect.get_center()
	sim.creatures[1].pos = Vector2(-500, -500)
	v.canopy_points = ArenaView.canopy_watchers(sim, [false, true], 0)
	for f in 40:
		v._fade_canopies(1.0 / 60.0)
	assert_near(v.canopy_alpha(0), ArenaView.CANOPY_SEE, 0.001, "it lets us see our own fighter")
	v.free()
