class_name CpuController
extends RefCounted
## A CPU opponent that plays by pressing buttons, exactly like a player. It reads the
## match state, decides, and returns an input bitmask for its creature each tick, so it
## obeys every rule the player does and its matches still replay exactly.
##
## Randomness comes from its own seeded generator, so a given seed always plays the
## same way. Difficulty changes reaction time, how often it defends, how reliably it
## finishes combos, and how often it fumbles.

const LEVELS := [
	{"name": "Easy", "reaction": 22, "defend": 0.25, "combo": 0.35, "mistake": 0.25,
		"breakaway": 0.05, "aggression": 0.35, "think": 18},
	{"name": "Normal", "reaction": 13, "defend": 0.55, "combo": 0.75, "mistake": 0.1,
		"breakaway": 0.25, "aggression": 0.55, "think": 12},
	{"name": "Hard", "reaction": 7, "defend": 0.85, "combo": 0.95, "mistake": 0.02,
		"breakaway": 0.5, "aggression": 0.7, "think": 7},
]

const ACTION_BIT := {
	"light": SimDefs.IN_LIGHT, "heavy": SimDefs.IN_HEAVY,
	"skill_1": SimDefs.IN_SKILL1, "skill_2": SimDefs.IN_SKILL2, "surge": SimDefs.IN_SURGE,
}

var me_idx: int
var level: int
var p: Dictionary
var rng := RandomNumberGenerator.new()

var _prev := 0
var _out := 0

# Combo state
var _route: Array = []
var _route_step := 0
var _route_serial := -1  ## the attack serial whose follow-up we've decided
var _route_drop := false

# Defense state
var _seen_serial := -1
var _defense := ""
var _defense_t := 0
var _break_combo_checked := -1

# Movement
var _plan := "approach"
var _plan_t := 0
var _plan_dir := Vector2.ZERO
var _think_t := 0
var _last_pos := Vector2.ZERO
var _stuck_t := 0
var _detour_t := 0
var _detour_dir := Vector2.ZERO
var _hold_heavy := 0
## Set in a Duel, so the CPU can tag out a hurt creature.
var duel: DuelSim = null


func _init(p_me: int, p_level := 1, p_seed := 1) -> void:
	me_idx = p_me
	level = clampi(p_level, 0, LEVELS.size() - 1)
	p = LEVELS[level]
	rng.seed = p_seed


func level_name() -> String:
	return String(p["name"])


func bits(sim: MatchSim) -> int:
	_out = 0
	var me := sim.creatures[me_idx]
	var foe := sim.nearest_opponent(me)
	if foe != null and me.state != CreatureSim.State.KO:
		_decide(sim, me, foe)
		# Normal and Hard aim attacks exactly (360 degrees), like a stick or a mouse; Easy
		# keeps to the 8 directions a keyboard gives.
		if level >= 1 and ((_out & PlayerInput.ATTACK_BITS) or me.state == CreatureSim.State.ATTACK):
			_out |= SimDefs.aim_bits(foe.pos - me.pos)
	_prev = _out
	return _out


# ------------------------------------------------------------------ helpers

## Presses a button this tick (a fresh press needs it released the tick before).
func _press(bit: int) -> void:
	if not (_prev & bit):
		_out |= bit


func _hold(bit: int) -> void:
	_out |= bit


func _move_toward(v: Vector2) -> void:
	_hold(SimDefs.bits_from_dir(v.normalized()))


func _ai(me: CreatureSim) -> Dictionary:
	return me.def.get("ai", {})


func _roll(chance: float) -> bool:
	return rng.randf() < chance


## How far the foe's current attack can reach, from the foe's position.
func _threat_range(foe: CreatureSim, me: CreatureSim) -> float:
	var mv := foe.move_def()
	var r := float(mv.get("reach", 14)) + float(mv.get("hit_radius", 10)) + me.radius
	var dash: Dictionary = mv.get("dash", {})
	if not dash.is_empty():
		r += float(dash["speed"]) * float(int(dash["to"]) - int(dash["from"]))
	r += float(mv.get("lunge", 0.0)) * float(mv.get("startup", 0))
	return r + 6.0


# ------------------------------------------------------------------ decisions

func _decide(sim: MatchSim, me: CreatureSim, foe: CreatureSim) -> void:
	var to_foe := foe.pos - me.pos
	var dist := to_foe.length()

	# Stunned: maybe burn energy on a breakaway, otherwise nothing to do.
	if me.is_stunned() or me.state == CreatureSim.State.KNOCKDOWN or me.state == CreatureSim.State.FALLING:
		_route = []
		if me.is_stunned() and me.combo_hits >= CreatureSim.BREAKAWAY_MIN_HITS \
				and me.energy >= CreatureSim.BREAKAWAY_COST and _break_combo_checked != me.combo_hits:
			_break_combo_checked = me.combo_hits
			if me.combo_hits == CreatureSim.BREAKAWAY_MIN_HITS and _roll(float(p["breakaway"])):
				_press(SimDefs.IN_GUARD)
				_press(SimDefs.IN_DODGE)
		return
	_break_combo_checked = -1

	if me.state == CreatureSim.State.ATTACK:
		_continue_attack(sim, me, foe, dist)
		return
	if me.state == CreatureSim.State.DODGE:
		return

	if _defend(sim, me, foe, dist):
		return
	if _maybe_tag(me, dist):
		return
	_neutral(sim, me, foe, to_foe, dist)


## Duel: tag out a badly hurt creature for a healthier teammate, from a safe distance.
func _maybe_tag(me: CreatureSim, dist: float) -> bool:
	if duel == null or not duel.can_tag(me_idx) or dist < 40.0:
		return false
	var mine := me.hp / me.max_hp
	var best := 0.0
	for c in duel.teams[me_idx]:
		if c != me and c.hp > 0.0:
			best = maxf(best, c.hp / c.max_hp)
	if mine < 0.35 and best > mine + 0.2 and _roll(0.03 + 0.03 * level):
		_press(SimDefs.IN_TAG)
		return true
	return false


func _continue_attack(sim: MatchSim, me: CreatureSim, foe: CreatureSim, dist: float) -> void:
	if me.charging:
		if _hold_heavy > 0:
			_hold_heavy -= 1
			_hold(SimDefs.IN_HEAVY)
		return
	if not me.connected or _route_drop:
		return
	if foe.state == CreatureSim.State.GUARD:
		# Blocked: a grab beats a guard; otherwise stop pressing.
		var grab := String(_ai(me).get("grab", ""))
		if grab != "" and me.can_use(grab) and me.move_rank(grab) > me.move_rank(me.move_id):
			_press(int(ACTION_BIT[grab]))
		return
	# On the first contact, pick a route; each new move after that is one step along it.
	if _route.is_empty():
		_route = _pick_route(me)
		_route_step = 1
		_route_serial = me.attack_serial
		if not _roll(float(p["combo"])):
			_route_drop = true
			return
	elif _route_serial != me.attack_serial:
		_route_serial = me.attack_serial
		_route_step += 1
		if not _roll(float(p["combo"])):
			_route_drop = true
			return
	if _route_step < _route.size():
		var action := String(_route[_route_step])
		if action == "light" or me.can_use(me.action_move(action)):
			_press(int(ACTION_BIT[action]))


func _pick_route(me: CreatureSim) -> Array:
	if me.move_id != "light_1":
		# Started with something else (a counter, a poke): finish with whatever ranks higher.
		var tail: Array = [me.move_id]
		for act in ["heavy", "skill_2", "skill_1", "surge"]:
			var mid := me.action_move(act)
			if me.move_rank(mid) > me.move_rank(me.move_id) and me.can_use(mid) \
					and not me.moves()[mid].has("counter"):
				tail.append(act)
				break
		return tail
	var routes: Array = _ai(me).get("routes", [["light"]])
	for r in routes:
		var ok := true
		for act in r:
			if act == "light":
				continue
			var mid := me.action_move(String(act))
			if not me.can_use(mid):
				ok = false
				break
		if ok and _roll(0.8):
			return r.duplicate()
	return routes[routes.size() - 1].duplicate()


func _defend(sim: MatchSim, me: CreatureSim, foe: CreatureSim, dist: float) -> bool:
	# Keep doing a defense already chosen.
	if _defense != "":
		_defense_t -= 1
		var foe_busy := foe.state == CreatureSim.State.ATTACK
		if _defense == "guard" and (foe_busy or _defense_t > 0) and _defense_t > -30:
			_hold(SimDefs.IN_GUARD)
			return true
		_defense = ""

	var threat := false
	var grab_threat := false
	var serial := foe.attack_serial
	if foe.state == CreatureSim.State.ATTACK and not foe.charging \
			and foe.attack_elapsed() >= int(p["reaction"]) - 6 and dist < _threat_range(foe, me):
		threat = true
		grab_threat = bool(foe.move_def().get("grab", false))
	# Shockwaves heading this way.
	for pr in sim.projectiles:
		if int(pr["owner"]) == me.id:
			continue
		var pp: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		if pp.distance_to(me.pos) < 70.0 and vel.dot(me.pos - pp) > 0.0:
			threat = true
			serial = 100000 + int(pr["serial"])
	if foe.charging and dist < 60.0:
		threat = true
		serial = 200000 + foe.attack_serial

	if not threat or serial == _seen_serial:
		return false
	_seen_serial = serial
	if not _roll(float(p["defend"])):
		return false

	var counter := String(_ai(me).get("counter", ""))
	if grab_threat or foe.charging:
		_dodge_away(me, foe)
		return true
	if counter != "" and me.can_use(counter) and foe.state == CreatureSim.State.ATTACK \
			and String(foe.move_def().get("type", "")) != "surge" and _roll(0.5):
		_press(int(ACTION_BIT[counter]))
		return true
	if _roll(0.7):
		_defense = "guard"
		_defense_t = 20
		_hold(SimDefs.IN_GUARD)
	else:
		_dodge_away(me, foe)
	return true


func _dodge_away(me: CreatureSim, foe: CreatureSim) -> void:
	var away := (me.pos - foe.pos).normalized()
	var side := Vector2(-away.y, away.x) * (1.0 if _roll(0.5) else -1.0)
	_hold(SimDefs.bits_from_dir((away + side).normalized()))
	_press(SimDefs.IN_DODGE)


func _neutral(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float) -> void:
	_route = []
	_route_drop = false
	var ai := _ai(me)
	var want := float(ai.get("range", 22)) + me.radius + foe.radius - 10.0

	# Stuck against a hole edge? Walk around it for a moment.
	if _detour_t > 0:
		_detour_t -= 1
		_move_toward(_detour_dir)
		return
	if me.state == CreatureSim.State.MOVE and me.pos.distance_to(_last_pos) < 0.05:
		_stuck_t += 1
		if _stuck_t > 6:
			_stuck_t = 0
			_detour_t = 24
			var n := to_foe.normalized()
			_detour_dir = Vector2(-n.y, n.x) * (1.0 if _roll(0.5) else -1.0)
			return
	else:
		_stuck_t = 0
	_last_pos = me.pos

	# The foe is down or protected: hang back at striking distance, or charge a slam.
	var foe_protected := foe.state in [CreatureSim.State.KNOCKDOWN, CreatureSim.State.FALLING] \
		or foe.invuln > 0 or foe.is_airborne()
	if foe_protected:
		if bool(ai.get("wakeup_charge", false)) and dist < 46.0 and me.can_use("heavy") \
				and foe.state == CreatureSim.State.KNOCKDOWN and _roll(0.05 + 0.1 * level):
			_hold_heavy = clampi(foe.stun - 4, 6, 45)
			_press(SimDefs.IN_HEAVY)
			_hold(SimDefs.bits_from_dir(to_foe.normalized()))
			return
		if dist > want + 14.0:
			_move_toward(to_foe)
		return

	# Free punish on a crumpled or stunned foe.
	if foe.is_stunned() and dist < want + 10.0:
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(SimDefs.IN_LIGHT)
		return

	_think_t -= 1
	if _think_t > 0:
		_follow_plan(me, foe, to_foe, dist, want)
		return
	_think_t = int(p["think"]) + rng.randi_range(0, 6)

	if _roll(float(p["mistake"])):
		_plan = "wait"
		return

	# Long-range pokes: a shockwave or a dash punch.
	var poke := String(ai.get("poke", ""))
	var pr: Array = ai.get("poke_range", [0, 0])
	if poke != "" and me.can_use(poke) and dist >= float(pr[0]) and dist <= float(pr[1]) \
			and absf(to_foe.y) < 18.0 and _roll(0.25 * float(p["aggression"]) + 0.05):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(int(ACTION_BIT[poke]))
		return

	# An area Surge (Storm Drain) works straight from neutral when the foe is close.
	var surge_range := float(ai.get("surge_range", 0))
	if surge_range > 0.0 and dist < surge_range and me.can_use("surge") and _roll(0.3 + 0.2 * level):
		_press(SimDefs.IN_SURGE)
		return

	# A guarding foe invites a grab.
	var grab := String(ai.get("grab", ""))
	if grab != "" and foe.state == CreatureSim.State.GUARD and dist < want + 8.0 and me.can_use(grab):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(int(ACTION_BIT[grab]))
		return

	if dist <= want + 6.0 and _roll(float(p["aggression"])):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		if _roll(0.15) and me.can_use("heavy"):
			_hold_heavy = rng.randi_range(0, 12)
			_press(SimDefs.IN_HEAVY)
		else:
			_press(SimDefs.IN_LIGHT)
		return

	if dist > want + 6.0:
		_plan = "approach"
	elif _roll(0.4):
		_plan = "retreat"
	elif _roll(0.5):
		_plan = "circle"
		_plan_dir = Vector2(-to_foe.y, to_foe.x).normalized() * (1.0 if _roll(0.5) else -1.0)
	else:
		_plan = "wait"
	_follow_plan(me, foe, to_foe, dist, want)


func _follow_plan(me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, want: float) -> void:
	match _plan:
		"approach":
			if dist > want:
				_move_toward(to_foe)
		"retreat":
			if dist < want + 30.0:
				_move_toward(-to_foe)
		"circle":
			_move_toward(_plan_dir + to_foe.normalized() * 0.3)
