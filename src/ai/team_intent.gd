class_name TeamIntent
extends RefCounted
## What a CPU team agrees on for one tick: the foe it focuses, whether it commits to the
## fight, pokes or backs off (the engage state), and where its front line stands. Built once
## per tick for every team, on the main thread, before the CPUs think (CpuController.think_start,
## or the first bits() call of the tick when they think one by one), from the match state and
## from what each member chose the tick before (its target, the foes it saw, its engage state).
## The CPUs then read it on the worker threads without a lock, and each writes its own choice
## back for the next build (`note`, `note_engage`, under the lock, one slot a member), so
## threaded and sequential thinking agree.
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
## A marked foe's pull (MatchSim.marks) over this many pixels is added to its score's weight.
const MARK_PX := 240.0
## Engage states: what each member says it is doing (`note_engage`) and what the team does,
## `commit` when at least ENGAGE_VOTES members commit (and no fewer than retreat), `retreat`
## when at least ENGAGE_VOTES members retreat, else `poke`.
const POKE := 0
const COMMIT := 1
const RETREAT := 2
const ENGAGE_VOTES := 2

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
## What each member said it was doing this tick (POKE, COMMIT, RETREAT; -1 nothing).
var member_engage := PackedInt32Array()
## The team's engage state this tick, from the members' engage notes of the tick before.
var engage := POKE
## The front line: the point it stands at (the tank's position, or the nearest melee's, with
## the focus in front of it; INF when there is none), the way it faces (toward the focus) and
## the member that makes it (-1 none). Kiters and skirmishers keep behind it.
var front := Vector2.INF
var front_dir := Vector2.ZERO
var front_slot := -1
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


## A member's engage state this tick (POKE, COMMIT or RETREAT), for the next build.
func note_engage(slot: int, state: int) -> void:
	_lock.lock()
	member_engage[slot] = state
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
	ti.member_engage.resize(n)
	ti.member_engage.fill(-1)
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
				s += f_near(me.pos.distance_to(foe.pos)) * f_weak(foe) * f_mark(sim, foe)
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
			_finish(sim, ti, prev)
			return ti
	ti.focus = best
	ti.focus_score = best_score
	_finish(sim, ti, prev)
	return ti


## The engage state (from last tick's notes of the living members) and the front line (from
## the focus and where the members stand now).
static func _finish(sim: MatchSim, ti: TeamIntent, prev: TeamIntent) -> void:
	var commits := 0
	var retreats := 0
	if prev != null:
		for m in sim.creatures.size():
			var c: CreatureSim = sim.creatures[m]
			if c.team != ti.team or c.state == CreatureSim.State.KO:
				continue
			if m >= prev.member_engage.size():
				continue
			commits += 1 if prev.member_engage[m] == COMMIT else 0
			retreats += 1 if prev.member_engage[m] == RETREAT else 0
	ti.engage = engage_of(commits, retreats)
	if ti.focus < 0:
		return
	var slot := front_of(sim, ti.team, sim.creatures[ti.focus])
	if slot < 0:
		return
	var anchor: CreatureSim = sim.creatures[slot]
	ti.front_slot = slot
	ti.front = anchor.pos
	ti.front_dir = (sim.creatures[ti.focus].pos - anchor.pos).normalized()


## The team state from how many living members commit and how many retreat.
static func engage_of(commits: int, retreats: int) -> int:
	if commits >= ENGAGE_VOTES and commits >= retreats:
		return COMMIT
	if retreats >= ENGAGE_VOTES:
		return RETREAT
	return POKE


## The member that makes `team`'s front line against `focus`: the living tank (a "press"
## plan with "peel" targeting) nearest the focus, else the nearest living melee that holds
## ground (a "press" or "footsie" plan); -1 when the team has neither.
static func front_of(sim: MatchSim, team: int, focus: CreatureSim) -> int:
	var best := -1
	var best_rank := 99
	var best_d := INF
	for m in sim.creatures.size():
		var c: CreatureSim = sim.creatures[m]
		if c.team != team or c.state == CreatureSim.State.KO or CpuController.ranged(c):
			continue
		var st := CpuController.style_of(c)
		var rank := 0 if String(st["target"]) == "peel" else (1 if String(st["plan"]) in ["press", "footsie"] else 99)
		if rank == 99:
			continue
		var d := c.pos.distance_squared_to(focus.pos)
		if rank < best_rank or (rank == best_rank and d < best_d):
			best = m
			best_rank = rank
			best_d = d
	return best


## 1 for a foe in your face, 1/2 at NEAR_PX, falling with distance.
static func f_near(d: float) -> float:
	return NEAR_PX / (NEAR_PX + maxf(0.0, d))


## A foe the mode marks as wanted (a spree, the crown; MatchSim.marks in px) scores a little
## more: 1 + pull / MARK_PX (60 px: x1.25). Nearness still counts first, so a team in a fight
## doesn't drop it to cross the map.
static func f_mark(sim: MatchSim, foe: CreatureSim) -> float:
	return 1.0 + CpuController.mark_of(sim, foe) / MARK_PX


## 1.5 for a foe at full health down to 0.5 at none: the hurt one is the one to finish.
static func f_weak(foe: CreatureSim) -> float:
	return 1.5 - clampf(foe.hp / maxf(1.0, foe.max_hp), 0.0, 1.0)
