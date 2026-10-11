class_name FxGround
extends Node2D
## The floor-level half of the effects: puddles, afterimages, crack decals, rock spires,
## the back half of orbiting pebbles, and the dimmer used by Surges. It sits between the
## arena and the fighters, so everything here is drawn underneath them. FxView owns the
## state and does the drawing through `painter`.

var painter: Callable


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
