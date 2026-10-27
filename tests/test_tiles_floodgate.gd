extends TestCase
## The Floodgate on tiles (the "wetland" set: Wetland paving, Set 1 water under its three
## shallows channels with the translucent animated surface over it, a stone bank, reeds in
## the margins): the cut's water terrain covers every side combination, the scene's Water
## and WaterSurface layers cover every shallows cell's tile and nothing else, the map plays
## as it did (pieces untouched), ArenaView draws from the tiles, and WaterView still finds
## the shallows. Every channel has a bank (the WaterBank layer, keyed by its eight
## neighbours), and the reeds stand with their feet on the floor's edges, never on the wall.
## The art pass: the channels sit below the floor behind a kerb of Wetland cobbles (the
## far bank a drop of Wetland stone), rounded, in a ragged shoulder of Wetland dirt, Wetland's glints lie
## over the water on a second surface layer in out-of-step variant rows, and swaying
## DecorativeProps reeds stand off the floor (the lower mouth, the side rails), none on top.

const MANIFEST := "res://assets/tiles/wetland_manifest.json"
const GROUND := "res://assets/tiles/wetland_ground.tres"
const SCENE := "res://assets/arenas/floodgate.tscn"


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _on() -> Array:
	var was: String = MatchFactory.arena
	MatchFactory.arena = "floodgate"
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = String(sim.arena.get("ground", "dirt"))
	v.arena_id = "floodgate"
	v.set_terrain(sim.terrain)
	return [sim, v]


## The tiles the map's shallows pieces cover (2 x 2 cells a tile, rounded out).
static func _shallows_tiles() -> Dictionary:
	var want := {}
	for piece in ArenaMap.get_map("floodgate").get("pieces", []):
		if String(piece.get("kind", "")) != "shallows":
			continue
		var r: Array = piece["rect"]
		for ty in range(floori(float(r[1]) / 2), ceili(float(int(r[1]) + int(r[3])) / 2)):
			for tx in range(floori(float(r[0]) / 2), ceili(float(int(r[0]) + int(r[2])) / 2)):
				want[Vector2i(tx, ty)] = true
	return want


func test_the_wetland_cut_has_the_water_terrain_and_its_surface() -> void:
	var man := _manifest()
	var block := {}
	for t in man["ground"]["terrains"]["water"]:
		if float(t["prob"]) >= 1.0:
			block[str(t["sides"])] = true
	assert_eq(block.size(), 16, "the water blob covers all 16 side combinations")
	assert_eq(man["ground"]["fills"]["paving"].size(), 4, "a 2 x 2 paving fill")
	assert_eq(man["ground"]["fills"]["water"].size(), 4, "a flat 2 x 2 water fill from the bed's interior")
	var surf: Dictionary = man["ground"]["surfaces"]["water"]
	assert_eq(int(surf["frames"]), 16, "Set 1's 16-frame water surface")
	assert_eq(String(surf["over"]), "water", "laid over the water terrain")
	var tex: Texture2D = load("res://assets/tiles/" + String(surf["source"]))
	assert_eq(tex.get_size(), Vector2(512, 32), "a strip of 16 frames of 32 px")
	var img := tex.get_image()
	var seen_alpha := {}
	for x in range(0, 512, 3):
		for y in range(0, 32, 3):
			seen_alpha[int(img.get_pixel(x, y).a * 255.0)] = true
	assert_true(seen_alpha.has(0) and seen_alpha.size() >= 2, "the surface keeps its translucency: %s" % [seen_alpha.keys()])
	for a in seen_alpha:
		assert_true(a == 0 or a < 200, "and is never opaque (alpha %d)" % a)
	var ts: TileSet = load(GROUND)
	assert_true(ts.has_source(2) and ts.has_source(3), "two surface sources after the ground and the pieces")
	var src := ts.get_source(2) as TileSetAtlasSource
	assert_eq(src.get_tile_animation_frames_count(Vector2i.ZERO), 16, "the tile animates through the 16 frames")


func test_the_glints_lie_over_the_water_out_of_step() -> void:
	var man := _manifest()
	var glint: Dictionary = man["ground"]["surfaces"]["glint"]
	assert_eq(String(glint["over"]), "water", "the glints lie over the water")
	assert_eq(int(glint["frames"]), 10, "Wetland water_effB's 10 frames")
	assert_eq(int(glint["variants"]), 4, "in four phase-shifted, mirrored rows")
	var tex: Texture2D = load("res://assets/tiles/" + String(glint["source"]))
	assert_eq(tex.get_size(), Vector2(320, 128), "10 frames of 32 px by 4 rows")
	var img := tex.get_image()
	var lit := 0
	for x in 320:
		for y in 128:
			lit += int(img.get_pixel(x, y).a > 0.0)
	assert_true(lit > 0 and lit < 320 * 128 / 20, "sparse glints, the water shows through: %d px" % lit)
	var ts: TileSet = load(GROUND)
	var src := ts.get_source(3) as TileSetAtlasSource
	for row in 4:
		assert_eq(src.get_tile_animation_frames_count(Vector2i(0, row)), 10, "variant row %d animates" % row)
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var layer := root.get_node_or_null("WaterSurfaceGlint") as TileMapLayer
	assert_true(layer != null, "a WaterSurfaceGlint layer")
	if layer != null:
		var want := _shallows_tiles()
		assert_eq(layer.get_used_cells().size(), want.size(), "glints on every channel tile")
		var rows := {}
		for c in layer.get_used_cells():
			assert_true(want.has(c), "glints only on the water: %s" % c)
			rows[layer.get_cell_atlas_coords(c).y] = true
		assert_true(rows.size() >= 3, "the tiles pick different variant rows: %s" % [rows.keys()])
		assert_true(layer.get_index() > root.get_node("WaterSurface").get_index(), "over the Set 1 surface")
		assert_true(layer.get_index() < root.get_node("WaterBank").get_index(), "under the bank")
	root.free()


func test_the_bank_drops_below_a_kerb_and_a_dirt_shoulder() -> void:
	var f := FileAccess.open("res://tools/tile_recipes/wetland.json", FileAccess.READ)
	var recipe: Dictionary = JSON.parse_string(f.get_as_text())
	var bank: Dictionary = recipe["ground"]["shores"]["water"]
	assert_eq(String(bank["face"]["src"]), "RPGW_Wetland_v1.1/_PNG/MainLev.png", "the far bank's face from the Wetland plateau")
	assert_true(int(bank["face_px"]) >= 12, "a face deep enough to read as a drop")
	assert_eq(Vector2i(int(bank["land"]["block"][0]), int(bank["land"]["block"][1])), Vector2i(21, 30), "the bank's top is Wetland's brown dirt")
	assert_eq(Vector2i(int(bank["edge"]["block"][0]), int(bank["edge"]["block"][1])), Vector2i(36, 23), "a kerb of the path border's cobbles at the water")
	assert_true(bool(bank.get("edge_over_face", false)), "the kerb runs along the top of the far bank's drop too")
	assert_true(int(bank["radius"]) >= 10, "the water's corners rounded")
	# the shoulder: a ragged band of dirt on the land tiles round the water, never more than
	# about half a tile wide
	var man := _manifest()
	var sh: Dictionary = man["ground"]["shores"]["water"].get("shoulder", {})
	assert_true(sh.size() >= 8, "a shoulder tile per water-neighbour mask (%d)" % sh.size())
	var img := (load("res://assets/tiles/" + String(man["ground"]["shores"]["water"]["source"])) as Texture2D).get_image()
	for key in ["00001000", "00000100", "00000001"]:  # water below, above, left
		var at: Array = sh[key]
		var widths := {}
		for i in 32:
			var n := 0
			for d in 32:
				var px := Vector2i(int(at[0]) * 32, int(at[1]) * 32)
				px += Vector2i(i, 31 - d) if key == "00001000" else (Vector2i(i, d) if key == "00000100" else Vector2i(d, i))
				if img.get_pixelv(px).a > 0.5:
					n = d + 1
			widths[n] = true
			assert_true(n <= 17, "%s: the band at most about half a tile (%d px)" % [key, n])
		assert_true(widths.size() >= 4, "%s: a ragged edge, not a straight one (%s)" % [key, widths.keys()])


func test_swaying_reeds_stand_off_the_floor() -> void:
	var man := _manifest()
	for kind in ["reeds_sway", "reed_sway"]:
		var a: Dictionary = man["anim"][kind]
		assert_eq(Vector2i(int(a["frame"][0]), int(a["frame"][1])), Vector2i(32, 32), "%s: 32 px frames" % kind)
		assert_eq(int(a["frames"]), 4, "%s: four frames" % kind)
		var tex: Texture2D = load("res://assets/tiles/" + String(a["source"]))
		assert_eq(tex.get_size(), Vector2(128, 32), "%s: a strip of four" % kind)
		var img := tex.get_image()
		var feet := Vector2i(int(a["feet"][0]), int(a["feet"][1]))
		var rooted := false
		for dx in range(-3, 4):
			rooted = rooted or img.get_pixel(feet.x + dx, feet.y).a > 0.5
		assert_true(rooted, "%s: its feet on its roots, not floating" % kind)
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var anim := root.get_node("Anim")
	assert_eq(anim.get_child_count(), 9, "reeds beside the lower mouth and along the side rails")
	var floor_px := Rect2(Vector2.ZERO, Vector2(84 * 16, 36 * 16))
	for s in anim.get_children():
		var kind := String(s.name).rsplit("_", true, 1)[0]
		var feet: Vector2 = s.position + Vector2(man["anim"][kind]["feet"][0], man["anim"][kind]["feet"][1])
		assert_false(floor_px.has_point(feet), "%s stands off the floor: %s" % [s.name, feet])
		assert_true(feet.y > 0.0, "%s: nothing new in the top margin" % s.name)
	root.free()


func test_the_scene_puts_water_under_every_channel_tile() -> void:
	var scene: PackedScene = load(SCENE)
	var root := scene.instantiate()
	var want := _shallows_tiles()
	assert_eq(want.size(), 56, "three channels: 4 tiles wide, 4 + 6 + 4 tall")
	var water := root.get_node("Water") as TileMapLayer
	var surface := root.get_node("WaterSurface") as TileMapLayer
	assert_eq(water.get_used_cells().size(), want.size(), "water on every channel tile")
	assert_eq(surface.get_used_cells().size(), want.size(), "and the surface over each")
	for c in water.get_used_cells():
		assert_true(want.has(c), "water only where the shallows are: %s" % c)
		assert_eq(water.get_cell_tile_data(c).terrain, 0, "autotiled water at %s" % c)
	var ground := root.get_node("Ground") as TileMapLayer
	assert_eq(ground.get_used_cells().size(), 42 * 18, "the paving, no ring")
	assert_eq((root.get_node("Pieces") as TileMapLayer).get_used_cells().size(), 0, "no pieces: the Floodgate has none")
	assert_eq(root.get_node("Decor").get_child_count(), 4, "reeds at the channel's mouths")
	var man := _manifest()
	for d in root.get_node("Decor").get_children():
		var s := d as Sprite2D
		var kind := String(s.name).rsplit("_", true, 1)[0]
		var feet := s.position + Vector2(man["decor"][kind]["feet"][0], man["decor"][kind]["feet"][1])
		var floor_px := Rect2(Vector2.ZERO, Vector2(84 * 16, 36 * 16))
		assert_false(floor_px.grow(-12).has_point(feet), "decor stands in the margins, not on the floor: %s" % feet)
		if feet.y < floor_px.size.y * 0.5:
			assert_eq(feet.y, 0.0, "%s at the top stands on the floor's top edge, not up the wall" % s.name)
	var problems := bank_problems(root, man)
	assert_true(problems.is_empty(), "every channel has its bank: %s" % [problems])
	root.free()


## The WaterBank layer over `water`: a bank tile on every water tile with land on a side or
## (both its sides water) a corner, keyed by those neighbours, and none on open water.
static func bank_problems(root: Node, man: Dictionary) -> Array:
	var water := root.get_node("Water") as TileMapLayer
	var bank := root.get_node_or_null("WaterBank") as TileMapLayer
	if bank == null:
		return ["no WaterBank layer"]
	var keys: Dictionary = man["ground"]["shores"]["water"]["tiles"]
	var wet := {}
	for c in water.get_used_cells():
		wet[c] = true
	var out := []
	var banked := 0
	for c in wet:
		var key := _key(c, wet)
		if key == "00000000":
			if bank.get_cell_source_id(c) != -1:
				out.append("a bank on open water at %s" % c)
			continue
		banked += 1
		var want: Array = keys.get(key, [])
		if want.is_empty() or bank.get_cell_atlas_coords(c) != Vector2i(int(want[0]), int(want[1])):
			out.append("tile %s: bank %s, want the %s tile %s" % [c, bank.get_cell_atlas_coords(c), key, want])
	for c in bank.get_used_cells():
		if not wet.has(c):
			out.append("a bank off the water at %s" % c)
	if banked == 0:
		out.append("no water tile has a bank")
	return out


static func _key(c: Vector2i, wet: Dictionary) -> String:
	var land := func(dx: int, dy: int) -> int:
		return 0 if wet.has(c + Vector2i(dx, dy)) else 1
	var l: int = land.call(-1, 0)
	var r: int = land.call(1, 0)
	var t: int = land.call(0, -1)
	var b: int = land.call(0, 1)
	var m := l | r << 1 | t << 2 | b << 3
	for k in 4:
		var d: Vector2i = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)][k]
		var s1: int = t if d.y < 0 else b
		var s2: int = l if d.x < 0 else r
		if land.call(d.x, d.y) == 1 and s1 == 0 and s2 == 0:
			m |= 1 << (4 + k)
	return String.num_int64(m, 2).lpad(8, "0")


func test_the_floodgate_plays_as_before_and_draws_from_tiles() -> void:
	var pair := _on()
	var sim: MatchSim = pair[0]
	var v: ArenaView = pair[1]
	assert_true(v.tiled(), "the Floodgate draws from tiles")
	assert_false(v._markings, "no court lines on the Floodgate")
	var shallows := 0
	for c in sim.terrain.cells:
		if c == TerrainGrid.SHALLOWS:
			shallows += 1
	assert_eq(shallows, 8 * 8 + 8 * 12 + 8 * 8, "the three channels' cells, untouched")
	assert_eq(sim.terrain.get_cell(Vector2i(41, 10)), TerrainGrid.INTACT, "the bridge between the channels is floor")
	assert_eq(v._overlay.get_used_cells().size(), 0, "nothing broken yet")
	sim.terrain.crack_cell(Vector2i(20, 20))
	v.refresh()
	assert_eq(v._overlay.get_cell_source_id(Vector2i(20, 20)), 0, "a crack sets an overlay cell")
	var water := WaterView.new()
	water.set_sim(sim)
	var found := 0
	for w in water._water:
		found += int(w)
	assert_eq(found, shallows, "WaterView still finds every shallows cell")
	water.free()
	v.free()
