class_name Replay
extends RefCounted
## A match recorded as one input bitmask per creature per tick. Because the simulation
## is deterministic, replaying the inputs on a fresh match reproduces it exactly.

const FORMAT := 1

var setup := "training"
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


static func from_dict(d: Dictionary) -> Replay:
	var r := Replay.new()
	r.setup = String(d.get("setup", "training"))
	for row in d.get("frames", []):
		var f := PackedInt32Array()
		for v in row:
			f.append(int(v))
		r.frames.append(f)
	return r


static func load_file(path: String) -> Replay:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
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
