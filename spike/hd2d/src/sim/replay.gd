class_name Replay
extends RefCounted
## A match recorded as one input bitmask per creature per tick. Because the simulation
## is deterministic, replaying the inputs on a fresh match reproduces it exactly.

const FORMAT := 1

## What the match was (a Dictionary main writes; ReplayBuilder rebuilds it), or the
## old plain label.
var setup = "training"
var frames: Array[PackedInt32Array] = []


func record(inputs: PackedInt32Array) -> void:
	frames.append(inputs.duplicate())


func to_dict() -> Dictionary:
	var rows: Array = []
	for f in frames:
		rows.append(Array(f))
	return {"format": FORMAT, "setup": setup, "frames": rows}


func save(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	return OK


## Replays come from files and the network: anything bigger than this, or shaped any
## other way, is refused before a single row is read (an hour of frames; a 4 v 4's
## eight inputs a row).
const MAX_FRAMES := 60 * 60 * 60
const MAX_WIDTH := 8
## A replay file bigger than this isn't read at all (an hour of a 4 v 4 is about 20 MB).
const MAX_FILE_BYTES := 32 * 1024 * 1024


## A replay from its dictionary, or null if it isn't one: `frames` must be an Array of
## at most `max_frames` rows, each an Array (or PackedInt32Array) of 1 to MAX_WIDTH
## numbers (exactly `width` when it's given). Everything is checked before anything is
## converted, so a hostile dictionary costs no more than its own size.
static func from_dict(d: Dictionary, max_frames := MAX_FRAMES, width := 0) -> Replay:
	var rows = d.get("frames", [])
	if not (rows is Array) or (rows as Array).size() > max_frames:
		return null
	for row in rows:
		var n := 0
		if row is PackedInt32Array:
			n = (row as PackedInt32Array).size()
		elif row is Array:
			n = (row as Array).size()
			if n <= MAX_WIDTH:
				for v in row:
					if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
						return null
		else:
			return null
		if n < 1 or n > MAX_WIDTH or (width > 0 and n != width):
			return null
	var setup = d.get("setup", "training")
	var r := Replay.new()
	r.setup = setup if (setup is Dictionary or setup is String) else "training"
	for row in rows:
		if row is PackedInt32Array:
			r.frames.append((row as PackedInt32Array).duplicate())
			continue
		var f := PackedInt32Array()
		for v in row:
			var x := float(v)
			f.append(int(x) if is_finite(x) and absf(x) < 2147483648.0 else 0)
		r.frames.append(f)
	return r


static func load_file(path: String) -> Replay:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_FILE_BYTES:
		return null
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return null
	return from_dict(data)


## Plays every frame on the given match and returns its final state hash.
func play(sim: MatchSim) -> int:
	for f in frames:
		sim.step(f)
	return sim.state_hash()
