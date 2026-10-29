class_name MatchSim
extends RefCounted
## The whole match state. Call step() once per tick with one input bitmask per creature.
## Everything the view needs to react to (hits, slams, falls) is listed in `events`
## after each step.
##
## Combo rules live in _apply_hit():
##   damage  = (base + stack bonus) x variety x stale
##   hitstun = base x max(0.4, 1 - 0.07 x (hit number - 1)) x stale
## where variety rises with the number of attack types landed in the combo and
## stale halves a move that already landed earlier in the same combo.

const HITSTUN_DECAY := 0.07
const HITSTUN_FLOOR := 0.4
const STALE_MULT := 0.5
## Defaults for the energy rates; data/rules/energy.json overrides them (energy_rules()).
const ENERGY_PER_DAMAGE := 1.5
const ENERGY_PER_DAMAGE_TAKEN := 1.0
const STONE_SHATTER_MULT := 1.25
## A blocked third light (or later: Cairn's Hook) leaves the attacker at least this many
## ticks behind the blocker, enough to punish with a jab, and it can't be cancelled out of.
const BLOCKED_ENDER_DISADVANTAGE := 16
## Defaults for a poison move without "poison_every" and a reel without "reel_speed".
const POISON_EVERY_DEFAULT := 30
const REEL_SPEED_DEFAULT := 5.0
## A raw Surge's windup when it doesn't freeze the match (freeze_all off), unless the
## move sets "crowd_windup": as long as the freeze it replaces.
const SURGE_CROWD_WINDUP := 18
## Training options a training match can turn on (set_training_flags).
const TRAINING_FLAGS := ["no_cooldowns", "full_energy"]
## Hit size of straight projectiles: radius_mult on every "radius" / "radius_end".
const PROJECTILES_PATH := "res://data/rules/projectiles.json"
static var _projectile_rules := {}
## Energy rates and whether the meter carries between rounds (data/rules/energy.json).
const ENERGY_PATH := "res://data/rules/energy.json"
static var _energy_rules := {}

var tick := 0
var hitstop := 0
## Knockout presentation lives in the simulation (not the view) so every player sees it
## on the same ticks: a full freeze, then slow motion where every other tick is skipped.
## Inputs are buffered throughout, as in hitstop.
var ko_freeze := 0
var slowmo := 0
var ko_freeze_ticks := 18
var ko_slowmo_ticks := 70
var terrain := TerrainGrid.new()
## The arena map this match plays on (ArenaMap): its id and its pieces are laid on the
## terrain by `set_arena`; every machine in an online match must pick the same one.
var arena_id := ArenaMap.DEFAULT
var arena := {}
## Rules a mode sets on the match: a fall knocks out (Sinkhole), and the ring of the
## floor that is cracked and about to drop (-1: none), so the CPU knows to get off it.
var fall_ko := false
## Whether the whole match stops for the big moments: hitstop on impact, a Surge's
## cut-in, a KO's freeze and slow motion. True with two on the field (1v1, a tag Duel, a
## Brawl of two). On a crowded field (a team match of 2 v 2 and up, a Brawl of three or
## four) nobody else should stutter for a hit across the map: hitstop is local to the two
## involved (`impact_stop`), a raw Surge winds up instead (SURGE_CROWD_WINDUP) and a KO
## freezes nobody. Fixed for the match by the mode (TeamSim, BrawlSim).
var freeze_all := true
var sink_ring := -1
## Sinkhole: the cells that stay floor once the cracked ring drops (empty: no warning).
var sink_safe := Rect2i()
## An objective on the floor (King of the Crater): where the zone is and its radius
## (0: none). Views draw it, the CPU goes for it.
var zone_pos := Vector2.ZERO
var zone_r := 0.0
## Where each creature's side wants it (set every tick by a mode's rules, Capture the
## Flag): per creature [] or [pos: Vector2, radius: float, urgent: bool]. The CPU heads
## for it when outside the radius, unless a foe is in reach (urgent: even then).
var goals: Array = []
## Match mutators (data/rules/mutators.json entries merged), fixed for the match.
var mutators := {}
## Training options (MatchFactory.training only): `training` is fixed when the match is
## built; `training_flags` ({"no_cooldowns": true, "full_energy": true}, missing = off)
## can change between ticks and is saved by snapshot(). Any other match refuses them.
var training := false:
	set(v):
		training = v and tick == 0 and creatures.is_empty()  # only while it's being built
var training_flags := {}
var creatures: Array[CreatureSim] = []
var projectiles: Array[Dictionary] = []
## Ground zones (Sno Mercy's Syrup Slick): {owner, pos, radius, ticks, slow_mult}. Foes of
## the owner standing in one are slowed.
var zones: Array[Dictionary] = []
## Storms (a lob's "storm" where it lands: Thousand Cranes): {owner, pos, radius, t,
## ticks, every, hit, end}. A pulse hits every foe inside each `every` ticks; at `ticks`
## the last one pushes them out (`end`: hit values) and cracks a ring of floor.
var storms: Array[Dictionary] = []
## Plants a missed lob left (a projectile "seed" block: Pinecone Bomb), stepped by
## Plants (plants.gd): {id, owner, team, pos, hp, hp_max, age, stage, apple, root, grow,
## apple_at, heal_share, radius, pick_radius}; `plant_seq` numbers them. Saved.
var plants: Array = []
var plant_seq := 0
var events: Array[Dictionary] = []
## Scratch, rebuilt at the start of every step from the creatures' state (so not saved):
## per creature 1 if it was in stealth as the tick began. `nearest_seen` reads it.
var hidden_at_step := PackedByteArray()
## The map's bridges ("bridges" in its JSON: {rect, strain, reform_seconds, crack}): per
## bridge [ticks until it stands again (0: standing), warned]. A heavy hit on someone
## standing on one cracks the floor under them (`crack` px, and the cell they're on a
## step further); once its cells' damage (cracked 1, hole 2) reaches `strain` the whole
## bridge falls into the river (its cells are shallows, waded across) until
## `reform_seconds` later, when it's whole again.
var bridges: Array = []
## The bridges' cells (from the map, fixed for the match).
var bridge_rects: Array[Rect2i] = []
## Arena hazards (a mutator's "hazards": Hazards in hazards.gd): each one's state
## ({id, phase, t, next, rng, side, front, done, puddles, dry, meteors}), and what they left
## on the floor to pick up ({pos, radius, until, kind, ticks, mult}). Saved. Their
## definitions (data/rules/hazards.json entries by id) are fixed for the match.
var hazards: Array = []
var hazard_pickups: Array = []
var hazard_defs := {}
## Shrines (a mode's "shrines" rules: Shrines in shrines.gd, stepped by the mode): per
## shrine [team claiming (-1), ticks claimed, ticks until ready, times claimed]. Saved
## (in the digest only when there are some). Where each one is ({pos, radius, kind}) and
## the merged rules are fixed for the match.
var shrines: Array = []
var shrine_spots: Array = []
var shrine_rules := {}
## The permanent-buff shrines' draws: an integer LCG seeded by the match seed (Shrines.setup).
var shrine_rng := 0
## Fighters a mode marks as wanted (Team Deathmatch's spree, the Brawl crown): one number
## per slot, the pixels of pull the CPU's target choice gives that foe (0: none). Empty in
## every other mode. Written by the mode each tick; saved (in the digest only when set).
var marks: Array = []


## Lays an arena map on the floor. Call before adding creatures (it resets the grid).
## A map with "size": [cols, rows] gets a grid that big (the stadium's 84 x 36 otherwise).
func set_arena(id: String) -> void:
	arena_id = id
	arena = ArenaMap.get_map(id)
	var sz := ArenaMap.size_of(arena)
	if sz != Vector2i(terrain.cols, terrain.rows):
		terrain = TerrainGrid.new(sz.x, sz.y)
	terrain.load_map(arena)
	bridges = []
	bridge_rects = ArenaMap.bridge_rects(arena)
	for b in arena.get("bridges", []):
		bridges.append([0, false])
	for c in creatures:
		c.floor_end = terrain.floor_rect().end


## The floor in world pixels (this map's size), and the whole stadium round it.
func floor_rect() -> Rect2:
	return terrain.floor_rect()


func arena_size() -> Vector2:
	return terrain.arena_size()


## Applies mutators (data/rules/mutators.json keys): per-fighter multipliers go on
## every creature, `surge_every` fills the meters on a timer, `pit_floor` sinks that
## share of the floor into chasms in a pattern from `seed_`, clear of the spawns,
## `hazards` switches on arena hazards (Hazards.setup: breakwaters rise, clear of everyone).
## Call once the creatures are in.
func apply_mutators(m: Dictionary, seed_: int) -> void:
	mutators = m.duplicate()
	for c in creatures:
		c.air_mult = float(m.get("air_mult", 1.0))
		c.speed_mult = float(m.get("speed_mult", 1.0))
		c.damage_mult = float(m.get("damage_mult", 1.0))
	var share := float(m.get("pit_floor", 0.0))
	if share > 0.0:
		var x := (seed_ * 1103515245 + 12345) & 0x7fffffff  # a small LCG: the same holes anywhere
		for cy in terrain.rows:
			for cx in terrain.cols:
				x = (x * 1103515245 + 12345) & 0x7fffffff
				if float(x % 1000) >= share * 1000.0:
					continue
				var c := Vector2i(cx, cy)
				var at := terrain.cell_center(c)
				var clear := true
				for side in 2:
					if at.distance_to(spawn(side)) < 48.0:
						clear = false
				if clear and terrain.get_cell(c) == TerrainGrid.INTACT:
					terrain.sink(c)
	var hz: Array = m.get("hazards", [])
	if not hz.is_empty():
		Hazards.setup(self, hz, seed_)


## Adds one mutators.json entry's keys to a merged set (`into`): a "hazards" list adds up
## with the ones already there; any other key replaces. "name" is skipped.
static func merge_mutator(into: Dictionary, entry: Dictionary) -> void:
	for k in entry:
		if k == "name":
			continue
		if k == "hazards":
			var list: Array = (into.get("hazards", []) as Array).duplicate()
			for h in entry[k]:
				if not (h in list):
					list.append(h)
			into["hazards"] = list
		else:
			into[k] = entry[k]


## Where a side's fighters start on this map.
func spawn(side: int) -> Vector2:
	return ArenaMap.spawn(arena, side)


## Whether any solid body stands on the cell (a rebuilding wall waits for it to leave).
func cell_occupied(c: Vector2i) -> bool:
	for o in creatures:
		if o.is_solid() and terrain.body_touches(o.pos, o.radius, c):
			return true
	return false


func add_creature(def: Dictionary, p: Vector2, is_dummy := false) -> CreatureSim:
	var c := CreatureSim.new(creatures.size(), def, p, is_dummy)
	c.floor_end = terrain.floor_rect().end
	creatures.append(c)
	return c


## Who gets the credit for knocking a fighter out, from this tick's events: `by[slot]` is the
## last fighter whose hit (a clean hit, a poison tick, a boulder it
## sent back with a heavy: Hazards) landed on that
## slot and `at[slot]` the tick it landed. Modes that score KOs per fighter (Team Deathmatch's
## spree, the Brawl crown) call it after each step and keep both arrays as their own state.
func note_credit(by: Array, at: Array) -> void:
	for e in events:
		var kind := String(e["type"])
		var who := -1
		var from := -1
		if kind == "hit" or kind == "block":
			who = int(e.get("target", -1))
			from = int(e.get("attacker", -1))
		elif kind == "poison" or kind == "hazard_hit":  # (a hazard's: only a boulder a heavy sent back has a `by`)
			who = int(e.get("who", -1))
			from = int(e.get("by", -1))
		if who >= 0 and who < by.size() and from >= 0 and from != who:
			by[who] = from
			at[who] = tick


## The fighter credited with knocking out `slot` (see note_credit): its last hitter, if that
## hit landed within `window` ticks; else -1 (a fall or a hazard with nobody's hit behind it).
static func credit_of(by: Array, at: Array, slot: int, now: int, window: int) -> int:
	if slot < 0 or slot >= by.size() or int(by[slot]) < 0:
		return -1
	return int(by[slot]) if now - int(at[slot]) <= window else -1


## Adds Surge energy (capped). The moment the meter fills it says so ("surge_ready"),
## for the aura and the sound; views read `energy` itself to keep the aura lit.
func gain_energy(c: CreatureSim, amount: float) -> void:
	var before := c.energy
	c.energy = minf(CreatureSim.MAX_ENERGY, c.energy + amount)
	if before < CreatureSim.MAX_ENERGY and c.energy >= CreatureSim.MAX_ENERGY:
		emit_event("surge_ready", c.pos, 0.0, {"who": c.id, "team": c.team})


func emit_event(kind: String, p: Vector2, power: float, extra := {}) -> void:
	var e := {"type": kind, "pos": p, "power": power, "tick": tick}
	e.merge(extra)
	events.append(e)
	if kind == "ko" and freeze_all and not training:  # (training: nobody stays down, so no freeze)
		var who := int(extra.get("who", -1))
		if who < 0 or who >= creatures.size() or not creatures[who].is_dummy:
			ko_freeze = maxi(ko_freeze, ko_freeze_ticks)
			slowmo = maxi(slowmo, ko_slowmo_ticks)


## Freeze-frame on impact for `ticks`. With two on the field the whole match stops
## (`hitstop`); on a crowded one only the attacker and the target do (their own
## `CreatureSim.hitstop`), and a ranged hit (a shot, a storm, a zone) only the target.
func impact_stop(a: CreatureSim, d: CreatureSim, ticks: int, ranged := false) -> void:
	if freeze_all:
		hitstop = maxi(hitstop, ticks)
		return
	d.hitstop = maxi(d.hitstop, ticks)
	if not ranged:
		a.hitstop = maxi(a.hitstop, ticks)


func step(inputs: PackedInt32Array) -> void:
	events.clear()
	tick += 1
	if ko_freeze > 0:
		ko_freeze -= 1
		_buffer_all(inputs)
		return
	if slowmo > 0:
		slowmo -= 1
		if slowmo % 2 == 1:
			_buffer_all(inputs)
			return
	if hitstop > 0:
		# Freeze-frame on impact: nothing moves, but presses are buffered.
		hitstop -= 1
		for i in creatures.size():
			creatures[i].buffer_input(_input(inputs, i), self)
		return
	terrain.tick(cell_occupied)
	var every := int(mutators.get("surge_every", 0))
	if every > 0 and tick % every == 0:
		for c in creatures:  # Surge rush: everyone's meter fills
			gain_energy(c, CreatureSim.MAX_ENERGY)
	hidden_at_step.resize(creatures.size())
	for i in creatures.size():
		hidden_at_step[i] = 1 if creatures[i].stealth > 0 else 0
	for i in creatures.size():
		var c := creatures[i]
		if c.hitstop > 0:
			# Its own freeze-frame (a crowded field): it holds while the match goes on.
			c.hitstop -= 1
			c.buffer_input(_input(inputs, i), self)
		else:
			c.step(_input(inputs, i), self)
	_step_swallows()
	_step_projectiles()
	_step_zones()
	_step_storms()
	if not plants.is_empty():
		Plants.step(self)
	_resolve_hits()
	if not hazards.is_empty():
		Hazards.step(self)
	_separate()
	_unstick()
	_check_falls()
	if not bridges.is_empty():
		_step_bridges()
	if training and not training_flags.is_empty():
		_apply_training()


## The training options this match is played with (TRAINING_FLAGS keys; anything else is
## dropped). Returns false, changing nothing, unless MatchFactory.training built it, so a
## versus, team, duel or online match can never have them.
func set_training_flags(flags: Dictionary) -> bool:
	if not training:
		return false
	var out := {}
	for k in TRAINING_FLAGS:
		if bool(flags.get(k, false)):
			out[k] = true
	training_flags = out
	return true


## After every tick of a training match, for the player (every creature that isn't the
## dummy): no_cooldowns readies every move and the dodge and fills the stamina (most
## dodges are gated by stamina); full_energy keeps the Surge meter full.
func _apply_training() -> void:
	var ready := bool(training_flags.get("no_cooldowns", false))
	var full := bool(training_flags.get("full_energy", false))
	for c in creatures:
		if c.is_dummy:
			continue
		if ready:
			for k in c.cooldowns.keys():
				c.cooldowns[k] = 0
			c.stamina = c.max_stamina
			c.regen_wait = 0
		if full:
			c.energy = CreatureSim.MAX_ENERGY


func _buffer_all(inputs: PackedInt32Array) -> void:
	for i in creatures.size():
		creatures[i].buffer_input(_input(inputs, i), self)


func nearest_opponent(c: CreatureSim) -> CreatureSim:
	var best: CreatureSim = null
	var best_d := INF
	for o in creatures:
		if not c.is_foe(o) or o.state == CreatureSim.State.KO:
			continue
		var d := o.pos.distance_squared_to(c.pos)
		if d < best_d:
			best_d = d
			best = o
	return best


## The nearest foe `c` can see, for the guard's facing: like `nearest_opponent`, but a foe
## in stealth (Tiptoe, a hidden Burrow) doesn't count. Who's hidden is read as it was at the
## start of the tick (`hidden_at_step`), so a foe whose strike gives it away this tick is
## faced the next tick whichever of the two steps first. A foe in brush (`covered`) still
## counts: the ground hides it, not a skill. Null when every foe is down or hidden.
func nearest_seen(c: CreatureSim) -> CreatureSim:
	var best: CreatureSim = null
	var best_d := INF
	var known := hidden_at_step.size() == creatures.size()
	for i in creatures.size():
		var o := creatures[i]
		if not c.is_foe(o) or o.state == CreatureSim.State.KO:
			continue
		if (hidden_at_step[i] != 0) if known else (o.stealth > 0):
			continue
		var d := o.pos.distance_squared_to(c.pos)
		if d < best_d:
			best_d = d
			best = o
	return best


## Everything that changes during a match, for rollback netcode: restore(snapshot())
## puts the match back exactly as it was. Creature definitions aren't copied (they
## never change), and events aren't either (they're rebuilt every step).
func snapshot() -> Dictionary:
	var cs: Array = []
	for c in creatures:
		cs.append(c.save_state())
	return {
		"tick": tick, "hitstop": hitstop, "ko_freeze": ko_freeze, "slowmo": slowmo, "sink_ring": sink_ring, "sink_safe": sink_safe,
		"zone_pos": zone_pos, "zone_r": zone_r, "goals": goals.duplicate(true),
		"cells": terrain.cells.duplicate(), "timers": terrain.timers.duplicate(), "base": terrain.base.duplicate(),
		"terrain_version": terrain.version,
		"creatures": cs, "projectiles": projectiles.duplicate(true), "zones": zones.duplicate(true),
		"storms": storms.duplicate(true), "training_flags": training_flags.duplicate(),
		"bridges": bridges.duplicate(true),
		"hazards": hazards.duplicate(true), "hazard_pickups": hazard_pickups.duplicate(true),
		"shrines": shrines.duplicate(true), "shrine_rng": shrine_rng, "marks": marks.duplicate(),
		"plants": plants.duplicate(true), "plant_seq": plant_seq,
	}


func restore(s: Dictionary) -> void:
	tick = int(s["tick"])
	hitstop = int(s["hitstop"])
	ko_freeze = int(s["ko_freeze"])
	slowmo = int(s["slowmo"])
	sink_ring = int(s.get("sink_ring", -1))
	sink_safe = s.get("sink_safe", Rect2i())
	zone_pos = s.get("zone_pos", Vector2.ZERO)
	zone_r = float(s.get("zone_r", 0.0))
	goals = (s.get("goals", []) as Array).duplicate(true)
	terrain.cells = PackedByteArray(s["cells"]).duplicate()
	terrain.timers = PackedInt32Array(s["timers"]).duplicate()
	if s.has("base"):
		terrain.base = PackedByteArray(s["base"]).duplicate()
	terrain.version = maxi(terrain.version, int(s["terrain_version"])) + 1  # forces a redraw
	var cs: Array = s["creatures"]
	for i in creatures.size():
		creatures[i].load_state(cs[i])
	projectiles.assign((s["projectiles"] as Array).duplicate(true))
	zones.assign((s.get("zones", []) as Array).duplicate(true))
	storms.assign((s.get("storms", []) as Array).duplicate(true))
	training_flags = (s.get("training_flags", {}) as Dictionary).duplicate()
	bridges = (s.get("bridges", []) as Array).duplicate(true)
	hazards = (s.get("hazards", []) as Array).duplicate(true)
	hazard_pickups = (s.get("hazard_pickups", []) as Array).duplicate(true)
	shrines = (s.get("shrines", []) as Array).duplicate(true)
	shrine_rng = int(s.get("shrine_rng", 0))
	marks = (s.get("marks", []) as Array).duplicate()
	plants = (s.get("plants", []) as Array).duplicate(true)
	plant_seq = int(s.get("plant_seq", 0))
	events.clear()


## An exact fingerprint of the match state (SHA-256 of its bytes). Floats are hashed
## bit for bit, so two machines only agree if they computed identical results; this
## is what online play checks to catch desyncs.
func state_digest() -> String:
	var parts: Array = [tick, hitstop, ko_freeze, slowmo, arena_id, sink_ring, sink_safe, zone_pos, zone_r, goals, terrain.cells, terrain.timers, terrain.base]
	for c in creatures:
		var st := c.save_state()
		for f in CreatureSim.STATE_FIELDS:
			parts.append(st[f])
	for p in projectiles:
		parts.append_array([p["pos"], p["vel"], p["life"], p["owner"], p["serial"]])
	for z in zones:
		parts.append_array([z["pos"], z["radius"], z["ticks"], z["owner"], z["slow_mult"]])
	for st in storms:
		parts.append_array([st["pos"], st["radius"], st["t"], st["ticks"], st["owner"]])
	for p in projectiles:
		if p.has("home"):
			parts.append_array([p["home"]["stop"], p["speed"]])
	if not bridges.is_empty():  # (only maps with bridges)
		parts.append(bridges)
	if not hazards.is_empty():  # (only matches with hazards: every other fingerprint is unchanged)
		parts.append_array([hazards, hazard_pickups])
	if not shrines.is_empty():  # (only matches with shrines, so every other fingerprint is unchanged)
		parts.append_array([shrines, shrine_rng])
		for c in creatures:
			for f in CreatureSim.BOOST_FIELDS:
				parts.append(c.get(f))
	if not marks.is_empty():  # (only modes that mark someone)
		parts.append(marks)
	if not plants.is_empty() or plant_seq > 0:  # (only once a seed has been planted)
		parts.append(plant_seq)
		for pl in plants:
			parts.append_array([pl["id"], pl["owner"], pl["pos"], pl["hp"], pl["age"], pl["stage"], pl["apple"]])
	if training:  # (only training matches: every other match's fingerprint is unchanged)
		for k in TRAINING_FLAGS:
			parts.append(bool(training_flags.get(k, false)))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(parts))
	return ctx.finish().hex_encode()


## A short form of state_digest(), used by the determinism and replay tests.
func state_hash() -> int:
	return hash(state_digest())


static func _input(inputs: PackedInt32Array, i: int) -> int:
	return inputs[i] if i < inputs.size() else 0


# ------------------------------------------------------------------ hits

## Whether `d` can be struck by a hit with these parameters right now.
func _hittable(d: CreatureSim, hit: Dictionary) -> bool:
	if not d.can_be_hit():
		return false
	if d.is_airborne():
		# A grab can't snag a target in the air, unless it's a "grab_air" one (Branch Grab).
		if not bool(hit["juggle"]) or (bool(hit["grab"]) and not bool(hit.get("grab_air", false))):
			return false
		# Each juggle move uses one of the target's juggle points; extra hits of the same
		# move are free, so multi-hit moves aren't cut short.
		var key := "%d:%d" % [int(hit["attacker"]), int(hit["serial"])]
		if d.juggles >= CreatureSim.JUGGLE_MAX and not d.juggle_serials.has(key):
			return false
	return true


func _resolve_hits() -> void:
	for a in creatures:
		var seg := a.active_seg()
		if seg < 0:
			continue
		var center := a.hit_center(seg)
		var reach := a.hit_radius(seg)
		var skip_struck := a.seg_flag(seg, "skip_struck")
		if not plants.is_empty():
			# A swing also strikes the other side's sprouts it covers, once per segment.
			var pkey := "p:%d" % seg
			if not a.seg_hit.has(pkey):
				var struck: Array = []
				if Plants.strike(self, a, center, reach, a.seg_value(seg, "damage"), struck) > 0:
					a.seg_hit[pkey] = true
		for d in creatures:
			if not a.is_foe(d):
				continue
			var key := "%d:%d" % [d.id, seg]
			if a.seg_hit.has(key):
				continue
			# "skip_struck": this segment passes over a foe an earlier segment already hit.
			if skip_struck and a.struck_before(d.id, seg):
				continue
			var hit := a.hit_params(seg)
			if not _hittable(d, hit):
				continue
			if center.distance_to(d.pos) > reach + d.radius:
				continue
			# A cone (Shaved Ice Spray): only foes in front of the attacker.
			if float(hit.get("cone", 0.0)) > 0.0:
				var to := d.pos - a.pos
				if to.length_squared() > 0.0001 and a.facing.dot(to.normalized()) < float(hit["cone"]):
					continue
			a.seg_hit[key] = true
			var push := d.pos - a.pos
			push = push.normalized() if push.length_squared() > 0.0001 else a.facing
			_apply_hit(a, d, hit, push, (center + d.pos) * 0.5 + Vector2(0, -12))


## The energy rules (data/rules/energy.json), loaded once: per_damage_dealt,
## per_type_mult, variety_energy, per_damage_taken, carry_between_rounds. Missing keys fall
## back to the constants (per_type_mult and variety_energy to 1.0: every hit alike).
static func energy_rules() -> Dictionary:
	if _energy_rules.is_empty():
		var f := FileAccess.open(ENERGY_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_energy_rules = d if d is Dictionary else {}
	return _energy_rules


static func energy_rate_dealt() -> float:
	return float(energy_rules().get("per_damage_dealt", ENERGY_PER_DAMAGE))


## The Surge energy `amount` of damage from a hit of `hit_type` on `d` earns its attacker:
## amount × per_damage_dealt × per_type_mult[hit_type] × variety_energy[types], where types
## is how many move types the combo on `d` has used counting this hit (d.combo_types). A
## Surge's own hits earn nothing. Used for clean hits, blocked chip and armor chip alike.
static func energy_dealt(d: CreatureSim, hit_type: String, amount: float) -> float:
	if hit_type == "surge":  # a Surge never charges the next one
		return 0.0
	var r := energy_rules()
	var mult := float((r.get("per_type_mult", {}) as Dictionary).get(hit_type, 1.0))
	var table: Array = r.get("variety_energy", [])
	var v := 1.0
	if not table.is_empty():
		var n := SimDefs.type_count(d.combo_types | int(SimDefs.TYPE_BIT.get(hit_type, 0)))
		v = float(table[mini(n, table.size() - 1)])
	return amount * energy_rate_dealt() * mult * v


static func energy_rate_taken() -> float:
	return float(energy_rules().get("per_damage_taken", ENERGY_PER_DAMAGE_TAKEN))


static func energy_carries() -> bool:
	return bool(energy_rules().get("carry_between_rounds", false))


static func projectile_radius_mult() -> float:
	if _projectile_rules.is_empty():
		var f := FileAccess.open(PROJECTILES_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_projectile_rules = d if d is Dictionary else {}
	return float(_projectile_rules.get("radius_mult", 1.0))


## The stamina a blocked hit costs `d`: damage × its guard's drain_per_damage × the
## move type's block_drain_mult (data/rules/stamina.json: lights drain less, heavies more).
static func block_drain(d: CreatureSim, hit_type: String, damage: float) -> float:
	var mult: Dictionary = CreatureSim.stamina_rules().get("block_drain_mult", {})
	return damage * float(d.def["guard"]["drain_per_damage"]) * float(mult.get(hit_type, 1.0))


## Lifesteal (Sneaky Pete's Five-Finger Discount): the attacker heals its "lifesteal" share
## of the health its hit took, up to max HP.
func _lifesteal(a: CreatureSim, dealt: float) -> void:
	var share := float(a.def.get("lifesteal", 0.0))
	if share > 0.0 and dealt > 0.0 and a.state != CreatureSim.State.KO:
		a.hp = minf(a.max_hp, a.hp + dealt * share)


## Resolves one hit: Slip counters, guarding, then damage with the combo rules.
## Returns "slip", "block" or "hit".
## `ranged`: the hit came from a projectile or a lob, not a strike in reach.
func _apply_hit(a: CreatureSim, d: CreatureSim, hit: Dictionary, push: Vector2, fx_pos: Vector2,
		ranged := false) -> String:
	# Blinded when the attack started (Headlamp Flash): it misses.
	if a.whiff_serial > 0 and int(hit["serial"]) == a.whiff_serial:
		emit_event("miss", fx_pos, 0.0, {"who": a.id, "target": d.id})
		return "miss"
	var same_attack := a.attack_serial == int(hit["serial"]) and a.state == CreatureSim.State.ATTACK
	var hooked := false

	# Slip: a strike inside the counter window is dodged and answered. Grabs beat it.
	if not bool(hit["grab"]) and d.in_counter_window():
		d.trigger_counter(a.pos, self)
		return "slip"

	var damage := float(hit["damage"])
	if a.atk_buff > 0:
		damage *= a.atk_mult  # Pickpocket: stolen power, or power stolen
	if a.boost_dmg != 1.0:
		damage *= a.boost_dmg  # the Crater shrine's permanent buff
	if d.vuln > 0:
		damage *= d.vuln_mult  # tenderized: every hit lands harder, armor chip included
	if (a.ambush_serial > 0 and int(hit["serial"]) == a.ambush_serial) or a.ambush_t > 0:
		damage *= float(a.def.get("ambush", 1.0))  # a sneak attack out of stealth, and its opening string
	var gd: Dictionary = d.def["guard"]

	# Armor (Bedrock): the hit only chips, and the target doesn't flinch or move.
	if d.is_armored() and not bool(hit["grab"]):
		var ar: Dictionary = d.move_def()["armor"]
		var taken := d.take_damage(damage * (1.0 - float(ar.get("reduction", 0.6))), self)
		a.dealt_damage()
		_lifesteal(a, taken)
		d.flash = 3
		gain_energy(a, energy_dealt(d, String(hit["type"]), taken))
		if same_attack:
			a.connected = true
		impact_stop(a, d, int(float(hit["hitstop"]) * 0.6), ranged)
		emit_event("armor", fx_pos, taken, {"attacker": a.id, "target": d.id, "move_type": String(hit["type"])})
		d.check_ko(self)
		return "armor"

	if d.state == CreatureSim.State.GUARD and not bool(hit["grab"]):
		var facing_attacker := d.facing.dot(-push) > 0.3
		var drain := block_drain(d, String(hit["type"]), damage)
		if facing_attacker and not bool(hit["guard_break"]) and d.stamina - drain <= 0.0:
			# Out of stamina: the guard drops and this hit lands clean, with nothing extra
			# (no guard-break stagger). Exhausted, it can't guard again until regen.
			d.spend_stamina(d.stamina)
			d.drop_guard()
			emit_event("guard_break", d.pos, 1.0, {"who": d.id, "drained": true})
		elif facing_attacker and not bool(hit["guard_break"]):
			# Blocked with stamina to spare: no health lost (no chip), the guard pays in stamina.
			# It still counts as combat for both (Stoneskin's calm timer).
			d.calm_t = 0
			a.dealt_damage()
			d.spend_stamina(drain)
			d.pause_regen_for_block()
			d.knock_vel = push * float(hit["knockback"]) * 0.4 / d.weight
			d.guard_hit = 10
			d.stun = int(float(hit["hitstun"]) * 0.5)
			if same_attack:
				a.connected = true
				_punish_blocked_ender(a, d)
			if bool(hit.get("root_through_guard", false)) and float(hit.get("root_ticks", 0.0)) > 0.0:
				# The roots take hold through a guard (Root Eruption): only the damage is blocked.
				d.root = maxi(d.root, int(hit["root_ticks"]))
				emit_event("rooted", d.pos, float(hit["root_ticks"]), {"who": d.id, "by": a.id, "blocked": true})
			impact_stop(a, d, int(float(hit["hitstop"]) * 0.5), ranged)
			emit_event("block", fx_pos, damage, {"attacker": a.id, "target": d.id, "move_type": String(hit["type"]),
				"dealt": 0.0})
			return "block"
	var broke_guard := false
	if d.state == CreatureSim.State.GUARD and not bool(hit["grab"]) and bool(hit["guard_break"]) \
			and d.facing.dot(-push) > 0.3:
		broke_guard = true
		emit_event("guard_break", d.pos, 1.0, {"who": d.id})

	# --- a clean hit
	# A statue (Petrify Punch) shatters on the next clean hit, which lands harder.
	if d.stone > 0:
		damage *= STONE_SHATTER_MULT
		d.stone = 0
		emit_event("shatter", d.pos, damage, {"who": d.id, "by": a.id, "ice": d.stone_ice})
	# A hit that doesn't stagger (Chef Cerebro's knife flicks): damage only. On a foe who
	# isn't already stunned it doesn't start a combo either. Unless it names a mark the
	# target carries ("stagger_if": a tenderized foe staggers under the Mallet Toss): set
	# up, then it lands as an ordinary hit.
	var no_flinch := bool(hit.get("no_flinch", false))
	var paid_off := false
	if no_flinch and d.has_mark(String(hit.get("stagger_if", ""))):
		no_flinch = false
		paid_off = true
	# Out of an ambush ("ambush_flinch": Digby, Pete): while the window is open his jabs
	# stagger like ordinary lights, so the opener from stealth starts a real combo.
	if no_flinch and a.ambush_t > 0 and bool(a.def.get("ambush_flinch", false)) and String(hit["type"]) == "light":
		no_flinch = false
	var was_stunned := d.is_stunned()
	var n := d.combo_hits + 1
	var types := d.combo_types | int(SimDefs.TYPE_BIT[String(hit["type"])])
	var variety := SimDefs.variety_mult(types)
	var move_key := "%d:%s" % [a.id, String(hit["move_id"])]
	var stale := 1.0
	if d.combo_moves.has(move_key) and int(d.combo_moves[move_key]) != int(hit["serial"]):
		stale = STALE_MULT

	var bonus := 0.0
	if float(hit["stack_bonus"]) > 0.0 and a.stack > 0:
		bonus = a.stack * float(hit["stack_bonus"])
		a.stack = 0
	var total := (damage + bonus) * variety * stale
	var stun := int(round(float(hit["hitstun"]) * maxf(HITSTUN_FLOOR, 1.0 - HITSTUN_DECAY * (n - 1)) * stale))

	var dealt := d.take_damage(total, self)
	_lifesteal(a, dealt)
	a.dealt_damage()
	d.flash = 6
	if float(hit.get("slow_ticks", 0.0)) > 0.0:
		d.slow = maxi(d.slow, int(hit["slow_ticks"]))
		d.slow_mult = float(hit["slow_mult"])
		emit_event("slow", d.pos, float(hit["slow_ticks"]), {"who": d.id})
	d.combo_hits = n
	d.combo_types = types
	d.combo_moves[move_key] = int(hit["serial"])
	d.combo_damage += total
	d.last_attacker = a.id
	gain_energy(a, energy_dealt(d, String(hit["type"]), total))  # d.combo_types includes this hit
	gain_energy(d, total * energy_rate_taken())
	if same_attack:
		a.connected = true
	var stack_def: Dictionary = a.def.get("stack", {})
	if String(hit["type"]) == "light" and not stack_def.is_empty():
		a.stack = mini(a.stack + 1, int(stack_def["max"]))
		a.stack_t = int(stack_def["timeout"])

	var kb := push * float(hit["knockback"]) / d.weight
	var was_air := d.is_airborne()
	# A "grab_air" grab (Branch Grab) only gets past guard, armor and counters like a grab;
	# otherwise it lands like any hit: hitstun, its own pull, and a juggle in the air.
	var grabbed := bool(hit["grab"]) and not bool(hit.get("grab_air", false))
	if was_air:
		var jkey := "%d:%d" % [a.id, int(hit["serial"])]
		if not d.juggle_serials.has(jkey):
			d.juggle_serials[jkey] = true
			d.juggles += 1

	_venom_frenzy(a, d)
	if float(hit.get("poison_ticks", 0.0)) > 0.0:
		d.poison = maxi(d.poison, int(hit["poison_ticks"]))
		# hit_params fills every key (0 when the move leaves it out), so the default
		# has to be applied here, not in get().
		var every := int(hit.get("poison_every", 0))
		d.poison_every = every if every > 0 else POISON_EVERY_DEFAULT
		d.poison_dmg = float(hit["poison_damage"])
		d.poison_by = a.id
		d.poison_look = String(hit.get("poison_look", ""))
		emit_event("poisoned", d.pos, float(hit["poison_ticks"]), {"who": d.id, "by": a.id, "look": d.poison_look})

	if d.stealth > 0 and not (no_flinch and ranged):
		d.stealth = 0  # caught: visible again (a thrown knife flick that doesn't stagger isn't enough)
		emit_event("unstealth", d.pos, 0.0, {"who": d.id})
	if float(hit.get("steal_ticks", 0.0)) > 0.0:
		var st := float(hit["steal"])
		a.atk_buff = int(hit["steal_ticks"])
		a.atk_mult = 1.0 + st
		d.atk_buff = int(hit["steal_ticks"])
		d.atk_mult = 1.0 - st
		emit_event("steal", d.pos, st, {"who": d.id, "by": a.id})
	if float(hit.get("blind_ticks", 0.0)) > 0.0:
		d.blind = maxi(d.blind, int(hit["blind_ticks"]))
		emit_event("blinded", d.pos, float(hit["blind_ticks"]), {"who": d.id, "by": a.id})
	if float(hit.get("root_ticks", 0.0)) > 0.0:
		d.root = maxi(d.root, int(hit["root_ticks"]))
		emit_event("rooted", d.pos, float(hit["root_ticks"]), {"who": d.id, "by": a.id})

	if float(hit.get("vuln_ticks", 0.0)) > 0.0:
		d.vuln = maxi(d.vuln, int(hit["vuln_ticks"]))
		d.vuln_mult = float(hit["vuln_mult"])
		emit_event("tenderized", d.pos, float(hit["vuln_ticks"]), {"who": d.id})

	if no_flinch and (d.is_winding_up() or d.is_folding()) and not ranged:
		# A jab doesn't stagger, but it still beats a big move's windup (and a fold, still
		# in his hands): hitting first stays a counter to the red and gold tells. Thrown
		# flicks don't.
		d.enter_hitstun(int(hit["hitstun"]), Vector2.ZERO)
	elif no_flinch:
		if not was_stunned:
			d.reset_combo()
	elif float(hit.get("petrify", 0.0)) > 0.0 or float(hit.get("freeze_ticks", 0.0)) > 0.0:
		# Turned to stone, or frozen solid in ice: stunned where it stands (even out of
		# the air), until it wears off or the next clean hit shatters it.
		var ice := float(hit.get("freeze_ticks", 0.0)) > 0.0
		var ticks := int(hit["freeze_ticks"]) if ice else int(hit["petrify"])
		d.enter_crumple(ticks, kb * 0.3)
		d.stone = ticks
		d.stone_ice = ice
		emit_event("freeze" if ice else "petrify", d.pos, total, {"who": d.id, "by": a.id})
	elif grabbed and float(hit.get("swallow", 0.0)) > 0.0:
		_swallow(a, d, hit)
		emit_event("swallow", a.pos + Vector2(0, -16), total, {"attacker": a.id, "target": d.id})
	elif grabbed and float(hit.get("flip", 0.0)) > 0.0:
		_flip(a, d, hit)
		emit_event("grab", a.pos + Vector2(0, -20), total, {"attacker": a.id, "target": d.id, "flip": true})
	elif grabbed and float(hit.get("pull", 0.0)) > 0.0:
		# A hook (Culvert's tongue, tapped): the target is stunned and hauled in to him.
		hooked = true
		d.enter_hitstun(stun, Vector2.ZERO)
		emit_event("hook", d.pos + Vector2(0, -12), total, {"attacker": a.id, "target": d.id})
	elif grabbed:
		# Swallow and spit out behind the attacker.
		d.pos = a.pos - a.facing * (a.radius + d.radius + 6.0)
		d.clamp_to_floor()
		d.enter_knockdown(int(hit["knockdown"]), -a.facing * 1.5)
		emit_event("grab", a.pos + Vector2(0, -20), total, {"attacker": a.id, "target": d.id})
	elif float(hit["knockdown"]) > 0.0:
		d.enter_knockdown(int(hit["knockdown"]), kb)
	elif float(hit["launch"]) > 0.0:
		if was_air:
			d.extend_air(int(hit["launch"]), kb * 0.5)
		else:
			d.enter_air(int(hit["launch"]), kb * 0.5)
	elif was_air:
		var float_t := int(hit.get("juggle_float", 0.0))
		d.extend_air(float_t if float_t > 0 else CreatureSim.JUGGLE_FLOAT, kb * 0.5)
	elif float(hit["crumple"]) > 0.0:
		d.enter_crumple(int(hit["crumple"]), kb)
	elif broke_guard:
		d.enter_crumple(maxi(stun, int(gd["break_stun"])), kb)
	else:
		d.enter_hitstun(stun, kb)

	# A pull (Branch Grab) reels the target in until it stops `pull` pixels short of the
	# attacker's body. Knockback slows by a fixed factor each tick, so the starting speed
	# that covers a distance is that distance times (1 - friction).
	var pull := float(hit.get("pull", 0.0))
	if pull > 0.0 and (hooked or not grabbed) and d.pos.distance_squared_to(a.pos) > 0.0001:
		var gap := d.pos.distance_to(a.pos) - (a.radius + d.radius + pull)
		var fr := CreatureSim.AIR_FRICTION if d.is_airborne() else CreatureSim.FRICTION
		d.knock_vel = (a.pos - d.pos).normalized() * maxf(0.0, gap) * (1.0 - fr)
		if not hooked:  # a hook has its own event (the tongue snapping back)
			emit_event("pull", d.pos, gap, {"attacker": a.id, "target": d.id})
	# A reel (Cast Line) is the other way round: the attacker is hauled in to the target.
	var reel := float(hit.get("reel", 0.0))
	if reel > 0.0 and same_attack and d.pos.distance_squared_to(a.pos) > 0.0001:
		var gap := d.pos.distance_to(a.pos) - (a.radius + d.radius + reel)
		var reel_speed := float(hit.get("reel_speed", 0.0))
		a.start_reel(d, reel, reel_speed if reel_speed > 0.0 else REEL_SPEED_DEFAULT)
		emit_event("reel", a.pos, gap, {"attacker": a.id, "target": d.id})

	impact_stop(a, d, int(hit["hitstop"]), ranged)
	emit_event("hit", fx_pos, total, {
		"attacker": a.id, "target": d.id, "move_type": String(hit["type"]), "dealt": dealt,
		"combo": n, "variety": variety, "stale": stale < 1.0,
		"heavy": String(hit["type"]) != "light", "no_flinch": no_flinch, "stagger_if": paid_off})
	d.check_ko(self)
	return "hit"


## Flip Out: the target is scooped up and carried in an arc over the attacker's head,
## landing `flip` pixels behind its body, and the attacker turns to face where it lands.
## The carry takes the first half of the launch; it hangs there for the rest.
func _flip(a: CreatureSim, d: CreatureSim, hit: Dictionary) -> void:
	var behind := a.pos - a.facing * (a.radius + d.radius + float(hit["flip"]))
	behind = behind.clamp(d.floor_min(), d.floor_max())
	var ticks := maxi(int(hit["launch"]), 2)
	d.enter_air(ticks, Vector2.ZERO)
	d.start_flip(behind, ticks / 2)
	a.facing = -a.facing


## Venom Frenzy (creature key "venom_frenzy", Hissy Fitz's passive): landing `at_hits`
## clean hits in one string (each within `streak_gap` ticks of the last; jabs count)
## sends her into a frenzy for `ticks`; meanwhile each clean hit adds a stack of poison
## (up to `max_stacks`, each `poison_damage` a pulse every `poison_every` ticks), and
## the poison lasts `poison_ticks` from the latest hit. Another string of `at_hits`
## starts it over.
func _venom_frenzy(a: CreatureSim, d: CreatureSim) -> void:
	var vf: Dictionary = a.def.get("venom_frenzy", {})
	if vf.is_empty():
		return
	if a.frenzy_t > 0:
		if d.poison <= 0:
			d.poison_stacks = 0
			d.poison_dmg = 0.0
		d.poison_stacks = mini(d.poison_stacks + 1, int(vf.get("max_stacks", 5)))
		d.poison_stack_dmg = float(vf.get("poison_damage", 1.0))
		d.poison = maxi(d.poison, int(vf.get("poison_ticks", 180)))
		d.poison_every = int(vf.get("poison_every", POISON_EVERY_DEFAULT))
		d.poison_by = a.id
		emit_event("poisoned", d.pos, float(d.poison), {"who": d.id, "by": a.id, "stacks": d.poison_stacks})
	if a.streak_t <= 0:
		a.hit_streak = 0
	a.hit_streak += 1
	a.streak_t = int(vf.get("streak_gap", 45))
	if a.hit_streak >= int(vf.get("at_hits", 4)):
		a.hit_streak = 0
		a.frenzy_t = int(vf.get("ticks", 300))
		emit_event("frenzy", a.pos + Vector2(0, -20), float(a.frenzy_t), {"who": a.id})


## Gulp, held: the target is slurped in and carried inside the attacker for `swallow`
## ticks (hidden, untouchable, not solid), then pushed out behind him (`_poop`).
func _swallow(a: CreatureSim, d: CreatureSim, hit: Dictionary) -> void:
	var ticks := maxi(int(hit["swallow"]), 1)
	var air := maxi(int(hit["launch"]), 2)
	d.enter_air(ticks + air, Vector2.ZERO)  # stunned throughout; re-launched on the way out
	d.pos = a.pos
	d.swallow_t = ticks
	d.swallow_by = a.id
	d.swallow_gap = float(hit.get("flip", 0.0))
	d.swallow_air = air
	d.invuln = maxi(d.invuln, ticks + 1)


## Swallowed creatures ride inside their swallower; when the time is up they come out
## the back end, `swallow_gap` px behind him, hopping away from him.
func _step_swallows() -> void:
	for d in creatures:
		if d.swallow_t <= 0:
			continue
		var a := creatures[d.swallow_by]
		d.swallow_t -= 1
		d.pos = a.pos
		d.knock_vel = Vector2.ZERO
		if d.swallow_t == 0:
			_poop(a, d)


const POOP_SPEED := 2.2  ## how fast the swallowed creature slides out behind (px/tick)

func _poop(a: CreatureSim, d: CreatureSim) -> void:
	var behind := a.pos - a.facing * (a.radius + d.radius + d.swallow_gap)
	d.pos = behind.clamp(d.floor_min(), d.floor_max())
	d.swallow_by = -1
	if d.state != CreatureSim.State.KO:
		d.enter_air(d.swallow_air, -a.facing * POOP_SPEED)
	emit_event("poop", d.pos, 1.0, {"attacker": a.id, "target": d.id})


## Guard + Dodge while stunned: spend energy to escape the combo.
func breakaway(d: CreatureSim) -> void:
	d.energy -= CreatureSim.BREAKAWAY_COST
	var away := -d.facing
	var a: CreatureSim = null
	if d.last_attacker >= 0 and d.last_attacker < creatures.size():
		a = creatures[d.last_attacker]
		if a.pos.distance_squared_to(d.pos) > 0.0001:
			away = (d.pos - a.pos).normalized()
	d.reset_combo()
	d.stun = 0
	d.cancel_attack()
	d._set_state(CreatureSim.State.IDLE)
	d.invuln = CreatureSim.BREAKAWAY_INVULN
	d.knock_vel = away * 3.2
	if a != null and a.state == CreatureSim.State.ATTACK:
		a.cancel_attack()
		a._set_state(CreatureSim.State.IDLE)
		a.knock_vel = -away * 2.4
	emit_event("breakaway", d.pos + Vector2(0, -16), 1.0, {"who": d.id})


## A blocked third light (or later) leaves the attacker open: no cancelling out of it into
## a skill, and enough extra recovery that the blocker is free BLOCKED_ENDER_DISADVANTAGE
## ticks before the attacker is. (Chaining on to a fourth light is still allowed.)
func _punish_blocked_ender(a: CreatureSim, d: CreatureSim) -> void:
	var mv := a.move_def()
	if not a.move_id.begins_with("light_") or int(a.move_id.substr(6)) < 3:
		return
	a.punish_serial = a.attack_serial
	var left := int(mv["length"]) - a.state_t
	a.block_lag = maxi(a.block_lag, d.stun + BLOCKED_ENDER_DISADVANTAGE - left)
	emit_event("punishable", a.pos, float(a.block_lag), {"who": a.id})


# ------------------------------------------------------------------ zones

## Leaves a zone on the floor (a move's "zone": {radius, ticks, slow_mult}).
func add_zone(owner: CreatureSim, at: Vector2, z: Dictionary) -> void:
	zones.append({"owner": owner.id, "pos": at, "radius": float(z.get("radius", 32)),
		"ticks": int(z.get("ticks", 240)), "slow_mult": float(z.get("slow_mult", 0.5))})
	emit_event("zone", at, float(z.get("radius", 32)), {"who": owner.id})


## Zones wear off; foes standing in one are slowed while they do (and a moment after).
func _step_zones() -> void:
	var keep: Array[Dictionary] = []
	for z in zones:
		z["ticks"] = int(z["ticks"]) - 1
		if int(z["ticks"]) <= 0:
			continue
		keep.append(z)
		var at: Vector2 = z["pos"]
		for c in creatures:
			if not creatures[int(z["owner"])].is_foe(c) or c.state == CreatureSim.State.KO or c.state == CreatureSim.State.FALLING \
					or c.is_airborne():
				continue
			if c.pos.distance_to(at) > float(z["radius"]):
				continue
			var m := c.slow_mult if c.slow > 0 else 1.0
			c.slow_mult = minf(m, float(z["slow_mult"]))
			c.slow = maxi(c.slow, 8)
	zones = keep


# ------------------------------------------------------------------ projectiles

## Two kinds: a ground projectile ("speed", "life") that travels until it hits someone,
## and a lob ("lob": true, "range", "time") that arcs over everyone and bursts where it
## lands, hitting everything within "burst" of that spot (Pinecone Bomb).
func spawn_projectile(owner: CreatureSim, mv: Dictionary, last := true, index := 0) -> void:
	var p: Dictionary = mv["projectile"]
	var hit := owner.hit_params(-1)
	# The last of a volley can hit differently (Knife Flurry's final knife knocks down).
	if last and p.has("volley"):
		for k in p["volley"].get("last", {}):
			hit[k] = p["volley"]["last"][k]
	var lob := bool(p.get("lob", false))
	var life := int(p["time"]) if lob else int(p["life"])
	var lob_range := lob_aim_range(owner, p)
	var locked := lob_lock(owner, p) if lob else null
	if locked != null:  # thrown at the foe the aim points at (Thousand Cranes)
		owner.facing = (locked.pos - owner.pos).normalized()
	var vel := owner.facing * (lob_range / float(life) if lob else float(p["speed"]))
	# A row ("row" {count, gap, side_push}): `count` shots side by side across the facing,
	# `gap` px apart (Paper Frog's three frogs). The middle one pushes straight on, the
	# outer ones push out to their own side (tilted forward by `side_push`), and a foe
	# touched by one of the row is passed by the rest.
	var row: Dictionary = {} if lob else p.get("row", {})
	# A fan ("volley" {fan, fan_max}): knife `index` leaves `fan` steps of the 64-step aim
	# table off the aim, alternating sides (0, +f, -f, +2f, -2f...), at most `fan_max` steps.
	var vol: Dictionary = {} if lob else p.get("volley", {})
	var fan := int(vol.get("fan", 0))
	if fan > 0 and index > 0 and not last:  # the last knife (knockdown, Tenderize) flies straight
		var steps := mini(((index + 1) / 2) * fan, int(vol.get("fan_max", 1000)))
		var base := SimDefs.aim_index(owner.facing)
		vel = SimDefs.aim_dirs()[posmod(base + (steps if index % 2 == 1 else -steps), SimDefs.AIM_STEPS)] * float(p["speed"])
	var count := maxi(1, int(row.get("count", 1)))
	var across := Vector2(-owner.facing.y, owner.facing.x)
	for k in count:
		var lane := float(k) - float(count - 1) * 0.5
		var pr := _new_projectile(owner, p, hit.duplicate() if k > 0 else hit, vel, life, lob)
		if not row.is_empty():
			pr["pos"] = Vector2(pr["pos"]) + across * lane * float(row.get("gap", 18.0))
			pr["lane"] = int(signf(lane))
			pr["row_struck"] = []
			pr["life_total"] = life  # the view times each frog's hops by it
			if lane != 0.0:
				pr["push"] = (across * signf(lane) + owner.facing * float(row.get("side_push", 0.0))).normalized()
		projectiles.append(pr)
	emit_event("projectile", owner.pos, 1.0, {"who": owner.id, "lob": lob, "sound": String(p.get("sound", ""))})


## How far a lob flies: its "range", or further the longer it was held ("range_charged",
## Pinecone Bomb), or, locked on (`lob_lock`), as far as the foe (clamped to that span).
func lob_aim_range(owner: CreatureSim, p: Dictionary) -> float:
	var lo := float(p.get("range", 0.0))
	var hi := float(p.get("range_charged", lo))
	var locked := lob_lock(owner, p)
	if locked != null:
		return clampf(owner.pos.distance_to(locked.pos) - float(p.get("offset", 16)), lo, hi)
	return lerpf(lo, hi, owner.charge_ratio) if p.has("range_charged") else lo


## A lob's lock-on ("lock_on" {dot}): the foe the aim points at, so a tap lands on them.
## A foe counts when the line to them is within the aim (dot of the two directions at
## least `dot`: 0.92 is about 23 degrees either side) and no further than the longest
## throw plus the storm's or burst's radius; the closest to the aim line wins, then the
## nearer. Hidden foes (stealth, brush) and knocked-out ones don't count. Null with no
## foe there: the throw goes where it's aimed, as far as it was held. Vectors only, so
## every machine agrees; the view calls this to draw the ring where it will land.
func lob_lock(owner: CreatureSim, p: Dictionary) -> CreatureSim:
	if not p.has("lock_on"):
		return null
	var min_dot := float((p["lock_on"] as Dictionary).get("dot", 0.92))
	var area := float((p.get("storm", {}) as Dictionary).get("radius", p.get("burst", 0.0)))
	var reach := float(p.get("range_charged", p.get("range", 0.0))) + float(p.get("offset", 16)) + area
	var best: CreatureSim = null
	var best_dot := -2.0
	var best_d := INF
	for o in creatures:
		if not owner.is_foe(o) or o.state == CreatureSim.State.KO or o.stealth > 0 or o.covered:
			continue
		var to := o.pos - owner.pos
		var d := to.length()
		if d < 0.0001 or d > reach:
			continue
		var dt := to.dot(owner.facing) / d
		if dt < min_dot:
			continue
		if dt > best_dot + 0.0001 or (absf(dt - best_dot) <= 0.0001 and d < best_d):
			best = o
			best_dot = dt
			best_d = d
	return best


func _new_projectile(owner: CreatureSim, p: Dictionary, hit: Dictionary, vel: Vector2, life: int, lob: bool) -> Dictionary:
	var pr := {
		"owner": owner.id,
		"serial": owner.attack_serial,
		"pos": owner.pos + owner.facing * float(p.get("offset", 16)),
		"vel": vel,
		"life": life,
		"radius": float(p.get("radius", 0.0)) * (1.0 if lob else projectile_radius_mult()),
		"hit": hit,
		"last_cell": Vector2i(-99, -99),
		"move": owner.move_id,  # for the view: which move threw it, so it knows what to draw
	}
	if p.has("radius_end") and not lob:
		# Grows over its flight (a hook): widest at the end of its reach.
		pr["radius_start"] = pr["radius"]
		pr["radius_end"] = float(p["radius_end"]) * projectile_radius_mult()
		pr["life_total"] = life
	if bool(p.get("pierce", false)):
		pr["struck"] = []  # passes through, hitting each body once (Knife Flurry)
	elif p.has("bounce") and not lob:
		pr["bounce"] = (p["bounce"] as Dictionary).duplicate(true)  # on to a second foe (Cleaver Toss)
	if p.has("end_sound"):
		pr["end_sound"] = String(p["end_sound"])  # cosmetic, passed on to the view
	if not bool(p.get("crack_trail", true)):
		pr["no_crack"] = true
	if lob:
		pr["lob"] = true
		pr["time"] = life
		pr["burst"] = float(p["burst"])
		pr["crack"] = float(p.get("crack", 0.0))
		if p.has("storm"):
			pr["storm"] = (p["storm"] as Dictionary).duplicate(true)
		if p.has("seed"):
			pr["seed"] = (p["seed"] as Dictionary).duplicate(true)  # a miss plants one (Pinecone Bomb)
	if p.has("home"):
		# Homing (Paper Crane): turns toward the nearest foe for its first `until` ticks,
		# by `turn` of a full step each tick, at its own speed. Vectors only, no angles,
		# so every machine steers it identically.
		var hm: Dictionary = p["home"]
		pr["home"] = {"turn": float(hm.get("turn", 0.15)), "stop": life - int(hm.get("until", life))}
		pr["speed"] = float(p["speed"])
	return pr


func _step_projectiles() -> void:
	var keep: Array[Dictionary] = []
	var fr := floor_rect()
	for p in projectiles:
		var pos: Vector2 = p["pos"]
		if bool(p.get("lob", false)):
			# In the air until it lands: stop at the wall, burst when the time runs out.
			var nxt := (pos + Vector2(p["vel"])).clamp(fr.position + Vector2(4, 4), fr.end - Vector2(4, 4))
			p["pos"] = nxt
			p["life"] = int(p["life"]) - 1
			if int(p["life"]) <= 0:
				_burst(p)
			else:
				keep.append(p)
			continue
		if p.has("home") and int(p["life"]) > int(p["home"]["stop"]):
			_steer(p)
		pos += p["vel"]
		p["pos"] = pos
		p["life"] = int(p["life"]) - 1
		if p.has("radius_end"):
			var flown := 1.0 - float(p["life"]) / float(p["life_total"])
			p["radius"] = lerpf(float(p["radius_start"]), float(p["radius_end"]), flown)
		if int(p["life"]) <= 0 or not fr.grow(-2.0).has_point(pos):
			emit_event("projectile_end", pos, 0.0, {"who": int(p["owner"]), "sound": String(p.get("end_sound", ""))})
			continue
		var cell := terrain.world_to_cell(pos)
		if TerrainGrid.blocks_shot(terrain.get_cell(cell)):
			# A rubble wall takes the shot (a fence or a chasm does not).
			emit_event("projectile_end", pos, 1.0, {"who": int(p["owner"]), "sound": String(p.get("end_sound", ""))})
			continue
		if cell != p["last_cell"] and not bool(p.get("no_crack", false)):
			p["last_cell"] = cell
			terrain.crack_cell(cell)
		var owner := creatures[int(p["owner"])]
		var hit: Dictionary = p["hit"]
		var spent := false
		var pierce := p.has("struck")
		if not plants.is_empty():
			# A shot hurts the other side's sprouts it passes over (once each) and flies on.
			if not p.has("plants_struck"):
				p["plants_struck"] = []
			Plants.strike(self, owner, pos, float(p["radius"]), float(hit["damage"]), p["plants_struck"])
		for d in creatures:
			if not owner.is_foe(d) or not _hittable(d, hit):
				continue
			if pierce and (p["struck"] as Array).has(d.id):
				continue
			if int(p.get("bounced_from", -1)) == d.id:
				continue
			if p.has("row_struck") and (p["row_struck"] as Array).has(d.id):
				continue
			if pos.distance_to(d.pos) > float(p["radius"]) + d.radius:
				continue
			var vel: Vector2 = p["vel"]
			_apply_hit(owner, d, hit, Vector2(p.get("push", vel.normalized())), pos + Vector2(0, -10), true)
			if p.has("row_struck"):
				_row_struck(p, d.id)
			if pierce:
				(p["struck"] as Array).append(d.id)
				emit_event("projectile_pierce", pos, 1.0, {"who": int(p["owner"]), "sound": String(p.get("end_sound", ""))})
				continue
			if p.has("bounce") and _bounce(p, d):
				break  # flies on at the next foe
			spent = true
			break
		if spent:
			emit_event("projectile_end", pos, 1.0, {"who": int(p["owner"]), "sound": String(p.get("end_sound", ""))})
		else:
			keep.append(p)
	projectiles = keep


## A bouncing shot ("bounce" {range, damage_mult}, Cleaver Toss) just hit `from`: it turns
## toward the nearest other foe whose body is within `range` px of where it hit, its damage
## × `damage_mult`, once. Foes it can't hit or can't see (stealth, brush) don't count, nor
## knocked-out ones. Returns false (the shot ends) with nobody in range. Vectors only, so
## every machine agrees.
func _bounce(p: Dictionary, from: CreatureSim) -> bool:
	var b: Dictionary = p["bounce"]
	p.erase("bounce")  # once: whatever happens now, it doesn't bounce again
	var owner := creatures[int(p["owner"])]
	var at: Vector2 = p["pos"]
	var hit: Dictionary = p["hit"]
	var best: CreatureSim = null
	var best_d := float(b.get("range", 80.0))
	for o in creatures:
		if o == from or not owner.is_foe(o) or o.state == CreatureSim.State.KO or o.stealth > 0 or o.covered:
			continue
		if not _hittable(o, hit):
			continue
		var dist := at.distance_to(o.pos) - o.radius
		if dist < best_d:
			best = o
			best_d = dist
	if best == null:
		return false
	var to := best.pos - at
	var speed := Vector2(p["vel"]).length()
	if to.length_squared() < 0.0001 or speed <= 0.0:
		return false
	p["vel"] = to.normalized() * speed
	p["life"] = int(to.length() / speed) + 4  # enough to get there, and not much past
	var nh := hit.duplicate()
	nh["damage"] = float(hit["damage"]) * float(b.get("damage_mult", 1.0))
	p["hit"] = nh
	p["bounced_from"] = from.id
	emit_event("projectile_bounce", at, 1.0, {"who": owner.id, "from": from.id, "to": best.id,
		"sound": String(p.get("end_sound", ""))})
	return true


## One of a row hit `foe_id`: the rest of that row (in flight, or yet to move this tick) pass them by.
func _row_struck(p: Dictionary, foe_id: int) -> void:
	for q in projectiles:
		if q.has("row_struck") and int(q["owner"]) == int(p["owner"]) and int(q["serial"]) == int(p["serial"]):
			(q["row_struck"] as Array).append(foe_id)


## A homing projectile turns toward the nearest foe (of its owner) from where it is.
func _steer(p: Dictionary) -> void:
	var at: Vector2 = p["pos"]
	var owner := creatures[int(p["owner"])]
	var best: CreatureSim = null
	var best_d := INF
	for o in creatures:
		if not owner.is_foe(o) or o.state == CreatureSim.State.KO or not o.can_be_hit():
			continue
		var d := o.pos.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = o
	if best == null or best_d < 0.0001:
		return
	var v: Vector2 = p["vel"]
	var want := (best.pos - at).normalized()
	var turned := v.normalized() + want * float(p["home"]["turn"])
	if turned.length_squared() < 0.0001:
		return
	p["vel"] = turned.normalized() * float(p["speed"])


## A lob lands: everything within the burst radius is hit, pushed away from the spot.
## A lob with a "storm" leaves one there instead (see _step_storms).
func _burst(p: Dictionary) -> void:
	var at: Vector2 = p["pos"]
	var owner := creatures[int(p["owner"])]
	var hit: Dictionary = p["hit"]
	if p.has("storm"):
		_add_storm(owner, at, p["storm"], hit)
		return
	if float(p.get("crack", 0.0)) > 0.0:
		terrain.crack_circle(at, float(p["crack"]))
	var landed := 0
	for d in creatures:
		if not owner.is_foe(d) or not _hittable(d, hit):
			continue
		if at.distance_to(d.pos) > float(p["burst"]) + d.radius:
			continue
		var push := d.pos - at
		push = push.normalized() if push.length_squared() > 0.0001 else Vector2(p["vel"]).normalized()
		_apply_hit(owner, d, hit, push, d.pos + Vector2(0, -10), true)
		landed += 1
	if not plants.is_empty():
		Plants.strike(self, owner, at, float(p["burst"]), float(hit["damage"]), [])
	emit_event("burst", at, float(p["burst"]), {"who": owner.id, "landed": landed})
	# A lob with a "seed" that hit nobody plants one where it fell: never after a hit.
	if landed == 0 and p.has("seed"):
		Plants.plant(self, owner, at, p["seed"], float(hit.get("root_ticks", 0.0)))


# ------------------------------------------------------------------ storms

## A storm where a lob landed: storm keys {radius, ticks, every, damage, hitstun,
## knockback_end, launch_end, crack_inner, crack_outer}; the throw's hit values
## otherwise.
func _add_storm(owner: CreatureSim, at: Vector2, sd: Dictionary, hit: Dictionary) -> void:
	var pulse := hit.duplicate()
	pulse["damage"] = float(sd.get("damage", 2.0))
	pulse["hitstun"] = float(sd.get("hitstun", 14.0))
	pulse["knockback"] = 0.0
	pulse["launch"] = 0.0
	pulse["knockdown"] = 0.0
	pulse["hitstop"] = float(sd.get("hitstop", 2.0))
	var last := hit.duplicate()
	last["damage"] = float(sd.get("damage_end", pulse["damage"]))
	last["knockback"] = float(sd.get("knockback_end", 4.0))
	last["launch"] = float(sd.get("launch_end", 0.0))
	last["knockdown"] = float(sd.get("knockdown_end", 0.0))
	last["hitstop"] = float(sd.get("hitstop_end", 10.0))
	storms.append({"owner": owner.id, "pos": at, "radius": float(sd.get("radius", 40.0)), "t": 0,
		"ticks": int(sd.get("ticks", 120)), "every": maxi(1, int(sd.get("every", 12))), "hit": pulse, "end": last,
		"crack_inner": float(sd.get("crack_inner", 0.0)), "crack_outer": float(sd.get("crack_outer", 0.0))})
	emit_event("storm", at, float(sd.get("radius", 40.0)), {"who": owner.id, "ticks": int(sd.get("ticks", 120))})


## Each storm ticks on: a pulse hits every foe inside it, the last tick pushes them out,
## cracks the ring and ends it.
func _step_storms() -> void:
	var keep: Array[Dictionary] = []
	for st in storms:
		st["t"] = int(st["t"]) + 1
		var owner := creatures[int(st["owner"])]
		var at: Vector2 = st["pos"]
		var done := int(st["t"]) >= int(st["ticks"])
		if done or int(st["t"]) % int(st["every"]) == 0:
			var hit: Dictionary = st["end"] if done else st["hit"]
			for d in creatures:
				if not owner.is_foe(d) or not _hittable(d, hit):
					continue
				if at.distance_to(d.pos) > float(st["radius"]) + d.radius:
					continue
				var push := d.pos - at
				push = push.normalized() if push.length_squared() > 0.0001 else Vector2.RIGHT
				_apply_hit(owner, d, hit, push, d.pos + Vector2(0, -10), true)
		if done:
			if float(st["crack_outer"]) > 0.0:
				terrain.crack_ring(at, float(st["crack_inner"]), float(st["crack_outer"]))
			emit_event("storm_end", at, float(st["radius"]), {"who": owner.id})
		else:
			keep.append(st)
	storms = keep


# ------------------------------------------------------------------ bodies and pits

func _separate() -> void:
	for i in creatures.size():
		for j in range(i + 1, creatures.size()):
			var a := creatures[i]
			var b := creatures[j]
			if not a.is_solid() or not b.is_solid():
				continue
			var d := b.pos - a.pos
			var dist := d.length()
			var min_d := a.radius + b.radius
			if dist >= min_d:
				continue
			var n := d / dist if dist > 0.0001 else Vector2.RIGHT
			# A rooted creature (Bedrock) doesn't budge, nor one in its own freeze-frame;
			# the other one takes the whole push.
			var a_still := a.is_armored() or a.hitstop > 0
			var b_still := b.is_armored() or b.hitstop > 0
			if a_still and b_still:
				continue
			var share_a := 0.0 if a_still else (1.0 if b_still else 0.5)
			var overlap := min_d - dist
			a.pos -= n * overlap * share_a
			b.pos += n * overlap * (1.0 - share_a)
			a.clamp_to_floor()
			b.clamp_to_floor()


## Nobody stays inside a wall or fence: a body pushed in (by another body, a blink, a
## wall that rebuilt around it) is moved out the shortest way.
func _unstick() -> void:
	for c in creatures:
		if not c.is_solid() and not c.passes_fences():
			continue
		var p := terrain.resolve_body(c.pos, c.radius, not c.passes_fences())
		if p != c.pos:
			c.pos = p
			c.clamp_to_floor()
		# Brush hides whoever stands in it (flattened brush doesn't).
		c.covered = terrain.get_cell(terrain.world_to_cell(c.pos)) == TerrainGrid.BRUSH


## A bridge's damage: each cracked cell counts 1, each hole 2.
func bridge_strain(i: int) -> int:
	var r := bridge_rects[i]
	var n := 0
	for cy in range(r.position.y, r.end.y):
		for cx in range(r.position.x, r.end.x):
			var v := terrain.get_cell(Vector2i(cx, cy))
			if v == TerrainGrid.CRACKED:
				n += 1
			elif v == TerrainGrid.HOLE:
				n += 2
	return n


## Whether bridge `i` is down (fallen in, not yet back).
func bridge_down(i: int) -> bool:
	return i < bridges.size() and int(bridges[i][0]) > 0


func _step_bridges() -> void:
	var defs: Array = arena.get("bridges", [])
	for i in mini(bridges.size(), bridge_rects.size()):
		var bd: Dictionary = defs[i]
		var r := bridge_rects[i]
		var st: Array = bridges[i]
		var mid := terrain.cell_center(r.position) + Vector2(r.size - Vector2i.ONE) * SimDefs.CELL * 0.5
		if int(st[0]) > 0:
			st[0] = int(st[0]) - 1
			if int(st[0]) == 0:  # back up, whole
				for cy in range(r.position.y, r.end.y):
					for cx in range(r.position.x, r.end.x):
						var k := cy * terrain.cols + cx
						terrain.cells[k] = terrain.base[k]
						terrain.timers[k] = 0
				terrain.version += 1
				st[1] = false
				emit_event("bridge_up", mid, 0.0, {"bridge": i})
			continue
		var crack := float(bd.get("crack", 10))
		for e in events:
			if String(e["type"]) != "hit" or not bool(e.get("heavy", false)):
				continue
			var d := creatures[int(e["target"])]
			var at := terrain.world_to_cell(d.pos)
			if r.has_point(at):
				terrain.crack_circle(d.pos, crack)
				terrain.damage_cell(at, 1)
		var strain := bridge_strain(i)
		var need := int(bd.get("strain", 28))
		if strain >= need:
			var t := int(float(bd.get("reform_seconds", 30)) * SimDefs.TICK_RATE)
			for cy in range(r.position.y, r.end.y):
				for cx in range(r.position.x, r.end.x):
					var k := cy * terrain.cols + cx
					terrain.cells[k] = TerrainGrid.SHALLOWS  # (heal_step leaves it: only bridge_up mends it)
					terrain.timers[k] = 0
			terrain.version += 1
			st[0] = t
			emit_event("bridge_fall", mid, float(t), {"bridge": i})
		elif not bool(st[1]) and strain * 2 >= need:
			st[1] = true
			emit_event("bridge_strain", mid, float(strain) / float(need), {"bridge": i})


func _check_falls() -> void:
	for c in creatures:
		if c.state in [CreatureSim.State.FALLING, CreatureSim.State.KO,
				CreatureSim.State.DODGE, CreatureSim.State.AIRBORNE] or c.is_leaping() or c.reel_t > 0:
			continue
		if c.invuln > 0 and c.state != CreatureSim.State.KNOCKDOWN:
			continue
		if c.hitstop > 0:
			continue  # held in its freeze-frame: the fall waits, as it did when everyone froze
		if terrain.is_hole_at(c.pos):
			c.start_fall(self)
