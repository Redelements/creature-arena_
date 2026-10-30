class_name Hazards
extends RefCounted
## Arena hazards: things the arena does to everyone on a schedule (data/rules/hazards.json),
## switched on by a mutator's "hazards" list (MatchSim.apply_mutators). The rules are here;
## the state lives on the match (`MatchSim.hazards`, `hazard_pickups`, saved by snapshot,
## restore and state_digest), and the definitions are fixed for the match
## (`MatchSim.hazard_defs`, not state). Every number is data (keys in docs/MECHANICS.md,
## "Arena hazards"); every choice (which edge, where a meteor falls) comes from an integer
## LCG seeded by the mutator seed, so every machine agrees.
##
## Shapes:
## - "wave": every `every_seconds` (the first warning at `first_seconds`) a warning of
##   `warn_seconds` (the swell on a seeded edge), then the front sweeps the floor in
##   `sweep_seconds`. A fighter it passes takes the effects and is pushed downstream,
##   unless a rubble wall (WALL) stands within `shelter.depth` px upstream of it in a lane
##   about its body wide (`sheltered`). Afterwards the downstream `shallows.share` of the
##   floor's intact cells is shallows for `shallows.seconds`, then the map's own floor again.
##   It raises `breakwaters` (rubble blocks) at the start, clear of every fighter.
## - "meteors": every `every_seconds`, `count` meteors land over `spread_seconds`, each a
##   shadow for `warn_ticks` first; `aimed_share` of them aimed near a fighter where it
##   stood when the shower began (+ up to `aim_jitter` px), the rest anywhere on the floor.
##   One per shower is `big` (its own overrides: a wider hit, a pit), one leaves a `pickup`.
## - "boulder": every `every_seconds`, `count` lanes `radius` x 2 wide across the floor
##   warn together for `warn_seconds`, each from an edge of `sides` (a seeded first one,
##   then the next in the list, so they come from different edges and cross) at a seeded
##   offset (`inset` px from the floor's sides); then a boulder rolls down each at `speed`
##   px a tick (state: the hazard's `rocks`, one dictionary each, and `pairs`). A fighter
##   one touches (not airborne, not leaping, not untouchable) takes the effects, once per
##   boulder until it turns, knocked down along its way. A hit of a type in
##   `reverse_types` (a heavy, a Surge) whose strike touches a boulder rolling at the
##   striker sends it back (`reverse_max` times a roll, `reverse_speed_mult` faster): from
##   then on it spares the striker's team and its hits are credited to the striker
##   (hazard_hit `by`, read by MatchSim.note_credit), through any ricochet after. Two
##   boulders that touch ricochet (`_ricochets`: the parts of their ways along the line
##   between them swap, an equal-weight bounce in plain vector sums), each on at its speed
##   x `ricochet_speed_mult` (never under `min_speed`); a pair can't again for
##   `ricochet_cooldown_ticks`. A wall or fence bounces one (the blocked axis flips)
##   `wall_bounces` times a roll, then it shatters. It's gone past the floor's edge or into
##   a pit (its middle over a hole or chasm).
## - "fault": every `every_seconds`, a seeded line across the floor (`axes`: "v" splits
##   left from right, "h" top from bottom; the data has "v" only, Kevin's ruling), `width` cells wide, wandering up to `wander`
##   cells (a step every `wander_every` cells), `inset` (a share of the floor) in from its
##   sides, cracks for `warn_seconds` (nothing changes underfoot yet), then opens into
##   CHASM for `open_seconds` and closes back to the map's `base`. Only cells whose base
##   is floor, shallows or brush open (never the map's walls, fences, chasms or bridges),
##   and the line keeps `spawn_clear` px from both spawns. An open fault is a chasm:
##   whoever stands on it falls (under `fall_ko`, Sinkhole's rule, that's a knockout);
##   leaps cross it.
##
## Effects (one dictionary, the same keys for any shape): `damage_pct` of max HP as true
## damage (no guard, no shield, no damage_mult), times `role_mult[role]`; never below
## `min_hp`; a `push` (px a tick, over weight) with `stun` ticks of hitstun, or
## `knockdown` ticks of a knockdown instead; `crack` px of cracked floor, a `pit` /
## `pit_core` (damage_circle), `pickup` {kind might|haste, seconds, radius, buff_seconds,
## mult}.
##
## Events: hazard_warn {hazard, shape, side, dir, ticks} (a boulder's, one per boulder,
## adds lane, radius, rock; a fault's axis, cells), hazard_strike {hazard, shape, radius,
## big, core} (a boulder starts rolling: rock; a fault opens), hazard_hit {who, hazard,
## shape, damage, by}, hazard_shelter {who, hazard}, hazard_reverse {hazard, by, dir, rock}
## (a heavy sent a boulder back), hazard_ricochet {hazard, rock, other (-1: a wall), dir,
## by}, hazard_end {hazard, shape, how} (a wave has passed; a boulder is gone: how = edge |
## pit | wall, rock; a fault has closed), hazard_pickup {who, kind, ticks},
## hazard_pickup_gone {}.

const PATH := "res://data/rules/hazards.json"
static var _table := {}

const IDLE := 0
const WARN := 1
const ACTIVE := 2
## A wave's edge: where it comes from, and the way it travels.
const SIDE_NAMES := ["left", "right", "top", "bottom"]
const SIDE_DIRS := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]


static func table() -> Dictionary:
	if _table.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_table = d if d is Dictionary else {}
	return _table


## Every hazard's id (data/rules/hazards.json), sorted: the Arena options page has a row each.
static func ids() -> Array:
	var out: Array = []
	for k in table():
		if not String(k).begins_with("_"):
			out.append(String(k))
	out.sort()
	return out


## A hazard's name for the screen ("name" in its entry, else its id).
static func name_of(id: String) -> String:
	return String((table().get(id, {}) as Dictionary).get("name", id))


static func ticks_of(seconds: Variant) -> int:
	return int(round(float(seconds) * SimDefs.TICK_RATE))


## The small LCG pit_floor uses: the same numbers on every machine.
static func lcg(x: int) -> int:
	return (x * 1103515245 + 12345) & 0x7fffffff


## Switches on the hazards `ids` (data/rules/hazards.json keys; unknown ones are skipped).
## Call once the creatures are in: breakwaters keep clear of them.
static func setup(sim: MatchSim, ids: Array, seed_: int) -> void:
	sim.hazards = []
	sim.hazard_pickups = []
	sim.hazard_defs = {}
	for k in ids.size():
		var id := String(ids[k])
		var d: Dictionary = table().get(id, {})
		if d.is_empty() or sim.hazard_defs.has(id):
			continue
		sim.hazard_defs[id] = d
		var st := {"id": id, "phase": IDLE, "t": 0, "next": ticks_of(d.get("first_seconds", 30)),
			"rng": lcg(seed_ * 31 + k * 7919 + 1), "side": 0, "front": 0.0, "done": [],
			"puddles": PackedInt32Array(), "dry": 0, "meteors": []}
		match String(d.get("shape", "")):
			"boulder":
				st.merge({"rocks": [], "pairs": {}})
			"fault":
				st.merge({"axis": 0, "cells": PackedInt32Array(), "open": PackedInt32Array(), "heal": 0})
		sim.hazards.append(st)
		if d.has("breakwaters"):
			_raise_breakwaters(sim, d["breakwaters"], st)


## Rubble blocks (`size` cells) on intact floor, at least `clear` px from every fighter and
## spawn, `gap` cells apart, `inset` cells in from the floor's edge. They are the map's own
## pieces from then on (base WALL): a heavy charge smashes one, and it rebuilds.
static func _raise_breakwaters(sim: MatchSim, bw: Dictionary, st: Dictionary) -> void:
	var t := sim.terrain
	var n := int(bw.get("count", 0))
	var sz: Array = bw.get("size", [2, 2])
	var w := int(sz[0])
	var h := int(sz[1])
	var clear := float(bw.get("clear", 56))
	var gap := int(bw.get("gap", 12))
	var inset := int(bw.get("inset", 4))
	var keep_clear: Array[Vector2] = [sim.spawn(0), sim.spawn(1)]
	for c in sim.creatures:
		keep_clear.append(c.pos)
	var placed: Array[Vector2i] = []
	var x := int(st["rng"])
	var tries := 0
	while placed.size() < n and tries < n * 40:
		tries += 1
		x = lcg(x)
		var cx := inset + x % maxi(1, t.cols - 2 * inset - w)
		x = lcg(x)
		var cy := inset + x % maxi(1, t.rows - 2 * inset - h)
		var ok := true
		for p in placed:
			if absi(p.x - cx) < gap and absi(p.y - cy) < gap:
				ok = false
		var mid := t.cell_center(Vector2i(cx, cy)) + Vector2(w - 1, h - 1) * SimDefs.CELL * 0.5
		for q in keep_clear:
			if q.distance_to(mid) < clear:
				ok = false
		for yy in range(cy, cy + h):
			for xx in range(cx, cx + w):
				var c := Vector2i(xx, yy)
				if not t.in_bounds(c) or t.get_cell(c) != TerrainGrid.INTACT or t.get_base(c) != TerrainGrid.INTACT:
					ok = false
		if not ok:
			continue
		placed.append(Vector2i(cx, cy))
		for yy in range(cy, cy + h):
			for xx in range(cx, cx + w):
				var i := yy * t.cols + xx
				t.cells[i] = TerrainGrid.WALL
				t.base[i] = TerrainGrid.WALL
				t.timers[i] = 0
		t.version += 1
	st["rng"] = x


## One tick of every hazard (MatchSim.step, after the hits). Nothing happens once fewer
## than two sides are standing: a match that's over stays over.
static func step(sim: MatchSim) -> void:
	if _sides_standing(sim) < 2:
		return
	for st in sim.hazards:
		var d: Dictionary = sim.hazard_defs.get(String(st["id"]), {})
		_dry(sim, st)
		match String(d.get("shape", "")):
			"wave":
				_step_wave(sim, d, st)
			"meteors":
				_step_meteors(sim, d, st)
			"boulder":
				_step_boulder(sim, d, st)
			"fault":
				_step_fault(sim, d, st)
	if not sim.hazard_pickups.is_empty():
		_step_pickups(sim)


static func _sides_standing(sim: MatchSim) -> int:
	var seen := {}
	for c in sim.creatures:
		if c.state != CreatureSim.State.KO and c.hp > 0.0:
			seen[c.team] = true
	return seen.size()


# ------------------------------------------------------------------ the wave

## How far `p` is downstream of the edge the wave comes from, along its travel.
static func wave_s(fr: Rect2, side: int, p: Vector2) -> float:
	match side:
		0: return p.x - fr.position.x
		1: return fr.end.x - p.x
		2: return p.y - fr.position.y
	return fr.end.y - p.y


## The floor's length along the wave's travel.
static func wave_len(fr: Rect2, side: int) -> float:
	return fr.size.x if side < 2 else fr.size.y


static func wave_dir(side: int) -> Vector2:
	return SIDE_DIRS[clampi(side, 0, 3)]


## Whether a body at `pos` is behind rubble for a wave travelling `dir`: a WALL cell within
## `depth` px upstream, sampled every 4 px down the middle of its lane and `lane` x its
## radius to either side.
static func sheltered(terrain: TerrainGrid, pos: Vector2, radius: float, dir: Vector2, depth := 48.0, lane := 0.6) -> bool:
	var across := Vector2(-dir.y, dir.x)
	var n := int(depth / 4.0)
	for i in range(1, n + 1):
		var back := pos - dir * (float(i) * 4.0)
		for j in [-1.0, 0.0, 1.0]:
			if terrain.get_cell(terrain.world_to_cell(back + across * (radius * lane * j))) == TerrainGrid.WALL:
				return true
	return false


static func shelters(d: Dictionary, terrain: TerrainGrid, c: CreatureSim, dir: Vector2) -> bool:
	var sh: Dictionary = d.get("shelter", {})
	return sheltered(terrain, c.pos, c.radius, dir, float(sh.get("depth", 48)), float(sh.get("lane", 0.6)))


static func _step_wave(sim: MatchSim, d: Dictionary, st: Dictionary) -> void:
	var fr := sim.floor_rect()
	match int(st["phase"]):
		IDLE:
			if sim.tick < int(st["next"]):
				return
			var x := lcg(int(st["rng"]))
			st["rng"] = x
			st["side"] = x % 4
			st["phase"] = WARN
			st["t"] = 0
			st["front"] = 0.0
			st["done"] = []
			st["next"] = int(st["next"]) + maxi(1, ticks_of(d.get("every_seconds", 30)))
			var side := int(st["side"])
			sim.emit_event("hazard_warn", _edge_mid(fr, side), float(ticks_of(d.get("warn_seconds", 3))),
				{"hazard": String(st["id"]), "shape": "wave", "side": side, "dir": wave_dir(side),
				"ticks": ticks_of(d.get("warn_seconds", 3))})
		WARN:
			st["t"] = int(st["t"]) + 1
			if int(st["t"]) >= ticks_of(d.get("warn_seconds", 3)):
				st["phase"] = ACTIVE
				st["t"] = 0
				var side := int(st["side"])
				sim.emit_event("hazard_strike", _edge_mid(fr, side), 0.0,
					{"hazard": String(st["id"]), "shape": "wave", "side": side, "dir": wave_dir(side)})
		ACTIVE:
			st["t"] = int(st["t"]) + 1
			var side := int(st["side"])
			var sweep := maxi(1, ticks_of(d.get("sweep_seconds", 1.0)))
			var front := wave_len(fr, side) * float(mini(int(st["t"]), sweep)) / float(sweep)
			st["front"] = front
			var dir := wave_dir(side)
			var done: Array = st["done"]
			for c in sim.creatures:
				if done.has(c.id) or wave_s(fr, side, c.pos) > front:
					continue
				done.append(c.id)
				if c.state == CreatureSim.State.KO or not c.can_be_hit():
					continue  # down, falling, or dodging through it
				if shelters(d, sim.terrain, c, dir):
					sim.emit_event("hazard_shelter", c.pos, 0.0, {"who": c.id, "hazard": String(st["id"])})
					continue
				hurt(sim, c, d, dir, String(st["id"]), "wave")
			if int(st["t"]) >= sweep:
				st["phase"] = IDLE
				st["t"] = 0
				_flood(sim, d, st)
				sim.emit_event("hazard_end", _edge_mid(fr, side ^ 1), 0.0, {"hazard": String(st["id"]), "shape": "wave", "side": side})


static func _edge_mid(fr: Rect2, side: int) -> Vector2:
	match side:
		0: return Vector2(fr.position.x, fr.get_center().y)
		1: return Vector2(fr.end.x, fr.get_center().y)
		2: return Vector2(fr.get_center().x, fr.position.y)
	return Vector2(fr.get_center().x, fr.end.y)


## After the wave: the downstream share of the floor's intact cells is shallows for a while.
static func _flood(sim: MatchSim, d: Dictionary, st: Dictionary) -> void:
	var sh: Dictionary = d.get("shallows", {})
	var share := float(sh.get("share", 0.0))
	if share <= 0.0:
		return
	_revert(sim, st)
	var t := sim.terrain
	var fr := sim.floor_rect()
	var side := int(st["side"])
	var from := wave_len(fr, side) * (1.0 - share)
	var out := PackedInt32Array()
	for cy in t.rows:
		for cx in t.cols:
			var i := cy * t.cols + cx
			if t.cells[i] != TerrainGrid.INTACT or t.base[i] != TerrainGrid.INTACT:
				continue
			if wave_s(fr, side, t.cell_center(Vector2i(cx, cy))) < from:
				continue
			t.cells[i] = TerrainGrid.SHALLOWS
			out.append(i)
	if not out.is_empty():
		t.version += 1
	st["puddles"] = out
	st["dry"] = sim.tick + ticks_of(sh.get("seconds", 5))


static func _dry(sim: MatchSim, st: Dictionary) -> void:
	if (st["puddles"] as PackedInt32Array).is_empty() or sim.tick < int(st["dry"]):
		return
	_revert(sim, st)


## The puddles go back to the map's floor (whatever its base is now); a cell something
## else changed since (a hole punched in the water can't be: shallows don't take damage)
## is left alone.
static func _revert(sim: MatchSim, st: Dictionary) -> void:
	var t := sim.terrain
	var any := false
	for i in (st["puddles"] as PackedInt32Array):
		if t.cells[i] == TerrainGrid.SHALLOWS:
			t.cells[i] = t.base[i]
			t.timers[i] = 0
			any = true
	if any:
		t.version += 1
	st["puddles"] = PackedInt32Array()
	st["dry"] = 0


# ------------------------------------------------------------------ meteors

static func _step_meteors(sim: MatchSim, d: Dictionary, st: Dictionary) -> void:
	if sim.tick >= int(st["next"]):
		st["next"] = int(st["next"]) + maxi(1, ticks_of(d.get("every_seconds", 25)))
		_start_shower(sim, d, st)
	var ms: Array = st["meteors"]
	if ms.is_empty():
		return
	var keep: Array = []
	for m in ms:
		if sim.tick >= int(m["land"]):
			_impact(sim, d, st, m)
		else:
			keep.append(m)
	st["meteors"] = keep


static func _start_shower(sim: MatchSim, d: Dictionary, st: Dictionary) -> void:
	var n := maxi(1, int(d.get("count", 8)))
	var spread := ticks_of(d.get("spread_seconds", 2))
	var warn := maxi(1, int(d.get("warn_ticks", 70)))
	var inset := float(d.get("inset", 20))
	var jitter := int(d.get("aim_jitter", 40))
	var aimed := int(round(float(n) * float(d.get("aimed_share", 0.5))))
	var fr := sim.floor_rect().grow(-inset)
	var targets: Array[Vector2] = []
	for c in sim.creatures:
		if c.state != CreatureSim.State.KO and c.hp > 0.0:
			targets.append(c.pos)
	var x := int(st["rng"])
	x = lcg(x)
	var big := x % n
	x = lcg(x)
	var core := (big + 1 + x % maxi(1, n - 1)) % n if n > 1 else 0
	var aimed_so_far := 0
	var out: Array = []
	for i in n:
		var at: Vector2
		if (i * aimed) % n < aimed and not targets.is_empty():
			x = lcg(x)
			var ox := x % (2 * jitter + 1) - jitter
			x = lcg(x)
			var oy := x % (2 * jitter + 1) - jitter
			at = targets[aimed_so_far % targets.size()] + Vector2(ox, oy)
			aimed_so_far += 1
		else:
			x = lcg(x)
			var px := fr.position.x + float(x % maxi(1, int(fr.size.x)))
			x = lcg(x)
			var py := fr.position.y + float(x % maxi(1, int(fr.size.y)))
			at = Vector2(px, py)
		at = at.clamp(fr.position, fr.end)
		var eff := effects(d, i == big)
		out.append({"pos": at, "land": sim.tick + warn + (i * spread) / maxi(1, n - 1), "warn": warn,
			"radius": float(eff.get("radius", 28)), "big": i == big, "core": i == core})
	st["rng"] = x
	st["meteors"] = out
	sim.emit_event("hazard_warn", sim.floor_rect().get_center(), float(warn + spread),
		{"hazard": String(st["id"]), "shape": "meteors", "side": -1, "dir": Vector2.ZERO, "ticks": warn + spread})


## A hazard's effects: its own keys, with the "big" block's on top for the big one.
static func effects(d: Dictionary, big: bool) -> Dictionary:
	if not big or not d.has("big"):
		return d
	var e := d.duplicate()
	e.merge(d["big"], true)
	return e


static func _impact(sim: MatchSim, d: Dictionary, st: Dictionary, m: Dictionary) -> void:
	var at: Vector2 = m["pos"]
	var eff := effects(d, bool(m["big"]))
	var r := float(eff.get("radius", 28))
	for c in sim.creatures:
		if not c.can_be_hit() or c.pos.distance_to(at) > r + c.radius:
			continue
		var push := c.pos - at
		push = push.normalized() if push.length_squared() > 0.0001 else Vector2.DOWN
		hurt(sim, c, eff, push, String(st["id"]), "meteors")
	if float(eff.get("crack", 0.0)) > 0.0:
		sim.terrain.crack_circle(at, float(eff["crack"]))
	if float(eff.get("pit", 0.0)) > 0.0:
		sim.terrain.damage_circle(at, float(eff["pit"]), float(eff.get("pit_core", -1.0)))
	sim.emit_event("hazard_strike", at, r, {"hazard": String(st["id"]), "shape": "meteors", "radius": r,
		"big": bool(m["big"]), "core": bool(m["core"])})
	if bool(m["core"]) and eff.has("pickup"):
		var pk: Dictionary = eff["pickup"]
		sim.hazard_pickups.append({"pos": at, "radius": float(pk.get("radius", 10)),
			"until": sim.tick + ticks_of(pk.get("seconds", 8)), "kind": String(pk.get("kind", "might")),
			"ticks": ticks_of(pk.get("buff_seconds", 10)), "mult": float(pk.get("mult", 1.2))})


# ------------------------------------------------------------------ the boulder

## The point across the floor a boulder lane runs through (px from the floor's side the
## lane is measured from: its top for a lane across, its left for one down).
static func lane_point(fr: Rect2, side: int, lane: float) -> Vector2:
	return Vector2(fr.position.x, fr.position.y + lane) if side < 2 else Vector2(fr.position.x + lane, fr.position.y)


## Where a boulder from `side` starts: just off the floor, its far edge on the floor's edge.
static func boulder_start(fr: Rect2, side: int, lane: float, radius: float) -> Vector2:
	var p := lane_point(fr, side, lane)
	match side:
		0: return Vector2(fr.position.x - radius, p.y)
		1: return Vector2(fr.end.x + radius, p.y)
		2: return Vector2(p.x, fr.position.y - radius)
	return Vector2(p.x, fr.end.y + radius)


## One boulder of a roll (its own dictionary in the hazard's `rocks`): where its lane is,
## where it is and where it's going, who sent it back last (credit), its hits this roll.
static func _new_rock(fr: Rect2, side: int, lane: float, r: float, speed: float) -> Dictionary:
	return {"side": side, "lane": lane, "pos": boulder_start(fr, side, lane, r), "dir": wave_dir(side),
		"speed": speed, "live": true, "by": -1, "by_team": -1, "rev": 0, "bounces": 0, "turned": -1,
		"done": []}


## The lanes of a roll: `count` boulders, each from an edge of `sides` (a seeded start,
## then the next edge in the list for each one after, so three come from three edges and
## their lanes cross) at a seeded offset `inset` px or more from the floor's sides.
static func _plan_rocks(sim: MatchSim, d: Dictionary, st: Dictionary) -> Array:
	var fr := sim.floor_rect()
	var r := float(d.get("radius", 18))
	var sides: Array = d.get("sides", [0, 1, 2, 3])
	if sides.is_empty():
		sides = [0]
	var n := maxi(1, int(d.get("count", 3)))
	var inset := float(d.get("inset", 36))
	var x := lcg(int(st["rng"]))
	var first := x % sides.size()
	var out: Array = []
	for k in n:
		var side := int(sides[(first + k) % sides.size()])
		x = lcg(x)
		var span := fr.size.y if side < 2 else fr.size.x
		var room := maxi(1, int(span - 2.0 * inset))
		out.append(_new_rock(fr, side, inset + float(x % room), r, float(d.get("speed", 3.0))))
	st["rng"] = x
	return out


static func _step_boulder(sim: MatchSim, d: Dictionary, st: Dictionary) -> void:
	var fr := sim.floor_rect()
	var r := float(d.get("radius", 18))
	var id := String(st["id"])
	match int(st["phase"]):
		IDLE:
			if sim.tick < int(st["next"]):
				return
			st["rocks"] = _plan_rocks(sim, d, st)
			st["pairs"] = {}
			st["phase"] = WARN
			st["t"] = 0
			st["next"] = int(st["next"]) + maxi(1, ticks_of(d.get("every_seconds", 30)))
			var warn := ticks_of(d.get("warn_seconds", 1.5))
			for k in (st["rocks"] as Array).size():
				var rk: Dictionary = st["rocks"][k]
				sim.emit_event("hazard_warn", rk["pos"], float(warn),
					{"hazard": id, "shape": "boulder", "side": int(rk["side"]), "dir": rk["dir"],
					"ticks": warn, "lane": float(rk["lane"]), "radius": r, "rock": k})
		WARN:
			st["t"] = int(st["t"]) + 1
			if int(st["t"]) < ticks_of(d.get("warn_seconds", 1.5)):
				return
			st["phase"] = ACTIVE
			st["t"] = 0
			for k in (st["rocks"] as Array).size():
				var rk: Dictionary = st["rocks"][k]
				sim.emit_event("hazard_strike", rk["pos"], r, {"hazard": id, "shape": "boulder",
					"side": int(rk["side"]), "dir": rk["dir"], "radius": r, "rock": k})
		ACTIVE:
			st["t"] = int(st["t"]) + 1
			var rocks: Array = st["rocks"]
			for k in rocks.size():
				var rk: Dictionary = rocks[k]
				if bool(rk["live"]) and int(rk["rev"]) < int(d.get("reverse_max", 1)):
					_reverse_boulder(sim, d, st, rk, k, r)
			for k in rocks.size():
				if bool(rocks[k]["live"]):
					_roll_rock(sim, d, st, rocks[k], k, r, fr)
			_ricochets(sim, d, st, r)
			for k in rocks.size():
				var rk: Dictionary = rocks[k]
				if bool(rk["live"]):
					_rock_hits(sim, d, st, rk, r)
			var any := false
			for rk in rocks:
				any = any or bool(rk["live"])
			if not any:
				st["phase"] = IDLE
				st["t"] = 0
				st["rocks"] = []
				st["pairs"] = {}


## One boulder's move: on, then off the floor's edge (gone), into a pit (gone), or into a
## wall or fence: it bounces off (`wall_bounces` times a roll), then shatters.
static func _roll_rock(sim: MatchSim, d: Dictionary, st: Dictionary, rk: Dictionary, k: int, r: float, fr: Rect2) -> void:
	var dir: Vector2 = rk["dir"]
	var old: Vector2 = rk["pos"]
	var pos: Vector2 = old + dir * float(rk["speed"])
	var how := ""
	var t := sim.terrain
	if not fr.grow(r + 1.0).has_point(pos):
		how = "edge"
	elif fr.has_point(pos) and t.is_hole_at(pos):
		how = "pit"
	elif t.solid_at(pos + dir * (r * 0.6)):
		if int(rk["bounces"]) < int(d.get("wall_bounces", 2)):
			# Off the wall: the way it was blocked flips (both, in a corner), from where it was.
			var flip := Vector2.ONE
			if t.solid_at(old + Vector2(dir.x, 0.0) * (r * 0.6 + float(rk["speed"]))):
				flip.x = -1.0
			if t.solid_at(old + Vector2(0.0, dir.y) * (r * 0.6 + float(rk["speed"]))):
				flip.y = -1.0
			if flip == Vector2.ONE:
				flip = -Vector2.ONE
			rk["dir"] = dir * flip
			rk["bounces"] = int(rk["bounces"]) + 1
			_turned(sim, d, st, rk, k, -1, old, r)
			return  # it stays where it was this tick
		how = "wall"
	rk["pos"] = pos
	if how != "":
		rk["live"] = false
		sim.emit_event("hazard_end", pos, r, {"hazard": String(st["id"]), "shape": "boulder", "how": how, "rock": k})


## A boulder changed its way (a ricochet off another or off a wall): slower by
## `ricochet_speed_mult`, its hits this roll start again (spares whom it spared), and the
## turn is noted for the preview (`turned`). `other` is the other boulder, -1 for a wall.
static func _turned(sim: MatchSim, d: Dictionary, st: Dictionary, rk: Dictionary, k: int, other: int, at: Vector2, r: float) -> void:
	rk["speed"] = maxf(float(d.get("min_speed", 1.5)), float(rk["speed"]) * float(d.get("ricochet_speed_mult", 1.0)))
	rk["turned"] = sim.tick
	rk["done"] = []
	sim.emit_event("hazard_ricochet", at, r, {"hazard": String(st["id"]), "rock": k, "other": other,
		"dir": rk["dir"], "by": int(rk["by"])})


## Boulders that touch bounce off each other: the parts of their ways along the line between
## their middles swap (an elastic bounce of equal weights; plain vector sums, no trig), each
## goes on at its own speed in its new way, and they're pushed apart. A pair that has just
## bounced can't again for `ricochet_cooldown_ticks`, so they never stick.
static func _ricochets(sim: MatchSim, d: Dictionary, st: Dictionary, r: float) -> void:
	var rocks: Array = st["rocks"]
	var pairs: Dictionary = st["pairs"]
	var cd := maxi(1, int(d.get("ricochet_cooldown_ticks", 10)))
	for i in rocks.size():
		for j in range(i + 1, rocks.size()):
			var a: Dictionary = rocks[i]
			var b: Dictionary = rocks[j]
			if not bool(a["live"]) or not bool(b["live"]):
				continue
			var key := "%d:%d" % [i, j]
			if sim.tick < int(pairs.get(key, 0)):
				continue
			var pa: Vector2 = a["pos"]
			var pb: Vector2 = b["pos"]
			var gap := pb - pa
			var dist := gap.length()
			if dist > 2.0 * r:
				continue
			var n := gap / dist if dist > 0.0001 else Vector2(-Vector2(a["dir"]).y, Vector2(a["dir"]).x)
			var va: Vector2 = Vector2(a["dir"]) * float(a["speed"])
			var vb: Vector2 = Vector2(b["dir"]) * float(b["speed"])
			if (va - vb).dot(n) <= 0.0:
				continue  # already moving apart
			var an := va.dot(n)
			var bn := vb.dot(n)
			var va2 := va + n * (bn - an)
			var vb2 := vb + n * (an - bn)
			a["dir"] = va2.normalized() if va2.length_squared() > 0.0001 else -n
			b["dir"] = vb2.normalized() if vb2.length_squared() > 0.0001 else n
			var push := (2.0 * r - dist) * 0.5 + 0.5
			a["pos"] = pa - n * push
			b["pos"] = pb + n * push
			pairs[key] = sim.tick + cd
			var at := (pa + pb) * 0.5
			_turned(sim, d, st, a, i, j, at, r)
			_turned(sim, d, st, b, j, i, at, r)


## A boulder's hits: a fighter within its radius + body, hittable and on the ground, once a
## roll (again after a send-back or a ricochet); never the team that last sent it back.
static func _rock_hits(sim: MatchSim, d: Dictionary, st: Dictionary, rk: Dictionary, r: float) -> void:
	var pos: Vector2 = rk["pos"]
	var done: Array = rk["done"]
	var by_team := int(rk["by_team"])
	for c in sim.creatures:
		if done.has(c.id) or (by_team >= 0 and c.team == by_team):
			continue
		if c.state == CreatureSim.State.KO or not c.can_be_hit() or c.is_airborne():
			continue  # down, falling, dodging, leaping or in the air: it rolls under
		if c.pos.distance_to(pos) > r + c.radius:
			continue
		done.append(c.id)
		hurt(sim, c, d, rk["dir"], String(st["id"]), "boulder", int(rk["by"]))


## A strike of a `reverse_types` move (a heavy) touching a boulder while it rolls at the
## striker sends it back the other way: the striker's now, sparing the striker's team.
static func _reverse_boulder(sim: MatchSim, d: Dictionary, st: Dictionary, rk: Dictionary, k: int, r: float) -> void:
	var types: Array = d.get("reverse_types", ["heavy"])
	var pos: Vector2 = rk["pos"]
	var dir: Vector2 = rk["dir"]
	for a in sim.creatures:
		var seg := a.active_seg()
		if seg < 0 or a.id == int(rk["by"]):
			continue
		if not (String(a.hit_params(seg).get("type", "")) in types):
			continue
		if (a.pos - pos).dot(dir) <= 0.0:
			continue  # it's rolling away from them: nothing to send back
		if a.hit_center(seg).distance_to(pos) > a.hit_radius(seg) + r:
			continue
		rk["dir"] = -dir
		rk["speed"] = float(rk["speed"]) * float(d.get("reverse_speed_mult", 1.0))
		rk["rev"] = int(rk["rev"]) + 1
		rk["by"] = a.id
		rk["by_team"] = a.team
		rk["done"] = []
		rk["turned"] = sim.tick
		sim.emit_event("hazard_reverse", pos, r, {"hazard": String(st["id"]), "by": a.id, "dir": -dir, "rock": k})
		return


# ------------------------------------------------------------------ the fault line

## Whether the fault may open cell `i`: the map's floor, shallows or brush there (never its
## walls, fences, chasms), nothing standing as a wall now, and not on a bridge.
static func _fault_ok(sim: MatchSim, i: int) -> bool:
	var t := sim.terrain
	var b := t.base[i]
	if not (b == TerrainGrid.INTACT or b == TerrainGrid.SHALLOWS or b == TerrainGrid.BRUSH):
		return false
	if TerrainGrid.blocks_body(t.cells[i]) or t.cells[i] == TerrainGrid.CHASM:
		return false
	var c := Vector2i(i % t.cols, i / t.cols)
	for br in sim.bridge_rects:
		if br.has_point(c):
			return false
	return true


## Where a fault line may start across the floor on `axis` (0: a line down the floor, so
## a column; 1: across, a row): every first column (row) from `inset` of the floor in, whose
## strip with its wander keeps `spawn_clear` px across from both spawns (the line runs the
## floor's whole length, so only the distance across counts). With `any`, all of them.
static func _fault_starts(sim: MatchSim, d: Dictionary, axis: int, any := false) -> Array:
	var t := sim.terrain
	var w := maxi(1, int(d.get("width", 3)))
	var wander := maxi(0, int(d.get("wander", 2)))
	var across := t.cols if axis == 0 else t.rows
	var lo := int(float(across) * float(d.get("inset", 0.25))) + wander
	var hi := maxi(lo, across - lo - w)
	var clear := float(d.get("spawn_clear", 40))
	var all: Array = []
	var out: Array = []
	for c0 in range(lo, hi + 1):
		all.append(c0)
		var ok := true
		for side in 2:
			var sp := sim.spawn(side)
			for v in range(c0 - wander, c0 + w + wander):
				var mid := t.cell_center(Vector2i(v, v))
				if absf((mid.x - sp.x) if axis == 0 else (mid.y - sp.y)) < clear:
					ok = false
		if ok:
			out.append(c0)
	return all if any else out


## The cells of a seeded fault line: an axis from `axes` that has room clear of the spawns
## (`_fault_starts`; if none has, the first axis anywhere), a first column (row) on it,
## then down the floor's whole length a strip `width` cells wide that steps a cell aside
## every `wander_every` cells, never more than `wander` from where it began. Only cells
## `_fault_ok` allows.
static func _plan_fault(sim: MatchSim, d: Dictionary, st: Dictionary) -> PackedInt32Array:
	var t := sim.terrain
	var named: Array = []
	for a in d.get("axes", ["v", "h"]):
		var ax := 1 if String(a) == "h" else 0
		if not (ax in named):
			named.append(ax)
	if named.is_empty():
		named = [0]
	var axes: Array = []
	var room := {}
	for ax in named:
		var s := _fault_starts(sim, d, int(ax))
		if not s.is_empty():
			axes.append(ax)
			room[ax] = s
	if axes.is_empty():
		axes = [named[0]]
		room[named[0]] = _fault_starts(sim, d, int(named[0]), true)
	var x := lcg(int(st["rng"]))
	var axis := int(axes[x % axes.size()])
	var starts: Array = room[axis]
	st["axis"] = axis
	var w := maxi(1, int(d.get("width", 3)))
	var wander := maxi(0, int(d.get("wander", 2)))
	var every := maxi(1, int(d.get("wander_every", 3)))
	var along := t.rows if axis == 0 else t.cols
	x = lcg(x)
	var c0 := int(starts[x % starts.size()])
	var off := 0
	var out := PackedInt32Array()
	for k in along:
		if k > 0 and k % every == 0:
			x = lcg(x)
			off = clampi(off + (x >> 8) % 3 - 1, -wander, wander)
		for j in w:
			var cell := Vector2i(c0 + off + j, k) if axis == 0 else Vector2i(k, c0 + off + j)
			if not t.in_bounds(cell):
				continue
			var i := cell.y * t.cols + cell.x
			if _fault_ok(sim, i):
				out.append(i)
	st["rng"] = x
	return out


static func _step_fault(sim: MatchSim, d: Dictionary, st: Dictionary) -> void:
	var t := sim.terrain
	match int(st["phase"]):
		IDLE:
			if sim.tick < int(st["next"]):
				return
			st["cells"] = _plan_fault(sim, d, st)
			st["phase"] = WARN
			st["t"] = 0
			st["next"] = int(st["next"]) + maxi(1, ticks_of(d.get("every_seconds", 35)))
			var warn := ticks_of(d.get("warn_seconds", 2))
			sim.emit_event("hazard_warn", sim.floor_rect().get_center(), float(warn),
				{"hazard": String(st["id"]), "shape": "fault", "side": -1, "dir": Vector2.ZERO, "ticks": warn,
				"axis": int(st["axis"]), "cells": (st["cells"] as PackedInt32Array).size()})
		WARN:
			st["t"] = int(st["t"]) + 1
			if int(st["t"]) < ticks_of(d.get("warn_seconds", 2)):
				return
			var opened := PackedInt32Array()
			for i in (st["cells"] as PackedInt32Array):
				if not _fault_ok(sim, i):
					continue
				t.cells[i] = TerrainGrid.CHASM
				t.timers[i] = 1 << 29  # held open by the fault, not healed by the floor's clock
				opened.append(i)
			if not opened.is_empty():
				t.version += 1
			st["open"] = opened
			st["phase"] = ACTIVE
			st["t"] = 0
			st["heal"] = sim.tick + maxi(1, ticks_of(d.get("open_seconds", 10)))
			sim.emit_event("hazard_strike", sim.floor_rect().get_center(), 0.0,
				{"hazard": String(st["id"]), "shape": "fault", "axis": int(st["axis"]), "cells": opened.size()})
		ACTIVE:
			st["t"] = int(st["t"]) + 1
			if sim.tick < int(st["heal"]):
				return
			_close_fault(sim, st)
			st["phase"] = IDLE
			st["t"] = 0
			sim.emit_event("hazard_end", sim.floor_rect().get_center(), 0.0,
				{"hazard": String(st["id"]), "shape": "fault", "how": "closed"})


## The fault's cells go back to the map's floor (whatever its base is now); a cell
## something else changed since is left alone.
static func _close_fault(sim: MatchSim, st: Dictionary) -> void:
	var t := sim.terrain
	var any := false
	for i in (st["open"] as PackedInt32Array):
		if t.cells[i] == TerrainGrid.CHASM:
			t.cells[i] = t.base[i]
			t.timers[i] = 0
			any = true
	if any:
		t.version += 1
	st["open"] = PackedInt32Array()
	st["cells"] = PackedInt32Array()
	st["heal"] = 0


# ------------------------------------------------------------------ effects

## The effects on one fighter: true damage (a share of max HP, by role, never below
## `min_hp`) and a push with hitstun along `push_dir`.
## `by`: the fighter it's credited to (a boulder a heavy sent back), -1 for nobody.
static func hurt(sim: MatchSim, c: CreatureSim, eff: Dictionary, push_dir: Vector2, id: String, shape: String, by := -1) -> float:
	var mult := float((eff.get("role_mult", {}) as Dictionary).get(TeamSim.role_of(c), 1.0))
	var dmg := c.max_hp * float(eff.get("damage_pct", 0.0)) * mult
	var least := float(eff.get("min_hp", 0.0))
	if least > 0.0:
		dmg = minf(dmg, maxf(0.0, c.hp - least))
	dmg = maxf(0.0, dmg)
	c.hp -= dmg
	c.calm_t = 0
	c.flash = 6
	var kb := push_dir * float(eff.get("push", 0.0)) / maxf(0.1, c.weight)
	if c.state in [CreatureSim.State.AIRBORNE, CreatureSim.State.KNOCKDOWN, CreatureSim.State.DODGE]:
		c.knock_vel = kb
	elif int(eff.get("knockdown", 0)) > 0:
		c.enter_knockdown(int(eff["knockdown"]), kb)
	else:
		var stun := int(eff.get("stun", 0))
		if c.is_stunned():
			stun = maxi(stun, c.stun)
		c.enter_hitstun(stun, kb)
	sim.emit_event("hazard_hit", c.pos, dmg, {"who": c.id, "hazard": id, "shape": shape, "damage": dmg, "by": by})
	c.check_ko(sim)
	return dmg


static func _step_pickups(sim: MatchSim) -> void:
	var keep: Array = []
	for pk in sim.hazard_pickups:
		if sim.tick >= int(pk["until"]):
			sim.emit_event("hazard_pickup_gone", pk["pos"], 0.0, {"kind": String(pk["kind"])})
			continue
		var taker: CreatureSim = null
		for c in sim.creatures:
			if c.state in [CreatureSim.State.KO, CreatureSim.State.FALLING] or c.is_airborne():
				continue
			if c.pos.distance_to(pk["pos"]) <= float(pk["radius"]) + c.radius:
				taker = c
				break
		if taker == null:
			keep.append(pk)
			continue
		var t := int(pk["ticks"])
		if String(pk["kind"]) == "haste":
			taker.haste = maxi(taker.haste, t)
			taker.haste_mult = float(pk["mult"])
		else:
			taker.atk_buff = maxi(taker.atk_buff, t)
			taker.atk_mult = float(pk["mult"])
		sim.emit_event("hazard_pickup", pk["pos"], float(t), {"who": taker.id, "kind": String(pk["kind"]), "ticks": t})
	sim.hazard_pickups = keep


# ------------------------------------------------------------------ for the CPU and the views

## The wave coming or running, if any: {side, dir, phase, left (ticks until the front
## starts: 0 once it runs), front (px from its edge), def}. Empty when none.
static func wave_now(sim: MatchSim) -> Dictionary:
	for st in sim.hazards:
		var d: Dictionary = sim.hazard_defs.get(String(st["id"]), {})
		if String(d.get("shape", "")) != "wave" or int(st["phase"]) == IDLE:
			continue
		var left := 0
		if int(st["phase"]) == WARN:
			left = ticks_of(d.get("warn_seconds", 3)) - int(st["t"])
		return {"side": int(st["side"]), "dir": wave_dir(int(st["side"])), "phase": int(st["phase"]),
			"left": left, "front": float(st["front"]), "def": d, "done": st["done"]}
	return {}


## Every meteor on its way: [{pos, radius, land, warn, big, core}] (shown once tick >= land - warn).
static func meteors_now(sim: MatchSim) -> Array:
	var out: Array = []
	for st in sim.hazards:
		out.append_array(st.get("meteors", []))
	return out


## Every boulder warning or rolling, one entry a boulder: [{phase, side, dir (its way now),
## lane (px across, its first lane), start, pos, radius, speed, left (ticks of warning left:
## 0 once it rolls), by, rev, bounces, turned (the tick it last changed its way, -1: never),
## def}]. Boulders already gone are left out.
static func boulders_now(sim: MatchSim) -> Array:
	var out: Array = []
	var fr := sim.floor_rect()
	for st in sim.hazards:
		var d: Dictionary = sim.hazard_defs.get(String(st["id"]), {})
		if String(d.get("shape", "")) != "boulder" or int(st["phase"]) == IDLE:
			continue
		var r := float(d.get("radius", 18))
		var left := ticks_of(d.get("warn_seconds", 1.5)) - int(st["t"]) if int(st["phase"]) == WARN else 0
		for rk in st.get("rocks", []):
			if not bool(rk["live"]):
				continue
			var side := int(rk["side"])
			out.append({"phase": int(st["phase"]), "side": side, "dir": rk["dir"], "lane": float(rk["lane"]),
				"start": boulder_start(fr, side, float(rk["lane"]), r), "pos": rk["pos"], "radius": r,
				"speed": float(rk["speed"]), "left": left, "by": int(rk["by"]), "rev": int(rk["rev"]),
				"bounces": int(rk["bounces"]), "turned": int(rk["turned"]), "def": d})
	return out


## Every fault cracking or open: [{phase, axis, cells (planned, while it warns), open (the
## cells now chasm), left (ticks until it opens, while it warns), heal (the tick it
## closes), warn (its warning's length), def}].
static func faults_now(sim: MatchSim) -> Array:
	var out: Array = []
	for st in sim.hazards:
		var d: Dictionary = sim.hazard_defs.get(String(st["id"]), {})
		if String(d.get("shape", "")) != "fault" or int(st["phase"]) == IDLE:
			continue
		var warn := ticks_of(d.get("warn_seconds", 2))
		out.append({"phase": int(st["phase"]), "axis": int(st["axis"]), "cells": st["cells"], "open": st["open"],
			"left": warn - int(st["t"]) if int(st["phase"]) == WARN else 0, "heal": int(st["heal"]),
			"warn": warn, "def": d})
	return out
