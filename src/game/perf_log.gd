class_name PerfLog
extends RefCounted
## Frame pacing during fights, for `--perf`: every drawn frame's wall time (measured
## between frames, not Godot's smoothed delta) and every 60 Hz tick's cost (inputs, CPU
## players, the sim, the views). `report()` gives percentiles and how many went over a
## 240 Hz, 120 Hz and 60 Hz frame, printed when the game quits. A stutter shows as a
## long tail (p99.9, max), not as the average.

const SKIP := 120  ## the first frames of a fight (loading, first draws) are left out

var frames := PackedFloat32Array()
var ticks := PackedFloat32Array()
var _last_us := 0


## Called once per drawn frame; `fighting` false (menus, banners) records nothing.
func frame(fighting: bool) -> void:
	var now := Time.get_ticks_usec()
	if fighting and _last_us > 0:
		frames.append((now - _last_us) / 1000.0)
	_last_us = now


func tick(fighting: bool, us: int) -> void:
	if fighting:
		ticks.append(us / 1000.0)


func report() -> String:
	var lines := ["PERF %s, %d fps now, %d draw calls" % [OS.get_processor_name(),
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]]
	lines.append(_line("frame", frames))
	lines.append(_line("tick", ticks))
	return "\n".join(lines)


static func _line(label: String, values: PackedFloat32Array) -> String:
	var a := Array(values).slice(SKIP)
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
