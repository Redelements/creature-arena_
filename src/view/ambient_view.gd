class_name AmbientView
extends Node2D
## A map's ambient life, from the optional "ambient" block of data/arenas/<id>.json (a map
## without the key draws nothing). Cosmetic: reads the sim, never writes it. The Greenhouse
## was the first user; every part is its own key, so another map picks what suits it:
##
##   "ambient": {
##     "panes":   {"w": 72, "h": 56, "bar": 3, "alpha": 0.1, "drift": 30},   glass-frame shadows
##     "motes":   {"kind": "pollen", "count": 40},                            drifting specks
##     "sway":    true,                                                       brush rustles
##     "critters": {"kind": "butterfly", "count": 3}                          flutter over the beds
##   }
##
## Panes: a soft grid of frame shadows on the floor, slid along the map's `light` a pixel
## every `drift` ticks (0 = still). Motes: `count` specks on a slow breeze ("pollen" with
## the odd seed, or "dust"). Sway: the top edge of every brush bed shifts a pixel or two in
## the breeze (strips of the map's own picture, moved whole pixels), and a bed someone
## wades through rustles harder and flicks leaves. Critters: butterflies that drift between
## the brush beds, settle, and flutter off from a fighter who comes close.
##
## Hidden foes: brush hides a fighter from the other team (Vision), so nothing here may
## give one away. A fighter stirs the brush, flicks leaves or scares a butterfly only when
## `fx.shown(c)` says the local team sees it; a hidden foe changes nothing.
##
## Pixel rules: whole pixels, no rotation or smooth scaling, animated on the 60 Hz tick
## (no interpolation). Cost: panes redraw when the drift steps, the sway layer a few times
## a second, the motes layer only on a tick where a speck changed pixel; all cull to the
## view (`FxView._view_rect`). Main calls set_sim() and advance(), and puts this between
## the water and the shadows; the motes and critters sit above the fighters (z_index 1).

const MARGIN := Vector2(400, 80)  ## where the map picture starts (ArenaView.MARGIN)
const CULL_PAD := 24.0
const DRAWN_PAD := 96.0  ## the sway layer draws this far past the view
const SWAY_STEP := 8  ## ticks between a calm bed's sway steps
const STIR_STEP := 3  ## ticks between a rustling bed's steps
const STIR_LIFE := 24  ## a bed keeps rustling this long after the fighter has gone by
const SCARE_RANGE := 44.0
const LEAF_CAP := 24
const MOTE_KINDS := {
	"pollen": {"colors": [Color(1.0, 0.93, 0.55), Color(0.98, 0.86, 0.45), Color(1.0, 1.0, 0.8)], "seeds": 0.2},
	"dust": {"colors": [Color(0.9, 0.9, 0.85), Color(0.75, 0.75, 0.7)], "seeds": 0.0},
}
const BUTTERFLY_COLORS: Array[Color] = [Color8(240, 150, 60), Color8(120, 176, 240), Color8(244, 214, 236), Color8(250, 226, 90)]
const LEAF_COLORS: Array[Color] = [Color8(96, 160, 74), Color8(150, 200, 104), Color8(62, 122, 56)]

var sim: MatchSim
## Main's FxView (anything with `shown(creature)`): the fighters the local team can see.
## null shows everyone.
var fx = null
var art: Texture2D = null  ## the map picture, for the sway (ArenaView.art())

var _cfg := {}
var _terrain: TerrainGrid
var _version := -1
var _panes: Layer
var _sway: Layer
var _over: Layer
var _floor := Rect2()
var _beds: Array[Rect2] = []  ## the map's brush beds (where butterflies go)
var _brush := PackedInt32Array()  ## cell indices of standing brush
var _edge := {}  ## cell index -> true when nothing brush lies above it
var _stir := {}  ## cell index -> {until, hard}: a bed a seen fighter is in
var _drawn := Rect2()
var _drawn_step := -1
var _pane_step := -1
var _last_tick := -1
var _motes: Array = []  ## {p, ph, col, seed}
var _leaves: Array = []  ## {p, v, z, vz, life, col}
var _flies: Array = []  ## {p, v, to, rest, afraid, ph, col}
var _was_moving := {}  ## creature id -> last position
var _rng := RandomNumberGenerator.new()
var _over_dirty := true
var _scared_now := 0


class Layer extends Node2D:
	var paint: Callable
	var label := ""

	func _draw() -> void:
		var t0 := PerfLog.now()
		paint.call(self)
		PerfLog.since(label, t0)


func _init() -> void:
	_sway = _layer(_paint_sway, "ambient sway")
	_panes = _layer(_paint_panes, "ambient panes")
	_over = _layer(_paint_over, "ambient over")
	_over.z_index = 1  # above the fighters (tiny and soft: it never hides play)
	_rng.seed = 2610


func _layer(f: Callable, label: String) -> Layer:
	var l := Layer.new()
	l.paint = f
	l.label = label
	add_child(l)
	return l


func set_sim(s: MatchSim, picture: Texture2D = null) -> void:
	sim = s
	art = picture
	_terrain = s.terrain
	_cfg = s.arena.get("ambient", {})
	_version = -1
	_last_tick = -1
	_drawn_step = -1
	_pane_step = -1
	_stir.clear()
	_leaves.clear()
	_was_moving.clear()
	_scared_now = 0
	_rng.seed = 2610
	visible = not _cfg.is_empty()
	_floor = _terrain.floor_rect()
	_beds.clear()
	for p in s.arena.get("pieces", []):
		if String(p.get("kind", "")) == "brush":
			var r: Array = p["rect"]
			_beds.append(Rect2(SimDefs.GRID_X + int(r[0]) * SimDefs.CELL, SimDefs.GRID_Y + int(r[1]) * SimDefs.CELL,
				int(r[2]) * SimDefs.CELL, int(r[3]) * SimDefs.CELL))
	_make_motes()
	_make_flies()
	_scan()
	_panes.queue_redraw()
	_sway.queue_redraw()
	_over.queue_redraw()


# ------------------------------------------------------------------ introspection (tests)

func stirred_cells() -> int:
	return _stir.size()


func leaf_count() -> int:
	return _leaves.size()


func scared_flies() -> int:
	return _scared_now


func fly_count() -> int:
	return _flies.size()


# ------------------------------------------------------------------ the tick

func advance() -> void:
	if sim == null or _terrain == null or _cfg.is_empty():
		return
	if sim.tick == _last_tick:
		return
	_last_tick = sim.tick
	if _terrain.version != _version:
		_scan()
	var t := sim.tick
	var view := FxView._view_rect(self, 0.0)
	# Panes slide along the light, a pixel at a time.
	var pc: Dictionary = _cfg.get("panes", {})
	if not pc.is_empty():
		var drift := int(pc.get("drift", 30))
		var step := t / drift if drift > 0 else 0
		if step != _pane_step:
			_pane_step = step
			_panes.queue_redraw()
	# Brush: who is in it (only fighters the local team sees), and the sway clock.
	if _cfg.get("sway", false):
		_watch_brush()
		var stirring := not _stir.is_empty()
		var every := STIR_STEP if stirring else SWAY_STEP
		var step2 := t / every
		if step2 != _drawn_step or not _drawn.encloses(view):
			_drawn_step = step2
			if not _drawn.encloses(view):
				_drawn = view.grow(DRAWN_PAD)
			_sway.queue_redraw()
	_move_motes()
	_move_flies()
	_move_leaves()
	if _over_dirty:
		_over.queue_redraw()
		_over_dirty = false


func _seen(c: CreatureSim) -> bool:
	return fx == null or fx.shown(c)


## A fighter that can stir things: alive, on the ground, and seen by the local team.
func _stirs(c: CreatureSim) -> bool:
	return c.state != CreatureSim.State.KO and c.air_t <= 0 and c.swallow_t <= 0 and _seen(c)


func _scan() -> void:
	_version = _terrain.version
	_brush.clear()
	_edge.clear()
	var cols := _terrain.cols
	for i in cols * _terrain.rows:
		if _terrain.cells[i] != TerrainGrid.BRUSH:
			continue
		_brush.append(i)
		if i < cols or _terrain.cells[i - cols] != TerrainGrid.BRUSH:
			_edge[i] = true
	_drawn = Rect2()
	_sway.queue_redraw()


func _cell_of(p: Vector2) -> int:
	var cx := floori((p.x - SimDefs.GRID_X) / float(SimDefs.CELL))
	var cy := floori((p.y - SimDefs.GRID_Y) / float(SimDefs.CELL))
	if cx < 0 or cy < 0 or cx >= _terrain.cols or cy >= _terrain.rows:
		return -1
	return cy * _terrain.cols + cx


## Marks the brush cells a seen fighter stands in or touches, and flicks leaves off it.
func _watch_brush() -> void:
	var t := sim.tick
	for c in sim.creatures:
		var prev: Vector2 = _was_moving.get(c.id, c.pos)
		_was_moving[c.id] = c.pos
		if not _stirs(c):
			continue
		var speed := (c.pos - prev).length()
		var home := _cell_of(c.pos)
		if home < 0 or _terrain.cells[home] != TerrainGrid.BRUSH:
			continue
		var reach := c.radius * 0.6
		for off in [Vector2.ZERO, Vector2(reach, 0), Vector2(-reach, 0), Vector2(0, reach), Vector2(0, -reach)]:
			var i := _cell_of(c.pos + off)
			if i >= 0 and _terrain.cells[i] == TerrainGrid.BRUSH:
				_stir[i] = {"until": t + STIR_LIFE, "hard": speed > 0.4}
		if speed > 0.4 and t % 5 == 0 and _leaves.size() < LEAF_CAP:
			_flick(c, speed)
		elif speed <= 0.4 and t % 50 == 0 and _leaves.size() < LEAF_CAP:
			_flick(c, 0.0)
	var dead := []
	for i in _stir:
		if int(_stir[i]["until"]) < t:
			dead.append(i)
	for i in dead:
		_stir.erase(i)


func _flick(c: CreatureSim, speed: float) -> void:
	var ang := _rng.randf() * TAU
	_leaves.append({"p": c.pos + Vector2(cos(ang), sin(ang) * 0.5) * c.radius * 0.7,
		"v": Vector2(_rng.randf_range(-0.5, 0.5) + cos(ang) * 0.3, -0.2), "z": 4.0 + _rng.randf() * 6.0,
		"vz": 0.5 + _rng.randf() * 0.8 + speed * 0.1, "life": 26 + _rng.randi() % 14,
		"col": LEAF_COLORS[_rng.randi() % LEAF_COLORS.size()]})
	_over_dirty = true


func _move_leaves() -> void:
	var i := 0
	while i < _leaves.size():
		var l: Dictionary = _leaves[i]
		l["p"] += l["v"]
		l["z"] += l["vz"]
		l["vz"] -= 0.07
		l["life"] = int(l["life"]) - 1
		if int(l["life"]) <= 0 or float(l["z"]) < 0.0:
			_leaves.remove_at(i)
		else:
			i += 1
	if not _leaves.is_empty():
		_over_dirty = true


# ------------------------------------------------------------------ motes

func _make_motes() -> void:
	_motes.clear()
	var mc: Dictionary = _cfg.get("motes", {})
	if mc.is_empty():
		return
	var kind: Dictionary = MOTE_KINDS.get(String(mc.get("kind", "pollen")), MOTE_KINDS["pollen"])
	var cols: Array = kind["colors"]
	for i in int(mc.get("count", 30)):
		_motes.append({"p": _floor.position + Vector2(_rng.randf() * _floor.size.x, _rng.randf() * _floor.size.y),
			"ph": _rng.randf() * TAU, "col": cols[i % cols.size()], "seed": _rng.randf() < float(kind["seeds"])})


## The breeze: mostly along the map, swelling and slackening, a little lift and fall.
func _wind(p: Vector2, t: int) -> Vector2:
	var gust := 0.5 + 0.5 * sin(float(t) * 0.011 + p.y * 0.012)
	return Vector2(0.06 + 0.16 * gust, 0.02 * sin(float(t) * 0.017 + p.x * 0.02))


func _move_motes() -> void:
	if _motes.is_empty():
		return
	var t := sim.tick
	var grow := _floor.grow(16.0)
	for m in _motes:
		var p: Vector2 = m["p"]
		var before := Vector2i(roundi(p.x), roundi(p.y))
		p += _wind(p, t) + Vector2(0.0, 0.03 * sin(float(t) * 0.05 + float(m["ph"])))
		if p.x > grow.end.x:
			p = Vector2(grow.position.x, _floor.position.y + _rng.randf() * _floor.size.y)
		elif p.y > grow.end.y or p.y < grow.position.y:
			p.y = clampf(p.y, _floor.position.y, _floor.end.y)
		m["p"] = p
		if before != Vector2i(roundi(p.x), roundi(p.y)):
			_over_dirty = true
	if t % 20 == 0:
		_over_dirty = true  # the twinkle


# ------------------------------------------------------------------ butterflies

func _make_flies() -> void:
	_flies.clear()
	var cc: Dictionary = _cfg.get("critters", {})
	if cc.is_empty() or _beds.is_empty():
		return
	for i in int(cc.get("count", 3)):
		var bed := _beds[_rng.randi() % _beds.size()]
		var p := _in_bed(bed)
		_flies.append({"p": p, "v": Vector2.ZERO, "to": _in_bed(_beds[_rng.randi() % _beds.size()]),
			"rest": _rng.randi() % 60, "afraid": 0, "ph": _rng.randf() * TAU,
			"col": BUTTERFLY_COLORS[i % BUTTERFLY_COLORS.size()]})


func _in_bed(bed: Rect2) -> Vector2:
	return bed.position + Vector2(_rng.randf() * bed.size.x, _rng.randf() * bed.size.y)


func _move_flies() -> void:
	if _flies.is_empty():
		return
	var t := sim.tick
	var scary: Array = []
	for c in sim.creatures:
		if c.state != CreatureSim.State.KO and _seen(c):
			scary.append(c)
	_scared_now = 0
	for f in _flies:
		var p: Vector2 = f["p"]
		var near: CreatureSim = null
		var best := SCARE_RANGE
		for c in scary:
			var d := p.distance_to(c.pos)
			if d < best:
				best = d
				near = c
		if near != null:
			var away := (p - near.pos).normalized() if p != near.pos else Vector2.RIGHT
			f["v"] = away * 1.7
			f["afraid"] = 40
			f["rest"] = 0
			f["to"] = _far_target(near.pos)
		if int(f["afraid"]) > 0:
			_scared_now += 1
			f["afraid"] = int(f["afraid"]) - 1
		if int(f["rest"]) > 0:
			f["rest"] = int(f["rest"]) - 1  # settled on a leaf
			if int(f["rest"]) == 0:
				f["to"] = _in_bed(_beds[_rng.randi() % _beds.size()])
			if near == null:
				continue
		var to: Vector2 = f["to"]
		var dir := to - p
		var speed := 0.55 if int(f["afraid"]) == 0 else 1.3
		if dir.length() < 4.0 and int(f["afraid"]) == 0:
			f["rest"] = 50 + _rng.randi() % 100
			f["v"] = Vector2.ZERO
			_over_dirty = true
			continue
		var want := dir.normalized() * speed + Vector2(0.0, 0.25 * sin(float(t) * 0.23 + float(f["ph"]))) \
			+ Vector2(0.2 * sin(float(t) * 0.11 + float(f["ph"]) * 2.0), 0.0)
		f["v"] = (f["v"] as Vector2).lerp(want, 0.12)
		f["p"] = p + (f["v"] as Vector2)
		_over_dirty = true
	if scary.is_empty():
		_scared_now = 0


## Somewhere to flee to: a bed well away from the fighter (or just away).
func _far_target(from: Vector2) -> Vector2:
	var best: Rect2 = _beds[0]
	var far := -1.0
	for b in _beds:
		var d := b.get_center().distance_to(from) + _rng.randf() * 40.0
		if d > far:
			far = d
			best = b
	return _in_bed(best)


# ------------------------------------------------------------------ drawing: panes

func _bar(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var q := r.intersection(_floor)
	if q.size.x > 0.0 and q.size.y > 0.0:
		ci.draw_rect(q, col)


func _paint_panes(ci: CanvasItem) -> void:
	if sim == null:
		return
	var pc: Dictionary = _cfg.get("panes", {})
	if pc.is_empty():
		return
	var pw := int(pc.get("w", 72))
	var ph := int(pc.get("h", 56))
	var bar := int(pc.get("bar", 3))
	var a := float(pc.get("alpha", 0.1))
	var d: Vector2 = ShadowLayer.light_of(sim.arena)["cast"]
	d = d.normalized()
	var off := Vector2i(floori(float(_pane_step) * d.x), floori(float(_pane_step) * d.y))
	var core := Color(0.02, 0.06, 0.05, a)
	var soft := Color(0.02, 0.06, 0.05, a * 0.5)
	var fx0 := int(_floor.position.x)
	var fy0 := int(_floor.position.y)
	var x := fx0 + posmod(off.x, pw)
	while x < _floor.end.x + pw:
		var xx := x - pw
		_bar(ci, Rect2(xx - 1, fy0, 1, _floor.size.y), soft)
		_bar(ci, Rect2(xx, fy0, bar, _floor.size.y), core)
		_bar(ci, Rect2(xx + bar, fy0, 1, _floor.size.y), soft)
		x += pw
	var y := fy0 + posmod(off.y, ph)
	while y < _floor.end.y + ph:
		var yy := y - ph
		_bar(ci, Rect2(fx0, yy - 1, _floor.size.x, 1), soft)
		_bar(ci, Rect2(fx0, yy, _floor.size.x, bar), core)
		_bar(ci, Rect2(fx0, yy + bar, _floor.size.x, 1), soft)
		y += ph


# ------------------------------------------------------------------ drawing: sway

## One 2-row strip of the map picture, moved `s` px sideways over itself.
func _strip(ci: CanvasItem, x: int, y: int, w: int, h: int, s: int) -> void:
	ci.draw_texture_rect_region(art, Rect2(x + s, y, w, h), Rect2(Vector2(x, y) + MARGIN, Vector2(w, h)))


func _paint_sway(ci: CanvasItem) -> void:
	if sim == null or art == null or not _cfg.get("sway", false):
		return
	var t := sim.tick
	var cols := _terrain.cols
	var view := _drawn
	var calm := float(t / SWAY_STEP)
	for i in _brush:
		var cx := i % cols
		var cy := i / cols
		var x := SimDefs.GRID_X + cx * SimDefs.CELL
		var y := SimDefs.GRID_Y + cy * SimDefs.CELL
		if not view.intersects(Rect2(x, y, 8, 8)):
			continue
		if _stir.has(i):
			var amp := 2.4 if bool(_stir[i]["hard"]) else 1.6
			var phase := float(t) * 0.9
			for dy in range(0, 8, 2):
				var s := roundi(amp * sin(phase + float(dy) * 0.9 + float(cx) * 2.3))
				if s != 0:
					_strip(ci, x, y + dy, 8, 2, s)
		elif _edge.has(i):
			# The top edge of a bed: the leaves sway in the breeze, a wave rolling along it.
			for dy in range(-2, 6, 2):
				var s := roundi(1.25 * sin(calm * 0.55 - float(x) * 0.05 + float(dy) * 0.3))
				if s != 0:
					_strip(ci, x, y + dy, 8, 2, s)


# ------------------------------------------------------------------ drawing: motes, critters, leaves

func _paint_over(ci: CanvasItem) -> void:
	if sim == null:
		return
	var view := FxView._view_rect(self, CULL_PAD)
	var t := sim.tick
	for m in _motes:
		var p: Vector2 = m["p"]
		if not view.has_point(p):
			continue
		if (t / 20 + int(float(m["ph"]) * 3.0)) % 6 == 0:
			continue  # twinkles out
		var col: Color = m["col"]
		var px := roundi(p.x)
		var py := roundi(p.y)
		if bool(m["seed"]):
			ci.draw_rect(Rect2(px, py, 1, 1), Color(1, 1, 1, 0.75))
			ci.draw_rect(Rect2(px - 1, py + 1, 1, 1), Color(1, 1, 1, 0.35))
			ci.draw_rect(Rect2(px + 1, py - 1, 1, 1), Color(1, 1, 1, 0.35))
		else:
			col.a = 0.7
			ci.draw_rect(Rect2(px, py, 1, 1), col)
	for l in _leaves:
		var p: Vector2 = l["p"]
		if not view.has_point(p):
			continue
		var col: Color = l["col"]
		var life := int(l["life"])
		if life < 8 and life % 2 == 0:
			continue  # fading out in a flicker
		ci.draw_rect(Rect2(roundi(p.x), roundi(p.y - float(l["z"])), 2, 1), col)
	for f in _flies:
		var p: Vector2 = f["p"]
		if not view.has_point(p):
			continue
		_draw_fly(ci, f, t)


func _draw_fly(ci: CanvasItem, f: Dictionary, t: int) -> void:
	var p: Vector2 = f["p"]
	var x := roundi(p.x)
	var y := roundi(p.y) - 7  # flying above the leaves
	var col: Color = f["col"]
	var rest := int(f["rest"]) > 0
	var open := ((t / (14 if rest else 3)) + int(float(f["ph"]) * 2.0)) % 2 == 0
	var body := Color8(52, 34, 30)
	var pale := col.lightened(0.35)
	if open:
		ci.draw_rect(Rect2(x - 2, y - 1, 2, 2), col)
		ci.draw_rect(Rect2(x + 1, y - 1, 2, 2), col)
		ci.draw_rect(Rect2(x - 2, y - 1, 1, 1), pale)
		ci.draw_rect(Rect2(x + 2, y - 1, 1, 1), pale)
	else:
		ci.draw_rect(Rect2(x - 1, y - 2, 1, 3), col)
		ci.draw_rect(Rect2(x + 1, y - 2, 1, 3), col)
	ci.draw_rect(Rect2(x, y - 1, 1, 2), body)
