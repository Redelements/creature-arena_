class_name UiTheme
extends RefCounted
## The one look every menu screen shares, built in code like the input bindings: the
## HUD's colours, its font, outlined text. Screens get it from ScreenStack.
##
## Text: every string the game draws (menus, HUD, fx callouts, overlays) uses the pixel font
## m5x7 (Daniel Linssen, CC0: assets/fonts/), from `font()`. Its native size is 16 pixels
## of the 960 x 540 grid, which is 8 canvas units (a canvas unit is two grid pixels:
## project.godot `window/stretch/scale`). It is only drawn at whole multiples of that,
## 8, 16, 24, 32..., so a glyph pixel is always a whole number of grid pixels: `px()` turns
## the sizes the layouts were written in (the old vector font's) into the nearest one.
##
## Rows are soft dark slabs with rounded corners; the focused one lifts (a lighter fill,
## an accent bar down its left edge and a faint glow), hover only lightens. Cards (the
## Single player and Settings hubs) are taller rows that carry a second, dimmer line.

const C_TEXT := Hud.C_TEXT
const C_DIM := Hud.C_DIM
const C_ACCENT := Hud.C_ACCENT
const C_DARK := Color(0.08, 0.08, 0.1)
const C_ROW := Color(0.11, 0.12, 0.15, 0.9)
const C_ROW_HOVER := Color(0.14, 0.15, 0.19, 0.95)
const C_ROW_FOCUS := Color(0.17, 0.18, 0.23, 1.0)
const C_PANEL := Color(0.055, 0.065, 0.09, 0.94)
const C_BORDER := Color(1, 1, 1, 0.07)
const C_RULE := Color(1, 1, 1, 0.12)

const SIZE_TITLE := 18
const SIZE_HEADING := 9
const SIZE_ROW := 9
const SIZE_BIG := 12
const SIZE_LOGO := 24
const SIZE_HINT := 6
const SIZE_SUB := 6  ## a card's second line
const CARD_HEIGHT := 19.0
const SIZE_LOGO_SMALL := 16  ## the logo over a page that has its own title
const RADIUS := 3

const FONT_PATH := "res://assets/fonts/m5x7.ttf"
## The pixel font's native size in canvas units (16 grid pixels; its glyphs are 5 x 7).
const FONT_NATIVE := 8

static var _font: Font


## The pixel font (imported with antialiasing, hinting and subpixel positioning off and a
## fixed oversampling of 2: one canvas unit is two grid pixels, so a glyph is rasterised
## on the grid and scaled up like a sprite).
static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH) as Font
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


## A layout's text size (the size it was written for, a vector font's) as a pixel-font
## size, a whole multiple of FONT_NATIVE: 5-6 → 8 (the small print: hints, tags, the
## controls strip), 7-11 → 16 (names, rows), 12-15 → 24, 16-20 → 32, 21-26 → 40, 27+ → 48.
static func px(design_size: int) -> int:
	for step in PX_STEPS:
		if design_size <= int(step[0]):
			return int(step[1])
	return FONT_NATIVE * 6

const PX_STEPS := [[6, 8], [11, 16], [15, 24], [20, 32], [26, 40]]


## The pixel font with narrower spaces (2 grid pixels instead of 4), for a line of small
## print that would run off a narrow screen (the controls strip).
static func font_tight() -> Font:
	if _tight == null:
		var v := FontVariation.new()
		v.base_font = font()
		v.spacing_space = -1
		_tight = v
	return _tight

static var _tight: Font


## An outline round pixel text: one glyph pixel at 2x and up (canvas units), one canvas
## unit under that.
static func outline(size_px: int) -> int:
	return maxi(1, size_px / (FONT_NATIVE * 2))


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = px(SIZE_ROW)

	var normal := _box(C_ROW)
	var hover := _box(C_ROW_HOVER)
	var focus := _box(C_ROW_FOCUS)
	focus.border_width_left = 3
	focus.border_color = C_ACCENT
	focus.shadow_color = Color(C_ACCENT, 0.18)
	focus.shadow_size = 3
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, "Button", normal)
	for state in ["hover", "pressed", "hover_pressed"]:
		t.set_stylebox(state, "Button", hover)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", C_TEXT)
	for c in ["font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", C_ACCENT)
	t.set_color("font_disabled_color", "Button", C_DIM)
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Button", outline(px(SIZE_ROW)))
	t.set_font_size("font_size", "Button", px(SIZE_ROW))

	# The title menu's big buttons: filled in the accent colour when focused.
	t.set_type_variation("BigButton", "Button")
	var big := _box(C_ROW)
	big.content_margin_left = 8
	big.content_margin_top = 3
	big.content_margin_bottom = 3
	var big_hover := _box(C_ROW_HOVER)
	big_hover.content_margin_left = 8
	big_hover.content_margin_top = 3
	big_hover.content_margin_bottom = 3
	var big_focus := _box(Color(C_ACCENT, 0.94))
	big_focus.content_margin_left = 8
	big_focus.content_margin_top = 3
	big_focus.content_margin_bottom = 3
	big_focus.shadow_color = Color(C_ACCENT, 0.3)
	big_focus.shadow_size = 5
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, "BigButton", big)
	for state in ["hover", "pressed", "hover_pressed"]:
		t.set_stylebox(state, "BigButton", big_hover)
	t.set_stylebox("focus", "BigButton", big_focus)
	for c in ["font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "BigButton", C_DARK)
	t.set_color("font_hover_color", "BigButton", C_ACCENT)
	t.set_font_size("font_size", "BigButton", px(SIZE_BIG))
	t.set_constant("outline_size", "BigButton", 0)

	# Cards: a taller row whose text sits in the top half; CardButton draws the second line.
	t.set_type_variation("Card", "Button")
	for state_box in [["normal", _box(C_ROW)], ["disabled", _box(C_ROW)], ["hover", _box(C_ROW_HOVER)],
			["pressed", _box(C_ROW_HOVER)], ["hover_pressed", _box(C_ROW_HOVER)]]:
		var b: StyleBoxFlat = state_box[1]
		b.content_margin_top = 2
		b.content_margin_bottom = CARD_HEIGHT - 12
		t.set_stylebox(String(state_box[0]), "Card", b)
	var card_focus := _box(C_ROW_FOCUS)
	card_focus.content_margin_top = 2
	card_focus.content_margin_bottom = CARD_HEIGHT - 12
	card_focus.border_width_left = 3
	card_focus.border_color = C_ACCENT
	card_focus.shadow_color = Color(C_ACCENT, 0.18)
	card_focus.shadow_size = 3
	t.set_stylebox("focus", "Card", card_focus)

	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 1)
	t.set_constant("line_spacing", "Label", 0)

	var field := _box(Color(0.03, 0.035, 0.05, 0.95))
	field.border_width_bottom = 1
	field.border_color = C_DIM
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_width_left = 3
	field_focus.border_color = C_ACCENT
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", C_DIM)
	t.set_color("caret_color", "LineEdit", C_ACCENT)
	t.set_font_size("font_size", "LineEdit", px(SIZE_ROW))

	# The frame round a screen's column.
	var panel := StyleBoxFlat.new()
	panel.bg_color = C_PANEL
	panel.corner_radius_top_left = 5
	panel.corner_radius_top_right = 5
	panel.corner_radius_bottom_left = 5
	panel.corner_radius_bottom_right = 5
	panel.border_width_left = 1
	panel.border_width_right = 1
	panel.border_width_top = 1
	panel.border_width_bottom = 1
	panel.border_color = C_BORDER
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 8
	panel.shadow_offset = Vector2(0, 3)
	panel.content_margin_left = 9
	panel.content_margin_right = 9
	panel.content_margin_top = 6
	panel.content_margin_bottom = 5
	t.set_stylebox("panel", "PanelContainer", panel)

	t.set_constant("separation", "VBoxContainer", 2)
	t.set_constant("separation", "HBoxContainer", 6)
	return t


static func _box(col: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	b.corner_radius_top_left = RADIUS
	b.corner_radius_top_right = RADIUS
	b.corner_radius_bottom_left = RADIUS
	b.corner_radius_bottom_right = RADIUS
	b.content_margin_left = 10
	b.content_margin_right = 8
	b.content_margin_top = 1
	b.content_margin_bottom = 1
	return b
