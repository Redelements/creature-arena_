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
##   assets/tiles/<set>_shore.tres     tile size 32: the bank tiles round a terrain (manifest
##                                     "shores"), one per land-neighbour mask (a set without
##                                     shores writes none)
##   assets/tiles/<set>_cells.tres     tile size 16 (one terrain cell): source 0 the scatter
##                                     sprites, 1.. the raised walls (a set with neither writes none)
##   assets/arenas/<id>.tscn           for every data/arenas/<id>.json with a "tiles" block
##                                     naming this set: a Node2D of TileMapLayers and sprites
##                                     that ArenaView instances at half scale under the floor
##                                     (a 32 px tile is 2 x 2 cells) and draws the breaking
##                                     ground over.
##
## A map's "tiles" block:
##   set        the cut set (default "set1")
##   ground     the fill under everything (a manifest fill name)
##   edge       a fill for a one-tile ring past the floor; only for a map whose picture
##              has no stands against the floor (the ring would cover their hoardings)
##   patches    [{fill, rect: [tx, ty, w, h]}]: rects of another fill over the ground
##   grass      rects [tx, ty, w, h] in tiles painted with the "grass" terrain (autotiled)
##   water      rects in tiles painted with the "water" terrain; the map's shallows pieces
##              are painted with it as well (rounded out to whole tiles); a set with an
##              animated surface over water (manifest "surfaces") gets a WaterSurface layer
##              (a second surface over the same terrain a WaterSurface<Name> layer over it; a
##              surface cut in "variants" rows picks a row per tile),
##              and one with a shore (manifest "shores") a WaterBank layer over that: a bank
##              tile on every water tile with land round it, picked by its eight neighbours
##   styles     {wall: "boulder", brush: "tuft", fence: "fence"}: the piece kind (manifest
##              "pieces" key) each map piece is drawn with; a kind the set lacks is skipped.
##              A kind may come oriented (`fence_h` / `fence_v`, by the rect's longer side) and
##              halved (`fence_v_l` / `_r`, `fence_h_t` / `_b`: the half of the tile a one-cell
##              piece lies in); the most specific pool the set has wins.
##              "fenceline:<name>" (manifest "fencelines") draws the kind's cells as joined
##              lines instead: each tile a post with rails to the neighbouring tiles of the
##              line (ends, runs, corners, junctions), in the half of the tile the line holds.
##              "bush:<name>" (manifest "bushes") draws each rect as a bed of swaying clumps;
##              "wall:<name>" draws a wall as a run of tall sprites, one per tile (manifest
##              "walls"), with the rubble a smashed tile shows;
##              "raised:<name>" (manifest "raised") draws every wall cell as a raised plateau:
##              16 px "Raised" tiles (the top, and the cliff face on a column's last cells,
##              all on the wall's own cells) over a "RaisedShadow" layer (the contact shadow
##              on the floor away from the map's light), picked by src/view/raised_tiles.gd and
##              repainted by ArenaView as cells are smashed; the rubble is the recipe's
##              "rubble" walls entry's heaps
##   shoulder   true: the water's bank (manifest shores.water.shoulder) also lays a ragged
##              band of trodden ground on the land tiles round the water, a tile per mask of
##              water neighbours, on floor tiles only, on a "Shoulder" layer under the water
##   scatter    [{kind, where: "floor" | "near_walls" | "near_water" | "near_fences" |
##              "near_brush" | "verge" (with `of`: a terrain key of this block, its rects'
##              edges but never on them) | [[tx, ty, w, h], ...],
##              near: 3, density: 0.05, seed}]: small sprites (manifest "scatter" kinds) on a
##              16 px "Scatter" layer, one a cell at most, by a fixed hash (a rebuild lays the
##              same ones); never on water, walls, fences, chasms, brush (or next to it), the
##              court markings, a flag base's capture zone or a shrine (`scatter_clear`)
##   scatter_clear  [[col, row, w, h], ...] cell rects the scatter keeps off (a keep's gates)
##   decor      [{kind, at: [tx, ty]} | {kind, pos: [x, y] units from the floor's top-left
##              corner, so the margins are negative or past the floor}]: a decor sprite
##              (manifest "decor") standing with its feet at the tile's bottom middle.
##              A piece whose feet stand on one of the map's wall cells, or with `"wall": true`
##              (a banner hung on a wall), joins the y-sorted Walls run and hides while the
##              wall cell under its feet is smashed; `lift` (units) raises the picture off its
##              spot onto the wall's top. On a raised wall a piece whose feet fall on the
##              face stands on the top just behind it, and goes when its column is smashed
##   anim       [{kind, at | pos, wall, lift}]: an animated piece (manifest "anim", a waterfall)
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
const CELL_PX := 16  ## a terrain cell in scene px: the raised and scatter tiles' size
const TRACK_CLEAR := 20.0  ## units: no scatter this near the map's `track` (the caravan's path)
const RAISED_INSET := 3.0  ## px a piece on a raised wall's top stands in from its face (_place)
const SRC_SCATTER := 0  ## in <set>_cells.tres: the scatter sprites
const SRC_RAISED := 1  ## in <set>_cells.tres: the first raised wall (manifest "raised"); one source each
const SCATTER_ALTS := 8  ## a scatter sprite's looks: plain, then mirrored and nudged
const SCATTER_BASE_CLEAR := 48.0  ## units round a flag base kept clear of scatter (its capture zone and stand)
const SCATTER_NUDGE: Array[Vector2i] = [Vector2i.ZERO, Vector2i(3, 2), Vector2i(-4, 1), Vector2i(2, -3)]
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
	var shore := _shore_set(set_name, man)
	var small := _cells_set(set_name, man)
	var built := 0
	for f in DirAccess.get_files_at("res://data/arenas/"):
		if not f.ends_with(".json"):
			continue
		var map := _json("res://data/arenas/" + f)
		var tiles: Dictionary = map.get("tiles", {})
		if tiles.is_empty() or String(tiles.get("set", "set1")) != set_name:
			continue
		_build_scene(map, tiles, man, ground, shore, small)
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
		for row in int(s.get("variants", 1)):  # a tile per variant row, its frames along the row
			var at := Vector2i(0, row)
			surf.create_tile(at)
			surf.set_tile_animation_columns(at, int(s["frames"]))
			surf.set_tile_animation_frames_count(at, int(s["frames"]))
			for k in int(s["frames"]):
				surf.set_tile_animation_frame_duration(at, k, 1.0 / maxf(1.0, float(s["fps"])))
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


## The animated surfaces laid over `terrain`, in recipe order: [[source id, name], ...].
static func _surface_sources(man: Dictionary, terrain: String) -> Array:
	var out := []
	var sid := SRC_SURFACE
	for name in man["ground"].get("surfaces", {}):
		if String(man["ground"]["surfaces"][name].get("over", name)) == terrain:
			out.append([sid, String(name)])
		sid += 1
	return out


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


## The bank TileSet (manifest "shores"): 32 px, one source per shored terrain in the
## manifest's order, a tile per land-neighbour mask. Null for a set without shores.
static func _shore_set(set_name: String, man: Dictionary) -> TileSet:
	var shores: Dictionary = man["ground"].get("shores", {})
	if shores.is_empty():
		return null
	var ts := TileSet.new()
	ts.tile_size = Vector2i(int(man["ground"]["tile"]), int(man["ground"]["tile"]))
	var sid := 0
	for name in shores:
		var src := TileSetAtlasSource.new()
		src.texture = load(TILES_DIR + String(shores[name]["source"]))
		src.texture_region_size = ts.tile_size
		ts.add_source(src, sid)
		for key in shores[name]["tiles"]:
			src.create_tile(_v(shores[name]["tiles"][key]))
		for key in shores[name].get("shoulder", {}):
			src.create_tile(_v(shores[name]["shoulder"][key]))
		sid += 1
	_save(ts, TILES_DIR + set_name + "_shore.tres")
	return ts


## The 16 px TileSet (one tile a terrain cell) of a set's raised walls and scatter, or null
## when it has neither: source SRC_SCATTER the scatter sprites (manifest "scatter": each a
## 32 px slot, a 2 x 2 tile centred on its cell, so its feet at the slot's (16, 24) stand on
## the cell's bottom middle; SCATTER_ALTS alternatives each, mirrored and nudged), then one
## source per raised wall (manifest "raised", in order: SRC_RAISED + its index).
static func _cells_set(set_name: String, man: Dictionary) -> TileSet:
	var sc: Dictionary = man.get("scatter", {})
	var rz: Dictionary = man.get("raised", {})
	if sc.is_empty() and rz.is_empty():
		return null
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL_PX, CELL_PX)
	if not sc.is_empty():
		var src := TileSetAtlasSource.new()
		src.texture = load(TILES_DIR + String(sc["source"]))
		src.texture_region_size = ts.tile_size
		ts.add_source(src, SRC_SCATTER)
		var per := int(sc["slot"]) / CELL_PX
		for kind in sc["kinds"]:
			for at in sc["kinds"][kind]:
				var coords := _v(at) * per
				src.create_tile(coords, Vector2i(per, per))
				for k in range(1, SCATTER_ALTS):
					var alt := src.create_alternative_tile(coords)
					var td := src.get_tile_data(coords, alt)
					td.flip_h = k % 2 == 1
					td.texture_origin = SCATTER_NUDGE[k / 2]
	var sid := SRC_RAISED
	for name in rz:
		var src := TileSetAtlasSource.new()
		src.texture = load(TILES_DIR + String(rz[name]["source"]))
		src.texture_region_size = ts.tile_size
		ts.add_source(src, sid)
		var made := {}
		for key in rz[name]["tiles"]:
			var at := _v(rz[name]["tiles"][key])
			if not made.has(at):
				src.create_tile(at)
				made[at] = true
		sid += 1
	_save(ts, TILES_DIR + set_name + "_cells.tres")
	return ts


## A water tile's land neighbours as the manifest's shore key (tools/cut_tiles.py
## `shore_mask`): bits l, r, t, b, then the corners tl, tr, bl, br, a corner only when both
## of its sides are water (otherwise a side's bank covers it); 8 binary digits, br first.
static func _shore_key(c: Vector2i, wet: Dictionary) -> String:
	var land := func(dx: int, dy: int) -> int:
		return 0 if wet.has(c + Vector2i(dx, dy)) else 1
	var l: int = land.call(-1, 0)
	var r: int = land.call(1, 0)
	var t: int = land.call(0, -1)
	var b: int = land.call(0, 1)
	var m := l | r << 1 | t << 2 | b << 3
	if land.call(-1, -1) == 1 and t == 0 and l == 0:
		m |= 1 << 4
	if land.call(1, -1) == 1 and t == 0 and r == 0:
		m |= 1 << 5
	if land.call(-1, 1) == 1 and b == 0 and l == 0:
		m |= 1 << 6
	if land.call(1, 1) == 1 and b == 0 and r == 0:
		m |= 1 << 7
	return String.num_int64(m, 2).lpad(8, "0")


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


## A wall run over the rect `r` (cells), drawn as sprites (manifest "walls"): one per tile,
## standing on the tile's bottom middle and taller than it, in a y-sorted node so the near
## ones overlap the far ones and the run reads as one barrier. A column takes the "top" and
## "bottom" roles at its ends and "vmid" between them, a row "left" and "right" (a missing
## role falls back to "mid"). A tile the rect only half covers (a run ending on an odd cell)
## stands on the rect's own last row, so the wall's face ends where its cells do.
## `rubble_only`: just the rubble (a raised wall draws the wall itself as tiles, RaisedTiles).
## Each tile also gets its rubble sprite, hidden; both record the cells under them (`meta
## "cells"`), and the rubble is marked `meta "broken"`, so ArenaView shows the wall while
## those cells are the map's wall and the rubble while any is smashed.
static func _wall_run(walls: Node2D, rubble: Node2D, root: Node, man: Dictionary, name: String, r: Array, per: int, tile: int, cache: Dictionary, rubble_only := false) -> void:
	var w: Dictionary = man.get("walls", {}).get(name, {})
	if w.is_empty():
		push_warning("no wall " + name)
		return
	if not cache.has(name):
		cache[name] = load(TILES_DIR + String(w["source"]))
	var tex: Texture2D = cache[name]
	var roles: Dictionary = w["roles"]
	var tiles := _tiles_of(r, per)
	var vertical := int(r[3]) > int(r[2])
	var first: Vector2i = tiles[0]
	var last: Vector2i = tiles[tiles.size() - 1]
	for c in tiles:
		var role := "vmid" if vertical else "mid"
		if tiles.size() > 1:
			if c == first:
				role = "top" if vertical else "left"
			elif c == last:
				role = "bottom" if vertical else "right"
		var pool: Array = roles.get(role, roles["mid"])
		var cells := Rect2i(c * per, Vector2i(per, per)).intersection(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
		var foot := Vector2((c.x + 0.5) * tile, cells.end.y * (tile / per) - 2)
		var picks := [] if rubble_only else [[walls, pool[_h(c.x, c.y, 2) % pool.size()], false]]
		var rub: Array = roles.get("rubble", [])
		if not rub.is_empty():
			picks.append([rubble, rub[_h(c.x, c.y, 3) % rub.size()], true])
		for pick in picks:
			var parent: Node2D = pick[0]
			var sp: Dictionary = pick[1]
			var at := AtlasTexture.new()
			at.atlas = tex
			var reg: Array = sp["region"]
			at.region = Rect2(int(reg[0]), int(reg[1]), int(reg[2]), int(reg[3]))
			var s := Sprite2D.new()
			s.name = "%s_%d" % [name, parent.get_child_count()]
			s.texture = at
			s.centered = false
			s.position = foot
			s.offset = -Vector2(float(sp["feet"][0]), float(sp["feet"][1]))  # y-sorted by its foot
			s.set_meta("cells", cells)
			if pick[2]:
				s.set_meta("broken", true)
				s.visible = false
			parent.add_child(s)
			s.owner = root


## Places a decor or anim sprite (`s`, not centred) with its feet at `spot` (scene px) and
## returns the group it belongs in: `group` (Decor, Anim) as before, or, when its feet stand
## on one of the map's wall rects (`walls_r`, cells of `cell_px`), the y-sorted Walls run,
## positioned by its foot like the pillars (so a brazier at a run's near end stands in front
## of it) with meta "cells" the wall cells its box covers: ArenaView hides it while any of
## them is smashed, as it hides the pillars (a sign never floats over rubble).


## The water's shoulder (manifest shores.water.shoulder): on every land tile round the water
## tiles `wet` (its eight neighbours), inside the map and on floor only, the shoulder tile for
## which of its neighbours are water (keyed like the banks: l, r, t, b, then a corner only
## when neither of its sides is water), on a "Shoulder" layer under the water.
static func _shoulder(root: Node2D, shore_ts: TileSet, shores: Dictionary, wet: Array[Vector2i], grid: TerrainGrid, per: int) -> void:
	var keys: Dictionary = shores.get("water", {}).get("shoulder", {})
	if shore_ts == null or keys.is_empty() or wet.is_empty():
		push_warning("tiles.shoulder: the set's water bank has no shoulder")
		return
	var src_id := shores.keys().find("water")
	var wet_set := {}
	for c in wet:
		wet_set[c] = true
	var layer := _layer(root, "Shoulder", shore_ts)
	for c in wet:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := c + Vector2i(dx, dy)
				if wet_set.has(n) or layer.get_cell_source_id(n) >= 0:
					continue
				if n.x < 0 or n.y < 0 or n.x * per >= grid.cols or n.y * per >= grid.rows or not _floor_tile(grid, n, per):
					continue
				var w := func(ox: int, oy: int) -> int:
					return 1 if wet_set.has(n + Vector2i(ox, oy)) else 0
				var l: int = w.call(-1, 0)
				var r: int = w.call(1, 0)
				var t: int = w.call(0, -1)
				var b: int = w.call(0, 1)
				var m := l | r << 1 | t << 2 | b << 3
				if w.call(-1, -1) == 1 and t == 0 and l == 0:
					m |= 1 << 4
				if w.call(1, -1) == 1 and t == 0 and r == 0:
					m |= 1 << 5
				if w.call(-1, 1) == 1 and b == 0 and l == 0:
					m |= 1 << 6
				if w.call(1, 1) == 1 and b == 0 and r == 0:
					m |= 1 << 7
				var key := String.num_int64(m, 2).lpad(8, "0")
				if keys.has(key):
					layer.set_cell(n, src_id, _v(keys[key]))


## Whether every cell of tile `t` is plain floor in the map (or its water).
static func _floor_tile(grid: TerrainGrid, t: Vector2i, per: int) -> bool:
	for dy in per:
		for dx in per:
			var c := t * per + Vector2i(dx, dy)
			if not grid.in_bounds(c):
				continue
			var v := grid.get_base(c)
			if v != TerrainGrid.INTACT and v != TerrainGrid.SHALLOWS:
				return false
	return true


## The map's walls as raised plateaus (manifest raised.<name>): a "RaisedShadow" and a
## "Raised" 16 px layer painted by RaisedTiles with every wall cell whole, each carrying meta
## "raised" (the source, the tile keys, the face's cells, the light's side) for ArenaView,
## which repaints them as walls are smashed and rebuilt.
static func _raised(root: Node2D, small: TileSet, man: Dictionary, map: Dictionary, name: String, grid: TerrainGrid) -> void:
	var all: Dictionary = man.get("raised", {})
	if small == null or not all.has(name):
		push_warning("no raised wall " + name)
		return
	var rz: Dictionary = all[name]
	var info := {"source": SRC_RAISED + all.keys().find(name), "tiles": rz["tiles"], "cells": int(rz["cells"]),
		"variants": int(rz.get("variants", 1)), "mirror": (ShadowLayer.light_of(map)["cast"] as Vector2).x < 0.0}
	var shadow := _layer(root, "RaisedShadow", small)
	var raised := _layer(root, "Raised", small)
	shadow.set_meta("raised", info)
	raised.set_meta("raised", info)
	var walls := wall_cells(grid)
	RaisedTiles.paint(raised, shadow, info, walls, func(c: Vector2i) -> bool: return walls.has(c), -1, grid.rows + 1)


## The map's own wall cells (Vector2i -> true).
static func wall_cells(grid: TerrainGrid) -> Dictionary:
	var walls := {}
	for cy in grid.rows:
		for cx in grid.cols:
			if grid.map_base[cy * grid.cols + cx] == TerrainGrid.WALL:
				walls[Vector2i(cx, cy)] = true
	return walls


## The map's `scatter`: [{kind, density, where, near, seed}] small sprites (manifest
## "scatter" kinds) on the "Scatter" layer, one a cell at most, picked by a fixed hash so a
## rebuild lays the same ones. `where`: "floor" (anywhere), "near_walls" / "near_water" /
## "near_fences" / "near_brush" (within `near` cells of a wall / the water / a fence / a brush
## bed, default 3), "verge" (within `near` cells of the tiles block's `of` rects, a terrain
## such as "earth", but never on them: a road's edges, not its middle), or [[tx, ty, w, h], ...]
## tile rects.
## Only on plain floor (`scatter_ok`), off the map's cleared cells (`scatter_clear`, flag bases,
## shrines) and never within TRACK_CLEAR units of the map's `track` (the caravan's path: its
## diagonals cut the corners of a stepped road).
static func _scatter(layer: TileMapLayer, tiles: Dictionary, man: Dictionary, grid: TerrainGrid, wet_tiles: Dictionary, per: int, map: Dictionary = {}) -> void:
	var track: Array = map.get("track", [])
	var kinds: Dictionary = man.get("scatter", {}).get("kinds", {})
	var slot := int(man.get("scatter", {}).get("slot", 32)) / CELL_PX
	var used := scatter_clear(tiles, map, grid)
	for e in tiles.get("scatter", []):
		var pool: Array = kinds.get(String(e.get("kind", "")), [])
		if pool.is_empty():
			push_warning("no scatter " + String(e.get("kind", "")))
			continue
		var seed := int(e.get("seed", 1))
		var density := int(float(e.get("density", 0.05)) * 1000.0)
		var where = e.get("where", "floor")
		var near := int(e.get("near", 3))
		var band := {}  # "verge": the cells of the `of` rects
		if String(where) == "verge":
			for r in tiles.get(String(e.get("of", "")), []):
				for cy in range(int(r[1]) * per, (int(r[1]) + int(r[3])) * per):
					for cx in range(int(r[0]) * per, (int(r[0]) + int(r[2])) * per):
						band[Vector2i(cx, cy)] = true
		for cy in grid.rows:
			for cx in grid.cols:
				var c := Vector2i(cx, cy)
				if used.has(c) or _h(cx, cy, 200 + seed) % 1000 >= density:
					continue
				if not scatter_ok(c, grid, wet_tiles, per, bool(tiles.get("markings", false))):
					continue
				if near_track(grid.cell_center(c), track):
					continue
				if where is Array:
					var inside := false
					for r in where:
						if Rect2i(int(r[0]) * per, int(r[1]) * per, int(r[2]) * per, int(r[3]) * per).has_point(c):
							inside = true
					if not inside:
						continue
				elif String(where) == "verge":
					if band.has(c) or not _near_band(c, band, near):
						continue
				elif String(where) != "floor" and not _near(c, grid, wet_tiles, per, near, String(where)):
					continue
				used[c] = true
				var at: Array = pool[_h(cx, cy, 201 + seed) % pool.size()]
				layer.set_cell(c, SRC_SCATTER, _v(at) * slot, _h(cx, cy, 202 + seed) % SCATTER_ALTS)


## The cells no scatter lies on besides `scatter_ok`'s (cell -> true): the tiles block's
## `scatter_clear` cell rects (a keep's gates), every flag base's capture zone (within
## SCATTER_BASE_CLEAR units of the map's `bases`) and every shrine's circle (its radius and
## a cell), so nothing small sits on a marked spot or in a doorway.
static func scatter_clear(tiles: Dictionary, map: Dictionary, grid: TerrainGrid) -> Dictionary:
	var out := {}
	for r in tiles.get("scatter_clear", []):
		for cy in range(int(r[1]), int(r[1]) + int(r[3])):
			for cx in range(int(r[0]), int(r[0]) + int(r[2])):
				out[Vector2i(cx, cy)] = true
	var spots: Array = []  # [centre in world units, radius]
	for side in map.get("bases", {}):
		var b: Array = map["bases"][side]
		spots.append([Vector2(float(b[0]), float(b[1])), SCATTER_BASE_CLEAR])
	for sh in map.get("shrines", []):
		var sp: Array = sh.get("pos", [0, 0])
		spots.append([Vector2(float(sp[0]), float(sp[1])), float(sh.get("radius", 20)) + SimDefs.CELL])
	for cy in grid.rows:
		for cx in grid.cols:
			var p := grid.cell_center(Vector2i(cx, cy))  # world units, as the map's bases and shrines
			for spot in spots:
				if p.distance_to(spot[0]) < float(spot[1]):
					out[Vector2i(cx, cy)] = true
	return out


## Whether a scatter sprite may lie on cell `c`: plain floor, off the water tiles, clear of
## brush by a cell, and (on a map with court markings) clear of the lines by about a cell.
static func scatter_ok(c: Vector2i, grid: TerrainGrid, wet_tiles: Dictionary, per: int, markings: bool) -> bool:
	if not grid.in_bounds(c) or grid.get_base(c) != TerrainGrid.INTACT:
		return false
	if wet_tiles.has(Vector2i(floori(float(c.x) / per), floori(float(c.y) / per))):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if grid.in_bounds(n) and grid.get_base(n) == TerrainGrid.BRUSH:
				return false
	return not (markings and near_marks(c, grid))


## Within `near` cells of a wall ("near_walls"), of the water ("near_water": the shallows,
## the water tiles), of a fence ("near_fences") or of a brush bed ("near_brush").
static func _near(c: Vector2i, grid: TerrainGrid, wet_tiles: Dictionary, per: int, near: int, where: String) -> bool:
	var want := {"near_walls": TerrainGrid.WALL, "near_fences": TerrainGrid.FENCE, "near_brush": TerrainGrid.BRUSH}
	for dy in range(-near, near + 1):
		for dx in range(-near, near + 1):
			var n := c + Vector2i(dx, dy)
			if not grid.in_bounds(n):
				continue
			var v := grid.get_base(n)
			if where == "near_water":
				if v == TerrainGrid.SHALLOWS or wet_tiles.has(Vector2i(floori(float(n.x) / per), floori(float(n.y) / per))):
					return true
			elif want.has(where) and v == int(want[where]):
				return true
	return false


## Whether a point (world units) lies within TRACK_CLEAR of the polyline `track` ([[x, y], ...]).
static func near_track(p: Vector2, track: Array) -> bool:
	for i in track.size() - 1:
		var a := Vector2(float(track[i][0]), float(track[i][1]))
		var b := Vector2(float(track[i + 1][0]), float(track[i + 1][1]))
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= TRACK_CLEAR:
			return true
	return false


## Within `near` cells of a cell of `band` (Vector2i -> true).
static func _near_band(c: Vector2i, band: Dictionary, near: int) -> bool:
	for dy in range(-near, near + 1):
		for dx in range(-near, near + 1):
			if band.has(c + Vector2i(dx, dy)):
				return true
	return false


## Whether cell `c` lies within about a cell of the Stadium's court markings (ArenaView
## `_paint_marks`: the boundary 6 units inside the floor, the centre line, the double centre
## circle of radius 34, the starting brackets 100 units either side of the centre).
static func near_marks(c: Vector2i, grid: TerrainGrid) -> bool:
	var p := grid.cell_center(c)
	var fr := grid.floor_rect()
	var box := fr.grow(-6)
	var m := float(SimDefs.CELL) * 1.5
	var mid := fr.get_center()
	if absf(p.x - box.position.x) < m or absf(p.x - box.end.x) < m or absf(p.y - box.position.y) < m or absf(p.y - box.end.y) < m:
		return true
	if absf(p.x - mid.x) < m or p.distance_to(mid) < 34.0 + m:
		return true
	for side in [-1.0, 1.0]:
		if p.distance_to(mid + Vector2(side * 100.0, 4.0)) < 12.0 + m:
			return true
	return false


## Where a decor or anim entry stands, in scene pixels (2 a unit): a tile's bottom middle
## (`at`) or a point in units from the floor's top-left corner (`pos`).
static func _spot(e: Dictionary, tile: int) -> Vector2:
	if e.has("pos"):
		return Vector2(float(e["pos"][0]), float(e["pos"][1])) * ArtScale.PX_PER_UNIT
	var at := _v(e["at"])
	return Vector2((at.x + 0.5) * tile, (at.y + 1) * tile)


## Puts a decor or anim sprite at its spot, feet first. One whose feet stand on a wall cell,
## or with `"wall": true` (a banner hung on a wall), joins the y-sorted "Walls" at the wall's
## foot line (its `pos` y), drawn over the wall sprite it stands on, and records the wall cells
## under it (meta "cells"), so ArenaView hides it with the wall when they are smashed.
## `lift` (units) draws it that much higher than its spot, on the wall's top (a brazier on a
## post), still sorted and hidden by the spot.
## On a raised wall (`raised`: {"walls": the map's wall cells, "k": the face's most cells}) a
## piece whose feet fall on the face (a run's south end, where a wall-sprite run's near end
## stood) stands on the top instead, RAISED_INSET px in from the face (`raised_spot`), and its
## cells run on down its column to the run's end: smashing the face under it drops it too,
## or it would hang on the face the wall grows over the gap.
static func _place(s: Node2D, e: Dictionary, d: Dictionary, size: Vector2, tile: int, per: int, group: Node2D, walls: Node2D, walls_r: Array[Rect2i], root: Node, raised := {}) -> void:
	var feet := Vector2(float(d["feet"][0]), float(d["feet"][1]))
	var cell_px := float(tile) / per
	var spot := raised_spot(_spot(e, tile), cell_px, raised)
	var foot := Vector2i(floori(spot.x / cell_px), floori((spot.y - 1.0) / cell_px))
	var on: Rect2i = Rect2i(foot, Vector2i.ONE) if bool(e.get("wall", false)) else Rect2i()
	for r in walls_r:
		if r.has_point(foot):
			var top_left := spot - feet
			var box := Rect2i(floori(top_left.x / cell_px), floori(top_left.y / cell_px),
				ceili((top_left.x + size.x) / cell_px) - floori(top_left.x / cell_px),
				foot.y + 1 - floori(top_left.y / cell_px))
			on = box.intersection(r)
			if on.size == Vector2i.ZERO:
				on = Rect2i(foot, Vector2i.ONE)
			if not raised.is_empty():
				on.end = Vector2i(on.end.x, r.end.y)
			break
	var parent := walls if on.size != Vector2i.ZERO else group
	s.name = "%s_%d" % [String(e["kind"]), parent.get_child_count()]
	if parent == walls:
		s.position = spot
		s.set("offset", -feet - Vector2(0.0, float(e.get("lift", 0.0)) * ArtScale.PX_PER_UNIT))
		s.set_meta("cells", on)
	else:
		s.position = spot - feet
	parent.add_child(s)
	s.owner = root


## A spot (scene px) moved off a raised wall's face onto its top: when the cell under it is a
## face cell (RaisedTiles: a column's last cells), up to RAISED_INSET px above the top's last
## row's south edge, in the same column. Any other spot is returned as it is.
static func raised_spot(spot: Vector2, cell_px: float, raised: Dictionary) -> Vector2:
	if raised.is_empty():
		return spot
	var walls: Dictionary = raised["walls"]
	var up := func(c: Vector2i) -> bool: return walls.has(c)
	var c := Vector2i(floori(spot.x / cell_px), floori((spot.y - 1.0) / cell_px))
	if RaisedTiles._face_row(c, up, int(raised["k"])).x == 0:
		return spot
	while walls.has(c) and RaisedTiles._face_row(c, up, int(raised["k"])).x > 0:
		c.y -= 1
	if not walls.has(c):
		return spot  # all face: a column too short for a top
	return Vector2(spot.x, (c.y + 1) * cell_px - RAISED_INSET)


## One map's ground scene: the fill under everything (a tile past the floor all round, an
## `edge` fill for that ring), the terrains, the pieces, the decor and the animated pieces.
static func _build_scene(map: Dictionary, tiles: Dictionary, man: Dictionary, ts: TileSet, shore_ts: TileSet, small: TileSet) -> void:
	var g: Dictionary = man["ground"]
	var p: Dictionary = man["pieces"]
	var tile := int(ts.tile_size.x)
	var per := tile / (int(SimDefs.CELL) * ArtScale.PX_PER_UNIT)  # cells a tile covers (2)
	var size := ArenaMap.size_of(map)
	var cols := ceili(float(size.x) / per)
	var rows := ceili(float(size.y) / per)
	var root := Node2D.new()
	root.name = "Ground"
	var grid := TerrainGrid.new(size.x, size.y)  # the map's cells as the sim lays them
	grid.load_map(map)

	var ground := _layer(root, "Ground", ts)
	var fill: Array = g["fills"][String(tiles.get("ground", "dirt"))]
	var ringed := tiles.has("edge")  # the stands' hoardings sit right past the floor: no ring by default
	var edge: Array = g["fills"][String(tiles.get("edge", tiles.get("ground", "dirt")))]
	var pad := 1 if ringed else 0
	for ty in range(-pad, rows + pad):
		for tx in range(-pad, cols + pad):
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
	var wet_tiles := {}  ## the tiles painted with water (a causeway's ends look at them)
	var names := ["grass", "water"]  # always there (tests look for the layers), then the set's own
	for i in ts.get_terrains_count(0):
		if not ts.get_terrain_name(0, i) in names:
			names.append(ts.get_terrain_name(0, i))
	for name in names:
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
		if name == "water" and bool(tiles.get("shoulder", false)):
			_shoulder(root, shore_ts, g.get("shores", {}), cells, grid, per)
		var layer := _layer(root, name.capitalize(), ts)
		counts[name] = _terrain(layer, ts, name, cells)
		if name == "water":
			for c in cells:
				wet_tiles[c] = true
		# the terrain's animated surfaces, if the set has any, each on its own layer over it
		# (the first "<Terrain>Surface", the next "<Terrain>Surface<Name>": Floodgate's glints);
		# a surface cut in variant rows picks a row per tile
		if not cells.is_empty():
			for pair in _surface_sources(man, name):
				var layer_name: String = String(name).capitalize() + "Surface"
				if root.has_node(layer_name):
					layer_name += String(pair[1]).capitalize()
				var surface := _layer(root, layer_name, ts)
				var variants := int(g["surfaces"][pair[1]].get("variants", 1))
				for c in cells:
					surface.set_cell(c, int(pair[0]), Vector2i(0, _h(c.x, c.y, 5) % variants))
		# its bank, over the water and its surface, on every tile with land round it
		var shores: Dictionary = g.get("shores", {})
		if shore_ts != null and shores.has(name) and not cells.is_empty():
			var bank := _layer(root, name.capitalize() + "Bank", shore_ts)
			var wet := {}
			for c in cells:
				wet[c] = true
			var keys: Dictionary = shores[name]["tiles"]
			var src_id := shores.keys().find(name)
			for c in cells:
				var key := _shore_key(c, wet)
				if keys.has(key):
					bank.set_cell(c, src_id, _v(keys[key]))

	var pieces := _layer(root, "Pieces", ts)
	var styles: Dictionary = DEFAULT_STYLES.duplicate()
	styles.merge(tiles.get("styles", {}), true)
	# small sprites over the floor (`scatter`), then a raised wall's contact shadow and the
	# wall itself (`styles.wall: "raised:<name>"`): 16 px layers, one tile a cell
	if small != null and tiles.has("scatter"):
		_scatter(_layer(root, "Scatter", small), tiles, man, grid, wet_tiles, per, map)
	var wall_style := String(styles.get("wall", ""))
	if wall_style.begins_with("raised:"):
		_raised(root, small, man, map, wall_style.trim_prefix("raised:"), grid)
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
	# walls drawn as runs of tall sprites (`styles.wall: "wall:<name>"`), y-sorted, with the
	# rubble each tile shows once smashed under them; ArenaView swaps them (`_sync_sprites`)
	var rubble := Node2D.new()
	rubble.name = "Rubble"
	root.add_child(rubble)
	rubble.owner = root
	var walls := Node2D.new()
	walls.name = "Walls"
	walls.y_sort_enabled = true
	root.add_child(walls)
	walls.owner = root
	var wall_tex := {}
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
		if style.begins_with("wall:"):
			_wall_run(walls, rubble, root, man, style.trim_prefix("wall:"), r, per, tile, wall_tex)
			continue
		if style.begins_with("raised:"):
			# the wall is RaisedTiles' layers; its rubble the named walls.<name>'s heaps
			var rub := String(man.get("raised", {}).get(style.trim_prefix("raised:"), {}).get("rubble", ""))
			if rub != "":
				_wall_run(walls, rubble, root, man, rub, r, per, tile, wall_tex, true)
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
		var rect_tiles := _tiles_of(r, per)
		for c in rect_tiles:
			var pick: Array = alt if not alt.is_empty() and _h(c.x, c.y, 1) % 3 == 0 else pool
			# a rect's end rows with water beyond (a causeway's ends): the kind's _t / _b tiles,
			# a lit lip upstream and the causeway's face down to the water downstream
			if p.has(style + "_t") and not (c + Vector2i.UP) in rect_tiles and wet_tiles.has(c + Vector2i.UP):
				pick = p[style + "_t"]
			elif p.has(style + "_b") and not (c + Vector2i.DOWN) in rect_tiles and wet_tiles.has(c + Vector2i.DOWN):
				pick = p[style + "_b"]
			pieces.set_cell(c, SRC_PIECES, _v(pick[_h(c.x, c.y, 2) % pick.size()]))
	for name in fence_cells:
		_fence_lines(pieces, man, String(name), fence_cells[name], per)

	# the map's wall rects (cells): a decor or anim piece standing on one joins the wall run
	# (`_place`), y-sorted among its sprites and gone while the wall under it is smashed
	var wall_rects: Array[Rect2i] = []
	for piece in placed:
		var r: Array = piece.get("rect", [])
		if String(piece.get("kind", "")) == "wall" and r.size() == 4:
			wall_rects.append(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
	var raised_ctx := {}  # a raised wall's cells and face height: pieces on it stand on its top
	if wall_style.begins_with("raised:"):
		var rz: Dictionary = man.get("raised", {}).get(wall_style.trim_prefix("raised:"), {})
		if not rz.is_empty():
			raised_ctx = {"walls": wall_cells(grid), "k": int(rz["cells"])}
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
		s.texture = load(TILES_DIR + String(d["source"]))
		s.centered = false
		_place(s, e, d, Vector2(d["size"][0], d["size"][1]), tile, per, decor, walls, wall_rects, root, raised_ctx)

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
		s.sprite_frames = frames
		s.centered = false
		s.autoplay = "default"
		_place(s, e, a, Vector2(fw, fh), tile, per, anim, walls, wall_rects, root, raised_ctx)

	var packed := PackedScene.new()
	packed.pack(root)
	var path := ARENAS_DIR + String(map["id"]) + ".tscn"
	if brush.get_child_count() > 0:
		print("  bush clumps: ", brush.get_child_count())
	if walls.get_child_count() > 0:
		print("  wall sprites: ", walls.get_child_count())
	DirAccess.make_dir_recursive_absolute(ARENAS_DIR)
	var err := ResourceSaver.save(packed, path)
	if err != OK:
		push_error("could not save %s: %d" % [path, err])
	print("wrote ", path, ": ", cols, "x", rows, " tiles, terrains ", counts,
		", pieces ", pieces.get_used_cells().size(), ", decor ", decor.get_child_count(), ", anim ", anim.get_child_count())
	root.free()
