extends TestCase
## The guard turns to the nearest foe it can see (MatchSim.nearest_seen): a stealthed foe
## (Tiptoe, a hidden Burrow) doesn't pull it round, so one that walks behind a guard lands a
## clean hit (hits from behind are clean). A foe in brush is hidden by the ground, not by a
## skill, and is still faced. Kevin's ruling R1 (Oct 28): don't guard toward what you can't see.

const L := SimDefs.IN_LIGHT
const G := SimDefs.IN_GUARD
const S1 := SimDefs.IN_SKILL1


## Pete on the left, Cairn on the right holding guard toward him.
func _duel() -> MatchSim:
	var sim := MatchFactory.versus("pete", "cairn")
	sim.creatures[0].pos = Vector2(200, 164)
	sim.creatures[1].pos = Vector2(280, 164)
	run(sim, 0, 6, G)
	assert_eq(sim.creatures[1].state, CreatureSim.State.GUARD, "Cairn guards")
	assert_gt(sim.creatures[1].facing.dot(Vector2.LEFT), 0.99, "facing Pete on the left")
	return sim


## Puts Pete just behind Cairn (to his right), facing him.
func _behind(sim: MatchSim) -> void:
	var pete := sim.creatures[0]
	var cairn := sim.creatures[1]
	pete.pos = cairn.pos + Vector2(pete.radius + cairn.radius + 4, 0)
	pete.facing = Vector2.LEFT


func _events(sim: MatchSim, kind: String, ticks: int, p0: int, p1: int) -> int:
	var n := 0
	for i in ticks:
		sim.step(PackedInt32Array([p0, p1]))
		for e in sim.events:
			if String(e["type"]) == kind:
				n += 1
	return n


func test_a_tiptoed_pete_behind_a_guard_lands_clean() -> void:
	var sim := _duel()
	var pete := sim.creatures[0]
	var cairn := sim.creatures[1]
	tap(sim, S1, 30, G)  # Tiptoe, with Cairn still guarding
	assert_gt(pete.stealth, 0, "Pete is in stealth")
	_behind(sim)  # he slipped round behind
	run(sim, 0, 4, G)
	assert_gt(cairn.facing.dot(Vector2.LEFT), 0.99, "the guard keeps the way it faced:")
	var aim := SimDefs.aim_bits(Vector2.LEFT) | L
	var hits := _events(sim, "hit", 1, aim, G) + _events(sim, "hit", 20, 0, G)
	assert_eq(hits, 1, "the jab from behind lands clean:")


func test_a_visible_foe_behind_is_faced() -> void:
	var sim := _duel()
	_behind(sim)
	run(sim, 0, 1, G)
	assert_gt(sim.creatures[1].facing.dot(Vector2.RIGHT), 0.99, "the guard turns to a foe it can see:")
	var aim := SimDefs.aim_bits(Vector2.LEFT) | L
	var blocks := _events(sim, "block", 1, aim, G) + _events(sim, "block", 20, 0, G)
	assert_eq(blocks, 1, "and blocks him:")


func test_a_foe_in_brush_is_still_faced() -> void:
	var sim := _duel()
	var pete := sim.creatures[0]
	_behind(sim)
	pete.covered = true  # in brush: hidden by the ground, not by a skill
	run(sim, 0, 1, G)
	assert_gt(sim.creatures[1].facing.dot(Vector2.RIGHT), 0.99, "a covered foe is still faced:")


func test_the_guard_turns_the_tick_after_stealth_ends() -> void:
	var sim := _duel()
	var pete := sim.creatures[0]
	var cairn := sim.creatures[1]
	pete.stealth = 100
	_behind(sim)
	run(sim, 0, 3, G)
	assert_gt(cairn.facing.dot(Vector2.LEFT), 0.99, "hidden: not faced")
	pete.stealth = 1  # runs out during Pete's next step
	run(sim, 0, 1, G)
	assert_eq(pete.stealth, 0, "stealth over")
	assert_gt(cairn.facing.dot(Vector2.LEFT), 0.99, "the guard read the tick's start, when he was hidden")
	run(sim, 0, 1, G)
	assert_gt(cairn.facing.dot(Vector2.RIGHT), 0.99, "the next tick it turns to him:")


func test_the_guard_turns_the_tick_after_a_hit_reveals() -> void:
	var sim := _duel()
	var pete := sim.creatures[0]
	var cairn := sim.creatures[1]
	pete.stealth = 100
	_behind(sim)
	run(sim, 0, 3, G)
	pete.stealth = 0  # caught (a hit's reveal sets it to 0 in _apply_hit, after the steps)
	run(sim, 0, 1, G)
	assert_gt(cairn.facing.dot(Vector2.RIGHT), 0.99, "revealed: faced on the next tick")


## With a visible foe far off and a stealthed one close, the guard faces the one it can see.
func test_a_far_visible_foe_beats_a_near_stealthed_one() -> void:
	var sim := _duel()
	var pete := sim.creatures[0]
	var cairn := sim.creatures[1]
	var digby := sim.add_creature(MatchFactory.load_def("digby"), Vector2(280, 300))
	digby.team = pete.team
	pete.stealth = 100
	_behind(sim)
	run(sim, 0, 1, G)
	assert_gt(cairn.facing.dot(Vector2.DOWN), 0.99, "faces Digby, far below, not hidden Pete:")
	pete.stealth = 0
	run(sim, 0, 1, G)
	assert_gt(cairn.facing.dot(Vector2.RIGHT), 0.99, "Pete in sight and nearer: faced")


func test_a_burrowed_digby_behind_a_guard_is_not_faced() -> void:
	var sim := MatchFactory.versus("digby", "cairn")
	var digby := sim.creatures[0]
	var cairn := sim.creatures[1]
	digby.pos = Vector2(200, 164)
	cairn.pos = Vector2(280, 164)
	run(sim, 0, 6, G)
	digby.stealth = 100  # a hidden Burrow
	digby.pos = cairn.pos + Vector2(digby.radius + cairn.radius + 4, 0)
	run(sim, 0, 2, G)
	assert_gt(cairn.facing.dot(Vector2.LEFT), 0.99, "the guard doesn't track a hidden Digby:")


func test_rollback_replays_the_guard_exactly() -> void:
	var sim := _duel()
	sim.creatures[0].stealth = 40
	_behind(sim)
	var snap := sim.snapshot()
	var aim := SimDefs.aim_bits(Vector2.LEFT) | L
	for i in 60:
		sim.step(PackedInt32Array([aim if i == 30 else 0, G]))
	var end := sim.state_digest()
	sim.restore(snap)
	for i in 60:
		sim.step(PackedInt32Array([aim if i == 30 else 0, G]))
	assert_eq(sim.state_digest(), end, "same guard facing after a restore:")
