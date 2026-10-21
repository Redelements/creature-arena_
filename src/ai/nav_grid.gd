class_name NavGrid
extends RefCounted
## A coarse walkable map of the arena for the CPU: 16 px nodes (2×2 terrain cells),
## blocked where any cell is a wall, a fence or a pit, costlier through shallows. A
## path is found with integer costs in a fixed neighbour order, so every machine and
## every run gets the same answer (the CPU is deterministic, like the sim). The grid
## is rebuilt whenever the terrain changes (walls smashed, holes opened or healed).
##
## Every CPU in a match reads the same floor, so they share one grid (`shared`): with
## eight CPUs a rebuild happens once, not eight times. Open nodes are labelled by the
## region they connect to, so a path between two regions that don't meet is known to be
## empty without searching the whole map.

const NODE := 2  ## cells per node side
const STRAIGHT := 2  ## cost of a straight step
const DIAGONAL := 3  ## and a diagonal one (about √2 × 2)
const SHALLOWS_EXTRA := 2  ## added per step into shallows
const BRUSH_EXTRA := 1

## Neighbours in a fixed order: the four straight steps first, then the diagonals.
const STEPS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const STEP_X: Array[int] = [1, -1, 0, 0, 1, -1, 1, -1]
const STEP_Y: Array[int] = [0, 0, 1, -1, 1, 1, -1, -1]

var cols := 0
var rows := 0
var blocked := PackedByteArray()
var extra := PackedByteArray()  ## added cost of stepping onto a node
## The connected region of each open node (-1 when blocked): a path exists only
## between nodes of the same region.
var region := PackedInt32Array()
var _regions_ok := false
var _label_lock := Mutex.new()
var _parent := PackedInt32Array()  ## union-find over row runs, while labelling
var _cells := PackedByteArray()  ## the cells last built from, to find the rows that changed
var _version := -1
var _terrain_id := 0

## terrain instance id -> NavGrid, for the few grids alive at once.
static var _shared := {}


## The grid for `t`, shared by every CPU reading that terrain, brought up to date.
static func shared(t: TerrainGrid) -> NavGrid:
	var id := t.get_instance_id()
	var g: NavGrid = _shared.get(id)
	if g == null:
		if _shared.size() >= 8:
			_shared.clear()  # old matches' grids; whoever is still alive rebuilds
		g = NavGrid.new()
		_shared[id] = g
	g.update(t)
	return g


func _index(n: Vector2i) -> int:
	return n.y * cols + n.x


func in_bounds(n: Vector2i) -> bool:
	return n.x >= 0 and n.y >= 0 and n.x < cols and n.y < rows


## Rebuilds from the terrain when it has changed since the last call: only the node
## rows whose cells changed (a hole opening, a wall smashed) are worked out again, and
## the regions only when a node's blocked state changed.
func update(t: TerrainGrid) -> void:
	if t.version == _version and t.get_instance_id() == _terrain_id and cols > 0:
		return
	_version = t.version
	var fresh := t.get_instance_id() != _terrain_id or cols != t.cols / NODE or rows != t.rows / NODE 			or _cells.size() != t.cells.size()
	_terrain_id = t.get_instance_id()
	cols = t.cols / NODE
	rows = t.rows / NODE
	if fresh:
		blocked.resize(cols * rows)
		extra.resize(cols * rows)
		_regions_ok = false
	var cells := t.cells
	var tc := t.cols
	var span := tc * NODE  # the cells under one row of nodes
	for ny in rows:
		var c0 := ny * span
		if not fresh and cells.slice(c0, c0 + span) == _cells.slice(c0, c0 + span):
			continue
		for nx in cols:
			var b := 0
			var e := 0
			for dy in NODE:
				var row := c0 + dy * tc + nx * NODE
				for dx in NODE:
					var v := cells[row + dx]
					if v == TerrainGrid.WALL or v == TerrainGrid.FENCE or v == TerrainGrid.HOLE 							or v == TerrainGrid.CHASM:
						b = 1
					elif v == TerrainGrid.SHALLOWS:
						e = maxi(e, SHALLOWS_EXTRA)
					elif v == TerrainGrid.BRUSH:
						e = maxi(e, BRUSH_EXTRA)
			var i := ny * cols + nx
			if blocked[i] != b:
				_regions_ok = false
			blocked[i] = b
			extra[i] = e
	_cells = cells.duplicate()


## Labels the open nodes by region, so two nodes share one exactly when a path joins
## them. A diagonal step needs both straight neighbours open, so it never joins what
## straight steps don't: regions are the straight-step components, found by runs of
## open nodes along each row, merged with the runs they touch in the row above.
func _label_regions() -> void:
	var n := cols * rows
	region.resize(n)
	region.fill(-1)
	_parent.clear()
	for y in rows:
		var x := 0
		while x < cols:
			if blocked[y * cols + x] == 1:
				x += 1
				continue
			var run := _parent.size()
			_parent.append(run)
			while x < cols and blocked[y * cols + x] == 0:
				region[y * cols + x] = run
				if y > 0:
					var up := region[(y - 1) * cols + x]
					if up >= 0:
						_union(run, up)
				x += 1
	for i in n:
		if region[i] >= 0:
			region[i] = _root(region[i])
	_regions_ok = true


func _root(a: int) -> int:
	while _parent[a] != a:
		_parent[a] = _parent[_parent[a]]
		a = _parent[a]
	return a


func _union(a: int, b: int) -> void:
	var ra := _root(a)
	var rb := _root(b)
	if ra != rb:
		_parent[maxi(ra, rb)] = mini(ra, rb)


## The node one step `k` (an index into STEPS) from node (x, y), or -1 when that step
## is off the grid, onto a blocked node, or cuts a corner past one.
func _step(x: int, y: int, k: int) -> int:
	var nx := x + STEP_X[k]
	var ny := y + STEP_Y[k]
	if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
		return -1
	var j := ny * cols + nx
	if blocked[j] == 1:
		return -1
	if k >= 4 and (blocked[y * cols + nx] == 1 or blocked[ny * cols + x] == 1):
		return -1  # no cutting a corner past a blocked node
	return j


func node_of(p: Vector2) -> Vector2i:
	return Vector2i(
		floori((p.x - SimDefs.GRID_X) / (SimDefs.CELL * NODE)),
		floori((p.y - SimDefs.GRID_Y) / (SimDefs.CELL * NODE)))


func center_of(n: Vector2i) -> Vector2:
	return Vector2(SimDefs.GRID_X + (n.x + 0.5) * SimDefs.CELL * NODE,
		SimDefs.GRID_Y + (n.y + 0.5) * SimDefs.CELL * NODE)


func is_blocked(n: Vector2i) -> bool:
	return not in_bounds(n) or blocked[_index(n)] == 1


## The nearest open node to `p` (rings outward), or (-1, -1) when there is none.
func nearest_open(p: Vector2) -> Vector2i:
	var start := node_of(p)
	start = Vector2i(clampi(start.x, 0, cols - 1), clampi(start.y, 0, rows - 1))
	if not is_blocked(start):
		return start
	for r in range(1, maxi(cols, rows)):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := start + Vector2i(dx, dy)
				if is_blocked(n):
					continue
				var d := center_of(n).distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = n
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Whether a body of radius `r` can go straight from `a` to `b` without meeting a wall,
## a fence or a chasm; with `holes`, a healing hole counts too. Samples every 4 px.
## Open floor (nothing solid in the box round the line) answers without sampling.
static func clear_line(t: TerrainGrid, a: Vector2, b: Vector2, r: float, holes := true) -> bool:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		return true
	var ix := TerrainIndex.of(t)
	# Every cell a sample can touch lies in this box (one cell wider for rounding).
	var c0 := t.world_to_cell(Vector2(minf(a.x, b.x) - r, minf(a.y, b.y) - r)) - Vector2i.ONE
	var c1 := t.world_to_cell(Vector2(maxf(a.x, b.x) + r, maxf(a.y, b.y) + r)) + Vector2i.ONE
	var any_body := ix.count(ix.body, c0.x, c0.y, c1.x, c1.y) > 0
	var any_pit := ix.count(ix.pit if holes else ix.chasm, c0.x, c0.y, c1.x, c1.y) > 0
	if not any_body and not any_pit:
		return true
	var n := int(len / 4.0) + 1
	for i in range(1, n + 1):
		var p := a + d * (float(i) / float(n))
		if any_pit:
			var v := t.get_cell(t.world_to_cell(p))
			if v == TerrainGrid.CHASM or (holes and v == TerrainGrid.HOLE):
				return false
		if any_body and ix.body_near(t, p, r) and t.body_blocked(p, r):
			return false
	return true


## TerrainGrid.body_blocked (fences count), skipping the cell walk on open floor.
static func body_blocked(t: TerrainGrid, p: Vector2, r: float) -> bool:
	return TerrainIndex.of(t).body_near(t, p, r) and t.body_blocked(p, r)


## The cheapest path from `from` to `to` as node centres, the start's node left out,
## the goal's node last. Empty when either end has no open node or none connects them.
## A* over integer costs with a bucket queue keyed on cost so far plus the octile
## distance left (which never overestimates, so the path found is a cheapest one); ties
## go in a fixed order, no floats, no heap. It searches toward the goal instead of
## flooding the whole map.
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var s := nearest_open(from)
	var g := nearest_open(to)
	if s.x < 0 or g.x < 0:
		return out
	if s == g:
		out.append(center_of(g))
		return out
	var si := _index(s)
	var gi := _index(g)
	if not _regions_ok:
		# Labelled on the first search after a change; CPUs thinking on several threads
		# (CpuController.think_all) may get here together, so one labels, the rest wait.
		_label_lock.lock()
		if not _regions_ok:
			_label_regions()
		_label_lock.unlock()
	if region[si] != region[gi]:
		return out  # nothing joins them: no search needed
	var n := cols * rows
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 30)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	dist[si] = 0
	# Buckets by estimate: one step raises it by at most two diagonals plus shallows.
	var span := 2 * DIAGONAL + SHALLOWS_EXTRA + 1
	var buckets: Array[PackedInt32Array] = []
	for i in span:
		buckets.append(PackedInt32Array())
	var est := _left(s.x, s.y, g.x, g.y)
	buckets[est % span].append(si)
	var pending := 1
	while pending > 0:
		var slot := est % span
		if buckets[slot].is_empty():
			est += 1
			continue
		var queue := buckets[slot]
		buckets[slot] = PackedInt32Array()  # a step that keeps the estimate lands here again
		for i in queue:
			pending -= 1
			var x := i % cols
			var y := i / cols
			var cost := dist[i]
			if cost + _left(x, y, g.x, g.y) != est:
				continue  # a stale entry: this node was reached cheaper
			if i == gi:
				pending = 0
				break
			for k in 8:
				var j := _step(x, y, k)
				if j < 0:
					continue
				var c := cost + (STRAIGHT if k < 4 else DIAGONAL) + int(extra[j])
				if c < dist[j]:
					dist[j] = c
					prev[j] = i
					buckets[(c + _left(j % cols, j / cols, g.x, g.y)) % span].append(j)
					pending += 1
	if prev[gi] < 0:
		return out
	var chain: Array[int] = []
	var at := gi
	while at != si and at >= 0:
		chain.append(at)
		at = prev[at]
	chain.reverse()
	for i in chain:
		out.append(center_of(Vector2i(i % cols, i / cols)))
	return out


## The cheapest a walk from node (x, y) to (gx, gy) could cost on open floor.
static func _left(x: int, y: int, gx: int, gy: int) -> int:
	var dx := absi(x - gx)
	var dy := absi(y - gy)
	return DIAGONAL * mini(dx, dy) + STRAIGHT * absi(dx - dy)
