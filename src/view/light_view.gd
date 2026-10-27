class_name LightView
extends Node2D
## Glow (Settings > Video): glowing things light the floor around them and get a soft halo,
## so the arena feels lit. Two of these: the floor pool layer (main puts it over the
## shadows, under the fighters) gathers the lights each tick; its `halo` twin (over the
## effects) draws the same lights as small halos where the glowing thing is, which also
## lights a fighter standing in one a little. Both draw additively.
##
## Not real lights or a blur: each light is one pre-made radial picture, stepped into a
## few levels and dithered between them (`_tex`), drawn whole-pixel at one texel per
## world pixel, so a pool reads as pixel art and the sprites under it stay crisp. A
## frame costs a few dozen textured quads, whatever the map.
##
## What glows, all read from the sim and the effects (never written):
##   - A fighter with the Surge ready: a pool in its aura colour, pulsing on the tick,
##     flaring when the meter fills (SurgeAura `burst_t`).
##   - A move's `fx.light` while it runs: {"color", "radius", "strength", "from", "to",
##     "ahead" (px along the facing), "height" (px over the floor), "charge" (true: only
##     while held, growing with the charge), "halo" (how much shows as a halo too, default
##     0.5)}. Headlamp Flash, Stone Gaze, Tenderize's
##     psychic charge, Flavor Blast.
##   - A projectile thrown by a move with `fx.projectile_light`: {"color", "radius",
##     "strength"}, following it (Chef Cerebro's kitchen, Hissy's venom).
##   - Bright effect particles: hit sparks, bursts, glints, and bright rings, streaks and
##     lines (`_part_light`), fading with them.
## Hidden foes never glow: a fighter `fx.shown` hides, or one in stealth (Tiptoe, Burrow),
## gives no light, a projectile only
## where FxView would draw it, and particles only exist for what the local team saw.
## With Lighting Low or High, Light2DView gathers through `gather` instead and hands this layer
## its lights (`show_lights`): the halos draw them all, the floor only `pools`, the ones it didn't
## make real floor lights (so nothing is lit twice).

const MAX_LIGHTS := 40  ## after merging; the rest are dropped (dimmest go first)
const MERGE_CELL := 20.0  ## lights this close merge into one (a burst of sparks is one pool)
const LEVELS := 5  ## brightness steps in a pool
## 4x4 ordered dither, for the step between two levels.
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const POOL_ALPHA := 1.0  ## the floor pool's strength, against a light's own
const HALO_ALPHA := 0.7
const HALO_SIZE := 0.45  ## a halo's radius, against the pool's
## A glow must never hide a fighter: a halo stays small and faint however big or bright the
## light (a big light's reach goes into the floor pool instead).
const HALO_MAX_R := 16.0
const HALO_MAX_ALPHA := 0.22
const POOL_MAX_ALPHA := 0.4  ## and a pool never bleaches the floor

var fx: FxView
var halo := false
var source: LightView = null  ## the halo layer draws its floor twin's lights
## Gathered each tick: [floor pos, height, colour, radius, strength, halo share, surge (a
## Surge's light: Light2DView makes these real first), age (ticks it has shone: newest first)].
var lights: Array = []
## The floor pools to draw, when Lighting (Light2DView) chose them: the lights it didn't make
## real floor lights (`show_lights`); null draws every light (Lighting Off, own gather).
var pools = null
var _tick := 0

## The pool sizes (radius in px): one picture each, made once when the game starts.
const SIZES: Array[int] = [4, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96]
static var _cache := {}


func _init() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


func _ready() -> void:
	if _cache.is_empty():
		for r in SIZES:  # all up front: building one mid-fight would be a hitch
			_cache[r] = _build(r)


## A white disc of radius `r` (whole pixels) that falls off in LEVELS dithered steps.
static func _build(r: int) -> Texture2D:
	var n := r * 2
	var data := PackedByteArray()
	data.resize(n * n * 2)
	var i := 0
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length() / float(r)
			var f := clampf(1.0 - d, 0.0, 1.0)
			f = f * (1.6 - 0.6 * f)  # a broad pool, brightest in the middle
			var v := f * LEVELS
			var lo := floorf(v)
			if v - lo > (BAYER[(y % 4) * 4 + x % 4] + 0.5) / 16.0:
				lo += 1.0
			data[i] = 255
			data[i + 1] = int(round(255.0 * minf(lo, LEVELS) / LEVELS))
			i += 2
	return ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_LA8, data))


static func _tex(r: int) -> Texture2D:
	if not _cache.has(r):
		_cache[r] = _build(r)
	return _cache[r]


## The nearest of SIZES, so a handful of pictures serve every light.
static func _bucket(r: float) -> int:
	var best := SIZES[0]
	for sz in SIZES:
		if absf(sz - r) < absf(best - r):
			best = sz
	return best


func clear() -> void:
	lights.clear()
	queue_redraw()


## Once a tick (main, after fx.advance): gather this tick's lights.
func advance() -> void:
	if halo or fx == null or fx.sim == null:
		return
	var t0 := PerfLog.now()
	if fx.time_scale > 0.0:
		_tick += 1
	var raw: Array = []
	gather(raw)
	lights = _merge(raw)
	pools = null
	queue_redraw()
	PerfLog.since("glow gather", t0)


## Everything that glows this tick, unmerged (Light2DView gathers through this too).
func gather(raw: Array) -> void:
	_creature_lights(raw)
	_projectile_lights(raw)
	_particle_lights(raw)


## Lighting on (Light2DView gathered them): `all` for the halos, `floor_pools` the pools still drawn
## (the rest light the floor as real lights, so nothing is lit twice).
func show_lights(all: Array, floor_pools: Array) -> void:
	lights = all
	pools = floor_pools
	queue_redraw()


## `halo`: how much of it shows as a halo too (1 for a small bright thing; a fighter's
## aura lights the floor, and only washes faintly over the fighter, or the sprite would
## go pale).
func _add(raw: Array, pos: Vector2, z: float, col: Color, r: float, s: float, halo_share := 1.0,
		surge := false, age := 0) -> void:
	if s > 0.01 and r >= 2.0:
		raw.append([pos, z, col, r, s, halo_share, surge, age])


## A light seen at `drawn` (where the effect draws), `h` px over the floor under it.
func _add_drawn(raw: Array, drawn: Vector2, h: float, col: Color, r: float, s: float, age := 0) -> void:
	_add(raw, drawn + Vector2(0, h), h, col, r, s, 1.0, false, age)


func _creature_lights(raw: Array) -> void:
	var view := FxView._view_rect(self, 160.0)
	for c in fx.sim.creatures:
		if not fx.shown(c) or not view.has_point(c.pos):
			continue  # out of sight: no glow gives it away
		if c.state == CreatureSim.State.FALLING or c.swallow_t > 0:
			continue
		if c.stealth > 0:
			continue  # invisible (Tiptoe) or underground (Burrow): Vision doesn't hide it, the glow mustn't show it
		var top := maxf(24.0, float(c.def.get("fx_top", 32)))
		if SurgeAura.is_ready(c):
			var col := _aura_color(c)
			var pulse := 0.04 if (_tick / 8) % 2 == 0 else 0.0  # stepped, on the tick
			_add(raw, c.pos, top * 0.5, col, 52.0, 0.34 + pulse, 0.12, true)
			var aura := _aura(c)
			if aura != null and aura.burst_t >= 0:
				var k := float(aura.burst_t) / float(SurgeAura.BURST_TICKS)
				_add(raw, c.pos, top * 0.5, col, 88.0, 0.6 * (1.0 - k), 0.2, true)
		if c.state != CreatureSim.State.ATTACK:
			continue
		var mv := c.move_def()
		var li: Dictionary = mv.get("fx", {}).get("light", {})
		if li.is_empty():
			continue
		var s := float(li.get("strength", 0.5))
		if bool(li.get("charge", false)):
			if not c.charging:
				continue
			s *= 0.35 + 0.65 * c.charge_ratio
		else:
			var from := int(li.get("from", int(mv.get("startup", 0))))
			var to := int(li.get("to", from + maxi(1, int(mv.get("active", 1)))))
			if c.state_t < from or c.state_t > to:
				continue
			var k := float(c.state_t - from) / float(maxi(1, to - from))
			if k > 0.6:
				s *= 1.0 - (k - 0.6) / 0.4 * 0.8  # dims out over the last part
		var at := c.pos + c.facing * float(li.get("ahead", 0.0))
		_add(raw, at, float(li.get("height", top * 0.5)), Color(String(li.get("color", _fx_color(c)))),
			float(li.get("radius", 40.0)), s, float(li.get("halo", 0.5)), c.move_type() == "surge", c.state_t)


func _projectile_lights(raw: Array) -> void:
	for pr in fx.sim.projectiles:
		var owner := fx._creature(int(pr["owner"]))
		if owner == null or not pr.has("move"):
			continue
		var pp: Vector2 = pr["pos"]
		if not fx.shown(owner) and not fx.sight_to(pp):
			continue  # FxView doesn't draw it either
		var mv: Dictionary = owner.moves().get(String(pr["move"]), {})
		var li: Dictionary = mv.get("fx", {}).get("projectile_light", {})
		if li.is_empty():
			continue
		var z := FxView.THROW_Z if String(mv.get("fx", {}).get("projectile", "")) in ["knife", "mallet", "cleaver"] \
			else 10.0
		var age := int(pr.get("life_total", 0)) - int(pr.get("life", 0)) if pr.has("life_total") else 0
		_add(raw, pp, z, Color(String(li.get("color", _fx_color(owner)))), float(li.get("radius", 24.0)),
			float(li.get("strength", 0.45)), 1.0, false, maxi(0, age))


func _particle_lights(raw: Array) -> void:
	var view := FxView._view_rect(self, 64.0)
	for p in fx._parts:
		var pos = p.get("pos")
		if pos is Vector2 and not view.has_point(pos):
			continue
		_part_light(raw, p)


## The light a bright particle gives while it lasts, fading as it does.
func _part_light(raw: Array, p: Dictionary) -> void:
	var life := float(p.get("life", 1.0))
	var k := clampf(float(p.get("t", 0.0)) / maxf(1.0, life), 0.0, 1.0)
	var fade := 1.0 - k
	var age := int(p.get("t", 0.0))
	match String(p["kind"]):
		"spark":  # the white flash of a heavy hit
			_add_drawn(raw, p["pos"], 8.0, FxView.C_SPARK[1], 26.0 * float(p.get("scale", 1.0)), 0.5 * fade, age)
		"burst":
			var col: Color = p["color"]
			_add_drawn(raw, p["pos"], 8.0, col, float(p["r1"]) * 1.6, 0.4 * fade, age)
		"glint":
			_add_drawn(raw, p["pos"], 6.0, p["color"], 14.0, 0.45 * fade, age)
		"ring":
			var col: Color = p.get("color", Color.BLACK)  # (an uncoloured ring is dust, not light)
			if _bright(col) and col.s >= 0.25:
				_add_drawn(raw, p["pos"], 0.0, col, float(p["radius"]) + 8.0, 0.3 * col.a * fade, age)
		"streak":
			var col: Color = p["color"]
			if _bright(col):
				var a: Vector2 = p["a"]
				var b: Vector2 = p["b"]
				_add_drawn(raw, a.lerp(b, 0.6), 6.0, col, maxf(12.0, a.distance_to(b) * 0.6), 0.3 * col.a * fade, age)
		"lines":
			var col: Color = p["color"]
			if _bright(col):
				_add_drawn(raw, p["pos"], 6.0, col, 18.0 * float(p.get("size", 1.0)), 0.3 * fade, age)
		"suck":  # Tenderize's violet sparks drawn in
			var col: Color = p.get("color", Color.WHITE)
			if col.s > 0.3 and col.v > 0.8:
				_add_drawn(raw, p["to"], 10.0, col, 16.0, 0.12 * fade, age)


## Coloured or white-hot, not grey dust or stone.
static func _bright(col: Color) -> bool:
	return col.v >= 0.8 and (col.s >= 0.25 or col.v >= 0.95)


## Lights in the same cell merge (strength adds up, to 1; colour by strength; the
## widest reach), then the strongest MAX_LIGHTS are kept.
func _merge(raw: Array) -> Array:
	var cells := {}
	for l in raw:
		var key := Vector2i(floori(Vector2(l[0]).x / MERGE_CELL), floori(Vector2(l[0]).y / MERGE_CELL))
		if not cells.has(key):
			cells[key] = l.duplicate()
			continue
		var m: Array = cells[key]
		var s0 := float(m[4])
		var s1 := float(l[4])
		var w := s1 / maxf(0.001, s0 + s1)
		m[0] = Vector2(m[0]).lerp(l[0], w)
		m[1] = lerpf(float(m[1]), float(l[1]), w)
		m[2] = Color(m[2]).lerp(l[2], w)
		m[3] = maxf(float(m[3]), float(l[3]))
		m[4] = minf(1.0, s0 + s1)
		m[5] = lerpf(float(m[5]), float(l[5]), w)
		if m.size() > 7 and l.size() > 7:
			m[6] = bool(m[6]) or bool(l[6])
			m[7] = mini(int(m[7]), int(l[7]))
	var out: Array = cells.values()
	if out.size() > MAX_LIGHTS:
		out.sort_custom(func(a, b): return float(a[4]) > float(b[4]))
		out.resize(MAX_LIGHTS)
	return out


func _aura(c: CreatureSim) -> SurgeAura:
	if c.id >= 0 and c.id < fx.views.size():
		var v: CreatureView = fx.views[c.id]
		if v != null and v.c == c:
			return v.aura
	return null


func _aura_color(c: CreatureSim) -> Color:
	var a := _aura(c)
	if a != null and a.colors.size() >= 2:
		return a.colors[1]
	return Color(_fx_color(c))


static func _fx_color(c: CreatureSim) -> String:
	return String(c.def.get("fx_color", "#ffcf3f"))


func _draw() -> void:
	var t0 := PerfLog.now()
	var list: Array = source.lights if halo and source != null else (pools if pools != null else lights)
	for l in list:
		var pos: Vector2 = l[0]
		var z := float(l[1])
		var col: Color = l[2]
		var s := float(l[4])
		var r: int
		var at: Vector2
		if halo:
			r = _bucket(minf(float(l[3]) * HALO_SIZE, HALO_MAX_R))
			at = pos - Vector2(0, z)
			col.a = minf(s * HALO_ALPHA * float(l[5]), HALO_MAX_ALPHA)
			if col.a < 0.02:
				continue
		else:
			r = _bucket(float(l[3]))
			at = pos
			col.a = minf(s * POOL_ALPHA / (1.0 + z / 60.0), POOL_MAX_ALPHA)  # a light up high lights the floor less
		draw_texture(_tex(r), (at - Vector2(r, r)).round(), col)
	PerfLog.since("glow draw", t0)
