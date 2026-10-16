class_name PaperFx
extends Node2D
## Mister Crease's paper, drawn over the fighters: the sheets of his Paper Stock floating
## above the hat, the crafts he has folded and carries (the shuriken in his hat band, the
## crane on his near hand, the frog on his far shoulder), the Paper Plane's trail, and the
## Thousand Cranes storm. The static draw_* functions are FxView's projectiles (darts,
## shuriken, the crane, the bundle in flight). Reads the sim, never writes it; anything a
## hidden fighter does stays hidden (FxView.shown / sight_to).

const C_PAPER: Array[Color] = [Color("8e8c86"), Color("d8d6ce"), Color("f6f4ec"), Color("ffffff")]
const C_OUT := Color("1b1e26")
const C_ORANGE := Color("ff9a2e")
const C_NAVY := Color("1e488e")
const C_MAROON := Color("761240")
const THROW_Z := 18.0
## Where the carried crafts sit on him (px above his feet; x is toward his facing).
const BAND := Vector2(4.0, -45.0)
const HAND := Vector2(9.0, -27.0)
const SHOULDER := Vector2(-6.0, -37.0)
const TRAIL := 14

var sim: MatchSim
var fx: FxView
var _tick := 0
var _scatter := {}  ## creature id -> ticks of a hit shaking the sheets loose
var _flourish := {}  ## creature id -> ticks since a sheet regrew
var _trails := {}  ## creature id -> recent positions while gliding
var _storm_seen := {}  ## storm key -> true, for the start shake


func set_sim(s: MatchSim) -> void:
	sim = s
	_scatter.clear()
	_flourish.clear()
	_trails.clear()
	_storm_seen.clear()
	queue_redraw()


## Each tick: react to the sim's events (a hit scatters the sheets, a regrown one flashes,
## a storm shakes the screen) and remember the glide's trail.
func advance(events: Array) -> void:
	if sim == null:
		return
	_tick += 1
	for e in events:
		match String(e.get("type", "")):
			"hit", "block":
				var t := int(e.get("target", -1))
				if t >= 0:
					_scatter[t] = 14
			"sheet":
				_flourish[int(e.get("who", -1))] = 0
			"storm":
				if fx != null and fx.sight_to(e["pos"]):
					fx.shake_out = maxf(fx.shake_out, 4.0)
			"storm_end":
				if fx != null and fx.sight_to(e["pos"]):
					fx.shake_out = maxf(fx.shake_out, 7.0)
	for k in _scatter.keys():
		_scatter[k] = int(_scatter[k]) - 1
		if int(_scatter[k]) <= 0:
			_scatter.erase(k)
	for k in _flourish.keys():
		_flourish[k] = int(_flourish[k]) + 1
		if int(_flourish[k]) > 24:
			_flourish.erase(k)
	for c in sim.creatures:
		var glide: bool = c.state == CreatureSim.State.DODGE and String(c.def.get("dodge", {}).get("trail", "")) == "paper"
		if glide:
			var tr: Array = _trails.get(c.id, [])
			tr.push_front(c.pos)
			if tr.size() > TRAIL:
				tr.pop_back()
			_trails[c.id] = tr
		elif _trails.has(c.id):
			var tr2: Array = _trails[c.id]
			tr2.pop_back()
			if tr2.is_empty():
				_trails.erase(c.id)
	queue_redraw()


func _shown(c: CreatureSim) -> bool:
	return fx == null or fx.shown(c)


func _draw() -> void:
	if sim == null:
		return
	for st in sim.storms:
		if fx == null or fx.sight_to(st["pos"]):
			_draw_storm(st)
	for id in _trails:
		if id < sim.creatures.size() and _shown(sim.creatures[id]):
			_draw_trail(_trails[id])
	for c in sim.creatures:
		if c.def.has("sheets") and _shown(c) and c.state != CreatureSim.State.KO:
			_draw_carried(c)
			_draw_sheets(c)


# ------------------------------------------------------------------ on him

func _side(c: CreatureSim) -> float:
	return -1.0 if c.facing.x < -0.2 else 1.0


## Sheets float in a slow ring over his hat, one per sheet in stock; a hit shakes them
## loose for a moment, and a regrown one arrives with a flash.
func _draw_sheets(c: CreatureSim) -> void:
	if c.state == CreatureSim.State.DODGE or c.sheets <= 0:
		return
	var top := float(c.def.get("fx_top", 60))
	var centre := c.pos + Vector2(0, -top - 6.0 - c.air_height())
	var jolt := float(_scatter.get(c.id, 0))
	for i in c.sheets:
		var a := _tick * 0.035 + TAU * i / 3.0
		var r := 9.0 + jolt * 0.6
		var at := centre + Vector2(cos(a) * r, sin(a) * r * 0.35 + sin(_tick * 0.08 + i) * 1.2)
		if jolt > 0.0:
			at += Vector2(sin(_tick * 1.7 + i * 2.0), cos(_tick * 1.3 + i)) * jolt * 0.3
		var fresh := i == c.sheets - 1 and _flourish.has(c.id)
		_paper_square(at.round(), 2.7, a * 0.6 + i, fresh and (int(_flourish[c.id]) / 3) % 2 == 0)
		if fresh and int(_flourish[c.id]) < 10:
			draw_arc(at, 3.0 + float(_flourish[c.id]) * 0.5, 0.0, TAU, 10,
				Color(1, 1, 1, 1.0 - float(_flourish[c.id]) / 10.0), 1.0)


## The crafts he has folded, where he carries them.
func _draw_carried(c: CreatureSim) -> void:
	if c.state == CreatureSim.State.DODGE or c.state == CreatureSim.State.FALLING:
		return
	var s := _side(c)
	var lift := Vector2(0, -c.air_height())
	var up := c.facing.y < -0.6  # facing away: he's in front of what he carries
	var down := c.facing.y > 0.6
	var xs := 0.35 if (up or down) else 1.0
	if c.folded.has("heavy"):
		var b := c.pos + lift + Vector2(BAND.x * s * xs, BAND.y)
		draw_shuriken(self, b.round(), 2.6, _tick * 0.0, false)
	if c.folded.has("skill_1"):
		var h := c.pos + lift + Vector2(HAND.x * s * xs, HAND.y + (2.0 if down else 0.0))
		draw_crane(self, h.round(), Vector2(s, 0), 0.75, sin(_tick * 0.12) * 0.5)
	if c.folded.has("skill_2"):
		var f := c.pos + lift + Vector2(SHOULDER.x * s * xs, SHOULDER.y)
		draw_frog(self, f.round(), s, 0.8)


func _draw_trail(tr: Array) -> void:
	for i in range(1, tr.size()):
		var a: Vector2 = tr[i - 1]
		var b: Vector2 = tr[i]
		var fade := 1.0 - float(i) / float(TRAIL)
		var z := Vector2(0, -16.0)
		if i % 2 == 0:
			draw_line(a + z, b + z, Color(C_PAPER[2], 0.6 * fade), 1.0)
		draw_line(a + z + Vector2(0, 2), b + z + Vector2(0, 2), Color(C_ORANGE, 0.35 * fade), 1.0)


# ------------------------------------------------------------------ the storm

## Thousand Cranes: a true circle on the floor where the storm is, a ring of cranes
## wheeling inside it at different heights, faster and tighter toward its end.
func _draw_storm(st: Dictionary) -> void:
	var at: Vector2 = st["pos"]
	var r := float(st["radius"])
	var k := clampf(float(st["t"]) / maxf(1.0, float(st["ticks"])), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_tick * 0.5)
	draw_circle(at, r, Color(C_NAVY, 0.10 + 0.06 * pulse))
	draw_arc(at, r, 0.0, TAU, 48, Color(C_ORANGE, 0.55 + 0.25 * pulse), 1.0)
	draw_arc(at, r * 0.62, 0.0, TAU, 40, Color(C_PAPER[2], 0.18), 1.0)
	var n := 9
	for i in n:
		var ring := r * (0.35 + 0.6 * float(i % 3) / 2.0) * (1.0 - k * 0.25)
		var a := _tick * (0.10 + 0.04 * float(i % 3)) * (1.0 + k) + TAU * i / n
		var z := 10.0 + 14.0 * float((i * 7) % 5) / 4.0 + sin(_tick * 0.2 + i) * 3.0
		var p := at + Vector2(cos(a) * ring, sin(a) * ring)
		# the shadow on the floor, then the crane above it, flying round
		draw_circle(p, 1.5, Color(0, 0, 0, 0.18))
		var heading := Vector2(-sin(a), cos(a))
		draw_crane(self, (p + Vector2(0, -z)).round(), heading, 1.0, sin(_tick * 0.45 + i * 1.3))


# ------------------------------------------------------------------ drawing kit (also FxView's)

## A tiny square of paper, turned `rot`, lit or plain.
func _paper_square(at: Vector2, half: float, rot: float, lit: bool) -> void:
	var d := Vector2.from_angle(rot) * half
	var n := d.orthogonal()
	var pts := PackedVector2Array([at + d, at + n, at - d, at - n])
	draw_colored_polygon(pts, C_PAPER[3] if lit else C_PAPER[2])
	draw_polyline(PackedVector2Array([at + d, at + n, at - d, at - n, at + d]), C_PAPER[0], 1.0)


## A paper crane seen from the side-ish: a body, a raised wing (`flap` -1..1), the neck
## and head forward along `dir`, the tail back.
static func draw_crane(ci: CanvasItem, at: Vector2, dir: Vector2, s: float, flap: float) -> void:
	var f := dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	f = Vector2(f.x, f.y * 0.5).normalized()  # seen from the stadium's angle
	var u := Vector2(0, -1)
	var k := 4.0 * s
	var head := at + f * k * 1.5 + u * k * 0.9
	var tail := at - f * k * 1.4 + u * k * 0.7
	var wing := at + u * k * (1.2 + flap * 0.9) - f * k * 0.2
	var body := PackedVector2Array([at + f * k * 0.9, at + u * k * 0.25, at - f * k * 0.9, at - u * k * 0.25])
	ci.draw_colored_polygon(PackedVector2Array([at + f * k * 0.4, wing + f * k * 0.3, at - f * k * 0.5]), C_PAPER[1])
	ci.draw_colored_polygon(body, C_PAPER[2])
	ci.draw_line(at + f * k * 0.7, head, C_PAPER[2], maxf(1.0, s))
	ci.draw_line(at - f * k * 0.7, tail, C_PAPER[1], maxf(1.0, s))
	ci.draw_colored_polygon(PackedVector2Array([at + f * k * 0.3, wing, at - f * k * 0.4]), C_PAPER[3])
	ci.draw_line(at + f * k * 0.3, wing, C_PAPER[0], 1.0)
	ci.draw_rect(Rect2(head.round(), Vector2.ONE), C_PAPER[0])


## The four-pointed paper star, spinning (`spin` in radians).
static func draw_shuriken(ci: CanvasItem, at: Vector2, r: float, spin: float, glow: bool) -> void:
	if glow:
		ci.draw_circle(at, r + 3.0, Color(C_ORANGE, 0.22))
	for i in 4:
		var d := Vector2.from_angle(spin + i * PI * 0.5)
		var n := d.orthogonal()
		ci.draw_colored_polygon(PackedVector2Array([at, at + d * r + n * r * 0.25, at + d * r * 0.2 + n * r * 0.5]),
			C_PAPER[2] if i % 2 == 0 else C_PAPER[1])
	ci.draw_rect(Rect2(at.round() - Vector2.ONE * 0.5, Vector2.ONE), C_PAPER[0])


## A paper frog, a little faceted lump with folded legs.
static func draw_frog(ci: CanvasItem, at: Vector2, side: float, s: float) -> void:
	var k := 3.0 * s
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(side * k * 1.2, 0), at + Vector2(0, -k * 0.9),
		at + Vector2(-side * k * 1.1, 0)]), C_PAPER[2])
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-side * k * 0.2, 0), at + Vector2(-side * k * 1.4, -k * 0.6),
		at + Vector2(-side * k * 1.1, k * 0.2)]), C_PAPER[1])
	ci.draw_line(at + Vector2(-side * k * 1.1, 0), at + Vector2(side * k * 1.2, 0), C_PAPER[0], 1.0)


## A dart in flight: a slim paper triangle along its path, a faint streak behind.
static func draw_dart(ci: CanvasItem, pr: Dictionary, tick: int) -> void:
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var d: Vector2 = Vector2(pr["vel"]).normalized()
	var at := pp + Vector2(0, -THROW_Z)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 2.0, Color(0, 0, 0, 0.22))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_line(at - d * 12.0, at - d * 4.0, Color(C_PAPER[2], 0.3), 1.0)
	var n := d.orthogonal()
	var tip := at + d * 5.0
	var tri := PackedVector2Array([tip, at - d * 3.0 + n * 2.0, at - d * 2.0, at - d * 3.0 - n * 2.0])
	ci.draw_colored_polygon(tri, C_PAPER[2])
	ci.draw_polyline(PackedVector2Array([tip, at - d * 3.0 + n * 2.0, at - d * 3.0 - n * 2.0, tip]), C_OUT, 1.0)
	ci.draw_line(tip, at - d * 2.0, C_PAPER[0], 1.0)


## The shuriken in flight: spinning fast, with a faint orange wake.
static func draw_thrown_shuriken(ci: CanvasItem, pr: Dictionary, tick: int) -> void:
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var d: Vector2 = Vector2(pr["vel"]).normalized()
	var at := pp + Vector2(0, -THROW_Z)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.25))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_line(at - d * 14.0, at - d * 4.0, Color(C_ORANGE, 0.35), 2.0)
	ci.draw_circle(at, 5.5, C_OUT)
	draw_shuriken(ci, at, 5.0, tick * (0.9 if d.x >= 0.0 else -0.9), false)


## The Paper Crane in flight: it flaps, faces where it's flying, and leaves a curl of
## paper dust as it turns.
static func draw_thrown_crane(ci: CanvasItem, pr: Dictionary, tick: int) -> void:
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var vel: Vector2 = pr["vel"]
	var at := pp + Vector2(0, -THROW_Z - 2.0 - sin(tick * 0.25) * 2.0)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.25))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 3:
		var back := at - vel.normalized() * (6.0 + i * 4.0)
		ci.draw_rect(Rect2(back.round(), Vector2.ONE), Color(C_PAPER[2], 0.5 - i * 0.15))
	draw_crane(ci, at, vel, 1.15, sin(tick * 0.6))


## Thousand Cranes in flight: a bundle of cranes arcing up and over, its landing circle
## (a true circle, the storm's size) already marked.
static func draw_bundle(ci: CanvasItem, pr: Dictionary, tick: int) -> void:
	var pp: Vector2 = pr["pos"]
	var vel: Vector2 = pr["vel"]
	var total := float(pr["time"])
	var left := float(pr["life"])
	var k := clampf(1.0 - left / total, 0.0, 1.0)
	var land := pp + vel * left
	var r := float(pr.get("storm", {}).get("radius", 40.0))
	var pulse := 0.5 + 0.5 * sin(tick * 0.7)
	ci.draw_arc(land, r, 0.0, TAU, 40, Color(C_ORANGE, 0.25 + 0.35 * pulse * k), 1.0)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.42))
	ci.draw_circle(Vector2.ZERO, 4.0, Color(0, 0, 0, 0.28))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var z := 14.0 + 4.0 * 30.0 * k * (1.0 - k)
	var at := (pp + Vector2(0, -z)).round()
	for i in 5:
		var a := tick * 0.3 + TAU * i / 5.0
		draw_crane(ci, at + Vector2(cos(a) * 5.0, sin(a) * 3.0), Vector2(cos(a + 1.6), 0.0), 0.6, sin(tick * 0.5 + i))
