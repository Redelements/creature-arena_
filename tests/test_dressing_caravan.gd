extends TestCase
## Dustwind Pass's hand dressing (assets/arenas/caravan_pass_dressing.tscn; assets/README.md
## "Dressing"), the Caravan map: its walls are one-tile raised plateaus and two fences, so the
## props stand on the plateau tops and along the fences and the floor carries the rest (trodden
## paths, ruts, wind streaks, gravel, dry grass, stones, slabs, blooms), never on the road the
## caravan rides or near its track. Palm crowns hang over the brush beds; every flame has a lamp.

const BT := preload("res://tools/build_tiles.gd")
const MAP := "caravan_pass"
const DRESSING := "res://assets/arenas/caravan_pass_dressing.tscn"
const GROUND := "res://assets/arenas/caravan_pass.tscn"
const FLAMES := ["brazier", "tripod", "torch"]
const PPU := 2.0  ## scene px a unit (ArtScale.PX_PER_UNIT)


func _grid(map: Dictionary) -> TerrainGrid:
	var size := ArenaMap.size_of(map)
	var grid := TerrainGrid.new(size.x, size.y)
	grid.load_map(map)
	return grid


static func _kind(n: Node) -> String:
	return String(n.get_meta("kind", String(n.name).rsplit("_", true, 1)[0]))


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


## The road's cells (the tiles block's earth rects) and the cells by the caravan's track.
func _road(map: Dictionary, grid: TerrainGrid) -> Dictionary:
	var out := {}
	for r in map["tiles"]["earth"]:
		for cy in range(int(r[1]) * 2, (int(r[1]) + int(r[3])) * 2):
			for cx in range(int(r[0]) * 2, (int(r[0]) + int(r[2])) * 2):
				out[Vector2i(cx, cy)] = true
	for cy in grid.rows:
		for cx in grid.cols:
			if BT.near_track(grid.cell_center(Vector2i(cx, cy)), map["track"]):
				out[Vector2i(cx, cy)] = true
	return out


func test_the_ground_scene_instances_the_dressing() -> void:
	var map := ArenaMap.get_map(MAP)
	assert_eq(String(map["tiles"].get("dressing", "")), DRESSING, "the map names its dressing scene")
	var root: Node = (load(GROUND) as PackedScene).instantiate()
	var d := root.get_node_or_null("Walls/Dressing") as Node2D
	assert_true(d != null and d.scene_file_path == DRESSING, "instanced, not copied")
	for flat in ["Paths", "Flat", "Detail"]:
		assert_eq((d.get_node(flat) as Node2D).position, Vector2.ZERO, "%s sorts at y 0" % flat)
	root.free()


func test_props_on_walls_and_fences_flat_things_off_the_road() -> void:
	var map := ArenaMap.get_map(MAP)
	var grid := _grid(map)
	var road := _road(map, grid)
	var d: Node = (load(DRESSING) as PackedScene).instantiate()
	var props := d.get_node("Props")
	assert_true(props.get_child_count() >= 20, "the plateau tops and the fences dressed (%d props)" % props.get_child_count())
	var kinds := {}
	for p: Node2D in props.get_children():
		kinds[_kind(p)] = true
		var foot := Vector2i(floori(p.position.x / (8 * PPU)), floori((p.position.y - 1.0) / (8 * PPU)))
		var v := grid.get_base(foot)
		assert_true(v == TerrainGrid.WALL or v == TerrainGrid.FENCE, "%s stands on a wall or fence cell (%s)" % [p.name, foot])
	for k in ["jars", "sacks", "hay", "crate", "cloths", "baskets", "grain", "awning_red", "awning_grey", "tripod", "torch"]:
		assert_true(kinds.has(k), "a %s among the props" % k)
	var ground := 0
	for layer in d.get_children():
		if layer is TileMapLayer and layer.name != "Detail":
			for t in (layer as TileMapLayer).get_used_cells():
				ground += 1
				for dy in 2:
					for dx in 2:
						var c: Vector2i = t * 2 + Vector2i(dx, dy)
						assert_eq(grid.get_base(c), TerrainGrid.INTACT, "%s tile on plain floor: %s" % [layer.name, t])
						assert_false(road.has(c), "%s tile off the road and the track: %s" % [layer.name, t])
	assert_true(ground >= 300, "paths, streaks, gravel and dry grass (%d tiles)" % ground)
	var detail := d.get_node("Detail") as TileMapLayer
	assert_true(detail.get_used_cells().size() >= 80, "stones, blooms, pebbles, tufts (%d)" % detail.get_used_cells().size())
	for c in detail.get_used_cells():
		assert_eq(grid.get_base(c), TerrainGrid.INTACT, "detail on plain floor: %s" % c)
		assert_false(road.has(c), "detail off the road: %s" % c)
	for f: Node2D in d.get_node("Flat").get_children():
		var mid := Vector2i((_picture(f).get_center() / 8.0).floor())
		assert_eq(grid.get_base(mid), TerrainGrid.INTACT, "%s lies flat on the floor" % f.name)
		assert_false(road.has(mid), "%s off the road" % f.name)
	d.free()


func test_every_flame_has_a_lamp_that_burns_by_day() -> void:
	var map := ArenaMap.get_map(MAP)
	var lights: Array = map.get("lights", [])
	assert_true(lights.size() <= Light2DView.MAX_DAY_LAMPS, "at most %d day lamps" % Light2DView.MAX_DAY_LAMPS)
	assert_true(Light2DView.lamps_by_day(map, "day") and Light2DView.lamps_by_day(map, "sunset"), "the lamps burn by day and at sunset")
	var root: Node = (load(GROUND) as PackedScene).instantiate()
	var flames: Array = []
	for n in root.get_node("Walls/Dressing/Props").get_children() + root.get_node("Walls").get_children() + root.get_node("Anim").get_children():
		if n is Node2D and _kind(n) in FLAMES:
			flames.append(n)
	assert_true(flames.size() >= 12, "braziers, tripods and torches (%d)" % flames.size())
	var origin := Vector2(SimDefs.GRID_X, SimDefs.GRID_Y)
	for n: Node2D in flames:
		var pic := _picture(n).grow(4.0)
		pic.position += origin
		var lit := false
		for e in lights:
			if bool(e.get("lamp", false)) and float(e.get("day", 0.0)) > 0.0 and pic.has_point(Vector2(e["pos"][0], e["pos"][1])):
				lit = true
		assert_true(lit, "%s at %s has its lamp on its flame" % [n.name, pic])
	root.free()


func test_palm_crowns_hang_over_the_beds_and_fade_over_our_own() -> void:
	var was: String = MatchFactory.arena
	MatchFactory.arena = MAP
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = "dirt"
	v.arena_id = MAP
	v.set_terrain(sim.terrain)
	assert_eq(v.canopy_count(), 8, "two crowns over each of the four brush beds")
	var props := v._tiles.get_node(ArenaView.DRESS_PROPS)
	var on: Array = props.get_children().filter(func(n): return n.has_meta("cells"))
	assert_eq(on.size(), props.get_child_count(), "every prop stands on a blocking cell and knows it")
	# a prop on a plateau's top goes when the face below it is smashed (the face regrows there)
	var top: Node2D = on.filter(func(n): return _kind(n) == "baskets")[0]
	var cells: Rect2i = top.get_meta("cells")
	assert_true(cells.size.y > 1, "its cells run on down its column")
	var face := Vector2i(cells.position.x, cells.end.y - 1)
	assert_true(sim.terrain.smash(face), "a charge smashes the face")
	v.refresh()
	assert_false(top.visible, "the goods go with it")
	v.free()
