extends TestCase
## Twin Keeps on tiles: the Capture the Flag map keeps its 150 x 64 cells (75 x 32 tiles)
## and every piece, drawn from the "keeps" set: castle tiles on each wall, fences on the
## fences, water under every shallows cell and under the bridge (so a fallen bridge shows
## it), a cobble causeway on the bridge, trees along the top margin, the waterfall where the
## river enters at the top and torches on the gate towers. Every water tile at the river's
## edge (the island, the head, the bridge's ends) carries its bank. ArenaView treats it as tiled.

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
	assert_eq(ground.get_used_cells().size(), 77 * 34, "75 x 32 tiles of floor and a tile round it")
	var castle: Array = _coords(man["pieces"]["castle_h"]) + _coords(man["pieces"]["castle_v"])
	var fence: Array = _coords(man["pieces"]["fence_h"]) + _coords(man["pieces"]["fence_v"])
	var bridge: Array = _coords(man["pieces"]["bridge"]) + _coords(man["pieces"].get("bridge_t", [])) + _coords(man["pieces"].get("bridge_b", []))
	for piece in map["pieces"]:
		var kind := String(piece["kind"])
		for c in _tiles_of(piece["rect"]):
			match kind:
				"wall":
					assert_true(pieces.get_cell_atlas_coords(c) in castle, "%s: a castle tile on the wall" % c)
				"fence":
					assert_true(pieces.get_cell_atlas_coords(c) in fence, "%s: a fence tile" % c)
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


func test_the_trees_the_waterfall_and_the_torches_stand_where_the_map_says() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var decor := root.get_node("Decor")
	var anim := root.get_node("Anim")
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
	# feet [112, 150] at tile (37, 1)'s bottom middle: x 37.5 * 32 - 112, y 64 - 150; its
	# curtain (5 tiles) spans the river's head (tiles 35..39)
	assert_eq(w.position, Vector2(1088, -86), "the waterfall (224 x 160, feet at 150) pours onto the river's second tile row, its pool on the floor past the crowd")
	var tex := w.sprite_frames.get_frame_texture("default", 0)
	assert_eq(tex.get_size(), Vector2(224, 160), "Set 1's five-wide fall")
	var img := tex.get_image()
	var lum := 0.0
	var n := 0
	for y in range(40, 130, 3):
		for x in range(40, 184, 3):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				lum += c.get_luminance()
				n += 1
	assert_true(n > 0 and lum / n > 0.2, "tinted like the river, not a dark slab (luminance %.2f)" % (lum / maxf(1, n)))
	assert_eq(w.sprite_frames.get_frame_count("default"), 8, "its eight frames")
	assert_true(w.autoplay == "default", "and it plays")
	var torches := anim.get_children().filter(func(n): return String(n.name).begins_with("torch"))
	assert_eq(torches.size(), 4, "a torch on each gate tower")
	root.free()


func test_the_river_has_its_banks() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var problems: Array = load("res://tests/test_tiles_floodgate.gd").bank_problems(root, _manifest())
	assert_true(problems.is_empty(), "every edge of the river has its bank: %s" % [problems])
	var bank := root.get_node("WaterBank") as TileMapLayer
	assert_true(bank.get_index() > root.get_node("WaterSurface").get_index(), "drawn over the water's surface")
	assert_true(bank.get_index() < root.get_node("Pieces").get_index(), "and under the bridge")
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
