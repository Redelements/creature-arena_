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
	var grabbed := run_until(sim, func(): return not _events(sim, "grab").is_empty(), 80, S1)
	assert_true(grabbed, "a held tongue swallows Cairn")
	assert_true(_events(sim, "hook").is_empty(), "no hook when held")
	assert_near(cairn.max_hp - cairn.hp, 12.0, 0.001, "swallow damage:")
	run(sim, 0, 40)
	assert_lt(cairn.pos.x, culv.pos.x, "spat out behind him:")
	assert_lt(culv.facing.x, 0.0, "and he turns to face where they land")


func test_the_tongue_flies_at_a_moderate_speed() -> void:
	var p: Dictionary = MatchFactory.load_def("culvert")["moves"]["skill_1"]["projectile"]
	assert_near(float(p["speed"]), 5.0, 0.001, "px a tick:")


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
	assert_eq(holes, 12, "a 3 by 4 block:")
	assert_eq(xs.max() - xs.min() + 1, 3, "3 deep (along his facing)")
	assert_eq(ys.max() - ys.min() + 1, 4, "4 across")
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
