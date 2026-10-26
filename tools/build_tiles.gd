extends SceneTree
## Builds the Godot TileSets and the tiled arenas' ground scenes from a cut pack's manifest
## (assets/tiles/<set>_manifest.json, written by tools/cut_set1.py).
##
## Run from the repo root, after `--import` (the atlases must be imported):
##   godot --headless --path . --script res://tools/build_tiles.gd [-- --set=set1]
##
## Writes:
##   assets/tiles/<set>_ground.tres    tile size 32: source 0 the ground atlas (fills and the
##                                     grass terrain, terrain set 0 "grass" matched by sides,
##                                     variants by probability), source 1 the pieces atlas
##   assets/tiles/<set>_overlay.tres   tile size 16: source 0 the overlay atlas, one tile per
##                                     id (ArenaView.OV_*; assets/README.md)
##   assets/arenas/<id>.tscn           for every data/arenas/<id>.json with a "tiles" block
##                                     naming this set: a Node2D of TileMapLayers, "Ground" (the
##                                     fill, one tile past the floor all round), "Grass" (the
##                                     map's grass rects, autotiled) and "Pieces" (boulders on
##                                     its walls, tufts on its brush). ArenaView instantiates it
##                                     at half scale under the floor (a 32 px tile is 2 x 2
##                                     cells) and draws the breaking ground over it.
## Rerun after a cut or a map's "tiles" block changes; the game and CI use the saved files.

const TILES_DIR := "res://assets/tiles/"
const ARENAS_DIR := "res://assets/arenas/"
const SRC_GROUND := 0
const SRC_PIECES := 1
const SIDES := [TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE]


func _init() -> void:
	var set_name := "set1"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--set="):
			set_name = a.trim_prefix("--set=")
	var man := _json(TILES_DIR + set_name + "_manifest.json")
	if man.is_empty():
		push_error("no manifest for " + set_name)
		quit(1)
		return
	var ground := _ground_set(set_name, man)
	var overlay := _overlay_set(set_name, man)
	var built := 0
	for f in DirAccess.get_files_at("res://data/arenas/"):
		if not f.ends_with(".json"):
			continue
		var map := _json("res://data/arenas/" + f)
		var tiles: Dictionary = map.get("tiles", {})
		if tiles.is_empty() or String(tiles.get("set", "set1")) != set_name:
			continue
		_build_scene(map, tiles, man, ground)
		built += 1
	print("built ", ground.resource_path, ", ", overlay.resource_path, " and ", built, " arena scene(s)")
	quit(0)


static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func _v(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


static func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("could not save %s: %d" % [path, err])
	res.take_over_path(path)  # so a scene packed next refers to it by path


## The ground TileSet: the fills and the grass terrain (matched by sides), and the pieces.
static func _ground_set(set_name: String, man: Dictionary) -> TileSet:
	var g: Dictionary = man["ground"]
	var ts := TileSet.new()
	ts.tile_size = Vector2i(int(g["tile"]), int(g["tile"]))
	ts.add_terrain_set()
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_SIDES)
	var terrain_ids := {}
	for name in g["terrains"]:
		ts.add_terrain(0)
		var idx := ts.get_terrains_count(0) - 1
		ts.set_terrain_name(0, idx, String(name))
		ts.set_terrain_color(0, idx, Color(0.3, 0.7, 0.3) if name == "grass" else Color(0.6, 0.5, 0.3))
		terrain_ids[name] = idx
	var src := TileSetAtlasSource.new()
	src.texture = load(TILES_DIR + String(g["source"]))
	src.texture_region_size = ts.tile_size
	ts.add_source(src, SRC_GROUND)
	for fill in g["fills"]:
		for at in g["fills"][fill]:
			src.create_tile(_v(at))
	for name in g["terrains"]:
		for t in g["terrains"][name]:
			var at := _v(t["at"])
			src.create_tile(at)
			var td := src.get_tile_data(at, 0)
			td.terrain_set = 0
			td.terrain = terrain_ids[name]
			td.probability = float(t.get("prob", 1.0))
			var sides: Array = t["sides"]
			for k in 4:
				td.set_terrain_peering_bit(SIDES[k], terrain_ids[name] if int(sides[k]) == 1 else -1)
	var p: Dictionary = man["pieces"]
	var pieces := TileSetAtlasSource.new()
	pieces.texture = load(TILES_DIR + String(p["source"]))
	pieces.texture_region_size = ts.tile_size
	ts.add_source(pieces, SRC_PIECES)
	for kind in ["boulder", "tuft", "sprig"]:
		for at in p.get(kind, []):
			pieces.create_tile(_v(at))
	_save(ts, TILES_DIR + set_name + "_ground.tres")
	return ts


## The overlay TileSet: 16 px tiles, one per id, in the order ArenaView draws them.
static func _overlay_set(set_name: String, man: Dictionary) -> TileSet:
	var o: Dictionary = man["overlay"]
	var ts := TileSet.new()
	ts.tile_size = Vector2i(int(o["tile"]), int(o["tile"]))
	var src := TileSetAtlasSource.new()
	src.texture = load(TILES_DIR + String(o["source"]))
	src.texture_region_size = ts.tile_size
	ts.add_source(src, 0)
	var cols := int(o["columns"])
	var ids := []
	for key in o["ids"]:
		var v = o["ids"][key]
		if v is Array:
			ids.append_array(v)
		else:
			ids.append(v)
	for id in ids:
		src.create_tile(Vector2i(int(id) % cols, int(id) / cols))
	_save(ts, TILES_DIR + set_name + "_overlay.tres")
	return ts


## A small fixed hash, so a scene rebuilt from the same map picks the same variants.
static func _h(x: int, y: int, k: int) -> int:
	return posmod((x * 73856093) ^ (y * 19349663) ^ (k * 83492791), 1021)


## One map's ground scene: the fill under everything (a tile past the floor all round),
## the grass autotiled, boulders on the walls and tufts on the brush.
static func _build_scene(map: Dictionary, tiles: Dictionary, man: Dictionary, ts: TileSet) -> void:
	var g: Dictionary = man["ground"]
	var p: Dictionary = man["pieces"]
	var cell := int(SimDefs.CELL)
	var per := int(ts.tile_size.x) / (cell * ArtScale.PX_PER_UNIT)  # cells a tile covers (2)
	var size := ArenaMap.size_of(map)
	var cols := ceili(float(size.x) / per)
	var rows := ceili(float(size.y) / per)
	var root := Node2D.new()
	root.name = "Ground"

	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = ts
	var fill: Array = g["fills"][String(tiles.get("ground", "dirt"))]
	var block := int(sqrt(float(fill.size())))  # the fill is a square block of seamless tiles
	for ty in range(-1, rows + 1):
		for tx in range(-1, cols + 1):
			ground.set_cell(Vector2i(tx, ty), SRC_GROUND, _v(fill[posmod(ty, block) * block + posmod(tx, block)]))
	root.add_child(ground)
	ground.owner = root

	var grass := TileMapLayer.new()
	grass.name = "Grass"
	grass.tile_set = ts
	var cells: Array[Vector2i] = []
	for r in tiles.get("grass", []):
		for ty in range(int(r[1]), int(r[1]) + int(r[3])):
			for tx in range(int(r[0]), int(r[0]) + int(r[2])):
				var c := Vector2i(tx, ty)
				if not c in cells:
					cells.append(c)
	if not cells.is_empty():
		grass.set_cells_terrain_connect(cells, 0, 0, false)
	root.add_child(grass)
	grass.owner = root

	var pieces := TileMapLayer.new()
	pieces.name = "Pieces"
	pieces.tile_set = ts
	for piece in map.get("pieces", []):
		var kind := String(piece.get("kind", ""))
		var r: Array = piece.get("rect", [0, 0, 0, 0])
		if r.size() < 4 or not (kind in ["wall", "brush"]):
			continue
		var x0 := floori(float(r[0]) / per)
		var y0 := floori(float(r[1]) / per)
		var x1 := ceili(float(int(r[0]) + int(r[2])) / per)
		var y1 := ceili(float(int(r[1]) + int(r[3])) / per)
		for ty in range(y0, y1):
			for tx in range(x0, x1):
				var pool: Array = p["boulder"] if kind == "wall" else (p["tuft"] if _h(tx, ty, 1) % 3 > 0 else p["sprig"])
				pieces.set_cell(Vector2i(tx, ty), SRC_PIECES, _v(pool[_h(tx, ty, 2) % pool.size()]))
	root.add_child(pieces)
	pieces.owner = root

	var packed := PackedScene.new()
	packed.pack(root)
	var path := ARENAS_DIR + String(map["id"]) + ".tscn"
	DirAccess.make_dir_recursive_absolute(ARENAS_DIR)
	var err := ResourceSaver.save(packed, path)
	if err != OK:
		push_error("could not save %s: %d" % [path, err])
	print("wrote ", path, ": ", cols, "x", rows, " tiles, ", cells.size(), " grass, ", pieces.get_used_cells().size(), " pieces")
	root.free()
