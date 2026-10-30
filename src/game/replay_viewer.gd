extends RefCounted
class_name ReplayViewer
## The Replay theater's playback controls, for main (`replay_ctl`), only while a replay
## is watched (`main._replaying()`): pause and resume, one tick forward or back, slow
## motion and fast forward (`SPEEDS`), jumps (5 s back or on, the start) and Export clip
## (`replay_clip`, clip_export.gd). Views only:
## the recorded inputs are never changed, and a jump rebuilds the match exactly.
##
## Speed: `ticks_now()` is how many sim ticks main runs this physics frame (0 when paused
## or between slow-motion ticks, 2 at double speed), counted in quarter ticks so 1/4 and
## 1/2 speed are exact.
## Jumps (`seek`): the stepping object (the DuelSim / TeamSim / BrawlSim, else the
## MatchSim) is restored in place from the nearest keyframe at or before the target
## (`sim.snapshot()`s taken every `_every` ticks as the replay plays or is stepped through;
## the first one when it starts) and the recorded frames are stepped from there, headless,
## up to the target: the same state as playing straight there (`tests/test_replays.gd`).
## Main's own per-round state (the Versus intro, timer and banners) is put back to what
## playing straight there leaves (`_fix_main_state`).

const Main := preload("res://src/game/main.gd")

## Playback speeds, in quarter ticks per physics frame: 1/4, 1/2, 1x, 2x.
const SPEEDS := [1, 2, 4, 8]
const SPEED_NAMES := ["1/4x", "1/2x", "1x", "2x"]
const NORMAL := 2
## How far Left / Right (and the pause menu's Back 5 seconds) jump.
const JUMP_TICKS := 5 * 60
## A keyframe every this many ticks; a long replay spreads them out so it keeps at most
## `MOST_KEYS` (a 4 v 4 Capture the Flag snapshot is about 80 KB). A jump on steps the
## frames headless from the last keyframe (about 130 ms for 5 s of a 4 v 4 on a desktop);
## a jump back or a tick back steps at most `_every` of them.
const KEY_EVERY := 60
const MOST_KEYS := 480

## The actions, bound in controls.gd for every device; [action, keyboard, gamepad, what].
const KEYS := [
	["replay_pause", "Space / P", "A", "pause / play"],
	["replay_step", ".", "X", "one tick on"],
	["replay_step_back", ",", "B", "one tick back"],
	["replay_slower", "-", "LB", "slower"],
	["replay_faster", "+", "RB", "faster"],
	["replay_back", "Left", "D-pad left", "back 5 s"],
	["replay_forward", "Right", "D-pad right", "on 5 s"],
	["replay_start", "Home", "Y", "from the start"],
	["replay_clip", "C", "R3", "export a clip"],
]

var main: Main
var playing := true
var speed_i := NORMAL
var _acc := 0
var _steps := 0  ## ticks asked for one at a time while paused
var _every := KEY_EVERY
var keys := {}  ## tick -> the stepping object's snapshot at that tick
var path := ""  ## the replay file being watched (a bug report includes it)


func _init(p_main: Main) -> void:
	main = p_main


## A replay just started (from `_play_replay`, the match built, before its first tick).
func begin() -> void:
	playing = true
	speed_i = NORMAL
	_acc = 0
	_steps = 0
	var n: int = main._replay_frames.size()
	_every = maxi(KEY_EVERY, ceili(float(n) / MOST_KEYS / 60.0) * 60)
	keys = {}
	keys[main.sim.tick] = _stepper().snapshot()


func end() -> void:
	keys = {}
	path = ""


func frames() -> Array:
	return main._replay_frames


## The tick being shown (how many recorded frames have played).
func tick() -> int:
	return mini(main.sim.tick, frames().size()) if main.sim != null else 0


## How many sim ticks main runs this physics frame.
func ticks_now() -> int:
	if not playing:
		var n := _steps
		_steps = 0
		return n
	_acc += int(SPEEDS[speed_i])
	var k := _acc / 4
	_acc -= k * 4
	return k


## After each tick main ran: keep a keyframe on the grid.
func note_tick() -> void:
	var t: int = main.sim.tick
	if t % _every == 0 and t <= frames().size() and not keys.has(t):
		keys[t] = _stepper().snapshot()


## A physics frame with no tick (paused, or between slow-motion ticks): the HUD still
## counts its toasts down and shows where the replay is.
func hold() -> void:
	main.hud.advance()
	update_hud()


func update_hud() -> void:
	main.hud.help_text = status_line()


func status_line() -> String:
	var pad: bool = main.hud.gamepad
	var state := "PAUSED" if not playing else String(SPEED_NAMES[speed_i])
	var line := "REPLAY  %s  %s / %s" % [state, _clock(tick()), _clock(frames().size())]
	var bits: Array = []
	for k in [KEYS[0], KEYS[1], KEYS[3], KEYS[5], KEYS[7]]:
		bits.append("%s %s" % [k[2] if pad else k[1], k[3]])
	if not pad:
		bits[2] = "- / + speed"
		bits[3] = "Left / Right 5 s"
	else:
		bits[2] = "LB / RB speed"
		bits[3] = "D-pad 5 s"
	return line + "     " + "   ".join(bits)


## The keys, for the pause menu's Controls page.
static func help_text() -> String:
	var lines: Array = ["Watching a replay:"]
	for k in KEYS:
		lines.append("%s  (%s)  %s" % [k[1], k[2], k[3]])
	return "\n".join(lines)


static func _clock(t: int) -> String:
	var s := t / 60
	return "%d:%02d" % [s / 60, s % 60]


## A press while watching (no screen open); true when it was one of the replay keys.
func handle(event: InputEvent) -> bool:
	if event.is_action_pressed("replay_pause"):
		toggle()
	elif event.is_action_pressed("replay_step", true):
		step()
	elif event.is_action_pressed("replay_step_back", true):
		step_back()
	elif event.is_action_pressed("replay_slower"):
		set_speed(speed_i - 1)
	elif event.is_action_pressed("replay_faster"):
		set_speed(speed_i + 1)
	elif event.is_action_pressed("replay_back", true):
		jump(-JUMP_TICKS)
	elif event.is_action_pressed("replay_forward", true):
		jump(JUMP_TICKS)
	elif event.is_action_pressed("replay_start"):
		seek(0)
		main.hud.show_toast("From the start")
	elif event.is_action_pressed("replay_clip"):
		main.clip_ctl.open_screen(true)  # (clip_export.gd: the replay holds while it's open)
	else:
		return false
	update_hud()
	return true


func toggle() -> void:
	playing = not playing
	_acc = 0
	main.hud.show_toast("Paused" if not playing else "Playing at " + String(SPEED_NAMES[speed_i]))


## One tick on (pausing first).
func step() -> void:
	playing = false
	_steps += 1


## One tick back (pausing first).
func step_back() -> void:
	playing = false
	_steps = 0
	seek(tick() - 1)


func set_speed(i: int) -> void:
	speed_i = clampi(i, 0, SPEEDS.size() - 1)
	_acc = 0
	playing = true
	main.hud.show_toast("Speed " + String(SPEED_NAMES[speed_i]))


## The next speed round the list (the pause menu's row).
func cycle_speed() -> void:
	set_speed((speed_i + 1) % SPEEDS.size())


func jump(by: int) -> void:
	var to := clampi(tick() + by, 0, frames().size())
	seek(to)
	main.hud.show_toast("%s  %s" % ["Back 5 s" if by < 0 else "On 5 s", _clock(to)])


## The match as it stands after `target` recorded frames (clamped to the recording).
## At the end, main's flow ends the replay as it does when the inputs run out.
func seek(target: int) -> void:
	var fr := frames()
	target = clampi(target, 0, fr.size())
	var g = _stepper()
	var best := -1
	for k in keys:
		if int(k) <= target and int(k) > best:
			best = int(k)
	if best < 0:
		return  # (begin() always keeps the first one)
	g.restore(keys[best])
	var t := best
	var training: bool = main.sim.training
	# A Versus round's intro plays no inputs (main's sides aren't live in it), whatever
	# the file holds there: the same here.
	var intro: int = Main.INTRO_TICKS if g == main.sim else 0
	while t < target:
		if training:
			ReplayBuilder.apply_flag_changes(main.sim, main._replay_watched, t)
		if t < intro:
			var quiet := PackedInt32Array()
			quiet.resize((fr[t] as PackedInt32Array).size())
			g.step(quiet)
		else:
			g.step(fr[t])
		t += 1
		if t % _every == 0 and not keys.has(t):
			keys[t] = g.snapshot()
	_fix_main_state(target)


## What playing straight to `target` leaves on main: a Versus round's intro, timer and
## flow (sim.tick = INTRO_TICKS + the fight ticks, timer = ROUND_TICKS - them); the
## other kinds keep their flow in the game object, so FIGHT until the end. The match-over
## screen closes, and the views drop what they were showing.
func _fix_main_state(target: int) -> void:
	if main.ui.is_open():
		main.ui.clear()
	main.paused = false
	main.wins = [0, 0]
	main.round_num = 1
	main.hud.wins = main.wins
	main.hud.banner = ""
	main.hud.banner_sub = ""
	main.replay.frames.assign(frames().slice(0, target))  # (F6 saves what has played)
	if main.duel == null and main.team_battle == null and main.brawl == null:
		if target < Main.INTRO_TICKS:
			main.flow = Main.Flow.INTRO
			main.flow_t = target
			main.timer = Main.ROUND_TICKS
		else:
			main.flow = Main.Flow.FIGHT
			main.flow_t = target - Main.INTRO_TICKS
			main.timer = Main.ROUND_TICKS - main.flow_t
		main.hud.timer_ticks = maxi(main.timer, 0)
	else:
		main.flow = Main.Flow.FIGHT
		main.flow_t = 0
	main.fx.clear()
	main._show_pads()  # the mode's own marks (pads, flags, shrines, caravan) at the tick now shown,
	main._update_zone()  # so a paused seek doesn't lose them until the next tick
	if main.letterbox != null:
		main.letterbox.clear()
	for i in main.views.size():
		main.views[i].rebind(main.sim.creatures[i])
	if target >= frames().size():
		main._update_flow()  # out of inputs: the replay ends now, as it would have


## What steps the match: the mode's game object, else the match itself.
func _stepper():
	if main.duel != null:
		return main.duel
	if main.team_battle != null:
		return main.team_battle
	if main.brawl != null:
		return main.brawl
	return main.sim
