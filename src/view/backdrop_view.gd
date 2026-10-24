class_name BackdropView
extends Node2D
## The world beyond the floor, in depth. A map's picture (ArenaView) holds the crowd's rows
## and everything below them; above that sit two pictures that move less than the camera
## (tools/gen_arenas.py, `split_backdrop`):
##
##   sky   assets/sprites/arena_<id>_sky.png   PARALLAX_SKY (0.6): sky, stars, the skyline
##   far   assets/sprites/arena_<id>_far.png   PARALLAX_FAR (0.85): the tiers under the
##         roof's edge, and the roof's edge
##
## A layer follows the camera by (1 - factor) of how far it has moved, so the floor and
## everything that matters stays at 1.0 and the world past it slides slower. Horizontally the
## reference is the arena's middle; vertically the reference is the camera at the top of its
## range (where the stands come into shot), so the layers sit as drawn there and slide down
## a little as the camera comes off the edge. Offsets are rounded to whole pixels, set from
## the camera every frame (no easing between positions). Furniture on those layers
## (FurnitureView) is a child of `sky` / `far`, so it moves with its layer.
## Cost: two textures, drawn once; moving them only changes a position.

const MARGIN := Vector2(400, 80)  ## where the main picture starts (ArenaView.MARGIN)
const PARALLAX_SKY := 0.6
const PARALLAX_FAR := 0.85
## In step with tools/gen_arenas.py: how far above the main picture the sky starts, and where
## the far picture starts (its first row, the roof's edge) in the main picture's rows.
const SKY_UP := 112.0
const FAR_TOP := 43.0
## The most the layers slide vertically (the camera's distance from the top of its range).
const MAX_DROP := 120.0

var sky: Node2D
var far: Node2D
var arena_size := Vector2(704, 366)
var _sky_tex: Texture2D = null
var _far_tex: Texture2D = null
var arena_id := ""
## The offsets the layers are at now (whole pixels), for tests and screenshots.
var sky_offset := Vector2.ZERO
var far_offset := Vector2.ZERO


class Layer extends Node2D:
	var tex: Texture2D = null

	func _draw() -> void:
		if tex != null:
			draw_texture(tex, Vector2.ZERO)


func _init() -> void:
	sky = Layer.new()
	far = Layer.new()
	add_child(sky)
	add_child(far)


## Loads a map's two pictures (none on a map without them: nothing is drawn).
func set_map(id: String, size: Vector2) -> void:
	arena_id = id
	arena_size = size
	_sky_tex = _load("res://assets/sprites/arena_%s_sky.png" % id)
	_far_tex = _load("res://assets/sprites/arena_%s_far.png" % id)
	(sky as Layer).tex = _sky_tex
	(far as Layer).tex = _far_tex
	sky.position = Vector2(-MARGIN.x, -MARGIN.y - SKY_UP)
	far.position = Vector2(-MARGIN.x, FAR_TOP - MARGIN.y)
	sky.queue_redraw()
	far.queue_redraw()
	_place(Vector2(size.x * 0.5, 0.0), 0.0)


## Where each layer sits at rest (world px): FurnitureView places a piece relative to it.
static func sky_rest() -> Vector2:
	return Vector2(-MARGIN.x, -MARGIN.y - SKY_UP)


static func far_rest() -> Vector2:
	return Vector2(-MARGIN.x, FAR_TOP - MARGIN.y)


static func _load(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


## How far a layer with parallax `factor` has slid, for a camera at `cam` whose view is
## `half` (world px) tall from its middle and which may look `show_top` above the arena.
## Whole pixels. Static so a test can pin it.
static func offset_for(factor: float, cam: Vector2, centre_x: float, half_y: float, show_top: float) -> Vector2:
	var drop := clampf(cam.y - (half_y - show_top), 0.0, MAX_DROP)
	var k := 1.0 - factor
	return Vector2(roundf((cam.x - centre_x) * k), roundf(drop * k))


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var vh := get_viewport().get_visible_rect().size.y
	_place(cam.position, vh * 0.5 / maxf(cam.zoom.y, 0.01))


func _place(cam_pos: Vector2, half_y: float) -> void:
	var base_sky := Vector2(-MARGIN.x, -MARGIN.y - SKY_UP)
	var base_far := Vector2(-MARGIN.x, FAR_TOP - MARGIN.y)
	sky_offset = offset_for(PARALLAX_SKY, cam_pos, arena_size.x * 0.5, half_y, CrowdView.SHOW_TOP)
	far_offset = offset_for(PARALLAX_FAR, cam_pos, arena_size.x * 0.5, half_y, CrowdView.SHOW_TOP)
	sky.position = base_sky + sky_offset
	far.position = base_far + far_offset
