class_name Showcase
extends RefCounted
## Scripted demos that show each fighter's whole kit, and how to answer the big moves.
##   godot --path . -- --showcase=cairn | culvert | counterplay
## Both fighters are driven by input bitmasks, exactly like players: each "press" step
## mashes its button until that move actually starts, so the combos shown are real
## inputs through the real rules. tests/test_showcase.gd plays every script headless.
##
## Steps (one at a time, in order):
##   wait t               do nothing for t ticks
##   press who bit move   mash `bit` until `who` starts `move` (aim: also hold toward the foe)
##   together bits        press [left, right] on the same tick
##   dodge who dir        roll "away" from, or "through", the other fighter
##   guard who            hold guard until an attack is blocked
##   approach who         walk until in jab range, lined up horizontally
##   until cond           wait for "settled" (both free) or "move:<side>:<id>"
##   place                fade out, repair the floor, put both back at the start, fade in
## "part" switches the caption line, "show" highlights an item on it.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const D := SimDefs.IN_DODGE
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE
const FADE := 14
const START_X := 210.0
const START_Y := 160.0

const SCRIPTS := {
	"cairn": {
		"left": "cairn", "right": "culvert", "energy": [100, 0], "gap": 2.0,
		"title": "CAIRN  -  FULL KIT",
		"captions": [
			["Slip counter", "Jab", "Jab", "Cross", "Hook", "Haymaker"],
			["Jab", "Jab", "Cross", "Haymaker", "Rockslide Rush", "Avalanche"],
		],
		"steps": [
			{"do": "wait", "t": 45, "part": 0},
			{"do": "together", "bits": [S1, L], "show": 0},
			{"do": "until", "cond": "move:0:slip_counter"},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 3},
			{"do": "press", "who": 0, "bit": L, "move": "light_4", "show": 4},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 30},
			{"do": "place", "part": 1},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 3},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 4},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 6},
		],
	},
	"culvert": {
		"left": "culvert", "right": "cairn", "energy": [100, 0], "gap": 2.0, "hp": [-1, 100],
		"title": "CULVERT  -  FULL KIT",
		"captions": [
			["Jab", "Jab", "Gulp"],
			["Jab", "Jab", "Hook", "Slam", "Runoff", "Storm Drain"],
		],
		"steps": [
			{"do": "wait", "t": 45, "part": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 2},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40, "show": 3},
			{"do": "place", "part": 1},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 3},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 4},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 6},
		],
	},
	"counterplay": {
		"left": "cairn", "right": "culvert", "energy": [0, 100], "gap": 2.0,
		"title": "COUNTERPLAY  -  READ THE WINDUP",
		"captions": [
			["Raw Gulp winds up red: unblockable", "Roll through it", "Punish: Jab, Jab, Cross, Rush"],
			["Storm Drain cut-in", "Dodge out during the freeze", "No damage taken"],
			["Raw Rush glows gold: blockable", "Guard it", "Punish: Jab, Jab, Gulp"],
		],
		"steps": [
			{"do": "wait", "t": 45, "part": 0},
			{"do": "press", "who": 1, "bit": S1, "move": "skill_1", "show": 0},
			{"do": "wait", "t": 12},  # about a human reaction time
			{"do": "dodge", "who": 0, "dir": "through", "show": 1},
			{"do": "until", "cond": "free:0"},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "aim": true, "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_2"},
			{"do": "press", "who": 0, "bit": L, "move": "light_3"},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2"},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40, "show": 3},
			{"do": "place", "part": 1, "gap": 22.0},
			{"do": "wait", "t": 25},
			{"do": "press", "who": 1, "bit": SU, "move": "surge", "show": 0},
			{"do": "wait", "t": 7},  # still inside the freeze
			{"do": "dodge", "who": 0, "dir": "away", "show": 1},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 50, "show": 2},
			{"do": "place", "part": 2, "gap": 34.0},
			{"do": "wait", "t": 25},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 0},
			{"do": "wait", "t": 9},
			{"do": "guard", "who": 1, "show": 1},
			{"do": "press", "who": 1, "bit": L, "move": "light_1", "show": 2},
			{"do": "press", "who": 1, "bit": L, "move": "light_2"},
			{"do": "press", "who": 1, "bit": S1, "move": "skill_1"},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 60, "show": 3},
		],
	},
}

var name := ""
var script_def: Dictionary
var step := 0
var finished := false
var failed := ""  ## set when a step couldn't complete, for tests
var part := 0
var show := -1
var fade := 0.0  ## 0..1 black overlay for scene changes

var _t := 0
var _serial := -1
var _phase := 0


static func names() -> Array:
	return SCRIPTS.keys()


func _init(p_name: String) -> void:
	name = p_name
	script_def = SCRIPTS[p_name]


## The match this showcase starts from: two fighters close together, centre stage.
func build() -> MatchSim:
	var sim := MatchFactory.versus(String(script_def["left"]), String(script_def["right"]))
	_place(sim, float(script_def.get("gap", 2.0)))
	var energy: Array = script_def.get("energy", [0, 0])
	var hp: Array = script_def.get("hp", [-1, -1])
	for i in 2:
		sim.creatures[i].energy = float(energy[i])
		if float(hp[i]) > 0.0:
			sim.creatures[i].hp = float(hp[i])
	return sim


func title() -> String:
	return String(script_def["title"])


func caption_items() -> Array:
	var caps: Array = script_def["captions"]
	return caps[clampi(part, 0, caps.size() - 1)]


## Inputs for both fighters this tick. Call once per simulation step.
func inputs(sim: MatchSim) -> PackedInt32Array:
	var out := PackedInt32Array([0, 0])
	var steps: Array = script_def["steps"]
	if finished or step >= steps.size():
		finished = true
		return out
	var s: Dictionary = steps[step]
	if s.has("part") and _t == 0 and _phase == 0:
		part = int(s["part"])
		show = -1
	if s.has("show"):
		show = int(s["show"])
	_t += 1
	var done := false
	match String(s["do"]):
		"wait":
			done = _t >= int(s["t"])
		"together":
			var b: Array = s["bits"]
			out[0] = int(b[0])
			out[1] = int(b[1])
			done = true
		"press":
			var who := int(s["who"])
			var c := sim.creatures[who]
			if _t == 1:
				_serial = c.attack_serial
			if c.attack_serial != _serial and c.move_id == String(s["move"]):
				done = true
			else:
				var bits := int(s["bit"]) if _t % 2 == 1 else 0
				if bool(s.get("aim", false)):
					bits |= _toward(sim, who)
				out[who] = bits
				if _t > 150:
					_fail("never started %s (in %s, state %d)" % [s["move"], c.move_id, c.state])
					done = true
		"dodge":
			var who := int(s["who"])
			var c := sim.creatures[who]
			var o := sim.creatures[1 - who]
			var away := (c.pos - o.pos).normalized()
			var dir := -away if String(s["dir"]) == "through" else away
			out[who] = D | SimDefs.bits_from_dir(dir)
			done = true
		"guard":
			var who := int(s["who"])
			out[who] = SimDefs.IN_GUARD
			done = sim.creatures[who].guard_hit > 0
			if _t > 120:
				_fail("nothing was blocked")
				done = true
		"approach":
			var who := int(s["who"])
			var c := sim.creatures[who]
			var o := sim.creatures[1 - who]
			var d := o.pos - c.pos
			var reach := c.radius + o.radius + 4.0
			if absf(d.y) > 3.0:
				out[who] = SimDefs.bits_from_dir(Vector2(0, signf(d.y)))
			elif absf(d.x) > reach:
				out[who] = SimDefs.bits_from_dir(Vector2(signf(d.x), 0))
			else:
				done = true
			if _t > 300:
				_fail("couldn't reach the other fighter")
				done = true
		"until":
			done = _check(sim, String(s["cond"]))
			if _t > 600:
				_fail("timed out waiting for " + String(s["cond"]))
				done = true
		"place":
			# Fade to black, reset positions, fade back in.
			if _t <= FADE:
				fade = float(_t) / FADE
			elif _t == FADE + 1:
				_place(sim, float(s.get("gap", script_def.get("gap", 2.0))))
				# Repair the floor so leftover pits don't swallow anyone.
				sim.terrain.cells.fill(0)
				sim.terrain.timers.fill(0)
				sim.terrain.version += 1
				fade = 1.0
			elif _t <= FADE * 2 + 1:
				fade = 1.0 - float(_t - FADE - 1) / FADE
			else:
				fade = 0.0
				done = true
	if done:
		step += 1
		_t = 0
		_phase = 0
		if step >= steps.size():
			finished = true
	return out


func _check(sim: MatchSim, cond: String) -> bool:
	if sim.hitstop > 0 and not cond.begins_with("move:"):
		return false
	if cond == "settled":
		return _free(sim.creatures[0]) and _free(sim.creatures[1])
	if cond.begins_with("free:"):
		return _free(sim.creatures[int(cond.get_slice(":", 1))])
	if cond.begins_with("move:"):
		var c := sim.creatures[int(cond.get_slice(":", 1))]
		return c.state == CreatureSim.State.ATTACK and c.move_id == cond.get_slice(":", 2)
	return true


## Not attacking, stunned, down, airborne, falling or rolling (a KO counts as done).
func _free(c: CreatureSim) -> bool:
	if c.state == CreatureSim.State.KO:
		return true
	return c.state in [CreatureSim.State.IDLE, CreatureSim.State.MOVE, CreatureSim.State.GUARD] \
		and c.invuln == 0


func _toward(sim: MatchSim, who: int) -> int:
	var d := sim.creatures[1 - who].pos - sim.creatures[who].pos
	return SimDefs.bits_from_dir(Vector2(signf(d.x), 0))


func _place(sim: MatchSim, gap: float) -> void:
	var a := sim.creatures[0]
	var b := sim.creatures[1]
	a.pos = Vector2(START_X, START_Y)
	b.pos = Vector2(START_X + a.radius + b.radius + gap, START_Y)
	a.facing = Vector2.RIGHT
	b.facing = Vector2.LEFT
	for c in [a, b]:
		c.knock_vel = Vector2.ZERO
		c.walk_vel = Vector2.ZERO


func _fail(msg: String) -> void:
	if failed == "":
		failed = "step %d: %s" % [step, msg]
	push_warning("Showcase %s: %s" % [name, failed])
