class_name OptionRow
extends Button
## A menu row with a value: "Label:  < value >". Left/Right step it (held keys repeat),
## Enter steps forward, a click on the left third steps back and anywhere else forward.
## `bar` >= 0 draws a meter at the right (volumes).

signal changed(index: int)

var label := ""
var values: Array = []
var index := 0
var wrap := true
var bar := -1.0


func _init(p_label := "", p_values: Array = [], p_index := 0) -> void:
	label = p_label
	values = p_values
	index = clampi(p_index, 0, maxi(0, p_values.size() - 1))
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	button_mask = 0  # clicks are handled below, by which half was clicked
	pressed.connect(func(): step(1))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	refresh()


func set_values(p_values: Array, p_index: int) -> void:
	values = p_values
	index = clampi(p_index, 0, maxi(0, values.size() - 1))
	refresh()


func refresh() -> void:
	var v := String(values[index]) if index < values.size() else ""
	text = "%s:  < %s >" % [label, v] if label != "" else "< %s >" % v
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


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		step(1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		step(-1 if event.position.x < size.x / 3.0 else 1)
		accept_event()


func _draw() -> void:
	if bar < 0.0:
		return
	var r := Rect2(size.x - 52, size.y * 0.5 - 2, 44, 4)
	draw_rect(r, Hud.C_BAR_BG)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(bar, 0.0, 1.0), r.size.y)),
		UiTheme.C_ACCENT if has_focus() else UiTheme.C_DIM)
	for k in range(1, 10):
		draw_rect(Rect2(r.position.x + r.size.x * k / 10.0, r.position.y, 1, r.size.y), Color(0, 0, 0, 0.35))
