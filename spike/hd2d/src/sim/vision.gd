class_name Vision
extends RefCounted
## Who can see whom: brush hides, fences and walls block the line of sight. One rule
## for both the screen (main/FxView/CreatureView hide what the local team can't see) and
## the CPU (it only chases and aims at what its team can see).
##
## Not part of the simulation: MatchSim never calls it and it never writes sim state.
## It reads the match (positions, states, the terrain) plus a small memory of recent
## hits that its owner feeds from `sim.events` each tick (`observe`), so it's a pure,
## deterministic function of the match and the events seen so far: integer grid walks
## and plain arithmetic, no sin/cos/atan2/pow/exp. The CPU on an online referee and in
## the Daily gets the same answer on every machine.
##
## The rules (a viewer is one living fighter; a team sees what any living member sees,
## and everything once none is left standing):
## - Yourself and your teammates: always.
## - A fighter that is knocked out: always (the KO is for everyone).
## - Line of sight: a straight line from the viewer's centre to the target's that
##   crosses a WALL or FENCE cell (the cells each of them stands in don't count) is
##   blocked. A smashed wall is cracked floor until it rebuilds, so sight passes it.
##   Chasms, holes, shallows and brush don't block sight.
## - Brush (`covered`): a fighter standing in it is hidden unless the viewer is within
##   HIDE_RANGE of it, or it is attacking (from the move's first startup frame), or it
##   is reeling from a hit (hitstun, crumple, launched, knocked down), or it landed or
##   took a hit (or a block) in the last REVEAL_TICKS ticks.
## Stealth (Tiptoe) is separate: main hides a stealthed foe from the local team entirely
## (`_update_vision`; his own team sees a ghost) and the CPU treats it as hidden.

const HIDE_RANGE := 34.0
const REVEAL_TICKS := 30
## Events that count as landing or taking a hit, and the keys naming who was in it.
const CLASH_EVENTS := ["hit", "block", "armor", "grab", "hook", "guard_break", "shatter"]
const CLASH_KEYS := ["attacker", "target", "who", "by"]
const LONG_AGO := -1000000

## creature id -> sim tick of its last hit landed or taken (a block counts).
var _clash := {}
## Line-of-sight is skipped on maps with no walls or fences (cached per arena).
var _blockers_arena := ""
var _blockers_terrain: TerrainGrid = null
var _has_blockers := true
## Line-of-sight answers for one terrain at one version (see clear_line).
static var _memo := {}
static var _memo_terrain := 0
static var _memo_version := -1
const MEMO_MAX := 1024
static var _memo_lock := Mutex.new()


func clear() -> void:
	_clash.clear()
	_blockers_terrain = null


## Notes the hits in `events` (one step's `sim.events`, each with its "tick").
func observe(events: Array) -> void:
	for e in events:
		if not (String(e.get("type", "")) in CLASH_EVENTS):
			continue
		var t := int(e.get("tick", 0))
		for k in CLASH_KEYS:
			if e.has(k):
				var id := int(e[k])
				if id >= 0 and t > int(_clash.get(id, LONG_AGO)):
					_clash[id] = t


## The tick `target` last landed or took a hit, as far as `observe` has seen.
func clash_tick(target: CreatureSim) -> int:
	return int(_clash.get(target.id, LONG_AGO))


## Whether `viewer` can see `target` right now.
func can_see(sim: MatchSim, viewer: CreatureSim, target: CreatureSim) -> bool:
	return sees(sim, viewer, target, clash_tick(target), _blockers(sim))


## Whether anyone on `team` can see `target` (team vision is shared). A target on
## `team` itself is always seen, and so is everyone while the whole team is knocked out
## (between respawns, or the match is over): there's nobody left to hide from.
func team_sees(sim: MatchSim, team: int, target: CreatureSim) -> bool:
	if target.team == team or target.state == CreatureSim.State.KO:
		return true
	var clash := clash_tick(target)
	var walls := _blockers(sim)
	var anyone := false
	for v in sim.creatures:
		if v.team != team or v.state == CreatureSim.State.KO:
			continue
		anyone = true
		if sees(sim, v, target, clash, walls):
			return true
	return not anyone


## Whether `team` has a clear line of sight to the point `p` (fences and walls only;
## for things that aren't fighters, like a thrown knife).
func team_sight_to(sim: MatchSim, team: int, p: Vector2) -> bool:
	if not _blockers(sim):
		return true
	for v in sim.creatures:
		if v.team == team and v.state != CreatureSim.State.KO and clear_line(sim.terrain, v.pos, p):
			return true
	return false


## The rule itself, as a pure function: `clash` is the tick `target` last landed or
## took a hit; `walls` false skips the line walk (the map has no walls or fences).
static func sees(sim: MatchSim, viewer: CreatureSim, target: CreatureSim, clash := LONG_AGO,
		walls := true) -> bool:
	if viewer == target or viewer.team == target.team:
		return true
	if target.state == CreatureSim.State.KO:
		return true
	if viewer.state == CreatureSim.State.KO:
		return false
	if walls and not clear_line(sim.terrain, viewer.pos, target.pos):
		return false
	if not target.covered:
		return true
	if viewer.pos.distance_squared_to(target.pos) <= HIDE_RANGE * HIDE_RANGE:
		return true
	if target.state in [CreatureSim.State.ATTACK, CreatureSim.State.HITSTUN, CreatureSim.State.CRUMPLE,
			CreatureSim.State.AIRBORNE, CreatureSim.State.KNOCKDOWN]:
		return true
	return sim.tick - clash <= REVEAL_TICKS


static func blocks_sight(v: int) -> bool:
	return v == TerrainGrid.WALL or v == TerrainGrid.FENCE


## Walks the grid cells the segment a -> b passes through (Amanatides-Woo: one cell at
## a time, plain arithmetic only) and says whether none of them blocks sight. The cells
## holding a and b don't count. Where the line passes exactly through a cell corner, both
## cells beside it are checked, so sight never slips between two blockers that touch
## diagonally.
##
## No wall or fence in the box round the two cells (TerrainIndex) means clear without
## walking. Answers are kept for the terrain's current version (`_memo`): within a tick
## every CPU on a team and the screen ask the same lines.
static func clear_line(t: TerrainGrid, a: Vector2, b: Vector2) -> bool:
	var c := t.world_to_cell(a)
	var end := t.world_to_cell(b)
	if c == end:
		return true
	var ix := TerrainIndex.of(t)
	if ix.count(ix.body, mini(c.x, end.x) - 1, mini(c.y, end.y) - 1, maxi(c.x, end.x) + 1,
			maxi(c.y, end.y) + 1) == 0:
		return true
	var id := t.get_instance_id()
	var key := Vector4(a.x, a.y, b.x, b.y)
	_memo_lock.lock()  # the CPUs may be thinking on several threads (CpuController.think_all)
	if id != _memo_terrain or t.version != _memo_version or _memo.size() >= MEMO_MAX:
		_memo.clear()
		_memo_terrain = id
		_memo_version = t.version
	var known: Variant = _memo.get(key)
	_memo_lock.unlock()
	if known != null:
		return known
	var clear := _walk(t, a, b, c, end)
	_memo_lock.lock()
	if id == _memo_terrain and t.version == _memo_version:
		_memo[key] = clear
	_memo_lock.unlock()
	return clear


static func _walk(t: TerrainGrid, a: Vector2, b: Vector2, c: Vector2i, end: Vector2i) -> bool:
	var cell := float(SimDefs.CELL)
	# Positions in cell units, from the grid's corner.
	var ax := (a.x - SimDefs.GRID_X) / cell
	var ay := (a.y - SimDefs.GRID_Y) / cell
	var dx := (b.x - a.x) / cell
	var dy := (b.y - a.y) / cell
	var sx := 1 if dx > 0.0 else (-1 if dx < 0.0 else 0)
	var sy := 1 if dy > 0.0 else (-1 if dy < 0.0 else 0)
	# Parametric distance (0..1 along the segment) to the next vertical / horizontal
	# cell boundary, and between boundaries.
	var big := 1.0e30
	var tdx := absf(1.0 / dx) if sx != 0 else big
	var tdy := absf(1.0 / dy) if sy != 0 else big
	var tmx := big
	var tmy := big
	if sx > 0:
		tmx = (float(c.x + 1) - ax) / dx
	elif sx < 0:
		tmx = (float(c.x) - ax) / dx
	if sy > 0:
		tmy = (float(c.y + 1) - ay) / dy
	elif sy < 0:
		tmy = (float(c.y) - ay) / dy
	var guard := absi(end.x - c.x) + absi(end.y - c.y) + 2
	while c != end and guard > 0:
		guard -= 1
		if tmx < tmy:
			c.x += sx
			tmx += tdx
		elif tmy < tmx:
			c.y += sy
			tmy += tdy
		else:
			# Exactly through a corner: both cells beside it must be clear.
			var side_a := Vector2i(c.x + sx, c.y)
			var side_b := Vector2i(c.x, c.y + sy)
			if (side_a != end and _blocks(t, side_a)) or (side_b != end and _blocks(t, side_b)):
				return false
			c.x += sx
			c.y += sy
			tmx += tdx
			tmy += tdy
		if c != end and _blocks(t, c):
			return false
	return true


static func _blocks(t: TerrainGrid, c: Vector2i) -> bool:
	return t.in_bounds(c) and blocks_sight(t.get_cell(c))


## Whether the match's map has any wall or fence at all (cached per arena and grid).
func _blockers(sim: MatchSim) -> bool:
	if _blockers_terrain != sim.terrain or _blockers_arena != sim.arena_id:
		_blockers_terrain = sim.terrain
		_blockers_arena = sim.arena_id
		_has_blockers = false
		for v in sim.terrain.base:
			if blocks_sight(v):
				_has_blockers = true
				break
	return _has_blockers
