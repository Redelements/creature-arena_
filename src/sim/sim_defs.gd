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
const IN_EVERYTHING := (1 << 20) - 1  ## buttons, aim and strafe, for fuzz tests
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

# Arena geometry in logical pixels (the game renders at 480x270).
const VIEW_W := 480
const VIEW_H := 270
const CELL := 8
const GRID_X := 16
const GRID_Y := 64
const GRID_COLS := 56
const GRID_ROWS := 24


static func floor_rect() -> Rect2:
	return Rect2(GRID_X, GRID_Y, GRID_COLS * CELL, GRID_ROWS * CELL)


static func dir_from_bits(bits: int) -> Vector2:
	var x := (1 if bits & IN_RIGHT else 0) - (1 if bits & IN_LEFT else 0)
	var y := (1 if bits & IN_DOWN else 0) - (1 if bits & IN_UP else 0)
	return Vector2(x, y).normalized()


static func aim_dirs() -> Array[Vector2]:
	if _aim_dirs.is_empty():
		for p in AIM_INT:
			_aim_dirs.append(Vector2(float(p[0]), float(p[1])).normalized())
	return _aim_dirs


## The way an attack aims: the exact aim angle when one is set, else the direction bits.
static func aim_from_bits(bits: int) -> Vector2:
	if bits & IN_AIM:
		return aim_dirs()[(bits >> AIM_SHIFT) & (AIM_STEPS - 1)]
	return dir_from_bits(bits)


## Input side: the aim bits for a direction (the nearest of the 64), or 0 for none.
## Picks by dot product, so no trig is needed here either.
static func aim_bits(v: Vector2) -> int:
	if v.length_squared() < 1e-6:
		return 0
	var best := 0
	var best_dot := -INF
	var dirs := aim_dirs()
	for i in AIM_STEPS:
		var d := dirs[i].dot(v)
		if d > best_dot:
			best_dot = d
			best = i
	return IN_AIM | (best << AIM_SHIFT)


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
