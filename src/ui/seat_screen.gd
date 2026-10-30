class_name SeatScreen
extends UiScreen
## Who's playing: the seats at this machine, before a local match's fighter pick.
##
## Player 1 is undecided until they press Enter (keyboard and mouse) or A on a controller
## (that pad, and the keyboard too). Every other controller that presses A takes the next
## empty seat. B gives a seat back (B / Esc from player 1 leaves the screen). Once `need`
## seats have joined, Enter or Start on a seated device goes on (`done`); the seats are
## packed by `LocalSeats.finish` then. Pure screen: it only talks to the seat table.

signal done
signal cancelled

const CARD_W := 104.0
const CARD_H := 92.0
const CARD_GAP := 8.0
const CARD_Y := 78.0

var mode_title := "VERSUS"
## Seats that must join before the match can start, and the most the screen lets in.
var need := 2
var most := 2
## Team modes: each seat picks a side with Left / Right (red or blue), at most `side_cap`
## a side (the team size; CPUs fill what's left).
var teams := false
var side_cap := 2
var seats: LocalSeats = null
var _o := Vector2.ZERO
var _font: Font


func _ready() -> void:
	focus_mode = FOCUS_ALL
	_font = UiTheme.font()
	resized.connect(queue_redraw)


## No rows: the screen itself takes the focus (the stack calls this on push).
func focus_first() -> void:
	grab_focus()


func rows() -> Array:
	return []


func ready_to_go() -> bool:
	if seats == null or seats.joined() < need:
		return false
	if teams:
		for side in 2:
			if _on_side(side) > side_cap:
				return false
	return true


## How many joined seats picked `side`.
func _on_side(side: int) -> int:
	var n := 0
	for k in most:
		if seats.decided(k) and seats.side_of_seat(k) == side:
			n += 1
	return n


## A seat's side is 0 or 1 (`dir` flips it); only the seat's own device changes it.
func _pick_side(seat: int, dir: int) -> void:
	if not teams or seat < 0:
		return
	seats.set_side(seat, 1 if dir > 0 else 0)


func _gui_input(event: InputEvent) -> void:
	if seats == null:
		return
	if event is InputEventJoypadButton:
		if not event.pressed:
			return
		var b := (event as InputEventJoypadButton).button_index
		var dev := event.device
		var held := seats.holder_of(dev)
		if b == JOY_BUTTON_A:
			if held < 0:
				seats.claim(dev)
			elif ready_to_go():
				_finish()
		elif b == JOY_BUTTON_B:
			if held == 0:
				cancelled.emit()
			elif held > 0:
				seats.unclaim(held)
		elif b == JOY_BUTTON_START:
			if held >= 0 and ready_to_go():
				_finish()
		elif b == JOY_BUTTON_DPAD_LEFT or b == JOY_BUTTON_DPAD_RIGHT:
			_pick_side(held, -1 if b == JOY_BUTTON_DPAD_LEFT else 1)
		else:
			return
		accept_event()
		queue_redraw()
		return
	if event is InputEventJoypadMotion or event is InputEventMouse:
		return
	# The keyboard (and a test's InputEventAction): player 1's.
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("menu_confirm"):
		if not seats.keyboard_only() and ready_to_go():
			_finish()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu_back"):
		cancelled.emit()
	elif event.is_action_pressed("pause"):
		if ready_to_go():
			_finish()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_pick_side(0 if seats.decided(0) else -1, -1 if event.is_action_pressed("ui_left") else 1)
	else:
		return
	accept_event()
	queue_redraw()


func _finish() -> void:
	done.emit()


func _card_rect(k: int) -> Rect2:
	var w := most * CARD_W + (most - 1) * CARD_GAP
	var x := (SimDefs.VIEW_W - w) * 0.5 + k * (CARD_W + CARD_GAP)
	return Rect2(x, CARD_Y, CARD_W, CARD_H)


## What a seat's card says under its name.
func seat_lines(k: int) -> Array:
	if seats == null:
		return []
	var pad := seats.device_of(k)
	var side := ""
	if teams and seats.decided(k):
		side = "< RED >" if seats.side_of_seat(k) == 0 else "< BLUE >"
	if k == 0:
		if pad == PlayerInput.ANY_PAD:
			return ["Enter: keyboard + mouse", "A: a controller"]
		if pad == PlayerInput.NO_PAD:
			return ["Keyboard + mouse", side, "Ready"] if teams else ["Keyboard + mouse", "Ready"]
		return ["Keyboard + controller %d" % (pad + 1), side, "Ready"] if teams else ["Keyboard + controller %d" % (pad + 1), "Ready"]
	if pad >= 0:
		return ["Controller %d" % (pad + 1), side, "Ready"] if teams else ["Controller %d" % (pad + 1), "Ready"]
	return ["Press A on a", "controller to join"]


## The side's colour for a seat's side line (the card's other lines are dim or accent).
func _line_color(k: int, i: int, lines: Array) -> Color:
	var in_seat := seats != null and seats.decided(k)
	if teams and in_seat and i == 1 and lines.size() == 3:
		return Accessibility.side_color(seats.side_of_seat(k))
	return UiTheme.C_ACCENT if in_seat and i == lines.size() - 1 else UiTheme.C_DIM


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.94))
	_o = ((size - Vector2(SimDefs.VIEW_W, SimDefs.VIEW_H)) * 0.5).floor()
	draw_set_transform(_o)
	var w := float(SimDefs.VIEW_W)
	_text(Vector2(0, 30), mode_title, 14, UiTheme.C_TEXT, w)
	_text(Vector2(0, 40), "Who's playing?  %d of %d seats" % [seats.joined() if seats != null else 0, need], 6,
		UiTheme.C_DIM, w)
	for k in most:
		var r := _card_rect(k)
		var in_seat := seats != null and seats.decided(k)
		draw_rect(r, Color(0.13, 0.15, 0.19, 0.95))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Accessibility.brawl_color(k))
		draw_rect(r, Accessibility.brawl_color(k) if in_seat else UiTheme.C_BORDER, false, 1.0)
		_text(Vector2(r.position.x, r.position.y + 20), "PLAYER %d" % (k + 1), 9,
			UiTheme.C_TEXT if in_seat else UiTheme.C_DIM, r.size.x)
		var lines := seat_lines(k)
		for i in lines.size():
			_text(Vector2(r.position.x, r.position.y + 40 + i * 10), String(lines[i]), 5, _line_color(k, i, lines), r.size.x)
	if ready_to_go():
		draw_rect(Rect2(0, 196, w, 22), Color(0, 0, 0, 0.6))
		_text(Vector2(0, 212), "Enter / Start: pick your fighters", 10, UiTheme.C_ACCENT, w)
	elif teams and seats != null and seats.joined() >= need:
		_text(Vector2(0, 212), "At most %d a side" % side_cap, 8, UiTheme.C_DIM, w)
	var foot := "B: give a seat back   Esc / B (player 1): back"
	if teams:
		foot = "Left / Right: your side   " + foot
	_text(Vector2(0, 258), foot, 6, UiTheme.C_DIM, w)


func _text(pos: Vector2, s: String, size_px: int, col: Color, width: float) -> void:
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, UiTheme.px(size_px), col)
