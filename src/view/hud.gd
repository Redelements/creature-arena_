class_name Hud
extends Node2D
## Fighter panels (health, energy, stamina, skill cooldowns, Cairn's stones), the combo
## counter with its damage multiplier, the round timer, banners, and the menu.

const C_PANEL := Color(0.07, 0.08, 0.1, 0.8)
const C_TEXT := Color("e8e6df")
const C_DIM := Color("9aa0aa")
const C_HP_HI := Color("6fcf5a")
const C_HP_MID := Color("f2c14e")
const C_HP_LO := Color("e5534b")
const C_STAMINA := Color("5aa9e6")
const C_ENERGY := Color("ffcf3f")
const C_BAR_BG := Color("2a2e38")
const C_ACCENT := Color("ffd166")
const HELP := "WASD move  J light  K heavy  U skill 1  I skill 2  O surge  Space dodge  Shift guard  Shift+Space breakaway  F1 hitboxes  Esc menu"

var sim: MatchSim
var tags := ["P1", "CPU"]
var key_labels := [["U", "I"], ["", ""]]
var show_help := true
var timer_ticks := -1
var wins := [0, 0]
var wins_needed := 2
var banner := ""
var banner_sub := ""
var dummy_mode_name := ""

# Menu
var menu_visible := false
var menu_items: Array[String] = []
var menu_index := 0
var menu_footer := ""

var _toast := ""
var _toast_t := 0
var _combo_show := [0, 0]
var _combo_last := [{}, {}]
var _tick := 0
var _font: Font = ThemeDB.fallback_font


func show_toast(text: String) -> void:
	_toast = text
	_toast_t = 120


func advance() -> void:
	_tick += 1
	if _toast_t > 0:
		_toast_t -= 1
	if sim != null and sim.creatures.size() >= 2:
		for side in 2:
			var d := sim.creatures[1 - side]
			if d.combo_hits >= 2:
				_combo_last[side] = {"hits": d.combo_hits, "mult": SimDefs.variety_mult(d.combo_types),
					"dmg": d.combo_damage}
				_combo_show[side] = 50
			elif _combo_show[side] > 0:
				_combo_show[side] -= 1
	queue_redraw()


func _draw() -> void:
	if menu_visible:
		_draw_menu()
		return
	if sim == null or sim.creatures.size() < 2:
		return
	_panel(0, 4.0, false)
	_panel(1, SimDefs.VIEW_W - 164.0, true)
	_center()
	for side in 2:
		if _combo_show[side] > 0:
			_combo(side)

	if banner != "":
		var y := 128.0
		draw_rect(Rect2(0, y - 22, SimDefs.VIEW_W, 34 if banner_sub == "" else 46), Color(0, 0, 0, 0.45))
		_text(Vector2(0, y), banner, 20, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)
		if banner_sub != "":
			_text(Vector2(0, y + 16), banner_sub, 8, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)

	if _toast_t > 0:
		var a := minf(1.0, _toast_t / 20.0)
		_text(Vector2(90, 236), _toast, 8, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 300)

	if show_help:
		draw_rect(Rect2(0, 259, SimDefs.VIEW_W, 11), C_PANEL)
		_text(Vector2(0, 267), HELP, 5, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)


func _panel(side: int, x: float, right: bool) -> void:
	var c := sim.creatures[side]
	draw_rect(Rect2(x, 3, 160, 34), C_PANEL)
	var name := String(c.def.get("name", "?")).to_upper()
	var tag := String(tags[side])
	if c.is_dummy:
		tag = "F2: " + dummy_mode_name
	_text(Vector2(x + 5, 12), name, 7, C_TEXT)
	_text(Vector2(x + 5, 12), tag, 6, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 150)
	_bar(Rect2(x + 5, 15, 150, 6), c.hp / c.max_hp, _hp_color(c.hp / c.max_hp), right)

	# Energy, with a pulse when a Surge is ready.
	var full := c.energy >= CreatureSim.MAX_ENERGY
	var ecol := C_ENERGY
	if full and (_tick / 8) % 2 == 0:
		ecol = Color.WHITE
	_bar(Rect2(x + 5, 24, 100, 3), c.energy / CreatureSim.MAX_ENERGY, ecol, right)
	_bar(Rect2(x + 5, 30, 60, 2), c.stamina / c.max_stamina, C_STAMINA, right)
	if full:
		_text(Vector2(x + 5 if not right else x + 5, 35), "SURGE READY", 5, C_ENERGY,
			HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT, 100 if not right else 100)

	# Cairn's stones.
	var stack_def: Dictionary = c.def.get("stack", {})
	if not stack_def.is_empty():
		for i in int(stack_def["max"]):
			var px := x + 70.0 + i * 8.0
			var pts := PackedVector2Array([Vector2(px, 28), Vector2(px + 3, 31), Vector2(px, 34), Vector2(px - 3, 31)])
			draw_colored_polygon(pts, Color("c8bfae") if i < c.stack else Color(0.3, 0.32, 0.36))

	# Skill cooldowns.
	if not c.is_dummy:
		for i in 2:
			var mid := "skill_%d" % (i + 1)
			if not c.moves().has(mid):
				continue
			var r := Rect2(x + 112 + i * 22, 23, 18, 11)
			var ready := c.can_use(mid)
			draw_rect(r, Color(0.16, 0.18, 0.22))
			var cd := c.cooldown_ratio(mid)
			var fill := r
			fill.size.x = round(r.size.x * (1.0 - cd))
			draw_rect(fill, Color("4f7a5a") if ready else Color(0.3, 0.33, 0.38))
			draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)
			var lbl := String(key_labels[side][i])
			if lbl == "":
				lbl = "S%d" % (i + 1)
			_text(Vector2(r.position.x, r.position.y + 8), lbl, 6, C_TEXT if ready else C_DIM,
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _center() -> void:
	if timer_ticks < 0:
		return
	draw_rect(Rect2(218, 3, 44, 24), C_PANEL)
	var secs := int(ceil(timer_ticks / 60.0))
	_text(Vector2(218, 19), str(secs), 13, C_HP_LO if secs <= 10 else C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 44)
	for side in 2:
		for i in wins_needed:
			var px := 232.0 + (i * 7.0 if side == 1 else -i * 7.0) + (14.0 if side == 1 else 0.0)
			var won := i < int(wins[side])
			draw_circle(Vector2(px, 32), 2.5, C_ACCENT if won else Color(0.25, 0.27, 0.3))


func _combo(side: int) -> void:
	var info: Dictionary = _combo_last[side]
	if info.is_empty():
		return
	var a := minf(1.0, _combo_show[side] / 15.0)
	var x := 8.0 if side == 0 else SimDefs.VIEW_W - 128.0
	var mult := float(info["mult"])
	var col := C_ACCENT
	if mult >= 1.5:
		col = Color("ff9a5a")
	col.a = a
	_text(Vector2(x, 86), "%d HITS" % int(info["hits"]), 14, Color(1, 1, 1, a))
	var mult_txt := "x" + ("1.0" if mult <= 1.0 else String.num(mult, 2))
	_text(Vector2(x + 70, 86), mult_txt, 10, col)
	_text(Vector2(x, 98), "%d damage" % int(round(float(info["dmg"]))), 7, Color(C_DIM.r, C_DIM.g, C_DIM.b, a))


func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, SimDefs.VIEW_W, SimDefs.VIEW_H), Color(0.05, 0.06, 0.08, 0.82))
	_text(Vector2(0, 58), "CREATURE ARENA", 24, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)
	_text(Vector2(0, 74), "prototype build", 7, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)
	var y := 104.0
	for i in menu_items.size():
		var sel := i == menu_index
		if sel:
			draw_rect(Rect2(130, y - 10, 220, 14), Color(1, 1, 1, 0.08))
			_text(Vector2(136, y), ">", 9, C_ACCENT)
		_text(Vector2(150, y), menu_items[i], 9, C_ACCENT if sel else C_TEXT)
		y += 16.0
	_text(Vector2(0, 232), menu_footer, 6, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)
	_text(Vector2(0, 244), "Up/Down choose   Left/Right change CPU level   Enter or J to start", 6, C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)


func _bar(r: Rect2, ratio: float, col: Color, from_right := false) -> void:
	draw_rect(r.grow(1), Color(0, 0, 0, 0.6))
	draw_rect(r, C_BAR_BG)
	var w: float = round(r.size.x * clampf(ratio, 0.0, 1.0))
	var fill := Rect2(r.position.x + (r.size.x - w if from_right else 0.0), r.position.y, w, r.size.y)
	draw_rect(fill, col)
	if fill.size.x > 0 and r.size.y > 3:
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, 1)), col.lightened(0.35))


func _hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return C_HP_HI
	if ratio > 0.25:
		return C_HP_MID
	return C_HP_LO


func _text(pos: Vector2, s: String, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(_font, pos, s, align, width, size, 2, Color(0, 0, 0, col.a * 0.8))
	draw_string(_font, pos, s, align, width, size, col)
