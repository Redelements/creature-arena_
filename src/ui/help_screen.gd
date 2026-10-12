class_name HelpScreen
extends UiScreen
## The controls for the device in use (PlayerInput's help text, one control a line), in
## two columns.

var body := ""


func _init(p_body := "") -> void:
	super()
	title = "CONTROLS"
	body = p_body
	row_width = 320.0
	hints = ["back"]


func build() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 1)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for line in body.split("\n", false):
		var l := _label(line.strip_edges(), UiTheme.SIZE_HINT + 1, UiTheme.C_TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(l)
	_list.add_child(grid)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_list.add_child(gap)
	var b := add_button("Back", back)
	b.custom_minimum_size.x = 140.0
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
