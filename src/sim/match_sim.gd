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
const ENERGY_PER_DAMAGE := 1.5
const ENERGY_PER_DAMAGE_TAKEN := 1.0
const STONE_SHATTER_MULT := 1.25
## A blocked third light (or later: Cairn's Hook) leaves the attacker at least this many
## ticks behind the blocker, enough to punish with a jab, and it can't be cancelled out of.
const BLOCKED_ENDER_DISADVANTAGE := 16
## Defaults for a poison move without "poison_every" and a reel without "reel_speed".
const POISON_EVERY_DEFAULT := 30
const REEL_SPEED_DEFAULT := 5.0
## Training options a training match can turn on (set_training_flags).
const TRAINING_FLAGS := ["no_cooldowns", "full_energy"]

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
var sink_ring := -1
## Sinkhole: the cells that stay floor once the cracked ring drops (empty: no warning).
var sink_safe := Rect2i()
## An objective on the floor (King of the Crater): where the zone is and its radius
## (0: none). Views draw it, the CPU goes for it.
var zone_pos := Vector2.ZERO
var zone_r := 0.0
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
var events: Array[Dictionary] = []


## Lays an arena map on the floor. Call before adding creatures (it resets the grid).
func set_arena(id: String) -> void:
	arena_id = id
	arena = ArenaMap.get_map(id)
	terrain.load_map(arena)


## Applies mutators (data/rules/mutators.json keys): per-fighter multipliers go on
## every creature, `surge_every` fills the meters on a timer, `pit_floor` sinks that
## share of the floor into chasms in a pattern from `seed_`, clear of the spawns.
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
	creatures.append(c)
	return c


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
	if kind == "ko":
		var who := int(extra.get("who", -1))
		if who < 0 or who >= creatures.size() or not creatures[who].is_dummy:
			ko_freeze = maxi(ko_freeze, ko_freeze_ticks)
			slowmo = maxi(slowmo, ko_slowmo_ticks)


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
	for i in creatures.size():
		creatures[i].step(_input(inputs, i), self)
	_step_swallows()
	_step_projectiles()
	_step_zones()
	_resolve_hits()
	_separate()
	_unstick()
	_check_falls()
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


## Everything that changes during a match, for rollback netcode: restore(snapshot())
## puts the match back exactly as it was. Creature definitions aren't copied (they
## never change), and events aren't either (they're rebuilt every step).
func snapshot() -> Dictionary:
	var cs: Array = []
	for c in creatures:
		cs.append(c.save_state())
	return {
		"tick": tick, "hitstop": hitstop, "ko_freeze": ko_freeze, "slowmo": slowmo, "sink_ring": sink_ring, "sink_safe": sink_safe,
		"zone_pos": zone_pos, "zone_r": zone_r,
		"cells": terrain.cells.duplicate(), "timers": terrain.timers.duplicate(), "base": terrain.base.duplicate(),
		"terrain_version": terrain.version,
		"creatures": cs, "projectiles": projectiles.duplicate(true), "zones": zones.duplicate(true),
		"training_flags": training_flags.duplicate(),
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
	training_flags = (s.get("training_flags", {}) as Dictionary).duplicate()
	events.clear()


## An exact fingerprint of the match state (SHA-256 of its bytes). Floats are hashed
## bit for bit, so two machines only agree if they computed identical results; this
## is what online play checks to catch desyncs.
func state_digest() -> String:
	var parts: Array = [tick, hitstop, ko_freeze, slowmo, arena_id, sink_ring, sink_safe, zone_pos, zone_r, terrain.cells, terrain.timers, terrain.base]
	for c in creatures:
		var st := c.save_state()
		for f in CreatureSim.STATE_FIELDS:
			parts.append(st[f])
	for p in projectiles:
		parts.append_array([p["pos"], p["vel"], p["life"], p["owner"], p["serial"]])
	for z in zones:
		parts.append_array([z["pos"], z["radius"], z["ticks"], z["owner"], z["slow_mult"]])
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
		if not bool(hit["juggle"]) or bool(hit["grab"]):
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
		for d in creatures:
			if not a.is_foe(d):
				continue
			var key := "%d:%d" % [d.id, seg]
			if a.seg_hit.has(key):
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
	if d.vuln > 0:
		damage *= d.vuln_mult  # tenderized: every hit lands harder, chip included
	if a.ambush_serial > 0 and int(hit["serial"]) == a.ambush_serial:
		damage *= float(a.def.get("ambush", 1.0))  # a sneak attack out of stealth
	var gd: Dictionary = d.def["guard"]

	# Armor (Bedrock): the hit only chips, and the target doesn't flinch or move.
	if d.is_armored() and not bool(hit["grab"]):
		var ar: Dictionary = d.move_def()["armor"]
		var taken := d.take_damage(damage * (1.0 - float(ar.get("reduction", 0.6))), self)
		a.dealt_damage()
		d.flash = 3
		if String(hit["type"]) != "surge":  # a Surge never charges the next one
			gain_energy(a, taken * ENERGY_PER_DAMAGE)
		if same_attack:
			a.connected = true
		hitstop = maxi(hitstop, int(float(hit["hitstop"]) * 0.6))
		emit_event("armor", fx_pos, taken, {"attacker": a.id, "target": d.id})
		d.check_ko(self)
		return "armor"

	if d.state == CreatureSim.State.GUARD and not bool(hit["grab"]):
		var facing_attacker := d.facing.dot(-push) > 0.3
		if facing_attacker and not bool(hit["guard_break"]):
			var chip := d.take_damage(damage * (1.0 - float(gd["reduction"])), self)
			a.dealt_damage()
			d.stamina -= damage * float(gd["drain_per_damage"])
			d.knock_vel = push * float(hit["knockback"]) * 0.4 / d.weight
			d.guard_hit = 10
			d.stun = int(float(hit["hitstun"]) * 0.5)
			if String(hit["type"]) != "surge":
				gain_energy(a, chip * ENERGY_PER_DAMAGE)
			if same_attack:
				a.connected = true
				_punish_blocked_ender(a, d)
			hitstop = maxi(hitstop, int(float(hit["hitstop"]) * 0.5))
			emit_event("block", fx_pos, damage, {"attacker": a.id, "target": d.id})
			if d.stamina <= 0.0:
				d.break_guard(self)
			d.check_ko(self)
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
	# isn't already stunned it doesn't start a combo either.
	var no_flinch := bool(hit.get("no_flinch", false))
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

	d.take_damage(total, self)
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
	if String(hit["type"]) != "surge":  # a Surge's hits never charge the next Surge
		gain_energy(a, total * ENERGY_PER_DAMAGE)
	gain_energy(d, total * ENERGY_PER_DAMAGE_TAKEN)
	if same_attack:
		a.connected = true
	var stack_def: Dictionary = a.def.get("stack", {})
	if String(hit["type"]) == "light" and not stack_def.is_empty():
		a.stack = mini(a.stack + 1, int(stack_def["max"]))
		a.stack_t = int(stack_def["timeout"])

	var kb := push * float(hit["knockback"]) / d.weight
	var was_air := d.is_airborne()
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
		emit_event("poisoned", d.pos, float(hit["poison_ticks"]), {"who": d.id, "by": a.id})

	if d.stealth > 0 and not (bool(hit["no_flinch"]) and ranged):
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

	if no_flinch and d.is_winding_up() and not ranged:
		# A jab doesn't stagger, but it still beats a big move's windup: hitting first stays
		# a counter to the red and gold tells. Thrown flicks don't.
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
	elif bool(hit["grab"]) and float(hit.get("swallow", 0.0)) > 0.0:
		_swallow(a, d, hit)
		emit_event("swallow", a.pos + Vector2(0, -16), total, {"attacker": a.id, "target": d.id})
	elif bool(hit["grab"]) and float(hit.get("flip", 0.0)) > 0.0:
		_flip(a, d, hit)
		emit_event("grab", a.pos + Vector2(0, -20), total, {"attacker": a.id, "target": d.id, "flip": true})
	elif bool(hit["grab"]) and float(hit.get("pull", 0.0)) > 0.0:
		# A hook (Culvert's tongue, tapped): the target is stunned and hauled in to him.
		hooked = true
		d.enter_hitstun(stun, Vector2.ZERO)
		emit_event("hook", d.pos + Vector2(0, -12), total, {"attacker": a.id, "target": d.id})
	elif bool(hit["grab"]):
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
	if pull > 0.0 and (hooked or not bool(hit["grab"])) and d.pos.distance_squared_to(a.pos) > 0.0001:
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

	hitstop = maxi(hitstop, int(hit["hitstop"]))
	emit_event("hit", fx_pos, total, {
		"attacker": a.id, "target": d.id, "type": String(hit["type"]),
		"combo": n, "variety": variety, "stale": stale < 1.0,
		"heavy": String(hit["type"]) != "light", "no_flinch": no_flinch})
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
func spawn_projectile(owner: CreatureSim, mv: Dictionary, last := true) -> void:
	var p: Dictionary = mv["projectile"]
	var hit := owner.hit_params(-1)
	# The last of a volley can hit differently (Knife Flurry's final knife knocks down).
	if last and p.has("volley"):
		for k in p["volley"].get("last", {}):
			hit[k] = p["volley"]["last"][k]
	var lob := bool(p.get("lob", false))
	var life := int(p["time"]) if lob else int(p["life"])
	var lob_range := float(p.get("range", 0.0))
	if p.has("range_charged"):  # held longer, thrown further (Pinecone Bomb)
		lob_range = lerpf(lob_range, float(p["range_charged"]), owner.charge_ratio)
	var vel := owner.facing * (lob_range / float(life) if lob else float(p["speed"]))
	var pr := {
		"owner": owner.id,
		"serial": owner.attack_serial,
		"pos": owner.pos + owner.facing * float(p.get("offset", 16)),
		"vel": vel,
		"life": life,
		"radius": float(p.get("radius", 0.0)),
		"hit": hit,
		"last_cell": Vector2i(-99, -99),
		"move": owner.move_id,  # for the view: which move threw it, so it knows what to draw
	}
	if bool(p.get("pierce", false)):
		pr["struck"] = []  # passes through, hitting each body once (Knife Flurry)
	if p.has("end_sound"):
		pr["end_sound"] = String(p["end_sound"])  # cosmetic, passed on to the view
	if not bool(p.get("crack_trail", true)):
		pr["no_crack"] = true
	if lob:
		pr["lob"] = true
		pr["time"] = life
		pr["burst"] = float(p["burst"])
		pr["crack"] = float(p.get("crack", 0.0))
	projectiles.append(pr)
	emit_event("projectile", owner.pos, 1.0, {"who": owner.id, "lob": lob, "sound": String(p.get("sound", ""))})


func _step_projectiles() -> void:
	var keep: Array[Dictionary] = []
	var fr := SimDefs.floor_rect()
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
		pos += p["vel"]
		p["pos"] = pos
		p["life"] = int(p["life"]) - 1
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
		for d in creatures:
			if not owner.is_foe(d) or not _hittable(d, hit):
				continue
			if pierce and (p["struck"] as Array).has(d.id):
				continue
			if pos.distance_to(d.pos) > float(p["radius"]) + d.radius:
				continue
			var vel: Vector2 = p["vel"]
			_apply_hit(owner, d, hit, vel.normalized(), pos + Vector2(0, -10), true)
			if pierce:
				(p["struck"] as Array).append(d.id)
				emit_event("projectile_pierce", pos, 1.0, {"who": int(p["owner"]), "sound": String(p.get("end_sound", ""))})
				continue
			spent = true
			break
		if spent:
			emit_event("projectile_end", pos, 1.0, {"who": int(p["owner"]), "sound": String(p.get("end_sound", ""))})
		else:
			keep.append(p)
	projectiles = keep


## A lob lands: everything within the burst radius is hit, pushed away from the spot.
func _burst(p: Dictionary) -> void:
	var at: Vector2 = p["pos"]
	var owner := creatures[int(p["owner"])]
	var hit: Dictionary = p["hit"]
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
	emit_event("burst", at, float(p["burst"]), {"who": owner.id, "landed": landed})


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
			# A rooted creature (Bedrock) doesn't budge; the other one takes the whole push.
			var share_a := 0.0 if a.is_armored() else (1.0 if b.is_armored() else 0.5)
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


func _check_falls() -> void:
	for c in creatures:
		if c.state in [CreatureSim.State.FALLING, CreatureSim.State.KO,
				CreatureSim.State.DODGE, CreatureSim.State.AIRBORNE] or c.is_leaping() or c.reel_t > 0:
			continue
		if c.invuln > 0 and c.state != CreatureSim.State.KNOCKDOWN:
			continue
		if terrain.is_hole_at(c.pos):
			c.start_fall(self)
