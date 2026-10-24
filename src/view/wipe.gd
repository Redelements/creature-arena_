class_name Wipe
extends Control
## A pixel wipe between screens: black blocks on a coarse grid that clear away along a
## diagonal, a step per tick (no interpolation, no smooth scaling; blocks are whole
## canvas pixels). The screen change has already happened underneath: the wipe starts
## fully covered and uncovers the new screen in TICKS ticks, so it can never hold the
## game up. Any press (or `finish()`) ends it at once. Drawn on the top layer.

const TICKS := 16
const CELL := 24  ## canvas units
const C_WIPE := Color(0.03, 0.03, 0.05, 1.0)

var t := -1  ## ticks since it began; -1: idle
var _cols := 0
var _rows := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func active() -> bool:
	return t >= 0


func start() -> void:
	t = 0
	visible = true
	queue_redraw()


func finish() -> void:
	if t >= 0:
		t = -1
		visible = false


## One tick. Redraws the step; ends after TICKS.
func advance() -> void:
	if t < 0:
		return
	t += 1
	if t >= TICKS:
		finish()
	else:
		queue_redraw()


## Whether the block at (col, row) is still black at tick `at`: the diagonal sweeps from
## the top left, each block clearing once the front has passed it.
static func covered(col: int, row: int, cols: int, rows: int, at: int) -> bool:
	var reach := cols + rows  # the diagonal index runs 0 .. cols + rows - 2
	var front := float(at) / float(TICKS) * float(reach + 6)
	return float(col + row) + 3.0 * float((col * 7 + row * 3) % 3) / 3.0 > front


func _draw() -> void:
	if t < 0:
		return
	var s := size
	_cols = ceili(s.x / CELL)
	_rows = ceili(s.y / CELL)
	for r in _rows:
		for c in _cols:
			if covered(c, r, _cols, _rows, t):
				draw_rect(Rect2(c * CELL, r * CELL, CELL, CELL), C_WIPE)
