extends SceneTree
## Caravan pacing: seeded CPU matches (Normal by default) on the Caravan rules. Prints, per
## match, each round's push (share of the track, or the finish time), checkpoints, the
## rockslides and how long the caravan spent digging, the escort's healing, and the winner.
##   godot --headless --path . --script res://tests/bench_caravan.gd -- [--seeds=6] [--sizes=2,3] [--level=1]

const ROSTER := ["cairn", "sno", "pete", "craglash", "culvert", "digby", "hissy", "barkley", "gillbert", "cerebro"]


func _init() -> void:
	var seeds := 6
	var sizes := [3]
	var level := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = int(arg.get_slice("=", 1))
		elif arg.begins_with("--sizes="):
			sizes = Array(arg.get_slice("=", 1).split(",")).map(func(x): return int(x))
		elif arg.begins_with("--level="):
			level = int(arg.get_slice("=", 1))
	var rules := TeamSim.load_rules(TeamSim.CARAVAN_PATH)
	print("Caravan bench: %d seeds per size, CPU level %s" % [seeds, CpuController.LEVELS[level]["name"]])
	for size in sizes:
		_bench(int(size), seeds, level, rules)
	quit()


func _bench(size: int, seeds: int, level: int, rules: Dictionary) -> void:
	print("\n%d v %d | seed | round: push, checkpoints, rockslides, digging s, healed hp | winner | secs" % [size, size])
	for s in seeds:
		var teams := [[], []]
		for k in size * 2:
			teams[k % 2].append(ROSTER[(s * 3 + k) % ROSTER.size()])
		var t := TeamSim.new(teams, size, rules.duplicate(true))
		var cpus: Array = []
		for i in t.slot_count():
			cpus.append(CpuController.new(i, level, 1000 * s + i))
		var rounds := [{}, {}]
		for tick in 60 * 600:
			var hp_before := 0.0
			for c in t.members(t.cv_attacker()):
				hp_before += (c as CreatureSim).hp
			var ins := PackedInt32Array()
			for i in t.slot_count():
				ins.append((cpus[i] as CpuController).bits(t.sim))
			var r := t.cv_round
			var healing := 0
			for c in t.members(t.cv_attacker()):
				if t.escort_healing(c):
					healing += 1
			t.step(ins)
			var row: Dictionary = rounds[r]
			for e in t.sim.events:
				if String(e["type"]) == "rockslide":
					row["slides"] = int(row.get("slides", 0)) + 1
			if t.cv_state == 3:
				row["dig"] = int(row.get("dig", 0)) + 1
			row["heal"] = float(row.get("heal", 0.0)) + float(healing) * float(rules.get("escort_heal", 0)) / 60.0
			if t.phase == TeamSim.Phase.OVER:
				break
		var parts := []
		for r in 2:
			var row: Dictionary = rounds[r]
			var push := "%d s" % (int(t.cv_time[r]) / 60) if int(t.cv_time[r]) >= 0 else "%d%%" % roundi(100.0 * float(t.cv_best[r]) / t.track_length())
			parts.append("R%d %s, %d slides, dig %.1f s, heal %d" % [r + 1, push, int(row.get("slides", 0)),
				float(row.get("dig", 0)) / 60.0, roundi(float(row.get("heal", 0.0)))])
		print("      | %d | %s | %s | %d" % [s, " · ".join(parts), ["RED", "BLUE"][t.winner] if t.winner >= 0 else "draw",
			roundi(float(t.sim.tick) / 60.0)])
