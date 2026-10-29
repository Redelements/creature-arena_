extends TestCase
## Capture the Flag's carry slow (Oct 2026): a carrier walks at `carry_slow` (0.8) of its
## speed, the same for every fighter (no class carries light); it stacks multiplicatively
## with a real slow and a haste instead of replacing them; dashes keep their own pace; and
## it's gone the very tick the flag drops, is passed or is captured.

const TEAMS := [["pete", "cairn"], ["culvert", "digby"]]


func _ctf(size := 1) -> TeamSim:
	var t := TeamSim.new(TEAMS, size, TeamSim.load_rules(TeamSim.CTF_PATH))
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _idle(t: TeamSim, ticks: int) -> void:
	for i in ticks:
		t.step(PackedInt32Array())
		for c in t.sim.creatures:
			c.walk_vel = Vector2.ZERO


## Pete (slot 0) picks blue's flag up and stands in the middle of the map.
func _carrying(size := 1) -> TeamSim:
	var t := _ctf(size)
	var pete := t.sim.creatures[0]
	pete.pos = t.base_of(1)
	_idle(t, 2)
	assert_eq(int(t.flag_carrier[1]), pete.id, "Pete carries blue's flag")
	pete.pos = t.sim.terrain.nearest_solid(t.sim.floor_rect().get_center())
	_idle(t, 1)
	return t


func test_a_carrier_walks_at_80_percent_whoever_it_is() -> void:
	assert_near(float(TeamSim.load_rules(TeamSim.CTF_PATH)["carry_slow"]), 0.8, 0.001, "the rule:")
	var t := _carrying()
	var pete := t.sim.creatures[0]
	var base := float(pete.def["speed"])
	assert_near(pete.carry_mult, 0.8, 0.001, "the carry multiplier:")
	assert_near(pete.walk_speed(), base * 0.8, 0.001, "Pete's walk while carrying:")
	assert_near(t.sim.creatures[1].carry_mult, 1.0, 0.001, "nobody else is slowed:")
	assert_false(t.rules["class_perks"].has("assassin"), "no class perk lightens the carry")


func test_the_carry_slow_stacks_with_a_slow_and_a_haste() -> void:
	var t := _carrying()
	var pete := t.sim.creatures[0]
	var base := float(pete.def["speed"])
	pete.slow = 30
	pete.slow_mult = 0.5
	assert_near(pete.walk_speed(), base * 0.5 * 0.8, 0.001, "a real slow on a carrier multiplies in:")
	_idle(t, 1)
	assert_near(pete.walk_speed(), base * 0.5 * 0.8, 0.001, "and the next tick neither replaces the other:")
	pete.haste = 30
	pete.haste_mult = 1.35
	assert_near(pete.walk_speed(), base * 0.5 * 0.8 * 1.35, 0.001, "a haste (Tiptoe's) multiplies in too:")
	pete.slow = 0
	assert_near(pete.walk_speed(), base * 0.8 * 1.35, 0.001, "slow gone, haste and carry remain:")


func test_dashes_keep_their_own_pace() -> void:
	var t := _carrying()
	var pete := t.sim.creatures[0]
	var dash: Dictionary = pete.def["moves"]["skill_2"]["dash"]  # Pickpocket
	var carried := pete._dash_speed(dash, t.sim)
	pete.carry_mult = 1.0
	assert_near(carried, pete._dash_speed(dash, t.sim), 0.001, "a dash is as fast with the flag as without:")


func test_the_slow_clears_the_tick_the_flag_is_captured() -> void:
	var t := _carrying()
	var pete := t.sim.creatures[0]
	pete.pos = t.base_of(0)
	t.step(PackedInt32Array())
	assert_eq(int(t.score[0]), 1, "captured:")
	assert_near(pete.carry_mult, 1.0, 0.001, "full speed on that very tick:")
	assert_near(pete.walk_speed(), float(pete.def["speed"]), 0.001, "the walk is back to normal:")


func test_the_slow_clears_the_tick_the_flag_drops() -> void:
	var t := _carrying()
	var pete := t.sim.creatures[0]
	pete.hp = 0.0
	pete.state = CreatureSim.State.KO
	t.step(PackedInt32Array())
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_DROPPED, "dropped:")
	assert_near(pete.carry_mult, 1.0, 0.001, "no lingering slow:")


func test_the_slow_clears_the_tick_the_flag_is_passed() -> void:
	var t := _carrying(2)
	var pete := t.sim.creatures[0]
	var cairn := t.sim.creatures[2]
	pete.facing = Vector2.RIGHT
	cairn.pos = pete.pos + Vector2(80, 0)
	_idle(t, 1)
	assert_near(pete.carry_mult, 0.8, 0.001, "slowed while holding it:")
	var ins := PackedInt32Array()
	ins.resize(t.slot_count())
	ins[0] = SimDefs.IN_TAG
	t.step(ins)
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_THROWN, "a fresh TAG passes it:")
	assert_near(pete.carry_mult, 1.0, 0.001, "and the thrower is at full speed at once:")
	assert_near(pete.walk_speed(), float(pete.def["speed"]), 0.001, "the walk too:")
