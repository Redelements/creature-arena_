extends SceneTree
## CPU tiers against each other: every fighter as one level against a field of opponents
## at another, from both sides. Prints win rates, health left and average distance.
##   godot --headless --path . --script res://tests/bench_cpu.gd -- [--a=1] [--b=1] [--seeds=2] [--only=cerebro] [--detail]
##   --matrix: every pair at level --a;  --pairs=a:b,c:d: just those, at level --a, both sides
##   --arena=ID: play on that arena map (default stadium; greenhouse and quarry test sight)
##   --detail: per foe, also the share of ticks at preferred spacing (a kiter: its kite band;
##     else ai.range ± 15%, at least ± 8 px, between body edges), ticks with stamina empty and guard breaks taken
##   --scored: the fighter under test plays the scored kit (CpuController.scored, the default)
##     and its foes the old ladder; with --a=3 --b=3 that is scored Rage against ladder Rage.
##     --ladder: everyone plays the ladder (the baseline to compare with)
##   --teams=3: 3v3 Normal (or --a) through TeamSim, a tank, a mage and an assassin a side: win
##     rate, length, target switches a minute per CPU, spacing share, focus switches a minute
##     per team (a baseline for team AI)
##     --intent=a: only the first-picks side plays to a team focus (TeamIntent), the other side
##     picks targets alone; --intent=off: nobody does (the old baseline)
##   --slot=<role>: the slot bench, team win rate per fighter in a 3v3 (Normal or --a): every
##     fighter (or --only=<id>) fills the <role> slot (tank, mage or assassin) of the reference
##     team culvert / cerebro / pete; its two teammates and the three foes (that reference team)
##     are fixed Normal CPUs. Both sides, --seeds games a side; a draw or a timeout counts half.
##     The reference pick itself is a mirror (about 50%), so 50% means "as good as the reference
##     in that slot". Team rules from data/rules/team.json (150 s, last team standing).
##   --matrix --only=<id>: play just that fighter's row (the same seeds as the full matrix)
##   --combat: how each fighter deals its damage, Normal (or --a) against Normal, every pair of the
##     roster from both sides (--seeds games a side, --only=<id> for its pairs): the share of
##     damage from light / heavy / skill / surge hits (clean, chip and on armor; from the
##     `move_type` and `dealt` of `hit`, `block` and `armor` events) and other (whatever else
##     the foe lost: poison, falls, walls, hazards), the average combo length in hits, the
##     average distinct move types per combo, the share of combos with 2+ types, Surges thrown a
##     minute and damage a minute. A combo is the sim's: the hits landed on the foe while its
##     `combo_hits` counts up; it ends when that resets (the foe recovers, or a hit restarts it
##     at 1). The baseline is in docs/plans/combat-metrics.md.

const MAX_TICKS := 7200  ## a 1v1 round (120 s)

var _scored_a := false  ## --scored: the fighter under test (side A) scored, the foe the old ladder
var _ladder := false  ## --ladder: everyone plays the old ladder kit (a baseline)
var _intent := "on"  ## --intent=on|a|off: who plays to the team focus in --teams


func _init() -> void:
	var a_lv := 1  # Normal: balance is measured with Normal CPUs, never Rage (Kevin, Oct 2026)
	var b_lv := 1
	var seeds := 2
	var only := ""
	var detail := false
	var matrix := false
	var pairs := ""
	var teams := 0
	var combat := false
	var slot := ""
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
		elif arg == "--scored":
			_scored_a = true
		elif arg == "--ladder":
			_ladder = true
		elif arg.begins_with("--teams="):
			teams = int(arg.get_slice("=", 1))
		elif arg.begins_with("--intent="):
			_intent = arg.get_slice("=", 1)
		elif arg == "--combat":
			combat = true
		elif arg.begins_with("--slot="):
			slot = arg.get_slice("=", 1)
	if combat:
		_combat(MatchFactory.FIGHTERS, a_lv, seeds, only)
		quit()
		return
	if slot != "":
		_slot(slot, a_lv, seeds, only)
		quit()
		return
	if teams > 0:
		_teams(teams, a_lv, seeds)
		quit()
		return
	var field: Array = MatchFactory.FIGHTERS
	if matrix:
		_matrix(field, a_lv, seeds, only)
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
	if _scored_a or _ladder:
		cpus[me].scored = _scored_a
		cpus[1 - me].scored = false
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
	var focus_switches := 0
	var on_focus := 0  ## CPU-ticks spent on the team's focus, of those playing to one
	var on_focus_n := 0
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
				var cpu := CpuController.new(i, lv, 700 + s * 31 + side * 7 + i)
				cpu.intent = _intent == "on" or (_intent == "a" and t.side_of(i) == side)
				cpus.append(cpu)
			var last := {}
			var last_focus := {}
			var ticks := 0
			var at := 0
			var samples := 0
			while t.phase != TeamSim.Phase.OVER and ticks < MAX_TICKS:
				var ins := PackedInt32Array()
				for i in t.slot_count():
					ins.append((cpus[i] as CpuController).bits(t.sim))
				for team in 2:
					var ti := TeamIntent.current(t.sim, team)
					# (a team of one plays its own pick: its focus is counted no more)
					if ti != null and ti.focus >= 0 and t.alive_count(team) >= 2:
						if last_focus.has(team) and last_focus[team] != ti.focus \
								and t.sim.creatures[last_focus[team]].state != CreatureSim.State.KO:
							focus_switches += 1
						last_focus[team] = ti.focus
						for i in t.slot_count():
							var cpu: CpuController = cpus[i]
							if cpu.intent and t.side_of(i) == team and t.sim.creatures[i].state != CreatureSim.State.KO:
								on_focus_n += 1
								on_focus += 1 if cpu._target == t.sim.creatures[ti.focus] else 0
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
	print("TEAMS %dv%d %s (intent %s): first picks won %d/%d  avg %4.1f s  target switches %4.1f /min/CPU  focus switches %4.1f /min/team  on focus %3d%%  at spacing %3d%%" % [
		size, size, CpuController.LEVELS[lv]["name"], _intent, w, n, ticks_sum / float(n) / 60.0,
		switches / maxf(0.01, minutes) / (size * 2), focus_switches / maxf(0.01, minutes) / 2.0,
		roundi(100.0 * on_focus / maxf(1.0, on_focus_n)), roundi(100.0 * space / n)])


## The reference team for --slot: a tank, a mage and an assassin, in slot order.
const SLOT_REF := {"tank": "culvert", "mage": "cerebro", "assassin": "pete"}


## --slot=<role>: each fighter (or `only`) takes the `role` slot of the reference team against
## the reference team, everyone else fixed CPUs at level `lv`, both sides, `seeds` games a side.
func _slot(role: String, lv: int, seeds: int, only: String) -> void:
	if not SLOT_REF.has(role):
		print("--slot: role must be one of %s" % [SLOT_REF.keys()])
		return
	var ref: Array = SLOT_REF.values()
	var k: int = SLOT_REF.keys().find(role)
	var rows := []
	for f in MatchFactory.FIGHTERS:
		if only != "" and f != only:
			continue
		var mine := ref.duplicate()
		mine[k] = f
		var score := 0.0
		var w := 0
		var d := 0
		var n := 0
		var ticks_sum := 0
		for s in seeds:
			for side in 2:
				var t_ids := [[], []]
				t_ids[side] = mine
				t_ids[1 - side] = ref
				var t := TeamSim.new(t_ids, 3)
				var cpus: Array = []
				for i in t.slot_count():
					cpus.append(CpuController.new(i, lv, 1100 + s * 37 + side * 11 + i))
				var ticks := 0
				while t.phase != TeamSim.Phase.OVER and ticks < 12000:
					var ins := PackedInt32Array()
					for i in t.slot_count():
						ins.append((cpus[i] as CpuController).bits(t.sim))
					t.step(ins)
					ticks += 1
				if t.winner == side:
					w += 1
					score += 1.0
				elif t.winner < 0:
					d += 1
					score += 0.5
				n += 1
				ticks_sum += ticks
		rows.append({"fighter": f, "score": score / n, "w": w, "d": d, "n": n, "secs": ticks_sum / float(n) / 60.0})
		print("%-9s in the %s slot of %s vs %s: won %2d drew %d of %2d  %3d%%  avg %5.1f s" % [f, role, mine, ref,
			w, d, n, roundi(100.0 * score / n), ticks_sum / float(n) / 60.0])
	rows.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]))
	print("SLOT %s %s: %s" % [role, CpuController.LEVELS[lv]["name"],
		", ".join(rows.map(func(r): return "%s %d%%" % [r["fighter"], roundi(100.0 * float(r["score"]))]))])


## Every pair at one level, both sides: a grid of win rates (row beats column) and the
## average distance, as JSON on one line (for scripts) after a readable table.
func _matrix(field: Array, lv: int, seeds: int, only := "") -> void:
	var grid := {}
	var rows: Array = field if only == "" else [only]
	for f in rows:
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
	for f in rows:
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


const COMBAT_TYPES := ["light", "heavy", "skill", "surge"]


## --combat: every pair of `field` at level `lv`, both sides, `seeds` games a side; each match
## adds to both fighters' tallies (see the header for the columns).
func _combat(field: Array, lv: int, seeds: int, only: String) -> void:
	var tally := {}
	for f in field:
		tally[f] = {"dmg": {"light": 0.0, "heavy": 0.0, "skill": 0.0, "surge": 0.0, "other": 0.0},
			"combos": 0, "hits": 0, "types": 0, "mixed": 0, "surges": 0, "ticks": 0}
	for i in field.size():
		for j in range(i + 1, field.size()):
			var f: String = field[i]
			var o: String = field[j]
			if only != "" and f != only and o != only:
				continue
			for s in seeds:
				for side in 2:
					var ids := [f, o] if side == 0 else [o, f]
					_combat_match(ids, lv, 900 + s * 17 + side, [tally[ids[0]], tally[ids[1]]])
	print("%-9s %6s %6s %6s %6s %6s  %5s %5s %5s  %7s %6s" % ["fighter", "light", "heavy", "skill", "surge",
		"other", "combo", "types", "2+", "surge/m", "dmg/m"])
	var rows := []
	for f in field:
		var t: Dictionary = tally[f]
		if int(t["ticks"]) == 0 or (only != "" and f != only):
			continue
		var total := 0.0
		for k in t["dmg"]:
			total += float(t["dmg"][k])
		var minutes := int(t["ticks"]) / 3600.0
		var combos := maxi(1, int(t["combos"]))
		var line := "%-9s" % f
		var row := {"fighter": f}
		for k in COMBAT_TYPES + ["other"]:
			var share := float(t["dmg"][k]) / maxf(0.001, total)
			line += " %5d%%" % roundi(100.0 * share)
			row[k] = snappedf(share, 0.001)
		row["combo"] = snappedf(float(t["hits"]) / combos, 0.01)
		row["types"] = snappedf(float(t["types"]) / combos, 0.01)
		row["mixed"] = snappedf(float(t["mixed"]) / combos, 0.001)
		row["surge_min"] = snappedf(int(t["surges"]) / minutes, 0.01)
		row["dmg_min"] = snappedf(total / minutes, 0.1)
		line += "  %5.2f %5.2f %4d%%  %7.2f %6.1f" % [row["combo"], row["types"], roundi(100.0 * float(row["mixed"])),
			row["surge_min"], row["dmg_min"]]
		print(line)
		rows.append(row)
	print("COMBAT " + JSON.stringify(rows))


## One match for --combat at level `lv`, adding to `tallies` (one per side).
func _combat_match(ids: Array, lv: int, seed_: int, tallies: Array) -> void:
	var sim := MatchFactory.versus(ids[0], ids[1])
	var cpus := [CpuController.new(0, lv, seed_ * 7 + 1), CpuController.new(1, lv, seed_ * 13 + 5)]
	var open := [null, null]  ## each side's combo on its foe: {hits, types} or null
	var ticks := 0
	while ticks < MAX_TICKS:
		ticks += 1
		var hp_before := [sim.creatures[0].hp, sim.creatures[1].hp]
		sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
		var typed := [0.0, 0.0]  ## damage each side's hits dealt this tick
		for e in sim.events:
			var kind := String(e["type"])
			if kind == "surge":
				var who := int(e.get("who", -1))
				if who == 0 or who == 1:
					tallies[who]["surges"] += 1
				continue
			if kind != "hit" and kind != "block" and kind != "armor":
				continue
			var a := int(e.get("attacker", -1))
			if (a != 0 and a != 1) or int(e.get("target", -1)) != 1 - a:
				continue
			var mt := String(e.get("move_type", ""))
			var dealt := float(e.get("dealt", e["power"]))
			if mt in COMBAT_TYPES:
				tallies[a]["dmg"][mt] += dealt
				typed[a] += dealt
			if kind == "hit":
				if int(e["combo"]) == 1 or open[a] == null:
					_close_combo(tallies[a], open[a])
					open[a] = {"hits": 0, "types": {}}
				open[a]["hits"] += 1
				open[a]["types"][mt] = true
		for side in 2:
			var foe: CreatureSim = sim.creatures[1 - side]
			var lost := float(hp_before[1 - side]) - foe.hp
			tallies[side]["dmg"]["other"] += maxf(0.0, lost - typed[side])
			if foe.combo_hits == 0 and open[side] != null:
				_close_combo(tallies[side], open[side])
				open[side] = null
		if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
			break
	for side in 2:
		_close_combo(tallies[side], open[side])
		tallies[side]["ticks"] += ticks


static func _close_combo(t: Dictionary, c) -> void:
	if c == null:
		return
	t["combos"] += 1
	t["hits"] += int(c["hits"])
	t["types"] += c["types"].size()
	t["mixed"] += 1 if c["types"].size() >= 2 else 0
