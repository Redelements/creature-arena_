class_name MenuStick
extends Node
## Turns a gamepad's left stick into clean menu presses (ui_up / ui_down / ui_left /
## ui_right), like a d-pad: one press when the stick is pushed, then a steady repeat while
## it's held.
##
## Godot's built-in ui actions read the stick themselves, but every small movement past
## the deadzone counts as a new press: one flick skipped several rows, and a diagonal moved
## both ways. Controls.setup() takes the stick out of those actions; this node puts it back
## as proper presses. It goes by time, not frames, so it behaves the same at any frame rate.

## Pushed past this far counts as pressed; it lets go below RELEASE (no flicker at the edge).
const PRESS := 0.6
const RELEASE := 0.35
## Held: the first repeat after this long, then one every REPEAT seconds.
const FIRST_REPEAT := 0.4
const REPEAT := 0.11

const ACTIONS := {Vector2i.UP: "ui_up", Vector2i.DOWN: "ui_down", Vector2i.LEFT: "ui_left",
	Vector2i.RIGHT: "ui_right"}

## Only menus listen; main turns this off during a fight.
var enabled := true
var held := Vector2i.ZERO  ## the direction being held (ZERO: none)
var _hold_t := 0.0
var _next_repeat := 0.0


func _process(delta: float) -> void:
	if not enabled:
		held = Vector2i.ZERO
		return
	for action in step(_stick(), delta):
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		Input.parse_input_event(ev)


## The menu presses for this frame, given the stick and the time since the last frame.
## Only the stronger axis counts, so a diagonal moves one way.
func step(v: Vector2, dt: float) -> Array:
	var dir := held
	if held == Vector2i.ZERO or _amount(v, held) < RELEASE:
		dir = Vector2i.ZERO
		if maxf(absf(v.x), absf(v.y)) >= PRESS:
			if absf(v.x) > absf(v.y):
				dir = Vector2i.RIGHT if v.x > 0.0 else Vector2i.LEFT
			else:
				dir = Vector2i.DOWN if v.y > 0.0 else Vector2i.UP
	if dir == Vector2i.ZERO:
		held = dir
		return []
	if dir != held:
		held = dir
		_hold_t = 0.0
		_next_repeat = FIRST_REPEAT
		return [ACTIONS[dir]]
	_hold_t += dt
	if _hold_t >= _next_repeat:
		_next_repeat += REPEAT
		return [ACTIONS[dir]]
	return []


## How far the stick is pushed toward `dir`.
static func _amount(v: Vector2, dir: Vector2i) -> float:
	return v.dot(Vector2(dir))


## The left stick of whichever connected pad is pushed furthest.
static func _stick() -> Vector2:
	var best := Vector2.ZERO
	for dev in Input.get_connected_joypads():
		var v := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if v.length() > best.length():
			best = v
	return best
