class_name ShaderWarmup
extends Node
## Shader warm-up: in the first frames after launch (the title, over its background match),
## every material a fight draws with is drawn once into a small SubViewport nobody sees, so
## the driver compiles its shaders and pipelines then, not in the middle of the first fight.
## On the Odin 3 the first fight after an install held one frame for ~41 ms while Vulkan
## compiled (docs/plans/android-touch-menus-perf.md); later launches reuse Vulkan's pipeline
## cache (`rendering/rendering_device/pipeline_cache/enable`, on), and on GL Compatibility
## (PC) Godot's own shader cache is off (project.godot: reloaded from it, 2D lights break),
## so the driver's own cache is all a launch has.
##
## Invisible by construction: the SubViewport has a World2D of its own, is never shown on
## screen and isn't a CanvasItem's child; a player's frames are the same with or without it.
## It draws PER_FRAME draws a frame (a cold pipeline compile can cost tens of ms), then frees
## its viewport. Measured on a PC (RTX 4090, Vulkan, pipelines never compiled before): about
## 20 ms a draw, the title's slowest frame ~70 ms, once; with the driver's cache warm, a few ms.
##
## The list isn't written by hand: it is every material `warm_materials()` of the SOURCES
## (each view that creates a material builds it there, from the same factory it draws with,
## so a change to one is a change to both), plus the default canvas material.
## tests/test_shader_warmup.gd fails when a script under src/ makes a material or loads a
## `.gdshader` without being a SOURCE, or a `.gdshader` in the project isn't in the list.
##
## Each material is drawn unlit and lit (a PointLight2D on WARM_MASK, a CanvasTexture with a
## normal map, as CreatureView draws a fighter), in each kind of draw the renderer keeps a
## pipeline for (`KINDS`: a rect, textured or not, is a quad; a polygon, coloured or
## textured, is vertex attributes; a thin line is a line primitive): one draw a cell. Off:
## `--no-warmup`, and headless (no renderer).

const SOURCES := [preload("res://src/view/creature_view.gd"), preload("res://src/view/bloom_view.gd"),
	preload("res://src/view/grade_view.gd"), preload("res://src/view/light2d_view.gd"),
	preload("res://src/view/light_view.gd"), preload("res://src/view/glade_view.gd"),
	preload("res://src/view/weather_view.gd"), preload("res://src/ui/fighter_preview.gd")]
const KINDS := ["quad", "polygon", "line"]
const PER_FRAME := 1  ## draws (cells) a frame: one compile at most
const WARM_MASK := 1 << 19  ## the warm-up light's mask, in its own World2D: no game light uses it
const CELL := 12
## The renderer reports a viewport's time a few frames late (its timestamps): after the last
## draw the warm-up keeps reading for LAG frames, adding each new reading once.
const LAG := 4

## Every material to warm, deduplicated by what compiles (a shader, or a CanvasItemMaterial's
## blend and light modes): [{key, material (null: the default), from}].
var entries: Array = []
## Every draw: [entry index, lit, kind index].
var draws: Array = []
var done := false
var drawn := 0
var ms := 0.0  ## the warm-up viewport's measured render CPU time, summed (the compiles)
var frames := 0
var slowest_ms := 0.0  ## the slowest whole frame while it ran (wall time: what a player could feel)
var _lag := 0
var _last_read := 0.0
var _last_us := 0
var _vp: SubViewport = null
var _cells: Array[Node] = []
var _tex: Texture2D = null
var _lit_tex: CanvasTexture = null
signal finished


static func collect() -> Array:
	var out: Array = [{"key": "default", "material": null, "from": "the default canvas material"}]
	var seen := {"default": true}
	for s in SOURCES:
		for m in (s as Script).call("warm_materials"):
			var k := key_of(m)
			if seen.has(k):
				continue
			seen[k] = true
			out.append({"key": k, "material": m, "from": (s as Script).resource_path.get_file()})
	return out


## What compiles: a ShaderMaterial's shader, or a CanvasItemMaterial's modes.
static func key_of(m: Material) -> String:
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		if sh == null:
			return "shader:none"
		return "shader:" + (sh.resource_path if sh.resource_path != "" else str(sh.get_instance_id()))
	if m is CanvasItemMaterial:
		var c := m as CanvasItemMaterial
		return "canvas_item:%d:%d" % [c.blend_mode, c.light_mode]
	return "other:" + m.get_class()


## Whether a launch warms up: not headless (tests, servers), not with --no-warmup.
static func wanted(args: PackedStringArray, display := DisplayServer.get_name()) -> bool:
	return display != "headless" and not ("--no-warmup" in args)


func _ready() -> void:
	entries = collect()
	for e in entries.size():
		for lit in [false, true]:
			for k in KINDS.size():
				draws.append([e, lit, k])
	_vp = SubViewport.new()
	_vp.world_2d = World2D.new()  # a canvas of its own: nothing here draws on screen
	_vp.disable_3d = true
	_vp.size = Vector2i(CELL * PER_FRAME, CELL)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_tex = ImageTexture.create_from_image(img)
	var nimg := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	nimg.fill(Color(0.5, 0.5, 1.0))  # a flat normal
	_lit_tex = CanvasTexture.new()
	_lit_tex.diffuse_texture = _tex
	_lit_tex.normal_texture = ImageTexture.create_from_image(nimg)
	var light := PointLight2D.new()  # as Light2DView's lights: additive, no shadows
	light.texture = Light2DView.radial()
	light.position = Vector2(_vp.size) * 0.5
	light.range_item_cull_mask = WARM_MASK
	light.range_z_min = -4096
	light.range_z_max = 4096
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.shadow_enabled = false
	light.height = 20.0
	_vp.add_child(light)


## One draw of one primitive kind (KINDS), with the cell's material.
class Cell extends Node2D:
	var tex: Texture2D
	var kind := 0

	func _draw() -> void:
		const S := 10.0
		match kind:
			0:
				draw_texture_rect(tex, Rect2(0, 0, S, S), false)
			1:
				draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(S, 0), Vector2(S, S)]),
					PackedColorArray([Color.WHITE]), PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]), tex)
			_:
				draw_line(Vector2(0, S * 0.5), Vector2(S, S * 0.5), Color.WHITE, 1.0)


func _process(_delta: float) -> void:
	step()


## One frame of the warm-up (the test calls it directly).
func step() -> void:
	if done:
		return
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		slowest_ms = maxf(slowest_ms, (now - _last_us) / 1000.0)
	_last_us = now
	var read := RenderingServer.viewport_get_measured_render_time_cpu(_vp.get_viewport_rid())
	if read != _last_read:
		ms += read
		_last_read = read
	for c in _cells:  # the draws of the frame before
		c.queue_free()
	_cells.clear()
	if drawn >= draws.size():
		_lag += 1
		if _lag > LAG:
			_finish()
		return
	for i in PER_FRAME:
		if drawn >= draws.size():
			break
		var d: Array = draws[drawn]
		var c := Cell.new()
		var lit := bool(d[1])
		c.material = entries[int(d[0])]["material"]
		c.kind = int(d[2])
		c.tex = _lit_tex if lit else _tex
		c.light_mask = WARM_MASK if lit else 1
		c.position = Vector2(i * CELL, 0)
		_vp.add_child(c)
		_cells.append(c)
		drawn += 1
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	frames += 1


func _finish() -> void:
	done = true
	if PerfLog.current != null:
		print("warmup: " + summary())
	_vp.queue_free()
	_vp = null
	set_process(false)
	finished.emit()


## For --perf's setup line: "7 materials, 42 draws in 12.3 ms (42 frames, the slowest 16.9 ms)",

## or how far it got. The ms are the renderer's own CPU time for the warm-up's viewport (the
## compiles); the slowest frame is wall time, the title's whole frame.
func summary() -> String:
	if done:
		return "%d materials, %d draws in %.1f ms (%d frames, the slowest %.1f ms)" % [entries.size(), drawn, ms, frames, slowest_ms]
	return "running (%d of %d draws)" % [drawn, draws.size()]
