extends TestCase
## The resolution policy and the pixel font: a 960 x 540 grid drawn at content scale 2 (so
## the canvas, the camera and every layout keep their 480 x 270 numbers), the window snapped
## to whole screen pixels per canvas unit, and every string in the pixel font at whole
## multiples of its native size.


func test_the_canvas_keeps_its_480_by_270_units() -> void:
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 960, "grid width:")
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 540, "grid height:")
	assert_near(float(ProjectSettings.get_setting("display/window/stretch/scale")), 2.0, 0.001,
		"two grid pixels a canvas unit:")
	var vs: Vector2 = (Engine.get_main_loop() as SceneTree).root.get_visible_rect().size
	assert_true(vs.x >= SimDefs.VIEW_W - 0.5 and vs.y >= SimDefs.VIEW_H - 0.5,
		"the visible canvas is at least 480 x 270 units: %s" % vs)


func test_the_window_scale_is_whole_pixels_per_unit() -> void:
	var main_script: GDScript = load("res://src/game/main.gd")
	var base := Vector2(960, 540)
	# [window, screen pixels per canvas unit]: fighters the size they were at 1440 x 810
	# and 1920 x 1080; 2560 x 1440 gets 4 (an even number, so 2x art's pixels stay whole:
	# ArtScale, tests/test_art_scale.gd), the spare edge showing more of the stadium.
	for case in [[Vector2(1440, 810), 3.0], [Vector2(1920, 1080), 4.0], [Vector2(2560, 1440), 4.0],
			[Vector2(1600, 900), 3.0], [Vector2(1920, 1200), 4.0], [Vector2(2400, 1080), 4.0],
			[Vector2(3440, 1440), 4.0], [Vector2(800, 450), 1.0]]:
		var size: Vector2 = case[0]
		var factor: float = main_script.pixel_scale_factor(size, base)
		var grid := minf(size.x / base.x, size.y / base.y)
		var unit_px := grid * factor  # screen pixels per canvas unit
		assert_near(unit_px, float(case[1]), 0.001, "%s:" % size)
		var shown := base / factor  # canvas units on screen at the 16:9 core
		assert_true(shown.x >= SimDefs.VIEW_W - 0.5 or size.x < base.x, "%s shows at least 480 wide" % size)
	assert_eq(main_script.pixel_scale_factor(Vector2.ZERO, base), 0.0, "no window, no change")


func test_text_sizes_are_whole_multiples_of_the_font() -> void:
	for design in range(4, 40):
		var px := UiTheme.px(design)
		assert_eq(px % UiTheme.FONT_NATIVE, 0, "size %d → %d:" % [design, px])
		assert_true(px >= UiTheme.FONT_NATIVE, "never under the native size")
	assert_eq(UiTheme.px(5), 8, "small print at 1x")
	assert_eq(UiTheme.px(9), 16, "rows at 2x")
	assert_true(UiTheme.px(24) > UiTheme.px(12), "bigger stays bigger")


func test_the_theme_and_views_use_the_pixel_font() -> void:
	var f := UiTheme.font()
	assert_true(f is FontFile, "the font loads as a FontFile")
	assert_eq((f as FontFile).antialiasing, TextServer.FONT_ANTIALIASING_NONE, "no antialiasing")
	assert_eq((f as FontFile).hinting, TextServer.HINTING_NONE, "no hinting")
	assert_eq((f as FontFile).subpixel_positioning, TextServer.SUBPIXEL_POSITIONING_DISABLED, "no subpixel positions")
	assert_near((f as FontFile).oversampling, 2.0, 0.001, "rasterised on the grid")
	var t := UiTheme.make()
	assert_eq(t.default_font, f, "menus")
	assert_eq(t.default_font_size % UiTheme.FONT_NATIVE, 0, "the theme's size is a multiple")
	# No view draws with the engine's vector font any more.
	for path in ["res://src/view/hud.gd", "res://src/view/fx_view.gd", "res://src/view/debug_view.gd",
			"res://src/view/perf_overlay.gd", "res://src/ui/character_select.gd", "res://src/ui/ui_theme.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var uses := src.count("ThemeDB.fallback_font")
		var allowed := 2 if path.ends_with("ui_theme.gd") else 0  # its fallback when the file is missing, and the Smooth setting
		assert_eq(uses, allowed, "%s draws with the fallback font:" % path)


func test_the_smooth_setting_swaps_font_and_sizes_and_back() -> void:
	var pixel := UiTheme.font()
	UiTheme.smooth = true
	assert_true(UiTheme.font() == ThemeDB.fallback_font, "Smooth draws with the engine's font")
	assert_eq(UiTheme.px(9), 9, "Smooth keeps the old design sizes")
	assert_true(UiTheme.font_tight() == ThemeDB.fallback_font, "and the tight variant too")
	var t := UiTheme.make()
	assert_true(t.default_font == ThemeDB.fallback_font, "the menu theme follows it")
	UiTheme.smooth = false
	assert_true(UiTheme.font() == pixel, "Pixel comes back")
	assert_eq(UiTheme.px(9), 16, "with whole multiples of the pixel font")
