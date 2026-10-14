extends TestCase
## League-style health bars over the fighters: whose colour each gets, and the trail a
## hit leaves.


func _game() -> Node:
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = "user://test_settings_bars.cfg"
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	return g


func _rels(g: Node) -> Array:
	return g.fx.side_marks.map(func(m): return String(m.get("rel", "")))


func test_you_are_green_the_cpu_is_red() -> void:
	var g := _game()
	g._start_match(0)  # Cairn vs CPU Culvert
	assert_eq(_rels(g), ["self", "enemy"], "you and the CPU:")
	g.free()


func test_nobody_playing_uses_the_side_colours() -> void:
	var g := _game()
	g._start_match(2)  # CPU vs CPU
	assert_eq(_rels(g), ["side", "side"], "CPU vs CPU:")
	g.free()


func test_two_local_players_use_the_side_colours() -> void:
	var g := _game()
	g._start_match(8)  # Versus: 2 players
	g._on_teams_chosen([["cairn"], ["sno"]])
	assert_eq(_rels(g), ["side", "side"], "local versus: both are 'you', so red and blue:")
	g.free()


func test_team_battle_teammates_are_blue() -> void:
	var g := _game()
	g._start_match(30)  # Team battle 3v3 vs CPU
	g._on_teams_chosen([["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]])
	var rels := _rels(g)
	assert_eq(rels.count("self"), 1, "one is you: %s" % str(rels))
	assert_eq(rels.count("ally"), 2, "two teammates")
	assert_eq(rels.count("enemy"), 3, "three foes")
	for i in rels.size():
		var c: CreatureSim = g.sim.creatures[i]
		if rels[i] == "ally":
			assert_eq(c.team, g.sim.creatures[rels.find("self")].team, "allies are on your team")
	g.free()


func test_a_hit_leaves_a_trail_that_drains_to_the_health_left() -> void:
	var fx := FxView.new()
	var sim := MatchFactory.versus("cairn", "sno")
	var c := sim.creatures[0]
	assert_near(fx._trail_step(c, 100.0), 100.0, 0.01, "no damage, no trail:")
	var t := fx._trail_step(c, 70.0)
	assert_near(t, 100.0, 0.01, "a hit: the trail holds where health was:")
	for i in 10:
		t = fx._trail_step(c, 70.0)
	assert_near(t, 100.0, 0.01, "for a moment:")
	for i in 120:
		t = fx._trail_step(c, 70.0)
	assert_near(t, 70.0, 0.01, "then drains down to the health left:")
	assert_near(fx._trail_step(c, 115.0), 115.0, 0.01, "healed (a respawn): no trail")
	fx.free()

