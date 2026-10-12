class_name PlayerInput
extends RefCounted
## Reads the local player's devices and produces one simulation input bitmask per tick.
##
## Two keyboard layouts (pick one in the menu) plus an Xbox-style gamepad, all active at once:
##   League-style:  mouse to move and aim, Q W E R abilities, D dodge, F guard
##   Classic:       WASD to move, J K U I O attacks, Space dodge, Shift guard
##   Gamepad:       left stick moves, right stick aims, face buttons attack
##
## The prompts on screen follow whichever device was used last.
##
## For local 2-player, each player gets their own PlayerInput: `pad_device` picks which
## controller it reads (or none), and `keyboard` turns keyboard and mouse off for player 2.

enum Device { KEYBOARD, GAMEPAD }

const LAYOUTS := ["league", "classic"]
const LAYOUT_NAMES := {"league": "League-style (mouse + QWER)", "classic": "Classic (WASD + JKUIO)"}
const AIM_DEADZONE := 0.5

const LABELS := {
	"league": {"light": "A", "heavy": "E", "skill_1": "Q", "skill_2": "W", "surge": "R", "dodge": "D", "guard": "F", "tag": "T"},
	"classic": {"light": "J", "heavy": "K", "skill_1": "U", "skill_2": "I", "surge": "O", "dodge": "Spc", "guard": "Shift", "tag": "L"},
	"gamepad": {"light": "A", "heavy": "X", "skill_1": "Y", "skill_2": "B", "surge": "RT", "dodge": "RB", "guard": "LB", "tag": "LT"},
}
const ANY_PAD := -1
const NO_PAD := -2
## The controls strip, filled in from the current bindings (they can be remapped).
const HELP := {
	"league": "Right-click move / attack   {light} or Left-click light   {heavy} heavy (hold)   {skill_1} skill 1   {skill_2} skill 2   {surge} surge   {dodge} dodge   {guard} guard   {dodge}+{guard} breakaway   {tag} tag   {stop} stop   Esc pause",
	"classic": "{up}{left}{down}{right} move  {light} light  {heavy} heavy  {skill_1} skill 1  {skill_2} skill 2  {surge} surge  {dodge} dodge  {guard} guard  {guard}+{dodge} breakaway  {tag} tag  F1 hitboxes  Esc pause",
	"gamepad": "L-stick move   R-stick aim   {light} light   {heavy} heavy (hold)   {skill_1} skill 1   {skill_2} skill 2   {surge} surge   {dodge} dodge   {guard} guard   {guard}+{dodge} breakaway   {tag} tag   Start pause",
}
## Which action each label set's buttons are bound to (light = the attack action).
const PREFIX := {"league": "lol_", "classic": "kb_", "gamepad": "pad_"}

var layout := "league"
var device: Device = Device.KEYBOARD
var pad_id := 0
var orders := MouseOrders.new()
var _pad_aim_t := 0
## Which controller this player reads: ANY_PAD (single player), NO_PAD, or a device id.
var pad_device := ANY_PAD
## Keyboard and mouse on? Off for player 2.
var keyboard := true
var _pad_prev := {}


func label_set() -> String:
	if not keyboard:
		return "gamepad"
	return "gamepad" if device == Device.GAMEPAD else layout


## The key or button bound to `action` ("light", "skill_1", "up"...) in the label set in
## use, as short text; it follows remapping.
func label(action: String) -> String:
	return label_for(label_set(), action)


static func label_for(set_name: String, action: String) -> String:
	var name := String(PREFIX[set_name]) + ("attack" if action == "light" and set_name == "league" else action)
	if InputMap.has_action(name):
		var group := "gamepad" if set_name == "gamepad" else set_name
		var t := Controls.binding_text(name, group)
		if t != "-":
			return t
	return String(LABELS[set_name].get(action, ""))


func help_text() -> String:
	var set_name := label_set()
	var t := String(HELP[set_name])
	for a in ["light", "heavy", "skill_1", "skill_2", "surge", "dodge", "guard", "tag", "stop", "up", "down",
			"left", "right"]:
		t = t.replace("{%s}" % a, label_for(set_name, a))
	return t


## Tracks the last device used, so prompts can switch between keyboard and controller.
func note_event(event: InputEvent) -> void:
	if pad_device >= 0 and (event is InputEventJoypadButton or event is InputEventJoypadMotion) \
			and event.device != pad_device:
		return
	if event is InputEventJoypadButton and event.pressed:
		device = Device.GAMEPAD
		pad_id = event.device
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		device = Device.GAMEPAD
		pad_id = event.device
	elif event is InputEventKey and event.pressed:
		device = Device.KEYBOARD
	elif event is InputEventMouseButton and event.pressed:
		device = Device.KEYBOARD


func reset() -> void:
	orders.clear()
	_pad_aim_t = 0


## The bitmask for this tick. `cursor` is the mouse position in arena coordinates.
func bits(sim: MatchSim, me_idx: int, cursor: Vector2) -> int:
	var me := sim.creatures[me_idx]
	var foe := sim.nearest_opponent(me)
	var out := 0
	if pad_device == ANY_PAD:
		out |= _gamepad_bits(me)
	elif pad_device >= 0:
		out |= _device_pad_bits(me, pad_device)
	if keyboard:
		if layout == "league":
			out |= orders.bits(me, foe, cursor, _held("lol_"), _pressed("lol_"))
			if Input.is_action_pressed("lol_tag"):
				out |= SimDefs.IN_TAG
		else:
			out |= _classic_bits()
	return out


const MOUSE_ACTIONS := ["move", "attack", "heavy", "skill_1", "skill_2", "surge", "dodge", "guard", "stop"]


func _held(prefix: String) -> Dictionary:
	var d := {}
	for a in MOUSE_ACTIONS:
		d[a] = Input.is_action_pressed(prefix + a)
	return d


func _pressed(prefix: String) -> Dictionary:
	var d := {}
	for a in MOUSE_ACTIONS:
		d[a] = Input.is_action_just_pressed(prefix + a)
	return d


func _classic_bits() -> int:
	var b := 0
	for action in Controls.CLASSIC_BITS:
		if Input.is_action_pressed(action):
			b |= int(Controls.CLASSIC_BITS[action])
	return b


func _gamepad_bits(me: CreatureSim) -> int:
	var held := {}
	var pressed := {}
	for a in ["light", "heavy", "skill_1", "skill_2", "surge", "dodge", "guard"]:
		held[a] = Input.is_action_pressed("pad_" + a)
		pressed[a] = Input.is_action_just_pressed("pad_" + a)
	var move := Input.get_vector("pad_left", "pad_right", "pad_up", "pad_down", 0.35)
	var aim := Input.get_vector("pad_aim_left", "pad_aim_right", "pad_aim_up", "pad_aim_down", 0.2)
	var out := combine_pad(move, aim, held, pressed, me.state == CreatureSim.State.ATTACK, _pad_aim_t)
	_pad_aim_t = out >> 16
	out &= 0xFFFF
	if Input.is_action_pressed("pad_tag"):
		out |= SimDefs.IN_TAG
	return out


## One specific controller, read directly (the pad_* actions listen to every controller).
func _device_pad_bits(me: CreatureSim, dev: int) -> int:
	var buttons := {"light": JOY_BUTTON_A, "heavy": JOY_BUTTON_X, "skill_1": JOY_BUTTON_Y,
		"skill_2": JOY_BUTTON_B, "dodge": JOY_BUTTON_RIGHT_SHOULDER, "guard": JOY_BUTTON_LEFT_SHOULDER}
	var held := {}
	var pressed := {}
	for a in buttons:
		held[a] = Input.is_joy_button_pressed(dev, buttons[a])
	held["surge"] = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	var tag := Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT) > 0.5
	for a in held:
		pressed[a] = bool(held[a]) and not bool(_pad_prev.get(a, false))
	_pad_prev = held.duplicate()
	var stick := func(ax: JoyAxis, ay: JoyAxis, dead: float) -> Vector2:
		var v := Vector2(Input.get_joy_axis(dev, ax), Input.get_joy_axis(dev, ay))
		return v if v.length() >= dead else Vector2.ZERO
	var move: Vector2 = stick.call(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.35)
	var dpad := Vector2(
		float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT)),
		float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_UP)))
	if dpad != Vector2.ZERO:
		move = dpad
	var aim: Vector2 = stick.call(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 0.2)
	var out := combine_pad(move, aim, held, pressed, me.state == CreatureSim.State.ATTACK, _pad_aim_t)
	_pad_aim_t = out >> 16
	out &= 0xFFFF
	if tag:
		out |= SimDefs.IN_TAG
	return out


## Pure gamepad logic, for tests. Attacks go the way the right stick points when it's
## pushed (twin-stick aiming); otherwise they go the way you're moving or facing.
## Returns bits | (aim ticks left << 16).
static func combine_pad(move: Vector2, aim: Vector2, held: Dictionary, pressed: Dictionary,
		attacking: bool, aim_t: int) -> int:
	var out := 0
	var press_bits := {"light": SimDefs.IN_LIGHT, "heavy": SimDefs.IN_HEAVY, "skill_1": SimDefs.IN_SKILL1,
		"skill_2": SimDefs.IN_SKILL2, "surge": SimDefs.IN_SURGE, "dodge": SimDefs.IN_DODGE}
	var acted := false
	for a in press_bits:
		if pressed.get(a, false):
			out |= int(press_bits[a])
			acted = acted or a != "dodge"
	if held.get("heavy", false):
		out |= SimDefs.IN_HEAVY
	if held.get("guard", false):
		out |= SimDefs.IN_GUARD
	var aiming := aim.length() >= AIM_DEADZONE
	if acted and aiming:
		aim_t = MouseOrders.AIM_HOLD
	elif aim_t > 0:
		aim_t -= 1
	if aiming and (acted or aim_t > 0 or attacking or held.get("heavy", false)):
		out |= SimDefs.bits_from_dir(aim.normalized())
	elif move.length() > 0.0:
		out |= SimDefs.bits_from_dir(move.normalized())
	return out | (aim_t << 16)
