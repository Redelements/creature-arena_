class_name UiTheme
extends RefCounted
## The one look every menu screen shares, built in code like the input bindings: the
## HUD's colours, its font, outlined text. Screens get it from ScreenStack.

const C_TEXT := Hud.C_TEXT
const C_DIM := Hud.C_DIM
const C_ACCENT := Hud.C_ACCENT
const C_DARK := Color(0.08, 0.08, 0.1)
const C_ROW := Color(0.07, 0.08, 0.1, 0.75)
const C_ROW_FOCUS := Color(1, 1, 1, 0.1)

const SIZE_TITLE := 18
const SIZE_HEADING := 9
const SIZE_ROW := 9
const SIZE_BIG := 12
const SIZE_LOGO := 24
const SIZE_HINT := 6


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = ThemeDB.fallback_font
	t.default_font_size = SIZE_ROW

	var normal := _box(C_ROW)
	var focus := _box(C_ROW_FOCUS)
	focus.border_width_left = 3
	focus.border_color = C_ACCENT
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, "Button", normal)
	for state in ["hover", "pressed", "hover_pressed"]:
		t.set_stylebox(state, "Button", normal)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", C_TEXT)
	for c in ["font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", C_ACCENT)
	t.set_color("font_disabled_color", "Button", C_DIM)
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Button", 2)
	t.set_font_size("font_size", "Button", SIZE_ROW)

	# The title menu's big buttons: filled in the accent colour when focused.
	t.set_type_variation("BigButton", "Button")
	var big := _box(C_ROW)
	big.content_margin_left = 8
	var big_focus := _box(Color(C_ACCENT, 0.92))
	big_focus.content_margin_left = 8
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "BigButton", big)
	t.set_stylebox("focus", "BigButton", big_focus)
	for c in ["font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "BigButton", C_DARK)
	t.set_font_size("font_size", "BigButton", SIZE_BIG)
	t.set_constant("outline_size", "BigButton", 0)

	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 2)
	t.set_constant("line_spacing", "Label", 0)

	var field := _box(Color(0.02, 0.02, 0.03, 0.9))
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
	t.set_font_size("font_size", "LineEdit", SIZE_ROW)

	t.set_constant("separation", "VBoxContainer", 2)
	t.set_constant("separation", "HBoxContainer", 6)
	return t


static func _box(col: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	b.content_margin_left = 10
	b.content_margin_right = 8
	b.content_margin_top = 1
	b.content_margin_bottom = 1
	return b
