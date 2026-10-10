class_name CreatureSim
extends RefCounted
## One creature in the simulation: plain data plus rules. No nodes, no clock, no randomness.
## All tuning comes from the creature's JSON definition in data/creatures/.

enum State { IDLE, MOVE, ATTACK, DODGE, GUARD, HITSTUN, FALLING, KO }

const FALL_TICKS := 45
const FALL_DAMAGE := 8.0
const RESPAWN_INVULN := 40
const DUMMY_RESET_TICKS := 90
const FRICTION := 0.82
const WALL_BOUNCE_MIN := 2.0
const EDGE_TOP := 6.0
const EDGE_BOTTOM := 3.0

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

var state: State = State.IDLE
var state_t := 0  ## ticks spent in the current state
var anim_t := 0  ## ticks since spawn, for idle/run cycles

var move_id := ""
var charging := false
var charge := 0
var charge_ratio := 0.0
var queued_light := false
var hit_ids := {}

var stun := 0
var invuln := 0
var flash := 0
var guard_hit := 0
var combo_hits := 0
var dodge_dir := Vector2.RIGHT
var prev_buttons := 0


func _init(p_id: int, p_def: Dictionary, p_pos: Vector2, p_is_dummy := false) -> void:
	id = p_id
	def = p_def
	pos = p_pos
	is_dummy = p_is_dummy
	max_hp = float(def.get("max_hp", 100))
	hp = max_hp
	max_stamina = float(def.get("stamina", 100))
	stamina = max_stamina
	radius = float(def.get("radius", 10))
	weight = float(def.get("weight", 1.0))


# ------------------------------------------------------------------ queries

func moves() -> Dictionary:
	return def.get("moves", {})


func move_def() -> Dictionary:
	return moves().get(move_id, {})


## A move stat, blended toward its "_charged" value by how long the heavy was held.
func move_value(key: String) -> float:
	var mv := move_def()
	var base := float(mv.get(key, 0.0))
	if mv.has(key + "_charged"):
		return lerpf(base, float(mv[key + "_charged"]), charge_ratio)
	return base


func is_active() -> bool:
	if state != State.ATTACK or charging:
		return false
	var mv := move_def()
	var su := int(mv["startup"])
	return state_t > su and state_t <= su + int(mv["active"])


func hit_center() -> Vector2:
	return pos + facing * float(move_def().get("reach", 12))


func is_invulnerable() -> bool:
	if invuln > 0:
		return true
	if state == State.DODGE:
		var dg: Dictionary = def["dodge"]
		return state_t >= int(dg["iframes_start"]) and state_t <= int(dg["iframes_end"])
	return false


func can_be_hit() -> bool:
	return state != State.FALLING and state != State.KO and not is_invulnerable()


## Whether this creature pushes and gets pushed by other bodies.
func is_solid() -> bool:
	return state != State.FALLING and state != State.KO and state != State.DODGE


func is_full_charge() -> bool:
	return charging and charge >= int(move_def().get("charge_max", 1))


# ------------------------------------------------------------------ per-tick update

## Called instead of step() during hitstop, so button presses aren't lost.
func buffer_input(buttons: int) -> void:
	var pressed := buttons & ~prev_buttons
	prev_buttons = buttons
	if state == State.ATTACK and (pressed & SimDefs.IN_LIGHT):
		queued_light = true


func step(buttons: int, sim: MatchSim) -> void:
	var pressed := buttons & ~prev_buttons
	prev_buttons = buttons
	anim_t += 1
	state_t += 1
	if invuln > 0:
		invuln -= 1
	if flash > 0:
		flash -= 1
	if guard_hit > 0:
		guard_hit -= 1
	if state != State.DODGE and state != State.GUARD and state != State.KO:
		stamina = minf(max_stamina, stamina + float(def.get("stamina_regen", 0.5)))

	var dir := SimDefs.dir_from_bits(buttons)
	match state:
		State.IDLE, State.MOVE:
			_update_free(buttons, pressed, dir, sim)
		State.ATTACK:
			_update_attack(buttons, pressed, dir, sim)
		State.DODGE:
			_update_dodge(sim)
		State.GUARD:
			_update_guard(buttons, dir, sim)
		State.HITSTUN:
			stun -= 1
			if stun <= 0:
				combo_hits = 0
				_set_state(State.IDLE)
		State.FALLING:
			if state_t >= FALL_TICKS:
				_land_from_fall(sim)
		State.KO:
			if is_dummy and state_t >= DUMMY_RESET_TICKS:
				hp = max_hp
				stamina = max_stamina
				combo_hits = 0
				invuln = 20
				_set_state(State.IDLE)
	_apply_knockback(sim)


func _update_free(buttons: int, pressed: int, dir: Vector2, sim: MatchSim) -> void:
	var dg: Dictionary = def["dodge"]
	if (pressed & SimDefs.IN_DODGE) and stamina >= float(dg["cost"]):
		stamina -= float(dg["cost"])
		dodge_dir = dir if dir != Vector2.ZERO else facing
		walk_vel = Vector2.ZERO
		_set_state(State.DODGE)
		sim.emit_event("dodge", pos, 0.0)
		return
	if (pressed & SimDefs.IN_LIGHT) and moves().has("light_1"):
		if dir != Vector2.ZERO:
			facing = dir
		_start_attack("light_1")
		return
	if (pressed & SimDefs.IN_HEAVY) and moves().has("heavy"):
		if dir != Vector2.ZERO:
			facing = dir
		_start_attack("heavy")
		charging = true
		charge = 0
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


func _start_attack(id_: String) -> void:
	move_id = id_
	hit_ids.clear()
	queued_light = false
	charging = false
	charge = 0
	charge_ratio = 0.0
	walk_vel = Vector2.ZERO
	_set_state(State.ATTACK)


func _update_attack(buttons: int, pressed: int, dir: Vector2, sim: MatchSim) -> void:
	var mv := move_def()
	if charging:
		if dir != Vector2.ZERO:
			facing = dir  # aim while charging
		if (buttons & SimDefs.IN_HEAVY) and charge < int(mv.get("charge_max", 0)):
			charge += 1
			state_t = 0
			return
		charging = false
		charge_ratio = float(charge) / float(maxi(int(mv.get("charge_max", 1)), 1))

	if pressed & SimDefs.IN_LIGHT:
		queued_light = true
	var su := int(mv["startup"])
	var ac := int(mv["active"])
	var rc := int(mv["recovery"])
	var t := state_t

	var lunge := float(mv.get("lunge", 0.0))
	if t <= su and lunge > 0.0:
		_move(facing * lunge, sim, true)
	if t == su + 1 and mv.has("terrain_radius"):
		_slam(mv, sim)

	var nxt := String(mv.get("next", ""))
	if queued_light and nxt != "" and t >= int(mv.get("cancel_from", su + ac + rc)):
		_start_attack(nxt)
		return
	if t >= su + ac + rc:
		_set_state(State.IDLE)


func _slam(mv: Dictionary, sim: MatchSim) -> void:
	var center := pos + facing * float(mv["reach"])
	var full := charge_ratio >= 1.0
	if full:
		sim.terrain.damage_circle(center, float(mv["terrain_radius_charged"]), float(mv["terrain_core_charged"]))
	else:
		sim.terrain.damage_circle(center, float(mv["terrain_radius"]), -1.0)
	sim.emit_event("slam", center, 1.0 if full else 0.5)


func _update_dodge(sim: MatchSim) -> void:
	var dg: Dictionary = def["dodge"]
	var frames := int(dg["frames"])
	var spd := float(dg["speed"])
	if state_t > frames - 5:
		spd *= 0.4
	_move(dodge_dir * spd, sim, false)
	if state_t >= frames:
		_set_state(State.IDLE)


func _update_guard(buttons: int, dir: Vector2, sim: MatchSim) -> void:
	var foe := sim.nearest_opponent(self)
	if foe != null and foe.pos.distance_squared_to(pos) > 0.0001:
		facing = _snap8(foe.pos - pos)
	if stun > 0:
		stun -= 1
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

## Applies an incoming hit. Returns true when it was blocked.
func receive_hit(attacker: CreatureSim, damage: float, knockback: float, hitstun: int,
		guard_break: bool, sim: MatchSim) -> bool:
	var push := pos - attacker.pos
	push = push.normalized() if push.length_squared() > 0.0001 else attacker.facing
	var gd: Dictionary = def["guard"]

	if state == State.GUARD:
		var facing_attacker := facing.dot(-push) > 0.3
		if facing_attacker and not guard_break:
			hp -= damage * (1.0 - float(gd["reduction"]))
			stamina -= damage * float(gd["drain_per_damage"])
			knock_vel = push * knockback * 0.4 / weight
			guard_hit = 10
			stun = int(hitstun * 0.5)
			if stamina <= 0.0:
				stamina = 0.0
				_enter_hitstun(int(gd["break_stun"]), push * knockback / weight)
				sim.emit_event("guard_break", pos, 1.0)
			_check_ko(sim)
			return true
		if guard_break:
			hitstun += int(float(gd["break_stun"]) * 0.5)
			sim.emit_event("guard_break", pos, 1.0)

	hp -= damage
	combo_hits += 1
	flash = 6
	_enter_hitstun(hitstun, push * knockback / weight)
	_check_ko(sim)
	return false


func _enter_hitstun(ticks: int, kb: Vector2) -> void:
	charging = false
	walk_vel = Vector2.ZERO
	knock_vel = kb
	stun = ticks
	_set_state(State.HITSTUN)


func _check_ko(sim: MatchSim) -> void:
	if hp <= 0.0 and state != State.KO:
		hp = 0.0
		_set_state(State.KO)
		sim.emit_event("ko", pos, 1.0)


func start_fall(sim: MatchSim) -> void:
	knock_vel = Vector2.ZERO
	walk_vel = Vector2.ZERO
	charging = false
	_set_state(State.FALLING)
	sim.emit_event("fall", pos, 0.0)


func _land_from_fall(sim: MatchSim) -> void:
	pos = _clamp_to_floor(sim.terrain.nearest_solid(pos))
	hp -= FALL_DAMAGE
	invuln = RESPAWN_INVULN
	combo_hits = 0
	if hp <= 0.0:
		hp = 0.0
		_set_state(State.KO)
		sim.emit_event("ko", pos, 1.0)
	else:
		_set_state(State.IDLE)
		sim.emit_event("land", pos, 0.0)


# ------------------------------------------------------------------ movement

func _apply_knockback(sim: MatchSim) -> void:
	if knock_vel.length_squared() < 0.0025:
		knock_vel = Vector2.ZERO
		return
	_move(knock_vel, sim, false, true)
	knock_vel *= FRICTION


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
				sim.emit_event("bounce", Vector2(nx, pos.y), absf(knock_vel.x))
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
				sim.emit_event("bounce", Vector2(pos.x, ny), absf(knock_vel.y))
			else:
				knock_vel.y = 0.0
	pos.y = ny


static func _snap8(v: Vector2) -> Vector2:
	var a := snappedf(v.angle(), PI / 4.0)
	var d := Vector2.from_angle(a)
	return Vector2(snappedf(d.x, 0.0001), snappedf(d.y, 0.0001)).normalized()
