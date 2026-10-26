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
##   rematch <------------------------------->  rematch   (both asked: pick again)
##   room {state "select", players} -------->              (the host's pick status)
##            <-------------------------------  pick {team}
##   start {teams, ...} --------------------->              (both locked in: the next match)
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
##
## Rooms on a server last between matches: "room" messages say what the room is doing
## (`room_state`: waiting, playing, select) and who's in it (`room_players`). After a
## match the game calls request_next() (this player is on the fighter select) and
## send_pick(team); the session stays in PLAYING meanwhile (the last match keeps
## stepping behind the select) until the next "start". If the other player of a 1v1
## room leaves, "wait" with `back` puts this session back to waiting (HANDSHAKE) in the
## same room.
##
## A 1v1 rematch outside a room (Quick match, ranked, direct host/join) goes through the
## fighter select too: once both players have asked, the server (or the direct host)
## says `room` {code "", state "select", players [slot 0, slot 1]}, the same status a
## room sends. rematch_pick() turns true, the game opens the select (the last pick
## ready to lock in), send_pick(team) answers, and the next "start" carries the new
## teams. The host plays the server's part on a direct link: it tracks both picks and
## starts the match once both are in. Team battles in Quick match still rematch with
## the same fighters.
##
## Picks stay hidden until both are in: the pick status only says who has locked in
## (`fighter` is still each player's fighter from the last match, and no `team` rides
## along); the fighters are revealed by "start". The status also carries `secs`, the
## seconds left on the pick's countdown (`rematch_pick_seconds` in data/online.json):
## when it runs out, the server (or the host) locks in anyone not in yet with their
## last pick and starts the match. A Quick match rematch on a server is on a new arena
## (in "start"); a direct one keeps the host's.

const NET_VERSION := 43  ## 43: CPUs roll over pits (CpuController._gap_roll), never end a dodge in one, and the nav grid lets a lone pit cell through (NavGrid.PIT_CELLS): the Daily's CPU and a leaver's CPU takeover play differently, so client and server must match; 42: the Floodgate's night lamps as real 2D lights (its arena JSON gains "lights": view only, but it changes data_hash); 41: assassin pass (Pete: ambush 1.2, Tiptoe haste 1.35 on a 7 s cooldown, Pickpocket steals 10% every 4 s, lights 5/5/7, Bag Swing recovery 18, 170 HP; Digby ambush 1.25; Cerebro blink 90 px, dodge cooldown 60, Mallet Toss recovery 30); 40: longer fights: every fighter's max_hp doubled (and Craglash's Stoneskin shield), single-target Surges deal double, area Surges 40% more, Thousand Cranes costs no sheets (fighter JSON, data_hash); 39: Normal-and-below CPU mages kite (CpuController._neutral_kite) and run kiters down (the "chase" plan): the Daily's CPU and a leaver's CPU takeover play differently, so client and server must match; 38: Mister Crease drawn at 37 px (0.54 scale, 96x96 frames; his sprite block, fx_top and ko_fx change data_hash); 37: no block chip (a hit blocked with stamina takes no health and gives no meter; guard.reduction removed from every fighter, which changes data_hash), exhaustion slows the walk for a moment (stamina.json exhaust_speed_mult, exhaust_slow_seconds; CreatureSim.exhaust_slow) and regen waits 3 s; Sneaky Pete lifesteal (fighter key lifesteal, MatchSim._lifesteal); 36: proximity voice chat ("vc" packets relayed by the server, hello "voice"); 35: the rolling boulders (several at once, ricocheting) and fault line hazards (hazards.json, mutators.json; hazard_hit `by` in MatchSim.note_credit); 34: Chef Cerebro kit pass (data keys stagger_if, projectile bounce, branches; the Mallet Toss staggers a tenderized foe, the Cleaver Toss bounces; CPU ai.setup / setup_routes); 33: player secrets (hello carries "secret"; the server refuses an id whose bound secret differs), the Daily board without ids ({name, score, you}), the Daily verified against the day's own CPU (its fight always on the stadium); 32: Team Deathmatch killing sprees and shutdowns, the Brawl crown (deathmatch.json and brawl.json keys, TeamSim streak / credit, BrawlSim crown, MatchSim.marks); 31: the Surge meter fills from combos (data/rules/energy.json per_type_mult and variety_energy: lights charge less, combos of several move types more); 30: shrines as a shared helper (src/sim/shrines.gd, data/rules/shrines.json; the "shrines" blocks of crater.json (permanent buffs, CreatureSim boost fields, MatchSim.shrine_rng) and brawl.json; Twin Keeps' three shrines; MatchSim.shrines; another PR may also bump: the second to merge renumbers); 29: arena hazards (data/rules/hazards.json, the tidal_wave and meteor_shower mutators; MatchSim.hazards); 28: reaction animations (hurt, guard and knockout rows in every fighter's JSON) and Cairn and the dummy as real rigs (their sprite blocks), which change data_hash; 27: diagonal 3/4 sheets (every fighter's JSON gains down_side and up_side views, which changes data_hash); 26: victory poses and idle variants for the roster, Crease batch 4 (folds, throws, Paper Plane), arena grade and ambient keys (fighter and arena JSON change data_hash); 25: roster animation pass (every fighter but Crease and Cairn gets new sheets and anim timelines in its JSON, which changes data_hash); 24: Rage CPU scored kit (ai.weights in Cerebro and Sno change data_hash); 23: assassin sneak engage (a hidden Burrow, ambush_ticks and the ambush_t state field, Storm Drain timing); 22: Surge energy rules (data/rules/energy.json: slower fill, meter carries between rounds), segment flag skip_struck, volley fan, widest-segment move_range; 21: a dodge cancels your own attack at a dearer cost (CreatureSim.can_dodge_cancel, stamina rules dodge_cancel_cost_mult); 20: Capture the Flag guards are the slots after a side's first (TeamSim._ctf_goals); 19: kit data pass (mage light reach, Digby Burrow and Pop-Up, Culvert HP and Gulp, Craglash, Gillbert, Barkley, Sno, roles); 18: on a crowded field hitstop is local to the attacker and target (CreatureSim.hitstop) and a KO neither freezes nor slows the match (MatchSim.freeze_all); 17: a Surge doesn't freeze a crowded field (2 v 2 and up, a Brawl of 3-4): it winds up instead (MatchSim.freeze_all); 16: 4 v 4 online (Capture the Flag: size up to the rules' "max_size"); 15: class perks (team rules "class_perks"), Caravan rockslides and escort healing; 14: Capture the Flag fumbles, passes (TAG), shrines, comeback rules and map bridges that fall in (MatchSim.bridges); 13: Caravan and Capture the Flag (team rules "caravan", "ctf"; maps of any size: a map's "size", "track", "bases"; sim.goals); 12: stamina rules (dearer dodge, block drain by move type, exhaustion at 0 drops the guard, regen pauses); 11: a 1v1 rematch outside rooms (Quick match, ranked, direct) picks again (room select status with secs, picks hidden until start, a countdown that locks in the last pick, Quick match draws a new arena; pick; ranked rates every game); 10: rooms last between matches (room, next, pick; wait back; bye room), Sinkhole collapses by rect and only a chasm fall is a ring-out; 9: the 1v1 is best of three rounds; 8: ranked play, player ids, daily scores; 7: team rules and tag Duels; 6: the server's ready check; 5: team battles; 4: 360 move angle
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
## The most frames a spectator takes from the server's log of a match in progress (an
## hour; a real match is minutes). A longer one is refused, not stepped.
const MAX_WATCH_LOG := 60 * 60 * 60

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
## Who this player is to a server: an id the game made once (settings) and a typed
## name. A session can carry its own (tests); otherwise the game's.
static var player_id := ""
static var player_name := "Player"
## What proves the id is this install's: 64 random hex characters made once (settings,
## next to the id), sent only to the server in hello, never shown. Losing it loses the
## ranked identity on servers that have seen it. Empty until the game loads it;
## secret() makes one for this run if nothing did (tests, tools).
static var player_secret := ""
var my_id := ""
var my_name := ""
var my_secret := ""
## Ranked: ask the server for a rated 1v1 within a rating band; the server's answer
## after the match ({old, new, rd, games, wins}).
var ranked := false
var last_rating := {}
var ratings_heard := 0  ## rating messages this session (every ranked game is rated)
## A room on a server: what it's doing ("" until the server says; "waiting", "playing",
## "select"), who's in it ([{name, fighter, locked, playing}]) and how many watch.
var room_state := ""
var room_players: Array = []
var room_watchers := 0
## This player left the match-over for the room's fighter select, and has locked in.
var picking := false
var picked := false
## Hosting a direct match: the joiner's name (from hello), and who has locked in for a
## rematch (by side) while picking.
var their_name := "Player"
var _locked := [false, false]
## A rematch pick's countdown: the seconds left when the last pick status came, and
## when that was (0: no countdown, as in a room's select). Hosting, the host runs it in
## ticks (`pick_ticks`; -1: rematch_pick_seconds() at 60 a second, tests shorten it).
var pick_secs := 0.0
var _pick_secs_ms := 0
var pick_ticks := -1
## Hosting: the countdown once both have locked in, in ticks (-1: rematch_locked_seconds()
## at 60 a second; tests shorten it).
var locked_ticks := -1
## Both players have locked in: the picks are frozen and shown (the status's `all_locked`;
## hosting, the host's own record of it).
var pick_all_locked := false
var _pick_until := 0
## Proximity voice chat: the "vc" packets of the match on now (VoiceChat checks the
## sender and the size; this checks the match). The game sets `voice.mode` from its
## setting, feeds the microphone in and plays the queues (src/view/voice_view.gd).
var voice := VoiceChat.new()
## Each slot's player name in the match on now ("" unknown, "CPU" for a CPU's), from
## "start": the voice chat mutes by name (VoiceChat.blocked), so a room's re-seating
## or a rematch keeps a muted player muted.
var player_names: Array = []

## What a player is told when the other player of a 1v1 leaves.
const OPPONENT_LEFT := "Your opponent left"
const PICK_SECONDS_DEFAULT := 20.0
const LOCKED_SECONDS_DEFAULT := 3.0


## The rematch pick's countdown, from data/online.json (`rematch_pick_seconds`): the
## server and the direct host both read it.
static func rematch_pick_seconds() -> float:
	return clampf(float(_online_data().get("rematch_pick_seconds", PICK_SECONDS_DEFAULT)), 1.0, 600.0)


## Once both have locked in, the countdown drops to this (`rematch_locked_seconds`,
## 3): both fighters show, the picks are frozen, then the rematch starts. 0 starts it
## at once.
static func rematch_locked_seconds() -> float:
	return clampf(float(_online_data().get("rematch_locked_seconds", LOCKED_SECONDS_DEFAULT)), 0.0, 60.0)


static func _online_data() -> Dictionary:
	var f := FileAccess.open("res://data/online.json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## Seconds left on a rematch pick's countdown (0 when there is none).
func pick_seconds_left() -> float:
	if room_state != "select" or pick_secs <= 0.0:
		return 0.0
	return maxf(0.0, pick_secs - float(Time.get_ticks_msec() - _pick_secs_ms) / 1000.0)


## A fresh player id: 16 hex characters from the system's random source.
static func make_player_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in 16:
		s += "0123456789abcdef"[rng.randi_range(0, 15)]
	return s


## A fresh player secret: 32 bytes from the system's cryptographic random source, as hex.
static func make_secret() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()


## Whether `s` looks like a player secret (what the server accepts).
static func valid_secret(s: String) -> bool:
	if s.length() < 32 or s.length() > 128:
		return false
	for ch in s:
		if not "0123456789abcdef".contains(ch):
			return false
	return true


## This install's secret (made for this run if the game hasn't loaded one).
static func secret() -> String:
	if not valid_secret(player_secret):
		player_secret = make_secret()
	return player_secret


## A typed name made safe to show: no control, invisible or direction-changing
## characters, runs of spaces as one, trimmed, at most NAME_MAX characters; "Player" if
## nothing is left. The server cleans every name it hears (players can't trust each other's).
const NAME_MAX := 16
## A "start"'s `names`, made safe: an Array of `players` Strings, each cleaned (an empty
## one stays "": unknown). Anything else is all "".
static func names_from(v, players: int) -> Array:
	var out: Array = []
	out.resize(players)
	out.fill("")
	if not (v is Array) or (v as Array).size() != players:
		return out
	for k in players:
		if not ((v as Array)[k] is String):
			out.fill("")
			return out
		var s := String((v as Array)[k])
		out[k] = clean_name(s) if s.strip_edges() != "" else ""
	return out


static func clean_name(s: String) -> String:
	var out := ""
	var space := false
	for ch in s:
		var u := ch.unicode_at(0)
		if u == 0x00AD or u == 0x061C or u == 0x180E or (u >= 0x200B and u <= 0x200F) \
				or (u >= 0x202A and u <= 0x202E) or (u >= 0x2060 and u <= 0x206F) or u == 0xFEFF \
				or (u >= 0xFFF0 and u <= 0xFFFF) or (u >= 0xD800 and u <= 0xDFFF) or (u >= 0xE0000 and u <= 0xE007F):
			continue  # invisible or direction-changing (format characters): gone
		if u < 32 or (u >= 127 and u < 160) or u == 0x2028 or u == 0x2029:
			u = 32  # a control character or a line break: a space at most
		if u == 32 or u == 0x3000 or u == 0x00A0:
			space = true
			continue
		if space and out != "":
			out += " "
		space = false
		out += ch
	out = out.left(NAME_MAX).strip_edges()
	return out if out != "" else "Player"


func _my_id() -> String:
	return my_id if my_id != "" else player_id


func _my_secret() -> String:
	return my_secret if my_secret != "" else secret()


func _my_name() -> String:
	return my_name if my_name != "" else player_name
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
		e.max_packet = NetLink.SMALL_PACKET  # every direct-play message is far smaller
		if e.host(port) != OK:
			return _fail(e.error)
		link = e
	voice.link = link
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
		# A player's messages from a host or a server are all small; a spectator's first
		# "start" carries the match's whole log so far, so it takes any size.
		if not watching:
			e.max_packet = NetLink.SMALL_PACKET
		if e.join(address, port) != OK:
			return _fail(e.error)
		link = e
	voice.link = link
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
			var why := link.error if link.error != "" else "Connection lost"
			if not watching:
				why = why.replace("The other player left", OPPONENT_LEFT)  # a player hears "Your opponent left"
			_fail(why)
		return
	match phase:
		Phase.CONNECTING:
			if link.status == NetLink.Status.CONNECTED:
				var hello := {"t": "hello", "v": NET_VERSION, "data": data_hash(), "team": my_team, "room": room,
					"size": team_size, "rules": rules_id, "watch": watching, "arena": arena_id,
					"name": _my_name(), "ranked": ranked, "voice": voice.mode != VoiceChat.Mode.OFF}
				if ranked:
					# Who this player is goes only where it counts (ranked, on a server): never to
					# a direct host or for an unrated match.
					hello["id"] = _my_id()
					hello["secret"] = _my_secret()
				link.send(hello, true)
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
			if hosting and rematch_local and rematch_remote and room_state != "select":
				_host_open_pick()
			elif hosting and room_state == "select" and _t >= _pick_until:
				_host_pick_timeout()
	link.flush()


## Ask for a rematch. Once both players have asked, a 1v1 goes to the fighter select
## (rematch_pick()); a team battle starts again with the same fighters. Not in a room
## (it picks again with request_next instead).
func request_rematch() -> void:
	if phase != Phase.PLAYING or rematch_local or in_room() or watching:
		return
	rematch_local = true
	link.send({"t": "rematch"}, true)
	link.flush()


## Playing in a room on a server (not watching): matches there end in a fighter select.
func in_room() -> bool:
	return room != "" and not hosting and not watching


## Both players asked for a 1v1 rematch outside a room, and the server (or the host)
## is waiting for this player's pick: the game shows the fighter select.
func rematch_pick() -> bool:
	return phase == Phase.PLAYING and not in_room() and not watching and room_state == "select"


## A room's match is over and this player is picking for the next: the server marks
## them as not locked in yet. The last match keeps stepping until the next starts.
func request_next() -> void:
	if not in_room() or phase != Phase.PLAYING:
		return
	picking = true
	picked = false
	link.send({"t": "next"}, true)
	link.flush()


## Locked in for the room's next match (it starts once everyone in the room has), or
## for a rematch (the same number of fighters as before: three for a tag Duel).
func send_pick(team: Array) -> void:
	if phase != Phase.PLAYING or not _valid_team(team):
		return
	if not in_room() and not (rematch_pick() and (team as Array).size() == my_team.size()):
		return
	if not in_room() and pick_all_locked:
		return  # both are in: the picks are frozen for the last seconds
	my_team = team.duplicate()
	picking = true
	picked = true
	if hosting:
		_locked[0] = true
		_host_pick_status()
		_host_try_start()
		return
	link.send({"t": "pick", "team": my_team}, true)
	link.flush()


## Hosting a direct match: both asked for a rematch, so both pick again, against the
## countdown.
func _host_open_pick() -> void:
	_locked = [false, false]
	pick_all_locked = false
	picking = true
	picked = false
	_pick_until = _t + (pick_ticks if pick_ticks >= 0 else roundi(rematch_pick_seconds() * 60.0))
	_host_pick_status()


## Hosting: the countdown ran out. Whoever hasn't locked in keeps their last pick
## (my_team / their_team only change when a pick comes in), and the match starts.
func _host_pick_timeout() -> void:
	_locked = [true, true]
	_start_match()


## Hosting: the pick status, here and to the joiner (a room's "room" message, code "").
## Only who has locked in: `fighter` is each one's from the last match, so neither
## pick is seen until both are in; then (`all_locked`) both new fighters show for the
## last seconds, and "start" follows.
func _host_pick_status() -> void:
	var who: Array = []
	var names := [_my_name(), their_name]
	var last: Array = [my_team, their_team] if pick_all_locked or game == null else game.teams
	for side in 2:
		who.append({"name": String(names[side]), "fighter": String(last[side][0]), "locked": bool(_locked[side]),
			"playing": false})
	var m := {"t": "room", "code": "", "state": "select", "players": who, "watchers": 0,
		"secs": maxf(0.0, float(_pick_until - _t) / 60.0), "all_locked": pick_all_locked}
	_room_status(m)
	link.send(m, true)
	link.flush()


## Hosting: both locked in. The picks freeze and show, and the countdown drops to
## rematch_locked_seconds (if less is left, it stays); the tick loop starts the rematch
## when it runs out (at once with 0).
func _host_try_start() -> void:
	if not (_locked[0] and _locked[1]) or pick_all_locked:
		return
	pick_all_locked = true
	var last := locked_ticks if locked_ticks >= 0 else roundi(rematch_locked_seconds() * 60.0)
	if last <= 0:
		_start_match()
		return
	_pick_until = mini(_pick_until, _t + last)
	_host_pick_status()


## The room's players who haven't locked in yet (names), and who has.
func room_waiting_on() -> Array:
	return room_players.filter(func(p): return not bool(p.get("locked", false))).map(func(p): return String(p.get("name", "")))


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
			if NetLink.int_of(m.get("v", -1), -1) != NET_VERSION or str(m.get("data", "")) != data_hash():
				link.send({"t": "reject", "why": "version"}, true)
				link.flush()
				_fail("The other player has a different version of the game. Both need the same build.")
				return
			var team = m.get("team")
			if not _valid_team(team):
				_fail("The other player picked a fighter this build doesn't have.")
				return
			their_team = team
			their_name = clean_name(String(m.get("name", "Player")) if m.get("name") is String else "Player")
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
				if bool(m.get("back", false)) and phase == Phase.PLAYING and not watching:
					# The other player left the room: wait there for someone new.
					game = null
					phase = Phase.HANDSHAKE
					picking = false
					picked = false
		"room":
			if hosting:
				return
			var was := room_state
			_room_status(m)
			if room_state == "select" and was != "select" and rematch_pick():
				picking = true  # both asked for a rematch: pick for it
				picked = false
		"rating":
			ratings_heard += 1
			last_rating = {"old": float(m.get("old", 0.0)), "new": float(m.get("new", 0.0)), "rd": float(m.get("rd", 0.0)),
				"games": int(m.get("games", 0)), "wins": int(m.get("wins", 0))}
		"found":
			if hosting or phase == Phase.PLAYING:
				return
			via_server = true
			match_found = true
			accepted = false
			found_size = clampi(int(m.get("size", 1)), 1, TeamSim.MOST_PER_SIDE)
			found_need = clampi(int(m.get("need", found_size * 2)), 2, TeamSim.MOST_PER_SIDE * 2)
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
			var size := NetLink.int_of(m.get("size", 1), 1, 1, TeamSim.MOST_PER_SIDE)
			if not (teams is Array) or (teams as Array).size() != 2 or not _valid_side(teams[0]) \
					or not _valid_side(teams[1]) or (size > 1 and ((teams[0] as Array).size() != size
					or (teams[1] as Array).size() != size)):
				_fail("Bad match setup from the host")
				return
			var slot := 1
			if m.has("side"):  # from a dedicated server, which picks the sides
				via_server = true
				slot = NetLink.int_of(m.get("slot", m["side"]), 0, 0, size * 2 - 1)
			ping_ms = NetLink.float_of(m.get("ping", 0.0), 0.0, 0.0, 5000.0)
			var rules := str(m.get("rules", ""))
			var arena := str(m.get("arena", ArenaMap.DEFAULT))
			if not (rules in TeamSim.RULE_IDS) or not ArenaMap.known(arena):
				_fail("Bad match setup from the host")
				return
			rules_id = rules
			arena_id = arena
			player_names = names_from(m.get("names"), size * 2)
			_begin(NetLink.int_of(m.get("n", 0)), teams, start_delay(m), slot, size, rules, arena)
			if size == 1 and String(player_names[1 - local_slot]) != "":
				their_name = String(player_names[1 - local_slot])
			their_team = teams[1 - local_side]
			if size == 1:
				my_team = (teams[local_side] as Array).duplicate()
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
		"pick":  # hosting a direct match: the joiner locked in for the rematch
			if not hosting or room_state != "select" or phase != Phase.PLAYING or pick_all_locked:
				return
			var team = m.get("team")
			if not _valid_team(team) or (team as Array).size() != their_team.size():
				return
			their_team = (team as Array).duplicate()
			_locked[1] = true
			_host_pick_status()
			_host_try_start()
		"rematch":
			rematch_remote = true
			rematch_asked[int(m.get("p", 1 - local_slot))] = true
		"bye":
			match String(m.get("why", "")):
				"server":
					_fail("The server shut down")
				"player":
					_fail("A player left the match")
				"room":
					_fail("The room closed: everyone left")
				"over":
					_fail("The match ended: its players left")
				_:
					_fail(OPPONENT_LEFT)
		"vc":  # someone's voice: only the match on now's (a rematch's old packets never play)
			var vn := NetLink.int_of(m.get("n", -1), -1)
			if watch != null:
				if vn == _watch_n:
					voice.receive(m)
			elif game != null and vn == game.id:
				voice.receive(m)
		"in", "dg":
			if watch != null:
				if str(m.get("t", "")) == "in" and NetLink.int_of(m.get("n", -1), -1) == _watch_n:
					watch.add_inputs(NetLink.int_of(m.get("p", 0), 0, 0, watch.players - 1), m)
			elif game != null and NetLink.int_of(m.get("n", -1), -1) == game.id:
				game.receive(m)


var _watch_n := 0


## A "room" status (a room's, or a 1v1 rematch's pick): what it's doing and who's in it.
func _room_status(m: Dictionary) -> void:
	room_state = String(m.get("state", ""))
	var who = m.get("players", [])
	room_players = []
	if who is Array:
		for p in who:
			if p is Dictionary:
				var e := {"name": clean_name(str(p.get("name", "Player"))),
					"fighter": String(p.get("fighter", "")), "locked": bool(p.get("locked", false)),
					"playing": bool(p.get("playing", false))}
				room_players.append(e)
	room_watchers = maxi(0, int(m.get("watchers", 0)))
	pick_secs = clampf(float(m.get("secs", 0.0)), 0.0, 600.0)
	_pick_secs_ms = Time.get_ticks_msec()
	pick_all_locked = bool(m.get("all_locked", false))


## The server put this spectator on a match: build a referee's copy of it and feed it
## everything stepped so far.
func _start_watching(m: Dictionary) -> void:
	var teams = m.get("teams")
	var size := NetLink.int_of(m.get("size", 1), 1, 1, TeamSim.MOST_PER_SIDE)
	var rules := str(m.get("rules", ""))
	var arena := str(m.get("arena", ArenaMap.DEFAULT))
	var rows = m.get("log", [])
	if not (teams is Array) or (teams as Array).size() != 2 or not _valid_side(teams[0]) \
			or not _valid_side(teams[1]) or not (rules in TeamSim.RULE_IDS) or not ArenaMap.known(arena) \
			or (size > 1 and ((teams[0] as Array).size() != size or (teams[1] as Array).size() != size)) \
			or not (rows is Array) or (rows as Array).size() > MAX_WATCH_LOG:
		_fail("Bad match setup from the server")
		return
	via_server = true
	match_found = false
	_watch_n = NetLink.int_of(m.get("n", 0))
	arena_id = arena
	if room == "":
		room_state = ""  # a rematch's pick is over
		room_players = []
	watch = Referee.new(teams, start_delay(m), size, rules, arena, _watch_n)
	watch.feed_log(rows)
	player_names = names_from(m.get("names"), size * 2)
	voice.reset(_watch_n, -1, player_names)  # a spectator listens, never talks
	phase = Phase.PLAYING
	status = "Watching"


## The input delay a "start" asks for, clamped to what a session takes (a host or server
## asking for millions of frames would otherwise freeze this machine building them).
static func start_delay(m: Dictionary) -> int:
	return NetLink.int_of(m.get("delay", 2), 2, 0, RollbackSession.MAX_INPUT_DELAY)


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
	player_names = [_my_name(), their_name]  # the joiner's from its hello
	link.send({"t": "start", "n": _match_count, "teams": teams, "delay": delay, "ping": ping_ms,
		"rules": rules_id, "arena": arena_id, "names": player_names}, true)
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
	voice.reset(n, local_slot, player_names)  # nothing from the last match plays into this one
	rematch_local = false
	rematch_remote = false
	rematch_asked = {}
	picking = false
	picked = false
	_locked = [false, false]
	last_rating = {}
	if not in_room():
		room_state = ""  # a rematch's pick is over
		room_players = []
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


## One side of a match as "start" lists it: up to four fighters (a 4 v 4).
func _valid_side(team) -> bool:
	return valid_team(team, TeamSim.MOST_PER_SIDE)


## A player's pick: one fighter, or three for a tag Duel (`most`: the longest allowed).
static func valid_team(team, most := 3) -> bool:
	if not (team is Array) or (team as Array).is_empty() or (team as Array).size() > most:
		return false
	for id in team:
		if not (id is String or id is StringName) or not (String(id) in MatchFactory.FIGHTERS):
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


## A fingerprint of the game data both machines must share: every fighter's file, arena and
## rules file. Different data would make the two simulations disagree.
static func data_hash() -> String:
	if _data_hash == "":
		_data_hash = _hash_data()  # the files never change while the game runs: once is enough
	return _data_hash


static var _data_hash := ""


static func _hash_data() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("v%d" % NET_VERSION).to_utf8_buffer())
	var paths: Array = [DuelSim.RULES_PATH, DuelSim.RULES_1V1_PATH, TeamSim.RULES_PATH, TeamSim.DEATHMATCH_PATH, TeamSim.SINKHOLE_PATH,
		TeamSim.CRATER_PATH, TeamSim.CARAVAN_PATH, TeamSim.CTF_PATH, BrawlSim.RULES_PATH, Daily.MUTATORS_PATH, CreatureSim.STAMINA_PATH,
		MatchSim.PROJECTILES_PATH, MatchSim.ENERGY_PATH, Hazards.PATH, Shrines.PATH]
	for id in MatchFactory.FIGHTERS:
		paths.append(MatchFactory.CREATURE_DIR + id + ".json")
	for id in ArenaMap.IDS + ArenaMap.MODE_IDS:
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
