extends TestCase
## Every example combo from the design plan (Combat system tab) must connect and deal
## the planned damage. If tuning breaks a route, this file says which one.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE


## Cairn (left) facing Culvert (right) at close range, or the reverse.
func _duel(attacker: String) -> MatchSim:
	var sim: MatchSim
	if attacker == "cairn":
		sim = MatchFactory.versus("cairn", "culvert")
	else:
		sim = MatchFactory.versus("culvert", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_cairn_bread_and_butter() -> void:
	var sim := _duel("cairn")
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S2, "skill_2"]])
	assert_near(dmg, 3 + 3 + 5 + (8 + 12) * 1.15, 0.05, "Jab, Jab, Cross > Rockslide Rush:")


func test_cairn_full_meter() -> void:
	var sim := _duel("cairn")
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"],
		[H, "heavy"], [S2, "skill_2"], [SU, "surge"]])
	var expected := 11.0 + (9 + 12) * 1.15 + 8 * 1.3 + 26 * 1.5
	assert_near(dmg, expected, 0.05, "Jab, Jab, Cross > Haymaker > Rush > Avalanche:")


func test_cairn_counter_punish() -> void:
	var sim := _duel("cairn")
	var cairn := sim.creatures[0]
	var culvert := sim.creatures[1]
	# Cairn starts Slip as Culvert throws a jab into it.
	sim.step(PackedInt32Array([S1, L]))
	var countered := run_until(sim, func(): return cairn.move_id == "slip_counter", 20)
	assert_true(countered, "Slip should counter the jab")
	var dmg := hit_damage(sim, 0, 1)
	dmg += route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [L, "light_4"], [H, "heavy"]])
	var expected := 10.0 + (3 + 3 + 5 + 6) * 1.15 + (9 + 12) * 1.3
	assert_near(dmg, expected, 0.05, "Slip counter > 4 lights > Haymaker:")
	assert_false(culvert.is_stunned(), "combo over")


func test_culvert_guard_breaker() -> void:
	var sim := _duel("culvert")
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [S1, "skill_1"]])
	assert_near(dmg, 4 + 5 + 12 * 1.15, 0.05, "Jab, Jab > Gulp:")


func test_culvert_shockwave() -> void:
	var sim := _duel("culvert")
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S2, "skill_2"]])
	assert_near(dmg, 18 + 10 * 1.15 + 7 * 1.3, 0.05, "Jab, Jab, Hook > Slam > Runoff:")


func test_culvert_full_meter() -> void:
	var sim := _duel("culvert")
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"],
		[H, "heavy"], [S2, "skill_2"], [SU, "surge"]])
	var expected := 18 + 10 * 1.15 + 7 * 1.3 + 30 * 1.5
	assert_near(dmg, expected, 0.05, "Jab, Jab, Hook > Slam > Runoff > Storm Drain:")
