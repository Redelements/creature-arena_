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
	"debug_perf": {"keys": [KEY_F9]},  # the performance overlay: off, FPS, FPS + graph
	# Range rings on/off in a fight: one action per remap group, so each can be rebound
	# (the controller has none until the player picks a button).
	"kb_range_rings": {"keys": [KEY_F7]},
	"lol_range_rings": {"keys": [KEY_F7]},
	"pad_range_rings": {},
	# Training: open the fighter grid and swap your fighter in place (the same way).
	"kb_change_fighter": {"keys": [KEY_F8]},
	"lol_change_fighter": {"keys": [KEY_F8]},
	"pad_change_fighter": {},
	# Online: push to talk (Settings > Audio > Voice chat), held. One per remap group.
	"kb_talk": {"keys": [KEY_V]},
	"lol_talk": {"keys": [KEY_V]},
	"pad_talk": {"buttons": [JOY_BUTTON_LEFT_STICK]},
	"debug_dummy_mode": {"keys": [KEY_F2]},
	"debug_help": {"keys": [KEY_F3]},
	"reset": {"keys": [KEY_F4]},
	"palette": {"keys": [KEY_F5]},
	"save_replay": {"keys": [KEY_F6]},
	"mute_music": {"keys": [KEY_M]},
	# Watching a replay (ReplayViewer.KEYS): nobody's fight keys are read then, so these
	# only act in the Replay theater, and none is a reserved key.
	"replay_pause": {"keys": [KEY_SPACE, KEY_P], "buttons": [JOY_BUTTON_A]},
	"replay_step": {"keys": [KEY_PERIOD], "buttons": [JOY_BUTTON_X]},
	"replay_step_back": {"keys": [KEY_COMMA], "buttons": [JOY_BUTTON_B]},
	"replay_slower": {"keys": [KEY_MINUS, KEY_KP_SUBTRACT], "buttons": [JOY_BUTTON_LEFT_SHOULDER]},
	"replay_faster": {"keys": [KEY_EQUAL, KEY_KP_ADD], "buttons": [JOY_BUTTON_RIGHT_SHOULDER]},
	"replay_back": {"keys": [KEY_LEFT], "buttons": [JOY_BUTTON_DPAD_LEFT]},
	"replay_forward": {"keys": [KEY_RIGHT], "buttons": [JOY_BUTTON_DPAD_RIGHT]},
	"replay_start": {"keys": [KEY_HOME], "buttons": [JOY_BUTTON_Y]},
	"replay_clip": {"keys": [KEY_C], "buttons": [JOY_BUTTON_RIGHT_STICK]},
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


## Bindings made in code listen to device 0 only unless told otherwise; -1 is every
## device (a controller that isn't the first, Steam's virtual pads, player 2's pad).
const ALL_DEVICES := -1


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
			ev.device = ALL_DEVICES
			InputMap.action_add_event(action, ev)
		for m in b.get("mouse", []):
			var mb := InputEventMouseButton.new()
			mb.button_index = m
			mb.device = ALL_DEVICES
			InputMap.action_add_event(action, mb)
		for btn in b.get("buttons", []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = btn
			jb.device = ALL_DEVICES
			InputMap.action_add_event(action, jb)
		if b.has("axis"):
			var jm := InputEventJoypadMotion.new()
			jm.axis = b["axis"][0]
			jm.axis_value = b["axis"][1]
			jm.device = ALL_DEVICES
			InputMap.action_add_event(action, jm)


static func _ensure_button(action: String, button: JoyButton) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return
	var jb := InputEventJoypadButton.new()
	jb.button_index = button
	jb.device = ALL_DEVICES
	InputMap.action_add_event(action, jb)


# ------------------------------------------------------------------ remapping

## What can be remapped, per binding group, in menu order: [action, name].
const REMAP := {
	"classic": [["kb_up", "Move up"], ["kb_down", "Move down"], ["kb_left", "Move left"], ["kb_right", "Move right"],
		["kb_light", "Light attack"], ["kb_heavy", "Heavy attack"], ["kb_skill_1", "Skill 1"], ["kb_skill_2", "Skill 2"],
		["kb_surge", "Surge"], ["kb_dodge", "Dodge"], ["kb_guard", "Guard"], ["kb_tag", "Tag"],
		["kb_range_rings", "Range rings"], ["kb_change_fighter", "Change fighter"], ["kb_talk", "Talk (push to talk)"]],
	"league": [["lol_attack", "Light attack"], ["lol_heavy", "Heavy attack"], ["lol_skill_1", "Skill 1"],
		["lol_skill_2", "Skill 2"], ["lol_surge", "Surge"], ["lol_dodge", "Dodge"], ["lol_guard", "Guard"],
		["lol_stop", "Stop"], ["lol_tag", "Tag"], ["lol_range_rings", "Range rings"],
		["lol_change_fighter", "Change fighter"], ["lol_talk", "Talk (push to talk)"]],
	"gamepad": [["pad_light", "Light attack"], ["pad_heavy", "Heavy attack"], ["pad_skill_1", "Skill 1"],
		["pad_skill_2", "Skill 2"], ["pad_surge", "Surge"], ["pad_dodge", "Dodge"], ["pad_guard", "Guard"],
		["pad_tag", "Tag"], ["pad_range_rings", "Range rings"],
		["pad_change_fighter", "Change fighter"], ["pad_talk", "Talk (push to talk)"]],
}
const PAD_NAMES := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS", JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Start",
	JOY_BUTTON_DPAD_UP: "Up", JOY_BUTTON_DPAD_DOWN: "Down", JOY_BUTTON_DPAD_LEFT: "Left",
	JOY_BUTTON_DPAD_RIGHT: "Right", JOY_BUTTON_MISC1: "Share", JOY_BUTTON_PADDLE1: "P1",
	JOY_BUTTON_PADDLE2: "P2", JOY_BUTTON_PADDLE3: "P3", JOY_BUTTON_PADDLE4: "P4"}
const SHORT_KEYS := {"Space": "Spc", "Escape": "Esc", "BackSpace": "Bksp", "Enter": "Enter", "Shift": "Shift",
	"Ctrl": "Ctrl", "Alt": "Alt", "Tab": "Tab"}


## Whether `event` is the kind a group binds (keys for the keyboards, buttons and
## triggers for the controller).
static func is_kind(group: String, event: InputEvent) -> bool:
	if group == "gamepad":
		return event is InputEventJoypadButton or event is InputEventJoypadMotion
	return event is InputEventKey


## The binding of `action` that a group remaps, as short text ("J", "Spc", "RT").
static func binding_text(action: String, group: String) -> String:
	for ev in InputMap.action_get_events(action):
		if is_kind(group, ev):
			return event_text(ev)
	return "-"


static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := (ev as InputEventKey).physical_keycode
		if k == KEY_NONE:
			k = (ev as InputEventKey).keycode
		var s := OS.get_keycode_string(k)
		return String(SHORT_KEYS.get(s, s))
	if ev is InputEventJoypadButton:
		return String(PAD_NAMES.get((ev as InputEventJoypadButton).button_index, "B%d" % (ev as InputEventJoypadButton).button_index))
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		match m.axis:
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
		return "Axis %d%s" % [m.axis, "+" if m.axis_value > 0 else "-"]
	return "?"


## Binds `event` to `action` in place of its main binding of that kind (extra ones, like
## the arrow keys beside WASD, stay). If another action of the group already had it, it
## gets the old main binding instead: a swap, so nothing is left doubled up.
static func rebind(group: String, action: String, event: InputEvent) -> void:
	var fresh := _clean(event)
	var mine := _kind_events(action, group)
	var old: InputEvent = mine[0] if not mine.is_empty() else null
	for pair in REMAP[group]:
		var other := String(pair[0])
		if other == action:
			continue
		var theirs := _kind_events(other, group)
		for k in theirs.size():
			if _same(theirs[k], fresh):
				if old != null and not theirs.any(func(e): return _same(e, old)):
					theirs[k] = old
				else:
					theirs.remove_at(k)
				_set_kind_events(other, group, theirs)
				break
	var rest := mine.slice(1).filter(func(e): return not _same(e, fresh))
	_set_kind_events(action, group, [fresh] + rest)


## An action's bindings of the kind a group remaps, main one first.
static func _kind_events(action: String, group: String) -> Array:
	var out: Array = []
	for ev in InputMap.action_get_events(action):
		if is_kind(group, ev):
			out.append(ev)
	return out


static func _set_kind_events(action: String, group: String, events: Array) -> void:
	var keep: Array = []
	for ev in InputMap.action_get_events(action):
		if not is_kind(group, ev):
			keep.append(ev)
	InputMap.action_erase_events(action)
	for ev in events + keep:
		InputMap.action_add_event(action, ev)


## A copy of a pressed key / button / trigger, as a binding for every device.
static func _clean(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var k := InputEventKey.new()
		k.physical_keycode = (event as InputEventKey).physical_keycode
		if k.physical_keycode == KEY_NONE:
			k.keycode = (event as InputEventKey).keycode
		k.device = ALL_DEVICES
		return k
	if event is InputEventJoypadButton:
		var b := InputEventJoypadButton.new()
		b.button_index = (event as InputEventJoypadButton).button_index
		b.device = ALL_DEVICES
		return b
	var m := InputEventJoypadMotion.new()
	m.axis = (event as InputEventJoypadMotion).axis
	m.axis_value = signf((event as InputEventJoypadMotion).axis_value)
	m.device = ALL_DEVICES
	return m


static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode \
			and (a as InputEventKey).keycode == (b as InputEventKey).keycode
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return (a as InputEventJoypadMotion).axis == (b as InputEventJoypadMotion).axis \
			and signf((a as InputEventJoypadMotion).axis_value) == signf((b as InputEventJoypadMotion).axis_value)
	return false


## Every remappable action back to BINDINGS (one group, or all with "").
static func reset(group := "") -> void:
	for g in REMAP:
		if group != "" and g != group:
			continue
		for pair in REMAP[g]:
			var action := String(pair[0])
			InputMap.action_erase_events(action)
			InputMap.erase_action(action)
	setup()


## The remapped bindings, to save: action -> [{"key": n} | {"button": n} | {"axis": n, "value": v}].
## Only actions that differ from BINDINGS are listed.
static func overrides() -> Dictionary:
	var out := {}
	for g in REMAP:
		for pair in REMAP[g]:
			var action := String(pair[0])
			var now: Array = []
			for ev in InputMap.action_get_events(action):
				if is_kind(g, ev):
					now.append(_save_event(ev))
			if now != _default_saved(action, g):
				out[action] = now
	return out


static func apply_overrides(saved: Dictionary) -> void:
	for action in saved:
		var group := ""
		for g in REMAP:
			for pair in REMAP[g]:
				if String(pair[0]) == String(action):
					group = g
		if group == "" or not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if is_kind(group, ev):
				InputMap.action_erase_event(action, ev)
		for d in saved[action]:
			var ev := _load_event(d)
			if ev != null:
				InputMap.action_add_event(action, ev)


static func _save_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return {"key": int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)}
	if ev is InputEventJoypadButton:
		return {"button": int((ev as InputEventJoypadButton).button_index)}
	var m := ev as InputEventJoypadMotion
	return {"axis": int(m.axis), "value": signf(m.axis_value)}


static func _load_event(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = int(d["key"])
		k.device = ALL_DEVICES
		return k
	if d.has("button"):
		var b := InputEventJoypadButton.new()
		b.button_index = int(d["button"])
		b.device = ALL_DEVICES
		return b
	if d.has("axis"):
		var m := InputEventJoypadMotion.new()
		m.axis = int(d["axis"])
		m.axis_value = float(d.get("value", 1.0))
		m.device = ALL_DEVICES
		return m
	return null


static func _default_saved(action: String, group: String) -> Array:
	var b: Dictionary = BINDINGS.get(action, {})
	var out: Array = []
	if group == "gamepad":
		for btn in b.get("buttons", []):
			out.append({"button": int(btn)})
		if b.has("axis"):
			out.append({"axis": int(b["axis"][0]), "value": signf(float(b["axis"][1]))})
	else:
		for k in b.get("keys", []):
			out.append({"key": int(k)})
	return out
