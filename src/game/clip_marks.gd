extends RefCounted
class_name ClipMarks
## Clip markers for the Replay theater's Export clip (`main.clips`): the moments of a match
## worth a clip, saved by F6 next to its replay in a sidecar, `<replay>.clips.json`:
## {"clips": [{"at": tick, "why": "F6" | "KO combo"}]}. View metadata only: read from
## `sim.events` (never written to the sim), and the replay file itself is unchanged, so a
## replay with no sidecar still plays and an old game ignores the sidecar.
##
## Markers: F6 (`main._save_replay`) adds one at the tick it was pressed; a KO by a local
## player's fighter (`main._is_local_fighter`) that ends a combo of `COMBO_KO` or more hits
## adds one by itself (`note`). They are kept per match (`reset` from `main._new_sim`, as the
## replay is), so each F6 save carries every marker of the fight so far.

const SUFFIX := ".clips.json"
## A KO marker needs a combo this long...
const COMBO_KO := 3
## ...whose last hit landed at most this many ticks before the KO (a knocked-up fighter
## finishes its fall first, then is KO'd on landing).
const KO_WINDOW := 150
const MOST := 200  ## markers kept per match (and read from a sidecar)

var marks: Array = []  ## [{"at": tick, "why": text}], in the order they came
var _last_hit := {}  ## target slot -> [attacker slot, combo hits, tick]


func reset() -> void:
	marks = []
	_last_hit = {}


## One sim event, at `tick` (the replay's frame count); `is_local` says whether a slot is
## a player on this machine.
func note(e: Dictionary, tick: int, is_local: Callable) -> void:
	match String(e.get("type", "")):
		"hit":
			_last_hit[int(e.get("target", -1))] = [int(e.get("attacker", -1)), int(e.get("combo", 0)), tick]
		"ko":
			var who := int(e.get("who", -1))
			var last: Array = _last_hit.get(who, [])
			_last_hit.erase(who)
			if last.is_empty() or int(last[0]) == who or int(last[1]) < COMBO_KO or tick - int(last[2]) > KO_WINDOW:
				return
			if is_local.call(int(last[0])):
				add(tick, "KO combo")


func add(tick: int, why: String) -> void:
	if marks.size() < MOST:
		marks.append({"at": tick, "why": why})


## The sidecar for a replay file (replay_X.json -> replay_X.clips.json).
static func sidecar_of(replay_path: String) -> String:
	return replay_path.trim_suffix(".json") + SUFFIX


## Whether a file in the replays folder is a sidecar, not a replay.
static func is_sidecar(file_name: String) -> bool:
	return file_name.ends_with(SUFFIX)


static func save_for(replay_path: String, list: Array) -> Error:
	var f := FileAccess.open(sidecar_of(replay_path), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"clips": list}))
	return OK


## A replay's markers, sorted by tick ([] with no sidecar or a damaged one):
## [{"at": int, "why": String}].
static func load_for(replay_path: String) -> Array:
	var path := sidecar_of(replay_path)
	var f := FileAccess.open(path, FileAccess.READ) if FileAccess.file_exists(path) else null
	if f == null or f.get_length() > 256 * 1024:
		return []
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or not (d.get("clips") is Array):
		return []
	var out: Array = []
	for c in (d["clips"] as Array).slice(0, MOST):
		if c is Dictionary and (typeof(c.get("at")) == TYPE_INT or typeof(c.get("at")) == TYPE_FLOAT):
			var at := float(c["at"])
			if is_finite(at) and at >= 0.0 and at < float(Replay.MAX_FRAMES):
				out.append({"at": int(at), "why": str(c.get("why", "")).left(40)})
	out.sort_custom(func(a, b): return int(a["at"]) < int(b["at"]))
	return out
