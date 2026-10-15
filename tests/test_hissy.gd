extends TestCase
## Hissy Fitz's kit: Venom Spit poisons over time, Stone Gaze slows whoever looks at her
## (more the longer they look, and not at all if they look away), and Petrify Punch
## turns the foe to stone until the next clean hit shatters it.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE
const GUARD := SimDefs.IN_GUARD


## Hissy Fitz on the left, `foe` on the right with `gap` pixels between their bodies,
## facing each other.
func _duel(foe := "cairn", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus("hissy", foe)
	sim.creatures[0].pos = Vector2(200, 164)
	sim.creatures[1].pos = Vector2(200 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


func _events(sim: MatchSim, kind: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e["type"]) == kind:
			out.append(e)
	return out


func test_venom_spit_poisons_from_range() -> void:
	var sim := _duel("cairn", 60.0)
	var foe := sim.creatures[1]
	var hit := run_until(sim, func(): return not _events(sim, "poisoned").is_empty(), 60, S1)
	assert_true(hit, "the spit reaches a foe 60 px away and poisons")
	var mv: Dictionary = sim.creatures[0].def["moves"]["skill_1"]
	var after_hit := foe.hp
	var pulses := 0
	for i in int(mv["poison_ticks"]) + 10:
		run(sim, 0, 1)
		pulses += _events(sim, "poison").size()
	var want := int(mv["poison_ticks"]) / int(mv["poison_every"])
	assert_eq(pulses, want, "poison pulses:")
	assert_near(after_hit - foe.hp, want * float(mv["poison_damage"]), 0.01, "poison damage over time:")
	assert_eq(foe.poison, 0, "and then it wears off:")


func test_poison_is_not_part_of_the_combo() -> void:
	var sim := _duel("cairn", 60.0)
	var foe := sim.creatures[1]
	run_until(sim, func(): return not _events(sim, "poisoned").is_empty(), 60, S1)
	run(sim, 0, 80)
	assert_eq(foe.combo_hits, 0, "the combo ended; the poison ticks on outside it:")
	assert_gt(float(foe.poison), 0.0, "still poisoned")


func test_stone_gaze_slows_more_the_longer_they_look() -> void:
	var sim := _duel("cairn", 60.0)
	var foe := sim.creatures[1]  # faces left, at her
	tap(sim, S2, 25)
	var early := foe.slow_mult
	assert_lt(early, 1.0, "slowed after a moment:")
	run(sim, 0, 60)
	assert_lt(foe.slow_mult, early - 0.15, "and slower the longer it lasts:")
	var g: Dictionary = sim.creatures[0].def["moves"]["skill_2"]["gaze"]
	run(sim, 0, 40)
	assert_near(foe.slow_mult, float(g["min_mult"]), 0.001, "down to the floor:")
	assert_gt(float(foe.slow), 0.0, "and it lingers after the gaze")


func test_looking_away_beats_the_gaze() -> void:
	var sim := _duel("cairn", 60.0)
	var foe := sim.creatures[1]
	foe.facing = Vector2.RIGHT  # turned away from her
	tap(sim, S2, 60)
	assert_eq(foe.slow, 0, "a foe looking away isn't slowed:")
	assert_true(_events(sim, "gaze").is_empty(), "no gaze effect")


func test_the_gaze_only_reaches_in_front_of_her() -> void:
	var sim := _duel("cairn", 60.0)
	var foe := sim.creatures[1]
	sim.creatures[0].facing = Vector2.LEFT  # she looks the other way
	foe.facing = Vector2.LEFT  # though Cairn looks at her back
	sim.creatures[0].prev_buttons = 0
	run(sim, SimDefs.IN_LEFT, 1)
	tap(sim, S2, 60)
	assert_eq(foe.slow, 0, "behind her, Cairn isn't slowed:")


func test_an_attack_breaks_out_of_the_gaze() -> void:
	var sim := _duel("cairn", 2.0)
	var hissy := sim.creatures[0]
	tap(sim, S2, 30)
	assert_eq(hissy.move_id, "skill_2", "gazing")
	var jabbed := run_until(sim, func(): return hissy.move_id == "light_1", 10, L)
	assert_true(jabbed, "a jab comes straight out of the gaze")


func test_petrify_punch_turns_the_foe_to_stone_and_a_hit_shatters_it() -> void:
	var sim := _duel("cairn", 2.0)
	var hissy := sim.creatures[0]
	var foe := sim.creatures[1]
	hissy.energy = 100.0
	var stoned := run_until(sim, func(): return not _events(sim, "petrify").is_empty(), 90, SU)
	assert_true(stoned, "the Petrify Punch lands")
	assert_eq(foe.state, CreatureSim.State.CRUMPLE, "stunned:")
	assert_gt(float(foe.stone), 60.0, "as a statue:")
	# Her recovery ends while the statue still stands; the next jab shatters it, harder.
	run_until(sim, func(): return hissy.state == CreatureSim.State.IDLE, 60)
	assert_gt(float(foe.stone), 0.0, "still stone when she can act again")
	var hp := foe.hp
	var shattered := run_until(sim, func(): return not _events(sim, "shatter").is_empty(), 30, L)
	assert_true(shattered, "the next clean hit shatters it")
	var jab := float(hissy.def["moves"]["light_1"]["damage"])
	# Still the Surge's combo, so the jab also gets the two-type variety bonus (x1.15).
	assert_near(hp - foe.hp, jab * MatchSim.STONE_SHATTER_MULT * 1.15, 0.01, "the shattering hit lands harder:")
	assert_eq(foe.stone, 0, "no longer stone:")


func test_petrify_pulls_a_foe_out_of_the_air() -> void:
	var sim := _duel("cairn", 2.0)
	sim.creatures[0].energy = 100.0
	var foe := sim.creatures[1]
	foe.enter_air(40, Vector2.ZERO)
	var stoned := run_until(sim, func(): return not _events(sim, "petrify").is_empty(), 90, SU)
	assert_true(stoned, "it hits the airborne foe")
	assert_eq(foe.state, CreatureSim.State.CRUMPLE, "a statue on the ground, not still flying:")


func test_rollback_with_poison_gaze_and_stone() -> void:
	var sim := _duel("culvert", 30.0)
	var foe := sim.creatures[1]
	foe.poison = 120
	foe.poison_dmg = 1.5
	foe.stone = 50
	foe.state = CreatureSim.State.CRUMPLE
	foe.stun = 50
	run_until(sim, func(): return sim.creatures[0].move_id == "skill_2", 20, S2)
	run(sim, 0, 10)
	var snap := sim.snapshot()
	run(sim, 0, 80, L)
	var once := sim.state_digest()
	sim.restore(snap)
	run(sim, 0, 80, L)
	assert_eq(sim.state_digest(), once, "replaying from the snapshot gives the same state:")


func test_poison_without_poison_every_pulses_at_the_default() -> void:
	var sim := _duel("cairn", 60.0)
	var foe := sim.creatures[1]
	sim.creatures[0].def = sim.creatures[0].def.duplicate(true)  # the factory caches defs; don't edit the shared one
	sim.creatures[0].def["moves"]["skill_1"].erase("poison_every")
	run_until(sim, func(): return not _events(sim, "poisoned").is_empty(), 60, S1)
	assert_eq(foe.poison_every, MatchSim.POISON_EVERY_DEFAULT, "a move that leaves it out gets the default, not every tick:")


# ------------------------------------------------------------------ Venom Frenzy (passive)

func test_four_hits_in_a_string_start_venom_frenzy() -> void:
	var sim := _duel("cairn", 12.0)
	var hissy := sim.creatures[0]
	# Jab, Jab, Hair Lash: three hits, not yet.
	route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"]])
	assert_eq(hissy.frenzy_t, 0, "three hits isn't enough")
	var sim2 := _duel("cairn", 12.0)
	var h2 := sim2.creatures[0]
	var f2 := sim2.creatures[1]
	route(sim2, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"]])
	assert_gt(h2.frenzy_t, 0, "the 4th hit (Coil Uppercut) starts the frenzy")
	assert_eq(f2.poison_stacks, 0, "the hit that starts it doesn't poison yet")


func test_frenzy_hits_stack_poison_up_to_five() -> void:
	var sim := _duel("cairn", 12.0)
	var hissy := sim.creatures[0]
	var foe := sim.creatures[1]
	var vf: Dictionary = hissy.def["venom_frenzy"]
	hissy.frenzy_t = int(vf["ticks"])
	for i in 7:
		route(sim, 0, [[L, "light_1"]])
		run(sim, 0, 20)
	assert_eq(foe.poison_stacks, int(vf["max_stacks"]), "stacks cap at %d:" % int(vf["max_stacks"]))
	var pulse := [0.0]
	run_until(sim, func():
		for e in sim.events:
			if String(e["type"]) == "poison" and int(e["who"]) == foe.id:
				pulse[0] = float(e["power"])
				return true
		return false, int(vf["poison_every"]) + 2)
	assert_near(pulse[0], float(vf["poison_damage"]) * int(vf["max_stacks"]), 0.01, "a pulse at full stacks:")
	run(sim, 0, int(vf["poison_ticks"]) + 10)
	assert_eq(foe.poison, 0, "the poison wears off")
	assert_eq(foe.poison_stacks, 0, "and the stacks with it")


func test_a_slow_string_doesnt_count_and_the_frenzy_ends() -> void:
	var sim := _duel("cairn", 12.0)
	var hissy := sim.creatures[0]
	var gap := int(hissy.def["venom_frenzy"]["streak_gap"])
	for i in 4:  # four jabs, each well after the last: not a string
		route(sim, 0, [[L, "light_1"]])
		run(sim, 0, gap + 20)
	assert_eq(hissy.frenzy_t, 0, "four hits far apart don't start it")
	hissy.frenzy_t = 5
	run(sim, 0, 10)
	assert_eq(hissy.frenzy_t, 0, "it runs out")


func test_frenzy_state_rolls_back() -> void:
	var sim := _duel("cairn", 12.0)
	var hissy := sim.creatures[0]
	hissy.frenzy_t = 100
	route(sim, 0, [[L, "light_1"]])
	var snap := sim.snapshot()
	var stacks := sim.creatures[1].poison_stacks
	run(sim, 0, 40)
	sim.restore(snap)
	assert_eq(sim.creatures[1].poison_stacks, stacks, "stacks restored")
	assert_gt(sim.creatures[0].frenzy_t, 0, "frenzy restored")
