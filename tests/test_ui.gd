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


func test_cpus_thinking_while_the_frame_draws_choose_what_they_would_in_the_tick() -> void:
	# With a screen, main sets the CPUs going on the next tick's inputs at the end of a
	# tick (_think_ahead), so they think while the frame draws. The headless tests think
	# in the tick; turned on here, the match must play out input for input the same.
	var frames := []
	for early in [true, false]:
		var g := _game()
		g._cpus_early = early
		g._cpu_vs_cpu = true
		g._start_match(32)  # Team Deathmatch 3v3, every slot a CPU
		g._on_teams_chosen([["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]])
		_tick(g, 400)
		assert_gt(float(g.replay.frames.size()), 200.0, "the fight ran:")
		frames.append(var_to_str(g.replay.frames))
		g.free()
	assert_true(frames[0] == frames[1], "thinking ahead gives the same inputs, tick for tick")


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


## Presses the hub card called `title` on the top screen.
func _open_card(g: Node, title: String) -> void:
	var hub: UiScreen = g.ui.top()
	for r in hub.rows():
		if r is CardButton and (r as Button).text == title:
			(r as Control).grab_focus()
			_press("ui_accept")
			return
	fail("no card called " + title)


func test_single_player_is_a_hub_of_pages_that_cover_every_row() -> void:
	var g := _game()
	Progress.set_enabled(true)  # every row, the Weekly's too (tests/test_weekly.gd: Off hides it)
	g._open_menu()
	_press("ui_accept")  # Single player
	var hub: UiScreen = g.ui.top()
	var cards: Array = hub.rows().filter(func(r): return r is CardButton)
	assert_eq(cards.size(), g.MENU_GROUPS.size(), "a card per group:")
	var seen := {}
	for gi in g.MENU_GROUPS.size():
		var group: Dictionary = g.MENU_GROUPS[gi]
		_open_card(g, String(group["title"]))
		var page: UiScreen = g.ui.top()
		assert_eq(page.title, String(group["title"]).to_upper(), "the page's title:")
		assert_eq(page.crumbs, ["SINGLE PLAYER"], "with its trail:")
		var labels: Array = []
		for r in page.rows():
			if r is OptionRow:
				labels.append((r as OptionRow).label)
			elif r is Button and (r as Button).text != "Back":
				labels.append((r as Button).text)
		for row in g.MENU_ROWS:
			if String(row.get("group", "")) == String(group["id"]):
				assert_true(String(row["label"]) in labels, "%s lists %s" % [group["title"], row["label"]])
				seen[row["label"]] = true
		assert_true(labels.size() <= 6, "%s fits a page (%d rows)" % [group["title"], labels.size()])
		_press("ui_cancel")
		assert_eq(g.ui.top(), hub, "back to the hub")
		assert_eq((_focus() as Button).text, String(group["title"]), "on the same card:")
	assert_eq(seen.size(), g.MENU_ROWS.size(), "every mode is reachable from some page:")
	Progress.set_enabled(false)
	g.free()


func test_single_player_starts_the_chosen_fighter() -> void:
	var g := _game()
	g._open_menu()
	_press("ui_accept")  # Single player
	var hub: UiScreen = g.ui.top()
	assert_true(hub.title == "SINGLE PLAYER", "the Single player hub")
	_open_card(g, "Fight the CPU")
	var scr: UiScreen = g.ui.top()
	assert_eq(scr.title, "FIGHT THE CPU", "its page:")
	var versus: OptionRow = null
	for r in scr.rows():
		if r is OptionRow and (r as OptionRow).label == "Versus CPU":
			versus = r
	assert_true(versus != null, "the Versus CPU row is on it")
	versus.grab_focus()
	_press("ui_right")
	_press("ui_right")
	_press("ui_accept")
	var row: Dictionary = g.MENU_ROWS.filter(func(r): return r["label"] == "Versus CPU")[0]
	assert_eq(g.mode, int(row["modes"][2]), "Enter starts the fighter picked with Right:")
	assert_false(g.ui.is_open(), "and the menus close")
	g.free()


func test_team_battle_row_opens_the_pick_then_fights_with_cpu_teammates() -> void:
	var g := _game()
	g._open_menu()
	_press("ui_accept")  # Single player
	_open_card(g, "Team battles")
	var scr: UiScreen = g.ui.top()
	var team_row: OptionRow = null
	for r in scr.rows():
		if r is OptionRow and (r as OptionRow).label == "Team battle vs CPU":
			team_row = r
	assert_true(team_row != null, "a Team battle row")
	team_row.grab_focus()
	_press("ui_right")  # 3 v 3
	_press("ui_accept")
	assert_eq(g.mode, 30, "3 v 3 chosen:")
	assert_true(g.ui.top() is CharacterSelect, "the pick screen comes first")
	g._on_teams_chosen([["cairn"], ["culvert"]])  # short picks are topped up to three
	assert_true(g.team_battle != null, "a team battle runs")
	assert_eq(g.sim.creatures.size(), 6, "six fighters on the field:")
	assert_eq(g.sides[0], g.Side.PLAYER, "you play the first slot:")
	var cpu_count := 0
	for c in g.cpus:
		if c != null:
			cpu_count += 1
	assert_eq(cpu_count, 5, "CPUs play the other five:")
	assert_eq(g.hud.tags.size(), 6, "a HUD tag per slot:")
	assert_false(g.hud.help_text.contains(" tag "), "no Tag in the help (nobody to tag):")
	_tick(g, 200)
	assert_eq(g.team_battle.phase, TeamSim.Phase.FIGHT, "past the intro:")
	g.free()


func test_back_from_a_page_returns_to_the_title_on_the_same_row() -> void:
	var g := _game()
	g._open_menu()
	((g.ui.top() as TitleScreen)._rows_by_name["settings"] as Control).grab_focus()  # (by name: the Profile row comes and goes)
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
	var kept: float = g.audio.volume("Master")
	g.free()
	# The next launch reads them back (the file already has a player id by now).
	var again: Node = load("res://scenes/main.tscn").instantiate()
	again.settings_path = TEST_SETTINGS
	_root().add_child(again)
	assert_eq(again.level, (before + 1) % 3, "the CPU level is kept:")
	assert_near(again.audio.volume("Master"), kept, 0.001, "and so is the volume:")
	again.free()


func test_the_music_is_the_new_track_and_it_loops() -> void:
	var g := _game()
	for name in ["menu", "fight"]:
		var stream: AudioStream = g.audio._music_tracks.get(name)
		assert_true(stream is AudioStreamOggVorbis, name + " plays the Creature Arena Battler track")
		if stream is AudioStreamOggVorbis:
			assert_true((stream as AudioStreamOggVorbis).loop, name + " loops seamlessly")
	g.free()


## Picks `id` on the online screen's character tiles, as the tiles would.
func _pick_online(lobby: OnlineLobby, id: String) -> void:
	assert_true(lobby.picker != null, "the character tiles are up")
	if lobby.picker != null:
		lobby.picker.chosen.emit([[id], []])


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
	assert_eq(got.size(), 0, "Enter in the address box opens the tiles first:")
	_pick_online(lobby, "sno")
	assert_eq(got.size(), 1, "then joins:")
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


func test_online_opens_on_quick_match_rooms_and_more() -> void:
	var lobby := OnlineLobby.new("digby", "", [], "game.example.net")
	var st := _stack()
	st.push(lobby)
	assert_eq(lobby.page, OnlineLobby.Page.MAIN, "the first page")
	assert_eq(_focus(), lobby._quick_page, "Quick match starts focused")
	assert_false(lobby._quick.visible or lobby._create.visible or lobby.field.visible,
		"the sizes, rooms and addresses wait on their own pages")
	_press("ui_accept")
	assert_eq(lobby.page, OnlineLobby.Page.QUICK, "Quick match opens its page")
	assert_eq(_focus(), lobby._quick, "on 1 v 1")
	assert_true(lobby._quick2.visible and lobby._quick3.visible and lobby._quick4.visible, "with 2 v 2, 3 v 3 and 4 v 4")
	assert_false(lobby._quick_page.visible, "")
	_press("ui_cancel")
	assert_eq(lobby.page, OnlineLobby.Page.MAIN, "Back goes up a page")
	assert_eq(_focus(), lobby._quick_page, "to where it came from")
	var left := [false]
	lobby.cancelled.connect(func(): left[0] = true)
	_press("ui_cancel")
	assert_true(left[0], "Back on the first page leaves")
	st.free()


func test_quick_match_picks_a_fighter_on_the_tiles_before_searching() -> void:
	var lobby := OnlineLobby.new("digby", "", [], "game.example.net")
	var st := _stack()
	st.push(lobby)
	var got := []
	lobby.server_join_pressed.connect(func(f, r, n): got.append([f, r, n]))
	lobby.open_page(OnlineLobby.Page.QUICK)
	lobby._quick2.grab_focus()
	_press("ui_accept")
	assert_true(st.top() is CharacterSelect, "2 v 2 opens the character tiles")
	var pick := st.top() as CharacterSelect
	assert_true(pick.solo and pick.team_size == 1, "for one fighter: yours")
	assert_eq(String(pick.roster[pick.cursor[0]]), "digby", "starting on last time's")
	assert_eq(got.size(), 0, "no search yet")
	_press("ui_cancel")
	assert_eq(st.top(), lobby, "Back on the tiles comes back here")
	assert_eq(got.size(), 0, "without searching")
	lobby.quick_match(2)
	pick = st.top() as CharacterSelect
	pick.cursor[0] = pick.roster.find("sno")
	pick.pick(0)
	assert_true(pick.is_done(), "one pick is all it takes")
	pick.chosen.emit(pick.teams.duplicate(true))  # what the tiles send after their beat
	assert_eq(st.top(), lobby, "the tiles close")
	assert_eq(got, [["sno", "", 2]], "and the search starts: that fighter, no room, 2 v 2:")
	assert_eq(lobby.fighter, "sno", "kept for next time:")
	lobby.busy = true
	assert_true(lobby._who_label.text.contains("Sno") and lobby._who_label.text.contains("2 v 2"),
		"searching shows who and what: " + lobby._who_label.text)
	assert_eq((_focus() as Button).text, "Cancel", "only Cancel")
	var stopped := [false]
	lobby.search_cancelled.connect(func(): stopped[0] = true)
	_press("ui_cancel")
	assert_true(stopped[0], "Cancel stops the search (and stays here)")
	st.free()


func test_rooms_pick_then_make_or_join_a_code() -> void:
	var lobby := OnlineLobby.new("digby", "", [], "game.example.net")
	var st := _stack()
	st.push(lobby)
	var got := []
	lobby.server_join_pressed.connect(func(f, r, n): got.append([f, r, n]))
	lobby._rooms_page.grab_focus()
	_press("ui_accept")
	assert_eq(lobby.page, OnlineLobby.Page.ROOMS, "Rooms opens its page")
	assert_eq(_focus(), lobby._size_row, "on the room size")
	_press("ui_right")  # Duel 3v3 tag
	_press("ui_right")  # 2 v 2
	_press("ui_down")  # the team rules
	_press("ui_down")  # Create room
	_press("ui_accept")
	_pick_online(lobby, "pete")
	assert_eq(got.size(), 1, "Create room searches after the pick")
	assert_eq(int(got[0][2]), 2, "with the room size:")
	var code := String(got[0][1])
	assert_eq(code.length(), OnlineLobby.CODE_LENGTH, "with a short code: " + code)
	for ch in code:
		assert_true(OnlineLobby.CODE_CHARS.contains(ch), "made of easy-to-read characters: " + code)
	lobby.busy = true
	assert_true(lobby.code_button.visible and lobby.code_button.text.contains(code),
		"the code is shown while waiting (press to copy): " + lobby.code_button.text)
	assert_true(lobby._room_label.text.contains("Join room"), "with what the friend does")
	assert_true(lobby._room_label.text.contains("2 v 2"), "and the size")
	lobby.busy = false
	assert_eq(lobby.page, OnlineLobby.Page.ROOMS, "done searching: back on the same page")
	lobby.join_room("  kx-7p ")
	_pick_online(lobby, "pete")
	assert_eq(got[1], ["pete", "KX7P", 0], "a typed code is tidied, and takes the room's size:")
	lobby.join_room("   ")
	assert_true(lobby.picker == null, "no code: no tiles")
	assert_true(lobby.status_bad and lobby.status.contains("code"), "it asks for the code: " + lobby.status)
	lobby.toggle_more()
	assert_true(lobby.field.visible and not lobby._create.visible, "More has the address rows")
	assert_eq(_focus(), lobby._host, "and focuses the first of them")
	st.free()


func test_no_server_says_where_to_set_one() -> void:
	var lobby := OnlineLobby.new()
	var st := _stack()
	st.push(lobby)
	var got := [false]
	lobby.server_join_pressed.connect(func(_f, _r, _n): got[0] = true)
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
	_pick_online(g.lobby, "cairn")
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


## The game searching on an in-memory server, with another (auto-accepting) player
## there. Returns [server, other player].
func _search_with_another(g: Node, mine: String, theirs: String) -> Array:
	g._start_match(20)  # Online
	var server := RelayServer.new()
	var la := LoopLink.pair()
	var lb := LoopLink.pair()
	server.add_client(la[0])
	server.add_client(lb[0])
	var me := Netplay.new()
	me.auto_ready = false  # as the menus set it: the player is asked
	me.join("server", 0, [mine], la[1])
	var other := Netplay.new()
	other.join("server", 0, [theirs], lb[1])
	g.lobby.use_fighter(mine)
	g.lobby.searching_for = "Quick match  1 v 1"
	g.netplay = me
	g.lobby.busy = true
	return [server, other]


func _step_online(g: Node, s: Array, ticks: int, cond: Callable) -> bool:
	for i in ticks:
		(s[1] as Netplay).tick(0)
		(s[0] as RelayServer).tick()
		_tick(g, 1)
		if cond.call():
			return true
	return false


func test_match_found_asks_to_accept_then_the_match_starts() -> void:
	var g := _game()
	var s := _search_with_another(g, "cairn", "sno")
	assert_true(_step_online(g, s, 200, func(): return g._ready_screen != null), "Match found opens")
	assert_true(g.ui.top() is ReadyCheck, "over the online screen")
	assert_eq((_focus() as Button).text, "Accept", "with Accept focused")
	assert_true((g.ui.top() as ReadyCheck).subtitle.contains("1 v 1"), "it says what was found")
	assert_eq((s[0] as RelayServer).games.size(), 0, "the match waits for this player")
	_press("ui_accept")
	assert_true(_step_online(g, s, 200, func(): return g.online != null), "accepted: the match starts")
	assert_eq(g.flow, g.Flow.FIGHT, "straight into the fight")
	assert_true(g._ready_screen == null and not g.ui.is_open(), "and the menus are gone")
	g._leave_online()
	g.free()


func test_declining_a_match_found_comes_back_to_the_online_screen() -> void:
	var g := _game()
	var s := _search_with_another(g, "cairn", "sno")
	_step_online(g, s, 200, func(): return g._ready_screen != null)
	_press("ui_cancel")  # Back declines
	assert_true(g._ready_screen == null, "Match found closes")
	assert_eq(g.ui.top(), g.lobby, "back on the online screen")
	assert_false(g.lobby.busy, "not searching any more")
	assert_true(g.lobby.status.contains("declined") and not g.lobby.status_bad,
		"it says so, calmly: " + g.lobby.status)
	assert_true(g.netplay == null, "and the session is closed")
	g._leave_online()
	g.free()


func test_no_answer_after_a_missed_home_lookup_says_what_to_check() -> void:
	var g := _game()
	g.finder_target = "127.0.0.1"  # nobody answers there
	g._online_server = "127.0.0.1:%d" % (20000 + (Time.get_ticks_usec() % 20000))  # nor here
	g._start_match(20)
	g.lobby.quick_match()
	_pick_online(g.lobby, "cairn")
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


## Only a server of this very build is taken from the LAN: an older one, or anyone else
## answering on a shared network, is ignored and the public name is used instead.
func test_a_nearby_answer_from_another_build_is_ignored() -> void:
	var bad := [
		{"t": ServerBeacon.ANSWER, "v": 2, "port": 0},  # an old server (no data hash)
		{"t": ServerBeacon.ANSWER, "v": Netplay.NET_VERSION, "port": 0, "data": "not-this-build"},
		{"t": ServerBeacon.ANSWER, "v": Netplay.NET_VERSION + 1, "port": 0, "data": Netplay.data_hash()},
		{"t": ServerBeacon.ANSWER, "v": [Netplay.NET_VERSION], "port": 0, "data": [1]},
	]
	for answer in bad:
		var port := 20000 + (Time.get_ticks_usec() % 20000)
		answer["port"] = port
		var udp := PacketPeerUDP.new()
		assert_eq(udp.bind(ServerBeacon.discovery_port(port), "*"), OK, "a stand-in server")
		var finder := LanFinder.new()
		finder.start(port, "127.0.0.1")
		var t0 := Time.get_ticks_msec()
		while not finder.poll() and Time.get_ticks_msec() - t0 < 3000:
			if udp.get_available_packet_count() > 0:
				udp.get_packet()
				udp.set_dest_address(udp.get_packet_ip(), udp.get_packet_port())
				udp.put_packet(JSON.stringify(answer).to_utf8_buffer())
			OS.delay_usec(2000)
		assert_true(finder.done and finder.found.is_empty(), "ignored %s" % JSON.stringify(answer))
		udp.close()
	# The same stand-in answering as this build is taken.
	var port := 20000 + (Time.get_ticks_usec() % 20000)
	var udp := PacketPeerUDP.new()
	assert_eq(udp.bind(ServerBeacon.discovery_port(port), "*"), OK, "a stand-in server")
	var finder := LanFinder.new()
	finder.start(port, "127.0.0.1")
	for i in 200:
		if udp.get_available_packet_count() > 0:
			udp.get_packet()
			udp.set_dest_address(udp.get_packet_ip(), udp.get_packet_port())
			udp.put_packet(JSON.stringify({"t": ServerBeacon.ANSWER, "v": Netplay.NET_VERSION, "port": port,
				"data": Netplay.data_hash()}).to_utf8_buffer())
		if finder.poll():
			break
		OS.delay_usec(2000)
	assert_eq(finder.found.get("address", ""), "127.0.0.1", "this build's answer is found:")
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


func test_the_remap_grid_walks_in_columns_and_crosses_with_left_right() -> void:
	Controls.setup()
	var st := _stack()
	st.push(RemapScreen.new("classic"))
	assert_eq((_focus() as Button).text, "Move up", "first binding focused")
	_press("ui_right")
	assert_eq((_focus() as Button).text, "Move down", "Right crosses to the second column")
	_press("ui_down")
	assert_eq((_focus() as Button).text, "Move right", "Down walks that column")
	_press("ui_left")
	assert_eq((_focus() as Button).text, "Move left", "Left comes back")
	_press("ui_up")
	assert_eq((_focus() as Button).text, "Move up", "")
	_press("ui_up")
	assert_eq((_focus() as Button).text, "Back", "Up from the top wraps to the last button")
	_press("ui_down")
	assert_eq((_focus() as Button).text, "Move up", "and Down from it to the first binding")
	for i in 8:  # fifteen bindings: eight in the left column (Talk last), seven on the right
		_press("ui_down")
	assert_eq((_focus() as Button).text, "Reset to defaults", "the bottom of a column leads to the buttons")
	st.free()


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
	# Near an edge the shot may run into the stands, as far as the margin allowed.
	assert_eq(g._cam_axis(100.0, 165.0, 480.0, 64.0, 64.0), 101.0, "into the side stand, no further")
	assert_eq(g._cam_axis(470.0, 165.0, 480.0, 64.0, 64.0), 379.0, "and the other side")
	assert_eq(g._cam_axis(100.0, 300.0, 480.0, 64.0, 64.0), 236.0, "a little wider than the arena: follows a little")
	assert_eq(g._cam_axis(100.0, 320.0, 480.0, 64.0, 64.0), 240.0, "wider than arena and margins: centred")
	g.free()


func test_the_crowd_stands_up_near_a_hit_and_redraws_only_its_block() -> void:
	var crowd := CrowdView.new()
	crowd.set_size(SimDefs.arena_size())
	var size := SimDefs.arena_size()
	# A hit by the left wall stands up fans in the left stand, nowhere else.
	crowd.react(Vector2(30, size.y * 0.5), 6)
	var up := {}
	for b in crowd._blocks:
		for i in b.pos.size():
			if b.up_until[i] > 0:
				up[b.stand] = int(up.get(b.stand, 0)) + 1
	assert_eq(up, {CrowdView.Stand.LEFT: 6}, "six fans in the left stand")
	var touched := crowd._blocks.filter(func(b): return b.version > 0).size()
	assert_true(touched >= 1 and touched <= 2, "only the block or two they sit in changes")
	# Many hits in one tick stand up at most REACT_CAP fans.
	for k in 10:
		crowd.react(Vector2(size.x * 0.5, 70), 6)
	var top := 0
	for b in crowd._blocks:
		if b.stand == CrowdView.Stand.TOP:
			for i in b.pos.size():
				top += int(b.up_until[i] > 0)
	assert_eq(top, CrowdView.REACT_CAP - 6, "capped per tick")
	# They sit down again after REACT_TICKS.
	for t in CrowdView.REACT_TICKS + 1:
		crowd.advance()
	assert_true(crowd._active.is_empty(), "everyone sat down")
	# The team looks: red armour left, blue right; a Brawl's are mixed.
	var looks := {}
	for b in crowd._blocks:
		looks[b.stand] = b.look[0]
	assert_eq(looks[CrowdView.Stand.LEFT], CrowdView.Look.RED, "")
	assert_eq(looks[CrowdView.Stand.RIGHT], CrowdView.Look.BLUE, "")
	assert_eq(looks[CrowdView.Stand.FRONT], CrowdView.Look.BACK, "the front rows from behind")
	crowd.set_size(size, false)
	for b in crowd._blocks:
		if b.stand == CrowdView.Stand.LEFT:
			assert_eq(b.look[0], CrowdView.Look.MIXED, "no sides: mixed")
			break
	assert_eq(CrowdView.sheet().get_height(), CrowdView.CELL_H * CrowdView.PPU * CrowdView.SHEET_ROWS, "every variant baked in one sheet (tools/cut_crowd.py)")
	crowd.free()


func test_the_fight_camera_keeps_both_fighters_in_shot() -> void:
	var g := _game()
	g._start_match(2)  # CPU vs CPU
	_tick(g, 2)
	var view: Vector2 = g.get_viewport().get_visible_rect().size
	var fr := SimDefs.floor_rect()
	var corners := [[fr.position + Vector2(20, 30), fr.end - Vector2(20, 20)],
		[Vector2(fr.position.x + 20, fr.end.y - 20), Vector2(fr.end.x - 20, fr.position.y + 30)]]
	for pair in corners:
		g.sim.creatures[0].pos = pair[0]
		g.sim.creatures[1].pos = pair[1]
		for i in 120:
			g._update_camera()
		var cam: Camera2D = g.camera
		var shown := Rect2(cam.position - view * 0.5 / cam.zoom.x, view / cam.zoom.x).grow(0.5)
		for c in g.sim.creatures:
			assert_true(shown.has_point(c.pos), "feet at %s in shot %s" % [c.pos, shown])
		assert_lt(cam.zoom.x, 1.0, "pulled back to fit them:")
	# Close together: the usual 1x.
	g.sim.creatures[0].pos = fr.get_center()
	g.sim.creatures[1].pos = fr.get_center() + Vector2(40, 0)
	for i in 300:
		g._update_camera()
	assert_near(g.camera.zoom.x, 1.0, 0.01, "close together, the camera sits at 1x:")
	g.free()


## Two fighters close together in the middle of the stadium, the camera settled on them.
func _close_pair(g: Node) -> void:
	var fr := SimDefs.floor_rect()
	g.sim.creatures[0].pos = fr.get_center()
	g.sim.creatures[1].pos = fr.get_center() + Vector2(40, 0)
	for i in 300:
		g._update_camera()


func test_the_camera_leads_an_attack_and_never_leads_anyone_out_of_shot() -> void:
	var g := _game()
	g._start_match(2)  # CPU vs CPU
	_tick(g, 2)
	_close_pair(g)
	assert_near(g._cam_lead.length(), 0.0, 0.5, "standing still, no look-ahead:")
	# Fighter 0 swings to the right: the camera drifts a little that way.
	var a: CreatureSim = g.sim.creatures[0]
	a.state = CreatureSim.State.ATTACK
	a.facing = Vector2.RIGHT
	for i in 120:
		g._update_camera()
	assert_gt(g._cam_lead.x, 5.0, "leads along the attack:")
	assert_lt(g._cam_lead.length(), g.LEAD_MAX + 0.01, "a little, no more:")
	a.state = CreatureSim.State.IDLE
	# However big a lead is asked for, every fighter stays in shot, clear of the edge.
	var view: Vector2 = g.get_viewport().get_visible_rect().size
	var fr := SimDefs.floor_rect()
	var spots := [[fr.position + Vector2(20, 30), fr.end - Vector2(20, 20)], [fr.get_center(), fr.get_center() + Vector2(40, 0)]]
	for pair in spots:
		g.sim.creatures[0].pos = pair[0]
		g.sim.creatures[1].pos = pair[1]
		for push in [Vector2(400, 0), Vector2(-400, 0), Vector2(0, 400), Vector2(0, -400)]:
			for i in 60:
				g._cam_lead = push
				g._update_camera()
			var cam: Camera2D = g.camera
			var shown := Rect2(cam.position - view * 0.5 / cam.zoom.x, view / cam.zoom.x).grow(0.5)
			for c in g.sim.creatures:
				assert_true(shown.has_point(c.pos), "lead %s: feet at %s in shot %s" % [push, c.pos, shown])
	# The rule on its own: a lead is only ever cut back, toward nothing.
	var tight := Rect2(100, 100, 40, 30)
	assert_eq(g._lead_room(Vector2(5, 0), tight.get_center(), tight, Vector2(240, 135)), Vector2(5, 0), "room to spare: kept")
	var cut: Vector2 = g._lead_room(Vector2(500, 0), tight.get_center(), tight, Vector2(80, 60))
	assert_near(cut.x, 80.0 - 20.0 - g.LEAD_KEEP.x, 0.01, "cut to the room there is:")
	assert_eq(g._lead_room(Vector2(9, 9), tight.get_center(), tight, Vector2(10, 10)), Vector2.ZERO, "no room: none")
	g.free()


func test_the_camera_pushes_in_on_a_trade_and_eases_out_after() -> void:
	var g := _game()
	g._start_match(2)
	_tick(g, 2)
	_close_pair(g)
	assert_near(g.camera.zoom.x, 1.0, 0.01, "before any hit:")
	# One poke doesn't move the camera.
	g._note_exchange()
	for i in 120:
		g._update_camera()
	assert_near(g.camera.zoom.x, 1.0, 0.01, "a single hit, no push:")
	# A trade (hits every half second) pushes in, a little.
	for i in 300:
		if i % 30 == 0:
			g._note_exchange()
		g._update_camera()
	assert_gt(g.camera.zoom.x, 1.06, "pushed in on the trade:")
	assert_lt(g.camera.zoom.x, 1.0 + g.EXCHANGE_PUSH + 0.01, "only a little:")
	# Smoothly: no tick jumps by much.
	var before: float = g.camera.zoom.x
	var worst := 0.0
	for i in 600:
		g._update_camera()
		worst = maxf(worst, absf(g.camera.zoom.x - before))
		before = g.camera.zoom.x
	assert_near(g.camera.zoom.x, 1.0, 0.01, "eased back out after the trade:")
	assert_lt(worst, 0.004, "no pumping:")
	# Apart, a trade doesn't push in (nobody is up close).
	g.sim.creatures[1].pos = g.sim.creatures[0].pos + Vector2(220, 0)
	for i in 300:
		if i % 30 == 0:
			g._note_exchange()
		g._update_camera()
	assert_near(g._cam_push, 0.0, 0.01, "far apart, no push:")
	g.free()


# ------------------------------------------------------------------ camera behaviour

## The pair from _close_pair standing still: nobody pressing anything, both idle.
func _still_pair(g: Node) -> void:
	for c in g.sim.creatures:
		c.state = CreatureSim.State.IDLE
		c.prev_buttons = 0
		c.facing = Vector2.RIGHT
	_close_pair(g)


func test_the_aim_lead_leans_toward_the_aim_and_returns_slowly() -> void:
	var g := _game()
	g._start_match(2)  # CPU vs CPU: nobody here, so the HUD's fighter (0) is the one followed
	_tick(g, 2)
	g._cam_cli = {"cam_settle": 0, "cam_clash": 0}
	_still_pair(g)
	var a: CreatureSim = g.sim.creatures[0]
	var full: float = g.AIM_LEAD[g.CAM_DEFAULT]
	assert_gt(g._cam_aim.x, full - 0.5, "facing right: leans right:")
	# An exact aim (twin-stick, mouse) down the screen: it turns that way, y scaled down.
	a.prev_buttons = SimDefs.aim_bits(Vector2.DOWN)
	for i in 200:
		g._update_camera()
	assert_near(g._cam_aim.x, 0.0, 0.5, "aiming down, no sideways lead:")
	assert_near(g._cam_aim.y, full * g.AIM_LEAD_Y, 0.5, "")
	# A wobble inside the dead zone (one step of 64, about 6 degrees) doesn't move it at all.
	var held: Vector2 = g._cam_aim_dir
	a.prev_buttons = SimDefs.IN_AIM | (17 << SimDefs.AIM_SHIFT)
	for i in 30:
		g._update_camera()
	assert_eq(g._cam_aim_dir, held, "a small wobble: the aim held")
	assert_near(g._cam_aim.x, 0.0, 0.5, "and the lead with it:")
	# Knocked down into a pit (no aim): the lead goes back, slowly.
	a.state = CreatureSim.State.FALLING
	var before: Vector2 = g._cam_aim
	var worst := 0.0
	for i in 20:
		g._update_camera()
		worst = maxf(worst, (g._cam_aim - before).length())
		before = g._cam_aim
	assert_gt(g._cam_aim.length(), full * g.AIM_LEAD_Y * 0.4, "still on its way back after a third of a second:")
	assert_lt(worst, full * g.AIM_EASE_OUT + 0.01, "no tick moves it more than the slow return:")
	for i in 400:
		g._update_camera()
	assert_eq(g._cam_aim, Vector2.ZERO, "back to nothing")
	# Off: no lead at all.
	a.state = CreatureSim.State.IDLE
	g._cam_cli["cam_lead"] = 0
	for i in 200:
		g._update_camera()
	assert_eq(g._cam_aim, Vector2.ZERO, "off: none")
	g.free()


func test_the_aim_lead_follows_the_local_player_and_keeps_everyone_in_shot() -> void:
	var g := _game()
	g._start_match(2)
	_tick(g, 2)
	g._cam_cli = {"cam_settle": 0, "cam_lead": 3}
	g.sides[1] = g.Side.PLAYER  # someone plays fighter 1 here: its aim leads, not the HUD's
	_still_pair(g)
	g.sim.creatures[1].prev_buttons = SimDefs.aim_bits(Vector2.LEFT)
	for i in 200:
		g._update_camera()
	assert_lt(g._cam_aim.x, -10.0, "leans the way the player aims:")
	assert_eq(g._aim_fighters(-1), [1], "")
	# Far apart and pulled back, a big lead never pushes anyone out of the shot.
	var view: Vector2 = g.get_viewport().get_visible_rect().size
	var fr := SimDefs.floor_rect()
	g.sim.creatures[0].pos = fr.position + Vector2(20, 30)
	g.sim.creatures[1].pos = fr.end - Vector2(20, 20)
	g._cam_prev = []
	for i in 200:
		g._update_camera()
	var cam: Camera2D = g.camera
	var shown := Rect2(cam.position - view * 0.5 / cam.zoom.x, view / cam.zoom.x).grow(0.5)
	for c in g.sim.creatures:
		assert_true(shown.has_point(c.pos), "feet at %s in shot %s" % [c.pos, shown])
	g.free()


func test_a_clash_pushes_in_on_the_event_and_lets_go() -> void:
	var g := _game()
	g._start_match(2)
	_tick(g, 2)
	g._cam_cli = {"cam_settle": 0, "cam_lead": 0}
	_still_pair(g)
	var base: float = g.camera.zoom.x
	assert_near(base, 1.0, 0.01, "settled at 1x:")
	var b: CreatureSim = g.sim.creatures[1]
	g._react({"type": "guard_break", "pos": b.pos, "power": 1.0, "who": 1, "tick": g.sim.tick})
	var zs := []
	for i in 80:
		g._update_camera()
		zs.append(g.camera.zoom.x)
	var peak: float = zs.max()
	assert_gt(zs[5], base + 0.05, "in within a few ticks:")
	assert_lt(peak, base * (1.0 + g.CLASH_PUSH[g.CAM_DEFAULT]) + 0.001, "by the clash's push, no more:")
	assert_gt(peak, base * (1.0 + g.CLASH_PUSH[g.CAM_DEFAULT]) - 0.01, "")
	assert_near(zs[79], base, 0.002, "and let go after:")
	assert_eq(g._cam_zclash, 1.0, "")
	# The hit that knocks someone out: the KO push-in owns it, no clash.
	g._ko_cam_t = 0
	g._note_clash(b.pos, 1.0)
	g._update_camera()
	assert_eq(g._clash, 0.0, "no clash on a knockout")
	g._ko_cam_t = -1
	# Not on top of a trade's push-in: the larger of the two, never the sum.
	assert_eq(g.clash_zoom(1.0, 0.07, 0.12, 2.0), 1.0, "the exchange already pushes in further: nothing more")
	assert_near(g.clash_zoom(1.0, 0.07, 0.03, 2.0), 1.07 / 1.03, 0.0001, "only the difference")
	assert_eq(g.clash_zoom(1.0, 0.07, 0.0, 1.02), 1.02, "never past the room round the fighters")
	assert_eq(g.clash_zoom(0.0, 0.07, 0.0, 2.0), 1.0, "")
	# Off: the event does nothing.
	g._cam_cli["cam_clash"] = 0
	g._react({"type": "guard_break", "pos": b.pos, "power": 1.0, "who": 1, "tick": g.sim.tick})
	for i in 6:
		g._update_camera()
	assert_eq(g._clash, 0.0, "off: none")
	g.free()


func test_a_quiet_camera_settles_and_wakes_on_any_input() -> void:
	var g := _game()
	g._start_match(2)
	_tick(g, 2)
	g._cam_cli = {"cam_lead": 0, "cam_clash": 0}
	_still_pair(g)
	assert_gt(g._cam_idle, g.SETTLE_AFTER, "a second with nothing happening:")
	# Settled, a small shift of the action (inside the dead zone) holds the picture still.
	var start: Vector2 = g._cam_follow
	for c in g.sim.creatures:
		c.pos += Vector2(8, 0)
	g._cam_prev = []  # (moved without walking, so nothing "happened")
	for i in 120:
		g._update_camera()
	assert_near(g._cam_follow.x, start.x, 0.01, "held through the dead zone:")
	# Further than the dead zone: it drifts there, slower than usual.
	for c in g.sim.creatures:
		c.pos += Vector2(20, 0)
	g._cam_prev = []
	g._update_camera()
	var step: float = g._cam_follow.x - start.x
	assert_gt(step, 0.0, "past the dead zone: it follows")
	assert_lt(step, 28.0 * 0.1 * 0.5, "slowly:")
	for i in 300:
		g._update_camera()
	assert_near(g._cam_follow.x, start.x + 28.0, 0.5, "and gets there")
	# Any press: the normal rules at once.
	g.sim.creatures[0].prev_buttons = SimDefs.IN_LIGHT
	g._update_camera()
	assert_eq(g._cam_idle, 0, "a press wakes it")
	g.sim.creatures[0].prev_buttons = 0
	for c in g.sim.creatures:
		c.pos += Vector2(8, 0)
	g._cam_prev = []
	var was: float = g._cam_follow.x
	g._update_camera()
	assert_gt(g._cam_follow.x - was, 8.0 * 0.1 - 0.01, "awake, it follows at the usual pace:")
	# Off: never settles.
	g._cam_cli["cam_settle"] = 0
	for i in 120:
		g._update_camera()
	assert_eq(g.cam_level("cam_settle"), 0, "")
	g.free()


func test_the_camera_sits_on_whole_screen_pixels() -> void:
	var g := _game()
	g._start_match(2)
	_tick(g, 60)
	var view: Vector2 = g.get_viewport().get_visible_rect().size
	for i in 30:
		_tick(g, 1)
		var px: float = g.camera.zoom.x * maxf(1.0, float(g.get_window().size.x) / view.x)
		var p: Vector2 = g.camera.position * px
		assert_near(p.x, roundf(p.x), 0.01, "x on the grid:")
		assert_near(p.y, roundf(p.y), 0.01, "y on the grid:")
	assert_eq(g.snap_cam(Vector2(10.3, 4.6), 4.0), Vector2(10.25, 4.5), "a quarter of a unit at 4 px a unit")
	g.free()


func test_camera_settings_and_flags() -> void:
	var g := _game()
	for k in ["cam_lead", "cam_clash", "cam_settle"]:
		assert_true(k in g.SETTING_PAGES["video"], "a Video setting: " + k)
		assert_eq(g.cam_level(k), g.CAM_DEFAULT, "Normal by default")
	g._open_settings_page("video")
	var row: OptionRow = g._setting_rows["cam_clash"]
	row.grab_focus()
	_press("ui_left")
	_press("ui_left")
	assert_eq(g.cam_clash, 0, "Off")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(int(cfg.get_value("video", "cam_clash", -1)), 0, "and it is saved")
	assert_eq(g.cam_level_arg("0"), 0, "")
	assert_eq(g.cam_level_arg("1"), g.CAM_DEFAULT, "")
	assert_eq(g.cam_level_arg("high"), 3, "")
	assert_eq(g.cam_level_arg("x"), -1, "")
	g._cam_cli["cam_lead"] = 0
	assert_eq(g.cam_level("cam_lead"), 0, "the command line outranks the setting")
	g.free()


func test_the_letterbox_comes_in_only_for_a_knockout_or_a_surge_freeze() -> void:
	var g := _game()
	g._start_match(2)
	_tick(g, 60)
	var lb: Letterbox = g.letterbox
	assert_eq(lb.h, 0, "a normal fight: no bars")
	# The KO push-in: bars slide in whole pixels at a time, and go once the push eases out.
	g._ko_cam_t = 0
	var seen := []
	for i in 12:
		g._update_letterbox()
		seen.append(lb.h)
	assert_eq(lb.h, Letterbox.BAR_H, "in for the knockout")
	assert_eq(seen[0], Letterbox.BAR_STEP_IN, "sliding in, a step a tick")
	g._ko_cam_t = g.KO_HOLD_UNTIL
	for i in 30:
		g._update_letterbox()
	assert_eq(lb.h, 0, "out as the camera eases back")
	g._ko_cam_t = -1
	# A Surge's freeze: as long as it lasts.
	g._surge_bars = 18
	for i in 10:
		g._update_letterbox()
	assert_eq(lb.h, Letterbox.BAR_H, "in for the Surge")
	for i in 30:
		g._update_letterbox()
	assert_eq(lb.h, 0, "out after the freeze")
	# The title's background match never gets them.
	g.flow = g.Flow.MENU
	g._ko_cam_t = 0
	for i in 12:
		g._update_letterbox()
	assert_eq(lb.h, 0, "not behind the menu")
	g._ko_cam_t = -1
	# The push-in: held a beat, then eased in and out, never past 0..1.
	assert_eq(g.ko_push(0), 0.0, "still on the impact")
	assert_eq(g.ko_push(g.KO_PUSH_DELAY), 0.0, "")
	assert_near(g.ko_push(g.KO_PUSH_DELAY + g.KO_PUSH_IN), 1.0, 0.001, "all the way in:")
	assert_near(g.ko_push(g.KO_HOLD_UNTIL), 1.0, 0.001, "held:")
	assert_eq(g.ko_push(g.KO_HOLD_UNTIL + g.KO_PUSH_OUT), 0.0, "back out")
	var prev := 0.0
	for t in range(g.KO_PUSH_DELAY, g.KO_PUSH_DELAY + g.KO_PUSH_IN + 1):
		var k: float = g.ko_push(t)
		assert_true(k >= prev and k - prev < 0.06, "eased in at %d: %.3f after %.3f" % [t, k, prev])
		prev = k
	g.free()


func test_the_letterbox_holds_for_the_whole_surge_cut_in() -> void:
	var g := _game()
	g._start_match(2)
	_tick(g, 2)
	var lb: Letterbox = g.letterbox
	# A freezing Surge: the freeze is shorter than the cut-in, the bars stay for the cut-in.
	g._surge_bars = 18
	g.hud.cut_in(g.sim.creatures[0], 0, "Surge")
	for i in Hud.CUT_IN_TICKS - 2:
		g.hud.advance()
		g._update_letterbox()
	assert_true(g.hud.cutting_in(), "the cut-in is still up")
	assert_eq(lb.h, Letterbox.BAR_H, "the bars hold past the freeze, through the cut-in")
	for i in 20:
		g.hud.advance()
		g._update_letterbox()
	assert_false(g.hud.cutting_in(), "")
	assert_eq(lb.h, 0, "then slide out")
	g.free()


## A game with the intro allowed (headless runs skip it unless --intro).
func _intro_game() -> Node:
	var g := _game()
	g._intro_arg = 1
	return g


func test_the_arena_intro_holds_the_sim_and_hands_over_to_the_round() -> void:
	var g := _intro_game()
	g._start_match(0)  # Cairn vs CPU Culvert
	assert_true(g.intro != null, "an offline 1v1 gets the intro")
	assert_true(g.hud.cinema, "no HUD panels during it")
	assert_eq(g.intro.groups.size(), 2, "one beat per fighter")
	var length: int = g.intro.length()
	assert_lt(length, 150, "short: about two seconds before the ROUND 1 / FIGHT banners")
	_tick(g, 40)
	assert_eq(g.sim.tick, 0, "the sim waits at its first tick")
	assert_eq(g.flow, g.Flow.INTRO, "")
	assert_eq(g.flow_t, 0, "the round's own intro hasn't started")
	assert_gt(g.letterbox.h, 0, "the bars are in")
	_tick(g, length)
	assert_true(g.intro == null, "over by itself")
	assert_false(g.hud.cinema, "")
	assert_gt(g.sim.tick, 0, "the sim runs")
	g.free()


func test_a_press_skips_the_arena_intro() -> void:
	var g := _intro_game()
	g._start_match(0)
	_tick(g, 20)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	_root().push_input(ev)
	assert_true(g.intro == null, "any key skips it")
	assert_false(g.paused, "the press only skips (Esc doesn't also pause)")
	_tick(g, 1)
	assert_eq(g.sim.tick, 1, "the sim starts on the next tick")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_ESCAPE
	_root().push_input(up)
	g.free()


func test_the_arena_intro_does_not_change_the_match() -> void:
	# With and without the intro, the same seed plays the same match tick for tick.
	var digests := []
	for with_intro in [false, true]:
		var g := _intro_game() if with_intro else _game()
		g.seed_base = 7
		g._start_match(2)  # CPU vs CPU
		if with_intro:
			assert_true(g.intro != null, "")
			_tick(g, g.intro.length())
		_tick(g, 400)
		digests.append([g.sim.tick, g.sim.state_digest()])
		g.free()
	assert_eq(digests[1], digests[0], "the intro is a view: same ticks, same state")


func test_no_arena_intro_where_it_does_not_belong() -> void:
	var g := _game()
	g._start_match(0)
	assert_true(g.intro == null, "headless (tests, the server, smoke runs): off by default")
	var no_intro: Array = [3, 5, g.mode_index("Combo Trials")]  # training, showcases, trials
	g.free()
	for m in no_intro:
		g = _intro_game()
		g._start_match(m)
		assert_true(g.intro == null, "no intro in %s" % g.MODES[m]["label"])
		g.free()
	g = _intro_game()
	g._intro_arg = -1  # --no-intro
	g._start_match(0)
	assert_true(g.intro == null, "--no-intro")
	g.free()
	g = _intro_game()
	g.match_intros = false  # Settings > Game > Match intros: Off
	g._start_match(0)
	assert_true(g.intro == null, "the setting turns it off")
	g.free()
	g = _intro_game()
	g._start_match(0)
	g._open_menu()
	assert_true(g.intro == null, "back to the menu drops it")
	g.free()


func test_a_team_intro_introduces_each_team_together() -> void:
	var g := _intro_game()
	g._skip_select = true
	g._start_match(30)  # Team battle 3v3 vs CPU
	assert_true(g.intro != null, "")
	assert_eq(g.intro.groups.size(), 2, "one beat per team, not per fighter")
	for side in 2:
		assert_eq((g.intro.groups[side]["slots"] as Array).size(), 3, "the whole team at once")
	_tick(g, g.intro.length() + 1)
	assert_eq(g.team_battle.sim.tick, 1, "then the team battle's own intro starts at its first tick")
	g.free()


func test_the_match_intros_setting_saves() -> void:
	var g := _game()
	g._open_menu("game")
	var row: OptionRow = g._setting_rows["intros"]
	assert_true(g.match_intros, "on by default")
	row.grab_focus()
	_press("ui_right")
	assert_false(g.match_intros, "Off")
	g._save_settings()
	g.free()
	var g2: Node = load("res://scenes/main.tscn").instantiate()
	g2.settings_path = TEST_SETTINGS
	_root().add_child(g2)
	assert_false(g2.match_intros, "kept after a restart")
	g2.free()


func test_the_hud_anchors_to_the_screen() -> void:
	var h := Hud.new()
	_root().add_child(h)
	h._layout()
	var vs: Vector2 = _root().get_visible_rect().size
	assert_near(h._sw, vs.x, 0.01, "the HUD knows the screen's width:")
	assert_lt(h._hr - h._hl, Hud.HUD_MAX_W + 0.01, "the health panels stay within the HUD width")
	assert_near((h._hl + h._hr) * 0.5, vs.x * 0.5, 0.01, "centred:")
	h.free()


# ------------------------------------------------------------------ menu and mode fixes

func _row_index(label: String) -> int:
	var rows: Array = load("res://src/game/main.gd").MENU_ROWS
	for i in rows.size():
		if String(rows[i]["label"]) == label:
			return i
	return -1


## Plays a team mode to its end: picks fighters, forces the sim's finish, runs the banner out.
func _finish_team(g: Node, label: String, winner: int, how: String, prep: Callable = Callable()) -> void:
	g._start_match(g.mode_index(label))
	g._on_teams_chosen([["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]])
	_tick(g, 200)
	if prep.is_valid():
		prep.call(g.team_battle)
	g.team_battle._finish(winner, how)
	for e in g.sim.events:  # the event the sim emits in its step (called outside one it isn't read)
		if e["type"] == "duel_over":
			g._react(e)
	_tick(g, 200)
	assert_eq(g.flow, g.Flow.MATCH_OVER, label + " is over:")


func test_the_final_banner_says_why_the_match_ended() -> void:
	var g := _game()
	_finish_team(g, "Team Deathmatch: 3v3 vs CPU", 0, "score", func(t): t.score = [12, 9])
	assert_eq(g.hud.banner, "YOUR TEAM WINS!", "")
	assert_true(g.hud.banner_sub.contains("12 - 9"), "a score: " + g.hud.banner_sub)
	_finish_team(g, "King of the Crater: 3v3 vs CPU", 1, "hold", func(t): t.score = [1200, 3600])
	assert_true(g.hud.banner_sub.contains("20 s - 60 s") and not g.hud.banner_sub.contains("3600"),
		"the Crater prints seconds, not ticks: " + g.hud.banner_sub)
	_finish_team(g, "Caravan: 3v3 vs CPU", 0, "caravan", func(t):
		t.cv_round = 1
		t.cv_time = [2400, 3000])
	assert_true(g.hud.banner_sub.contains("Faster finish") and g.hud.banner_sub.contains("40 s - 50 s"),
		"the Caravan says the finish times: " + g.hud.banner_sub)
	_finish_team(g, "Capture the Flag: 3v3 vs CPU", 0, "capture", func(t): t.score = [3, 1])
	assert_true(g.hud.banner_sub.contains("Captures") and g.hud.banner_sub.contains("3 - 1"), g.hud.banner_sub)
	_finish_team(g, "Team battle: 3v3 vs CPU", 0, "ko")
	assert_eq(g.hud.banner_sub, "K.O.", "a team battle by knockout:")
	_finish_team(g, "Sinkhole: 3v3 vs CPU", 1, "time")
	assert_eq(g.hud.banner_sub, "Time: more health left", "by the clock:")
	g.free()


func test_the_duel_and_versus_reasons() -> void:
	var g := _game()
	g._over_by = "time"
	assert_eq(g._over_reason(), "Time: more health left", "")
	g._over_by = "ko"
	assert_eq(g._over_reason(), "K.O.", "")
	# A Versus round ends through _end_round, which remembers how.
	g._start_match(g.mode_index("Versus CPU") if g.mode_index("Versus CPU") >= 0 else 0)
	_tick(g, 200)
	g._end_round(-2)
	assert_eq(g._over_by, "time", "")
	g._end_round(0)
	assert_eq(g._over_by, "ko", "")
	g.free()


func test_the_crater_sudden_death_text_is_about_the_zone() -> void:
	var g := _game()
	g._start_match(g.mode_index("King of the Crater: 3v3 vs CPU"))
	g._on_teams_chosen([["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]])
	_tick(g, 200)
	g.team_battle.overtime = true
	g.team_battle.timer = -5
	g._team_flow()
	assert_eq(g.hud.banner, "SUDDEN DEATH", "")
	assert_false(g.hud.banner_sub.contains("KO"), "KOs score nothing in the Crater: " + g.hud.banner_sub)
	assert_true(g.hud.banner_sub.contains("zone"), g.hud.banner_sub)
	g.free()


func test_every_team_mode_has_a_goal_line() -> void:
	var plain := TeamSim.new([["cairn", "sno"], ["culvert", "digby"]], 2)
	assert_eq(plain.goal_text(), "LAST TEAM STANDING", "a team battle:")
	var sink := TeamSim.new([["cairn", "sno"], ["culvert", "digby"]], 2, TeamSim.load_rules(TeamSim.SINKHOLE_PATH))
	assert_eq(sink.goal_text(), "THE EDGE FALLS IN", "the Sinkhole:")


func test_active_mutators_stay_on_the_hud() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(g.mode_index("Chaos Cup"))
	_tick(g, 300)
	assert_eq(g.brawl.phase, BrawlSim.Phase.FIGHT, "the Brawl is stepped: past its intro")
	assert_true(g.hud.mutator_text != "", "Chaos Cup names its mutators beside the clock")
	assert_eq(g.hud.banner_sub, "", "after the intro line is gone")
	g._start_match(g.mode_index("Daily Challenge"))
	_tick(g, 300)
	assert_true(g.hud.mutator_text != "", "and so does the Daily Challenge: " + g.hud.mutator_text)
	g._start_match(g.mode_index("Brawl: you vs 3 CPUs"))
	assert_eq(g.hud.mutator_text, "", "a plain Brawl has none")
	g.free()


func test_brawl_and_chaos_cup_open_the_pick_screen() -> void:
	var g := _game()
	g._start_match(g.mode_index("Chaos Cup"))
	assert_eq(g.flow, g.Flow.SELECT, "the pick comes first")
	assert_true(g.ui.top() is CharacterSelect, "")
	g._on_teams_chosen([["digby"], ["cairn"]])
	assert_true(g.brawl != null, "then the Brawl")
	assert_eq(String(g.sim.creatures[0].def["id"]), "digby", "you play the pick:")
	var lone := _game()
	lone._start_match(lone.mode_index("Brawl: you vs 3 CPUs"))
	assert_true(lone.ui.top() is CharacterSelect, "Brawl too")
	lone.free()
	var skip := _game()
	skip._skip_select = true  # --mode=N
	skip._start_match(skip.mode_index("Brawl: you vs 3 CPUs"))
	assert_true(skip.brawl != null and not skip.ui.is_open(), "--mode=N skips it:")
	skip.free()
	g.free()


func test_leaving_a_match_returns_to_the_page_and_row_it_came_from() -> void:
	var g := _game()
	g._open_menu()
	_press("ui_accept")  # Single player
	_open_card(g, "Team battles")
	var page: UiScreen = g.ui.top()
	for r in page.rows():
		if r is OptionRow and (r as OptionRow).label == "Capture the Flag vs CPU":
			r.grab_focus()
	_press("ui_accept")
	assert_true(g.ui.top() is CharacterSelect, "the pick screen")
	_press("ui_cancel")  # the pick's Back
	assert_true(g.ui.top() is UiScreen and (g.ui.top() as UiScreen).title == page.title, "back on the group page")
	assert_eq(((g.ui.top() as UiScreen).crumbs), ["SINGLE PLAYER"], "")
	assert_true(_focus() is OptionRow and (_focus() as OptionRow).label == "Capture the Flag vs CPU",
		"on the same row")
	# And from a match: pause > Quit.
	_press("ui_accept")
	g._on_teams_chosen([["cairn"], ["culvert"]])
	_tick(g, 30)
	_press("pause")
	g.ui.top().quit_requested.emit()
	assert_eq(g.flow, g.Flow.MENU, "")
	assert_eq((g.ui.top() as UiScreen).title, page.title, "Quit lands on the page too")
	# A match started from the command line has no page to go back to.
	g._row_from = {}
	g._back_to_row()
	assert_true(g.ui.top() is TitleScreen, "the title:")
	g.free()


func test_the_left_right_fighter_choice_is_kept_between_launches() -> void:
	var g := _game()
	var r := _row_index("Versus CPU")
	g._row_choice[r] = 5
	g._save_settings()
	g.free()
	var again: Node = load("res://scenes/main.tscn").instantiate()
	again.settings_path = TEST_SETTINGS
	_root().add_child(again)
	assert_eq(int(again._row_choice[r]), 5, "")
	again.free()


func test_gauntlet_restart_says_what_it_does_and_leaving_records_the_best() -> void:
	var p := "user://test_progress_menu_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(p)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var g := _game()
	g._arcade_fighter = "sno"
	g._skip_select = true
	g._start_match(g.mode_index("Gauntlet"))
	g.arcade.stage = 4
	g._open_pause()
	var pause: PauseScreen = g.ui.top()
	assert_true(pause.restart_question.contains("new run"), pause.restart_question)
	assert_true(pause.restart_note.contains("4 wave"), pause.restart_note)
	pause.quit_requested.emit()
	assert_eq(Progress.gauntlet_best("sno"), 4, "Quit counts the waves cleared:")
	g.free()
	Progress.reset_for_tests("user://progress.json")


func test_the_arcade_boss_has_its_own_intro_and_a_clear_offers_a_new_run() -> void:
	var p := "user://test_progress_menu_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(p)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var g := _game()
	g._skip_select = true
	g._start_match(g.mode_index("Arcade"))
	g.arcade.stage = Arcade.STAGES - 1
	g._start_arcade_stage()
	_tick(g, 10)
	assert_eq(g.hud.banner, "STAGE 6 of 6", "")
	assert_true(g.hud.banner_sub.contains("BOSS TEAM"), g.hud.banner_sub)
	assert_true(g._arcade_result(true), "the boss falls")
	g.flow_t = 0
	_tick(g, g.MATCH_OVER_MENU_AT + 1)
	if g.ui.top() is EndingScreen:  # Progression on: the fighter's ending card first (tests/test_endings.gd)
		(g.ui.top() as EndingScreen).continue_button.pressed.emit()
	var labels: Array = []
	for r in g.ui.top().rows():
		labels.append((r as Button).text)
	assert_true("New run" in labels and not ("Retry the stage" in labels), "after a clear: " + str(labels))
	g.free()
	Progress.reset_for_tests("user://progress.json")


## On a fresh install the replays folder doesn't exist yet: the Replay theater says there are
## none (without an engine error), F6 makes the folder and saves, and the theater then lists it.
## (This test once failed only on a fresh user folder: it listed the missing folder with
## DirAccess.get_files_at, which logs an error; the folder came from the first run's save.)
func test_f6_saves_the_replay_at_the_match_over_screen() -> void:
	var g := _game()
	var dir := "user://test_replays_fresh_%d" % Time.get_ticks_usec()
	assert_false(DirAccess.dir_exists_absolute(dir), "a folder not made yet")
	g.replays_dir = dir
	g._open_replays()
	var none: Array = g.ui.top().find_children("*", "Label", true, false).filter(
		func(l): return (l as Label).text.begins_with("No replays yet"))
	assert_eq(none.size(), 1, "the theater says none yet:")
	g.ui.clear()
	g._start_match(2)  # CPU vs CPU
	_tick(g, 60)
	g.flow = g.Flow.MATCH_OVER
	g.flow_t = g.MATCH_OVER_MENU_AT - 1
	_tick(g, 2)
	assert_true(g.ui.is_open(), "the match-over menu is up")
	_press("save_replay")
	assert_true(DirAccess.dir_exists_absolute(dir), "F6 made the folder")
	var added := Array(DirAccess.get_files_at(dir))
	assert_eq(added.size(), 2, "F6 saved the fight just finished (and its clip markers beside it):")
	assert_eq(added.filter(func(f): return ClipMarks.is_sidecar(String(f))).size(), 1, "one of them the sidecar:")
	g.ui.clear()
	g._open_replays()
	assert_eq(g.ui.top().rows().size(), 2, "the theater lists it (and Back):")
	g.ui.clear()
	for f in added:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(String(f))))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	g.free()


func test_pausing_a_watched_replay_or_a_spectated_room_has_no_restart() -> void:
	var g := _game()
	g._start_match(0)
	_tick(g, 140)
	var path := "user://replays/replay_test_pause_%d.json" % Time.get_ticks_usec()
	assert_eq(g.replay.save(path), OK, "")
	g._play_replay(path)
	_tick(g, 5)
	_press("pause")
	assert_true(g.ui.top() is PauseScreen, "")
	var labels: Array = []
	for r in g.ui.top().rows():
		labels.append((r as Button).text)
	# No Restart; the replay viewer's jumps, speed and keys (replay_viewer.gd), a bug report.
	assert_eq(labels, ["Resume", "Back 5 seconds", "Watch from the start", "Speed: 1x", "Export clip", "Save a bug report",
		"Replay theater", "Controls", "Main menu"], "")
	_press("ui_cancel")
	assert_false(g.paused, "Resume")
	g.watch = Referee.new([["cairn"], ["culvert"]], 0)
	g._open_pause()
	assert_true(g.ui.top() is PauseScreen and not g.paused, "a spectator gets the online pause: the match keeps going")
	var watching: Array = []
	for r in g.ui.top().rows():
		watching.append((r as Button).text)
	assert_true("Stop watching" in watching and not ("Restart" in watching), "Stop watching, no Restart: %s" % [watching])
	g.watch = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	g.free()


func test_the_trials_help_reads_the_bound_keys() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(9)
	assert_eq(g.hud.help_text, "%s watch the demo again    %s next trial    Esc menu" % [
		Controls.binding_text("debug_dummy_mode", "classic"), Controls.binding_text("reset", "classic")], "")
	g.free()


func test_the_description_box_never_changes_size_as_focus_moves() -> void:
	# The mouse focuses whatever it's over: if a longer description grew the panel, the
	# rows would shift under a still cursor, focus another row, and the text would
	# change again. So the box is sized once, for the longest text the page shows.
	var g := _game()
	g._open_menu()
	_press("ui_accept")  # Single player
	for card in ["Team battles", "Challenges"]:
		_open_card(g, card)
		var page: UiScreen = g.ui.top()
		assert_true(page.detail, card + ": rows on the left, the panel on the right")
		var sizes := {}
		var texts := {}
		for r in page.rows():
			(r as Control).grab_focus()
			sizes[[page._desc.get_combined_minimum_size(), page._extra.get_combined_minimum_size()]] = true
			texts[page._desc.text] = true
			if r is OptionRow:  # Left/Right swap what the card shows, never how much
				for i in 3:
					_press("ui_right")
					sizes[[page._desc.get_combined_minimum_size(), page._extra.get_combined_minimum_size()]] = true
			var label: String = (r as OptionRow).label if r is OptionRow else (r as Button).text
			assert_eq(page._detail_title.text, label, card + ": the panel is titled after the row")
		assert_true(texts.size() > 1, card + ": the text changes with the row")
		assert_eq(sizes.size(), 1, card + ": the box never does: " + str(sizes.keys()))
		(page.rows().back() as Control).grab_focus()  # Back has no text of its own
		assert_eq(page._desc.text, page.blurb, card + ": Back shows the page's own line")
		_press("ui_cancel")
	# A page that keeps the line under the column holds two lines whatever the text.
	g._start_match(2)
	_tick(g, 30)
	_press("pause")
	var pause: UiScreen = g.ui.top()
	var pause_sizes := {}
	for r in pause.rows():
		(r as Control).grab_focus()
		pause_sizes[pause._desc.get_combined_minimum_size()] = true
	assert_eq(pause_sizes.size(), 1, "the pause menu's line: " + str(pause_sizes.keys()))
	assert_eq(pause._desc.max_lines_visible, 2, "two lines")
	g.free()


func test_the_card_shows_the_fighter_the_row_names_and_the_modes_facts() -> void:
	var g := _game()
	g._open_menu()
	_press("ui_accept")  # Single player
	_open_card(g, "Challenges")
	var page: UiScreen = g.ui.top()
	var arcade: OptionRow = page.rows()[0]
	assert_eq(arcade.label, "Arcade", "")
	arcade.grab_focus()
	var card: DetailCard = page.card(arcade)
	assert_true(card.visible, "the focused row's card shows")
	assert_eq(card.fighter, MatchFactory.FIGHTERS[0], "the first choice's fighter:")
	_press("ui_right")
	_press("ui_right")
	assert_eq(card.fighter, MatchFactory.FIGHTERS[2], "Right twice: the third:")
	assert_true(String(card.facts[0]).begins_with("%d stages" % Arcade.STAGES), "the Arcade's facts: " + str(card.facts))
	_press("ui_down")
	assert_false(card.visible, "another row: its card hides")
	assert_true((page.card(page.rows()[1]) as DetailCard).visible, "and that row's shows")
	_press("ui_cancel")
	_open_card(g, "Team battles")
	page = g.ui.top()
	var tdm: OptionRow = page.rows()[1]
	assert_eq(tdm.label, "Team Deathmatch vs CPU", "")
	var want: Array = TeamSim.rules_by_id("deathmatch")["score_to_win"]
	var tc: DetailCard = page.card(tdm)
	assert_eq(tc.fighter, "", "a team row shows no fighter")
	assert_true(String(tc.facts[0]).begins_with("First to %d KOs" % int(want[2])), "2 v 2: " + str(tc.facts))
	tdm.grab_focus()
	_press("ui_right")  # 3 v 3
	assert_true(String(tc.facts[0]).begins_with("First to %d KOs" % int(want[3])), "3 v 3: " + str(tc.facts))
	assert_true(tc.facts.size() <= 3, "three lines at most")
	for r in page.rows():
		var k: DetailCard = page.card(r)
		if r is Button and (r as Button).text == "Back":
			assert_true(k == null or k.facts.is_empty(), "Back has no facts")
		else:
			assert_true(k != null and not k.facts.is_empty(), "every mode row has facts: " + str(r))
	# The hub's Arena row shows the map.
	_press("ui_cancel")
	var hub: UiScreen = g.ui.top()
	var arena: OptionRow = hub.rows()[0]
	assert_eq(arena.label, "Arena", "")
	assert_true((hub.card(arena) as DetailCard).picture != null, "a picture of the arena")
	g.free()


func test_the_glow_setting_hides_the_lights_and_saves() -> void:
	var main_script: GDScript = load("res://src/game/main.gd")
	assert_false(main_script.default_glow(true), "off by default on a phone or handheld")
	assert_true(main_script.default_glow(false), "on by default on a desktop")
	var g := _game()
	assert_true("glow" in g.SETTING_PAGES["video"], "a Video setting")
	g._set_setting("glow", 0)
	assert_false(g.glow_floor.visible or g.glow_halo.visible, "Off hides both layers")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(cfg.get_value("video", "glow", true), false, "and it is saved")
	g._set_setting("glow", 1)
	assert_true(g.glow_floor.visible, "On again")
	assert_eq(g.glow_halo.visible, g.lighting_tier() != Light2DView.Tier.HIGH,
		"its halos too, except with Lighting High (the bloom draws them)")
	g._set_setting("lighting", Light2DView.Tier.LOW)
	assert_true(g.glow_halo.visible, "Lighting Low: halos back")
	g._set_setting("lighting", Light2DView.Tier.HIGH)
	assert_false(g.glow_halo.visible, "High: the bloom stands in for them")
	g.queue_free()


func test_the_text_font_setting_switches_menus_and_saves() -> void:
	var g := _game()
	g._open_settings_page("video")
	g._set_setting("font", 1)
	assert_true(UiTheme.smooth, "Smooth is on")
	assert_true(g.ui.ui_theme.default_font == ThemeDB.fallback_font, "the open menus take the smooth font")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(String(cfg.get_value("video", "font", "")), "smooth", "and it is saved")
	g._set_setting("font", 0)
	assert_false(UiTheme.smooth, "Pixel again")
	assert_true(g.ui.ui_theme.default_font == UiTheme.font(), "back to the pixel font")
	g.queue_free()


# ------------------------------------------------------------------ voice chat

func test_the_audio_page_has_the_voice_chat_rows() -> void:
	var g := _game()
	g._open_menu("game")
	g._open_settings_page("audio")
	var labels := {}
	for key in ["voice", "mic", "vol_Voice"]:
		var row: OptionRow = g._setting_rows.get(key)
		assert_true(row != null, "a %s row" % key)
		if row != null:
			labels[key] = row.label
	assert_eq(labels.get("voice"), "Voice chat", "")
	assert_eq(labels.get("mic"), "Microphone", "")
	assert_eq(labels.get("vol_Voice"), "Voice volume", "and its own volume")
	assert_eq((g._setting_rows["voice"] as OptionRow).values, VoiceChat.MODE_NAMES, "off, push to talk, open mic")
	assert_gt((g._setting_rows["mic"] as OptionRow).values.size(), 0, "a microphone choice (Default without devices)")
	assert_true(AudioServer.get_bus_index("Voice") >= 0, "the Voice bus is a volume group")
	g.free()


func test_test_microphone_records_shows_a_level_and_plays_back() -> void:
	var g := _game()
	g._open_menu("game")
	g._open_settings_page("audio")
	var row: OptionRow = g._setting_rows.get("mic_test")
	assert_true(row != null, "a Test microphone row on the Audio page")
	if row == null:
		g.free()
		return
	assert_eq(row.value_text(), "Press to test", "idle, and no arrows on a one-value row")
	var v: VoiceView = g.voice_view
	v.tone = true  # headless: the tone stands in for the microphone
	row.activated.emit()
	assert_eq(v.test_state, VoiceView.Test.RECORDING, "Enter starts recording")
	v.test_step(0.5)
	g._refresh_mic_test()
	assert_true(row.value_text().begins_with("Speak now"), "counts down: " + row.value_text())
	assert_gt(row.bar, 0.3, "the bar shows the tone's level")
	for k in 6:
		v.test_step(0.5)
	assert_eq(v.test_state, VoiceView.Test.PLAYING, "after the recording it plays back")
	assert_gt(v._test_pcm.size(), int(AudioServer.get_mix_rate() * 2.5), "about three seconds recorded")
	for k in 8:
		v.test_step(0.5)
	assert_eq(v.test_state, VoiceView.Test.IDLE, "and ends")
	v.tone = false
	row.activated.emit()
	v.test_step(0.1)
	assert_eq(v.test_state, VoiceView.Test.NO_MIC, "no microphone headless: it says so")
	g._refresh_mic_test()
	assert_eq(row.value_text(), "No microphone", "")
	g.free()


func test_the_voice_chat_setting_is_saved_and_read_back() -> void:
	var g := _game()
	g._open_menu("game")
	g._open_settings_page("audio")
	assert_eq(g.voice_mode, VoiceChat.Mode.PUSH_TO_TALK, "push to talk by default")
	var row: OptionRow = g._setting_rows["voice"]
	row.grab_focus()
	_press("ui_right")
	assert_eq(g.voice_mode, VoiceChat.Mode.OPEN_MIC, "Right: open mic")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(int(cfg.get_value("audio", "voice_mode", -1)), VoiceChat.Mode.OPEN_MIC, "saved at once")
	g.free()
	var again: Node = load("res://scenes/main.tscn").instantiate()
	again.settings_path = TEST_SETTINGS
	_root().add_child(again)
	assert_eq(again.voice_mode, VoiceChat.Mode.OPEN_MIC, "kept after a restart")
	again.free()


func test_the_voice_flag_lasts_the_session_and_is_never_saved() -> void:
	var g := _game()
	g._voice_arg("--voice=off")
	assert_eq(g.voice_mode_now(), VoiceChat.Mode.OFF, "--voice=off")
	g._voice_arg("--voice=open")
	assert_eq(g.voice_mode_now(), VoiceChat.Mode.OPEN_MIC, "--voice=open")
	assert_eq(g.voice_mode, VoiceChat.Mode.PUSH_TO_TALK, "the setting itself stays")
	g.netplay = Netplay.new()
	g._apply_voice()
	assert_eq(g.netplay.voice.mode, VoiceChat.Mode.OPEN_MIC, "a session gets the flag's mode")
	g.netplay = null
	g._save_settings()
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(int(cfg.get_value("audio", "voice_mode", -1)), VoiceChat.Mode.PUSH_TO_TALK, "not saved")
	g.free()


func test_push_to_talk_is_bound_in_every_group_and_listed_for_remapping() -> void:
	Controls.setup()
	Controls.reset()
	for a in ["kb_talk", "lol_talk", "pad_talk"]:
		assert_true(InputMap.has_action(a), a + " exists")
	assert_true(_key(KEY_V).is_action_pressed("kb_talk"), "V talks (classic)")
	assert_true(_key(KEY_V).is_action_pressed("lol_talk"), "V talks (league)")
	var ls := InputEventJoypadButton.new()
	ls.button_index = JOY_BUTTON_LEFT_STICK
	ls.pressed = true
	ls.device = 1
	assert_true(ls.is_action_pressed("pad_talk"), "the left stick click talks, on any controller")
	for a in Controls.BINDINGS:
		if a.ends_with("_talk"):
			continue
		assert_false(_key(KEY_V).is_action_pressed(a), "V does nothing else (%s)" % a)
	var groups := {"classic": "kb_talk", "league": "lol_talk", "gamepad": "pad_talk"}
	var st := _stack()
	for group in groups:
		var listed := false
		for pair in Controls.REMAP[group]:
			listed = listed or String(pair[0]) == groups[group]
		assert_true(listed, "%s lists Talk" % group)
		var scr := RemapScreen.new(group)
		st.push(scr)
		var texts := []
		for b in scr.rows():
			if b is Button:
				texts.append((b as Button).text)
		assert_true("Talk (push to talk)" in texts, "the %s remap screen shows it: %s" % [group, str(texts)])
		st.pop()
	st.free()


func test_the_voice_view_does_nothing_without_an_online_match() -> void:
	var vv := VoiceView.new()
	_root().add_child(vv)
	vv.frame(null, null, -1, Vector2.ZERO, true, 1.0 / 60.0)
	assert_false(vv.sending, "nothing sent")
	assert_false(vv.speaking(0), "nobody speaking")
	assert_true(vv.heard.is_empty(), "")
	assert_true(vv._mic == null, "the microphone never opened")
	assert_true(vv._players.is_empty(), "no speakers")
	vv.free()


func test_a_voice_is_placed_by_where_its_fighter_stands() -> void:
	var p := VoiceView.place(Vector2(300, 100), Vector2(100, 100), false)
	assert_near(p.x, VoiceChat.gain_for(200.0, false), 0.0001, "gain from the distance:")
	assert_near(p.y, VoiceChat.pan_for(200.0), 0.0001, "to the right:")
	var q := VoiceView.place(Vector2(-400, 100), Vector2(400, 100), true)
	assert_near(q.x, VoiceChat.gain_for(800.0, true), 0.0001, "a far teammate keeps the floor:")
	assert_near(q.y, -1.0, 0.0001, "far left")
	# A real packet from slot 1 (the other side's fighter, 250 px right and 100 down).
	var d := DuelSim.new([["cairn"], ["culvert"]])
	d.active_creature(0).pos = Vector2(200, 150)
	d.active_creature(1).pos = Vector2(450, 250)
	var links := LoopLink.pair()
	var np := Netplay.new()
	np.voice.link = links[1]
	np.voice.reset(1, 0)
	var far := VoiceChat.new()
	far.link = links[0]
	far.reset(1, 1)
	var now := Time.get_ticks_msec()
	var n := far.frame_samples()
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	for i in n:
		pcm[i] = 0.4 * sin(TAU * 220.0 * i / far.sample_rate())
	for k in 6:
		far.clock_ms = now
		far.push_mic(pcm, true)
	np.voice.clock_ms = now
	for m in links[1].poll():
		if String(m.get("t", "")) == "vc":
			np.voice.receive(m)
	assert_gt(np.voice.received, 0, "packets arrived")
	var vv := VoiceView.new()
	_root().add_child(vv)
	vv.frame(np, d, 0, Vector2.ZERO, false, 1.0 / 60.0)
	var want := VoiceView.place(Vector2(450, 250), Vector2(200, 150), false)
	var got: Vector2 = vv._place.get(1, Vector2(-1, -1))
	assert_near(got.x, want.x, 0.0001, "the gain heard is gain_for its distance:")
	assert_near(got.y, want.y, 0.0001, "and the pan pan_for its offset:")
	assert_near(got.x, VoiceChat.gain_for(Vector2(250, 100).length(), false), 0.0001, "")
	assert_true(vv.speaking(1), "slot 1 is speaking (the icon)")
	assert_false(vv.speaking(0), "we are not")
	assert_true(vv._players.is_empty(), "headless: no speakers made")
	vv.stop()
	assert_false(vv.speaking(1), "stop() clears it")
	vv.free()


# ------------------------------------------------------------------ voice chat safety

func test_hear_voices_from_is_on_the_audio_page_and_kept() -> void:
	var g := _game()
	g._open_settings_page("audio")
	assert_true(g._setting_rows.has("voice_hear"), "Settings > Audio has Hear voices from")
	var row: OptionRow = g._setting_rows["voice_hear"]
	assert_eq(row.label, "Hear voices from", "")
	assert_eq(String(row.values[row.index]), "Everyone", "everyone by default:")
	row.grab_focus()
	_press("ui_right")
	assert_eq(g.voice_hear, 1, "Right picks Rooms and friends:")
	g.free()
	var again: Node = load("res://scenes/main.tscn").instantiate()
	again.settings_path = TEST_SETTINGS
	_root().add_child(again)
	assert_eq(again.voice_hear, 1, "and the next launch reads it back:")
	again.free()


## The game in an online match on an in-memory server with another player (a Quick match
## with `room` "", else that room), `hear` the Hear voices from setting. Returns
## [server, other] once the match is on (or not, if it never started).
func _voice_match(g: Node, room: String, hear: int) -> Array:
	g.voice_hear = hear
	g._start_match(20)  # Online
	var server := RelayServer.new()
	var la := LoopLink.pair()
	var lb := LoopLink.pair()
	server.add_client(la[0])
	server.add_client(lb[0])
	var me := Netplay.new()
	me.room = room
	me.my_name = "Me"
	me.join("server", 0, ["cairn"], la[1])
	var other := Netplay.new()
	other.room = room
	other.my_name = "Rival"
	other.team_size = 0 if room != "" else 1
	other.join("server", 0, ["sno"], lb[1])
	g.lobby.use_fighter("cairn")
	g.netplay = me
	g.lobby.busy = true
	var s := [server, other]
	_step_online(g, s, 400, func(): return g.online != null)
	return s


func test_rooms_and_friends_mutes_quick_match_strangers_but_not_a_room() -> void:
	var g := _game()
	var s := _voice_match(g, "", 1)
	assert_true(g.online != null, "the Quick match starts")
	assert_true(g.netplay.voice.mute_all, "Rooms and friends: strangers start muted")
	g.netplay.voice.mute_all = false  # the player unmutes them in the pause menu...
	g._apply_voice_hear()  # ...and the next match of this session (a rematch) keeps that
	assert_false(g.netplay.voice.mute_all, "a rematch doesn't mute them again")
	g._leave_online()
	g.free()
	g = _game()
	s = _voice_match(g, "", 0)
	assert_true(g.online != null, "")
	assert_false(g.netplay.voice.mute_all, "Everyone: a Quick match starts unmuted")
	g._leave_online()
	g.free()
	g = _game()
	s = _voice_match(g, "fox7", 1)
	assert_true(g.online != null, "the room's match starts")
	assert_false(g.netplay.voice.mute_all, "a room starts unmuted even with Rooms and friends")
	g._leave_online()
	g.free()


func _option(scr: UiScreen, label: String) -> OptionRow:
	for r in scr.rows():
		if r is OptionRow and (r as OptionRow).label == label:
			return r
	return null


func test_the_online_pause_menu_keeps_the_match_going_and_opens_the_voice_screen() -> void:
	var g := _game()
	var s := _voice_match(g, "", 0)
	assert_true(g.online != null, "the match starts")
	g._open_pause()
	assert_true(g.ui.top() is PauseScreen, "Esc online: the pause menu")
	assert_false(g.paused, "the match isn't paused")
	var labels: Array = []
	var voice_btn: Button = null
	for r in g.ui.top().rows():
		if r is Button:
			labels.append((r as Button).text)
			if (r as Button).text == "Voice chat":
				voice_btn = r
	assert_true("Leave match" in labels and "Resume" in labels and voice_btn != null, "Resume, Voice chat, Leave match: %s" % [labels])
	assert_false("Restart" in labels, "no Restart online")
	voice_btn.pressed.emit()
	var scr: UiScreen = g.ui.top()
	assert_eq(scr.title, "VOICE CHAT", "Voice chat opens its screen:")
	var rows: Array = g.voice_rows()
	assert_eq(rows.size(), 1, "one other player: %s" % [rows])
	var slot := 1 - int(g.online.local_slot)
	assert_eq(int(rows[0]["slot"]), slot, "the other slot")
	assert_true(String(rows[0]["label"]).contains("· Sno"), "named with their fighter: " + String(rows[0]["label"]))
	var everyone := _option(scr, "Mute everyone")
	var mic := _option(scr, "Mute my mic")
	var them := _option(scr, String(rows[0]["label"]))
	assert_true(everyone != null and mic != null and them != null, "the rows are there")
	assert_true(_option(scr, "Voice chat") != null, "and the mode setting")
	everyone.step(1)
	assert_true(g.netplay.voice.mute_all, "Mute everyone flips mute_all")
	everyone.step(1)
	assert_false(g.netplay.voice.mute_all, "and back")
	mic.step(1)
	assert_true(g.netplay.voice.mic_muted, "Mute my mic flips mic_muted")
	assert_eq(String(them.values[them.index]), "Hearing", "")
	them.step(1)
	assert_true(g.netplay.voice.is_muted(slot), "a player's row mutes them")
	assert_false(g.netplay.voice.hearing(slot), "")
	them.step(1)
	assert_false(g.netplay.voice.is_muted(slot), "and unmutes")
	# The HUD says what's muted.
	g._voice_step(1.0 / 60.0)
	assert_true(g.hud.mic_muted, "MIC MUTED on the HUD")
	g.netplay.voice.mute_all = true
	g._voice_step(1.0 / 60.0)
	assert_true(g.hud.voice_muted, "VOICE MUTED on the HUD")
	# The match went on underneath.
	var before: int = g.sim.tick
	_step_online(g, s, 30, func(): return false)
	assert_gt(float(g.sim.tick), float(before), "the match keeps stepping with the screens open")
	g._leave_online()
	g.free()


func test_four_players_pick_at_once_one_column_each_no_fighter_twice() -> void:
	var st := _stack()
	var cs := CharacterSelect.new()
	cs.setup("BRAWL", 1, ["PLAYER 1", "PLAYER 2", "PLAYER 3", "PLAYER 4"], true)
	cs.set_pickers([0, 1, 2, 3])
	cs.unique_across = true
	st.push(cs)
	assert_eq(cs.columns, 4, "a column a player")
	assert_true(cs.compact(), "narrow panels")
	var got := []
	cs.chosen.connect(func(t): got.append(t))
	_pad(2, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(cs.cursor[2], 1, "player 3's d-pad moves player 3's cursor:")
	assert_eq(cs.cursor[0], 0, "")
	_pad(2, JOY_BUTTON_A)
	assert_eq(cs.teams[2], [String(cs.roster[1])], "player 3's A picks for column 3:")
	_pad(3, JOY_BUTTON_DPAD_RIGHT)
	_pad(3, JOY_BUTTON_A)
	assert_true(cs.teams[3].is_empty(), "player 4 can't take player 3's fighter")
	_pad(3, JOY_BUTTON_DPAD_RIGHT)
	_pad(3, JOY_BUTTON_A)
	assert_eq(cs.teams[3], [String(cs.roster[2])], "the next one is theirs:")
	_pad(0, JOY_BUTTON_A)
	_pad(1, JOY_BUTTON_DPAD_DOWN)
	_pad(1, JOY_BUTTON_A)
	assert_true(cs.is_done(), "four columns full")
	cs._process(CharacterSelect.START_DELAY + 0.1)
	assert_eq(got.size(), 1, "the match starts:")
	assert_eq((got[0] as Array).size(), 4, "with four one-fighter teams")
	_pad(3, JOY_BUTTON_B)
	assert_eq(got.size(), 1, "")
	st.free()
