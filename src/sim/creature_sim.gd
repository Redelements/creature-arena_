class_name CreatureSim
extends RefCounted
## One creature in the simulation: plain data plus rules. No nodes, no clock, no randomness.
## All tuning comes from the creature's JSON definition in data/creatures/.
##
## Moves have a type (light, heavy, skill, surge). Lights chain into the next light in
## their string; any move that has connected (hit or blocked) can cancel into a move of a
## higher rank. Damage bonuses and limits are applied by MatchSim when a hit lands.
##
## Windups: a move with "windup": N spends N extra frames winding up when it is thrown
## raw (from neutral or guard), so the other player has time to see it coming. Cancelled
## into from a move that connected, it starts at full speed, so combos are unaffected.
## A windup can be interrupted by getting hit, and doesn't move or re-aim the creature
## (charge moves keep charging and aiming through it).

enum State { IDLE, MOVE, ATTACK, DODGE, GUARD, HITSTUN, FALLING, KO, AIRBORNE, CRUMPLE, KNOCKDOWN }

const FALL_TICKS := 45
const FALL_DAMAGE := 8.0
const RESPAWN_INVULN := 40
const DUMMY_RESET_TICKS := 90
const FRICTION := 0.82
const AIR_FRICTION := 0.92
const WALL_BOUNCE_MIN := 2.0
const WALL_BOUNCE_STUN := 12
const EDGE_TOP := 6.0
const EDGE_BOTTOM := 3.0
const BUFFER_TICKS := 10
const MAX_ENERGY := 100.0
const BREAKAWAY_COST := 50.0
const BREAKAWAY_MIN_HITS := 3
const BREAKAWAY_INVULN := 30
const JUGGLE_MAX := 3
const JUGGLE_FLOAT := 16
const LAND_KNOCKDOWN := 24
const GETUP_INVULN := 12
const TAN_22_5 := 0.41421356237309503

## Everything that changes during a match, in a fixed order. snapshot()/restore() copy
## exactly these, which is what rollback netcode saves every frame. A test checks that
## every variable declared below is either listed here or in STATIC_FIELDS.
const STATE_FIELDS := [
	"pos", "walk_vel", "knock_vel", "facing", "hp", "stamina", "energy",
	"state", "state_t", "anim_t",
	"move_id", "attack_serial", "charging", "charge", "charge_ratio", "connected", "seg_hit",
	"cooldowns", "buffered", "buffer_t", "countered", "stack", "stack_t", "windup_left",
	"windup_total", "stun", "invuln", "flash", "guard_hit", "air_t", "air_total",
	"combo_hits", "combo_types", "combo_moves", "combo_bounced", "combo_damage", "juggles",
	"juggle_serials", "last_attacker", "dodge_dir", "prev_buttons", "dodge_buffer",
	"dodge_buffer_dir",
]
## Set once when the creature is made and never changed by the simulation.
const STATIC_FIELDS := ["id", "def", "is_dummy", "radius", "weight", "max_hp", "max_stamina"]

const ACTION_BITS := [
	["surge", SimDefs.IN_SURGE],
	["skill_1", SimDefs.IN_SKILL1],
	["skill_2", SimDefs.IN_SKILL2],
	["heavy", SimDefs.IN_HEAVY],
	["light", SimDefs.IN_LIGHT],
]

var id: int
var def: Dictionary
var is_dummy := false

var pos := Vector2.ZERO
var walk_vel := Vector2.ZERO
var knock_vel := Vector2.ZERO
var facing := Vector2.RIGHT
var radius := 10.0
var weight := 1.0

var hp := 0.0
var max_hp := 0.0
var stamina := 0.0
var max_stamina := 0.0
var energy := 0.0

var state: State = State.IDLE
var state_t := 0  ## ticks spent in the current state
var anim_t := 0  ## ticks since spawn, for idle/run cycles

# Attacking
var move_id := ""
var attack_serial := 0
var charging := false
var charge := 0
var charge_ratio := 0.0
var connected := false
var seg_hit := {}
var cooldowns := {}
var buffered := ""
var buffer_t := 0
var countered := false
var stack := 0
var stack_t := 0
var windup_left := 0  ## raw-move windup frames still to go
var windup_total := 0  ## windup frames this attack started with (0 when cancelled into)

# Being hit
var stun := 0
var invuln := 0
var flash := 0
var guard_hit := 0
var air_t := 0
var air_total := 0
var combo_hits := 0
var combo_types := 0
var combo_moves := {}
var combo_bounced := false
var combo_damage := 0.0
var juggles := 0
var juggle_serials := {}
var last_attacker := -1

var dodge_dir := Vector2.RIGHT
var prev_buttons := 0
var dodge_buffer := 0  ## a dodge pressed during hitstop, kept until it can happen
var dodge_buffer_dir := Vector2.ZERO  ## the direction held when it was pressed


func _init(p_id: int, p_def: Dictionary, p_pos: Vector2, p_is_dummy := false) -> void:
	id = p_id
	def = p_def.duplicate(true)
	pos = p_pos
	is_dummy = p_is_dummy
	max_hp = float(def.get("max_hp", 100))
	hp = max_hp
	max_stamina = float(def.get("stamina", 100))
	stamina = max_stamina
	radius = float(def.get("radius", 10))
	weight = float(def.get("weight", 1.0))
	for mid in moves():
		_normalize_move(String(mid), moves()[mid])


## Fills in each move's type, hit segments and total length so the rest of the code
## can treat single-hit and multi-hit moves the same way.
static func _normalize_move(mid: String, mv: Dictionary) -> void:
	if not mv.has("type"):
		if mid.begins_with("light"):
			mv["type"] = "light"
		elif mid.begins_with("heavy"):
			mv["type"] = "heavy"
		elif mid.begins_with("surge"):
			mv["type"] = "surge"
		else:
			mv["type"] = "skill"
	var su := int(mv.get("startup", 0))
	var ac := int(mv.get("active", 0))
	var segs: Array = []
	if mv.has("hits"):
		for h in mv["hits"]:
			segs.append(h)
	elif ac > 0:
		segs.append({"at": su + 1, "active": ac})
	mv["_segs"] = segs
	if not mv.has("length"):
		mv["length"] = su + ac + int(mv.get("recovery", 0))


# ------------------------------------------------------------------ rollback state

func save_state() -> Dictionary:
	var d := {}
	for f in STATE_FIELDS:
		var v = get(f)
		d[f] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return d


func load_state(d: Dictionary) -> void:
	for f in STATE_FIELDS:
		var v = d[f]
		set(f, v.duplicate(true) if (v is Dictionary or v is Array) else v)


# ------------------------------------------------------------------ queries

func moves() -> Dictionary:
	return def.get("moves", {})


func move_def() -> Dictionary:
	return moves().get(move_id, {})


func move_type() -> String:
	return String(move_def().get("type", ""))


## A move stat, blended toward its "_charged" value by how long the heavy was held.
func move_value(key: String, mv: Dictionary = {}) -> float:
	if mv.is_empty():
		mv = move_def()
	var base := float(mv.get(key, 0.0))
	if mv.has(key + "_charged"):
		return lerpf(base, float(mv[key + "_charged"]), charge_ratio)
	return base


## Index of the hit segment active this tick, or -1.
func active_seg() -> int:
	if state != State.ATTACK or charging:
		return -1
	var segs: Array = move_def().get("_segs", [])
	for i in segs.size():
		var at := int(segs[i]["at"])
		if state_t >= at and state_t < at + int(segs[i]["active"]):
			return i
	return -1


func is_active() -> bool:
	return active_seg() >= 0


## A hit parameter for the given segment: the segment's own value, else the move's.
func seg_value(seg: int, key: String) -> float:
	var segs: Array = move_def().get("_segs", [])
	if seg >= 0 and seg < segs.size() and segs[seg].has(key):
		return float(segs[seg][key])
	return move_value(key)


func hit_center(seg: int = -2) -> Vector2:
	if seg == -2:
		seg = active_seg()
	return pos + facing * seg_value(seg, "reach")


func hit_radius(seg: int = -2) -> float:
	if seg == -2:
		seg = active_seg()
	return seg_value(seg, "hit_radius")


## Everything MatchSim needs to resolve one hit from segment `seg` of the current move.
func hit_params(seg: int) -> Dictionary:
	var mv := move_def()
	return {
		"attacker": id,
		"move_id": move_id,
		"type": String(mv["type"]),
		"serial": attack_serial,
		"damage": seg_value(seg, "damage"),
		"knockback": seg_value(seg, "knockback"),
		"hitstun": seg_value(seg, "hitstun"),
		"hitstop": seg_value(seg, "hitstop"),
		"launch": seg_value(seg, "launch"),
		"crumple": seg_value(seg, "crumple"),
		"knockdown": seg_value(seg, "knockdown"),
		"guard_break": bool(mv.get("guard_break", false)),
		"grab": bool(mv.get("grab", false)),
		"juggle": bool(mv.get("juggle", false)),
		"stack_bonus": float(mv.get("stack_bonus", 0.0)),
	}


func is_invulnerable() -> bool:
	if invuln > 0 or state == State.KNOCKDOWN:
		return true
	if state == State.DODGE:
		var dg: Dictionary = def["dodge"]
		return state_t >= int(dg["iframes_start"]) and state_t <= int(dg["iframes_end"])
	return false


func can_be_hit() -> bool:
	return state != State.FALLING and state != State.KO and not is_invulnerable()


func is_airborne() -> bool:
	return state == State.AIRBORNE


func is_stunned() -> bool:
	return state == State.HITSTUN or state == State.CRUMPLE or state == State.AIRBORNE


## Whether this creature pushes and gets pushed by other bodies.
func is_solid() -> bool:
	return not (state in [State.FALLING, State.KO, State.DODGE, State.AIRBORNE, State.KNOCKDOWN])


func is_full_charge() -> bool:
	return charging and charge >= int(move_def().get("charge_max", 1))


func can_use(mid: String) -> bool:
	var mv: Dictionary = moves().get(mid, {})
	if mv.is_empty():
		return false
	if int(cooldowns.get(mid, 0)) > 0:
		return false
	return energy >= float(mv.get("energy_cost", 0.0))


func cooldown_ratio(mid: String) -> float:
	var mv: Dictionary = moves().get(mid, {})
	var total := float(mv.get("cooldown", 0))
	if total <= 0.0:
		return 0.0
	return float(cooldowns.get(mid, 0)) / total


func is_winding_up() -> bool:
	return state == State.ATTACK and windup_left > 0


## Ticks since the current attack began, counting its windup. A charge held in place
## isn't counted (state_t restarts when the charge is released).
func attack_elapsed() -> int:
	return state_t + windup_total - windup_left


func in_counter_window() -> bool:
	if state != State.ATTACK or countered:
		return false
	var c: Dictionary = move_def().get("counter", {})
	return not c.is_empty() and state_t >= int(c["from"]) and state_t <= int(c["to"])


## Height above the ground while launched, for drawing.
func air_height() -> float:
	if state != State.AIRBORNE or air_total <= 0:
		return 0.0
	var t := float(air_t)
	var tt := float(air_total)
	var peak := clampf(tt * 0.6, 10.0, 28.0)
	return maxf(0.0, 4.0 * peak * t * (tt - t) / (tt * tt))


func move_rank(mid: String) -> int:
	var mv: Dictionary = moves().get(mid, {})
	return int(SimDefs.TYPE_RANK.get(String(mv.get("type", "")), 0))


func action_move(action: String) -> String:
	if action == "light":
		return "light_1"
	return action


# ------------------------------------------------------------------ per-tick update

## Called instead of step() during hitstop, so button presses aren't lost.
func buffer_input(buttons: int, sim: MatchSim) -> void:
	var pressed := buttons & ~prev_buttons
	prev_buttons = buttons
	if is_stunned() and _wants_breakaway(buttons, pressed):
		sim.hitstop = 0
		sim.breakaway(self)
		return
	_buffer_presses(pressed)
	# Without this, a dodge pressed during a freeze (like a Surge's) would be lost.
	if pressed & SimDefs.IN_DODGE:
		dodge_buffer = BUFFER_TICKS
		dodge_buffer_dir = SimDefs.dir_from_bits(buttons)


func _buffer_presses(pressed: int) -> void:
	for a in ACTION_BITS:
		if pressed & int(a[1]):
			buffered = String(a[0])
			buffer_t = BUFFER_TICKS
			return


func step(buttons: int, sim: MatchSim) -> void:
	var pressed := buttons & ~prev_buttons
	prev_buttons = buttons
	_buffer_presses(pressed)
	anim_t += 1
	state_t += 1
	if invuln > 0:
		invuln -= 1
	if flash > 0:
		flash -= 1
	if guard_hit > 0:
		guard_hit -= 1
	for k in cooldowns.keys():
		if int(cooldowns[k]) > 0:
			cooldowns[k] = int(cooldowns[k]) - 1
	if stack > 0:
		stack_t -= 1
		if stack_t <= 0:
			stack = 0
	if not (state in [State.DODGE, State.GUARD, State.KO]):
		stamina = minf(max_stamina, stamina + float(def.get("stamina_regen", 0.5)))

	if is_stunned() and _wants_breakaway(buttons, pressed):
		sim.breakaway(self)
	else:
		var dir := SimDefs.dir_from_bits(buttons)
		match state:
			State.IDLE, State.MOVE:
				_update_free(buttons, pressed, dir, sim)
			State.ATTACK:
				_update_attack(buttons, dir, sim)
			State.DODGE:
				_update_dodge(sim)
			State.GUARD:
				_update_guard(buttons, pressed, dir, sim)
			State.HITSTUN, State.CRUMPLE:
				stun -= 1
				if stun <= 0:
					_recover()
			State.AIRBORNE:
				air_t += 1
				if air_t >= air_total:
					_land(sim)
			State.KNOCKDOWN:
				stun -= 1
				if stun <= 0:
					invuln = GETUP_INVULN
					_recover()
			State.FALLING:
				if state_t >= FALL_TICKS:
					_land_from_fall(sim)
			State.KO:
				if is_dummy and state_t >= DUMMY_RESET_TICKS:
					hp = max_hp
					stamina = max_stamina
					reset_combo()
					invuln = 20
					_set_state(State.IDLE)
	_apply_knockback(sim)

	if buffer_t > 0:
		buffer_t -= 1
		if buffer_t == 0:
			buffered = ""
	if dodge_buffer > 0:
		dodge_buffer -= 1


func _wants_breakaway(buttons: int, pressed: int) -> bool:
	var both := SimDefs.IN_GUARD | SimDefs.IN_DODGE
	return (buttons & both) == both and (pressed & both) != 0 \
		and combo_hits >= BREAKAWAY_MIN_HITS and energy >= BREAKAWAY_COST


func _update_free(buttons: int, pressed: int, dir: Vector2, sim: MatchSim) -> void:
	var dg: Dictionary = def["dodge"]
	if ((pressed & SimDefs.IN_DODGE) or dodge_buffer > 0) and stamina >= float(dg["cost"]):
		_start_dodge(dir, sim)
		return
	if _try_start_buffered(dir, sim):
		return
	if buttons & SimDefs.IN_GUARD:
		walk_vel = Vector2.ZERO
		_set_state(State.GUARD)
		return

	walk_vel = walk_vel.move_toward(dir * float(def["speed"]), float(def["accel"]))
	if dir != Vector2.ZERO:
		facing = dir
		if state != State.MOVE:
			_set_state(State.MOVE)
	elif walk_vel.length() < 0.05 and state != State.IDLE:
		walk_vel = Vector2.ZERO
		_set_state(State.IDLE)
	_move(walk_vel, sim, true)


func _start_dodge(dir: Vector2, sim: MatchSim) -> void:
	var dg: Dictionary = def["dodge"]
	stamina -= float(dg["cost"])
	if dir == Vector2.ZERO and dodge_buffer > 0:
		dir = dodge_buffer_dir
	dodge_buffer = 0
	dodge_dir = dir if dir != Vector2.ZERO else facing
	walk_vel = Vector2.ZERO
	_set_state(State.DODGE)
	sim.emit_event("dodge", pos, 0.0)


## Starts the buffered attack from a neutral state, if it's usable.
func _try_start_buffered(dir: Vector2, sim: MatchSim) -> bool:
	if buffered == "":
		return false
	var mid := action_move(buffered)
	if not can_use(mid):
		return false
	if dir != Vector2.ZERO:
		facing = dir
	_start_attack(mid, sim, true)
	return true


func _start_attack(mid: String, sim: MatchSim, raw := false) -> void:
	move_id = mid
	attack_serial += 1
	seg_hit.clear()
	connected = false
	countered = false
	charge = 0
	charge_ratio = 0.0
	buffered = ""
	buffer_t = 0
	walk_vel = Vector2.ZERO
	var mv := move_def()
	charging = mv.has("charge_max")
	if mv.has("cooldown"):
		cooldowns[mid] = int(mv["cooldown"])
	if mv.has("energy_cost"):
		energy -= float(mv["energy_cost"])
	_set_state(State.ATTACK)
	windup_total = int(mv.get("windup", 0)) if raw else 0
	windup_left = windup_total
	if windup_total > 0:
		sim.emit_event("windup", pos, float(windup_total),
			{"who": id, "move": mid, "tell": String(mv.get("tell", "strong"))})
	if String(mv["type"]) == "surge":
		sim.hitstop = maxi(sim.hitstop, int(mv.get("freeze", 18)))
		sim.emit_event("surge", pos, 1.0, {"who": id, "name": String(mv.get("name", "SURGE"))})


func _update_attack(buttons: int, dir: Vector2, sim: MatchSim) -> void:
	var mv := move_def()
	if windup_left > 0:
		windup_left -= 1
		state_t = 0
		if charging:
			if dir != Vector2.ZERO:
				facing = dir
			if (buttons & SimDefs.IN_HEAVY) and charge < int(mv.get("charge_max", 0)):
				charge += 1
		return
	if charging:
		if dir != Vector2.ZERO:
			facing = dir  # aim while charging
		if (buttons & SimDefs.IN_HEAVY) and charge < int(mv.get("charge_max", 0)):
			charge += 1
			state_t = 0
			return
		charging = false
		charge_ratio = float(charge) / float(maxi(int(mv.get("charge_max", 1)), 1))

	var t := state_t
	var su := int(mv.get("startup", 0))

	# Movement during the move: a short lunge before it hits, or a dash.
	var lunge := float(mv.get("lunge", 0.0))
	if t <= su and lunge > 0.0:
		_move(facing * lunge, sim, true)
	var dash: Dictionary = mv.get("dash", {})
	if not dash.is_empty() and t >= int(dash["from"]) and t <= int(dash["to"]) and not connected:
		_move(facing * float(dash["speed"]), sim, true)

	# One-off effects at the first active tick.
	var segs: Array = mv["_segs"]
	var first_at := int(segs[0]["at"]) if segs.size() > 0 else su + 1
	if t == first_at:
		if mv.has("terrain_radius"):
			_slam(mv, sim)
		if mv.has("terrain_ring"):
			var r: Dictionary = mv["terrain_ring"]
			sim.terrain.damage_ring(pos, float(r["inner"]), float(r["outer"]))
			sim.emit_event("slam", pos, 1.0)
	if mv.has("projectile") and t == su + 1:
		sim.spawn_projectile(self, mv)

	# Cancels: the next light in the string, or any higher rank once this move connected.
	if buffered != "":
		var want := buffered
		if want == "light" and String(mv["type"]) == "light":
			var nxt := String(mv.get("next", ""))
			if nxt != "" and t >= int(mv.get("cancel_from", 9999)):
				_start_attack(nxt, sim)
				return
		else:
			var mid := action_move(want)
			if connected and move_rank(mid) > move_rank(move_id) and can_use(mid):
				if dir != Vector2.ZERO:
					facing = dir
				_start_attack(mid, sim)
				return

	if t >= int(mv["length"]):
		_set_state(State.IDLE)


func _slam(mv: Dictionary, sim: MatchSim) -> void:
	var center := pos + facing * float(mv["reach"])
	var full := charge_ratio >= 1.0
	if full:
		sim.terrain.damage_circle(center, float(mv["terrain_radius_charged"]), float(mv["terrain_core_charged"]))
	else:
		sim.terrain.damage_circle(center, float(mv["terrain_radius"]), -1.0)
	sim.emit_event("slam", center, 1.0 if full else 0.5)


## Called by MatchSim when a strike lands inside this creature's counter window (Slip).
func trigger_counter(attacker_pos: Vector2, sim: MatchSim) -> void:
	var c: Dictionary = move_def()["counter"]
	if attacker_pos.distance_squared_to(pos) > 0.0001:
		facing = _snap8(attacker_pos - pos)
	_start_attack(String(c["move"]), sim)
	countered = true
	invuln = int(c.get("invuln", 12))
	sim.emit_event("slip", pos + Vector2(0, -20), 1.0, {"who": id})


func _update_dodge(sim: MatchSim) -> void:
	var dg: Dictionary = def["dodge"]
	var frames := int(dg["frames"])
	var spd := float(dg["speed"])
	if state_t > frames - 5:
		spd *= 0.4
	_move(dodge_dir * spd, sim, false)
	if state_t >= frames:
		_set_state(State.IDLE)


func _update_guard(buttons: int, pressed: int, dir: Vector2, sim: MatchSim) -> void:
	var foe := sim.nearest_opponent(self)
	if foe != null and foe.pos.distance_squared_to(pos) > 0.0001:
		facing = _snap8(foe.pos - pos)
	if stun > 0:
		stun -= 1
		return
	var dg: Dictionary = def["dodge"]
	if ((pressed & SimDefs.IN_DODGE) or dodge_buffer > 0) and stamina >= float(dg["cost"]):
		_start_dodge(dir, sim)
		return
	if _try_start_buffered(Vector2.ZERO, sim):
		return
	if not (buttons & SimDefs.IN_GUARD):
		_set_state(State.IDLE)
		return
	var gd: Dictionary = def["guard"]
	walk_vel = dir * float(def["speed"]) * float(gd["speed_mult"])
	_move(walk_vel, sim, true)


func _set_state(s: State) -> void:
	state = s
	state_t = 0


# ------------------------------------------------------------------ getting hit

func reset_combo() -> void:
	combo_hits = 0
	combo_types = 0
	combo_moves.clear()
	combo_bounced = false
	combo_damage = 0.0
	juggles = 0
	juggle_serials.clear()


func _recover() -> void:
	stun = 0
	reset_combo()
	_set_state(State.IDLE)


func cancel_attack() -> void:
	charging = false
	windup_left = 0
	connected = false
	buffered = ""
	buffer_t = 0


func enter_hitstun(ticks: int, kb: Vector2) -> void:
	cancel_attack()
	walk_vel = Vector2.ZERO
	knock_vel = kb
	stun = maxi(ticks, 1)
	_set_state(State.HITSTUN)


func enter_crumple(ticks: int, kb: Vector2) -> void:
	cancel_attack()
	walk_vel = Vector2.ZERO
	knock_vel = kb
	stun = maxi(ticks, 1)
	_set_state(State.CRUMPLE)


func enter_air(ticks: int, kb: Vector2) -> void:
	cancel_attack()
	walk_vel = Vector2.ZERO
	knock_vel = kb
	air_t = 0
	air_total = maxi(ticks, 1)
	_set_state(State.AIRBORNE)


func enter_knockdown(ticks: int, kb: Vector2) -> void:
	cancel_attack()
	walk_vel = Vector2.ZERO
	knock_vel = kb
	stun = maxi(ticks, 1)
	_set_state(State.KNOCKDOWN)


## A juggle hit on an airborne target keeps it up a little longer.
func extend_air(extra: int, kb: Vector2) -> void:
	air_total = air_t + maxi(air_total - air_t, extra)
	knock_vel = kb


func _land(sim: MatchSim) -> void:
	sim.emit_event("land_hard", pos, 1.0)
	if hp <= 0.0:
		hp = 0.0
		_set_state(State.KO)
		sim.emit_event("ko", pos, 1.0, {"who": id})
		return
	enter_knockdown(LAND_KNOCKDOWN, knock_vel * 0.3)


## Stamina ran out while guarding: the guard shatters and the creature crumples.
func break_guard(sim: MatchSim) -> void:
	stamina = 0.0
	var gd: Dictionary = def["guard"]
	enter_crumple(int(gd["break_stun"]), knock_vel)
	sim.emit_event("guard_break", pos, 1.0)


func check_ko(sim: MatchSim) -> void:
	if hp <= 0.0 and state != State.KO:
		hp = 0.0
		if state == State.AIRBORNE:
			return  # finishes the fall first, then lands KO'd
		cancel_attack()
		_set_state(State.KO)
		sim.emit_event("ko", pos, 1.0, {"who": id})


func start_fall(sim: MatchSim) -> void:
	knock_vel = Vector2.ZERO
	walk_vel = Vector2.ZERO
	cancel_attack()
	_set_state(State.FALLING)
	sim.emit_event("fall", pos, 0.0)


func _land_from_fall(sim: MatchSim) -> void:
	pos = _clamp_to_floor(sim.terrain.nearest_solid(pos))
	hp -= FALL_DAMAGE
	invuln = RESPAWN_INVULN
	reset_combo()
	if hp <= 0.0:
		hp = 0.0
		_set_state(State.KO)
		sim.emit_event("ko", pos, 1.0, {"who": id})
	else:
		_set_state(State.IDLE)
		sim.emit_event("land", pos, 0.0)


# ------------------------------------------------------------------ movement

func _apply_knockback(sim: MatchSim) -> void:
	if knock_vel.length_squared() < 0.0025:
		knock_vel = Vector2.ZERO
		return
	_move(knock_vel, sim, false, true)
	knock_vel *= AIR_FRICTION if state == State.AIRBORNE else FRICTION


func floor_min() -> Vector2:
	return Vector2(SimDefs.GRID_X + radius, SimDefs.GRID_Y + EDGE_TOP)


func floor_max() -> Vector2:
	return Vector2(
		SimDefs.GRID_X + SimDefs.GRID_COLS * SimDefs.CELL - radius,
		SimDefs.GRID_Y + SimDefs.GRID_ROWS * SimDefs.CELL - EDGE_BOTTOM)


func _clamp_to_floor(p: Vector2) -> Vector2:
	return p.clamp(floor_min(), floor_max())


func clamp_to_floor() -> void:
	pos = _clamp_to_floor(pos)


## Moves one axis at a time. Voluntary movement (walking) refuses to step into a hole;
## knockback and dodges don't, which is how creatures end up falling in.
func _move(delta: Vector2, sim: MatchSim, voluntary: bool, bounce := false) -> void:
	var lo := floor_min()
	var hi := floor_max()
	var standing_on_hole := sim.terrain.is_hole_at(pos)

	var nx := pos.x + delta.x
	if voluntary and not standing_on_hole and sim.terrain.is_hole_at(Vector2(nx, pos.y)):
		nx = pos.x
	if nx < lo.x or nx > hi.x:
		nx = clampf(nx, lo.x, hi.x)
		if bounce:
			if absf(knock_vel.x) >= WALL_BOUNCE_MIN:
				knock_vel.x = -knock_vel.x * 0.6
				_on_wall_bounce(sim, Vector2(nx, pos.y), absf(knock_vel.x))
			else:
				knock_vel.x = 0.0
	pos.x = nx

	var ny := pos.y + delta.y
	if voluntary and not standing_on_hole and sim.terrain.is_hole_at(Vector2(pos.x, ny)):
		ny = pos.y
	if ny < lo.y or ny > hi.y:
		ny = clampf(ny, lo.y, hi.y)
		if bounce:
			if absf(knock_vel.y) >= WALL_BOUNCE_MIN:
				knock_vel.y = -knock_vel.y * 0.6
				_on_wall_bounce(sim, Vector2(pos.x, ny), absf(knock_vel.y))
			else:
				knock_vel.y = 0.0
	pos.y = ny


## The first wall bounce in a combo adds stun, which is what makes it a combo extender.
func _on_wall_bounce(sim: MatchSim, at: Vector2, power: float) -> void:
	if not combo_bounced and (state == State.HITSTUN or state == State.CRUMPLE):
		combo_bounced = true
		stun += WALL_BOUNCE_STUN
	sim.emit_event("bounce", at, power)


## Snaps a direction to the nearest of 8. Uses only comparisons and one square root
## (no sin/cos/atan2), because trig functions can round differently on different
## platforms and online play needs every machine to compute identical results.
static func _snap8(v: Vector2) -> Vector2:
	if v.length_squared() < 1e-12:
		return Vector2.RIGHT
	var ax := absf(v.x)
	var ay := absf(v.y)
	if ay <= ax * TAN_22_5:
		return Vector2(signf(v.x), 0.0)
	if ax <= ay * TAN_22_5:
		return Vector2(0.0, signf(v.y))
	return Vector2(signf(v.x), signf(v.y)).normalized()
