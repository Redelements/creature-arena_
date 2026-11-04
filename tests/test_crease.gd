extends TestCase
## Mister Crease's kit: Paper Stock (three sheets that regrow), fold-then-use crafts (a
## first press folds, a second uses), the homing Paper Crane, the Paper Frog row of three hopping frogs, the
## bleeding Paper Shuriken, the Paper Plane dodge and the Thousand Cranes storm.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE


func _duel(foe := "cairn", gap := 60.0) -> MatchSim:
	var sim := MatchFactory.versus("crease", foe)
	sim.creatures[0].pos = Vector2(200, 164)
	sim.creatures[0].facing = Vector2.RIGHT
	sim.creatures[1].pos = Vector2(200 + gap, 164)
	sim.creatures[1].facing = Vector2.LEFT
	return sim


## Presses `bit` and waits until Crease is free again (or `limit` ticks).
func _press_and_settle(sim: MatchSim, bit: int, limit := 120) -> void:
	var c := sim.creatures[0]
	tap(sim, bit, 1)
	for i in limit:
		if c.state == CreatureSim.State.IDLE or c.state == CreatureSim.State.MOVE:
			return
		sim.step(PackedInt32Array([0, 0]))


func test_three_sheets_that_regrow_one_every_five_seconds() -> void:
	var sim := _duel("cairn", 160.0)
	var c := sim.creatures[0]
	assert_eq(c.sheets, 3, "a full stock to start:")
	_press_and_settle(sim, H)  # folds the shuriken: one sheet
	assert_eq(c.sheets, 2, "a fold spends one:")
	run(sim, 0, 299 - 30)
	var before := c.sheets
	run(sim, 0, 60)
	assert_eq(c.sheets, before + 1 if before < 3 else 3, "one regrows after 300 ticks:")
	run(sim, 0, 1200)
	assert_eq(c.sheets, 3, "never past three:")


func test_first_press_folds_second_press_uses() -> void:
	var sim := _duel("cairn", 160.0)
	var c := sim.creatures[0]
	tap(sim, H, 2)
	assert_eq(c.move_id, "fold_heavy", "the first press folds:")
	assert_false(c.folded.has("heavy"), "not ready until the fold is done")
	assert_true(run_until(sim, func(): return c.folded.has("heavy"), 40), "folded")
	assert_eq(c.sheets, 2, "the sheet is spent when the fold completes:")
	_press_and_settle(sim, 0)
	var serial := c.attack_serial
	tap(sim, H, 2)
	assert_eq(c.move_id, "heavy", "the second press throws it:")
	assert_true(c.attack_serial != serial, "")
	assert_false(c.folded.has("heavy"), "and the craft is gone")
	assert_eq(c.sheets, 2, "using it costs nothing more:")


func test_he_can_carry_all_three_crafts() -> void:
	var sim := _duel("cairn", 160.0)
	var c := sim.creatures[0]
	for bit in [H, S1, S2]:
		_press_and_settle(sim, bit)
	assert_eq(c.folded.keys().size(), 3, "three crafts ready:")
	assert_eq(c.sheets, 0, "all three sheets used:")
	assert_false(c.can_use("heavy") and c.needs_fold("heavy"), "")
	run(sim, 0, 200)  # cooldowns of nothing: the crafts wait
	assert_eq(c.folded.keys().size(), 3, "they stay ready:")


func test_no_sheets_no_fold() -> void:
	var sim := _duel("cairn", 160.0)
	var c := sim.creatures[0]
	c.sheets = 0
	assert_false(c.can_use("heavy"), "nothing to fold with")
	tap(sim, H, 4)
	assert_true(c.move_id != "fold_heavy" or c.state != CreatureSim.State.ATTACK, "no fold starts")


func test_a_hit_during_the_fold_refunds_the_sheet() -> void:
	var sim := _duel("cairn", 20.0)
	var c := sim.creatures[0]
	tap(sim, H, 3)
	assert_eq(c.move_id, "fold_heavy", "folding:")
	# The foe jabs him out of it.
	assert_true(run_until(sim, func(): return c.is_stunned(), 30, 0, SimDefs.IN_LIGHT), "hit out of the fold")
	run(sim, 0, 60)
	assert_eq(c.sheets, 3, "the sheet comes back (it was never spent):")
	assert_false(c.folded.has("heavy"), "and nothing was folded")


func test_carried_crafts_survive_a_hit() -> void:
	var sim := _duel("craglash", 24.0)  # Craglash's lights stagger
	var c := sim.creatures[0]
	_press_and_settle(sim, S1)
	assert_true(c.folded.has("skill_1"), "a crane in hand")
	assert_true(run_until(sim, func(): return c.is_stunned(), 40, 0, SimDefs.IN_LIGHT), "hit")
	assert_true(c.folded.has("skill_1"), "still carrying it")


func test_a_fold_is_never_a_combo_cancel() -> void:
	var sim := _duel("cairn", 40.0)
	var c := sim.creatures[0]
	# A light that connects, then Heavy pressed straight away: no fold out of the string.
	tap(sim, L, 0)
	var was_attacking := true
	for i in 40:
		sim.step(PackedInt32Array([H if i % 2 == 0 else 0, 0]))
		if c.move_id == "fold_heavy":
			assert_false(was_attacking, "the fold waits for the light to finish (no cancel):")
			break
		was_attacking = c.state == CreatureSim.State.ATTACK
	# Folded first, the shuriken does cancel out of a connected light.
	_press_and_settle(sim, 0, 120)  # (the press above folded it once the light was done)
	if not c.folded.has("heavy"):
		_press_and_settle(sim, H)
	assert_true(c.folded.has("heavy"), "folded in neutral")
	sim.creatures[1].pos = c.pos + Vector2(40, 0)
	var hit_once := false
	tap(sim, L, 0)
	for i in 40:
		sim.step(PackedInt32Array([H if i % 2 == 0 else 0, 0]))
		if c.move_id == "heavy":
			hit_once = true
			break
	assert_true(hit_once, "a folded shuriken cancels out of the string")


func test_the_crane_homes_toward_the_foe() -> void:
	var sim := _duel("cairn", 140.0)
	var c := sim.creatures[0]
	sim.creatures[1].pos = c.pos + Vector2(120, 50)  # off to one side
	_press_and_settle(sim, S1)  # fold
	c.facing = Vector2.RIGHT
	tap(sim, S1, 0)
	assert_true(run_until(sim, func(): return sim.projectiles.size() > 0, 30), "the crane flies")
	var start: Vector2 = sim.projectiles[0]["vel"]
	run(sim, 0, 12)
	assert_true(sim.projectiles.size() > 0, "still flying")
	var now: Vector2 = sim.projectiles[0]["vel"]
	assert_gt(now.y, start.y + 0.5, "it curves toward the foe:")
	assert_near(now.length(), start.length(), 0.001, "at the same speed:")
	var landed := run_until(sim, func(): return sim.creatures[1].is_airborne(), 60)
	assert_true(landed, "it finds them and pops them up")


func test_the_crane_stops_turning_after_its_limit() -> void:
	var sim := _duel("cairn", 140.0)
	var c := sim.creatures[0]
	_press_and_settle(sim, S1)
	sim.creatures[1].pos = c.pos + Vector2(-150, 0)  # behind him
	c.facing = Vector2.RIGHT
	tap(sim, S1, 0)
	assert_true(run_until(sim, func(): return sim.projectiles.size() > 0, 30), "")
	run(sim, 0, 40)  # past "until" (36)
	if sim.projectiles.is_empty():
		return
	var v: Vector2 = sim.projectiles[0]["vel"]
	run(sim, 0, 5)
	if sim.projectiles.is_empty():
		return
	assert_true(Vector2(sim.projectiles[0]["vel"]).is_equal_approx(v), "locked once its turn limit is up")


func test_the_shuriken_bleeds() -> void:
	var sim := _duel("cairn", 70.0)
	var c := sim.creatures[0]
	var foe := sim.creatures[1]
	_press_and_settle(sim, H)
	tap(sim, H, 0)
	assert_true(run_until(sim, func(): return foe.poison > 0, 60), "it cuts")
	assert_eq(foe.poison_look, "bleed", "a bleed, not venom:")
	var hp := foe.hp
	run(sim, 0, 160)
	assert_lt(foe.hp, hp - 3.0, "the bleed ticks:")
	assert_eq(foe.poison_look, "", "and wears off")


## Folds, then sends the frogs; returns the foe's position when the first one lands.
func _frog_at(lane_dy: float) -> Dictionary:
	var sim := _duel("cairn", 90.0)
	var c := sim.creatures[0]
	var foe := sim.creatures[1]
	_press_and_settle(sim, S2)  # fold
	foe.pos = Vector2(c.pos.x + 90.0, c.pos.y + lane_dy)
	foe.walk_vel = Vector2.ZERO
	var at := foe.pos
	tap(sim, S2, 0)
	var hit := run_until(sim, func(): return foe.slow > 0, 60)
	run(sim, 0, 20)
	return {"hit": hit, "moved": foe.pos - at, "foe": foe, "sim": sim, "c": c}


func test_the_frog_sends_three_frogs_side_by_side() -> void:
	var sim := _duel("cairn", 160.0)
	var c := sim.creatures[0]
	_press_and_settle(sim, S2)  # fold
	var x0 := c.pos.x
	tap(sim, S2, 0)
	assert_true(run_until(sim, func(): return sim.projectiles.size() == 3, 30), "three frogs")
	assert_lt(absf(c.pos.x - x0), 4.0, "he stays put; the frogs go")
	var ys: Array = []
	for p in sim.projectiles:
		ys.append(Vector2(p["pos"]).y)
	ys.sort()
	assert_near(float(ys[1]) - float(ys[0]), 18.0, 0.01, "18 px apart:")
	assert_near(float(ys[2]) - float(ys[1]), 18.0, 0.01, "18 px apart:")


## Nov 2026: every frog knocks square across its flight ("knock": "side"), toward the side
## of its line the foe stands on, so the row shoves a foe into (or keeps them in) the storm.
func test_a_frog_knocks_the_foe_sideways_toward_their_side_of_its_line() -> void:
	for dy in [4.0, -4.0, 18.0, -18.0, 22.0]:
		var r := _frog_at(dy)
		var moved := Vector2(r["moved"])
		assert_true(r["hit"], "a frog lands and slows (%s px off the middle)" % dy)
		assert_gt(moved.y * signf(dy), 6.0, "pushed out to the foe's side of the line (%s):" % dy)
		assert_lt(absf(moved.x), 1.5, "not back along the flight (%s):" % dy)
	var on := _frog_at(18.0)  # dead on an outer lane: out to that lane's side
	assert_gt(Vector2(on["moved"]).y, 6.0, "an outer frog dead on pushes out:")


## The sideways knock is the flight turned a quarter, with no trig: square to it at any angle.
func test_the_side_knock_is_perpendicular_to_the_flight() -> void:
	var sim := _duel()
	for v in [Vector2(4, 0), Vector2(3, 4), Vector2(-2.5, 1.0), Vector2(0, -4)]:
		var p := {"vel": v, "pos": Vector2(100, 100), "lane": 0}
		var left := Vector2(-v.y, v.x)
		var k: Vector2 = sim._side_knock(p, Vector2(100, 100) + left * 3.0 + v)
		assert_near(k.dot(v), 0.0, 0.0001, "square to the flight %s:" % v)
		assert_near(k.length(), 1.0, 0.0001, "a unit push:")
		assert_gt(k.dot(left), 0.0, "toward the foe's side:")
		var k2: Vector2 = sim._side_knock(p, Vector2(100, 100) - left * 3.0)
		assert_lt(k2.dot(left), 0.0, "and the other side the other way:")


## Blocking a frog still means facing where it comes from, not where it shoves.
func test_a_frog_on_the_outer_lane_is_blocked_facing_it() -> void:
	var sim := _duel("cairn", 90.0)
	var c := sim.creatures[0]
	var foe := sim.creatures[1]
	_press_and_settle(sim, S2)  # fold
	foe.pos = Vector2(c.pos.x + 90.0, c.pos.y + 18.0)
	var hp := foe.hp
	tap(sim, S2, 0, SimDefs.IN_GUARD)
	run(sim, 0, 60, SimDefs.IN_GUARD)
	assert_near(foe.hp, hp, 0.01, "blocked:")


func test_a_foe_is_hit_by_one_frog_of_the_row() -> void:
	var r := _frog_at(9.0)  # between two lanes: touched by both
	var foe: CreatureSim = r["foe"]
	assert_true(r["hit"], "one lands")
	assert_near(foe.hp, foe.max_hp - 4.0, 0.6, "the other passes by:")


## His guard answer, now that the frogs are blockable: the Shuriken held to a full charge.
func test_a_full_charge_shuriken_breaks_guard_a_tap_does_not() -> void:
	for full in [false, true]:
		var sim := _duel("cairn", 90.0)
		var c := sim.creatures[0]
		var foe := sim.creatures[1]
		_press_and_settle(sim, H)  # fold
		var hold := int(c.def["moves"]["heavy"]["charge_max"]) + 10 if full else 1
		for t in hold:
			sim.step(PackedInt32Array([H, SimDefs.IN_GUARD]))
		var broke := false
		for t in 60:
			sim.step(PackedInt32Array([0, SimDefs.IN_GUARD]))
			broke = broke or foe.state == CreatureSim.State.CRUMPLE
		assert_eq(broke, full, "full charge %s:" % full)


func test_the_frogs_can_be_blocked() -> void:
	var sim := _duel("cairn", 90.0)
	var foe := sim.creatures[1]
	_press_and_settle(sim, S2)
	var hp := foe.hp
	var st := foe.stamina
	tap(sim, S2, 0, SimDefs.IN_GUARD)
	var stunned := false
	for i in 40:
		sim.step(PackedInt32Array([0, SimDefs.IN_GUARD]))
		stunned = stunned or foe.state == CreatureSim.State.HITSTUN
	assert_lt(foe.stamina, st, "it lands on the guard")
	assert_near(foe.hp, hp, 0.001, "and takes no health (no chip):")
	assert_false(stunned, "no guard break: the guard holds")
	assert_true(foe.state == CreatureSim.State.GUARD, "still guarding")


func test_the_paper_plane_glides_far_and_through_fences() -> void:
	var sim := _duel("cairn", 200.0)
	var c := sim.creatures[0]
	var cell := sim.terrain.world_to_cell(c.pos + Vector2(30, 0))
	for dy in range(-3, 4):
		sim.terrain.set_cell(cell + Vector2i(0, dy), TerrainGrid.FENCE)
	var x0 := c.pos.x
	tap(sim, SimDefs.IN_DODGE | SimDefs.IN_RIGHT, 30)
	assert_gt(c.pos.x - x0, 60.0, "a long glide, over the fence:")


## Since Oct 2026 Thousand Cranes costs no paper (Kevin): a full meter is all it takes.
func test_thousand_cranes_needs_only_a_full_meter() -> void:
	var sim := _duel("cairn", 100.0)
	var c := sim.creatures[0]
	c.energy = CreatureSim.MAX_ENERGY
	c.sheets = 0
	assert_true(c.can_use("surge"), "no sheets needed, just the meter")
	c.energy = CreatureSim.MAX_ENERGY - 1.0
	assert_false(c.can_use("surge"), "the meter still has to be full")
	c.energy = CreatureSim.MAX_ENERGY
	c.sheets = 2
	tap(sim, SU, 0)
	assert_eq(c.move_id, "surge", "")
	assert_eq(c.sheets, 2, "and it leaves his sheets alone:")


func test_the_storm_pulses_then_pushes_out_and_cracks_a_ring() -> void:
	var sim := _duel("cairn", 100.0)
	var c := sim.creatures[0]
	var foe := sim.creatures[1]
	c.energy = CreatureSim.MAX_ENERGY
	# Held to a full charge: the bundle lands near the foe.
	for i in 60:
		sim.step(PackedInt32Array([SU, 0]))
		if not c.charging and c.state == CreatureSim.State.ATTACK and c.state_t > 2:
			break
	assert_true(run_until(sim, func(): return sim.storms.size() > 0, 120), "a storm where it lands")
	var st: Dictionary = sim.storms[0]
	foe.pos = st["pos"] + Vector2(8, 0)
	foe.walk_vel = Vector2.ZERO
	var hits := 0
	var ended := false
	var slowed := false
	for i in 300:  # 120 storm ticks, plus the hitstop each pulse adds
		sim.step(PackedInt32Array([0, 0]))
		for e in sim.events:
			if e["type"] == "hit" and int(e["attacker"]) == 0:
				hits += 1
			if e["type"] == "storm_end":
				ended = true
		if foe.slow > 0:
			slowed = true
		if ended:
			break
	assert_true(slowed, "the storm slows whoever stands in it")
	assert_true(ended, "it ends")
	assert_gt(float(hits), 4.0, "it hit them again and again:")
	var cracked := 0
	var at: Vector2 = st["pos"]
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var cl := sim.terrain.world_to_cell(at) + Vector2i(dx, dy)
			var d := sim.terrain.cell_center(cl).distance_to(at)
			if d >= 70.0 and d <= 95.0 and sim.terrain.get_cell(cl) == TerrainGrid.CRACKED:
				cracked += 1
	assert_gt(float(cracked), 8.0, "a ring of cracked floor:")


## Thousand Cranes locks on: aimed near a foe (within the "lock_on" cone and the longest
## throw), even a tap lands the storm on them; aimed at empty floor, it goes as far as
## it was held. Hidden foes aren't locked onto.
func _storm_at(sim: MatchSim, hold: int, aim_bits := 0) -> Vector2:
	var c := sim.creatures[0]
	c.energy = CreatureSim.MAX_ENERGY
	for i in hold:
		sim.step(PackedInt32Array([SU | aim_bits, 0]))
	assert_true(run_until(sim, func(): return sim.storms.size() > 0, 160), "a storm lands")
	return sim.storms[0]["pos"] if sim.storms.size() > 0 else Vector2.INF


func test_thousand_cranes_locks_onto_the_foe_it_points_at() -> void:
	var sim := _duel("cairn", 150.0)
	var foe := sim.creatures[1].pos
	assert_lt(_storm_at(sim, 1).distance_to(foe), 6.0, "a tap lands on a foe 150 px away:")
	# A little off the line (about 15 degrees), still locked: it bends onto them.
	sim = _duel("cairn", 150.0)
	sim.creatures[1].pos += Vector2(0, 38)
	foe = sim.creatures[1].pos
	assert_lt(_storm_at(sim, 1).distance_to(foe), 6.0, "slightly off the line, it still lands on them:")


func test_thousand_cranes_aimed_away_goes_where_it_points() -> void:
	var sim := _duel("cairn", 150.0)
	var c := sim.creatures[0]
	var start := c.pos
	var at := _storm_at(sim, 1, SimDefs.aim_bits(Vector2.UP) | SimDefs.IN_UP)
	assert_lt(at.y, start.y - 60.0, "aimed up, away from the foe: it flies up")
	var pr: Dictionary = c.moves()["surge"]["projectile"]
	assert_lt(absf(start.distance_to(at) - float(pr["range"]) - float(pr["offset"])), 6.0,
		"a tap with nothing locked is the shortest throw:")


func test_thousand_cranes_doesnt_lock_onto_far_or_hidden_foes() -> void:
	var sim := _duel("cairn", 320.0)
	var c := sim.creatures[0]
	var pr: Dictionary = c.moves()["surge"]["projectile"]
	assert_eq(sim.lob_lock(c, pr), null, "too far: no lock")
	sim = _duel("pete", 150.0)
	c = sim.creatures[0]
	assert_eq(sim.lob_lock(c, pr), sim.creatures[1], "in range and in the aim: locked")
	sim.creatures[1].stealth = 100
	assert_eq(sim.lob_lock(c, pr), null, "a foe in stealth isn't")
	sim.creatures[1].stealth = 0
	sim.creatures[1].covered = true
	assert_eq(sim.lob_lock(c, pr), null, "nor one hidden in brush")


func test_it_all_rolls_back() -> void:
	var sim := _duel("cairn", 90.0)
	var c := sim.creatures[0]
	c.energy = CreatureSim.MAX_ENERGY
	tap(sim, S1, 6)  # mid-fold
	var snap := sim.snapshot()
	var digest := sim.state_digest()
	var inputs: Array = []
	for i in 400:
		inputs.append(PackedInt32Array([[S1, H, 0, SU, L, S2, 0, 0][(i / 7) % 8] if i % 3 == 0 else 0, 0]))
	for ins in inputs:
		sim.step(ins)
	var later := sim.state_digest()
	sim.restore(snap)
	assert_eq(sim.state_digest(), digest, "back to mid-fold:")
	for ins in inputs:
		sim.step(ins)
	assert_eq(sim.state_digest(), later, "the same 400 ticks again:")


## The Paper Plane used to match Chef Cerebro's blink (116 px); his blink went to 90 px in
## the Oct 2026 assassin pass and the plane was left alone (no mage changes beyond that nerf).
func test_the_paper_plane_glides_at_least_as_far_as_cerebros_blink() -> void:
	var dist := {}
	for id in ["cerebro", "crease"]:
		var sim := MatchFactory.training(id)
		var c := sim.creatures[0]
		sim.creatures[1].pos = Vector2(100, 250)
		c.pos = Vector2(150, 120)
		var x0 := c.pos.x
		run(sim, SimDefs.IN_DODGE | SimDefs.IN_RIGHT, 1)
		run(sim, 0, 30)
		dist[id] = c.pos.x - x0
	assert_gt(float(dist["crease"]), float(dist["cerebro"]) - 1.0, "at least as far:")
	assert_near(float(dist["crease"]), 116.0, 1.0, "the plane still glides about 116 px:")


## Thousand Cranes, Nov 2026: a pulse knocks up a foe standing in the storm's center
## ("center_launch"), once per foe per storm; every other pulse, and the last hit, slows.
func _storm_on_foe() -> MatchSim:
	var sim := _duel("cairn", 150.0)
	var at := _storm_at(sim, 1)
	assert_lt(at.distance_to(sim.creatures[1].pos), 6.0, "the storm lands on the foe")
	return sim


## Steps until the storm ends (at most `ticks`), counting the times `foe` goes up.
func _airborne_edges(sim: MatchSim, foe: CreatureSim, ticks: int) -> int:
	var ups := 0
	var was := foe.state == CreatureSim.State.AIRBORNE
	for i in ticks:
		if sim.storms.is_empty():
			break  # (stops the tick the storm ends)
		sim.step(PackedInt32Array([0, 0]))
		var now := foe.state == CreatureSim.State.AIRBORNE
		if now and not was:
			ups += 1
		was = now
	return ups


func test_the_storm_center_knocks_up_once_on_the_first_pulse_then_slows() -> void:
	var sim := _storm_on_foe()
	var foe := sim.creatures[1]
	var st: Dictionary = sim.storms[0]
	foe.slow = 0
	assert_true(run_until(sim, func(): return foe.state == CreatureSim.State.AIRBORNE, 30), "the first pulse knocks them up")
	assert_eq(int(st["t"]), int(st["every"]), "on the first pulse:")
	assert_eq(foe.slow, 0, "a knock-up, not a slow:")
	assert_eq((st["launched"] as Array), [foe.id], "remembered by the storm:")
	# Bring them down early, still in the center, and let them get up.
	foe.air_total = foe.air_t + 1
	assert_true(run_until(sim, func(): return foe.state != CreatureSim.State.AIRBORNE \
		and foe.state != CreatureSim.State.KNOCKDOWN and foe.invuln == 0, 80), "back on their feet")
	foe.pos = st["pos"]
	foe.slow = 0
	var ups := _airborne_edges(sim, foe, 300)
	assert_eq(ups, 0, "never knocked up again by this storm:")
	assert_true(sim.storms.is_empty(), "the storm ran out")
	assert_gt(float(foe.slow), 0.0, "the later pulses and the last hit slow them:")


func test_outside_the_center_the_storm_only_slows() -> void:
	var sim := _storm_on_foe()
	var foe := sim.creatures[1]
	var st: Dictionary = sim.storms[0]
	foe.pos = Vector2(st["pos"]) + Vector2(40, 0)
	foe.slow = 0
	assert_true(run_until(sim, func(): return foe.slow > 0, 30), "a pulse slows them")
	var ups := _airborne_edges(sim, foe, 300)
	assert_eq(ups, 0, "never knocked up outside the center:")
	assert_true(sim.storms.is_empty(), "the storm ran out")
	assert_true(not (st["launched"] as Array).has(foe.id), "")


func test_walking_into_the_center_knocks_up_on_the_next_pulse_and_rolls_back() -> void:
	var sim := _storm_on_foe()
	var foe := sim.creatures[1]
	var st: Dictionary = sim.storms[0]
	foe.pos = Vector2(st["pos"]) + Vector2(40, 0)
	assert_true(run_until(sim, func(): return int(sim.storms[0]["t"]) > 25, 60), "two pulses outside")
	assert_true(foe.state != CreatureSim.State.AIRBORNE, "only slowed so far")
	var snap := sim.snapshot()
	var digest := sim.state_digest()
	foe.pos = st["pos"]  # into the center
	foe.walk_vel = Vector2.ZERO
	assert_true(run_until(sim, func(): return foe.state == CreatureSim.State.AIRBORNE, 20), "knocked up on the next pulse")
	assert_eq((sim.storms[0]["launched"] as Array), [foe.id], "")
	var later := sim.state_digest()
	sim.restore(snap)
	assert_eq(sim.state_digest(), digest, "rolled back to before:")
	assert_eq((sim.storms[0]["launched"] as Array), [], "the storm forgets the knock-up:")
	sim.creatures[1].pos = Vector2(sim.storms[0]["pos"])
	sim.creatures[1].walk_vel = Vector2.ZERO
	assert_true(run_until(sim, func(): return sim.creatures[1].state == CreatureSim.State.AIRBORNE, 20), "and again")
	assert_eq(sim.state_digest(), later, "the same ticks again:")


## Nov 2026 balance pass: every crowd control of his lasts long enough to follow up. The
## window: the move's recovery, then fold the follow-up craft (fold startup + recovery),
## its windup from neutral, its startup, its flight to 110 px, plus 15 ticks of reaction.
func _follow_up(mv: Dictionary) -> int:
	var fd: Dictionary = mv["fold"]
	return int(fd["startup"]) + int(fd["recovery"]) + int(mv.get("windup", 0)) + int(mv["startup"]) \
		+ int(ceilf(110.0 / float(mv["projectile"]["speed"])))


func test_every_crowd_control_lasts_long_enough_to_follow_up() -> void:
	var m: Dictionary = MatchFactory.versus("crease", "cairn").creatures[0].def["moves"]
	var shuriken := _follow_up(m["heavy"])
	var crane := _follow_up(m["skill_1"])
	var frog := _follow_up(m["skill_2"])
	const REACT := 15
	# Paper Frog's slow -> Paper Crane.
	var w := int(m["skill_2"]["recovery"]) + crane + REACT
	assert_gt(float(m["skill_2"]["slow_ticks"]) + 0.5, float(w), "frog slow >= its window:")
	# Paper Crane's pop-up (and its float on a foe already up) -> Paper Shuriken.
	w = int(m["skill_1"]["recovery"]) + shuriken + REACT
	assert_gt(float(m["skill_1"]["launch"]) + 0.5, float(w), "crane launch >= its window:")
	assert_gt(float(m["skill_1"]["juggle_float"]) + 0.5, float(w), "crane float >= its window:")
	# Paper Shuriken's stagger -> Paper Crane.
	w = int(m["heavy"]["recovery"]) + crane + REACT
	assert_gt(float(m["heavy"]["hitstun"]) + 0.5, float(w), "shuriken hitstun >= its window:")
	assert_gt(float(m["heavy"]["hitstun_charged"]) + 0.5, float(w), "charged too:")
	# Thousand Cranes: the storm's slow -> Paper Frog; its center knock-up -> Paper Crane.
	var su: Dictionary = m["surge"]
	w = int(su["recovery"]) + frog + REACT
	assert_gt(float(su["slow_ticks"]) + 0.5, float(w), "storm slow >= its window:")
	w = int(su["recovery"]) + crane + REACT
	assert_gt(float(su["projectile"]["storm"]["center_launch"]["launch"]) + 0.5, float(w), "center knock-up >= its window:")
	assert_false(su["projectile"]["storm"].has("launch_end"), "the last hit doesn't knock up any more")
