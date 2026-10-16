extends TestCase
## Ranked play: Glicko ratings on the server, a matchmaking band that widens with the
## wait, rating messages after a ranked match, and the Daily Challenge's scores
## submitted, verified and ranked on the server.

const FIGHTERS := ["cairn", "culvert", "sno", "barkley"]


func _ratings() -> Ratings:
	var r := Ratings.new()
	r.persist = false
	return r


func test_a_win_moves_both_and_newcomers_move_most() -> void:
	var r := _ratings()
	var out := r.record("a", "Ann", "b", "Bob", 1.0, 1000)
	assert_gt(float(out[0]["new"]), float(out[0]["old"]), "the winner goes up")
	assert_lt(float(out[1]["new"]), float(out[1]["old"]), "the loser goes down")
	assert_lt(float(out[0]["rd"]), Ratings.START_RD, "a game narrows the deviation")
	assert_eq(int(r.player("a")["wins"]), 1, "a win counted:")
	assert_eq(int(r.player("b")["games"]), 1, "a game counted:")
	var first := float(out[0]["new"]) - float(out[0]["old"])
	for i in 20:
		r.record("a", "Ann", "c%d" % i, "C", 1.0, 2000 + i)
	var late := r.record("a", "Ann", "z", "Z", 1.0, 5000)
	assert_lt(float(late[0]["new"]) - float(late[0]["old"]), first, "a veteran moves less than a newcomer")
	assert_eq(r.player("z")["name"], "Z", "names are kept:")
	var draw := r.record("d", "D", "e", "E", 0.5, 6000)
	assert_near(float(draw[0]["new"]), float(draw[1]["new"]), 0.01, "an even draw leaves them even:")


func test_the_band_widens_with_the_wait_and_time_away_loosens_a_rating() -> void:
	var r := _ratings()
	r.player("x")["rating"] = 1500.0
	r.player("y")["rating"] = 1700.0
	assert_false(r.band_ok("x", "y", 0), "200 apart: not straight away")
	assert_true(r.band_ok("x", "y", 20000), "after 20 s the band reaches them")
	r.player("x")["rd"] = 60.0
	r.player("x")["last_ms"] = 0
	assert_near(r.deviation("x", 0), 60.0, 0.01, "just played: as it is")
	r.player("x")["last_ms"] = 1000
	assert_gt(r.deviation("x", 1000 + 30 * 86400000), 100.0, "a month away loosens it")
	assert_near(r.deviation("x", 1000 + 3650 * 86400000), Ratings.START_RD, 0.01, "never past a newcomer's")


func test_daily_scores_keep_the_best_and_rank() -> void:
	var r := _ratings()
	assert_eq(r.submit_daily(20261015, "a", "Ann", 900), 1, "first in:")
	assert_eq(r.submit_daily(20261015, "b", "Bob", 1200), 1, "a better one leads:")
	assert_eq(r.submit_daily(20261015, "a", "Ann", 500), 2, "a worse run keeps the best:")
	assert_eq(int(r.daily_board(20261015)[1]["score"]), 900, "Ann's best:")
	assert_eq(r.daily_board(20261016).size(), 0, "another day is empty:")
	r.persist = true
	r.path = "user://test_ratings_%d.json" % Time.get_ticks_usec()
	r.save()
	var again := Ratings.new()
	again.path = r.path
	assert_eq(int(again.daily_board(20261015)[0]["score"]), 1200, "saved and loaded:")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(r.path))


# ------------------------------------------------------------------ through the server

func _player(server: RelayServer, i: int, ranked := false, pid := "", name := "") -> Netplay:
	var links := LoopLink.pair(1, 0, 0.0, 5 + i * 13)
	server.add_client(links[0], "test:%d" % i)
	var n := Netplay.new()
	n.ranked = ranked
	n.my_id = pid if pid != "" else "ab%08d" % i
	n.my_name = name if name != "" else "P%d" % i
	n.join("server", 0, [FIGHTERS[i % FIGHTERS.size()]], links[1])
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


func test_ranked_players_pair_within_the_band_and_get_their_new_ratings() -> void:
	var server := RelayServer.new()
	server.ratings.persist = false
	server.ratings.player("fa400000")["rating"] = 2400.0
	var a := _player(server, 0, true, "aaaa0001", "Ann")
	var b := _player(server, 1, false)  # unranked: never paired with a ranked player
	var c := _player(server, 2, true, "fa400000", "Far")
	var all := [a, b, c]
	_run(server, all, 300)
	assert_false(a.is_playing(), "nobody within Ann's band yet")
	assert_false(b.is_playing(), "the unranked player waits for an unranked one")
	var d := _player(server, 3, true, "dddd0004", "Dan")
	all.append(d)
	assert_true(_run(server, all, 300, func(): return a.is_playing() and d.is_playing()), "Ann and Dan pair up")
	assert_false(c.is_playing(), "Far waits for someone closer")
	var g: RelayServer.Game = server.games[0]
	assert_true(g.ranked, "a ranked match")
	# Ann already has a round (a 1v1 is best of three) and knocks Dan out: a result the
	# referee can score.
	var ref: Referee = g.referee
	_run(server, all, 200, Callable(), 4)
	(ref.duel as DuelSim).round_wins = [1, 0]
	(ref.duel as DuelSim).sim.creatures[1].hp = 0.0
	(ref.duel as DuelSim).sim.creatures[1]._set_state(CreatureSim.State.KO)
	for n: Netplay in [a, d]:
		n.game.duel.round_wins = [1, 0]
		n.game.duel.sim.creatures[1].hp = 0.0
		n.game.duel.sim.creatures[1]._set_state(CreatureSim.State.KO)
	assert_true(_run(server, all, 400, func(): return not a.last_rating.is_empty() and not d.last_rating.is_empty()),
		"both get a rating message")
	assert_gt(float(a.last_rating["new"]), float(a.last_rating["old"]), "Ann went up")
	assert_lt(float(d.last_rating["new"]), float(d.last_rating["old"]), "Dan went down")
	assert_near(server.ratings.rating("aaaa0001"), float(a.last_rating["new"]), 0.01, "the server's book agrees:")
	# Far has waited long enough for the band to reach a newcomer: when Eve arrives they pair.
	var e := _player(server, 4, true, "eeee0005", "Eve")
	all.append(e)
	var far_client: RelayServer.Client = null
	for cl in server.clients.values():
		if (cl as RelayServer.Client).pid == "fa400000":
			far_client = cl
	far_client.waiting_since -= 200000  # 200 s ago
	assert_true(_run(server, all, 300, func(): return c.is_playing() and e.is_playing()), "the band widened to Eve")


func test_a_daily_score_is_submitted_verified_and_ranked() -> void:
	var server := RelayServer.new()
	server.ratings.persist = false
	# A short Daily fight played here, recorded like main does.
	var d := Daily.new("cairn", 20261015)
	var sim := d.build()
	var rep := Replay.new()
	rep.setup = {"kind": "versus", "ids": [d.fighter, d.opponent()], "arena": "stadium", "mutators": d.mutators(),
		"mut_seed": d.date}
	var foe := sim.creatures[1]
	foe.hp = 1.0
	foe.pos = sim.creatures[0].pos + Vector2(24, 0)
	for i in 120:
		var ins := PackedInt32Array([SimDefs.IN_LIGHT if i % 10 == 0 else 0, 0])
		rep.record(ins)
		sim.step(ins)
		if foe.state == CreatureSim.State.KO:
			break
	var honest := d.verify(rep)  # on a fresh match the foe has full health: this is what counts
	var links := LoopLink.pair(1, 0, 0.0, 77)
	server.add_client(links[0], "daily")
	Netplay.player_id = "cafe0001"
	Netplay.player_name = "Cal"
	var c := DailyClient.submit("server", 0, 20261015, "cairn", rep.to_dict(), links[1])
	for i in 600:
		c.tick()
		server.tick()
		if c.done:
			break
	assert_true(c.done and c.ok, "answered: " + c.error)
	assert_eq(c.score, honest, "the server scored the replay itself:")
	assert_eq(c.rank, 1, "first on the board:")
	assert_eq(server.ratings.daily_board(20261015)[0]["name"], "Cal", "under the player's name:")
	var links2 := LoopLink.pair(1, 0, 0.0, 78)
	server.add_client(links2[0], "board")
	var b := DailyClient.fetch_board("server", 0, 20261015, links2[1])
	for i in 600:
		b.tick()
		server.tick()
		if b.done:
			break
	assert_true(b.ok, "the board came back: " + b.error)
	assert_eq(b.board.size(), 1, "with the one score:")
