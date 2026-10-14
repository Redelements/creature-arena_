extends TestCase
## The dedicated server: players join it like a host, it pairs them (by room), relays
## their matches, referees them with its own simulation, and cleans up when they leave.

const TEAM_A := ["cairn"]
const TEAM_B := ["culvert"]
const TEAM_C := ["sno"]


## A server and `teams.size()` players joined to it over in-memory links.
func _setup(teams: Array, rooms: Array = [], lag := 0, jitter := 0, loss := 0.0) -> Array:
	var server := RelayServer.new()
	var nets: Array = []
	for i in teams.size():
		var links := LoopLink.pair(lag, jitter, loss, 7 + i * 10)
		server.add_client(links[0], "test:%d" % i)
		var n := Netplay.new()
		if i < rooms.size():
			n.room = String(rooms[i])
		n.join("server", 0, teams[i], links[1])
		nets.append(n)
	return [server, nets]


## Ticks every player and the server until `cond` holds.
func _run(server: RelayServer, nets: Array, ticks: int, cond: Callable = Callable(),
		inputs: Callable = Callable()) -> bool:
	for i in ticks:
		for k in nets.size():
			var bits := int(inputs.call(k, i)) if inputs.is_valid() else 0
			(nets[k] as Netplay).tick(bits)
		server.tick()
		if cond.is_valid() and cond.call():
			return true
	return not cond.is_valid()


func _mash(seed_: int) -> Callable:
	var rngs := [RandomNumberGenerator.new(), RandomNumberGenerator.new(), RandomNumberGenerator.new()]
	for k in 3:
		rngs[k].seed = seed_ + 100 * k
	var hold := [0, 0, 0]
	return func(k: int, i: int) -> int:
		if i % 7 == 0:
			hold[k] = rngs[k].randi() & (SimDefs.IN_ALL & ~SimDefs.IN_TAG)
		return hold[k]


func _both_playing(nets: Array) -> bool:
	return (nets[0] as Netplay).is_playing() and (nets[1] as Netplay).is_playing()


func test_two_players_are_paired_and_start_the_same_match() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	assert_true(_run(server, nets, 200, func(): return _both_playing(nets)), "both start playing")
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	assert_true(a.via_server and b.via_server, "both know they're on a server")
	assert_eq(a.game.local_side + b.game.local_side, 1, "one plays each side:")
	assert_eq(a.game.teams, b.game.teams, "the same teams:")
	assert_eq(a.game.teams[a.game.local_side], TEAM_A, "each plays their own fighter:")
	assert_eq(b.game.teams[b.game.local_side], TEAM_B, "")
	assert_eq(a.game.input_delay, b.game.input_delay, "the same input delay:")
	assert_eq(server.games.size(), 1, "the server runs one match:")


func test_a_lone_player_waits_on_the_server() -> void:
	var s := _setup([TEAM_A])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	_run(server, nets, 100)
	var a: Netplay = nets[0]
	assert_eq(a.phase, Netplay.Phase.HANDSHAKE, "still setting up:")
	assert_true(a.status.contains("Waiting for an opponent"), "and says so: " + a.status)


func test_a_laggy_match_through_the_server_stays_in_sync_and_the_referee_agrees() -> void:
	var s := _setup([TEAM_A, TEAM_B], [], 3, 2, 0.1)
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	_run(server, nets, 300, func(): return _both_playing(nets))
	_run(server, nets, 1500, Callable(), _mash(11))
	var a: OnlineMatch = (nets[0] as Netplay).game
	var b: OnlineMatch = (nets[1] as Netplay).game
	assert_eq(a.desync_frame, -1, "no desync for player A")
	assert_eq(b.desync_frame, -1, "no desync for player B")
	assert_gt(float(a.digests_matched), 15.0, "the players compared fingerprints:")
	var ref: Referee = (server.games[0] as RelayServer.Game).referee
	assert_eq(ref.desync, [-1, -1], "the referee agrees with both:")
	assert_gt(float(ref.checked), 30.0, "having checked their fingerprints all match:")
	assert_gt(float(ref.frame), 1300.0, "its copy kept up:")


func test_the_referee_spots_which_player_went_wrong() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	_run(server, nets, 200, func(): return _both_playing(nets))
	_run(server, nets, 150, Callable(), _mash(3))
	var b: Netplay = nets[1]
	b.game.duel.active_creature(0).hp -= 5.0  # a bug on B's machine only
	_run(server, nets, 400, Callable(), _mash(4))
	var ref: Referee = (server.games[0] as RelayServer.Game).referee
	assert_gt(float(ref.desync[b.game.local_side]), 0.0, "B's game is the wrong one")
	assert_eq(ref.desync[1 - b.game.local_side], -1, "A's is fine")


func test_rooms_pair_friends_with_each_other() -> void:
	var s := _setup([TEAM_A, TEAM_B, TEAM_C], ["kev", "", "KEV"])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	var c: Netplay = nets[2]
	_run(server, nets, 200, func(): return a.is_playing() and c.is_playing())
	assert_true(a.is_playing() and c.is_playing(), "the two in room kev play each other")
	assert_eq(a.game.teams, c.game.teams, "the same match:")
	assert_false(b.is_playing(), "the player with no room waits for someone else")


## Like _run, but with a short pause each tick, for the server's ready-check clock.
func _run_slow(server: RelayServer, nets: Array, ticks: int, cond: Callable = Callable()) -> bool:
	for i in ticks:
		for n: Netplay in nets:
			n.tick(0)
		server.tick()
		if cond.is_valid() and cond.call():
			return true
		OS.delay_msec(4)
	return not cond.is_valid()


## Two players whose game asks them before accepting (as the real menus do).
func _asking_setup() -> Array:
	var s := _setup([TEAM_A, TEAM_B])
	for n: Netplay in s[1]:
		n.auto_ready = false
	return s


func test_a_match_found_waits_for_everyone_to_accept() -> void:
	var s := _asking_setup()
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	assert_true(_run(server, nets, 200, func(): return a.match_found and b.match_found), "both hear a match was found")
	assert_eq(a.status, "Match found!", "and are told:")
	assert_gt(a.seconds_left(), 5.0, "with time to accept:")
	_run(server, nets, 40)
	assert_false(_both_playing(nets), "nothing starts until they accept")
	assert_eq(server.games.size(), 0, "")
	a.accept_match()
	_run(server, nets, 40)
	assert_false(_both_playing(nets), "one accepting isn't enough")
	assert_eq(b.accepted_have, 1, "the other sees one of two in:")
	b.accept_match()
	assert_true(_run(server, nets, 60, func(): return _both_playing(nets)), "both accepted: the match starts")
	assert_false(a.match_found or b.match_found, "and the ready check is over")


func test_time_running_out_requeues_who_accepted_and_drops_who_didnt() -> void:
	var s := _asking_setup()
	var server: RelayServer = s[0]
	server.ready_ms = 200
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	_run(server, nets, 200, func(): return a.match_found and b.match_found)
	a.accept_match()
	_run_slow(server, nets, 150, func(): return b.phase == Netplay.Phase.ENDED)
	assert_eq(b.phase, Netplay.Phase.ENDED, "the one who never accepted is let go:")
	assert_true(b.error.contains("didn't accept"), "and told why: " + b.error)
	assert_false(a.match_found, "the one who accepted goes back to searching")
	assert_eq(a.phase, Netplay.Phase.HANDSHAKE, "still on the server:")
	assert_true(a.status.contains("Back to searching"), "and says so: " + a.status)
	assert_eq(server.player_count(), 1, "the server keeps only them:")
	# Someone new arrives: the player who waited gets a match again.
	var links := LoopLink.pair()
	server.add_client(links[0])
	var c := Netplay.new()
	c.join("server", 0, TEAM_C, links[1])
	nets = [a, c]
	assert_true(_run(server, nets, 200, func(): return a.match_found), "the requeued player is found a match again")
	a.accept_match()
	assert_true(_run(server, nets, 100, func(): return a.is_playing() and c.is_playing()),
		"and plays the next player once they accept")


func test_declining_sends_the_other_player_back_to_searching() -> void:
	var s := _asking_setup()
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	_run(server, nets, 200, func(): return a.match_found and b.match_found)
	a.accept_match()
	b.decline_match()
	assert_eq(b.phase, Netplay.Phase.ENDED, "declining leaves:")
	assert_true(b.declined and b.error.contains("declined"), "and says so: " + b.error)
	_run(server, nets, 20)
	assert_false(a.match_found, "the other is back to searching")
	assert_true(a.status.contains("left before the match"), "and told why: " + a.status)
	assert_eq(server.games.size(), 0, "no match started:")
	assert_eq(server.checks.size(), 0, "and no ready check is left over:")


func test_rematch_through_the_server() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	_run(server, nets, 200, func(): return _both_playing(nets))
	_run(server, nets, 60, Callable(), _mash(8))
	var first := a.game
	a.request_rematch()
	_run(server, nets, 20)
	assert_true(b.rematch_remote, "B hears that A wants a rematch")
	assert_true(a.game == first, "one ask isn't enough")
	b.request_rematch()
	_run(server, nets, 40, func(): return a.game != first and b.game.id == a.game.id)
	assert_eq(a.game.id, 2, "a second match:")
	assert_eq(b.game.id, 2, "on both sides:")
	_run(server, nets, 300, Callable(), _mash(9))
	assert_eq(a.game.desync_frame, -1, "the rematch is in sync too")
	assert_eq(server.matches_started, 2, "the server counted both:")


func test_leaving_ends_the_match_for_the_opponent_and_frees_the_server() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	_run(server, nets, 200, func(): return _both_playing(nets))
	(nets[1] as Netplay).leave()
	_run(server, nets, 10)
	assert_eq(a.phase, Netplay.Phase.ENDED, "A's session ends:")
	assert_true(a.error.contains("left"), "and says why: " + a.error)
	assert_eq(server.player_count(), 0, "the server let both go:")
	assert_eq(server.games.size(), 0, "and the match:")


func test_a_different_build_is_refused_with_a_reason() -> void:
	var server := RelayServer.new()
	var links := LoopLink.pair()
	server.add_client(links[0])
	links[1].send({"t": "hello", "v": Netplay.NET_VERSION, "data": "not-the-same", "team": TEAM_A}, true)
	server.tick()
	var got: Array = links[1].poll()
	assert_eq(got.size(), 1, "one answer:")
	assert_eq(String(got[0].get("t")), "reject", "a refusal:")
	assert_true(String(got[0].get("msg")).contains("version"), "that says why")
	assert_eq(server.player_count(), 0, "and the player is let go")


func test_a_refusal_reaches_the_player() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	server.max_players = 2
	var nets: Array = s[1]
	var links := LoopLink.pair()
	server.add_client(links[0])
	var late := Netplay.new()
	late.join("server", 0, TEAM_C, links[1])
	nets.append(late)
	_run(server, nets, 20)
	assert_eq(late.phase, Netplay.Phase.ENDED, "a third player on a 2-player server is turned away:")
	assert_true(late.error.contains("full"), "told it's full: " + late.error)


func test_a_silent_connection_is_dropped() -> void:
	var server := RelayServer.new()
	server.hello_timeout_ms = 0
	var links := LoopLink.pair()
	server.add_client(links[0])
	OS.delay_msec(2)
	server.tick()
	assert_eq(server.player_count(), 0, "no hello, no seat:")


func test_junk_inputs_are_not_relayed() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	_run(server, nets, 200, func(): return _both_playing(nets))
	var g: RelayServer.Game = server.games[0]
	var cheat: RelayServer.Client = g.players[0]
	var big := PackedInt32Array()
	big.resize(5000)
	(cheat.link as LoopLink).other.send({"t": "in", "n": g.n, "first": 0, "inputs": big}, false)
	(cheat.link as LoopLink).other.send({"t": "in", "n": g.n, "first": 9999999, "inputs": PackedInt32Array([1])}, false)
	var victim: LoopLink = ((g.players[1] as RelayServer.Client).link as LoopLink).other
	server.tick()
	var relayed := 0
	for m in victim.poll():
		if String(m.get("t")) == "in" and (m["inputs"] as PackedInt32Array).size() > RollbackSession.MAX_PACKET_INPUTS:
			relayed += 1
		if String(m.get("t")) == "in" and int(m["first"]) == 9999999:
			relayed += 1
	assert_eq(relayed, 0, "nothing oversized or far-fetched gets through:")


func test_the_referee_records_the_result() -> void:
	var ref := Referee.new([TEAM_A, TEAM_B], 0)
	ref.duel.active_creature(1).hp = 0.5
	var mash := _mash(1)
	for i in 3000:
		ref.add_inputs(0, {"first": i, "inputs": PackedInt32Array([SimDefs.IN_LIGHT if i % 2 == 0 else 0])})
		ref.add_inputs(1, {"first": i, "inputs": PackedInt32Array([0])})
		ref.advance()
		if ref.winner != -2:
			break
	assert_eq(ref.winner, 0, "a fighter on half a hit point loses to jabs:")


func test_over_real_udp_through_a_server_on_this_machine() -> void:
	var port := 20000 + (Time.get_ticks_usec() % 20000)
	var hub := EnetHub.new()
	assert_eq(hub.listen(port, 8), OK, "server on UDP %d: %s" % [port, hub.error])
	var server := RelayServer.new()
	var a := Netplay.new()
	var b := Netplay.new()
	assert_true(a.join("127.0.0.1", port, TEAM_A), "A joins: " + a.error)
	assert_true(b.join("127.0.0.1", port, TEAM_B), "B joins: " + b.error)
	var nets := [a, b]
	var step := func(bits_a: int, bits_b: int) -> void:
		a.tick(bits_a)
		b.tick(bits_b)
		for l in hub.poll():
			server.add_client(l, (l as EnetHub.PeerLink).address)
		server.tick()
		hub.flush()
	var started := false
	for i in 800:
		step.call(0, 0)
		if _both_playing(nets):
			started = true
			break
		OS.delay_usec(2000)
	assert_true(started, "both paired and playing over UDP (%s / %s)" % [a.status, b.status])
	if started:
		var mash := _mash(2)
		for i in 900:
			step.call(mash.call(0, i), mash.call(1, i))
			OS.delay_usec(300)
		assert_eq(a.game.desync_frame, -1, "no desync over UDP")
		assert_gt(float(a.game.digests_matched), 8.0, "fingerprints compared:")
		var ref: Referee = (server.games[0] as RelayServer.Game).referee
		assert_eq(ref.desync, [-1, -1], "the referee agrees:")
		assert_gt(float(ref.checked), 8.0, "after checking:")
		b.leave()
		for i in 200:
			step.call(0, 0)
			if a.phase == Netplay.Phase.ENDED:
				break
			OS.delay_usec(2000)
		assert_eq(a.phase, Netplay.Phase.ENDED, "A sees B leave:")
	a.leave()
	b.leave()
	server.shutdown()
	hub.close()


func test_a_game_finds_the_server_on_its_own_network() -> void:
	var port := 20000 + (Time.get_ticks_usec() % 20000)
	var beacon := ServerBeacon.new()
	assert_true(beacon.listen(port), "the beacon listens on %d: %s" % [port + 1, beacon.error])
	var finder := LanFinder.new()
	finder.start(port, "127.0.0.1")  # tests ask this machine instead of broadcasting
	for i in 200:
		beacon.poll()
		if finder.poll():
			break
		OS.delay_usec(2000)
	assert_eq(finder.found.get("address", ""), "127.0.0.1", "found it:")
	assert_eq(int(finder.found.get("port", 0)), port, "with its game port:")
	assert_eq(beacon.answered, 1, "answered once (it stops asking once it's found one):")
	beacon.close()


func test_nothing_found_away_from_home_is_quick() -> void:
	var port := 20000 + (Time.get_ticks_usec() % 20000)
	var finder := LanFinder.new()
	var t0 := Time.get_ticks_msec()
	finder.start(port, "127.0.0.1")  # nobody answers there
	while not finder.poll():
		OS.delay_usec(5000)
		if Time.get_ticks_msec() - t0 > 3000:
			break
	assert_true(finder.done and finder.found.is_empty(), "gave up with nothing found")
	assert_lt(float(Time.get_ticks_msec() - t0), LanFinder.WAIT_MS + 400.0, "and didn't keep the player waiting:")


func test_the_beacon_ignores_junk() -> void:
	var port := 20000 + (Time.get_ticks_usec() % 20000)
	var beacon := ServerBeacon.new()
	assert_true(beacon.listen(port), beacon.error)
	var udp := PacketPeerUDP.new()
	udp.set_dest_address("127.0.0.1", beacon.port)
	udp.put_packet("hello".to_utf8_buffer())
	udp.put_packet(JSON.stringify({"t": "something else"}).to_utf8_buffer())
	var big := PackedByteArray()
	big.resize(ServerBeacon.MAX_PACKET + 10)
	udp.put_packet(big)
	OS.delay_msec(20)
	beacon.poll()
	assert_eq(beacon.answered, 0, "nothing answered")
	udp.close()
	beacon.close()
