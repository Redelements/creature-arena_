class_name CardButton
extends Button
## A menu card: a row twice the usual height with its title on the first line and a
## dimmer second line saying what's behind it (the Single player and Settings hubs).
## The title is the Button's own text, kept in the top half by the "Card" variation's
## margins; the second line is drawn here. A small chevron on the right says it opens
## a page.

var subtitle := ""
var chevron := true


func _init(p_title := "", p_subtitle := "") -> void:
	text = p_title
	subtitle = p_subtitle
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	theme_type_variation = "Card"
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var font := get_theme_font("font")
	var focus := has_focus()
	var col: Color = UiTheme.C_ACCENT if focus else UiTheme.C_DIM
	if subtitle != "":
		var fs := UiTheme.SIZE_SUB
		var y := size.y - 3.5
		draw_string_outline(font, Vector2(10, y), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, fs, 2, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(10, y), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, fs, Color(col, 0.85 if focus else 1.0))
	if chevron:
		var cx := size.x - 9.0
		var cy := size.y * 0.5
		var pts := PackedVector2Array([Vector2(cx - 2.5, cy - 3.5), Vector2(cx + 1.0, cy), Vector2(cx - 2.5, cy + 3.5)])
		draw_polyline(pts, Color(col, 0.9), 1.5, true)
