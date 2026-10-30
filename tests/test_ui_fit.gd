extends TestCase
## Every menu page fits the screen at the sizes phones, handhelds and PCs have: 16:9
## (1920 x 1080, the Odin 3; 1440 x 810), 20:9 and 19.5:9 phones, 16:10 and a 4:3 tablet.
## The window is scaled the way main.gd's _apply_pixel_scale scales it (whole screen
## pixels per canvas unit), then each page is checked: nothing visible leaves the screen
## (a column too tall for it scrolls, so its rows are judged by the scroll box), no text
## is wider than its box (rows, labels, the panel's cards' facts), and the key hints at
## the foot don't sit on the page. Since Oct 2026: Settings > Video ran off a 1080p
## screen and Team battles' facts ran past the panel, both hidden on a 1440p monitor.
## Progression's pages too (`PROFILE_PAGES`, with every reward unlocked so the longest
## titles and lines show), and the winner's title and victory line on the results.

const MAIN := preload("res://src/game/main.gd")
const TEST_SETTINGS := "user://test_ui_fit.cfg"
const SIZES := [Vector2i(1920, 1080), Vector2i(1440, 810), Vector2i(2400, 1080), Vector2i(2340, 1080),
	Vector2i(1280, 800), Vector2i(2048, 1536)]
const PAGES := ["main", "single", "look", "settings", "game", "video", "audio", "accessibility", "controls",
	"remap:classic", "remap:league", "remap:gamepad", "credits", "credits:justin", "credits:godot", "credits:notices"]
## The Profile's pages (Settings > Game > Progression on): the Profile, the account's and
## every fighter's; and the Single player hub (its today card) and Challenges (the Weekly's row).
const PROFILE_PAGES := ["main", "profile", "profile:account", "profile:challenges", "profile:endings", "ending:cairn", "ending:gillbert", "ending:crease", "profile:cairn", "profile:culvert", "profile:craglash",
	"profile:barkley", "profile:gillbert", "profile:cerebro", "profile:hissy", "profile:digby", "profile:pete",
	"profile:sno", "profile:crease", "single", "single:challenge"]

var _was_size := Vector2i.ZERO
var _was_scale := 2.0


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


## The window at `size`, scaled as main scales a real one.
func _screen(size: Vector2i) -> void:
	var r := _root()
	if _was_size == Vector2i.ZERO:
		_was_size = r.size
		_was_scale = r.content_scale_factor
	r.size = size
	r.content_scale_factor = MAIN.pixel_scale_factor(Vector2(size), Vector2(r.content_scale_size))


func _restore() -> void:
	if _was_size != Vector2i.ZERO:
		_root().size = _was_size
		_root().content_scale_factor = _was_scale


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


## Lay the page out now (containers sort on a deferred call, which a test never reaches):
## top down, a few passes, since a scroll box sizes itself from what its parent got.
func _layout(n: Node) -> void:
	for pass_i in 3:
		_sort(n)


func _sort(n: Node) -> void:
	if n is Container:
		(n as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c in n.get_children():
		_sort(c)


func _text_w(c: Control, text: String) -> float:
	var font := c.get_theme_font("font")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, c.get_theme_font_size("font_size")).x


## Every way `scr` (the top screen) fails to fit, as lines.
func _misfits(scr: Control) -> Array:
	var out: Array = []
	var vis := _root().get_visible_rect().grow(0.5)
	_walk(scr, vis, out)
	# The hints at the foot against the page's frame and rows.
	var hint: Label = scr.get("_hint") if scr is UiScreen else null
	if hint != null and hint.is_visible_in_tree() and hint.text != "":
		var hr := hint.get_global_rect()
		var w := _text_w(hint, hint.text)
		var text_r := Rect2(hr.get_center().x - w * 0.5, hr.position.y + 2, w, hr.size.y - 4)
		for c in _boxes(scr):
			if text_r.intersects((c as Control).get_global_rect()):
				out.append("the hints overlap %s" % _name(c))
				break
	return out


## The page's frames and rows: what the hints mustn't cover.
func _boxes(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			if c is PanelContainer or c is ScrollContainer or c is BaseButton:
				out.append(c)
				continue
			out.append_array(_boxes(c))
	return out


func _walk(n: Node, vis: Rect2, out: Array) -> void:
	for ch in n.get_children():
		if not (ch is Control) or not (ch as Control).is_visible_in_tree():
			continue
		var c := ch as Control
		var r := c.get_global_rect()
		r.size = r.size.max(c.get_combined_minimum_size())  # a Label set this tick hasn't grown yet
		if r.size.x > 0.0 and r.size.y > 0.0 and not vis.encloses(r):
			out.append("%s leaves the screen: %s in %s" % [_name(c), r, vis])
		if c is Button and not (c is OptionRow) and not (c is CardButton) and (c as Button).text != "":
			var b := c as Button
			var sb := b.get_theme_stylebox("normal")
			if _text_w(b, b.text) + sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) > r.size.x + 1.0:
				out.append("%s's text is wider than the row" % _name(c))
		elif c is Label and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF and (c as Label).text != "" \
				and not (c as Label).text.contains("\n"):
			var w := _text_w(c, (c as Label).text)
			if w > r.size.x + 1.0:
				out.append("%s is wider than its box (%d > %d)" % [_name(c), w, r.size.x])
		elif c is DetailCard:
			for f in (c as DetailCard).facts:
				var room := r.size.x - 8
				var font := DetailCard.fit_font(UiTheme.font(), String(f), DetailCard.FONT_FACT, room)
				if font.get_string_size(String(f), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(DetailCard.FONT_FACT)).x > room + 1.0:
					out.append("the card's fact '%s' runs past the panel" % f)
		if c is ScrollContainer:
			continue  # its rows scroll into view: the box is what has to fit
		_walk(c, vis, out)


func _name(c: Control) -> String:
	var t := ""
	if c is OptionRow:
		t = (c as OptionRow).label
	elif c is Button:
		t = (c as Button).text
	elif c is Label:
		t = (c as Label).text
	var kind: String = c.get_class()
	if c.get_script() != null and String(c.get_script().get_global_name()) != "":
		kind = String(c.get_script().get_global_name())
	return "%s '%s'" % [kind, t.left(30)]


func _check(g: Node, size: Vector2i, what: String) -> void:
	var scr: Control = g.ui.top()
	assert_true(scr != null, what + " is open")
	if scr == null:
		return
	_layout(g.ui)
	var bad := _misfits(scr)
	assert_true(bad.is_empty(), "%s at %d x %d: %s" % [what, size.x, size.y, "; ".join(PackedStringArray(bad.slice(0, 4)))])


func test_every_menu_page_fits_every_screen() -> void:
	for size in SIZES:
		_screen(size)
		var g := _game()
		var pages: Array = PAGES.duplicate()
		for group in g.MENU_GROUPS:
			pages.append("single:" + String(group["id"]))
		for page in pages:
			g._open_menu(page)
			_check(g, size, page)
		g.free()
	_restore()


func test_the_fight_screens_fit_every_screen() -> void:
	var training := -1
	for i in MAIN.MODES.size():
		if MAIN.MODES[i].get("training", false) and training < 0:
			training = i
	for size in SIZES:
		_screen(size)
		var g := _game()
		g._start_match(6)  # Duel vs CPU: the character select
		_check(g, size, "character select")
		g._start_match(2)  # CPU vs CPU
		_tick(g, 5)
		_press("pause")
		_check(g, size, "pause")
		g.free()
		g = _game()
		g._start_match(training)
		_tick(g, 5)
		g._open_pause()
		_check(g, size, "training pause")
		g._open_training_options()
		_check(g, size, "training options")
		g._open_fighter_swap()
		_check(g, size, "change fighter")
		g.free()
	_restore()


func test_the_results_and_online_screens_fit_every_screen() -> void:
	for size in SIZES:
		_screen(size)
		var g := _game()
		g._start_match(2)
		_tick(g, 30)
		g.sim.creatures[1].hp = 0.0
		g.sim.creatures[1].state = CreatureSim.State.KO
		g.flow = g.Flow.MATCH_OVER
		g.flow_t = 0
		g.hud.banner = "CAIRN WINS!"
		# Progression's rows at their longest: XP and a level-up, two mastery-ups, unlocks
		Progress.set_enabled(true)
		g._progress_for = g.sim.get_instance_id()
		g._progress_shown = {"xp": 1234, "level_from": 29, "level_to": 30, "unlocked":
			["title:crowd_favourite", "line:crease_2", "palette:crease:3"], "mastery": {
			"crease": {"xp": 600, "from": 9, "to": 10}, "cerebro": {"xp": 600, "from": 5, "to": 6}}}
		g._challenges_shown = ["ko_500"]  # and a challenge's row
		_tick(g, g.MATCH_OVER_MENU_AT + 1)
		Progress.set_enabled(false)
		assert_eq((_find_results(g.ui.top()) as ResultsPanel).data["progress"].size(), 4, "the rows are there:")
		_check(g, size, "results")
		g._open_menu()
		var lobby := OnlineLobby.new("digby", "", ["game.example.net/kev"], "game.example.net")
		g.ui.push(lobby)
		for p in [OnlineLobby.Page.MAIN, OnlineLobby.Page.QUICK, OnlineLobby.Page.ROOMS, OnlineLobby.Page.MORE]:
			lobby.open_page(p)
			_check(g, size, "online page %d" % p)
		g.ui.push(ReadyCheck.new("Quick match 2 v 2", "digby"))
		_check(g, size, "ready check")
		g.free()
	_restore()


## Every reward unlocked (the longest words show), in a save of the test's own; the
## Challenges page part done (goals done in most groups: their ticks and "Done").
func _full_progress() -> String:
	var p := "user://test_ui_fit_progress_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(p)
	Progress.set_enabled(true)
	Progress._ensure()
	Progress._data["xp"] = 10000000
	for f in MatchFactory.FIGHTERS:
		Progress._data["mastery"][String(f)] = 10000000
	Progress.award({"kind": "cpu", "cpu_level": 1, "players": [
		{"slot": 0, "fighters": MatchFactory.FIGHTERS.duplicate(), "won": true, "kos": 0}]})
	for id in Challenges.titles() + Endings.titles():
		Progress.grant_unlock(String(id))
	# The Challenges page with goals done in every group (ticks, "Done"), the rest under way.
	Challenges.note_match({"kind": "cpu", "cpu_level": 3, "clear_arcade": true, "waves": 3, "players": [
		{"slot": 0, "fighters": ["crease"], "won": true, "kos": 2}]}, {0: {"kos": 2, "combo": 7, "blocks": 40}},
		{"mode": "chaos", "arena": "quarry", "hp": 1.0})
	return p


func _end_progress(p: String) -> void:
	Progress.set_enabled(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Progress.reset_for_tests(Progress.PATH)


func test_the_profile_pages_and_the_winners_title_fit_every_screen() -> void:
	var p := _full_progress()
	# The longest title and victory line, worn by Mister Crease (the longest name).
	var long_title := ""
	for r in Progress.account_rewards() + Progress.mastery_rewards("crease"):
		var id := String(r["id"])
		if id.begins_with("title:") and Progress.title_text(id).length() > Progress.title_text(long_title).length():
			long_title = id
	var long_line := ""
	for f in MatchFactory.FIGHTERS:
		for r in Progress.mastery_rewards(String(f)):
			var id := String(r["id"])
			if id.begins_with("line:") and Progress.line_text(id).length() > Progress.line_text(long_line).length():
				long_line = id
	assert_true(Progress.set_equipped("crease", "title", long_title), "")
	Progress._data["equipped"]["crease"]["line"] = long_line  # the longest of anyone's, on Crease to measure
	Progress.save()
	for size in SIZES:
		_screen(size)
		var g := _game()
		Progress.set_enabled(true)  # (set after the settings load, never left to its default)
		for page in PROFILE_PAGES:
			g._open_menu(page)
			_check(g, size, page)
			if String(page).begins_with("ending:"):
				_check_continue(g.ui.top() as EndingScreen, size, page)
			# Each picker's every value, for the panel's card and the row.
			var top: UiScreen = g.ui.top()
			for r in top.rows():
				if r is OptionRow and (r as OptionRow).values.size() > 1:
					var o := r as OptionRow
					o.grab_focus()
					for i in o.values.size():
						o.step(1)
						_check(g, size, "%s, %s %s" % [page, o.label, o.values[o.index]])
					var font := o.get_theme_font("font")
					var fs := o.get_theme_font_size("font_size")
					for v in o.values:
						var w := font.get_string_size(o.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0 \
							+ font.get_string_size("<  %s  >" % v, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
						assert_true(w <= o.size.x, "%s: '%s' and '%s' fit the row (%d > %d)" % [page, o.label, v, w, o.size.x])
		# An ending card that says the title it gave (the longest name and ending title).
		var card := EndingScreen.new("crease", true)
		card.unlocked_title = "title:crease_ending"
		g.ui.push(card)
		_check(g, size, "ending:crease with its title unlocked")
		_check_continue(card, size, "ending:crease with its title unlocked")
		# The results of a win as Crease, with the title and line (the pickers above stepped
		# through Crease's own lines and wore them: the longest, another fighter's, again).
		Progress.set_equipped("crease", "title", long_title)
		Progress._data["equipped"]["crease"]["line"] = long_line
		g._open_menu()
		g._skip_select = true
		g._start_match(g.mode_index("Mister Crease  vs  CPU Chef Cerebro"))
		_tick(g, 30)
		g.wins = [2, 0]
		g.flow = g.Flow.MATCH_OVER
		g.flow_t = 0
		g.hud.banner = "MISTER CREASE WINS!"
		_tick(g, g.MATCH_OVER_MENU_AT + 1)
		var panel := _find_results(g.ui.top()) as ResultsPanel
		assert_true(panel != null and String(panel.data["line"]) == Progress.line_text(long_line), "the line is on the results")
		_check(g, size, "results with a title and a victory line")
		g.free()
	_restore()
	_end_progress(p)


## The ending card's Continue, focused, shows whole: its glow (UiTheme's focus shadow, 3)
## inside the column, which clips at its edge (QC, Oct 2026: it was cut off at the bottom).
func _check_continue(card: EndingScreen, size: Vector2i, what: String) -> void:
	_layout(card)
	card.continue_button.grab_focus()
	var b := card.continue_button.get_global_rect()
	var col := card._scroll.get_global_rect()
	assert_true(b.end.y + 3.0 <= col.end.y + 0.01, "%s at %s: Continue and its glow inside the card (%.1f > %.1f)" % [what, size, b.end.y + 3.0, col.end.y])


## Every card's facts, for every row and every choice on it (a page only shows the
## focused row's first choice), on one line of the panel.
func test_every_rows_facts_fit_on_a_line_of_the_panel() -> void:
	var g := _game()
	var room := 170.0 - 8  # the Single player pages' panel (main.gd:_open_single_group)
	var checked := 0
	for row in MAIN.MENU_ROWS:
		if not row.has("modes"):
			continue
		for m in row["modes"]:
			for f in g._mode_facts(row, MAIN.MODES[int(m)]):
				var s := String(f)
				var font := DetailCard.fit_font(UiTheme.font(), s, DetailCard.FONT_FACT, room)
				var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(DetailCard.FONT_FACT)).x
				assert_true(w <= room + 1.0, "'%s' (%s) is %d wide, the panel %d" % [s, row["label"], w, room])
				checked += 1
	assert_gt(float(checked), 20.0, "every row's facts were read:")
	# The Weekly's card and the hub's today card change every week: a year of weeks.
	var hub_room := 150.0 - 8  # the Single player hub keeps UiScreen's default panel (main.gd:_open_single)
	var day := Daily.day_number(20261026)
	for k in 53:
		var w := Weekly.new("crease", Daily.date_of_day(day + 7 * k))
		var lines: Array = g._weekly_facts(w).map(func(t): return [t, room])
		for n in w.mutator_names_list():
			lines.append([String(n), hub_room])
		lines.append(["Weekly: best 9999", hub_room])  # main.gd:_today_facts
		lines.append(["Weekly: no score yet", hub_room])
		lines.append(["on " + ArenaMap.name_of(w.arena_id), hub_room])
		lines.append(["Daily: played, no score yet", hub_room])
		for pair in lines:
			var s := String(pair[0])
			var font := DetailCard.fit_font(UiTheme.font(), s, DetailCard.FONT_FACT, float(pair[1]))
			var wd := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(DetailCard.FONT_FACT)).x
			assert_true(wd <= float(pair[1]) + 1.0, "week %d: '%s' is %d wide, the panel %d" % [w.week, s, wd, pair[1]])
	g.free()


func test_the_60_hz_hint_fits_every_screen() -> void:
	for size in SIZES:
		_screen(size)
		var g := _game()
		g._refresh = 60.0  # a 60 Hz screen with a 120 cap chosen: the Fight frame rate row's hint
		g.fight_fps = 120
		g._open_menu("video")
		var row: Control = g._setting_rows.get("fps")
		assert_true(row != null, "the Fight frame rate row")
		if row != null:
			row.grab_focus()
			assert_true("refreshes 60 times" in String(g.ui.top().get("_desc").text), "the hint shows")
		_check(g, size, "video with the 60 Hz hint")
		g.free()
	_restore()


func _find_results(n: Node) -> Node:
	if n is ResultsPanel:
		return n
	for c in n.get_children():
		var f := _find_results(c)
		if f != null:
			return f
	return null


## The title's last row clears the description line under it at every size, with the
## Profile row there (Progression on, the default): a 16:9 1080p screen and a phone are
## 270 canvas units high, where Exit sat on the line (Oct 2026, task F's screenshots).
func test_the_title_rows_clear_the_description_line() -> void:
	for size in SIZES:
		_screen(size)
		var g := _game()
		Progress.set_enabled(true)
		g._open_menu()
		var t: TitleScreen = g.ui.top()
		_layout(g.ui)
		var exit_r := (t._rows_by_name["exit"] as Control).get_global_rect()
		var desc_r := t._desc.get_global_rect()
		assert_true(exit_r.end.y <= desc_r.position.y + 0.01, "%s: Exit (to %.1f) above the description (from %.1f)" % [size, exit_r.end.y, desc_r.position.y])
		assert_true(t._scroll.size.y >= t._list.get_combined_minimum_size().y - 0.5, "%s: the five rows fit unscrolled" % size)
		g.free()
	_restore()
	Progress.set_enabled(false)
