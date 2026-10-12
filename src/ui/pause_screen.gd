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
		add_button("Restart", func(): _confirm("Restart the match?", restart_requested))
	add_button("Controls", func(): stack.push(HelpScreen.new(help_body)))
	add_button(quit_text, func(): _confirm("Quit to the main menu?", quit_requested))


func back() -> void:
	if stack != null:
		stack.pop()
	resumed.emit()


func _confirm(question: String, then: Signal) -> void:
	var c := ConfirmScreen.new(question, "The match so far is lost.")
	c.answered.connect(func(yes: bool): if yes: then.emit())
	stack.push(c)
