extends TestCase
## Training options: No cooldowns and Surge always full (training-only sim flags, saved
## for rollback and replays), Change fighter in place (pause menu or F8), and the
## [training] settings section.

const TEST_SETTINGS := "user://test_training.cfg"
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const DODGE := SimDefs.IN_DODGE
const SURGE := SimDefs.IN_SURGE


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


func _ticks(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


func _training(id := "cairn", flags := {}) -> MatchSim:
	var sim := MatchFactory.training(id)
	assert_true(sim.set_training_flags(flags), "a training match takes the flags")
	return sim


# ------------------------------------------------------------------ the sim flags

func test_no_cooldowns_readies_a_move_on_the_next_tick() -> void:
	var off := _training("cairn")
	tap(off, S2, 0)  # Rockslide Rush: 180 ticks of cooldown
	assert_gt(int(off.creatures[0].cooldowns.get("skill_2", 0)), 0, "without the flag it cools down:")
	assert_false(off.creatures[0].can_use("skill_2"), "")
	var sim := _training("cairn", {"no_cooldowns": true})
	tap(sim, S2, 0)
	var me := sim.creatures[0]
	assert_eq(me.move_id, "skill_2", "the move came out:")
	assert_eq(int(me.cooldowns.get("skill_2", 0)), 0, "its cooldown is cleared the same tick:")
	assert_true(me.can_use("skill_2"), "usable on the next tick")
	run(sim, 0, 40)
	tap(sim, S1, 0)  # Slip (240 ticks)
	assert_true(me.can_use("skill_1"), "every move")


func test_no_cooldowns_keeps_the_dodge_ready_and_the_stamina_full() -> void:
	var sim := _training("cairn", {"no_cooldowns": true})
	var me := sim.creatures[0]
	tap(sim, DODGE, 0)
	assert_eq(me.state, CreatureSim.State.DODGE, "dodged:")
	assert_eq(me.stamina, me.max_stamina, "the stamina is full again:")
	assert_true(me.can_dodge(), "")
	var cer := _training("cerebro", {"no_cooldowns": true})  # a dodge with a cooldown (the blink)
	tap(cer, DODGE, 0)
	assert_eq(cer.creatures[0].state, CreatureSim.State.DODGE, "blinked:")
	assert_true(cer.creatures[0].can_dodge(), "the blink is ready again")
	var plain := _training("cerebro")
	tap(plain, DODGE, 0)
	assert_false(plain.creatures[0].can_dodge(), "without the flag it recharges")


func test_surge_always_full_keeps_the_meter_at_max() -> void:
	var sim := _training("cairn", {"full_energy": true})
	var me := sim.creatures[0]
	run(sim, 0, 1)
	assert_eq(me.energy, CreatureSim.MAX_ENERGY, "full from the first tick:")
	assert_eq(sim.creatures[1].energy, 0.0, "the dummy's isn't touched:")
	tap(sim, SURGE, 0)
	assert_eq(me.move_id, "surge", "the Surge came out:")
	assert_eq(me.energy, CreatureSim.MAX_ENERGY, "and the meter is full again:")
	run(sim, 0, 200)
	tap(sim, SURGE, 0)
	assert_eq(me.move_id, "surge", "again straight away:")
	assert_eq(me.energy, CreatureSim.MAX_ENERGY, "")


func test_flags_are_saved_restored_and_in_the_digest() -> void:
	var sim := _training("cairn")
	var snap := sim.snapshot()
	var before := sim.state_digest()
	sim.set_training_flags({"no_cooldowns": true, "full_energy": true})
	assert_true(sim.state_digest() != before, "the flags are part of the fingerprint")
	assert_eq(sim.snapshot()["training_flags"], {"no_cooldowns": true, "full_energy": true}, "and of the snapshot:")
	sim.restore(snap)
	assert_eq(sim.training_flags, {}, "restore puts them back:")
	assert_eq(sim.state_digest(), before, "")
	# Rolled back mid-match with the flags on, the match re-simulates exactly.
	var on := _training("cairn", {"no_cooldowns": true, "full_energy": true})
	var seq := [S2, 0, 0, SURGE, 0, DODGE, 0, S1, SimDefs.IN_LIGHT, SimDefs.IN_HEAVY]
	for i in 120:
		on.step(PackedInt32Array([seq[i % seq.size()], 0]))
	var mid := on.snapshot()
	for i in 240:
		on.step(PackedInt32Array([seq[(i * 7) % seq.size()], 0]))
	var end := on.state_digest()
	on.set_training_flags({})
	on.restore(mid)
	assert_eq(on.training_flags, {"no_cooldowns": true, "full_energy": true}, "")
	for i in 240:
		on.step(PackedInt32Array([seq[(i * 7) % seq.size()], 0]))
	assert_eq(on.state_digest(), end, "re-simulated from a snapshot:")


func test_only_training_matches_take_the_flags() -> void:
	var all := {"no_cooldowns": true, "full_energy": true}
	var sims := {
		"versus": MatchFactory.versus("cairn", "culvert"),
		"duel": DuelSim.new([["cairn", "culvert", "sno"], ["pete", "digby", "hissy"]]).sim,
		"online 1v1": DuelSim.new([["cairn"], ["culvert"]], DuelSim.rules_for([["cairn"], ["culvert"]])).sim,
		"team": TeamSim.new([["cairn", "sno"], ["pete", "digby"]], 2).sim,
		"brawl": BrawlSim.new(["cairn", "culvert", "sno", "pete"]).sim,
		"online match": OnlineMatch.new([["cairn"], ["culvert"]], 0, 0, null, 1).duel.sim,
		"online team": OnlineMatch.new([["cairn", "sno"], ["pete", "digby"]], 0, 0, null, 1, 2).team.sim,
		"combo trials": ComboTrials.new().build(),
		"reaction drill": ReactionDrill.new("culvert", 1).build(),
	}
	for k in sims:
		var sim: MatchSim = sims[k]
		assert_false(sim.training, "%s is no training match" % k)
		assert_false(sim.set_training_flags(all), "%s refuses the flags" % k)
		assert_eq(sim.training_flags, {}, k)
		sim.training = true  # too late: the match is built
		assert_false(sim.training, "%s can't be made one afterwards" % k)
		sim.training_flags = all  # even forced in, a non-training match ignores them
		sim.creatures[0].energy = 0.0
		sim.step(PackedInt32Array([0, 0, 0, 0, 0, 0]))
		assert_true(sim.creatures[0].energy < CreatureSim.MAX_ENERGY, "%s: no Surge filling" % k)
	var t := MatchFactory.training("cairn")
	t.set_training_flags({"bogus": true, "full_energy": true})
	assert_eq(t.training_flags, {"full_energy": true}, "unknown keys are dropped:")


func test_a_training_replay_with_flags_plays_back() -> void:
	var sim := _training("cairn", {"full_energy": true})
	var rep := Replay.new()
	rep.setup = {"kind": "training", "ids": ["cairn", "dummy"], "arena": sim.arena_id,
		"training_flags": {"full_energy": true}, "flag_changes": [[60, true, true], [150, false, false]]}
	var seq := [SURGE, 0, S2, 0, DODGE, 0, SimDefs.IN_LIGHT, 0]
	for i in 240:
		ReplayBuilder.apply_flag_changes(sim, rep.setup, i)
		var f := PackedInt32Array([seq[(i / 3) % seq.size()], 0])
		rep.record(f)
		sim.step(f)
	var back := Replay.from_dict(JSON.parse_string(JSON.stringify(rep.to_dict())))
	assert_eq(ReplayBuilder.play(back), sim.state_digest(), "saved and played back exactly:")
	var no_changes := Replay.from_dict(JSON.parse_string(JSON.stringify(rep.to_dict())))
	no_changes.setup.erase("flag_changes")
	assert_true(ReplayBuilder.play(no_changes) != sim.state_digest(), "(the changes matter)")


# ------------------------------------------------------------------ the game

func test_the_pause_menu_has_the_training_rows_only_in_training() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(0)  # Cairn vs CPU
	g._open_pause()
	var texts: Array = (g.ui.top() as UiScreen).rows().map(func(r): return r.text if r is Button else "")
	assert_false("Change fighter" in texts, "not in a versus match: %s" % str(texts))
	g._close_ui()
	g._start_match(3)  # Training: Cairn
	g._open_pause()
	texts = (g.ui.top() as UiScreen).rows().map(func(r): return r.text if r is Button else "")
	assert_true("Change fighter" in texts and "Training options" in texts, str(texts))
	g._open_training_options()
	for k in ["no_cooldowns", "full_energy", "dummy_mode"]:
		assert_true(g._setting_rows.has(k), "a %s row" % k)
	(g._setting_rows["no_cooldowns"] as OptionRow).step(1)
	assert_eq(g.sim.training_flags, {"no_cooldowns": true}, "the row turns it on in the match:")
	(g._setting_rows["dummy_mode"] as OptionRow).step(1)
	assert_eq(g.dummy_mode, 1, "the dummy row is the F2 setting:")
	assert_eq(g.hud.dummy_mode_name, "Guard", "")
	g.free()


func test_change_fighter_swaps_in_place_and_restart_keeps_it() -> void:
	var g := _game()
	var was: String = MatchFactory.arena
	MatchFactory.arena = "quarry"
	g._skip_select = true
	g._start_match(3)  # Training: Cairn
	g._set_setting("dummy_mode", 2)
	g._set_setting("full_energy", 1)
	_ticks(g, 30)
	g._open_pause()
	g._open_fighter_swap()
	var pick = g.ui.top()
	assert_true(pick is CharacterSelect, "a fighter grid:")
	assert_eq(String((pick as CharacterSelect).roster[(pick as CharacterSelect).cursor[0]]), "cairn",
		"the cursor starts on your fighter:")
	(pick as CharacterSelect).chosen.emit([["sno"], []])
	assert_false(g.ui.is_open(), "back in the fight:")
	assert_false(g.paused, "")
	assert_eq(String(g.sim.creatures[0].def["id"]), "sno", "the new fighter:")
	assert_true(g.sim.creatures[1].is_dummy, "against the dummy:")
	assert_eq(g.sim.arena_id, "quarry", "on the same arena:")
	assert_eq(g.dummy_mode, 2, "the dummy keeps walking:")
	assert_eq(g.sim.training_flags, {"full_energy": true}, "with the same options:")
	assert_eq(g.sim.tick, 0, "a fresh match")
	assert_gt(g.fade_rect.color.a, 0.5, "under a short fade:")
	_ticks(g, 20)
	assert_eq(g.fade_rect.color.a, 0.0, "gone by now:")
	assert_eq(Presence.describe(g).get("state"), "as Sno Mercy", "the Discord status follows:")
	assert_eq(g.replay.setup["ids"][0], "sno", "a fresh replay of the new fighter:")
	g._start_match(g.mode, true)  # pause > Restart
	assert_eq(String(g.sim.creatures[0].def["id"]), "sno", "Restart keeps the swapped fighter:")
	g._start_round()  # F4
	assert_eq(String(g.sim.creatures[0].def["id"]), "sno", "and so does F4:")
	g._open_menu()
	g._start_match(3)
	assert_eq(String(g.sim.creatures[0].def["id"]), "cairn", "until you leave training:")
	MatchFactory.arena = was
	g.free()


func test_the_change_fighter_key_opens_the_grid() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(0)
	_ticks(g, 3)
	var key := "lol_change_fighter" if g.player_input.layout == "league" else "kb_change_fighter"
	assert_eq(Controls.binding_text(key, g.player_input.layout), "F8", "F8 by default:")
	_press(key)
	assert_false(g.ui.is_open(), "nothing outside training")
	g._start_match(3)
	_ticks(g, 3)
	_press(key)
	assert_true(g.ui.top() is CharacterSelect, "the grid, without the pause menu:")
	assert_true(g.paused, "the fight waits behind it:")
	assert_true(g._tools_help().contains("F8 change fighter"), "the pause menu's Controls page lists it")
	(g.ui.top() as CharacterSelect).cancelled.emit()
	assert_false(g.ui.is_open(), "Back returns to the fight:")
	assert_false(g.paused, "")
	g.free()


func test_it_can_be_rebound_in_each_remap_group() -> void:
	Controls.setup()
	for group in ["classic", "league", "gamepad"]:
		var found := false
		for pair in Controls.REMAP[group]:
			if String(pair[1]) == "Change fighter":
				found = true
		assert_true(found, "a Change fighter row in Remap %s" % group)
	assert_eq(Controls.binding_text("pad_change_fighter", "gamepad"), "-", "no controller button by default:")
	assert_eq(Controls.binding_text("lol_change_fighter", "league"), "F8", "")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F9
	Controls.rebind("classic", "kb_change_fighter", ev)
	assert_eq(Controls.binding_text("kb_change_fighter", "classic"), "F9", "rebound:")
	Controls.reset()
	assert_eq(Controls.binding_text("kb_change_fighter", "classic"), "F8", "reset puts F8 back:")


func test_the_options_are_kept_in_the_training_section() -> void:
	var g := _game()
	assert_eq(g.training_opts, {"no_cooldowns": false, "full_energy": false}, "off by default:")
	g._set_setting("no_cooldowns", 1)
	g._set_setting("full_energy", 1)
	g._set_setting("dummy_mode", 3)
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(cfg.get_value("training", "no_cooldowns"), true, "")
	assert_eq(cfg.get_value("training", "full_energy"), true, "")
	assert_eq(cfg.get_value("training", "dummy_mode"), 3, "")
	g.free()
	var again := _game(true)
	assert_eq(again.training_opts, {"no_cooldowns": true, "full_energy": true}, "kept after a relaunch:")
	assert_eq(again.dummy_mode, 3, "")
	again._skip_select = true
	again._start_match(3)
	assert_eq(again.sim.training_flags, {"no_cooldowns": true, "full_energy": true}, "training starts with them:")
	again._start_match(0)
	assert_eq(again.sim.training_flags, {}, "a versus match doesn't:")
	again._start_match(9)  # Combo Trials
	assert_eq(again.coach.sim.training_flags, {}, "nor Combo Trials:")
	assert_false(again.coach.sim.training, "")
	again.free()


func test_options_changed_mid_training_replay_exactly() -> void:
	var g := _game()
	g._skip_select = true
	g._set_setting("dummy_mode", 2)  # walking, so the dummy's inputs change
	g._start_match(3)
	_ticks(g, 40)
	g._set_setting("full_energy", 1)
	_ticks(g, 40)
	g._set_setting("no_cooldowns", 1)
	g._set_setting("full_energy", 0)
	_ticks(g, 40)
	assert_eq(g.replay.setup["flag_changes"].size(), 3, "each change noted: %s" % str(g.replay.setup["flag_changes"]))
	var back := Replay.from_dict(JSON.parse_string(JSON.stringify(g.replay.to_dict())))
	assert_eq(ReplayBuilder.play(back), g.sim.state_digest(), "the saved replay plays back exactly:")
	g.free()
