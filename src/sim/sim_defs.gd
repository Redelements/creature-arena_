class_name SimDefs
extends RefCounted
## Shared constants for the deterministic simulation.
## Nothing in src/sim/ reads the clock, the screen, or a random number generator:
## the same inputs always produce the same match.

const TICK_RATE := 60

# One input bitmask per player per tick. Replays are just arrays of these.
const IN_UP := 1
const IN_DOWN := 2
const IN_LEFT := 4
const IN_RIGHT := 8
const IN_LIGHT := 16
const IN_HEAVY := 32
const IN_DODGE := 64
const IN_GUARD := 128
const IN_SKILL1 := 256
const IN_SKILL2 := 512
const IN_SURGE := 1024
const IN_TAG := 2048  ## Duel: swap to the next teammate (ignored outside Duel)
const IN_ALL := 4095  ## every button

# 360-degree aim (twin-stick, mouse, aim assist). The direction bits above only make 8
# directions; an exact aim angle rides in the same input as an index into AIM_DIRS.
const IN_AIM := 4096  ## the aim index below is set; attacks go that way
const AIM_SHIFT := 13
const AIM_STEPS := 64  ## 5.625 degrees apart; index 0 = right, 16 = down (y grows downward)
const IN_STRAFE := 1 << 19  ## keep facing the aim while walking (twin-stick right stick held)
# 360-degree movement (a stick, or walking to a mouse click). The direction bits above
# still say roughly which way (menus, the CPU and old replays read them); when IN_MOVE is
# set, walking, dodging and attacks without an aim of their own go exactly this way.
const IN_MOVE := 1 << 20  ## the move index below is set
const MOVE_SHIFT := 21  ## 6 bits, an index into the same 64 directions as the aim
const IN_EVERYTHING := (1 << 27) - 1  ## buttons, aim, strafe and move, for fuzz tests
## Each aim direction as integers (x, y) / 10000, turned into unit vectors with only
## sqrt and division, which every platform rounds identically (no sin/cos in src/sim).
const AIM_INT := [
	[10000, 0], [9952, 980], [9808, 1951], [9569, 2903], [9239, 3827], [8819, 4714], [8315, 5556], [7730, 6344],
	[7071, 7071], [6344, 7730], [5556, 8315], [4714, 8819], [3827, 9239], [2903, 9569], [1951, 9808], [980, 9952],
	[0, 10000], [-980, 9952], [-1951, 9808], [-2903, 9569], [-3827, 9239], [-4714, 8819], [-5556, 8315], [-6344, 7730],
	[-7071, 7071], [-7730, 6344], [-8315, 5556], [-8819, 4714], [-9239, 3827], [-9569, 2903], [-9808, 1951], [-9952, 980],
	[-10000, 0], [-9952, -980], [-9808, -1951], [-9569, -2903], [-9239, -3827], [-8819, -4714], [-8315, -5556], [-7730, -6344],
	[-7071, -7071], [-6344, -7730], [-5556, -8315], [-4714, -8819], [-3827, -9239], [-2903, -9569], [-1951, -9808], [-980, -9952],
	[0, -10000], [980, -9952], [1951, -9808], [2903, -9569], [3827, -9239], [4714, -8819], [5556, -8315], [6344, -7730],
	[7071, -7071], [7730, -6344], [8315, -5556], [8819, -4714], [9239, -3827], [9569, -2903], [9808, -1951], [9952, -980],
]
static var _aim_dirs: Array[Vector2] = []

# Attack types. A combo can cancel from a lower rank into a higher one.
const TYPE_RANK := {"light": 1, "heavy": 2, "skill": 3, "surge": 4}
const TYPE_BIT := {"light": 1, "heavy": 2, "skill": 4, "surge": 8}
## Damage multiplier by how many different attack types have landed in the combo.
const VARIETY := [1.0, 1.0, 1.15, 1.3, 1.5]

# Arena geometry in logical pixels. The screen shows 480x270 of it at a time (more when
# the camera pulls back); the stadium is bigger, so the camera follows the fight.
const VIEW_W := 480
const VIEW_H := 270
const CELL := 8
const GRID_X := 16  ## side wall
const GRID_Y := 64  ## stands and back wall above the floor
const GRID_COLS := 84  ## 672 px: 1.5x the original 56
const GRID_ROWS := 36  ## 288 px: 1.5x the original 24
const FRONT_WALL := 14  ## below the floor
const ARENA_W := GRID_X * 2 + GRID_COLS * CELL  ## the whole stadium, walls included
const ARENA_H := GRID_Y + GRID_ROWS * CELL + FRONT_WALL


## The stadium-sized floor (GRID_COLS x GRID_ROWS). A map can be bigger ("size" in its
## JSON): code with a match at hand asks it (`MatchSim.floor_rect`, `TerrainGrid.floor_rect`).
static func floor_rect() -> Rect2:
	return floor_rect_of(GRID_COLS, GRID_ROWS)


## The floor of a grid `cols` x `rows` cells: its corner is always (GRID_X, GRID_Y).
static func floor_rect_of(cols: int, rows: int) -> Rect2:
	return Rect2(GRID_X, GRID_Y, cols * CELL, rows * CELL)


static func arena_size() -> Vector2:
	return Vector2(ARENA_W, ARENA_H)


## The whole stadium round a floor of `cols` x `rows` cells, walls included.
static func arena_size_of(cols: int, rows: int) -> Vector2:
	return Vector2(GRID_X * 2 + cols * CELL, GRID_Y + rows * CELL + FRONT_WALL)


static func dir_from_bits(bits: int) -> Vector2:
	var x := (1 if bits & IN_RIGHT else 0) - (1 if bits & IN_LEFT else 0)
	var y := (1 if bits & IN_DOWN else 0) - (1 if bits & IN_UP else 0)
	return Vector2(x, y).normalized()


static func aim_dirs() -> Array[Vector2]:
	if _aim_dirs.is_empty():
		for p in AIM_INT:
			_aim_dirs.append(Vector2(float(p[0]), float(p[1])).normalized())
	return _aim_dirs


## The way an attack aims: the exact aim angle when one is set, else the way you move.
static func aim_from_bits(bits: int) -> Vector2:
	if bits & IN_AIM:
		return aim_dirs()[(bits >> AIM_SHIFT) & (AIM_STEPS - 1)]
	return move_from_bits(bits)


## The way you walk: the exact move angle when one is set, else the 8 direction bits.
static func move_from_bits(bits: int) -> Vector2:
	if bits & IN_MOVE:
		return aim_dirs()[(bits >> MOVE_SHIFT) & (AIM_STEPS - 1)]
	return dir_from_bits(bits)


## Input side: the bits for walking toward `v` in 360 degrees: the nearest of the 64
## directions, plus the rough direction bits. 0 for none.
static func move_bits(v: Vector2) -> int:
	var a := aim_bits(v)
	if a == 0:
		return 0
	return bits_from_dir(v.normalized()) | IN_MOVE | (((a >> AIM_SHIFT) & (AIM_STEPS - 1)) << MOVE_SHIFT)


## Input side: the aim bits for a direction (the nearest of the 64), or 0 for none.
## Picks by dot product, so no trig is needed here either.
static func aim_bits(v: Vector2) -> int:
	if v.length_squared() < 1e-6:
		return 0
	return IN_AIM | (aim_index(v) << AIM_SHIFT)


## The index (0-63) of the aim table entry nearest to `v`: the largest dot product, ties
## to the lower index. 0 for a zero vector. No trig.
static func aim_index(v: Vector2) -> int:
	var best := 0
	var best_dot := -INF
	var dirs := aim_dirs()
	for i in AIM_STEPS:
		var d := dirs[i].dot(v)
		if d > best_dot:
			best_dot = d
			best = i
	return best


static func bits_from_dir(d: Vector2) -> int:
	var b := 0
	if d.x > 0.3:
		b |= IN_RIGHT
	elif d.x < -0.3:
		b |= IN_LEFT
	if d.y > 0.3:
		b |= IN_DOWN
	elif d.y < -0.3:
		b |= IN_UP
	return b


static func variety_mult(types_mask: int) -> float:
	var n := 0
	for b in [1, 2, 4, 8]:
		if types_mask & b:
			n += 1
	return VARIETY[n]
