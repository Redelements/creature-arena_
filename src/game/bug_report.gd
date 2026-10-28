extends RefCounted
class_name BugReport
## A bug report in one zip (`write`): Settings > Save a bug report, the pause menu's row,
## or `--bug-report[=DIR]`. It holds what helps reproduce a problem and nothing that
## identifies or signs in the player:
##   system.txt        the OS, CPU, GPU, renderer, screen, window, controllers, game and
##                     protocol version (and the build's commit if one is stamped in
##                     res://version.txt), the mode being played
##   logs/<file>       the two newest Godot logs (this run's and the one before), with this
##                     install's player id and secret blanked out if they appear
##   settings.cfg      the settings without the [online] id, secret, name, address,
##                     server and recent servers (`REDACT`)
##   progress.json     Arcade clears, palettes, Gauntlet and Daily bests
##   replay/<file>     the replay being watched, else the newest saved one (a match in
##                     progress is saved as a replay first, as F6 does)
##   perf.txt          the last `--perf` report, if there is one
## Never included: anything outside user:// (no .env, no project files), voice or mic
## audio (none is ever written to disk), user://ratings.json (a server's), the online
## player id and secret.

const Main := preload("res://src/game/main.gd")

const DIR := "user://bug-reports"
const BLURB := "Saves the log, settings, progress and the last replay in one zip, to send with a bug"
const PERF := "user://perf.txt"
## Settings left out of the copy: who the player is online and where they play.
const REDACT := [["online", "id"], ["online", "secret"], ["online", "name"], ["online", "address"],
	["online", "server"], ["online", "recent"]]
## A log bigger than this keeps only its end.
const MOST_LOG_BYTES := 4 * 1024 * 1024
const LOGS := 2


## Writes the zip into `dir` and returns its path ("" if it couldn't). `save_match`: a
## match in progress is saved as a replay first (main's `_save_replay`).
static func write(main: Main, dir := DIR, save_match := true) -> String:
	if save_match and _match_to_save(main):
		main._save_replay()
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := dir.path_join("bugreport_%s.zip" % stamp)
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("bugreport_%s_%d.zip" % [stamp, n])
		n += 1
	var entries := entries_for(main)
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return ""
	for name in entries:
		zip.start_file(String(name))
		zip.write_file(entries[name])
		zip.close_file()
	zip.close()
	return path


## Entry name -> bytes, everything `write` puts in the zip.
static func entries_for(main: Main) -> Dictionary:
	var out := {}
	out["system.txt"] = system_text(main).to_utf8_buffer()
	for p in _newest_logs():
		var b := _tail(FileAccess.get_file_as_bytes(p))
		out["logs/" + String(p).get_file()] = _redact(b.get_string_from_utf8()).to_utf8_buffer()
	var settings := settings_text(String(main.settings_path))
	if settings != "":
		out["settings.cfg"] = settings.to_utf8_buffer()
	if FileAccess.file_exists(Progress.path):
		out["progress.json"] = FileAccess.get_file_as_bytes(Progress.path)
	var rep := _replay_file(main)
	if rep != "":
		out["replay/" + rep.get_file()] = FileAccess.get_file_as_bytes(rep)
	if FileAccess.file_exists(PERF):
		out["perf.txt"] = FileAccess.get_file_as_bytes(PERF)
	return out


## The settings file without the REDACT keys ("" when there is none).
static func settings_text(path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	for pair in REDACT:
		if cfg.has_section_key(String(pair[0]), String(pair[1])):
			cfg.erase_section_key(String(pair[0]), String(pair[1]))
	return cfg.encode_to_text()


static func system_text(main: Main) -> String:
	var lines: Array = []
	var add := func(k: String, v) -> void: lines.append("%s: %s" % [k, str(v)])
	add.call("game", ProjectSettings.get_setting("application/config/name", "?"))
	var ver := String(ProjectSettings.get_setting("application/config/version", ""))
	add.call("version", ver if ver != "" else "(none set)")
	add.call("build", _build_stamp())
	add.call("debug build", OS.is_debug_build())
	add.call("protocol (NET_VERSION)", Netplay.NET_VERSION)
	add.call("godot", Engine.get_version_info().get("string", "?"))
	add.call("saved", Time.get_datetime_string_from_system())
	add.call("os", "%s %s (%s)" % [OS.get_name(), OS.get_version(), OS.get_model_name()])
	add.call("locale", OS.get_locale())
	add.call("cpu", "%s, %d threads" % [OS.get_processor_name(), OS.get_processor_count()])
	add.call("renderer", "%s, %s" % [RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name()])
	add.call("gpu", "%s (%s), API %s" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version()])
	add.call("display server", DisplayServer.get_name())
	if DisplayServer.get_name() != "headless":
		var sc := DisplayServer.window_get_current_screen()
		add.call("screen", "%s at %.2f Hz, scale %.2f" % [str(DisplayServer.screen_get_size(sc)),
			DisplayServer.screen_get_refresh_rate(sc), DisplayServer.screen_get_scale(sc)])
	var win := main.get_window()
	add.call("window", "%s, mode %d, viewport %s" % [str(win.size), int(win.mode), str(main.get_viewport().get_visible_rect().size)])
	add.call("max fps", Engine.max_fps)
	add.call("vsync", DisplayServer.window_get_vsync_mode())
	var pads: Array = []
	for id in Input.get_connected_joypads():
		pads.append("%d: %s" % [id, Input.get_joy_name(id)])
	add.call("controllers", ", ".join(pads) if not pads.is_empty() else "none")
	var mode := int(main.mode)
	add.call("mode", "%d %s" % [mode, String(Main.MODES[mode].get("label", "")) if mode >= 0 and mode < Main.MODES.size() else ""])
	add.call("flow", Main.Flow.find_key(main.flow))
	add.call("online", main.online != null or main.watch != null)
	return "\n".join(lines) + "\n"


## The commit an export was built from, when the build stamps one in res://version.txt
## (none does yet: playable-build.yml would have to write it before exporting).
static func _build_stamp() -> String:
	if FileAccess.file_exists("res://version.txt"):
		return FileAccess.get_file_as_string("res://version.txt").strip_edges()
	return "not stamped"


static func _match_to_save(main: Main) -> bool:
	if main.sim == null or main._menu_bg or main._replaying() or main.mode == Main.REPLAY_MODE:
		return false
	if not (main.flow in [Main.Flow.INTRO, Main.Flow.FIGHT, Main.Flow.ROUND_OVER, Main.Flow.MATCH_OVER]):
		return false
	if main.online != null or main.watch != null:
		return true
	return main.replay != null and main.replay.frames.size() > 0


## The replay being watched, else the newest one saved.
static func _replay_file(main: Main) -> String:
	var watching: String = main.replay_ctl.path
	if main._replaying() and watching != "" and FileAccess.file_exists(watching):
		return watching
	var newest := _newest(String(main.replays_dir), ".json", 1)
	return String(newest[0]) if not newest.is_empty() else ""


static func _newest_logs() -> Array:
	var log_path := String(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	return _newest(log_path.get_base_dir(), ".log", LOGS)


## The `most` newest files in `dir` ending in `ext` (by modification time, then name).
static func _newest(dir: String, ext: String, most: int) -> Array:
	if not DirAccess.dir_exists_absolute(dir):
		return []
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if String(f).ends_with(ext):
			var p := dir.path_join(String(f))
			files.append([FileAccess.get_modified_time(p), String(f), p])
	files.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and String(a[1]) > String(b[1])))
	var out: Array = []
	for row in files.slice(0, most):
		out.append(row[2])
	return out


static func _tail(b: PackedByteArray) -> PackedByteArray:
	return b if b.size() <= MOST_LOG_BYTES else b.slice(b.size() - MOST_LOG_BYTES)


## This install's online id and secret blanked out of a text.
static func _redact(text: String) -> String:
	for s in [Netplay.player_secret, Netplay.player_id]:
		if String(s).length() >= 8:
			text = text.replace(String(s), "<redacted>")
	return text
