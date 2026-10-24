class_name ShadowLayer
extends Node2D
## The fighters' shadows, cast along the arena's light: each fighter's current sprite frame
## as a black silhouette laid on the floor from its feet, mirrored with its facing, and
## shrinking and fading as it goes up (`CreatureView.shadow_size`, `shadow_fade`). The light
## is the map's "light" key (data/arenas/<id>.json, `light_of`); tools/gen_arenas.py casts
## the pieces' shadows in the map art along the same light.
##
## Main adds this node between the floor effects and the fighters, so a shadow lies on the
## floor under everyone and never darkens another fighter. Each shadow is its own canvas
## item at its fighter's feet (`Caster`), repainted only when its look changes and hidden
## off screen; walking just moves it. A shadow is drawn a row at a
## time: each shadow row is one row of the sprite shifted a whole pixel along the light, so
## its edges stay crisp pixel steps (no sheared texels) and rows never overlap (no darker
## seams). FxView draws the Caravan's wagon's and the flags' shadows with `draw_silhouette`.

## When a map has no "light": stadium floodlights, high and a little to the left.
const DEFAULT_LIGHT := {"dir": [0.25, 1.0], "length": 0.38, "alpha": 0.32}
## The flattest a shadow may lie (floor rows per pixel of height), so a light along the
## screen's x axis doesn't squash a fighter's shadow into a line.
const MIN_FLAT := 0.2

## CreatureView per creature (main's `views`, shared).
var views: Array = []
## This match's light (`light_of`); setting it repaints every shadow.
var light: Dictionary = light_of({}):
	set(l):
		light = l
		for k in _casters:
			k.key = []

static var _lights := {}


## A map's light: {"cast": where a point one pixel up throws its shadow (the normalised
## "dir" times "length"), "alpha": how dark}. Cached by map id.
static func light_of(arena: Dictionary) -> Dictionary:
	var id := String(arena.get("id", ""))
	if id != "" and _lights.has(id):
		return _lights[id]
	var l: Dictionary = DEFAULT_LIGHT.duplicate()
	l.merge(arena.get("light", {}), true)
	var d := Vector2(float(l["dir"][0]), float(l["dir"][1]))
	d = d.normalized() if d.length() > 0.001 else Vector2.DOWN
	var cast := d * float(l["length"])
	if absf(cast.y) < MIN_FLAT:
		cast.y = -MIN_FLAT if cast.y < 0.0 else MIN_FLAT
	var out := {"cast": cast, "alpha": float(l["alpha"])}
	if id != "":
		_lights[id] = out
	return out


## Margin round the screen inside which a shadow is still drawn (a long one reaches in).
const CULL_PAD := 96.0

## One fighter's shadow: a canvas item standing at its feet, so walking only moves it and it
## repaints only when the frame, facing, squash or size changes (`CreatureView.shadow_key`).
class Caster extends Node2D:
	var view: CreatureView
	var layer: ShadowLayer
	var key: Array = []

	func _draw() -> void:
		var t0 := PerfLog.now()
		view.draw_shadow(self, layer.light["cast"], float(layer.light["alpha"]))
		PerfLog.since("shadows draw", t0)


var _casters: Array[Caster] = []


## Once a tick (the fighters' frames and places change on the tick): each caster follows its
## fighter, hides when the fighter is hidden or off screen, and repaints when its look changed.
func _physics_process(_delta: float) -> void:
	while _casters.size() < views.size():
		var k := Caster.new()
		k.layer = self
		add_child(k)
		_casters.append(k)
	var view := FxView._view_rect(self, CULL_PAD)
	for i in _casters.size():
		var k := _casters[i]
		var o = views[i] if i < views.size() else null
		var v: CreatureView = o if is_instance_valid(o) else null
		var on := v != null and v.visible and v.shadow_fade > 0.0 and view.has_point(v.position)
		k.visible = on
		if not on:
			continue
		if k.view != v:
			k.view = v
			k.key = []
		k.position = v.position.round()
		var key := v.shadow_key()
		if key != k.key:
			k.key = key
			k.queue_redraw()


## Draws `region` of `tex` as a shadow on the floor: black at `alpha`, its point `origin`
## (the feet, in the region) at `feet`, every pixel `h` above the feet moved `h * cast`
## along the floor. `size` scales it (x: width, y: height: squash, shrinking in the air);
## `flip` mirrors the sprite, not the light.
static func draw_silhouette(ci: CanvasItem, tex: Texture2D, region: Rect2, origin: Vector2, flip: bool,
		feet: Vector2, cast: Vector2, alpha: float, size := Vector2.ONE) -> void:
	if alpha <= 0.0 or tex == null:
		return
	var col := Color(0, 0, 0, alpha)
	var fy := cast.y * size.y
	var fx := cast.x * size.y
	if absf(fy) < 0.01:
		return
	var w := region.size.x * size.x
	var left := -origin.x * size.x
	# the rows the sprite's heights land on: from the bottom of the frame to its top
	var y_a := (origin.y - region.size.y) * fy
	var y_b := origin.y * fy
	var j0 := floori(minf(y_a, y_b))
	var j1 := ceili(maxf(y_a, y_b))
	ci.draw_set_transform(feet.round(), 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	for j in range(j0, j1):
		var h := (float(j) + 0.5) / fy  # the height this row of shadow comes from
		var r := floori(origin.y - h)
		if r < 0 or r >= int(region.size.y):
			continue
		var off := roundf(h * fx)
		ci.draw_texture_rect_region(tex, Rect2((-off if flip else off) + left, j, w, 1),
			Rect2(region.position.x, region.position.y + r, region.size.x, 1), col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
