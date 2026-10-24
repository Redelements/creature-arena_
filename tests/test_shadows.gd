extends TestCase
## Shadows cast along each arena's light: every map names its light, a fighter's shadow
## shrinks and fades as it goes up and is gone while it falls or is hidden, and a smashed
## wall or flattened brush takes its baked shadow with it (the floor round it shows the
## _alt picture once every piece shading it has changed).


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_every_arena_has_a_light_that_falls_down_the_screen() -> void:
	for id in ArenaMap.IDS + ArenaMap.MODE_IDS:
		var map := ArenaMap.get_map(id)
		assert_true(map.has("light"), "%s names its light" % id)
		var l := ShadowLayer.light_of(map)
		var cast: Vector2 = l["cast"]
		assert_near(cast.length(), float(map["light"]["length"]), 0.21, "%s: the cast is the dir at the length" % id)
		assert_gt(cast.y, ShadowLayer.MIN_FLAT - 0.001, "%s: shadows lie on the floor in front" % id)
		assert_gt(float(l["alpha"]), 0.0, "%s: a visible shadow" % id)
	var none := ShadowLayer.light_of({})
	assert_near(float(none["alpha"]), float(ShadowLayer.DEFAULT_LIGHT["alpha"]), 0.001, "no light: the default")


func test_a_launched_fighter_casts_a_smaller_fainter_shadow() -> void:
	var sim := MatchFactory.training("craglash")
	var v := CreatureView.new()
	v.setup(sim.creatures[0])
	var c := v.c
	v.refresh()
	assert_near(v.shadow_size, 1.0, 0.001, "on the floor: full size")
	assert_near(v.shadow_fade, 1.0, 0.001, "on the floor: full strength")
	var key := v.shadow_key()
	c.pos += Vector2(12, 5)
	v.refresh()
	assert_eq(v.shadow_key(), key, "walking only moves the shadow, it doesn't repaint it:")
	c.state = CreatureSim.State.AIRBORNE
	c.air_total = 40
	c.air_t = 20
	v.refresh()
	assert_gt(c.air_height(), 10.0, "up in the air")
	assert_true(v.shadow_size < 0.9, "the shadow shrinks (%.2f)" % v.shadow_size)
	assert_true(v.shadow_fade < 0.95, "and fades (%.2f)" % v.shadow_fade)
	c.state = CreatureSim.State.FALLING
	c.state_t = 5
	v.refresh()
	assert_eq(v.shadow_fade, 0.0, "falling into a pit: no shadow")
	c.state = CreatureSim.State.IDLE
	v.out_of_sight = true
	v.refresh()
	assert_false(v.visible, "a hidden foe isn't drawn, so the layer skips its shadow")
	v.free()


func test_a_smashed_wall_takes_its_shadow_with_it() -> void:
	var sim := MatchSim.new()
	sim.set_arena("quarry")
	var av := ArenaView.new()
	_root().add_child(av)
	av.arena_id = "quarry"
	av.set_terrain(sim.terrain)
	assert_true(av._art_alt != null, "the quarry has a changed-piece picture")
	assert_false(av._shade.is_empty(), "its walls shade the floor round them")
	# a floor cell in a wall's shadow, and the wall cells shading it
	var p: int = av._shade.keys()[av._shade.size() / 2]
	assert_false(av._unshaded(p), "with the wall standing, the floor keeps its shadow")
	for i: int in av._shade[p]:
		sim.terrain.smash(Vector2i(i % sim.terrain.cols, i / sim.terrain.cols))
	assert_true(av._unshaded(p), "every wall shading it smashed: the floor shows without the shadow")
	av.refresh()
	assert_true(av._pending.has((p / sim.terrain.cols) / ArenaView.BAND_ROWS), "its band repaints")
	av.free()
