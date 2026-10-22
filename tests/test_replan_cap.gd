extends TestCase
## The CPU's path searches on a crowded field take turns: one search a tick at most, each
## CPU's turn coming round every creatures.size() ticks (CpuController._replan_turn), so
## eight CPUs chasing a moving goal can't all run an A* in the same tick. With two on the
## field every tick is a turn, so a 1v1 plays exactly as before.


func _zero(n: int) -> PackedInt32Array:
	var ins := PackedInt32Array()
	ins.resize(n)
	return ins


func test_with_two_on_the_field_every_tick_is_a_turn() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var cpus := [CpuController.new(0, 2, 1), CpuController.new(1, 2, 2)]
	for t in 6:
		sim.step(_zero(2))
		for c in cpus:
			assert_true((c as CpuController)._replan_turn(sim), "tick %d, slot %d" % [sim.tick, c.me_idx])


func test_a_crowded_field_takes_turns_one_search_a_tick() -> void:
	var t := TeamSim.new([["cairn", "culvert", "sno", "pete"], ["cairn", "culvert", "sno", "pete"]], 4,
		TeamSim.load_rules(TeamSim.CTF_PATH))  # the CTF rules allow four a side
	var n := t.slot_count()
	assert_eq(n, 8, "a 4v4:")
	var cpus: Array = []
	for i in n:
		cpus.append(CpuController.new(i, 2, i))
	var turns := {}
	for tick in 2 * n:
		t.step(_zero(n))
		var whose := -1
		for c in cpus:
			if (c as CpuController)._replan_turn(t.sim):
				assert_eq(whose, -1, "two CPUs on one tick (%d and %d)" % [whose, c.me_idx])
				whose = c.me_idx
		assert_true(whose >= 0, "someone's turn each tick")
		turns[whose] = int(turns.get(whose, 0)) + 1
	for i in n:
		assert_eq(int(turns.get(i, 0)), 2, "slot %d's turns in %d ticks:" % [i, 2 * n])


func test_a_cpu_off_its_turn_still_moves_toward_its_goal() -> void:
	# No path yet and not its turn: it walks straight at the goal rather than standing.
	var t := TeamSim.new([["cairn", "culvert", "sno", "pete"], ["cairn", "culvert", "sno", "pete"]], 4)
	var zero := _zero(t.slot_count())
	while t.phase == TeamSim.Phase.INTRO:
		t.step(zero)
	var cpu := CpuController.new(0, 2, 7)
	var me := t.sim.creatures[0]
	var goal := me.pos + Vector2(120, 0)
	var moved := false
	for tick in 8:
		if cpu._replan_turn(t.sim):
			t.step(zero)
			continue
		cpu._out = 0
		cpu._go_to(t.sim, me, goal)
		if cpu._out & (SimDefs.IN_RIGHT | SimDefs.IN_MOVE):
			moved = true
		t.step(zero)
	assert_true(moved, "it pressed toward the goal on a tick that wasn't its turn")
