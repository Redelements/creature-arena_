class_name TitleScreen
extends UiScreen
## The title menu: Single player, Online, Profile, Settings, Exit. Back points at Exit (the
## game only closes on Exit itself). The Profile row is there only while Settings > Game >
## Progression is on (hidden, re-checked whenever the title shows again), and says "New!"
## while a level-up gave something the Profile has not shown yet.

signal single_pressed
signal online_pressed
signal profile_pressed
signal settings_pressed
signal exit_pressed

## The row to land on: "single", "online", "profile", "settings" or "exit".
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
	row_gap = 2  # (five rows and the wordmark fit a 270-unit-high screen above the description)
	hints = ["move", "select"]


func build() -> void:
	_rows_by_name["single"] = add_button("Single player", single_pressed.emit,
		"Fight the CPU, train, take on Combo Trials, or play 2 players on one screen")
	_rows_by_name["online"] = add_button("Online", online_pressed.emit,
		"Play someone on another computer or a server, 1 v 1")
	_rows_by_name["profile"] = add_button("Profile", profile_pressed.emit,
		"Your level, each fighter's mastery, and the palettes, titles and victory lines you've unlocked")
	_rows_by_name["settings"] = add_button("Settings", settings_pressed.emit,
		"CPU level, keyboard layout, volume, fullscreen, frame rate")
	_rows_by_name["exit"] = add_button("Exit", exit_pressed.emit, "Close the game")
	default_focus = _rows_by_name.get(focus_row)
	_show_profile()
	visibility_changed.connect(func(): if visible: _show_profile())


## The Profile row: there only with Progression on, "New!" while something new waits.
func _show_profile() -> void:
	var b: Button = _rows_by_name["profile"]
	var on := Progress.enabled()
	b.text = "Profile   New!" if Progress.new_anywhere() else "Profile"
	if b.visible == on:
		return
	if not on and b.has_focus():
		(_rows_by_name["settings"] as Control).grab_focus()
	b.visible = on
	link_focus()


func back() -> void:
	(_rows_by_name["exit"] as Control).grab_focus()
