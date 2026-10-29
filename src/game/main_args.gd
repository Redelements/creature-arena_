extends RefCounted
class_name MainArgs
## The command line for main (the flags after `--`, listed in main.gd's header):
## `_parse_args` sets main's session options and returns the mode to start (-1: the menu);
## `--server` → `_run_server`, `--sim-check` → `_run_sim_check`. Moved out of main.gd
## verbatim; everything it sets is still main's (`main`).

const Main := preload("res://src/game/main.gd")

var main: Main


func _init(p_main: Main) -> void:
	main = p_main


## --sim-check=SEED: print (and optionally write) the determinism fingerprint, then quit.
## --server[=PORT]: run as a dedicated server (see DedicatedServer) instead of the game.
func _run_server() -> bool:
	var server := DedicatedServer.new()
	if not server.configure(OS.get_cmdline_user_args()):
		return false
	main.set_physics_process(false)
	main.set_process_input(false)
	main.set_process_unhandled_input(false)
	main.add_child(server)
	return true


func _run_sim_check() -> bool:
	var seed_ := -1
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sim-check="):
			seed_ = int(a.get_slice("=", 1))
		elif a.begins_with("--sim-check-out="):
			out = a.get_slice("=", 1)
	if seed_ < 0:
		return false
	var digest := SimCheck.run(seed_)
	print("SIMCHECK ", digest)
	if out != "":
		# Use an absolute path: an exported game resolves relative ones inside its package.
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(digest)
			f.close()
		else:
			printerr("Could not write ", out, " (use an absolute path)")
	main.get_tree().quit()
	return true


func _parse_args() -> int:
	var start := -1
	var pick := false
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			main.autoplay = AutoPlay.new()
			start = 4
		elif a == "--hitboxes":
			main.debug.visible = true
		elif a == "--intro":
			main._intro_arg = 1
		elif a == "--no-intro":
			main._intro_arg = -1
		elif a == "--range-rings":
			main.range_rings = true
		elif a.begins_with("--a11y="):
			Accessibility.cli = Accessibility.parse_flag(a.substr("--a11y=".length()))
		elif a.begins_with("--progression="):  # Settings > Game > Progression for this session only (not saved)
			var v := a.get_slice("=", 1)
			if v in ["on", "off"]:
				Progress.set_enabled(v == "on")
		elif a.begins_with("--lighting="):
			main._lighting_cli = ["off", "low", "high"].find(a.get_slice("=", 1))
		elif a.begins_with("--mode="):
			start = clampi(int(a.get_slice("=", 1)), 0, Main.MODES.size() - 1)
			main._skip_select = true  # straight into the match with the default teams
		elif a == "--pick":
			pick = true
		elif a == "--cpu-vs-cpu":
			main._cpu_vs_cpu = true
		elif a.begins_with("--mutators="):
			var table := Daily.mutator_table()
			main._forced_mutators = {}
			main._forced_names = []
			for id in a.get_slice("=", 1).split(",", false):
				if table.has(id):
					MatchSim.merge_mutator(main._forced_mutators, table[id])
					main._forced_names.append(String(table[id].get("name", id)))
				else:
					push_warning("--mutators: no mutator '%s' (data/rules/mutators.json)" % id)
		elif a.begins_with("--view-team="):
			main._view_team_arg = int(a.get_slice("=", 1))
		elif a.begins_with("--teams="):
			# --teams=cairn,culvert,cairn:culvert,cairn,culvert
			var halves := a.get_slice("=", 1).split(":")
			if halves.size() == 2:
				main._teams = [Array(halves[0].split(",")), Array(halves[1].split(","))]
		elif a.begins_with("--level="):
			main.level = clampi(int(a.get_slice("=", 1)), 0, Main.LEVEL_NAMES.size() - 1)
		elif a.begins_with("--seed="):
			main.seed_base = int(a.get_slice("=", 1))
		elif a == "--perf":
			main._perf = PerfLog.new()
			PerfLog.current = main._perf
			main._perf.measure(main.get_viewport().get_viewport_rid())
		elif a.begins_with("--fight-fps="):
			main._fight_fps_cli = maxi(0, int(a.get_slice("=", 1)))
		elif a.begins_with("--fps-pacing="):
			main._fps_pacing = a.get_slice("=", 1)
		elif a.begins_with("--cpu-threads="):
			CpuController.threaded = a.get_slice("=", 1) != "off"
		elif a.begins_with("--cpu-think="):
			main.cpu_think = a.get_slice("=", 1)
		elif a.begins_with("--arena="):
			var ar := a.get_slice("=", 1)
			if ar in ArenaMap.IDS:
				MatchFactory.arena = ar
		elif a.begins_with("--time="):
			var tid := a.get_slice("=", 1)
			if tid == WeatherView.RANDOM or tid in WeatherView.time_ids():
				main._look_cli["time"] = tid
		elif a.begins_with("--weather="):
			var wid := a.get_slice("=", 1)
			if wid == WeatherView.RANDOM or wid in WeatherView.weather_ids():
				main._look_cli["weather"] = wid
		elif a.begins_with("--dummy-mode="):
			main.dummy_mode = clampi(int(a.get_slice("=", 1)), 0, Main.DUMMY_MODES.size() - 1)
		elif a.begins_with("--training-flags="):
			var on := a.get_slice("=", 1).split(",")
			for k in MatchSim.TRAINING_FLAGS:
				main.training_opts[k] = k in on
		elif a.begins_with("--training-screen="):
			main._training_screen_arg = a.get_slice("=", 1)
		elif a.begins_with("--shots="):
			for s in a.get_slice("=", 1).split(","):
				main._shots[int(s)] = true
		elif a.begins_with("--cam="):
			var cp := a.get_slice("=", 1).split(",")
			main._cam_force = Vector3(float(cp[0]), float(cp[1]), float(cp[2]) if cp.size() > 2 else 0.0)
		elif a.begins_with("--cam-lead=") or a.begins_with("--cam-clash=") or a.begins_with("--cam-settle="):
			var lv := MainCamera.cam_level_arg(a.get_slice("=", 1))
			if lv >= 0:
				main._cam_cli[a.get_slice("=", 0).trim_prefix("--").replace("-", "_")] = lv
		elif a.begins_with("--shot-dir="):
			main._shot_dir = a.get_slice("=", 1)
		elif a.begins_with("--rematch-after="):
			main._rematch_after = maxi(0, int(a.get_slice("=", 1)))
		elif a.begins_with("--print-vram="):
			main._print_vram_at = int(a.get_slice("=", 1))
		elif a.begins_with("--replay="):
			main._clip_cli["path"] = a.substr("--replay=".length())
		elif a.begins_with("--from="):
			main._clip_cli["from"] = maxi(0, int(a.get_slice("=", 1)))
		elif a.begins_with("--to="):
			main._clip_cli["to"] = maxi(0, int(a.get_slice("=", 1)))
		elif a.begins_with("--quit-after="):
			main._quit_after = int(a.get_slice("=", 1))
		elif a == "--bug-report" or a.begins_with("--bug-report="):
			var d := a.get_slice("=", 1) if a.contains("=") else ""
			main._bug_report_dir = d if d != "" else BugReport.DIR
		elif a.begins_with("--showcase="):
			var sc := a.get_slice("=", 1)
			if sc in Showcase.names():
				main._showcase_arg = sc
			for i in Main.MODES.size():
				if Main.MODES[i].get("showcase", false):
					start = i
		elif a == "--online-host" or a.begins_with("--online-host="):
			main._net_args["host"] = int(a.get_slice("=", 1)) if a.contains("=") else Netplay.DEFAULT_PORT
		elif a.begins_with("--online-join="):
			main._net_args["join"] = a.get_slice("=", 1)
		elif a.begins_with("--online-watch="):
			main._net_args["join"] = a.get_slice("=", 1)
			main._net_args["watch"] = true
		elif a.begins_with("--menu="):
			var page := a.get_slice("=", 1)
			if page in ["main", "single", "look", "settings", "game", "video", "audio", "accessibility", "controls", "touch"] or page.begins_with("single:") \
					or page.begins_with("credits") or page == "profile" or page.begins_with("profile:") or page.begins_with("ending:") \
					or page in ["remap:classic", "remap:league", "remap:gamepad"]:
				main._menu_arg = "" if page == "main" else page
		elif a.begins_with("--fighter="):
			var f := a.get_slice("=", 1)
			if f in MatchFactory.FIGHTERS:
				main._online_fighter = f
				main._arcade_fighter = f
		elif a.begins_with("--net-lag="):
			main._net_args["lag"] = int(a.get_slice("=", 1))
		elif a.begins_with("--net-loss="):
			main._net_args["loss"] = float(a.get_slice("=", 1))
		elif a.begins_with("--online-size="):
			main._net_args["size"] = clampi(int(a.get_slice("=", 1)), 1, TeamSim.MOST_PER_SIDE)
		elif a.begins_with("--net-delay="):
			main._net_args["delay"] = int(a.get_slice("=", 1))
		elif a.begins_with("--net-report="):
			main._net_args["report"] = a.get_slice("=", 1)
		elif a.begins_with("--voice"):
			main._voice_arg(a)
		elif a == "--net-no-pick" or a.begins_with("--net-no-pick="):
			main._net_no_pick = int(a.get_slice("=", 1)) if a.contains("=") else 1 << 30
		elif a.begins_with("--layout="):
			var lay := a.get_slice("=", 1)
			if lay in PlayerInput.LAYOUTS:
				main.player_input.layout = lay
		elif a.begins_with("--pad-layout="):
			var pl := a.get_slice("=", 1)
			if pl in PlayerInput.PAD_LAYOUTS:
				main._set_pad_layout(pl)
		elif a == "--touch-demo" or a.begins_with("--touch-demo="):
			main.touch_demo = TouchDemo.new()
			if a.get_slice("=", 1) == "left":
				main.touch_demo.mirror = true
				main._touch_demo_left = true  # this session only (not saved)
	if main.touch_demo != null and start < 0:
		start = 3  # training as Cairn: a dummy to aim at
		main._skip_select = true
	if pick:
		main._skip_select = false
	return start


## --replay=<file> [--from=A] [--to=B]: watch one saved replay (absolute path or user://)
## from tick A (default 0) to tick B (default its end), at 1x, then quit (`clip_over`,
## checked in main's `_capture`). The match is rebuilt and its inputs re-simulated
## (`_play_replay`, then `ReplayViewer.seek(A)` headless), so every frame is the replay's.
## Frame 1 (the first physics frame: `--shots`, `--quit-after`, the movie maker's first
## frame) shows tick A + 1. The HUD's replay key strip is hidden for a clean picture.
## The Replay theater's Export clip and `tools/clip.py` run this with `--write-movie`.
func start_replay_cli() -> void:
	var path := String(main._clip_cli.get("path", ""))
	if not FileAccess.file_exists(path):
		printerr("--replay: no file ", path)
		main.get_tree().quit(1)
		return
	main._play_replay(path)
	if not main._replaying():
		printerr("--replay: can't play ", path)
		main.get_tree().quit(1)
		return
	var n: int = main.replay_ctl.frames().size()
	var from := clampi(int(main._clip_cli.get("from", 0)), 0, n)
	var to := clampi(int(main._clip_cli.get("to", n)), from, n)
	main._clip_cli["from"] = from
	main._clip_cli["to"] = to
	main._clip_cli["frame0"] = main.frame_count
	if from > 0:
		main.replay_ctl.seek(from)
	main._cam_zoom = 0.0  # frame the fight where it stands, no pan in from the last view
	main._cam_prev = []
	main.hud.show_help = false
	print("REPLAY CLIP ticks %d to %d of %d" % [from, to, n])


## Whether a --replay range has played to its end (and say so); main quits on it.
func clip_over() -> bool:
	if not main._clip_cli.has("frame0") or main._clip_cli.get("done", false):
		return false
	var t: int = main.replay_ctl.tick() if main._replaying() else int(main._clip_cli["to"])
	if t < int(main._clip_cli["to"]):
		return false
	main._clip_cli["done"] = true
	print("REPLAY CLIP END tick %d frame %d" % [t, main.frame_count - int(main._clip_cli["frame0"])])
	return true
