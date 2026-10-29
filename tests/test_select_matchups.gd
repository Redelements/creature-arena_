extends TestCase
## The fighter select's "Beats mages  ·  Loses to fighters" line under the class line:
## every fighter's class gets one, it says what the CPU's table (CpuController.BEATS)
## says, it fits the panel on one line, and the pick screen shows it on both panels (the
## CPU's picks too) and on the online pick screen.


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## The classes `role` loses to, worked out here from BEATS (not through the menu's code).
func _losers_to(role: String) -> Array:
	var out: Array = []
	for other in CpuController.BEATS:
		if role in CpuController.BEATS[other]:
			out.append(String(other))
	return out


## The class names a part of the line lists ("the rest": every other class but `skip`'s).
func _named(part: String, role: String, skip: Array) -> Array:
	if part == "the rest":
		return CpuController.BEATS.keys().filter(func(r): return r != role and not (r in skip))
	var out: Array = []
	for w in part.split(", "):
		out.append(String(w).trim_suffix("s"))
	return out


func _sorted(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b


func test_every_class_gets_a_line_that_agrees_with_the_cpus_table() -> void:
	var font := UiTheme.font()
	for id in MatchFactory.FIGHTERS:
		var role := String(MatchFactory.load_def(id).get("role", ""))
		assert_true(role in CpuController.BEATS, "%s's class '%s' is in the triangle" % [id, role])
		var text := CharacterSelect.matchup_text(role, font, CharacterSelect.MATCHUP_W)
		assert_true(text != "", "%s (%s) has a matchup line" % [id, role])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(6)).x
		assert_true(w <= CharacterSelect.MATCHUP_W, "%s's line fits the panel: '%s' %d > %d" % [id, text, w,
			CharacterSelect.MATCHUP_W])
		var short := text.contains(" / ")
		var parts := text.split(" / " if short else "  ·  ")
		var beats_pre := "Beats: " if short else "Beats "
		var loses_pre := "Loses to: " if short else "Loses to "
		var beats: Array = CpuController.BEATS[role]
		var loses := _losers_to(role)
		var got_beats: Array = []
		var got_loses: Array = []
		for p in parts:
			if p.begins_with(beats_pre):
				got_beats = _named(p.trim_prefix(beats_pre), role, loses)
			elif p.begins_with(loses_pre):
				got_loses = _named(p.trim_prefix(loses_pre), role, beats)
			else:
				assert_true(false, "%s: unknown part '%s' in '%s'" % [id, p, text])
		assert_eq(_sorted(got_beats), _sorted(beats), "%s beats what BEATS says ('%s'):" % [id, text])
		assert_eq(_sorted(got_loses), _sorted(loses), "%s loses to what BEATS says ('%s'):" % [id, text])
	# The long form where it fits; plural names joined with commas.
	assert_eq(CharacterSelect.matchup_text("fighter"), "Beats assassins  ·  Loses to mages", "a fighter:")
	assert_eq(CharacterSelect.matchup_text("mage"), "Beats fighters, tanks, bruisers, skirmishers  ·  Loses to assassins",
		"a mage, unmeasured:")
	assert_eq(CharacterSelect.matchup_text("nobody"), "", "a class outside the triangle: no line")


func test_the_pick_screen_shows_it_on_both_panels_and_online() -> void:
	var cs := CharacterSelect.new()
	_root().add_child(cs)
	for side in 2:
		var lbl: Label = cs._matchups[side]
		assert_eq(lbl.get_theme_color("font_color"), UiTheme.C_DIM, "side %d: the secondary text colour" % side)
		for id in MatchFactory.FIGHTERS:
			cs.cursor[side] = cs.roster.find(id)
			cs._refresh()
			var role := String(MatchFactory.load_def(id)["role"])
			assert_eq(lbl.text, CharacterSelect.matchup_text(role, UiTheme.font(), CharacterSelect.MATCHUP_W),
				"side %d on %s:" % [side, id])
		cs.cursor[side] = cs.roster.find(CharacterSelect.RANDOM)
		cs._refresh()
		assert_eq(lbl.text, "", "side %d on Random: no line" % side)
	cs.free()
	# Online: player 1's panel has it; the other panel says what happens next.
	cs = CharacterSelect.new()
	cs.solo = true
	cs.solo_heading = "ONLINE"
	_root().add_child(cs)
	cs.cursor[0] = cs.roster.find("digby")
	cs.cursor[1] = cs.roster.find("digby")
	cs._refresh()
	assert_eq((cs._matchups[0] as Label).text, CharacterSelect.matchup_text("assassin", UiTheme.font(),
		CharacterSelect.MATCHUP_W), "online: player 1's panel")
	assert_eq((cs._matchups[1] as Label).text, "", "online: no line on the what-next panel")
	cs.free()

