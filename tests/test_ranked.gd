extends TestCase
## Ranked play: Glicko ratings on the server, a matchmaking band that widens with the
## wait, rating messages after a ranked match, and the Daily Challenge's scores
## submitted, verified (against the day's own CPU, today ±1 only) and ranked on the server;
## player secrets (an id needs its secret; ids from before secrets are claimed once), one
## ranked connection per id, no same-address ranked pairs, a board without ids, cleaned
## names, and a ratings file written whole and kept when damaged.

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
	server.add_client(links[0], "10.0.0.%d:5000" % i)  # each from its own address
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


func _submit(server: RelayServer, date: int, rep: Replay, seed_: int, address := "") -> DailyClient:
	var links := LoopLink.pair(1, 0, 0.0, seed_)
	server.add_client(links[0], address if address != "" else "10.1.0.%d:4000" % seed_)
	var c := DailyClient.submit("server", 0, date, "cairn", rep.to_dict(), links[1])
	for i in 900:
		c.tick()
		server.tick()
		if c.done:
			break
	return c


func _board(server: RelayServer, date: int, seed_: int) -> DailyClient:
	var links := LoopLink.pair(1, 0, 0.0, seed_)
	server.add_client(links[0], "10.2.0.%d:4000" % seed_)
	var b := DailyClient.fetch_board("server", 0, date, links[1])
	for i in 600:
		b.tick()
		server.tick()
		if b.done:
			break
	return b


func test_a_daily_score_is_submitted_verified_and_ranked() -> void:
	var server := RelayServer.new()
	server.ratings.persist = false
	server.daily_today = 20261016  # the server's day: the 15th is yesterday, still taken
	var d := Daily.new("cairn", 20261015)
	var played: Array = load("res://tests/test_ladders.gd").play_daily(d)
	var rep: Replay = played[0]
	var honest: int = played[1]
	assert_gt(float(honest), 0.0, "a won fight")
	Netplay.player_id = "cafe0001"
	Netplay.player_name = "Cal"
	Netplay.player_secret = ""  # made for this run
	var c := _submit(server, 20261015, rep, 77)
	assert_true(c.done and c.ok, "answered: " + c.error)
	assert_eq(c.score, honest, "the server scored the replay itself, the same as the game:")
	assert_eq(c.rank, 1, "first on the board:")
	assert_eq(server.ratings.daily_board(20261015)[0]["name"], "Cal", "under the player's name:")
	assert_true(bool(c.board[0].get("you", false)), "the sender's own row is marked")
	var b := _board(server, 20261015, 78)
	assert_true(b.ok, "the board came back: " + b.error)
	assert_eq(b.board.size(), 1, "with the one score:")
	for row in b.board:
		assert_eq((row as Dictionary).keys(), ["name", "score", "you"], "names and scores only, never ids:")
	# A forged replay: the player's inputs kept, the CPU standing still.
	var forged := Replay.new()
	for row in rep.frames:
		forged.record(PackedInt32Array([row[0], 0]))
	Netplay.player_id = "f0f0f0f0"
	var f := _submit(server, 20261015, forged, 79)
	assert_false(f.ok, "a replay whose CPU column the day's CPU doesn't play is refused")
	assert_eq(server.ratings.daily_board(20261015).size(), 1, "and never reaches the board:")
	# Only around the server's today.
	Netplay.player_id = "0dd0dd00"
	var old := _submit(server, 20261012, rep, 80)
	assert_false(old.ok, "a Daily from days ago is refused: " + old.error)
	server.daily_today = 0
	var future := _submit(server, Daily.today() + 10000, rep, 81)
	assert_false(future.ok, "and one from a year ahead")


func test_the_board_never_carries_ids() -> void:
	var r := _ratings()
	r.submit_daily(20261015, "0123456789abcdef", "Ann", 900)
	r.submit_daily(20261015, "fedcba9876543210", "Bob", 1200)
	var rows := r.daily_board(20261015, Ratings.TOP, "0123456789abcdef")
	assert_eq(rows.size(), 2, "both rows:")
	assert_eq(rows[0], {"name": "Bob", "score": 1200}, "a name and a score:")
	assert_eq(rows[1], {"name": "Ann", "score": 900, "you": true}, "and the asker's own row marked:")
	assert_false(JSON.stringify(rows).contains("0123456789abcdef"), "no id anywhere")


func test_old_days_are_dropped_and_a_day_has_room_for_so_many() -> void:
	var r := _ratings()
	r.submit_daily(20260101, "aaaaaaaa", "Old", 10)
	r.keys["aaaaaaaa"] = "k"
	r.submit_daily(20261015, "bbbbbbbb", "New", 20)
	assert_false(r.daily.has("20260101"), "a day more than DAILY_DAYS old goes when a new day starts:")
	assert_false(r.keys.has("aaaaaaaa"), "with the key of a player who has nothing else in the book")
	assert_true(r.daily.has("20261015"), "the new day is kept")
	assert_eq(Ratings.date_days(20261332), -1, "not a date:")
	assert_eq(Ratings.date_days(20260229), -1, "2026 isn't a leap year:")
	assert_eq(Ratings.date_days(20261016) - Ratings.date_days(20261015), 1, "a day apart:")
	var day: Dictionary = r.daily["20261015"]
	for k in Ratings.DAILY_ROWS - 1:
		day["%08x" % (k + 1)] = {"name": "x", "score": 50}
	assert_eq(day.size(), Ratings.DAILY_ROWS, "a full day:")
	assert_eq(r.submit_daily(20261015, "cccccccc", "Low", 5), 0, "a score below them all finds no room:")
	assert_gt(r.submit_daily(20261015, "dddddddd", "High", 500), 0, "a better one takes the lowest's place:")
	assert_eq(day.size(), Ratings.DAILY_ROWS, "still full, no more:")
	assert_false(day.has("bbbbbbbb"), "the lowest went")


# ------------------------------------------------------------------ identity

const SECRET_A := "aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11"
const SECRET_B := "bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22"


func _ranked(server: RelayServer, i: int, pid: String, secret: String, name: String, address := "") -> Netplay:
	var links := LoopLink.pair(1, 0, 0.0, 31 + i * 7)
	server.add_client(links[0], address if address != "" else "10.3.0.%d:6000" % i)
	var n := Netplay.new()
	n.ranked = true
	n.my_id = pid
	n.my_secret = secret
	n.my_name = name
	n.join("server", 0, [FIGHTERS[i % FIGHTERS.size()]], links[1])
	return n


func _client_of(server: RelayServer, pid: String) -> RelayServer.Client:
	for cl in server.clients.values():
		if (cl as RelayServer.Client).pid == pid:
			return cl
	return null


func test_a_player_id_needs_its_secret() -> void:
	var server := RelayServer.new()
	# An id from before secrets: a rating in the book, no key.
	server.ratings.player("0123456789abcdef", "Kev")["rating"] = 1800.0
	var a := _ranked(server, 0, "0123456789abcdef", SECRET_A, "Kev")
	_run(server, [a], 60)
	assert_true(_client_of(server, "0123456789abcdef") != null, "the first install to claim it is in")
	assert_eq(server.ratings.check_key("0123456789abcdef", Ratings.key_of("0123456789abcdef", SECRET_A)),
		Ratings.Key.OK, "and its secret is bound to the id:")
	assert_false(server.ratings.keys.values().has(SECRET_A), "only a hash of it is kept")
	a.leave()
	_run(server, [a], 30)
	# Someone who learned the id: refused, the book untouched.
	var thief := _ranked(server, 1, "0123456789abcdef", SECRET_B, "Thief")
	_run(server, [thief], 60)
	assert_eq(thief.phase, Netplay.Phase.ENDED, "a hello with the id but another secret is refused")
	assert_true(thief.status.contains("another copy"), "and told why: " + thief.status)
	assert_eq(server.ratings.player("0123456789abcdef")["name"], "Kev", "the name is untouched:")
	assert_near(server.ratings.rating("0123456789abcdef"), 1800.0, 0.01, "and the rating:")
	# The owner comes back with the right secret.
	var back := _ranked(server, 2, "0123456789abcdef", SECRET_A, "Kev")
	_run(server, [back], 60)
	assert_true(_client_of(server, "0123456789abcdef") != null, "the owner is let in again")
	# Kevin resets a player who lost their settings: the next secret binds.
	assert_true(server.ratings.reset_key("0123456789abcdef"), "a reset forgets the key")
	assert_eq(server.ratings.check_key("0123456789abcdef", "x"), Ratings.Key.UNKNOWN, "")


func test_without_a_secret_a_player_is_anonymous() -> void:
	var server := RelayServer.new()
	var l := LoopLink.pair(1, 0, 0.0, 3)
	server.add_client(l[0], "10.4.0.1:1")
	(l[1] as NetLink).send({"t": "hello", "v": Netplay.NET_VERSION, "data": Netplay.data_hash(), "team": ["cairn"],
		"id": "0123456789abcdef", "ranked": true, "name": "NoKey"}, true)
	for i in 5:
		server.tick()
	var c: RelayServer.Client = server.clients.values()[0]
	assert_eq(c.pid, "", "an id without a secret counts for nothing:")
	assert_false(c.ranked, "so no ranked")
	assert_true(server.ratings.keys.is_empty(), "and nothing is bound")


func test_one_live_ranked_connection_per_player_and_never_one_address_twice() -> void:
	var server := RelayServer.new()
	var a := _ranked(server, 0, "aaaa0001", SECRET_A, "Ann")
	_run(server, [a], 30)
	var again := _ranked(server, 1, "aaaa0001", SECRET_A, "Ann")
	_run(server, [a, again], 60)
	assert_eq(again.phase, Netplay.Phase.ENDED, "a second ranked game with the same id is turned away")
	assert_true(again.status.contains("already in ranked"), "and told why: " + again.status)
	assert_true(a.phase != Netplay.Phase.ENDED, "the first stays")
	# Two games behind one address never play each other rated...
	var s2 := RelayServer.new()
	var x := _ranked(s2, 0, "aaaa0002", SECRET_A, "X", "192.168.1.9:5001")
	var y := _ranked(s2, 1, "bbbb0002", SECRET_B, "Y", "192.168.1.9:5002")
	assert_false(_run(s2, [x, y], 400, func(): return x.is_playing() and y.is_playing()),
		"two ranked games from one address don't pair")
	var z := _ranked(s2, 2, "cccc0002", SECRET_B, "Z", "192.168.1.10:5003")
	assert_true(_run(s2, [x, y, z], 400, func(): return z.is_playing()), "one from another address does")
	# ...unless the server allows it (--ranked-same-ip: a LAN party).
	var s3 := RelayServer.new()
	s3.ranked_same_ip = true
	var p := _ranked(s3, 0, "aaaa0003", SECRET_A, "P", "192.168.1.9:5001")
	var q := _ranked(s3, 1, "bbbb0003", SECRET_B, "Q", "192.168.1.9:5002")
	assert_true(_run(s3, [p, q], 400, func(): return p.is_playing() and q.is_playing()), "allowed, they pair")


func test_names_are_cleaned() -> void:
	assert_eq(Netplay.clean_name("  Kev  "), "Kev", "trimmed:")
	assert_eq(Netplay.clean_name("a\u202Eb\u200Bc"), "abc", "direction and invisible characters go:")
	assert_eq(Netplay.clean_name("x\ny\tz\u0007"), "x y z", "control characters too:")
	assert_eq(Netplay.clean_name("a     b"), "a b", "runs of spaces are one:")
	assert_eq(Netplay.clean_name("\u2066\u2069"), "Player", "nothing left: Player")
	assert_eq(Netplay.clean_name("abcdefghijklmnopqrstuvwxyz").length(), Netplay.NAME_MAX, "capped:")
	assert_eq(RelayServer._clean_name("Eve\u202E"), "Eve", "the server cleans every name it hears")


func test_the_ratings_file_is_written_whole_and_a_bad_one_is_kept() -> void:
	var dir := "user://test_ratings_%d" % Time.get_ticks_usec()
	var r := Ratings.new()
	r.path = dir.path_join("ratings.json")
	r.record("aaaa0001", "Ann", "bbbb0002", "Bob", 1.0, 1000)
	r.submit_daily(20261015, "aaaa0001", "Ann", 900)
	assert_true(FileAccess.file_exists(r.path), "saved")
	assert_true(FileAccess.file_exists(r.path + ".bak"), "the save before kept as .bak")
	assert_false(FileAccess.file_exists(r.path + ".tmp"), "no temporary file left")
	# The file is damaged (a crash, a full disk): it's moved aside, the backup is used.
	var f := FileAccess.open(r.path, FileAccess.WRITE)
	f.store_string("{\"players\": {\"aaa")
	f.close()
	var logged: Array = []
	var again := Ratings.new()
	again.path = r.path
	again.on_log = func(s: String) -> void: logged.append(s)
	assert_eq(int(again.peek("aaaa0001").get("games", 0)), 1, "the backup's book is read:")
	assert_true(logged.size() >= 1 and String(logged[0]).contains("UNREADABLE"), "and it says so loudly: %s" % [logged])
	var aside := Array(DirAccess.get_files_at(dir)).filter(func(n): return String(n).contains("corrupt"))
	assert_eq(aside.size(), 1, "the damaged file is kept aside, never overwritten:")
	for n in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(n)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_a_game_from_before_secrets_is_told_to_update() -> void:
	var server := RelayServer.new()
	for hello in [{"ranked": true}, {"submit": true}]:
		var links := LoopLink.pair()
		server.add_client(links[0], "10.5.0.1:1")
		var m := {"t": "hello", "v": 31, "data": "an-older-build", "team": ["cairn"], "id": "0123456789abcdef", "name": "Old"}
		m.merge(hello)
		(links[1] as NetLink).send(m, true)
		server.tick()
		var got: Array = (links[1] as NetLink).poll()
		assert_eq(String(got[0].get("t")), "reject", "an old game is refused:")
		assert_true(String(got[0].get("msg")).contains("Update your game"), "and told to update: " + String(got[0].get("msg")))
	assert_eq(server.player_count(), 0, "and let go")
	assert_true(server.ratings.keys.is_empty() and server.ratings.players.is_empty(), "the book untouched")
