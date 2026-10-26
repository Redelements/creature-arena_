extends TestCase
## Combat rules: combos, the charged slam, dodging, guarding, falling, knockouts.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const D := SimDefs.IN_DODGE
const G := SimDefs.IN_GUARD
const RIGHT := SimDefs.IN_RIGHT
const LEFT := SimDefs.IN_LEFT


## Training match with Culvert standing just left of the dummy, both facing each other.
func _close_training() -> MatchSim:
	var sim := MatchFactory.training()
	sim.creatures[0].pos = Vector2(280, 164)
	sim.creatures[1].pos = Vector2(304, 164)
	return sim


func _jab_range_training() -> MatchSim:
	var sim := MatchFactory.training()
	sim.creatures[0].pos = Vector2(282, 164)
	sim.creatures[1].pos = Vector2(306, 164)
	return sim


func _saw_event(sim: MatchSim, kind: String) -> bool:
	for e in sim.events:
		if e["type"] == kind:
			return true
	return false


func test_three_hit_light_combo_deals_full_damage() -> void:
	var sim := _close_training()
	var d := sim.creatures[1]
	tap(sim, L, 9)
	tap(sim, L, 9)
	tap(sim, L, 60)
	assert_near(d.hp, d.max_hp - 18.0, 0.001, "4 + 5 + 9 damage:")


func test_light_combo_counts_consecutive_hits() -> void:
	var sim := _close_training()
	var d := sim.creatures[1]
	var max_combo := 0
	var schedule := [L, 0, 0, 0, 0, 0, 0, 0, 0, 0, L, 0, 0, 0, 0, 0, 0, 0, 0, 0, L]
	for b in schedule:
		run(sim, b, 1)
		max_combo = maxi(max_combo, d.combo_hits)
	for i in 80:  # long enough for the finisher's hitstop + hitstun to finish
		run(sim, 0, 1)
		max_combo = maxi(max_combo, d.combo_hits)
	# The first two jabs only deal damage (no stagger, no combo); the third hit staggers
	# and starts the combo.
	assert_eq(max_combo, 1, "combo counter: only the third hit counts:")
	assert_lt(d.hp, d.max_hp - 15.0, "but all three hits did damage:")
	assert_eq(d.combo_hits, 0, "combo resets once the dummy recovers:")


func test_full_charge_slam_digs_hole_and_target_falls() -> void:
	var sim := MatchFactory.training()
	var p := sim.creatures[0]
	var d := sim.creatures[1]
	p.pos = Vector2(260, 164)
	d.pos = Vector2(280, 164)
	run(sim, H, 50)  # hold heavy past the 45-tick full charge
	var fell := run_until(sim, func(): return d.state == CreatureSim.State.FALLING, 30)
	assert_true(fell, "dummy should drop into the slam hole")
	assert_gt(sim.terrain.count(TerrainGrid.HOLE), 0, "holes after full slam:")
	run(sim, 0, 80)
	assert_near(d.hp, d.max_hp - 18.0 - CreatureSim.FALL_DAMAGE, 0.001, "slam + fall damage:")  # a charged Slam does 18 since the Oct 2026 kit pass
	assert_false(sim.terrain.is_hole_at(d.pos), "dummy should climb out onto solid ground")


func test_tapped_heavy_only_cracks_the_floor() -> void:
	var sim := MatchFactory.training()
	sim.creatures[0].pos = Vector2(120, 164)
	tap(sim, H, 40)
	assert_eq(sim.terrain.count(TerrainGrid.HOLE), 0, "holes:")
	assert_gt(sim.terrain.count(TerrainGrid.CRACKED), 0, "cracked cells:")


func test_two_slams_on_cracked_ground_open_a_hole() -> void:
	var sim := MatchFactory.training()
	sim.creatures[0].pos = Vector2(120, 164)
	tap(sim, H, 40)
	tap(sim, H, 40)
	assert_gt(sim.terrain.count(TerrainGrid.HOLE), 0, "holes after second slam:")


func test_jab_hits_a_standing_opponent() -> void:
	var sim := MatchFactory.versus()
	var b := sim.creatures[1]
	sim.creatures[0].pos = Vector2(200, 164)
	b.pos = Vector2(224, 164)
	tap(sim, L, 40)
	assert_near(b.hp, b.max_hp - 4.0, 0.001, "jab damage:")


func test_dodge_iframes_avoid_the_same_jab() -> void:
	var sim := MatchFactory.versus()
	var b := sim.creatures[1]
	sim.creatures[0].pos = Vector2(200, 164)
	b.pos = Vector2(224, 164)
	run(sim, L, 1)
	run(sim, 0, 1)
	run(sim, 0, 1, D | LEFT)  # roll through the attacker during its active frames
	run(sim, 0, 40)
	assert_near(b.hp, b.max_hp, 0.001, "dodger hp:")


func test_guard_blocks_all_damage_and_drains_stamina() -> void:
	var sim := _close_training()
	var d := sim.creatures[1]
	run(sim, 0, 1, G)
	tap(sim, L, 30, G)
	assert_near(d.hp, d.max_hp, 0.001, "no chip damage through guard:")
	assert_near(d.stamina, d.max_stamina - MatchSim.block_drain(d, "light", 4.0), 0.001, "guard stamina:")
	assert_eq(d.state, CreatureSim.State.GUARD, "still guarding:")


func test_heavy_breaks_guard() -> void:
	var sim := _close_training()
	var d := sim.creatures[1]
	run(sim, 0, 1, G)
	run(sim, H, 1, G)
	var hit := run_until(sim, func(): return d.hp < d.max_hp, 40, 0, G)
	assert_true(hit, "heavy should connect")
	assert_near(d.hp, d.max_hp - 10.0, 0.001, "full heavy damage through guard:")
	assert_eq(d.state, CreatureSim.State.CRUMPLE, "guard broken into a crumple:")


func test_walking_stops_at_a_hole_edge() -> void:
	var sim := MatchFactory.training()
	var p := sim.creatures[0]
	p.pos = Vector2(100, 164)
	for r in sim.terrain.rows:
		sim.terrain.set_cell(Vector2i(15, r), TerrainGrid.HOLE)  # x 136..144
	var fell := run_until(sim, func(): return p.state == CreatureSim.State.FALLING, 120, RIGHT)
	assert_false(fell, "walking should never step into a hole")
	assert_lt(p.pos.x, 136.0, "stopped at the edge:")


func test_dodge_rolls_across_a_narrow_hole() -> void:
	var sim := MatchFactory.training()
	var p := sim.creatures[0]
	p.pos = Vector2(128, 164)
	for r in sim.terrain.rows:
		sim.terrain.set_cell(Vector2i(15, r), TerrainGrid.HOLE)
	run(sim, D | RIGHT, 1)
	var fell := run_until(sim, func(): return p.state == CreatureSim.State.FALLING, 40)
	assert_false(fell, "a dodge should clear a one-cell gap")
	assert_gt(p.pos.x, 144.0, "landed on the far side:")


func test_knockback_into_a_hole_causes_a_fall() -> void:
	var sim := _jab_range_training()
	var d := sim.creatures[1]
	for x in range(37, 40):
		for r in sim.terrain.rows:
			sim.terrain.set_cell(Vector2i(x, r), TerrainGrid.HOLE)  # just behind the dummy
	run(sim, L, 1)
	run(sim, 0, 12)
	assert_true(d.state != CreatureSim.State.FALLING and d.state != CreatureSim.State.HITSTUN,
		"a jab doesn't stagger or push any more")
	var fell := false
	for i in 120:  # mash the string
		run(sim, L if i % 2 == 0 else 0, 1)
		if d.state == CreatureSim.State.FALLING:
			fell = true
			break
	assert_true(fell, "the string's third hit knocks the dummy into the hole")
	run(sim, 0, 80)
	assert_lt(d.hp, d.max_hp - CreatureSim.FALL_DAMAGE, "the hits and the fall both hurt:")


func test_hard_knockback_bounces_off_the_wall() -> void:
	var sim := MatchFactory.training()
	var p := sim.creatures[0]
	var d := sim.creatures[1]
	d.pos = Vector2(d.floor_max().x - 6.0, 164)
	p.pos = d.pos - Vector2(24, 0)
	var bounced := false
	var schedule := [L, 0, 0, 0, 0, 0, 0, 0, 0, 0, L, 0, 0, 0, 0, 0, 0, 0, 0, 0, L]
	for b in schedule:
		run(sim, b, 1)
		bounced = bounced or _saw_event(sim, "bounce")
	for i in 60:
		run(sim, 0, 1)
		bounced = bounced or _saw_event(sim, "bounce")
	assert_true(bounced, "combo finisher should bounce the dummy off the wall")


func test_dummy_gets_back_up_after_ko() -> void:
	var sim := _close_training()
	var d := sim.creatures[1]
	d.hp = 3.0
	run(sim, L, 1)
	var ko := run_until(sim, func(): return d.state == CreatureSim.State.KO, 30)
	assert_true(ko, "dummy should be knocked out")
	run(sim, 0, CreatureSim.DUMMY_RESET_TICKS + 5)
	assert_near(d.hp, d.max_hp, 0.001, "dummy hp after reset:")
	assert_eq(d.state, CreatureSim.State.IDLE, "dummy back up:")


func test_knocked_out_player_stays_down() -> void:
	var sim := MatchFactory.versus()
	var b := sim.creatures[1]
	sim.creatures[0].pos = Vector2(200, 164)
	b.pos = Vector2(224, 164)
	b.hp = 2.0
	tap(sim, L, 200)
	assert_eq(b.state, CreatureSim.State.KO, "player KO is final:")


## Fires Cairn's Rockslide Rush straight right at a dummy placed `ahead` px forward and
## `side` px off the line. Returns whether it connected.
func _rush_hits(ahead: float, side: float) -> bool:
	var sim := MatchFactory.training("cairn")
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	a.pos = Vector2(150, 150)
	a.facing = Vector2.RIGHT
	d.pos = a.pos + Vector2(ahead, side)
	var hp := d.hp
	tap(sim, SimDefs.IN_SKILL2, 45)
	return d.hp < hp


func test_rush_catches_a_glancing_target() -> void:
	# Bodies just brush at 20 px off the line; the Rush should still connect there.
	assert_true(_rush_hits(48.0, 22.0), "Rush hits a target it grazes")
	assert_true(_rush_hits(24.0, 18.0), "Rush hits a close target slightly off the line")
	assert_true(_rush_hits(96.0, 0.0), "Rush reaches a target 96 px away")
	assert_false(_rush_hits(48.0, 30.0), "Rush still misses a target well off the line")
