class_name OnlineMatch
extends RefCounted
## One online Duel between two machines: the deterministic DuelSim driven by a
## RollbackSession, with the input stream on a NetLink. Netplay makes these; main shows
## whatever `duel` holds and plays `events`.
##
## Each tick:
##   1. Schedule the local input and send it (with this machine's frame and advantage).
##   2. Time sync: if this machine is running ahead of the other, skip a frame now and
##      then so both see about the same amount of rollback (GGPO's frame advantage).
##   3. Advance: roll back if a late input changed the past, then simulate one frame, or
##      wait if the other machine is too far behind.
##
## Effects: a rollback re-simulates frames, which emit their events again. Only events
## not already shown pass to the views (keyed by tick, kind and who), so a hit spark
## plays once; a hit that only turned out to happen after a correction still shows.
##
## Desync check: every DIGEST_EVERY confirmed frames each side sends a fingerprint of
## its whole match state. They must be identical; if not, `desync_frame` is set and the
## input log can be saved to replay the bug exactly.

const DIGEST_EVERY := 60
## Frames between time-sync waits, so a correction is spread out and nobody feels it.
const SYNC_COOLDOWN := 20

var duel: DuelSim
var session: RollbackSession
var link: NetLink
var id := 0  ## which match of the session this is (rematches count up)
var local_side := 0
var teams: Array
var input_delay := 2

## New events since the last tick, for the views.
var events: Array = []
## Ticks in a row spent waiting for the other player.
var waiting_ticks := 0
var sync_waits := 0
var desync_frame := -1
## How many state fingerprints both machines have agreed on so far.
var digests_matched := 0
## Every confirmed frame's inputs, [side 0, side 1]: a desync report replays from it.
var input_log := {}
## This machine's fingerprint of every checked frame (frame -> digest), for reports.
var final_digests := {}

var _tap: _Tap
var _digests := {}
var _remote_digests := {}
var _remote_frame := -1
var _remote_adv := 0.0
var _sync_cool := 0


## The match's game object for the rollback session: steps the duel and collects the
## events nobody has seen yet.
class _Tap:
	var duel: DuelSim
	var out: Array = []
	var _seen := {}  ## event key -> tick

	func _init(d: DuelSim) -> void:
		duel = d

	func step(inputs: PackedInt32Array) -> void:
		duel.step(inputs)
		var t := duel.sim.tick
		for e in duel.sim.events:
			var key := "%d:%s:%s:%s:%s" % [int(e.get("tick", t)), String(e["type"]), str(e.get("attacker", "")),
				str(e.get("target", "")), str(e.get("who", ""))]
			if not _seen.has(key):
				_seen[key] = t
				out.append(e)
		if t % 120 == 0:
			for k in _seen.keys():
				if int(_seen[k]) < t - 120:
					_seen.erase(k)

	func snapshot() -> Dictionary:
		return duel.snapshot()

	func restore(s: Dictionary) -> void:
		duel.restore(s)

	func state_digest() -> String:
		return duel.state_digest()


func _init(p_teams: Array, p_side: int, p_delay: int, p_link: NetLink, p_id: int) -> void:
	teams = p_teams
	local_side = p_side
	input_delay = p_delay
	link = p_link
	id = p_id
	duel = DuelSim.new(teams)
	_tap = _Tap.new(duel)
	session = RollbackSession.new(_tap, local_side, input_delay)
	session.on_final = _on_final


## A message for this match from the other machine.
func receive(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"in":
			var inputs = m.get("inputs")
			if not (inputs is PackedInt32Array):
				return
			session.receive({"first": int(m.get("first", 0)), "inputs": inputs})
			_remote_frame = maxi(_remote_frame, int(m.get("f", -1)))
			_remote_adv = float(m.get("adv", 0.0))
		"dg":
			var f := int(m.get("f", -1))
			_remote_digests[f] = String(m.get("d", ""))
			_check_digest(f)


func tick(local_bits: int) -> void:
	events.clear()
	_tap.out = events
	var adv := frame_advantage()
	var pkt := session.add_local_input(local_bits)
	pkt["t"] = "in"
	pkt["n"] = id
	pkt["f"] = session.frame
	pkt["adv"] = adv
	link.send(pkt)
	if _sync_cool > 0:
		_sync_cool -= 1
	# Running ahead of the other machine: hold this frame once, then wait a while.
	if _remote_frame >= 0 and _sync_cool == 0 and (adv - _remote_adv) * 0.5 >= 1.0:
		_sync_cool = SYNC_COOLDOWN
		sync_waits += 1
		session.sync()
		return
	if session.advance():
		waiting_ticks = 0
	else:
		waiting_ticks += 1


## How many frames this machine is ahead of the other (negative: behind), using the
## other side's last reported frame plus the time its packet spent on the way.
func frame_advantage() -> float:
	if _remote_frame < 0:
		return 0.0
	var one_way := link.rtt_ms() * 0.5 * SimDefs.TICK_RATE / 1000.0
	return float(session.frame) - (float(_remote_frame) + one_way)


func rollback_frames() -> int:
	return session.max_rollback_seen


func _on_final(f: int, inputs: PackedInt32Array, after: Dictionary) -> void:
	input_log[f] = [inputs[0], inputs[1]]
	if f > 0 and f % DIGEST_EVERY == 0:
		var d := snapshot_digest(after)
		_digests[f] = d
		final_digests[f] = d
		link.send({"t": "dg", "n": id, "f": f, "d": d}, true)
		_check_digest(f)


## A fingerprint of a saved match state. Snapshots are built in the same order on every
## machine and floats are compared bit for bit, so equal states give equal bytes. The
## terrain's redraw counter is left out: it only tells the view to repaint, and each
## rollback bumps it.
static func snapshot_digest(snap: Dictionary) -> String:
	var top := snap.duplicate()
	if top.has("match"):
		var m: Dictionary = (top["match"] as Dictionary).duplicate()
		m.erase("terrain_version")
		top["match"] = m
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(top))
	return ctx.finish().hex_encode()


func _check_digest(f: int) -> void:
	if not _digests.has(f) or not _remote_digests.has(f):
		return
	if _digests[f] != _remote_digests[f]:
		if desync_frame < 0 or f < desync_frame:
			desync_frame = f
	else:
		digests_matched += 1
	_digests.erase(f)
	_remote_digests.erase(f)


## Everything needed to replay this match offline and find a desync: the teams and the
## confirmed inputs of both sides, frame by frame.
func report() -> Dictionary:
	var frames: Array = []
	var f := 0
	while input_log.has(f):
		frames.append(input_log[f])
		f += 1
	return {"teams": teams, "input_delay": input_delay, "local_side": local_side,
		"desync_frame": desync_frame, "digests_matched": digests_matched, "frames": frames,
		"digests": final_digests, "at_frame": session.frame, "rollbacks": session.rollbacks,
		"max_rollback": session.max_rollback_seen, "sync_waits": sync_waits}
