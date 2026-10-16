class_name RoomCodeButton
extends Button
## A room's code as a row you can press: "Room code  KX7P" with a copy icon on the right
## (two offset rounded squares, drawn here so they stay crisp at the pixel-art scale).
## Pressing it (mouse, Enter, or the pad's A on it) puts the code on the clipboard; for
## `COPIED_SECS` the row says "Copied" and the icon turns into a tick.

const COPIED_SECS := 1.5
const ICON_W := 9.0  ## the icon's box, right-aligned

## The last text copied by any of these (tests read it: a headless run has no clipboard).
static var last_copied := ""

var code := "":
	set(v):
		code = v
		_refresh()
var _copied_left := 0.0


func _init(p_code := "") -> void:
	code = p_code
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	tooltip_text = "Copy the room code"
	pressed.connect(copy)
	for s in [focus_entered, focus_exited, mouse_entered, mouse_exited]:
		(s as Signal).connect(queue_redraw)
	set_process(false)


## Puts the code on the clipboard and says so for a moment.
func copy() -> void:
	if code == "":
		return
	copy_text(code)
	_copied_left = COPIED_SECS
	set_process(true)
	_refresh()


## The clipboard, where the platform has one (a headless run doesn't).
static func copy_text(t: String) -> void:
	last_copied = t
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(t)


func copied() -> bool:
	return _copied_left > 0.0


func _process(delta: float) -> void:
	_copied_left -= delta
	if _copied_left <= 0.0:
		_copied_left = 0.0
		set_process(false)
		_refresh()


func _refresh() -> void:
	text = ("Room code  %s     Copied!" if copied() else "Room code  %s") % code
	tooltip_text = "Copied" if copied() else "Copy the room code"
	queue_redraw()


func _draw() -> void:
	var lit := has_focus() or is_hovered()
	var col: Color = UiTheme.C_ACCENT if (lit or copied()) else UiTheme.C_DIM
	var x := floorf(size.x - ICON_W - 5.0)
	var y := floorf(size.y * 0.5 - 4.0)
	if copied():
		# A tick.
		var pts := PackedVector2Array([Vector2(x + 1, y + 4), Vector2(x + 3.5, y + 6.5), Vector2(x + 8, y + 1)])
		draw_polyline(pts, col, 1.5, true)
		return
	# Two sheets: the back one up and left, the front one over it (filled with the row's
	# colour so the back one's corner hides behind it).
	_sheet(Rect2(x, y, 6, 7), col, Color(0, 0, 0, 0))
	var bg: Color = UiTheme.C_ROW_FOCUS if lit else UiTheme.C_ROW
	_sheet(Rect2(x + 3, y + 2, 6, 7), col, bg)


func _sheet(r: Rect2, line: Color, fill: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.draw_center = fill.a > 0.0
	sb.border_color = line
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(1)
	sb.anti_aliasing = false
	draw_style_box(sb, r)
