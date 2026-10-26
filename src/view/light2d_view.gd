class_name Light2DView
extends Node2D
## Real 2D lights (Settings > Video > Lighting): Godot PointLight2Ds that light the fighters
## per pixel through their normal sheets (CreatureView puts a
## sheet's `_n.png` beside it in a CanvasTexture), and at night light the floor through the
## weather's multiply layer. Views only: it reads the sim, the arena JSON and the weather,
## never writes back.
##
## Three tiers (`tier`, main's `lighting` setting):
##   - OFF: no lights at all; the look is the baked one (WeatherView's light map at night,
##     LightView's dithered pools for Glow).
##   - LOW: the sun on the fighters by day, and a ready Surge's and a move's `fx.light`
##     lighting the fighter sprites (the Glow pools still light the floor). Night keeps the
##     baked light map.
##   - HIGH: LOW, plus the arena's `lights` (data/arenas/<id>.json) at night: each lamp lights
##     the floor (through WeatherView's flat night shade, which takes the light: `FLOOR_MASK`)
##     and the fighters standing near it (from above, `height`), instead of the baked pools;
##     the furniture lamp heads under a `lamp` glow (FurnitureView.set_lit), and the moon.
##     Bloom (BloomView) is on in this tier only.
##
## Light masks: a light lights only canvas items whose `light_mask` shares a bit with its
## `range_item_cull_mask`. Everything in the game keeps the default mask (1), which no light
## here uses, so floor art, effects, telegraphs and bars keep their exact colours. Fighter
## sprites carry `FIGHTER_MASK`; the night shade carries `FLOOR_MASK`.
##
## The sun: a DirectionalLight2D would be the natural fit, but on the Compatibility renderer
## (Godot 4.7.2) it ignores `range_item_cull_mask` and lights every canvas item, the HUD
## included, so the sun is one wide PointLight2D per fighter instead (`_suns`), set back
## along the shadows' light from the fighter, wide enough to be even across the sprite. Each
## lights its own fighter only (`SUN_BIT`). Its colour and strength are the arena's and the
## look's (`sun_of`); at night it is the moon, on HIGH only (`sun_at`).
##
## Hidden foes never light anything: the moving lights are gathered by a LightView's own
## `_creature_lights` (fighters `fx.shown` passes and not in stealth only), capped at
## `MAX_DYNAMIC`. Gathered once a tick, no interpolation.

enum Tier {OFF, LOW, HIGH}

const FIGHTER_MASK := 2  ## fighter sprites (CreatureView.sprite.light_mask)
const FLOOR_MASK := 4  ## the night shade over the floor (WeatherView.shade.light_mask)
const MAX_DYNAMIC := 8  ## Surge and move lights at once (the strongest)
const TEX_SIZE := 256  ## the radial light texture, built once
## A lamp without `fighter_energy` lights the fighters near it with this share of its floor
## energy (their palette is already bright: a lamp should model them, not bleach them).
const FIGHTER_SHARE := 0.2
## How far up the screen a lamp's fighter light sits, against its `height` (it hangs over
## the pool, so it lights a fighter from above, not from the feet).
const LAMP_LIFT := 0.4
## A moving light (Surge, `fx.light`) on the fighters: energy per unit of its strength, and
## how far in front of the sprite it sits (Godot's light height, px), so it lights the face
## turned to the camera most and the sides a little.
const DYNAMIC_ENERGY := 1.4
const DYNAMIC_HEIGHT := 28.0
## The sun (by day; low, warm and stronger at sunset; the moon at night), per arena and look
## (`sun_of`): the arena's `light.sun` {color, energy} (else `SUN_DEFAULT`), times the time
## of day's `sun` block in data/weather.json ({color: replaces the arena's, energy: a
## multiplier, height: its elevation, 0 grazing .. 1 straight down the camera, shade: how
## much the rest of a fighter is dimmed, `WeatherView.fighter_scale`, so the side away from
## it reads as shade, matching the cast shadow}) and the weather's `sun.energy` (overcast: a
## softer sun, and a softer shade with it). A time without a `sun` block has none.
const SUN_DEFAULT := {"color": "#fff6e8", "energy": 0.34}
const SUN_BACK := 80.0  ## a fighter's sun sits this far back along the light (screen px)
const SUN_RADIUS := 360.0  ## and reaches this far, so it is near even across a sprite
const MAX_SUNS := 8  ## one per fighter on screen (4v4)
## Each fighter's sun lights that fighter only: sun i lights light-mask bit `SUN_BIT << i`
## and the fighter it follows carries that bit (`CreatureView.sun_bit`), so in a crowd the
## suns never stack on one sprite (nor push it past the 15 lights Godot draws on one canvas item).
const SUN_BIT := 8
## The most floor lights an arena's `lights` may list (the rest are dropped with a warning):
## a big map can be all on screen at once, and every lamp lights the night shade, one canvas
## item (Godot draws at most 15 lights on an item; measured). A lamp with `fighter_energy` 0 (a lamp
## head on a tower or a torch) gives no fighter light.
const MAX_LAMPS := 15
## A furniture lamp head (FurnitureView floodlight, worklight, torch) glows when a lit
## `"lamp": true` light sits within this of it (`lamp_heads`).
const HEAD_NEAR := 16.0

var tier := Tier.HIGH
var fx: FxView
var sim: MatchSim
## This tick's moving lights, as LightView gathers them: [floor pos, height, colour, radius,
## strength, halo share]; at most MAX_DYNAMIC.
var dynamic: Array = []
## The arena's lamps lit this match (HIGH, at night), parsed: {pos, color, radius, energy,
## height, fighter_color, fighter_energy, lamp}.
var lamps: Array = []
var _suns: Array[PointLight2D] = []
var _sun := {}  ## this match's sun: {dir, color, energy, height}; empty without one or Off
## Main's CreatureViews (shared): each seen fighter's sun bit goes on its sprite. Without
## them (tests) every sun lights `FIGHTER_MASK`.
var views: Array = []
var _gather := LightView.new()
var _pool: Array[PointLight2D] = []
var _lamp_lights: Array[PointLight2D] = []
static var _tex: Texture2D = null
static var _pool_tex: Texture2D = null
## A lamp's floor pool keeps full strength out to this share of its radius (`pool`).
const POOL_CORE := 0.55


func _ready() -> void:
	_gather.visible = false  # used only to gather lights, never drawn
	add_child(_gather)
	for i in MAX_DYNAMIC:
		var l := _point(FIGHTER_MASK)
		l.height = DYNAMIC_HEIGHT
		l.enabled = false
		_pool.append(l)
	for i in MAX_SUNS:
		var l := _point(FIGHTER_MASK)
		l.texture_scale = SUN_RADIUS * 2.0 / TEX_SIZE
		l.enabled = false
		_suns.append(l)


func _point(mask: int) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = radial()
	l.range_item_cull_mask = mask
	l.range_z_min = -4096
	l.range_z_max = 4096
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.shadow_enabled = false
	add_child(l)
	return l


## A smooth radial falloff, white in the middle to black at the edge (opaque: black adds
## nothing), falling off on a smoothstep (lights add, unlike the baked pools' flat tops,
## so a pool must fade right out at its edge), and a 4x4 ordered dither of one 8-bit step so the gradient
## doesn't band on the SDR screen.
static func radial() -> Texture2D:
	if _tex == null:
		_tex = _falloff(0.0)
	return _tex


## A lamp's pool on the floor: `radial`'s falloff with a flat bright core (`POOL_CORE` of the
## radius), so a floodlight reads as a pool with an edge, like the baked ones, not a haze.
static func pool() -> Texture2D:
	if _pool_tex == null:
		_pool_tex = _falloff(POOL_CORE)
	return _pool_tex


static func _falloff(core: float) -> Texture2D:
	var n := TEX_SIZE
	var r := n * 0.5
	var data := PackedByteArray()
	data.resize(n * n)
	var i := 0
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length() / r
			var f := clampf((1.0 - d) / (1.0 - core), 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)  # smoothstep: lights add up, so the edge must fade right out
			var v: float = f * 255.0 + (LightView.BAYER[(y % 4) * 4 + x % 4] + 0.5) / 16.0 - 0.5
			data[i] = clampi(int(floorf(v + 0.5)), 0, 255) if f > 0.0 else 0
			i += 1
	var img := Image.create_from_data(n, n, false, Image.FORMAT_L8, data)
	img.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)


## For a new match (main, after WeatherView.apply): the sun from the shadows' light and the
## time of day, the lamps from the arena at night (HIGH only).
func apply(s: MatchSim, look: Dictionary, cast: Vector2) -> void:
	sim = s
	_gather.fx = fx
	dynamic.clear()
	lamps.clear()
	for l in _lamp_lights:
		l.queue_free()
	_lamp_lights.clear()
	var t := String(look.get("time", "day"))
	var w := String(look.get("weather", "clear"))
	# the sun (or the moon)
	var sd := sun_at(s.arena, t, w, tier)
	_sun = {}
	if not sd.is_empty():
		var dir := cast.normalized() if cast.length() > 0.001 else Vector2.DOWN
		_sun = {"dir": dir, "color": sd["color"], "energy": sd["energy"],
			"height": SUN_BACK * float(sd["height"]) / maxf(0.05, 1.0 - float(sd["height"]))}
		for l in _suns:
			l.color = _sun["color"]
			l.energy = _sun["energy"]
			l.height = _sun["height"]
	# the lamps
	if tier == Tier.HIGH and lamps_on(s.arena, t):
		for e in s.arena.get("lights", []):
			if not e is Dictionary:
				continue
			if lamps.size() >= MAX_LAMPS:
				push_warning("%s: more than %d lights, the rest dropped" % [s.arena.get("id", "?"), MAX_LAMPS])
				break
			var lamp := lamp_of(e)
			lamps.append(lamp)
			_lamp_lights.append(_lamp_light(lamp, FLOOR_MASK))
			if float(lamp["fighter_energy"]) > 0.0:
				_lamp_lights.append(_lamp_light(lamp, FIGHTER_MASK))
	_sync()


## The sun this tier shows: none when Off, and a time's sun marked `high_only` (the moon:
## Low keeps the night exactly as it was) only on High.
static func sun_at(arena: Dictionary, time: String, weather: String, t: int) -> Dictionary:
	var sd := sun_of(arena, time, weather)
	if t == Tier.OFF or (bool(sd.get("high_only", false)) and t != Tier.HIGH):
		return {}
	return sd


## The sun on `arena` at `time` in `weather` (see SUN_DEFAULT): {color, energy, height, shade,
## high_only}, or empty when the time has none.
static func sun_of(arena: Dictionary, time: String, weather: String) -> Dictionary:
	var d := WeatherView.data()
	var tm: Dictionary = ((d.get("times", {}) as Dictionary).get(time, {}) as Dictionary).get("sun", {})
	if tm.is_empty():
		return {}
	var base: Dictionary = SUN_DEFAULT.duplicate()
	base.merge((arena.get("light", {}) as Dictionary).get("sun", {}), true)
	var wm := float((((d.get("weathers", {}) as Dictionary).get(weather, {}) as Dictionary).get("sun", {}) as Dictionary).get("energy", 1.0))
	var shade := float(tm.get("shade", 1.0))
	return {"color": Color(String(tm.get("color", base["color"]))),
		"energy": float(base["energy"]) * float(tm.get("energy", 1.0)) * wm,
		"height": float(tm.get("height", 0.45)),
		"shade": 1.0 - (1.0 - shade) * minf(1.0, wm), "high_only": bool(tm.get("high_only", false))}


## Where the lit lamp heads are this match (the `"lamp": true` lamps): FurnitureView lights
## the floodlight, worklight and torch heads within HEAD_NEAR of one.
func lamp_heads() -> Array:
	var out: Array = []
	for lp in lamps:
		if bool(lp["lamp"]):
			out.append(lp["pos"])
	return out


## One `lights` entry of an arena JSON, with its defaults (docs/MECHANICS.md, "Arena lights").
static func lamp_of(e: Dictionary) -> Dictionary:
	var p: Array = e.get("pos", [0, 0])
	var col := Color(String(e.get("color", "#fff2d8")))
	var energy := float(e.get("energy", 2.5))
	return {"pos": Vector2(float(p[0]), float(p[1])), "color": col, "radius": float(e.get("radius", 120.0)),
		"energy": energy, "height": float(e.get("height", 80.0)),
		"fighter_color": Color(String(e.get("fighter_color", col.to_html(false)))),
		"fighter_energy": float(e.get("fighter_energy", energy * FIGHTER_SHARE)),
		"lamp": bool(e.get("lamp", false))}


## Whether this arena's `lights` replace the baked light map: HIGH, a time with floodlights
## (night), and an arena that lists them.
static func lamps_on(arena: Dictionary, time: String) -> bool:
	if (arena.get("lights", []) as Array).is_empty():
		return false
	var tm: Dictionary = (WeatherView.data().get("times", {}) as Dictionary).get(time, {})
	return tm.has("floodlights")


## One lamp as a light: on the floor (FLOOR_MASK) a pool at `pos`; on the fighters
## (FIGHTER_MASK) the same lamp seen from its height, so it lights them from above.
func _lamp_light(lamp: Dictionary, mask: int) -> PointLight2D:
	var l := _point(mask)
	l.texture_scale = float(lamp["radius"]) * 2.0 / TEX_SIZE
	if mask == FLOOR_MASK:
		l.texture = pool()
	if mask == FIGHTER_MASK:
		l.position = Vector2(lamp["pos"]) - Vector2(0, float(lamp["height"]) * LAMP_LIFT)
		l.height = float(lamp["height"])
		l.color = lamp["fighter_color"]
		l.energy = float(lamp["fighter_energy"])
	else:
		l.position = lamp["pos"]
		l.color = lamp["color"]
		l.energy = float(lamp["energy"])
	return l


func clear() -> void:
	dynamic.clear()
	_sync()


## Once a tick (main, after the effects): gather the moving lights and place the pool.
func advance() -> void:
	if tier == Tier.OFF or fx == null or fx.sim == null:
		if not dynamic.is_empty():
			clear()
		_place_suns()
		return
	var t0 := PerfLog.now()
	_gather.fx = fx
	if fx.time_scale > 0.0:
		_gather._tick += 1
	var raw: Array = []
	_gather._creature_lights(raw)
	take(raw)
	_place_suns()
	PerfLog.since("light2d gather", t0)


## This tick's moving lights (LightView's format): merged by cell, the strongest
## MAX_DYNAMIC kept, and the pool placed on them.
func take(raw: Array) -> void:
	var merged := _gather._merge(raw)
	if merged.size() > MAX_DYNAMIC:
		merged.sort_custom(func(a, b): return float(a[4]) > float(b[4]))
		merged.resize(MAX_DYNAMIC)
	dynamic = merged
	_sync()


## Puts the pool's lights where `dynamic` says; the rest off.
func _sync() -> void:
	for i in _pool.size():
		var l := _pool[i]
		if i >= dynamic.size() or tier == Tier.OFF:
			l.enabled = false
			continue
		var d: Array = dynamic[i]
		l.enabled = true
		l.position = (Vector2(d[0]) - Vector2(0, float(d[1]))).round()
		l.color = d[2]
		l.energy = float(d[4]) * DYNAMIC_ENERGY
		l.texture_scale = maxf(8.0, float(d[3])) * 2.0 / TEX_SIZE


## The sun behind each fighter the local team sees (a hidden one gets none: nothing of it
## shows, its light included).
func _place_suns() -> void:
	var i := 0
	var by_c := {}
	for o in views:
		if is_instance_valid(o) and (o as CreatureView).c != null:
			by_c[(o as CreatureView).c] = o
			(o as CreatureView).set_sun_bit(0)
	if not _sun.is_empty() and fx != null and fx.sim != null:
		for c in fx.sim.creatures:
			if i >= _suns.size():
				break
			if not fx.shown(c) or c.stealth > 0:
				continue
			var top := maxf(24.0, float(c.def.get("fx_top", 32)))
			_suns[i].position = (c.pos - Vector2(0, top * 0.5) - Vector2(_sun["dir"]) * SUN_BACK).round()
			_suns[i].enabled = true
			if by_c.has(c):  # this sun lights its own fighter only
				_suns[i].range_item_cull_mask = SUN_BIT << i
				(by_c[c] as CreatureView).set_sun_bit(SUN_BIT << i)
			else:
				_suns[i].range_item_cull_mask = FIGHTER_MASK
			i += 1
	for k in range(i, _suns.size()):
		_suns[k].enabled = false


## How many point lights are on now (moving ones, suns, lamps).
func lights_on() -> int:
	var n := 0
	for l in _pool + _suns:
		if l.enabled:
			n += 1
	return n + _lamp_lights.size()


## The suns on now (tests).
func suns_on() -> int:
	var n := 0
	for l in _suns:
		if l.enabled:
			n += 1
	return n
