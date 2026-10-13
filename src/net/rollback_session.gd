class_name RollbackSession
extends RefCounted
## Rollback netcode (GGPO-style) for one player's machine in a two-player match.
##
## Every machine runs the full deterministic simulation. Each tick:
##   1. The local player's input is scheduled `input_delay` frames ahead and sent to
##      the other machine (each packet repeats the last few inputs, so a lost packet
##      costs nothing).
##   2. The opponent's input for this frame is used if it has arrived; otherwise it is
##      PREDICTED (their last known input repeated, which is right most of the time).
##   3. When a real input arrives that differs from what was predicted, the match is
##      rolled back to that frame and quickly re-simulated to the present with the
##      right inputs. The player sees at most a few frames of correction.
##
## The game object only needs step(inputs), snapshot(), restore(snapshot) and
## state_digest(); MatchSim provides all four. Transport is up to the caller:
## add_local_input() returns the packet to send, receive() takes packets.

## Frames of input delay. 0 = most responsive, more = fewer rollbacks. Fighting games
## usually use 1-2 and adapt to the connection.
var input_delay := 2
## Never predict further than this ahead of the last confirmed remote input; the session
## waits (stalls) instead, which keeps rollbacks short.
var max_rollback := 8
## How many recent inputs ride along in every packet.
var redundancy := 8
## A packet carries at most this many inputs (when the other side is missing a lot).
const MAX_PACKET_INPUTS := 60
## The other machine has every input of ours up to this frame (it says so in its
## packets): anything after it that it hasn't got is sent again, so a burst of lost
## packets longer than `redundancy` can't leave both machines waiting for each other.
var remote_ack := -1

var game  ## the deterministic simulation
var local_player := 0
var frame := 0  ## the next frame to simulate

var _local := {}  ## frame -> input bits
var _remote := {}  ## frame -> confirmed input bits
var _used_remote := {}  ## frame -> the remote bits the simulation actually used
var _snapshots := {}  ## frame -> state before simulating that frame
var _confirmed := -1  ## every remote input up to this frame has arrived (no gaps)
var _rollback_from := -1

# Stats, for tuning and tests.
var rollbacks := 0
var rollback_frames := 0
var max_rollback_seen := 0
var stalls := 0


## Called once for each frame as it becomes final (both players' inputs confirmed and
## simulated with them, so it will never be rolled back), in order, with
## (frame, inputs used [side 0, side 1], snapshot of the state after that frame).
## Online play takes its input log and desync checks there.
var on_final := Callable()
var _final := -1

## Every input scheduled locally, frame -> bits (only kept when this is on; for tests).
var keep_history := false
var history := {}


## Both machines must use the same input delay: the first `input_delay` frames have no
## inputs on either side, so they start out confirmed as empty.
func _init(p_game, p_local_player: int, p_input_delay := 2) -> void:
	game = p_game
	local_player = p_local_player
	input_delay = p_input_delay
	for f in input_delay:
		_local[f] = 0
		_remote[f] = 0
		history[f] = 0
	_confirmed = input_delay - 1


## Records this tick's local input (it will be played `input_delay` frames from now)
## and returns the packet to send to the other player.
func add_local_input(bits: int) -> Dictionary:
	var f := frame + input_delay
	if not _local.has(f):
		_local[f] = bits
		if keep_history:
			history[f] = bits
	var first := maxi(0, f - redundancy + 1)
	if remote_ack + 1 < first:
		first = maxi(remote_ack + 1, f - MAX_PACKET_INPUTS + 1)
	var inputs := PackedInt32Array()
	for i in range(first, f + 1):
		inputs.append(int(_local.get(i, 0)))
	return {"first": first, "inputs": inputs, "ack": _confirmed}


## Takes a packet from the other player. Out-of-order and duplicate packets are fine.
func receive(packet: Dictionary) -> void:
	var first := int(packet["first"])
	var inputs: PackedInt32Array = packet["inputs"]
	if packet.has("ack"):
		remote_ack = maxi(remote_ack, int(packet["ack"]))
	for i in inputs.size():
		var f := first + i
		if _remote.has(f):
			continue
		var bits := inputs[i]
		_remote[f] = bits
		# Already simulated this frame with a guess? If the guess was wrong, rewind.
		if f < frame and _used_remote.has(f) and int(_used_remote[f]) != bits:
			if _rollback_from < 0 or f < _rollback_from:
				_rollback_from = f
	while _remote.has(_confirmed + 1):
		_confirmed += 1


## Simulates the next frame (after fixing any misprediction). Returns false if it had
## to wait for the other player instead.
func advance() -> bool:
	_do_rollback()
	if frame - _confirmed > max_rollback:
		stalls += 1
		return false
	_simulate(frame)
	frame += 1
	_finalize()
	_forget_old()
	return true


## Applies any pending correction now, without simulating a new frame.
func sync() -> void:
	_do_rollback()
	_finalize()


## Reports frames that just became final (see on_final). Runs after any rollback, so
## every frame up to the confirmed point was simulated with the right inputs.
func _finalize() -> void:
	var upto := mini(_confirmed, frame - 1)
	if _rollback_from >= 0:
		upto = mini(upto, _rollback_from - 1)
	while _final < upto:
		_final += 1
		if not on_final.is_valid():
			continue
		var inputs := PackedInt32Array([0, 0])
		inputs[local_player] = int(_local.get(_final, 0))
		inputs[1 - local_player] = int(_used_remote.get(_final, _remote.get(_final, 0)))
		var after = _snapshots.get(_final + 1) if _final + 1 < frame else game.snapshot()
		on_final.call(_final, inputs, after)


func _do_rollback() -> void:
	if _rollback_from < 0:
		return
	var from := _rollback_from
	_rollback_from = -1
	var depth := frame - from
	rollbacks += 1
	rollback_frames += depth
	max_rollback_seen = maxi(max_rollback_seen, depth)
	game.restore(_snapshots[from])
	for f in range(from, frame):
		_simulate(f)


func _simulate(f: int) -> void:
	_snapshots[f] = game.snapshot()
	var remote := _remote_input(f)
	_used_remote[f] = remote
	var inputs := PackedInt32Array([0, 0])
	inputs[local_player] = int(_local.get(f, 0))
	inputs[1 - local_player] = remote
	game.step(inputs)


## The confirmed input if it's here, else a prediction: the opponent is still doing
## whatever they were last confirmed doing (holding a direction, a guard...).
func _remote_input(f: int) -> int:
	if _remote.has(f):
		return int(_remote[f])
	return int(_remote.get(_confirmed, 0))


## Drops history nothing can roll back to: frames before the confirmed point are final.
func _forget_old() -> void:
	var keep_from := mini(mini(_confirmed + 1, frame - 1), _final + 1)
	for d in [_snapshots, _used_remote]:
		for k in d.keys():
			if int(k) < keep_from:
				d.erase(k)
	# Keep every remote input not yet simulated (the other machine can run ahead, and
	# its packets only repeat the last few inputs), plus the newest confirmed one, which
	# predictions copy.
	for k in _remote.keys():
		if int(k) < mini(_confirmed, frame - 1):
			_remote.erase(k)
	for k in _local.keys():
		if int(k) < mini(mini(frame - redundancy - input_delay - 2, _final + 1), remote_ack + 1):
			_local.erase(k)


## True once every simulated frame used confirmed inputs (nothing left to correct).
func is_settled() -> bool:
	return _confirmed >= frame - 1 and _rollback_from < 0


## Every remote input up to this frame has arrived.
func confirmed_frame() -> int:
	return _confirmed
