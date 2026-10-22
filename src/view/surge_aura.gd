class_name SurgeAura
extends Node2D
## The power-up aura a fighter wears while their Surge is ready: a flickering shell of
## energy rising off them, motes that drift up through it, and a coloured rim on the
## sprite (CreatureView sets the rim from `rim_color()`). The moment the meter fills, a
## burst: the shell flares out, pillars of light shoot up and a ring runs along the
## floor.
##
## Each fighter's look is data, the "surge_aura" block in its JSON:
##   "colors": [outer, inner, core]   the shell's three layers, outside in
##   "motes":  pebbles | embers | drops | leaves | bubbles | rings | wisps | clods |
##             glints | flakes        what drifts up through it
##   "spikes": how many flame tongues go round the shell (fewer = bigger tongues)
##   "sharp":  0 (a smooth, flowing shell: water, psychic) to 1 (jagged flames, ice)
##   "speed":  how fast it flickers;  "height": how tall the tongues reach
##
## CreatureView keeps two: one behind the sprite (the shell, the pillars, the floor ring)
## and one in front (`front`: a faint core and half the motes), so motes pass both in
## front of and behind the body. Cosmetic only: it reads the creature, never writes.

const BURST_TICKS := 42
const POINTS := 44
const MOTES := 12
const FALLBACK := {"colors": ["#ffb02e", "#ffe27a", "#fffbe6"], "motes": "embers",
	"spikes": 7, "sharp": 0.8, "speed": 1.0, "height": 1.0}

var c: CreatureSim
var front := false
## Set by the back aura for its front twin, so both share one clock and one burst.
var twin: SurgeAura = null
var cfg: Dictionary = FALLBACK
var colors: Array = []
var t := 0.0
var burst_t := -1  ## ticks since the meter filled (-1: no burst playing)
var lit := false
var _was_ready := false
var _body_h := 32.0
var _body_w := 12.0


## Shows `creature`'s aura. A fighter who arrives already powered up (a tag) just glows;
## the burst is for the meter filling in front of you.
func bind(creature: CreatureSim) -> void:
	c = creature
	cfg = FALLBACK.duplicate()
	cfg.merge(c.def.get("surge_aura", {}), true)
	colors = []
	for h in cfg["colors"]:
		colors.append(Color(String(h)))
	_body_h = maxf(30.0, float(c.def.get("fx_top", 32)))  # squat fighters still get a tall flame
	_body_w = maxf(9.0, c.radius * 1.25)
	_was_ready = is_ready(c)
	burst_t = -1
	lit = _was_ready
	queue_redraw()


static func is_ready(cr: CreatureSim) -> bool:
	return cr.energy >= CreatureSim.MAX_ENERGY and cr.state != CreatureSim.State.KO \
		and cr.state != CreatureSim.State.FALLING


## Once a frame (CreatureView.refresh). `dt` is in ticks; 0 holds it still (the KO freeze).
func step(dt := 1.0) -> void:
	if c == null:
		return
	if twin == null and front:
		return  # the back aura steps its twin
	var ready := is_ready(c)
	if ready and not _was_ready:
		burst_t = 0
	_was_ready = ready
	lit = ready
	t += dt
	if burst_t >= 0:
		burst_t += int(ceil(dt))
		if burst_t > BURST_TICKS:
			burst_t = -1
	queue_redraw()
	if twin != null:
		twin.t = t
		twin.burst_t = burst_t
		twin.lit = lit
		twin.queue_redraw()


## The sprite's rim colour and strength while the aura is lit (0: no rim).
func rim() -> float:
	if not lit:
		return 0.0
	var k := 0.55 + 0.25 * (0.5 + 0.5 * sin(t * 0.21 * float(cfg["speed"])))
	if burst_t >= 0 and burst_t < 10:
		k = 1.0
	return k


func rim_color() -> Color:
	return (colors[1] as Color).lerp(colors[2], 0.35) if colors.size() >= 3 else Color.WHITE


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var t0 := PerfLog.now()
	_draw_now()
	PerfLog.since("aura draw", t0)


## How far off screen a fighter can be and still have its aura drawn (the shell and the
## motes reach a little past the body).
const CULL_PAD := 96.0


func _on_screen() -> bool:
	if not is_inside_tree():
		return true
	return get_viewport_rect().grow(CULL_PAD).has_point(get_global_transform_with_canvas().origin)


func _draw_now() -> void:
	if c == null or (not lit and burst_t < 0) or not _on_screen():
		return
	var b := _burst_k()
	if not front:
		if burst_t >= 0:
			_draw_burst_back()
		# Breathing: the whole shell swells and settles, so it reads as alive at a glance.
		var breath := 1.0 + 0.07 * sin(t * 0.12 * float(cfg["speed"]))
		_draw_shell(colors[0], (1.05 + 0.5 * b) * breath, 0.46 + 0.2 * b, 0.0)
		_draw_shell(colors[1], (0.82 + 0.4 * b) * breath, 0.55 + 0.15 * b, 1.7)
		_draw_motes(false)
	else:
		# A faint core over the body, so the energy wraps round it rather than sitting behind.
		_draw_shell(colors[2], 0.55 + 0.3 * b, 0.16 + 0.3 * b, 3.1)
		_draw_motes(true)
		if burst_t >= 0 and burst_t < 8:
			_draw_shell(Color.WHITE, 1.1, 0.35 * (1.0 - burst_t / 8.0), 0.6)


## 1 at the burst's start easing to 0, else 0.
func _burst_k() -> float:
	if burst_t < 0:
		return 0.0
	var k := 1.0 - float(burst_t) / float(BURST_TICKS)
	return k * k


## One layer of the shell: a ring of flame tongues round the body, taller at the top.
## Every point sits on a ray from one centre, so the outline never crosses itself.
func _draw_shell(col: Color, size: float, alpha: float, phase: float) -> void:
	if alpha <= 0.01:
		return
	var spikes := float(cfg["spikes"])
	var sharp := clampf(float(cfg["sharp"]), 0.0, 1.0)
	var speed := float(cfg["speed"])
	var height := float(cfg["height"])
	var h := _body_h * size
	var w := _body_w * size
	var centre := Vector2(0, -h * 0.45)
	var pts := PackedVector2Array()
	for i in POINTS:
		var a := TAU * float(i) / float(POINTS)
		var dir := Vector2(cos(a), sin(a))
		var up := maxf(0.0, -dir.y)  # 1 straight up, 0 at the sides and below
		# Flame tongues: a wave round the ring, sharpened into points, flickering in time.
		var wave := 0.5 + 0.5 * sin(a * spikes + t * 0.17 * speed + phase)
		wave = lerpf(wave, pow(wave, 3.0), sharp)
		var flick := 0.5 + 0.5 * sin(t * 0.31 * speed + float(i) * 1.7 + phase * 2.0)
		var reach := 1.0 + (0.45 + 1.05 * up * height) * wave * (0.7 + 0.3 * flick)
		var r := Vector2(w * 0.95, h * 0.62) * reach
		var p := centre + Vector2(dir.x * r.x, dir.y * r.y)
		p.y = minf(p.y, 1.5)  # the bottom sits on the floor
		pts.append(p)
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, alpha))


## Motes drifting up through the aura; even ones behind the body, odd ones in front.
func _draw_motes(in_front: bool) -> void:
	var kind := String(cfg["motes"])
	var period := 46.0 / maxf(0.3, float(cfg["speed"]))
	for i in MOTES:
		if (i % 2 == 1) != in_front:
			continue
		var seed_ := float(i) * 12.9898
		var r1 := fposmod(sin(seed_) * 43758.5453, 1.0)
		var r2 := fposmod(sin(seed_ * 1.7 + 4.1) * 24634.6345, 1.0)
		var prog := fposmod(t / period + r1, 1.0)
		var x := (r2 - 0.5) * 2.0 * _body_w * 1.1 * (1.0 - prog * 0.4)
		x += sin(t * 0.09 + seed_) * 2.0
		var y := -prog * _body_h * (1.15 + 0.35 * float(cfg["height"]))
		var a := sin(prog * PI)  # fades in and out
		_mote(kind, Vector2(x, y), a, prog, i)


func _mote(kind: String, p: Vector2, a: float, prog: float, i: int) -> void:
	var core: Color = colors[2]
	var inner: Color = colors[1]
	var outer: Color = colors[0]
	p = p.round()
	match kind:
		"pebbles":
			var stone := Color(0.62, 0.6, 0.58, a) if i % 3 else Color(0.82, 0.8, 0.76, a)
			draw_rect(Rect2(p, Vector2(2, 2)), stone)
		"embers":
			draw_rect(Rect2(p, Vector2(1, 2)), Color(core.r, core.g, core.b, a))
			draw_rect(Rect2(p + Vector2(0, 2), Vector2(1, 1)), Color(outer.r, outer.g, outer.b, a * 0.7))
		"drops":
			draw_rect(Rect2(p, Vector2(1, 2)), Color(inner.r, inner.g, inner.b, a))
			draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 1)), Color(core.r, core.g, core.b, a))
		"leaves":
			var lean := 1.0 if int(t / 8.0 + i) % 2 == 0 else -1.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(-2, 0), p + Vector2(0, -1 * lean),
				p + Vector2(2, 0), p + Vector2(0, 1 * lean)]), Color(inner.r, inner.g, inner.b, a))
		"bubbles":
			draw_arc(p, 1.5 + prog * 1.2, 0.0, TAU, 8, Color(core.r, core.g, core.b, a), 1.0)
		"rings":
			draw_set_transform(p, 0.0, Vector2(1.0, 0.35))
			draw_arc(Vector2.ZERO, 3.0 + prog * 6.0, 0.0, TAU, 14, Color(core.r, core.g, core.b, a * 0.8), 1.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"wisps":
			var s := sin(t * 0.2 + i) * 2.0
			draw_polyline(PackedVector2Array([p + Vector2(0, 3), p + Vector2(s, 0), p + Vector2(-s, -3)]),
				Color(inner.r, inner.g, inner.b, a), 1.0)
		"clods":
			# Kicked up from the floor, then falling back: an arc, not a drift.
			var q := Vector2(p.x, -sin(prog * PI) * _body_h * 0.9)
			draw_rect(Rect2(q.round(), Vector2(2, 2)), Color(outer.r, outer.g, outer.b, 0.9))
		"glints":
			if int(t / 4.0 + i) % 3 == 0:
				draw_rect(Rect2(p + Vector2(-2, 0), Vector2(5, 1)), Color(core.r, core.g, core.b, a))
				draw_rect(Rect2(p + Vector2(0, -2), Vector2(1, 5)), Color(core.r, core.g, core.b, a))
			else:
				draw_rect(Rect2(p, Vector2(1, 1)), Color(core.r, core.g, core.b, a))
		"flakes":
			var fc := Color(core.r, core.g, core.b, a)
			draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), fc)
			draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), fc)
		_:
			draw_rect(Rect2(p, Vector2(1, 1)), Color(core.r, core.g, core.b, a))


## The meter just filled: pillars of light shoot up round the fighter and a ring runs out
## along the floor.
func _draw_burst_back() -> void:
	var k := float(burst_t) / float(BURST_TICKS)
	var fade := 1.0 - k
	var core: Color = colors[2]
	var inner: Color = colors[1]
	# The floor ring, as a true circle on the floor (squashed only because the floor is).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.38))
	var rr := _body_w * (1.2 + 3.2 * sqrt(k))
	draw_arc(Vector2.ZERO, rr, 0.0, TAU, 32, Color(inner.r, inner.g, inner.b, 0.7 * fade), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Pillars: shoot up fast, then thin out and fade.
	var grow := clampf(k * 4.0, 0.0, 1.0)
	for j in 6:
		var side := -1.0 if j % 2 == 0 else 1.0
		var x := side * _body_w * (0.6 + 0.45 * float(j / 2))
		var tall := _body_h * (1.6 + 0.5 * float((j * 7) % 3)) * grow
		var wide := maxf(1.0, (3.0 - float(j / 2)) * fade)
		draw_rect(Rect2(x - wide * 0.5, -tall, wide, tall), Color(core.r, core.g, core.b, 0.85 * fade))
		draw_rect(Rect2(x - wide * 0.5 - 1.0, -tall, wide + 2.0, tall), Color(inner.r, inner.g, inner.b, 0.25 * fade))
