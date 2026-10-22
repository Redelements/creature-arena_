class_name CreatureSim
extends RefCounted
## One creature in the simulation: plain data plus rules. No nodes, no clock, no randomness.
## All tuning comes from the creature's JSON definition in data/creatures/.
##
## Moves have a type (light, heavy, skill, surge). Lights chain into the next light in
## their string; any move that has connected (hit or blocked) can cancel into a move of a
## higher rank. Damage bonuses and limits are applied by MatchSim when a hit lands.
##
## Windups: a move with "windup": N spends N extra frames winding up when it is thrown
## raw (from neutral or guard), so the other player has time to see it coming. Cancelled
## into from a move that connected, it starts at full speed, so combos are unaffected.
## A windup can be interrupted by getting hit, and doesn't move or re-aim the creature
## (charge moves keep charging and aiming through it).

enum State { IDLE, MOVE, ATTACK, DODGE, GUARD, HITSTUN, FALLING, KO, AIRBORNE, CRUMPLE, KNOCKDOWN }

const FALL_TICKS := 45
const FALL_DAMAGE := 8.0
const RESPAWN_INVULN := 40
const DUMMY_RESET_TICKS := 90
const FRICTION := 0.82
const AIR_FRICTION := 0.92
const WALL_BOUNCE_MIN := 2.0
const WALL_BOUNCE_STUN := 12
const EDGE_TOP := 6.0
const EDGE_BOTTOM := 3.0
const BUFFER_TICKS := 10
const MAX_ENERGY := 100.0
const BREAKAWAY_COST := 50.0
const BREAKAWAY_MIN_HITS := 3
const BREAKAWAY_INVULN := 30
const JUGGLE_MAX := 3
const JUGGLE_FLOAT := 16
const LAND_KNOCKDOWN := 24
const GETUP_INVULN := 12
const TAN_22_5 := 0.41421356237309503
## Walking speed while taunted (see a move's "taunt").
const TAUNT_SPEED := 0.6
## A taunted fighter is dragged this many pixels a tick toward its taunter (Bedrock),
## unless the taunt's "pull" says otherwise.
const TAUNT_PULL := 0.6
## Walking speed while strafing (facing the aim instead of the way you walk).
const STRAFE_SPEED := 0.85

## Everything that changes during a match, in a fixed order. snapshot()/restore() copy
## exactly these, which is what rollback netcode saves every frame. A test checks that
## every variable declared below is either listed here or in STATIC_FIELDS.
const STATE_FIELDS := [
	"pos", "walk_vel", "knock_vel", "facing", "hp", "stamina", "energy",
	"state", "state_t", "anim_t",
	"move_id", "attack_serial", "charging", "charge", "charge_ratio", "connected", "seg_hit",
	"cooldowns", "buffered", "buffer_t", "countered", "stack", "stack_t", "windup_left",
	"windup_total", "stun", "invuln", "flash", "guard_hit", "air_t", "air_total",
	"combo_hits", "combo_types", "combo_moves", "combo_bounced", "combo_damage", "juggles",
	"juggle_serials", "last_attacker", "dodge_dir", "prev_buttons", "dodge_buffer",
	"dodge_buffer_dir", "shield", "calm_t", "slow", "slow_mult", "taunt", "taunt_by", "taunt_pull",
	"reel_t", "reel_to", "reel_gap", "reel_speed", "vuln", "vuln_mult",
	"flip_t", "flip_total", "flip_from", "flip_to",
	"swallow_t", "swallow_by", "swallow_gap", "swallow_air",
	"poison", "poison_every", "poison_dmg", "poison_by", "poison_stacks", "poison_stack_dmg", "frenzy_t", "hit_streak", "streak_t", "stone",
	"blind", "whiff_serial", "ambush_serial", "root", "hitstop",
	"stealth", "haste", "haste_mult", "atk_buff", "atk_mult", "stone_ice", "covered",
	"block_lag", "punish_serial", "home_speed", "fall_chasm",
	"sheets", "sheet_t", "folded", "poison_look", "regen_wait",
]
## Set once when the creature is made and never changed by the simulation.
const STATIC_FIELDS := ["id", "team", "def", "is_dummy", "radius", "weight", "max_hp", "max_stamina",
	"dodge_cost", "air_mult", "speed_mult", "damage_mult", "floor_end"]

## Stamina rules every fighter shares: the dodge cost multiplier, a blocked hit's drain
## per move type, the regen pause after a block and the exhaustion delay at 0.
const STAMINA_PATH := "res://data/rules/stamina.json"
static var _stamina_rules := {}

const ACTION_BITS := [
	["surge", SimDefs.IN_SURGE],
	["skill_1", SimDefs.IN_SKILL1],
	["skill_2", SimDefs.IN_SKILL2],
	["heavy", SimDefs.IN_HEAVY],
	["light", SimDefs.IN_LIGHT],
]

var id: int
## Which side it fights for. Teammates can't hurt each other, and moves that pick a foe
## (taunts, gazes, homing, blinks, the CPU) skip them. Set to `id` when made, so a 1v1
## is two teams of one; TeamSim puts several creatures on each side.
var team: int
var def: Dictionary
var is_dummy := false

var pos := Vector2.ZERO
var walk_vel := Vector2.ZERO
var knock_vel := Vector2.ZERO
var facing := Vector2.RIGHT
var radius := 10.0
var weight := 1.0

var hp := 0.0
var max_hp := 0.0
var stamina := 0.0
var max_stamina := 0.0
var dodge_cost := 0.0  ## max_stamina × the dodge share (data/rules/stamina.json)
var regen_wait := 0  ## ticks before stamina regrows: a blocked hit's pause, or exhaustion at 0
var energy := 0.0

var state: State = State.IDLE
var state_t := 0  ## ticks spent in the current state
var anim_t := 0  ## ticks since spawn, for idle/run cycles

# Attacking
var move_id := ""
var attack_serial := 0
var charging := false
var charge := 0
var charge_ratio := 0.0
var connected := false
var seg_hit := {}
var cooldowns := {}
var buffered := ""
var buffer_t := 0
var countered := false
var stack := 0
var stack_t := 0
var windup_left := 0  ## raw-move windup frames still to go
var windup_total := 0  ## windup frames this attack started with (0 when cancelled into)

# Being hit
var stun := 0
var invuln := 0
var flash := 0
var guard_hit := 0
var air_t := 0
var air_total := 0
var combo_hits := 0
var combo_types := 0
var combo_moves := {}
var combo_bounced := false
var combo_damage := 0.0
var juggles := 0
var juggle_serials := {}
var last_attacker := -1

var dodge_dir := Vector2.RIGHT
var prev_buttons := 0
var dodge_buffer := 0  ## a dodge pressed during hitstop, kept until it can happen
## This creature's own freeze-frame on impact, on a crowded field (MatchSim.impact_stop):
## while it counts down only buffer_input runs, and the rest of the match goes on.
var hitstop := 0
var dodge_buffer_dir := Vector2.ZERO  ## the direction held when it was pressed

# Status
var shield := 0.0  ## absorbs damage before hp (Craglash's Stoneskin passive)
var calm_t := 0  ## ticks since this creature last took damage (or dealt it, with Stoneskin's `reset_on_deal`)
var slow := 0  ## ticks of slowed walking left
var slow_mult := 1.0
var taunt := 0  ## ticks left of being taunted by `taunt_by`
var taunt_by := -1
var taunt_pull := TAUNT_PULL  ## px/tick this taunt drags it in
var reel_t := 0  ## ticks left of being reeled in to `reel_to` (Gillbert's Cast Line)
var reel_to := -1
var reel_gap := 0.0
var reel_speed := 0.0
var vuln := 0  ## ticks left of taking extra damage (Chef Cerebro's Tenderize)
var vuln_mult := 1.0
var flip_t := 0  ## ticks left of being carried over the attacker's head (Flip Out)
var flip_total := 0
var flip_from := Vector2.ZERO
var flip_to := Vector2.ZERO
## Swallowed (Culvert's held Gulp): ticks left inside the attacker `swallow_by`, who
## carries it, hidden and untouchable; then it's pushed out `swallow_gap` px behind him
## and hops away for `swallow_air` ticks.
var swallow_t := 0
var swallow_by := -1
var swallow_gap := 0.0
var swallow_air := 0
var poison := 0  ## ticks of poison left (Hissy Fitz's Venom Spit)
var poison_every := 30  ## a pulse of damage every this many ticks
var poison_dmg := 0.0
var poison_by := -1
## Stacked poison (Hissy Fitz's Venom Frenzy): each stack adds `poison_stack_dmg` to
## every pulse, on top of `poison_dmg`. Gone when the poison runs out.
var poison_stacks := 0
var poison_stack_dmg := 0.0
## Ticks left of this creature's own Venom Frenzy (creature key "venom_frenzy"): its
## clean hits stack poison on whoever they hit.
var frenzy_t := 0
## Clean hits landed in a row (any hit counts, jabs too), and ticks left before the
## string is over (Venom Frenzy's "streak_gap" after each hit).
var hit_streak := 0
var streak_t := 0
var stone := 0  ## ticks left as a statue (Petrify Punch); the next clean hit shatters it
var blind := 0  ## ticks left blinded (Digby's Headlamp Flash): the next attack started misses
var whiff_serial := 0  ## the attack (attack_serial) that a blind made miss
## The attack that sprang out of stealth (Tiptoe): its hits land harder, by the
## creature's "ambush" multiplier. A sneak attack is the assassin's whole point.
var ambush_serial := 0
var root := 0  ## ticks left rooted in place (Cave-In): no walking, no dodging
## Ticks left invisible (Sneaky Pete's Tiptoe). Being hit ends it; so does an attack,
## but only as its strike comes out (or its projectile flies): the ambush out of
## stealth is the point, so the startup stays hidden.
var stealth := 0
## Match mutators (MatchSim.apply_mutators), fixed for the match: launches last
## longer, walking is faster, every hit lands harder.
var air_mult := 1.0
var speed_mult := 1.0
var damage_mult := 1.0
## Standing in brush (an arena piece): hidden from foes outside it, like stealth.
## Set by MatchSim after everyone has moved.
var covered := false
## The floor's far corner (this map's size), set by MatchSim when the creature joins.
var floor_end := SimDefs.floor_rect().end
var haste := 0  ## ticks left of walking faster
var haste_mult := 1.0
var atk_buff := 0  ## ticks left of dealing atk_mult x damage (Pickpocket: up for him, down for them)
var atk_mult := 1.0
var stone_ice := false  ## the statue is ice, not stone (Sno Mercy's Flavor Blast)
## A blocked combo ender (the third light) leaves the attacker open: extra recovery ticks
## on this attack, and no cancelling out of it (punish_serial is the attack's serial).
var block_lag := 0
var punish_serial := 0
var home_speed := 0.0  ## a homing dash's pace once its landing spot is locked
## The pit it is falling into is a chasm (decided when the fall starts: a hole can heal
## during the fall). Under `fall_ko` only a chasm is a knockout.
var fall_chasm := false
## Paper Stock (creature "sheets" {max, regen}): sheets in hand; one regrows every `regen`
## ticks while below `max`. Folds and `sheets_cost` moves spend them.
var sheets := 0
var sheet_t := 0
## Moves with a "fold" step that are folded and ready (move id -> true): the next press
## uses the craft; until then the press folds it (see _resolve_fold).
var folded := {}
## How the poison on this creature looks ("": venom; "bleed": a shuriken's cut), for views.
var poison_look := ""


## Whether `o` is on the other side (never itself).
func is_foe(o: CreatureSim) -> bool:
	return o != self and o.team != team


func _init(p_id: int, p_def: Dictionary, p_pos: Vector2, p_is_dummy := false) -> void:
	id = p_id
	team = p_id
	def = p_def.duplicate(true)
	pos = p_pos
	is_dummy = p_is_dummy
	max_hp = float(def.get("max_hp", 100))
	hp = max_hp
	max_stamina = float(def.get("stamina", 100))
	stamina = max_stamina
	dodge_cost = max_stamina * dodge_share(String(def.get("id", "")))
	radius = float(def.get("radius", 10))
	weight = float(def.get("weight", 1.0))
	for mid in moves().keys():
		_normalize_move(String(mid), moves()[mid])
	# Fold-then-use: a move with "fold" {anim, startup, recovery, cost} gets a "fold_<id>"
	# step of its own, played on the first press; the craft is ready once it completes.
	for mid in moves().keys():
		var fd: Dictionary = moves()[mid].get("fold", {})
		if fd.is_empty():
			continue
		var fm := {"type": "fold", "fold_of": String(mid), "name": "Fold " + String(moves()[mid].get("name", mid)),
			"anim": String(fd.get("anim", moves()[mid].get("anim", "idle"))),
			"startup": int(fd.get("startup", 12)), "active": 0, "recovery": int(fd.get("recovery", 6)),
			"mobile": float(fd.get("mobile", 0.0))}
		_normalize_move("fold_" + String(mid), fm)
		moves()["fold_" + String(mid)] = fm
	shield = float(def.get("stoneskin", {}).get("shield", 0.0))
	sheets = int(def.get("sheets", {}).get("max", 0))


## Fills in each move's type, hit segments and total length so the rest of the code
## can treat single-hit and multi-hit moves the same way.
static func _normalize_move(mid: String, mv: Dictionary) -> void:
	if not mv.has("type"):
		if mid.begins_with("light"):
			mv["type"] = "light"
		elif mid.begins_with("heavy"):
			mv["type"] = "heavy"
		elif mid.begins_with("surge"):
			mv["type"] = "surge"
		else:
			mv["type"] = "skill"
	var su := int(mv.get("startup", 0))
	var ac := int(mv.get("active", 0))
	var segs: Array = []
	if mv.has("hits"):
		for h in mv["hits"]:
			segs.append(h)
	elif ac > 0:
		segs.append({"at": su + 1, "active": ac})
	mv["_segs"] = segs
	if not mv.has("length"):
		mv["length"] = su + ac + int(mv.get("recovery", 0))


# ------------------------------------------------------------------ rollback state

func save_state() -> Dictionary:
	var d := {}
	for f in STATE_FIELDS:
		var v = get(f)
		d[f] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return d


func load_state(d: Dictionary) -> void:
	for f in STATE_FIELDS:
		var v = d[f]
		set(f, v.duplicate(true) if (v is Dictionary or v is Array) else v)


# ------------------------------------------------------------------ queries

func moves() -> Dictionary:
	return def.get("moves", {})


func move_def() -> Dictionary:
	return moves().get(move_id, {})


func move_type() -> String:
	return String(move_def().get("type", ""))


## A move stat, blended toward its "_charged" value by how long the heavy was held. A
## move held to a full charge takes its "hold" values instead, shape included (Runoff:
## a short shove tapped, the wave of water held).
func move_value(key: String, mv: Dictionary = {}) -> float:
	if mv.is_empty():
		mv = move_def()
	if charge_ratio >= 1.0 and mv.has("hold") and (mv["hold"] as Dictionary).has(key):
		return float(mv["hold"][key])
	var base := float(mv.get(key, 0.0))
	if mv.has(key + "_charged"):
		return lerpf(base, float(mv[key + "_charged"]), charge_ratio)
	return base


## Index of the hit segment active this tick, or -1.
func active_seg() -> int:
	if state != State.ATTACK or charging:
		return -1
	var segs: Array = move_def().get("_segs", [])
	for i in segs.size():
		var at := int(segs[i]["at"])
		if state_t >= at and state_t < at + int(segs[i]["active"]):
			return i
	return -1


func is_active() -> bool:
	return active_seg() >= 0


## A hit parameter for the given segment: the segment's own value, else the move's.
func seg_value(seg: int, key: String) -> float:
	var segs: Array = move_def().get("_segs", [])
	if seg >= 0 and seg < segs.size() and segs[seg].has(key):
		return float(segs[seg][key])
	return move_value(key)


func hit_center(seg: int = -2) -> Vector2:
	if seg == -2:
		seg = active_seg()
	return pos + facing * seg_value(seg, "reach")


func hit_radius(seg: int = -2) -> float:
	if seg == -2:
		seg = active_seg()
	return seg_value(seg, "hit_radius")


## A foe (not KO) is inside the current move's first strike with its near edge already
## at the strike's centre or closer: the lunge holds its ground. So a lunge closes to the
## move's sweet spot (a gap of `reach - radius` between the bodies) and no further, and
## still follows a foe that the last hit knocked back.
func _foe_in_strike(sim: MatchSim) -> bool:
	var c := hit_center(0)
	var r := hit_radius(0)
	var reach := seg_value(0, "reach")
	for o in sim.creatures:
		if not is_foe(o) or o.state == State.KO:
			continue
		if c.distance_to(o.pos) <= r + o.radius and pos.distance_to(o.pos) - o.radius <= reach:
			return true
	return false


## Everything MatchSim needs to resolve one hit from segment `seg` of the current move.
## Hit values read per segment (0 when the move leaves one out).
const HIT_SEG_KEYS := ["damage", "knockback", "hitstun", "hitstop", "launch", "crumple",
	"knockdown", "slow_ticks", "juggle_float", "pull", "reel", "reel_speed", "vuln_ticks",
	"flip", "swallow", "poison_ticks", "poison_damage", "poison_every", "petrify",
	"blind_ticks", "root_ticks", "steal_ticks", "freeze_ticks"]
## Hit flags read from the move itself.
const HIT_FLAG_KEYS := ["guard_break", "grab", "grab_air", "juggle", "no_flinch"]


func hit_params(seg: int) -> Dictionary:
	var mv := move_def()
	var out := _hit_base(mv, move_id, String(mv["type"]))
	for k in HIT_SEG_KEYS:
		out[k] = seg_value(seg, k)
	# A move held to a full charge can hit differently ("hold": {...} overrides any of the
	# values above): Culvert's Gulp, a hook when tapped, a swallow when held.
	if mv.has("hold") and charge_ratio >= 1.0:
		for k in mv["hold"]:
			out[k] = mv["hold"][k]
	return out


## The hit of a ramming dodge ("dodge.ram"): one segment, its values on the ram block.
func ram_hit_params(ram: Dictionary) -> Dictionary:
	var out := _hit_base(ram, "ram", String(ram.get("type", "light")))
	for k in HIT_SEG_KEYS:
		out[k] = float(ram.get(k, 0.0))
	return out


func _hit_base(mv: Dictionary, mid: String, type: String) -> Dictionary:
	var out := {"attacker": id, "move_id": mid, "type": type, "serial": attack_serial,
		"stack_bonus": float(mv.get("stack_bonus", 0.0)), "slow_mult": float(mv.get("slow_mult", 1.0)),
		"vuln_mult": float(mv.get("vuln_mult", 1.0)), "steal": float(mv.get("steal", 0.0)),
		"cone": float(mv.get("cone", 0.0)), "poison_look": String(mv.get("poison_look", ""))}
	for k in HIT_FLAG_KEYS:
		out[k] = bool(mv.get(k, false))
	return out


func is_invulnerable() -> bool:
	if invuln > 0 or state == State.KNOCKDOWN or is_leaping():
		return true
	if state == State.DODGE:
		var dg: Dictionary = def["dodge"]
		return state_t >= int(dg["iframes_start"]) and state_t <= int(dg["iframes_end"])
	return false


## Bedrock-style armor: hits only chip it, and nothing moves it. Grabs still work.
func is_armored() -> bool:
	if state != State.ATTACK or windup_left > 0:
		return false
	var ar: Dictionary = move_def().get("armor", {})
	return not ar.is_empty() and state_t >= int(ar["from"]) and state_t <= int(ar["to"])


## Takes damage, the shield soaking it up first. Returns what reached hp.
func take_damage(amount: float, sim: MatchSim) -> float:
	calm_t = 0
	amount *= damage_mult
	if shield > 0.0 and amount > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
		if shield <= 0.0:
			shield = 0.0
			sim.emit_event("shield_break", pos, 1.0, {"who": id})
	hp -= amount
	return amount


## This creature's hit dealt damage (clean, chip or on armor). Stoneskin with
## `reset_on_deal` counts that as combat too: the shield only grows back out of it.
func dealt_damage() -> void:
	if bool(def.get("stoneskin", {}).get("reset_on_deal", false)):
		calm_t = 0


func walk_speed() -> float:
	if root > 0:
		return 0.0
	var s := float(def["speed"]) * speed_mult
	if slow > 0:
		s *= slow_mult
	if taunt > 0:
		s *= TAUNT_SPEED
	if haste > 0:
		s *= haste_mult
	return s


func can_be_hit() -> bool:
	return state != State.FALLING and state != State.KO and not is_invulnerable()


func is_airborne() -> bool:
	return state == State.AIRBORNE


func is_stunned() -> bool:
	return state == State.HITSTUN or state == State.CRUMPLE or state == State.AIRBORNE


## Whether this creature pushes and gets pushed by other bodies.
func is_solid() -> bool:
	return not (state in [State.FALLING, State.KO, State.DODGE, State.AIRBORNE, State.KNOCKDOWN]) \
		and not is_leaping() and not _ghosting()


## Through fences: a ghost dash, or a dash or dodge with "passes": ["fence"].
func passes_fences() -> bool:
	if _ghosting():
		return true
	if state == State.ATTACK and windup_left <= 0:
		var dash: Dictionary = move_def().get("dash", {})
		return "fence" in (dash.get("passes", []) as Array) \
			and state_t >= int(dash["from"]) and state_t <= int(dash["to"])
	if state == State.DODGE:
		return "fence" in ((def["dodge"] as Dictionary).get("passes", []) as Array)
	return false


## A charge with "breaks": ["wall"] smashes the rubble wall cells its body would reach
## on this step, so the step goes through instead of stopping.
func _smash_ahead(sim: MatchSim, breaks: Array, delta: Vector2) -> void:
	if not ("wall" in breaks or "rubble" in breaks):
		return
	var at := pos + delta
	var any := false
	for c in sim.terrain.cells_touching(at, radius + 1.0, TerrainGrid.WALL):
		if sim.terrain.smash(c):
			any = true
	if any:
		sim.emit_event("smash", at, 1.0, {"who": id})


## A dash or roll flattens the brush its body passes through (it grows back).
func _trample(sim: MatchSim) -> void:
	for c in sim.terrain.cells_touching(pos, radius * 0.7, TerrainGrid.BRUSH):
		sim.terrain.flatten(c)


## The dash speed here: faster through shallows for the moves made for them.
func _dash_speed(dash: Dictionary, sim: MatchSim) -> float:
	var spd := float(dash["speed"])
	if sim.terrain.get_cell(sim.terrain.world_to_cell(pos)) == TerrainGrid.SHALLOWS:
		spd *= float(dash.get("shallows_mult", 1.0))
	return spd


## Walking speed on this ground: shallows and brush slow it unless he "wades".
func floor_mult(sim: MatchSim) -> float:
	var v := sim.terrain.get_cell(sim.terrain.world_to_cell(pos))
	if v == TerrainGrid.SHALLOWS and bool(def.get("wades", false)):
		return 1.0
	return TerrainGrid.walk_mult_of(v)


## Slipping through bodies during a "ghost" dash (Pickpocket dashes past the foe).
func _ghosting() -> bool:
	if state != State.ATTACK or windup_left > 0:
		return false
	var dash: Dictionary = move_def().get("dash", {})
	return bool(dash.get("ghost", false)) and state_t >= int(dash["from"]) and state_t <= int(dash["to"])


## High in the air during a move's "leap" window (Gillbert's Surge): out of reach of
## every hit, passing over bodies and pits.
func is_leaping() -> bool:
	if state != State.ATTACK or windup_left > 0:
		return false
	var lp: Dictionary = move_def().get("leap", {})
	return not lp.is_empty() and state_t >= int(lp["from"]) and state_t <= int(lp["to"])


func is_full_charge() -> bool:
	return charging and charge >= int(move_def().get("charge_max", 1))


func can_use(mid: String) -> bool:
	var mv: Dictionary = moves().get(mid, {})
	if mv.is_empty():
		return false
	if needs_fold(mid):
		# Not folded yet: this press folds it, which needs the sheets for it.
		return sheets >= int(mv["fold"].get("cost", 1)) and int(cooldowns.get(mid, 0)) <= 0
	if int(cooldowns.get(mid, 0)) > 0:
		return false
	if sheets < int(mv.get("sheets_cost", 0)):
		return false
	return energy >= float(mv.get("energy_cost", 0.0))


## A move with a fold step that isn't folded yet: pressing it folds instead.
func needs_fold(mid: String) -> bool:
	return moves().get(mid, {}).has("fold") and not folded.has(mid)


## What a press of `mid` starts: its fold step while the craft isn't folded, else itself.
func _resolve_fold(mid: String) -> String:
	return "fold_" + mid if needs_fold(mid) else mid


func cooldown_ratio(mid: String) -> float:
	var mv: Dictionary = moves().get(mid, {})
	var total := float(mv.get("cooldown", 0))
	if total <= 0.0:
		return 0.0
	return float(cooldowns.get(mid, 0)) / total


func is_winding_up() -> bool:
	return state == State.ATTACK and windup_left > 0


## Folding a craft and not done yet (a hit now cancels it, and no sheet is spent).
func is_folding() -> bool:
	return state == State.ATTACK and move_def().has("fold_of") and state_t < int(move_def().get("startup", 0))


## Ticks since the current attack began, counting its windup. A charge held in place
## isn't counted (state_t restarts when the charge is released).
func attack_elapsed() -> int:
	return state_t + windup_total - windup_left


func in_counter_window() -> bool:
	if state != State.ATTACK or countered:
		return false
	var c: Dictionary = move_def().get("counter", {})
	return not c.is_empty() and state_t >= int(c["from"]) and state_t <= int(c["to"])


## Height above the ground while launched, for drawing.
func air_height() -> float:
	if state != State.AIRBORNE or air_total <= 0:
		return 0.0
	var t := float(air_t)
	var tt := float(air_total)
	var peak := clampf(tt * 0.6, 10.0, 28.0)
	return maxf(0.0, 4.0 * peak * t * (tt - t) / (tt * tt))


## How far a move reaches from the body's centre: the strike's reach and radius, or how
## far its projectile flies. Used by the mouse auto-attack and the CPU to pick range.
func move_range(mid: String) -> float:
	var mv: Dictionary = moves().get(mid, {})
	if mv.has("projectile"):
		var p: Dictionary = mv["projectile"]
		if bool(p.get("lob", false)):
			return float(p.get("offset", 16)) + float(p["range"]) + float(p.get("burst", 0))
		return float(p.get("offset", 16)) + float(p["speed"]) * float(p["life"]) + float(p.get("radius", 0))
	return float(mv.get("reach", 14)) + float(mv.get("hit_radius", 9))


func move_rank(mid: String) -> int:
	var mv: Dictionary = moves().get(mid, {})
	return int(SimDefs.TYPE_RANK.get(String(mv.get("type", "")), 0))


func action_move(action: String) -> String:
	if action == "light":
		return "light_1"
	return action


# ------------------------------------------------------------------ per-tick update

## Called instead of step() during hitstop, so button presses aren't lost.
func buffer_input(buttons: int, sim: MatchSim) -> void:
	var pressed := buttons & ~prev_buttons
	prev_buttons = buttons
	if is_stunned() and _wants_breakaway(buttons, pressed):
		sim.hitstop = 0
		hitstop = 0
		sim.breakaway(self)
		return
	_buffer_presses(pressed)
	# Without this, a dodge pressed during a freeze (like a Surge's) would be lost.
	if pressed & SimDefs.IN_DODGE:
		dodge_buffer = BUFFER_TICKS
		dodge_buffer_dir = SimDefs.move_from_bits(buttons)


func _buffer_presses(pressed: int) -> void:
	for a in ACTION_BITS:
		if pressed & int(a[1]):
			buffered = String(a[0])
			buffer_t = BUFFER_TICKS
			return


func step(buttons: int, sim: MatchSim) -> void:
	var pressed := buttons & ~prev_buttons
	prev_buttons = buttons
	_buffer_presses(pressed)
	if pressed & SimDefs.IN_DODGE and int(cooldowns.get("dodge", 0)) > 0:
		# Pressed a moment before the blink has recharged: it comes out when it's ready.
		dodge_buffer = BUFFER_TICKS
		dodge_buffer_dir = SimDefs.move_from_bits(buttons)
	anim_t += 1
	state_t += 1
	if invuln > 0:
		invuln -= 1
	if flash > 0:
		flash -= 1
	if guard_hit > 0:
		guard_hit -= 1
	for k in cooldowns.keys():
		if int(cooldowns[k]) > 0:
			cooldowns[k] = int(cooldowns[k]) - 1
	if stack > 0:
		stack_t -= 1
		if stack_t <= 0:
			stack = 0
	_regrow_sheets(sim)
	if regen_wait > 0:
		regen_wait -= 1
	elif not (state in [State.DODGE, State.GUARD, State.KO]):
		stamina = minf(max_stamina, stamina + float(def.get("stamina_regen", 0.5)))
	_tick_status(sim)

	if is_stunned() and _wants_breakaway(buttons, pressed):
		sim.breakaway(self)
	else:
		var dir := SimDefs.move_from_bits(buttons)  # walking: 360 degrees from a stick
		var aim := SimDefs.aim_from_bits(buttons)  # attacks: the exact aim when one is sent
		match state:
			State.IDLE, State.MOVE:
				_update_free(buttons, pressed, dir, aim, sim)
			State.ATTACK:
				_update_attack(buttons, aim, sim)
			State.DODGE:
				_update_dodge(sim)
			State.GUARD:
				_update_guard(buttons, pressed, dir, aim, sim)
			State.HITSTUN, State.CRUMPLE:
				stun -= 1
				if stun <= 0:
					_recover()
			State.AIRBORNE:
				air_t += 1
				if air_t >= air_total:
					_land(sim)
			State.KNOCKDOWN:
				stun -= 1
				if stun <= 0:
					invuln = GETUP_INVULN
					_recover()
			State.FALLING:
				if state_t >= FALL_TICKS:
					_land_from_fall(sim)
			State.KO:
				if is_dummy and state_t >= DUMMY_RESET_TICKS:
					hp = max_hp
					stamina = max_stamina
					regen_wait = 0
					reset_combo()
					invuln = 20
					_set_state(State.IDLE)
	if reel_t > 0:
		_reel_step(sim)
	if flip_t > 0:
		_flip_step()
	_apply_knockback(sim)

	if buffer_t > 0:
		buffer_t -= 1
		if buffer_t == 0:
			buffered = ""
	if dodge_buffer > 0:
		dodge_buffer -= 1


func _tick_status(sim: MatchSim) -> void:
	# Taunted (Bedrock): dragged in toward the taunter while free on its feet.
	var tt := taunter(sim)
	if tt != null and (state == State.IDLE or state == State.MOVE or state == State.GUARD):
		var to := tt.pos - pos
		if to.length() > float(radius + tt.radius) + 6.0:
			_move(to.normalized() * taunt_pull, sim, true)
	if slow > 0:
		slow -= 1
	if taunt > 0:
		taunt -= 1
	if vuln > 0:
		vuln -= 1
	if blind > 0:
		blind -= 1
	if root > 0:
		root -= 1
	if stealth > 0:
		stealth -= 1
	if haste > 0:
		haste -= 1
	if atk_buff > 0:
		atk_buff -= 1
		if atk_buff == 0:
			atk_mult = 1.0
	if stone > 0:
		stone -= 1
		if state != State.CRUMPLE:
			stone = 0  # back on its feet: the stone has crumbled away
	# Poison: a pulse of damage every so often. It isn't part of any combo.
	if frenzy_t > 0:
		frenzy_t -= 1
	if streak_t > 0:
		streak_t -= 1
		if streak_t == 0:
			hit_streak = 0
	if poison > 0 and state != State.KO:
		poison -= 1
		if poison % maxi(1, poison_every) == 0:
			var dealt := take_damage(poison_dmg + poison_stacks * poison_stack_dmg, sim)
			flash = maxi(flash, 2)
			sim.emit_event("poison", pos, dealt, {"who": id, "by": poison_by, "stacks": poison_stacks, "look": poison_look})
			check_ko(sim)
		if poison <= 0:
			poison_stacks = 0
			poison_dmg = 0.0
			poison_look = ""
	# Stoneskin: a while without taking damage (nor dealing it, with `reset_on_deal`)
	# grows the shield back.
	var skin: Dictionary = def.get("stoneskin", {})
	if not skin.is_empty() and state != State.KO:
		calm_t += 1
		var full := float(skin["shield"])
		if calm_t >= int(skin["delay"]) and shield < full:
			shield = full
			sim.emit_event("shield_up", pos, full, {"who": id})


## Paper Stock: one sheet regrows every `regen` ticks while below `max` (not while down).
func _regrow_sheets(sim: MatchSim) -> void:
	var sh: Dictionary = def.get("sheets", {})
	if sh.is_empty():
		return
	if sheets >= int(sh["max"]) or state == State.KO:
		sheet_t = 0
		return
	sheet_t += 1
	if sheet_t >= int(sh["regen"]):
		sheet_t = 0
		sheets += 1
		sim.emit_event("sheet", pos, float(sheets), {"who": id})


## The creature taunting this one, if any.
func taunter(sim: MatchSim) -> CreatureSim:
	if taunt <= 0 or taunt_by < 0 or taunt_by >= sim.creatures.size():
		return null
	var t := sim.creatures[taunt_by]
	return null if t.state == State.KO else t


func _wants_breakaway(buttons: int, pressed: int) -> bool:
	var both := SimDefs.IN_GUARD | SimDefs.IN_DODGE
	return (buttons & both) == both and (pressed & both) != 0 \
		and combo_hits >= BREAKAWAY_MIN_HITS and energy >= BREAKAWAY_COST


func _update_free(buttons: int, pressed: int, dir: Vector2, aim: Vector2, sim: MatchSim) -> void:
	var dg: Dictionary = def["dodge"]
	if ((pressed & SimDefs.IN_DODGE) or dodge_buffer > 0) and can_dodge():
		_start_dodge(dir, sim)
		return
	if _try_start_buffered(aim, sim):
		return
	if buttons & SimDefs.IN_GUARD and can_guard():
		walk_vel = Vector2.ZERO
		_set_state(State.GUARD)
		return

	# Strafing (twin-stick right stick held): face the aim and walk any way, a bit slower.
	var strafing := (buttons & SimDefs.IN_STRAFE) != 0 and (buttons & SimDefs.IN_AIM) != 0
	var speed := walk_speed() * (STRAFE_SPEED if strafing else 1.0) * floor_mult(sim)
	walk_vel = walk_vel.move_toward(dir * speed, float(def["accel"]))
	if strafing:
		facing = aim
	if dir != Vector2.ZERO:
		if not strafing:
			facing = dir
		if state != State.MOVE:
			_set_state(State.MOVE)
	elif walk_vel.length() < 0.05 and state != State.IDLE:
		walk_vel = Vector2.ZERO
		_set_state(State.IDLE)
	_move(walk_vel, sim, true)


## Enough stamina, not rooted, and (for a dodge with a "cooldown", like Chef Cerebro's
## teleport) not still recharging from the last one.
func can_dodge() -> bool:
	return stamina >= dodge_cost and root <= 0 and int(cooldowns.get("dodge", 0)) <= 0


## Stamina to block with. Exhausted (at 0) a guard can't start.
func can_guard() -> bool:
	return stamina > 0.0


## Out of stamina: no guard, and regen waits out the exhaustion delay.
func is_exhausted() -> bool:
	return stamina <= 0.0


## Spends stamina. Reaching 0 exhausts the creature: regen waits `exhaust_delay_seconds`,
## replacing any shorter pause a blocked hit started.
func spend_stamina(amount: float) -> void:
	stamina -= amount
	if stamina <= 0.0:
		stamina = 0.0
		regen_wait = stamina_ticks("exhaust_delay_seconds", 2.0)


## A blocked hit holds regen off for `block_regen_pause_seconds`, restarted by every
## blocked hit; an exhaustion delay already running is left as it is (they don't stack).
func pause_regen_for_block() -> void:
	regen_wait = maxi(regen_wait, stamina_ticks("block_regen_pause_seconds", 0.5))


## The guard drops: stamina ran out under a hit, which then lands clean.
func drop_guard() -> void:
	stun = 0
	_set_state(State.IDLE)


static func stamina_rules() -> Dictionary:
	if _stamina_rules.is_empty():
		var f := FileAccess.open(STAMINA_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_stamina_rules = d if d is Dictionary else {}
	return _stamina_rules


## The share of the stamina bar a dodge costs fighter `fid`: its own entry in
## dodge_cost_share_by_fighter, or dodge_cost_share.
static func dodge_share(fid: String) -> float:
	var r := stamina_rules()
	return float((r.get("dodge_cost_share_by_fighter", {}) as Dictionary).get(fid, r.get("dodge_cost_share", 0.6)))


## A time from the stamina rules, in seconds there, as ticks.
static func stamina_ticks(key: String, default_seconds: float) -> int:
	return roundi(float(stamina_rules().get(key, default_seconds)) * SimDefs.TICK_RATE)


## How much of the dodge's cooldown is left, 0 (ready) to 1 (just used).
func dodge_cooldown_ratio() -> float:
	var total := float(def["dodge"].get("cooldown", 0))
	return float(cooldowns.get("dodge", 0)) / total if total > 0.0 else 0.0


func _start_dodge(dir: Vector2, sim: MatchSim) -> void:
	var dg: Dictionary = def["dodge"]
	spend_stamina(dodge_cost)
	if int(dg.get("cooldown", 0)) > 0:
		cooldowns["dodge"] = int(dg["cooldown"])
	if dg.has("ram"):
		# A ramming dodge is an attack of its own: a fresh serial (one hit per foe per
		# dash, stale if it repeats in a combo) and a clean hit list.
		attack_serial += 1
		seg_hit = {}
	if dir == Vector2.ZERO and dodge_buffer > 0:
		dir = dodge_buffer_dir
	dodge_buffer = 0
	dodge_dir = dir if dir != Vector2.ZERO else facing
	walk_vel = Vector2.ZERO
	_set_state(State.DODGE)
	sim.emit_event("dodge", pos, 0.0)


## Starts the buffered attack from a neutral state, if it's usable.
func _try_start_buffered(dir: Vector2, sim: MatchSim) -> bool:
	if buffered == "":
		return false
	var mid := action_move(buffered)
	if not can_use(mid):
		return false
	if dir != Vector2.ZERO:
		facing = dir
	facing = _taunt_aim(facing, sim)
	_start_attack(mid, sim, true)
	return true


## Where an attack aimed `dir` actually goes: a taunted creature swings at its taunter.
func _taunt_aim(dir: Vector2, sim: MatchSim) -> Vector2:
	var t := taunter(sim)
	if t != null and t.pos.distance_squared_to(pos) > 0.0001:
		return (t.pos - pos).normalized()  # straight at it, any angle
	return dir


func _start_attack(mid: String, sim: MatchSim, raw := false) -> void:
	mid = _resolve_fold(mid)
	move_id = mid
	attack_serial += 1
	block_lag = 0
	if blind > 0:
		# Blinded (Headlamp Flash): this attack can't find its target.
		whiff_serial = attack_serial
		blind = 0
	seg_hit.clear()
	connected = false
	countered = false
	charge = 0
	charge_ratio = 0.0
	buffered = ""
	buffer_t = 0
	var mv := move_def()
	if float(mv.get("mobile", 0.0)) <= 0.0:
		walk_vel = Vector2.ZERO  # a "mobile" move keeps its glide going
	charging = mv.has("charge_max")
	if mv.has("aim"):
		_aim(float(mv["aim"]), sim)
	# Self buffs as the move starts (Tiptoe: invisible and quicker). Any other attack
	# gives the stealth away once its strike comes out (see _reveal).
	var buff: Dictionary = mv.get("self", {})
	if buff.has("stealth"):
		stealth = maxi(stealth, int(buff["stealth"]))
		sim.emit_event("stealth", pos, float(buff["stealth"]), {"who": id})
	if buff.has("haste"):
		haste = maxi(haste, int(buff["haste"]))
		haste_mult = float(buff.get("haste_mult", 1.4))
	if mv.has("cooldown"):
		cooldowns[mid] = int(mv["cooldown"])
	if mv.has("energy_cost"):
		energy -= float(mv["energy_cost"])
	if mv.has("fold"):
		folded.erase(mid)  # the craft is used up: it has to be folded again
	if mv.has("sheets_cost"):
		sheets = maxi(0, sheets - int(mv["sheets_cost"]))
	_set_state(State.ATTACK)
	var surge := String(mv["type"]) == "surge"
	windup_total = int(mv.get("windup", 0)) if raw else 0
	if surge and raw and not sim.freeze_all:
		# A crowded field doesn't stop for a Surge: the caster winds up in its place.
		windup_total = maxi(windup_total, int(mv.get("crowd_windup", MatchSim.SURGE_CROWD_WINDUP)))
	windup_left = windup_total
	if windup_total > 0:
		sim.emit_event("windup", pos, float(windup_total),
			{"who": id, "move": mid, "tell": String(mv.get("tell", "strong"))})
	if surge:
		if sim.freeze_all:
			sim.hitstop = maxi(sim.hitstop, int(mv.get("freeze", 18)))
		sim.emit_event("surge", pos, 1.0, {"who": id, "name": String(mv.get("name", "SURGE")),
			"freeze": sim.freeze_all})


func _update_attack(buttons: int, dir: Vector2, sim: MatchSim) -> void:
	var mv := move_def()
	if windup_left > 0:
		windup_left -= 1
		state_t = 0
		if charging:
			if dir != Vector2.ZERO:
				facing = dir
			if (buttons & _charge_bit()) and charge < int(mv.get("charge_max", 0)):
				charge += 1
		return
	if charging:
		if dir != Vector2.ZERO:
			facing = dir  # aim while charging
		if (buttons & _charge_bit()) and charge < int(mv.get("charge_max", 0)):
			charge += 1
			state_t = 0
			return
		charging = false
		charge_ratio = float(charge) / float(maxi(int(mv.get("charge_max", 1)), 1))
		if mv.has("aim"):
			_aim(float(mv["aim"]), sim)  # released: snap to a foe roughly where it was aimed

	var t := state_t
	var su := int(mv.get("startup", 0))

	# A fold step: the sheet is spent and the craft ready the moment the fold is done (a
	# hit before that cancels it, so nothing is lost).
	if mv.has("fold_of") and t == su:
		var of := String(mv["fold_of"])
		sheets = maxi(0, sheets - int(moves()[of]["fold"].get("cost", 1)))
		folded[of] = true
		sim.emit_event("fold", pos, float(sheets), {"who": id, "craft": of})

	# Steering: until the strike comes out, the held direction re-aims the move (8-way,
	# like walking). Lights steer through their whole startup by default; other moves only
	# with "aim_frames", so a raw big move stays committed to the way its tell pointed.
	var aim_until := int(mv.get("aim_frames", su if String(mv["type"]) == "light" else 0))
	if t <= aim_until and dir != Vector2.ZERO and not connected:
		facing = _taunt_aim(dir, sim)

	# Movement during the move: a short lunge before it hits, or a dash. The lunge only
	# closes distance: with a foe already inside the strike it holds its ground, so a
	# string keeps its spacing instead of walking into the target (a whiff still steps in).
	var lunge := float(mv.get("lunge", 0.0))
	if t <= su and lunge > 0.0 and not _foe_in_strike(sim):
		_move(facing * lunge, sim, true)
	# "mobile": he keeps walking (at this share of his speed) while the move plays out,
	# whichever way it's thrown: Chef Cerebro's telekinetic throws, run-and-gun.
	var mob := float(mv.get("mobile", 0.0))
	if mob > 0.0:
		var walk := SimDefs.move_from_bits(buttons)
		walk_vel = walk_vel.move_toward(walk * walk_speed() * mob, float(def["accel"]))
		_move(walk_vel, sim, true)
	var dash: Dictionary = mv.get("dash", {})
	if not dash.is_empty() and t >= int(dash["from"]) and t <= int(dash["to"]) and dash.has("home"):
		_home(dash, t, sim)
	elif not dash.is_empty() and t >= int(dash["from"]) and t <= int(dash["to"]) \
			and (not connected or bool(dash.get("ghost", false))):  # a ghost dash runs on past
		# A steerable dash (Burrow): the stick turns it a little each tick.
		if float(dash.get("steer", 0.0)) > 0.0 and dir != Vector2.ZERO:
			facing = (facing + dir * float(dash["steer"])).normalized()
		var step_v := facing * _dash_speed(dash, sim)
		if dash.has("breaks"):
			_smash_ahead(sim, dash["breaks"], step_v)
		_move(step_v, sim, not is_leaping())  # a leap sails over pits
		_trample(sim)

	# One-off effects at the first active tick.
	var segs: Array = mv["_segs"]
	var first_at := int(segs[0]["at"]) if segs.size() > 0 else su + 1
	if t >= first_at and not mv.get("self", {}).has("stealth"):
		_reveal(sim)  # the ambush is sprung: visible again
	if t == first_at:
		if mv.has("terrain_radius") or mv.has("terrain_rect"):
			_slam(mv, sim)
		if mv.has("terrain_ring"):
			var r: Dictionary = mv["terrain_ring"]
			sim.terrain.damage_ring(pos, float(r["inner"]), float(r["outer"]), _terrain_heal(mv))
			sim.emit_event("slam", pos, 1.0)
		if mv.has("terrain_crack"):
			# Cracks the floor without opening holes (Root Eruption's roots break the surface).
			sim.terrain.crack_circle(pos + facing * float(mv.get("reach", 0)), float(mv["terrain_crack"]))
	if mv.has("projectile") and t > su:
		# One projectile at the first active tick, or a "volley" of them (Knife Flurry):
		# "count" in a row, one every "every" ticks.
		var vol: Dictionary = mv["projectile"].get("volley", {})
		var every := maxi(1, int(vol.get("every", 1)))
		var k := t - su - 1
		if k % every == 0 and k / every < int(vol.get("count", 1)):
			if mv.has("aim"):
				_aim(float(mv["aim"]), sim)  # each throw of a volley tracks the foe
			sim.spawn_projectile(self, mv, k / every == int(vol.get("count", 1)) - 1)

	# A zone left on the floor (Syrup Slick).
	var zn: Dictionary = mv.get("zone", {})
	if not zn.is_empty() and t == int(zn.get("at", su)):
		sim.add_zone(self, pos, zn)

	# A vanish and reappear behind the foe (The Big Heist).
	var bl: Dictionary = mv.get("blink", {})
	if not bl.is_empty() and t == int(bl["at"]):
		_blink(bl, sim)

	# A gaze (Stone Gaze): every few ticks, slow whoever is in front and looking back.
	var gaze: Dictionary = mv.get("gaze", {})
	if not gaze.is_empty() and t >= int(gaze["from"]) and t <= int(gaze["to"]) \
			and (t - int(gaze["from"])) % maxi(1, int(gaze.get("every", 10))) == 0:
		_gaze(gaze, sim)
	if not gaze.is_empty() and buffered != "" and t >= int(gaze.get("release_from", 9999)) and t <= int(gaze["to"]):
		var g_rel := action_move(buffered)
		if g_rel != move_id and can_use(g_rel):
			if dir != Vector2.ZERO:
				facing = dir
			_start_attack(g_rel, sim)
			return

	# Armored stances (Bedrock): taunt as the armor sets, and let any attack answer
	# straight out of it once `release_from` is reached.
	var armor: Dictionary = mv.get("armor", {})
	if not armor.is_empty():
		if t == int(armor["from"]) and mv.has("taunt"):
			_taunt(mv["taunt"], sim)
		if buffered != "" and t >= int(armor.get("release_from", 9999)) and t <= int(armor["to"]):
			var rel := action_move(buffered)
			if rel != move_id and can_use(rel):
				if dir != Vector2.ZERO:
					facing = dir
				_start_attack(rel, sim)
				return

	# Cancels: the next light in the string, or any higher rank once this move connected.
	if buffered != "":
		var want := buffered
		if want == "light" and String(mv["type"]) == "light":
			var nxt := String(mv.get("next", ""))
			if nxt != "" and t >= int(mv.get("cancel_from", 9999)):
				if dir != Vector2.ZERO:
					facing = _taunt_aim(dir, sim)  # each hit of a string can turn to a new direction
				_start_attack(nxt, sim)
				return
		else:
			var mid := action_move(want)
			# A multi-hit move can hold its cancel back until its last hit ("rank_cancel_from").
			if connected and punish_serial != attack_serial and move_rank(mid) > move_rank(move_id) \
					and can_use(mid) and not needs_fold(mid) and t >= int(mv.get("rank_cancel_from", 0)):
				if dir != Vector2.ZERO:
					facing = dir
				_start_attack(mid, sim)
				return

	if t >= int(mv["length"]) + block_lag:
		_set_state(State.IDLE)


## Out of stealth (Tiptoe): the strike or throw gave it away.
func _reveal(sim: MatchSim) -> void:
	if stealth > 0:
		stealth = 0
		ambush_serial = attack_serial
		sim.emit_event("unstealth", pos, 0.0, {"who": id})


func _taunt(tn: Dictionary, sim: MatchSim) -> void:
	var r := float(tn["radius"])
	for o in sim.creatures:
		if not is_foe(o) or o.state == State.KO or o.pos.distance_to(pos) > r + o.radius:
			continue
		o.taunt = int(tn["ticks"])
		o.taunt_by = id
		o.taunt_pull = float(tn.get("pull", TAUNT_PULL))
		sim.emit_event("taunt", o.pos, 1.0, {"who": o.id, "by": id})
	sim.emit_event("roar", pos, r, {"who": id})


## The button that keeps a charge move charging: the one that started it (the Heavy, or a
## Skill that charges, like Pinecone Bomb).
func _charge_bit() -> int:
	if move_id == "skill_1":
		return SimDefs.IN_SKILL1
	if move_id == "skill_2":
		return SimDefs.IN_SKILL2
	if move_id == "surge":
		return SimDefs.IN_SURGE  # a held Surge (Thousand Cranes: the throw's distance)
	return SimDefs.IN_HEAVY


## Turns to face the nearest foe when it's roughly ahead (facing·dir >= `cone`): moves
## with "aim" (Knife Flurry) don't need the foe lined up on one of the 8 directions.
func _aim(cone: float, sim: MatchSim) -> void:
	var foe := sim.nearest_opponent(self)
	if foe == null:
		return
	var to := foe.pos - pos
	if to.length_squared() < 0.0001:
		return
	var n := to.normalized()
	if facing.dot(n) >= cone:
		facing = n


## A homing dash (The One That Got Away): until "home.until" it steers for the nearest
## foe and paces itself to arrive as the dash ends (no faster than "home.max"); after that
## the landing spot is locked, so a late sidestep or dodge still beats it.
func _home(dash: Dictionary, t: int, sim: MatchSim) -> void:
	var hm: Dictionary = dash["home"]
	var spd := float(dash["speed"])
	var foe := sim.nearest_opponent(self)
	if foe != null and t <= int(hm.get("until", int(dash["to"]))):
		var to := foe.pos - pos
		var dist := to.length()
		if dist > 0.5:
			facing = to / dist
		var left := maxi(1, int(dash["to"]) - t + 1)
		spd = minf(float(hm.get("max", 3.0)), dist / float(left))
		home_speed = spd
	elif bool(hm.get("through", false)):
		spd = float(hm.get("max", 3.0))  # steered in, now runs on through (Pickpocket)
	else:
		spd = minf(home_speed, float(hm.get("max", 3.0)))
	_move(facing * spd, sim, not is_leaping())
	_trample(sim)


## Reappears behind the nearest foe (opposite the way it faces), or on its far side when
## that spot is a hole or off the floor; stays put when neither will do. Then faces it.
func _blink(bl: Dictionary, sim: MatchSim) -> void:
	var foe := sim.nearest_opponent(self)
	if foe == null:
		return
	var gap := float(foe.radius + radius) + float(bl.get("gap", 2.0))
	var away := foe.pos - pos
	away = away.normalized() if away.length_squared() > 0.0001 else facing
	var room := sim.floor_rect().grow(-float(radius) - 2.0)
	var from := pos
	for spot in [foe.pos - foe.facing * gap, foe.pos + away * gap]:
		if room.has_point(spot) and not sim.terrain.is_hole_at(spot) and not sim.terrain.solid_at(spot):
			pos = spot
			break
	var to_foe := foe.pos - pos
	if to_foe.length_squared() > 0.0001:
		facing = to_foe.normalized()
	sim.emit_event("blink", pos, 1.0, {"who": id, "from": from})


## Stone Gaze: anyone within range, in front of her, and facing her is slowed a little
## more each pulse (down to `min_mult`); the slow wears off `slow_ticks` after the gaze.
## Turning away (or getting behind her) is the counterplay.
func _gaze(g: Dictionary, sim: MatchSim) -> void:
	var r := float(g.get("range", 110))
	for o in sim.creatures:
		if not is_foe(o) or o.state == State.KO or o.state == State.FALLING:
			continue
		var to := o.pos - pos
		var d := to.length()
		if d > r + o.radius or d < 0.0001:
			continue
		var n := to / d
		if facing.dot(n) < float(g.get("cone", 0.7)):
			continue  # not in front of her
		if o.facing.dot(-n) < float(g.get("facing", 0.3)):
			continue  # looking away: safe
		var m := o.slow_mult if o.slow > 0 else 1.0
		o.slow_mult = maxf(float(g.get("min_mult", 0.35)), m - float(g.get("step", 0.08)))
		o.slow = maxi(o.slow, int(g.get("slow_ticks", 90)))
		sim.emit_event("gaze", o.pos, o.slow_mult, {"who": o.id, "by": id})


func _slam(mv: Dictionary, sim: MatchSim) -> void:
	var center := pos + facing * float(mv["reach"])
	var full := charge_ratio >= 1.0
	var heal := _terrain_heal(mv)
	if mv.has("terrain_rect"):
		# A fixed block of cells (Culvert's Slam): cracked by a plain slam, so a second
		# one there opens the hole; a full charge opens it at once, with a cracked rim.
		var r: Array = mv["terrain_rect"]
		# "terrain_at": how far ahead the block is centred (default: where the slam hits),
		# so a deeper block can reach further out without coming back under his feet.
		center = pos + facing * float(mv.get("terrain_at", mv["reach"]))
		var w := int(r[0])
		var h := int(r[1])
		if absf(facing.y) > absf(facing.x):
			var t := w
			w = h
			h = t  # facing up or down: the long side runs across
		sim.terrain.damage_rect(center, w, h, 2 if full else 1, full, heal)
	elif full:
		sim.terrain.damage_circle(center, float(mv["terrain_radius_charged"]), float(mv["terrain_core_charged"]), heal)
	else:
		sim.terrain.damage_circle(center, float(mv["terrain_radius"]), -1.0, heal)
	sim.emit_event("slam", center, 1.0 if full else 0.5)


## How long this move's damage to the floor lasts before it starts to mend:
## "terrain_heal" times the usual (1.5: half as long again).
func _terrain_heal(mv: Dictionary) -> int:
	return int(round(TerrainGrid.HEAL_TICKS * float(mv.get("terrain_heal", 1.0))))


## Called by MatchSim when a strike lands inside this creature's counter window (Slip).
func trigger_counter(attacker_pos: Vector2, sim: MatchSim) -> void:
	var c: Dictionary = move_def()["counter"]
	if attacker_pos.distance_squared_to(pos) > 0.0001:
		facing = (attacker_pos - pos).normalized()
	_start_attack(String(c["move"]), sim)
	countered = true
	invuln = int(c.get("invuln", 12))
	sim.emit_event("slip", pos + Vector2(0, -20), 1.0, {"who": id})


func _update_dodge(sim: MatchSim) -> void:
	var dg: Dictionary = def["dodge"]
	var frames := int(dg["frames"])
	if dg.has("blink"):
		# A teleport (Chef Cerebro): he stays put for a moment, then is simply somewhere
		# else, "distance" px the way he dodged (stopped by the walls, not by pits).
		var bl: Dictionary = dg["blink"]
		if state_t == int(bl["at"]):
			var from := pos
			pos = sim.terrain.resolve_body(_clamp_to_floor(pos + dodge_dir * float(bl["distance"])), radius)
			sim.emit_event("warp", pos, 1.0, {"who": id, "from": from})
		if state_t >= frames:
			_set_state(State.IDLE)
		return
	var spd := float(dg["speed"])
	if state_t > frames - 5:
		spd *= 0.4
	var before := pos
	var wanted := dodge_dir * spd
	# A roll vaults a pit; a ram runs along the ground and stops at its edge (an impact).
	if dg.has("ram") and (dg["ram"] as Dictionary).has("breaks"):
		_smash_ahead(sim, dg["ram"]["breaks"], wanted)
	_move(wanted, sim, dg.has("ram"))
	_trample(sim)
	if dg.has("ram"):
		_ram_step(dg["ram"], sim, pos - before, wanted)
		if state != State.DODGE:
			return
	if state_t >= frames:
		_set_state(State.IDLE)


## Landslide Ram (Craglash): a dodge with "ram" is a shoulder charge. The first foe his
## body reaches is hit like a strike (small damage, a short stun, counted in the combo)
## and the dash ends on the impact. Running into the arena wall ends it the same way:
## the floor cracks under the impact, and a foe pinned against the wall is hit too.
func _ram_step(ram: Dictionary, sim: MatchSim, moved: Vector2, wanted: Vector2) -> void:
	var hit := ram_hit_params(ram)
	var reach := float(ram.get("radius", 0.0))
	var impact := false
	for d in sim.creatures:
		var key := "ram:%d" % d.id
		if not is_foe(d) or seg_hit.has(key) or not sim._hittable(d, hit):
			continue
		if pos.distance_to(d.pos) > float(radius + d.radius) + reach:
			continue
		seg_hit[key] = true
		var push := d.pos - pos
		push = push.normalized() if push.length_squared() > 0.0001 else dodge_dir
		sim._apply_hit(self, d, hit, push, (pos + d.pos) * 0.5 + Vector2(0, -12))
		impact = true
	# The wall: the step came up short along the dash.
	if not impact and wanted.length_squared() > 0.0001 and moved.dot(wanted) < wanted.length_squared() * 0.5:
		impact = true
		var at := pos + dodge_dir * float(radius)
		if float(ram.get("crack", 0.0)) > 0.0:
			sim.terrain.crack_circle(at, float(ram["crack"]))
		sim.impact_stop(self, self, int(hit["hitstop"]))
		sim.emit_event("ram_wall", at, float(hit["damage"]), {"who": id})
	if impact:
		_set_state(State.IDLE)


func _update_guard(buttons: int, pressed: int, dir: Vector2, aim: Vector2, sim: MatchSim) -> void:
	var foe := sim.nearest_opponent(self)
	if foe != null and foe.pos.distance_squared_to(pos) > 0.0001:
		facing = (foe.pos - pos).normalized()
	if stun > 0:
		stun -= 1
		return
	var dg: Dictionary = def["dodge"]
	if ((pressed & SimDefs.IN_DODGE) or dodge_buffer > 0) and can_dodge():
		_start_dodge(dir, sim)
		return
	# Out of guard an attack goes at the opponent, unless an exact aim says otherwise.
	if _try_start_buffered(aim if buttons & SimDefs.IN_AIM else Vector2.ZERO, sim):
		return
	if not (buttons & SimDefs.IN_GUARD):
		_set_state(State.IDLE)
		return
	var gd: Dictionary = def["guard"]
	walk_vel = dir * walk_speed() * float(gd["speed_mult"])
	_move(walk_vel, sim, true)


func _set_state(s: State) -> void:
	state = s
	state_t = 0


# ------------------------------------------------------------------ getting hit

func reset_combo() -> void:
	combo_hits = 0
	combo_types = 0
	combo_moves.clear()
	combo_bounced = false
	combo_damage = 0.0
	juggles = 0
	juggle_serials.clear()


func _recover() -> void:
	stun = 0
	reset_combo()
	_set_state(State.IDLE)


func cancel_attack() -> void:
	charging = false
	windup_left = 0
	connected = false
	buffered = ""
	buffer_t = 0
	reel_t = 0


## Cast Line hooked someone: get hauled in to them at a steady speed, like a fish on a
## line, until `reel_gap` short of their body. Arriving ends the cast, so a light can
## follow straight away while they're still stunned.
func start_reel(target: CreatureSim, gap: float, speed: float) -> void:
	reel_to = target.id
	reel_gap = gap
	reel_speed = speed
	reel_t = 60
	knock_vel = Vector2.ZERO


func _reel_step(sim: MatchSim) -> void:
	reel_t -= 1
	if reel_to < 0 or reel_to >= sim.creatures.size() or sim.creatures[reel_to].state == State.KO:
		reel_t = 0
		return
	var t := sim.creatures[reel_to]
	var to := t.pos - pos
	var left := to.length() - (radius + t.radius + reel_gap)
	if left > 0.01:
		_move(to.normalized() * minf(reel_speed, left), sim, false)
		left -= reel_speed
	if left <= 0.01 or reel_t <= 0:
		reel_t = 0
		if state == State.ATTACK and move_def().has("reel"):
			walk_vel = Vector2.ZERO
			_set_state(State.IDLE)
		sim.emit_event("reeled_in", pos, 0.0, {"who": id, "target": t.id})

## Flip Out: carried in an arc over the attacker's head, from where it was scooped to
## the spot behind, at a steady pace, then left hanging there until it lands. Hits taken
## on the way (a Knife Flurry) don't knock it off course.
func start_flip(to: Vector2, ticks: int) -> void:
	flip_from = pos
	flip_to = to
	flip_total = maxi(ticks, 1)
	flip_t = flip_total
	knock_vel = Vector2.ZERO


func _flip_step() -> void:
	if state != State.AIRBORNE:
		flip_t = 0
		return
	flip_t -= 1
	pos = flip_from.lerp(flip_to, 1.0 - float(flip_t) / float(flip_total))
	knock_vel = Vector2.ZERO


func enter_hitstun(ticks: int, kb: Vector2) -> void:
	cancel_attack()
	walk_vel = Vector2.ZERO
	knock_vel = kb
	stun = maxi(ticks, 1)
	_set_state(State.HITSTUN)


func enter_crumple(ticks: int, kb: Vector2) -> void:
	cancel_attack()
	walk_vel = Vector2.ZERO
	knock_vel = kb
	stun = maxi(ticks, 1)
	_set_state(State.CRUMPLE)


func enter_air(ticks: int, kb: Vector2) -> void:
	cancel_attack()
	walk_vel = Vector2.ZERO
	knock_vel = kb
	air_t = 0
	air_total = maxi(int(float(ticks) * air_mult), 1)
	_set_state(State.AIRBORNE)


func enter_knockdown(ticks: int, kb: Vector2) -> void:
	cancel_attack()
	walk_vel = Vector2.ZERO
	knock_vel = kb
	stun = maxi(ticks, 1)
	_set_state(State.KNOCKDOWN)


## A juggle hit on an airborne target keeps it up a little longer.
func extend_air(extra: int, kb: Vector2) -> void:
	air_total = air_t + maxi(air_total - air_t, extra)
	knock_vel = kb


func _land(sim: MatchSim) -> void:
	sim.emit_event("land_hard", pos, 1.0)
	if hp <= 0.0:
		hp = 0.0
		_set_state(State.KO)
		sim.emit_event("ko", pos, 1.0, {"who": id})
		return
	enter_knockdown(LAND_KNOCKDOWN, knock_vel * 0.3)


func check_ko(sim: MatchSim) -> void:
	if hp <= 0.0 and state != State.KO:
		hp = 0.0
		if state == State.AIRBORNE:
			return  # finishes the fall first, then lands KO'd
		cancel_attack()
		_set_state(State.KO)
		sim.emit_event("ko", pos, 1.0, {"who": id})


func start_fall(sim: MatchSim) -> void:
	knock_vel = Vector2.ZERO
	walk_vel = Vector2.ZERO
	cancel_attack()
	_set_state(State.FALLING)
	fall_chasm = sim.terrain.get_cell(sim.terrain.world_to_cell(pos)) == TerrainGrid.CHASM
	sim.emit_event("fall", pos, 0.0, {"who": id, "pit": "chasm" if fall_chasm else "hole"})


func _land_from_fall(sim: MatchSim) -> void:
	pos = _clamp_to_floor(sim.terrain.nearest_solid(pos))
	hp -= FALL_DAMAGE
	if sim.fall_ko and fall_chasm:
		hp = 0.0  # Sinkhole: the chasm is the end (a creature's hole only hurts)
	fall_chasm = false
	calm_t = 0
	invuln = RESPAWN_INVULN
	reset_combo()
	if hp <= 0.0:
		hp = 0.0
		_set_state(State.KO)
		sim.emit_event("ko", pos, 1.0, {"who": id})
	else:
		_set_state(State.IDLE)
		sim.emit_event("land", pos, 0.0)


# ------------------------------------------------------------------ movement

func _apply_knockback(sim: MatchSim) -> void:
	if knock_vel.length_squared() < 0.0025:
		knock_vel = Vector2.ZERO
		return
	_move(knock_vel, sim, false, true)
	knock_vel *= AIR_FRICTION if state == State.AIRBORNE else FRICTION


func floor_min() -> Vector2:
	return Vector2(SimDefs.GRID_X + radius, SimDefs.GRID_Y + EDGE_TOP)


func floor_max() -> Vector2:
	return Vector2(floor_end.x - radius, floor_end.y - EDGE_BOTTOM)


func _clamp_to_floor(p: Vector2) -> Vector2:
	return p.clamp(floor_min(), floor_max())


func clamp_to_floor() -> void:
	pos = _clamp_to_floor(pos)


## Moves one axis at a time. Voluntary movement (walking) refuses to step into a hole;
## knockback and dodges don't, which is how creatures end up falling in. The arena's
## edges and its rubble walls and fences stop everything, and bounce knockback.
func _move(delta: Vector2, sim: MatchSim, voluntary: bool, bounce := false) -> void:
	var lo := floor_min()
	var hi := floor_max()
	var standing_on_hole := sim.terrain.is_hole_at(pos)
	var fences := not passes_fences()

	var nx := pos.x + delta.x
	if voluntary and not standing_on_hole and sim.terrain.is_hole_at(Vector2(nx, pos.y)):
		nx = pos.x
	var hit_wall := nx < lo.x or nx > hi.x
	nx = clampf(nx, lo.x, hi.x)
	var slid := sim.terrain.slide_x(pos, nx, radius, fences)
	hit_wall = hit_wall or slid != nx
	nx = slid
	if hit_wall and bounce:
		if absf(knock_vel.x) >= WALL_BOUNCE_MIN:
			knock_vel.x = -knock_vel.x * 0.6
			_on_wall_bounce(sim, Vector2(nx, pos.y), absf(knock_vel.x))
		else:
			knock_vel.x = 0.0
	pos.x = nx

	var ny := pos.y + delta.y
	if voluntary and not standing_on_hole and sim.terrain.is_hole_at(Vector2(pos.x, ny)):
		ny = pos.y
	hit_wall = ny < lo.y or ny > hi.y
	ny = clampf(ny, lo.y, hi.y)
	slid = sim.terrain.slide_y(pos, ny, radius, fences)
	hit_wall = hit_wall or slid != ny
	ny = slid
	if hit_wall and bounce:
		if absf(knock_vel.y) >= WALL_BOUNCE_MIN:
			knock_vel.y = -knock_vel.y * 0.6
			_on_wall_bounce(sim, Vector2(pos.x, ny), absf(knock_vel.y))
		else:
			knock_vel.y = 0.0
	pos.y = ny


## The first wall bounce in a combo adds stun, which is what makes it a combo extender.
func _on_wall_bounce(sim: MatchSim, at: Vector2, power: float) -> void:
	if not combo_bounced and (state == State.HITSTUN or state == State.CRUMPLE):
		combo_bounced = true
		stun += WALL_BOUNCE_STUN
	sim.emit_event("bounce", at, power, {"who": id})


## Snaps a direction to the nearest of 8. Uses only comparisons and one square root
## (no sin/cos/atan2), because trig functions can round differently on different
## platforms and online play needs every machine to compute identical results.
static func _snap8(v: Vector2) -> Vector2:
	if v.length_squared() < 1e-12:
		return Vector2.RIGHT
	var ax := absf(v.x)
	var ay := absf(v.y)
	if ay <= ax * TAN_22_5:
		return Vector2(signf(v.x), 0.0)
	if ax <= ay * TAN_22_5:
		return Vector2(0.0, signf(v.y))
	return Vector2(signf(v.x), signf(v.y)).normalized()
