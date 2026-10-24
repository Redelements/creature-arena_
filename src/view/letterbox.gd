class_name Letterbox
extends Control
## Black bars across the top and bottom of the screen for the big moments (a knockout's
## push-in, a Surge's freeze), on the screen layer: over the arena, under the HUD panels.
## main sets `shown` each tick and calls `advance()`; the bars slide in and out by whole
## pixels, BAR_STEP a tick, so nothing is drawn between pixels or between ticks.

## How tall each bar is when fully in, in canvas pixels (the 480 x 270 canvas: 9% each;
## the top one mostly sits under the HUD panels, so it has to reach below them to read).
const BAR_H := 24
## How many pixels a bar moves each tick: in over 8 ticks, out over 12.
const BAR_STEP_IN := 3
const BAR_STEP_OUT := 2
const C_BAR := Color(0, 0, 0, 1)

var shown := false
## The bars' height right now, in whole pixels (0: hidden).
var h := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## One tick: the bars step toward in or out. Redraws only when they move.
func advance() -> void:
	var before := h
	if shown:
		h = mini(BAR_H, h + BAR_STEP_IN)
	else:
		h = maxi(0, h - BAR_STEP_OUT)
	if h != before:
		queue_redraw()


## Straight to hidden (a new match, back to the menu).
func clear() -> void:
	shown = false
	if h != 0:
		h = 0
		queue_redraw()


func _draw() -> void:
	if h <= 0:
		return
	var s := size
	draw_rect(Rect2(0, 0, s.x, h), C_BAR)
	draw_rect(Rect2(0, roundf(s.y) - h, s.x, h), C_BAR)
