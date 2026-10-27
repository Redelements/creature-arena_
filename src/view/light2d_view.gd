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
##   - LOW: the sun on the fighters by day, and the first `LOW_DYNAMIC` fight lights (`take`)
##     real, on the fighters and the floor; Glow's dithered pools light the floor
##     for the rest. Night keeps the baked light map. No halos are lost: Glow still draws them.
##   - HIGH: LOW with `MAX_DYNAMIC` fight lights, plus the arena's `lights`
##     (data/arenas/<id>.json) at night: each lamp lights
##     the floor (through WeatherView's flat night shade, which takes the light: `FLOOR_MASK`)
##     and the fighters standing near it (from above, `height`), instead of the baked pools;
##     the furniture lamp heads under a `lamp` glow (FurnitureView.set_lit), and the moon.
##     Bloom (BloomView) is on in this tier only, and stands in for Glow's halos (main hides
##     them), so nothing glows twice.
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
## `gather` (fighters `fx.shown` passes and not in stealth, projectiles where FxView draws
## them, particles spawned only for what was seen), capped at `MAX_DYNAMIC`. Gathered once a
## tick, no interpolation.
##
## The fight's lights (`take`): everything Glow gathers (a ready Surge, a move's `fx.light`, a
## projectile's `fx.projectile_light`, bright particles) plus short flashes on big hits and
## Surges (`on_event`, stepped on the tick), merged by cell and again when closer than
## `REAL_MERGE`, then chosen by priority: Surge first, then nearest the camera's centre (in
## `FOCUS_BAND` rings), then newest. High makes `MAX_DYNAMIC` of them real, Low `LOW_DYNAMIC`.
## Each real one is a fighter light (FIGHTER_MASK, up at its height) and a floor light
## (`GLOW_MASK`, on the floor under it). The floor light shines on `FloorGlow`, a black rect
## at Glow's floor-pool depth that adds only the light falling on it (its shader's `light()`),
## so it brightens the floor by day and night alike, under a lamp too (the night shade only
## multiplies, so a light on it can't lift a lamp-lit floor). `gathered` is every light (the
## bloom's and Glow's halos' source), `pools` the ones Glow's dithered floor pools still draw
## (those not made real), so no floor is lit twice. Main hands both to Glow's LightView
## (`show_lights`) instead of it gathering.

enum Tier {OFF, LOW, HIGH}

const FIGHTER_MASK := 2  ## fighter sprites (CreatureView.sprite.light_mask)
const FLOOR_MASK := 4  ## the night shade over the floor (WeatherView.shade.light_mask)
const GLOW_MASK := 2048  ## FloorGlow: the fight lights on the floor (bit 11: above the suns' SUN_BIT << 0..7)
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
const LOW_DYNAMIC := 2  ## Low: the fight lights made real (the rest stay Glow's pools)
const REAL_MERGE := 40.0  ## real candidates this close share one light
const MIN_REAL := 0.06  ## fainter than this stays a pool (a spark's last ticks)
const FOCUS_BAND := 128.0  ## distance from the camera's centre counts in rings this wide
## A real light on the floor (FloorGlow, added to the picture as Glow's pools are): energy per
## unit of strength, less for a light up high (as a pool: 1 + height / 60), at most FLOOR_MAX
## (a pool never bleaches the floor), and its reach against the light's radius (the smooth
## falloff fades sooner than a dithered pool).
const FLOOR_ENERGY := 1.2
const FLOOR_MAX := 0.5
const FLOOR_REACH := 1.3
## Flashes (`on_event`): a heavy hit dealing at least FLASH_HIT_MIN, and a Surge starting.
## [radius, strength, ticks]; the strength steps down every FLASH_STEP ticks.
const FLASH_HIT := [64.0, 0.75, 8]
const FLASH_SURGE := [96.0, 0.9, 12]
const FLASH_HIT_MIN := 10.0
const FLASH_STEP := 2
const MAX_FLASHES := 6
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
## Every light gathered this tick (merged, LightView.MAX_LIGHTS at most): bloom and halos.
var gathered: Array = []
## The lights Glow's floor pools draw (`gathered` less those lit by a real floor light).
var pools: Array = []
## Whether it is night (a time with floodlights), set by `apply`: BloomView's water glints.
var night := false
## The camera's centre in the world, when not in a tree (tests); in one, read off the viewport.
var focus := Vector2.ZERO
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
var _floor_pool: Array[PointLight2D] = []
var _flashes: Array = []  ## [pos, height, colour, radius, strength, age, life, surge]
var _lamp_lights: Array[PointLight2D] = []
static var _tex: Texture2D = null
## Main's FloorGlow (at Glow's floor-pool depth): shown only while a floor light is on.
var floor_glow: FloorGlow = null


## Takes the fight's floor lights and adds just them to the picture: a black rect over the
## whole world, drawn additively, whose `light()` returns the light's colour alone (an ordinary
## lit item would multiply it by its own black). On GLOW_MASK only.
class FloorGlow extends Node2D:
	const CODE := "shader_type canvas_item;\nrender_mode blend_add;\n" \
		+ "void fragment() { COLOR = vec4(0.0, 0.0, 0.0, 1.0); }\n" \
		+ "void light() { LIGHT = vec4(LIGHT_COLOR.rgb * LIGHT_ENERGY, 1.0); }\n"
	static var _shader: Shader = null

	func _init() -> void:
		if _shader == null:
			_shader = Shader.new()
			_shader.code = CODE
		var m := ShaderMaterial.new()
		m.shader = _shader
		material = m
		light_mask = GLOW_MASK
		visible = false

	func _draw() -> void:
		const BIG := 100000.0
		draw_rect(Rect2(-BIG, -BIG, BIG * 2.0, BIG * 2.0), Color.BLACK)
static var _pool_tex: Texture2D = null
## A lamp's floor pool keeps full strength out to this share of its radius (`pool`).
const POOL_CORE := 0.6


func _ready() -> void:
	_gather.visible = false  # used only to gather lights, never drawn
	add_child(_gather)
	for i in MAX_DYNAMIC:
		var l := _point(FIGHTER_MASK)
		l.height = DYNAMIC_HEIGHT
		l.enabled = false
		_pool.append(l)
		var f := _point(GLOW_MASK)
		f.enabled = false
		_floor_pool.append(f)
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
	gathered.clear()
	pools.clear()
	_flashes.clear()
	lamps.clear()
	for l in _lamp_lights:
		l.queue_free()
	_lamp_lights.clear()
	var t := String(look.get("time", "day"))
	var w := String(look.get("weather", "clear"))
	var on := tier != Tier.OFF
	night = on and ((WeatherView.data().get("times", {}) as Dictionary).get(t, {}) as Dictionary).has("floodlights")
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
	gathered.clear()
	pools.clear()
	_flashes.clear()
	_sync()


## Once a tick (main, after the effects): gather the moving lights and place the pool.
func advance() -> void:
	if tier == Tier.OFF or fx == null or fx.sim == null:
		if not dynamic.is_empty() or not gathered.is_empty():
			clear()
		_place_suns()
		return
	var t0 := PerfLog.now()
	_gather.fx = fx
	if fx.time_scale > 0.0:
		_gather._tick += 1
	var raw: Array = []
	_gather.gather(raw)
	_flash_lights(raw, fx.time_scale > 0.0)
	take(raw)
	_place_suns()
	PerfLog.since("light2d gather", t0)


## The fight lights made real now: MAX_DYNAMIC on High, LOW_DYNAMIC on Low, none Off.
func cap() -> int:
	match tier:
		Tier.HIGH:
			return MAX_DYNAMIC
		Tier.LOW:
			return LOW_DYNAMIC
	return 0


## This tick's lights (LightView's format): merged by cell (`gathered`), the real ones chosen
## by priority with close ones merged into one (`dynamic`), the rest left to Glow's pools
## (`pools`), and the lights placed on them.
func take(raw: Array) -> void:
	if tier == Tier.OFF:
		clear()
		return
	gathered = _gather._merge(raw)
	var centre := _focus()
	var cand: Array = []
	for l in gathered:
		if float(l[4]) >= MIN_REAL:
			cand.append(l)
	cand.sort_custom(func(a, b): return _before(a, b, centre))
	var real: Array = []
	var covered: Array = []  # the gathered lights a real one stands for
	var n := cap()
	for l in cand:
		var into := -1
		for i in real.size():
			if Vector2(real[i][0]).distance_to(l[0]) < REAL_MERGE:
				into = i
				break
		if into >= 0:
			_absorb(real[into], l)
		elif real.size() < n:
			real.append(l.duplicate())
		else:
			continue
		covered.append(l)
	dynamic = real
	pools = []
	for l in gathered:
		if not covered.has(l):
			pools.append(l)
	_sync()


## Priority order: Surge first, then nearer the camera's centre (by FOCUS_BAND rings), then
## newest, then stronger.
static func _before(a: Array, b: Array, centre: Vector2) -> bool:
	var sa := a.size() > 6 and bool(a[6])
	var sb := b.size() > 6 and bool(b[6])
	if sa != sb:
		return sa
	var ra := int(Vector2(a[0]).distance_to(centre) / FOCUS_BAND)
	var rb := int(Vector2(b[0]).distance_to(centre) / FOCUS_BAND)
	if ra != rb:
		return ra < rb
	var ga: int = int(a[7]) if a.size() > 7 else 0
	var gb: int = int(b[7]) if b.size() > 7 else 0
	if ga != gb:
		return ga < gb
	return float(a[4]) > float(b[4])


## `l` merged into the real light `m` (LightView._merge's rule: strength adds up to 1, place and
## colour by strength, the widest reach).
static func _absorb(m: Array, l: Array) -> void:
	var s0 := float(m[4])
	var s1 := float(l[4])
	var w := s1 / maxf(0.001, s0 + s1)
	m[0] = Vector2(m[0]).lerp(l[0], w)
	m[1] = lerpf(float(m[1]), float(l[1]), w)
	m[2] = Color(m[2]).lerp(l[2], w)
	m[3] = maxf(float(m[3]), float(l[3]))
	m[4] = minf(1.0, s0 + s1)


## The camera's centre in the world (`focus` outside a tree).
func _focus() -> Vector2:
	if not is_inside_tree():
		return focus
	return get_global_transform_with_canvas().affine_inverse() * (get_viewport_rect().size * 0.5)


## A short flash of light for a big hit or a Surge starting (main, for each sim event): view
## only, and never for what the local team didn't see (FxView's `_event_shown`).
func on_event(e: Dictionary) -> void:
	if tier == Tier.OFF or fx == null or fx.sim == null:
		return
	var kind := String(e.get("type", ""))
	var spec: Array = []
	var col := Color("fff2d0")
	var who: CreatureSim = null
	if kind == "hit":
		var surge := String(e.get("move_type", "")) == "surge"
		if not surge and not (bool(e.get("heavy", false)) and float(e.get("power", 0.0)) >= FLASH_HIT_MIN):
			return
		spec = FLASH_SURGE if surge else FLASH_HIT
	elif kind == "surge":
		spec = FLASH_SURGE
		who = fx._creature(int(e.get("who", -1)))
		if who != null:
			col = Color(LightView._fx_color(who))
	else:
		return
	if not fx._event_shown(e):
		return
	if who != null and (who.stealth > 0 or not fx.shown(who)):
		return
	var top := 16.0 if who == null else maxf(24.0, float(who.def.get("fx_top", 32))) * 0.5
	_flashes.append([Vector2(e["pos"]), top, col, float(spec[0]), float(spec[1]), 0, int(spec[2]), kind == "surge"])
	if _flashes.size() > MAX_FLASHES:
		_flashes.pop_front()


## The flashes still shining, stepped down every FLASH_STEP ticks (no fade between ticks);
## `step` ages them (not while the fight is held still).
func _flash_lights(raw: Array, step: bool) -> void:
	var keep: Array = []
	for f in _flashes:
		var age := int(f[5])
		var life := int(f[6])
		if age >= life:
			continue
		var steps := maxi(1, life / FLASH_STEP)
		var k := 1.0 - float(age / FLASH_STEP) / float(steps)
		raw.append([f[0], f[1], f[2], f[3], float(f[4]) * k, 0.3, bool(f[7]), age])
		if step:
			f[5] = age + 1
		keep.append(f)
	_flashes = keep


## Flashes shining now (tests).
func flashes() -> int:
	return _flashes.size()


## Puts the pool's lights where `dynamic` says (and their floor lights); the rest off.
func _sync() -> void:
	if floor_glow != null:
		floor_glow.visible = tier != Tier.OFF and not dynamic.is_empty()
	for i in _pool.size():
		var l := _pool[i]
		var f := _floor_pool[i]
		if i >= dynamic.size() or tier == Tier.OFF:
			l.enabled = false
			f.enabled = false
			continue
		var d: Array = dynamic[i]
		l.enabled = true
		l.position = (Vector2(d[0]) - Vector2(0, float(d[1]))).round()
		l.color = d[2]
		l.energy = float(d[4]) * DYNAMIC_ENERGY
		l.texture_scale = maxf(8.0, float(d[3])) * 2.0 / TEX_SIZE
		f.enabled = true
		f.position = Vector2(d[0]).round()
		f.color = d[2]
		f.energy = minf(float(d[4]) * FLOOR_ENERGY / (1.0 + float(d[1]) / 60.0), FLOOR_MAX)
		f.texture_scale = l.texture_scale * FLOOR_REACH


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
	for l in _pool + _floor_pool + _suns:
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
