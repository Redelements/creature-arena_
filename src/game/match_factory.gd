class_name MatchFactory
extends RefCounted
## Builds matches from the creature definitions in data/creatures/.

const CREATURE_DIR := "res://data/creatures/"

const SPAWN_LEFT := Vector2(170, 164)
const SPAWN_RIGHT := Vector2(310, 164)


static func load_def(id: String) -> Dictionary:
	var path := CREATURE_DIR + id + ".json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Missing creature definition: " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Could not parse " + path)
		return {}
	return data


## Training: player-controlled Culvert on the left, a training dummy on the right.
static func training() -> MatchSim:
	var sim := MatchSim.new()
	sim.add_creature(load_def("culvert"), SPAWN_LEFT)
	var dummy := sim.add_creature(load_def("dummy"), SPAWN_RIGHT, true)
	dummy.facing = Vector2.LEFT
	return sim


## Two player-controlled creatures, used by tests (and later local versus).
static func versus(left_id := "culvert", right_id := "culvert") -> MatchSim:
	var sim := MatchSim.new()
	sim.add_creature(load_def(left_id), SPAWN_LEFT)
	var right := sim.add_creature(load_def(right_id), SPAWN_RIGHT)
	right.facing = Vector2.LEFT
	return sim
