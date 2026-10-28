class_name GladeView
extends Node2D
## The life round a map's trees and keeps (the arena JSON `ambient.glades` block; Twin Keeps):
## dappled leaf shade under every crown, faint sun shafts through them by day, fireflies and a
## warm glow round the glades at sunset only, leaves dropping from the crowns, thin smoke off
## the lamps (`lights` with `"lamp": true`), spray and mist where the waterfall meets the
## river, ripples on the river, and (the Floodgate) bubbles rising in the shallows and a
## low mist lying over them at night. View only: it reads the sim (fighters' positions, the
## terrain) and never writes it; everything moves on its own clock (`_vt`, a count of
## `advance` calls), not the sim's tick.
##
##   "glades": {"pools": 7, "shafts": 2, "fireflies": 16, "leaf_every": 80, "smoke": true,
##              "spray": [col, row, w, h], "ripple_every": 40, "bubble_every": 50,
##              "mist": {"areas": [[col, row, w, h], ...], "count": 12, "times": ["night"]}}
##
## Lighting (`set_look`): Off draws no shade, shafts, glow, low mist or bubbles (the leaves,
## smoke, spray and fireflies stay: they are critters, not light); Low draws the shade and the
## mist still (no drift) and no shafts; High lets the shade and mist drift and adds the shafts
## by day.
## Hidden foes: a firefly only scatters from a fighter the local team sees (`fx.shown`), and
## nothing spawns over the HUD's corners (`hud_rects`, screen px) or on a wall or fence cell.
##
## Layers: `shade` (dapple, ripples, the sunset glow) sits under the fighters (main adds it
## after AmbientView, before the shadows); `air` (fireflies, leaves, smoke, spray, mist) and
## `shafts` (additive) above them, at z 1, tiny and faint so they never hide play.

const POOL_ALPHA := 0.17
const FLECK_ALPHA := 0.09
const SHAFT_ALPHA := 0.08
const GLOW_ALPHA := 0.07
const SHADE_STEP := 4  ## view ticks between the drifting shade's redraws (High)
const LEAF_CAP := 14
const SMOKE_CAP := 72
const SPRAY_CAP := 40
const RIPPLE_CAP := 6
const BUBBLE_CAP := 6
const BUBBLE_LIFE := 44  ## view ticks: a bead swelling at the surface, then a ring as it pops
const MIST_ALPHA := 0.075
const FLY_SCARE := 26.0
const SHADE_COL := Color(0.05, 0.11, 0.09)
const FLECK_COL := Color(1.0, 0.95, 0.72)
const SHAFT_COL := Color(1.0, 0.9, 0.66)
const GLOW_COL := Color(1.0, 0.62, 0.3)
const FIREFLY_COL := Color(1.0, 0.94, 0.5)
const LEAF_COLS: Array[Color] = [Color8(96, 140, 60), Color8(150, 170, 80), Color8(176, 128, 60)]

var sim: MatchSim
var fx = null  ## FxView: who the local team sees (`shown`)
var tier := 2  ## Light2DView.Tier: OFF 0, LOW 1, HIGH 2
var time := "day"
## Screen rects the HUD covers (main sets the corners and the bottom line): nothing spawns
## under them, so no critter sits behind a bar.
var hud_rects: Array = []
var shade: Node2D
var water: Node2D  ## the river's ripples, under the fighters, redrawn only while one spreads
var air: Node2D
var shafts: Node2D

var _cfg := {}
var _crowns: Array = []  ## world rects
var _pools: Array = []  ## {p, r, ph, fleck}
var _flies: Array = []  ## {p, home, ph, v}
var _leaves: Array = []  ## {p, z, vz, ph, life, col}
var _smoke: Array = []  ## {p, life, max}
var _spray: Array = []  ## {p, z, vz, life}
var _mist: Array = []  ## {p, ph}
var _ripples: Array = []  ## {p, t}
var _bubbles: Array = []  ## {p, t}
var _low_mist: Array = []  ## {p, ph, w}: puffs lying over the water (`mist`), at its times only
var _mist_times: Array = []
var _lamps: Array = []  ## world points of the lamps that smoke
var _spray_rect := Rect2()
var _shallows := PackedInt32Array()
var _vt := 0
var _ripples_drawn := false
var _leaf_next := 60
var _ripple_next := 30
var _bubble_next := 20
var _rng := RandomNumberGenerator.new()


class Paint extends Node2D:
	var paint: Callable
	var label := ""

	func _draw() -> void:
		var t0 := PerfLog.now()
		paint.call(self)
		PerfLog.since(label, t0)


## A hard-edged white ellipse, made once: every pool, glow and mist puff is this texture
## drawn tinted, so a layer is one batch instead of a draw call per shape.
static var _blob: Texture2D = null


static func blob() -> Texture2D:
	if _blob == null:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				img.set_pixel(x, y, Color(1, 1, 1, 1) if d <= 1.0 else Color(1, 1, 1, 0))
		_blob = ImageTexture.create_from_image(img)
	return _blob


## Draws `blob` as an ellipse of radii `rx`, `ry` round `c`, tinted.
static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_texture_rect(blob(), Rect2((c - Vector2(rx, ry)).round(), Vector2(rx, ry).round() * 2.0), false, col)


func _init() -> void:
	shade = _paint_layer(_paint_shade)
	water = _paint_layer(_paint_water)
	air = _paint_layer(_paint_air)
	air.z_index = 1
	shafts = _paint_layer(_paint_shafts)
	shafts.z_index = 1
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	shafts.material = add


func _paint_layer(f: Callable) -> Paint:
	var p := Paint.new()
	p.paint = f
	p.label = "glade " + f.get_method().trim_prefix("_paint_")
	add_child(p)
	return p


## A new match: the map's `ambient.glades` block, the crowns' world rects (ArenaView
## `canopy_rects`), its lamps and its water. A map without the block draws nothing.
func set_sim(s: MatchSim, crowns: Array) -> void:
	sim = s
	_cfg = (s.arena.get("ambient", {}) as Dictionary).get("glades", {})
	_crowns = crowns.duplicate()
	_rng.seed = 2710
	_vt = 0
	_leaves.clear()
	_smoke.clear()
	_spray.clear()
	_ripples.clear()
	_bubbles.clear()
	_low_mist.clear()
	_pools.clear()
	_flies.clear()
	_mist.clear()
	_lamps.clear()
	visible = not _cfg.is_empty()
	if _cfg.is_empty():
		return
	var n := int(_cfg.get("pools", 7))
	for r: Rect2 in _crowns:
		var mid := shade_mid(r)
		for i in n:
			var a := _rng.randf() * TAU
			var d := sqrt(_rng.randf())
			_pools.append({"p": mid + Vector2(cos(a) * r.size.x * 0.45, sin(a) * r.size.y * 0.3) * d,
				"ph": _rng.randf() * TAU, "fleck": i % 3 == 2})
			var rad := 3.0 + _rng.randf() * 5.0
			var pl: Dictionary = _pools[_pools.size() - 1]
			pl["size"] = (Vector2(maxf(1.5, rad * 0.4), maxf(1.0, rad * 0.25)) if pl["fleck"] else Vector2(rad, rad * 0.55)).round()
	if bool(_cfg.get("smoke", false)):
		for e in s.arena.get("lights", []):
			if e is Dictionary and bool(e.get("lamp", false)):
				_lamps.append(Vector2(float(e["pos"][0]), float(e["pos"][1])))
	var sp: Array = _cfg.get("spray", [])
	if sp.size() == 4:
		_spray_rect = Rect2(SimDefs.GRID_X + int(sp[0]) * SimDefs.CELL, SimDefs.GRID_Y + int(sp[1]) * SimDefs.CELL,
			int(sp[2]) * SimDefs.CELL, int(sp[3]) * SimDefs.CELL)
		for i in 6:
			_mist.append({"p": _spray_rect.position + Vector2(_rng.randf(), _rng.randf()) * _spray_rect.size, "ph": _rng.randf() * TAU})
	var lm: Dictionary = _cfg.get("mist", {})
	_mist_times = lm.get("times", ["night"])
	var areas: Array = lm.get("areas", [])
	var n_mist := int(lm.get("count", 0)) if not areas.is_empty() else 0
	for i in n_mist:
		var a: Array = areas[i % areas.size()]
		var r := Rect2(SimDefs.GRID_X + int(a[0]) * SimDefs.CELL, SimDefs.GRID_Y + int(a[1]) * SimDefs.CELL,
			int(a[2]) * SimDefs.CELL, int(a[3]) * SimDefs.CELL)
		_low_mist.append({"p": r.position + Vector2(_rng.randf(), _rng.randf()) * r.size, "ph": _rng.randf() * TAU,
			"w": 9.0 + _rng.randf() * 7.0})
	_shallows = PackedInt32Array()
	for i in s.terrain.map_base.size():
		if s.terrain.map_base[i] == TerrainGrid.SHALLOWS:
			_shallows.append(i)
	_make_fireflies()
	_redraw()


## Where a crown's shade falls (world px): on the ground below and in front of its lower edge,
## round the trunk's foot, the light being high and from the back.
static func shade_mid(r: Rect2) -> Vector2:
	return Vector2(r.get_center().x, r.end.y + r.size.y * 0.22)


## The time of day and the Lighting tier (main `_light_look`): fireflies come out at sunset
## only; the shade and shafts follow the tier.
func set_look(p_time: String, p_tier: int) -> void:
	time = p_time
	tier = p_tier
	_make_fireflies()
	_redraw()


func _make_fireflies() -> void:
	_flies.clear()
	if sim == null or _cfg.is_empty() or time != "sunset" or _crowns.is_empty():
		return
	var tries := 0
	while _flies.size() < int(_cfg.get("fireflies", 16)) and tries < 400:
		tries += 1
		var r: Rect2 = _crowns[_rng.randi() % _crowns.size()]
		var p := Vector2(r.position.x + _rng.randf() * r.size.x, r.end.y - r.size.y * 0.1 + (_rng.randf() - 0.5) * 30.0)
		if _spot_ok(p):
			_flies.append({"p": p, "home": p, "ph": _rng.randf() * TAU, "v": Vector2.ZERO})


## Whether a critter may appear at world point `p`: on the map's floor, not on a wall or
## fence cell (it would sit on the barrier), and not under the HUD.
func _spot_ok(p: Vector2) -> bool:
	if sim == null:
		return false
	var t := sim.terrain
	var c := Vector2i(floori((p.x - SimDefs.GRID_X) / SimDefs.CELL), floori((p.y - SimDefs.GRID_Y) / SimDefs.CELL))
	if c.x < 0 or c.y < 0 or c.x >= t.cols or c.y >= t.rows:
		return false
	var v := t.map_base[c.y * t.cols + c.x]
	if v == TerrainGrid.WALL or v == TerrainGrid.FENCE:
		return false
	return not under_hud(p)


## Whether world point `p` falls on one of the HUD's screen rects (in a tree: through the
## canvas transform; out of one, as tests do, world px are screen px).
func under_hud(p: Vector2) -> bool:
	if hud_rects.is_empty():
		return false
	var s := p
	if is_inside_tree():
		s = get_global_transform_with_canvas() * p
	for r: Rect2 in hud_rects:
		if r.has_point(s):
			return true
	return false


func firefly_count() -> int:
	return _flies.size()


func leaf_count() -> int:
	return _leaves.size()


func smoke_count() -> int:
	return _smoke.size()


## Shade pools drawn now (0 with Lighting Off or no crowns).
func pool_count() -> int:
	return 0 if tier == 0 else _pools.size()


func bubble_count() -> int:
	return _bubbles.size()


## Low mist puffs drawn now: the map's `mist` at its times, none with Lighting Off.
func mist_count() -> int:
	return 0 if tier == 0 or not time in _mist_times else _low_mist.size()


func fireflies() -> Array:
	return _flies.map(func(f): return f["p"])


func leaves() -> Array:
	return _leaves.map(func(l): return l["p"])


## Once a tick (main, beside AmbientView.advance): the view clock steps, everything moves.
func advance() -> void:
	if sim == null or _cfg.is_empty():
		return
	_vt += 1
	var view := FxView._view_rect(self, 32.0)
	_move_flies()
	_move_leaves(view)
	_move_smoke(view)
	_move_water(view)
	if _vt % 2 == 0 and (not _flies.is_empty() or not _leaves.is_empty() or not _smoke.is_empty() or not _spray.is_empty() or not _mist.is_empty()):
		air.queue_redraw()  # every other tick: smoke and leaves move a fraction of a pixel a tick
	if tier == 2 and _vt % SHADE_STEP == 0:
		shade.queue_redraw()
		shafts.queue_redraw()
	if not _ripples.is_empty() or not _bubbles.is_empty() or _ripples_drawn:
		water.queue_redraw()
		_ripples_drawn = not _ripples.is_empty() or not _bubbles.is_empty()


func _redraw() -> void:
	shade.queue_redraw()
	water.queue_redraw()
	air.queue_redraw()
	shafts.queue_redraw()


func _seen_near(p: Vector2, r: float) -> CreatureSim:
	for c in sim.creatures:
		if c.state != CreatureSim.State.KO and c.pos.distance_to(p) < r and (fx == null or fx.shown(c)):
			return c
	return null


func _move_flies() -> void:
	for f in _flies:
		var p: Vector2 = f["p"]
		var c := _seen_near(p, FLY_SCARE)
		if c != null:
			f["v"] = (p - c.pos).normalized() * 0.9
		else:
			var home: Vector2 = f["home"]
			var ph := float(f["ph"])
			var want := (home + Vector2(sin(_vt * 0.013 + ph) * 10.0, cos(_vt * 0.017 + ph * 1.3) * 6.0)) - p
			f["v"] = (f["v"] as Vector2).lerp(want * 0.03, 0.1)
		var q: Vector2 = p + f["v"]
		if _spot_ok(q):
			f["p"] = q


func _move_leaves(view: Rect2) -> void:
	if _vt >= _leaf_next and not _crowns.is_empty() and _leaves.size() < LEAF_CAP:
		_leaf_next = _vt + int(float(_cfg.get("leaf_every", 80)) * (0.5 + _rng.randf()))
		var r: Rect2 = _crowns[_rng.randi() % _crowns.size()]
		var p := Vector2(r.position.x + r.size.x * (0.2 + 0.6 * _rng.randf()), r.end.y - r.size.y * 0.15)
		if view.has_point(p) and _spot_ok(p):
			_leaves.append({"p": p, "z": r.size.y * (0.3 + 0.3 * _rng.randf()), "vz": 0.0, "ph": _rng.randf() * TAU,
				"life": 260, "col": LEAF_COLS[_rng.randi() % LEAF_COLS.size()]})
	var i := 0
	while i < _leaves.size():
		var l: Dictionary = _leaves[i]
		l["life"] = int(l["life"]) - 1
		if float(l["z"]) > 0.0:
			l["z"] = maxf(0.0, float(l["z"]) - 0.22)
			l["p"] += Vector2(0.12 + 0.35 * sin(_vt * 0.07 + float(l["ph"])), 0.02)
		if int(l["life"]) <= 0:
			_leaves.remove_at(i)
		else:
			i += 1


func _move_smoke(view: Rect2) -> void:
	if _vt % 9 == 0:
		for p: Vector2 in _lamps:
			if _smoke.size() < SMOKE_CAP and view.has_point(p):
				_smoke.append({"p": p + Vector2(_rng.randf_range(-1.0, 1.0), -3.0), "life": 0, "max": 44 + _rng.randi() % 16})
	var i := 0
	while i < _smoke.size():
		var s: Dictionary = _smoke[i]
		s["life"] = int(s["life"]) + 1
		s["p"] += Vector2(0.08 + 0.12 * sin(_vt * 0.05 + float(i)), -0.28)
		if int(s["life"]) >= int(s["max"]):
			_smoke.remove_at(i)
		else:
			i += 1


func _move_water(view: Rect2) -> void:
	if _spray_rect.has_area() and view.intersects(_spray_rect):
		if _vt % 3 == 0 and _spray.size() < SPRAY_CAP:
			_spray.append({"p": _spray_rect.position + Vector2(_rng.randf() * _spray_rect.size.x, _spray_rect.size.y * (0.4 + 0.6 * _rng.randf())),
				"z": 0.0, "vz": 0.6 + _rng.randf() * 0.7, "life": 0})
	var i := 0
	while i < _spray.size():
		var s: Dictionary = _spray[i]
		s["life"] = int(s["life"]) + 1
		s["z"] = float(s["z"]) + float(s["vz"])
		s["vz"] = float(s["vz"]) - 0.08
		s["p"] += Vector2(0.15, 0.0)
		if float(s["z"]) < 0.0 or int(s["life"]) > 30:
			_spray.remove_at(i)
		else:
			i += 1
	var every := int(_cfg.get("ripple_every", 0))
	if every > 0 and _vt >= _ripple_next and not _shallows.is_empty() and _ripples.size() < RIPPLE_CAP:
		_ripple_next = _vt + int(every * (0.5 + _rng.randf()))
		var j := _shallows[_rng.randi() % _shallows.size()]
		var c := sim.terrain.cell_center(Vector2i(j % sim.terrain.cols, j / sim.terrain.cols))
		if view.has_point(c) and sim.terrain.cells[j] == TerrainGrid.SHALLOWS and _seen_near(c, 24.0) == null:
			_ripples.append({"p": c + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)), "t": 0})
	i = 0
	while i < _ripples.size():
		var r: Dictionary = _ripples[i]
		r["t"] = int(r["t"]) + 1
		if int(r["t"]) > 36:
			_ripples.remove_at(i)
		else:
			i += 1
	# bubbles rising in the shallows (not with Lighting Off), never beside a fighter we see
	var b_every := int(_cfg.get("bubble_every", 0))
	if b_every > 0 and tier > 0 and _vt >= _bubble_next and not _shallows.is_empty() and _bubbles.size() < BUBBLE_CAP:
		_bubble_next = _vt + int(b_every * (0.5 + _rng.randf()))
		var j := _shallows[_rng.randi() % _shallows.size()]
		var c := sim.terrain.cell_center(Vector2i(j % sim.terrain.cols, j / sim.terrain.cols))
		if view.has_point(c) and sim.terrain.cells[j] == TerrainGrid.SHALLOWS and _seen_near(c, 24.0) == null:
			_bubbles.append({"p": c + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)), "t": 0})
	i = 0
	while i < _bubbles.size():
		var b: Dictionary = _bubbles[i]
		b["t"] = int(b["t"]) + 1
		if int(b["t"]) > BUBBLE_LIFE or tier == 0:
			_bubbles.remove_at(i)
		else:
			i += 1


# ------------------------------------------------------------------ drawing

## Under the fighters: the leaf shade under each crown (drifting with the sway on High),
## the sunset's warm glow round the glades, ripples on the river.
func _paint_shade(ci: CanvasItem) -> void:
	if sim == null:
		return
	var view := FxView._view_rect(ci, 24.0)
	if tier > 0:
		var drift := tier == 2
		var dark := Color(SHADE_COL, POOL_ALPHA)
		var lit := Color(FLECK_COL, FLECK_ALPHA)
		var tex := blob()
		for pl: Dictionary in _pools:
			var p: Vector2 = pl["p"]
			if not view.has_point(p):
				continue
			if drift:
				var ph: float = pl["ph"]
				p += Vector2(roundf(1.5 * sin(_vt * 0.021 + ph)), roundf(sin(_vt * 0.017 + ph * 1.7)))
			var rr: Vector2 = pl["size"]
			ci.draw_texture_rect(tex, Rect2((p - rr).round(), rr * 2.0), false, lit if pl["fleck"] else dark)
		if time == "sunset":
			for r: Rect2 in _crowns:
				var mid := shade_mid(r)
				if view.has_point(mid):
					_ellipse(ci, mid, r.size.x * 0.55, r.size.x * 0.27, Color(GLOW_COL, GLOW_ALPHA))
		if time in _mist_times:
			# low mist over the water: long flat puffs, drifting slowly on High, still on Low
			var col := Color(0.86, 0.94, 1.0, MIST_ALPHA)
			for m: Dictionary in _low_mist:
				var p: Vector2 = m["p"]
				if drift:
					var ph := float(m["ph"])
					p += Vector2(roundf(6.0 * sin(_vt * 0.006 + ph)), roundf(1.5 * sin(_vt * 0.009 + ph * 1.3)))
				if view.has_point(p):
					var w := float(m["w"])
					_ellipse(ci, p, w, w * 0.32, col)



## Under the fighters: ripples spreading on the river, bubbles surfacing and popping.
func _paint_water(ci: CanvasItem) -> void:
	for bb in _bubbles:
		var p: Vector2 = bb["p"]
		var t := int(bb["t"])
		var x := roundi(p.x)
		var y := roundi(p.y)
		if t < BUBBLE_LIFE - 8:
			# a bead swelling at the surface: a pale pixel, then two with a glint
			var a := 0.35 + 0.4 * float(t) / float(BUBBLE_LIFE)
			ci.draw_rect(Rect2(x, y, 2 if t > 16 else 1, 1), Color(0.9, 0.97, 1.0, a))
			if t > 16:
				ci.draw_rect(Rect2(x, y - 1, 1, 1), Color(1.0, 1.0, 1.0, a))
		else:
			# the pop: a tiny ring of four pixels, fading
			var col := Color(0.88, 0.96, 1.0, 0.5 * float(BUBBLE_LIFE - t) / 8.0)
			ci.draw_rect(Rect2(x - 1, y, 1, 1), col)
			ci.draw_rect(Rect2(x + 2, y, 1, 1), col)
			ci.draw_rect(Rect2(x, y - 1, 2, 1), col)
			ci.draw_rect(Rect2(x, y + 1, 2, 1), col)
	for rp in _ripples:
		var p: Vector2 = rp["p"]
		var t := int(rp["t"])
		var rad := 1 + t / 6
		var a := 0.45 * (1.0 - float(t) / 37.0)
		var x := roundi(p.x)
		var y := roundi(p.y)
		var col := Color(0.88, 0.96, 1.0, a)
		ci.draw_rect(Rect2(x - rad, y, 1, 1), col)
		ci.draw_rect(Rect2(x + rad, y, 1, 1), col)
		ci.draw_rect(Rect2(x - rad / 2, y - (rad + 1) / 2, rad, 1), col)
		ci.draw_rect(Rect2(x - rad / 2, y + (rad + 1) / 2, rad, 1), col)


## Above the fighters, faint: fireflies (sunset), falling leaves, smoke, spray and mist.
func _paint_air(ci: CanvasItem) -> void:
	if sim == null:
		return
	var view := FxView._view_rect(ci, 24.0)
	for f in _flies:
		var p: Vector2 = f["p"]
		if not view.has_point(p):
			continue
		var blink := (_vt + int(float(f["ph"]) * 20.0)) % 70
		if blink > 44:
			continue
		var x := roundi(p.x)
		var y := roundi(p.y) - 6
		ci.draw_rect(Rect2(x - 1, y - 1, 3, 3), Color(FIREFLY_COL, 0.22))
		ci.draw_rect(Rect2(x, y, 1, 1), FIREFLY_COL)
	for l in _leaves:
		var p: Vector2 = l["p"]
		if not view.has_point(p):
			continue
		var col: Color = l["col"]
		if int(l["life"]) < 40:
			col.a = float(l["life"]) / 40.0
		var up := roundi(float(l["z"]))
		var flip := (_vt / 6 + int(float(l["ph"]) * 3.0)) % 2 == 0 and up > 0
		ci.draw_rect(Rect2(roundi(p.x), roundi(p.y) - up, 1 if flip else 2, 1), col)
	for s in _smoke:
		var p: Vector2 = s["p"]
		if not view.has_point(p):
			continue
		var u := float(s["life"]) / float(s["max"])
		var a := 0.22 * (1.0 - u)
		var w := 1 if u < 0.4 else 2
		ci.draw_rect(Rect2(roundi(p.x), roundi(p.y), w, w), Color(0.78, 0.76, 0.74, a))
	for s in _spray:
		var p: Vector2 = s["p"]
		ci.draw_rect(Rect2(roundi(p.x), roundi(p.y - float(s["z"])), 1, 1), Color(0.95, 0.99, 1.0, 0.75))
	for m in _mist:
		var p: Vector2 = (m["p"] as Vector2) + Vector2(4.0 * sin(_vt * 0.01 + float(m["ph"])), -2.0 * absf(sin(_vt * 0.013 + float(m["ph"]))))
		if view.has_point(p):
			_ellipse(ci, p, 8.0, 5.0, Color(0.92, 0.97, 1.0, 0.07))


## Additive, by day on High only: two faint shafts of sun slanting down from each crown's
## top left (the maps' light), swelling and fading slowly; none at sunset.
func _paint_shafts(ci: CanvasItem) -> void:
	if sim == null or tier != 2 or time != "day":
		return
	var view := FxView._view_rect(ci, 40.0)
	var n := int(_cfg.get("shafts", 2))
	for k in _crowns.size():
		var r: Rect2 = _crowns[k]
		if not view.intersects(r):
			continue
		for j in n:
			var x0 := r.position.x + r.size.x * (0.3 + 0.35 * j)
			var top := Vector2(x0, r.position.y + r.size.y * 0.35)
			var bot := top + Vector2(r.size.y * 0.35, r.size.y * 0.75)
			var w := 4.0 + 3.0 * j
			var a := SHAFT_ALPHA * (0.6 + 0.4 * sin(_vt * 0.01 + k * 1.7 + j))
			ci.draw_colored_polygon(PackedVector2Array([top, top + Vector2(w, 0), bot + Vector2(w, 0), bot]), Color(SHAFT_COL, a))
