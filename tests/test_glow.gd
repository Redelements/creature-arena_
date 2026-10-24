extends TestCase
## Glow (LightView): glowing things light the floor, from data, and never give away a
## fighter the local team can't see.


func _setup(a: String, b: String) -> Array:
	var sim := MatchFactory.versus(a, b)
	var fx := FxView.new()
	fx.sim = sim
	fx.unseen = [false, false]
	var lv := LightView.new()
	lv.fx = fx
	return [sim, fx, lv]


func _near(lv: LightView, p: Vector2, r := 40.0) -> int:
	var n := 0
	for l in lv.lights:
		if Vector2(l[0]).distance_to(p) <= r:
			n += 1
	return n


func _free(r: Array) -> void:
	(r[1] as FxView).free()
	(r[2] as LightView).free()


func test_a_ready_surge_lights_the_floor_in_the_aura_colour() -> void:
	var r := _setup("cerebro", "cairn")
	var c: CreatureSim = r[0].creatures[0]
	c.energy = CreatureSim.MAX_ENERGY
	(r[2] as LightView).advance()
	assert_eq(_near(r[2], c.pos), 1, "one pool under him")
	var col: Color = (r[2] as LightView).lights[0][2]
	assert_true(col.b > col.g, "violet, from his surge_aura colours: " + str(col))
	_free(r)


func test_a_hidden_fighter_gives_no_light() -> void:
	var r := _setup("cerebro", "hissy")
	var sim: MatchSim = r[0]
	var foe: CreatureSim = sim.creatures[1]
	foe.energy = CreatureSim.MAX_ENERGY
	(r[1] as FxView).unseen = [false, true]  # in the brush, or Tiptoe-invisible
	(r[2] as LightView).advance()
	assert_eq(_near(r[2], foe.pos, 80.0), 0, "a hidden foe's Surge doesn't glow through")
	# Her Stone Gaze (fx.light) doesn't either.
	foe.energy = 0.0
	sim.creatures[0].pos = foe.pos + Vector2(200, 0)
	for i in 30:
		run(sim, 0, 1, SimDefs.IN_SKILL2 if i < 2 else 0)
		(r[1] as FxView).advance()
		(r[2] as LightView).advance()
		assert_eq(_near(r[2], foe.pos, 80.0), 0, "no gaze light from a hidden foe (tick %d)" % i)
	_free(r)


func test_an_invisible_or_burrowed_fighter_gives_no_light() -> void:
	var r := _setup("pete", "digby")
	for c in (r[0] as MatchSim).creatures:
		c.energy = CreatureSim.MAX_ENERGY
		c.stealth = 60  # Tiptoe; Burrow sets the same
	(r[2] as LightView).advance()
	assert_eq((r[2] as LightView).lights.size(), 0, "no Surge pool gives them away")
	_free(r)


func test_stone_gaze_lights_ahead_of_her_while_seen() -> void:
	var r := _setup("hissy", "cairn")
	var sim: MatchSim = r[0]
	var h: CreatureSim = sim.creatures[0]
	sim.creatures[1].pos = h.pos + Vector2(300, 0)
	var lit := 0
	for i in 30:
		run(sim, SimDefs.IN_SKILL2 if i < 2 else 0, 1)
		(r[1] as FxView).advance()
		(r[2] as LightView).advance()
		lit += _near(r[2], h.pos, 60.0)
	assert_gt(lit, 0, "her gaze glows")
	_free(r)


func test_every_light_key_is_well_formed() -> void:
	for path in DirAccess.get_files_at("res://data/creatures"):
		var def: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures/" + path))
		for mid in def.get("moves", {}):
			var fx: Dictionary = def["moves"][mid].get("fx", {})
			for key in ["light", "projectile_light"]:
				if fx.has(key):
					var li: Dictionary = fx[key]
					assert_true(Color.html_is_valid(String(li.get("color", "#fff"))), "%s %s colour" % [path, mid])
					assert_true(float(li.get("radius", 24)) > 0.0 and float(li.get("radius", 24)) <= 96.0,
						"%s %s radius within the pool sizes" % [path, mid])
			if fx.has("projectile_light"):
				assert_true(def["moves"][mid].has("projectile"), "%s %s throws something to light" % [path, mid])
