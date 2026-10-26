extends SceneTree
## Sinkhole pacing: seeded Normal CPU matches (1v1, 2v2, 3v3) on the Sinkhole rules. Prints,
## per ring, the tick it dropped (average over the matches that got that far) and the
## floor left (in cells), then how the fighters went down (a fall into a pit or damage),
## how the matches ended and how long they ran.
##   godot --headless --path . --script res://tests/bench_sinkhole.gd -- [--seeds=6] [--sizes=1,2,3] [--level=1]

const MAX_TICKS := 15000


func _init() -> void:
	var seeds := 6
	var sizes := [1, 2, 3]
	var level := 1  # Normal CPUs (Kevin, Oct 2026: no Rage benches)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = int(arg.get_slice("=", 1))
		elif arg.begins_with("--sizes="):
			sizes = Array(arg.get_slice("=", 1).split(",")).map(func(x): return int(x))
		elif arg.begins_with("--level="):
			level = int(arg.get_slice("=", 1))
	var rules := TeamSim.load_rules(TeamSim.SINKHOLE_PATH)
	print("Sinkhole bench: %d seeds per size, CPU level %s, shrink_every %s, shrink_warn %s" % [seeds,
		CpuController.LEVELS[level]["name"], rules.get("shrink_every"), rules.get("shrink_warn")])
	_schedule(rules)
	for size in sizes:
		_bench(int(size), seeds, level, rules)
	quit()


## The planned collapse, whatever the fighters do: when each ring drops (ko freezes
## aside) and the floor it leaves.
func _schedule(rules: Dictionary) -> void:
	var t := TeamSim.new([["cairn"], ["culvert"]], 1, rules.duplicate(true))
	var every := int(rules.get("shrink_every", 420))
	var warn := int(rules.get("shrink_warn", 120))
	var intro := int(rules.get("intro_ticks", 100))
	print("
schedule | ring | drops at | floor left (cells)")
	for r in int(rules.get("max_rings", 16)):
		if t.ring_rect(r) == t.ring_rect(r - 1):
			break
		var rc := t.ring_rect(r)
		print("         | %4d | %6.1f s | %d x %d" % [r, (intro + (r + 1) * (every + warn)) / 60.0, rc.size.x, rc.size.y])


func _bench(size: int, seeds: int, level: int, rules: Dictionary) -> void:
	var drop_ticks := {}  # ring -> [ticks]
	var drop_rect := {}  # ring -> the floor left, in cells
	var ends := {}
	var downs := {}
	var hole_falls := 0
	var length := 0
	for s in seeds:
		var r := _match(size, s, level, rules)
		length += int(r["ticks"])
		ends[r["by"]] = int(ends.get(r["by"], 0)) + 1
		for k in r["downs"]:
			downs[k] = int(downs.get(k, 0)) + int(r["downs"][k])
		hole_falls += int(r["hole_falls"])
		for d in r["drops"]:
			var ring := int(d[0])
			if not drop_ticks.has(ring):
				drop_ticks[ring] = []
			(drop_ticks[ring] as Array).append(int(d[1]))
			drop_rect[ring] = d[2]
	print("\n== %dv%d, %d matches: avg length %.1f s; ended by %s; knockouts %s; falls that weren't KOs %d" % [
		size, size, seeds, length / float(seeds) / 60.0, ends, downs, hole_falls])
	print("ring | dropped at (avg s, matches) | floor left (cells)")
	var rings := drop_ticks.keys()
	rings.sort()
	for ring in rings:
		var t: Array = drop_ticks[ring]
		var sum := 0
		for x in t:
			sum += int(x)
		var rc: Rect2i = drop_rect[ring]
		print("%4d | %6.1f s (%d) | %d x %d" % [ring, sum / float(t.size()) / 60.0, t.size(), rc.size.x, rc.size.y])


func _match(size: int, s: int, level: int, rules: Dictionary) -> Dictionary:
	var field: Array = MatchFactory.FIGHTERS
	var teams := [[], []]
	for k in 3:
		teams[0].append(field[(s * 3 + k) % field.size()])
		teams[1].append(field[(s * 3 + k + 5) % field.size()])
	var t := TeamSim.new(teams, size, rules.duplicate(true))
	var cpus: Array = []
	for i in t.slot_count():
		cpus.append(CpuController.new(i, level, 1000 + s * 31 + i))
	var drops: Array = []
	var downs := {}
	var hole_falls := 0
	var fell_at := {}  # who -> [tick, pit kind]
	var ticks := 0
	while t.phase != TeamSim.Phase.OVER and ticks < MAX_TICKS:
		var ins := PackedInt32Array()
		for i in t.slot_count():
			ins.append((cpus[i] as CpuController).bits(t.sim))
		t.step(ins)
		ticks += 1
		for e in t.sim.events:
			match String(e["type"]):
				"sink":
					var rect: Rect2 = e["rect"]
					var cells := Rect2i(Vector2i(rect.position / SimDefs.CELL), Vector2i(rect.size / SimDefs.CELL))
					drops.append([int(e["ring"]), ticks, cells])
				"fall":
					fell_at[int(e["who"])] = [ticks, String(e.get("pit", "pit"))]
				"land":
					pass
				"ko":
					var who := int(e["who"])
					var how := "damage"
					if fell_at.has(who) and ticks - int(fell_at[who][0]) <= CreatureSim.FALL_TICKS + 2:
						how = "fall into " + String(fell_at[who][1])
					downs[how] = int(downs.get(how, 0)) + 1
		for who in fell_at.keys():
			# A fall that ended standing up: hurt, not out.
			var c: CreatureSim = t.sim.creatures[int(who)]
			if c.state != CreatureSim.State.FALLING and c.state != CreatureSim.State.KO \
					and ticks - int(fell_at[who][0]) <= CreatureSim.FALL_TICKS + 2:
				hole_falls += 1
				fell_at.erase(who)
	var by := "unfinished"
	for e in t.sim.events:
		if String(e["type"]) == "duel_over":
			by = String(e.get("by", "?"))
	if t.phase == TeamSim.Phase.OVER and by == "unfinished":
		by = "ko" if t.timer > 0 else "time"
	return {"ticks": ticks, "by": by, "drops": drops, "downs": downs, "hole_falls": hole_falls}
