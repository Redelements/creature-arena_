extends TestCase
## What a client takes from a host, a server or another player is bounded: the input delay
## in "start" is clamped, absurd setups are refused, far-future inputs and stray digests
## aren't kept, names are cleaned, the LAN finder only takes this build's server and a
## Daily board is sanitised. None of it may hang the game or print a script error.

const TEAMS := [["cairn"], ["culvert"]]


## A joining client and the raw other end of its link (a hostile host or server).
func _guest() -> Array:
	var links := LoopLink.pair(0, 0, 0.0, 3)
	var guest := Netplay.new()
	guest.join("loop", 0, ["culvert"], links[1])
	return [guest, links[0]]


func _feed(guest: Netplay, other: NetLink, m: Dictionary, ticks := 5) -> void:
	other.send(m, true)
	for i in ticks:
		guest.tick(0)


func test_the_input_delay_in_start_is_clamped() -> void:
	assert_eq(Netplay.start_delay({"delay": 2147483647}), RollbackSession.MAX_INPUT_DELAY, "huge:")
	assert_eq(Netplay.start_delay({"delay": -5}), 0, "negative:")
	assert_eq(Netplay.start_delay({"delay": []}), 2, "not a number:")
	assert_eq(Netplay.start_delay({"delay": NAN}), 2, "NaN:")
	assert_eq(Netplay.start_delay({"delay": 2.0}), 2, "a float from JSON:")
	assert_eq(Netplay.start_delay({}), 2, "missing:")
	var gl := _guest()
	var guest: Netplay = gl[0]
	var t0 := Time.get_ticks_msec()
	_feed(guest, gl[1], {"t": "start", "n": 1, "teams": TEAMS, "delay": 2147483647})
	assert_lt(float(Time.get_ticks_msec() - t0), 1000.0, "no freeze:")
	assert_true(guest.game != null, "the match starts")
	assert_eq(guest.game.input_delay, RollbackSession.MAX_INPUT_DELAY, "with the delay clamped:")
	assert_eq(guest.game.session.input_delay, RollbackSession.MAX_INPUT_DELAY, "in the session too:")
	assert_lt(float(guest.game.session._local.size()), 20.0, "nothing built for the asked delay:")
	# The session and the match clamp on their own as well.
	var s := RollbackSession.new(MatchFactory.versus("cairn", "culvert"), 0, 1 << 40, 2)
	assert_eq(s.input_delay, RollbackSession.MAX_INPUT_DELAY, "RollbackSession clamps:")


func test_a_start_with_wrong_types_is_refused_or_defaulted_without_errors() -> void:
	var gl := _guest()
	var guest: Netplay = gl[0]
	_feed(guest, gl[1], {"t": "start", "n": [], "teams": TEAMS, "delay": {}, "size": "x", "ping": [],
		"rules": 5, "arena": []})
	assert_eq(guest.phase, Netplay.Phase.ENDED, "an arena that isn't a name is a bad setup:")
	gl = _guest()
	guest = gl[0]
	_feed(guest, gl[1], {"t": "start", "n": [], "teams": TEAMS, "delay": {}, "size": "x", "ping": []})
	assert_true(guest.game != null, "defaults otherwise")
	assert_eq(guest.game.input_delay, 2, "the default delay:")
	gl = _guest()
	guest = gl[0]
	_feed(guest, gl[1], {"t": "start", "n": 1, "teams": [["cairn", "sno"], ["culvert"]], "size": 2})
	assert_eq(guest.phase, Netplay.Phase.ENDED, "teams of the wrong size are refused:")


func test_a_watch_start_clamps_the_delay_and_refuses_a_huge_log() -> void:
	var gl := _guest()
	var guest: Netplay = gl[0]
	var t0 := Time.get_ticks_msec()
	_feed(guest, gl[1], {"t": "start", "watch": true, "n": 1, "teams": TEAMS, "delay": 1 << 40, "log": []})
	assert_lt(float(Time.get_ticks_msec() - t0), 1000.0, "no freeze:")
	assert_true(guest.watch != null, "watching")
	assert_lt(float((guest.watch._inputs[0] as Dictionary).size()), RollbackSession.MAX_INPUT_DELAY + 1.0,
		"the referee's copy got a clamped delay:")
	gl = _guest()
	guest = gl[0]
	var rows: Array = []
	rows.resize(Netplay.MAX_WATCH_LOG + 1)
	rows.fill(PackedInt32Array([0, 0]))
	_feed(guest, gl[1], {"t": "start", "watch": true, "n": 1, "teams": TEAMS, "log": rows})
	assert_true(guest.watch == null and guest.phase == Netplay.Phase.ENDED, "a log longer than any match is refused")
	gl = _guest()
	guest = gl[0]
	_feed(guest, gl[1], {"t": "start", "watch": true, "n": 1, "teams": TEAMS, "log": 7})
	assert_true(guest.watch == null, "so is a log that isn't a list")
	gl = _guest()
	guest = gl[0]
	_feed(guest, gl[1], {"t": "start", "watch": true, "n": 1, "teams": [["cairn"], ["culvert", "sno"]], "size": 2})
	assert_true(guest.watch == null, "and teams of the wrong size")


func test_far_future_inputs_are_not_kept() -> void:
	var s := RollbackSession.new(MatchFactory.versus("cairn", "culvert"), 0, 2, 2)
	var sixty := PackedInt32Array()
	sixty.resize(60)
	sixty.fill(5)
	var t0 := Time.get_ticks_msec()
	for i in 20000:
		s.receive({"p": 1, "first": 10000 + i * 60, "inputs": sixty})
	assert_lt(float((s._remote[1] as Dictionary).size()), 10.0, "far-future packets dropped:")
	s.receive({"p": 1, "first": RollbackSession.MAX_AHEAD - 10, "inputs": sixty})
	assert_eq((s._remote[1] as Dictionary).size(), 2 + 11, "a packet straddling the window keeps only its part:")
	# Huge or very negative `first`, and a very long list: bounded work, nothing kept past the window.
	var big := PackedInt32Array()
	big.resize(1000000)
	s.receive({"p": 1, "first": -(1 << 50), "inputs": big})
	s.receive({"p": 1, "first": 1 << 62, "inputs": sixty})
	s.receive({"p": 1, "first": [], "inputs": sixty})
	s.receive({"p": 1, "first": 0, "inputs": [1, 2, 3]})
	s.receive({"p": 1, "first": 0, "inputs": sixty, "ack": 1 << 50})
	assert_lt(float(s.remote_ack), 100.0, "an ack beyond anything sent is capped:")
	assert_lt(float((s._remote[1] as Dictionary).size()), RollbackSession.MAX_AHEAD + 4.0, "bounded:")
	assert_lt(float(Time.get_ticks_msec() - t0), 3000.0, "and quick:")
	# Honest inputs still confirm.
	var h := RollbackSession.new(MatchFactory.versus("cairn", "culvert"), 0, 2, 2)
	h.receive({"p": 1, "first": 2, "inputs": PackedInt32Array([1, 2, 3])})
	assert_eq(h._confirmed, 4, "in-window inputs confirm as before:")


func test_stray_digests_and_frame_reports_dont_pile_up() -> void:
	var links := LoopLink.pair(0, 0, 0.0, 5)
	var m := OnlineMatch.new(TEAMS, 1, 2, links[0], 1)
	var t0 := Time.get_ticks_msec()
	for i in 20000:
		m.receive({"t": "dg", "p": 0, "f": 60000 - i, "d": "x".repeat(10)})
		m.receive({"t": "dg", "p": 0, "f": 60 * (i % 10) + 1, "d": "y"})
	for f in [60, 120, 180, 240, 300, 360, 420, 480, 540, 600, 660]:
		m.receive({"t": "dg", "p": 0, "f": f, "d": "z".repeat(100000)})
	m.receive({"t": "dg", "p": 0, "f": [], "d": {}})
	m.receive({"t": "dg", "p": [], "f": 60})
	assert_lt(float(m._remote_digests.size()), 12.0, "only digests on the 60-frame grid near this frame:")
	for k in m._remote_digests:
		assert_lt(float(String(m._remote_digests[k]).length()), 129.0, "each clipped:")
	m.receive({"t": "in", "p": 0, "first": 0, "inputs": PackedInt32Array([0]), "f": 1 << 50, "adv": INF})
	assert_lt(float(m._remote_frame[0]), RollbackSession.MAX_AHEAD + 1.0, "a reported frame is kept in the window:")
	assert_eq(float(m._remote_adv[0]), 0.0, "a non-finite advantage is ignored:")
	m.receive({"t": "in", "p": 0, "first": 0, "inputs": PackedInt32Array([0]), "adv": -1e12})
	assert_eq(float(m._remote_adv[0]), -float(RollbackSession.MAX_AHEAD), "a huge one is clamped:")
	assert_lt(float(Time.get_ticks_msec() - t0), 3000.0, "quick:")


func test_names_are_cleaned() -> void:
	assert_eq(Netplay.clean_name("\u202Elive\u202C"), "live", "bidi overrides dropped:")
	assert_eq(Netplay.clean_name("a\u200Bb\u2066c\uFEFF"), "abc", "zero-width and isolates dropped:")
	assert_eq(Netplay.clean_name("  a \t\n  b  "), "a b", "spaces collapsed and trimmed:")
	assert_eq(Netplay.clean_name("x\u0001\u0007\u001b[31my"), "x[31my", "control characters dropped:")
	assert_eq(Netplay.clean_name("\u0001\u200B "), "Player", "nothing left: the default:")
	assert_eq(Netplay.clean_name("abcdefghijklmnopqrstuvwxyz"), "abcdefghijklmnop", "16 at most:")
	var zoe := "Zo\u00EB " + String.chr(0x1F642) + " \u00DCnal"
	assert_eq(Netplay.clean_name(zoe), zoe, "letters and emoji kept:")
	assert_eq(Netplay.clean_name("a\u2028b"), "a b", "line separators are spaces:")
	# A direct host shows the joiner's name cleaned.
	var links := LoopLink.pair(0, 0, 0.0, 9)
	var host := Netplay.new()
	host.host(0, ["cairn"], links[0])
	links[1].send({"t": "hello", "v": Netplay.NET_VERSION, "data": Netplay.data_hash(), "team": ["culvert"],
		"name": "\u202Egnp.exe\u0001"}, true)
	for i in 3:
		host.tick(0)
	assert_eq(host.their_name, "gnp.exe", "the host's view of the joiner:")
	host.leave()


func test_the_lan_finder_takes_only_this_build() -> void:
	var good := {"t": ServerBeacon.ANSWER, "v": float(Netplay.NET_VERSION), "port": 7777.0, "data": Netplay.data_hash()}
	assert_true(LanFinder.accepts(good), "this build (JSON numbers are floats)")
	for bad in [{"t": ServerBeacon.ANSWER, "v": Netplay.NET_VERSION - 1, "data": Netplay.data_hash()},
			{"t": ServerBeacon.ANSWER, "v": Netplay.NET_VERSION, "data": "other"},
			{"t": ServerBeacon.ANSWER, "v": Netplay.NET_VERSION},
			{"t": ServerBeacon.ANSWER, "v": "x", "data": 5},
			{"t": 3, "v": Netplay.NET_VERSION, "data": Netplay.data_hash()},
			{}]:
		assert_false(LanFinder.accepts(bad), "refused %s" % JSON.stringify(bad))


func test_a_daily_board_is_sanitised() -> void:
	var rows: Array = [5, "x", {"name": "\u202Eevil", "score": []}, {"name": "ok", "score": 12.0}]
	for i in 500:
		rows.append({"name": "n", "score": i})
	var b := DailyClient.clean_board(rows)
	assert_eq(b.size(), DailyClient.MAX_BOARD, "at most MAX_BOARD rows, dictionaries only:")
	assert_eq(String(b[0]["name"]), "evil", "names cleaned:")
	assert_eq(int(b[0]["score"]), 0, "a bad score is 0:")
	assert_eq(int(b[1]["score"]), 12, "a good one kept:")
	assert_eq(DailyClient.clean_board("nope"), [], "not a list: empty")
