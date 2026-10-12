class_name ConfirmScreen
extends UiScreen
## "Are you sure?": Yes / No, with No focused, so a stray press can't do it. Back = No.

signal answered(yes: bool)

var yes_text := "Yes"
var no_text := "No"


func _init(p_title := "Are you sure?", p_subtitle := "", p_yes := "Yes", p_no := "No") -> void:
	super()
	title = p_title
	subtitle = p_subtitle
	yes_text = p_yes
	no_text = p_no
	row_width = 160.0


func build() -> void:
	add_button(yes_text, func(): _answer(true))
	default_focus = add_button(no_text, func(): _answer(false))


func back() -> void:
	_answer(false)


func _answer(yes: bool) -> void:
	if stack != null:
		stack.pop()
	answered.emit(yes)
