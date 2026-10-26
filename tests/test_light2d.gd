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


func test_the_sun_follows_each_seen_fighter_and_the_moon_at_night() -> void:
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
	assert_eq(lv.suns_on(), 1, "the moon follows the seen fighter at night")
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
	assert_false(Light2DView.lamps_on({"id": "bare"}, "night"), "a map without `lights` keeps its baked pools")
	lv.apply(sim, {"time": "night", "weather": "clear"}, Vector2(0.25, 1))
	var n: int = (sim.arena["lights"] as Array).size()
	assert_eq(lv.lamps.size(), n, "every lamp")
	var fighter := 0
	for lp in lv.lamps:
		if float(lp["fighter_energy"]) > 0.0:
			fighter += 1
	assert_eq(lv.lights_on(), n + fighter, "a floor light each, and a fighter light for the lamps that light fighters")
	lv.tier = Light2DView.Tier.LOW
	lv.apply(sim, {"time": "night", "weather": "clear"}, Vector2(0.25, 1))
	assert_eq(lv.lamps.size(), 0, "Low keeps the baked light map")
	_free(r)


func test_pete_and_culvert_have_normal_sheets_the_sprite_uses() -> void:
	for id in ["pete", "culvert"]:
		var sp: Dictionary = MatchFactory.load_def(id)["sprite"]
		var paths: Array = [String(sp["path"])]
		for vname in sp.get("views", {}):
			paths.append(String(sp["views"][vname]["path"]))
		for p in paths:
			var n := String(p).get_basename() + "_n.png"
			assert_true(ResourceLoader.exists(n), "%s has %s" % [id, n])
			if ResourceLoader.exists(n):
				var a: Texture2D = load(p)
				var b: Texture2D = load(n)
				assert_eq(b.get_size(), a.get_size(), "%s: same layout as its colour sheet" % n)
		var sim := MatchFactory.training(id)
		var v := CreatureView.new()
		v.setup(sim.creatures[0])
		assert_true(v.sprite.texture is CanvasTexture, "%s draws through a CanvasTexture" % id)
		assert_true(v.lit(), "%s takes the lights" % id)
		assert_eq(v.sprite.light_mask, Light2DView.FIGHTER_MASK, "%s is on the fighter light mask" % id)
		assert_eq(v.sheet().resource_path, String(sp["path"]), "the colour sheet is still the sheet")
		v.free()
	# A fighter without normal sheets draws exactly as before: no lights reach it.
	var sim2 := MatchFactory.training("cairn")
	var v2 := CreatureView.new()
	v2.setup(sim2.creatures[0])
	assert_false(v2.sprite.texture is CanvasTexture, "cairn keeps a plain texture")
	assert_false(v2.lit(), "and no light reaches him")
	assert_eq(v2.sprite.light_mask, 1, "default mask: no light uses it")
	v2.free()


func test_the_light_texture_fades_to_black_at_its_edge() -> void:
	var img := Light2DView.radial().get_image()
	var n := img.get_width()
	assert_gt(img.get_pixel(n / 2, n / 2).r, 0.95, "white in the middle")
	assert_lt(img.get_pixel(n / 2, n - 2).r, 0.02, "black at the edge (lights add, so nothing may spill)")
	assert_lt(img.get_pixel(1, 1).r, 0.01, "and in the corners")


## Every floor point the test samples (every 16 px, edges included).
static func _floor_points(fr: Rect2) -> Array:
	var out: Array = []
	var y := fr.position.y
	while y <= fr.end.y:
		var x := fr.position.x
		while x <= fr.end.x:
			out.append(Vector2(x, y))
			x += 16.0
		y += 16.0
	return out


## A lamp's floor light at `p` (the pool texture's flat core and smoothstep edge, times its energy).
static func _lamp_at(lp: Dictionary, p: Vector2) -> float:
	var d := p.distance_to(lp["pos"]) / float(lp["radius"])
	var f := clampf((1.0 - d) / (1.0 - Light2DView.POOL_CORE), 0.0, 1.0)
	return f * f * (3.0 - 2.0 * f) * float(lp["energy"])


func test_night_is_offered_only_where_an_arena_lists_it() -> void:
	var nights: Array = []
	for id in ArenaMap.IDS + ArenaMap.MODE_IDS:
		if "night" in WeatherView.times_of(_arena(id)):
			nights.append(id)
	assert_eq(nights, ["floodgate"], "night on the Floodgate only (Kevin, Oct 2026)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 60:
		assert_true(String(WeatherView.resolve(_arena("stadium"), "random", "clear", rng)["time"]) != "night",
			"Random never draws night on a map without it")
	assert_eq(String(WeatherView.resolve(_arena("twin_keeps"), "night", "clear")["time"]), "day",
		"asking for night there plays day")


func test_every_arena_with_a_night_has_lamps_on_its_floor() -> void:
	for id in ArenaMap.IDS + ArenaMap.MODE_IDS:
		var a := _arena(id)
		if not "night" in WeatherView.times_of(a):
			continue
		var sim := MatchSim.new()
		sim.set_arena(id)
		assert_true(Light2DView.lamps_on(a, "night"), "%s: lamps at night" % id)
		var list: Array = a.get("lights", [])
		assert_true(list.size() <= Light2DView.MAX_LAMPS, "%s: at most %d lamps (Godot draws 15 lights on one canvas item)" % [id, Light2DView.MAX_LAMPS])
		var size := sim.arena_size()
		var pic := Rect2(-WeatherView.MARGIN, size + WeatherView.MARGIN * 2.0)
		var fr := sim.floor_rect()
		var lamps: Array = []
		var heads: Array = []
		for e in list:
			var lp := Light2DView.lamp_of(e)
			lamps.append(lp)
			assert_true(pic.has_point(lp["pos"]), "%s: lamp at %s is on the map" % [id, lp["pos"]])
			if bool(lp["lamp"]):
				heads.append(lp["pos"])
			else:
				assert_true(fr.has_point(lp["pos"]), "%s: the pool at %s falls on the floor" % [id, lp["pos"]])
		# every lamp head the furniture shows has its light, so it glows at night
		for e in a.get("furniture", []):
			var h := FurnitureView.head_of(e, size)
			if h == Vector2.INF:
				continue
			var near := false
			for q in heads:
				near = near or h.distance_to(q) <= Light2DView.HEAD_NEAR
			assert_true(near, "%s: the %s head at %s has a lamp" % [id, e["kind"], h])
		# separate pools: no two bright cores overlap, and the night stays dark between them
		# (a fighter there keeps `lit_fighter_min` and the moon, not a brighter floor)
		for i in lamps.size():
			for j in range(i + 1, lamps.size()):
				var a1: Dictionary = lamps[i]
				var a2: Dictionary = lamps[j]
				if bool(a1["lamp"]) or bool(a2["lamp"]):
					continue
				var d := Vector2(a1["pos"]).distance_to(a2["pos"])
				var cores := (float(a1["radius"]) + float(a2["radius"])) * Light2DView.POOL_CORE
				assert_gt(d, cores, "%s: the pools at %s and %s keep their cores apart" % [id, a1["pos"], a2["pos"]])
				var mid := (Vector2(a1["pos"]) + Vector2(a2["pos"])) * 0.5
				var between := false  # another pool sits between them: they aren't neighbours
				for k in lamps.size():
					if k != i and k != j and not bool(lamps[k]["lamp"]) and mid.distance_to(lamps[k]["pos"]) < float(lamps[k]["radius"]):
						between = true
				if between:
					continue
				var gap := 0.0
				for lp in lamps:
					gap += _lamp_at(lp, mid)
				assert_lt(gap, 0.5, "%s: dark between the pools at %s and %s (%.2f)" % [id, a1["pos"], a2["pos"], gap])
		var most := 0
		var dark := 0
		var pts := _floor_points(fr)
		for p in pts:
			var sum := 0.0
			var n := 0
			for lp in lamps:
				sum += _lamp_at(lp, p)
				if float(lp["fighter_energy"]) > 0.0 and p.distance_to(lp["pos"]) < float(lp["radius"]) + 40.0:
					n += 1
			if sum < 0.1:
				dark += 1
			most = maxi(most, n)
		assert_gt(float(dark) / pts.size(), 0.3, "%s: a real night: much of the floor is dark" % id)
		assert_gt(float(WeatherView.data()["times"]["night"]["lit_fighter_min"]), 0.6, "a fighter in the dark still reads")
		assert_true(most + Light2DView.MAX_DYNAMIC + 1 <= 15, "%s: lamps + moving lights + its moon fit a sprite's 15 lights (%d lamps)" % [id, most])


func test_the_sun_is_per_arena_and_per_time() -> void:
	var desert := Light2DView.sun_of(_arena("caravan_pass"), "day", "clear")
	var glass := Light2DView.sun_of(_arena("greenhouse"), "day", "clear")
	assert_gt(float(desert["energy"]), float(glass["energy"]), "the desert sun is harder than the light through glass")
	assert_gt(float(desert["energy"]), 0.34, "stronger than phase 0's sun")
	for id in ArenaMap.IDS + ArenaMap.MODE_IDS:
		var a := _arena(id)
		var day := Light2DView.sun_of(a, "day", "clear")
		var dusk := Light2DView.sun_of(a, "sunset", "clear")
		var moon := Light2DView.sun_of(a, "night", "clear")
		var rain := Light2DView.sun_of(a, "day", "rain")
		assert_gt(float(dusk["energy"]), float(day["energy"]), "%s: the low sun is stronger" % id)
		assert_lt(float(dusk["height"]), float(day["height"]), "%s: and lower" % id)
		assert_gt((dusk["color"] as Color).r - (dusk["color"] as Color).b, 0.2, "%s: and warm" % id)
		assert_lt(float(moon["energy"]), float(day["energy"]) * 0.6, "%s: the moon is faint" % id)
		assert_gt((moon["color"] as Color).b, (moon["color"] as Color).r, "%s: and cool" % id)
		assert_lt(float(rain["energy"]), float(day["energy"]), "%s: rain softens the sun" % id)
		assert_gt(float(rain["shade"]), float(day["shade"]), "%s: and the shade side" % id)
		assert_lt(float(day["energy"]), 1.0, "%s: never strong enough to bleach a face" % id)


func test_in_a_4v4_on_the_biggest_map_no_sprite_takes_more_than_15_lights() -> void:
	var r := TeamSim.load_rules(TeamSim.CTF_PATH)
	var t := TeamSim.new([["pete", "culvert", "pete", "culvert"], ["culvert", "pete", "culvert", "pete"]], 4, r)
	var sim := t.sim
	assert_eq(sim.arena_id, "twin_keeps", "the biggest map")
	var fx := FxView.new()
	fx.sim = sim
	fx.unseen = []
	for c in sim.creatures:
		fx.unseen.append(false)
	var lv := Light2DView.new()
	lv.fx = fx
	lv._ready()
	var views: Array = []
	var mid := sim.floor_rect().get_center()
	for i in sim.creatures.size():
		var c: CreatureSim = sim.creatures[i]
		c.pos = mid + Vector2((i % 4) * 14.0, (i / 4) * 14.0)  # all in one heap
		c.energy = CreatureSim.MAX_ENERGY
		var v := CreatureView.new()
		v.setup(c)
		views.append(v)
	lv.views = views
	lv.apply(sim, {"time": "night", "weather": "clear"}, Vector2(0.25, 1))
	lv.advance()
	assert_true(lv.dynamic.size() <= Light2DView.MAX_DYNAMIC, "moving lights capped")
	assert_eq(lv.suns_on(), 8, "a moon for each fighter")
	var lights: Array = []
	for ch in lv.get_children():
		if ch is PointLight2D and (ch as PointLight2D).enabled:
			lights.append(ch)
	for v in views:
		var cv := v as CreatureView
		assert_true(cv.lit(), "lit")
		var n := 0
		for l in lights:
			var pl := l as PointLight2D
			var reach := pl.texture_scale * Light2DView.TEX_SIZE * 0.5 + 40.0
			if pl.range_item_cull_mask & cv.sprite.light_mask and pl.position.distance_to(cv.c.pos) < reach:
				n += 1
		assert_true(n <= 15, "%s takes %d lights" % [cv.c.def.get("id", "?"), n])
		assert_gt(n, 0, "and some")
	var bits := {}
	for v in views:
		bits[(v as CreatureView).sun_bit] = true
	assert_eq(bits.size(), 8, "each fighter has its own moon")
	for v in views:
		(v as CreatureView).free()
	fx.free()
	lv.free()
