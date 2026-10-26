extends SceneTree
## Builds the Godot TileSets and the tiled arenas' ground scenes from a cut set's manifest
## (assets/tiles/<set>_manifest.json, written by tools/cut_tiles.py from a recipe).
##
## Run from the repo root, after `--import` (the atlases must be imported):
##   godot --headless --path . --script res://tools/build_tiles.gd [-- --set=set1]
##
## Writes:
##   assets/tiles/<set>_ground.tres    tile size 32: source 0 the ground atlas (the fills and
##                                     every terrain of the manifest, terrain set 0 matched by
##                                     sides, variants by probability), source 1 the pieces
##   assets/tiles/<set>_overlay.tres   tile size 16: source 0 the overlay atlas, one tile per
##                                     id (ArenaView.OV_*; assets/README.md)
##   assets/arenas/<id>.tscn           for every data/arenas/<id>.json with a "tiles" block
##                                     naming this set: a Node2D of TileMapLayers and sprites
##                                     that ArenaView instances at half scale under the floor
##                                     (a 32 px tile is 2 x 2 cells) and draws the breaking
##                                     ground over.
##
## A map's "tiles" block:
##   set        the cut set (default "set1")
##   ground     the fill under everything (a manifest fill name)
##   edge       a fill for the one-tile ring past the floor (default the ground)
##   patches    [{fill, rect: [tx, ty, w, h]}]: rects of another fill over the ground
##   grass      rects [tx, ty, w, h] in tiles painted with the "grass" terrain (autotiled)
##   water      rects in tiles painted with the "water" terrain; the map's shallows pieces
##              are painted with it as well (rounded out to whole tiles)
##   styles     {wall: "boulder", brush: "tuft", fence: "fence"}: the piece kind (manifest
##              "pieces" key) each map piece is drawn with; a kind the set lacks is skipped.
##              A kind may come oriented (`fence_h` / `fence_v`, by the rect's longer side) and
##              halved (`fence_v_l` / `_r`, `fence_h_t` / `_b`: the half of the tile a one-cell
##              piece lies in); the most specific pool the set has wins
##   decor      [{kind, at: [tx, ty]} | {kind, pos: [x, y] units from the floor's top-left
##              corner, so the margins are negative or past the floor}]: a decor sprite
##              (manifest "decor") standing with its feet at the tile's bottom middle
##   anim       [{kind, at | pos}]: an animated piece (manifest "anim", a waterfall)
##   markings   true: ArenaView draws the court lines over the tiles (the Stadium)
## Rerun after a cut or a map's "tiles" block changes; the game and CI use the saved files.

const TILES_DIR := "res://assets/tiles/"
const ARENAS_DIR := "res://assets/arenas/"
const SRC_GROUND := 0
const SRC_PIECES := 1
const SIDES := [TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE]
const DEFAULT_STYLES := {"wall": "boulder", "brush": "tuft", "fence": "fence", "bridge": "bridge"}


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


## The ground TileSet: the fills, every terrain (matched by sides) and the pieces.
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
		ts.set_terrain_color(0, idx, {"grass": Color(0.3, 0.7, 0.3), "water": Color(0.2, 0.4, 0.8)}.get(name, Color(0.6, 0.5, 0.3)))
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
	for kind in p:
		if p[kind] is Array:
			for at in p[kind]:
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


## The tiles a rect of cells covers (rounded out to whole tiles).
static func _tiles_of(r: Array, per: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 := floori(float(r[0]) / per)
	var y0 := floori(float(r[1]) / per)
	var x1 := ceili(float(int(r[0]) + int(r[2])) / per)
	var y1 := ceili(float(int(r[1]) + int(r[3])) / per)
	for ty in range(y0, y1):
		for tx in range(x0, x1):
			out.append(Vector2i(tx, ty))
	return out


static func _layer(root: Node2D, name: String, ts: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = name
	layer.tile_set = ts
	root.add_child(layer)
	layer.owner = root
	return layer


## Paints `cells` with a terrain, connecting them to each other.
static func _terrain(layer: TileMapLayer, ts: TileSet, name: String, cells: Array[Vector2i]) -> int:
	if cells.is_empty():
		return 0
	for i in ts.get_terrains_count(0):
		if ts.get_terrain_name(0, i) == name:
			layer.set_cells_terrain_connect(cells, 0, i, false)
			return cells.size()
	push_warning("the set has no terrain " + name)
	return 0


## Where a decor or anim entry stands, in scene pixels (2 a unit): a tile's bottom middle
## (`at`) or a point in units from the floor's top-left corner (`pos`).
static func _spot(e: Dictionary, tile: int) -> Vector2:
	if e.has("pos"):
		return Vector2(float(e["pos"][0]), float(e["pos"][1])) * ArtScale.PX_PER_UNIT
	var at := _v(e["at"])
	return Vector2((at.x + 0.5) * tile, (at.y + 1) * tile)


## One map's ground scene: the fill under everything (a tile past the floor all round, an
## `edge` fill for that ring), the terrains, the pieces, the decor and the animated pieces.
static func _build_scene(map: Dictionary, tiles: Dictionary, man: Dictionary, ts: TileSet) -> void:
	var g: Dictionary = man["ground"]
	var p: Dictionary = man["pieces"]
	var tile := int(ts.tile_size.x)
	var per := tile / (int(SimDefs.CELL) * ArtScale.PX_PER_UNIT)  # cells a tile covers (2)
	var size := ArenaMap.size_of(map)
	var cols := ceili(float(size.x) / per)
	var rows := ceili(float(size.y) / per)
	var root := Node2D.new()
	root.name = "Ground"

	var ground := _layer(root, "Ground", ts)
	var fill: Array = g["fills"][String(tiles.get("ground", "dirt"))]
	var edge: Array = g["fills"][String(tiles.get("edge", tiles.get("ground", "dirt")))]
	for ty in range(-1, rows + 1):
		for tx in range(-1, cols + 1):
			var ring := tx < 0 or ty < 0 or tx >= cols or ty >= rows
			var f := edge if ring else fill
			var block := int(sqrt(float(f.size())))  # a fill is a square block of seamless tiles
			ground.set_cell(Vector2i(tx, ty), SRC_GROUND, _v(f[posmod(ty, block) * block + posmod(tx, block)]))
	# `patches`: rects of another fill laid over the ground (a worn lane, a cobbled corner),
	# for sets without a blob terrain. [{fill, rect: [tx, ty, w, h]}] in tiles.
	for patch in tiles.get("patches", []):
		var f: Array = g["fills"].get(String(patch.get("fill", "")), [])
		var r: Array = patch.get("rect", [])
		if f.is_empty() or r.size() < 4:
			push_warning("a patch needs a known fill and a rect: " + str(patch))
			continue
		var block := int(sqrt(float(f.size())))
		for ty in range(int(r[1]), int(r[1]) + int(r[3])):
			for tx in range(int(r[0]), int(r[0]) + int(r[2])):
				ground.set_cell(Vector2i(tx, ty), SRC_GROUND, _v(f[posmod(ty, block) * block + posmod(tx, block)]))

	var counts := {}
	for name in ["grass", "water"]:
		var layer := _layer(root, name.capitalize(), ts)
		var cells: Array[Vector2i] = []
		for r in tiles.get(name, []):
			for ty in range(int(r[1]), int(r[1]) + int(r[3])):
				for tx in range(int(r[0]), int(r[0]) + int(r[2])):
					var c := Vector2i(tx, ty)
					if not c in cells:
						cells.append(c)
		if name == "water":
			# the map's shallows, and the water under its bridges (shown when one falls in)
			var wet: Array = []
			for piece in map.get("pieces", []):
				if String(piece.get("kind", "")) == "shallows":
					wet.append(piece.get("rect", [0, 0, 0, 0]))
			for b in map.get("bridges", []):
				wet.append(b.get("rect", [0, 0, 0, 0]))
			for r in wet:
				for c in _tiles_of(r, per):
					if not c in cells:
						cells.append(c)
		counts[name] = _terrain(layer, ts, name, cells)

	var pieces := _layer(root, "Pieces", ts)
	var styles: Dictionary = DEFAULT_STYLES.duplicate()
	styles.merge(tiles.get("styles", {}), true)
	# the map's bridges are pieces too (style "bridge"): ArenaView clears a tile whose cells
	# left the map's state, so a fallen bridge shows the water painted under it
	var placed: Array = map.get("pieces", []).duplicate()
	for b in map.get("bridges", []):
		placed.append({"kind": "bridge", "rect": b.get("rect", [0, 0, 0, 0])})
	for piece in placed:
		var kind := String(piece.get("kind", ""))
		var r: Array = piece.get("rect", [0, 0, 0, 0])
		if r.size() < 4 or not styles.has(kind):
			continue
		var style := String(styles[kind])
		# a kind with oriented tiles (fence_h / fence_v) picks by the rect's longer side, and
		# one with half tiles (fence_v_l / fence_v_r, fence_h_t / fence_h_b) by which half of
		# the 2 x 2-cell tile a one-cell-wide piece lies in
		var vertical := int(r[3]) > int(r[2])
		var oriented := style + ("_v" if vertical else "_h")
		var half := oriented + (("_l" if int(r[0]) % per == 0 else "_r") if vertical else ("_t" if int(r[1]) % per == 0 else "_b"))
		var pool: Array = p.get(half, p.get(oriented, p.get(style, [])))
		var alt: Array = p.get("sprig", []) if style == "tuft" else []
		if pool.is_empty():
			continue
		for c in _tiles_of(r, per):
			var pick: Array = alt if not alt.is_empty() and _h(c.x, c.y, 1) % 3 == 0 else pool
			pieces.set_cell(c, SRC_PIECES, _v(pick[_h(c.x, c.y, 2) % pick.size()]))

	var decor := Node2D.new()
	decor.name = "Decor"
	root.add_child(decor)
	decor.owner = root
	for e in tiles.get("decor", []):
		var d: Dictionary = man.get("decor", {}).get(String(e.get("kind", "")), {})
		if d.is_empty():
			push_warning("no decor " + String(e.get("kind", "")))
			continue
		var s := Sprite2D.new()
		s.name = "%s_%d" % [String(e["kind"]), decor.get_child_count()]
		s.texture = load(TILES_DIR + String(d["source"]))
		s.centered = false
		s.position = _spot(e, tile) - Vector2(float(d["feet"][0]), float(d["feet"][1]))
		decor.add_child(s)
		s.owner = root

	var anim := Node2D.new()
	anim.name = "Anim"
	root.add_child(anim)
	anim.owner = root
	for e in tiles.get("anim", []):
		var a: Dictionary = man.get("anim", {}).get(String(e.get("kind", "")), {})
		if a.is_empty():
			push_warning("no anim " + String(e.get("kind", "")))
			continue
		var tex: Texture2D = load(TILES_DIR + String(a["source"]))
		var frames := SpriteFrames.new()
		frames.set_animation_speed("default", float(a["fps"]))
		var fw := int(a["frame"][0])
		var fh := int(a["frame"][1])
		for k in int(a["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(k * fw, 0, fw, fh)
			frames.add_frame("default", at)
		var s := AnimatedSprite2D.new()
		s.name = "%s_%d" % [String(e["kind"]), anim.get_child_count()]
		s.sprite_frames = frames
		s.centered = false
		s.autoplay = "default"
		s.position = _spot(e, tile) - Vector2(float(a["feet"][0]), float(a["feet"][1]))
		anim.add_child(s)
		s.owner = root

	var packed := PackedScene.new()
	packed.pack(root)
	var path := ARENAS_DIR + String(map["id"]) + ".tscn"
	DirAccess.make_dir_recursive_absolute(ARENAS_DIR)
	var err := ResourceSaver.save(packed, path)
	if err != OK:
		push_error("could not save %s: %d" % [path, err])
	print("wrote ", path, ": ", cols, "x", rows, " tiles, grass ", counts["grass"], ", water ", counts["water"],
		", pieces ", pieces.get_used_cells().size(), ", decor ", decor.get_child_count(), ", anim ", anim.get_child_count())
	root.free()
