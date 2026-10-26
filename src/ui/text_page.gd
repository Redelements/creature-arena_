class_name TextPage
extends UiScreen
## A page of long text that scrolls (a licence, the third-party notices): the text box
## fills what the screen leaves under the title, Up/Down scroll it a few lines, Left/Right
## a page; the mouse wheel and a drag (touch) scroll it too. Back (B / Esc, or the row)
## closes it.

const LINES_PER_PRESS := 3

var body := ""
var text_box: RichTextLabel
var _fitting := false


func _init(p_title := "", p_body := "") -> void:
	super()
	logo = true
	title = p_title
	body = p_body
	row_width = 360.0
	show_desc = false
	hints = ["scroll", "back"]


func build() -> void:
	text_box = RichTextLabel.new()
	text_box.bbcode_enabled = false
	text_box.scroll_active = true
	text_box.selection_enabled = false
	text_box.text = body
	text_box.add_theme_font_override("normal_font", UiTheme.font())
	text_box.add_theme_font_size_override("normal_font_size", UiTheme.px(UiTheme.SIZE_HINT + 1))
	text_box.add_theme_color_override("default_color", UiTheme.C_TEXT)
	var pad := StyleBoxFlat.new()  # a little room round the text, no focus frame
	pad.bg_color = Color(0, 0, 0, 0.18)
	pad.set_content_margin_all(4)
	text_box.add_theme_stylebox_override("normal", pad)
	text_box.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# The scroll bar as the column's (UiScreen._scroller): a thin rule with an accent grab.
	var bar := text_box.get_v_scroll_bar()
	var track := StyleBoxFlat.new()
	track.bg_color = UiTheme.C_RULE
	track.content_margin_left = 1
	track.content_margin_right = 1
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(UiTheme.C_ACCENT, 0.7)
	grab.content_margin_left = 1
	grab.content_margin_right = 1
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(k, grab)
	bar.custom_minimum_size = Vector2(2, 0)
	text_box.gui_input.connect(_on_text_input)
	add_row(text_box)
	text_box.custom_minimum_size = Vector2(row_width, row_height * 6)
	add_space(3)
	var b := add_button("Back", back)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size.x = 140.0
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	default_focus = text_box


## The text box takes the height the rest of the page leaves (a little to spare).
func _fit_rows() -> void:
	if _fitting or text_box == null or _col == null or not is_inside_tree():
		super()
		return
	_fitting = true
	var room := size.y - _col.offset_top + _col.offset_bottom
	text_box.custom_minimum_size.y = row_height * 3
	super()
	var spare := room - _col.get_combined_minimum_size().y - 4.0
	text_box.custom_minimum_size.y = maxf(row_height * 3, row_height * 3 + spare)
	super()
	_fitting = false


## Keys, the menu stick and touch scroll the text; it never hands Up/Down to the focus.
func _on_text_input(event: InputEvent) -> void:
	var bar := text_box.get_v_scroll_bar()
	var line := float(text_box.get_theme_font("normal_font").get_height(text_box.get_theme_font_size("normal_font_size")))
	var step := 0.0
	if event.is_action_pressed("ui_down", true):
		step = line * LINES_PER_PRESS
	elif event.is_action_pressed("ui_up", true):
		step = -line * LINES_PER_PRESS
	elif event.is_action_pressed("ui_right", true) or event.is_action_pressed("ui_page_down", true):
		step = text_box.size.y * 0.9
	elif event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_page_up", true):
		step = -text_box.size.y * 0.9
	elif event is InputEventScreenDrag:
		step = -(event as InputEventScreenDrag).relative.y
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION \
			and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		step = -(event as InputEventMouseMotion).relative.y
	else:
		return
	bar.value = clampf(bar.value + step, 0.0, maxf(0.0, bar.max_value - bar.page))
	text_box.accept_event()
	if stack != null and not (event is InputEventMouseMotion or event is InputEventScreenDrag):
		stack.moved.emit()
