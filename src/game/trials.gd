class_name ComboTrials
extends RefCounted
## Combo Trials: "perform this route" challenges, from data/trials.json.
##
## Each trial first plays a demo (a Showcase built from the route, real inputs), then
## hands over: the player must start every move of the route in order, each must
## connect, and the combo can't drop. A wrong move, a miss or a dropped combo resets
## the attempt. Clear it and the next trial loads.
##
## A coach like this drives the partner and judges the player; main.gd asks it for
## both sides' inputs each tick and draws its captions.

enum Phase { DEMO, PLAY, RESULT }

const DATA_PATH := "res://data/trials.json"
const ACTION_BIT := {
	"light": SimDefs.IN_LIGHT, "heavy": SimDefs.IN_HEAVY, "skill_1": SimDefs.IN_SKILL1,
	"skill_2": SimDefs.IN_SKILL2, "surge": SimDefs.IN_SURGE,
}
const RESULT_TICKS := 70

var trials: Array = []
var index := 0
var sim: MatchSim
var phase: Phase = Phase.DEMO
var attempts := 0

# For main.gd / the HUD.
var title := ""
var caption_items: Array = []
var caption_index := -1
var banner := ""
var fade := 0.0
var reset_view := false  ## main clears effects when this is set
var callouts: Array = []  ## [pos, text, color] for FxView

var _labels: Callable  ## action -> button label, from main's PlayerInput
var _initial := {}
var _demo: Showcase
var _t := 0
var _progress := 0
var _serial := -1
var _landed: Array = []
var _combo_seen := false
var _result_clear := false
var _first_hit := false


static func load_trials() -> Array:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d.get("trials", []) if typeof(d) == TYPE_DICTIONARY else []


func _init(labels: Callable = Callable(), start := 0) -> void:
	_labels = labels
	trials = load_trials()
	index = clampi(start, 0, trials.size() - 1)


func trial() -> Dictionary:
	return trials[index]


func route() -> Array:
	return trial()["route"]


## A route step to hold to a full charge: ["skill_2", "skill_2", "hold"].
static func held(step: Array) -> bool:
	return step.size() > 2 and String(step[2]) == "hold"


## A route step that hides the fighter and needn't hit (Tiptoe): ["skill_1", "skill_1", "sneak"].
## After it the player walks in, still unseen, to throw the next move.
static func sneak(step: Array) -> bool:
	return step.size() > 2 and String(step[2]) == "sneak"


## A fresh match for the current trial: the fighter facing its training partner.
func build() -> MatchSim:
	var t := trial()
	var fighter := String(t["fighter"])
	var partner := "culvert" if fighter == "cairn" else "cairn"
	sim = MatchFactory.versus(fighter, partner)
	sim.creatures[0].pos = Vector2(Showcase.START_X, Showcase.START_Y)
	# "gap": start this far apart instead of in jab range (a hook or a dash opens the route).
	sim.creatures[1].pos = Vector2(Showcase.START_X + sim.creatures[0].radius + sim.creatures[1].radius
		+ float(t.get("gap", 2.0)), Showcase.START_Y)
	sim.creatures[0].energy = float(t.get("energy", 0))
	_initial = sim.snapshot()
	_start_demo()
	_refresh_caption()
	return sim


func _start_demo() -> void:
	phase = Phase.DEMO
	_t = 0
	var steps: Array = [{"do": "wait", "t": 30, "part": 0}]
	var r := route()
	var first := 0
	if bool(trial().get("partner_jab", false)):
		steps.append({"do": "together", "bits": [ACTION_BIT[String(r[0][0])], SimDefs.IN_LIGHT], "show": 0})
		steps.append({"do": "until", "cond": "move:0:" + String(r[0][1])})
		first = 1
	var moves: Dictionary = MatchFactory.load_def(String(trial()["fighter"])).get("moves", {})
	for i in range(first, r.size()):
		var st := {"do": "press", "who": 0, "bit": ACTION_BIT[String(r[i][0])], "move": String(r[i][1]), "show": i}
		if bool(trial().get("ambush", false)):
			st["aim"] = true  # a dash out of hiding can carry him past: turn back to the partner
		if held(r[i]):  # hold it to a full charge (Runoff's wave)
			st["charge"] = int(moves.get(String(r[i][1]), {}).get("charge_max", 0))
		steps.append(st)
		if sneak(r[i]):  # out of sight: let it finish, then creep up to "approach" px away
			steps.append({"do": "until", "cond": "free:0"})
			steps.append({"do": "approach", "who": 0, "gap": float(trial().get("approach", 4.0))})
	steps.append({"do": "until", "cond": "settled"})
	steps.append({"do": "wait", "t": 40, "show": r.size()})
	_demo = Showcase.new("trial", {"left": "", "right": "", "title": "", "captions": [[]], "steps": steps})


func _reset_attempt() -> void:
	var from_demo := phase == Phase.DEMO
	sim.restore(_initial)
	reset_view = true
	phase = Phase.PLAY
	_t = 0
	_progress = 0
	_serial = sim.creatures[0].attack_serial
	_landed = []
	_landed.resize(route().size())
	_landed.fill(false)
	_combo_seen = false
	_first_hit = false
	banner = ""
	_refresh_caption()
	callouts.append([sim.creatures[0].pos + Vector2(0, -32), "YOUR TURN!" if from_demo else "TRY AGAIN",
		Color("ffd166")])


func _refresh_caption() -> void:
	var t := trial()
	var def: Dictionary = sim.creatures[0].def if sim != null else {}
	title = "TRIAL %d / %d  -  %s  -  %s%s" % [index + 1, trials.size(), String(def.get("name", "")).to_upper(),
		String(t["name"]), "   (demo)" if phase == Phase.DEMO else ""]
	caption_items = []
	for step in route():
		var mv: Dictionary = def.get("moves", {}).get(String(step[1]), {})
		var lbl := String(_labels.call(String(step[0]))) if _labels.is_valid() else ""
		var how := "hold " + lbl if held(step) and lbl != "" else ("hold" if held(step) else lbl)
		caption_items.append("%s%s%s" % [String(mv.get("name", step[1])), " (%s)" % how if how != "" else "",
			", sneak in" if sneak(step) else ""])
	caption_index = _progress if phase != Phase.DEMO else maxi(0, _demo.show if _demo != null else 0)


## Both sides' inputs this tick. `player_bits` is what the player is pressing.
func inputs(player_bits: int) -> PackedInt32Array:
	_t += 1
	match phase:
		Phase.DEMO:
			var out := _demo.inputs(sim)
			caption_index = clampi(_demo.show, 0, route().size())
			if _demo.finished:
				_reset_attempt()
			return out
		Phase.PLAY:
			var partner := 0
			# Counter trials: the partner keeps throwing jabs to Slip.
			if bool(trial().get("partner_jab", false)) and _progress == 0 and _t % 90 == 45:
				partner = SimDefs.IN_LIGHT
			return PackedInt32Array([player_bits, partner])
		Phase.RESULT:
			if _t >= RESULT_TICKS:
				if _result_clear:
					index = (index + 1) % trials.size()
					attempts = 0
					build()
					reset_view = true
				else:
					_reset_attempt()
	return PackedInt32Array([0, 0])


## Judges the attempt after each simulation step.
func after_step() -> void:
	if phase != Phase.PLAY:
		return
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	var r := route()
	# A move started: is it the next one in the route?
	if a.state == CreatureSim.State.ATTACK and a.attack_serial != _serial:
		_serial = a.attack_serial
		if _progress < r.size() and a.move_id == String(r[_progress][1]):
			_progress += 1
			if sneak(r[_progress - 1]):
				_landed[_progress - 1] = true  # nothing to hit: it only has to hide him
		elif _progress < r.size() and r[_progress].size() > 2 and a.move_id == String(r[_progress][2]):
			pass  # an allowed lead-in (Slip before its counter)
		else:
			_fail("Wrong move: %s" % String(a.move_def().get("name", a.move_id)))
			return
	for e in sim.events:
		if String(e["type"]) in ["hit", "grab"] and int(e.get("attacker", -1)) == 0 and _progress > 0:
			_landed[_progress - 1] = true
			if not bool(e.get("no_flinch", false)):  # a hit that doesn't stagger starts no combo
				_combo_seen = true
			# "ambush": the opening hit has to come out of hiding (the sim's ambush window is open).
			if not _first_hit and bool(trial().get("ambush", false)) and a.ambush_t <= 0:
				_fail("Spotted")
				return
			_first_hit = true
	# "ambush": the stealth ran out before the first hit.
	if bool(trial().get("ambush", false)) and not _first_hit and _progress > 0 			and a.stealth == 0 and a.ambush_t <= 0 and a.state != CreatureSim.State.ATTACK:
		_fail("Spotted")
		return
	caption_index = _progress
	if _progress == r.size() and _landed[r.size() - 1]:
		_clear()
		return
	# The combo dropped: the partner recovered before the route was done.
	if _combo_seen and d.combo_hits == 0 and not d.is_stunned() \
			and d.state != CreatureSim.State.KNOCKDOWN and d.state != CreatureSim.State.AIRBORNE:
		_fail("Dropped")
		return
	# The last move started but missed.
	if _progress > 0 and not _landed[_progress - 1] and a.state != CreatureSim.State.ATTACK:
		_fail("Missed")


func _fail(why: String) -> void:
	attempts += 1
	phase = Phase.RESULT
	_t = 0
	_result_clear = false
	banner = why.to_upper()
	callouts.append([sim.creatures[0].pos + Vector2(0, -32), why.to_upper(), Color("ff9a5a")])


func _clear() -> void:
	attempts += 1
	phase = Phase.RESULT
	_t = 0
	_result_clear = true
	banner = "CLEAR!"
	caption_index = route().size()
	callouts.append([sim.creatures[0].pos + Vector2(0, -32), "CLEAR!", Color("b6f28a")])


## Plays the demo again (F2).
func replay_demo() -> void:
	sim.restore(_initial)
	reset_view = true
	_start_demo()
	banner = ""
	_refresh_caption()


func skip(dir: int) -> void:
	index = (index + dir + trials.size()) % trials.size()
	attempts = 0
	build()
	reset_view = true
