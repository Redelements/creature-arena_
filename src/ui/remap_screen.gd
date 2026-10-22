class_name RemapScreen
extends UiScreen
## Remaps one binding group (Classic keyboard, League-style keyboard or the controller):
## pick an action, press the new key or button. A key another action already used moves
## over to it and that action gets the old one (a swap), so nothing is doubled up.
## Changes apply at once; `changed` tells main to save them.

signal changed

## Keys the game keeps for itself (pause, tools, mute).
const RESERVED_KEYS := [KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F9, KEY_M]
## Buttons the controller keeps (pause and moving through menus).
const RESERVED_BUTTONS := [JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_GUIDE]

var group := "classic"
var _rows := {}  ## action -> KeyRow
var _waiting := ""  ## the action waiting for a press ("" when not)


## A row with the binding shown on the right.
class KeyRow extends Button:
	var value := ""

	func _init() -> void:
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _draw() -> void:
		var font := get_theme_font("font")
		var fs := get_theme_font_size("font_size")
		var col := get_theme_color("font_focus_color" if has_focus() else "font_color")
		var w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
		draw_string_outline(font, Vector2(size.x - 8 - w, base), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2,
			Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(size.x - 8 - w, base), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _init(p_group := "classic") -> void:
	super()
	group = p_group
	logo = false
	title = {"classic": "CLASSIC KEYBOARD", "league": "LEAGUE-STYLE KEYBOARD", "gamepad": "CONTROLLER"}[group]
	subtitle = "Choose an action, then press its new key" if group != "gamepad" else \
		"Choose an action, then press its new button or trigger"
	row_width = 250.0
	row_height = 12.0
	row_font = 8
	row_gap = 1
	hints = ["move", "select", "back"]


## The bindings sit in two columns (fourteen on a keyboard would not fit in one), the
## two buttons under them.
func build() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", row_gap)
	_list.add_child(grid)
	for pair in Controls.REMAP[group]:
		var action := String(pair[0])
		var r := KeyRow.new()
		r.text = String(pair[1])
		r.pressed.connect(func(): _listen(action))
		var what := "Press Enter / A, then the new %s" % ("button" if group == "gamepad" else "key")
		r.custom_minimum_size = Vector2((row_width - 4) * 0.5, row_height)
		r.focus_mode = Control.FOCUS_ALL
		r.add_theme_font_size_override("font_size", row_font)
		r.mouse_entered.connect(func(): if r.is_visible_in_tree(): r.grab_focus())
		r.focus_entered.connect(func(): _show_description(r))
		_descriptions[r] = what
		grid.add_child(r)
		_rows[action] = r
	add_space(2)
	add_button("Reset to defaults", func():
		Controls.reset(group)
		_refresh()
		changed.emit(), "Put every %s binding back" % ("controller" if group == "gamepad" else "key"))
	add_button("Back", back)
	_refresh()


## The key rows first (reading order), then the buttons.
func rows() -> Array:
	var out: Array = []
	for c in _list.get_children():
		if c is GridContainer:
			out.append_array(c.get_children())
	out.append_array(super())
	return out


## Up/Down walk a column of the grid and wrap through the buttons; Left/Right cross
## between the two columns.
func link_focus() -> void:
	var keys: Array = []
	for c in _list.get_children():
		if c is GridContainer:
			keys = c.get_children()
	var buttons: Array = super.rows()
	var n := keys.size()
	for i in n:
		var c: Control = keys[i]
		var up: Control = keys[i - 2] if i >= 2 else buttons[-1]
		var down: Control = keys[i + 2] if i + 2 < n else buttons[0]
		var side: Control = keys[i ^ 1] if (i ^ 1) < n else c
		c.focus_neighbor_top = c.get_path_to(up)
		c.focus_neighbor_bottom = c.get_path_to(down)
		c.focus_neighbor_left = c.get_path_to(side)
		c.focus_neighbor_right = c.get_path_to(side)
		c.focus_previous = c.get_path_to(keys[i - 1] if i > 0 else buttons[-1])
		c.focus_next = c.get_path_to(keys[i + 1] if i + 1 < n else buttons[0])
	for i in buttons.size():
		var b: Control = buttons[i]
		var up: Control = buttons[i - 1] if i > 0 else keys[-1]
		var down: Control = buttons[i + 1] if i + 1 < buttons.size() else keys[0]
		b.focus_neighbor_top = b.get_path_to(up)
		b.focus_neighbor_bottom = b.get_path_to(down)
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)
		b.focus_previous = b.focus_neighbor_top
		b.focus_next = b.focus_neighbor_bottom


func back() -> void:
	if _waiting != "":
		_stop_listening()
		return
	super()


func _listen(action: String) -> void:
	_waiting = action
	(_rows[action] as KeyRow).value = "press a %s..." % ("button" if group == "gamepad" else "key")
	(_rows[action] as KeyRow).queue_redraw()
	describe(_rows[action], ("Start / View" if group == "gamepad" else "Esc") + " cancels")


func _stop_listening() -> void:
	var a := _waiting
	_waiting = ""
	_refresh()
	if _rows.has(a):
		describe(_rows[a], "Press Enter / A, then the new %s" % ("button" if group == "gamepad" else "key"))


## While waiting, the next key / button / trigger is the new binding (before the menu sees it).
func _input(event: InputEvent) -> void:
	if _waiting == "" or not is_visible_in_tree():
		return
	var accepted := false
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ESCAPE:
			_stop_listening()
			get_viewport().set_input_as_handled()
			return
		if group != "gamepad" and not (k in RESERVED_KEYS):
			accepted = true
	elif event is InputEventJoypadButton and event.pressed:
		var b := (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_START or b == JOY_BUTTON_BACK:
			_stop_listening()
			get_viewport().set_input_as_handled()
			return
		accepted = group == "gamepad" and not (b in RESERVED_BUTTONS)
	elif event is InputEventJoypadMotion and group == "gamepad":
		var m := event as InputEventJoypadMotion
		accepted = (m.axis == JOY_AXIS_TRIGGER_LEFT or m.axis == JOY_AXIS_TRIGGER_RIGHT) and m.axis_value > 0.6
	if not accepted:
		if event is InputEventKey or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()  # not moving through the menu meanwhile
		return
	get_viewport().set_input_as_handled()
	Controls.rebind(group, _waiting, event)
	_stop_listening()
	changed.emit()
	if stack != null:
		stack.notify_chosen()


func _refresh() -> void:
	for action in _rows:
		var r: KeyRow = _rows[action]
		r.value = Controls.binding_text(action, group)
		r.queue_redraw()
