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
## The frame line is also read as a player would: average fps, the 1% and 0.1% lows (the
## average fps over the slowest 1% and 0.1% of frames), the frames that missed the cap's
## refresh (over 1.5 frame intervals: shown twice), and the slowest second of the fight.

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
const SLOW_KEPT := 40  ## the slowest frames kept for the report
var _slow_ms := PackedFloat32Array()
var _start_us := 0


## Only the main thread records: `_part_us` is a plain Dictionary, and the CPU players
## think on worker threads (CpuController.think_all) with probes of their own in the way
## (cpu_controller.gd). Those count only when the CPUs think in turn (the AI bench with
## --threads=off); on a worker thread they do nothing, and the game never stalls on them.
static var _main_thread := OS.get_main_thread_id()


static func now() -> int:
	return Time.get_ticks_usec() if current != null and OS.get_thread_caller_id() == _main_thread else 0


static func since(part: String, t0: int) -> void:
	if current != null and t0 > 0 and OS.get_thread_caller_id() == _main_thread:
		current._part_us[part] = current._part_us.get(part, 0) + Time.get_ticks_usec() - t0


## A number to report like a part (a count, not ms): the most it reached in a frame.
static func count(part: String, n: int) -> void:
	if current != null and OS.get_thread_caller_id() == _main_thread:
		current._part_us[part] = maxi(int(current._part_us.get(part, 0)), n * 1000)


## Also log the renderer's CPU and GPU time for this viewport's frames.
func measure(viewport: RID) -> void:
	if "--render-thread" in OS.get_cmdline_args() or ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1) == 2:
		return  # reading the times waits for a separate render thread every frame (and slows it)
	_viewport = viewport
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
## The frame's first work (its tick, else its process) up to the renderer starting: the
## game's own cost for the frame (ticks, views, their drawing), without the renderer or
## the wait for the screen or the frame cap.
var _busy_from := 0
var _ticks_since := 0  ## ticks stepped since the last frame went to the renderer
var _no_tick_run := 0
## Runs of two or more frames without a tick (see _pre_draw).
var uneven := 0


func _pre_draw() -> void:
	if _busy_from > 0:
		since("game", _busy_from)
		# The same time split by what the frame carried: at 120 fps every other frame steps a
		# 60 Hz tick, and one that steps two (catching up after a slow frame) costs double.
		# A tick's picture held for three frames or more where two would be even (at 120 Hz):
		# a judder however steady the frames are. Counted as runs of frames with no tick.
		if _ticks_since == 0:
			_no_tick_run += 1
		else:
			if _no_tick_run >= 2:
				uneven += 1
			_no_tick_run = 0
		var kind := "game, tick frames" if _ticks_since == 1 else ("game, no-tick frames" if _ticks_since == 0 else "game, 2+ tick frames")
		since(kind, _busy_from)
	_busy_from = 0
	_ticks_since = 0


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
		if ms > 12.0 and frames.size() > SKIP and (slow.size() < SLOW_KEPT or ms > _slow_ms[_slowest_kept_min()]):
			var what := []
			for part in _part_us:
				if _part_us[part] > 500:
					what.append("%s %.1f" % [part, _part_us[part] / 1000.0])
			var line := "%.2fs %.1f ms (%s)" % [(now - _start_us) / 1e6, ms, ", ".join(what)]
			if slow.size() < SLOW_KEPT:
				slow.append(line)
				_slow_ms.append(ms)
			else:  # keep the slowest SLOW_KEPT, in the order they came
				var k := _slowest_kept_min()
				slow.remove_at(k)
				_slow_ms.remove_at(k)
				slow.append(line)
				_slow_ms.append(ms)
		for part in _part_us:
			_add_part(part, _part_us[part] / 1000.0)
		if _viewport.is_valid():
			_add_part("render cpu", RenderingServer.viewport_get_measured_render_time_cpu(_viewport))
			_add_part("render gpu", RenderingServer.viewport_get_measured_render_time_gpu(_viewport))
		# What the renderer was handed (counts, not ms): draw calls, canvas items, primitives.
		_add_part("draw calls (count)", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_add_part("objects (count)", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		_add_part("primitives (count)", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_part_us.clear()
	_last_us = now


func _slowest_kept_min() -> int:
	var k := 0
	for i in _slow_ms.size():
		if _slow_ms[i] < _slow_ms[k]:
			k = i
	return k


func _add_part(part: String, ms: float) -> void:
	if frames.size() <= SKIP:
		return
	if not parts.has(part):
		parts[part] = PackedFloat32Array()
	parts[part].append(ms)


func tick(fighting: bool, us: int) -> void:
	_ticks_since += 1
	if fighting:
		ticks.append(us / 1000.0)


func report(cap := 60) -> String:
	var lines := ["PERF %s, %s, %d fps now, %d draw calls" % [OS.get_processor_name(),
		RenderingServer.get_current_rendering_method(), Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]]
	lines.append("PERF memory: textures %.1f MB, video %.1f MB" % [
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	lines.append(_line("frame", frames))
	lines.append(lows(frames, cap))
	lines.append("PERF ticks held 3+ frames: %d (%.2f a second)" % [uneven, uneven * 1000.0 / maxf(1.0, _sum(frames))])
	lines.append(_line("tick", ticks))
	for part in parts:
		var line := _line("  " + part, parts[part], 0)
		if String(part).ends_with("(count)"):  # a count a frame, not a time
			line = line.replace(" ms: ", ": ").get_slice(" | ", 0)
		lines.append(line)
	for line in slow:
		lines.append("PERF slow frame at " + line)
	return "\n".join(lines)


## The frame times as a player reads them, at a cap of `cap` fps (see the header).
static func lows(values: PackedFloat32Array, cap: int, skip := SKIP) -> String:
	var a := Array(values).slice(skip)
	if a.is_empty():
		return "PERF fps: no samples"
	var total := 0.0
	for v in a:
		total += v
	var worst_s := INF
	var i0 := 0
	var span := 0.0
	for i in a.size():  # every run of frames a second long
		span += a[i]
		while span - a[i0] >= 1000.0:
			span -= a[i0]
			i0 += 1
		if span >= 1000.0:
			worst_s = minf(worst_s, (i - i0 + 1) * 1000.0 / span)
	var missed := a.filter(func(v): return v > 1500.0 / cap).size()
	var by := a.duplicate()
	by.sort()
	by.reverse()
	return "PERF fps at a cap of %d: avg %.1f, 1%% low %.1f, 0.1%% low %.1f, slowest second %s | missed %d of %d (%.2f%%, %.2f a second)" % [
		cap, a.size() * 1000.0 / total, _low(by, 0.01), _low(by, 0.001),
		"%.1f" % worst_s if worst_s < INF else "-", missed, a.size(), 100.0 * missed / a.size(), missed * 1000.0 / total]


static func _sum(a: PackedFloat32Array) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t


## The average fps over the slowest `share` of frames (`slowest_first` sorted, longest first).
static func _low(slowest_first: Array, share: float) -> float:
	var n := maxi(1, int(slowest_first.size() * share))
	var ms := 0.0
	for i in n:
		ms += slowest_first[i]
	return n * 1000.0 / ms


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
