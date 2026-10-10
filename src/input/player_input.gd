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

enum Device { KEYBOARD, GAMEPAD }

const LAYOUTS := ["league", "classic"]
const LAYOUT_NAMES := {"league": "League-style (mouse + QWER)", "classic": "Classic (WASD + JKUIO)"}
const AIM_DEADZONE := 0.5

const LABELS := {
	"league": {"light": "A", "heavy": "E", "skill_1": "Q", "skill_2": "W", "surge": "R", "dodge": "D", "guard": "F"},
	"classic": {"light": "J", "heavy": "K", "skill_1": "U", "skill_2": "I", "surge": "O", "dodge": "Spc", "guard": "Shift"},
	"gamepad": {"light": "A", "heavy": "X", "skill_1": "Y", "skill_2": "B", "surge": "RT", "dodge": "RB", "guard": "LB"},
}
const HELP := {
	"league": "Right-click move / attack   A or Left-click light   E heavy (hold)   Q skill 1   W skill 2   R surge   D dodge   F guard   D+F breakaway   S stop   Esc menu",
	"classic": "WASD move  J light  K heavy  U skill 1  I skill 2  O surge  Space dodge  Shift guard  Shift+Space breakaway  F1 hitboxes  Esc menu",
	"gamepad": "L-stick move   R-stick aim   A light   X heavy (hold)   Y skill 1   B skill 2   RT surge   RB dodge   LB guard   LB+RB breakaway   View menu",
}

var layout := "league"
var device: Device = Device.KEYBOARD
var pad_id := 0
var orders := MouseOrders.new()
var _pad_aim_t := 0


func label_set() -> String:
	return "gamepad" if device == Device.GAMEPAD else layout


func label(action: String) -> String:
	return String(LABELS[label_set()].get(action, ""))


func help_text() -> String:
	return String(HELP[label_set()])


## Tracks the last device used, so prompts can switch between keyboard and controller.
func note_event(event: InputEvent) -> void:
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
	var out := _gamepad_bits(me)
	if layout == "league":
		out |= orders.bits(me, foe, cursor, _held("lol_"), _pressed("lol_"))
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
	return out & 0xFFFF


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
