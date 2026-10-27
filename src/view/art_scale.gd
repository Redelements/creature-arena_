class_name ArtScale
extends RefCounted
## Where the art density lives: how many art pixels one world unit is.
##
## The sim works in world units (SimDefs.CELL = 8 a terrain cell) and never changes.
## The screen grid is already two pixels a unit (project.godot: a 960 x 540 viewport at
## stretch scale 2, so the canvas is 480 x 270 units), and the older sheets draw one
## texture pixel per unit (two grid pixels each). New art is drawn at PX_PER_UNIT texture
## pixels a unit, at scale 1 / PX_PER_UNIT, so each of its pixels is one grid pixel: a
## 32 px Set 1 ground tile is 2 x 2 cells, a 16 px overlay tile is one cell.
##
## Each asset says its own density ("ppu", pixels per unit): a creature's sprite block
## (default 1, so every older sheet draws exactly as before), an effect in data/vfx.json,
## or an arena picture by its size (`picture_ppu`). Nothing crosses the wire or the data
## hash differently: this is a view convention only (docs/plans/32px-migration.md).

## Art pixels per world unit for art made for this scale.
const PX_PER_UNIT := 2
## One terrain cell in art pixels at that density.
const CELL_PX := SimDefs.CELL * PX_PER_UNIT
## A ground tile (Szadi art's RPG Worlds sets) in art pixels, and in cells.
const TILE_PX := 32
const TILE_CELLS := TILE_PX / CELL_PX
## The densities an asset may declare.
const ALLOWED := [1, PX_PER_UNIT]


## An asset block's density: its "ppu" (1 unless given), else `fallback`.
static func ppu_of(block: Dictionary, fallback := 1) -> int:
	var p := int(block.get("ppu", fallback))
	return p if p in ALLOWED else fallback


## A picture's density from its size against the world units it covers: 2x art is twice
## the size it would be at one pixel a unit (a pixel or two of slack for an odd margin).
static func picture_ppu(tex_size: Vector2, units: Vector2) -> int:
	if units.x <= 0.0 or units.y <= 0.0:
		return 1
	var twice := units * float(PX_PER_UNIT)
	if absf(tex_size.x - twice.x) <= 2.0 and absf(tex_size.y - twice.y) <= 2.0:
		return PX_PER_UNIT
	return 1


## The scale a sprite of density `ppu` is drawn at (world units per texture pixel).
static func scale_of(ppu: int) -> Vector2:
	return Vector2.ONE / float(maxi(1, ppu))


## A world position on the art's own pixel grid: whole units for 1x art, halves for 2x,
## so a sprite never lands between its own pixels.
static func snap(p: Vector2, ppu: int) -> Vector2:
	var k := float(maxi(1, ppu))
	return (p * k).round() / k


## The same for one coordinate.
static func snapf(v: float, ppu: int) -> float:
	var k := float(maxi(1, ppu))
	return roundf(v * k) / k
