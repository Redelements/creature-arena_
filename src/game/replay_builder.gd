class_name ReplayBuilder
extends RefCounted
## Rebuilds the match a replay was recorded on from the setup saved with it (main
## writes `Replay.setup` when a match starts), so its inputs play back the same fight.
## A setup is {"kind": "versus" | "training" | "duel" | "team" | "brawl", "ids": [fighter
## per slot], "teams": [[...], [...]] (duel, team), "size": per side (team), "rules": id
## (team: "" for a plain battle; duel: "1v1" for a best-of-three online 1v1), "arena": map id, "mutators": {...}, "mut_seed": int}.
## Training adds "training_flags" (the options it started with, MatchSim.TRAINING_FLAGS)
## and "flag_changes": [[frame, no_cooldowns, full_energy], ...], options changed from the
## pause menu, applied just before that frame's inputs (`apply_flag_changes`).
## Returns {"sim": MatchSim, "game": the DuelSim / TeamSim / BrawlSim or null}.

const REMOVED_MODE := "This replay is from a mode that was removed"


## Why a setup can't be rebuilt any more ("" when it can): a team replay whose rules id
## is no longer one of TeamSim.RULE_IDS (Showtime, removed) would rebuild as a different
## match and play its inputs into nonsense, so the theater refuses it instead.
## A setup that isn't one this game could have written (a damaged or hand-made file: an
## unknown fighter or kind, a team of the wrong size) is refused the same way, with
## DAMAGED, before anything is built from it.
static func unsupported(setup: Dictionary) -> String:
	if not valid_setup(setup):
		return DAMAGED
	if str(setup.get("kind", "versus")) == "team" and not TeamSim.RULE_IDS.has(str(setup.get("rules", ""))):
		return REMOVED_MODE
	return ""


const DAMAGED := "This replay file is damaged or from an unknown build"
const KINDS := ["versus", "training", "duel", "team", "brawl"]


## Whether every part of a setup `build` reads is the right type and in range: the kind,
## each fighter id (one this build has), the teams (two sides of known fighters, `size`
## each in a team battle), the size, the arena, and the optional mutators, energy,
## training flags and flag changes.
static func valid_setup(setup: Dictionary) -> bool:
	var kind = setup.get("kind", "versus")
	if not (kind is String) or not (kind in KINDS):
		return false
	var ids = setup.get("ids", ["cairn", "culvert"])
	if not (ids is Array) or (ids as Array).is_empty() or (ids as Array).size() > TeamSim.MOST_PER_SIDE * 2:
		return false
	for id in ids:
		if not (id is String) or not (id in MatchFactory.FIGHTERS or id == "dummy"):
			return false
	if kind == "brawl" and ((ids as Array).size() < 2 or (ids as Array).size() > BrawlSim.MAX_PLAYERS):
		return false
	if kind == "versus" and (ids as Array).size() > 2:
		return false
	if setup.has("arena") and not (setup["arena"] is String and ArenaMap.known(String(setup["arena"]))):
		return false
	for k in ["rules"]:
		if setup.has(k) and not (setup[k] is String):
			return false
	for k in ["mut_seed"]:
		if setup.has(k) and typeof(setup[k]) != TYPE_INT and typeof(setup[k]) != TYPE_FLOAT:
			return false
	for k in ["mutators", "training_flags"]:
		if setup.has(k) and not (setup[k] is Dictionary):
			return false
	for k in ["energy", "flag_changes"]:
		if setup.has(k) and not (setup[k] is Array):
			return false
	if setup.has("energy") and (setup["energy"] as Array).size() > 8:
		return false
	if setup.has("mutators") and not _valid_mutators(setup["mutators"]):
		return false
	if kind == "duel" or kind == "team":
		var size := 1
		if kind == "team":
			var s = setup.get("size", 1)
			if typeof(s) != TYPE_INT and typeof(s) != TYPE_FLOAT:
				return false
			size = int(s)
			if size < 1 or size > TeamSim.MOST_PER_SIDE:
				return false
		if setup.has("teams"):
			var teams = setup["teams"]
			if not (teams is Array) or (teams as Array).size() != 2:
				return false
			for side in teams:
				if not Netplay.valid_team(side, TeamSim.MOST_PER_SIDE):
					return false
				if kind == "team" and (side as Array).size() != size:
					return false
		elif (ids as Array).size() < 2:
			return false
	return true


## The mutator keys MatchSim.apply_mutators reads, each a number in a sane range, and
## `hazards` a short list of ids (unknown ones are skipped by Hazards.setup).
static func _valid_mutators(m: Dictionary) -> bool:
	var most := {"air_mult": 10.0, "speed_mult": 10.0, "damage_mult": 10.0, "pit_floor": 1.0, "surge_every": 1e6}
	for k in most:
		if m.has(k):
			var v = m[k]
			if (typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT) or is_nan(float(v)) \
					or float(v) < 0.0 or float(v) > float(most[k]):
				return false
	if m.has("hazards"):
		if not (m["hazards"] is Array) or (m["hazards"] as Array).size() > 8:
			return false
		for h in m["hazards"]:
			if not (h is String):
				return false
	return true


static func build(setup: Dictionary) -> Dictionary:
	var kind := String(setup.get("kind", "versus"))
	var ids: Array = setup.get("ids", ["cairn", "culvert"])
	var was: String = MatchFactory.arena
	MatchFactory.arena = String(setup.get("arena", ArenaMap.DEFAULT))
	var out := {"sim": null, "game": null}
	match kind:
		"training":
			out["sim"] = MatchFactory.training(String(ids[0]))
			(out["sim"] as MatchSim).set_training_flags(setup.get("training_flags", {}))
		"duel":
			# "rules": "1v1" since online 1v1s went best of three; older replays have "".
			var d := DuelSim.new(setup.get("teams", [[ids[0]], [ids[1]]]),
				DuelSim.rules_by_id(String(setup.get("rules", ""))))
			out["sim"] = d.sim
			out["game"] = d
		"team":
			var rules := TeamSim.rules_by_id(String(setup.get("rules", "")))
			var t := TeamSim.new(setup.get("teams", [[ids[0]], [ids[1]]]), clampi(int(setup.get("size", 1)), 1, TeamSim.MOST_PER_SIDE), rules,
				int(setup.get("mut_seed", 0)))
			out["sim"] = t.sim
			out["game"] = t
		"brawl":
			var b := BrawlSim.new(ids, {}, setup.get("mutators", {}), int(setup.get("mut_seed", 0)))
			out["sim"] = b.sim
			out["game"] = b
		_:
			out["sim"] = MatchFactory.versus(String(ids[0]), String(ids[1] if ids.size() > 1 else "culvert"))
	MatchFactory.arena = was
	# A round that began with Surge energy carried over from the last one.
	var start_energy: Array = setup.get("energy", [])
	if kind == "versus" and start_energy.size() == 2:
		for i in 2:
			(out["sim"] as MatchSim).creatures[i].energy = float(start_energy[i])
	var muts: Dictionary = setup.get("mutators", {})
	if not muts.is_empty() and kind != "brawl":
		(out["sim"] as MatchSim).apply_mutators(muts, int(setup.get("mut_seed", 0)))
	return out


## Plays a replay's frames on what it was recorded on; returns the final digest.
static func play(rep: Replay) -> String:
	var built := build(rep.setup if rep.setup is Dictionary else {})
	var game = built["game"]
	var setup: Dictionary = rep.setup if rep.setup is Dictionary else {}
	for i in rep.frames.size():
		var f: PackedInt32Array = rep.frames[i]
		apply_flag_changes(built["sim"], setup, i)
		if game != null:
			game.step(f)
		else:
			(built["sim"] as MatchSim).step(f)
	return (built["sim"] as MatchSim).state_digest()


## A training replay: the options changed mid-recording that take effect before frame
## `frame` (in the order they were made; the last one wins).
static func apply_flag_changes(sim: MatchSim, setup: Dictionary, frame: int) -> void:
	for ch in setup.get("flag_changes", []):
		if ch is Array and (ch as Array).size() >= 3 and int(ch[0]) == frame:
			sim.set_training_flags({"no_cooldowns": bool(ch[1]), "full_energy": bool(ch[2])})
