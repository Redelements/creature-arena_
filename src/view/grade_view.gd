class_name GradeView
extends ColorRect
## A map's grade: a subtle colour tint and a vignette over the whole picture, under the
## HUD (the first child of main's screen layer). Data: the arena JSON `grade`
## {"tint": "#f4f6ff", "vignette": 0.2}; none = no grade, nothing drawn. View only.
##
## One full-screen multiply (grade.gdshader): the cost is a flat fill, no screen read.
## The time of day and weather already tint the picture (WeatherView), so main hands this
## their `grade_scale()` too: night takes less of the map's tint and vignette, and the
## two never stack into a double dark.

const SHADER := preload("res://src/view/grade.gdshader")
## How far (a share of the screen) the vignette's middle leans toward the side the map's
## light comes from (against its `light` cast direction, ShadowLayer.light_of).
const LIGHT_LEAN := 0.08

var _mat := ShaderMaterial.new()


## ShaderWarmup's list: the grade's material, compiled before the first fight.
static func warm_materials() -> Array:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	return [m]


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = SHADER
	material = _mat
	color = Color.WHITE
	visible = false


## Grade for `arena` (its `grade` block), eased by `scale` {tint, vignette} multipliers.
func apply(arena: Dictionary, scale: Dictionary = {}) -> void:
	var g: Dictionary = arena.get("grade", {})
	if g.is_empty():
		visible = false
		return
	var k_tint := float(scale.get("tint", 1.0))
	var k_vig := float(scale.get("vignette", 1.0))
	var t := Color(String(g.get("tint", "#ffffff")))
	var tint := Color.WHITE.lerp(t, clampf(k_tint, 0.0, 1.0))
	_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_mat.set_shader_parameter("vignette", clampf(float(g.get("vignette", 0.0)) * k_vig, 0.0, 0.6))
	_mat.set_shader_parameter("centre", centre_for(arena))
	visible = true


## The vignette's middle (UV) for `arena`: the screen's middle leaned LIGHT_LEAN toward the
## side its light comes from. Static so a test can pin it.
static func centre_for(arena: Dictionary) -> Vector2:
	var cast: Vector2 = ShadowLayer.light_of(arena)["cast"]
	if cast.length() < 0.001:
		return Vector2(0.5, 0.5)
	# sideways only: every map's light comes from the back, and leaning up would darken the
	# front of the screen against the floor's lighter near band (tools/gen_arenas.py depth_shift)
	return Vector2(0.5 - cast.normalized().x * LIGHT_LEAN, 0.5)
