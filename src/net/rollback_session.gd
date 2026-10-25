class_name RollbackSession
extends RefCounted
## Rollback netcode (GGPO-style) for one player's machine in a match of 2 or more
## players (a 1v1, or a 2v2/3v3/4v4 team battle with every player on their own machine).
##
## Every machine runs the full deterministic simulation. Each tick:
##   1. The local player's input is scheduled `input_delay` frames ahead and sent to
##      the other machine (each packet repeats the last few inputs, so a lost packet
##      costs nothing).
##   2. Each other player's input for this frame is used if it has arrived; otherwise
##      it is PREDICTED (their last known input repeated, right most of the time).
##   3. When a real input arrives that differs from what was predicted, the match is
##      rolled back to that frame and quickly re-simulated to the present with the
##      right inputs. The player sees at most a few frames of correction.
##
## The game object only needs step(inputs), snapshot(), restore(snapshot) and
## state_digest(); MatchSim provides all four. Transport is up to the caller:
## add_local_input() returns the packet to send, receive() takes packets (each says
## which player `p` it's from; a two-player packet without one is the other player's).

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
## The most input delay a session takes: a "start" from a host or server asking for more
## is clamped (rollback keeps 8 frames; Netplay.pick_delay picks 1-3).
const MAX_INPUT_DELAY := 8
## Remote inputs further ahead of this machine than this many frames are dropped: no
## honest peer runs that far ahead (the server's Referee uses the same window).
const MAX_AHEAD := 600
## Every other machine has every input of ours up to this frame (each says so in its
## packets; this is the lowest): anything after it is sent again, so a burst of lost
## packets longer than `redundancy` can't leave the machines waiting for each other.
var remote_ack := -1

var game  ## the deterministic simulation
var local_player := 0
var players := 2  ## input slots in the match
var frame := 0  ## the next frame to simulate

var _local := {}  ## frame -> input bits
var _remote: Array = []  ## player -> {frame -> confirmed input bits} (empty for the local one)
var _confirmed_p: Array = []  ## player -> every input of theirs up to here has arrived
var _acks: Array = []  ## player -> how far they have all of ours
var _used := {}  ## frame -> the inputs the simulation actually used (every player)
var _snapshots := {}  ## frame -> state before simulating that frame
var _confirmed := -1  ## every other player's input up to this frame has arrived
var _rollback_from := -1

# Stats, for tuning and tests.
var rollbacks := 0
var rollback_frames := 0
var max_rollback_seen := 0
var stalls := 0


## Called once for each frame as it becomes final (both players' inputs confirmed and
## simulated with them, so it will never be rolled back), in order, with
## (frame, inputs used [one per player], snapshot of the state after that frame).
## Online play takes its input log and desync checks there.
var on_final := Callable()
var _final := -1

## Every input scheduled locally, frame -> bits (only kept when this is on; for tests).
var keep_history := false
var history := {}


## Both machines must use the same input delay: the first `input_delay` frames have no
## inputs on either side, so they start out confirmed as empty.
func _init(p_game, p_local_player: int, p_input_delay := 2, p_players := 2) -> void:
	game = p_game
	local_player = p_local_player
	input_delay = clampi(p_input_delay, 0, MAX_INPUT_DELAY)
	players = maxi(2, p_players)
	for p in players:
		_remote.append({})
		_confirmed_p.append(input_delay - 1)
		_acks.append(-1)
	for f in input_delay:
		_local[f] = 0
		history[f] = 0
		for p in players:
			if p != local_player:
				_remote[p][f] = 0
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


## Takes a packet from another player. Out-of-order and duplicate packets are fine.
func receive(packet: Dictionary) -> void:
	var p := int(packet.get("p", 1 - local_player if players == 2 else -1))
	if p < 0 or p >= players or p == local_player:
		return
	if not (packet.get("inputs") is PackedInt32Array) or not (typeof(packet.get("first")) in [TYPE_INT, TYPE_FLOAT]):
		return
	var first := int(packet["first"])
	var inputs: PackedInt32Array = packet["inputs"]
	if packet.has("ack"):
		# Nobody can have confirmed inputs this machine hasn't scheduled yet.
		_acks[p] = maxi(int(_acks[p]), mini(int(packet["ack"]), frame + input_delay))
		var lowest := 1 << 30
		for q in players:
			if q != local_player:
				lowest = mini(lowest, int(_acks[q]))
		remote_ack = lowest
	var mine: Dictionary = _remote[p]
	# Only frames this machine still needs, and none past MAX_AHEAD: whatever a packet's
	# `first` and length, it can't make the session keep (or loop over) more than that.
	var from := clampi(int(_confirmed_p[p]) - first, 0, inputs.size())
	var upto := clampi(frame + MAX_AHEAD - first + 1, 0, inputs.size())
	for i in range(from, upto):
		var f := first + i
		if mine.has(f) or f <= int(_confirmed_p[p]) - 1:
			continue
		var bits := inputs[i]
		mine[f] = bits
		# Already simulated this frame with a guess? If the guess was wrong, rewind.
		if f < frame and _used.has(f) and int((_used[f] as PackedInt32Array)[p]) != bits:
			if _rollback_from < 0 or f < _rollback_from:
				_rollback_from = f
	while mine.has(int(_confirmed_p[p]) + 1):
		_confirmed_p[p] = int(_confirmed_p[p]) + 1
	var low := 1 << 30
	for q in players:
		if q != local_player:
			low = mini(low, int(_confirmed_p[q]))
	_confirmed = low


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
		var inputs: PackedInt32Array = _used[_final] if _used.has(_final) else _inputs_for(_final)
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
	var inputs := _inputs_for(f)
	_used[f] = inputs
	game.step(inputs)


## Every player's input for frame `f`: ours, and the others' confirmed or predicted.
func _inputs_for(f: int) -> PackedInt32Array:
	var inputs := PackedInt32Array()
	inputs.resize(players)
	for p in players:
		inputs[p] = int(_local.get(f, 0)) if p == local_player else _remote_input(p, f)
	return inputs


## The confirmed input if it's here, else a prediction: that player is still doing
## whatever they were last confirmed doing (holding a direction, a guard...).
func _remote_input(p: int, f: int) -> int:
	var mine: Dictionary = _remote[p]
	if mine.has(f):
		return int(mine[f])
	return int(mine.get(_confirmed_p[p], 0))


## Drops history nothing can roll back to: frames before the confirmed point are final.
func _forget_old() -> void:
	var keep_from := mini(mini(_confirmed + 1, frame - 1), _final + 1)
	for d in [_snapshots, _used]:
		for k in d.keys():
			if int(k) < keep_from:
				d.erase(k)
	# Keep every remote input not yet simulated (the other machines can run ahead, and
	# their packets only repeat the last few inputs), everything a rollback to the
	# slowest player's frame could replay, and each player's newest confirmed input,
	# which predictions copy.
	var drop_below := mini(_confirmed, frame - 1)
	for p in players:
		if p == local_player:
			continue
		var mine: Dictionary = _remote[p]
		for k in mine.keys():
			if int(k) < drop_below:
				mine.erase(k)
	for k in _local.keys():
		if int(k) < mini(mini(frame - redundancy - input_delay - 2, _final + 1), remote_ack + 1):
			_local.erase(k)


## True once every simulated frame used confirmed inputs (nothing left to correct).
func is_settled() -> bool:
	return _confirmed >= frame - 1 and _rollback_from < 0


## Every remote input up to this frame has arrived.
func confirmed_frame() -> int:
	return _confirmed
