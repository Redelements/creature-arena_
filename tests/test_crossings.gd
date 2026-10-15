extends TestCase
## Arena crossings: heavy charges smash rubble, ghost dashes slip through fences, leaps
## and Burrow cross chasms, Culvert wades, the water dashes run further in shallows,
## brush hides whoever stands in it and any dash flattens it.

const R := SimDefs.IN_RIGHT
const L := SimDefs.IN_LEFT


func _with(pieces: Array, left: String, right := "cairn") -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.terrain.load_map({"pieces": pieces})
	return sim


## The input bit for the move called `name`.
func _bit(c: CreatureSim, name: String) -> int:
	var slots := {"light_1": SimDefs.IN_LIGHT, "heavy": SimDefs.IN_HEAVY, "skill_1": SimDefs.IN_SKILL1,
		"skill_2": SimDefs.IN_SKILL2, "surge": SimDefs.IN_SURGE}
	for slot in slots:
		if String((c.def["moves"] as Dictionary).get(slot, {}).get("name", "")) == name:
			return slots[slot]
	fail("no move called " + name)
	return 0


func _saw(sim: MatchSim, kind: String) -> bool:
	for e in sim.events:
		if e["type"] == kind:
			return true
	return false


func _place_right_of_wall(sim: MatchSim, c: CreatureSim, gap := 30.0) -> float:
	var wall_x := sim.terrain.cell_rect(Vector2i(50, 0)).position.x  # wall is cells 50-51
	c.pos = Vector2(wall_x + 16.0 + gap, sim.terrain.cell_center(Vector2i(50, 18)).y)
	c.facing = Vector2.LEFT
	sim.creatures[1].pos = Vector2(wall_x - 120.0, c.pos.y)  # the foe is beyond, out of reach
	return wall_x


func test_landslide_charge_smashes_through_a_rubble_wall() -> void:
	var sim := _with([{"kind": "wall", "rect": [50, 0, 2, 36]}], "craglash")
	var c := sim.creatures[0]
	var wall_x := _place_right_of_wall(sim, c)
	var smashed := false
	var bit := _bit(c, "Landslide Charge")
	run(sim, bit | L, 1)
	for i in 70:
		run(sim, L, 1)
		smashed = smashed or _saw(sim, "smash")
	assert_true(smashed, "the charge fires a smash event")
	assert_eq(sim.terrain.get_cell(Vector2i(50, 18)), TerrainGrid.CRACKED, "the wall cell in his path is cracked floor:")
	assert_true(c.pos.x < wall_x, "he came out the far side of the wall (x %.0f, wall at %.0f)" % [c.pos.x, wall_x])
	assert_eq(sim.terrain.get_cell(Vector2i(50, 2)), TerrainGrid.WALL, "cells away from his path still stand:")


func test_the_ram_dodge_smashes_too_but_a_plain_dash_stops() -> void:
	var sim := _with([{"kind": "wall", "rect": [50, 0, 2, 36]}], "craglash")
	var c := sim.creatures[0]
	var wall_x := _place_right_of_wall(sim, c, 24.0)
	c.stamina = c.max_stamina
	tap(sim, SimDefs.IN_DODGE | L, 40)
	assert_true(c.pos.x < wall_x + 16.0, "the ram broke in (x %.0f)" % c.pos.x)
	var plain := _with([{"kind": "wall", "rect": [50, 0, 2, 36]}], "culvert")
	var d := plain.creatures[0]
	var wx := _place_right_of_wall(plain, d, 24.0)
	tap(plain, _bit(d, "Gulp") | L if _has_move(d, "Gulp") else SimDefs.IN_DODGE | L, 60)
	assert_true(d.pos.x >= wx + 16.0 + d.radius - 0.5, "Culvert stops at the wall")
	assert_eq(plain.terrain.get_cell(Vector2i(50, 18)), TerrainGrid.WALL, "and leaves it standing:")


func _has_move(c: CreatureSim, name: String) -> bool:
	for slot in c.def["moves"]:
		if String((c.def["moves"][slot] as Dictionary).get("name", "")) == name:
			return true
	return false


func test_rockslide_rush_breaks_rubble() -> void:
	var sim := _with([{"kind": "wall", "rect": [50, 0, 2, 36]}], "cairn", "culvert")
	var c := sim.creatures[0]
	var wall_x := _place_right_of_wall(sim, c, 26.0)
	var bit := _bit(c, "Rockslide Rush")
	run(sim, bit | L, 1)
	run(sim, L, 70)
	assert_true(c.pos.x < wall_x + 8.0, "Cairn rushed into the wall (x %.0f)" % c.pos.x)
	assert_eq(sim.terrain.get_cell(Vector2i(51, 18)), TerrainGrid.CRACKED, "and broke it:")


func test_pickpocket_ghosts_through_a_fence_but_a_roll_does_not() -> void:
	var sim := _with([{"kind": "fence", "rect": [50, 0, 2, 36]}], "pete")
	var p := sim.creatures[0]
	var fence_x := sim.terrain.cell_rect(Vector2i(50, 0)).position.x
	p.pos = Vector2(fence_x + 16.0 + 26.0, sim.terrain.cell_center(Vector2i(50, 18)).y)
	p.facing = Vector2.LEFT
	sim.creatures[1].pos = Vector2(fence_x - 40.0, p.pos.y)  # the mark is just past the fence
	var bit := _bit(p, "Pickpocket")
	run(sim, bit | L, 1)
	run(sim, L, 60)
	assert_true(p.pos.x < fence_x, "ghosted through the fence (x %.0f, fence at %.0f)" % [p.pos.x, fence_x])
	assert_false(sim.terrain.body_blocked(p.pos, p.radius), "and ended clear of it")
	var roll := _with([{"kind": "fence", "rect": [50, 0, 2, 36]}], "pete")
	var q := roll.creatures[0]
	q.pos = Vector2(fence_x + 16.0 + 20.0, roll.terrain.cell_center(Vector2i(50, 18)).y)
	tap(roll, SimDefs.IN_DODGE | L, 40)
	assert_true(q.pos.x >= fence_x + 16.0 + q.radius - 0.5, "a dodge roll stops at the fence")


func test_burrow_and_a_leap_cross_a_chasm_walking_does_not() -> void:
	var sim := _with([{"kind": "chasm", "rect": [50, 0, 3, 36]}], "digby", "cairn")
	var d := sim.creatures[0]
	var pit_x := sim.terrain.cell_rect(Vector2i(50, 0)).position.x
	d.pos = Vector2(pit_x - 30.0, sim.terrain.cell_center(Vector2i(50, 18)).y)
	d.facing = Vector2.RIGHT
	sim.creatures[1].pos = Vector2(pit_x + 24.0 + 120.0, d.pos.y)
	var bit := _bit(d, "Burrow")
	run(sim, bit | R, 1)
	run(sim, R, 80)
	assert_true(d.state != CreatureSim.State.FALLING, "Digby did not fall")
	assert_true(d.pos.x > pit_x + 24.0, "Burrow came up past the chasm (x %.0f)" % d.pos.x)
	var walk := _with([{"kind": "chasm", "rect": [50, 0, 3, 36]}], "digby", "cairn")
	var w := walk.creatures[0]
	w.pos = Vector2(pit_x - 30.0, walk.terrain.cell_center(Vector2i(50, 18)).y)
	run(walk, R, 60)
	assert_true(w.pos.x < pit_x + 1.0, "walking stops at the chasm's edge")


func test_culvert_wades_and_the_water_dashes_go_further_in_shallows() -> void:
	var dry := MatchFactory.versus("culvert", "cairn")
	var wet := _with([{"kind": "shallows", "rect": [0, 0, 84, 36]}], "culvert")
	for sim: MatchSim in [dry, wet]:
		sim.creatures[0].pos = sim.terrain.cell_center(Vector2i(20, 18))
		run(sim, R, 60)
	assert_near(wet.creatures[0].pos.x, dry.creatures[0].pos.x, 0.01, "Culvert walks shallows at full speed:")
	var dash_dry := MatchFactory.versus("gillbert", "cairn")
	var dash_wet := _with([{"kind": "shallows", "rect": [0, 0, 84, 36]}], "gillbert")
	var reach := []
	for sim: MatchSim in [dash_dry, dash_wet]:
		var g: CreatureSim = sim.creatures[0]
		g.pos = sim.terrain.cell_center(Vector2i(10, 18))
		sim.creatures[1].pos = sim.terrain.cell_center(Vector2i(80, 18))
		var x0 := g.pos.x
		run(sim, _bit(g, "Flop Dash") | R, 1)
		run(sim, R, 50)
		reach.append(g.pos.x - x0)
	assert_gt(float(reach[1]), float(reach[0]) * 1.3, "Flop Dash in shallows %.0f vs dry %.0f" % [reach[1], reach[0]])


func test_brush_hides_whoever_stands_in_it_and_a_roll_flattens_it() -> void:
	var sim := _with([{"kind": "brush", "rect": [40, 14, 8, 8]}], "cairn", "culvert")
	var c := sim.creatures[0]
	c.pos = sim.terrain.cell_center(Vector2i(43, 17))
	run(sim, 0, 1)
	assert_true(c.covered, "standing in brush covers him")
	c.pos = sim.terrain.cell_center(Vector2i(30, 17))
	run(sim, 0, 1)
	assert_false(c.covered, "out of the brush he's seen")
	c.pos = sim.terrain.cell_center(Vector2i(38, 17))
	c.facing = Vector2.RIGHT
	tap(sim, SimDefs.IN_DODGE | R, 30)
	assert_true(sim.terrain.count(TerrainGrid.BRUSH_FLAT) > 0, "the roll flattened brush")
	var flat := sim.terrain.world_to_cell(c.pos)
	if sim.terrain.get_cell(flat) == TerrainGrid.BRUSH_FLAT:
		assert_false(c.covered, "flattened brush hides nobody")
	for i in TerrainGrid.HEAL_TICKS + 2:
		sim.terrain.tick()
	assert_eq(sim.terrain.count(TerrainGrid.BRUSH_FLAT), 0, "flattened brush grows back:")


func test_the_cpu_loses_a_foe_in_the_brush_until_it_is_close() -> void:
	var sim := _with([{"kind": "brush", "rect": [40, 14, 8, 8]}], "cairn", "culvert")
	var cpu := CpuController.new(1, 1, 3)
	var me := sim.creatures[1]
	var foe := sim.creatures[0]
	me.pos = sim.terrain.cell_center(Vector2i(20, 17))
	foe.pos = sim.terrain.cell_center(Vector2i(30, 17))
	cpu.bits(sim)  # sees the foe here
	foe.pos = sim.terrain.cell_center(Vector2i(43, 17))
	run(sim, 0, 1)
	cpu.bits(sim)
	assert_true(foe.covered, "the foe is in the brush")
	assert_eq(cpu._seen(foe), sim.terrain.cell_center(Vector2i(30, 17)), "the CPU still looks where it last saw him:")
	me.pos = foe.pos + Vector2(-24.0, 0.0)
	cpu.bits(sim)
	assert_eq(cpu._seen(foe), foe.pos, "next to the bush it sees him:")
