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
## More kinds (every key optional; `motes` and `critters` may also be a list of blocks):
##   motes    kind pollen | dust | sundust (hangs in low sun) | mist (rises, low alpha) |
##            sand (fast streaks) | leaf (tumbling), `area` [col,row,w,h] cells to stay in
##   critters butterfly (brush beds) | dragonfly (`area`) | bird {every, flock, span, alpha,
##            first} high over the whole arena | fish {every} jumps in shallows |
##            devil {every, life} a wandering dust devil
##   grit     {every}: a trickle off the rubble walls that puffs where it lands
##   confetti {cap, on: ["ko", "surge"]}: paper scraps fall after those big moments
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
## speed: x the breeze; alpha: how solid; w: pixels wide; rise: up (-) or down per tick.
const MOTE_KINDS := {
	"pollen": {"colors": [Color(1.0, 0.93, 0.55), Color(0.98, 0.86, 0.45), Color(1.0, 1.0, 0.8)], "seeds": 0.2},
	"dust": {"colors": [Color(0.9, 0.9, 0.85), Color(0.75, 0.75, 0.7)], "seeds": 0.0},
	"sundust": {"colors": [Color(1.0, 0.88, 0.62), Color(0.96, 0.8, 0.52), Color(1.0, 0.95, 0.8)], "seeds": 0.0,
		"speed": 0.3, "alpha": 0.8},
	"mist": {"colors": [Color(0.86, 0.94, 1.0), Color(0.72, 0.86, 0.96)], "seeds": 0.0,
		"speed": 0.5, "alpha": 0.26, "w": 2, "rise": -0.05},
	"sand": {"colors": [Color(0.9, 0.78, 0.56), Color(0.8, 0.66, 0.46)], "seeds": 0.0,
		"speed": 3.2, "alpha": 0.42, "w": 2},
	"leaf": {"colors": [Color(0.5, 0.64, 0.28), Color(0.7, 0.55, 0.26), Color(0.4, 0.5, 0.22)], "seeds": 0.0,
		"speed": 1.5, "alpha": 0.85, "w": 2, "rise": 0.012},
}
## Flying critters. zone: "beds" (the brush) or "area". speed/flee in px per tick, rest in ticks.
const FLY_KINDS := {
	"butterfly": {"zone": "beds", "speed": 0.55, "fear": 1.3, "flee": 1.7, "scare": 44.0, "rest": [50, 100],
		"wob": 0.25, "lift": 7},
	"dragonfly": {"zone": "area", "speed": 1.15, "fear": 2.2, "flee": 2.6, "scare": 40.0, "rest": [6, 34],
		"wob": 0.08, "lift": 6},
}
const DRAGON_COLORS: Array[Color] = [Color8(70, 190, 190), Color8(90, 150, 230), Color8(110, 210, 140)]
const GRIT_COLORS: Array[Color] = [Color8(176, 156, 124), Color8(128, 112, 90), Color8(206, 190, 160)]
const CONFETTI_COLORS: Array[Color] = [Color8(236, 70, 70), Color8(80, 130, 240), Color8(250, 220, 80),
	Color8(245, 245, 245), Color8(90, 200, 120), Color8(240, 130, 200)]
const CONFETTI_CAP := 90
const DUST_LIGHT := Color8(236, 220, 186)
const DUST_DARK := Color8(120, 100, 76)
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
var _low: Layer  ## under the fighters: grit, splashes, dust devil, confetti on the floor
var _sky: Layer  ## above everything: birds
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
var _mote_kind: Dictionary = MOTE_KINDS["pollen"]
var _mote_rect := Rect2()
var _walls := PackedInt32Array()  ## cell indices of standing rubble (grit falls off them)
var _shallows := PackedInt32Array()
var _grit: Array = []  ## {p, z, vz, puff (-1 falling), col}
var _streams: Array = []  ## {p, z, left}: a trickle that sheds grit
var _grit_next := 0
var _fish: Array = []  ## {p, dx, t, dur}
var _fish_next := 0
var _splash: Array = []  ## {p, t}
var _birds: Array = []  ## {p, v, age, ph}
var _bird_next := 0
var _devil: Dictionary = {}
var _devil_next := 0
var _scraps: Array = []  ## {p, v, ty, rest, ph, col}
var _low_dirty := true
var _sky_dirty := true
var _leaves: Array = []  ## {p, v, z, vz, life, col}
var _flies: Array = []  ## {p, v, to, rest, afraid, ph, col}
var _was_moving := {}  ## creature id -> last position
var _rng := RandomNumberGenerator.new()
var _over_dirty := true
var _scared_now := 0
var _crit: Dictionary = {}  ## critter kind -> its config block
## The match's weather (WeatherView, `set_weather`): x the breeze, x the motes, and
## whether butterflies and dragonflies come out (they shelter from rain and snow).
var wind_mul := 1.0
var mote_mul := 1.0
var flies := true


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
	_low = _layer(_paint_low, "ambient low")
	_over.z_index = 1  # above the fighters (tiny and soft: it never hides play)
	_sky = _layer(_paint_sky, "ambient sky")
	_sky.z_index = 10  # birds cross high over everything
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
	_grit.clear()
	_streams.clear()
	_fish.clear()
	_splash.clear()
	_birds.clear()
	_devil = {}
	_scraps.clear()
	_crit.clear()
	for cc in _blocks(_cfg.get("critters", {})):
		_crit[String(cc.get("kind", "butterfly"))] = cc
	_grit_next = 90
	_fish_next = 120
	_bird_next = int((_crit.get("bird", {}) as Dictionary).get("first", 240))
	_devil_next = 300
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
	_low_dirty = true
	_sky_dirty = true
	_panes.queue_redraw()
	_sway.queue_redraw()
	_over.queue_redraw()
	_low.queue_redraw()
	_sky.queue_redraw()


## The weather (WeatherView): a stronger or calmer breeze, more or fewer motes, critters
## out or sheltering. Called after set_sim; remakes the motes and the critters.
func set_weather(p_wind: float, p_motes: float, p_flies: bool) -> void:
	if is_equal_approx(p_wind, wind_mul) and is_equal_approx(p_motes, mote_mul) and p_flies == flies:
		return
	wind_mul = p_wind
	mote_mul = p_motes
	flies = p_flies
	if sim == null or _cfg.is_empty():
		return
	_make_motes()
	_make_flies()
	_over_dirty = true
	_over.queue_redraw()


## A config entry that may be one block or a list of them, as a list.
func _blocks(v) -> Array:
	if v is Array:
		return v
	if v is Dictionary and not (v as Dictionary).is_empty():
		return [v]
	return []


# ------------------------------------------------------------------ introspection (tests)

func stirred_cells() -> int:
	return _stir.size()


func leaf_count() -> int:
	return _leaves.size()


func scared_flies() -> int:
	return _scared_now


func fly_count() -> int:
	return _flies.size()


func mote_count() -> int:
	return _motes.size()


func scrap_count() -> int:
	return _scraps.size()


func bird_count() -> int:
	return _birds.size()


func grit_count() -> int:
	return _grit.size() + _streams.size()


func fish_count() -> int:
	return _fish.size()


func devil_active() -> bool:
	return not _devil.is_empty()


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
	_life(t, view)
	if _over_dirty:
		_over.queue_redraw()
		_over_dirty = false
	if _low_dirty:
		_low.queue_redraw()
		_low_dirty = false
	if _sky_dirty:
		_sky.queue_redraw()
		_sky_dirty = false


func _seen(c: CreatureSim) -> bool:
	return fx == null or fx.shown(c)


## A fighter that can stir things: alive, on the ground, and seen by the local team.
func _stirs(c: CreatureSim) -> bool:
	return c.state != CreatureSim.State.KO and c.air_t <= 0 and c.swallow_t <= 0 and _seen(c)


func _scan() -> void:
	_version = _terrain.version
	_brush.clear()
	_edge.clear()
	_walls.clear()
	_shallows.clear()
	var cols := _terrain.cols
	var want_walls := _cfg.has("grit")
	var want_water := _crit.has("fish")
	for i in cols * _terrain.rows:
		var cell := _terrain.cells[i]
		if want_walls and cell == TerrainGrid.WALL:
			_walls.append(i)
		elif want_water and cell == TerrainGrid.SHALLOWS:
			_shallows.append(i)
		if cell != TerrainGrid.BRUSH:
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
	_mote_kind = kind
	_mote_rect = _cells_rect(mc.get("area", []), _floor)
	var cols: Array = kind["colors"]
	for i in int(round(int(mc.get("count", 30)) * mote_mul)):
		_motes.append({"p": _mote_rect.position + Vector2(_rng.randf() * _mote_rect.size.x, _rng.randf() * _mote_rect.size.y),
			"ph": _rng.randf() * TAU, "col": cols[i % cols.size()], "seed": _rng.randf() < float(kind["seeds"])})


## [col, row, w, h] in cells as floor pixels (or `fallback` when the key is absent).
func _cells_rect(a, fallback: Rect2) -> Rect2:
	if not (a is Array) or (a as Array).size() < 4:
		return fallback
	return Rect2(SimDefs.GRID_X + int(a[0]) * SimDefs.CELL, SimDefs.GRID_Y + int(a[1]) * SimDefs.CELL,
		int(a[2]) * SimDefs.CELL, int(a[3]) * SimDefs.CELL)


## The breeze: mostly along the map, swelling and slackening, a little lift and fall.
func _wind(p: Vector2, t: int) -> Vector2:
	var gust := 0.5 + 0.5 * sin(float(t) * 0.011 + p.y * 0.012)
	return Vector2(0.06 + 0.16 * gust, 0.02 * sin(float(t) * 0.017 + p.x * 0.02)) * wind_mul


func _move_motes() -> void:
	if _motes.is_empty():
		return
	var t := sim.tick
	var grow := _mote_rect.grow(16.0)
	var speed := float(_mote_kind.get("speed", 1.0))
	var rise := float(_mote_kind.get("rise", 0.0))
	for m in _motes:
		var p: Vector2 = m["p"]
		var before := Vector2i(roundi(p.x), roundi(p.y))
		p += _wind(p, t) * speed + Vector2(0.0, 0.03 * sin(float(t) * 0.05 + float(m["ph"])) + rise)
		if p.x > grow.end.x:
			p = Vector2(grow.position.x, _mote_rect.position.y + _rng.randf() * _mote_rect.size.y)
		elif rise != 0.0 and (p.y < _mote_rect.position.y or p.y > _mote_rect.end.y):
			p = Vector2(_mote_rect.position.x + _rng.randf() * _mote_rect.size.x, _mote_rect.end.y if rise < 0.0 else _mote_rect.position.y)
		elif p.y > grow.end.y or p.y < grow.position.y:
			p.y = clampf(p.y, _mote_rect.position.y, _mote_rect.end.y)
		m["p"] = p
		if before != Vector2i(roundi(p.x), roundi(p.y)):
			_over_dirty = true
	if t % 20 == 0:
		_over_dirty = true  # the twinkle


# ------------------------------------------------------------------ butterflies

func _make_flies() -> void:
	_flies.clear()
	for kind in ["butterfly", "dragonfly"]:
		if not _crit.has(kind) or not flies:
			continue
		var cc: Dictionary = _crit[kind]
		var spec: Dictionary = FLY_KINDS[kind]
		var zone := Rect2()
		if String(spec["zone"]) == "beds":
			if _beds.is_empty():
				continue
		else:
			zone = _cells_rect(cc.get("area", []), _floor)
		var cols: Array[Color] = BUTTERFLY_COLORS if kind == "butterfly" else DRAGON_COLORS
		for i in int(cc.get("count", 3)):
			var f := {"k": kind, "zone": zone, "v": Vector2.ZERO, "rest": _rng.randi() % 60, "afraid": 0,
				"ph": _rng.randf() * TAU, "col": cols[i % cols.size()]}
			f["p"] = _spot(f)
			f["to"] = _spot(f)
			_flies.append(f)


## A random place a critter of this kind goes: a brush bed, or a point in its area.
func _spot(f: Dictionary) -> Vector2:
	if String(f["k"]) == "butterfly":
		return _in_bed(_beds[_rng.randi() % _beds.size()])
	return _in_bed(f["zone"])


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
		var spec: Dictionary = FLY_KINDS[f["k"]]
		var near: CreatureSim = null
		var best := float(spec["scare"])
		for c in scary:
			var d := p.distance_to(c.pos)
			if d < best:
				best = d
				near = c
		if near != null:
			var away := (p - near.pos).normalized() if p != near.pos else Vector2.RIGHT
			f["v"] = away * float(spec["flee"])
			f["afraid"] = 40
			f["rest"] = 0
			f["to"] = _far_target(near.pos, f)
		if int(f["afraid"]) > 0:
			_scared_now += 1
			f["afraid"] = int(f["afraid"]) - 1
		if int(f["rest"]) > 0:
			f["rest"] = int(f["rest"]) - 1  # settled on a leaf
			if int(f["rest"]) == 0:
				f["to"] = _spot(f)
			if near == null:
				continue
		var to: Vector2 = f["to"]
		var dir := to - p
		var speed := float(spec["speed"]) if int(f["afraid"]) == 0 else float(spec["fear"])
		if dir.length() < 4.0 and int(f["afraid"]) == 0:
			var rr: Array = spec["rest"]
			f["rest"] = int(rr[0]) + _rng.randi() % maxi(1, int(rr[1]) - int(rr[0]) + 1)
			f["v"] = Vector2.ZERO
			_over_dirty = true
			continue
		var wob := float(spec["wob"])
		var want := dir.normalized() * speed + Vector2(0.0, wob * sin(float(t) * 0.23 + float(f["ph"]))) \
			+ Vector2(wob * 0.8 * sin(float(t) * 0.11 + float(f["ph"]) * 2.0), 0.0)
		f["v"] = (f["v"] as Vector2).lerp(want, 0.12)
		f["p"] = p + (f["v"] as Vector2)
		_over_dirty = true
	if scary.is_empty():
		_scared_now = 0


## Somewhere to flee to: a bed well away from the fighter (or just away).
func _far_target(from: Vector2, f: Dictionary) -> Vector2:
	if String(f["k"]) != "butterfly":
		var pick := _spot(f)
		for i in 3:
			var q := _spot(f)
			if q.distance_to(from) > pick.distance_to(from):
				pick = q
		return pick
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
	var mw := int(_mote_kind.get("w", 1))
	var ma := float(_mote_kind.get("alpha", 0.7))
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
			col.a = ma
			ci.draw_rect(Rect2(px, py, mw, 1), col)
	_draw_fish(ci, view)
	_draw_scraps(ci, view, true)
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
	var y := roundi(p.y) - int(FLY_KINDS[f["k"]]["lift"])  # flying above the leaves
	var col: Color = f["col"]
	var rest := int(f["rest"]) > 0
	if String(f["k"]) == "dragonfly":
		_draw_dragonfly(ci, f, x, y, t)
		return
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


func _draw_dragonfly(ci: CanvasItem, f: Dictionary, x: int, y: int, t: int) -> void:
	var col: Color = f["col"]
	var dir := -1 if (f["v"] as Vector2).x < -0.05 else 1
	var flap := ((t / 2) + int(float(f["ph"]) * 2.0)) % 2 == 0
	ci.draw_rect(Rect2(x, roundi((f["p"] as Vector2).y), 1, 1), Color(0, 0, 0, 0.18))  # its shadow below
	ci.draw_rect(Rect2(x - 1, y, 3, 1), col)
	ci.draw_rect(Rect2(x + dir * 2, y, 1, 1), col.lightened(0.4))
	var wing := Color(0.92, 0.97, 1.0, 0.6)
	if flap:
		ci.draw_rect(Rect2(x - 1, y - 1, 3, 1), wing)
	else:
		ci.draw_rect(Rect2(x, y - 2, 1, 1), wing)
		ci.draw_rect(Rect2(x, y + 1, 1, 1), wing)


# ------------------------------------------------------------------ life: birds, fish, devil, grit, confetti

var _vis := Rect2()  ## the part of the floor in view (spawns go here)


func _life(t: int, view: Rect2) -> void:
	if _crit.is_empty() and not _cfg.has("grit") and not _cfg.has("confetti"):
		return
	_vis = view.intersection(_floor.grow(60.0))
	if _crit.has("bird"):
		_move_birds(t)
	if _crit.has("fish"):
		_move_fish(t)
	if _crit.has("devil"):
		_move_devil(t)
	if _cfg.has("grit"):
		_move_grit(t)
	if _cfg.has("confetti"):
		_move_scraps(t)


func _jitter(every: int) -> int:
	return int(float(every) * (0.6 + _rng.randf() * 0.8))


# -- birds: a few tiny dark shapes crossing high over the arena now and then

func spawn_flock() -> void:
	var bc: Dictionary = _crit.get("bird", {})
	var vis := _vis if _vis.has_area() else _floor
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	var y := vis.position.y + vis.size.y * (0.04 + 0.5 * _rng.randf())
	var x := vis.position.x - 24.0 if dir > 0.0 else vis.end.x + 24.0
	var speed := 0.7 + _rng.randf() * 0.5
	for i in int(bc.get("flock", 3)):
		_birds.append({"p": Vector2(x - dir * float(i) * 11.0, y + float((i % 2) * 6) + _rng.randf() * 4.0),
			"v": Vector2(dir * speed, _rng.randf_range(-0.03, 0.03)), "age": 0, "ph": _rng.randf() * TAU})
	_sky_dirty = true


func _move_birds(t: int) -> void:
	var bc: Dictionary = _crit["bird"]
	if t >= _bird_next and _vis.has_area():
		_bird_next = t + _jitter(int(bc.get("every", 1500)))
		spawn_flock()
	if _birds.is_empty():
		return
	var keep := _vis.grow(160.0)
	var i := 0
	while i < _birds.size():
		var b: Dictionary = _birds[i]
		b["age"] = int(b["age"]) + 1
		b["p"] += (b["v"] as Vector2) + Vector2(0.0, 0.1 * sin(float(b["age"]) * 0.05 + float(b["ph"])))
		if int(b["age"]) > 3000 or (int(b["age"]) > 120 and not keep.has_point(b["p"])):
			_birds.remove_at(i)
		else:
			i += 1
	_sky_dirty = true


func _paint_sky(ci: CanvasItem) -> void:
	if sim == null or _birds.is_empty():
		return
	var view := FxView._view_rect(self, CULL_PAD)
	var bc: Dictionary = _crit.get("bird", {})
	var span := int(bc.get("span", 2))
	var col := Color(0.07, 0.08, 0.11, float(bc.get("alpha", 0.42)))
	for b in _birds:
		var p: Vector2 = b["p"]
		if not view.has_point(p):
			continue
		var x := roundi(p.x)
		var y := roundi(p.y)
		var up := ((int(b["age"]) / 9) + int(float(b["ph"]) * 2.0)) % 2 == 0
		var w := 1 if up else -1  # wing tips raised or lowered
		ci.draw_rect(Rect2(x, y, 1, 1), col)
		for k in range(1, span + 1):
			var dy := w if k == span else 0
			ci.draw_rect(Rect2(x - k, y - dy, 1, 1), col)
			ci.draw_rect(Rect2(x + k, y - dy, 1, 1), col)


# -- fish: one leaps out of the shallows now and then (never beside a fighter the team sees)

## Starts a jump at shallows cell `i` if it is open water and no seen fighter is near.
func try_jump(i: int) -> bool:
	var cols := _terrain.cols
	if i < cols or i >= _terrain.cells.size() - cols:
		return false
	for n in [i, i - 1, i + 1, i - cols, i + cols]:
		if _terrain.cells[n] != TerrainGrid.SHALLOWS:
			return false
	var c := _terrain.cell_center(Vector2i(i % cols, i / cols))
	for k in sim.creatures:
		if k.state != CreatureSim.State.KO and c.distance_to(k.pos) < 40.0 and _seen(k):
			return false
	var dx := 1.0 if _rng.randf() < 0.5 else -1.0
	_fish.append({"p": c - Vector2(dx * 4.0, 0.0), "dx": dx, "t": 0, "dur": 30})
	_splash.append({"p": c - Vector2(dx * 4.0, 0.0), "t": 0})
	_over_dirty = true
	_low_dirty = true
	return true


func _move_fish(t: int) -> void:
	var fc: Dictionary = _crit["fish"]
	if t >= _fish_next and not _shallows.is_empty() and _vis.has_area():
		_fish_next = t + _jitter(int(fc.get("every", 300)))
		for tries in 8:
			var j := _shallows[_rng.randi() % _shallows.size()]
			var c := _terrain.cell_center(Vector2i(j % _terrain.cols, j / _terrain.cols))
			if _vis.has_point(c) and try_jump(j):
				break
	var i := 0
	while i < _fish.size():
		var f: Dictionary = _fish[i]
		f["t"] = int(f["t"]) + 1
		f["p"] += Vector2(float(f["dx"]) * 0.28, 0.0)
		if int(f["t"]) >= int(f["dur"]):
			_splash.append({"p": f["p"], "t": 0})
			_fish.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _splash.size():
		var s: Dictionary = _splash[i]
		s["t"] = int(s["t"]) + 1
		if int(s["t"]) > 14:
			_splash.remove_at(i)
		else:
			i += 1
	if not _fish.is_empty():
		_over_dirty = true
	if not _fish.is_empty() or not _splash.is_empty():
		_low_dirty = true


func _draw_fish(ci: CanvasItem, view: Rect2) -> void:
	for f in _fish:
		var p: Vector2 = f["p"]
		if not view.has_point(p):
			continue
		var u := float(f["t"]) / float(f["dur"])
		var z := 11.0 * 4.0 * u * (1.0 - u)
		var dx := int(f["dx"])
		var x := roundi(p.x)
		var y := roundi(p.y - z)
		var head := -1 if u < 0.5 else 1  # nose up on the way up, down on the way back
		ci.draw_rect(Rect2(x - 1, y, 3, 1), Color8(190, 208, 222))
		ci.draw_rect(Rect2(x - 1, y - 1, 2, 1), Color8(120, 150, 176))
		ci.draw_rect(Rect2(x + dx * 2, y + head, 1, 1), Color8(214, 228, 238))
		ci.draw_rect(Rect2(x - dx * 2, y - head, 1, 2), Color8(150, 176, 198))


# -- dust devil: a small swirl that wanders across the floor, then fades

func _move_devil(t: int) -> void:
	var dc: Dictionary = _crit["devil"]
	if _devil.is_empty():
		if t >= _devil_next and _vis.has_area():
			_devil_next = t + _jitter(int(dc.get("every", 1500)))
			var dir := 1.0 if _rng.randf() < 0.5 else -1.0
			_devil = {"p": _vis.position + Vector2(_rng.randf(), _rng.randf()) * _vis.size,
				"v": Vector2(dir * (0.18 + _rng.randf() * 0.14), _rng.randf_range(-0.08, 0.08)),
				"age": 0, "life": int(dc.get("life", 420)), "ph": _rng.randf() * TAU}
		return
	_devil["age"] = int(_devil["age"]) + 1
	var a := float(_devil["age"])
	_devil["p"] += (_devil["v"] as Vector2) + Vector2(0.12 * sin(a * 0.04 + float(_devil["ph"])), 0.05 * sin(a * 0.06))
	if int(_devil["age"]) >= int(_devil["life"]):
		_devil = {}
	_low_dirty = true


func _draw_devil(ci: CanvasItem, view: Rect2) -> void:
	var p: Vector2 = _devil["p"]
	if not view.grow(20.0).has_point(p):
		return
	var age := float(_devil["age"])
	var env := minf(1.0, minf(age / 60.0, (float(_devil["life"]) - age) / 60.0))
	var t := float(sim.tick)
	var n := int(30.0 * env)
	for k in n:
		var h := float(k) * 1.0
		var r := 2.0 + h * 0.4
		var ang := t * 0.33 + h * 0.8
		var col := DUST_LIGHT if k % 2 == 0 else DUST_DARK
		col.a = env * (0.85 - float(k) * 0.015)
		var q := Vector2(roundi(p.x + cos(ang) * r), roundi(p.y - h + sin(ang) * r * 0.4))
		ci.draw_rect(Rect2(q, Vector2(2, 1)), col)
		if k % 3 == 0:
			ci.draw_rect(Rect2(roundi(p.x - cos(ang) * r), roundi(p.y - h - sin(ang) * r * 0.4), 1, 1), col)
	var base := DUST_DARK
	base.a = env * 0.4
	ci.draw_rect(Rect2(roundi(p.x) - 4, roundi(p.y), 9, 1), base)
	base.a = env * 0.2
	ci.draw_rect(Rect2(roundi(p.x) - 2, roundi(p.y) + 1, 5, 1), base)


# -- grit: a thin trickle off the rubble walls that puffs at the foot

func _move_grit(t: int) -> void:
	var gc: Dictionary = _cfg["grit"]
	if t >= _grit_next and not _walls.is_empty() and _vis.has_area():
		_grit_next = t + _jitter(int(gc.get("every", 70)))
		for tries in 6:
			var j := _walls[_rng.randi() % _walls.size()]
			var cx := SimDefs.GRID_X + (j % _terrain.cols) * SimDefs.CELL
			var cy := SimDefs.GRID_Y + (j / _terrain.cols) * SimDefs.CELL
			if _vis.has_point(Vector2(cx + 4, cy + 4)):
				_streams.append({"p": Vector2(cx + 1 + _rng.randi() % 6, cy + 7), "z": 6.0 + _rng.randf() * 8.0,
					"left": 4 + _rng.randi() % 8})
				break
	var n := 0
	var i := 0
	while i < _streams.size():
		var s: Dictionary = _streams[i]
		if t % 3 == 0:
			_grit.append({"p": (s["p"] as Vector2) + Vector2(_rng.randf() - 0.5, 0.0), "z": s["z"], "vz": 0.0,
				"puff": -1, "col": GRIT_COLORS[_rng.randi() % GRIT_COLORS.size()]})
			s["left"] = int(s["left"]) - 1
		if int(s["left"]) <= 0:
			_streams.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _grit.size():
		var g: Dictionary = _grit[i]
		if int(g["puff"]) < 0:
			g["vz"] = float(g["vz"]) + 0.07
			g["z"] = float(g["z"]) - float(g["vz"])
			if float(g["z"]) <= 0.0:
				g["z"] = 0.0
				g["puff"] = 0
		else:
			g["puff"] = int(g["puff"]) + 1
		if int(g["puff"]) > 10:
			_grit.remove_at(i)
		else:
			i += 1
		n += 1
	if n > 0:
		_low_dirty = true


func _draw_grit(ci: CanvasItem, view: Rect2) -> void:
	for g in _grit:
		var p: Vector2 = g["p"]
		if not view.has_point(p):
			continue
		var col: Color = g["col"]
		var puff := int(g["puff"])
		var x := roundi(p.x)
		var y := roundi(p.y)
		if puff < 0:
			ci.draw_rect(Rect2(x, y - roundi(float(g["z"])), 1, 1), col)
		else:
			col.a = 0.6 * (1.0 - float(puff) / 11.0)
			var r := puff / 3 + 1
			ci.draw_rect(Rect2(x - r, y - r / 2, 1, 1), col)
			ci.draw_rect(Rect2(x + r, y - r / 2, 1, 1), col)
			ci.draw_rect(Rect2(x, y - r, 1, 1), col)


# -- confetti: paper scraps fall from the stands after a knockout or a Surge

func burst(n: int) -> void:
	var cc: Dictionary = _cfg.get("confetti", {})
	var cap := int(cc.get("cap", CONFETTI_CAP))
	var vis := _vis if _vis.has_area() else _floor
	for i in n:
		if _scraps.size() >= cap:
			break
		var y := vis.position.y - _rng.randf() * 24.0
		_scraps.append({"p": Vector2(vis.position.x + _rng.randf() * vis.size.x, y),
			"v": Vector2(_rng.randf_range(-0.12, 0.12), 0.3 + _rng.randf() * 0.25),
			"ty": maxf(y + 30.0, vis.position.y + _rng.randf() * vis.size.y), "rest": -1,
			"ph": _rng.randf() * TAU, "col": CONFETTI_COLORS[_rng.randi() % CONFETTI_COLORS.size()]})
	_over_dirty = true
	_low_dirty = true


func _move_scraps(t: int) -> void:
	var cc: Dictionary = _cfg["confetti"]
	var on: Array = cc.get("on", ["ko", "surge"])
	for e in sim.events:
		var kind := String(e.get("type", ""))
		if kind in on:
			burst(40 if kind == "ko" else 28)
	if _scraps.is_empty():
		return
	var i := 0
	while i < _scraps.size():
		var s: Dictionary = _scraps[i]
		if int(s["rest"]) < 0:
			s["p"] += (s["v"] as Vector2) + Vector2(0.3 * sin(float(t) * 0.07 + float(s["ph"])), 0.0)
			if (s["p"] as Vector2).y >= float(s["ty"]):
				s["rest"] = 90 + _rng.randi() % 140
		else:
			s["rest"] = int(s["rest"]) - 1
		if int(s["rest"]) == 0:
			_scraps.remove_at(i)
		else:
			i += 1
	_over_dirty = true
	_low_dirty = true


## `falling` scraps go above the fighters; the ones lying on the floor go under them.
func _draw_scraps(ci: CanvasItem, view: Rect2, falling: bool) -> void:
	var t := sim.tick
	for s in _scraps:
		var down := int(s["rest"]) < 0
		if down != falling:
			continue
		var p: Vector2 = s["p"]
		if not view.has_point(p):
			continue
		var col: Color = s["col"]
		var x := roundi(p.x)
		var y := roundi(p.y)
		if down:
			col.a = 0.85
			if ((t / 6) + int(float(s["ph"]) * 3.0)) % 2 == 0:
				ci.draw_rect(Rect2(x, y, 2, 1), col)
			else:
				ci.draw_rect(Rect2(x, y, 1, 2), col.darkened(0.15))
		else:
			if int(s["rest"]) < 24 and int(s["rest"]) % 4 < 2:
				continue
			col.a = 0.6
			ci.draw_rect(Rect2(x, y, 2, 1), col)


func _paint_low(ci: CanvasItem) -> void:
	if sim == null:
		return
	var view := FxView._view_rect(self, CULL_PAD)
	for s in _splash:
		var p: Vector2 = s["p"]
		if not view.has_point(p):
			continue
		var r := int(s["t"]) / 3 + 1
		var col := Color(0.9, 0.97, 1.0, 0.55 * (1.0 - float(s["t"]) / 15.0))
		var x := roundi(p.x)
		var y := roundi(p.y)
		ci.draw_rect(Rect2(x - r, y, 1, 1), col)
		ci.draw_rect(Rect2(x + r, y, 1, 1), col)
		ci.draw_rect(Rect2(x - r / 2, y - r / 2 - 1, 1, 1), col)
		ci.draw_rect(Rect2(x + r / 2, y - r / 2 - 1, 1, 1), col)
	if not _devil.is_empty():
		_draw_devil(ci, view)
	_draw_grit(ci, view)
	_draw_scraps(ci, view, false)
