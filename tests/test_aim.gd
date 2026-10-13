extends TestCase
## Steering attacks: each hit of a light string can turn, lights re-aim during their
## startup, and raw big moves stay committed to the way their windup pointed.

const L := SimDefs.IN_LIGHT
const S1 := SimDefs.IN_SKILL1
const UP := SimDefs.IN_UP
const DOWN := SimDefs.IN_DOWN
const RIGHT := SimDefs.IN_RIGHT


## Presses `bit` (holding `dir`) on alternate ticks until creature 0 starts `move_id`.
func _mash(sim: MatchSim, bit: int, dir: int, move_id: String) -> bool:
	var c := sim.creatures[0]
	var serial := c.attack_serial
	for i in 120:
		sim.step(PackedInt32Array([(bit if i % 2 == 0 else 0) | dir, 0]))
		if c.attack_serial != serial and c.move_id == move_id:
			return true
	return false


func test_the_next_hit_of_a_string_turns_to_the_held_direction() -> void:
	var sim := MatchFactory.training("cairn")
	var cairn := sim.creatures[0]
	cairn.facing = Vector2.RIGHT
	assert_true(_mash(sim, L, 0, "light_1"), "first jab")
	assert_eq(cairn.facing, Vector2.RIGHT, "jab goes right:")
	assert_true(_mash(sim, L, UP, "light_2"), "second jab, holding up")
	assert_eq(cairn.facing, Vector2.UP, "the second jab turned up:")


func test_a_light_can_be_steered_during_its_startup() -> void:
	var sim := MatchFactory.training("cairn")
	var cairn := sim.creatures[0]
	cairn.facing = Vector2.RIGHT
	sim.step(PackedInt32Array([L, 0]))
	assert_eq(cairn.move_id, "light_1")
	sim.step(PackedInt32Array([DOWN, 0]))
	assert_eq(cairn.facing, Vector2.DOWN, "held down during startup:")


func test_a_string_can_switch_to_a_target_above() -> void:
	var sim := MatchFactory.training("cairn")
	var cairn := sim.creatures[0]
	var dummy := sim.creatures[1]
	cairn.pos = Vector2(240, 170)
	cairn.facing = Vector2.RIGHT
	dummy.pos = Vector2(240, 170 - cairn.radius - dummy.radius - 2)
	assert_true(_mash(sim, L, 0, "light_1"), "jab to the right, at nothing")
	var hit := false
	for i in 120:
		sim.step(PackedInt32Array([(L if i % 2 == 0 else 0) | UP, 0]))
		for e in sim.events:
			if e["type"] == "hit" and int(e["target"]) == 1:
				hit = true
		if hit:
			break
	assert_true(hit, "turning up mid-string should hit the dummy above")


func test_after_the_strike_the_direction_holds_until_the_next_move() -> void:
	var sim := MatchFactory.training("cairn")
	var cairn := sim.creatures[0]
	cairn.facing = Vector2.RIGHT
	sim.step(PackedInt32Array([L, 0]))
	var su := int(cairn.move_def()["startup"])
	run(sim, 0, su + 2)  # now active or recovering
	run(sim, UP, 3)
	assert_eq(cairn.facing, Vector2.RIGHT, "a swing already out doesn't turn:")


func test_a_raw_windup_move_stays_committed() -> void:
	var sim := MatchFactory.training("craglash")
	var crag := sim.creatures[0]
	crag.facing = Vector2.RIGHT
	sim.step(PackedInt32Array([S1, 0]))
	assert_true(crag.is_winding_up(), "raw Landslide Charge winds up")
	run(sim, UP, 12)
	assert_eq(crag.facing, Vector2.RIGHT, "the Lash still goes where its tell pointed:")
