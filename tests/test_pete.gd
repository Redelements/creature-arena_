extends TestCase
## Sneaky Pete's kit: Tiptoe goes invisible and quicker (an attack or a hit gives him
## away), Pickpocket dashes through a foe and steals some of their attack power, and The
## Big Heist vanishes and reappears behind the foe for a flurry.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE


func _duel(foe := "cairn", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus("pete", foe)
	sim.creatures[0].pos = Vector2(200, 164)
	sim.creatures[1].pos = Vector2(200 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


func _count(sim: MatchSim, kind: String, ticks: int, p0 := 0, p1 := 0) -> int:
	var n := 0
	for i in ticks:
		sim.step(PackedInt32Array([p0, p1]))
		for e in sim.events:
			if String(e["type"]) == kind:
				n += 1
	return n


func test_tiptoe_goes_invisible_and_quicker() -> void:
	var sim := _duel("cairn", 120.0)
	var pete := sim.creatures[0]
	var normal := pete.walk_speed()
	tap(sim, S1, 30)
	assert_gt(float(pete.stealth), 0.0, "invisible")
	assert_gt(pete.walk_speed(), normal * 1.3, "and quicker:")


func test_attacking_gives_him_away() -> void:
	var sim := _duel("cairn", 120.0)
	var pete := sim.creatures[0]
	tap(sim, S1, 30)
	tap(sim, L, 2)
	assert_gt(pete.stealth, 0, "the jab's startup is still hidden (the ambush):")
	run(sim, 0, int(pete.def["moves"]["light_1"]["startup"]))
	assert_eq(pete.stealth, 0, "the strike coming out ends the stealth:")


func test_a_hit_gives_him_away() -> void:
	var sim := _duel("cairn", 4.0)
	var pete := sim.creatures[0]
	pete.stealth = 100
	run_until(sim, func(): return pete.state == CreatureSim.State.HITSTUN, 40, 0, L)
	assert_eq(pete.stealth, 0, "caught: visible again:")


func test_the_cpu_chases_where_it_last_saw_him() -> void:
	var sim := _duel("cairn", 60.0)
	var pete := sim.creatures[0]
	var cpu := CpuController.new(1, 1, 3)
	for i in 25:
		sim.step(PackedInt32Array([S1 if i == 0 else 0, cpu.bits(sim)]))
	pete.pos = Vector2(200, 260)  # he slips away down the arena
	var foe := sim.creatures[1]
	var y0 := foe.pos.y
	for i in 40:
		sim.step(PackedInt32Array([0, cpu.bits(sim)]))
	assert_lt(absf(foe.pos.y - y0), 12.0, "Cairn doesn't follow him down: it can't see him")


func test_pickpocket_dashes_through_and_steals_power() -> void:
	var sim := _duel("cairn", 30.0)
	var pete := sim.creatures[0]
	var foe := sim.creatures[1]
	var x0 := foe.pos.x
	assert_eq(_count(sim, "steal", 40, S2), 1, "Pickpocket steals:")
	assert_gt(pete.pos.x, x0, "and dashes right past him")
	var st := float(pete.def["moves"]["skill_2"]["steal"])
	assert_near(pete.atk_mult, 1.0 + st, 0.001, "Pete hits harder:")
	assert_near(foe.atk_mult, 1.0 - st, 0.001, "Cairn hits softer:")
	run(sim, 0, int(pete.def["moves"]["skill_2"]["steal_ticks"]))
	assert_near(pete.atk_mult, 1.0, 0.001, "until it wears off:")


func test_stolen_power_changes_damage() -> void:
	var sim := _duel("cairn", 2.0)
	var pete := sim.creatures[0]
	var foe := sim.creatures[1]
	pete.atk_buff = 200
	pete.atk_mult = 1.2
	var hp := foe.hp
	run_until(sim, func(): return foe.hp < hp, 20, L)
	var jab := float(pete.def["moves"]["light_1"]["damage"])
	assert_near(hp - foe.hp, jab * 1.2, 0.01, "a jab with stolen power:")


func test_big_heist_reappears_behind_the_foe() -> void:
	var sim := _duel("cairn", 60.0)
	var pete := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.facing = Vector2.LEFT  # Cairn watches him
	pete.energy = 100.0
	var blinked := 0
	var hits := 0
	var behind := false
	for i in 110:
		sim.step(PackedInt32Array([SU if i < 4 else 0, 0]))
		for e in sim.events:
			if String(e["type"]) == "blink":
				blinked += 1
				behind = pete.pos.x > foe.pos.x and pete.facing.x < 0.0
			elif String(e["type"]) == "hit":
				hits += 1
	assert_eq(blinked, 1, "he vanishes and reappears:")
	assert_true(behind, "behind Cairn, facing his back")
	assert_gt(float(hits), 4.0, "and robs him with a flurry")


func test_big_heist_never_lands_in_a_pit() -> void:
	var sim := _duel("cairn", 60.0)
	var pete := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.facing = Vector2.LEFT
	var behind := foe.pos + Vector2(foe.radius + pete.radius + 2.0, 0)
	sim.terrain.set_cell(sim.terrain.world_to_cell(behind), TerrainGrid.HOLE)
	pete.energy = 100.0
	_count(sim, "blink", 60, SU)
	assert_false(sim.terrain.is_hole_at(pete.pos), "he picks the other side instead")


func test_rollback_with_stealth_and_steal() -> void:
	var sim := _duel("culvert", 30.0)
	var foe := sim.creatures[1]
	foe.atk_buff = 100
	foe.atk_mult = 0.8
	run(sim, S1, 1)
	run(sim, 0, 10)
	var snap := sim.snapshot()
	run(sim, 0, 80, L)
	var once := sim.state_digest()
	sim.restore(snap)
	run(sim, 0, 80, L)
	assert_eq(sim.state_digest(), once, "replaying from the snapshot gives the same state:")
