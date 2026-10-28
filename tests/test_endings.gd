extends TestCase
## Arcade ending cards (src/game/endings.gd, src/ui/ending_screen.gd, data/endings/): every
## fighter has an ending file with the keys the card reads, short lines and an art file that
## exists; the card builds for each; with Progression on a headless Arcade clear shows the card
## before the results, marks the ending seen, grants its title and still reaches the results
## (Continue or Back); the Profile's Endings gallery greys the unseen ones and opens the seen
## ones; Off, the clear goes straight to the results as before and nothing is marked.

const TEST_SETTINGS := "user://test_endings.cfg"

var _save := ""


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _fresh() -> void:
	_save = "user://test_endings_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(_save)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save))


func _done(g: Node) -> void:
	if g != null:
		g.free()
	Progress.set_enabled(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save))
	Progress.reset_for_tests(Progress.PATH)


func _game(on: bool) -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	Progress.set_enabled(on)  # (set after the settings load, never left to its default)
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


## The Arcade's boss falls (as tests/test_ui.gd's clear does), then the match-over beat runs.
func _clear(g: Node, fighter: String) -> void:
	g._arcade_fighter = fighter
	g._skip_select = true
	g._start_match(g.mode_index("Arcade"))
	g.arcade.stage = Arcade.STAGES - 1
	g._start_arcade_stage()
	_tick(g, 10)
	assert_true(g._arcade_result(true), "the boss falls")
	g.flow_t = 0
	_tick(g, g.MATCH_OVER_MENU_AT + 1)


func _labels(scr: UiScreen) -> Array:
	var out: Array = []
	for r in scr.rows():
		out.append((r as OptionRow).label if r is OptionRow else (r as Button).text)
	return out


func test_every_fighter_has_an_ending_with_its_keys_and_art() -> void:
	assert_eq(Endings.fighters(), MatchFactory.FIGHTERS, "one ending a fighter, the roster's order")
	var titles := {}
	for f in MatchFactory.FIGHTERS:
		var e := Endings.of(String(f))
		assert_false(e.is_empty(), "%s has data/endings/%s.json" % [f, f])
		for k in Endings.KEYS:
			assert_true(e.has(k), "%s's ending has '%s'" % [f, k])
		assert_true(String(e.get("title", "")) != "", "%s: a title" % f)
		var lines: Array = e.get("lines", [])
		assert_true(lines.size() >= 3 and lines.size() <= 5, "%s: three to five lines, not %d" % [f, lines.size()])
		for l in lines:
			assert_true(String(l).length() < 60, "%s: a line under 60 characters for phones: '%s'" % [f, l])
		var art := String(e.get("art", ""))
		assert_true(art.begins_with("res://assets/ui/endings/") and ResourceLoader.exists(art), "%s: the art exists: %s" % [f, art])
		assert_true(Endings.art(String(f)) != null, "%s: the art loads" % f)
		var t := String(e.get("unlock_title", ""))
		if t != "":
			assert_true(t.begins_with("title:"), "%s: the reward is a title" % f)
			assert_true(Progress.title_text(t) != t.trim_prefix("title:"), "%s: '%s' has words in progression.json" % [f, t])
			assert_false(titles.has(t), "%s: its own title" % f)
			titles[t] = true
			assert_eq(Endings.fighter_of_reward(t), String(f), "")


func test_the_card_builds_for_every_fighter() -> void:
	_fresh()
	var g := _game(true)
	for f in MatchFactory.FIGHTERS:
		var scr := EndingScreen.new(String(f), true)
		g.ui.push(scr)
		assert_eq(scr.title, String(Endings.of(String(f))["title"]).to_upper(), "")
		assert_true(scr.find_child("Art", true, false) is TextureRect, "%s: the art is on the card" % f)
		assert_eq(_labels(scr), ["Continue"], "%s: one row" % f)
		var said: Array = scr.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
		for line in Endings.of(String(f))["lines"]:
			assert_true(said.has(String(line)), "%s: '%s' is on the card" % [f, line])
		scr.continue_button.pressed.emit()  # from the gallery: Continue closes it
		assert_true(g.ui.top() != scr, "%s: closed" % f)
	assert_false(Progress.ending_seen("cairn"), "looking at a card from the gallery marks nothing")
	_done(g)


func test_an_arcade_clear_shows_the_card_marks_it_and_reaches_the_results() -> void:
	_fresh()
	var g := _game(true)
	_clear(g, "sno")
	var top: UiScreen = g.ui.top()
	assert_true(top is EndingScreen, "the card comes up where the results would: %s" % [top])
	assert_eq((top as EndingScreen).fighter, "sno", "")
	assert_true(Progress.ending_seen("sno"), "seen as it shows")
	assert_false(Progress.ending_seen("cairn"), "only the fighter that cleared")
	assert_true(Progress.unlocked("title:sno_ending"), "its title is granted")
	(top as EndingScreen).continue_button.pressed.emit()
	top = g.ui.top()
	assert_false(top is EndingScreen, "Continue: the card is gone")
	var labels := _labels(top)
	assert_true("New run" in labels and not ("Retry the stage" in labels), "the results after a clear: %s" % [labels])
	# A second clear shows the card again (it's the ending), Back goes on to the results too.
	g._open_menu()
	_clear(g, "sno")
	assert_true(g.ui.top() is EndingScreen, "the card again on the next clear")
	g.ui.top().back()
	assert_true("New run" in _labels(g.ui.top()), "Back: the results")
	_done(g)


func test_off_the_clear_goes_straight_to_the_results() -> void:
	_fresh()
	var g := _game(false)
	_clear(g, "sno")
	var top: UiScreen = g.ui.top()
	assert_false(top is EndingScreen, "no card while Progression is off")
	var labels := _labels(top)
	assert_true("New run" in labels and not ("Retry the stage" in labels), "the results as before: %s" % [labels])
	assert_false(Progress.ending_seen("sno"), "nothing marked")
	assert_false(Progress.unlocked("title:sno_ending"), "nothing granted")
	assert_false(Endings.show("sno"), "show() does nothing while off")
	g._open_menu("ending:sno")
	assert_false(g.ui.top() is EndingScreen, "--menu=ending: needs Progression on")
	_done(g)


func test_the_gallery_greys_unseen_endings_and_opens_seen_ones() -> void:
	_fresh()
	Progress.set_enabled(true)
	assert_true(Endings.show("pete"), "the first showing")
	assert_false(Endings.show("pete"), "once")
	var g := _game(true)
	g._open_menu("profile")
	var hub: UiScreen = g.ui.top()
	var row: OptionRow = null
	for r in hub.rows():
		if r is OptionRow and (r as OptionRow).label == "Endings":
			row = r
	assert_true(row != null, "the Profile has an Endings row")
	assert_eq(row.value_text(), "1 / %d" % MatchFactory.FIGHTERS.size(), "")
	g._open_menu("profile:endings")
	var gal := g.ui.top() as ProfileScreen
	assert_true(gal != null and gal.page == "endings", "--menu=profile:endings opens the gallery")
	assert_eq(gal.ending_rows.size(), MatchFactory.FIGHTERS.size(), "a row a fighter")
	for f in MatchFactory.FIGHTERS:
		var o: OptionRow = gal.ending_rows[String(f)]
		var seen := String(f) == "pete"
		assert_eq(bool(o.locked[0]), not seen, "%s: greyed unless seen" % f)
		assert_eq(o.activates, seen, "%s: opens only when seen" % f)
		if not seen:
			assert_eq(o.get_theme_color("font_color"), UiTheme.C_DIM, "%s: its name greyed too" % f)
			assert_true(String(gal._descriptions[o]).contains("Clear the Arcade as"), "%s says how" % f)
	(gal.ending_rows["pete"] as OptionRow).activated.emit()
	assert_true(g.ui.top() is EndingScreen and (g.ui.top() as EndingScreen).fighter == "pete", "Enter: the card again")
	g.ui.top().back()
	assert_true(g.ui.top() == gal, "Back: the gallery")
	g._open_menu("ending:crease")
	assert_true(g.ui.top() is EndingScreen and (g.ui.top() as EndingScreen).fighter == "crease",
		"--menu=ending:<fighter> opens one card (even unseen: captures)")
	# The ending's title is offered on the fighter's page.
	g._open_menu("profile:pete")
	var picker: OptionRow = null
	for r in g.ui.top().rows():
		if r is OptionRow and (r as OptionRow).label == "Title":
			picker = r
	assert_true(picker != null and picker.values.has(Progress.title_text("title:pete_ending")), "Pete's page offers his ending title")
	assert_true(Progress.set_equipped("pete", "title", "title:pete_ending"), "and it can be worn")
	_done(g)


func test_an_old_save_without_endings_loads() -> void:
	_fresh()
	var f := FileAccess.open(_save, FileAccess.WRITE)
	f.store_string(JSON.stringify({"xp": 120, "arcade": {"cairn": 1}}))
	f.close()
	Progress.reset_for_tests(_save)
	assert_false(Progress.ending_seen("cairn"), "no endings key: none seen")
	assert_eq(Progress.account_xp(), 120, "the rest still loads")
	Progress.set_enabled(true)
	assert_true(Progress.see_ending("cairn"), "")
	Progress.reset_for_tests(_save)
	assert_true(Progress.ending_seen("cairn"), "saved")
	_done(null)
