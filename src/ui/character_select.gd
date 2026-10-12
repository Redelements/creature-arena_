class_name CharacterSelect
extends UiScreen
## Fighting-game character select: every fighter in a portrait grid, a cursor per player
## (red for player 1, blue for player 2 or the CPU), a big preview of whoever each
## cursor is on, and the team filling up beside it.
##
## Two players pick at the same time, each with their own controller (player 1 also has
## the keyboard and mouse). Against the CPU, player 1 picks their own team, then the
## CPU's. A press picks, B / Esc takes the last pick back (with nothing to take back,
## player 1 leaves); "?" picks at random. When both teams are full the match starts.

signal chosen(teams: Array)
signal cancelled

const COLS := 6
const TILE := Vector2(54, 40)
const GAP := 4.0
const GRID_Y := 170.0
const PANEL_Y := 30.0
const PANEL_H := 132.0
const PANEL_W := 226.0
const RANDOM := "random"
const C_TILE := Color(0.13, 0.15, 0.19, 0.95)
## A beat to see the last pick before the fight starts (B still takes it back).
const START_DELAY := 0.6

var mode_title := "DUEL"
var team_size := 3
var two_players := false
var labels: Array = ["PLAYER 1", "CPU"]
## Player 1's devices: the keyboard and mouse, and a pad (PlayerInput.ANY_PAD: any pad
## not player 2's; NO_PAD: none). Player 2's pad (two players only).
var p1_keyboard := true
var p1_pad := PlayerInput.ANY_PAD
var p2_pad := PlayerInput.NO_PAD

var roster: Array = []
var teams: Array = [[], []]
var cursor: Array = [0, 0]  ## the tile each side's cursor is on
var _history: Array = [[], []]  ## per player: the sides they picked for, newest last (for undo)
var _sticks: Array = []
var _done_t := -1.0
var _sent := false
var _rng := RandomNumberGenerator.new()
var _tiles: Array = []
var _big: Array = []  ## the two panels' big previews
var _names: Array = []
var _blurbs: Array = []
var _infos: Array = []
var _tex := {}
var _font: Font = ThemeDB.fallback_font
var _hint_text := ""
var _overlay: Control  ## cursors and the READY banner, over the previews
## Everything is laid out in a 480 x 270 stage centred on the screen (wider screens get
## more backdrop around it); `_o` is where the stage sits.
var _stage: Control
var _o := Vector2.ZERO


func _init() -> void:
	super()
	roster = MatchFactory.FIGHTERS.duplicate()
	roster.append(RANDOM)
	_rng.randomize()
	for i in 2:
		_sticks.append(MenuStick.new())


## `previous`: last time's teams, so the cursors start on familiar faces.
func setup(p_title: String, p_size: int, p_labels: Array, p_two: bool, previous: Array = []) -> void:
	mode_title = p_title
	team_size = maxi(1, p_size)
	labels = p_labels
	two_players = p_two
	for side in 2:
		if previous.size() > side and not (previous[side] as Array).is_empty():
			cursor[side] = maxi(0, roster.find(previous[side][0]))


func _ready() -> void:
	focus_mode = FOCUS_ALL
	_stage = Control.new()
	_stage.size = Vector2(SimDefs.VIEW_W, SimDefs.VIEW_H)
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_stage)
	resized.connect(_place_stage)
	_place_stage()
	for id in MatchFactory.FIGHTERS:
		var sp: Dictionary = MatchFactory.load_def(id).get("sprite", {})
		if sp.has("path"):
			_tex[id] = load(String(sp["path"]))
	for side in 2:
		var x := _panel_x(side)
		var p := FighterPreview.new()
		p.position = Vector2(x + 6, PANEL_Y + 16)
		p.size = Vector2(92, 104)
		p.zoom = 1.55
		p.face_left = side == 1
		p.mouse_filter = MOUSE_FILTER_IGNORE
		_stage.add_child(p)
		_big.append(p)
		_names.append(_make_label(Vector2(x + 102, PANEL_Y + 22), 11, UiTheme.C_TEXT))
		var blurb := _make_label(Vector2(x + 102, PANEL_Y + 38), 6, UiTheme.C_DIM)
		blurb.size.x = PANEL_W - 108
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_blurbs.append(blurb)
		_infos.append(_make_label(Vector2(x + 102, PANEL_Y + 64), 6, UiTheme.C_ACCENT))
	for i in roster.size():
		var r := _tile_rect(i)
		var t := FighterPreview.new()
		t.position = r.position + Vector2(0, 2)
		t.size = r.size - Vector2(0, 11)  # feet above the name
		t.zoom = 0.55
		t.mouse_filter = MOUSE_FILTER_IGNORE
		if String(roster[i]) != RANDOM:
			t.fighter = String(roster[i])
		_stage.add_child(t)
		_tiles.append(t)
	_overlay = Control.new()
	_overlay.size = _stage.size
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_stage.add_child(_overlay)
	_refresh()


func focus_first() -> void:
	grab_focus()


func set_gamepad(on: bool) -> void:
	_gamepad = on
	_hint_text = Prompts.line(on, ["move", "select", "undo"]) + "     " + \
		("Y random" if on else "R random")
	queue_redraw()


## Back from the stack (a device that isn't anyone's): player 1 takes a pick back.
func back() -> void:
	_undo(0)


# ------------------------------------------------------------------ who is picking

## The side `player` is picking for now: their own, or (against the CPU) the CPU's once
## player 1's team is full.
func side_of(player: int) -> int:
	if two_players:
		return player
	return 0 if (teams[0] as Array).size() < team_size else 1


func is_done() -> bool:
	return (teams[0] as Array).size() >= team_size and (teams[1] as Array).size() >= team_size


## Which player an event belongs to (-1: nobody's).
func _player_of(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouse or event is InputEventAction:
		return 0 if p1_keyboard or event is InputEventAction else -1
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if two_players and event.device == p2_pad:
			return 1
		if p1_pad == PlayerInput.ANY_PAD or event.device == p1_pad:
			return 0
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed):
		_mouse(event)
		return
	var who := _player_of(event)
	if who < 0:
		return
	var dir := _dir_of(event)
	if dir != Vector2i.ZERO:
		move(who, dir)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("menu_confirm"):
		pick(who)
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu_back"):
		_undo(who)
	elif _is_random(event):
		pick(who, true)
	else:
		return
	accept_event()


static func _dir_of(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("ui_left", true) or event.is_action_pressed("kb_left", true):
		return Vector2i.LEFT
	if event.is_action_pressed("ui_right", true) or event.is_action_pressed("kb_right", true):
		return Vector2i.RIGHT
	if event.is_action_pressed("ui_up", true) or event.is_action_pressed("kb_up", true):
		return Vector2i.UP
	if event.is_action_pressed("ui_down", true) or event.is_action_pressed("kb_down", true):
		return Vector2i.DOWN
	return Vector2i.ZERO


static func _is_random(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == JOY_BUTTON_Y
	if event is InputEventKey and event.pressed and not event.echo:
		return (event as InputEventKey).physical_keycode == KEY_R
	return false


func _mouse(event: InputEvent) -> void:
	if not p1_keyboard:
		return
	var p: Vector2 = event.position - _o
	for i in roster.size():
		if _tile_rect(i).has_point(p):
			var side := side_of(0)
			if cursor[side] != i:
				cursor[side] = i
				if stack != null:
					stack.moved.emit()
				_refresh()
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				pick(0)
			elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
				_undo(0)
			accept_event()
			return


## Each player's stick (their own pad's), like a d-pad.
func _process(delta: float) -> void:
	for player in (2 if two_players else 1):
		var v := _stick_of(player)
		for action in (_sticks[player] as MenuStick).step(v, delta):
			move(player, {"ui_left": Vector2i.LEFT, "ui_right": Vector2i.RIGHT, "ui_up": Vector2i.UP,
				"ui_down": Vector2i.DOWN}[action])
	if _done_t >= 0.0 and not _sent:
		_done_t += delta
		if _done_t >= START_DELAY:
			_sent = true
			chosen.emit(teams.duplicate(true))
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _stick_of(player: int) -> Vector2:
	var best := Vector2.ZERO
	for dev in Input.get_connected_joypads():
		var mine := (player == 1 and dev == p2_pad) or (player == 0 and (p1_pad == dev or \
			(p1_pad == PlayerInput.ANY_PAD and not (two_players and dev == p2_pad))))
		if not mine:
			continue
		var v := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if v.length() > best.length():
			best = v
	return best


# ------------------------------------------------------------------ actions

func move(player: int, dir: Vector2i) -> void:
	if is_done():
		return
	var side := side_of(player)
	if two_players and (teams[side] as Array).size() >= team_size:
		return  # ready: waiting for the other player
	var n := roster.size()
	var i: int = cursor[side]
	var rows := ceili(float(n) / COLS)
	if dir.x != 0:
		i = (i + dir.x + n) % n
	else:
		var row := (i / COLS + dir.y + rows) % rows
		i = mini(row * COLS + i % COLS, n - 1)
	cursor[side] = i
	if stack != null:
		stack.moved.emit()
	_refresh()


## Picks what `player`'s cursor is on (or a random fighter) for the side they're picking.
func pick(player: int, random := false) -> void:
	if is_done():
		return
	var side := side_of(player)
	var team: Array = teams[side]
	if team.size() >= team_size:
		return
	var id := String(roster[cursor[side]])
	if random or id == RANDOM:
		var left: Array = MatchFactory.FIGHTERS.filter(func(f): return not (f in team))
		id = String(left[_rng.randi_range(0, left.size() - 1)])
	elif id in team:
		return  # already on this team
	team.append(id)
	(_history[player] as Array).append(side)
	if stack != null:
		stack.notify_chosen()
	if not two_players and side == 0 and team.size() >= team_size:
		cursor[1] = cursor[0]  # the CPU's cursor starts where player 1's ended
	if is_done():
		_done_t = 0.0
	_refresh()


func _undo(player: int) -> void:
	var h: Array = _history[player]
	if h.is_empty():
		if player == 0:
			cancelled.emit()
		return
	var side: int = h.pop_back()
	(teams[side] as Array).pop_back()
	_done_t = -1.0
	_sent = false
	if stack != null:
		stack.moved.emit()
	_refresh()


# ------------------------------------------------------------------ drawing

func _panel_x(side: int) -> float:
	return 10.0 if side == 0 else SimDefs.VIEW_W - 10.0 - PANEL_W


func _tile_rect(i: int) -> Rect2:
	var w := COLS * (TILE.x + GAP) - GAP
	var x0 := (SimDefs.VIEW_W - w) * 0.5
	return Rect2(x0 + (i % COLS) * (TILE.x + GAP), GRID_Y + (i / COLS) * (TILE.y + GAP), TILE.x, TILE.y)


func _make_label(pos: Vector2, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.add_child(l)
	return l


## The panels show what each side's cursor is on.
func _refresh() -> void:
	if _big.is_empty():
		return
	for side in 2:
		var id := String(roster[cursor[side]])
		var show := id != RANDOM
		(_big[side] as FighterPreview).fighter = id if show else ""
		var def := MatchFactory.load_def(id) if show else {}
		(_names[side] as Label).text = String(def.get("name", "Random")) if show else "Random"
		(_blurbs[side] as Label).text = String(def.get("title", "")) if show else "Anyone not on your team yet"
		var bits := PackedStringArray()
		for k in ["role", "affinity"]:
			var v = def.get(k)
			if v != null and String(v) != "" and String(v) != "none":
				bits.append(String(v).capitalize())
		(_infos[side] as Label).text = "  ·  ".join(bits)
	queue_redraw()


func _place_stage() -> void:
	_o = ((size - Vector2(SimDefs.VIEW_W, SimDefs.VIEW_H)) * 0.5).floor()
	if _stage != null:
		_stage.position = _o
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.94))
	draw_set_transform(_o)
	var w := float(SimDefs.VIEW_W)
	_text(Vector2(0, 18), mode_title, 14, UiTheme.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, 27), "Pick your team of %d" % team_size if team_size > 1 else "Pick your fighter", 6,
		UiTheme.C_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	for side in 2:
		_draw_panel(side)
	for i in roster.size():
		var r := _tile_rect(i)
		draw_rect(r, C_TILE)
		# A stripe in each side's colour on a fighter it has picked.
		for side in 2:
			if String(roster[i]) in teams[side]:
				draw_rect(Rect2(r.position.x + side * r.size.x * 0.5, r.position.y, r.size.x * 0.5, 2),
					Hud.SIDE_COLORS[side])
		if String(roster[i]) == RANDOM:
			_text(Vector2(r.position.x, r.position.y + 27), "?", 20, UiTheme.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER,
				r.size.x)
		var nm := "Random" if String(roster[i]) == RANDOM else \
			String(MatchFactory.load_def(String(roster[i])).get("name", ""))
		_text(Vector2(r.position.x, r.end.y - 2), nm, 5, UiTheme.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_text(Vector2(0, 266), _hint_text, 6, UiTheme.C_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)


## Over the previews: the cursors (both on one tile: player 1's outside, the other
## inside) and READY when both teams are full.
func _draw_overlay() -> void:
	var o := _overlay
	for side in 2:
		if not _cursor_shown(side):
			continue
		var r := _tile_rect(cursor[side]).grow(1.0 if side == 0 else -1.0)
		var col: Color = Hud.SIDE_COLORS[side]
		o.draw_rect(r, col, false, 2.0)
		var tag := "1P" if side == 0 else ("2P" if two_players else "CPU")
		var tx := r.position.x if side == 0 else r.end.x - 18.0
		o.draw_rect(Rect2(tx, r.position.y - 7, 18, 7), col)
		o.draw_string(_font, Vector2(tx, r.position.y - 1.5), tag, HORIZONTAL_ALIGNMENT_CENTER, 18, 5, UiTheme.C_DARK)
	if is_done():
		var w := float(SimDefs.VIEW_W)
		o.draw_rect(Rect2(0, 108, w, 26), Color(0, 0, 0, 0.6))
		o.draw_string_outline(_font, Vector2(0, 127), "READY!", HORIZONTAL_ALIGNMENT_CENTER, w, 16, 2, Color(0, 0, 0, 0.8))
		o.draw_string(_font, Vector2(0, 127), "READY!", HORIZONTAL_ALIGNMENT_CENTER, w, 16, UiTheme.C_ACCENT)


func _cursor_shown(side: int) -> bool:
	if is_done():
		return false
	if two_players:
		return true
	return side == side_of(0)


func _draw_panel(side: int) -> void:
	var x := _panel_x(side)
	var col: Color = Hud.SIDE_COLORS[side]
	var team: Array = teams[side]
	draw_rect(Rect2(x, PANEL_Y, PANEL_W, PANEL_H), UiTheme.C_ROW)
	draw_rect(Rect2(x, PANEL_Y, PANEL_W, 2), col)
	_text(Vector2(x + 6, PANEL_Y + 11), String(labels[side]), 7, col)
	var status := ""
	if team.size() >= team_size:
		status = "READY"
	elif not two_players and side == 1 and side_of(0) == 0:
		status = "Player 1 picks after their own team"
	else:
		status = "Pick %d more" % (team_size - team.size()) if team_size > 1 else "Pick a fighter"
	_text(Vector2(x + 6, PANEL_Y + 11), status, 6, UiTheme.C_ACCENT if team.size() >= team_size else UiTheme.C_DIM,
		HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 12)
	# The team so far.
	var slot_w := 34.0
	for k in team_size:
		var r := Rect2(x + 102 + k * (slot_w + 4), PANEL_Y + PANEL_H - 42, slot_w, 36)
		draw_rect(r, C_TILE)
		draw_rect(r, col if k < team.size() else Color(1, 1, 1, 0.15), false, 1.0)
		if k < team.size():
			_draw_mini(String(team[k]), Vector2(r.get_center().x, r.end.y - 2), side == 1)


## A fighter's first idle frame, small, standing at `feet`.
func _draw_mini(id: String, feet: Vector2, face_left: bool) -> void:
	var tex: Texture2D = _tex.get(id)
	if tex == null:
		return
	var sp: Dictionary = MatchFactory.load_def(id)["sprite"]
	var fpx := float(sp.get("frame", 48))
	var o: Array = sp.get("origin", [24, 43])
	var idle: Array = sp.get("anims", {}).get("idle", [0, 0, 1])
	var k := float(sp.get("select_scale", minf(1.0, 55.0 / fpx))) * 0.6
	draw_set_transform(feet + _o, 0.0, Vector2(-k if face_left else k, k))
	draw_texture_rect_region(tex, Rect2(-float(o[0]), -float(o[1]), fpx, fpx),
		Rect2(int(idle[1]) * fpx, int(idle[0]) * fpx, fpx, fpx))
	draw_set_transform(_o)


func _text(pos: Vector2, s: String, size_px: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(_font, pos, s, align, width, size_px, 2, Color(0, 0, 0, col.a * 0.8))
	draw_string(_font, pos, s, align, width, size_px, col)
