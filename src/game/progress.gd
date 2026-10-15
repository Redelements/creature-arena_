class_name Progress
extends RefCounted
## What the player has earned, kept in user://progress.json (outside the simulation):
## the best CPU level each fighter has cleared the Arcade ladder on, and the palette
## each fighter wears. Palettes unlock with clears: one per level cleared, up to four.

const PATH := "user://progress.json"
const PALETTES := 4

static var _data := {}
static var _loaded := false
static var path := PATH


static func read() -> void:
	_loaded = true
	_data = {"arcade": {}, "palette": {}}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_data["arcade"] = d.get("arcade", {})
		_data["palette"] = d.get("palette", {})


static func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_data, "\t"))


static func _ensure() -> void:
	if not _loaded:
		read()


## The highest CPU level (0 Easy .. 3 Rage) this fighter has cleared the ladder on, or -1.
static func arcade_best(fighter: String) -> int:
	_ensure()
	return int((_data["arcade"] as Dictionary).get(fighter, -1))


## Records a clear; true when it is a new best.
static func record_clear(fighter: String, level: int) -> bool:
	_ensure()
	if level <= arcade_best(fighter):
		return false
	_data["arcade"][fighter] = level
	save()
	return true


## How many palettes this fighter can wear: the first always, one more per level cleared.
static func palettes_unlocked(fighter: String) -> int:
	return clampi(2 + arcade_best(fighter), 1, PALETTES)


static func palette(fighter: String) -> int:
	_ensure()
	return clampi(int((_data["palette"] as Dictionary).get(fighter, 0)), 0, palettes_unlocked(fighter) - 1)


static func set_palette(fighter: String, index: int) -> void:
	_ensure()
	_data["palette"][fighter] = clampi(index, 0, palettes_unlocked(fighter) - 1)
	save()


## The next unlocked palette after the current one (wraps).
static func next_palette(fighter: String) -> int:
	var n := palettes_unlocked(fighter)
	var i := (palette(fighter) + 1) % n
	set_palette(fighter, i)
	return i


static func reset_for_tests(p: String) -> void:
	path = p
	_loaded = false
	_data = {}
