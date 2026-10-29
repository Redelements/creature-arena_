extends TestCase
## Caravan's plays and every mode's class perks: a rockslide down across the road at each
## checkpoint that the caravan has to be dug through (or smashed), the escort healing at
## the caravan, a new round putting the map back, rollback; and each class's perk in
## Caravan (push, dig, heal, contest, roll-back, respawn) and in Capture the Flag (carry,
## steady, knock, pass, claim, reach).

const TEAMS := [["cairn", "sno", "pete"], ["culvert", "digby", "hissy"]]


func _caravan(teams := TEAMS, size := 1, over := {}) -> TeamSim:
	var r := TeamSim.load_rules(TeamSim.CARAVAN_PATH)
	for k in over:
		r[k] = over[k]
	var t := TeamSim.new(teams, size, r)
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _ctf(teams: Array, size := 1) -> TeamSim:
	var t := TeamSim.new(teams, size, TeamSim.load_rules(TeamSim.CTF_PATH))
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _idle(t: TeamSim, ticks: int) -> void:
	for i in ticks:
		t.step(PackedInt32Array())
		for c in t.sim.creatures:
			c.walk_vel = Vector2.ZERO


## `ticks` ticks with the creatures in `with` standing at the caravan.
func _escort(t: TeamSim, with: Array, ticks: int) -> void:
	for i in ticks:
		for c in with:
			(c as CreatureSim).pos = t.caravan_pos()
		_idle(t, 1)


func _away(t: TeamSim, c: CreatureSim) -> void:
	c.pos = t.sim.terrain.nearest_solid(t.caravan_pos() + Vector2(0.0, 120.0 if t.caravan_pos().y < 220.0 else -120.0))


func _events(t: TeamSim, kind: String) -> Array:
	return t.sim.events.filter(func(e): return String(e["type"]) == kind)


## Pushes until the first checkpoint, returning the rockslide event (empty if none).
func _to_checkpoint(t: TeamSim, with: Array) -> Dictionary:
	t.cv_p = t.checkpoint_at(0) - 1.0
	for i in 60:
		for c in with:
			(c as CreatureSim).pos = t.caravan_pos()
		t.step(PackedInt32Array())
		var ev := _events(t, "rockslide")
		if not ev.is_empty():
			return ev[0]
	return {}


func _rubble_count(t: TeamSim) -> int:
	var n := 0
	for i in t.sim.terrain.cells.size():
		if t.sim.terrain.cells[i] == TerrainGrid.WALL and t.sim.terrain.base[i] != TerrainGrid.WALL:
			n += 1
	return n


# ------------------------------------------------------------------ rockslides

func test_a_checkpoint_brings_a_rockslide_down_ahead() -> void:
	var t := _caravan()
	var att := t.sim.creatures[0]
	var slide := _to_checkpoint(t, [att])
	assert_false(slide.is_empty(), "a rockslide at the checkpoint")
	assert_gt(float(_rubble_count(t)), 10.0, "rubble across the road (%d cells)" % _rubble_count(t))
	var at: Vector2 = slide["pos"]
	assert_gt(at.distance_to(t.caravan_pos()), 80.0, "ahead of the caravan, not on it")
	assert_lt(at.distance_to(t.track_point(t._cv_d(t.cv_p + 110.0))), 24.0, "on the road it's taking")


func test_the_caravan_stops_at_the_rubble_and_is_dug_through() -> void:
	var t := _caravan()
	var att := t.sim.creatures[0]
	_away(t, t.sim.creatures[1])
	_to_checkpoint(t, [att])
	var dug := false
	var stopped := false
	for i in 1200:
		att.pos = t.caravan_pos()
		var before := t.cv_p
		_idle(t, 1)
		if t.cv_state == 3:
			stopped = true
			assert_eq(t.cv_p, before, "held at the rubble")
		if not _events(t, "rubble_clear").is_empty():
			dug = true
			break
	assert_true(stopped, "it stopped at the rubble, digging")
	assert_true(dug, "and got dug through")
	var p := t.cv_p
	_escort(t, [att], 60)
	assert_gt(t.cv_p, p + 5.0, "then it rolls on")


func test_a_heavy_charge_smashes_rockslide_rubble() -> void:
	var t := _caravan()
	_to_checkpoint(t, [t.sim.creatures[0]])
	var cell := -1
	for i in t.sim.terrain.cells.size():
		if t.sim.terrain.cells[i] == TerrainGrid.WALL and t.sim.terrain.base[i] != TerrainGrid.WALL:
			cell = i
			break
	var c := Vector2i(cell % t.sim.terrain.cols, cell / t.sim.terrain.cols)
	assert_true(t.sim.terrain.smash(c), "rubble smashes like a rubble wall")
	assert_eq(t.sim.terrain.get_cell(c), TerrainGrid.CRACKED, "to cracked floor")


func test_a_new_round_puts_the_map_back() -> void:
	var t := _caravan()
	_to_checkpoint(t, [t.sim.creatures[0]])
	assert_gt(float(_rubble_count(t)), 0.0, "rubble down")
	t._cv_end_round()
	assert_eq(t.cv_round, 1, "round 2")
	assert_eq(_rubble_count(t), 0, "no rubble left from round 1")


func test_escorts_heal_at_the_caravan() -> void:
	var t := _caravan()
	var att := t.sim.creatures[0]
	var dfn := t.sim.creatures[1]
	_away(t, dfn)
	att.hp = att.max_hp * 0.5
	dfn.hp = dfn.max_hp * 0.5
	_escort(t, [att], 120)
	var per_sec := float(t.rules["escort_heal"])
	assert_near(att.hp, att.max_hp * 0.5 + per_sec * 2.0, 0.6, "the attacker healed %s a second:" % per_sec)
	assert_eq(dfn.hp, dfn.max_hp * 0.5, "the defender didn't")
	att.enter_hitstun(30, Vector2.ZERO)
	var hp := att.hp
	att.pos = t.caravan_pos()
	_idle(t, 5)
	assert_eq(att.hp, hp, "not while stunned")


func test_it_all_rolls_back_through_a_rockslide() -> void:
	var t := _caravan()
	var att := t.sim.creatures[0]
	_to_checkpoint(t, [att])
	var snap := t.snapshot()
	var d := t.state_digest()
	_escort(t, [att], 300)
	var after := t.state_digest()
	t.restore(snap)
	assert_eq(t.state_digest(), d, "restored")
	_escort(t, [att], 300)
	assert_eq(t.state_digest(), after, "and replays the same")


# ------------------------------------------------------------------ class perks: Caravan

## Progress after `ticks` with red's one fighter (`who`) pushing alone.
func _push_with(who: String, ticks: int) -> float:
	var t := _caravan([[who], ["culvert"]])
	_away(t, t.sim.creatures[1])
	_escort(t, [t.sim.creatures[0]], ticks)
	return t.cv_p


func test_a_tank_pushes_faster() -> void:
	var tank := _push_with("craglash", 300)
	var plain := _push_with("hissy", 300)
	assert_near(tank / plain, 1.3, 0.02, "Craglash (tank) vs Hissy (fighter):")


func test_a_bruiser_digs_faster() -> void:
	var ticks := {}
	for who in ["barkley", "hissy"]:
		var t := _caravan([[who], ["culvert"]])
		_away(t, t.sim.creatures[1])
		_to_checkpoint(t, [t.sim.creatures[0]])
		var digging := 0
		for i in 2000:
			t.sim.creatures[0].pos = t.caravan_pos()
			_idle(t, 1)
			if t.cv_state == 3:
				digging += 1
			if not _events(t, "rubble_clear").is_empty():
				ticks[who] = digging
				break
	assert_true(ticks.has("barkley") and ticks.has("hissy"), "both dug through")
	assert_near(float(ticks["hissy"]) / float(ticks["barkley"]), 2.0, 0.05, "Barkley (bruiser) digs twice as fast (%s)" % str(ticks))


func test_a_mage_doubles_the_escort_heal() -> void:
	var got := {}
	for who in ["cerebro", "hissy"]:
		var t := _caravan([[who], ["culvert"]])
		var c := t.sim.creatures[0]
		_away(t, t.sim.creatures[1])
		c.hp = c.max_hp * 0.4
		_escort(t, [c], 120)
		got[who] = c.hp - c.max_hp * 0.4
	assert_near(float(got["cerebro"]) / float(got["hissy"]), 2.0, 0.05, "Cerebro (mage) heals twice as fast:")


func test_a_fighter_wins_a_contest() -> void:
	# Hissy (fighter) attacking against Pete (assassin): contested, it creeps Hissy's way.
	var t := _caravan([["hissy"], ["pete"]])
	var p := t.cv_p
	_escort(t, [t.sim.creatures[0], t.sim.creatures[1]], 300)
	assert_eq(t.cv_state, 2, "contested")
	assert_gt(t.cv_p, p + 3.0, "and still creeping forward")
	# Two fighters: no edge, it holds (Culvert is a tank since the Oct 2026 kit pass, so Cairn).
	var t2 := _caravan([["hissy"], ["cairn"]])
	var p2 := t2.cv_p
	_escort(t2, [t2.sim.creatures[0], t2.sim.creatures[1]], 300)
	assert_eq(t2.cv_p, p2, "fighter against fighter: it holds")


func test_an_assassin_rolls_it_back_faster() -> void:
	var back := {}
	for who in ["pete", "hissy"]:
		var t := _caravan([["cairn"], [who]])
		_away(t, t.sim.creatures[0])
		t.cv_p = 200.0
		_escort(t, [t.sim.creatures[1]], 300)
		back[who] = 200.0 - t.cv_p
	assert_near(float(back["pete"]) / float(back["hissy"]), 1.5, 0.05, "Pete (assassin) rolls it back faster:")


func test_a_skirmisher_respawns_sooner() -> void:
	var t := _caravan([["gillbert"], ["hissy"]])
	for c in t.sim.creatures:
		c.hp = 0.0
		c.state = CreatureSim.State.KO
	_idle(t, 1)
	assert_eq(int(t.respawn_t[1]) - int(t.respawn_t[0]), 90, "Gillbert (skirmisher) is back 1.5 s sooner:")


func test_every_class_has_a_perk_in_both_modes() -> void:
	# Capture the Flag's assassin perk (a lighter carry) went in Oct 2026: every fighter
	# carries at the same speed, so the assassin has none there until Kevin picks another.
	for path in [TeamSim.CARAVAN_PATH, TeamSim.CTF_PATH]:
		var perks: Dictionary = TeamSim.load_rules(path).get("class_perks", {})
		for role in ["tank", "bruiser", "fighter", "mage", "assassin", "skirmisher"]:
			if path == TeamSim.CTF_PATH and role == "assassin":
				assert_false(perks.has(role), "ctf.json: no assassin perk (no class carries light)")
				continue
			assert_true(perks.has(role) and String((perks[role] as Dictionary).get("text", "")) != "",
				"%s: %s has a perk with words for the screen" % [path.get_file(), role])
	for f in MatchFactory.FIGHTERS:
		var role := String(MatchFactory.load_def(f).get("role", "fighter"))
		assert_true(role in ["tank", "bruiser", "fighter", "mage", "assassin", "skirmisher"], "%s's class %s has perks" % [f, role])


# ------------------------------------------------------------------ class perks: CTF

func _carry_slow(who: String) -> float:
	var t := _ctf([[who], ["culvert"]])
	var c := t.sim.creatures[0]
	c.pos = t.base_of(1)
	_idle(t, 3)
	return c.carry_mult


func test_every_class_carries_at_the_same_speed() -> void:
	# No class perk lightens the carry (the assassin's 0.97 went in Oct 2026: a carrier
	# who outruns everyone makes a solo run the best plan, and escorts and passes pointless).
	assert_near(_carry_slow("pete"), 0.8, 0.001, "Pete (assassin):")
	assert_near(_carry_slow("hissy"), 0.8, 0.001, "Hissy (fighter):")
	assert_near(_carry_slow("culvert"), 0.8, 0.001, "Culvert (tank):")


func test_a_tank_carrier_is_steady() -> void:
	for who in ["craglash", "hissy"]:
		var t := _ctf([[who], ["culvert"]])
		var c := t.sim.creatures[0]
		c.pos = t.base_of(1)
		_idle(t, 2)
		c.pos = t.sim.terrain.nearest_solid(Vector2(400, 320))
		c.enter_crumple(30, Vector2.ZERO)
		_idle(t, 1)
		var kept := int(t.flag_state[1]) == TeamSim.FLAG_CARRIED
		assert_eq(kept, who == "craglash", "%s: a stun %s" % [who, "keeps the flag" if who == "craglash" else "knocks it loose"])


func test_a_bruisers_heavy_hit_knocks_it_loose() -> void:
	for who in ["barkley", "culvert"]:
		var t := _ctf([["hissy"], [who]])
		var c := t.sim.creatures[0]
		c.pos = t.base_of(1)
		_idle(t, 2)
		c.pos = t.sim.terrain.nearest_solid(Vector2(400, 320))
		t.sim.events.clear()
		t.sim.emit_event("hit", c.pos, 8.0, {"attacker": 1, "target": 0, "heavy": true})
		assert_eq(t._hard_hit(c), who == "barkley", "a heavy hit by %s" % who)


func test_a_mage_claims_shrines_faster() -> void:
	var got := {}
	for who in ["cerebro", "hissy"]:
		var t := _ctf([[who], ["culvert"]])
		_idle(t, int(t.shrines[0][2]) + 1)
		t.sim.creatures[0].pos = t.shrine_pos(0)
		for i in 400:
			_idle(t, 1)
			t.sim.creatures[0].pos = t.shrine_pos(0)
			if not _events(t, "shrine").is_empty():
				got[who] = i
				break
	assert_near(float(got["hissy"]) / float(got["cerebro"]), 1.5, 0.05, "Cerebro (mage) claims faster (%s)" % str(got))


func test_a_fighter_reaches_farther_and_a_skirmisher_passes_farther() -> void:
	var t := _ctf([["hissy", "gillbert"], ["culvert", "digby"]], 2)
	var hissy := t.sim.creatures[0]
	var pete_like := t.sim.creatures[2]  # culvert: a fighter too; digby (assassin) has no reach
	var digby := t.sim.creatures[3]
	assert_true(t._touches_flag(hissy, 1) == false, "far off")
	var r := float(t.rules["pickup_radius"])
	hissy.pos = t.base_of(1) + Vector2(r + hissy.radius + 6.0, 0)
	digby.pos = t.base_of(0) + Vector2(r + digby.radius + 6.0, 0)
	assert_true(t._touches_flag(hissy, 1), "Hissy (fighter) reaches it from 6 px farther")
	assert_false(t._touches_flag(digby, 0), "Digby (assassin) doesn't")
	assert_near(float(t.perk(t.sim.creatures[1], "pass", 1.0)), 1.3, 0.001, "Gillbert (skirmisher) passes 1.3x")
	assert_near(float(t.perk(pete_like, "pass", 1.0)), 1.0, 0.001, "a fighter passes plain")
