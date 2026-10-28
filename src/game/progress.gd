class_name Progress
extends RefCounted
## What the player has earned, kept in user://progress.json (outside the simulation):
## the best CPU level each fighter has cleared the Arcade ladder on, the palette each
## fighter wears, Gauntlet and Daily bests, and (Settings > Game > Progression) the
## account's XP, each fighter's mastery XP, the rewards unlocked and what is equipped.
## Palettes unlock with Arcade clears (one per level cleared, up to four) and, with
## Progression on, with mastery: a palette counts as unlocked if either rule grants it.
## The numbers and tables are data: data/progression.json.
##
## Progression API (every award, line and toast checks `enabled()` first):
##   enabled() -> bool                 Settings > Game > Progression (set_enabled, from main_settings)
##   account_xp() / account_level()    the account's XP and level (1 .. cap)
##   level_progress() -> [into, need]  XP into the current level and the XP it needs ([0, 0] at the cap)
##   mastery_xp(f) / mastery_level(f) / mastery_progress(f)   the same per fighter id
##   unlocked(reward_id) -> bool       reward ids: "palette:<fighter>:N", "title:<id>", "line:<id>"
##   unlocks_of(f) -> Array            the reward ids this fighter has (palettes by either rule)
##   mastery_rewards(f) / account_rewards() -> [{"level", "id"}]   the tables, "{fighter}" filled in
##   reward_text(id), title_text(id), line_text(id)   the words for a reward
##   equipped(f) -> {palette, title, line}; set_equipped(f, key, value)   ("" = none)
##   award(report) -> Dictionary       once per finished match (see `award`)
##   merge_results(a, b), result_lines(result)   an Arcade run's stages as one; the results rows
##   account_title() / set_account_title(id)   the title worn by the account (any fighter without its own)
##   shown_title(f) / shown_line(f)    the words the versus and results screens show ("" when off or none)
##   is_new(id), new_of(f), new_anywhere(), mark_seen(ids)   the Profile's "New!" marks (save key "seen")
##   grant_xp(amount, reason) -> Dictionary   account XP from outside a match's award (a challenge's
##                                     reward; account-level rewards it reaches unlock), shaped like `award`'s
##   grant_unlock(reward_id) -> bool   a reward given outright (a challenge's title); false when off or had
##   section(key) -> Dictionary        a save key another tracker keeps (Challenges: "challenges")
##   weekly_best(week) / record_weekly(week, score)   the Weekly Challenge's local best per ISO week (YYYYWW)
##   ending_seen(f) / see_ending(f) -> bool   the Arcade ending cards shown (save key "endings", fighter ids;
##                                     src/game/endings.gd); see_ending is false when off or already seen
##   streak_days() -> int              the play streak: calendar days in a row (local time) with a paid
##                                     fight, 0 once a day is missed; `award` keeps it (save key "streak")
##   streak_bonus() -> float           the XP multiplier a fight gets now (streak_mult from streak_min_days)

const PATH := "user://progress.json"
const DATA_PATH := "res://data/progression.json"
const PALETTES := 4
## The most XP (or any count) a save holds: a hand-edited 1e30 reads as this, never as an overflow.
const XP_MAX := 1000000000
## Every key of the save and its default (an old file without some of them still loads).
const SAVE_KEYS := {"arcade": {}, "palette": {}, "gauntlet": {}, "daily": {}, "xp": 0, "mastery": {},
	"unlocked": [], "equipped": {}, "account_title": "", "seen": [], "challenges": {},
	"weekly": {}, "streak": {}, "endings": []}

static var _data := {}
static var _loaded := false
static var path := PATH
static var _enabled := false
static var _table := {}
## The streak's last day may be this many days after today and still count as today (a
## clock set back, a trip west across midnight); a later one (a clock far off) starts again.
const CLOCK_SLACK_DAYS := 2
## The local calendar day (YYYYMMDD) the streak counts with; 0 = the system clock. Tests set it.
static var day_override := 0


static func read() -> void:
	_loaded = true
	_data = SAVE_KEYS.duplicate(true)
	var d = _read_file(path)
	if d == null and FileAccess.file_exists(path):
		# There but unreadable (empty, cut off, not a save): never write over it. Move it
		# aside, say so, and fall back on the last good save before it.
		var aside := "%s.corrupt-%d" % [path, int(Time.get_unix_time_from_system())]
		DirAccess.rename_absolute(path, aside)
		printerr("progress: %s was unreadable, moved to %s" % [path, aside])
		d = _read_file(path + ".bak")
		if d != null:
			printerr("progress: restored from %s.bak (the save before)" % path)
	if d is Dictionary:
		_data = clean(d)


## The save in `file`, or null when it's missing or not a save.
static func _read_file(file: String) -> Variant:
	if not FileAccess.file_exists(file):
		return null
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return null
	var json := JSON.new()  # (not parse_string: a bad file is handled here, not an engine error)
	if json.parse(f.get_as_text()) != OK:
		return null
	return json.data if json.data is Dictionary else null


## The save as the game reads it: every known key with its type, whatever the file held
## (a hand-edited or damaged file never reaches the getters as a wrong type). Numbers are
## whole and in range (JSON reads them as floats: they are stored back as ints), lists
## hold strings, an odd entry is dropped and a missing key gets its default.
static func clean(d: Dictionary) -> Dictionary:
	var out := SAVE_KEYS.duplicate(true)
	out["xp"] = _num(d.get("xp"), 0, XP_MAX, 0)
	out["arcade"] = _num_map(d.get("arcade"), -1, CpuController.LEVELS.size() - 1)
	out["palette"] = _num_map(d.get("palette"), 0, PALETTES - 1)
	for k in ["gauntlet", "daily", "weekly", "mastery"]:
		out[k] = _num_map(d.get(k), 0, XP_MAX)
	for k in ["unlocked", "seen", "endings"]:
		out[k] = _str_list(d.get(k))
	var eq = d.get("equipped")
	if eq is Dictionary:
		for fid in eq:
			var e = eq[fid]
			if e is Dictionary:
				out["equipped"][String(fid)] = {
					"title": String(e["title"]) if e.get("title") is String else "",
					"line": String(e["line"]) if e.get("line") is String else ""}
	out["account_title"] = String(d["account_title"]) if d.get("account_title") is String else ""
	var ch = d.get("challenges")
	if ch is Dictionary:
		out["challenges"] = {"counts": _num_map(ch.get("counts"), 0, XP_MAX), "done": _str_list(ch.get("done"))}
	var st = d.get("streak")
	if st is Dictionary:
		out["streak"] = {"days": _num(st.get("days"), 0, 100000, 0), "last_day": _num(st.get("last_day"), 0, 99991231, 0)}
	return out


## A whole number from a save value in [lo, hi], or `fallback` when it isn't a number.
static func _num(v: Variant, lo: int, hi: int, fallback: int) -> int:
	if v is int:
		return clampi(v, lo, hi)
	if v is float and is_finite(v):
		return int(clampf(v, lo, hi))
	return fallback


## {key: whole number}: the entries that are numbers, kept in [lo, hi].
static func _num_map(v: Variant, lo: int, hi: int) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			if v[k] is int or v[k] is float:
				out[String(k)] = _num(v[k], lo, hi, lo)
	return out


## The strings of a list, each once.
static func _str_list(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for s in v:
			if s is String and not out.has(s):
				out.append(s)
	return out


## Written whole to <path>.tmp, the old file copied to <path>.bak, then the temporary file
## renamed over it (as the server's ratings.json): a crash mid-write never loses the profile.
static func save() -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		printerr("progress not saved: can't write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(_data, "\t"))
	var err := f.get_error()
	f.close()
	if err != OK:
		printerr("progress not saved: writing %s failed (%s)" % [tmp, error_string(err)])
		DirAccess.remove_absolute(tmp)
		return
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		printerr("progress not saved: renaming %s failed (%s)" % [tmp, error_string(err)])


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


## Palette `index` (0 always) is this fighter's under either rule: Arcade clears (one per
## level cleared) or, with Progression on, its mastery reward "palette:<fighter>:<index>".
static func palette_unlocked(fighter: String, index: int) -> bool:
	if index <= 0:
		return true
	if index >= PALETTES:
		return false
	if index <= 1 + arcade_best(fighter):
		return true
	return enabled() and _unlocked_list().has("palette:%s:%d" % [fighter, index])


## How many palettes this fighter can wear: the unbroken run 0, 1, .. that is unlocked.
static func palettes_unlocked(fighter: String) -> int:
	var n := 1
	while n < PALETTES and palette_unlocked(fighter, n):
		n += 1
	return n


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


## The Gauntlet: most waves cleared per fighter.
static func gauntlet_best(fighter: String) -> int:
	_ensure()
	return int((_data["gauntlet"] as Dictionary).get(fighter, 0))


static func record_gauntlet(fighter: String, waves: int) -> bool:
	_ensure()
	if waves <= gauntlet_best(fighter):
		return false
	_data["gauntlet"][fighter] = waves
	save()
	return true


## The Daily Challenge: the best score per day (YYYYMMDD).
static func daily_best(date: int) -> int:
	_ensure()
	return int((_data["daily"] as Dictionary).get(str(date), 0))


static func record_daily(date: int, score: int) -> bool:
	_ensure()
	if score <= daily_best(date):
		return false
	_data["daily"][str(date)] = score
	save()
	return true


## The Weekly Challenge: the best score per ISO week (YYYYWW, Weekly.week_of).
static func weekly_best(week: int) -> int:
	_ensure()
	return int((_data["weekly"] as Dictionary).get(str(week), 0))


static func record_weekly(week: int, score: int) -> bool:
	_ensure()
	if score <= weekly_best(week):
		return false
	_data["weekly"][str(week)] = score
	save()
	return true


static func reset_for_tests(p: String) -> void:
	path = p
	_loaded = false
	_data = {}


# --- Progression ----------------------------------------------------------------------


## Settings > Game > Progression. Off: `award` gives nothing and changes nothing, and
## palettes unlock by Arcade clears only (as before the setting existed).
static func enabled() -> bool:
	return _enabled


static func set_enabled(on: bool) -> void:
	_enabled = on


## data/progression.json (read once).
static func table() -> Dictionary:
	if _table.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_table = d if d is Dictionary else {"xp": {}, "account_curve": {}, "mastery_curve": {}}
	return _table


## The XP level `lvl` takes to reach the next one on this curve ({base, step, cap}).
static func level_cost(curve: Dictionary, lvl: int) -> int:
	return int(curve.get("base", 100)) + int(curve.get("step", 0)) * (lvl - 1)


## The total XP that reaches level `lvl` (level 1 is 0 XP; past the cap, the cap's).
static func xp_for_level(curve: Dictionary, lvl: int) -> int:
	var total := 0
	for k in range(1, mini(lvl, int(curve.get("cap", 1)))):
		total += level_cost(curve, k)
	return total


static func level_of(curve: Dictionary, xp: int) -> int:
	var lvl := 1
	var cap := int(curve.get("cap", 1))
	var spent := 0
	while lvl < cap and xp >= spent + level_cost(curve, lvl):
		spent += level_cost(curve, lvl)
		lvl += 1
	return lvl


## [XP into this level, XP this level needs]; [0, 0] at the cap.
static func progress_of(curve: Dictionary, xp: int) -> Array:
	var lvl := level_of(curve, xp)
	if lvl >= int(curve.get("cap", 1)):
		return [0, 0]
	return [xp - xp_for_level(curve, lvl), level_cost(curve, lvl)]


static func account_xp() -> int:
	_ensure()
	return clampi(int(_data["xp"]), 0, XP_MAX)


static func account_level() -> int:
	return level_of(table()["account_curve"], account_xp())


static func level_progress() -> Array:
	return progress_of(table()["account_curve"], account_xp())


static func mastery_xp(fighter: String) -> int:
	_ensure()
	return clampi(int((_data["mastery"] as Dictionary).get(fighter, 0)), 0, XP_MAX)


static func mastery_level(fighter: String) -> int:
	return level_of(table()["mastery_curve"], mastery_xp(fighter))


static func mastery_progress(fighter: String) -> Array:
	return progress_of(table()["mastery_curve"], mastery_xp(fighter))


static func _unlocked_list() -> Array:
	_ensure()
	return _data["unlocked"]


## True when the reward is the player's: recorded by a level-up, or (a palette) by either rule.
static func unlocked(reward_id: String) -> bool:
	if reward_id.begins_with("palette:"):
		var p := reward_id.split(":")
		return p.size() == 3 and palette_unlocked(p[1], int(p[2]))
	return _unlocked_list().has(reward_id)


## Every reward this fighter has: its palettes (either rule), then its mastery titles and lines.
static func unlocks_of(fighter: String) -> Array:
	var out: Array = []
	for i in range(1, PALETTES):
		if palette_unlocked(fighter, i):
			out.append("palette:%s:%d" % [fighter, i])
	for r in mastery_rewards(fighter):
		var id := String(r["id"])
		if not id.begins_with("palette:") and _unlocked_list().has(id) and not out.has(id):
			out.append(id)
	return out


## The mastery table for this fighter: [{"level", "id"}] by level, "{fighter}" filled in.
static func mastery_rewards(fighter: String) -> Array:
	return _rewards(table().get("mastery", {}), fighter)


static func account_rewards() -> Array:
	return _rewards(table().get("account", {}), "")


static func _rewards(t: Dictionary, fighter: String) -> Array:
	var out: Array = []
	var levels: Array = []
	for k in t:
		levels.append(int(k))
	levels.sort()
	for lvl in levels:
		for id in t[str(lvl)]:
			out.append({"level": lvl, "id": String(id).replace("{fighter}", fighter)})
	return out


## A title's or a victory line's words: its own entry, else the "{fighter}_..." template
## with the fighter's name for "{name}".
static func _text(map_key: String, id: String) -> String:
	var m: Dictionary = table().get(map_key, {})
	if m.has(id):
		return String(m[id])
	for f in MatchFactory.FIGHTERS:
		var fs := String(f)
		var rest := id.substr(fs.length())
		if id.begins_with(fs + "_") and m.has("{fighter}" + rest):
			return String(m["{fighter}" + rest]).replace("{name}", _name(fs))
	return id


static func _name(fighter: String) -> String:
	return String(MatchFactory.load_def(fighter).get("name", fighter))


static func title_text(id: String) -> String:
	return _text("titles", id.trim_prefix("title:"))


static func line_text(id: String) -> String:
	return _text("lines", id.trim_prefix("line:"))


## What the results screen calls a reward.
static func reward_text(reward_id: String) -> String:
	var p := reward_id.split(":")
	match p[0]:
		"palette":
			return "%s palette %d" % [_name(p[1]), int(p[2]) + 1] if p.size() == 3 else reward_id
		"title":
			return "title \"%s\"" % title_text(reward_id)
		"line":
			return "victory line \"%s\"" % line_text(reward_id)
	return reward_id


## What this fighter wears: {"palette": int, "title": reward id or "", "line": reward id or ""}.
static func equipped(fighter: String) -> Dictionary:
	_ensure()
	var e: Dictionary = (_data["equipped"] as Dictionary).get(fighter, {})
	return {"palette": palette(fighter), "title": String(e.get("title", "")), "line": String(e.get("line", ""))}


## Wear a title or a line ("" takes it off; a locked one is refused, false), or a palette (an index).
static func set_equipped(fighter: String, key: String, value) -> bool:
	_ensure()
	if key == "palette":
		set_palette(fighter, int(value))
		return true
	if not key in ["title", "line"] or (String(value) != "" and not unlocked(String(value))):
		return false
	if not (_data["equipped"] as Dictionary).has(fighter):
		_data["equipped"][fighter] = {}
	_data["equipped"][fighter][key] = String(value)
	save()
	return true


## The XP one player earns from a report (see `award`); nothing is added.
static func xp_for(report: Dictionary, player: Dictionary) -> int:
	var kind := String(report.get("kind", "none"))
	if not kind in ["cpu", "local", "online"]:
		return 0
	var x: Dictionary = table().get("xp", {})
	var kos := mini(int(player.get("kos", 0)), int(x.get("ko_cap", 99)))
	var total := float(x.get("fight", 0)) + kos * float(x.get("ko", 0))
	if bool(player.get("won", false)):
		total += float(x.get("win", 0))
	if bool(report.get("clear_arcade", false)):
		total += float(x.get("clear_arcade", 0))
	total += int(report.get("waves", 0)) * float(x.get("gauntlet_wave", 0))
	total += int(report.get("daily_score", 0)) / 100.0 * float(x.get("daily_score_mult", 0))
	if bool(report.get("weekly_clear", false)):
		total += float(x.get("weekly_clear", 0))
	if kind == "cpu":
		var mults: Array = x.get("level_mult", [1.0])
		total *= float(mults[clampi(int(report.get("cpu_level", 1)), 0, mults.size() - 1)])
	return roundi(total)


## Pays a finished match. `report`:
##   "kind": "cpu" (one human against CPUs: times the CPU level's `level_mult`), "local"
##           (two or more humans on this machine: each paid fully), "online" (the local
##           human, fully) or "none" (training, showcases, replays, CPU vs CPU, coaches)
##   "cpu_level": 0 Easy .. 3 Rage (kind "cpu")
##   "players": [{"slot": int, "fighters": [ids], "won": bool, "kos": int}], the humans
##   "clear_arcade": bool, "waves": int (Gauntlet waves this fight cleared), "daily_score": int
##   (the Daily's or the Weekly's score), "weekly_clear": bool (the week's first scoring win)
## A paid fight keeps the play streak (`streak_days`); from `streak_min_days` days in a row
## every player's XP is times `streak_mult`.
## The account gains the best player's XP (one account per machine, so four local players
## don't pay it four times); a player's fighters share that player's XP for mastery (a
## Duel's three split it), and a fighter two players used takes the larger share.
## Returns {} when Progression is off or nothing was earned (and changes nothing), else
##   {"xp": gained, "level_from", "level_to", "mastery": {fighter: {"xp", "from", "to"}},
##    "unlocked": [reward ids newly unlocked], "streak": days, "streak_up": true when this
##    fight added a day to a streak of two or more}
static func award(report: Dictionary) -> Dictionary:
	if not enabled():
		return {}
	_ensure()
	var best := 0
	var per_fighter := {}
	var paid := false
	for p in report.get("players", []):
		paid = paid or xp_for(report, p) > 0
	var streak_up := _note_streak() if paid else false
	var bonus := streak_bonus()
	for p in report.get("players", []):
		var gain := roundi(xp_for(report, p) * bonus)
		best = maxi(best, gain)
		var fs: Array = p.get("fighters", [])
		if fs.is_empty() or gain <= 0:
			continue
		var share := ceili(float(gain) / fs.size())
		for f in fs:
			per_fighter[String(f)] = maxi(int(per_fighter.get(String(f), 0)), share)
	if best <= 0:
		return {}
	var before := account_level()
	_data["xp"] = account_xp() + best
	var out := {"xp": best, "level_from": before, "level_to": account_level(), "mastery": {}, "unlocked": [],
		"streak": streak_days(), "streak_up": streak_up, "streak_bonus": bonus}
	var had: Array = []  # a palette an Arcade clear already gave is no news
	for f in per_fighter:
		for i in range(1, PALETTES):
			if i <= 1 + arcade_best(f):
				had.append("palette:%s:%d" % [f, i])
		var m0 := mastery_level(f)
		_data["mastery"][f] = mastery_xp(f) + int(per_fighter[f])
		out["mastery"][f] = {"xp": int(per_fighter[f]), "from": m0, "to": mastery_level(f)}
	# Everything at or under the levels now held (so a table that grows later catches up).
	var due: Array = []
	for r in account_rewards():
		if int(r["level"]) <= account_level():
			due.append(String(r["id"]))
	for f in per_fighter:
		for r in mastery_rewards(f):
			if int(r["level"]) <= mastery_level(f):
				due.append(String(r["id"]))
	for id in due:
		if not _unlocked_list().has(id):
			_unlocked_list().append(id)
			if not had.has(id):
				out["unlocked"].append(id)
			elif not (_data["seen"] as Array).has(id):
				(_data["seen"] as Array).append(id)  # had already: no "New!" either
	save()
	return out


## Two award results as one (the stages of an Arcade or Gauntlet run add up).
static func merge_results(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty():
		return b.duplicate(true)
	if b.is_empty():
		return a.duplicate(true)
	var out := a.duplicate(true)
	out["xp"] = int(a["xp"]) + int(b["xp"])
	out["level_to"] = b["level_to"]
	for f in b["mastery"]:
		var m: Dictionary = b["mastery"][f]
		if out["mastery"].has(f):
			out["mastery"][f]["xp"] = int(out["mastery"][f]["xp"]) + int(m["xp"])
			out["mastery"][f]["to"] = m["to"]
		else:
			out["mastery"][f] = m.duplicate()
	for id in b["unlocked"]:
		if not out["unlocked"].has(id):
			out["unlocked"].append(id)
	out["streak"] = maxi(int(a.get("streak", 0)), int(b.get("streak", 0)))
	out["streak_up"] = bool(a.get("streak_up", false)) or bool(b.get("streak_up", false))
	out["streak_bonus"] = maxf(float(a.get("streak_bonus", 1.0)), float(b.get("streak_bonus", 1.0)))
	return out


## The results screen's rows for an award result: "+N XP" (and a level-up), the
## mastery-ups, then what unlocked (two named at most, then "and N more").
static func result_lines(r: Dictionary) -> Array:
	if r.is_empty():
		return []
	var first := "+%d XP" % int(r["xp"])
	if int(r["level_to"]) > int(r["level_from"]):
		first += "   ·   Level up! Level %d" % int(r["level_to"])
	var ups: Array = []
	for f in r["mastery"]:
		var m: Dictionary = r["mastery"][f]
		if int(m["to"]) > int(m["from"]):
			ups.append("Mastery up! %s %d" % [_name(String(f)), int(m["to"])])
	var lines: Array = [first]
	if not ups.is_empty():
		lines.append("   ·   ".join(PackedStringArray(ups.slice(0, 2))) + ("   ·   %d more" % (ups.size() - 2) if ups.size() > 2 else ""))
	var got: Array = r["unlocked"]
	if not got.is_empty():
		var names: Array = []
		for id in got.slice(0, 2):
			names.append(reward_text(String(id)))
		lines.append("Unlocked: " + ", ".join(PackedStringArray(names)) + (" and %d more" % (got.size() - 2) if got.size() > 2 else ""))
	if bool(r.get("streak_up", false)):
		lines.append(streak_text(int(r.get("streak", 0)), float(r.get("streak_bonus", 1.0))))
	return lines


# --- The play streak -------------------------------------------------------------------------


## Today, the local calendar day (YYYYMMDD), or `day_override`.
static func today_local() -> int:
	if day_override > 0:
		return day_override
	var d := Time.get_date_dict_from_system(false)
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])


## The play streak: calendar days in a row with at least one paid fight, counting today
## or yesterday as its last day; 0 once a whole day was missed.
static func streak_days() -> int:
	_ensure()
	var st: Dictionary = _data["streak"]
	var last := int(st.get("last_day", 0))
	if last <= 0:
		return 0
	var gap := Daily.day_number(today_local()) - Daily.day_number(last)
	return maxi(0, int(st.get("days", 0))) if gap >= -CLOCK_SLACK_DAYS and gap <= 1 else 0


## The XP multiplier a paid fight gets now: `streak_mult` once the streak reaches
## `streak_min_days` (data/progression.json), else 1.
static func streak_bonus() -> float:
	var x: Dictionary = table().get("xp", {})
	if streak_days() >= int(x.get("streak_min_days", 3)):
		return float(x.get("streak_mult", 1.0))
	return 1.0


## "Streak: 5 days" (and the bonus while it pays one).
static func streak_text(days: int, bonus := 1.0) -> String:
	var t := "Streak: %d day%s" % [days, "" if days == 1 else "s"]
	if bonus > 1.0:
		t += "   ·   +%d%% XP" % roundi((bonus - 1.0) * 100.0)
	return t


## A paid fight today: the streak goes on (yesterday was its last day), starts again at
## one (a gap), or stays (already counted today). True when it grew to two days or more.
static func _note_streak() -> bool:
	_ensure()
	var st: Dictionary = _data["streak"]
	var today := today_local()
	var last := int(st.get("last_day", 0))
	var gap := Daily.day_number(today) - Daily.day_number(last) if last > 0 else 99
	if gap <= 0 and gap >= -CLOCK_SLACK_DAYS:
		return false  # today, or a clock a day or two behind the last fight: the same day (never moves back)
	var days := 1
	if gap == 1:
		days = maxi(0, int(st.get("days", 0))) + 1
	st["days"] = days
	st["last_day"] = today
	return days >= 2


# --- The Profile (src/ui/profile_screen.gd) -----------------------------------------------


## The account's title: a "title:<id>" reward id, or "" (none). Worn by every fighter
## that has no title of its own equipped.
static func account_title() -> String:
	_ensure()
	return String(_data["account_title"])


## Wear an account title ("" takes it off; a locked or non-title id is refused, false).
static func set_account_title(id: String) -> bool:
	_ensure()
	if id != "" and (not id.begins_with("title:") or not unlocked(id)):
		return false
	_data["account_title"] = id
	save()
	return true


## The title the versus and results screens show for the player on this fighter: the
## fighter's own, else the account's; "" when Progression is off or none is worn.
static func shown_title(fighter: String) -> String:
	if not enabled():
		return ""
	var id := String(equipped(fighter)["title"])
	if id == "" or not unlocked(id):
		id = account_title()
	return title_text(id) if id != "" and unlocked(id) else ""


## The victory line the results screen shows when the player wins on this fighter ("" none / off).
static func shown_line(fighter: String) -> String:
	if not enabled():
		return ""
	var id := String(equipped(fighter)["line"])
	return line_text(id) if id != "" and unlocked(id) else ""


## True for a reward a level-up gave that the Profile has not shown yet (save key "seen").
static func is_new(reward_id: String) -> bool:
	_ensure()
	return _unlocked_list().has(reward_id) and not (_data["seen"] as Array).has(reward_id)


## This fighter's new rewards; "" for the account's (its level titles, and the titles
## challenges and Arcade endings give: the Account page's title picker offers them all).
static func new_of(fighter: String) -> Array:
	var ids: Array = []
	for r in (account_rewards() if fighter == "" else mastery_rewards(fighter)):
		ids.append(String(r["id"]))
	if fighter == "":
		ids.append_array(Challenges.titles())
		ids.append_array(Endings.titles())
	var out: Array = []
	for id in ids:
		if is_new(String(id)) and not out.has(id):
			out.append(String(id))
	return out


## Anything new anywhere (the title menu's "Profile  New!"; nothing while Progression is off).
static func new_anywhere() -> bool:
	if not enabled():
		return false
	if not new_of("").is_empty():
		return true
	for f in MatchFactory.FIGHTERS:
		if not new_of(String(f)).is_empty():
			return true
	return false


## The Profile showed these: they stop being new.
static func mark_seen(ids: Array) -> void:
	_ensure()
	var seen: Array = _data["seen"]
	var grew := false
	for id in ids:
		if not seen.has(String(id)):
			seen.append(String(id))
			grew = true
	if grew:
		save()


# --- Challenges (src/game/challenges.gd) ----------------------------------------------------


## A save key another tracker owns (a Dictionary; Challenges keeps "challenges" here),
## written by `save()`.
static func section(key: String) -> Dictionary:
	_ensure()
	if not (_data.get(key) is Dictionary):
		_data[key] = {}
	return _data[key]


## Account XP from outside a match's award (a challenge's reward): the account-level
## rewards it reaches unlock. {} when Progression is off or `amount` <= 0, else shaped
## like `award`'s result (no mastery), so `merge_results` adds it to the match's rows.
## `reason` (the challenge id) rides along in the result as "reason".
static func grant_xp(amount: int, reason := "") -> Dictionary:
	if not enabled() or amount <= 0:
		return {}
	_ensure()
	var before := account_level()
	_data["xp"] = account_xp() + amount
	var out := {"xp": amount, "level_from": before, "level_to": account_level(), "mastery": {}, "unlocked": [],
		"reason": reason}
	for r in account_rewards():
		var id := String(r["id"])
		if int(r["level"]) <= account_level() and not _unlocked_list().has(id):
			_unlocked_list().append(id)
			out["unlocked"].append(id)
	save()
	return out


## A reward given outright (a challenge's title): true when it is new. Off: nothing.
static func grant_unlock(reward_id: String) -> bool:
	if not enabled() or reward_id == "" or _unlocked_list().has(reward_id):
		return false
	_unlocked_list().append(reward_id)
	save()
	return true


# --- Arcade endings (src/game/endings.gd) ---------------------------------------------------


## This fighter's Arcade ending card has been shown (the Profile's Endings gallery opens it again).
static func ending_seen(fighter: String) -> bool:
	_ensure()
	return (_data["endings"] as Array).has(fighter)


## The ending card was shown: remember it. False while Progression is off or when it was already seen.
static func see_ending(fighter: String) -> bool:
	if not enabled() or fighter == "" or ending_seen(fighter):
		return false
	(_data["endings"] as Array).append(fighter)
	save()
	return true
