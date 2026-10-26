class_name Daily
extends Ladder
## The Daily Challenge: one seeded fight a day, the same for everyone. The date (UTC)
## picks the opponent, the CPU level (Normal or Hard) and two mutators from
## data/rules/mutators.json. A win scores by health left and time to spare; a loss
## scores nothing. The replay of the fight is saved with the score, and `verify`
## replays the player's inputs on a fresh match against the day's CPU to recompute the
## score, so a score can be checked by anyone with the inputs (the server does).

const MUTATORS_PATH := "res://data/rules/mutators.json"
const PICKS := 2
const FIGHT_TICKS := 120 * 60  ## the fight's clock (main.gd ROUND_TICKS)
const INTRO_TICKS := 90  ## the round's intro before it (main.gd INTRO_TICKS): nobody moves

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
## same for the same inputs anywhere). Always the stadium, whatever arena the player
## last picked: the day's fight is the same for everyone.
func build() -> MatchSim:
	var sim := MatchFactory.versus(fighter, opponent(), ArenaMap.DEFAULT)
	sim.apply_mutators(mutators(), date)
	return sim


## The CPU this challenge faces (the same for everyone on the day).
func cpu() -> CpuController:
	return CpuController.new(1, stage_level(), date)


## The most rows a Daily replay can have: the intro, the fight's clock, and a little over.
static func max_frames() -> int:
	return INTRO_TICKS + FIGHT_TICKS + 60


## Replays a recorded fight on a fresh match and scores it: the score anyone can check.
## Only the player's column of the replay is played: the day's CPU plays itself again,
## as it did in the game. -1 when the replay's CPU column isn't what that CPU pressed
## (not the day's fight, or a forged one).
func verify(rep: Replay) -> int:
	var v := Verify.new(self, rep)
	while not v.step(max_frames()):
		pass
	return -1 if v.mismatch else v.score


## A verification done a slice at a time (the server spreads one over several loops, so
## scoring a replay never holds up the matches it runs): step() until it returns true,
## then read `score` (and `mismatch`). Same result as verify().
##
## The fight is played as main plays it: INTRO_TICKS rows of nobody pressing anything
## (the "ROUND 1 / FIGHT!" banner), then the player's recorded input against the day's
## CPU (cpu()), which chooses its own input every tick from the match, exactly as it
## did offline. The recorded CPU column is never stepped: it is only compared with
## what the CPU pressed, and the first difference ends the run (`mismatch`). The round
## ends as main ends it: a knockout, or the clock (FIGHT_TICKS after the intro), where
## the bigger health share wins.
class Verify:
	var daily: Daily
	var rep: Replay
	var sim: MatchSim
	var cpu: CpuController
	var ticks := 0
	var score := 0
	var done := false
	var mismatch := false  ## the replay's CPU column differs from the day's CPU

	func _init(p_daily: Daily, p_rep: Replay) -> void:
		daily = p_daily
		rep = p_rep
		sim = daily.build()
		cpu = daily.cpu()

	## Steps up to `frames` more; true once the fight is over and `score` is set.
	func step(frames: int) -> bool:
		if done:
			return true
		var end := Daily.INTRO_TICKS + Daily.FIGHT_TICKS
		var until := mini(mini(rep.frames.size(), end), ticks + frames)
		while ticks < until:
			var row: PackedInt32Array = rep.frames[ticks]
			var ins := PackedInt32Array([0, 0])
			if ticks >= Daily.INTRO_TICKS:
				ins[0] = row[0]
				ins[1] = cpu.bits(sim)
			if row.size() < 2 or row[1] != ins[1]:
				mismatch = true
				done = true
				return true
			sim.step(ins)
			ticks += 1
			if _ko(0) or _ko(1):
				break
		var over := ticks >= rep.frames.size() or ticks >= end or _ko(0) or _ko(1)
		if not over:
			return false
		var me := sim.creatures[0]
		var foe := sim.creatures[1]
		var won := false
		if _ko(0) or _ko(1):
			won = _ko(1) and not _ko(0)
		elif ticks >= end:
			won = me.hp / me.max_hp > foe.hp / foe.max_hp
		score = daily.score_fight(won, clampf(me.hp / me.max_hp, 0.0, 1.0), ticks)
		done = true
		return true

	func _ko(i: int) -> bool:
		return sim.creatures[i].state == CreatureSim.State.KO
