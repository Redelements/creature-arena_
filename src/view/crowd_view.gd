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
## Redrawn only when the picture changes: who is up (CROWD_KEY's parts), a flash, or the
## camera nearing the edge of the seats last drawn (only seats on screen, plus CULL_PAD,
## are drawn: a big map's stands are mostly off screen).
var _drawn_key := Vector4i(-1, -1, -1, -1)
var _drawn_rect := Rect2()
const CULL_PAD := 96.0
## The camera flashes, on a layer of their own over the seats: they pop on most ticks of
## a busy fight, and redrawing a few pixels is nothing next to redrawing every seat.
var _flash_layer: FlashLayer
var _drawn_flashes := false


class FlashLayer extends Node2D:
	var crowd: CrowdView

	func _draw() -> void:
		crowd._draw_flashes(self)


func _ready() -> void:
	_flash_layer = FlashLayer.new()
	_flash_layer.crowd = self
	add_child(_flash_layer)
	set_width(SimDefs.ARENA_W)


## Lays the seats along a stadium `w` px wide (a bigger map's is wider), running on past
## it for wide screens (ArenaView.MARGIN).
func set_width(w: float) -> void:
	_seats.clear()
	_drawn_key = Vector4i(-1, -1, -1, -1)
	queue_redraw()
	var from := -int(ArenaView.MARGIN.x / 12.0)
	var to := int((w + ArenaView.MARGIN.x) / 12.0)
	for row in 3:
		for i in range(from, to):
			var x := 2 + i * 12 + (row % 2) * 6
			if posmod(i * 3 + row * 5, 11) == 0:
				continue  # leave a few empty seats
			_seats.append({
				"pos": Vector2(x, 1 + row * 14),
				"variant": posmod(i * 5 + row * 3, 4),
				"phase": posmod(i * 7 + row * 11, 13),
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
	var cheering := 10 if _roar > 0 else int(excitement * 10.0)
	var key := Vector4i(cheering, _tick / 6, _tick / 4, int(_roar > 0))
	if key != _drawn_key or not _drawn_rect.encloses(_view_rect().grow(-CULL_PAD * 0.5)):
		_drawn_key = key
		queue_redraw()
	if _flash_layer != null and (_drawn_flashes or not _flashes.is_empty()):
		_drawn_flashes = not _flashes.is_empty()
		_flash_layer.queue_redraw()


## The part of this node's space on screen now.
func _view_rect() -> Rect2:
	if not is_inside_tree():
		return Rect2()
	return get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()


func _draw() -> void:
	var t0 := PerfLog.now()
	_draw_now()
	PerfLog.since("crowd draw", t0)


func _draw_now() -> void:
	var cheering := 10 if _roar > 0 else int(excitement * 10.0)
	_drawn_rect = _view_rect().grow(CULL_PAD)
	var seen := _drawn_rect.grow_individual(W, H, 0, 0)
	for s in _seats:
		if not seen.has_point(s["pos"]):
			continue
		var up: bool = ((_tick / 6 + int(s["phase"])) % 10) < cheering
		var frame := int(s["variant"]) * 2 + (1 if up else 0)
		var p: Vector2 = s["pos"]
		if up and (_tick / 4 + int(s["phase"])) % 2 == 0:
			p.y -= 3 if _roar > 0 else 2
		draw_texture_rect_region(SHEET, Rect2(p, Vector2(W, H)), Rect2(frame * W, 0, W, H))


func _draw_flashes(ci: CanvasItem) -> void:
	for f in _flashes:
		var fp: Vector2 = f["pos"]
		var big := int(f["t"]) >= 3
		ci.draw_rect(Rect2(fp - Vector2(1, 1), Vector2(3, 3)) if big else Rect2(fp, Vector2(1, 1)), Color(1, 1, 0.92, 0.95))
		if big:
			ci.draw_rect(Rect2(fp - Vector2(3, 0), Vector2(7, 1)), Color(1, 1, 0.9, 0.5))
			ci.draw_rect(Rect2(fp - Vector2(0, 3), Vector2(1, 7)), Color(1, 1, 0.9, 0.5))
