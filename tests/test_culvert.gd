extends TestCase
## Culvert's reworked kit: Gulp as a tongue hook (tapped) or a swallow (held), the Slam
## block clear of his own feet, and the long roll.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const D := SimDefs.IN_DODGE


## Culvert on the left, `foe` to the right with `gap` px between their bodies.
func _duel(foe := "cairn", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus("culvert", foe)
	var y := SimDefs.floor_rect().get_center().y
	sim.creatures[0].pos = Vector2(160, y)
	sim.creatures[1].pos = Vector2(160 + sim.creatures[0].radius + sim.creatures[1].radius + gap, y)
	return sim


func _events(sim: MatchSim, kind: String) -> Array:
	return sim.events.filter(func(e): return String(e["type"]) == kind)


func test_a_tapped_gulp_hooks_from_three_times_the_old_reach_and_hauls_them_in() -> void:
	var sim := _duel("cairn", 60.0)
	var culv := sim.creatures[0]
	var cairn := sim.creatures[1]
	assert_gt(culv.move_range("skill_1"), 78.0, "the tongue reaches about three times the old 26 px:")
	run(sim, S1, 1)  # a tap
	var hooked := run_until(sim, func(): return not _events(sim, "hook").is_empty(), 60)
	assert_true(hooked, "the tongue hooks Cairn from 60 px away")
	assert_eq(cairn.state, CreatureSim.State.HITSTUN, "hooked: stunned")
	run(sim, 0, 20)
	assert_lt(cairn.pos.x - culv.pos.x, 34.0, "and hauled in next to him (bodies 23 px apart when touching):")
	assert_near(cairn.max_hp - cairn.hp, 6.0, 0.001, "hook damage:")


func test_a_held_gulp_swallows_and_spits_them_out_behind() -> void:
	var sim := _duel("cairn", 60.0)
	var culv := sim.creatures[0]
	var cairn := sim.creatures[1]
	var grabbed := run_until(sim, func(): return not _events(sim, "swallow").is_empty(), 80, S1)
	assert_true(grabbed, "a held tongue swallows Cairn")
	assert_true(_events(sim, "hook").is_empty(), "no hook when held")
	assert_near(cairn.max_hp - cairn.hp, 12.0, 0.001, "swallow damage:")
	assert_gt(cairn.swallow_t, 0, "inside him:")
	assert_eq(cairn.pos, culv.pos, "carried along inside him:")
	assert_true(cairn.is_invulnerable(), "and out of reach while he is")
	var pooped := run_until(sim, func(): return not _events(sim, "poop").is_empty(), 40)
	assert_true(pooped, "out the back end")
	assert_lt(cairn.pos.x, culv.pos.x - culv.radius, "behind him:")
	run(sim, 0, 30)
	assert_lt(cairn.pos.x, culv.pos.x - culv.radius - cairn.radius, "skidding away behind him:")
	assert_gt(culv.facing.x, 0.0, "he doesn't even turn round")


func test_the_tongue_reaches_half_as_far_again_in_the_same_time() -> void:
	# 87 px (offset 14 + 5 px a tick for 13 ticks + an 8 px tip) became about 130 px,
	# still out and back in 13 ticks: it flies faster, not longer. The Oct 2026 kit pass
	# fattened the tip (radius 12, 20 at the end) so it is easier to land: about 134 px.
	var p: Dictionary = MatchFactory.load_def("culvert")["moves"]["skill_1"]["projectile"]
	assert_eq(int(p["life"]), 13, "same travel time (ticks):")
	var reach := float(p["offset"]) + float(p["speed"]) * float(p["life"]) + float(p["radius"])
	assert_near(reach, 87.0 * 1.5 + 4.0, 1.0, "reach (px):")


func test_sidestepping_the_tongue_beats_it() -> void:
	var sim := _duel("cairn", 40.0)
	var cairn := sim.creatures[1]
	sim.step(PackedInt32Array([S1, 0]))
	run(sim, 0, 12)  # a reaction's worth
	run(sim, 0, 1, D | SimDefs.IN_UP)
	run(sim, 0, 60)
	assert_eq(cairn.hp, cairn.max_hp, "a roll out of the lane takes nothing:")


func test_slam_cracks_a_wall_in_front_and_never_under_his_own_feet() -> void:
	var sim := MatchFactory.training()
	var culv := sim.creatures[0]
	for i in 2:  # a second Slam opens the block
		tap(sim, H, 40)
	assert_false(sim.terrain.is_hole_at(culv.pos), "he isn't standing over his own hole")
	assert_eq(culv.state != CreatureSim.State.FALLING, true, "and doesn't fall in")
	var holes := 0
	var xs: Array = []
	var ys: Array = []
	for cy in sim.terrain.rows:
		for cx in sim.terrain.cols:
			if sim.terrain.get_cell(Vector2i(cx, cy)) == TerrainGrid.HOLE:
				holes += 1
				xs.append(cx)
				ys.append(cy)
	assert_eq(holes, 25, "a 5 by 5 block:")
	assert_eq(xs.max() - xs.min() + 1, 5, "5 deep (along his facing)")
	assert_eq(ys.max() - ys.min() + 1, 5, "5 across")
	var near_edge: float = SimDefs.GRID_X + int(xs.min()) * SimDefs.CELL
	assert_gt(near_edge - culv.pos.x, culv.radius, "the near edge is past his body:")


func test_the_roll_goes_twice_as_far_in_the_same_time() -> void:
	var sim := _duel("cairn", 80.0)
	var culv := sim.creatures[0]
	var dg: Dictionary = culv.def["dodge"]
	var start := culv.pos
	run(sim, D | SimDefs.IN_RIGHT, 1)
	run(sim, 0, int(dg["frames"]))
	assert_eq(culv.state, CreatureSim.State.IDLE, "the roll lasts its 20 frames")
	assert_gt(culv.pos.x - start.x, 90.0, "and covers twice what 3 px a tick did:")


## The CPU holds Gulp to a full charge some of the time, so it swallows too. (It throws
## Gulp mostly to open a guard, so the opponent is a tank that guards.)
func test_cpu_culvert_swallows_sometimes() -> void:
	var swallows := 0
	var hooks := 0
	for s in 6:
		var sim := MatchFactory.versus("culvert", "craglash")
		var cpus := [CpuController.new(0, CpuController.RAGE, 40 + s * 7), CpuController.new(1, 2, 90 + s * 13)]
		for t in 3600:
			sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
			for e in sim.events:
				if int(e.get("attacker", -1)) == 0:
					swallows += 1 if String(e["type"]) == "swallow" else 0
					hooks += 1 if String(e["type"]) == "hook" else 0
			if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
				break
	assert_gt(float(swallows), 0.0, "swallows (hooks: %d):" % hooks)
	assert_gt(float(hooks), 0.0, "and still hooks")


## Storm Drain's pits start just past his body, so a fighter swallowed straight after
## comes out the back end into a pit.
func test_storm_drain_then_a_swallow_poops_them_into_a_pit() -> void:
	var sim := MatchFactory.versus("culvert", "cairn")
	var culv := sim.creatures[0]
	var cairn := sim.creatures[1]
	culv.pos = Vector2(220, 164)
	cairn.pos = Vector2(330, 164)
	culv.facing = Vector2.RIGHT
	culv.energy = 100.0
	tap(sim, SimDefs.IN_SURGE, 80)
	assert_false(sim.terrain.is_hole_at(culv.pos), "he stands on his island")
	var ring: Dictionary = culv.moves()["surge"]["terrain_ring"]
	assert_near(float(ring["outer"]), 80.0, 0.5, "the ring reaches 80 px:")
	cairn.pos = culv.pos + Vector2(90, 0)
	culv.facing = Vector2.RIGHT
	run(sim, S1, 40)  # Gulp, held
	var fell := run_until(sim, func(): return cairn.state == CreatureSim.State.FALLING, 80)
	assert_true(fell, "out the back end and into the pit")


## Storm Drain's ring leaves a cracked lane open to his left and right: a fighter who
## sidestepped it walks in and punishes him in his recovery. The front stays walled off.
func test_storm_drain_can_be_punished_through_its_side_lanes() -> void:
	var sim := MatchFactory.versus("culvert", "cairn")
	var culv := sim.creatures[0]
	var cairn := sim.creatures[1]
	culv.pos = Vector2(220, 164)
	cairn.pos = Vector2(330, 164)
	culv.facing = Vector2.RIGHT
	culv.energy = 100.0
	tap(sim, SimDefs.IN_SURGE, 0)
	assert_true(run_until(sim, func(): return sim.terrain.count(TerrainGrid.HOLE) > 0, 60), "the ring opens")
	assert_eq(culv.state, CreatureSim.State.ATTACK, "he's still in the move")
	assert_near(cairn.hp, cairn.max_hp, 0.001, "the sidestepper wasn't hit:")
	# From his side: straight in through the lane, in reach before he has recovered.
	cairn.pos = culv.pos + Vector2(0, 100)
	var reached := run_until(sim, func(): return cairn.pos.distance_to(culv.pos) < 30.0, 45, 0, SimDefs.IN_UP)
	assert_true(reached, "walked in through the lane (%.0f px off)" % cairn.pos.distance_to(culv.pos))
	assert_eq(culv.state, CreatureSim.State.ATTACK, "while he's still recovering")
	run(sim, 0, 1, L)
	assert_true(run_until(sim, func(): return culv.hp < culv.max_hp, 20), "and the jab lands")
	# From the front the pits still wall him off.
	cairn.pos = culv.pos + Vector2(100, 0)
	cairn.state = CreatureSim.State.IDLE
	run(sim, 0, 45, SimDefs.IN_LEFT)
	assert_gt(cairn.pos.distance_to(culv.pos), 45.0, "stopped at the pits' edge in front:")


## A fighter who falls into the ring is put down clear of it, not at a pit's lip to be
## knocked straight back in.
func test_a_fall_into_the_ring_lands_clear_of_the_pits() -> void:
	var sim := MatchFactory.versus("culvert", "cairn")
	var culv := sim.creatures[0]
	var cairn := sim.creatures[1]
	culv.pos = Vector2(220, 164)
	cairn.pos = Vector2(330, 164)
	culv.facing = Vector2.RIGHT
	culv.energy = 100.0
	tap(sim, SimDefs.IN_SURGE, 0)
	assert_true(run_until(sim, func(): return sim.terrain.count(TerrainGrid.HOLE) > 0, 60), "the ring opens")
	cairn.pos = culv.pos + Vector2(50, 0)  # in the ring, ahead of him
	cairn.invuln = 0
	assert_true(run_until(sim, func(): return cairn.state == CreatureSim.State.FALLING, 5), "falls in")
	assert_true(run_until(sim, func(): return cairn.state != CreatureSim.State.FALLING, 60), "lands")
	var c := sim.terrain.world_to_cell(cairn.pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			assert_true(TerrainGrid.is_walkable(sim.terrain.get_cell(c + Vector2i(dx, dy))),
				"floor at %s round the landing cell %s" % [Vector2i(dx, dy), c])
