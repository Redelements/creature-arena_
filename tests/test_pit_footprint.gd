extends TestCase
## Pit falls by footprint (data/rules/falls.json, TerrainGrid.footprint_falls): a fighter
## falls only when at least half its footprint (the centre and eight points round its body
## circle) is over pit cells, so a big fighter no longer drops through a hole it covers with
## room to spare. The walking guard (CreatureSim._move) and the CPU's landing checks
## (CpuController._lands_safe) read the same rule. Expectations worked out by hand from the
## defaults (fall_fraction 0.5: five of nine points; fall_radius_mult 1.0).

## Pit shapes, in cells from the anchor cell A (col 40, row 18): [x0, y0, w, h]. "strip" is a
## chasm six cells wide down the whole floor.
const SHAPES := {
	"1": [0, 0, 1, 1],
	"2": [0, 0, 2, 1],
	"3x3": [-1, -1, 3, 3],
	"4x4": [-2, -2, 4, 4],
	"strip": [0, -99, 6, 999],
}
const ANCHOR := Vector2i(40, 18)

## Where the body's centre stands, along x, measured from the shape's left edge (px):
## "mid" its middle, "half" just inside its left edge (half the body over), "three_q" half a
## radius inside (three quarters over), "quarter" half a radius outside (a quarter over).
## y is always the shape's middle (the strip's: the anchor row's middle).
##
## [radius, shape, where, falls]
const TABLE := [
	# One cell: never, wherever the body stands (at most 3 of 9 points fit in one cell).
	[9, "1", "mid", false], [10, "1", "mid", false], [13, "1", "mid", false],
	[9, "1", "half", false], [13, "1", "half", false],
	# Two cells side by side: never either.
	[9, "2", "mid", false], [10, "2", "mid", false], [13, "2", "mid", false],
	[9, "2", "half", false],
	# 3x3 (24 px): everyone in the middle; at the lip the small ones, not the big one (its
	# top and bottom points stick out past the hole).
	[9, "3x3", "mid", true], [10, "3x3", "mid", true], [13, "3x3", "mid", true],
	[9, "3x3", "half", true], [10, "3x3", "half", true], [13, "3x3", "half", false],
	[9, "3x3", "three_q", true], [13, "3x3", "three_q", false],
	[9, "3x3", "quarter", false], [13, "3x3", "quarter", false],
	# 4x4 (32 px): everyone, from half over.
	[9, "4x4", "mid", true], [10, "4x4", "mid", true], [13, "4x4", "mid", true],
	[9, "4x4", "half", true], [13, "4x4", "half", true],
	[9, "4x4", "three_q", true], [13, "4x4", "three_q", true],
	[9, "4x4", "quarter", false], [13, "4x4", "quarter", false],
	# A chasm strip: half over falls, a quarter over doesn't, for every size.
	[9, "strip", "mid", true], [10, "strip", "mid", true], [13, "strip", "mid", true],
	[9, "strip", "half", true], [10, "strip", "half", true], [13, "strip", "half", true],
	[9, "strip", "three_q", true], [13, "strip", "three_q", true],
	[9, "strip", "quarter", false], [10, "strip", "quarter", false], [13, "strip", "quarter", false],
]


func _sim_with(shape: String) -> MatchSim:
	var sim := MatchFactory.training()
	var s: Array = SHAPES[shape]
	var t := sim.terrain
	for dy in range(int(s[1]), int(s[1]) + int(s[3])):
		for dx in range(int(s[0]), int(s[0]) + int(s[2])):
			var c := ANCHOR + Vector2i(dx, dy)
			if t.in_bounds(c):
				t.set_cell(c, TerrainGrid.CHASM if shape == "strip" else TerrainGrid.HOLE)
	return sim


func _spot(sim: MatchSim, shape: String, where: String, radius: float) -> Vector2:
	var s: Array = SHAPES[shape]
	var t := sim.terrain
	var left := t.cell_rect(ANCHOR + Vector2i(int(s[0]), 0)).position.x
	var w := float(int(s[2]) * SimDefs.CELL)
	var y := t.cell_center(ANCHOR).y
	if shape != "strip":
		y = t.cell_rect(ANCHOR + Vector2i(0, int(s[1]))).position.y + float(int(s[3]) * SimDefs.CELL) * 0.5
	match where:
		"mid": return Vector2(left + w * 0.5, y)
		"half": return Vector2(left + 0.5, y)
		"three_q": return Vector2(left + radius * 0.5, y)
		_: return Vector2(left - radius * 0.5, y)


func _label(row: Array) -> String:
	return "radius %d over %s at %s" % [row[0], row[1], row[2]]


func test_the_table_with_the_rule() -> void:
	for row in TABLE:
		var sim := _sim_with(row[1])
		var p := _spot(sim, row[1], row[2], float(row[0]))
		assert_eq(sim.terrain.footprint_falls(p, float(row[0])), row[3], _label(row) + ":")


func test_the_table_in_a_match() -> void:
	# A body put there and stepped once: it falls exactly when the table says.
	for row in TABLE:
		var sim := _sim_with(row[1])
		var c := sim.creatures[0]
		c.radius = float(row[0])
		c.pos = _spot(sim, row[1], row[2], c.radius)
		sim.creatures[1].pos = Vector2(60, 60)
		run(sim, 0, 1)
		assert_eq(c.state == CreatureSim.State.FALLING, row[3], _label(row) + " falls in the match:")


func test_the_walking_guard_agrees() -> void:
	# One step onto each spot from 2 px to its left: refused where the rule drops the body,
	# taken where it doesn't, and never left standing where it would fall.
	for row in TABLE:
		var sim := _sim_with(row[1])
		var c := sim.creatures[0]
		c.radius = float(row[0])
		var to := _spot(sim, row[1], row[2], c.radius)
		var from := to - Vector2(2, 0)
		if sim.terrain.footprint_falls(from, c.radius):
			continue  # already over the pit: the guard lets it move (it is falling anyway)
		c.pos = from
		c._move(to - from, sim, true)
		if row[3]:
			assert_true(c.pos.x < to.x, _label(row) + ": the walk stops short")
		else:
			assert_near(c.pos.x, to.x, 0.001, _label(row) + ": the walk gets there:")
		assert_false(sim.terrain.footprint_falls(c.pos, c.radius), _label(row) + ": never walks onto a fall")


func test_big_and_small_walk_up_to_a_chasm_and_never_fall() -> void:
	for r in [9.0, 10.0, 13.0]:
		var sim := _sim_with("strip")
		var c := sim.creatures[0]
		c.radius = r
		c.pos = Vector2(sim.terrain.cell_rect(ANCHOR).position.x - 40.0, sim.terrain.cell_center(ANCHOR).y)
		sim.creatures[1].pos = Vector2(60, 60)
		var fell := run_until(sim, func(): return c.state == CreatureSim.State.FALLING, 120, SimDefs.IN_RIGHT)
		assert_false(fell, "radius %d walks to the lip without falling" % r)
		assert_lt(c.pos.x, sim.terrain.cell_rect(ANCHOR).position.x + 1.0, "and stops at the lip (radius %d):" % r)


func test_a_one_cell_crack_is_walked_over() -> void:
	# Before the footprint rule a crack one cell wide stopped every walk; it drops nobody now,
	# so nobody is held back by it either.
	var sim := MatchFactory.training()
	for row in sim.terrain.rows:
		sim.terrain.set_cell(Vector2i(ANCHOR.x, row), TerrainGrid.HOLE)
	var c := sim.creatures[0]
	c.radius = 13.0
	c.pos = Vector2(sim.terrain.cell_rect(ANCHOR).position.x - 30.0, sim.terrain.cell_center(ANCHOR).y)
	sim.creatures[1].pos = Vector2(60, 60)
	var fell := run_until(sim, func(): return c.state == CreatureSim.State.FALLING, 60, SimDefs.IN_RIGHT)
	assert_false(fell, "the crack drops nobody")
	assert_gt(c.pos.x, sim.terrain.cell_rect(ANCHOR).end.x, "walked across it:")


func test_the_cpu_landing_check_agrees_with_the_sim() -> void:
	# _lands_safe also keeps LAND_MARGIN round the spot, so it may refuse a spot the sim
	# would let stand, never the other way round; and the clear cases match.
	for row in TABLE:
		var sim := _sim_with(row[1])
		var p := _spot(sim, row[1], row[2], float(row[0]))
		var safe := CpuController._lands_safe(sim.terrain, p, float(row[0]))
		if row[3]:
			assert_false(safe, _label(row) + ": the CPU won't land a roll there")
	var sim := _sim_with("1")
	var mid := _spot(sim, "1", "mid", 13.0)
	assert_true(CpuController._lands_safe(sim.terrain, mid, 13.0), "a big fighter may roll onto a lone hole cell")
	assert_false(CpuController._lands_safe(sim.terrain, mid), "the centre-point check (radius 0) still refuses it")
	sim = _sim_with("strip")
	var deep := _spot(sim, "strip", "mid", 10.0)
	var far := Vector2(deep.x + 60.0, deep.y)
	assert_false(CpuController._lands_safe(sim.terrain, deep, 10.0), "never in the middle of a chasm")
	assert_true(CpuController._lands_safe(sim.terrain, far, 10.0), "the far side is floor")


func test_radius_mult_zero_is_the_old_centre_rule() -> void:
	TerrainGrid.set_fall_rules({"fall_fraction": 0.5, "fall_radius_mult": 0.0})
	var sim := _sim_with("1")
	var mid := _spot(sim, "1", "mid", 13.0)
	var ok := sim.terrain.footprint_falls(mid, 13.0)
	var beside := sim.terrain.footprint_falls(mid + Vector2(8, 0), 13.0)
	TerrainGrid.set_fall_rules()
	assert_true(ok, "the centre over a lone hole falls under the old rule")
	assert_false(beside, "and a cell over doesn't")
	assert_false(sim.terrain.footprint_falls(mid, 13.0), "back to the data: it doesn't")


## Sinkhole-style floor: everything sunk to chasm but the floor cells c0..c1 (inclusive).
func _island(c0: Vector2i, c1: Vector2i) -> MatchSim:
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.fall_ko = true
	var t := sim.terrain
	for cy in t.rows:
		for cx in t.cols:
			if cx < c0.x or cy < c0.y or cx > c1.x or cy > c1.y:
				t.sink(Vector2i(cx, cy))
	sim.creatures[1].pos = t.cell_center(Vector2i(45, 20))
	for c in sim.creatures:
		c.invuln = 0
	return sim


## Steps until creature 0 is knocked out (or `limit` ticks), noting the first fall's pit.
func _fall_pit(sim: MatchSim, limit: int) -> String:
	var pit := ""
	for i in limit:
		run(sim, 0, 1)
		for e in sim.events:
			if e["type"] == "fall" and pit == "":
				pit = String(e.get("pit", ""))
		if sim.creatures[0].state == CreatureSim.State.KO:
			break
	return pit


func test_a_corner_of_the_sinkhole_floor_is_a_chasm_knockout() -> void:
	# Just inside the floor's top-left corner: the centre on floor, five of the nine points
	# over the chasm. It falls, the fall is a chasm's, and under fall_ko it's a knockout
	# (before the fix the centre's floor cell made it a hole: hurt and back up).
	var sim := _island(Vector2i(30, 10), Vector2i(53, 25))
	var c := sim.creatures[0]
	c.pos = sim.terrain.cell_rect(Vector2i(30, 10)).position + Vector2(1, 1)
	assert_false(sim.terrain.is_hole_at(c.pos), "the centre is on floor")
	assert_true(sim.terrain.footprint_chasm(c.pos, c.radius), "the footprint says chasm")
	assert_eq(_fall_pit(sim, 200), "chasm", "the fall event's pit:")
	assert_eq(c.state, CreatureSim.State.KO, "a chasm fall knocks out under fall_ko:")


func test_a_hole_with_a_chasm_corner_stays_a_hole() -> void:
	# Mostly over a hole (centre too), one point over a chasm: still a hole, as before.
	var sim := MatchFactory.versus("cairn", "culvert")
	var t := sim.terrain
	for dy in range(-2, 2):
		for dx in range(-2, 2):
			t.set_cell(ANCHOR + Vector2i(dx, dy), TerrainGrid.HOLE)
	t.sink(ANCHOR + Vector2i(2, 0))
	var p := t.cell_rect(ANCHOR).position + Vector2(4, 0)
	assert_false(t.footprint_chasm(p, 13.0), "more hole than chasm, centre on a hole")


func _sunk_top_row() -> MatchSim:
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.fall_ko = true
	for cx in sim.terrain.cols:
		sim.terrain.sink(Vector2i(cx, 0))
	sim.creatures[1].pos = sim.terrain.cell_center(Vector2i(45, 20))
	for c in sim.creatures:
		c.invuln = 0
	return sim


func test_hugging_the_top_wall_over_a_sunk_top_row_falls() -> void:
	# Sinkhole's ring 0 sinks the top row. A body hugging the top wall (its centre EDGE_TOP
	# px into row 0) has its three upward points past the grid: they read the edge row (a
	# chasm), not floor, so it falls and is knocked out, as under the centre-point rule.
	var sim := _sunk_top_row()
	var c := sim.creatures[0]
	c.pos = Vector2(sim.terrain.cell_center(Vector2i(20, 0)).x, SimDefs.GRID_Y + CreatureSim.EDGE_TOP)
	assert_true(sim.terrain.footprint_falls(c.pos, c.radius), "the footprint over the sunk row falls")
	assert_eq(_fall_pit(sim, 200), "chasm", "the fall event's pit:")
	assert_eq(c.state, CreatureSim.State.KO, "knocked out:")


func test_a_walk_up_never_steps_onto_a_sunk_top_row() -> void:
	var sim := _sunk_top_row()
	var c := sim.creatures[0]
	c.pos = Vector2(sim.terrain.cell_center(Vector2i(20, 0)).x, SimDefs.GRID_Y + 30.0)
	var fell := run_until(sim, func(): return c.state == CreatureSim.State.FALLING, 90, SimDefs.IN_UP)
	assert_false(fell, "walking up stops at the lip")
	assert_gt(c.pos.y, SimDefs.GRID_Y + SimDefs.CELL - 0.01, "its centre stays off the sunk row:")
