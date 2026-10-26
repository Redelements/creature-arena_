class_name VoiceChat
extends RefCounted
## Proximity voice chat for an online match: what this machine says goes out as small
## unreliable packets, what the others say comes back in and is queued per player for
## the speakers. Nothing here is heard or recorded: VoiceView (src/view) feeds the
## microphone in and plays the queues out, placing each voice by where that player's
## fighter stands (`gain_for`, `pan_for`). Netplay owns one per session and routes the
## "vc" messages; the dedicated server relays them to the other players and spectators.
##
## Wire: {"t": "vc", "n": match, "p": slot, "s": sequence, "d": bytes}, `d` being
## `frames_per_packet` IMA ADPCM frames (VoiceCodec) of `frame_ms` each, sent
## unreliably: a lost packet is a lost 40 ms, and the queue skips over it. Nothing is
## sent while the player is quiet: push to talk (`ptt_held`) or, with an open mic, a
## level gate with a short hold. Tuning in data/voice.json.
##
## Time is `clock_ms`, set by the owner each frame (the view: the wall clock; tests:
## whatever they like), so nothing here reads a clock of its own.

const DATA_PATH := "res://data/voice.json"

enum Mode { OFF, PUSH_TO_TALK, OPEN_MIC }
const MODE_NAMES := ["Off", "Push to talk", "Open mic"]

static var _data := {}

var cfg: Dictionary
var mode: int = Mode.PUSH_TO_TALK
var link: NetLink = null
var match_id := 0
## This machine's input slot (-1: a spectator, who listens but never sends).
var slot := -1
var clock_ms := 0
## Sending right now (the HUD's MIC light).
var talking := false
## Packets sent and received, for the net line and tests.
var sent := 0
var received := 0
var dropped := 0  ## packets that arrived too late or malformed

var seq := 0
var _pending := PackedFloat32Array()  ## mic samples not yet a whole frame
var _frames: Array = []  ## encoded frames waiting to fill a packet
var _enc_state := {}
var _loud_ms := -100000  ## when the mic last passed the gate
var _held_ms := -100000  ## when push to talk was last held
var _speakers := {}  ## slot -> _Speaker


## One remote player's incoming voice: packets by sequence, played in order after a
## short wait for stragglers.
class _Speaker:
	var pending := {}  ## seq -> PackedFloat32Array (decoded)
	var next_seq := -1  ## the sequence pull() wants next (-1: whatever comes first)
	var heard_ms := -100000  ## when a packet last arrived
	var started_ms := 0  ## when the current burst began queueing
	var playing := false  ## past the jitter wait: pull() hands out samples
	var gap_since := -1  ## when pull() first found the next packet missing (-1: no gap)
	var level := 0.0  ## the last packet's peak, for the icon


func _init(p_cfg: Dictionary = {}) -> void:
	cfg = p_cfg if not p_cfg.is_empty() else data()


## data/voice.json, read once.
static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_data = d if d is Dictionary else {}
	return _data


func sample_rate() -> int:
	return int(cfg.get("sample_rate", 16000))


## Samples in one codec frame.
func frame_samples() -> int:
	return sample_rate() * int(cfg.get("frame_ms", 20)) / 1000


func frames_per_packet() -> int:
	return maxi(1, int(cfg.get("frames_per_packet", 2)))


## Bytes a well-formed packet's `d` holds.
func packet_bytes() -> int:
	return VoiceCodec.frame_bytes(frame_samples()) * frames_per_packet()


func enabled() -> bool:
	return mode != Mode.OFF and link != null


# ------------------------------------------------------------------ sending

## Microphone samples at sample_rate(), mono, -1..1, however many arrived this frame.
## Whole frames are encoded; with push to talk `ptt_held` opens the mic (plus a short
## release), with an open mic the level gate does. Quiet frames are thrown away.
func push_mic(pcm: PackedFloat32Array, ptt_held: bool) -> void:
	if not enabled() or slot < 0:
		talking = false
		return
	if ptt_held:
		_held_ms = clock_ms
	_pending.append_array(pcm)
	var n := frame_samples()
	while _pending.size() >= n:
		var frame := _pending.slice(0, n)
		_pending = _pending.slice(n)
		var open := false
		match mode:
			Mode.PUSH_TO_TALK:
				open = clock_ms - _held_ms <= int(cfg.get("ptt_release_ms", 180))
			Mode.OPEN_MIC:
				if VoiceCodec.level_db(frame) >= float(cfg.get("gate_db", -40.0)):
					_loud_ms = clock_ms
				open = clock_ms - _loud_ms <= int(cfg.get("gate_hold_ms", 450))
		if not open:
			_frames.clear()
			_enc_state.clear()
			talking = false
			continue
		talking = true
		_frames.append(VoiceCodec.encode_frame(frame, _enc_state))
		if _frames.size() >= frames_per_packet():
			_send_packet()
	if _pending.size() > n * 8:
		_pending = _pending.slice(_pending.size() - n)  # the mic ran far ahead (a hitch): keep the newest


func _send_packet() -> void:
	var d := PackedByteArray()
	for f in _frames:
		d.append_array(f)
	_frames.clear()
	link.send({"t": "vc", "n": match_id, "p": slot, "s": seq, "d": d})
	link.flush()  # out now, not at the next tick: the view calls this between ticks
	seq += 1
	sent += 1


# ------------------------------------------------------------------ receiving

## A "vc" message from another machine (Netplay checks the match number first).
func receive(m: Dictionary) -> void:
	if mode == Mode.OFF:
		return
	var p := NetLink.int_of(m.get("p", -1), -1)
	var s := NetLink.int_of(m.get("s", -1), -1)
	var d = m.get("d")
	if p < 0 or p == slot or s < 0 or not (d is PackedByteArray) or (d as PackedByteArray).size() != packet_bytes():
		dropped += 1
		return
	received += 1
	var sp: _Speaker = _speakers.get(p)
	if sp == null:
		sp = _Speaker.new()
		_speakers[p] = sp
	# Stale: older than what's already been played out, or from before a long silence.
	var gap := clock_ms - sp.heard_ms
	var fresh := gap > int(cfg.get("max_buffer_ms", 360)) * 2
	if fresh:
		sp.pending.clear()
		sp.next_seq = -1
		sp.playing = false
		sp.started_ms = clock_ms
		sp.gap_since = -1
	elif sp.next_seq >= 0 and s < sp.next_seq:
		dropped += 1
		return
	elif sp.pending.is_empty() and gap > int(cfg.get("jitter_ms", 80)):
		# A new burst after a pause (a breath, the gate closing): wait for stragglers
		# again before playing, as at the start.
		sp.playing = false
		sp.started_ms = clock_ms
		sp.gap_since = -1
	sp.heard_ms = clock_ms
	var n := frame_samples()
	var fb := VoiceCodec.frame_bytes(n)
	var pcm := PackedFloat32Array()
	var peak := 0.0
	for k in frames_per_packet():
		var part := VoiceCodec.decode_frame((d as PackedByteArray).slice(k * fb, (k + 1) * fb), n)
		for v in part:
			peak = maxf(peak, absf(v))
		pcm.append_array(part)
	sp.level = peak
	sp.pending[s] = pcm
	# Too much queued (the other side ran ahead, or we stalled): drop the oldest.
	var most := maxi(1, int(cfg.get("max_buffer_ms", 360)) / (int(cfg.get("frame_ms", 20)) * frames_per_packet()))
	while sp.pending.size() > most:
		var keys := sp.pending.keys()
		keys.sort()
		sp.pending.erase(keys[0])
		sp.next_seq = int(keys[1]) if keys.size() > 1 else -1
		dropped += 1


## The next samples of player `p`'s voice to play, in order, up to `most` of them: an
## empty array when there's nothing ready (silence: let the speaker starve). A burst
## starts playing once `jitter_ms` of it has queued, or that long has passed since
## its first packet; a packet that hasn't come `jitter_ms` after its turn came up is
## given up on (the lost 40 ms), and the ones after it play.
func pull(p: int, most: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var sp: _Speaker = _speakers.get(p)
	if sp == null or sp.pending.is_empty():
		return out
	var jitter := int(cfg.get("jitter_ms", 80))
	var per_packet := int(cfg.get("frame_ms", 20)) * frames_per_packet()
	if not sp.playing:
		if sp.pending.size() * per_packet < jitter and clock_ms - sp.started_ms < jitter:
			return out
		sp.playing = true
	while out.size() < most and not sp.pending.is_empty():
		var keys := sp.pending.keys()
		keys.sort()
		var s := int(keys[0])
		if sp.next_seq >= 0 and s > sp.next_seq:
			# A gap: give the missing packet `jitter_ms` from when its turn came up (not
			# from the last arrival, or steady talk would hold the wait open for ever).
			if sp.gap_since < 0:
				sp.gap_since = clock_ms
			if clock_ms - sp.gap_since < jitter:
				break
			dropped += s - sp.next_seq
		sp.gap_since = -1
		out.append_array(sp.pending[s])
		sp.pending.erase(s)
		sp.next_seq = s + 1
	return out


## Whether player `p` was heard within `talk_show_ms` (the icon over their fighter).
func speaking(p: int) -> bool:
	var sp: _Speaker = _speakers.get(p)
	return sp != null and clock_ms - sp.heard_ms <= int(cfg.get("talk_show_ms", 260))


## The peak of the last packet heard from `p`, 0..1.
func level(p: int) -> float:
	var sp: _Speaker = _speakers.get(p)
	return sp.level if sp != null and speaking(p) else 0.0


## Packets of `p`'s voice queued and not yet played (the net line, tests).
func queued(p: int) -> int:
	var sp: _Speaker = _speakers.get(p)
	return sp.pending.size() if sp != null else 0


## Slots heard from at all this match.
func heard_slots() -> Array:
	return _speakers.keys()


## A new match (a rematch, the room's next): old packets must not play into it.
func reset(p_match_id: int, p_slot: int) -> void:
	match_id = p_match_id
	slot = p_slot
	_speakers.clear()
	_pending.clear()
	_frames.clear()
	_enc_state.clear()
	talking = false


# ------------------------------------------------------------------ placing a voice

## How loud a voice `dist` world pixels away plays, 0..1: full inside `full_radius`,
## fading to nothing at `silent_radius`. A teammate never drops below `team_floor`,
## so a team can still call plays across the map.
static func gain_for(dist: float, same_team: bool, c: Dictionary = {}) -> float:
	if c.is_empty():
		c = data()
	var full := float(c.get("full_radius", 110.0))
	var silent := float(c.get("silent_radius", 420.0))
	var g := 1.0
	if dist > full:
		g = 1.0 - (dist - full) / maxf(1.0, silent - full)
		g = clampf(g, 0.0, 1.0)
		g = g * g  # quieter sooner, like sound in the open
	if same_team:
		g = maxf(g, float(c.get("team_floor", 0.25)))
	return g


## Stereo placement for a voice `dx` world pixels to the listener's right (negative:
## left), -1..1, reaching the edges `pan_width` away.
static func pan_for(dx: float, c: Dictionary = {}) -> float:
	if c.is_empty():
		c = data()
	return clampf(dx / maxf(1.0, float(c.get("pan_width", 240.0))), -1.0, 1.0)
