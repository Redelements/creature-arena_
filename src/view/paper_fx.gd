class_name PaperFx
extends Node2D
## Mister Crease's paper, drawn over the fighters: the sheets of his Paper Stock floating
## above the hat, the crafts he has folded and carries (the shuriken in his hat band, the
## crane on his near hand, the three frogs on his far shoulder), the Paper Plane's trail,
## the Thousand Cranes storm, and the paper the Paper Frogs leave behind (a flick on each
## landing, a burst when one hits or unfolds). The static draw_* functions are FxView's
## projectiles (darts, shuriken, the crane, the hopping frogs, the bundle in flight). Reads
## the sim, never writes it; anything a hidden fighter does stays hidden (FxView.shown /
## sight_to). Everything is flat paper: light top faces, darker sides, a crisp outline, a
## fold line where two faces meet, and a glimpse of the warmer back when a sheet turns over.

const C_PAPER: Array[Color] = [Color("8e8c86"), Color("d8d6ce"), Color("f6f4ec"), Color("ffffff")]
const C_BACK := Color("e4dcc8")  ## the back of a sheet, a shade warmer
const C_FOLD := Color("6e6c66")  ## a valley fold, darker than the paper's grey edge
const C_OUT := Color("1b1e26")
const C_ORANGE := Color("ff9a2e")
const C_NAVY := Color("1e488e")
const C_MAROON := Color("761240")
const THROW_Z := 18.0
## Where the carried crafts sit on him (px above his feet; x is toward his facing).
const BAND := Vector2(5.0, -58.0)
const HAND := Vector2(12.0, -35.0)
const SHOULDER := Vector2(-8.0, -47.0)
const TRAIL := 14
## A Paper Frog's hop: `HOP` ticks from one landing to the next, `HOP_H` px high at the top.
const HOP := 9
const HOP_H := 11.0
## How a frog is shaped through its hop (ticks since it landed): -1 flat on the landing,
## then stretched off the ground, round at the top, legs out again coming down.
const HOP_SHAPE: Array[float] = [-1.0, 0.9, 0.6, 0.3, 0.0, 0.1, 0.3, 0.5, 0.3]

var sim: MatchSim
var fx: FxView
var _tick := 0
var _scatter := {}  ## creature id -> ticks of a hit shaking the sheets loose
var _flourish := {}  ## creature id -> ticks since a sheet regrew
var _trails := {}  ## creature id -> recent positions while gliding
var _storm_seen := {}  ## storm key -> true, for the start shake
var _frogs := {}  ## frog key -> {pos, vel, hop}: the hopping frogs seen last tick
var _bits: Array[Dictionary] = []  ## loose paper: flecks, dust puffs, an unfolding sheet


func set_sim(s: MatchSim) -> void:
	sim = s
	_scatter.clear()
	_flourish.clear()
	_trails.clear()
	_storm_seen.clear()
	_frogs.clear()
	_bits.clear()
	queue_redraw()


## Each tick: react to the sim's events (a hit scatters the sheets, a regrown one flashes,
## a storm shakes the screen), remember the glide's trail, and follow the frogs (a flick of
## paper when one lands, a burst when one is gone).
func advance(events: Array) -> void:
	if sim == null:
		return
	_tick += 1
	var ends: Array[Vector2] = []  # where shots ended by hitting something this tick
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
			"projectile_end":
				if float(e.get("power", 0.0)) > 0.0:
					ends.append(Vector2(e["pos"]))
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
	_follow_frogs(ends)
	_step_bits()
	queue_redraw()


func _shown(c: CreatureSim) -> bool:
	return fx == null or fx.shown(c)


func _sight(p: Vector2) -> bool:
	return fx == null or fx.sight_to(p)


func _draw() -> void:
	if sim == null:
		return
	for st in sim.storms:
		if fx == null or fx.sight_to(st["pos"]):
			_draw_storm(st)
	for id in _trails:
		if id < sim.creatures.size() and _shown(sim.creatures[id]):
			_draw_trail(_trails[id])
	for b in _bits:
		_draw_bit(b)
	for c in sim.creatures:
		if c.def.has("sheets") and _shown(c) and c.state != CreatureSim.State.KO:
			_draw_carried(c)
			_draw_sheets(c)


# ------------------------------------------------------------------ on him

func _side(c: CreatureSim) -> float:
	return -1.0 if c.facing.x < -0.2 else 1.0


## Sheets float in a slow ring over his hat, one per sheet in stock, each turning over
## as it drifts (a flutter, the warmer back showing for a moment); a hit shakes them
## loose, and a regrown one arrives with a flash.
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
		var turn := cos(_tick * 0.06 + i * 2.1 + jolt * 0.4)  # the sheet turning over, slowly
		_paper_sheet(at.round(), 3.0, a * 0.6 + i, turn, fresh and (int(_flourish[c.id]) / 3) % 2 == 0)
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
		# the three frogs, a little cluster on his shoulder: the back one higher and smaller
		var f := c.pos + lift + Vector2(SHOULDER.x * s * xs, SHOULDER.y)
		var dir := Vector2(s, 0)
		draw_frog(self, (f + Vector2(s * 1.0, -4.0)).round(), dir, 0.55, 0.0)
		draw_frog(self, (f + Vector2(-s * 3.5 * xs, 0.0)).round(), dir, 0.62, 0.0)
		draw_frog(self, (f + Vector2(s * 3.0 * xs, 0.5)).round(), dir, 0.62, 0.0)


## The Paper Plane's trail: a ribbon of paper that thins and fades behind him, with a
## loose sheet or two turning over in it.
func _draw_trail(tr: Array) -> void:
	var z := Vector2(0, -16.0)
	for i in range(1, tr.size()):
		var a: Vector2 = tr[i - 1]
		var b: Vector2 = tr[i]
		var fade := 1.0 - float(i) / float(TRAIL)
		var d := b - a
		if d.length_squared() < 0.01:
			continue
		var n := d.normalized().orthogonal() * (0.8 + 2.2 * fade)
		var tone := C_PAPER[3].lerp(C_PAPER[1], 1.0 - fade)
		draw_colored_polygon(PackedVector2Array([a + z - n, b + z - n, b + z + n, a + z + n]), Color(tone, 0.6 * fade))
		draw_line(a + z + n, b + z + n, Color(C_ORANGE, 0.4 * fade), 1.0)
		if i % 4 == 2:
			_paper_sheet((a + z + Vector2(0, -3.0 - float(i) * 0.3)).round(), 1.6 + fade, float(i) * 0.7,
				sin(_tick * 0.35 + float(i)), false)


# ------------------------------------------------------------------ the frogs' paper

func _frog_kind(pr: Dictionary) -> bool:
	if not pr.has("lane") or not pr.has("move"):
		return false
	var who := int(pr["owner"])
	if who < 0 or who >= sim.creatures.size():
		return false
	var mv: Dictionary = sim.creatures[who].moves().get(String(pr["move"]), {})
	return String(mv.get("fx", {}).get("projectile", "")) == "frog"


## Keeps up with the hopping frogs in the sim: a flick of paper and a puff of dust when
## one lands; when one is gone, torn paper where it hit something (`ends`), or the frog
## unfolding flat where it just ran out.
func _follow_frogs(ends: Array[Vector2]) -> void:
	var seen := {}
	for pr in sim.projectiles:
		if not _frog_kind(pr):
			continue
		var key := "%d:%d:%d" % [int(pr["owner"]), int(pr["serial"]), int(pr["lane"])]
		var hop := int(frog_hop(pr)[2])
		var was: Dictionary = _frogs.get(key, {})
		if not was.is_empty() and hop > int(was["hop"]) and _sight(pr["pos"]):
			_landing(Vector2(pr["pos"]), Vector2(pr["vel"]))
		seen[key] = {"pos": Vector2(pr["pos"]), "vel": Vector2(pr["vel"]), "hop": hop}
	for key in _frogs:
		if seen.has(key):
			continue
		var last: Dictionary = _frogs[key]
		var at: Vector2 = last["pos"] + last["vel"]
		if not _sight(at):
			continue
		var struck := false
		for p in ends:
			if p.distance_to(at) < 20.0:
				struck = true
				break
		if struck:
			_torn(at, Vector2(last["vel"]))
		else:
			_bits.append({"kind": "unfold", "pos": at, "life": 22, "t": 0, "rot": Vector2(last["vel"]).angle()})
	_frogs = seen


func _landing(at: Vector2, vel: Vector2) -> void:
	var back := -vel.normalized()
	_bits.append({"kind": "puff", "pos": at, "life": 10, "t": 0})
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		_bits.append({"kind": "fleck", "pos": at + back * 2.0, "z": 1.0, "life": 14, "t": 0,
			"vel": back * 0.6 + back.orthogonal() * side * 0.5, "vz": 1.4 + 0.3 * i,
			"rot": randf() * TAU, "vrot": randf_range(-0.5, 0.5), "half": 1.3})


func _torn(at: Vector2, vel: Vector2) -> void:
	_bits.append({"kind": "puff", "pos": at, "life": 12, "t": 0})
	var fwd := vel.normalized()
	for i in 7:
		var a := randf() * TAU
		var v := Vector2.from_angle(a) * randf_range(0.5, 1.6) + fwd * 0.6
		_bits.append({"kind": "fleck", "pos": at, "z": 4.0 + randf() * 4.0, "life": 18 + i, "t": 0,
			"vel": v, "vz": randf_range(1.2, 2.6), "rot": randf() * TAU, "vrot": randf_range(-0.6, 0.6),
			"half": randf_range(1.2, 2.2), "torn": true})


func _step_bits() -> void:
	var keep: Array[Dictionary] = []
	for b in _bits:
		b["t"] = int(b["t"]) + 1
		if int(b["t"]) >= int(b["life"]):
			continue
		if String(b["kind"]) == "fleck":
			var vel: Vector2 = b["vel"]
			b["pos"] = Vector2(b["pos"]) + vel
			b["vel"] = vel * 0.9
			b["z"] = float(b["z"]) + float(b["vz"])
			b["vz"] = float(b["vz"]) - 0.22
			b["rot"] = float(b["rot"]) + float(b["vrot"])
			if float(b["z"]) < 0.0:  # settles on the floor, rocking once
				b["z"] = 0.0
				b["vz"] = 0.0
				b["vrot"] = float(b["vrot"]) * 0.5
		keep.append(b)
	_bits = keep


func _draw_bit(b: Dictionary) -> void:
	var k := float(b["t"]) / float(b["life"])
	var at: Vector2 = b["pos"]
	match String(b["kind"]):
		"puff":
			# a flat puff of dust on the floor, spreading and thinning
			draw_set_transform(at, 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 2.0 + 6.0 * k, Color(0.52, 0.42, 0.28, 0.35 * (1.0 - k)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"fleck":
			var z := float(b["z"])
			var half := float(b["half"])
			if z > 0.5:
				draw_set_transform(at, 0.0, Vector2(1.0, 0.45))
				draw_circle(Vector2.ZERO, half * 0.8, Color(0, 0, 0, 0.18 * (1.0 - k)))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var p := (at + Vector2(0, -z)).round()
			var turn := cos(float(b["rot"]) * 1.7)
			if bool(b.get("torn", false)):
				_paper_scrap(p, half, float(b["rot"]), turn, 1.0 - k * k)
			else:
				_paper_sheet(p, half, float(b["rot"]), turn, false, 1.0 - k * k)
		"unfold":
			# the frog opening out flat on the floor: a sheet unfolding, its creases showing, then gone
			var half := lerpf(3.0, 8.0, minf(1.0, k * 2.5))
			var alpha := 1.0 if k < 0.55 else 1.0 - (k - 0.55) / 0.45
			draw_set_transform(at, float(b["rot"]), Vector2(1.0, 0.5))
			var pts := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
			draw_colored_polygon(pts, Color(C_PAPER[2], alpha))
			draw_line(Vector2(-half, -half), Vector2(half, half), Color(C_FOLD, 0.7 * alpha), 1.0)
			draw_line(Vector2(-half, half), Vector2(half, -half), Color(C_PAPER[0], 0.7 * alpha), 1.0)
			draw_line(Vector2(0, -half), Vector2(0, half), Color(C_PAPER[0], 0.5 * alpha), 1.0)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(C_OUT, 0.8 * alpha), 1.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ the storm

## Thousand Cranes: a true circle on the floor where the storm is, a ring of cranes
## wheeling inside it at different heights, faster and tighter toward its end, and loose
## sheets skating round the floor under them.
func _draw_storm(st: Dictionary) -> void:
	var at: Vector2 = st["pos"]
	var r := float(st["radius"])
	var k := clampf(float(st["t"]) / maxf(1.0, float(st["ticks"])), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_tick * 0.5)
	draw_circle(at, r, Color(C_NAVY, 0.10 + 0.06 * pulse))
	draw_arc(at, r, 0.0, TAU, 48, Color(C_ORANGE, 0.55 + 0.25 * pulse), 1.0)
	draw_arc(at, r * 0.62, 0.0, TAU, 40, Color(C_PAPER[2], 0.18), 1.0)
	for i in 6:
		var a := -_tick * 0.07 * (1.0 + k) + TAU * i / 6.0
		var ring := r * (0.5 + 0.35 * float(i % 2))
		var p := at + Vector2(cos(a) * ring, sin(a) * ring)
		_paper_sheet(p.round(), 2.0, a + float(i), cos(_tick * 0.3 + i * 1.1), false, 0.8)
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

## A small sheet of paper, turned `rot`, seen turning over: `turn` is 1 flat to us, 0
## edge-on, -1 showing its warmer back. Folded once across the middle, the lit half
## brighter than the other.
func _paper_sheet(at: Vector2, half: float, rot: float, turn: float, lit: bool, alpha := 1.0) -> void:
	var d := Vector2.from_angle(rot) * half
	var n := d.orthogonal() * maxf(0.12, absf(turn))
	var pts := PackedVector2Array([at + d, at + n, at - d, at - n])
	if turn < 0.0:
		draw_colored_polygon(pts, Color(C_BACK, alpha))
	else:
		draw_colored_polygon(PackedVector2Array([at + d, at + n, at - d]), Color(C_PAPER[3], alpha))
		draw_colored_polygon(PackedVector2Array([at + d, at - n, at - d]), Color(C_PAPER[3] if lit else C_PAPER[2], alpha))
		if half >= 2.5:
			draw_line(at + d, at - d, Color(C_PAPER[0], 0.6 * alpha), 1.0)
	draw_polyline(PackedVector2Array([at + d, at + n, at - d, at - n, at + d]), Color(C_PAPER[0], 0.8 * alpha), 1.0)


## A torn scrap: a sheet with a ragged edge, light or grey as it tumbles.
func _paper_scrap(at: Vector2, half: float, rot: float, turn: float, alpha: float) -> void:
	var d := Vector2.from_angle(rot) * half
	var n := d.orthogonal() * maxf(0.15, absf(turn))
	var pts := PackedVector2Array([at + d, at + n * 0.6 + d * 0.3, at + n, at - d * 0.8 + n * 0.3, at - d, at - n])
	draw_colored_polygon(pts, Color(C_BACK if turn < 0.0 else C_PAPER[3], alpha))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[5], pts[0]]),
		Color(C_PAPER[0], 0.7 * alpha), 1.0)


## A paper crane seen from the side-ish: a body, a raised wing (`flap` -1..1, the wing's
## underside showing on the downstroke), the neck and head forward along `dir`, the tail
## back, a fold line at the wing root.
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
	ci.draw_colored_polygon(PackedVector2Array([at + f * k * 0.9, at + u * k * 0.25, at - u * k * 0.25]), C_PAPER[3])
	ci.draw_line(at + f * k * 0.7, head, C_PAPER[2], maxf(1.0, s))
	ci.draw_line(at - f * k * 0.7, tail, C_PAPER[1], maxf(1.0, s))
	ci.draw_colored_polygon(PackedVector2Array([at + f * k * 0.3, wing, at - f * k * 0.4]),
		C_PAPER[3] if flap >= -0.3 else C_BACK)
	ci.draw_line(at + f * k * 0.3, wing, C_PAPER[0], 1.0)
	ci.draw_line(at - f * k * 0.4, at + f * k * 0.3, C_FOLD, 1.0)
	ci.draw_rect(Rect2(head.round(), Vector2.ONE), C_PAPER[0])


## The four-pointed paper star, spinning (`spin` in radians): each blade a lit and a
## shaded face either side of its fold.
static func draw_shuriken(ci: CanvasItem, at: Vector2, r: float, spin: float, glow: bool) -> void:
	if glow:
		ci.draw_circle(at, r + 3.0, Color(C_ORANGE, 0.22))
	for i in 4:
		var d := Vector2.from_angle(spin + i * PI * 0.5)
		var n := d.orthogonal()
		var tip := at + d * r + n * r * 0.25
		ci.draw_colored_polygon(PackedVector2Array([at, tip, at + d * r * 0.2 + n * r * 0.5]),
			C_PAPER[2] if i % 2 == 0 else C_PAPER[1])
		ci.draw_colored_polygon(PackedVector2Array([at, tip, at + d * r * 0.55 + n * r * 0.05]),
			C_PAPER[3] if i % 2 == 0 else C_PAPER[2])
		if r >= 4.0:
			ci.draw_line(at, tip, Color(C_PAPER[0], 0.7), 1.0)
	ci.draw_rect(Rect2(at.round() - Vector2.ONE * 0.5, Vector2.ONE), C_PAPER[0])


## A paper frog facing `dir`: a wedge of a body with a lit top face and a shaded side, a
## fold between body and haunch, and the hind legs folded behind in a Z. `shape` is -1
## squashed flat (just landed) to 1 stretched out (in the air, legs out).
static func draw_frog(ci: CanvasItem, at: Vector2, dir: Vector2, s: float, shape := 0.0) -> void:
	var f := dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	f = Vector2(f.x, f.y * 0.5).normalized()
	var u := Vector2(0, -1)
	var k := 3.6 * s
	var sq := maxf(0.0, -shape)
	var st := maxf(0.0, shape)
	var sx := 1.0 + 0.25 * sq - 0.15 * st
	var sy := 1.0 - 0.5 * sq + 0.35 * st
	var P := func(x: float, y: float) -> Vector2:
		return at + f * (x * k * sx) + u * (y * k * sy)
	# the body: a low wedge, snout in front, the hump and the brow (eye bump) on top
	var snout: Vector2 = P.call(1.7, 0.3)
	var chin: Vector2 = P.call(1.5, 0.0)
	var belly_f: Vector2 = P.call(0.9, 0.0)
	var belly_b: Vector2 = P.call(-1.2, 0.0)
	var rump: Vector2 = P.call(-1.4, 0.55)
	var back: Vector2 = P.call(-0.9, 1.15)
	var hump: Vector2 = P.call(-0.1, 1.3)
	var brow: Vector2 = P.call(0.7, 1.0)
	var eye_t: Vector2 = P.call(1.0, 1.25)
	var eye_f: Vector2 = P.call(1.25, 0.85)
	var body := PackedVector2Array([chin, snout, eye_f, eye_t, brow, hump, back, rump, belly_b, belly_f])
	ci.draw_colored_polygon(body, C_PAPER[1])
	# the lit top face, and the folds: the haunch crease, the head crease
	ci.draw_colored_polygon(PackedVector2Array([back, hump, brow, eye_t, eye_f, P.call(1.1, 0.55),
		P.call(0.1, 0.7), P.call(-0.8, 0.6)]), C_PAPER[3])
	ci.draw_line(P.call(-0.8, 0.6), belly_b, C_FOLD, 1.0)
	ci.draw_line(brow, belly_f, Color(C_PAPER[0], 0.8), 1.0)
	# hind legs: a Z-fold off the rump, folded under on the squash, out behind on the stretch
	var knee: Vector2 = P.call(lerpf(-1.9, -2.4, st) + 0.35 * sq, lerpf(1.0, 0.7, st) - 0.45 * sq)
	var foot: Vector2 = P.call(lerpf(-2.4, -3.1, st) + 0.5 * sq, 0.0)
	var heel: Vector2 = P.call(-1.6, 0.0)
	ci.draw_colored_polygon(PackedVector2Array([rump, knee, foot, heel, belly_b]), C_PAPER[1])
	ci.draw_colored_polygon(PackedVector2Array([rump, knee, P.call(-1.8, 0.55)]), C_PAPER[2])
	ci.draw_line(knee, heel, C_FOLD, 1.0)
	ci.draw_polyline(PackedVector2Array([rump, knee, foot, heel]), C_OUT, 1.0)
	# the outline, then the eye
	ci.draw_polyline(PackedVector2Array([belly_b, belly_f, chin, snout, eye_f, eye_t, brow, hump, back, rump]), C_OUT, 1.0)
	var eye: Vector2 = (P.call(0.95, 0.95) as Vector2).round()
	ci.draw_rect(Rect2(eye, Vector2.ONE * (2.0 if k >= 4.5 else 1.0)), C_OUT)


## Where a hopping frog is in its hop: [z (px above the floor), shape (-1..1 for
## draw_frog), hop index]. Timed from `life_total - life`, so it's the same on every
## peer; the lanes start together but slip a couple of ticks apart over the first hop,
## so the three don't bob as one.
static func frog_hop(pr: Dictionary) -> Array:
	var total := int(pr.get("life_total", 38))
	var age := total - int(pr.get("life", total))
	var lane := int(pr.get("lane", 0))
	var eff := float(age) + float((lane + 1) * 2) * minf(1.0, float(age) / float(HOP))
	var hop := int(eff / float(HOP))
	var t := (eff - float(hop) * HOP) / float(HOP)
	var z := HOP_H * 4.0 * t * (1.0 - t)
	var i := int(t * float(HOP))
	var shape := HOP_SHAPE[clampi(i, 0, HOP_SHAPE.size() - 1)]
	if age == 0:
		shape = 0.9  # straight off his hand
	return [z, shape, hop]


## A Paper Frog in flight: hopping along its path (a short arc, a squash on landing, a
## stretch on takeoff), its shadow on the floor shrinking as it rises.
static func draw_frog_shot(ci: CanvasItem, pr: Dictionary, _tick: int) -> void:
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var vel: Vector2 = pr["vel"]
	var hop := frog_hop(pr)
	var z := float(hop[0])
	var lift := z / HOP_H
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.42))
	ci.draw_circle(Vector2.ZERO, lerpf(6.0, 3.5, lift), Color(0, 0, 0, lerpf(0.3, 0.14, lift)))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_frog(ci, pp + Vector2(0, -z - 1.0), vel, 1.35, float(hop[1]))


## A dart in flight: a slim paper triangle along its path, one face lit and one shaded
## either side of its fold, a faint streak behind.
static func draw_dart(ci: CanvasItem, pr: Dictionary, _tick: int) -> void:
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var d: Vector2 = Vector2(pr["vel"]).normalized()
	var at := pp + Vector2(0, -THROW_Z)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 2.0, Color(0, 0, 0, 0.22))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_line(at - d * 12.0, at - d * 4.0, Color(C_PAPER[2], 0.3), 1.0)
	var n := d.orthogonal()
	var tip := at + d * 5.0
	ci.draw_colored_polygon(PackedVector2Array([tip, at - d * 3.0 + n * 2.0, at - d * 2.0]), C_PAPER[3])
	ci.draw_colored_polygon(PackedVector2Array([tip, at - d * 2.0, at - d * 3.0 - n * 2.0]), C_PAPER[1])
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
