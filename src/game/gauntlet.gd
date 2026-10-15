class_name Gauntlet
extends Ladder
## Endless waves of CPU opponents as one fighter, health carrying over (plus a small
## breather between waves). The level climbs every two waves up to Rage and stays
## there; the opponents cycle the roster in a seeded order, reshuffled each lap. The
## score is the waves cleared; the best per fighter goes to Progress.

const HEAL_SHARE := 0.15  ## of max health back between waves
const WAVES_PER_LEVEL := 2

var order: Array = []
var _rng := RandomNumberGenerator.new()
var _hp := -1.0
var max_hp := 100.0


func _init(p_fighter: String, seed_: int) -> void:
	fighter = p_fighter if p_fighter in MatchFactory.FIGHTERS else "cairn"
	level = 0
	_rng.seed = seed_
	max_hp = float(MatchFactory.load_def(fighter).get("max_hp", 100))
	_shuffle()


func _shuffle() -> void:
	order = MatchFactory.FIGHTERS.filter(func(f): return f != fighter)
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t


func opponent() -> String:
	return String(order[stage % order.size()])


func stage_level() -> int:
	return mini(stage / WAVES_PER_LEVEL, CpuController.LEVELS.size() - 1)


func stage_label() -> String:
	return "WAVE %d" % (stage + 1)


func carried_hp() -> float:
	return _hp


func stage_won(hp: float) -> bool:
	_hp = minf(max_hp, hp + max_hp * HEAL_SHARE)
	stage += 1
	if stage % order.size() == 0:
		_shuffle()
	return true


## Waves cleared when the run ended.
func waves() -> int:
	return stage


func lost_banner() -> Array:
	var best := Progress.record_gauntlet(fighter, waves())
	return ["GAUNTLET OVER", "%d wave%s cleared%s" % [waves(), "" if waves() == 1 else "s",
		"   ·   a new best!" if best else "   ·   best %d" % Progress.gauntlet_best(fighter)]]


func can_retry() -> bool:
	return false
