extends TestCase
## Mister Crease's kit: Paper Stock (three sheets that regrow), fold-then-use crafts (a
## first press folds, a second uses), the homing Paper Crane, the Paper Frog leap, the
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


func test_the_frog_leaps_over_a_pit_and_slows_where_it_lands() -> void:
	var sim := _duel("cairn", 110.0)
	var c := sim.creatures[0]
	var foe := sim.creatures[1]
	var mid := sim.terrain.world_to_cell(c.pos + Vector2(50, 0))
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			sim.terrain.set_cell(mid + Vector2i(dx, dy), TerrainGrid.HOLE)
	_press_and_settle(sim, S2)  # fold
	var x0 := c.pos.x
	tap(sim, S2, 0)
	assert_true(run_until(sim, func(): return c.is_leaping(), 20), "the leap")
	assert_true(c.is_invulnerable(), "untouchable in the air")
	assert_true(run_until(sim, func(): return foe.slow > 0, 40), "lands on them and slows them")
	assert_true(c.state != CreatureSim.State.FALLING, "the pit didn't take him")
	assert_gt(c.pos.x - x0, 90.0, "about 110 px:")


func test_the_paper_plane_glides_far_and_through_fences() -> void:
	var sim := _duel("cairn", 200.0)
	var c := sim.creatures[0]
	var cell := sim.terrain.world_to_cell(c.pos + Vector2(30, 0))
	for dy in range(-3, 4):
		sim.terrain.set_cell(cell + Vector2i(0, dy), TerrainGrid.FENCE)
	var x0 := c.pos.x
	tap(sim, SimDefs.IN_DODGE | SimDefs.IN_RIGHT, 30)
	assert_gt(c.pos.x - x0, 60.0, "a long glide, over the fence:")


func test_thousand_cranes_needs_three_sheets_and_a_full_meter() -> void:
	var sim := _duel("cairn", 100.0)
	var c := sim.creatures[0]
	c.energy = CreatureSim.MAX_ENERGY
	c.sheets = 2
	assert_false(c.can_use("surge"), "two sheets aren't enough")
	c.sheets = 3
	assert_true(c.can_use("surge"), "three and a full meter")
	tap(sim, SU, 0)
	assert_eq(c.move_id, "surge", "")
	assert_eq(c.sheets, 0, "it spends all three:")


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
	for i in 300:  # 120 storm ticks, plus the hitstop each pulse adds
		sim.step(PackedInt32Array([0, 0]))
		for e in sim.events:
			if e["type"] == "hit" and int(e["attacker"]) == 0:
				hits += 1
			if e["type"] == "storm_end":
				ended = true
		if ended:
			break
	assert_true(ended, "it ends")
	assert_gt(float(hits), 4.0, "it hit them again and again:")
	var cracked := 0
	var at: Vector2 = st["pos"]
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var cl := sim.terrain.world_to_cell(at) + Vector2i(dx, dy)
			var d := sim.terrain.cell_center(cl).distance_to(at)
			if d >= 36.0 and d <= 54.0 and sim.terrain.get_cell(cl) == TerrainGrid.CRACKED:
				cracked += 1
	assert_gt(float(cracked), 8.0, "a ring of cracked floor:")


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


func test_the_paper_plane_glides_as_far_as_cerebros_blink() -> void:
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
	assert_near(float(dist["crease"]), float(dist["cerebro"]), 1.0, "the same distance:")
