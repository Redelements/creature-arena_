extends Node
class_name ClipExport
## The Replay theater's Export clip, for main (`clip_ctl`, a child node so it can watch the
## export between frames): C (pad R3) while watching, or the replay pause menu's row,
## opens "EXPORT CLIP" (`open_screen`), which lists the replay's clip markers (ClipMarks:
## F6 presses and combo KOs) and "this moment". Picking one renders the 10 s before it
## and the second after: the game's own executable is started again
## (`OS.get_executable_path()`) with the movie maker (`--write-movie`, an MJPEG AVI with
## sound) and `--replay=<file> --from=A --to=B` (main_args.gd), which re-simulates the
## recorded inputs, so the frames are the replay's exactly. The AVI is written next to
## the replay. Godot writes no GIF or MP4 itself: with ffmpeg on PATH the AVI becomes an
## MP4 and a 480 px GIF (and the AVI is removed); without it the AVI stays and the screen
## says so. `tools/clip.py` does the same from a terminal (a size-capped GIF with Pillow).
## Views only: nothing here touches the match being watched.

const Main := preload("res://src/game/main.gd")

const BEFORE := 10 * 60  ## ticks before the marker
const AFTER := 60  ## and after it (the KO landing)
const TITLE := "EXPORT CLIP"
const NO_EDITOR := "Export clip works in the exported game (or `godot --path .` from a terminal), not from the editor's Play button"
const NO_DESKTOP := "Export clip needs the desktop game"

enum State { IDLE, RENDER, MP4, GIF, DONE, FAILED }

var main: Main
var state := State.IDLE
var message := ""  ## what the screen says about the last export
var avi := ""  ## OS paths of this export's files
var mp4 := ""
var gif := ""
var _pid := -1
var _t0 := 0
var _ticks := 0  ## how long the clip is, in ticks
var _status: Label  ## the screen's status line, updated as the export runs
var _froze := false  ## the screen paused the replay (opened with the replay key)


func _init(p_main: Main) -> void:
	main = p_main


## Why this game can't start an export ("" when it can).
static func spawn_problem() -> String:
	if OS.has_feature("mobile") or OS.has_feature("web"):
		return NO_DESKTOP
	if OS.has_feature("editor") and EngineDebugger.is_active():
		return NO_EDITOR  # (Play in the editor: the binary is the editor's own)
	if OS.get_executable_path() == "":
		return NO_DESKTOP
	return ""


## The range a marker at `at` exports, in a replay of `frames` ticks: [from, to].
static func range_for(at: int, frames: int) -> Array:
	var to := clampi(at + AFTER, 0, frames)
	return [maxi(0, mini(at, frames) - BEFORE), to]


## The command line that renders ticks [from, to] of a replay into `movie` (an AVI): the
## same flags `tools/clip.py` passes.
static func command(replay_os_path: String, from: int, to: int, movie: String) -> PackedStringArray:
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--resolution", "1280x720", "--fixed-fps", "60", "--write-movie", movie, "--",
		"--replay=" + replay_os_path, "--from=%d" % from, "--to=%d" % to])
	return args


func busy() -> bool:
	return state == State.RENDER or state == State.MP4 or state == State.GIF


## Renders a clip of the replay at `replay_path` around the marker at tick `at`; "" when it
## started, else why not.
func start(replay_path: String, at: int, frames: int) -> String:
	if busy():
		return "A clip is already being made"
	var why := spawn_problem()
	if why != "":
		return why
	var r := range_for(at, frames)
	if int(r[1]) <= int(r[0]):
		return "Nothing to export there"
	var src := ProjectSettings.globalize_path(replay_path)
	var base := src.trim_suffix(".json") + "_clip_%d" % at
	avi = base + ".avi"
	mp4 = base + ".mp4"
	gif = base + ".gif"
	for p in [avi, mp4, gif, base + ".wav"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	_pid = OS.create_process(OS.get_executable_path(), command(src, int(r[0]), int(r[1]), avi))
	if _pid <= 0:
		_to(State.FAILED, "Could not start the game to render the clip")
		return message
	_ticks = int(r[1]) - int(r[0])
	_t0 = Time.get_ticks_msec()
	print("Exporting a clip: ticks %d to %d -> %s" % [r[0], r[1], avi])
	_to(State.RENDER, "")
	return ""


func _process(_delta: float) -> void:
	if not busy():
		return
	if _status != null and is_instance_valid(_status):
		_status.text = status_text()
	if OS.is_process_running(_pid):
		return
	var code := OS.get_process_exit_code(_pid)
	match state:
		State.RENDER:
			if not _has_file(avi):
				_to(State.FAILED, "The clip didn't render (exit %d)" % code)
			elif ffmpeg_path() == "":
				_to(State.DONE, "Saved %s. No ffmpeg on PATH, so it stays an AVI (no MP4 or GIF)" % avi.get_file())
			else:
				_run_ffmpeg(State.MP4, ["-y", "-loglevel", "error", "-i", avi, "-c:v", "libx264", "-pix_fmt", "yuv420p",
					"-c:a", "aac", mp4])
		State.MP4:
			_run_ffmpeg(State.GIF, ["-y", "-loglevel", "error", "-i", avi, "-vf",
				"fps=15,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", gif])
		State.GIF:
			if _has_file(mp4) and _has_file(gif):
				DirAccess.remove_absolute(avi)
				_to(State.DONE, "Saved %s and %s" % [mp4.get_file(), gif.get_file()])
			else:
				_to(State.DONE, "ffmpeg didn't convert it: kept %s" % avi.get_file())


func _run_ffmpeg(next: State, args: Array) -> void:
	_pid = OS.create_process(ffmpeg_path(), PackedStringArray(args))
	if _pid <= 0:
		_to(State.DONE, "Saved %s (ffmpeg didn't start)" % avi.get_file())
		return
	_to(next, "")


## ffmpeg's path when it's on PATH, else "" (looked up, not run: running a missing
## program logs an engine error).
static func ffmpeg_path() -> String:
	var windows := OS.get_name() == "Windows"
	for dir in OS.get_environment("PATH").split(";" if windows else ":", false):
		var p := String(dir).strip_edges().trim_suffix("\\").path_join("ffmpeg.exe" if windows else "ffmpeg")
		if FileAccess.file_exists(p):
			return p
	return ""


static func _has_file(p: String) -> bool:
	return p != "" and FileAccess.file_exists(p) and FileAccess.open(p, FileAccess.READ).get_length() > 0


func _to(s: State, msg: String) -> void:
	state = s
	message = msg
	if s == State.DONE or s == State.FAILED:
		print("Clip export: ", msg)
	_refresh()


func status_text() -> String:
	var secs := (Time.get_ticks_msec() - _t0) / 1000
	match state:
		State.RENDER:
			return "Rendering %d s of the fight...  %d s" % [_ticks / 60, secs]
		State.MP4:
			return "Converting to MP4...  %d s" % secs
		State.GIF:
			return "Making the GIF...  %d s" % secs
		State.DONE, State.FAILED:
			return message
	return "Pick a moment: the clip is the 10 s before it."


## The folder the clips go in (the replays folder), as the OS names it.
func folder() -> String:
	return avi.get_base_dir() if avi != "" else ProjectSettings.globalize_path(main.replays_dir)


# ------------------------------------------------------------------ the screen

## `freeze`: opened from the replay key (C / R3), so the replay holds still behind it and
## plays on when it closes; from the pause menu, Back returns there.
func open_screen(freeze := false) -> void:
	if freeze:
		_froze = true
		main.paused = true
	var scr := UiScreen.new()
	scr.title = TITLE
	if _froze:
		scr.on_back = func():
			_froze = false
			main.ui.pop()
			main.paused = false
	scr.row_width = 260.0
	scr.row_height = 13.0
	scr.row_font = 7
	scr.row_gap = 1
	scr.builder = _build
	main.ui.push(scr)


func _build(s: UiScreen) -> void:
	var path: String = main.replay_ctl.path
	var frames: int = main.replay_ctl.frames().size()
	_status = s.add_text(status_text())
	var why := spawn_problem()
	if why != "":
		s.add_text(why, UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
	if state == State.DONE:
		s.add_button("Open folder", func(): OS.shell_open(folder()), folder())
	if not busy() and why == "":
		s.add_space(3)
		var here: int = main.replay_ctl.tick()
		s.add_button("This moment   %s" % ReplayViewer._clock(here), func(): _pick(path, here, frames),
			"The 10 s before where the replay is now")
		for m in ClipMarks.load_for(path):
			var at := int(m["at"])
			if at <= frames:
				s.add_button("%s   %s" % [ReplayViewer._clock(at), String(m["why"])], func(): _pick(path, at, frames),
					"The 10 s before this marker")
	s.add_space(4)
	s.add_button("Back", s.back)


func _pick(path: String, at: int, frames: int) -> void:
	var err := start(path, at, frames)
	if err != "":
		main.ui.toast(err)


## The screen shows the export's new state (rebuilt, if it's the one on top).
func _refresh() -> void:
	if main.ui == null:
		return
	var top := main.ui.top()
	if top == null or top.title != TITLE:
		return
	main.ui.pop()
	open_screen()
