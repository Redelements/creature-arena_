class_name PerfOverlay
extends Control
## The performance overlay (Settings > Video, or F9): the frame rate in a corner, and in
## its second mode a chart of the last few seconds of frame times with lines at the
## 240, 120 and 60 Hz budgets, so a stutter shows as a spike over a line. Under the chart:
## the last tick's cost (inputs, CPU players, sim, views) and the renderer's CPU and GPU
## time. It only measures; it never touches the match. `--perf` is the full report.
##
## Frame times are wall time between drawn frames (not Godot's smoothed delta), the same
## as PerfLog. The text updates a few times a second so it can be read; the chart every
## frame.

enum Mode { OFF, FPS, GRAPH }
const MODE_NAMES := ["Off", "FPS", "FPS + graph"]

## Frames kept for the chart and the 1% low (about four seconds at 60 fps, one at 240).
const SAMPLES := 240
## The chart's top, in ms: anything slower is clipped to it (and drawn red).
const CHART_MS := 20.0
## In the 480 x 270 canvas the HUD uses (scaled up to the window).
const CHART_W := 96.0
const CHART_H := 36.0
const PAD := 3.0
## Budget lines: [ms, label, colour].
const LINES := [[1000.0 / 240.0, "240", Color(0.45, 0.9, 0.55, 0.7)],
	[1000.0 / 120.0, "120", Color(1.0, 0.85, 0.35, 0.7)], [1000.0 / 60.0, "60", Color(1.0, 0.4, 0.35, 0.7)]]
const TEXT_EVERY_US := 250000
const C_BG := Color(0, 0, 0, 0.55)
const C_TEXT := Color(0.92, 0.92, 0.92)
const C_DIM := Color(0.7, 0.7, 0.7)

var mode := Mode.OFF:
	set(v):
		mode = v
		visible = v != Mode.OFF
		if v != Mode.OFF and _viewport.is_valid():
			RenderingServer.viewport_set_measure_render_time(_viewport, true)
		_last_us = 0
		queue_redraw()

var _font: Font:  ## read each draw, so Settings > Video > Text font shows at once
	get: return UiTheme.font()
var _viewport := RID()
var _ms := PackedFloat32Array()  ## ring buffer of frame times
var _at := 0
var _count := 0
var _last_us := 0
var _tick_ms := 0.0
var _text_us := 0
var _line1 := ""
var _line2 := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_ms.resize(SAMPLES)
	_viewport = get_viewport().get_viewport_rid()
	mode = mode


## Main reports each 60 Hz tick's cost (µs).
func tick(us: int) -> void:
	_tick_ms = us / 1000.0


func _process(_delta: float) -> void:
	if mode == Mode.OFF:
		return
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_ms[_at] = (now - _last_us) / 1000.0
		_at = (_at + 1) % SAMPLES
		_count = mini(_count + 1, SAMPLES)
	_last_us = now
	if now - _text_us >= TEXT_EVERY_US:
		_text_us = now
		_update_text()
	queue_redraw()


## Average fps over the last half second, and the 1% low over the whole buffer.
func _update_text() -> void:
	if _count == 0:
		_line1 = "-- fps"
		return
	var sum := 0.0
	var n := 0
	var i := _at
	while n < _count and sum < 500.0:
		i = (i - 1 + SAMPLES) % SAMPLES
		sum += _ms[i]
		n += 1
	var fps := 1000.0 * n / maxf(sum, 0.001)
	var sorted := _ms.slice(0, _count) if _count < SAMPLES else _ms.duplicate()
	sorted.sort()
	var worst := sorted[clampi(int(ceil(sorted.size() * 0.99)) - 1, 0, sorted.size() - 1)]
	_line1 = "%d fps   1%% low %d" % [roundi(fps), roundi(1000.0 / maxf(worst, 0.001))]
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(_viewport) \
		+ RenderingServer.get_frame_setup_time_cpu()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_viewport)
	_line2 = "tick %.1f ms   render cpu %.1f  gpu %.1f ms" % [_tick_ms, cpu, gpu]


func _draw() -> void:
	if mode == Mode.OFF:
		return
	var graph := mode == Mode.GRAPH
	var w := CHART_W + PAD * 2.0 if graph else 52.0
	var h := (CHART_H + 16.0 if graph else 6.0) + PAD * 2.0
	var vs := get_viewport_rect().size
	var origin := Vector2(vs.x - w - 3.0, vs.y - h - 14.0)  # above the controls strip
	draw_rect(Rect2(origin, Vector2(w, h)), C_BG)
	var x0 := origin.x + PAD
	_text(Vector2(x0, origin.y + PAD + 5.0), _line1, 6, C_TEXT)
	if not graph:
		return
	var top := origin.y + PAD + 8.0
	var bottom := top + CHART_H
	for ln in LINES:
		var y := bottom - CHART_H * float(ln[0]) / CHART_MS
		draw_line(Vector2(x0, y), Vector2(x0 + CHART_W, y), ln[2], 0.34)
		_text(Vector2(x0 + CHART_W - 9.0, y - 0.8), String(ln[1]), 4, ln[2])
	if _count > 1:
		var pts := PackedVector2Array()
		var colors := PackedColorArray()
		var step := CHART_W / float(SAMPLES - 1)
		for k in _count:
			# Oldest on the left, newest at the right edge.
			var ms := _ms[(_at - _count + k + SAMPLES) % SAMPLES]
			pts.append(Vector2(x0 + CHART_W - step * (_count - 1 - k), bottom - CHART_H * minf(ms, CHART_MS) / CHART_MS))
			colors.append(_color(ms))
		draw_polyline_colors(pts, colors, 0.34)
	_text(Vector2(x0, bottom + 6.0), _line2, 4, C_DIM)


static func _color(ms: float) -> Color:
	for ln in LINES:
		if ms <= float(ln[0]) * 1.05:
			return Color(ln[2], 1.0)
	return Color(1.0, 0.25, 0.25)


func _text(at: Vector2, s: String, fs: int, col: Color) -> void:
	var size_px := UiTheme.px(fs)
	draw_string_outline(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 1, Color(0, 0, 0, 0.8))
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
