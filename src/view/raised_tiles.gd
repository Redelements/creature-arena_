class_name RaisedTiles
extends RefCounted
## A tiled map's walls drawn as raised plateaus (map style `tiles.styles.wall: "raised:<name>"`,
## recipe `raised.<name>` in tools/cut_tiles.py): two 16 px TileMapLayers of the ground scene,
## one tile a terrain cell, picked per cell from which of its neighbours are raised.
##
## Everything stays on the cells the sim blocks: a column of raised cells shows the plateau's
## top, and its last `k` cells (k = the recipe's "cells", fewer for a shorter column) its cliff
## face hanging down to the floor, so a fighter north of a wall never stands under its
## picture and one south of it stands in front of the face. "Raised" holds the top and face
## tiles, "RaisedShadow" (under it) a contact shadow on the floor cells beside the wall, along
## the map's light (on the side away from it, and under the face).
##
## A raised cell is a map wall cell that is still whole (`up`): tools/build_tiles.gd paints the
## layers with every wall whole, ArenaView repaints the rows round a cell that was smashed or
## rebuilt with the same rules, so the rest of the wall gets a rim and a new face round the gap
## and the floor its shadow back. The smashed cell itself shows the floor (its crack overlay)
## and the scene's "Rubble" sprite.
##
## The layers' meta "raised" (written by build_tiles): {"source": the TileSet source,
## "tiles": the manifest's key -> atlas coords, "cells": the tallest face in cells, "variants":
## how many top blocks the cut has, "mirror": true when the light falls to -x}.


## Repaints raised and shadow tiles on rows row0..row1-1. `walls`: the map's wall cells
## (Vector2i -> true); `up`: whether a cell is raised now (a wall cell still whole).
static func paint(raised: TileMapLayer, shadow: TileMapLayer, info: Dictionary, walls: Dictionary, up: Callable, row0: int, row1: int) -> void:
	var tiles: Dictionary = info["tiles"]
	var src := int(info["source"])
	var k_max := int(info["cells"])
	var variants := maxi(1, int(info.get("variants", 1)))
	var mirror := bool(info.get("mirror", false))
	var side := Vector2i(1, 0) if not mirror else Vector2i(-1, 0)  # where a wall's shadow falls
	var floor_cells := {}
	for c: Vector2i in walls:
		if c.y < row0 - 1 or c.y >= row1:
			continue
		for d in [side, side * 2, Vector2i(0, 1), side + Vector2i(0, 1)]:
			floor_cells[c + d] = true
		if c.y < row0:
			continue
		if not up.call(c):
			raised.erase_cell(c)
			continue
		var key := top_or_face_key(c, up, k_max, variants)
		if tiles.has(key):
			raised.set_cell(c, src, _v(tiles[key]))
		else:
			raised.erase_cell(c)
	for c: Vector2i in floor_cells:
		if c.y < row0 or c.y >= row1:
			continue
		var key := "" if up.call(c) else shadow_key(c, up, mirror)
		if key != "" and tiles.has(key):
			shadow.set_cell(c, src, _v(tiles[key]))
		else:
			shadow.erase_cell(c)


## The manifest key of a raised cell's tile: a face row when the cell is among the last k of
## its column ("f<l><r><k><row><px>"), else the top ("t<l><r><u><v><q>": v a
## variant by hash per 2 x 2 cells, q the cell's quarter of it); l, r, u 1 where
## that neighbour is not raised (a face's sides: not a face cell of the same height).
static func top_or_face_key(c: Vector2i, up: Callable, k_max: int, variants: int) -> String:
	var fr := _face_row(c, up, k_max)
	if fr.x > 0:
		var l := 0 if _face_row(c + Vector2i.LEFT, up, k_max) == fr else 1
		var r := 0 if _face_row(c + Vector2i.RIGHT, up, k_max) == fr else 1
		return "f%d%d%d%d%d" % [l, r, fr.x, fr.y, posmod(c.x, 2)]
	var lt := 0 if up.call(c + Vector2i.LEFT) else 1
	var rt := 0 if up.call(c + Vector2i.RIGHT) else 1
	var ut := 0 if up.call(c + Vector2i.UP) else 1
	# one of the plateau's floor blocks (or its mirror) per 2 x 2 cells, by a fixed hash, and
	# the cell's quarter of it, so a long run is one varied ridge, not a block repeated
	var bx := floori(c.x / 2.0)
	var by := floori(c.y / 2.0)
	var v := posmod((bx * 73856093) ^ (by * 19349663), 1021) % variants
	return "t%d%d%d%d%d" % [lt, rt, ut, v, posmod(c.x, 2) + 2 * posmod(c.y, 2)]


## (k, row) when cell `c` is raised and in its column's face (k cells tall: the most the
## recipe allows, one less than the column so a top shows, at least 1), else (0, 0).
static func _face_row(c: Vector2i, up: Callable, k_max: int) -> Vector2i:
	if not up.call(c):
		return Vector2i.ZERO
	var below := 0
	while below <= k_max and up.call(c + Vector2i(0, below + 1)):
		below += 1
	if below >= k_max:
		return Vector2i.ZERO
	var above := 0
	while above <= k_max and up.call(c - Vector2i(0, above + 1)):
		above += 1
	var k := mini(k_max, maxi(1, above + below))  # the column's cells less one
	if below >= k:
		return Vector2i.ZERO
	return Vector2i(k, k - 1 - below)


## A floor cell's contact shadow key ("s<side><up><diag><m>"), "" for none: the wall on its
## side away from the light, above it (under the face), or only on that diagonal; "w<m>" a
## second cell out from the wall (a set whose shadow is wider than a cell has the tile).
static func shadow_key(c: Vector2i, up: Callable, mirror: bool) -> String:
	var dx := -1 if not mirror else 1
	var s := 1 if up.call(c + Vector2i(dx, 0)) else 0
	var u := 1 if up.call(c + Vector2i(0, -1)) else 0
	var d := 1 if up.call(c + Vector2i(dx, -1)) else 0
	if s == 0 and u == 0 and d == 0:
		# the rest of a side shadow wider than a cell (a tall wall in a low sun)
		return "w%d" % (1 if mirror else 0) if up.call(c + Vector2i(dx * 2, 0)) else ""
	return "s%d%d%d%d" % [s, u, d, 1 if mirror else 0]


static func _v(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
