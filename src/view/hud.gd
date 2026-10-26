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
const C_DODGE_CD := Color("d58cff")
const C_EXHAUSTED := Color("e5534b")
const C_ENERGY := Color("ffcf3f")
const C_BAR_BG := Color("2a2e38")
const C_ACCENT := Color("ffd166")
const CUT_IN_TICKS := 30
## On very wide screens the health panels stay within this width (centred).
const HUD_MAX_W := 640.0
const TYPE_PIPS := [["light", "LT"], ["heavy", "HV"], ["skill", "SK"], ["surge", "SG"]]
## Training options shown as tags under the dummy's panel (MatchSim.training_flags).
const TRAINING_TAGS := {"no_cooldowns": "NO COOLDOWNS", "full_energy": "SURGE FULL"}

var sim: MatchSim
var duel: DuelSim = null  ## set during a Duel: draws the team strip under each panel
## Set during a team battle (2v2, 3v3): a column of small panels per team instead of
## one big panel per side; `focus` (the local player's slot) keeps the big one.
var team: TeamSim = null
## Set during a Brawl: a card per fighter, two down each edge, in BRAWL_COLORS.
var brawl: BrawlSim = null
var focus := 0
var tag_labels := ["", ""]
var tags := ["P1", "CPU"]
var key_labels := [["", "", ""], ["", "", ""]]
const SIDE_COLORS: Array[Color] = [Color("ff5a5a"), Color("5aa0ff")]
## A Brawl's four fighters, each their own colour.
const BRAWL_COLORS: Array[Color] = [Color("ff5a5a"), Color("5aa0ff"), Color("6fd66f"), Color("ffd166")]
var surge_labels := ["", ""]
var help_text := ""
var show_help := true
var timer_ticks := -1
## Team Deathmatch: the seconds until your fighter is back (-1: you're up).
var respawn_in := -1
var wins := [0, 0]
var wins_needed := 2
var banner := ""
var banner_sub := ""
## The results screen says it itself: the banner stays set (tests, flow) but is not drawn.
var banner_hidden := false
## The match's mutators (Chaos Cup, Daily Challenge), short names beside the clock.
var mutator_text := ""
var dummy_mode_name := ""
## Online: ping, input delay, rollback; drawn small in the bottom corner.
var net_info := ""
## Voice chat (VoiceView): slots speaking now -> level, for the speaker icon by their name;
## `mic_on` while this machine is sending (a red dot and MIC at the bottom left), `mic_missing`
## when voice is on but no microphone is heard (NO MIC).
var speaking := {}
var mic_on := false
var mic_missing := false

# Showcase captions: a title, the chain of moves, and which one is happening now.
var caption_title := ""
var caption_items: Array = []
var caption_index := -1

# Menu
## A menu screen covers the game: draw nothing (the screens dim the match behind).
var menu_visible := false
## The arena intro is playing (ArenaIntro draws its own cards): no panels or banners yet.
var cinema := false
## Button hints for a controller (else keyboard and mouse).
var gamepad := false
## The touch controls are on screen: the bottom corners are under the thumbs, so the
## controls strip goes (the buttons say what they do) and the online line moves to the
## bottom middle, between the stick and the buttons.
var touch := false

var _toast := ""
var _toast_t := 0
## A big moment (a capture): a banner of its own with a coloured band, for a second and a
## half, over whatever banner the flow sets.
var _moment := {}
## An alarm (your flag is taken): the screen's edge pulses in this colour for a while.
var _alert_t := 0
var _alert_col := Color.RED
const ALERT_TICKS := 100
const MOMENT_TICKS := 100
var _combo_show := [0, 0]
var _combo_last := [{}, {}]
var _combo_pop := [0, 0]
## How far each side's combo counter moves down to clear its panels (a 4 v 4's fourth card).
var _combo_dy := [0.0, 0.0]
var _cut := {}
var _tick := 0
var _font: Font:  ## read each draw, so Settings > Video > Text font shows at once
	get: return UiTheme.font()
## Training: damage per second on the dummy, drawn in the dummy's panel (DpsMeter).
var dps := DpsMeter.new()
var _dps_sim: MatchSim = null

## Portrait column beside a full panel, and the bar animation state (all on the 60 Hz tick,
## whole pixels, nothing tweened between ticks).
const PW := 28.0  ## width a portrait takes beside a panel (box 26 + gap 2)
const PORT_W := 24  ## portrait picture area, px
const PORT_H := 32
const HP_W := 150
const CARD_W := 112.0  ## a compact teammate card
const HP_HOLD := 24  ## ticks the "chunk" of a hit stays before it drains
var _hp := {}  ## slot -> [fill px, chunk px, hold ticks]
var _cd_was := {}  ## slot * 3 + box -> was recharging last tick
var _cd_flash := {}  ## slot * 3 + box -> ticks of "ready" flash left
var _bars_sim: MatchSim = null
var _ports := {}  ## sprite path + portrait key -> {tex, src, scale}


## The per-slot labels (tags, key prompts) have one entry per creature slot: 2, or up
## to 6 in a team battle.
func resize_slots(n: int) -> void:
	n = maxi(n, 2)
	while tags.size() < n:
		tags.append("")
		key_labels.append(["", "", ""])
		surge_labels.append("")
		tag_labels.append("")


func show_toast(text: String) -> void:
	_toast = text
	_toast_t = 120


func moment(text: String, sub: String, col: Color) -> void:
	_moment = {"text": text, "sub": sub, "color": col, "t": MOMENT_TICKS}


func alert(col: Color) -> void:
	_alert_col = col
	_alert_t = ALERT_TICKS


## A fighting-game super cut-in: a slanted band with the fighter's portrait and the move.
func cut_in(c: CreatureSim, side: int, move_name: String) -> void:
	var sp: Dictionary = c.def.get("sprite", {})
	if sp.is_empty():
		return
	var fsz = sp.get("frame", 48)  # a size, or [width, height] (Mister Crease's tall frames)
	var fpx := int(fsz[0]) if fsz is Array else int(fsz)
	var fh := int(fsz[1]) if fsz is Array else fpx
	var fr: Array = c.def.get("cut_in_frame", [0, 0])
	var o: Array = sp.get("origin", [24, 43])
	var chained := not _cut.is_empty()  # a second Surge right behind the first: the dark stays up
	_cut = {
		"chain": chained,
		"side": side, "move": move_name.to_upper(), "who": String(c.def.get("name", "")).to_upper(),
		"tex": load(String(sp["path"])), "region": Rect2(int(fr[1]) * fpx, int(fr[0]) * fh, fpx, fh),
		"origin": Vector2(float(o[0]), float(o[1])), "fpx": fpx, "fh": fh,
		"color": Color(String(c.def.get("fx_color", "#ffcf3f"))), "t": 0,
	}


## Whether the Surge cut-in is on screen (main holds the letterbox in until it's gone).
func cutting_in() -> bool:
	return not _cut.is_empty()


func advance() -> void:
	_tick += 1
	if _toast_t > 0:
		_toast_t -= 1
	if _alert_t > 0:
		_alert_t -= 1
	if not _moment.is_empty():
		_moment["t"] = int(_moment["t"]) - 1
		if int(_moment["t"]) <= 0:
			_moment = {}
	if sim != null and sim.creatures.size() >= 2:
		for side in 2:
			var d := _combo_target(side)
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
	_watch_dummy()
	_track_bars()
	if not _cut.is_empty():
		_cut["t"] = int(_cut["t"]) + 1
		if int(_cut["t"]) > CUT_IN_TICKS:
			_cut = {}
	queue_redraw()


## Width a portrait takes beside a panel: none in Team Deathmatch and CTF, where the score
## boxes beside the clock need the room.
func _pw() -> float:
	return 0.0 if team != null and team.deathmatch else PW


## Health bars drain in two parts: the fill drops to the new value at once and the pale
## chunk (what the hit took) waits, then shrinks a whole pixel at a time; a heal ticks the
## fill up. Skill boxes get a short flash when their cooldown ends.
func _track_bars() -> void:
	if sim == null:
		return
	if sim != _bars_sim:
		_bars_sim = sim
		_hp = {}
		_cd_was = {}
		_cd_flash = {}
	for i in sim.creatures.size():
		var c := sim.creatures[i]
		var target := roundi(HP_W * clampf(c.hp / c.max_hp, 0.0, 1.0))
		if not _hp.has(i):
			_hp[i] = [target, target, 0]
		var st: Array = _hp[i]
		var fill: int = st[0]
		var chunk: int = st[1]
		var hold: int = st[2]
		if target < fill:
			chunk = maxi(chunk, fill)
			fill = target
			hold = HP_HOLD
		elif target > fill:
			fill = mini(target, fill + maxi(1, (target - fill) / 8))
			chunk = maxi(chunk, fill)
		if chunk > fill:
			if hold > 0:
				hold -= 1
			else:
				chunk = maxi(fill, chunk - maxi(1, (chunk - fill) / 10))
		st[0] = fill
		st[1] = chunk
		st[2] = hold
		if c.is_dummy:
			continue
		for j in 3:
			var key := i * 3 + j
			var mid := String(["heavy", "skill_1", "skill_2"][j])
			var cooling := c.moves().has(mid) and c.cooldown_ratio(mid) > 0.0
			if _cd_was.get(key, false) and not cooling:
				_cd_flash[key] = 8
			elif int(_cd_flash.get(key, 0)) > 0:
				_cd_flash[key] = int(_cd_flash[key]) - 1
			_cd_was[key] = cooling


## A health bar for slot `slot` in `r` (HP_W px wide): fill, the pale chunk after a hit,
## and a blink when low.
func _hp_bar(r: Rect2, slot: int, right: bool) -> void:
	var c := sim.creatures[slot]
	var st: Array = _hp.get(slot, [0, 0, 0])
	var w := r.size.x
	var fill := roundi(int(st[0]) * w / HP_W)  # tracked in HP_W px, drawn in the bar's own
	var chunk := roundi(int(st[1]) * w / HP_W)
	var ratio := clampf(c.hp / c.max_hp, 0.0, 1.0)
	draw_rect(r.grow(1), Color(0, 0, 0, 0.6))
	draw_rect(r, C_BAR_BG)
	var fx := r.position.x + (w - fill if right else 0.0)
	if chunk > fill:
		var cx := r.position.x + (w - chunk if right else float(fill))
		draw_rect(Rect2(cx, r.position.y, chunk - fill, r.size.y), Color(1, 0.93, 0.8, 0.9))
	if fill > 0:
		var col := _hp_color(ratio)
		if ratio <= 0.25 and ratio > 0.0 and (_tick / 10) % 2 == 0:
			col = col.lightened(0.45)
		draw_rect(Rect2(fx, r.position.y, fill, r.size.y), col)
		if r.size.y > 2:
			draw_rect(Rect2(fx, r.position.y, fill, 1), col.lightened(0.35))


## The head-and-shoulders crop of a fighter's idle frame. `sprite.portrait` [x, y, w, h]
## (frame pixels, at most PORT_W x PORT_H) overrides the default: the top of the picture's
## opaque area, centred on it. Scaled by the biggest whole multiple that fits.
func _portrait_info(c: CreatureSim) -> Dictionary:
	var sp: Dictionary = c.def.get("sprite", {})
	var key := String(sp.get("path", "")) + str(sp.get("portrait", ""))
	if _ports.has(key):
		return _ports[key]
	var info := {}
	if sp.has("path"):
		var tex: Texture2D = load(String(sp["path"]))
		var fr = sp.get("frame", 48)
		var fw := int(fr[0]) if fr is Array else int(fr)
		var fh := int(fr[1]) if fr is Array else int(fr)
		var anim: Array = sp.get("anims", {}).get("idle", [0, 0, 1])
		var frame := Rect2i(int(anim[1]) * fw, int(anim[0]) * fh, fw, fh)
		var src := Rect2i()
		if sp.has("portrait"):
			var pr: Array = sp["portrait"]
			src = Rect2i(frame.position + Vector2i(int(pr[0]), int(pr[1])),
				Vector2i(clampi(int(pr[2]), 1, PORT_W), clampi(int(pr[3]), 1, PORT_H)))
		elif tex != null:
			var img := tex.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				var used := img.get_region(frame).get_used_rect()
				if used.size.x > 0:
					src = Rect2i(frame.position + Vector2i(used.position.x + used.size.x / 2 - PORT_W / 2,
						used.position.y), Vector2i(PORT_W, PORT_H))
		if tex != null and src.size.x > 0:
			var sc := maxi(1, mini(PORT_W / src.size.x, PORT_H / src.size.y))
			info = {"tex": tex, "src": Rect2(src), "scale": sc}
	_ports[key] = info
	return info


func _draw_portrait(c: CreatureSim, x: float, col: Color, right: bool) -> void:
	var down := c.state == CreatureSim.State.KO or c.hp <= 0.0
	draw_rect(Rect2(x, 3, PW - 2.0, 34), col)
	draw_rect(Rect2(x + 1, 4, PORT_W, PORT_H + 1), Color(0.1, 0.11, 0.14))
	var info := _portrait_info(c)
	if not info.is_empty():
		var src: Rect2 = info["src"]
		var sc: float = info["scale"]
		var dw := src.size.x * sc
		var dh := src.size.y * sc
		var dx := x + 1.0 + floorf((PORT_W - dw) / 2.0)
		var dy := 4.0 + floorf((PORT_H - dh) / 2.0)
		if right:  # face the middle
			draw_set_transform(Vector2(dx + dw, dy), 0.0, Vector2(-1, 1))
			draw_texture_rect_region(info["tex"], Rect2(0, 0, dw, dh), src)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect_region(info["tex"], Rect2(dx, dy, dw, dh), src)
	if down:
		draw_rect(Rect2(x + 1, 4, PORT_W, PORT_H + 1), Color(0, 0, 0, 0.6))


## Training: feeds the dummy's health to the DPS meter (a new match starts it over).
func _watch_dummy() -> void:
	if sim == null or not sim.training:
		return
	if sim != _dps_sim:
		_dps_sim = sim
		dps.reset()
	for c in sim.creatures:
		if c.is_dummy:
			dps.observe(c.hp, sim.tick)
			return


## Whose combo side `side` is building: the foe taking the longest combo right now (in a
## 1v1 or a Duel, simply the other fighter).
func _combo_target(side: int) -> CreatureSim:
	var best: CreatureSim = null
	for c in sim.creatures:
		if c.team == side:
			continue
		if best == null or c.combo_hits > best.combo_hits:
			best = c
	return best if best != null else sim.creatures[1 - side]


## The screen's size (wider than 480 on ultrawide monitors, taller on 16:10) and where
## things anchor: the health panels sit at the edges of a HUD area at most HUD_MAX_W
## wide (no glancing to the corners of a 32:9 screen), centred things on the centre.
var _sw := float(SimDefs.VIEW_W)
var _sh := float(SimDefs.VIEW_H)
var _hl := 0.0  ## left edge of the HUD area
var _hr := float(SimDefs.VIEW_W)  ## right edge
var _cx := 0.0  ## how far the screen's centre moved right of a 480-wide screen's
var _cy := 0.0  ## and down


func _layout() -> void:
	var vs := get_viewport_rect().size
	_sw = maxf(vs.x, 1.0)
	_sh = maxf(vs.y, 1.0)
	var hw := minf(_sw, HUD_MAX_W)
	_hl = (_sw - hw) * 0.5
	_hr = _hl + hw
	_cx = (_sw - SimDefs.VIEW_W) * 0.5
	_cy = (_sh - SimDefs.VIEW_H) * 0.5


func _draw() -> void:
	var t0 := PerfLog.now()
	_draw_now()
	PerfLog.since("hud draw", t0)


func _draw_now() -> void:
	_layout()
	if menu_visible or cinema:
		return
	if sim == null or sim.creatures.size() < 2:
		return
	if not _cut.is_empty():
		_draw_cut_in_dim()
	_combo_dy = [0.0, 0.0]
	_draw_panels()
	_center()
	_draw_pointers()
	for side in 2:
		if _combo_show[side] > 0:
			_combo(side)
	if caption_title != "":
		_draw_caption()
	if not _cut.is_empty():
		_draw_cut_in()

	if banner != "" and not banner_hidden:
		var y := 128.0 + _cy
		draw_rect(Rect2(0, y - 22, _sw, 34 if banner_sub == "" else 46), Color(0, 0, 0, 0.45))
		_text(Vector2(0, y), banner, 20, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, _sw)
		if banner_sub != "":
			_text(Vector2(0, y + 16), banner_sub, 8, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, _sw)

	if not _moment.is_empty():
		_draw_moment()
	if _alert_t > 0:
		_draw_alert()

	if _toast_t > 0:
		var a := minf(1.0, _toast_t / 20.0)
		_text(Vector2(_sw * 0.5 - 150.0, _sh - 34.0), _toast, 8, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 300)

	if net_info != "" and touch:
		_text(Vector2(_sw * 0.5 - 100.0, _sh - 4.0), net_info, 5, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 200)
	elif net_info != "":
		_text(Vector2(_hr - 404, _sh - 15.0), net_info, 6, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 400)  # room for a long map name

	if mic_on or mic_missing:
		_draw_mic()

	if show_help and not touch:
		draw_rect(Rect2(0, _sh - 11.0, _sw, 11), C_PANEL)
		_text(Vector2(0, _sh - 3.0), help_text, 5, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, _sw)


## Voice chat: a red dot and MIC while this machine sends, NO MIC (dim) when voice is on
## and nothing is heard from the microphone. Bottom left, on the net line's row.
func _draw_mic() -> void:
	var y := _sh - 4.0 if touch else _sh - 15.0
	var x := _hl + 6.0
	if mic_on:
		draw_rect(Rect2(x, y - 4.0, 3, 3), Color("e5534b"))
		_text(Vector2(x + 5.0, y), "MIC", 6 if not touch else 5, C_TEXT)
	else:
		_text(Vector2(x, y), "NO MIC", 6 if not touch else 5, C_DIM)


## The speaker icon after a name drawn at `x` (its left edge) of `size`, while that slot talks.
func _speaker_after(slot: int, name: String, x: float, y: float, size: int) -> void:
	if not speaking.has(slot):
		return
	var w := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(size)).x
	VoiceView.draw_glyph(self, Vector2(x + w + 3.0, y), float(speaking[slot]), C_TEXT)


## A capture: a slanted band in the side's colour across the middle, the words over it,
## sliding in and fading out.
func _draw_moment() -> void:
	var t := int(_moment["t"])
	var age := MOMENT_TICKS - t
	var a := minf(1.0, minf(float(age) / 6.0, float(t) / 15.0))
	var col: Color = _moment["color"]
	var y := 96.0 + _cy
	var slide := maxf(0.0, 1.0 - float(age) / 8.0) * 60.0
	var band := PackedVector2Array([Vector2(-slide, y - 18), Vector2(_sw + 20 - slide, y - 24),
		Vector2(_sw + 20 - slide, y + 14), Vector2(-slide, y + 20)])
	draw_colored_polygon(band, Color(col.darkened(0.55), 0.8 * a))
	draw_rect(Rect2(0, y - 20, _sw, 2), Color(col, a))
	draw_rect(Rect2(0, y + 16, _sw, 2), Color(col, a))
	_text(Vector2(0, y + 2), String(_moment["text"]), 20, Color(col.lightened(0.4), a), HORIZONTAL_ALIGNMENT_CENTER, _sw)
	_text(Vector2(0, y + 13), String(_moment["sub"]), 9, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, _sw)


## Your flag is taken: the screen's edge pulses red (or your side's colour), fading out.
func _draw_alert() -> void:
	var fade := float(_alert_t) / float(ALERT_TICKS)
	var pulse := 0.55 + 0.45 * sin(float(_tick) * 0.35)
	var a := 0.75 * fade * pulse
	for i in 10:
		var w := 10.0 - float(i)
		var c := Color(_alert_col, a * (1.0 - float(i) / 10.0))
		draw_rect(Rect2(0, 0, _sw, w), c)
		draw_rect(Rect2(0, _sh - w, _sw, w), c)
		draw_rect(Rect2(0, 0, w, _sh), c)
		draw_rect(Rect2(_sw - w, 0, w, _sh), c)


## Team battle: each team down its own edge. The local player's fighter gets the full
## panel (skills, Surge, stamina); everyone else a small card: name, health, energy.
const LOCAL_TAGS := ["P1", "P2", "P3", "P4"]  ## the tags a person at this screen or its pads has


## Slots a person here plays: their panel tag is P1..P4. Empty when nobody does (a replay,
## spectating, a demo, a CPU match): then every panel shows.
func _locals() -> Array:
	var out := []
	for i in sim.creatures.size():
		if i < tags.size() and LOCAL_TAGS.has(String(tags[i])):
			out.append(i)
	return out


## Which panels show. Where a side has several fighters (team battles, Deathmatch, Caravan,
## CTF, Brawl, Duel's tag teams) you see your own side only: `panel[col]` is the slot with
## the full panel in the left (0) or right (1) column (-1 none) and `cards[col]` the slots
## with a compact card under it. Local players on different sides each keep a full panel
## (the focus's, plus the first local on the other side); a second local on the same side is
## a card. Nobody local (replay, spectating, demo): both sides, as before. A plain 1v1
## shows both panels. Enemies keep the small bars over their heads in the world.
func panel_plan() -> Dictionary:
	var panel := [-1, -1]
	var cards := [[], []]
	if sim == null:
		return {"panel": panel, "cards": cards}
	var loc := _locals()
	var all := loc.is_empty()
	var n := sim.creatures.size()
	if team != null:
		for side in 2:
			var mine := []
			for i in n:
				if sim.creatures[i].team == side:
					mine.append(i)
			var has_local := false
			for i in mine:
				has_local = has_local or loc.has(i)
			if not all and not has_local:
				continue
			var p := -1
			if mine.has(focus):
				p = focus
			elif not all:
				for i in mine:
					if loc.has(i):
						p = i
						break
			panel[side] = p
			for i in mine:
				if i != p:
					cards[side].append(i)
	elif brawl != null:
		for col in 2:
			var slots := []
			for sl in [col * 2, col * 2 + 1]:
				if sl < n:
					slots.append(sl)
			var p := -1
			if slots.has(focus):
				p = focus
			else:
				for sl in slots:
					if loc.has(sl):
						p = sl
						break
			panel[col] = p
			for sl in slots:
				if sl != p and (all or loc.has(sl)):
					cards[col].append(sl)
	elif duel != null:
		for side in 2:
			if all or loc.has(side):
				panel[side] = side
	else:
		panel = [0, 1]
	return {"panel": panel, "cards": cards}


func _draw_panels() -> void:
	var plan := panel_plan()
	for col in 2:
		var right := col == 1
		var x := _hl + 4.0 if not right else _hr - 164.0
		var y := 3.0
		var slot := int(plan["panel"][col])
		if slot >= 0:
			if team != null or brawl != null or duel != null:
				x += -_pw() if right else _pw()
			else:
				x += -PW if right else PW
			var cs := -1
			if team != null:
				cs = col
			elif brawl != null:
				cs = slot % 2
			_panel(slot, x, right, cs)
			y = 39.0
		for i in plan["cards"][col]:
			_card(int(i), x, y, right)
			y += 13.0
		if team != null:
			_combo_dy[col] = maxf(0.0, y - 74.0)


## A teammate (or second local player): a name, a slim health bar and a Surge pip.
func _card(slot: int, x: float, y: float, right: bool) -> void:
	var c := sim.creatures[slot]
	var down := c.state == CreatureSim.State.KO or c.hp <= 0.0
	var w := CARD_W
	var cx := x if not right else x + 160.0 - w
	draw_rect(Rect2(cx, y, w, 12), C_PANEL)
	var stripe := BRAWL_COLORS[slot % BRAWL_COLORS.size()] if brawl != null else SIDE_COLORS[clampi(c.team, 0, 1)]
	draw_rect(Rect2(cx if not right else cx + w - 2.0, y, 2, 12), stripe)
	var name := String(c.def.get("name", "?")).to_upper()
	_text(Vector2(cx + 5, y + 6), name, 5, C_DIM if down else C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 30.0)
	_speaker_after(slot, name, cx + 5, y + 4, 5)
	if down:
		var down_txt := "K.O."
		if team != null and team.deathmatch and slot < team.respawn_t.size() and int(team.respawn_t[slot]) > 0:
			down_txt = "BACK IN %d" % ceili(int(team.respawn_t[slot]) / 60.0)
		_text(Vector2(cx + 5, y + 6), down_txt, 5, C_HP_LO, HORIZONTAL_ALIGNMENT_RIGHT, w - 10.0)
		draw_rect(Rect2(cx + 5, y + 8, w - 10.0, 2), C_BAR_BG)
		return
	if c.energy >= CreatureSim.MAX_ENERGY:  # a Surge is ready: a blinking pip
		draw_rect(Rect2(cx + w - 9.0, y + 2, 4, 4), Color.WHITE if (_tick / 8) % 2 == 0 else C_ENERGY)
	_hp_bar(Rect2(cx + 5, y + 8, w - 10.0, 2), slot, right)


## `side` is a creature slot; `color_side` picks the stripe (its team in a team battle).
## Training: the options that are on (the sim's training flags), as small tags under the
## dummy's panel, right-aligned to `right_x`.
func _training_tags(right_x: float) -> void:
	if not sim.training:
		return
	var font := _font
	var x := right_x
	for k in ["full_energy", "no_cooldowns"]:  # right to left
		if not sim.training_flags.get(k, false):
			continue
		var txt := String(TRAINING_TAGS[k])
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(5)).x + 6.0
		x -= w
		draw_rect(Rect2(x, 39, w, 8), C_PANEL)
		draw_rect(Rect2(x, 39, 1, 8), C_ENERGY if k == "full_energy" else C_STAMINA)
		_text(Vector2(x + 3, 45), txt, 5, C_TEXT)
		x -= 3.0


## Training: the DPS meter in the dummy's panel, where a fighter's skill boxes would be:
## the burst's damage per second, then its total and length; dimmed once it has ended.
func _dps(x: float, w: float) -> void:
	if not dps.has_burst():
		_text(Vector2(x, 29), "DPS -", 6, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, w)
		return
	var live := dps.active()
	_text(Vector2(x, 29), "DPS %.1f" % dps.dps(), 6, C_ACCENT if live else C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, w)
	_text(Vector2(x, 36), "%d dmg  %.1f s" % [roundi(dps.total), dps.seconds()], 5,
		C_TEXT if live else C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, w)


func _panel(side: int, x: float, right: bool, color_side := -1) -> void:
	var c := sim.creatures[side]
	draw_rect(Rect2(x, 3, 160, 34), C_PANEL)
	# red left, blue right, like the markers
	var team_col: Color = SIDE_COLORS[side if color_side < 0 else color_side]
	draw_rect(Rect2(x, 3, 160, 2), team_col)
	if _pw() > 0.0:
		_draw_portrait(c, x + 162.0 if right else x - PW, team_col, right)
	var name := String(c.def.get("name", "?")).to_upper()
	var tag := String(tags[side])
	if c.is_dummy:
		tag = "F2: " + dummy_mode_name
		_training_tags(x + 160.0)
		if sim.training:
			_dps(x + 108.0, 46.0)
	_text(Vector2(x + 5, 12), name, 7, C_TEXT)
	_speaker_after(side, name, x + 5, 9, 7)
	_text(Vector2(x + 5, 12), tag, 6, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 150)
	# Health is also over the fighter (FxView's bars); the panel keeps a slim copy that
	# drains with the chunk. A shield (Stoneskin) still says so by name.
	if c.shield > 0.0:
		var shield_name := String(c.def.get("stoneskin", {}).get("name", "Stoneskin")).to_upper()
		_text(Vector2(x + 5, 12), shield_name + "  ", 5, Color("d8d4cc"), HORIZONTAL_ALIGNMENT_RIGHT, 118)
	if duel != null:
		_team_strip(side, x, right)

	# Energy, with a pulse when a Surge is ready.
	var full := c.energy >= CreatureSim.MAX_ENERGY
	var ecol := C_ENERGY
	if full and (_tick / 8) % 2 == 0:
		ecol = Color.WHITE
	_hp_bar(Rect2(x + 5, 15, HP_W, 3), side, right)
	_bar(Rect2(x + 5, 23, 100, 4), _steps(c.energy / CreatureSim.MAX_ENERGY), ecol, right)
	if full and (_tick / 8) % 2 == 0:  # a gold frame blinks with the white bar
		draw_rect(Rect2(x + 4, 22, 102, 6), C_ENERGY, false, 1.0)
	_bar(Rect2(x + 5, 30, 60, 2), c.stamina / c.max_stamina, C_STAMINA, right)
	# Exhausted (0 stamina): no guard until regen starts again; the empty bar blinks red
	# inside a red frame.
	if c.is_exhausted():
		draw_rect(Rect2(x + 4, 29, 62, 4), C_EXHAUSTED, false, 1.0)
		if (_tick / 8) % 2 == 0:
			draw_rect(Rect2(x + 5, 30, 60, 2), C_EXHAUSTED)
	# A dodge with a cooldown (Chef Cerebro's blink): a short violet bar beside the stamina
	# bar drains away while it recharges.
	var dcd := c.dodge_cooldown_ratio()
	if dcd > 0.0:
		_bar(Rect2(x + 70, 30, 30, 2), dcd, C_DODGE_CD, right)
	if full:
		var ready_txt := "SURGE READY" + (" (%s)" % surge_labels[side] if String(surge_labels[side]) != "" else "")
		var pulse: Color = [C_ENERGY, Color("fff0a8"), Color.WHITE, Color("fff0a8")][(_tick / 5) % 4]
		_text(Vector2(x + 5, 35), ready_txt, 5, pulse,
			HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT, 100 if not right else 100)

	# Cairn's stones.
	var stack_def: Dictionary = c.def.get("stack", {})
	if not stack_def.is_empty():
		for i in int(stack_def["max"]):
			var px := x + 70.0 + i * 8.0
			var pts := PackedVector2Array([Vector2(px, 28), Vector2(px + 3, 31), Vector2(px, 34), Vector2(px - 3, 31)])
			draw_colored_polygon(pts, Color("c8bfae") if i < c.stack else Color(0.3, 0.32, 0.36))

	# Paper Stock (Mister Crease): a pip per sheet. A folded craft shows as a paper corner
	# on its button's box below.
	var sheet_def: Dictionary = c.def.get("sheets", {})
	if not sheet_def.is_empty():
		for i in int(sheet_def["max"]):
			var px := x + 70.0 + i * 7.0
			var pts := PackedVector2Array([Vector2(px, 28), Vector2(px + 3, 31), Vector2(px, 34), Vector2(px - 3, 31)])
			draw_colored_polygon(pts, Color("f4f0e4") if i < c.sheets else Color(0.3, 0.32, 0.36))

	# The Heavy and skill buttons: a box each with its key, filling as a cooldown runs out.
	if not c.is_dummy:
		for i in 3:
			var mid := String(["heavy", "skill_1", "skill_2"][i])
			if not c.moves().has(mid):
				continue
			var r := Rect2(x + 110 + i * 16, 23, 14, 11)
			var ready := c.can_use(mid)
			draw_rect(r, Color(0.16, 0.18, 0.22))
			var cd := c.cooldown_ratio(mid)
			if cd <= 0.0:
				draw_rect(r, Color("4f7a5a") if ready else Color(0.3, 0.33, 0.38))
			else:  # recharging: the box fills from the bottom a whole row at a time
				var rows := floorf(r.size.y * (1.0 - cd))
				if rows > 0.0:
					draw_rect(Rect2(r.position.x, r.end.y - rows, r.size.x, rows), Color(0.3, 0.36, 0.44))
					draw_rect(Rect2(r.position.x, r.end.y - rows, r.size.x, 1), Color(0.5, 0.58, 0.68))
			var fl := int(_cd_flash.get(side * 3 + i, 0))
			if fl > 0:  # ready again: a stepped flash
				draw_rect(r, Color(1, 1, 1, 0.85 if fl % 2 == 0 else 0.4))
			draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)
			var lbl := String(key_labels[side][i])
			if lbl == "":
				lbl = ["HV", "S1", "S2"][i]
			_text(Vector2(r.position.x, r.position.y + 8), lbl, 6, C_TEXT if ready else C_DIM,
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			if c.folded.has(mid):  # folded and in hand: a paper corner on its box
				draw_colored_polygon(PackedVector2Array([r.position + Vector2(r.size.x - 6, 0),
					r.position + Vector2(r.size.x, 0), r.position + Vector2(r.size.x, 6)]), Color("f4f0e4"))


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
	var secs := int(ceil(timer_ticks / 60.0))
	var low := secs <= 10 and timer_ticks > 0
	var tock := low and timer_ticks % 60 >= 52  # the beat after each second turns over
	draw_rect(Rect2(218 + _cx, 3, 44, 24), C_PANEL)
	if tock:
		draw_rect(Rect2(217 + _cx, 2, 46, 26), Color(C_HP_LO.r, C_HP_LO.g, C_HP_LO.b, 0.45))
	var tcol := C_TEXT
	if low:
		tcol = Color.WHITE if (timer_ticks / 15) % 2 == 0 else C_HP_LO
	_text(Vector2(218 + _cx, 22 if low else 19), str(secs), 17 if low else 13, tcol, HORIZONTAL_ALIGNMENT_CENTER, 44)
	if team != null and team.deathmatch:
		_deathmatch_score()
	elif team != null:
		_team_goal()
	elif brawl != null and brawl.crown_on:
		_crown_points()
	if mutator_text != "":
		_text(Vector2(140 + _cx, 52), mutator_text, 5, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 200)
	for side in 2:
		for i in wins_needed:
			var px := 232.0 + _cx + (i * 7.0 if side == 1 else -i * 7.0) + (14.0 if side == 1 else 0.0)
			var won := i < int(wins[side])
			draw_circle(Vector2(px, 32), 2.5, C_ACCENT if won else Color(0.25, 0.27, 0.3))


## The Brawl crown under the clock: each fighter's crown points in its colour (the holder's
## with a little crown, standing fighters only), or what takes the crown while nobody wears it.
func _crown_points() -> void:
	var shown: Array = []
	for i in brawl.slot_count():
		if brawl.crown == i or (brawl.crown_points(i) > 0 and brawl.alive(i)):
			shown.append(i)
	if shown.is_empty():
		_text(Vector2(184 + _cx, 34), "NEXT KO TAKES THE CROWN", 5, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 112)
		return
	var w := 36.0
	var x0 := 240.0 + _cx - w * shown.size() * 0.5
	for k in shown.size():
		var i := int(shown[k])
		var x := x0 + w * k
		var col := BRAWL_COLORS[i % BRAWL_COLORS.size()]
		draw_rect(Rect2(x, 29, w - 2, 13), C_PANEL)
		draw_rect(Rect2(x, 29, w - 2, 1), col)
		if brawl.crown == i:
			var g := Color("ffd84a")
			draw_rect(Rect2(x + 3, 37, 9, 3), g)
			draw_rect(Rect2(x + 3, 32, 1, 5), g)
			draw_rect(Rect2(x + 7, 31, 1, 6), g)
			draw_rect(Rect2(x + 11, 32, 1, 5), g)
			draw_rect(Rect2(x + 4, 35, 7, 2), g)
		else:
			draw_rect(Rect2(x + 4, 33, 6, 6), col)
		_text(Vector2(x + 14, 40), str(brawl.crown_points(i)), 8, col, HORIZONTAL_ALIGNMENT_LEFT, w - 15)


## Team battle and Sinkhole: what wins, and for the Sinkhole the ring the edge is on and
## how long until the next crack.
func _team_goal() -> void:
	_text(Vector2(184 + _cx, 34), team.goal_text(), 5, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 112)
	if team.sinkhole:
		var rings := int(team.rules.get("max_rings", 16))
		var total := float(team.rules.get("shrink_warn", 120) if team.warned else team.rules.get("shrink_every", 420))
		var left := clampf(float(team.sink_t) / maxf(total, 1.0), 0.0, 1.0)
		if team.ring >= rings:
			_text(Vector2(184 + _cx, 42), "THE EDGE HOLDS", 5, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 112)
			return
		_bar(Rect2(204 + _cx, 38, 72, 2), 1.0 - left, C_HP_LO if team.warned else C_ACCENT)
		_text(Vector2(184 + _cx, 47), ("CRACKING!   " if team.warned else "") + "RING %d / %d" % [team.ring + 1, rings], 5,
			C_HP_LO if team.warned else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 112)


## Team Deathmatch: each team's KOs either side of the clock, what wins, and your respawn.
func _deathmatch_score() -> void:
	for side in 2:
		var x := 218.0 + _cx + (-34.0 if side == 0 else 46.0)
		draw_rect(Rect2(x, 3, 32, 24), C_PANEL)
		draw_rect(Rect2(x, 3, 32, 2), SIDE_COLORS[side])
		_text(Vector2(x, 21), team.score_text(side), 13, SIDE_COLORS[side], HORIZONTAL_ALIGNMENT_CENTER, 32)
	_text(Vector2(184 + _cx, 34), team.goal_text(), 5, C_ACCENT if team.overtime else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 112)
	if team.caravan:
		_caravan_bar()
	if respawn_in > 0:
		_text(Vector2(0, 62 + _cy), "BACK IN %d" % respawn_in, 10, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, _sw)


## Caravan: the track as a strip under the clock (red's end left, blue's right), the
## checkpoints this round, the caravan, and in round two the mark to beat (round one's push).
func _caravan_bar() -> void:
	var x0 := 190.0 + _cx
	var w := 100.0
	var y := 41.0
	var L := maxf(team.track_length(), 1.0)
	var att := team.cv_attacker()
	draw_rect(Rect2(x0 - 2, y - 3, w + 4, 7), C_PANEL)
	draw_rect(Rect2(x0, y, w, 1), Color(0.55, 0.5, 0.42))
	draw_rect(Rect2(x0 - 1, y - 2, 2, 5), SIDE_COLORS[0])
	draw_rect(Rect2(x0 + w - 1, y - 2, 2, 5), SIDE_COLORS[1])
	var cps: Array = team.rules.get("checkpoints", [])
	for i in cps.size():
		var f := float(cps[i]) if att == 0 else 1.0 - float(cps[i])
		draw_rect(Rect2(x0 + w * f, y - 1, 1, 3), C_ACCENT if i < team.cv_cp else C_DIM)
	if team.cv_round == 1 and int(team.cv_time[0]) < 0:
		var f0 := 1.0 - float(team.cv_best[0]) / L
		draw_rect(Rect2(x0 + w * f0, y - 3, 1, 7), Color("e8c060"))
	var f := team.cv_p / L if att == 0 else 1.0 - team.cv_p / L
	var mx := x0 + w * f
	draw_colored_polygon(PackedVector2Array([Vector2(mx - 3, y - 3), Vector2(mx + 3, y - 3), Vector2(mx, y + 1)]), SIDE_COLORS[att])


## Objectives off the screen on a big map (set by main each frame): an arrow at the screen's
## edge pointing at each, in its colour, with a word. Each {"pos" (screen), "dir", "color",
## "label"}.
var pointers: Array = []


func _draw_pointers() -> void:
	for p in pointers:
		var at: Vector2 = p["pos"]
		var d: Vector2 = p["dir"]
		var col: Color = p["color"]
		var side := Vector2(-d.y, d.x)
		var tip := at + d * 7.0
		var pts := PackedVector2Array([tip, at - d * 3.0 + side * 6.0, at - d * 3.0 - side * 6.0])
		draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
		var inner := PackedVector2Array([tip - d * 1.5, at - d * 2.0 + side * 4.0, at - d * 2.0 - side * 4.0])
		draw_colored_polygon(inner, col)
		_text(at - d * 14.0 + Vector2(-30, 3), String(p.get("label", "")), 5, col, HORIZONTAL_ALIGNMENT_CENTER, 60)


## The count's colour by combo size: white, then warmer and warmer.
func _combo_color(hits: int) -> Color:
	if hits >= 13:
		return Color("ff5a3c")
	if hits >= 9:
		return Color("ff8a3c")
	if hits >= 6:
		return Color("ffc85a")
	if hits >= 4:
		return Color("fff0b0")
	return Color.WHITE


func _combo(side: int) -> void:
	var info: Dictionary = _combo_last[side]
	if info.is_empty():
		return
	var a := minf(1.0, _combo_show[side] / 15.0)
	var x := _hl + 8.0 if side == 0 else _hr - 128.0
	var dy: float = _combo_dy[side]
	var mult := float(info["mult"])
	var col := C_ACCENT
	if mult >= 1.5:
		col = Color("ff9a5a")
	col.a = a

	# Each new hit kicks the count: a font step up and a 1 px lift for a few ticks, then it
	# settles (whole-pixel steps, no tweening). Its colour warms as the combo grows.
	var hits := int(info["hits"])
	var kick: int = _combo_pop[side]
	var big := kick > 5
	var ccol := _combo_color(hits)
	ccol.a = a
	var lift := -2.0 if big else (-1.0 if kick > 0 else 0.0)
	_text(Vector2(x, 86 + dy + lift), "%d HITS" % hits, (18 if UiTheme.smooth else 20) if big else 14, ccol)
	var mult_txt := "x" + ("1.0" if mult <= 1.0 else String.num(mult, 2))
	_text(Vector2(x + 70 + (8.0 if big else 0.0), 86 + dy), mult_txt, 10, col)
	_text(Vector2(x, 98 + dy), "%d damage" % int(round(float(info["dmg"]))), 7, Color(C_DIM.r, C_DIM.g, C_DIM.b, a))

	# Which attack types have landed: mixing all four is the x1.5 bonus.
	var types := int(info.get("types", 0))
	for i in TYPE_PIPS.size():
		var lit := (types & int(SimDefs.TYPE_BIT[TYPE_PIPS[i][0]])) != 0
		var r := Rect2(x + i * 15.0, 102 + dy, 13, 8)
		draw_rect(r, Color(col.r, col.g, col.b, a * 0.9) if lit else Color(0.2, 0.22, 0.26, a * 0.8))
		_text(Vector2(r.position.x, r.position.y + 6.5), String(TYPE_PIPS[i][1]), 5,
			Color(0.08, 0.08, 0.1, a) if lit else Color(C_DIM.r, C_DIM.g, C_DIM.b, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if mult >= 1.5:
		_text(Vector2(x + 62, 109 + dy), "FULL MIX!", 6, col)


func _draw_caption() -> void:
	var y := _sh - 40.0
	var left := _hl
	var cw := _hr - _hl
	draw_rect(Rect2(left + 6, y, cw - 12, 34), C_PANEL)
	draw_rect(Rect2(left + 6, y, 3, 34), C_ACCENT)
	_text(Vector2(left + 14, y + 11), caption_title, 7, C_ACCENT)
	var size := 7
	var sep := "  >  "
	var total := 0.0
	for i in caption_items.size():
		total += _font.get_string_size(String(caption_items[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(size)).x
		if i > 0:
			total += _font.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(size)).x
	if total > cw - 30:
		size = 6
	var x := left + 14.0
	for i in caption_items.size():
		if i > 0:
			_text(Vector2(x, y + 26), sep, size, C_DIM)
			x += _font.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(size)).x
		var item := String(caption_items[i])
		var w := _font.get_string_size(item, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(size)).x
		var col := C_DIM
		if i < caption_index:
			col = C_TEXT
		elif i == caption_index:
			col = C_ACCENT
			draw_rect(Rect2(x, y + 28, w, 1), C_ACCENT)
		_text(Vector2(x, y + 26), item, size, col)
		x += w


## The arena goes dark behind a Surge cut-in (drawn first, so the panels stay bright).
func _draw_cut_in_dim() -> void:
	var t := int(_cut["t"])
	var k := clampf((t + (4 if _cut.get("chain", false) else 0)) / 4.0, 0.0, 1.0) * (1.0 - clampf((t - 22) / 8.0, 0.0, 1.0))
	# Four whole steps, so it stays a crisp flat tone rather than a smooth fade.
	draw_rect(Rect2(0, 0, _sw, _sh), Color(0.0, 0.0, 0.04, floorf(k * 4.0) / 4.0 * 0.6))


func _draw_cut_in() -> void:
	var ti := int(_cut["t"])
	var t := float(ti)
	var side := int(_cut["side"])
	var dir := 1.0 if side == 0 else -1.0
	var w := _sw
	# Short on purpose: it has to be gone by the time the move's startup is worth reading.
	var k_in := clampf(t / 5.0, 0.0, 1.0)
	var k_out := clampf((t - 20.0) / 9.0, 0.0, 1.0)
	var off := roundf(-pow(1.0 - k_in, 3.0) * (w + 80.0) * dir + k_out * k_out * (w + 80.0) * dir)
	var y0 := 98.0 + _cy
	var y1 := 152.0 + _cy
	var accent: Color = _cut["color"]
	var hot := accent.lerp(Color.WHITE, 0.55)

	var band := PackedVector2Array([Vector2(off - 60, y1), Vector2(off - 20, y0), Vector2(off + w + 60, y0),
		Vector2(off + w + 20, y1)])
	draw_colored_polygon(band, Color(0.04, 0.045, 0.07, 0.92))
	draw_line(Vector2(off - 20, y0), Vector2(off + w + 60, y0), accent, 3.0)
	draw_line(Vector2(off - 60, y1), Vector2(off + w + 20, y1), accent, 3.0)
	# Speed streaks in the fighter's colour, in whole pixels: long ones sweep the band, and
	# a few run on past it, behind the portrait.
	for i in 22:
		var wide := i >= 14
		var ly := roundf((y0 - 14.0 if wide else y0 + 6.0) + fposmod(i * 17.3, (y1 - y0 + 28.0) if wide else (y1 - y0 - 12.0)))
		var len := 40.0 + (i % 3) * 18.0 + (50.0 if wide else 0.0)
		var lx := roundf(fposmod(i * 71.0 - t * (30.0 if wide else 22.0) * dir, w + 160.0) - 80.0 + off)
		var a := 0.55 if i % 4 == 0 else 0.3
		draw_rect(Rect2(lx if dir > 0.0 else lx - len, ly, len, 2.0 if i % 5 == 0 else 1.0), Color(hot if i % 4 == 0 else accent, a))

	# The portrait breaks out over the top of the band.
	var tex: Texture2D = _cut["tex"]
	var fpx := float(_cut["fpx"])
	var fh := float(_cut.get("fh", fpx))
	var origin: Vector2 = _cut["origin"]
	var sc := maxf(1.0, roundf(2.6 * minf(1.0, 64.0 / fpx)))  # whole multiples only; Craglash's 96 px drops to 2x
	var feet := Vector2(roundf(_cx + (96.0 if side == 0 else SimDefs.VIEW_W - 96.0) + off * 1.25), roundf(y1 + 6.0))
	# Colour-keyed glow: the sprite once more in the accent, offset a step behind.
	draw_set_transform(feet + Vector2(-6.0 * dir, 0.0), 0.0, Vector2(sc * dir, sc))
	draw_texture_rect_region(tex, Rect2(-origin.x, -origin.y, fpx, fh), _cut["region"], Color(accent, 0.55))
	draw_set_transform(feet, 0.0, Vector2(sc * dir, sc))
	draw_texture_rect_region(tex, Rect2(-origin.x, -origin.y, fpx, fh), _cut["region"], Color(0, 0, 0, 0.5))
	draw_set_transform(feet + Vector2(-3.0 * dir, -2.0), 0.0, Vector2(sc * dir, sc))
	draw_texture_rect_region(tex, Rect2(-origin.x, -origin.y, fpx, fh), _cut["region"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var tx := roundf(_cx + (170.0 if side == 0 else 20.0) + off)
	_text(Vector2(tx, y0 + 18), String(_cut["who"]), 8, accent, HORIZONTAL_ALIGNMENT_LEFT, 290)
	# The move's name slams in: big, then three steps down to its size, held, then out with the band.
	var name_s := String(_cut["move"]) + "!"
	var steps := [0, 0, 40, 40, 32, 32, 28, 28]  # size by tick from t=0; 0 = not yet
	var ns := 24 if ti >= steps.size() else int(steps[ti])
	if ns > 0:
		ns = mini(ns, _fit_size(name_s, ns, 290.0))
		var slam := 0.0 if ti >= 8 else 1.0 - ti / 8.0
		_text(Vector2(tx, y0 + 42 + roundf(slam * 3.0)), name_s, ns, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, 290)
	# Entry: a screen tear, torn strips of the frame shoved sideways by whole pixels, then a flash.
	if ti < 6:
		for i in 7:
			var sy := roundf(fposmod(i * 37.0 + ti * 53.0, _sh - 8.0))
			var sh := 3.0 + (i % 3) * 3.0
			var sx := roundf((12.0 + (i * 13) % 40) * (1.0 - t / 6.0)) * (dir if i % 2 == 0 else -dir)
			draw_rect(Rect2(sx, sy, _sw, sh), Color(hot, 0.28))
			draw_rect(Rect2(sx, sy, _sw, 1.0), Color(1, 1, 1, 0.5))
	if ti < 3:
		draw_rect(Rect2(0, 0, w, _sh), Color(1, 1, 1, 0.5 * (1.0 - t / 3.0)))


## The biggest size at most `size` where `s` fits `width` (so a long move name still lands whole).
func _fit_size(s: String, size: int, width: float) -> int:
	while size > 24 and _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(size)).x > width:
		size -= 4
	return size


func _bar(r: Rect2, ratio: float, col: Color, from_right := false) -> void:
	draw_rect(r.grow(1), Color(0, 0, 0, 0.6))
	draw_rect(r, C_BAR_BG)
	var w: float = round(r.size.x * clampf(ratio, 0.0, 1.0))
	var fill := Rect2(r.position.x + (r.size.x - w if from_right else 0.0), r.position.y, w, r.size.y)
	draw_rect(fill, col)
	if fill.size.x > 0 and r.size.y > 3:
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, 1)), col.lightened(0.35))


## A 0..1 meter in 20 steps (full stays exactly full).
func _steps(ratio: float) -> float:
	return 1.0 if ratio >= 1.0 else floorf(clampf(ratio, 0.0, 1.0) * 20.0) / 20.0


func _hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return C_HP_HI
	if ratio > 0.25:
		return C_HP_MID
	return C_HP_LO


func _text(pos: Vector2, s: String, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var fs := UiTheme.px(size)  # the layout's size as a pixel-font size
	var f := _font
	if width > 0.0 and _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		f = UiTheme.font_tight()  # narrower spaces before it runs off its box
	draw_string_outline(f, pos, s, align, width, fs, UiTheme.outline(fs), Color(0, 0, 0, col.a * 0.8))
	draw_string(f, pos, s, align, width, fs, col)
