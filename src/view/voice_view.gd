class_name VoiceView
extends Node
## Proximity voice chat's sound: the microphone into VoiceChat and the other players' voices out of it, each placed by where their fighter stands.
##
## A view like AudioView: it reads the match (fighters' positions) and the chat's queues,
## and never writes the sim. Main calls `frame()` every rendered frame (after
## `netplay.pump()`), and `stop()` when the online match ends.
##
## The microphone plays into a muted "Mic" bus whose AudioEffectCapture hands its frames
## here; it runs only while voice is on, an online match (or a watched one) is on and this
## machine is a player (never in menus, never for a spectator). Each heard player has an
## AudioStreamPlayer on the "Voice" bus (a volume group in Settings > Audio) fed by an
## AudioStreamGenerator, louder the closer their fighter is to yours (VoiceChat.gain_for)
## and panned left or right of it (VoiceChat.pan_for). A spectator listens from the
## camera's centre. Headless runs never open the mic or a speaker (they still drain the
## queues, so a headless tone test counts packets).
##
## `--voice-test=tone`: a 220 Hz tone instead of the microphone, always "held", and a log
## line a second of what was sent and heard (two processes on one machine test the path).

const MIC_BUS := "Mic"
const VOICE_BUS := "Voice"
## The capture effect's ring buffer: 0.2 s, so a slow frame (a hitch, a load) doesn't
## overflow it between reads (each frame reads everything it holds).
const CAPTURE_SECONDS := 0.2
## Each speaker's generator buffer, in seconds.
const PLAYER_BUFFER := 0.25
## Under this a voice is muted outright.
const GAIN_FLOOR := 0.001
## How far a voice's gain moves toward its target each frame (no zipper noise as fighters move).
const GAIN_SMOOTH := 0.2
## Enabled, capturing, and nothing from the microphone for this long: "NO MIC".
const NO_MIC_MS := 2000.0
const TONE_HZ := 220.0
const TONE_AMP := 0.3
const ANDROID_MIC := "android.permission.RECORD_AUDIO"

## --voice-test=tone: the tone instead of the microphone, and the log lines.
var tone := false
## Sending right now (the HUD's MIC light).
var sending := false
## The microphone can't be heard: no input device, or nothing from it for NO_MIC_MS.
var mic_missing := false
## Slots speaking now -> their level (0..1), refreshed every frame: the HUD's and the
## name plates' speaker icons.
var heard := {}

var _silent := DisplayServer.get_name() == "headless"
var _chat: VoiceChat = null
var _mic: AudioStreamPlayer = null
var _capture: AudioEffectCapture = null
var _capturing := false
var _rs_state := {}
var _quiet_ms := 0.0  ## capturing with no frames from the microphone, this long
var _no_device := false
var _device_check_ms := 0.0
var _tone_phase := 0.0
var _tone_carry := 0.0
var _tone_buf := PackedFloat32Array()
var _players := {}  ## slot -> AudioStreamPlayer
var _gain := {}  ## slot -> the gain playing now (smoothed)
var _place := {}  ## slot -> Vector2(target gain, pan), for the test log
var _frames := PackedVector2Array()
var _log_ms := 0.0


func _exit_tree() -> void:
	stop()


# ------------------------------------------------------------------ each frame

## One rendered frame of an online match (or none: `np` or `game` null stops everything).
## `game` is the match being shown (a DuelSim or a TeamSim), `local_slot` this machine's
## player (-1 spectating), `listener` where a spectator hears from (the camera's centre),
## `ptt` whether the push-to-talk key is held.
func frame(np: Netplay, game, local_slot: int, listener: Vector2, ptt: bool, delta: float) -> void:
	heard.clear()
	var chat: VoiceChat = np.voice if np != null else null
	if chat == null or game == null:
		if _chat != null or _capturing or not _players.is_empty():
			stop()
		return
	_chat = chat
	chat.clock_ms = Time.get_ticks_msec()
	var on := chat.mode != VoiceChat.Mode.OFF
	if on and local_slot >= 0 and chat.slot >= 0:
		_capture_step(chat, ptt or tone, delta)
		sending = chat.talking
	else:
		_stop_capture()
		sending = false
	var me := fighter(game, local_slot)
	var at := me.pos if me != null else listener
	for slot in chat.heard_slots():
		var s := int(slot)
		var c := fighter(game, s)
		var pl := Vector2.ZERO  # a slot with no fighter (gone): silent
		var hear := chat.hearing(s)  # muted (or everyone is): silent and no icon, whatever is queued
		if c != null and hear:
			pl = place(c.pos, at, me != null and c.team == me.team)
		if not hear:
			_gain[s] = 0.0  # straight to the floor, no fade
		_place[s] = pl
		_play(chat, s, pl.x, pl.y, delta)
		if hear and chat.speaking(s):
			heard[s] = chat.level(s)
	if tone:
		_log(chat, delta)


## Everything off: the microphone stops, the speakers go.
func stop() -> void:
	_stop_capture()
	for s in _players:
		var p: AudioStreamPlayer = _players[s]
		p.stop()
		p.queue_free()
	_players.clear()
	_gain.clear()
	_place.clear()
	heard.clear()
	sending = false
	mic_missing = false
	_chat = null


func speaking(slot: int) -> bool:
	return heard.has(slot)


func level(slot: int) -> float:
	return float(heard.get(slot, 0.0))


## The fighter that speaks for input slot `slot` in `game`: a 1v1 Duel's side's active
## fighter, a team battle's slot's. Null when there is none.
static func fighter(game, slot: int) -> CreatureSim:
	if game == null or slot < 0:
		return null
	if game is DuelSim:
		return (game as DuelSim).active_creature(slot) if slot < 2 else null
	if game is TeamSim:
		var cs: Array = (game as TeamSim).sim.creatures
		return cs[slot] if slot < cs.size() else null
	return null


## How a voice from `speaker` sounds to a listener at `listener` (world pixels):
## Vector2(gain 0..1, pan -1..1).
static func place(speaker: Vector2, listener: Vector2, same_team: bool) -> Vector2:
	return Vector2(VoiceChat.gain_for(speaker.distance_to(listener), same_team),
		VoiceChat.pan_for(speaker.x - listener.x))


## Android asks for the microphone once voice is on (the permission is in the export
## preset; the system asks the player the first time).
static func ask_permission() -> void:
	if OS.get_name() == "Android" and not (ANDROID_MIC in OS.get_granted_permissions()):
		OS.request_permission(ANDROID_MIC)


# ------------------------------------------------------------------ the microphone

func _capture_step(chat: VoiceChat, ptt: bool, delta: float) -> void:
	if tone:
		mic_missing = false
		chat.push_mic(_tone(chat.sample_rate(), delta), true)
		return
	if _silent:
		return  # headless: never the microphone
	_start_capture()
	var n := _capture.get_frames_available()
	if n > 0:
		_quiet_ms = 0.0
		var mono := VoiceCodec.to_mono(_capture.get_buffer(n))
		chat.push_mic(VoiceCodec.resample(mono, AudioServer.get_mix_rate(), chat.sample_rate(), _rs_state), ptt)
	else:
		_quiet_ms += delta * 1000.0
		if _quiet_ms >= NO_MIC_MS and fmod(_quiet_ms, NO_MIC_MS) < delta * 1000.0:
			_mic.stop()  # nothing yet (a permission granted late, a device plugged in): try again
			_mic.play()
	_device_check_ms -= delta * 1000.0
	if _device_check_ms <= 0.0:
		_device_check_ms = NO_MIC_MS
		_no_device = AudioServer.get_input_device_list().is_empty()
	mic_missing = _no_device or _quiet_ms >= NO_MIC_MS


func _start_capture() -> void:
	if _capturing:
		return
	_ensure_mic()
	_capture.clear_buffer()
	_rs_state.clear()
	_quiet_ms = 0.0
	_device_check_ms = 0.0
	_mic.play()
	_capturing = true


func _stop_capture() -> void:
	if not _capturing:
		return
	_capturing = false
	if _mic != null:
		_mic.stop()
	if _capture != null:
		_capture.clear_buffer()
	_rs_state.clear()
	mic_missing = false


## The muted Mic bus with its capture effect, and the player that streams the microphone
## into it (made the first time voice is used, never headless).
func _ensure_mic() -> void:
	if _mic != null:
		return
	var i := AudioServer.get_bus_index(MIC_BUS)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, MIC_BUS)
		AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_mute(i, true)  # heard by the capture only, never in the speakers
	for k in AudioServer.get_bus_effect_count(i):
		if AudioServer.get_bus_effect(i, k) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(i, k)
	if _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = CAPTURE_SECONDS
		AudioServer.add_bus_effect(i, _capture)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = MIC_BUS
	add_child(_mic)


## --voice-test=tone: `delta` worth of a 220 Hz tone at `rate`.
func _tone(rate: int, delta: float) -> PackedFloat32Array:
	_tone_carry += delta * rate
	var n := int(_tone_carry)
	_tone_carry -= n
	_tone_buf.resize(n)
	var step := TAU * TONE_HZ / rate
	for k in n:
		_tone_buf[k] = TONE_AMP * sin(_tone_phase)
		_tone_phase = fmod(_tone_phase + step, TAU)
	return _tone_buf


# ------------------------------------------------------------------ the speakers

func _play(chat: VoiceChat, slot: int, gain: float, pan: float, delta: float) -> void:
	var g := lerpf(float(_gain.get(slot, gain)), gain, GAIN_SMOOTH)
	_gain[slot] = g
	# pull() hands out whole packets, so it may go up to a packet past what was asked.
	var packet := chat.frame_samples() * chat.frames_per_packet()
	if _silent:
		chat.pull(slot, maxi(1, int(delta * chat.sample_rate())))  # headless: drain, play nothing
		return
	var p: AudioStreamPlayer = _players.get(slot)
	if p == null:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = chat.sample_rate()
		gen.buffer_length = PLAYER_BUFFER
		p = AudioStreamPlayer.new()
		p.stream = gen
		p.bus = VOICE_BUS
		add_child(p)
		p.play()
		_players[slot] = p
	p.volume_db = linear_to_db(g) if g > GAIN_FLOOR else -80.0
	var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var most := pb.get_frames_available() - (packet - 1)
	if most <= 0:
		return
	var pcm := chat.pull(slot, most)
	if pcm.is_empty():
		return  # nothing ready: the speaker starves into silence
	var a := (pan + 1.0) * PI * 0.25  # constant power: equal at the centre
	var l := cos(a)
	var r := sin(a)
	_frames.resize(pcm.size())
	for k in pcm.size():
		_frames[k] = Vector2(pcm[k] * l, pcm[k] * r)
	pb.push_buffer(_frames)


func _log(chat: VoiceChat, delta: float) -> void:
	_log_ms += delta * 1000.0
	if _log_ms < 1000.0:
		return
	_log_ms -= 1000.0
	print("voice: sent %d" % chat.sent)
	for s in chat.heard_slots():
		var pl: Vector2 = _place.get(int(s), Vector2.ZERO)
		print("voice: heard slot %d gain %.2f pan %.2f received %d dropped %d queued %d" % [int(s), pl.x, pl.y,
			chat.received, chat.dropped, chat.queued(int(s))])


# ------------------------------------------------------------------ the icon

## A small speaker with sound waves (wider with `level`), its left edge at `at.x` and
## centred on `at.y`, about 10 x 9 pixels, with a dark outline so it reads on any floor.
static func draw_glyph(ci: CanvasItem, at: Vector2, lvl: float, col: Color) -> void:
	var x := roundf(at.x)
	var y := roundf(at.y)
	var waves := 1 + int(lvl > 0.12) + int(lvl > 0.35)
	var o := Color(0.06, 0.07, 0.09, 0.85 * col.a)
	for pass_ in 2:
		var c := o if pass_ == 0 else col
		var d := 1.0 if pass_ == 0 else 0.0
		ci.draw_rect(Rect2(x + d, y - 1 + d, 2, 3), c)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x + 2 + d, y - 1 + d), Vector2(x + 5 + d, y - 4 + d),
			Vector2(x + 5 + d, y + 5 + d), Vector2(x + 2 + d, y + 2 + d)]), c)
		for w in waves:
			ci.draw_arc(Vector2(x + 5 + d, y + 0.5 + d), 2.5 + 2.0 * w, -0.9, 0.9, 5, c, 1.0)
