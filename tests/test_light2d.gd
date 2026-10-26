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
	assert_eq(lv.lights_on(), 2, "and it's on (on the fighters, and on the floor)")
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
	# a crowded 4v4's worth of shots and sparks, spread out so they don't merge
	var raw: Array = []
	for i in 12:
		raw.append([Vector2(i * 130.0, 100.0), 16.0, Color.WHITE, 40.0, 0.2 + i * 0.05, 0.5, false, 0])
	lv.focus = Vector2(0, 100)
	lv.take(raw)
	assert_eq(lv.dynamic.size(), Light2DView.MAX_DYNAMIC, "%d kept" % Light2DView.MAX_DYNAMIC)
	assert_eq(lv.lights_on(), Light2DView.MAX_DYNAMIC * 2, "and no more lights on (one on the fighters, one on the floor)")
	for d in lv.dynamic:
		assert_lt(Vector2(d[0]).x, 8 * 130.0, "the four furthest from the camera's centre went first")
	assert_eq(lv.gathered.size(), 12, "all of them still gathered (bloom, halos)")
	assert_eq(lv.pools.size(), 4, "Glow's pools only for the four left over")
	lv.tier = Light2DView.Tier.LOW
	lv.take(raw)
	assert_eq(lv.dynamic.size(), Light2DView.LOW_DYNAMIC, "Low: %d real" % Light2DView.LOW_DYNAMIC)
	lv.tier = Light2DView.Tier.OFF
	lv.take(raw)
	assert_eq(lv.dynamic.size() + lv.gathered.size() + lv.pools.size() + lv.lights_on(), 0, "Off: nothing")
	_free(r)


func test_a_surge_comes_first_then_the_nearest_then_the_newest() -> void:
	var r := _setup("culvert", "pete")
	var lv: Light2DView = r[2]
	lv.tier = Light2DView.Tier.LOW  # two real lights
	lv.focus = Vector2.ZERO
	var far_surge := [Vector2(900, 0), 16.0, Color.VIOLET, 52.0, 0.34, 0.12, true, 0]
	var near_old := [Vector2(40, 0), 10.0, Color.WHITE, 24.0, 0.9, 1.0, false, 30]
	var near_new := [Vector2(-60, 0), 10.0, Color.GREEN, 24.0, 0.3, 1.0, false, 2]
	var mid := [Vector2(400, 0), 10.0, Color.RED, 24.0, 1.0, 1.0, false, 0]
	lv.take([mid, near_old, far_surge, near_new])
	assert_eq(lv.dynamic.size(), 2, "two")
	assert_eq(Color(lv.dynamic[0][2]), Color.VIOLET, "the Surge first, however far")
	assert_eq(Color(lv.dynamic[1][2]), Color.GREEN, "then, both near the centre, the newer (not the brighter)")
	_free(r)


func test_close_lights_share_one_real_light() -> void:
	var r := _setup("culvert", "pete")
	var lv: Light2DView = r[2]
	# a volley of knives a little apart (different merge cells): one light, not three
	var raw: Array = []
	for i in 3:
		raw.append([Vector2(100 + i * 15.0, 100.0 + i * 12.0), 10.0, Color("d58cff"), 22.0, 0.4, 1.0, false, i])
	raw.append([Vector2(400, 100), 10.0, Color.WHITE, 22.0, 0.4, 1.0, false, 0])
	lv.take(raw)
	assert_eq(lv.dynamic.size(), 2, "the volley is one light, the far shot another")
	assert_near(float(lv.dynamic[0][4]), 1.0, 0.001, "their strength adds up (to 1)")
	_free(r)


func test_a_real_light_lights_the_floor_and_its_pool_goes() -> void:
	var r := _setup("pete", "culvert")
	var lv: Light2DView = r[2]
	var glow := Light2DView.FloorGlow.new()
	lv.floor_glow = glow
	lv.apply(r[0], {"time": "night", "weather": "clear"}, Vector2(0.25, 1))
	assert_true(lv.night, "night")
	assert_false(glow.visible, "no fight light yet: the floor glow isn't drawn")
	var raw: Array = []
	for i in 10:
		raw.append([Vector2(i * 130.0, 100.0), 10.0, Color.WHITE, 30.0, 0.5, 1.0, false, 0])
	lv.focus = Vector2(0, 100)
	lv.take(raw)
	assert_eq(lv.dynamic.size(), Light2DView.MAX_DYNAMIC, "eight real")
	assert_eq(lv.lights_on() - lv.lamps.size() * 2, Light2DView.MAX_DYNAMIC * 2, "each on the fighters and the floor")
	assert_true(glow.visible, "the floor glow takes them")
	assert_eq(glow.light_mask, Light2DView.GLOW_MASK, "on its own mask: the night shade and the lamps don't mix in")
	assert_eq(lv.pools.size(), 2, "Glow's dithered pools only for the two left over: no floor lit twice")
	lv.apply(r[0], {"time": "day", "weather": "clear"}, Vector2(0.25, 1))
	lv.take(raw)
	assert_eq(lv.pools.size(), 2, "by day too (the floor glow adds, so it shows on a sunlit floor)")
	lv.tier = Light2DView.Tier.OFF
	lv.take(raw)
	assert_false(glow.visible, "Off: gone")
	glow.free()
	_free(r)


func test_projectiles_become_real_lights() -> void:
	var r := _setup("cerebro", "cairn")
	var sim: MatchSim = r[0]
	var lv: Light2DView = r[2]
	var me: CreatureSim = sim.creatures[0]
	me.pos = sim.creatures[1].pos + Vector2(-260, 0)
	me.facing = Vector2.RIGHT
	var flew := false
	var lit := false
	for i in 40:
		run(sim, SimDefs.IN_SKILL1 if i < 2 else 0, 1)
		(r[1] as FxView).advance()
		lv.advance()
		for pr in sim.projectiles:
			flew = true
			for d in lv.dynamic:
				if Vector2(d[0]).distance_to(pr["pos"]) < 30.0:
					lit = true
	assert_true(flew, "(he threw his cleaver)")
	assert_true(lit, "and it carries a real light")
	_free(r)


## FxView that can't see anything a hidden foe throws (as behind a wall).
class BlindFx extends FxView:
	func sight_to(_p: Vector2) -> bool:
		return false


func test_a_hidden_foes_projectile_gives_no_light() -> void:
	var sim := MatchFactory.versus("cairn", "cerebro")
	var fx := BlindFx.new()
	fx.sim = sim
	fx.unseen = [false, true]
	var lv := Light2DView.new()
	lv.fx = fx
	lv._ready()
	var foe: CreatureSim = sim.creatures[1]
	foe.pos = sim.creatures[0].pos + Vector2(260, 0)
	foe.facing = Vector2.LEFT
	var flew := false
	for i in 40:
		run(sim, 0, 1, SimDefs.IN_SKILL1 if i < 2 else 0)
		fx.advance()
		lv.advance()
		flew = flew or not sim.projectiles.is_empty()
		assert_eq(lv.gathered.size(), 0, "no light from a hidden foe's cleaver (tick %d)" % i)
	assert_true(flew, "(he did throw)")
	fx.free()
	lv.free()


func test_a_big_hit_and_a_surge_flash_for_a_few_ticks() -> void:
	var r := _setup("pete", "culvert")
	var sim: MatchSim = r[0]
	var lv: Light2DView = r[2]
	var at := sim.creatures[1].pos
	lv.on_event({"type": "hit", "pos": at, "power": 4.0, "heavy": false, "attacker": 0, "target": 1, "move_type": "light"})
	assert_eq(lv.flashes(), 0, "a light jab doesn't flash")
	lv.on_event({"type": "hit", "pos": at, "power": 16.0, "heavy": true, "attacker": 0, "target": 1, "move_type": "heavy"})
	assert_eq(lv.flashes(), 1, "a big heavy does")
	var seen: Array = []
	for i in 12:
		lv.advance()
		seen.append(_near(lv, at, 20.0))
	assert_eq(seen[0], 1, "lit at once")
	assert_eq(seen[11], 0, "and out within %d ticks" % int(Light2DView.FLASH_HIT[2]))
	# A hidden fighter's Surge doesn't flash.
	(r[1] as FxView).unseen = [false, true]
	(r[1] as FxView).viewer_team = 0
	lv.on_event({"type": "surge", "pos": at, "power": 0.0, "who": 1})
	assert_eq(lv.flashes(), 0, "no flash gives a hidden Surge away")
	lv.tier = Light2DView.Tier.OFF
	(r[1] as FxView).unseen = [false, false]
	lv.on_event({"type": "surge", "pos": at, "power": 0.0, "who": 1})
	assert_eq(lv.flashes(), 0, "Off: no flashes")
	_free(r)


## An emissive fixture the size of the sheet, written by the test (not committed art).
static func _fixture(sheet: Texture2D, path: String) -> void:
	var img := Image.create(sheet.get_width(), sheet.get_height(), false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(10, 10, 4, 4), Color(1.0, 0.9, 0.3, 1.0))
	img.save_png(path)


func test_an_emissive_sheet_draws_over_the_sprite_when_there_is_one() -> void:
	var sim := MatchFactory.training("pete")
	var c: CreatureSim = sim.creatures[0]
	var sp: Dictionary = (c.def["sprite"] as Dictionary).duplicate(true)
	var path := "user://test_pete_e.png"
	_fixture(load(String(sp["path"])), path)
	# Without one (none on main yet): no layer, and nothing changes.
	var v0 := CreatureView.new()
	v0.setup(c)
	assert_false(v0.emitting(), "no _e.png: no emissive layer")
	assert_true(v0.emit_frame().is_empty(), "and nothing to bloom")
	v0.free()
	assert_eq(CreatureView.load_emissive("res://assets/sprites/no_such_e.png"), null, "a missing sheet is null")
	# With one, named by the view block.
	sp["emissive"] = path
	var def := c.def.duplicate()
	def["sprite"] = sp
	c.def = def
	var v := CreatureView.new()
	v.setup(c)
	assert_true(v.emitting(), "the fixture shows as the emissive layer")
	assert_eq(v.emit.frame, v.sprite.frame, "on the sprite's frame")
	assert_eq(v.emit.light_mask, 1, "outside every light (it gives light, it doesn't take it)")
	var e := v.emit_frame()
	assert_eq(Vector2(e["size"]), Vector2(v.emit.texture.get_width() / v.sprite.hframes,
		v.emit.texture.get_height() / v.sprite.vframes), "a frame of the sheet")
	v.sprite.self_modulate = Color(0.3, 0.3, 0.4)  # the night's tint
	v.refresh()
	assert_eq(v.emit.self_modulate, Color.WHITE, "the night's tint doesn't dim it")
	CreatureView.emissive_on = false  # Lighting Off
	v.refresh()
	assert_false(v.emitting(), "Off: no emissive layer")
	CreatureView.emissive_on = true
	v.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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
