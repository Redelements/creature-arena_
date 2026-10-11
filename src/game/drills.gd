class_name ReactionDrill
extends RefCounted
## Reaction Drills: the partner throws random RAW big moves, which wind up with a tell,
## and the player answers. Red (can't be blocked): roll away, or hit them first.
## Gold (strong but blockable): guard, roll, or hit them first. 20 reps, then a score
## with the average reaction time (from the tell to the first guard or roll press).
##
## Like ComboTrials, this is a coach: main.gd asks it for both sides' inputs each tick.

enum Phase { SETUP, WAIT, ATTACK, RESULT, DONE }

const REPS := 20
const SETS := {
	# player fighter, partner (attacker), the partner's moves and the gap to throw them from
	"culvert": {"player": "cairn", "partner": "culvert", "title": "Read Culvert's windups",
		"moves": [["skill_1", 4.0], ["heavy", 4.0], ["skill_2", 60.0]]},
	"cairn": {"player": "culvert", "partner": "cairn", "title": "Read Cairn's windups",
		"moves": [["skill_2", 36.0], ["heavy", 4.0]]},
}
const BITS := {"heavy": SimDefs.IN_HEAVY, "skill_1": SimDefs.IN_SKILL1, "skill_2": SimDefs.IN_SKILL2}

var set_name := "culvert"
var sim: MatchSim
var phase: Phase = Phase.SETUP
var rep := 0
var clean := 0
var streak := 0
var best_streak := 0
var reactions: Array = []

# For main.gd / the HUD.
var title := ""
var caption_items: Array = []
var caption_index := 99
var banner := ""
var fade := 0.0
var reset_view := false
var callouts: Array = []

var _rng := RandomNumberGenerator.new()
var _initial := {}
var _t := 0
var _wait := 0
var _move := ""
var _tell := ""
var _tell_tick := -1
var _reaction := -1
var _hit := false
var _blocked := false
var _dodged := false
var _interrupted := false
var _guarded_red := false
var _prev_player := 0


func _init(p_set := "culvert", seed_ := 1) -> void:
	set_name = p_set if SETS.has(p_set) else "culvert"
	_rng.seed = seed_


func build() -> MatchSim:
	var s: Dictionary = SETS[set_name]
	sim = MatchFactory.versus(String(s["player"]), String(s["partner"]))
	_initial = sim.snapshot()
	title = "REACTION DRILL  -  %s  -  red: roll away   gold: guard" % String(s["title"])
	rep = 0
	clean = 0
	streak = 0
	best_streak = 0
	reactions = []
	_next_rep()
	return sim


func _next_rep() -> void:
	sim.restore(_initial)
	reset_view = true
	var s: Dictionary = SETS[set_name]
	var pick: Array = s["moves"][_rng.randi() % (s["moves"] as Array).size()]
	_move = String(pick[0])
	var gap := float(pick[1])
	var p := sim.creatures[0]
	var a := sim.creatures[1]
	p.pos = Vector2(Showcase.START_X, Showcase.START_Y)
	a.pos = Vector2(Showcase.START_X + p.radius + a.radius + gap, Showcase.START_Y)
	p.facing = Vector2.RIGHT
	a.facing = Vector2.LEFT
	_wait = _rng.randi_range(45, 110)
	_t = 0
	_tell = ""
	_tell_tick = -1
	_reaction = -1
	_hit = false
	_blocked = false
	_dodged = false
	_interrupted = false
	_guarded_red = false
	banner = ""
	phase = Phase.WAIT
	_refresh_caption()


func _refresh_caption() -> void:
	var avg := "-"
	if not reactions.is_empty():
		var sum := 0
		for r in reactions:
			sum += int(r)
		avg = "%d f" % int(round(float(sum) / reactions.size()))
	caption_items = ["Rep %d / %d" % [mini(rep + 1, REPS), REPS], "Clean %d" % clean, "Streak %d (best %d)" % [streak, best_streak],
		"Avg reaction %s" % avg]


func inputs(player_bits: int) -> PackedInt32Array:
	_t += 1
	var partner := 0
	match phase:
		Phase.WAIT:
			if _t >= _wait:
				partner = int(BITS[_move])
				phase = Phase.ATTACK
				_t = 0
		Phase.RESULT:
			if _t >= 70:
				rep += 1
				if rep >= REPS:
					phase = Phase.DONE
					_t = 0
					banner = "%d / %d CLEAN" % [clean, REPS]
				else:
					_next_rep()
		Phase.DONE:
			if _t >= 240:
				build()
	# Reaction time: from the tell to the first guard or roll press.
	if _tell_tick >= 0 and _reaction < 0:
		var pressed := player_bits & ~_prev_player
		if (pressed & SimDefs.IN_DODGE) or (player_bits & SimDefs.IN_GUARD) or (pressed & SimDefs.IN_LIGHT):
			_reaction = sim.tick - _tell_tick
	_prev_player = player_bits
	return PackedInt32Array([player_bits, partner])


func after_step() -> void:
	if phase != Phase.ATTACK:
		return
	var p := sim.creatures[0]
	var a := sim.creatures[1]
	for e in sim.events:
		match String(e["type"]):
			"windup":
				if int(e.get("who", -1)) == 1:
					_tell = String(e.get("tell", "strong"))
					_tell_tick = sim.tick
			"hit", "grab":
				if int(e.get("target", -1)) == 0:
					_hit = true
					if _tell in ["unblockable", "guard_break"] and p.state in [CreatureSim.State.GUARD, CreatureSim.State.CRUMPLE]:
						_guarded_red = true
				elif int(e.get("target", -1)) == 1:
					_interrupted = true
			"block":
				if int(e.get("target", -1)) == 0:
					_blocked = true
			"guard_break":
				_guarded_red = true
	if p.state == CreatureSim.State.DODGE:
		_dodged = true
	# The attack is over once the partner is back to neutral (or got hit out of it)
	# and any wave it threw has finished.
	var done := a.state != CreatureSim.State.ATTACK and sim.projectiles.is_empty() and _t > 4
	if done:
		_judge()


func _judge() -> void:
	phase = Phase.RESULT
	_t = 0
	var p := sim.creatures[0]
	var ok := not _hit
	var why := ""
	if _interrupted and not _hit:
		why = "INTERRUPTED!"
	elif ok and _blocked:
		why = "BLOCKED!"
	elif ok and _dodged:
		why = "DODGED!"
	elif ok:
		why = "AVOIDED"
	elif _guarded_red:
		why = "RED CAN'T BE BLOCKED - ROLL!"
	else:
		why = "HIT"
	if ok:
		clean += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		if _reaction >= 0:
			reactions.append(_reaction)
	else:
		streak = 0
	var react_txt := ("  %d f" % _reaction) if _reaction >= 0 else ""
	banner = why + react_txt
	callouts.append([p.pos + Vector2(0, -30), why, Color("b6f28a") if ok else Color("ff9a5a")])
	_refresh_caption()
