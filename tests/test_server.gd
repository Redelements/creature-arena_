extends TestCase
## The dedicated server: players join it like a host, it pairs them (by room), relays
## their matches, referees them with its own simulation, and cleans up when they leave.

const TEAM_A := ["cairn"]
const TEAM_B := ["culvert"]
const TEAM_C := ["sno"]


## A server and `teams.size()` players joined to it over in-memory links.
func _setup(teams: Array, rooms: Array = [], lag := 0, jitter := 0, loss := 0.0) -> Array:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in (the last 3 s have their own test)
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
	assert_true(_run(server, nets, 40, func(): return a.rematch_pick() and b.rematch_pick()), "both asked: both pick")
	var g: RelayServer.Game = server.games[0]
	assert_true(g.picking, "the server waits for their picks")
	assert_eq(a.room_players.size(), 2, "both hear who has locked in:")
	a.send_pick(["barkley"])
	assert_true(_run(server, nets, 20, func(): return bool(b.room_players[0]["locked"])), "B sees A lock in")
	assert_false(b.room_players[0].has("team"), "but not A's fighter (hidden until the start):")
	assert_eq(b.room_players[0]["fighter"], TEAM_A[0], "the status still shows A's last one:")
	assert_true(a.game == first, "and A waits for B")
	b.send_pick(["sno", "pete"])  # not a tag Duel: one fighter
	_run(server, nets, 20)
	assert_true(a.game == first and g.picking, "a pick of the wrong size is refused")
	b.send_pick(["digby"])
	_run(server, nets, 40, func(): return a.game != first and b.game.id == a.game.id)
	assert_eq(a.game.id, 2, "a second match:")
	assert_eq(b.game.id, 2, "on both sides:")
	assert_eq(a.game.teams, [["barkley"], ["digby"]], "with the new fighters:")
	assert_eq(b.game.teams, a.game.teams, "on both sides:")
	assert_eq(g.referee.teams, a.game.teams, "and on the referee:")
	_run(server, nets, 300, Callable(), _mash(9))
	assert_eq(a.game.desync_frame, -1, "the rematch is in sync too")
	assert_eq(b.game.desync_frame, -1, "")
	assert_gt(float(g.referee.checked), 2.0, "the referee checked both players' fingerprints:")
	assert_eq(g.referee.desync, [-1, -1], "and they agree with its own:")
	assert_eq(server.matches_started, 2, "the server counted both:")


## Both players of a server 1v1 ask for a rematch, then pick these.
func _repick(server: RelayServer, nets: Array, fa: Array, fb: Array) -> bool:
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	var n := a.game.id
	a.request_rematch()
	b.request_rematch()
	if not _run(server, nets, 40, func(): return a.rematch_pick() and b.rematch_pick()):
		return false
	a.send_pick(fa)
	b.send_pick(fb)
	return _run(server, nets, 60, func(): return a.game.id == n + 1 and b.game.id == n + 1)


func test_a_tag_duel_rematch_picks_three_again_and_same_again_works() -> void:
	var s := _setup([["cairn", "sno", "pete"], ["culvert", "digby", "barkley"]])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	assert_true(_run(server, nets, 300, func(): return _both_playing(nets)), "a tag Duel")
	_run(server, nets, 60, Callable(), _mash(2))
	a.request_rematch()
	b.request_rematch()
	_run(server, nets, 40, func(): return a.rematch_pick() and b.rematch_pick())
	a.send_pick(["gillbert"])  # a tag Duel picks three
	_run(server, nets, 20)
	assert_false(bool(b.room_players[0]["locked"]), "one fighter isn't a tag team")
	a.send_pick(["gillbert", "hissy", "cerebro"])
	b.send_pick(b.my_team)  # same again
	assert_true(_run(server, nets, 60, func(): return a.game.id == 2 and b.game.id == 2), "the rematch starts")
	assert_eq(a.game.teams, [["gillbert", "hissy", "cerebro"], ["culvert", "digby", "barkley"]], "a new team of three:")
	assert_eq(b.game.teams, a.game.teams, "")
	_run(server, nets, 300, Callable(), _mash(4))
	assert_eq(a.game.desync_frame, -1, "in sync")
	assert_eq((server.games[0] as RelayServer.Game).referee.desync, [-1, -1], "")
	assert_true(_repick(server, nets, a.my_team, b.my_team), "same again, both")
	assert_eq(a.game.teams, [["gillbert", "hissy", "cerebro"], ["culvert", "digby", "barkley"]], "the same teams:")


func test_leaving_during_the_rematch_pick_ends_it_cleanly_for_everyone() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	_run(server, nets, 200, func(): return _both_playing(nets))
	var wl := LoopLink.pair(1, 0, 0.0, 77)
	server.add_client(wl[0], "watch")
	var w := Netplay.new()
	w.spectate("server", 0, "", wl[1])
	var all := [a, b, w]
	assert_true(_run(server, all, 100, func(): return w.is_watching()), "a spectator")
	a.request_rematch()
	b.request_rematch()
	assert_true(_run(server, all, 40, func(): return a.rematch_pick() and w.room_state == "select"),
		"picking; the spectator hears so")
	a.send_pick(["sno"])
	_run(server, all, 10)
	b.leave()
	_run(server, all, 20)
	assert_eq(a.phase, Netplay.Phase.ENDED, "the other player's session ends:")
	assert_true(a.error.contains("left"), "and says why: " + a.error)
	assert_eq(w.phase, Netplay.Phase.ENDED, "the spectator's too:")
	assert_true(w.error.contains("ended"), "the match ended: " + w.error)
	assert_eq(server.games.size(), 0, "the server lets the match go:")
	assert_eq(server.clients.size(), 0, "")


func test_every_match_of_a_rematch_run_saves_its_replay_with_its_own_fighters() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	server.save_replays = true
	server.replay_dir = "user://test_rematch_replays_%d" % Time.get_ticks_usec()
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	_run(server, nets, 200, func(): return _both_playing(nets))
	_run(server, nets, 200, Callable(), _mash(6))
	var first_log: Array = (server.games[0] as RelayServer.Game).referee.log.duplicate()
	assert_true(_repick(server, nets, ["sno"], ["pete"]), "a rematch with new fighters")
	_run(server, nets, 200, Callable(), _mash(7))
	assert_true(_repick(server, nets, ["hissy"], ["pete"]), "and another")
	a.leave()
	_run(server, [b], 10)
	var files := Array(DirAccess.get_files_at(server.replay_dir))
	files.sort()
	assert_eq(files.size(), 3, "three matches, three replays:")
	var want := [[TEAM_A, TEAM_B], [["sno"], ["pete"]], [["hissy"], ["pete"]]]
	for k in mini(files.size(), 3):
		var rep := Replay.load_file(server.replay_dir.path_join(String(files[k])))
		var n := int(String(files[k]).get_basename().get_slice("_", 2))
		assert_eq((rep.setup as Dictionary)["teams"], want[n - 1], "match %d's replay has its own fighters:" % n)
	var rep1 := Replay.load_file(server.replay_dir.path_join("online_1_1.json"))
	assert_true(rep1.frames.size() >= first_log.size(), "match 1's replay has its frames")
	for f in files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(server.replay_dir.path_join(String(f))))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(server.replay_dir))


## A spectator of the server's match, its link keeping what it hears.
func _spectator(server: RelayServer) -> Netplay:
	var wl := LoopLink.pair(1, 0, 0.0, 77)
	server.add_client(wl[0], "watch")
	var w := Netplay.new()
	w.spectate("server", 0, "", wl[1])
	return w


## Whether any message in `heard` mentions a fighter id.
func _mentions(heard: Array, fighter: String) -> bool:
	for m in heard:
		if JSON.stringify(m).contains(fighter):
			return true
	return false


func test_rematch_picks_stay_hidden_from_the_opponent_and_spectators_until_both_are_in() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	_run(server, nets, 200, func(): return _both_playing(nets))
	var w := _spectator(server)
	var all := [a, b, w]
	assert_true(_run(server, all, 100, func(): return w.is_watching()), "a spectator")
	a.request_rematch()
	b.request_rematch()
	assert_true(_run(server, all, 40, func(): return a.rematch_pick() and b.rematch_pick() and w.room_state == "select"),
		"picking")
	for n: Netplay in all:
		(n.link as LoopLink).keep_heard = true
	a.send_pick(["gillbert"])
	assert_true(_run(server, all, 30, func(): return bool(b.room_players[0]["locked"]) and bool(w.room_players[0]["locked"])),
		"B and the spectator hear that A locked in")
	_run(server, all, 30)
	assert_false(_mentions((b.link as LoopLink).heard, "gillbert"), "nothing B hears names A's pick")
	assert_false(_mentions((w.link as LoopLink).heard, "gillbert"), "nor anything the spectator hears")
	assert_true(b.room_players.all(func(p): return not (p as Dictionary).has("team")), "no team in the status")
	b.send_pick(["hissy"])
	assert_true(_run(server, all, 20, func(): return (a.link as LoopLink).heard.any(func(m): return m.get("t") == "start")),
		"both in: the start")
	assert_false(_mentions((a.link as LoopLink).heard.filter(func(m): return m.get("t") != "start"), "hissy"),
		"A only learns B's pick from the start")
	assert_true(_run(server, all, 60, func(): return a.game.id == 2 and b.game.id == 2 and w.watch.teams == [["gillbert"], ["hissy"]]),
		"which reveals both, to the spectator too")


func test_a_quick_match_rematch_is_on_a_new_arena_for_everyone() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	server.rng.seed = 4242
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	_run(server, nets, 200, func(): return _both_playing(nets))
	var w := _spectator(server)
	var all := [a, b, w]
	assert_true(_run(server, all, 100, func(): return w.is_watching()), "a spectator")
	var seen := {}
	for k in 4:
		var last := a.game.arena_id
		seen[last] = true
		assert_eq(b.game.arena_id, last, "match %d: both players on the same arena:" % a.game.id)
		assert_eq(w.arena_id, last, "and the spectator:")
		assert_eq((server.games[0] as RelayServer.Game).referee.arena, last, "and the referee:")
		assert_true(_repick(server, all, a.my_team, b.my_team), "rematch %d" % (k + 1))
		_run(server, all, 30, func(): return w.watch != null and w.arena_id == a.game.arena_id)
		assert_true(a.game.arena_id != last, "a new arena each rematch (%s after %s)" % [a.game.arena_id, last])
		assert_eq(b.game.duel.sim.arena_id, a.game.arena_id, "built on both machines:")
	assert_gt(float(seen.size()), 1.0, "the draw moves around:")
	_run(server, all, 300, Callable(), _mash(3))
	assert_eq(a.game.desync_frame, -1, "in sync on the drawn arena")


func test_the_rematch_pick_countdown_locks_in_the_last_pick() -> void:
	var s := _setup([TEAM_A, TEAM_B])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	assert_eq(server.rematch_pick_ms, 20000, "20 seconds, from data/online.json:")
	_run(server, nets, 200, func(): return _both_playing(nets))
	_run(server, nets, 100, Callable(), _mash(11))
	var first := a.game
	a.request_rematch()
	b.request_rematch()
	assert_true(_run(server, nets, 40, func(): return a.rematch_pick() and b.rematch_pick()), "picking")
	assert_gt(a.pick_secs, 19.0, "the players hear the countdown:")
	assert_gt(a.pick_seconds_left(), 0.0, "")
	a.send_pick(["sno"])
	_run(server, nets, 60)
	assert_true(a.game == first, "B hasn't locked in and time's not up: still picking")
	server.clock_skip_ms += 20001  # time runs out
	assert_true(_run(server, nets, 40, func(): return a.game.id == 2 and b.game.id == 2), "time's up: the rematch starts")
	assert_eq(a.game.teams, [["sno"], TEAM_B], "A's pick, and B's last fighter:")
	assert_eq(b.game.teams, a.game.teams, "the same match on both machines:")
	assert_eq(b.my_team, TEAM_B, "")
	_run(server, nets, 400, Callable(), _mash(12))
	assert_eq(a.game.desync_frame, -1, "in sync")
	assert_eq(b.game.desync_frame, -1, "")
	assert_eq((server.games[0] as RelayServer.Game).referee.desync, [-1, -1], "the referee agrees:")
	assert_gt(float(a.game.digests_matched), 2.0, "fingerprints compared:")
	# Nobody locks in: both keep their fighters.
	a.request_rematch()
	b.request_rematch()
	assert_true(_run(server, nets, 40, func(): return a.rematch_pick() and b.rematch_pick()), "picking again")
	server.clock_skip_ms += 20001
	assert_true(_run(server, nets, 40, func(): return a.game.id == 3 and b.game.id == 3), "time's up again")
	assert_eq(a.game.teams, [["sno"], TEAM_B], "the same fighters:")
	# Both in before time's up: no waiting for the countdown.
	a.request_rematch()
	b.request_rematch()
	assert_true(_run(server, nets, 40, func(): return a.rematch_pick() and b.rematch_pick()), "and again")
	a.send_pick(["pete"])
	b.send_pick(["digby"])
	assert_true(_run(server, nets, 20, func(): return a.game.id == 4 and b.game.id == 4), "starts at once")
	assert_eq(a.game.teams, [["pete"], ["digby"]], "")


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


## Both locked in: the countdown drops to rematch_locked_seconds (3), both new fighters
## show, the picks freeze, and the rematch starts when it runs out.
func test_once_both_lock_in_the_countdown_drops_to_three_seconds_and_shows_both() -> void:
	var s := _setup([["cairn"], ["culvert"]])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	assert_eq(RelayServer.new().rematch_locked_ms, 3000, "3 seconds, from data/online.json:")
	server.rematch_locked_ms = 3000
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	_run(server, nets, 300, func(): return a.is_playing() and b.is_playing())
	_run(server, nets, 60)
	var first := a.game
	for n: Netplay in nets:
		n.request_rematch()
	assert_true(_run(server, nets, 200, func(): return a.rematch_pick() and b.rematch_pick()), "both picking")
	assert_gt(a.pick_seconds_left(), 15.0, "the full countdown while they choose:")
	a.send_pick(["sno"])
	_run(server, nets, 20)
	assert_false(b.pick_all_locked, "one in: still hidden")
	assert_eq(String(b.room_players[a.local_slot]["fighter"]), "cairn", "the opponent's pick doesn't show yet:")
	b.send_pick(["barkley"])
	assert_true(_run(server, nets, 40, func(): return a.pick_all_locked and b.pick_all_locked), "both in")
	assert_true(a.game == first, "not started at once")
	assert_lt(a.pick_seconds_left(), 3.01, "the countdown drops to 3:")
	assert_gt(a.pick_seconds_left(), 2.0, "")
	assert_eq(String(a.room_players[b.local_slot]["fighter"]), "barkley", "now both fighters show:")
	assert_eq(String(b.room_players[a.local_slot]["fighter"]), "sno", "")
	a.send_pick(["digby"])  # too late: frozen
	_run(server, nets, 20)
	assert_eq(String(b.room_players[a.local_slot]["fighter"]), "sno", "a pick after both are in is ignored:")
	assert_true(a.game == first, "still the last seconds")
	server.clock_skip_ms += 3001
	assert_true(_run(server, nets, 200, func(): return a.game != first and b.game != null and b.game.id == a.game.id),
		"then the rematch starts")
	var want := [["sno"], ["barkley"]] if a.local_slot == 0 else [["barkley"], ["sno"]]
	assert_eq(a.game.teams, want, "with the frozen picks:")
	assert_eq(b.game.teams, a.game.teams, "on both:")


func test_with_less_than_three_seconds_left_locking_in_doesnt_add_time() -> void:
	var s := _setup([["cairn"], ["culvert"]])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	server.rematch_locked_ms = 3000
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	_run(server, nets, 300, func(): return a.is_playing() and b.is_playing())
	_run(server, nets, 60)
	var first := a.game
	for n: Netplay in nets:
		n.request_rematch()
	assert_true(_run(server, nets, 200, func(): return a.rematch_pick() and b.rematch_pick()), "both picking")
	server.clock_skip_ms += 18500  # 1.5 s left
	a.send_pick(["sno"])
	b.send_pick(["barkley"])
	assert_true(_run(server, nets, 40, func(): return a.pick_all_locked), "both in")
	assert_lt(a.pick_seconds_left(), 1.6, "the countdown keeps its 1.5 s:")
	server.clock_skip_ms += 1600
	assert_true(_run(server, nets, 200, func(): return a.game != first), "the rematch starts on time")
