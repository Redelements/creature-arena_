extends TestCase
## Settings > Credits, driven like a player: the title, Settings, the Credits card. The
## page credits the people (data/credits.json), the bought art (Szadi art, kiddolink), the m5x7 font and Godot
## Engine with its copyright lines straight from the engine; Godot's row opens its licence
## and the notices row the third-party notices, on a page that scrolls with Up/Down and
## closes with Back. That the pages fit every screen: tests/test_ui_fit.gd (its PAGES).

const TEST_SETTINGS := "user://test_credits.cfg"


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
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	return g


## Title > Settings > Credits, by key presses.
func _open_credits(g: Node) -> CreditsScreen:
	g._open_menu()
	assert_true(g.ui.top() is TitleScreen, "the title")
	((g.ui.top() as TitleScreen)._rows_by_name["settings"] as Control).grab_focus()  # (by name: the Profile row comes and goes)
	_press("ui_accept")
	assert_eq(g.ui.top().title, "SETTINGS", "Settings opened")
	for i in 8:
		if _focus() is Button and (_focus() as Button).text == "Credits":
			break
		_press("ui_down")
	assert_eq((_focus() as Button).text, "Credits", "the Credits card")
	_press("ui_accept")
	assert_true(g.ui.top() is CreditsScreen, "Credits opened")
	return g.ui.top() as CreditsScreen


func _all_text(scr: UiScreen) -> String:
	var out := PackedStringArray([scr.blurb])
	for r in scr.rows():
		out.append(scr._row_title(r))
		out.append(String(scr._descriptions.get(r, "")))
	return "\n".join(out)


func test_credits_open_from_the_title_and_credit_everyone() -> void:
	var g := _game()
	var scr := _open_credits(g)
	var text := _all_text(scr)
	for want in ["Kevin Winstead", "Redelements", "Jake Johnston", "Dirknasty", "Justin Brown", "Cyanical",
			"Anthony Smith", "Cheffy916", "Lead Combat Designer", "Head of Growth", "drew the fighters by hand",
			"BillCrittin", "David Taylor", "Broobs", "Szadi art", "szadiart.itch.io", "kiddolink", "VFX Complete Set Season 1",
			"m5x7", "Daniel Linssen", "Godot Engine", "MIT"]:
		assert_true(text.contains(want), "the page says " + want)
	var lines := CreditsScreen.godot_copyright()
	assert_true(lines.size() >= 2, "Godot's licence has its copyright lines: %s" % [lines])
	for l in lines:
		assert_true(text.contains(l), "the page shows Godot's copyright: " + l)
	assert_true(String(lines[0]).contains("Godot Engine contributors"), String(lines[0]))
	assert_false(text.contains("generators"), "the fighters aren't credited to the generators")
	# Focus walks every row, the people then the rest, and the panel follows.
	var want := []
	for p in CreditsScreen.people():
		want.append(String(p["name"]))
	want.append_array(["Szadi art", "kiddolink", "m5x7 font", "Godot Engine", "Third-party notices", "Back"])
	assert_eq(_focus(), scr.row("kevin"), "the first row is the first of the team")
	assert_eq(scr._detail_title.text, "Kevin Winstead", "the panel names the focused row")
	assert_true(scr._desc.text.contains("Benevolent Dictator"), scr._desc.text)
	for i in range(1, want.size()):
		_press("ui_down")
		assert_eq((_focus() as Button).text, want[i], "Down reaches " + String(want[i]))
	for i in range(want.size() - 1):
		_press("ui_up")
	assert_eq(_focus(), scr.row("kevin"), "Up walks back to the top")
	scr.row("szadi").grab_focus()
	assert_eq(scr._detail_title.text, "Szadi art", "the panel follows the focus")
	assert_true(scr._desc.text.contains("szadiart.itch.io"), scr._desc.text)
	_press("ui_cancel")
	assert_eq(g.ui.top().title, "SETTINGS", "Back to Settings")
	assert_eq((_focus() as Button).text, "Credits", "on Credits")
	g.free()


func test_godot_and_the_notices_open_full_pages_that_scroll() -> void:
	var g := _game()
	var scr := _open_credits(g)
	scr.row("godot").grab_focus()
	_press("ui_accept")
	var page := g.ui.top() as TextPage
	assert_true(page != null, "Godot Engine opens a page")
	assert_true(page.body.contains(Engine.get_license_text()), "the full MIT licence")
	_press("ui_cancel")
	assert_true(g.ui.top() is CreditsScreen, "Back to Credits")
	assert_eq(_focus(), scr.row("godot"), "on the same row")

	scr.row("notices").grab_focus()
	_press("ui_accept")
	page = g.ui.top() as TextPage
	assert_true(page != null, "the notices open a page")
	var info := Engine.get_license_info()
	for key in info:
		assert_true(page.body.contains("--- %s ---" % key), "the %s licence text" % key)
	for comp in Engine.get_copyright_info():
		assert_true(page.body.contains(String(comp["name"])), "names " + String(comp["name"]))
	assert_eq(_focus(), page.text_box, "the text has the focus")
	# Lay it out so the scroll bar knows its range, then scroll by key.
	for i in 3:
		for c in [page, page._col]:
			(c as Control).notification(Container.NOTIFICATION_SORT_CHILDREN)
	page.text_box.size = page.text_box.custom_minimum_size
	page.text_box.notification(Control.NOTIFICATION_RESIZED)
	var bar := page.text_box.get_v_scroll_bar()
	var was := bar.value
	_press("ui_down")
	_press("ui_down")
	assert_true(bar.value > was, "Down scrolls the text (%s -> %s, max %s)" % [was, bar.value, bar.max_value])
	assert_eq(_focus(), page.text_box, "and keeps the focus there")
	var mid := bar.value
	_press("ui_up")
	assert_true(bar.value < mid, "Up scrolls back")
	_press("ui_cancel")
	assert_true(g.ui.top() is CreditsScreen, "Back to Credits")
	g.free()
