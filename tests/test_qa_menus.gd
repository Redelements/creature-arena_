extends TestCase
## QC sweep of the menus (docs/qa/part8-menus.md): every screen reachable from the title by
## key presses has rows that can take focus, a focus style in the theme, a Back that closes
## it, and no orphan (every row reachable with Up/Down); settings survive a save and a fresh
## load; Settings pages list only rows that exist; no debug words in the UI source.

const MAIN := preload("res://src/game/main.gd")
const TEST_SETTINGS := "user://test_qa_menus.cfg"
const SKIP_ROWS := ["Exit", "Quit", "Online", "Quick match"]
const MAX_DEPTH := 4


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _press(action: String) -> void:
	for down in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		_root().push_input(ev)


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	return g


## A row a press can open a screen from (a button or card; an option row that activates).
func _opens(c: Control) -> bool:
	if c is OptionRow:
		return (c as OptionRow).activates
	return c is Button and not (String((c as Button).text) in SKIP_ROWS)


## Re-open the title and follow `path` (row indexes), one accept each. False if it left the menu.
func _replay(g: Node, path: Array) -> bool:
	g._open_menu()
	for idx in path:
		var rows: Array = g.ui.top().rows()
		if int(idx) >= rows.size():
			return false
		(rows[int(idx)] as Control).grab_focus()
		_press("ui_accept")
		if g.flow != g.Flow.MENU or not g.ui.is_open():
			return false
	return true


func _sig(s: UiScreen) -> String:
	var parts := PackedStringArray([s.title, s.get_script().resource_path.get_file()])
	for r in s.rows():
		parts.append(s._row_title(r))
	return "|".join(parts)


func test_every_screen_reachable_from_the_title_is_sound() -> void:
	var g := _game()
	var seen := {}
	var queue: Array = [[]]
	var visited := 0
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		if not _replay(g, path):
			continue
		var scr: UiScreen = g.ui.top()
		var sig := _sig(scr)
		if seen.has(sig):
			continue
		seen[sig] = path
		visited += 1
		var where := "%s (path %s)" % [scr.title if scr.title != "" else sig.left(40), str(path)]
		var rows := scr.rows()
		assert_true(rows.size() > 0 or scr is TextPage or scr is EndingScreen, where + " has something to focus")
		for r in rows:
			assert_true((r as Control).focus_mode == Control.FOCUS_ALL, where + ": row focusable " + scr._row_title(r))
			if r is Button:
				var tv := String((r as Button).theme_type_variation)
				var tt := tv if tv != "" else "Button"
				assert_true(scr.theme.has_stylebox("focus", tt) or scr.theme.has_stylebox("focus", "Button"),
					where + ": focus style for " + tt)
		if rows.size() > 1 and not (scr is CharacterSelect or scr is RemapScreen):
			var reach := {}
			var c: Control = rows[0]
			for i in rows.size() + 1:
				reach[c] = true
				var nx := c.get_node_or_null(c.focus_neighbor_bottom) as Control
				if nx == null:
					break
				c = nx
			for r in rows:
				assert_true(reach.has(r), where + ": row reachable by Down: " + scr._row_title(r))
		if not path.is_empty():
			var depth_before: int = g.ui.screens.size()
			_press("ui_cancel")
			var closed: bool = g.ui.screens.size() < depth_before or g.ui.top() != scr
			assert_true(closed, where + ": Back leaves the screen")
		if path.size() >= MAX_DEPTH:
			continue
		for i in rows.size():
			if not _opens(rows[i]):
				continue
			var kid := path + [i]
			if _replay(g, kid) and g.ui.top() != scr and g.ui.screens.size() > path.size() + 1:
				queue.append(kid)
	g.free()
	assert_true(visited >= 25, "walked a real menu graph (%d screens)" % visited)
	print("  qa_menus: %d distinct screens walked" % visited)


func test_settings_pages_list_only_rows_that_exist() -> void:
	var g := _game()
	for page in MAIN.SETTING_PAGES:
		for key in MAIN.SETTING_PAGES[page]:
			if String(key).begins_with("#") or String(key) in ["server", "mic_test"]:
				continue
			var d: Dictionary = g.settings_ctl._setting(String(key))
			assert_true(d.has("label"), "%s/%s is a real setting row" % [page, key])
			if d.has("values") and d.has("index"):
				assert_true(int(d["index"]) >= 0 and int(d["index"]) < (d["values"] as Array).size(),
					"%s/%s: index %s inside its %d values" % [page, key, d["index"], (d["values"] as Array).size()])
	g.free()


func test_settings_survive_a_save_and_a_fresh_load() -> void:
	var was_smooth := UiTheme.smooth
	Controls.setup()
	Controls.reset()
	var g := _game()
	g.level = 2
	g.shake_scale = 0.5
	g.rumble = false
	g.match_intros = false
	g.discord_status = false
	g.vsync = false
	g.wide_fill = false
	g.glow = not g.glow
	g.lighting = 1
	g.cam_lead = 2
	g.fight_fps = 60
	g.voice_mode = 1
	g.voice_hear = 1
	g.touch_opacity = 3
	g.touch_left = true
	g.dummy_mode = 1
	var hz: Array = Hazards.ids().slice(0, 1)
	g.hazards_on = hz.duplicate()
	g.audio.set_volume("Master", 0.3)
	g.audio.set_volume("Music", 0.7)
	g.audio.set_volume("Effects", 0.2)
	g.audio.set_music_muted(true)
	g._online_server = "example.test:1234"
	UiTheme.smooth = true
	Accessibility.teams_saved = 1
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	Controls.rebind("gamepad", "pad_light", rb)
	var want_bind := Controls.binding_text("pad_light", "gamepad")
	var want_vol := {"Master": 0.3, "Music": 0.7, "Effects": 0.2}
	var glow_want: bool = g.glow
	g.settings_ctl._save_settings()
	g.free()
	UiTheme.smooth = false
	Accessibility.teams_saved = 0
	Controls.reset()
	var h: Node = load("res://scenes/main.tscn").instantiate()
	h.settings_path = TEST_SETTINGS
	_root().add_child(h)
	assert_eq(h.level, 2, "CPU level")
	assert_near(h.shake_scale, 0.5, 0.001, "screen shake")
	assert_false(h.rumble, "rumble")
	assert_false(h.match_intros, "match intros")
	assert_false(h.discord_status, "discord status")
	assert_false(h.vsync, "vsync")
	assert_false(h.wide_fill, "wide fill")
	assert_eq(h.glow, glow_want, "glow")
	assert_eq(h.lighting, 1, "lighting")
	assert_eq(h.cam_lead, 2, "camera lead")
	assert_eq(h.fight_fps, 60, "fight fps")
	assert_eq(h.voice_mode, 1, "voice mode")
	assert_eq(h.voice_hear, 1, "voice hear")
	assert_eq(h.touch_opacity, 3, "touch opacity")
	assert_true(h.touch_left, "left-handed touch")
	assert_eq(h.dummy_mode, 1, "dummy mode")
	assert_eq(h.hazards_on, hz, "hazards")
	for bus in want_vol:
		assert_near(h.audio.volume(bus), want_vol[bus], 0.001, "volume " + bus)
	assert_true(h.audio.music_muted, "music muted")
	assert_eq(h._online_server, "example.test:1234", "server address")
	assert_true(UiTheme.smooth, "text font smooth")
	assert_eq(Accessibility.teams_saved, 1, "colour-safe teams")
	assert_eq(Controls.binding_text("pad_light", "gamepad"), want_bind, "keybind")
	h.free()
	UiTheme.smooth = was_smooth
	Accessibility.teams_saved = 0
	Controls.reset()
	DirAccess.remove_absolute(TEST_SETTINGS)


func test_no_debug_words_in_the_ui_source() -> void:
	var bad := ["TODO", "FIXME", "PLACEHOLDER", "lorem", "asdf", "test label", "XXX"]
	var files: Array = ["res://src/game/main_settings.gd"]
	for f in DirAccess.get_files_at("res://src/ui"):
		if f.ends_with(".gd"):
			files.append("res://src/ui/" + f)
	for path in files:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			for w in bad:
				if line.contains(w) and line.contains("\""):
					fail("%s has a quoted '%s': %s" % [path, w, line.strip_edges().left(80)])
