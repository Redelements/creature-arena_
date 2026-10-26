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


## A Daily fight played as main plays it: INTRO_TICKS rows of nothing, then a Rage CPU
## in the player's seat against the day's CPU, recorded row by row until a knockout or
## the clock. Returns [replay, the score main gives it].
static func play_daily(d: Daily, seed_ := 7) -> Array:
	var sim := d.build()
	var me := CpuController.new(0, CpuController.RAGE, seed_)
	var foe := d.cpu()
	var rep := Replay.new()
	var end := Daily.INTRO_TICKS + Daily.FIGHT_TICKS
	while sim.tick < end:
		var ins := PackedInt32Array([0, 0])
		if sim.tick >= Daily.INTRO_TICKS:
			ins = PackedInt32Array([me.bits(sim), foe.bits(sim)])
		rep.record(ins)
		sim.step(ins)
		if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
			break
	var a := sim.creatures[0]
	var b := sim.creatures[1]
	var ko_a := a.state == CreatureSim.State.KO
	var ko_b := b.state == CreatureSim.State.KO
	var won := (ko_b and not ko_a) or (not ko_a and not ko_b and a.hp / a.max_hp > b.hp / b.max_hp)
	return [rep, d.score_fight(won, clampf(a.hp / a.max_hp, 0.0, 1.0), sim.tick)]


func test_a_daily_score_is_what_its_replay_says() -> void:
	var d := Daily.new("cairn", 20261015)
	var played := play_daily(d)
	var rep: Replay = played[0]
	var score: int = played[1]
	assert_gt(float(score), 0.0, "the Rage player wins the day's fight:")
	assert_eq(d.verify(rep), score, "and the replay, played again against the day's own CPU, scores the same:")
	assert_eq(Daily.new("cairn", 20261015).verify(rep), score, "every time:")
	# The CPU's column is never trusted: a replay where the CPU stood still is refused.
	var forged := Replay.new()
	for row in rep.frames:
		forged.record(PackedInt32Array([row[0], 0]))
	assert_eq(d.verify(forged), -1, "a replay whose CPU column is all zeros is refused:")
	var moved := Replay.new()
	for k in rep.frames.size():
		var row: PackedInt32Array = rep.frames[k].duplicate()
		if k == Daily.INTRO_TICKS + 30:
			row[1] ^= SimDefs.IN_GUARD
		moved.record(row)
	assert_eq(d.verify(moved), -1, "and so is one with a single CPU input changed:")
	# Moving early doesn't help: the intro's rows are played as nobody pressing anything.
	var early := Replay.new()
	for k in rep.frames.size():
		var row: PackedInt32Array = rep.frames[k].duplicate()
		if k < Daily.INTRO_TICKS:
			row[0] = SimDefs.IN_LIGHT
		early.record(row)
	assert_eq(d.verify(early), score, "inputs during the intro count for nothing:")
	assert_eq(Daily.max_frames(), Daily.INTRO_TICKS + Daily.FIGHT_TICKS + 60, "room for a fight that goes the distance")
	assert_eq(load("res://src/game/main.gd").INTRO_TICKS, Daily.INTRO_TICKS, "the intro is main's:")
	assert_eq(d.score_fight(false, 0.5, 100), 0, "a loss scores nothing:")
	assert_eq(d.score_fight(true, 1.0, 0), 1000 + 90 * 5, "a perfect instant win (the fight is 90 s):")


func test_the_daily_is_on_the_stadium_whatever_arena_was_picked() -> void:
	var was := MatchFactory.arena
	MatchFactory.arena = "quarry"
	var sim := Daily.new("cairn", 20261015).build()
	MatchFactory.arena = was
	assert_eq(String(sim.arena.get("id", "")), ArenaMap.DEFAULT, "the same fight for everyone:")


## The game itself plays a Daily (a Rage CPU in the player's seat, headless): the score it
## shows and saves is the one the server's verification gives its saved replay.
func test_a_daily_played_in_the_game_verifies_to_the_same_score() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	const SETTINGS := "user://test_ladders_daily.cfg"
	Progress.reset_for_tests("user://test_progress_ladders_%d.json" % Time.get_ticks_usec())
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = SETTINGS
	root.add_child(g)
	g._online_server = ""  # no server: nothing is sent
	g._cpu_vs_cpu = true  # a CPU plays the player's seat
	g.level = 3
	var path := "user://daily/daily_%d.json" % Daily.today()
	var kept := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	g._start_match(g.mode_index("Daily Challenge"))
	var d: Daily = g.arcade
	for i in Daily.max_frames() + 400:
		g._physics_process(1.0 / 60.0)
		if g.flow == g.Flow.MATCH_OVER:
			break
	assert_eq(g.flow, g.Flow.MATCH_OVER, "the fight ends:")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(saved is Dictionary, "and is saved with its replay")
	var rep := Replay.from_dict(saved["replay"], Daily.max_frames(), 2)
	assert_true(rep != null, "a replay the server takes")
	assert_eq(Daily.new(d.fighter, d.date).verify(rep), int(saved["score"]), "the server's score is the game's:")
	g.free()
	if kept != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(kept)
		f.close()
	else:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(SETTINGS)
