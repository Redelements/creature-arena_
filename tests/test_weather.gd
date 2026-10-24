extends TestCase
## Time of day and weather (WeatherView, data/weather.json): presets from data, the
## arena's allowed set, the menu choice saved, online and the menu's background fight
## day + clear, replays their recorded look, and the sim never touched.

const TEST_SETTINGS := "user://test_weather_settings.cfg"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	return g


func test_every_preset_builds_from_data() -> void:
	var d := WeatherView.data()
	assert_true(WeatherView.time_ids() == ["day", "sunset", "night"], "three times of day: " + str(WeatherView.time_ids()))
	for w in ["clear", "rain", "fog", "wind", "snow"]:
		assert_true(w in WeatherView.weather_ids(), w + " is a weather")
	var sim := MatchFactory.versus("cairn", "culvert")
	for t in WeatherView.time_ids():
		for w in WeatherView.weather_ids():
			var wv := WeatherView.new()
			wv.apply(sim, {"time": t, "weather": w})
			assert_eq(wv.look, {"time": t, "weather": w}, "")
			if t == "night":
				assert_true(wv.shade.tex != null and wv.shade.visible, "night: a light map over the floor")
			elif t == "day" and w == "clear":
				assert_false(wv.shade.visible, "day and clear: no tint at all")
			wv.ground.free()
			wv.shade.free()
			wv.free()
	for k in ["times", "weathers"]:
		for id in d[k]:
			for key in ["floor", "fighter", "life"]:
				if (d[k][id] as Dictionary).has(key):
					assert_true(Color.html_is_valid(String(d[k][id][key])), "%s.%s.%s is a colour" % [k, id, key])


func test_arenas_choose_from_their_own_list() -> void:
	for id in ArenaMap.IDS + ArenaMap.MODE_IDS:
		var arena := ArenaMap.get_map(id)
		for t in WeatherView.times_of(arena):
			assert_true(t in WeatherView.time_ids(), "%s allows a known time (%s)" % [id, t])
		for w in WeatherView.weathers_of(arena):
			assert_true(w in WeatherView.weather_ids(), "%s allows a known weather (%s)" % [id, w])
	var gh := ArenaMap.get_map("greenhouse")
	assert_false("snow" in WeatherView.weathers_of(gh), "no snow under the glass")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 200:
		var l := WeatherView.resolve(gh, "random", "random", rng)
		assert_true(String(l["weather"]) in WeatherView.weathers_of(gh), "random stays in the allowed set")
		seen[l["weather"]] = true
	assert_eq(seen.size(), WeatherView.weathers_of(gh).size(), "and reaches every allowed one")
	assert_eq(WeatherView.resolve(gh, "night", "snow")["weather"], "clear", "a choice the map doesn't allow plays clear")
	assert_eq(WeatherView.resolve(gh, "night", "snow")["time"], "night", "")
	var none := WeatherView.times_of({"times": ["noon"]})
	assert_eq(none, ["day"], "unknown ids fall back to day")


func test_night_lights_fighters_in_pools_and_keeps_a_floor_of_brightness() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var v := CreatureView.new()
	v.setup(sim.creatures[0])
	var wv := WeatherView.new()
	wv.views = [v]
	wv.apply(sim, {"time": "night", "weather": "clear"})
	var pool: Vector2 = wv._lights[0][0]
	sim.creatures[0].pos = pool
	wv.advance()
	assert_near(wv.light_at(pool), 1.0, 0.01, "the middle of a pool is lit")
	assert_true(v.sprite.self_modulate.is_equal_approx(Color.WHITE), "a fighter in a pool is lit fully: " + str(v.sprite.self_modulate))
	var far := sim.floor_rect().position + Vector2(2, 2)
	assert_lt(wv.light_at(far), 0.3, "a corner between pools is dark")
	sim.creatures[0].pos = far
	wv.advance()
	var c := v.sprite.self_modulate
	assert_gt(c.r * 0.3 + c.g * 0.55 + c.b * 0.15, float(WeatherView.data()["times"]["night"]["fighter_min"]) - 0.06,
		"a fighter in the dark keeps its minimum brightness: " + str(c))
	v.free()
	wv.ground.free()
	wv.shade.free()
	wv.free()


func test_rain_retunes_shadows_and_sends_the_butterflies_to_shelter() -> void:
	MatchFactory.arena = "greenhouse"
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = ArenaMap.DEFAULT
	var amb := AmbientView.new()
	amb.set_sim(sim)
	var flies := amb.fly_count()
	assert_gt(flies, 0, "butterflies over the beds on a clear day")
	var sh := ShadowLayer.new()
	var wv := WeatherView.new()
	wv.apply(sim, {"time": "day", "weather": "rain"}, sh, amb)
	assert_eq(amb.fly_count(), 0, "they shelter from the rain")
	assert_lt(float(sh.light["alpha"]), float(ShadowLayer.light_of(sim.arena)["alpha"]), "overcast: softer shadows")
	wv.apply(sim, {"time": "sunset", "weather": "clear"}, sh, amb)
	assert_eq(amb.fly_count(), flies, "back out when it clears")
	assert_gt(Vector2(sh.light["cast"]).length(), Vector2(ShadowLayer.light_of(sim.arena)["cast"]).length() * 1.5,
		"sunset: long shadows")
	for n in [amb, sh, wv.ground, wv.shade, wv]:
		n.free()


func test_the_sim_never_feels_the_weather() -> void:
	var a := MatchFactory.versus("culvert", "cairn")
	var b := MatchFactory.versus("culvert", "cairn")
	var wv := WeatherView.new()
	wv.apply(b, {"time": "night", "weather": "rain"})
	for i in 240:
		var bits := SimDefs.IN_LIGHT if i % 20 == 0 else 0
		a.step(PackedInt32Array([bits, 0]))
		b.step(PackedInt32Array([bits, 0]))
		wv.advance()
	assert_eq(a.state_digest(), b.state_digest(), "the same fight, whatever the look")
	wv.ground.free()
	wv.shade.free()
	wv.free()


func test_the_menu_choice_saves_and_online_stays_day_and_clear() -> void:
	var g := _game()
	assert_eq(g.weather.look, WeatherView.default_look(), "the menu's background fight is day and clear")
	g._set_look_choice("times", "night")
	g._set_look_choice("weathers", "rain")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(cfg.get_value("game", "time", ""), "night", "the Time choice is saved")
	assert_eq(cfg.get_value("game", "weather", ""), "rain", "the Weather choice is saved")
	g._start_match(2)
	assert_eq(g.weather.look, {"time": "night", "weather": "rain"}, "an offline match plays it")
	assert_eq(g.replay.setup.get("look", {}), {"time": "night", "weather": "rain"}, "and the replay records it")
	# a replay plays its own look, an old one (none saved) day and clear
	g.mode = g.REPLAY_MODE
	g._replay_watched = {"look": {"time": "sunset", "weather": "fog"}}
	assert_eq(g._match_look(g.sim), {"time": "sunset", "weather": "fog"}, "a replay's recorded look")
	g._replay_watched = {}
	assert_eq(g._match_look(g.sim), WeatherView.default_look(), "an old replay: day and clear")
	# online, watching a room and the menu's background fight: always day and clear (one branch)
	g.mode = 2
	g._menu_bg = true
	assert_eq(g._match_look(g.sim), WeatherView.default_look(), "online / background: day and clear")
	g._menu_bg = false
	g.free()
	var again: Node = load("res://scenes/main.tscn").instantiate()
	again.settings_path = TEST_SETTINGS
	_root().add_child(again)
	assert_eq(again.time_choice, "night", "kept after a restart")
	assert_eq(again.weather_choice, "rain", "")
	again.free()


func test_enter_on_the_arena_row_opens_time_and_weather() -> void:
	var g := _game()
	g._open_single()
	var hub: UiScreen = g.ui.top()
	var arena: OptionRow = hub.rows()[0]
	assert_eq(arena.label, "Arena", "")
	assert_true(arena.activates, "Enter on the Arena row does something")
	arena.activated.emit()
	var page: UiScreen = g.ui.top()
	assert_true(page != hub, "a page of its own")
	var labels: Array = []
	for r in page.rows():
		if r is OptionRow:
			labels.append((r as OptionRow).label)
	assert_eq(labels, ["Time", "Weather"], "with the two options")
	var t: OptionRow = page.rows()[0]
	assert_eq(t.values[0], "Random", "Random first, the default")
	g.free()
