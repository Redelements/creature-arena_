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
##
## Ready check: once the server has a group for this player it says "found"
## (`match_found`), and the match only starts after everyone answers "ready". The game
## shows a Match found screen and calls accept_match() (or decline_match()); with
## `auto_ready` (tests, command-line joins) the answer goes back at once. Time running
## out, or someone leaving, puts the players who accepted back to waiting ("wait" with
## `requeue`); someone who never accepted is refused with a reason.
##
## Team battles (2v2, 3v3) only run through a server: hello asks for a `size` (players
## per side; 0 when joining a friend's room takes the room's), and "start" gives this
## player's `slot` among the 4 or 6 and the `size`; the inputs of every player then
## pass through the server to everyone else, each tagged with whose (`p`). Slots the
## server's CPU plays are listed in "start" (`cpu`), or come later as "cpu" when a
## player leaves; their inputs arrive like anyone's.

const NET_VERSION := 7  ## 7: team rules and tag Duels online; 6: the server's ready check; 5: team battles (slots, sizes); 4: 360 move angle
const DEFAULT_PORT := 7777
const PINGS := 5
## A precise ping (a real link) blocks the host this long at most waiting for the pong.
const PING_WAIT_MS := 400
## During a match, both sides keep pinging this often (ticks) for a live figure.
const LIVE_PING_EVERY := 60
const LIVE_PING_KEEP := 5  ## the live ping is the best of this many recent samples
const ATTENTIVE_WAIT_MS := 12  ## the guest waits on the socket this long a tick while being pinged
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
## Players per side to ask a server for: 1 (a 1v1), 2 or 3; 0 = whatever the room is.
var team_size := 1
## The rules a team battle plays (TeamSim.RULE_IDS; "" the plain battle): asked for in
## hello, decided by the host or the server, carried in "start". A tag Duel is simply a
## team of three fighters per player at size 1.
var rules_id := ""
## Spectating: this machine watches a match on the server (a room's, or the newest)
## with a Referee of its own stepping only on confirmed inputs, never predicting.
var watching := false
var watch: Referee = null
## The arena the host (or a room's maker) asks for; the one in "start" is what plays.
var arena_id := ArenaMap.DEFAULT
## This player's slot in the match (its side in a 1v1).
var local_slot := 0
## Dedicated servers pair players who give the same room ("" for anyone).
var room := ""
## True once the other end turned out to be a dedicated server.
var via_server := false

## The server found a match and is waiting for everyone to accept it.
var match_found := false
## Answer the ready check straight away (the game sets this off to ask the player).
var auto_ready := true
var accepted := false
var declined := false
## About the match found: players per side, how many players it has (the rest are
## CPUs), the seconds to accept, and how many have accepted so far.
var found_size := 1
var found_players := 2
var found_need := 2
var found_secs := 15.0
var accepted_have := 0
var _found_ms := 0

var rematch_local := false
var rematch_remote := false  ## another player asked
var rematch_asked := {}  ## who else asked (by slot)

var _match_count := 0
var _t := 0
var _pings_sent := {}  ## n -> usec
var _rtts: Array = []
var _next_ping := 0
var _live_rtts: Array = []
var _live_n := 1000
## How long a precise ping may wait on the socket; 0 reads pongs a tick at a time (the
## tests that run both ends in one loop set that: the other end can't answer meanwhile).
var ping_wait_ms := PING_WAIT_MS
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


## Watches a match on a server: the room's, or whatever is on.
func spectate(address: String, port: int, p_room: String, p_link: NetLink = null) -> bool:
	watching = true
	room = p_room
	return join(address, port, [MatchFactory.FIGHTERS[0]], p_link)


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


## Reads whatever has arrived and acts on it. Once a tick from tick(); on a real link
## the game also calls it every rendered frame, so the other player's inputs reach the
## rollback session the moment they land instead of waiting for the next tick.
func pump() -> void:
	if link == null or phase == Phase.IDLE or phase == Phase.ENDED:
		return
	for m in link.poll():
		_handle(m)


## Once per frame. `local_bits` is this player's input (used only during a match).
func tick(local_bits: int) -> void:
	if link == null or phase == Phase.IDLE or phase == Phase.ENDED:
		return
	_t += 1
	pump()
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
				link.send({"t": "hello", "v": NET_VERSION, "data": data_hash(), "team": my_team, "room": room,
					"size": team_size, "rules": rules_id, "watch": watching, "arena": arena_id}, true)
				phase = Phase.HANDSHAKE
				status = "Connected. Setting up the match..."
			elif _t > CONNECT_TIMEOUT_TICKS:
				_fail(_no_answer())
				return
		Phase.HANDSHAKE:
			if hosting:
				_ping_step()
			elif link.realtime and ping_wait_ms > 0:
				# Being pinged: wait on the socket for most of this tick (nothing else is
				# moving yet) so each ping is answered within a millisecond of arriving.
				for m in link.poll(ATTENTIVE_WAIT_MS):
					_handle(m)
		Phase.PLAYING:
			if watch != null:
				watch.advance()
			else:
				game.tick(local_bits)
			_live_ping_step()
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


## Accept the match the server found (the ready check).
func accept_match() -> void:
	if not match_found or accepted or link == null:
		return
	accepted = true
	link.send({"t": "ready"}, true)
	link.flush()
	status = "Accepted. Waiting for everyone..."


## Turn the match down: leaves the server, so searching again starts afresh.
func decline_match() -> void:
	leave()
	declined = true
	match_found = false
	error = "You declined the match"
	status = error


## Seconds left to accept the match found (0 when none is waiting).
func seconds_left() -> float:
	if not match_found:
		return 0.0
	return maxf(0.0, found_secs - float(Time.get_ticks_msec() - _found_ms) / 1000.0)


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


func is_watching() -> bool:
	return phase == Phase.PLAYING and watch != null


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
				match_found = false  # back to searching (or still searching)
				accepted = false
				status = String(m.get("msg", "On the server. Waiting for an opponent..."))
		"found":
			if hosting or phase == Phase.PLAYING:
				return
			via_server = true
			match_found = true
			accepted = false
			found_size = clampi(int(m.get("size", 1)), 1, 3)
			found_need = clampi(int(m.get("need", found_size * 2)), 2, 6)
			found_players = clampi(int(m.get("players", found_need)), 1, found_need)
			found_secs = clampf(float(m.get("secs", 15.0)), 1.0, 120.0)
			accepted_have = 0
			_found_ms = Time.get_ticks_msec()
			status = "Match found!"
			if auto_ready:
				accept_match()
		"accepted":
			if match_found:
				accepted_have = clampi(int(m.get("have", 0)), 0, found_players)
				if accepted:
					status = "Accepted. Waiting for everyone (%d of %d)..." % [accepted_have, found_players]
		"path":
			if game != null:
				_set_paths(m)
		"ping":
			link.send({"t": "pong", "n": m.get("n", 0)}, true)
			link.flush()  # straight back out, not at the end of the tick
		"pong":
			var n := int(m.get("n", -1))
			if _pings_sent.has(n):
				var ms := float(Time.get_ticks_usec() - int(_pings_sent[n])) / 1000.0
				_pings_sent.erase(n)
				if n >= 1000:  # a live ping during the match: the best of the recent few
					_live_rtts.append(ms)
					while _live_rtts.size() > LIVE_PING_KEEP:
						_live_rtts.pop_front()
					ping_ms = _live_rtts.min()
					if game != null:
						game.ping_ms = ping_ms
				else:
					_rtts.append(ms)
		"start":
			if hosting:
				return
			if bool(m.get("watch", false)):
				_start_watching(m)
				return
			var teams = m.get("teams")
			var size := clampi(int(m.get("size", 1)), 1, 3)
			if not (teams is Array) or (teams as Array).size() != 2 or not _valid_team(teams[0]) \
					or not _valid_team(teams[1]) or (size > 1 and ((teams[0] as Array).size() != size
					or (teams[1] as Array).size() != size)):
				_fail("Bad match setup from the host")
				return
			var slot := 1
			if m.has("side"):  # from a dedicated server, which picks the sides
				via_server = true
				slot = clampi(int(m.get("slot", m["side"])), 0, size * 2 - 1)
			ping_ms = float(m.get("ping", 0.0))
			var rules := String(m.get("rules", ""))
			var arena := String(m.get("arena", ArenaMap.DEFAULT))
			if not (rules in TeamSim.RULE_IDS) or not (arena in ArenaMap.IDS):
				_fail("Bad match setup from the host")
				return
			rules_id = rules
			arena_id = arena
			_begin(int(m.get("n", 0)), teams, int(m.get("delay", 2)), slot, size, rules, arena)
			their_team = teams[1 - local_side]
			var cpu = m.get("cpu", [])
			if cpu is Array:
				for k in cpu:
					game.set_cpu(int(k))
			if m.has("vias"):
				_set_paths({"rtts": m["vias"]})
			else:
				game.relay_rtt_ms = float(m.get("via", 0.0))
		"cpu":  # a player left the team battle: the server's CPU plays their slot now
			if game != null and int(m.get("n", -1)) == game.id:
				game.set_cpu(int(m.get("p", -1)))
		"rematch":
			rematch_remote = true
			rematch_asked[int(m.get("p", 1 - local_slot))] = true
		"bye":
			match String(m.get("why", "")):
				"server":
					_fail("The server shut down")
				"player":
					_fail("A player left the match")
				_:
					_fail("The other player left")
		"in", "dg":
			if watch != null:
				if String(m.get("t", "")) == "in" and int(m.get("n", -1)) == _watch_n:
					watch.add_inputs(clampi(int(m.get("p", 0)), 0, watch.players - 1), m)
			elif game != null and int(m.get("n", -1)) == game.id:
				game.receive(m)


var _watch_n := 0


## The server put this spectator on a match: build a referee's copy of it and feed it
## everything stepped so far.
func _start_watching(m: Dictionary) -> void:
	var teams = m.get("teams")
	var size := clampi(int(m.get("size", 1)), 1, 3)
	var rules := String(m.get("rules", ""))
	var arena := String(m.get("arena", ArenaMap.DEFAULT))
	if not (teams is Array) or (teams as Array).size() != 2 or not _valid_team(teams[0]) \
			or not _valid_team(teams[1]) or not (rules in TeamSim.RULE_IDS) or not (arena in ArenaMap.IDS):
		_fail("Bad match setup from the server")
		return
	via_server = true
	match_found = false
	_watch_n = int(m.get("n", 0))
	arena_id = arena
	watch = Referee.new(teams, int(m.get("delay", 2)), size, rules, arena)
	var rows = m.get("log", [])
	if rows is Array:
		watch.feed_log(rows)
	phase = Phase.PLAYING
	status = "Watching"


## Host: measure the round trip with a few pings, then start the match. On a real link
## each ping is timed precisely: the host waits on the socket for the pong (one ping a
## tick, PING_WAIT_MS at most), so the figure is the network's, not rounded up by the
## frames a reply would otherwise sit unread.
func _ping_step() -> void:
	if their_team.is_empty():
		return  # still waiting for hello
	var sent := PINGS - _pings_sent.size() - _rtts.size()
	if sent > 0 and _t >= _next_ping:
		var n := _rtts.size() + _pings_sent.size()
		_pings_sent[n] = Time.get_ticks_usec()
		link.send({"t": "ping", "n": n}, true)
		_next_ping = _t + 3
		if link.realtime and ping_wait_ms > 0:
			link.flush()
			var until := Time.get_ticks_usec() + ping_wait_ms * 1000
			while _pings_sent.has(n) and Time.get_ticks_usec() < until and phase == Phase.HANDSHAKE:
				for m in link.poll(1):
					_handle(m)
			_next_ping = _t + 1
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
	link.send({"t": "start", "n": _match_count, "teams": teams, "delay": delay, "ping": ping_ms,
		"rules": rules_id, "arena": arena_id}, true)
	_begin(_match_count, teams, delay, -1, 1, rules_id, arena_id)


## A host's own matches: it plays side 0.
func _begin(n: int, teams: Array, delay: int, slot := -1, size := 1, rules := "", arena := ArenaMap.DEFAULT) -> void:
	if slot < 0:
		slot = local_side
	match_found = false
	game = OnlineMatch.new(teams, slot, delay, link, n, size, rules, arena)
	game.ping_ms = ping_ms
	local_slot = game.local_slot
	local_side = game.local_side
	rematch_local = false
	rematch_remote = false
	rematch_asked = {}
	phase = Phase.PLAYING
	status = ""


## Each player's round trip to the server ({"rtts": [...]}, one per slot), or the
## opponent's in a 1v1 ({"rtt": ms}).
func _set_paths(m: Dictionary) -> void:
	var rtts = m.get("rtts")
	if rtts is Array or rtts is PackedFloat32Array:
		for p in mini((rtts as Array).size() if rtts is Array else (rtts as PackedFloat32Array).size(), game.players):
			game.relay_rtts[p] = clampf(float(rtts[p]), 0.0, 5000.0)
	elif m.has("rtt"):
		game.relay_rtt_ms = clampf(float(m["rtt"]), 0.0, 5000.0)


## Input delay from the measured round trip: just enough that most inputs arrive
## before they're needed, so rollbacks stay small. Fighting games use 1-3 frames.
## The input delay for a round trip: as low as rollback can comfortably absorb. One
## frame up to 100 ms (a 50 ms trip is 3 frames each way; rollback re-simulates the two
## frames a late input missed, which costs well under a millisecond), two up to 170, three
## beyond: the whole of a 200 ms trip would need more than the 8 frames rollback keeps.
static func pick_delay(rtt_ms: float) -> int:
	if rtt_ms < 100.0:
		return 1
	if rtt_ms < 170.0:
		return 2
	return 3


## During a match, a ping every second (both sides, so each shows its own round trip);
## the pong is read by the next pump, within a rendered frame on a real link.
func _live_ping_step() -> void:
	if _t % LIVE_PING_EVERY != 0:
		return
	_live_n += 1
	_pings_sent[_live_n] = Time.get_ticks_usec()
	link.send({"t": "ping", "n": _live_n}, true)
	for k in _pings_sent.keys():  # a lost pong doesn't pile up
		if k >= 1000 and k < _live_n - 2:
			_pings_sent.erase(k)


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
	match_found = false
	if link != null and link.status != NetLink.Status.CLOSED:
		link.close()
	return false


## A fingerprint of the game data both machines must share: every fighter's file and
## the Duel rules. Different data would make the two simulations disagree.
static func data_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("v%d" % NET_VERSION).to_utf8_buffer())
	var paths: Array = [DuelSim.RULES_PATH, TeamSim.RULES_PATH, TeamSim.DEATHMATCH_PATH, TeamSim.SINKHOLE_PATH,
		TeamSim.CRATER_PATH, TeamSim.SHOWTIME_PATH, BrawlSim.RULES_PATH, Daily.MUTATORS_PATH]
	for id in MatchFactory.FIGHTERS:
		paths.append(MatchFactory.CREATURE_DIR + id + ".json")
	for id in ArenaMap.IDS:
		paths.append(ArenaMap.DIR + id + ".json")
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
