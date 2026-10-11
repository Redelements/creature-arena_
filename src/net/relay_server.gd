class_name RelayServer
extends RefCounted
## A dedicated server for online Duels: players connect to it (with the game's ordinary
## Join), it pairs them two by two, relays each match's input stream between them, and
## referees every match with its own copy of the simulation (Referee).
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

	func label() -> String:
		return "player %d (%s)" % [id, ", ".join(PackedStringArray(team))] if not team.is_empty() \
			else "player %d" % id

	func pinged() -> bool:
		return rtts.size() >= RelayServer.PINGS or (rtts.size() > 0 and ping_usec == 0)


## Two players paired; rematches keep the pair and count `n` up.
class Game:
	var label := 0  ## the server's match number, for the log
	var players: Array = []  ## [Client side 0, Client side 1]
	var n := 0
	var delay := 2
	var referee: Referee
	var rematch := [false, false]
	var reported := false
	var path_ms := 0

	func other(c: Client) -> Client:
		return players[1 - c.side]


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
			c.state = State.LOBBY
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
			if not g.referee.add_inputs(c.side, m):
				return
			# Passed on rebuilt from known fields only, never as the player sent it.
			g.other(c).link.send({"t": "in", "n": g.n, "first": int(m["first"]), "inputs": m["inputs"],
				"ack": int(m.get("ack", -1)), "f": int(m.get("f", -1)), "adv": float(m.get("adv", 0.0))})
		"dg":
			var g := c.game
			if g == null or int(m.get("n", -1)) != g.n:
				return
			var f := int(m.get("f", -1))
			var d := String(m.get("d", "")).left(128)
			g.referee.add_digest(c.side, f, d)
			g.other(c).link.send({"t": "dg", "n": g.n, "f": f, "d": d}, true)
		"rematch":
			var g := c.game
			if g == null or g.rematch[c.side]:
				return
			g.rematch[c.side] = true
			g.other(c).link.send({"t": "rematch"}, true)
			if g.rematch[0] and g.rematch[1]:
				_report(g)
				_start(g)
		"bye":
			_drop(c, "left")


func _wait_text(c: Client) -> String:
	var where := (" in room '%s'" % c.room) if c.room != "" else ""
	return "On the server%s. Waiting for an opponent..." % where


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

## Pairs waiting players, oldest first, two in the same room at a time.
func _pair_waiting() -> void:
	var by_room := {}
	for c: Client in clients.values():
		if c.state == State.LOBBY and c.pinged():
			if by_room.has(c.room):
				_begin_game(by_room[c.room], c)
				by_room.erase(c.room)
			else:
				by_room[c.room] = c


func _begin_game(a: Client, b: Client) -> void:
	var g := Game.new()
	g.players = [a, b]
	a.side = 0
	b.side = 1
	for c: Client in g.players:
		c.game = g
		c.state = State.PLAYING
	games.append(g)
	_start(g)


func _start(g: Game) -> void:
	var a: Client = g.players[0]
	var b: Client = g.players[1]
	for c: Client in g.players:
		if c.link.rtt_ms() > 0.0:
			c.rtt = c.link.rtt_ms()
	var path := a.rtt + b.rtt
	g.n += 1
	g.delay = forced_delay if forced_delay >= 0 else Netplay.pick_delay(path)
	g.rematch = [false, false]
	g.reported = false
	g.referee = Referee.new([a.team, b.team], g.delay)
	g.path_ms = Time.get_ticks_msec()
	matches_started += 1
	g.label = matches_started
	var teams := [a.team.duplicate(), b.team.duplicate()]
	for c: Client in g.players:
		c.link.send({"t": "start", "n": g.n, "teams": teams, "delay": g.delay, "ping": path,
			"side": c.side, "via": g.other(c).rtt}, true)
	_log("match %d started%s: %s vs %s, round trip %d ms, input delay %d" % [g.label,
		" (rematch)" if g.n > 1 else "", a.label(), b.label(), roundi(path), g.delay])


func _referee_step(g: Game, now: int) -> void:
	g.referee.advance()
	if g.referee.winner != -2 and not g.reported:
		_report(g)
	if now - g.path_ms >= PATH_EVERY_MS:
		g.path_ms = now
		for c: Client in g.players:
			var r := g.other(c).link.rtt_ms()
			if r > 0.0:
				c.link.send({"t": "path", "rtt": r}, true)


## Logs how the match went, once.
func _report(g: Game) -> void:
	if g.reported:
		return
	g.reported = true
	var r := g.referee
	var how := ""
	if r.winner >= 0:
		matches_finished += 1
		how = "%s won" % (g.players[r.winner] as Client).label()
	elif r.winner == -1:
		matches_finished += 1
		how = "a draw"
	else:
		how = "unfinished at frame %d" % r.frame
	_log("match %d over: %s (%d fingerprints checked)" % [g.label, how, r.checked])
	for side in 2:
		if r.desync[side] >= 0:
			_log("match %d: %s's game went out of sync at frame %d (a bug: their report is in their desyncs folder)"
				% [g.label, (g.players[side] as Client).label(), r.desync[side]])


func _refuse(c: Client, why: String, msg: String) -> void:
	c.link.send({"t": "reject", "why": why, "msg": msg}, true)
	_drop(c, "refused: " + why)


## Removes a player; their opponent (if any) is told, and their session ends too.
func _drop(c: Client, why: String) -> void:
	if not clients.has(c.id):
		return
	clients.erase(c.id)
	_log("%s %s" % [c.label(), why])
	var g := c.game
	if g != null:
		_report(g)
		games.erase(g)
		var o := g.other(c)
		o.game = null
		if clients.has(o.id):
			o.link.send({"t": "bye", "why": "opponent"}, true)
			o.link.flush()
			clients.erase(o.id)
			o.link.close()
			_log("%s's match ended: the opponent %s" % [o.label(), why])
		g.players.clear()  # players and game point at each other: break the loop so both are freed
	c.game = null
	c.link.flush()
	c.link.close()


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 200:
		log_lines.pop_front()
	if on_log.is_valid():
		on_log.call(s)
