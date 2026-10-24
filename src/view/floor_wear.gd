class_name FloorWear
extends Node2D
## The floor remembers the fight: claw scratches, gouges, craters, drag lines, dirt clods,
## mallet marks and, for a few seconds, wet / slushy / sticky footprints. Cosmetic: reads
## the sim, never writes it. FxView decides what leaves a mark (see its header, `fx.decal`)
## and calls mark(); this node stores and draws them.
##
## Pixel art, cheap: every mark is a tiny pre-drawn shape (8 directions, no rotation) in the
## floor's own tones, built once per ground kind into a small atlas (`_atlas`) and drawn as
## one whole-pixel texture blit. Marks are static, so this layer repaints only when one is
## added, removed, steps its fade or the camera leaves the area drawn, never every tick.
## Shots leave marks where they end: "scuff" (a dust streak), "stuck" (a knife or shuriken
## standing in the floor) and "splat" (venom). Marks fade in whole alpha steps (FADE_AT / FADE_A) over 20 to 40 seconds, then go; the
## oldest goes first past the cap (`cap()`, 200 on the stadium, more on a big map). A mark
## on a cell that became a pit, wall, water or brush is dropped (`_scan`), so a healed
## cell is fresh floor. Main adds this between the crowd and FxGround and calls
## set_sim() / advance().

const CELL := 32  ## atlas cell: every shape fits in 32 x 32, centred
const CAP_BASE := 200
const DRAWN_PAD := 96.0  ## draws this far past the view; repaints when the view leaves it
const SCAN_EVERY := 10  ## ticks between floor-change scans
const NEAR := 5.0  ## a new mark this close to a recent one of its kind is skipped
## Fade: whole alpha steps at these fractions of a mark's life.
const FADE_AT: Array[float] = [0.0, 0.5, 0.75, 0.9]
const FADE_A: Array[float] = [1.0, 0.75, 0.5, 0.28]

## kind -> [atlas row, life in ticks]
const KINDS := {
	"scratch": [0, 1500], "gouge": [1, 2400], "drag": [2, 1500], "crater_s": [3, 2100],
	"crater_l": [4, 2400], "clod": [5, 1800], "mallet": [6, 1800],
	"print_wet": [7, 240], "print_slush": [8, 300], "print_syrup": [9, 360],
	"scuff": [10, 900], "stuck": [11, 600], "splat": [12, 1200],
}
const ROWS := 13

## ground -> [furrow, lip, shade]: the tone of a cut, of the edge it throws up, and the
## darker tone under a crater. Dirt cuts dark; stone and concrete scratch pale; turf tears
## to soil with green flecks.
const TONES := {
	"dirt": ["3f2a18", "b08c60", "2c1c10"],
	"stone": ["d8ccb6", "4a4034", "3a3228"],
	"concrete": ["dfe3e8", "454a53", "353a42"],
	"grass": ["4a3016", "7fd08a", "2e1e0e"],
}
const PRINT_TONES := {  ## kind -> [print, edge]
	"print_wet": ["2c4560", "5f8fb8"],
	"print_slush": ["d6f2f8", "8fbccc"],
	"print_syrup": ["c8860e", "f0c040"],
}
const OK_CELLS := [TerrainGrid.INTACT, TerrainGrid.CRACKED, TerrainGrid.BRUSH_FLAT]

var sim: MatchSim
var _terrain: TerrainGrid
var _marks: Array[Dictionary] = []  ## {k, x, y, col, born, life, g, step}
var _atlas := {}  ## ground -> ImageTexture (prints are in every atlas)
var _version := -1
var _scan_due := false
var _last_scan := 0
var _dirty := false
var _drawn := Rect2()
var _drawn_ok := false
var _cap := CAP_BASE
var _last_tick := -1


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_sim(s: MatchSim) -> void:
	sim = s
	_terrain = s.terrain
	clear()
	var ref := SimDefs.arena_size()
	var a := s.arena_size()
	_cap = int(CAP_BASE * clampf(a.x * a.y / maxf(1.0, ref.x * ref.y), 1.0, 3.0))
	if not _atlas.has(ground()):  # build the shapes now, not on the first mark
		_atlas[ground()] = _build(ground())


func clear() -> void:
	_marks.clear()
	_version = _terrain.version if _terrain != null else -1
	_last_tick = -1
	_drawn_ok = false
	queue_redraw()


func cap() -> int:
	return _cap


func count() -> int:
	return _marks.size()


## The arena's ground kind: dirt, stone, concrete or grass.
func ground() -> String:
	var g := String(sim.arena.get("ground", "dirt")) if sim != null else "dirt"
	return g if TONES.has(g) else "dirt"


## Leave a mark. `kind` is a KINDS key; `dir` the direction it points (scratches, gouges,
## drags, prints); `scale` isn't used: bigger marks are other kinds. Nothing is left on
## water, brush, pits or walls.
func mark(kind: String, pos: Vector2, dir := Vector2.RIGHT) -> void:
	if sim == null or not KINDS.has(kind):
		return
	if not _floor_ok(pos):
		return
	# Don't pile marks on top of each other: look at the recent few.
	var n := _marks.size()
	for i in range(n - 1, maxi(-1, n - 7), -1):
		var m: Dictionary = _marks[i]
		if m["k"] == kind and absf(float(m["x"]) - pos.x) < NEAR and absf(float(m["y"]) - pos.y) < NEAR \
				and sim.tick - int(m["born"]) < 90:
			return
	var col := 0
	if kind.begins_with("crater") or kind in ["clod", "mallet", "splat"]:
		col = randi() % 8  # the shape's own variants
	else:
		col = _bucket(dir)
	var life: int = int(KINDS[kind][1])
	life = int(life * randf_range(0.85, 1.15))
	_marks.append({"k": kind, "x": roundf(pos.x), "y": roundf(pos.y), "col": col, "born": sim.tick,
		"life": life, "g": ground(), "step": 0})
	while _marks.size() > _cap:
		_marks.pop_front()
	_dirty = true


## Which of the 8 pre-drawn directions `dir` is closest to (0 = right, clockwise on screen).
static func _bucket(dir: Vector2) -> int:
	if dir.length_squared() < 0.0001:
		return 0
	return posmod(int(roundf(dir.angle() / (TAU / 8.0))), 8)


func _floor_ok(pos: Vector2) -> bool:
	var tg := _terrain
	var cell := tg.world_to_cell(pos)
	return tg.in_bounds(cell) and tg.get_cell(cell) in OK_CELLS


## Main calls this every frame; work happens only when the sim ticks.
func advance() -> void:
	if sim == null or _terrain == null:
		return
	if sim.tick < _last_tick:  # a rollback or a restart: marks from the future go
		var keep: Array[Dictionary] = []
		for m in _marks:
			if int(m["born"]) <= sim.tick:
				keep.append(m)
		if keep.size() != _marks.size():
			_marks = keep
			_dirty = true
	if sim.tick != _last_tick:
		_last_tick = sim.tick
		if _terrain.version != _version:
			_version = _terrain.version
			_scan_due = true
		if sim.tick - _last_scan >= SCAN_EVERY:
			_last_scan = sim.tick
			_age()
	var view := FxView._view_rect(self, 0.0)
	if not _drawn_ok or not _drawn.encloses(view):
		_dirty = true
	if _dirty:
		_dirty = false
		_drawn = view.grow(DRAWN_PAD)
		_drawn_ok = true
		queue_redraw()


## Drop what is over a pit, wall, water or brush now; step the fades; remove the expired.
func _age() -> void:
	var out: Array[Dictionary] = []
	var changed := false
	for m in _marks:
		var age := maxi(0, sim.tick - int(m["born"]))
		var life := int(m["life"])
		if age >= life or (_scan_due and not _floor_ok(Vector2(float(m["x"]), float(m["y"])))):
			changed = true
			continue
		var f := float(age) / float(life)
		var s := 0
		for i in FADE_AT.size():
			if f >= FADE_AT[i]:
				s = i
		if s != int(m["step"]):
			m["step"] = s
			changed = true
		out.append(m)
	_scan_due = false
	if changed:
		_marks = out
		_dirty = true


func _draw() -> void:
	if sim == null:
		return
	var t0 := PerfLog.now()
	for m in _marks:
		var x := float(m["x"])
		var y := float(m["y"])
		if not _drawn.has_point(Vector2(x, y)):
			continue
		var g: String = m["g"]
		if not _atlas.has(g):
			_atlas[g] = _build(g)
		var row: int = KINDS[m["k"]][0]
		draw_texture_rect_region(_atlas[g], Rect2(x - CELL / 2, y - CELL / 2, CELL, CELL),
			Rect2(int(m["col"]) * CELL, row * CELL, CELL, CELL), Color(1, 1, 1, FADE_A[int(m["step"])]))
	PerfLog.since("floor wear draw", t0)


# ------------------------------------------------------------------ the shapes

func _build(g: String) -> ImageTexture:
	var img := Image.create(CELL * 8, CELL * ROWS, false, Image.FORMAT_RGBA8)
	var t: Array = TONES[g]
	var furrow := Color(String(t[0]))
	var lip := Color(String(t[1]))
	var shade := Color(String(t[2]))
	for d in 8:
		var a := d * TAU / 8.0
		var dv := Vector2(cos(a), sin(a))
		var nv := Vector2(-dv.y, dv.x)
		var o := Vector2i(d * CELL, 0)
		# claw scratches: three short parallel cuts
		for i in 3:
			var off := (i - 1) * 2.2
			var len := 4.0 + (i % 2) * 1.5
			_line(img, o, 0, dv * (-len + (i - 1) * 0.8) + nv * off, dv * len + nv * off, furrow.lerp(shade, 0.15), 0.85)
		# gouge: three long furrows with a lip thrown up on one side
		for i in 3:
			var off := (i - 1) * 3.4
			var len := 9.0 - absf(i - 1) * 2.0 + (2.0 if i == 2 else 0.0)
			_line(img, o, 1, dv * -len + nv * off, dv * len + nv * off, furrow, 0.92)
			_line(img, o, 1, dv * (-len + 2.0) + nv * (off + 1.4), dv * (len - 2.0) + nv * (off + 1.4), lip, 0.55, 2)
		# drag line: two faint ruts and a dotted dust line between
		for s in [-1.0, 1.0]:
			_line(img, o, 2, dv * -9.0 + nv * 2.4 * s, dv * 9.0 + nv * 2.4 * s, furrow, 0.6)
		_line(img, o, 2, dv * -8.0, dv * 8.0, lip, 0.4, 2)
		# scuff: a short pale streak with two specks; stuck: a blade standing in the floor (same in every atlas)
		_line(img, o, 10, dv * -5.0, dv * 3.0, lip, 0.8)
		_line(img, o, 10, dv * -3.0 + nv * 1.0, dv * 1.0 + nv * 1.0, furrow, 0.75)
		_px(img, Vector2i(d * CELL + CELL / 2, 10 * CELL + CELL / 2) + Vector2i(roundi(dv.x * 6.0), roundi(dv.y * 6.0)), lip, 0.6)
		_line(img, o, 11, dv * -4.0, dv * 4.0, Color("2a2628"), 0.9)
		_line(img, o, 11, dv * -2.0 - nv * 1.0, dv * 4.0 - nv * 1.0, Color("cfd3d8"), 0.9)
		_px(img, Vector2i(d * CELL + CELL / 2, 11 * CELL + CELL / 2) + Vector2i(roundi(-dv.x * 4.0), roundi(-dv.y * 4.0)), furrow, 0.9)
		# footprints (same in every atlas): a 3 x 2 oval along the heading
		for kind in PRINT_TONES:
			var pt: Array = PRINT_TONES[kind]
			var row: int = KINDS[kind][0]
			var c := Vector2i(d * CELL + CELL / 2, row * CELL + CELL / 2)
			_oval(img, c, dv, 1.9, 1.1, Color(String(pt[0])), 0.85)
			_px(img, c + Vector2i(roundi(-dv.x * 2.0), roundi(-dv.y * 2.0)), Color(String(pt[1])), 0.7)
			if kind == "print_syrup":
				_px(img, c + Vector2i(roundi(dv.x * 2.0), roundi(dv.y * 2.0)), Color(String(pt[1])), 0.8)
	# the variants: craters, clods, mallet teeth (a different jitter per column)
	var rng := RandomNumberGenerator.new()
	for v in 8:
		rng.seed = 1000 + v * 77
		var o := Vector2i(v * CELL, 0)
		_crater(img, o, 3, 5.0, furrow, lip, shade, rng, 0)
		_crater(img, o, 4, 10.0, furrow, lip, shade, rng, 4)
		_clods(img, o, 5, furrow, lip, shade, rng)
		_mallet(img, o, 6, furrow, lip, rng)
		_splat(img, o, 12, rng)
	return ImageTexture.create_from_image(img)


static func _px(img: Image, p: Vector2i, c: Color, a := 1.0) -> void:
	if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
		return
	img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, a))


## A Bresenham line from `a` to `b` (offsets from the cell centre), every `every`th pixel.
static func _line(img: Image, o: Vector2i, row: int, a: Vector2, b: Vector2, c: Color, alpha: float,
		every := 1) -> void:
	var cen := Vector2i(o.x + CELL / 2, row * CELL + CELL / 2)
	var p0 := cen + Vector2i(roundi(a.x), roundi(a.y))
	var p1 := cen + Vector2i(roundi(b.x), roundi(b.y))
	var dx := absi(p1.x - p0.x)
	var dy := -absi(p1.y - p0.y)
	var sx := 1 if p0.x < p1.x else -1
	var sy := 1 if p0.y < p1.y else -1
	var err := dx + dy
	var i := 0
	while true:
		if i % every == 0:
			_px(img, p0, c, alpha)
		i += 1
		if p0 == p1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p0.x += sx
		if e2 <= dx:
			err += dx
			p0.y += sy


## A filled oval, `rx` along `dv`, `ry` across.
static func _oval(img: Image, c: Vector2i, dv: Vector2, rx: float, ry: float, col: Color, alpha: float) -> void:
	var nv := Vector2(-dv.y, dv.x)
	for y in range(-3, 4):
		for x in range(-3, 4):
			var u := (x * dv.x + y * dv.y) / rx
			var w := (x * nv.x + y * nv.y) / ry
			if u * u + w * w <= 1.0:
				_px(img, c + Vector2i(x, y), col, alpha)


## A ring of cut pixels (a true circle on the floor), a darker dent inside, chips thrown out.
static func _crater(img: Image, o: Vector2i, row: int, r: float, furrow: Color, lip: Color, shade: Color,
		rng: RandomNumberGenerator, cracks: int) -> void:
	var cen := Vector2i(o.x + CELL / 2, row * CELL + CELL / 2)
	var ri := int(ceil(r)) + 1
	for y in range(-ri, ri + 1):
		for x in range(-ri, ri + 1):
			var d := sqrt(float(x * x + y * y))
			if d <= r - 1.5:
				_px(img, cen + Vector2i(x, y), shade, 0.38)
			elif d <= r + 0.4:
				var gap := (x * 7 + y * 13 + int(o.x)) % 9 == 0  # a broken rim
				if not gap:
					_px(img, cen + Vector2i(x, y), furrow, 0.9)
			elif d <= r + 1.4 and x + y < 0 and (x + 2 * y) % 3 != 0:
				_px(img, cen + Vector2i(x, y), lip, 0.6)  # the lit rim, up and to the left
	for i in cracks:  # short cracks running out of the rim
		var a := rng.randf() * TAU
		var dv := Vector2(cos(a), sin(a))
		_line(img, o, row, dv * (r + 0.5), dv * (r + 3.0 + rng.randf() * 2.5), furrow, 0.8)
	for i in 3:  # loose chips
		var a := rng.randf() * TAU
		var rr := r + 2.5 + rng.randf() * 3.0
		_px(img, cen + Vector2i(roundi(cos(a) * rr), roundi(sin(a) * rr)), lip, 0.8)


## Dirt thrown out of a hole: a ring of 2 x 2 clods round a dark mouth.
static func _clods(img: Image, o: Vector2i, row: int, furrow: Color, lip: Color, shade: Color,
		rng: RandomNumberGenerator) -> void:
	var cen := Vector2i(o.x + CELL / 2, row * CELL + CELL / 2)
	for y in range(-3, 4):
		for x in range(-3, 4):
			if x * x + y * y <= 9:
				_px(img, cen + Vector2i(x, y), shade, 0.55)
	var n := 9
	for i in n:
		var a := TAU * i / n + rng.randf() * 0.5
		var r := 7.0 + rng.randf() * 4.0
		var p := cen + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
		for dy in 2:
			for dx in 2:
				_px(img, p + Vector2i(dx, dy), furrow, 0.9)
		_px(img, p, lip, 0.85)
		if rng.randf() < 0.5:
			_px(img, p + Vector2i(-1, 2), furrow, 0.6)


## A splat of venom: a green blob with a darker core and a few flung drops.
static func _splat(img: Image, o: Vector2i, row: int, rng: RandomNumberGenerator) -> void:
	var cen := Vector2i(o.x + CELL / 2, row * CELL + CELL / 2)
	var rx := 4.0 + rng.randf() * 1.5
	for y in range(-3, 4):
		for x in range(-5, 6):
			var u := float(x) / rx
			var w := float(y) / 2.2
			var r := u * u + w * w
			if r <= 1.0:
				_px(img, cen + Vector2i(x, y), Color("3f8a2a") if r > 0.45 else Color("2c6a1c"), 0.8)
	for i in 5:
		var a := rng.randf() * TAU
		var rr := 5.0 + rng.randf() * 4.0
		_px(img, cen + Vector2i(roundi(cos(a) * rr), roundi(sin(a) * rr * 0.6)), Color("7fd64e"), 0.85)
	_px(img, cen + Vector2i(-1, -1), Color("c8f59a"), 0.8)


## A meat mallet's tooth marks: a 3 x 3 grid of dimples.
static func _mallet(img: Image, o: Vector2i, row: int, furrow: Color, lip: Color,
		rng: RandomNumberGenerator) -> void:
	var cen := Vector2i(o.x + CELL / 2, row * CELL + CELL / 2)
	for gy in 3:
		for gx in 3:
			var p := cen + Vector2i((gx - 1) * 4 - 1, (gy - 1) * 4 - 1)
			if rng.randf() < 0.12:
				continue
			_px(img, p, furrow, 0.9)
			_px(img, p + Vector2i(1, 0), furrow, 0.9)
			_px(img, p + Vector2i(0, 1), furrow, 0.9)
			_px(img, p + Vector2i(1, 1), lip, 0.6)
