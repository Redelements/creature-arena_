extends TestCase
## Arena options (Single player > Enter on the Arena row): Time and Weather (looks only) and
## one On/Off row per arena hazard in data/rules/hazards.json (how the match plays). Off by
## default, saved, shown on the Arena row and the opening banner, on in every offline match
## but the Daily, the ladders, coaches, showcases and replays; Chaos Cup ignores the rows
## and can always draw a hazard (Kevin's ruling, Oct 2026); a replay rebuilds the same hazards.

const TEST_SETTINGS := "user://test_arena_options.cfg"
const ON_MODES := ["Cairn  vs  CPU Culvert", "Training: Cairn", "Team battle: 2v2 vs CPU",
	"Team Deathmatch: 2v2 vs CPU", "Sinkhole: 1v1 vs CPU", "King of the Crater: 1v1 vs CPU",
	"Caravan: 2v2 vs CPU", "Capture the Flag: 3v3 vs CPU", "Brawl: you vs 3 CPUs", "Duel: you vs CPU  (3v3 tag)"]
const OFF_MODES := ["Daily Challenge", "Arcade", "Gauntlet", "Combo Trials", "Reaction Drill: read Culvert", "Watch: combo showcases"]


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _game(fresh := true) -> Node:
	if fresh and FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	g._cpu_vs_cpu = true
	g._skip_select = true  # straight into the match, as --mode does
	return g


func _hazards(g: Node) -> Array:
	return (g.sim.mutators.get("hazards", []) as Array) if g.sim != null else []


## The Arena options page, opened like a player: the hub, then Enter on the Arena row.
func _open_options(g: Node) -> UiScreen:
	g._open_single()
	var hub: UiScreen = g.ui.top()
	var arena: OptionRow = hub.rows()[0]
	assert_eq(arena.label, "Arena", "the hub's first row")
	arena.activated.emit()
	return g.ui.top()


func _row(page: UiScreen, label: String) -> OptionRow:
	for r in page.rows():
		if r is OptionRow and (r as OptionRow).label == label:
			return r
	return null


func test_the_page_has_a_row_per_hazard_off_by_default() -> void:
	var g := _game()
	var page := _open_options(g)
	assert_eq(page.title, "ARENA OPTIONS", "renamed:")
	var labels: Array = []
	for r in page.rows():
		if r is OptionRow:
			labels.append((r as OptionRow).label)
	var want: Array = ["Time", "Weather"]
	for id in Hazards.ids():
		want.append(Hazards.name_of(id))
	assert_eq(labels, want, "time, weather, then one row per hazard in the data:")
	for id in Hazards.ids():
		var row := _row(page, Hazards.name_of(id))
		assert_eq(row.values, ["Off", "On"], "an On/Off row")
		assert_eq(row.index, 0, "off by default")
	assert_true(g.hazards_on.is_empty(), "nothing on")
	assert_true(page.blurb.contains("look") and page.blurb.contains("play"), "says weather is looks, hazards play: " + page.blurb)
	g.free()


func test_toggling_saves_shows_and_plays() -> void:
	var g := _game()
	var page := _open_options(g)
	_row(page, "Tidal wave").step(1)
	assert_eq(g.hazards_on, ["tidal_wave"], "on:")
	page.back()  # back on the hub: the Arena row says what's on
	var hub: UiScreen = g.ui.top()
	assert_true(String(hub._descriptions[hub.rows()[0]]).contains("Hazards: Tidal wave"), "the Arena row: "
		+ String(hub._descriptions[hub.rows()[0]]))
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(cfg.get_value("game", "hazards", []), ["tidal_wave"], "saved:")
	g._start_match(g.mode_index("Cairn  vs  CPU Culvert"))
	assert_eq(_hazards(g), ["tidal_wave"], "a 1v1 plays it:")
	assert_true(g.sim.terrain.count(TerrainGrid.WALL) > 0, "breakwaters and all")
	assert_true(g.hud.mutator_text.contains("TIDAL WAVE"), "named beside the clock: " + g.hud.mutator_text)
	for i in 30:
		g._physics_process(1.0 / 60.0)
	assert_true(g.hud.banner_sub.contains("Hazards: Tidal wave"), "and in the opening banner: " + g.hud.banner_sub)
	g.free()
	var again := _game(false)
	assert_eq(again.hazards_on, ["tidal_wave"], "kept after a restart:")
	again._open_single()
	var hub2: UiScreen = again.ui.top()
	assert_true(String(hub2._descriptions[hub2.rows()[0]]).contains("Tidal wave"), "the hub says so from the start")
	again.free()


func test_on_in_every_offline_mode_and_kept_on_rematch() -> void:
	var g := _game()
	g._set_hazard("meteor_shower", true)
	g._set_hazard("tidal_wave", true)
	for label in ON_MODES:
		var m: int = g.mode_index(label)
		assert_true(m >= 0, label + " is a mode")
		g._start_match(m)
		assert_eq(_hazards(g), ["meteor_shower", "tidal_wave"], label + ":")
		g._start_match(m, true)  # Rematch
		assert_eq(_hazards(g), ["meteor_shower", "tidal_wave"], label + " (rematch):")
	g._set_hazard("meteor_shower", false)
	g._set_hazard("tidal_wave", false)
	g._start_match(g.mode_index("Cairn  vs  CPU Culvert"))
	assert_true(_hazards(g).is_empty(), "Off: none")
	g.free()


func test_not_in_the_daily_ladders_coaches_or_showcases() -> void:
	var g := _game()
	g._set_hazard("meteor_shower", true)
	g._set_hazard("tidal_wave", true)
	for label in OFF_MODES:
		g._start_match(g.mode_index(label))
		var hz := _hazards(g)
		if g.arcade is Daily:  # the Daily draws its own two (one may be a hazard): never the setting
			assert_eq(g.sim.mutators, (g.arcade as Daily).mutators(), label + ": its own mutators only")
		else:
			assert_true(hz.is_empty(), label + ": no hazards (" + str(hz) + ")")
	g.free()


func test_chaos_cup_draws_hazards_whatever_the_rows_say() -> void:
	var g := _game()
	var m: int = g.mode_index("Chaos Cup")
	var seen_off := false
	for s in range(1, 41):
		g.seed_base = s
		g._start_match(m)
		assert_eq(String(g._chaos_names).split(", ").size(), 3, "three mutators drawn")
		seen_off = seen_off or not _hazards(g).is_empty()
	assert_true(seen_off, "both Off: the cup still draws them")
	var seen_on := false
	g._set_hazard("meteor_shower", true)
	g._set_hazard("tidal_wave", true)
	for s in range(1, 41):
		g.seed_base = s
		g._start_match(m)
		assert_eq(String(g._chaos_names).split(", ").size(), 3, "three mutators drawn")
		seen_on = seen_on or not _hazards(g).is_empty()
	assert_true(seen_on, "On: the cup draws them too")
	g.free()


func test_a_replay_rebuilds_the_same_hazards() -> void:
	var g := _game()
	g._set_hazard("tidal_wave", true)
	g._set_hazard("meteor_shower", true)
	g.seed_base = 7
	g._start_match(g.mode_index("Team battle: 2v2 vs CPU"))
	var setup: Dictionary = g.replay.setup
	assert_eq(setup.get("mutators", {}).get("hazards", []), ["meteor_shower", "tidal_wave"], "recorded:")
	assert_eq(int(setup.get("mut_seed", -1)), 7, "with its seed:")
	var built: Dictionary = ReplayBuilder.build(setup)
	var rs: MatchSim = built["sim"]
	assert_eq(rs.terrain.cells, g.sim.terrain.cells, "the same breakwaters:")
	assert_eq(rs.hazards, g.sim.hazards, "the same hazard state:")
	g.free()


func test_the_command_line_overrides_the_setting() -> void:
	var g := _game()
	g._set_hazard("tidal_wave", true)
	g._forced_mutators = {"hazards": ["meteor_shower"]}
	g._start_match(g.mode_index("Cairn  vs  CPU Culvert"))
	assert_eq(_hazards(g), ["meteor_shower"], "--mutators wins for the session:")
	g.free()
