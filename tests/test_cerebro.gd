extends TestCase
## Chef Cerebro's kit: thrown knives, a thrown mallet and a thrown cleaver that all reach
## about as far as Gillbert's Cast Line, a thrown Tenderize that softens foes up and stuns
## them for 3 s, a thrown Flip Out that flips a foe toward him (tapped) or away (held), and
## Knife Flurry's stream of knives through everything in line.

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


## Since the Nov 2026 balance pass Tenderize is thrown: the meat mallet, slower than
## anything else he throws, about as far as his skills.
func test_tenderize_is_thrown_slower_than_his_other_shots() -> void:
	var chef := _duel().creatures[0]
	var mv: Dictionary = chef.def["moves"]["heavy"]
	assert_true(mv.has("projectile"), "Tenderize is a projectile")
	var speed := float(mv["projectile"]["speed"])
	for mid in ["light_1", "light_2", "light_3", "skill_1", "skill_2", "surge"]:
		var other := float(chef.def["moves"][mid]["projectile"]["speed"])
		assert_lt(speed, other, "slower than %s (%.1f):" % [mid, other])
	assert_true(absf(chef.move_range("heavy") - 110.0) <= 10.0,
		"reaches about 110 px (%.0f)" % chef.move_range("heavy"))
	assert_false(mv["projectile"].has("home"), "no homing")


## On a hit: tenderized, and stunned on its feet for exactly 180 ticks (3 s) of play, not
## shortened by combo decay. The match-wide hitstop of the hit itself comes on top.
func test_thrown_tenderize_tenderizes_and_stuns_for_exactly_3_s() -> void:
	var sim := _duel("cairn", 70.0)
	var foe := sim.creatures[1]
	var mv: Dictionary = sim.creatures[0].def["moves"]["heavy"]
	sim.step(PackedInt32Array([H, 0]))
	var hit := run_until(sim, func(): return not _events(sim, "stunned").is_empty(), 80)
	assert_true(hit, "the thrown mallet lands from 70 px")
	assert_eq(foe.vuln, int(mv["vuln_ticks"]), "tenderized for:")
	assert_near(foe.vuln_mult, float(mv["vuln_mult"]), 0.001, "taking extra damage:")
	assert_eq(foe.state, CreatureSim.State.CRUMPLE, "stunned on its feet, not launched:")
	assert_eq(foe.stun_lock, 180, "a fixed stun of 3 s:")
	var stop := sim.hitstop
	var helpless := 0
	var played := 0
	for i in 400:
		var before := foe.stun_lock
		sim.step(PackedInt32Array([0, SimDefs.IN_LIGHT if i % 2 == 0 else 0]))
		if foe.stun_lock != before:
			played += 1
		if foe.state == CreatureSim.State.CRUMPLE:
			helpless += 1
		else:
			break
	assert_eq(helpless, 179 + stop, "helpless for the rest of the 180 ticks plus the hit's own hitstop (%d):" % stop)
	assert_eq(played, 180, "180 ticks of play:")
	run(sim, 0, 2, SimDefs.IN_LIGHT)
	assert_eq(foe.state, CreatureSim.State.ATTACK, "and then it acts at once:")


## His own follow-ups don't cut the stun short: a Mallet Toss that staggers the tenderized
## foe (a short, decayed hitstun of its own) leaves it helpless until the 3 s are up.
func test_the_stun_outlasts_his_follow_ups() -> void:
	var sim := _duel("cairn", 60.0)
	var foe := sim.creatures[1]
	sim.step(PackedInt32Array([H, 0]))
	run_until(sim, func(): return foe.stun_lock > 0, 80)
	var free_early := false
	var hits := 0
	for i in 240:
		sim.step(PackedInt32Array([L if i % 2 == 0 else 0, 0]))
		hits += _events(sim, "hit").size()
		if foe.stun_lock > 1 and not foe.is_stunned():
			free_early = true
	assert_gt(hits, 2, "the string lands on the stunned foe")
	assert_false(free_early, "never free while the stun runs")


func test_a_dodge_avoids_the_thrown_tenderize() -> void:
	for dir in [SimDefs.IN_UP, SimDefs.IN_LEFT]:
		var sim := _duel("cairn", 90.0)
		var foe := sim.creatures[1]
		sim.step(PackedInt32Array([H, 0]))
		run_until(sim, func(): return _shot_near(sim, foe, 44.0), 80)
		run(sim, 0, 1, SimDefs.IN_DODGE | dir)
		var stunned := run_until(sim, func(): return not _events(sim, "stunned").is_empty(), 60)
		assert_false(stunned, "a dodge (%d) gets past the mallet" % dir)
		assert_eq(foe.vuln, 0, "not tenderized (%d):" % dir)
		assert_eq(foe.hp, foe.max_hp, "untouched (%d):" % dir)


## One of his shots in flight within `d` px of `foe`.
func _shot_near(sim: MatchSim, foe: CreatureSim, d: float) -> bool:
	for p in sim.projectiles:
		if Vector2(p["pos"]).distance_to(foe.pos) < d:
			return true
	return false


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


## Flip Out is thrown (Nov 2026 balance pass): the spatula flies about 110 px and flips
## whoever it meets. Tapped, the foe comes toward him, over his head, and lands behind him
## (he turns to follow); held to a full charge (Culvert's Gulp rule: the button still down
## for `charge_max` (20) ticks after the press, windup included) it's flipped away instead.
func test_flip_out_tapped_flips_the_foe_over_his_head_toward_him() -> void:
	var sim := _duel("cairn", 60.0)
	var chef := sim.creatures[0]
	var foe := sim.creatures[1]
	assert_true(absf(chef.move_range("skill_2") - 110.0) <= 10.0,
		"the spatula reaches about 110 px (%.0f)" % chef.move_range("skill_2"))
	sim.step(PackedInt32Array([S2, GUARD]))
	var grabbed := run_until(sim, func(): return not _events(sim, "grab").is_empty(), 60, 0, GUARD)
	assert_true(grabbed, "the spatula scoops a guarding foe from 60 px")
	assert_lt(chef.charge_ratio, 1.0, "tapped:")
	assert_eq(foe.state, CreatureSim.State.AIRBORNE, "flipped into the air:")
	assert_eq(chef.facing, Vector2.LEFT, "he turns to follow it:")
	run_until(sim, func(): return foe.state != CreatureSim.State.AIRBORNE, 80)
	assert_lt(foe.pos.x, chef.pos.x - chef.radius - foe.radius, "it lands behind him")


func test_flip_out_held_flips_the_foe_away() -> void:
	var sim := _duel("cairn", 60.0)
	var chef := sim.creatures[0]
	var foe := sim.creatures[1]
	var start := foe.pos.x
	var hold := int(chef.def["moves"]["skill_2"]["charge_max"])
	assert_eq(hold, int(MatchFactory.load_def("culvert")["moves"]["skill_1"]["charge_max"]),
		"held as long as Culvert's Gulp:")
	run(sim, S2, hold + 1)  # the press starts it, then charge_max ticks of charge
	var grabbed := run_until(sim, func(): return not _events(sim, "grab").is_empty(), 60)
	assert_true(grabbed, "the held spatula flips it too")
	assert_near(chef.charge_ratio, 1.0, 0.001, "held to a full charge:")
	assert_eq(chef.facing, Vector2.RIGHT, "he keeps facing it:")
	run_until(sim, func(): return foe.state != CreatureSim.State.AIRBORNE, 80)
	var away := float(chef.def["moves"]["skill_2"]["hold"]["flip_away"])
	assert_near(foe.pos.x - start, away, 6.0, "it lands about flip_away px further out:")


## One tick short of the full charge is still a tap.
func test_flip_out_a_tick_short_of_the_hold_is_a_tap() -> void:
	var sim := _duel("cairn", 60.0)
	var chef := sim.creatures[0]
	var foe := sim.creatures[1]
	run(sim, S2, int(chef.def["moves"]["skill_2"]["charge_max"]))
	run_until(sim, func(): return not _events(sim, "grab").is_empty(), 60)
	run_until(sim, func(): return foe.state != CreatureSim.State.AIRBORNE, 80)
	assert_lt(foe.pos.x, chef.pos.x, "flipped toward him and over:")


func test_flip_out_misses_out_of_its_lane_and_through_a_dodge() -> void:
	var sim := _duel("cairn", 60.0)
	sim.creatures[1].pos.y += 30.0  # off the line he throws along
	tap(sim, S2, 60)
	assert_eq(sim.creatures[1].hp, sim.creatures[1].max_hp, "out of the lane: missed:")
	var sim2 := _duel("cairn", 80.0)
	var foe := sim2.creatures[1]
	sim2.step(PackedInt32Array([S2, 0]))
	run_until(sim2, func(): return _shot_near(sim2, foe, 44.0), 80)
	run(sim2, 0, 1, SimDefs.IN_DODGE | SimDefs.IN_UP)
	var grabbed := run_until(sim2, func(): return not _events(sim2, "grab").is_empty(), 60)
	assert_false(grabbed, "a dodge gets past the spatula")


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
