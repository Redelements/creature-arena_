class_name MouseOrders
extends RefCounted
## League-style mouse controls, turned into the same input bitmask a gamepad produces.
##
##   Right-click ground    walk to that spot (hold to keep steering)
##   Right-click opponent  walk into range and keep attacking (auto-attack)
##   A / left-click        light attack toward the cursor
##   Q / W                 Skill 1 / Skill 2 toward the cursor
##   E (hold)              heavy, aimed at the cursor while charging
##   R                     Surge
##   D                     dodge roll toward the cursor
##   F (hold)              guard;  D + F while stunned = breakaway
##   S                     stop
##
## The simulation only understands 8 directions, so aiming snaps to the nearest of 8.
## This class is pure logic (no Input calls), so tests can drive it directly.

const ARRIVE := 2.5  ## close enough to a move destination to stop
const AIM_HOLD := 10  ## ticks to keep aiming at the cursor after a press (matches the input buffer)
const STUCK_TICKS := 12

const PRESS_BITS := {
	"attack": SimDefs.IN_LIGHT,
	"heavy": SimDefs.IN_HEAVY,
	"skill_1": SimDefs.IN_SKILL1,
	"skill_2": SimDefs.IN_SKILL2,
	"surge": SimDefs.IN_SURGE,
}

var dest := Vector2.INF  ## current move destination, or INF for none
var chase := false  ## auto-attacking the opponent
var aim_t := 0
var aim_point := Vector2.ZERO
## Set when a new order is given, so the view can draw a click marker: {"pos", "attack"}.
var ping := {}

var _prev := 0
var _last_pos := Vector2.INF
var _stuck := 0


func clear() -> void:
	dest = Vector2.INF
	chase = false
	aim_t = 0


## `held` and `pressed` map action names (move, attack, heavy, skill_1, skill_2, surge,
## dodge, guard, stop) to booleans for this tick. `cursor` is in arena coordinates.
func bits(me: CreatureSim, foe: CreatureSim, cursor: Vector2, held: Dictionary, pressed: Dictionary) -> int:
	var out := 0
	ping = {}
	if aim_t > 0:
		aim_t -= 1

	# --- orders
	if pressed.get("stop", false):
		clear()
	if held.get("move", false):
		if pressed.get("move", false) and foe != null and is_on_creature(foe, cursor):
			chase = true
			dest = Vector2.INF
			ping = {"pos": foe.pos, "attack": true}
		elif not chase or pressed.get("move", false):
			chase = false
			dest = cursor
			if pressed.get("move", false):
				ping = {"pos": cursor, "attack": false}

	# --- abilities, aimed at the cursor
	var acted := false
	for act in PRESS_BITS:
		if pressed.get(act, false):
			out |= int(PRESS_BITS[act])
			acted = true
	if held.get("heavy", false):
		out |= SimDefs.IN_HEAVY
	if acted:
		aim_t = AIM_HOLD
		dest = Vector2.INF
		chase = false
	if pressed.get("dodge", false):
		out |= SimDefs.IN_DODGE
		aim_t = maxi(aim_t, 1)
		dest = Vector2.INF
		chase = false
	if held.get("guard", false):
		out |= SimDefs.IN_GUARD
		if pressed.get("guard", false):
			dest = Vector2.INF
			chase = false

	# --- direction: aim, chase, or walk to the destination
	var aiming: bool = aim_t > 0 or (held.get("heavy", false) and me.charging)
	if aiming:
		out |= _dir_bits(cursor - me.pos, 0.0)
	elif chase:
		out |= _chase(me, foe)
	elif dest != Vector2.INF and not held.get("guard", false):
		var v := dest - me.pos
		if v.length() <= ARRIVE:
			dest = Vector2.INF
		else:
			# Give up if a pit or wall stops us for a moment.
			if _last_pos != Vector2.INF and me.pos.distance_to(_last_pos) < 0.05 and me.state == CreatureSim.State.MOVE:
				_stuck += 1
				if _stuck > STUCK_TICKS:
					dest = Vector2.INF
			else:
				_stuck = 0
			if dest != Vector2.INF:
				out |= _dir_bits(v, 1.0)
	_last_pos = me.pos
	_prev = out
	return out


func _chase(me: CreatureSim, foe: CreatureSim) -> int:
	if foe == null or foe.state == CreatureSim.State.KO:
		chase = false
		return 0
	var v := foe.pos - me.pos
	var lt: Dictionary = me.moves().get("light_1", {})
	var reach := float(lt.get("reach", 14)) + float(lt.get("hit_radius", 9)) + foe.radius - 4.0
	if lt.has("projectile"):
		# A thrown opener (Chef Cerebro's Knife Flick): attack from range, but only once
		# a straight throw in one of the 8 directions would meet the target.
		reach = me.move_range("light_1") + foe.radius - 8.0
		var d := CreatureSim._snap8(v)
		var off := v.x * d.y - v.y * d.x
		if v.length() <= reach and absf(off) > foe.radius + 2.0:
			return _dir_bits(Vector2(-d.y, d.x) * -off, 0.5)  # step sideways to line up
	if v.length() > reach:
		return _dir_bits(v, 1.0)
	if not foe.can_be_hit():
		return 0  # wait for it to get up
	# In range: keep jabbing, facing the target. A fresh press needs a released tick before it.
	var out := _dir_bits(v, 0.0)
	if not (_prev & SimDefs.IN_LIGHT):
		out |= SimDefs.IN_LIGHT
	return out


## Direction bits toward `v`, dropping an axis once it's within `slack` pixels
## (so 8-direction walking settles on the destination instead of zig-zagging).
static func _dir_bits(v: Vector2, slack: float) -> int:
	if v.length() < 0.001:
		return 0
	var b := SimDefs.bits_from_dir(v.normalized())
	if slack > 0.0:
		if absf(v.x) <= slack:
			b &= ~(SimDefs.IN_LEFT | SimDefs.IN_RIGHT)
		if absf(v.y) <= slack:
			b &= ~(SimDefs.IN_UP | SimDefs.IN_DOWN)
	return b


## Whether the cursor is over a creature's sprite (feet at pos, body above it).
static func is_on_creature(c: CreatureSim, cursor: Vector2) -> bool:
	var r := Rect2(c.pos.x - c.radius - 6.0, c.pos.y - 36.0, (c.radius + 6.0) * 2.0, 44.0)
	return r.has_point(cursor)
