extends TestCase
## The menu system (ScreenStack, UiScreen, OptionRow) and the pause menu, driven by the
## same input events a player makes.


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_root().push_input(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	_root().push_input(up)


func _focus() -> Control:
	return _root().gui_get_focus_owner()


class ThreeRows extends UiScreen:
	var picked := ""

	func build() -> void:
		add_button("One", func(): picked = "one")
		add_button("Two", func(): picked = "two")
		add_button("Three", func(): picked = "three")


func _stack() -> ScreenStack:
	Controls.setup()
	var s := ScreenStack.new()
	_root().add_child(s)
	return s


func test_up_and_down_walk_the_rows_and_wrap_round() -> void:
	var st := _stack()
	var scr := ThreeRows.new()
	st.push(scr)
	var r := scr.rows()
	assert_eq(_focus(), r[0], "the first row starts focused")
	_press("ui_down")
	assert_eq(_focus(), r[1], "down")
	_press("ui_down")
	_press("ui_down")
	assert_eq(_focus(), r[0], "past the last row: back to the first")
	_press("ui_up")
	assert_eq(_focus(), r[2], "up from the first: the last")
	_press("ui_accept")
	assert_eq(scr.picked, "three", "Enter / A presses it:")
	st.free()


func test_back_closes_the_top_screen_and_restores_focus_below() -> void:
	var st := _stack()
	var a := ThreeRows.new()
	st.push(a)
	_press("ui_down")
	var was := _focus()
	st.push(ThreeRows.new())
	assert_false(a.visible, "the screen below is hidden")
	var emptied := [false]
	st.emptied.connect(func(): emptied[0] = true)
	_press("ui_cancel")  # B / Esc
	assert_eq(st.screens.size(), 1, "back closed the top one")
	assert_true(a.visible, "the one below shows again")
	assert_eq(_focus(), was, "on the row it was on")
	_press("menu_back")  # View
	assert_false(st.is_open(), "and back again closes the last")
	assert_true(emptied[0], "the stack says so")
	st.free()


func test_an_option_row_changes_with_left_and_right_without_moving_focus() -> void:
	var st := _stack()
	var scr := UiScreen.new()
	st.push(scr)
	var got := [-1]
	var o := scr.add_option("Level", ["Easy", "Normal", "Hard"], 1, func(i): got[0] = i)
	scr.add_button("Back", func(): pass)
	scr.link_focus()
	o.grab_focus()
	_press("ui_right")
	assert_eq(o.index, 2, "right steps forward:")
	assert_eq(got[0], 2, "and reports it:")
	assert_eq(_focus(), o, "focus stays on the row")
	_press("ui_right")
	assert_eq(o.index, 0, "and wraps round:")
	_press("ui_left")
	assert_eq(o.index, 2, "left steps back:")
	assert_true(o.value_text().contains("Hard"), "the row shows the value: " + o.value_text())
	st.free()


func test_a_confirm_starts_on_no_and_back_means_no() -> void:
	var st := _stack()
	var c := ConfirmScreen.new("Quit?")
	var answer := [null]
	c.answered.connect(func(yes): answer[0] = yes)
	st.push(c)
	assert_eq((_focus() as Button).text, "No", "No is focused, so a stray press can't do it")
	_press("ui_cancel")
	assert_eq(answer[0], false, "back answers no:")
	assert_false(st.is_open(), "and closes it")
	st.free()


func test_prompts_follow_the_device() -> void:
	assert_true(Prompts.line(true, ["select", "back"]).contains("A select"), "")
	assert_true(Prompts.line(true, ["back"]).contains("B back"), "")
	assert_true(Prompts.line(false, ["back"]).contains("Esc back"), "")


func test_b_and_a_are_menu_buttons() -> void:
	Controls.setup()
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	assert_true(b.is_action_pressed("ui_cancel"), "B is Back in menus")
	assert_false(b.is_action_pressed("pause"), "but never pauses a fight (it's Skill 2)")
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	assert_true(start.is_action_pressed("pause"), "Start pauses")


# ------------------------------------------------------------------ the game's pause menu

const TEST_SETTINGS := "user://test_settings.cfg"


## The game, with settings of its own (fresh each time, never the player's).
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


func test_pause_freezes_the_fight_and_resume_carries_on() -> void:
	var g := _game()
	g._start_match(2)  # CPU vs CPU
	_tick(g, 120)
	var t: int = g.sim.tick
	_press("pause")
	assert_true(g.paused, "Start / Esc pauses")
	assert_true(g.ui.top() is PauseScreen, "the pause menu is up")
	_tick(g, 60)
	assert_eq(g.sim.tick, t, "nothing moves while paused:")
	_press("pause")
	assert_false(g.paused, "pressing it again resumes")
	_tick(g, 10)
	assert_gt(float(g.sim.tick), float(t), "and the fight carries on")
	g.free()


func test_quitting_from_the_pause_menu_asks_first() -> void:
	var g := _game()
	g._start_match(2)
	_tick(g, 30)
	_press("pause")
	var pause: UiScreen = g.ui.top()
	var quit: Button = pause.rows().back()
	quit.grab_focus()
	_press("ui_accept")
	assert_true(g.ui.top() is ConfirmScreen, "a confirm comes up")
	_press("ui_accept")  # on No
	assert_true(g.ui.top() is PauseScreen, "No: back on the pause menu")
	assert_true(g.flow != g.Flow.MENU, "still in the match")
	(pause.rows().back() as Button).grab_focus()
	_press("ui_accept")
	_press("ui_up")  # Yes
	_press("ui_accept")
	assert_eq(g.flow, g.Flow.MENU, "Yes: the title menu")
	assert_false(g.paused, "not paused any more")
	assert_true(g.ui.top() is TitleScreen, "the title screen, nothing else")
	assert_eq(g.ui.screens.size(), 1, "")
	g.free()


func test_start_at_match_over_is_still_a_rematch() -> void:
	var g := _game()
	g._start_match(2)
	g.flow = g.Flow.MATCH_OVER
	_press("pause")
	assert_false(g.paused, "the match-over screen doesn't pause")
	g.free()


# ------------------------------------------------------------------ character select

func _pad(device: int, button: JoyButton) -> void:
	for down in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = device
		ev.button_index = button
		ev.pressed = down
		_root().push_input(ev)


func _select(size: int, two: bool) -> Array:
	var st := _stack()
	var cs := CharacterSelect.new()
	cs.setup("DUEL", size, ["PLAYER 1", "PLAYER 2" if two else "CPU"], two)
	if two:
		cs.p1_pad = 0
		cs.p2_pad = 1
	st.push(cs)
	return [st, cs]


func test_against_the_cpu_player_1_picks_both_teams() -> void:
	var made := _select(3, false)
	var cs: CharacterSelect = made[1]
	var got := []
	cs.chosen.connect(func(t): got.append(t))
	for i in 3:
		_press("ui_accept")
		_press("ui_right")
	assert_eq((cs.teams[0] as Array).size(), 3, "player 1's team is full:")
	assert_eq(cs.side_of(0), 1, "now player 1 picks for the CPU")
	for i in 3:
		_press("ui_right")
		_press("ui_accept")
	assert_true(cs.is_done(), "both teams full")
	cs._process(1.0)
	assert_eq(got.size(), 1, "the match starts:")
	assert_eq(got[0][0], ["cairn", "culvert", "craglash"], "player 1's picks, in order:")
	assert_eq((got[0][1] as Array).size(), 3, "")
	(made[0] as Node).free()


func test_two_players_pick_at_once_with_their_own_pads() -> void:
	var made := _select(1, true)
	var cs: CharacterSelect = made[1]
	_pad(1, JOY_BUTTON_DPAD_RIGHT)
	_pad(1, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(cs.cursor[1], 2, "player 2's d-pad moves player 2's cursor:")
	assert_eq(cs.cursor[0], 0, "not player 1's")
	_pad(1, JOY_BUTTON_A)
	assert_eq(cs.teams[1], ["craglash"], "player 2's A picks for player 2:")
	assert_true(cs.teams[0].is_empty(), "")
	_pad(0, JOY_BUTTON_DPAD_DOWN)
	_pad(0, JOY_BUTTON_A)
	assert_eq(cs.teams[0], [String(cs.roster[CharacterSelect.COLS])], "player 1 picks with theirs:")
	assert_true(cs.is_done(), "1 v 1: done")
	_pad(1, JOY_BUTTON_B)
	assert_true(cs.teams[1].is_empty(), "player 2's B takes back player 2's pick")
	assert_eq((cs.teams[0] as Array).size(), 1, "and only theirs")
	(made[0] as Node).free()


func test_undo_then_leave() -> void:
	var made := _select(3, false)
	var cs: CharacterSelect = made[1]
	var left := [false]
	cs.cancelled.connect(func(): left[0] = true)
	_press("ui_accept")
	_press("ui_cancel")
	assert_true(cs.teams[0].is_empty(), "B / Esc takes the pick back")
	assert_false(left[0], "without leaving")
	_press("ui_cancel")
	assert_true(left[0], "with nothing to take back, it leaves")
	(made[0] as Node).free()


func test_no_fighter_twice_on_a_team_and_random_respects_that() -> void:
	var made := _select(3, false)
	var cs: CharacterSelect = made[1]
	_press("ui_accept")
	_press("ui_accept")
	assert_eq(cs.teams[0], ["cairn"], "the same fighter can't be picked twice:")
	for i in 2:
		cs.pick(0, true)
	var t: Array = cs.teams[0]
	assert_eq(t.size(), 3, "random fills the team:")
	assert_true(t[1] != "cairn" and t[2] != "cairn" and t[1] != t[2], "with fighters not on it yet: %s" % str(t))
	(made[0] as Node).free()


func test_the_mouse_picks_a_tile() -> void:
	var made := _select(1, false)
	var cs: CharacterSelect = made[1]
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = cs._tile_rect(4).get_center() + cs._o  # the grid sits in a centred stage
	cs._gui_input(ev)
	assert_eq(cs.teams[0], [String(cs.roster[4])], "a click picks what's under it:")
	(made[0] as Node).free()


func test_the_game_opens_it_for_a_duel() -> void:
	var g := _game()
	g._start_match(6)
	assert_true(g.ui.top() is CharacterSelect, "Duel vs CPU opens the character select")
	assert_eq(g.flow, g.Flow.SELECT, "")
	_tick(g, 1)
	assert_false(g.menu_stick.enabled, "it reads the sticks itself")
	g.free()


# ------------------------------------------------------------------ the game's menus

func test_the_title_menu_is_a_screen_and_back_points_at_exit() -> void:
	var g := _game()
	g._open_menu()
	assert_true(g.ui.top() is TitleScreen, "the title menu is up")
	var t: TitleScreen = g.ui.top()
	assert_eq((_focus() as Button).text, "Single player", "it starts on Single player")
	_press("ui_cancel")
	assert_eq((_focus() as Button).text, "Exit", "Back points at Exit (it doesn't quit)")
	assert_true(g.ui.top() == t, "and stays on the title")
	g.free()


func test_single_player_starts_the_chosen_fighter() -> void:
	var g := _game()
	g._open_menu()
	_press("ui_accept")  # Single player
	var scr: UiScreen = g.ui.top()
	assert_true(scr.title == "SINGLE PLAYER", "the Single player page")
	var versus: OptionRow = null
	for r in scr.rows():
		if r is OptionRow and (r as OptionRow).label == "Versus CPU":
			versus = r
	versus.grab_focus()
	_press("ui_right")
	_press("ui_right")
	_press("ui_accept")
	assert_eq(g.mode, int(g.MENU_ROWS[3]["modes"][2]), "Enter starts the fighter picked with Right:")
	assert_false(g.ui.is_open(), "and the menus close")
	g.free()


func test_back_from_a_page_returns_to_the_title_on_the_same_row() -> void:
	var g := _game()
	g._open_menu()
	_press("ui_down")
	_press("ui_down")  # Settings
	_press("ui_accept")
	assert_true(g.ui.top().title == "SETTINGS", "Settings opened")
	_press("ui_cancel")
	assert_true(g.ui.top() is TitleScreen, "back on the title")
	assert_eq((_focus() as Button).text, "Settings", "on Settings")
	g.free()


func test_settings_change_and_are_kept() -> void:
	var g := _game()
	g._open_menu("game")
	var before: int = g.level
	var row: OptionRow = g._setting_rows["level"]
	row.grab_focus()
	_press("ui_right")
	assert_eq(g.level, (before + 1) % 3, "Right changes the CPU level:")
	g._open_settings_page("audio")
	var vol: OptionRow = g._setting_rows["vol_Master"]
	vol.grab_focus()
	var v: float = g.audio.volume("Master")
	_press("ui_left")
	assert_near(g.audio.volume("Master"), maxf(0.0, v - 0.1), 0.001, "Left turns a volume down:")
	assert_near(vol.bar, g.audio.volume("Master"), 0.001, "and its bar follows:")
	g.free()


func test_the_online_screen_joins_what_was_typed() -> void:
	var lobby := OnlineLobby.new("sno", "", ["game.example.net/kev"])
	var st := _stack()
	st.push(lobby)
	var got := []
	lobby.join_pressed.connect(func(f, a, p, r): got.append([f, a, p, r]))
	lobby.field.grab_focus()
	lobby.field.text = "10.0.0.5:7800/Friends"
	lobby.field.text_changed.emit(lobby.field.text)
	lobby.field.text_submitted.emit(lobby.field.text)
	assert_eq(got.size(), 1, "Enter in the address box joins:")
	assert_eq(got[0], ["sno", "10.0.0.5", 7800, "Friends"], "with the fighter, address, port and room:")
	lobby.busy = true
	assert_eq((_focus() as Button).text, "Cancel", "connecting: only Cancel")
	assert_eq(lobby.field.focus_mode, Control.FOCUS_NONE, "the rest can't be reached")
	lobby.busy = false
	assert_eq(lobby._recent_rows.size(), 1, "a recent server is listed")
	st.free()


func test_an_empty_address_says_so() -> void:
	var lobby := OnlineLobby.new()
	var st := _stack()
	st.push(lobby)
	var joined := [false]
	lobby.join_pressed.connect(func(_f, _a, _p, _r): joined[0] = true)
	lobby._join.grab_focus()
	_press("ui_accept")
	assert_false(joined[0], "nothing to join")
	assert_true(lobby.status_bad and lobby.status.contains("address"), "it says what's missing: " + lobby.status)
	st.free()


func test_quick_match_and_rooms_play_on_the_server() -> void:
	var lobby := OnlineLobby.new("digby", "", [], "game.example.net")
	var st := _stack()
	st.push(lobby)
	var got := []
	lobby.server_join_pressed.connect(func(f, r): got.append([f, r]))
	assert_eq(_focus(), lobby._fighter_row, "the fighter row starts focused")
	_press("ui_down")
	assert_eq(_focus(), lobby._quick, "then Quick match")
	_press("ui_accept")
	assert_eq(got, [["digby", ""]], "Quick match: the server, no room:")
	_press("ui_down")
	_press("ui_accept")
	assert_eq(got.size(), 2, "Create room joins too")
	var code := String(got[1][1])
	assert_eq(code.length(), OnlineLobby.CODE_LENGTH, "with a short code: " + code)
	for ch in code:
		assert_true(OnlineLobby.CODE_CHARS.contains(ch), "made of easy-to-read characters: " + code)
	lobby.busy = true
	assert_true(lobby._room_label.text.contains(code), "the code is shown while waiting: " + lobby._room_label.text)
	assert_true(lobby._room_label.text.contains("Join room"), "with what the friend does")
	lobby.busy = false
	lobby.join_room("  kx-7p ")
	assert_eq(got[2], ["digby", "KX7P"], "a typed code is tidied:")
	assert_false(lobby.more_shown, "the address rows wait under More")
	assert_false(lobby.field.visible, "")
	lobby.toggle_more()
	assert_true(lobby.field.visible and not lobby._quick.visible, "More swaps the rows")
	assert_eq(_focus(), lobby._host, "and focuses the first of them")
	st.free()


func test_no_server_says_where_to_set_one() -> void:
	var lobby := OnlineLobby.new()
	var st := _stack()
	st.push(lobby)
	var got := [false]
	lobby.server_join_pressed.connect(func(_f, _r): got[0] = true)
	lobby.quick_match()
	assert_false(got[0], "nothing to join")
	assert_true(lobby.status_bad and lobby.status.contains("Settings"), "it says where: " + lobby.status)
	assert_true(lobby.more_shown, "and the address rows are out")
	assert_eq(OnlineLobby.clean_code(" a b-c!9 "), "ABC9", "codes keep letters and digits")
	st.free()


func test_the_online_server_setting_is_kept_and_has_a_default() -> void:
	var g := _game()
	assert_true(g.default_server() != "", "the game has its own server")
	assert_eq(g.online_server(), g.default_server(), "used when none is set")
	g._open_settings_page("game")
	var f: LineEdit = null
	for c in g.ui.top().rows():
		if c is LineEdit:
			f = c
	assert_true(f != null, "Settings > Game has the server box")
	f.text = "my.server.net:7800"
	f.text_changed.emit(f.text)
	assert_eq(g.online_server(), "my.server.net:7800", "typing sets it")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(String(cfg.get_value("online", "server", "")), "my.server.net:7800", "and it's saved")
	g.free()


func test_quick_match_finds_the_server_at_home_first() -> void:
	var g := _game()
	var port := 20000 + (Time.get_ticks_usec() % 20000)
	var beacon := ServerBeacon.new()
	assert_true(beacon.listen(port), beacon.error)
	g.finder_target = "127.0.0.1"
	g._online_server = "203.0.113.9:%d" % port  # a public address that won't answer
	g._start_match(20)  # Online
	assert_true(g.lobby != null, "the online screen is up")
	g.lobby.quick_match()
	assert_true(g.lobby.busy and g.lobby.status.contains("Looking"), "it looks nearby first: " + g.lobby.status)
	for i in 120:
		beacon.poll()
		_tick(g, 1)
		if g.netplay != null:
			break
		OS.delay_usec(3000)
	assert_true(g.netplay != null, "then joins")
	if g.netplay != null:
		assert_eq(g.netplay._address, "127.0.0.1:%d" % port, "the one it found, not the public address:")
	beacon.close()
	g._leave_online()
	g.free()


func test_no_answer_after_a_missed_home_lookup_says_what_to_check() -> void:
	var g := _game()
	g.finder_target = "127.0.0.1"  # nobody answers there
	g._online_server = "127.0.0.1:%d" % (20000 + (Time.get_ticks_usec() % 20000))  # nor here
	g._start_match(20)
	g.lobby.quick_match()
	for i in 900:
		_tick(g, 1)
		if not g.lobby.busy:
			break
		if g._finder != null:
			OS.delay_usec(2000)
	assert_false(g.lobby.busy, "it gave up")
	assert_true(g.lobby.status.contains("7778") and g.lobby.status.contains("7777"),
		"and says what to check at home and away: " + g.lobby.status)
	g._leave_online()
	g.free()


func test_an_older_server_nearby_is_still_found() -> void:
	var port := 20000 + (Time.get_ticks_usec() % 20000)
	var udp := PacketPeerUDP.new()
	assert_eq(udp.bind(ServerBeacon.discovery_port(port), "*"), OK, "a stand-in old server")
	var finder := LanFinder.new()
	finder.start(port, "127.0.0.1")
	for i in 200:
		if udp.get_available_packet_count() > 0:
			udp.get_packet()
			udp.set_dest_address(udp.get_packet_ip(), udp.get_packet_port())
			udp.put_packet(JSON.stringify({"t": ServerBeacon.ANSWER, "v": 2, "port": port}).to_utf8_buffer())
		if finder.poll():
			break
		OS.delay_usec(2000)
	assert_eq(finder.found.get("address", ""), "127.0.0.1",
		"found, so joining it can say the builds differ instead of 'no answer':")
	udp.close()


func test_match_over_offers_rematch_and_back_goes_to_the_menu() -> void:
	var g := _game()
	g._start_match(6)  # Duel vs CPU (pick screen)
	g._on_teams_chosen(g.DEFAULT_TEAMS.duplicate(true))
	g._apply_frame_rate()
	g.flow = g.Flow.MATCH_OVER
	g.flow_t = 0
	_tick(g, g.MATCH_OVER_MENU_AT + 1)
	assert_true(g.ui.is_open(), "the match-over choices come up")
	var labels: Array = []
	for r in g.ui.top().rows():
		labels.append((r as Button).text)
	assert_eq(labels, ["Rematch", "Change fighters", "Main menu"], "")
	_press("ui_cancel")
	assert_eq(g.flow, g.Flow.MENU, "Back goes to the title menu")
	g.free()


func test_every_controller_works_in_menus_and_fights() -> void:
	Controls.setup()
	for dev in [0, 1, 3]:
		var a := InputEventJoypadButton.new()
		a.device = dev
		a.button_index = JOY_BUTTON_A
		a.pressed = true
		var start := InputEventJoypadButton.new()
		start.device = dev
		start.button_index = JOY_BUTTON_START
		start.pressed = true
		assert_true(a.is_action_pressed("ui_accept"), "controller %d: A selects" % dev)
		assert_true(a.is_action_pressed("pad_light"), "controller %d: A attacks" % dev)
		assert_true(start.is_action_pressed("pause"), "controller %d: Start pauses" % dev)



# ------------------------------------------------------------------ remapping and new settings

func _key(k: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = true
	return ev


func test_remapping_swaps_and_the_prompts_follow() -> void:
	Controls.setup()
	Controls.reset()
	assert_eq(Controls.binding_text("kb_light", "classic"), "J", "")
	Controls.rebind("classic", "kb_light", _key(KEY_K))  # K was Heavy
	assert_eq(Controls.binding_text("kb_light", "classic"), "K", "Light is K now:")
	assert_eq(Controls.binding_text("kb_heavy", "classic"), "J", "and Heavy took J (a swap):")
	assert_true(_key(KEY_K).is_action_pressed("kb_light"), "K does a light attack")
	assert_false(_key(KEY_K).is_action_pressed("kb_heavy"), "and nothing else")
	assert_eq(PlayerInput.label_for("classic", "light"), "K", "the HUD label follows:")
	var pi := PlayerInput.new()
	pi.layout = "classic"
	assert_true(pi.help_text().contains("K light"), "and the controls strip: " + pi.help_text())
	Controls.reset()


func test_remapped_controls_are_saved_and_loaded() -> void:
	Controls.setup()
	Controls.reset()
	assert_true(Controls.overrides().is_empty(), "defaults save nothing")
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	Controls.rebind("gamepad", "pad_light", rb)
	var saved := Controls.overrides()
	assert_true(saved.has("pad_light") and saved.has("pad_dodge"), "the change and its swap are saved: %s" % str(saved))
	Controls.reset()
	assert_eq(Controls.binding_text("pad_light", "gamepad"), "A", "reset")
	Controls.apply_overrides(saved)
	assert_eq(Controls.binding_text("pad_light", "gamepad"), "RB", "loaded back:")
	assert_eq(Controls.binding_text("pad_dodge", "gamepad"), "A", "")
	var rb1 := rb.duplicate() as InputEventJoypadButton
	rb1.device = 2
	assert_true(rb1.is_action_pressed("pad_light"), "on any controller")
	Controls.reset()


func test_the_remap_screen_takes_the_next_key() -> void:
	Controls.setup()
	Controls.reset()
	var st := _stack()
	var r := RemapScreen.new("classic")
	var saved := [0]
	r.changed.connect(func(): saved[0] += 1)
	st.push(r)
	_press("ui_accept")  # Move up: listen
	assert_eq(r._waiting, "kb_up", "listening")
	_root().push_input(_key(KEY_ESCAPE))
	assert_eq(r._waiting, "", "Esc cancels")
	assert_true(st.is_open(), "without leaving the screen")
	_press("ui_accept")
	_root().push_input(_key(KEY_M))
	assert_eq(r._waiting, "kb_up", "M is the game's (mute): still listening")
	_root().push_input(_key(KEY_I))
	assert_eq(Controls.binding_text("kb_up", "classic"), "I", "the next key is the new binding:")
	assert_eq(Controls.binding_text("kb_skill_2", "classic"), "W", "and Skill 2 got W:")
	assert_true(_key(KEY_UP).is_action_pressed("kb_up"), "the Up arrow still moves up")
	assert_eq(saved[0], 1, "main is told to save")
	st.free()
	Controls.reset()


func test_screen_shake_and_rumble_settings() -> void:
	var g := _game()
	g._open_menu("game")
	var shake: OptionRow = g._setting_rows["shake"]
	shake.grab_focus()
	_press("ui_right")
	assert_near(g.shake_scale, 0.5, 0.001, "Reduced:")
	_press("ui_right")
	assert_near(g.shake_scale, 0.0, 0.001, "Off:")
	g.shake = 6.0
	g._start_match(2)
	_tick(g, 1)
	assert_eq(g.camera.offset, Vector2.ZERO, "no shake at all")
	var rumble: OptionRow = g._setting_rows.get("rumble")
	assert_true(rumble == null or g.rumble, "")
	g.free()



# ------------------------------------------------------------------ wide screens

func test_the_camera_keeps_the_arena_centred_on_a_wide_screen() -> void:
	var g := _game()
	# 21:9 at 1x: wider than the arena, so the arena sits in the middle whatever the focus.
	assert_eq(g._cam_axis(100.0, 320.0, 480.0), 240.0, "wider than the arena: centred")
	# 16:9: the camera follows but never shows past the arena's edges.
	assert_eq(g._cam_axis(100.0, 240.0, 480.0), 240.0, "exactly as wide: centred")
	assert_eq(g._cam_axis(100.0, 165.0, 480.0), 165.0, "zoomed in: clamped to the edge")
	assert_eq(g._cam_axis(300.0, 165.0, 480.0), 300.0, "and follows inside")
	g.free()


func test_the_hud_anchors_to_the_screen() -> void:
	var h := Hud.new()
	_root().add_child(h)
	h._layout()
	var vs: Vector2 = _root().get_visible_rect().size
	assert_near(h._sw, vs.x, 0.01, "the HUD knows the screen's width:")
	assert_lt(h._hr - h._hl, Hud.HUD_MAX_W + 0.01, "the health panels stay within the HUD width")
	assert_near((h._hl + h._hr) * 0.5, vs.x * 0.5, 0.01, "centred:")
	h.free()
