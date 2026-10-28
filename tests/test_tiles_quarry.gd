extends TestCase
## The Quarry Bowl on bought tiles (the "rock" set: Mountains scree and its tan cliff face, Set 1
## tan dirt and cobbles, Desert v2 packed earth, ledge and rock stacks): the cut has its fills,
## the lane blob and the earth blob9, the scene has ragged lanes and a rounded middle as
## terrains with a ledge along its south side, cobbled corners as patches, walls as raised rock
## shelves (RaisedTiles) with rubble, and the map plays as it did: ArenaView is tiled there, a smashed wall tile
## shows its rocks, a crack sets an overlay cell. The hand dressing (assets/arenas/quarry_dressing.tscn):
## props on the shelves' tops and at their faces' feet that fall with the shelf, flat things on
## the floor, a lamp on every flame.

const MANIFEST := "res://assets/tiles/rock_manifest.json"
const GROUND := "res://assets/tiles/rock_ground.tres"
const SCENE := "res://assets/arenas/quarry.tscn"


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _at(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


func _terrain_id(ts: TileSet, name: String) -> int:
	for i in ts.get_terrains_count(0):
		if ts.get_terrain_name(0, i) == name:
			return i
	return -1


func test_the_rock_cut_has_its_fills_terrains_and_overlay() -> void:
	var man := _manifest()
	assert_eq(man["set"], "rock")
	assert_eq(man["ground"]["fills"]["stone"].size(), 16, "a 4 x 4 stone fill")
	assert_eq(man["ground"]["fills"]["cobble"].size(), 4, "a 2 x 2 cobble fill")
	var terrains: Dictionary = man["ground"]["terrains"]
	var lane := {}
	for t in terrains["lane"]:
		lane[str(t["sides"].map(func(x): return int(x)))] = true
	assert_eq(lane.size(), 16, "the lane blob covers every side combination")
	assert_eq(terrains["patch"].size(), 9, "the middle patch is a blob9: corners, edges, middle")
	assert_eq(man["walls"]["rock"]["roles"]["rubble"].size(), 4, "rock heaps for smashed wall tiles")
	for k in ["ledge_l", "ledge_r"]:
		assert_true(man["decor"].has(k), "the middle's south ledge: %s" % k)
	assert_false(man["pieces"].has("boulder"), "no loose boulder tiles on the walls")
	assert_eq(int(man["overlay"]["ids"]["wall_top"]), ArenaView.OV_WALL_TOP, "the overlay ids are ArenaView's")
	var ts: TileSet = load(GROUND)
	assert_eq(ts.tile_size, Vector2i(32, 32))
	assert_eq(ts.get_terrains_count(0), 2, "the lane and the patch")
	assert_true(ResourceLoader.exists("res://assets/tiles/rock_overlay.tres"), "the overlay set exists")


func test_the_quarry_scene_has_lanes_a_raised_middle_and_rock_walls() -> void:
	var scene: PackedScene = load(SCENE)
	var root := scene.instantiate()
	var ground := root.get_node("Ground") as TileMapLayer
	assert_eq(ground.get_used_cells().size(), 42 * 18, "the fill: 42 x 18 tiles of floor, no ring")
	var man := _manifest()
	var fills: Dictionary = man["ground"]["fills"]
	var stone: Array = fills["stone"].map(_at)
	var cobble: Array = fills["cobble"].map(_at)
	assert_true(ground.get_cell_atlas_coords(Vector2i(20, 3)) in stone, "the open floor is sandstone")
	assert_true(ground.get_cell_atlas_coords(Vector2i(20, 8)) in stone, "scree under the middle patch: its ragged edge shows it")
	assert_eq(ground.get_cell_source_id(Vector2i(-1, 9)), -1, "no ring: the stands' hoardings sit past the floor")
	assert_true(ground.get_cell_atlas_coords(Vector2i(1, 1)) in cobble, "a cobbled corner")
	assert_true(ground.get_cell_atlas_coords(Vector2i(40, 16)) in cobble, "and the opposite one")
	assert_eq((root.get_node("Grass") as TileMapLayer).get_used_cells().size(), 0, "no grass in the quarry")
	var ts: TileSet = load(GROUND)
	var lane := root.get_node("Lane") as TileMapLayer
	assert_eq(lane.get_used_cells().size(), 2 * 2 * 18, "two lanes, two tiles wide, top to bottom")
	for c in [Vector2i(11, 9), Vector2i(12, 0), Vector2i(29, 17), Vector2i(30, 2)]:
		assert_eq(lane.get_cell_tile_data(c).terrain, _terrain_id(ts, "lane"), "a ragged lane at %s" % c)
	var patch := root.get_node("Patch") as TileMapLayer
	assert_eq(patch.get_used_cells().size(), 24, "the middle patch over the old rect [18, 7, 6, 4]")
	assert_eq(patch.get_cell_tile_data(Vector2i(20, 8)).terrain, _terrain_id(ts, "patch"), "the trampled middle")
	var corner: Array = man["ground"]["terrains"]["patch"].filter(func(t): return t["sides"].map(func(x): return int(x)) == [0, 1, 0, 1])
	assert_eq(patch.get_cell_atlas_coords(Vector2i(18, 7)), _at(corner[0]["at"]), "a rounded top-left corner")
	var decor := root.get_node("Decor")
	assert_eq(decor.get_child_count(), 2, "the ledge in two runs along the patch's south side")
	for s in decor.get_children():
		var sp := s as Sprite2D
		assert_true(sp.position.y > 10 * 32 and sp.position.y < 11 * 32, "%s overlaps the patch's bottom row" % sp.name)
	assert_eq((root.get_node("Pieces") as TileMapLayer).get_used_cells().size(), 0, "no boulder tiles: the walls are sprites")
	# the walls at cells [20, 5, 2, 26] and [62, 5, 2, 26] and four 4 x 2 outcrops: raised rock
	# shelves, a 16 px tile on every wall cell (RaisedTiles), the rubble per 32 px tile
	var raised := root.get_node("Raised") as TileMapLayer
	var wall_cells := {}
	for piece in ArenaMap.get_map("quarry")["pieces"]:
		if String(piece["kind"]) == "wall":
			var r: Array = piece["rect"]
			for cy in range(int(r[1]), int(r[1]) + int(r[3])):
				for cx in range(int(r[0]), int(r[0]) + int(r[2])):
					wall_cells[Vector2i(cx, cy)] = true
	assert_eq(raised.get_used_cells().size(), 2 * 2 * 26 + 4 * 4 * 2, "a raised tile on every wall cell")
	for c in raised.get_used_cells():
		assert_true(wall_cells.has(c), "only on the walls' own cells: %s" % c)
	assert_eq(root.get_node("Walls").get_children().map(func(n): return String(n.name)), ["Dressing"], "no stack sprites: the walls are tiles (the hand dressing only)")
	assert_eq(root.get_node("Rubble").get_child_count(), 28 + 4 * 2, "rubble for every wall tile, hidden")
	root.free()


func test_the_quarry_plays_as_before_and_breaks_over_the_tiles() -> void:
	var was: String = MatchFactory.arena
	MatchFactory.arena = "quarry"
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	assert_eq(sim.terrain.get_cell(Vector2i(20, 10)), TerrainGrid.WALL, "the left wall still stands in the sim")
	assert_eq(sim.terrain.get_cell(Vector2i(63, 30)), TerrainGrid.WALL, "and the right one")
	var v := ArenaView.new()
	v.ground = "stone"
	v.arena_id = "quarry"
	v.set_terrain(sim.terrain)
	assert_true(v.tiled(), "the Quarry draws from tiles")
	assert_eq(v.ground, "stone", "its ground stays stone (pit palette, dust)")
	assert_false(v._markings, "no court lines in a quarry")
	var raised := v._tiles.get_node("Raised") as TileMapLayer
	var heap: Sprite2D = null
	for s in v._tiles.get_node("Rubble").get_children():
		if (s.get_meta("cells") as Rect2i).has_point(Vector2i(20, 10)):
			heap = s
	assert_true(heap != null, "a heap over cell (20, 10)")
	assert_true(raised.get_cell_source_id(Vector2i(20, 10)) >= 0 and not heap.visible, "the wall stands")
	assert_true(sim.terrain.smash(Vector2i(20, 10)), "the wall's cell smashed")
	v.refresh()
	assert_true(heap.visible and raised.get_cell_source_id(Vector2i(20, 10)) == -1, "the smashed cell shows its rocks, not the shelf")
	sim.terrain.crack_cell(Vector2i(40, 18))
	v.refresh()
	var at := v._overlay.get_cell_atlas_coords(Vector2i(40, 18))
	assert_true((at.x + at.y * ArenaView.OV_COLS) in ArenaView.OV_CRACK, "a crack over the sandstone")
	v.free()


const DRESSING := "res://assets/arenas/quarry_dressing.tscn"
const FLAMES := ["brazier", "tripod", "lantern"]
const PPU := 2.0  ## scene px a unit (ArtScale.PX_PER_UNIT)


static func _kind(n: Node) -> String:
	return String(n.get_meta("kind", String(n.name).rsplit("_", true, 1)[0]))


## A prop's picture in units from the floor's corner: its feet at position, drawn at offset.
static func _picture(n: Node2D) -> Rect2:
	var size := Vector2.ZERO
	var off := Vector2.ZERO
	if n is Sprite2D:
		size = (n as Sprite2D).texture.get_size()
		off = (n as Sprite2D).offset
	elif n is AnimatedSprite2D:
		var an := n as AnimatedSprite2D
		size = an.sprite_frames.get_frame_texture(an.animation, 0).get_size()
		off = an.offset
	return Rect2((n.position + off) / PPU, size / PPU)


func _view() -> Array:
	var was: String = MatchFactory.arena
	MatchFactory.arena = "quarry"
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = "stone"
	v.arena_id = "quarry"
	v.set_terrain(sim.terrain)
	return [sim, v]


func test_the_quarry_is_dressed_on_its_shelves_and_flat_on_its_floor() -> void:
	var map := ArenaMap.get_map("quarry")
	assert_eq(String(map["tiles"].get("dressing", "")), DRESSING, "the map names its dressing scene")
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var d := root.get_node_or_null("Walls/Dressing") as Node2D
	assert_true(d != null and d.scene_file_path == DRESSING, "the built scene instances the hand-edited dressing")
	for flat in ["Paths", "Flat", "Detail"]:
		assert_eq((d.get_node(flat) as Node2D).position, Vector2.ZERO, "%s sorts at y 0, under the shelves" % flat)
	root.free()
	var size := ArenaMap.size_of(map)
	var grid := TerrainGrid.new(size.x, size.y)
	grid.load_map(map)
	var dr: Node = (load(DRESSING) as PackedScene).instantiate()
	var props := dr.get_node("Props")
	assert_true(props.get_child_count() >= 40, "dressed along every shelf (%d props)" % props.get_child_count())
	var kinds := {}
	for p: Node2D in props.get_children():
		kinds[_kind(p)] = true
		var foot := Vector2i(floori(p.position.x / (8 * PPU)), floori((p.position.y - 1.0) / (8 * PPU)))
		assert_eq(grid.get_base(foot), TerrainGrid.WALL, "%s stands on a shelf, not the floor (%s)" % [p.name, foot])
		var sh := p.get_node_or_null("Shadow") as Sprite2D
		assert_true(sh != null and sh.show_behind_parent, "%s has its contact shadow under it" % p.name)
	for k in ["crate", "sack", "millstones", "shovel", "chop_block", "logs", "fire_pit", "brazier", "tripod", "lantern"]:
		assert_true(kinds.has(k), "a %s among the props" % k)
	var paths := dr.get_node("Paths") as TileMapLayer
	assert_true(paths.get_used_cells().size() >= 20, "packed-earth patches (%d tiles)" % paths.get_used_cells().size())
	for t in paths.get_used_cells():
		for dy in 2:
			for dx in 2:
				assert_eq(grid.get_base(t * 2 + Vector2i(dx, dy)), TerrainGrid.INTACT, "an earth tile on plain floor: %s" % t)
	var detail := dr.get_node("Detail") as TileMapLayer
	assert_true(detail.get_used_cells().size() >= 120, "chips, ore, tufts, stones (%d)" % detail.get_used_cells().size())
	for c in detail.get_used_cells():
		assert_eq(grid.get_base(c), TerrainGrid.INTACT, "flat detail on plain floor: %s" % c)
	assert_true(dr.get_node("Flat").get_child_count() >= 8, "rubble spills and dropped planks")
	for f: Node2D in dr.get_node("Flat").get_children():
		var mid := Vector2i((_picture(f).get_center() / 8.0).floor())
		assert_eq(grid.get_base(mid), TerrainGrid.INTACT, "%s lies flat on the floor" % f.name)
	dr.free()


func test_every_flame_has_a_lamp_that_burns_by_day_and_smokes() -> void:
	var map := ArenaMap.get_map("quarry")
	var lights: Array = map.get("lights", [])
	assert_true(lights.size() <= Light2DView.MAX_DAY_LAMPS, "at most %d day lamps" % Light2DView.MAX_DAY_LAMPS)
	assert_true(Light2DView.lamps_by_day(map, "day") and Light2DView.lamps_by_day(map, "sunset"), "the lamps burn by day and at sunset")
	assert_true(bool(map["ambient"]["glades"]["smoke"]), "thin smoke off the flames (GladeView)")
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var flames: Array = root.get_node("Walls/Dressing/Props").get_children().filter(func(n): return _kind(n) in FLAMES)
	assert_true(flames.size() >= 8, "braziers, tripods and lantern posts (%d)" % flames.size())
	var origin := Vector2(SimDefs.GRID_X, SimDefs.GRID_Y)
	var used := {}
	for n: Node2D in flames:
		var pic := _picture(n).grow(4.0)
		pic.position += origin
		var lit := false
		for i in lights.size():
			var e: Dictionary = lights[i]
			if bool(e.get("lamp", false)) and float(e.get("day", 0.0)) > 0.0 and pic.has_point(Vector2(e["pos"][0], e["pos"][1])):
				lit = true
				used[i] = true
		assert_true(lit, "%s at %s has its lamp on its flame" % [n.name, n.position / PPU])
	assert_eq(used.size(), lights.size(), "and no lamp burns without a flame")
	root.free()


func test_a_prop_on_a_shelf_falls_when_the_face_would_grow_under_it() -> void:
	var r := _view()
	var sim: MatchSim = r[0]
	var v: ArenaView = r[1]
	var props := v._tiles.get_node(ArenaView.DRESS_PROPS)
	assert_eq(props.get_children().filter(func(n): return n.has_meta("cells")).size(), props.get_child_count(), "every prop knows the shelf it stands on")
	# the crate on the left shelf's top, cell (21, 10): a smash 3 cells below it would lift the
	# face to its feet, one 6 below leaves the top under it whole
	var crate: Node2D = props.get_children().filter(func(n): return _kind(n) == "crate" and Vector2i((n.position / 16.0).floor()) == Vector2i(21, 10))[0]
	assert_true(crate.visible, "the crate stands")
	assert_true(sim.terrain.smash(Vector2i(21, 16)), "a charge smashes the shelf six cells below")
	v.refresh()
	assert_true(crate.visible, "the top under the crate is still a top")
	sim.terrain.set_cell(Vector2i(21, 16), TerrainGrid.WALL)
	assert_true(sim.terrain.smash(Vector2i(21, 13)), "one three cells below")
	v.refresh()
	assert_false(crate.visible, "the face would rise under it: it goes")
	sim.terrain.set_cell(Vector2i(21, 13), TerrainGrid.WALL)
	v.refresh()
	assert_true(crate.visible, "and comes back when the shelf rebuilds")
	v.free()
