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
const IN_ALL := 4095

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
