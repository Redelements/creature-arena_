extends TestCase
## Counterplay: big moves thrown raw must be readable and answerable, and reacting to a
## Surge's freeze must work. On a crowded field (2 v 2 and up, a Brawl of three or four) a
## Surge doesn't freeze anyone: thrown raw, it winds up instead, long enough to react to. Combo routes stay fast (see test_combos.gd).

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const D := SimDefs.IN_DODGE
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE
## About a quarter second: a typical reaction to something you're watching for.
const REACTION := 15
## The high-reward moves that need a readable windup when thrown raw.
const BIG_MOVES := [["cairn", "heavy"], ["cairn", "skill_2"], ["culvert", "heavy"],
	["culvert", "skill_1"], ["culvert", "skill_2"], ["craglash", "heavy"], ["craglash", "skill_1"],
	["craglash", "skill_2"],
	["barkley", "heavy"], ["barkley", "skill_1"], ["gillbert", "heavy"], ["gillbert", "skill_1"],
	["gillbert", "skill_2"], ["cerebro", "heavy"], ["cerebro", "skill_1"], ["cerebro", "skill_2"],
	["hissy", "heavy"], ["hissy", "skill_1"], ["digby", "heavy"], ["digby", "skill_2"],
	["pete", "heavy"], ["pete", "skill_2"], ["sno", "heavy"], ["sno", "skill_2"],
	["crease", "heavy"], ["crease", "skill_1"]]


func _duel(left: String, right: String, gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


func test_big_moves_give_time_to_react_when_thrown_raw() -> void:
	for pair in BIG_MOVES:
		var def := MatchFactory.load_def(String(pair[0]))
		var mv: Dictionary = def["moves"][pair[1]]
		var warning := int(mv.get("windup", 0)) + int(mv.get("startup", 0)) + 1
		assert_true(warning >= REACTION, "%s %s gives only %d frames of warning"
			% [def["name"], mv["name"], warning])


func test_raw_move_winds_up_and_holds_still() -> void:
	var sim := _duel("culvert", "cairn", 30.0)
	var culvert := sim.creatures[0]
	var start := culvert.pos
	tap(sim, S1, 1)
	assert_true(culvert.is_winding_up(), "a raw Gulp should start with a windup")
	var wind := int(culvert.move_def()["windup"])
	assert_eq(culvert.windup_total, wind, "windup length:")
	run(sim, 0, wind - 2)
	assert_true(culvert.is_winding_up(), "still winding up")
	assert_near(culvert.pos.x, start.x, 0.001, "no lunge during the windup:")
	run(sim, 0, 2)
	assert_false(culvert.is_winding_up(), "windup over")


func test_cancelled_move_skips_the_windup() -> void:
	var sim := _duel("culvert", "cairn")
	var culvert := sim.creatures[0]
	assert_true(_mash_until(sim, 0, L, "light_1"), "jab")
	assert_true(_mash_until(sim, 0, L, "light_2"), "second jab")
	assert_true(_mash_until(sim, 0, S1, "skill_1"), "Gulp cancelled from the jab")
	assert_eq(culvert.windup_total, 0, "a Gulp cancelled into has no windup:")


## Presses `bit` on alternate ticks until `side` starts `move_id`, like a player mashing.
func _mash_until(sim: MatchSim, side: int, bit: int, move_id: String) -> bool:
	var c := sim.creatures[side]
	var serial := c.attack_serial
	for i in 120:
		var inputs := [0, 0]
		inputs[side] = bit if i % 2 == 0 else 0
		sim.step(PackedInt32Array(inputs))
		if c.attack_serial != serial and c.move_id == move_id:
			return true
	return false


func test_a_jab_interrupts_a_raw_grab() -> void:
	var sim := _duel("cairn", "culvert")
	var cairn := sim.creatures[0]
	var culvert := sim.creatures[1]
	sim.step(PackedInt32Array([0, S1]))  # Culvert throws a raw Gulp
	assert_true(culvert.is_winding_up(), "Gulp winding up")
	run(sim, 0, 5)  # Cairn sees it, then jabs
	var grabbed := false
	var interrupted := false
	for i in 40:
		sim.step(PackedInt32Array([L if i == 0 else 0, 0]))
		for e in sim.events:
			if e["type"] == "grab":
				grabbed = true
		if culvert.state == CreatureSim.State.HITSTUN:
			interrupted = true
	assert_true(interrupted, "the jab should hit Culvert out of the windup")
	assert_false(grabbed, "the grab should never come out")
	assert_eq(cairn.state != CreatureSim.State.KNOCKDOWN, true, "Cairn wasn't swallowed:")


func test_reacting_to_a_raw_grab_with_a_dodge_works() -> void:
	# Gulp's tongue chases down the lane, so the roll goes sideways, out of it.
	var sim := _duel("cairn", "culvert")
	var cairn := sim.creatures[0]
	sim.step(PackedInt32Array([0, S1]))
	run(sim, 0, REACTION - 3)  # reaction time, then press dodge (input lag included)
	sim.step(PackedInt32Array([D | SimDefs.IN_UP, 0]))
	var grabbed := false
	for i in 60:
		sim.step(PackedInt32Array([0, 0]))
		for e in sim.events:
			if e["type"] == "grab":
				grabbed = true
	assert_false(grabbed, "dodging on reaction should beat a raw Gulp")
	assert_eq(cairn.hp, cairn.max_hp, "no damage taken:")


func test_dodge_pressed_during_a_freeze_all_comes_out() -> void:
	var sim := _duel("cairn", "culvert", 20.0)
	var cairn := sim.creatures[0]
	var culvert := sim.creatures[1]
	culvert.energy = 100.0
	sim.step(PackedInt32Array([0, SU]))
	assert_gt(sim.hitstop, 0, "Storm Drain freezes the screen")
	run(sim, 0, 6)
	sim.step(PackedInt32Array([D | SimDefs.IN_LEFT, 0]))  # react to the cut-in
	assert_gt(sim.hitstop, 0, "still frozen when dodge was pressed")
	var dodged := run_until(sim, func(): return cairn.state == CreatureSim.State.DODGE, 30)
	assert_true(dodged, "the dodge should come out when the freeze ends")
	var hit := false
	for i in 80:
		sim.step(PackedInt32Array([0, 0]))
		for e in sim.events:
			if e["type"] == "hit" and int(e["target"]) == 0:
				hit = true
	assert_false(hit, "dodging Storm Drain on reaction to the cut-in should avoid it")


## A 2 v 2 with Culvert (slot 0) next to a Cairn (slot 2); the other two far off.
func _crowd(gap := 20.0) -> TeamSim:
	var t := TeamSim.new([["culvert", "cairn"], ["cairn", "barkley"]], 2)
	var zero := PackedInt32Array()
	zero.resize(t.slot_count())
	while t.phase == TeamSim.Phase.INTRO:
		t.step(zero)
	var c := t.sim.floor_rect().get_center()
	var cs := t.sim.creatures
	cs[0].pos = c
	cs[2].pos = c + Vector2(cs[0].radius + cs[2].radius + gap, 0)
	cs[1].pos = c + Vector2(-140, -60)
	cs[3].pos = c + Vector2(-140, 60)
	return t


func _ins(n: int, first: int, at := 0) -> PackedInt32Array:
	var ins := PackedInt32Array()
	ins.resize(n)
	ins[at] = first
	return ins


func test_only_a_two_fighter_field_freezes_for_a_surge() -> void:
	assert_true(TeamSim.new([["cairn"], ["culvert"]], 1).sim.freeze_all, "a team match of 1 v 1 freezes")
	assert_false(TeamSim.new([["cairn", "culvert"], ["culvert", "cairn"]], 2).sim.freeze_all, "2 v 2 doesn't")
	assert_false(TeamSim.new([["cairn", "culvert", "barkley"], ["culvert", "cairn", "sno"]], 3).sim.freeze_all,
		"3 v 3 doesn't")
	assert_true(BrawlSim.new(["cairn", "culvert"]).sim.freeze_all, "a Brawl of two freezes")
	assert_false(BrawlSim.new(["cairn", "culvert", "sno"]).sim.freeze_all, "a Brawl of three doesn't")
	assert_true(MatchFactory.versus("cairn", "culvert").freeze_all, "a 1v1 freezes")
	assert_true(DuelSim.new([["cairn", "culvert"], ["culvert", "cairn"]]).sim.freeze_all,
		"a tag Duel (two on the field) freezes")


func test_every_surge_winds_up_long_enough_on_a_crowded_field() -> void:
	for id in MatchFactory.FIGHTERS:
		var mv: Dictionary = MatchFactory.load_def(String(id))["moves"].get("surge", {})
		if mv.is_empty():
			continue
		var wind := maxi(int(mv.get("windup", 0)), int(mv.get("crowd_windup", MatchSim.SURGE_CROWD_WINDUP)))
		var warning := wind + int(mv.get("startup", 0)) + 1
		assert_true(warning >= REACTION, "%s's Surge gives only %d frames of warning in a team fight"
			% [id, warning])


func test_a_surge_in_a_team_fight_winds_up_instead_of_freezing() -> void:
	var t := _crowd()
	var sim := t.sim
	var culvert := sim.creatures[0]
	culvert.energy = 100.0
	var far := sim.creatures[1]
	t.step(_ins(4, SU))
	assert_eq(sim.hitstop, 0, "nobody is frozen")
	assert_true(culvert.is_winding_up(), "the Surge winds up")
	assert_eq(culvert.windup_total, MatchSim.SURGE_CROWD_WINDUP, "windup length:")
	var seen := {}
	for e in sim.events:
		seen[String(e["type"])] = e
	assert_true(seen.has("windup"), "the windup tell is shown")
	assert_true(seen.has("surge") and not bool(seen["surge"]["freeze"]), "the surge event says no freeze")
	var from := far.pos
	for i in 6:
		t.step(_ins(4, SimDefs.IN_UP, 1))
	assert_gt(from.distance_to(far.pos), 1.0, "everyone else keeps moving through it")


## Whether Storm Drain hits the Cairn next to it, which dodges `react` ticks in (-1: never).
func _team_surge_hits(react: int) -> bool:
	var t := _crowd()
	var sim := t.sim
	sim.creatures[0].energy = 100.0
	t.step(_ins(4, SU))
	var hit := false
	for i in 100:
		t.step(_ins(4, D | SimDefs.IN_RIGHT if i == react else 0, 2))
		for e in sim.events:
			if e["type"] == "hit" and int(e["target"]) == 2:
				hit = true
	return hit


func test_dodge_on_reaction_to_a_team_fight_surge() -> void:
	assert_true(_team_surge_hits(-1), "Storm Drain hits a Cairn that stands there")
	# Reaction time, then press dodge (input lag included).
	assert_false(_team_surge_hits(REACTION - 3), "dodging Storm Drain on reaction to its windup should avoid it")
