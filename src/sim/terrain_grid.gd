class_name TerrainGrid
extends RefCounted
## The arena floor as a grid of 8x8 cells. Attacks crack cells and punch holes;
## damaged cells heal back one step every HEAL_TICKS, toward the map's own state for
## that cell (`base`): plain floor on the stadium, or a fixed piece an arena map put
## there (a rubble wall, a fence, a chasm, shallows, brush). A smashed wall is cracked
## floor until it rebuilds; flattened brush grows back; a chasm never changes.

const INTACT := 0
const CRACKED := 1
const HOLE := 2
## Fixed pieces from an arena map (data/arenas/*.json).
const WALL := 3  ## rubble: stops bodies and shots; the heavy charges smash it
const FENCE := 4  ## stops bodies, not shots; ghost dashes and blinks cross it
const CHASM := 5  ## a pit that never heals; leaps cross it
const SHALLOWS := 6  ## slows walking
const BRUSH := 7  ## slows a little; hides whoever stands in it
const BRUSH_FLAT := 8  ## brush a dash flattened; grows back
const HEAL_TICKS := 720  # 12 seconds at 60 Hz
const CRACK_BAND := 10.0
## Walking speed on the slow pieces.
const SHALLOWS_WALK := 0.6
const BRUSH_WALK := 0.85

var cols: int
var rows: int
var cells := PackedByteArray()
var timers := PackedInt32Array()
## What each cell heals back to: INTACT, or the map's piece there. Set once per match.
var base := PackedByteArray()
## Bumps whenever any cell changes, so the view knows when to redraw.
var version := 0


## This grid's floor in world pixels, and the whole stadium round it.
func floor_rect() -> Rect2:
	return SimDefs.floor_rect_of(cols, rows)


func arena_size() -> Vector2:
	return SimDefs.arena_size_of(cols, rows)


func _init(c: int = SimDefs.GRID_COLS, r: int = SimDefs.GRID_ROWS) -> void:
	cols = c
	rows = r
	cells.resize(cols * rows)
	cells.fill(INTACT)
	timers.resize(cols * rows)
	timers.fill(0)
	base.resize(cols * rows)
	base.fill(INTACT)


## Lays an arena map's pieces: `pieces` is a list of {kind, rect: [cx, cy, w, h]} in
## cells (kinds: wall, fence, chasm, shallows, brush), `rows` an optional list of
## strings (one character per cell: `.` floor, `#` wall, `F` fence, `X` chasm,
## `~` shallows, `*` brush). Everything else is plain floor.
func load_map(map: Dictionary) -> void:
	cells.fill(INTACT)
	timers.fill(0)
	base.fill(INTACT)
	var strings: Array = map.get("rows", [])
	for cy in mini(rows, strings.size()):
		var line := String(strings[cy])
		for cx in mini(cols, line.length()):
			var v := piece_of_char(line[cx])
			if v != INTACT:
				base[cy * cols + cx] = v
	for p in map.get("pieces", []):
		var v := piece_of_name(String(p.get("kind", "")))
		var r: Array = p.get("rect", [0, 0, 0, 0])
		if v == INTACT or r.size() < 4:
			continue
		for cy in range(int(r[1]), int(r[1]) + int(r[3])):
			for cx in range(int(r[0]), int(r[0]) + int(r[2])):
				if in_bounds(Vector2i(cx, cy)):
					base[cy * cols + cx] = v
	for i in cells.size():
		cells[i] = base[i]
	version += 1


static func piece_of_name(name: String) -> int:
	match name:
		"wall": return WALL
		"fence": return FENCE
		"chasm": return CHASM
		"shallows": return SHALLOWS
		"brush": return BRUSH
	return INTACT


static func piece_of_char(ch: String) -> int:
	match ch:
		"#": return WALL
		"F": return FENCE
		"X": return CHASM
		"~": return SHALLOWS
		"*": return BRUSH
	return INTACT


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(
		floori((p.x - SimDefs.GRID_X) / SimDefs.CELL),
		floori((p.y - SimDefs.GRID_Y) / SimDefs.CELL))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(
		SimDefs.GRID_X + (c.x + 0.5) * SimDefs.CELL,
		SimDefs.GRID_Y + (c.y + 0.5) * SimDefs.CELL)


func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(SimDefs.GRID_X + c.x * SimDefs.CELL, SimDefs.GRID_Y + c.y * SimDefs.CELL,
		SimDefs.CELL, SimDefs.CELL)


func get_cell(c: Vector2i) -> int:
	if not in_bounds(c):
		return INTACT
	return cells[c.y * cols + c.x]


func get_base(c: Vector2i) -> int:
	if not in_bounds(c):
		return INTACT
	return base[c.y * cols + c.x]


func set_cell(c: Vector2i, value: int) -> void:
	if not in_bounds(c):
		return
	var i := c.y * cols + c.x
	cells[i] = value
	timers[i] = HEAL_TICKS if value != base[i] else 0
	version += 1


# ---------------------------------------------------------------- what a cell does

## A pit: a hole from damage, or a chasm the map drew. Bodies fall in.
static func is_pit(v: int) -> bool:
	return v == HOLE or v == CHASM


## Stops bodies (walking, dashes, knockback). A ghost dash slips through fences.
static func blocks_body(v: int, fences := true) -> bool:
	return v == WALL or (fences and v == FENCE)


## Stops shots (not lobs, which fly over).
static func blocks_shot(v: int) -> bool:
	return v == WALL


## Ground a creature can stand on: not a pit, not a piece that stops bodies.
static func is_walkable(v: int) -> bool:
	return not is_pit(v) and not blocks_body(v)


## Walking speed multiplier on this cell.
static func walk_mult_of(v: int) -> float:
	if v == SHALLOWS:
		return SHALLOWS_WALK
	if v == BRUSH:
		return BRUSH_WALK
	return 1.0


func is_hole_at(p: Vector2) -> bool:
	return is_pit(get_cell(world_to_cell(p)))


func solid_at(p: Vector2) -> bool:
	return blocks_body(get_cell(world_to_cell(p)))


func walk_mult_at(p: Vector2) -> float:
	return walk_mult_of(get_cell(world_to_cell(p)))


# ---------------------------------------------------------------- bodies vs pieces

## The cells a body circle at `p` with radius `r` could touch.
func _around(p: Vector2, r: float) -> Rect2i:
	var c0 := world_to_cell(p - Vector2(r, r))
	var c1 := world_to_cell(p + Vector2(r, r))
	return Rect2i(c0, c1 - c0 + Vector2i.ONE)


static func _overlaps(rect: Rect2, p: Vector2, r: float) -> bool:
	var q := p.clamp(rect.position, rect.end)
	return q.distance_squared_to(p) < r * r


## Where a body sliding along x from `p` to x = `nx` actually gets to before a wall or
## fence stops it (its y stays `p.y`). Never pulls it back behind where it started.
func slide_x(p: Vector2, nx: float, r: float, fences := true) -> float:
	if nx == p.x:
		return nx
	var right := nx > p.x
	var span := _around(Vector2(nx, p.y), r)
	for cy in range(span.position.y, span.end.y):
		for cx in range(span.position.x, span.end.x):
			var c := Vector2i(cx, cy)
			if not blocks_body(get_cell(c), fences):
				continue
			var rect := cell_rect(c)
			if not _overlaps(rect, Vector2(nx, p.y), r):
				continue
			nx = minf(nx, rect.position.x - r) if right else maxf(nx, rect.end.x + r)
	return maxf(nx, p.x) if right else minf(nx, p.x)


func slide_y(p: Vector2, ny: float, r: float, fences := true) -> float:
	if ny == p.y:
		return ny
	var down := ny > p.y
	var span := _around(Vector2(p.x, ny), r)
	for cy in range(span.position.y, span.end.y):
		for cx in range(span.position.x, span.end.x):
			var c := Vector2i(cx, cy)
			if not blocks_body(get_cell(c), fences):
				continue
			var rect := cell_rect(c)
			if not _overlaps(rect, Vector2(p.x, ny), r):
				continue
			ny = minf(ny, rect.position.y - r) if down else maxf(ny, rect.end.y + r)
	return maxf(ny, p.y) if down else minf(ny, p.y)


## Whether a body circle overlaps any wall or fence.
func body_blocked(p: Vector2, r: float, fences := true) -> bool:
	var span := _around(p, r)
	for cy in range(span.position.y, span.end.y):
		for cx in range(span.position.x, span.end.x):
			var c := Vector2i(cx, cy)
			if blocks_body(get_cell(c), fences) and _overlaps(cell_rect(c), p, r):
				return true
	return false


## The cells of one state a body circle touches.
func cells_touching(p: Vector2, r: float, state: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var span := _around(p, r)
	for cy in range(span.position.y, span.end.y):
		for cx in range(span.position.x, span.end.x):
			var c := Vector2i(cx, cy)
			if get_cell(c) == state and _overlaps(cell_rect(c), p, r):
				out.append(c)
	return out


## Pushes a body out of any wall or fence it overlaps (a wall rebuilt under it, a push
## from another body, a blink into one). A body clipping a cell's edge is nudged out of
## it; one whose centre is inside the piece takes the shortest straight way out.
func resolve_body(p: Vector2, r: float, fences := true) -> Vector2:
	if not body_blocked(p, r, fences):
		return p
	for pass_ in 3:
		var moved := false
		var span := _around(p, r)
		for cy in range(span.position.y, span.end.y):
			for cx in range(span.position.x, span.end.x):
				var c := Vector2i(cx, cy)
				if not blocks_body(get_cell(c), fences):
					continue
				var rect := cell_rect(c)
				if not _overlaps(rect, p, r):
					continue
				var q := p.clamp(rect.position, rect.end)
				var d := p - q
				if d.length_squared() > 0.0001:
					p += d.normalized() * (r - d.length())
					moved = true
		if not moved:
			break
	if not body_blocked(p, r, fences):
		return p
	var best := p
	var best_k := 1 << 30
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		for k in range(1, 97):
			if k >= best_k:
				break
			var q: Vector2 = p + dir * float(k)
			if not body_blocked(q, r, fences):
				best = q
				best_k = k
				break
	return best


## Whether a body circle touches any cell of `rect` (cells).
func body_touches(p: Vector2, r: float, c: Vector2i) -> bool:
	return _overlaps(cell_rect(c), p, r)


# ---------------------------------------------------------------- damage and healing

## `heal`: ticks before this damage starts to mend (HEAL_TICKS unless the move says
## otherwise: Culvert's holes stay open longer). Fixed pieces don't take floor damage;
## the floor of a smashed wall does, and heals back to the wall.
func damage_cell(c: Vector2i, amount: int, heal := HEAL_TICKS) -> void:
	if not in_bounds(c) or amount <= 0:
		return
	var i := c.y * cols + c.x
	if cells[i] > HOLE:
		return
	var next := mini(cells[i] + amount, HOLE)
	if next != cells[i]:
		cells[i] = next
		version += 1
	timers[i] = maxi(timers[i], heal)  # fresh damage restarts the healing clock


## Damages a block of whole cells, `w` by `h` of them, centred on `center` (snapped to
## the grid, so the shape is the same wherever it lands): the inner block by `amount`,
## and a one-cell rim around it by one step when `rim` is set. A slam that always
## leaves the same rectangle, and two of them in one spot leave a rectangular hole.
func damage_rect(center: Vector2, w: int, h: int, amount: int, rim := false, heal := HEAL_TICKS) -> void:
	var c := world_to_cell(center)
	var x0 := c.x - (w - 1) / 2
	var y0 := c.y - (h - 1) / 2
	var pad := 1 if rim else 0
	for cy in range(y0 - pad, y0 + h + pad):
		for cx in range(x0 - pad, x0 + w + pad):
			var inside := cx >= x0 and cx < x0 + w and cy >= y0 and cy < y0 + h
			damage_cell(Vector2i(cx, cy), amount if inside else 1, heal)


## Cracks every cell within radius; cells within core_radius become holes.
func damage_circle(center: Vector2, radius: float, core_radius: float = -1.0, heal := HEAL_TICKS) -> void:
	var c0 := world_to_cell(center - Vector2(radius, radius))
	var c1 := world_to_cell(center + Vector2(radius, radius))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cy)
			if not in_bounds(c):
				continue
			var d := cell_center(c).distance_to(center)
			if d <= core_radius:
				damage_cell(c, 2, heal)
			elif d <= radius:
				damage_cell(c, 1, heal)


## Turns an intact cell into a cracked one (never opens a hole). Used by shockwaves.
func crack_cell(c: Vector2i) -> void:
	if not in_bounds(c):
		return
	var i := c.y * cols + c.x
	if cells[i] > HOLE:
		return
	if cells[i] == INTACT:
		cells[i] = CRACKED
		version += 1
	if cells[i] != base[i]:
		timers[i] = maxi(timers[i], HEAL_TICKS)


## Cracks every intact cell within radius, never opening a hole.
func crack_circle(center: Vector2, radius: float) -> void:
	var c0 := world_to_cell(center - Vector2(radius, radius))
	var c1 := world_to_cell(center + Vector2(radius, radius))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cy)
			if in_bounds(c) and cell_center(c).distance_to(center) <= radius:
				crack_cell(c)


## Cracks (never opens) the cells whose centres lie between inner and outer radius.
func crack_ring(center: Vector2, inner: float, outer: float) -> void:
	var c0 := world_to_cell(center - Vector2(outer, outer))
	var c1 := world_to_cell(center + Vector2(outer, outer))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cy)
			if not in_bounds(c):
				continue
			var d := cell_center(c).distance_to(center)
			if d >= inner and d <= outer:
				crack_cell(c)


## Opens a ring of holes between inner and outer radius, and cracks a band just outside it.
func damage_ring(center: Vector2, inner: float, outer: float, heal := HEAL_TICKS) -> void:
	var edge := outer + CRACK_BAND
	var c0 := world_to_cell(center - Vector2(edge, edge))
	var c1 := world_to_cell(center + Vector2(edge, edge))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cy)
			if not in_bounds(c):
				continue
			var d := cell_center(c).distance_to(center)
			if d >= inner and d <= outer:
				damage_cell(c, 2, heal)
			elif d > outer and d <= edge:
				damage_cell(c, 1, heal)


## A heavy charge smashes a rubble wall cell into cracked floor; it rebuilds later.
func smash(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var i := c.y * cols + c.x
	if cells[i] != WALL:
		return false
	cells[i] = CRACKED
	timers[i] = HEAL_TICKS
	version += 1
	return true


## A dash flattens brush; it grows back.
func flatten(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var i := c.y * cols + c.x
	if cells[i] != BRUSH:
		return false
	cells[i] = BRUSH_FLAT
	timers[i] = HEAL_TICKS
	version += 1
	return true


## Sinkhole: the cell drops into a chasm for good (the map's own state changes too).
func sink(c: Vector2i) -> void:
	if not in_bounds(c):
		return
	var i := c.y * cols + c.x
	cells[i] = CHASM
	base[i] = CHASM
	timers[i] = 0
	version += 1


## One healing step toward what the map put there.
static func heal_step(v: int, b: int) -> int:
	if b == INTACT:
		return v if v > HOLE else maxi(INTACT, v - 1)
	if b == WALL:
		return CRACKED if v == HOLE else WALL
	return b


## Heals every damaged cell a step when its timer runs out. `blocked` (a cell → bool),
## when given, says a body is standing there: a wall waits a tick rather than rebuilding
## under someone.
func tick(blocked := Callable()) -> void:
	for i in cells.size():
		if cells[i] == base[i]:
			continue
		timers[i] -= 1
		if timers[i] <= 0:
			var next := heal_step(cells[i], base[i])
			if blocks_body(next) and blocked.is_valid() and blocked.call(Vector2i(i % cols, i / cols)):
				timers[i] = 1
				continue
			cells[i] = next
			timers[i] = HEAL_TICKS if cells[i] != base[i] else 0
			version += 1


## Centre of the closest cell a creature can stand on (searches outward in rings).
func nearest_solid(p: Vector2) -> Vector2:
	var start := world_to_cell(p)
	for r in range(0, maxi(cols, rows)):
		var best := Vector2.INF
		var best_d := INF
		for cy in range(start.y - r, start.y + r + 1):
			for cx in range(start.x - r, start.x + r + 1):
				if maxi(absi(cx - start.x), absi(cy - start.y)) != r:
					continue
				var c := Vector2i(cx, cy)
				if not in_bounds(c) or not is_walkable(get_cell(c)):
					continue
				var d := cell_center(c).distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = cell_center(c)
		if best_d < INF:
			return best
	return p


func count(state: int) -> int:
	var n := 0
	for v in cells:
		if v == state:
			n += 1
	return n
