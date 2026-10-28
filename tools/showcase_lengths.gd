extends SceneTree
## How long each showcase plays, for tools/capture_gallery.py (which picks the frames to
## capture from it, so a retune that changes a combo's length keeps the captures in step).
##   godot --headless --path . --script res://tools/showcase_lengths.gd
## Prints one line: `SHOWCASE_LENGTHS {"cairn": {"ticks": 636, "last": 486}, ...}`, where
## `ticks` is the whole script and `last` the tick its final step (the closing wait) starts.
## Steps the sim exactly as tests/test_showcase.gd does; nothing is drawn.


func _init() -> void:
	var out := {}
	for name in Showcase.names():
		var sc := Showcase.new(String(name))
		var sim := sc.build()
		var steps: int = (sc.script_def["steps"] as Array).size()
		var n := 0
		var last := -1
		while not sc.finished and n < 10000:
			if last < 0 and sc.step >= steps - 1:
				last = n
			sim.step(sc.inputs(sim))
			n += 1
		out[name] = {"ticks": n, "last": last if last >= 0 else n}
	print("SHOWCASE_LENGTHS " + JSON.stringify(out))
	quit()
