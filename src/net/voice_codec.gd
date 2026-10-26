class_name VoiceCodec
extends RefCounted
## The voice chat's sound codec: IMA ADPCM, 4 bits a sample, which the game encodes
## and decodes itself in GDScript (Godot has no Opus). At 16 kHz that is 64 kbit/s of
## speech that sounds like a phone call with the top end kept; a 20 ms frame of 320
## samples is 163 bytes. Every frame carries its own predictor and step index in a
## 3-byte header, so each one decodes on its own and a lost packet costs only itself.
##
## Also here: the resampler that takes the microphone's mix rate (44.1 or 48 kHz) down
## to the codec's, with a cheap lowpass first so speech doesn't alias, and the level
## meter the gate and the talking icons read. Nothing here touches the simulation.

const HEADER_BYTES := 3

const STEPS: Array[int] = [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
	50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
	337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
	2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
	15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
const INDEX_STEP: Array[int] = [-1, -1, -1, -1, 2, 4, 6, 8]


## How many bytes a frame of `samples` samples takes.
static func frame_bytes(samples: int) -> int:
	return HEADER_BYTES + (samples + 1) / 2


## Encodes one frame of mono samples in -1..1. `state` carries the step index from
## the previous frame (a better start than 0; the header stores it, so a frame still
## decodes alone). Pass the same Dictionary to every call.
static func encode_frame(pcm: PackedFloat32Array, state: Dictionary = {}) -> PackedByteArray:
	var n := pcm.size()
	var out := PackedByteArray()
	if n == 0:
		return out
	out.resize(frame_bytes(n))
	var pred := clampi(roundi(pcm[0] * 32767.0), -32768, 32767)
	var idx := clampi(int(state.get("index", 0)), 0, 88)
	out.encode_s16(0, pred)
	out[2] = idx
	var half := 0
	var pos := HEADER_BYTES
	var low := true
	for i in n:
		var s := clampi(roundi(pcm[i] * 32767.0), -32768, 32767)
		var step := STEPS[idx]
		var diff := s - pred
		var nib := 0
		if diff < 0:
			nib = 8
			diff = -diff
		var vp := step >> 3
		if diff >= step:
			nib |= 4
			diff -= step
			vp += step
		step >>= 1
		if diff >= step:
			nib |= 2
			diff -= step
			vp += step
		step >>= 1
		if diff >= step:
			nib |= 1
			vp += step
		pred = clampi(pred - vp if nib & 8 else pred + vp, -32768, 32767)
		idx = clampi(idx + INDEX_STEP[nib & 7], 0, 88)
		if low:
			half = nib
			low = false
		else:
			out[pos] = half | (nib << 4)
			pos += 1
			low = true
	if not low:
		out[pos] = half
	state["index"] = idx
	return out


## Decodes a frame made by encode_frame into `samples` mono samples in -1..1
## (an empty array for a frame too short to be one).
static func decode_frame(bytes: PackedByteArray, samples: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if samples <= 0 or bytes.size() < frame_bytes(samples):
		return out
	out.resize(samples)
	var pred := bytes.decode_s16(0)
	var idx := clampi(bytes[2], 0, 88)
	var pos := HEADER_BYTES
	var low := true
	for i in samples:
		var nib := 0
		if low:
			nib = bytes[pos] & 15
			low = false
		else:
			nib = bytes[pos] >> 4
			pos += 1
			low = true
		var step := STEPS[idx]
		var vp := step >> 3
		if nib & 4:
			vp += step
		if nib & 2:
			vp += step >> 1
		if nib & 1:
			vp += step >> 2
		pred = clampi(pred - vp if nib & 8 else pred + vp, -32768, 32767)
		idx = clampi(idx + INDEX_STEP[nib & 7], 0, 88)
		out[i] = pred / 32768.0
	return out


## Takes `src` (mono, at `src_rate`) to `dst_rate` by linear interpolation, carrying the
## phase and the last sample in `state` so a stream fed in pieces comes out seamless.
## Downsampling first runs two one-pole lowpasses (corner about a third of the new
## rate) so what's above the new rate's half doesn't fold back in as hiss.
static func resample(src: PackedFloat32Array, src_rate: float, dst_rate: float, state: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if src.is_empty() or src_rate <= 0.0 or dst_rate <= 0.0:
		return out
	var x := src
	if src_rate > dst_rate * 1.01:
		x = lowpass(src, dst_rate * 0.34, src_rate, state)
	var step := src_rate / dst_rate
	var t := float(state.get("phase", 0.0))
	var last := float(state.get("last", 0.0))
	var n := x.size()
	# Positions count in the stream [last, x[0], x[1], ...]: t = 0 is `last`, t = 1 is x[0].
	while t + 1.0 <= float(n):
		var i := int(t)
		var frac := t - float(i)
		var a := last if i == 0 else x[i - 1]
		var b := x[i]
		out.append(a + (b - a) * frac)
		t += step
	state["phase"] = t - float(n)
	state["last"] = x[n - 1]
	return out


## Two cascaded one-pole lowpasses at `corner` Hz; `state` keeps the filter's memory.
static func lowpass(src: PackedFloat32Array, corner: float, rate: float, state: Dictionary) -> PackedFloat32Array:
	var alpha := 1.0 - exp(-TAU * corner / rate)
	var y1 := float(state.get("lp1", 0.0))
	var y2 := float(state.get("lp2", 0.0))
	var out := PackedFloat32Array()
	out.resize(src.size())
	for i in src.size():
		y1 += alpha * (src[i] - y1)
		y2 += alpha * (y1 - y2)
		out[i] = y2
	state["lp1"] = y1
	state["lp2"] = y2
	return out


## The level of `pcm` in decibels below full scale (-100 for silence).
static func level_db(pcm: PackedFloat32Array) -> float:
	if pcm.is_empty():
		return -100.0
	var sum := 0.0
	for v in pcm:
		sum += v * v
	var rms := sqrt(sum / pcm.size())
	return maxf(-100.0, 20.0 * log(maxf(rms, 1e-6)) / log(10.0))


## Stereo frames from the capture bus (or any PackedVector2Array) folded to mono.
static func to_mono(frames: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames.size())
	for i in frames.size():
		out[i] = (frames[i].x + frames[i].y) * 0.5
	return out
