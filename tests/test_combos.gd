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
	# Jab, Jab and Cross only deal damage (only the Hook staggers), so the Rush starts the
	# combo: no variety bonus on it.
	assert_near(dmg, 3 + 3 + 5 + (8 + 12), 0.05, "Jab, Jab, Cross > Rockslide Rush:")


func test_cairn_full_meter() -> void:
	var sim := _duel("cairn")
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"],
		[H, "heavy"], [S2, "skill_2"], [SU, "surge"]])
	var expected := 11.0 + (9 + 12) + 8 * 1.15 + 52 * 1.3  # the combo starts at the Haymaker; Avalanche doubled (Oct 2026)
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
	# The jabs only deal damage (they don't start a combo), so the hook is the combo's
	# first hit: no variety bonus.
	assert_near(dmg, 4 + 5 + 6, 0.05, "Jab, Jab > Gulp (tapped: the hook):")


## Runoff's full charge: tapped it's a short shove, held it's the wave that reaches a
## foe the Slam knocked back.
const RUNOFF_HOLD := 12


func test_culvert_shockwave() -> void:
	var sim := _duel("culvert")
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S2, "skill_2", RUNOFF_HOLD]])
	assert_near(dmg, 18 + 10 * 1.15 + 9 * 1.3, 0.05, "Jab, Jab, Hook > Slam > Runoff (held):")


func test_culvert_full_meter() -> void:
	var sim := _duel("culvert")
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"],
		[H, "heavy"], [S2, "skill_2", RUNOFF_HOLD], [SU, "surge"]])
	var expected := 18 + 10 * 1.15 + 9 * 1.3 + 30.8 * 1.5  # Storm Drain 22 x1.4 (area Surges, Oct 2026)
	assert_near(dmg, expected, 0.05, "Jab, Jab, Hook > Slam > Runoff (held) > Storm Drain:")


## Craglash (left) facing Cairn at close range.
func _craglash() -> MatchSim:
	var sim := MatchFactory.versus("craglash", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_craglash_rake_to_charge() -> void:
	var dmg := route(_craglash(), 0, [[L, "light_1"], [S1, "skill_1"]])
	assert_near(dmg, 6 + 8 * 1.15, 0.05, "Rake > Landslide Charge (no string since the Oct 25 2026 nerf):")


func test_craglash_stomp_launcher() -> void:
	var dmg := route(_craglash(), 0, [[L, "light_1"], [H, "heavy"], [S1, "skill_1"]])
	assert_near(dmg, 6 + 11 * 1.15 + 8 * 1.3, 0.05, "Rake > Rockslide Stomp > Landslide Charge:")


## Mountain Maw (the hook, now Skill 2) hauls a foe in from far away, crumpled, and the
## string follows. Bedrock is his Surge and finishes no combo: it holds foes for the team.
func test_craglash_hook_opener() -> void:
	var sim := _craglash()
	sim.creatures[1].pos.x += 100.0
	var dmg := route(sim, 0, [[S2, "skill_2"], [L, "light_1"], [H, "heavy"], [S1, "skill_1"]])
	assert_near(dmg, 6 + 6 * 1.15 + 11 * 1.3 + 8 * 1.3, 0.05,
		"Mountain Maw > Rake > Rockslide Stomp > Landslide Charge:")


## Barkley (left) facing Cairn at close range.
func _barkley() -> MatchSim:
	var sim := MatchFactory.versus("barkley", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_barkley_twister_into_pinecone() -> void:
	var dmg := route(_barkley(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S2, "skill_2"]])
	assert_near(dmg, 19 + 4 * 1.15 * 3 + 10 * 1.3, 0.05, "Twig, Bough, Log Drop > Timber Twister > Pinecone Bomb:")


func test_barkley_twister_into_branch_grab() -> void:
	var dmg := route(_barkley(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S1, "skill_1"]])
	assert_near(dmg, 19 + 4 * 1.15 * 3 + 8 * 1.3, 0.05, "3 lights > Timber Twister > Branch Grab:")


func test_barkley_full_meter() -> void:
	var sim := _barkley()
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"],
		[S1, "skill_1"], [SU, "surge"]])
	assert_near(dmg, 19 + 4 * 1.15 * 3 + 8 * 1.3 + (12.6 + 12.6 + 16.8) * 1.5, 0.05, "... > Root Eruption:")  # x1.4: an area Surge


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
	assert_near(dmg, 15 + 6 * 1.15 + 8 * 1.3 + 30.8 * 1.5, 0.05, "... > The One That Got Away:")  # x1.4: an area Surge


## Chef Cerebro (left) facing Cairn at close range. Since Oct 25 2026 the Mallet Toss
## doesn't stagger (Kevin's nerf), so nothing after the string is a combo: against a dummy
## that stands still the follow-up lands as a fresh hit (no variety bonus), and a real foe
## can block or dodge it.
func _cerebro() -> MatchSim:
	var sim := MatchFactory.versus("cerebro", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_cerebro_knives_out() -> void:
	var dmg := route(_cerebro(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S1, "skill_1"]])
	assert_near(dmg, 11 + 8, 0.05, "Flick, Flick, Mallet, then a fresh Cleaver Toss:")


func test_cerebro_tenderized() -> void:
	var dmg := route(_cerebro(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S1, "skill_1"]])
	# Tenderize softens Cairn up: the Cleaver after it lands 20% harder.
	assert_near(dmg, 11 + 7 + 8 * 1.2 * 1.15, 0.05, "3 lights, then Tenderize > Cleaver Toss:")


## Mise en place (Oct 2026 kit pass): on a tenderized foe the Mallet Toss staggers
## ("stagger_if"), so the Cleaver Toss after it is the same combo: the variety bonus, and
## everything 20% harder.
func test_cerebro_mise_en_place() -> void:
	var sim := _cerebro()
	sim.creatures[1].vuln = 400
	sim.creatures[1].vuln_mult = 1.2
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S1, "skill_1"]])
	assert_near(dmg, 11 * 1.2 + 8 * 1.2 * 1.15, 0.05, "tenderized: Flick, Flick, Mallet (staggers) > Cleaver Toss:")


func test_cerebro_flip_out_knife_flurry() -> void:
	var sim := _cerebro()
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S2, "skill_2"], [SU, "surge"]])
	assert_near(dmg, 11 + 7 + (4.2 * 7 + 8.4) * 1.15, 0.05, "3 lights, then Flip Out > Knife Flurry:")


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
	assert_near(dmg, 14 + 8 * 1.15 + 3 * 1.3 + 36 * 1.5, 0.05, "... > Venom Spit > Petrify Punch:")  # x2: a single-target Surge


## Digby (left) facing Cairn at close range.
func _digby() -> MatchSim:
	var sim := MatchFactory.versus("digby", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_digby_claws_and_flash() -> void:
	var dmg := route(_digby(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [S1, "skill_1"]])
	assert_near(dmg, 20 + 2 * 1.15, 0.05, "Swipe, Swipe, Pickaxe > Headlamp Flash:")  # 6 + 6 + 8


func test_digby_pop_up_cave_in() -> void:
	var sim := _digby()
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [SU, "surge"]])
	assert_near(dmg, 20 + 10 * 1.15 + 19.6 * 1.3, 0.05, "3 lights > Pickaxe Pop-Up > Cave-In:")  # Pop-Up 10 since the Oct 2026 kit pass


## Sneaky Pete (left) facing Cairn at close range.
func _pete() -> MatchSim:
	var sim := MatchFactory.versus("pete", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_pete_sack_smack_pickpocket() -> void:
	var dmg := route(_pete(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S2, "skill_2"]])
	assert_near(dmg, 17 + 9 * 1.15 + 5 * 1.3, 0.05, "3 lights > Sack Smack > Pickpocket:")  # 5 + 5 + 7 since the Oct 2026 assassin pass


func test_pete_big_heist() -> void:
	var sim := _pete()
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S2, "skill_2"],
		[SU, "surge"]])
	# After Pickpocket his hits land 10% harder (stolen power): the whole Heist does.
	assert_near(dmg, 17 + 9 * 1.15 + 5 * 1.3 + (5 * 6 + 20) * 1.5 * 1.1, 0.05, "... > The Big Heist:")


## Sno Mercy (left) facing Cairn at close range.
func _sno() -> MatchSim:
	var sim := MatchFactory.versus("sno", "cairn")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + 2, 164)
	return sim


func test_sno_ice_spray_slush_slide() -> void:
	var dmg := route(_sno(), 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [S2, "skill_2"]])
	assert_near(dmg, 21 + 12 * 1.15 + 10 * 1.3, 0.05, "Cold Cross, Brain Freeze > Shaved Ice > Slush Slide:")


func test_sno_flavor_blast() -> void:
	var sim := _sno()
	sim.creatures[0].energy = 100.0
	var dmg := route(sim, 0, [[L, "light_1"], [L, "light_2"], [L, "light_3"], [H, "heavy"], [SU, "surge"]])
	assert_near(dmg, 21 + 12 * 1.15 + 22.4 * 1.3, 0.05, "... > Shaved Ice > Flavor Blast:")  # x1.4: an area Surge


## Ambush openers into the lights ("ambush_flinch"): out of stealth, Digby's and Pete's jabs
## stagger for the ambush window, so the opener starts a real combo. A training dummy stands
## still; the attacker holds toward it like a player and mashes each button until its move
## starts. Returns the "combo" count of every hit he lands, in order; `downed` is set when
## the dummy is knocked down (invulnerable) before the last step's move starts.
func _ambush_string(fighter: String, gap: float, steps: Array) -> Dictionary:
	var sim := MatchFactory.training(fighter)
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	a.pos = Vector2(200, 164)
	d.pos = Vector2(200 + a.radius + d.radius + gap, 164)
	var combos: Array[int] = []
	var downed := false
	for s in steps:
		var serial := a.attack_serial
		var press := true
		var started := false
		for i in 160:
			sim.step(PackedInt32Array([(int(s[0]) if press else 0) | SimDefs.move_bits(d.pos - a.pos), 0]))
			press = not press
			for e in sim.events:
				if String(e["type"]) == "hit" and int(e["attacker"]) == a.id:
					combos.append(int(e["combo"]))
			if d.state == CreatureSim.State.KNOCKDOWN:
				downed = true
			if a.attack_serial != serial and a.move_id == String(s[1]):
				started = true
				break
		if not started:
			fail("%s never reached %s (combo %d)" % [fighter, s[1], d.combo_hits])
			return {"combos": combos, "downed": downed}
	for i in 60:  # the last move plays out
		sim.step(PackedInt32Array([0, 0]))
		for e in sim.events:
			if String(e["type"]) == "hit" and int(e["attacker"]) == a.id:
				combos.append(int(e["combo"]))
	return {"combos": combos, "downed": downed}


func test_digby_burrow_into_the_claws() -> void:
	# The pop-up launches; out of the ambush his first two swipes juggle like the Pickaxe.
	# Each of the three lights uses a juggle point (JUGGLE_MAX), so the string ends there.
	var r := _ambush_string("digby", 96.0, [[S2, "skill_2"], [L, "light_1"], [L, "light_2"], [L, "light_3"]])
	assert_eq(r["combos"], [1, 2, 3, 4], "Burrow > Swipe, Swipe, Pickaxe, one combo:")
	assert_false(r["downed"], "the dummy is kept up until the last light")


func test_digby_burrow_into_the_pop_up() -> void:
	# His real Burrow route: two swipes, then the Pickaxe Pop-Up takes the third juggle point.
	var r := _ambush_string("digby", 96.0, [[S2, "skill_2"], [L, "light_1"], [L, "light_2"], [H, "heavy"]])
	assert_eq(r["combos"], [1, 2, 3, 4], "Burrow > Swipe, Swipe > Pickaxe Pop-Up, one combo:")
	assert_false(r["downed"], "no knockdown mid-string")


func test_pete_pickpocket_into_the_jabs() -> void:
	var r := _ambush_string("pete", 40.0, [[S1, "skill_1"], [S2, "skill_2"], [L, "light_1"], [L, "light_2"], [L, "light_3"]])
	assert_eq(r["combos"], [1, 2, 3, 4], "Tiptoe > Pickpocket > Jab, Jab, Bag Swing, one combo:")
	assert_false(r["downed"], "no knockdown mid-string")
