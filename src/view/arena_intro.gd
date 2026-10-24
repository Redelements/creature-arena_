class_name ArenaIntro
extends Node2D
## The arena intro before an offline match: the camera flies in from the stands to the
## whole floor, the arena's name card slams in, then each side is introduced (a 1v1 one
## fighter at a time, a team battle a whole team at once) with a push-in on them and a card
## with the name, title and class. Main then hands over to the round's usual "ROUND 1 /
## FIGHT!" banners (or a team battle's own intro), so the sim starts exactly as it would
## without it.
##
## Purely a view: the sim is not stepped while it plays (main returns before the tick),
## so it never shifts the sim's ticks, a replay's frames or the CPUs' thinking. Main reads
## `focus` / `zoom` for the camera each tick and calls `advance()`; every move is eased
## per tick (no interpolation between ticks) and text and cards move by whole pixels.
## On the screen layer, over the letterbox (main holds the bars in while it plays).

## The fly-over: from the stands across the top, pushed in, to the whole stadium.
const FLY := 50
const FLY_ZOOM := 2.2
## The arena's name card: slams in, holds, slides off.
const CARD_IN := 12
const CARD_OUT := 54
const CARD_SLIDE := 6
## Each side's beat: the camera pushes in on them and their card slides in from their side.
const BEATS_AT := 56
const BEAT := 38
const BEAT_ZOOM := 2.0
const TEAM_ZOOM_MAX := 1.6
const CARD_SLIDE_IN := 6
const CARD_SLIDE_OUT := 5
## After the last beat, a moment before the round's banners take over.
const TAIL := 4
const C_BAND := Color(0.04, 0.045, 0.07, 0.92)
const C_TEXT := Hud.C_TEXT
const C_DIM := Hud.C_DIM
const C_ACCENT := Hud.C_ACCENT

var sim: MatchSim
var arena_name := ""
var subtitle := ""
## One per beat: {"slots": [creature slots], "side": 0 or 1 (which edge its card comes
## from), "color": Color, "tag": "PLAYER 1", "name": "CAIRN" or "RED TEAM", "lines":
## [title, "Fighter  ·  Stone"] or the team's names}.
var groups: Array = []
var t := 0
var focus := Vector2.ZERO
var zoom := 1.0
var _sw := float(SimDefs.VIEW_W)
var _sh := float(SimDefs.VIEW_H)


func length() -> int:
	return BEATS_AT + groups.size() * BEAT + TAIL


func finished() -> bool:
	return t >= length()


## Which beat is on at tick `at` (-1: none yet, or past them all).
func beat_at(at: int) -> int:
	if at < BEATS_AT:
		return -1
	var g := (at - BEATS_AT) / BEAT
	return g if g < groups.size() else -1


## One tick: moves the camera (`focus`, `zoom`) for a screen of `view` over an arena of
## `size`. Returns the beat that starts on this tick (-1 if none), so main can pose its
## fighters and play the sting.
func advance(view: Vector2, size: Vector2) -> int:
	var whole := clampf(minf(view.x / size.x, view.y / size.y), 0.35, 1.0)
	if t == 0:
		focus = Vector2(size.x * 0.32, 20.0)
		zoom = FLY_ZOOM
	if t <= FLY:
		var k := smoothstep(0.0, 1.0, float(t) / FLY)
		focus = Vector2(size.x * 0.32, 20.0).lerp(size * 0.5, k)
		zoom = lerpf(FLY_ZOOM, whole, k)
	else:
		var g := beat_at(t)
		var want_f := size * 0.5
		var want_z := whole
		if g >= 0:
			var box := _box_of(groups[g]["slots"])
			want_f = box.get_center()
			want_z = BEAT_ZOOM
			if (groups[g]["slots"] as Array).size() > 1:
				var room := box.grow_individual(48, 40, 48, 30)
				want_z = clampf(minf(view.x / room.size.x, view.y / room.size.y), whole, TEAM_ZOOM_MAX)
				want_f.y += 18.0  # the team stands a little higher, clear of its card
		focus = focus.lerp(want_f, 0.16)
		zoom = lerpf(zoom, want_z, 0.14)
	var started := beat_at(t) if t >= BEATS_AT and (t - BEATS_AT) % BEAT == 0 else -1
	t += 1
	queue_redraw()
	return started


## The fighters in `slots`, heads to feet.
func _box_of(slots: Array) -> Rect2:
	var box := Rect2()
	var any := false
	for i in slots:
		if int(i) >= sim.creatures.size():
			continue
		var c := sim.creatures[int(i)]
		var body := Rect2(c.pos - Vector2(0, float(c.def.get("fx_top", 32))), Vector2.ZERO).expand(c.pos)
		box = body if not any else box.merge(body)
		any = true
	return box if any else Rect2(sim.arena_size() * 0.5, Vector2.ZERO)


func _draw() -> void:
	var vs := get_viewport_rect().size
	_sw = maxf(vs.x, 1.0)
	_sh = maxf(vs.y, 1.0)
	var at := t - 1  # advance() already counted this tick
	if at >= CARD_IN and at < CARD_OUT + CARD_SLIDE:
		_draw_name_card(at - CARD_IN, at - CARD_OUT)
	var g := beat_at(at)
	if g >= 0:
		_draw_fighter_card(groups[g], at - BEATS_AT - g * BEAT)


## The arena's name across the middle: the band snaps open, the name lands big and steps
## down to its size (whole font sizes), then everything slides off to the left.
func _draw_name_card(ti: int, out_t: int) -> void:
	var off := 0.0
	if out_t >= 0:
		var k := float(out_t + 1) / CARD_SLIDE
		off = -roundf(k * k * (_sw + 40.0))
	var cy := roundf(_sh * 0.5 - 14.0)
	var open := minf(1.0, float(ti + 1) / 3.0)
	var half := roundf(22.0 * open)
	draw_rect(Rect2(off, cy - half, _sw, half * 2.0), C_BAND)
	draw_rect(Rect2(off, cy - half, _sw, 2), C_ACCENT)
	draw_rect(Rect2(off, cy + half - 2, _sw, 2), C_ACCENT)
	if ti < 2:
		return
	var steps := [40, 40, 26, 26, 26]  # px() sizes 48, 48, 40: the name lands big and steps down
	var size := 20 if ti - 2 >= steps.size() else int(steps[ti - 2])
	var name := arena_name.to_upper()
	var drop := 0.0 if ti >= 7 else 3.0 * (1.0 - (ti - 2) / 5.0)
	_text(Vector2(off, cy + 6 + roundf(drop)), name, size, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, _sw)
	if ti >= 8 and subtitle != "":
		_text(Vector2(off, cy + 18), subtitle, 8, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, _sw)
	if ti >= 2 and ti < 5:
		draw_rect(Rect2(0, 0, _sw, _sh), Color(1, 1, 1, 0.35 * (1.0 - (ti - 2) / 3.0)))


## A side's card in the lower third, sliding in from its own edge.
func _draw_fighter_card(gr: Dictionary, bt: int) -> void:
	var side := int(gr.get("side", 0))
	var dir := 1.0 if side == 0 else -1.0
	var col: Color = gr.get("color", C_ACCENT)
	var lines: Array = gr.get("lines", [])
	var w := minf(240.0, _sw - 32.0)
	var h := 34.0 + 12.0 * lines.size()
	var k_in := clampf(float(bt + 1) / CARD_SLIDE_IN, 0.0, 1.0)
	var k_out := clampf(float(bt - (BEAT - CARD_SLIDE_OUT)) / CARD_SLIDE_OUT, 0.0, 1.0)
	var slide := roundf(pow(1.0 - k_in, 3.0) * (w + 24.0) + k_out * k_out * (w + 24.0))
	var x := (16.0 - slide) if side == 0 else (_sw - 16.0 - w + slide)
	var y := roundf(_sh - 32.0 - h)
	draw_rect(Rect2(x, y, w, h), C_BAND)
	draw_rect(Rect2(x if side == 0 else x + w - 3, y, 3, h), col)
	draw_rect(Rect2(x, y, w, 1), Color(col, 0.6))
	var tx := x + (10.0 if side == 0 else 6.0)
	var tw := w - 16.0
	var align := HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	_text(Vector2(tx, y + 9), String(gr.get("tag", "")), 6, col, align, tw)
	var nm := String(gr.get("name", ""))
	var drop := 0.0 if bt >= 6 else roundf(2.0 * (1.0 - bt / 6.0))
	_text(Vector2(tx, y + 28 + drop), nm, 16, C_TEXT, align, tw)
	for i in lines.size():
		_text(Vector2(tx, y + 41 + 12 * i), String(lines[i]), 8, C_ACCENT if i == lines.size() - 1 else C_DIM, align, tw)


func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var fs := UiTheme.px(size)
	var f := UiTheme.font()
	if width > 0.0 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		f = UiTheme.font_tight()
	draw_string_outline(f, pos.round(), s, align, width, fs, UiTheme.outline(fs), Color(0, 0, 0, col.a * 0.8))
	draw_string(f, pos.round(), s, align, width, fs, col)
