class_name RelayServer
extends RefCounted
## A dedicated server for online matches: players connect to it (with the game's
## ordinary Join), it groups them (two for a 1v1, four for a 2v2, six for a 3v3, eight for a 4v4 Capture the Flag), relays
## each match's input streams between them, and referees every match with its own copy
## of the simulation (Referee).
##
##   Player                      Server                        Player
##   hello {version, data, team, room} -->      <-- hello
##   <-- wait, ping x5 / pong -->               <-- ping x5 / pong -->
##   ...two players in the same room are paired...
##   <-- found {size, secs}                     found {size, secs} -->
##   ready  -->                                 <-- ready      (the ready check)
##   <-- accepted {have, need}                  accepted -->
##   <-- start {side 0, teams, delay}           start {side 1, ...} -->
##   in / dg  ---------------------> relayed --------------------->  (and back)
##   rematch  ---------------------> relayed;  both asked: pick again (a 1v1) or start again
##   bye      ---------------------> relayed;  the other player's session ends
##
## To a player the server looks like a host that gives them a side: Netplay needs only
## the `side` in "start" (and the opponent's round trip, `via`, for its time sync).
## "start" also lists every slot's player name (`names`, "CPU" for a CPU's) for the voice
## chat's mutes. Voice ("vc") goes to the other players who said `voice` in hello, and to
## spectators only in a room's match (they typed its code), never Quick match or ranked.
##
## Ready check: a group that's been put together isn't started straight away. Everyone
## in it gets "found" and has `ready_ms` to answer "ready"; once every player has, the
## match starts. If time runs out, those who accepted go back to waiting (keeping their
## place in the queue) and those who didn't are told why and dropped. A player who
## leaves during the check sends everyone else back to waiting. Rematches skip it: the
## players are already there.
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
##
## Team seats: players alternate sides as they're grouped, unless that would put two of
## the same fighter on one team; then the fewest players move to the other side so every
## duplicate faces itself across the match instead (when the picks allow it).
##
## Rooms: a room code is a Room that outlives its matches (a Game is one match). Its
## maker's size, tag, rules and arena hold for its whole life. Its first match is found
## like any (the ready check); after a match, players say "next" (they're on the fighter
## select) and "pick" {team}; once everyone in the room has locked in, the next match
## starts with a new `n`, re-seated (seat()). No ready check: they're all there.
##
##   <-- room {code, state, players [{name, fighter, locked, playing}], watchers}
##   next  -->                       (left the match-over for the fighter select)
##   pick {team}  -->                (locked in for the next match)
##   <-- start {...}                 (everyone locked in: the next match)
##
## Leaving a room never ends it for the others: in a 1v1 the one left goes back to
## waiting ("wait" with `back`) and keeps the code, and whoever joins it next plays them;
## in a team room a CPU plays the leaver's slot to the end of that match, and the next
## match fills the empty slots with CPUs (or newcomers, who join between matches). The
## room closes when its last player leaves; its watchers get "bye" {why: "room"}.
## Spectators of a room follow it from match to match without rejoining. Rooms don't
## take "rematch" (they pick again instead).
##
## A 1v1 rematch outside a room (Quick match, ranked, tag Duels) picks again too: once
## both players have asked, the Game goes to its pick (`picking`) and everyone, its
## spectators included, hears the room's status message with code "" and state
## "select"; each player answers "pick" {team} (as many fighters as before), and once
## both are in the next match starts with the new teams, `n` counted on. Ranked rates
## every game. Team battles in Quick match rematch with the same fighters.
##
## The picks stay hidden until both are in: the status only says who has locked in
## (`fighter` is each one's from the last match; no `team`), and "start" reveals both.
## It also carries `secs`, the countdown (`rematch_pick_ms`, from
## `rematch_pick_seconds` in data/online.json): when it runs out, anyone not locked in
## keeps their last pick and the match starts. Every Quick match rematch (1v1 or team
## battle, ranked or not) is on a newly drawn arena, never the one just played.
##
##   <-- room {code "", state "select", players [slot 0, slot 1]}  (both asked)
##   pick {team}  -->
##   <-- start {...}                 (both locked in: the rematch)

const PINGS := 5
## A ping that doesn't come back in this long is given up on.
const PING_TIMEOUT_MS := 2000
## How often each player hears the other's latest round trip.
const PATH_EVERY_MS := 2000
const MAX_ROOM_LENGTH := 32

## What one connection may cost the server (nothing an honest game comes near).
## Timeouts and rates run on the limits' clock (`_clock_ms`: the wall clock on the real
## server, `realtime`; in tests every tick() counts as a frame).
## A Daily submission's connection (state SUBMIT) is let go after this long.
const SUBMIT_TIMEOUT_MS := 15000
## Anyone quiet this long is pinged (every game answers), and dropped after IDLE_TIMEOUT_MS.
const KEEPALIVE_MS := 10000
const IDLE_TIMEOUT_MS := 60000
## Messages a connection may send: MSG_RATE a second on average, MSG_BURST at once (a
## player sends about 62 a second, 87 while talking: 62 input packets plus 25 voice
## packets, each spent like any other message, so a talker is still well under 240).
## Over it, the connection is dropped.
const MSG_RATE := 240
const MSG_BURST := 480
## Voice packets a connection may send on top of that: VOICE_RATE a second on average,
## VOICE_BURST at once. A talker sends 25 a second; a voice packet is ~440 bytes (an input
## packet ~40) and goes out to everyone else in the match, so without this one client
## could have the server send 240 x 440 x 7 = ~740 KB/s in an 8-player match (with it:
## 30 x 440 x 7 = ~92 KB/s at most). Over it, the packet is dropped, not relayed; the
## connection stays (a hitch can bunch up a few packets of an honest talker).
const VOICE_RATE := 30
const VOICE_BURST := 60
## The biggest packet once a connection has said hello (a player's are a few hundred
## bytes); before hello and for a Daily submission, EnetHub.MAX_PACKET_BYTES.
const MAX_PACKET_PLAYER := NetLink.SMALL_PACKET
## The referee keeps to the clock: inputs reaching more than AHEAD_INPUT_FRAMES past the
## frame the match's clock is on are refused, it steps at most AHEAD_STEP_FRAMES past it,
## and at most STEPS_PER_TICK frames per match per server loop (the real server loops
## about a thousand times a second, so a match keeps up at 60 frames a second easily).
const AHEAD_INPUT_FRAMES := 120
const AHEAD_STEP_FRAMES := 30
const STEPS_PER_TICK := 8
## Daily scores are verified a slice at a time, DAILY_FRAMES_PER_TICK frames a loop (a
## full fight is about 5500), one at a time with at most DAILY_QUEUE waiting, and
## DAILY_PER_MINUTE accepted server-wide (DAILY_BURST at once). One request per connection.
const DAILY_FRAMES_PER_TICK := 120
const DAILY_QUEUE := 4
const DAILY_PER_MINUTE := 30
const DAILY_BURST := 5
## Server replays kept on disk when data/online.json has no `server_replays_keep`.
const REPLAYS_KEEP_DEFAULT := 500

## The type(s) each field of a message must have; a message with a field of any other
## type is ignored whole (so nothing is half applied). Fields not listed aren't read.
const FIELD_TYPES := {
	"hello": {"v": [TYPE_INT], "data": [TYPE_STRING], "team": [TYPE_ARRAY], "room": [TYPE_STRING],
		"size": [TYPE_INT], "rules": [TYPE_STRING], "arena": [TYPE_STRING], "id": [TYPE_STRING],
		"name": [TYPE_STRING], "ranked": [TYPE_BOOL], "submit": [TYPE_BOOL], "watch": [TYPE_BOOL],
		"secret": [TYPE_STRING], "voice": [TYPE_BOOL]},
	"ping": {"n": [TYPE_INT]},
	"pong": {"n": [TYPE_INT]},
	"daily": {"date": [TYPE_INT], "fighter": [TYPE_STRING], "replay": [TYPE_DICTIONARY]},
	"board": {"date": [TYPE_INT]},
	"in": {"n": [TYPE_INT], "first": [TYPE_INT], "inputs": [TYPE_PACKED_INT32_ARRAY], "ack": [TYPE_INT],
		"f": [TYPE_INT], "adv": [TYPE_FLOAT, TYPE_INT], "advs": [TYPE_PACKED_FLOAT32_ARRAY]},
	"dg": {"n": [TYPE_INT], "f": [TYPE_INT], "d": [TYPE_STRING]},
	"pick": {"team": [TYPE_ARRAY]},
	"vc": {"n": [TYPE_INT], "s": [TYPE_INT], "d": [TYPE_PACKED_BYTE_ARRAY]},
}

enum State { HELLO, LOBBY, FOUND, PLAYING, WATCHING, SUBMIT, ROOM }
## What a room is doing: waiting for players (its first match, or a 1v1 whose other
## player left), playing a match, or picking fighters for the next.
enum RoomState { WAITING, PLAYING, SELECT }
const ROOM_STATE_NAMES := ["waiting", "playing", "select"]

## Messages players are dropped or requeued with during the ready check.
const MSG_NOT_ACCEPTED := "You didn't accept the match in time. Search again when you're ready."
const MSG_REQUEUE := "A player didn't accept. Back to searching..."
const MSG_LEFT := "A player left before the match. Back to searching..."

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
## How long every player in a group has to accept the match (the ready check).
var ready_ms := 15000
## Picks the CPUs' fighters (tests seed it; the server leaves it random).
var rng := RandomNumberGenerator.new()
## How well the CPUs play (CpuController levels: 0 Easy, 1 Normal, 2 Hard, 3 Rage).
var cpu_level := 1
## A 1v1 rematch's pick lasts this long (data/online.json `rematch_pick_seconds`).
var rematch_pick_ms := roundi(Netplay.rematch_pick_seconds() * 1000.0)
## Once both have locked in, the countdown drops to this (`rematch_locked_seconds`).
var rematch_locked_ms := roundi(Netplay.rematch_locked_seconds() * 1000.0)
## Added to the server's clock for the pick's countdown: tests move time on with it
## instead of sleeping.
var clock_skip_ms := 0
## The real server (DedicatedServer) turns this on: the limits' clock is the wall clock.
## Off (tests), every tick() counts as one frame (1000/60 ms) plus `clock_skip_ms`.
var realtime := false
## Connections at once from one address (its host part; 0: no limit). The real server
## sets it (--max-per-ip, default 6).
var max_per_ip := 0
## Ranked pairs two players from the same address only when this is on (--ranked-same-ip:
## a LAN party or a test). Off, two games behind one address never play each other rated.
var ranked_same_ip := false
## The Daily dates accepted are this day and the one either side of it (YYYYMMDD; 0:
## today's UTC date, Daily.today(); tests set it).
var daily_today := 0
## Server replays kept in `replay_dir` (the oldest go first).
var replays_keep := _replays_keep()
## Every log line goes here too (the server prints them).
var on_log := Callable()
var log_lines: Array = []

var clients := {}  ## id -> Client
var games: Array = []
var checks: Array = []  ## Checks: groups waiting for everyone to accept
var rooms := {}  ## code -> Room
var matches_started := 0
var matches_finished := 0
var _next_id := 1
var _ticks := 0
## Daily verifications under way, oldest first: {"c": Client, "verify": Daily.Verify, "date": int}.
var _daily_jobs: Array = []
var _daily_tokens := float(DAILY_BURST)
var _daily_tokens_ms := 0


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
	var rules := ""  ## the team rules asked for (TeamSim.RULE_IDS)
	var wait_shown := -1  ## the group size last told to this player
	var waiting_since := 0  ## when they started waiting for a match (ms)
	var check: Check = null  ## the ready check they're in (state FOUND)
	var watch := false  ## a spectator: never seated, fed every input of a match
	var arena := ArenaMap.DEFAULT  ## the map asked for (a room's maker decides; Quick match draws one)
	var pid := ""  ## the player's proven id (ranked and Daily only; "" otherwise) and typed name
	var key := ""  ## Ratings.key_of(pid, their secret): bound to the id at its first rated use
	var name := "Player"
	var ranked := false  ## wants a rated 1v1 (paired within a rating band)
	var heard_ms := 0  ## their last message, on the limits' clock
	var keepalive_ms := 0  ## the last keepalive ping sent them
	var submit_ms := 0  ## when they said hello as a Daily submission
	var asked := false  ## a Daily submission's one request is in
	var voice := false  ## said in hello that they hear voice chat (off: none is relayed to them)
	var tokens := float(RelayServer.MSG_BURST)  ## their message budget left
	var tokens_ms := 0
	var voice_tokens := float(RelayServer.VOICE_BURST)  ## their voice packet budget left
	var voice_tokens_ms := 0
	var voice_dropped := 0  ## voice packets over that budget, not relayed

	func label() -> String:
		return "player %d (%s)" % [id, ", ".join(PackedStringArray(team))] if not team.is_empty() \
			else "player %d" % id

	func pinged() -> bool:
		return rtts.size() >= RelayServer.PINGS or (rtts.size() > 0 and ping_usec == 0)


## A group that's been found, waiting for every player in it to accept.
class Check:
	var players: Array = []  ## Clients, in the order they were grouped
	var size := 1
	var rules := ""
	var ranked := false
	var deadline_ms := 0
	var accepted := {}  ## client id -> true

	func all_in() -> bool:
		return accepted.size() >= players.size()


## A room code's lasting state: who's in it and what it plays. A Game is one match; a
## Room outlives its games (a player leaving, picking new fighters, the next match).
class Room:
	var code := ""
	var maker := ""  ## the name of whoever set it up
	var cfg_set := false  ## size/tag/rules/arena come from the first player who asked for a size
	var size := 1
	var tag := 1  ## fighters per player (3: a tag Duel)
	var rules := ""
	var arena := ArenaMap.DEFAULT
	var players: Array = []  ## Clients, in the order they came (never more than size * 2)
	var watchers: Array = []  ## spectators, who follow every match here
	var state := 0  ## a RelayServer.RoomState
	var game: Game = null  ## the match on now, or the one just played (during SELECT)
	var locked := {}  ## client id -> true: picked a fighter for the next match
	var n := 0  ## the last match number here (the next one counts on, so old packets never match)

	func full() -> bool:
		return cfg_set and players.size() >= size * 2


## Players grouped into a match; rematches keep the group and count `n` up.
class Game:
	var label := 0  ## the server's match number, for the log
	var players: Array = []  ## Clients by slot (side 0 first: [left..., right...]); null: a CPU
	var cpu_fighters := {}  ## slot -> fighter id, for the CPU-played slots
	var size := 1  ## players per side
	var rules := ""  ## the team rules (TeamSim.RULE_IDS)
	var room := ""  ## the room it came from ("" for Quick match), so a spectator can find it
	var arena := ArenaMap.DEFAULT
	var ranked := false
	var watchers: Array = []  ## spectators (Clients) fed every input
	var n := 0
	var delay := 2
	var referee: Referee
	var rematch: Array = []
	## A 1v1 rematch's fighter select: on, and who has locked in (slot -> true).
	var picking := false
	var picks := {}  ## slot -> the team locked in (kept off the players until "start")
	var pick_deadline_ms := 0
	var all_locked := false  ## both picks are in: frozen and shown until the countdown ends
	var reported := false
	var path_ms := 0
	var clock_ms := 0  ## when this match started, on the limits' clock

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
	var clock := _clock_ms()
	c.heard_ms = clock
	c.keepalive_ms = clock
	c.tokens_ms = clock
	if link.max_packet <= 0 or link.max_packet > EnetHub.MAX_PACKET_BYTES:
		link.max_packet = EnetHub.MAX_PACKET_BYTES
	clients[c.id] = c
	_log("player %d connected%s" % [c.id, (" from " + address) if address != "" else ""])
	if clients.size() > max_players:
		_refuse(c, "full", "The server is full (%d players). Try again later." % max_players)
	elif max_per_ip > 0 and address != "" and _from_host(_host(address)) > max_per_ip:
		_refuse(c, "busy", "Too many connections from your address. Close another game and try again.")
	return c


## The host part of an address ("1.2.3.4:5678" -> "1.2.3.4"; an IPv6 one keeps its colons).
static func _host(address: String) -> String:
	var at := address.rfind(":")
	return address.substr(0, at) if at > 0 else address


func _from_host(host: String) -> int:
	var n := 0
	for o: Client in clients.values():
		if _host(o.address) == host:
			n += 1
	return n


## The limits' clock, in ms: the wall clock on the real server (`realtime`), else a
## frame's worth for every tick() so far (tests), plus `clock_skip_ms` either way.
func _clock_ms() -> int:
	return _now() if realtime else _ticks * 1000 / 60 + clock_skip_ms


## Takes one message from `c`'s budget (refilled at MSG_RATE a second up to MSG_BURST).
## False when it's spent.
func _spend(c: Client, clock: int) -> bool:
	c.tokens = minf(float(MSG_BURST), c.tokens + float(clock - c.tokens_ms) * MSG_RATE / 1000.0)
	c.tokens_ms = clock
	if c.tokens < 1.0:
		return false
	c.tokens -= 1.0
	return true


## Takes one voice packet from `c`'s voice budget (refilled at VOICE_RATE a second up to
## VOICE_BURST). False when it's spent: the packet isn't relayed (the first time, logged).
func _spend_voice(c: Client, clock: int) -> bool:
	c.voice_tokens = minf(float(VOICE_BURST), c.voice_tokens + float(clock - c.voice_tokens_ms) * VOICE_RATE / 1000.0)
	c.voice_tokens_ms = clock
	if c.voice_tokens < 1.0:
		c.voice_dropped += 1
		if c.voice_dropped == 1:
			_log("%s sends voice faster than %d packets a second: the extra isn't relayed" % [c.label(), VOICE_RATE])
		return false
	c.voice_tokens -= 1.0
	return true


## Whether every field of `m` that the server reads has the type it must (FIELD_TYPES).
static func _well_typed(m: Dictionary) -> bool:
	var t = m.get("t")
	if not (t is String):
		return false
	var spec: Dictionary = FIELD_TYPES.get(t, {})
	for k in spec:
		if m.has(k) and not (typeof(m[k]) in (spec[k] as Array)):
			return false
	return true


## The size of a well-formed voice packet's audio (VoiceChat.packet_bytes), worked out once.
static var _voice_packet_bytes := 0
static func _voice_bytes() -> int:
	if _voice_packet_bytes <= 0:
		_voice_packet_bytes = VoiceChat.new().packet_bytes()
	return _voice_packet_bytes


## `c` is a player seated in their match (not a spectator, not someone it's done with):
## only they may send its inputs, fingerprints, rematch and pick.
func _seated(c: Client) -> bool:
	var g := c.game
	return g != null and not c.watch and c.state == State.PLAYING and c.slot >= 0 \
		and c.slot < g.players.size() and g.players[c.slot] == c


## Once per server loop: read every player's messages, pair players, referee matches.
func tick() -> void:
	var now := Time.get_ticks_msec()
	_ticks += 1
	var clock := _clock_ms()
	for c: Client in clients.values():
		if not clients.has(c.id):
			continue  # dropped while handling someone else's message
		var msgs: Array = c.link.poll()
		if msgs.size() > MSG_BURST:
			_drop(c, "sent too many messages (%d at once)" % msgs.size())
			continue
		for m in msgs:
			if not clients.has(c.id):
				break
			if not _spend(c, clock):
				_drop(c, "sent too many messages")
				break
			c.heard_ms = clock
			if m is Dictionary and _well_typed(m):
				_handle(c, m)
		if not clients.has(c.id):
			continue
		if c.link.status == NetLink.Status.CLOSED:
			_drop(c, c.link.error if c.link.error.begins_with("sent ") else "disconnected")
		elif c.state == State.HELLO and now - c.since_ms > hello_timeout_ms:
			_drop(c, "never said hello")
		elif c.state == State.SUBMIT and clock - c.submit_ms > SUBMIT_TIMEOUT_MS and not _verifying(c):
			_drop(c, "took too long over its Daily request")
		elif c.state != State.HELLO and clock - c.heard_ms > IDLE_TIMEOUT_MS:
			_drop(c, "went quiet")
		else:
			if c.state == State.LOBBY:
				_ping_step(c)
			if c.state != State.HELLO and clock - c.heard_ms > KEEPALIVE_MS and clock - c.keepalive_ms > KEEPALIVE_MS:
				c.keepalive_ms = clock
				c.link.send({"t": "ping", "n": 0}, true)  # every game answers; n 0 is never a timed ping
	_daily_step()
	_pair_waiting()
	_attach_watchers()
	_check_step(now)
	for g: Game in games.duplicate():
		if g.picking and _now() >= g.pick_deadline_ms:
			_pick_timeout(g)
	for g: Game in games:
		_referee_step(g, now, clock)
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
	for k: Check in checks:
		k.players.clear()
	clients.clear()
	games.clear()
	checks.clear()
	rooms.clear()


# ------------------------------------------------------------------ messages

## One message from `c`, its fields' types already checked (_well_typed).
func _handle(c: Client, m: Dictionary) -> void:
	match String(m.get("t", "")):
		"hello":
			if c.state != State.HELLO:
				return
			if int(m.get("v", -1)) != Netplay.NET_VERSION or String(m.get("data", "")) != Netplay.data_hash():
				_refuse(c, "version", "The server runs a different version of the game. Update your game (or ask the server's owner to update the server) so both are the same build.")
				return
			var team = m.get("team")
			if not Netplay.valid_team(team):
				_refuse(c, "fighter", "The server doesn't have the fighter you picked. It needs the same build as you.")
				return
			c.team = (team as Array).duplicate()
			c.room = String(m.get("room", "")).strip_edges().to_lower().left(MAX_ROOM_LENGTH)
			c.size = clampi(int(m.get("size", 1)), 0, TeamSim.MOST_PER_SIDE)
			if c.room == "" and c.size == 0:
				c.size = 1
			c.rules = String(m.get("rules", ""))
			if not (c.rules in TeamSim.RULE_IDS):
				c.rules = ""
			if c.size > 1:
				c.size = mini(c.size, TeamSim.max_size_for(c.rules))  # 4 v 4 is Capture the Flag only
			c.arena = String(m.get("arena", ArenaMap.DEFAULT))
			if not (c.arena in ArenaMap.IDS):
				c.arena = ArenaMap.DEFAULT
			c.name = _clean_name(String(m.get("name", "")))
			c.voice = bool(m.get("voice", false))
			var submit := bool(m.get("submit", false))
			c.ranked = bool(m.get("ranked", false)) and not submit and c.size == 1 and c.team.size() == 1 and c.room == ""
			if (c.ranked or submit) and not _identify(c, m, submit):
				return  # refused
			c.ranked = c.ranked and c.pid != ""
			if submit:
				# Here to send a Daily score or read the board, then go.
				c.state = State.SUBMIT
				c.submit_ms = _clock_ms()
				return
			c.link.max_packet = MAX_PACKET_PLAYER  # a player's messages are all small
			if bool(m.get("watch", false)):
				# A spectator: attached to a match as soon as there is one to watch.
				c.watch = true
				c.slot = -1  # never anyone's slot
				c.state = State.WATCHING
				c.waiting_since = Time.get_ticks_msec()
				_log("%s wants to watch%s" % [c.label(), (" room '%s'" % c.room) if c.room != "" else ""])
				c.link.send({"t": "wait", "msg": "On the server. Waiting for a match to watch..."}, true)
				if c.room != "":
					var wr := _room(c.room)
					wr.watchers.append(c)
					_room_status(wr)
				return
			if c.room != "" and not _join_room(c):
				return
			if c.state == State.ROOM:
				return  # joined a room between (or during) its matches: in for the next one
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
		"ready":
			_accept(c)
		"daily":
			if c.state != State.SUBMIT:
				return
			if c.asked:
				_drop(c, "sent a second Daily request")
				return
			c.asked = true
			_daily_submit(c, m)
		"board":
			if c.state != State.SUBMIT:
				return
			if c.asked:
				_drop(c, "sent a second Daily request")
				return
			c.asked = true
			c.link.send({"t": "daily_board", "date": int(m.get("date", 0)),
				"board": ratings.daily_board(int(m.get("date", 0)), Ratings.TOP, c.pid)}, true)
		"in":
			var g := c.game
			if not _seated(c) or int(m.get("n", -1)) != g.n:
				return
			if not g.referee.add_inputs(c.slot, m, _clock_frame(g) + AHEAD_INPUT_FRAMES):
				return
			# Passed on rebuilt from known fields only, never as the player sent it.
			var out := {"t": "in", "n": g.n, "p": c.slot, "first": int(m["first"]), "inputs": m["inputs"],
				"ack": int(m.get("ack", -1)), "f": int(m.get("f", -1)), "adv": float(m.get("adv", 0.0))}
			var advs = m.get("advs")
			if advs is PackedFloat32Array and (advs as PackedFloat32Array).size() == g.players.size():
				out["advs"] = advs
			for o: Client in g.others(c):
				o.link.send(out)
			for w: Client in g.watchers:
				w.link.send(out)
		"vc":
			# Voice chat: only from a seated player, for the match on now, exactly one packet's
			# worth of audio. Rebuilt from known fields (the slot is the server's, never the
			# sender's `p`) and sent unreliably only to whoever asked for voice: the other
			# players with it on and, in a room's match only, the spectators who didn't turn
			# it off (they typed its code; Quick match and ranked spectators are strangers
			# watching whatever is on, so they hear nothing). Never from a spectator
			# (_seated). Each spends from the message budget (_spend, in tick) and the voice
			# budget (_spend_voice: over it, dropped quietly).
			var g := c.game
			if not _seated(c) or int(m.get("n", -1)) != g.n:
				return
			if not _spend_voice(c, _clock_ms()):
				return
			var d = m.get("d")
			var s := int(m.get("s", -1))
			if not (d is PackedByteArray) or (d as PackedByteArray).size() != _voice_bytes() or s < 0:
				return
			var out := {"t": "vc", "n": g.n, "p": c.slot, "s": s, "d": d}
			for o: Client in g.others(c):
				if o.voice:
					o.link.send(out)
			if g.room != "":
				for w: Client in g.watchers:
					if w.voice:
						w.link.send(out)
		"dg":
			var g := c.game
			if not _seated(c) or int(m.get("n", -1)) != g.n:
				return
			var f := int(m.get("f", -1))
			var d := String(m.get("d", "")).left(128)
			if not g.referee.add_digest(c.slot, f, d):
				return  # refused: not passed on either
			for o: Client in g.others(c):
				o.link.send({"t": "dg", "n": g.n, "p": c.slot, "f": f, "d": d}, true)
		"rematch":
			var g := c.game
			if not _seated(c) or g.rematch[c.slot] or g.room != "":
				return  # a room picks again instead
			g.rematch[c.slot] = true
			for o: Client in g.others(c):
				o.link.send({"t": "rematch", "p": c.slot}, true)
			if not (false in g.rematch):  # CPUs always say yes
				_report(g)
				if g.size == 1:
					_open_pick(g)  # a 1v1 picks again first
				else:
					_start(g)
		"next":
			_room_next(c)
		"pick":
			if c.game != null and c.game.picking:
				if _seated(c):
					_rematch_pick(c, m.get("team"))
			else:
				_room_pick(c, m.get("team"))
		"bye":
			_drop(c, "left")


func _wait_text(c: Client, have := 1, need := 2) -> String:
	var where := (" in room '%s'" % c.room) if c.room != "" else ""
	if c.ranked:
		var p := ratings.peek(c.pid)
		return "Ranked. Your rating %d (%d games). Waiting for someone near it..." % [
			roundi(float(p.get("rating", Ratings.START))), int(p.get("games", 0))]
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
	var waiting: Array = clients.values().filter(func(c): return c.state == State.LOBBY)
	waiting.sort_custom(func(a, b): return a.id < b.id)
	for c: Client in waiting:
		# Quick match groups by what each asked for: players per side, fighters per
		# player (a tag Duel is three) and the team rules. A room takes its maker's.
		# Ranked players queue apart and pair by rating (below).
		var cfg: Array = [c.size, c.team.size(), c.rules]
		if c.room != "":
			var r: Room = rooms.get(c.room)
			cfg = [r.size, r.tag, r.rules] if r != null and r.cfg_set else [1, 1, ""]
		var key := "%s|%d|%d|%s%s" % [c.room, int(cfg[0]), int(cfg[1]), String(cfg[2]), "|ranked" if c.ranked else ""]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(c)
	for key in groups:
		if String(key).ends_with("|ranked"):
			_pair_ranked((groups[key] as Array).filter(func(c): return c.pinged()))
			continue
		var size := int(String(key).get_slice("|", 1))
		var key_rules := String(key).get_slice("|", 3)
		var need := size * 2
		var ready: Array = (groups[key] as Array).filter(func(c): return c.pinged())
		while ready.size() >= need:
			_found(ready.slice(0, need), size, key_rules)
			ready = ready.slice(need)
		# Waited long enough for a team battle: CPUs take the empty slots.
		if need > 2 and not ready.is_empty():
			var fill := _fill_ms(ready[0])
			if fill > 0 and Time.get_ticks_msec() - (ready[0] as Client).waiting_since >= fill:
				_found(ready, size, key_rules)
				ready = []
		for c: Client in groups[key]:
			if c.state == State.LOBBY and need > 2 and c.wait_shown != (groups[key] as Array).size():
				c.wait_shown = (groups[key] as Array).size()
				c.link.send({"t": "wait", "msg": _wait_text(c, mini(c.wait_shown, need), need)}, true)


## Spectators waiting for a match: a room's match once it is on, or (no room) the
## newest match on the server. They get the match's setup and every input so far.
func _attach_watchers() -> void:
	for c: Client in clients.values():
		if c.state != State.WATCHING or c.game != null:
			continue
		var g: Game = null
		if c.room != "":
			var r: Room = rooms.get(c.room)
			g = r.game if r != null else null
		else:
			for cand: Game in games:
				if not cand.players.is_empty():
					g = cand
		if g == null:
			continue
		g.watchers.append(c)
		c.game = g
		_send_watch_start(g, c)
		if g.picking:
			_pick_status(g)  # its players are picking for a rematch
		_log("%s is watching match %d" % [c.label(), g.label])


func _send_watch_start(g: Game, c: Client) -> void:
	c.link.send({"t": "start", "watch": true, "n": g.n, "teams": g.referee.teams, "size": g.size, "rules": g.rules,
		"arena": g.arena, "delay": g.delay, "log": g.referee.log.duplicate(), "names": _names(g)}, true)


## Each slot's player name in slot order ("CPU" for a CPU's), for "start": the voice
## chat mutes by name, so a muted player stays muted when a room re-seats everyone.
func _names(g: Game) -> Array:
	var out: Array = []
	for c in g.players:
		out.append("CPU" if c == null else (c as Client).name)
	return out


## Ranked: the longest waiter first, paired with the closest rating within the band
## their wait has opened (Ratings.band), so a lopsided match only happens after a
## long wait.
func _pair_ranked(ready: Array) -> void:
	var now := Time.get_ticks_msec()
	var pool := ready.duplicate()
	while pool.size() >= 2:
		var a: Client = pool[0]
		var best: Client = null
		var best_gap := INF
		for k in range(1, pool.size()):
			var b: Client = pool[k]
			if not _may_rate(a, b):
				continue
			var waited := now - mini(a.waiting_since, b.waiting_since)
			if not ratings.band_ok(a.pid, b.pid, waited):
				continue
			var gap := absf(ratings.rating(a.pid) - ratings.rating(b.pid))
			if gap < best_gap:
				best_gap = gap
				best = b
		if best == null:
			pool.remove_at(0)
			continue
		pool.erase(best)
		pool.remove_at(0)
		_found([a, best], 1, "", true)


## Two players may meet in ranked: never the same id, and never two games behind one
## address unless `ranked_same_ip` (in-memory test links have no address).
func _may_rate(a: Client, b: Client) -> bool:
	if a.pid == b.pid:
		return false
	return ranked_same_ip or a.address == "" or b.address == "" or _host(a.address) != _host(b.address)


## A ranked or Daily hello: who is this? The id counts only with a secret that proves it
## (Ratings.key_of): an id already bound to another secret is refused, and so is an id
## that already has a live connection of the same kind (one ranked game, one Daily
## request per player; the newer one is turned away). An id from before secrets, with
## history in the book but no key, is bound here to the first secret that claims it.
## No id or no secret: the player is anonymous (no ranked, no Daily board). False when refused.
func _identify(c: Client, m: Dictionary, submit: bool) -> bool:
	c.pid = ""
	c.key = ""
	var pid := _clean_id(String(m.get("id", "")))
	var secret := String(m.get("secret", ""))
	if pid == "" or not Netplay.valid_secret(secret):
		return true
	var key := Ratings.key_of(pid, secret)
	match ratings.check_key(pid, key):
		Ratings.Key.WRONG:
			_refuse(c, "identity", "The server knows your player id from another copy of the game, so it can't "
				+ "rate this one. Ask the server's owner to reset your player if you moved computers.")
			return false
		Ratings.Key.UNKNOWN:
			if ratings.has_history(pid):
				ratings.bind_key(pid, key)
				_log("%s claimed an existing player record (first secret bound to it)" % c.label())
	for o: Client in clients.values():
		if o != c and o.pid == pid and (o.state == State.SUBMIT) == submit:
			_refuse(c, "twice", ("You're already sending a Daily score from another game." if submit else
				"You're already in ranked from another game. Close it, or wait a minute for it to time out."))
			return false
	c.pid = pid
	c.key = key
	return true


static func _clean_id(s: String) -> String:
	s = s.strip_edges().to_lower()
	if s.length() < 8 or s.length() > 32:
		return ""
	for ch in s:
		if not ("0123456789abcdef".contains(ch)):
			return ""
	return s


static func _clean_name(s: String) -> String:
	return Netplay.clean_name(s)


## Whether a Daily date is today (the server's UTC date, or `daily_today`) or a day either side.
func _daily_date_ok(date: int) -> bool:
	var today := daily_today if daily_today > 0 else Daily.today()
	var day := Ratings.date_days(date)
	return day >= 0 and absi(day - Ratings.date_days(today)) <= 1


## A Daily Challenge replay: scored here on a fresh match of that day, never trusted
## from the client, then put on the board.
func _daily_submit(c: Client, m: Dictionary) -> void:
	var date := int(m.get("date", 0))
	var fighter := String(m.get("fighter", ""))
	var rep_dict = m.get("replay")
	if not (fighter in MatchFactory.FIGHTERS) or not (rep_dict is Dictionary) or c.pid == "":
		c.link.send({"t": "reject", "why": "daily", "msg": "That score can't be taken: a bad request."}, true)
		return
	if not _daily_date_ok(date):
		c.link.send({"t": "reject", "why": "daily", "msg": "That Daily is over: scores are taken on the day only."}, true)
		return
	# Size and shape first, before anything is converted: two inputs a row, no longer
	# than the fight.
	var rep := Replay.from_dict(rep_dict, Daily.max_frames(), 2)
	if rep == null:
		c.link.send({"t": "reject", "why": "daily", "msg": "That replay isn't a Daily fight."}, true)
		return
	if _daily_jobs.size() > DAILY_QUEUE or not _take_daily_token():
		c.link.send({"t": "reject", "why": "busy", "msg": "The server is busy scoring. Try again in a minute."}, true)
		return
	_daily_jobs.append({"c": c, "verify": Daily.Verify.new(Daily.new(fighter, date), rep), "date": date})


## One Daily verification spends DAILY_FRAMES_PER_TICK frames of this loop; once one is
## scored it goes on the board and its sender hears the rank.
func _daily_step() -> void:
	while not _daily_jobs.is_empty() and not clients.has((_daily_jobs[0]["c"] as Client).id):
		_daily_jobs.pop_front()  # its sender left: nobody to tell
	if _daily_jobs.is_empty():
		return
	var job: Dictionary = _daily_jobs[0]
	var v: Daily.Verify = job["verify"]
	if not v.step(DAILY_FRAMES_PER_TICK):
		return
	_daily_jobs.pop_front()
	var c: Client = job["c"]
	var date := int(job["date"])
	if v.mismatch:
		# Its CPU column isn't what the day's CPU does against those inputs: not the
		# day's fight as the game plays it (another build, or made up).
		_log("%s sent a Daily replay for %d that the day's CPU doesn't play the same (frame %d): refused"
			% [c.label(), date, v.ticks])
		c.link.send({"t": "reject", "why": "daily", "msg": "The server couldn't replay that fight the same way. "
			+ "Is your game up to date?"}, true)
		return
	if not ratings.bind_key(c.pid, c.key):
		c.link.send({"t": "reject", "why": "identity", "msg": "That score can't be taken for this player."}, true)
		return
	var rank := ratings.submit_daily(date, c.pid, c.name, v.score)
	_log("%s sent a Daily score for %d: %d (rank %d)" % [c.label(), date, v.score, rank])
	c.link.send({"t": "daily_ok", "date": date, "score": v.score, "rank": rank,
		"board": ratings.daily_board(date, Ratings.TOP, c.pid)}, true)


func _verifying(c: Client) -> bool:
	for job in _daily_jobs:
		if job["c"] == c:
			return true
	return false


## The server-wide Daily budget: DAILY_PER_MINUTE, DAILY_BURST at once.
func _take_daily_token() -> bool:
	var clock := _clock_ms()
	_daily_tokens = minf(float(DAILY_BURST), _daily_tokens + float(clock - _daily_tokens_ms) * DAILY_PER_MINUTE / 60000.0)
	_daily_tokens_ms = clock
	if _daily_tokens < 1.0:
		return false
	_daily_tokens -= 1.0
	return true


## A group is ready to play: ask everyone in it to accept (the ready check).
func _found(group: Array, size: int, rules := "", ranked := false) -> void:
	var k := Check.new()
	k.players = group.duplicate()
	k.size = size
	k.rules = rules
	k.ranked = ranked
	k.deadline_ms = Time.get_ticks_msec() + ready_ms
	checks.append(k)
	for c: Client in group:
		c.state = State.FOUND
		c.check = k
		c.wait_shown = -1
		c.link.send({"t": "found", "size": size, "players": group.size(), "need": size * 2,
			"secs": ready_ms / 1000.0}, true)
	_log("match found for %s; waiting for everyone to accept" % ", ".join(PackedStringArray(
		group.map(func(c): return (c as Client).label()))))


## A player in a ready check accepted. Once everyone has, the match starts.
func _accept(c: Client) -> void:
	if c.state != State.FOUND or c.check == null or c.check.accepted.has(c.id):
		return
	var k := c.check
	k.accepted[c.id] = true
	for o: Client in k.players:
		o.link.send({"t": "accepted", "have": k.accepted.size(), "need": k.players.size()}, true)
	if k.all_in():
		checks.erase(k)
		for o: Client in k.players:
			o.check = null
		_begin_game(k.players, k.size, k.rules, k.ranked)


## Ready checks whose time ran out: those who accepted wait again (their place kept),
## the rest are told why and dropped.
func _check_step(now: int) -> void:
	for k: Check in checks.duplicate():
		if now < k.deadline_ms:
			continue
		checks.erase(k)
		for c: Client in k.players:
			c.check = null
			if k.accepted.has(c.id):
				_requeue(c, MSG_REQUEUE)
		for c: Client in k.players:
			if not k.accepted.has(c.id) and clients.has(c.id):
				_refuse(c, "ready", MSG_NOT_ACCEPTED)


## Back to waiting for a match, keeping their place in the queue.
func _requeue(c: Client, msg: String) -> void:
	if not clients.has(c.id):
		return
	c.state = State.LOBBY
	c.check = null
	c.wait_shown = -1
	c.link.send({"t": "wait", "msg": msg, "requeue": true}, true)


## Which side each player of a group sits on. They alternate as they arrived (so in a
## room the first two face each other), unless that puts the same fighter twice on one
## team: then the fewest players move so duplicates face each other across the match.
static func seat(teams: Array, size: int) -> Array:
	var n := teams.size()
	var sides: Array = []
	for k in n:
		sides.append(k % 2)
	if size <= 1 or n <= 2:
		return sides
	var on_right := n / 2
	var best_mask := -1
	var best := [1 << 30, 1 << 30]
	for mask in 1 << n:
		var right := 0
		for k in n:
			right += (mask >> k) & 1
		if right != on_right:
			continue
		var seen := [{}, {}]
		var dups := 0
		var moved := 0
		for k in n:
			var s := (mask >> k) & 1
			var f := String((teams[k] as Array)[0]) if not (teams[k] as Array).is_empty() else ""
			if (seen[s] as Dictionary).has(f):
				dups += 1
			seen[s][f] = true
			if s != int(sides[k]):
				moved += 1
		if dups < int(best[0]) or (dups == int(best[0]) and moved < int(best[1])):
			best = [dups, moved]
			best_mask = mask
	if best_mask >= 0:
		for k in n:
			sides[k] = (best_mask >> k) & 1
	return sides


## `group`: the players in the order they arrived; `seat()` picks their sides. Fewer
## than a full match: CPUs take the slots left over (fighters nobody picked, first).
func _begin_game(group: Array, size: int, rules := "", ranked := false) -> void:
	var g := Game.new()
	g.size = size
	g.rules = rules
	g.ranked = ranked
	g.room = (group[0] as Client).room if not group.is_empty() else ""
	var r: Room = rooms.get(g.room) if g.room != "" else null
	if r != null and not r.cfg_set:
		# Nobody asked for a size (friends who all joined by code): a 1v1, from now on.
		r.cfg_set = true
		r.size = size
		r.tag = (group[0] as Client).team.size()
		r.rules = rules
		r.arena = (group[0] as Client).arena
	# The map: a room's maker picked it; Quick match draws one (the server's choice).
	# Rules with their own map (Caravan, Capture the Flag) always play it.
	g.arena = r.arena if r != null else String(ArenaMap.IDS[rng.randi_range(0, ArenaMap.IDS.size() - 1)])
	var rules_arena := String(TeamSim.rules_by_id(rules).get("arena", "")) if size > 1 else ""
	if ArenaMap.known(rules_arena):
		g.arena = rules_arena
	if r != null:
		# The room's next match: numbered on from the last, so nothing from it can mix in,
		# and its spectators come along.
		g.n = r.n
		r.game = g
		r.state = RoomState.PLAYING
		r.locked.clear()
		for c: Client in r.players:
			if not (c in group):
				# In the room but not grouped (still being pinged): in for the next match.
				c.state = State.ROOM
				r.locked[c.id] = true
		for w: Client in r.watchers:
			if w.game != null:
				w.game.watchers.erase(w)
			w.game = g
			g.watchers.append(w)
	g.players.resize(size * 2)
	var used := {}
	var sides := seat(group.map(func(c): return (c as Client).team), size)
	var filled := [0, 0]
	for k in group.size():
		var c: Client = group[k]
		c.side = int(sides[k])
		c.slot = c.side * size + int(filled[c.side])
		filled[c.side] += 1
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
	if g.room == "" and g.n > 0 and not (g.arena in ArenaMap.MODE_IDS):
		g.arena = _draw_arena(g.arena)  # a Quick match rematch: somewhere new (a mode's map stays)
	for slot in g.picks:  # a rematch's picks, revealed now
		(g.players[int(slot)] as Client).team = (g.picks[slot] as Array).duplicate()
	g.n += 1
	if g.room != "" and rooms.has(g.room):
		(rooms[g.room] as Room).n = g.n
	g.delay = forced_delay if forced_delay >= 0 else Netplay.pick_delay(path)
	g.rematch = []
	g.picking = false
	g.picks = {}
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
	g.referee = Referee.new(teams, g.delay, g.size, g.rules, g.arena, g.n)
	g.referee.post_result_frames = Referee.POST_RESULT_FRAMES
	g.referee.max_frames = Referee.MAX_MATCH_FRAMES
	for slot in g.cpu_fighters:
		g.referee.add_cpu(int(slot), cpu_level, g.label * 31 + int(slot) * 7 + g.n)
	g.path_ms = Time.get_ticks_msec()
	g.clock_ms = _clock_ms()
	matches_started += 1
	g.label = matches_started
	var cpu_slots: Array = g.cpu_fighters.keys()
	cpu_slots.sort()
	var slot_names := _names(g)
	for c: Client in g.humans():
		var worst := 0.0
		for o: Client in g.others(c):
			worst = maxf(worst, o.rtt)
		var m := {"t": "start", "n": g.n, "teams": teams, "delay": g.delay, "ping": c.rtt + worst,
			"side": c.side, "via": worst, "rules": g.rules, "arena": g.arena, "names": slot_names}
		if g.size > 1:
			m["slot"] = c.slot
			m["size"] = g.size
			m["vias"] = rtts
			if not cpu_slots.is_empty():
				m["cpu"] = cpu_slots
		c.link.send(m, true)
	for w: Client in g.watchers:
		_send_watch_start(g, w)
	var sides := ["", ""]
	for side in 2:
		var names := PackedStringArray()
		for slot in range(side * g.size, (side + 1) * g.size):
			var c = g.players[slot]
			names.append("CPU (%s)" % g.cpu_fighters[slot] if c == null else (c as Client).label())
		sides[side] = " + ".join(names)
	_log("match %d started%s: %s vs %s on %s, round trip %d ms, input delay %d" % [g.label,
		(" in room '%s'" % g.room) if g.room != "" else (" (rematch)" if g.n > 1 else ""), sides[0], sides[1],
		g.arena, roundi(path), g.delay])
	if g.room != "" and rooms.has(g.room):
		_room_status(rooms[g.room])


## The frame match `g` is on by the limits' clock (frame 0 when it started).
func _clock_frame(g: Game, clock := -1) -> int:
	return int((float(_clock_ms() if clock < 0 else clock) - float(g.clock_ms)) * 60.0 / 1000.0)


func _referee_step(g: Game, now: int, clock: int) -> void:
	g.referee.advance(_clock_frame(g, clock) + AHEAD_STEP_FRAMES, STEPS_PER_TICK)
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
	for w: Client in g.watchers:
		w.link.send({"t": "in", "n": g.n, "p": slot, "first": int(pkt["first"]), "inputs": pkt["inputs"],
			"ack": -1, "f": -1}, true)


## Where the server keeps its matches' replays when `save_replays` is on (the
## dedicated server turns it on): one file per match, playable in the Replay theater.
var save_replays := false
var replay_dir := "user://replays/"
## Ranked ratings and daily scores (user://ratings.json on a real server).
var ratings := Ratings.new()


func _init() -> void:
	ratings.persist = false  # the dedicated server turns it on; tests keep it in memory
	ratings.on_log = func(s: String) -> void: _log(s)


func _save_replay(g: Game) -> String:
	var rep := Replay.new()
	rep.setup = g.referee.setup_dict()
	for row in g.referee.log:
		rep.record(row)
	var path := replay_dir.path_join("online_%d_%d.json" % [g.label, g.n])
	if rep.save(path) == OK:
		_log("replay of match %d saved: %s (%d frames)" % [g.label, path, rep.frames.size()])
		_rotate_replays()
		return path
	return ""


## Keeps the newest `replays_keep` server replays in `replay_dir`; older ones are deleted.
func _rotate_replays() -> void:
	if replays_keep <= 0:
		return
	var files: Array = []
	for f in DirAccess.get_files_at(replay_dir):
		if f.begins_with("online_") and f.ends_with(".json"):
			var p := replay_dir.path_join(f)
			files.append([FileAccess.get_modified_time(p), f, p])
	if files.size() <= replays_keep:
		return
	files.sort()  # oldest first (then by name)
	for k in files.size() - replays_keep:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(files[k][2])))


## data/online.json `server_replays_keep`, or REPLAYS_KEEP_DEFAULT.
static func _replays_keep() -> int:
	var f := FileAccess.open("res://data/online.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	if d is Dictionary and (d.get("server_replays_keep") is float or d.get("server_replays_keep") is int):
		return maxi(0, int(d["server_replays_keep"]))
	return REPLAYS_KEEP_DEFAULT


## Logs how the match went, once.
func _report(g: Game) -> void:
	if g.reported:
		return
	g.reported = true
	if save_replays:
		_save_replay(g)
	var r := g.referee
	if g.ranked and r.winner != -2 and g.players.size() == 2 and g.players[0] != null and g.players[1] != null \
			and _keys_bound(g):
		# A rated result: both players hear their new rating.
		var a: Client = g.players[0]
		var b: Client = g.players[1]
		var score_a := 0.5 if r.winner == -1 else (1.0 if r.winner == 0 else 0.0)
		var out := ratings.record(a.pid, a.name, b.pid, b.name, score_a)
		for k in 2:
			var cl: Client = g.players[k]
			if clients.has(cl.id):
				cl.link.send({"t": "rating", "old": out[k]["old"], "new": out[k]["new"], "rd": out[k]["rd"],
					"games": out[k]["games"], "wins": out[k]["wins"]}, true)
		_log("match %d rated: %s %d -> %d, %s %d -> %d" % [g.label, a.name, roundi(float(out[0]["old"])),
			roundi(float(out[0]["new"])), b.name, roundi(float(out[1]["old"])), roundi(float(out[1]["new"]))])
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


## Both players' ids are theirs: each key is bound (on its first rated game) or matches.
func _keys_bound(g: Game) -> bool:
	for cl: Client in g.players:
		if not ratings.bind_key(cl.pid, cl.key):
			_log("match %d not rated: %s's id is bound to another secret" % [g.label, cl.label()])
			return false
	return true


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
	var r: Room = rooms.get(c.room) if c.room != "" else null
	if r != null and not (c in r.players) and not (c in r.watchers):
		r = null  # turned away before it got in (a full room): not this room's to change
	if c.watch:
		if c.game != null:
			c.game.watchers.erase(c)
		c.game = null
		if r != null:
			r.watchers.erase(c)
			if r.players.is_empty() and r.watchers.is_empty() and r.game == null:
				rooms.erase(r.code)
			else:
				_room_status(r)
		c.link.flush()
		c.link.close()
		return
	if r != null:
		r.players.erase(c)
		r.locked.erase(c.id)
	if c.check != null:
		# Left during the ready check: everyone else goes back to waiting.
		var k := c.check
		checks.erase(k)
		c.check = null
		for o: Client in k.players:
			if o != c:
				_requeue(o, MSG_LEFT)
	var g := c.game
	if r != null:
		_room_left(r, c)
	elif g != null and g.size > 1 and not g.others(c).is_empty():
		_cpu_takes_over(g, c)
	elif g != null:
		_report(g)
		games.erase(g)
		for w: Client in g.watchers:
			if clients.has(w.id):
				w.link.send({"t": "bye", "why": "over"}, true)
				w.link.flush()
				clients.erase(w.id)
				w.link.close()
			w.game = null
		g.watchers.clear()
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


# ------------------------------------------------------------------ a 1v1 rematch's pick

## The server's clock for the pick's countdown (tests skip it on).
func _now() -> int:
	return Time.get_ticks_msec() + clock_skip_ms


## A Quick match rematch's arena: drawn like a new pairing's, from the others.
func _draw_arena(last: String) -> String:
	var pool: Array = ArenaMap.IDS.filter(func(id): return id != last)
	if pool.is_empty():
		return last
	return String(pool[rng.randi_range(0, pool.size() - 1)])


## Both players of a 1v1 asked for a rematch: they pick again, against the countdown
## (the finished match keeps being refereed meanwhile, so nobody's session stalls).
func _open_pick(g: Game) -> void:
	g.picking = true
	g.picks = {}
	g.all_locked = false
	g.pick_deadline_ms = _now() + rematch_pick_ms
	_log("match %d: both want a rematch; picking fighters (%d s)" % [g.label, roundi(rematch_pick_ms / 1000.0)])
	_pick_status(g)


## The players and the match's spectators hear who has locked in (a room's status
## message, code "", players in slot order) and the seconds left. Never what anyone
## picked while someone is still choosing: `fighter` is their last match's. Once both
## are in (`all_locked`), the new fighters show for the last seconds.
func _pick_status(g: Game) -> void:
	var who: Array = []
	for c in g.players:
		var cl: Client = c
		var fighter := String(cl.team[0])
		if g.all_locked and g.picks.has(cl.slot):
			fighter = String(g.picks[cl.slot][0])
		who.append({"name": cl.name, "fighter": fighter, "locked": g.picks.has(cl.slot), "playing": false})
	var m := {"t": "room", "code": "", "state": "select", "players": who, "watchers": g.watchers.size(),
		"secs": maxf(0.0, float(g.pick_deadline_ms - _now()) / 1000.0), "all_locked": g.all_locked}
	for c: Client in g.humans() + g.watchers:
		if clients.has(c.id):
			c.link.send(m, true)


## A player locked in for the rematch: as many fighters as they had (three for a tag
## Duel), kept aside until the match starts. Once both have, the picks freeze and show,
## and the countdown drops to `rematch_locked_ms` (the rematch starts when it ends).
func _rematch_pick(c: Client, team) -> void:
	var g := c.game
	if g.all_locked or not Netplay.valid_team(team) or (team as Array).size() != c.team.size():
		return
	g.picks[c.slot] = (team as Array).duplicate()
	_log("%s locked in for the rematch" % c.label())
	if g.picks.size() >= g.humans().size():
		if rematch_locked_ms <= 0:
			_start(g)
			return
		g.all_locked = true
		g.pick_deadline_ms = mini(g.pick_deadline_ms, _now() + rematch_locked_ms)
		_log("match %d: both locked in; the rematch starts in %.1f s" % [g.label,
			float(g.pick_deadline_ms - _now()) / 1000.0])
	_pick_status(g)


## The pick's countdown ran out: whoever hasn't locked in keeps their last pick.
func _pick_timeout(g: Game) -> void:
	if not g.all_locked:
		_log("match %d: time's up for the rematch pick (%d of %d locked in); the rest keep their fighters" % [
			g.label, g.picks.size(), g.humans().size()])
	_start(g)


# ------------------------------------------------------------------ rooms

## The room for a code, made if it's new.
func _room(code: String) -> Room:
	if not rooms.has(code):
		var r := Room.new()
		r.code = code
		rooms[code] = r
	return rooms[code]


## A player with a room code said hello. Returns false if they were turned away (the
## room is full). Between (or during) a room's matches they wait in state ROOM for the
## next one, their hello's fighter as their pick; otherwise they wait to be grouped.
func _join_room(c: Client) -> bool:
	var r := _room(c.room)
	if not r.cfg_set and c.size > 0:
		# The first player to ask for a size makes the room what it is, for good.
		r.cfg_set = true
		r.size = c.size
		r.tag = c.team.size()
		r.rules = c.rules
		r.arena = c.arena
		r.maker = c.name
	if r.full():
		_refuse(c, "full", "Room %s is full. Pick Watch room to see its matches." % c.room.to_upper())
		return false
	if c.size == 0:
		c.size = r.size  # a friend joining by code takes the room's size
	if r.state != RoomState.WAITING and c.team.size() != r.tag:
		_refuse(c, "fighter", "Room %s plays %d fighters each." % [c.room.to_upper(), r.tag])
		return false
	r.players.append(c)
	if r.state != RoomState.WAITING:
		c.state = State.ROOM
		c.waiting_since = Time.get_ticks_msec()
		r.locked[c.id] = true
		_log("%s joined room '%s' between matches" % [c.label(), r.code])
		c.link.send({"t": "wait", "msg": "In room %s: you play in its next match. They're %s..." % [
			r.code.to_upper(), "playing" if r.state == RoomState.PLAYING else "picking fighters"]}, true)
		_send_ping(c)
		_room_status(r)
		_room_ready(r)
	else:
		_room_status(r)
	return true


## Everyone in the room (players and spectators) hears who's in it and what it's doing.
func _room_status(r: Room) -> void:
	var who: Array = []
	for c: Client in r.players:
		who.append({"name": c.name, "fighter": String(c.team[0]) if not c.team.is_empty() else "",
			"locked": r.locked.has(c.id), "playing": c.state == State.PLAYING and r.state == RoomState.PLAYING})
	var m := {"t": "room", "code": r.code, "state": ROOM_STATE_NAMES[r.state], "players": who,
		"watchers": r.watchers.size(), "size": r.size, "maker": r.maker}
	for c: Client in r.players + r.watchers:
		if clients.has(c.id):
			c.link.send(m, true)


## A player left the match-over for the fighter select: the room is picking now.
func _room_next(c: Client) -> void:
	var r: Room = rooms.get(c.room) if c.room != "" else null
	if r == null or c.watch or r.state == RoomState.WAITING or not (c in r.players):
		return
	r.locked.erase(c.id)
	if r.state == RoomState.PLAYING:
		r.state = RoomState.SELECT
		_log("room '%s' is picking fighters" % r.code)
	_room_status(r)


## A player locked in a fighter (a team for a tag Duel) for the room's next match.
func _room_pick(c: Client, team) -> void:
	var r: Room = rooms.get(c.room) if c.room != "" else null
	if r == null or c.watch or r.state == RoomState.WAITING or not (c in r.players):
		return
	if not Netplay.valid_team(team) or (team as Array).size() != r.tag:
		return
	c.team = (team as Array).duplicate()
	r.locked[c.id] = true
	if r.state == RoomState.PLAYING:
		r.state = RoomState.SELECT
	_log("%s locked in for room '%s'" % [c.label(), r.code])
	_room_status(r)
	_room_ready(r)


## Everyone in the room has locked in: the next match starts, re-seated.
func _room_ready(r: Room) -> void:
	if r.state != RoomState.SELECT or r.players.is_empty():
		return
	for c: Client in r.players:
		if not r.locked.has(c.id):
			return
	var old := r.game
	if old != null:
		_retire(old)
	r.game = null
	_begin_game(r.players.duplicate(), r.size, r.rules)


## A match that's over for good (its room moved on, or everyone left): reported and let
## go. Its spectators are detached (a room's are re-attached by the next match).
func _retire(g: Game) -> void:
	_report(g)
	games.erase(g)
	for w: Client in g.watchers:
		if w.game == g:
			w.game = null
	g.watchers.clear()
	for c in g.players:
		if c != null and (c as Client).game == g:
			(c as Client).game = null
	g.players.clear()  # players and game point at each other: break the loop


## A room player left (already out of r.players). The room carries on without them.
func _room_left(r: Room, c: Client) -> void:
	var g := c.game
	if r.players.is_empty():
		# The last one: the room closes, and its spectators are told so.
		if g != null:
			_retire(g)
		for w: Client in r.watchers.duplicate():
			if clients.has(w.id):
				w.link.send({"t": "bye", "why": "room"}, true)
				w.link.flush()
				clients.erase(w.id)
				w.link.close()
			w.game = null
		r.watchers.clear()
		rooms.erase(r.code)
		_log("room '%s' closed" % r.code)
		return
	if g != null and g == r.game and g.size > 1 and not g.others(c).is_empty():
		_cpu_takes_over(g, c)  # this match plays on; the next one has the slot open
	elif g != null and g == r.game and g.size == 1:
		# A 1v1 room: whoever is left waits for someone new, keeping the code.
		_retire(g)
		r.game = null
		r.state = RoomState.WAITING
		r.locked.clear()
		for o: Client in r.players:
			o.state = State.LOBBY
			o.game = null
			o.waiting_since = Time.get_ticks_msec()
			o.wait_shown = -1
			o.link.send({"t": "wait", "back": true,
				"msg": "Your opponent left. Waiting for a player: room code %s" % r.code.to_upper()}, true)
			_log("%s waits in room '%s' again" % [o.label(), r.code])
	elif g != null and g == r.game:
		# Nobody from that match is left (only newcomers waiting for the next): pick now.
		_retire(g)
		r.game = null
		r.state = RoomState.SELECT
	c.game = null
	_room_status(r)
	_room_ready(r)


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 200:
		log_lines.pop_front()
	if on_log.is_valid():
		on_log.call(s)
