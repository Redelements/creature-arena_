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
## The meter's width (a row with a tag after its label can take a shorter one).
var bar_width := BAR_W
## Values shown greyed (a locked reward on the Profile): true per index; still steppable,
## the screen decides what a locked one does.
var locked: Array = []
## A short accent tag drawn after the label ("New!"), or "".
var tag := "":
	set(v):
		tag = v
		queue_redraw()

## Room kept for the value beside a bar (a row whose values are short can keep less, and
## its label gets the rest: the Profile's challenges, "37 / 500").
var bar_value_room := BAR_VALUE_ROOM
## A tick drawn after the label (a done challenge on the Profile; the font has no ✓).
var ticked := false:
	set(v):
		ticked = v
		queue_redraw()

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


## "<  70%  >"; a row with one value (a status, a lone choice) has no arrows.
func value_text() -> String:
	if index >= values.size():
		return ""
	return String(values[0]) if values.size() == 1 else "<  %s  >" % String(values[index])


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


## Where the meter is drawn: a fixed spot, so the bars line up whatever the value's
## width ("Off" or "100%").
func bar_rect() -> Rect2:
	var bx := minf(_value_rect().position.x, size.x - 8.0 - bar_value_room) - GAP - bar_width
	return Rect2(bx, size.y * 0.5 - 2, bar_width, 4)


func _draw() -> void:
	var font := get_theme_font("font")
	var fs := get_theme_font_size("font_size")
	var focus := has_focus()
	var col := get_theme_color("font_focus_color" if focus else "font_color")
	var v := _value_rect()
	var base := (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	if index < locked.size() and bool(locked[index]):
		col = UiTheme.C_DIM
	if tag != "":
		var sb := get_theme_stylebox("normal")
		var tfs := UiTheme.px(UiTheme.SIZE_HINT + 1)  # smaller than the label, on its baseline
		var tx := sb.get_margin(SIDE_LEFT) + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 4.0
		draw_string_outline(font, Vector2(tx, base), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, UiTheme.outline(tfs), Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(tx, base), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, UiTheme.C_ACCENT)
	if ticked:
		var sb2 := get_theme_stylebox("normal")
		var kx := sb2.get_margin(SIDE_LEFT) + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 5.0
		var ky := size.y * 0.5
		var tick := PackedVector2Array([Vector2(kx, ky), Vector2(kx + 2, ky + 2), Vector2(kx + 6, ky - 3)])
		draw_polyline(tick, Color(0, 0, 0, 0.8), 3.0)
		draw_polyline(tick, UiTheme.C_ACCENT, 1.0)
	draw_string_outline(font, Vector2(v.position.x, base), value_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UiTheme.outline(fs), Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(v.position.x, base), value_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if bar < 0.0:
		return
	var r := bar_rect()
	draw_rect(r, Hud.C_BAR_BG)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(bar, 0.0, 1.0), r.size.y)),
		UiTheme.C_ACCENT if focus else UiTheme.C_DIM)
	for k in range(1, 10):
		draw_rect(Rect2(r.position.x + r.size.x * k / 10.0, r.position.y, 1, r.size.y), Color(0, 0, 0, 0.35))
