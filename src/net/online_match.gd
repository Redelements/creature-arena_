class_name OnlineMatch
extends RefCounted
## One online match: a 1v1 Duel between two machines (DuelSim), or a 2v2/3v3 team
## battle with each player on their own machine (TeamSim), driven by a RollbackSession,
## with the input streams on a NetLink. Netplay makes these; main shows whatever `duel`
## or `team` holds and plays `events`.
##
## Each tick:
##   1. Schedule the local input and send it (with this machine's frame and advantage).
##   2. Time sync: if this machine is running ahead of another, skip a frame now and
##      then so both see about the same amount of rollback (GGPO's frame advantage).
##      With several players each pair is compared, and the furthest-behind one counts.
##   3. Advance: roll back if a late input changed the past, then simulate one frame, or
##      wait if another machine is too far behind.
##
## Effects: a rollback re-simulates frames, which emit their events again. Only events
## not already shown pass to the views (keyed by tick, kind and who), so a hit spark
## plays once; a hit that only turned out to happen after a correction still shows.
##
## Desync check: every DIGEST_EVERY confirmed frames each player sends a fingerprint of
## their whole match state. They must be identical; if not, `desync_frame` is set and
## the input log can be saved to replay the bug exactly.

const DIGEST_EVERY := 60
## Frames between time-sync waits, so a correction is spread out and nobody feels it.
const SYNC_COOLDOWN := 20

var duel: DuelSim = null  ## a 1v1 (null in a team battle)
var team: TeamSim = null  ## a team battle (null in a 1v1)
var session: RollbackSession
var link: NetLink
var id := 0  ## which match of the session this is (rematches count up)
var local_slot := 0  ## this machine's player: its input slot (= its side in a 1v1)
var local_side := 0  ## the side that player fights for
var size := 1  ## players per side
var players := 2
var teams: Array
var input_delay := 2
## Through a dedicated server, each player's round trip to it: their packets travel
## that far too, on top of this machine's own hop (the link's round trip).
var relay_rtts: Array = []
## In a 1v1: the opponent's round trip to the server.
var relay_rtt_ms: float:
	get:
		return float(relay_rtts[1 - local_slot]) if players == 2 else 0.0
	set(v):
		if players == 2:
			relay_rtts[1 - local_slot] = v

## Slots the server's CPU plays (team battles: empty slots, or a player who left).
## Their inputs come from the server after everyone's, so they don't count for time
## sync, and they send no fingerprints.
var cpu_slots := {}
## New events since the last tick, for the views.
var events: Array = []
## Ticks in a row spent waiting for the other player.
var waiting_ticks := 0
var sync_waits := 0
var desync_frame := -1
## How many state fingerprints both machines have agreed on so far.
var digests_matched := 0
## Every confirmed frame's inputs, one per player: a desync report replays from it.
var input_log := {}
## This machine's fingerprint of every checked frame (frame -> digest), for reports.
var final_digests := {}

var _tap: _Tap
var _digests := {}  ## frame -> ours
var _remote_digests := {}  ## "player:frame" -> theirs
var _remote_frame: Array = []  ## player -> the frame they last reported (-1: none yet)
var _remote_adv: Array = []  ## player -> how far ahead of us they think they are
var _sync_cool := 0


## The match's game object for the rollback session: steps the Duel or team battle
## and collects the events nobody has seen yet.
class _Tap:
	var duel  ## a DuelSim or a TeamSim: both step, snapshot, restore and digest
	var out: Array = []
	var _seen := {}  ## event key -> tick

	func _init(d) -> void:
		duel = d

	func step(inputs: PackedInt32Array) -> void:
		duel.step(inputs)
		var t: int = duel.sim.tick
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


## `p_size` players per side: 1 is a Duel between two machines (`p_slot` is the side);
## 2 or 3 is a team battle, `p_slot` one of TeamSim's slots (side 0 first).
var rules_id := ""


## What this match is, for a replay saved from the confirmed input log (F6).
func setup_dict() -> Dictionary:
	var ids: Array = []
	for t in teams:
		for id in t:
			ids.append(String(id))
	return {"kind": "team" if size > 1 else "duel", "ids": ids, "teams": teams.duplicate(true), "size": size,
		"rules": rules_id if size > 1 else DuelSim.rules_id_for(teams), "arena": arena_id, "mutators": {}, "mut_seed": 0}


## The confirmed inputs so far as replay rows (frames 0 up to the first gap).
func confirmed_rows() -> Array:
	var rows: Array = []
	var f := 0
	while input_log.has(f):
		rows.append(PackedInt32Array(input_log[f]))
		f += 1
	return rows


var arena_id := ArenaMap.DEFAULT


func _init(p_teams: Array, p_slot: int, p_delay: int, p_link: NetLink, p_id: int, p_size := 1, p_rules := "",
		p_arena := ArenaMap.DEFAULT) -> void:
	teams = p_teams
	rules_id = p_rules
	arena_id = p_arena if p_arena in ArenaMap.IDS else ArenaMap.DEFAULT
	size = clampi(p_size, 1, 3)
	players = size * 2
	local_slot = clampi(p_slot, 0, players - 1)
	input_delay = p_delay
	link = p_link
	id = p_id
	var menu_arena: String = MatchFactory.arena
	MatchFactory.arena = arena_id  # the map "start" named: every machine builds the same one
	if size > 1:
		team = TeamSim.new(teams, size, TeamSim.rules_by_id(p_rules))
		local_side = team.side_of(local_slot)
		_tap = _Tap.new(team)
	else:
		duel = DuelSim.new(teams, DuelSim.rules_for(teams))
		local_side = local_slot
		_tap = _Tap.new(duel)
	MatchFactory.arena = menu_arena  # the single player menu's choice is its own
	for p in players:
		relay_rtts.append(0.0)
		_remote_frame.append(-1)
		_remote_adv.append(0.0)
	session = RollbackSession.new(_tap, local_slot, input_delay, players)
	session.on_final = _on_final


## From now on the server's CPU plays `slot`.
func set_cpu(slot: int) -> void:
	if slot >= 0 and slot < players and slot != local_slot:
		cpu_slots[slot] = true


## The match being played (a DuelSim or a TeamSim).
func game_sim():
	return team if team != null else duel


## -2 undecided, -1 a draw, else the winning side.
func winner() -> int:
	return team.winner if team != null else duel.winner


## A message for this match from another machine (`p`: whose; a 1v1 may leave it out).
func receive(m: Dictionary) -> void:
	var p := int(m.get("p", 1 - local_slot if players == 2 else -1))
	if p < 0 or p >= players or p == local_slot:
		return
	match String(m.get("t", "")):
		"in":
			var inputs = m.get("inputs")
			if not (inputs is PackedInt32Array):
				return
			session.receive({"p": p, "first": int(m.get("first", 0)), "inputs": inputs,
				"ack": int(m.get("ack", -1))})
			if cpu_slots.has(p):
				return
			_remote_frame[p] = maxi(int(_remote_frame[p]), int(m.get("f", -1)))
			# How far ahead of this machine they think they are: from their per-player
			# list, or (a 1v1) their single figure.
			var advs = m.get("advs")
			if advs is PackedFloat32Array and local_slot < (advs as PackedFloat32Array).size():
				_remote_adv[p] = float((advs as PackedFloat32Array)[local_slot])
			else:
				_remote_adv[p] = float(m.get("adv", 0.0))
		"dg":
			var f := int(m.get("f", -1))
			_remote_digests["%d:%d" % [p, f]] = String(m.get("d", ""))
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
	var advs := PackedFloat32Array()
	advs.resize(players)
	var gap := 0.0
	for p in players:
		if p == local_slot or int(_remote_frame[p]) < 0 or cpu_slots.has(p):
			continue
		advs[p] = advantage_over(p)
		# Half the difference of the two views cancels out a lopsided round trip.
		gap = maxf(gap, (advs[p] - float(_remote_adv[p])) * 0.5)
	pkt["advs"] = advs
	link.send(pkt)
	if _sync_cool > 0:
		_sync_cool -= 1
	# Running ahead of another machine: hold this frame once, then wait a while.
	if _sync_cool == 0 and gap >= 1.0:
		_sync_cool = SYNC_COOLDOWN
		sync_waits += 1
		session.sync()
		return
	if session.advance():
		waiting_ticks = 0
	else:
		waiting_ticks += 1


## How many frames this machine is ahead of the furthest-behind other player
## (negative: behind everyone).
func frame_advantage() -> float:
	var most := -INF
	for p in players:
		if p != local_slot and int(_remote_frame[p]) >= 0 and not cpu_slots.has(p):
			most = maxf(most, advantage_over(p))
	return most if most > -INF else 0.0


## How many frames this machine is ahead of player `p`, using their last reported frame
## plus the time their packet spent on the way.
func advantage_over(p: int) -> float:
	if int(_remote_frame[p]) < 0:
		return 0.0
	var one_way := (link.rtt_ms() + float(relay_rtts[p])) * 0.5 * SimDefs.TICK_RATE / 1000.0
	return float(session.frame) - (float(_remote_frame[p]) + one_way)


func rollback_frames() -> int:
	return session.max_rollback_seen


func _on_final(f: int, inputs: PackedInt32Array, after: Dictionary) -> void:
	input_log[f] = Array(inputs)
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
	if not _digests.has(f):
		return
	var waiting := false
	for p in players:
		if p == local_slot or cpu_slots.has(p):
			continue
		var key := "%d:%d" % [p, f]
		if not _remote_digests.has(key):
			waiting = true
			continue
		if _digests[f] != _remote_digests[key]:
			if desync_frame < 0 or f < desync_frame:
				desync_frame = f
		else:
			digests_matched += 1
		_remote_digests.erase(key)
	if not waiting:
		_digests.erase(f)
	# Fingerprints that never came (a player left) don't pile up.
	for k in _digests.keys():
		if int(k) < f - DIGEST_EVERY * 4:
			_digests.erase(k)
	for k in _remote_digests.keys():
		if int(String(k).get_slice(":", 1)) < f - DIGEST_EVERY * 4:
			_remote_digests.erase(k)


## Everything needed to replay this match offline and find a desync: the teams and the
## confirmed inputs of every player, frame by frame.
## The round trip as Netplay last measured it, for the report.
var ping_ms := 0.0


func report() -> Dictionary:
	var frames: Array = []
	var f := 0
	while input_log.has(f):
		frames.append(input_log[f])
		f += 1
	return {"match": id, "arena": arena_id, "teams": teams, "size": size, "input_delay": input_delay, "local_side": local_side,
		"local_slot": local_slot, "cpu_slots": cpu_slots.keys(),
		"desync_frame": desync_frame, "digests_matched": digests_matched, "frames": frames,
		"digests": final_digests, "at_frame": session.frame, "rollbacks": session.rollbacks,
		"max_rollback": session.max_rollback_seen, "sync_waits": sync_waits, "ping_ms": ping_ms}
