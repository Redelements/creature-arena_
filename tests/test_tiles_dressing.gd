extends TestCase
## Twin Keeps' hand dressing (assets/arenas/twin_keeps_dressing.tscn; assets/README.md
## "Dressing"): a scene of its own that the built ground scene instances under its y-sorted
## Walls, so a rebuild (tools/build_tiles.gd) keeps every hand edit. Props stand only on the
## map's walls and fences (they hide while the cell under them is smashed); the floor gets
## flat things only (worn paths, cobbles, moss, leaves, stones, flowers). Every flame in it has
## its lamp in the arena's `lights`, glowing by day and more at sunset on Lighting High.

const BT := preload("res://tools/build_tiles.gd")
const MAP := "twin_keeps"
const DRESSING := "res://assets/arenas/twin_keeps_dressing.tscn"
const GROUND := "res://assets/arenas/twin_keeps.tscn"
const FLAMES := ["torch", "brazier", "brazier_red", "brazier_cyan", "candelabra", "lantern"]
const PPU := 2.0  ## scene px a unit (ArtScale.PX_PER_UNIT)


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles/keeps_manifest.json"))


func _grid(map: Dictionary) -> TerrainGrid:
	var size := ArenaMap.size_of(map)
	var grid := TerrainGrid.new(size.x, size.y)
	grid.load_map(map)
	return grid


## A prop's kind: its meta (tools/seed_dressing.gd), else its name less the index.
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


func test_the_map_names_its_dressing_and_the_ground_scene_instances_it() -> void:
	var map := ArenaMap.get_map(MAP)
	assert_eq(String(map["tiles"].get("dressing", "")), DRESSING, "the map names its dressing scene")
	var root: Node = (load(GROUND) as PackedScene).instantiate()
	var d := root.get_node_or_null("Walls/Dressing") as Node2D
	assert_true(d != null, "the built scene carries the dressing in its wall run")
	assert_eq(d.scene_file_path, DRESSING, "as an instance of the hand-edited scene, not a copy")
	assert_true(d.y_sort_enabled and (d.get_node("Props") as Node2D).y_sort_enabled, "props sort among the wall sprites by their feet")
	for flat in ["Paths", "Flat", "Detail"]:
		assert_eq((d.get_node(flat) as Node2D).position, Vector2.ZERO, "%s sorts at y 0, under every wall sprite" % flat)
	assert_true(d.get_index() == root.get_node("Walls").get_child_count() - 1, "last in the run")
	root.free()


func test_a_rebuild_keeps_the_dressing_and_never_writes_it() -> void:
	var map := ArenaMap.get_map(MAP)
	var man := _manifest()
	var ts: TileSet = load("res://assets/tiles/keeps_ground.tres")
	var shore: TileSet = load("res://assets/tiles/keeps_shore.tres")
	var small: TileSet = load("res://assets/tiles/keeps_cells.tres")
	var before := FileAccess.get_md5(DRESSING)
	# a hand edit: a dressing scene of one crate, which a rebuild must carry as it is
	var edit := Node2D.new()
	edit.name = "Dressing"
	var props := Node2D.new()
	props.name = "Props"
	edit.add_child(props)
	props.owner = edit
	var crate := Sprite2D.new()
	crate.name = "crate_moved"
	crate.texture = load("res://assets/tiles/keeps_decor_crate.png")
	crate.position = Vector2(13, 175.5) * PPU + Vector2(3, 0)
	props.add_child(crate)
	crate.owner = edit
	var ps := PackedScene.new()
	ps.pack(edit)
	edit.free()
	var tmp := "user://test_dressing_edit.tscn"
	assert_eq(ResourceSaver.save(ps, tmp), OK, "the edited dressing saved")
	var tiles: Dictionary = map["tiles"].duplicate(true)
	tiles["dressing"] = tmp
	var root := BT.build_root(map, tiles, man, ts, shore, small)
	var built := PackedScene.new()
	built.pack(root)
	root.free()
	var again := built.instantiate()
	var moved := again.get_node_or_null("Walls/Dressing/Props/crate_moved") as Sprite2D
	assert_true(moved != null and moved.position == Vector2(13, 175.5) * PPU + Vector2(3, 0), "the hand-moved crate is where it was put")
	again.free()
	# the real one: rebuilt, still the same file, still all there
	root = BT.build_root(map, map["tiles"], man, ts, shore, small)
	var n := (root.get_node("Walls/Dressing/Props") as Node).get_child_count()
	root.free()
	var own: Node = (load(DRESSING) as PackedScene).instantiate()
	assert_eq(n, own.get_node("Props").get_child_count(), "every prop of the dressing in the rebuilt scene")
	own.free()
	assert_eq(FileAccess.get_md5(DRESSING), before, "the builder never writes the dressing scene")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


func test_props_stand_on_walls_and_fences_and_the_floor_gets_flat_things_only() -> void:
	var map := ArenaMap.get_map(MAP)
	var grid := _grid(map)
	var d: Node = (load(DRESSING) as PackedScene).instantiate()
	var props := d.get_node("Props")
	assert_true(props.get_child_count() >= 50, "dressed along the walls and gates (%d props)" % props.get_child_count())
	var kinds := {}
	for p: Node2D in props.get_children():
		kinds[_kind(p)] = true
		var foot := Vector2i(floori(p.position.x / (8 * PPU)), floori((p.position.y - 1.0) / (8 * PPU)))
		var v := grid.get_base(foot)
		assert_true(v == TerrainGrid.WALL or v == TerrainGrid.FENCE, "%s stands on a wall or fence cell, not the floor (%s)" % [p.name, foot])
		var sh := p.get_node_or_null("Shadow") as Sprite2D
		if sh != null:
			assert_true(sh.show_behind_parent, "%s: its contact shadow under it" % p.name)
	for k in ["barrel", "crate", "sack", "rack", "torch", "lantern", "ivy", "swag_red", "swag_blue"]:
		assert_true(kinds.has(k), "a %s among the props" % k)
	# the flat parts: paths, decals and detail never on a wall, fence, chasm or brush; paths and
	# decals off the water too (lily pads float on it)
	var paths := d.get_node("Paths") as TileMapLayer
	assert_true(paths.get_used_cells().size() >= 60, "worn paths from the gates (%d tiles)" % paths.get_used_cells().size())
	for t in paths.get_used_cells():
		for dy in 2:
			for dx in 2:
				assert_eq(grid.get_base(t * 2 + Vector2i(dx, dy)), TerrainGrid.INTACT, "a path tile on plain floor: %s" % t)
	var detail := d.get_node("Detail") as TileMapLayer
	var man := _manifest()
	var lily: Array = man["scatter"]["kinds"]["lily"].map(func(a): return Vector2i(int(a[0]), int(a[1])) * 2)
	assert_true(detail.get_used_cells().size() >= 150, "moss, leaves, stones and flowers (%d)" % detail.get_used_cells().size())
	for c in detail.get_used_cells():
		var v := grid.get_base(c)
		if detail.get_cell_atlas_coords(c) in lily:
			assert_eq(v, TerrainGrid.SHALLOWS, "a lily pad on the water: %s" % c)
		else:
			assert_eq(v, TerrainGrid.INTACT, "flat detail on plain floor: %s" % c)
	for f: Node2D in d.get_node("Flat").get_children():
		var mid := Vector2i((_picture(f).get_center() / 8.0).floor())
		assert_eq(grid.get_base(mid), TerrainGrid.INTACT, "%s lies flat on the floor" % f.name)
	d.free()


func test_every_flame_has_a_lamp_that_burns_by_day() -> void:
	var map := ArenaMap.get_map(MAP)
	var lights: Array = map.get("lights", [])
	assert_true(lights.size() <= Light2DView.MAX_LAMPS, "at most %d lamps" % Light2DView.MAX_LAMPS)
	assert_true(Light2DView.lamps_by_day(map, "day") and Light2DView.lamps_by_day(map, "sunset"), "the lamps burn by day and at sunset")
	assert_gt(Light2DView.day_glow("sunset"), Light2DView.day_glow("day"), "brighter as the light goes")
	var root: Node = (load(GROUND) as PackedScene).instantiate()
	var flames: Array = []
	for n in root.get_node("Walls/Dressing/Props").get_children() + root.get_node("Walls").get_children():
		if n is Node2D and _kind(n) in FLAMES:
			flames.append(n)
	assert_true(flames.size() >= 12, "torches, braziers, a lantern and a candelabra a keep (%d)" % flames.size())
	var origin := Vector2(SimDefs.GRID_X, SimDefs.GRID_Y)
	for n: Node2D in flames:
		var pic := _picture(n).grow(4.0)
		pic.position += origin
		var lit := false
		for e in lights:
			if bool(e.get("lamp", false)) and float(e.get("day", 0.0)) > 0.0 and pic.has_point(Vector2(e["pos"][0], e["pos"][1])):
				lit = true
		assert_true(lit, "%s at %s has its lamp on its flame" % [n.name, n.position / PPU])
	root.free()


func test_the_lamps_glow_on_the_floor_by_day_on_high_only() -> void:
	var sim := MatchSim.new()
	sim.set_arena(MAP)
	var lv := Light2DView.new()
	lv._ready()
	var glow := Light2DView.FloorGlow.new(Light2DView.LAMP_GLOW_MASK)
	lv.lamp_glow = glow
	var n: int = (sim.arena["lights"] as Array).size()
	lv.apply(sim, {"time": "day", "weather": "clear"}, Vector2(0.25, 1))
	assert_eq(lv.lamps.size(), n, "High by day: every lamp lit")
	assert_true(glow.visible, "glowing on the floor")
	var day := 0.0
	for l in lv.get_children():
		if l is PointLight2D and (l as PointLight2D).range_item_cull_mask == Light2DView.LAMP_GLOW_MASK:
			day += (l as PointLight2D).energy
	assert_true(day > 0.0, "with some strength")
	lv.apply(sim, {"time": "sunset", "weather": "clear"}, Vector2(0.25, 1))
	var dusk := 0.0
	for l in lv.get_children():
		if l is PointLight2D and not (l as PointLight2D).is_queued_for_deletion() 				and (l as PointLight2D).range_item_cull_mask == Light2DView.LAMP_GLOW_MASK:
			dusk += (l as PointLight2D).energy
	assert_gt(dusk, day, "brighter at sunset")
	lv.tier = Light2DView.Tier.LOW
	lv.apply(sim, {"time": "sunset", "weather": "clear"}, Vector2(0.25, 1))
	assert_eq(lv.lamps.size(), 0, "Low keeps the look as it was: no lamps")
	assert_false(glow.visible, "and no glow")
	glow.free()
	lv.free()


func test_a_prop_falls_with_the_wall_under_it() -> void:
	var was: String = MatchFactory.arena
	MatchFactory.arena = MAP
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = "grass"
	v.arena_id = MAP
	v.set_terrain(sim.terrain)
	var props := v._tiles.get_node(ArenaView.DRESS_PROPS)
	var on: Array = props.get_children().filter(func(n): return n.has_meta("cells"))
	assert_eq(on.size(), props.get_child_count(), "every prop stands on a blocking cell and knows it")
	var p: Node2D = on.filter(func(n): return _kind(n) == "rack")[0]
	var cell: Vector2i = (p.get_meta("cells") as Rect2i).position
	assert_true(p.visible, "the rack stands")
	assert_true(sim.terrain.smash(cell), "a charge smashes the wall under it")
	v.refresh()
	assert_false(p.visible, "the rack goes with the wall")
	sim.terrain.set_cell(cell, TerrainGrid.WALL)
	v.refresh()
	assert_true(p.visible, "and comes back when it rebuilds")
	v.free()
