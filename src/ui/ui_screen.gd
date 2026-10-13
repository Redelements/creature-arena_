class_name UiScreen
extends Control
## One menu screen: a heading, a column of rows, a line describing the focused row, and
## a hint line at the bottom. Subclasses (or whoever makes one) add rows in build();
## ScreenStack shows it and handles Back.
##
## Rows are ordinary Controls (Buttons, OptionRows, a LineEdit...), so Godot's focus
## system moves between them with the arrows, the d-pad and the stick (MenuStick), and the
## mouse focuses whatever it's over. The column wraps round from the last row to the first.

## Pressed Back (B / Esc) on this screen. The default closes it.
signal backed

## The game's name over the page (title, Single player and Settings pages).
var logo := false
var title := ""
var subtitle := ""
## Hint line items for Prompts.line(); empty: no hint line.
var hints: Array = ["move", "select", "back"]
## How dark the screen behind is drawn (0: not at all).
var dim := 0.82
var row_width := 220.0
var row_height := 15.0
## Row text size (0: the theme's) and the gap between rows; long pages go compact.
var row_font := 0
var row_gap := 2
## A theme type variation for the rows ("BigButton" on the title menu), and their text
## alignment.
var row_variation := ""
var row_align := HORIZONTAL_ALIGNMENT_LEFT
## Moves the whole column down (or up), e.g. to leave a banner visible above it.
var column_shift := 0.0
var stack: ScreenStack = null
## The row to focus when the screen opens (null: the first).
var default_focus: Control = null
## Builds the rows when the screen has no subclass of its own: builder.call(screen).
var builder := Callable()
## What Back does instead of closing the screen.
var on_back := Callable()

var _list: VBoxContainer
var _desc: Label
var _hint: Label
var _gamepad := false
var _descriptions := {}  ## row -> text shown while it's focused


func _init() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.07, dim)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(PRESET_FULL_RECT)
	col.offset_top = 22 + column_shift
	col.offset_bottom = -34 + column_shift
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(col)
	if logo:
		col.add_child(_label("CREATURE ARENA", UiTheme.SIZE_LOGO, UiTheme.C_TEXT))
		col.add_child(_label("prototype build", UiTheme.SIZE_HINT + 1, UiTheme.C_DIM))
		if title != "":
			col.add_child(_label(title, UiTheme.SIZE_HEADING, UiTheme.C_ACCENT))
	elif title != "":
		col.add_child(_label(title, UiTheme.SIZE_TITLE, UiTheme.C_TEXT))
	if subtitle != "":
		col.add_child(_label(subtitle, UiTheme.SIZE_HINT + 1, UiTheme.C_DIM))
	if logo or title != "" or subtitle != "":
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		col.add_child(gap)
	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(center)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(row_width, 0)
	_list.add_theme_constant_override("separation", row_gap)
	center.add_child(_list)
	_desc = _label("", UiTheme.SIZE_HINT, UiTheme.C_DIM)
	_desc.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_desc.offset_top = -38
	_desc.offset_bottom = -28
	add_child(_desc)
	_hint = _label("", UiTheme.SIZE_HINT, UiTheme.C_DIM)
	_hint.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_hint.offset_top = -26
	_hint.offset_bottom = -16
	add_child(_hint)
	build()
	link_focus()
	refresh_hint()


## Subclasses add their rows here (or set `builder`).
func build() -> void:
	if builder.is_valid():
		builder.call(self)


## Back (B / Esc): closes the screen, unless `on_back` says otherwise or a subclass
## overrides it (screens with something to confirm).
func back() -> void:
	backed.emit()
	if on_back.is_valid():
		on_back.call()
	elif stack != null:
		stack.pop()


func add_button(text: String, on_press: Callable, description := "") -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = row_align
	b.pressed.connect(func(): if stack != null: stack.notify_chosen())
	b.pressed.connect(on_press)
	add_row(b, description)
	return b


func add_option(label: String, values: Array, index: int, on_change: Callable, description := "") -> OptionRow:
	var o := OptionRow.new(label, values, index)
	o.changed.connect(func(_i): if stack != null: stack.moved.emit())
	o.changed.connect(on_change)
	add_row(o, description)
	return o


## A line of text in the column (not focusable).
func add_text(text: String, size_px := UiTheme.SIZE_HINT + 1, col := UiTheme.C_DIM) -> Label:
	var l := _label(text, size_px, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(row_width, 0)
	_list.add_child(l)
	return l


## A gap in the column.
func add_space(px := 6.0) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, px)
	gap.mouse_filter = MOUSE_FILTER_IGNORE
	_list.add_child(gap)


## Any focusable Control as a row: sized to the column, and the mouse focuses it.
func add_row(c: Control, description := "") -> void:
	c.custom_minimum_size = Vector2(row_width, row_height)
	c.focus_mode = Control.FOCUS_ALL
	if row_variation != "" and c is Button and not (c is OptionRow):
		c.theme_type_variation = row_variation
	if row_font > 0:
		c.add_theme_font_size_override("font_size", row_font)
	c.mouse_entered.connect(func(): if c.is_visible_in_tree() and c.focus_mode != FOCUS_NONE: c.grab_focus())
	_descriptions[c] = description
	c.focus_entered.connect(func(): _show_description(c))
	_list.add_child(c)


## The line under the column while `c` is focused.
func describe(c: Control, text: String) -> void:
	_descriptions[c] = text
	if c.has_focus():
		_show_description(c)


func rows() -> Array:
	var out: Array = []
	for c in _list.get_children():
		if c is Control and (c as Control).focus_mode != Control.FOCUS_NONE and (c as Control).visible:
			out.append(c)
	return out


## Up/Down walk the column and wrap round; Left/Right stay put (OptionRows use them).
func link_focus() -> void:
	var r := rows()
	for i in r.size():
		var c: Control = r[i]
		c.focus_neighbor_top = c.get_path_to(r[(i - 1 + r.size()) % r.size()])
		c.focus_neighbor_bottom = c.get_path_to(r[(i + 1) % r.size()])
		c.focus_neighbor_left = c.get_path_to(c)
		c.focus_neighbor_right = c.get_path_to(c)
		c.focus_previous = c.focus_neighbor_top
		c.focus_next = c.focus_neighbor_bottom


func focus_first() -> void:
	var r := rows()
	if default_focus != null and default_focus in r:
		default_focus.grab_focus()
	elif not r.is_empty():
		(r[0] as Control).grab_focus()


func set_gamepad(on: bool) -> void:
	_gamepad = on
	refresh_hint()


func refresh_hint() -> void:
	if _hint != null:
		_hint.text = Prompts.line(_gamepad, hints) if not hints.is_empty() else ""


func _show_description(c: Control) -> void:
	if _desc != null:
		_desc.text = String(_descriptions.get(c, ""))


func _label(text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l
