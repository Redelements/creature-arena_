extends TestCase
## Proximity voice chat (VoiceChat, VoiceCodec, data/voice.json): the codec keeps speech
## clear, the resampler keeps the level and the length, push to talk and the open-mic
## gate send only while talking, the jitter buffer plays in order and skips what's lost,
## the placing (gain_for, pan_for) fades with distance, and the "vc" packets travel
## between two Netplay sessions and through the dedicated server: only for the match on
## now, never to a player who turned voice off, never from a spectator, to spectators
## only in a room's match, at most VOICE_RATE a second per sender, always carrying the
## sender's real slot. "start" names every slot, so a mute by slot carries over by name
## through a room's re-seating. Nothing here touches the simulation: the match stays in sync.

const RATE := 16000


## `seconds` of a voice-like signal: a 180 Hz tone with overtones at 900 Hz and 2.4 kHz,
## peaking at `amp`.
func _voice(seconds: float, amp := 0.4, start := 0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(seconds * RATE)
	out.resize(n)
	for i in n:
		var t := float(start + i) / RATE
		out[i] = amp * (0.6 * sin(TAU * 180.0 * t) + 0.3 * sin(TAU * 900.0 * t) + 0.1 * sin(TAU * 2400.0 * t))
	return out


func _tone(n: int, hz: float, rate: float, amp := 0.5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = amp * sin(TAU * hz * float(i) / rate)
	return out


## The signal-to-noise ratio of `got` against `want`, in dB.
func _snr(want: PackedFloat32Array, got: PackedFloat32Array) -> float:
	var sig := 0.0
	var err := 0.0
	for i in mini(want.size(), got.size()):
		sig += want[i] * want[i]
		err += (want[i] - got[i]) * (want[i] - got[i])
	return 10.0 * log(sig / maxf(err, 1e-12)) / log(10.0)


## One packet's audio: every sample `value` (its frames' headers start on it, so the
## decoded packet's first sample tells which packet it was).
func _packet(v: VoiceChat, value: float) -> PackedByteArray:
	var d := PackedByteArray()
	var frame := PackedFloat32Array()
	frame.resize(v.frame_samples())
	frame.fill(value)
	for k in v.frames_per_packet():
		d.append_array(VoiceCodec.encode_frame(frame, {}))
	return d


func _vc(v: VoiceChat, p: int, s: int, value := 0.1) -> Dictionary:
	return {"t": "vc", "n": v.match_id, "p": p, "s": s, "d": _packet(v, value)}


## A listener on slot 1 of match 1 (no link needed to receive).
func _listener() -> VoiceChat:
	var v := VoiceChat.new()
	v.reset(1, 1)
	return v


## Two VoiceChats over an in-memory link, slots 0 and 1 of match 1.
func _two() -> Array:
	var links := LoopLink.pair()
	var a := VoiceChat.new()
	var b := VoiceChat.new()
	a.link = links[0]
	b.link = links[1]
	a.reset(1, 0)
	b.reset(1, 1)
	return [a, b]


## What `b`'s end of the link has received, handed to it.
func _deliver(b: VoiceChat) -> void:
	for m in b.link.poll():
		if String(m.get("t", "")) == "vc":
			b.receive(m)


# ------------------------------------------------------------------ codec

func test_the_codec_keeps_a_voice_clear_and_each_frame_the_size_it_should_be() -> void:
	var v := VoiceChat.new()
	var n := v.frame_samples()
	assert_eq(n, 320, "a 20 ms frame at 16 kHz:")
	var pcm := _voice(1.0)
	var state := {}
	var got := PackedFloat32Array()
	for k in pcm.size() / n:
		var bytes := VoiceCodec.encode_frame(pcm.slice(k * n, (k + 1) * n), state)
		assert_eq(bytes.size(), VoiceCodec.frame_bytes(n), "frame %d's size:" % k)
		got.append_array(VoiceCodec.decode_frame(bytes, n))
	assert_eq(got.size(), pcm.size(), "every sample comes back:")
	var snr := _snr(pcm, got)
	assert_gt(snr, 25.0, "the signal-to-noise ratio (%.1f dB)" % snr)
	assert_eq(v.packet_bytes(), 326, "a packet is two 163-byte frames:")


func test_silence_decodes_to_silence_and_a_short_frame_to_nothing() -> void:
	var quiet := PackedFloat32Array()
	quiet.resize(320)
	var got := VoiceCodec.decode_frame(VoiceCodec.encode_frame(quiet, {}), 320)
	var peak := 0.0
	for x in got:
		peak = maxf(peak, absf(x))
	assert_lt(peak, 0.001, "silence stays silent")
	assert_eq(VoiceCodec.decode_frame(PackedByteArray([1, 2, 3, 4]), 320).size(), 0, "a too-short frame decodes to nothing:")
	assert_eq(VoiceCodec.decode_frame(PackedByteArray(), 320).size(), 0, "nor does an empty one:")


# ------------------------------------------------------------------ resampler

func _resample_check(src_rate: int, piece: int) -> void:
	var state := {}
	var src := _tone(piece * 60, 440.0, src_rate)
	var out := PackedFloat32Array()
	for k in 60:
		out.append_array(VoiceCodec.resample(src.slice(k * piece, (k + 1) * piece), src_rate, RATE, state))
	assert_near(float(out.size()), float(RATE), 2.0, "%d Hz -> 16 kHz in 60 pieces, the samples:" % src_rate)
	# The level after the filter has settled (skip its first few milliseconds).
	var a := VoiceCodec.level_db(src.slice(src_rate / 10))
	var b := VoiceCodec.level_db(out.slice(RATE / 10))
	assert_near(b, a, 1.5, "%d Hz -> 16 kHz, a 440 Hz tone's level (dB):" % src_rate)


func test_resampling_44100_to_16000_keeps_the_length_and_the_level() -> void:
	_resample_check(44100, 735)


func test_resampling_48000_to_16000_keeps_the_length_and_the_level() -> void:
	_resample_check(48000, 800)


# ------------------------------------------------------------------ sending

func test_push_to_talk_sends_only_while_held_and_the_far_side_hears_it_in_order() -> void:
	var ab := _two()
	var a: VoiceChat = ab[0]
	var b: VoiceChat = ab[1]
	var n := a.frame_samples()
	a.mode = VoiceChat.Mode.PUSH_TO_TALK
	for k in 10:
		a.clock_ms += 20
		a.push_mic(_voice(0.02, 0.4, k * n), false)
	assert_eq(a.sent, 0, "not held: nothing sent:")
	assert_false(a.talking, "and not talking")
	# Held: a slow ramp from -0.5 to 0.5, so the order is easy to see.
	var frames := 40
	var ramp := PackedFloat32Array()
	ramp.resize(frames * n)
	for i in ramp.size():
		ramp[i] = -0.5 + float(i) / float(ramp.size() - 1)
	var heard := PackedFloat32Array()
	for k in frames:
		a.clock_ms += 20
		b.clock_ms = a.clock_ms
		a.push_mic(ramp.slice(k * n, (k + 1) * n), true)
		assert_true(a.talking, "held: talking (frame %d)" % k)
		_deliver(b)
		heard.append_array(b.pull(0, 1 << 20))
	for k in 6:  # let the last packets play out
		b.clock_ms += 20
		_deliver(b)
		heard.append_array(b.pull(0, 1 << 20))
	assert_eq(a.sent, frames / a.frames_per_packet(), "a packet every two frames:")
	assert_eq(b.received, a.sent, "every packet arrived:")
	assert_eq(heard.size(), ramp.size(), "every sample played:")
	var worst := 0.0
	var backwards := 0.0
	for i in mini(heard.size(), ramp.size()):
		worst = maxf(worst, absf(heard[i] - ramp[i]))
		if i > 0:
			backwards = maxf(backwards, heard[i - 1] - heard[i])
	assert_lt(worst, 0.01, "the samples come back in order, close to what was said")
	assert_lt(backwards, 0.003, "and the ramp never runs backwards (beyond the codec's step)")
	# Released: talking stops within ptt_release_ms.
	var held_at := a.clock_ms
	var stopped_at := -1
	for k in 30:
		a.clock_ms += 20
		a.push_mic(ramp.slice(0, n), false)
		if not a.talking:
			stopped_at = a.clock_ms
			break
	assert_true(stopped_at > 0, "released: talking stops")
	assert_true(stopped_at - held_at <= int(a.cfg["ptt_release_ms"]) + int(a.cfg["frame_ms"]),
		"within ptt_release_ms (%d ms after the release)" % (stopped_at - held_at))
	var sent := a.sent
	for k in 10:
		a.clock_ms += 20
		a.push_mic(ramp.slice(0, n), false)
	assert_eq(a.sent, sent, "and nothing more is sent:")


func test_the_open_mic_gate_sends_loud_frames_only_and_stops_after_its_hold() -> void:
	var ab := _two()
	var a: VoiceChat = ab[0]
	a.mode = VoiceChat.Mode.OPEN_MIC
	var n := a.frame_samples()
	for k in 20:
		a.clock_ms += 20
		a.push_mic(_tone(n, 300.0, RATE, 0.001), false)
	assert_eq(a.sent, 0, "quiet frames send nothing:")
	for k in 20:
		a.clock_ms += 20
		a.push_mic(_voice(0.02, 0.4, k * n), false)
	assert_eq(a.sent, 10, "loud ones do:")
	var quiet_from := a.clock_ms
	var last_send := quiet_from
	for k in 60:
		a.clock_ms += 20
		var before := a.sent
		a.push_mic(_tone(n, 300.0, RATE, 0.001), false)
		if a.sent > before:
			last_send = a.clock_ms
	assert_gt(float(last_send - quiet_from), 0.0, "the hold carries on a moment after it goes quiet")
	assert_true(last_send - quiet_from <= int(a.cfg["gate_hold_ms"]),
		"and sending stops within gate_hold_ms (%d ms)" % (last_send - quiet_from))
	assert_false(a.talking, "not talking by the end")


# ------------------------------------------------------------------ receiving

func test_the_jitter_buffer_plays_in_order_and_skips_a_lost_packet() -> void:
	var v := _listener()
	for s in [0, 1, 3, 4]:
		v.receive(_vc(v, 0, s, 0.1 * (s + 1)))
	assert_eq(v.received, 4, "four packets in:")
	var per := v.frame_samples() * v.frames_per_packet()
	var first := v.pull(0, 1 << 20)
	assert_eq(first.size(), per * 2, "0 and 1 play; 3 waits a moment for the missing 2:")
	if first.size() == per * 2:
		assert_near(first[0], 0.1, 0.002, "packet 0 first:")
		assert_near(first[per], 0.2, 0.002, "then packet 1:")
	assert_eq(v.dropped, 0, "nothing given up on yet:")
	v.clock_ms += int(v.cfg["jitter_ms"]) + 20
	var rest := v.pull(0, 1 << 20)
	assert_eq(rest.size(), per * 2, "then 3 and 4 play:")
	if rest.size() == per * 2:
		assert_near(rest[0], 0.4, 0.002, "packet 3:")
		assert_near(rest[per], 0.5, 0.002, "then packet 4:")
	assert_eq(v.dropped, 1, "and the lost packet is counted:")
	# Late: older than what has already played.
	v.receive(_vc(v, 0, 2, 0.3))
	assert_eq(v.dropped, 2, "a packet older than next_seq is dropped:")
	assert_eq(v.pull(0, 1 << 20).size(), 0, "and never plays:")


func test_steady_talk_with_one_lost_packet_plays_on_without_stalling() -> void:
	# Packets every 40 ms for 30 packets, number 7 lost, pulled every 16 ms like a frame.
	# The missing one is given up on jitter_ms after its turn, so the queue never
	# piles up behind it (it used to wait for ever while packets kept coming).
	var v := _listener()
	var per := v.frame_samples() * v.frames_per_packet()
	var step := int(v.cfg["frame_ms"]) * v.frames_per_packet()
	var got := 0
	var most_pending := 0
	var s := 0
	var t := 0
	while t < 30 * step:
		v.clock_ms = t
		while s < 30 and s * step <= t:  # every packet due by now
			if s != 7:
				v.receive(_vc(v, 0, s, 0.1))
			s += 1
		got += v.pull(0, 1 << 20).size()
		most_pending = maxi(most_pending, (v._speakers[0] as VoiceChat._Speaker).pending.size())
		t += 16
	v.clock_ms = t + int(v.cfg["jitter_ms"]) * 2
	got += v.pull(0, 1 << 20).size()
	assert_eq(got, per * 29, "every packet but the lost one played:")
	assert_eq(v.dropped, 1, "the lost one counted:")
	assert_true(most_pending <= 4, "the queue never piled up behind the gap (most queued: %d)" % most_pending)


func test_a_burst_after_a_short_pause_waits_for_stragglers_again() -> void:
	var v := _listener()
	v.receive(_vc(v, 0, 0, 0.1))
	v.receive(_vc(v, 0, 1, 0.1))
	assert_gt(float(v.pull(0, 1 << 20).size()), 0.0, "jitter_ms of audio queued: it plays")
	v.clock_ms += int(v.cfg["jitter_ms"]) * 3  # a breath, well under the stale limit
	v.receive(_vc(v, 0, 2, 0.1))
	assert_eq(v.pull(0, 1 << 20).size(), 0, "the new burst's first packet waits for the next")
	v.clock_ms += int(v.cfg["jitter_ms"])
	assert_gt(float(v.pull(0, 1 << 20).size()), 0.0, "and plays once the wait has passed")


func test_a_mute_sticks_by_name_but_never_by_the_default_name() -> void:
	var v := VoiceChat.new()
	v.reset(1, 0, ["Me", "Rival", "Player", "CPU"])
	v.set_muted(1, true)
	v.set_muted(2, true)
	assert_true(v.is_muted(1) and v.is_muted(2), "both muted this match")
	assert_true(v.blocked.has("Rival"), "a real name is remembered:")
	assert_false(v.blocked.has("Player"), "the default name isn't:")
	v.reset(2, 0, ["Me", "Player", "Rival", "Someone"])
	assert_true(v.is_muted(2), "Rival is still muted on the new slot")
	assert_false(v.is_muted(1), "a new 'Player' isn't")
	assert_false(v.is_muted(3), "nor anyone else")


func test_malformed_packets_and_your_own_echo_are_dropped() -> void:
	var v := _listener()
	var bad := _vc(v, 0, 0)
	bad["d"] = (bad["d"] as PackedByteArray).slice(0, 100)
	v.receive(bad)
	assert_eq(v.received, 0, "a packet of the wrong size isn't taken:")
	assert_eq(v.dropped, 1, "and is counted:")
	var not_bytes := _vc(v, 0, 0)
	not_bytes["d"] = "hello"
	v.receive(not_bytes)
	assert_eq(v.dropped, 2, "nor one whose audio isn't bytes:")
	v.receive(_vc(v, 1, 0))
	assert_eq(v.received, 0, "nor this machine's own voice coming back:")
	assert_eq(v.dropped, 3, "")
	assert_false(v.speaking(1), "so it never shows as speaking")


func test_nothing_plays_until_the_jitter_wait_has_queued_or_passed() -> void:
	var v := _listener()
	v.receive(_vc(v, 0, 0))
	assert_eq(v.pull(0, 1 << 20).size(), 0, "one packet just in: wait")
	v.clock_ms = int(v.cfg["jitter_ms"]) - 1
	assert_eq(v.pull(0, 1 << 20).size(), 0, "still waiting just before jitter_ms")
	v.clock_ms = int(v.cfg["jitter_ms"])
	assert_gt(float(v.pull(0, 1 << 20).size()), 0.0, "and plays once jitter_ms has passed")
	var w := _listener()
	w.receive(_vc(w, 0, 0))
	w.receive(_vc(w, 0, 1))
	assert_gt(float(w.pull(0, 1 << 20).size()), 0.0, "or at once when jitter_ms of audio has queued")


func test_a_burst_after_a_long_silence_starts_fresh() -> void:
	var v := _listener()
	for s in 3:
		v.receive(_vc(v, 0, s, 0.1))
	var per := v.frame_samples() * v.frames_per_packet()
	assert_eq(v.pull(0, per).size(), per, "one packet plays, two stay queued:")
	assert_true(v._speakers[0].playing, "playing")
	v.clock_ms += int(v.cfg["max_buffer_ms"]) * 2 + 1
	v.receive(_vc(v, 0, 10, 0.7))
	var sp = v._speakers[0]
	assert_false(sp.playing, "the new burst waits to prebuffer")
	assert_eq(sp.pending.keys(), [10], "the old queue is gone:")
	assert_eq(v.pull(0, 1 << 20).size(), 0, "nothing plays at once")
	v.clock_ms += int(v.cfg["jitter_ms"])
	var got := v.pull(0, 1 << 20)
	assert_eq(got.size(), per, "then only the new packet:")
	if got.size() > 0:
		assert_near(got[0], 0.7, 0.002, "the new burst's audio:")


func test_reset_forgets_every_voice() -> void:
	var v := _listener()
	v.receive(_vc(v, 0, 0))
	v.receive(_vc(v, 0, 1))
	assert_true(v.speaking(0), "heard: speaking")
	v.reset(2, 1)
	assert_false(v.speaking(0), "after a reset nobody is speaking")
	assert_eq(v.pull(0, 1 << 20).size(), 0, "and nothing is left to play:")
	assert_eq(v.match_id, 2, "the new match:")


# ------------------------------------------------------------------ placing

func test_gain_fades_with_distance_and_a_teammate_keeps_a_floor() -> void:
	var c := VoiceChat.data()
	var full := float(c["full_radius"])
	var silent := float(c["silent_radius"])
	assert_eq(VoiceChat.gain_for(0.0, false), 1.0, "right beside:")
	assert_eq(VoiceChat.gain_for(full, false), 1.0, "at full_radius:")
	assert_eq(VoiceChat.gain_for(silent, false), 0.0, "an enemy at silent_radius:")
	assert_eq(VoiceChat.gain_for(silent * 3.0, false), 0.0, "far beyond it:")
	assert_near(VoiceChat.gain_for(silent * 3.0, true), float(c["team_floor"]), 0.0001, "a teammate far away:")
	var last := 1.0
	var d := full + 5.0
	while d < silent:
		var g := VoiceChat.gain_for(d, false)
		assert_lt(g, last, "quieter at %d than closer in" % int(d))
		last = g
		d += 10.0
	var w := float(c["pan_width"])
	assert_eq(VoiceChat.pan_for(-w), -1.0, "pan_width to the left:")
	assert_eq(VoiceChat.pan_for(0.0), 0.0, "straight ahead:")
	assert_eq(VoiceChat.pan_for(w * 2.0), 1.0, "past the right edge:")


# ------------------------------------------------------------------ over Netplay

func _pair(guest_voice := VoiceChat.Mode.PUSH_TO_TALK) -> Array:
	var links := LoopLink.pair(1, 0, 0.0, 7)
	var host := Netplay.new()
	var guest := Netplay.new()
	guest.voice.mode = guest_voice
	host.host(0, ["cairn"], links[0])
	guest.join("loop", 0, ["culvert"], links[1])
	return [host, guest]


## Ticks every session (and the server), each one's voice clock 16 ms a tick; while
## `talker` is set it says a tone into its mic with push to talk held.
func _talk(nets: Array, ticks: int, talker: Netplay = null, server: RelayServer = null) -> void:
	for i in ticks:
		for n: Netplay in nets:
			n.voice.clock_ms += 16
		if talker != null:
			talker.voice.push_mic(_voice(0.016, 0.4, i * 256), true)
		for n: Netplay in nets:
			n.tick(0)
		if server != null:
			server.tick()


func _until(nets: Array, ticks: int, cond: Callable, server: RelayServer = null) -> bool:
	for i in ticks:
		_talk(nets, 1, null, server)
		if cond.call():
			return true
	return false


func _all_playing(nets: Array) -> bool:
	for n: Netplay in nets:
		if not n.is_playing():
			return false
	return true


func test_two_sessions_talk_over_the_link_and_the_match_stays_in_sync() -> void:
	var nets := _pair()
	var host: Netplay = nets[0]
	var guest: Netplay = nets[1]
	assert_true(_until(nets, 200, func(): return _all_playing(nets)), "both start playing")
	assert_eq(host.voice.match_id, host.game.id, "the host's voice is on the match:")
	assert_eq(guest.voice.slot, guest.local_slot, "the guest's voice has its slot:")
	host.voice.mode = VoiceChat.Mode.PUSH_TO_TALK
	_talk(nets, 30, host)
	assert_gt(float(host.voice.sent), 0.0, "the host sent its voice")
	assert_gt(float(guest.voice.received), 0.0, "the guest got it")
	assert_true(guest.voice.speaking(host.local_slot), "the host shows as speaking")
	assert_gt(float(guest.voice.pull(host.local_slot, 1 << 20).size()), 0.0, "and its voice plays")
	_talk(nets, 120)
	assert_eq(host.game.desync_frame, -1, "the host's match stays in sync:")
	assert_eq(guest.game.desync_frame, -1, "the guest's too:")


func test_a_player_with_voice_off_still_plays_and_hears_nothing() -> void:
	var nets := _pair(VoiceChat.Mode.OFF)
	var host: Netplay = nets[0]
	var guest: Netplay = nets[1]
	assert_true(_until(nets, 200, func(): return _all_playing(nets)), "both start playing")
	_talk(nets, 30, host)
	assert_gt(float(host.voice.sent), 0.0, "the host talks")
	assert_eq(guest.voice.received, 0, "the guest, voice off, takes none of it:")
	assert_eq(guest.voice.sent, 0, "and sends none:")
	_talk(nets, 60)
	assert_eq(guest.game.desync_frame, -1, "the match plays normally:")


# ------------------------------------------------------------------ through the server

func _client(server: RelayServer, i: int, size: int, fighter: String, p_room := "") -> Netplay:
	var links := LoopLink.pair(1, 0, 0.0, 5 + i * 13)
	server.add_client(links[0], "test:%d" % i)
	var n := Netplay.new()
	n.team_size = size
	n.room = p_room
	n.my_name = "P%d" % i
	n.join("server", 0, [fighter], links[1])
	(n.link as LoopLink).keep_heard = true
	return n


func _heard_vc(n: Netplay) -> Array:
	return (n.link as LoopLink).heard.filter(func(m): return String(m.get("t", "")) == "vc")


func _watcher(server: RelayServer, i: int, p_room := "", mode := VoiceChat.Mode.PUSH_TO_TALK) -> Netplay:
	var links := LoopLink.pair(1, 0, 0.0, 99 + i * 13)
	server.add_client(links[0], "watch:%d" % i)
	var w := Netplay.new()
	w.voice.mode = mode
	w.spectate("server", 0, p_room, links[1])
	(w.link as LoopLink).keep_heard = true
	return w


## One packet's worth of silence, well-formed.
func _blank(n: Netplay) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(n.voice.packet_bytes())
	return d


func test_the_server_relays_voice_to_those_who_want_it_but_not_quick_match_spectators() -> void:
	var server := RelayServer.new()
	var fighters := ["cairn", "culvert", "sno", "barkley"]
	var nets: Array = []
	for i in 4:
		nets.append(_client(server, i, 2, fighters[i]))
	var off: Netplay = nets[3]
	off.voice.mode = VoiceChat.Mode.OFF  # said in hello: the server sends this one nothing
	assert_true(_until(nets, 300, func(): return _all_playing(nets), server), "a 2v2 starts")
	var w := _watcher(server, 0)  # Quick match: a stranger watching whatever is on
	var all: Array = nets + [w]
	assert_true(_until(all, 300, func(): return w.is_watching(), server), "a spectator joins the match")
	var talker: Netplay = nets[0]
	_talk(all, 40, talker, server)
	_talk(all, 10, null, server)
	assert_gt(float(talker.voice.sent), 10.0, "player 0 talked")
	for k in [1, 2]:
		assert_gt(float((nets[k] as Netplay).voice.received), 0.0, "player %d hears it" % k)
	assert_eq(off.voice.received, 0, "the player with voice off hears nothing:")
	assert_eq(_heard_vc(off).size(), 0, "and the server sent them nothing:")
	assert_eq(w.voice.received, 0, "a Quick match spectator hears nothing:")
	assert_eq(_heard_vc(w).size(), 0, "the server sends them none of it:")
	for n: Netplay in nets:
		assert_eq(w.voice.name_of(n.local_slot), n.my_name, "the spectator's start names slot %d:" % n.local_slot)
		for o: Netplay in nets:
			assert_eq(n.voice.name_of(o.local_slot), o.my_name, "slot %d's start names slot %d:" % [n.local_slot, o.local_slot])
	for m in _heard_vc(nets[1]):
		if int(m["p"]) != talker.local_slot:
			fail("a relayed packet carries slot %s, not the talker's %d" % [str(m["p"]), talker.local_slot])
			break
	# A lie about whose voice it is: the server puts the real slot on it.
	var good := PackedByteArray()
	good.resize(talker.voice.packet_bytes())
	talker.link.send({"t": "vc", "n": talker.game.id, "p": (nets[2] as Netplay).local_slot, "s": 9000, "d": good})
	# The wrong size, and a spectator talking: neither is relayed.
	talker.link.send({"t": "vc", "n": talker.game.id, "p": talker.local_slot, "s": 9001, "d": good.slice(0, 10)})
	w.link.send({"t": "vc", "n": w._watch_n, "p": 0, "s": 9002, "d": good})
	_talk(all, 10, null, server)
	var seen := {}
	for m in _heard_vc(nets[1]):
		seen[int(m["s"])] = int(m["p"])
	assert_true(seen.has(9000), "the well-formed packet is relayed")
	assert_eq(seen.get(9000, -1), talker.local_slot, "with the sender's real slot, not the one it claimed:")
	assert_false(seen.has(9001), "a packet of the wrong size isn't relayed")
	assert_false(seen.has(9002), "nor a spectator's voice")
	assert_eq(_heard_vc(off).size(), 0, "still nothing to the player with voice off:")
	for n: Netplay in nets:
		assert_eq(n.game.desync_frame, -1, "the match stays in sync (slot %d):" % n.local_slot)


func test_after_a_rematch_the_last_matchs_voice_is_ignored() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0
	var a := _client(server, 0, 1, "cairn")
	var b := _client(server, 1, 1, "culvert")
	var nets := [a, b]
	assert_true(_until(nets, 300, func(): return _all_playing(nets), server), "a 1v1 starts")
	_talk(nets, 20, a, server)
	assert_gt(float(b.voice.received), 0.0, "B hears A in match 1")
	a.request_rematch()
	b.request_rematch()
	assert_true(_until(nets, 60, func(): return a.rematch_pick() and b.rematch_pick(), server), "both pick again")
	a.send_pick(["sno"])
	b.send_pick(["barkley"])
	assert_true(_until(nets, 90, func(): return a.game.id == 2 and b.game.id == 2, server), "the rematch starts")
	assert_false(b.voice.speaking(a.local_slot), "the new match starts with nobody speaking")
	assert_eq(b.voice.match_id, 2, "B's voice is on match 2:")
	var heard := b.voice.received
	var d := PackedByteArray()
	d.resize(a.voice.packet_bytes())
	# Through the server: it drops the old match's packet.
	a.link.send({"t": "vc", "n": 1, "p": a.local_slot, "s": 5000, "d": d})
	_talk(nets, 6, null, server)
	assert_eq(b.voice.received, heard, "match 1's packet through the server isn't heard:")
	# Straight to B (as if it was in flight when the rematch started): B drops it too.
	b._handle({"t": "vc", "n": 1, "p": a.local_slot, "s": 5001, "d": d})
	assert_eq(b.voice.received, heard, "nor one that reaches B late:")
	b._handle({"t": "vc", "n": 2, "p": a.local_slot, "s": 5002, "d": d})
	assert_eq(b.voice.received, heard + 1, "but match 2's is:")
	_talk(nets, 20, a, server)
	assert_gt(float(b.voice.received), float(heard + 1), "and A's voice in match 2 comes through")


func test_a_rooms_spectators_hear_its_voices_and_the_players_see_them_come_and_go() -> void:
	var server := RelayServer.new()
	var a := _client(server, 0, 1, "cairn", "v")
	var b := _client(server, 1, 1, "culvert", "v")
	var nets := [a, b]
	assert_true(_until(nets, 300, func(): return _all_playing(nets), server), "a room's 1v1 starts")
	var w := _watcher(server, 0, "v")
	var deaf := _watcher(server, 1, "v", VoiceChat.Mode.OFF)  # turned voice off: hears nothing
	var all: Array = nets + [w, deaf]
	assert_true(_until(all, 300, func(): return w.is_watching() and deaf.is_watching(), server), "two spectators join by code")
	assert_true(_until(all, 30, func(): return a.room_watchers == 2 and b.room_watchers == 2, server),
		"the players are told two are watching (%d, %d)" % [a.room_watchers, b.room_watchers])
	_talk(all, 40, a, server)
	_talk(all, 10, null, server)
	assert_gt(float(a.voice.sent), 10.0, "A talked")
	assert_gt(float(b.voice.received), 0.0, "B hears it")
	assert_gt(float(w.voice.received), 0.0, "the room's spectator hears it too")
	assert_eq(_heard_vc(deaf).size(), 0, "but not the one who turned voice off:")
	assert_eq(w.voice.name_of(a.local_slot), "P0", "the spectator's start names the players:")
	assert_eq(w.voice.name_of(b.local_slot), "P1", "")
	w.leave()
	assert_true(_until(nets, 30, func(): return a.room_watchers == 1 and b.room_watchers == 1, server),
		"one spectator leaves mid-match: the players are told (%d, %d)" % [a.room_watchers, b.room_watchers])
	deaf.leave()
	assert_true(_until(nets, 30, func(): return a.room_watchers == 0 and b.room_watchers == 0, server),
		"the other leaves: nobody is listening (%d, %d)" % [a.room_watchers, b.room_watchers])
	assert_true(_all_playing(nets), "and the match plays on")
	assert_eq(a.game.desync_frame, -1, "in sync:")


func test_the_server_relays_at_most_the_voice_budget_and_keeps_the_connection() -> void:
	var server := RelayServer.new()
	var a := _client(server, 0, 1, "cairn")
	var b := _client(server, 1, 1, "culvert")
	var nets := [a, b]
	assert_true(_until(nets, 300, func(): return _all_playing(nets), server), "a 1v1 starts")
	var d := _blank(a)
	for k in 200:
		a.link.send({"t": "vc", "n": a.game.id, "p": a.local_slot, "s": 10000 + k, "d": d})
	_talk(nets, 6, null, server)
	var first := _heard_vc(b).filter(func(m): return int(m["s"]) >= 10000 and int(m["s"]) < 10200).size()
	assert_eq(first, RelayServer.VOICE_BURST, "200 voice packets at once: VOICE_BURST relayed:")
	var sc: RelayServer.Client = null
	for c: RelayServer.Client in server.clients.values():
		if c.slot == a.local_slot and not c.watch:
			sc = c
	assert_true(sc != null and sc.voice_dropped == 200 - RelayServer.VOICE_BURST,
		"the rest counted as dropped (%d)" % (sc.voice_dropped if sc != null else -1))
	assert_eq(a.link.status, NetLink.Status.CONNECTED, "the connection is kept:")
	assert_eq(server.clients.size(), 2, "nobody dropped:")
	var frame := b.game.session.frame
	_talk(nets, 60, null, server)  # a second of the limits' clock refills the budget
	assert_gt(float(b.game.session.frame), float(frame + 40), "inputs are still relayed: the match plays on")
	for k in 40:
		a.link.send({"t": "vc", "n": a.game.id, "p": a.local_slot, "s": 20000 + k, "d": d})
	_talk(nets, 6, null, server)
	var again := _heard_vc(b).filter(func(m): return int(m["s"]) >= 20000).size()
	assert_true(again >= RelayServer.VOICE_RATE and again < 40,
		"a second later about VOICE_RATE more get through (%d of 40)" % again)
	# An honest talker (25 packets a second) is never held back.
	_talk(nets, 120, null, server)  # the budget fills up again
	var dropped := sc.voice_dropped
	var before := _heard_vc(b).size()
	var sent := a.voice.sent
	_talk(nets, 180, a, server)
	_talk(nets, 6, null, server)
	assert_gt(float(a.voice.sent - sent), 60.0, "A talked for three seconds")
	assert_eq(sc.voice_dropped, dropped, "none of honest talk is dropped:")
	assert_eq(_heard_vc(b).size() - before, a.voice.sent - sent, "every packet relayed:")
	assert_eq(b.game.desync_frame, -1, "in sync:")


func test_direct_play_names_both_players_in_start() -> void:
	var nets := _pair()
	var host: Netplay = nets[0]
	var guest: Netplay = nets[1]
	host.my_name = "Hosty"
	guest.my_name = "Guesty"
	assert_true(_until(nets, 200, func(): return _all_playing(nets)), "both start playing")
	assert_eq(host.voice.names, ["Hosty", "Guesty"], "the host names both (the guest's from its hello):")
	assert_eq(guest.voice.names, ["Hosty", "Guesty"], "and so does the guest, from the host's start:")
	assert_eq(guest.their_name, "Hosty", "the guest knows the host's name now:")


func test_start_names_are_checked() -> void:
	assert_eq(Netplay.names_from(["a", "b"], 2), ["a", "b"], "well-formed:")
	assert_eq(Netplay.names_from(["a"], 2), ["", ""], "the wrong count: all unknown:")
	assert_eq(Netplay.names_from(["a", 5], 2), ["", ""], "not all Strings: all unknown:")
	assert_eq(Netplay.names_from("ab", 2), ["", ""], "not an Array:")
	assert_eq(Netplay.names_from(null, 2), ["", ""], "missing:")
	var long := Netplay.names_from(["x".repeat(200), "  "], 2)
	assert_eq(String(long[0]).length(), Netplay.NAME_MAX, "a long name is cut:")
	assert_eq(long[1], "", "a blank one stays unknown:")
	assert_eq(Netplay.names_from(["a" + char(0x202e) + "b", "CPU"], 2), ["ab", "CPU"], "cleaned like any name:")


func test_mute_by_slot_mute_everyone_and_mute_my_mic() -> void:
	var ab := _two()
	var a: VoiceChat = ab[0]
	var b: VoiceChat = ab[1]
	var n := a.frame_samples()
	a.mode = VoiceChat.Mode.PUSH_TO_TALK
	a.mic_muted = true
	for k in 20:
		a.clock_ms += 20
		a.push_mic(_voice(0.02, 0.4, k * n), true)
	assert_eq(a.sent, 0, "my mic muted: nothing sent while held:")
	assert_false(a.talking, "and not shown as talking")
	a.mic_muted = false
	b.set_muted(0, true)
	assert_true(b.is_muted(0), "B mutes slot 0")
	assert_false(b.hearing(0), "and doesn't hear it")
	for k in 20:
		a.clock_ms += 20
		b.clock_ms = a.clock_ms
		a.push_mic(_voice(0.02, 0.4, k * n), true)
		_deliver(b)
	_deliver(b)
	assert_gt(float(a.sent), 0.0, "A talks")
	assert_eq(b.received, 0, "a muted player's packets aren't taken:")
	assert_eq(b.muted_packets, a.sent, "they're counted as muted:")
	assert_false(b.speaking(0), "and never shown as speaking")
	b.set_muted(0, false)
	b.mute_all = true
	var muted := b.muted_packets
	var sent := a.sent
	for k in 20:
		a.clock_ms += 20
		b.clock_ms = a.clock_ms
		a.push_mic(_voice(0.02, 0.4, k * n), true)
		_deliver(b)
	_deliver(b)
	assert_eq(b.received, 0, "mute everyone: nothing taken:")
	assert_eq(b.muted_packets - muted, a.sent - sent, "all of it counted as muted:")
	assert_false(b.hearing(0), "")
	b.mute_all = false
	for k in 20:
		a.clock_ms += 20
		b.clock_ms = a.clock_ms
		a.push_mic(_voice(0.02, 0.4, k * n), true)
		_deliver(b)
	assert_gt(float(b.received), 0.0, "unmuted: heard again")


func test_a_mute_carries_over_by_name_when_a_room_reseats_everyone() -> void:
	var server := RelayServer.new()
	server.rematch_locked_ms = 0
	var fighters := ["cairn", "culvert", "sno", "barkley"]
	var nets: Array = []
	for i in 4:
		nets.append(_client(server, i, 2 if i == 0 else 0, fighters[i], "m"))
	assert_true(_until(nets, 400, func(): return _all_playing(nets), server), "a 2v2 room starts")
	var me: Netplay = nets[0]
	var them: Netplay = nets[2]
	for n: Netplay in nets:
		for o: Netplay in nets:
			assert_eq(n.voice.name_of(o.local_slot), o.my_name, "match 1: slot %d's start names slot %d:" % [n.local_slot, o.local_slot])
	var old_slot := them.local_slot
	me.voice.set_muted(old_slot, true)
	assert_true(me.voice.blocked.has("P2"), "muted by slot, remembered by name")
	# Everyone picks again; two on one side picking the same fighter makes seat() move people.
	for n: Netplay in nets:
		n.request_next()
	_talk(nets, 10, null, server)
	var picks := ["sno", "culvert", "sno", "barkley"]
	for i in 4:
		(nets[i] as Netplay).send_pick([picks[i]])
	assert_true(_until(nets, 300, func():
		for n: Netplay in nets:
			if n.game == null or n.game.id != 2 or not n.is_playing():
				return false
		return true, server), "the room's next match starts")
	assert_true(them.local_slot != old_slot, "P2 was re-seated (slot %d -> %d)" % [old_slot, them.local_slot])
	for n: Netplay in nets:
		for o: Netplay in nets:
			assert_eq(n.voice.name_of(o.local_slot), o.my_name, "match 2: slot %d's start names slot %d:" % [n.local_slot, o.local_slot])
	assert_true(me.voice.is_muted(them.local_slot), "P2 is still muted on their new slot")
	assert_false(me.voice.is_muted(old_slot), "and whoever sits on the old one isn't")
	var heard := me.voice.received
	var muted := me.voice.muted_packets
	var others_heard := (nets[1] as Netplay).voice.received
	_talk(nets, 40, them, server)
	_talk(nets, 10, null, server)
	assert_gt(float(them.voice.sent), 10.0, "P2 talks")
	assert_eq(me.voice.received, heard, "P0 takes none of it:")
	assert_gt(float(me.voice.muted_packets), float(muted), "it's counted as muted")
	assert_gt(float((nets[1] as Netplay).voice.received), float(others_heard), "the others still hear P2")
