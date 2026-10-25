class_name Shrines
extends RefCounted
## Shrines: rings on the floor that a team claims for a buff, in any mode whose rules turn
## them on (a "shrines" block; data/rules/shrines.json holds the defaults it is laid over).
## The rules are here; the state lives on the match (`MatchSim.shrines`, saved by snapshot,
## restore and state_digest), and where each one is and the merged rules are fixed for the
## match (`MatchSim.shrine_spots`, `shrine_rules`). The mode steps them (`step`, during the
## fight only, not in a KO freeze), so any mode with any number of teams can have them:
## Team battle, Team Deathmatch, King of the Crater, Sinkhole and Capture the Flag (two
## sides), Brawl (each fighter its own team).
##
## Per shrine the state is [the team claiming it (-1), ticks claimed (a float: the `claim`
## class perk claims faster), ticks until it's ready (0: ready), times it's been claimed].
## A team alone in a ready shrine claims it; another team alone wears an enemy claim down
## (twice as fast) before it starts its own; two or more teams in it hold the claim where it
## is; nobody in it lets it fade a tick a tick. A full claim buffs every fighter of that team
## on its feet (haste or might) and the shrine rests. Keys in docs/MECHANICS.md ("Shrines").
##
## Events: shrine_soon {shrine, kind, ticks} `announce_seconds` before it's ready,
## shrine_ready {shrine, kind}, shrine {shrine, kind, team; power: the buff's ticks}.

const PATH := "res://data/rules/shrines.json"
static var _defaults := {}


static func defaults() -> Dictionary:
	if _defaults.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_defaults = d if d is Dictionary else {}
	return _defaults


static func ticks_of(seconds: Variant) -> int:
	return int(float(seconds) * SimDefs.TICK_RATE)


## Turns shrines on for the match when the mode's rules have a "shrines" block (`block`,
## laid over the defaults); `perks` is the mode's "class_perks" (their `claim`). The map's
## "shrines" say where they are, else the rules' "spots" (fractions of the floor). Call once
## the arena is set.
static func setup(sim: MatchSim, block: Dictionary, perks: Dictionary = {}) -> void:
	sim.shrines = []
	sim.shrine_spots = []
	sim.shrine_rules = {}
	if block.is_empty():
		return
	var sr := defaults().duplicate(true)
	sr.merge(block, true)
	var claim := {}
	for role in perks:
		var p: Dictionary = perks[role]
		if p.has("claim"):
			claim[String(role)] = float(p["claim"])
	sr["_claim"] = claim
	sim.shrine_rules = sr
	var r := float(sr.get("radius", 24))
	if sim.arena.has("shrines"):
		for sd in sim.arena["shrines"]:
			var v: Array = (sd as Dictionary).get("pos", [0, 0])
			sim.shrine_spots.append({"pos": Vector2(float(v[0]), float(v[1])),
				"radius": float((sd as Dictionary).get("radius", r)), "kind": String((sd as Dictionary).get("kind", "haste"))})
	else:
		var fr := sim.floor_rect()
		for sp in sr.get("spots", [[0.5, 0.5]]):
			var at := sim.terrain.nearest_solid(Vector2(fr.position.x + fr.size.x * float(sp[0]),
				fr.position.y + fr.size.y * float(sp[1])))
			sim.shrine_spots.append({"pos": at, "radius": r, "kind": "haste"})
	for i in sim.shrine_spots.size():
		sim.shrines.append([-1, 0.0, ticks_of(sr.get("first_seconds", 30)), 0])


static func pos(sim: MatchSim, i: int) -> Vector2:
	return sim.shrine_spots[i]["pos"]


static func radius(sim: MatchSim, i: int) -> float:
	return float(sim.shrine_spots[i]["radius"])


## What shrine `i` gives next: the rules' "kinds" cycle when there is one, else the map's.
static func kind(sim: MatchSim, i: int) -> String:
	var ks: Array = sim.shrine_rules.get("kinds", [])
	if not ks.is_empty():
		return String(ks[(i + int(sim.shrines[i][3])) % ks.size()])
	return String(sim.shrine_spots[i]["kind"])


static func claim_ticks(sim: MatchSim) -> int:
	return ticks_of(sim.shrine_rules.get("claim_seconds", 3))


static func _down(c: CreatureSim) -> bool:
	return c.state == CreatureSim.State.KO or c.hp <= 0.0


## Whether `c` counts as standing in shrine `i`.
static func inside(sim: MatchSim, c: CreatureSim, i: int) -> bool:
	return not _down(c) and c.state != CreatureSim.State.FALLING and c.pos.distance_to(pos(sim, i)) <= radius(sim, i)


## The teams standing in shrine `i`, each once, in slot order.
static func teams_in(sim: MatchSim, i: int) -> Array:
	var out: Array = []
	for c in sim.creatures:
		if inside(sim, c, i) and not (c.team in out):
			out.append(c.team)
	return out


## One tick of every shrine. The mode calls it while the fight is on (not in a KO freeze).
static func step(sim: MatchSim) -> void:
	var sr := sim.shrine_rules
	var need := claim_ticks(sim)
	var soon := ticks_of(sr.get("announce_seconds", 10))
	var perks: Dictionary = sr.get("_claim", {})
	for i in sim.shrines.size():
		var st: Array = sim.shrines[i]
		if int(st[2]) > 0:
			st[2] = int(st[2]) - 1
			if int(st[2]) == 0:
				sim.emit_event("shrine_ready", pos(sim, i), 0.0, {"shrine": i, "kind": kind(sim, i)})
			elif int(st[2]) == soon:
				sim.emit_event("shrine_soon", pos(sim, i), float(soon), {"shrine": i, "kind": kind(sim, i), "ticks": soon})
			continue
		var who := -1  # the one team in it (-1: none), or -2 when two or more are
		var rate := 1.0  # its fastest claimer's (`claim` perk)
		for c in sim.creatures:
			if not inside(sim, c, i):
				continue
			if who == -1:
				who = c.team
			elif who != c.team:
				who = -2
				break
			rate = maxf(rate, float(perks.get(String(c.def.get("role", "fighter")), 1.0)))
		if who == -2:
			continue  # contested: the claim holds where it is
		if who == -1:
			st[1] = maxf(0.0, float(st[1]) - 1.0)
		elif int(st[0]) == who or float(st[1]) <= 0.0:
			st[0] = who
			st[1] = float(st[1]) + rate
		else:
			st[1] = maxf(0.0, float(st[1]) - 2.0 * rate)
		if float(st[1]) <= 0.0:
			st[0] = -1
		elif float(st[1]) >= float(need):
			var team := int(st[0])
			var k := kind(sim, i)
			var t := ticks_of(sr.get("buff_seconds", 20))
			for c in sim.creatures:
				if c.team != team or _down(c):
					continue
				if k == "might":
					c.atk_buff = maxi(c.atk_buff, t)
					c.atk_mult = float(sr.get("might_mult", 1.2))
				else:
					c.haste = maxi(c.haste, t)
					c.haste_mult = float(sr.get("haste_mult", 1.2))
			st[0] = -1
			st[1] = 0.0
			st[2] = ticks_of(sr.get("cooldown_seconds", 45))
			st[3] = int(st[3]) + 1
			sim.emit_event("shrine", pos(sim, i), float(t), {"shrine": i, "kind": k, "team": team})


## The nearest ready shrine to `p`, or -1.
static func nearest_ready(sim: MatchSim, p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in sim.shrines.size():
		if int(sim.shrines[i][2]) > 0:
			continue
		var d := p.distance_to(pos(sim, i))
		if d < best_d:
			best_d = d
			best = i
	return best


## The CPU's goals (sim.goals) for a mode with no goals of its own: per team, the one
## fighter nearest a ready shrine goes to claim it, if it's within `cpu_range` px and no
## foe is within `cpu_engaged` px of it (mid-fight); one already in it stays. The rest of
## the team fights on. A shrine being claimed by another team counts (to contest it).
static func write_goals(sim: MatchSim) -> void:
	sim.goals.resize(sim.creatures.size())
	for k in sim.creatures.size():
		sim.goals[k] = []
	var reach := float(sim.shrine_rules.get("cpu_range", 260))
	var engaged := float(sim.shrine_rules.get("cpu_engaged", 56))
	var picked := {}  # team -> [slot, distance, shrine]
	for c in sim.creatures:
		if _down(c) or c.state == CreatureSim.State.FALLING:
			continue
		var si := nearest_ready(sim, c.pos)
		if si < 0:
			continue
		var d := c.pos.distance_to(pos(sim, si))
		if d > reach:
			continue
		var busy := false
		for o in sim.creatures:
			if c.is_foe(o) and not _down(o) and o.pos.distance_to(c.pos) < engaged:
				busy = true
				break
		if busy and d > radius(sim, si):
			continue
		var best: Array = picked.get(c.team, [])
		if best.is_empty() or d < float(best[1]):
			picked[c.team] = [c.id, d, si]
	for team in picked:
		var b: Array = picked[team]
		var si := int(b[2])
		sim.goals[int(b[0])] = [pos(sim, si), radius(sim, si) - 8.0, false]
