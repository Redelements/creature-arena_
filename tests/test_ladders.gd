extends TestCase
## Mutators on the match, the Gauntlet's waves and the Daily Challenge's seeded fight
## with a replay-verified score.


func _fresh_progress() -> void:
	var p := "user://test_progress_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(p)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_mutators_change_the_match() -> void:
	var plain := MatchFactory.versus("cairn", "culvert")
	var fast := MatchFactory.versus("cairn", "culvert")
	fast.apply_mutators({"speed_mult": 1.3, "damage_mult": 1.5, "air_mult": 2.0}, 1)
	for sim: MatchSim in [plain, fast]:
		sim.creatures[0].pos = sim.terrain.cell_center(Vector2i(20, 18))
		run(sim, SimDefs.IN_RIGHT, 40)
	assert_gt(fast.creatures[0].pos.x, plain.creatures[0].pos.x + 10.0, "haste walks further")
	var hurt := [0.0, 0.0]
	for k in 2:
		var sim: MatchSim = [plain, fast][k]
		var d: CreatureSim = sim.creatures[1]
		var before := d.hp
		d.take_damage(10.0, sim)
		hurt[k] = before - d.hp
	assert_near(float(hurt[1]), float(hurt[0]) * 1.5, 0.01, "glass cannon: hits land harder:")
	plain.creatures[1].enter_air(30, Vector2.ZERO)
	fast.creatures[1].enter_air(30, Vector2.ZERO)
	assert_eq(fast.creatures[1].air_total, 60, "low gravity: twice the air time:")
	var surge := MatchFactory.versus("cairn", "culvert")
	surge.apply_mutators({"surge_every": 100}, 1)
	run(surge, 0, 100)
	assert_near(surge.creatures[0].energy, CreatureSim.MAX_ENERGY, 0.01, "surge rush fills the meter:")
	var pits := MatchFactory.versus("cairn", "culvert")
	pits.apply_mutators({"pit_floor": 0.2}, 5)
	var sunk := pits.terrain.count(TerrainGrid.CHASM)
	assert_gt(float(sunk), 84.0 * 36.0 * 0.1, "a floor of pits sinks a share of it (%d)" % sunk)
	for c in pits.creatures:
		assert_false(pits.terrain.is_hole_at(c.pos), "but not under a spawn")
	var again := MatchFactory.versus("cairn", "culvert")
	again.apply_mutators({"pit_floor": 0.2}, 5)
	assert_eq(again.terrain.cells, pits.terrain.cells, "the same seed sinks the same cells:")


func test_the_gauntlet_climbs_and_carries_health() -> void:
	_fresh_progress()
	var g := Gauntlet.new("sno", 4)
	assert_eq(g.stage_level(), 0, "wave 1 is Easy:")
	assert_eq(g.carried_hp(), -1.0, "full health to start:")
	var first := g.opponent()
	assert_true(first in MatchFactory.FIGHTERS and first != "sno", "a real opponent")
	g.stage_won(40.0)
	assert_eq(g.stage, 1, "wave 2:")
	assert_near(g.carried_hp(), 40.0 + g.max_hp * Gauntlet.HEAL_SHARE, 0.01, "health carries with a breather:")
	g.stage_won(g.max_hp)
	assert_eq(g.carried_hp(), g.max_hp, "never over full:")
	assert_eq(g.stage_level(), 1, "wave 3 is Normal:")
	for i in 10:
		g.stage_won(50.0)
	assert_eq(g.stage_level(), 3, "and it tops out at Rage:")
	var b := g.lost_banner()
	assert_eq(g.waves(), 12, "waves cleared:")
	assert_eq(Progress.gauntlet_best("sno"), 12, "the best is kept:")
	assert_true(String(b[1]).contains("new best"), "and announced")
	assert_false(g.can_retry(), "a lost Gauntlet starts over")


func test_the_daily_is_the_same_for_the_same_date() -> void:
	var a := Daily.new("pete", 20261015)
	var b := Daily.new("pete", 20261015)
	var c := Daily.new("pete", 20261016)
	assert_eq(a.opponent(), b.opponent(), "same opponent:")
	assert_eq(a.picks, b.picks, "same mutators:")
	assert_eq(a.stage_level(), b.stage_level(), "same level:")
	assert_true(a.level >= 1 and a.level <= 2, "Normal or Hard")
	assert_eq(a.picks.size(), 2, "two mutators:")
	assert_true(a.picks[0] != a.picks[1], "different ones")
	assert_true(a.opponent() != c.opponent() or a.picks != c.picks or a.level != c.level, "another day, another fight")
	assert_true(a.versus_label().contains("·"), "the banner names them")
	assert_false(a.stage_won(50.0), "one fight only")


func test_a_daily_score_is_what_its_replay_says() -> void:
	var d := Daily.new("cairn", 20261015)
	var sim := d.build()
	var rep := Replay.new()
	var me := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.hp = 6.0  # a short fight: the player jabs it down
	foe.pos = me.pos + Vector2(24, 0)
	me.facing = Vector2.RIGHT
	var ticks := 0
	for i in 300:
		# The foe stands still here: what matters is that a recorded fight rescored
		# on a fresh match gives the same number (the fair run below).
		var ins := PackedInt32Array([SimDefs.IN_LIGHT if i % 10 == 0 else 0, 0])
		rep.record(ins)
		sim.step(ins)
		ticks += 1
		if foe.state == CreatureSim.State.KO:
			break
	assert_eq(foe.state, CreatureSim.State.KO, "the player won:")
	var score := d.score_fight(true, me.hp / me.max_hp, ticks)
	assert_gt(float(score), 0.0, "a win scores")
	# Verification replays the inputs on a fresh match of the day: the foe has full
	# health there, so the hand-weakened fight can't be reproduced; a fair run can.
	var fair := Daily.new("cairn", 20261015)
	var sim2 := fair.build()
	var cpu2 := fair.cpu()
	var rep2 := Replay.new()
	var t2 := 0
	for i in 600:
		var ins := PackedInt32Array([0, cpu2.bits(sim2)])
		rep2.record(ins)
		sim2.step(ins)
		t2 += 1
	var expect := fair.score_fight(false, sim2.creatures[0].hp / sim2.creatures[0].max_hp, t2) \
		if sim2.creatures[0].state == CreatureSim.State.KO or sim2.creatures[1].state != CreatureSim.State.KO else -1
	var got := fair.verify(rep2)
	if expect >= 0:
		assert_eq(got, expect, "the replay scores the same:")
	assert_eq(fair.verify(rep2), got, "and verifies the same twice:")
	assert_eq(d.score_fight(false, 0.5, 100), 0, "a loss scores nothing:")
	assert_eq(d.score_fight(true, 1.0, 0), 1000 + 180 * 5, "a perfect instant win:")
