class_name BloomView
extends Node
## Bloom (Settings > Video > Lighting: High only), hand-rolled: the Compatibility renderer
## has no 2D HDR glow. The bright things are drawn again, small and soft, into a SubViewport
## at half the window's size (`_emit`, through the world camera's transform), blurred along x
## into a second half-size viewport, then along y straight onto the screen layer with
## `blend_add` (`out`, which main puts on the screen layer under the letterbox and the HUD).
## Three cheap passes, whatever is on screen; nothing is read back.
##
## What blooms (all already gated for hidden foes): every light Light2DView gathered
## (`gathered`: a ready Surge's aura, `fx.light`, `fx.projectile_light`, sparks and bursts, the
## flashes of big hits and Surges), whatever the Glow setting (Glow's own `lights` only when
## there is no Light2DView), the arena's lamps (`lights` entries with `"lamp": true`,
## Light2DView.lamps) at night, the fighters' emissive sheets (`CreatureView.emit_frame`: the
## frame showing, for fighters `fx.shown` passes and not in stealth), and the water's brightest
## highlights (`WaterView.glints`) where a lamp shines on them at night, faintly by day.
## Kept faint (`STRENGTH`, `LIGHT_SHARE`, `EMIT_ALPHA`): a halo over a fighter must never wash
## the sprite out (src/view/CLAUDE.md, Glow). In High the bloom stands in for Glow's halos
## (main hides them), so nothing glows twice.

const SCALE := 0.5  ## the bloom's size against the window
const STRENGTH := 0.9  ## the composite's gain
const SPREAD := 2.0  ## texels between blur taps (at half size: 4 window px)
const LIGHT_SHARE := 0.35  ## a light's strength that blooms
## and more for a small bright thing (its `halo` share: a knife, a spark; 0.12 for an aura over
## a fighter): in High the bloom draws what Glow's halos drew
const HALO_SHARE := 0.6
const LIGHT_SIZE := 0.3  ## a light's bloom radius against its reach
const LIGHT_MAX_R := 18.0
const LAMP_R := 9.0  ## a lamp head's bloom radius
const LAMP_ALPHA := 0.85
const EMIT_ALPHA := 0.8  ## an emissive pixel's share that blooms
const GLINT_DAY := 0.18  ## a water highlight's bloom by day
const GLINT_LAMP := 0.7  ## and at night, at the middle of a lamp's pool (none outside one)
const SHADER := preload("res://src/view/bloom.gdshader")

var glow: LightView  ## main's floor LightView (its `lights`, when there's no Light2DView)
var light2d: Light2DView
var fx: FxView  ## for `shown` (hidden foes' emissive parts don't bloom)
var views: Array = []  ## main's CreatureViews (their emissive sheets)
var water: WaterView
var _glint_ver := -1
var _glint_w := PackedFloat32Array()  ## each glint's bloom, worked out when the surface redraws
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
		material = make_material()

	static func make_material() -> CanvasItemMaterial:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		return m

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


## ShaderWarmup's list: the emitters' additive layer and the blur, compiled before the first
## fight (Lighting High only shows them, but a player can turn it on mid-session).
static func warm_materials() -> Array:
	return [Emitters.make_material(), _blur(Vector2(1, 0), 1.0)]


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
	if light2d != null:
		list = light2d.gathered
	elif glow != null and glow.visible:
		list = glow.lights
	for l in list:
		var col: Color = l[2]
		var halo_share := float(l[5]) if l.size() > 5 else 0.0
		col.a = clampf(float(l[4]) * (LIGHT_SHARE + HALO_SHARE * halo_share), 0.0, 1.0)
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
	_draw_emissive(ci)
	_draw_glints(ci)
	PerfLog.since("bloom draw", t0)


## The fighters' emissive frames, where they stand (a hidden or stealthed fighter's don't).
func _draw_emissive(ci: CanvasItem) -> void:
	for o in views:
		if not is_instance_valid(o):
			continue
		var v: CreatureView = o
		if v.c == null or not v.is_visible_in_tree() or v.c.stealth > 0:
			continue
		if fx != null and fx.sim != null and not fx.shown(v.c):
			continue
		var e := v.emit_frame()
		if e.is_empty():
			continue
		ci.draw_set_transform_matrix(e["xform"])
		ci.draw_texture_rect_region(e["tex"], Rect2(Vector2.ZERO, e["size"]), e["region"],
			Color(1, 1, 1, EMIT_ALPHA * v.modulate.a))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## The water's brightest highlights: under the night's lamps (worked out once per surface
## redraw, `_glint_weights`), faintly by day.
func _draw_glints(ci: CanvasItem) -> void:
	if water == null or not water.is_visible_in_tree() or water.glints.is_empty():
		return
	if water.glint_ver != _glint_ver:
		_glint_ver = water.glint_ver
		_glint_w = _glint_weights()
	var view := FxView._view_rect(water, 8.0)
	var col := WaterView.WATER[6]
	for i in water.glints.size():
		var a := _glint_w[i]
		var g := water.glints[i]
		if a < 0.02 or not view.has_point(g):
			continue
		col.a = a
		ci.draw_rect(Rect2(g - Vector2(1.5, 0.5), Vector2(3, 1)), col)


func _glint_weights() -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(water.glints.size())
	var night := light2d != null and light2d.night
	for i in water.glints.size():
		if not night:
			w[i] = GLINT_DAY
			continue
		var best := 0.0
		for lp in light2d.lamps:
			var d := Vector2(lp["pos"]).distance_to(water.glints[i]) / maxf(1.0, float(lp["radius"]))
			if d < 1.0:
				best = maxf(best, 1.0 - d)
		w[i] = GLINT_LAMP * best
	return w
