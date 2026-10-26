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
	var y := SimDefs.floor_rect().get_center().y  # room above and below for a long blink
	sim.creatures[0].pos = Vector2(120, y)
	sim.creatures[1].pos = Vector2(120 + sim.creatures[0].radius + sim.creatures[1].radius + gap, y)
	return sim


func _events(sim: MatchSim, kind: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e["type"]) == kind:
			out.append(e)
	return out


## His skills reach about 120 px (what Gillbert's Cast Line reached before it was doubled)
## and his lights half again as far.
func test_his_throws_reach_about_120_px_and_his_lights_about_115() -> void:
	var sim := _duel()
	var chef := sim.creatures[0]
	var cast := 119.0
	for mid in ["skill_1", "surge"]:
		var r := chef.move_range(mid)
		assert_true(absf(r - cast) <= cast * 0.15, "%s reaches %.0f px, about %.0f px" % [mid, r, cast])
	# The lights reached half again as far until the Oct 2026 kit pass: the thrown string
	# outranged every melee kit and did about 90% of his damage, so now it reaches about
	# 115 px (the mallet a little further) and his skills are what reach further.
	for mid in ["light_1", "light_2", "light_3"]:
		var r := chef.move_range(mid)
		assert_true(absf(r - 115.0) <= 15.0, "%s reaches %.0f px, about 115 px" % [mid, r])


func test_knife_flick_hits_from_range() -> void:
	var sim := _duel("cairn", 88.0)
	var hit := run_until(sim, func(): return not _events(sim, "hit").is_empty(), 40, L)
	assert_true(hit, "a knife flicked from 88 px away lands")
	assert_false(sim.creatures[1].is_stunned(), "but doesn't stagger: none of his lights do")


## The Mallet Toss staggered until Oct 25 2026 (Kevin's nerf): now none of the string does.
func test_none_of_the_lights_stagger() -> void:
	var sim := _duel("cairn", 60.0)
	var foe := sim.creatures[1]
	var stuns: Array = []
	for i in 90:
		sim.step(PackedInt32Array([L if i % 2 == 0 else 0, 0]))
		for e in sim.events:
			if String(e["type"]) == "hit":
				stuns.append(foe.is_stunned())
	assert_true(stuns.size() >= 3, "all three lights land")
	assert_eq(stuns.slice(0, 3), [false, false, false], "not even the third, the Mallet Toss:")


func test_knife_flick_misses_from_half_again_as_far() -> void:
	var sim := _duel("cairn", 140.0)
	tap(sim, L, 50)
	assert_eq(sim.creatures[1].hp, sim.creatures[1].max_hp, "a knife flicked from 140 px away falls short (it reached since the Oct 2026 kit pass):")


func test_knife_flick_misses_past_its_range() -> void:
	var sim := _duel("cairn", 190.0)
	tap(sim, L, 50)
	assert_eq(sim.creatures[1].hp, sim.creatures[1].max_hp, "out of range: untouched:")


func test_the_whole_ranged_string_combos_from_afar() -> void:
	var sim := _duel("cairn", 84.0)
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S1, "skill_1"], [SU, "surge"]])
	assert_eq(errors.size(), 0, "every step comes out")
	assert_gt(dmg, 50.0, "Flick, Flick, Mallet > Cleaver > Flurry all land from 84 px:")
	assert_gt(sim.creatures[1].combo_damage + 1.0, 1.0, "as one combo")


## Since the Oct 2026 kit pass the cleaver bounces off the first foe into one more close by
## (projectile "bounce"; tests/test_kit_keys.gd has the rules), never a third.
func test_cleaver_toss_bounces_from_the_first_foe_to_one_more() -> void:
	var sim := _duel("cairn", 30.0)
	var behind := sim.add_creature(MatchFactory.load_def("culvert"), sim.creatures[1].pos + Vector2(26, 0))
	behind.facing = Vector2.LEFT
	var third := sim.add_creature(MatchFactory.load_def("sno"), behind.pos + Vector2(0, 30))
	run_until(sim, func(): return not _events(sim, "hit").is_empty(), 60, S1)
	run(sim, 0, 30)
	assert_lt(sim.creatures[1].hp, sim.creatures[1].max_hp, "the cleaver hits the first in line")
	assert_lt(behind.hp, behind.max_hp, "bounces into the nearest other foe")
	assert_eq(third.hp, third.max_hp, "and stops there:")


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
	var tenderized := false
	sim.step(PackedInt32Array([SU, 0, 0]))
	for i in 140:
		sim.step(PackedInt32Array([0, 0, 0]))
		knocked_down = knocked_down or sim.creatures[1].state == CreatureSim.State.KNOCKDOWN
		tenderized = tenderized or sim.creatures[1].vuln > 0
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
	assert_true(tenderized, "and tenderizes: the team's damage goes up for a while")


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


func test_his_dodge_is_a_teleport_after_a_short_delay() -> void:
	var sim := _duel("cairn", 60.0)
	var chef := sim.creatures[0]
	var bl: Dictionary = chef.def["dodge"]["blink"]
	var start := chef.pos
	run(sim, SimDefs.IN_DODGE | SimDefs.IN_UP, 1)
	assert_eq(chef.state, CreatureSim.State.DODGE, "the dodge starts")
	for t in int(bl["at"]) - 1:
		assert_near(chef.pos.distance_to(start), 0.0, 0.001, "he stays put before the blink (tick %d):" % t)
		run(sim, 0, 1)
	var warped := false
	for t in 3:
		run(sim, 0, 1)
		if not sim.events.filter(func(e): return String(e["type"]) == "warp").is_empty():
			warped = true
			break
	assert_true(warped, "a warp event when he blinks")
	assert_near(start.y - chef.pos.y, float(bl["distance"]), 0.001, "and he's that far up the screen at once:")
	assert_near(chef.pos.x, start.x, 0.001, "straight up:")
	assert_true(chef.is_invulnerable(), "untouchable around the jump")
	run(sim, 0, int(chef.def["dodge"]["frames"]))
	assert_eq(chef.state, CreatureSim.State.IDLE, "and back to normal after")


func test_his_teleport_stops_at_the_wall() -> void:
	var sim := _duel()
	var chef := sim.creatures[0]
	chef.pos = Vector2(SimDefs.floor_rect().position.x + 30.0, chef.pos.y)
	run(sim, SimDefs.IN_DODGE | SimDefs.IN_LEFT, 1)
	run(sim, 0, int(chef.def["dodge"]["frames"]) + 1)
	assert_near(chef.pos.x, chef.floor_min().x, 0.001, "lands against the wall, still on the floor:")


func test_his_teleport_has_a_cooldown() -> void:
	var sim := _duel("cairn", 160.0)
	var chef := sim.creatures[0]
	var dg: Dictionary = chef.def["dodge"]
	var cd := int(dg["cooldown"])
	assert_eq(cd, 60, "1 s (0.75 s before the Oct 2026 assassin pass):")
	run(sim, SimDefs.IN_DODGE | SimDefs.IN_UP, 1)
	run(sim, 0, int(dg["frames"]) + 1)
	assert_eq(chef.state, CreatureSim.State.IDLE, "the blink is over")
	assert_false(chef.can_dodge(), "but it's still recharging")
	assert_gt(chef.dodge_cooldown_ratio(), 0.0, "the HUD shows it recharging:")
	var at := chef.pos
	run(sim, SimDefs.IN_DODGE | SimDefs.IN_DOWN, 1)
	run(sim, 0, 8)
	assert_ne_state(chef)
	assert_lt(chef.pos.distance_to(at), 1.0, "a dodge pressed too soon doesn't blink (a step at most):")
	run(sim, 0, cd)
	assert_true(chef.can_dodge(), "ready again after 1 s")
	at = chef.pos
	run(sim, SimDefs.IN_DODGE | SimDefs.IN_DOWN, 1)
	run(sim, 0, int(dg["blink"]["at"]) + 1)
	assert_near(chef.pos.y - at.y, float(dg["blink"]["distance"]), 0.001, "and then it blinks:")


func assert_ne_state(c: CreatureSim) -> void:
	assert_true(c.state != CreatureSim.State.DODGE, "no dodge while recharging")


func test_a_blink_pressed_just_before_it_recharges_comes_out_when_ready() -> void:
	var sim := _duel("cairn", 160.0)
	var chef := sim.creatures[0]
	var dg: Dictionary = chef.def["dodge"]
	run(sim, SimDefs.IN_DODGE | SimDefs.IN_UP, 1)
	run(sim, 0, int(dg["cooldown"]) - 4)  # 3 ticks of cooldown left
	assert_false(chef.can_dodge(), "still recharging")
	chef.stamina = chef.max_stamina  # the cooldown is what's tested, not the stamina for two blinks
	assert_false(chef.can_dodge(), "still recharging, with stamina to spare")
	run(sim, SimDefs.IN_DODGE | SimDefs.IN_DOWN, 1)
	run(sim, 0, 4)
	assert_eq(chef.state, CreatureSim.State.DODGE, "the early press blinks as soon as it's ready")
