class_name FxView
extends Node2D
## Short-lived effects driven by simulation events: hit sparks, dust, slam shockwaves,
## and floating text. Purely cosmetic, so it may use randomness.

const SHEET := preload("res://assets/sprites/fx.png")

var _parts: Array[Dictionary] = []
var _font: Font = ThemeDB.fallback_font


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
			_text(p + Vector2(0, -6), str(int(round(power))), Color("ffe08a"))
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
			_text(p + Vector2(0, -40), "K.O.!", Color("ff6b6b"), 10)


func advance() -> void:
	for p in _parts:
		p["t"] = int(p["t"]) + 1
	_parts = _parts.filter(func(p): return int(p["t"]) < int(p["life"]))
	queue_redraw()


func _draw() -> void:
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
