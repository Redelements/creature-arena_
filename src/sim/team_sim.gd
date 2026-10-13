class_name TeamSim
extends RefCounted
## Team battle: two sides of 1 to 3 creatures each, all on the field at once (2v2, 3v3).
## Every creature is one player's, with one life. Teammates can't hurt each other (see
## CreatureSim.team). The last side with anyone standing wins; at time out, the side
## with the bigger share of its health left wins.
##
## Slots: creature i is player i. Side 0 (left, red) is slots 0..n-1 and side 1 (right,
## blue) is slots n..2n-1, so step() takes one input per slot in that order.
##
## Every rule here is simulation code and everything is saved by snapshot(), so a
## RollbackSession can drive it exactly like a Duel. Tuning: data/rules/team.json.

enum Phase { INTRO, FIGHT, OVER }

const RULES_PATH := "res://data/rules/team.json"

var sim: MatchSim
var rules: Dictionary
var size := 1  ## creatures per side

var phase: Phase = Phase.INTRO
var phase_t := 0
var timer := 0
var winner := -2  ## -2 undecided, -1 draw, else the winning side


static func load_rules() -> Dictionary:
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if typeof(d) == TYPE_DICTIONARY else {}


## `team_ids` is [[left ids], [right ids]]. `per_side` creatures fight on each side (1 to
## 3; 0: as many as the shorter list), the first ones of each list.
func _init(team_ids: Array, per_side := 0, p_rules: Dictionary = {}) -> void:
	rules = p_rules if not p_rules.is_empty() else load_rules()
	sim = MatchSim.new()
	var most := mini((team_ids[0] as Array).size(), (team_ids[1] as Array).size())
	size = clampi(per_side if per_side > 0 else most, 1, mini(3, most))
	for side in 2:
		for k in size:
			var c := sim.add_creature(MatchFactory.load_def(String(team_ids[side][k])),
				spawn_point(side, k, size, float(rules.get("spawn_spread", 60))))
			c.team = side
			c.facing = Vector2.RIGHT if side == 0 else Vector2.LEFT
	timer = int(float(rules.get("time_seconds", 150)) * SimDefs.TICK_RATE)


## Where slot k of a side with n starts: stacked up and down the side's spawn point.
static func spawn_point(side: int, k: int, n: int, spread := 60.0) -> Vector2:
	var base := MatchFactory.SPAWN_LEFT if side == 0 else MatchFactory.SPAWN_RIGHT
	return base + Vector2(0.0, (float(k) - float(n - 1) * 0.5) * spread)


func slot_count() -> int:
	return size * 2


func side_of(slot: int) -> int:
	return sim.creatures[slot].team


func members(side: int) -> Array:
	var out: Array = []
	for c in sim.creatures:
		if c.team == side:
			out.append(c)
	return out


func alive_count(side: int) -> int:
	var n := 0
	for c in members(side):
		if not _down(c):
			n += 1
	return n


func _down(c: CreatureSim) -> bool:
	return c.state == CreatureSim.State.KO or c.hp <= 0.0


# ------------------------------------------------------------------ stepping

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
	var before := [alive_count(0), alive_count(1)]
	sim.step(ins)
	if phase != Phase.FIGHT:
		return
	if sim.ko_freeze == 0:
		timer -= 1
	var left := [alive_count(0), alive_count(1)]
	if left[0] == 0 or left[1] == 0:
		winner = -1 if left[0] == left[1] else (0 if left[0] > 0 else 1)
		_set_phase(Phase.OVER)
		sim.emit_event("duel_over", Vector2.ZERO, 1.0, {"winner": winner, "by": "ko"})
	elif left[0] < before[0] or left[1] < before[1]:
		# Someone went down but the fight goes on: a shorter slow motion than a finish.
		sim.slowmo = mini(sim.slowmo, int(rules.get("mid_ko_slowmo", 30)))
	elif timer <= 0:
		_time_out()


func _set_phase(p: Phase) -> void:
	phase = p
	phase_t = 0


func _time_out() -> void:
	var share := [0.0, 0.0]
	for side in 2:
		var hp := 0.0
		var total := 0.0
		for c in members(side):
			hp += maxf(0.0, (c as CreatureSim).hp)
			total += (c as CreatureSim).max_hp
		share[side] = hp / maxf(total, 1.0)
	winner = 0 if share[0] > share[1] else (1 if share[1] > share[0] else -1)
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
