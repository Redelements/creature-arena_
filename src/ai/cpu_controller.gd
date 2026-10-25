class_name CpuController
extends RefCounted
## A CPU opponent that plays by pressing buttons, exactly like a player. It reads the
## match state, decides, and returns an input bitmask for its creature each tick, so it
## obeys every rule the player does and its matches still replay exactly.
##
## Randomness comes from its own seeded generator, so a given seed always plays the
## same way. Difficulty changes reaction time, how often it defends, how reliably it
## finishes combos, and how often it fumbles.
##
## Rage (level 3) is a different brain on the same buttons: it reads every foe's frame
## data and projectiles, steps out of range or times its dodges to the frame, punishes
## every whiff, leads its shots, never drops a combo, walks around holes and out of
## corners, and plays each fighter by its class (STYLES): a mage kites at the edge of
## its range, strafing and throwing as it backs off; an assassin lurks, bursts in and
## gets out; a tank walks you into the walls; a bruiser keeps the pressure on; a
## skirmisher hits and runs; a fighter plays footsies at the edge of your reach.

const LEVELS := [
	{"name": "Easy", "reaction": 22, "defend": 0.25, "combo": 0.35, "mistake": 0.25,
		"breakaway": 0.05, "aggression": 0.35, "think": 18},
	{"name": "Normal", "reaction": 13, "defend": 0.55, "combo": 0.75, "mistake": 0.1,
		"breakaway": 0.25, "aggression": 0.55, "think": 12},
	{"name": "Hard", "reaction": 7, "defend": 0.85, "combo": 0.95, "mistake": 0.02,
		"breakaway": 0.5, "aggression": 0.7, "think": 7},
	{"name": "Rage", "reaction": 1, "defend": 1.0, "combo": 1.0, "mistake": 0.0,
		"breakaway": 1.0, "aggression": 0.9, "think": 2, "rage": true},
]
const RAGE := 3
## A guard at or under this share of its stamina is pressed, not waited out: blocked hits
## drain it, and the one that empties it lands clean.
const PRESSURE_GUARD_SHARE := 0.5

## How Rage plays each class ("role" in the creature file; an "ai" "style" overrides).
##   plan     what it does in neutral (see _rage_neutral)
##   target   who it goes after in a team battle: the nearest foe, the weakest one, or
##            (a tank) whoever is closest to its most hurt teammate
##   defense  evade: step out of reach or dodge; guard: block and punish; mixed: both
const STYLES := {
	"mage": {"plan": "kite", "target": "nearest", "defense": "evade"},
	"assassin": {"plan": "lurk", "target": "weakest", "defense": "evade"},
	"tank": {"plan": "press", "target": "peel", "defense": "guard"},
	"bruiser": {"plan": "press", "target": "nearest", "defense": "guard"},
	"skirmisher": {"plan": "skirmish", "target": "nearest", "defense": "evade", "weights": {"poke": 1.0}},
	"fighter": {"plan": "footsie", "target": "nearest", "defense": "mixed", "weights": {"poke": 1.0}},
}

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
## How close a CPU has to be to see a foe hiding in brush (Vision's rule).
const HIDE_RANGE := Vision.HIDE_RANGE
var _plan_t := 0
var _plan_dir := Vector2.ZERO
var _think_t := 0
var _last_pos := Vector2.ZERO
var _stuck_t := 0
## What this CPU's team can see (Vision: brush, fences and walls), fed from sim.events.
var _vision := Vision.new()
## Where each foe was last seen by this team (CreatureSim -> Vector2): a foe out of sight
## (invisible, in brush, behind a wall or fence) is chased and aimed at there, not where
## it is. A foe never seen yet is known where it started.
var _last_seen := {}
## The foes out of sight this tick (CreatureSim -> true).
var _unseen := {}
## Whether the current target is out of sight right now.
var _foe_hidden := false
## Finding a way round walls, fences and pits (NavGrid): the current path, where it
## was going, and ticks until it may be replanned. Only used when the straight line to
## the goal is blocked, so open-floor play is exactly what it was. The grid itself is
## shared by every CPU on the same terrain (NavGrid.shared).
var _path := PackedVector2Array()
var _path_goal := Vector2.INF
var _path_t := 0
const REPLAN_TICKS := 20
const WAYPOINT_REACHED := 7.0
var _detour_t := 0
var _detour_dir := Vector2.ZERO
var _hold_heavy := 0
var _hold_bit := SimDefs.IN_HEAVY  ## the button a held charge is held on
var _hold_serial := -1  ## the attack whose "hold" (full-charge) choice is made
var _guard_press := false  ## the last attack pressed was thrown to beat a guard
## Set in a Duel, so the CPU can tag out a hurt creature.
var duel: DuelSim = null

# Rage
var _target: CreatureSim = null
var _target_t := 0
var _orbit := 1.0  ## which way it circles (+1 / -1)
var _orbit_t := 0
var _engage_t := 0  ## ticks left in a committed attack run (assassin, skirmisher)
const MOUND_SIGHT := Vision.HIDE_RANGE  ## px: a tunnelling (hidden) foe's mound is plain to see this close, like a shape in brush
var _cover := Vector2.INF  ## brush to lurk in (assassin), or INF when the arena has none in reach
var _cover_t := 0  ## ticks until the cover spot is looked for again
var _step_dir := Vector2.ZERO
var _kit_t := 0
var scored: bool = scored_default
## Extra px a scored kiter keeps its near edge out (`_give_ground`); 0 otherwise.
var _give := 0.0
var _dance_t := 0
var _blocked_serial := -1  ## the attack of ours that was last blocked
var _blocked_streak := 0  ## attacks of ours blocked in a row (a hit resets it)
var _quiet_t := 0  ## ticks since one of our attacks last landed or was blocked


func _init(p_me: int, p_level := 1, p_seed := 1) -> void:
	me_idx = p_me
	level = clampi(p_level, 0, LEVELS.size() - 1)
	p = LEVELS[level]
	rng.seed = p_seed


func level_name() -> String:
	return String(p["name"])


## Every CPU in `cpus` (nulls skipped) chooses its input for this tick at once, on the
## worker threads; read each answer from `last_bits`. A CPU reads the match and writes
## only its own state, and the caches they share (TerrainIndex, NavGrid, Vision's lines)
## are brought up to date here first or are locked, so every answer is exactly what
## calling bits() one CPU after another gives. Big team matches have eight CPUs: this
## spreads their thinking over the cores instead of one frame.
static func think_all(cpus: Array, sim: MatchSim) -> void:
	think_wait(think_start(cpus, sim))


## think_all in two halves, so main can draw a frame while the CPUs think: think_start
## sets them going on the worker threads and returns at once; think_wait(task) waits for
## them. Until it returns, nothing may change the match (the CPUs are reading it). Returns
## -1 when it thought there and then (threads off, or nobody to think).
static func think_start(cpus: Array, sim: MatchSim) -> int:
	var list: Array[CpuController] = []
	for c in cpus:
		if c != null:
			list.append(c)
	if list.is_empty() or not threaded:
		for c in list:
			c.bits(sim)
		return -1
	SimDefs.aim_dirs()
	var t0 := PerfLog.now()
	NavGrid.shared(sim.terrain)  # (and its TerrainIndex) built here, read-only on the threads
	TerrainIndex.of(sim.terrain)
	PerfLog.since("ai nav update", t0)
	t0 = PerfLog.now()
	TeamIntent.build_all(sim)  # each team's focus, from the match and last tick's choices
	PerfLog.since("ai intent", t0)
	return WorkerThreadPool.add_group_task(func(k: int) -> void: list[k].bits(sim),
		list.size(), -1, true, "CPU players")


static func think_wait(task: int) -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(task)


## Whether think_all uses the worker threads (--cpu-threads=off turns it off, to compare).
static var threaded := true
## The scored kit (`_rage_kit_scored`) for new controllers (on; false plays the old ladder,
## for A/B with `tests/bench_cpu.gd --scored`). Each controller's `scored` can differ.
static var scored_default := true
## Team intent (`TeamIntent`: a shared focus target) for new controllers (on; false picks
## targets alone, for A/B with `tests/bench_cpu.gd --teams=3 --intent=off`).
static var intent_default := true
var intent: bool = intent_default
## This tick's intent of my team (TeamIntent.of), set in bits(); the focus slot my current
## target was picked under, so a new focus is weighed at once; whether the target was
## forced on me by a foe in reach (then it isn't my vote for the team's focus).
var _team: TeamIntent = null
var _focus_slot := -1
var _target_forced := false
## The input chosen by the last bits() call.
var last_bits := 0


func bits(sim: MatchSim) -> int:
	_out = 0
	var me := sim.creatures[me_idx]
	_quiet_t += 1
	for e in sim.events:
		if String(e["type"]) == "block" and int(e.get("attacker", -1)) == me_idx:
			if _blocked_serial != me.attack_serial:
				_blocked_streak += 1
			_blocked_serial = me.attack_serial
			_quiet_t = 0
		elif String(e["type"]) in ["hit", "grab", "guard_break"] and int(e.get("attacker", -1)) == me_idx:
			_blocked_streak = 0
			_quiet_t = 0
	if _quiet_t > 75:
		_blocked_streak = 0  # a standoff: try again rather than stand there
	var t0 := PerfLog.now()
	_look(sim, me)
	PerfLog.since("ai look", t0)
	t0 = PerfLog.now()
	_team = TeamIntent.of(sim, me.team)
	var foe := _pick_target(sim, me) if _rage() else _nearest_known(sim, me)
	# My choice, for the team's next build: who I'm on and whom I can see.
	var saw := 0
	for i in sim.creatures.size():
		if me.is_foe(sim.creatures[i]) and not _unseen.has(sim.creatures[i]):
			saw |= 1 << i
	var slot := sim.creatures.find(foe) if foe != null else -1
	_team.note(me_idx, slot, saw, -1 if _target_forced else slot)
	PerfLog.since("ai target", t0)
	if foe != null and me.state != CreatureSim.State.KO:
		t0 = PerfLog.now()
		_decide(sim, me, foe)
		PerfLog.since("ai decide", t0)
		# Normal and up aim attacks exactly (360 degrees), like a stick or a mouse; Easy
		# keeps to the 8 directions a keyboard gives. Rage leads a moving target. A foe out
		# of sight is aimed at where it was last seen.
		if level >= 1 and ((_out & PlayerInput.ATTACK_BITS) or me.state == CreatureSim.State.ATTACK) \
				and not (_out & SimDefs.IN_AIM):
			var at := _aim_point(me, foe) if _rage() else _seen(foe)
			_out |= SimDefs.aim_bits(at - me.pos)
	_prev = _out
	last_bits = _out
	return _out


# ------------------------------------------------------------------ sight

## What the team sees this tick: the foes out of sight (stealth, or Vision says no) and
## where each foe was last seen. Called once per tick, before any decision.
func _look(sim: MatchSim, me: CreatureSim) -> void:
	_vision.observe(sim.events)
	_unseen.clear()
	for o in sim.creatures:
		if not me.is_foe(o):
			continue
		if (o.stealth > 0 and not _mound_in_sight(me, o)) or not _vision.team_sees(sim, me.team, o):
			_unseen[o] = true
			if not _last_seen.has(o):
				_last_seen[o] = o.pos
		else:
			_last_seen[o] = o.pos


## A foe hidden by its own move ("hidden": Digby's Burrow) is still a moving mound of dirt a
## player can see: up close, within MOUND_SIGHT (the brush rule's 34 px), the CPU sees it too and can step off it.
func _mound_in_sight(me: CreatureSim, o: CreatureSim) -> bool:
	return o.state == CreatureSim.State.ATTACK and bool(o.move_def().get("hidden", false)) 		and o.pos.distance_squared_to(me.pos) <= MOUND_SIGHT * MOUND_SIGHT


## The nearest foe by where this team knows it to be (the sim's nearest_opponent, with
## out-of-sight foes counted where they were last seen).
func _nearest_known(sim: MatchSim, me: CreatureSim) -> CreatureSim:
	var best: CreatureSim = null
	var best_d := INF
	for o in sim.creatures:
		if not me.is_foe(o) or o.state == CreatureSim.State.KO:
			continue
		var d := _seen(o).distance_squared_to(me.pos)
		if d < best_d:
			best_d = d
			best = o
	return best


## Whether this team can see `o` this tick.
func _sees(o: CreatureSim) -> bool:
	return not _unseen.has(o)


# ------------------------------------------------------------------ helpers

## Presses a button this tick (a fresh press needs it released the tick before).
func _press(bit: int) -> void:
	if not (_prev & bit):
		_out |= bit


func _hold(bit: int) -> void:
	_out |= bit


## Walks toward `v`: 360 degrees, like a stick, on Normal and Hard; Easy keeps to the 8
## directions a keyboard gives.
func _move_toward(v: Vector2) -> void:
	_hold(SimDefs.move_bits(v) if level >= 1 else SimDefs.bits_from_dir(v.normalized()))


## Walks to the point `goal`: straight when no fixed piece is in the way (healing holes
## are left to `_steer`, as before maps existed, so open-floor play is unchanged), else
## along a path round the walls, fences and pits (replanned every REPLAN_TICKS or when
## the goal moves). `weave` is added to the straight step (the chase's sidestep), never
## to the path, so the detour stays on open floor.
func _go_to(sim: MatchSim, me: CreatureSim, goal: Vector2, weave := Vector2.ZERO) -> void:
	var t0 := PerfLog.now()
	var straight := NavGrid.clear_line(sim.terrain, me.pos, goal, me.radius, false)
	PerfLog.since("ai line", t0)
	if straight:
		_path = PackedVector2Array()
		var v := (goal - me.pos).normalized() + weave
		if _rage():
			_go(sim, me, v)
		else:
			_move_toward(v)
		return
	_path_t -= 1
	if (_path.is_empty() or _path_t <= 0 or _path_goal.distance_to(goal) > 20.0) and _replan_turn(sim):
		var t1 := PerfLog.now()
		_path = NavGrid.shared(sim.terrain).path(me.pos, goal)
		PerfLog.since("ai path", t1)
		_path_goal = goal
		_path_t = REPLAN_TICKS
	# Drop waypoints already reached, or that the next one can be walked to straight.
	while _path.size() > 1 and (me.pos.distance_to(_path[0]) < WAYPOINT_REACHED
			or NavGrid.clear_line(sim.terrain, me.pos, _path[1], me.radius, false)):
		_path.remove_at(0)
	if _path.is_empty():
		_move_toward(_steer(sim, me, goal - me.pos))  # no way round: press on as before
		return
	var d := _steer(sim, me, _path[0] - me.pos)
	if d != Vector2.ZERO:
		_move_toward(d)


# ------------------------------------------------------------------ arena hazards

## How many ticks before a meteor lands each level notices its shadow (Easy late, Hard
## and Rage as soon as it shows).
const HAZARD_NOTICE := [28, 48, 999, 999]
## How far round itself (cells) a CPU looks for rubble to shelter behind from a wave.
const SHELTER_LOOK := 18
var _shelter := Vector2.INF  ## the spot behind rubble picked for this wave (INF: none)
var _shelter_t := 0  ## ticks until it looks again


## Arena hazards (Hazards): steps out of a meteor's shadow, gets behind rubble when a wave
## is coming (Hard and Rage dodge through its front when there's none), and takes a core
## that's close when no foe is on it. Only moves and presses, like a player. True when it
## acted (or holds still in shelter) and the rest of the decision waits.
func _mind_hazards(sim: MatchSim, me: CreatureSim, foe: CreatureSim) -> bool:
	var flee := Vector2.ZERO
	for m in Hazards.meteors_now(sim):
		var left := int(m["land"]) - sim.tick
		if left > int(m["warn"]) or left > int(HAZARD_NOTICE[clampi(level, 0, 3)]):
			continue  # no shadow yet, or not noticed yet
		var d := me.pos - Vector2(m["pos"])
		var need := float(m["radius"]) + me.radius + 6.0
		var dl := d.length()
		if dl < need:
			flee += (d / dl if dl > 0.01 else Vector2.RIGHT) * (need - dl + 4.0)
	if flee != Vector2.ZERO:
		_go_to(sim, me, me.pos + flee.normalized() * 28.0)
		return true
	var w := Hazards.wave_now(sim)
	if w.is_empty() or (w["done"] as Array).has(me.id):
		_shelter = Vector2.INF
		_shelter_t = 0
	else:
		var dir: Vector2 = w["dir"]
		var near_foe := foe != null and _seen(foe).distance_to(me.pos) <= _reach_of(foe, me) + 6.0
		if Hazards.shelters(w["def"], sim.terrain, me, dir):
			return not near_foe  # behind rubble: stay there (fight only what comes to us)
		_shelter_t -= 1
		if _shelter_t <= 0:
			_shelter = _find_shelter(sim, me, dir, w["def"])
			_shelter_t = 20
		if _shelter != Vector2.INF:
			_go_to(sim, me, _shelter)
			return true
		if level >= 2 and int(w["phase"]) == Hazards.ACTIVE and me.can_dodge():
			var fr := sim.floor_rect()
			var side := int(w["side"])
			var speed := Hazards.wave_len(fr, side) / float(maxi(1, Hazards.ticks_of((w["def"] as Dictionary).get("sweep_seconds", 1.0))))
			var gap := Hazards.wave_s(fr, side, me.pos) - float(w["front"])
			if gap > 0.0 and gap < speed * 3.0:
				_move_toward(-dir)
				_press(SimDefs.IN_DODGE)
				return true
	for pk in sim.hazard_pickups:
		var at: Vector2 = pk["pos"]
		if me.pos.distance_to(at) < 110.0 and not sim.terrain.is_hole_at(at) \
				and (foe == null or _seen(foe).distance_to(me.pos) > _reach_of(foe, me) + 16.0):
			_go_to(sim, me, at)
			return true
	return false


## The nearest spot behind rubble (downstream of a WALL cell, sheltered from a wave going
## `dir`) within SHELTER_LOOK cells, on floor it can stand on; INF when there's none.
func _find_shelter(sim: MatchSim, me: CreatureSim, dir: Vector2, d: Dictionary) -> Vector2:
	var t := sim.terrain
	var c0 := t.world_to_cell(me.pos)
	var best := Vector2.INF
	var best_d := INF
	for cy in range(c0.y - SHELTER_LOOK, c0.y + SHELTER_LOOK + 1):
		for cx in range(c0.x - SHELTER_LOOK, c0.x + SHELTER_LOOK + 1):
			var c := Vector2i(cx, cy)
			if t.get_cell(c) != TerrainGrid.WALL:
				continue
			var spot := t.cell_center(c) + dir * (SimDefs.CELL * 0.5 + me.radius + 3.0)
			if not t.is_walkable(t.get_cell(t.world_to_cell(spot))) or t.body_blocked(spot, me.radius) \
					or not sim.floor_rect().grow(-me.radius).has_point(spot):
				continue
			var sh: Dictionary = d.get("shelter", {})
			if not Hazards.sheltered(t, spot, me.radius, dir, float(sh.get("depth", 48)), float(sh.get("lane", 0.6))):
				continue
			var dd := spot.distance_squared_to(me.pos)
			if dd < best_d:
				best_d = dd
				best = spot
	return best


## Whether this CPU may run a path search this tick. A search costs up to a few ms on a
## big map, and a goal that keeps moving (a flag carrier) asks for one every tick, so on
## a crowded field the CPUs take turns: one search a tick at most, each CPU's turn coming
## round every `creatures.size()` ticks (a 4v4: 133 ms). Meanwhile it keeps to its last
## path, or walks straight at the goal. With two on the field there's no need, so a 1v1
## plays exactly as before.
func _replan_turn(sim: MatchSim) -> bool:
	var n := sim.creatures.size()
	return n <= 2 or (sim.tick + me_idx) % n == 0


func _ai(me: CreatureSim) -> Dictionary:
	return me.def.get("ai", {})


func _roll(chance: float) -> bool:
	return rng.randf() < chance


## How far the foe's current attack can reach, from the foe's position.
## A foe with a grab ready beats an armored stance (Bedrock): grabs go through armor, so
## a tank doesn't root in front of one.
func _foe_grab_ready(foe: CreatureSim) -> bool:
	var moves: Dictionary = foe.moves()
	for mid in moves:
		if bool(moves[mid].get("grab", false)) and _usable(foe, mid):
			return true
	return false


## How far this fighter's roll carries: its speed for the frames, slowed to 0.4 in the last
## four ticks (CreatureSim._update_dodge). A blink dodge uses its teleport distance.
static func _roll_distance(me: CreatureSim) -> float:
	var dg: Dictionary = me.def["dodge"]
	if dg.has("blink"):
		return float(dg["blink"].get("distance", 0.0))
	var frames := int(dg["frames"])
	var spd := float(dg["speed"])
	return spd * float(maxi(0, frames - 4)) + spd * 0.4 * float(mini(4, frames))


## About how far a roll carries.
const DODGE_DISTANCE := 50.0


## How close the foe must be for an area Surge: the fighter's "surge_range", else (a strike
## Surge with no projectile and no armor) its widest segment's reach minus a margin.
func _surge_range(me: CreatureSim, ai: Dictionary) -> float:
	if ai.has("surge_range"):
		return float(ai["surge_range"])
	var mv: Dictionary = me.moves().get("surge", {})
	if mv.is_empty() or mv.has("projectile") or mv.has("armor"):
		return 0.0
	return me.move_range("surge") - 10.0


func _threat_range(foe: CreatureSim, me: CreatureSim) -> float:
	var mv := foe.move_def()
	var r := float(mv.get("reach", 14)) + float(mv.get("hit_radius", 10)) + me.radius
	if not mv.has("projectile"):
		# The widest hit segment of the move (a Surge's last ring is wider than its first).
		r = foe.move_range(foe.move_id) + 1.0 + me.radius
	var dash: Dictionary = mv.get("dash", {})
	if not dash.is_empty():
		r += float(dash["speed"]) * float(int(dash["to"]) - int(dash["from"]))
	r += float(mv.get("lunge", 0.0)) * float(mv.get("startup", 0))
	return r + 6.0


# ------------------------------------------------------------------ decisions

func _decide(sim: MatchSim, me: CreatureSim, foe: CreatureSim) -> void:
	# Sinkhole: the ring under us (or a cell short of it) is cracked and about to drop.
	# Nothing matters more than getting off it (a dash or dodge in progress finishes first).
	if sim.sink_ring >= 0 and me.state in [CreatureSim.State.IDLE, CreatureSim.State.MOVE, CreatureSim.State.GUARD] \
			and not sim.sink_safe.grow(-1).has_point(sim.terrain.world_to_cell(me.pos)):
		_go_to(sim, me, sim.floor_rect().get_center())
		return
	# Arena hazards (a mutator's): meteor shadows, a wave coming, a core to pick up.
	if not sim.hazards.is_empty() and me.state in [CreatureSim.State.IDLE, CreatureSim.State.MOVE, CreatureSim.State.GUARD] \
			and _mind_hazards(sim, me, foe):
		return
	var to_foe := _seen(foe) - me.pos
	# A goal the mode's rules give this fighter (Capture the Flag: the flag, home, the
	# carrier, the base): go there when outside it, unless the foe is in reach to fight;
	# an urgent one (running the flag home) even then.
	if me.id < sim.goals.size() and not (sim.goals[me.id] as Array).is_empty() \
			and me.state in [CreatureSim.State.IDLE, CreatureSim.State.MOVE, CreatureSim.State.GUARD]:
		var g: Array = sim.goals[me.id]
		var gp: Vector2 = g[0]
		# Carrying with a foe on us: the rules name a teammate open ahead; pass to them
		# (TAG, aimed), sooner the better the level.
		if g.size() > 3 and int(g[3]) >= 0 and _roll(0.03 + 0.02 * level):
			_press(SimDefs.IN_TAG)
			_out |= SimDefs.aim_bits(sim.creatures[int(g[3])].pos - me.pos)
		if me.pos.distance_to(gp) > float(g[1]) and (bool(g[2]) or to_foe.length() > _reach_of(me, foe) + 12.0):
			_go_to(sim, me, gp)
			return
	# King of the Crater: the zone is the point. Outside it, go to it unless the foe is
	# right here to fight; inside, fight as usual (and come back if the fight drifts).
	if sim.zone_r > 0.0 and me.state in [CreatureSim.State.IDLE, CreatureSim.State.MOVE, CreatureSim.State.GUARD]:
		var out := me.pos.distance_to(sim.zone_pos) > sim.zone_r - 6.0
		if out and (to_foe.length() > _reach_of(me, foe) + 12.0 or _seen(foe).distance_to(sim.zone_pos) <= sim.zone_r):
			_go_to(sim, me, sim.zone_pos)
			return
	# Out of sight (Vision: brush, fences, walls; or invisible): to_foe is to where it was
	# last seen.
	_foe_hidden = not _sees(foe)
	var dist := to_foe.length()

	# Stunned: maybe burn energy on a breakaway, otherwise nothing to do.
	if me.is_stunned() or me.state == CreatureSim.State.KNOCKDOWN or me.state == CreatureSim.State.FALLING:
		_route = []
		if me.is_stunned() and me.combo_hits >= CreatureSim.BREAKAWAY_MIN_HITS \
				and me.energy >= CreatureSim.BREAKAWAY_COST and _break_combo_checked != me.combo_hits:
			_break_combo_checked = me.combo_hits
			if me.combo_hits == CreatureSim.BREAKAWAY_MIN_HITS and _roll(float(p["breakaway"])) \
					and (not _rage() or _rage_breaks_away(sim, me)):
				_press(SimDefs.IN_GUARD)
				_press(SimDefs.IN_DODGE)
		return
	_break_combo_checked = -1

	if me.state == CreatureSim.State.ATTACK:
		_continue_attack(sim, me, foe, dist)
		if _rage():
			_rage_attack_move(sim, me, foe)
		return
	if me.state == CreatureSim.State.DODGE:
		return

	if _rage():
		if _rage_defend(sim, me):
			return
		if _maybe_tag(me, dist):
			return
		if _rage_punish(sim, me, foe, to_foe, dist):
			return
		_rage_neutral(sim, me, foe, to_foe, dist)
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
	var t0 := PerfLog.now()
	_continue_attack_now(sim, me, foe, dist)
	PerfLog.since("ai attack", t0)


func _continue_attack_now(sim: MatchSim, me: CreatureSim, foe: CreatureSim, dist: float) -> void:
	if me.charging:
		# A move that does something else when held to a full charge (Gulp: tapped, a hook;
		# held, a swallow): decide once per throw whether to hold it all the way.
		var mv := me.move_def()
		if mv.has("hold") and _hold_serial != me.attack_serial:
			_hold_serial = me.attack_serial
			# A foe out of the tapped version's reach gets the held one (Runoff's wave);
			# otherwise it's a roll (Gulp: a hook or a swallow, same reach either way).
			var tap_reach := float(mv.get("reach", 0.0)) + float(mv.get("hit_radius", 0.0)) + foe.radius
			var out_of_tap := not mv.has("projectile") and dist > tap_reach
			if _breaks_guard_held_only(mv):
				# It only breaks guard at a full charge (Sack Smack): thrown at a guard, held
				# all the way; otherwise it's a plain heavy, tapped.
				if _guard_press or foe.state == CreatureSim.State.GUARD:
					_hold_heavy = int(mv.get("charge_max", 0)) + 1
					_hold_bit = int(ACTION_BIT.get(me.move_id, SimDefs.IN_HEAVY))
			elif me.move_id != "heavy" and (out_of_tap or _roll(0.25 + 0.1 * level)):
				_hold_heavy = int(mv.get("charge_max", 0)) + 1
				_hold_bit = int(ACTION_BIT.get(me.move_id, SimDefs.IN_HEAVY))
		if _hold_heavy > 0:
			_hold_heavy -= 1
			_hold(_hold_bit if me.move_id != "heavy" else SimDefs.IN_HEAVY)
		_guard_press = false
		return
	# A steerable dash (Burrow): steer it toward the foe, to come up under them, while it
	# runs; once he has popped up the string below carries on (the juggle after the launch).
	var steer_dash: Dictionary = me.move_def().get("dash", {})
	if float(steer_dash.get("steer", 0.0)) > 0.0 and me.state_t <= int(steer_dash.get("to", 0)):
		_hold(SimDefs.bits_from_dir((_seen(foe) - me.pos).normalized()))
		return
	# Holding a gaze (Stone Gaze): break out with a jab once the foe walks in close.
	var gz: Dictionary = me.move_def().get("gaze", {})
	if not gz.is_empty() and dist < float(_ai(me).get("range", 22)) + me.radius + foe.radius \
			and me.state_t >= int(gz.get("release_from", 9999)):
		_hold(SimDefs.bits_from_dir((_seen(foe) - me.pos).normalized()))
		_press(SimDefs.IN_LIGHT)
		return
	# Rage in an armored stance (Bedrock): answer out of it the moment the foe is in reach.
	var armor: Dictionary = me.move_def().get("armor", {})
	if _rage() and not armor.is_empty() and me.state_t >= int(armor.get("release_from", 9999)) \
			and me.state_t <= int(armor["to"]) and dist < _reach_of(me, foe):
		_hold(SimDefs.move_bits(_seen(foe) - me.pos))
		_press(SimDefs.IN_HEAVY if _usable(me, "heavy") and _roll(0.4) else SimDefs.IN_LIGHT)
		return
	# Rage's knife strings keep coming at range, hit or miss: a mage's lights are its
	# shots, and backing off while throwing is the whole plan.
	if _rage() and not me.connected and me.move_type() == "light" \
			and me.moves().get("light_1", {}).has("projectile") and dist > 45.0:
		_press(SimDefs.IN_LIGHT)
		return
	if not me.connected or _route_drop:
		return
	if foe.state == CreatureSim.State.GUARD or (_rage() and _blocked_serial == me.attack_serial):
		# Blocked: a grab beats a guard; otherwise stop pressing (Rage remembers the block
		# even once the foe drops its guard to punish: pushing the string on would run
		# into that punish).
		var grab := String(_ai(me).get("grab", ""))
		if _rage():
			grab = _guard_answer(me, dist)
		if grab != "" and _usable(me, grab) and me.move_rank(grab) > me.move_rank(me.move_id) \
				and foe.state == CreatureSim.State.GUARD:
			_press(int(ACTION_BIT[grab]))
			_guard_press = true
			return
		# A guard low on stamina is worn down instead: the string goes on, and the hit
		# that empties it lands clean.
		if not _guard_wearing(foe):
			return
	# On the first contact, pick a route; each new move after that is one step along it.
	if _route.is_empty():
		_route = _pick_route(me, dist, foe)
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
		if action == "light" or _usable(me, me.action_move(action)):
			_press(int(ACTION_BIT[action]))


func _pick_route(me: CreatureSim, dist: float, foe: CreatureSim = null) -> Array:
	# First contact on a later light of the string (the first knife missed, the second hit):
	# the light routes still apply, from that point of the string.
	var k := _string_index(me)
	if k < 0:
		# A route that opens with this very move (Digby's pop-up out of Burrow: the launch,
		# then the juggle string and the heavy) is followed as written.
		for r in _ai(me).get("routes", []):
			if r.size() > 1 and String(r[0]) != "light" and me.action_move(String(r[0])) == me.move_id:
				return r.duplicate()
		# Started with something else (a counter, a poke): finish with whatever ranks higher.
		var tail: Array = [me.move_id]
		for act in ["heavy", "skill_2", "skill_1", "surge"]:
			var mid := me.action_move(act)
			if me.move_rank(mid) > me.move_rank(me.move_id) and _usable(me, mid) \
					and not me.moves()[mid].has("counter"):
				tail.append(act)
				break
		return tail
	var routes: Array = _ai(me).get("routes", [["light"]])
	# A ranged fighter (Chef Cerebro) that landed its opener from afar finishes with
	# moves that reach that far.
	if _ai(me).has("far_routes") and dist > float(_ai(me).get("far_from", 9999)):
		routes = _ai(me)["far_routes"]
	elif _ai(me).has("setup_routes") and foe != null \
			and not foe.has_mark(String((_ai(me).get("setup", {}) as Dictionary).get("mark", ""))):
		# Up close on a foe not set up yet (not tenderized): routes that set it up first.
		routes = _ai(me)["setup_routes"]
	var longest: Array = []
	var whole: Array = []  ## the first route affordable in full
	for r0 in routes:
		if String(r0[0]) != "light":
			continue  # an opener route (a skill first) is for that opener, above
		var r: Array = r0
		if k > 0:
			var lead := 0
			while lead < r0.size() and String(r0[lead]) == "light":
				lead += 1
			if lead <= k:
				continue  # the string is already past this route's lights
			r = r0.slice(k)
		var ok := true
		var prefix: Array = []
		for act in r:
			if act != "light" and not _usable(me, me.action_move(String(act))):
				ok = false
				break
			prefix.append(act)
		if ok and whole.is_empty() and (_rage() or _roll(0.8)):
			whole = r.duplicate()
			if not _rage():
				return whole
		if prefix.size() > longest.size():
			longest = prefix
	# Rage takes the longest run it can afford: a route that ends in a cooling skill
	# still has its heavy, which beats a plain three-light string.
	if _rage():
		if whole.is_empty() and longest.is_empty():
			return [me.move_id]  # no route reaches this far into the string: it ends here
		return whole if whole.size() >= longest.size() else longest
	if whole.is_empty() and k > 0:
		return [me.move_id]
	return whole if not whole.is_empty() else routes[routes.size() - 1].duplicate()


## Where the current move sits in the light string: 0 for light_1, 1 for the light its
## "next" leads to, and so on; -1 for anything that isn't in the string.
func _string_index(me: CreatureSim) -> int:
	var mid := "light_1"
	for i in 8:
		if mid == me.move_id:
			return i
		mid = String(me.moves().get(mid, {}).get("next", ""))
		if mid == "":
			break
	return -1


func _defend(sim: MatchSim, me: CreatureSim, foe: CreatureSim, dist: float) -> bool:
	var t0 := PerfLog.now()
	var out := _defend_now(sim, me, foe, dist)
	PerfLog.since("ai defend", t0)
	return out


func _defend_now(sim: MatchSim, me: CreatureSim, foe: CreatureSim, dist: float) -> bool:
	# Keep doing a defense already chosen.
	if _defense != "":
		_defense_t -= 1
		var foe_busy := foe.state == CreatureSim.State.ATTACK
		if _defense == "guard" and (foe_busy or _defense_t > 0) and _defense_t > -30 \
				and me.can_guard():
			_hold(SimDefs.IN_GUARD)
			return true
		_defense = ""

	var threat := false
	var grab_threat := false
	var serial := foe.attack_serial
	if not _foe_hidden and foe.state == CreatureSim.State.ATTACK and not foe.charging \
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
	if not _foe_hidden and foe.charging and dist < 60.0:
		threat = true
		serial = 200000 + foe.attack_serial

	if not threat or serial == _seen_serial:
		return false
	_seen_serial = serial
	if not _roll(float(p["defend"])):
		return false

	var counter := String(_ai(me).get("counter", ""))
	if foe.charging and not grab_threat and counter != "" and _usable(me, counter) and _roll(0.35):
		_press(int(ACTION_BIT[counter]))  # a Slip under a held slam: a gamble on when it drops
		return true
	if grab_threat or foe.charging:
		_dodge_away(me, foe)
		return true
	if counter != "" and _usable(me, counter) and foe.state == CreatureSim.State.ATTACK \
			and String(foe.move_def().get("type", "")) != "surge" and _roll(0.5):
		_press(int(ACTION_BIT[counter]))
		return true
	if _roll(0.7) and _guard_holds(me, _strike_drain(me, foe)):
		_defense = "guard"
		_defense_t = 20
		_hold(SimDefs.IN_GUARD)
	else:
		_dodge_away(me, foe)
	return true


func _dodge_away(me: CreatureSim, foe: CreatureSim) -> void:
	var away := (me.pos - _seen(foe)).normalized()
	if not me.can_dodge():
		# Out of stamina or the dodge is recharging (Chef Cerebro's blink): guard instead,
		# or, exhausted (no guard either), back off.
		if me.can_guard():
			_defense = "guard"
			_defense_t = 20
			_hold(SimDefs.IN_GUARD)
		else:
			_hold(SimDefs.bits_from_dir(away))
		return
	var side := Vector2(-away.y, away.x) * (1.0 if _roll(0.5) else -1.0)
	_hold(SimDefs.bits_from_dir((away + side).normalized()))
	_press(SimDefs.IN_DODGE)


## A move it can throw right now: usable, and (a fold-then-use craft) already folded. An
## unfolded craft's press would fold it instead, which only _maybe_fold decides to do.
static func _usable(c: CreatureSim, mid: String) -> bool:
	return c.can_use(mid) and not c.needs_fold(mid)


## Fold-then-use (ai "fold": the crafts in the order it wants them): with the foe far
## enough not to punish the fold, and a sheet to fold with, it presses an unfolded
## craft's button, like a player does. It keeps three sheets back once its Surge is
## nearly full, when the Surge needs them.
func _maybe_fold(me: CreatureSim, foe: CreatureSim, dist: float) -> bool:
	var order: Array = _ai(me).get("fold", [])
	if order.is_empty() or me.state == CreatureSim.State.ATTACK:
		return false
	var safe := float(_ai(me).get("fold_safe", 90.0)) + foe.radius
	if dist < safe or foe.state == CreatureSim.State.ATTACK and dist < safe * 1.4:
		return false
	var surge_sheets := int(me.moves().get("surge", {}).get("sheets_cost", 0))
	if surge_sheets > 0 and me.energy >= CreatureSim.MAX_ENERGY * 0.75 and me.sheets <= surge_sheets:
		return false
	for mid in order:
		if me.needs_fold(String(mid)) and me.can_use(String(mid)):
			var bit: int = int({"heavy": SimDefs.IN_HEAVY, "skill_1": SimDefs.IN_SKILL1, "skill_2": SimDefs.IN_SKILL2}.get(String(mid), 0))
			if bit != 0:
				_press(bit)
				return true
	return false


func _neutral(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float) -> void:
	var t0 := PerfLog.now()
	_neutral_now(sim, me, foe, to_foe, dist)
	PerfLog.since("ai neutral", t0)


func _neutral_now(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float) -> void:
	_route = []
	_route_drop = false
	var ai := _ai(me)
	if _maybe_fold(me, foe, dist):
		return
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
		if bool(ai.get("wakeup_charge", false)) and dist < 46.0 and _usable(me, "heavy") \
				and foe.state == CreatureSim.State.KNOCKDOWN and _roll(0.05 + 0.1 * level):
			_hold_heavy = clampi(foe.stun - 4, 6, 45)
			_press(SimDefs.IN_HEAVY)
			_hold(SimDefs.bits_from_dir(to_foe.normalized()))
			return
		if dist > want + 14.0:
			_go_to(sim, me, me.pos + to_foe)
		return

	# Free punish on a crumpled or stunned foe.
	if foe.is_stunned() and dist < want + 10.0:
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(SimDefs.IN_LIGHT)
		return

	_think_t -= 1
	if _think_t > 0:
		_follow_plan(sim, me, foe, to_foe, dist, want)
		return
	_think_t = int(p["think"]) + rng.randi_range(0, 6)

	if _roll(float(p["mistake"])):
		_plan = "wait"
		return

	# Long-range pokes: a shockwave or a dash punch.
	var poke := String(ai.get("poke", ""))
	var pr: Array = ai.get("poke_range", [0, 0])
	var poke_lined: bool = poke == "" or not me.moves().get(poke, {}).has("projectile") or absf(to_foe.y) < 18.0
	if poke != "" and _usable(me, poke) and dist >= float(pr[0]) and dist <= float(pr[1]) \
			and poke_lined and _roll(0.25 * float(p["aggression"]) + 0.05):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(int(ACTION_BIT[poke]))
		return

	# A lob (Pinecone Bomb) lands a fixed distance ahead: throw it when the foe is about there.
	var lob := String(ai.get("lob", ""))
	var lr: Array = ai.get("lob_range", [0, 0])
	if lob != "" and _usable(me, lob) and dist >= float(lr[0]) and dist <= float(lr[1]) \
			and _roll(0.25 * float(p["aggression"]) + 0.05):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(int(ACTION_BIT[lob]))
		# A lob that charges for distance (Pinecone Bomb): hold it just long enough to land
		# on the foe.
		var lmv: Dictionary = me.moves().get(lob, {})
		var lp: Dictionary = lmv.get("projectile", {})
		if lmv.has("charge_max") and lp.has("range_charged"):
			var k := clampf((dist - float(lp["range"])) / maxf(1.0, float(lp["range_charged"]) - float(lp["range"])),
				0.0, 1.0)
			_hold_heavy = int(round(k * float(lmv["charge_max"])))
			_hold_bit = int(ACTION_BIT[lob])
		return

	# A gaze (Stone Gaze) slows a foe who is looking this way: use it at mid range.
	var gaze := String(ai.get("gaze", ""))
	var gzr: Array = ai.get("gaze_range", [0, 0])
	if gaze != "" and _usable(me, gaze) and dist >= float(gzr[0]) and dist <= float(gzr[1]) \
			and foe.facing.dot(-to_foe.normalized()) > 0.3 and _roll(0.15 + 0.1 * level):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(int(ACTION_BIT[gaze]))
		return

	# A slowing puddle round his feet (Syrup Slick) when the foe is close.
	var zone := String(ai.get("zone", ""))
	var zr: Array = ai.get("zone_range", [0, 0])
	if zone != "" and _usable(me, zone) and dist >= float(zr[0]) and dist <= float(zr[1]) \
			and _roll(0.1 + 0.06 * level):
		_press(int(ACTION_BIT[zone]))
		return

	# Going invisible (Tiptoe) to sneak in from mid range.
	var sneak := String(ai.get("stealth", ""))
	var sr: Array = ai.get("stealth_range", [0, 0])
	if sneak != "" and _usable(me, sneak) and me.stealth <= 0 and dist >= float(sr[0]) and dist <= float(sr[1]) \
			and _roll(0.12 + 0.06 * level):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(int(ACTION_BIT[sneak]))
		return

	# A tunnel (Burrow) closes a long gap safely, out of reach while underground.
	var burrow := String(ai.get("burrow", ""))
	var br: Array = ai.get("burrow_range", [0, 0])
	if burrow != "" and _usable(me, burrow) and dist >= float(br[0]) and dist <= float(br[1]) \
			and _roll(0.08 + 0.06 * level):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(int(ACTION_BIT[burrow]))
		return

	# A line Surge (Knife Flurry) works from neutral when the foe is lined up in range.
	var surge_line := float(ai.get("surge_line", 0))
	if surge_line > 0.0 and dist < surge_line and _usable(me, "surge") and _lined_up(to_foe, foe) \
			and _roll(0.2 + 0.15 * level):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(SimDefs.IN_SURGE)
		return

	# An area Surge (Storm Drain) works straight from neutral when the foe is close.
	var surge_range := _surge_range(me, ai)
	if surge_range > 0.0 and dist < surge_range and _usable(me, "surge") \
			and not (me.moves()["surge"].has("armor") and _foe_grab_ready(foe)) and _roll(0.3 + 0.2 * level):
		_press(SimDefs.IN_SURGE)
		return

	# A guarding foe invites a grab.
	var grab := String(ai.get("grab", ""))
	var grab_reach := float(ai.get("grab_range", want - me.radius - foe.radius + 10.0)) + me.radius + foe.radius
	if grab != "" and foe.state == CreatureSim.State.GUARD and dist < grab_reach + 8.0 and _usable(me, grab):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(int(ACTION_BIT[grab]))
		return

	# A kiting fighter peels off a foe that walked in close with its grab.
	if bool(ai.get("kite", false)) and grab != "" and dist < grab_reach and _usable(me, grab) \
			and _roll(0.3 + 0.15 * level):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		_press(int(ACTION_BIT[grab]))
		return

	# A ranged opener only lands lined up: otherwise step sideways to line up first.
	var ranged: bool = me.moves().get("light_1", {}).has("projectile")
	if ranged and dist <= want + 6.0 and not _lined_up(to_foe, foe):
		_move_toward(Vector2(0.0, signf(to_foe.y)) if absf(to_foe.y) < absf(to_foe.x) else Vector2(signf(to_foe.x), 0.0))
		return

	if dist <= want + 6.0 and _roll(float(p["aggression"])):
		_hold(SimDefs.bits_from_dir(to_foe.normalized()))
		if _roll(0.15) and _usable(me, "heavy"):
			_hold_heavy = rng.randi_range(0, 12)
			_press(SimDefs.IN_HEAVY)
		else:
			_press(SimDefs.IN_LIGHT)
		return

	if dist > want + 6.0:
		_plan = "approach"
	elif bool(ai.get("kite", false)) and dist < want - 24.0:
		_plan = "retreat"  # keep the foe at knife range
	elif _roll(0.4):
		_plan = "retreat"
	elif _roll(0.5):
		_plan = "circle"
		_plan_dir = Vector2(-to_foe.y, to_foe.x).normalized() * (1.0 if _roll(0.5) else -1.0)
	else:
		_plan = "wait"
	_follow_plan(sim, me, foe, to_foe, dist, want)


## Whether a straight throw in the nearest of 8 directions would meet the foe.
func _lined_up(to_foe: Vector2, foe: CreatureSim) -> bool:
	var d := CreatureSim._snap8(to_foe)
	var off := absf(to_foe.x * d.y - to_foe.y * d.x)
	return off < foe.radius + 3.0


func _follow_plan(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, want: float) -> void:
	match _plan:
		"approach":
			if dist > want:
				_go_to(sim, me, me.pos + to_foe)
		"retreat":
			if dist < want + 30.0:
				_move_toward(-to_foe)
		"circle":
			_move_toward(_plan_dir + to_foe.normalized() * 0.3)


# ------------------------------------------------------------------ Rage

func _rage() -> bool:
	return level >= RAGE


## Rage spends half its energy on a breakaway only when it's worth more than a Surge
## later: when it's hurt, or the combo's owner has a Surge to finish with.
func _rage_breaks_away(sim: MatchSim, me: CreatureSim) -> bool:
	var hurt := me.hp / me.max_hp < 0.5
	var surging := false
	for o in sim.creatures:
		if me.is_foe(o) and _sees(o) and o.energy >= CreatureSim.MAX_ENERGY and o.pos.distance_to(me.pos) < 80.0:
			surging = true
	if me.energy >= CreatureSim.MAX_ENERGY and not hurt:
		return false  # keep the Surge
	return hurt or surging or me.energy >= CreatureSim.BREAKAWAY_COST * 1.5


func _style(me: CreatureSim) -> Dictionary:
	var name := String(_ai(me).get("style", me.def.get("role", "fighter")))
	return STYLES.get(name, STYLES["fighter"])


## Who to fight: the nearest foe, or by class in a team battle (an assassin goes for the
## weakest, a tank for whoever is on its most hurt teammate). Kept for a moment, so it
## doesn't dither between two. With a living teammate the team's focus (TeamIntent) comes
## first, unless the class has a better idea: the assassin's much weaker foe, the tank's
## peel, and for anyone the foe already in its face.
func _pick_target(sim: MatchSim, me: CreatureSim) -> CreatureSim:
	var focus := _focus(sim, me)
	var focus_slot := _team.focus if focus != null else -1
	if _target != null and _target_t > 0 and me.is_foe(_target) and _target.state != CreatureSim.State.KO \
			and focus_slot == _focus_slot:
		_target_t -= 1
		return _target
	var how := String(_style(me)["target"])
	var ally := _hurt_ally(sim, me) if how == "peel" else null
	var best: CreatureSim = null
	var best_score := INF
	var nearest: CreatureSim = null
	var nearest_d := INF
	for o in sim.creatures:
		if not me.is_foe(o) or o.state == CreatureSim.State.KO:
			continue
		var at := _seen(o)  # a foe out of sight counts where it was last seen
		var d := at.distance_to(me.pos)
		var score := d
		if how == "weakest":
			score = d * 0.5 + o.hp / o.max_hp * 220.0
		elif ally != null:
			score = at.distance_to(ally.pos) + d * 0.3
		if score < best_score:
			best_score = score
			best = o
		if d < nearest_d:
			nearest_d = d
			nearest = o
	_target_forced = false
	if focus != null and best != null and focus != best:
		# A foe in reach is fought first; for a kiter, one inside the band it kites at.
		var close := kite_band(me, nearest).x if String(_style(me)["plan"]) == "kite" else _reach_of(nearest, me) + 16.0
		var in_my_face := nearest != null and nearest_d <= close
		var much_weaker := how == "weakest" and best.hp / best.max_hp < focus.hp / focus.max_hp - 0.25
		var peeling := how == "peel" and ally != null
		if not (much_weaker or peeling):
			best = nearest if in_my_face else focus
			_target_forced = in_my_face
	_focus_slot = focus_slot
	_target = best
	_target_t = 30
	return best if best != null else _nearest_known(sim, me)


## The team's focus target, when this CPU plays to it: team intent on, a living teammate
## (alone, its own pick is the team's), and a focus that is a living foe.
func _focus(sim: MatchSim, me: CreatureSim) -> CreatureSim:
	if not intent or _team == null or _team.focus < 0:
		return null
	var f: CreatureSim = sim.creatures[_team.focus]
	if not me.is_foe(f) or f.state == CreatureSim.State.KO:
		return null
	for o in sim.creatures:
		if o != me and o.team == me.team and o.state != CreatureSim.State.KO:
			return f
	return null


## The teammate with the least health left, if one is under 70%.
func _hurt_ally(sim: MatchSim, me: CreatureSim) -> CreatureSim:
	var best: CreatureSim = null
	for o in sim.creatures:
		if o == me or me.is_foe(o) or o.state == CreatureSim.State.KO:
			continue
		if o.hp / o.max_hp < 0.7 and (best == null or o.hp / o.max_hp < best.hp / best.max_hp):
			best = o
	return best


## Where the foe is, as far as this fighter's team knows: where it was last seen while
## it's out of sight (invisible, in brush, behind a wall or fence), which is the point
## of hiding.
func _seen(foe: CreatureSim) -> Vector2:
	if _unseen.has(foe):
		return _last_seen.get(foe, foe.pos)
	return foe.pos


## Where to aim: at the foe, or for a thrown move where the foe will be when it arrives.
func _aim_point(me: CreatureSim, foe: CreatureSim) -> Vector2:
	if not _sees(foe):
		return _seen(foe)
	var mid := me.move_id if me.state == CreatureSim.State.ATTACK else "light_1"
	if _out & SimDefs.IN_SKILL1:
		mid = "skill_1"
	elif _out & SimDefs.IN_SKILL2:
		mid = "skill_2"
	elif _out & SimDefs.IN_SURGE:
		mid = "surge"
	var pr: Dictionary = me.moves().get(mid, {}).get("projectile", {})
	if pr.is_empty():
		return foe.pos
	var t := 0.0
	if bool(pr.get("lob", false)):
		t = float(pr.get("time", 30))
	else:
		t = foe.pos.distance_to(me.pos) / maxf(1.0, float(pr.get("speed", 6.0)))
	return foe.pos + foe.walk_vel * clampf(t, 0.0, 40.0)


## Walks toward `v` around holes and walls (Rage).
func _go(sim: MatchSim, me: CreatureSim, v: Vector2) -> void:
	var d := _steer(sim, me, v)
	if d != Vector2.ZERO:
		_move_toward(d)


## The walkable direction closest to `v`: steps that would end in a hole or against a
## wall score lower.
func _steer(sim: MatchSim, me: CreatureSim, v: Vector2) -> Vector2:
	var t0 := PerfLog.now()
	var out := _steer_now(sim, me, v)
	PerfLog.since("ai steer", t0)
	return out


func _steer_now(sim: MatchSim, me: CreatureSim, v: Vector2) -> Vector2:
	if v.length_squared() < 0.0001:
		return Vector2.ZERO
	var want := v.normalized()
	var room := sim.floor_rect().grow(-me.radius - 3.0)
	var best := want
	var best_s := -INF
	var dirs := SimDefs.aim_dirs()
	for i in 32:
		var d: Vector2 = dirs[i * 2]
		var s := d.dot(want)
		if s < -0.1:
			continue
		for k in [6.0, 14.0, 24.0]:
			var at: Vector2 = me.pos + d * (me.radius + k)
			if sim.terrain.is_hole_at(at) or NavGrid.body_blocked(sim.terrain, at, me.radius):
				s -= 2.5 if k < 20.0 else 0.8
				break
		if not room.has_point(me.pos + d * 10.0):
			s -= 1.5
		if s > best_s:
			best_s = s
			best = d
	return best


## A way to back off from `away` that keeps to open floor: away from the foe, but
## preferring directions with room to keep going (out of corners, around holes).
func _open_dir(sim: MatchSim, me: CreatureSim, away: Vector2, look := 34.0) -> Vector2:
	var a := away.normalized() if away.length_squared() > 0.0001 else Vector2.RIGHT
	var room := sim.floor_rect().grow(-me.radius - 4.0)
	var best := a
	var best_s := -INF
	var dirs := SimDefs.aim_dirs()
	for i in 16:
		var d: Vector2 = dirs[i * 4]
		var clear := _clearance(room, me.pos, d)
		var s := d.dot(a) * 1.2 + minf(clear, 100.0) / 100.0
		for k in [8.0, 20.0, look * 0.5, look]:
			var at: Vector2 = me.pos + d * (me.radius + k)
			if sim.terrain.is_hole_at(at) or NavGrid.body_blocked(sim.terrain, at, me.radius):
				s -= 1.5
				break
		if s > best_s:
			best_s = s
			best = d
	return best


## How far from `p` along `d` before leaving `room`.
static func _clearance(room: Rect2, p: Vector2, d: Vector2) -> float:
	var t := INF
	if d.x > 0.001:
		t = minf(t, (room.end.x - p.x) / d.x)
	elif d.x < -0.001:
		t = minf(t, (room.position.x - p.x) / d.x)
	if d.y > 0.001:
		t = minf(t, (room.end.y - p.y) / d.y)
	elif d.y < -0.001:
		t = minf(t, (room.position.y - p.y) / d.y)
	return maxf(t, 0.0)


## Circling `foe` at distance `r`: the tangent, with a pull in or out to hold the radius.
## The direction flips off walls and every so often, so it isn't predictable.
func _orbit_dir(sim: MatchSim, me: CreatureSim, foe: CreatureSim, r: float) -> Vector2:
	var to_foe := _seen(foe) - me.pos
	var dist := to_foe.length()
	var n := to_foe / maxf(dist, 0.001)
	var tangent := Vector2(-n.y, n.x) * _orbit
	_orbit_t -= 1
	var room := sim.floor_rect().grow(-me.radius - 4.0)
	if _orbit_t <= 0 or _clearance(room, me.pos, tangent) < 24.0:
		if _orbit_t <= 0 or _clearance(room, me.pos, -tangent) > 40.0:
			_orbit = -_orbit
			tangent = -tangent
		_orbit_t = rng.randi_range(70, 160)
	return tangent + n * clampf((dist - r) / 30.0, -1.0, 1.0)


## Whether the assassin's way in (Burrow or Tiptoe, `ai.burrow` / `ai.stealth`) is usable now.
func _burst_ready(me: CreatureSim) -> bool:
	var ai := _ai(me)
	for key in ["burrow", "stealth"]:
		var mid := String(ai.get(key, ""))
		if mid != "" and _usable(me, mid) and not (key == "stealth" and me.stealth > 0):
			return true
	return false


## Brush to lurk in: the centre of the nearest standing brush cell within 160 px of `me`
## that lies within this fighter's burst range of where the foe was last seen (its Burrow
## or Tiptoe range, else 40 px past its reach), looked for again every 30 ticks. INF when
## there is none (most arenas): the lurk plan circles instead.
func _cover_spot(sim: MatchSim, me: CreatureSim, foe: CreatureSim) -> Vector2:
	_cover_t -= 1
	if _cover_t > 0:
		if _cover != Vector2.INF and sim.terrain.get_cell(sim.terrain.world_to_cell(_cover)) != TerrainGrid.BRUSH:
			_cover = Vector2.INF  # flattened under someone's dash
		return _cover
	_cover_t = 30
	_cover = Vector2.INF
	var ai := _ai(me)
	var burst: Array = ai.get("burrow_range", ai.get("stealth_range", [0, 0]))
	var lo := float(burst[0])
	var hi := float(burst[1])
	if hi <= 0.0:
		lo = 0.0
		hi = _reach_of(me, foe) + 40.0
	var target := _seen(foe)
	var best := INF
	for c in sim.terrain.cells_touching(me.pos, 160.0, TerrainGrid.BRUSH):
		var p := sim.terrain.cell_center(c)
		var to_foe := p.distance_to(target)
		if to_foe < lo or to_foe > hi:
			continue
		var d := p.distance_squared_to(me.pos)
		if d < best:
			best = d
			_cover = p
	return _cover


## How far `o`'s light (with its lunge) reaches from its centre, to the edge of `me`.
static func _reach_of(o: CreatureSim, me: CreatureSim) -> float:
	var mv: Dictionary = o.moves().get("light_1", {})
	if mv.has("projectile"):
		return float(mv.get("reach", 14)) + float(mv.get("hit_radius", 10)) + me.radius + 4.0
	return o.move_range("light_1") + float(mv.get("lunge", 0.0)) * float(mv.get("startup", 0)) + me.radius + 4.0


## Whether a light thrown now would land: `foe` is in reach and can't walk out of it
## before the strike comes out (or is stuck: attacking, guarding, stunned, cornered).
func _lands(sim: MatchSim, me: CreatureSim, foe: CreatureSim, dist: float, reach: float) -> bool:
	var t0 := PerfLog.now()
	var out := _lands_now(sim, me, foe, dist, reach)
	PerfLog.since("ai lands", t0)
	return out


func _lands_now(sim: MatchSim, me: CreatureSim, foe: CreatureSim, dist: float, reach: float) -> bool:
	if dist > reach or foe.state == CreatureSim.State.GUARD or not _sees(foe):
		return false  # a guard is grabbed, not jabbed; a foe out of sight can't be aimed at
	if _blocked_streak >= 2 and foe.state != CreatureSim.State.ATTACK and not foe.is_stunned():
		return false  # it blocks on reaction: wait for it to swing, or break the guard
	var su := float(me.moves().get("light_1", {}).get("startup", 5)) + 1.0
	if foe.state == CreatureSim.State.ATTACK:
		# Committed: open if its move is spent, or if this light comes out first.
		if _recovery_left(foe) >= int(su) - 1:
			return true
		var mv := foe.move_def()
		var fta := _frames_to_active(foe)
		if mv.has("projectile") and foe.windup_left <= 0 and foe.state_t <= int(mv.get("startup", 0)):
			fta = int(mv.get("startup", 0)) + 1 - foe.state_t
		return fta > int(su) + 1
	if foe.is_stunned() or foe.root > 0:
		return true
	# A free foe with a quicker jab that reaches here wins the trade: let it swing and
	# punish that instead.
	var foe_su := int(foe.moves().get("light_1", {}).get("startup", 5)) + 1
	if foe_su < int(su) and dist <= _reach_of(foe, me):
		return false
	var escape := foe.walk_speed() * maxf(su - 2.0, 0.0) * 0.8
	var room := sim.floor_rect().grow(-foe.radius - 2.0)
	var out := (foe.pos - me.pos).normalized()
	escape = minf(escape, _clearance(room, foe.pos, out))  # backed against a wall: nowhere to go
	return dist + escape <= reach


## Ticks until `o`'s current strike comes out (0: it's out now), or -1 if it's spent or
## not a strike (a throw is answered when the projectile flies).
static func _frames_to_active(o: CreatureSim) -> int:
	if o.state != CreatureSim.State.ATTACK or o.charging:
		return -1
	var mv := o.move_def()
	if mv.has("projectile"):
		return -1
	var segs: Array = mv.get("_segs", [])
	if segs.is_empty():
		return -1
	var first := int(segs[0]["at"])
	var last := 0
	for sg in segs:
		last = maxi(last, int(sg["at"]) + int(sg["active"]))
	if o.windup_left > 0:
		return o.windup_left + first
	if o.state_t >= last:
		return -1
	return maxi(0, first - o.state_t)


## Ticks until `o` can act again if its move is spent (its strikes or throws are done),
## else -1: the window to punish.
static func _recovery_left(o: CreatureSim) -> int:
	if o.state != CreatureSim.State.ATTACK or o.charging or o.windup_left > 0:
		return -1
	var mv := o.move_def()
	var done := 0
	for sg in mv.get("_segs", []):
		done = maxi(done, int(sg["at"]) + int(sg["active"]))
	if mv.has("projectile"):
		var vol: Dictionary = mv["projectile"].get("volley", {})
		done = maxi(done, int(mv.get("startup", 0)) + 1 + int(vol.get("count", 1)) * maxi(1, int(vol.get("every", 1))))
	if mv.has("dash"):
		done = maxi(done, int(mv["dash"].get("to", 0)) + 1)
	if o.state_t < done:
		return -1
	return int(mv["length"]) + o.block_lag - o.state_t


## Rage's defense: the most urgent threat from any foe (a strike about to come out in
## reach, a projectile on a collision course, a lob landing here), answered by class:
## step out of reach when there's time, time a dodge so its invincible frames cover the
## hit, or guard.
func _rage_defend(sim: MatchSim, me: CreatureSim) -> bool:
	var t0 := PerfLog.now()
	var out := _rage_defend_now(sim, me)
	PerfLog.since("ai rage defend", t0)
	return out


func _rage_defend_now(sim: MatchSim, me: CreatureSim) -> bool:
	if _defense == "step":
		_defense_t -= 1
		if _defense_t > 0:
			_go(sim, me, _step_dir)
			return true
		_defense = ""
	elif _defense == "guard":
		_defense_t -= 1
		# A blocked swing is punished, not waited out: the moment its owner is recovering
		# for longer than this fighter's jab takes, drop the guard and hit back.
		if _defense_t > 0 and not _blocked_and_open(sim, me) and me.can_guard():
			_hold(SimDefs.IN_GUARD)
			return true
		_defense = ""

	var when := 999
	var kind := ""  ## "strike", "unblockable", "shot", "lob"
	var from := Vector2.ZERO
	var need := 0.0  ## how far to move to be clear
	var drain := 0.0  ## the stamina blocking that strike would cost
	for o in sim.creatures:
		if not me.is_foe(o) or o.state != CreatureSim.State.ATTACK or not _sees(o):
			continue  # (a foe out of sight can't be read: invisible, or behind a wall)
		var d := o.pos.distance_to(me.pos)
		if o.charging:
			if d < 64.0 and 8 < when:
				when = 8
				kind = "unblockable"
				from = o.pos
				need = 64.0 - d
			continue
		var t := _frames_to_active(o)
		var reach := _threat_range(o, me)
		if t < 0 or d > reach or t >= when:
			continue
		when = t
		from = o.pos
		need = reach - d + 2.0
		var mv := o.move_def()
		drain = _strike_drain(me, o)
		kind = "unblockable" if _breaks_guard(mv) and (not _breaks_guard_held_only(mv) or o.charge_ratio >= 1.0) \
			or (String(mv.get("type", "")) == "surge" and mv.has("terrain_ring")) else "strike"
	for pr in sim.projectiles:
		var owner_id := int(pr["owner"])
		if owner_id < 0 or owner_id >= sim.creatures.size() or not me.is_foe(sim.creatures[owner_id]):
			continue
		var pp: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		if bool(pr.get("lob", false)):
			var land := pp + vel * float(pr["life"])
			var r := float(pr.get("burst", 0)) + me.radius + 3.0
			var dl := land.distance_to(me.pos)
			if dl < r and int(pr["life"]) < when:
				when = int(pr["life"])
				kind = "lob"
				from = land
				need = r - dl
			continue
		var v2 := vel.length_squared()
		if v2 < 0.0001:
			continue
		# A chip shot that doesn't stagger (a knife flick) isn't worth a step to an
		# assassin closing on a kiter: fast enough to take the 3 damage and keep coming,
		# unless nearly beaten. Slower classes respect it (and lose ground), as designed.
		var ph: Dictionary = pr.get("hit", {})
		if bool(ph.get("no_flinch", false)) and float(ph.get("damage", 0.0)) <= 4.0 \
				and String(_style(me)["plan"]) == "lurk" and me.hp / me.max_hp > 0.3:
			continue
		var rel := me.pos - pp
		var t_ca := rel.dot(vel) / v2
		if t_ca < 0.0 or t_ca > 40.0:
			continue
		var miss := (pp + vel * t_ca).distance_to(me.pos)
		var r2 := float(pr.get("radius", 0)) + me.radius + 3.0
		if miss < r2 and int(t_ca) < when:
			when = int(t_ca)
			kind = "shot"
			from = pp + vel * t_ca
			need = r2 - miss
	if kind == "":
		return false

	var style := String(_style(me)["defense"])
	var speed := me.walk_speed() * 0.85
	var room_ticks := float(when) - 1.0
	match kind:
		"lob":
			_step(sim, me, me.pos - from, int(need / maxf(speed, 0.5)) + 3)
			return true
		"shot":
			# Sideways out of its path; dodge through it if there's no time.
			var path: Vector2 = (me.pos - from)
			if path.length_squared() < 0.01:
				path = Vector2(-me.facing.y, me.facing.x)
			if speed * room_ticks >= need:
				_step(sim, me, path, int(need / maxf(speed, 0.5)) + 2)
				return true
			if when <= 5 and me.can_dodge():
				_dodge_dir(me, path)
				return true
			if when <= 4 and me.can_guard():
				_guard_for(when + 6)
			return true
		"unblockable":
			if speed * room_ticks >= need:
				_step(sim, me, me.pos - from, int(need / maxf(speed, 0.5)) + 3)
				return true
			var ivs := int(me.def["dodge"].get("iframes_start", 2))
			if when <= ivs + 2 and me.can_dodge():
				_dodge_dir(me, _open_dir(sim, me, me.pos - from, _roll_distance(me)))
			return true
		_:  # a strike
			# Blocking it would empty the stamina (the guard drops and it lands clean):
			# even a tank gets out of the way instead.
			var guard_ok := _guard_holds(me, drain)
			if (style != "guard" or not guard_ok) and speed * room_ticks >= need:
				_step(sim, me, _open_dir(sim, me, me.pos - from), int(need / maxf(speed, 0.5)) + 3)
				return true
			# A counter answers it when there's one ready: a tank's armored stance
			# (Bedrock), a fighter's parry (Slip Counter) timed to catch the strike.
			var counter := String(_ai(me).get("counter", ""))
			if style != "evade" and counter != "" and _usable(me, counter):
				var cw: Dictionary = me.moves()[counter].get("counter", {})
				var arm: Dictionary = me.moves()[counter].get("armor", {})
				var lo := int(cw.get("from", arm.get("from", 2)))
				var hi := int(cw.get("to", arm.get("to", 30)))
				if when >= lo and when <= hi:
					_press(int(ACTION_BIT[counter]))
					return true
			if not guard_ok:
				var ivs := int(me.def["dodge"].get("iframes_start", 2))
				if when <= ivs + 2 and me.can_dodge():
					# Too wide to out-roll: the i-frames save us, not the distance, so go across.
					var away := me.pos - from
					if need > DODGE_DISTANCE and away.length_squared() > 0.0001:
						away = Vector2(-away.y, away.x)
					_dodge_dir(me, _open_dir(sim, me, away, _roll_distance(me)))
				else:
					_go(sim, me, _open_dir(sim, me, me.pos - from))
				return true
			_guard_for(when + 8)
			return true
	return false


## Some foe in jab reach is recovering from a move for at least as long as this
## fighter's jab takes to come out (and nobody else is about to strike).
func _blocked_and_open(sim: MatchSim, me: CreatureSim) -> bool:
	var su := int(me.moves().get("light_1", {}).get("startup", 5)) + 1
	if _blocked_streak >= 2:
		return false  # the last punishes were blocked: hold the guard, it'll swing again
	var open := false
	for o in sim.creatures:
		if not me.is_foe(o) or o.state == CreatureSim.State.KO or not _sees(o):
			continue
		var d := o.pos.distance_to(me.pos)
		var t := _frames_to_active(o)
		if t >= 0 and t <= su + 2 and d < _threat_range(o, me):
			return false  # another strike is coming first
		if _recovery_left(o) >= su and d <= _reach_of(me, o) - 2.0:
			open = true
	return open


func _step(sim: MatchSim, me: CreatureSim, dir: Vector2, ticks: int) -> void:
	_defense = "step"
	_step_dir = dir
	_defense_t = clampi(ticks, 2, 24)
	_go(sim, me, dir)


func _guard_for(ticks: int) -> void:
	_defense = "guard"
	_defense_t = clampi(ticks, 4, 30)
	_hold(SimDefs.IN_GUARD)


func _dodge_dir(me: CreatureSim, dir: Vector2) -> void:
	if not me.can_dodge():
		if me.can_guard():
			_guard_for(10)
		else:
			_hold(SimDefs.move_bits(dir))  # exhausted: no guard either, so just go
		return
	_hold(SimDefs.move_bits(dir))
	_press(SimDefs.IN_DODGE)


## Punish: a foe whose move is spent is open until it recovers. Hit it if a light gets
## there in time, a poke if that does, or close in if the window is long enough.
func _rage_punish(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float) -> bool:
	var t0 := PerfLog.now()
	var out := _rage_punish_now(sim, me, foe, to_foe, dist)
	PerfLog.since("ai rage punish", t0)
	return out


func _rage_punish_now(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float) -> bool:
	var left := _recovery_left(foe)
	if left < 0 or foe.is_invulnerable():
		return false
	# A whiff in reach of the setup move (Tenderize) is the safest time to set it up.
	if _plan_setup(me, foe, to_foe, dist, left):
		return true
	var light: Dictionary = me.moves().get("light_1", {})
	var su := int(light.get("startup", 4)) + 1
	var reach := _reach_of(me, foe) - 4.0
	if light.has("projectile"):
		reach = me.move_range("light_1") * 0.9
	if dist <= reach and left >= su:
		_hold(SimDefs.move_bits(to_foe))
		_press(SimDefs.IN_LIGHT)
		return true
	var ai := _ai(me)
	var poke := String(ai.get("poke", ""))
	var pr: Array = ai.get("poke_range", [0, 0])
	if poke != "" and _usable(me, poke) and dist >= float(pr[0]) and dist <= float(pr[1]) \
			and left >= int(me.moves()[poke].get("startup", 6)) + 1:
		_press(int(ACTION_BIT[poke]))
		return true
	if String(_style(me)["plan"]) != "kite" and float(left) * me.walk_speed() + reach >= dist + 4.0:
		_go_to(sim, me, me.pos + to_foe)
		return true
	return false


## While attacking: a mage keeps walking its kite line through its mobile throws.
func _rage_attack_move(sim: MatchSim, me: CreatureSim, foe: CreatureSim) -> void:
	if float(me.move_def().get("mobile", 0.0)) <= 0.0:
		return
	var v := _kite_vector(sim, me, foe)
	var d := _steer(sim, me, v)
	if d != Vector2.ZERO:
		_hold(SimDefs.move_bits(d))


## Holds a direction to walk while facing (aiming at) the foe: twin-stick strafing.
func _strafe(sim: MatchSim, me: CreatureSim, foe: CreatureSim, v: Vector2) -> void:
	var d := _steer(sim, me, v)
	if d != Vector2.ZERO:
		_hold(SimDefs.move_bits(d))
	_out |= SimDefs.IN_STRAFE | SimDefs.aim_bits(_aim_point(me, foe) - me.pos)


func _rage_neutral(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float) -> void:
	var t0 := PerfLog.now()
	_rage_neutral_now(sim, me, foe, to_foe, dist)
	PerfLog.since("ai rage neutral", t0)


func _rage_neutral_now(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float) -> void:
	_route = []
	_route_drop = false
	var ai := _ai(me)
	if _maybe_fold(me, foe, dist):
		return
	var plan := String(_style(me)["plan"])
	var reach := _reach_of(me, foe) - 4.0  # where its light lands
	var danger := _reach_of(foe, me)  # where the foe's lands

	# The foe is down or protected: wait where it'll get up (a mage keeps its distance),
	# or charge a slam to meet it.
	if foe.state in [CreatureSim.State.KNOCKDOWN, CreatureSim.State.FALLING] or foe.invuln > 0 or foe.is_airborne():
		if bool(ai.get("wakeup_charge", false)) and dist < 46.0 and _usable(me, "heavy") \
				and foe.state == CreatureSim.State.KNOCKDOWN and _roll(0.3):
			# Held so the slam lands as the foe stands: its windup and startup come first.
			var hv: Dictionary = me.moves()["heavy"]
			_hold_heavy = clampi(foe.stun - int(hv.get("windup", 0)) - int(hv.get("startup", 0)) - 2, 0, 45)
			_press(SimDefs.IN_HEAVY)
			_hold(SimDefs.move_bits(to_foe))
			return
		# A foe on the floor is where to leave a puddle (Syrup Slick): it wakes up slowed.
		var zone := String(ai.get("zone", ""))
		var zr: Array = ai.get("zone_range", [0, 0])
		if zone != "" and _usable(me, zone) and foe.state == CreatureSim.State.KNOCKDOWN and dist <= float(zr[1]) \
				and foe.stun > int(me.moves()[zone].get("length", 24)):
			_press(int(ACTION_BIT[zone]))
			return
		if plan == "kite":
			_strafe(sim, me, foe, _kite_vector(sim, me, foe))
		elif dist > reach - 2.0:
			_go_to(sim, me, me.pos + to_foe)
		return

	# No straight way to the foe (a wall, a fence or a pit between): walk the way round
	# first. The plans below circle and press as if it were in plain sight.
	if dist > reach + 8.0 and not NavGrid.clear_line(sim.terrain, me.pos, _seen(foe), me.radius, false):
		_go_to(sim, me, _seen(foe))
		return

	# A stunned or crumpled foe: hit it.
	if foe.is_stunned() and dist < reach + 4.0:
		_hold(SimDefs.move_bits(to_foe))
		_press(SimDefs.IN_LIGHT)
		return

	# A guarding foe in reach (or one that blocks everything): grab it, or break the guard.
	var grab := _guard_answer(me, dist)
	var telegraphed := grab != "" and int(me.moves()[me.action_move(grab)].get("windup", 0)) > 0
	# A wound-up guard-breaker is only for a foe that is guarding now (or can't dodge);
	# thrown at a free foe it's a gift to dodge and punish.
	if grab != "" and (foe.state == CreatureSim.State.GUARD or (_blocked_streak >= 2
			and foe.state != CreatureSim.State.ATTACK
			and (not telegraphed or not foe.can_dodge() or _blocked_streak >= 4))) \
			and _usable(me, grab):
		_hold(SimDefs.move_bits(to_foe))
		_press(int(ACTION_BIT[grab]))
		_guard_press = true
		return

	# A guard low on stamina: wear it down (heavies drain the most); the blocked hit that
	# empties it lands clean.
	if foe.state == CreatureSim.State.GUARD and dist <= reach and _guard_wearing(foe) and _sees(foe):
		_hold(SimDefs.move_bits(to_foe))
		_press(SimDefs.IN_HEAVY if _usable(me, "heavy") else SimDefs.IN_LIGHT)
		return

	if _plan_setup(me, foe, to_foe, dist):
		return

	if _rage_kit(sim, me, foe, to_foe, dist, plan):
		return

	# A foe that fights from range (a kiting mage) is run down, not waited for. An assassin
	# whose burst (Burrow, Tiptoe) is cooling lurks in brush instead when the arena has some
	# in reach, rather than walk through the knives, and comes out of it when the burst is up.
	if plan != "kite" and _is_ranged(foe) and dist > reach:
		if plan == "lurk" and not _burst_ready(me):
			var cover := _cover_spot(sim, me, foe)
			if cover != Vector2.INF:
				if not (me.covered and me.pos.distance_to(cover) < 10.0):
					_go_to(sim, me, cover)
				return
		_chase(sim, me, foe, to_foe, dist, reach)
		return

	_give = _give_ground(me, foe, to_foe) if scored and plan == "kite" else 0.0
	match plan:
		"kite":
			_plan_kite(sim, me, foe, to_foe, dist, danger)
		"lurk":
			_plan_lurk(sim, me, foe, to_foe, dist, reach, danger)
		"press":
			_plan_press(sim, me, foe, to_foe, dist, reach)
		"skirmish":
			_plan_skirmish(sim, me, foe, to_foe, dist, reach, danger)
		_:
			_plan_footsie(sim, me, foe, to_foe, dist, reach, danger)


## A setup move (ai "setup" {move, range, mark, chance}): thrown at a foe whose body is
## within `range` px of its own that doesn't carry `mark` yet (CreatureSim.has_mark: the
## pink of a tenderized foe is on screen), so the string after it pays off (Chef
## Cerebro's Tenderize, then a Mallet Toss that staggers). As a punish (`left`: the foe's
## recovery ticks) only when it lands before the foe recovers, windup included; in
## neutral not into a swing, a dodge or a guard, and only `chance` of the ticks it could.
func _plan_setup(me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, left := -1) -> bool:
	var su: Dictionary = _ai(me).get("setup", {})
	if su.is_empty():
		return false
	var act := String(su.get("move", ""))
	if not ACTION_BIT.has(act) or not _usable(me, me.action_move(act)):
		return false
	if foe.has_mark(String(su.get("mark", ""))) or _foe_hidden:
		return false
	if dist - me.radius - foe.radius > float(su.get("range", 16.0)):
		return false
	if left >= 0:
		var mv: Dictionary = me.moves()[me.action_move(act)]
		if left < int(mv.get("windup", 0)) + int(mv.get("startup", 0)) + 1:
			return false
	elif foe.state in [CreatureSim.State.ATTACK, CreatureSim.State.DODGE, CreatureSim.State.GUARD] \
			or not _roll(float(su.get("chance", 1.0))):
		return false
	_hold(SimDefs.move_bits(to_foe))
	_press(int(ACTION_BIT[act]))
	return true


## The rest of the kit, used when it's sure to pay off: a Surge that can't miss, a lob
## landing where the foe will be, a gaze on a foe looking this way, a puddle under a
## foe up close, a long poke on a foe walking into it.
func _rage_kit(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, plan: String) -> bool:
	_kit_t -= 1
	if _kit_t > 0:
		return false
	_kit_t = 4
	if scored:
		var t0 := PerfLog.now()
		var fired := _rage_kit_scored(sim, me, foe, to_foe, dist, plan)
		PerfLog.since("ai score", t0)
		return fired
	var ai := _ai(me)
	var busy := _recovery_left(foe) >= 6 or foe.is_stunned() or foe.state == CreatureSim.State.GUARD
	# Surges: an area one with the foe close and stuck, a line one with the foe in range.
	var surge_range := _surge_range(me, ai)
	if surge_range > 0.0 and _usable(me, "surge") and dist < surge_range * (1.0 if busy else 0.65) \
			and not (me.moves()["surge"].has("armor") and _foe_grab_ready(foe)):
		_press(SimDefs.IN_SURGE)
		return true
	var surge_line := float(ai.get("surge_line", 0))
	if surge_line > 0.0 and _usable(me, "surge") and dist < surge_line * 0.85 and (busy or dist < surge_line * 0.5):
		_press(SimDefs.IN_SURGE)
		return true
	# A lob, charged to land where the foe will be.
	var lob := String(ai.get("lob", ""))
	var lr: Array = ai.get("lob_range", [0, 0])
	if lob != "" and _usable(me, lob) and dist >= float(lr[0]) and dist <= float(lr[1]) and _roll(0.35):
		_fire_lob(me, foe, lob)
		return true
	# A gaze, when the foe is looking this way.
	var gaze := String(ai.get("gaze", ""))
	var gzr: Array = ai.get("gaze_range", [0, 0])
	if gaze != "" and _usable(me, gaze) and dist >= float(gzr[0]) and dist <= float(gzr[1]) \
			and foe.facing.dot(-to_foe.normalized()) > 0.5 and _roll(0.5):
		_press(int(ACTION_BIT[gaze]))
		return true
	# A puddle under a foe in close, when it can't punish the drop (it's busy or down), or
	# round its feet as a foe walks in (Syrup Slick: it has to wade through to reach him),
	# unless a strike of theirs lands before the puddle is down.
	var zone := String(ai.get("zone", ""))
	var zr: Array = ai.get("zone_range", [0, 0])
	var zlen := int(me.moves().get(zone, {}).get("length", 24)) if zone != "" else 0
	var zsu := int(me.moves().get(zone, {}).get("startup", 8)) if zone != "" else 0
	var closing := foe.walk_vel.dot(-to_foe.normalized()) > 0.5 and dist <= float(zr[1]) * 0.75
	var fta := _frames_to_active(foe)
	var striking := fta >= 0 and fta <= zsu + 2
	if zone != "" and _usable(me, zone) and dist >= float(zr[0]) and dist <= float(zr[1]) \
			and (_recovery_left(foe) >= zlen or foe.is_stunned() or foe.state == CreatureSim.State.GUARD
			or foe.stun > zlen or (closing and not striking)):
		_press(int(ACTION_BIT[zone]))
		return true
	# A long poke (a thrown or dashing skill), not for a mage's plan or an assassin's
	# opener, which choose their own moment.
	if plan in ["press", "footsie", "skirmish"]:
		var poke := String(ai.get("poke", ""))
		var pr: Array = ai.get("poke_range", [0, 0])
		if poke != "" and _usable(me, poke) and dist >= float(pr[0]) and dist <= float(pr[1]) \
				and (busy or (plan != "press" and (foe.walk_vel.dot(-to_foe) > 0.5 or _roll(0.2)))):
			_press(int(ACTION_BIT[poke]))
			return true
	return false


## A lob, charged to land where the foe will be.
func _fire_lob(me: CreatureSim, foe: CreatureSim, lob: String) -> void:
	var target := _aim_point(me, foe)
	var lmv: Dictionary = me.moves().get(lob, {})
	var lp: Dictionary = lmv.get("projectile", {})
	_out |= SimDefs.aim_bits(target - me.pos)
	_press(int(ACTION_BIT[lob]))
	if lmv.has("charge_max") and lp.has("range_charged"):
		var far := target.distance_to(me.pos) - float(lp.get("offset", 16))
		var k := clampf((far - float(lp["range"])) / maxf(1.0, float(lp["range_charged"]) - float(lp["range"])), 0.0, 1.0)
		_hold_heavy = int(round(k * float(lmv["charge_max"])))
		_hold_bit = int(ACTION_BIT[lob])


# --- Scored kit (piece 2 of docs/plans/ai-utility-and-teamplay.md) ---------------------
# The ladder above fires the first kit piece whose rule passes, with fixed rolls. The scored
# kit looks at every piece that could fire, scores each (its weight times its considerations,
# each 0-1) and fires the best one above SCORE_MIN. Weights are data: WEIGHTS, then the
# style's "weights", then the creature's ai.weights.

const SCORE_MIN := 0.3
const WEIGHTS := {"surge": 1.0, "lob": 0.8, "gaze": 0.8, "zone": 0.9, "poke": 0.7, "give_ground": 1.0}
## How far a kiter giving ground keeps the near edge of its band out.
const GIVE_PX := 24.0
## The class triangle: assassin > mage > fighter/tank (and bruiser, skirmisher) > assassin.
const BEATS := {"assassin": ["mage"], "mage": ["fighter", "tank", "bruiser", "skirmisher"],
	"fighter": ["assassin"], "tank": ["assassin"], "bruiser": ["assassin"], "skirmisher": ["assassin"]}


## 1 inside [lo, hi], falling to 0 over `fall` px either side.
static func f_band(dist: float, lo: float, hi: float, fall: float) -> float:
	if dist < lo:
		return clampf(1.0 - (lo - dist) / maxf(1.0, fall), 0.0, 1.0)
	if dist > hi:
		return clampf(1.0 - (dist - hi) / maxf(1.0, fall), 0.0, 1.0)
	return 1.0


## How squarely `foe` walks at `me` (0 standing or walking away, 1 straight in).
static func f_closing(foe: CreatureSim, to_foe: Vector2) -> float:
	if foe.walk_vel.length_squared() < 0.0001 or to_foe.length_squared() < 0.0001:
		return 0.0
	return clampf(foe.walk_vel.normalized().dot(-to_foe.normalized()), 0.0, 1.0)


## How squarely `foe` faces `me`, with a dead zone: 0 at 0.3 or less, 1 at 0.8 and up.
static func f_facing(foe: CreatureSim, to_foe: Vector2) -> float:
	if to_foe.length_squared() < 0.0001:
		return 0.0
	return clampf((foe.facing.dot(-to_foe.normalized()) - 0.3) / 0.5, 0.0, 1.0)


## 1 when the foe can't answer for a while (stunned, guarding, or more than `need` frames
## of stun or recovery left), else its share of `need`.
static func f_busy(foe: CreatureSim, need: int) -> float:
	if foe.is_stunned() or foe.state == CreatureSim.State.GUARD or foe.stun > need:
		return 1.0
	return clampf(float(_recovery_left(foe)) / maxf(1.0, float(need)), 0.0, 1.0)


## Safe to start a move with `startup` frames: 1 when the foe isn't striking (or its strike
## is already out), falling to 0 as its active frames come before ours would.
static func f_safe(foe: CreatureSim, startup: int) -> float:
	var fta := _frames_to_active(foe)
	if fta < 0:
		return 1.0
	return clampf(float(fta - startup) / 10.0, 0.0, 1.0)


## The class triangle from `me`'s side: 1 when its class beats the foe's, 0 when it loses,
## 0.5 even.
static func f_matchup(me: CreatureSim, foe: CreatureSim) -> float:
	var a := String(me.def.get("role", ""))
	var b := String(foe.def.get("role", ""))
	if b in BEATS.get(a, []):
		return 1.0
	if a in BEATS.get(b, []):
		return 0.0
	return 0.5


## 0.5 even on health, toward 1 when `me` is ahead, 0 behind.
static func f_hp_edge(me: CreatureSim, foe: CreatureSim) -> float:
	return clampf(0.5 + 0.5 * (me.hp / me.max_hp - foe.hp / foe.max_hp), 0.0, 1.0)


## A product of `n` considerations, made up so that having more of them doesn't sink a
## score by count alone (the usual utility-AI compensation: s + (1 - s) * (1 - 1/n) * s).
static func compensate(s: float, n: int) -> float:
	if n <= 1:
		return s
	return s + (1.0 - s) * (1.0 - 1.0 / float(n)) * s


func _weights(me: CreatureSim) -> Dictionary:
	var w: Dictionary = WEIGHTS.duplicate()
	w.merge(_style(me).get("weights", {}), true)
	w.merge(_ai(me).get("weights", {}), true)
	return w


## Every kit piece that could fire now, with its score: [[name, score], ...] in a fixed
## order (a tie goes to the earlier). The gates (ranges, cooldowns) are the ladder's; what
## the ladder rolled for is a consideration here, and a small jitter from the controller's
## own rng keeps a little of the old unpredictability (one seed still replays the same).
func _score_candidates(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, plan: String) -> Array:
	var ai := _ai(me)
	var w := _weights(me)
	var out: Array = []
	var closing := f_closing(foe, to_foe)
	# Surge: the ladder's rule (an area one with the foe close, and stuck unless very close;
	# a line one with the foe in range), scored 1 so it comes first as it did there: a Surge
	# thrown on a free foe is a long cooldown wasted.
	var busy := _recovery_left(foe) >= 6 or foe.is_stunned() or foe.state == CreatureSim.State.GUARD
	if _usable(me, "surge"):
		var sr := _surge_range(me, ai)
		var sl := float(ai.get("surge_line", 0))
		if (sr > 0.0 and dist < sr * (1.0 if busy else 0.65)
				and not (me.moves()["surge"].has("armor") and _foe_grab_ready(foe))) \
				or (sl > 0.0 and dist < sl * 0.85 and (busy or dist < sl * 0.5)):
			out.append(["surge", float(w["surge"])])
	var lob := String(ai.get("lob", ""))
	var lr: Array = ai.get("lob_range", [0, 0])
	if lob != "" and _usable(me, lob) and dist >= float(lr[0]) and dist <= float(lr[1]):
		out.append(["lob", maxf(0.6, f_busy(foe, 6)) * float(w["lob"]) * _jitter()])
	var gaze := String(ai.get("gaze", ""))
	var gzr: Array = ai.get("gaze_range", [0, 0])
	if gaze != "" and _usable(me, gaze) and dist >= float(gzr[0]) and dist <= float(gzr[1]):
		out.append(["gaze", f_facing(foe, to_foe) * float(w["gaze"]) * _jitter()])
	var zone := String(ai.get("zone", ""))
	var zr: Array = ai.get("zone_range", [0, 0])
	if zone != "" and _usable(me, zone) and dist >= float(zr[0]) and dist <= float(zr[1]):
		var zlen := int(me.moves()[zone].get("length", 24))
		var fta := _frames_to_active(foe)
		var striking := fta >= 0 and fta <= int(me.moves()[zone].get("startup", 8)) + 2
		var walk_in := 0.0 if striking or dist > float(zr[1]) * 0.75 else closing
		out.append(["zone", maxf(f_busy(foe, zlen), walk_in) * float(w["zone"])])
	# A long poke: on a stuck foe, or one walking into it (a mage's knives on a diver). An
	# assassin's opener chooses its own moment (_plan_lurk).
	var poke := String(ai.get("poke", ""))
	var pr: Array = ai.get("poke_range", [0, 0])
	if poke != "" and plan != "lurk" and _usable(me, poke) and dist >= float(pr[0]) and dist <= float(pr[1]):
		var into := 0.0 if plan == "press" else closing
		# Footsies and skirmishes poke in neutral too, on the ladder's 20% roll.
		var free := 1.0 if plan in ["footsie", "skirmish"] and _roll(0.2) else 0.0
		var safe := f_safe(foe, int(me.moves()[poke].get("startup", 8)))
		out.append(["poke", maxf(maxf(f_busy(foe, 6), into), free) * safe * float(w["poke"]) * _jitter()])
	return out


## Movement for a kiter: hold its band ("kite") or give ground ("give_ground": the band's
## near edge GIVE_PX further out) when a foe walks in that wins the class matchup, the more
## when behind on health. Returns the px to add to the near edge.
func _give_ground(me: CreatureSim, foe: CreatureSim, to_foe: Vector2) -> float:
	var w := _weights(me)
	var s := f_closing(foe, to_foe) * lerpf(1.0, 0.4, f_matchup(me, foe)) * lerpf(1.2, 0.8, f_hp_edge(me, foe))
	return GIVE_PX if minf(1.0, s) * float(w["give_ground"]) > SCORE_MIN else 0.0


func _jitter() -> float:
	return 0.9 + 0.2 * rng.randf()


## The scored kit: the best candidate above SCORE_MIN fires, or nothing does.
func _rage_kit_scored(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, plan: String) -> bool:
	var best := ""
	var top := SCORE_MIN
	for c in _score_candidates(sim, me, foe, to_foe, dist, plan):
		if float(c[1]) > top:
			top = float(c[1])
			best = String(c[0])
	if best == "":
		return false
	var ai := _ai(me)
	match best:
		"surge":
			_press(SimDefs.IN_SURGE)
		"lob":
			_fire_lob(me, foe, String(ai["lob"]))
		_:
			_press(int(ACTION_BIT[String(ai[best])]))
	return true


## The move that beats a guard from `dist` away, if one is ready: a grab (beats armor
## too) or a guard-breaker, the cheapest first (a Surge last).
func _guard_answer(me: CreatureSim, dist: float) -> String:
	var best := ""
	var best_rank := 99
	for act in ["heavy", "skill_1", "skill_2", "surge"]:
		var mid := me.action_move(act)
		var mv: Dictionary = me.moves().get(mid, {})
		if mv.is_empty() or not _breaks_guard(mv):
			continue
		if not _usable(me, mid) or mv.has("counter"):
			continue
		var rng_px := me.move_range(mid)
		var dash: Dictionary = mv.get("dash", {})
		if not dash.is_empty():
			rng_px += float(dash.get("speed", 0.0)) * float(int(dash.get("to", 0)) - int(dash.get("from", 0)))
		if dist > rng_px + 4.0:
			continue
		var rank := me.move_rank(mid)
		if rank < best_rank:
			best_rank = rank
			best = act
	return best


## Whether `me` can block a hit that drains `drain` and keep its guard: blocking into
## empty stamina drops the guard and the hit lands clean.
static func _guard_holds(me: CreatureSim, drain: float) -> bool:
	return me.can_guard() and me.stamina - drain > 0.0


## The stamina blocking `o`'s current strike would cost `me` (0 when it isn't striking).
static func _strike_drain(me: CreatureSim, o: CreatureSim) -> float:
	if o.state != CreatureSim.State.ATTACK:
		return 0.0
	var mv := o.move_def()
	return MatchSim.block_drain(me, String(mv.get("type", "")), float(mv.get("damage", 0.0)))


## A guarding foe whose stamina is low enough to wear down with blocked hits.
static func _guard_wearing(foe: CreatureSim) -> bool:
	return foe.state == CreatureSim.State.GUARD and foe.stamina <= foe.max_stamina * PRESSURE_GUARD_SHARE


## A grab or a guard-breaker, including one that only breaks guard held to a full charge.
static func _breaks_guard(mv: Dictionary) -> bool:
	return bool(mv.get("grab", false)) or bool(mv.get("guard_break", false)) \
		or bool(mv.get("hold", {}).get("guard_break", false))


## A move that breaks guard only at a full charge ("hold": {"guard_break": true}, Sack
## Smack): the CPU has to hold it all the way to the top.
static func _breaks_guard_held_only(mv: Dictionary) -> bool:
	return bool(mv.get("hold", {}).get("guard_break", false)) and not bool(mv.get("guard_break", false)) \
		and not bool(mv.get("grab", false))


func _is_ranged(o: CreatureSim) -> bool:
	return o.moves().get("light_1", {}).has("projectile") or bool(o.def.get("ai", {}).get("kite", false))


## Running down a kiter: head for where it's going (and a little toward the middle, so
## it backs into a wall), weave so its shots miss, throw every gap closer as soon as it
## reaches, and roll forward through the shots when there's stamina to spare.
func _chase(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, reach: float) -> void:
	var ai := _ai(me)
	for key in ["burrow", "stealth", "poke"]:
		var mid := String(ai.get(key, ""))
		var rg: Array = ai.get(key + "_range", [0, 0])
		if mid != "" and _usable(me, mid) and dist >= float(rg[0]) * 0.7 and dist <= float(rg[1]) \
				and not (key == "stealth" and me.stealth > 0):
			_press(int(ACTION_BIT[mid]))
			return
	var dg: Dictionary = me.def["dodge"]
	var roll := float(dg.get("speed", 0.0)) * float(dg.get("frames", 0))
	if me.can_dodge() and me.stamina > me.max_stamina * 0.55 and roll > 20.0 \
			and dist > reach + roll * 0.5 and dist < reach + roll * 1.6 and _roll(0.2):
		_dodge_dir(me, to_foe)
		return
	var lead := foe.walk_vel * clampf(dist / maxf(me.walk_speed(), 0.5), 0.0, 40.0) * 0.6
	var mid_floor := sim.floor_rect().get_center()
	var goal := _seen(foe) + lead + (mid_floor - _seen(foe)).normalized() * 16.0
	var n := (goal - me.pos).normalized()
	_dance_t -= 1
	if _dance_t <= 0:
		_dance_t = rng.randi_range(12, 22)
		_orbit = -_orbit
	# Invisible (Tiptoe): the foe throws along the line it last saw this fighter on, so
	# come in from well off that line, and keep to one side rather than weaving back
	# across it.
	if me.stealth > 0:
		var side := Vector2(-n.y, n.x) * (1.0 if _orbit_t % 2 == 0 else -1.0)
		_go_to(sim, me, goal, side * 0.6 / 0.6 * 0.6 + n * -0.4)
		return
	_go_to(sim, me, goal, Vector2(-n.y, n.x) * _orbit * 0.45)


## Where a mage walks: out to the edge of its range when the foe closes in, round it at
## that range, in when it's out of range; always toward open floor.
func _kite_vector(sim: MatchSim, me: CreatureSim, foe: CreatureSim) -> Vector2:
	var to_foe := _seen(foe) - me.pos
	var dist := to_foe.length()
	var band := kite_band(me, foe)
	var hi := band.y
	var lo := minf(band.x + _give, hi - 8.0)
	if dist < lo:
		return _open_dir(sim, me, -to_foe) + _orbit_dir(sim, me, foe, hi) * 0.25
	if dist > hi:
		return to_foe.normalized() + _orbit_dir(sim, me, foe, hi) * 0.5
	return _orbit_dir(sim, me, foe, (lo + hi) * 0.5)


## The centre-to-centre distances a kiter holds `foe` between (x = near, y = far): inside
## 80% of its light's range, and well outside the foe's light.
static func kite_band(me: CreatureSim, foe: CreatureSim) -> Vector2:
	var hi := me.move_range("light_1") * 0.8
	return Vector2(clampf(_reach_of(foe, me) + 48.0, 56.0, hi - 20.0), hi)


## Mage: keep the foe at the edge of its range, strafing (facing it) and throwing all
## the while; a foe in its face gets flipped away (the grab) or left behind (a dodge).
func _plan_kite(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, danger: float) -> void:
	var ai := _ai(me)
	if dist < danger + 8.0:
		var grab := String(ai.get("grab", ""))
		if grab != "" and _usable(me, grab) and foe.state != CreatureSim.State.ATTACK \
				and dist < float(ai.get("grab_range", 30)) + me.radius + foe.radius:
			_press(int(ACTION_BIT[grab]))
			return
		if me.can_dodge() and _roll(0.5):
			_dodge_dir(me, _open_dir(sim, me, -to_foe, _roll_distance(me)))
			return
	_strafe(sim, me, foe, _kite_vector(sim, me, foe))
	var max_r := me.move_range("light_1")
	if dist > max_r * 0.97:
		return
	var poke := String(ai.get("poke", ""))
	var pr: Array = ai.get("poke_range", [0, 0])
	if poke != "" and _usable(me, poke) and dist >= float(pr[0]) and dist <= float(pr[1]) and _roll(0.08):
		_press(int(ACTION_BIT[poke]))
		return
	_press(SimDefs.IN_LIGHT)


## Assassin: hover just out of reach, then burst in (a tunnel, going invisible, a dash
## poke) for a full combo when the foe is weak, stuck or out of tools, and get out.
func _plan_lurk(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, reach: float, danger: float) -> void:
	var ai := _ai(me)
	if _engage_t > 0:
		_engage_t -= 1
	elif foe.hp / foe.max_hp < 0.35 or not foe.can_dodge() or me.energy >= CreatureSim.MAX_ENERGY \
			or (foe.state == CreatureSim.State.MOVE and _roll(0.03)):
		_engage_t = 80
	if _engage_t <= 0:
		# Cover first: on an arena with brush, slip into a patch within burst range of the foe
		# and wait there out of sight, so the engage (Burrow, Tiptoe, a dash) comes from
		# where it can't be seen coming. Without brush in reach, circle out of range.
		var cover := _cover_spot(sim, me, foe)
		if cover != Vector2.INF:
			if me.covered and me.pos.distance_to(cover) < 10.0:
				if _roll(0.06):
					_engage_t = 80  # strike from cover
				return  # hold still in the leaves
			_go_to(sim, me, cover)
			return
		_go(sim, me, _orbit_dir(sim, me, foe, danger + 22.0))
		return
	var burrow := String(ai.get("burrow", ""))
	var br: Array = ai.get("burrow_range", [0, 0])
	if burrow != "" and _usable(me, burrow) and dist >= float(br[0]) * 0.6 and dist <= float(br[1]):
		_press(int(ACTION_BIT[burrow]))
		return
	var sneak := String(ai.get("stealth", ""))
	var sr: Array = ai.get("stealth_range", [0, 0])
	if sneak != "" and _usable(me, sneak) and me.stealth <= 0 and dist >= float(sr[0]) * 0.6 and dist <= float(sr[1]):
		_press(int(ACTION_BIT[sneak]))
		return
	var poke := String(ai.get("poke", ""))
	var pr: Array = ai.get("poke_range", [0, 0])
	if poke != "" and _usable(me, poke) and dist >= float(pr[0]) and dist <= float(pr[1]):
		_press(int(ACTION_BIT[poke]))
		return
	if _lands(sim, me, foe, dist, reach):
		_hold(SimDefs.move_bits(to_foe))
		_press(SimDefs.IN_LIGHT)
		_engage_t = mini(_engage_t, 20)  # in and out: after this string, back to lurking
		return
	_go_to(sim, me, me.pos + to_foe)


## Tank and bruiser: walk the foe down, cutting off the way to open floor so it ends up
## against a wall, and swing whenever it's in reach.
func _plan_press(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, reach: float) -> void:
	var ai := _ai(me)
	# Up close, an armored taunt (Bedrock) drags the foe in and soaks its answer.
	var counter := String(ai.get("counter", ""))
	if counter != "" and _usable(me, counter) and me.moves()[counter].has("armor") and dist < reach + 30.0 \
			and not _foe_grab_ready(foe) and _roll(0.08):
		_press(int(ACTION_BIT[counter]))
		return
	if _lands(sim, me, foe, dist, reach):
		_hold(SimDefs.move_bits(to_foe))
		if _usable(me, "heavy") and _roll(0.2):
			_hold_heavy = rng.randi_range(4, 14)
			_press(SimDefs.IN_HEAVY)
		else:
			_press(SimDefs.IN_LIGHT)
		return
	if dist <= reach:
		_go_to(sim, me, me.pos + to_foe)  # not yet sure to land: keep walking it down
		return
	# Aim a little between the foe and the middle of the floor: it gets pushed outward.
	var mid := sim.floor_rect().get_center()
	var at := _seen(foe)
	var cut := at + (mid - at).normalized() * minf(24.0, dist * 0.3)
	_go(sim, me, cut - me.pos)


## Skirmisher: poke from range, dive in for a combo when the poke lands or the foe is
## stuck, then run back out to poke range.
func _plan_skirmish(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, reach: float, danger: float) -> void:
	var ai := _ai(me)
	if _engage_t > 0:
		_engage_t -= 1
		if _lands(sim, me, foe, dist, reach):
			_hold(SimDefs.move_bits(to_foe))
			_press(SimDefs.IN_LIGHT)
			_engage_t = mini(_engage_t, 15)
		else:
			_go_to(sim, me, me.pos + to_foe)
		return
	if me.energy >= CreatureSim.MAX_ENERGY or foe.hp / foe.max_hp < 0.3 or not foe.can_dodge():
		_engage_t = 60
	var pr: Array = ai.get("poke_range", [danger + 30.0, danger + 80.0])
	var keep := (float(pr[0]) + float(pr[1])) * 0.5
	_go(sim, me, _orbit_dir(sim, me, foe, maxf(keep, danger + 24.0)))


## Fighter: hover at the edge of the foe's reach, step in and out to bait a swing (and
## punish it), and take the hit when its own reach is longer.
func _plan_footsie(sim: MatchSim, me: CreatureSim, foe: CreatureSim, to_foe: Vector2, dist: float, reach: float, danger: float) -> void:
	_dance_t -= 1
	if _dance_t <= 0:
		_dance_t = rng.randi_range(14, 30)
	var edge := danger + 3.0
	if _lands(sim, me, foe, dist, reach):
		_hold(SimDefs.move_bits(to_foe))
		_press(SimDefs.IN_LIGHT)
		return
	var inward := _dance_t > 18
	var r := edge - 6.0 if inward else edge + 6.0
	_go(sim, me, _orbit_dir(sim, me, foe, r))
