extends TestCase
## Lighting (Light2DView, BloomView, Settings > Video > Lighting): real 2D lights on the
## fighters from their normal sheets, the night's lamps from the arena JSON, and never a light
## that gives away a fighter the local team can't see.


func _setup(a: String, b: String) -> Array:
	var sim := MatchFactory.versus(a, b)
	var fx := FxView.new()
	fx.sim = sim
	fx.unseen = [false, false]
	var lv := Light2DView.new()
	lv.fx = fx
	lv._ready()
	return [sim, fx, lv]


static func _arena(id: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/arenas/%s.json" % id))
	return parsed if parsed is Dictionary else {}


func _free(r: Array) -> void:
	(r[1] as FxView).free()
	(r[2] as Light2DView).free()


func _near(lv: Light2DView, p: Vector2, r := 80.0) -> int:
	var n := 0
	for l in lv.dynamic:
		if Vector2(l[0]).distance_to(p) <= r:
			n += 1
	return n


func test_a_ready_surge_becomes_a_real_light_on_the_fighters() -> void:
	var r := _setup("culvert", "pete")
	var c: CreatureSim = r[0].creatures[0]
	c.energy = CreatureSim.MAX_ENERGY
	var lv: Light2DView = r[2]
	lv.advance()
	assert_eq(_near(lv, c.pos), 1, "one light at his aura")
	assert_eq(lv.lights_on(), 1, "and it's on")
	_free(r)


func test_a_hidden_fighter_gives_no_light() -> void:
	var r := _setup("cerebro", "hissy")
	var sim: MatchSim = r[0]
	var lv: Light2DView = r[2]
	var foe: CreatureSim = sim.creatures[1]
	foe.energy = CreatureSim.MAX_ENERGY
	(r[1] as FxView).unseen = [false, true]  # in the brush, or behind a wall
	lv.advance()
	assert_eq(_near(lv, foe.pos), 0, "a hidden foe's Surge doesn't light anyone")
	# Her Stone Gaze (fx.light) doesn't either.
	foe.energy = 0.0
	sim.creatures[0].pos = foe.pos + Vector2(200, 0)
	for i in 30:
		run(sim, 0, 1, SimDefs.IN_SKILL2 if i < 2 else 0)
		(r[1] as FxView).advance()
		lv.advance()
		assert_eq(_near(lv, foe.pos), 0, "no gaze light from a hidden foe (tick %d)" % i)
	_free(r)


func test_an_invisible_fighter_gives_no_light_and_no_sun() -> void:
	var r := _setup("pete", "digby")
	var lv: Light2DView = r[2]
	lv.apply(r[0], {"time": "day", "weather": "clear"}, Vector2(0.25, 1))
	for c in (r[0] as MatchSim).creatures:
		c.energy = CreatureSim.MAX_ENERGY
		c.stealth = 60  # Tiptoe; Burrow sets the same
	lv.advance()
	assert_eq(lv.dynamic.size(), 0, "no Surge light gives them away")
	assert_eq(lv.suns_on(), 0, "no sun follows them either")
	_free(r)


func test_the_sun_follows_each_seen_fighter_by_day_only() -> void:
	var r := _setup("pete", "culvert")
	var lv: Light2DView = r[2]
	lv.apply(r[0], {"time": "day", "weather": "clear"}, Vector2(0.25, 1))
	lv.advance()
	assert_eq(lv.suns_on(), 2, "a sun behind each fighter")
	(r[1] as FxView).unseen = [false, true]
	lv.advance()
	assert_eq(lv.suns_on(), 1, "none behind a hidden one")
	lv.apply(r[0], {"time": "night", "weather": "clear"}, Vector2(0.25, 1))
	lv.advance()
	assert_eq(lv.suns_on(), 0, "no sun at night")
	lv.tier = Light2DView.Tier.OFF
	lv.apply(r[0], {"time": "day", "weather": "clear"}, Vector2(0.25, 1))
	lv.advance()
	assert_eq(lv.lights_on(), 0, "Off: no lights at all")
	_free(r)


func test_moving_lights_are_capped_at_eight() -> void:
	var r := _setup("culvert", "pete")
	var lv: Light2DView = r[2]
	# a crowded 4v4's worth of Surges and flashes, spread out so they don't merge
	var raw: Array = []
	for i in 12:
		raw.append([Vector2(i * 60.0, 100.0), 16.0, Color.WHITE, 40.0, 0.2 + i * 0.05, 0.5])
	lv.take(raw)
	assert_eq(lv.dynamic.size(), Light2DView.MAX_DYNAMIC, "the strongest %d kept" % Light2DView.MAX_DYNAMIC)
	assert_eq(lv.lights_on(), Light2DView.MAX_DYNAMIC, "and no more lights on")
	assert_gt(float(lv.dynamic.back()[4]), 0.35, "the dimmest four went first")
	_free(r)


func test_floodgate_lamps_light_the_night_in_high_only() -> void:
	var r := _setup("pete", "culvert")
	var sim: MatchSim = r[0]
	sim.arena = _arena("floodgate")
	var lv: Light2DView = r[2]
	assert_true(Light2DView.lamps_on(sim.arena, "night"), "the Floodgate lists lamps for the night")
	assert_false(Light2DView.lamps_on(sim.arena, "day"), "not by day")
	assert_false(Light2DView.lamps_on(_arena("stadium"), "night"), "a map without `lights` keeps its baked pools")
	lv.apply(sim, {"time": "night", "weather": "clear"}, Vector2(0.25, 1))
	var n: int = (sim.arena["lights"] as Array).size()
	assert_eq(lv.lamps.size(), n, "every lamp")
	assert_eq(lv.lights_on(), n * 2, "a floor light and a fighter light each")
	lv.tier = Light2DView.Tier.LOW
	lv.apply(sim, {"time": "night", "weather": "clear"}, Vector2(0.25, 1))
	assert_eq(lv.lamps.size(), 0, "Low keeps the baked light map")
	_free(r)


## Every sheet of a fighter (and the training dummy): its colour sheet's path and those of
## its views.
static func _sheet_paths(id: String) -> Array:
	var sp: Dictionary = MatchFactory.load_def(id)["sprite"]
	var paths: Array = [String(sp["path"])]
	for vname in sp.get("views", {}):
		paths.append(String(sp["views"][vname]["path"]))
	return paths


func test_every_fighter_has_normal_sheets_the_sprite_uses() -> void:
	for id in MatchFactory.FIGHTERS + ["dummy"]:
		for p in _sheet_paths(id):
			var n := String(p).get_basename() + "_n.png"
			assert_true(ResourceLoader.exists(n), "%s has %s" % [id, n])
			if ResourceLoader.exists(n):
				var a: Texture2D = load(p)
				var b: Texture2D = load(n)
				assert_eq(b.get_size(), a.get_size(), "%s: same layout as its colour sheet" % n)
		var sim := MatchFactory.training(id) if id != "dummy" else MatchFactory.training("cairn")
		var v := CreatureView.new()
		v.setup(sim.creatures[0 if id != "dummy" else 1])
		assert_true(v.sprite.texture is CanvasTexture, "%s draws through a CanvasTexture" % id)
		assert_true(v.lit(), "%s takes the lights" % id)
		assert_eq(v.sprite.light_mask, Light2DView.FIGHTER_MASK, "%s is on the fighter light mask" % id)
		assert_eq(v.sheet().resource_path, _sheet_paths(id)[0], "the colour sheet is still the sheet")
		v.free()


func test_emissive_sheets_match_their_colour_sheets() -> void:
	# Optional per sheet (docs/SPRITES.md "Emissive sheets"): where one exists it has the colour
	# sheet's layout.
	var found := 0
	for id in MatchFactory.FIGHTERS + ["dummy"]:
		for p in _sheet_paths(id):
			var e := String(p).get_basename() + "_e.png"
			if not ResourceLoader.exists(e):
				continue
			found += 1
			var a: Texture2D = load(p)
			var b: Texture2D = load(e)
			assert_eq(b.get_size(), a.get_size(), "%s: same layout as its colour sheet" % e)
	assert_gt(found, 0, "some fighters glow")


## Full-strength emissive pixels per row of a sheet's _e.png (read as is, not the
## VRAM-compressed import), or [] when it has no emissive sheet.
static func _full_glow_rows(path: String, frame_h: int) -> Array:
	var e := path.get_basename() + "_e.png"
	if not FileAccess.file_exists(e):
		return []
	var img := Image.new()
	img.load_png_from_buffer(FileAccess.get_file_as_bytes(e))
	var out := []
	for r in img.get_height() / frame_h:
		var n := 0
		for y in range(r * frame_h, (r + 1) * frame_h):
			for x in img.get_width():
				if img.get_pixel(x, y).a8 == 255:
					n += 1
		out.append(n)
	return out


func test_surge_frames_light_the_eyes() -> void:
	# Every fighter's eyes glow at full strength in the rows its Surge plays (docs/SPRITES.md
	# "Emissive sheets"), in the views that show the face; nothing glows full in idle. Pete,
	# Gillbert, Mister Crease and Cairn glow nowhere but in the Surge.
	for id in MatchFactory.FIGHTERS:
		var d := MatchFactory.load_def(id)
		var sp: Dictionary = d["sprite"]
		var row := int(sp["anims"][String(d["moves"]["surge"]["anim"])][0])
		var idle := int(sp["anims"]["idle"][0])
		var sheets := [[String(sp["path"]), sp["frame"]]]
		for vname in ["down", "down_side"]:
			sheets.append([String(sp["views"][vname]["path"]), sp["views"][vname].get("frame", sp["frame"])])
		for s in sheets:
			var fh := int(s[1][1]) if s[1] is Array else int(s[1])
			var rows := _full_glow_rows(s[0], fh)
			assert_true(rows.size() > row and rows[row] > 0, "%s: the Surge row glows in %s" % [id, s[0]])
			if rows.size() <= row:
				continue
			assert_eq(rows[idle], 0, "%s: nothing glows full in idle in %s" % [id, s[0]])
			if id in ["pete", "gillbert", "crease", "cairn"]:
				var other := 0
				for r in rows.size():
					if r != row:
						other += rows[r]
				assert_eq(other, 0, "%s: only the Surge glows in %s" % [id, s[0]])


func test_a_sheet_without_normals_draws_exactly_as_before() -> void:
	# No light reaches a sheet without a normal sheet (its plain texture, the default mask).
	var v := CreatureView._load_view({"path": "res://assets/sprites/caravan.png", "frame": [32, 32]}, {}, [])
	assert_eq(v["lit"], v["tex"], "no CanvasTexture without a normal sheet")


func test_the_light_texture_fades_to_black_at_its_edge() -> void:
	var img := Light2DView.radial().get_image()
	var n := img.get_width()
	assert_gt(img.get_pixel(n / 2, n / 2).r, 0.95, "white in the middle")
	assert_lt(img.get_pixel(n / 2, n - 2).r, 0.02, "black at the edge (lights add, so nothing may spill)")
	assert_lt(img.get_pixel(1, 1).r, 0.01, "and in the corners")
