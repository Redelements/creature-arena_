extends TestCase
## Replay clips: F6 saves a clip marker beside the replay (ClipMarks, a sidecar the replay
## file never sees), a combo KO by a player here adds one by itself, and
## `--replay=FILE --from=A --to=B` (main_args.gd) starts at tick A of the same fight and
## quits at tick B, which is what Export clip (clip_export.gd) and tools/clip.py render.

const TEST_SETTINGS := "user://test_settings_replay_clips.cfg"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	g.replays_dir = "user://test_clip_replays_%d" % Time.get_ticks_usec()
	_root().add_child(g)
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


func _cleanup(path: String) -> void:
	for p in [path, ClipMarks.sidecar_of(path)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path.get_base_dir()))  # (only once it's empty)


## A recorded Cairn vs CPU fight of `n` ticks, saved with F6's path; returns
## [path, {tick: digest}] (the digests every 50 ticks).
func _recorded(n: int) -> Array:
	var g := _game()
	g._skip_select = true
	g._cpu_vs_cpu = true
	g.seed_base = 7
	g._start_match(0)
	var digests := {}
	for i in n:
		_tick(g, 1)
		if g.replay.frames.size() % 50 == 0:
			digests[g.replay.frames.size()] = g.sim.state_digest()
	var path: String = g._save_replay()
	g.free()
	return [path, digests]


func test_f6_saves_a_clip_marker_beside_the_replay() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(0)
	_tick(g, 200)
	var frames: int = g.replay.frames.size()
	var path: String = g._save_replay()
	assert_true(path != "", "saved:")
	assert_true(FileAccess.file_exists(ClipMarks.sidecar_of(path)), "a sidecar next to it")
	var marks := ClipMarks.load_for(path)
	assert_eq(marks.size(), 1, "one marker:")
	assert_eq(int(marks[0]["at"]), frames, "at the tick F6 was pressed:")
	assert_eq(String(marks[0]["why"]), "F6", "and says why:")
	# The replay itself is untouched by it, and still plays.
	var rep := Replay.load_file(path)
	assert_true(rep != null and rep.frames.size() == frames, "the replay reloads as before")
	assert_false(JSON.parse_string(FileAccess.get_file_as_string(path)).has("clips"), "no markers inside the replay")
	# A second F6 in the same match keeps the first marker.
	_tick(g, 30)
	var path2: String = g._save_replay()
	assert_true(path2 != path, "a second save in the same second gets its own file")
	var marks2 := ClipMarks.load_for(path2)
	assert_eq(marks2.size(), 2, "both markers in the newer save:")
	assert_eq(int(marks2[1]["at"]), frames + 30, "the second where it was pressed:")
	# The theater lists replays, not their sidecars, and counts the clips.
	assert_true(ClipMarks.is_sidecar(ClipMarks.sidecar_of(path).get_file()), "a sidecar is known by its name")
	assert_false(ClipMarks.is_sidecar(path.get_file()), "a replay isn't")
	assert_true(g._replay_label(path2).ends_with("2 clips"), "the theater's row counts them: " + g._replay_label(path2))
	# Watching it: Export clip lists the markers.
	g._play_replay(path2)
	assert_true(g._replaying(), "watching it")
	g.clip_ctl.open_screen(true)
	assert_true(g.paused, "the replay holds while the screen is open")
	var texts: Array = []
	for b in g.ui.top().rows():
		if b is Button:
			texts.append((b as Button).text)
	assert_true(texts.any(func(t): return String(t).ends_with("F6")), "a row per marker: %s" % str(texts))
	g.ui.top().back()
	assert_false(g.paused, "and plays on when it closes")
	g.free()
	_cleanup(path2)
	_cleanup(path)


func test_a_combo_ko_by_a_player_here_adds_a_marker() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(0)  # Cairn (you) vs CPU
	assert_true(g._is_local_fighter(0), "slot 0 is the player")
	assert_false(g._is_local_fighter(1), "slot 1 is the CPU")
	var c := ClipMarks.new()
	var local: Callable = g._is_local_fighter
	var hit := func(att: int, tgt: int, combo: int, t: int):
		c.note({"type": "hit", "attacker": att, "target": tgt, "combo": combo}, t, local)
	for k in 3:
		hit.call(0, 1, k + 1, 100 + k * 10)
	c.note({"type": "ko", "who": 1}, 125, local)
	assert_eq(c.marks.size(), 1, "a 3-hit combo KO by the player:")
	assert_eq(int(c.marks[0]["at"]), 125, "at the KO:")
	hit.call(0, 1, 2, 300)
	c.note({"type": "ko", "who": 1}, 301, local)
	assert_eq(c.marks.size(), 1, "two hits aren't enough")
	hit.call(1, 0, 5, 400)
	c.note({"type": "ko", "who": 0}, 401, local)
	assert_eq(c.marks.size(), 1, "the CPU's combo KO isn't the player's")
	hit.call(0, 1, 4, 500)
	c.note({"type": "ko", "who": 1}, 500 + ClipMarks.KO_WINDOW + 1, local)
	assert_eq(c.marks.size(), 1, "a KO long after the last hit (poison, a pit) isn't a combo's")
	c.reset()
	assert_eq(c.marks.size(), 0, "a new match starts clean")
	# Through main: its events reach the markers (and only while a fight is on).
	g.clips.reset()
	g.clips.note({"type": "hit", "attacker": 0, "target": 1, "combo": 3}, 10, local)
	g.clips.note({"type": "ko", "who": 1}, 11, local)
	assert_eq(g.clips.marks.size(), 1, "main's markers")
	g.free()


func test_replay_from_starts_at_that_tick_of_the_same_fight() -> void:
	var rec := _recorded(300)
	var path: String = rec[0]
	var digests: Dictionary = rec[1]
	var g := _game()
	g._clip_cli = {"path": ProjectSettings.globalize_path(path), "from": 200, "to": 280}
	g.args_ctl.start_replay_cli()
	assert_true(g._replaying(), "watching it")
	assert_eq(g.replay_ctl.tick(), 200, "at --from:")
	assert_eq(g.sim.state_digest(), digests[200], "the same state as the recording there:")
	assert_false(g.hud.show_help, "no key strip over the clip")
	_tick(g, 50)
	assert_eq(g.replay_ctl.tick(), 250, "1x: a tick a frame:")
	assert_eq(g.sim.state_digest(), digests[250], "still the same fight:")
	assert_false(g.args_ctl.clip_over(), "not over before --to")
	assert_eq(ClipExport.range_for(1000, 1452), [400, 1060], "Export clip: the 10 s before a marker and the second after")
	assert_eq(ClipExport.range_for(1452, 1452), [852, 1452], "clamped to the replay")
	var cmd := ClipExport.command("C:/r.json", 400, 1060, "C:/r_clip.avi")
	for want in ["--write-movie", "C:/r_clip.avi", "--replay=C:/r.json", "--from=400", "--to=1060"]:
		assert_true(want in cmd, "the export's command line has %s: %s" % [want, str(cmd)])
	g.free()
	_cleanup(path)


## The real command line, in a second Godot: it plays the range and quits on --to's tick.
func test_replay_from_to_quits_at_the_right_tick() -> void:
	var rec := _recorded(220)
	var path: String = rec[0]
	var exe := OS.get_executable_path()
	var base := ["--headless", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"), "--"]
	var out: Array = []
	var code := OS.execute(exe, PackedStringArray(base + ["--replay=" + ProjectSettings.globalize_path(path),
		"--from=100", "--to=160"]), out, true)
	var text := "\n".join(out)
	assert_eq(code, 0, "exit code:")
	assert_true(text.contains("REPLAY CLIP ticks 100 to 160 of 220"), "started at --from: " + text.right(600))
	assert_true(text.contains("REPLAY CLIP END tick 160 frame 60"), "quit at --to's tick, 60 frames in: " + text.right(600))
	assert_false(text.contains("SCRIPT ERROR"), "no script errors")
	out = []
	code = OS.execute(exe, PackedStringArray(base + ["--replay=" + ProjectSettings.globalize_path(path) + ".missing"]), out, true)
	assert_eq(code, 1, "a missing replay quits with an error:")
	_cleanup(path)
