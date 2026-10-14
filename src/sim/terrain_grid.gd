class_name TerrainGrid
extends RefCounted
## The arena floor as a grid of 8x8 cells. Attacks crack cells and punch holes;
## damaged cells heal back one step every HEAL_TICKS.

const INTACT := 0
const CRACKED := 1
const HOLE := 2
const HEAL_TICKS := 720  # 12 seconds at 60 Hz
const CRACK_BAND := 10.0

var cols: int
var rows: int
var cells := PackedByteArray()
var timers := PackedInt32Array()
## Bumps whenever any cell changes, so the view knows when to redraw.
var version := 0


func _init(c: int = SimDefs.GRID_COLS, r: int = SimDefs.GRID_ROWS) -> void:
	cols = c
	rows = r
	cells.resize(cols * rows)
	cells.fill(INTACT)
	timers.resize(cols * rows)
	timers.fill(0)


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


func get_cell(c: Vector2i) -> int:
	if not in_bounds(c):
		return INTACT
	return cells[c.y * cols + c.x]


func set_cell(c: Vector2i, value: int) -> void:
	if not in_bounds(c):
		return
	var i := c.y * cols + c.x
	cells[i] = value
	timers[i] = HEAL_TICKS if value != INTACT else 0
	version += 1


func is_hole_at(p: Vector2) -> bool:
	return get_cell(world_to_cell(p)) == HOLE


## `heal`: ticks before this damage starts to mend (HEAL_TICKS unless the move says
## otherwise: Culvert's holes stay open longer).
func damage_cell(c: Vector2i, amount: int, heal := HEAL_TICKS) -> void:
	if not in_bounds(c) or amount <= 0:
		return
	var i := c.y * cols + c.x
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
	if cells[i] == INTACT:
		cells[i] = CRACKED
		version += 1
	if cells[i] != INTACT:
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


func tick() -> void:
	for i in cells.size():
		if cells[i] == INTACT:
			continue
		timers[i] -= 1
		if timers[i] <= 0:
			cells[i] -= 1
			timers[i] = HEAL_TICKS if cells[i] != INTACT else 0
			version += 1


## Centre of the closest cell that is not a hole (searches outward in rings).
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
				if not in_bounds(c) or get_cell(c) == HOLE:
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
