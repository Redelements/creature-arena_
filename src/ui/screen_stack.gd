class_name ScreenStack
extends CanvasLayer
## The menu screens open right now, newest on top: push() opens one over the others,
## Back (B / Esc / View, or Start for a pause screen) closes the top one, and the screen
## underneath gets its focus back where it was. Only the top screen is shown.
##
## Main forwards nothing: the stack reads Back itself, and Godot's focus system does the
## rest. It tells main when to play the menu sounds (moved / chosen) and when the last
## screen closes (emptied).

signal moved
signal chosen
signal emptied

var screens: Array[UiScreen] = []
var ui_theme: Theme
var gamepad := false
var _focus := {}  ## screen -> the Control it had focused when covered
var _quiet := false
var _toast: Label
var _toast_t := 0.0


func _init() -> void:
	layer = 20
	ui_theme = UiTheme.make()


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_toast = Label.new()
	_toast.theme = ui_theme
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 4
	_toast.offset_bottom = 16
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", UiTheme.px(8))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.z_index = 10
	add_child(_toast)


## A short message over the screens (the HUD's toasts are under them).
func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.0
	_toast.modulate.a = 1.0
	move_child(_toast, get_child_count() - 1)


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)


func is_open() -> bool:
	return not screens.is_empty()


func top() -> UiScreen:
	return screens.back() if not screens.is_empty() else null


func push(s: UiScreen) -> UiScreen:
	var below := top()
	if below != null:
		var f := get_viewport().gui_get_focus_owner()
		if f != null and below.is_ancestor_of(f):
			_focus[below] = f
		below.visible = false
	s.stack = self
	s.theme = ui_theme
	s.set_gamepad(gamepad)
	screens.append(s)
	add_child(s)
	_quiet = true
	s.focus_first()
	_quiet = false
	return s


func pop() -> void:
	if screens.is_empty():
		return
	var s: UiScreen = screens.pop_back()
	_focus.erase(s)
	s.queue_free()
	var below := top()
	if below == null:
		var f := get_viewport().gui_get_focus_owner()
		if f != null:
			f.release_focus()
		emptied.emit()
		return
	below.visible = true
	_quiet = true
	var f: Control = _focus.get(below)
	if f != null and is_instance_valid(f) and f.is_visible_in_tree():
		f.grab_focus()
	else:
		below.focus_first()
	_quiet = false
	_focus.erase(below)


## Closes every screen (a match ending, the game going back to the title).
func clear() -> void:
	var had := is_open()
	for s in screens:
		s.queue_free()
	screens.clear()
	_focus.clear()
	if had:
		emptied.emit()


func set_gamepad(on: bool) -> void:
	gamepad = on
	for s in screens:
		s.set_gamepad(on)


## Back on the top screen. "pause" too, so Start / Esc closes a pause menu it opened.
func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu_back") \
			or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		chosen.emit()
		top().back()


func _on_focus_changed(c: Control) -> void:
	if _quiet or not is_open() or c == null or not top().is_ancestor_of(c):
		return
	moved.emit()


## Every Button press on a screen (OptionRow changes count as moves).
func notify_chosen() -> void:
	chosen.emit()
