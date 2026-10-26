class_name WeatherView
extends Node2D
## Time of day and weather: how a match looks, never how it plays. The presets are data
## (data/weather.json); an arena lists the ones it allows ("times", "weathers" in
## data/arenas/<id>.json, else the file's "defaults"). Main picks the look when a match
## starts (`resolve`: the Single player menu's Time / Weather, Random by default, or
## `--time=` / `--weather=`); online matches and the menu's background fight are always
## day + clear, a replay plays the look it was recorded with (`Replay.setup["look"]`).
##
## Four layers, each at its own depth (main adds them):
##   - `shade` (over the floor art, the crowd and the floor wear, under the floor effects,
##     so telegraphs on the floor keep their colours): multiplies the picture by the
##     look's `floor` tint. At night it is a light map instead: the dark tint with
##     floodlight pools cut into it, pre-made once per match: a few flat brightness steps
##     with a narrow ordered-dither seam between them (one texel a pixel, no smoothing).
##     Glow's additive pools (LightView) draw over it, so auras and sparks pop at night.
##   - `ground` (over the shadows, under the fighters): fog bands, rain splashes and ripples.
##   - this node (over the fighters, under the effects, telegraphs and health bars): rain
##     streaks, snow, blown debris, the floodlight lamps.
##   - the fighters: each sprite's `self_modulate`, the look's `fighter` tint; at night
##     lit by the pool it stands in, never below `fighter_min` (the flash shader's hit
##     flash and windup tells replace the colour, so they stay exact).
## Lighting (Light2DView, Settings > Video > Lighting): with `lamp_lights` (High, on an arena
## with `lights`) the night shade is the flat dark tint and the arena's lamps light it
## (`shade.light_mask` is Light2DView.FLOOR_MASK, so the lamps' PointLight2Ds brighten the
## multiply layer where they shine): the pools come from real lights instead of the baked
## light map, which still answers `light_at`. Fighters with normal sheets (`CreatureView.lit`)
## then keep the night tint, never under the time's `lit_fighter_min` (else `fighter_min`),
## and the lamps light them per pixel; the others take the baked pool's light as before.
## `fighter_scale` dims the fighters with normal sheets a little by day so the sun's lit side
## reads; the others draw exactly as before.
## It also tints the water and the ambient life (`life`), softens or stretches the shadows
## (`shadow`: length, alpha, `low_sun`) and tells AmbientView about wind, motes and
## critters (`ambient`). Everything moves on the 60 Hz tick (no interpolation); a phone
## or handheld uses each block's `mobile` counts.

const PATH := "res://data/weather.json"
const DAY := "day"
const CLEAR := "clear"
const RANDOM := "random"
const MARGIN := Vector2(400, 80)  ## the map picture reaches this far past the arena (ArenaView.MARGIN)
const LIGHTMAP_SCALE := 1  ## world px per light-map texel
const SEAM := 0.3  ## the share of each step, at its outer edge, dithered into the next
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const C_WATER_L := Color("a8d6f0")
const C_FOAM := Color("e8f4fa")

static var _data := {}
static var _pools := {}  ## half-res pool radius -> Image

var look := {"time": DAY, "weather": CLEAR}
var mobile := OS.has_feature("mobile")
var sim: MatchSim
var views: Array = []  ## main's CreatureViews (shared)
var shade := Shade.new()
var ground := Layer.new()
var _time := {}
var _weather := {}
var _tick := 0
var _fighter := Color.WHITE
var _fighter_min := 1.0
var _lit_min := 1.0  ## `lit_fighter_min`: a normal-mapped fighter's least brightness under the lamps
var _lightmap: Image = null
var _lm_origin := Vector2.ZERO
var _lights: Array = []  ## night: [pos, radius] of each floodlight pool
var _lamps: Array = []
var _debris := ""
## Set by main before `apply` (Light2DView): the arena's lamps light the night (no baked pools).
var lamp_lights := false
## Set by main (Light2DView): every fighter's tint times this (the sun's shade side by day).
var fighter_scale := 1.0


## The multiply layer over the floor art.
class Shade extends Node2D:
	var tint := Color.WHITE
	var tex: Texture2D = null
	var rect := Rect2()

	func _init() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		material = m
		light_mask = Light2DView.FLOOR_MASK  # the lamps (High) light the night through it

	func _draw() -> void:
		const BIG := 100000.0
		if tex == null and not rect.has_area():
			draw_rect(Rect2(-BIG, -BIG, BIG * 2.0, BIG * 2.0), tint)
			return
		if tex != null:
			draw_texture_rect(tex, rect, false)
		else:
			# lit by the lamps (High): the map's own rect, the flat dark the lights brighten
			draw_rect(rect, tint)
		# the dark all round the light map (the camera can look past the picture)
		draw_rect(Rect2(-BIG, -BIG, BIG * 2.0, rect.position.y + BIG), tint)
		draw_rect(Rect2(-BIG, rect.end.y, BIG * 2.0, BIG), tint)
		draw_rect(Rect2(-BIG, rect.position.y, rect.position.x + BIG, rect.size.y), tint)
		draw_rect(Rect2(rect.end.x, rect.position.y, BIG, rect.size.y), tint)


class Layer extends Node2D:
	var paint: Callable

	func _draw() -> void:
		var t0 := PerfLog.now()
		if paint.is_valid():
			paint.call(self)
		PerfLog.since("weather ground", t0)


func _init() -> void:
	ground.paint = _paint_ground
	shade.visible = false


# ------------------------------------------------------------------ the presets (data)

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


## Every time of day, in the file's order.
static func time_ids() -> Array:
	return (data().get("times", {}) as Dictionary).keys()


static func weather_ids() -> Array:
	return (data().get("weathers", {}) as Dictionary).keys()


static func name_of(kind: String, id: String) -> String:
	var block: Dictionary = data().get(kind, {})
	return String((block.get(id, {}) as Dictionary).get("name", id.capitalize()))


## The times an arena allows (its "times", else the defaults), known ids only, day if none.
static func times_of(arena: Dictionary) -> Array:
	return _allowed(arena, "times", time_ids(), DAY)


static func weathers_of(arena: Dictionary) -> Array:
	return _allowed(arena, "weathers", weather_ids(), CLEAR)


static func _allowed(arena: Dictionary, key: String, known: Array, fallback: String) -> Array:
	var want: Array = arena.get(key, (data().get("defaults", {}) as Dictionary).get(key, [fallback]))
	var out: Array = []
	for id in want:
		if String(id) in known and not String(id) in out:
			out.append(String(id))
	return out if not out.is_empty() else [fallback]


## The look for a match on `arena`: each choice an id or "random" (one of the arena's
## allowed, at random); a choice the arena doesn't allow falls back to its first.
static func resolve(arena: Dictionary, time_choice: String, weather_choice: String,
		rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return {"time": _pick(times_of(arena), time_choice, rng), "weather": _pick(weathers_of(arena), weather_choice, rng)}


static func _pick(allowed: Array, choice: String, rng: RandomNumberGenerator) -> String:
	if choice == RANDOM:
		return String(allowed[rng.randi() % allowed.size()])
	return choice if choice in allowed else String(allowed[0])


static func default_look() -> Dictionary:
	return {"time": DAY, "weather": CLEAR}


## A block's numbers, with its `mobile` overrides on a phone.
func _counts(block: Dictionary, key: String) -> Dictionary:
	var out: Dictionary = (block.get(key, {}) as Dictionary).duplicate()
	if mobile:
		out.merge(block.get("mobile", {}), true)
	return out


# ------------------------------------------------------------------ setting a match up

## Sets the look for `s`, retuning the shadows, the ambient life and the water; called by
## main after those views have their sim.
func apply(s: MatchSim, p_look: Dictionary, shadows: ShadowLayer = null, ambient: AmbientView = null,
		water: WaterView = null) -> void:
	sim = s
	var d := data()
	var t := String(p_look.get("time", DAY))
	var w := String(p_look.get("weather", CLEAR))
	if not (d.get("times", {}) as Dictionary).has(t):
		t = DAY
	if not (d.get("weathers", {}) as Dictionary).has(w):
		w = CLEAR
	look = {"time": t, "weather": w}
	_time = d["times"][t] if d.has("times") else {}
	_weather = d["weathers"][w] if d.has("weathers") else {}
	_tick = 0
	var floor_tint := _tint("floor")
	_fighter = _tint("fighter")
	_fighter_min = float(_time.get("fighter_min", 1.0))
	_lit_min = float(_time.get("lit_fighter_min", _fighter_min))
	var life := _tint("life")
	# shadows: the arena's own light, stretched or softened
	if shadows != null:
		var l: Dictionary = ShadowLayer.light_of(s.arena).duplicate()
		var cast: Vector2 = l["cast"]
		var alpha := float(l["alpha"])
		for blk in [_time.get("shadow", {}), _weather.get("shadow", {})]:
			var sh: Dictionary = blk
			if sh.has("low_sun"):  # the sun near the horizon: shadows rake sideways
				var sx := 1.0 if cast.x >= 0.0 else -1.0
				cast = Vector2(sx, float(sh["low_sun"])).normalized() * cast.length()
			cast *= float(sh.get("length", 1.0))
			alpha *= float(sh.get("alpha", 1.0))
		if absf(cast.y) < ShadowLayer.MIN_FLAT:
			cast.y = ShadowLayer.MIN_FLAT if cast.y >= 0.0 else -ShadowLayer.MIN_FLAT
		shadows.light = {"cast": cast, "alpha": clampf(alpha, 0.0, 0.6)}
	if ambient != null:
		var amb: Dictionary = {}
		for blk in [_time.get("ambient", {}), _weather.get("ambient", {})]:
			amb.merge(blk, true)
		ambient.set_weather(float(amb.get("wind", 1.0)), float(amb.get("motes", 1.0)), bool(amb.get("flies", true)))
		ambient.modulate = life
	if water != null:
		water.modulate = life
	# the multiply layer
	shade.tint = floor_tint
	shade.tex = null
	shade.rect = Rect2()
	_lightmap = null
	_lights.clear()
	_lamps.clear()
	if _time.has("floodlights"):
		_build_lightmap(floor_tint, _time["floodlights"])
		if lamp_lights:
			shade.tex = null  # the flat dark: the lamps' lights make the pools
	if ambient != null:
		ambient.set_moths(_moth_points())
	shade.visible = shade.tex != null or not floor_tint.is_equal_approx(Color.WHITE)
	shade.queue_redraw()
	_debris = String((d.get("debris_by_ground", {}) as Dictionary).get(String(s.arena.get("ground", "dirt")), "paper"))
	if not _weather.has("debris"):
		_debris = ""
	var moving := _weather.has("rain") or _weather.has("fog") or _weather.has("snow") or _weather.has("debris")
	visible = moving or not _lamps.is_empty()
	ground.visible = _weather.has("rain") or _weather.has("fog")
	_apply_fighters()
	queue_redraw()
	ground.queue_redraw()


## Night: where the moths circle, the lit lamps (the corner towers' and the arena's
## furniture floodlights' heads); none by day.
func _moth_points() -> Array:
	var out: Array = []
	if _lamps.is_empty():
		return out
	for l in _lamps:
		out.append(Vector2(l[0]) + Vector2(0, 1))
	var size := sim.arena_size()
	for e in sim.arena.get("furniture", []):
		if e is Dictionary and String(e.get("kind", "")) == "floodlight":
			var p := FurnitureView.world_pos(e, size) + Vector2(0, -int(e.get("h", 96)) - 5)
			var dup := false
			for q in out:
				if (q as Vector2).distance_to(p) < 24.0:
					dup = true
					break
			if not dup:
				out.append(p)
	return out


## How much of the arena's grade (`grade` in its JSON, GradeView) this time and weather
## let through: night already darkens and tints the picture, so it takes less of the
## map's own tint and vignette. Each preset's optional `grade` {tint, vignette} are
## multipliers, 1 when absent.
func grade_scale() -> Dictionary:
	var out := {"tint": 1.0, "vignette": 1.0}
	for blk in [_time, _weather]:
		var g: Dictionary = (blk as Dictionary).get("grade", {})
		for k in out:
			out[k] = float(out[k]) * float(g.get(k, 1.0))
	return out


## Back to day and clear (the menu's background fight, online).
func reset(s: MatchSim, shadows: ShadowLayer = null, ambient: AmbientView = null, water: WaterView = null) -> void:
	apply(s, default_look(), shadows, ambient, water)


func _tint(key: String) -> Color:
	var c := Color.WHITE
	for blk in [_time, _weather]:
		if (blk as Dictionary).has(key):
			c *= Color(String(blk[key]))
	c.a = 1.0
	return c


## Night: the dark tint with a pool of light under every floodlight, on a grid over the
## floor, made once (flat steps with dithered seams), plus the lamps on the corners.
func _build_lightmap(dark: Color, fl: Dictionary) -> void:
	var size := sim.arena_size() + MARGIN * 2.0
	var w := int(ceil(size.x / LIGHTMAP_SCALE))
	var h := int(ceil(size.y / LIGHTMAP_SCALE))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(dark)
	var fr := sim.floor_rect()
	var spacing := float(fl.get("spacing", 230))
	var radius := float(fl.get("radius", 150))
	var cols := maxi(2, roundi(fr.size.x / spacing))
	var rows := maxi(1, roundi(fr.size.y / spacing))
	var pool := _pool_image(int(radius / LIGHTMAP_SCALE), Color(String(fl.get("color", "#fff2d8"))),
		float(fl.get("strength", 0.9)), int(fl.get("levels", 5)))
	var pw := pool.get_width()
	for j in rows:
		for i in cols:
			var p := fr.position + Vector2((i + 0.5) * fr.size.x / cols, (j + 0.5) * fr.size.y / rows)
			_lights.append([p, radius])
			var at := Vector2i(((p + MARGIN) / LIGHTMAP_SCALE).round()) - Vector2i(pw / 2, pw / 2)
			img.blend_rect(pool, Rect2i(0, 0, pw, pw), at)
	_lightmap = img
	_lm_origin = -MARGIN
	shade.tex = ImageTexture.create_from_image(img)
	shade.rect = Rect2(-MARGIN, Vector2(w, h) * LIGHTMAP_SCALE)
	# the lamps: on the towers at the floor's corners
	var lamp := Color(String(fl.get("lamps", "#fff8e0")))
	for c in [Vector2(fr.position.x, fr.position.y - 30), Vector2(fr.end.x, fr.position.y - 30),
			Vector2(fr.position.x, fr.end.y + 10), Vector2(fr.end.x, fr.end.y + 10)]:
		_lamps.append([c.round(), lamp])


## A pool of light `r` texels round, in `levels` dithered steps, strongest in the middle.
static func _pool_image(r: int, col: Color, strength: float, levels: int) -> Image:
	var key := "%d:%s:%.2f:%d" % [r, col.to_html(), strength, levels]
	if _pools.has(key):
		return _pools[key]
	var n := r * 2
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dd := Vector2(x + 0.5 - r, y + 0.5 - r).length() / float(r)
			var f := clampf(1.0 - dd, 0.0, 1.0)
			f = f * (1.7 - 0.7 * f)  # a broad, flat-topped pool
			var v := f * levels
			var lo := floorf(v)
			var fr := v - lo  # flat steps; only a narrow seam at each step's edge is dithered
			if fr > 1.0 - SEAM and (fr - (1.0 - SEAM)) / SEAM > (BAYER[(y % 4) * 4 + x % 4] + 0.5) / 16.0:
				lo += 1.0
			img.set_pixel(x, y, Color(col, strength * minf(lo, levels) / levels))
	_pools[key] = img
	return img


## How lit the floor is at `p` at night (0 the dark, 1 the middle of a pool).
func light_at(p: Vector2) -> float:
	if _lightmap == null:
		return 1.0
	var best := 0.0
	for l in _lights:
		var d := (p - Vector2(l[0])).length() / float(l[1])
		if d < 1.0:
			var f := 1.0 - d
			best = maxf(best, f * (1.7 - 0.7 * f))
	return clampf(best, 0.0, 1.0)


## Each fighter's sprite tint: the look's, and at night the pool's light on it.
func _apply_fighters() -> void:
	for o in views:
		if not is_instance_valid(o):
			continue
		var v: CreatureView = o
		if v.sprite == null:
			continue
		var col := _fighter
		var lit := v.lit()
		if _lightmap != null and v.c != null:
			var by_lamps := lamp_lights and lit
			var k := 0.0 if by_lamps else light_at(v.c.pos)
			var least := _lit_min if by_lamps else _fighter_min
			col = _fighter.lerp(Color.WHITE, k)
			var lum := col.r * 0.3 + col.g * 0.55 + col.b * 0.15
			if lum < least:
				col = col.lerp(Color.WHITE, (least - lum) / maxf(0.01, 1.0 - lum))
			col = Color(snappedf(col.r, 0.05), snappedf(col.g, 0.05), snappedf(col.b, 0.05))  # palette steps
		if fighter_scale < 1.0 and lit:
			col = Color(col.r * fighter_scale, col.g * fighter_scale, col.b * fighter_scale)
		v.sprite.self_modulate = col


# ------------------------------------------------------------------ the tick

func advance() -> void:
	if sim == null:
		return
	_tick += 1
	_apply_fighters()
	if visible:
		queue_redraw()
	if ground.visible:
		ground.queue_redraw()


## Over the floor, under the fighters: fog bands, splashes and ripples.
func _paint_ground(ci: CanvasItem) -> void:
	if sim == null:
		return
	var view := FxView._view_rect(ci, 8.0)
	var fr := sim.floor_rect()
	var area := view.intersection(fr)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	if _weather.has("fog"):
		_draw_fog(ci, fr, view)
	if _weather.has("rain"):
		var rc := _counts(_weather, "rain")
		rain_splashes(ci, area, int(rc.get("splashes", 40)), _tick)
		var nr := int(rc.get("ripples", 8))
		for i in nr:
			var cyc := 36
			var ph := (_tick + i * 11) % cyc
			var seed := i * 7919 + ((_tick + i * 11) / cyc) * 104729
			var at := area.position + Vector2(float(seed % int(area.size.x)), float((seed / 13) % int(area.size.y)))
			var r := 1 + ph / 6
			var a := 0.5 * (1.0 - float(ph) / cyc)
			var col := Color(C_WATER_L, a)
			ci.draw_rect(Rect2(at + Vector2(-r, 0).round(), Vector2(1, 1)), col)
			ci.draw_rect(Rect2(at + Vector2(r, 0).round(), Vector2(1, 1)), col)
			ci.draw_rect(Rect2((at + Vector2(-r * 0.6, -r * 0.5)).round(), Vector2(maxi(1, roundi(r * 1.2)), 1)), col)
			ci.draw_rect(Rect2((at + Vector2(-r * 0.6, r * 0.5)).round(), Vector2(maxi(1, roundi(r * 1.2)), 1)), col)


## The look of Culvert's Rain Dance: little foam-and-water splashes at hashed spots, a new
## set every 4 ticks. Shared with FxView.
static func rain_splashes(ci: CanvasItem, area: Rect2, n: int, tick: int) -> void:
	if area.size.x < 1.0 or area.size.y < 1.0:
		return
	for i in n:
		var hsh := i * 7919 + (tick / 4) * 104729
		var sx := area.position.x + float(hsh % int(area.size.x))
		var sy := area.position.y + float((hsh / 7) % int(area.size.y))
		ci.draw_rect(Rect2(Vector2(sx, sy - 1), Vector2(1, 1)), Color(C_FOAM, 0.6))
		ci.draw_rect(Rect2(Vector2(sx - 1, sy), Vector2(3, 1)), Color(C_WATER_L, 0.5))


## The falling streaks of Rain Dance over `view`. Shared with FxView.
static func rain_streaks(ci: CanvasItem, view: Rect2, n: int, tick: int, alpha := 0.45) -> void:
	var col := Color(C_WATER_L, alpha)
	var w := view.size.x + 40.0
	var h := view.size.y + 30.0
	for i in n:
		var x := view.position.x + fposmod(i * 37.7 + tick * 2.4, w) - 20.0
		var y := view.position.y + fposmod(i * 61.3 + i * i * 0.37 + tick * 8.0, h) - 15.0
		x = roundf(x)
		y = roundf(y)
		ci.draw_line(Vector2(x, y), Vector2(x - 2.0, y + 7.0), col, 1.0)


func _draw_fog(ci: CanvasItem, fr: Rect2, view: Rect2) -> void:
	var fc := _counts(_weather, "fog")
	var n := int(fc.get("bands", 6))
	var base := Color(String(fc.get("color", "#e6eef2")))
	var a := float(fc.get("alpha", 0.16))
	var hr: Array = fc.get("height", [10, 22])
	var lr: Array = fc.get("length", [180, 380])
	var sr: Array = fc.get("speed", [0.08, 0.22])
	var span := fr.size.x + 400.0
	for b in n:
		var hsh := (b * 2654435761) & 0x7fffffff
		var bh := int(hr[0]) + hsh % maxi(1, int(hr[1]) - int(hr[0]))
		var bl := float(int(lr[0]) + (hsh / 31) % maxi(1, int(lr[1]) - int(lr[0])))
		var sp := float(sr[0]) + float((hsh / 977) % 100) / 100.0 * (float(sr[1]) - float(sr[0]))
		var y := fr.position.y + float((hsh / 7) % maxi(1, int(fr.size.y - bh)))
		var x := fr.position.x - 200.0 + fposmod(float(hsh % 997) + _tick * sp, span)
		x = floorf(x)
		if x > view.end.x or x + bl < view.position.x or y > view.end.y or y + bh < view.position.y:
			continue
		for j in bh:
			# thicker in the middle rows, ragged ends that shift every few rows
			var mid := 1.0 - absf(float(j) - bh * 0.5) / (bh * 0.5)
			var step := 0.5 if mid < 0.34 else (0.75 if mid < 0.67 else 1.0)
			var rag := float(((j / 2) * 7 + b * 13) % 17)
			ci.draw_rect(Rect2(x + rag, y + j, bl - rag * 2.0, 1), Color(base, a * step))


## Over the fighters: rain, snow, blown debris, the floodlight lamps.
func _draw() -> void:
	if sim == null:
		return
	var t0 := PerfLog.now()
	var view := FxView._view_rect(self, 0.0)
	if _weather.has("rain"):
		rain_streaks(self, view, int(_counts(_weather, "rain").get("streaks", 110)), _tick, 0.4)
	if _weather.has("snow"):
		_draw_snow(view)
	if _debris != "":
		_draw_debris(view)
	for l in _lamps:
		var p: Vector2 = l[0]
		if view.grow(40.0).has_point(p):
			var col: Color = l[1]
			draw_rect(Rect2(p + Vector2(-4, -2), Vector2(8, 3)), Color(0.18, 0.18, 0.22))
			draw_rect(Rect2(p + Vector2(-3, -1), Vector2(6, 1)), col)
			draw_rect(Rect2(p + Vector2(-5, 1), Vector2(10, 1)), Color(col, 0.35))
	PerfLog.since("weather draw", t0)


func _draw_snow(view: Rect2) -> void:
	var n := int(_counts(_weather, "snow").get("flakes", 80))
	var w := view.size.x + 40.0
	var h := view.size.y + 30.0
	for i in n:
		var fall := 0.45 + float(i % 5) * 0.12
		var x := fposmod(i * 47.3 + _tick * 0.35 + 6.0 * sin(_tick * 0.03 + i), w) - 20.0
		var y := fposmod(i * 71.9 + i * i * 0.23 + _tick * fall, h) - 15.0
		var at := (view.position + Vector2(x, y)).round()
		var big := i % 7 == 0
		draw_rect(Rect2(at, Vector2(2, 2) if big else Vector2(1, 1)), Color(1, 1, 1, 0.75 if big else 0.6))


const DEBRIS_COLORS := {
	"leaf": [Color("7fa346"), Color("b08a3e"), Color("5f7a32")],
	"paper": [Color("f2efe6"), Color("e0dccf"), Color("f2efe6")],
	"grit": [Color("b8ad98"), Color("948a78"), Color("cfc4ad")],
}


func _draw_debris(view: Rect2) -> void:
	var dc := _counts(_weather, "debris")
	var n := int(dc.get("count", 24))
	var sp: Array = dc.get("speed", [2.2, 4.2])
	var cols: Array = DEBRIS_COLORS.get(_debris, DEBRIS_COLORS["paper"])
	var w := view.size.x + 60.0
	for i in n:
		var v := float(sp[0]) + float((i * 37) % 100) / 100.0 * (float(sp[1]) - float(sp[0]))
		var x := fposmod(i * 83.1 + _tick * v, w) - 30.0
		var y := fposmod(i * 59.7 + i * i * 0.41, view.size.y) + 4.0 * sin(_tick * 0.09 + i * 1.7)
		var at := (view.position + Vector2(x, y)).round()
		var col: Color = cols[i % cols.size()]
		match _debris:
			"leaf":  # tumbling: flat, then on edge
				draw_rect(Rect2(at, Vector2(2, 1) if (_tick / 6 + i) % 2 == 0 else Vector2(1, 2)), col)
			"paper":
				if i % 3 == 0:
					draw_rect(Rect2(at, Vector2(3, 2) if (_tick / 5 + i) % 2 == 0 else Vector2(2, 1)), Color(col, 0.9))
				else:
					draw_rect(Rect2(at, Vector2(3, 1)), Color(Color("cdb48a"), 0.45))  # sand
			_:  # grit: a short streak with a darker head
				draw_rect(Rect2(at - Vector2(3, 0), Vector2(3, 1)), Color(col, 0.5))
				draw_rect(Rect2(at, Vector2(2, 1)), Color(col.darkened(0.25), 0.9))
