class_name PerfLog
extends RefCounted
## Frame pacing during fights, for `--perf`: every drawn frame's wall time (measured
## between frames, not Godot's smoothed delta) and every 60 Hz tick's cost (inputs, CPU
## players, the sim, the views). `report()` gives percentiles and how many went over a
## 240 Hz, 120 Hz and 60 Hz frame, printed when the game quits. A stutter shows as a
## long tail (p99.9, max), not as the average.
## Parts: main and the views add where the time went (`PerfLog.since("fx", t0)` with `t0`
## from `PerfLog.now()`), plus the renderer's own CPU and GPU time per frame, so the report
## says which part to cut.

const SKIP := 120  ## the first frames of a fight (loading, first draws) are left out

var frames := PackedFloat32Array()
var ticks := PackedFloat32Array()
var _last_us := 0
## The running log while `--perf` is on, else null (then now/since cost next to nothing).
static var current: PerfLog = null
## Each part's time per frame it ran in (ms), and what it has added since the last frame.
var parts := {}
var _part_us := {}
var _viewport := RID()
## When the slowest frames came (seconds into the log) and what each part took in them.
var slow: Array[String] = []
var _start_us := 0


static func now() -> int:
	return Time.get_ticks_usec() if current != null else 0


static func since(part: String, t0: int) -> void:
	if current != null:
		current._part_us[part] = current._part_us.get(part, 0) + Time.get_ticks_usec() - t0


## Also log the renderer's CPU and GPU time for this viewport's frames.
func measure(viewport: RID) -> void:
	_viewport = viewport
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
## The frame's first work (its tick, else its process) up to the renderer starting: the
## game's own cost for the frame (ticks, views, their drawing), without the renderer or
## the wait for the screen or the frame cap.
var _busy_from := 0


func _pre_draw() -> void:
	if _busy_from > 0:
		since("game", _busy_from)
	_busy_from = 0


## Called first thing in a tick and in a frame's process.
static func mark() -> void:
	if current != null and current._busy_from == 0:
		current._busy_from = Time.get_ticks_usec()


## Called once per drawn frame; `fighting` false (menus, banners) records nothing.
func frame(fighting: bool) -> void:
	var now := Time.get_ticks_usec()
	if fighting and _last_us > 0:
		var ms := (now - _last_us) / 1000.0
		frames.append(ms)
		if _start_us == 0:
			_start_us = now
		if ms > 12.0 and frames.size() > SKIP and slow.size() < 40:
			var what := []
			for part in _part_us:
				if _part_us[part] > 500:
					what.append("%s %.1f" % [part, _part_us[part] / 1000.0])
			slow.append("%.2fs %.1f ms (%s)" % [(now - _start_us) / 1e6, ms, ", ".join(what)])
		for part in _part_us:
			_add_part(part, _part_us[part] / 1000.0)
		if _viewport.is_valid():
			_add_part("render cpu", RenderingServer.viewport_get_measured_render_time_cpu(_viewport))
			_add_part("render gpu", RenderingServer.viewport_get_measured_render_time_gpu(_viewport))
	_part_us.clear()
	_last_us = now


func _add_part(part: String, ms: float) -> void:
	if frames.size() <= SKIP:
		return
	if not parts.has(part):
		parts[part] = PackedFloat32Array()
	parts[part].append(ms)


func tick(fighting: bool, us: int) -> void:
	if fighting:
		ticks.append(us / 1000.0)


func report() -> String:
	var lines := ["PERF %s, %d fps now, %d draw calls" % [OS.get_processor_name(),
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]]
	lines.append(_line("frame", frames))
	lines.append(_line("tick", ticks))
	for part in parts:
		lines.append(_line("  " + part, parts[part], 0))
	for line in slow:
		lines.append("PERF slow frame at " + line)
	return "\n".join(lines)


static func _line(label: String, values: PackedFloat32Array, skip := SKIP) -> String:
	var a := Array(values).slice(skip)
	if a.is_empty():
		return "PERF %s: no samples" % label
	a.sort()
	var sum := 0.0
	for v in a:
		sum += v
	var over := func(ms: float) -> int: return a.filter(func(v): return v > ms).size()
	return "PERF %s ms: n=%d avg=%.2f p50=%.2f p99=%.2f p99.9=%.2f max=%.2f | over 4.2: %d, 8.3: %d, 16.7: %d" % [
		label, a.size(), sum / a.size(), a[a.size() / 2], a[int(a.size() * 0.99)],
		a[int(a.size() * 0.999)], a[-1], over.call(4.17), over.call(8.33), over.call(16.67)]
