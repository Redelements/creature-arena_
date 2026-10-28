extends TestCase
## The Floodgate's hand dressing (assets/arenas/floodgate_dressing.tscn; assets/README.md
## "Dressing"): floor only, since the map has no wall or fence cells for props to stand on.
## Moss, silt fans and trodden paths lie on plain floor, lily pads on the shallows, the rest
## of the detail and the drain grates on plain floor; the night keeps its lamps. Its life
## (GladeView, `ambient.glades`): bubbles rising in the shallows and a low mist over them at
## sunset and night, both gone with Lighting Off.

const BT := preload("res://tools/build_tiles.gd")
const MAP := "floodgate"
const DRESSING := "res://assets/arenas/floodgate_dressing.tscn"
const GROUND := "res://assets/arenas/floodgate.tscn"
const PPU := 2.0  ## scene px a unit (ArtScale.PX_PER_UNIT)


func _grid(map: Dictionary) -> TerrainGrid:
	var size := ArenaMap.size_of(map)
	var grid := TerrainGrid.new(size.x, size.y)
	grid.load_map(map)
	return grid


func test_the_map_names_its_dressing_and_the_ground_scene_instances_it() -> void:
	var map := ArenaMap.get_map(MAP)
	assert_eq(String(map["tiles"].get("dressing", "")), DRESSING, "the map names its dressing scene")
	var root: Node = (load(GROUND) as PackedScene).instantiate()
	var d := root.get_node_or_null("Walls/Dressing") as Node2D
	assert_true(d != null, "the built scene carries the dressing in its wall run")
	assert_eq(d.scene_file_path, DRESSING, "as an instance of the hand-edited scene, not a copy")
	for flat in ["Moss", "Silt", "Paths", "Flat", "Detail"]:
		assert_eq((d.get_node(flat) as Node2D).position, Vector2.ZERO, "%s sorts at y 0, under every wall sprite" % flat)
	assert_true(d.get_index() == root.get_node("Walls").get_child_count() - 1, "last in the run")
	root.free()


func test_a_rebuild_never_writes_the_dressing() -> void:
	var map := ArenaMap.get_map(MAP)
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles/wetland_manifest.json"))
	var before := FileAccess.get_md5(DRESSING)
	var root := BT.build_root(map, map["tiles"], man, load("res://assets/tiles/wetland_ground.tres"),
		load("res://assets/tiles/wetland_shore.tres"), load("res://assets/tiles/wetland_cells.tres"))
	assert_true(root.has_node("Walls/Dressing"), "the rebuilt scene instances it")
	root.free()
	assert_eq(FileAccess.get_md5(DRESSING), before, "the builder never writes the dressing scene")


func test_floor_only_and_everything_lies_flat_where_it_belongs() -> void:
	var map := ArenaMap.get_map(MAP)
	var grid := _grid(map)
	for c in grid.cols * grid.rows:
		var v := grid.get_base(Vector2i(c % grid.cols, c / grid.cols))
		assert_true(v != TerrainGrid.WALL and v != TerrainGrid.FENCE, "no wall or fence on this map: nothing for a prop to stand on")
	var d: Node = (load(DRESSING) as PackedScene).instantiate()
	assert_eq(d.get_node("Props").get_child_count(), 0, "so no props on the floor")
	var counts := {"Moss": 20, "Silt": 8, "Paths": 40}
	for name: String in counts:
		var layer := d.get_node(name) as TileMapLayer
		var used := layer.get_used_cells()
		assert_true(used.size() >= int(counts[name]), "%s laid (%d tiles)" % [name, used.size()])
		for t in used:
			for dy in 2:
				for dx in 2:
					assert_eq(grid.get_base(t * 2 + Vector2i(dx, dy)), TerrainGrid.INTACT, "%s on plain floor: %s" % [name, t])
	var detail := d.get_node("Detail") as TileMapLayer
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles/wetland_manifest.json"))
	var kinds: Dictionary = man["scatter"]["kinds"]
	var lily: Array = kinds["lily"].map(func(a): return Vector2i(int(a[0]), int(a[1])) * 2)
	var puddle: Array = kinds["puddle"].map(func(a): return Vector2i(int(a[0]), int(a[1])) * 2)
	assert_true(detail.get_used_cells().size() >= 150, "moss, puddles, silt, grit, leaves and lily pads (%d)" % detail.get_used_cells().size())
	var pads := 0
	var puddles := 0
	for c in detail.get_used_cells():
		var at := detail.get_cell_atlas_coords(c)
		if at in lily:
			pads += 1
			assert_eq(grid.get_base(c), TerrainGrid.SHALLOWS, "a lily pad on the water: %s" % c)
		else:
			puddles += 1 if at in puddle else 0
			assert_eq(grid.get_base(c), TerrainGrid.INTACT, "flat detail on plain floor: %s" % c)
	assert_true(pads >= 6 and puddles >= 12, "lily pads in the shallows (%d), puddles on the paving (%d)" % [pads, puddles])
	var flat := d.get_node("Flat")
	assert_true(flat.get_child_count() >= 6, "drain grates (%d)" % flat.get_child_count())
	for f: Sprite2D in flat.get_children():
		var rect := Rect2((f.position + f.offset) / PPU, f.texture.get_size() / PPU)
		for corner in [rect.position, rect.end - Vector2(0.01, 0.01)]:
			assert_eq(grid.get_base(Vector2i((corner / 8.0).floor())), TerrainGrid.INTACT, "%s lies on plain floor" % f.name)
	d.free()


func test_the_night_keeps_its_lamps() -> void:
	var map := ArenaMap.get_map(MAP)
	assert_true("night" in map.get("times", []), "the only map with a night")
	var lights: Array = map.get("lights", [])
	assert_true(lights.size() >= 7 and lights.size() <= Light2DView.MAX_LAMPS, "its lamps, within the cap (%d)" % lights.size())


func _glade() -> Array:
	var was: String = MatchFactory.arena
	MatchFactory.arena = MAP
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var g := GladeView.new()
	g.set_sim(sim, [])
	for c in sim.creatures:
		c.pos = Vector2(-900, -900)  # out of the way: nothing shies away
	return [sim, g]


func test_bubbles_rise_in_the_shallows_and_go_with_lighting_off() -> void:
	var r := _glade()
	var sim: MatchSim = r[0]
	var g: GladeView = r[1]
	assert_true(g.visible, "the map's glades block turns the view on")
	g.set_look("day", Light2DView.Tier.LOW)
	var seen := 0
	for i in 600:
		g.advance()
		seen = maxi(seen, g.bubble_count())
		for b in g._bubbles:
			var p: Vector2 = b["p"]
			var c := Vector2i(floori((p.x - SimDefs.GRID_X) / SimDefs.CELL), floori((p.y - SimDefs.GRID_Y) / SimDefs.CELL))
			assert_eq(sim.terrain.map_base[c.y * sim.terrain.cols + c.x], TerrainGrid.SHALLOWS, "a bubble in the shallows: %s" % c)
	assert_true(seen > 0 and seen <= GladeView.BUBBLE_CAP, "bubbles come and go (at most %d at once: %d)" % [GladeView.BUBBLE_CAP, seen])
	g.set_look("day", Light2DView.Tier.OFF)
	for i in 120:
		g.advance()
	assert_eq(g.bubble_count(), 0, "none with Lighting Off")
	r[1].free()


func test_low_mist_lies_over_the_water_at_sunset_and_night_only() -> void:
	var r := _glade()
	var g: GladeView = r[1]
	g.set_look("day", Light2DView.Tier.HIGH)
	assert_eq(g.mist_count(), 0, "none by day")
	g.set_look("night", Light2DView.Tier.HIGH)
	assert_gt(g.mist_count(), 8, "a low mist over the channel at night")
	g.set_look("sunset", Light2DView.Tier.LOW)
	assert_gt(g.mist_count(), 0, "and at sunset, still on Low")
	g.set_look("night", Light2DView.Tier.OFF)
	assert_eq(g.mist_count(), 0, "none with Lighting Off")
	r[1].free()
