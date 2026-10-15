class_name ReplayBuilder
extends RefCounted
## Rebuilds the match a replay was recorded on from the setup saved with it (main
## writes `Replay.setup` when a match starts), so its inputs play back the same fight.
## A setup is {"kind": "versus" | "training" | "duel" | "team" | "brawl", "ids": [fighter
## per slot], "teams": [[...], [...]] (duel, team), "size": per side (team), "rules": id
## (team, "" for a plain battle), "arena": map id, "mutators": {...}, "mut_seed": int}.
## Returns {"sim": MatchSim, "game": the DuelSim / TeamSim / BrawlSim or null}.

static func build(setup: Dictionary) -> Dictionary:
	var kind := String(setup.get("kind", "versus"))
	var ids: Array = setup.get("ids", ["cairn", "culvert"])
	var was: String = MatchFactory.arena
	MatchFactory.arena = String(setup.get("arena", ArenaMap.DEFAULT))
	var out := {"sim": null, "game": null}
	match kind:
		"training":
			out["sim"] = MatchFactory.training(String(ids[0]))
		"duel":
			var d := DuelSim.new(setup.get("teams", [[ids[0]], [ids[1]]]))
			out["sim"] = d.sim
			out["game"] = d
		"team":
			var rules := {}
			match String(setup.get("rules", "")):
				"deathmatch": rules = TeamSim.load_rules(TeamSim.DEATHMATCH_PATH)
				"sinkhole": rules = TeamSim.load_rules(TeamSim.SINKHOLE_PATH)
				"crater": rules = TeamSim.load_rules(TeamSim.CRATER_PATH)
				"showtime": rules = TeamSim.load_rules(TeamSim.SHOWTIME_PATH)
			var t := TeamSim.new(setup.get("teams", [[ids[0]], [ids[1]]]), int(setup.get("size", 1)), rules)
			out["sim"] = t.sim
			out["game"] = t
		"brawl":
			var b := BrawlSim.new(ids, {}, setup.get("mutators", {}), int(setup.get("mut_seed", 0)))
			out["sim"] = b.sim
			out["game"] = b
		_:
			out["sim"] = MatchFactory.versus(String(ids[0]), String(ids[1] if ids.size() > 1 else "culvert"))
	MatchFactory.arena = was
	var muts: Dictionary = setup.get("mutators", {})
	if not muts.is_empty() and kind != "brawl":
		(out["sim"] as MatchSim).apply_mutators(muts, int(setup.get("mut_seed", 0)))
	return out


## Plays a replay's frames on what it was recorded on; returns the final digest.
static func play(rep: Replay) -> String:
	var built := build(rep.setup if rep.setup is Dictionary else {})
	var game = built["game"]
	for f in rep.frames:
		if game != null:
			game.step(f)
		else:
			(built["sim"] as MatchSim).step(f)
	return (built["sim"] as MatchSim).state_digest()
