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
##
## Effects (one dictionary, the same keys for any shape): `damage_pct` of max HP as true
## damage (no guard, no shield, no damage_mult), times `role_mult[role]`; never below
## `min_hp`; a `push` (px a tick, over weight) with `stun` ticks of hitstun; `crack` px of
## cracked floor, a `pit` / `pit_core` (damage_circle), `pickup` {kind might|haste,
## seconds, radius, buff_seconds, mult}.
##
## Events: hazard_warn {hazard, shape, side, dir, ticks}, hazard_strike {hazard, shape,
## radius, big, core}, hazard_hit {who, hazard, shape, damage}, hazard_shelter {who,
## hazard}, hazard_end {hazard, shape} (a wave has passed), hazard_pickup {who, kind,
## ticks}, hazard_pickup_gone {}.

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


# ------------------------------------------------------------------ effects

## The effects on one fighter: true damage (a share of max HP, by role, never below
## `min_hp`) and a push with hitstun along `push_dir`.
static func hurt(sim: MatchSim, c: CreatureSim, eff: Dictionary, push_dir: Vector2, id: String, shape: String) -> float:
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
	else:
		var stun := int(eff.get("stun", 0))
		if c.is_stunned():
			stun = maxi(stun, c.stun)
		c.enter_hitstun(stun, kb)
	sim.emit_event("hazard_hit", c.pos, dmg, {"who": c.id, "hazard": id, "shape": shape, "damage": dmg})
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
