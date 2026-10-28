extends SceneTree
## Why a fighter wins or loses: seeded CPU matches of one fighter against a field, counting
## each move it throws, lands and has blocked, damage dealt and taken, hits taken mid-move,
## pit falls, time spent guarding and the moves that hit it most. Not a test.
##   godot --headless --path . --script res://tests/bench_fighter.gd -- --fighter=sno
##   [--foes=cairn,hissy] (default: the whole roster) [--seeds=2] [--a=3] [--b=3]
## --a is the fighter's CPU level, --b the opponents' (default 1, Normal; 3 = Rage). It plays the left side.
##   [--arena=twin_keeps] (the map) [--mutators=pit_floor,...] (data/rules/mutators.json ids or key:value)
## Also counted: the share of its time on its feet with no walk to the foe (another region of
## the CPU's nav grid: a chasm or a wall between), and pits crossed in the air (a leap or
## Burrow over a pit).

const TICKS := 7200


func _init() -> void:
	var me_id := "barkley"
	var foes: Array = []
	var seeds := 2
	var lv_a := 1  # Normal CPUs (Kevin, Oct 2026: no Rage benches)
	var lv_b := 1
	var arena := ""
	var muts := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fighter="):
			me_id = arg.get_slice("=", 1)
		elif arg.begins_with("--foes="):
			foes = Array(arg.get_slice("=", 1).split(","))
		elif arg.begins_with("--seeds="):
			seeds = int(arg.get_slice("=", 1))
		elif arg.begins_with("--a="):
			lv_a = int(arg.get_slice("=", 1))
		elif arg.begins_with("--b="):
			lv_b = int(arg.get_slice("=", 1))
		elif arg.begins_with("--arena="):
			arena = arg.get_slice("=", 1)
		elif arg.begins_with("--mutators="):
			var all := BrawlSim.load_rules("res://data/rules/mutators.json")
			for m in arg.get_slice("=", 1).split(",", false):
				if m.contains(":"):
					muts[m.get_slice(":", 0)] = float(m.get_slice(":", 1))
				elif all.has(m):
					MatchSim.merge_mutator(muts, all[m])
	if foes.is_empty():
		foes = MatchFactory.FIGHTERS.filter(func(f): return f != me_id)

	var started := {}
	var landed := {}
	var blocked := {}
	var hit_by := {}
	var dealt := 0.0
	var taken := 0.0
	var hit_mid_move := 0
	var hit_otherwise := 0
	var falls := 0
	var guard_ticks := 0
	var cut_ticks := 0
	var feet_ticks := 0
	var crossed := 0
	var ticks := 0
	var wins := 0
	var games := 0
	for foe in foes:
		for s in seeds:
			var sim := MatchFactory.versus(me_id, String(foe), arena)
			if not muts.is_empty():
				sim.apply_mutators(muts, s)
			var over_pit := false
			var cpus := [CpuController.new(0, lv_a, s * 7 + 1), CpuController.new(1, lv_b, s * 13 + 5)]
			var me := sim.creatures[0]
			var them := sim.creatures[1]
			var last_serial := -1
			games += 1
			for t in TICKS:
				sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
				ticks += 1
				if me.state == CreatureSim.State.GUARD:
					guard_ticks += 1
				if me.state in [CreatureSim.State.IDLE, CreatureSim.State.MOVE, CreatureSim.State.GUARD] and them.state != CreatureSim.State.KO:
					feet_ticks += 1
					var nav := NavGrid.shared(sim.terrain)
					if nav.region_of(me.pos) != nav.region_of(them.pos):
						cut_ticks += 1
				var now_over := me.is_leaping() and sim.terrain.is_hole_at(me.pos)
				if now_over and not over_pit:
					crossed += 1
				over_pit = now_over
				if me.state == CreatureSim.State.ATTACK and me.attack_serial != last_serial:
					last_serial = me.attack_serial
					started[me.move_id] = int(started.get(me.move_id, 0)) + 1
				for e in sim.events:
					var ty := String(e["type"])
					if ty in ["hit", "hook", "grab", "swallow"] and int(e.get("attacker", -1)) == me.id:
						landed[me.move_id] = int(landed.get(me.move_id, 0)) + 1
						dealt += float(e["power"])
					elif ty == "block" and int(e.get("attacker", -1)) == me.id:
						blocked[me.move_id] = int(blocked.get(me.move_id, 0)) + 1
					elif ty == "hit" and int(e.get("target", -1)) == me.id:
						taken += float(e["power"])
						var k := "%s %s" % [foe, them.move_id]
						hit_by[k] = int(hit_by.get(k, 0)) + 1
						if me.state == CreatureSim.State.ATTACK:
							hit_mid_move += 1
						else:
							hit_otherwise += 1
					elif ty == "fall" and int(e.get("who", -1)) == me.id:
						falls += 1
				if me.state == CreatureSim.State.KO or them.state == CreatureSim.State.KO:
					if them.state == CreatureSim.State.KO:
						wins += 1
					break

	print("%s (level %d) vs %s (level %d): won %d of %d" % [me_id, lv_a, ", ".join(foes), lv_b, wins, games])
	print("move        thrown  landed  blocked")
	var moves := started.keys()
	moves.sort()
	for m in moves:
		print("%-10s  %6d  %6d  %7d" % [m, int(started[m]), int(landed.get(m, 0)), int(blocked.get(m, 0))])
	print("dealt %.0f, taken %.0f (%.1fx)" % [dealt, taken, taken / maxf(1.0, dealt)])
	print("hit mid-move %d, otherwise %d; pit falls %d; guarding %.0f%% of the time" % [
		hit_mid_move, hit_otherwise, falls, 100.0 * guard_ticks / maxf(1.0, ticks)])
	print("arena %s %s: no walk to the foe %.1f%% of the time on its feet; pits crossed in the air %d" % [
		arena if arena != "" else MatchFactory.arena, muts if not muts.is_empty() else "",
		100.0 * cut_ticks / maxf(1.0, feet_ticks), crossed])
	var top := hit_by.keys()
	top.sort_custom(func(a, b): return int(hit_by[a]) > int(hit_by[b]))
	print("hit most by: ", ", ".join(top.slice(0, 6).map(func(k): return "%s (%d)" % [k, hit_by[k]])))
	quit()
