class_name UiScreen
extends Control
## One menu screen: a heading, a column of rows, a description of the focused row (in a
## panel on the right with `detail`, else a line under the column) and a hint line at the
## bottom. Subclasses (or whoever makes one) add rows in build(); ScreenStack shows it and
## handles Back.
##
## Nothing on a screen moves while it is open: the description's box is sized once, for
## the longest text it will show, so a longer line can't grow the panel and shift the rows
## under a still mouse (which refocused another row, which changed the text again).
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
## The pages above this one, shown as a trail over the title ("SINGLE PLAYER  ›  TEAM BATTLES").
var crumbs: Array = []
## A framed panel round the column (off on the title menu, whose big buttons stand alone).
var framed := true
## The line under the rows describing the focused one (off where the rows say it all).
var show_desc := true
## Two panes: the rows on the left and a panel on the right, the same height as the
## column, with the focused row's title, its description and its card (`card()`: a
## fighter's preview, a picture, a few facts). For pages with a lot to say; the pause and
## match-over menus keep the line.
var detail := false
var detail_width := 150.0
## What the panel says for a row with no description of its own (Back): the page's.
var blurb := ""
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
var _detail_title: Label
var _extra: Control  ## the cards' slot under the text, the tallest card high
var _cards := {}  ## row -> DetailCard
var _hint: Label
var _gamepad := false
var _descriptions := {}  ## row -> text shown while it's focused
var _titles := {}  ## row -> the panel's title when the row has no text of its own


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
	col.offset_top = 12 + column_shift
	col.offset_bottom = -30 + column_shift
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(col)
	if logo:
		# Full size on the title menu; smaller over a page with a title of its own.
		col.add_child(_label("CREATURE ARENA", UiTheme.SIZE_LOGO if title == "" else UiTheme.SIZE_LOGO_SMALL, UiTheme.C_TEXT))
		col.add_child(_rule(60.0 if title == "" else 44.0))
		if title == "":
			col.add_child(_label("prototype build", UiTheme.SIZE_HINT + 1, UiTheme.C_DIM))
	if not crumbs.is_empty():
		col.add_child(_label("  ›  ".join(PackedStringArray(crumbs)) + "  ›", UiTheme.SIZE_HINT + 1, UiTheme.C_DIM))
	if title != "":
		col.add_child(_label(title, UiTheme.SIZE_HEADING if logo else UiTheme.SIZE_TITLE,
			UiTheme.C_ACCENT if logo else UiTheme.C_TEXT))
	if subtitle != "":
		col.add_child(_label(subtitle, UiTheme.SIZE_HINT + 1, UiTheme.C_DIM))
	if logo or title != "" or subtitle != "":
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		col.add_child(gap)
	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(center)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(row_width, 0)
	_list.add_theme_constant_override("separation", row_gap)
	_desc = _label("", UiTheme.SIZE_HINT, UiTheme.C_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if framed and detail:
		# Two panes in one frame: the column, a rule, and the panel. The panel's width is
		# fixed and its text box is sized after build() for the longest description.
		var frame := PanelContainer.new()
		frame.mouse_filter = MOUSE_FILTER_IGNORE
		center.add_child(frame)
		var panes := HBoxContainer.new()
		panes.add_theme_constant_override("separation", 7)
		panes.mouse_filter = MOUSE_FILTER_IGNORE
		frame.add_child(panes)
		panes.add_child(_list)
		var vr := ColorRect.new()
		vr.color = UiTheme.C_RULE
		vr.custom_minimum_size = Vector2(1, 0)
		vr.mouse_filter = MOUSE_FILTER_IGNORE
		panes.add_child(vr)
		var side := VBoxContainer.new()
		side.custom_minimum_size = Vector2(detail_width, 0)
		side.add_theme_constant_override("separation", 3)
		side.mouse_filter = MOUSE_FILTER_IGNORE
		panes.add_child(side)
		_detail_title = _label("", UiTheme.SIZE_ROW, UiTheme.C_ACCENT)
		_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_detail_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_detail_title.custom_minimum_size = Vector2(detail_width, 13.0)
		_detail_title.clip_text = true
		side.add_child(_detail_title)
		side.add_child(_rule(detail_width))
		_desc.add_theme_font_size_override("font_size", UiTheme.SIZE_HINT + 1)
		_desc.add_theme_color_override("font_color", Color(UiTheme.C_TEXT, 0.9))
		_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_desc.custom_minimum_size = Vector2(detail_width, 0)
		side.add_child(_desc)
		var spring := Control.new()  # the card sits at the panel's foot, the text at its head
		spring.size_flags_vertical = SIZE_EXPAND_FILL
		spring.mouse_filter = MOUSE_FILTER_IGNORE
		side.add_child(spring)
		_extra = Control.new()
		_extra.mouse_filter = MOUSE_FILTER_IGNORE
		_extra.custom_minimum_size = Vector2(detail_width, 0)
		side.add_child(_extra)
	elif framed:
		# The column and its description line in one panel.
		var frame := PanelContainer.new()
		frame.mouse_filter = MOUSE_FILTER_IGNORE
		center.add_child(frame)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 3)
		inner.mouse_filter = MOUSE_FILTER_IGNORE
		frame.add_child(inner)
		inner.add_child(_list)
		if show_desc:
			inner.add_child(_rule(row_width))
			# Two lines, always: a one-line text leaves the second empty, a longer one is cut.
			_desc.max_lines_visible = 2
			_desc.custom_minimum_size = Vector2(row_width, _lines_height(_desc, 2))
			_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			inner.add_child(_desc)
	else:
		center.add_child(_list)
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
	if _detail_title != null:
		_size_detail()


## The panel's text box, sized once for the longest text any row (or the page) shows.
func _size_detail() -> void:
	var texts: Array = _descriptions.values()
	texts.append(blurb)
	var font := _desc.get_theme_font("font")
	var fs := _desc.get_theme_font_size("font_size")
	var tallest := 0.0
	for t in texts:
		var sz := font.get_multiline_string_size(String(t), HORIZONTAL_ALIGNMENT_LEFT, detail_width, fs,
			-1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
		tallest = maxf(tallest, sz.y)
	# Half a line of slack: the Label's own wrapping can differ from the measure by a hair.
	_desc.custom_minimum_size = Vector2(detail_width, tallest + font.get_height(fs) * 0.5)
	_size_extra()


## The cards' slot: as tall as the tallest card, so a row's card never moves the frame.
func _size_extra() -> void:
	if _extra == null:
		return
	var tallest := 0.0
	for c in _cards.values():
		tallest = maxf(tallest, (c as DetailCard).height())
	_extra.custom_minimum_size = Vector2(detail_width, tallest)


## The card shown under the text while `c` is focused (made on first ask; null on a
## screen without the panel). A row keeps its card's height constant: swap what it
## shows, not how much.
func card(c: Control) -> DetailCard:
	if _extra == null:
		return null
	if _cards.has(c):
		return _cards[c]
	var k := DetailCard.new(detail_width)
	k.size = Vector2(detail_width, 0)
	k.visible = c.has_focus()
	k.changed.connect(func():
		k.size = Vector2(detail_width, k.height())
		_size_extra())
	_extra.add_child(k)
	_cards[c] = k
	return k


## The height of `n` lines of a label's font.
func _lines_height(l: Label, n: int) -> float:
	return l.get_theme_font("font").get_height(l.get_theme_font_size("font_size")) * n + 1.0


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


## A card: a taller row with a second line, for a hub of pages.
func add_card(title_text: String, sub: String, on_press: Callable, description := "") -> CardButton:
	var c := CardButton.new(title_text, sub)
	c.pressed.connect(func(): if stack != null: stack.notify_chosen())
	c.pressed.connect(on_press)
	var h := row_height
	row_height = UiTheme.CARD_HEIGHT
	add_row(c, description)
	row_height = h
	return c


## A small heading over a run of rows, with a thin rule.
func add_heading(text: String) -> void:
	var l := _label(text.to_upper(), UiTheme.SIZE_HINT, UiTheme.C_ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.custom_minimum_size = Vector2(row_width, 0)
	_list.add_child(l)
	_list.add_child(_rule(row_width))


func _rule(width: float) -> Control:
	var wrap := CenterContainer.new()
	wrap.mouse_filter = MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = UiTheme.C_RULE
	r.custom_minimum_size = Vector2(width, 1)
	r.mouse_filter = MOUSE_FILTER_IGNORE
	wrap.add_child(r)
	return wrap


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
	if row_variation != "" and c is Button and not (c is OptionRow) and not (c is CardButton):
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


## The panel's title while `c` is focused, for a row that isn't a Button or an OptionRow
## (a text field).
func entitle(c: Control, text: String) -> void:
	_titles[c] = text
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
	if _desc == null:
		return
	var text := String(_descriptions.get(c, ""))
	if _detail_title != null:
		_detail_title.text = _row_title(c)
		_desc.text = text if text != "" else blurb
		for row in _cards:
			(_cards[row] as DetailCard).visible = row == c
	else:
		_desc.text = text


## What the panel calls a row: an OptionRow's label, a Button's text, or what `entitle` said.
func _row_title(c: Control) -> String:
	if _titles.has(c):
		return String(_titles[c])
	if c is OptionRow:
		return (c as OptionRow).label
	if c is Button:
		return (c as Button).text
	return ""


func _label(text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l
