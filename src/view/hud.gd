class_name Hud
extends Node2D
## Fighter panels (health, energy, stamina, skill cooldowns, Cairn's stones), the combo
## counter with its damage multiplier and attack-type tracker, the Surge cut-in, the
## round timer, banners, and the menu.

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
const CUT_IN_TICKS := 30
const TYPE_PIPS := [["light", "LT"], ["heavy", "HV"], ["skill", "SK"], ["surge", "SG"]]

var sim: MatchSim
var duel: DuelSim = null  ## set during a Duel: draws the team strip under each panel
var tag_labels := ["", ""]
var tags := ["P1", "CPU"]
var key_labels := [["", ""], ["", ""]]
const SIDE_COLORS: Array[Color] = [Color("ff5a5a"), Color("5aa0ff")]
var surge_labels := ["", ""]
var help_text := ""
var show_help := true
var timer_ticks := -1
var wins := [0, 0]
var wins_needed := 2
var banner := ""
var banner_sub := ""
var dummy_mode_name := ""
## Online: ping, input delay, rollback; drawn small in the bottom corner.
var net_info := ""

# Showcase captions: a title, the chain of moves, and which one is happening now.
var caption_title := ""
var caption_items: Array = []
var caption_index := -1

# Menu
var menu_visible := false
var menu_items: Array[String] = []
var menu_index := 0
var menu_footer := ""
var menu_title := ""
## Per menu row: a 0..1 level drawn as a bar (volumes), or -1 for none.
var menu_values: Array = []  ## the page's name under the logo ("SINGLE PLAYER"); empty on the title menu
var menu_y0 := 104.0
var menu_dy := 16.0

var _toast := ""
var _toast_t := 0
var _combo_show := [0, 0]
var _combo_last := [{}, {}]
var _combo_pop := [0, 0]
var _cut := {}
var _tick := 0
var _font: Font = ThemeDB.fallback_font


func show_toast(text: String) -> void:
	_toast = text
	_toast_t = 120


## A fighting-game super cut-in: a slanted band with the fighter's portrait and the move.
func cut_in(c: CreatureSim, side: int, move_name: String) -> void:
	var sp: Dictionary = c.def.get("sprite", {})
	if sp.is_empty():
		return
	var fpx := int(sp.get("frame", 48))
	var fr: Array = c.def.get("cut_in_frame", [0, 0])
	var o: Array = sp.get("origin", [24, 43])
	_cut = {
		"side": side, "move": move_name.to_upper(), "who": String(c.def.get("name", "")).to_upper(),
		"tex": load(String(sp["path"])), "region": Rect2(int(fr[1]) * fpx, int(fr[0]) * fpx, fpx, fpx),
		"origin": Vector2(float(o[0]), float(o[1])), "fpx": fpx,
		"color": Color(String(c.def.get("fx_color", "#ffcf3f"))), "t": 0,
	}


func advance() -> void:
	_tick += 1
	if _toast_t > 0:
		_toast_t -= 1
	if sim != null and sim.creatures.size() >= 2:
		for side in 2:
			var d := sim.creatures[1 - side]
			if _combo_pop[side] > 0:
				_combo_pop[side] -= 1
			if d.combo_hits >= 2:
				var prev: Dictionary = _combo_last[side]
				if _combo_show[side] < 50 or int(prev.get("hits", 0)) != d.combo_hits:
					_combo_pop[side] = 8
				_combo_last[side] = {"hits": d.combo_hits, "mult": SimDefs.variety_mult(d.combo_types),
					"dmg": d.combo_damage, "types": d.combo_types}
				_combo_show[side] = 50
			elif _combo_show[side] > 0:
				_combo_show[side] -= 1
	if not _cut.is_empty():
		_cut["t"] = int(_cut["t"]) + 1
		if int(_cut["t"]) > CUT_IN_TICKS:
			_cut = {}
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
	if caption_title != "":
		_draw_caption()
	if not _cut.is_empty():
		_draw_cut_in()

	if banner != "":
		var y := 128.0
		draw_rect(Rect2(0, y - 22, SimDefs.VIEW_W, 34 if banner_sub == "" else 46), Color(0, 0, 0, 0.45))
		_text(Vector2(0, y), banner, 20, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)
		if banner_sub != "":
			_text(Vector2(0, y + 16), banner_sub, 8, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)

	if _toast_t > 0:
		var a := minf(1.0, _toast_t / 20.0)
		_text(Vector2(90, 236), _toast, 8, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 300)

	if net_info != "":
		_text(Vector2(SimDefs.VIEW_W - 304, 255), net_info, 6, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300)

	if show_help:
		draw_rect(Rect2(0, 259, SimDefs.VIEW_W, 11), C_PANEL)
		_text(Vector2(0, 267), help_text, 5, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)


func _panel(side: int, x: float, right: bool) -> void:
	var c := sim.creatures[side]
	draw_rect(Rect2(x, 3, 160, 34), C_PANEL)
	draw_rect(Rect2(x, 3, 160, 2), SIDE_COLORS[side])  # red left, blue right, like the markers
	var name := String(c.def.get("name", "?")).to_upper()
	var tag := String(tags[side])
	if c.is_dummy:
		tag = "F2: " + dummy_mode_name
	_text(Vector2(x + 5, 12), name, 7, C_TEXT)
	_text(Vector2(x + 5, 12), tag, 6, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 150)
	_bar(Rect2(x + 5, 15, 150, 6), c.hp / c.max_hp, _hp_color(c.hp / c.max_hp), right)
	# A shield (Craglash's Stoneskin): pale stone over the end of the health bar, and its name.
	if c.shield > 0.0:
		var sw := minf(1.0, c.shield / c.max_hp) * 150.0
		var hw := c.hp / c.max_hp * 150.0
		var sx := x + 5 + (150.0 - hw - sw if right else hw)
		sx = clampf(sx, x + 5, x + 155 - sw)
		draw_rect(Rect2(sx, 15, sw, 6), Color("d8d4cc"))
		draw_rect(Rect2(sx, 15, sw, 6), Color(0, 0, 0, 0.5), false, 1.0)
		_text(Vector2(x + 5, 12), "STONESKIN  ", 5, Color("d8d4cc"), HORIZONTAL_ALIGNMENT_RIGHT, 118)
	if duel != null:
		_team_strip(side, x, right)

	# Energy, with a pulse when a Surge is ready.
	var full := c.energy >= CreatureSim.MAX_ENERGY
	var ecol := C_ENERGY
	if full and (_tick / 8) % 2 == 0:
		ecol = Color.WHITE
	_bar(Rect2(x + 5, 24, 100, 3), c.energy / CreatureSim.MAX_ENERGY, ecol, right)
	_bar(Rect2(x + 5, 30, 60, 2), c.stamina / c.max_stamina, C_STAMINA, right)
	if full:
		var ready_txt := "SURGE READY" + (" (%s)" % surge_labels[side] if String(surge_labels[side]) != "" else "")
		_text(Vector2(x + 5, 35), ready_txt, 5, C_ENERGY,
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


## Duel: each teammate's health (active one outlined, knocked-out ones crossed out)
## and whether a tag is ready.
func _team_strip(side: int, x: float, right: bool) -> void:
	draw_rect(Rect2(x, 38, 160, 12), C_PANEL)
	var team: Array = duel.teams[side]
	for i in team.size():
		var m: CreatureSim = team[i]
		var bx := x + 5.0 + i * 26.0
		if right:
			bx = x + 160.0 - 5.0 - 22.0 - i * 26.0
		var r := Rect2(bx, 41, 22, 6)
		var ratio := clampf(m.hp / m.max_hp, 0.0, 1.0)
		draw_rect(r, C_BAR_BG)
		var down := m.hp <= 0.0 or m.state == CreatureSim.State.KO
		if not down:
			var fill := Rect2(r.position, Vector2(round(r.size.x * ratio), r.size.y))
			draw_rect(fill, _hp_color(ratio))
		else:
			draw_line(r.position, r.end, C_HP_LO, 1.0)
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), C_HP_LO, 1.0)
		if i == int(duel.active[side]):
			draw_rect(r.grow(1), C_ACCENT, false, 1.0)
	var cd := int(duel.tag_cd[side])
	var lbl := String(tag_labels[side])
	var tx := x + 86.0 if not right else x + 6.0
	if duel.can_tag(side):
		_text(Vector2(tx, 47), "TAG READY" + (" (%s)" % lbl if lbl != "" else ""), 5, Color("9ee6ff"))
	elif cd > 0:
		var total := float(duel.rules.get("tag_cooldown", 300))
		_bar(Rect2(tx, 43, 50, 2), 1.0 - cd / total, Color(0.4, 0.55, 0.7), right)
		_text(Vector2(tx + 54, 47), "TAG", 5, C_DIM)


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

	# The hit count pops each time it goes up, and grows with the combo.
	var pop := float(_combo_pop[side]) / 8.0
	var s := 1.0 + 0.35 * pop * pop + minf(0.25, (int(info["hits"]) - 2) * 0.02)
	var jit := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * pop * 1.5
	draw_set_transform(Vector2(x, 86) + jit, 0.0, Vector2(s, s))
	_text(Vector2.ZERO, "%d HITS" % int(info["hits"]), 14, Color(1, 1, 1, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var mult_txt := "x" + ("1.0" if mult <= 1.0 else String.num(mult, 2))
	_text(Vector2(x + 70 + 20.0 * (s - 1.0), 86), mult_txt, 10, col)
	_text(Vector2(x, 98), "%d damage" % int(round(float(info["dmg"]))), 7, Color(C_DIM.r, C_DIM.g, C_DIM.b, a))

	# Which attack types have landed: mixing all four is the x1.5 bonus.
	var types := int(info.get("types", 0))
	for i in TYPE_PIPS.size():
		var lit := (types & int(SimDefs.TYPE_BIT[TYPE_PIPS[i][0]])) != 0
		var r := Rect2(x + i * 15.0, 102, 13, 8)
		draw_rect(r, Color(col.r, col.g, col.b, a * 0.9) if lit else Color(0.2, 0.22, 0.26, a * 0.8))
		_text(Vector2(r.position.x, r.position.y + 6.5), String(TYPE_PIPS[i][1]), 5,
			Color(0.08, 0.08, 0.1, a) if lit else Color(C_DIM.r, C_DIM.g, C_DIM.b, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if mult >= 1.5:
		_text(Vector2(x + 62, 109), "FULL MIX!", 6, col)


func _draw_caption() -> void:
	var y := 230.0
	draw_rect(Rect2(6, y, SimDefs.VIEW_W - 12, 34), C_PANEL)
	draw_rect(Rect2(6, y, 3, 34), C_ACCENT)
	_text(Vector2(14, y + 11), caption_title, 7, C_ACCENT)
	var size := 7
	var sep := "  >  "
	var total := 0.0
	for i in caption_items.size():
		total += _font.get_string_size(String(caption_items[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if i > 0:
			total += _font.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if total > SimDefs.VIEW_W - 30:
		size = 6
	var x := 14.0
	for i in caption_items.size():
		if i > 0:
			_text(Vector2(x, y + 26), sep, size, C_DIM)
			x += _font.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var item := String(caption_items[i])
		var w := _font.get_string_size(item, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var col := C_DIM
		if i < caption_index:
			col = C_TEXT
		elif i == caption_index:
			col = C_ACCENT
			draw_rect(Rect2(x, y + 28, w, 1), C_ACCENT)
		_text(Vector2(x, y + 26), item, size, col)
		x += w


func _draw_cut_in() -> void:
	var t := float(_cut["t"])
	var side := int(_cut["side"])
	var dir := 1.0 if side == 0 else -1.0
	var w := float(SimDefs.VIEW_W)
	# Short on purpose: it has to be gone by the time the move's startup is worth reading.
	var k_in := clampf(t / 5.0, 0.0, 1.0)
	var k_out := clampf((t - 20.0) / 9.0, 0.0, 1.0)
	var off := -pow(1.0 - k_in, 3.0) * (w + 80.0) * dir + k_out * k_out * (w + 80.0) * dir
	var y0 := 98.0
	var y1 := 152.0
	var accent: Color = _cut["color"]

	var band := PackedVector2Array([Vector2(off - 60, y1), Vector2(off - 20, y0), Vector2(off + w + 60, y0),
		Vector2(off + w + 20, y1)])
	draw_colored_polygon(band, Color(0.04, 0.045, 0.07, 0.92))
	draw_line(Vector2(off - 20, y0), Vector2(off + w + 60, y0), accent, 3.0)
	draw_line(Vector2(off - 60, y1), Vector2(off + w + 20, y1), accent, 3.0)
	for i in 14:  # speed lines rushing through the band
		var ly := y0 + 6.0 + fposmod(i * 17.3, y1 - y0 - 12.0)
		var lx := fposmod(i * 71.0 - t * 22.0 * dir, w + 120.0) - 60.0 + off
		draw_line(Vector2(lx, ly), Vector2(lx + 40.0 + (i % 3) * 18.0, ly), Color(accent, 0.35), 1.0)

	# The portrait breaks out over the top of the band.
	var tex: Texture2D = _cut["tex"]
	var fpx := float(_cut["fpx"])
	var origin: Vector2 = _cut["origin"]
	var sc := 2.6 * minf(1.0, 64.0 / fpx)  # big frames (Craglash's 96 px) scale down to fit
	var feet := Vector2((96.0 if side == 0 else w - 96.0) + off * 1.25, y1 + 6.0)
	draw_set_transform(feet, 0.0, Vector2(sc * dir, sc))
	draw_texture_rect_region(tex, Rect2(-origin.x, -origin.y, fpx, fpx), _cut["region"], Color(0, 0, 0, 0.5))
	draw_set_transform(feet + Vector2(-3.0 * dir, -2.0), 0.0, Vector2(sc * dir, sc))
	draw_texture_rect_region(tex, Rect2(-origin.x, -origin.y, fpx, fpx), _cut["region"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var tx := (170.0 if side == 0 else 20.0) + off
	_text(Vector2(tx, y0 + 18), String(_cut["who"]), 8, accent, HORIZONTAL_ALIGNMENT_LEFT, 290)
	_text(Vector2(tx, y0 + 42), String(_cut["move"]) + "!", 24, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, 290)
	if t < 3.0:
		draw_rect(Rect2(0, 0, w, SimDefs.VIEW_H), Color(1, 1, 1, 0.5 * (1.0 - t / 3.0)))


func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, SimDefs.VIEW_W, SimDefs.VIEW_H), Color(0.05, 0.06, 0.08, 0.82))
	_text(Vector2(0, menu_y0 - 46), "CREATURE ARENA", 24, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)
	_text(Vector2(0, menu_y0 - 31), "prototype build", 7, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)
	if menu_title != "":
		_text(Vector2(0, menu_y0 - 17), menu_title, 9, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)
	var y := menu_y0
	var big := menu_dy >= 18.0
	var fs := 12 if big else (9 if menu_dy >= 15.0 else 8)
	for i in menu_items.size():
		var sel := i == menu_index
		if big:
			# The title menu: wide centred buttons.
			var r := Rect2(150, y - menu_dy + 5, 180, menu_dy - 3)
			draw_rect(r, Color(C_ACCENT, 0.9) if sel else Color(0.07, 0.08, 0.1, 0.75))
			_text(Vector2(r.position.x, y - 2), menu_items[i], fs, Color(0.08, 0.08, 0.1) if sel else C_TEXT,
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		else:
			if sel:
				draw_rect(Rect2(130, y - menu_dy + 4, 220, menu_dy - 1), Color(1, 1, 1, 0.08))
				_text(Vector2(136, y), ">", fs, C_ACCENT)
			_text(Vector2(150, y), menu_items[i], fs, C_ACCENT if sel else C_TEXT)
			if i < menu_values.size() and float(menu_values[i]) >= 0.0:
				var bar := Rect2(298, y - 6, 44, 4)
				draw_rect(bar, C_BAR_BG)
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(menu_values[i]), bar.size.y)),
					C_ACCENT if sel else C_DIM)
				for k in range(1, 10):
					draw_rect(Rect2(bar.position.x + bar.size.x * k / 10.0, bar.position.y, 1, bar.size.y),
						Color(0, 0, 0, 0.35))
		y += menu_dy
	_text(Vector2(0, 232), menu_footer, 6, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, SimDefs.VIEW_W)
	_text(Vector2(0, 244), "Arrows / D-pad / mouse to choose   Left/Right to change   Enter / A / click to start", 6, C_DIM,
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
