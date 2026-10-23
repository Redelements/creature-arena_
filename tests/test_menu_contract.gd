extends TestCase
## The menus' words against the rules they describe: every number a row's description
## quotes (KOs to win, the Crater's hold, captures, team sizes, best of three, the
## Arcade's stages, the Gauntlet's climb, the Daily's and Chaos Cup's mutators) is read
## back from the rules files and the code that plays them, so a tuning change that
## leaves the menu lying fails here. Also each row's Left/Right choices against the
## modes they start, and each hub card's line against the rows behind it.

const MAIN := preload("res://src/game/main.gd")
const WORDS := {1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight"}


func _row(label: String) -> Dictionary:
	for r in MAIN.MENU_ROWS:
		if String(r["label"]) == label:
			return r
	fail("no row called " + label)
	return {}


func _desc(label: String) -> String:
	return String(_row(label).get("desc", ""))


func _group(id: String) -> Dictionary:
	for g in MAIN.MENU_GROUPS:
		if String(g["id"]) == id:
			return g
	return {}


func _name(fighter: String) -> String:
	return String(MatchFactory.load_def(fighter).get("name", fighter))


func test_team_deathmatch_quotes_the_kos_to_win_for_each_size() -> void:
	var rules := TeamSim.rules_by_id("deathmatch")
	var want: Array = rules["score_to_win"]
	var d := _desc("Team Deathmatch vs CPU")
	assert_true(d.contains("to %d KOs" % int(want[2])), "2 v 2 wins at %d KOs: %s" % [int(want[2]), d])
	assert_true(d.contains("(%d in 3 v 3)" % int(want[3])), "3 v 3 at %d: %s" % [int(want[3]), d])


func test_king_of_the_crater_quotes_the_hold() -> void:
	var rules := TeamSim.rules_by_id("crater")
	var secs := int(rules["score_to_win"]) / 60
	var d := _desc("King of the Crater vs CPU")
	assert_true(d.contains("%d s held wins" % secs), "the hold is %d s: %s" % [secs, d])


func test_capture_the_flag_quotes_the_captures() -> void:
	var rules := TeamSim.rules_by_id("ctf")
	var d := _desc("Capture the Flag vs CPU")
	assert_true(d.contains("First to %d captures" % int(rules["captures_to_win"])), d)


func test_duels_are_teams_of_the_rules_size() -> void:
	var size := int(DuelSim.load_rules().get("team_size", 3))
	for label in ["Duel: you vs CPU  (3v3 tag)", "Duel: 2 players"]:
		var d := _desc(label)
		assert_true(d.contains("Teams of %s" % WORDS[size]), "%s: teams of %s: %s" % [label, WORDS[size], d])
	var mode: Dictionary = MAIN.MODES[int(_row("Duel: you vs CPU  (3v3 tag)")["modes"][0])]
	assert_true(String(mode["label"]).contains("%dv%d" % [size, size]), "the row says %dv%d: %s" % [size, size, mode["label"]])
	var arcade := _desc("Arcade")
	assert_true(arcade.contains("a boss team in a %dv%d Duel" % [size, size]), "the Arcade's boss Duel too: " + arcade)


func test_versus_is_best_of_the_rounds_needed() -> void:
	var best_of: int = MAIN.WINS_NEEDED * 2 - 1
	var d := _desc("Versus CPU")
	assert_true(d.contains("Best of %s rounds" % WORDS[best_of]), "best of %d: %s" % [best_of, d])


func test_the_arcade_counts_its_fights_and_names_the_palette_key() -> void:
	var fights: int = Arcade.STAGES - 1
	var d := _desc("Arcade")
	assert_true(d.contains("%s fights up the roster" % WORDS[fights].capitalize()), "%d fights then the boss: %s" % [fights, d])
	Controls.setup()
	var key := Controls.binding_text("palette", "classic")
	assert_true(d.contains("(%s in a fight)" % key), "the palette key is %s: %s" % [key, d])


func test_the_gauntlet_climbs_every_so_many_waves() -> void:
	var d := _desc("Gauntlet")
	assert_true(d.contains("harder every %s" % WORDS[Gauntlet.WAVES_PER_LEVEL]), d)


func test_the_daily_and_the_chaos_cup_count_their_mutators_and_name_them_all() -> void:
	var d := _desc("Daily Challenge")
	assert_true(d.contains("%s mutators" % WORDS[Daily.PICKS]), "the Daily draws %d: %s" % [Daily.PICKS, d])
	var chaos := _desc("Chaos Cup")
	var table := Daily.mutator_table()
	for id in table:
		var n := String(table[id].get("name", id)).to_lower()
		assert_true(chaos.to_lower().contains(n), "Chaos Cup lists %s: %s" % [n, chaos])
	# Chaos Cup stacks three: what the game actually draws.
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = "user://test_menu_contract.cfg"
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	g._start_match(MAIN.mode_index("Chaos Cup"))
	g._on_teams_chosen([["cairn"], ["culvert"]])
	var names: PackedStringArray = String(g._chaos_names).split(", ")
	assert_true(chaos.contains("%s random mutators" % WORDS[names.size()]), "it draws %d: %s" % [names.size(), chaos])
	g.free()


func test_brawl_seats_as_many_as_the_sim_allows() -> void:
	var d := _desc("Brawl")
	assert_true(d.contains("%s fighters" % WORDS[BrawlSim.MAX_PLAYERS]), d)
	var row := _row("Brawl")
	for m in row["modes"]:
		assert_eq((MAIN.MODES[int(m)]["sides"] as Array).size(), BrawlSim.MAX_PLAYERS, "every Brawl mode seats %d" % BrawlSim.MAX_PLAYERS)
	var hub := _group("brawl")
	assert_true(String(hub["sub"]).contains("up to %s" % WORDS[BrawlSim.MAX_PLAYERS]), String(hub["sub"]))


func test_every_choice_names_the_mode_it_starts() -> void:
	for row in MAIN.MENU_ROWS:
		if not row.has("choices"):
			continue
		var choices: Array = row["choices"]
		var modes: Array = row["modes"]
		var label := String(row["label"])
		if row.get("fighter_choice", false):
			assert_eq(choices.size(), MatchFactory.FIGHTERS.size(), label + ": a choice per fighter")
			assert_eq(modes.size(), 1, label + ": one mode, the fighter chosen by the row")
			for i in choices.size():
				assert_eq(String(choices[i]), "as " + _name(MatchFactory.FIGHTERS[i]), label + ": choice %d" % i)
			continue
		assert_eq(choices.size(), modes.size(), label + ": a mode per choice")
		for i in choices.size():
			var c := String(choices[i])
			var cfg: Dictionary = MAIN.MODES[int(modes[i])]
			var where := "%s [%s] -> %s" % [label, c, cfg["label"]]
			if cfg.has("team"):
				assert_eq(c, "%d v %d" % [int(cfg["team"]), int(cfg["team"])], where)
			elif cfg.get("training", false):
				assert_eq(c, _name(String(cfg["left"])), where)
			elif cfg.has("drill"):
				assert_eq(c, "read " + _name(String(cfg["drill"])), where)
			elif cfg.get("brawl", false):
				var humans := 0
				for s in cfg["sides"]:
					if s in MAIN.LOCAL_SIDES:
						humans += 1
				assert_eq(c, "you vs 3 CPUs" if humans == 1 else "%d players" % humans, where)
			elif cfg.has("left") and not (MAIN.Side.PLAYER in cfg["sides"]):  # Watch: nobody's seat
				assert_eq(c, "CPU vs CPU", where)
			elif cfg.has("left"):  # Versus CPU: as the fighter on the left
				assert_eq(c, "as " + _name(String(cfg["left"])), where)
				assert_true(String(cfg["label"]).begins_with(_name(String(cfg["left"]))), where + ": the mode's label starts with it")
			elif cfg.get("showcase", false):
				assert_eq(c, "combo showcases", where)
			else:
				fail(where + ": a choice this test doesn't know how to read")


func test_each_hub_card_counts_and_names_what_is_behind_it() -> void:
	var by_group := {}
	for row in MAIN.MENU_ROWS:
		var gid := String(row.get("group", ""))
		if not by_group.has(gid):
			by_group[gid] = []
		(by_group[gid] as Array).append(String(row["label"]))
	var team := String(_group("team")["sub"])
	var n: int = (by_group["team"] as Array).size()
	assert_true(team.to_lower().contains("%s modes" % WORDS[n]), "Team battles has %d rows: %s" % [n, team])
	var sizes: Array = []
	for row in MAIN.MENU_ROWS:
		if String(row.get("group", "")) == "team":
			for m in row["modes"]:
				sizes.append(int(MAIN.MODES[int(m)]["team"]))
	assert_true(team.contains("%dv%d to %dv%d" % [sizes.min(), sizes.min(), sizes.max(), sizes.max()]),
		"team sizes %d to %d: %s" % [sizes.min(), sizes.max(), team])
	var challenge := String(_group("challenge")["sub"])
	for label in by_group["challenge"]:
		var word := String(label).split(" ")[0]
		assert_true(challenge.contains(word), "Challenges names %s: %s" % [word, challenge])
	var practice := String(_group("practice")["sub"])
	assert_true(practice.to_lower().contains("replay"), practice)
	assert_true(practice.to_lower().contains("training"), practice)
	var local := String(_group("local")["sub"])
	assert_true(local.contains("Duel") and local.contains("Versus"), local)


func test_the_cpu_level_setting_names_the_top_level() -> void:
	var top := String(CpuController.LEVELS.back()["name"])
	assert_eq(top, MAIN.LEVEL_NAMES.back(), "the level names match the CPU's")
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = "user://test_menu_contract.cfg"
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	g._open_menu("game")
	var scr: UiScreen = g.ui.top()
	var row: OptionRow = null
	for r in scr.rows():
		if r is OptionRow and (r as OptionRow).label == "CPU level":
			row = r
	assert_true(row != null, "a CPU level row")
	assert_eq(row.values, MAIN.LEVEL_NAMES, "its choices are the levels")
	assert_true(String(scr._descriptions.get(row, "")).contains(top), "its line names %s" % top)
	g.free()
