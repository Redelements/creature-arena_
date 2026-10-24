class_name TeamIntent
extends RefCounted
## What a CPU team agrees on for one tick: the foe it focuses. Built once per tick for every
## team, on the main thread, before the CPUs think (CpuController.think_start, or the first
## bits() call of the tick when they think one by one), from the match state and from what
## each member chose the tick before (its target, the foes it saw). The CPUs then read it on
## the worker threads without a lock, and each writes its own choice back for the next build
## (`note`, under the lock, one slot a member), so threaded and sequential thinking agree.
##
## A team of one keeps its own counsel: CpuController reads the focus only with a living ally.
## Players on a mixed team are members too (their positions count toward the focus); they
## never write a choice, so their slots stay empty.

## Switching focus needs this much more team score than the current focus has.
const SWITCH_MARGIN := 1.15
## Ticks a focus nobody on the team can see is kept before it's dropped.
const UNSEEN_TICKS := 60
## Distance at which a foe counts half as near as one in your face (f_near).
const NEAR_PX := 160.0
## Each member voting for a foe (the target it chose last tick, not one it was forced onto
## by a foe in its face) adds this to the foe's score.
const VOTE := 0.5
## Share of this tick's raw score that moves the team's running score (the rest is last
## tick's): fighters move fast, so the belief lags them a little rather than flapping.
const SMOOTH := 0.1

var team := 0
var tick := 0
## The foe (a slot in sim.creatures) the team goes after, -1 when there is none.
var focus := -1
## Ticks the focus has held, and ticks since anyone on the team saw it.
var focus_t := 0
var focus_unseen := 0
## The team score of the focus when it was last seen (what a rival must beat by SWITCH_MARGIN).
var focus_score := 0.0
## Every living foe's team score this tick (slot -> float), for the benches and tests.
var scores := {}
## Foes any member saw last tick, as a bitmask of slots (the team's shared sight, one tick old).
var saw := 0
## What each member chose this tick, by slot: its target (-1 none), the foe it votes for
## (its target unless that was forced on it; -1 none) and the foes it saw.
var member_target := PackedInt32Array()
var member_vote := PackedInt32Array()
var member_saw := PackedInt32Array()
var _lock := Mutex.new()

# The intents of the match being played: one per team for this tick, and the tick before.
static var _sim_id := 0
static var _tick := -1
static var _now := {}
static var _prev := {}
static var _build_lock := Mutex.new()


## This tick's intent for `team`, building every team's first when the tick is new. Reading
## is lock-free once built; the build itself is locked so a stray parallel first call is safe.
static func of(sim: MatchSim, team: int) -> TeamIntent:
	if _sim_id != sim.get_instance_id() or _tick != sim.tick:
		build_all(sim)
	return _now.get(team)


## The intent built for `team` this tick, or null: never builds (for the benches).
static func current(sim: MatchSim, team: int) -> TeamIntent:
	if _sim_id != sim.get_instance_id() or _tick != sim.tick:
		return null
	return _now.get(team)


## Builds every team's intent for the match's current tick. Called again for the same tick
## (the game re-thinks a tick after a training option), it rebuilds from the same previous
## tick, so the answer is the same.
static func build_all(sim: MatchSim) -> void:
	_build_lock.lock()
	var same := _sim_id == sim.get_instance_id()
	if not same or _tick != sim.tick:
		_prev = _now if same and _tick == sim.tick - 1 else {}
		_now = {}
	_sim_id = sim.get_instance_id()
	_tick = sim.tick
	var teams := {}
	for c in sim.creatures:
		teams[c.team] = true
	var fresh := {}
	for t in teams:
		fresh[t] = _build(sim, int(t), _prev.get(t))
	_now = fresh
	_build_lock.unlock()


## Forgets the match (tests start clean).
static func reset() -> void:
	_build_lock.lock()
	_sim_id = 0
	_tick = -1
	_now = {}
	_prev = {}
	_build_lock.unlock()


## A member's choice this tick, for the next build: its target slot, the foe it votes for
## (`target` unless given) and the foes it saw.
func note(slot: int, target: int, saw_mask: int, vote := -2) -> void:
	_lock.lock()
	member_target[slot] = target
	member_vote[slot] = target if vote == -2 else vote
	member_saw[slot] = saw_mask
	_lock.unlock()


static func _build(sim: MatchSim, team: int, prev: TeamIntent) -> TeamIntent:
	var ti := TeamIntent.new()
	ti.team = team
	ti.tick = sim.tick
	var n := sim.creatures.size()
	ti.member_target.resize(n)
	ti.member_target.fill(-1)
	ti.member_vote.resize(n)
	ti.member_vote.fill(-1)
	ti.member_saw.resize(n)
	# What the team saw last tick, from the members' notes; before the first note, everyone.
	var saw := 0
	var noted := false
	if prev != null:
		for i in n:
			if sim.creatures[i].team == team and prev.member_target[i] >= 0:
				noted = true
				saw |= prev.member_saw[i]
	if not noted:
		saw = (1 << n) - 1
	ti.saw = saw
	# Team score of each living foe in sight: how near and how hurt it is, summed over the
	# living members, plus a vote from each member already on it; run into last tick's score.
	var best := -1
	var best_score := 0.0
	for f in n:
		var foe: CreatureSim = sim.creatures[f]
		if foe.team == team or foe.state == CreatureSim.State.KO:
			continue
		var s := 0.0
		if saw & (1 << f):
			for m in n:
				var me: CreatureSim = sim.creatures[m]
				if me.team != team or me.state == CreatureSim.State.KO:
					continue
				s += f_near(me.pos.distance_to(foe.pos)) * f_weak(foe)
				if prev != null and prev.member_vote[m] == f:
					s += VOTE
		if prev != null and prev.scores.has(f):
			s = lerpf(float(prev.scores[f]), s, SMOOTH)
		ti.scores[f] = s
		if s > best_score:
			best_score = s
			best = f
	# Keep the focus unless a rival clearly outscores it; a focus out of sight is kept for a
	# while (it ducked behind a wall or into brush), then let go.
	if prev != null and prev.focus >= 0 and ti.scores.has(prev.focus):
		var seen := bool(saw & (1 << prev.focus))
		var unseen_t := 0 if seen else prev.focus_unseen + 1
		var held := float(ti.scores[prev.focus]) if seen else prev.focus_score
		if unseen_t < UNSEEN_TICKS and (best < 0 or best_score < held * SWITCH_MARGIN):
			ti.focus = prev.focus
			ti.focus_t = prev.focus_t + 1
			ti.focus_unseen = unseen_t
			ti.focus_score = held
			return ti
	ti.focus = best
	ti.focus_score = best_score
	return ti


## 1 for a foe in your face, 1/2 at NEAR_PX, falling with distance.
static func f_near(d: float) -> float:
	return NEAR_PX / (NEAR_PX + maxf(0.0, d))


## 1.5 for a foe at full health down to 0.5 at none: the hurt one is the one to finish.
static func f_weak(foe: CreatureSim) -> float:
	return 1.5 - clampf(foe.hp / maxf(1.0, foe.max_hp), 0.0, 1.0)
