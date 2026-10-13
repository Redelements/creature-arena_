extends TestCase
## Duel (3v3 tag): tagging, tag cancels, cooldowns, bench healing, knockouts bringing
## in the next creature, winning, time out, and rollback across tags.

const L := SimDefs.IN_LIGHT
const T := SimDefs.IN_TAG
const TEAM_A := ["cairn", "culvert", "cairn"]
const TEAM_B := ["culvert", "cairn", "culvert"]


func _duel(close := true) -> DuelSim:
	var d := DuelSim.new([TEAM_A, TEAM_B])
	if close:
		d.sim.creatures[0].pos = Vector2(220, 164)
		d.sim.creatures[1].pos = Vector2(245, 164)
	# Skip the intro.
	while d.phase == DuelSim.Phase.INTRO:
		d.step(PackedInt32Array([0, 0]))
	return d


## Steps the duel (not just its match) until `cond` holds.
func _until(d: DuelSim, cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		d.step(PackedInt32Array([0, 0]))
	return cond.call()


func _press(d: DuelSim, p0: int, p1 := 0) -> void:
	d.step(PackedInt32Array([p0, p1]))
	d.step(PackedInt32Array([0, 0]))


func test_intro_holds_everyone_still() -> void:
	var d := DuelSim.new([TEAM_A, TEAM_B])
	var start := d.sim.creatures[0].pos
	for i in 30:
		d.step(PackedInt32Array([SimDefs.IN_RIGHT | L, 0]))
	assert_eq(d.phase, DuelSim.Phase.INTRO, "still in the intro:")
	assert_near(d.sim.creatures[0].pos.x, start.x, 0.001, "no moving during the intro:")


func test_tag_swaps_in_the_next_creature_with_a_strike() -> void:
	var d := _duel()
	var first := d.active_creature(0)
	_press(d, T)
	var now := d.active_creature(0)
	assert_true(now != first, "a different creature is in")
	assert_eq(String(now.def["id"]), "culvert", "the second team member:")
	assert_eq(d.sim.creatures[0], now, "the match uses the new creature")
	assert_eq(now.move_id, "tag_in", "it enters with its tag-in strike:")
	assert_true(now.is_invulnerable(), "protected while the strike starts")
	assert_near(now.pos.x, first.pos.x, 3.0, "enters where the partner stood:")


func test_tag_has_a_cooldown() -> void:
	var d := _duel(false)
	_press(d, T)
	var second := d.active_creature(0)
	run_until_free(d, 0)
	_press(d, T)
	assert_eq(d.active_creature(0), second, "no tag again while on cooldown:")
	for i in int(d.rules["tag_cooldown"]):
		d.step(PackedInt32Array([0, 0]))
	_press(d, T)
	assert_true(d.active_creature(0) != second, "tags again after the cooldown")


func run_until_free(d: DuelSim, side: int) -> void:
	for i in 120:
		var c := d.active_creature(side)
		if c.state == CreatureSim.State.IDLE or c.state == CreatureSim.State.MOVE:
			return
		d.step(PackedInt32Array([0, 0]))


func test_no_tag_while_stunned() -> void:
	var d := _duel()
	_press(d, 0, L)  # the right side jabs the left
	_until(d, func(): return d.active_creature(0).is_stunned(), 20)
	assert_true(d.active_creature(0).is_stunned(), "left side is in hitstun")
	assert_false(d.can_tag(0), "can't tag out of hitstun")


func test_tag_cancel_extends_a_combo_for_energy() -> void:
	var d := _duel()
	var a := d.active_creature(0)
	a.energy = 80.0
	d.step(PackedInt32Array([L, 0]))
	_until(d, func(): return a.connected, 30)
	assert_true(a.connected, "the jab hit")
	assert_true(d.can_tag(0), "a connected attack can tag cancel")
	d.step(PackedInt32Array([L | T, 0]))
	var b := d.active_creature(0)
	assert_true(b != a, "tagged out mid-combo")
	assert_near(b.energy, 80.0 - float(d.rules["tag_cancel_energy"]) + 0.0, 8.0, "paid for the tag cancel:")
	var foe := d.active_creature(1)
	var hits_before := foe.combo_hits
	_until(d, func(): return foe.combo_hits > hits_before, 40)
	assert_gt(float(foe.combo_hits), float(hits_before), "the tag-in strike continues the combo")


func test_no_tag_cancel_without_energy() -> void:
	var d := _duel()
	var a := d.active_creature(0)
	a.energy = 0.0
	d.step(PackedInt32Array([L, 0]))
	_until(d, func(): return a.connected, 30)
	assert_false(d.can_tag(0), "tag cancel needs energy")


func test_benched_creature_heals_back_part_of_its_damage() -> void:
	var d := _duel(false)
	var a := d.active_creature(0)
	a.hp = a.max_hp * 0.4
	_press(d, T)
	for i in 60 * 30:
		d.step(PackedInt32Array([0, 0]))
	var cap := a.max_hp * 0.4 + a.max_hp * float(d.rules["bench_regen_cap"])
	assert_near(a.hp, cap, 0.01, "heals up to the cap, no further:")


func test_knockout_brings_in_the_next_creature() -> void:
	var d := _duel()
	var victim := d.active_creature(1)
	victim.hp = 1.0
	_press(d, L)
	assert_true(_until(d, func(): return d.phase == DuelSim.Phase.SWAP, 60), "waiting for the next creature")
	assert_true(_until(d, func(): return d.phase == DuelSim.Phase.FIGHT, 400), "back to fighting")
	assert_true(d.active_creature(1) != victim, "a new creature is in")
	assert_eq(d.alive_count(1), 2, "two left:")
	assert_true(d.active_creature(1).invuln > 0, "it enters protected")


func test_losing_every_creature_loses_the_duel() -> void:
	var d := _duel()
	for c in d.teams[1]:
		(c as CreatureSim).hp = 0.0
	(d.teams[1][0] as CreatureSim).hp = 1.0
	_press(d, L)
	for i in 120:
		if d.phase == DuelSim.Phase.OVER:
			break
		d.step(PackedInt32Array([0, 0]))
	assert_eq(d.phase, DuelSim.Phase.OVER, "duel over:")
	assert_eq(d.winner, 0, "left side wins:")


func test_time_out_goes_to_the_team_with_more_health() -> void:
	var d := _duel(false)
	(d.teams[1][2] as CreatureSim).hp = 10.0
	d.timer = 3
	for i in 5:
		d.step(PackedInt32Array([0, 0]))
	assert_eq(d.phase, DuelSim.Phase.OVER, "time out:")
	assert_eq(d.winner, 0, "left side has more health left:")


func test_rollback_across_a_tag_restores_the_old_team_order() -> void:
	var d := _duel()
	var snap := d.snapshot()
	var digest := d.state_digest()
	var first := d.active_creature(0)
	_press(d, T)
	for i in 40:
		d.step(PackedInt32Array([L if i % 6 == 0 else 0, 0]))
	assert_true(d.active_creature(0) != first, "tagged")
	d.restore(snap)
	assert_eq(d.active_creature(0), first, "the original creature is back in")
	assert_eq(d.sim.creatures[0], first, "and the match uses it")
	assert_eq(d.state_digest(), digest, "the whole duel is restored:")


func test_online_duel_stays_in_sync() -> void:
	# Two machines play a duel full of tags over a 5-frame connection.
	var duels := [_duel(), _duel()]
	var sessions: Array[RollbackSession] = []
	for p in 2:
		var s := RollbackSession.new(duels[p], p, 1)
		s.keep_history = true
		sessions.append(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var frames := 900
	var streams := [PackedInt32Array(), PackedInt32Array()]
	for p in 2:
		var hold := 0
		for i in frames:
			if i % 9 == 0:
				hold = rng.randi() & SimDefs.IN_EVERYTHING
			streams[p].append(hold)
	var in_flight: Array = []
	var t := 0
	while t < frames + 300:
		for p in 2:
			var s := sessions[p]
			if s.frame < frames:
				var pkt := s.add_local_input(streams[p][t] if t < frames else 0)
				in_flight.append([t + 5, 1 - p, pkt])
		var still: Array = []
		for m in in_flight:
			if int(m[0]) <= t:
				sessions[int(m[1])].receive(m[2])
			else:
				still.append(m)
		in_flight = still
		for s in sessions:
			if s.frame < frames:
				s.advance()
		t += 1
		if sessions[0].frame >= frames and sessions[1].frame >= frames and in_flight.is_empty():
			break
	for s in sessions:
		s.sync()
	var offline := _duel()
	for f in frames:
		offline.step(PackedInt32Array([int(sessions[0].history.get(f, 0)), int(sessions[1].history.get(f, 0))]))
	assert_eq(duels[0].state_digest(), offline.state_digest(), "machine A matches offline:")
	assert_eq(duels[1].state_digest(), offline.state_digest(), "machine B matches offline:")
	assert_gt(float(sessions[0].rollbacks), 0.0, "rollbacks happened")
