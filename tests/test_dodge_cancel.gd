extends TestCase
## Dodge cancel (issue #9): a Dodge pressed during your own attack leaves it at any point
## (out of a light string, a feint during a raw move's windup, out of a whiffed heavy's
## recovery) for a dearer stamina cost (stamina.json "dodge_cancel_cost_mult"); a blocked
## third light can't be left that way; a press that can't cancel is kept until the attack
## ends so the dodge comes out on the first free frame; the cancelled move lands nothing.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const D := SimDefs.IN_DODGE
const G := SimDefs.IN_GUARD


func _duel(gap := 2.0, left := "cairn", right := "cairn") -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(220 + sim.creatures[0].radius + sim.creatures[1].radius + gap, 164)
	sim.creatures[0].facing = Vector2.RIGHT
	sim.creatures[1].facing = Vector2.LEFT
	return sim


## Steps once with `p0` and returns the dodge events that tick.
func _dodges(sim: MatchSim, p0: int, p1 := 0) -> Array:
	sim.step(PackedInt32Array([p0, p1]))
	return sim.events.filter(func(e): return e["type"] == "dodge")


func test_the_cost_lives_in_the_stamina_rules() -> void:
	var r := CreatureSim.stamina_rules()
	assert_true(r.has("dodge_cancel_cost_mult"), "stamina.json has dodge_cancel_cost_mult")
	assert_gt(float(r["dodge_cancel_cost_mult"]), 1.0, "a cancel is dearer than a dodge:")
	var c := _duel().creatures[0]
	assert_near(c.dodge_cancel_cost(), c.dodge_cost * float(r["dodge_cancel_cost_mult"]), 0.001, "cost:")


func test_a_dodge_leaves_a_light_string() -> void:
	var sim := _duel(80.0)  # the foe out of reach: nothing connects, no hitstop
	var a := sim.creatures[0]
	tap(sim, L, 2)
	assert_eq(a.state, CreatureSim.State.ATTACK, "jabbing")
	assert_eq(a.move_id, "light_1", "the first light")
	var ev := _dodges(sim, D | SimDefs.IN_LEFT)
	assert_eq(a.state, CreatureSim.State.DODGE, "the dodge took over at once")
	assert_eq(a.dodge_dir, Vector2.LEFT, "the way held when pressed")
	assert_near(a.stamina, a.max_stamina - a.dodge_cancel_cost(), 0.001, "it cost the cancel price:")
	assert_eq(ev.size(), 1, "one dodge event")
	assert_true(bool(ev[0].get("cancel", false)), "marked as a cancel")
	assert_eq(int(ev[0]["who"]), 0, "by the dodger")


func test_a_dodge_from_neutral_is_not_a_cancel() -> void:
	var sim := _duel(80.0)
	var a := sim.creatures[0]
	var ev := _dodges(sim, D)
	assert_eq(a.state, CreatureSim.State.DODGE, "dodging")
	assert_near(a.stamina, a.max_stamina - a.dodge_cost, 0.001, "the plain price:")
	assert_false(bool(ev[0].get("cancel", true)), "not a cancel")


func test_a_feint_leaves_a_raw_heavy_during_its_windup() -> void:
	var sim := _duel(2.0)
	var a := sim.creatures[0]
	var b := sim.creatures[1]
	tap(sim, H, 2)
	assert_true(a.is_winding_up(), "a raw Haymaker winds up")
	run(sim, D, 1)
	assert_eq(a.state, CreatureSim.State.DODGE, "the windup was left")
	run(sim, 0, 60)
	assert_near(b.hp, b.max_hp, 0.001, "the feint hit nothing:")


func test_a_dodge_skips_a_whiffed_heavys_recovery() -> void:
	var sim := _duel(80.0)
	var a := sim.creatures[0]
	tap(sim, H, 0)
	assert_true(run_until(sim, func(): return a.is_active(), 40), "the swing comes out")
	assert_true(run_until(sim, func(): return not a.is_active(), 10), "and is over")
	assert_eq(a.state, CreatureSim.State.ATTACK, "recovering")
	var left := int(a.move_def()["length"]) - a.state_t
	assert_gt(float(left), 10.0, "with a long recovery ahead:")
	run(sim, D, 1)
	assert_eq(a.state, CreatureSim.State.DODGE, "left early")


func test_a_cancelled_strike_lands_nothing() -> void:
	# Control: the jab connects.
	var sim := _duel(2.0)
	var b := sim.creatures[1]
	tap(sim, L, 20)
	assert_lt(b.hp, b.max_hp, "the jab lands when it's let be:")
	# Cancelled during the startup: it never does.
	sim = _duel(2.0)
	var a := sim.creatures[0]
	b = sim.creatures[1]
	tap(sim, L, 1)
	assert_eq(a.state, CreatureSim.State.ATTACK, "jabbing")
	assert_false(a.is_active(), "still in the startup")
	run(sim, D, 1)
	assert_eq(a.state, CreatureSim.State.DODGE, "cancelled")
	run(sim, 0, 40)
	assert_near(b.hp, b.max_hp, 0.001, "no hit from the cancelled jab:")


func test_a_blocked_ender_has_to_be_served() -> void:
	var sim := _duel(2.0)
	var a := sim.creatures[0]
	var punished := false
	for i in 120:
		sim.step(PackedInt32Array([L if i % 2 == 0 else 0, G]))
		if a.state == CreatureSim.State.ATTACK and a.punish_serial == a.attack_serial:
			punished = true
			break
	assert_true(punished, "a third light got blocked")
	assert_true(a.stamina >= a.dodge_cancel_cost(), "with the stamina for a cancel")
	# Chaining a fourth light out of the punished move is allowed (a new attack, which
	# could then be left): drop the mashed press so the punished move itself is tested.
	a.buffered = ""
	a.buffer_t = 0
	run(sim, D, 1, G)
	assert_false(a.state == CreatureSim.State.DODGE, "no dodge out of the punish window")
	assert_true(a.dodge_buffer > 0, "the press is kept")
	var dodged_while_attacking := false
	for i in 60:
		if a.state != CreatureSim.State.ATTACK:
			break
		sim.step(PackedInt32Array([0, G]))
		if a.state == CreatureSim.State.DODGE:
			dodged_while_attacking = true
	assert_false(dodged_while_attacking, "the recovery was served to the end")
	assert_true(run_until(sim, func(): return a.state == CreatureSim.State.DODGE, 3, 0, G),
		"then the kept dodge comes out")


func test_short_of_the_cancel_price_the_press_waits_for_the_recovery() -> void:
	var sim := _duel(80.0)
	var a := sim.creatures[0]
	# Enough for a dodge, not for a cancel, and not enough regen through the jab to reach
	# one (the kept press would cancel the moment it could afford to).
	var base := a.dodge_cost + 2.0
	a.stamina = base
	tap(sim, L, 1)
	assert_eq(a.state, CreatureSim.State.ATTACK, "jabbing")
	run(sim, D, 1)
	assert_eq(a.state, CreatureSim.State.ATTACK, "can't afford the cancel: still jabbing")
	var length := int(a.move_def()["length"])
	assert_gt(float(length - a.state_t), float(CreatureSim.BUFFER_TICKS),
		"more of the jab left than a plain buffer would keep:")
	var dodged_at := -1
	for i in 40:
		sim.step(PackedInt32Array([0, 0]))
		if a.state == CreatureSim.State.DODGE:
			dodged_at = i
			break
	assert_true(dodged_at >= 0, "the dodge came out when the jab ended")
	var steps := 3 + dodged_at + 1  # the tap (2), the press (1), the loop
	assert_near(a.stamina, base + float(a.def["stamina_regen"]) * float(steps) - a.dodge_cost, 0.6,
		"at the plain price (regen ran through the jab):")


func test_a_press_in_your_own_hitstop_cancels_as_it_ends() -> void:
	var sim := _duel(2.0)
	var a := sim.creatures[0]
	var b := sim.creatures[1]
	tap(sim, L, 0)
	assert_true(run_until(sim, func(): return sim.hitstop > 0, 20), "the jab lands and freezes the match")
	assert_eq(a.state, CreatureSim.State.ATTACK, "mid-jab")
	run(sim, D, 1)
	assert_eq(a.state, CreatureSim.State.ATTACK, "frozen: nothing happens yet")
	assert_true(a.dodge_buffer > 0, "the press is kept")
	assert_true(run_until(sim, func(): return sim.hitstop == 0 and a.state == CreatureSim.State.DODGE, 20),
		"the dodge takes over the first tick after the freeze")
	assert_lt(b.hp, b.max_hp, "the jab that landed still counts:")


# ---- Connected lights (Kevin's ruling R3, Oct 28): a fighter, tank or bruiser that lands
# a light (hit or blocked) dodges out of it at dodge_cancel_connected_mult x the dodge
# price; a whiff, a heavy, and every other role keep dodge_cancel_cost_mult.

## Starts `btn` on fighter `left` against `right` (holding `p1`), waits for it to
## connect (`connect` false: the foe stands out of reach), then dodges out. Returns the
## stamina the dodge cost, or -1.0 if it never came out.
func _cancel_spend(left: String, right: String, btn: int, connect := true, p1 := 0) -> float:
	var sim := _duel(2.0 if connect else 80.0, left, right)
	var a := sim.creatures[0]
	tap(sim, btn, 0, p1)
	if connect:
		assert_true(run_until(sim, func(): return a.connected, 40, 0, p1), "%s's move connects" % left)
	else:
		run(sim, 0, 2, p1)
	assert_eq(a.state, CreatureSim.State.ATTACK, "%s is still attacking" % left)
	assert_true(a.connected == connect, "connected is %s" % connect)
	var before := a.stamina
	run(sim, D, 1, p1)
	if not run_until(sim, func(): return a.state == CreatureSim.State.DODGE, 30, 0, p1) \
			and a.state != CreatureSim.State.DODGE:
		return -1.0
	return before - a.stamina


func _mult() -> float:
	return float(CreatureSim.stamina_rules()["dodge_cancel_cost_mult"])


func _plain(fid: String) -> float:
	return _duel(2.0, fid, "cairn").creatures[0].dodge_cost


func test_the_connected_rules_live_in_the_stamina_rules() -> void:
	var r := CreatureSim.stamina_rules()
	assert_true(r.has("dodge_cancel_connected_mult"), "stamina.json has dodge_cancel_connected_mult")
	var roles: Array = r.get("dodge_cancel_refund_roles", [])
	for role in ["fighter", "tank", "bruiser"]:
		assert_true(roles.has(role), "%s gets the refund" % role)
	for role in ["mage", "assassin", "skirmisher"]:
		assert_false(roles.has(role), "%s does not" % role)


func test_a_landed_light_is_left_at_the_plain_price() -> void:
	assert_near(_cancel_spend("cairn", "cairn", L), _plain("cairn") * float(
		CreatureSim.stamina_rules()["dodge_cancel_connected_mult"]), 0.001, "Cairn after a landed jab:")


func test_a_whiffed_light_still_costs_the_cancel_price() -> void:
	assert_near(_cancel_spend("cairn", "cairn", L, false), _plain("cairn") * _mult(), 0.001, "Cairn after a whiffed jab:")


func test_a_connected_heavy_still_costs_the_cancel_price() -> void:
	assert_near(_cancel_spend("cairn", "cairn", H), _plain("cairn") * _mult(), 0.001, "Cairn after a landed Haymaker:")


func test_an_assassin_pays_the_cancel_price_after_a_landed_light() -> void:
	assert_near(_cancel_spend("digby", "cairn", L), _plain("digby") * _mult(), 0.001, "Digby after a landed jab:")


func test_a_mage_pays_the_cancel_price_after_a_landed_light() -> void:
	assert_near(_cancel_spend("cerebro", "cairn", L), _plain("cerebro") * _mult(), 0.001, "Cerebro after a landed jab:")


func test_a_blocked_light_counts_as_connected() -> void:
	var spent := _cancel_spend("cairn", "cairn", L, true, G)
	assert_near(spent, _plain("cairn"), 0.001, "Cairn after a blocked jab:")


func test_every_refund_role_gets_it_and_no_other() -> void:
	var refund: Array = CreatureSim.stamina_rules()["dodge_cancel_refund_roles"]
	for fid in ["cairn", "culvert", "craglash", "barkley", "sno", "hissy"]:
		var c := _duel(2.0, fid, "cairn").creatures[0]
		assert_true(refund.has(String(c.def.get("role", "fighter"))), "%s gets the refund" % fid)
	for fid in ["cerebro", "crease", "gillbert", "digby", "pete"]:
		var c := _duel(2.0, fid, "cairn").creatures[0]
		assert_false(refund.has(String(c.def.get("role", "fighter"))), "%s does not" % fid)
