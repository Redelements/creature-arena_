extends TestCase
## The "less flat" tile features (tools/cut_tiles.py raised / scatter, tools/build_tiles.gd
## styles.wall "raised:<name>", shoulder, scatter; src/view/raised_tiles.gd):
## raised walls are tiles on the wall's own cells only, a face on a column's last cells, a
## contact shadow on the floor away from the light; a smashed cell drops its tile and shows its
## rubble, the wall above it grows a face, and a rebuilt cell comes back. A shoulder of dirt
## rings the water on floor tiles only, under the water. Scatter is deterministic (a rebuild
## lays the same sprites) and never lies on water, walls, brush beds (or next to them) or
## the Stadium's markings, and leaves most of the floor clean.

const BT := preload("res://tools/build_tiles.gd")


func _raised_view() -> Array:
	var was: String = MatchFactory.arena
	MatchFactory.arena = "quarry"
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = "stone"
	v.arena_id = "quarry"
	v.set_terrain(sim.terrain)
	return [sim, v]


func test_a_column_shows_its_top_then_its_face() -> void:
	var cells := {}
	for y in 6:
		cells[Vector2i(0, y)] = true
		cells[Vector2i(1, y)] = true
	var up := func(c: Vector2i) -> bool: return cells.has(c)
	assert_eq(RaisedTiles.top_or_face_key(Vector2i(0, 0), up, 4, 2), "t10100", "the top-left corner: rims left and above")
	assert_eq(RaisedTiles.top_or_face_key(Vector2i(1, 1), up, 4, 2), "t01003", "the right side below it, its block's lower right quarter")
	assert_eq(RaisedTiles.top_or_face_key(Vector2i(0, 2), up, 4, 2), "f10400", "the face starts four cells from the end")
	assert_eq(RaisedTiles.top_or_face_key(Vector2i(1, 5), up, 4, 2), "f01431", "and reaches the floor")
	var short := {Vector2i(0, 0): true, Vector2i(0, 1): true}
	var up2 := func(c: Vector2i) -> bool: return short.has(c)
	assert_eq(RaisedTiles.top_or_face_key(Vector2i(0, 0), up2, 4, 2), "t11100", "a two-cell column keeps a top")
	assert_eq(RaisedTiles.top_or_face_key(Vector2i(0, 1), up2, 4, 2), "f11100", "and a one-cell face")
	# a long run: the plateau's top all the way down, blocks varied by hash, a face only at
	# its south end (in 3/4 view only the edge facing the camera shows a face)
	var run := {}
	for y in 26:
		run[Vector2i(0, y)] = true
		run[Vector2i(1, y)] = true
	var up3 := func(c: Vector2i) -> bool: return run.has(c)
	var seen := {}
	for y in 26:
		for x in 2:
			var key := RaisedTiles.top_or_face_key(Vector2i(x, y), up3, 4, 10)
			assert_eq(key.substr(0, 1), "f" if y >= 22 else "t", "cell (%d, %d): %s" % [x, y, key])
			if key.begins_with("t"):
				assert_eq(key.substr(1, 2), "10" if x == 0 else "01", "rims along both long sides: %s" % key)
				seen[key.substr(4, 1)] = true
	assert_true(seen.size() >= 3, "the top varies down the run: %s" % [seen.keys()])
	assert_eq(RaisedTiles.shadow_key(Vector2i(2, 3), up, false), "s1010", "the shadow on the far side of the light")
	assert_eq(RaisedTiles.shadow_key(Vector2i(3, 3), up, false), "w0", "a low sun's shadow runs on a second cell")
	assert_eq(RaisedTiles.shadow_key(Vector2i(-1, 3), up, false), "", "none on the lit side")
	assert_eq(RaisedTiles.shadow_key(Vector2i(0, 6), up, false), "s0100", "and under the face")
	assert_eq(RaisedTiles.shadow_key(Vector2i(-1, 3), up, true), "s1011", "a light from the right throws it left")


func test_the_quarry_walls_are_raised_on_their_own_cells() -> void:
	var root: Node = (load("res://assets/arenas/quarry.tscn") as PackedScene).instantiate()
	var map := ArenaMap.get_map("quarry")
	var size := ArenaMap.size_of(map)
	var grid := TerrainGrid.new(size.x, size.y)
	grid.load_map(map)
	var raised := root.get_node("Raised") as TileMapLayer
	var shadow := root.get_node("RaisedShadow") as TileMapLayer
	var walls := 0
	for i in grid.map_base.size():
		if grid.map_base[i] == TerrainGrid.WALL:
			walls += 1
	assert_eq(raised.get_used_cells().size(), walls, "one raised tile a wall cell")
	for c in raised.get_used_cells():
		assert_eq(grid.get_base(c), TerrainGrid.WALL, "raised only over the wall's own cells: %s" % c)
	assert_true(shadow.get_used_cells().size() > 0, "the walls cast contact shadows")
	for c in shadow.get_used_cells():
		assert_true(grid.get_base(c) != TerrainGrid.WALL, "shadows lie on the floor beside the wall: %s" % c)
	assert_true(shadow.get_index() < raised.get_index(), "the shadow under the wall")
	assert_true(raised.get_index() < root.get_node("Rubble").get_index(), "the rubble over the wall's layer")
	assert_true(raised.has_meta("raised"), "the layer carries what ArenaView repaints it with")
	root.free()


func test_a_smashed_cell_drops_its_shelf_and_the_wall_grows_a_face() -> void:
	var pair := _raised_view()
	var sim: MatchSim = pair[0]
	var v: ArenaView = pair[1]
	var raised := v._tiles.get_node("Raised") as TileMapLayer
	var shadow := v._tiles.get_node("RaisedShadow") as TileMapLayer
	var info: Dictionary = raised.get_meta("raised")
	var tiles: Dictionary = info["tiles"]
	var face_coords := {}
	for key in tiles:
		if String(key).begins_with("f"):
			face_coords[Vector2i(int(tiles[key][0]), int(tiles[key][1]))] = true
	var above := Vector2i(20, 13)
	assert_false(face_coords.has(raised.get_cell_atlas_coords(above)), "mid-wall: a top tile")
	for c in [Vector2i(20, 14), Vector2i(21, 14), Vector2i(20, 15), Vector2i(21, 15)]:
		assert_true(sim.terrain.smash(c), "smashed %s" % c)
	v.refresh()
	assert_eq(raised.get_cell_source_id(Vector2i(20, 14)), -1, "the smashed cell shows the floor")
	assert_true(face_coords.has(raised.get_cell_atlas_coords(above)), "the wall above the gap ends in a face")
	assert_true(shadow.get_cell_source_id(Vector2i(20, 14)) >= 0, "and shades the gap under it")
	var heap: Sprite2D = null
	for s in v._tiles.get_node("Rubble").get_children():
		if (s.get_meta("cells") as Rect2i).has_point(Vector2i(20, 14)):
			heap = s
	assert_true(heap != null and heap.visible, "the gap shows its rubble")
	for c in [Vector2i(20, 14), Vector2i(21, 14), Vector2i(20, 15), Vector2i(21, 15)]:
		sim.terrain.set_cell(c, TerrainGrid.WALL)
	v.refresh()
	assert_true(raised.get_cell_source_id(Vector2i(20, 14)) >= 0, "a rebuilt cell is raised again")
	assert_false(face_coords.has(raised.get_cell_atlas_coords(above)), "and the wall above is whole")
	assert_false(heap.visible, "its rubble gone")
	v.free()


func test_the_floodgate_shoulder_lies_on_floor_under_the_water() -> void:
	var root: Node = (load("res://assets/arenas/floodgate.tscn") as PackedScene).instantiate()
	var map := ArenaMap.get_map("floodgate")
	var size := ArenaMap.size_of(map)
	var grid := TerrainGrid.new(size.x, size.y)
	grid.load_map(map)
	var shoulder := root.get_node("Shoulder") as TileMapLayer
	var water := root.get_node("Water") as TileMapLayer
	assert_true(shoulder.get_index() < water.get_index(), "the shoulder under the water")
	var wet := {}
	for c in water.get_used_cells():
		wet[c] = true
	var ring := 0
	for t in shoulder.get_used_cells():
		assert_true(t.x >= 0 and t.y >= 0 and t.x * 2 < size.x and t.y * 2 < size.y, "inside the floor: %s" % t)
		if wet.has(t):
			continue
		ring += 1
		for dy in 2:
			for dx in 2:
				assert_eq(grid.get_base(t * 2 + Vector2i(dx, dy)), TerrainGrid.INTACT, "a shoulder tile on floor cells only: %s" % t)
	assert_true(ring >= 20, "a ring of dirt round every channel: %d tiles" % ring)
	for c in water.get_used_cells():
		for d in [Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + d
			if not wet.has(n):
				assert_true(shoulder.get_cell_source_id(n) >= 0, "dirt beside the water at %s" % n)
	root.free()


func test_scatter_is_stable_and_stays_off_water_walls_and_beds() -> void:
	for id in ["quarry", "floodgate", "twin_keeps", "greenhouse", "stadium"]:
		var map := ArenaMap.get_map(id)
		var tiles: Dictionary = map.get("tiles", {}).duplicate(true)
		var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles/%s_manifest.json" % String(tiles.get("set", "set1"))))
		var size := ArenaMap.size_of(map)
		var grid := TerrainGrid.new(size.x, size.y)
		grid.load_map(map)
		var wet := {}
		for r in tiles.get("water", []):
			for ty in range(int(r[1]), int(r[1]) + int(r[3])):
				for tx in range(int(r[0]), int(r[0]) + int(r[2])):
					wet[Vector2i(tx, ty)] = true
		var kinds: Dictionary = man.get("scatter", {}).get("kinds", {})
		if kinds.is_empty():
			# a set without scatter: borrow the rock set's to test the placement rules
			man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles/rock_manifest.json"))
			kinds = man["scatter"]["kinds"]
		if not tiles.has("scatter"):
			tiles["scatter"] = [{"kind": kinds.keys()[0], "where": "floor", "density": 0.5, "seed": 7}]
		var a := TileMapLayer.new()
		var b := TileMapLayer.new()
		BT._scatter(a, tiles, man, grid, wet, 2)
		BT._scatter(b, tiles, man, grid, wet, 2)
		var cells := a.get_used_cells()
		assert_true(cells.size() > 0, "%s: some scatter" % id)
		assert_eq(cells.size(), b.get_used_cells().size(), "%s: a rebuild lays as many" % id)
		for c in cells:
			assert_eq(a.get_cell_atlas_coords(c), b.get_cell_atlas_coords(c), "%s: the same sprite at %s" % [id, c])
			assert_eq(a.get_cell_alternative_tile(c), b.get_cell_alternative_tile(c), "%s: the same look at %s" % [id, c])
			assert_eq(grid.get_base(c), TerrainGrid.INTACT, "%s: on plain floor only: %s" % [id, c])
			assert_false(wet.has(c / 2), "%s: never on the water tiles: %s" % [id, c])
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n: Vector2i = c + Vector2i(dx, dy)
					if grid.in_bounds(n):
						assert_true(grid.get_base(n) != TerrainGrid.BRUSH, "%s: clear of the brush beds: %s" % [id, c])
			if bool(tiles.get("markings", false)):
				assert_false(BT.near_marks(c, grid), "%s: clear of the markings: %s" % [id, c])
		if map.get("tiles", {}).has("scatter"):
			assert_true(cells.size() < size.x * size.y / 8, "%s: subtle, most floor clean (%d sprites)" % [id, cells.size()])
		a.free()
		b.free()
	var stadium := ArenaMap.get_map("stadium")
	var sz := ArenaMap.size_of(stadium)
	var g := TerrainGrid.new(sz.x, sz.y)
	g.load_map(stadium)
	assert_true(BT.near_marks(Vector2i(sz.x / 2, sz.y / 2), g), "the centre circle is markings")
	assert_false(BT.near_marks(Vector2i(sz.x / 4, sz.y / 4 + 2), g), "open court is not")


func test_the_built_scenes_carry_their_scatter() -> void:
	for id in ["quarry", "floodgate", "twin_keeps"]:
		var root: Node = (load("res://assets/arenas/%s.tscn" % id) as PackedScene).instantiate()
		var layer := root.get_node_or_null("Scatter") as TileMapLayer
		assert_true(layer != null, "%s: a Scatter layer" % id)
		if layer != null:
			assert_true(layer.get_used_cells().size() >= 20, "%s: pebbles and plants (%d)" % [id, layer.get_used_cells().size()])
			assert_true(layer.tile_set.tile_size == Vector2i(16, 16), "%s: one tile a cell" % id)
		root.free()
