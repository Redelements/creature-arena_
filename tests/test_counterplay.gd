extends TestCase
## Counterplay: big moves thrown raw must be readable and answerable, and reacting to a
## Surge's freeze must work. Combo routes stay fast (see test_combos.gd).

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
	["culvert", "skill_1"], ["culvert", "skill_2"], ["craglash", "heavy"], ["craglash", "skill_1"]]


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
	var sim := _duel("cairn", "culvert")
	var cairn := sim.creatures[0]
	sim.step(PackedInt32Array([0, S1]))
	run(sim, 0, REACTION - 3)  # reaction time, then press dodge (input lag included)
	sim.step(PackedInt32Array([D | SimDefs.IN_LEFT, 0]))
	var grabbed := false
	for i in 60:
		sim.step(PackedInt32Array([0, 0]))
		for e in sim.events:
			if e["type"] == "grab":
				grabbed = true
	assert_false(grabbed, "dodging on reaction should beat a raw Gulp")
	assert_eq(cairn.hp, cairn.max_hp, "no damage taken:")


func test_dodge_pressed_during_a_surge_freeze_comes_out() -> void:
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
