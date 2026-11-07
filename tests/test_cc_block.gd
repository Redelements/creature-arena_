extends TestCase
## CC through guard (data/rules/stamina.json cc_through_guard, MatchSim._cc_through_guard):
## a blocked hit still lands its crowd control in full (a launch, a slow, a root, a stone, a
## stagger) while the guard keeps stopping the damage, a plain hit's hitstun and poison; the
## stamina drain stays what a block costs. Removing a kind from the list blocks it again.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const G := SimDefs.IN_GUARD

var _log: Array = []


## Two fighters facing each other, the right one guarding, a step apart.
func _duel(left := "cairn", right := "culvert", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	sim.creatures[0].facing = Vector2.RIGHT
	sim.creatures[1].facing = Vector2.LEFT
	return sim


## The right fighter in its guard (as the sim puts it there), facing the left one.
func _guarding(sim: MatchSim) -> CreatureSim:
	var d := sim.creatures[1]
	d._set_state(CreatureSim.State.GUARD)
	d.facing = Vector2.LEFT
	return d


## A synthetic hit (every key hit_params fills), for MatchSim._apply_hit directly.
func _hit(type: String, extra := {}) -> Dictionary:
	var h := {
		"attacker": 0, "move_id": "test", "type": type, "serial": 1,
		"damage": 10.0, "knockback": 1.0, "hitstun": 20.0, "hitstop": 0.0,
		"launch": 0.0, "crumple": 0.0, "knockdown": 0.0, "slow_ticks": 0.0, "slow_mult": 1.0,
		"poison_ticks": 0.0, "poison_damage": 0.0, "poison_every": 0.0, "petrify": 0.0,
		"freeze_ticks": 0.0, "blind_ticks": 0.0, "root_ticks": 0.0, "pull": 0.0,
		"guard_break": false, "grab": false, "juggle": false, "no_flinch": false, "stack_bonus": 0.0,
		"stagger_if": "",
	}
	h.merge(extra, true)
	return h


func _apply(sim: MatchSim, hit: Dictionary) -> String:
	var r := sim._apply_hit(sim.creatures[0], sim.creatures[1], hit, Vector2.RIGHT, sim.creatures[1].pos)
	_log.append_array(sim.events)
	return r


func _blocks() -> Array:
	return _log.filter(func(e): return String(e["type"]) == "block")


func test_a_blocked_launcher_launches_the_guard_with_no_health_lost() -> void:
	var sim := _duel()
	var d := _guarding(sim)
	var r := _apply(sim, _hit("heavy", {"launch": 30.0}))
	assert_eq(r, "block", "still a block:")
	assert_near(d.hp, d.max_hp, 0.001, "no health lost:")
	assert_near(d.stamina, d.max_stamina - MatchSim.block_drain(d, "heavy", 10.0), 0.001, "a block's drain:")
	assert_eq(d.state, CreatureSim.State.AIRBORNE, "launched out of the guard:")
	assert_eq(d.air_total, maxi(int(30.0 * d.air_mult), 1), "for the launch's full time:")
	assert_eq(d.energy, 0.0, "no meter for the blocker:")
	assert_eq(sim.creatures[0].energy, 0.0, "nor for the attacker:")
	var b := _blocks()
	assert_eq(b.size(), 1, "one block event")
	if b.size() == 1:
		assert_eq(b[0]["cc"], ["launch"], "naming the launch:")


func test_a_blocked_slow_applies_its_full_slow() -> void:
	var sim := _duel()
	var d := _guarding(sim)
	_apply(sim, _hit("light", {"slow_ticks": 60.0, "slow_mult": 0.8}))
	assert_eq(d.slow, 60, "the full slow_ticks:")
	assert_near(d.slow_mult, 0.8, 0.0001, "at its multiplier:")
	assert_eq(d.state, CreatureSim.State.GUARD, "a slow alone keeps the guard up:")
	assert_near(d.hp, d.max_hp, 0.001, "no health lost:")


func test_a_blocked_plain_light_stuns_no_more_than_the_guard_did() -> void:
	var sim := _duel()
	var d := _guarding(sim)
	_apply(sim, _hit("light"))
	assert_eq(d.state, CreatureSim.State.GUARD, "still guarding:")
	assert_eq(d.stun, 10, "the guard's own stun, hitstun x 0.5:")
	assert_eq(d.guard_hit, 10, "and its guard_hit:")
	assert_eq(d.slow, 0, "no slow")
	var b := _blocks()
	if b.size() == 1:
		assert_eq(b[0]["cc"], [], "no CC named:")


func test_poison_stays_blocked() -> void:
	var sim := _duel()
	var d := _guarding(sim)
	_apply(sim, _hit("skill", {"poison_ticks": 120.0, "poison_damage": 2.0}))
	assert_eq(d.poison, 0, "poison is damage over time, not CC:")
	assert_eq(d.state, CreatureSim.State.GUARD, "guard up:")


func test_blocked_knockdown_crumple_root_blind_and_freeze_land_in_full() -> void:
	var cases := [
		[{"knockdown": 40.0}, CreatureSim.State.KNOCKDOWN, "knockdown"],
		[{"crumple": 35.0}, CreatureSim.State.CRUMPLE, "crumple"],
		[{"freeze_ticks": 90.0}, CreatureSim.State.CRUMPLE, "freeze"],
		[{"petrify": 80.0}, CreatureSim.State.CRUMPLE, "petrify"],
		[{"root_ticks": 50.0}, CreatureSim.State.GUARD, "root"],
		[{"blind_ticks": 70.0}, CreatureSim.State.GUARD, "blind"],
	]
	for c in cases:
		_log = []
		var sim := _duel()
		var d := _guarding(sim)
		_apply(sim, _hit("skill", c[0]))
		assert_eq(d.state, c[1], "%s state:" % c[2])
		assert_near(d.hp, d.max_hp, 0.001, "%s takes no health:" % c[2])
		match String(c[2]):
			"knockdown": assert_eq(d.stun, 40, "full knockdown:")
			"crumple": assert_eq(d.stun, 35, "full crumple:")
			"freeze": assert_eq(d.stone, 90, "a full ice statue:")
			"petrify": assert_eq(d.stone, 80, "a full statue:")
			"root": assert_eq(d.root, 50, "a full root:")
			"blind": assert_eq(d.blind, 70, "a full blind:")


func test_a_stagger_if_pays_off_through_a_guard_but_a_plain_flick_does_not() -> void:
	var sim := _duel()
	var d := _guarding(sim)
	_apply(sim, _hit("light", {"no_flinch": true, "stagger_if": "tenderized", "launch": 20.0}))
	assert_eq(d.state, CreatureSim.State.GUARD, "no mark: a no_flinch hit doesn't move the guard:")
	var sim2 := _duel()
	var d2 := _guarding(sim2)
	d2.vuln = 60
	_apply(sim2, _hit("light", {"no_flinch": true, "stagger_if": "tenderized"}))
	assert_eq(d2.state, CreatureSim.State.HITSTUN, "tenderized: it staggers through the guard:")
	assert_eq(d2.stun, 20, "for the full hitstun:")


func test_a_kind_taken_out_of_the_rules_is_blocked_again() -> void:
	var rules := CreatureSim.stamina_rules()
	var had := rules.has("cc_through_guard")
	var old = rules.get("cc_through_guard")
	rules["cc_through_guard"] = ["slow"]
	var sim := _duel()
	var d := _guarding(sim)
	_apply(sim, _hit("heavy", {"launch": 30.0, "slow_ticks": 40.0, "slow_mult": 0.5}))
	if had:
		rules["cc_through_guard"] = old
	else:
		rules.erase("cc_through_guard")
	assert_eq(d.state, CreatureSim.State.GUARD, "launch left out: blocked:")
	assert_eq(d.slow, 40, "slow kept in: it lands:")


func test_a_blocked_fixed_stun_lands_in_full() -> void:
	# The thrown Tenderize's 3 s stun (stun_ticks) is crowd control: a guard still eats it.
	var sim := _duel()
	var d := _guarding(sim)
	var r := _apply(sim, _hit("heavy", {"stun_ticks": 180.0}))
	assert_eq(r, "block", "still a block:")
	assert_near(d.hp, d.max_hp, 0.001, "no health lost:")
	assert_eq(d.state, CreatureSim.State.CRUMPLE, "crumpled out of the guard:")
	assert_eq(d.stun_lock, 180, "locked for the full stun:")
	assert_true(d.stun >= 180, "helpless for all of it:")
	var b := _blocks()
	assert_eq(b.size(), 1, "one block event")
	if b.size() == 1:
		assert_eq(b[0]["cc"], ["stun"], "naming the stun:")


func test_the_default_list_is_every_kind() -> void:
	var listed: Array = CreatureSim.stamina_rules().get("cc_through_guard", [])
	for k in MatchSim.CC_KINDS:
		assert_true(k in listed, "%s goes through a guard in stamina.json" % k)
	assert_false("poison" in listed, "poison isn't CC")


func test_a_real_blocked_heavy_launches_the_guard() -> void:
	var sim := _duel("cairn", "culvert", 4.0)
	var d := sim.creatures[1]
	run(sim, 0, 2, G)
	assert_eq(d.state, CreatureSim.State.GUARD, "guarding:")
	run(sim, H, 1, G)  # tapped: the uncharged Haymaker, launch 32
	var up := run_until(sim, func(): return d.state == CreatureSim.State.AIRBORNE, 60, 0, G)
	assert_true(up, "the blocked Haymaker launches the blocker")
	assert_near(d.hp, d.max_hp, 0.001, "with no health lost:")
	assert_lt(d.stamina, d.max_stamina, "and the guard paid its stamina")


func test_a_real_blocked_sno_jab_slows() -> void:
	var sim := _duel("sno", "culvert", 4.0)
	var d := sim.creatures[1]
	run(sim, 0, 2, G)
	run(sim, L, 1, G)
	var slowed := run_until(sim, func(): return d.slow > 0, 30, 0, G)
	assert_true(slowed, "Cold Cross slows through a guard")
	assert_near(d.hp, d.max_hp, 0.001, "no health lost:")
	assert_eq(d.state, CreatureSim.State.GUARD, "and the guard holds:")
