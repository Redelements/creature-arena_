class_name CrowdView
extends Node2D
## The crowd in the stands. Big moments raise excitement; more fans cheer and bounce,
## and camera flashes pop. A knockout makes the whole stadium jump (roar).

const SHEET := preload("res://assets/sprites/crowd.png")
const W := 12
const H := 16

var excitement := 0.1
var _tick := 0
var _seats: Array[Dictionary] = []
var _roar := 0
var _flashes: Array[Dictionary] = []


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


## Everyone on their feet for `ticks` frames.
func roar(ticks: int) -> void:
	_roar = maxi(_roar, ticks)
	excitement = 1.0


func advance() -> void:
	_tick += 1
	excitement = maxf(0.1, excitement * 0.985)
	if _roar > 0:
		_roar -= 1
	# Camera flashes once the crowd gets excited.
	var chance := maxf(0.0, excitement - 0.35) * 0.9 + (0.5 if _roar > 0 else 0.0)
	while chance > 0.0:
		if randf() < chance and not _seats.is_empty():
			var s: Dictionary = _seats[randi() % _seats.size()]
			_flashes.append({"pos": Vector2(s["pos"]) + Vector2(randi_range(3, 8), randi_range(2, 6)), "t": 3})
		chance -= 1.0
	for f in _flashes:
		f["t"] = int(f["t"]) - 1
	_flashes = _flashes.filter(func(f): return int(f["t"]) > 0)
	queue_redraw()


func _draw() -> void:
	var cheering := 10 if _roar > 0 else int(excitement * 10.0)
	for s in _seats:
		var up: bool = ((_tick / 6 + int(s["phase"])) % 10) < cheering
		var frame := int(s["variant"]) * 2 + (1 if up else 0)
		var p: Vector2 = s["pos"]
		if up and (_tick / 4 + int(s["phase"])) % 2 == 0:
			p.y -= 3 if _roar > 0 else 2
		draw_texture_rect_region(SHEET, Rect2(p, Vector2(W, H)), Rect2(frame * W, 0, W, H))
	for f in _flashes:
		var fp: Vector2 = f["pos"]
		var big := int(f["t"]) >= 3
		draw_rect(Rect2(fp - Vector2(1, 1), Vector2(3, 3)) if big else Rect2(fp, Vector2(1, 1)), Color(1, 1, 0.92, 0.95))
		if big:
			draw_rect(Rect2(fp - Vector2(3, 0), Vector2(7, 1)), Color(1, 1, 0.9, 0.5))
			draw_rect(Rect2(fp - Vector2(0, 3), Vector2(1, 7)), Color(1, 1, 0.9, 0.5))
