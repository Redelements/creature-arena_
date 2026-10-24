class_name ForeView
extends Node2D
## The foreground: things between the camera and the fight, over the fighters, so the arena
## has a near layer as well as a far one (BackdropView). Two pictures from
## tools/gen_arenas.py (`fore_layers`):
##
##   front  assets/sprites/arena_<id>_fore.png  the nearest fans' heads and a rail (per map:
##          steel, rope, pipe, a keep's parapet, a greenhouse's planter leaves), its top
##          FORE_GAP px below the front wall's foot at rest (negative: the tallest heads
##          rise over the wall's face, never past its top)
##   hang   assets/sprites/arena_<id>_hang.png  what hangs from the roof at the back (a
##          lighting truss, bunting, vines), its top at world y HANG_TOP at rest
##
## Both slide a little faster than the floor (PARALLAX, more than 1): at rest when the camera
## is as far toward their edge as it goes (main._cam_axis: SHOW_FRONT past the front wall,
## SHOW_TOP above the arena), and pushed off the screen's edge by (PARALLAX - 1) of every
## pixel the camera is away from that, so they show only while the camera is near that edge
## (about 20 px of travel) and never over the middle of the floor. Horizontally they slide
## (PARALLAX - 1) of the camera's offset from the arena's middle. Offsets are whole pixels,
## set from the camera every frame (no easing); a strip well off screen isn't drawn.
## Cost: two textures, drawn once; moving them only changes a position.
## Main adds this after the entities (over the fighters), under the weather and FxView.

const MARGIN := Vector2(400, 80)  ## where the pictures start horizontally (ArenaView.MARGIN)
const PARALLAX := 1.25
## In step with tools/gen_arenas.py (FORE_GAP, FORE_H, HANG_TOP, HANG_H).
const FORE_GAP := -8.0
const FORE_H := 72.0
const HANG_TOP := -60.0
const HANG_H := 56.0
## Past this far off its rest spot a strip is surely off screen: not drawn.
const HIDE_PAST := 60.0

var front: Node2D
var hang: Node2D
var arena_size := Vector2(704, 366)
var arena_id := ""
## The offsets the strips are at now (whole pixels), for tests and screenshots.
var front_offset := Vector2.ZERO
var hang_offset := Vector2.ZERO


class Layer extends Node2D:
	var tex: Texture2D = null

	func _draw() -> void:
		if tex != null:
			draw_texture(tex, Vector2.ZERO)


func _init() -> void:
	front = Layer.new()
	hang = Layer.new()
	add_child(hang)
	add_child(front)


## Loads a map's two strips (none on a map without them: nothing is drawn).
func set_map(id: String, size: Vector2) -> void:
	arena_id = id
	arena_size = size
	(front as Layer).tex = _load("res://assets/sprites/arena_%s_fore.png" % id)
	(hang as Layer).tex = _load("res://assets/sprites/arena_%s_hang.png" % id)
	front.queue_redraw()
	hang.queue_redraw()
	_place(Vector2(size.x * 0.5, size.y * 0.5), Vector2(240.0, 135.0))


static func _load(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


## How far the front strip has slid off its rest spot, for a camera at `cam` whose view is
## `half` (world px) from its middle on an arena `size`: down (positive y) by (PARALLAX - 1)
## of the camera's distance from its front-most spot. Whole pixels; static so a test can pin it.
static func front_offset_for(cam: Vector2, half: Vector2, size: Vector2) -> Vector2:
	var rest := size.y + CrowdView.SHOW_FRONT - half.y
	var k := PARALLAX - 1.0
	return Vector2(roundf(-(cam.x - size.x * 0.5) * k), roundf(maxf(0.0, rest - cam.y) * k))


## ...and the hanging strip: up (negative y) by (PARALLAX - 1) of the camera's distance from
## its top-most spot.
static func hang_offset_for(cam: Vector2, half: Vector2, size: Vector2) -> Vector2:
	var rest := half.y - CrowdView.SHOW_TOP
	var k := PARALLAX - 1.0
	return Vector2(roundf(-(cam.x - size.x * 0.5) * k), roundf(-maxf(0.0, cam.y - rest) * k))


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var vs := get_viewport().get_visible_rect().size * 0.5
	_place(cam.position, Vector2(vs.x / maxf(cam.zoom.x, 0.01), vs.y / maxf(cam.zoom.y, 0.01)))


func _place(cam_pos: Vector2, half: Vector2) -> void:
	front_offset = front_offset_for(cam_pos, half, arena_size)
	hang_offset = hang_offset_for(cam_pos, half, arena_size)
	front.position = Vector2(-MARGIN.x, arena_size.y + FORE_GAP) + front_offset
	hang.position = Vector2(-MARGIN.x, HANG_TOP) + hang_offset
	front.visible = front_offset.y < HIDE_PAST
	hang.visible = -hang_offset.y < HIDE_PAST
