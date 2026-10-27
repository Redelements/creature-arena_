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
##              are painted with it as well (rounded out to whole tiles); a set with an
##              animated surface over water (manifest "surfaces") gets a WaterSurface layer
##   styles     {wall: "boulder", brush: "tuft", fence: "fence"}: the piece kind (manifest
##              "pieces" key) each map piece is drawn with; a kind the set lacks is skipped.
##              A kind may come oriented (`fence_h` / `fence_v`, by the rect's longer side) and
##              halved (`fence_v_l` / `_r`, `fence_h_t` / `_b`: the half of the tile a one-cell
##              piece lies in); the most specific pool the set has wins.
##              "fenceline:<name>" (manifest "fencelines") draws the kind's cells as joined
##              lines instead: each tile a post with rails to the neighbouring tiles of the
##              line (ends, runs, corners, junctions), in the half of the tile the line holds.
##              "bush:<name>" (manifest "bushes") draws each rect as a bed of swaying clumps
##   decor     [{kind, at: [tx, ty]} | {kind, pos: [x, y] units from the floor's top-left
##              corner, so the margins are negative or past the floor}]: a decor sprite
##              (manifest "decor") standing with its feet at the tile's bottom middle
##   anim       [{kind, at | pos}]: an animated piece (manifest "anim", a waterfall)
##   markings   true: ArenaView draws the court lines over the tiles (the Stadium)
## Rerun after a cut or a map's "tiles" block changes; the game and CI use the saved files.

const TILES_DIR := "res://assets/tiles/"
const ARENAS_DIR := "res://assets/arenas/"
const SRC_GROUND := 0
const SRC_PIECES := 1
const SRC_SURFACE := 2  ## the first animated surface; one source per surface from here
const BLOB_OVER := 3  ## px a bed of blob clumps may spill past its cells
const SRC_FENCE := 16  ## the first fence line (manifest "fencelines"); one source each from here
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
	# Animated surfaces (a translucent water sheet): one source each, from SRC_SURFACE up,
	# a single tile whose frames run along the strip.
	var sid := SRC_SURFACE
	for name in g.get("surfaces", {}):
		var s: Dictionary = g["surfaces"][name]
		var surf := TileSetAtlasSource.new()
		surf.texture = load(TILES_DIR + String(s["source"]))
		surf.texture_region_size = ts.tile_size
		ts.add_source(surf, sid)
		surf.create_tile(Vector2i.ZERO)
		surf.set_tile_animation_columns(Vector2i.ZERO, int(s["frames"]))
		surf.set_tile_animation_frames_count(Vector2i.ZERO, int(s["frames"]))
		for k in int(s["frames"]):
			surf.set_tile_animation_frame_duration(Vector2i.ZERO, k, 1.0 / maxf(1.0, float(s["fps"])))
		sid += 1
	# Fence lines: 32 x 64 tiles (the tile and the post rising over it), lifted by 16 so the
	# lower 32 px sit on the cell; a column per arm mask, a row per post spot.
	var fid := SRC_FENCE
	for name in man.get("fencelines", {}):
		var f: Dictionary = man["fencelines"][name]
		var fs := TileSetAtlasSource.new()
		fs.texture = load(TILES_DIR + String(f["source"]))
		fs.texture_region_size = Vector2i(int(f["cell"][0]), int(f["cell"][1]))
		ts.add_source(fs, fid)
		for row in f["spots"].size():
			for mask in 16:
				fs.create_tile(Vector2i(mask, row))
				fs.get_tile_data(Vector2i(mask, row), 0).texture_origin = Vector2i(0, (int(f["cell"][1]) - int(f["cell"][0])) / 2)
		fid += 1
	_save(ts, TILES_DIR + set_name + "_ground.tres")
	return ts


## The source id of the animated surface laid over `terrain` (-1: none).
static func _surface_source(man: Dictionary, terrain: String) -> int:
	var sid := SRC_SURFACE
	for name in man["ground"].get("surfaces", {}):
		if String(man["ground"]["surfaces"][name].get("over", name)) == terrain:
			return sid
		sid += 1
	return -1


## The source id of fence line `name` (-1: the set has none).
static func _fence_source(man: Dictionary, name: String) -> int:
	var fid := SRC_FENCE
	for n in man.get("fencelines", {}):
		if String(n) == name:
			return fid
		fid += 1
	return -1


## Draws the fence cells `cells` (a set: Vector2i -> true) as joined lines: per tile, the
## post spot (manifest "spots": across a line, the middle of the half it lies in; along it,
## the middle of the cells it holds) and the arms to the tiles whose fence cells touch this
## tile's (L 1, R 2, T 4, B 8). A tile where a vertical arm meets a horizontal one (a corner,
## a junction) puts its post where the two lines cross.
static func _fence_lines(pieces: TileMapLayer, man: Dictionary, name: String, cells: Dictionary, per: int) -> void:
	var fid := _fence_source(man, name)
	if fid < 0:
		push_warning("no fence line " + name)
		return
	var spots: Array = man["fencelines"][name]["spots"]
	var half := 32 / per  # a cell in tile px (16)
	var tiles := {}
	for c: Vector2i in cells:
		tiles[Vector2i(floori(float(c.x) / per), floori(float(c.y) / per))] = true
	for t: Vector2i in tiles:
		var mine: Array[Vector2i] = []
		for dy in per:
			for dx in per:
				if cells.has(t * per + Vector2i(dx, dy)):
					mine.append(t * per + Vector2i(dx, dy))
		var mask := 0
		var vx := -1  # the column a vertical arm leaves from, the row a horizontal one
		var hy := -1
		for c in mine:
			var lx := c.x - t.x * per
			var ly := c.y - t.y * per
			if lx == 0 and cells.has(c + Vector2i.LEFT):
				mask |= 1
				hy = ly
			if lx == per - 1 and cells.has(c + Vector2i.RIGHT):
				mask |= 2
				hy = ly
			if ly == 0 and cells.has(c + Vector2i.UP):
				mask |= 4
				vx = lx
			if ly == per - 1 and cells.has(c + Vector2i.DOWN):
				mask |= 8
				vx = lx
		# across: the arm's half; else the half every cell lies in; else the middle
		var xs := {}
		var ys := {}
		for c in mine:
			xs[c.x - t.x * per] = true
			ys[c.y - t.y * per] = true
		var sx := vx * half + half / 2 if vx >= 0 else (int(xs.keys()[0]) * half + half / 2 if xs.size() == 1 else 16)
		var sy := hy * half + half / 2 if hy >= 0 else (int(ys.keys()[0]) * half + half / 2 if ys.size() == 1 else 16)
		var row := 0
		for i in spots.size():
			if int(spots[i][0]) == sx and int(spots[i][1]) == sy:
				row = i
		pieces.set_cell(t, fid, Vector2i(mask, row))


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


## The SpriteFrames of a bush (manifest "bushes"): one animation per clump, its sway frames.
static func _bush_sprite_frames(man: Dictionary, name: String, cache: Dictionary) -> SpriteFrames:
	if cache.has(name):
		return cache[name]
	var b: Dictionary = man.get("bushes", {}).get(name, {})
	if b.is_empty():
		return null
	var tex: Texture2D = load(TILES_DIR + String(b["source"]))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var cw := int(b["cell"][0])
	var ch := int(b["cell"][1])
	for row in b["clumps"].size():
		var key := String(b["clumps"][row])
		var size: Array = b["sizes"][key]
		frames.add_animation(key)
		frames.set_animation_speed(key, float(b["fps"]))
		for k in int(b["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(k * cw, row * ch, int(size[0]), int(size[1]))
			frames.add_frame(key, at)
	cache[name] = frames
	return frames


## One bed of bushes over the brush rect `r` (cells): round blob clumps scattered over it
## (`_blob_spots`), or a nine-slice (corner clumps flush with the bed's corners, edge clumps
## along its sides, inner clumps filling the middle; `_nine_slice_spots`), each an
## AnimatedSprite2D of the clump's sway frames
## started at its own phase, sorted by its foot. `cell_px` is a cell in scene pixels (16).
## Each clump records the cells it covers (`meta "cells"`), so ArenaView can hide it while
## a dash has flattened them.
static func _bush_bed(brush: Node2D, root: Node, man: Dictionary, name: String, r: Array, cell_px: int, cache: Dictionary) -> void:
	var frames := _bush_sprite_frames(man, name, cache)
	if frames == null:
		push_warning("no bush " + name)
		return
	var b: Dictionary = man["bushes"][name]
	var sizes: Dictionary = b["sizes"]
	var x0 := int(r[0]) * cell_px
	var y0 := int(r[1]) * cell_px
	var w := int(r[2]) * cell_px
	var h := int(r[3]) * cell_px
	var n := int(b["frames"])
	var spots: Array = []  # [key, x, y] top-left corners in scene px

	var sz := func(key: String) -> Vector2i:
		return Vector2i(int(sizes[key][0]), int(sizes[key][1]))
	if b.get("blobs", false):
		spots = _blob_spots(b, x0, y0, w, h)
	else:
		_nine_slice_spots(spots, sz, x0, y0, w, h)
	for s in spots:
		var key := String(s[0])
		var size: Vector2i = sz.call(key)
		var px := int(s[1])
		var py := int(s[2])
		var sprite := AnimatedSprite2D.new()
		sprite.name = "%s_%d" % [key, brush.get_child_count()]
		sprite.sprite_frames = frames
		sprite.animation = key
		sprite.centered = false
		sprite.offset = Vector2(0, -size.y)  # y-sorted by its foot
		sprite.position = Vector2(px, py + size.y)
		sprite.flip_h = s.size() > 3 and bool(s[3])
		sprite.autoplay = key
		sprite.frame = _h(px, py, 11) % n
		sprite.speed_scale = 0.85 + 0.3 * float(_h(px, py, 12) % 10) / 10.0
		# the cells this clump covers, clipped to the bed (what a dash can flatten)
		var cx0 := clampi(floori(float(px) / cell_px), int(r[0]), int(r[0]) + int(r[2]) - 1)
		var cy0 := clampi(floori(float(py) / cell_px), int(r[1]), int(r[1]) + int(r[3]) - 1)
		var cx1 := clampi(ceili(float(px + size.x) / cell_px), cx0 + 1, int(r[0]) + int(r[2]))
		var cy1 := clampi(ceili(float(py + size.y) / cell_px), cy0 + 1, int(r[1]) + int(r[3]))
		sprite.set_meta("cells", Rect2i(cx0, cy0, cx1 - cx0, cy1 - cy0))
		brush.add_child(sprite)
		sprite.owner = root


## A bed of round blob clumps (manifest bushes.<name>.blobs): rows of slots the size of the
## biggest clump, overlapping by about 40 % across and half down, every other row shifted by
## half a step, the first and last slot of each row and the first and last row flush with
## the bed (BLOB_OVER px over it at most), so the leafy outlines make the bed's edge. Each
## slot takes a clump, a mirror and a nudge of its own (a fixed hash), so neighbours differ
## and no column or row lines up. Returns [key, x, y, flip] top-left corners in scene px.
static func _blob_spots(b: Dictionary, x0: int, y0: int, w: int, h: int) -> Array:
	var keys: Array = b["clumps"]
	var cw := int(b["cell"][0])
	var ch := int(b["cell"][1])
	var step := Vector2i(int(cw * 0.6), int(ch * 0.5))
	var spots: Array = []
	var span_y := h + 2 * BLOB_OVER - ch
	var rows := maxi(1, ceili(float(span_y) / step.y) + 1)
	for j in rows:
		var yy := y0 - BLOB_OVER + (0 if rows == 1 else roundi(float(j * span_y) / (rows - 1)))
		var shift := step.x / 2 if j % 2 == 1 else 0
		var span_x := w + 2 * BLOB_OVER - cw - shift
		var cols := maxi(1, ceili(float(span_x) / step.x) + 1)
		for i in cols:
			var xx := x0 - BLOB_OVER + shift + (0 if cols == 1 else roundi(float(i * span_x) / (cols - 1)))
			var key := String(keys[_h(xx, yy, 13) % keys.size()])
			var size: Array = b["sizes"][key]
			# centred in its slot, nudged a little inside the bed's edge
			var px := xx + (cw - int(size[0])) / 2
			var py := yy + (ch - int(size[1])) / 2
			if i > 0 and i < cols - 1:
				px += _h(xx, yy, 14) % 5 - 2
			if j > 0 and j < rows - 1:
				py += _h(xx, yy, 15) % 5 - 2
			spots.append([key, px, py, _h(xx, yy, 16) % 2 == 1])
	return spots


## The nine-slice bed's spots (Twin Keeps): the middle first (drawn under), then the edges,
## then the corners on top. Appends [key, x, y] top-left corners in scene px to `spots`.
static func _nine_slice_spots(spots: Array, sz: Callable, x0: int, y0: int, w: int, h: int) -> void:
	var c: Vector2i = sz.call("c")
	var yy := y0 + 10
	var row_k := 0
	while yy + c.y <= y0 + h - 6 or row_k == 0:
		var xx := x0 + 10 + (int(c.x * 0.35) if row_k % 2 == 1 else 0)
		while xx + c.x <= x0 + w - 6 or xx == x0 + 10:
			spots.append(["c", xx + _h(xx, yy, 5) % 7 - 3, yy + _h(xx, yy, 6) % 5 - 2])
			xx += int(c.x * 0.72)
		yy += int(c.y * 0.6)
		row_k += 1
	var t: Vector2i = sz.call("t")
	var bt: Vector2i = sz.call("b")
	var tl: Vector2i = sz.call("tl")
	var tr: Vector2i = sz.call("tr")
	var bl: Vector2i = sz.call("bl")
	var br: Vector2i = sz.call("br")
	var xx2 := x0 + tl.x - int(t.x * 0.4)
	while xx2 + t.x < x0 + w - tr.x + int(t.x * 0.4):
		spots.append(["t", xx2 + _h(xx2, y0, 7) % 5 - 2, y0])
		spots.append(["b", xx2 + _h(xx2, y0 + h, 8) % 5 - 2, y0 + h - bt.y])
		xx2 += int(t.x * 0.75)
	var l: Vector2i = sz.call("l")
	var rr: Vector2i = sz.call("r")
	var yy2 := y0 + tl.y - int(l.y * 0.4)
	while yy2 + l.y < y0 + h - bl.y + int(l.y * 0.4):
		spots.append(["l", x0, yy2 + _h(x0, yy2, 9) % 5 - 2])
		spots.append(["r", x0 + w - rr.x, yy2 + _h(x0 + w, yy2, 10) % 5 - 2])
		yy2 += int(l.y * 0.75)
	spots.append(["tl", x0, y0])
	spots.append(["tr", x0 + w - tr.x, y0])
	spots.append(["bl", x0, y0 + h - bl.y])
	spots.append(["br", x0 + w - br.x, y0 + h - br.y])


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
	var names := ["grass", "water"]  # always there (tests look for the layers), then the set's own
	for i in ts.get_terrains_count(0):
		if not ts.get_terrain_name(0, i) in names:
			names.append(ts.get_terrain_name(0, i))
	for name in names:
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
		# the terrain's animated surface, if the set has one, on its own layer over it
		var sid := _surface_source(man, name)
		if sid >= 0 and not cells.is_empty():
			var surface := _layer(root, name.capitalize() + "Surface", ts)
			for c in cells:
				surface.set_cell(c, sid, Vector2i.ZERO)

	var pieces := _layer(root, "Pieces", ts)
	var styles: Dictionary = DEFAULT_STYLES.duplicate()
	styles.merge(tiles.get("styles", {}), true)
	# the map's bridges are pieces too (style "bridge"): ArenaView clears a tile whose cells
	# left the map's state, so a fallen bridge shows the water painted under it
	var placed: Array = map.get("pieces", []).duplicate()
	for b in map.get("bridges", []):
		placed.append({"kind": "bridge", "rect": b.get("rect", [0, 0, 0, 0])})
	# brush drawn as bushes (`styles.brush: "bush:<name>"`): a nine-slice of swaying canopy
	# clumps per bed, under the fighters like the rest of the scene; ArenaView hides a clump
	# whose cells are flattened (`_sync_brush`)
	var brush := Node2D.new()
	brush.name = "Brush"
	brush.y_sort_enabled = true
	root.add_child(brush)
	brush.owner = root
	var bush_frames := {}
	var fence_cells := {}  # fence line name -> {cell: true}
	for piece in placed:
		var kind := String(piece.get("kind", ""))
		var r: Array = piece.get("rect", [0, 0, 0, 0])
		if r.size() < 4 or not styles.has(kind):
			continue
		var style := String(styles[kind])
		if style.begins_with("bush:"):
			_bush_bed(brush, root, man, style.trim_prefix("bush:"), r, tile / per, bush_frames)
			continue
		if style.begins_with("fenceline:"):
			var line: Dictionary = fence_cells.get_or_add(style.trim_prefix("fenceline:"), {})
			for cy in range(int(r[1]), int(r[1]) + int(r[3])):
				for cx in range(int(r[0]), int(r[0]) + int(r[2])):
					line[Vector2i(cx, cy)] = true
			continue
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
	for name in fence_cells:
		_fence_lines(pieces, man, String(name), fence_cells[name], per)

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
	if brush.get_child_count() > 0:
		print("  bush clumps: ", brush.get_child_count())
	DirAccess.make_dir_recursive_absolute(ARENAS_DIR)
	var err := ResourceSaver.save(packed, path)
	if err != OK:
		push_error("could not save %s: %d" % [path, err])
	print("wrote ", path, ": ", cols, "x", rows, " tiles, terrains ", counts,
		", pieces ", pieces.get_used_cells().size(), ", decor ", decor.get_child_count(), ", anim ", anim.get_child_count())
	root.free()
