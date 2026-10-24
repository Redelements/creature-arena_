extends TestCase
## AmbientView (a map's "ambient" block): maps without the key draw nothing, the Greenhouse's
## pieces build from data, and above all nothing here gives away a fighter the local team
## can't see (brush hides one): a hidden fighter in the brush doesn't rustle it, flick
## leaves or scare a butterfly; a seen one does.


class Sight:
	extends RefCounted
	var hidden := {}

	func shown(c: CreatureSim) -> bool:
		return not hidden.has(c.id)


func _view(arena: String, sight: Sight) -> Array:
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.set_arena(arena)
	var v := AmbientView.new()
	v.fx = sight
	v.set_sim(sim)
	return [sim, v]


func _walk(sim: MatchSim, v: AmbientView, c: CreatureSim, ticks: int) -> void:
	var p := sim.terrain.cell_center(Vector2i(41, 17))
	for i in ticks:
		c.pos = p + Vector2(float(i % 6) * 1.5, 0)
		run(sim, 0, 1)
		v.advance()


func test_a_map_without_the_key_draws_nothing() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.set_arena("stadium")
	sim.arena = sim.arena.duplicate()
	sim.arena.erase("ambient")
	var v := AmbientView.new()
	v.set_sim(sim)
	var r := [sim, v]
	assert_false((r[1] as AmbientView).visible, "no ambient block, nothing drawn")
	assert_eq((r[1] as AmbientView).fly_count(), 0)
	(r[1] as AmbientView).free()


func test_greenhouse_builds_its_life_from_data() -> void:
	var r := _view("greenhouse", Sight.new())
	var v: AmbientView = r[1]
	assert_true(v.visible)
	assert_eq(v.fly_count(), 3, "three butterflies")
	v.free()


func test_a_seen_fighter_rustles_the_brush() -> void:
	var r := _view("greenhouse", Sight.new())
	var sim: MatchSim = r[0]
	var v: AmbientView = r[1]
	sim.creatures[1].pos = sim.terrain.cell_center(Vector2i(20, 20))
	_walk(sim, v, sim.creatures[0], 40)
	assert_gt(v.stirred_cells(), 0, "wading through brush stirs it")
	assert_gt(v.leaf_count(), 0, "and flicks leaves")
	v.free()


func test_a_hidden_fighter_does_not_rustle_the_brush() -> void:
	var sight := Sight.new()
	var r := _view("greenhouse", sight)
	var sim: MatchSim = r[0]
	var v: AmbientView = r[1]
	sim.creatures[1].pos = sim.terrain.cell_center(Vector2i(20, 20))
	sight.hidden[0] = true  # the local team can't see fighter 0
	_walk(sim, v, sim.creatures[0], 60)
	assert_eq(v.stirred_cells(), 0, "no rustle for a foe in hiding")
	assert_eq(v.leaf_count(), 0, "no flying leaves")
	v.free()


func test_butterflies_flee_only_from_fighters_the_team_sees() -> void:
	var sight := Sight.new()
	var r := _view("greenhouse", sight)
	var sim: MatchSim = r[0]
	var v: AmbientView = r[1]
	var foe := sim.creatures[1]
	sim.creatures[0].pos = sim.terrain.cell_center(Vector2i(2, 2))
	sight.hidden[1] = true
	var fly: Dictionary = v._flies[0]
	foe.pos = fly["p"]
	run(sim, 0, 1)
	v.advance()
	assert_eq(v.scared_flies(), 0, "a hidden foe beside a butterfly changes nothing")
	sight.hidden.clear()
	foe.pos = fly["p"]
	run(sim, 0, 1)
	v.advance()
	assert_gt(v.scared_flies(), 0, "a seen fighter scares it off")
	v.free()


# ------------------------------------------------------------------ the other maps

func _tick(sim: MatchSim, v: AmbientView, n: int) -> void:
	for i in n:
		run(sim, 0, 1)
		v.advance()


func test_every_map_has_life_built_from_data() -> void:
	for id in ["stadium", "quarry", "floodgate", "twin_keeps", "caravan_pass"]:
		var r := _view(id, Sight.new())
		assert_true((r[1] as AmbientView).visible, "%s has an ambient block" % id)
		(r[1] as AmbientView).free()
	var q: AmbientView = _view("quarry", Sight.new())[1]
	assert_eq(q.mote_count(), 38, "quarry: dust in the low sun")
	q.free()
	var f: AmbientView = _view("floodgate", Sight.new())[1]
	assert_eq(f.mote_count(), 34, "floodgate: mist")
	assert_eq(f.fly_count(), 3, "floodgate: three dragonflies")
	f.free()
	var c: AmbientView = _view("caravan_pass", Sight.new())[1]
	assert_eq(c.mote_count(), 46, "caravan: blown sand")
	c.free()


func test_quarry_sheds_grit_and_raises_a_dust_devil() -> void:
	var r := _view("quarry", Sight.new())
	var sim: MatchSim = r[0]
	var v: AmbientView = r[1]
	var grit := 0
	var devil := false
	for i in 700:
		_tick(sim, v, 1)
		grit = maxi(grit, v.grit_count())
		devil = devil or v.devil_active()
	assert_gt(grit, 0, "grit trickles off the rubble walls")
	assert_true(devil, "a dust devil wanders through")
	v.free()


func test_confetti_falls_after_a_ko_and_a_surge_and_is_capped() -> void:
	var r := _view("stadium", Sight.new())
	var sim: MatchSim = r[0]
	var v: AmbientView = r[1]
	_tick(sim, v, 3)
	assert_eq(v.scrap_count(), 0, "nothing falls in a quiet moment")
	run(sim, 0, 1)
	sim.events.append({"type": "ko", "pos": Vector2(100, 100)})
	v.advance()
	var after_ko := v.scrap_count()
	assert_gt(after_ko, 0, "a knockout rains paper")
	for i in 5:
		run(sim, 0, 1)
		sim.events.append({"type": "surge"})
		v.advance()
	assert_true(v.scrap_count() <= AmbientView.CONFETTI_CAP, "capped")
	_tick(sim, v, 1600)
	assert_eq(v.scrap_count(), 0, "every scrap lands and fades")
	v.free()


func test_birds_cross_the_arena() -> void:
	var r := _view("stadium", Sight.new())
	var sim: MatchSim = r[0]
	var v: AmbientView = r[1]
	v.spawn_flock()
	assert_eq(v.bird_count(), 3, "a flock of three")
	_tick(sim, v, 60)
	assert_eq(v.bird_count(), 3)
	v.free()


func test_fish_jump_only_in_open_water_and_never_beside_a_seen_fighter() -> void:
	var sight := Sight.new()
	var r := _view("floodgate", sight)
	var sim: MatchSim = r[0]
	var v: AmbientView = r[1]
	var cell := 17 * sim.terrain.cols + 41  # the middle of the channel
	var rock := 2 * sim.terrain.cols + 5  # dry floor
	sim.creatures[1].pos = sim.terrain.cell_center(Vector2i(2, 2))
	assert_false(v.try_jump(rock), "no fish on dry land")
	sim.creatures[0].pos = sim.terrain.cell_center(Vector2i(41, 17))
	assert_false(v.try_jump(cell), "not beside a fighter the team sees")
	sight.hidden[0] = true
	assert_true(v.try_jump(cell), "a hidden fighter changes nothing: the fish jumps anyway")
	assert_eq(v.fish_count(), 1)
	_tick(sim, v, 40)
	assert_eq(v.fish_count(), 0, "and lands")
	v.free()


func test_dragonflies_flee_only_from_fighters_the_team_sees() -> void:
	var sight := Sight.new()
	var r := _view("floodgate", sight)
	var sim: MatchSim = r[0]
	var v: AmbientView = r[1]
	var foe := sim.creatures[1]
	sim.creatures[0].pos = sim.terrain.cell_center(Vector2i(2, 2))
	sight.hidden[1] = true
	var fly: Dictionary = v._flies[0]
	foe.pos = fly["p"]
	_tick(sim, v, 1)
	assert_eq(v.scared_flies(), 0, "a hidden foe beside a dragonfly changes nothing")
	sight.hidden.clear()
	foe.pos = fly["p"]
	_tick(sim, v, 1)
	assert_gt(v.scared_flies(), 0, "a seen fighter scares it off")
	v.free()


func test_twin_keeps_and_caravan_stir_their_brush_for_seen_fighters_only() -> void:
	for id in ["twin_keeps", "caravan_pass"]:
		var sight := Sight.new()
		var r := _view(id, sight)
		var sim: MatchSim = r[0]
		var v: AmbientView = r[1]
		var bed: Rect2 = v._beds[0]
		var at := bed.get_center()
		sim.creatures[1].pos = Vector2(40, 40)
		sight.hidden[0] = true
		for i in 40:
			sim.creatures[0].pos = at + Vector2(float(i % 6), 0)
			_tick(sim, v, 1)
		assert_eq(v.stirred_cells(), 0, "%s: no rustle for a foe in hiding" % id)
		sight.hidden.clear()
		for i in 40:
			sim.creatures[0].pos = at + Vector2(float(i % 6), 0)
			_tick(sim, v, 1)
		assert_gt(v.stirred_cells(), 0, "%s: a seen fighter rustles it" % id)
		v.free()
