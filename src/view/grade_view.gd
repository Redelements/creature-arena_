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

var _mat := ShaderMaterial.new()


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
	visible = true
