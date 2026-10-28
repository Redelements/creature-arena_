class_name Endings
extends RefCounted
## Arcade ending cards (Settings > Game > Progression on): one per fighter, shown after the
## Arcade boss falls (main.gd `_open_ending`, before the results) and again from Profile >
## Endings. The words and the art's path are data, `data/endings/<fighter>.json`:
##   title         the card's title ("Still Standing")
##   lines         three to five short lines (under 60 characters each, for phones)
##   art           the picture (`assets/ui/endings/<fighter>.png`; placeholders by
##                 tools/gen_ending_cards.py until the real art lands)
##   unlock_title  optional: a "title:<id>" reward the first showing grants (its words in
##                 data/progression.json's `titles`)
## Seen state lives in progress.json's "endings" list (`Progress.ending_seen` / `see_ending`).
## Nothing here touches a match.
##
## API: fighters(), of(fighter) -> Dictionary, art(fighter) -> Texture2D, show(fighter) -> bool,
## titles() -> [reward ids], fighter_of_reward(reward_id) -> fighter id or "".

const DIR := "res://data/endings"
## Every ending file needs these.
const KEYS := ["title", "lines", "art"]

static var _cache := {}


## The fighters with an ending (the whole roster, in the pick screen's order).
static func fighters() -> Array:
	return MatchFactory.FIGHTERS


## A fighter's ending ({} when its file is missing or broken).
static func of(fighter: String) -> Dictionary:
	if _cache.has(fighter):
		return _cache[fighter]
	var d := {}
	var path := "%s/%s.json" % [DIR, fighter]
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			d = parsed
	_cache[fighter] = d
	return d


static func art(fighter: String) -> Texture2D:
	var p := String(of(fighter).get("art", ""))
	return load(p) as Texture2D if p != "" and ResourceLoader.exists(p) else null


## The card is being shown after a clear: remember it, and the first time grant its title.
## True the first time (false while Progression is off).
static func show(fighter: String) -> bool:
	if not Progress.see_ending(fighter):
		return false
	var t := String(of(fighter).get("unlock_title", ""))
	if t.begins_with("title:"):
		Progress.grant_unlock(t)
	return true


## Every ending's title reward, in roster order.
static func titles() -> Array:
	var out: Array = []
	for f in fighters():
		var t := String(of(String(f)).get("unlock_title", ""))
		if t != "":
			out.append(t)
	return out


## The fighter whose ending grants this reward ("" when none does).
static func fighter_of_reward(reward_id: String) -> String:
	for f in fighters():
		if String(of(String(f)).get("unlock_title", "")) == reward_id:
			return String(f)
	return ""
