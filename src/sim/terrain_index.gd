class_name TerrainIndex
extends RefCounted
## Summed-area counts over a TerrainGrid's cells, so "is there any wall, fence or pit in
## this box of cells?" is four lookups instead of a walk. The CPU's line and body checks
## (NavGrid) and line of sight (Vision) ask it first and only walk the cells when the box
## holds something; the answers are exactly what the walk alone gives.
##
## Not match state: a pure function of the terrain's cells, rebuilt when `version`
## changes, and shared by everyone reading the same grid (`of`). Integers only.

## Cell classes counted: bodies stop (and sight is blocked) at walls and fences; pits are
## holes and chasms; chasms alone are what a walk that leaves holes to steering avoids.
var body := PackedInt32Array()
var pit := PackedInt32Array()
var chasm := PackedInt32Array()
var cols := 0
var rows := 0
var _version := -1

## terrain instance id -> TerrainIndex, for the few grids alive at once.
static var _shared := {}


## The index for `t`, brought up to date.
static func of(t: TerrainGrid) -> TerrainIndex:
	var id := t.get_instance_id()
	var ix: TerrainIndex = _shared.get(id)
	if ix == null:
		if _shared.size() >= 8:
			_shared.clear()  # old matches' grids; whoever is still alive rebuilds
		ix = TerrainIndex.new()
		_shared[id] = ix
	if ix._version != t.version or ix.cols != t.cols or ix.rows != t.rows:
		ix._build(t)
	return ix


func _build(t: TerrainGrid) -> void:
	_version = t.version
	cols = t.cols
	rows = t.rows
	var w := cols + 1
	var n := w * (rows + 1)
	body.resize(n)
	pit.resize(n)
	chasm.resize(n)
	body.fill(0)
	pit.fill(0)
	chasm.fill(0)
	var cells := t.cells
	for y in rows:
		var rb := 0
		var rp := 0
		var rc := 0
		var row := y * cols
		var up := y * w + 1
		var at := up + w
		for x in cols:
			var v := cells[row + x]
			if v == TerrainGrid.WALL or v == TerrainGrid.FENCE:
				rb += 1
			elif v == TerrainGrid.CHASM:
				rc += 1
				rp += 1
			elif v == TerrainGrid.HOLE:
				rp += 1
			body[at + x] = body[up + x] + rb
			pit[at + x] = pit[up + x] + rp
			chasm[at + x] = chasm[up + x] + rc


## How many cells of `sat` lie in the cell box (x0, y0)..(x1, y1), corners included
## and clipped to the grid (cells off the grid are plain floor).
func count(sat: PackedInt32Array, x0: int, y0: int, x1: int, y1: int) -> int:
	x0 = maxi(x0, 0)
	y0 = maxi(y0, 0)
	x1 = mini(x1, cols - 1)
	y1 = mini(y1, rows - 1)
	if x0 > x1 or y0 > y1:
		return 0
	var w := cols + 1
	return sat[(y1 + 1) * w + x1 + 1] - sat[y0 * w + x1 + 1] - sat[(y1 + 1) * w + x0] + sat[y0 * w + x0]


## Whether any wall or fence is within the cells a circle at `p` of radius `r` touches
## (TerrainGrid._around): false means TerrainGrid.body_blocked(p, r) is false.
func body_near(t: TerrainGrid, p: Vector2, r: float) -> bool:
	var c0 := t.world_to_cell(p - Vector2(r, r))
	var c1 := t.world_to_cell(p + Vector2(r, r))
	return count(body, c0.x, c0.y, c1.x, c1.y) > 0
