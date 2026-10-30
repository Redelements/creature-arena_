class_name CharacterSelect
extends UiScreen
## Fighting-game character select: every fighter in a portrait grid, a cursor per player
## (red for player 1, blue for player 2 or the CPU), a big preview of whoever each
## cursor is on, and the team filling up beside it.
##
## Several players pick at the same time, each with their own controller (player 1 also has
## the keyboard and mouse): `set_pickers` seats them, one column (a team list, a cursor)
## each; with more than two columns (a Brawl of 3-4 players) the panels go compact, a
## stripe in each seat's colour. Against the CPU, player 1 picks their own team, then the
## CPU's. A press picks, B / Esc takes the last pick back (with nothing to take back,
## player 1 leaves); "?" picks at random. When every column is full the match starts.
## `unique_across`: no fighter in two columns (a Brawl: one of each).
##
## `solo`: only player 1 picks (online, before searching). The right panel says what
## happens next (`solo_heading`, `solo_info`) instead of holding a second team, and the
## banner says `done_text`.

signal chosen(teams: Array)
signal cancelled

const COLS := 6
const TILE := Vector2(54, 40)
const GAP := 4.0
const GRID_Y := 170.0
const PANEL_Y := 30.0
const PANEL_H := 132.0
const PANEL_W := 226.0
## The room right of the big preview for the class and matchup lines.
const MATCHUP_W := PANEL_W - 108.0
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
## Players 3 and 4's pads (`set_pickers`), how many players pick, and how many columns
## (team lists) there are: two, or one a player past two.
var extra_pads: Array = []
var players := 1
var columns := 2
## No fighter in two columns (a Brawl).
var unique_across := false
var solo := false
var solo_heading := ""
var solo_info := ""
## The banner once the picks are in.
var done_text := "READY!"
## Progression: the title shown small after a side's label, for the fighter its cursor is
## on: title_for.call(side, fighter_id) -> String ("" none). Unset (or Progression off,
## main's choice): nothing is drawn.
var title_for := Callable()

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
var _matchups: Array = []  ## "Beats mages  ·  Loses to fighters" under the class line
var _tex := {}
var _font: Font:  ## read each draw, so Settings > Video > Text font shows at once
	get: return UiTheme.font()
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
	players = maxi(players, 2 if p_two else 1)
	_resize_columns()
	for side in columns:
		if previous.size() > side and not (previous[side] as Array).is_empty():
			cursor[side] = maxi(0, roster.find(previous[side][0]))


## Seats the players: `pads[k]` is player k+1's controller (player 1's may be ANY_PAD or
## NO_PAD; they keep the keyboard and mouse). Two or more make `two_players`; past two,
## each gets a column of their own. Call before the screen is on the stack.
func set_pickers(pads: Array) -> void:
	players = clampi(pads.size(), 1, LocalSeats.MAX_SEATS)
	p1_pad = int(pads[0]) if pads.size() > 0 else PlayerInput.ANY_PAD
	p2_pad = int(pads[1]) if pads.size() > 1 else PlayerInput.NO_PAD
	extra_pads = pads.slice(2)
	two_players = players >= 2
	_resize_columns()


func _resize_columns() -> void:
	columns = maxi(2, players)
	while teams.size() < columns:
		teams.append([])
		cursor.append(cursor[0])
	while labels.size() < columns:
		labels.append("PLAYER %d" % labels.size() if labels.size() < players else "CPU")
	while _history.size() < players:
		_history.append([])
	while _sticks.size() < players:
		_sticks.append(MenuStick.new())


## Player `p`'s controller (p from 0).
func _pad_of(p: int) -> int:
	match p:
		0: return p1_pad
		1: return p2_pad
	return int(extra_pads[p - 2]) if p - 2 < extra_pads.size() else PlayerInput.NO_PAD


## A column's colour: the side's, or past two columns each seat's own.
func _side_col(side: int) -> Color:
	return Accessibility.brawl_color(side) if columns > 2 else Accessibility.side_color(side)


## Panels go compact (a narrow column each) past two of them.
func compact() -> bool:
	return columns > 2


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
			_tex[id] = PackedSheet.load_sheet(String(sp["path"]))
	for side in columns:
		var x := _panel_x(side)
		var p := FighterPreview.new()
		if compact():  # a narrow column: the preview in the middle, the name under it
			p.position = Vector2(x + (_panel_w() - 64) * 0.5, PANEL_Y + 14)
			p.size = Vector2(64, 78)
			p.zoom = 1.15
		else:
			p.position = Vector2(x + 6, PANEL_Y + 16)
			p.size = Vector2(92, 104)
			p.zoom = 1.55
		p.face_left = side == columns - 1
		p.mouse_filter = MOUSE_FILTER_IGNORE
		_stage.add_child(p)
		_big.append(p)
		if compact():
			var nm := _make_label(Vector2(x, PANEL_Y + 94), 8, UiTheme.C_TEXT)
			nm.size.x = _panel_w()
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_names.append(nm)
			_blurbs.append(_make_label(Vector2(x, PANEL_Y + 108), 6, UiTheme.C_DIM))
			_infos.append(_make_label(Vector2(x, PANEL_Y + 108), 6, UiTheme.C_ACCENT))
			_matchups.append(_make_label(Vector2(x, PANEL_Y + 108), 6, UiTheme.C_DIM))
			for l in [_blurbs.back(), _infos.back(), _matchups.back()]:
				(l as Label).visible = false
			continue
		_names.append(_make_label(Vector2(x + 102, PANEL_Y + 22), 11, UiTheme.C_TEXT))
		var blurb := _make_label(Vector2(x + 102, PANEL_Y + 38), 6, UiTheme.C_DIM)
		blurb.size.x = PANEL_W - 108
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_blurbs.append(blurb)
		_infos.append(_make_label(Vector2(x + 102, PANEL_Y + 64), 6, UiTheme.C_ACCENT))
		_matchups.append(_make_label(Vector2(x + 102, PANEL_Y + 73), 6, UiTheme.C_DIM))
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
	if solo:
		return 0
	if two_players:
		return player
	return 0 if (teams[0] as Array).size() < team_size else 1


func is_done() -> bool:
	if solo:
		return (teams[0] as Array).size() >= team_size
	for side in columns:
		if (teams[side] as Array).size() < team_size:
			return false
	return true


## Which player an event belongs to (-1: nobody's): a pad to the player holding it,
## else player 1 when they listen to any pad.
func _player_of(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouse or event is InputEventAction:
		return 0 if p1_keyboard or event is InputEventAction else -1
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if two_players:
			for p in range(1, players):
				if event.device == _pad_of(p):
					return p
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
	for player in (players if two_players else 1):
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
		var mine := _pad_of(player) == dev
		if player == 0 and p1_pad == PlayerInput.ANY_PAD:
			mine = true  # any pad, but not one another player holds
			for p in range(1, players if two_players else 1):
				if _pad_of(p) == dev:
					mine = false
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
		var left: Array = MatchFactory.FIGHTERS.filter(func(f): return not (f in team) and not _taken_elsewhere(f, side))
		if left.is_empty():
			return
		id = String(left[_rng.randi_range(0, left.size() - 1)])
	elif id in team or _taken_elsewhere(id, side):
		return  # already on this team (or, in a Brawl, someone else's)
	team.append(id)
	(_history[player] as Array).append(side)
	if stack != null:
		stack.notify_chosen()
	if not two_players and not solo and side == 0 and team.size() >= team_size:
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

## `unique_across`: whether another column already has this fighter.
func _taken_elsewhere(id: String, side: int) -> bool:
	if not unique_across:
		return false
	for other in columns:
		if other != side and id in (teams[other] as Array):
			return true
	return false


func _panel_w() -> float:
	if not compact():
		return PANEL_W
	return floorf((SimDefs.VIEW_W - 20.0 - 6.0 * (columns - 1)) / columns)


func _panel_x(side: int) -> float:
	if compact():
		return 10.0 + side * (_panel_w() + 6.0)
	return 10.0 if side == 0 else SimDefs.VIEW_W - 10.0 - PANEL_W


func _tile_rect(i: int) -> Rect2:
	var w := COLS * (TILE.x + GAP) - GAP
	var x0 := (SimDefs.VIEW_W - w) * 0.5
	return Rect2(x0 + (i % COLS) * (TILE.x + GAP), GRID_Y + (i / COLS) * (TILE.y + GAP), TILE.x, TILE.y)


func _make_label(pos: Vector2, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", UiTheme.px(size_px))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.add_child(l)
	return l


## Solo: changes what the right panel says (an online room's who-has-locked-in list).
func set_solo_info(text: String) -> void:
	if text == solo_info:
		return
	solo_info = text
	_refresh()


## The panels show what each side's cursor is on.
func _refresh() -> void:
	if _big.is_empty():
		return
	for side in columns:
		if solo and side == 1:
			# What happens next, in place of a second team.
			(_big[1] as FighterPreview).fighter = ""
			(_names[1] as Label).text = solo_heading
			(_blurbs[1] as Label).text = solo_info
			(_infos[1] as Label).text = ""
			(_matchups[1] as Label).text = ""
			continue
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
		(_matchups[side] as Label).text = matchup_text(String(def.get("role", "")), UiTheme.font(),
			MATCHUP_W) if show else ""
	queue_redraw()


## The class triangle from `role`'s side, read from the CPU's table (CpuController.BEATS)
## so the menu can't drift from it: {"beats": [classes], "loses": [classes]}.
static func matchups(role: String) -> Dictionary:
	var loses: Array = []
	for other in CpuController.BEATS:
		if role in CpuController.BEATS[other]:
			loses.append(String(other))
	return {"beats": (CpuController.BEATS.get(role, []) as Array).duplicate(), "loses": loses}


## "Beats mages  ·  Loses to fighters, tanks, bruisers, skirmishers", shortened until it
## is at most `room` wide in `font` at the line's size: a list that names every other
## class but the other side's becomes "the rest", then "Beats: x / Loses to: y". "" for a
## class not in the triangle.
static func matchup_text(role: String, font: Font = null, room := INF) -> String:
	var m := matchups(role)
	var beats: Array = m["beats"]
	var loses: Array = m["loses"]
	if beats.is_empty() and loses.is_empty():
		return ""
	var b := _plural_list(beats)
	var l := _plural_list(loses)
	var tries: Array = [_matchup_line(b, l, false)]
	# "the rest": the longer list, when the two name every class but this one.
	var others: Array = CpuController.BEATS.keys().filter(func(r): return r != role)
	var b2 := b
	var l2 := l
	if not beats.is_empty() and not loses.is_empty() and beats.size() + loses.size() == others.size():
		if beats.size() >= loses.size():
			b2 = "the rest"
		else:
			l2 = "the rest"
	tries.append(_matchup_line(b2, l2, false))
	tries.append(_matchup_line(b2, l2, true))
	for t in tries:
		if font == null or font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(6)).x <= room:
			return t
	return tries[-1]


static func _plural_list(classes: Array) -> String:
	return ", ".join(PackedStringArray(classes.map(func(c): return String(c) + "s")))


static func _matchup_line(b: String, l: String, short: bool) -> String:
	var parts := PackedStringArray()
	if b != "":
		parts.append(("Beats: " if short else "Beats ") + b)
	if l != "":
		parts.append(("Loses to: " if short else "Loses to ") + l)
	return (" / " if short else "  ·  ").join(parts)


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
	for side in columns:
		_draw_panel(side)
	for i in roster.size():
		var r := _tile_rect(i)
		draw_rect(r, C_TILE)
		# A stripe in each column's colour on a fighter it has picked.
		var sw := r.size.x / columns
		for side in columns:
			if String(roster[i]) in teams[side]:
				draw_rect(Rect2(r.position.x + side * sw, r.position.y, sw, 2), _side_col(side))
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
	for side in columns:
		if not _cursor_shown(side):
			continue
		var r := _tile_rect(cursor[side]).grow(1.0 if side == 0 else -1.0 - 2.0 * maxi(0, side - 1))
		var col: Color = _side_col(side)
		o.draw_rect(r, col, false, 2.0)
		var tag := "%dP" % (side + 1) if side == 0 or two_players else "CPU"
		var tx := r.position.x + (side * 18.0 if compact() else (0.0 if side == 0 else r.size.x - 18.0))
		o.draw_rect(Rect2(tx, r.position.y - 7, 18, 7), col)
		o.draw_string(_font, Vector2(tx, r.position.y - 1.5), tag, HORIZONTAL_ALIGNMENT_CENTER, 18, UiTheme.px(5), UiTheme.C_DARK)
	if is_done():
		var w := float(SimDefs.VIEW_W)
		o.draw_rect(Rect2(0, 108, w, 26), Color(0, 0, 0, 0.6))
		o.draw_string_outline(_font, Vector2(0, 127), done_text, HORIZONTAL_ALIGNMENT_CENTER, w, UiTheme.px(16), UiTheme.outline(UiTheme.px(16)), Color(0, 0, 0, 0.8))
		o.draw_string(_font, Vector2(0, 127), done_text, HORIZONTAL_ALIGNMENT_CENTER, w, UiTheme.px(16), UiTheme.C_ACCENT)


func _cursor_shown(side: int) -> bool:
	if is_done():
		return false
	if solo:
		return side == 0
	if two_players:
		return true
	return side == side_of(0)


func _draw_panel(side: int) -> void:
	var x := _panel_x(side)
	var col: Color = _side_col(side)
	var team: Array = teams[side]
	var pw := _panel_w()
	draw_rect(Rect2(x, PANEL_Y, pw, PANEL_H), UiTheme.C_ROW)
	draw_rect(Rect2(x, PANEL_Y, pw, 2), col)
	if compact():  # label and status on one line each, the pick as one slot at the foot
		_text(Vector2(x, PANEL_Y + 11), String(labels[side]), 7, col, HORIZONTAL_ALIGNMENT_CENTER, pw)
		var st := _status(side)
		_text(Vector2(x, PANEL_Y + PANEL_H - 6), st, 5, UiTheme.C_ACCENT if team.size() >= team_size else UiTheme.C_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, pw)
		if not team.is_empty():
			_draw_mini(String(team[0]), Vector2(x + pw - 14, PANEL_Y + 30), side == columns - 1, 0.6)
		return
	_text(Vector2(x + 6, PANEL_Y + 11), String(labels[side]), 7, col)
	if solo and side == 1:
		return  # the labels hold what happens next
	var status := _status(side)
	var status_w := _font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(6)).x
	var shown := side_title(side)
	if shown != "":  # the player's title after their label, cut short of the status
		var tx := x + 6 + _font.get_string_size(String(labels[side]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(7)).x + 6
		var room := PANEL_W - 12 - status_w - 6 - (tx - x - 6)
		while shown.length() > 3 and _font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(5)).x > room:
			shown = shown.left(-3) + ".."
		if room > 12.0:
			_text(Vector2(tx, PANEL_Y + 11), shown, 5, Color(UiTheme.C_ACCENT, 0.85), HORIZONTAL_ALIGNMENT_LEFT, room)
	_text(Vector2(x + 6, PANEL_Y + 11), status, 6, UiTheme.C_ACCENT if team.size() >= team_size else UiTheme.C_DIM,
		HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 12)
	_draw_team(side, x, col, team)


## What a panel's title line shows on the right: READY, or how many picks are left.
func _status(side: int) -> String:
	var team: Array = teams[side]
	var status := ""
	if team.size() >= team_size:
		status = "READY"
	elif not two_players and side == 1 and side_of(0) == 0:
		status = "Player 1 picks after their own team"
	else:
		status = "Pick %d more" % (team_size - team.size()) if team_size > 1 else "Pick a fighter"
	return status


## The title after a side's label: for the fighter its cursor is on, else its first pick.
func side_title(side: int) -> String:
	if not title_for.is_valid():
		return ""
	var id := String(roster[cursor[side]])
	if id == RANDOM:
		id = String(teams[side][0]) if not (teams[side] as Array).is_empty() else ""
	return String(title_for.call(side, id)) if id != "" else ""


func _draw_team(side: int, x: float, col: Color, team: Array) -> void:
	# The team so far: slots narrow so four still fit inside the panel.
	var slot_w := minf(34.0, (PANEL_W - 108.0 - 4.0 * (team_size - 1)) / maxf(1.0, team_size))
	for k in team_size:
		var r := Rect2(x + 102 + k * (slot_w + 4), PANEL_Y + PANEL_H - 42, slot_w, 36)
		draw_rect(r, C_TILE)
		draw_rect(r, col if k < team.size() else Color(1, 1, 1, 0.15), false, 1.0)
		if k < team.size():
			_draw_mini(String(team[k]), Vector2(r.get_center().x, r.end.y - 2), side == 1, slot_w / 34.0)


## A fighter's first idle frame, small, standing at `feet`.
func _draw_mini(id: String, feet: Vector2, face_left: bool, scale := 1.0) -> void:
	var tex: Texture2D = _tex.get(id)
	if tex == null:
		return
	var sp: Dictionary = MatchFactory.load_def(id)["sprite"]
	var fsz = sp.get("frame", 48)  # a size, or [width, height]
	var fpx := float(fsz[0]) if fsz is Array else float(fsz)
	var fh := float(fsz[1]) if fsz is Array else fpx
	var o: Array = sp.get("origin", [24, 43])
	var idle: Array = sp.get("anims", {}).get("idle", [0, 0, 1])
	var ppu := float(ArtScale.ppu_of(sp))  # a 2x sheet draws at half the scale, the same size
	var k := float(sp.get("select_scale", minf(1.0, 55.0 * ppu / fpx))) * 0.6 * scale / ppu
	draw_set_transform(feet + _o, 0.0, Vector2(-k if face_left else k, k))
	draw_texture_rect_region(tex, Rect2(-float(o[0]), -float(o[1]), fpx, fh),
		Rect2(int(idle[1]) * fpx, int(idle[0]) * fh, fpx, fh))
	draw_set_transform(_o)


func _text(pos: Vector2, s: String, size_px: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var fs := UiTheme.px(size_px)
	draw_string_outline(_font, pos, s, align, width, fs, UiTheme.outline(fs), Color(0, 0, 0, col.a * 0.8))
	draw_string(_font, pos, s, align, width, fs, col)
