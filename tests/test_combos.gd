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


## Craglash (left) facing Cairn at close range.
func _craglash() -> MatchSim:
	var sim := MatchFactory.versus("craglash", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_craglash_rake_to_lash() -> void:
	var dmg := route(_craglash(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S1, "skill_1"]])
	assert_near(dmg, 4 + 4 + 7 + 7 * 1.15, 0.05, "Rake, Backhand, Headbutt > Boulder Lash:")


func test_craglash_stomp_launcher() -> void:
	var dmg := route(_craglash(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"],
		[S1, "skill_1"]])
	assert_near(dmg, 15 + 8 * 1.15 + 7 * 1.3, 0.05, "3 lights > Rockslide Stomp > Boulder Lash:")


func test_craglash_full_meter() -> void:
	var sim := _craglash()
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"],
		[S1, "skill_1"], [SU, "surge"]])
	assert_near(dmg, 15 + 8 * 1.15 + 7 * 1.3 + 16 * 1.5, 0.05, "... > Avalanche Coil:")


## Barkley (left) facing Cairn at close range.
func _barkley() -> MatchSim:
	var sim := MatchFactory.versus("barkley", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_barkley_twister_into_pinecone() -> void:
	var dmg := route(_barkley(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S2, "skill_2"]])
	assert_near(dmg, 17 + 4 * 1.15 * 3 + 8 * 1.3, 0.05, "Twig, Bough, Log Drop > Timber Twister > Pinecone Bomb:")


func test_barkley_twister_into_branch_grab() -> void:
	var dmg := route(_barkley(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S1, "skill_1"]])
	assert_near(dmg, 17 + 4 * 1.15 * 3 + 6 * 1.3, 0.05, "3 lights > Timber Twister > Branch Grab:")


func test_barkley_full_meter() -> void:
	var sim := _barkley()
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"],
		[S1, "skill_1"], [SU, "surge"]])
	assert_near(dmg, 17 + 4 * 1.15 * 3 + 6 * 1.3 + (7 + 7 + 10) * 1.5, 0.05, "... > Root Eruption:")


## Gillbert (left) facing Cairn at close range.
func _gillbert() -> MatchSim:
	var sim := MatchFactory.versus("gillbert", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_gillbert_flop_chain() -> void:
	var dmg := route(_gillbert(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S1, "skill_1"]])
	assert_near(dmg, 15 + 8 * 1.15, 0.05, "Snout Jab, Tail Whip, Rod Flail > Flop Dash:")


func test_gillbert_splash_and_dash() -> void:
	var dmg := route(_gillbert(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S1, "skill_1"]])
	assert_near(dmg, 15 + 6 * 1.15 + 8 * 1.3, 0.05, "3 lights > Splash Zone > Flop Dash:")


func test_gillbert_full_meter() -> void:
	var sim := _gillbert()
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"],
		[S1, "skill_1"], [SU, "surge"]])
	assert_near(dmg, 15 + 6 * 1.15 + 8 * 1.3 + 22 * 1.5, 0.05, "... > The One That Got Away:")


## Chef Cerebro (left) facing Cairn at close range.
func _cerebro() -> MatchSim:
	var sim := MatchFactory.versus("cerebro", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_cerebro_knives_out() -> void:
	var dmg := route(_cerebro(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S1, "skill_1"]])
	assert_near(dmg, 11 + 8 * 1.15, 0.05, "Flick, Flick, Mallet > Cleaver Toss:")


func test_cerebro_tenderized() -> void:
	var dmg := route(_cerebro(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S1, "skill_1"]])
	# Tenderize softens Cairn up: the Cleaver after it lands 20% harder.
	assert_near(dmg, 11 + 7 * 1.15 + 8 * 1.2 * 1.3, 0.05, "3 lights > Tenderize > Cleaver Toss:")


func test_cerebro_flip_out_knife_flurry() -> void:
	var sim := _cerebro()
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S2, "skill_2"], [SU, "surge"]])
	assert_near(dmg, 11 + 7 * 1.15 + (3 * 7 + 6) * 1.3, 0.05, "3 lights > Flip Out > Knife Flurry:")


## Hissy Fitz (left) facing Cairn at close range.
func _hissy() -> MatchSim:
	var sim := MatchFactory.versus("hissy", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_hissy_one_two_venom() -> void:
	var dmg := route(_hissy(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S1, "skill_1"]])
	# The poison ticks afterwards aren't hits, so they don't count here.
	assert_near(dmg, 14 + 8 * 1.15 + 3 * 1.3, 0.05, "Jab, Jab, Hair Lash > Coil Uppercut > Venom Spit:")


func test_hissy_petrify_punch() -> void:
	var sim := _hissy()
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S1, "skill_1"],
		[SU, "surge"]])
	assert_near(dmg, 14 + 8 * 1.15 + 3 * 1.3 + 18 * 1.5, 0.05, "... > Venom Spit > Petrify Punch:")
