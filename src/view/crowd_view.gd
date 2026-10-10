class_name CrowdView
extends Node2D
## The crowd in the stands. Big moments raise excitement; more fans cheer and bounce.

const SHEET := preload("res://assets/sprites/crowd.png")
const W := 12
const H := 16

var excitement := 0.1
var _tick := 0
var _seats: Array[Dictionary] = []


func _ready() -> void:
	for row in 3:
		for i in 40:
			var x := 2 + i * 12 + (row % 2) * 6
			if x > SimDefs.VIEW_W - W or (i * 3 + row * 5) % 11 == 0:
				continue  # leave a few empty seats
			_seats.append({
				"pos": Vector2(x, 1 + row * 14),
				"variant": (i * 5 + row * 3) % 4,
				"phase": (i * 7 + row * 11) % 13,
			})


func cheer(amount: float) -> void:
	excitement = minf(1.0, excitement + amount)


func advance() -> void:
	_tick += 1
	excitement = maxf(0.1, excitement * 0.985)
	queue_redraw()


func _draw() -> void:
	var cheering := int(excitement * 10.0)
	for s in _seats:
		var up: bool = ((_tick / 6 + int(s["phase"])) % 10) < cheering
		var frame := int(s["variant"]) * 2 + (1 if up else 0)
		var p: Vector2 = s["pos"]
		if up and (_tick / 4 + int(s["phase"])) % 2 == 0:
			p.y -= 2
		draw_texture_rect_region(SHEET, Rect2(p, Vector2(W, H)), Rect2(frame * W, 0, W, H))
