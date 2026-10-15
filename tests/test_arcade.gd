extends TestCase
## The Arcade ladder (Arcade) and what it earns (Progress): six stages, the boss a
## 3v3 Duel one level up, a seeded order, clears that unlock palettes.


func _fresh_progress() -> void:
	var p := "user://test_progress_%d.json" % Time.get_ticks_usec()
	Progress.reset_for_tests(p)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_a_ladder_has_five_opponents_then_a_boss_team_one_level_up() -> void:
	var a := Arcade.new("cairn", 1, 7)
	assert_eq(a.order.size(), Arcade.STAGES, "six stages:")
	for i in Arcade.STAGES - 1:
		assert_true(String(a.order[i]) in MatchFactory.FIGHTERS, "stage %d is a fighter" % (i + 1))
		assert_true(String(a.order[i]) != "cairn", "never yourself")
	var boss: Array = a.boss_team()
	assert_eq(boss.size(), 3, "the boss is a team of three:")
	assert_eq(a.player_team().size(), 3, "so is yours:")
	assert_eq(a.player_team()[0], "cairn", "with you first:")
	assert_false(a.is_boss(), "stage 1 is not the boss")
	assert_eq(a.stage_level(), 1, "stages play at the chosen level:")
	for i in Arcade.STAGES - 1:
		assert_true(a.advance(), "won stage %d" % (i + 1))
	assert_true(a.is_boss(), "the sixth is the boss")
	assert_eq(a.stage_level(), 2, "one level up:")
	assert_false(a.advance(), "past the boss the ladder is cleared")
	var rage := Arcade.new("cairn", 3, 7)
	rage.stage = Arcade.STAGES - 1
	assert_eq(rage.stage_level(), 3, "Rage stays Rage:")


func test_the_same_seed_gives_the_same_ladder_and_a_different_one_another() -> void:
	var a := Arcade.new("digby", 2, 11)
	var b := Arcade.new("digby", 2, 11)
	var c := Arcade.new("digby", 2, 12)
	assert_eq(a.order, b.order, "seeded:")
	assert_true(a.order != c.order, "another seed, another run")
	var seen := {}
	for id in a.order.slice(0, Arcade.STAGES - 1):
		seen[id] = true
	assert_eq(seen.size(), Arcade.STAGES - 1, "five different opponents:")


func test_clears_are_recorded_and_unlock_palettes() -> void:
	_fresh_progress()
	assert_eq(Progress.arcade_best("sno"), -1, "nothing cleared yet:")
	assert_eq(Progress.palettes_unlocked("sno"), 1, "one palette to start:")
	assert_true(Progress.record_clear("sno", 1), "a Normal clear is new")
	assert_eq(Progress.palettes_unlocked("sno"), 3, "Normal: three palettes:")
	assert_false(Progress.record_clear("sno", 0), "an Easy clear after that is nothing new")
	assert_true(Progress.record_clear("sno", 3), "a Rage clear is")
	assert_eq(Progress.palettes_unlocked("sno"), 4, "the lot:")
	assert_eq(Progress.palettes_unlocked("pete"), 1, "per fighter:")
	Progress.set_palette("sno", 2)
	Progress.reset_for_tests(Progress.path)  # reload from disk
	assert_eq(Progress.palette("sno"), 2, "the palette is saved:")
	assert_eq(Progress.next_palette("sno"), 3, "cycles on:")
	assert_eq(Progress.next_palette("sno"), 0, "and wraps:")
	Progress.set_palette("pete", 3)
	assert_eq(Progress.palette("pete"), 0, "can't wear a locked palette:")
