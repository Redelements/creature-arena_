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
var creatures: Array[CreatureSim] = []
var projectiles: Array[Dictionary] = []
var events: Array[Dictionary] = []


func add_creature(def: Dictionary, p: Vector2, is_dummy := false) -> CreatureSim:
	var c := CreatureSim.new(creatures.size(), def, p, is_dummy)
	creatures.append(c)
	return c


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
	terrain.tick()
	for i in creatures.size():
		creatures[i].step(_input(inputs, i), self)
	_step_projectiles()
	_resolve_hits()
	_separate()
	_check_falls()


func _buffer_all(inputs: PackedInt32Array) -> void:
	for i in creatures.size():
		creatures[i].buffer_input(_input(inputs, i), self)


func nearest_opponent(c: CreatureSim) -> CreatureSim:
	var best: CreatureSim = null
	var best_d := INF
	for o in creatures:
		if o == c or o.state == CreatureSim.State.KO:
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
		"tick": tick, "hitstop": hitstop, "ko_freeze": ko_freeze, "slowmo": slowmo,
		"cells": terrain.cells.duplicate(), "timers": terrain.timers.duplicate(),
		"terrain_version": terrain.version,
		"creatures": cs, "projectiles": projectiles.duplicate(true),
	}


func restore(s: Dictionary) -> void:
	tick = int(s["tick"])
	hitstop = int(s["hitstop"])
	ko_freeze = int(s["ko_freeze"])
	slowmo = int(s["slowmo"])
	terrain.cells = PackedByteArray(s["cells"]).duplicate()
	terrain.timers = PackedInt32Array(s["timers"]).duplicate()
	terrain.version = maxi(terrain.version, int(s["terrain_version"])) + 1  # forces a redraw
	var cs: Array = s["creatures"]
	for i in creatures.size():
		creatures[i].load_state(cs[i])
	projectiles.assign((s["projectiles"] as Array).duplicate(true))
	events.clear()


## An exact fingerprint of the match state (SHA-256 of its bytes). Floats are hashed
## bit for bit, so two machines only agree if they computed identical results; this
## is what online play checks to catch desyncs.
func state_digest() -> String:
	var parts: Array = [tick, hitstop, ko_freeze, slowmo, terrain.cells, terrain.timers]
	for c in creatures:
		var st := c.save_state()
		for f in CreatureSim.STATE_FIELDS:
			parts.append(st[f])
	for p in projectiles:
		parts.append_array([p["pos"], p["vel"], p["life"], p["owner"], p["serial"]])
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
			if d == a:
				continue
			var key := "%d:%d" % [d.id, seg]
			if a.seg_hit.has(key):
				continue
			var hit := a.hit_params(seg)
			if not _hittable(d, hit):
				continue
			if center.distance_to(d.pos) > reach + d.radius:
				continue
			a.seg_hit[key] = true
			var push := d.pos - a.pos
			push = push.normalized() if push.length_squared() > 0.0001 else a.facing
			_apply_hit(a, d, hit, push, (center + d.pos) * 0.5 + Vector2(0, -12))


## Resolves one hit: Slip counters, guarding, then damage with the combo rules.
## Returns "slip", "block" or "hit".
func _apply_hit(a: CreatureSim, d: CreatureSim, hit: Dictionary, push: Vector2, fx_pos: Vector2) -> String:
	var same_attack := a.attack_serial == int(hit["serial"]) and a.state == CreatureSim.State.ATTACK

	# Slip: a strike inside the counter window is dodged and answered. Grabs beat it.
	if not bool(hit["grab"]) and d.in_counter_window():
		d.trigger_counter(a.pos, self)
		return "slip"

	var damage := float(hit["damage"])
	var gd: Dictionary = d.def["guard"]

	if d.state == CreatureSim.State.GUARD and not bool(hit["grab"]):
		var facing_attacker := d.facing.dot(-push) > 0.3
		if facing_attacker and not bool(hit["guard_break"]):
			var chip := damage * (1.0 - float(gd["reduction"]))
			d.hp -= chip
			d.stamina -= damage * float(gd["drain_per_damage"])
			d.knock_vel = push * float(hit["knockback"]) * 0.4 / d.weight
			d.guard_hit = 10
			d.stun = int(float(hit["hitstun"]) * 0.5)
			a.energy = minf(CreatureSim.MAX_ENERGY, a.energy + chip * ENERGY_PER_DAMAGE)
			if same_attack:
				a.connected = true
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
		emit_event("guard_break", d.pos, 1.0)

	# --- a clean hit
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

	d.hp -= total
	d.flash = 6
	d.combo_hits = n
	d.combo_types = types
	d.combo_moves[move_key] = int(hit["serial"])
	d.combo_damage += total
	d.last_attacker = a.id
	a.energy = minf(CreatureSim.MAX_ENERGY, a.energy + total * ENERGY_PER_DAMAGE)
	d.energy = minf(CreatureSim.MAX_ENERGY, d.energy + total * ENERGY_PER_DAMAGE_TAKEN)
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

	if bool(hit["grab"]):
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
		d.extend_air(CreatureSim.JUGGLE_FLOAT, kb * 0.5)
	elif float(hit["crumple"]) > 0.0:
		d.enter_crumple(int(hit["crumple"]), kb)
	elif broke_guard:
		d.enter_crumple(maxi(stun, int(gd["break_stun"])), kb)
	else:
		d.enter_hitstun(stun, kb)

	hitstop = maxi(hitstop, int(hit["hitstop"]))
	emit_event("hit", fx_pos, total, {
		"attacker": a.id, "target": d.id, "type": String(hit["type"]),
		"combo": n, "variety": variety, "stale": stale < 1.0,
		"heavy": String(hit["type"]) != "light"})
	d.check_ko(self)
	return "hit"


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


# ------------------------------------------------------------------ projectiles

func spawn_projectile(owner: CreatureSim, mv: Dictionary) -> void:
	var p: Dictionary = mv["projectile"]
	var hit := owner.hit_params(-1)
	projectiles.append({
		"owner": owner.id,
		"serial": owner.attack_serial,
		"pos": owner.pos + owner.facing * float(p.get("offset", 16)),
		"vel": owner.facing * float(p["speed"]),
		"life": int(p["life"]),
		"radius": float(p["radius"]),
		"hit": hit,
		"last_cell": Vector2i(-99, -99),
	})
	emit_event("projectile", owner.pos, 1.0)


func _step_projectiles() -> void:
	var keep: Array[Dictionary] = []
	var fr := SimDefs.floor_rect()
	for p in projectiles:
		var pos: Vector2 = p["pos"]
		pos += p["vel"]
		p["pos"] = pos
		p["life"] = int(p["life"]) - 1
		if int(p["life"]) <= 0 or not fr.grow(-2.0).has_point(pos):
			emit_event("projectile_end", pos, 0.0)
			continue
		var cell := terrain.world_to_cell(pos)
		if cell != p["last_cell"]:
			p["last_cell"] = cell
			terrain.crack_cell(cell)
		var owner := creatures[int(p["owner"])]
		var hit: Dictionary = p["hit"]
		var spent := false
		for d in creatures:
			if d == owner or not _hittable(d, hit):
				continue
			if pos.distance_to(d.pos) > float(p["radius"]) + d.radius:
				continue
			var vel: Vector2 = p["vel"]
			_apply_hit(owner, d, hit, vel.normalized(), pos + Vector2(0, -10))
			spent = true
			break
		if spent:
			emit_event("projectile_end", pos, 1.0)
		else:
			keep.append(p)
	projectiles = keep


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
			var push := (min_d - dist) * 0.5
			a.pos -= n * push
			b.pos += n * push
			a.clamp_to_floor()
			b.clamp_to_floor()


func _check_falls() -> void:
	for c in creatures:
		if c.state in [CreatureSim.State.FALLING, CreatureSim.State.KO,
				CreatureSim.State.DODGE, CreatureSim.State.AIRBORNE]:
			continue
		if c.invuln > 0 and c.state != CreatureSim.State.KNOCKDOWN:
			continue
		if terrain.is_hole_at(c.pos):
			c.start_fall(self)
