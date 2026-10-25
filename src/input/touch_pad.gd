class_name TouchPad
extends RefCounted
## Touch fight controls, turned into the same input bitmask a gamepad produces.
##
##   Left ~40% of the screen   a floating move stick: it appears where the thumb lands,
##                             walks the way it points (the 64-step move angle) and goes
##                             back to its rest spot when let go
##   Right: an arc of buttons  Light (the biggest), Heavy, Skill 1, Skill 2, Surge, Dodge,
##                             Guard (hold), Tag (Duel only); Pause small in the top corner
##
## Aiming ("tap + drag", the default):
##   - Tap a button: it fires the way you move or face; PlayerInput adds aim assist at the
##     wider ASSIST_DEG (25 degrees) for touch.
##   - Drag off Heavy, Skill 1, Skill 2 or Surge: it aims instead (the view draws the
##     move's reach) and fires on release with the exact aim (IN_AIM). While a drag aims, a
##     red cancel zone shows near the top of the right side (clear of the arc and Pause):
##     let go inside it to cancel; let go anywhere else and it fires (MOBA style).
##   - A move that charges (its data has charge_max) and is held still on its button for
##     HOLD_TICKS starts then and charges while held, like a held pad button; dragging off
##     it aims the charge exactly.
##   - Light and Dodge fire on the touch itself (release-to-fire would slow combos).
## "Tap only": every button fires on the touch and holds while the finger stays down.
##
## Pure logic, like MouseOrders: main feeds it InputEventScreenTouch / InputEventScreenDrag
## (any number of fingers, told apart by `index`) in canvas units, and bits() hands out one
## tick's bits. A press always lasts at least one tick, even when the finger was down and
## up between two ticks, and a press the last tick already carried waits a tick (the sim
## only starts a move on a fresh press).

const STICK_ZONE := 0.4  ## the stick starts anywhere in this share of the screen's width
const STICK_TOP := 46.0  ## ...below this (the fighter panels)
const STICK_R := 30.0  ## the knob's travel
const STICK_DEAD := 0.22  ## of STICK_R: closer to the middle is no walk
const KNOB_R := 13.0
const SLOP := 1.2  ## a touch this far out (times a button's radius) still finds it
const OFF := 1.25  ## a drag past this (times the button's radius) is off it: aiming
const CANCEL_R := 16.0  ## the cancel zone's radius (fixed: it never grows with the buttons)
const CANCEL_AT := Vector2(34, 94)  ## its centre, in from the top-right corner (under Pause)
const HOLD_TICKS := 18  ## held still this long, a charging move starts and charges
const AIM_HOLD := MouseOrders.AIM_HOLD  ## ticks an exact aim keeps being sent after a press
const SIZES := [0.85, 1.0, 1.2]  ## Settings > Controls > Touch > Button size
const SIZE_NAMES := ["Small", "Medium", "Large"]
const AIM_STYLES := ["Tap + drag", "Tap only"]
const DRAG_BUTTONS := ["heavy", "skill_1", "skill_2", "surge"]
const BITS := {
	"light": SimDefs.IN_LIGHT, "heavy": SimDefs.IN_HEAVY, "skill_1": SimDefs.IN_SKILL1,
	"skill_2": SimDefs.IN_SKILL2, "surge": SimDefs.IN_SURGE, "dodge": SimDefs.IN_DODGE,
	"guard": SimDefs.IN_GUARD, "tag": SimDefs.IN_TAG,
}
## Buttons whose bit stays on while the finger is down (charging, guarding).
const HOLDS := ["heavy", "skill_1", "skill_2", "guard"]
## Each button's spot from Light's centre at Medium size (screen y grows down), and radius.
const LAYOUT := {
	"light": [Vector2(0, 0), 24.0],
	"heavy": [Vector2(-60, 0), 15.0],
	"skill_1": [Vector2(-52, -30), 15.0],
	"skill_2": [Vector2(-30, -52), 15.0],
	"surge": [Vector2(0, -60), 15.0],
	"dodge": [Vector2(-100, 4), 14.0],
	"guard": [Vector2(-92, -40), 14.0],
	"tag": [Vector2(-62, -86), 12.0],
}
const LIGHT_IN := 42.0  ## Light's centre this far in from the bottom-right corner (Medium)
const PAUSE_R := 9.0
const PAUSE_AT := Vector2(14, 58)  ## in from the top-right corner, under the fighter panel

# Settings
var size_step := 1
var left_handed := false
var tap_only := false
var show_tag := false  ## Duel: the Tag button shows
## Which of the drag buttons start a charging move (main fills it from the fighter).
var charges := {}
## Touch-downs start fingers only while this is on (a fight with a local player); lifts
## and drags of fingers already down are always followed.
var active := true

## Bumped whenever anything the overlay draws from the pad changes.
var version := 0
## The stick: its centre while held (it floats to where the thumb landed), the knob.
var stick_origin := Vector2.ZERO
var stick_knob := Vector2.ZERO
var stick_finger := -1
## Set by a tap on Pause; main reads and clears it.
var pause_requested := false

var _screen := Vector2(480, 270)
var _centers := {}
var _radii := {}
var _rest := Vector2.ZERO
var _cancel_at := Vector2.ZERO
## index -> {"button": name, "start": Vector2, "pos": Vector2, "mode": armed|aiming|
## cancel|held, "t": ticks down}
var _fingers := {}
var _queue: Array = []  ## presses waiting for their tick: {"bit", "aim" (Vector2), "dodge"}
var _last := 0
var _last_dir := Vector2.ZERO
var _aim := Vector2.ZERO
var _aim_t := 0


func _init() -> void:
	layout(_screen)


## Lays the controls out for a screen of `size` canvas units (call again when it changes
## or a setting does).
func layout(size: Vector2) -> void:
	_screen = size
	var s: float = SIZES[clampi(size_step, 0, SIZES.size() - 1)]
	var light := Vector2(size.x - LIGHT_IN * s - 6.0 * s, size.y - LIGHT_IN * s - 6.0 * s)
	_centers.clear()
	_radii.clear()
	for b in LAYOUT:
		if b == "tag" and not show_tag:
			continue
		_centers[b] = _flip(light + (LAYOUT[b][0] as Vector2) * s)
		_radii[b] = float(LAYOUT[b][1]) * s
	_centers["pause"] = _flip(Vector2(size.x - PAUSE_AT.x, PAUSE_AT.y))
	_radii["pause"] = PAUSE_R
	_rest = _flip(Vector2(8.0 + 38.0 * s, size.y - 8.0 - 38.0 * s))
	_cancel_at = _flip(Vector2(size.x - CANCEL_AT.x, CANCEL_AT.y))
	if stick_finger < 0:
		stick_origin = _rest
		stick_knob = _rest
	version += 1


func _flip(p: Vector2) -> Vector2:
	return Vector2(_screen.x - p.x, p.y) if left_handed else p


func screen() -> Vector2:
	return _screen


func scale() -> float:
	return SIZES[clampi(size_step, 0, SIZES.size() - 1)]


func stick_radius() -> float:
	return STICK_R * scale()


func knob_radius() -> float:
	return KNOB_R * scale()


func rest_spot() -> Vector2:
	return _rest


## The cancel zone (shown only while a drag aims): let go inside it to cancel the cast.
func cancel_center() -> Vector2:
	return _cancel_at


func cancel_radius() -> float:
	return CANCEL_R


func in_cancel_zone(pos: Vector2) -> bool:
	return pos.distance_to(_cancel_at) <= CANCEL_R


## The buttons shown, in drawing order.
func buttons() -> Array:
	return _centers.keys()


func center(button: String) -> Vector2:
	return _centers.get(button, Vector2.INF)


func radius(button: String) -> float:
	return float(_radii.get(button, 0.0))


## Is a finger on this button now?
func is_down(button: String) -> bool:
	for f in _fingers.values():
		if String(f["button"]) == button:
			return true
	return false


## The drag being aimed, if any: {"button", "dir" (from the button's centre to the
## finger), "cancel" (the finger is in the cancel zone: letting go cancels), "held" (a
## charging move being aimed: already thrown, so no cancel zone)}; empty when nothing aims.
func aiming() -> Dictionary:
	for f in _fingers.values():
		var mode := String(f["mode"])
		var b := String(f["button"])
		var held_aim := mode == "held" and not tap_only and b in DRAG_BUTTONS and _off_button(f)
		if mode == "aiming" or mode == "cancel" or held_aim:
			return {"button": b, "dir": (f["pos"] as Vector2) - center(b),
				"cancel": mode == "cancel", "held": mode == "held"}
	return {}


func fingers_down() -> int:
	return _fingers.size() + (1 if stick_finger >= 0 else 0)


## Feeds one event; true when it was a touch event (handled here).
func feed(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.canceled:
			_lift(t.index, false)
		elif t.pressed:
			_touch(t.index, t.position)
		else:
			_lift(t.index, true)
		return true
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position)
		return true
	return false


## A lost touch (the app paused, the window lost focus, the fight ended): every finger
## is let go without firing anything, and presses not yet sent are dropped.
func release_all() -> void:
	if _fingers.is_empty() and stick_finger < 0 and _queue.is_empty() and _aim_t == 0:
		return
	_fingers.clear()
	_queue.clear()
	_aim_t = 0
	stick_finger = -1
	stick_origin = _rest
	stick_knob = _rest
	version += 1


func _touch(index: int, pos: Vector2) -> void:
	_lift(index, false)  # a repeated down for one index: start over
	if not active:
		return
	var b := _button_at(pos)
	if b == "pause":
		_fingers[index] = {"button": "pause", "start": pos, "pos": pos, "mode": "armed", "t": 0}
		version += 1
		return
	if b == "" and stick_finger < 0 and _in_stick_zone(pos):
		stick_finger = index
		stick_origin = pos
		stick_knob = pos
		version += 1
		return
	if b == "":
		return
	_fingers[index] = {"button": b, "start": pos, "pos": pos, "mode": "armed", "t": 0}
	version += 1
	if tap_only or not (b in DRAG_BUTTONS):
		_fingers[index]["mode"] = "held"
		_queue.append({"bit": int(BITS[b]), "dodge": b == "dodge"})


func _drag(index: int, pos: Vector2) -> void:
	if index == stick_finger:
		var v := pos - stick_origin
		var r := stick_radius()
		if v.length() > r:
			v = v.normalized() * r
		var knob := stick_origin + v
		if knob != stick_knob:
			stick_knob = knob
			version += 1
		return
	if not _fingers.has(index):
		return
	var f: Dictionary = _fingers[index]
	if f["pos"] == pos:
		return
	f["pos"] = pos
	version += 1
	var b := String(f["button"])
	if not (b in DRAG_BUTTONS) or tap_only:
		return
	var mode := String(f["mode"])
	if mode == "armed" and not _off_button(f):
		return  # still on the button: a tap so far
	if mode == "armed" or mode == "aiming" or mode == "cancel":
		f["mode"] = "cancel" if in_cancel_zone(pos) else "aiming"


func _lift(index: int, fire: bool) -> void:
	if index == stick_finger:
		stick_finger = -1
		stick_origin = _rest
		stick_knob = _rest
		version += 1
		return
	if not _fingers.has(index):
		return
	var f: Dictionary = _fingers[index]
	_fingers.erase(index)
	version += 1
	if not fire:
		return
	var b := String(f["button"])
	if b == "pause":
		if (f["pos"] as Vector2).distance_to(center("pause")) <= radius("pause") * SLOP:
			pause_requested = true
		return
	match String(f["mode"]):
		"armed":  # a tap: fire, aim assist picks the way
			_queue.append({"bit": int(BITS[b]), "dodge": false})
		"aiming":  # let go anywhere but the cancel zone: fire exactly that way
			_queue.append({"bit": int(BITS[b]), "dodge": false,
				"aim": (f["pos"] as Vector2) - center(b)})
		# "cancel": let go in the cancel zone, nothing; "held": already pressed, the hold ends


func _off_button(f: Dictionary) -> bool:
	var b := String(f["button"])
	return (f["pos"] as Vector2).distance_to(center(b)) > radius(b) * OFF


func _in_stick_zone(pos: Vector2) -> bool:
	if pos.y < STICK_TOP:
		return false
	var x := _screen.x - pos.x if left_handed else pos.x
	return x < _screen.x * STICK_ZONE


## The button under `pos` (the nearest within SLOP of its radius), or "".
func _button_at(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for b in _centers:
		var d := pos.distance_to(_centers[b]) / float(_radii[b])
		if d <= SLOP and d < best_d:
			best_d = d
			best = String(b)
	return best


## The stick's direction now (zero inside the dead zone or when let go).
func stick_dir() -> Vector2:
	if stick_finger < 0:
		return Vector2.ZERO
	var v := stick_knob - stick_origin
	return v if v.length() >= stick_radius() * STICK_DEAD else Vector2.ZERO


## One tick's bits. Call once per tick.
func bits() -> int:
	var out := 0
	var dir := stick_dir()
	if dir != Vector2.ZERO:
		out |= SimDefs.move_bits(dir)
		_last_dir = dir
	for f in _fingers.values():
		var b := String(f["button"])
		if b == "pause":
			continue
		f["t"] = int(f["t"]) + 1
		var mode := String(f["mode"])
		if mode == "armed" and int(f["t"]) >= HOLD_TICKS and charges.get(b, false):
			f["mode"] = "held"  # held still: the charge starts now and charges while held
			mode = "held"
			_queue.append({"bit": int(BITS[b]), "dodge": false})
			version += 1
		if mode == "held" and b in HOLDS:
			out |= int(BITS[b])
			if b != "guard" and not tap_only and _off_button(f):
				out |= SimDefs.aim_bits((f["pos"] as Vector2) - center(b))  # aiming the charge
	var waiting: Array = []
	for p in _queue:
		var bit := int(p["bit"])
		if _last & bit and bit != SimDefs.IN_GUARD:
			out &= ~bit  # the last tick carried it: a fresh press needs a gap first
			waiting.append(p)
			continue
		out |= bit  # (guard just carries on: holding it is all it does)
		if p.has("aim") and (p["aim"] as Vector2) != Vector2.ZERO:
			_aim = p["aim"]
			_aim_t = AIM_HOLD
		if p.get("dodge", false) and dir == Vector2.ZERO and _last_dir != Vector2.ZERO:
			out |= SimDefs.move_bits(_last_dir)  # the stick's last way, like the pad
	_queue = waiting
	if _aim_t > 0:
		_aim_t -= 1
		if not (out & SimDefs.IN_AIM):
			out |= SimDefs.aim_bits(_aim)
	_last = out
	return out
