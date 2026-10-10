class_name MatchSim
extends RefCounted
## The whole match state. Call step() once per tick with one input bitmask per creature.
## Everything the view needs to react to (hits, slams, falls) is listed in `events`
## after each step.

var tick := 0
var hitstop := 0
var terrain := TerrainGrid.new()
var creatures: Array[CreatureSim] = []
var events: Array[Dictionary] = []


func add_creature(def: Dictionary, p: Vector2, is_dummy := false) -> CreatureSim:
	var c := CreatureSim.new(creatures.size(), def, p, is_dummy)
	creatures.append(c)
	return c


func emit_event(kind: String, p: Vector2, power: float, extra := {}) -> void:
	var e := {"type": kind, "pos": p, "power": power, "tick": tick}
	e.merge(extra)
	events.append(e)


func step(inputs: PackedInt32Array) -> void:
	events.clear()
	tick += 1
	if hitstop > 0:
		# Freeze-frame on impact: nothing moves, but presses are buffered.
		hitstop -= 1
		for i in creatures.size():
			creatures[i].buffer_input(_input(inputs, i))
		return
	terrain.tick()
	for i in creatures.size():
		creatures[i].step(_input(inputs, i), self)
	_resolve_hits()
	_separate()
	_check_falls()


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


## A fingerprint of the full match state, used by the determinism and replay tests.
func state_hash() -> int:
	var parts: Array = [tick, hitstop, terrain.version, hash(terrain.cells)]
	for c in creatures:
		parts.append_array([
			snappedf(c.pos.x, 0.001), snappedf(c.pos.y, 0.001),
			snappedf(c.hp, 0.001), snappedf(c.stamina, 0.001),
			c.state, c.state_t, c.move_id, c.charge])
	return hash(str(parts))


static func _input(inputs: PackedInt32Array, i: int) -> int:
	return inputs[i] if i < inputs.size() else 0


func _resolve_hits() -> void:
	for a in creatures:
		if not a.is_active():
			continue
		var center := a.hit_center()
		var reach := a.move_value("hit_radius")
		for d in creatures:
			if d == a or a.hit_ids.has(d.id) or not d.can_be_hit():
				continue
			if center.distance_to(d.pos) > reach + d.radius:
				continue
			a.hit_ids[d.id] = true
			var damage := a.move_value("damage")
			var blocked := d.receive_hit(a, damage, a.move_value("knockback"),
				int(round(a.move_value("hitstun"))), bool(a.move_def().get("guard_break", false)), self)
			var stop := int(round(a.move_value("hitstop")))
			hitstop = maxi(hitstop, int(stop * 0.5) if blocked else stop)
			var mid := (center + d.pos) * 0.5 + Vector2(0, -12)
			emit_event("block" if blocked else "hit", mid, damage,
				{"attacker": a.id, "target": d.id, "heavy": a.move_id == "heavy"})


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
		if c.state == CreatureSim.State.FALLING or c.state == CreatureSim.State.KO:
			continue
		if c.state == CreatureSim.State.DODGE or c.invuln > 0:
			continue
		if terrain.is_hole_at(c.pos):
			c.start_fall(self)
