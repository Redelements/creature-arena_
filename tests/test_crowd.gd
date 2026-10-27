extends TestCase
## The crowd (CrowdView): Szadi's Warrior baked into crowd.png by tools/cut_crowd.py, a row a
## fan variant; the stands pick rows by facing and colours; the seated fans breathe without
## a redraw; two fans raise mugs over a waterfall.


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_the_sheet_matches_the_layout() -> void:
	var tex := CrowdView.sheet()
	var cell := Vector2i(CrowdView.CELL_W, CrowdView.CELL_H) * CrowdView.PPU
	assert_eq(tex.get_width(), cell.x * (CrowdView.COL_CHEER + 1), "columns: four sitting, one cheering:")
	assert_eq(tex.get_height(), cell.y * CrowdView.SHEET_ROWS, "rows (tools/cut_crowd.py GROUPS + mugs):")
	var groups := [CrowdView.ROWS_FRONT, CrowdView.ROWS_RED, CrowdView.ROWS_BLUE,
		CrowdView.ROWS_MIXED_R, CrowdView.ROWS_MIXED_L, CrowdView.ROWS_BACK]
	var next := 0
	for g: Vector2i in groups:
		assert_eq(g.x, next, "the groups run on, in order:")
		next = g.x + g.y
	assert_eq(next, CrowdView.MUG_ROW, "the mug fans come last")
	assert_eq(CrowdView.MUG_ROW + 2, CrowdView.SHEET_ROWS, "two of them")


func test_each_stand_wears_its_own_rows() -> void:
	var crowd := CrowdView.new()
	_root().add_child(crowd)
	var want := {CrowdView.Stand.TOP: CrowdView.ROWS_FRONT, CrowdView.Stand.LEFT: CrowdView.ROWS_RED,
		CrowdView.Stand.RIGHT: CrowdView.ROWS_BLUE, CrowdView.Stand.FRONT: CrowdView.ROWS_BACK}
	var seen := {}
	for b in crowd._blocks:
		var rows: Vector2i = want[b.stand]
		for r in b.row:
			assert_true(r >= rows.x and r < rows.x + rows.y, "stand %d wears rows %s, not %d" % [b.stand, rows, r])
			seen[r] = true
	assert_gt(float(seen.size()), 30.0, "a mix of variants, not clones (%d rows used)" % seen.size())
	crowd.set_size(SimDefs.arena_size(), false)
	for b in crowd._blocks:
		if b.stand == CrowdView.Stand.LEFT:
			assert_true(b.row[0] >= CrowdView.ROWS_MIXED_R.x and b.row[0] < CrowdView.ROWS_MIXED_R.x + 8, "a Brawl's left stand is mixed, facing right")
	crowd.free()


func test_breathing_moves_layers_and_never_redraws() -> void:
	var crowd := CrowdView.new()
	_root().add_child(crowd)
	crowd.advance()
	assert_false(crowd._near.is_empty(), "blocks near the screen")
	var seen := {}
	for t in CrowdView.BREATH_TICKS * 2:
		crowd.advance()
		for b in crowd._near:
			for se in b.seated:
				seen[se.position.y] = true
	assert_eq(seen.size(), 2, "the seated layers rise and settle:")
	assert_true(seen.has(0.0) and seen.has(-0.5), "a breath is half a unit (one art px)")
	assert_eq(crowd._blocks[0].seated.size(), CrowdView.BREATHS, "a seated layer per beat:")
	for se in crowd._blocks[0].seated:
		assert_eq(se.get_parent(), crowd._blocks[0], "under its block")
	crowd.free()


func test_two_fans_raise_mugs_over_the_twin_keeps_waterfall() -> void:
	var f := FileAccess.open("res://data/arenas/twin_keeps.json", FileAccess.READ)
	var arena: Dictionary = JSON.parse_string(f.get_as_text())
	var xs := CrowdView.toasts_for(arena)
	assert_eq(xs.size(), 1, "one waterfall")
	assert_near(xs[0], 616.0, 0.01, "its middle, world x:")
	assert_eq(CrowdView.toasts_for({}).size(), 0, "no tiles, no toasts")
	var crowd := CrowdView.new()
	_root().add_child(crowd)
	var size := Vector2(1232, 590)
	crowd.set_size(size, true, xs)
	assert_eq(crowd._mugs.size(), 2, "two toasters")
	var a: Vector2 = crowd._mugs[0][0]
	var b: Vector2 = crowd._mugs[1][0]
	assert_eq(a.y, 1.0 + (CrowdView.TOP_ROWS - 1) * 14, "in the lowest row of the top stand")
	assert_lt(a.x + CrowdView.W * 0.5, xs[0] + 0.01, "the left one's middle left of the fall")
	assert_gt(b.x + CrowdView.W * 0.5, xs[0], "the right one's right of it")
	assert_eq([crowd._mugs[0][1], crowd._mugs[1][1]], [CrowdView.MUG_ROW, CrowdView.MUG_ROW + 1], "left then right")
	for blk in crowd._blocks:
		for p in blk.pos:
			assert_false(p == a or p == b, "their seats aren't also in a block")
	var cols := {}
	for t in CrowdView.MUG_TICKS * CrowdView.POSES:
		crowd.advance()
		cols[crowd._mug_col] = true
	assert_eq(cols.size(), CrowdView.POSES, "the toast runs through its poses")
	crowd.roar(10)
	crowd.advance()
	assert_true(crowd._mug_col == CrowdView.COL_CHEER or crowd._mug_col == 2, "a roar: on their feet, clinking")
	crowd.free()


func test_a_hit_still_stands_fans_up_near_it() -> void:
	var crowd := CrowdView.new()
	_root().add_child(crowd)
	crowd.advance()
	crowd.react(Vector2(300, 70))
	var up := 0
	for b in crowd._blocks:
		up += b.reacting.size()
		if not b.reacting.is_empty():
			assert_eq(b.stand, CrowdView.Stand.TOP, "the top stand, nearest a hit by the back wall")
	assert_eq(up, CrowdView.REACT_FANS, "REACT_FANS fans stand:")
	for t in CrowdView.REACT_TICKS + 1:
		crowd.advance()
	up = 0
	for b in crowd._blocks:
		up += b.reacting.size()
	assert_eq(up, 0, "and sit again after REACT_TICKS")
	crowd.free()
