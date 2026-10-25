class_name Daily
extends Ladder
## The Daily Challenge: one seeded fight a day, the same for everyone. The date (UTC)
## picks the opponent, the CPU level (Normal or Hard) and two mutators from
## data/rules/mutators.json. A win scores by health left and time to spare; a loss
## scores nothing. The replay of the fight is saved with the score, and `verify`
## replays it on a fresh match to recompute the score, so a score can be checked
## by anyone with the inputs (a server, later).

const MUTATORS_PATH := "res://data/rules/mutators.json"
const PICKS := 2
const FIGHT_TICKS := 90 * 60  ## the fight's clock (main.gd ROUND_TICKS)

var date := 0  ## YYYYMMDD, UTC
var picks: Array = []  ## mutator ids
var _opponent := "culvert"


static func today() -> int:
	var d := Time.get_datetime_dict_from_system(true)
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])


static func mutator_table() -> Dictionary:
	var f := FileAccess.open(MUTATORS_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	var out := {}
	if d is Dictionary:
		for k in d:
			if not String(k).begins_with("_"):
				out[k] = d[k]
	return out


## The names of the mutators in a merged mutator dictionary (MatchSim.mutators).
static func mutator_names(m: Dictionary) -> Array:
	var out: Array = []
	var table := mutator_table()
	for id in table:
		var entry: Dictionary = table[id]
		var all := true
		var any := false
		for k in entry:
			if k == "name":
				continue
			any = true
			if k == "hazards":  # merged lists add up: each of this entry's hazards is on
				for h in entry[k]:
					if not (h in (m.get("hazards", []) as Array)):
						all = false
			elif not m.has(k) or m[k] != entry[k]:
				all = false
		if any and all:
			out.append(String(entry.get("name", id)))
	return out


func _init(p_fighter: String, p_date := 0) -> void:
	fighter = p_fighter if p_fighter in MatchFactory.FIGHTERS else "cairn"
	date = p_date if p_date > 0 else today()
	var rng := RandomNumberGenerator.new()
	rng.seed = date * 7919 + 17
	var pool: Array = MatchFactory.FIGHTERS.duplicate()
	_opponent = String(pool[rng.randi_range(0, pool.size() - 1)])
	level = 1 + rng.randi_range(0, 1)  # Normal or Hard
	var ids: Array = mutator_table().keys()
	ids.sort()
	picks = []
	while picks.size() < mini(PICKS, ids.size()):
		var id: String = ids[rng.randi_range(0, ids.size() - 1)]
		if not (id in picks):
			picks.append(id)


func opponent() -> String:
	return _opponent


func stage_label() -> String:
	return "DAILY CHALLENGE  %d-%02d-%02d" % [date / 10000, (date / 100) % 100, date % 100]


func versus_label() -> String:
	var table := mutator_table()
	var names: Array = picks.map(func(id): return String(table[id].get("name", id)))
	return "vs %s  ·  %s  ·  %s" % [String(MatchFactory.load_def(opponent()).get("name", opponent())),
		CpuController.LEVELS[stage_level()]["name"], ", ".join(names)]


func mutators() -> Dictionary:
	var out := {}
	var table := mutator_table()
	for id in picks:
		MatchSim.merge_mutator(out, table[id])
	return out


func stage_won(_hp: float) -> bool:
	return false  # one fight: done


func can_retry() -> bool:
	return false


## A win is worth the health left (up to 1000) plus five a second to spare; a loss nothing.
func score_fight(won: bool, hp_share: float, ticks: int) -> int:
	if not won:
		return 0
	return roundi(hp_share * 1000.0) + maxi(0, (FIGHT_TICKS - ticks) / 60) * 5


func cleared_banner() -> Array:
	return ["TIME", ""]


## The match this challenge plays: the fighter against the day's opponent, with its
## mutators, seeded by the date (the CPU's seed is the date too, so the fight is the
## same for the same inputs anywhere).
func build() -> MatchSim:
	var sim := MatchFactory.versus(fighter, opponent())
	sim.apply_mutators(mutators(), date)
	return sim


## The CPU this challenge faces (the same for everyone on the day).
func cpu() -> CpuController:
	return CpuController.new(1, stage_level(), date)


## Replays a recorded fight on a fresh match and scores it: the score anyone can check.
## The replay's rows are [player bits, cpu bits] per tick, the CPU's as they were.
func verify(rep: Replay) -> int:
	var v := Verify.new(self, rep)
	while not v.step(Daily.FIGHT_TICKS + 60):
		pass
	return v.score


## A verification done a slice at a time (the server spreads one over several loops, so
## scoring a replay never holds up the matches it runs): step() until it returns true,
## then read `score`. Same result as verify().
class Verify:
	var daily: Daily
	var rep: Replay
	var sim: MatchSim
	var ticks := 0
	var score := 0
	var done := false

	func _init(p_daily: Daily, p_rep: Replay) -> void:
		daily = p_daily
		rep = p_rep
		sim = daily.build()

	## Steps up to `frames` more; true once the fight is over and `score` is set.
	func step(frames: int) -> bool:
		if done:
			return true
		var until := mini(rep.frames.size(), ticks + frames)
		while ticks < until:
			sim.step(rep.frames[ticks])
			ticks += 1
			if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
				break
		var over := ticks >= rep.frames.size() or sim.creatures[0].state == CreatureSim.State.KO \
			or sim.creatures[1].state == CreatureSim.State.KO
		if not over:
			return false
		var me := sim.creatures[0]
		var foe := sim.creatures[1]
		var won := foe.state == CreatureSim.State.KO or (me.state != CreatureSim.State.KO and ticks >= Daily.FIGHT_TICKS
			and me.hp / me.max_hp > foe.hp / foe.max_hp)
		score = daily.score_fight(won, me.hp / me.max_hp, ticks)
		done = true
		return true
