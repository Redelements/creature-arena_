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
static func unsupported(setup: Dictionary) -> String:
	if String(setup.get("kind", "versus")) == "team" and not TeamSim.RULE_IDS.has(String(setup.get("rules", ""))):
		return REMOVED_MODE
	return ""


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
			var t := TeamSim.new(setup.get("teams", [[ids[0]], [ids[1]]]), int(setup.get("size", 1)), rules,
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
