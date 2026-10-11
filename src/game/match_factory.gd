class_name MatchFactory
extends RefCounted
## Builds matches from the creature definitions in data/creatures/.

const CREATURE_DIR := "res://data/creatures/"
const FIGHTERS := ["cairn", "culvert", "craglash", "barkley", "gillbert", "cerebro", "hissy"]

const SPAWN_LEFT := Vector2(170, 164)
const SPAWN_RIGHT := Vector2(310, 164)

static var _cache := {}


static func load_def(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := CREATURE_DIR + id + ".json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Missing creature definition: " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Could not parse " + path)
		return {}
	_cache[id] = data
	return data


## Training: a player-controlled fighter on the left, a training dummy on the right.
static func training(fighter := "culvert") -> MatchSim:
	var sim := MatchSim.new()
	sim.add_creature(load_def(fighter), SPAWN_LEFT)
	var dummy := sim.add_creature(load_def("dummy"), SPAWN_RIGHT, true)
	dummy.facing = Vector2.LEFT
	return sim


## Two fighters facing each other. Either side can be a player or the CPU.
static func versus(left_id := "culvert", right_id := "culvert") -> MatchSim:
	var sim := MatchSim.new()
	sim.add_creature(load_def(left_id), SPAWN_LEFT)
	var right := sim.add_creature(load_def(right_id), SPAWN_RIGHT)
	right.facing = Vector2.LEFT
	return sim
