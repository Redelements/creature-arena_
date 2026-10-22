class_name BrawlSim
extends RefCounted
## Brawl: a free-for-all of two to four creatures, each on its own team with one life.
## The last one standing wins; at time, the one with the biggest share of its health.
## Slot i is player i. Every rule here is simulation code and everything is saved by
## snapshot(), so it rolls back like a Duel. Tuning: data/rules/brawl.json. Chaos Cup
## is a Brawl with mutators (MatchSim.apply_mutators) stacked on.

enum Phase { INTRO, FIGHT, OVER }

const RULES_PATH := "res://data/rules/brawl.json"
const MAX_PLAYERS := 4

var sim: MatchSim
var rules: Dictionary
var phase: Phase = Phase.INTRO
var phase_t := 0
var timer := 0
var winner := -2  ## -2 undecided, -1 draw, else the winning slot


static func load_rules(path := RULES_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if typeof(d) == TYPE_DICTIONARY else {}


## `ids`: two to four fighter ids, one per slot. `mutators` (Chaos Cup) are applied
## with `seed_` once everyone is in.
func _init(ids: Array, p_rules: Dictionary = {}, mutators: Dictionary = {}, seed_ := 0) -> void:
	rules = p_rules if not p_rules.is_empty() else load_rules()
	sim = MatchSim.new()
	sim.set_arena(String(rules.get("arena", MatchFactory.arena)))
	var n := clampi(ids.size(), 2, MAX_PLAYERS)
	var fr := sim.floor_rect()
	var spots: Array = rules.get("spawns", [[0.25, 0.3], [0.75, 0.3], [0.25, 0.7], [0.75, 0.7]])
	for k in n:
		var sp: Array = spots[k % spots.size()]
		var at := sim.terrain.nearest_solid(Vector2(fr.position.x + fr.size.x * float(sp[0]),
			fr.position.y + fr.size.y * float(sp[1])))
		var c := sim.add_creature(MatchFactory.load_def(String(ids[k])), at)
		c.team = k
		c.facing = Vector2.RIGHT if at.x < fr.get_center().x else Vector2.LEFT
	sim.surge_freeze = n == 2  # three or four: a Surge winds up instead of stopping everyone
	if not mutators.is_empty():
		sim.apply_mutators(mutators, seed_)
	timer = int(float(rules.get("time_seconds", 120)) * SimDefs.TICK_RATE)


func slot_count() -> int:
	return sim.creatures.size()


func alive(slot: int) -> bool:
	var c := sim.creatures[slot]
	return c.state != CreatureSim.State.KO and c.hp > 0.0


func alive_count() -> int:
	var n := 0
	for i in slot_count():
		if alive(i):
			n += 1
	return n


func step(inputs: PackedInt32Array) -> void:
	var ins := PackedInt32Array()
	ins.resize(slot_count())
	if phase == Phase.FIGHT:
		for i in slot_count():
			ins[i] = inputs[i] if i < inputs.size() else 0
	else:
		phase_t += 1
		if phase == Phase.INTRO and phase_t >= int(rules.get("intro_ticks", 100)):
			_set_phase(Phase.FIGHT)
	var before := alive_count()
	sim.step(ins)
	if phase != Phase.FIGHT:
		return
	if sim.ko_freeze == 0:
		timer -= 1
	var left := alive_count()
	if left <= 1:
		winner = -1
		for i in slot_count():
			if alive(i):
				winner = i
		_set_phase(Phase.OVER)
		sim.emit_event("duel_over", Vector2.ZERO, 1.0, {"winner": winner, "by": "ko"})
	elif left < before:
		sim.slowmo = mini(sim.slowmo, int(rules.get("mid_ko_slowmo", 30)))
	elif timer <= 0:
		_time_out()


func _set_phase(p: Phase) -> void:
	phase = p
	phase_t = 0


func _time_out() -> void:
	var best := -1.0
	winner = -1
	for i in slot_count():
		if not alive(i):
			continue
		var c := sim.creatures[i]
		var share := c.hp / c.max_hp
		if share > best + 0.0001:
			best = share
			winner = i
		elif absf(share - best) <= 0.0001:
			winner = -1  # a tie at the top is a draw
	_set_phase(Phase.OVER)
	sim.emit_event("duel_over", Vector2.ZERO, 1.0, {"winner": winner, "by": "time"})


# ------------------------------------------------------------------ rollback

func snapshot() -> Dictionary:
	return {"phase": phase, "phase_t": phase_t, "timer": timer, "winner": winner, "match": sim.snapshot()}


func restore(s: Dictionary) -> void:
	phase = s["phase"]
	phase_t = int(s["phase_t"])
	timer = int(s["timer"])
	winner = int(s["winner"])
	sim.restore(s["match"])


func state_digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes([sim.state_digest(), phase, phase_t, timer, winner]))
	return ctx.finish().hex_encode()


func state_hash() -> int:
	return hash(state_digest())
