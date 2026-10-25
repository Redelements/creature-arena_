class_name BrawlSim
extends RefCounted
## Brawl: a free-for-all of two to four creatures, each on its own team with one life.
## The last one standing wins; at time, the one with the biggest share of its health.
## Slot i is player i. Every rule here is simulation code and everything is saved by
## snapshot(), so it rolls back like a Duel. Tuning: data/rules/brawl.json. Chaos Cup
## is a Brawl with mutators (MatchSim.apply_mutators) stacked on. With a "shrines" block in
## the rules (brawl.json has one) the floor has shrines (Shrines), claimed by one fighter
## alone: each fighter is its own team, so a claim is a fighter's.
##
## The crown (rules with "crown": true, brawl.json): a KO is credited to the victim's last
## hitter if that hit landed within `credit_seconds` (MatchSim.note_credit). While nobody
## wears the crown (the start, or after its holder went down with nobody's hit behind it:
## a pit, a hazard), the next credited KO gives it to the killer; KOing the holder takes it.
## Event "crown" ({who: the new holder or -1 when it drops, from: who lost it}). The holder
## scores `crown_points_per_second` (`crown_points`) and is marked for the CPU
## (`MatchSim.marks`, `crown_cpu_pull` px). At time the standing fighter with the most
## crown points wins (`crown_decides_time`; a tie there falls back to health), and with
## `crown_points_to_win` > 0 reaching it wins outright (by "crown").

enum Phase { INTRO, FIGHT, OVER }

const RULES_PATH := "res://data/rules/brawl.json"
const MAX_PLAYERS := 4

var sim: MatchSim
var rules: Dictionary
var phase: Phase = Phase.INTRO
var phase_t := 0
var timer := 0
var winner := -2  ## -2 undecided, -1 draw, else the winning slot
## The crown (rules with "crown"): its holder (-1 none), each slot's ticks wearing it, who
## last hit each slot and when (MatchSim.note_credit), and whose knockout it has dealt with.
var crown_on := false
var crown := -1
var crown_t: Array = []
var hit_by: Array = []
var hit_at: Array = []
var gone: Array = []


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
	sim.freeze_all = n == 2  # three or four: a Surge winds up instead of stopping everyone
	if not mutators.is_empty():
		sim.apply_mutators(mutators, seed_)
	Shrines.setup(sim, rules.get("shrines", {}), {}, seed_)
	if not sim.shrines.is_empty():
		Shrines.write_goals(sim)
	timer = int(float(rules.get("time_seconds", 120)) * SimDefs.TICK_RATE)
	crown_on = bool(rules.get("crown", false))
	for k in n:
		crown_t.append(0)
		hit_by.append(-1)
		hit_at.append(-1)
		gone.append(false)
	if crown_on:
		sim.marks.resize(n)
		sim.marks.fill(0.0)


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
		if not sim.shrines.is_empty():
			Shrines.step(sim)
			Shrines.write_goals(sim)
	if crown_on:
		_crown_step()
		if phase != Phase.FIGHT:
			return
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


## The crown this tick: credit the hits, pass it on for each fighter that just went down,
## count the holder's time, mark it for the CPU, and a win on points when
## `crown_points_to_win` is set.
func _crown_step() -> void:
	sim.note_credit(hit_by, hit_at)
	var window := int(float(rules.get("credit_seconds", 5)) * SimDefs.TICK_RATE)
	for i in slot_count():
		if bool(gone[i]) or alive(i):
			continue
		gone[i] = true
		var k := MatchSim.credit_of(hit_by, hit_at, i, sim.tick, window)
		hit_by[i] = -1
		if k >= 0 and not alive(k):
			k = -1  # (both went down this tick)
		if crown == i or (crown < 0 and k >= 0):
			var from := crown
			crown = k
			sim.emit_event("crown", sim.creatures[k].pos if k >= 0 else sim.creatures[i].pos, 0.0,
				{"who": k, "from": from, "victim": i, "team": k})
	if crown >= 0 and sim.ko_freeze == 0:
		crown_t[crown] = int(crown_t[crown]) + 1
	for i in slot_count():
		sim.marks[i] = float(rules.get("crown_cpu_pull", 80)) if i == crown else 0.0
	var to_win := int(rules.get("crown_points_to_win", 0))
	if crown >= 0 and to_win > 0 and crown_points(crown) >= to_win:
		winner = crown
		_set_phase(Phase.OVER)
		sim.emit_event("duel_over", Vector2.ZERO, 1.0, {"winner": winner, "by": "crown"})


## A slot's crown points: `crown_points_per_second` for every second it has worn the crown.
func crown_points(slot: int) -> int:
	if slot < 0 or slot >= crown_t.size():
		return 0
	return floori(float(crown_t[slot]) * float(rules.get("crown_points_per_second", 1)) / float(SimDefs.TICK_RATE))


func _set_phase(p: Phase) -> void:
	phase = p
	phase_t = 0


func _time_out() -> void:
	var best := -1.0
	winner = -1
	if crown_on and bool(rules.get("crown_decides_time", true)):
		# The crown first: the standing fighter with the most crown points (a tie: health).
		var top := 0
		var at_top: Array = []
		for i in slot_count():
			if not alive(i):
				continue
			var pts := crown_points(i)
			if pts > top:
				top = pts
				at_top = [i]
			elif pts == top and top > 0:
				at_top.append(i)
		if at_top.size() == 1:
			winner = int(at_top[0])
			_set_phase(Phase.OVER)
			sim.emit_event("duel_over", Vector2.ZERO, 1.0, {"winner": winner, "by": "time"})
			return
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
	return {"phase": phase, "phase_t": phase_t, "timer": timer, "winner": winner, "match": sim.snapshot(),
		"crown": [crown, crown_t.duplicate(), hit_by.duplicate(), hit_at.duplicate(), gone.duplicate()]}


func restore(s: Dictionary) -> void:
	phase = s["phase"]
	phase_t = int(s["phase_t"])
	timer = int(s["timer"])
	winner = int(s["winner"])
	if s.has("crown"):
		crown = int(s["crown"][0])
		crown_t = (s["crown"][1] as Array).duplicate()
		hit_by = (s["crown"][2] as Array).duplicate()
		hit_at = (s["crown"][3] as Array).duplicate()
		gone = (s["crown"][4] as Array).duplicate()
	sim.restore(s["match"])


func state_digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes([sim.state_digest(), phase, phase_t, timer, winner, crown, crown_t, hit_by, hit_at, gone]))
	return ctx.finish().hex_encode()


func state_hash() -> int:
	return hash(state_digest())
