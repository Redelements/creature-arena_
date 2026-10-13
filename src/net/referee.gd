class_name Referee
extends RefCounted
## The dedicated server's copy of one online match (a 1v1 Duel or a 2v2/3v3 team
## battle). It never predicts or rolls back: it steps the match only once every player's
## input for a frame has arrived, so its match is the true one. Every player sends a
## fingerprint of their state every OnlineMatch.DIGEST_EVERY frames; the referee checks
## each against its own, so it can tell whose game went wrong, and it records the result.
##
## CPU players (team battles): a slot with no player, or whose player left, is played
## by a CpuController reading the referee's own match, the true one. Its input for a
## frame is decided as that frame is stepped, and the server sends it to everyone like
## any player's (take_cpu_inputs), so the players' games predict and roll back on it
## as usual. Nothing about it lives in the deterministic simulation.

## Input packets repeat the last few frames (more when resending); anything bigger is junk.
const MAX_PACKET_INPUTS := RollbackSession.MAX_PACKET_INPUTS
## Inputs further ahead than this of the referee's own frame are ignored (a client can't
## run that far ahead, so they can only be junk filling the server's memory).
const MAX_AHEAD := 600
## Every slot's inputs this far back are kept, so when a CPU takes over a slot whoever
## missed some of the leaver's last inputs can still get them.
const HISTORY := 240

var duel  ## the match: a DuelSim (1v1) or a TeamSim (team battle)
var teams: Array
var players := 2  ## input slots
var frame := 0  ## the next frame to simulate
var winner := -2  ## the match's result once decided: the winning side (-1 draw)
var finished_at := -1  ## frame the result was decided
## Frame of the first fingerprint each player got wrong (-1: none yet), by slot.
var desync: Array = []
var checked := 0  ## fingerprints that matched

var _inputs: Array = []  ## slot -> frame -> bits
var _history: Array = []  ## slot -> frame -> bits, the last HISTORY frames stepped
## slot -> CpuController for the CPU-played slots.
var cpus := {}
## The CPUs' inputs decided since the last take_cpu_inputs(): slot -> {first, inputs}.
var _cpu_out := {}
var _mine := {}  ## frame -> digest
var _theirs: Array = []  ## slot -> frame -> digest


## `size` players per side: 1 is a Duel, 2 or 3 a team battle.
func _init(p_teams: Array, input_delay: int, size := 1) -> void:
	teams = p_teams
	if size > 1:
		duel = TeamSim.new(teams, size)
		players = size * 2
	else:
		duel = DuelSim.new(teams)
	for p in players:
		_inputs.append({})
		_history.append({})
		_theirs.append({})
		desync.append(-1)
	for f in input_delay:  # nobody has input before the delay runs out
		for p in players:
			_inputs[p][f] = 0


## An input packet from slot `side` ({first, inputs}). Returns false if it's malformed.
func add_inputs(side: int, m: Dictionary) -> bool:
	var inputs = m.get("inputs")
	if not (inputs is PackedInt32Array) or (inputs as PackedInt32Array).size() > MAX_PACKET_INPUTS:
		return false
	var first := int(m.get("first", -1))
	if first < 0 or first > frame + MAX_AHEAD:
		return false
	var d: Dictionary = _inputs[side]
	for i in (inputs as PackedInt32Array).size():
		var f := first + i
		if f >= frame and not d.has(f):
			d[f] = (inputs as PackedInt32Array)[i]
	return true


## From now on a CPU plays `slot` (any inputs its player already sent are still used).
func add_cpu(slot: int, level := 1, seed := 1) -> void:
	cpus[slot] = CpuController.new(slot, level, seed)
	desync[slot] = -1
	(_theirs[slot] as Dictionary).clear()


## The CPUs' new inputs, to send to the players: slot -> {first, inputs}; then clears.
func take_cpu_inputs() -> Dictionary:
	var out := _cpu_out
	_cpu_out = {}
	return out


## The last frame of `slot`'s inputs the referee has with no gaps (its frame - 1 if
## the next one hasn't come): the player has had everything up to here acknowledged.
func have_upto(slot: int) -> int:
	var f := frame
	var d: Dictionary = _inputs[slot]
	while d.has(f):
		f += 1
	return f - 1


## Every input of `slot`'s the referee knows from `from` on (clamped to what's kept),
## as input packets ({first, inputs}), one per unbroken run: what a CPU taking over
## sends first. The leaver's last packets may have reached some players and not others,
## so all of them go to everyone; the CPU only decides the frames nobody has.
func inputs_since(slot: int, from: int) -> Array:
	var known := {}
	var h: Dictionary = _history[slot]
	for f in h:
		if int(f) >= from:
			known[int(f)] = int(h[f])
	var d: Dictionary = _inputs[slot]
	for f in d:
		if int(f) >= from:
			known[int(f)] = int(d[f])
	var frames: Array = known.keys()
	frames.sort()
	var out: Array = []
	var first := -1
	var run := PackedInt32Array()
	for f in frames:
		if first >= 0 and first + run.size() != int(f):
			out.append({"first": first, "inputs": run})
			run = PackedInt32Array()
			first = -1
		if first < 0:
			first = int(f)
		run.append(int(known[f]))
	if first >= 0:
		out.append({"first": first, "inputs": run})
	return out


## A state fingerprint from `side`.
func add_digest(side: int, f: int, digest: String) -> void:
	if f <= 0 or f > frame + MAX_AHEAD or (_theirs[side] as Dictionary).size() > 64:
		return
	_theirs[side][f] = digest
	_check(f)


## Simulates every frame all players' inputs have arrived for.
func advance() -> int:
	var n := 0
	while _all_have(frame):
		var ins := PackedInt32Array()
		for p in players:
			var bits := 0
			if (_inputs[p] as Dictionary).has(frame):
				bits = int(_inputs[p][frame])
				_inputs[p].erase(frame)
			else:
				bits = (cpus[p] as CpuController).bits(duel.sim)
				# Packed arrays copy on assignment: build it, then put it back.
				var pkt: Dictionary = _cpu_out.get(p, {"first": frame, "inputs": PackedInt32Array()})
				var list: PackedInt32Array = pkt["inputs"]
				list.append(bits)
				pkt["inputs"] = list
				_cpu_out[p] = pkt
			ins.append(bits)
			_history[p][frame] = bits
			_history[p].erase(frame - HISTORY)
		duel.step(ins)
		if winner == -2 and duel.winner != -2:
			winner = duel.winner
			finished_at = frame
		if frame > 0 and frame % OnlineMatch.DIGEST_EVERY == 0:
			_mine[frame] = OnlineMatch.snapshot_digest(duel.snapshot())
			_check(frame)
		frame += 1
		n += 1
	return n


func _all_have(f: int) -> bool:
	for p in players:
		if not (_inputs[p] as Dictionary).has(f) and not cpus.has(p):
			return false
	return true


func _check(f: int) -> void:
	if not _mine.has(f):
		return
	var done := true
	for side in players:
		if cpus.has(side):
			continue  # a CPU sends no fingerprints
		if not (_theirs[side] as Dictionary).has(f):
			done = false
			continue
		if _theirs[side][f] != _mine[f]:
			if desync[side] < 0:
				desync[side] = f
		else:
			checked += 1
		_theirs[side].erase(f)
	if done:
		_mine.erase(f)
	# Fingerprints that never came (a player left) don't pile up.
	for k in _mine.keys():
		if int(k) < f - OnlineMatch.DIGEST_EVERY * 4:
			_mine.erase(k)
