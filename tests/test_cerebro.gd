extends TestCase
## Chef Cerebro's kit: thrown knives, a thrown mallet and a thrown cleaver that all reach
## about as far as Gillbert's Cast Line, Tenderize softening foes up, Flip Out throwing a
## foe over his head, and Knife Flurry's stream of knives through everything in line.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE
const GUARD := SimDefs.IN_GUARD


## Chef Cerebro on the left, `foe` on the right with `gap` pixels between their bodies.
func _duel(foe := "cairn", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus("cerebro", foe)
	sim.creatures[0].pos = Vector2(200, 164)
	sim.creatures[1].pos = Vector2(200 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


func _events(sim: MatchSim, kind: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e["type"]) == kind:
			out.append(e)
	return out


func test_his_throws_reach_as_far_as_gillberts_cast_line() -> void:
	var sim := _duel()
	var chef := sim.creatures[0]
	var gill := CreatureSim.new(9, MatchFactory.load_def("gillbert"), Vector2.ZERO)
	var cast := gill.move_range("skill_2")
	for mid in ["light_1", "light_2", "light_3", "skill_1", "surge"]:
		var r := chef.move_range(mid)
		assert_true(absf(r - cast) <= cast * 0.15, "%s reaches %.0f px, Cast Line %.0f px" % [mid, r, cast])


func test_knife_flick_hits_from_range() -> void:
	var sim := _duel("cairn", 88.0)
	var hit := run_until(sim, func(): return not _events(sim, "hit").is_empty(), 40, L)
	assert_true(hit, "a knife flicked from 88 px away lands")
	assert_false(sim.creatures[1].is_stunned(), "but doesn't stagger: only the Mallet Toss does")


func test_only_the_mallet_toss_staggers() -> void:
	var sim := _duel("cairn", 60.0)
	var foe := sim.creatures[1]
	var stuns: Array = []
	for i in 90:
		sim.step(PackedInt32Array([L if i % 2 == 0 else 0, 0]))
		for e in sim.events:
			if String(e["type"]) == "hit":
				stuns.append(foe.is_stunned())
	assert_true(stuns.size() >= 3, "all three lights land")
	assert_eq(stuns.slice(0, 3), [false, false, true], "only the third, the Mallet Toss, staggers:")


func test_knife_flick_misses_past_its_range() -> void:
	var sim := _duel("cairn", 130.0)
	tap(sim, L, 50)
	assert_eq(sim.creatures[1].hp, sim.creatures[1].max_hp, "out of range: untouched:")


func test_the_whole_ranged_string_combos_from_afar() -> void:
	var sim := _duel("cairn", 84.0)
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S1, "skill_1"], [SU, "surge"]])
	assert_eq(errors.size(), 0, "every step comes out")
	assert_gt(dmg, 50.0, "Flick, Flick, Mallet > Cleaver > Flurry all land from 84 px:")
	assert_gt(sim.creatures[1].combo_damage + 1.0, 1.0, "as one combo")


func test_cleaver_toss_hits_only_the_first_foe() -> void:
	var sim := _duel("cairn", 30.0)
	var behind := sim.add_creature(MatchFactory.load_def("culvert"), sim.creatures[1].pos + Vector2(26, 0))
	behind.facing = Vector2.LEFT
	run_until(sim, func(): return not _events(sim, "hit").is_empty(), 60, S1)
	run(sim, 0, 30)
	assert_lt(sim.creatures[1].hp, sim.creatures[1].max_hp, "the cleaver hits the first in line")
	assert_eq(behind.hp, behind.max_hp, "and stops there:")


func test_tenderize_hits_all_around_and_softens_them_up() -> void:
	var sim := _duel("cairn", 2.0)
	var foe := sim.creatures[1]
	foe.pos.x = sim.creatures[0].pos.x - 24.0  # behind him
	var soft := run_until(sim, func(): return not _events(sim, "tenderized").is_empty(), 60, H)
	assert_true(soft, "the mallet reaches behind him too")
	var mv: Dictionary = sim.creatures[0].def["moves"]["heavy"]
	assert_eq(foe.vuln, int(mv["vuln_ticks"]), "tenderized for:")
	assert_near(foe.vuln_mult, float(mv["vuln_mult"]), 0.001, "taking extra damage:")


func test_a_tenderized_foe_takes_more_damage_until_it_wears_off() -> void:
	var dmg := []
	for soft in [false, true]:
		var sim := _duel("cairn", 60.0)
		var foe := sim.creatures[1]
		if soft:
			foe.vuln = 200
			foe.vuln_mult = 1.2
		run_until(sim, func(): return not _events(sim, "hit").is_empty(), 40, L)
		dmg.append(foe.max_hp - foe.hp)
	assert_near(dmg[1], dmg[0] * 1.2, 0.01, "a knife on a tenderized foe:")
	var sim2 := _duel("cairn", 60.0)
	sim2.creatures[1].vuln = 10
	sim2.creatures[1].vuln_mult = 1.2
	run(sim2, 0, 12)
	assert_eq(sim2.creatures[1].vuln, 0, "it wears off:")


func test_flip_out_throws_the_foe_over_his_head_through_guard() -> void:
	var sim := _duel("cairn", 4.0)
	var chef := sim.creatures[0]
	var foe := sim.creatures[1]
	var grabbed := run_until(sim, func(): return not _events(sim, "grab").is_empty(), 60, S2, GUARD)
	assert_true(grabbed, "the spatula scoops a guarding foe")
	assert_eq(foe.state, CreatureSim.State.AIRBORNE, "flipped into the air:")
	assert_eq(chef.facing, Vector2.LEFT, "he turns to follow it:")
	run_until(sim, func(): return foe.state != CreatureSim.State.AIRBORNE, 80)
	assert_lt(foe.pos.x, chef.pos.x - chef.radius - foe.radius, "it lands behind him")


func test_flip_out_into_knife_flurry() -> void:
	var sim := _duel("cairn", 2.0)
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S2, "skill_2"], [SU, "surge"]])
	assert_eq(errors.size(), 0, "every step comes out")
	assert_gt(dmg, 45.0, "the flurry follows them over his head:")


func test_knife_flurry_throws_a_stream_through_everyone_in_line() -> void:
	var sim := _duel("cairn", 20.0)
	var chef := sim.creatures[0]
	chef.energy = 100.0
	var behind := sim.add_creature(MatchFactory.load_def("culvert"), sim.creatures[1].pos + Vector2(30, 0))
	behind.facing = Vector2.LEFT
	var thrown := 0
	var hits := [0, 0, 0]
	var knocked_down := false
	sim.step(PackedInt32Array([SU, 0, 0]))
	for i in 140:
		sim.step(PackedInt32Array([0, 0, 0]))
		knocked_down = knocked_down or sim.creatures[1].state == CreatureSim.State.KNOCKDOWN
		for e in sim.events:
			if String(e["type"]) == "projectile" and int(e["who"]) == 0:
				thrown += 1
			if String(e["type"]) == "hit" and int(e["attacker"]) == 0:
				hits[int(e["target"])] += 1
	var count := int(chef.def["moves"]["surge"]["projectile"]["volley"]["count"])
	assert_eq(thrown, count, "knives thrown:")
	assert_gt(hits[1], 2, "the first in line takes a stream of knives:")
	assert_gt(hits[2], 0, "and they fly on into the one behind:")
	assert_true(knocked_down, "the last knife knocks down")


func test_rollback_with_knives_in_the_air() -> void:
	var sim := _duel("culvert", 40.0)
	sim.creatures[0].energy = 100.0
	sim.creatures[1].vuln = 100
	sim.creatures[1].vuln_mult = 1.2
	run_until(sim, func(): return sim.projectiles.size() >= 3, 60, SU)
	var snap := sim.snapshot()
	run(sim, 0, 50, L)
	var once := sim.state_digest()
	sim.restore(snap)
	run(sim, 0, 50, L)
	assert_eq(sim.state_digest(), once, "replaying from the snapshot gives the same state:")
