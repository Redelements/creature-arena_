extends TestCase
## The seat table (LocalSeats): who gets which controller at a match's start, a pad
## unplugged and plugged back mid-match, whose pad an event is, and the per-controller
## reading that follows the gamepad remaps (PlayerInput.pad_map).


func _seats() -> LocalSeats:
	return LocalSeats.new()


func test_solo_player_1_listens_to_any_pad_and_the_keyboard() -> void:
	var s := _seats()
	assert_eq(s.assign(1, [0, 1]), "", "nobody missing")
	assert_eq(s.device_of(0), PlayerInput.ANY_PAD, "any pad")
	assert_true(s.inputs[0].keyboard, "and the keyboard")
	for k in [1, 2, 3]:
		assert_eq(s.device_of(k), PlayerInput.NO_PAD, "seat %d empty" % k)
		assert_false(s.inputs[k].keyboard, "seats 2-4 never have the keyboard")
	assert_eq(s.seat_of_device(7), 0, "any pad is player 1's")


func test_a_pad_each_gives_everyone_one_in_order() -> void:
	var s := _seats()
	assert_eq(s.assign(3, [4, 5, 6]), "", "")
	assert_eq(s.device_of(0), 4, "player 1 the first pad")
	assert_true(s.inputs[0].keyboard, "and still the keyboard")
	assert_eq(s.device_of(1), 5, "")
	assert_eq(s.device_of(2), 6, "")
	assert_eq(s.device_of(3), PlayerInput.NO_PAD, "nobody in seat 4")
	assert_eq(s.seat_of_device(6), 2, "")
	assert_eq(s.seat_of_device(9), -1, "a pad nobody plays on")
	assert_true(s.seated(2), "")
	assert_false(s.seated(3), "")


func test_one_pad_short_player_1_takes_the_keyboard() -> void:
	var s := _seats()
	assert_eq(s.assign(2, [3]), "", "two people, one pad: nobody missing")
	assert_eq(s.device_of(0), PlayerInput.NO_PAD, "player 1 on keyboard and mouse")
	assert_true(s.inputs[0].keyboard, "")
	assert_eq(s.device_of(1), 3, "player 2 the pad")
	assert_eq(s.seat_of_device(3), 1, "")
	assert_eq(s.seat_of_device(8), -1, "player 1 isn't on any pad now")


func test_missing_controllers_are_asked_for() -> void:
	var s := _seats()
	assert_eq(s.assign(3, []), "Connect 2 controllers for players 2-3", "")
	assert_eq(_seats().assign(2, []), "Connect 1 controller for players 2", "")
	assert_eq(_seats().assign(4, [1]), "Connect 2 controllers for players 2-4", "")
	assert_false(s.seated(1), "")


func test_a_pad_plugged_in_later_fills_the_empty_seat() -> void:
	var s := _seats()
	s.assign(3, [0])
	assert_eq(s.device_of(1), 0, "")
	assert_eq(s.device_of(2), PlayerInput.NO_PAD, "")
	assert_eq(s.pad_found(1, "guid-b"), 2, "the waiting seat")
	assert_eq(s.device_of(2), 1, "")
	assert_eq(s.pad_found(2, "guid-c"), -1, "nobody else is waiting")


func test_an_unplugged_pad_frees_its_seat_and_the_same_pad_takes_it_back() -> void:
	var s := _seats()
	s.assign(3, [0, 1, 2], {0: "g0", 1: "g1", 2: "g2"})
	s.inputs[2]._pad_prev = {"guard": true}
	assert_eq(s.pad_lost(2), 2, "player 3 lost theirs")
	assert_eq(s.device_of(2), PlayerInput.NO_PAD, "")
	assert_true(s.inputs[2]._pad_prev.is_empty(), "nothing stays held")
	assert_eq(s.pad_lost(2), -1, "already gone")
	assert_eq(s.pad_lost(9), -1, "a pad nobody held")
	assert_eq(s.pad_lost(1), 1, "player 2 too")
	# Player 3's pad comes back first, under a new id: it goes to seat 3 by GUID, not to the
	# first waiting seat.
	assert_eq(s.pad_found(5, "g2"), 2, "the same pad, its own seat")
	assert_eq(s.device_of(2), 5, "")
	assert_eq(s.pad_found(6, "other"), 1, "an unknown pad takes the first seat still waiting")
	assert_eq(s.device_of(1), 6, "")
	assert_true(s.lost.is_empty(), "")


func test_player_1_loses_their_pad_and_keeps_the_keyboard() -> void:
	var s := _seats()
	s.assign(2, [0, 1])
	assert_eq(s.pad_lost(0), 0, "")
	assert_eq(s.device_of(0), PlayerInput.NO_PAD, "")
	assert_true(s.inputs[0].keyboard, "the keyboard still plays")
	assert_true(s.seated(0), "")
	assert_eq(s.pad_found(0, ""), 0, "")


func test_events_belong_to_the_seat_holding_the_pad() -> void:
	var s := _seats()
	s.assign(2, [0, 1])
	var jb := InputEventJoypadButton.new()
	jb.device = 1
	jb.button_index = JOY_BUTTON_START
	jb.pressed = true
	assert_eq(s.owner_of_event(jb), 1, "player 2's Start")
	jb.device = 0
	assert_eq(s.owner_of_event(jb), 0, "")
	jb.device = 3
	assert_eq(s.owner_of_event(jb), -1, "a pad nobody plays on")
	var key := InputEventKey.new()
	key.pressed = true
	assert_eq(s.owner_of_event(key), 0, "the keyboard is player 1's")
	assert_eq(s.note_event(jb), -1, "nobody takes it")
	jb.device = 1
	assert_eq(s.note_event(jb), 1, "")
	assert_eq(s.inputs[1].pad_id, 1, "player 2 noted their pad")
	assert_eq(s.rumble_device(1), 1, "and it's the one to rumble")
	assert_eq(s.rumble_device(0), -1, "player 1 hasn't touched a pad")
	s.note_event(key)
	assert_eq(s.rumble_device(0), -1, "")


func test_pad_map_follows_the_gamepad_remaps() -> void:
	Controls.setup()
	var map := PlayerInput.pad_map()
	assert_eq((map["light"]["buttons"] as Array), [JOY_BUTTON_A], "A is light by default")
	assert_eq((map["skill_2"]["buttons"] as Array), [JOY_BUTTON_B], "")
	assert_eq((map["surge"]["axes"] as Array), [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], "RT is surge")
	assert_eq((map["tag"]["axes"] as Array), [[JOY_AXIS_TRIGGER_LEFT, 1.0]], "")
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	Controls.rebind("gamepad", "pad_light", b)
	map = PlayerInput.pad_map()
	assert_eq((map["light"]["buttons"] as Array), [JOY_BUTTON_B], "light is B now")
	assert_eq((map["skill_2"]["buttons"] as Array), [JOY_BUTTON_A], "and skill 2 took A (a swap)")
	Controls.reset("gamepad")
	map = PlayerInput.pad_map()
	assert_eq((map["light"]["buttons"] as Array), [JOY_BUTTON_A], "back to the default")
	assert_false(PlayerInput.pad_action_held(0, map["light"]), "no controller 0 here: nothing held")


# ------------------------------------------------------------------ the join screen

func test_joining_claims_seats_in_order_and_packs_them_at_the_end() -> void:
	var s := _seats()
	s.begin(3)
	assert_eq(s.joined(), 0, "player 1 is undecided until they press")
	assert_eq(s.claim(7), 0, "the first pad is player 1's (with the keyboard)")
	assert_true(s.inputs[0].keyboard, "")
	assert_eq(s.claim(7), 0, "pressing again keeps the seat")
	assert_eq(s.claim(9), 1, "")
	assert_eq(s.claim(4), 2, "")
	assert_eq(s.claim(5), -1, "full: three seats")
	assert_eq(s.joined(), 3, "")
	s.unclaim(1)
	assert_eq(s.joined(), 2, "")
	assert_eq(s.holder_of(9), -1, "")
	assert_eq(s.finish(), 3 - 1, "two play")
	assert_eq(s.device_of(1), 4, "seat 3's pad moved down into the hole")
	assert_eq(s.device_of(2), PlayerInput.NO_PAD, "")
	assert_eq(s.seat_of_device(4), 1, "")


func test_player_1_on_the_keyboard_alone_then_the_only_pad_is_player_2s() -> void:
	var s := _seats()
	s.begin(2)
	assert_true(s.keyboard_only(), "")
	assert_false(s.keyboard_only(), "already decided")
	assert_eq(s.claim(0), 1, "the pad goes to player 2")
	assert_eq(s.finish(), 2, "")
	assert_eq(s.device_of(0), PlayerInput.NO_PAD, "player 1 never reads that pad")
	assert_eq(s.seat_of_device(0), 1, "")
	s.unclaim(0)
	assert_eq(s.device_of(0), PlayerInput.ANY_PAD, "player 1 undecided again")


func test_finishing_with_nobody_else_leaves_player_1_on_any_pad() -> void:
	var s := _seats()
	s.begin(2)
	assert_eq(s.finish(), 1, "")
	assert_eq(s.device_of(0), PlayerInput.ANY_PAD, "solo: any pad is theirs")


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _press(action: String) -> void:
	for down in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		_root().push_input(ev)


func _pad(device: int, button: JoyButton) -> void:
	for down in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = device
		ev.button_index = button
		ev.pressed = down
		_root().push_input(ev)


func _screen(need: int) -> Array:
	Controls.setup()
	var st := ScreenStack.new()
	_root().add_child(st)
	var s := _seats()
	s.begin(need)
	var scr := SeatScreen.new()
	scr.need = need
	scr.most = need
	scr.seats = s
	st.push(scr)
	return [st, scr, s]


func test_the_join_screen_seats_two_pads_and_starts_on_start() -> void:
	var made := _screen(2)
	var st: ScreenStack = made[0]
	var scr: SeatScreen = made[1]
	var s: LocalSeats = made[2]
	var got := [0, 0]
	scr.done.connect(func(): got[0] += 1)
	scr.cancelled.connect(func(): got[1] += 1)
	_pad(1, JOY_BUTTON_START)
	assert_eq(got[0], 0, "nobody seated yet: Start does nothing")
	_pad(1, JOY_BUTTON_A)
	assert_eq(s.device_of(0), 1, "player 1 took pad 1")
	assert_false(scr.ready_to_go(), "one of two")
	_pad(2, JOY_BUTTON_A)
	assert_eq(s.device_of(1), 2, "player 2 took pad 2")
	assert_true(scr.ready_to_go(), "")
	_pad(2, JOY_BUTTON_B)
	assert_eq(s.device_of(1), PlayerInput.NO_PAD, "B gave the seat back")
	_pad(2, JOY_BUTTON_START)
	assert_eq(got[0], 0, "not ready: Start waits")
	_pad(3, JOY_BUTTON_A)
	assert_eq(s.device_of(1), 3, "another pad takes the seat")
	_pad(3, JOY_BUTTON_START)
	assert_eq(got[0], 1, "Start on a seated pad goes on")
	assert_eq(got[1], 0, "")
	assert_true(st.is_open(), "the screen stays until main pops it")
	st.free()


func test_the_join_screen_on_the_keyboard_enter_then_enter() -> void:
	var made := _screen(2)
	var st: ScreenStack = made[0]
	var scr: SeatScreen = made[1]
	var s: LocalSeats = made[2]
	var got := [0, 0]
	scr.done.connect(func(): got[0] += 1)
	scr.cancelled.connect(func(): got[1] += 1)
	_press("ui_accept")
	assert_eq(s.device_of(0), PlayerInput.NO_PAD, "Enter: player 1 on the keyboard alone")
	_press("ui_accept")
	assert_eq(got[0], 0, "one seat of two: Enter waits")
	_pad(0, JOY_BUTTON_A)
	assert_eq(s.device_of(1), 0, "the pad is player 2's")
	_press("ui_accept")
	assert_eq(got[0], 1, "Enter goes on")
	_pad(0, JOY_BUTTON_B)
	assert_eq(got[1], 0, "player 2's B isn't a cancel")
	_press("ui_cancel")
	assert_eq(got[1], 1, "Esc from player 1 leaves")
	assert_true(st.is_open(), "main closes the screen, the stack didn't pop it by itself")
	st.free()


# ------------------------------------------------------------------ the free-for-all's seats

func _game() -> Node:
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = "user://test_local_seats.cfg"
	_root().add_child(g)
	return g


func test_a_free_for_all_started_headless_seats_locals_then_cpus() -> void:
	var g := _game()
	g._skip_select = true
	g._cli_locals = 3
	g._start_match(g.mode_index("Brawl"))
	assert_eq(g.sides, [g.Side.PLAYER, g.Side.PLAYER2, g.Side.PLAYER3, g.Side.CPU], "three people, one CPU:")
	assert_eq(g.seats.humans, 3, "")
	g._cli_locals = 0
	g._start_match(g.mode_index("Chaos Cup"))
	assert_eq(g.sides, [g.Side.PLAYER, g.Side.CPU, g.Side.CPU, g.Side.CPU], "no --locals: one, as before:")
	g.free()


func test_the_join_screen_decides_how_many_play_a_free_for_all() -> void:
	var g := _game()
	g._start_match(g.mode_index("Brawl"))
	assert_true(g.ui.top() is SeatScreen, "who's playing first")
	var ss: SeatScreen = g.ui.top()
	assert_eq(ss.need, 1, "one is enough")
	assert_eq(ss.most, 4, "up to four")
	_press("ui_accept")  # player 1 on the keyboard
	g.seats.claim(0)
	g.seats.claim(1)
	assert_eq(g.seats.joined(), 3, "")
	_press("ui_accept")
	assert_true(g.ui.top() is CharacterSelect, "then the pick")
	var cs: CharacterSelect = g.ui.top()
	assert_eq(cs.players, 3, "a picker a seat")
	assert_eq(cs.columns, 3, "")
	for p in 3:
		cs.pick(p, true)
	assert_true(cs.is_done(), "")
	cs._process(CharacterSelect.START_DELAY + 0.1)
	assert_eq(g.sides, [g.Side.PLAYER, g.Side.PLAYER2, g.Side.PLAYER3, g.Side.CPU], "three seats and a CPU:")
	assert_eq(g.seats.device_of(1), 0, "player 2 on pad 0")
	assert_eq(g.seats.device_of(2), 1, "player 3 on pad 1")
	g.free()


# ------------------------------------------------------------------ teams with four seats

func test_seats_pick_sides_and_pack_with_them() -> void:
	var s := _seats()
	s.begin(4)
	assert_eq(s.side_pick, [0, 1, 0, 1], "seats alternate by default")
	s.claim(0)
	s.claim(1)
	s.claim(2)
	s.set_side(1, 0)
	s.set_side(2, 1)
	s.unclaim(1)
	assert_eq(s.finish(), 2, "")
	assert_eq(s.device_of(1), 2, "seat 3's pad moved down")
	assert_eq(s.side_of_seat(1), 1, "with its side")
	assert_eq(s.seats_on(0), [0], "")
	assert_eq(s.seats_on(1), [1], "")


func test_a_local_team_battle_started_headless_seats_everyone_alternating_sides() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(g.mode_index("Team battle: 2v2 local"))
	assert_eq(g.sides, [g.Side.PLAYER, g.Side.PLAYER3, g.Side.PLAYER2, g.Side.PLAYER4],
		"side 0's slots: seats 1 and 3; side 1's: seats 2 and 4:")
	assert_true(g.team_battle != null, "")
	assert_eq(g._viewer_team(), -1, "people on both sides: nobody's vision is hidden")
	g._cli_locals = 3
	g._start_match(g.mode_index("Team Deathmatch: 2v2 local"))
	assert_eq(g.sides, [g.Side.PLAYER, g.Side.PLAYER3, g.Side.PLAYER2, g.Side.CPU], "three people: a CPU on blue")
	g.free()


func test_the_join_screen_sides_feed_the_team_pick_and_the_match() -> void:
	var g := _game()
	g._start_match(g.mode_index("Team battle: 2v2 local"))
	assert_true(g.ui.top() is SeatScreen, "")
	var ss: SeatScreen = g.ui.top()
	assert_true(ss.teams, "a team join screen")
	assert_eq(ss.need, 2, "")
	_press("ui_accept")  # player 1, keyboard, red by default
	g.seats.claim(0)  # player 2: blue by default
	g.seats.claim(1)  # player 3: red by default
	_pad(1, JOY_BUTTON_DPAD_RIGHT)  # player 3 moves to blue
	assert_eq(g.seats.side_of_seat(2), 1, "Right: blue")
	_press("ui_left")
	assert_eq(g.seats.side_of_seat(0), 0, "Left keeps player 1 red")
	assert_true(ss.ready_to_go(), "red 1, blue 2: within two a side")
	_pad(0, JOY_BUTTON_DPAD_LEFT)  # player 2 to red
	_press("ui_right")  # player 1 to blue: red 1 (p2), blue 2 (p1, p3)
	_pad(1, JOY_BUTTON_DPAD_LEFT)  # player 3 to red: red 2, blue 1
	assert_true(ss.ready_to_go(), "")
	_press("ui_accept")
	assert_true(g.ui.top() is CharacterSelect, "then the pick, a column a seat")
	var cs: CharacterSelect = g.ui.top()
	assert_eq(cs.players, 3, "")
	assert_eq(cs.team_size, 1, "one fighter each")
	assert_true(String(cs.labels[0]).contains("BLUE"), "player 1's column says blue: " + String(cs.labels[0]))
	for p in 3:
		cs.pick(p, true)
	cs._process(CharacterSelect.START_DELAY + 0.1)
	assert_eq(g.sides, [g.Side.PLAYER2, g.Side.PLAYER3, g.Side.PLAYER, g.Side.CPU],
		"red: seats 2 and 3; blue: seat 1 and a CPU:")
	assert_eq(String(g.sim.creatures[2].def["id"]), String(cs.teams[0][0]), "player 1 plays their own pick, on blue")
	g.free()


# ------------------------------------------------------------------ co-op: everyone vs the CPU

func test_coop_puts_everyone_on_one_side_against_a_cpu_side() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(g.mode_index("Team battle: 4v4 co-op vs CPU"))
	var P: int = g.Side.PLAYER
	assert_eq(g.sides, [P, g.Side.PLAYER2, g.Side.PLAYER3, g.Side.PLAYER4, g.Side.CPU, g.Side.CPU, g.Side.CPU, g.Side.CPU],
		"four people on red, four CPUs on blue:")
	assert_eq(g.team_battle.size, 4, "a 4v4 on the team rules (max_size 4)")
	assert_eq(g._viewer_team(), 0, "one team here: its vision")
	g._cli_locals = 2
	g._start_match(g.mode_index("Capture the Flag: 4v4 co-op vs CPU"))
	assert_eq(g.sides, [P, g.Side.PLAYER2, g.Side.CPU, g.Side.CPU, g.Side.CPU, g.Side.CPU, g.Side.CPU, g.Side.CPU],
		"two people and two CPU teammates:")
	assert_true(g.team_battle.ctf, "")
	assert_eq(g.local_slots(), [0, 1], "")
	g._start_match(g.mode_index("Team Deathmatch: 4v4 co-op vs CPU"))
	assert_eq(g.team_battle.score_to_win(), 18, "a 4v4 Deathmatch has its own target")
	g.free()


func test_the_coop_join_screen_never_asks_for_a_side() -> void:
	var g := _game()
	g._start_match(g.mode_index("Team battle: 4v4 co-op vs CPU"))
	var ss: SeatScreen = g.ui.top()
	assert_false(ss.teams, "no sides to pick")
	assert_eq(ss.need, 1, "")
	_press("ui_accept")
	g.seats.claim(3)
	_pad(3, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(g.seats.side_of_seat(1), 0, "Right changes nothing: everyone is red")
	_press("ui_accept")
	var cs: CharacterSelect = g.ui.top()
	assert_eq(cs.players, 2, "")
	assert_eq(String(cs.labels[1]), "PLAYER 2", "no side on the label")
	for p in 2:
		cs.pick(p, true)
	cs._process(CharacterSelect.START_DELAY + 0.1)
	assert_eq(g.sides.slice(0, 4), [g.Side.PLAYER, g.Side.PLAYER2, g.Side.CPU, g.Side.CPU], "")
	assert_eq(g.sides.slice(4), [g.Side.CPU, g.Side.CPU, g.Side.CPU, g.Side.CPU], "")
	g.free()


# ------------------------------------------------------------------ polish

func test_a_pad_unplugged_mid_fight_pauses_an_offline_match() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(g.mode_index("Versus: 2 players"))
	g.seats.inputs[1].pad_device = 5  # player 2 holds pad 5
	g.flow = g.Flow.FIGHT
	g._on_pad_changed(5, false)
	assert_true(g.paused, "the fight waits for player 2's controller")
	assert_true(g.ui.top() is PauseScreen, "")
	assert_eq(g.seats.device_of(1), PlayerInput.NO_PAD, "")
	g._close_ui()
	g.paused = false
	g._on_pad_changed(5, true)
	assert_eq(g.seats.device_of(1), 5, "back in their seat")
	assert_false(g.paused, "plugging in never pauses")
	g.free()


func test_only_player_1_earns_in_local_play() -> void:
	var g := _game()
	g._skip_select = true
	g._cli_locals = 3
	g._start_match(g.mode_index("Brawl"))
	var r: Dictionary = g.show_ctl.progress_report(false)
	assert_eq(String(r[Progress.R_KIND]), "local", "three people here: local play")
	assert_eq((r[Progress.R_PLAYERS] as Array).size(), 1, "but one earns:")
	assert_eq(int(r[Progress.R_PLAYERS][0][Progress.P_SLOT]), 0, "player 1")
	assert_true(bool(r.get(Progress.R_CPUS, false)), "with a CPU in the match")
	g.free()
