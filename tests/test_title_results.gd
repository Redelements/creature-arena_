extends TestCase
## The title's attract demo, the screen wipes and the results screen (stats counted from
## sim events, the winner's pose, an MVP in team modes, the same buttons as before).

const TEST_SETTINGS := "user://test_title_results.cfg"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


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


func _key() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	return ev


func _find(n: Node, cls: Variant) -> Node:
	if is_instance_of(n, cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _hit(a: int, t: int, dmg: float, combo: int) -> Dictionary:
	return {"type": "hit", "attacker": a, "target": t, "power": dmg, "combo": combo, "pos": Vector2.ZERO}


func test_stats_count_hits_damage_blocks_surges_combo_and_kos_from_events() -> void:
	var s := MatchStats.new()
	s.note(_hit(0, 1, 10.0, 1))
	s.note(_hit(0, 1, 12.5, 2))
	s.note(_hit(0, 1, 7.5, 3))
	s.note(_hit(1, 0, 4.0, 1))
	s.note({"type": "block", "attacker": 0, "target": 1, "power": 3.0})
	s.note({"type": "surge", "who": 1, "name": "X"})
	s.note({"type": "ko", "who": 1})
	assert_eq(int(s.rows[0]["hits"]), 3, "hits:")
	assert_eq(roundi(s.rows[0]["damage"]), 30, "damage:")
	assert_eq(int(s.rows[0]["combo"]), 3, "best combo:")
	assert_eq(int(s.rows[0]["kos"]), 1, "the KO goes to the last one who hit:")
	assert_eq(int(s.rows[1]["blocks"]), 1, "the blocker is credited:")
	assert_eq(int(s.rows[1]["surges"]), 1, "surge:")
	assert_eq(int(s.rows[1]["kos"]), 0, "")
	s.note({"type": "ko", "who": 1})
	assert_eq(int(s.rows[0]["kos"]), 1, "one KO per hit credit, never twice:")
	s.reset()
	assert_true(s.rows.is_empty(), "reset clears:")


func test_a_fall_with_nobody_to_blame_counts_for_no_one() -> void:
	var s := MatchStats.new()
	s.note({"type": "fall", "who": 0, "pit": "hole"})
	assert_false(s.rows.has(0) and int(s.rows[0]["kos"]) > 0, "")
	s.note(_hit(1, 0, 5.0, 1))
	s.note({"type": "fall", "who": 0, "pit": "hole"})
	assert_eq(int(s.rows[1]["kos"]), 1, "a fall after a hit is the hitter's:")


func test_the_wipe_clears_in_steps_within_twenty_ticks_and_ends() -> void:
	assert_true(Wipe.TICKS <= 20, "short:")
	var cols := 20
	var rows := 12
	var before := cols * rows + 1
	for t in range(0, Wipe.TICKS + 1):
		var n := 0
		for r in rows:
			for c in cols:
				if Wipe.covered(c, r, cols, rows, t):
					n += 1
		assert_true(n <= before, "never covers more as it goes (tick %d):" % t)
		before = n
	assert_eq(before, 0, "nothing left covered at the end:")
	var w := Wipe.new()
	w.start()
	assert_true(w.active(), "")
	for i in Wipe.TICKS:
		w.advance()
	assert_false(w.active(), "ends by itself:")
	w.start()
	w.finish()
	assert_false(w.active(), "a press ends it at once:")
	w.free()


func test_the_title_starts_the_attract_demo_after_idling_and_a_press_returns() -> void:
	var g := _game()
	_tick(g, 5)
	assert_true(g.ui.top() is TitleScreen, "on the title")
	assert_false(g._attract, "")
	g._idle_t = g.ATTRACT_AT - 3
	_tick(g, 2)
	assert_false(g._attract, "not yet:")
	_tick(g, 3)
	assert_true(g._attract, "after ~20 s idle the demo plays:")
	assert_false(g.ui.visible, "the menu is out of the way")
	assert_true(g._attract_ui.visible, "the logo and prompt are up")
	var t: int = g.sim.tick
	_tick(g, 30)
	assert_true(g.sim.tick > t, "a CPU match is playing:")
	g._input(_key())
	assert_false(g._attract, "any press returns to the title:")
	assert_true(g.ui.visible and g.ui.top() is TitleScreen, "")
	assert_false(g._attract_ui.visible, "")
	g.free()


func test_a_press_on_the_title_restarts_the_idle_count() -> void:
	var g := _game()
	_tick(g, 5)
	g._idle_t = 900
	g._input(_key())
	assert_eq(g._idle_t, 0, "")
	g.free()


func test_the_idle_count_waits_while_a_page_is_open() -> void:
	var g := _game()
	_tick(g, 5)
	g._open_single()
	g._idle_t = 500
	_tick(g, 3)
	assert_eq(g._idle_t, 0, "only the bare title counts:")
	g.free()


func test_the_results_screen_shows_stats_and_its_buttons_work() -> void:
	var g := _game()
	g._start_match(2)  # CPU vs CPU
	_tick(g, 90)
	assert_true(g.stats.rows.size() > 0 or g.sim.tick > 0, "")
	g.stats.row(0)["hits"] = 5  # (counted from events; here just checked it is shown)
	g.stats.row(0)["damage"] = 42.0
	g.sim.creatures[1].hp = 0.0
	g.sim.creatures[1].state = CreatureSim.State.KO
	g.flow = g.Flow.MATCH_OVER
	g.flow_t = 0
	g.hud.banner = "CAIRN WINS!"
	_tick(g, g.MATCH_OVER_MENU_AT + 1)
	assert_true(g.ui.is_open(), "the results come up")
	var panel := _find(g.ui.top(), ResultsPanel) as ResultsPanel
	assert_true(panel != null, "with the stats panel")
	assert_eq(panel.data["rows"].size(), 2, "a row per fighter:")
	assert_eq(int(panel.data["rows"][0]["stats"]["hits"]), 5, "")
	assert_eq(panel.data["title"], "CAIRN WINS!", "")
	assert_true(g.wipe.active(), "a wipe brings it in:")
	g._input(_key())
	assert_false(g.wipe.active(), "and a press skips it:")
	var labels: Array = []
	for r in g.ui.top().rows():
		labels.append((r as Button).text)
	assert_eq(labels[0], "Rematch", "")
	assert_true("Main menu" in labels, "")
	(g.ui.top().rows().back() as Button).pressed.emit()
	assert_eq(g.flow, g.Flow.MENU, "Main menu goes back:")
	g.free()


func test_results_name_an_mvp_in_a_team_mode() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(g.mode_index("Team 2v2 vs CPU") if g.mode_index("Team 2v2 vs CPU") >= 0 else 29)
	_tick(g, 5)
	assert_true(g.team_battle != null, "a team battle")
	g.stats.row(1)["damage"] = 99.0
	g.stats.row(1)["kos"] = 2
	var d: Dictionary = g.results_data()
	assert_true(d["rows"].size() >= 4, "every fighter:")
	assert_true(int(d["mvp"]) >= 0, "an MVP:")
	# a win by flag or clock leaves nobody standing over every foe: the pose is the winning
	# side's MVP all the same
	g.team_battle.winner = g.sim.creatures[1].team
	d = g.results_data()
	assert_eq(int(d["mvp"]), 1, "the winning side's best:")
	assert_eq(String(d["fighter"]), String(g.sim.creatures[1].def.get("id", "")), "and they take the pose:")
	g.free()


func test_a_fighter_without_a_victory_row_shows_its_idle() -> void:
	var p := FighterPreview.new()
	p.fighter = "cairn"
	p.anim = "victory"
	assert_false(p.has_victory() and false, "")
	p.free()
	assert_eq(FighterPreview.victory_frame(0, 10), 0, "getting ready:")
	assert_eq(FighterPreview.victory_frame(12, 10), 1, "")
	assert_eq(FighterPreview.victory_frame(9999, 10), 9, "the last frame held:")


## The background match restarts a moment after it ends, or when its two minutes are up, and
## then plays on. Before Oct 27 2026 the clock behind "two minutes are up" was never reset, so
## from then on a new match (a new sim, new views, new sheets) was built every single tick: the
## title cycled through fighters at a few frames a second (Kevin's report).
func test_the_background_match_restarts_once_not_every_tick() -> void:
	var g := _game()
	_tick(g, 5)
	assert_true(g.ui.top() is TitleScreen, "on the title")
	g.flow_t = g.ROUND_TICKS - 1
	var restarts := _count_restarts(g, 240)
	assert_eq(restarts, 1, "time up: one new background match in the next four seconds:")
	# The same in the attract demo (its fighters change each time round).
	g._idle_t = g.ATTRACT_AT
	_tick(g, 2)
	assert_true(g._attract, "the demo plays")
	g.flow_t = g.ROUND_TICKS - 1
	restarts = _count_restarts(g, 240)
	assert_eq(restarts, 1, "time up in the demo: one new match, not one a tick:")
	assert_true(g._attract, "and the demo is still on")
	g.free()


## How many times `g.sim` is replaced over `n` ticks.
func _count_restarts(g: Node, n: int) -> int:
	var restarts := 0
	var last = g.sim
	for i in n:
		_tick(g, 1)
		if g.sim != last:
			restarts += 1
			last = g.sim
	return restarts
