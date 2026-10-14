extends SceneTree
## How far apart fighters fight: CPU against CPU, each fighter against the field, from
## both sides. "Gap" is the space between the two body circles (centre distance minus
## both radii), so 0 is touching. Prints, per fighter: the average gap when its light
## hits land, the share of fighting time spent touching (gap under 4 px), and the
## average gap overall.
##   godot --headless --path . --script res://tests/bench_spacing.gd -- [--lv=3] [--seeds=1] [--only=hissy]

const MAX_TICKS := 5400
const TOUCH := 4.0


func _init() -> void:
	var lv := 3
	var seeds := 1
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lv="):
			lv = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seeds="):
			seeds = int(arg.get_slice("=", 1))
		elif arg.begins_with("--only="):
			only = arg.get_slice("=", 1)
	var field: Array = MatchFactory.FIGHTERS
	var all_light := 0.0
	var all_light_n := 0
	var all_touch := 0
	var all_ticks := 0
	print("%-9s %10s %8s %8s" % ["fighter", "light gap", "touching", "avg gap"])
	for f in field:
		if only != "" and f != only:
			continue
		var light_sum := 0.0
		var light_n := 0
		var touch := 0
		var gap_sum := 0.0
		var ticks := 0
		for o in field:
			for s in seeds:
				for side in 2:
					var r := _match(f, o, lv, side, 500 + s * 17 + side)
					light_sum += float(r["light_sum"])
					light_n += int(r["light_n"])
					touch += int(r["touch"])
					gap_sum += float(r["gap_sum"])
					ticks += int(r["ticks"])
		all_light += light_sum
		all_light_n += light_n
		all_touch += touch
		all_ticks += ticks
		print("%-9s %10.1f %7d%% %8.1f" % [f, light_sum / maxf(1, light_n),
			roundi(100.0 * touch / maxf(1, ticks)), gap_sum / maxf(1, ticks)])
	print("ALL       %10.1f %7d%%" % [all_light / maxf(1, all_light_n), roundi(100.0 * all_touch / maxf(1, all_ticks))])
	quit()


func _match(f: String, o: String, lv: int, side: int, seed_: int) -> Dictionary:
	var sim := MatchFactory.versus(f, o) if side == 0 else MatchFactory.versus(o, f)
	var me := side
	var cpus := [CpuController.new(0, lv, seed_ * 7 + 1), CpuController.new(1, lv, seed_ * 13 + 5)]
	var r := {"light_sum": 0.0, "light_n": 0, "touch": 0, "gap_sum": 0.0, "ticks": 0}
	var t := 0
	while t < MAX_TICKS:
		t += 1
		sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
		var a: CreatureSim = sim.creatures[0]
		var b: CreatureSim = sim.creatures[1]
		var gap := a.pos.distance_to(b.pos) - a.radius - b.radius
		for e in sim.events:
			if String(e["type"]) == "hit" and int(e["attacker"]) == me and String(e.get("type", "")) == "hit" \
					and String(sim.creatures[me].moves().get(sim.creatures[me].move_id, {}).get("type", "")) == "light":
				r["light_sum"] += gap
				r["light_n"] += 1
		# Fighting time only: both on their feet.
		if a.state != CreatureSim.State.KNOCKDOWN and b.state != CreatureSim.State.KNOCKDOWN:
			r["ticks"] += 1
			r["gap_sum"] += gap
			if gap < TOUCH:
				r["touch"] += 1
		if a.state == CreatureSim.State.KO or b.state == CreatureSim.State.KO:
			break
	return r
