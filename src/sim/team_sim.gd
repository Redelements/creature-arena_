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
## and `shrink_warn` ticks later drops into a chasm for good, up to `max_rings`. A ring
## takes `shrink_cols` cells off the left and right and `shrink_rows` off the top and
## bottom, and an axis stops at `min_cols` / `min_rows`, so the last floor is a block,
## not a strip (see ring_rect). A fall into a chasm is a knockout (`fall_ko` on the
## match); a fall into an ordinary hole only hurts. Last side standing wins.
##
## King of the Crater (rules with "crater": data/rules/crater.json, on top of the
## deathmatch respawns): a zone on the floor (`sim.zone_pos`, `sim.zone_r`) that moves
## every `zone_move_every` ticks through `zone_points`. A side alone inside it scores a
## tick a tick (`score`); first to `score_to_win` ticks wins, or the longer hold at time.
## The rim cracks when the zone lands and chips every `crack_every` ticks while held.
## KOs score nothing.
##
## Caravan (rules with "caravan": data/rules/caravan.json, on top of the deathmatch
## respawns, on a map with a "track"): a caravan rides the track, a polyline of floor
## points from side 0's end to side 1's. Two rounds: in round 0 side 0 attacks from the
## track's start, in round 1 side 1 attacks from its end. Within `radius` of the caravan,
## attackers alone push it (`push_speed` px a tick, times `push_mult` by how many), both
## sides stop it, defenders alone roll it back (`back_speed`), never behind the last
## checkpoint passed. Checkpoints (`checkpoints`, shares of the track) add
## `checkpoint_seconds` to the clock and move the attackers' respawn up to them. At time
## out a round goes on while an attacker is at the caravan (up to `overtime_seconds`).
## Round 1 stops as soon as it is decided: past round 0's distance, or slower than round
## 0's finish. The winner finished faster, or pushed further. KOs score nothing.
##
## Capture the Flag (rules with "ctf": data/rules/ctf.json, on top of the deathmatch
## respawns): each side's flag stands on its base (the map's "bases"). A fighter touching
## the other side's flag (within `pickup_radius` of it plus its body) takes it; a carrier
## is slowed (`carry_slow`) and drops it where it goes down or falls. A dropped flag goes
## home when one of its own side touches it, or by itself after `return_seconds`. A
## carrier who reaches its own base while its own flag is home scores a capture (`score`);
## first to `captures_to_win` wins, or more at time, and a tie at time is sudden death
## (the next capture). Every tick the rules give each fighter a goal (`sim.goals`) for the
## CPU: the carrier runs home, the first `defenders` of a side guard its base, the rest go
## for the enemy flag or escort its carrier, and anyone goes after their own flag when it's
## taken. KOs score nothing.
##
## On top of that (all tuned in ctf.json): a hard hit on the carrier (launched, knocked
## down, guard broken or stunned stiff, swallowed) knocks the flag loose a few steps
## (`fumble_pop`), and the carrier can pass it (a fresh press of TAG): it flies to the
## teammate it's aimed at (within `pass_range`, inside `pass_cone`), or that far along the
## aim. A flag in the air (FLAG_THROWN) can be caught in its second half (`catch_from`) by
## anyone but the fighter it left: a teammate of that fighter carries it on, one of the
## flag's own side sends it home (an interception); uncaught, it lands as a dropped flag.
## While a side's own flag is away its fighters respawn faster (`respawn_seconds_flag_away`),
## in sudden death the carrier isn't slowed (`overtime_carry_slow`), and a capture plays
## a moment of slow motion (`capture_slowmo`). Shrines (the map's "shrines", the rules'
## "shrines"): a side alone in one for `claim_seconds` claims it, which gives every one of
## its fighters standing a buff for `buff_seconds` (haste: walking `haste_mult`; might:
## damage `might_mult`); then it's spent for `cooldown_seconds`. Both sides in one hold the
## claim where it is; the other side alone wears it down twice as fast.

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
## Caravan only: the round (0: side 0 attacks), the caravan's progress (px from the
## attackers' start), checkpoints passed, ticks into the round, overtime ticks used, what
## it is doing (-1 rolling back, 0 still, 1 pushed, 2 contested), and per side the best
## distance it pushed and the ticks it took to finish (-1: didn't).
var caravan := false
var cv_round := 0
var cv_p := 0.0
var cv_cp := 0
var cv_t := 0
var cv_ot := 0
var cv_state := 0
var cv_best := [0.0, 0.0]
var cv_time := [-1, -1]
## The track (from the map, fixed for the match): its points and the distance along it
## to each one.
var _track: Array[Vector2] = []
var _track_at: Array[float] = []
## Capture the Flag only: per side (whose flag) its position, state (FLAG_HOME, FLAG_CARRIED,
## FLAG_DROPPED), carrier slot (-1) and ticks until a dropped flag goes home.
var ctf := false
var flag_pos := [Vector2.ZERO, Vector2.ZERO]
var flag_state := [0, 0]
var flag_carrier := [-1, -1]
var flag_t := [0, 0]
const FLAG_HOME := 0
const FLAG_CARRIED := 1
const FLAG_DROPPED := 2
const FLAG_THROWN := 3
## A flag in the air (FLAG_THROWN: passed, or knocked loose): where it left and where it
## lands, ticks flown and ticks the flight takes, the fighter it left (-1) and ticks
## that fighter can't touch it.
var flag_from := [Vector2.ZERO, Vector2.ZERO]
var flag_to := [Vector2.ZERO, Vector2.ZERO]
var flag_ft := [0, 0]
var flag_fn := [1, 1]
var flag_by := [-1, -1]
var flag_lock := [0, 0]
## Each slot's input last tick (a pass is a fresh press of TAG).
var prev_in: Array = []
## The map's shrines (Capture the Flag with "shrines" rules): per shrine [the side
## claiming it (-1), ticks claimed, ticks until it's ready again].
var shrines: Array = []


## The rules a mode id names ("" is the plain team battle), for the menus and the net.
const RULE_IDS := ["", "deathmatch", "sinkhole", "crater", "caravan", "ctf"]
const RULE_NAMES := ["Team battle", "Team Deathmatch", "Sinkhole", "King of the Crater", "Caravan", "Capture the Flag"]
const CARAVAN_PATH := "res://data/rules/caravan.json"
const CTF_PATH := "res://data/rules/ctf.json"


static func rules_by_id(id: String) -> Dictionary:
	match id:
		"deathmatch": return load_rules(DEATHMATCH_PATH)
		"sinkhole": return load_rules(SINKHOLE_PATH)
		"crater": return load_rules(CRATER_PATH)
		"caravan": return load_rules(CARAVAN_PATH)
		"ctf": return load_rules(CTF_PATH)
	return {}


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
	size = clampi(per_side if per_side > 0 else most, 1, mini(int(rules.get("max_size", 3)), most))
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
		prev_in.append(0)
	caravan = bool(rules.get("caravan", false))
	if caravan:
		_load_track()
		_cv_start_round(0)
	ctf = bool(rules.get("ctf", false))
	if ctf:
		for side in 2:
			flag_pos[side] = base_of(side)
		var sr: Dictionary = rules.get("shrines", {})
		if not sr.is_empty():
			for sd in sim.arena.get("shrines", []):
				shrines.append([-1, 0, int(float(sr.get("first_seconds", 15)) * SimDefs.TICK_RATE)])
		_ctf_goals()


## Team Deathmatch: where slot k of a side respawns, on its pad against its own side wall
## (stacked up and down it like the start).
func pad_point(side: int, k: int) -> Vector2:
	if caravan and side == cv_attacker():
		return _cv_respawn_point(k)
	var fl := sim.floor_rect()
	var inset := float(rules.get("pad_inset", 44))
	var x := fl.position.x + inset if side == 0 else fl.end.x - inset
	var spread := float(rules.get("pad_spread", 48))
	return Vector2(x, fl.get_center().y + (float(k) - float(size - 1) * 0.5) * spread)


## The KOs a side needs to win (Team Deathmatch); captures in Capture the Flag.
func score_to_win() -> int:
	if ctf:
		return int(rules.get("captures_to_win", 3))
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
	var pressed := PackedInt32Array()
	pressed.resize(slot_count())
	for i in slot_count():
		pressed[i] = ins[i] & ~int(prev_in[i])
		prev_in[i] = ins[i]
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
	if caravan and sim.ko_freeze == 0:
		_caravan_step()
		if phase != Phase.FIGHT:
			return
	if ctf and sim.ko_freeze == 0:
		_ctf_step(ins, pressed)
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
			var wait := float(rules.get("respawn_seconds", 4))
			if ctf and int(flag_state[c.team]) != FLAG_HOME and rules.has("respawn_seconds_flag_away"):
				wait = float(rules["respawn_seconds_flag_away"])  # a comeback: back sooner while your flag is away
			respawn_t[slot] = int(wait * SimDefs.TICK_RATE)
			guard_t[slot] = 0
			if not crater and not caravan and not ctf:  # objective modes score objectives, not KOs
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
	if timer <= 0 and not overtime and not caravan:
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
	var fr := sim.floor_rect()
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


## What the score panels show: seconds held in the Crater, the share of the track pushed
## in the Caravan, KOs elsewhere.
func score_text(side: int) -> String:
	if caravan:
		if side != cv_attacker() and cv_round <= side:
			return "-"  # hasn't had its push yet
		if int(cv_time[side]) >= 0:
			return "%d s" % (int(cv_time[side]) / SimDefs.TICK_RATE)
		return "%d%%" % roundi(100.0 * float(cv_best[side]) / maxf(track_length(), 1.0))
	return str(int(score[side]) / SimDefs.TICK_RATE) if crater else str(int(score[side]))


func goal_text() -> String:
	if caravan:
		if cv_ot > 0:
			return "OVERTIME"
		return "ROUND %d: %s PUSHES" % [cv_round + 1, "RED" if cv_attacker() == 0 else "BLUE"]
	if overtime:
		return "SUDDEN DEATH"
	if ctf:
		return "FIRST TO %d CAPTURES" % score_to_win()
	if crater:
		return "HOLD %d s" % (score_to_win() / SimDefs.TICK_RATE)
	return "FIRST TO %d" % score_to_win()


## Sinkhole: the edge cracks, then drops, ring by ring.
func _sinkhole_step() -> void:
	if sim.ko_freeze > 0:
		return
	if ring >= int(rules.get("max_rings", 16)) or ring_rect(ring) == ring_rect(ring - 1):
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
		sim.sink_safe = ring_rect(ring)
		sink_t = int(rules.get("shrink_warn", 120))
		sim.emit_event("sink_warn", Vector2.ZERO, float(ring), {"ring": ring, "rect": _ring_rect(ring)})
	else:
		for c in _ring_cells(ring):
			t.sink(c)
		warned = false
		sim.sink_ring = -1
		sim.sink_safe = Rect2i()
		sim.emit_event("sink", Vector2.ZERO, float(ring), {"ring": ring, "rect": _ring_rect(ring)})
		ring += 1
		sink_t = int(rules.get("shrink_every", 420))


## The floor left (in cells) once rings 0..r have dropped; r = -1 is the whole grid.
## Each ring takes `shrink_cols` cells off the left and the right and `shrink_rows` off
## the top and the bottom, and an axis stops once it is down to `min_cols` / `min_rows`.
func ring_rect(r: int) -> Rect2i:
	var t := sim.terrain
	var n := r + 1
	var ix := mini(n * int(rules.get("shrink_cols", 1)), maxi(0, (t.cols - int(rules.get("min_cols", 0))) / 2))
	var iy := mini(n * int(rules.get("shrink_rows", 1)), maxi(0, (t.rows - int(rules.get("min_rows", 0))) / 2))
	return Rect2i(ix, iy, t.cols - 2 * ix, t.rows - 2 * iy)


## The cells ring `r` drops: on the floor before it, off the floor after it.
func _ring_cells(r: int) -> Array[Vector2i]:
	var before := ring_rect(r - 1)
	var after := ring_rect(r)
	var out: Array[Vector2i] = []
	for y in range(before.position.y, before.end.y):
		for x in range(before.position.x, before.end.x):
			if not after.has_point(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


## The floor left once ring `r` has dropped, in pixels (the events' `rect`).
func _ring_rect(r: int) -> Rect2:
	var c := ring_rect(r)
	return Rect2(sim.terrain.cell_rect(c.position).position, Vector2(c.size * SimDefs.CELL))


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


# ------------------------------------------------------------------ caravan

func _load_track() -> void:
	_track.clear()
	_track_at.clear()
	var total := 0.0
	for pt in sim.arena.get("track", []):
		var v := Vector2(float(pt[0]), float(pt[1]))
		if not _track.is_empty():
			total += _track[_track.size() - 1].distance_to(v)
		_track.append(v)
		_track_at.append(total)
	if _track.size() < 2:  # a map with no track: a straight run between the spawns
		_track = [sim.spawn(0), sim.spawn(1)]
		_track_at = [0.0, sim.spawn(0).distance_to(sim.spawn(1))]


func track_length() -> float:
	return _track_at[_track_at.size() - 1] if not _track_at.is_empty() else 0.0


## The point `d` px along the track from its start (side 0's end).
func track_point(d: float) -> Vector2:
	d = clampf(d, 0.0, track_length())
	for i in range(1, _track.size()):
		if d <= _track_at[i] or i == _track.size() - 1:
			var seg := _track_at[i] - _track_at[i - 1]
			var k := (d - _track_at[i - 1]) / seg if seg > 0.0 else 0.0
			return _track[i - 1].lerp(_track[i], k)
	return _track[0]


## The way the track runs at `d` px along it (from side 0's end toward side 1's).
func track_dir(d: float) -> Vector2:
	d = clampf(d, 0.0, track_length())
	for i in range(1, _track.size()):
		if d <= _track_at[i] or i == _track.size() - 1:
			return (_track[i] - _track[i - 1]).normalized()
	return Vector2.RIGHT


## The side pushing this round.
func cv_attacker() -> int:
	return cv_round


## How far along the track (from side 0's end) a progress of `p` from the attackers'
## start is.
func _cv_d(p: float) -> float:
	return p if cv_attacker() == 0 else track_length() - p


func caravan_pos() -> Vector2:
	return track_point(_cv_d(cv_p))


## The way the caravan is headed (toward the defenders' end).
func caravan_heading() -> Vector2:
	var d := track_dir(_cv_d(cv_p))
	return d if cv_attacker() == 0 else -d


## Progress of each checkpoint, in px from the attackers' start.
func checkpoint_at(i: int) -> float:
	var cps: Array = rules.get("checkpoints", [])
	return float(cps[i]) * track_length() if i < cps.size() else INF


func _near_caravan(c: CreatureSim) -> bool:
	return not _down(c) and c.state != CreatureSim.State.FALLING \
		and c.pos.distance_to(caravan_pos()) <= float(rules.get("radius", 56))


## How many of each side are at the caravan.
func caravan_counts() -> Array:
	var n := [0, 0]
	for c in sim.creatures:
		if _near_caravan(c):
			n[c.team] += 1
	return n


func _caravan_step() -> void:
	var att := cv_attacker()
	var n := caravan_counts()
	var a := int(n[att])
	var d := int(n[1 - att])
	var floor_p := checkpoint_at(cv_cp - 1) if cv_cp > 0 else 0.0
	if a > 0 and d == 0:
		var mult: Array = rules.get("push_mult", [1.0, 1.0, 1.2, 1.35])
		cv_p += float(rules.get("push_speed", 0.26)) * float(mult[mini(a, mult.size() - 1)])
		cv_state = 1
	elif a > 0:
		cv_state = 2
	elif d > 0:
		cv_p = maxf(floor_p, cv_p - float(rules.get("back_speed", 0.1)))
		cv_state = -1
	else:
		cv_state = 0
	cv_p = minf(cv_p, track_length())
	cv_t += 1
	while cv_p >= checkpoint_at(cv_cp):
		cv_cp += 1
		timer += int(float(rules.get("checkpoint_seconds", 30)) * SimDefs.TICK_RATE)
		sim.emit_event("checkpoint", caravan_pos(), float(cv_cp), {"team": att})
	cv_best[att] = maxf(float(cv_best[att]), cv_p)
	sim.zone_pos = caravan_pos()
	sim.zone_r = float(rules.get("radius", 56))
	if cv_p >= track_length():
		cv_time[att] = cv_t
		sim.emit_event("caravan_done", caravan_pos(), float(cv_t), {"team": att})
		_cv_end_round()
		return
	if cv_round == 1:
		# Decided early: past round 0's push, or already slower than its finish.
		if int(cv_time[0]) >= 0 and cv_t >= int(cv_time[0]):
			_cv_end_round()
			return
		if int(cv_time[0]) < 0 and cv_p > float(cv_best[0]) + 0.5:
			_cv_end_round()
			return
	if timer <= 0:
		var ot_max := int(float(rules.get("overtime_seconds", 20)) * SimDefs.TICK_RATE)
		if a > 0 and cv_ot < ot_max:
			cv_ot += 1  # overtime: it goes on while an attacker is at the caravan
		else:
			_cv_end_round()


func _cv_end_round() -> void:
	if cv_round == 0:
		_cv_start_round(1)
		return
	var w := -1
	var t0 := int(cv_time[0])
	var t1 := int(cv_time[1])
	if t0 >= 0 and t1 >= 0:
		w = 0 if t0 < t1 else (1 if t1 < t0 else -1)
	elif t0 >= 0 or t1 >= 0:
		w = 0 if t0 >= 0 else 1
	else:
		var b0 := float(cv_best[0])
		var b1 := float(cv_best[1])
		w = 0 if b0 > b1 + 0.5 else (1 if b1 > b0 + 0.5 else -1)
	if w < 0:
		winner = -1
		_set_phase(Phase.OVER)
		sim.emit_event("duel_over", Vector2.ZERO, 1.0, {"winner": -1, "by": "caravan"})
	else:
		_finish(w, "caravan")


## A round starts: the caravan at the attackers' end, everyone back at their own end,
## fresh, the clock reset; then the intro countdown.
func _cv_start_round(r: int) -> void:
	cv_round = r
	cv_p = 0.0
	cv_cp = 0
	cv_t = 0
	cv_ot = 0
	cv_state = 0
	timer = int(float(rules.get("round_seconds", 120)) * SimDefs.TICK_RATE)
	sim.zone_pos = caravan_pos()
	sim.zone_r = float(rules.get("radius", 56))
	if r > 0:
		for slot in slot_count():
			var c := sim.creatures[slot]
			var k := 0
			for o in sim.creatures:
				if o.team == c.team and o.id < c.id:
					k += 1
			var fresh := CreatureSim.new(c.id, c.def, spawn_point(c.team, k, size, float(rules.get("spawn_spread", 60))), c.is_dummy)
			var energy := c.energy
			c.load_state(fresh.save_state())
			c.energy = energy
			c.facing = Vector2.RIGHT if c.team == 0 else Vector2.LEFT
			respawn_t[slot] = -1
			guard_t[slot] = 0
		sim.projectiles.clear()
		sim.zones.clear()
		sim.storms.clear()
		_set_phase(Phase.INTRO)
	sim.emit_event("caravan_round", caravan_pos(), float(r), {"team": cv_attacker()})


## Where an attacker respawns: beside the track at the last checkpoint passed (the
## attackers' end before the first), stacked across the track.
func _cv_respawn_point(k: int) -> Vector2:
	var p := checkpoint_at(cv_cp - 1) if cv_cp > 0 else 0.0
	var back := float(rules.get("respawn_behind", 70))
	var dd := _cv_d(maxf(0.0, p - back))
	var at := track_point(dd)
	var dir := track_dir(dd)
	var across := Vector2(-dir.y, dir.x)
	var spread := float(rules.get("pad_spread", 48))
	return at + across * (float(k) - float(size - 1) * 0.5) * spread


# ------------------------------------------------------------------ capture the flag

## Where a side's flag stands: the map's "bases" (floor pixels), else its pad row's middle.
func base_of(side: int) -> Vector2:
	var b: Dictionary = sim.arena.get("bases", {})
	var key := "left" if side == 0 else "right"
	if b.has(key):
		var v: Array = b[key]
		return Vector2(float(v[0]), float(v[1]))
	var fl := sim.floor_rect()
	var inset := float(rules.get("pad_inset", 44)) + 24.0
	return Vector2(fl.position.x + inset if side == 0 else fl.end.x - inset, fl.get_center().y)


func _touches_flag(c: CreatureSim, side: int) -> bool:
	return not _down(c) and c.state != CreatureSim.State.FALLING \
		and c.pos.distance_to(flag_pos[side]) <= float(rules.get("pickup_radius", 14)) + float(c.radius)


## Whether `c` can pick up (or send home) flag `side` now: touching it, on its feet (not
## launched, knocked down, stunned stiff or swallowed), and not the fighter it just left.
func _may_touch(c: CreatureSim, side: int) -> bool:
	if not _touches_flag(c, side) or c.swallow_t > 0:
		return false
	if c.state in [CreatureSim.State.AIRBORNE, CreatureSim.State.KNOCKDOWN, CreatureSim.State.CRUMPLE]:
		return false
	return not (c.id == int(flag_by[side]) and int(flag_lock[side]) > 0)


## A hit hard enough to knock the flag loose: the carrier launched, knocked down, guard
## broken or stunned stiff (crumpled), or swallowed.
func _hard_hit(c: CreatureSim) -> bool:
	return c.swallow_t > 0 or c.state in [CreatureSim.State.AIRBORNE, CreatureSim.State.KNOCKDOWN,
		CreatureSim.State.CRUMPLE]


func _flag_home(side: int) -> void:
	flag_state[side] = FLAG_HOME
	flag_carrier[side] = -1
	flag_t[side] = 0
	flag_by[side] = -1
	flag_lock[side] = 0
	flag_pos[side] = base_of(side)


func _ctf_step(ins := PackedInt32Array(), pressed := PackedInt32Array()) -> void:
	for side in 2:
		if int(flag_lock[side]) > 0:
			flag_lock[side] = int(flag_lock[side]) - 1
	for slot in mini(pressed.size(), slot_count()):
		if pressed[slot] & SimDefs.IN_TAG:
			_try_pass(sim.creatures[slot], ins[slot])
	for side in 2:  # side: whose flag
		match int(flag_state[side]):
			FLAG_CARRIED:
				var c := sim.creatures[int(flag_carrier[side])]
				if _down(c) or c.state == CreatureSim.State.FALLING:
					flag_state[side] = FLAG_DROPPED
					flag_carrier[side] = -1
					flag_t[side] = int(float(rules.get("return_seconds", 12)) * SimDefs.TICK_RATE)
					flag_pos[side] = sim.terrain.nearest_solid(c.pos)
					sim.emit_event("flag_drop", flag_pos[side], 0.0, {"team": side, "who": c.id, "by": c.last_attacker})
				elif bool(rules.get("fumble", false)) and _hard_hit(c):
					_fumble(side, c)
				else:
					flag_pos[side] = c.pos
					var slow_m := float(rules.get("overtime_carry_slow", rules.get("carry_slow", 0.88))) if overtime \
						else float(rules.get("carry_slow", 0.88))
					if slow_m < 1.0 and c.slow <= 1:  # carrying slows you (a real slow already on you wins)
						c.slow = 2
						c.slow_mult = slow_m
			FLAG_THROWN:
				_fly(side)
			FLAG_DROPPED:
				flag_t[side] = int(flag_t[side]) - 1
				if int(flag_t[side]) <= 0:
					_flag_home(side)
					sim.emit_event("flag_return", flag_pos[side], 0.0, {"team": side, "who": -1})
					continue
				for c in sim.creatures:
					if not _may_touch(c, side):
						continue
					if c.team == side:
						_flag_home(side)
						sim.emit_event("flag_return", flag_pos[side], 0.0, {"team": side, "who": c.id})
					else:
						_take_flag(side, c)
					break
			FLAG_HOME:
				for c in sim.creatures:
					if c.team != side and _may_touch(c, side) and _carrying(c) < 0:
						_take_flag(side, c)
						break
	# A capture: a carrier at its own base while its own flag is home.
	for s in 2:
		var other := 1 - s
		if int(flag_state[other]) != FLAG_CARRIED or int(flag_state[s]) != FLAG_HOME:
			continue
		var c := sim.creatures[int(flag_carrier[other])]
		if c.pos.distance_to(base_of(s)) <= float(rules.get("pickup_radius", 14)) + float(c.radius) + 8.0:
			score[s] += 1
			_flag_home(other)
			sim.slowmo = maxi(sim.slowmo, int(rules.get("capture_slowmo", 0)))
			sim.emit_event("capture", c.pos, float(score[s]), {"team": s, "who": c.id, "score": score.duplicate()})
			if int(score[s]) >= score_to_win() or overtime:
				_finish(s, "capture")
				return
	if not shrines.is_empty():
		_shrine_step()
	_ctf_goals()


func _take_flag(side: int, c: CreatureSim, caught := false) -> void:
	flag_state[side] = FLAG_CARRIED
	flag_carrier[side] = c.id
	flag_t[side] = 0
	flag_by[side] = -1
	flag_lock[side] = 0
	flag_pos[side] = c.pos
	sim.emit_event("flag_take", c.pos, 0.0, {"team": side, "who": c.id, "catch": caught})


## The flag `c` carries (its side), or -1.
func _carrying(c: CreatureSim) -> int:
	for side in 2:
		if int(flag_state[side]) == FLAG_CARRIED and int(flag_carrier[side]) == c.id:
			return side
	return -1


## Flag `side` leaves `c` through the air to land at `to` in `ticks`; `c` can't touch it
## for `lock` ticks.
func _throw(side: int, c: CreatureSim, to: Vector2, ticks: int, lock: int) -> void:
	flag_state[side] = FLAG_THROWN
	flag_carrier[side] = -1
	flag_t[side] = 0
	flag_from[side] = c.pos
	flag_to[side] = sim.terrain.nearest_solid(to)
	flag_ft[side] = 0
	flag_fn[side] = maxi(1, ticks)
	flag_by[side] = c.id
	flag_lock[side] = lock
	flag_pos[side] = c.pos


## A hard hit knocks the flag loose: it pops out a few steps the way the carrier was hit.
func _fumble(side: int, c: CreatureSim) -> void:
	var dir := c.knock_vel.normalized() if c.knock_vel.length_squared() > 0.01 else -c.facing
	_throw(side, c, c.pos + dir * float(rules.get("fumble_pop", 34)), int(rules.get("fumble_ticks", 18)),
		int(rules.get("fumble_lock", 60)))
	sim.emit_event("flag_fumble", c.pos, 0.0, {"team": side, "who": c.id, "by": c.last_attacker})


## TAG while carrying, on your feet: the flag flies to the teammate you aim at (or face),
## leading them, or `pass_range` x 0.7 along the aim when nobody is that way.
func _try_pass(c: CreatureSim, bits: int) -> void:
	var side := _carrying(c)
	if side < 0 or not (c.state in [CreatureSim.State.IDLE, CreatureSim.State.MOVE, CreatureSim.State.GUARD]):
		return
	var aim := SimDefs.aim_from_bits(bits)
	if aim == Vector2.ZERO:
		aim = c.facing
	var reach := float(rules.get("pass_range", 150))
	var speed := float(rules.get("pass_speed", 4.5))
	var best: CreatureSim = null
	var best_dot := float(rules.get("pass_cone", 0.7))
	for o in members(c.team):
		var m := o as CreatureSim
		if m == c or _down(m) or m.state == CreatureSim.State.FALLING:
			continue
		var to := m.pos - c.pos
		var d := to.length()
		if d < 1.0 or d > reach:
			continue
		var dot := to.dot(aim) / d
		if dot > best_dot:
			best_dot = dot
			best = m
	var at := c.pos + aim * reach * 0.7
	if best != null:
		at = best.pos + best.walk_vel * float(ceili(c.pos.distance_to(best.pos) / speed))
	var ticks := maxi(8, ceili(c.pos.distance_to(at) / speed))
	_throw(side, c, at, ticks, ticks + 20)
	sim.emit_event("flag_pass", c.pos, float(ticks), {"team": side, "who": c.id, "to": best.id if best != null else -1})


## A flag in the air: along its flight, catchable in the second half, else it lands.
func _fly(side: int) -> void:
	flag_ft[side] = int(flag_ft[side]) + 1
	var k := float(flag_ft[side]) / float(flag_fn[side])
	flag_pos[side] = (flag_from[side] as Vector2).lerp(flag_to[side], minf(k, 1.0))
	if k >= float(rules.get("catch_from", 0.5)):
		for c in sim.creatures:
			if not _may_touch(c, side):
				continue
			if c.team == side:
				_flag_home(side)
				sim.emit_event("flag_return", flag_pos[side], 0.0, {"team": side, "who": c.id, "intercept": true})
			else:
				_take_flag(side, c, true)
			return
	if int(flag_ft[side]) >= int(flag_fn[side]):
		flag_state[side] = FLAG_DROPPED
		flag_t[side] = int(float(rules.get("return_seconds", 12)) * SimDefs.TICK_RATE)
		flag_pos[side] = flag_to[side]
		sim.emit_event("flag_land", flag_pos[side], 0.0, {"team": side, "who": int(flag_by[side])})


# ------------------------------------------------------------------ shrines

func shrine_pos(i: int) -> Vector2:
	var v: Array = (sim.arena.get("shrines", [])[i] as Dictionary).get("pos", [0, 0])
	return Vector2(float(v[0]), float(v[1]))


func shrine_radius(i: int) -> float:
	return float((sim.arena.get("shrines", [])[i] as Dictionary).get("radius", 22))


func shrine_kind(i: int) -> String:
	return String((sim.arena.get("shrines", [])[i] as Dictionary).get("kind", "haste"))


## How many of each side stand in shrine `i`.
func shrine_counts(i: int) -> Array:
	var n := [0, 0]
	var at := shrine_pos(i)
	var r := shrine_radius(i)
	for c in sim.creatures:
		if not _down(c) and c.state != CreatureSim.State.FALLING and c.pos.distance_to(at) <= r:
			n[c.team] += 1
	return n


func shrine_claim_ticks() -> int:
	return int(float((rules.get("shrines", {}) as Dictionary).get("claim_seconds", 3)) * SimDefs.TICK_RATE)


func _shrine_step() -> void:
	var sr: Dictionary = rules.get("shrines", {})
	var need := shrine_claim_ticks()
	for i in shrines.size():
		var st: Array = shrines[i]
		if int(st[2]) > 0:
			st[2] = int(st[2]) - 1
			if int(st[2]) == 0:
				sim.emit_event("shrine_ready", shrine_pos(i), 0.0, {"shrine": i, "kind": shrine_kind(i)})
			continue
		var n := shrine_counts(i)
		if int(n[0]) > 0 and int(n[1]) > 0:
			continue  # both sides in it: the claim holds where it is
		if int(n[0]) == 0 and int(n[1]) == 0:
			st[1] = maxi(0, int(st[1]) - 1)
		else:
			var who := 0 if int(n[0]) > 0 else 1
			if int(st[0]) == who or int(st[1]) == 0:
				st[0] = who
				st[1] = int(st[1]) + 1
			else:
				st[1] = maxi(0, int(st[1]) - 2)
		if int(st[1]) == 0:
			st[0] = -1
		elif int(st[1]) >= need:
			var side := int(st[0])
			var kind := shrine_kind(i)
			var t := int(float(sr.get("buff_seconds", 20)) * SimDefs.TICK_RATE)
			for o in members(side):
				var c := o as CreatureSim
				if _down(c):
					continue
				if kind == "might":
					c.atk_buff = maxi(c.atk_buff, t)
					c.atk_mult = float(sr.get("might_mult", 1.2))
				else:
					c.haste = maxi(c.haste, t)
					c.haste_mult = float(sr.get("haste_mult", 1.2))
			st[0] = -1
			st[1] = 0
			st[2] = int(float(sr.get("cooldown_seconds", 45)) * SimDefs.TICK_RATE)
			sim.emit_event("shrine", shrine_pos(i), float(t), {"shrine": i, "kind": kind, "team": side})


## The nearest shrine ready to claim, or -1.
func _ready_shrine(c: CreatureSim) -> int:
	var best := -1
	var best_d := INF
	for i in shrines.size():
		if int(shrines[i][2]) > 0:
			continue
		var d := c.pos.distance_to(shrine_pos(i))
		if d < best_d:
			best_d = d
			best = i
	return best


## The carrier's CPU hint: a teammate to pass to (well ahead toward home, in range, with
## no foe on them) while a foe is on the carrier, else -1.
func _pass_hint(c: CreatureSim) -> int:
	var pressed := false
	for o in sim.creatures:
		if c.is_foe(o) and not _down(o) and o.pos.distance_to(c.pos) < 60.0:
			pressed = true
	if not pressed:
		return -1
	var home := base_of(c.team)
	var reach := float(rules.get("pass_range", 150)) * 0.9
	var best := -1
	var best_d := c.pos.distance_to(home) - 50.0
	for o in members(c.team):
		var m := o as CreatureSim
		if m == c or _down(m) or m.state == CreatureSim.State.FALLING or m.pos.distance_to(c.pos) > reach:
			continue
		var safe := true
		for f in sim.creatures:
			if c.is_foe(f) and not _down(f) and f.pos.distance_to(m.pos) < 45.0:
				safe = false
		var d := m.pos.distance_to(home)
		if safe and d < best_d:
			best_d = d
			best = m.id
	return best


## Every fighter's goal for the CPU (sim.goals): see the header. A carrier's goal also
## names a teammate to pass to (-1: none); with three or more a side, its last fighter
## goes for a shrine when one is ready.
func _ctf_goals() -> void:
	sim.goals.resize(sim.creatures.size())
	var defenders := int(rules.get("defenders", 1))
	var k := [0, 0]
	for c in sim.creatures:
		var me := c.team
		var foe := 1 - me
		var role := int(k[me])
		k[me] += 1
		var g: Array = []
		if _down(c):
			g = []
		elif _carrying(c) == foe:
			g = [base_of(me), 6.0, true, _pass_hint(c)]  # run it home
		elif int(flag_state[me]) != FLAG_HOME and (role >= defenders or int(flag_state[me]) != FLAG_CARRIED):
			g = [flag_pos[me], 8.0, false]  # get our flag back
		elif role < defenders and size > 1:
			var toward := (sim.floor_rect().get_center() - base_of(me)).normalized()
			g = [base_of(me) + toward * 48.0, 36.0, false]  # guard the base
		elif role == size - 1 and size >= 3 and _ready_shrine(c) >= 0:
			var si := _ready_shrine(c)
			g = [shrine_pos(si), shrine_radius(si) - 8.0, false]  # claim a shrine
		elif int(flag_state[foe]) == FLAG_CARRIED:
			g = [flag_pos[foe], 44.0, false]  # escort our carrier
		else:
			g = [flag_pos[foe], 6.0, false]  # go take theirs
		sim.goals[c.id] = g


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
		"overtime": overtime, "ring": ring, "sink_t": sink_t, "warned": warned, "zone_i": zone_i, "zone_t": zone_t,
		"cv": [cv_round, cv_p, cv_cp, cv_t, cv_ot, cv_state, cv_best.duplicate(), cv_time.duplicate()],
		"flags": [flag_pos.duplicate(), flag_state.duplicate(), flag_carrier.duplicate(), flag_t.duplicate(),
			flag_from.duplicate(), flag_to.duplicate(), flag_ft.duplicate(), flag_fn.duplicate(), flag_by.duplicate(),
			flag_lock.duplicate()],
		"prev_in": prev_in.duplicate(), "shrines": shrines.duplicate(true)}


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
	var cv: Array = s.get("cv", [0, 0.0, 0, 0, 0, 0, [0.0, 0.0], [-1, -1]])
	cv_round = int(cv[0])
	cv_p = float(cv[1])
	cv_cp = int(cv[2])
	cv_t = int(cv[3])
	cv_ot = int(cv[4])
	cv_state = int(cv[5])
	cv_best = (cv[6] as Array).duplicate()
	cv_time = (cv[7] as Array).duplicate()
	var fl: Array = s.get("flags", [[Vector2.ZERO, Vector2.ZERO], [0, 0], [-1, -1], [0, 0]])
	flag_pos = (fl[0] as Array).duplicate()
	flag_state = (fl[1] as Array).duplicate()
	flag_carrier = (fl[2] as Array).duplicate()
	flag_t = (fl[3] as Array).duplicate()
	if fl.size() > 4:
		flag_from = (fl[4] as Array).duplicate()
		flag_to = (fl[5] as Array).duplicate()
		flag_ft = (fl[6] as Array).duplicate()
		flag_fn = (fl[7] as Array).duplicate()
		flag_by = (fl[8] as Array).duplicate()
		flag_lock = (fl[9] as Array).duplicate()
	if s.has("prev_in"):
		prev_in = (s["prev_in"] as Array).duplicate()
	shrines = (s.get("shrines", []) as Array).duplicate(true)
	sim.restore(s["match"])


func state_digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes([sim.state_digest(), phase, phase_t, timer, winner, score, respawn_t, guard_t,
		overtime, ring, sink_t, warned, zone_i, zone_t, cv_round, cv_p, cv_cp, cv_t, cv_ot, cv_state, cv_best, cv_time,
		flag_pos, flag_state, flag_carrier, flag_t, flag_from, flag_to, flag_ft, flag_fn, flag_by, flag_lock,
		prev_in, shrines]))
	return ctx.finish().hex_encode()


func state_hash() -> int:
	return hash(state_digest())
