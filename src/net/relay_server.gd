class_name RelayServer
extends RefCounted
## A dedicated server for online matches: players connect to it (with the game's
## ordinary Join), it groups them (two for a 1v1, four for a 2v2, six for a 3v3), relays
## each match's input streams between them, and referees every match with its own copy
## of the simulation (Referee).
##
##   Player                      Server                        Player
##   hello {version, data, team, room} -->      <-- hello
##   <-- wait, ping x5 / pong -->               <-- ping x5 / pong -->
##   ...two players in the same room are paired...
##   <-- start {side 0, teams, delay}           start {side 1, ...} -->
##   in / dg  ---------------------> relayed --------------------->  (and back)
##   rematch  ---------------------> relayed;  both asked: start again
##   bye      ---------------------> relayed;  the other player's session ends
##
## To a player the server looks like a host that gives them a side: Netplay needs only
## the `side` in "start" (and the opponent's round trip, `via`, for its time sync).
##
## Team battles: hello asks for a `size` (players per side). Quick match groups players
## who asked for the same size; in a room the first player to ask for a size sets it,
## and friends who join by code (size 0) take it. "start" adds each player's `slot` and
## everyone's round trips (`vias`); every input and fingerprint goes to all the others,
## tagged with the sender's slot (`p`). Players alternate sides as they're grouped.
##
## CPU players: a team battle that has waited `cpu_fill_ms` (Quick match) or
## `room_fill_ms` (a room) starts with CPUs in the empty slots, and a player who leaves
## a team battle is replaced by a CPU instead of ending it. The referee plays them (see
## Referee) and their inputs go to everyone, slot `p` like anyone's; "start" lists the
## CPU slots (`cpu`) and a takeover sends {"t": "cpu", "p": slot}.
## The rollback itself still runs on the players' machines; the server adds the hop
## through it to the round trip, which picks the input delay.
##
## It works on NetLinks, so tests drive it with in-memory links; the real server
## (DedicatedServer) feeds it the players of an EnetHub.

const PINGS := 5
## A ping that doesn't come back in this long is given up on.
const PING_TIMEOUT_MS := 2000
## How often each player hears the other's latest round trip.
const PATH_EVERY_MS := 2000
const MAX_ROOM_LENGTH := 32

enum State { HELLO, LOBBY, PLAYING }

var max_players := 32
## A player who connects but never says hello is dropped after this long.
var hello_timeout_ms := 10000
## Input delay for every match instead of picking one from the round trips.
var forced_delay := -1
## A team battle in Quick match starts with CPUs in the empty slots once its first
## player has waited this long (0: never); in a room, after `room_fill_ms`, since
## friends take a while to type the code.
var cpu_fill_ms := 20000
var room_fill_ms := 45000
## Picks the CPUs' fighters (tests seed it; the server leaves it random).
var rng := RandomNumberGenerator.new()
## How well the CPUs play (CpuController levels: 0 Easy, 1 Normal, 2 Hard, 3 Rage).
var cpu_level := 1
## Every log line goes here too (the server prints them).
var on_log := Callable()
var log_lines: Array = []

var clients := {}  ## id -> Client
var games: Array = []
var matches_started := 0
var matches_finished := 0
var _next_id := 1


class Client:
	var id := 0
	var link: NetLink
	var address := ""
	var state := 0  ## a RelayServer.State
	var team: Array = []
	var room := ""
	var since_ms := 0
	var rtt := 0.0  ## best measured round trip to the server, ms
	var rtts: Array = []
	var ping_n := 0
	var ping_usec := 0  ## when the outstanding ping went out (0: none)
	var game: Game = null
	var side := 0
	var slot := 0  ## input slot in the match (= side in a 1v1)
	var size := 1  ## players per side asked for (0: whatever the room is)
	var wait_shown := -1  ## the group size last told to this player
	var waiting_since := 0  ## when they started waiting for a match (ms)

	func label() -> String:
		return "player %d (%s)" % [id, ", ".join(PackedStringArray(team))] if not team.is_empty() \
			else "player %d" % id

	func pinged() -> bool:
		return rtts.size() >= RelayServer.PINGS or (rtts.size() > 0 and ping_usec == 0)


## Players grouped into a match; rematches keep the group and count `n` up.
class Game:
	var label := 0  ## the server's match number, for the log
	var players: Array = []  ## Clients by slot (side 0 first: [left..., right...]); null: a CPU
	var cpu_fighters := {}  ## slot -> fighter id, for the CPU-played slots
	var size := 1  ## players per side
	var n := 0
	var delay := 2
	var referee: Referee
	var rematch: Array = []
	var reported := false
	var path_ms := 0

	## The opponent in a 1v1.
	func other(c: Client) -> Client:
		return players[1 - c.slot]

	## Everyone else who's a player (not a CPU).
	func others(c: Client) -> Array:
		return players.filter(func(o): return o != null and o != c)

	func humans() -> Array:
		return players.filter(func(o): return o != null)


## A player connected: `link` is their connection.
func add_client(link: NetLink, address := "") -> Client:
	var c := Client.new()
	c.id = _next_id
	_next_id += 1
	c.link = link
	c.address = address
	c.since_ms = Time.get_ticks_msec()
	clients[c.id] = c
	_log("player %d connected%s" % [c.id, (" from " + address) if address != "" else ""])
	if clients.size() > max_players:
		_refuse(c, "full", "The server is full (%d players). Try again later." % max_players)
	return c


## Once per server loop: read every player's messages, pair players, referee matches.
func tick() -> void:
	var now := Time.get_ticks_msec()
	for c: Client in clients.values():
		if not clients.has(c.id):
			continue  # dropped while handling someone else's message
		for m in c.link.poll():
			if not clients.has(c.id):
				break
			_handle(c, m)
		if not clients.has(c.id):
			continue
		if c.link.status == NetLink.Status.CLOSED:
			_drop(c, "disconnected")
		elif c.state == State.HELLO and now - c.since_ms > hello_timeout_ms:
			_drop(c, "never said hello")
		elif c.state == State.LOBBY:
			_ping_step(c)
	_pair_waiting()
	for g: Game in games:
		_referee_step(g, now)
	for c: Client in clients.values():
		c.link.flush()


func player_count() -> int:
	return clients.size()


## Tells everyone the server is going away.
func shutdown() -> void:
	for c: Client in clients.values():
		c.link.send({"t": "bye", "why": "server"}, true)
		c.link.flush()
		c.link.close()
		c.game = null
	for g: Game in games:
		g.players.clear()
	clients.clear()
	games.clear()


# ------------------------------------------------------------------ messages

func _handle(c: Client, m: Dictionary) -> void:
	match String(m.get("t", "")):
		"hello":
			if c.state != State.HELLO:
				return
			if int(m.get("v", -1)) != Netplay.NET_VERSION or String(m.get("data", "")) != Netplay.data_hash():
				_refuse(c, "version", "The server runs a different version of the game. You both need the same build as the server.")
				return
			var team = m.get("team")
			if not Netplay.valid_team(team):
				_refuse(c, "fighter", "The server doesn't have the fighter you picked. It needs the same build as you.")
				return
			c.team = (team as Array).duplicate()
			c.room = String(m.get("room", "")).strip_edges().to_lower().left(MAX_ROOM_LENGTH)
			c.size = clampi(int(m.get("size", 1)), 0, 3)
			if c.room == "" and c.size == 0:
				c.size = 1
			c.state = State.LOBBY
			c.waiting_since = Time.get_ticks_msec()
			_log("%s is waiting%s" % [c.label(), (" in room '%s'" % c.room) if c.room != "" else ""])
			c.link.send({"t": "wait", "msg": _wait_text(c)}, true)
			_send_ping(c)
		"pong":
			var n := int(m.get("n", -1))
			if c.ping_usec != 0 and n == c.ping_n:
				c.rtts.append(float(Time.get_ticks_usec() - c.ping_usec) / 1000.0)
				c.ping_usec = 0
				c.rtt = float(c.rtts.min())
		"ping":
			c.link.send({"t": "pong", "n": m.get("n", 0)}, true)
		"in":
			var g := c.game
			if g == null or int(m.get("n", -1)) != g.n:
				return
			if not g.referee.add_inputs(c.slot, m):
				return
			# Passed on rebuilt from known fields only, never as the player sent it.
			var out := {"t": "in", "n": g.n, "p": c.slot, "first": int(m["first"]), "inputs": m["inputs"],
				"ack": int(m.get("ack", -1)), "f": int(m.get("f", -1)), "adv": float(m.get("adv", 0.0))}
			var advs = m.get("advs")
			if advs is PackedFloat32Array and (advs as PackedFloat32Array).size() == g.players.size():
				out["advs"] = advs
			for o: Client in g.others(c):
				o.link.send(out)
		"dg":
			var g := c.game
			if g == null or int(m.get("n", -1)) != g.n:
				return
			var f := int(m.get("f", -1))
			var d := String(m.get("d", "")).left(128)
			g.referee.add_digest(c.slot, f, d)
			for o: Client in g.others(c):
				o.link.send({"t": "dg", "n": g.n, "p": c.slot, "f": f, "d": d}, true)
		"rematch":
			var g := c.game
			if g == null or g.rematch[c.slot]:
				return
			g.rematch[c.slot] = true
			for o: Client in g.others(c):
				o.link.send({"t": "rematch", "p": c.slot}, true)
			if not (false in g.rematch):  # CPUs always say yes
				_report(g)
				_start(g)
		"bye":
			_drop(c, "left")


func _wait_text(c: Client, have := 1, need := 2) -> String:
	var where := (" in room '%s'" % c.room) if c.room != "" else ""
	if need <= 2:
		return "On the server%s. Waiting for an opponent..." % where
	var n := need / 2
	var t := "On the server%s. %d v %d: waiting for players (%d of %d here)" % [where, n, n, have, need]
	var fill := _fill_ms(c)
	if fill > 0:
		t += "; CPUs fill the rest after %d s" % roundi(fill / 1000.0)
	return t + "..."


func _fill_ms(c: Client) -> int:
	return room_fill_ms if c.room != "" else cpu_fill_ms


func _send_ping(c: Client) -> void:
	c.ping_n += 1
	c.ping_usec = Time.get_ticks_usec()
	c.link.send({"t": "ping", "n": c.ping_n}, true)


func _ping_step(c: Client) -> void:
	if c.ping_usec != 0:
		if float(Time.get_ticks_usec() - c.ping_usec) / 1000.0 > PING_TIMEOUT_MS:
			c.ping_usec = 0  # lost or very slow: carry on with what we have
			if c.rtts.is_empty():
				_send_ping(c)
	elif c.rtts.size() < PINGS:
		_send_ping(c)


# ------------------------------------------------------------------ matches

## Groups waiting players, oldest first: in Quick match by the size they asked for, in
## a room by the room's size (the first size anyone there asked for; a 1v1 if none).
## A group starts once it has both teams' worth of players.
func _pair_waiting() -> void:
	var groups := {}  ## key -> [Client], oldest first
	var room_size := {}
	var waiting: Array = clients.values().filter(func(c): return c.state == State.LOBBY)
	waiting.sort_custom(func(a, b): return a.id < b.id)
	for c: Client in waiting:
		if c.room != "" and c.size > 0 and not room_size.has(c.room):
			room_size[c.room] = c.size
	for c: Client in waiting:
		var size: int = c.size if c.room == "" else int(room_size.get(c.room, 1))
		var key := "%s|%d" % [c.room, size]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(c)
	for key in groups:
		var size := int(String(key).get_slice("|", 1))
		var need := size * 2
		var ready: Array = (groups[key] as Array).filter(func(c): return c.pinged())
		while ready.size() >= need:
			_begin_game(ready.slice(0, need), size)
			ready = ready.slice(need)
		# Waited long enough for a team battle: CPUs take the empty slots.
		if need > 2 and not ready.is_empty():
			var fill := _fill_ms(ready[0])
			if fill > 0 and Time.get_ticks_msec() - (ready[0] as Client).waiting_since >= fill:
				_begin_game(ready, size)
				ready = []
		for c: Client in groups[key]:
			if c.state == State.LOBBY and need > 2 and c.wait_shown != (groups[key] as Array).size():
				c.wait_shown = (groups[key] as Array).size()
				c.link.send({"t": "wait", "msg": _wait_text(c, mini(c.wait_shown, need), need)}, true)


## `group`: the players in the order they arrived; they alternate sides, so in a room
## the first two (the friend who made it and the next to join) face each other. Fewer
## than a full match: CPUs take the slots left over (fighters nobody picked, first).
func _begin_game(group: Array, size: int) -> void:
	var g := Game.new()
	g.size = size
	g.players.resize(size * 2)
	var used := {}
	for k in group.size():
		var c: Client = group[k]
		c.side = k % 2
		c.slot = c.side * size + k / 2
		g.players[c.slot] = c
		c.game = g
		c.state = State.PLAYING
		used[String(c.team[0])] = true
	var pool: Array = MatchFactory.FIGHTERS.filter(func(f): return not used.has(f))
	if pool.is_empty():
		pool = MatchFactory.FIGHTERS.duplicate()
	for i in range(pool.size() - 1, 0, -1):  # shuffled: the server's choice, outside any match
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for slot in g.players.size():
		if g.players[slot] == null:
			g.cpu_fighters[slot] = String(pool[g.cpu_fighters.size() % pool.size()])
	games.append(g)
	_start(g)


func _start(g: Game) -> void:
	var rtts: Array = []
	for c in g.players:
		if c == null:
			rtts.append(0.0)  # a CPU, on the server itself
			continue
		if (c as Client).link.rtt_ms() > 0.0:
			c.rtt = (c as Client).link.rtt_ms()
		rtts.append(c.rtt)
	# The slowest path between two players picks everyone's input delay. A CPU's inputs
	# go out from the server once the players' have arrived, so it counts as one more
	# hop from there.
	var sorted := rtts.duplicate()
	sorted.sort()
	var path: float = float(sorted[-1]) + float(sorted[-2])
	if not g.cpu_fighters.is_empty():
		path = maxf(path, float(sorted[-1]) * 2.0)
	g.n += 1
	g.delay = forced_delay if forced_delay >= 0 else Netplay.pick_delay(path)
	g.rematch = []
	for c in g.players:
		g.rematch.append(c == null)  # CPUs always want a rematch
	g.reported = false
	var teams := [[], []]
	if g.size == 1:
		teams = [(g.players[0] as Client).team.duplicate(), (g.players[1] as Client).team.duplicate()]
	else:
		for slot in g.players.size():
			var c = g.players[slot]
			var fighter: String = String(g.cpu_fighters[slot]) if c == null else String(c.team[0])
			(teams[slot / g.size] as Array).append(fighter)  # one fighter each
	g.referee = Referee.new(teams, g.delay, g.size)
	for slot in g.cpu_fighters:
		g.referee.add_cpu(int(slot), cpu_level, g.label * 31 + int(slot) * 7 + g.n)
	g.path_ms = Time.get_ticks_msec()
	matches_started += 1
	g.label = matches_started
	var cpu_slots: Array = g.cpu_fighters.keys()
	cpu_slots.sort()
	for c: Client in g.humans():
		var worst := 0.0
		for o: Client in g.others(c):
			worst = maxf(worst, o.rtt)
		var m := {"t": "start", "n": g.n, "teams": teams, "delay": g.delay, "ping": c.rtt + worst,
			"side": c.side, "via": worst}
		if g.size > 1:
			m["slot"] = c.slot
			m["size"] = g.size
			m["vias"] = rtts
			if not cpu_slots.is_empty():
				m["cpu"] = cpu_slots
		c.link.send(m, true)
	var sides := ["", ""]
	for side in 2:
		var names := PackedStringArray()
		for slot in range(side * g.size, (side + 1) * g.size):
			var c = g.players[slot]
			names.append("CPU (%s)" % g.cpu_fighters[slot] if c == null else (c as Client).label())
		sides[side] = " + ".join(names)
	_log("match %d started%s: %s vs %s, round trip %d ms, input delay %d" % [g.label,
		" (rematch)" if g.n > 1 else "", sides[0], sides[1], roundi(path), g.delay])


func _referee_step(g: Game, now: int) -> void:
	g.referee.advance()
	_send_cpu_inputs(g)
	if g.referee.winner != -2 and not g.reported:
		_report(g)
	if now - g.path_ms >= PATH_EVERY_MS:
		g.path_ms = now
		if g.size == 1:
			for c: Client in g.players:
				var r := g.other(c).link.rtt_ms()
				if r > 0.0:
					c.link.send({"t": "path", "rtt": r}, true)
		else:
			var rtts: Array = []
			for c in g.players:
				if c == null:
					rtts.append(0.0)
				else:
					rtts.append((c as Client).link.rtt_ms() if (c as Client).link.rtt_ms() > 0.0 else c.rtt)
			for c: Client in g.humans():
				c.link.send({"t": "path", "rtts": rtts}, true)


## The CPUs' new inputs, to every player (reliably: a CPU never resends). Each copy's
## `ack` says how far the server has that player's own inputs, as a player's would.
func _send_cpu_inputs(g: Game) -> void:
	var out := g.referee.take_cpu_inputs()
	for slot in out:
		_send_inputs(g, int(slot), out[slot])


func _send_inputs(g: Game, slot: int, pkt: Dictionary) -> void:
	if (pkt["inputs"] as PackedInt32Array).is_empty():
		return
	for c: Client in g.humans():
		c.link.send({"t": "in", "n": g.n, "p": slot, "first": int(pkt["first"]), "inputs": pkt["inputs"],
			"ack": g.referee.have_upto(c.slot), "f": -1}, true)


## Logs how the match went, once.
func _report(g: Game) -> void:
	if g.reported:
		return
	g.reported = true
	var r := g.referee
	var how := ""
	if r.winner >= 0 and g.size == 1:
		matches_finished += 1
		how = "%s won" % (g.players[r.winner] as Client).label()
	elif r.winner >= 0:
		matches_finished += 1
		how = "the %s team won" % ("left" if r.winner == 0 else "right")
	elif r.winner == -1:
		matches_finished += 1
		how = "a draw"
	else:
		how = "unfinished at frame %d" % r.frame
	_log("match %d over: %s (%d fingerprints checked)" % [g.label, how, r.checked])
	for side in r.desync.size():
		if r.desync[side] >= 0 and g.players[side] != null:
			_log("match %d: %s's game went out of sync at frame %d (a bug: their report is in their desyncs folder)"
				% [g.label, (g.players[side] as Client).label(), r.desync[side]])


func _refuse(c: Client, why: String, msg: String) -> void:
	c.link.send({"t": "reject", "why": why, "msg": msg}, true)
	_drop(c, "refused: " + why)


## Removes a player. In a team battle with other players still in it, a CPU takes
## their place; otherwise everyone else in their match is told, and their sessions end.
func _drop(c: Client, why: String) -> void:
	if not clients.has(c.id):
		return
	clients.erase(c.id)
	_log("%s %s" % [c.label(), why])
	var g := c.game
	if g != null and g.size > 1 and not g.others(c).is_empty():
		_cpu_takes_over(g, c)
	elif g != null:
		_report(g)
		games.erase(g)
		for o: Client in g.others(c):
			o.game = null
			if clients.has(o.id):
				o.link.send({"t": "bye", "why": "opponent" if g.size == 1 else "player"}, true)
				o.link.flush()
				clients.erase(o.id)
				o.link.close()
				_log("%s's match ended: %s %s" % [o.label(), "the opponent" if g.size == 1 else c.label(), why])
		g.players.clear()  # players and game point at each other: break the loop so both are freed
	c.game = null
	c.link.flush()
	c.link.close()


## A CPU plays `c`'s slot from the first frame nobody has their input for. Everyone
## first gets every input of theirs the server knows (some may have missed the last
## few), then the CPU's, like anyone's.
func _cpu_takes_over(g: Game, c: Client) -> void:
	var slot := c.slot
	g.players[slot] = null
	g.cpu_fighters[slot] = String(c.team[0])
	g.rematch[slot] = true
	g.referee.add_cpu(slot, cpu_level, g.label * 31 + slot * 7 + g.n)
	for o: Client in g.others(c):
		o.link.send({"t": "cpu", "n": g.n, "p": slot}, true)
	for pkt in g.referee.inputs_since(slot, maxi(0, g.referee.frame - Referee.HISTORY)):
		_send_inputs(g, slot, pkt)
	_log("match %d: a CPU plays %s's slot" % [g.label, c.label()])
	c.game = null
	if not (false in g.rematch):
		_report(g)
		_start(g)


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 200:
		log_lines.pop_front()
	if on_log.is_valid():
		on_log.call(s)
