class_name DetailCard
extends Control
## What a menu row shows under its text in the panel on the right (UiScreen `detail`):
## a fighter's idle preview with its name, title and class; a picture (the arena); and
## a few short lines of facts. Its height comes from what it holds, and the panel keeps
## the tallest card's height for every row, so nothing moves as the focus does.

signal changed

const PREVIEW_H := 44.0
const PICTURE_H := 56.0
const LINE_H := 9.0
const FONT_FACT := UiTheme.SIZE_HINT + 1

var fighter := "":
	set(v):
		if fighter == v:
			return
		fighter = v
		_preview.fighter = v
		_preview.visible = v != ""
		_def = MatchFactory.load_def(v) if v != "" else {}
		_relayout()
var picture: Texture2D = null:
	set(v):
		picture = v
		_relayout()
var facts: Array = []:
	set(v):
		facts = v
		_relayout()

var _preview: FighterPreview
var _def := {}


func _init(width := 150.0) -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(width, 0)
	_preview = FighterPreview.new()
	_preview.position = Vector2(0, 0)
	_preview.size = Vector2(52, PREVIEW_H)
	_preview.zoom = 0.8
	_preview.visible = false
	_preview.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_preview)


## How tall the card's contents are.
func height() -> float:
	var h := 0.0
	if fighter != "":
		h += PREVIEW_H + 2
	if picture != null:
		h += PICTURE_H + 2
	if not facts.is_empty():
		h += facts.size() * LINE_H + 2
	return h


func _relayout() -> void:
	var top := 0.0
	if picture != null:
		top += PICTURE_H + 2
	_preview.position = Vector2(0, top)
	custom_minimum_size = Vector2(custom_minimum_size.x, height())
	queue_redraw()
	changed.emit()


func _draw() -> void:
	var font := get_theme_font("font")
	var w := size.x
	var y := 0.0
	if picture != null:
		var ps := picture.get_size()
		var k := minf(w / ps.x, PICTURE_H / ps.y)
		var r := Rect2(Vector2((w - ps.x * k) * 0.5, y), ps * k)
		draw_rect(r.grow(1), Color(0, 0, 0, 0.5))
		draw_texture_rect(picture, r, false)
		y += PICTURE_H + 2
	if fighter != "":
		var x := 56.0
		var name := String(_def.get("name", fighter))
		_text(font, Vector2(x, y + 11), name, UiTheme.SIZE_ROW, UiTheme.C_TEXT, w - x)
		var title := String(_def.get("title", ""))
		if title != "":
			_text(font, Vector2(x, y + 22), title, UiTheme.SIZE_HINT, UiTheme.C_DIM, w - x)
		var bits := PackedStringArray()
		for k in ["role", "affinity"]:
			var v = _def.get(k)
			if v != null and String(v) != "" and String(v) != "none":
				bits.append(String(v).capitalize())
		_text(font, Vector2(x, y + 33), "  ·  ".join(bits), UiTheme.SIZE_HINT, UiTheme.C_ACCENT, w - x)
		y += PREVIEW_H + 2
	if not facts.is_empty():
		for f in facts:
			draw_circle(Vector2(2.5, y + 5.5), 1.2, UiTheme.C_ACCENT)
			_text(font, Vector2(8, y + 8), String(f), FONT_FACT, UiTheme.C_DIM, w - 8)
			y += LINE_H


func _text(font: Font, at: Vector2, s: String, fs: int, col: Color, width: float) -> void:
	var size_px := UiTheme.px(fs)
	draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, UiTheme.outline(size_px), Color(0, 0, 0, 0.8))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, col)
