extends TestCase
## Craglash's kit: Stoneskin's shield, Bedrock (his Surge: armor, taunt, drag and release),
## Mountain Maw (his hook: unblockable, hauls in and crumples), and the full combo route.

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


## Craglash (with a full meter) starts Bedrock and holds it until the armor sets.
func _bedrock(sim: MatchSim, p1 := 0) -> void:
	var crag := sim.creatures[0]
	crag.energy = 100.0
	var armored := run_until(sim, func(): return crag.is_armored(), 80, SU, p1)
	assert_true(armored, "Bedrock should be armored once its freeze and windup are over")


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


func test_bedrock_is_the_surge_and_costs_the_meter() -> void:
	var sim := _duel()
	var crag := sim.creatures[0]
	assert_false(crag.can_use("surge"), "no meter, no Bedrock")
	crag.energy = 100.0
	run(sim, SU, 1)
	assert_eq(crag.move_id, "surge", "Bedrock is the Surge:")
	assert_eq(String(crag.def["moves"]["surge"]["name"]), "Bedrock")
	assert_near(crag.energy, 0.0, 0.001, "and it spends the meter:")


func test_bedrock_armor_takes_hits_without_flinching() -> void:
	var sim := _duel()
	var crag := sim.creatures[0]
	crag.shield = 0.0
	_bedrock(sim)
	var start := crag.pos
	var hp := crag.hp
	var armored := run_until(sim, func(): return _has_event(sim, "armor"), 30, 0, L)
	assert_true(armored, "Cairn's jab should land on the armor")
	run(sim, 0, 10)
	assert_eq(crag.state, CreatureSim.State.ATTACK, "still in Bedrock, not in hitstun:")
	assert_eq(crag.move_id, "surge")
	assert_near(crag.pos.x, start.x, 0.001, "rooted in place:")
	var jab := float(sim.creatures[1].def["moves"]["light_1"]["damage"])
	var reduction := float(crag.def["moves"]["surge"]["armor"]["reduction"])
	assert_near(hp - crag.hp, jab * (1.0 - reduction), 0.01, "armor damage:")


func test_bedrock_holds_for_three_seconds() -> void:
	var sim := _duel("cairn", 10.0)
	var crag := sim.creatures[0]
	_bedrock(sim)
	run(sim, 0, 150)
	assert_eq(crag.move_id, "surge", "still rooted and armored 2.5 s in:")
	assert_true(crag.is_armored(), "")
	run(sim, 0, 40)
	assert_eq(crag.state, CreatureSim.State.IDLE, "and free again after about 3 s:")


func test_a_grab_goes_through_bedrock() -> void:
	var sim := _duel("culvert")
	var crag := sim.creatures[0]
	_bedrock(sim)
	var grabbed := run_until(sim, func(): return _has_event(sim, "swallow"), 60, 0, S1)
	assert_true(grabbed, "a held Gulp should swallow Craglash out of Bedrock")
	assert_eq(crag.state, CreatureSim.State.AIRBORNE, "carried out of the stance:")


func test_bedrock_taunts_and_turns_attacks_toward_craglash() -> void:
	var sim := _duel("cairn", 10.0)
	var cairn := sim.creatures[1]
	_bedrock(sim)
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
	var release := int(crag.def["moves"]["surge"]["armor"]["release_from"])
	_bedrock(sim)
	run_until(sim, func(): return crag.state_t >= release + 2, 40)
	assert_eq(crag.move_id, "surge", "still holding Bedrock")
	run(sim, H, 2)
	assert_eq(crag.move_id, "heavy", "released into Rockslide Stomp:")
	assert_eq(crag.windup_total, 0, "a release skips the raw windup:")


func test_bedrock_reaches_far_and_drags_the_taunted_in_fast() -> void:
	var sim := _duel("cairn", 170.0)
	var crag := sim.creatures[0]
	var cairn := sim.creatures[1]
	var d0 := cairn.pos.distance_to(crag.pos)
	_bedrock(sim)
	assert_gt(float(cairn.taunt), 0.0, "taunted from 170 px away")
	var pull := float(crag.def["moves"]["surge"]["taunt"]["pull"])
	assert_near(cairn.taunt_pull, pull, 0.001, "the taunt's own pull, not the default:")
	assert_gt(pull, CreatureSim.TAUNT_PULL, "and it drags harder than a plain taunt")
	run(sim, 0, 60)
	assert_lt(cairn.pos.distance_to(crag.pos), d0 - 60.0, "dragged a long way in one second:")


func test_a_taunt_without_a_pull_key_uses_the_default() -> void:
	var sim := _duel("cairn", 10.0)
	var cairn := sim.creatures[1]
	sim.creatures[0]._taunt({"radius": 90, "ticks": 60}, sim)
	assert_near(cairn.taunt_pull, CreatureSim.TAUNT_PULL, 0.001, "")


func test_lights_are_slow() -> void:
	var mv: Dictionary = MatchFactory.load_def("craglash")["moves"]
	assert_gt(float(mv["light_1"]["startup"]), 6.0, "a heavy, deliberate Rake (others start in 4-5):")
	assert_eq(String(mv["light_1"].get("next", "")), "", "and no string after it (Oct 25 2026 nerf):")
	assert_false(mv.has("light_2"), "no Backhand")


func test_landslide_charge_stuns_for_a_quarter_second() -> void:
	var sim := _duel("cairn", 40.0)
	var cairn := sim.creatures[1]
	var stunned := run_until(sim, func(): return cairn.state == CreatureSim.State.CRUMPLE, 60, S1)
	assert_true(stunned, "the charge reaches 40 px and stuns")
	assert_lt(float(cairn.stun), 17.0, "briefly: about a quarter second:")
	assert_gt(float(cairn.stun), 10.0, "")


func test_mountain_maw_is_a_skill_on_a_cooldown() -> void:
	var sim := _duel("cairn", 100.0)
	var crag := sim.creatures[0]
	run(sim, S2, 1)
	assert_eq(crag.move_id, "skill_2", "Mountain Maw is Skill 2:")
	assert_near(crag.energy, 0.0, 0.001, "and costs no meter:")
	assert_eq(int(crag.cooldowns["skill_2"]), int(crag.def["moves"]["skill_2"]["cooldown"]), "on cooldown:")
	assert_gt(int(crag.def["moves"]["skill_2"]["cooldown"]), 180, "a long one (about 3.3 s since the Oct 2026 kit pass):")


func test_mountain_maw_bites_from_far_hauls_in_and_crumples() -> void:
	var sim := _duel("cairn", 120.0)
	var crag := sim.creatures[0]
	var cairn := sim.creatures[1]
	var bit := run_until(sim, func(): return _has_event(sim, "pull"), 120, S2)
	assert_true(bit, "the head reaches Cairn 120 px away")
	assert_eq(cairn.state, CreatureSim.State.CRUMPLE, "crumpled, not knocked up:")
	run(sim, 0, 20)
	assert_lt(cairn.pos.distance_to(crag.pos), 50.0, "and hauled in to Craglash:")
	assert_eq(cairn.state, CreatureSim.State.CRUMPLE, "still crumpled when it arrives:")


func test_mountain_maw_is_shorter_than_it_was_as_a_surge() -> void:
	var sim := _duel("cairn", 200.0)
	var bit := run_until(sim, func(): return _has_event(sim, "pull"), 120, S2)
	assert_false(bit, "200 px is out of the hook's reach now")


func test_mountain_maw_cant_be_blocked() -> void:
	var sim := _duel("cairn", 100.0)
	var cairn := sim.creatures[1]
	var bit := false
	for i in 120:
		sim.step(PackedInt32Array([S2 if i < 3 else 0, SimDefs.IN_GUARD]))
		if _has_event(sim, "pull"):
			bit = true
			break
	assert_true(bit, "guarding doesn't stop it")
	assert_eq(cairn.state, CreatureSim.State.CRUMPLE, "")


func test_mountain_maw_can_be_dodged() -> void:
	var sim := _duel("cairn", 100.0)
	var cairn := sim.creatures[1]
	var dodged := false
	for i in 120:
		var p1 := 0
		if not dodged and not sim.projectiles.is_empty():
			var pr: Dictionary = sim.projectiles[0]
			if Vector2(pr["pos"]).distance_to(cairn.pos) < 60.0:
				p1 = SimDefs.IN_DODGE | SimDefs.IN_DOWN
				dodged = true
		sim.step(PackedInt32Array([S2 if i < 3 else 0, p1]))
	assert_true(dodged, "Cairn dodged")
	assert_near(cairn.hp, cairn.max_hp, 0.001, "a dodge through the bite beats it:")


func test_mountain_maw_links_into_the_light_string() -> void:
	var sim := _duel("cairn", 100.0)
	var crag := sim.creatures[0]
	var cairn := sim.creatures[1]
	var bit := run_until(sim, func(): return _has_event(sim, "pull"), 120, S2)
	assert_true(bit, "hooked")
	run_until(sim, func(): return crag.state == CreatureSim.State.IDLE, 60)
	var raked := run_until(sim, func(): return crag.move_id == "light_1" and crag.connected, 40, L)
	assert_true(raked, "a Rake lands on the crumpled foe once the hook recovers")
	assert_gt(int(cairn.combo_hits), 1, "in the same combo:")


# ------------------------------------------------------------------ Landslide Ram

func test_the_ram_covers_about_a_normal_roll() -> void:
	# Half the old ram's distance since the Oct 25 2026 nerf (it was twice a roll).
	var sim := _duel("cairn", 300.0)
	var crag := sim.creatures[0]
	var cairn := sim.creatures[1]
	var x0 := crag.pos.x
	var x1 := cairn.pos.x
	run(sim, SimDefs.IN_DODGE | RIGHT, 1, SimDefs.IN_DODGE | RIGHT)
	run(sim, 0, 30)
	var crag_d := crag.pos.x - x0
	var cairn_d := cairn.pos.x - x1
	assert_near(crag_d, cairn_d, cairn_d * 0.2, "Craglash's dash (%.0f px) is about Cairn's roll (%.0f px)" % [crag_d, cairn_d])


func test_the_ram_costs_its_share_of_the_bar() -> void:
	var sim := _duel("cairn", 100.0)
	var crag := sim.creatures[0]
	var cost := crag.dodge_cost
	assert_near(cost, crag.max_stamina * CreatureSim.dodge_share("craglash"), 0.001, "the same share as any dodge:")
	run(sim, SimDefs.IN_DODGE | RIGHT, 1)
	assert_near(crag.stamina, crag.max_stamina - cost, 0.01, "spent on the dash:")
	run(sim, 0, 30)
	assert_false(crag.can_dodge(), "no second dash straight after")


func test_the_ram_hits_the_foe_in_its_path_and_stops_there() -> void:
	var sim := _duel("cairn", 25.0)
	var crag := sim.creatures[0]
	var cairn := sim.creatures[1]
	var hp := cairn.hp
	var hit := run_until(sim, func(): return _has_event(sim, "hit"), 30, SimDefs.IN_DODGE | RIGHT)
	assert_true(hit, "the dash connects with Cairn 25 px away")
	assert_near(hp - cairn.hp, float(crag.def["dodge"]["ram"]["damage"]), 0.01, "a small hit:")
	assert_eq(cairn.state, CreatureSim.State.HITSTUN, "a little stun:")
	assert_eq(int(cairn.combo_hits), 1, "it counts in the combo:")
	assert_eq(crag.state, CreatureSim.State.IDLE, "and the dash ends on the impact:")
	assert_lt(int(crag.state_t), 2, "")


func test_the_ram_links_into_the_rake() -> void:
	var sim := _duel("cairn", 25.0)
	var crag := sim.creatures[0]
	var cairn := sim.creatures[1]
	run_until(sim, func(): return _has_event(sim, "hit"), 30, SimDefs.IN_DODGE | RIGHT)
	var raked := run_until(sim, func(): return crag.move_id == "light_1" and crag.connected, 30, L)
	assert_true(raked, "a Rake lands on the stunned foe")
	assert_eq(int(cairn.combo_hits), 2, "ram, Rake: one combo:")
	assert_gt(float(cairn.combo_damage), 4.0 + 6.0 - 0.01, "")


func test_the_ram_hits_once_per_dash() -> void:
	var sim := _duel("cairn", 25.0)
	var hits := 0
	for i in 40:
		sim.step(PackedInt32Array([SimDefs.IN_DODGE | RIGHT if i == 0 else 0, 0]))
		for e in sim.events:
			if String(e["type"]) == "hit":
				hits += 1
	assert_eq(hits, 1, "one impact, then the dash is over:")


func test_the_ram_into_the_wall_cracks_the_floor_and_ends_the_dash() -> void:
	var sim := _duel("cairn", 200.0)
	var crag := sim.creatures[0]
	crag.pos.x = crag.floor_min().x + 30.0
	var intact := sim.terrain.count(TerrainGrid.INTACT)
	var hit_wall := run_until(sim, func(): return _has_event(sim, "ram_wall"), 30, SimDefs.IN_DODGE | LEFT)
	assert_true(hit_wall, "the dash reaches the wall 30 px away")
	assert_eq(crag.state, CreatureSim.State.IDLE, "and ends there:")
	assert_lt(sim.terrain.count(TerrainGrid.INTACT), intact, "the floor cracked under the impact:")


func test_the_ram_keeps_its_invincible_frames() -> void:
	var sim := _duel("cairn", 200.0)
	var crag := sim.creatures[0]
	var dg: Dictionary = crag.def["dodge"]
	run(sim, SimDefs.IN_DODGE | RIGHT, 1)
	run(sim, 0, int(dg["iframes_start"]))
	assert_true(crag.is_invulnerable(), "still a dodge: untouchable in its middle")


# ------------------------------------------------------------------ the slower pass

func test_stoneskin_waits_seven_seconds_out_of_combat() -> void:
	var skin: Dictionary = MatchFactory.load_def("craglash")["stoneskin"]
	assert_eq(int(skin["delay"]), 420, "seven seconds without combat:")
	assert_true(bool(skin.get("reset_on_deal", false)), "dealing damage counts as combat too")


func test_stoneskin_stays_down_while_craglash_keeps_hitting() -> void:
	var sim := _duel("cairn", 2.0)
	var crag := sim.creatures[0]
	var delay := int(crag.def["stoneskin"]["delay"])
	crag.shield = 0.0
	# He takes nothing, but rakes Cairn every second: that's still a brawl.
	for i in delay + 60:
		sim.step(PackedInt32Array([L if i % 60 == 0 else 0, 0]))
		sim.creatures[1].hp = sim.creatures[1].max_hp
	assert_near(crag.shield, 0.0, 0.001, "no shield while he's trading blows:")
	assert_lt(float(crag.calm_t), float(delay), "")
	# Then he stops, and seven seconds later it's back.
	assert_true(run_until(sim, func(): return crag.shield > 0.0, delay + 5),
		"the shield comes back once the fight leaves him alone")


func test_a_blocked_hit_counts_as_combat() -> void:
	var sim := _duel("cairn", 2.0)
	var crag := sim.creatures[0]
	crag.calm_t = 300
	var chipped := false
	for i in 40:
		sim.step(PackedInt32Array([L if i == 0 else 0, SimDefs.IN_GUARD]))
		for e in sim.events:
			chipped = chipped or String(e["type"]) == "block"
		if chipped:
			break
	assert_true(chipped, "Cairn blocks the Rake")
	assert_lt(float(crag.calm_t), 2.0, "the hit he had blocked reset his calm:")


func test_mashed_light_comes_out_once_every_two_seconds() -> void:
	# One Rake, then a 2 s cooldown: mashing light can't string or spam it (Oct 25 2026 nerf).
	var sim := _duel("cairn", 2.0)
	var crag := sim.creatures[0]
	var starts := []
	var was := ""
	var press := true
	for i in 300:
		sim.step(PackedInt32Array([L if press else 0, 0]))
		press = not press
		var now := crag.move_id if crag.state == CreatureSim.State.ATTACK else ""
		if now == "light_1" and was != "light_1":
			starts.append(i)
		was = now
	assert_eq(starts.size(), 3, "three Rakes in 5 s of mashing:")
	for k in range(1, starts.size()):
		assert_gt(float(starts[k] - starts[k - 1]), 119.0, "at least 2 s apart:")


func test_landslide_charge_cancels_from_the_rake() -> void:
	var sim := _duel("cairn", 2.0)
	var crag := sim.creatures[0]
	var cairn := sim.creatures[1]
	var hit := run_until(sim, func(): return crag.move_id == "light_1" and crag.connected, 60, L)
	assert_true(hit, "the Rake lands")
	var charged := run_until(sim, func(): return crag.move_id == "skill_1" and crag.connected, 60, S1)
	assert_true(charged, "the Charge lands after the Rake")
	assert_eq(int(cairn.combo_hits), 2, "as the second hit of the combo:")
