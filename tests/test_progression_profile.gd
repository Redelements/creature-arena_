extends TestCase
## The Profile (src/ui/profile_screen.gd; title menu > Profile with Settings > Game >
## Progression on): it builds from an empty save and from a full one (every reward
## unlocked), on every page; its pickers wear unlocked rewards and refuse locked ones
## (and so does Progress); the title and victory line worn reach the results data and the
## pick screen; the "New!" marks clear once the page is opened; and the Profile row is
## absent with Progression off, present with it on. Phone fit: tests/test_ui_fit.gd.

const TEST_SETTINGS := "user://test_progression_profile.cfg"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


var _save := ""


func _fresh() -> void:
	_save = "user://test_profile_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(_save)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save))


func _done() -> void:
	Progress.set_enabled(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save))
	Progress.reset_for_tests(Progress.PATH)


func _game(on := true) -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	Progress.set_enabled(on)  # (after the settings load, which reads it Off)
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


## Every reward unlocked: the account and every fighter past their caps, paid once.
func _fill() -> void:
	Progress.set_enabled(true)
	Progress._ensure()
	Progress._data["xp"] = 10000000
	for f in MatchFactory.FIGHTERS:
		Progress._data["mastery"][String(f)] = 10000000
	Progress.award({"kind": "cpu", "cpu_level": 1, "players": [
		{"slot": 0, "fighters": MatchFactory.FIGHTERS.duplicate(), "won": true, "kos": 0}]})
	for id in Challenges.titles():  # and the challenges' titles
		Progress.grant_unlock(String(id))


func _row(scr: UiScreen, label: String) -> OptionRow:
	for r in scr.rows():
		if r is OptionRow and (r as OptionRow).label == label:
			return r
	return null


func _labels(scr: UiScreen) -> Array:
	var out: Array = []
	for r in scr.rows():
		out.append((r as OptionRow).label if r is OptionRow else (r as Button).text)
	return out


func _pages(g: Node) -> void:
	g._open_menu("profile")
	var top: UiScreen = g.ui.top()
	assert_true(top is ProfileScreen, "the Profile opens")
	var labels := _labels(top)
	assert_eq(labels.size(), 2 + MatchFactory.FIGHTERS.size() + 1, "Account, Challenges, a row per fighter, Back: %s" % [labels])
	assert_eq(labels[0], "Account", "")
	assert_eq(labels[1], "Challenges", "")
	g._open_menu("profile:challenges")
	assert_true(g.ui.top() is ProfileScreen and (g.ui.top() as ProfileScreen).page == "challenges", "the Challenges page opens")
	g.ui.top().back()
	assert_eq(labels.back(), "Back", "")
	for page in ["account"] + MatchFactory.FIGHTERS:
		g._open_menu("profile:" + String(page))
		top = g.ui.top()
		assert_true(top is ProfileScreen and (top as ProfileScreen).page == String(page), "%s's page opens" % page)
		assert_true(_row(top, "Title") != null, "%s has a title picker" % page)
		if String(page) != "account":
			assert_true(_row(top, "Palette") != null and _row(top, "Victory line") != null, "and palettes and lines")
		top.back()
		assert_true(g.ui.top() is ProfileScreen and (g.ui.top() as ProfileScreen).page == "", "Back: the Profile")


func test_the_profile_builds_from_an_empty_save_and_a_full_one() -> void:
	_fresh()
	var g := _game()
	_pages(g)
	# The empty save: level 1, mastery 1, nothing to wear but the first palette and None.
	g._open_menu("profile:cairn")
	var pal := _row(g.ui.top(), "Palette")
	assert_eq(pal.values.size(), Progress.PALETTES, "every palette listed:")
	assert_eq(pal.locked, [false, true, true, true], "only the first one is yours:")
	assert_true(String(pal.values[1]).contains("Mastery 2"), "a locked one says the level it needs: %s" % pal.values[1])
	assert_eq(_row(g.ui.top(), "Title").locked.count(false), 1, "of the titles only None:")
	g.free()
	_fill()
	g = _game()
	_pages(g)
	g._open_menu("profile:cairn")
	assert_eq(_row(g.ui.top(), "Palette").locked, [false, false, false, false], "full: every palette:")
	assert_eq(_row(g.ui.top(), "Title").locked.count(true), 0, "every title:")
	assert_eq(_row(g.ui.top(), "Victory line").locked.count(true), 0, "every line:")
	g.free()
	_done()


func test_the_pickers_wear_unlocked_rewards_and_refuse_locked_ones() -> void:
	_fresh()
	Progress.set_enabled(true)
	# Mastery 2 on Cairn: palette 2 is Cairn's, palette 3 isn't.
	Progress._ensure()
	Progress._data["mastery"]["cairn"] = Progress.xp_for_level(Progress.table()["mastery_curve"], 3)
	Progress.award({"kind": "cpu", "cpu_level": 1, "players": [{"slot": 0, "fighters": ["cairn"], "won": false, "kos": 0}]})
	assert_true(Progress.unlocked("line:cairn_1") and not Progress.unlocked("line:cairn_2"), "mastery 3: the first line only")
	var g := _game()
	g._open_menu("profile:cairn")
	var pal := _row(g.ui.top(), "Palette")
	pal.step(1)
	assert_eq(Progress.palette("cairn"), 1, "an unlocked palette is worn:")
	pal.step(1)
	assert_eq(Progress.palette("cairn"), 1, "a locked one is only looked at:")
	var lines := _row(g.ui.top(), "Victory line")
	lines.step(1)
	assert_eq(String(Progress.equipped("cairn")["line"]), "line:cairn_1", "the unlocked line is worn:")
	lines.step(1)
	assert_eq(String(Progress.equipped("cairn")["line"]), "line:cairn_1", "the locked one is refused:")
	var titles := _row(g.ui.top(), "Title")
	titles.step(1)
	assert_eq(String(Progress.equipped("cairn")["title"]), "", "Cairn Master is locked:")
	g.free()
	assert_false(Progress.set_equipped("cairn", "title", "title:legend"), "Progress refuses a locked title")
	assert_false(Progress.set_account_title("title:legend"), "for the account too")
	assert_false(Progress.set_account_title("line:cairn_1"), "and a line as a title")
	Progress._data["xp"] = Progress.xp_for_level(Progress.table()["account_curve"], 2)
	Progress.award({"kind": "cpu", "cpu_level": 1, "players": [{"slot": 0, "fighters": ["cairn"], "won": false, "kos": 0}]})
	assert_true(Progress.set_account_title("title:rookie"), "an unlocked account title is worn")
	assert_eq(Progress.shown_title("digby"), "Rookie Rambler", "by a fighter without its own:")
	g = _game()
	g._open_menu("profile:account")
	assert_eq(_row(g.ui.top(), "Title").index, 1, "the account page shows it worn:")
	_row(g.ui.top(), "Title").step(-1)
	assert_eq(Progress.account_title(), "", "None takes it off:")
	g.free()
	_done()


func test_the_title_and_line_worn_reach_the_results_and_the_pick_screen() -> void:
	_fresh()
	_fill()
	assert_true(Progress.set_equipped("cairn", "title", "title:cairn_master"), "")
	assert_true(Progress.set_equipped("cairn", "line", "line:cairn_2"), "")
	assert_true(Progress.set_account_title("title:legend"), "")
	for won in [true, false]:
		var g := _game()
		g._skip_select = true
		g._start_match(0)  # Cairn vs CPU Culvert
		_tick(g, 30)
		g.wins = [2, 0] if won else [0, 2]
		var d: Dictionary = g.results_data()
		if won:
			assert_eq(d["badge"], Progress.title_text("title:cairn_master"), "the winner's title:")
			assert_eq(d["line"], Progress.line_text("line:cairn_2"), "and their line:")
		else:
			assert_eq(d["badge"], "", "a loss: no title")
			assert_eq(d["line"], "", "and no line")
		Progress.set_enabled(false)
		d = g.results_data()
		assert_eq([d["badge"], d["line"]], ["", ""], "Off: neither:")
		Progress.set_enabled(true)
		g.free()
	# The panel shows them.
	var panel := ResultsPanel.new({"title": "CAIRN WINS!", "badge": "Cairn Master", "line": "Cairn takes a bow.", "rows": []})
	assert_true(panel.find_child("Badge", true, false) != null and panel.find_child("VictoryLine", true, false) != null, "the panel draws both")
	panel.free()
	# The pick screen: player 1's title for the fighter under the cursor (the account's
	# where the fighter wears none).
	var g := _game()
	g._start_match(6)  # Duel vs CPU: the pick screen
	var pick := g.ui.top() as CharacterSelect
	assert_true(pick != null, "the pick screen")
	pick.cursor[0] = pick.roster.find("cairn")
	assert_eq(pick.side_title(0), Progress.title_text("title:cairn_master"), "Cairn's own:")
	pick.cursor[0] = pick.roster.find("digby")
	assert_eq(pick.side_title(0), "Rambles Legend", "Digby wears the account's:")
	assert_eq(pick.side_title(1), "", "the CPU wears none:")
	g.free()
	g = _game(false)
	g._start_match(6)
	assert_eq((g.ui.top() as CharacterSelect).side_title(0), "", "Off: no titles")
	g.free()
	_done()


func test_new_marks_clear_once_the_page_is_seen() -> void:
	_fresh()
	Progress.set_enabled(true)
	assert_false(Progress.new_anywhere(), "an empty save: nothing new")
	Progress._ensure()
	Progress._data["mastery"]["sno"] = Progress.xp_for_level(Progress.table()["mastery_curve"], 2)
	Progress.award({"kind": "cpu", "cpu_level": 1, "players": [{"slot": 0, "fighters": ["sno"], "won": false, "kos": 0}]})
	assert_eq(Progress.new_of("sno"), ["palette:sno:1"], "mastery 2: a new palette")
	var g := _game()
	g._open_menu()
	var title: TitleScreen = g.ui.top()
	assert_eq(title._rows_by_name["profile"].text, "Profile   New!", "the title says so:")
	g._open_menu("profile")
	title = g.ui.screens[0]  # (a new title under the Profile)
	var sno: OptionRow = _row(g.ui.top(), ProfileScreen._name("sno"))
	assert_true(sno != null, "Sno's row")
	if sno != null:
		assert_eq(sno.tag, "New!", "and Sno's row:")
	assert_eq(_row(g.ui.top(), ProfileScreen._name("cairn")).tag, "", "not Cairn's:")
	g._open_profile("sno")
	assert_eq(Progress.new_of("sno"), [], "seen:")
	g.ui.top().back()
	if sno != null:
		assert_eq(sno.tag, "", "Sno's row no longer says New:")
	g.ui.top().back()
	assert_eq(title._rows_by_name["profile"].text, "Profile", "nor does the title:")
	g.free()
	# A fresh read keeps what was seen.
	Progress._loaded = false
	assert_eq(Progress.new_of("sno"), [], "saved:")
	_done()


func test_the_profile_row_is_there_only_with_progression_on() -> void:
	_fresh()
	var g := _game(false)
	g._open_menu()
	assert_false("Profile" in _labels(g.ui.top()), "Off: no Profile row")
	g._open_profile()
	assert_true(g.ui.top() is TitleScreen, "and it doesn't open")
	g._open_menu("profile")
	assert_true(g.ui.top() is TitleScreen, "not even from --menu=profile")
	# Turning it on in Settings shows the row on the way back.
	g._open_menu("game")
	Progress.set_enabled(true)
	g.ui.top().back()
	g.ui.top().back()
	assert_true(g.ui.top() is TitleScreen, "back on the title")
	assert_eq(_labels(g.ui.top()), ["Single player", "Online", "Profile", "Settings", "Exit"], "On: the Profile row, by Settings:")
	g.free()
	g = _game(true)
	g._open_menu()
	assert_true("Profile" in _labels(g.ui.top()), "On from the start: there too")
	g.free()
	_done()
