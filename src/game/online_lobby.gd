class_name OnlineLobby
extends Node2D
## The online screen: pick your fighter, then host a match or join one by address.
## While hosting it lists this computer's addresses for the other player; while
## connecting it shows what's happening. Keyboard, mouse and controller all work; on
## the address row, type (or paste with Ctrl+V) an IP or host name, with an optional
## ":port".

signal host_pressed(fighter: String)
signal join_pressed(fighter: String, address: String, port: int, room: String)
signal cancelled

const C_PANEL := Color(0.07, 0.08, 0.1, 0.85)
const C_TEXT := Color("e8e6df")
const C_DIM := Color("9aa0aa")
const C_ACCENT := Color("ffd166")
const C_BAD := Color("ff8a7a")
const ROWS := ["fighter", "host", "join", "back"]
const ROW_Y := [64.0, 112.0, 136.0, 160.0]
const X := 120.0
const W := 240.0

var fighter := "cairn"
var address := ""
var cursor := 0
## Set by main from the Netplay session: what's happening, and whether it went wrong.
var status := ""
var status_bad := false
var busy := false  ## hosting or connecting: only Back works
var hosting_port := 0
var _font: Font = ThemeDB.fallback_font
var _tick := 0
var _time := 0.0
var _tex := {}


func open(p_fighter: String, p_address: String) -> void:
	fighter = p_fighter
	address = p_address
	cursor = 0
	status = ""
	status_bad = false
	busy = false
	for id in MatchFactory.FIGHTERS:
		var path := String(MatchFactory.load_def(id).get("sprite", {}).get("path", ""))
		if path != "" and not _tex.has(path):
			_tex[path] = load(path)
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


## Returns true when the event did something (for the menu blip).
func handle(event: InputEvent) -> bool:
	if not visible:
		return false
	if event.is_action_pressed("menu_back"):
		cancelled.emit()
		return true
	if busy:
		return false
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed):
		return _mouse(event)
	# Typing on the address row (letters too: host names are fine).
	if cursor == 2 and event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_BACKSPACE:
			address = address.substr(0, maxi(0, address.length() - 1))
			queue_redraw()
			return true
		if k.keycode == KEY_V and (k.ctrl_pressed or k.meta_pressed):
			address = (address + DisplayServer.clipboard_get().strip_edges()).substr(0, 60)
			queue_redraw()
			return true
		var ch := char(k.unicode) if k.unicode > 0 else ""
		if ch != "" and (ch.is_valid_identifier() or ch in "0123456789.:-[]/") and address.length() < 60:
			address += ch
			queue_redraw()
			return true
	if event.is_action_pressed("ui_down"):
		cursor = (cursor + 1) % ROWS.size()
	elif event.is_action_pressed("ui_up"):
		cursor = (cursor + ROWS.size() - 1) % ROWS.size()
	elif event.is_action_pressed("ui_left") and cursor == 0:
		_cycle(-1)
	elif event.is_action_pressed("ui_right") and cursor == 0:
		_cycle(1)
	elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("ui_accept"):
		_choose(cursor)
	else:
		return false
	queue_redraw()
	return true


func _mouse(event: InputEvent) -> bool:
	var p: Vector2 = get_global_mouse_position()
	for i in ROWS.size():
		var r := Rect2(X, ROW_Y[i] - (14.0 if i == 0 else 12.0), W, 30.0 if i == 0 else 18.0)
		if r.has_point(p):
			var changed := cursor != i
			cursor = i
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				if i == 0:
					_cycle(-1 if p.x < X + W * 0.5 else 1)
				else:
					_choose(i)
				changed = true
			queue_redraw()
			return changed
	return false


func _cycle(dir: int) -> void:
	var roster: Array = MatchFactory.FIGHTERS
	fighter = roster[(roster.find(fighter) + dir + roster.size()) % roster.size()]


func _choose(row: int) -> void:
	match ROWS[row]:
		"fighter":
			cursor = 1
		"host":
			host_pressed.emit(fighter)
		"join":
			var parsed := parse_address(address)
			if String(parsed[0]) == "":
				status = "Type the host's address first (for example 192.168.1.20)"
				status_bad = true
				return
			join_pressed.emit(fighter, String(parsed[0]), int(parsed[1]), String(parsed[2]))
		"back":
			cancelled.emit()


## "1.2.3.4", "1.2.3.4:7000", "my-pc.lan", "[::1]:7777" -> [host, port, room].
## A dedicated server's address can end in /ROOM ("game.example.net/kev") to be paired
## with whoever types the same room.
static func parse_address(text: String) -> Array:
	var t := text.strip_edges()
	var room := ""
	var slash := t.find("/")
	if slash >= 0:
		room = t.substr(slash + 1).strip_edges()
		t = t.substr(0, slash).strip_edges()
	var port := Netplay.DEFAULT_PORT
	if t.begins_with("["):  # [IPv6]:port
		var end := t.find("]")
		if end > 0:
			if t.substr(end + 1).begins_with(":"):
				port = int(t.substr(end + 2))
			t = t.substr(1, end - 1)
	elif t.count(":") == 1:
		port = int(t.get_slice(":", 1))
		t = t.get_slice(":", 0)
	if port <= 0 or port > 65535:
		port = Netplay.DEFAULT_PORT
	return [t, port, room]


## Animations count 60 ticks a second of real time, whatever the frame rate (counting
## frames made them race on a 144 Hz screen).
func _process(delta: float) -> void:
	if visible:
		_time += delta
		_tick = int(_time * 60.0 + 1e-6)
		queue_redraw()


func _draw() -> void:
	var w := float(SimDefs.VIEW_W)
	draw_rect(Rect2(0, 0, w, SimDefs.VIEW_H), Color(0.04, 0.05, 0.07, 0.9))
	_text(Vector2(0, 30), "ONLINE  1 v 1", 18, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, 42), "Play someone on another computer: one hosts, the other joins", 7, C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER, w)

	# Fighter
	var sel := cursor == 0
	var r := Rect2(X, ROW_Y[0] - 14.0, W, 30.0)
	draw_rect(r, Color(1, 1, 1, 0.1) if sel else C_PANEL)
	if sel:
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), C_ACCENT)
	var def := MatchFactory.load_def(fighter)
	_draw_idle(def, Vector2(X + 26, ROW_Y[0] + 13))
	_text(Vector2(X + 52, ROW_Y[0]), ("<  %s  >" if sel else "%s") % String(def.get("name", fighter)), 9,
		C_ACCENT if sel else C_TEXT)
	_text(Vector2(X + 52, ROW_Y[0] + 11), String(def.get("title", "")), 6, C_DIM)

	_button(1, "HOST A MATCH")
	var shown := address if address != "" else ("type the host's address" if cursor != 2 else "")
	var caret := "_" if cursor == 2 and (_tick / 20) % 2 == 0 and not busy else ""
	_button(2, "JOIN:  " + shown + caret)
	_button(3, "BACK")

	# Status, and how to connect over the internet.
	var y := 190.0
	if status != "":
		_text(Vector2(0, y), status, 7, C_BAD if status_bad else C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, w)
		y += 11.0
	if busy and hosting_port > 0:
		var addrs := Netplay.local_addresses()
		var line := "Your addresses:  " + ("  ".join(addrs) if not addrs.is_empty() else "(none found)")
		_text(Vector2(0, y), line, 7, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
		y += 11.0
	_text(Vector2(0, 227), "A dedicated server: join its address. Add /room (game.example.net/kev) to meet a friend there.", 6,
		C_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, 236), "Same network: join the host's 192.168... address.  Over the internet: the host forwards", 6,
		C_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, 245), "UDP port %d on their router, or both install Tailscale and join the host's 100.x address." %
		Netplay.DEFAULT_PORT, 6, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, 260), "Up/Down choose   Left/Right fighter   Enter / A select   Ctrl+V paste   Esc / View back", 6,
		C_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)


func _button(row: int, label: String) -> void:
	var sel := cursor == row
	var r := Rect2(X, ROW_Y[row] - 12.0, W, 18.0)
	var dim := busy and row != 3
	draw_rect(r, Color(C_ACCENT, 0.9) if sel and not dim else (Color(1, 1, 1, 0.1) if sel else C_PANEL))
	var col := Color(0.08, 0.08, 0.1) if sel and not dim else (C_DIM if dim else C_TEXT)
	_text(Vector2(r.position.x + 10, r.position.y + 12), label, 8, col)


func _draw_idle(def: Dictionary, feet: Vector2) -> void:
	var sp: Dictionary = def.get("sprite", {})
	var tex: Texture2D = _tex.get(String(sp.get("path", "")))
	if tex == null:
		return
	var fr = sp.get("frame", 48)
	var size := Vector2(float(fr[0]), float(fr[1])) if fr is Array else Vector2(float(fr), float(fr))
	var o: Array = sp.get("origin", [24, 43])
	var idle: Array = sp.get("anims", {}).get("idle", [0, 0, 1])
	var frame := int(idle[1]) + (_tick / 10) % int(idle[2])
	var region := Rect2(frame * size.x, int(idle[0]) * size.y, size.x, size.y)
	var k := float(sp.get("select_scale", minf(1.0, 55.0 / size.x))) * 0.6
	draw_set_transform(feet, 0.0, Vector2(k, k))
	draw_texture_rect_region(tex, Rect2(-float(o[0]), -float(o[1]), size.x, size.y), region)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(_font, pos, s, align, width, size, 2, Color(0, 0, 0, col.a * 0.8))
	draw_string(_font, pos, s, align, width, size, col)
