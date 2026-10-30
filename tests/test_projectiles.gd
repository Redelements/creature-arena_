extends TestCase
## Projectile hit size (data/rules/projectiles.json): every straight shot's radius ×
## radius_mult, lobs left alone, and the hooks (Gulp, Mountain Maw, Cast Line) widening over their
## flight to "radius_end" at the end of their reach.

const L := SimDefs.IN_LIGHT


## `id` in training facing right at the dummy, `dy` px off the line of fire and far
## enough away that a shot gets there.
func _range(id: String, dy: float, dx := 90.0) -> MatchSim:
	var sim := MatchFactory.training(id)
	sim.creatures[0].pos = Vector2(200, 164)
	sim.creatures[0].facing = Vector2.RIGHT
	sim.creatures[1].pos = Vector2(200 + dx, 164 + dy)
	return sim


## Presses `bit` (aimed right) and steps until a projectile is out.
func _throw(sim: MatchSim, bit: int) -> Dictionary:
	var aim := SimDefs.IN_AIM | (0 << SimDefs.AIM_SHIFT)  # aim index 0: straight right
	sim.step(PackedInt32Array([bit | aim, 0]))
	for i in 40:
		if not sim.projectiles.is_empty():
			return sim.projectiles[0]
		sim.step(PackedInt32Array([aim, 0]))
	return {}


func test_a_straight_shot_is_wider_by_the_multiplier() -> void:
	var mult := MatchSim.projectile_radius_mult()
	assert_gt(mult, 1.0, "shots are made wider:")
	var sim := _range("cerebro", 60.0)
	var pr := _throw(sim, L)
	assert_false(pr.is_empty(), "the knife flies")
	var want := float(sim.creatures[0].moves()["light_1"]["projectile"]["radius"]) * mult
	assert_near(float(pr["radius"]), want, 0.001, "its hit radius:")


func test_a_shot_that_used_to_graze_past_now_lands() -> void:
	var sim0 := _range("cerebro", 0.0)
	var base := float(sim0.creatures[0].moves()["light_1"]["projectile"]["radius"])
	var d_radius := sim0.creatures[1].radius
	# Off the line by more than the old reach, less than the new one.
	var sim := _range("cerebro", base + d_radius + 1.5)
	var d := sim.creatures[1]
	_throw(sim, L)
	run(sim, 0, 30)
	assert_lt(d.hp, d.max_hp, "the wider knife catches it")


func test_a_lob_keeps_its_burst() -> void:
	var sim := _range("barkley", 60.0)
	var pr := _throw(sim, SimDefs.IN_SKILL2)
	assert_false(pr.is_empty(), "the pinecone flies")
	assert_true(bool(pr.get("lob", false)), "a lob")
	assert_near(float(pr["radius"]), float(sim.creatures[0].moves()["skill_2"]["projectile"].get("radius", 0.0)), 0.001,
		"not scaled:")


func test_the_hooks_widen_to_the_end_of_their_reach() -> void:
	var mult := MatchSim.projectile_radius_mult()
	for pair in [["culvert", SimDefs.IN_SKILL1, "skill_1"], ["craglash", SimDefs.IN_SKILL2, "skill_2"],
			["gillbert", SimDefs.IN_SKILL2, "skill_2"]]:
		var sim := _range(String(pair[0]), 120.0)  # the dummy well off the line: nothing to hit
		var p: Dictionary = sim.creatures[0].moves()[pair[2]]["projectile"]
		var pr := _throw(sim, int(pair[1]))
		assert_false(pr.is_empty(), "%s's hook flies" % pair[0])
		if pr.is_empty():
			continue
		var r0 := float(p["radius"]) * mult
		var r1 := float(p["radius_end"]) * mult
		assert_gt(r1, r0, "%s: wider at the end than at the start:" % pair[0])
		var last := float(pr["radius"])
		assert_lt(last, r0 + (r1 - r0) * 0.25, "%s: starts narrow:" % pair[0])
		while not sim.projectiles.is_empty():
			pr = sim.projectiles[0]
			assert_true(float(pr["radius"]) >= last - 0.0001, "%s: never narrows" % pair[0])
			last = float(pr["radius"])
			sim.step(PackedInt32Array([0, 0]))
		assert_gt(last, r0 + (r1 - r0) * 0.8, "%s: near radius_end at full reach:" % pair[0])


func test_a_growing_hook_survives_a_rollback() -> void:
	var sim := _range("culvert", 120.0)
	_throw(sim, SimDefs.IN_SKILL1)
	run(sim, 0, 3)
	var snap := sim.snapshot()
	var r := float(sim.projectiles[0]["radius"])
	run(sim, 0, 4)
	sim.restore(snap)
	assert_near(float(sim.projectiles[0]["radius"]), r, 0.0001, "restored:")
	run(sim, 0, 4)
	var again := float(sim.projectiles[0]["radius"]) if not sim.projectiles.is_empty() else -1.0
	sim.restore(snap)
	run(sim, 0, 4)
	var third := float(sim.projectiles[0]["radius"]) if not sim.projectiles.is_empty() else -1.0
	assert_near(again, third, 0.0001, "and grows the same way again:")
