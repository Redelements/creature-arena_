extends SceneTree
## Mode pacing, the same yardstick for every mode: seeded Rage CPU matches of each mode,
## and per mode how long a match runs, how much of it nobody lands a hit (stalemates),
## how many separate fights break out a minute, how often the side behind at half time
## comes back to win, captures (CTF), the shrines claimed (and how often the claiming side
## won), and with the Crater's permanent shrine buffs how often the side with more won.
## Definitions in docs/plans/mode-metrics.md.
##   godot --headless --path . --script res://tests/bench_modes.gd -- [--seeds=6] [--seed0=0] [--level=3]
##     [--modes=team2,team3,tdm2,tdm3,crater2,sinkhole2,brawl3,brawl4,caravan3,ctf3]
##     [--shrines=data|on|off] [--shrine-set=first_seconds:15,...] [--rows]
## --shrines=on turns shrines on in a mode whose rules leave them out (with the shared
## defaults, data/rules/shrines.json, and the haste/might cycle); off takes them out of
## any mode (Capture the Flag too); --shrine-set tries a shrine tuning (numbers) in every
## mode that has them. --rows prints every match.

## A hit after this many ticks of quiet starts a new fight; this many ticks without a hit
## landed is a stalemate tick.
const QUIET := 180
## Standings are sampled this often (ticks) for the half-time leader.
const SAMPLE := 30
var _shrine_set := {}
var _seed0 := 0  ## the first seed (--seed0: more matches on top of an earlier run)
const ROSTER := ["cairn", "sno", "pete", "craglash", "culvert", "digby", "hissy", "barkley", "gillbert", "cerebro"]
## id: [kind, rules id, fighters a side (team) or players (brawl), name]
const MODES := {
	"team2": ["team", "", 2, "Team battle 2v2"],
	"team3": ["team", "", 3, "Team battle 3v3"],
	"tdm2": ["team", "deathmatch", 2, "Team Deathmatch 2v2"],
	"tdm3": ["team", "deathmatch", 3, "Team Deathmatch 3v3"],
	"crater2": ["team", "crater", 2, "King of the Crater 2v2"],
	"sinkhole2": ["team", "sinkhole", 2, "Sinkhole 2v2"],
	"brawl3": ["brawl", "", 3, "Brawl (3)"],
	"brawl4": ["brawl", "", 4, "Brawl (4)"],
	"caravan3": ["team", "caravan", 3, "Caravan 3v3"],
	"ctf3": ["team", "ctf", 3, "Capture the Flag 3v3"],
}


func _init() -> void:
	var seeds := 6
	var level := 3
	var modes: Array = MODES.keys()
	var shrines := "data"
	var rows := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seed0="):
			_seed0 = int(arg.get_slice("=", 1))
		elif arg.begins_with("--level="):
			level = int(arg.get_slice("=", 1))
		elif arg.begins_with("--modes="):
			modes = Array(arg.get_slice("=", 1).split(",", false))
		elif arg.begins_with("--shrines="):
			shrines = arg.get_slice("=", 1)
		elif arg.begins_with("--shrine-set="):
			for kv in arg.get_slice("=", 1).split(",", false):
				_shrine_set[kv.get_slice(":", 0)] = float(kv.get_slice(":", 1))
		elif arg == "--rows":
			rows = true
	print("Mode bench: %d seeds a mode, CPU level %s, shrines %s %s" % [seeds, CpuController.LEVELS[level]["name"], shrines,
		_shrine_set if not _shrine_set.is_empty() else ""])
	print("| Mode | Matches | Length (s) | Stalemate | Fights/min | KOs/match | Captures/match | Leader at half | Comebacks | Shrine claims/match | Claimer won | More buffs won |")
	print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for m in modes:
		if MODES.has(m):
			_bench(String(m), seeds, level, shrines, rows)
	quit()


func _rules(cfg: Array, shrines: String) -> Dictionary:
	var r := BrawlSim.load_rules() if cfg[0] == "brawl" else (
		TeamSim.load_rules() if String(cfg[1]) == "" else TeamSim.rules_by_id(String(cfg[1])))
	if shrines == "off":
		r.erase("shrines")
	elif shrines == "on" and not r.has("shrines"):
		r["shrines"] = {"kinds": ["haste", "might"]}
	if r.has("shrines"):
		(r["shrines"] as Dictionary).merge(_shrine_set, true)
	return r


func _bench(id: String, seeds: int, level: int, shrines: String, rows: bool) -> void:
	var cfg: Array = MODES[id]
	var rules := _rules(cfg, shrines)
	var tot := {"len": 0.0, "fight": 0, "quiet": 0, "fights": 0, "kos": 0, "led": 0, "back": 0, "claims": 0,
		"claims_won": 0, "claims_decided": 0, "caps": 0, "buff_led": 0, "buff_won": 0}
	for s in range(_seed0, _seed0 + seeds):
		var r := _match(cfg, s, level, rules)
		for k in tot:
			tot[k] += r[k]
		if rows:
			print("  %s seed %d: %.0f s, winner %d, stalemate %.0f%%, fights %d, KOs %d, leader at half %s, claims %d" % [
				id, s, r["len"], r["winner"], 100.0 * r["quiet"] / maxf(1.0, r["fight"]), r["fights"], r["kos"],
				str(r["leader"]), r["claims"]])
	var mins := float(tot["fight"]) / 3600.0
	print("| %s | %d | %.0f | %.0f%% | %.2f | %.1f | %.1f | %d | %s | %.1f | %s | %s |" % [cfg[3], seeds, tot["len"] / seeds,
		100.0 * tot["quiet"] / maxf(1.0, tot["fight"]), tot["fights"] / maxf(0.01, mins), float(tot["kos"]) / seeds,
		float(tot["caps"]) / seeds, tot["led"], ("%d of %d" % [tot["back"], tot["led"]]) if tot["led"] > 0 else "n/a",
		float(tot["claims"]) / seeds,
		("%.0f%%" % (100.0 * tot["claims_won"] / tot["claims_decided"])) if tot["claims_decided"] > 0 else "n/a",
		("%d of %d" % [tot["buff_won"], tot["buff_led"]]) if tot["buff_led"] > 0 else "n/a"])


func _match(cfg: Array, s: int, level: int, rules: Dictionary) -> Dictionary:
	var brawl: bool = cfg[0] == "brawl"
	var n: int = int(cfg[2])
	var game: Object
	if brawl:
		var ids: Array = []
		for k in n:
			ids.append(ROSTER[(s * 3 + k) % ROSTER.size()])
		game = BrawlSim.new(ids, rules.duplicate(true))
	else:
		var teams := [[], []]
		for k in n * 2:
			teams[k % 2].append(ROSTER[(s * 3 + k) % ROSTER.size()])
		game = TeamSim.new(teams, n, rules.duplicate(true))
	var sim: MatchSim = game.sim
	var cpus: Array = []
	for i in game.slot_count():
		cpus.append(CpuController.new(i, level, 1000 * s + i))
	var limit := int(float(rules.get("time_seconds", 180)) * 60) + 60 * 150
	var fight := 0
	var quiet := 0
	var last_hit := -1
	var fights := 0
	var kos := 0
	var was_down: Array = []
	was_down.resize(sim.creatures.size())
	was_down.fill(false)
	var samples: Array = []
	var claims: Array = []  # the team of each claim
	var caps := 0
	var buffs := {}  # team -> permanent shrine buffs taken
	for t in limit:
		var ins := PackedInt32Array()
		for i in game.slot_count():
			ins.append((cpus[i] as CpuController).bits(sim))
		var was_fight := int(game.phase) == 1  # FIGHT (the deciding tick's events count too)
		game.step(ins)
		if not was_fight:
			continue
		for e in sim.events:
			match String(e["type"]):
				"hit":
					if last_hit < 0 or fight - last_hit > QUIET:
						fights += 1
					last_hit = fight
				"shrine":
					claims.append(int(e.get("team", -1)))
				"capture":
					caps += 1
				"shrine_boost":
					if String(e.get("boost", "")) != "":
						buffs[int(e["team"])] = int(buffs.get(int(e["team"]), 0)) + 1
		for c in sim.creatures:  # a knockout: going down (the deciding one ends the match before its "ko" event)
			var down := c.state == CreatureSim.State.KO or c.hp <= 0.0
			if down and not bool(was_down[c.id]):
				kos += 1
			was_down[c.id] = down
		if last_hit < 0 or fight - last_hit > QUIET:
			quiet += 1
		if fight % SAMPLE == 0:
			samples.append(_standing(game, cfg))
		fight += 1
		if int(game.phase) == 2:  # OVER
			break
	var winner := int(game.winner)
	var leader := -1
	if not samples.is_empty():
		leader = _leader(samples[mini(samples.size() - 1, samples.size() / 2)])
	var buff_led := 0
	var buff_won := 0
	if winner >= 0 and not buffs.is_empty():
		var most := -1
		var top := 0
		for team in buffs:
			if int(buffs[team]) > top:
				top = int(buffs[team])
				most = int(team)
			elif int(buffs[team]) == top:
				most = -1
		if most >= 0:
			buff_led = 1
			buff_won = 1 if most == winner else 0
	var won := 0
	for c in claims:
		if int(c) == winner:
			won += 1
	return {"len": float(sim.tick) / 60.0, "fight": fight, "quiet": quiet, "fights": fights, "kos": kos,
		"led": 1 if leader >= 0 and winner >= 0 else 0, "back": 1 if leader >= 0 and winner >= 0 and winner != leader else 0,
		"claims": claims.size(), "claims_won": won if winner >= 0 else 0, "claims_decided": claims.size() if winner >= 0 else 0,
		"winner": winner, "leader": leader, "caps": caps, "buff_led": buff_led, "buff_won": buff_won}


## Each side's standing (higher is ahead): the mode's score where it keeps one, else the
## share of the side's health left. Caravan has none (its rounds are judged at the end).
func _standing(game: Object, cfg: Array) -> Array:
	var sim: MatchSim = game.sim
	if cfg[0] == "brawl":
		var out: Array = []
		for c in sim.creatures:
			out.append(maxf(0.0, c.hp) / c.max_hp if c.state != CreatureSim.State.KO else 0.0)
		return out
	var t := game as TeamSim
	if t.caravan:
		return []
	if t.deathmatch:  # deathmatch, crater, ctf: the score
		return [float(t.score[0]), float(t.score[1])]
	var share := [0.0, 0.0]
	for side in 2:
		var hp := 0.0
		var total := 0.0
		for c in t.members(side):
			hp += maxf(0.0, (c as CreatureSim).hp)
			total += (c as CreatureSim).max_hp
		share[side] = hp / maxf(1.0, total)
	return share


## The side alone at the top, or -1 (a tie, or nothing to judge).
func _leader(st: Array) -> int:
	var best := -1
	var top := -INF
	for i in st.size():
		var v := float(st[i])
		if v > top + 0.001:
			top = v
			best = i
		elif absf(v - top) <= 0.001:
			best = -1
	return best
