extends TestCase
## Settings > Accessibility (src/view/accessibility.gd, data/accessibility.json): the three rows
## exist, start off, are saved and come back; the colour-safe team set really is told apart
## with colour blindness (Machado 2009's simulation of each kind, CIE76 distance); outlines
## never draw round a fighter the local team can't see (or one in the brush); the hit
## markers' sizes come from the data; `--a11y=` turns them on for a session.

const TEST_SETTINGS := "user://test_accessibility.cfg"
## Machado, Oliveira & Fernandes (2009), severity 1.0, applied to linear RGB.
const CVD := {
	"protanopia": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
	"deuteranopia": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
	"tritanopia": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}
## The least CIE76 distance friend and foe keep under every simulation (about 2.3 is "just
## noticeable"; 30 is plainly different colours), and the two sides' colours.
const MIN_FRIEND_FOE := 30.0
const MIN_SIDES := 60.0


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	return g


func _reset() -> void:
	Accessibility.cli = {}
	Accessibility.teams_saved = 0
	Accessibility.outlines_saved = 0
	Accessibility.markers_saved = 0


# ------------------------------------------------------------------ the rows

func test_the_rows_exist_start_off_and_are_kept() -> void:
	var g := _game()
	var keys: Array = g.SETTING_PAGES["accessibility"]
	assert_eq(keys, ["a11y_teams", "a11y_outlines", "a11y_markers"], "a page of its own")
	for k in keys:
		var info: Dictionary = g._setting(k)
		assert_eq(int(info["index"]), 0, k + " is off by default")
		assert_true(String(info["desc"]) != "", k + " says what it does")
	assert_eq(g._setting("a11y_outlines")["values"], ["Off", "Team", "High contrast"], "outline choices")
	g._open_settings_page("accessibility")
	assert_eq(g.ui.top().title, "ACCESSIBILITY", "the page opens")
	assert_true(g._setting_rows.has("a11y_markers"), "its rows are built")
	g._set_setting("a11y_teams", 1)
	g._set_setting("a11y_outlines", 2)
	g._set_setting("a11y_markers", 1)
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(int(cfg.get_value("accessibility", "teams", -1)), 1, "saved under [accessibility]")
	assert_eq(int(cfg.get_value("accessibility", "outlines", -1)), 2, "outlines saved")
	assert_eq(int(cfg.get_value("accessibility", "markers", -1)), 1, "markers saved")
	g.free()
	_reset()
	var again: Node = load("res://scenes/main.tscn").instantiate()
	again.settings_path = TEST_SETTINGS
	(Engine.get_main_loop() as SceneTree).root.add_child(again)
	assert_eq(Accessibility.teams(), Accessibility.Teams.SAFE, "loaded again")
	assert_eq(Accessibility.outlines(), Accessibility.Outlines.HIGH_CONTRAST, "outlines loaded")
	assert_eq(Accessibility.markers(), Accessibility.Markers.HIGH_CONTRAST, "markers loaded")
	again.free()
	_reset()


func test_a_fresh_game_has_them_all_off() -> void:
	Accessibility.teams_saved = 1  # left over from an earlier game in this run
	var g := _game()
	assert_eq(Accessibility.teams(), 0, "no settings file: default colours")
	assert_eq(Accessibility.outlines(), 0, "no outlines")
	assert_eq(Accessibility.markers(), 0, "default hit markers")
	assert_eq(Accessibility.side_color(0), Color("ff5a5a"), "the old red")
	assert_eq(Accessibility.side_color(1), Color("5aa0ff"), "the old blue")
	assert_eq(Accessibility.rel_color("self", Color.BLACK), Color("6fcf5a"), "the old self green")
	g.free()
	_reset()


func test_the_flag_turns_them_on_for_the_session_and_a_row_wins_after() -> void:
	assert_eq(Accessibility.parse_flag("teams,outlines,markers"),
		{"teams": 1, "outlines": 2, "markers": 1}, "all three, outlines at High contrast")
	assert_eq(Accessibility.parse_flag("outlines=team"), {"outlines": 1}, "Team outlines")
	assert_eq(Accessibility.parse_flag("all").size(), 3, "all")
	var g := _game()
	Accessibility.cli = Accessibility.parse_flag("teams")
	assert_eq(Accessibility.teams(), 1, "the flag wins over the setting")
	g._set_setting("a11y_teams", 0)
	assert_eq(Accessibility.teams(), 0, "until the row is changed")
	g.free()
	_reset()


# ------------------------------------------------------------------ colours

func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


func _lab(rgb: Array) -> Vector3:
	var r: float = rgb[0]
	var gg: float = rgb[1]
	var b: float = rgb[2]
	var x := (0.4124 * r + 0.3576 * gg + 0.1805 * b) / 0.95047
	var y := 0.2126 * r + 0.7152 * gg + 0.0722 * b
	var z := (0.0193 * r + 0.1192 * gg + 0.9505 * b) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = f.call(x)
	var fy: float = f.call(y)
	var fz: float = f.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func _seen(c: Color, m: Array) -> Vector3:
	var l := [_lin(c.r), _lin(c.g), _lin(c.b)]
	var out := []
	for row in m:
		out.append(clampf(float(row[0]) * l[0] + float(row[1]) * l[1] + float(row[2]) * l[2], 0.0, 1.0))
	return _lab(out)


## The least CIE76 distance between two colours under any of the three simulations.
func _least(a: Color, b: Color) -> float:
	var least := INF
	for kind in CVD:
		least = minf(least, _seen(a, CVD[kind]).distance_to(_seen(b, CVD[kind])))
	return least


func test_colour_safe_friend_and_foe_stay_apart_with_colour_blindness() -> void:
	var safe := Accessibility.Teams.SAFE
	var foe := Accessibility.rel_color("enemy", Color.BLACK, safe)
	for friend in ["self", "ally"]:
		var d := _least(Accessibility.rel_color(friend, Color.BLACK, safe), foe)
		assert_gt(d, MIN_FRIEND_FOE, "%s vs enemy, least CIE76 under protan / deutan / tritan: %.1f" % [friend, d])
	var sides := _least(Accessibility.side_color(0, safe), Accessibility.side_color(1, safe))
	assert_gt(sides, MIN_SIDES, "left vs right side: %.1f" % sides)
	# The point of it: the default self green against the enemy red nearly vanish for deuteranopia.
	var old := _least(Accessibility.rel_color("self", Color.BLACK, 0), Accessibility.rel_color("enemy", Color.BLACK, 0))
	var now := _least(Accessibility.rel_color("self", Color.BLACK, safe), foe)
	assert_lt(old, MIN_FRIEND_FOE, "the default pair is the problem (%.1f)" % old)
	assert_gt(now, old * 2.0, "colour-safe more than doubles it")
	# Brawl's four: every pair better apart than the default four.
	var worst := [INF, INF]
	for which in 2:
		for i in 4:
			for j in range(i + 1, 4):
				worst[which] = minf(worst[which], _least(Accessibility.brawl_color(i, which), Accessibility.brawl_color(j, which)))
	assert_gt(worst[1], worst[0], "Brawl colours: %.1f against the default %.1f" % [worst[1], worst[0]])
	# Lightness differs too, not hue alone (L* of friend and foe at least 15 apart).
	assert_gt(absf(_lab([_lin(foe.r), _lin(foe.g), _lin(foe.b)]).x
		- _lab([_lin(Accessibility.rel_color("ally", Color.BLACK, safe).r), _lin(Accessibility.rel_color("ally", Color.BLACK, safe).g),
			_lin(Accessibility.rel_color("ally", Color.BLACK, safe).b)]).x), 15.0, "ally and enemy differ in lightness")


func test_team_colours_reach_the_bars_and_the_hud() -> void:
	var g := _game()
	g._start_match(0)  # Cairn vs CPU
	g._physics_process(1.0 / 60.0)
	assert_eq(g.fx.mark_color(1), Color("e5534b"), "the CPU's bar: the default enemy red")
	g._set_setting("a11y_teams", 1)
	assert_eq(g.fx.mark_color(1), Color("d55e00"), "colour-safe: vermillion, at once")
	assert_eq(g.fx.mark_color(0), Color("f0e442"), "yours: yellow")
	assert_eq(g._team_color(1), Color("56b4e9"), "the side colour everything else reads")
	g.free()
	_reset()


# ------------------------------------------------------------------ outlines

func _outline(v: CreatureView) -> float:
	return float(v.mat.get_shader_parameter("outline"))


func test_outlines_draw_in_the_marker_colour_or_black_and_white() -> void:
	var g := _game()
	g._start_match(0)
	g._physics_process(1.0 / 60.0)
	assert_eq(_outline(g.views[1]), 0.0, "off by default")
	g._set_setting("a11y_outlines", Accessibility.Outlines.TEAM)
	g._physics_process(1.0 / 60.0)
	assert_gt(_outline(g.views[1]), 0.0, "Team: on")
	assert_eq(g.views[1].mat.get_shader_parameter("outline_outer"), g.fx.mark_color(1), "in its bar's colour")
	assert_eq(float((g.views[1].mat.get_shader_parameter("outline_inner") as Color).a), 0.0, "no inner ring")
	g._set_setting("a11y_outlines", Accessibility.Outlines.HIGH_CONTRAST)
	g._physics_process(1.0 / 60.0)
	assert_eq(g.views[0].mat.get_shader_parameter("outline_outer"), Color.WHITE, "High contrast: white outside")
	assert_eq(g.views[0].mat.get_shader_parameter("outline_inner"), Color.BLACK, "round a black edge")
	g.free()
	_reset()


const BRUSH := {"kind": "brush", "rect": [40, 14, 8, 8]}


func test_outlines_never_show_a_fighter_the_local_team_cant_see() -> void:
	var g := _game()
	g._start_match(0)  # Cairn vs CPU
	Accessibility.outlines_saved = Accessibility.Outlines.HIGH_CONTRAST
	var sim: MatchSim = g.sim
	sim.terrain.load_map({"pieces": [BRUSH]})
	g.vision.clear()
	sim.creatures[0].pos = sim.terrain.cell_center(Vector2i(12, 17))
	sim.creatures[1].pos = sim.terrain.cell_center(Vector2i(43, 17))
	sim.step(PackedInt32Array([0, 0]))
	g._update_vision([])
	assert_true(g._is_hidden(1), "the CPU in the brush is hidden from you")
	for v in g.views:
		v.out_of_sight = g._is_hidden(v.c.id)
		v.refresh()
	assert_false(g.views[1].visible, "not drawn")
	assert_eq(_outline(g.views[1]), 0.0, "and no outline either")
	assert_false(g.views[1].outline_allowed(), "never allowed while hidden")
	assert_gt(_outline(g.views[0]), 0.0, "you in the open: outlined")
	# Your own fighter in the brush: a faint shape on your screen, but no outline to point at it.
	sim.creatures[0].pos = sim.terrain.cell_center(Vector2i(41, 15))
	sim.creatures[1].pos = sim.terrain.cell_center(Vector2i(12, 17))
	sim.step(PackedInt32Array([0, 0]))
	g._update_vision([])
	assert_true(sim.creatures[0].covered, "you're in the brush")
	g.views[0].out_of_sight = g._is_hidden(0)
	g.views[0].refresh()
	assert_true(g.views[0].visible, "you still see yourself")
	assert_eq(_outline(g.views[0]), 0.0, "without an outline")
	# Invisible (Tiptoe-style stealth): none either.
	sim.creatures[1].stealth = 30
	g.views[1].out_of_sight = false
	g.views[1].refresh()
	assert_eq(_outline(g.views[1]), 0.0, "an invisible fighter gets none")
	g.free()
	_reset()


# ------------------------------------------------------------------ hit markers

func _hit(fx: FxView, power := 5.0) -> Dictionary:
	fx._incoming.clear()
	fx._hit_sparks({"type": "hit", "pos": Vector2(200, 150), "power": power, "attacker": -1, "target": 1}, Vector2(200, 150), Vector2.RIGHT)
	for p in fx._incoming:
		if String(p["kind"]) == "burst":
			return p
	return {}


func test_hit_markers_scale_from_the_data() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var fx := FxView.new()
	fx.sim = sim
	fx.unseen = [false, false]
	var plain := _hit(fx)
	assert_eq(float(plain.get("edge", -1.0)), 0.0, "default: no outline on the rays")
	var plain_size := fx._dmg_size(5.0, "light")
	Accessibility.markers_saved = Accessibility.Markers.HIGH_CONTRAST
	var hc: Dictionary = Accessibility.data()["hit_markers"]["high_contrast"]
	var big := _hit(fx)
	assert_near(float(big["r1"]), float(plain["r1"]) * float(hc["spark_scale"]), 0.001, "rays reach spark_scale further")
	assert_near(float(big["width"]), float(plain["width"]) + float(hc["spark_width_add"]), 0.001, "and are wider")
	assert_eq(float(big["edge"]), float(hc["spark_outline_width"]), "with a dark outline")
	assert_eq(fx._dmg_size(5.0, "light"), plain_size + int(hc["number_size_add"]), "damage numbers a step bigger")
	assert_gt(float(hc["spark_scale"]), 1.0, "high contrast is bigger")
	assert_true(bool(hc["full_flash"]), "and flashes white on every hit")
	fx.free()
	_reset()


func test_every_page_has_its_strings_in_data() -> void:
	var d := Accessibility.data()
	for set_id in Accessibility.TEAM_SETS:
		var s: Dictionary = d["teams"][set_id]
		for k in ["sides", "brawl", "self", "ally", "enemy", "neutral"]:
			assert_true(s.has(k), "%s has %s" % [set_id, k])
		assert_eq((s["sides"] as Array).size(), 2, set_id + ": two sides")
		assert_eq((s["brawl"] as Array).size(), 4, set_id + ": four Brawl colours")
	for k in ["team", "high_contrast"]:
		assert_true(d["outlines"].has(k), "outline style " + k)
	var keys: Array = d["hit_markers"]["default"].keys()
	keys.sort()
	var hk: Array = d["hit_markers"]["high_contrast"].keys()
	hk.sort()
	assert_eq(hk, keys, "both hit-marker blocks name the same keys")
