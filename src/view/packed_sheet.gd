class_name PackedSheet
extends Texture2D
## A fighter sheet stored packed (tools/pack_sheets.py), drawn as if it were the grid sheet.
##
## A grid sheet is mostly empty canvas (a 2x Crease frame is a 192 px square his drawing covers
## 6% of), and the GPU holds every empty pixel. `tools/pack_sheets.py` writes each sheet's frames
## cut to their used rect and packed tight into `assets/sprites/packed/<sheet>.png` (and its
## `_n` / `_e` sheets the same way), plus `<sheet>.json` with each frame's rect. This texture
## stands in for the grid sheet: it reports the grid's size, and drawing any region of it
## (`_draw_rect_region`: a Sprite2D's frame, a band of rows for a death animation, one row of a
## shadow) draws the packed pixels of the frames that region covers at their grid places, so
## every reader keeps grid coordinates (frame size, origin, `hframes`) and nothing on screen
## changes. Pixels are copied, never resampled: the colour is exact, and the rim flash
## (flash.gdshader's TEXTURE_PIXEL_SIZE) has 1 px of clear border round each frame.
##
## `draw_tex` is what is drawn: the packed colour sheet, a CanvasTexture of it with the packed
## normal sheet (the lights), or the packed emissive sheet; all three share one layout.
## `load_sheet` opens a sheet by its grid path (the packed one when it exists, else the grid
## PNG itself: fixtures, tiles); `piece` gives one frame's packed texture, rect and origin for
## code that draws many slices of a frame (ShadowLayer).

const RECT_SIZE := 6  ## [packed x, packed y, x in the frame, y in the frame, w, h]

var draw_tex: Texture2D
var source := ""  ## the grid sheet's path (`path_of`)
var grid := Vector2i.ONE  ## the grid sheet's size
var frame := Vector2i.ONE  ## its frame size
var cols := 1  ## its frames across
var rects := PackedInt32Array()  ## RECT_SIZE ints per grid frame (row-major); w 0: empty

static var _layouts := {}  ## packed json path -> parsed layout ({} when none)


## The packed copy of a grid sheet's path: `<dir>/packed/<file>`.
static func packed_path(path: String) -> String:
	return path.get_base_dir().path_join("packed").path_join(path.get_file())


## The packed layout of the grid sheet at `path`, or {} when it has none.
static func layout_of(path: String) -> Dictionary:
	var jpath := packed_path(path).get_basename() + ".json"
	if _layouts.has(jpath):
		return _layouts[jpath]
	var lay := {}
	if path.begins_with("res://") and FileAccess.file_exists(jpath):
		var d = JSON.parse_string(FileAccess.get_file_as_string(jpath))
		if d is Dictionary and d.has("rects"):
			lay = d
	_layouts[jpath] = lay
	return lay


## The sheet at grid path `path` as the game draws it: a PackedSheet over its packed copy, or
## the grid texture itself when it has none (null when neither exists).
static func load_sheet(path: String) -> Texture2D:
	var lay := layout_of(path)
	if not lay.is_empty():
		var pp := packed_path(path)
		if ResourceLoader.exists(pp):
			var s := make(lay, load(pp))
			s.source = path
			return s
	return load(path) if ResourceLoader.exists(path) else null


## A PackedSheet with `lay`'s layout drawing `tex`.
static func make(lay: Dictionary, tex: Texture2D) -> PackedSheet:
	var s := PackedSheet.new()
	s.draw_tex = tex
	s.grid = Vector2i(int(lay["width"]), int(lay["height"]))
	var fr: Array = lay["frame"]
	s.frame = Vector2i(int(fr[0]), int(fr[1]))
	s.cols = int(lay["cols"])
	var flat := PackedInt32Array()
	for r in lay["rects"]:
		var a: Array = r
		if a.size() == RECT_SIZE:
			for v in a:
				flat.append(int(v))
		else:
			for i in RECT_SIZE:
				flat.append(0)
	s.rects = flat
	return s


## The same layout drawing another texture (the colour sheet's normals or emissive sheet).
func with_texture(tex: Texture2D) -> PackedSheet:
	var s := PackedSheet.new()
	s.draw_tex = tex
	s.source = source
	s.grid = grid
	s.frame = frame
	s.cols = cols
	s.rects = rects
	return s


## The grid sheet a texture shows: a PackedSheet's grid path, else the texture's own path.
static func path_of(tex: Texture2D) -> String:
	if tex is PackedSheet:
		return (tex as PackedSheet).source
	return tex.resource_path if tex != null else ""


## The texture the GPU holds for this sheet (the colour sheet under a CanvasTexture).
func held() -> Texture2D:
	if draw_tex is CanvasTexture:
		return (draw_tex as CanvasTexture).diffuse_texture
	return draw_tex


func _get_width() -> int:
	return grid.x


func _get_height() -> int:
	return grid.y


func _has_alpha() -> bool:
	return true


func _is_pixel_opaque(x: int, y: int) -> bool:
	var i := (y / frame.y) * cols + x / frame.x
	if x < 0 or y < 0 or x >= grid.x or y >= grid.y or (i + 1) * RECT_SIZE > rects.size():
		return false
	var b := i * RECT_SIZE
	var lx := x % frame.x - rects[b + 2]
	var ly := y % frame.y - rects[b + 3]
	return lx >= 0 and ly >= 0 and lx < rects[b + 4] and ly < rects[b + 5]


func _draw(ci: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
	_draw_rect_region(ci, Rect2(pos, Vector2(grid)), Rect2(Vector2.ZERO, Vector2(grid)), modulate, transpose, false)


func _draw_rect(ci: RID, rect: Rect2, _tile: bool, modulate: Color, transpose: bool) -> void:
	_draw_rect_region(ci, rect, Rect2(Vector2.ZERO, Vector2(grid)), modulate, transpose, false)


func _draw_rect_region(ci: RID, rect: Rect2, src: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
	if draw_tex == null:
		return
	var rid := draw_tex.get_rid()
	for p in pieces(rect, src):
		RenderingServer.canvas_item_add_texture_rect_region(ci, p[0], rid, p[1], modulate, transpose, clip_uv)


## What drawing grid region `src` into `rect` draws: [[dest rect, packed source rect], ...],
## one per frame it covers that has pixels there. A negative `rect` size mirrors (as the
## RenderingServer reads it: the rect spans |size| from its position, the picture flipped),
## so each piece keeps its mirrored place.
func pieces(rect: Rect2, src: Rect2) -> Array:
	var out := []
	if src.size.x <= 0.0 or src.size.y <= 0.0:
		return out
	var flip_x := rect.size.x < 0.0
	var flip_y := rect.size.y < 0.0
	var k := Vector2(absf(rect.size.x) / src.size.x, absf(rect.size.y) / src.size.y)
	var c0 := maxi(0, floori(src.position.x / frame.x))
	var c1 := mini(cols - 1, ceili(src.end.x / frame.x) - 1)
	var r0 := maxi(0, floori(src.position.y / frame.y))
	var r1 := mini(grid.y / frame.y - 1, ceili(src.end.y / frame.y) - 1)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var b := (r * cols + c) * RECT_SIZE
			if b + RECT_SIZE > rects.size() or rects[b + 4] <= 0:
				continue
			var at := Rect2(c * frame.x + rects[b + 2], r * frame.y + rects[b + 3], rects[b + 4], rects[b + 5])
			var cut := at.intersection(src)
			if cut.size.x <= 0.0 or cut.size.y <= 0.0:
				continue
			var from := Rect2(rects[b] + cut.position.x - at.position.x, rects[b + 1] + cut.position.y - at.position.y,
				cut.size.x, cut.size.y)
			var ax := cut.position.x - src.position.x
			var ay := cut.position.y - src.position.y
			var dx := rect.position.x + (src.size.x - ax - cut.size.x if flip_x else ax) * k.x
			var dy := rect.position.y + (src.size.y - ay - cut.size.y if flip_y else ay) * k.y
			var dw := cut.size.x * k.x * (-1.0 if flip_x else 1.0)
			var dh := cut.size.y * k.y * (-1.0 if flip_y else 1.0)
			out.append([Rect2(dx, dy, dw, dh), from])
	return out


## One frame of `tex` as its own picture: {tex, region, origin}, where `region` is one grid
## frame and `origin` a point in it. A PackedSheet gives its packed texture, the frame's
## packed rect and the origin moved into that rect (empty region: a blank frame); any other
## texture comes back as it is. ShadowLayer draws a frame a row at a time from this.
static func piece(tex: Texture2D, region: Rect2, origin: Vector2) -> Dictionary:
	if not tex is PackedSheet:
		return {"tex": tex, "region": region, "origin": origin}
	var s := tex as PackedSheet
	var c := int(region.position.x) / s.frame.x
	var r := int(region.position.y) / s.frame.y
	var b := (r * s.cols + c) * RECT_SIZE
	if region.size != Vector2(s.frame) or b + RECT_SIZE > s.rects.size() or s.rects[b + 4] <= 0:
		return {"tex": s.held(), "region": Rect2(), "origin": origin}
	return {"tex": s.held(), "region": Rect2(s.rects[b], s.rects[b + 1], s.rects[b + 4], s.rects[b + 5]),
		"origin": origin - Vector2(s.rects[b + 2], s.rects[b + 3])}


## The used part of grid frame `fr` (Rect2i in grid pixels) as the packed rect saw it: the
## frame's rect less its 1 px border, empty for a blank frame. (A Hud portrait without its
## own crop centres on this.)
func used_rect(fr: Rect2i) -> Rect2i:
	var c := fr.position.x / frame.x
	var r := fr.position.y / frame.y
	var b := (r * cols + c) * RECT_SIZE
	if b + RECT_SIZE > rects.size() or rects[b + 4] <= 0:
		return Rect2i()
	var img := held().get_image() if held() != null else null
	if img != null:
		if img.is_compressed():
			img.decompress()
		var u := img.get_region(Rect2i(rects[b], rects[b + 1], rects[b + 4], rects[b + 5])).get_used_rect()
		if u.size.x > 0:
			return Rect2i(u.position + Vector2i(rects[b + 2], rects[b + 3]), u.size)
	return Rect2i(rects[b + 2], rects[b + 3], rects[b + 4], rects[b + 5]).grow(-1)
