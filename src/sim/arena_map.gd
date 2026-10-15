class_name ArenaMap
extends RefCounted
## Arena maps: data/arenas/<id>.json. A map names its ground, lays fixed pieces on the
## terrain grid (see TerrainGrid.load_map) and says where each side starts. The
## stadium is the plain floor every match used before maps existed.
##
##   {"id": "quarry", "name": "Quarry Bowl", "ground": "dirt",
##    "pieces": [{"kind": "wall", "rect": [20, 4, 2, 28]}, ...],
##    "spawns": {"left": [x, y], "right": [x, y]}}    (floor pixels; optional)

const DIR := "res://data/arenas/"
const DEFAULT := "stadium"
## Every map, in menu order.
const IDS := ["stadium", "quarry", "floodgate", "greenhouse"]

static var _cache := {}


static func get_map(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var f := FileAccess.open(DIR + id + ".json", FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f != null else null
	if typeof(data) != TYPE_DICTIONARY:
		if id != DEFAULT:
			push_error("Missing arena map: " + id)
		data = {"id": DEFAULT, "name": "Stadium"}
	_cache[id] = data
	return data


static func name_of(id: String) -> String:
	return String(get_map(id).get("name", id.capitalize()))


## Where a side starts, from the map or the stadium's default.
static func spawn(map: Dictionary, side: int) -> Vector2:
	var sp: Dictionary = map.get("spawns", {})
	var key := "left" if side == 0 else "right"
	if sp.has(key):
		var v: Array = sp[key]
		return Vector2(float(v[0]), float(v[1]))
	return MatchFactory.SPAWN_LEFT if side == 0 else MatchFactory.SPAWN_RIGHT
