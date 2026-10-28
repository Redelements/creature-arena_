class_name Challenges
extends RefCounted
## Challenges (Settings > Game > Progression on): about fifty goals in data/challenges.json,
## each watching one counter ("stat") up to a target, counted outside the simulation from
## MatchStats and the sim's events, shown on Profile > Challenges. A completed goal pays its
## reward once through Progress: account XP (`Progress.grant_xp`) and/or a reward id such as
## a title (`Progress.grant_unlock`). Nothing here changes how a match plays.
##
## Fed by main: `begin_match()` where MatchStats resets (main.gd `_new_sim`, round 1),
## `note_event(e)` from `_react` next to `stats.note`, and `note_match(report, rows, ctx)`
## from main_presentation.gd `award_match`, right after `Progress.award` (once per sim).
## Only the account's own player counts: the report's first human (player 1 in local
## play, the local slot online); a report of kind "none" (training, showcases, coaches,
## replays, spectating, CPU vs CPU) counts nothing, and so does everything while Off.
##
## Save: progress.json's "challenges" key (`Progress.section`):
##   {"counts": {counter: n}, "done": [goal ids]}; a missing or odd one reads as empty.
## Counters are keyed by the stat (a per-fighter one "wins_as:<fighter>", a map's win
## "wins_on:<arena id>"), so goals sharing a stat share its count and a goal added later
## starts from what was already counted.
##
## API: goals(), goal(id), counter_of(goal), count(counter), progress(id) -> [count, target],
## done(id), done_count(), completed_this_match() -> [ids], result_line(ids), reward_text(goal),
## titles() -> [reward ids of titles], goal_of_reward(reward_id).

const DATA_PATH := "res://data/challenges.json"
const SAVE_KEY := "challenges"
## Every counter a goal's "stat" may name (tests/test_challenges.gd fails on any other).
const STATS := ["fights", "wins", "kos", "blocks", "combo_5", "combo_10", "wins_as", "surge_kos",
	"guard_breaks", "dodge_cancels", "breakaways", "flawless_wins", "clutch_wins", "ring_outs",
	"sprees", "flag_captures", "caravan_finishes", "crater_holds", "gauntlet_waves",
	"arcade_clears_easy", "arcade_clears_normal", "arcade_clears_hard", "arcade_clears_rage",
	"dailies", "brawl_wins", "chaos_wins", "sinkhole_wins", "online_matches",
	"meteor_untouched", "wave_shelters", "boulders_sent_back", "boulder_hits", "maps_won"]
## Stats counted per fighter (a goal using one names its "fighter").
const PER_FIGHTER := ["wins_as"]
## The Arcade's CPU levels, for arcade_clears_<level> (a clear counts for its level and every easier one).
const LEVELS := ["easy", "normal", "hard", "rage"]
## "flawless" and "clutch": health share left at the end.
const CLUTCH_SHARE := 0.1
## King of the Crater: zone time (ticks) for crater_holds.
const CRATER_HOLD_TICKS := 60 * 60

static var _goals: Array = []
static var _by_id := {}
static var _groups: Array = []

# This match (from begin_match): counts by creature id and by team, and what the events need.
static var _m := {}
static var _team := {}
static var _last := {}  ## victim id -> [the id that last hurt it, that hit's move_type]
static var _breaking := {}  ## a guard_break's victim -> true until the hit that broke it
static var _hurt := {}  ## ids that lost health
static var _meteors := false
static var _meteor_hit := {}
static var _boulder_hits: Array = []  ## [by, who]: a sent-back boulder struck someone
static var _completed: Array = []


# ------------------------------------------------------------------ the data


static func _load() -> void:
	if not _goals.is_empty():
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	if not (d is Dictionary):
		return
	_groups = d.get("groups", [])
	for g in d.get("goals", []):
		if String(g.get("fighter", "")) == "{fighter}":
			for fid in MatchFactory.FIGHTERS:
				_goals.append(_expand(g, String(fid)))
		else:
			_goals.append((g as Dictionary).duplicate(true))
	for g in _goals:
		_by_id[String(g["id"])] = g


static func _expand(g: Dictionary, fid: String) -> Dictionary:
	var name := String(MatchFactory.load_def(fid).get("name", fid))
	var out := g.duplicate(true)
	out["fighter"] = fid
	for k in ["id", "name", "desc"]:
		out[k] = String(g.get(k, "")).replace("{fighter}", fid).replace("{name}", name)
	return out


## Every goal, per-fighter ones expanded (data order).
static func goals() -> Array:
	_load()
	return _goals


## The headings, in order.
static func groups() -> Array:
	_load()
	return _groups


static func goal(id: String) -> Dictionary:
	_load()
	return _by_id.get(id, {})


## The counter a goal watches: its stat, or "<stat>:<fighter>" for a per-fighter one.
static func counter_of(g: Dictionary) -> String:
	var stat := String(g.get("stat", ""))
	return stat + ":" + String(g["fighter"]) if stat in PER_FIGHTER and g.has("fighter") else stat


# ------------------------------------------------------------------ the save


static func _save() -> Dictionary:
	var s := Progress.section(SAVE_KEY)
	if not (s.get("counts") is Dictionary):
		s["counts"] = {}
	if not (s.get("done") is Array):
		s["done"] = []
	return s


static func count(counter: String) -> int:
	if counter == "maps_won":  # derived: the maps won on at least once
		var n := 0
		var counts: Dictionary = _save()["counts"]
		for k in counts:
			if String(k).begins_with("wins_on:") and int(counts[k]) > 0:
				n += 1
		return n
	var v = _save()["counts"].get(counter, 0)
	return maxi(0, int(v)) if (v is int or v is float) else 0


## [count, target] (the count stops at the target).
static func progress(id: String) -> Array:
	var g := goal(id)
	if g.is_empty():
		return [0, 0]
	var t := int(g.get("target", 1))
	return [mini(count(counter_of(g)), t), t]


static func done(id: String) -> bool:
	return (_save()["done"] as Array).has(id)


static func done_count() -> int:
	var n := 0
	for g in goals():
		if done(String(g["id"])):
			n += 1
	return n


# ------------------------------------------------------------------ a match


## A new match (main.gd `_new_sim` at round 1, where MatchStats resets).
static func begin_match() -> void:
	_m.clear()
	_team.clear()
	_last.clear()
	_breaking.clear()
	_hurt.clear()
	_meteor_hit.clear()
	_boulder_hits.clear()
	_meteors = false


static func _add(id: int, stat: String, n := 1) -> void:
	if id < 0:
		return
	if not _m.has(id):
		_m[id] = {}
	_m[id][stat] = int(_m[id].get(stat, 0)) + n


## One sim event (main.gd `_react`, beside `stats.note`). Off: nothing.
static func note_event(e: Dictionary) -> void:
	if not Progress.enabled():
		return
	match String(e.get("type", "")):
		"hit":
			var a := int(e.get("attacker", -1))
			var t := int(e.get("target", -1))
			if _breaking.has(t):
				_breaking.erase(t)
				if a != t:
					_add(a, "guard_breaks")
			_last[t] = [a, String(e.get("move_type", ""))]
			if float(e.get("dealt", e.get("power", 0.0))) > 0.0:
				_hurt[t] = true
		"block":
			if float(e.get("dealt", 0.0)) > 0.0:
				_hurt[int(e.get("target", -1))] = true
		"armor":
			if float(e.get("power", 0.0)) > 0.0:
				_hurt[int(e.get("target", -1))] = true
		"poisoned", "shatter":
			var by := int(e.get("by", -1))
			if by >= 0:
				_last[int(e.get("who", -1))] = [by, ""]
		"poison":
			_hurt[int(e.get("who", -1))] = true
		"guard_break":
			_breaking[int(e.get("who", -1))] = true
		"ko", "fall":
			var who := int(e.get("who", -1))
			_hurt[who] = true
			if _last.has(who):
				var k: int = _last[who][0]
				var mt := String(_last[who][1])
				_last.erase(who)
				if k != who:
					if String(e["type"]) == "fall":
						_add(k, "ring_outs")
					if mt == "surge":
						_add(k, "surge_kos")
		"dodge":
			if bool(e.get("cancel", false)):
				_add(int(e.get("who", -1)), "dodge_cancels")
		"breakaway":
			_add(int(e.get("who", -1)), "breakaways")
		"spree":
			_add(int(e.get("who", -1)), "sprees")
		"capture":
			_add(int(e.get("who", -1)), "flag_captures")
		"caravan_done":
			var tm := int(e.get("team", -1))
			_team[tm] = int(_team.get(tm, 0)) + 1
		"hazard_strike":
			if String(e.get("shape", "")) == "meteors":
				_meteors = true
		"hazard_hit":
			var who := int(e.get("who", -1))
			_hurt[who] = true
			if String(e.get("shape", "")) == "meteors":
				_meteor_hit[who] = true
			var by := int(e.get("by", -1))
			if String(e.get("shape", "")) == "boulder" and by >= 0 and by != who:
				_boulder_hits.append([by, who])
		"hazard_shelter":
			_add(int(e.get("who", -1)), "wave_shelters")
		"hazard_reverse":
			_add(int(e.get("by", -1)), "boulders_sent_back")


## The finished match (main_presentation.gd `award_match`, after `Progress.award`):
## `report` is Progress.award's report, `rows` MatchStats.rows, `ctx` what the report
## lacks: {"mode": "versus" | "duel" | "team" | "tdm" | "sinkhole" | "crater" | "caravan" |
## "ctf" | "brawl" | "chaos" | "arcade" | "gauntlet" | "daily" | "weekly", "arena": arena id,
## "hp": the player's health share at the end (-1 unknown), "team": their team,
## "teams": {creature id: team}, "crater_ticks": their team's zone time}.
## Adds to the counters, completes goals and pays them. Returns the rewards paid, shaped
## like Progress.award's result ({} when nothing was paid); `completed_this_match()` the ids.
static func note_match(report: Dictionary, rows: Dictionary, ctx := {}) -> Dictionary:
	_completed = []
	var players: Array = report.get("players", [])
	if not Progress.enabled() or String(report.get("kind", "none")) == "none" or players.is_empty():
		return {}
	var p: Dictionary = players[0]  # the account's player: player 1 here, the local slot online
	var slot := int(p.get("slot", 0))
	var won := bool(p.get("won", false))
	var row: Dictionary = rows.get(slot, {})
	var mode := String(ctx.get("mode", ""))
	var hp := float(ctx.get("hp", -1.0))
	var add := {}
	_inc(add, "fights")
	if won:
		_inc(add, "wins")
		for f in p.get("fighters", []):
			_inc(add, "wins_as:" + String(f))
		if String(ctx.get("arena", "")) != "":
			_inc(add, "wins_on:" + String(ctx["arena"]))
		if mode in ["brawl", "chaos", "sinkhole"]:
			_inc(add, {"brawl": "brawl_wins", "chaos": "chaos_wins", "sinkhole": "sinkhole_wins"}[mode])
		if mode == "chaos":
			_inc(add, "brawl_wins")  # the Chaos Cup is a Brawl too
		if not _hurt.has(slot) and (hp < 0.0 or hp >= 0.999):
			_inc(add, "flawless_wins")
		if hp > 0.0 and hp < CLUTCH_SHARE:
			_inc(add, "clutch_wins")
	_inc(add, "kos", int(row.get("kos", 0)))
	_inc(add, "blocks", int(row.get("blocks", 0)))
	if int(row.get("combo", 0)) >= 5:
		_inc(add, "combo_5")
	if int(row.get("combo", 0)) >= 10:
		_inc(add, "combo_10")
	for stat in _m.get(slot, {}):
		_inc(add, String(stat), int(_m[slot][stat]))
	_inc(add, "caravan_finishes", int(_team.get(int(ctx.get("team", -1)), 0)))
	var teams: Dictionary = ctx.get("teams", {})
	for bh in _boulder_hits:
		if int(bh[0]) == slot and teams.get(int(bh[1]), -1) != teams.get(slot, -2):
			_inc(add, "boulder_hits")
	if _meteors and not _meteor_hit.has(slot):
		_inc(add, "meteor_untouched")
	if mode == "crater" and int(ctx.get("crater_ticks", 0)) >= CRATER_HOLD_TICKS:
		_inc(add, "crater_holds")
	if mode == "daily":
		_inc(add, "dailies")
	_inc(add, "gauntlet_waves", int(report.get("waves", 0)))
	if bool(report.get("clear_arcade", false)):
		for k in range(0, clampi(int(report.get("cpu_level", 0)), 0, LEVELS.size() - 1) + 1):
			_inc(add, "arcade_clears_" + LEVELS[k])
	if String(report.get("kind", "")) == "online":
		_inc(add, "online_matches")
	var s := _save()
	for c in add:
		s["counts"][c] = count(String(c)) + int(add[c])
	# Completions, each paid once.
	var paid := {}
	for g in goals():
		var id := String(g["id"])
		if done(id) or count(counter_of(g)) < int(g.get("target", 1)):
			continue
		(s["done"] as Array).append(id)
		_completed.append(id)
		var rw: Dictionary = g.get("reward", {})
		paid = Progress.merge_results(paid, Progress.grant_xp(int(rw.get("xp", 0)), id))
		var rid := String(rw.get("id", ""))
		if rid != "" and Progress.grant_unlock(rid):
			if paid.is_empty():
				var lvl := Progress.account_level()
				paid = {"xp": 0, "level_from": lvl, "level_to": lvl, "mastery": {}, "unlocked": []}
			paid["unlocked"].append(rid)
	Progress.save()
	return paid


static func _inc(add: Dictionary, counter: String, n := 1) -> void:
	if n > 0:
		add[counter] = int(add.get(counter, 0)) + n


## The goals the last `note_match` completed.
static func completed_this_match() -> Array:
	return _completed.duplicate()


## The results screen's row for these completions: "Challenge: <name>", "+N challenges", "".
static func result_line(ids: Array) -> String:
	if ids.is_empty():
		return ""
	if ids.size() == 1:
		return "Challenge: " + String(goal(String(ids[0])).get("name", ids[0]))
	return "+%d challenges" % ids.size()


## A goal's reward in words: "+100 XP", "+400 XP, title \"Centurion\"".
static func reward_text(g: Dictionary) -> String:
	var rw: Dictionary = g.get("reward", {})
	var bits := PackedStringArray()
	if int(rw.get("xp", 0)) > 0:
		bits.append("+%d XP" % int(rw["xp"]))
	if String(rw.get("id", "")) != "":
		bits.append(Progress.reward_text(String(rw["id"])))
	return ", ".join(bits)


## Every title a challenge gives (reward ids, data order), for the Profile's title pickers.
static func titles() -> Array:
	var out: Array = []
	for g in goals():
		var rid := String(g.get("reward", {}).get("id", ""))
		if rid.begins_with("title:") and not out.has(rid):
			out.append(rid)
	return out


## The goal whose reward this is ({} none).
static func goal_of_reward(reward_id: String) -> Dictionary:
	for g in goals():
		if String(g.get("reward", {}).get("id", "")) == reward_id:
			return g
	return {}
