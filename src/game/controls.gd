class_name Controls
extends RefCounted
## Input actions are registered in code so every binding lives in one readable place.
##
## Three groups, all active together (PlayerInput decides which keyboard group to read):
##   lol_  League-style: mouse to move and aim, Q W E R, D dodge, F guard, S stop
##   kb_   Classic keyboard: WASD, J K U I O, Space, Shift
##   pad_  Xbox-style gamepad: sticks, face buttons, bumpers, right trigger

const MB_LEFT := MOUSE_BUTTON_LEFT
const MB_RIGHT := MOUSE_BUTTON_RIGHT

const BINDINGS := {
	# League-style keyboard and mouse
	"lol_move": {"mouse": [MB_RIGHT]},
	"lol_attack": {"keys": [KEY_A], "mouse": [MB_LEFT]},
	"lol_skill_1": {"keys": [KEY_Q]},
	"lol_skill_2": {"keys": [KEY_W]},
	"lol_heavy": {"keys": [KEY_E]},
	"lol_surge": {"keys": [KEY_R]},
	"lol_dodge": {"keys": [KEY_D, KEY_SPACE]},
	"lol_guard": {"keys": [KEY_F, KEY_SHIFT]},
	"lol_stop": {"keys": [KEY_S]},
	"lol_tag": {"keys": [KEY_T]},
	# Classic keyboard
	"kb_up": {"keys": [KEY_W, KEY_UP]},
	"kb_down": {"keys": [KEY_S, KEY_DOWN]},
	"kb_left": {"keys": [KEY_A, KEY_LEFT]},
	"kb_right": {"keys": [KEY_D, KEY_RIGHT]},
	"kb_light": {"keys": [KEY_J]},
	"kb_heavy": {"keys": [KEY_K]},
	"kb_skill_1": {"keys": [KEY_U]},
	"kb_skill_2": {"keys": [KEY_I]},
	"kb_surge": {"keys": [KEY_O]},
	"kb_dodge": {"keys": [KEY_SPACE]},
	"kb_guard": {"keys": [KEY_SHIFT]},
	"kb_tag": {"keys": [KEY_L]},
	# Xbox-style gamepad
	"pad_up": {"buttons": [JOY_BUTTON_DPAD_UP], "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	"pad_down": {"buttons": [JOY_BUTTON_DPAD_DOWN], "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	"pad_left": {"buttons": [JOY_BUTTON_DPAD_LEFT], "axis": [JOY_AXIS_LEFT_X, -1.0]},
	"pad_right": {"buttons": [JOY_BUTTON_DPAD_RIGHT], "axis": [JOY_AXIS_LEFT_X, 1.0]},
	"pad_aim_up": {"axis": [JOY_AXIS_RIGHT_Y, -1.0]},
	"pad_aim_down": {"axis": [JOY_AXIS_RIGHT_Y, 1.0]},
	"pad_aim_left": {"axis": [JOY_AXIS_RIGHT_X, -1.0]},
	"pad_aim_right": {"axis": [JOY_AXIS_RIGHT_X, 1.0]},
	"pad_light": {"buttons": [JOY_BUTTON_A]},
	"pad_heavy": {"buttons": [JOY_BUTTON_X]},
	"pad_skill_1": {"buttons": [JOY_BUTTON_Y]},
	"pad_skill_2": {"buttons": [JOY_BUTTON_B]},
	"pad_surge": {"axis": [JOY_AXIS_TRIGGER_RIGHT, 1.0]},
	"pad_dodge": {"buttons": [JOY_BUTTON_RIGHT_SHOULDER]},
	"pad_guard": {"buttons": [JOY_BUTTON_LEFT_SHOULDER]},
	"pad_tag": {"axis": [JOY_AXIS_TRIGGER_LEFT, 1.0]},
	# Menus and tools
	"menu_confirm": {"keys": [KEY_ENTER, KEY_KP_ENTER], "buttons": [JOY_BUTTON_A, JOY_BUTTON_START]},
	"menu_back": {"keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_BACK]},
	# In a fight: the pause menu (B can't be Back there: it's Skill 2).
	"pause": {"keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_START, JOY_BUTTON_BACK]},
	"debug_hitboxes": {"keys": [KEY_F1]},
	"debug_dummy_mode": {"keys": [KEY_F2]},
	"debug_help": {"keys": [KEY_F3]},
	"reset": {"keys": [KEY_F4]},
	"save_replay": {"keys": [KEY_F6]},
	"mute_music": {"keys": [KEY_M]},
}

const CLASSIC_BITS := {
	"kb_up": SimDefs.IN_UP,
	"kb_down": SimDefs.IN_DOWN,
	"kb_left": SimDefs.IN_LEFT,
	"kb_right": SimDefs.IN_RIGHT,
	"kb_light": SimDefs.IN_LIGHT,
	"kb_heavy": SimDefs.IN_HEAVY,
	"kb_skill_1": SimDefs.IN_SKILL1,
	"kb_skill_2": SimDefs.IN_SKILL2,
	"kb_surge": SimDefs.IN_SURGE,
	"kb_dodge": SimDefs.IN_DODGE,
	"kb_guard": SimDefs.IN_GUARD,
	"kb_tag": SimDefs.IN_TAG,
}


## Godot's menu actions whose stick binding MenuStick replaces.
const UI_DIRECTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]


static func setup() -> void:
	# The built-in menu actions count every wobble of the stick past the deadzone as a
	# new press; MenuStick reads the stick for menus instead (d-pad and keys stay).
	for action in UI_DIRECTIONS:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadMotion:
				InputMap.action_erase_event(action, ev)
	# Menus: A selects and B goes back, as on every console.
	_ensure_button("ui_accept", JOY_BUTTON_A)
	_ensure_button("ui_cancel", JOY_BUTTON_B)
	for action in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.35)
		var b: Dictionary = BINDINGS[action]
		for k in b.get("keys", []):
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		for m in b.get("mouse", []):
			var mb := InputEventMouseButton.new()
			mb.button_index = m
			InputMap.action_add_event(action, mb)
		for btn in b.get("buttons", []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = btn
			InputMap.action_add_event(action, jb)
		if b.has("axis"):
			var jm := InputEventJoypadMotion.new()
			jm.axis = b["axis"][0]
			jm.axis_value = b["axis"][1]
			InputMap.action_add_event(action, jm)


static func _ensure_button(action: String, button: JoyButton) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return
	var jb := InputEventJoypadButton.new()
	jb.button_index = button
	InputMap.action_add_event(action, jb)
