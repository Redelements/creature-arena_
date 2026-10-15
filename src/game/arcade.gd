class_name Arcade
extends RefCounted
## The Arcade ladder: six fights as one fighter up the roster, the sixth a 3v3 Duel
## against a Rage-level team (the boss). Stages 1-5 are single rounds against one
## opponent each at the chosen CPU level; the boss plays one level up (Rage at most).
## The order of opponents is drawn from the roster with a seed, so a run can be
## repeated. Clearing it records the level on the player's progress (Progress).

const STAGES := 6
const TEAM := 3  ## the boss Duel's team size

var fighter := "cairn"
var level := 1  ## the CPU level for stages 1-5
var stage := 0  ## 0-based; STAGES - 1 is the boss
var order: Array = []  ## opponent ids for stages 1-5, then the boss team
var allies: Array = []  ## the two teammates for the boss Duel


func _init(p_fighter: String, p_level: int, seed_: int) -> void:
	fighter = p_fighter if p_fighter in MatchFactory.FIGHTERS else "cairn"
	level = clampi(p_level, 0, CpuController.LEVELS.size() - 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var pool: Array = MatchFactory.FIGHTERS.filter(func(f): return f != fighter)
	# A seeded shuffle (Fisher-Yates) so the same seed gives the same ladder.
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	order = pool.slice(0, STAGES - 1)
	var rest: Array = pool.slice(STAGES - 1)
	while rest.size() < TEAM + 2:
		rest.append(pool[rest.size() % pool.size()])
	allies = rest.slice(0, 2)
	order.append(rest.slice(2, 2 + TEAM))  # the boss team


func is_boss() -> bool:
	return stage >= STAGES - 1


func opponent() -> String:
	return String(order[stage]) if not is_boss() else ""


func boss_team() -> Array:
	return order[STAGES - 1]


func player_team() -> Array:
	return [fighter] + allies


## The CPU level this stage plays at: the boss one up, Rage at most.
func stage_level() -> int:
	return mini(level + 1, CpuController.LEVELS.size() - 1) if is_boss() else level


func stage_label() -> String:
	return "STAGE %d of %d" % [stage + 1, STAGES]


## What this stage is against, for the intro banner.
func versus_label() -> String:
	if is_boss():
		var names: Array = boss_team().map(func(id): return String(MatchFactory.load_def(id).get("name", id)))
		return "THE BOSS TEAM: %s  ·  %s" % [", ".join(names), CpuController.LEVELS[stage_level()]["name"]]
	return "vs %s  ·  %s" % [String(MatchFactory.load_def(opponent()).get("name", opponent())),
		CpuController.LEVELS[stage_level()]["name"]]


## Advances past a won stage; false when that was the boss (the ladder is cleared).
func advance() -> bool:
	if is_boss():
		return false
	stage += 1
	return true
