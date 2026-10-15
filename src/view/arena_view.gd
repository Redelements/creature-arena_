class_name ArenaView
extends Node2D
## Draws the stadium: stands, walls, and the breakable floor from the terrain grid.
## Redraws only when the terrain changes.

const TILES := preload("res://assets/sprites/tiles.png")
const TILE_HOLE := 8
const TILE_HOLE_DEEP := 9
## Arena map pieces (tools/gen_sprites.py tiles_sheet).
const TILE_WALL_TOP := 10  # two variants
const TILE_WALL_FACE := 12
const TILE_FENCE := 13
const TILE_CHASM_RIM := 14
const TILE_CHASM := 15
const TILE_SHALLOWS := 16  # two variants
const TILE_BRUSH := 18  # two variants
const TILE_BRUSH_FLAT := 20
const TILE_RUBBLE_FLOOR := 21
## How each map's ground tints the dirt tiles (the map's "ground" key).
const GROUND_TINT := {
	"dirt": Color(1.0, 1.0, 1.0),
	"stone": Color(0.86, 0.86, 0.9),
	"concrete": Color(0.78, 0.82, 0.88),
	"grass": Color(0.84, 0.98, 0.72),
}
var ground := "dirt":
	set(v):
		if v != ground:
			ground = v
			_drawn_version = -1
			queue_redraw()

const C_BG := Color("1b1e26")
const C_STAND_A := Color("3a3f4e")
const C_STAND_B := Color("323645")
const C_RAIL := Color("23262f")
const C_WALL := Color("5d6470")
const C_WALL_TOP := Color("8a909a")
const C_WALL_DARK := Color("464c58")
const C_LINE := Color(1, 1, 1, 0.2)
## How far the stadium carries on past its walls, for when the camera pulls back and for
## wider (ultrawide) and taller (16:10) screens: they see more stands and wall.
const MARGIN := Vector2(400, 80)

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
	var x0 := -MARGIN.x
	var w := float(SimDefs.ARENA_W) + MARGIN.x * 2.0
	var y0 := -MARGIN.y
	var h := float(SimDefs.ARENA_H) + MARGIN.y * 2.0

	# Stands behind the crowd (rising out of sight above), then the back wall.
	draw_rect(Rect2(x0, y0, w, h), C_BG)
	for i in range(-6, 4):
		draw_rect(Rect2(x0, i * 14, w, 14), C_STAND_A if posmod(i, 2) == 0 else C_STAND_B)
	draw_rect(Rect2(x0, 47, w, 2), C_RAIL)
	draw_rect(Rect2(x0, fr.position.y - 8, w, 8), C_WALL)
	draw_rect(Rect2(x0, fr.position.y - 8, w, 1), C_WALL_TOP)
	draw_rect(Rect2(x0, fr.position.y - 1, w, 1), C_WALL_DARK)

	# Side and front walls.
	draw_rect(Rect2(x0, fr.position.y, fr.position.x - x0, fr.size.y), C_WALL_DARK)
	draw_rect(Rect2(fr.end.x, fr.position.y, x0 + w - fr.end.x, fr.size.y), C_WALL_DARK)
	draw_rect(Rect2(fr.position.x - 1, fr.position.y, 1, fr.size.y), C_WALL)
	draw_rect(Rect2(fr.end.x, fr.position.y, 1, fr.size.y), C_WALL)
	draw_rect(Rect2(x0, fr.end.y, w, y0 + h - fr.end.y), C_WALL)
	draw_rect(Rect2(x0, fr.end.y, w, 1), C_WALL_TOP)

	# Floor: intact and cracked cells first, then the map's pieces that sit on it.
	for cy in terrain.rows:
		for cx in terrain.cols:
			var v := terrain.cells[cy * terrain.cols + cx]
			if TerrainGrid.is_pit(v):
				continue
			var idx := (cx * 7 + cy * 13 + (cx * cy) % 5) % 4
			var b := terrain.base[cy * terrain.cols + cx]
			match v:
				TerrainGrid.CRACKED:
					idx = TILE_RUBBLE_FLOOR if b == TerrainGrid.WALL else 4 + (cx * 13 + cy * 7 + cx * cy) % 4
				TerrainGrid.WALL:
					# The bottom row of a wall shows its face; the rest its rubble top.
					var below := terrain.cells[(cy + 1) * terrain.cols + cx] if cy + 1 < terrain.rows else TerrainGrid.INTACT
					idx = TILE_WALL_FACE if below != TerrainGrid.WALL else TILE_WALL_TOP + (cx + cy) % 2
				TerrainGrid.SHALLOWS:
					idx = TILE_SHALLOWS + (cx * 3 + cy * 5) % 2
			var plain := v == TerrainGrid.INTACT or v == TerrainGrid.CRACKED or v == TerrainGrid.BRUSH \
				or v == TerrainGrid.BRUSH_FLAT or v == TerrainGrid.FENCE
			draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(idx * 8, 0, 8, 8),
				GROUND_TINT.get(ground, Color.WHITE) if plain else Color.WHITE)
			var over := -1
			match v:
				TerrainGrid.FENCE: over = TILE_FENCE
				TerrainGrid.BRUSH: over = TILE_BRUSH + (cx * 5 + cy * 3) % 2
				TerrainGrid.BRUSH_FLAT: over = TILE_BRUSH_FLAT
			if over >= 0:
				draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(over * 8, 0, 8, 8))

	# Court markings.
	var c := fr.get_center()
	draw_rect(fr.grow(-4), C_LINE, false, 1.0)
	draw_line(Vector2(c.x, fr.position.y + 4), Vector2(c.x, fr.end.y - 4), C_LINE, 1.0)
	draw_arc(c, 34.0, 0.0, TAU, 48, C_LINE, 1.0)

	# Holes and chasms last so they cut through the markings. A pit whose upper
	# neighbour is solid gets the lit rim tile, which reads as the pit's far wall.
	for cy in terrain.rows:
		for cx in terrain.cols:
			var v := terrain.cells[cy * terrain.cols + cx]
			if not TerrainGrid.is_pit(v):
				continue
			var above_solid := cy == 0 or not TerrainGrid.is_pit(terrain.cells[(cy - 1) * terrain.cols + cx])
			var chasm := v == TerrainGrid.CHASM
			var idx: int
			if above_solid:
				idx = TILE_CHASM_RIM if chasm else TILE_HOLE
			else:
				idx = TILE_CHASM if chasm else TILE_HOLE_DEEP
			draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(idx * 8, 0, 8, 8))


func _cell_rect(cx: int, cy: int) -> Rect2:
	return Rect2(SimDefs.GRID_X + cx * SimDefs.CELL, SimDefs.GRID_Y + cy * SimDefs.CELL, SimDefs.CELL, SimDefs.CELL)
