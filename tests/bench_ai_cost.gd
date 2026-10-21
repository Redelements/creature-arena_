extends SceneTree
## What a tick costs in a big team match: the CPU players' thinking (all slots, through
## CpuController.think_all) and the sim step, as percentiles over a seeded match. A stutter
## shows in the tail (p99.9, max), so watch those, not the average. At 240 Hz a frame is
## 4.2 ms and every fourth one carries a tick. The editor binary runs GDScript slower than
## a release build, and its threads gain less, so compare runs with each other.
##   godot --headless --path . --script res://tests/bench_ai_cost.gd -- [--mode=ctf|caravan|sinkhole]
##       [--size=4] [--level=3] [--seconds=180] [--seed=7] [--threads=off]

const ROSTER := ["cairn", "sno", "pete", "craglash", "culvert", "digby", "hissy", "barkley", "gillbert", "cerebro"]
const PATHS := {"ctf": TeamSim.CTF_PATH, "caravan": TeamSim.CARAVAN_PATH, "sinkhole": TeamSim.SINKHOLE_PATH}


func _init() -> void:
	var mode := "ctf"
	var size := 4
	var level := 3
	var seconds := 180
	var seed := 7
	for arg in OS.get_cmdline_user_args():
		var v := arg.get_slice("=", 1)
		if arg.begins_with("--mode="):
			mode = v
		elif arg.begins_with("--size="):
			size = int(v)
		elif arg.begins_with("--level="):
			level = int(v)
		elif arg.begins_with("--seconds="):
			seconds = int(v)
		elif arg.begins_with("--seed="):
			seed = int(v)
		elif arg == "--threads=off":
			CpuController.threaded = false
	var teams := [[], []]
	for k in size * 2:
		teams[k % 2].append(ROSTER[(seed + k) % ROSTER.size()])
	var t := TeamSim.new(teams, size, TeamSim.load_rules(PATHS.get(mode, TeamSim.CTF_PATH)))
	var cpus: Array = []
	for i in t.slot_count():
		cpus.append(CpuController.new(i, level, seed * 100 + i))
	var think := PackedFloat32Array()
	var step := PackedFloat32Array()
	for tick in seconds * 60:
		var a := Time.get_ticks_usec()
		CpuController.think_all(cpus, t.sim)
		var ins := PackedInt32Array()
		for c in cpus:
			ins.append((c as CpuController).last_bits)
		var b := Time.get_ticks_usec()
		t.step(ins)
		think.append((b - a) / 1000.0)
		step.append((Time.get_ticks_usec() - b) / 1000.0)
		if t.phase == TeamSim.Phase.OVER:
			break
	print("%s %dv%d, CPU %s, threads %s, %d ticks" % [mode, size, size, CpuController.LEVELS[level]["name"],
		"on" if CpuController.threaded else "off", think.size()])
	print(PerfLog._line("cpu think", think).trim_prefix("PERF "))
	print(PerfLog._line("sim step", step).trim_prefix("PERF "))
	quit()
