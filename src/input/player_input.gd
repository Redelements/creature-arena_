class_name PlayerInput
extends RefCounted
## Reads the local player's devices and produces one simulation input bitmask per tick.
##
## Two keyboard layouts (pick one in the menu) plus an Xbox-style gamepad, all active at once:
##   League-style:  mouse to move and aim, Q W E R abilities, D dodge, F guard
##   Classic:       WASD to move, J K U I O attacks, Space dodge, Shift guard
##   Gamepad:       left stick moves and aims 360 degrees, right stick aims, face buttons
##                  attack. Two controller layouts: Standard (the right stick aims an attack
##                  as you throw it) and Twin-stick (the right stick aims and holds your
##                  facing, so you can strafe)
##
## Moving: the left stick walks any way it points (the input's 64-step move angle), and
## a mouse click walks straight to the spot. WASD gives 8 directions.
## Aiming: a mouse aims exactly at the cursor and a right stick exactly where it points
## (the 64-step aim angle); with neither, attacks go the way the left stick points. Aim
## assist: an attack aimed within ASSIST_DEG of an opponent in range goes straight at them
## (ASSIST_DEG_STICK from a 360-degree left stick, which needs less help than WASD). Assist
## lives here, in the input, so online peers simply receive the assisted aim.
##
##   Touch:         a floating stick on the left, a button arc on the right (TouchPad);
##                  taps get the wider ASSIST_DEG, drags off the big moves aim exactly
##
## The prompts on screen follow whichever device was used last (a touch shows the touch
## controls; a key or a pad button hides them again).
##
## For local 2-player, each player gets their own PlayerInput: `pad_device` picks which
## controller it reads (or none), and `keyboard` turns keyboard and mouse off for player 2.

enum Device { KEYBOARD, GAMEPAD, TOUCH }

const LAYOUTS := ["league", "classic"]
const LAYOUT_NAMES := {"league": "League-style (mouse + QWER)", "classic": "Classic (WASD + JKUIO)"}
const PAD_LAYOUTS := ["standard", "twinstick"]
const PAD_LAYOUT_NAMES := {"standard": "Standard", "twinstick": "Twin-stick (360 aim, strafe)"}
const AIM_DEADZONE := 0.5
const TWIN_DEADZONE := 0.35  ## twin-stick: past this the right stick aims and holds facing
const ATTACK_BITS := SimDefs.IN_LIGHT | SimDefs.IN_HEAVY | SimDefs.IN_SKILL1 | SimDefs.IN_SKILL2 \
	| SimDefs.IN_SURGE
const ASSIST_DEG := 25.0
const ASSIST_DEG_STICK := 12.0
const ASSIST_RANGE := 90.0
const PAD_T_SHIFT := 27  ## combine_pad packs its aim timer above the input bits
const AUTO_QUIET := 12  ## twin-stick auto-fire holds off this long after another button
const AUTO_PEND := 40  ## and re-presses an attack pressed mid-light for up to this long

const LABELS := {
	"league": {"light": "A", "heavy": "E", "skill_1": "Q", "skill_2": "W", "surge": "R", "dodge": "D", "guard": "F", "tag": "T"},
	"classic": {"light": "J", "heavy": "K", "skill_1": "U", "skill_2": "I", "surge": "O", "dodge": "Spc", "guard": "Shift", "tag": "L"},
	"gamepad": {"light": "A", "heavy": "X", "skill_1": "Y", "skill_2": "B", "surge": "RT", "dodge": "RB", "guard": "LB", "tag": "LT"},
	"touch": {},  ## the buttons on screen say what they are
}
const ANY_PAD := -1
const NO_PAD := -2
## The controls strip, filled in from the current bindings (they can be remapped).
const HELP := {
	"league": "Right-click move / attack   {light} or Left-click light   {heavy} heavy (hold)   {skill_1} skill 1   {skill_2} skill 2   {surge} surge   {dodge} dodge   {guard} guard   {dodge}+{guard} breakaway   {tag} tag   {stop} stop   Esc pause",
	"classic": "{up}{left}{down}{right} move  {light} light  {heavy} heavy  {skill_1} skill 1  {skill_2} skill 2  {surge} surge  {dodge} dodge  {guard} guard  {guard}+{dodge} breakaway  {tag} tag  F1 hitboxes  Esc pause",
	"gamepad": "L-stick move   R-stick aim   {light} light   {heavy} heavy (hold)   {skill_1} skill 1   {skill_2} skill 2   {surge} surge   {dodge} dodge   {guard} guard   {guard}+{dodge} breakaway   {tag} tag   Start pause",
	"touch": "Left thumb: move   Tap a button: attack (aimed for you)   Drag Heavy / Skills / Surge off the button: aim, let go to throw (in the red circle: cancel)   Hold Guard   Dodge goes the way you move",
	"twinstick": "L-stick move   R-stick aim 360 + face (strafe; Chef Cerebro and Mister Crease throw)   {light} light   {heavy} heavy   {skill_1} skill 1   {skill_2} skill 2   {surge} surge   {dodge} dodge   {guard} guard   {tag} tag   Start pause",
}
## Which action each label set's buttons are bound to (light = the attack action).
const PREFIX := {"league": "lol_", "classic": "kb_", "gamepad": "pad_"}

var layout := "league"
var pad_layout := "standard"
var device: Device = Device.KEYBOARD
var pad_id := 0
var orders := MouseOrders.new()
## Touch controls (only player 1's is fed: main passes it the screen's touches).
var touch := TouchPad.new()
## The touch target lock (aims taps at one foe, chases it), and which creatures the local
## team can't see (main's Vision answer, set each tick): never locked, never revealed.
var target := TouchTarget.new()
var touch_hidden: Array = []
var _pad_aim_t := 0
## Which controller this player reads: ANY_PAD (single player), NO_PAD, or a device id.
var pad_device := ANY_PAD
## Keyboard and mouse on? Off for player 2.
var keyboard := true
var _pad_prev := {}
## Twin-stick auto-fire (fighters with "twinstick": {"autofire": "light"}: Chef Cerebro,
## Mister Crease): its tick counter, how long it stays quiet after another button, and an
## attack pressed mid-light that it presses again until it starts.
var _auto := {"t": 0, "quiet": 0, "pend": 0, "pend_t": 0}


func label_set() -> String:
	if not keyboard:
		return "gamepad"
	if device == Device.TOUCH:
		return "touch"
	return "gamepad" if device == Device.GAMEPAD else layout


## The key or button bound to `action` ("light", "skill_1", "up"...) in the label set in
## use, as short text; it follows remapping.
func label(action: String) -> String:
	return label_for(label_set(), action)


static func label_for(set_name: String, action: String) -> String:
	if not PREFIX.has(set_name):
		return String(LABELS.get(set_name, {}).get(action, ""))
	var name := String(PREFIX[set_name]) + ("attack" if action == "light" and set_name == "league" else action)
	if InputMap.has_action(name):
		var group := "gamepad" if set_name == "gamepad" else set_name
		var t := Controls.binding_text(name, group)
		if t != "-":
			return t
	return String(LABELS[set_name].get(action, ""))


## `tag`: false leaves out the Tag button (team battles have no bench to tag).
func help_text(tag := true) -> String:
	var set_name := label_set()
	var t := String(HELP["twinstick" if set_name == "gamepad" and pad_layout == "twinstick" else set_name])
	if not tag:
		t = t.replace("{tag} tag   ", "").replace("{tag} tag  ", "")
	for a in ["light", "heavy", "skill_1", "skill_2", "surge", "dodge", "guard", "tag", "stop", "up", "down",
			"left", "right"]:
		t = t.replace("{%s}" % a, label_for(set_name, a))
	return t


## Tracks the last device used, so prompts can switch between keyboard and controller.
func note_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if keyboard and event is InputEventScreenTouch and event.pressed:
			device = Device.TOUCH
		return
	if (event is InputEventMouseButton or event is InputEventMouseMotion) \
			and event.device == InputEvent.DEVICE_ID_EMULATION:
		return  # a touch's copy as a mouse click (emulate_mouse_from_touch): still touch
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
	_auto = {"t": 0, "quiet": 0, "pend": 0, "pend_t": 0}
	touch.release_all()
	target.clear()


## The bitmask for this tick. `cursor` is the mouse position in arena coordinates.
func bits(sim: MatchSim, me_idx: int, cursor: Vector2) -> int:
	var me := sim.creatures[me_idx]
	var foe := sim.nearest_opponent(me)
	var aim_foe := assist_foe(sim, me)
	var out := 0
	if device == Device.TOUCH and keyboard:
		touch_charges(me, touch)
		var tb := touch.bits()
		if touch.lock_request >= 0:
			target.lock_on(sim, me_idx, touch.lock_request, touch_hidden)
			touch.lock_request = -1
		out |= target.apply(tb, sim, me_idx, touch_hidden, touch.stick_dir())
		if pad_device == ANY_PAD:
			out |= _gamepad_bits(me)
		# No keyboard or mouse: a tap also arrives as a mouse click (League's light attack).
		return assist(out, me, aim_foe, ASSIST_DEG)
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
	return assist(out, me, aim_foe)


## Tells the touch pad which of its drag buttons start a charging move for `me` (held
## still on the button, those start and charge).
static func touch_charges(me: CreatureSim, pad: TouchPad) -> void:
	var mv := me.moves()
	for b in ["heavy", "skill_1", "skill_2"]:
		pad.charges[b] = (mv.get(b, {}) as Dictionary).has("charge_max")


## The foe aim assist bends toward: the nearest one standing that isn't stealthed (Pete's
## Tiptoe must not pull the aim mark onto a fighter the screen hides). A
## `covered` foe in brush still counts. Input-layer only; the sim's `nearest_opponent`
## (guard facing, homing, blinks) is unchanged. null when none.
static func assist_foe(sim: MatchSim, me: CreatureSim) -> CreatureSim:
	var best: CreatureSim = null
	var best_d := INF
	for o in sim.creatures:
		if not me.is_foe(o) or o.state == CreatureSim.State.KO or o.stealth > 0:
			continue
		var d := o.pos.distance_squared_to(me.pos)
		if d < best_d:
			best_d = d
			best = o
	return best


## Aim assist: an attack aimed within ASSIST_DEG (ASSIST_DEG_STICK for a 360-degree left
## stick) of an opponent in range goes straight at them. Exact aims (mouse, right stick, a
## touch drag) pass through untouched. `deg` overrides the angle (touch: ASSIST_DEG even
## with the stick held, since a thumb on glass aims looser than a stick).
static func assist(bits: int, me: CreatureSim, foe: CreatureSim, deg := -1.0) -> int:
	if bits & SimDefs.IN_AIM or foe == null or foe.state == CreatureSim.State.KO:
		return bits
	if not (bits & ATTACK_BITS) and me.state != CreatureSim.State.ATTACK:
		return bits
	var to := foe.pos - me.pos
	if to.length() > ASSIST_RANGE + foe.radius or to.length_squared() < 1e-6:
		return bits
	var want := SimDefs.aim_from_bits(bits)
	if want == Vector2.ZERO:
		want = me.facing
	if deg < 0.0:
		deg = ASSIST_DEG_STICK if bits & SimDefs.IN_MOVE else ASSIST_DEG
	if want.normalized().dot(to.normalized()) < cos(deg_to_rad(deg)):
		return bits
	return bits | SimDefs.aim_bits(to)


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
	var out := combine_pad(move, aim, held, pressed, me.state == CreatureSim.State.ATTACK, _pad_aim_t,
		pad_layout == "twinstick")
	_pad_aim_t = out >> PAD_T_SHIFT
	out &= (1 << PAD_T_SHIFT) - 1
	if pad_layout == "twinstick":
		out = autofire(out, me, _auto)
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
	var out := combine_pad(move, aim, held, pressed, me.state == CreatureSim.State.ATTACK, _pad_aim_t,
		pad_layout == "twinstick")
	_pad_aim_t = out >> PAD_T_SHIFT
	out &= (1 << PAD_T_SHIFT) - 1
	if pad_layout == "twinstick":
		out = autofire(out, me, _auto)
	if tag:
		out |= SimDefs.IN_TAG
	return out


## Twin-stick auto-fire, for fighters whose data says "twinstick": {"autofire": "light"}
## (Chef Cerebro, Mister Crease): while the right stick aims (twin-stick sends IN_STRAFE
## then), Light is pressed every other tick, so the light string comes out at once and keeps
## coming, aimed where the stick points. Any other attack, a dodge or guard pauses it for
## AUTO_QUIET ticks so it can't overwrite that button in the input buffer. A light lasts
## longer than the buffer keeps a press, so another attack pressed mid-light is pressed
## again every other tick until its move starts (at most AUTO_PEND ticks): it always comes
## out after the light it was pressed in. `st` keeps the counters.
static func autofire(bits: int, me: CreatureSim, st: Dictionary) -> int:
	if me == null or String(me.def.get("twinstick", {}).get("autofire", "")) != "light":
		return bits
	if not (bits & SimDefs.IN_STRAFE):
		st["t"] = 0
		st["pend"] = 0
		return bits
	var attacks := SimDefs.IN_HEAVY | SimDefs.IN_SKILL1 | SimDefs.IN_SKILL2 | SimDefs.IN_SURGE
	if bits & attacks and me.state == CreatureSim.State.ATTACK and me.move_id.begins_with("light"):
		st["pend"] = bits & attacks
		st["pend_t"] = AUTO_PEND
	var pend := int(st.get("pend", 0))
	if pend != 0:
		st["pend_t"] = int(st["pend_t"]) - 1
		if int(st["pend_t"]) <= 0 or not (me.state == CreatureSim.State.ATTACK and me.move_id.begins_with("light")):
			st["pend"] = 0  # its move started (or the light was cut short): nothing to re-press
		else:
			st["quiet"] = AUTO_QUIET
			return (bits & ~attacks) | (pend if (AUTO_PEND - int(st["pend_t"])) % 2 == 1 else 0)
	if bits & (attacks | SimDefs.IN_DODGE | SimDefs.IN_GUARD):
		st["quiet"] = AUTO_QUIET
		return bits
	if int(st["quiet"]) > 0:
		st["quiet"] = int(st["quiet"]) - 1
		return bits
	st["t"] = int(st["t"]) + 1
	return bits | (SimDefs.IN_LIGHT if int(st["t"]) % 2 == 1 else 0)


## Pure gamepad logic, for tests. The left stick walks 360 degrees. Standard: attacks go
## exactly the way the right stick points when it's pushed; otherwise the way you're
## moving or facing. Twin-stick: a pushed right stick aims and holds your facing while you
## walk.
## Returns bits | (aim ticks left << PAD_T_SHIFT).
static func combine_pad(move: Vector2, aim: Vector2, held: Dictionary, pressed: Dictionary,
		attacking: bool, aim_t: int, twin := false) -> int:
	var out := 0
	var press_bits := {"light": SimDefs.IN_LIGHT, "heavy": SimDefs.IN_HEAVY, "skill_1": SimDefs.IN_SKILL1,
		"skill_2": SimDefs.IN_SKILL2, "surge": SimDefs.IN_SURGE, "dodge": SimDefs.IN_DODGE}
	var acted := false
	for a in press_bits:
		if pressed.get(a, false):
			out |= int(press_bits[a])
			acted = acted or a != "dodge"
	for a in MouseOrders.HOLD_BITS:  # held, a charging move keeps charging (Gulp, Pinecone Bomb)
		if held.get(a, false):
			out |= int(MouseOrders.HOLD_BITS[a])
	if held.get("guard", false):
		out |= SimDefs.IN_GUARD
	if twin and aim.length() >= TWIN_DEADZONE:
		out |= SimDefs.aim_bits(aim) | SimDefs.IN_STRAFE
		if move.length() > 0.0:
			out |= SimDefs.move_bits(move)
		return out
	var aiming := aim.length() >= AIM_DEADZONE
	if acted and aiming:
		aim_t = MouseOrders.AIM_HOLD
	elif aim_t > 0:
		aim_t -= 1
	if aiming and (acted or aim_t > 0 or attacking or held.get("heavy", false) or held.get("skill_1", false)
			or held.get("skill_2", false)):
		out |= SimDefs.bits_from_dir(aim.normalized()) | SimDefs.aim_bits(aim)
	elif move.length() > 0.0:
		out |= SimDefs.move_bits(move)
	return out | (aim_t << PAD_T_SHIFT)
