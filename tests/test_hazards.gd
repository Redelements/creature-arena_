extends TestCase
## Arena hazards (src/sim/hazards.gd, data/rules/hazards.json): the tidal wave and the
## meteor shower. Seeded placement, rollback mid-wave and mid-shower, damage as a share of
## max HP with the tank multiplier, shelter behind rubble, a wave that can't KO, warnings
## long enough to react to, the core's might buff, puddles that dry, mutators that stack,
## and a CPU that steps out of a shadow and gets behind rubble.

const WAVE := {"hazards": ["tidal_wave"]}
const METEORS := {"hazards": ["meteor_shower"]}


func _sim(m: Dictionary, seed_ := 7, a := "cairn", b := "culvert") -> MatchSim:
	var sim := MatchFactory.versus(a, b)
	sim.apply_mutators(m, seed_)
	return sim


## Takes the breakwaters away again (tests that want open floor).
func _clear_walls(sim: MatchSim) -> void:
	var t := sim.terrain
	for i in t.cells.size():
		if t.cells[i] == TerrainGrid.WALL:
			t.cells[i] = TerrainGrid.INTACT
			t.base[i] = TerrainGrid.INTACT
	t.version += 1


func _state(sim: MatchSim, shape: String) -> Dictionary:
	for st in sim.hazards:
		if String(sim.hazard_defs[String(st["id"])]["shape"]) == shape:
			return st
	return {}


## Steps with no input, collecting every event.
func _steps(sim: MatchSim, n: int, out: Array = []) -> Array:
	for i in n:
		sim.step(PackedInt32Array([0, 0]))
		out.append_array(sim.events)
	return out


func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e): return String(e["type"]) == kind)


## Starts the wave's warning on the next tick, from `side` (0 left, 1 right, 2 top, 3 bottom).
func _start_wave(sim: MatchSim, side := 0) -> Array:
	var st := _state(sim, "wave")
	st["next"] = sim.tick + 1
	var ev := _steps(sim, 1)
	st["side"] = side
	return ev


func _warn_ticks(sim: MatchSim) -> int:
	return Hazards.ticks_of(sim.hazard_defs["tidal_wave"]["warn_seconds"])


func test_breakwaters_rise_seeded_and_clear_of_the_fighters() -> void:
	var a := _sim(WAVE, 7)
	var b := _sim(WAVE, 7)
	var c := _sim(WAVE, 8)
	var walls := a.terrain.count(TerrainGrid.WALL)
	var bw: Dictionary = a.hazard_defs["tidal_wave"]["breakwaters"]
	assert_eq(walls, int(bw["count"]) * int(bw["size"][0]) * int(bw["size"][1]), "every breakwater rose:")
	assert_eq(a.terrain.cells, b.terrain.cells, "the same seed raises the same rubble:")
	assert_true(a.terrain.cells != c.terrain.cells, "another seed raises it elsewhere")
	for i in a.terrain.cells.size():
		if a.terrain.cells[i] != TerrainGrid.WALL:
			continue
		assert_eq(a.terrain.base[i], TerrainGrid.WALL, "a breakwater is the map's rubble (it rebuilds when smashed):")
		var at := a.terrain.cell_center(Vector2i(i % a.terrain.cols, i / a.terrain.cols))
		for f in a.creatures:
			assert_gt(at.distance_to(f.pos), 40.0, "rubble keeps clear of a fighter")
	var plain := MatchFactory.versus("cairn", "culvert")
	assert_eq(plain.terrain.count(TerrainGrid.WALL), 0, "no hazards, no rubble")
	assert_true(plain.hazards.is_empty(), "and no hazard state")


func test_the_wave_warns_then_sweeps_and_pushes_downstream() -> void:
	var sim := _sim(WAVE)
	_clear_walls(sim)
	var ev := _start_wave(sim, 0)
	var warn := _of(ev, "hazard_warn")
	assert_eq(warn.size(), 1, "a warning:")
	assert_true(int(warn[0]["ticks"]) >= 60, "of at least a second (%d ticks)" % int(warn[0]["ticks"]))
	var x0 := [sim.creatures[0].pos.x, sim.creatures[1].pos.x]
	var hp0 := [sim.creatures[0].hp, sim.creatures[1].hp]
	ev = _steps(sim, _warn_ticks(sim) + 2 * SimDefs.TICK_RATE)
	var strike := _of(ev, "hazard_strike")
	assert_eq(strike.size(), 1, "the front starts once:")
	assert_true(int(strike[0]["tick"]) >= int(warn[0]["tick"]) + _warn_ticks(sim), "only after the whole warning")
	var hits := _of(ev, "hazard_hit")
	assert_eq(hits.size(), 2, "it hits both fighters once each:")
	var d: Dictionary = sim.hazard_defs["tidal_wave"]
	var pct := float(d["damage_pct"])
	assert_near(float(hp0[0]) - sim.creatures[0].hp, sim.creatures[0].max_hp * pct, 0.01, "a share of max HP (fighter):")
	assert_near(float(hp0[1]) - sim.creatures[1].hp, sim.creatures[1].max_hp * pct * float(d["role_mult"]["tank"]), 0.01,
		"less on a tank:")
	assert_gt(sim.creatures[0].pos.x, float(x0[0]) + 20.0, "pushed downstream (to the right)")
	assert_gt(sim.creatures[1].pos.x, float(x0[1]) + 10.0, "the heavier one less, but still")


func test_the_wave_cannot_ko_but_a_pit_can() -> void:
	var sim := _sim(WAVE)
	_clear_walls(sim)
	sim.creatures[0].hp = 2.0
	_start_wave(sim, 0)
	_steps(sim, _warn_ticks(sim) + 90)
	assert_near(sim.creatures[0].hp, 1.0, 0.001, "left on 1 HP:")
	assert_true(sim.creatures[0].state != CreatureSim.State.KO, "still standing")
	# A chasm just downstream: the push carries it in, and the fall does the rest.
	var sim2 := _sim(WAVE)
	_clear_walls(sim2)
	sim2.fall_ko = true
	var c := sim2.creatures[0]
	var cell := sim2.terrain.world_to_cell(c.pos)
	for dy in range(-3, 4):
		for dx in range(3, 6):
			sim2.terrain.sink(cell + Vector2i(dx, dy))
	_start_wave(sim2, 0)
	var ev := _steps(sim2, _warn_ticks(sim2) + 200)
	assert_true(_of(ev, "fall").any(func(e): return int(e["who"]) == 0), "pushed into the pit")
	assert_eq(c.state, CreatureSim.State.KO, "a chasm fall KOs where the mode says so:")


func test_rubble_upstream_shelters_from_damage_and_push() -> void:
	var sim := _sim(WAVE)
	_clear_walls(sim)
	var c := sim.creatures[0]
	var cell := sim.terrain.world_to_cell(c.pos)
	_start_wave(sim, 0)  # from the left
	for dy in [-1, 0]:
		for dx in [-4, -3]:
			var w := cell + Vector2i(dx, dy)
			sim.terrain.set_cell(w, TerrainGrid.WALL)
	assert_true(Hazards.sheltered(sim.terrain, c.pos, c.radius, Vector2.RIGHT), "behind the rubble")
	assert_false(Hazards.sheltered(sim.terrain, c.pos, c.radius, Vector2.LEFT), "but not from the other way")
	var hp := c.hp
	var at := c.pos
	var ev := _steps(sim, _warn_ticks(sim) + 90)
	assert_near(c.hp, hp, 0.001, "no damage in shelter:")
	assert_lt(c.pos.distance_to(at), 1.0, "and no push")
	assert_true(_of(ev, "hazard_shelter").any(func(e): return int(e["who"]) == 0), "said so")
	assert_true(_of(ev, "hazard_hit").any(func(e): return int(e["who"]) == 1), "the other one, out in the open, is hit")


func test_puddles_after_the_wave_then_they_dry() -> void:
	var sim := _sim(WAVE)
	_clear_walls(sim)
	_start_wave(sim, 1)  # from the right: the left third floods
	var ev := _steps(sim, _warn_ticks(sim) + 70)
	assert_eq(_of(ev, "hazard_end").size(), 1, "the wave has passed:")
	var n := sim.terrain.count(TerrainGrid.SHALLOWS)
	assert_gt(float(n), 84.0 * 36.0 * 0.25, "a third of the floor is shallows (%d)" % n)
	var fr := sim.floor_rect()
	for i in sim.terrain.cells.size():
		if sim.terrain.cells[i] == TerrainGrid.SHALLOWS:
			var at := sim.terrain.cell_center(Vector2i(i % sim.terrain.cols, i / sim.terrain.cols))
			assert_lt(at.x, fr.position.x + fr.size.x * 0.4, "downstream only")
			break
	_steps(sim, Hazards.ticks_of(sim.hazard_defs["tidal_wave"]["shallows"]["seconds"]) + 2)
	assert_eq(sim.terrain.count(TerrainGrid.SHALLOWS), 0, "dried back to the floor:")
	assert_eq(sim.terrain.cells, sim.terrain.base, "exactly the map again:")


func test_warnings_are_long_enough_to_react() -> void:
	# tests/test_counterplay.gd wants 15+ frames before a big move; a hazard gives far more.
	for id in Hazards.table():
		if String(id).begins_with("_"):
			continue
		var d: Dictionary = Hazards.table()[id]
		var warn := Hazards.ticks_of(d.get("warn_seconds", 0)) if d.has("warn_seconds") else int(d.get("warn_ticks", 0))
		assert_true(warn >= 60, "%s warns %d ticks (want 60+)" % [id, warn])
	var sim := _sim(METEORS)
	var st := _state(sim, "meteors")
	st["next"] = sim.tick + 1
	var ev := _steps(sim, 1)
	var start := sim.tick
	var ms: Array = st["meteors"]
	assert_eq(ms.size(), int(sim.hazard_defs["meteor_shower"]["count"]), "the whole shower is planned:")
	for m in ms:
		assert_true(int(m["land"]) - start >= 60, "each shadow shows 60+ ticks before it lands")
		assert_eq(int(m["warn"]), int(sim.hazard_defs["meteor_shower"]["warn_ticks"]), "its own warning:")
	assert_eq(_of(ev, "hazard_warn").size(), 1, "the shower is announced:")
	assert_eq(ms.filter(func(m): return bool(m["big"])).size(), 1, "one big meteor:")
	assert_eq(ms.filter(func(m): return bool(m["core"])).size(), 1, "one leaves a core:")


func test_meteor_placement_is_seeded_and_half_aimed() -> void:
	var a := _sim(METEORS, 11)
	var b := _sim(METEORS, 11)
	var c := _sim(METEORS, 12)
	for sim: MatchSim in [a, b, c]:
		_state(sim, "meteors")["next"] = sim.tick + 1
		_steps(sim, 1)
	assert_eq(_state(a, "meteors")["meteors"], _state(b, "meteors")["meteors"], "same seed, same meteors:")
	assert_true(_state(a, "meteors")["meteors"] != _state(c, "meteors")["meteors"], "another seed, others")
	var near := 0
	var jitter := float(a.hazard_defs["meteor_shower"]["aim_jitter"])
	for m in _state(a, "meteors")["meteors"]:
		for f in a.creatures:
			if Vector2(m["pos"]).distance_to(f.pos) <= jitter * 1.5:
				near += 1
				break
	assert_true(near >= 4, "about half land near a fighter (%d)" % near)


func test_damage_scales_with_max_hp_and_role() -> void:
	var sim := _sim(METEORS, 1, "cairn", "craglash")
	var d: Dictionary = sim.hazard_defs["meteor_shower"]
	var f := sim.creatures[0]
	var t := sim.creatures[1]
	var got_f := Hazards.hurt(sim, f, d, Vector2.RIGHT, "meteor_shower", "meteors")
	var got_t := Hazards.hurt(sim, t, d, Vector2.LEFT, "meteor_shower", "meteors")
	assert_near(got_f, f.max_hp * float(d["damage_pct"]), 0.001, "fighter: the share of max HP:")
	assert_near(got_t, t.max_hp * float(d["damage_pct"]) * float(d["role_mult"]["tank"]), 0.001, "tank: times its multiplier:")
	# True damage: guard, shield and Glass cannon don't change it.
	var g := _sim(METEORS, 1, "cairn", "craglash")
	g.creatures[0].damage_mult = 1.5
	g.creatures[0].shield = 20.0
	g.creatures[0]._set_state(CreatureSim.State.GUARD)
	assert_near(Hazards.hurt(g, g.creatures[0], d, Vector2.RIGHT, "meteor_shower", "meteors"), got_f, 0.001, "true damage:")
	assert_eq(g.creatures[0].state, CreatureSim.State.HITSTUN, "through the guard:")
	var big := Hazards.effects(d, true)
	assert_gt(float(big["radius"]), float(d["radius"]), "the big one reaches further")
	assert_gt(float(big["pit"]), 0.0, "and punches a pit")


func test_a_meteor_lands_where_its_shadow_was() -> void:
	var sim := _sim(METEORS)
	var st := _state(sim, "meteors")
	st["next"] = sim.tick + 1
	_steps(sim, 1)
	var ms: Array = st["meteors"]
	var m: Dictionary = ms.filter(func(x): return bool(x["big"]))[0]
	var c := sim.creatures[0]
	c.pos = Vector2(m["pos"])
	sim.creatures[1].pos = sim.floor_rect().position + Vector2(12, 12)  # out of the way (or not: it doesn't matter)
	var hp := c.hp
	var ev := _steps(sim, int(m["land"]) - sim.tick + 1)
	var strike := _of(ev, "hazard_strike").filter(func(e): return bool(e["big"]))
	assert_eq(strike.size(), 1, "the big one lands:")
	assert_eq(Vector2(strike[0]["pos"]), Vector2(m["pos"]), "where its shadow was:")
	assert_lt(c.hp, hp - 1.0, "and it hurts")
	assert_true(sim.terrain.is_pit(sim.terrain.get_cell(sim.terrain.world_to_cell(Vector2(m["pos"])))) \
		or _of(ev, "fall").size() > 0 or c.state == CreatureSim.State.FALLING, "a pit where it hit")


func test_the_core_gives_might_to_the_first_to_touch_it() -> void:
	var sim := _sim(METEORS)
	var st := _state(sim, "meteors")
	st["next"] = sim.tick + 1
	_steps(sim, 1)
	var core: Dictionary = (st["meteors"] as Array).filter(func(x): return bool(x["core"]))[0]
	var fr := sim.floor_rect()
	sim.creatures[0].pos = fr.position + Vector2(14, 14)
	sim.creatures[1].pos = fr.end - Vector2(14, 14)
	_steps(sim, int(core["land"]) - sim.tick + 1)
	assert_eq(sim.hazard_pickups.size(), 1, "a core is left:")
	var pk: Dictionary = sim.hazard_pickups[0]
	var c := sim.creatures[0]
	c.pos = Vector2(pk["pos"]) + Vector2(4, 0)
	if sim.terrain.is_hole_at(c.pos):
		sim.terrain.set_cell(sim.terrain.world_to_cell(c.pos), TerrainGrid.INTACT)
	c._set_state(CreatureSim.State.IDLE)
	var ev := _steps(sim, 2)
	assert_eq(_of(ev, "hazard_pickup").size(), 1, "taken:")
	assert_true(sim.hazard_pickups.is_empty(), "and gone")
	var pd: Dictionary = sim.hazard_defs["meteor_shower"]["pickup"]
	assert_near(c.atk_mult, float(pd["mult"]), 0.001, "might:")
	assert_gt(float(c.atk_buff), Hazards.ticks_of(pd["buff_seconds"]) - 5.0, "for its time")


func test_an_untaken_core_fades() -> void:
	var sim := _sim(METEORS)
	sim.hazard_pickups = [{"pos": Vector2(300, 150), "radius": 10.0, "until": sim.tick + 5, "kind": "might", "ticks": 60, "mult": 1.2}]
	for c in sim.creatures:
		c.pos = Vector2(c.pos.x, 100.0) if c.pos.distance_to(Vector2(300, 150)) < 40.0 else c.pos
	var ev := _steps(sim, 6)
	assert_true(sim.hazard_pickups.is_empty(), "gone after its time")
	assert_eq(_of(ev, "hazard_pickup_gone").size(), 1, "said so:")


func _roll_check(sim: MatchSim, ticks: int) -> void:
	var snap := sim.snapshot()
	var hashes: Array = []
	for i in ticks:
		sim.step(PackedInt32Array([SimDefs.IN_RIGHT if i % 20 < 10 else SimDefs.IN_LIGHT, SimDefs.IN_LEFT]))
		hashes.append(sim.state_hash())
	sim.restore(snap)
	for i in ticks:
		sim.step(PackedInt32Array([SimDefs.IN_RIGHT if i % 20 < 10 else SimDefs.IN_LIGHT, SimDefs.IN_LEFT]))
		assert_eq(sim.state_hash(), hashes[i], "tick %d after the restore:" % i)
		if sim.state_hash() != hashes[i]:
			return


func test_rollback_mid_wave_and_mid_shower() -> void:
	var sim := _sim({"hazards": ["tidal_wave", "meteor_shower"]})
	_start_wave(sim, 2)
	_steps(sim, _warn_ticks(sim) - 10)
	_roll_check(sim, 120)  # the front starts, sweeps, floods
	var st := _state(sim, "meteors")
	st["next"] = sim.tick + 1
	_steps(sim, 30)
	_roll_check(sim, 200)  # shadows, impacts, the core
	# Puddles drying inside the window too.
	_roll_check(sim, 300)


func test_the_same_seed_plays_the_same_hazards() -> void:
	var hashes: Array = []
	for k in 2:
		var sim := _sim({"hazards": ["tidal_wave", "meteor_shower"]}, 5)
		for st in sim.hazards:
			st["next"] = 30
		for i in 900:
			sim.step(PackedInt32Array([SimDefs.IN_RIGHT if (i / 30) % 2 == 0 else SimDefs.IN_DOWN, SimDefs.IN_LEFT]))
		hashes.append(sim.state_digest())
	assert_eq(hashes[0], hashes[1], "same seed, same match:")


func test_two_mutators_hazards_stack_and_name() -> void:
	var table := Daily.mutator_table()
	assert_true(table.has("tidal_wave") and table.has("meteor_shower"), "both are mutators")
	var m := {}
	MatchSim.merge_mutator(m, table["tidal_wave"])
	MatchSim.merge_mutator(m, table["glass"])
	MatchSim.merge_mutator(m, table["meteor_shower"])
	assert_eq(m["hazards"], ["tidal_wave", "meteor_shower"], "the hazards add up:")
	var names := Daily.mutator_names(m)
	for n in ["Tidal wave", "Meteor shower", "Glass cannon"]:
		assert_true(n in names, "%s named (%s)" % [n, names])
	var sim := _sim(m)
	assert_eq(sim.hazards.size(), 2, "both run:")


func test_no_hazards_once_the_match_is_decided() -> void:
	var sim := _sim(WAVE)
	_clear_walls(sim)
	sim.creatures[1].hp = 0.0
	sim.creatures[1]._set_state(CreatureSim.State.KO)
	_start_wave(sim, 0)
	var ev := _steps(sim, _warn_ticks(sim) + 90)
	assert_eq(_of(ev, "hazard_hit").size(), 0, "a finished match stays finished:")


func test_cpu_steps_out_of_a_meteor_shadow() -> void:
	for level in [1, 3]:
		var sim := _sim(METEORS)
		var cpu := CpuController.new(0, level, 3)
		var c := sim.creatures[0]
		var st := _state(sim, "meteors")
		st["next"] = 1 << 30
		var r := float(sim.hazard_defs["meteor_shower"]["radius"])
		st["meteors"] = [{"pos": c.pos, "land": sim.tick + 70, "warn": 70, "radius": r, "big": false, "core": false}]
		var at := c.pos
		for i in 68:
			sim.step(PackedInt32Array([cpu.bits(sim), 0]))
		assert_gt(c.pos.distance_to(at), r + c.radius, "level %d out of the shadow before it lands" % level)


func test_cpu_gets_behind_rubble_when_a_wave_comes() -> void:
	var sim := _sim(WAVE)
	_clear_walls(sim)
	var cpu := CpuController.new(0, 2, 3)
	var c := sim.creatures[0]
	sim.creatures[1].pos = sim.floor_rect().end - Vector2(20, 20)  # the foe far off
	var cell := sim.terrain.world_to_cell(c.pos) + Vector2i(3, -6)
	for dy in 2:
		for dx in 2:
			sim.terrain.set_cell(cell + Vector2i(dx, dy), TerrainGrid.WALL)
	_start_wave(sim, 2)  # from the top
	var hp := c.hp
	var ev: Array = []
	for i in _warn_ticks(sim) + 80:
		sim.step(PackedInt32Array([cpu.bits(sim), 0]))
		ev.append_array(sim.events)
	assert_true(_of(ev, "hazard_shelter").any(func(e): return int(e["who"]) == 0), "it sheltered")
	assert_near(c.hp, hp, 0.001, "and took nothing:")
