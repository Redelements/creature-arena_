extends SceneTree
## Rollback cost benchmark (not a test):
##   godot --headless --path . --script res://tests/bench_sim.gd
## Prints the time to step, snapshot and restore the match, and what an 8-frame
## rollback costs against a 16.7 ms frame.

func _init() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(245, 164)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var inputs: Array[PackedInt32Array] = []
	var hold := [0, 0]
	for i in 3000:
		if i % 8 == 0:
			hold = [rng.randi() & SimDefs.IN_EVERYTHING, rng.randi() & SimDefs.IN_EVERYTHING]
		inputs.append(PackedInt32Array(hold))
	var t0 := Time.get_ticks_usec()
	for f in inputs:
		sim.step(f)
	var step_us := float(Time.get_ticks_usec() - t0) / inputs.size()
	t0 = Time.get_ticks_usec()
	var snap := {}
	for i in 1000:
		snap = sim.snapshot()
	var snap_us := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	for i in 1000:
		sim.restore(snap)
	var restore_us := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	for i in 200:
		sim.state_digest()
	var digest_us := float(Time.get_ticks_usec() - t0) / 200.0
	var rb8 := restore_us + 8.0 * (step_us + snap_us)
	print("step     %.1f us" % step_us)
	print("snapshot %.1f us" % snap_us)
	print("restore  %.1f us" % restore_us)
	print("digest   %.1f us" % digest_us)
	print("8-frame rollback %.2f ms (%.0f%% of a 16.7 ms frame)" % [rb8 / 1000.0, rb8 / 167.0])
	print("frames re-simulated per 4 ms budget: %d" % int(4000.0 / (step_us + snap_us)))
	quit()
