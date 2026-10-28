extends TestCase
## Barkley's plants on screen (PlantView): a node per plant standing among the fighters,
## the sprout's look, the tree's, the apple, gone with the plant; hidden from a foe who
## can't see the spot; the events' effects (FxView) play without errors.

func _setup() -> Array:
	var sim := MatchFactory.training("barkley")
	var fx := FxView.new()
	fx.sim = sim
	var pv := PlantView.new()
	pv.sim = sim
	pv.fx = fx
	return [sim, fx, pv]


func _seed(sim: MatchSim) -> Dictionary:
	var b := sim.creatures[0]
	Plants.plant(sim, b, b.pos + Vector2(30, 0), b.moves()["skill_2"]["projectile"]["seed"], 90)
	return sim.plants[sim.plants.size() - 1]


func _free(parts: Array) -> void:
	(parts[2] as PlantView).stand.free()
	(parts[2] as PlantView).free()
	(parts[1] as FxView).free()


func test_a_plant_gets_a_node_that_follows_its_stage() -> void:
	var parts := _setup()
	var sim: MatchSim = parts[0]
	var pv: PlantView = parts[2]
	var pl := _seed(sim)
	pv.advance()
	assert_eq(pv.stand.get_child_count(), 1, "a node for the sprout")
	assert_true(pv.stand.y_sort_enabled, "the plants sort with the fighters")
	var n: PlantView.Plant = pv.stand.get_child(0)
	assert_eq(int(n.key[0]), 0, "drawn as a sprout")
	assert_eq(n.position, ArtScale.snap(Vector2(pl["pos"]), 2), "standing on its spot")
	pl["hp"] = 4.0
	pv.advance()
	assert_true(bool(n.key[4]), "a struck sprout flashes")
	pl["stage"] = Plants.TREE
	pl["age"] = int(pl["grow"]) + 100
	pl["apple"] = true
	pv.advance()
	assert_eq(int(n.key[0]), 1, "drawn as a tree")
	assert_eq(float(n.key[3]), 1.0, "fully risen")
	assert_true(int(n.key[2]) >= 0, "with its apple")
	sim.plants.clear()
	pv.advance()
	assert_false(n.is_queued_for_deletion(), "a spent tree sinks back into the floor first")
	assert_true(float(n.key[3]) < 1.0, "lower than it stood")
	for i in PlantView.TREE_SINK:
		pv.advance()
	assert_true(n.is_queued_for_deletion(), "gone with the plant")
	_free(parts)


func test_events_play_effects() -> void:
	var parts := _setup()
	var sim: MatchSim = parts[0]
	var fx: FxView = parts[1]
	var pl := _seed(sim)
	var at: Vector2 = pl["pos"]
	var d := sim.creatures[1]
	for e in [
		{"type": "seed", "pos": at, "power": 10.0, "who": 0, "plant": 1},
		{"type": "plant_hit", "pos": at, "power": 5.0, "who": 0, "by": 1, "plant": 1, "hp": 5.0},
		{"type": "plant_grow", "pos": at, "power": 1.0, "who": 0, "plant": 1},
		{"type": "apple", "pos": at, "power": 1.0, "who": 0, "plant": 1},
		{"type": "apple_eaten", "pos": at, "power": 20.0, "who": 0, "by": 0, "plant": 1},
		{"type": "apple_spoiled", "pos": at, "power": 0.0, "who": 1, "plant": 1},
		{"type": "plant_gone", "pos": at, "power": 0.0, "who": 0, "plant": 1, "how": "killed", "by": 1},
	]:
		fx.spawn(e)
	assert_true(fx.move_fx.playing() >= 5, "the hand-drawn effects play")
	fx.spawn({"type": "rooted", "pos": d.pos, "power": 45.0, "who": d.id, "by": 0, "plant": 1})
	assert_true(bool(fx._leaf_root.get(d.id, false)), "a root from Barkley is a leafy one")
	fx.spawn({"type": "rooted", "pos": d.pos, "power": 45.0, "who": d.id, "by": -1})
	assert_false(bool(fx._leaf_root.get(d.id, true)), "anyone else's heaps rubble")
	_free(parts)
