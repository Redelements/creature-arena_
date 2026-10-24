extends TestCase
## Arena furniture (the "furniture" list of data/arenas/<id>.json, FurnitureView) and the
## parallax layers behind the floor (BackdropView): the pieces build from data and never sit
## on the playable floor, the scoreboard shows the real match clock and score, and parallax
## moves the sky and far stands in whole pixels while the floor and everything on it stay put.

const MAPS := ["stadium", "quarry", "floodgate", "greenhouse", "twin_keeps", "caravan_pass"]


func _sim(id: String) -> MatchSim:
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.set_arena(id)
	return sim


func test_every_map_builds_its_furniture_from_data() -> void:
	for id in MAPS:
		var sim := _sim(id)
		var v := FurnitureView.new()
		var b := BackdropView.new()
		v.backdrop = b
		var list: Array = sim.arena.get("furniture", [])
		assert_gt(list.size(), 0, "%s has furniture" % id)
		v.set_arena(sim.arena, sim.arena_size())
		assert_eq(v.pieces.size(), list.size(), "%s: every entry becomes a piece (known kind)" % id)
		v.free()
		b.free()


func test_no_piece_sits_on_the_playable_floor() -> void:
	for id in MAPS:
		var sim := _sim(id)
		var floor_rect := sim.terrain.floor_rect()
		var v := FurnitureView.new()
		v.set_arena(sim.arena, sim.arena_size())
		for p in v.pieces:
			var r := FurnitureView.footprint(p)
			assert_false(r.intersects(floor_rect), "%s: %s at %s is off the floor" % [id, p.kind, str(p.world)])
		v.free()


func test_stadium_gets_the_full_set() -> void:
	var v := FurnitureView.new()
	var sim := _sim("stadium")
	v.set_arena(sim.arena, sim.arena_size())
	var kinds := {}
	for p in v.pieces:
		kinds[p.kind] = true
	for k in ["floodlight", "flag", "banner", "scoreboard", "sponsor", "post"]:
		assert_true(kinds.has(k), "the stadium has a %s" % k)
	v.free()


func test_a_map_without_furniture_gets_nothing() -> void:
	var v := FurnitureView.new()
	v.set_arena({"id": "x"}, Vector2(704, 366))
	assert_eq(v.pieces.size(), 0)
	v.set_arena({"furniture": [{"kind": "not_a_kind", "pos": [0, 0]}]}, Vector2(704, 366))
	assert_eq(v.pieces.size(), 0, "an unknown kind is skipped")
	v.free()


func test_anchors_place_a_piece_from_the_arena_corner() -> void:
	var size := Vector2(704, 366)
	assert_eq(FurnitureView.world_pos({"pos": [-30, 56]}, size), Vector2(-30, 56))
	assert_eq(FurnitureView.world_pos({"pos": [30, 56], "anchor": "tr"}, size), Vector2(734, 56))
	assert_eq(FurnitureView.world_pos({"pos": [-34, 22], "anchor": "bl"}, size), Vector2(-34, 388))
	assert_eq(FurnitureView.world_pos({"pos": [-95, -1], "anchor": "t"}, size), Vector2(257, -1))


func test_scoreboard_text_is_the_match_clock_and_score() -> void:
	var t := FurnitureView.board_text(5400, [1, 2])
	assert_eq(t["time"], "1:30")
	assert_eq(t["left"], "1")
	assert_eq(t["right"], "2")
	assert_false(t["low"])
	t = FurnitureView.board_text(599, [0, 0])
	assert_eq(t["time"], "0:10", "rounds up like the HUD's clock")
	assert_true(t["low"], "the last ten seconds")
	assert_eq(FurnitureView.board_text(-1, [0, 0])["time"], "--", "no clock, no time")


func test_scoreboard_follows_the_hud() -> void:
	var hud := Hud.new()
	var sim := _sim("stadium")
	var v := FurnitureView.new()
	v.hud = hud
	v.set_arena(sim.arena, sim.arena_size())
	var board: FurnitureView.Piece = null
	for p in v.pieces:
		if p.kind == "scoreboard":
			board = p
	assert_true(board != null)
	hud.timer_ticks = 4500
	hud.wins = [1, 0]
	v._clock = -1
	v._process(0.0)
	assert_true(board.text_key.begins_with("1:15|1|0"), "shows the HUD's clock and score: %s" % board.text_key)
	hud.timer_ticks = 4440
	v._clock = -1
	v._process(0.0)
	assert_true(board.text_key.begins_with("1:14"), "and follows it: %s" % board.text_key)
	v.free()
	hud.free()


func test_parallax_offsets_are_whole_pixels_and_zero_at_rest() -> void:
	var at_rest := BackdropView.offset_for(0.6, Vector2(352, 116), 352.0, 180.0, 64.0)
	assert_eq(at_rest, Vector2.ZERO, "the camera in the middle, at the top of its range: as drawn")
	var moved := BackdropView.offset_for(0.6, Vector2(452.0, 136.0), 352.0, 180.0, 64.0)
	assert_eq(moved.x, 40.0, "100 px right: the sky follows 40% of it")
	assert_eq(moved.y, 8.0, "and slides down 40% of the 20 px the camera came off the top")
	var far := BackdropView.offset_for(0.85, Vector2(452.0, 136.0), 352.0, 180.0, 64.0)
	assert_eq(far.x, 15.0)
	assert_eq(far.y, 3.0)
	for dx in range(-7, 8):
		var o := BackdropView.offset_for(0.85, Vector2(352.0 + dx * 3.7, 150.3), 352.0, 180.0, 64.0)
		assert_eq(o.x, roundf(o.x), "whole pixels")
		assert_eq(o.y, roundf(o.y), "whole pixels")
	assert_eq(BackdropView.offset_for(1.0, Vector2(900, 900), 352.0, 180.0, 64.0), Vector2.ZERO, "factor 1 never moves")
	var deep := BackdropView.offset_for(0.6, Vector2(352, 5000), 352.0, 180.0, 64.0)
	assert_eq(deep.y, BackdropView.MAX_DROP * 0.4, "the drop is capped")


func test_parallax_moves_the_far_layers_and_not_the_floor() -> void:
	var b := BackdropView.new()
	b.set_map("stadium", Vector2(704, 366))
	var arena := ArenaView.new()
	var floor_before := arena.position
	b._place(Vector2(452, 200), 180.0)
	assert_eq(b.sky.position, BackdropView.sky_rest() + b.sky_offset)
	assert_eq(b.far.position, BackdropView.far_rest() + b.far_offset)
	assert_gt(absf(b.sky_offset.x), absf(b.far_offset.x), "the sky slides more than the far stands")
	assert_eq(b.position, Vector2.ZERO, "the backdrop node itself never moves")
	assert_eq(arena.position, floor_before, "the floor stays at 1.0")
	b.free()
	arena.free()


func test_far_furniture_rides_its_layer() -> void:
	var b := BackdropView.new()
	var v := FurnitureView.new()
	v.backdrop = b
	var sim := _sim("stadium")
	v.set_arena(sim.arena, sim.arena_size())
	for p in v.pieces:
		match p.layer:
			"far":
				assert_eq(p.get_parent(), b.far, "%s hangs from the far layer" % p.kind)
				assert_eq(p.position + BackdropView.far_rest(), p.world, "and sits at its world spot at rest")
			"sky":
				assert_eq(p.get_parent(), b.sky)
			_:
				assert_eq(p.get_parent(), v)
				assert_eq(p.position, p.world)
	b.free()
	v.free()
