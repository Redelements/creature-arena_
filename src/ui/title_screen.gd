class_name TitleScreen
extends UiScreen
## The title menu: Single player, Online, Settings, Exit. Back points at Exit (the game
## only closes on Exit itself).

signal single_pressed
signal online_pressed
signal settings_pressed
signal exit_pressed

## The row to land on: "single", "online", "settings" or "exit".
var focus_row := ""
var _rows_by_name := {}


func _init(p_focus := "") -> void:
	super()
	focus_row = p_focus
	logo = true
	framed = false
	row_variation = "BigButton"
	row_align = HORIZONTAL_ALIGNMENT_CENTER
	row_width = 180.0
	row_height = 19.0
	row_gap = 3
	hints = ["move", "select"]


func build() -> void:
	_rows_by_name["single"] = add_button("Single player", single_pressed.emit,
		"Fight the CPU, train, take on Combo Trials, or play 2 players on one screen")
	_rows_by_name["online"] = add_button("Online", online_pressed.emit,
		"Play someone on another computer or a server, 1 v 1")
	_rows_by_name["settings"] = add_button("Settings", settings_pressed.emit,
		"CPU level, keyboard layout, volume, fullscreen, frame rate")
	_rows_by_name["exit"] = add_button("Exit", exit_pressed.emit, "Close the game")
	default_focus = _rows_by_name.get(focus_row)


func back() -> void:
	(_rows_by_name["exit"] as Control).grab_focus()
