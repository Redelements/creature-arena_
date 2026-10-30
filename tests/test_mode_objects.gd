extends TestCase
## A mode's objects belong to its match (QA part 1, 2026-10-29): Capture the Flag's flags, the
## shrines, the Caravan's wagon and the wanted marks never outlive the match that made them
## (FxView keeps them in `flags`, `shrines`, `caravan`, `wanted`, written only by
## `main.gd:_update_zone` in team and Brawl fights; `FxView.clear()` from `_new_sim` must drop
## them, or the menu background and the next 1v1 drew the last CTF's flags and shrines). And
## the sim side: every offline mode builds exactly the objects its rules file
## (data/rules/*.json) asks for, on the map its rules pin or a pickable map, never a mode map.
##
## MODES indices this file uses (checked against their labels below, so a renumbering fails
## here first): 0 "Cairn  vs  CPU Culvert", 45 "Brawl: you vs 3 CPUs", 50 "Caravan: 2v2 vs CPU",
## 52 "Capture the Flag: 3v3 vs CPU". The table test walks every MODES entry and skips the
## online lobby (20), the Replay theater (47), the showcases (5), Combo Trials (9) and the
## Reaction Drills (10, 11): they need a server, a saved replay or a coach's script.

const MAIN := preload("res://src/game/main.gd")
const TEST_SETTINGS := "user://test_mode_objects.cfg"
const VERSUS := 0
const BRAWL := 45
const CARAVAN := 50
const CTF := 52
const LABELS := {VERSUS: "Cairn  vs  CPU Culvert", BRAWL: "Brawl: you vs 3 CPUs",
	CARAVAN: "Caravan: 2v2 vs CPU", CTF: "Capture the Flag: 3v3 vs CPU"}
const TEAMS := [["cairn", "culvert", "barkley", "gillbert"], ["craglash", "cerebro", "hissy", "digby"]]


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	g._cpu_vs_cpu = true
	g._skip_select = true  # straight into the match, as --mode does
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


## The mode arrays FxView still holds that it shouldn't (empty: none).
func _leftovers(g: Node) -> String:
	var out: Array = []
	if not g.fx.flags.is_empty():
		out.append("flags %d" % g.fx.flags.size())
	if not g.fx.shrines.is_empty():
		out.append("shrines %d" % g.fx.shrines.size())
	if not g.fx.caravan.is_empty():
		out.append("caravan")
	if not g.fx.wanted.is_empty():
		out.append("wanted %d" % g.fx.wanted.size())
	return ", ".join(out)


func test_the_indices_this_file_uses_are_still_those_modes() -> void:
	for m in LABELS:
		assert_eq(String(MAIN.MODES[m]["label"]), String(LABELS[m]), "MODES[%d]" % m)


## (a) CTF (played to its results), the Caravan and a Brawl, then the main menu and a 1v1:
## nothing of the mode is still drawn behind the menu or in the 1v1.
func test_mode_objects_do_not_outlive_their_match() -> void:
	var g := _game()
	for src in [CTF, CARAVAN, BRAWL]:
		var label := String(LABELS[src])
		g._start_match(src)
		var shown := false
		for t in 600:
			_tick(g, 1)
			shown = (not g.fx.flags.is_empty()) if src == CTF else \
				((not g.fx.caravan.is_empty()) if src == CARAVAN else not g.fx.shrines.is_empty())
			if shown:
				break
		assert_true(shown, label + ": its objects show during the match")
		if src == CTF:
			assert_false(g.fx.shrines.is_empty(), label + ": its shrines show too")
			var tb = g.team_battle
			tb.overtime = false
			tb.score[0] = int(tb.score[0]) + 1  # side 0 leads; the clock runs out
			tb.timer = 1
			var over := false
			for t in 2400:
				_tick(g, 1)
				if g.flow == g.Flow.MATCH_OVER and g.ui.is_open():
					over = true
					break
			assert_true(over, label + ": reached its results")
		g._back_to_row()  # the results' Main menu (Pause > Quit lands the same way)
		_tick(g, 30)
		assert_eq(_leftovers(g), "", label + " -> main menu: the menu background still draws")
		g._start_match(VERSUS)
		_tick(g, 120)
		assert_eq(g.team_battle, null, "the 1v1 is no team battle")
		assert_eq(_leftovers(g), "", label + " -> main menu -> 1v1: the 1v1 still draws")
		g._open_menu()
	g.free()


## The rules file a MODES entry plays by (data/rules/<id>.json; "" for none), the way main
## picks it (`_start_round`, `_start_team`, `TeamSim.rules_by_id`).
func _rules_id(cfg: Dictionary) -> String:
	if cfg.has("team"):
		return String(cfg.get("rules", "deathmatch" if cfg.get("deathmatch", false) else "team"))
	if cfg.get("brawl", false):
		return "brawl"
	if cfg.get("duel", false):
		return "duel"
	if cfg.get("training", false):
		return ""
	return "duel_1v1"


func _rules(id: String) -> Dictionary:
	if id == "":
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules/%s.json" % id))
	return d if d is Dictionary else {}


## (b) Every offline mode, started through main: the objects in the sim are the ones its
## rules file asks for, and the map is the pinned one or a pickable one.
func test_every_mode_builds_only_its_rules_objects() -> void:
	var g := _game()
	var checked := 0
	for m in MAIN.MODES.size():
		var cfg: Dictionary = MAIN.MODES[m]
		if cfg.get("online", false) or cfg.get("replay", false) or cfg.get("showcase", false) \
				or cfg.get("trials", false) or cfg.has("drill"):
			continue
		var label := "%d %s" % [m, String(cfg["label"])]
		g._start_match(m)
		_tick(g, 2)
		var sim: MatchSim = g.sim
		assert_true(sim != null, label + ": a match")
		if sim == null:
			continue
		var rules := _rules(_rules_id(cfg))
		var tb = g.team_battle if g.team_battle != null and g.team_battle.sim == sim else null
		var pinned := String(rules.get("arena", ""))
		if pinned != "":
			assert_eq(sim.arena_id, pinned, label + ": the map its rules pin")
		else:
			assert_true(sim.arena_id in ArenaMap.IDS, label + ": a pickable map, not " + sim.arena_id)
		var ctf := bool(rules.get("ctf", false))
		var caravan := bool(rules.get("caravan", false))
		var crater := bool(rules.get("crater", false))
		assert_eq(tb != null and bool(tb.ctf), ctf, label + ": flags only with rules ctf")
		assert_eq(sim.arena.has("bases"), ctf, label + ": flag bases only with rules ctf")
		assert_eq(tb != null and bool(tb.caravan), caravan, label + ": a caravan only with rules caravan")
		assert_eq(sim.arena.has("track"), caravan, label + ": a caravan track only with rules caravan")
		assert_eq(tb != null and bool(tb.crater), crater, label + ": a crater only with rules crater")
		# (the Caravan reuses the sim's zone as the wagon's push ring: team_sim.gd `_cv_start_round`)
		assert_eq(sim.zone_r > 0.0, crater or caravan, label + ": a floor zone only with rules crater / caravan")
		assert_eq(not sim.shrine_spots.is_empty(), rules.has("shrines"), label + ": shrines iff the rules have a shrines block")
		assert_eq(not sim.bridges.is_empty(), sim.arena_id == "twin_keeps", label + ": bridges only on twin_keeps")
		checked += 1
		g._open_menu()
	assert_gt(checked, 50, "most modes checked")
	g.free()


## (c) Capture the Flag on Twin Keeps: two bases, two flags at distinct spots, each at its base.
func test_ctf_has_two_bases_and_two_flags_apart() -> void:
	var tb := TeamSim.new(TEAMS, 3, TeamSim.rules_by_id("ctf"))
	assert_eq(tb.sim.arena_id, "twin_keeps", "CTF's map")
	var bases: Dictionary = tb.sim.arena.get("bases", {})
	assert_true(bases.has("left") and bases.has("right"), "two bases: %s" % [bases.keys()])
	assert_gt(tb.base_of(0).distance_to(tb.base_of(1)), 200.0, "the bases far apart")
	assert_gt(Vector2(tb.flag_pos[0]).distance_to(tb.flag_pos[1]), 200.0, "the flags far apart")
	for side in 2:
		assert_eq(Vector2(tb.flag_pos[side]), tb.base_of(side), "flag %d on its base" % side)


## (c) Every team rules file at every size it allows: `size` distinct spawn points a side, and
## the two sides apart.
func test_every_team_mode_has_distinct_spawns_per_side() -> void:
	for id in TeamSim.RULE_IDS:
		var rules := TeamSim.rules_by_id(id)
		for n in range(1, TeamSim.max_size_for(id) + 1):
			var tb := TeamSim.new(TEAMS, n, rules)
			var label := "%s %dv%d on %s" % [id if id != "" else "team", n, n, tb.sim.arena_id]
			var pts := [[], []]
			for side in 2:
				for k in n:
					var p := tb.spawn_point(side, k, n)
					for q in pts[side]:
						assert_gt(p.distance_to(q), 8.0, label + ": side %d spawn %d apart from its teammates" % [side, k])
					pts[side].append(p)
			var closest := INF
			for p in pts[0]:
				for q in pts[1]:
					closest = minf(closest, Vector2(p).distance_to(q))
			assert_gt(closest, 96.0, label + ": the sides start apart")
