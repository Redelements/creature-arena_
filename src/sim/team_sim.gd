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
##
## Team Deathmatch (rules with "deathmatch": data/rules/deathmatch.json): lives are
## unlimited. A knocked-out fighter comes back after `respawn_seconds` on its team's spawn
## pad, against its own side wall, fresh (full health, no statuses; its Surge energy
## kept), invulnerable for `spawn_protect_seconds` or until it attacks. Every KO scores a
## point for the other team; first to `score_to_win` (by fighters per side) wins, or the
## higher score at time. A tie at time is sudden death: the next KO wins.
##
## Sinkhole (rules with "sinkhole": data/rules/sinkhole.json): one life each, and every
## `shrink_every` ticks the outermost ring of the floor cracks (a warning the CPU heeds)
## and `shrink_warn` ticks later drops into a chasm for good, up to `max_rings`. A fall
## is a knockout (`fall_ko` on the match). Last side standing wins.
##
## King of the Crater (rules with "crater": data/rules/crater.json, on top of the
## deathmatch respawns): a zone on the floor (`sim.zone_pos`, `sim.zone_r`) that moves
## every `zone_move_every` ticks through `zone_points`. A side alone inside it scores a
## tick a tick (`score`); first to `score_to_win` ticks wins, or the longer hold at time.
## The rim cracks when the zone lands and chips every `crack_every` ticks while held.
## KOs score nothing.

enum Phase { INTRO, FIGHT, OVER }

const RULES_PATH := "res://data/rules/team.json"
const DEATHMATCH_PATH := "res://data/rules/deathmatch.json"
const SINKHOLE_PATH := "res://data/rules/sinkhole.json"
const CRATER_PATH := "res://data/rules/crater.json"

var sim: MatchSim
var rules: Dictionary
var size := 1  ## creatures per side

var phase: Phase = Phase.INTRO
var phase_t := 0
var timer := 0
var winner := -2  ## -2 undecided, -1 draw, else the winning side
## Team Deathmatch only: the score (KOs each side has scored), each slot's ticks until it
## respawns (-1: not waiting), each slot's spawn protection left, and sudden death.
var deathmatch := false
## Sinkhole only: rings fallen so far, ticks until the next crack or drop, and whether
## the current ring is cracked and waiting to drop.
var sinkhole := false
var ring := 0
var sink_t := 0
var warned := false
## King of the Crater only: which zone point is up and ticks until the zone moves.
var crater := false
var zone_i := 0
var zone_t := 0
var score := [0, 0]
var respawn_t: Array = []
var guard_t: Array = []
var overtime := false


static func load_rules(path := RULES_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if typeof(d) == TYPE_DICTIONARY else {}


## `team_ids` is [[left ids], [right ids]]. `per_side` creatures fight on each side (1 to
## 3; 0: as many as the shorter list), the first ones of each list.
func _init(team_ids: Array, per_side := 0, p_rules: Dictionary = {}) -> void:
	rules = p_rules if not p_rules.is_empty() else load_rules()
	sim = MatchSim.new()
	sim.set_arena(String(rules.get("arena", MatchFactory.arena)))
	var most := mini((team_ids[0] as Array).size(), (team_ids[1] as Array).size())
	size = clampi(per_side if per_side > 0 else most, 1, mini(3, most))
	for side in 2:
		for k in size:
			var c := sim.add_creature(MatchFactory.load_def(String(team_ids[side][k])),
				spawn_point(side, k, size, float(rules.get("spawn_spread", 60))))
			c.team = side
			c.facing = Vector2.RIGHT if side == 0 else Vector2.LEFT
	timer = int(float(rules.get("time_seconds", 150)) * SimDefs.TICK_RATE)
	deathmatch = bool(rules.get("deathmatch", false))
	sinkhole = bool(rules.get("sinkhole", false))
	sim.fall_ko = bool(rules.get("fall_ko", false))
	sink_t = int(rules.get("shrink_every", 420))
	crater = bool(rules.get("crater", false))
	if crater:
		zone_t = int(rules.get("zone_move_every", 1200))
		_place_zone(false)
	for i in slot_count():
		respawn_t.append(-1)
		guard_t.append(0)


## Team Deathmatch: where slot k of a side respawns, on its pad against its own side wall
## (stacked up and down it like the start).
func pad_point(side: int, k: int) -> Vector2:
	var fl := SimDefs.floor_rect()
	var inset := float(rules.get("pad_inset", 44))
	var x := fl.position.x + inset if side == 0 else fl.end.x - inset
	var spread := float(rules.get("pad_spread", 48))
	return Vector2(x, fl.get_center().y + (float(k) - float(size - 1) * 0.5) * spread)


## The KOs a side needs to win (Team Deathmatch).
func score_to_win() -> int:
	var t = rules.get("score_to_win", [8, 8, 12, 15])
	if t is Array:
		return int(t[clampi(size, 0, (t as Array).size() - 1)])
	return int(t)  # the Crater's hold, in ticks


## Where slot k of a side with n starts: stacked up and down the side's spawn point.
func spawn_point(side: int, k: int, n: int, spread := 60.0) -> Vector2:
	var base := sim.spawn(side)
	return sim.terrain.nearest_solid(base + Vector2(0.0, (float(k) - float(n - 1) * 0.5) * spread))


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
	if sinkhole:
		_sinkhole_step()
	if crater and sim.ko_freeze == 0:
		_crater_step()
		if phase != Phase.FIGHT:
			return
	if deathmatch:
		_deathmatch_step()
		return
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


# ------------------------------------------------------------------ team deathmatch

func _deathmatch_step() -> void:
	for slot in slot_count():
		var c := sim.creatures[slot]
		if _down(c) and int(respawn_t[slot]) < 0:
			# Down: a point for the other side (not in the Crater), and back in a few seconds.
			var side := 1 - c.team
			respawn_t[slot] = int(float(rules.get("respawn_seconds", 4)) * SimDefs.TICK_RATE)
			guard_t[slot] = 0
			if not crater:
				score[side] += 1
				sim.emit_event("score", c.pos, float(score[side]), {"who": c.id, "team": side,
					"score": score.duplicate()})
				if score[side] >= score_to_win() or overtime:
					_finish(side, "score")
					return
			sim.slowmo = mini(sim.slowmo, int(rules.get("mid_ko_slowmo", 18)))
		elif int(respawn_t[slot]) > 0:
			if sim.ko_freeze == 0:
				respawn_t[slot] = int(respawn_t[slot]) - 1
			if int(respawn_t[slot]) == 0:
				_respawn(slot)
		elif int(guard_t[slot]) > 0:
			guard_t[slot] = int(guard_t[slot]) - 1
			# Spawn protection ends the moment you attack: it's for getting back in, not
			# for fighting untouchable.
			if c.state == CreatureSim.State.ATTACK:
				guard_t[slot] = 0
				c.invuln = 0
	if timer <= 0 and not overtime:
		if score[0] == score[1]:
			overtime = true  # sudden death: the next KO (or the next tick held) wins
			sim.emit_event("overtime", Vector2.ZERO, 0.0)
		else:
			_finish(0 if score[0] > score[1] else 1, "time")


# ------------------------------------------------------------------ king of the crater

## Where the zone sits now: one of the rules' points, as fractions of the floor.
func _place_zone(moved: bool) -> void:
	var pts: Array = rules.get("zone_points", [[0.5, 0.5]])
	var p: Array = pts[zone_i % pts.size()]
	var fr := SimDefs.floor_rect()
	sim.zone_r = float(rules.get("zone_radius", 40))
	sim.zone_pos = Vector2(fr.position.x + fr.size.x * float(p[0]), fr.position.y + fr.size.y * float(p[1]))
	sim.terrain.crack_circle(sim.zone_pos, sim.zone_r + 6.0)
	if moved:
		sim.emit_event("zone_move", sim.zone_pos, sim.zone_r)


func _in_zone(c: CreatureSim) -> bool:
	return not _down(c) and c.state != CreatureSim.State.FALLING and not c.is_airborne() \
		and c.pos.distance_to(sim.zone_pos) <= sim.zone_r


## The side alone in the zone, or -1.
func zone_holder() -> int:
	var inside := [false, false]
	for c in sim.creatures:
		if _in_zone(c):
			inside[c.team] = true
	if inside[0] == inside[1]:
		return -1
	return 0 if inside[0] else 1


func _crater_step() -> void:
	var holder := zone_holder()
	if holder >= 0:
		score[holder] += 1
		if int(score[holder]) % int(rules.get("crack_every", 45)) == 0:
			# The ground gives under the fight: a cell of the rim, round and round.
			var k := int(score[holder]) / int(rules.get("crack_every", 45))
			var d := SimDefs.aim_dirs()[(k * 11) % SimDefs.AIM_STEPS]
			sim.terrain.damage_cell(sim.terrain.world_to_cell(sim.zone_pos + d * (sim.zone_r + 4.0)), 1)
		if int(score[holder]) >= score_to_win() or overtime:
			_finish(holder, "hold")
			return
	zone_t -= 1
	if zone_t <= 0:
		zone_i += 1
		zone_t = int(rules.get("zone_move_every", 1200))
		_place_zone(true)


## What the score panels show: seconds held in the Crater, KOs elsewhere.
func score_text(side: int) -> String:
	return str(int(score[side]) / SimDefs.TICK_RATE) if crater else str(int(score[side]))


func goal_text() -> String:
	if overtime:
		return "SUDDEN DEATH"
	return "HOLD %d s" % (score_to_win() / SimDefs.TICK_RATE) if crater else "FIRST TO %d" % score_to_win()


## Sinkhole: the edge cracks, then drops, ring by ring.
func _sinkhole_step() -> void:
	if sim.ko_freeze > 0:
		return
	if ring >= int(rules.get("max_rings", 16)):
		return
	sink_t -= 1
	if sink_t > 0:
		return
	var t := sim.terrain
	if not warned:
		for c in _ring_cells(ring):
			if t.get_cell(c) == TerrainGrid.INTACT:
				t.set_cell(c, TerrainGrid.CRACKED)
		warned = true
		sim.sink_ring = ring
		sink_t = int(rules.get("shrink_warn", 120))
		sim.emit_event("sink_warn", Vector2.ZERO, float(ring), {"ring": ring, "rect": _ring_rect(ring)})
	else:
		for c in _ring_cells(ring):
			t.sink(c)
		warned = false
		sim.sink_ring = -1
		sim.emit_event("sink", Vector2.ZERO, float(ring), {"ring": ring, "rect": _ring_rect(ring)})
		ring += 1
		sink_t = int(rules.get("shrink_every", 420))


func _ring_cells(r: int) -> Array[Vector2i]:
	var t := sim.terrain
	var out: Array[Vector2i] = []
	for x in range(r, t.cols - r):
		out.append(Vector2i(x, r))
		out.append(Vector2i(x, t.rows - 1 - r))
	for y in range(r + 1, t.rows - 1 - r):
		out.append(Vector2i(r, y))
		out.append(Vector2i(t.cols - 1 - r, y))
	return out


## The floor left once ring `r` has gone, in pixels.
func _ring_rect(r: int) -> Rect2:
	var t := sim.terrain
	return Rect2(t.cell_rect(Vector2i(r, r)).position, Vector2((t.cols - 2 * r) * SimDefs.CELL, (t.rows - 2 * r) * SimDefs.CELL))


func _finish(side: int, how: String) -> void:
	winner = side
	_set_phase(Phase.OVER)
	sim.emit_event("duel_over", Vector2.ZERO, 1.0, {"winner": winner, "by": how})


## Back on the team's pad, fresh: full health, nothing left over from before the KO
## (cooldowns, statuses, combo) except the Surge energy.
func _respawn(slot: int) -> void:
	var c := sim.creatures[slot]
	var k := 0
	for o in sim.creatures:
		if o.team == c.team and o.id < c.id:
			k += 1
	var at := sim.terrain.nearest_solid(pad_point(c.team, k))
	var fresh := CreatureSim.new(c.id, c.def, at, c.is_dummy)
	var energy := c.energy
	c.load_state(fresh.save_state())
	c.energy = energy
	c.facing = Vector2.RIGHT if c.team == 0 else Vector2.LEFT
	var protect := int(float(rules.get("spawn_protect_seconds", 2)) * SimDefs.TICK_RATE)
	c.invuln = protect
	guard_t[slot] = protect
	respawn_t[slot] = -1
	sim.emit_event("respawn", c.pos, 0.0, {"who": c.id, "team": c.team})


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
	return {"phase": phase, "phase_t": phase_t, "timer": timer, "winner": winner, "match": sim.snapshot(),
		"score": score.duplicate(), "respawn_t": respawn_t.duplicate(), "guard_t": guard_t.duplicate(),
		"overtime": overtime, "ring": ring, "sink_t": sink_t, "warned": warned, "zone_i": zone_i, "zone_t": zone_t}


func restore(s: Dictionary) -> void:
	phase = s["phase"]
	phase_t = int(s["phase_t"])
	timer = int(s["timer"])
	winner = int(s["winner"])
	score = (s["score"] as Array).duplicate()
	respawn_t = (s["respawn_t"] as Array).duplicate()
	guard_t = (s["guard_t"] as Array).duplicate()
	overtime = bool(s["overtime"])
	ring = int(s.get("ring", 0))
	sink_t = int(s.get("sink_t", 0))
	warned = bool(s.get("warned", false))
	zone_i = int(s.get("zone_i", 0))
	zone_t = int(s.get("zone_t", 0))
	sim.restore(s["match"])


func state_digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes([sim.state_digest(), phase, phase_t, timer, winner, score, respawn_t, guard_t,
		overtime, ring, sink_t, warned, zone_i, zone_t]))
	return ctx.finish().hex_encode()


func state_hash() -> int:
	return hash(state_digest())
