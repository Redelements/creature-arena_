class_name TouchTarget
extends RefCounted
## Target lock for the touch controls: it aims taps at one foe, can walk you to it, and
## turns the touch pad's bits into the same input bits a pad sends (input layer only:
## nothing here touches the sim, so online peers simply receive the aimed inputs).
##
## - **Sticky lock.** The first tap of Light or a tap-cast (Heavy, a Skill, Surge without
##   a drag) picks a foe by `priority` and keeps its creature index. Later taps and
##   tap-casts aim exactly at it (IN_AIM at the nearest of the 64 steps), kept for
##   AIM_HOLD ticks so a buffered press and a light's startup still turn to it. A drag-aim
##   overrides the lock for that cast.
## - **It drops** when the foe is knocked out, goes past LOCK_RANGE, or the local team
##   can't see it (`hidden`, main's Vision answer: brush, walls, Tiptoe and the rest).
##   Only foes the team sees are ever picked, so the lock never gives a hidden one away.
## - **Picking a foe yourself:** `lock_on(slot)` (the overlay's enemy portraits, the
##   objective button), refused for a foe that couldn't be picked by a tap.
## - **Chase** (`chase_on`): a Light tap with the locked foe out of reach
##   (`MouseOrders.chase_reach`) but within CHASE_RANGE walks to it and throws the light
##   on arrival, like the mouse's right-click on a foe. The walk goes round walls and pits
##   on the CPU's nav grid (`NavGrid`); with no way round it stops rather than step into
##   a hole. The stick always wins: held toward the foe it walks as usual, held away it
##   ends the chase. Any other button, losing the lock or CHASE_TICKS also end it.
## Pure logic: main hands PlayerInput the hidden list each tick; tests drive it directly.

enum Priority { AIM, NEAREST, LOWEST_HP }
const PRIORITY_NAMES := ["Closest to aim", "Nearest", "Lowest health"]
const LOCK_RANGE := 220.0  ## a foe further than this is never picked, and a lock drops
const CONE_DEG := 40.0  ## Closest to aim: foes within this of the aim, nearest first
const CHASE_RANGE := 160.0  ## a Light tap chases a locked foe out of reach up to this far
const CHASE_TICKS := 240  ## a chase gives up after this long
const AIM_HOLD := MouseOrders.AIM_HOLD
const REPLAN_TICKS := 15  ## a chase looks for a new way round this often
const WAYPOINT := 6.0  ## close enough to a path node to head for the next
const AWAY_DOT := 0.5  ## the stick further than 60 degrees off the foe ends a chase
const OTHER_BUTTONS := SimDefs.IN_HEAVY | SimDefs.IN_SKILL1 | SimDefs.IN_SKILL2 | SimDefs.IN_SURGE \
	| SimDefs.IN_DODGE | SimDefs.IN_GUARD | SimDefs.IN_TAG

var priority: Priority = Priority.AIM
var chase_on := true
var lock := -1  ## the locked foe's creature index (-1: none)
var chasing := false
## Bumped when the lock or the chase changes (the overlay redraws then).
var version := 0

var _aim_t := 0
var _chase_t := 0
var _prev := 0
var _path := PackedVector2Array()
var _path_t := 0


func clear() -> void:
	if lock >= 0 or chasing:
		version += 1
	lock = -1
	chasing = false
	_aim_t = 0
	_path = PackedVector2Array()


## Whether creature `i` may be locked by `me_idx`: a foe, standing, seen by the local
## team, within LOCK_RANGE.
static func can_lock(sim: MatchSim, me_idx: int, i: int, hidden: Array) -> bool:
	if i < 0 or i >= sim.creatures.size() or i == me_idx:
		return false
	var me := sim.creatures[me_idx]
	var o := sim.creatures[i]
	if not me.is_foe(o) or o.state == CreatureSim.State.KO or o.hp <= 0.0:
		return false
	if i < hidden.size() and bool(hidden[i]):
		return false
	return me.pos.distance_to(o.pos) <= LOCK_RANGE


## The foe a tap picks: by `prio`, among those `can_lock` allows. `aim` is the way the
## player points (the stick, else facing). -1 when none.
static func pick(sim: MatchSim, me_idx: int, hidden: Array, prio: int, aim: Vector2) -> int:
	var me := sim.creatures[me_idx]
	var best := -1
	var best_key := INF
	var in_cone := false
	var cone := cos(deg_to_rad(CONE_DEG))
	for i in sim.creatures.size():
		if not can_lock(sim, me_idx, i, hidden):
			continue
		var o := sim.creatures[i]
		var to := o.pos - me.pos
		var d := to.length()
		var key := d
		match prio:
			Priority.LOWEST_HP:
				key = o.hp * 10000.0 + d  # lowest health, then nearest
			Priority.AIM:
				var inside := aim != Vector2.ZERO and d > 0.001 and aim.normalized().dot(to / d) >= cone
				if inside != in_cone:
					if not inside:
						continue  # one inside the cone already beats any outside it
					in_cone = true  # the first inside the cone: forget those outside
					best_key = INF
		if key < best_key:
			best_key = key
			best = i
	return best


## Locks a foe the player picked on screen (a portrait, the objective); false and
## nothing changes when it couldn't be picked by a tap (hidden, too far, down).
func lock_on(sim: MatchSim, me_idx: int, i: int, hidden: Array) -> bool:
	if not can_lock(sim, me_idx, i, hidden):
		return false
	if lock != i:
		lock = i
		chasing = false
		version += 1
	return true


## The Capture the Flag objective for `me`'s team: the foe carrying our flag (-1: none,
## or it's home or lying on the ground). Caravan has none: the wagon can't be hit.
static func ctf_objective(t: TeamSim, me: CreatureSim) -> int:
	if t == null or not t.ctf or me.team < 0 or me.team > 1:
		return -1
	var id := int(t.flag_carrier[me.team])
	if id < 0:
		return -1
	for i in t.sim.creatures.size():
		if t.sim.creatures[i].id == id:
			return i
	return -1


## One tick: `bits` from the touch pad in, the bits to send out. `stick` is the pad's
## stick direction (zero when let go).
func apply(bits: int, sim: MatchSim, me_idx: int, hidden: Array, stick: Vector2) -> int:
	var me := sim.creatures[me_idx]
	if lock >= 0 and not can_lock(sim, me_idx, lock, hidden):
		clear()  # down, out of range or out of sight: the lock (and a chase) ends
	var pressed := bits & ~_prev
	var attacks := pressed & PlayerInput.ATTACK_BITS
	if attacks and bits & SimDefs.IN_AIM:
		_end_chase()  # a drag-aim: exactly where the finger said, the lock stays for later
		_aim_t = 0
	elif attacks:
		if lock < 0:
			var aim := stick if stick != Vector2.ZERO else me.facing
			var p := pick(sim, me_idx, hidden, priority, aim)
			if p >= 0:
				lock = p
				version += 1
		if lock >= 0:
			var foe := sim.creatures[lock]
			var far := me.pos.distance_to(foe.pos)
			if chase_on and attacks == SimDefs.IN_LIGHT and far > MouseOrders.chase_reach(me, foe) \
					and far <= CHASE_RANGE and not _away(stick, foe.pos - me.pos):
				chasing = true  # walk there first; the light is thrown on arrival
				_chase_t = CHASE_TICKS
				_path = PackedVector2Array()
				_path_t = 0
				version += 1
				bits &= ~SimDefs.IN_LIGHT
			else:
				_end_chase()
				_aim_t = AIM_HOLD
	elif pressed & OTHER_BUTTONS:
		_end_chase()
	if chasing:
		bits = _chase_step(bits, sim, me, stick)
	if _aim_t > 0 and lock >= 0:
		_aim_t -= 1
		if not (bits & SimDefs.IN_AIM):
			bits |= SimDefs.aim_bits(sim.creatures[lock].pos - me.pos)
	_prev = bits
	return bits


func _end_chase() -> void:
	if chasing:
		chasing = false
		version += 1


static func _away(stick: Vector2, to: Vector2) -> bool:
	if stick == Vector2.ZERO or to.length_squared() < 1e-6:
		return false
	return stick.normalized().dot(to.normalized()) < AWAY_DOT


func _chase_step(bits: int, sim: MatchSim, me: CreatureSim, stick: Vector2) -> int:
	_chase_t -= 1
	if lock < 0 or _chase_t <= 0:
		_end_chase()
		return bits
	var foe := sim.creatures[lock]
	var to := foe.pos - me.pos
	if _away(stick, to):
		_end_chase()  # the stick wins: no pulling the player back toward the foe
		return bits
	if to.length() <= MouseOrders.chase_reach(me, foe):
		_end_chase()  # there: throw the light, aimed at it
		_aim_t = AIM_HOLD
		if not (_prev & SimDefs.IN_LIGHT):
			bits |= SimDefs.IN_LIGHT
		return bits
	if stick != Vector2.ZERO:
		return bits  # held toward it: the stick walks
	if me.state != CreatureSim.State.IDLE and me.state != CreatureSim.State.MOVE:
		return bits  # mid-move or hit: walk on once free
	return bits | _walk(sim, me, foe.pos)


## Move bits toward `goal` that never step into a hole: straight when the line is clear
## of walls and pits (healing holes too), else along the nav grid's path; nothing when
## there's no way round (stop at the edge).
func _walk(sim: MatchSim, me: CreatureSim, goal: Vector2) -> int:
	var t := sim.terrain
	if NavGrid.clear_line(t, me.pos, goal, me.radius, true):
		_path = PackedVector2Array()
		return SimDefs.move_bits(goal - me.pos)
	_path_t -= 1
	if _path.is_empty() or _path_t <= 0:
		_path = NavGrid.shared(t).path(me.pos, goal)
		_path_t = REPLAN_TICKS
	while _path.size() > 1 and (me.pos.distance_to(_path[0]) < WAYPOINT
			or NavGrid.clear_line(t, me.pos, _path[1], me.radius, true)):
		_path.remove_at(0)
	if _path.is_empty():
		return 0
	var v := _path[0] - me.pos
	if v.length() < 0.5:
		_path.remove_at(0)
		return 0
	if not NavGrid.clear_line(t, me.pos, _path[0], 0.0, true):
		return 0  # a hole on the way (the floor broke since the path was found): wait
	return SimDefs.move_bits(v)
