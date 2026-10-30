extends TestCase
## No map hides a solid piece under tree crowns: a wall or fence (or brush, which stops
## nothing) under the leaves, drawn above the fighters (ArenaView `_adopt_canopies`), is a
## blockage nobody can see. Geometry as the view: each crown of the dressing scene's
## "Canopies" group is its picture (position + offset, frame 0, mirrored by flip_h) in
## scene px, 16 to a cell; only its opaque pixels (alpha >= 0.5) hide anything.

const MAPS := ["stadium", "quarry", "twin_keeps", "caravan_pass", "floodgate", "greenhouse"]
const CELL_PX := 16
const MAX_HIDDEN := 0.5


## One map's crowns as [Rect2 (scene px), Image or null, flip_h].
static func crowns(map: String) -> Array:
	var out: Array = []
	var ps := load("res://assets/arenas/%s_dressing.tscn" % map) as PackedScene
	if ps == null:
		return out
	var root := ps.instantiate()
	var group := root.get_node_or_null("Canopies")
	if group != null:
		for n in group.get_children():
			var a := n as AnimatedSprite2D
			if a == null or a.sprite_frames == null:
				continue
			var tex := a.sprite_frames.get_frame_texture(a.animation, 0)
			var img: Image = tex.get_image() if tex != null else null
			if tex == null:
				continue
			out.append([Rect2(a.position + a.offset, tex.get_size()), img, a.flip_h])
	root.free()
	return out


static func _opaque(c: Array, x: int, y: int) -> bool:
	var r: Rect2 = c[0]
	var lx := x - int(r.position.x)
	var ly := y - int(r.position.y)
	if lx < 0 or ly < 0 or lx >= int(r.size.x) or ly >= int(r.size.y):
		return false
	if c[1] == null:
		return true
	if c[2]:
		lx = int(r.size.x) - 1 - lx
	return (c[1] as Image).get_pixel(lx, ly).a >= 0.5


## Share (0..1) of a piece's rect [col, row, w, h] (cells) hidden under the crowns.
static func hidden_share(rect: Array, cs: Array) -> float:
	var x0 := int(rect[0]) * CELL_PX
	var y0 := int(rect[1]) * CELL_PX
	var x1 := x0 + int(rect[2]) * CELL_PX
	var y1 := y0 + int(rect[3]) * CELL_PX
	var hit := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			for c in cs:
				if _opaque(c, x, y):
					hit += 1
					break
	return float(hit) / float((x1 - x0) * (y1 - y0))


## [[index, kind, rect, share]] for every solid piece of the map, in file order.
static func report(map: String) -> Array:
	var f := FileAccess.open("res://data/arenas/%s.json" % map, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var cs := crowns(map)
	var out: Array = []
	var pieces: Array = data.get("pieces", [])
	for i in pieces.size():
		var k := String(pieces[i].get("kind", ""))
		if k in ["wall", "fence", "brush"] and not cs.is_empty():
			out.append([i, k, pieces[i]["rect"], hidden_share(pieces[i]["rect"], cs)])
	return out


func test_no_solid_piece_is_hidden_under_a_crown() -> void:
	assert_true(not crowns("twin_keeps").is_empty(), "Twin Keeps has no Canopies group: this test would check nothing")
	for map in MAPS:
		for r in report(map):
			if r[1] == "brush":
				continue
			assert_true(r[3] <= MAX_HIDDEN, "%s piece %d (%s %s) is %d%% under tree crowns:" % [map, r[0], r[1], r[2], int(r[3] * 100)])


## `QA_OCCLUDED=1` prints every piece under a crown (a report, not a check).
func test_report() -> void:
	if OS.get_environment("QA_OCCLUDED") == "":
		return
	for map in MAPS:
		for r in report(map):
			if r[3] > 0.0:
				print("OCC %s #%d %s %s %d%%" % [map, r[0], r[1], r[2], int(r[3] * 100)])
