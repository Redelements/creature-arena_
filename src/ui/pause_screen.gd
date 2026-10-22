class_name PauseScreen
extends UiScreen
## The pause menu (Start / Esc / View in a fight): the match is frozen behind it.
## Quitting asks first. Back (or Start again) resumes.

signal resumed
signal restart_requested
signal quit_requested

var can_restart := true
var help_body := ""
var quit_text := "Quit to main menu"
## What the Restart and Quit confirms ask and say (a mode with more at stake changes them).
var restart_question := "Restart the match?"
var restart_note := "The match so far is lost."
## Rows a mode adds after Restart, each [text, Callable, description] (training: Change
## fighter, Training options).
var extras: Array = []


func _init(p_can_restart := true, p_help := "") -> void:
	super()
	title = "PAUSED"
	can_restart = p_can_restart
	help_body = p_help
	row_width = 180.0
	hints = ["move", "select", "resume"]


func build() -> void:
	add_button("Resume", back)
	if can_restart:
		add_button("Restart", func(): _confirm(restart_question, restart_requested, restart_note))
	for e in extras:
		add_button(String(e[0]), e[1], String(e[2]) if (e as Array).size() > 2 else "")
	if help_body != "":
		add_button("Controls", func(): stack.push(HelpScreen.new(help_body)))
	add_button(quit_text, func(): _confirm("Quit to the main menu?", quit_requested))


func back() -> void:
	if stack != null:
		stack.pop()
	resumed.emit()


func _confirm(question: String, then: Signal, note := "The match so far is lost.") -> void:
	var c := ConfirmScreen.new(question, note)
	c.answered.connect(func(yes: bool): if yes: then.emit())
	stack.push(c)
