class_name ArenaView
extends Node2D
## Draws the stadium: stands, walls, and the breakable floor from the terrain grid.
## Redraws only the rows whose cells changed (BAND_ROWS).
## A map with its own art (assets/sprites/arena_<id>.png, tools/gen_arenas.py) draws that
## picture as the whole backdrop (stands, walls, floor, court lines, and the map's pieces
## as it starts). A cell whose piece has changed shows its piece of arena_<id>_alt.png
## (a smashed wall's rubble, flattened brush). A cracked cell shows
## its piece of arena_<id>_cracked.png (the same floor broken by one network of cracks, so
## a cracked patch joins up); pieces and pits are drawn on top as usual, each pit with a
## broken lip of floor where it meets solid ground.
## A hole in a map's bridge ("bridges"), or the bridge fallen in (its cells shallows),
## shows the river under it from the _alt picture, rather than a pit or the planks.
## A map without one is drawn from the tiles below.
## The art has the pieces' shadows cast along the map's light ("light", ShadowLayer.light_of).
## A piece that changes (a wall smashed, brush flattened, a bridge fallen) takes its shadow
## with it: a floor cell in the shadow of changing pieces shows the _alt picture (which has
## none of their shadows) once every piece shading it has changed (`_shade`).

const TILES := preload("res://assets/sprites/tiles.png")
const TILE_HOLE := 8
const TILE_HOLE_DEEP := 9
## Arena map pieces (tools/gen_sprites.py tiles_sheet).
const TILE_WALL_TOP := 10  # two variants
const TILE_WALL_FACE := 12
const TILE_FENCE := 13
const TILE_CHASM_RIM := 14
const TILE_CHASM := 15
const TILE_SHALLOWS := 16  # two variants
const TILE_BRUSH := 18  # two variants
const TILE_BRUSH_FLAT := 20
const TILE_RUBBLE_FLOOR := 21
## How each map's ground tints the dirt tiles (the map's "ground" key).
const GROUND_TINT := {
	"dirt": Color(1.0, 1.0, 1.0),
	"stone": Color(0.86, 0.86, 0.9),
	"concrete": Color(0.78, 0.82, 0.88),
	"grass": Color(0.84, 0.98, 0.72),
}
var ground := "dirt":
	set(v):
		if v != ground:
			ground = v
			_rebuild()

const C_BG := Color("1b1e26")
const C_STAND_A := Color("3a3f4e")
const C_STAND_B := Color("323645")
const C_RAIL := Color("23262f")
const C_WALL := Color("5d6470")
const C_WALL_TOP := Color("8a909a")
const C_WALL_DARK := Color("464c58")
const C_LINE := Color(1, 1, 1, 0.2)
## Over a cracked cell on a map with art but no cracked picture: a shade darker.
const C_CRACKED_SHADE := Color(0.18, 0.09, 0.04, 0.16)
## Pit edges on a map with art (_paint_lips).
const C_LIP_SHADOW := Color(0.0, 0.0, 0.0, 0.55)
const C_LIP_LIT := Color(0.95, 0.78, 0.55, 0.55)
const C_LIP_SIDE := Color(0.25, 0.14, 0.08, 0.6)
## How far the stadium carries on past its walls, for when the camera pulls back and for
## wider (ultrawide) and taller (16:10) screens: they see more stands and wall.
const MARGIN := Vector2(400, 80)

var terrain: TerrainGrid
var _drawn_version := -1
## The map's id (its arena JSON "id"): picks its art, if it has any.
var arena_id := "":
	set(v):
		if v != arena_id:
			arena_id = v
			var path := "res://assets/sprites/arena_%s.png" % v
			_art = load(path) if v != "" and ResourceLoader.exists(path) else null
			var cpath := "res://assets/sprites/arena_%s_cracked.png" % v
			_art_cracked = load(cpath) if _art != null and ResourceLoader.exists(cpath) else null
			var apath := "res://assets/sprites/arena_%s_alt.png" % v
			_art_alt = load(apath) if _art != null and ResourceLoader.exists(apath) else null
			_bridges = ArenaMap.bridge_rects(ArenaMap.get_map(v)) if v != "" else []
			_rebuild()
var _art: Texture2D = null
var _art_cracked: Texture2D = null
## The floor with its pieces changed (a smashed wall's rubble, flattened brush), if any.
var _art_alt: Texture2D = null
## The map's bridges (cells), whose holes show the water in the _alt picture.
var _bridges: Array[Rect2i] = []
## How tall (px) the pieces that change are, as tools/gen_arenas.py casts their shadows
## (keep in step with CAST_HEIGHT there; taller only widens `_shade`, never wrong).
const CAST_HEIGHT := {TerrainGrid.WALL: 12.0, TerrainGrid.BRUSH: 6.0}
const BRIDGE_HEIGHT := 3.0
## Floor cell -> the cells of changing pieces whose shadow (in the art) falls on it.
var _shade := {}
## Row -> its cells in `_shade`.
var _shade_rows := {}
## How many rows a piece's shadow reaches above (x) and below (y) it.
var _shade_reach := Vector2i.ZERO


## A hole in a bridge or a fallen bridge, on a map whose _alt picture shows the water under it.
func _bridge_gone(cx: int, cy: int) -> bool:
	if _art_alt == null:
		return false
	for r in _bridges:
		if r.has_point(Vector2i(cx, cy)):
			var v := terrain.cells[cy * terrain.cols + cx]
			return v == TerrainGrid.HOLE or v == TerrainGrid.SHALLOWS
	return false


func set_terrain(t: TerrainGrid) -> void:
	terrain = t
	_rebuild()


## The floor and the pits are drawn in bands of BAND_ROWS rows, each its own canvas item,
## so a cell that cracks, heals or breaks redraws only its band (and its neighbours',
## since a wall's face and a pit's rim look at the cells round them), not the whole map:
## a big map's full redraw costs a few milliseconds, a band's a fraction of one. Bands are
## full rows, drawn top to bottom, so everything overlaps exactly as one big drawing would.
const BAND_ROWS := 4


## One band of rows: `paint` draws rows row0..row1-1 onto it.
class Band extends Node2D:
	var paint: Callable
	var row0 := 0
	var row1 := 0

	func _draw() -> void:
		var t0 := PerfLog.now()
		paint.call(self, row0, row1)
		PerfLog.since("arena draw", t0)


var _floor_bands: Array[Band] = []
var _pit_bands: Array[Band] = []
var _marks: Band = null
## The cells as the bands last drew them, to find the rows that changed.
var _seen := PackedByteArray()
## Bands waiting to be repainted. A change to the floor can dirty many at once (a slam's
## ring, a Sinkhole collapse) and each costs a fraction of a millisecond, so they're
## repainted a few per frame (`_process`) over at most SPREAD_FRAMES frames instead of
## all in the tick that changed them, which read as a hitch at high frame rates.
var _pending: Array[int] = []
const SPREAD_FRAMES := 4


## Starts the drawing over: a new terrain, map art or ground.
func _rebuild() -> void:
	queue_redraw()
	for b in _floor_bands + _pit_bands:
		b.queue_free()
	if _marks != null:
		_marks.queue_free()
	_floor_bands.clear()
	_pit_bands.clear()
	_pending.clear()
	_marks = null
	if terrain == null:
		return
	var bands := ceili(terrain.rows / float(BAND_ROWS))
	for k in bands:
		_floor_bands.append(_band(_paint_floor, k))
	_marks = _band(_paint_marks, 0)
	for k in bands:
		_pit_bands.append(_band(_paint_pit_band, k))
	_seen = terrain.cells.duplicate()
	_drawn_version = terrain.version
	_build_shade()


## Which floor cells lie in the shadow of pieces that can change (`_shade`): each such
## piece cell's shadow swept along the light, as the art casts it, with a pixel or two spare.
func _build_shade() -> void:
	_shade.clear()
	_shade_rows.clear()
	_shade_reach = Vector2i.ZERO
	if _art_alt == null or terrain == null:
		return
	var cast: Vector2 = ShadowLayer.light_of(ArenaMap.get_map(arena_id))["cast"]
	var cols := terrain.cols
	var casters := {}
	for i in terrain.map_base.size():
		var b := terrain.map_base[i]
		if CAST_HEIGHT.has(b):
			casters[i] = CAST_HEIGHT[b]
	for r in _bridges:
		for cy in range(r.position.y, r.end.y):
			for cx in range(r.position.x, r.end.x):
				if not casters.has(cy * cols + cx):
					casters[cy * cols + cx] = BRIDGE_HEIGHT
	var cell := float(SimDefs.CELL)
	for i: int in casters:
		var cx := i % cols
		var cy := i / cols
		var px := Rect2(cx * cell, cy * cell, cell, cell)
		var box := px.merge(Rect2(px.position + cast * float(casters[i]), px.size)).grow(2.0)
		var y0 := maxi(0, floori(box.position.y / cell))
		var y1 := mini(terrain.rows - 1, ceili(box.end.y / cell) - 1)
		var x0 := maxi(0, floori(box.position.x / cell))
		var x1 := mini(cols - 1, ceili(box.end.x / cell) - 1)
		_shade_reach = Vector2i(maxi(_shade_reach.x, cy - y0), maxi(_shade_reach.y, y1 - cy))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var p := y * cols + x
				if casters.has(p):
					continue
				if not _shade.has(p):
					_shade[p] = []
					if not _shade_rows.has(y):
						_shade_rows[y] = []
					_shade_rows[y].append(p)
				_shade[p].append(i)


## Whether a changing piece's cell has changed (its shadow gone with it).
func _piece_gone(i: int) -> bool:
	var b := terrain.map_base[i]
	if CAST_HEIGHT.has(b):
		return terrain.cells[i] != b
	return _bridge_gone(i % terrain.cols, i / terrain.cols)


## Floor cell `p` (in `_shade`) as the map made it, with every piece shading it changed: its
## piece of the _alt picture, which has the floor without their shadows.
func _unshaded(p: int) -> bool:
	if terrain.cells[p] != terrain.map_base[p]:
		return false
	for i: int in _shade[p]:
		if not _piece_gone(i):
			return false
	return true


func _band(paint: Callable, k: int) -> Band:
	var b := Band.new()
	b.paint = paint
	b.row0 = k * BAND_ROWS
	b.row1 = mini(terrain.rows, b.row0 + BAND_ROWS)
	add_child(b)
	return b


func refresh() -> void:
	if terrain == null or terrain.version == _drawn_version:
		return
	_drawn_version = terrain.version
	if _seen.size() != terrain.cells.size():
		_rebuild()
		return
	var cols := terrain.cols
	var dirty := {}
	for cy in terrain.rows:
		var a := cy * cols
		if terrain.cells.slice(a, a + cols) != _seen.slice(a, a + cols):
			for r in range(maxi(0, cy - 1 - _shade_reach.x), mini(terrain.rows, cy + 2 + _shade_reach.y)):
				dirty[r / BAND_ROWS] = true
	_seen = terrain.cells.duplicate()
	for k in dirty:
		if not (k in _pending):
			_pending.append(k)


## A few of the pending bands each frame (every band paints the floor as it is now, so a
## band that changed again meanwhile is still right).
func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var n := maxi(1, ceili(_pending.size() / float(SPREAD_FRAMES)))
	for i in mini(n, _pending.size()):
		var k: int = _pending.pop_front()
		if k < _floor_bands.size():
			_floor_bands[k].queue_redraw()
			_pit_bands[k].queue_redraw()


## Under the bands: the map's art, or the stands and walls round a tiled floor.
func _draw() -> void:
	if terrain == null:
		return
	if _art != null:
		draw_texture(_art, -MARGIN)
		return
	var fr := terrain.floor_rect()
	var size := terrain.arena_size()
	var x0 := -MARGIN.x
	var w := size.x + MARGIN.x * 2.0
	var y0 := -MARGIN.y
	var h := size.y + MARGIN.y * 2.0

	# Stands behind the crowd (rising out of sight above), then the back wall.
	draw_rect(Rect2(x0, y0, w, h), C_BG)
	for i in range(-6, 4):
		draw_rect(Rect2(x0, i * 14, w, 14), C_STAND_A if posmod(i, 2) == 0 else C_STAND_B)
	draw_rect(Rect2(x0, 47, w, 2), C_RAIL)
	draw_rect(Rect2(x0, fr.position.y - 8, w, 8), C_WALL)
	draw_rect(Rect2(x0, fr.position.y - 8, w, 1), C_WALL_TOP)
	draw_rect(Rect2(x0, fr.position.y - 1, w, 1), C_WALL_DARK)

	# Side and front walls.
	draw_rect(Rect2(x0, fr.position.y, fr.position.x - x0, fr.size.y), C_WALL_DARK)
	draw_rect(Rect2(fr.end.x, fr.position.y, x0 + w - fr.end.x, fr.size.y), C_WALL_DARK)
	draw_rect(Rect2(fr.position.x - 1, fr.position.y, 1, fr.size.y), C_WALL)
	draw_rect(Rect2(fr.end.x, fr.position.y, 1, fr.size.y), C_WALL)
	draw_rect(Rect2(x0, fr.end.y, w, y0 + h - fr.end.y), C_WALL)
	draw_rect(Rect2(x0, fr.end.y, w, 1), C_WALL_TOP)


## A floor band: on a map with art, the cells that differ from it; else the floor tiles
## (intact and cracked cells, then the map's pieces that sit on them).
func _paint_floor(ci: CanvasItem, row0: int, row1: int) -> void:
	if _art != null:
		_paint_changed(ci, row0, row1)
		return
	for cy in range(row0, row1):
		for cx in terrain.cols:
			var v := terrain.cells[cy * terrain.cols + cx]
			if TerrainGrid.is_pit(v):
				continue
			var idx := (cx * 7 + cy * 13 + (cx * cy) % 5) % 4
			var b := terrain.base[cy * terrain.cols + cx]
			match v:
				TerrainGrid.CRACKED:
					idx = TILE_RUBBLE_FLOOR if b == TerrainGrid.WALL else 4 + (cx * 13 + cy * 7 + cx * cy) % 4
				TerrainGrid.WALL:
					# The bottom row of a wall shows its face; the rest its rubble top.
					var below := terrain.cells[(cy + 1) * terrain.cols + cx] if cy + 1 < terrain.rows else TerrainGrid.INTACT
					idx = TILE_WALL_FACE if below != TerrainGrid.WALL else TILE_WALL_TOP + (cx + cy) % 2
				TerrainGrid.SHALLOWS:
					idx = TILE_SHALLOWS + (cx * 3 + cy * 5) % 2
			var plain := v == TerrainGrid.INTACT or v == TerrainGrid.CRACKED or v == TerrainGrid.BRUSH \
				or v == TerrainGrid.BRUSH_FLAT or v == TerrainGrid.FENCE
			ci.draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(idx * 8, 0, 8, 8),
				GROUND_TINT.get(ground, Color.WHITE) if plain else Color.WHITE)
			var over := -1
			match v:
				TerrainGrid.FENCE: over = TILE_FENCE
				TerrainGrid.BRUSH: over = TILE_BRUSH + (cx * 5 + cy * 3) % 2
				TerrainGrid.BRUSH_FLAT: over = TILE_BRUSH_FLAT
			if over >= 0:
				ci.draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(over * 8, 0, 8, 8))


## Court markings over a tiled floor (the art has its own), under the pits.
func _paint_marks(ci: CanvasItem, _row0: int, _row1: int) -> void:
	if _art != null:
		return
	var fr := terrain.floor_rect()
	var c := fr.get_center()
	ci.draw_rect(fr.grow(-4), C_LINE, false, 1.0)
	ci.draw_line(Vector2(c.x, fr.position.y + 4), Vector2(c.x, fr.end.y - 4), C_LINE, 1.0)
	ci.draw_arc(c, 34.0, 0.0, TAU, 48, C_LINE, 1.0)


## A pit band: holes and chasms over everything else, so they cut through the markings;
## on a map with art, then the ragged lips where they meet the floor.
func _paint_pit_band(ci: CanvasItem, row0: int, row1: int) -> void:
	_paint_pits(ci, row0, row1)
	if _art != null:
		_paint_lips(ci, row0, row1)


## Whether the art already shows cell `i` as a chasm: only the map's own chasms are in the
## picture. A cell sunk during the match (Sinkhole's rings, the Floor of pits mutator) has
## `base` CHASM too, so it never heals, but it has to be drawn.
func _in_art(i: int) -> bool:
	return _art != null and terrain.map_base[i] == TerrainGrid.CHASM


## A pit whose upper neighbour is solid gets the lit rim tile, which reads as the pit's
## far wall. On a map with art, the map's own chasms are in the picture already.
func _paint_pits(ci: CanvasItem, row0: int, row1: int) -> void:
	for cy in range(row0, row1):
		for cx in terrain.cols:
			var v := terrain.cells[cy * terrain.cols + cx]
			if not TerrainGrid.is_pit(v):
				continue
			if v == TerrainGrid.CHASM and _in_art(cy * terrain.cols + cx):
				continue
			if _bridge_gone(cx, cy):
				continue
			var above_solid := cy == 0 or not TerrainGrid.is_pit(terrain.cells[(cy - 1) * terrain.cols + cx])
			var chasm := v == TerrainGrid.CHASM
			var idx: int
			if above_solid:
				idx = TILE_CHASM_RIM if chasm else TILE_HOLE
			else:
				idx = TILE_CHASM if chasm else TILE_HOLE_DEEP
			ci.draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(idx * 8, 0, 8, 8))


## A map with art: a crack mark on each cracked cell, the map's changed pieces (rubble,
## flattened brush), the river under a broken bridge. Pits come in the pit bands.
func _paint_changed(ci: CanvasItem, row0: int, row1: int) -> void:
	for cy in range(row0, row1):
		var a := cy * terrain.cols
		for p: int in _shade_rows.get(cy, []):  # floor out of the shadow of pieces that changed
			if _unshaded(p):
				ci.draw_texture_rect_region(_art_alt, _cell_rect(p - a, cy),
					Rect2((p - a) * SimDefs.CELL, cy * SimDefs.CELL, SimDefs.CELL, SimDefs.CELL))
		# The art already shows the floor and every piece as the map made it.
		if terrain.cells.slice(a, a + terrain.cols) == terrain.map_base.slice(a, a + terrain.cols):
			continue
		for cx in terrain.cols:
			var v := terrain.cells[a + cx]
			var b := terrain.map_base[a + cx]
			if v == b:
				continue
			var cell := _cell_rect(cx, cy)
			var src := Rect2(cx * SimDefs.CELL, cy * SimDefs.CELL, SimDefs.CELL, SimDefs.CELL)
			if (v == TerrainGrid.HOLE or v == TerrainGrid.SHALLOWS) and _bridge_gone(cx, cy):
				ci.draw_texture_rect_region(_art_alt, cell, src)  # the river under the broken bridge
				continue
			if TerrainGrid.is_pit(v):
				continue
			if v == TerrainGrid.WALL:  # rubble the map didn't put there: a Caravan rockslide
				_draw_rubble(ci, cx, cy)
				continue
			if (v == TerrainGrid.CRACKED and b == TerrainGrid.WALL) or v == TerrainGrid.BRUSH_FLAT:
				# a smashed wall's rubble, flattened brush: the map's changed-piece picture
				if _art_alt != null:
					ci.draw_texture_rect_region(_art_alt, cell, src)
				else:
					var t := TILE_RUBBLE_FLOOR if v == TerrainGrid.CRACKED else TILE_BRUSH_FLAT
					ci.draw_texture_rect_region(TILES, cell, Rect2(t * 8, 0, 8, 8))
			elif v == TerrainGrid.CRACKED:
				if _art_cracked != null:
					ci.draw_texture_rect_region(_art_cracked, cell, src)
				else:
					ci.draw_rect(cell, C_CRACKED_SHADE)


## Rockslide rubble on a map with art: a heap of boulders, the same heap for the same
## cell (no randomness, so a redraw doesn't shuffle it), lit from the top left.
const C_RUBBLE: Array[Color] = [Color("3e3026"), Color("6a5442"), Color("846a52"), Color("a88e70")]


func _draw_rubble(ci: CanvasItem, cx: int, cy: int) -> void:
	var r := _cell_rect(cx, cy)
	ci.draw_rect(Rect2(r.position + Vector2(-1, 1), r.size + Vector2(2, 1)), Color(C_RUBBLE[0], 0.55))
	for k in 3:
		var off := Vector2(posmod(cx * 5 + cy * 3 + k * 7, 6) - 2.5, posmod(cx * 3 + cy * 11 + k * 5, 5) - 2.5)
		var rad := 3.2 + 0.8 * posmod(cx + cy * 2 + k, 3)
		var p := r.get_center() + off
		ci.draw_circle(p + Vector2(0.5, 1.0), rad, C_RUBBLE[0])
		ci.draw_circle(p, rad, C_RUBBLE[1 + posmod(cx + cy + k, 2)])
		ci.draw_circle(p - Vector2(rad, rad) * 0.35, rad * 0.45, C_RUBBLE[3])


## A map with art: where a pit meets solid floor, the floor's edge breaks off ragged (a
## dark undercut on the far side, a lit broken edge on the near side and the sides).
func _paint_lips(ci: CanvasItem, row0: int, row1: int) -> void:
	for cy in range(row0, row1):
		for cx in terrain.cols:
			var i := cy * terrain.cols + cx
			if not TerrainGrid.is_pit(terrain.cells[i]) or _in_art(i) or _bridge_gone(cx, cy):
				continue
			var r := _cell_rect(cx, cy)
			var n := posmod(cx * 7 + cy * 11, 5)
			# far side (above): the floor's lip casting a shadow into the pit
			if cy > 0 and not TerrainGrid.is_pit(terrain.cells[i - terrain.cols]):
				ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), C_LIP_SHADOW)
				ci.draw_rect(Rect2(r.position + Vector2(n, 2), Vector2(3, 1)), C_LIP_SHADOW)
			# near side (below): the broken edge of the floor in front, lit
			if cy + 1 < terrain.rows and not TerrainGrid.is_pit(terrain.cells[i + terrain.cols]):
				ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), C_LIP_LIT)
				ci.draw_rect(Rect2(r.position + Vector2(n, r.size.y - 2), Vector2(2 + n % 2, 1)), C_LIP_LIT)
			for side: int in [-1, 1]:
				var ncx := cx + side
				if ncx < 0 or ncx >= terrain.cols or TerrainGrid.is_pit(terrain.cells[i + side]):
					continue
				var x := r.position.x if side < 0 else r.end.x - 1
				ci.draw_rect(Rect2(x, r.position.y, 1, r.size.y), C_LIP_SIDE)


func _cell_rect(cx: int, cy: int) -> Rect2:
	return Rect2(SimDefs.GRID_X + cx * SimDefs.CELL, SimDefs.GRID_Y + cy * SimDefs.CELL, SimDefs.CELL, SimDefs.CELL)
