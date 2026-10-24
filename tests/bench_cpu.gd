extends SceneTree
## CPU tiers against each other: every fighter as one level against a field of opponents
## at another, from both sides. Prints win rates, health left and average distance.
##   godot --headless --path . --script res://tests/bench_cpu.gd -- [--a=3] [--b=2] [--seeds=2] [--only=cerebro] [--detail]
##   --matrix: every pair at level --a;  --pairs=a:b,c:d: just those, at level --a, both sides
##   --arena=ID: play on that arena map (default stadium; greenhouse and quarry test sight)
##   --detail: per foe, also the share of ticks at preferred spacing (a kiter: its kite band;
##     else ai.range ± 15%, at least ± 8 px, between body edges), ticks with stamina empty and guard breaks taken
##   --teams=3: 3v3 Rage (or --a) through TeamSim, a tank, a mage and an assassin a side: win
##     rate, length, target switches a minute per CPU, spacing share (a baseline for team AI)

const MAX_TICKS := 5400


func _init() -> void:
	var a_lv := 3
	var b_lv := 2
	var seeds := 2
	var only := ""
	var detail := false
	var matrix := false
	var pairs := ""
	var teams := 0
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
		elif arg.begins_with("--teams="):
			teams = int(arg.get_slice("=", 1))
	if teams > 0:
		_teams(teams, a_lv, seeds)
		quit()
		return
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
			var o_space := 0.0
			var o_empty := 0
			var o_breaks := 0
			for s in seeds:
				for side in 2:
					var r := _match(f, o, a_lv, b_lv, side, 100 + s * 17 + side)
					wins += 1 if r["win"] else 0
					ow += 1 if r["win"] else 0
					on += 1
					hp_left += float(r["hp"])
					dist_sum += float(r["dist"])
					ticks_sum += int(r["ticks"])
					o_space += float(r["spacing"])
					o_empty += int(r["empty"])
					o_breaks += int(r["breaks"])
					n += 1
			if detail:
				print("    vs %-9s %d/%d  at spacing %3d%%  stamina empty %4d ticks  guard breaks %d" % [o, ow, on,
					roundi(100.0 * o_space / on), o_empty / on, o_breaks])
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
	var at_spacing := 0
	var empty := 0
	var breaks := 0
	var c: CreatureSim = sim.creatures[me]
	var foe: CreatureSim = sim.creatures[1 - me]
	while ticks < MAX_TICKS:
		ticks += 1
		sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
		var d := c.pos.distance_to(foe.pos)
		dist += d
		at_spacing += 1 if _at_spacing(c, foe, d) else 0
		empty += 1 if c.stamina <= 0.0 else 0
		for e in sim.events:
			if String(e["type"]) == "guard_break" and int(e.get("who", -1)) == c.id:
				breaks += 1
		if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
			break
	var mine := sim.creatures[me].hp / sim.creatures[me].max_hp
	var theirs := sim.creatures[1 - me].hp / sim.creatures[1 - me].max_hp
	return {"win": mine > theirs, "hp": maxf(mine, 0.0), "dist": dist / ticks, "ticks": ticks,
		"spacing": at_spacing / float(ticks), "empty": empty, "breaks": breaks}


## At the CPU's preferred spacing: a kiter (a ranged light, or ai.kite) inside the band its
## kite plan holds (CpuController.kite_band); anyone else with the gap between bodies within
## ai.range ± 15% (± 8 px at least).
static func _at_spacing(c: CreatureSim, foe: CreatureSim, d: float) -> bool:
	if c.moves().get("light_1", {}).has("projectile") or bool(c.def.get("ai", {}).get("kite", false)):
		var band := CpuController.kite_band(c, foe)
		return d >= band.x - 4.0 and d <= band.y + 4.0
	var want := float(c.def.get("ai", {}).get("range", 22))
	return absf(d - c.radius - foe.radius - want) <= maxf(want * 0.15, 8.0)


## 3v3 (or `size` a side) at level `lv`: a tank, a mage and an assassin a side, the two picks of
## each class swapped between sides each seed, both sides played. Target switches count each
## CPU's `_target` changing to another living foe.
func _teams(size: int, lv: int, seeds: int) -> void:
	var picks := [["craglash", "culvert"], ["crease", "cerebro"], ["pete", "digby"]]
	var w := 0
	var n := 0
	var ticks_sum := 0
	var switches := 0
	var space := 0.0
	for s in seeds:
		for side in 2:
			var t_ids := [[], []]
			for k in mini(size, picks.size()):
				t_ids[side].append(picks[k][s % 2])
				t_ids[1 - side].append(picks[k][(s + 1) % 2])
			var t := TeamSim.new(t_ids, size)
			var cpus: Array = []
			for i in t.slot_count():
				cpus.append(CpuController.new(i, lv, 700 + s * 31 + side * 7 + i))
			var last := {}
			var ticks := 0
			var at := 0
			var samples := 0
			while t.phase != TeamSim.Phase.OVER and ticks < MAX_TICKS:
				var ins := PackedInt32Array()
				for i in t.slot_count():
					ins.append((cpus[i] as CpuController).bits(t.sim))
				t.step(ins)
				ticks += 1
				for i in t.slot_count():
					var cpu: CpuController = cpus[i]
					var me: CreatureSim = t.sim.creatures[i]
					if cpu._target == null or me.state == CreatureSim.State.KO:
						continue
					if last.has(i) and last[i] != cpu._target and last[i].state != CreatureSim.State.KO:
						switches += 1
					last[i] = cpu._target
					samples += 1
					at += 1 if _at_spacing(me, cpu._target, me.pos.distance_to(cpu._target.pos)) else 0
			w += 1 if t.winner == side else 0
			n += 1
			ticks_sum += ticks
			space += at / maxf(1.0, samples)
			print("  seed %d side %d: %s vs %s  winner %d  %4.1f s" % [s, side, t_ids[side], t_ids[1 - side],
				t.winner, ticks / 60.0])
	var minutes := ticks_sum / 3600.0
	print("TEAMS %dv%d %s: first picks won %d/%d  avg %4.1f s  target switches %4.1f /min/CPU  at spacing %3d%%" % [
		size, size, CpuController.LEVELS[lv]["name"], w, n, ticks_sum / float(n) / 60.0,
		switches / maxf(0.01, minutes) / (size * 2), roundi(100.0 * space / n)])


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
