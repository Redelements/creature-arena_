extends TestCase
## Spectators: a client that watches a match through the server sees exactly what the
## players play, joining before it starts or in the middle; the server saves every
## match's replay from its referee's log, and the theater can play it.

const FIGHTERS := ["cairn", "culvert", "sno", "barkley"]


func _server() -> RelayServer:
	var s := RelayServer.new()
	s.rematch_locked_ms = 0  # a rematch starts once both are in
	return s


func _player(server: RelayServer, i: int, size := 1, room := "", lag := 1) -> Netplay:
	var links := LoopLink.pair(lag, 0, 0.0, 5 + i * 13)
	server.add_client(links[0], "test:%d" % i)
	var n := Netplay.new()
	n.team_size = size
	n.room = room
	n.join("server", 0, [FIGHTERS[i % FIGHTERS.size()]], links[1])
	return n


func _watcher(server: RelayServer, i: int, room := "", lag := 1) -> Netplay:
	var links := LoopLink.pair(lag, 0, 0.0, 5 + i * 13)
	server.add_client(links[0], "watch:%d" % i)
	var n := Netplay.new()
	n.spectate("server", 0, room, links[1])
	return n


func _run(server: RelayServer, nets: Array, ticks: int, cond: Callable = Callable(), mash := -1) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(mash, 0)
	var hold: Array = []
	hold.resize(nets.size())
	hold.fill(0)
	for i in ticks:
		for k in nets.size():
			if mash >= 0 and (i + k) % 7 == 0:
				hold[k] = rng.randi() & (SimDefs.IN_ALL & ~SimDefs.IN_TAG)
			(nets[k] as Netplay).tick(int(hold[k]))
		server.tick()
		if cond.is_valid() and cond.call():
			return true
	return not cond.is_valid()


func _agree(players: Array, w: Netplay, msg: String) -> void:
	# The last frame everyone has a fingerprint for.
	var at := -1
	for f in (players[0] as Netplay).game.final_digests:
		if w.watch.digest_at(int(f)) != "":
			at = maxi(at, int(f))
	assert_true(at > 0, msg + ": a shared fingerprint frame")
	var d0 := String((players[0] as Netplay).game.final_digests[at])
	assert_eq(w.watch.digest_at(at), d0, msg + ": the watcher at frame %d:" % at)


func test_a_watcher_in_the_room_sees_the_same_match() -> void:
	var server := _server()
	var a := _player(server, 0, 1, "r")
	var b := _player(server, 1, 1, "r")
	var w := _watcher(server, 2, "r")
	var all := [a, b, w]
	assert_true(_run(server, all, 300, func(): return a.is_playing() and b.is_playing() and w.is_watching()),
		"the players start and the watcher is on it")
	assert_eq(server.games[0].watchers.size(), 1, "the server knows its watcher:")
	_run(server, all, 900, Callable(), 3)
	assert_gt(float(w.watch.frame), 600.0, "the watcher's copy keeps up (frame %d)" % w.watch.frame)
	assert_eq(a.game.desync_frame, -1, "no desync")
	_agree([a, b], w, "in the room")


func test_a_late_watcher_catches_up_and_any_match_will_do() -> void:
	var server := _server()
	var a := _player(server, 0)
	var b := _player(server, 1)
	assert_true(_run(server, [a, b], 300, func(): return a.is_playing() and b.is_playing()), "the players start")
	_run(server, [a, b], 400, Callable(), 9)
	var w := _watcher(server, 2, "")
	var all := [a, b, w]
	assert_true(_run(server, all, 300, func(): return w.is_watching()), "the late watcher gets the match")
	_run(server, all, 600, Callable(), 9)
	assert_gt(float(w.watch.frame), 800.0, "it replayed the log and caught up (frame %d)" % w.watch.frame)
	_agree([a, b], w, "late")


func test_the_server_saves_the_replay_and_it_plays_back() -> void:
	var server := _server()
	server.save_replays = true
	server.replay_dir = "user://test_online_replays_%d" % Time.get_ticks_usec()
	var a := _player(server, 0, 2, "d")
	var b := _player(server, 1, 2, "d")
	server.room_fill_ms = 1  # CPUs fill the other two seats straight away
	server.rng.seed = 2
	assert_true(_run(server, [a, b], 400, func(): return a.is_playing() and b.is_playing()), "a 2v2 starts")
	_run(server, [a, b], 600, Callable(), 11)
	var ref: Referee = (server.games[0] as RelayServer.Game).referee
	assert_gt(float(ref.log.size()), 400.0, "the referee logged the match")
	# One player leaving hands the slot to a CPU (the match goes on); the last one
	# leaving ends it, and that is when the server reports and saves.
	a.leave()
	server.tick()
	_run(server, [b], 30)
	b.leave()
	server.tick()
	var dir := DirAccess.open(server.replay_dir)
	assert_true(dir != null, "the replay folder exists")
	var files := dir.get_files() if dir != null else PackedStringArray()
	assert_eq(files.size(), 1, "one replay saved:")
	var rep := Replay.load_file(server.replay_dir.path_join(files[0]))
	assert_true(rep != null and rep.setup is Dictionary, "it loads with its setup")
	assert_eq(String(rep.setup["kind"]), "team", "a team battle:")
	assert_eq(rep.frames.size(), ref.log.size(), "every frame:")
	assert_eq(ReplayBuilder.play(rep), ref.duel.sim.state_digest(), "and plays back to the referee's final state:")
	for f in files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(server.replay_dir.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(server.replay_dir))


func test_a_watcher_follows_a_quick_match_from_match_to_the_rematch_pick_to_the_next_match() -> void:
	var server := _server()
	var a := _player(server, 0)
	var b := _player(server, 1)
	var w := _watcher(server, 2, "")
	var all := [a, b, w]
	assert_true(_run(server, all, 300, func(): return a.is_playing() and b.is_playing() and w.is_watching()),
		"the players start and the watcher is on it")
	_run(server, all, 400, Callable(), 5)
	_agree([a, b], w, "match 1")
	var first := w.watch
	a.request_rematch()
	b.request_rematch()
	assert_true(_run(server, all, 60, func(): return w.room_state == "select" and a.rematch_pick() and b.rematch_pick()),
		"both asked: the watcher hears they're picking")
	assert_eq(w.room_players.size(), 2, "both players, neither locked in:")
	_run(server, all, 30, Callable(), 6)
	assert_true(w.watch == first and w.is_watching(), "still on match 1 meanwhile")
	a.send_pick(["hissy"])
	b.send_pick(["gillbert"])
	assert_true(_run(server, all, 60, func(): return w.watch != first), "then follows the next match")
	assert_eq(w.watch.teams, [["hissy"], ["gillbert"]], "with the new fighters:")
	assert_eq(w.room_state, "", "the pick is over:")
	_run(server, all, 600, Callable(), 7)
	assert_gt(float(w.watch.frame), 300.0, "the watcher's copy of match 2 keeps up (frame %d)" % w.watch.frame)
	assert_eq(a.game.desync_frame, -1, "no desync")
	_agree([a, b], w, "match 2")
