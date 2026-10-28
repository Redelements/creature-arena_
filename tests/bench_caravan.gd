extends SceneTree
## Caravan pacing: seeded CPU matches (Normal by default) on the Caravan rules. Prints, per
## match, each round's push (share of the track, or the finish time), checkpoints, the
## rockslides and how long the caravan spent digging, the escort's healing, and the winner;
## then a summary per size: the average push, checkpoints a round, finished pushes, how
## much of the fight an attacker / a defender was at the caravan, the caravan's state
## (pushed, contested, rolled back, nobody, digging) as shares of the fight, and how often
## the side that attacked first won.
##   godot --headless --path . --script res://tests/bench_caravan.gd -- [--seeds=6] [--sizes=2,3] [--level=1] [--plan=off]

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
		elif arg == "--plan=off":
			CpuController.caravan_default = false  # the caravan played as a plain zone (before Oct 2026)
	var rules := TeamSim.load_rules(TeamSim.CARAVAN_PATH)
	print("Caravan bench: %d seeds per size, CPU level %s" % [seeds, CpuController.LEVELS[level]["name"]])
	for size in sizes:
		_bench(int(size), seeds, level, rules)
	quit()


func _bench(size: int, seeds: int, level: int, rules: Dictionary) -> void:
	print("\n%d v %d | seed | round: push, checkpoints, rockslides, digging s, healed hp | winner | secs" % [size, size])
	var sum := {"push": 0.0, "cps": 0, "done": 0, "rounds": 0, "fight": 0, "att": 0, "def": 0,
		"s1": 0, "s2": 0, "s-1": 0, "s0": 0, "s3": 0, "red": 0, "decided": 0}
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
			if t.phase == TeamSim.Phase.FIGHT:
				var n := t.caravan_counts()
				sum["fight"] += 1
				sum["att"] += 1 if int(n[t.cv_attacker()]) > 0 else 0
				sum["def"] += 1 if int(n[1 - t.cv_attacker()]) > 0 else 0
				sum["s%d" % t.cv_state] += 1
			var cp_before := t.cv_cp
			var healing := 0
			for c in t.members(t.cv_attacker()):
				if t.escort_healing(c):
					healing += 1
			t.step(ins)
			var row: Dictionary = rounds[r]
			row["cps"] = maxi(int(row.get("cps", 0)), t.cv_cp if t.cv_round == r else cp_before)
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
			sum["rounds"] += 1
			sum["cps"] += int(row.get("cps", 0))
			sum["done"] += 1 if int(t.cv_time[r]) >= 0 else 0
			sum["push"] += 1.0 if int(t.cv_time[r]) >= 0 else float(t.cv_best[r]) / t.track_length()
			parts.append("R%d %s, %d cps, %d slides, dig %.1f s, heal %d" % [r + 1, push, int(row.get("cps", 0)), int(row.get("slides", 0)),
				float(row.get("dig", 0)) / 60.0, roundi(float(row.get("heal", 0.0)))])
		print("      | %d | %s | %s | %d" % [s, " · ".join(parts), ["RED", "BLUE"][t.winner] if t.winner >= 0 else "draw",
			roundi(float(t.sim.tick) / 60.0)])
		if t.winner >= 0:
			sum["decided"] += 1
			sum["red"] += 1 if t.winner == 0 else 0
	var f := maxf(1.0, float(sum["fight"]))
	print("%d v %d summary: push %.0f%% of the track, %.2f checkpoints a round, %d of %d pushes finished, first attacker won %d of %d" % [
		size, size, 100.0 * float(sum["push"]) / maxf(1.0, float(sum["rounds"])), float(sum["cps"]) / maxf(1.0, float(sum["rounds"])),
		sum["done"], sum["rounds"], sum["red"], sum["decided"]])
	print("  at the caravan: an attacker %.0f%%, a defender %.0f%% of the fight; caravan pushed %.0f%%, contested %.0f%%, rolled back %.0f%%, nobody %.0f%%, digging %.0f%%" % [
		100.0 * sum["att"] / f, 100.0 * sum["def"] / f, 100.0 * sum["s1"] / f, 100.0 * sum["s2"] / f,
		100.0 * sum["s-1"] / f, 100.0 * sum["s0"] / f, 100.0 * sum["s3"] / f])
