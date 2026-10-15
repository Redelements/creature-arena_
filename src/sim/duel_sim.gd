class_name DuelSim
extends RefCounted
## Duel: 3v3 tag. Each side brings a team; one creature per side fights at a time.
##
##   - TAG (IN_TAG) sends the next living teammate in with its tag-in strike, from
##     neutral or guard, or out of an attack that connected (costs energy: a combo
##     extender). Then the tag is on cooldown.
##   - Benched creatures slowly heal back part of what they lost.
##   - When the active creature is knocked out, the next one enters after the death
##     animation. A team with nobody left loses; at time out, the most health left wins.
##
## Every rule here is deterministic simulation code, and the whole duel is saved by
## snapshot(), so a RollbackSession can drive a Duel exactly like a single sim.
## Tuning: data/rules/duel.json.

enum Phase { INTRO, FIGHT, SWAP, OVER }

const RULES_PATH := "res://data/rules/duel.json"

var sim: MatchSim
var teams: Array = [[], []]  ## CreatureSim per member; every member of side s has id s
var rules: Dictionary

# Duel state (all saved by snapshot()).
var active := [0, 0]
var tag_cd := [0, 0]
var prev_inputs := [0, 0]
var bench_cap := [[], []]  ## hp each benched member may heal back up to
var phase: Phase = Phase.INTRO
var phase_t := 0
var timer := 0
var winner := -2  ## -2 undecided, -1 draw, else the winning side
var swap_side := -1  ## the side waiting for its next creature to enter


static func load_rules() -> Dictionary:
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if typeof(d) == TYPE_DICTIONARY else {}


## `team_ids` is [[left ids], [right ids]], e.g. [["cairn", "culvert", "cairn"], [...]].
func _init(team_ids: Array, p_rules: Dictionary = {}) -> void:
	rules = p_rules if not p_rules.is_empty() else load_rules()
	sim = MatchSim.new()
	sim.set_arena(String(rules.get("arena", MatchFactory.arena)))
	for side in 2:
		for i in (team_ids[side] as Array).size():
			var c := CreatureSim.new(side, MatchFactory.load_def(String(team_ids[side][i])), sim.spawn(side))
			c.facing = Vector2.RIGHT if side == 0 else Vector2.LEFT
			teams[side].append(c)
			bench_cap[side].append(c.max_hp)
	sim.creatures.assign([teams[0][0], teams[1][0]])
	timer = int(float(rules.get("time_seconds", 180)) * SimDefs.TICK_RATE)


func active_creature(side: int) -> CreatureSim:
	return teams[side][active[side]]


func alive_count(side: int) -> int:
	var n := 0
	for c in teams[side]:
		if not _down(c):
			n += 1
	return n


func _down(c: CreatureSim) -> bool:
	return c.state == CreatureSim.State.KO or c.hp <= 0.0


## The next living benched teammate's index, or -1.
func _next_member(side: int) -> int:
	var n: int = teams[side].size()
	for k in range(1, n):
		var i: int = (active[side] + k) % n
		if not _down(teams[side][i]):
			return i
	return -1


## Whether `side` may tag right now (and whether it would be a paid tag cancel).
func can_tag(side: int) -> bool:
	return _tag_kind(side) != ""


func _tag_kind(side: int) -> String:
	if phase != Phase.FIGHT or tag_cd[side] > 0 or _next_member(side) < 0:
		return ""
	var c := active_creature(side)
	match c.state:
		CreatureSim.State.IDLE, CreatureSim.State.MOVE:
			return "neutral"
		CreatureSim.State.GUARD:
			return "neutral" if c.stun <= 0 else ""
		CreatureSim.State.ATTACK:
			if c.connected and not c.charging and c.energy >= float(rules.get("tag_cancel_energy", 50)):
				return "cancel"
	return ""


# ------------------------------------------------------------------ stepping

func step(inputs: PackedInt32Array) -> void:
	var ins := PackedInt32Array([_in(inputs, 0), _in(inputs, 1)])
	match phase:
		Phase.INTRO:
			phase_t += 1
			ins = PackedInt32Array([0, 0])
			if phase_t >= int(rules.get("intro_ticks", 100)):
				_set_phase(Phase.FIGHT)
		Phase.FIGHT:
			for side in 2:
				var pressed := ins[side] & ~int(prev_inputs[side])
				if (pressed & SimDefs.IN_TAG) and can_tag(side):
					_tag(side)
		Phase.SWAP, Phase.OVER:
			ins = PackedInt32Array([0, 0])
			phase_t += 1
	prev_inputs = [_in(inputs, 0), _in(inputs, 1)]

	sim.step(ins)

	for side in 2:
		if tag_cd[side] > 0 and sim.ko_freeze == 0:
			tag_cd[side] -= 1
		_bench_regen(side)
	if phase == Phase.FIGHT and sim.ko_freeze == 0:
		timer -= 1
	_check_knockouts()
	if phase == Phase.SWAP and phase_t >= int(rules.get("ko_swap_ticks", 110)):
		_enter_next(swap_side)
	if phase == Phase.FIGHT and timer <= 0:
		_time_out()


static func _in(inputs: PackedInt32Array, i: int) -> int:
	return inputs[i] if i < inputs.size() else 0


func _set_phase(p: Phase) -> void:
	phase = p
	phase_t = 0


func _tag(side: int) -> void:
	var kind := _tag_kind(side)
	var out := active_creature(side)
	var nxt := _next_member(side)
	var inc: CreatureSim = teams[side][nxt]
	# Energy and stamina belong to the team, not the creature.
	inc.energy = out.energy - (float(rules.get("tag_cancel_energy", 50)) if kind == "cancel" else 0.0)
	inc.stamina = out.stamina
	inc.pos = out.pos
	inc.facing = out.facing
	inc.knock_vel = Vector2.ZERO
	inc.walk_vel = Vector2.ZERO
	inc.reset_combo()
	inc.cancel_attack()
	inc.prev_buttons = out.prev_buttons
	# The outgoing creature leaves cleanly and may heal back part of what it lost.
	bench_cap[side][active[side]] = minf(out.max_hp, out.hp + out.max_hp * float(rules.get("bench_regen_cap", 0.25)))
	out.cancel_attack()
	out.knock_vel = Vector2.ZERO
	out.walk_vel = Vector2.ZERO
	out._set_state(CreatureSim.State.IDLE)
	active[side] = nxt
	sim.creatures[side] = inc
	if inc.moves().has("tag_in"):
		inc._start_attack("tag_in", sim)
		var mv := inc.move_def()
		inc.invuln = int(mv.get("startup", 0)) + int(rules.get("tag_in_invuln", 10))
	else:
		inc._set_state(CreatureSim.State.IDLE)
	tag_cd[side] = int(rules.get("tag_cooldown", 300))
	sim.emit_event("tag", inc.pos, 1.0, {"who": side, "kind": kind,
		"name": String(inc.def.get("name", "")), "out": String(out.def.get("name", ""))})


func _bench_regen(side: int) -> void:
	var per_tick := float(rules.get("bench_regen_per_second", 1.5)) / SimDefs.TICK_RATE
	for i in (teams[side] as Array).size():
		if i == active[side]:
			continue
		var c: CreatureSim = teams[side][i]
		if _down(c):
			continue
		c.hp = minf(c.hp + per_tick, float(bench_cap[side][i]))


func _check_knockouts() -> void:
	if phase != Phase.FIGHT:
		return
	var down := [_down(active_creature(0)), _down(active_creature(1))]
	if not down[0] and not down[1]:
		return
	var left := [alive_count(0), alive_count(1)]
	if left[0] == 0 or left[1] == 0:
		winner = -1 if left[0] == left[1] else (0 if left[0] > 0 else 1)
		_set_phase(Phase.OVER)
		sim.emit_event("duel_over", Vector2.ZERO, 1.0, {"winner": winner, "by": "ko"})
		return
	# A creature went down but its team has more: shorter slow motion, then a swap.
	sim.slowmo = mini(sim.slowmo, int(rules.get("mid_ko_slowmo", 40)))
	swap_side = 0 if down[0] else 1
	_set_phase(Phase.SWAP)


func _enter_next(side: int) -> void:
	var nxt := _next_member(side)
	if nxt < 0:
		return
	var inc: CreatureSim = teams[side][nxt]
	var out := active_creature(side)
	inc.energy = out.energy
	inc.stamina = inc.max_stamina
	inc.pos = sim.terrain.nearest_solid(sim.spawn(side))
	var foe := active_creature(1 - side)
	inc.facing = Vector2.RIGHT if foe.pos.x >= inc.pos.x else Vector2.LEFT
	inc.reset_combo()
	inc.cancel_attack()
	inc._set_state(CreatureSim.State.IDLE)
	inc.invuln = int(rules.get("enter_invuln", 60))
	active[side] = nxt
	sim.creatures[side] = inc
	# The survivor resets to neutral too, so the new round of the duel starts fair.
	foe.reset_combo()
	swap_side = -1
	_set_phase(Phase.FIGHT)
	sim.emit_event("enter", inc.pos, 1.0, {"who": side, "name": String(inc.def.get("name", ""))})


func _time_out() -> void:
	var share := [0.0, 0.0]
	for side in 2:
		var hp := 0.0
		var total := 0.0
		for c in teams[side]:
			hp += maxf(0.0, c.hp)
			total += c.max_hp
		share[side] = hp / maxf(total, 1.0)
	winner = 0 if share[0] > share[1] else (1 if share[1] > share[0] else -1)
	_set_phase(Phase.OVER)
	sim.emit_event("duel_over", Vector2.ZERO, 1.0, {"winner": winner, "by": "time"})


# ------------------------------------------------------------------ rollback

func snapshot() -> Dictionary:
	var members := [[], []]
	for side in 2:
		for c in teams[side]:
			members[side].append(c.save_state())
	return {
		"members": members, "active": active.duplicate(), "tag_cd": tag_cd.duplicate(),
		"prev_inputs": prev_inputs.duplicate(), "bench_cap": bench_cap.duplicate(true),
		"phase": phase, "phase_t": phase_t, "timer": timer, "winner": winner,
		"swap_side": swap_side, "match": sim.snapshot(),
	}


func restore(s: Dictionary) -> void:
	active = (s["active"] as Array).duplicate()
	for side in 2:
		for i in (teams[side] as Array).size():
			(teams[side][i] as CreatureSim).load_state(s["members"][side][i])
		sim.creatures[side] = teams[side][active[side]]
	tag_cd = (s["tag_cd"] as Array).duplicate()
	prev_inputs = (s["prev_inputs"] as Array).duplicate()
	bench_cap = (s["bench_cap"] as Array).duplicate(true)
	phase = s["phase"]
	phase_t = int(s["phase_t"])
	timer = int(s["timer"])
	winner = int(s["winner"])
	swap_side = int(s["swap_side"])
	sim.restore(s["match"])


func state_digest() -> String:
	var parts: Array = [sim.state_digest(), active, tag_cd, prev_inputs, bench_cap, phase, phase_t,
		timer, winner, swap_side]
	for side in 2:
		for c in teams[side]:
			var st := (c as CreatureSim).save_state()
			for f in CreatureSim.STATE_FIELDS:
				parts.append(st[f])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(parts))
	return ctx.finish().hex_encode()


func state_hash() -> int:
	return hash(state_digest())
