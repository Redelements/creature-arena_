class_name Netplay
extends RefCounted
## An online session between two machines: connect, agree on the match, play it with
## rollback, rematch. The game calls tick() once per frame and shows `game.duel`.
##
##   Host                                   Joiner
##   host(port)  ............................ join(address, port)
##            <-------------------------------  hello  {version, data hash, team}
##   ping x5  ------------------------------->  pong   (the host measures the round trip)
##   start {teams, input delay, match id} --->
##   ...both play the match: input stream (unreliable), state fingerprints (reliable)...
##   rematch <------------------------------->  rematch   (both asked: the host starts again)
##   bye     (either side, on leaving)
##
## The host is side 0 (left), the joiner side 1. Both builds must have the same game
## data (creature files and Duel rules), or the simulations would disagree: hello
## carries a hash of it, and a mismatch is refused with a clear message.
##
## Joining a dedicated server (RelayServer) is the same Join: the server answers like a
## host, except that it says "wait" until it has paired this player with another, and
## its "start" gives this player's `side` and the opponent's round trip to the server.
## A `room` in hello pairs players who typed the same one.

const NET_VERSION := 4  ## 4: 360 move angle in each input, bigger arena; 3: aim angle + strafe
const DEFAULT_PORT := 7777
const PINGS := 5
## Give up on a join that hasn't connected after this long.
const CONNECT_TIMEOUT_TICKS := 10 * 60

enum Phase { IDLE, WAITING, CONNECTING, HANDSHAKE, PLAYING, ENDED }

var phase: Phase = Phase.IDLE
var link: NetLink
var hosting := false
var my_team: Array = []
var their_team: Array = []
var local_side := 0
var game: OnlineMatch = null
## A short line for the player about what's happening.
var status := ""
## Why the session ended, if it did badly.
var error := ""
var ping_ms := 0.0
## Input delay to use instead of picking one from the ping (--net-delay).
var forced_delay := -1
var team_size := 1
## Dedicated servers pair players who give the same room ("" for anyone).
var room := ""
## True once the other end turned out to be a dedicated server.
var via_server := false

var rematch_local := false
var rematch_remote := false

var _match_count := 0
var _t := 0
var _pings_sent := {}  ## n -> usec
var _rtts: Array = []
var _next_ping := 0
var _address := ""


## Waits for another player to connect. Returns false (with `error`) if the port is busy.
func host(port: int, team: Array, p_link: NetLink = null) -> bool:
	hosting = true
	local_side = 0
	my_team = team.duplicate()
	if p_link != null:
		link = p_link
	else:
		var e := EnetLink.new()
		if e.host(port) != OK:
			return _fail(e.error)
		link = e
	phase = Phase.WAITING
	status = "Waiting for a player on UDP port %d" % port
	return true


func join(address: String, port: int, team: Array, p_link: NetLink = null) -> bool:
	hosting = false
	local_side = 1
	my_team = team.duplicate()
	_address = "%s:%d" % [address, port]
	if p_link != null:
		link = p_link
	else:
		var e := EnetLink.new()
		if e.join(address, port) != OK:
			return _fail(e.error)
		link = e
	phase = Phase.CONNECTING
	status = "Connecting to %s" % _address
	return true


## Once per frame. `local_bits` is this player's input (used only during a match).
func tick(local_bits: int) -> void:
	if link == null or phase == Phase.IDLE or phase == Phase.ENDED:
		return
	_t += 1
	var msgs := link.poll()
	for m in msgs:
		_handle(m)
	if phase == Phase.ENDED:
		return
	if link.status == NetLink.Status.CLOSED:
		if phase == Phase.CONNECTING:
			_fail(_no_answer())  # never got through: not "the other player left"
		else:
			_fail(link.error if link.error != "" else "Connection lost")
		return
	match phase:
		Phase.CONNECTING:
			if link.status == NetLink.Status.CONNECTED:
				link.send({"t": "hello", "v": NET_VERSION, "data": data_hash(), "team": my_team, "room": room}, true)
				phase = Phase.HANDSHAKE
				status = "Connected. Setting up the match..."
			elif _t > CONNECT_TIMEOUT_TICKS:
				_fail(_no_answer())
				return
		Phase.HANDSHAKE:
			if hosting:
				_ping_step()
		Phase.PLAYING:
			game.tick(local_bits)
			if hosting and rematch_local and rematch_remote:
				_start_match()
	link.flush()


## Ask for a rematch; it starts when both players have asked.
func request_rematch() -> void:
	if phase != Phase.PLAYING or rematch_local:
		return
	rematch_local = true
	link.send({"t": "rematch"}, true)
	link.flush()


## Leave politely: the other player is told straight away.
func leave() -> void:
	if link != null and link.status == NetLink.Status.CONNECTED:
		link.send({"t": "bye"}, true)
		link.flush()
	if link != null:
		link.close()
	phase = Phase.ENDED
	status = "Left the match"


func is_playing() -> bool:
	return phase == Phase.PLAYING and game != null


# ------------------------------------------------------------------ messages

func _handle(m: Dictionary) -> void:
	var kind := String(m.get("t", ""))
	match kind:
		"hello":
			if not hosting or phase == Phase.PLAYING:
				return
			if int(m.get("v", -1)) != NET_VERSION or String(m.get("data", "")) != data_hash():
				link.send({"t": "reject", "why": "version"}, true)
				link.flush()
				_fail("The other player has a different version of the game. Both need the same build.")
				return
			var team = m.get("team")
			if not _valid_team(team):
				_fail("The other player picked a fighter this build doesn't have.")
				return
			their_team = team
			phase = Phase.HANDSHAKE
			status = "Player connected. Measuring the connection..."
			_next_ping = _t
		"reject":
			_fail(String(m.get("msg", "The host has a different version of the game. Both need the same build.")))
		"wait":
			if not hosting:
				via_server = true
				status = String(m.get("msg", "On the server. Waiting for an opponent..."))
		"path":
			if game != null:
				game.relay_rtt_ms = float(m.get("rtt", 0.0))
		"ping":
			link.send({"t": "pong", "n": m.get("n", 0)}, true)
		"pong":
			var n := int(m.get("n", -1))
			if _pings_sent.has(n):
				_rtts.append(float(Time.get_ticks_usec() - int(_pings_sent[n])) / 1000.0)
				_pings_sent.erase(n)
		"start":
			if hosting:
				return
			var teams = m.get("teams")
			if not (teams is Array) or (teams as Array).size() != 2 or not _valid_team(teams[0]) \
					or not _valid_team(teams[1]):
				_fail("Bad match setup from the host")
				return
			if m.has("side"):  # from a dedicated server, which picks the sides
				via_server = true
				local_side = clampi(int(m["side"]), 0, 1)
			their_team = teams[1 - local_side]
			ping_ms = float(m.get("ping", 0.0))
			_begin(int(m.get("n", 0)), teams, int(m.get("delay", 2)))
			game.relay_rtt_ms = float(m.get("via", 0.0))
		"rematch":
			rematch_remote = true
		"bye":
			_fail("The server shut down" if String(m.get("why", "")) == "server" else "The other player left")
		"in", "dg":
			if game != null and int(m.get("n", -1)) == game.id:
				game.receive(m)


## Host: measure the round trip with a few pings, then start the match.
func _ping_step() -> void:
	if their_team.is_empty():
		return  # still waiting for hello
	var sent := PINGS - _pings_sent.size() - _rtts.size()
	if sent > 0 and _t >= _next_ping:
		var n := _rtts.size() + _pings_sent.size()
		_pings_sent[n] = Time.get_ticks_usec()
		link.send({"t": "ping", "n": n}, true)
		_next_ping = _t + 3
	if _rtts.size() >= PINGS or (_rtts.size() > 0 and _t - _next_ping > 120):
		# The best of the samples: the others include frames spent waiting to be read.
		var best := float(_rtts[0])
		for r in _rtts:
			best = minf(best, float(r))
		ping_ms = best
		_start_match()


func _start_match() -> void:
	_match_count += 1
	var teams := [my_team.duplicate(), their_team.duplicate()]
	var delay := forced_delay if forced_delay >= 0 else pick_delay(ping_ms)
	link.send({"t": "start", "n": _match_count, "teams": teams, "delay": delay, "ping": ping_ms}, true)
	_begin(_match_count, teams, delay)


func _begin(n: int, teams: Array, delay: int) -> void:
	game = OnlineMatch.new(teams, local_side, delay, link, n)
	rematch_local = false
	rematch_remote = false
	phase = Phase.PLAYING
	status = ""


## Input delay from the measured round trip: just enough that most inputs arrive
## before they're needed, so rollbacks stay small. Fighting games use 1-3 frames.
static func pick_delay(rtt_ms: float) -> int:
	if rtt_ms < 60.0:
		return 1
	if rtt_ms < 130.0:
		return 2
	return 3


func _valid_team(team) -> bool:
	return valid_team(team)


static func valid_team(team) -> bool:
	if not (team is Array) or (team as Array).is_empty() or (team as Array).size() > 3:
		return false
	for id in team:
		if not (String(id) in MatchFactory.FIGHTERS):
			return false
	return true


func _no_answer() -> String:
	return "No answer from %s. Check the address, and that its UDP port is open." % _address


func _fail(why: String) -> bool:
	error = why
	status = why
	phase = Phase.ENDED
	if link != null and link.status != NetLink.Status.CLOSED:
		link.close()
	return false


## A fingerprint of the game data both machines must share: every fighter's file and
## the Duel rules. Different data would make the two simulations disagree.
static func data_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("v%d" % NET_VERSION).to_utf8_buffer())
	var paths: Array = [DuelSim.RULES_PATH]
	for id in MatchFactory.FIGHTERS:
		paths.append(MatchFactory.CREATURE_DIR + id + ".json")
	for p in paths:
		ctx.update(FileAccess.get_file_as_string(p).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


## This computer's addresses another player could connect to (LAN and virtual-LAN
## addresses such as Tailscale's 100.x; the public address is the router's).
static func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		out.append(a)
	return out
