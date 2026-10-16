extends TestCase
## Rooms on the server last between matches: after one, everyone picks again and the
## next match starts with the new fighters; a player leaving doesn't end the room;
## spectators follow it from match to match; the code copies to the clipboard. Also the
## flows rooms sit beside: Quick match and ranked rematches (which pick again too, and
## ranked rates every game), and a spectator following a rematch through its pick.

const FIGHTERS := ["cairn", "culvert", "sno", "barkley"]


func _player(server: RelayServer, i: int, room := "", size := 1, team: Array = []) -> Netplay:
	var links := LoopLink.pair(1, 0, 0.0, 5 + i * 13)
	server.add_client(links[0], "test:%d" % i)
	var n := Netplay.new()
	n.team_size = size
	n.room = room
	n.my_name = "P%d" % i
	n.join("server", 0, team if not team.is_empty() else [FIGHTERS[i % FIGHTERS.size()]], links[1])
	return n


func _watcher(server: RelayServer, i: int, room := "") -> Netplay:
	var links := LoopLink.pair(1, 0, 0.0, 5 + i * 13)
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


func _room(server: RelayServer, code: String) -> RelayServer.Room:
	return server.rooms.get(code)


## Both players go to the select and lock in these fighters.
func _pick_again(server: RelayServer, nets: Array, a: Netplay, b: Netplay, fa: Array, fb: Array) -> void:
	a.request_next()
	b.request_next()
	_run(server, nets, 10)
	a.send_pick(fa)
	b.send_pick(fb)


func test_a_room_plays_picks_again_and_starts_the_next_match_with_the_new_fighters() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var a := _player(server, 0, "kev", 1, ["cairn"])
	var b := _player(server, 1, "kev", 0, ["culvert"])
	var all := [a, b]
	assert_true(_run(server, all, 300, func(): return a.is_playing() and b.is_playing()), "the room's first match starts")
	assert_true(a.in_room() and b.in_room(), "both know it's a room")
	assert_eq(a.room_state, "playing", "the room says it's playing:")
	_run(server, all, 300, Callable(), 3)
	var first := a.game
	a.request_next()
	_run(server, all, 10)
	assert_eq(_room(server, "kev").state, RelayServer.RoomState.SELECT, "a player on the select: the room is picking")
	assert_eq(b.room_state, "select", "and the other hears so:")
	a.send_pick(["sno"])
	_run(server, all, 60, Callable(), 4)
	assert_true(a.game == first, "one lock-in isn't enough: the old match carries on behind the select")
	assert_eq(b.room_waiting_on(), ["P1"], "the other sees who's still picking:")
	assert_eq(b.room_players.filter(func(p): return p["locked"]).size(), 1, "and that one has locked in:")
	b.request_next()
	_run(server, all, 5)
	b.send_pick(["barkley"])
	assert_true(_run(server, all, 60, func(): return a.game != first and b.game != null and b.game.id == a.game.id),
		"everyone locked in: the next match starts")
	assert_eq(a.game.id, first.id + 1, "numbered on from the last:")
	assert_eq(a.game.teams, b.game.teams, "the same match on both:")
	assert_eq(a.game.teams[a.game.local_side], ["sno"], "each plays their new pick:")
	assert_eq(b.game.teams[b.game.local_side], ["barkley"], "")
	assert_false(a.picking or a.picked, "the select is over")
	assert_eq(server.games.size(), 1, "the old match is gone from the server:")
	assert_eq(server.player_count(), 2, "nobody was let go:")
	_run(server, all, 600, Callable(), 5)
	assert_eq(a.game.desync_frame, -1, "the next match is in sync")
	assert_eq((server.games[0] as RelayServer.Game).referee.desync, [-1, -1], "and the referee agrees:")


func test_a_room_has_no_rematch() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var a := _player(server, 0, "r")
	var b := _player(server, 1, "r")
	var all := [a, b]
	_run(server, all, 300, func(): return a.is_playing() and b.is_playing())
	a.request_rematch()
	assert_false(a.rematch_local, "the client doesn't ask in a room")
	a.link.send({"t": "rematch"}, true)
	b.link.send({"t": "rematch"}, true)
	_run(server, all, 30)
	assert_eq(server.matches_started, 1, "and the server takes no rematch from one:")


func test_a_player_leaving_a_1v1_room_leaves_the_other_waiting_there_and_a_newcomer_plays_them() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var a := _player(server, 0, "kx7p")
	var b := _player(server, 1, "kx7p")
	var w := _watcher(server, 2, "kx7p")
	var all := [a, b, w]
	_run(server, all, 300, func(): return a.is_playing() and b.is_playing() and w.is_watching())
	_run(server, all, 200, Callable(), 7)
	b.leave()
	assert_true(_run(server, all, 30, func(): return a.phase == Netplay.Phase.HANDSHAKE), "A goes back to waiting")
	assert_true(a.game == null, "the match is over for them")
	assert_true(a.status.contains("Waiting for a player") and a.status.contains("KX7P"),
		"with the code to hand out: " + a.status)
	assert_true(a.status.begins_with("Your opponent left"), "and says who left: " + a.status)
	assert_true(server.rooms.has("kx7p"), "the room is still there")
	assert_eq(_room(server, "kx7p").state, RelayServer.RoomState.WAITING, "waiting for a player:")
	assert_eq(server.games.size(), 0, "with no match on:")
	assert_eq(w.phase, Netplay.Phase.PLAYING, "the watcher stays")
	assert_eq(w.room_state, "waiting", "and hears the room is waiting:")
	var c := _player(server, 3, "kx7p", 0)
	all = [a, c, w]
	var watched := w.watch
	assert_true(_run(server, all, 300, func(): return a.is_playing() and c.is_playing()), "a newcomer plays the one who waited")
	assert_eq(a.game.id, 2, "the room's second match:")
	assert_true(_run(server, all, 30, func(): return w.watch != watched), "the watcher is on it too")
	_run(server, all, 400, Callable(), 8)
	assert_eq(a.game.desync_frame, -1, "in sync")
	assert_gt(float(w.watch.frame), 250.0, "the watcher keeps up (frame %d)" % w.watch.frame)


func test_watchers_follow_the_room_from_match_to_select_to_the_next_match() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var a := _player(server, 0, "r")
	var b := _player(server, 1, "r")
	var w := _watcher(server, 2, "r")
	var all := [a, b, w]
	assert_true(_run(server, all, 300, func(): return a.is_playing() and b.is_playing() and w.is_watching()),
		"the watcher is on the room's first match")
	_run(server, all, 300, Callable(), 2)
	var first := w.watch
	a.request_next()
	assert_true(_run(server, all, 20, func(): return w.room_state == "select"), "the watcher hears the room is picking")
	assert_eq(w.room_players.size(), 2, "and who's in it:")
	assert_true(w.is_watching(), "still connected, still on the last match")
	a.send_pick(["sno"])
	b.request_next()
	b.send_pick(["cairn"])
	assert_true(_run(server, all, 60, func(): return w.watch != first and a.game.id == 2), "the next match starts")
	assert_true(w.is_watching(), "the watcher follows without rejoining")
	assert_eq(w.room_state, "playing", "")
	assert_eq(w.watch.teams, a.game.teams, "the new match's teams:")
	_run(server, all, 600, Callable(), 6)
	assert_gt(float(w.watch.frame), 400.0, "and keeps up (frame %d)" % w.watch.frame)
	var at := -1
	for f in a.game.final_digests:
		if w.watch.digest_at(int(f)) != "":
			at = maxi(at, int(f))
	assert_true(at > 0, "a shared fingerprint frame")
	assert_eq(w.watch.digest_at(at), String(a.game.final_digests[at]), "the watcher sees the same match:")


func test_the_room_closes_when_its_last_player_leaves() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var a := _player(server, 0, "r")
	var b := _player(server, 1, "r")
	var w := _watcher(server, 2, "r")
	var all := [a, b, w]
	_run(server, all, 300, func(): return a.is_playing() and b.is_playing() and w.is_watching())
	b.leave()
	_run(server, all, 20)
	assert_eq(w.phase, Netplay.Phase.PLAYING, "one leaving keeps the room (and its watcher)")
	a.leave()
	_run(server, all, 20)
	assert_eq(w.phase, Netplay.Phase.ENDED, "the last one leaving closes it")
	assert_true(w.error.contains("room closed"), "and the watcher is told so: " + w.error)
	assert_true(server.rooms.is_empty(), "the server forgets it")
	assert_eq(server.player_count(), 0, "and lets everyone go:")


func test_a_full_room_turns_a_third_player_away() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var a := _player(server, 0, "r")
	var b := _player(server, 1, "r")
	var all := [a, b]
	_run(server, all, 300, func(): return a.is_playing() and b.is_playing())
	var c := _player(server, 2, "r")
	all.append(c)
	_run(server, all, 30, func(): return c.phase == Netplay.Phase.ENDED)
	assert_eq(c.phase, Netplay.Phase.ENDED, "a third player in a 1v1 room is turned away")
	assert_true(c.error.contains("full") and c.error.contains("Watch room"), "and told to watch instead: " + c.error)
	assert_true(a.is_playing() and b.is_playing(), "the match goes on")


func test_a_team_room_plays_on_with_a_cpu_and_a_newcomer_joins_the_next_match() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	server.room_fill_ms = 1  # CPUs fill the empty seats at once
	server.rng.seed = 3
	var a := _player(server, 0, "t", 2)
	var b := _player(server, 1, "t", 0)
	var all := [a, b]
	assert_true(_run(server, all, 400, func(): return a.is_playing() and b.is_playing()), "a 2v2 room starts")
	assert_eq(a.game.cpu_slots.size(), 2, "with two CPUs:")
	b.leave()
	all = [a]
	assert_true(_run(server, all, 30, func(): return a.game.cpu_slots.size() == 3), "a CPU takes the leaver's slot")
	assert_true(a.is_playing(), "and the match plays on")
	var c := _player(server, 2, "t", 0)
	all = [a, c]
	_run(server, all, 60)
	assert_eq(c.phase, Netplay.Phase.HANDSHAKE, "a newcomer mid-match waits for the next one")
	assert_true(c.status.contains("next match"), "and is told so: " + c.status)
	var first := a.game
	a.request_next()
	a.send_pick(["digby"])
	assert_true(_run(server, all, 100, func(): return a.game != first and c.is_playing()), "the next match has them both")
	assert_eq(a.game.id, c.game.id, "the same match:")
	assert_eq(a.game.cpu_slots.size(), 2, "and CPUs in the open seats:")
	var fighters: Array = a.game.teams[0] + a.game.teams[1]
	assert_true("digby" in fighters, "A's new pick plays: %s" % [fighters])
	_run(server, all, 300, Callable(), 2)
	assert_eq(a.game.desync_frame, -1, "in sync")


# ------------------------------------------------------------------ Quick match and ranked

func test_quick_match_rematch_still_works_and_its_watcher_follows() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var a := _player(server, 0)
	var b := _player(server, 1)
	var all := [a, b]
	_run(server, all, 300, func(): return a.is_playing() and b.is_playing())
	var w := _watcher(server, 2)
	all.append(w)
	_run(server, all, 100, func(): return w.is_watching())
	var watched := w.watch
	a.request_rematch()
	b.request_rematch()
	assert_true(_run(server, all, 60, func(): return a.rematch_pick() and b.rematch_pick() and w.room_state == "select"),
		"a Quick match rematch picks first; the watcher hears the players are picking")
	assert_false(w.rematch_pick(), "the watcher doesn't pick")
	a.send_pick(["digby"])
	assert_true(_run(server, all, 30, func(): return w.room_players.size() == 2 and bool(w.room_players[0]["locked"])),
		"the watcher sees who has locked in")
	b.send_pick(["pete"])
	assert_true(_run(server, all, 60, func(): return a.game.id == 2 and b.game.id == 2), "then the rematch starts")
	assert_true(_run(server, all, 30, func(): return w.watch != watched), "and the watcher gets it")
	assert_eq(w.watch.teams, [["digby"], ["pete"]], "with the new fighters:")
	assert_eq(w.room_state, "", "the pick is over for the watcher too:")


func test_a_ranked_rematch_picks_again_and_rates_every_game() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var nets: Array = []
	for i in 2:
		var links := LoopLink.pair(1, 0, 0.0, 5 + i * 13)
		server.add_client(links[0])
		var n := Netplay.new()
		n.ranked = true
		n.my_id = "abcd000%d" % i
		n.my_name = "R%d" % i
		n.join("server", 0, [FIGHTERS[i]], links[1])
		nets.append(n)
	var a: Netplay = nets[0]
	var b: Netplay = nets[1]
	assert_true(_run(server, nets, 300, func(): return a.is_playing() and b.is_playing()), "a ranked match")
	var g: RelayServer.Game = server.games[0]
	for d in [g.referee.duel, a.game.duel, b.game.duel]:
		(d as DuelSim).round_wins = [1, 0]
		(d as DuelSim).sim.creatures[1].hp = 0.0
		(d as DuelSim).sim.creatures[1]._set_state(CreatureSim.State.KO)
	assert_true(_run(server, nets, 400, func(): return not a.last_rating.is_empty() and not b.last_rating.is_empty()), "rated")
	assert_eq(int(server.ratings.player("abcd0000")["games"]), 1, "one game in the book:")
	var after_one := server.ratings.rating("abcd0000")
	a.request_rematch()
	assert_true(a.rematch_local, "ranked has a rematch now")
	b.request_rematch()
	assert_true(_run(server, nets, 60, func(): return a.rematch_pick() and b.rematch_pick()), "through the pick")
	a.send_pick(["sno"])
	b.send_pick(["digby"])
	assert_true(_run(server, nets, 60, func(): return a.game.id == 2 and b.game.id == 2), "the rematch starts")
	assert_eq(a.game.teams, [["sno"], ["digby"]], "with the new fighters:")
	assert_true(a.last_rating.is_empty(), "the last game's rating is cleared for the new one")
	g = server.games[0]
	assert_true(g.ranked, "still ranked")
	for d in [g.referee.duel, a.game.duel, b.game.duel]:
		(d as DuelSim).round_wins = [1, 0]
		(d as DuelSim).sim.creatures[1].hp = 0.0
		(d as DuelSim).sim.creatures[1]._set_state(CreatureSim.State.KO)
	assert_true(_run(server, nets, 400, func(): return not a.last_rating.is_empty() and not b.last_rating.is_empty()),
		"the rematch is rated too")
	assert_eq(a.ratings_heard, 2, "two rating messages each:")
	assert_eq(b.ratings_heard, 2, "")
	assert_eq(int(server.ratings.player("abcd0000")["games"]), 2, "two games in the book:")
	assert_eq(int(server.ratings.player("abcd0001")["games"]), 2, "")
	assert_eq(int(a.last_rating["games"]), 2, "the message says so:")
	assert_gt(server.ratings.rating("abcd0000"), after_one, "and the second win moved the rating again")


# ------------------------------------------------------------------ the copy button

func test_the_room_code_copies() -> void:
	var b := RoomCodeButton.new("KX7P")
	_root().add_child(b)
	RoomCodeButton.last_copied = ""
	assert_true(b.text.contains("KX7P"), "it shows the code: " + b.text)
	assert_eq(b.focus_mode, Control.FOCUS_ALL, "the pad and keyboard can reach it:")
	b.pressed.emit()
	assert_eq(RoomCodeButton.last_copied, "KX7P", "pressing copies the code:")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		assert_eq(DisplayServer.clipboard_get(), "KX7P", "onto the clipboard:")
	assert_true(b.copied() and b.text.contains("Copied"), "and says so: " + b.text)
	b._process(RoomCodeButton.COPIED_SECS + 0.1)
	assert_false(b.copied() or b.text.contains("Copied"), "for a moment: " + b.text)
	b.free()


func test_the_online_screen_shows_the_room_code_as_a_copy_button() -> void:
	var lobby := OnlineLobby.new("digby", "", [], "game.example.net")
	var st := ScreenStack.new()
	_root().add_child(st)
	st.push(lobby)
	assert_false(lobby.code_button.visible, "no room, no code")
	lobby.room_code = "KX7P"
	lobby.room_created = true
	lobby.busy = true
	assert_true(lobby.code_button.visible and lobby.code_button.code == "KX7P", "waiting in a room: the code is up")
	assert_true(lobby.code_button in lobby.rows(), "and reachable with the pad, down from Cancel")
	RoomCodeButton.last_copied = ""
	lobby.code_button.grab_focus()
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)
	lobby.code_button.pressed.emit()
	assert_eq(RoomCodeButton.last_copied, "KX7P", "pressing it copies:")
	st.free()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


# ------------------------------------------------------------------ in the game

const TEST_SETTINGS := "user://test_rooms_settings.cfg"


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


## Steps the game, the other players and the server until `cond`.
func _step(g: Node, server: RelayServer, others: Array, ticks: int, cond: Callable) -> bool:
	for i in ticks:
		for n: Netplay in others:
			n.tick(0)
		server.tick()
		_tick(g, 1)
		if cond.call():
			return true
	return false


## The game in a room on an in-memory server with another player. Returns [server, other].
func _game_in_room(g: Node, code: String, mine: String, theirs: String) -> Array:
	g._start_match(20)  # Online
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var la := LoopLink.pair()
	server.add_client(la[0])
	var me := Netplay.new()
	me.room = code
	me.join("server", 0, [mine], la[1])
	var other := _player(server, 1, code, 0, [theirs])
	g.lobby.use_fighter(mine)
	g.lobby.room_code = code.to_upper()
	g.lobby.room_created = true
	g.lobby.searching_for = "Room " + code
	g.netplay = me
	g.lobby.busy = true
	return [server, other]


func _labels(scr: UiScreen) -> Array:
	var out: Array = []
	for r in scr.rows():
		if r is Button and not (r is RoomCodeButton):
			out.append((r as Button).text)
	return out


func test_in_the_game_a_room_goes_from_match_over_to_the_select_and_into_the_next_match() -> void:
	var g := _game()
	var s := _game_in_room(g, "kev", "cairn", "sno")
	var server: RelayServer = s[0]
	var other: Netplay = s[1]
	assert_true(_step(g, server, [other], 300, func(): return g.online != null), "the room's first match starts")
	var first: OnlineMatch = g.online
	g.flow = g.Flow.MATCH_OVER
	g.flow_t = 0
	_step(g, server, [other], g.MATCH_OVER_MENU_AT + 2, func(): return false)
	assert_true(g.ui.is_open(), "the match-over choices come up")
	assert_eq(_labels(g.ui.top()), ["Next match", "Leave room"], "a room offers the next match, not a rematch:")
	var has_code := false
	for r in g.ui.top().rows():
		has_code = has_code or (r is RoomCodeButton and (r as RoomCodeButton).code == "KEV")
	assert_true(has_code, "with the room code to copy")
	g._room_next()
	assert_true(g.ui.top() is CharacterSelect, "Next match opens the fighter select")
	assert_true(g._room_screen != null and is_instance_valid(g._room_screen), "over the room's page")
	assert_true(g.netplay.picking, "and tells the server")
	_step(g, server, [other], 20, func(): return false)
	assert_true((g.ui.top() as CharacterSelect).solo_info.contains("picking"), "the select shows who's still picking: "
		+ (g.ui.top() as CharacterSelect).solo_info)
	(g.ui.top() as CharacterSelect).chosen.emit([["digby"], []])
	assert_eq(g.ui.top(), g._room_screen, "locked in: back on the room's page")
	assert_true(g.online == first, "waiting for the other player")
	other.request_next()
	other.send_pick(["pete"])
	assert_true(_step(g, server, [other], 120, func(): return g.online != first), "the next match starts")
	assert_eq(g.flow, g.Flow.FIGHT, "straight into the fight")
	assert_false(g.ui.is_open(), "the room's screens close")
	assert_eq(g.online.teams[g.online.local_side], ["digby"], "with the new pick:")
	assert_eq(g.online.teams[1 - g.online.local_side], ["pete"], "against theirs:")
	g._leave_online()
	g.free()


func test_in_the_game_the_other_player_leaving_a_room_goes_back_to_waiting_with_the_code() -> void:
	var g := _game()
	var s := _game_in_room(g, "kx7p", "cairn", "sno")
	var server: RelayServer = s[0]
	var other: Netplay = s[1]
	assert_true(_step(g, server, [other], 300, func(): return g.online != null), "the match starts")
	other.leave()
	assert_true(_step(g, server, [], 30, func(): return g.lobby != null), "back to the online screen")
	assert_true(g.netplay != null and g.netplay.phase == Netplay.Phase.HANDSHAKE, "still in the room on the server")
	assert_true(g.lobby.busy, "waiting")
	assert_true(g.lobby.status.contains("Waiting for a player"), "and says so: " + g.lobby.status)
	assert_true(g.lobby.code_button.visible and g.lobby.code_button.code == "KX7P", "with the code to copy")
	var c := _player(server, 3, "kx7p", 0, ["barkley"])
	assert_true(_step(g, server, [c], 300, func(): return g.online != null), "a newcomer plays them")
	assert_eq(g.online.teams[1 - g.online.local_side], ["barkley"], "")
	g._leave_online()
	g.free()


func test_in_the_game_ranked_match_over_has_a_rematch_and_back_to_online() -> void:
	var g := _game()
	g._start_match(20)
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var nets: Array = []
	for i in 2:
		var links := LoopLink.pair()
		server.add_client(links[0])
		var n := Netplay.new()
		n.ranked = true
		n.my_id = "abcd000%d" % i
		n.join("server", 0, [FIGHTERS[i]], links[1])
		nets.append(n)
	g.netplay = nets[0]
	g.lobby.busy = true
	assert_true(_step(g, server, [nets[1]], 300, func(): return g.online != null), "a ranked match starts")
	g.flow = g.Flow.MATCH_OVER
	g.flow_t = 0
	_step(g, server, [nets[1]], g.MATCH_OVER_MENU_AT + 2, func(): return false)
	assert_eq(_labels(g.ui.top()), ["Rematch", "Back to online", "Leave"], "ranked: a rematch, or back to the online screen:")
	(nets[1] as Netplay).leave()
	_step(g, server, [], 300, func(): return false)
	assert_true(g.ui.is_open() and g.flow == g.Flow.MATCH_OVER, "the other going back doesn't throw this one out")
	assert_eq(g._match_over_status.text, "Your opponent left", "it says they left:")
	assert_true(g.hud.banner != "DISCONNECTED", "nor call it a disconnection")
	g._leave_to_lobby()
	assert_true(g.lobby != null and g.ui.top() == g.lobby, "Back to online: the online screen")
	g.free()


func test_in_the_game_a_spectator_follows_a_rematch() -> void:
	var g := _game()
	g._start_match(20)
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var a := _player(server, 0)
	var b := _player(server, 1)
	var la := LoopLink.pair()
	server.add_client(la[0])
	var me := Netplay.new()
	me.spectate("server", 0, "", la[1])
	g._pending_watch = false
	g.netplay = me
	g.lobby.busy = true
	assert_true(_step(g, server, [a, b], 400, func(): return g.watch != null), "watching the match")
	var first: Referee = g.watch
	g.flow = g.Flow.MATCH_OVER
	g.flow_t = 0
	_step(g, server, [a, b], g.MATCH_OVER_MENU_AT + 2, func(): return false)
	assert_true(g.ui.is_open(), "the watcher's match-over screen")
	a.request_rematch()
	b.request_rematch()
	var says_picking := func() -> bool:
		return g._match_over_status != null and g._match_over_status.text.contains("picking")
	assert_true(_step(g, server, [a, b], 60, says_picking), "it says the players are picking: "
		+ (g._match_over_status.text if g._match_over_status != null else ""))
	assert_true(g._match_over_status.text.contains("Starts in "), "with the countdown: " + g._match_over_status.text)
	_step(g, server, [a, b], 30, func(): return a.rematch_pick() and b.rematch_pick())
	a.send_pick(["pete"])
	b.send_pick(["hissy"])
	assert_true(_step(g, server, [a, b], 120, func(): return g.watch != first), "the rematch: the game follows it")
	assert_eq(g.watch.teams, [["pete"], ["hissy"]], "with the new fighters:")
	assert_true(g.watch == g.netplay.watch, "showing the new match")
	assert_eq(g.flow, g.Flow.FIGHT, "back in the fight, not frozen on the match-over")
	assert_false(g.ui.is_open(), "")
	g._leave_online()
	g.free()


func test_in_the_game_a_room_spectator_sees_the_players_picking_then_the_next_match() -> void:
	var g := _game()
	g._start_match(20)
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var a := _player(server, 0, "r")
	var b := _player(server, 1, "r")
	var la := LoopLink.pair()
	server.add_client(la[0])
	var me := Netplay.new()
	me.spectate("server", 0, "r", la[1])
	g.netplay = me
	g.lobby.busy = true
	assert_true(_step(g, server, [a, b], 400, func(): return g.watch != null), "watching the room")
	var first: Referee = g.watch
	g.flow = g.Flow.MATCH_OVER
	g.flow_t = 0
	_step(g, server, [a, b], g.MATCH_OVER_MENU_AT + 2, func(): return false)
	a.request_next()
	var says_picking := func() -> bool:
		return g._match_over_status != null and g._match_over_status.text.contains("picking")
	assert_true(_step(g, server, [a, b], 30, says_picking), "it says the players are picking")
	a.send_pick(["sno"])
	b.request_next()
	b.send_pick(["digby"])
	assert_true(_step(g, server, [a, b], 120, func(): return g.watch != first), "then shows the next match")
	assert_eq(g.flow, g.Flow.FIGHT, "")
	g._leave_online()
	g.free()


## The game in a Quick match 1v1 on an in-memory server with another player. Returns
## [server, other].
func _game_in_quick_match(g: Node, mine: String, theirs: String) -> Array:
	g._start_match(20)  # Online
	var server := RelayServer.new()
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	var la := LoopLink.pair()
	server.add_client(la[0])
	var me := Netplay.new()
	me.my_name = "Me"
	me.join("server", 0, [mine], la[1])
	var other := _player(server, 1, "", 1, [theirs])
	g.lobby.use_fighter(mine)
	g.netplay = me
	g.lobby.busy = true
	return [server, other]


## Plays the game's match to its match-over screen.
func _to_match_over(g: Node, server: RelayServer, others: Array) -> void:
	g.flow = g.Flow.MATCH_OVER
	g.flow_t = 0
	_step(g, server, others, g.MATCH_OVER_MENU_AT + 2, func(): return false)


func test_in_the_game_a_quick_match_rematch_opens_the_select_and_starts_with_the_new_fighters() -> void:
	var g := _game()
	var s := _game_in_quick_match(g, "cairn", "sno")
	var server: RelayServer = s[0]
	var other: Netplay = s[1]
	var report := OS.get_user_data_dir().path_join("test_rematch_report.json")
	g._net_args["report"] = report
	assert_true(_step(g, server, [other], 300, func(): return g.online != null), "a Quick match starts")
	var first: OnlineMatch = g.online
	_to_match_over(g, server, [other])
	assert_eq(_labels(g.ui.top()), ["Rematch", "Leave"], "Quick match offers a rematch:")
	var again: Button = g.ui.top().rows()[0]
	again.pressed.emit()
	assert_true(g.netplay.rematch_local and again.disabled, "asked")
	other.request_rematch()
	assert_true(_step(g, server, [other], 60, func(): return g.ui.top() is CharacterSelect), "both asked: the fighter select opens")
	var pick: CharacterSelect = g.ui.top()
	assert_true(pick.solo, "just this player's")
	assert_eq(String(pick.roster[pick.cursor[0]]), "cairn", "with the last pick ready to lock in again:")
	assert_true(g._room_screen != null and g._room_screen.title == "REMATCH", "over the rematch page")
	assert_eq(_labels(g._room_screen), ["Same again", "Pick your fighter", "Leave"], "")
	assert_true(pick.solo_info.contains("Opponent is choosing"), "it says the opponent is choosing: " + pick.solo_info)
	_step(g, server, [other], 10, func(): return other.rematch_pick())
	other.send_pick(["barkley"])
	assert_true(_step(g, server, [other], 30, func(): return pick.solo_info.contains("Opponent locked in")),
		"then that they've locked in: " + pick.solo_info)
	assert_false(pick.solo_info.contains("Barkley"), "but not who with (that waits for the start)")
	assert_true(pick.solo_info.contains("Starts in "), "with the countdown: " + pick.solo_info)
	assert_true(g.online == first, "the old match is still on behind the select")
	pick.pick(0)  # one press: the same fighter again
	assert_true(pick.is_done(), "one press locks it in")
	pick._process(CharacterSelect.START_DELAY + 0.1)  # the LOCKED IN banner, then it's sent
	_step(g, server, [other], 40, func(): return g.online != first)
	assert_true(g.online != first, "the rematch starts")
	assert_eq(g.flow, g.Flow.FIGHT, "straight into the fight")
	assert_false(g.ui.is_open(), "the select and its page close")
	assert_eq(g.online.id, 2, "match 2:")
	assert_eq(g.online.teams[g.online.local_side], ["cairn"], "the same fighter (one press):")
	assert_eq(g.online.teams[1 - g.online.local_side], ["barkley"], "against their new one:")
	var kept = JSON.parse_string(FileAccess.get_file_as_string(report.get_basename() + "_m1.json"))
	assert_true(kept is Dictionary and int(kept["match"]) == 1, "--net-report kept match 1's report")
	assert_eq(kept["teams"][1 - g.online.local_side], ["sno"], "with match 1's fighters:")
	g._write_net_report()
	var now = JSON.parse_string(FileAccess.get_file_as_string(report))
	assert_true(now is Dictionary and int(now["match"]) == 2, "and the report itself is match 2's")
	assert_eq(now["teams"][1 - g.online.local_side], ["barkley"], "with the new fighters:")
	g._net_args.erase("report")
	DirAccess.remove_absolute(report)
	DirAccess.remove_absolute(report.get_basename() + "_m1.json")
	# Same again on the page locks in at once too.
	_to_match_over(g, server, [other])
	(g.ui.top().rows()[0] as Button).pressed.emit()
	other.request_rematch()
	assert_true(_step(g, server, [other], 60, func(): return g.ui.top() is CharacterSelect), "the select again")
	g.ui.pop()  # back out of the select to the page
	assert_eq(g.ui.top(), g._room_screen, "back on the rematch page")
	(g._room_screen.rows()[0] as Button).pressed.emit()  # Same again
	_step(g, server, [other], 10, func(): return other.rematch_pick())
	other.send_pick(["sno"])
	var second: OnlineMatch = g.online
	assert_true(_step(g, server, [other], 60, func(): return g.online != second), "match 3 starts")
	assert_eq(g.online.teams[g.online.local_side], ["cairn"], "")
	assert_eq(g.online.id, 3, "counting up:")
	g._leave_online()
	g.free()


func test_in_the_game_the_rematch_countdown_running_out_starts_with_the_last_fighter() -> void:
	var g := _game()
	var s := _game_in_quick_match(g, "cairn", "sno")
	var server: RelayServer = s[0]
	var other: Netplay = s[1]
	assert_true(_step(g, server, [other], 300, func(): return g.online != null), "a Quick match starts")
	var first: OnlineMatch = g.online
	_to_match_over(g, server, [other])
	g.netplay.request_rematch()
	other.request_rematch()
	assert_true(_step(g, server, [other], 60, func(): return g.ui.top() is CharacterSelect), "picking")
	var pick: CharacterSelect = g.ui.top()
	assert_true(pick.solo_info.contains("Starts in 20 s") or pick.solo_info.contains("Starts in 19 s"),
		"the select shows the countdown: " + pick.solo_info)
	assert_true(g._room_status_label.text.contains("Starts in "), "and so does the page: " + g._room_status_label.text)
	_step(g, server, [other], 10, func(): return other.rematch_pick())
	other.send_pick(["barkley"])
	assert_true(_step(g, server, [other], 30, func(): return pick.solo_info.contains("Opponent locked in")), "they lock in")
	server.clock_skip_ms += 20001  # this player never does: time runs out
	assert_true(_step(g, server, [other], 40, func(): return g.online != first), "the rematch starts anyway")
	assert_eq(g.flow, g.Flow.FIGHT, "straight into the fight")
	assert_false(g.ui.is_open(), "the select and its page close")
	assert_eq(g.online.teams[g.online.local_side], ["cairn"], "with this player's last fighter:")
	assert_eq(g.online.teams[1 - g.online.local_side], ["barkley"], "against their new one:")
	g._leave_online()
	g.free()


func test_in_the_game_the_other_player_leaving_during_the_rematch_pick_goes_back_to_online() -> void:
	var g := _game()
	var s := _game_in_quick_match(g, "cairn", "sno")
	var server: RelayServer = s[0]
	var other: Netplay = s[1]
	assert_true(_step(g, server, [other], 300, func(): return g.online != null), "a Quick match starts")
	_to_match_over(g, server, [other])
	g.netplay.request_rematch()
	other.request_rematch()
	assert_true(_step(g, server, [other], 60, func(): return g.ui.top() is CharacterSelect), "picking")
	other.leave()
	var gone := func() -> bool:
		return g.ui.top() is UiScreen and (g.ui.top() as UiScreen).title == "REMATCH" and g._room_screen == null
	assert_true(_step(g, server, [], 30, gone), "the select closes")
	assert_eq((g.ui.top() as UiScreen).subtitle, "Your opponent left", "and says the other player left:")
	assert_true(g.hud.banner != "DISCONNECTED", "no disconnection banner over it")
	assert_true(_step(g, server, [], 300, func(): return g.lobby != null), "then back to the online screen by itself")
	assert_true(g.netplay == null, "the session is over")
	g.free()


func test_in_the_game_a_direct_rematch_picks_too() -> void:
	var g := _game()
	g._start_match(20)
	var links := LoopLink.pair()
	var host := Netplay.new()
	host.locked_ticks = 0
	host.host(0, ["culvert"], links[0])
	var me := Netplay.new()
	me.join("loop", 0, ["cairn"], links[1])
	g.netplay = me
	g.lobby.busy = true
	var server := RelayServer.new()  # not used: nobody joins it
	server.rematch_locked_ms = 0  # a rematch starts once both are in
	assert_true(_step(g, server, [host], 300, func(): return g.online != null), "a direct match starts")
	var first: OnlineMatch = g.online
	_to_match_over(g, server, [host])
	g.netplay.request_rematch()
	host.request_rematch()
	assert_true(_step(g, server, [host], 60, func(): return g.ui.top() is CharacterSelect), "the host opens the pick")
	assert_true(host.rematch_pick(), "on the host too")
	(g.ui.top() as CharacterSelect).chosen.emit([["digby"], []])
	host.send_pick(["craglash"])
	assert_true(_step(g, server, [host], 60, func(): return g.online != first), "the rematch starts")
	assert_eq(g.online.teams, [["craglash"], ["digby"]], "with both new picks:")
	assert_eq(host.game.teams, g.online.teams, "the host agrees:")
	g._leave_online()
	g.free()
