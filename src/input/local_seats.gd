class_name LocalSeats
extends RefCounted
## The seats at this machine: which device feeds each local player's PlayerInput.
##
## Seat 0 is player 1 (main's `player_input`: keyboard and mouse, touch, and a pad); seats
## 1-3 are players 2-4, controller only. `assign` hands the connected pads out when a match
## starts, `pad_lost` / `pad_found` keep the table right when one is unplugged or plugged in
## mid-match (the same pad, or the next one plugged in, takes the empty seat back), and
## `seat_of_device` / `owner_of_event` say whose pad an event came from. A local human is a
## sim slot fed by a seat, as an online human is a slot fed by the network; the sim never
## knows the difference. Pure logic: main feeds it `Input.get_connected_joypads()` and the
## `joy_connection_changed` signal, so tests drive it without a controller.

const MAX_SEATS := 4

## One PlayerInput a seat; `inputs[0]` is main's `player_input`.
var inputs: Array[PlayerInput] = []
## How many people play at this machine in the current match (1 when solo).
var humans := 1
## Seats whose controller was unplugged mid-match (seat -> the pad's GUID), kept so the
## same pad, or the next one plugged in, takes the seat back.
var lost := {}
## Pad id -> GUID of every pad the table has been told about.
var guids := {}


func _init(first: PlayerInput = null) -> void:
	inputs.append(first if first != null else PlayerInput.new())
	for _k in range(1, MAX_SEATS):
		var pin := PlayerInput.new()
		pin.keyboard = false
		pin.pad_device = PlayerInput.NO_PAD
		inputs.append(pin)


func input_of(seat: int) -> PlayerInput:
	return inputs[clampi(seat, 0, MAX_SEATS - 1)]


func device_of(seat: int) -> int:
	return input_of(seat).pad_device


## Whether seat `seat` plays in the current match with something to press: player 1 always
## (the keyboard), the others once they hold a controller.
func seated(seat: int) -> bool:
	if seat < 0 or seat >= humans:
		return false
	return seat == 0 or device_of(seat) >= 0


## Hands the connected pads out for a match of `p_humans` people: with a controller each,
## everyone gets one (player 1 keeps the keyboard too); one short, player 1 uses keyboard
## and mouse and the controllers go to players 2 and up. Returns what to tell the players
## when controllers are missing ("" when nobody is).
func assign(p_humans: int, pads: Array, pad_guids := {}) -> String:
	humans = clampi(p_humans, 1, MAX_SEATS)
	lost.clear()
	for id in pad_guids:
		guids[int(id)] = String(pad_guids[id])
	inputs[0].keyboard = true
	inputs[0].pad_device = PlayerInput.ANY_PAD
	for k in range(1, MAX_SEATS):
		inputs[k].pad_device = PlayerInput.NO_PAD
		inputs[k].release_pad()
	if humans <= 1:
		return ""
	var need := humans - 1
	var first := 0
	if pads.size() >= humans:
		inputs[0].pad_device = int(pads[0])
		first = 1
	else:
		inputs[0].pad_device = PlayerInput.NO_PAD
	for k in need:
		if first + k < pads.size():
			inputs[1 + k].pad_device = int(pads[first + k])
	if pads.size() < need:
		var short := need - pads.size()
		return "Connect %d controller%s for players %s" % [short, "" if short == 1 else "s",
			"2-%d" % humans if humans > 2 else "2"]
	return ""


## The seat whose controller `device` is: a pad a seat holds, else player 1 when they listen
## to any pad (solo play), else -1 (a pad nobody is playing on).
func seat_of_device(device: int) -> int:
	for k in range(1, MAX_SEATS):
		if inputs[k].pad_device == device:
			return k
	if inputs[0].pad_device == device or inputs[0].pad_device == PlayerInput.ANY_PAD:
		return 0
	return -1


## The seat an input event belongs to: a controller event to the seat holding that pad,
## anything else (keyboard, mouse, touch) to player 1.
func owner_of_event(event: InputEvent) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return seat_of_device(event.device)
	return 0


## Hands `event` to the seat it belongs to (for prompts and `pad_id`). Returns that seat.
func note_event(event: InputEvent) -> int:
	var k := owner_of_event(event)
	if k >= 0:
		inputs[k].note_event(event)
	return k


## A controller was unplugged: the seat holding it lets go of everything it held and keeps
## its place for the pad's return. Returns that seat, or -1 when nobody was playing on it.
func pad_lost(device: int) -> int:
	for k in humans:
		if inputs[k].pad_device != device:
			continue
		lost[k] = String(guids.get(device, ""))
		inputs[k].pad_device = PlayerInput.NO_PAD
		inputs[k].release_pad()
		return k
	return -1


## A controller was plugged in: the seat that lost this very pad (by GUID) takes it back,
## else the first seat still waiting for a controller (one lost mid-match, or never given
## one at the start). Returns that seat, or -1 when nobody needed it.
func pad_found(device: int, guid := "") -> int:
	guids[device] = guid
	var waiting: Array[int] = []
	for k in humans:
		if k in lost or (k > 0 and inputs[k].pad_device == PlayerInput.NO_PAD):
			waiting.append(k)
	if waiting.is_empty():
		return -1
	var seat: int = waiting[0]
	if guid != "":
		for k in waiting:
			if String(lost.get(k, "")) == guid:
				seat = k
				break
	inputs[seat].pad_device = device
	lost.erase(seat)
	return seat


## The controller to rumble for seat `seat`: its pad, or for player 1 the pad they used
## last while it's the device in use; -1 for none.
func rumble_device(seat: int) -> int:
	var pin := input_of(seat)
	if seat == 0:
		return pin.pad_id if pin.device == PlayerInput.Device.GAMEPAD else -1
	return pin.pad_device if pin.pad_device >= 0 else -1


func set_pad_layout(lay: String) -> void:
	for pin in inputs:
		pin.pad_layout = lay


func reset_all() -> void:
	for pin in inputs:
		pin.reset()
