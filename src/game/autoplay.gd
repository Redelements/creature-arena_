class_name AutoPlay
extends RefCounted
## A scripted input sequence for the player, used for demo captures and smoke tests:
##   godot --path . -- --autoplay
## Each step is [ticks, input bits]. The sequence loops.

const R := SimDefs.IN_RIGHT
const LT := SimDefs.IN_LEFT
const UP := SimDefs.IN_UP
const DN := SimDefs.IN_DOWN
const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const D := SimDefs.IN_DODGE

const SCRIPT_STEPS := [
	[30, 0],
	[70, R],          # walk up to the dummy
	[1, L], [9, 0],   # three-hit light combo
	[1, L], [9, 0],
	[1, L], [50, 0],
	[40, R],          # close the distance again
	[55, H],          # hold heavy to full charge -> slam opens a hole under the dummy
	[90, 0],
	[1, D | UP], [25, 0],  # dodge roll
	[30, DN],
	[30, LT],
	[1, H], [60, 0],  # quick heavy: cracks only
]

var _schedule := PackedInt32Array()


func _init() -> void:
	for s in SCRIPT_STEPS:
		for i in int(s[0]):
			_schedule.append(int(s[1]))


func bits(tick: int) -> int:
	return _schedule[(tick - 1) % _schedule.size()] if tick > 0 else 0


func length() -> int:
	return _schedule.size()
