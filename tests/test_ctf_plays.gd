extends TestCase
## Capture the Flag's plays: a hard hit knocks the flag loose, passes (TAG) to a teammate,
## catches and interceptions in the air, the bridge that falls in and comes back, the
## shrines, the comeback rules, and Normal CPUs using all of it.

const TEAMS := [["cairn", "sno", "pete", "craglash"], ["culvert", "digby", "hissy", "barkley"]]


func _ctf(size := 1, over := {}) -> TeamSim:
	var r := TeamSim.load_rules(TeamSim.CTF_PATH)
	for k in over:
		r[k] = over[k]
	var t := TeamSim.new(TEAMS, size, r)
	while t.phase == TeamSim.Phase.INTRO:
		t.step(PackedInt32Array())
	return t


func _idle(t: TeamSim, ticks: int, ins := PackedInt32Array()) -> void:
	for i in ticks:
		t.step(ins)
		for c in t.sim.creatures:
			c.walk_vel = Vector2.ZERO


## A spot on open grass on red's side of the river, clear of everything.
func _field(t: TeamSim, dx := 0.0, dy := 0.0) -> Vector2:
	return t.sim.terrain.nearest_solid(Vector2(400 + dx, 320 + dy))


## Red (slot 0) takes blue's flag and stands at `at` with it.
func _red_carries(t: TeamSim, at: Vector2) -> CreatureSim:
	var red := t.sim.creatures[0]
	red.pos = t.base_of(1)
	_idle(t, 2)
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_CARRIED, "red took blue's flag")
	red.pos = at
	_idle(t, 1)
	return red


func _slot_inputs(t: TeamSim, slot: int, bits: int) -> PackedInt32Array:
	var ins := PackedInt32Array()
	ins.resize(t.slot_count())
	ins[slot] = bits
	return ins


func _events(t: TeamSim, kind: String) -> Array:
	return t.sim.events.filter(func(e): return String(e["type"]) == kind)


func test_a_hard_hit_knocks_the_flag_loose() -> void:
	var t := _ctf(1)
	var red := _red_carries(t, _field(t))
	var blue := t.sim.creatures[1]
	blue.pos = _field(t, 0, 120)
	red.enter_knockdown(40, Vector2(2, 0))
	red.last_attacker = blue.id
	t.step(PackedInt32Array())
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_THROWN, "knocked loose, in the air")
	var ev := _events(t, "flag_fumble")
	assert_eq(ev.size(), 1, "a fumble event")
	assert_eq(int(ev[0]["by"]), blue.id, "credited to the hitter")
	_idle(t, 30)
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_DROPPED, "it landed")
	assert_gt(t.flag_pos[1].x, red.pos.x + 20.0, "a few steps the way the carrier was hit")


func test_a_plain_hit_doesnt_fumble() -> void:
	var t := _ctf(1)
	var red := _red_carries(t, _field(t))
	red.enter_hitstun(12, Vector2(1, 0))
	_idle(t, 3)
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_CARRIED, "hitstun alone keeps the flag")


func test_the_fumbler_cant_grab_it_back_at_once_but_a_teammate_can() -> void:
	var t := _ctf(2)
	var red := _red_carries(t, _field(t))
	var mate := t.sim.creatures[1]
	red.enter_knockdown(2, Vector2.ZERO)
	t.step(PackedInt32Array())
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_THROWN, "loose")
	_idle(t, 25)  # landed, and red is up, standing by it
	red.pos = t.flag_pos[1]
	_idle(t, 2)
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_DROPPED, "red is locked out for a moment")
	mate.pos = t.flag_pos[1]
	_idle(t, 2)
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_CARRIED, "red's teammate picks it up")
	assert_eq(int(t.flag_carrier[1]), mate.id, "the teammate carries it")


func test_a_pass_to_a_teammate() -> void:
	var t := _ctf(2)
	var red := _red_carries(t, _field(t))
	var mate := t.sim.creatures[1]
	mate.pos = red.pos + Vector2(-100, 0)
	_idle(t, 1)
	# TAG, aimed at the teammate.
	t.step(_slot_inputs(t, 0, SimDefs.IN_TAG | SimDefs.aim_bits(Vector2.LEFT)))
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_THROWN, "in the air")
	assert_eq(_events(t, "flag_pass").size(), 1, "a pass event")
	for i in 40:
		_idle(t, 1)
		if int(t.flag_state[1]) != TeamSim.FLAG_THROWN:
			break
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_CARRIED, "caught")
	assert_eq(int(t.flag_carrier[1]), mate.id, "by the teammate")


func test_holding_tag_passes_once() -> void:
	var t := _ctf(2)
	var red := _red_carries(t, _field(t))
	var mate := t.sim.creatures[1]
	mate.pos = red.pos + Vector2(-60, 0)
	var held := _slot_inputs(t, 0, SimDefs.IN_TAG | SimDefs.aim_bits(Vector2.LEFT))
	held[1] = SimDefs.IN_TAG
	for i in 40:
		t.step(held)
		for c in t.sim.creatures:
			c.walk_vel = Vector2.ZERO
	assert_eq(int(t.flag_carrier[1]), mate.id, "the teammate caught it and, TAG held, didn't throw it back")


func test_an_interception_sends_it_home() -> void:
	var t := _ctf(2)
	var red := _red_carries(t, _field(t))
	var mate := t.sim.creatures[1]
	var blue := t.sim.creatures[2]
	mate.pos = red.pos + Vector2(-120, 0)
	blue.pos = red.pos + Vector2(-80, 0)  # in the way, in the flight's second half
	_idle(t, 1)
	t.step(_slot_inputs(t, 0, SimDefs.IN_TAG | SimDefs.aim_bits(Vector2.LEFT)))
	for i in 40:
		_idle(t, 1)
		if int(t.flag_state[1]) != TeamSim.FLAG_THROWN:
			break
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_HOME, "blue caught its own flag: home")


func test_a_pass_to_nobody_lands_and_waits() -> void:
	var t := _ctf(1)
	var red := _red_carries(t, _field(t))
	t.step(_slot_inputs(t, 0, SimDefs.IN_TAG | SimDefs.aim_bits(Vector2.UP)))
	_idle(t, 40)
	assert_eq(int(t.flag_state[1]), TeamSim.FLAG_DROPPED, "on the ground")
	assert_lt(t.flag_pos[1].y, red.pos.y - 60.0, "up the way it was thrown")


func test_comeback_respawn_and_sudden_death_speed() -> void:
	var t := _ctf(1)
	var red := t.sim.creatures[0]
	var blue := t.sim.creatures[1]
	blue.pos = t.base_of(0)  # blue has red's flag
	_idle(t, 2)
	assert_eq(int(t.flag_state[0]), TeamSim.FLAG_CARRIED, "red's flag is away")
	red.hp = 0.0
	red.state = CreatureSim.State.KO
	_idle(t, 1)
	assert_eq(int(t.respawn_t[0]), int(float(t.rules["respawn_seconds_flag_away"]) * 60), "red is back sooner:")
	# Sudden death: the carrier isn't slowed.
	t.overtime = true
	blue.slow = 0
	_idle(t, 2)
	assert_true(blue.slow <= 0 or blue.slow_mult >= 1.0, "no carry slow in sudden death")


func test_a_capture_slows_the_game_for_a_moment() -> void:
	var t := _ctf(1)
	var red := _red_carries(t, _field(t))
	red.pos = t.base_of(0)
	_idle(t, 2)
	assert_eq(int(t.score[0]), 1, "captured")
	assert_gt(float(t.sim.slowmo), 0.0, "slow motion")


func test_heavy_hits_bring_the_bridge_down_and_it_comes_back() -> void:
	var t := _ctf(1)
	var sim := t.sim
	assert_eq(sim.bridges.size(), 1, "Twin Keeps has a bridge")
	var r: Rect2i = ArenaMap.bridge_rects(sim.arena)[0]
	var blue := sim.creatures[1]
	var red := sim.creatures[0]
	var falls := 0
	var strained := 0
	# Heavy hits on someone standing on the bridge, all over it.
	for k in 40:
		var cx := r.position.x + 1 + (k % 3) * 3
		var cy := r.position.y + 1 + (k / 3 % 4) * 3
		blue.pos = sim.terrain.cell_center(Vector2i(cx, cy))
		blue.state = CreatureSim.State.IDLE
		sim.events.clear()
		sim.emit_event("hit", blue.pos, 10.0, {"attacker": red.id, "target": blue.id, "heavy": true})
		sim._step_bridges()
		strained += _events(t, "bridge_strain").size()
		falls += _events(t, "bridge_fall").size()
		if falls > 0:
			break
	assert_eq(strained, 1, "a creak first")
	assert_eq(falls, 1, "then it falls in")
	assert_true(sim.bridge_down(0), "down")
	assert_eq(sim.terrain.get_cell(r.position + r.size / 2), TerrainGrid.SHALLOWS, "it's river now: waded, not walked")
	blue.pos = _field(t)
	red.pos = _field(t, 0, 40)
	var back := false
	for i in int(float(sim.arena["bridges"][0]["reform_seconds"]) * 60) + 30:
		t.step(PackedInt32Array())
		if not _events(t, "bridge_up").is_empty():
			back = true
			break
	assert_true(back, "it comes back")
	for cy in range(r.position.y, r.end.y):
		for cx in range(r.position.x, r.end.x):
			if sim.terrain.get_cell(Vector2i(cx, cy)) != TerrainGrid.INTACT:
				fail("cell %d,%d isn't whole again" % [cx, cy])
				return


func test_light_hits_dont_crack_the_bridge() -> void:
	var t := _ctf(1)
	var sim := t.sim
	var r: Rect2i = ArenaMap.bridge_rects(sim.arena)[0]
	var blue := sim.creatures[1]
	blue.pos = sim.terrain.cell_center(r.position + r.size / 2)
	for k in 20:
		sim.events.clear()
		sim.emit_event("hit", blue.pos, 4.0, {"attacker": 0, "target": blue.id, "heavy": false})
		sim._step_bridges()
	assert_eq(sim.bridge_strain(0), 0, "no strain from light hits")


func test_a_shrine_is_claimed_alone_and_buffs_the_side() -> void:
	var t := _ctf(2)
	assert_eq(t.shrines.size(), 2, "two shrines")
	var red := t.sim.creatures[0]
	var mate := t.sim.creatures[1]
	var first := int(t.shrines[0][2])
	assert_gt(float(first), 0.0, "not ready at the start")
	_idle(t, first + 1)
	red.pos = t.shrine_pos(0)
	var claimed := {}
	for i in t.shrine_claim_ticks() + 5:
		_idle(t, 1)
		for e in _events(t, "shrine"):
			claimed = e
	assert_eq(int(claimed.get("team", -1)), 0, "red claimed it")
	var kind := t.shrine_kind(0)
	for c: CreatureSim in [red, mate]:
		if kind == "might":
			assert_gt(float(c.atk_buff), 0.0, "might on %d" % c.id)
		else:
			assert_gt(float(c.haste), 0.0, "haste on %d" % c.id)
	assert_gt(float(t.shrines[0][2]), 0.0, "and it rests")


func test_a_contested_shrine_holds() -> void:
	var t := _ctf(1)
	_idle(t, int(t.shrines[1][2]) + 1)
	t.sim.creatures[0].pos = t.shrine_pos(1)
	t.sim.creatures[1].pos = t.shrine_pos(1) + Vector2(6, 0)
	_idle(t, t.shrine_claim_ticks() * 2)
	assert_eq(int(t.shrines[1][1]), 0, "nobody claims it with both sides in")
	assert_eq(int(t.shrines[1][2]), 0, "still ready")


func test_plays_roll_back() -> void:
	var t := _ctf(2)
	var red := _red_carries(t, _field(t))
	t.sim.creatures[1].pos = red.pos + Vector2(-100, 0)
	t.step(_slot_inputs(t, 0, SimDefs.IN_TAG | SimDefs.aim_bits(Vector2.LEFT)))
	var snap := t.snapshot()
	var d := t.state_digest()
	_idle(t, 60)
	var after := t.state_digest()
	t.restore(snap)
	assert_eq(t.state_digest(), d, "restored mid-flight")
	_idle(t, 60)
	assert_eq(t.state_digest(), after, "and replays the same")


## Normal CPUs, 3 a side, one long match: they pass, fumble, claim shrines and capture.
func test_normal_cpus_use_the_plays() -> void:
	var t := TeamSim.new(TEAMS, 3, TeamSim.load_rules(TeamSim.CTF_PATH))
	var cpus: Array = []
	for i in t.slot_count():
		cpus.append(CpuController.new(i, 1, 40 + i))
	var seen := {}
	for tick in 60 * 360 + 200:
		var ins := PackedInt32Array()
		for i in t.slot_count():
			ins.append((cpus[i] as CpuController).bits(t.sim))
		t.step(ins)
		for e in t.sim.events:
			seen[String(e["type"])] = int(seen.get(String(e["type"]), 0)) + 1
		if t.phase == TeamSim.Phase.OVER:
			break
	for kind in ["flag_take", "shrine", "flag_fumble", "capture"]:
		assert_gt(float(seen.get(kind, 0)), 0.0, "%s happened (%s)" % [kind, str(seen.get(kind, 0))])
