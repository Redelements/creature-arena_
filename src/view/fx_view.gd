class_name FxView
extends Node2D
## Short-lived effects driven by simulation events: hit sparks, dust, slam shockwaves,
## and floating text. Purely cosmetic, so it may use randomness.

const SHEET := preload("res://assets/sprites/fx.png")

var sim: MatchSim
var _parts: Array[Dictionary] = []
var _font: Font = ThemeDB.fallback_font
var _tick := 0


func clear() -> void:
	_parts.clear()
	queue_redraw()


func spawn(e: Dictionary) -> void:
	var p: Vector2 = e["pos"]
	var power: float = e["power"]
	match String(e["type"]):
		"hit":
			var big := power >= 9.0 or bool(e.get("heavy", false))
			_add({"kind": "spark", "pos": p, "life": 12 if big else 8, "scale": 2.0 if big else 1.0})
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
			_text(p + Vector2(0, -6), "BLOCK", Color("9ec5ff"))
		"guard_break":
			_text(p + Vector2(0, -34), "GUARD BREAK", Color("ff9a5a"))
		"slam":
			var full := power >= 1.0
			_add({"kind": "ring", "pos": p, "life": 18 if full else 12, "radius": 34.0 if full else 18.0})
			var n := 10 if full else 6
			for i in n:
				var a := TAU * i / n + randf() * 0.3
				var r := (22.0 if full else 12.0) + randf() * 6.0
				_dust(p + Vector2(cos(a) * r, sin(a) * r * 0.5), Vector2(cos(a), sin(a) * 0.5 - 0.6) * 0.5)
		"bounce":
			_add({"kind": "spark", "pos": p + Vector2(0, -12), "life": 8, "scale": 1.0})
			_dust(p, Vector2(0, -0.4))
		"fall":
			for i in 4:
				_dust(p + Vector2(randf_range(-8, 8), randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.5))
		"land", "dodge":
			_dust(p + Vector2(0, 1), Vector2(0, -0.3))
		"ko":
			_add({"kind": "spark", "pos": p + Vector2(0, -16), "life": 16, "scale": 2.5})
		"slip":
			_text(p, "SLIP!", Color("9ee6ff"))
		"grab":
			_text(p, "GULP!", Color("b6f28a"))
		"breakaway":
			_add({"kind": "ring", "pos": p + Vector2(0, 16), "life": 16, "radius": 30.0})
			_text(p + Vector2(0, -10), "BREAKAWAY", Color("c9a7ff"))
		"surge":
			_add({"kind": "ring", "pos": p, "life": 20, "radius": 40.0})
			_text(p + Vector2(0, -44), String(e.get("name", "SURGE")).to_upper() + "!", Color("ffcf3f"), 10)
		"land_hard", "projectile", "projectile_end":
			for i in 3:
				_dust(p + Vector2(randf_range(-6, 6), randf_range(-2, 2)), Vector2(randf_range(-0.3, 0.3), -0.4))


## A click marker for League-style orders: green for a move, red for an attack.
func ping(pos: Vector2, attack: bool) -> void:
	_add({"kind": "ping", "pos": pos, "life": 18, "attack": attack})


func advance() -> void:
	_tick += 1
	for p in _parts:
		p["t"] = int(p["t"]) + 1
	_parts = _parts.filter(func(p): return int(p["t"]) < int(p["life"]))
	queue_redraw()


func _draw() -> void:
	if sim != null:
		for pr in sim.projectiles:
			var pp: Vector2 = pr["pos"]
			var vel: Vector2 = pr["vel"]
			var frame := (_tick / 4) % 4
			var w := -16.0 if vel.x < 0.0 else 16.0
			draw_texture_rect_region(SHEET, Rect2(pp.round() + Vector2(-w * 0.5, -14), Vector2(w, 16)),
				Rect2(frame * 16, 32, 16, 16))
	for p in _parts:
		var t := float(p["t"])
		var life := float(p["life"])
		var k := t / life
		var pos: Vector2 = p["pos"]
		match String(p["kind"]):
			"spark":
				var s: float = p["scale"]
				var frame := mini(int(k * 4.0), 3)
				var size := Vector2(16, 16) * s
				draw_texture_rect_region(SHEET, Rect2((pos - size * 0.5).round(), size), Rect2(frame * 16, 0, 16, 16))
			"dust":
				var v: Vector2 = p["vel"]
				var frame := mini(int(k * 4.0), 3)
				draw_texture_rect_region(SHEET, Rect2((pos + v * t - Vector2(8, 12)).round(), Vector2(16, 16)), Rect2(frame * 16, 16, 16, 16))
			"ping":
				var col := Color("ff5a5a") if bool(p["attack"]) else Color("7cf27c")
				col.a = 1.0 - k
				var r := lerpf(9.0, 3.0, k)
				draw_set_transform(pos, 0.0, Vector2(1.0, 0.5))
				draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, col, 1.5)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				for ang in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
					var dir := Vector2.from_angle(ang) * Vector2(1.0, 0.5)
					draw_line(pos + dir * (r + 4.0), pos + dir * (r + 1.0), col, 1.0)
			"ring":
				var r := lerpf(4.0, float(p["radius"]), sqrt(k))
				draw_set_transform(pos, 0.0, Vector2(1.0, 0.5))
				draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1.0, 0.92, 0.7, 1.0 - k), 2.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"text":
				var col: Color = p["color"]
				col.a = 1.0 - maxf(0.0, k - 0.6) / 0.4
				var at := pos + Vector2(-40, -t * 0.5)
				var fs: int = p["size"]
				draw_string_outline(_font, at, String(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, 3, Color(0.1, 0.08, 0.1, col.a))
				draw_string(_font, at, String(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, col)


func _add(p: Dictionary) -> void:
	p["t"] = 0
	_parts.append(p)


func _dust(pos: Vector2, vel: Vector2) -> void:
	_add({"kind": "dust", "pos": pos, "vel": vel, "life": 16})


func _text(pos: Vector2, text: String, color: Color, size := 8) -> void:
	_add({"kind": "text", "pos": pos, "text": text, "color": color, "size": size, "life": 40})
