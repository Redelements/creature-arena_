extends RefCounted
class_name MainSettings
## Settings for main: the Settings pages and their rows (`_open_settings`,
## `_open_settings_page`, `_add_setting_row`, the Controls and remap pages), each row's
## shown value and what a change does (`_setting`, `_set_setting`), and the settings file
## (`_load_settings`, `_save_settings`; `user://settings.cfg`, or main's `settings_path`).
## Moved out of main.gd verbatim; the values themselves are still main's (`main`), and
## `SETTING_PAGES` and the choice tables are main's constants (`Main.`).

const Main := preload("res://src/game/main.gd")

var main: Main


func _init(p_main: Main) -> void:
	main = p_main


## Settings: five pages: Game, Video, Audio, Accessibility, Controls; and the Credits.
func _open_settings() -> void:
	var scr := UiScreen.new()
	scr.logo = true
	scr.title = "SETTINGS"
	scr.row_width = 230.0
	scr.detail = true
	scr.blurb = "CPU level, keyboard layout, volume, fullscreen, frame rate"
	scr.builder = func(s: UiScreen):
		s.add_card("Game", "CPU level, rumble, screen shake, online server, input delay",
			func(): _open_settings_page("game"), "How the game plays and where it plays online")
		s.add_card("Video", "Fullscreen, wide screens, vsync, frame rate",
			func(): _open_settings_page("video"), "The screen and the frame rate")
		s.add_card("Audio", "Master, music, sound effects, menu sounds, voice chat",
			func(): _open_settings_page("audio"), "Volumes")
		s.add_card("Accessibility", "Colour-safe team colours, fighter outlines, hit markers",
			func(): _open_settings_page("accessibility"), "Easier to tell who's who and when a hit lands")
		s.add_card("Controls", "Keyboard and controller layouts; remap keys and buttons",
			_open_controls, "Who presses what")
		s.add_card("Credits", "Who made the game; art, font and engine licences",
			_open_credits, "Credits and licences, and the engine's third-party notices")
		s.add_card("Save a bug report", "The log, settings, progress and your last replay, in one zip",
			func(): main._save_bug_report(true), BugReport.BLURB + " (no online id or secret)")
		s.add_space(3)
		s.add_button("Back", s.back)
	main.ui.push(scr)


## Settings > Credits (src/ui/credits_screen.gd; LICENSES.md says it at length).
func _open_credits() -> void:
	main.ui.push(CreditsScreen.new())


## One Settings page: each row's values and description come from _setting(); a change
## goes through _set_setting() and is saved at once.
func _open_settings_page(page: String) -> void:
	var scr := UiScreen.new()
	scr.logo = true
	scr.crumbs = ["SETTINGS"]
	scr.title = page.to_upper()
	scr.row_width = 236.0
	scr.detail = true
	scr.blurb = {"game": "How the game plays and where it plays online", "video": "The screen and the frame rate",
		"audio": "Volumes and voice chat", "accessibility": "Easier to tell who's who and when a hit lands (all off by default)", "touch": "The on-screen stick and buttons (they show when you touch the screen in a fight)"}.get(page, "")
	scr.hints = ["move", "change", "back"]
	scr.builder = func(s: UiScreen):
		for key in Main.SETTING_PAGES[page]:
			if key == "server":
				_add_server_row(s)
			elif key.begins_with("#"):
				s.add_heading(key.substr(1))
			elif key == "mic_test":
				_add_mic_test_row(s)
			else:
				_add_setting_row(s, key)
		s.add_space(4)
		s.add_button("Back", s.back)
	scr.backed.connect(func():
		main._setting_rows.clear()
		if main.voice_view != null:
			main.voice_view.test_stop())
	main.ui.push(scr)


## Rebuild an open Settings page in place (its rows carry their own font sizes), with
## the row that changed focused again: Text font swaps every size on the page.
func _reopen_settings_page(page: String, key: String) -> void:
	var top := main.ui.top()
	if top == null or top.title != page.to_upper():
		return
	main.ui.pop()
	_open_settings_page(page)
	var row: Control = main._setting_rows.get(key)
	if row != null:
		row.grab_focus()


func _add_setting_row(s: UiScreen, key: String) -> OptionRow:
	var info := _setting(key)
	var o := s.add_option(String(info["label"]), info["values"], int(info["index"]), func(_i): pass,
		String(info["desc"]))
	o.wrap = bool(info.get("wrap", true))
	o.bar = float(info.get("bar", -1.0))
	o.changed.connect(func(i: int):
		_set_setting(key, i)
		var now := _setting(key)
		o.set_values(now["values"], int(now["index"]))
		o.bar = float(now.get("bar", -1.0)))
	main._setting_rows[key] = o
	return o


## Settings > Audio > Test microphone: Enter records a few seconds with a live level bar,
## then plays them back (VoiceView.test_start); `_voice_step` keeps the row current.
func _add_mic_test_row(s: UiScreen) -> OptionRow:
	var o := s.add_option("Test microphone", [main.voice_view.test_text()], 0, func(_i): pass,
		"Press, say a few words, and hear them played back. The bar shows how loud the microphone hears you. Nothing heard: pick another Microphone, or allow the game to use it in your system settings")
	o.activates = true
	o.bar = main.voice_view.test_level
	o.activated.connect(func():
		main._apply_mic()
		main.voice_view.test_start()
		_refresh_mic_test())
	main._setting_rows["mic_test"] = o
	return o


func _refresh_mic_test() -> void:
	var o: OptionRow = main._setting_rows.get("mic_test")
	if o == null or main.voice_view == null:
		return
	var t := main.voice_view.test_text()
	if o.values.size() != 1 or String(o.values[0]) != t:
		o.set_values([t], 0)
	if not is_equal_approx(o.bar, main.voice_view.test_level):
		o.bar = main.voice_view.test_level
		o.queue_redraw()


## Settings > Game > Online server: a text box, saved as it's typed. Empty means the
## game's own server.
func _add_server_row(s: UiScreen) -> LineEdit:
	var f := LineEdit.new()
	f.text = main._online_server
	f.placeholder_text = "Online server: " + default_server()
	f.max_length = 80
	f.text_changed.connect(func(t: String):
		main._online_server = t.strip_edges()
		_save_settings())
	s.add_row(f, "Where Quick match and rooms play. Leave it empty for %s" % default_server())
	s.entitle(f, "Online server")
	return f


## The game's own server, from data/online.json.
static func default_server() -> String:
	var f := FileAccess.open("res://data/online.json", FileAccess.READ)
	if f == null:
		return ""
	var d = JSON.parse_string(f.get_as_text())
	return String(d.get("server", "")).strip_edges() if d is Dictionary else ""


## The server Quick match and rooms use: the player's, or the game's own.
func online_server() -> String:
	return main._online_server if main._online_server != "" else default_server()


## Controls: the keyboard layout, and remapping for each keyboard layout and the controller.
func _open_controls() -> void:
	var scr := UiScreen.new()
	scr.logo = true
	scr.crumbs = ["SETTINGS"]
	scr.title = "CONTROLS"
	scr.row_width = 236.0
	scr.detail = true
	scr.blurb = "Who presses what"
	scr.hints = ["move", "change", "select", "back"]
	scr.builder = func(s: UiScreen):
		_add_setting_row(s, "layout")
		_add_setting_row(s, "pad_layout")
		_add_setting_row(s, "range_rings")
		s.add_button("Touch controls", func(): _open_settings_page("touch"),
			"The on-screen stick and buttons: how see-through, how big, which hand, how to aim")
		s.add_button("Remap controller", func(): _open_remap("gamepad"), "Change which button does what")
		s.add_button("Remap Classic keyboard", func(): _open_remap("classic"), "WASD + J K U I O, or your own keys")
		s.add_button("Remap League-style keyboard", func(): _open_remap("league"),
			"Mouse to move and aim; Q W E R, or your own keys")
		s.add_button("Reset all controls", func():
			var c := ConfirmScreen.new("Reset every key and button?", "Back to the game's defaults.", "Reset", "Cancel")
			c.answered.connect(func(yes: bool):
				if yes:
					Controls.reset()
					_save_settings()
					main._apply_device()
					main._toast("Controls reset"))
			main.ui.push(c), "Put every key and button back")
		s.add_space(4)
		s.add_button("Back", s.back)
	scr.backed.connect(func(): main._setting_rows.clear())
	main.ui.push(scr)


func _open_remap(group: String) -> void:
	var r := RemapScreen.new(group)
	r.changed.connect(func():
		_save_settings()
		main._apply_device())  # the prompts and help show the new keys
	main.ui.push(r)


## A Settings row: its label, values (shown), current index, a description, and for a
## volume its bar.
func _setting(key: String) -> Dictionary:
	if key.begins_with("vol_"):
		var bus := key.trim_prefix("vol_")
		var v := main.audio.volume(bus)
		var vals: Array = ["Off"]
		for i in range(1, 11):
			vals.append("%d%%" % (i * 10))
		var idx := clampi(roundi(v / Main.VOLUME_STEP), 0, 10)
		if bus == "Music" and main.audio.music_muted and idx > 0:
			vals[idx] = "muted (M)"
		return {"label": Main.VOLUME_NAMES[bus], "values": vals, "index": idx, "bar": v, "wrap": false,
			"desc": "Left/Right sets it.  M mutes the music any time"}
	match key:
		"level":
			return {"label": "CPU level", "values": Main.LEVEL_NAMES, "index": main.level, "desc": "How hard the CPU fights. Rage: absurdly good, and plays each fighter by its class"}
		"delay":
			return {"label": "Online input delay", "values": ["Auto", "1 frame", "2 frames", "3 frames"],
				"index": clampi(main.input_delay + 1, 0, 3),
				"desc": "Frames between a press and the move online. Auto picks from the ping; more means fewer rollbacks. For matches you host or join directly (the server sets its own)"}
		"layout":
			var names: Array = []
			for l in PlayerInput.LAYOUTS:
				names.append(PlayerInput.LAYOUT_NAMES[l])
			return {"label": "Keyboard", "values": names, "index": PlayerInput.LAYOUTS.find(main.player_input.layout),
				"desc": "League-style: mouse to move, QWER.  Classic: WASD and J K U I O"}
		"pad_layout":
			var pads: Array = []
			for l in PlayerInput.PAD_LAYOUTS:
				pads.append(PlayerInput.PAD_LAYOUT_NAMES[l])
			return {"label": "Controller", "values": pads,
				"index": maxi(0, PlayerInput.PAD_LAYOUTS.find(main.player_input.pad_layout)),
				"desc": "Twin-stick: the right stick aims 360 degrees and holds your facing while you walk"}
		"fullscreen":
			return {"label": "Fullscreen", "values": ["Off", "On"], "index": 1 if main.fullscreen else 0,
				"desc": "Fill the screen"}
		"wide":
			return {"label": "Wide screens", "values": ["16:9 with bars", "Fill"], "index": 1 if main.wide_fill else 0,
				"desc": "Ultrawide and 16:10: show more of the stadium, or keep a 16:9 picture"}
		"vsync":
			return {"label": "Vsync", "values": ["Off", "On"], "index": 1 if main.vsync else 0,
				"desc": "On: no tearing, and the screen's refresh rate caps the frame rate"}
		"touch_opacity":
			var ops: Array = []
			for o in Main.TOUCH_OPACITY:
				ops.append("%d%%" % roundi(float(o) * 100.0))
			return {"label": "Opacity", "values": ops, "index": main.touch_opacity,
				"desc": "How see-through the touch stick and buttons are"}
		"touch_size":
			return {"label": "Button size", "values": TouchPad.SIZE_NAMES, "index": main.player_input.touch.size_step,
				"desc": "Bigger buttons are easier to hit and cover more of the fight"}
		"touch_hand":
			return {"label": "Hand", "values": ["Right-handed", "Left-handed"],
				"index": 1 if main.touch_left else 0,
				"desc": "Left-handed: the buttons on the left and the stick on the right"}
		"touch_priority":
			return {"label": "Lock on", "values": TouchTarget.PRIORITY_NAMES, "index": int(main.player_input.target.priority),
				"desc": "Which foe a tap locks onto: the one nearest where you point, the nearest, or the one with the least health. Tap a portrait to pick one yourself"}
		"touch_chase":
			return {"label": "Chase target", "values": ["Off", "On"], "index": 1 if main.player_input.target.chase_on else 0,
				"desc": "Tap Light with your target out of reach and you walk to it (round pits and walls), then hit. The stick always wins"}
		"touch_aim":
			return {"label": "Aiming", "values": TouchPad.AIM_STYLES, "index": 1 if main.player_input.touch.tap_only else 0,
				"desc": "Tap + drag: tap fires (aimed for you), drag Heavy, Skills or Surge off the button to aim and let go to throw. Tap only: every button fires on the touch"}
		"range_rings":
			return {"label": "Range rings", "values": ["Off", "On"], "index": 1 if main.range_rings else 0,
				"desc": "Show each attack's real hit area on the floor"}
		"no_cooldowns":
			return {"label": "No cooldowns", "values": ["Off", "On"], "index": 1 if main.training_opts["no_cooldowns"] else 0,
				"desc": "Every move and the dodge are always ready, and your stamina stays full"}
		"full_energy":
			return {"label": "Surge always full", "values": ["Off", "On"], "index": 1 if main.training_opts["full_energy"] else 0,
				"desc": "Your Surge meter stays full: throw the Surge as often as you like"}
		"dummy_mode":
			return {"label": "Dummy", "values": Main.DUMMY_MODES, "index": main.dummy_mode,
				"desc": "What the dummy does (F2 cycles it in a fight)"}
		"intros":
			return {"label": "Match intros", "values": ["Off", "On"], "index": 1 if main.match_intros else 0,
				"desc": "Before an offline match: a fly-over of the arena and each side's entrance (any button skips it)"}
		"rumble":
			return {"label": "Controller rumble", "values": ["Off", "On"], "index": 1 if main.rumble else 0,
				"desc": "A buzz when you land a hit or get hit"}
		"discord":
			return {"label": "Discord status", "values": ["Off", "On"], "index": 1 if main.discord_status else 0,
				"desc": "Show what you're playing on your Discord profile (with the Discord app open)"}
		"shake":
			var names: Array = []
			var idx := 0
			for i in Main.SHAKE_CHOICES.size():
				names.append(Main.SHAKE_CHOICES[i][0])
				if is_equal_approx(float(Main.SHAKE_CHOICES[i][1]), main.shake_scale):
					idx = i
			return {"label": "Screen shake", "values": names, "index": idx,
				"desc": "How much the camera shakes on big hits"}
		"fps":
			var vals: Array = []
			for f in Main.FPS_CHOICES:
				vals.append("Unlimited" if int(f) == 0 else "%d fps" % int(f))
			return {"label": "Fight frame rate", "values": vals, "index": maxi(0, Main.FPS_CHOICES.find(main.fight_fps)),
				"desc": "Menus always run at 60 fps; this sets fights (up to your screen's refresh rate)"}
		"glow":
			return {"label": "Glow", "values": ["Off", "On"], "index": 1 if main.glow else 0,
				"desc": "Glowing things (auras, sparks, flashes, shots) light the floor around them. Off for weaker devices"}
		"lighting":
			return {"label": "Lighting", "values": ["Off", "Low", "High"], "index": main.lighting,
				"desc": "Real light on the fighters (sun, auras, flashes); High adds the Floodgate's night lamps and bloom. Lower for weaker devices"}
		"font":
			return {"label": "Text font", "values": ["Pixel", "Smooth"], "index": 1 if UiTheme.smooth else 0,
				"desc": "The menus and the HUD: the pixel font, or the smooth font from before"}
		"cam_lead":
			return {"label": "Aim lead", "values": Main.CAM_LEVELS, "index": main.cam_lead,
				"desc": "The camera leans a little toward where you aim, so you see more of the floor in front of you"}
		"cam_clash":
			return {"label": "Clash reaction", "values": Main.CAM_LEVELS, "index": main.cam_clash,
				"desc": "A heavy hit, a guard break or a Surge's hit: the camera punches in for a moment"}
		"cam_settle":
			return {"label": "Settle", "values": Main.CAM_LEVELS, "index": main.cam_settle,
				"desc": "When nothing is happening, the camera holds still instead of hunting. Higher: stiller"}
		"voice":
			var talk := Controls.binding_text("lol_talk" if main.player_input.layout == "league" else "kb_talk",
				"league" if main.player_input.layout == "league" else "classic")
			return {"label": "Voice chat", "values": VoiceChat.MODE_NAMES, "index": main.voice_mode_now(),
				"desc": "Online: talk to players near your fighter (teammates always faintly). Push to talk holds %s. Voice isn't encrypted: treat it like a phone call on open Wi-Fi. Open mic sends any sound above a whisper, TV included; push to talk is the safer default" % talk}
		"voice_hear":
			return {"label": "Hear voices from", "values": Main.VOICE_HEAR, "index": main.voice_hear,
				"desc": "Everyone: anyone in your match. Rooms and friends: Quick match and ranked strangers start muted; unmute them from the pause menu"}
		"mic":
			var mics := main.mic_choices()
			return {"label": "Microphone", "values": mics, "index": maxi(0, mics.find(main.mic_device)),
				"desc": "Which microphone voice chat listens to"}
		"perf_overlay":
			return {"label": "Performance overlay", "values": PerfOverlay.MODE_NAMES, "index": main.perf_overlay.mode,
				"desc": "The frame rate in a corner; with the graph, the last few seconds of frame times (F9 in a fight)"}
		"a11y_teams":
			return {"label": "Team colours", "values": Accessibility.TEAM_NAMES, "index": Accessibility.teams(),
				"desc": "Colour-safe: orange against sky blue (and yellow for you), told apart with any colour blindness, by brightness too"}
		"a11y_outlines":
			return {"label": "Fighter outlines", "values": Accessibility.OUTLINE_NAMES, "index": Accessibility.outlines(),
				"desc": "A thin line round every fighter you can see: in its team's colour, or white round black. Never shows a hidden fighter"}
		"a11y_markers":
			return {"label": "Hit markers", "values": Accessibility.MARKER_NAMES, "index": Accessibility.markers(),
				"desc": "High contrast: bigger hit sparks and damage numbers with a dark outline, and a white flash on every hit"}
	return {"label": key, "values": [""], "index": 0, "desc": ""}


func _set_setting(key: String, i: int) -> void:
	if key.begins_with("vol_"):
		var bus := key.trim_prefix("vol_")
		var v := clampf(i * Main.VOLUME_STEP, 0.0, 1.0)
		main.audio.set_volume(bus, v)
		if bus == "Music" and v > 0.0 and main.audio.music_muted:
			main.audio.set_music_muted(false)  # turning the music up unmutes it
		# Let the player hear the new level (the music is already playing).
		if bus == "Effects":
			main.audio.preview("hit_light", "Effects")
		elif bus != "Music":
			main.audio.preview("ui_select", "Menu")
	else:
		match key:
			"level":
				main.level = clampi(i, 0, Main.LEVEL_NAMES.size() - 1)
			"delay":
				main.input_delay = clampi(i, 0, 3) - 1
			"layout":
				main.player_input.layout = PlayerInput.LAYOUTS[clampi(i, 0, PlayerInput.LAYOUTS.size() - 1)]
				main._apply_device()
			"pad_layout":
				main._set_pad_layout(PlayerInput.PAD_LAYOUTS[clampi(i, 0, PlayerInput.PAD_LAYOUTS.size() - 1)])
				main._apply_device()
			"fullscreen":
				main.fullscreen = i == 1
				main._apply_fullscreen()
			"wide":
				main.wide_fill = i == 1
				main._apply_aspect()
			"vsync":
				main.vsync = i == 1
				main._apply_vsync()
			"intros":
				main.match_intros = i == 1
			"rumble":
				main.rumble = i == 1
				if main.rumble and main.player_input.device == PlayerInput.Device.GAMEPAD:
					Input.start_joy_vibration(main.player_input.pad_id, 0.4, 0.4, 0.2)  # feel it
			"shake":
				main.shake_scale = float(Main.SHAKE_CHOICES[clampi(i, 0, Main.SHAKE_CHOICES.size() - 1)][1])
			"range_rings":
				main.range_rings = i == 1
				main._apply_range_rings()
			"touch_opacity":
				main.touch_opacity = clampi(i, 0, Main.TOUCH_OPACITY.size() - 1)
				main._apply_touch()
			"touch_size":
				main.player_input.touch.size_step = clampi(i, 0, TouchPad.SIZES.size() - 1)
				main._apply_touch()
			"touch_hand":
				main.touch_left = i == 1
				main._apply_touch()
			"touch_aim":
				main.player_input.touch.tap_only = i == 1
			"touch_priority":
				main.player_input.target.priority = clampi(i, 0, TouchTarget.PRIORITY_NAMES.size() - 1) as TouchTarget.Priority
			"touch_chase":
				main.player_input.target.chase_on = i == 1
			"no_cooldowns", "full_energy":
				main.training_opts[key] = i == 1
				main._apply_training_opts()
			"dummy_mode":
				main.dummy_mode = clampi(i, 0, Main.DUMMY_MODES.size() - 1)
				main.hud.dummy_mode_name = Main.DUMMY_MODES[main.dummy_mode]
			"discord":
				main.discord_status = i == 1
				main._apply_discord()
			"fps":
				main.fight_fps = int(Main.FPS_CHOICES[clampi(i, 0, Main.FPS_CHOICES.size() - 1)])
			"cam_lead", "cam_clash", "cam_settle":
				main.set(key, clampi(i, 0, Main.CAM_LEVELS.size() - 1))
				main._cam_cli.erase(key)  # (the menu outranks a command-line value from here on)
			"perf_overlay":
				main.perf_overlay.mode = clampi(i, 0, PerfOverlay.MODE_NAMES.size() - 1) as PerfOverlay.Mode
			"a11y_teams":
				Accessibility.teams_saved = clampi(i, 0, Accessibility.TEAM_NAMES.size() - 1)
				Accessibility.cli.erase("teams")  # (the menu outranks --a11y from here on)
			"a11y_outlines":
				Accessibility.outlines_saved = clampi(i, 0, Accessibility.OUTLINE_NAMES.size() - 1)
				Accessibility.cli.erase("outlines")
			"a11y_markers":
				Accessibility.markers_saved = clampi(i, 0, Accessibility.MARKER_NAMES.size() - 1)
				Accessibility.cli.erase("markers")
			"voice":
				main.voice_mode = clampi(i, 0, VoiceChat.MODE_NAMES.size() - 1)
				main._voice_cli = -1  # (the menu outranks --voice from here on)
				main._apply_voice()
			"voice_hear":
				main.voice_hear = clampi(i, 0, Main.VOICE_HEAR.size() - 1)
			"mic":
				var mics := main.mic_choices()
				main.mic_device = String(mics[clampi(i, 0, mics.size() - 1)])
				main._apply_mic()
			"glow":
				main.glow = i == 1
				main._apply_glow()
			"lighting":
				main.lighting = clampi(i, 0, 2)
				main._lighting_cli = -1
				main._apply_lighting()
			"font":
				if UiTheme.smooth != (i == 1):
					UiTheme.smooth = i == 1
					main.ui.restyle()
					_reopen_settings_page.call_deferred("video", "font")
	_save_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	# Settings > Accessibility: off unless saved (static, so a second game in one run starts clean too)
	Accessibility.cli = {}
	Accessibility.teams_saved = 0
	Accessibility.outlines_saved = 0
	Accessibility.markers_saved = 0
	if cfg.load(main.settings_path) == OK:
		Accessibility.teams_saved = clampi(int(cfg.get_value("accessibility", "teams", 0)), 0, Accessibility.TEAM_NAMES.size() - 1)
		Accessibility.outlines_saved = clampi(int(cfg.get_value("accessibility", "outlines", 0)), 0, Accessibility.OUTLINE_NAMES.size() - 1)
		Accessibility.markers_saved = clampi(int(cfg.get_value("accessibility", "markers", 0)), 0, Accessibility.MARKER_NAMES.size() - 1)
		var lay := String(cfg.get_value("input", "layout", "league"))
		if lay in PlayerInput.LAYOUTS:
			main.player_input.layout = lay
		var pad := String(cfg.get_value("input", "pad_layout", "standard"))
		if pad in PlayerInput.PAD_LAYOUTS:
			main._set_pad_layout(pad)
		main.level = clampi(int(cfg.get_value("game", "level", main.level)), 0, Main.LEVEL_NAMES.size() - 1)
		main.input_delay = clampi(int(cfg.get_value("online", "delay", -1)), -1, 3)
		Netplay.player_id = String(cfg.get_value("online", "id", ""))
		Netplay.player_secret = String(cfg.get_value("online", "secret", ""))
		Netplay.player_name = Netplay.clean_name(String(cfg.get_value("online", "name", "Player")))
		if Netplay.player_name == "":
			Netplay.player_name = "Player"
		var tc := String(cfg.get_value("game", "time", WeatherView.RANDOM))
		main.time_choice = tc if tc == WeatherView.RANDOM or tc in WeatherView.time_ids() else WeatherView.RANDOM
		var wc := String(cfg.get_value("game", "weather", WeatherView.RANDOM))
		main.weather_choice = wc if wc == WeatherView.RANDOM or wc in WeatherView.weather_ids() else WeatherView.RANDOM
		main.hazards_on = []
		var known := Hazards.ids()
		for h in cfg.get_value("game", "hazards", []):
			if String(h) in known and not (String(h) in main.hazards_on):
				main.hazards_on.append(String(h))
		main.hazards_on.sort()
		var ar := String(cfg.get_value("game", "arena", MatchFactory.arena))
		if ar in ArenaMap.IDS:
			main._arena_saved = ar
			if MatchFactory.arena == ArenaMap.DEFAULT:  # no --arena flag
				MatchFactory.arena = ar
		main.audio.set_music_muted(bool(cfg.get_value("audio", "music_muted", false)))
		main._online_fighter = String(cfg.get_value("online", "fighter", main._online_fighter))
		if not (main._online_fighter in MatchFactory.FIGHTERS):
			main._online_fighter = "cairn"
		main._online_address = String(cfg.get_value("online", "address", ""))
		main._online_server = String(cfg.get_value("online", "server", "")).strip_edges()
		main._recent_servers = Array(cfg.get_value("online", "recent", []))
		for bus in AudioView.DEFAULT_VOLUMES:
			main.audio.set_volume(bus, float(cfg.get_value("audio", "volume_" + String(bus).to_lower(),
				AudioView.DEFAULT_VOLUMES[bus])))
		main.fullscreen = bool(cfg.get_value("video", "fullscreen", false))
		if main.fullscreen:
			main._apply_fullscreen()
		main.vsync = bool(cfg.get_value("video", "vsync", true))
		main._apply_vsync()
		main.wide_fill = bool(cfg.get_value("video", "wide_fill", true))
		main._apply_aspect()
		main.rumble = bool(cfg.get_value("game", "rumble", true))
		main.match_intros = bool(cfg.get_value("game", "intros", true))
		main.discord_status = bool(cfg.get_value("game", "discord", true))
		main.shake_scale = float(cfg.get_value("game", "shake", 1.0))
		main.range_rings = bool(cfg.get_value("game", "range_rings", false))
		main.touch_opacity = clampi(int(cfg.get_value("touch", "opacity", Main.TOUCH_OPACITY_DEFAULT)), 0, Main.TOUCH_OPACITY.size() - 1)
		main.player_input.touch.size_step = clampi(int(cfg.get_value("touch", "size", 1)), 0, TouchPad.SIZES.size() - 1)
		main.touch_left = bool(cfg.get_value("touch", "left_handed", false))
		main.player_input.touch.tap_only = bool(cfg.get_value("touch", "tap_only", false))
		main.player_input.target.priority = clampi(int(cfg.get_value("touch", "priority", 0)), 0,
			TouchTarget.PRIORITY_NAMES.size() - 1) as TouchTarget.Priority
		main.player_input.target.chase_on = bool(cfg.get_value("touch", "chase", true))
		for k in MatchSim.TRAINING_FLAGS:
			main.training_opts[k] = bool(cfg.get_value("training", k, false))
		main.dummy_mode = clampi(int(cfg.get_value("training", "dummy_mode", 0)), 0, Main.DUMMY_MODES.size() - 1)
		Controls.apply_overrides(cfg.get_value("controls", "bindings", {}))
		var fps := int(cfg.get_value("video", "fight_fps", Main.default_fps()))
		main.fight_fps = fps if fps in Main.FPS_CHOICES else Main.default_fps()
		UiTheme.smooth = String(cfg.get_value("video", "font", "pixel")) == "smooth"
		main.glow = bool(cfg.get_value("video", "glow", Main.default_glow()))
		main._apply_glow()
		main.lighting = clampi(int(cfg.get_value("video", "lighting", Main.default_lighting())), 0, 2)
		for k in ["cam_lead", "cam_clash", "cam_settle"]:
			main.set(k, clampi(int(cfg.get_value("video", k, Main.CAM_DEFAULT)), 0, Main.CAM_LEVELS.size() - 1))
		main.perf_overlay.mode = clampi(int(cfg.get_value("video", "perf_overlay", 0)), 0,
			PerfOverlay.MODE_NAMES.size() - 1) as PerfOverlay.Mode
		main.voice_mode = clampi(int(cfg.get_value("audio", "voice_mode", VoiceChat.Mode.PUSH_TO_TALK)), 0,
			VoiceChat.MODE_NAMES.size() - 1)
		main.mic_device = String(cfg.get_value("audio", "mic_device", ""))
		main.voice_hear = clampi(int(cfg.get_value("audio", "voice_hear", 0)), 0, Main.VOICE_HEAR.size() - 1)
		main._apply_mic()
		var saved_rows = cfg.get_value("game", "row_choice", {})
		if saved_rows is Dictionary:
			for r in Main.MENU_ROWS.size():
				var lbl := String(Main.MENU_ROWS[r]["label"])
				if saved_rows.has(lbl) and Main.MENU_ROWS[r].has("choices"):
					main._row_choice[r] = clampi(int(saved_rows[lbl]), 0, (Main.MENU_ROWS[r]["choices"] as Array).size() - 1)
	# After everything is loaded: saving here first would write defaults over it.
	# The secret proves the id is this install's to a server (never shown or sent to
	# another player); made with the id, or once for an id from before secrets.
	if Netplay.player_id.length() < 8 or not Netplay.valid_secret(Netplay.player_secret):
		if Netplay.player_id.length() < 8:
			Netplay.player_id = Netplay.make_player_id()
		if not Netplay.valid_secret(Netplay.player_secret):
			Netplay.player_secret = Netplay.make_secret()
		_save_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "layout", main.player_input.layout)
	cfg.set_value("input", "pad_layout", main.player_input.pad_layout)
	cfg.set_value("game", "level", main.level)
	cfg.set_value("game", "arena", main._arena_saved)
	cfg.set_value("game", "time", main.time_choice)
	cfg.set_value("game", "weather", main.weather_choice)
	cfg.set_value("game", "hazards", main.hazards_on)
	cfg.set_value("online", "delay", main.input_delay)
	cfg.set_value("online", "id", Netplay.player_id)
	cfg.set_value("online", "secret", Netplay.player_secret)
	cfg.set_value("online", "name", Netplay.player_name)
	cfg.set_value("audio", "music_muted", main.audio.music_muted)
	cfg.set_value("audio", "voice_mode", main.voice_mode)
	cfg.set_value("audio", "voice_hear", main.voice_hear)
	cfg.set_value("audio", "mic_device", main.mic_device)
	cfg.set_value("online", "fighter", main._online_fighter)
	cfg.set_value("online", "address", main._online_address)
	cfg.set_value("online", "server", main._online_server)
	cfg.set_value("online", "recent", main._recent_servers)
	cfg.set_value("video", "fullscreen", main.fullscreen)
	cfg.set_value("video", "fight_fps", main.fight_fps)
	cfg.set_value("video", "vsync", main.vsync)
	cfg.set_value("video", "wide_fill", main.wide_fill)
	cfg.set_value("video", "perf_overlay", main.perf_overlay.mode)
	for k in ["cam_lead", "cam_clash", "cam_settle"]:
		cfg.set_value("video", k, int(main.get(k)))
	cfg.set_value("video", "glow", main.glow)
	cfg.set_value("video", "lighting", main.lighting)
	cfg.set_value("video", "font", "smooth" if UiTheme.smooth else "pixel")
	cfg.set_value("accessibility", "teams", Accessibility.teams_saved)
	cfg.set_value("accessibility", "outlines", Accessibility.outlines_saved)
	cfg.set_value("accessibility", "markers", Accessibility.markers_saved)
	cfg.set_value("game", "rumble", main.rumble)
	cfg.set_value("game", "intros", main.match_intros)
	cfg.set_value("game", "shake", main.shake_scale)
	cfg.set_value("game", "range_rings", main.range_rings)
	cfg.set_value("touch", "opacity", main.touch_opacity)
	cfg.set_value("touch", "size", main.player_input.touch.size_step)
	cfg.set_value("touch", "left_handed", main.touch_left)
	cfg.set_value("touch", "tap_only", main.player_input.touch.tap_only)
	cfg.set_value("touch", "priority", int(main.player_input.target.priority))
	cfg.set_value("touch", "chase", main.player_input.target.chase_on)
	for k in MatchSim.TRAINING_FLAGS:
		cfg.set_value("training", k, bool(main.training_opts.get(k, false)))
	cfg.set_value("training", "dummy_mode", main.dummy_mode)
	cfg.set_value("game", "discord", main.discord_status)
	var rows := {}
	for r in Main.MENU_ROWS.size():
		if Main.MENU_ROWS[r].has("choices") and r < main._row_choice.size():
			rows[String(Main.MENU_ROWS[r]["label"])] = int(main._row_choice[r])
	cfg.set_value("game", "row_choice", rows)
	cfg.set_value("controls", "bindings", Controls.overrides())
	for bus in AudioView.DEFAULT_VOLUMES:
		cfg.set_value("audio", "volume_" + String(bus).to_lower(), main.audio.volume(bus))
	cfg.save(main.settings_path)
