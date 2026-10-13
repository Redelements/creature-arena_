class_name RemapScreen
extends UiScreen
## Remaps one binding group (Classic keyboard, League-style keyboard or the controller):
## pick an action, press the new key or button. A key another action already used moves
## over to it and that action gets the old one (a swap), so nothing is doubled up.
## Changes apply at once; `changed` tells main to save them.

signal changed

## Keys the game keeps for itself (pause, tools, mute).
const RESERVED_KEYS := [KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_M]
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
	row_width = 230.0
	row_height = 12.0
	row_font = 8
	row_gap = 1
	hints = ["move", "select", "back"]


func build() -> void:
	for pair in Controls.REMAP[group]:
		var action := String(pair[0])
		var r := KeyRow.new()
		r.text = String(pair[1])
		r.pressed.connect(func(): _listen(action))
		add_row(r, "Press Enter / A, then the new %s" % ("button" if group == "gamepad" else "key"))
		_rows[action] = r
	add_space(3)
	add_button("Reset to defaults", func():
		Controls.reset(group)
		_refresh()
		changed.emit(), "Put every %s binding back" % ("controller" if group == "gamepad" else "key"))
	add_button("Back", back)
	_refresh()


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
