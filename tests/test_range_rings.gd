extends TestCase
## Range rings (Settings > Controls, F7 in a fight): the floor ring for each active hit,
## projectiles and bodies, the setting kept across launches, and the toggle mid-match.

const TEST_SETTINGS := "user://test_range_rings.cfg"
const L := SimDefs.IN_LIGHT


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _game(keep := false) -> Node:
	if not keep and FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	return g


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_root().push_input(ev)


## A ring in `rings` at `at` with `radius` (within half a pixel), or null.
func _find(rings: Array, at: Vector2, radius: float) -> Variant:
	for r in rings:
		if (r[0] as Vector2).distance_to(at) < 0.5 and absf(float(r[1]) - radius) < 0.5:
			return r
	return null


func test_an_active_hit_draws_its_reach_then_fades() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var rr := RangeRings.new()
	rr.set_sim(sim)
	var a := sim.creatures[0]
	sim.step(PackedInt32Array([L, 0]))
	var guard := 0
	while a.active_seg() < 0 and guard < 60:
		sim.step(PackedInt32Array([0, 0]))
		rr.advance()
		guard += 1
	assert_true(a.active_seg() >= 0, "the jab goes active")
	rr.advance()
	var want := a.hit_radius(a.active_seg()) + RangeRings.BODY_PAD
	var ring = _find(rr.rings(), a.hit_center(a.active_seg()), want)
	assert_true(ring != null, "a ring at the hit centre, hit radius + a body")
	assert_near((ring[2] as Color).a, RangeRings.ALPHA, 0.01, "full strength while active:")
	assert_eq(Color(ring[2]).r, RangeRings.colour_of(a).r, "in the attacker's colour")
	var center := a.hit_center(a.active_seg())
	while a.active_seg() >= 0:
		sim.step(PackedInt32Array([0, 0]))
		rr.advance()
	ring = _find(rr.rings(), center, want)
	assert_true(ring != null and (ring[2] as Color).a < RangeRings.ALPHA, "it fades once the strike ends")
	for i in RangeRings.FADE_TICKS:
		sim.step(PackedInt32Array([0, 0]))
		rr.advance()
	assert_eq(_find(rr.rings(), center, want), null, "gone after the fade")
	assert_true(_find(rr.rings(), a.pos, a.radius) != null, "the body ring stays")
	rr.free()


func test_the_ring_is_the_same_size_facing_any_way() -> void:
	var sizes := {}
	for f in [Vector2.RIGHT, Vector2.DOWN, Vector2.UP, Vector2(-0.6, 0.8)]:
		var sim := MatchFactory.versus("cairn", "culvert")
		var a := sim.creatures[0]
		a.facing = f
		a._start_attack("light_1", sim)
		while a.active_seg() < 0:
			sim.step(PackedInt32Array([0, 0]))
		var rr := RangeRings.new()
		rr.set_sim(sim)
		rr.advance()
		var ring = _find(rr.rings(), a.hit_center(a.active_seg()), a.hit_radius(a.active_seg()) + RangeRings.BODY_PAD)
		assert_true(ring != null, "a ring facing %s" % f)
		sizes[snappedf(float(ring[1]), 0.01)] = true
		assert_near(((ring[0] as Vector2) - a.pos).length(), a.seg_value(a.active_seg(), "reach"), 0.01,
			"centred at the reach in front, facing %s:" % f)
		rr.free()
	assert_eq(sizes.size(), 1, "one radius for every direction:")


func test_projectiles_and_lobs_get_a_ring() -> void:
	var sim := MatchFactory.versus("cerebro", "culvert")
	var rr := RangeRings.new()
	rr.set_sim(sim)
	sim.projectiles.append({"owner": 0, "pos": Vector2(200, 150), "vel": Vector2(6, 0), "life": 10, "radius": 5.0})
	sim.projectiles.append({"owner": 0, "pos": Vector2(200, 120), "vel": Vector2(4, 0), "life": 5, "radius": 0.0,
		"lob": true, "burst": 24.0})
	var rings := rr.rings()
	assert_true(_find(rings, Vector2(200, 150), 5.0 + RangeRings.BODY_PAD) != null, "a shot: its radius + a body")
	assert_true(_find(rings, Vector2(220, 120), 24.0 + RangeRings.BODY_PAD) != null,
		"a lob: its burst, where it will land")
	rr.free()


func test_a_stealthed_foe_keeps_its_body_ring_hidden() -> void:
	var sim := MatchFactory.versus("cairn", "pete")
	var rr := RangeRings.new()
	rr.set_sim(sim)
	rr.rel = ["self", "enemy"]
	var pete := sim.creatures[1]
	pete.stealth = 60
	assert_eq(_find(rr.rings(), pete.pos, pete.radius), null, "no body ring for a hidden foe")
	rr.rel = ["enemy", "self"]
	assert_true(_find(rr.rings(), pete.pos, pete.radius) != null, "but its own player sees it")
	rr.free()


func test_the_setting_is_kept_and_on_the_controls_page() -> void:
	var g := _game()
	assert_false(g.range_rings, "off by default")
	assert_false(g.rings.visible, "")
	g._open_controls()
	assert_true(g._setting_rows.has("range_rings"), "a row on the Controls page")
	assert_eq(g._setting("range_rings")["desc"], "Show each attack's real hit area on the floor", "")
	g._set_setting("range_rings", 1)
	assert_true(g.range_rings and g.rings.visible, "On shows them")
	g.free()
	var again := _game(true)
	assert_true(again.range_rings, "kept after a restart")
	assert_true(again.rings.visible, "and showing")
	again.free()


func test_the_key_toggles_it_mid_match_and_saves() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(0)
	for i in 5:
		g._physics_process(1.0 / 60.0)
	var key := "lol_range_rings" if g.player_input.layout == "league" else "kb_range_rings"
	assert_eq(Controls.binding_text(key, g.player_input.layout), "F7", "F7 by default:")
	_press(key)
	assert_true(g.range_rings, "the key turns them on")
	assert_true(g.rings.visible, "")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(cfg.get_value("game", "range_rings"), true, "and saves it")
	assert_true(g._tools_help().contains("F7 range rings"), "the pause menu's Controls page lists it")
	_press(key)
	assert_false(g.range_rings, "again turns them off")
	assert_false(g.debug.visible, "independent of the F1 overlay")
	g.free()


func test_it_can_be_rebound_in_each_remap_group() -> void:
	Controls.setup()
	for group in ["classic", "league", "gamepad"]:
		var found := false
		for pair in Controls.REMAP[group]:
			if String(pair[1]) == "Range rings":
				found = true
		assert_true(found, "a Range rings row in Remap %s" % group)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F8
	Controls.rebind("classic", "kb_range_rings", ev)
	assert_eq(Controls.binding_text("kb_range_rings", "classic"), "F8", "rebound:")
	assert_true(Controls.overrides().has("kb_range_rings"), "saved with the other bindings")
	Controls.reset()
	assert_eq(Controls.binding_text("kb_range_rings", "classic"), "F7", "reset puts F7 back:")


func test_a_foe_the_team_cant_see_gets_no_rings() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var fx := FxView.new()
	fx.sim = sim
	fx.unseen = [false, true]  # Vision: the foe is hidden from the local team
	var rr := RangeRings.new()
	rr.fx = fx
	rr.set_sim(sim)
	var foe := sim.creatures[1]
	foe._start_attack("light_1", sim)
	while foe.active_seg() < 0:
		sim.step(PackedInt32Array([0, 0]))
	rr.advance()
	assert_eq(_find(rr.rings(), foe.pos, foe.radius), null, "no body ring")
	assert_eq(_find(rr.rings(), foe.hit_center(foe.active_seg()), foe.hit_radius(foe.active_seg()) + RangeRings.BODY_PAD),
		null, "no ring for its swing")
	fx.unseen = [false, false]
	assert_true(_find(rr.rings(), foe.hit_center(foe.active_seg()), foe.hit_radius(foe.active_seg()) + RangeRings.BODY_PAD)
		!= null, "seen again: its ring shows")
	rr.free()
	fx.free()
