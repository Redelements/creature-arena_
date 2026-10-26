extends TestCase
## The class balance pass: the kit changes that came out of it (an armored Stomp, the
## stealth ambush, guard-breakers for the fighters that had none) and the matchups it
## targeted, measured with Normal CPUs on both sides (deterministic seeds, so these are
## exact, not flaky).

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const G := SimDefs.IN_GUARD
const NORMAL := 1  ## balance plays Normal CPUs, never Rage


func _duel(left: String, right: String, gap := 2.0) -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	return sim


func _events(sim: MatchSim, kind: String) -> int:
	var n := 0
	for e in sim.events:
		if String(e["type"]) == kind:
			n += 1
	return n


## Normal vs Normal, both sides, `seeds` games a side: wins for `a`.
func _wins(a: String, b: String, seeds := 5) -> Array:
	var w := 0
	var n := 0
	for s in seeds:
		for side in 2:
			var sim := MatchFactory.versus(a, b) if side == 0 else MatchFactory.versus(b, a)
			var cpus := [CpuController.new(0, NORMAL, 900 + s * 7 + side), CpuController.new(1, NORMAL, 950 + s * 13 + side)]
			for t in 7200:  # a 1v1 round (120 s)
				sim.step(PackedInt32Array([cpus[0].bits(sim), cpus[1].bits(sim)]))
				if sim.creatures[0].state == CreatureSim.State.KO or sim.creatures[1].state == CreatureSim.State.KO:
					break
			var me := sim.creatures[side]
			var foe := sim.creatures[1 - side]
			w += 1 if me.hp / me.max_hp > foe.hp / foe.max_hp else 0
			n += 1
	return [w, n]


# ------------------------------------------------------------------ kit changes

func test_rockslide_stomp_is_armored_once_its_windup_is_over() -> void:
	# Out of Bedrock (no windup) the Stomp can't be jabbed out of its startup: the jab
	# only chips it, and the Stomp lands.
	var sim := _duel("craglash", "cairn", 6.0)
	var crag := sim.creatures[0]
	var rel := int(crag.moves()["surge"]["armor"]["release_from"])
	crag.energy = 100.0
	run_until(sim, func(): return crag.is_armored(), 80, SimDefs.IN_SURGE)
	run_until(sim, func(): return crag.state_t >= rel + 1, 40)
	tap(sim, H, 1)
	assert_eq(crag.move_id, "heavy", "the Stomp answers out of Bedrock:")
	var armored := false
	var landed := false
	for t in 16:
		sim.step(PackedInt32Array([0, L if t == 1 else 0]))
		armored = armored or _events(sim, "armor") > 0
		for e in sim.events:
			if e["type"] == "hit" and int(e["attacker"]) == 0:
				landed = true
	assert_true(armored, "Cairn's jab only chips the armored Stomp")
	assert_eq(crag.move_id, "heavy", "and doesn't interrupt it:")
	assert_true(landed, "the Stomp lands")
	# Thrown raw, its windup is still open: a jab interrupts it.
	var sim2 := _duel("craglash", "cairn", 6.0)
	tap(sim2, H, 1)
	run(sim2, 0, 4, L)
	run(sim2, 0, 6)
	assert_eq(sim2.creatures[0].state, CreatureSim.State.HITSTUN, "a raw Stomp's tell can be jabbed:")


func test_a_strike_out_of_stealth_is_hidden_until_it_comes_out_and_hits_harder() -> void:
	var sim := _duel("pete", "cairn", 2.0)
	var pete := sim.creatures[0]
	var foe := sim.creatures[1]
	var base := float(pete.def["moves"]["light_1"]["damage"])
	pete.stealth = 100
	var hp := foe.hp
	tap(sim, L, 2)
	assert_gt(pete.stealth, 0, "still hidden through the jab's startup:")
	run_until(sim, func(): return foe.hp < hp, 20)
	assert_eq(pete.stealth, 0, "revealed as it lands:")
	assert_near(hp - foe.hp, base * float(pete.def["ambush"]), 0.05, "the sneak attack lands harder (x%.2f):" % float(pete.def["ambush"]))
	hp = foe.hp
	run(sim, 0, 30)
	tap(sim, L, 2)
	run_until(sim, func(): return foe.hp < hp, 20)
	assert_near(hp - foe.hp, base * float(pete.def["ambush"]), 0.05, "a jab inside the ambush window (ambush_ticks) lands harder too:")
	pete.ambush_t = 0  # the window has closed
	hp = foe.hp
	run(sim, 0, 30)
	tap(sim, L, 2)
	run_until(sim, func(): return foe.hp < hp, 20)
	assert_near(hp - foe.hp, base, 0.05, "after it, an ordinary jab:")


## The Mallet Toss gave Pete away until Oct 25 2026; since it stopped staggering, nothing in
## Cerebro's thrown string does (a ranged no_flinch hit keeps stealth).
func test_cerebros_thrown_string_doesnt_blow_petes_cover() -> void:
	var sim := _duel("cerebro", "pete", 60.0)
	var pete := sim.creatures[1]
	pete.stealth = 300
	pete.facing = Vector2.LEFT
	tap(sim, L, 30)  # a flick flies and hits
	assert_lt(pete.hp, pete.max_hp, "the flick hit")
	assert_gt(pete.stealth, 0, "but he stays hidden")
	var hp := pete.hp
	tap(sim, L, 2)
	tap(sim, L, 2)
	run(sim, 0, 20)
	tap(sim, L, 40)  # the third throw is the Mallet
	assert_lt(pete.hp, hp, "the rest of the string hit too")
	assert_gt(pete.stealth, 0, "and the Mallet doesn't give him away either:")


func test_pickpocket_homes_in_and_runs_on_through() -> void:
	var sim := _duel("pete", "cairn", 30.0)
	var pete := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.pos.y += 20  # off the line Pete faces
	var x0 := foe.pos.x
	var stole := false
	tap(sim, S2, 1)
	for t in 40:
		sim.step(PackedInt32Array([0, 0]))
		stole = stole or _events(sim, "steal") > 0
	assert_true(stole, "the dash steers onto a foe standing off-line")
	assert_gt(pete.pos.x, x0, "and runs on past him")


func test_every_fighter_has_a_guard_answer() -> void:
	# A grab or a guard-breaker (Sneaky Pete's only at a full charge: "hold"), so a turtle
	# can always be opened; the pass gave one to the fighters that had none. Three stay without on purpose: Gillbert's hook and
	# Barkley's Branch Grab are meant to be blockable, and Cairn opens people with his
	# Slip counter.
	for id in MatchFactory.FIGHTERS:
		if id in ["gillbert", "cairn", "barkley"]:
			continue
		var moves: Dictionary = MatchFactory.load_def(id)["moves"]
		var has := false
		for mid in moves:
			var mv: Dictionary = moves[mid]
			if bool(mv.get("grab", false)) or bool(mv.get("guard_break", false)) \
					or bool(mv.get("hold", {}).get("guard_break", false)):
				has = true
		assert_true(has, id + " can open a guard")


func test_the_new_guard_breakers_break_guards() -> void:
	# [fighter, button, gap, ticks to hold it]: Sneaky Pete's Sack Smack only breaks guard
	# held to a full charge.
	var pete_full := int(MatchFactory.load_def("pete")["moves"]["heavy"]["charge_max"]) + 2
	for pair in [["hissy", H, 4.0, 1], ["pete", H, 4.0, pete_full], ["sno", S2, 30.0, 1]]:
		var sim := _duel(String(pair[0]), "cairn", float(pair[2]))
		var broke := false
		for t in 90:
			sim.step(PackedInt32Array([int(pair[1]) if t < int(pair[3]) else 0, G]))
			broke = broke or _events(sim, "guard_break") > 0
		assert_true(broke, "%s breaks a guard" % pair[0])


func test_a_tapped_sack_smack_is_blocked_and_a_full_one_breaks_guard() -> void:
	var mv: Dictionary = MatchFactory.load_def("pete")["moves"]["heavy"]
	assert_false(bool(mv.get("guard_break", false)), "not a guard-breaker on a tap:")
	assert_true(bool(mv["hold"]["guard_break"]), "only held to the top:")
	assert_eq(String(mv["tell"]), "strong", "so its raw tell is the gold one:")
	for held in [1, 12, int(mv["charge_max"]) + 2]:
		var sim := _duel("pete", "cairn", 4.0)
		var broke := 0
		var blocked := 0
		for t in 90:
			sim.step(PackedInt32Array([H if t < held else 0, G]))
			broke += _events(sim, "guard_break")
			blocked += _events(sim, "block")
		if held > int(mv["charge_max"]):
			assert_eq(broke, 1, "a full charge breaks the guard:")
			assert_eq(blocked, 0, "")
		else:
			assert_eq(broke, 0, "held %d ticks, the Smack doesn't break guard:" % held)
			assert_eq(blocked, 1, "it's blocked:")
			assert_eq(sim.creatures[1].state, CreatureSim.State.GUARD, "Cairn is still guarding:")


func test_the_cpu_holds_sack_smack_to_a_full_charge_against_a_guard() -> void:
	var sim := _duel("pete", "cairn", 4.0)
	var cpu := CpuController.new(0, 3, 77)
	var broke := false
	for t in 600:
		sim.step(PackedInt32Array([cpu.bits(sim), G]))
		if _events(sim, "guard_break") > 0:
			broke = sim.creatures[0].move_id == "heavy" and sim.creatures[0].charge_ratio >= 1.0
			break
	assert_true(broke, "Rage Pete opens a turtle with a full Sack Smack")


# ------------------------------------------------------------------ matchups (Normal vs Normal)

# Balance is measured with Normal CPUs, never Rage (Kevin's ruling, Oct 25 2026: the Rage
# results didn't match how the game plays). Normal vs Normal on main first read assassins
# about 78% and both mages under 10%; the Normal mage AI (kiting) and the assassin pass that
# followed (Pete: ambush 1.2, Tiptoe 1.35x and 7 s, Pickpocket steals 10% every 4 s, lights
# 5/5/7, a slower Bag Swing, 170 HP; Digby: ambush 1.25; Cerebro: blink 90 px on a 1 s
# cooldown, a slower Mallet Toss) left this (bench_cpu.gd --matrix --seeds=5, wins against
# the field): Sno 69, Digby 66, Barkley 63, Hissy 62, Pete 60, Cerebro 55, Culvert 44,
# Cairn 43, Crease 39, Craglash 23, Gillbert 16. What holds of the class triangle is pinned
# here; what doesn't is written down instead:
#   - assassins beat Mister Crease (Pete about 75%, Digby about 55%), but not Chef Cerebro
#     (Pete about 40%, Digby about 10%: Normal Digby's Burrow engage doesn't reach a mage who
#     kites, so that is the CPU as much as the kit);
#   - Chef Cerebro beats the fighters and tanks (Hissy about 90%, Culvert 75%, Craglash 65%);
#     Mister Crease doesn't (Cairn about 5%);
#   - the fighters don't beat the assassins (Cairn 15-20%).
# Kevin's call for the pass: trim the assassins and nerf Cerebro a little, never buff a mage.


func test_no_assassin_runs_away_with_it() -> void:
	# Pete beat the field 85% before the pass (Cairn 10 of 10); now about 80% on Cairn and
	# 60% overall. Held loosely: he must drop a game to Cairn in 20.
	var r := _wins("pete", "cairn", 10)
	assert_lt(float(r[0]), float(r[1]), "Sneaky Pete doesn't sweep Cairn (%d of %d)" % r)


func test_assassins_beat_crease() -> void:
	var r := _wins("pete", "crease", 5)
	assert_gt(float(r[0]), r[1] * 0.5, "Sneaky Pete beats Mister Crease (%d of %d)" % r)


func test_cerebro_beats_fighters_and_tanks() -> void:
	for foe in ["hissy", "culvert", "craglash"]:
		var r := _wins("cerebro", foe, 4)
		assert_gt(float(r[0]), r[1] * 0.5, "Chef Cerebro beats %s (%d of %d):" % [foe, r[0], r[1]])


# ------------------------------------------------------------------ Culvert and Sno Mercy tweaks

## The cells a Slam leaves behind, as a sorted list of [x, y] in the grid.
func _damaged_cells(sim: MatchSim, value: int) -> Array:
	var out: Array = []
	for cy in sim.terrain.rows:
		for cx in sim.terrain.cols:
			if sim.terrain.get_cell(Vector2i(cx, cy)) == value:
				out.append([cx, cy])
	return out


func test_slam_leaves_the_same_rectangle_wherever_it_lands() -> void:
	# Facing right: a block 5 cells deep and 5 across (in front of him, clear of his own
	# feet), cracked; a second Slam there opens it.
	for x in [120.0, 123.0, 127.0]:
		var sim := MatchFactory.training()
		sim.creatures[0].pos = Vector2(x, 164)
		tap(sim, H, 40)
		var cracked := _damaged_cells(sim, TerrainGrid.CRACKED)
		assert_eq(cracked.size(), 25, "a 5x5 block of cracks from x=%d:" % int(x))
		var xs := cracked.map(func(c): return c[0])
		var ys := cracked.map(func(c): return c[1])
		assert_eq(xs.max() - xs.min() + 1, 5, "5 deep:")
		assert_eq(ys.max() - ys.min() + 1, 5, "5 across:")
		var feet := sim.terrain.world_to_cell(sim.creatures[0].pos)
		assert_true(xs.min() > feet.x + 1, "the block starts clear of his own feet (from x=%d):" % int(x))
		assert_eq(sim.terrain.count(TerrainGrid.HOLE), 0, "no holes from one plain Slam")
		tap(sim, H, 40)
		assert_eq(_damaged_cells(sim, TerrainGrid.HOLE).size(), 25, "the second Slam opens the whole block:")
	# Facing up: the same block, out in front of him (above).
	var sim2 := MatchFactory.training()
	sim2.creatures[0].pos = Vector2(200, 220)
	sim2.creatures[0].facing = Vector2.UP
	run(sim2, 0, 2, SimDefs.IN_UP)
	tap(sim2, H, 40)
	var cr := _damaged_cells(sim2, TerrainGrid.CRACKED)
	var xs2 := cr.map(func(c): return c[0])
	var ys2 := cr.map(func(c): return c[1])
	assert_eq(xs2.max() - xs2.min() + 1, 5, "facing up: 5 across:")
	assert_eq(ys2.max() - ys2.min() + 1, 5, "and 5 deep:")
	var feet2 := sim2.terrain.world_to_cell(sim2.creatures[0].pos)
	assert_true(ys2.max() < feet2.y - 1, "above him, clear of his feet")


func test_slam_is_quicker_and_still_gives_a_quarter_second_of_warning() -> void:
	var mv: Dictionary = MatchFactory.load_def("culvert")["moves"]["heavy"]
	assert_eq(int(mv["windup"]) + int(mv["startup"]) + 1, 15, "the warning floor, exactly:")
	assert_eq(int(mv["recovery"]), 18, "recovery cut by 30% (was 26):")
	assert_eq(int(mv["charge_max"]), 32, "a full charge 30% sooner (was 45):")


func test_culverts_holes_last_half_as_long_again() -> void:
	var sim := MatchFactory.training()
	sim.creatures[0].pos = Vector2(120, 164)
	tap(sim, H, 40)
	tap(sim, H, 40)
	var holes := sim.terrain.count(TerrainGrid.HOLE)
	assert_gt(holes, 0, "holes to time")
	run(sim, 0, TerrainGrid.HEAL_TICKS + 10)
	assert_eq(sim.terrain.count(TerrainGrid.HOLE), holes, "still open past the usual 12 s:")
	run(sim, 0, TerrainGrid.HEAL_TICKS / 2 + 10)
	assert_eq(sim.terrain.count(TerrainGrid.HOLE), 0, "mended after 18 s:")
	# Someone else's damage still mends on the usual clock.
	var sim2 := MatchFactory.versus("barkley", "cairn")
	sim2.creatures[0].energy = 100.0
	sim2.creatures[1].pos = Vector2(400, 100)
	tap(sim2, SimDefs.IN_SURGE, 60)  # Root Eruption cracks the floor
	assert_gt(sim2.terrain.count(TerrainGrid.CRACKED), 0, "Barkley cracked it")
	run(sim2, 0, TerrainGrid.HEAL_TICKS + 10)
	assert_eq(sim2.terrain.count(TerrainGrid.CRACKED), 0, "and it mended on the usual clock")


func test_runoff_is_a_cone_that_pushes_gently() -> void:
	var sim := _duel("culvert", "cairn", 20.0)
	var foe := sim.creatures[1]
	var x0 := foe.pos.x
	tap(sim, S2, 1)
	run_until(sim, func(): return foe.hp < foe.max_hp, 40)
	assert_lt(foe.hp, foe.max_hp, "the wave hits a foe in front")
	assert_true(sim.projectiles.is_empty(), "nothing flies: it's a cone, not a projectile")
	run(sim, 0, 30)
	var pushed := foe.pos.x - x0
	assert_gt(pushed, 12.0, "pushed back a little:")
	assert_lt(pushed, 45.0, "but gently:")
	assert_false(foe.is_airborne(), "and not launched")
	# A foe behind him is untouched.
	var sim2 := _duel("culvert", "cairn", 20.0)
	sim2.creatures[1].pos = sim2.creatures[0].pos - Vector2(30, 0)
	tap(sim2, S2, 40)
	assert_near(sim2.creatures[1].hp, sim2.creatures[1].max_hp, 0.001, "a foe behind is outside the cone:")


func test_syrup_slick_is_wider_stickier_and_lasts_longer() -> void:
	var z: Dictionary = MatchFactory.load_def("sno")["moves"]["skill_1"]["zone"]
	assert_eq(int(z["radius"]), 80, "radius doubled (was 40):")
	assert_eq(int(z["ticks"]), 450, "lasts 7.5 s (was 5):")
	assert_lt(float(z["slow_mult"]), 0.5, "slows a little more than half speed:")
	var sim := _duel("sno", "cairn", 50.0)
	var foe := sim.creatures[1]
	tap(sim, S1, 20)
	assert_eq(sim.zones.size(), 1, "one puddle down")
	run(sim, 0, 10)
	assert_gt(foe.slow, 0, "a foe 70 px away stands in it")


func test_the_red_guard_break_cue_shows_only_at_a_full_charge() -> void:
	var cm := int(MatchFactory.load_def("pete")["moves"]["heavy"]["charge_max"])
	for held in [8, cm + 2]:
		var sim := _duel("pete", "cairn", 40.0)
		var pete := sim.creatures[0]
		var shown := false
		for t in 60:
			sim.step(PackedInt32Array([H if t < held else 0, 0]))
			shown = shown or CreatureView.full_charge_breaks_guard(pete)
		assert_eq(shown, held > cm, "held %d ticks, the red GUARD BREAK cue:" % held)
	# A move-level guard-breaker (Hissy's Coil Uppercut) keeps its windup tell instead.
	var sim2 := _duel("hissy", "cairn", 40.0)
	var shown2 := false
	for t in 60:
		sim2.step(PackedInt32Array([H if t < cm + 2 else 0, 0]))
		shown2 = shown2 or CreatureView.full_charge_breaks_guard(sim2.creatures[0])
	assert_false(shown2, "")
