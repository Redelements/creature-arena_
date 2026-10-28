extends TestCase
## The Replay theater's viewer (replay_viewer.gd) and the bug-report zip (bug_report.gd):
## pause and one-tick steps, slow motion and fast forward at their exact rates, jumps that
## land on the same state as playing straight there (keyframes or not), a jump past the end
## that ends the replay cleanly, and a bug report that holds the expected files and none of
## the online id, secret or address.

const TEST_SETTINGS := "user://test_settings_replay_tools.cfg"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	g.replays_dir = "user://test_replays_tools_%d" % Time.get_ticks_usec()
	_root().add_child(g)
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


## Records `ticks` of a mode (CPU vs CPU) and starts watching it; returns the file.
func _watch(g: Node, mode: int, ticks: int) -> String:
	g._cpu_vs_cpu = true
	g._skip_select = true
	g._start_match(mode)
	_tick(g, ticks)
	var path: String = g.replays_dir.path_join("replay_test_%d.json" % Time.get_ticks_usec())
	assert_eq(g.replay.save(path), OK, "saved:")
	g._play_replay(path)
	assert_true(g._replaying(), "watching")
	return path


func _digest(g: Node) -> String:
	return g.replay_ctl._stepper().state_digest()


func _clean(g: Node) -> void:
	var dir: String = g.replays_dir
	g.free()
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func test_pause_and_step_move_exactly_one_tick() -> void:
	var g := _game()
	_watch(g, 2, 300)  # a CPU vs CPU Versus round
	_tick(g, 120)
	var t: int = g.sim.tick
	assert_eq(t, 120, "one tick a frame at 1x:")
	g.replay_ctl.toggle()
	_tick(g, 10)
	assert_eq(g.sim.tick, t, "paused: nothing steps")
	g.replay_ctl.step()
	_tick(g, 1)
	assert_eq(g.sim.tick, t + 1, "a step is one tick:")
	_tick(g, 5)
	assert_eq(g.sim.tick, t + 1, "and only one")
	g.replay_ctl.step_back()
	assert_eq(g.sim.tick, t, "a step back is one tick:")
	g.replay_ctl.toggle()
	_tick(g, 3)
	assert_eq(g.sim.tick, t + 3, "playing again:")
	assert_true(String(g.hud.help_text).begins_with("REPLAY"), "the HUD line shows the viewer: " + g.hud.help_text)
	_clean(g)


func test_slow_motion_and_fast_forward_step_at_their_rates() -> void:
	var g := _game()
	_watch(g, 2, 400)
	_tick(g, 100)
	for row in [[1, 8, 4], [0, 8, 2], [3, 4, 8], [2, 6, 6]]:  # [speed, frames, ticks]: 1/2, 1/4, 2x, 1x
		g.replay_ctl.set_speed(int(row[0]))
		var t: int = g.sim.tick
		_tick(g, int(row[1]))
		assert_eq(g.sim.tick - t, int(row[2]), "%s over %d frames:" % [ReplayViewer.SPEED_NAMES[row[0]], row[1]])
	_clean(g)


## A jump back (or on) to tick T: the same state as playing straight to T, in a Versus
## round (in its intro and in the fight) and a Chaos Cup Brawl (mutators); playing on from
## there reaches the same state as before.
func test_a_jump_reaches_the_same_state_as_playing_there() -> void:
	for mode_name in ["", "Chaos Cup", "Team 2v2 vs CPU"]:
		var g := _game()
		var mode: int = 2 if mode_name == "" else g.mode_index(mode_name)
		_watch(g, mode, 700)
		var seen := {}
		for t in [40, 200, 250, 333, 600]:
			_tick(g, t - g.sim.tick)
			assert_eq(g.sim.tick, t, "%s: at %d" % [mode_name, t])
			seen[t] = _digest(g)
		for t in [333, 40, 250, 0, 600, 200]:
			g.replay_ctl.seek(t)
			assert_eq(g.sim.tick, t, "%s: jumped to %d" % [mode_name, t])
			if seen.has(t):
				assert_eq(_digest(g), seen[t], "%s: the same state at %d:" % [mode_name, t])
		g.replay_ctl.seek(200)
		_tick(g, 133)
		assert_eq(_digest(g), seen[333], "%s: played on from a jump, the same at 333:" % mode_name)
		if mode_name == "":
			g.replay_ctl.seek(40)
			assert_eq(g.flow, g.Flow.INTRO, "back in the round's intro")
			g.replay_ctl.seek(250)
			assert_eq(g.flow, g.Flow.FIGHT, "and in the fight")
			assert_eq(g.timer, g.ROUND_TICKS - (250 - g.INTRO_TICKS), "with its clock:")
		_clean(g)


func test_a_jump_past_the_end_stops_cleanly() -> void:
	for mode in [2, 29]:
		var g := _game()
		_watch(g, mode, 300)
		_tick(g, 50)
		g.replay_ctl.seek(100000)
		assert_eq(g.sim.tick, 300, "clamped to the recording:")
		_tick(g, 400)
		assert_eq(g.flow, g.Flow.MATCH_OVER, "the replay ends:")
		assert_eq(g.hud.banner, "END OF REPLAY", "and says so:")
		g.replay_ctl.seek(10)  # from the end screen: watching again
		assert_true(g.flow != g.Flow.MATCH_OVER and not g.ui.is_open(), "watching again")
		_tick(g, 20)
		assert_eq(g.sim.tick, 30, "from there:")
		_clean(g)


func test_the_replay_keys_are_bound_for_every_device_and_reserve_nothing() -> void:
	Controls.setup()
	for k in ReplayViewer.KEYS:
		var action := String(k[0])
		assert_true(InputMap.has_action(action), action)
		var events := InputMap.action_get_events(action)
		assert_true(not events.is_empty(), action + " has keys")
		for ev in events:
			assert_eq(ev.device, Controls.ALL_DEVICES, action + " on every device:")
			if ev is InputEventKey:
				assert_false((ev as InputEventKey).physical_keycode in RemapScreen.RESERVED_KEYS, action + " takes no reserved key")
	assert_true(ReplayViewer.help_text().contains("one tick on"), "the pause menu's Controls page lists them")


func test_a_bug_report_holds_the_files_and_no_secrets() -> void:
	var g := _game()
	Netplay.player_id = "testplayerid12345"
	Netplay.player_secret = "f00d".repeat(16)
	g._online_address = "10.1.2.3:7777"
	g.settings_ctl._save_settings()
	print("bug report test: id ", Netplay.player_id)  # into the log, to be blanked out
	var f := FileAccess.open(BugReport.PERF, FileAccess.WRITE)
	f.store_string("PERF test\n")
	f.close()
	g._cpu_vs_cpu = true
	g._skip_select = true
	g._start_match(2)
	_tick(g, 150)  # a match in progress: saved as a replay first
	var dir := "user://test_bug_reports_%d" % Time.get_ticks_usec()
	var path := BugReport.write(g, dir)
	assert_true(path.ends_with(".zip") and FileAccess.file_exists(path), "written: " + path)
	var zip := ZIPReader.new()
	assert_eq(zip.open(path), OK, "a zip:")
	var names := Array(zip.get_files()).filter(func(n): return not String(n).ends_with("/"))  # (folders listed too)
	for want in ["system.txt", "settings.cfg", "perf.txt"]:
		assert_true(want in names, "holds %s: %s" % [want, str(names)])
	if FileAccess.file_exists(Progress.path):
		assert_true("progress.json" in names, "holds progress.json")
	var replays := names.filter(func(n): return String(n).begins_with("replay/"))
	assert_eq(replays.size(), 1, "the match in progress, saved as a replay:")
	var logs := names.filter(func(n): return String(n).begins_with("logs/"))
	assert_true(logs.size() >= 1 and logs.size() <= BugReport.LOGS, "the newest logs: " + str(logs))
	for n in names:
		assert_false(String(n).contains("ratings") or String(n).contains("online") or String(n).begins_with(".env"),
			"nothing else: " + String(n))
		var text := zip.read_file(String(n)).get_string_from_utf8()
		assert_false(text.contains(Netplay.player_secret), "no secret in " + String(n))
		assert_false(text.contains(Netplay.player_id), "no player id in " + String(n))
		assert_false(text.contains("10.1.2.3"), "no server address in " + String(n))
	var settings := zip.read_file("settings.cfg").get_string_from_utf8()
	assert_true(settings.contains("[video]"), "the settings are there")
	var sys := zip.read_file("system.txt").get_string_from_utf8()
	assert_true(sys.contains("NET_VERSION") and sys.contains("gpu:") and sys.contains("controllers:"), sys)
	zip.close()
	for n in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(n))
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(BugReport.PERF)
	Netplay.player_id = ""
	Netplay.player_secret = ""
	_clean(g)
