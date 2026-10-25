extends TestCase
## Rollback netcode groundwork: the match state can be saved and restored exactly, and
## two machines exchanging inputs over a laggy, lossy connection end up in exactly the
## same state as a match played with no network at all.


func _close_match() -> MatchSim:
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.creatures[0].pos = Vector2(220, 164)
	sim.creatures[1].pos = Vector2(245, 164)
	return sim


## Random button mashing, each combination held 1-20 ticks.
func _mash(seed_: int, n: int) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out := PackedInt32Array()
	var hold := 0
	var left := 0
	for i in n:
		if left <= 0:
			hold = rng.randi() & SimDefs.IN_EVERYTHING
			left = rng.randi_range(1, 20)
		left -= 1
		out.append(hold)
	return out


func test_every_creature_variable_is_saved_or_static() -> void:
	var c := MatchFactory.versus("cairn", "culvert").creatures[0]
	for prop in c.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n := String(prop["name"])
		assert_true(n in CreatureSim.STATE_FIELDS or n in CreatureSim.STATIC_FIELDS or n in CreatureSim.BOOST_FIELDS,
			"CreatureSim.%s must be listed in STATE_FIELDS (or STATIC_FIELDS) for rollback" % n)


func test_every_match_variable_is_saved_or_static() -> void:
	var saved := ["tick", "hitstop", "ko_freeze", "slowmo", "terrain", "creatures", "projectiles", "zones", "sink_ring", "sink_safe",
		"zone_pos", "zone_r", "goals", "training_flags", "storms", "bridges", "hazards", "hazard_pickups", "shrines", "shrine_rng"]
	var static_or_scratch := ["ko_freeze_ticks", "ko_slowmo_ticks", "events", "arena_id", "arena", "fall_ko", "freeze_all", "mutators",
		"training", "bridge_rects", "hazard_defs", "shrine_spots", "shrine_rules"]  # the map, the mode, the hazards and the shrines are fixed for the match
	for prop in MatchSim.new().get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n := String(prop["name"])
		assert_true(n in saved or n in static_or_scratch,
			"MatchSim.%s must be saved by snapshot() for rollback" % n)


func test_snapshot_and_restore_replay_exactly() -> void:
	var sim := _close_match()
	var a := _mash(1, 900)
	var b := _mash(2, 900)
	for i in 400:
		sim.step(PackedInt32Array([a[i], b[i]]))
	var snap := sim.snapshot()
	var at_snap := sim.state_digest()
	for i in range(400, 900):
		sim.step(PackedInt32Array([a[i], b[i]]))
	var end := sim.state_digest()
	sim.restore(snap)
	assert_eq(sim.state_digest(), at_snap, "restored state:")
	for i in range(400, 900):
		sim.step(PackedInt32Array([a[i], b[i]]))
	assert_eq(sim.state_digest(), end, "re-simulated from a snapshot:")


## Plays one online match between two simulated machines and checks both end in the
## same state as an offline match with the same inputs. Returns the two sessions.
func _online(latency: int, jitter: int, loss: float, delay: int, frames := 900) -> Array:
	var sims := [_close_match(), _close_match()]
	var sessions: Array[RollbackSession] = []
	for p in 2:
		var s := RollbackSession.new(sims[p], p, delay)
		s.keep_history = true
		sessions.append(s)
	var streams := [_mash(11, frames + 200), _mash(22, frames + 200)]
	var net := RandomNumberGenerator.new()
	net.seed = 99
	var in_flight: Array = []  # [deliver_at, to, packet]
	var t := 0
	while t < frames + 400:
		for p in 2:
			var s := sessions[p]
			if s.frame < frames:
				var pkt := s.add_local_input(streams[p][t] if t < frames else 0)
				if net.randf() >= loss:
					var lag := latency + (net.randi_range(-jitter, jitter) if jitter > 0 else 0)
					in_flight.append([t + maxi(0, lag), 1 - p, pkt])
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
		if sessions[0].frame >= frames and sessions[1].frame >= frames and in_flight.is_empty() \
				and sessions[0].is_settled() and sessions[1].is_settled():
			break
	for s in sessions:
		s.sync()
	assert_eq(sessions[0].frame, frames, "machine A frame:")
	assert_eq(sessions[1].frame, frames, "machine B frame:")
	# The same match with no network: each player's inputs exactly as scheduled.
	var offline := _close_match()
	for f in frames:
		offline.step(PackedInt32Array([int(sessions[0].history.get(f, 0)), int(sessions[1].history.get(f, 0))]))
	var want := offline.state_digest()
	assert_eq(sims[0].state_digest(), want, "machine A matches the offline match:")
	assert_eq(sims[1].state_digest(), want, "machine B matches the offline match:")
	return sessions


func test_online_match_stays_in_sync_through_rollbacks() -> void:
	var s := _online(4, 0, 0.0, 1)
	assert_gt(float(s[0].rollbacks + s[1].rollbacks), 0.0, "a 4-frame connection should cause rollbacks")
	assert_true(s[0].max_rollback_seen <= s[0].max_rollback, "rollbacks stay within the limit")


func test_online_match_survives_jitter_and_packet_loss() -> void:
	var s := _online(6, 3, 0.15, 2)
	assert_gt(float(s[0].rollbacks), 0.0, "rollbacks happened")


func test_input_delay_covering_latency_means_no_rollbacks() -> void:
	var s := _online(2, 0, 0.0, 2, 600)
	assert_eq(s[0].rollbacks + s[1].rollbacks, 0, "inputs always arrive in time:")


## The other machine can run ahead (this one hitched: a window drag, a slow frame) and
## its packets only repeat the last 8 inputs. Inputs it sent earlier must not be thrown
## away before they're used, or this machine would play the wrong ones and desync.
func test_inputs_from_a_machine_running_ahead_are_kept_until_used() -> void:
	var games := [MatchFactory.versus("cairn", "culvert"), MatchFactory.versus("cairn", "culvert")]
	var ss := [RollbackSession.new(games[0], 0, 2), RollbackSession.new(games[1], 1, 2)]
	for s in ss:
		s.keep_history = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var packets_for_a: Array = []
	for t in 400:
		var bits := [rng.randi() & SimDefs.IN_ALL, rng.randi() & SimDefs.IN_ALL]
		# Machine A freezes for ticks 100-129 while B keeps going as far as it can.
		var a_frozen := t >= 100 and t < 130
		if not a_frozen:
			ss[1].receive(ss[0].add_local_input(bits[0]))
		packets_for_a.append(ss[1].add_local_input(bits[1]))
		if not a_frozen:
			for p in packets_for_a:
				ss[0].receive(p)
			packets_for_a.clear()
			ss[0].advance()
		ss[1].advance()
	# A catches up (time sync's job in a real match), then both settle.
	for t in 120:
		ss[1].receive(ss[0].add_local_input(0))
		ss[0].receive(ss[1].add_local_input(0))
		ss[0].advance()
		if ss[1].frame < ss[0].frame:
			ss[1].advance()
	for t in 3:
		ss[1].receive(ss[0].add_local_input(0))
		ss[0].receive(ss[1].add_local_input(0))
	for s in ss:
		s.sync()
	assert_eq(ss[0].frame, ss[1].frame, "both caught up to the same frame:")
	var offline := MatchFactory.versus("cairn", "culvert")
	for f in ss[0].frame:
		offline.step(PackedInt32Array([int(ss[0].history.get(f, 0)), int(ss[1].history.get(f, 0))]))
	assert_eq(games[0].state_digest(), offline.state_digest(), "machine A played the right inputs:")
	assert_eq(games[1].state_digest(), offline.state_digest(), "machine B played the right inputs:")
