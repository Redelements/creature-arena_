class_name Hud
extends Node2D
## Health and stamina bars, combo counter, controls strip and short notices.

const C_PANEL := Color(0.07, 0.08, 0.1, 0.78)
const C_TEXT := Color("e8e6df")
const C_DIM := Color("9aa0aa")
const C_HP_HI := Color("6fcf5a")
const C_HP_MID := Color("f2c14e")
const C_HP_LO := Color("e5534b")
const C_STAMINA := Color("5aa9e6")
const C_BAR_BG := Color("2a2e38")
const HELP := "WASD move    J light    K heavy (hold)    Space dodge    Shift guard    F1 hitboxes    F2 dummy    F6 save replay    R reset    F3 hide"

var sim: MatchSim
var dummy_mode_name := ""
var show_help := true
var _toast := ""
var _toast_t := 0
var _font: Font = ThemeDB.fallback_font


func show_toast(text: String) -> void:
	_toast = text
	_toast_t = 120


func advance() -> void:
	if _toast_t > 0:
		_toast_t -= 1
	queue_redraw()


func _draw() -> void:
	if sim == null or sim.creatures.size() < 2:
		return
	var p := sim.creatures[0]
	var d := sim.creatures[1]

	# Player panel (left).
	draw_rect(Rect2(4, 3, 156, 27), C_PANEL)
	_text(Vector2(9, 12), String(p.def.get("name", "Player")).to_upper(), 7, C_TEXT)
	_bar(Rect2(9, 15, 146, 6), p.hp / p.max_hp, _hp_color(p.hp / p.max_hp))
	_bar(Rect2(9, 23, 100, 3), p.stamina / p.max_stamina, C_STAMINA)

	# Dummy panel (right).
	draw_rect(Rect2(320, 3, 156, 27), C_PANEL)
	_text(Vector2(325, 12), String(d.def.get("name", "Opponent")).to_upper(), 7, C_TEXT)
	_text(Vector2(325, 12), "F2: " + dummy_mode_name, 6, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 146)
	_bar(Rect2(325, 15, 146, 6), d.hp / d.max_hp, _hp_color(d.hp / d.max_hp))
	_bar(Rect2(371, 23, 100, 3), d.stamina / d.max_stamina, C_STAMINA)

	# Combo counter.
	if d.combo_hits >= 2:
		_text(Vector2(140, 26), "%d HITS" % d.combo_hits, 12, Color("ffe08a"), HORIZONTAL_ALIGNMENT_CENTER, 200)

	if _toast_t > 0:
		var a := minf(1.0, _toast_t / 20.0)
		_text(Vector2(90, 236), _toast, 8, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 300)

	if show_help:
		draw_rect(Rect2(0, 259, SimDefs.VIEW_W, 11), C_PANEL)
		_text(Vector2(0, 267), HELP, 5, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)


func _bar(r: Rect2, ratio: float, col: Color) -> void:
	draw_rect(r.grow(1), Color(0, 0, 0, 0.6))
	draw_rect(r, C_BAR_BG)
	var fill := r
	fill.size.x = round(r.size.x * clampf(ratio, 0.0, 1.0))
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
