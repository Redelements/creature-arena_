class_name NavGrid
extends RefCounted
## A coarse walkable map of the arena for the CPU: 16 px nodes (2×2 terrain cells),
## blocked where any cell is a wall, a fence or a pit, costlier through shallows. A
## path is found with integer costs in a fixed neighbour order, so every machine and
## every run gets the same answer (the CPU is deterministic, like the sim). The grid
## is rebuilt whenever the terrain changes (walls smashed, holes opened or healed).

const NODE := 2  ## cells per node side
const STRAIGHT := 2  ## cost of a straight step
const DIAGONAL := 3  ## and a diagonal one (about √2 × 2)
const SHALLOWS_EXTRA := 2  ## added per step into shallows
const BRUSH_EXTRA := 1

## Neighbours in a fixed order: the four straight steps first, then the diagonals.
const STEPS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

var cols := 0
var rows := 0
var blocked := PackedByteArray()
var extra := PackedByteArray()  ## added cost of stepping onto a node
var _version := -1


func _index(n: Vector2i) -> int:
	return n.y * cols + n.x


func in_bounds(n: Vector2i) -> bool:
	return n.x >= 0 and n.y >= 0 and n.x < cols and n.y < rows


## Rebuilds from the terrain when it has changed since the last call.
func update(t: TerrainGrid) -> void:
	if t.version == _version and cols > 0:
		return
	_version = t.version
	cols = t.cols / NODE
	rows = t.rows / NODE
	blocked.resize(cols * rows)
	extra.resize(cols * rows)
	for ny in rows:
		for nx in cols:
			var b := 0
			var e := 0
			for dy in NODE:
				for dx in NODE:
					var v := t.get_cell(Vector2i(nx * NODE + dx, ny * NODE + dy))
					if TerrainGrid.blocks_body(v) or TerrainGrid.is_pit(v):
						b = 1
					elif v == TerrainGrid.SHALLOWS:
						e = maxi(e, SHALLOWS_EXTRA)
					elif v == TerrainGrid.BRUSH:
						e = maxi(e, BRUSH_EXTRA)
			blocked[ny * cols + nx] = b
			extra[ny * cols + nx] = e


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
static func clear_line(t: TerrainGrid, a: Vector2, b: Vector2, r: float, holes := true) -> bool:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		return true
	var n := int(len / 4.0) + 1
	for i in range(1, n + 1):
		var p := a + d * (float(i) / float(n))
		var v := t.get_cell(t.world_to_cell(p))
		if v == TerrainGrid.CHASM or (holes and v == TerrainGrid.HOLE) or t.body_blocked(p, r):
			return false
	return true


## The cheapest path from `from` to `to` as node centres, the start's node left out,
## the goal's node last. Empty when either end has no open node or none connects them.
## Dijkstra with a bucket queue over integer costs: no floats, no heap tie-breaking.
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var s := nearest_open(from)
	var g := nearest_open(to)
	if s.x < 0 or g.x < 0:
		return out
	if s == g:
		out.append(center_of(g))
		return out
	var n := cols * rows
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 30)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var si := _index(s)
	var gi := _index(g)
	dist[si] = 0
	# Buckets by cost: a step costs at most DIAGONAL + extra, so a small ring suffices.
	var span := DIAGONAL + SHALLOWS_EXTRA + 1
	var buckets: Array = []
	for i in span:
		buckets.append(PackedInt32Array())
	buckets[0].append(si)
	var cost := 0
	var pending := 1
	while pending > 0:
		var b: PackedInt32Array = buckets[cost % span]
		if b.is_empty():
			cost += 1
			continue
		var queue := b.duplicate()
		buckets[cost % span] = PackedInt32Array()
		for i in queue:
			pending -= 1
			if dist[i] != cost:
				continue  # a stale entry: this node was reached cheaper
			if i == gi:
				pending = 0
				break
			var here := Vector2i(i % cols, i / cols)
			for k in STEPS.size():
				var step: Vector2i = STEPS[k]
				var nb := here + step
				if is_blocked(nb):
					continue
				if k >= 4 and (is_blocked(here + Vector2i(step.x, 0)) or is_blocked(here + Vector2i(0, step.y))):
					continue  # no cutting a corner past a blocked node
				var j := _index(nb)
				var c := cost + (STRAIGHT if k < 4 else DIAGONAL) + int(extra[j])
				if c < dist[j]:
					dist[j] = c
					prev[j] = i
					buckets[c % span].append(j)
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
