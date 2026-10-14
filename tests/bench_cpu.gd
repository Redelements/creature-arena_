extends SceneTree
## CPU tiers against each other: every fighter as one level against a field of opponents
## at another, from both sides. Prints win rates, health left and average distance.
##   godot --headless --path . --script res://tests/bench_cpu.gd -- [--a=3] [--b=2] [--seeds=2] [--only=cerebro] [--detail]

const MAX_TICKS := 5400


func _init() -> void:
	var a_lv := 3
	var b_lv := 2
	var seeds := 2
	var only := ""
	var detail := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--a="):
			a_lv = int(arg.get_slice("=", 1))
		elif arg.begins_with("--b="):
			b_lv = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seeds="):
			seeds = int(arg.get_slice("=", 1))
		elif arg.begins_with("--only="):
			only = arg.get_slice("=", 1)
		elif arg == "--detail":
			detail = true
	var field: Array = MatchFactory.FIGHTERS
	var total_w := 0
	var total_n := 0
	for f in field:
		if only != "" and f != only:
			continue
		var wins := 0
		var n := 0
		var hp_left := 0.0
		var dist_sum := 0.0
		var ticks_sum := 0
		for o in field:
			var ow := 0
			var on := 0
			for s in seeds:
				for side in 2:
					var r := _match(f, o, a_lv, b_lv, side, 100 + s * 17 + side)
					wins += 1 if r["win"] else 0
					ow += 1 if r["win"] else 0
					on += 1
					hp_left += float(r["hp"])
					dist_sum += float(r["dist"])
					ticks_sum += int(r["ticks"])
					n += 1
			if detail:
				print("    vs %-9s %d/%d" % [o, ow, on])
		total_w += wins
		total_n += n
		print("%-9s %s vs %s: won %2d/%2d  hp left %3d%%  avg dist %5.1f  avg %4.1f s" % [f,
			CpuController.LEVELS[a_lv]["name"], CpuController.LEVELS[b_lv]["name"], wins, n,
			roundi(hp_left / n * 100.0), dist_sum / n, ticks_sum / float(n) / 60.0])
	print("TOTAL won %d/%d (%d%%)" % [total_w, total_n, roundi(100.0 * total_w / maxf(1, total_n))])
	quit()


func _match(f: String, o: String, a_lv: int, b_lv: int, side: int, seed_: int) -> Dictionary:
	var sim := MatchFactory.versus(f, o) if side == 0 else MatchFactory.versus(o, f)
	var me := side
	var cpus := [null, null]
	cpus[me] = CpuController.new(me, a_lv, seed_ * 7 + 1)
	cpus[1 - me] = CpuController.new(1 - me, b_lv, seed_ * 13 + 5)
	var dist := 0.0
	var ticks := 0
	while ticks < MAX_TICKS:
		ticks += 1
		sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
		dist += sim.creatures[0].pos.distance_to(sim.creatures[1].pos)
		if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
			break
	var mine := sim.creatures[me].hp / sim.creatures[me].max_hp
	var theirs := sim.creatures[1 - me].hp / sim.creatures[1 - me].max_hp
	return {"win": mine > theirs, "hp": maxf(mine, 0.0), "dist": dist / ticks, "ticks": ticks}
