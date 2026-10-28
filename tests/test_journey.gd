extends TestCase
## Every Single player row, driven like a player: title, Single player, the row's page,
## the row with each of its Left/Right choices, Enter; the pick screen when the mode has
## one; the match played by CPUs to the final banner; the match-over choices; and Back,
## which must land on the page and row it came from with the choice kept. A row's first
## choice is played to the end (the clock is run down once the fight is under way, so a
## stalemate can't hang the test); the other choices start, then leave from the pause
## menu. Modes with no end (training, the showcases, trials, drills) leave from the pause
## menu too, and Replay theater opens its screen and comes back. A row only Settings > Game >
## Progression shows (the Weekly Challenge) is walked with Progression on, the rest with it off.

const TEST_SETTINGS := "user://test_journey.cfg"
## Ticks a fight plays before the clock is run down, and what it is run down to.
const HURRY_AT := 600
const HURRY_LEFT := 120
## Ticks of sudden death before the journey settles it (see _hurry).
const OVERTIME_HURRY := 1800
## Ticks the current team battle has spent in sudden death.
var _overtime_ticks := 0
## The most ticks a mode gets to reach its final banner.
const BUDGET := 14000


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


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	Progress.reset_for_tests("user://test_progress_journey_%d.json" % Time.get_ticks_usec())
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	g._online_server = "127.0.0.1:1"  # a won Daily sends its score: to a closed local port here
	g.level = 3  # Rage CPUs finish fights
	g._cpu_vs_cpu = true  # CPUs play the human seats, so a match reaches its end
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


func _group_title(g: Node, gid: String) -> String:
	for group in g.MENU_GROUPS:
		if String(group["id"]) == gid:
			return String(group["title"])
	return ""


## Title > Single player > the row's page > the row, with `choice` picked by Right.
## Returns the page.
func _go_to_row(g: Node, r: int, choice: int) -> UiScreen:
	var row: Dictionary = g.MENU_ROWS[r]
	g._open_menu()
	assert_true(g.ui.top() is TitleScreen, "the title")
	_press("ui_accept")  # Single player
	var hub: UiScreen = g.ui.top()
	assert_eq(hub.title, "SINGLE PLAYER", "the hub")
	var title := _group_title(g, String(row["group"]))
	for c in hub.rows():
		if c is CardButton and (c as Button).text == title:
			(c as Control).grab_focus()
	assert_eq((_focus() as Button).text, title, "the card")
	_press("ui_accept")
	var page: UiScreen = g.ui.top()
	assert_eq(page.title, title.to_upper(), "the page")
	var target: Control = null
	for c in page.rows():
		if c is OptionRow and (c as OptionRow).label == String(row["label"]):
			target = c
		elif c is Button and (c as Button).text == String(row["label"]):
			target = c
	assert_true(target != null, "%s is on the %s page" % [row["label"], title])
	target.grab_focus()
	if target is OptionRow:
		var o := target as OptionRow
		var guard := 0
		while o.index != choice and guard < 20:
			_press("ui_right")
			guard += 1
		assert_eq(o.index, choice, "%s: Right reaches choice %d" % [row["label"], choice])
	_press("ui_accept")
	return page


## Back on the page the row was started from, on that row, with its choice kept.
func _assert_on_row(g: Node, page_title: String, r: int, choice: int, where: String) -> void:
	var row: Dictionary = g.MENU_ROWS[r]
	assert_eq(g.flow, g.Flow.MENU, where + ": the menu")
	var top: UiScreen = g.ui.top()
	assert_true(top is UiScreen and not (top is TitleScreen) and (top as UiScreen).title == page_title,
		"%s: on the %s page, not %s" % [where, page_title, (top as UiScreen).title if top != null else "nothing"])
	assert_eq((top as UiScreen).crumbs, ["SINGLE PLAYER"], where + ": its trail")
	var f := _focus()
	var label := (f as OptionRow).label if f is OptionRow else ((f as Button).text if f is Button else "")
	assert_eq(label, String(row["label"]), where + ": on the row")
	if f is OptionRow:
		assert_eq((f as OptionRow).index, choice, where + ": the choice kept")
		assert_eq(int(g._row_choice[r]), choice, where + ": and saved")


## Through the pick screen, if the mode has one: a real pick first, then the rest at random.
func _through_pick(g: Node, label: String) -> void:
	if not (g.ui.top() is CharacterSelect):
		return
	var cs: CharacterSelect = g.ui.top()
	assert_eq(g.flow, g.Flow.SELECT, label + ": picking")
	_press("ui_accept")
	var guard := 0
	while not cs.is_done() and guard < 16:
		cs.pick(1 if cs.two_players and cs.teams[1].size() < cs.team_size else 0, true)
		guard += 1
	assert_true(cs.is_done(), label + ": both teams picked")
	cs._process(CharacterSelect.START_DELAY + 0.1)
	assert_false(g.ui.top() is CharacterSelect, label + ": the pick closes")
	assert_true(g.flow in [g.Flow.INTRO, g.Flow.FIGHT], label + ": and the match starts")


## Runs the fight's clock down, whichever sim holds it, so a stalemate still ends.
func _hurry(g: Node) -> void:
	if g.flow != g.Flow.FIGHT:
		return
	if g.duel != null:
		g.duel.timer = mini(g.duel.timer, HURRY_LEFT)
	elif g.team_battle != null:
		var tb = g.team_battle
		if tb.overtime and _overtime_ticks >= OVERTIME_HURRY:
			# Capture the Flag's sudden death ends only on a capture, and CPUs can stall
			# in it for good: hand side 0 the lead and let the clock run out instead.
			tb.overtime = false
			tb.score[0] = int(tb.score[0]) + 1
			tb.timer = 1
		tb.timer = mini(tb.timer, HURRY_LEFT)
	elif g.brawl != null:
		g.brawl.timer = mini(g.brawl.timer, HURRY_LEFT)
	else:
		g.timer = mini(g.timer, HURRY_LEFT)


## Plays until the final banner and its menu. Returns the ticks it took (-1: never).
func _play_to_over(g: Node, label: String) -> int:
	var fought := 0
	for t in BUDGET:
		_tick(g, 1)
		if g.flow == g.Flow.FIGHT:
			fought += 1
			_overtime_ticks = _overtime_ticks + 1 if g.team_battle != null and g.team_battle.overtime else 0
			if fought >= HURRY_AT and fought % 60 == 0:
				_hurry(g)
		if g.flow == g.Flow.MATCH_OVER and g.ui.is_open():
			return t
	fail("%s never reached its final banner in %d ticks (flow %d)" % [label, BUDGET, g.flow])
	return -1


func _row_labels(scr: UiScreen) -> Array:
	var out: Array = []
	for c in scr.rows():
		if c is Button:
			out.append((c as Button).text)
	return out


## Pause > Quit > Yes.
func _quit_from_pause(g: Node, label: String) -> void:
	_press("pause")
	assert_true(g.ui.top() is PauseScreen, label + ": the pause menu")
	(g.ui.top().rows().back() as Control).grab_focus()
	_press("ui_accept")
	assert_true(g.ui.top() is ConfirmScreen, label + ": Quit asks first")
	_press("ui_up")  # Yes
	_press("ui_accept")


func _choices(g: Node, r: int) -> int:
	var row: Dictionary = g.MENU_ROWS[r]
	return (row["choices"] as Array).size() if row.has("choices") else 1


## Whether the row's mode plays to a final banner (else it is left from the pause menu).
func _ends(g: Node, r: int, choice: int) -> bool:
	var row: Dictionary = g.MENU_ROWS[r]
	if not row.has("modes"):
		return false
	var cfg: Dictionary = g.MODES[int(row["modes"][choice if not row.get("fighter_choice", false) else 0])]
	return not (cfg.get("training", false) or cfg.get("showcase", false) or cfg.get("trials", false)
		or cfg.has("drill"))


func _keep_daily() -> Array:
	var path := "user://daily/daily_%d.json" % Daily.today()
	if not FileAccess.file_exists(path):
		return [path, null]
	return [path, FileAccess.get_file_as_string(path)]


func _restore_daily(kept: Array) -> void:
	if kept[1] == null:
		DirAccess.remove_absolute(String(kept[0]))
		return
	var f := FileAccess.open(String(kept[0]), FileAccess.WRITE)
	f.store_string(String(kept[1]))
	f.close()


func test_every_row_plays_to_the_final_banner_and_back_lands_on_the_row() -> void:
	var kept := _keep_daily()
	var g := _game()
	var played := 0
	for r in g.MENU_ROWS.size():
		var row: Dictionary = g.MENU_ROWS[r]
		var label := String(row["label"])
		if not row.has("modes") or not _ends(g, r, 0):
			continue
		Progress.set_enabled(bool(row.get("progression", false)))  # the Weekly's row is there only with it on
		var page := _go_to_row(g, r, 0)
		var page_title: String = page.title
		var m := int(row["modes"][0])
		assert_eq(g.mode, m, label + ": the first choice's mode")
		_through_pick(g, label)
		var ticks := _play_to_over(g, label)
		if ticks < 0:
			g._open_menu()
			continue
		played += 1
		assert_true(g.hud.banner != "", label + ": a final banner")
		assert_true(g.hud.banner_sub != "", label + ": says why (" + g.hud.banner + ")")
		var labels := _row_labels(g.ui.top())
		assert_true(labels[0] in ["Rematch", "New run", "Play again", "Retry the stage"],
			label + ": the first choice plays again: " + str(labels))
		assert_eq(labels.back(), "Main menu", label + ": the last is Main menu: " + str(labels))
		if g._has_pick(g.MODES[m]):
			assert_true("Change fighters" in labels, label + ": a pick mode offers Change fighters: " + str(labels))
		else:
			assert_false("Change fighters" in labels, label + ": no pick, no Change fighters: " + str(labels))
		_press("ui_cancel")
		_assert_on_row(g, page_title, r, 0, label + " / Back")
		# Enter again on the row it landed on: the same mode, then leave from the pause menu.
		_press("ui_accept")
		assert_eq(g.mode, m, label + ": Enter on the landed row starts the same mode")
		_through_pick(g, label)
		_tick(g, 30)
		_quit_from_pause(g, label)
		_assert_on_row(g, page_title, r, 0, label + " / pause Quit")
	assert_gt(float(played), 12.0, "rows played to the end: %d" % played)
	Progress.set_enabled(false)
	g.free()
	_restore_daily(kept)


func test_every_other_choice_starts_its_mode_and_leaves_to_the_row() -> void:
	var g := _game()
	var started := 0
	for r in g.MENU_ROWS.size():
		var row: Dictionary = g.MENU_ROWS[r]
		var label := String(row["label"])
		if not row.has("modes"):
			continue
		Progress.set_enabled(bool(row.get("progression", false)))
		for choice in _choices(g, r):
			if choice == 0 and _ends(g, r, 0):
				continue  # played to the end by the other test
			var what := "%s [%s]" % [label, String(row["choices"][choice]) if row.has("choices") else "-"]
			var page := _go_to_row(g, r, choice)
			var page_title: String = page.title
			var m := int(row["modes"][0 if row.get("fighter_choice", false) else choice])
			assert_eq(g.mode, m, what + ": its mode")
			if row.get("fighter_choice", false):
				assert_eq(g._arcade_fighter, MatchFactory.FIGHTERS[choice], what + ": your fighter")
			_through_pick(g, what)
			_tick(g, 150)  # past the intro
			assert_true(g.flow in [g.Flow.INTRO, g.Flow.FIGHT], what + ": fighting (flow %d)" % g.flow)
			assert_true(g.sim != null and g.sim.creatures.size() >= 2, what + ": a match")
			if g.MODES[m].get("training", false):
				assert_eq(String(g.sim.creatures[0].def["id"]), MatchFactory.FIGHTERS[choice], what + ": training as")
			elif g.MODES[m].has("left") and not g.MODES[m].get("training", false):
				assert_eq(String(g.sim.creatures[0].def["id"]), String(g.MODES[m]["left"]), what + ": as")
			started += 1
			if g.showcase != null:
				_press("pause")  # a demo: straight back
			else:
				_quit_from_pause(g, what)
			_assert_on_row(g, page_title, r, choice, what + " / leave")
	assert_gt(float(started), 40.0, "choices started: %d" % started)
	Progress.set_enabled(false)
	g.free()


func test_replay_theater_opens_from_its_row_and_back_returns_to_it() -> void:
	var g := _game()
	var r := -1
	for i in g.MENU_ROWS.size():
		if String(g.MENU_ROWS[i]["label"]) == "Replay theater":
			r = i
	assert_true(r >= 0, "a Replay theater row")
	var page := _go_to_row(g, r, 0)
	assert_eq((g.ui.top() as UiScreen).title, "REPLAY THEATER", "its screen opens")
	_press("ui_cancel")
	_assert_on_row(g, page.title, r, 0, "Replay theater / Back")
	g.free()


func test_rematch_keeps_the_fighters_and_skips_the_pick() -> void:
	var g := _game()
	for label in ["Versus CPU", "Team battle vs CPU", "Brawl"]:
		var r := -1
		for i in g.MENU_ROWS.size():
			if String(g.MENU_ROWS[i]["label"]) == label:
				r = i
		_go_to_row(g, r, 0)
		var m: int = g.mode
		_through_pick(g, label)
		var ids: Array = []
		for c in g.sim.creatures:
			ids.append(String(c.def["id"]))
		assert_true(_play_to_over(g, label) >= 0, label + ": over")
		(g.ui.top().rows()[0] as Control).grab_focus()
		assert_eq((_focus() as Button).text, "Rematch", label + ": Rematch first")
		_press("ui_accept")
		assert_eq(g.mode, m, label + ": the same mode")
		assert_false(g.ui.top() is CharacterSelect, label + ": no pick screen")
		assert_true(g.flow in [g.Flow.INTRO, g.Flow.FIGHT], label + ": straight into the match")
		var again: Array = []
		for c in g.sim.creatures:
			again.append(String(c.def["id"]))
		assert_eq(again, ids, label + ": the same fighters")
		g._open_menu()
	g.free()
