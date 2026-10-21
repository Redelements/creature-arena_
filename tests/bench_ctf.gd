extends SceneTree
## Capture the Flag pacing: seeded CPU matches (Normal by default) on the CTF rules. Prints
## each match's length, how it ended, the score, and how often each play happened (takes,
## captures, fumbles, passes and their catches, interceptions, timed returns, bridge falls,
## shrines claimed), then the averages.
##   godot --headless --path . --script res://tests/bench_ctf.gd -- [--seeds=6] [--sizes=3,4] [--level=1] [--set=key:value,...]

const KINDS := ["flag_take", "capture", "flag_fumble", "flag_pass", "catch", "intercept", "flag_return",
	"timed_return", "bridge_fall", "shrine"]
const TEAMS := [["cairn", "sno", "pete", "craglash"], ["culvert", "digby", "hissy", "barkley"]]
const ROSTER := ["cairn", "sno", "pete", "craglash", "culvert", "digby", "hissy", "barkley", "gillbert", "cerebro"]


func _init() -> void:
	var seeds := 6
	var sizes := [3]
	var level := 1
	var rules := TeamSim.load_rules(TeamSim.CTF_PATH)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = int(arg.get_slice("=", 1))
		elif arg.begins_with("--sizes="):
			sizes = Array(arg.get_slice("=", 1).split(",")).map(func(x): return int(x))
		elif arg.begins_with("--level="):
			level = int(arg.get_slice("=", 1))
		elif arg.begins_with("--set="):  # try a tuning without editing the file: --set=captures_to_win:2
			for kv in arg.get_slice("=", 1).split(","):
				rules[kv.get_slice(":", 0)] = float(kv.get_slice(":", 1))
	print("CTF bench: %d seeds per size, CPU level %s" % [seeds, CpuController.LEVELS[level]["name"]])
	for size in sizes:
		_bench(int(size), seeds, level, rules)
	quit()


func _bench(size: int, seeds: int, level: int, rules: Dictionary) -> void:
	print("\n%d v %d | seed | secs | by | score | %s" % [size, size, " ".join(KINDS)])
	var total := {}
	var secs := 0.0
	for s in seeds:
		# A different line-up each seed, drawn from the roster in a fixed order.
		var teams := [[], []]
		for k in size * 2:
			teams[k % 2].append(ROSTER[(s * 3 + k) % ROSTER.size()])
		var t := TeamSim.new(teams, size, rules.duplicate(true))
		var cpus: Array = []
		for i in t.slot_count():
			cpus.append(CpuController.new(i, level, 1000 * s + i))
		var n := {}
		var by := ""
		var limit := int(float(rules.get("time_seconds", 360)) * 60) + 60 * 120
		for tick in limit:
			var ins := PackedInt32Array()
			for i in t.slot_count():
				ins.append((cpus[i] as CpuController).bits(t.sim))
			t.step(ins)
			for e in t.sim.events:
				var k := String(e["type"])
				if k == "flag_take" and bool(e.get("catch", false)):
					n["catch"] = int(n.get("catch", 0)) + 1
				if k == "flag_return" and bool(e.get("intercept", false)):
					n["intercept"] = int(n.get("intercept", 0)) + 1
				if k == "flag_return" and int(e.get("who", 0)) < 0:
					n["timed_return"] = int(n.get("timed_return", 0)) + 1
				if k == "duel_over":
					by = String(e.get("by", ""))
				n[k] = int(n.get(k, 0)) + 1
			if t.phase == TeamSim.Phase.OVER:
				break
		var sec := float(t.sim.tick) / 60.0
		secs += sec
		var row := []
		for k in KINDS:
			row.append(str(int(n.get(k, 0))))
			total[k] = int(total.get(k, 0)) + int(n.get(k, 0))
		print("      | %d | %d | %s | %d-%d | %s" % [s, roundi(sec), by if by != "" else "unfinished",
			int(t.score[0]), int(t.score[1]), " ".join(row)])
	var avg := []
	for k in KINDS:
		avg.append("%.1f" % (float(total.get(k, 0)) / float(seeds)))
	print("  avg | %d s | %s" % [roundi(secs / float(seeds)), " ".join(avg)])
