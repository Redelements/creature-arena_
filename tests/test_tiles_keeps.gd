extends TestCase
## Twin Keeps on tiles: the Capture the Flag map keeps its 150 x 64 cells (75 x 32 tiles)
## and every piece, drawn from the "keeps" set: each wall a y-sorted run of Castle wall-kit
## sprites (rubble hidden under each tile), the fences as joined lines, the brush as round
## hedge clumps, water under every shallows cell and under the bridge (so a fallen bridge
## shows it), a cobble causeway on the bridge, trees along the top margin, the waterfall
## where the river enters at the top with its pool inside the banks, team braziers on the
## gate posts and team banners hung on the keeps' walls (they fall with the wall). Every
## water tile at the river's edge (the island, the head, the bridge's ends) carries its
## bank. The river sits below the floor (a kerb of ledge stones along the water and along
## the top of the far bank's rock drop, rounded corners) in a ragged dirt shoulder on the land
## round it and the islands; pebbles lie by it and tufts and small flowers on the open grass,
## never on the bridge, the flag bases' capture zones, the shrines, the brush beds or the
## keeps' gates. ArenaView treats it as tiled.

const BT := preload("res://tools/build_tiles.gd")
const SCENE := "res://assets/arenas/twin_keeps.tscn"
const MANIFEST := "res://assets/tiles/keeps_manifest.json"


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


static func _tiles_of(r: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in range(floori(float(r[1]) / 2), ceili(float(int(r[1]) + int(r[3])) / 2)):
		for tx in range(floori(float(r[0]) / 2), ceili(float(int(r[0]) + int(r[2])) / 2)):
			out.append(Vector2i(tx, ty))
	return out


static func _coords(list: Array) -> Array:
	return list.map(func(a): return Vector2i(int(a[0]), int(a[1])))


func test_the_scene_covers_the_map_with_its_pieces_in_place() -> void:
	var map := ArenaMap.get_map("twin_keeps")
	var man := _manifest()
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var ground := root.get_node("Ground") as TileMapLayer
	var water := root.get_node("Water") as TileMapLayer
	var pieces := root.get_node("Pieces") as TileMapLayer
	assert_eq(ground.get_used_cells().size(), 75 * 32, "75 x 32 tiles of floor, no ring")
	assert_false(man["pieces"].has("castle_v"), "no facade tiles stood on end for the walls (wrong cut 3)")
	var fence_src := 16  # build_tiles.gd SRC_FENCE: the first fence line
	var walls := root.get_node("Walls")
	var rubble := root.get_node("Rubble")
	assert_true(walls.y_sort_enabled, "a run's near sprites overlap the far ones")
	var bridge: Array = _coords(man["pieces"]["bridge"]) + _coords(man["pieces"].get("bridge_t", [])) + _coords(man["pieces"].get("bridge_b", []))
	for piece in map["pieces"]:
		var kind := String(piece["kind"])
		for c in _tiles_of(piece["rect"]):
			match kind:
				"wall":
					assert_eq(pieces.get_cell_source_id(c), -1, "%s: no tile under the wall sprites" % c)
					var standing := walls.get_children().filter(func(n): return n.has_meta("cells") and (n.get_meta("cells") as Rect2i).intersects(Rect2i(c * 2, Vector2i(2, 2))) and String(n.name).begins_with("castle"))
					assert_eq(standing.size(), 1, "%s: one castle wall sprite" % c)
					var heaps := rubble.get_children().filter(func(n): return (n.get_meta("cells") as Rect2i).intersects(Rect2i(c * 2, Vector2i(2, 2))))
					assert_true(heaps.size() == 1 and not heaps[0].visible, "%s: its rubble, hidden while it stands" % c)
				"fence":
					assert_eq(pieces.get_cell_source_id(c), fence_src, "%s: a fence line tile" % c)
				"brush":
					assert_eq(pieces.get_cell_source_id(c), -1, "%s: no tuft tile, the bed is bush clumps" % c)
				"shallows":
					assert_eq(water.get_cell_source_id(c), 0, "%s: water under the shallows" % c)
					var td := water.get_cell_tile_data(c)
					assert_true(td != null and td.terrain == 1, "%s: the water terrain" % c)
	for b in map["bridges"]:
		for c in _tiles_of(b["rect"]):
			assert_true(pieces.get_cell_atlas_coords(c) in bridge, "%s: the causeway on the bridge" % c)
			assert_eq(water.get_cell_source_id(c), 0, "%s: and water under it" % c)
		# its ends over the river: the lit lip upstream, the causeway's face downstream
		var r: Array = b["rect"]
		var top := Vector2i(int(r[0]) / 2 + 1, int(r[1]) / 2)
		var bottom := Vector2i(int(r[0]) / 2 + 1, (int(r[1]) + int(r[3])) / 2 - 1)
		assert_true(pieces.get_cell_atlas_coords(top) in _coords(man["pieces"]["bridge_t"]), "the causeway's upstream end has its lip")
		assert_true(pieces.get_cell_atlas_coords(bottom) in _coords(man["pieces"]["bridge_b"]), "and its downstream end its face")
	root.free()


func test_the_trees_the_waterfall_the_braziers_and_the_banners_stand_where_the_map_says() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var decor := root.get_node("Decor")
	var anim := root.get_node("Anim")
	var walls := root.get_node("Walls")
	var kinds := {}
	for s in decor.get_children():
		kinds[String(s.name).split("_")[0]] = true
		var sp := s as Sprite2D
		assert_true(sp != null and sp.texture != null, "%s is a sprite with its picture" % s.name)
		# every tree stands in the top margin, its feet on the floor's top edge (y = 0 in scene
		# pixels), so no canopy covers walkable floor
		assert_true(sp.position.y + sp.texture.get_height() <= 32.0, "%s stands above the floor" % s.name)
	for k in ["oak", "birch", "pine", "bush"]:
		assert_true(kinds.has(k), "a %s among the trees" % k)
	assert_true(decor.get_child_count() >= 12, "a line of trees along the top")
	var falls := anim.get_children().filter(func(n): return String(n.name).begins_with("waterfall"))
	assert_eq(falls.size(), 1, "one waterfall")
	var w := falls[0] as AnimatedSprite2D
	# feet [80, 154] at tile (37, 0)'s bottom middle: x 37.5 * 32 - 80, y 32 - 154; its foam
	# pool (x 19..140 of the frame) lies inside the river's head (cells 71..79: x 1136..1264)
	assert_eq(w.position, Vector2(1120, -122), "the waterfall (160 x 160, feet at 154) pours onto the river's first row, its curtain over the stands")
	assert_true(w.position.x + 19 >= 1136 and w.position.x + 140 <= 1264, "its pool stays inside the banks")
	var tex := w.sprite_frames.get_frame_texture("default", 0)
	assert_eq(tex.get_size(), Vector2(160, 160), "Set 1's three-wide fall")
	var img := tex.get_image()
	var lum := 0.0
	var n := 0
	for y in range(40, 130, 3):
		for x in range(30, 130, 3):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				lum += c.get_luminance()
				n += 1
	assert_true(n > 0 and lum / n > 0.2, "tinted like the river, not a dark slab (luminance %.2f)" % (lum / maxf(1, n)))
	assert_eq(w.sprite_frames.get_frame_count("default"), 8, "its eight frames")
	assert_true(w.autoplay == "default", "and it plays")
	# the braziers and banners hang on the walls: in the y-sorted Walls, each on a wall cell
	# (so it hides when that cell is smashed), red on the left keep, cyan / blue on the right
	var map := ArenaMap.get_map("twin_keeps")
	var wall_cells := {}
	for piece in map["pieces"]:
		if String(piece["kind"]) == "wall":
			var r: Array = piece["rect"]
			for cy in range(int(r[1]), int(r[1]) + int(r[3])):
				for cx in range(int(r[0]), int(r[0]) + int(r[2])):
					wall_cells[Vector2i(cx, cy)] = true
	var hung := {"brazier_red": 0, "brazier_cyan": 0, "banner_red": 0, "banner_blue": 0}
	for s in walls.get_children():
		var kind := String(s.name).rsplit("_", true, 1)[0]
		if not hung.has(kind):
			continue
		hung[kind] += 1
		var cell: Vector2i = (s.get_meta("cells") as Rect2i).position
		assert_true(wall_cells.has(cell), "%s stands on a wall cell (%s)" % [s.name, cell])
		var left := cell.x < 75
		assert_eq(left, kind.ends_with("red"), "%s: red on the left keep, blue on the right" % s.name)
	assert_eq(hung["brazier_red"], 2, "a red brazier on each of the left gate's posts")
	assert_eq(hung["brazier_cyan"], 2, "a cyan one on each of the right gate's")
	assert_eq(hung["banner_red"], 4, "red banners on the left keep's walls")
	assert_eq(hung["banner_blue"], 4, "blue ones on the right keep's")
	assert_eq(anim.get_children().filter(func(n): return String(n.name).begins_with("torch")).size(), 0, "the braziers replace the torches")
	root.free()


func test_the_river_has_its_banks() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var problems: Array = load("res://tests/test_tiles_floodgate.gd").bank_problems(root, _manifest())
	assert_true(problems.is_empty(), "every edge of the river has its bank: %s" % [problems])
	var bank := root.get_node("WaterBank") as TileMapLayer
	assert_true(bank.get_index() > root.get_node("WaterSurface").get_index(), "drawn over the water's surface")
	assert_true(bank.get_index() < root.get_node("Pieces").get_index(), "and under the bridge")
	root.free()


func test_the_river_is_sunk_in_a_shoulder_with_scatter_off_the_marked_spots() -> void:
	var man := _manifest()
	var sh: Dictionary = man["ground"]["shores"]["water"]
	assert_true(sh.has("shoulder") and not (sh["shoulder"] as Dictionary).is_empty(), "the bank cuts a shoulder")
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/tile_recipes/keeps.json"))
	var spec: Dictionary = recipe["ground"]["shores"]["water"]
	assert_true(bool(spec.get("edge_over_face", false)) and spec.has("edge"), "a kerb along the water and over the far bank's drop")
	assert_true(int(spec.get("face_px", 0)) >= 10, "a drop you can see on the far bank")
	assert_true(float(spec.get("radius", 0)) >= 10.0, "rounded corners")
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var map := ArenaMap.get_map("twin_keeps")
	var size := ArenaMap.size_of(map)
	var grid := TerrainGrid.new(size.x, size.y)
	grid.load_map(map)
	var water := root.get_node("Water") as TileMapLayer
	var shoulder := root.get_node("Shoulder") as TileMapLayer
	assert_true(shoulder.get_index() < water.get_index(), "the shoulder under the water")
	var wet := {}
	for c in water.get_used_cells():
		wet[c] = true
	var ring := 0
	for t in shoulder.get_used_cells():
		if wet.has(t):
			continue
		ring += 1
		for dy in 2:
			for dx in 2:
				assert_eq(grid.get_base(t * 2 + Vector2i(dx, dy)), TerrainGrid.INTACT, "a shoulder tile on floor cells only: %s" % t)
	assert_true(ring >= 40, "dirt round the river and both islands: %d tiles" % ring)
	for island in [Vector2i(36, 5), Vector2i(36, 25)]:  # each island's west edge, beside the channel
		assert_true(shoulder.get_cell_source_id(island) >= 0, "the island at %s has its shoulder" % island)
	# the scatter: some, subtle, and never on a marked spot
	var scatter := root.get_node("Scatter") as TileMapLayer
	var cells := scatter.get_used_cells()
	assert_true(cells.size() >= 30, "pebbles, tufts and flowers (%d)" % cells.size())
	assert_true(cells.size() <= size.x * size.y / 20, "at most a few percent of the floor (%d)" % cells.size())
	var clear: Dictionary = BT.scatter_clear(map["tiles"], map, grid)
	var gates: Array = map["tiles"]["scatter_clear"]
	assert_eq(gates.size(), 6, "three gates a keep kept clear")
	var bridge: Array = map["bridges"][0]["rect"]
	for c in cells:
		assert_false(clear.has(c), "off the gates, bases and shrines: %s" % c)
		assert_false(Rect2i(int(bridge[0]), int(bridge[1]), int(bridge[2]), int(bridge[3])).grow(1).has_point(c), "off the bridge: %s" % c)
		for side in map["bases"]:
			var b: Array = map["bases"][side]
			assert_true(grid.cell_center(c).distance_to(Vector2(b[0], b[1])) >= 40.0, "off the %s flag's capture zone: %s" % [side, c])
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if grid.in_bounds(n):
					assert_true(grid.get_base(n) != TerrainGrid.BRUSH, "clear of the brush beds: %s" % c)
		assert_eq(grid.get_base(c), TerrainGrid.INTACT, "on plain floor: %s" % c)
	root.free()


func test_arena_view_draws_it_from_tiles_and_a_fallen_bridge_shows_water() -> void:
	var was: String = MatchFactory.arena
	MatchFactory.arena = "twin_keeps"
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = "grass"
	v.arena_id = "twin_keeps"
	v.set_terrain(sim.terrain)
	assert_true(v.tiled(), "Twin Keeps draws from tiles")
	assert_eq(sim.terrain.cols, 150, "the sim's grid is what it was")
	var pieces := v._tiles.get_node("Pieces") as TileMapLayer
	var bridge: Array = ArenaMap.get_map("twin_keeps")["bridges"][0]["rect"]
	var tile := Vector2i(int(bridge[0]) / 2 + 1, int(bridge[1]) / 2 + 1)
	assert_eq(pieces.get_cell_source_id(tile), 1, "the causeway stands")
	# a smashed wall cell shows its rubble, and the banner hung there falls with the wall
	var at := Vector2i(4, 21)  # the left keep's top wall, under its first banner
	var on: Array = v._tiles.get_node("Walls").get_children().filter(func(n): return (n.get_meta("cells") as Rect2i).has_point(at))
	var heap: Array = v._tiles.get_node("Rubble").get_children().filter(func(n): return (n.get_meta("cells") as Rect2i).has_point(at))
	assert_eq(on.map(func(n): return String(n.name).rsplit("_", true, 1)[0]), ["castle", "banner_red"], "a wall sprite and a red banner over cell %s" % at)
	assert_eq(heap.size(), 1, "and one rubble heap")
	assert_true(on[0].visible and on[1].visible and not heap[0].visible, "the wall stands")
	assert_true(sim.terrain.smash(at), "a charge smashes the wall cell")
	v.refresh()
	assert_true(heap[0].visible and not on[0].visible and not on[1].visible, "rubble shows; the wall and its banner are gone")
	sim.terrain.set_cell(at, TerrainGrid.WALL)
	v.refresh()
	assert_true(on[0].visible and on[1].visible and not heap[0].visible, "both stand again when it rebuilds")
	sim.terrain.crack_cell(Vector2i(20, 10))
	v.refresh()
	assert_eq(v._overlay.get_cell_source_id(Vector2i(20, 10)), 0, "a crack sets an overlay cell")
	for cy in range(int(bridge[1]), int(bridge[1]) + int(bridge[3])):
		for cx in range(int(bridge[0]), int(bridge[0]) + int(bridge[2])):
			sim.terrain.set_cell(Vector2i(cx, cy), TerrainGrid.SHALLOWS)
	v.refresh()
	assert_eq(pieces.get_cell_source_id(tile), -1, "the bridge fell: the causeway is gone, the water under it shows")
	assert_eq(v._overlay.get_cell_source_id(Vector2i(int(bridge[0]) + 2, int(bridge[1]) + 2)), -1, "no pit tile over the river")
	v.free()
