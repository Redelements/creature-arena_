class_name WaterView
extends Node2D
## Living water over the shallows (Floodgate's channel, Twin Keeps' pools): a slow flow
## down the map, twinkling highlights, foam that flickers along the banks, and a wake and
## splash around whoever wades in. Cosmetic: reads the sim, never writes it, and draws
## only over `TerrainGrid.SHALLOWS` cells, so a bridge that falls in gets the same water.
##
## Pixel-crisp and cheap: everything is 1 px rects in the picture's own water tones, no
## alpha ramps, no sub-pixel motion, no interpolation. The surface (highlights + foam) is
## one layer that redraws when the flow clock steps (STEP_TICKS, about 6 Hz) or the camera
## leaves the area it drew; the wakes are another layer that redraws each tick, only while
## someone is in water. Both skip what is off screen (`FxView._view_rect`). Main calls
## set_sim() and advance(), and puts this between the floor and the fighters.

const WATER: Array[Color] = [Color8(22, 52, 86), Color8(30, 68, 106), Color8(40, 86, 126),
	Color8(54, 106, 146), Color8(74, 130, 168), Color8(116, 172, 202), Color8(200, 230, 242)]
const STEP_TICKS := 10  ## the flow moves 1 px each time (6 px/s)
const LATTICE := Vector2i(13, 11)  ## highlight spacing; one dash per lattice slot at most
const DRAWN_PAD := 120.0  ## the surface draws this far past the view, redrawing when it leaves
const CULL_PAD := 24.0
const EDGE_DEPTH := 3  ## foam flickers this many px in from a bank (the picture has its own line)
const FOAM_TICKS := 40  ## a foam speck holds this long; each starts at its own phase, so a few change at a time
const RIPPLE_LIFE := 24
const SPLASH_LIFE := 18

var sim: MatchSim
## Main's FxView: no wake for a fighter the local team can't see (a sneaking assassin).
var fx: FxView = null

var _terrain: TerrainGrid
var _version := -1
var _shallows_at := PackedInt32Array()  ## the shallows _scan read (AmbientView.cells_of)
var _water := PackedByteArray()  ## 1 where a cell is shallows
var _cols := 0
var _rows := 0
var _edges: Array = []  ## [x, y, dx, dy, nx, ny]: an 8 px bank segment, its direction and water-side normal
## A tiled map's drawn bank (ArenaView.water_bank): the water is painted a whole tile at a
## time with a bank this many px wide inside it, so the foam runs along the painted edge
## (the cells rounded out to tiles of `_bank_cells`), this far in. 0: the cells' own edges.
var _bank := 0.0
var _bank_cells := 1
var _drawn_wet := PackedByteArray()  ## 1 where the painted water is (the cells, or whole tiles)
var _foam_edges := PackedInt32Array()  ## _scan_foam: each bank segment's corner (x, y)
var _foam := PackedInt32Array()  ## _scan_foam: 7 ints a speck, 8 specks a segment
var _foam_ok := PackedByteArray()  ## _scan_foam: the depths a speck may show at, a bit each
var _surface: Layer
var _wakes: Layer
var _drawn := Rect2()
var _drawn_step := -1
var _last_tick := -1
var _state := {}  ## creature id -> {pos, wet, dir, idle}
var _ripples: Array = []  ## {pos, age, life, r0, grow}
var _drops: Array = []  ## {pos, vx, vy, z, vz, age}
var _rng := RandomNumberGenerator.new()
var _any_water := false
var _bounds := Rect2()  ## the box round all the water
var _wakes_drawn := false
## The brightest highlights the surface drew last (their middles, world px) and a count that
## changes each redraw: BloomView blooms them where the lamps shine.
var glints := PackedVector2Array()
var glint_ver := 0


## A drawing layer: `paint` runs in its _draw.
class Layer extends Node2D:
	var paint: Callable
	var label := ""

	func _draw() -> void:
		var t0 := PerfLog.now()
		paint.call(self)
		PerfLog.since(label, t0)


func _init() -> void:
	_surface = Layer.new()
	_surface.paint = _paint_surface
	_surface.label = "water draw"
	add_child(_surface)
	_wakes = Layer.new()
	_wakes.paint = _paint_wakes
	_wakes.label = "wake draw"
	add_child(_wakes)
	_rng.seed = 4711


## `bank`, `bank_cells`: a tiled map's drawn bank (ArenaView.water_bank), 0 for none.
func set_sim(s: MatchSim, bank := 0.0, bank_cells := 1) -> void:
	sim = s
	_bank = bank
	_bank_cells = maxi(1, bank_cells) if bank > 0.0 else 1
	_terrain = s.terrain
	_version = -1
	_last_tick = -1
	_state.clear()
	_ripples.clear()
	_drops.clear()
	_drawn_step = -1
	_scan()


## One tick (main calls it every physics tick; wakes do nothing until the sim moves on).
func advance() -> void:
	if sim == null or _terrain == null:
		return
	if _terrain.version != _version:
		# A crack or a hole elsewhere leaves the water alone: no rescan, no surface redraw.
		var at := AmbientView.cells_of(_terrain.cells, TerrainGrid.SHALLOWS)
		if at != _shallows_at or _terrain.cols != _cols:
			_shallows_at = at
			_scan()
		_version = _terrain.version
	if not _any_water:
		return
	var view := FxView._view_rect(self, 0.0)
	var step := sim.tick / STEP_TICKS
	if step != _drawn_step or not _drawn.encloses(view):
		_drawn_step = step
		_drawn = view.grow(DRAWN_PAD)
		_surface.queue_redraw()
	if sim.tick == _last_tick:
		return
	_last_tick = sim.tick
	_watch_fighters()
	_age_wakes()
	var busy := not _ripples.is_empty() or not _drops.is_empty() or _wading()
	if busy or _wakes_drawn:
		_wakes.queue_redraw()
	_wakes_drawn = busy


func _wading() -> bool:
	for id in _state:
		if _state[id]["wet"]:
			return true
	return false


## Which cells are water now, and where the banks are (rebuilt when the floor changes).
func _scan() -> void:
	_version = _terrain.version
	_cols = _terrain.cols
	_rows = _terrain.rows
	_water.resize(_cols * _rows)
	_any_water = false
	var first := true
	for i in _cols * _rows:
		var w := 1 if _terrain.cells[i] == TerrainGrid.SHALLOWS else 0
		_water[i] = w
		if w == 1:
			_any_water = true
			var cell := Rect2(SimDefs.GRID_X + (i % _cols) * SimDefs.CELL, SimDefs.GRID_Y + (i / _cols) * SimDefs.CELL, SimDefs.CELL, SimDefs.CELL)
			_bounds = cell if first else _bounds.merge(cell)
			first = false
	_edges.clear()
	if _any_water:
		# the edge the foam runs along: the cells', or on a tiled map the painted water's (a
		# tile is water when any of its cells is), whose bank the foam stays clear of
		var drawn := _water
		if _bank_cells > 1:
			drawn = PackedByteArray()
			drawn.resize(_cols * _rows)
			for i in _cols * _rows:
				if _water[i] == 1:
					var tx := (i % _cols) / _bank_cells * _bank_cells
					var ty := (i / _cols) / _bank_cells * _bank_cells
					for dy in _bank_cells:
						for dx in _bank_cells:
							if tx + dx < _cols and ty + dy < _rows:
								drawn[(ty + dy) * _cols + tx + dx] = 1
		_drawn_wet = drawn
		var wet := func(cx: int, cy: int) -> bool:
			return cx >= 0 and cy >= 0 and cx < _cols and cy < _rows and drawn[cy * _cols + cx] == 1
		var c := SimDefs.CELL
		for cy in _rows:
			for cx in _cols:
				if drawn[cy * _cols + cx] == 0:
					continue
				var x := SimDefs.GRID_X + cx * c
				var y := SimDefs.GRID_Y + cy * c
				# a tiled map's bank runs along the floor's edge too
				if (cy > 0 or _bank > 0.0) and not wet.call(cx, cy - 1):
					_edges.append([x, y, 1, 0, 0, 1])
				if (cy + 1 < _rows or _bank > 0.0) and not wet.call(cx, cy + 1):
					_edges.append([x, y + c - 1, 1, 0, 0, -1])
				if (cx > 0 or _bank > 0.0) and not wet.call(cx - 1, cy):
					_edges.append([x, y, 0, 1, 1, 0])
				if (cx + 1 < _cols or _bank > 0.0) and not wet.call(cx + 1, cy):
					_edges.append([x + c - 1, y, 0, 1, -1, 0])
	_scan_foam()
	_drawn = Rect2()
	_surface.queue_redraw()


func _is_water(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < _cols and cy < _rows and _water[cy * _cols + cx] == 1


## Whether the floor pixel is water.
func _wet_px(x: int, y: int) -> bool:
	var c := float(SimDefs.CELL)
	return _is_water(floori((x - SimDefs.GRID_X) / c), floori((y - SimDefs.GRID_Y) / c))


static func _hash(a: int, b: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


# ------------------------------------------------------------------ the surface

func _paint_surface(ci: CanvasItem) -> void:
	glints.clear()
	glint_ver += 1
	if sim == null:
		return
	var view := _drawn.intersection(_bounds)
	if view.size == Vector2.ZERO:
		return
	var sp := surface_specks(view, _drawn_step, sim.tick)
	for i in range(0, sp.size(), 4):
		var tone := sp[i + 3]
		ci.draw_rect(Rect2(sp[i], sp[i + 1], sp[i + 2], 1), WATER[tone])
		if tone == 6 and sp[i + 2] > 1:
			glints.append(Vector2(sp[i] + sp[i + 2] * 0.5, sp[i + 1] + 0.5))


## What the surface paints over `view` at flow step `step` and tick `tick`: 1 px tall runs,
## four ints each (x, y, width, WATER tone), in drawing order. The highlights first: one dash
## per lattice slot that rides down the channel (it keeps its index k while its y grows), with
## a trough under a long one; then the foam flickering along the banks (and where the water
## ends under a bridge deck), each speck holding FOAM_TICKS from its own phase. Everything
## that doesn't change with the clock is worked out once per floor (`_scan_foam`), and the
## water lookups are inlined, so a redraw is a short loop (it once cost 3-6 ms on Twin
## Keeps). `tests/test_perf_main_thread.gd` checks it against the plain per-pixel version.
## (A dash's highlight is the only width-2+ run in tone 6; a foam speck is 1 px.)
func surface_specks(view: Rect2, step: int, tick: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var phase := tick / 28
	var x0 := floori(view.position.x)
	var x1 := ceili(view.end.x)
	var y0 := floori(view.position.y)
	var y1 := ceili(view.end.y)
	var k0 := floori((y0 - step) / float(LATTICE.y)) - 1
	var k1 := floori((y1 - step) / float(LATTICE.y)) + 1
	var g0 := floori(x0 / float(LATTICE.x)) - 1
	var g1 := floori(x1 / float(LATTICE.x)) + 1
	for k in range(k0, k1 + 1):
		var ky := k * LATTICE.y + step
		var kx := (k & 1) * 3
		for g in range(g0, g1 + 1):
			var h := (g * 73856093) ^ (k * 19349663) ^ 0x5bd1e995  # _hash(g, k), inlined
			h = (h ^ (h >> 13)) * 1274126177
			h = (h ^ (h >> 16)) & 0x7fffffff
			if h % 100 >= 46:
				continue
			var y := ky + (h >> 17) % 3
			if y < y0 or y > y1:
				continue
			var x := g * LATTICE.x + (h >> 11) % (LATTICE.x - 3) + kx
			if x < x0 or x > x1:
				continue
			var tone := ((h >> 3) + phase) % 4
			if tone == 3:
				continue  # dark moment: the dash is out
			var ln := 2 + (h >> 7) % 3
			if not _deep_i(x, y) or not _deep_i(x + ln, y):
				continue
			out.append(x)
			out.append(y)
			out.append(ln)
			out.append(6 if tone == 0 else 5)
			if ln > 2:
				out.append(x + 1)
				out.append(y + 1)
				out.append(ln - 2)
				out.append(1)
	var f := _foam
	var inset := roundi(_bank)
	var far := inset + (2 if inset > 0 else 0)
	for e in range(0, _foam_edges.size(), 2):
		var ex := _foam_edges[e]
		var ey := _foam_edges[e + 1]
		if ex + 8 < x0 or ex > x1 or ey + 8 < y0 or ey > y1:
			continue
		var j0 := (e / 2) * 8
		for j in range(j0, j0 + 8):
			var o := j * 7
			var t := (tick + f[o + 4]) / FOAM_TICKS
			var h2 := (f[o + 5] * 73856093) ^ ((f[o + 6] + t * 1009) * 19349663) ^ 0x5bd1e995
			h2 = (h2 ^ (h2 >> 13)) * 1274126177
			h2 = (h2 ^ (h2 >> 16)) & 0x7fffffff
			var m := h2 % 7
			var depth := 0
			if m < 2:
				depth = 1 + (h2 >> 5) % EDGE_DEPTH
			elif m != 2:
				continue
			var okb := _foam_ok[j]
			if (okb >> (depth + 4)) & 1 == 0:  # not worked out yet at this depth
				okb |= 1 << (depth + 4)
				if _clear_i(f[o] + f[o + 2] * depth, f[o + 1] + f[o + 3] * depth, inset, far):
					okb |= 1 << depth
				_foam_ok[j] = okb
			if (okb >> depth) & 1 == 0:
				continue  # a corner: the next bank along covers it
			out.append(f[o] + f[o + 2] * depth)
			out.append(f[o + 1] + f[o + 3] * depth)
			out.append(1)
			out.append(6 if depth <= 1 else 5)
	return out


## _deep with the water lookups inlined (the same cells: floor division by CELL).
func _deep_i(x: int, y: int) -> bool:
	var cx := (x - SimDefs.GRID_X) >> 3
	var cy := (y - SimDefs.GRID_Y) >> 3
	var l := (x - 3 - SimDefs.GRID_X) >> 3
	var r := (x + 3 - SimDefs.GRID_X) >> 3
	var t := (y - 3 - SimDefs.GRID_Y) >> 3
	var b := (y + 3 - SimDefs.GRID_Y) >> 3
	if l < 0 or r >= _cols or t < 0 or b >= _rows or cx < 0 or cx >= _cols or cy < 0 or cy >= _rows:
		return false
	return _water[cy * _cols + l] == 1 and _water[cy * _cols + r] == 1 \
		and _water[t * _cols + cx] == 1 and _water[b * _cols + cx] == 1


## The foam's fixed part, per bank segment (`_edges`): each of its 8 specks' spot pushed in
## by the bank's inset, its normal, its phase and its hash inputs (7 ints). Whether a speck
## at a depth stays clear of a drawn bank is worked out the first time it shows there
## (`_foam_ok`: bit d known at d + 4, clear at d), so a floor change costs no spike.
func _scan_foam() -> void:
	var n := _edges.size()
	_foam_edges = PackedInt32Array()
	_foam_edges.resize(n * 2)
	_foam = PackedInt32Array()
	_foam.resize(n * 8 * 7)
	_foam_ok = PackedByteArray()
	_foam_ok.resize(n * 8)
	_foam_ok.fill(0xff if roundi(_bank) <= 0 else 0)  # no bank: every depth is clear
	var inset := roundi(_bank)
	var far := inset + (2 if inset > 0 else 0)  # the far bank (land above) is deeper, its face shades the water
	for i in n:
		var e: Array = _edges[i]
		var ex := int(e[0])
		var ey := int(e[1])
		var dx := int(e[2])
		var dy := int(e[3])
		var nx := int(e[4])
		var ny := int(e[5])
		_foam_edges[i * 2] = ex
		_foam_edges[i * 2 + 1] = ey
		var off := far if ny == 1 else inset
		for u in 8:
			var px := ex + dx * u
			var py := ey + dy * u
			var h0 := ((px * 5 + nx * 11) * 73856093) ^ ((py * 5 + ny * 11) * 19349663) ^ 0x5bd1e995  # _hash, inlined
			h0 = (h0 ^ (h0 >> 13)) * 1274126177
			h0 = (h0 ^ (h0 >> 16)) & 0x7fffffff
			var o := (i * 8 + u) * 7
			_foam[o] = px + nx * off
			_foam[o + 1] = py + ny * off
			_foam[o + 2] = nx
			_foam[o + 3] = ny
			_foam[o + 4] = h0 % FOAM_TICKS
			_foam[o + 5] = px * 3 + nx * 7
			_foam[o + 6] = py * 3 + ny * 7


## _clear_of_bank without the list of offsets (the same four cells).
func _clear_i(x: int, y: int, side: int, top: int) -> bool:
	var l := (x - side - SimDefs.GRID_X) >> 3
	var r := (x + side - SimDefs.GRID_X) >> 3
	var cx := (x - SimDefs.GRID_X) >> 3
	var cy := (y - SimDefs.GRID_Y) >> 3
	var t := (y - top - SimDefs.GRID_Y) >> 3
	var b := (y + side - SimDefs.GRID_Y) >> 3
	if l < 0 or r >= _cols or cx < 0 or cx >= _cols or cy < 0 or cy >= _rows or t < 0 or b >= _rows:
		return false
	return _drawn_wet[cy * _cols + l] == 1 and _drawn_wet[cy * _cols + r] == 1 \
		and _drawn_wet[t * _cols + cx] == 1 and _drawn_wet[b * _cols + cx] == 1


## On a tiled map, whether a foam speck at (x, y) is clear of every drawn bank: the painted
## water reaches `side` px left, right and below it and `top` px above.
func _clear_of_bank(x: int, y: int, side: int, top: int) -> bool:
	var c := float(SimDefs.CELL)
	for o in [Vector2i(-side, 0), Vector2i(side, 0), Vector2i(0, -top), Vector2i(0, side)]:
		var cx := floori((x + o.x - SimDefs.GRID_X) / c)
		var cy := floori((y + o.y - SimDefs.GRID_Y) / c)
		if cx < 0 or cy < 0 or cx >= _cols or cy >= _rows or _drawn_wet[cy * _cols + cx] == 0:
			return false
	return true


## Water at the pixel and a little way round it (so a highlight stays off the foam).
func _deep(x: int, y: int) -> bool:
	return _wet_px(x - 3, y) and _wet_px(x + 3, y) and _wet_px(x, y - 3) and _wet_px(x, y + 3)


# ------------------------------------------------------------------ wakes

func _in_water(p: Vector2) -> bool:
	return _wet_px(floori(p.x), floori(p.y))


func _shown(c: CreatureSim) -> bool:
	return fx == null or fx.shown(c)


func _scale_of(c: CreatureSim) -> float:
	return clampf(c.radius / 10.0, 0.8, 2.2)


func _watch_fighters() -> void:
	for c in sim.creatures:
		var st: Dictionary = _state.get(c.id, {})
		if st.is_empty():
			st = {"pos": c.pos, "wet": false, "dir": Vector2.DOWN, "idle": 0, "moved": 0.0}
			_state[c.id] = st
		var was_wet: bool = st["wet"]
		var wet := c.state != CreatureSim.State.KO and c.swallow_t <= 0 and c.air_t <= 0 \
			and _in_water(c.pos)
		var moved: Vector2 = c.pos - st["pos"]
		var speed := moved.length()
		st["pos"] = c.pos
		st["wet"] = wet
		st["moved"] = speed
		if not wet:
			continue
		if speed > 0.3:
			st["dir"] = moved / speed
		if not _shown(c):
			continue
		var sc := _scale_of(c)
		if not was_wet:
			_splash(c.pos, sc)
			continue
		if speed > 0.3:
			var every := 2 if speed > 3.0 else 3
			if sim.tick % every == 0:
				var d: Vector2 = st["dir"]
				_ripples.append({"pos": c.pos - d * (c.radius * 0.35), "age": 0,
					"life": RIPPLE_LIFE + int(speed * 2.0), "r0": 8.0 * sc, "grow": 9.0 * sc})
			st["idle"] = 0
		else:
			st["idle"] = int(st["idle"]) + 1
			if int(st["idle"]) % 45 == 1:  # standing in it: a slow ring
				_ripples.append({"pos": c.pos, "age": 0, "life": 30, "r0": 8.0 * sc, "grow": 7.0 * sc})


func _splash(p: Vector2, sc: float) -> void:
	_ripples.append({"pos": p, "age": 0, "life": SPLASH_LIFE, "r0": 6.0 * sc, "grow": 18.0 * sc})
	_ripples.append({"pos": p, "age": -4, "life": SPLASH_LIFE + 6, "r0": 4.0 * sc, "grow": 14.0 * sc})
	for i in int(6 * sc) + 2:
		_drops.append({"pos": p + Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-2, 2)) * sc,
			"vx": _rng.randf_range(-1.1, 1.1), "vy": _rng.randf_range(-0.6, 0.6),
			"z": 0.0, "vz": _rng.randf_range(1.8, 3.2) * sqrt(sc), "age": 0})


func _age_wakes() -> void:
	var i := 0
	while i < _ripples.size():
		var r: Dictionary = _ripples[i]
		r["age"] = int(r["age"]) + 1
		if int(r["age"]) >= int(r["life"]):
			_ripples.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _drops.size():
		var d: Dictionary = _drops[i]
		d["pos"] += Vector2(d["vx"], d["vy"])
		d["z"] += d["vz"]
		d["vz"] -= 0.32
		d["age"] = int(d["age"]) + 1
		if d["z"] < 0.0:
			_ripples.append({"pos": d["pos"], "age": 0, "life": 9, "r0": 1.0, "grow": 3.0})
			_drops.remove_at(i)
		else:
			i += 1


## Tones fade with age; the last third breaks up in a checker so nothing is a smooth fade.
func _ripple_tone(age: int, life: int, px: int, py: int) -> int:
	var f := float(age) / float(life)
	if f > 0.66 and (px + py) % 2 != 0:
		return -1
	if f < 0.33:
		return 6
	return 5 if f < 0.75 else 4


func _paint_wakes(ci: CanvasItem) -> void:
	if sim == null:
		return
	var view := FxView._view_rect(self, CULL_PAD)
	for r in _ripples:
		var age := int(r["age"])
		if age < 0:
			continue
		var p: Vector2 = r["pos"]
		if not view.has_point(p):
			continue
		var life := int(r["life"])
		var rad := float(r["r0"]) + float(r["grow"]) * float(age) / float(life)
		var n := maxi(int(rad * 2.4), 8)
		for j in n:
			if j % 3 == 2:
				continue  # a broken ring
			var a := TAU * float(j) / float(n)
			var px := roundi(p.x + cos(a) * rad)
			var py := roundi(p.y + sin(a) * rad * 0.55)
			if not _wet_px(px, py):
				continue
			var t := _ripple_tone(age, life, px, py)
			if t >= 0:
				ci.draw_rect(Rect2(px, py, 1, 1), WATER[t])
	# The V behind a wading fighter.
	for c in sim.creatures:
		var st: Dictionary = _state.get(c.id, {})
		if st.is_empty() or not st["wet"] or not view.has_point(c.pos) or not _shown(c):
			continue
		var speed: float = st["moved"]
		if speed < 0.3:
			continue
		var d: Vector2 = st["dir"]
		var sc := _scale_of(c)
		var length := (9.0 + speed * 3.0) * sc
		for side in [-1.0, 1.0]:
			var arm := (-d).rotated(side * 0.5)
			var s := c.radius * 0.5
			while s < length:
				var q := c.pos + arm * s
				var px := roundi(q.x)
				var py := roundi(c.pos.y + (q.y - c.pos.y) * 0.55)
				if _wet_px(px, py) and int(s) % 3 != 2:
					ci.draw_rect(Rect2(px, py, 1, 1), WATER[6] if s < length * 0.5 else WATER[4])
				s += 1.0
	for dr in _drops:
		var p: Vector2 = dr["pos"]
		if view.has_point(p):
			ci.draw_rect(Rect2(roundi(p.x), roundi(p.y - float(dr["z"])), 1, 1), WATER[6])
