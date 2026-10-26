class_name BloomView
extends Node
## Bloom (Settings > Video > Lighting: High only), hand-rolled: the Compatibility renderer
## has no 2D HDR glow. The bright things are drawn again, small and soft, into a SubViewport
## at half the window's size (`_emit`, through the world camera's transform), blurred along x
## into a second half-size viewport, then along y straight onto the screen layer with
## `blend_add` (`out`, which main puts on the screen layer under the letterbox and the HUD).
## Three cheap passes, whatever is on screen; nothing is read back.
##
## What blooms (all already gated for hidden foes): Glow's lights (LightView: a ready Surge,
## `fx.light`, `fx.projectile_light`, bright sparks), or Light2DView's moving lights when Glow is
## off, and the arena's lamps (`lights` entries with `"lamp": true`, Light2DView.lamps) at
## night. Kept faint (`STRENGTH`, `LIGHT_SHARE`): a halo over a fighter must never wash the
## sprite out (src/view/CLAUDE.md, Glow).

const SCALE := 0.5  ## the bloom's size against the window
const STRENGTH := 0.9  ## the composite's gain
const SPREAD := 2.0  ## texels between blur taps (at half size: 4 window px)
const LIGHT_SHARE := 0.35  ## a light's strength that blooms
const LIGHT_SIZE := 0.3  ## a light's bloom radius against its reach
const LIGHT_MAX_R := 18.0
const LAMP_R := 9.0  ## a lamp head's bloom radius
const LAMP_ALPHA := 0.85
const SHADER := preload("res://src/view/bloom.gdshader")

var glow: LightView  ## main's floor LightView (its `lights`, when Glow is on)
var light2d: Light2DView
var out := TextureRect.new()
var _vp_a := SubViewport.new()
var _vp_b := SubViewport.new()
var _emit := Emitters.new()
var _blur_h := TextureRect.new()
var _size := Vector2i.ZERO
var on := false


## The bright things, in world coordinates, drawn additively into the first viewport.
class Emitters extends Node2D:
	var bloom: BloomView

	func _init() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

	func _draw() -> void:
		bloom._draw_emitters(self)


func _ready() -> void:
	for vp in [_vp_a, _vp_b]:
		vp.world_2d = World2D.new()  # a canvas of its own: only the bloom's sources
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		add_child(vp)
	_emit.bloom = self
	_vp_a.add_child(_emit)
	_blur_h.texture = _vp_a.get_texture()
	_blur_h.material = _blur(Vector2(1, 0), 1.0)
	_vp_b.add_child(_blur_h)
	out.texture = _vp_b.get_texture()
	out.material = _blur(Vector2(0, 1), STRENGTH)
	out.set_anchors_preset(Control.PRESET_FULL_RECT)
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	out.stretch_mode = TextureRect.STRETCH_SCALE
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_on(on)


static func _blur(d: Vector2, gain: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("dir", d)
	m.set_shader_parameter("spread", SPREAD)
	m.set_shader_parameter("strength", gain)
	return m


func set_on(v: bool) -> void:
	on = v
	out.visible = v
	var mode := SubViewport.UPDATE_ALWAYS if v else SubViewport.UPDATE_DISABLED
	_vp_a.render_target_update_mode = mode
	_vp_b.render_target_update_mode = mode


## Every drawn frame (main's _process): follow the camera and the window size.
func frame(world: Viewport) -> void:
	if not on:
		return
	var win := world.get_visible_rect().size
	var px := Vector2(DisplayServer.window_get_size())
	if px.x < 2.0:
		px = win
	var want := Vector2i(maxi(2, int(px.x * SCALE)), maxi(2, int(px.y * SCALE)))
	if want != _size:
		_size = want
		_vp_a.size = want
		_vp_b.size = want
		_blur_h.size = Vector2(want)
	var k := float(_size.x) / maxf(1.0, win.x)
	_vp_a.canvas_transform = Transform2D(0.0, Vector2(k, k), 0.0, Vector2.ZERO) * world.canvas_transform


## Once a tick, after the lights are gathered.
func advance() -> void:
	if on:
		_emit.queue_redraw()


func _draw_emitters(ci: CanvasItem) -> void:
	var t0 := PerfLog.now()
	var tex := Light2DView.radial()
	var list: Array = []
	if glow != null and glow.visible:
		list = glow.lights
	elif light2d != null:
		list = light2d.dynamic
	for l in list:
		var col: Color = l[2]
		col.a = clampf(float(l[4]) * LIGHT_SHARE, 0.0, 1.0)
		var r := minf(float(l[3]) * LIGHT_SIZE, LIGHT_MAX_R)
		var at := Vector2(l[0]) - Vector2(0, float(l[1]))
		ci.draw_texture_rect(tex, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, col)
	if light2d != null:
		for lp in light2d.lamps:
			if not bool(lp["lamp"]):
				continue
			var col: Color = lp["fighter_color"]
			col.a = LAMP_ALPHA
			ci.draw_texture_rect(tex, Rect2(Vector2(lp["pos"]) - Vector2(LAMP_R, LAMP_R), Vector2(LAMP_R, LAMP_R) * 2.0),
				false, col)
	PerfLog.since("bloom draw", t0)
