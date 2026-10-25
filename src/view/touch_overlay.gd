class_name TouchOverlay
extends Node2D
## The touch controls on screen: the floating move stick, the button arc (Light biggest),
## each move's cooldown and the Surge meter on its button, the small Pause button, and
## while a drag aims a big move, that move's reach round the fighter as a true circle on
## the floor (no y squash: reach is the same every way) with a line the way it will go.
##
## Draws from the TouchPad's state and reads the sim (cooldowns, energy, where the fighter
## stands); it never writes either. It redraws only on a frame where something it shows
## changed (`_key`), so it costs nothing on the frames in between at 120 Hz and more.
## Main puts it on the screen layer over the HUD, shows it while touch is the device in a
## fight (`visible`), and sets `opacity` from Settings > Controls > Touch.

const C_FILL := Color(0.06, 0.07, 0.09, 0.55)
const C_FILL_DOWN := Color(0.95, 0.93, 0.86, 0.45)
const C_RING := Color(1, 1, 1, 0.55)
const C_RING_DIM := Color(1, 1, 1, 0.3)
const C_TEXT := Hud.C_TEXT
const C_COOL := Color(0, 0, 0, 0.55)
const C_ENERGY := Hud.C_ENERGY
const C_AIM := Color("ffd166")
const C_CANCEL := Color(0.75, 0.75, 0.75, 0.8)
const CD_STEPS := 16  ## a cooldown or the Surge meter shows in this many steps
const NAMES := {"light": "LIGHT", "heavy": "HEAVY", "skill_1": "S1", "skill_2": "S2", "surge": "SURGE",
	"dodge": "DODGE", "guard": "GUARD", "tag": "TAG"}
## Which move a button's cooldown and reach come from.
const MOVES := {"heavy": "heavy", "skill_1": "skill_1", "skill_2": "skill_2", "surge": "surge"}

var pad: TouchPad
var sim: MatchSim
var slot := 0  ## the local player's creature
var opacity := 0.7:
	set(v):
		opacity = v
		modulate.a = v

var _last_key: Array = []



func _ready() -> void:

	modulate.a = opacity
	visibility_changed.connect(func(): _last_key = [])


func _process(_delta: float) -> void:
	if not visible or pad == null:
		return
	var k := _key()
	if k != _last_key:
		_last_key = k
		queue_redraw()


func _me() -> CreatureSim:
	if sim == null or slot < 0 or slot >= sim.creatures.size():
		return null
	return sim.creatures[slot]


## Everything the picture depends on, in drawn steps: a frame whose key matches the last
## one has nothing new to draw.
func _key() -> Array:
	var k: Array = [pad.version, pad.screen()]
	var me := _me()
	if me != null:
		for b in ["heavy", "skill_1", "skill_2", "dodge"]:
			k.append(_cool_step(me, b))
		k.append(_energy_step(me))
		if not pad.aiming().is_empty():
			var xf := get_viewport().get_canvas_transform()
			k.append_array([me.pos.round(), xf.origin.round(), xf.get_scale().x])
	return k


## How much of a button's cooldown is left, in CD_STEPS steps (0: ready).
func _cool_step(me: CreatureSim, b: String) -> int:
	var left := int(me.cooldowns.get(b, 0))
	if left <= 0:
		return 0
	var total := 0
	if b == "dodge":
		total = int((me.def.get("dodge", {}) as Dictionary).get("cooldown", 0))
	else:
		total = int((me.moves().get(b, {}) as Dictionary).get("cooldown", 0))
	if total <= 0:
		return 0
	return clampi(ceili(float(left) / float(total) * CD_STEPS), 1, CD_STEPS)


func _energy_step(me: CreatureSim) -> int:
	return clampi(floori(me.energy / CreatureSim.MAX_ENERGY * CD_STEPS), 0, CD_STEPS)


func _draw() -> void:
	var t0 := PerfLog.now()
	_draw_now()
	PerfLog.since("touch draw", t0)


func _draw_now() -> void:
	if pad == null:
		return
	var me := _me()
	var aim := pad.aiming()
	if not aim.is_empty() and me != null:
		_draw_reach(me, aim)
	_draw_stick()
	for b in pad.buttons():
		if b == "pause":
			_draw_pause()
		else:
			_draw_button(String(b), me, aim)


func _draw_stick() -> void:
	var held := pad.stick_finger >= 0
	var o := pad.stick_origin.round()
	var r := pad.stick_radius()
	draw_circle(o, r, Color(0, 0, 0, 0.25 if held else 0.15))
	draw_arc(o, r, 0.0, TAU, 48, C_RING if held else C_RING_DIM, 1.0)
	draw_circle(pad.stick_knob.round(), pad.knob_radius(), C_FILL_DOWN if held else C_FILL)
	draw_arc(pad.stick_knob.round(), pad.knob_radius(), 0.0, TAU, 32, C_RING, 1.0)


func _draw_button(b: String, me: CreatureSim, aim: Dictionary) -> void:
	var c := pad.center(b).round()
	var r := pad.radius(b)
	var down := pad.is_down(b)
	var ready := true
	draw_circle(c, r, C_FILL_DOWN if down else C_FILL)
	if me != null and b == "surge":
		var e := _energy_step(me)
		ready = e >= CD_STEPS
		if ready:  # lit when the meter is full
			draw_circle(c, r, Color(C_ENERGY, 0.75 if not down else 0.95))
		elif e > 0:  # the meter fills round the rim
			draw_arc(c, r - 1.5, -PI * 0.5, -PI * 0.5 + TAU * e / CD_STEPS, 32, C_ENERGY, 2.0)
	elif me != null and b in ["heavy", "skill_1", "skill_2", "dodge"]:
		var cd := _cool_step(me, b)
		if cd > 0:  # still cooling down: dark, with what's left round the rim
			ready = false
			draw_circle(c, r, C_COOL)
			draw_arc(c, r - 1.5, -PI * 0.5, -PI * 0.5 + TAU * cd / CD_STEPS, 32, Color(1, 1, 1, 0.5), 2.0)
	draw_arc(c, r, 0.0, TAU, 40, C_RING if ready else C_RING_DIM, 1.0)
	var size := 6 if b == "light" else 5
	var col := C_TEXT if ready else Hud.C_DIM
	if b == "surge" and ready:
		col = Color(0.1, 0.08, 0.02)
	if not aim.is_empty() and String(aim["button"]) == b:
		if bool(aim["cancel"]):
			_text(c + Vector2(-r - 20, -r - 4), "CANCEL", 5, C_CANCEL, 40)
		else:  # the drag from the button: where the finger is, as a short line
			var d: Vector2 = aim["dir"]
			draw_line(c, c + d.limit_length(r * 2.5), Color(C_AIM, 0.8), 1.0)
	_text(c + Vector2(-r, 2), String(NAMES.get(b, b)), size, col, r * 2.0)


func _draw_pause() -> void:
	var c := pad.center("pause").round()
	var r := pad.radius("pause")
	draw_circle(c, r, C_FILL_DOWN if pad.is_down("pause") else C_FILL)
	draw_arc(c, r, 0.0, TAU, 24, C_RING_DIM, 1.0)
	draw_rect(Rect2(c + Vector2(-3, -3), Vector2(2, 6)), C_TEXT)
	draw_rect(Rect2(c + Vector2(1, -3), Vector2(2, 6)), C_TEXT)


## The aimed move's reach round the fighter, on the floor: a true circle (the sim hits
## the same distance every way), and the line the move will go along.
func _draw_reach(me: CreatureSim, aim: Dictionary) -> void:
	var mid := String(MOVES.get(String(aim["button"]), ""))
	if mid == "" or not me.moves().has(mid):
		return
	var xf := get_viewport().get_canvas_transform()
	var at := (xf * me.pos).round()
	var reach := me.move_range(mid) * xf.get_scale().x
	var cancel := bool(aim["cancel"])
	var col := C_CANCEL if cancel else C_AIM
	draw_arc(at, reach + 1.0, 0.0, TAU, 64, Color(0, 0, 0, 0.3), 1.0)
	draw_arc(at, reach, 0.0, TAU, 64, Color(col, 0.7 if not cancel else 0.4), 1.0)
	if cancel:
		return
	var d: Vector2 = aim["dir"]
	if d.length_squared() < 1e-6:
		return
	# The exact way the sim will throw it: the nearest of the 64 aim steps.
	var dir := SimDefs.aim_from_bits(SimDefs.aim_bits(d))
	draw_line(at, (at + dir * reach).round(), Color(col, 0.85), 1.0)
	draw_circle((at + dir * reach).round(), 2.0, col)


func _text(pos: Vector2, s: String, size: int, col: Color, width: float) -> void:
	var fs := UiTheme.px(size)
	draw_string_outline(UiTheme.font(), pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, fs, UiTheme.outline(fs),
		Color(0, 0, 0, col.a * 0.8))
	draw_string(UiTheme.font(), pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)
