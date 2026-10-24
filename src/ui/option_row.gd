class_name OptionRow
extends Button
## A menu row with a value, shown on the right: "Music            < 70% >". Left/Right
## step it (held keys repeat). On the mouse, a click on the left or right half of the
## value steps it back or forward; a click on the label does what Enter does.
##
## Enter steps forward (a setting), or with `activates` it fires `activated` instead (a
## Single player row: Left/Right pick the fighter, Enter starts). `bar` >= 0 draws a
## meter before the value (volumes).

signal changed(index: int)
signal activated

var label := ""
var values: Array = []
var index := 0
var wrap := true
var activates := false
var bar := -1.0

const BAR_W := 44.0
const GAP := 8.0
## Room kept for the value beside a bar (the widest is "<  muted (M)  >").
const BAR_VALUE_ROOM := 74.0


func _init(p_label := "", p_values: Array = [], p_index := 0) -> void:
	label = p_label
	values = p_values
	index = clampi(p_index, 0, maxi(0, p_values.size() - 1))
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	button_mask = 0  # clicks are handled below, by where they land
	pressed.connect(_on_pressed)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	refresh()


func set_values(p_values: Array, p_index: int) -> void:
	values = p_values
	index = clampi(p_index, 0, maxi(0, values.size() - 1))
	refresh()


func value_text() -> String:
	return "<  %s  >" % String(values[index]) if index < values.size() else ""


func refresh() -> void:
	text = label
	queue_redraw()


func step(dir: int) -> void:
	var n := values.size()
	if n == 0:
		return
	var i := (index + dir + n) % n if wrap else clampi(index + dir, 0, n - 1)
	if i == index:
		return
	index = i
	refresh()
	changed.emit(index)


func _on_pressed() -> void:
	if activates:
		activated.emit()
	else:
		step(1)


## Where the value starts (x), for drawing and for telling which half a click hit.
func _value_rect() -> Rect2:
	var font := get_theme_font("font")
	var fs := get_theme_font_size("font_size")
	var w := font.get_string_size(value_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var right := size.x - 8.0
	return Rect2(right - w, 0, w, size.y)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		step(1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			var v := _value_rect()
			if mb.position.x >= v.position.x - 6.0:
				step(-1 if mb.position.x < v.get_center().x else 1)
			else:
				_on_pressed()
			accept_event()


func _draw() -> void:
	var font := get_theme_font("font")
	var fs := get_theme_font_size("font_size")
	var focus := has_focus()
	var col := get_theme_color("font_focus_color" if focus else "font_color")
	var v := _value_rect()
	var base := (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string_outline(font, Vector2(v.position.x, base), value_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UiTheme.outline(fs), Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(v.position.x, base), value_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if bar < 0.0:
		return
	# A fixed spot, so the bars line up whatever the value's width ("Off" or "100%").
	var bx := minf(v.position.x, size.x - 8.0 - BAR_VALUE_ROOM) - GAP - BAR_W
	var r := Rect2(bx, size.y * 0.5 - 2, BAR_W, 4)
	draw_rect(r, Hud.C_BAR_BG)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(bar, 0.0, 1.0), r.size.y)),
		UiTheme.C_ACCENT if focus else UiTheme.C_DIM)
	for k in range(1, 10):
		draw_rect(Rect2(r.position.x + r.size.x * k / 10.0, r.position.y, 1, r.size.y), Color(0, 0, 0, 0.35))
