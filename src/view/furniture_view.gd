class_name FurnitureView
extends Node2D
## Arena furniture: decor in the margins round the floor, from the optional "furniture"
## list of data/arenas/<id>.json (a map without it gets nothing). Cosmetic: reads the HUD's
## timer and score for the scoreboard, never writes anything. Each piece:
##
##   {"kind": "floodlight", "pos": [-30, 56], "anchor": "tl", "h": 110}
##
## `pos` is where the piece stands (its base; a banner, planter or sponsor board: its top
## or top-left) in world px from `anchor`: tl (default), tr, bl, br corners of the arena, or
## t / b (x from the arena's middle). `mirror` flips it. `layer`: sky (parallax 0.6), far
## (0.85, under the roof edge, behind the crowd) or near (1.0, over the crowd, under the
## fighters); each kind has a default. Other keys per kind (see _draw_piece): `h`, `w`,
## `len`, `color` (#rrggbb), `text`, `emblem`, `vertical`. Never on the playable floor
## (tests/test_furniture.gd checks footprints against the floor).
##
## Kinds: floodlight, flag (flaps), banner (sways), scoreboard (the match clock and score),
## sponsor (an invented name on the wall), post (ring post), crane, worklight, planter
## (sways), sprinkler (sprays), pipe, sign, torch (flickers).
##
## Lit lamps (Settings > Video > Lighting: High, at night): a floodlight, worklight or torch
## whose head has one of the arena's `"lamp": true` lights on it (`head_of`, `set_lit`, from
## Light2DView.lamp_heads) draws its lamps bright with a wider glow; that light lifts the night
## shade round the head, and the bloom haloes it. Otherwise it draws as it always has.
##
## Pixel rules: rects on whole pixels; animation steps on the 60 Hz physics tick clock, no
## easing; a piece redraws only when its frame (or the scoreboard's text) changes.

const KINDS := ["floodlight", "flag", "banner", "scoreboard", "sponsor", "post", "crane", "worklight",
	"planter", "sprinkler", "pipe", "sign", "torch"]
const LAYERS := {"floodlight": "near", "flag": "near", "banner": "far", "scoreboard": "far",
	"sponsor": "near", "post": "near", "crane": "sky", "worklight": "near", "planter": "far",
	"sprinkler": "near", "pipe": "near", "sign": "near", "torch": "near"}
## Ticks per animation step, and how many steps, for the pieces that move.
const ANIM := {"flag": [7, 6], "banner": [24, 4], "planter": [24, 4], "sprinkler": [5, 8], "torch": [5, 6]}
const WAVE := [0, 1, 1, 0, -1, -1]
const FLAME := [0, 2, 1, 3, 1, 2]
const C_STEEL := Color8(74, 78, 92)
const C_STEEL_LIT := Color8(150, 156, 170)
const C_STEEL_DARK := Color8(40, 44, 56)
const C_LAMP := Color8(255, 244, 200)
const C_LAMP_LIT := Color8(255, 255, 240)  ## a lamp lit at night

var backdrop: BackdropView
var hud: Hud  ## the scoreboard reads its timer and score
var pieces: Array[Piece] = []
var _sky_pieces := 0
var _clock := -1
var _board_key := ""


class Piece extends Node2D:
	var view: FurnitureView
	var kind := ""
	var data := {}
	var layer := "near"
	var world := Vector2.ZERO  ## where it stands, world px
	var frame := 0
	var text_key := ""  ## the scoreboard's current text, drawn
	var lit := false  ## a lit lamp sits on its head (set_lit)

	func _draw() -> void:
		view._draw_piece(self)


## Builds the pieces of an arena (its "furniture" list) for a map `size` px big.
func set_arena(arena: Dictionary, size: Vector2) -> void:
	for p in pieces:
		p.queue_free()
	pieces.clear()
	for e in arena.get("furniture", []):
		if not (e is Dictionary) or not KINDS.has(String(e.get("kind", ""))):
			continue
		var p := Piece.new()
		p.view = self
		p.kind = String(e["kind"])
		p.data = e
		p.layer = String(e.get("layer", LAYERS[p.kind]))
		p.world = world_pos(e, size)
		pieces.append(p)
		var parent: Node = self
		var origin := Vector2.ZERO
		if backdrop != null and p.layer == "sky":
			parent = backdrop.sky
			origin = BackdropView.sky_rest()
		elif backdrop != null and p.layer == "far":
			parent = backdrop.far
			origin = BackdropView.far_rest()
		p.position = p.world - origin
		parent.add_child(p)
	_clock = -1
	_board_key = ""


## The kinds with a lamp head, and where the head is against the piece's base (its `h` up).
const HEADS := {"floodlight": 5, "worklight": 4, "torch": 5}
const HEAD_H := {"floodlight": 96, "worklight": 36, "torch": 28}


## Where a lamp-headed piece's lamp is in the world (a floodlight's bank, a worklight's
## lamp, a torch's flame); Vector2.INF for a piece without one.
static func head_of(e: Dictionary, size: Vector2) -> Vector2:
	var k := String(e.get("kind", ""))
	if not HEADS.has(k):
		return Vector2.INF
	var h := int(e.get("h", HEAD_H[k]))
	return world_pos(e, size) + Vector2(0, -h - int(HEADS[k]))


## Lights the lamp heads within Light2DView.HEAD_NEAR of `points` (world px), the rest dark.
func set_lit(points: Array) -> void:
	for p in pieces:
		var was := p.lit
		p.lit = false
		if HEADS.has(p.kind):
			var at := p.world + Vector2(0, -int(p.data.get("h", HEAD_H[p.kind])) - int(HEADS[p.kind]))
			for q in points:
				if at.distance_to(q) <= Light2DView.HEAD_NEAR:
					p.lit = true
					break
		if p.lit != was:
			p.queue_redraw()


## Where a piece's `pos` is in the world, given its `anchor` corner of a map `size` px big.
static func world_pos(e: Dictionary, size: Vector2) -> Vector2:
	var at := e.get("pos", [0, 0]) as Array
	var v := Vector2(float(at[0]), float(at[1]))
	var a := String(e.get("anchor", "tl"))
	if a == "tr" or a == "br":
		v.x = size.x + v.x
	if a == "bl" or a == "br" or a == "b":
		v.y = size.y + v.y
	if a == "t" or a == "b":
		v.x = size.x * 0.5 + v.x
	return v


## The box a piece covers, world px (for the check that none sits on the floor).
static func footprint(p: Piece) -> Rect2:
	var d := p.data
	var h := float(d.get("h", 0))
	var r: Rect2
	match p.kind:
		"floodlight": r = Rect2(-10, -(h if h > 0 else 96) - 9, 21, (h if h > 0 else 96) + 9)
		"flag": r = Rect2(-1, -(h if h > 0 else 44) - 2, 28, (h if h > 0 else 44) + 2)
		"banner": r = Rect2(-12, 0, 24, float(d.get("h", 30)) + 2)
		"scoreboard": r = Rect2(-36, -26, 72, 26)
		"sponsor": r = Rect2(0, 0, float(d.get("w", 62)), 9)
		"post": r = Rect2(-3, -24, 14, 24)
		"crane": r = Rect2(-26, -(h if h > 0 else 80), 72, (h if h > 0 else 80) + 30)
		"worklight": r = Rect2(-7, -(h if h > 0 else 36) - 8, 15, (h if h > 0 else 36) + 8)
		"planter": r = Rect2(-9, 0, 19, float(d.get("len", 16)) + 14)
		"sprinkler": r = Rect2(-12, -(h if h > 0 else 18) - 14, 25, (h if h > 0 else 18) + 14)
		"pipe":
			var n := float(d.get("len", 60))
			r = Rect2(-4, -n, 9, n) if d.get("vertical", false) else Rect2(0, -7, n, 7)
		"sign": r = Rect2(-7, -30, 15, 30)
		"torch": r = Rect2(-4, -(h if h > 0 else 28) - 14, 9, (h if h > 0 else 28) + 14)
		_: r = Rect2()
	if d.get("mirror", false):
		r = Rect2(-r.end.x, r.position.y, r.size.x, r.size.y)
	r.position += p.world
	return r


## The clock and score a scoreboard shows, as strings: {"time", "left", "right", "low"}.
static func board_text(timer_ticks: int, wins: Array, team: Object = null) -> Dictionary:
	var out := {"time": "--", "left": str(int(wins[0])) if wins.size() > 0 else "0",
		"right": str(int(wins[1])) if wins.size() > 1 else "0", "low": false}
	if timer_ticks >= 0:
		var secs := int(ceil(timer_ticks / 60.0))
		out["time"] = "%d:%02d" % [secs / 60, secs % 60]
		out["low"] = secs <= 10
	if team != null and team.get("deathmatch"):
		out["left"] = String(team.score_text(0))
		out["right"] = String(team.score_text(1))
	return out


func _process(_delta: float) -> void:
	var tick := Engine.get_physics_frames()
	if tick == _clock:
		return
	_clock = tick
	for p in pieces:
		if ANIM.has(p.kind):
			var a: Array = ANIM[p.kind]
			var f := (tick / int(a[0])) % int(a[1])
			if f != p.frame:
				p.frame = f
				p.queue_redraw()
		elif p.kind == "scoreboard" and hud != null:
			var t := board_text(hud.timer_ticks, hud.wins, hud.team)
			var key := "%s|%s|%s" % [t["time"], t["left"], t["right"]]
			if key != p.text_key:
				p.text_key = key
				p.queue_redraw()


# ------------------------------------------------------------------ drawing

static func _r(ci: CanvasItem, x: float, y: float, w: float, h: float, c: Color) -> void:
	ci.draw_rect(Rect2(floorf(x), floorf(y), w, h), c)


func _col(d: Dictionary, key: String, def: Color) -> Color:
	return Color.html(String(d[key])) if d.has(key) else def


func _text(ci: CanvasItem, s: String, x: float, base: float, w: float, size: int, c: Color) -> void:
	ci.draw_string(UiTheme.font(), Vector2(floorf(x), floorf(base)), s, HORIZONTAL_ALIGNMENT_CENTER, w,
		UiTheme.px(size), c)


func _draw_piece(p: Piece) -> void:
	var d := p.data
	if d.get("mirror", false):
		p.draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	match p.kind:
		"floodlight": _floodlight(p, int(d.get("h", 96)), p.lit)
		"flag": _flag(p, int(d.get("h", 44)), int(d.get("w", 24)), _col(d, "color", Color8(196, 52, 52)))
		"banner": _banner(p, int(d.get("w", 22)), int(d.get("h", 30)), _col(d, "color", Color8(40, 84, 150)),
			int(d.get("emblem", 0)))
		"scoreboard": _scoreboard(p)
		"sponsor": _sponsor(p, int(d.get("w", 62)), String(d.get("text", "")), _col(d, "color", Color8(40, 92, 168)))
		"post": _post(p, int(d.get("h", 22)), _col(d, "color", Color8(196, 52, 52)))
		"crane": _crane(p, int(d.get("h", 80)), _col(d, "color", Color8(34, 38, 52)))
		"worklight": _worklight(p, int(d.get("h", 36)), p.lit)
		"planter": _planter(p, int(d.get("len", 16)))
		"sprinkler": _sprinkler(p, int(d.get("h", 18)))
		"pipe": _pipe(p, int(d.get("len", 60)), bool(d.get("vertical", false)))
		"sign": _sign(p)
		"torch": _torch(p, int(d.get("h", 28)), p.lit)


func _floodlight(p: Node2D, h: int, lit := false) -> void:
	# A tower with a bank of lamps, and the glow round them in stepped, low-alpha boxes.
	_r(p, -1, -h, 3, h, C_STEEL)
	_r(p, -1, -h, 1, h, C_STEEL_LIT)
	_r(p, -4, -3, 9, 3, C_STEEL_DARK)
	for y in range(8, h, 16):
		_r(p, -2, -y, 5, 1, C_STEEL_DARK)
	var g := 2.5 if lit else 1.0  # lit at night: the glow boxes stronger
	if lit:
		_r(p, -36, -h - 32, 73, 54, Color(1.0, 0.95, 0.7, 0.06))
	_r(p, -26, -h - 24, 53, 38, Color(1.0, 0.95, 0.7, 0.07 * g))
	_r(p, -17, -h - 16, 35, 22, Color(1.0, 0.95, 0.7, 0.09 * g))
	_r(p, -10, -h - 9, 21, 9, C_STEEL_DARK)
	_r(p, -10, -h - 9, 21, 1, C_STEEL)
	for i in 3:
		_r(p, -9 + i * 7, -h - 7, 5, 3, C_LAMP_LIT if lit else C_LAMP)
		_r(p, -9 + i * 7, -h - 3, 5, 2, C_LAMP if lit else Color8(214, 200, 150))
	if lit:  # the beams' first reach, down toward the floor
		_r(p, -10, -h + 1, 21, 2, Color(1.0, 0.95, 0.75, 0.22))
		_r(p, -8, -h + 3, 17, 3, Color(1.0, 0.95, 0.75, 0.12))


func _flag(p: Piece, h: int, w: int, c: Color) -> void:
	_r(p, 0, -h, 2, h, C_STEEL_LIT)
	_r(p, -1, -h - 2, 4, 2, Color8(226, 184, 60))
	var dark := c.darkened(0.3)
	var lit := c.lightened(0.35)
	for i in w:
		var amp := minf(float(i) / 8.0, 1.0)
		var off := int(round(WAVE[(i / 3 + p.frame) % 6] * (1.0 + amp)))
		var tail := maxi(0, i - (w - 5))  # a swallowtail
		var top := -h + 2 + off + tail
		var hh := 12 - tail * 2
		_r(p, 2 + i, top, 1, hh, c)
		_r(p, 2 + i, top + 5, 1, 2, lit)
		_r(p, 2 + i, top + hh - 1, 1, 1, dark)


func _banner(p: Piece, w: int, h: int, c: Color, emblem: int) -> void:
	_r(p, -w / 2 - 1, 0, w + 2, 2, Color8(70, 56, 40))
	var sway: int = [-1, 0, 1, 0][p.frame % 4]
	var lit := c.lightened(0.45)
	for r in h:
		var sh := int(round(float(sway) * r / float(h)))
		var cut := maxi(0, r - (h - 6)) * 2  # swallowtail
		var x0 := -w / 2 + sh
		if cut > 0:
			_r(p, x0, 2 + r, (w - cut) / 2, 1, c)
			_r(p, x0 + (w + cut) / 2, 2 + r, (w - cut) / 2, 1, c)
		else:
			_r(p, x0, 2 + r, w, 1, c)
		if r > 6 and r < 6 + 9:
			var k := r - 6
			match emblem % 3:
				0:  # a diamond
					var half := 4 - absi(k - 4)
					_r(p, sh - half, 2 + r, half * 2 + 1, 1, lit)
				1:  # a stripe
					if k % 4 < 2:
						_r(p, x0 + 3, 2 + r, w - 6, 1, lit)
				_:  # a chevron
					_r(p, sh - 4 + absi(k - 4) / 2, 2 + r, 8 - absi(k - 4), 1, lit)
	_r(p, -w / 2, 2, 1, h, c.lightened(0.15))


func _scoreboard(p: Piece) -> void:
	var w := 72
	var h := 26
	_r(p, -w / 2, -h, w, h, Color8(28, 30, 40))
	_r(p, -w / 2, -h, w, 1, C_STEEL_LIT)
	_r(p, -w / 2 + 2, -h + 2, w - 4, h - 4, Color8(8, 10, 14))
	_r(p, -w / 2 + 2, -4, w - 4, 2, Color8(20, 22, 30))
	var t := {"time": "--", "left": "0", "right": "0", "low": false}
	if hud != null:
		t = board_text(hud.timer_ticks, hud.wins, hud.team)
	var amber := Color8(255, 96, 70) if t["low"] else Color8(255, 190, 70)
	_text(p, String(t["time"]), -w / 2 + 18, -h + 17, 36, 8, amber)
	# the two sides' scores, each over a bar in the side's colour
	_r(p, -w / 2 + 3, -h + 4, 14, 2, Hud.SIDE_COLORS[0])
	_r(p, w / 2 - 17, -h + 4, 14, 2, Hud.SIDE_COLORS[1])
	_text(p, String(t["left"]), -w / 2 + 3, -h + 17, 14, 6, Color8(255, 236, 230))
	_text(p, String(t["right"]), w / 2 - 17, -h + 17, 14, 6, Color8(226, 236, 255))


func _sponsor(p: Piece, w: int, text: String, c: Color) -> void:
	_r(p, 0, 0, w, 9, c)
	_r(p, 0, 0, w, 1, c.lightened(0.3))
	_r(p, 0, 8, w, 1, c.darkened(0.45))
	var light := c.get_luminance() < 0.45
	_text(p, text, 0, 7, w, 6, Color8(255, 246, 222) if light else Color8(40, 28, 16))


func _post(p: Piece, h: int, c: Color) -> void:
	_r(p, -2, -h, 4, h, C_STEEL)
	_r(p, -2, -h, 1, h, C_STEEL_LIT)
	_r(p, -3, -h - 2, 6, 2, C_STEEL_LIT)
	_r(p, -3, -14, 6, 10, c)
	_r(p, -3, -14, 6, 1, c.lightened(0.4))
	_r(p, 3, -h + 4, 8, 1, Color8(236, 236, 230))
	_r(p, 3, -h + 10, 8, 1, Color8(236, 236, 230))


func _crane(p: Piece, h: int, c: Color) -> void:
	for y in range(0, h, 4):
		_r(p, -3, -y - 4, 1, 4, c)
		_r(p, 2, -y - 4, 1, 4, c)
		_r(p, -3 + (y / 4) % 2 * 4, -y - 2, 2, 1, c)
	_r(p, -3, -h, 6, 3, c)
	_r(p, -26, -h - 2, 72, 2, c)  # the jib and the counter jib
	for i in range(0, 28, 4):
		_r(p, -2 + i, -h - 6 + i / 7, 2, 4, c)
	_r(p, -26, -h, 8, 7, c)  # counterweight
	_r(p, 38, -h, 1, 26, c)  # hook line
	_r(p, 36, -h + 26, 5, 3, c)


func _worklight(p: Node2D, h: int, lit := false) -> void:
	_r(p, -1, -h, 2, h, C_STEEL)
	_r(p, -6, -2, 13, 2, C_STEEL_DARK)
	if lit:
		_r(p, -14, -h - 22, 29, 30, Color(1.0, 0.8, 0.45, 0.08))
	_r(p, -6, -h - 14, 13, 14, Color(1.0, 0.8, 0.45, 0.2 if lit else 0.07))
	_r(p, -7, -h - 8, 15, 8, Color8(214, 140, 40))
	_r(p, -7, -h - 8, 15, 1, Color8(240, 180, 90))
	_r(p, -6, -h - 6, 13, 4, C_LAMP_LIT if lit else Color8(255, 236, 170))


func _planter(p: Piece, ln: int) -> void:
	var sway: int = [0, 1, 0, -1][p.frame % 4]
	_r(p, -6, 0, 1, ln, Color8(150, 150, 150))
	_r(p, 5, 0, 1, ln, Color8(150, 150, 150))
	_r(p, -8, ln, 17, 8, Color8(176, 92, 60))
	_r(p, -9, ln, 19, 2, Color8(206, 122, 82))
	_r(p, -9, ln - 4, 19, 4, Color8(70, 150, 70))
	_r(p, -6, ln - 6, 5, 2, Color8(96, 176, 84))
	_r(p, 1, ln - 7, 6, 3, Color8(96, 176, 84))
	for k in [-6, -2, 2, 6]:
		_r(p, k, ln + 8, 1, 4, Color8(60, 130, 60))
		_r(p, k + sway, ln + 12, 1, 4, Color8(76, 150, 70))


func _sprinkler(p: Piece, h: int) -> void:
	_r(p, -1, -h, 3, h, C_STEEL_LIT)
	_r(p, -4, -2, 9, 2, C_STEEL)
	_r(p, -3, -h - 3, 7, 3, Color8(200, 60, 50))
	for i in 5:
		var q := (p.frame + i * 3) % 8
		var x := 2 + q * 2
		var y := -h - 4 - (q * (8 - q)) / 3 + q / 2
		_r(p, x, y, 1, 1, Color8(170, 214, 255))
		_r(p, -x, y, 1, 1, Color8(170, 214, 255))


func _pipe(p: Node2D, ln: int, vertical: bool) -> void:
	var body := Color8(110, 116, 128)
	if vertical:
		_r(p, -2, -ln, 5, ln, body)
		_r(p, -2, -ln, 1, ln, C_STEEL_LIT)
		_r(p, 2, -ln, 1, ln, Color8(70, 74, 86))
		for y in range(10, ln, 24):
			_r(p, -4, -y, 9, 3, Color8(86, 90, 102))
		_r(p, -3, -ln / 2 - 3, 7, 1, Color8(150, 90, 50))
	else:
		_r(p, 0, -5, ln, 5, body)
		_r(p, 0, -5, ln, 1, C_STEEL_LIT)
		_r(p, 0, -1, ln, 1, Color8(70, 74, 86))
		for x in range(10, ln, 24):
			_r(p, x, -7, 3, 9, Color8(86, 90, 102))
		_r(p, ln / 2, -6, 1, 3, Color8(150, 90, 50))


func _sign(p: Node2D) -> void:
	_r(p, -1, -18, 2, 18, C_STEEL)
	for i in 12:
		var half := i / 2
		_r(p, -half - 1, -30 + i, half * 2 + 3, 1, Color8(20, 20, 24))
		if half > 0:
			_r(p, -half, -30 + i, half * 2 + 1, 1, Color8(236, 190, 40))
	_r(p, 0, -26, 1, 4, Color8(20, 20, 24))
	_r(p, 0, -21, 1, 1, Color8(20, 20, 24))


func _torch(p: Piece, h: int, lit := false) -> void:
	_r(p, -1, -h, 3, h, Color8(96, 70, 44))
	_r(p, -4, -h - 3, 9, 3, Color8(60, 50, 44))
	var f: int = FLAME[p.frame % 6]
	if lit:  # flickers with the flame
		_r(p, -15 - f, -h - 20 - f, 31 + f * 2, 26 + f, Color(1.0, 0.7, 0.3, 0.08))
	_r(p, -9, -h - 14, 19, 14, Color(1.0, 0.7, 0.3, 0.18 if lit else 0.07))
	_r(p, -2, -h - 7, 5, 4, Color8(240, 120, 30))
	_r(p, -1, -h - 7 - f, 3, 3 + f, Color8(250, 170, 50))
	_r(p, 0, -h - 6, 1, 2, Color8(255, 248, 210) if lit else Color8(255, 236, 160))
