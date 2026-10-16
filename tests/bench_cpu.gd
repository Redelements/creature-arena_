extends SceneTree
## CPU tiers against each other: every fighter as one level against a field of opponents
## at another, from both sides. Prints win rates, health left and average distance.
##   godot --headless --path . --script res://tests/bench_cpu.gd -- [--a=3] [--b=2] [--seeds=2] [--only=cerebro] [--detail]
##   --matrix: every pair at level --a;  --pairs=a:b,c:d: just those, at level --a, both sides
##   --arena=ID: play on that arena map (default stadium; greenhouse and quarry test sight)

const MAX_TICKS := 5400


func _init() -> void:
	var a_lv := 3
	var b_lv := 2
	var seeds := 2
	var only := ""
	var detail := false
	var matrix := false
	var pairs := ""
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
		elif arg == "--matrix":
			matrix = true
		elif arg.begins_with("--pairs="):
			pairs = arg.get_slice("=", 1)
		elif arg.begins_with("--arena="):
			MatchFactory.arena = arg.get_slice("=", 1)
	var field: Array = MatchFactory.FIGHTERS
	if matrix:
		_matrix(field, a_lv, seeds)
		quit()
		return
	if pairs != "":
		_pairs(pairs, a_lv, seeds)
		quit()
		return
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


## Every pair at one level, both sides: a grid of win rates (row beats column) and the
## average distance, as JSON on one line (for scripts) after a readable table.
func _matrix(field: Array, lv: int, seeds: int) -> void:
	var grid := {}
	for f in field:
		grid[f] = {}
		for o in field:
			if o == f:
				continue
			var w := 0
			var n := 0
			var hp := 0.0
			var d := 0.0
			var ticks := 0
			for s in seeds:
				for side in 2:
					var r := _match(f, o, lv, lv, side, 300 + s * 17 + side)
					w += 1 if r["win"] else 0
					hp += float(r["hp"])
					d += float(r["dist"])
					ticks += int(r["ticks"])
					n += 1
			grid[f][o] = {"w": w, "n": n, "hp": hp / n, "dist": d / n, "ticks": ticks / n}
	var head := "%-9s" % ""
	for o in field:
		head += "%5s" % String(o).substr(0, 4)
	print(head)
	for f in field:
		var line := "%-9s" % f
		var tot := 0
		var tn := 0
		for o in field:
			if o == f:
				line += "    -"
				continue
			line += "%5d" % roundi(100.0 * int(grid[f][o]["w"]) / int(grid[f][o]["n"]))
			tot += int(grid[f][o]["w"])
			tn += int(grid[f][o]["n"])
		print(line + "   %3d%%" % roundi(100.0 * tot / tn))
	print("MATRIX " + JSON.stringify(grid))


## Named pairs at one level, both sides, `seeds` games a side.
func _pairs(spec: String, lv: int, seeds: int) -> void:
	for pr in spec.split(","):
		var f := pr.get_slice(":", 0)
		var o := pr.get_slice(":", 1)
		var w := 0
		var n := 0
		var hp := 0.0
		var d := 0.0
		var ticks := 0
		for s in seeds:
			for side in 2:
				var r := _match(f, o, lv, lv, side, 500 + s * 23 + side)
				w += 1 if r["win"] else 0
				hp += float(r["hp"])
				d += float(r["dist"])
				ticks += int(r["ticks"])
				n += 1
		print("%-9s vs %-9s %2d/%2d  hp %3d%%  dist %5.1f  %4.1f s" % [f, o, w, n, roundi(100.0 * hp / n), d / n,
			ticks / float(n) / 60.0])
