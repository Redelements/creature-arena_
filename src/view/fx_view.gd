class_name FxView
extends Node2D
## Cosmetic effects. Two things drive them:
##
##   - Simulation events (hits, slams, grabs, falls, KOs...), passed in through spawn().
##   - A per-frame watch over every creature that notices move starts, strikes, charging,
##     dashes, Cairn's stones and knockouts. It reads the "fx" block of the move being
##     performed and the "ko_fx" block of the creature, both in data/creatures/*.json,
##     so a new creature gets effects by adding data, not code.
##
## Nothing here feeds back into the simulation, so it is free to use randomness, and
## replays and tests are unaffected. Effects draw in two layers: this node, above the
## fighters, and `ground` (an FxGround), below them.
##
## Move "fx" keys:
##   smear        "thrust" | "arc" | "rise" | "flurry"  a swipe drawn on each strike
##   size         smear scale (default 1)
##   charge       "pebbles" | "drips"                  while a heavy is held
##   afterimage   [from, to]   ghost trail during those ticks of the move
##   ghost_color  tint of the afterimages
##   trail        "gravel"     debris kicked up during the afterimage window
##   suction      true         air pulled into the mouth during startup
##   impact       "spire" | "geysers"                   on the move's last strike
##   speedlines   true         anime speed lines while the move is active
##   rain         true         a downpour and darkened arena
##   telegraph    true         marks where a leaping move will land
##   projectile   "wave"       draws the move's projectile as water
##   impact       also "lash" (stone chips), "quake" (a stomp's shockwave),
##                "avalanche" (boulders raining onto the strike)
## Creature "ko_fx" keys: style "scatter" (the sprite breaks into horizontal pieces that
## tumble across the floor), "crack" (cracks, water gushing out, rubble) or "crumble"
## (cracks, then the neck stones burst loose).
## Status drawn from creature state: Stoneskin plates while `shield` > 0, a rooted ring
## while armored, pebbles at the feet while slowed, a red "!" while taunted.

const SHEET := preload("res://assets/sprites/fx.png")
const GRAVITY := 0.2
const FOREVER := 1.0e9

const C_OUTLINE := Color("1b1e26")
const C_WATER := Color("549cd0")
const C_WATER_L := Color("a8d6f0")
const C_FOAM := Color("e8f4fa")
const C_CON: Array[Color] = [Color("5d6470"), Color("8a909a"), Color("b8bcc2")]
const C_STONE: Array[Color] = [Color("706250"), Color("94846c"), Color("b2a38a")]
const C_STACK: Array[Color] = [Color("94846c"), Color("78818c"), Color("626876")]
const C_HEAD := Color("aea89d")
const C_PEBBLE: Array[Color] = [Color("605c56"), Color("827c74")]
const C_CRACK := Color("28221e")
const C_SPARK: Array[Color] = [Color("fff6d5"), Color("ffd04a"), Color("ff8a3a")]
const C_DIM := Color(0.02, 0.03, 0.07)
const C_PARRY := Color("9ee6ff")
const C_WARN := Color(1.0, 0.36, 0.28)
const C_GREY: Array[Color] = [Color("5a585c"), Color("7f7f7f"), Color("aaa8a6"), Color("cecccb")]
const C_CRAG: Array[Color] = [Color("8c4547"), Color("b5665f"), Color("d08c84")]
const C_AMBER := Color("ffc45c")
const C_TAUNT := Color("ff4a3a")

## Asks AudioView for a sound that belongs to a timed effect (a KO scatter, geysers...).
signal cue(sound: String)

var sim: MatchSim
var views: Array = []  ## CreatureView per creature, same order as sim.creatures
var ground: FxGround
var time_scale := 1.0  ## main slows this for KO slow-motion; 0 holds everything still
var shake_out := 0.0  ## extra screen shake asked for by effects; main takes it each frame

var _parts: Array[Dictionary] = []
var _incoming: Array[Dictionary] = []
var _font: Font = ThemeDB.fallback_font
var _tick := 0
var _watch := {}
var _last_push := {}
var _dark := 0.0
var _rain := 0.0


func bind_ground(g: FxGround) -> void:
	ground = g
	ground.painter = _paint.bind(true)


func clear() -> void:
	_parts.clear()
	_incoming.clear()
	_watch.clear()
	_last_push.clear()
	_dark = 0.0
	_rain = 0.0
	time_scale = 1.0
	shake_out = 0.0
	queue_redraw()


# ------------------------------------------------------------------ events

func spawn(e: Dictionary) -> void:
	var p: Vector2 = e["pos"]
	var power: float = e["power"]
	match String(e["type"]):
		"hit":
			var big := power >= 9.0 or bool(e.get("heavy", false))
			_add({"kind": "spark", "pos": p, "life": 12 if big else 8, "scale": 2.0 if big else 1.0})
			var push := _note_push(e)
			if big:
				_add({"kind": "lines", "pos": p, "life": 8, "size": 1.4 if power >= 14.0 else 1.0, "color": C_SPARK[0]})
			for i in (6 if big else 3):
				_px(p, push.rotated(randf_range(-0.7, 0.7)) * randf_range(1.2, 2.8), C_SPARK[randi() % 3], 12)
			var col := Color("ffe08a")
			if float(e.get("variety", 1.0)) >= 1.5:
				col = Color("ff9a5a")
			elif float(e.get("variety", 1.0)) > 1.0:
				col = Color("ffd166")
			if bool(e.get("stale", false)):
				col = Color("b8b8b8")
			_text(p + Vector2(0, -6), str(int(round(power))), col)
		"block":
			_add({"kind": "spark", "pos": p, "life": 6, "scale": 0.75})
			_add({"kind": "ring", "pos": p + Vector2(0, 4), "life": 8, "radius": 10.0, "color": Color("9ec5ff")})
			_text(p + Vector2(0, -6), "BLOCK", Color("9ec5ff"))
		"guard_break":
			_add({"kind": "lines", "pos": p + Vector2(0, -16), "life": 10, "size": 1.3, "color": Color("ff9a5a")})
			for i in 8:
				_px(p + Vector2(0, -16), Vector2.from_angle(randf() * TAU) * randf_range(1.0, 2.5), Color("9ec5ff"), 16)
			_text(p + Vector2(0, -34), "GUARD BREAK", Color("ff9a5a"))
		"slam":
			var full := power >= 1.0
			_add({"kind": "ring", "pos": p, "life": 18 if full else 12, "radius": 34.0 if full else 18.0})
			var n := 10 if full else 6
			for i in n:
				var a := TAU * i / n + randf() * 0.3
				var r := (22.0 if full else 12.0) + randf() * 6.0
				_dust(p + Vector2(cos(a) * r, sin(a) * r * 0.5), Vector2(cos(a), sin(a) * 0.5 - 0.6) * 0.5)
			_slam_debris(p, full)
		"bounce":
			_add({"kind": "spark", "pos": p + Vector2(0, -12), "life": 8, "scale": 1.0})
			_add({"kind": "lines", "pos": p + Vector2(0, -12), "life": 6, "size": 0.8, "color": C_SPARK[0]})
			_dust(p, Vector2(0, -0.4))
		"fall":
			for i in 4:
				_dust(p + Vector2(randf_range(-8, 8), randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.5))
			_later(CreatureSim.FALL_TICKS - 6, _pit_plume.bind(p))
		"land", "dodge":
			_dust(p + Vector2(0, 1), Vector2(0, -0.3))
		"ko":
			var who := int(e.get("who", -1))
			var styled: bool = who >= 0 and who < sim.creatures.size() \
				and not sim.creatures[who].def.get("ko_fx", {}).is_empty()
			_add({"kind": "spark", "pos": p + Vector2(0, -16), "life": 16, "scale": 1.5 if styled else 2.5})
			_add({"kind": "lines", "pos": p + Vector2(0, -16), "life": 14, "size": 2.0, "color": Color.WHITE})
		"slip":
			_add({"kind": "ring", "pos": p + Vector2(0, 20), "life": 14, "radius": 24.0, "color": C_PARRY})
			_add({"kind": "lines", "pos": p, "life": 10, "size": 1.3, "color": C_PARRY})
			for i in 6:
				_px(p, Vector2.from_angle(randf() * TAU) * randf_range(1.0, 2.2), Color.WHITE, 12)
			_text(p, "SLIP!", C_PARRY)
		"grab":
			_text(p, "GULP!", Color("b6f28a"))
			if int(e.get("attacker", -1)) >= 0:
				var a := sim.creatures[int(e["attacker"])]
				var mouth := a.pos - a.facing * 6.0
				for i in 14:
					var v := (-a.facing).rotated(randf_range(-0.6, 0.6)) * randf_range(0.8, 2.2)
					_drop(mouth, 10.0, v, randf_range(0.8, 2.2), true)
		"windup":
			_windup_tell(e)
		"tag":
			# A tag: the partner swaps in with a burst of dust and a call-out.
			_add({"kind": "ring", "pos": p, "life": 16, "radius": 30.0, "color": Color("9ee6ff")})
			_add({"kind": "lines", "pos": p + Vector2(0, -18), "life": 10, "size": 1.2, "color": Color("9ee6ff")})
			for i in 8:
				var a := TAU * i / 8.0
				_dust(p + Vector2(cos(a) * 10.0, sin(a) * 4.0), Vector2(cos(a), sin(a) * 0.5 - 0.5) * 0.6)
			var label := "TAG CANCEL!" if String(e.get("kind", "")) == "cancel" else "TAG!"
			_text(p + Vector2(0, -44), label, Color("9ee6ff"), 9)
		"enter":
			_add({"kind": "ring", "pos": p, "life": 20, "radius": 34.0, "color": Color("ffd166")})
			for i in 6:
				_dust(p + Vector2(randf_range(-10, 10), randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.5))
			_text(p + Vector2(0, -46), String(e.get("name", "")).to_upper() + " IN", Color("ffd166"), 9)
		"breakaway":
			_add({"kind": "ring", "pos": p + Vector2(0, 16), "life": 16, "radius": 30.0})
			_text(p + Vector2(0, -10), "BREAKAWAY", Color("c9a7ff"))
		"projectile":
			# Runoff leaves the hand: a slap of water.
			var owner := _owner_near(p)
			var at := p + (owner.facing * 14.0 if owner != null else Vector2.ZERO)
			for i in 10:
				_drop(at, 2.0, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.2), randf_range(1.5, 3.0), true)
			_add({"kind": "ripple", "pos": at, "life": 20, "radius": 20.0})
			for i in 3:
				_dust(at + Vector2(randf_range(-6, 6), randf_range(-2, 2)), Vector2(randf_range(-0.3, 0.3), -0.4))
		"projectile_end":
			var n := 12 if power >= 1.0 else 6
			for i in n:
				_drop(p, 3.0, Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.4), randf_range(1.0, 2.6), true)
			_add({"kind": "ripple", "pos": p, "life": 18, "radius": 16.0})
		"armor":
			var tgt := _creature(int(e.get("target", -1)))
			_add({"kind": "spark", "pos": p, "life": 6, "scale": 0.8})
			_add({"kind": "ring", "pos": p + Vector2(0, 8), "life": 9, "radius": 12.0, "color": C_AMBER})
			if tgt != null:
				for i in 4:
					_chunk(tgt.pos, _chest(tgt), _note_push(e).rotated(randf_range(-1.2, 1.2)) * randf_range(0.5, 1.2),
						randf_range(1.0, 2.0), 2.0, C_GREY[randi() % 3], 30.0)
			_text(p + Vector2(0, -6), str(int(round(power))) if power >= 0.5 else "ROOTED", C_AMBER)
		"shield_up":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				var at := c.pos + Vector2(0, -_chest(c))
				_add({"kind": "ring", "pos": c.pos, "life": 14, "radius": c.radius + 10.0, "color": C_GREY[3]})
				for i in 8:
					_px(at + Vector2.from_angle(TAU * i / 8.0) * 16.0, -Vector2.from_angle(TAU * i / 8.0) * 0.8,
						C_GREY[3], 14)
				_text(c.pos + Vector2(0, -_top(c) - 8), "STONESKIN", C_GREY[3], 7, 34.0)
		"shield_break":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				for i in 9:
					_chunk(c.pos, _chest(c) + randf_range(-6, 6), Vector2.from_angle(randf() * TAU) * randf_range(0.6, 1.8),
						randf_range(1.2, 2.4), randf_range(2.0, 3.0), C_GREY[randi() % 3], 40.0)
				_add({"kind": "lines", "pos": c.pos + Vector2(0, -_chest(c)), "life": 8, "size": 1.0, "color": C_GREY[3]})
				_text(c.pos + Vector2(0, -_top(c) - 8), "SHIELD BROKEN", C_GREY[2], 7, 34.0)
		"slow":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				for i in 4:
					_dust(c.pos + Vector2(randf_range(-8, 8), randf_range(-2, 2)), Vector2(randf_range(-0.3, 0.3), -0.3))
				_text(c.pos + Vector2(0, -_top(c) - 14), "SLOWED", Color("b9c6d6"), 7, 40.0)
		"taunt":
			_add({"kind": "ring", "pos": p, "life": 14, "radius": 18.0, "color": C_TAUNT})
		"roar":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				_add({"kind": "ring", "pos": c.pos, "life": 20, "radius": power, "color": C_TAUNT})
				_add({"kind": "ring", "pos": c.pos, "life": 14, "radius": power * 0.6, "color": C_AMBER})
				_add({"kind": "lines", "pos": c.pos + Vector2(c.facing.x * 12.0, -_top(c) + 10), "life": 12, "size": 1.3,
					"color": C_AMBER})
				_text(c.pos + Vector2(0, -_top(c) + 2), "BEDROCK!", C_AMBER, 9, 40.0)
				_slam_debris(c.pos, false)
				shake_out = maxf(shake_out, 2.0)
		"land_hard":
			for i in 3:
				_dust(p + Vector2(randf_range(-6, 6), randf_range(-2, 2)), Vector2(randf_range(-0.3, 0.3), -0.4))


## A floating call-out (Combo Trials and drills: "CLEAR!", "DODGED!").
func callout(pos: Vector2, text: String, color: Color) -> void:
	_text(pos, text, color, 9, 60.0)


## A click marker for League-style orders: green for a move, red for an attack.
func ping(pos: Vector2, attack: bool) -> void:
	_add({"kind": "ping", "pos": pos, "life": 18, "attack": attack, "real": true})


# ------------------------------------------------------------------ per frame

func advance() -> void:
	_tick += 1
	var ts := time_scale
	if sim != null:
		_watch_all()
		if ts > 0.0:
			_projectile_spray()
	_parts.append_array(_incoming)
	_incoming.clear()

	var keep: Array[Dictionary] = []
	var ends: Array[Callable] = []
	for p in _parts:
		var dt: float = 1.0 if bool(p.get("real", false)) else ts
		if dt <= 0.0:
			keep.append(p)
			continue
		p["t"] = float(p["t"]) + dt
		if p.has("vz"):
			_physics(p, dt)
		elif String(p["kind"]) == "px":
			p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * dt
			p["vel"] = Vector2(p["vel"]) + Vector2(0, 0.12 * dt)
		elif String(p["kind"]) == "emit":
			p["acc"] = float(p["acc"]) + dt
			while float(p["acc"]) >= float(p["every"]):
				p["acc"] = float(p["acc"]) - float(p["every"])
				var fn: Callable = p["fn"]
				fn.call(float(p["t"]) / float(p["life"]))
		if float(p["t"]) < float(p["life"]):
			keep.append(p)
		elif p.has("on_end"):
			ends.append(p["on_end"])
	_parts = keep
	for fn in ends:
		fn.call()
	_parts.append_array(_incoming)
	_incoming.clear()

	_dark = maxf(0.0, _dark - 0.01 * ts)
	_rain = maxf(0.0, _rain - ts)
	if _rain > 0.0:
		_dark = maxf(_dark, 0.35 * minf(1.0, _rain / 30.0))
	queue_redraw()
	if ground != null:
		ground.queue_redraw()


## Debris and water: a position on the floor plus a height `z` above it.
func _physics(p: Dictionary, dt: float) -> void:
	var vel: Vector2 = p["vel"]
	var z := float(p["z"]) + float(p["vz"]) * dt
	var vz := float(p["vz"]) - float(p.get("g", GRAVITY)) * dt
	var pos: Vector2 = p["pos"] + vel * dt
	if bool(p.get("walls", false)):
		var fr := SimDefs.floor_rect().grow(-4.0)
		if pos.x < fr.position.x or pos.x > fr.end.x:
			vel.x = -vel.x * 0.5
			pos.x = clampf(pos.x, fr.position.x, fr.end.x)
		if pos.y < fr.position.y or pos.y > fr.end.y:
			vel.y = -vel.y * 0.5
			pos.y = clampf(pos.y, fr.position.y, fr.end.y)
	var grounded := false
	if z <= 0.0 and vz < 0.0:
		z = 0.0
		match String(p["kind"]):
			"drop":
				p["t"] = p["life"]
				if bool(p.get("pool", false)) and randf() < 0.3:
					_add({"kind": "puddle", "pos": pos, "radius": randf_range(1.5, 3.5), "ry": 0.45,
						"grow": 3.0, "life": 90.0, "fade": 40.0})
			_:
				if -vz > 0.9:
					vz = -vz * float(p.get("bounce", 0.35))
					vel *= 0.65
					p["vrot"] = float(p.get("vrot", 0.0)) * 0.6
					if float(p.get("size", 0.0)) >= 3.0 or p.has("piece"):
						_dust(pos, Vector2(randf_range(-0.2, 0.2), -0.3))
				else:
					vz = 0.0
					grounded = true
	elif z <= 0.0:
		grounded = true
	if grounded:
		vel *= pow(0.9, dt)
		if bool(p.get("roll", false)):
			var rot := float(p["rot"]) + vel.x * dt / float(p.get("radius", 5.0))
			if vel.length() < 0.35:
				# Rock back and forth, then settle on a flat side.
				var rest := roundf(rot / (PI * 0.5)) * PI * 0.5
				var vr := (float(p.get("vrot", 0.0)) + (rest - rot) * 0.12 * dt) * pow(0.86, dt)
				p["vrot"] = vr
				rot += vr * dt
			p["rot"] = rot
		elif p.has("rot"):
			var rot := float(p["rot"])
			p["rot"] = lerp_angle(rot, roundf(rot / PI) * PI, minf(1.0, 0.25 * dt))
		if vel.length() < 0.03:
			vel = Vector2.ZERO
	elif p.has("rot"):
		p["rot"] = float(p["rot"]) + float(p.get("vrot", 0.0)) * dt
	p["z"] = z
	p["vz"] = vz
	p["vel"] = vel
	p["pos"] = pos
	p["grounded"] = grounded


# ------------------------------------------------------------------ watching creatures

func _watch_all() -> void:
	for c in sim.creatures:
		var w: Dictionary = _watch.get(c.id, {})
		if not w.is_empty() and w.get("obj") != c:
			w = {}  # a different creature in this slot (Duel tag): start fresh
		if w.is_empty():
			w = {"serial": c.attack_serial, "seg": -1, "charging": false, "stack": c.stack,
				"state": c.state, "anim_t": c.anim_t, "obj": c}
			_watch[c.id] = w
		var ticked := c.anim_t != int(w["anim_t"])
		var attacking := c.state == CreatureSim.State.ATTACK
		var mv := c.move_def() if attacking else {}
		var fx: Dictionary = mv.get("fx", {})

		if attacking and c.attack_serial != int(w["serial"]):
			w["seg"] = -1
			_move_started(c, mv, fx)
		w["serial"] = c.attack_serial

		var charging := attacking and c.charging
		if charging and ticked:
			_charging(c, mv, fx)
		elif bool(w["charging"]) and not charging and attacking:
			_charge_released(c, mv, fx)
		w["charging"] = charging

		var seg := c.active_seg()
		if seg >= 0 and seg != int(w["seg"]):
			_strike(c, mv, fx, seg)
		w["seg"] = seg if attacking else -1

		if attacking and ticked and not c.charging:
			_during_move(c, mv, fx)
		if c.state == CreatureSim.State.DODGE and ticked and c.state_t % 4 == 1:
			_ghost(c, Color(0.75, 0.85, 1.0, 0.4), 10.0)
		if c.state == CreatureSim.State.AIRBORNE and ticked and c.air_t < c.air_total / 2 and c.anim_t % 2 == 0:
			_launch_streak(c)
		if c.stack != int(w["stack"]):
			_stack_changed(c, int(w["stack"]), attacking)
		w["stack"] = c.stack

		# Stoneskin glints now and then (the rim itself is CreatureView's shader).
		if c.shield > 0.0 and ticked and c.anim_t % 26 == 0 and c.state != CreatureSim.State.KO:
			var at := c.pos + Vector2(randf_range(-c.radius, c.radius), -randf_range(8.0, _top(c) - 8.0))
			_add({"kind": "glint", "pos": at, "life": 10, "color": C_GREY[3]})
		if c.state == CreatureSim.State.KO and int(w["state"]) != CreatureSim.State.KO:
			_ko(c)
		w["state"] = c.state
		w["anim_t"] = c.anim_t


func _move_started(c: CreatureSim, mv: Dictionary, fx: Dictionary) -> void:
	if String(mv.get("type", "")) == "surge":
		_dark = maxf(_dark, 0.6)
	if bool(fx.get("rain", false)):
		_rain = 130.0


func _charging(c: CreatureSim, mv: Dictionary, fx: Dictionary) -> void:
	var full := c.is_full_charge()
	match String(fx.get("charge", "")):
		"drips":
			if c.anim_t % (2 if full else 4) == 0:
				var at := c.pos + Vector2(randf_range(-11, 11), randf_range(-2, 2))
				_drop(at, randf_range(12, 20), Vector2.ZERO, 0.0, false)
			if c.anim_t % (8 if full else 14) == 0:
				_add({"kind": "ripple", "pos": c.pos + Vector2(0, 1), "life": 22, "radius": 22.0 if full else 16.0})
		"pebbles":
			if full and c.anim_t % 6 == 0:
				_dust(c.pos + Vector2(randf_range(-10, 10), randf_range(-2, 2)), Vector2(0, -0.4))


func _charge_released(c: CreatureSim, mv: Dictionary, fx: Dictionary) -> void:
	match String(fx.get("charge", "")):
		"pebbles":
			for pb in _pebbles(c, c.charge):
				var at: Vector2 = pb["ground"]
				var out := (at - c.pos).normalized()
				_chunk(at, float(pb["z"]), out * 0.8 + c.facing * 1.8, randf_range(0.8, 1.6), 2.0, C_PEBBLE[1], 30.0)
		"drips":
			for i in 8:
				_drop(c.pos, 14.0, Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.2), randf_range(1.0, 2.0), true)


func _strike(c: CreatureSim, mv: Dictionary, fx: Dictionary, seg: int) -> void:
	var segs: Array = mv.get("_segs", [])
	var last := seg == segs.size() - 1
	var size := float(fx.get("size", 1.0))
	match String(fx.get("smear", "")):
		"thrust":
			_smear_thrust(c, seg, size, 0.0)
		"arc":
			_smear_arc(c, seg, size)
		"rise":
			_smear_rise(c, seg, size)
		"flurry":
			if last:
				_smear_rise(c, seg, size * 1.3)
			else:
				_smear_thrust(c, seg, size, randf_range(-6.0, 6.0))
	if last:
		match String(fx.get("impact", "")):
			"spire":
				_spire(c.hit_center(seg), c.facing)
			"geysers":
				_geysers(c, mv)
			"lash":
				_lash_impact(c, seg)
			"quake":
				_quake(c, mv)
			"avalanche":
				_avalanche(c.hit_center(seg))


func _during_move(c: CreatureSim, mv: Dictionary, fx: Dictionary) -> void:
	var t := c.state_t
	if fx.has("afterimage"):
		var win: Array = fx["afterimage"]
		if t >= int(win[0]) and t <= int(win[1]):
			if t % 3 == 0:
				_ghost(c, Color(String(fx.get("ghost_color", "#ffffff"))), 14.0)
			if String(fx.get("trail", "")) == "gravel" and not c.connected:
				var back := c.pos - c.facing * 7.0 + Vector2(randf_range(-4, 4), randf_range(-2, 2))
				_chunk(back, 1.0, -c.facing * randf_range(0.2, 0.8) + Vector2(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3)),
					randf_range(0.6, 1.5), randf_range(1.0, 2.0), C_PEBBLE[randi() % 2], 26.0)
				if t % 4 == 0:
					_dust(back, Vector2(-c.facing.x * 0.3, -0.3))
	if bool(fx.get("suction", false)) and t <= int(mv.get("startup", 0)) + int(mv.get("active", 0)):
		var mouth := c.pos + c.facing * 12.0 + Vector2(0, -_chest(c))
		for i in 2:
			var from := mouth + c.facing.rotated(randf_range(-1.0, 1.0)) * randf_range(16, 30) + Vector2(0, randf_range(-6, 6))
			_add({"kind": "suck", "from": from, "to": mouth, "life": 8})


# ------------------------------------------------------------------ smears

func _chest(c: CreatureSim) -> float:
	return float(c.def.get("fx_height", 16))


func _top(c: CreatureSim) -> float:
	return float(c.def.get("fx_top", 32))


## A tapered streak behind the fist: thin at the shoulder, wide at the point of impact.
func _smear_thrust(c: CreatureSim, seg: int, size: float, dz: float) -> void:
	var f := _swing_dir(c)
	var up := Vector2(0, -_chest(c) - c.air_height() + dz)
	var start := c.pos + f * 4.0 + up
	var end := c.pos + f * (c.seg_value(seg, "reach") + c.hit_radius(seg) * 0.5) + up
	var n := f.orthogonal()
	var w := 2.5 * size
	_add({"kind": "smear", "life": 6, "color": Color(1, 1, 1, 0.9),
		"pts": PackedVector2Array([start, end + n * w, end + f * 3.0 * size, end - n * w])})
	for side in [-1.0, 1.0]:
		var o: Vector2 = n * (w + 2.0) * side
		_add({"kind": "streak", "a": start + f * 6.0 + o, "b": end - f * 2.0 + o, "life": 5,
			"color": Color(1, 1, 1, 0.55)})


## A hook: a crescent sweeping around the front of the body.
func _smear_arc(c: CreatureSim, seg: int, size: float) -> void:
	var center := c.pos + Vector2(0, -_chest(c) - c.air_height())
	var r := c.seg_value(seg, "reach") + 3.0 * size
	var f := _swing_dir(c)
	var a0 := f.angle()
	var sweep := -1.0 if f.x < 0.0 else 1.0
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var k := float(i) / steps
		var a := a0 + sweep * lerpf(-1.9, 0.6, k)
		var dir := Vector2(cos(a), sin(a) * 0.55)
		outer.append(center + dir * r)
		inner.append(center + dir * (r - lerpf(0.5, 5.0, k * k) * size))
	inner.reverse()
	outer.append_array(inner)
	_add({"kind": "smear", "life": 7, "color": Color(1, 1, 1, 0.85), "pts": outer})


## An uppercut: a vertical crescent rising in front of the body.
func _smear_rise(c: CreatureSim, seg: int, size: float) -> void:
	var side := -1.0 if c.facing.x < -0.1 else (1.0 if c.facing.x > 0.1 else (-1.0 if _flip(c) else 1.0))
	var r := 15.0 * size
	var center := c.pos + c.facing * c.seg_value(seg, "reach") * 0.4 + Vector2(-side * 4.0, -_chest(c) - c.air_height() - 4.0)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var k := float(i) / steps
		var a := lerpf(0.9, -1.7, k)  # from low in front, up and over the top
		var dir := Vector2(cos(a) * side, sin(a))
		outer.append(center + dir * r)
		inner.append(center + dir * (r - lerpf(0.5, 6.0, k) * size))
	inner.reverse()
	outer.append_array(inner)
	_add({"kind": "smear", "life": 8, "color": Color(1, 0.97, 0.88, 0.9), "pts": outer})


## Where a swing is drawn. Fighters with up/down art swing exactly where the hit goes;
## side-only art can't show a punch straight up or down, so it's drawn angled toward the
## side the sprite faces.
func _swing_dir(c: CreatureSim) -> Vector2:
	var f := c.facing
	if c.id < views.size() and views[c.id] != null and (views[c.id] as CreatureView).has_vertical_views():
		return f  # it has up/down art, so the swing goes where the hit goes
	if absf(f.x) < 0.1:
		return Vector2(-1.0 if _flip(c) else 1.0, f.y * 0.8).normalized()
	return f


func _flip(c: CreatureSim) -> bool:
	if c.id < views.size() and views[c.id] != null:
		return bool((views[c.id] as CreatureView).flip)
	return c.facing.x < 0.0


# ------------------------------------------------------------------ move effects

func _ghost(c: CreatureSim, tint: Color, life: float) -> void:
	if c.id >= views.size() or views[c.id] == null:
		return
	var v: CreatureView = views[c.id]
	if v.ko_hidden:
		return
	var snap := v.snapshot()
	snap["kind"] = "ghost"
	snap["life"] = life
	snap["tint"] = tint
	_add(snap)


func _launch_streak(c: CreatureSim) -> void:
	var body := c.pos + Vector2(randf_range(-7, 7), -c.air_height() - randf_range(0, 6))
	_add({"kind": "streak", "a": body + Vector2(0, 6), "b": body + Vector2(0, 16), "life": 6,
		"color": Color(1, 1, 1, 0.6)})


func _slam_debris(p: Vector2, full: bool) -> void:
	for i in (10 if full else 5):
		var v := Vector2.from_angle(randf() * TAU) * randf_range(0.5, 1.8)
		_chunk(p + v * 3.0, 2.0, v, randf_range(1.6, 3.4), randf_range(2.0, 3.5), C_CON[randi() % 3], 55.0)
	# Cracks that run outward from the impact.
	var lines: Array = []
	for i in (7 if full else 4):
		var a := TAU * i / (7 if full else 4) + randf_range(-0.3, 0.3)
		var pts := PackedVector2Array([p])
		var cur := p
		for j in 4:
			a += randf_range(-0.5, 0.5)
			cur += Vector2(cos(a), sin(a) * 0.6) * randf_range(4.0, 8.0 if full else 5.0)
			pts.append(cur)
		lines.append(pts)
	_add({"kind": "decal", "lines": lines, "life": 80, "grow": 8.0, "fade": 30.0})
	shake_out = maxf(shake_out, 1.0)


func _spire(at: Vector2, facing: Vector2) -> void:
	_add({"kind": "spire", "pos": at, "life": 34, "h": 30.0, "w": 8.0, "front": true})
	_add({"kind": "spire", "pos": at - facing * 9.0 + Vector2(0, 2), "life": 30, "h": 18.0, "w": 6.0, "delay": 2.0})
	_add({"kind": "spire", "pos": at + facing.orthogonal() * 8.0, "life": 28, "h": 14.0, "w": 5.0, "delay": 3.0})
	for i in 8:
		_chunk(at, 4.0, Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.4), randf_range(1.8, 3.2),
			randf_range(2.0, 3.0), C_STONE[randi() % 3], 45.0)
	for i in 5:
		_dust(at + Vector2(randf_range(-8, 8), randf_range(-2, 2)), Vector2(randf_range(-0.4, 0.4), -0.6))
	_later(30.0, _spire_crumble.bind(at))
	shake_out = maxf(shake_out, 3.0)
	cue.emit("spire")


func _spire_crumble(at: Vector2) -> void:
	for i in 6:
		_chunk(at + Vector2(randf_range(-4, 4), 0), randf_range(6, 20), Vector2.from_angle(randf() * TAU) * 0.6,
			0.5, randf_range(2.0, 3.0), C_STONE[randi() % 3], 30.0)


## Boulder Lash: the head cracks into the target and chips fly off the tip.
func _lash_impact(c: CreatureSim, seg: int) -> void:
	var at := c.hit_center(seg) + c.facing * 6.0
	for i in 7:
		var v := c.facing.rotated(randf_range(-1.0, 1.0)) * randf_range(0.6, 1.8)
		_chunk(at, 22.0, v, randf_range(0.8, 2.0), randf_range(1.5, 2.5), C_GREY[randi() % 3], 40.0)
	_add({"kind": "ring", "pos": at, "life": 8, "radius": 10.0, "color": C_GREY[3]})
	_dust(at, Vector2(c.facing.x * 0.3, -0.4))
	cue.emit("lash")


## Rockslide Stomp: a shockwave rolls out from the stomping foot and the ground jumps.
func _quake(c: CreatureSim, mv: Dictionary) -> void:
	var r := float(mv.get("hit_radius", 24))
	var full := c.charge_ratio >= 1.0
	_add({"kind": "ring", "pos": c.pos, "life": 16, "radius": r + 6.0, "color": C_CRAG[2]})
	_add({"kind": "ring", "pos": c.pos, "life": 22, "radius": r + 18.0})
	for i in 12:
		var a := TAU * i / 12.0 + randf() * 0.3
		var at := c.pos + Vector2(cos(a), sin(a) * 0.5) * (r - 4.0 + randf() * 6.0)
		_dust(at, Vector2(cos(a), sin(a) * 0.5 - 0.7) * 0.6)
		if i % 2 == 0:
			_chunk(at, 1.0, Vector2(cos(a), sin(a) * 0.5) * randf_range(0.3, 0.9), randf_range(1.6, 2.8),
				randf_range(2.0, 3.0), C_CRAG[randi() % 3] if i % 4 == 0 else C_GREY[randi() % 3], 45.0)
	_slam_debris(c.pos + c.facing * 6.0, full)
	shake_out = maxf(shake_out, 3.5 if full else 2.5)


## Avalanche Coil: boulders shaken loose by the crash rain down around it.
func _avalanche(at: Vector2) -> void:
	_add({"kind": "lines", "pos": at + Vector2(0, -10), "life": 12, "size": 2.0, "color": C_AMBER})
	for i in 14:
		var spot := at + Vector2(randf_range(-30, 30), randf_range(-12, 12))
		_chunk(spot, randf_range(40, 90), Vector2(randf_range(-0.2, 0.2), 0), -randf_range(0.5, 1.5),
			randf_range(2.5, 4.5), C_GREY[randi() % 3] if i % 3 else C_CRAG[randi() % 3], 70.0, true)
	for i in 10:
		var a := TAU * i / 10.0
		_dust(at + Vector2(cos(a) * 20.0, sin(a) * 8.0), Vector2(cos(a), sin(a) * 0.5 - 0.6) * 0.7)
	shake_out = maxf(shake_out, 6.0)
	cue.emit("avalanche")


## Storm Drain: water erupts from the ring of pits it leaves behind.
func _geysers(c: CreatureSim, mv: Dictionary) -> void:
	var ring: Dictionary = mv.get("terrain_ring", {"inner": 24, "outer": 40})
	var r := (float(ring["inner"]) + float(ring["outer"])) * 0.5
	var n := 8
	for i in n:
		var at := c.pos + Vector2.from_angle(TAU * i / n + 0.2) * r
		_later(randf_range(0.0, 6.0), _geyser_start.bind(at))
	shake_out = maxf(shake_out, 4.0)
	cue.emit("geysers")


func _geyser_start(at: Vector2) -> void:
	_add({"kind": "ripple", "pos": at, "life": 24, "radius": 14.0})
	_add({"kind": "emit", "life": 22, "every": 1.0, "acc": 0.0, "fn": _geyser_tick.bind(at)})


func _geyser_tick(k: float, at: Vector2) -> void:
	for j in 2:
		var col := C_FOAM if randf() < 0.3 else (C_WATER_L if randf() < 0.5 else C_WATER)
		_drop(at + Vector2(randf_range(-3, 3), randf_range(-1, 1)), 1.0,
			Vector2(randf_range(-0.35, 0.35), randf_range(-0.2, 0.2)), randf_range(3.4, 5.0) * (1.0 - k * 0.5), true, col,
			Vector2(2, 3) if randf() < 0.6 else Vector2(1, 2))


func _projectile_spray() -> void:
	for pr in sim.projectiles:
		if not _is_wave(pr):
			continue
		var pos: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		for i in 2:
			_drop(pos + Vector2(randf_range(-4, 4), randf_range(-2, 2)), randf_range(4, 9),
				vel * 0.25 + Vector2(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3)), randf_range(0.6, 1.6), false)
		if _tick % 3 == 0:
			_add({"kind": "puddle", "pos": pos - vel * 2.0, "radius": randf_range(3.0, 5.0), "ry": 0.4,
				"grow": 4.0, "life": 80.0, "fade": 40.0})


func _is_wave(pr: Dictionary) -> bool:
	var owner := sim.creatures[int(pr["owner"])]
	for mid in owner.moves():
		var mv: Dictionary = owner.moves()[mid]
		if mv.has("projectile") and String(mv.get("fx", {}).get("projectile", "")) == "wave":
			return true
	return false


func _owner_near(p: Vector2) -> CreatureSim:
	var best: CreatureSim = null
	var bd := INF
	for c in sim.creatures:
		var d := c.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = c
	return best


func _pit_plume(p: Vector2) -> void:
	for i in 9:
		var v := Vector2(randf_range(-0.35, 0.35), randf_range(-1.6, -0.8))
		_add({"kind": "dust", "pos": p + Vector2(randf_range(-6, 6), randf_range(-2, 2)), "vel": v, "life": 24})
	_add({"kind": "ring", "pos": p, "life": 14, "radius": 22.0})
	shake_out = maxf(shake_out, 2.5)
	cue.emit("land")


# ------------------------------------------------------------------ windup tells

## A raw big move is winding up: a glint over the head for the length of the windup,
## a ring at the feet, and a "!" when it can't be blocked.
func _windup_tell(e: Dictionary) -> void:
	var who := int(e.get("who", -1))
	if who < 0 or who >= sim.creatures.size():
		return
	var c := sim.creatures[who]
	var frames := float(e["power"])
	var tell := String(e.get("tell", "strong"))
	var red := tell in ["unblockable", "guard_break"]
	var col := CreatureView.TELL_RED if red else CreatureView.TELL_GOLD
	var head := c.pos + Vector2(0, -_top(c) - 9.0)
	_add({"kind": "glint", "pos": head, "life": frames + 2.0, "color": col})
	_add({"kind": "ring", "pos": c.pos, "life": frames, "radius": 22.0, "color": col})
	if red:
		_text(head + Vector2(10, -2), "!", col, 12, frames + 10.0)
		_text(head + Vector2(0, -12), "UNBLOCKABLE" if tell == "unblockable" else "GUARD BREAK", col, 6,
			frames + 10.0)


# ------------------------------------------------------------------ Cairn's stones

## Where the stones hover above Cairn's head, as [floor position, height].
func _stack_slots(c: CreatureSim, count: int) -> Array:
	var out: Array = []
	var z := _top(c) + 7.0 + c.air_height()
	for i in count:
		var x := (i - (count - 1) * 0.5) * 7.0
		var bob := sin((c.anim_t + i * 9) * 0.12) * 1.5
		out.append([c.pos + Vector2(x, 0), z + bob])
	return out


func _stack_changed(c: CreatureSim, before: int, attacking: bool) -> void:
	if c.state == CreatureSim.State.KO:
		return
	var max_n := int(c.def.get("stack", {}).get("max", 3))
	if c.stack > before:
		var slot: Array = _stack_slots(c, c.stack)[c.stack - 1]
		var sp: Vector2 = slot[0] + Vector2(0, -float(slot[1]))
		for i in 4:
			_px(sp, Vector2.from_angle(randf() * TAU) * 0.9, C_SPARK[0], 8)
		return
	# Spent on a Haymaker or Rush: the stones fly into the punch. Timed out: they drop.
	var slots := _stack_slots(c, before)
	for i in before:
		var at: Vector2 = slots[i][0]
		var z := float(slots[i][1])
		var col: Color = C_STACK[i % max_n]
		if attacking:
			_chunk(at, z, c.facing * 3.2 + Vector2(0, randf_range(-0.3, 0.3)), -0.6, 3.0, col, 12.0)
		else:
			_chunk(at, z, Vector2(randf_range(-0.3, 0.3), 0), 0.5, 3.0, col, 40.0)
	if attacking:
		var c_at := c.pos + Vector2(0, -_top(c))
		_add({"kind": "lines", "pos": c_at, "life": 8, "size": 0.8, "color": C_STONE[2]})


# ------------------------------------------------------------------ knockouts

func _ko(c: CreatureSim) -> void:
	var ko: Dictionary = c.def.get("ko_fx", {})
	match String(ko.get("style", "")):
		"scatter":
			_later(0.5, _scatter.bind(c))
		"crack":
			var ends := _crack_body(c, ko)
			_later(0.5, _gush.bind(c, ko, ends))
			_later(20.0, _rubble.bind(c))
		"crumble":
			_crack_body(c, ko)
			_later(14.0, _crumble.bind(c))


## Craglash: the stone neck comes apart and its pieces bounce away, then the body
## settles into rubble.
func _crumble(c: CreatureSim) -> void:
	var dir: Vector2 = _last_push.get(c.id, -c.facing)
	for i in 7:
		var v := dir.rotated(randf_range(-1.1, 1.1)) * randf_range(0.6, 1.8)
		_chunk(c.pos, randf_range(20, 36), v, randf_range(1.0, 2.2), randf_range(3.0, 4.0), C_GREY[randi() % 3],
			FOREVER, true)
	for i in 6:
		_chunk(c.pos, randf_range(6, 18), Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.2),
			randf_range(0.8, 1.8), randf_range(2.0, 3.0), C_CRAG[randi() % 3], FOREVER, true)
	for i in 8:
		_dust(c.pos + Vector2(randf_range(-14, 14), randf_range(-3, 3)), Vector2(randf_range(-0.5, 0.5), -0.4))
	_add({"kind": "ring", "pos": c.pos, "life": 16, "radius": 32.0})
	shake_out = maxf(shake_out, 3.0)
	cue.emit("stones_scatter")


## Cairn falls apart: each stone of the stack becomes its own piece and tumbles away
## from the final hit. The head rolls the farthest and wobbles to a stop.
func _scatter(c: CreatureSim) -> void:
	if c.id >= views.size() or views[c.id] == null:
		return
	var v: CreatureView = views[c.id]
	var snap := v.snapshot()
	v.ko_hidden = true
	var ko: Dictionary = c.def["ko_fx"]
	var frame: Array = ko.get("frame", [0, 0])
	var fpx := int(snap["frame_px"])
	var origin: Vector2 = snap["side_origin"]
	var flip := bool(snap["flip"])
	var dir: Vector2 = _last_push.get(c.id, -c.facing)
	var pieces: Array = ko["pieces"]
	for i in pieces.size():
		var y0 := int(pieces[i][0])
		var y1 := int(pieces[i][1])
		var zc := origin.y - (y0 + y1) * 0.5
		var head := i == 0
		var spread := dir.rotated(randf_range(-0.8, 0.8))
		var speed := randf_range(0.7, 1.6) + (1.3 if head else 0.0)
		_add({"kind": "chunk", "piece": true, "tex": snap["side_tex"], "flip": flip,
			"region": Rect2(int(frame[1]) * fpx, int(frame[0]) * fpx + y0, fpx, y1 - y0),
			"ox": origin.x, "band_c": (y0 + y1) * 0.5,
			"pos": c.pos + Vector2(randf_range(-2, 2), randf_range(-1, 1)), "z": zc,
			"vel": spread * speed, "vz": randf_range(1.0, 2.2) + zc * 0.025,
			"rot": 0.0, "vrot": randf_range(-0.25, 0.25), "bounce": 0.4,
			"roll": head, "radius": 6.0, "walls": true, "life": FOREVER,
			"x_eyes": ko.get("x_eyes", []) if head else []})
	for i in 5:
		_chunk(c.pos, randf_range(10, 22), Vector2.from_angle(randf() * TAU) * randf_range(0.5, 1.5),
			randf_range(1.0, 2.0), 2.0, C_PEBBLE[randi() % 2], FOREVER, true)
	for i in 6:
		_dust(c.pos + Vector2(randf_range(-10, 10), randf_range(-3, 3)), Vector2(randf_range(-0.5, 0.5), -0.4))
	_add({"kind": "ring", "pos": c.pos, "life": 16, "radius": 30.0})
	shake_out = maxf(shake_out, 3.0)
	cue.emit("stones_scatter")


## Culvert's concrete cracks under the final blow. Returns the crack ends, where water
## will burst out, relative to the feet.
func _crack_body(c: CreatureSim, ko: Dictionary) -> Array:
	var body := Vector2(0, -float(ko.get("body_z", 12)))
	var rx := float(ko.get("body_rx", 13))
	var ry := float(ko.get("body_ry", 9))
	var lines: Array = []
	var ends: Array = []
	var n := int(ko.get("cracks", 5))
	for i in n:
		var a := TAU * i / n + randf_range(-0.3, 0.3)
		var cur := body + Vector2(randf_range(-2, 2), randf_range(-1, 1))
		var pts := PackedVector2Array([cur])
		for j in 3:
			a += randf_range(-0.6, 0.6)
			var nxt := cur + Vector2(cos(a), sin(a) * 0.8) * randf_range(3.0, 5.0)
			var rel := nxt - body
			if (rel.x * rel.x) / (rx * rx) + (rel.y * rel.y) / (ry * ry) > 1.0:
				break
			cur = nxt
			pts.append(cur)
		lines.append(pts)
		ends.append(cur)
	_add({"kind": "bodycrack", "id": c.id, "lines": lines, "life": 46, "grow": 14.0, "fade": 28.0, "real": true})
	cue.emit("crack")
	return ends


func _gush(c: CreatureSim, ko: Dictionary, ends: Array) -> void:
	var body_z := float(ko.get("body_z", 12))
	for i in 16:
		var e: Vector2 = ends[randi() % ends.size()]
		var d := (e + Vector2(0, body_z)).normalized()
		_drop(c.pos + Vector2(e.x, 0), -e.y, Vector2(d.x, d.y * 0.5) * randf_range(1.0, 2.2), randf_range(1.2, 2.6), true,
			Color(0, 0, 0, 0), Vector2(2, 2))
	_add({"kind": "puddle", "pos": c.pos + Vector2(0, 2), "radius": float(ko.get("puddle", 30)), "ry": 0.32,
		"grow": 100.0, "life": FOREVER})
	_add({"kind": "emit", "life": 80, "every": 1.0, "acc": 0.0, "fn": _gush_tick.bind(c, ends, body_z)})
	shake_out = maxf(shake_out, 2.5)
	cue.emit("water_gush")


## Water keeps pouring out of the cracks, weaker over time, lower as the body slumps.
func _gush_tick(k: float, c: CreatureSim, ends: Array, body_z: float) -> void:
	var sink := clampf(1.0 - c.state_t / 22.0, 0.4, 1.0)
	for j in 2:
		var e: Vector2 = ends[randi() % ends.size()]
		var d := (e + Vector2(0, body_z)).normalized()
		_drop(c.pos + Vector2(e.x * sink, randf_range(-1, 1)), maxf(2.0, -e.y * sink),
			Vector2(d.x, d.y * 0.5) * randf_range(0.4, 1.4), randf_range(0.5, 2.0) * (1.0 - k * 0.7), true)


func _rubble(c: CreatureSim) -> void:
	for i in 8:
		var v := Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5))
		_chunk(c.pos + Vector2(randf_range(-8, 8), randf_range(-2, 2)), randf_range(4, 12), v, randf_range(0.8, 1.8),
			randf_range(2.0, 4.0), C_CON[randi() % 3], FOREVER, true)
	for i in 5:
		_dust(c.pos + Vector2(randf_range(-12, 12), randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.4))


# ------------------------------------------------------------------ helpers

func _creature(i: int) -> CreatureSim:
	return sim.creatures[i] if i >= 0 and i < sim.creatures.size() else null


func _note_push(e: Dictionary) -> Vector2:
	var a := int(e.get("attacker", -1))
	var d := int(e.get("target", -1))
	if a < 0 or d < 0 or a >= sim.creatures.size() or d >= sim.creatures.size():
		return Vector2.RIGHT
	var push := sim.creatures[d].pos - sim.creatures[a].pos
	push = push.normalized() if push.length_squared() > 0.001 else sim.creatures[a].facing
	_last_push[d] = push
	return push


func _add(p: Dictionary) -> void:
	p["t"] = 0.0
	_incoming.append(p)


func _later(delay: float, fn: Callable) -> void:
	_add({"kind": "later", "life": maxf(0.01, delay), "on_end": fn})


func _dust(pos: Vector2, vel: Vector2) -> void:
	_add({"kind": "dust", "pos": pos, "vel": vel, "life": 16})


func _px(pos: Vector2, vel: Vector2, col: Color, life: float) -> void:
	_add({"kind": "px", "pos": pos, "vel": vel, "color": col, "life": life})


func _chunk(pos: Vector2, z: float, vel: Vector2, vz: float, size: float, col: Color, life: float,
		walls := false) -> void:
	_add({"kind": "chunk", "pos": pos, "z": z, "vel": vel, "vz": vz, "size": size, "color": col,
		"life": life, "rot": randf() * TAU, "vrot": randf_range(-0.4, 0.4), "bounce": 0.35, "walls": walls})


func _drop(pos: Vector2, z: float, vel: Vector2, vz: float, pool: bool, col := Color(0, 0, 0, 0),
		size := Vector2(1, 2)) -> void:
	if col.a == 0.0:
		col = C_WATER if randf() < 0.6 else C_WATER_L
	_add({"kind": "drop", "pos": pos, "z": z, "vel": vel, "vz": vz, "color": col, "life": 120.0, "pool": pool,
		"dsize": size})


func _text(pos: Vector2, text: String, color: Color, size := 8, life := 40.0) -> void:
	_add({"kind": "text", "pos": pos, "text": text, "color": color, "size": size, "life": life})


## Orbiting pebbles while Haymaker charges: more of them, higher, the longer it's held.
func _pebbles(c: CreatureSim, charge: int) -> Array:
	var cmax := float(c.move_def().get("charge_max", 30))
	var k := clampf(charge / cmax, 0.0, 1.0)
	var n := 1 + int(k * 4.0)
	var out: Array = []
	for i in n:
		var a := c.anim_t * 0.16 + TAU * i / n
		var z := 4.0 + 16.0 * k + sin(a * 1.7 + i) * 1.5
		var g := c.pos + Vector2(cos(a) * 15.0, sin(a) * 5.0)
		out.append({"ground": g, "z": z, "front": sin(a) > 0.0, "full": k >= 1.0})
	return out


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	_paint(self, false)


func _paint(ci: CanvasItem, floor_layer: bool) -> void:
	if floor_layer:
		if _dark > 0.0:
			ci.draw_rect(Rect2(-40, -40, SimDefs.VIEW_W + 80, SimDefs.VIEW_H + 80), Color(C_DIM, _dark))
		for p in _parts:  # flat things first, so debris sits on top of puddles and cracks
			if String(p["kind"]) in ["puddle", "decal", "ripple"]:
				_draw_part(ci, p)
		for p in _parts:
			var kind := String(p["kind"])
			if kind == "ghost" or (kind == "spire" and not bool(p.get("front", false))):
				_draw_part(ci, p)
			elif p.has("vz") and float(p["z"]) > 1.0:
				_draw_shadow(ci, p)
			elif kind == "chunk" and bool(p.get("grounded", false)):
				_draw_part(ci, p)
		if sim != null:
			_draw_creature_extras(ci, true)
		return

	if sim != null:
		_draw_projectiles(ci)
	for p in _parts:
		var kind := String(p["kind"])
		if kind in ["puddle", "decal", "ripple", "ghost", "later", "emit"]:
			continue
		if kind == "spire" and not bool(p.get("front", false)):
			continue
		if kind == "chunk" and bool(p.get("grounded", false)):
			continue
		_draw_part(ci, p)
	if sim != null:
		_draw_creature_extras(ci, false)
	if _rain > 0.0:
		_draw_rain(ci)


func _alpha(p: Dictionary) -> float:
	var life := float(p["life"])
	var t := float(p["t"])
	if p.has("fade"):
		return clampf((life - t) / float(p["fade"]), 0.0, 1.0)
	return 1.0


func _draw_part(ci: CanvasItem, p: Dictionary) -> void:
	var t := float(p["t"])
	var life := float(p["life"])
	var k := clampf(t / life, 0.0, 1.0)
	match String(p["kind"]):
		"spark":
			var pos: Vector2 = p["pos"]
			var s: float = p["scale"]
			var frame := mini(int(k * 4.0), 3)
			var size := Vector2(16, 16) * s
			ci.draw_texture_rect_region(SHEET, Rect2((pos - size * 0.5).round(), size), Rect2(frame * 16, 0, 16, 16))
		"dust":
			var pos: Vector2 = p["pos"]
			var v: Vector2 = p["vel"]
			var frame := mini(int(k * 4.0), 3)
			ci.draw_texture_rect_region(SHEET, Rect2((pos + v * t - Vector2(8, 12)).round(), Vector2(16, 16)), Rect2(frame * 16, 16, 16, 16))
		"ping":
			var pos: Vector2 = p["pos"]
			var col := Color("ff5a5a") if bool(p["attack"]) else Color("7cf27c")
			col.a = 1.0 - k
			var r := lerpf(9.0, 3.0, k)
			ci.draw_set_transform(pos, 0.0, Vector2(1.0, 0.5))
			ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, col, 1.5)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for ang in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
				var dir := Vector2.from_angle(ang) * Vector2(1.0, 0.5)
				ci.draw_line(pos + dir * (r + 4.0), pos + dir * (r + 1.0), col, 1.0)
		"ring":
			var pos: Vector2 = p["pos"]
			var r := lerpf(4.0, float(p["radius"]), sqrt(k))
			var col: Color = p.get("color", Color(1.0, 0.92, 0.7))
			col.a = 1.0 - k
			ci.draw_set_transform(pos, 0.0, Vector2(1.0, 0.5))
			ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, 2.0)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"ripple":
			var pos: Vector2 = p["pos"]
			var r := lerpf(3.0, float(p["radius"]), sqrt(k))
			ci.draw_set_transform(pos, 0.0, Vector2(1.0, 0.4))
			ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(C_WATER_L, 0.8 * (1.0 - k)), 1.5)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"text":
			var pos: Vector2 = p["pos"]
			var col: Color = p["color"]
			col.a = 1.0 - maxf(0.0, k - 0.6) / 0.4
			var at := pos + Vector2(-40, -t * 0.5)
			var fs: int = p["size"]
			ci.draw_string_outline(_font, at, String(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, 3, Color(0.1, 0.08, 0.1, col.a))
			ci.draw_string(_font, at, String(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, col)
		"glint":
			# A four-point star that flares and shrinks over the windup.
			var pos: Vector2 = Vector2(p["pos"]).round()
			var col: Color = p["color"]
			var r := 3.0 + 7.0 * sin(clampf(k * 1.4, 0.0, 1.0) * PI)
			var w := 1.5
			ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(w, -w),
				pos + Vector2(r, 0), pos + Vector2(w, w), pos + Vector2(0, r), pos + Vector2(-w, w),
				pos + Vector2(-r, 0), pos + Vector2(-w, -w)]), col)
			ci.draw_rect(Rect2(pos - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)
		"px":
			var col: Color = p["color"]
			col.a = 1.0 - k
			var pos: Vector2 = p["pos"]
			ci.draw_rect(Rect2(pos.round(), Vector2.ONE * (2.0 if k < 0.4 else 1.0)), col)
		"streak":
			var col: Color = p["color"]
			col.a *= 1.0 - k
			ci.draw_line(p["a"], p["b"], col, 1.0)
		"suck":
			var a: Vector2 = p["from"]
			var b: Vector2 = p["to"]
			ci.draw_line(a.lerp(b, k), a.lerp(b, minf(1.0, k + 0.35)), Color(1, 1, 1, 0.7 * (1.0 - k * 0.5)), 1.0)
		"smear":
			var col: Color = p["color"]
			col.a *= pow(1.0 - k, 0.7)
			ci.draw_colored_polygon(p["pts"], col)
		"lines":
			var pos: Vector2 = p["pos"]
			var size := float(p["size"])
			var col: Color = p["color"]
			col.a = 1.0 - k
			for i in 8:
				var dir := Vector2.from_angle(TAU * i / 8.0 + 0.2)
				ci.draw_line(pos + dir * lerpf(5.0, 12.0, k) * size, pos + dir * lerpf(10.0, 20.0, k) * size, col, 1.0)
		"ghost":
			var tint: Color = p["tint"]
			tint.a *= 1.0 - k
			var feet: Vector2 = p["feet"]
			var origin: Vector2 = p["origin"]
			var size: Vector2 = p["frame_size"]
			ci.draw_set_transform(feet, 0.0, Vector2(-1.0 if bool(p["flip"]) else 1.0, 1.0))
			ci.draw_texture_rect_region(p["tex"], Rect2(-origin.x, -origin.y, size.x, size.y), p["region"], tint)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"chunk":
			_draw_chunk(ci, p)
		"drop":
			var col: Color = p["color"]
			var at := (Vector2(p["pos"]) + Vector2(0, -float(p["z"]))).round()
			ci.draw_rect(Rect2(at, p.get("dsize", Vector2(1, 2))), col)
		"puddle":
			var pos: Vector2 = p["pos"]
			var grow := clampf(t / float(p.get("grow", 1.0)), 0.0, 1.0)
			var r := float(p["radius"]) * (1.0 - pow(1.0 - grow, 2.0))
			if r < 0.5:
				return
			var a := 0.55 * _alpha(p)
			var ry := float(p["ry"])
			ci.draw_set_transform(pos, 0.0, Vector2(1.0, ry))
			ci.draw_circle(Vector2.ZERO, r, Color(C_WATER, a))
			if r > 6.0:
				ci.draw_arc(Vector2.ZERO, r * 0.7, PI * 1.1, PI * 1.5, 8, Color(C_WATER_L, a), 1.0 / ry)
				var gl := Vector2.from_angle(_tick * 0.03) * r * 0.5
				ci.draw_circle(gl, 1.0, Color(C_FOAM, a))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"decal":
			var grow := clampf(t / float(p["grow"]), 0.0, 1.0)
			var col := Color(C_CRACK, 0.85 * _alpha(p))
			for pts in p["lines"]:
				_draw_partial_line(ci, pts, grow, col)
		"spire":
			_draw_spire(ci, p)
		"bodycrack":
			if int(p["id"]) >= sim.creatures.size():
				return
			var c := sim.creatures[int(p["id"])]
			var base := c.pos.round()
			var grow := clampf(t / float(p["grow"]), 0.0, 1.0)
			var a := clampf((life - t) / (life - float(p["fade"])), 0.0, 1.0)
			for pts in p["lines"]:
				var moved := PackedVector2Array()
				for q in pts:
					moved.append(base + Vector2(q))
				_draw_partial_line(ci, moved, grow, Color(C_CRACK, a))
				if grow >= 1.0:
					ci.draw_rect(Rect2(moved[moved.size() - 1].round(), Vector2.ONE), Color(C_WATER_L, a))


func _draw_partial_line(ci: CanvasItem, pts: PackedVector2Array, grow: float, col: Color) -> void:
	var n := pts.size() - 1
	if n < 1:
		return
	var upto := grow * n
	for i in n:
		if i >= upto:
			break
		var b := pts[i + 1] if i + 1 <= upto else pts[i].lerp(pts[i + 1], upto - i)
		ci.draw_line(pts[i], b, col, 1.0)


func _draw_chunk(ci: CanvasItem, p: Dictionary) -> void:
	var at := (Vector2(p["pos"]) + Vector2(0, -float(p["z"]))).round()
	var a := 1.0
	var life := float(p["life"])
	if life < FOREVER:
		a = clampf((life - float(p["t"])) / 12.0, 0.0, 1.0)
	if bool(p.get("piece", false)):
		var region: Rect2 = p["region"]
		var h := region.size.y
		var ox := float(p["ox"])
		ci.draw_set_transform(at, float(p["rot"]), Vector2(-1.0 if bool(p["flip"]) else 1.0, 1.0))
		ci.draw_texture_rect_region(p["tex"], Rect2(-ox, -h * 0.5, region.size.x, h), region)
		var eyes: Array = p.get("x_eyes", [])
		var vel: Vector2 = p["vel"]
		if not eyes.is_empty() and bool(p.get("grounded", false)) and vel.length() < 0.15 \
				and absf(float(p.get("vrot", 0.0))) < 0.02:
			var bc := float(p["band_c"])
			for e in eyes:
				var ex := float(e[0]) - ox
				var ey := float(e[1]) - bc
				ci.draw_rect(Rect2(ex - 1, ey - 1, 3, 3), C_HEAD)
				ci.draw_line(Vector2(ex - 1, ey - 1), Vector2(ex + 2, ey + 2), C_OUTLINE, 1.0)
				ci.draw_line(Vector2(ex - 1, ey + 2), Vector2(ex + 2, ey - 1), C_OUTLINE, 1.0)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var s := float(p["size"])
	var col: Color = p["color"]
	col.a = a
	ci.draw_set_transform(at, float(p["rot"]), Vector2.ONE)
	ci.draw_rect(Rect2(-s * 0.5 - 0.5, -s * 0.4 - 0.5, s + 1.0, s * 0.8 + 1.0), Color(C_OUTLINE, a * 0.8))
	ci.draw_rect(Rect2(-s * 0.5, -s * 0.4, s, s * 0.8), col)
	if s >= 2.5:
		ci.draw_rect(Rect2(-s * 0.5, -s * 0.4, s, 1.0), Color(col.lightened(0.3), a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_shadow(ci: CanvasItem, p: Dictionary) -> void:
	var s := 2.0 if String(p["kind"]) == "drop" else (8.0 if bool(p.get("piece", false)) else float(p.get("size", 2.0)))
	var z := float(p["z"])
	var a := clampf(0.3 - z * 0.006, 0.08, 0.3)
	ci.draw_set_transform(Vector2(p["pos"]), 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, s * 0.6, Color(0, 0, 0, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_spire(ci: CanvasItem, p: Dictionary) -> void:
	var t := float(p["t"]) - float(p.get("delay", 0.0))
	if t < 0.0:
		return
	var life := float(p["life"]) - float(p.get("delay", 0.0))
	var rise := clampf(t / 4.0, 0.0, 1.0)
	var sink := clampf((life - t) / 8.0, 0.0, 1.0)
	var h := float(p["h"]) * (1.0 - pow(1.0 - rise, 3.0)) * sink
	if h < 5.0:
		return  # too short to draw as a shape without it folding over
	var w := float(p["w"])
	var b: Vector2 = Vector2(p["pos"]).round()
	ci.draw_set_transform(b, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, w + 2.0, Color(0, 0, 0, 0.3))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var outline := PackedVector2Array([b + Vector2(-w - 1, 1), b + Vector2(-w * 0.6, -h * 0.5),
		b + Vector2(-w * 0.2, -h * 0.62), b + Vector2(0, -h - 1), b + Vector2(w * 0.35, -h * 0.72),
		b + Vector2(w * 0.55, -h * 0.5), b + Vector2(w + 1, 1)])
	ci.draw_colored_polygon(outline, C_OUTLINE)
	var body := PackedVector2Array([b + Vector2(-w, 0), b + Vector2(-w * 0.6, -h * 0.5 + 1),
		b + Vector2(-w * 0.2, -h * 0.62 + 1), b + Vector2(0, -h), b + Vector2(w * 0.35, -h * 0.72 + 1),
		b + Vector2(w * 0.55, -h * 0.5 + 1), b + Vector2(w, 0)])
	ci.draw_colored_polygon(body, C_STONE[1])
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-w, 0), b + Vector2(-w * 0.6, -h * 0.5 + 1),
		b + Vector2(-w * 0.2, -h * 0.62 + 1), b + Vector2(0, -h), b + Vector2(-w * 0.15, 0)]), C_STONE[2])
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(w * 0.35, -h * 0.72 + 1),
		b + Vector2(w * 0.55, -h * 0.5 + 1), b + Vector2(w, 0), b + Vector2(w * 0.3, 0)]), C_STONE[0])


func _draw_projectiles(ci: CanvasItem) -> void:
	for pr in sim.projectiles:
		var pp: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		if _is_wave(pr):
			_draw_wave(ci, pp.round(), vel)
			continue
		var frame := (_tick / 4) % 4
		var w := -16.0 if vel.x < 0.0 else 16.0
		ci.draw_texture_rect_region(SHEET, Rect2(pp.round() + Vector2(-w * 0.5, -14), Vector2(w, 16)),
			Rect2(frame * 16, 32, 16, 16))


## Runoff as a rolling wave: a low swell with a curling crest and foam.
func _draw_wave(ci: CanvasItem, p: Vector2, vel: Vector2) -> void:
	var dir := -1.0 if vel.x < 0.0 else 1.0
	var bob := sin(_tick * 0.5) * 1.0
	var h := 11.0 + bob
	ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.25))
	ci.draw_circle(Vector2(0, -1), 9.0, Color(C_WATER, 0.9))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pts := PackedVector2Array()
	pts.append(p + Vector2(-10 * dir, 1))
	pts.append(p + Vector2(-6 * dir, -h * 0.45))
	pts.append(p + Vector2(-1 * dir, -h * 0.85))
	pts.append(p + Vector2(3 * dir, -h))
	pts.append(p + Vector2(7 * dir, -h * 0.8))
	pts.append(p + Vector2(6 * dir, -h * 0.55))
	pts.append(p + Vector2(4 * dir, -h * 0.6))
	pts.append(p + Vector2(8 * dir, 1))
	if dir < 0.0:
		pts.reverse()
	ci.draw_colored_polygon(pts, C_WATER)
	ci.draw_line(p + Vector2(-5 * dir, -h * 0.45), p + Vector2(0, -h * 0.85), C_WATER_L, 1.0)
	ci.draw_line(p + Vector2(0, -h * 0.85), p + Vector2(3 * dir, -h), C_FOAM, 2.0)
	ci.draw_line(p + Vector2(3 * dir, -h), p + Vector2(7 * dir, -h * 0.8), C_FOAM, 1.0)
	for i in 3:
		var fx := p + Vector2((randf_range(-8, 8)), randf_range(-2, 1))
		ci.draw_rect(Rect2(fx.round(), Vector2.ONE), C_FOAM)


## Things drawn straight from creature state every frame: orbiting pebbles, Cairn's
## stones, the Storm Drain landing marker and Avalanche speed lines.
func _draw_creature_extras(ci: CanvasItem, floor_layer: bool) -> void:
	for c in sim.creatures:
		var attacking := c.state == CreatureSim.State.ATTACK
		var mv := c.move_def() if attacking else {}
		var fx: Dictionary = mv.get("fx", {})

		if attacking and c.charging and String(fx.get("charge", "")) == "pebbles":
			for pb in _pebbles(c, c.charge):
				if bool(pb["front"]) == floor_layer:
					continue
				var at := (Vector2(pb["ground"]) + Vector2(0, -float(pb["z"]))).round()
				var col := C_PEBBLE[1]
				if bool(pb["full"]) and (c.anim_t / 3) % 2 == 0:
					col = Color(1.0, 0.86, 0.5)
				ci.draw_rect(Rect2(at - Vector2(2, 1), Vector2(4, 3)), C_OUTLINE)
				ci.draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), col)

		if floor_layer:
			if attacking and bool(fx.get("telegraph", false)) and c.state_t <= int(mv.get("startup", 0)):
				_draw_telegraph(ci, c, mv)
			if c.is_armored():
				_draw_rooted(ci, c)
			if not (c.state in [CreatureSim.State.KO, CreatureSim.State.FALLING]) and not c.is_dummy:
				_draw_aim_mark(ci, c, attacking)
			continue

		if c.state != CreatureSim.State.KO:
			_draw_status(ci, c)

		var stack_def: Dictionary = c.def.get("stack", {})
		if not stack_def.is_empty() and c.stack > 0 and c.state != CreatureSim.State.KO:
			var slots := _stack_slots(c, c.stack)
			for i in slots.size():
				var at := (Vector2(slots[i][0]) + Vector2(0, -float(slots[i][1]))).round()
				ci.draw_set_transform(at, 0.0, Vector2(1.0, 0.7))
				ci.draw_circle(Vector2.ZERO, 3.4, C_OUTLINE)
				ci.draw_circle(Vector2.ZERO, 2.6, C_STACK[i % C_STACK.size()])
				ci.draw_circle(Vector2(-1, -1), 1.0, C_STACK[i % C_STACK.size()].lightened(0.35))
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if c.stack >= int(stack_def.get("max", 3)) and (c.anim_t / 6) % 2 == 0:
				var top := (c.pos + Vector2(0, -_top(c) - 7.0 - c.air_height() - 6.0)).round()
				ci.draw_rect(Rect2(top, Vector2.ONE), C_SPARK[0])

		if attacking and bool(fx.get("speedlines", false)):
			var segs: Array = mv.get("_segs", [])
			if segs.size() > 0:
				var last: Dictionary = segs[segs.size() - 1]
				if c.state_t >= int(mv.get("startup", 0)) and c.state_t <= int(last["at"]) + 6:
					var center := c.pos + Vector2(0, -_chest(c))
					for i in 30:
						var dir := Vector2.from_angle(randf() * TAU)
						var r0 := randf_range(80.0, 120.0)
						ci.draw_line(center + dir * r0, center + dir * (r0 + randf_range(60.0, 160.0)),
							Color(1, 1, 1, 0.22), 1.0)


func _draw_telegraph(ci: CanvasItem, c: CreatureSim, mv: Dictionary) -> void:
	var dash: Dictionary = mv.get("dash", {})
	var remaining := 0.0
	if not dash.is_empty():
		remaining = maxf(0.0, float(dash["to"]) - c.state_t) * float(dash["speed"])
	var land := c.pos + c.facing * (remaining + float(mv.get("reach", 0)))
	var k := clampf(float(c.state_t) / maxf(1.0, float(mv.get("startup", 1))), 0.0, 1.0)
	var r := float(mv.get("hit_radius", 40))
	var pulse := 0.5 + 0.5 * sin(_tick * 0.6)
	ci.draw_arc(land, r, 0.0, TAU, 48, Color(C_WARN, 0.25 + 0.35 * pulse * k), 1.0)
	ci.draw_arc(land, r * k, 0.0, TAU, 40, Color(C_WARN, 0.35), 1.0)
	ci.draw_set_transform(land, 0.0, Vector2(1.0, 0.38))
	ci.draw_circle(Vector2.ZERO, lerpf(4.0, 16.0, k), Color(0, 0, 0, 0.35))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A small chevron on the floor where the fighter faces. Aiming is 360 degrees but the
## sprites have three views, so this shows the exact angle; it brightens while an attack
## is still being aimed.
func _draw_aim_mark(ci: CanvasItem, c: CreatureSim, attacking: bool) -> void:
	var f := c.facing
	var aiming := attacking and c.active_seg() < 0 and c.state_t <= int(c.move_def().get("startup", 0)) + 1
	var a := 0.75 if aiming else 0.3
	var tip := c.pos + f * (c.radius + 9.0)
	var base := c.pos + f * (c.radius + 4.0)
	var side := f.orthogonal() * 3.0
	var pts := PackedVector2Array([tip, base + side, base - side])
	ci.draw_colored_polygon(pts, Color(1, 1, 1, a * 0.8))
	ci.draw_polyline(PackedVector2Array([base + side, tip, base - side]), Color(0, 0, 0, a * 0.6), 1.0)


## Bedrock: a glowing ring where the feet are planted, cracks pulsing outward.
func _draw_rooted(ci: CanvasItem, c: CreatureSim) -> void:
	var pulse := 0.5 + 0.5 * sin(_tick * 0.4)
	ci.draw_set_transform(c.pos, 0.0, Vector2(1.0, 0.42))
	ci.draw_arc(Vector2.ZERO, c.radius + 8.0 + pulse * 2.0, 0.0, TAU, 32, Color(C_AMBER, 0.55), 2.0)
	ci.draw_arc(Vector2.ZERO, c.radius + 15.0 + pulse * 3.0, 0.0, TAU, 32, Color(C_AMBER, 0.25), 1.0)
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(d * (c.radius + 4.0), d * (c.radius + 11.0 + pulse * 4.0), Color(C_AMBER, 0.6), 1.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Shield plates, slowed pebbles and the taunt mark, drawn over the creature.
func _draw_status(ci: CanvasItem, c: CreatureSim) -> void:
	var lift := c.air_height()
	if c.slow > 0:
		for i in 3:
			var a := _tick * 0.12 + TAU * i / 3.0
			var at := (c.pos + Vector2(cos(a) * (c.radius + 2.0), sin(a) * 3.0 - 1.0)).round()
			ci.draw_rect(Rect2(at - Vector2(1, 1), Vector2(3, 2)), C_OUTLINE)
			ci.draw_rect(Rect2(at - Vector2(0, 1), Vector2(1, 1)), C_GREY[2])
	if c.taunt > 0 and (c.taunt > 30 or (_tick / 4) % 2 == 0):
		var top := (c.pos + Vector2(0, -_top(c) - 10.0 - lift)).round()
		_bang(ci, top)


func _bang(ci: CanvasItem, at: Vector2) -> void:
	ci.draw_rect(Rect2(at + Vector2(-2, -9), Vector2(5, 8)), C_OUTLINE)
	ci.draw_rect(Rect2(at + Vector2(-2, 0), Vector2(5, 4)), C_OUTLINE)
	ci.draw_rect(Rect2(at + Vector2(-1, -8), Vector2(3, 6)), C_TAUNT)
	ci.draw_rect(Rect2(at + Vector2(-1, 1), Vector2(3, 2)), C_TAUNT)


func _draw_rain(ci: CanvasItem) -> void:
	var amount := minf(1.0, _rain / 30.0)
	var n := int(110 * amount)
	var col := Color(C_WATER_L, 0.45)
	for i in n:
		var x := fposmod(i * 37.7 + _tick * 2.4, 520.0) - 20.0
		var y := fposmod(i * 61.3 + i * i * 0.37 + _tick * 8.0, 300.0) - 15.0
		ci.draw_line(Vector2(x, y), Vector2(x - 2.0, y + 7.0), col, 1.0)
	var fr := SimDefs.floor_rect()
	for i in n / 3:
		var hsh := i * 7919 + (_tick / 4) * 104729
		var sx := fr.position.x + float(hsh % int(fr.size.x))
		var sy := fr.position.y + float((hsh / 7) % int(fr.size.y))
		ci.draw_rect(Rect2(Vector2(sx, sy - 1), Vector2(1, 1)), Color(C_FOAM, 0.6))
		ci.draw_rect(Rect2(Vector2(sx - 1, sy), Vector2(3, 1)), Color(C_WATER_L, 0.5))
