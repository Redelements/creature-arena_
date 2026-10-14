extends TestCase
## Craglash's kit: Stoneskin's shield, Bedrock's armor, taunt and release, Boulder
## Lash's slow, and the full combo route.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE
const LEFT := SimDefs.IN_LEFT
const RIGHT := SimDefs.IN_RIGHT


## Craglash on the left, `foe` right next to it on the right.
func _duel(foe := "cairn", gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus("craglash", foe)
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


func _has_event(sim: MatchSim, kind: String) -> bool:
	for e in sim.events:
		if String(e["type"]) == kind:
			return true
	return false


func test_stoneskin_soaks_damage_then_grows_back() -> void:
	var sim := _duel()
	var crag := sim.creatures[0]
	var full := float(crag.def["stoneskin"]["shield"])
	assert_near(crag.shield, full, 0.001, "starts with the shield up:")
	var hp := crag.hp
	tap(sim, 0, 20, L)  # Cairn jabs
	assert_near(crag.hp, hp, 0.001, "the jab only chipped the shield:")
	assert_lt(crag.shield, full, "shield after the jab")
	assert_true(run_until(sim, func(): return crag.shield >= full, int(crag.def["stoneskin"]["delay"]) + 5),
		"the shield should come back after a while without damage")


func test_breaking_the_shield_lets_damage_through() -> void:
	var sim := _duel()
	var crag := sim.creatures[0]
	crag.shield = 1.0
	var hp := crag.hp
	var broke := run_until(sim, func(): return _has_event(sim, "shield_break"), 30, 0, L)
	assert_true(broke, "a jab breaks a 1-point shield")
	assert_lt(crag.hp, hp, "the rest of the jab reaches hp")


func test_bedrock_armor_takes_hits_without_flinching() -> void:
	var sim := _duel()
	var crag := sim.creatures[0]
	crag.shield = 0.0
	tap(sim, S2, 5)
	assert_true(crag.is_armored(), "Bedrock should be armored a few frames in")
	var start := crag.pos
	var hp := crag.hp
	var armored := run_until(sim, func(): return _has_event(sim, "armor"), 30, 0, L)
	assert_true(armored, "Cairn's jab should land on the armor")
	run(sim, 0, 10)
	assert_eq(crag.state, CreatureSim.State.ATTACK, "still in Bedrock, not in hitstun:")
	assert_eq(crag.move_id, "skill_2")
	assert_near(crag.pos.x, start.x, 0.001, "rooted in place:")
	var jab := float(sim.creatures[1].def["moves"]["light_1"]["damage"])
	var reduction := float(crag.def["moves"]["skill_2"]["armor"]["reduction"])
	assert_near(hp - crag.hp, jab * (1.0 - reduction), 0.01, "armor damage:")


func test_a_grab_goes_through_bedrock() -> void:
	var sim := _duel("culvert")
	var crag := sim.creatures[0]
	tap(sim, S2, 3)
	var grabbed := run_until(sim, func(): return _has_event(sim, "grab"), 60, 0, S1)
	assert_true(grabbed, "a held Gulp should swallow Craglash out of Bedrock")
	assert_eq(crag.state, CreatureSim.State.AIRBORNE, "carried out of the stance:")


func test_bedrock_taunts_and_turns_attacks_toward_craglash() -> void:
	var sim := _duel("cairn", 10.0)
	var cairn := sim.creatures[1]
	tap(sim, S2, 6)
	assert_gt(float(cairn.taunt), 0.0, "Cairn should be taunted")
	assert_lt(cairn.walk_speed(), float(cairn.def["speed"]), "taunted walking is slower")
	# Cairn tries to jab while holding right, away from Craglash.
	run(sim, 0, 1, RIGHT)
	run(sim, 0, 1, RIGHT | L)
	run_until(sim, func(): return cairn.state == CreatureSim.State.ATTACK, 10, 0, RIGHT)
	assert_eq(cairn.state, CreatureSim.State.ATTACK, "Cairn attacks")
	assert_lt(cairn.facing.x, -0.5, "a taunted attack swings at the taunter, not where it was aimed")


func test_bedrock_releases_into_any_attack_without_a_windup() -> void:
	var sim := _duel()
	var crag := sim.creatures[0]
	var release := int(crag.def["moves"]["skill_2"]["armor"]["release_from"])
	tap(sim, S2, release + 2)
	assert_eq(crag.move_id, "skill_2", "still holding Bedrock")
	run(sim, H, 2)
	assert_eq(crag.move_id, "heavy", "released into Rockslide Stomp:")
	assert_eq(crag.windup_total, 0, "a release skips the raw windup:")


func test_lights_are_slow() -> void:
	var mv: Dictionary = MatchFactory.load_def("craglash")["moves"]
	assert_gt(float(mv["light_1"]["startup"]), 6.0, "a heavy, deliberate Rake (others start in 4-5):")
	assert_gt(float(mv["light_3"]["startup"]), 9.0, "and a slow Headbutt:")


func test_landslide_charge_stuns_for_a_quarter_second() -> void:
	var sim := _duel("cairn", 40.0)
	var cairn := sim.creatures[1]
	var stunned := run_until(sim, func(): return cairn.state == CreatureSim.State.CRUMPLE, 60, S1)
	assert_true(stunned, "the charge reaches 40 px and stuns")
	assert_lt(float(cairn.stun), 17.0, "briefly: about a quarter second:")
	assert_gt(float(cairn.stun), 10.0, "")


func test_mountain_maw_bites_from_far_pulls_in_and_knocks_up() -> void:
	var sim := _duel("cairn", 150.0)
	var crag := sim.creatures[0]
	var cairn := sim.creatures[1]
	crag.energy = 100.0
	var bit := run_until(sim, func(): return _has_event(sim, "pull"), 120, SU)
	assert_true(bit, "the head reaches Cairn 150 px away")
	assert_true(cairn.is_airborne(), "knocked up")
	run_until(sim, func(): return not cairn.is_airborne(), 80)
	assert_lt(cairn.pos.distance_to(crag.pos), 50.0, "and hauled in to Craglash:")


func test_mountain_maw_cant_be_blocked() -> void:
	var sim := _duel("cairn", 100.0)
	sim.creatures[0].energy = 100.0
	var cairn := sim.creatures[1]
	var bit := false
	for i in 120:
		sim.step(PackedInt32Array([SU if i < 3 else 0, SimDefs.IN_GUARD]))
		if _has_event(sim, "pull"):
			bit = true
			break
	assert_true(bit, "guarding doesn't stop it")
	assert_true(cairn.is_airborne(), "")


func test_mountain_maw_can_be_dodged() -> void:
	var sim := _duel("cairn", 100.0)
	var crag := sim.creatures[0]
	crag.energy = 100.0
	var cairn := sim.creatures[1]
	var dodged := false
	for i in 120:
		var p1 := 0
		if not dodged and not sim.projectiles.is_empty():
			var pr: Dictionary = sim.projectiles[0]
			if Vector2(pr["pos"]).distance_to(cairn.pos) < 60.0:
				p1 = SimDefs.IN_DODGE | SimDefs.IN_DOWN
				dodged = true
		sim.step(PackedInt32Array([SU if i < 3 else 0, p1]))
	assert_true(dodged, "Cairn dodged")
	assert_near(cairn.hp, cairn.max_hp, 0.001, "a dodge through the bite beats it:")


func test_bedrock_drags_the_taunted_in() -> void:
	var sim := _duel("cairn", 60.0)
	var crag := sim.creatures[0]
	var cairn := sim.creatures[1]
	var d0 := cairn.pos.distance_to(crag.pos)
	tap(sim, S2, 60)
	assert_gt(float(cairn.taunt), 0.0, "taunted")
	assert_lt(cairn.pos.distance_to(crag.pos), d0 - 20.0, "and dragged in toward Craglash:")
