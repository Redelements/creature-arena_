extends TestCase
## Stamina rules (data/rules/stamina.json): the dearer dodge, blocked hits draining by
## move type, the regen pause after a block, exhaustion at 0 (no guard, a held guard
## drops and the hit lands clean, a longer regen delay), and the CPU playing by them.

const L := SimDefs.IN_LIGHT
const D := SimDefs.IN_DODGE
const G := SimDefs.IN_GUARD
const RIGHT := SimDefs.IN_RIGHT

var _log: Array = []  ## every event since the test's match started (sim.events is per tick)


## Culvert just left of the dummy, in jab reach, facing each other.
func _close() -> MatchSim:
	_log = []
	var sim := MatchFactory.training()
	sim.creatures[0].pos = Vector2(280, 164)
	sim.creatures[1].pos = Vector2(304, 164)
	return sim


func _step(sim: MatchSim, p0: int, p1: int) -> void:
	sim.step(PackedInt32Array([p0, p1]))
	_log.append_array(sim.events)


func _go(sim: MatchSim, p0: int, ticks: int, p1 := 0) -> void:
	for i in ticks:
		_step(sim, p0, p1)


func _until(sim: MatchSim, cond: Callable, limit: int, p0 := 0, p1 := 0) -> bool:
	for i in limit:
		_step(sim, p0, p1)
		if cond.call():
			return true
	return false


func _seen(kind: String) -> Array:
	return _log.filter(func(e): return e["type"] == kind)


## Steps until stamina grows again; returns the ticks that took (or -1).
func _ticks_until_regen(sim: MatchSim, c: CreatureSim, limit: int) -> int:
	for i in limit:
		var before := c.stamina
		_step(sim, 0, 0)
		if c.stamina > before:
			return i
	return -1


func test_the_numbers_live_in_one_rules_file() -> void:
	var r := CreatureSim.stamina_rules()
	for k in ["dodge_cost_mult", "block_drain_mult", "block_regen_pause_seconds", "exhaust_delay_seconds"]:
		assert_true(r.has(k), "stamina.json has %s" % k)
	var m: Dictionary = r["block_drain_mult"]
	assert_lt(float(m["light"]), float(m["heavy"]), "a light drains less than a heavy:")


func test_every_dodge_costs_the_multiplier_more_capped_at_the_bar() -> void:
	var mult := float(CreatureSim.stamina_rules()["dodge_cost_mult"])
	for id in MatchFactory.FIGHTERS:
		var c := MatchFactory.training(id).creatures[0]
		var want := minf(c.max_stamina, float(c.def["dodge"]["cost"]) * mult)
		assert_near(c.dodge_cost, want, 0.001, "%s's dodge cost:" % id)


func test_a_dodge_spends_the_new_cost() -> void:
	var sim := _close()
	var p := sim.creatures[0]
	_go(sim, D | RIGHT, 1)
	assert_near(p.stamina, p.max_stamina - p.dodge_cost, 0.001, "spent:")


func test_a_blocked_light_drains_less_than_a_blocked_heavy_per_damage() -> void:
	var sim := _close()
	var d := sim.creatures[1]
	assert_lt(MatchSim.block_drain(d, "light", 10.0), MatchSim.block_drain(d, "heavy", 10.0),
		"same damage, a light drains less:")
	_go(sim, 0, 1, G)
	_go(sim, L, 1, G)
	_go(sim, 0, 30, G)
	assert_eq(_seen("block").size(), 1, "the light was blocked")
	assert_near(d.stamina, d.max_stamina - MatchSim.block_drain(d, "light", 4.0), 0.001, "drain:")
	assert_lt(d.hp, d.max_hp, "chip damage still goes through")


func test_no_guard_at_zero_stamina() -> void:
	var sim := _close()
	var d := sim.creatures[1]
	d.spend_stamina(d.stamina)
	assert_true(d.is_exhausted(), "exhausted at 0")
	_go(sim, 0, 10, G)
	assert_true(d.state != CreatureSim.State.GUARD, "holding guard does nothing while exhausted")
	_go(sim, L, 1, G)
	_go(sim, 0, 30, G)
	assert_eq(_seen("block").size(), 0, "so the jab isn't blocked")
	assert_eq(_seen("hit").size(), 1, "it lands clean")


func test_the_hit_that_empties_a_guard_drops_it_and_lands_clean_without_a_stagger() -> void:
	var sim := _close()
	var d := sim.creatures[1]
	_go(sim, 0, 1, G)
	d.stamina = 1.0
	_go(sim, L, 1, G)
	var hit := _until(sim, func(): return d.hp < d.max_hp, 30, 0, G)
	assert_true(hit, "the jab connects")
	assert_near(d.hp, d.max_hp - 4.0, 0.001, "full damage, not chip:")
	assert_eq(d.stamina, 0.0, "stamina empty")
	var brk := _seen("guard_break")
	assert_eq(brk.size(), 1, "the drop is shown")
	if brk.size() == 1:
		assert_true(bool(brk[0].get("drained", false)), "as drained, not a guard-breaker")
	assert_eq(_seen("block").size(), 0, "not counted as a block")
	# The same reaction an unguarded jab gets: nothing extra (no guard-break crumple).
	var ctl := _close()
	var cd := ctl.creatures[1]
	_go(ctl, L, 1)
	_until(ctl, func(): return cd.hp < cd.max_hp, 30)
	assert_eq(d.state, cd.state, "the jab's own reaction, no crumple:")
	assert_eq(d.stun, cd.stun, "and no extra stun:")


func test_a_blocked_hit_pauses_regen_and_each_new_block_restarts_it() -> void:
	var pause := CreatureSim.stamina_ticks("block_regen_pause_seconds", 0.5)
	var sim := _close()
	var d := sim.creatures[1]
	_go(sim, 0, 1, G)
	_go(sim, L, 1, G)
	_until(sim, func(): return not _seen("block").is_empty(), 30, 0, G)
	assert_eq(_seen("block").size(), 1, "blocked")
	assert_eq(d.regen_wait, pause, "the pause starts on the block:")
	_go(sim, 0, 10, G)
	d.pause_regen_for_block()  # as a second blocked hit does
	assert_eq(d.regen_wait, pause, "and restarts on the next one:")
	var waited := _ticks_until_regen(sim, d, pause + 60)
	assert_true(waited >= pause - 1, "no regen for the pause (%d ticks waited)" % waited)


func test_exhaustion_delays_regen_longer_and_a_block_pause_does_not_stack_on_it() -> void:
	var delay := CreatureSim.stamina_ticks("exhaust_delay_seconds", 2.0)
	assert_gt(delay, CreatureSim.stamina_ticks("block_regen_pause_seconds", 0.5), "longer than the block pause:")
	var sim := _close()
	var p := sim.creatures[0]
	p.stamina = p.dodge_cost - float(p.def["stamina_regen"])  # (regen ticks before the dodge spends)
	_go(sim, D | RIGHT, 1)
	assert_eq(p.stamina, 0.0, "the dodge emptied it")
	assert_eq(p.regen_wait, delay, "the exhaustion delay:")
	p.pause_regen_for_block()
	assert_eq(p.regen_wait, delay, "a block pause neither adds to it nor cuts it short:")
	var waited := _ticks_until_regen(sim, p, delay + 60)
	assert_true(waited >= delay - 1, "no regen for the delay (%d ticks waited)" % waited)
	assert_true(p.can_guard(), "regen back: it can guard again")


func test_regen_wait_survives_a_rollback() -> void:
	var sim := _close()
	var p := sim.creatures[0]
	p.spend_stamina(p.stamina)
	var snap := sim.snapshot()
	_go(sim, 0, 50)
	sim.restore(snap)
	assert_eq(p.regen_wait, CreatureSim.stamina_ticks("exhaust_delay_seconds", 2.0), "restored:")


func test_an_exhausted_cpu_never_holds_guard() -> void:
	for level in [1, CpuController.RAGE]:
		var sim := _close()
		var cpu := CpuController.new(1, level, 7)
		var me := sim.creatures[1]
		var held := 0
		for i in 240:
			me.stamina = 0.0
			me.regen_wait = 999
			var b := cpu.bits(sim)
			if b & G:
				held += 1
			_step(sim, L if i % 20 == 0 else 0, b)
		assert_eq(held, 0, "level %d: no guard pressed while exhausted:" % level)


func test_the_rage_cpu_does_not_block_a_hit_that_would_empty_its_guard() -> void:
	var sim := _close()
	var cpu := CpuController.new(1, CpuController.RAGE, 3)
	var me := sim.creatures[1]
	var foe := sim.creatures[0]
	var guarded := 0
	for i in 300:
		if me.stamina > 2.0:
			me.stamina = 2.0  # any blocked strike empties it
		var b := cpu.bits(sim)
		if (b & G) and foe.state == CreatureSim.State.ATTACK:
			guarded += 1
		_step(sim, L if i % 24 == 0 else 0, b)
	assert_eq(guarded, 0, "it steps or dodges instead:")


func test_the_rage_cpu_wears_down_a_low_guard() -> void:
	# Cairn: no grab or guard-breaker, so wearing the guard down is all he has.
	_log = []
	var sim := MatchFactory.training("cairn")
	sim.creatures[0].pos = Vector2(280, 164)
	sim.creatures[1].pos = Vector2(304, 164)
	var cpu := CpuController.new(0, CpuController.RAGE, 5)
	var d := sim.creatures[1]
	_go(sim, 0, 1, G)
	d.stamina = d.max_stamina * 0.4
	var start := d.stamina
	for i in 240:
		_step(sim, cpu.bits(sim), G)
		if d.is_exhausted():
			break
	assert_false(_seen("block").is_empty(), "it attacked the guard instead of waiting")
	assert_lt(d.stamina, start, "and blocked hits wore it down")
