class_name Ladder
extends RefCounted
## A run of single-round fights main plays one stage at a time: the Arcade ladder, the
## Gauntlet's endless waves and the Daily Challenge's one seeded fight all answer
## these questions, so main's stage flow (`_start_ladder_stage`, `_ladder_result`) is
## the same for each. Subclasses fill in who you fight, at what level, under which
## mutators, what carries over, and what a win or a loss earns.

var fighter := "cairn"
var level := 1
var stage := 0


## The sixth Arcade stage: a 3v3 Duel instead of a single fight.
func is_boss() -> bool:
	return false


func opponent() -> String:
	return "culvert"


func boss_team() -> Array:
	return []


func player_team() -> Array:
	return [fighter]


func stage_level() -> int:
	return level


func stage_label() -> String:
	return "STAGE %d" % (stage + 1)


func versus_label() -> String:
	return "vs %s  ·  %s" % [String(MatchFactory.load_def(opponent()).get("name", opponent())),
		CpuController.LEVELS[stage_level()]["name"]]


## Mutators for this stage (keys as in data/rules/mutators.json's entries, merged).
func mutators() -> Dictionary:
	return {}


## Health the fighter starts the stage with, or -1 for full.
func carried_hp() -> float:
	return -1.0


## A stage was won with this much health left. Returns false when the run is complete.
func stage_won(_hp: float) -> bool:
	stage += 1
	return true


## The banner and line for a loss (`stage` is the one lost on).
func lost_banner() -> Array:
	return ["GAME OVER", "%s   ·   %s" % [stage_label(), versus_label()]]


## The banner and line once the run is complete (a win where stage_won returns false).
func cleared_banner() -> Array:
	return ["CLEAR!", ""]


## What the match-over menu's retry does: true to retry the same stage, false when a
## loss ends the run (the Gauntlet, the Daily) and only a fresh start makes sense.
func can_retry() -> bool:
	return true


## Scores the fight that just ended (the Daily); 0 means no score to show.
func score_fight(_won: bool, _hp_share: float, _ticks: int) -> int:
	return 0
