extends TestCase
## Texture memory: fighter sheets are drawn from packed copies (tools/pack_sheets.py,
## PackedSheet), so a 4v4 with the whole roster at 2x fits the budget (docs/plans/roster-2x.md):
## every fighter's every view is packed and up to date with its grid sheet, packed rects draw at
## their grid places (mirrored too), the colour sheets stay lossless while the normal and
## emissive ones are VRAM-compressed, Lighting Off loads no normal or emissive sheet, and the
## sheets a 4v4 holds stay under the budget measured with --print-vram (with headroom).

## Bytes a pixel takes as Godot holds it: colour lossless RGBA8; normal and emissive sheets
## VRAM-compressed (S3TC/RGTC on desktop, ETC2 on Android: 1 byte a pixel).
const BPP := {"colour": 4, "normal": 1, "emit": 1}
## The eight largest fighters' sheets in a 4v4, every one at 2x (a 1x sheet counted 4 times, an
## overestimate: packing wastes less on bigger frames; Crease's real 2x sheets hold 13.4 MB):
## 328 MB when this was written (Oct 27 2026), about 2.7 GB before packing. With the rest of a
## match's textures (about 85 MB) that is about 0.4 GB, under the 1 GB budget with headroom.
const BUDGET_4V4_2X_MB := 450.0
## One fighter at 2x: the most any one may hold (Craglash's projection, 67 MB, is the largest).
const BUDGET_ONE_2X_MB := 90.0


func _view(id: String) -> CreatureView:
	var sim := MatchFactory.training(id) if id != "dummy" else MatchFactory.training("cairn")
	var v := CreatureView.new()
	v.setup(sim.creatures[0 if id != "dummy" else 1])
	return v


## {colour, normal, emit} bytes of a view's sheets, each texture once.
static func _bytes(v: CreatureView) -> Dictionary:
	var out := {"colour": 0, "normal": 0, "emit": 0}
	var seen := {}
	for vw in v._views.values():
		var kinds := {"colour": vw["tex"], "emit": vw["emit"]}
		var lt = vw["lit"]
		if lt is PackedSheet:
			lt = (lt as PackedSheet).draw_tex
		if lt is CanvasTexture:
			kinds["normal"] = (lt as CanvasTexture).normal_texture
		for k in kinds:
			var t: Texture2D = kinds[k]
			if t is PackedSheet:
				t = (t as PackedSheet).held()
			if t == null or seen.has(t):
				continue
			seen[t] = true
			out[k] += t.get_width() * t.get_height() * int(BPP[k])
	return out


func test_every_fighter_draws_packed_sheets_up_to_date_with_the_grid() -> void:
	for id in MatchFactory.FIGHTERS + ["dummy"]:
		var v := _view(id)
		for name in v._views:
			var vw: Dictionary = v._views[name]
			assert_true(vw["tex"] is PackedSheet, "%s %s: drawn from its packed copy (tools/pack_sheets.py)" % [id, name])
			if not vw["tex"] is PackedSheet:
				continue
			var ps := vw["tex"] as PackedSheet
			var lay := PackedSheet.layout_of(ps.source)
			var src: Dictionary = lay.get("sources", {})
			assert_eq(String(src.get("colour", "")), FileAccess.get_md5(ps.source),
				"%s: packed from the grid sheet as it is now (rerun tools/pack_sheets.py %s)" % [ps.source, id])
			for k in [["normal", "_n.png"], ["emissive", "_e.png"]]:
				var g := ps.source.get_basename() + String(k[1])
				if FileAccess.file_exists(g):
					assert_eq(String(src.get(k[0], "")), FileAccess.get_md5(g), "%s: packed as it is now" % g)
			assert_eq(Vector2i(ps.get_width(), ps.get_height()), Vector2i(int(lay["width"]), int(lay["height"])),
				"%s: reports the grid sheet's size" % ps.source)
			assert_true(vw["lit"] is PackedSheet and vw["lit"] != vw["tex"], "%s %s: lit through its packed normals" % [id, name])
		v.free()


func test_packed_imports_keep_colour_lossless_and_compress_the_rest() -> void:
	var dir := "res://assets/sprites/packed"
	var n := 0
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".png.import"):
			continue
		n += 1
		var txt := FileAccess.get_file_as_string(dir.path_join(f))
		assert_true(txt.contains("mipmaps/generate=false"), "%s: no mipmaps" % f)
		var extra := f.ends_with("_n.png.import") or f.ends_with("_e.png.import")
		if extra:
			assert_true(txt.contains("compress/mode=2"), "%s: VRAM-compressed" % f)
		else:
			assert_true(txt.contains("compress/mode=0"), "%s: lossless (palette pixel art)" % f)
	assert_gt(n, 50, "the packed sheets are there")


func test_pieces_land_at_their_grid_places_mirrored_too() -> void:
	# Two 10x10 frames across; frame 0 uses (2,3)-(6,8) packed at (0,0); frame 1 is empty;
	# frame 2 (row 1) uses (0,0)-(10,10) packed at (8,0).
	var s := PackedSheet.make({"width": 20, "height": 20, "frame": [10, 10], "cols": 2,
		"rects": [[0, 0, 2, 3, 4, 5], [], [8, 0, 0, 0, 10, 10], []]}, null)
	var p := s.pieces(Rect2(100, 100, 10, 10), Rect2(0, 0, 10, 10))
	assert_eq(p.size(), 1, "one piece for one frame")
	assert_eq(p[0][0], Rect2(102, 103, 4, 5), "at its place in the frame")
	assert_eq(p[0][1], Rect2(0, 0, 4, 5), "from its packed rect")
	var m := s.pieces(Rect2(100, 100, -10, 10), Rect2(0, 0, 10, 10))
	assert_eq(m[0][0], Rect2(104, 103, -4, 5), "mirrored: the far side of the frame, flipped")
	var k := s.pieces(Rect2(0, 0, 20, 20), Rect2(0, 0, 10, 10))
	assert_eq(k[0][0], Rect2(4, 6, 8, 10), "scaled with the destination")
	assert_true(s.pieces(Rect2(0, 0, 10, 10), Rect2(10, 0, 10, 10)).is_empty(), "an empty frame draws nothing")
	var band := s.pieces(Rect2(0, 0, 10, 2), Rect2(0, 4, 10, 2))
	assert_eq(band[0][1], Rect2(0, 1, 4, 2), "a band of rows cuts the packed rect")
	assert_eq(band[0][0], Rect2(2, 0, 4, 2))
	var piece := PackedSheet.piece(s, Rect2(0, 0, 10, 10), Vector2(5, 9))
	assert_eq(piece["region"], Rect2(0, 0, 4, 5), "a frame on its own: its packed rect")
	assert_eq(piece["origin"], Vector2(3, 6), "and the feet moved into it")
	assert_false(s._is_pixel_opaque(0, 0), "outside the used rect")
	assert_true(s._is_pixel_opaque(3, 4), "inside it")


func test_lighting_off_loads_no_normal_or_emissive_sheets() -> void:
	var was := CreatureView.lit_sheets
	CreatureView.set_lit_sheets(false)
	var v := _view("crease")
	for name in v._views:
		var vw: Dictionary = v._views[name]
		assert_eq(vw["lit"], vw["tex"], "Off: %s has no normals loaded" % name)
		assert_eq(vw["emit"], null, "Off: %s has no emissive sheet loaded" % name)
	assert_eq(_bytes(v)["normal"] + _bytes(v)["emit"], 0, "nothing but the colour sheets held")
	CreatureView.set_lit_sheets(true)  # Lighting turned back on mid-match: the live view reloads
	assert_ne(v._views["side"]["lit"], v._views["side"]["tex"], "normals back")
	assert_true(v._views["side"]["emit"] != null, "the emissive sheet back")
	v.refresh()
	assert_true(v.lit(), "and the lights take the sprite again")
	v.free()
	CreatureView.set_lit_sheets(was)


func test_a_4v4_at_2x_fits_the_texture_budget() -> void:
	var proj := []
	for id in MatchFactory.FIGHTERS:
		var v := _view(id)
		var b := _bytes(v)
		var total := float(b["colour"] + b["normal"] + b["emit"]) / 1048576.0
		var at2x := total * (4.0 if v.ppu == 1 else 1.0)
		assert_lt(at2x, BUDGET_ONE_2X_MB, "%s at 2x: %.1f MB of sheets" % [id, at2x])
		proj.append(at2x)
		v.free()
	proj.sort()
	proj.reverse()
	var sum := 0.0
	for i in mini(8, proj.size()):
		sum += proj[i]
	assert_lt(sum, BUDGET_4V4_2X_MB, "the eight largest at 2x: %.1f MB of sheets" % sum)


func assert_ne(a, b, msg := "") -> void:
	assert_false(a == b, msg)
