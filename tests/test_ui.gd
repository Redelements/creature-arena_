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

func _game() -> Node:
	var g: Node = load("res://scenes/main.tscn").instantiate()
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


func test_the_pick_screen_knows_where_the_mouse_is() -> void:
	var ts := TeamSelect.new()
	ts.open("DUEL", 3, ["PLAYER 1", "CPU"], [["cairn", "culvert", "sno"], ["pete", "digby", "hissy"]])
	assert_eq(ts._row_at(Vector2(TeamSelect.COLS[0] + 20, TeamSelect.TOP + 5)), 0, "the first slot:")
	assert_eq(ts._row_at(Vector2(TeamSelect.COLS[1] + 20, TeamSelect.TOP + TeamSelect.ROW_H + 5)), 4,
		"the CPU's second slot:")
	assert_eq(ts._row_at(ts._start_rect().get_center()), ts._rows() - 1, "START:")
	assert_eq(ts._row_at(Vector2(2, 2)), -1, "nothing:")
	ts.free()


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
	g._open_menu("settings")
	var before: int = g.level
	var row: OptionRow = g._setting_rows["level"]
	row.grab_focus()
	_press("ui_right")
	assert_eq(g.level, (before + 1) % 3, "Right changes the CPU level:")
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


func test_match_over_offers_rematch_and_back_goes_to_the_menu() -> void:
	var g := _game()
	g._start_match(6)  # Duel vs CPU (pick screen)
	g._on_teams_chosen(g.DEFAULT_TEAMS.duplicate(true))
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
