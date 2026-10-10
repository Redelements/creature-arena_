class_name ArenaView
extends Node2D
## Draws the stadium: stands, walls, and the breakable floor from the terrain grid.
## Redraws only when the terrain changes.

const TILES := preload("res://assets/sprites/tiles.png")
const TILE_HOLE := 8
const TILE_HOLE_DEEP := 9

const C_BG := Color("1b1e26")
const C_STAND_A := Color("3a3f4e")
const C_STAND_B := Color("323645")
const C_RAIL := Color("23262f")
const C_WALL := Color("5d6470")
const C_WALL_TOP := Color("8a909a")
const C_WALL_DARK := Color("464c58")
const C_LINE := Color(1, 1, 1, 0.2)

var terrain: TerrainGrid
var _drawn_version := -1


func set_terrain(t: TerrainGrid) -> void:
	terrain = t
	_drawn_version = -1
	queue_redraw()


func refresh() -> void:
	if terrain != null and terrain.version != _drawn_version:
		queue_redraw()


func _draw() -> void:
	if terrain == null:
		return
	_drawn_version = terrain.version
	var fr := SimDefs.floor_rect()
	var w := float(SimDefs.VIEW_W)
	var h := float(SimDefs.VIEW_H)

	# Stands behind the crowd, then the back wall.
	draw_rect(Rect2(0, 0, w, h), C_BG)
	for i in 4:
		draw_rect(Rect2(0, i * 14, w, 14), C_STAND_A if i % 2 == 0 else C_STAND_B)
	draw_rect(Rect2(0, 47, w, 2), C_RAIL)
	draw_rect(Rect2(0, fr.position.y - 8, w, 8), C_WALL)
	draw_rect(Rect2(0, fr.position.y - 8, w, 1), C_WALL_TOP)
	draw_rect(Rect2(0, fr.position.y - 1, w, 1), C_WALL_DARK)

	# Side and front walls.
	draw_rect(Rect2(0, fr.position.y, fr.position.x, fr.size.y), C_WALL_DARK)
	draw_rect(Rect2(fr.end.x, fr.position.y, w - fr.end.x, fr.size.y), C_WALL_DARK)
	draw_rect(Rect2(fr.position.x - 1, fr.position.y, 1, fr.size.y), C_WALL)
	draw_rect(Rect2(fr.end.x, fr.position.y, 1, fr.size.y), C_WALL)
	draw_rect(Rect2(0, fr.end.y, w, h - fr.end.y), C_WALL)
	draw_rect(Rect2(0, fr.end.y, w, 1), C_WALL_TOP)

	# Floor: intact and cracked cells first.
	for cy in terrain.rows:
		for cx in terrain.cols:
			var v := terrain.cells[cy * terrain.cols + cx]
			if v == TerrainGrid.HOLE:
				continue
			var idx := (cx * 7 + cy * 13 + (cx * cy) % 5) % 4
			if v == TerrainGrid.CRACKED:
				idx = 4 + (cx * 13 + cy * 7 + cx * cy) % 4
			draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(idx * 8, 0, 8, 8))

	# Court markings.
	var c := fr.get_center()
	draw_rect(fr.grow(-4), C_LINE, false, 1.0)
	draw_line(Vector2(c.x, fr.position.y + 4), Vector2(c.x, fr.end.y - 4), C_LINE, 1.0)
	draw_arc(c, 34.0, 0.0, TAU, 48, C_LINE, 1.0)

	# Holes last so they cut through the markings. A hole whose upper neighbour is solid
	# gets the lit rim tile, which reads as the pit's far wall.
	for cy in terrain.rows:
		for cx in terrain.cols:
			if terrain.cells[cy * terrain.cols + cx] != TerrainGrid.HOLE:
				continue
			var above_solid := cy == 0 or terrain.cells[(cy - 1) * terrain.cols + cx] != TerrainGrid.HOLE
			if above_solid:
				draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(TILE_HOLE * 8, 0, 8, 8))
			else:
				draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(TILE_HOLE_DEEP * 8, 0, 8, 8))


func _cell_rect(cx: int, cy: int) -> Rect2:
	return Rect2(SimDefs.GRID_X + cx * SimDefs.CELL, SimDefs.GRID_Y + cy * SimDefs.CELL, SimDefs.CELL, SimDefs.CELL)
