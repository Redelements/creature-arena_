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
	var r := _view("stadium", Sight.new())
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
