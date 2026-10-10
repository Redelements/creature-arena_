class_name Controls
extends RefCounted
## Input actions are registered in code so the bindings live in one readable place.
## Keyboard and gamepad both work out of the box.

const BINDINGS := {
	"move_up": {"keys": [KEY_W, KEY_UP], "buttons": [JOY_BUTTON_DPAD_UP], "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	"move_down": {"keys": [KEY_S, KEY_DOWN], "buttons": [JOY_BUTTON_DPAD_DOWN], "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	"move_left": {"keys": [KEY_A, KEY_LEFT], "buttons": [JOY_BUTTON_DPAD_LEFT], "axis": [JOY_AXIS_LEFT_X, -1.0]},
	"move_right": {"keys": [KEY_D, KEY_RIGHT], "buttons": [JOY_BUTTON_DPAD_RIGHT], "axis": [JOY_AXIS_LEFT_X, 1.0]},
	"light": {"keys": [KEY_J], "buttons": [JOY_BUTTON_A]},
	"heavy": {"keys": [KEY_K], "buttons": [JOY_BUTTON_X]},
	"dodge": {"keys": [KEY_SPACE], "buttons": [JOY_BUTTON_RIGHT_SHOULDER]},
	"guard": {"keys": [KEY_SHIFT], "buttons": [JOY_BUTTON_LEFT_SHOULDER]},
	"debug_hitboxes": {"keys": [KEY_F1]},
	"debug_dummy_mode": {"keys": [KEY_F2], "buttons": [JOY_BUTTON_BACK]},
	"debug_help": {"keys": [KEY_F3]},
	"save_replay": {"keys": [KEY_F6]},
	"reset": {"keys": [KEY_R], "buttons": [JOY_BUTTON_START]},
}

const BITS := {
	"move_up": SimDefs.IN_UP,
	"move_down": SimDefs.IN_DOWN,
	"move_left": SimDefs.IN_LEFT,
	"move_right": SimDefs.IN_RIGHT,
	"light": SimDefs.IN_LIGHT,
	"heavy": SimDefs.IN_HEAVY,
	"dodge": SimDefs.IN_DODGE,
	"guard": SimDefs.IN_GUARD,
}


static func setup() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.4)
		var b: Dictionary = BINDINGS[action]
		for k in b.get("keys", []):
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		for btn in b.get("buttons", []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = btn
			InputMap.action_add_event(action, jb)
		if b.has("axis"):
			var jm := InputEventJoypadMotion.new()
			jm.axis = b["axis"][0]
			jm.axis_value = b["axis"][1]
			InputMap.action_add_event(action, jm)


## The local player's buttons this tick, as a simulation input bitmask.
static func read_bits() -> int:
	var bits := 0
	for action in BITS:
		if Input.is_action_pressed(action):
			bits |= BITS[action]
	return bits
