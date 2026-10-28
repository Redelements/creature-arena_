extends TestCase
## The art density (ArtScale): the world stays in sim units (8 px cells) and 2x art draws at
## two texture pixels a unit, so a terrain cell is 16 grid pixels and a Set 1 tile 32. Pins
## the constant to the project's viewport and stretch settings so it can't drift, and the
## per-asset "ppu" rule in the views: a 2x sheet draws at half scale on half-unit positions,
## a 2x arena picture is told from its size, portraits keep whole art pixels.


func test_the_world_unit_scale_is_pinned_to_the_project() -> void:
	assert_eq(ArtScale.PX_PER_UNIT, 2, "two art pixels a world unit:")
	assert_eq(ArtScale.CELL_PX, 16, "a terrain cell is 16 art pixels:")
	assert_eq(ArtScale.TILE_PX, 32, "a ground tile is 32 art pixels:")
	assert_eq(ArtScale.TILE_CELLS, 2, "a ground tile covers 2 x 2 cells:")
	assert_eq(SimDefs.CELL, 8, "the sim's cell never moved:")
	# The screen grid is PX_PER_UNIT pixels a canvas unit: the viewport is that many times
	# the 480 x 270 view, and the stretch scale brings the canvas back to view units.
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		SimDefs.VIEW_W * ArtScale.PX_PER_UNIT, "viewport width:")
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")),
		SimDefs.VIEW_H * ArtScale.PX_PER_UNIT, "viewport height:")
	assert_near(float(ProjectSettings.get_setting("display/window/stretch/scale")),
		float(ArtScale.PX_PER_UNIT), 0.001, "stretch scale:")
	assert_eq(String(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items", "stretch mode:")


func test_an_asset_declares_its_density() -> void:
	assert_eq(ArtScale.ppu_of({}), 1, "no key: the older 1x art")
	assert_eq(ArtScale.ppu_of({"ppu": 2}), 2, "a 2x sheet")
	assert_eq(ArtScale.ppu_of({"ppu": 3}), 1, "an unknown density falls back")
	assert_eq(ArtScale.ppu_of({"ppu": 0}, 2), 2, "fallback given")
	assert_eq(ArtScale.scale_of(1), Vector2.ONE)
	assert_eq(ArtScale.scale_of(2), Vector2(0.5, 0.5))
	assert_eq(ArtScale.snap(Vector2(10.3, 4.6), 1), Vector2(10, 5), "1x art: whole units")
	assert_eq(ArtScale.snap(Vector2(10.3, 4.6), 2), Vector2(10.5, 4.5), "2x art: half units")
	assert_near(ArtScale.snapf(7.74, 2), 7.5, 0.0001)


func test_a_picture_is_told_by_its_size() -> void:
	var units := Vector2(704, 366) + ArenaView.MARGIN * 2.0
	assert_eq(ArtScale.picture_ppu(units, units), 1, "the baked stadium picture")
	assert_eq(ArtScale.picture_ppu(units * 2.0, units), 2, "twice the size: 2x art")
	assert_eq(ArtScale.picture_ppu(units * 2.0 + Vector2(1, 0), units), 2, "a pixel of slack")
	assert_eq(ArtScale.picture_ppu(units * 1.5, units), 1, "anything else draws 1:1")
	assert_eq(ArtScale.picture_ppu(Vector2(10, 10), Vector2.ZERO), 1, "no world: 1")
	for id in ["stadium", "twin_keeps", "caravan_pass"]:
		var tex: Texture2D = load("res://assets/sprites/arena_%s.png" % id)
		var cells := ArenaMap.size_of(ArenaMap.get_map(id))
		var size := SimDefs.arena_size_of(cells.x, cells.y)
		assert_eq(ArtScale.picture_ppu(tex.get_size(), size + ArenaView.MARGIN * 2.0), 1,
			"%s's baked picture is 1x today" % id)


func _view(id: String) -> CreatureView:
	var sim := MatchFactory.training(id)
	var v := CreatureView.new()
	v.setup(sim.creatures[0])
	return v


func test_a_1x_sheet_draws_exactly_as_before() -> void:
	# Every sheet in the game is 2x now (the training dummy was the last 1x one), so the 1x
	# rule is pinned on a copy of the dummy's sprite block with its "ppu" keys taken out: a
	# block without the key draws as the older 1x art did, whatever the texture.
	var sim := MatchFactory.training("dummy")
	var c: CreatureSim = sim.creatures[0]
	c.def = c.def.duplicate(true)
	var sp: Dictionary = c.def["sprite"]
	sp.erase("ppu")
	for vname in sp.get("views", {}):
		sp["views"][vname].erase("ppu")
	var v := CreatureView.new()
	v.setup(c)
	v.c.pos = Vector2(200.3, 150.6)
	v.refresh()
	assert_eq(v.ppu, 1, "a sprite block without \"ppu\" is 1x")
	assert_eq(v.sprite.scale, Vector2.ONE, "no scaling")
	assert_eq(v.position, Vector2(200, 151), "whole-unit positions")
	assert_eq(v.sprite.position, -v.origin, "the origin in sheet pixels is the origin in units")
	assert_eq(v.snapshot()["ppu"], 1)
	v.free()


func test_a_2x_sheet_draws_at_half_scale_on_half_units() -> void:
	var v := _view("crease")
	# Mister Crease's sheets are 2x (the route A pilot): twice the frame, twice the origin,
	# the same world size, in every view.
	assert_eq(v.ppu, 2, "crease's sheet is 2x")
	for vname in v._views:
		assert_eq(int(v._views[vname]["ppu"]), 2, "crease's %s view is 2x" % vname)
		assert_eq(v._views[vname]["size"], Vector2(192, 192), "crease's %s frame" % vname)
	v.c.pos = Vector2(200.3, 150.6)
	v.c.facing = Vector2.RIGHT
	v.refresh()
	assert_eq(v.sprite.scale, Vector2(0.5, 0.5), "half scale")
	assert_eq(v.position, Vector2(200.5, 150.5), "half-unit positions")
	assert_eq(v.origin, Vector2(96, 144), "the origin in sheet pixels")
	assert_eq(v.sprite.position, -v.origin / 2.0, "feet land where they did: the doubled origin at half scale")
	assert_eq(v.snapshot()["ppu"], 2, "afterimages know the density")
	assert_eq(v.emit.scale, v.sprite.scale if v.emit.visible else v.emit.scale, "the emissive layer follows")
	v.free()


func test_a_256_px_frame_draws_like_its_128_px_one() -> void:
	# Sno Mercy at 2x: 256 px frames (views 224 x 256), the largest frame so far. Nothing in
	# the views may assume a frame of 192 or less: the same world size as his 128 px sheets.
	var v := _view("sno")
	assert_eq(v.ppu, 2, "sno's sheet is 2x")
	var sizes := {"down": Vector2(224, 256), "up": Vector2(224, 256),
		"down_side": Vector2(256, 256), "up_side": Vector2(256, 256)}
	for vname in v._views:
		assert_eq(int(v._views[vname]["ppu"]), 2, "sno's %s view is 2x" % vname)
		if sizes.has(vname):
			assert_eq(v._views[vname]["size"], sizes[vname], "sno's %s frame" % vname)
	v.c.pos = Vector2(120.2, 90.7)
	v.c.facing = Vector2.RIGHT
	v.refresh()
	assert_eq(v.sprite.scale, Vector2(0.5, 0.5), "half scale")
	assert_eq(v.origin, Vector2(128, 208), "the origin in sheet pixels")
	assert_eq(v.sprite.position, -v.origin / 2.0, "the feet where the 1x origin (64, 104) put them")
	assert_eq(Vector2(v.sprite.texture.get_width() / v.sprite.hframes, v.sprite.texture.get_height() / v.sprite.vframes),
		Vector2(256, 256), "the sheet cut into whole 256 px frames")
	v.free()
	var sp: Dictionary = MatchFactory.training("sno").creatures[0].def["sprite"]
	var pr: Array = sp["portrait"]
	assert_true(int(pr[2]) <= Hud.PORT_W * 2 and int(pr[3]) <= Hud.PORT_H * 2, "the portrait crop fits the box at 2x")
	assert_near(Hud.portrait_scale(Vector2i(int(pr[2]), int(pr[3])), 2), 0.5, 0.001, "sno's portrait: one grid pixel an art pixel")


func test_pete_at_2x_still_vanishes_into_a_ghost() -> void:
	# Sneaky Pete at 2x: Tiptoe draws him (for his own side) as a faint ghost, the same
	# alpha at any density, on the half-scale sprite; his afterimages know the density.
	var v := _view("pete")
	assert_eq(v.ppu, 2, "pete's sheet is 2x")
	assert_eq(v.origin, Vector2(128, 208), "the origin in sheet pixels")
	v.c.facing = Vector2.RIGHT
	v.c.stealth = 30
	v.refresh()
	assert_eq(v.sprite.scale, Vector2(0.5, 0.5), "half scale while invisible")
	assert_true(v.modulate.a >= 0.4 and v.modulate.a <= 0.48, "a ghost, not solid: %s" % v.modulate.a)
	assert_eq(v.snapshot()["ppu"], 2, "the Tiptoe afterimages are cut from the 2x sheet")
	v.c.stealth = 0
	v.refresh()
	assert_eq(v.modulate.a, 1.0, "solid again")
	var cut: Array = MatchFactory.training("pete").creatures[0].def["cut_in_frame"]
	assert_eq([int(cut[0]), int(cut[1])], [8, 9], "the Surge cut-in stays a [row, col] index")
	v.free()


func test_the_hud_portrait_keeps_whole_art_pixels() -> void:
	assert_near(Hud.portrait_scale(Vector2i(24, 32), 1), 1.0, 0.001, "a 1x crop that fills the box: 1")
	assert_near(Hud.portrait_scale(Vector2i(12, 16), 1), 2.0, 0.001, "a small 1x crop: doubled")
	assert_near(Hud.portrait_scale(Vector2i(48, 64), 2), 0.5, 0.001, "a 2x crop that fills the box: half a unit a pixel")
	assert_near(Hud.portrait_scale(Vector2i(24, 32), 2), 1.0, 0.001, "a small 2x crop: one unit a pixel")
	assert_near(Hud.portrait_scale(Vector2i(60, 80), 2), 0.5, 0.001, "never under one grid pixel an art pixel")


func test_the_window_keeps_whole_screen_pixels_per_art_pixel() -> void:
	var main_script: GDScript = load("res://src/game/main.gd")
	var base := Vector2(960, 540)
	# [window, screen pixels per canvas unit]: an even number once the window has two or
	# more screen pixels a grid pixel, so a 2x sheet's pixels are all the same size.
	for case in [[Vector2(1920, 1080), 4.0], [Vector2(2560, 1440), 4.0], [Vector2(3840, 2160), 8.0],
			[Vector2(3440, 1440), 4.0], [Vector2(2400, 1080), 4.0]]:
		var size: Vector2 = case[0]
		var grid := minf(size.x / base.x, size.y / base.y)
		var unit_px: float = grid * main_script.pixel_scale_factor(size, base)
		assert_near(unit_px, float(case[1]), 0.001, "%s:" % size)
		assert_eq(int(roundf(unit_px)) % ArtScale.PX_PER_UNIT, 0, "%s: whole pixels per art pixel" % size)
	# Under two: whole pixels per canvas unit, as the 1x sheets want (1440 x 810 keeps its 3).
	assert_near(1.5 * main_script.pixel_scale_factor(Vector2(1440, 810), base), 3.0, 0.001, "1440 x 810:")
