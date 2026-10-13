class_name Referee
extends RefCounted
## The dedicated server's copy of one online match (a 1v1 Duel or a 2v2/3v3 team
## battle). It never predicts or rolls back: it steps the match only once every player's
## input for a frame has arrived, so its match is the true one. Every player sends a
## fingerprint of their state every OnlineMatch.DIGEST_EVERY frames; the referee checks
## each against its own, so it can tell whose game went wrong, and it records the result.

## Input packets repeat the last few frames (more when resending); anything bigger is junk.
const MAX_PACKET_INPUTS := RollbackSession.MAX_PACKET_INPUTS
## Inputs further ahead than this of the referee's own frame are ignored (a client can't
## run that far ahead, so they can only be junk filling the server's memory).
const MAX_AHEAD := 600

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
			ins.append(int(_inputs[p][frame]))
			_inputs[p].erase(frame)
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
		if not (_inputs[p] as Dictionary).has(f):
			return false
	return true


func _check(f: int) -> void:
	if not _mine.has(f):
		return
	var done := true
	for side in players:
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
