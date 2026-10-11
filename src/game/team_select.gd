class_name TeamSelect
extends Node2D
## Picks each side's creatures before a Duel (three each) or a 2-player Versus (one
## each). Up/down moves between slots, left/right changes the creature, confirm on
## START begins. Either player's controller or the keyboard can drive it.

signal chosen(teams: Array)
signal cancelled

const C_PANEL := Color(0.07, 0.08, 0.1, 0.85)
const C_TEXT := Color("e8e6df")
const C_DIM := Color("9aa0aa")
const C_ACCENT := Color("ffd166")
const ROW_H := 44.0
const TOP := 70.0
const COLS := [40.0, 252.0]
const COL_W := 188.0

var title := "DUEL"
var team_size := 3
var side_labels := ["PLAYER 1", "CPU"]
var teams := [[], []]
var cursor := 0
var _font: Font = ThemeDB.fallback_font
var _tick := 0
var _roster: Array = []
var _tex := {}  ## sprite sheets by path, loaded up front (not inside _draw)


func open(p_title: String, size: int, labels: Array, defaults: Array) -> void:
	title = p_title
	team_size = size
	side_labels = labels.duplicate()
	_roster = MatchFactory.FIGHTERS.duplicate()
	for id in _roster:
		var path := String(MatchFactory.load_def(id).get("sprite", {}).get("path", ""))
		if path != "" and not _tex.has(path):
			_tex[path] = load(path)
	teams = [[], []]
	for side in 2:
		for i in size:
			var d: Array = defaults[side]
			teams[side].append(String(d[i % d.size()]))
	cursor = 0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _rows() -> int:
	return team_size * 2 + 1


## Returns true when the event changed something (for the menu blip).
func handle(event: InputEvent) -> bool:
	if not visible:
		return false
	if event.is_action_pressed("menu_back"):
		cancelled.emit()
		return true
	if event.is_action_pressed("ui_down"):
		cursor = (cursor + 1) % _rows()
	elif event.is_action_pressed("ui_up"):
		cursor = (cursor + _rows() - 1) % _rows()
	elif event.is_action_pressed("ui_left"):
		_cycle(-1)
	elif event.is_action_pressed("ui_right"):
		_cycle(1)
	elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("ui_accept"):
		if cursor == _rows() - 1:
			chosen.emit(teams.duplicate(true))
		else:
			cursor += 1
	else:
		return false
	queue_redraw()
	return true


func _cycle(dir: int) -> void:
	if cursor >= team_size * 2:
		return
	var side := cursor / team_size
	var slot := cursor % team_size
	var i := _roster.find(teams[side][slot])
	teams[side][slot] = _roster[(i + dir + _roster.size()) % _roster.size()]


func _process(_delta: float) -> void:
	if visible:
		_tick += 1
		queue_redraw()


func _draw() -> void:
	var w := float(SimDefs.VIEW_W)
	draw_rect(Rect2(0, 0, w, SimDefs.VIEW_H), Color(0.04, 0.05, 0.07, 0.9))
	_text(Vector2(0, 40), title, 18, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, 56), "Pick your team" if team_size > 1 else "Pick your fighters", 7, C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER, w)
	for side in 2:
		var x: float = COLS[side]
		_text(Vector2(x, TOP - 4), String(side_labels[side]), 8, C_ACCENT)
		for slot in team_size:
			var row := side * team_size + slot
			var y := TOP + slot * ROW_H
			var sel := row == cursor
			draw_rect(Rect2(x, y, COL_W, ROW_H - 6), Color(1, 1, 1, 0.1) if sel else C_PANEL)
			if sel:
				draw_rect(Rect2(x, y, 3, ROW_H - 6), C_ACCENT)
			var id := String(teams[side][slot])
			var def := MatchFactory.load_def(id)
			_draw_idle(def, Vector2(x + 30, y + ROW_H - 9), side == 1)
			var name_txt := ("<  %s  >" if sel else "%s") % String(def.get("name", id))
			_text(Vector2(x + 56, y + 16), name_txt, 9, C_ACCENT if sel else C_TEXT)
			_text(Vector2(x + 56, y + 28), String(def.get("title", "")), 6, C_DIM)
			if team_size > 1:
				_text(Vector2(x + COL_W - 18, y + 16), str(slot + 1), 7, C_DIM)
	var start_sel := cursor == _rows() - 1
	var r := Rect2(w * 0.5 - 50, 214, 100, 18)
	draw_rect(r, Color(C_ACCENT, 0.9) if start_sel else C_PANEL)
	_text(Vector2(r.position.x, r.position.y + 13), "START", 9, Color(0.08, 0.08, 0.1) if start_sel else C_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_text(Vector2(0, 248), "Up/Down choose slot   Left/Right change creature   Enter / A confirm   Esc / View back",
		6, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	if team_size > 1:
		_text(Vector2(0, 260), "In the fight: T / L / LT tags in the next teammate", 6, C_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_idle(def: Dictionary, feet: Vector2, face_left: bool) -> void:
	var sp: Dictionary = def.get("sprite", {})
	if sp.is_empty():
		return
	var tex: Texture2D = _tex.get(String(sp["path"]))
	if tex == null:
		return
	var fpx := float(sp.get("frame", 48))
	var o: Array = sp.get("origin", [24, 43])
	var idle: Array = sp.get("anims", {}).get("idle", [0, 0, 1])
	var frame := int(idle[1]) + (_tick / 10) % int(idle[2])
	var region := Rect2(frame * fpx, int(idle[0]) * fpx, fpx, fpx)
	# Big sheets (Craglash's 96 px frames) shrink to fit the slot.
	var k := minf(1.0, 55.0 / fpx)
	var sx := -k if face_left else k
	draw_set_transform(feet, 0.0, Vector2(sx, k))
	draw_texture_rect_region(tex, Rect2(-float(o[0]), -float(o[1]), fpx, fpx), region)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(_font, pos, s, align, width, size, 2, Color(0, 0, 0, col.a * 0.8))
	draw_string(_font, pos, s, align, width, size, col)
