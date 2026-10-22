extends TestCase
## 360-degree aiming: the exact aim angle in the input, twin-stick strafing, mouse aim,
## keyboard/standard-pad aim assist, and the CPU's aim.

const L := SimDefs.IN_LIGHT
const S1 := SimDefs.IN_SKILL1
const LEFT := SimDefs.IN_LEFT
const RIGHT := SimDefs.IN_RIGHT


func test_the_aim_table_is_64_unit_directions_that_round_trip() -> void:
	var dirs := SimDefs.aim_dirs()
	assert_eq(dirs.size(), SimDefs.AIM_STEPS)
	assert_eq(dirs[0], Vector2.RIGHT, "index 0:")
	assert_eq(dirs[16], Vector2.DOWN, "index 16:")
	assert_eq(dirs[32], Vector2.LEFT, "index 32:")
	assert_eq(dirs[48], Vector2.UP, "index 48:")
	for i in dirs.size():
		assert_near(dirs[i].length(), 1.0, 0.0001, "unit length %d:" % i)
		var b := SimDefs.aim_bits(dirs[i] * 3.0)
		assert_eq((b >> SimDefs.AIM_SHIFT) & (SimDefs.AIM_STEPS - 1), i, "round trip %d:" % i)
	assert_eq(SimDefs.aim_from_bits(RIGHT), Vector2.RIGHT, "no aim bits: the direction bits")


## Chef Cerebro at the left; Cairn within Cleaver Toss's range, 22 degrees below the
## line to the right (as far off as 8-way aiming ever is). The cleaver flies straight.
func _off_angle() -> MatchSim:
	var sim := MatchFactory.versus("cerebro", "cairn")
	sim.creatures[0].pos = Vector2(200, 150)
	sim.creatures[1].pos = Vector2(200, 150) + Vector2.from_angle(deg_to_rad(22.0)) * 80.0  # 30 px off the line: past even the wider shots
	sim.creatures[0].facing = Vector2.RIGHT
	return sim


func _lash_hits(sim: MatchSim, bits: int) -> bool:
	sim.step(PackedInt32Array([bits, 0]))
	for i in 60:
		sim.step(PackedInt32Array([0, 0]))
		for e in sim.events:
			if e["type"] == "hit" and int(e["attacker"]) == 0:
				return true
	return false


func test_an_off_angle_throw_misses_with_8_way_aim_and_lands_with_exact_aim() -> void:
	assert_false(_lash_hits(_off_angle(), S1 | RIGHT), "aimed straight right, 22 degrees off at long range: a miss")
	var sim := _off_angle()
	var to := sim.creatures[1].pos - sim.creatures[0].pos
	assert_true(_lash_hits(sim, S1 | SimDefs.aim_bits(to)), "aimed exactly at Cairn: a hit")


func test_strafing_walks_one_way_while_facing_the_aim() -> void:
	var sim := MatchFactory.training("cairn")
	var c := sim.creatures[0]
	var start := c.pos
	var aim := SimDefs.aim_bits(Vector2.RIGHT) | SimDefs.IN_STRAFE
	run(sim, LEFT | aim, 40)
	assert_lt(c.pos.x, start.x - 10.0, "walked left")
	assert_eq(c.facing, Vector2.RIGHT, "still facing right:")
	var strafe_dist := start.x - c.pos.x
	var sim2 := MatchFactory.training("cairn")
	var c2 := sim2.creatures[0]
	run(sim2, LEFT, 40)
	assert_lt(strafe_dist, start.x - c2.pos.x, "strafing is a little slower")
	assert_eq(c2.facing, Vector2.LEFT, "without strafe you face where you walk:")


func test_aim_without_strafe_doesnt_turn_you_while_walking() -> void:
	var sim := MatchFactory.training("cairn")
	var c := sim.creatures[0]
	run(sim, LEFT | SimDefs.aim_bits(Vector2.RIGHT), 10)
	assert_eq(c.facing, Vector2.LEFT, "walking facing:")


func test_twinstick_pad_sends_exact_aim_and_strafe() -> void:
	var stick := Vector2(0.3, 0.95)
	var out := PlayerInput.combine_pad(Vector2(-1, 0), stick, {"light": true}, {"light": true}, false, 0, true)
	assert_true(out & SimDefs.IN_AIM, "exact aim")
	assert_true(out & SimDefs.IN_STRAFE, "strafe while the right stick is held")
	assert_true(out & LEFT, "still walks with the left stick")
	var dir := SimDefs.aim_from_bits(out)
	assert_gt(dir.dot(stick.normalized()), 0.995, "aims where the stick points")
	var std := PlayerInput.combine_pad(Vector2(-1, 0), stick, {"light": true}, {"light": true}, false, 0, false)
	assert_true(std & SimDefs.IN_AIM, "standard layout: the right stick aims exactly too")
	assert_gt(SimDefs.aim_from_bits(std).dot(stick.normalized()), 0.995, "standard layout aims where it points")
	assert_false(std & SimDefs.IN_STRAFE, "standard layout: no strafe")
	var idle := PlayerInput.combine_pad(Vector2(-1, 0), Vector2.ZERO, {}, {}, false, 0, true)
	assert_false(idle & SimDefs.IN_STRAFE, "right stick released: walk normally")


func _assist_setup(angle_deg: float, dist := 40.0) -> MatchSim:
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.creatures[0].pos = Vector2(200, 150)
	sim.creatures[1].pos = Vector2(200, 150) + Vector2.from_angle(deg_to_rad(angle_deg)) * dist
	return sim


func test_aim_assist_bends_a_close_8_way_attack_onto_the_opponent() -> void:
	var sim := _assist_setup(18.0)
	var me := sim.creatures[0]
	var foe := sim.creatures[1]
	var out := PlayerInput.assist(L | RIGHT, me, foe)
	assert_true(out & SimDefs.IN_AIM, "18 degrees off: assisted")
	assert_gt(SimDefs.aim_from_bits(out).dot((foe.pos - me.pos).normalized()), 0.995, "straight at them")
	assert_false(PlayerInput.assist(L | RIGHT, me, _assist_setup(40.0).creatures[1]) & SimDefs.IN_AIM,
		"40 degrees off: not assisted")
	var far := _assist_setup(10.0, 200.0)
	assert_false(PlayerInput.assist(L | RIGHT, far.creatures[0], far.creatures[1]) & SimDefs.IN_AIM,
		"out of range: not assisted")
	assert_false(PlayerInput.assist(RIGHT, me, foe) & SimDefs.IN_AIM, "only when attacking")


func test_mouse_attacks_aim_exactly_at_the_cursor() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var mo := MouseOrders.new()
	var cursor := me.pos + Vector2(40, 13)
	var out := mo.bits(me, sim.creatures[1], cursor, {"attack": true}, {"attack": true})
	assert_true(out & SimDefs.IN_AIM, "exact aim")
	assert_gt(SimDefs.aim_from_bits(out).dot((cursor - me.pos).normalized()), 0.995, "at the cursor")


func _cpu_aims(level: int) -> bool:
	var sim := MatchFactory.versus("cairn", "culvert")
	var cpu := CpuController.new(0, level, 5)
	var other := CpuController.new(1, 1, 9)
	for i in 900:
		var b := cpu.bits(sim)
		if b & SimDefs.IN_AIM:
			return true
		sim.step(PackedInt32Array([b, other.bits(sim)]))
	return false


func test_cpu_aims_exactly_except_on_easy() -> void:
	assert_false(_cpu_aims(0), "Easy keeps to 8 directions")
	assert_true(_cpu_aims(2), "Hard aims exactly")


func test_chef_cerebro_auto_throws_while_the_right_stick_aims() -> void:
	var sim := MatchFactory.versus("cerebro", "cairn")
	var chef := sim.creatures[0]
	var st := {"t": 0, "quiet": 0}
	var aim := PlayerInput.combine_pad(Vector2.ZERO, Vector2(0.2, 1.0), {}, {}, false, 0, true)
	aim &= (1 << PlayerInput.PAD_T_SHIFT) - 1
	var presses := 0
	for i in 6:
		if PlayerInput.autofire(aim, chef, st) & SimDefs.IN_LIGHT:
			presses += 1
	assert_eq(presses, 3, "Light pressed every other tick while the stick aims:")
	assert_true(PlayerInput.autofire(aim, chef, {"t": 0, "quiet": 0}) & SimDefs.IN_LIGHT, "from the very first tick")
	# Released: nothing.
	var idle := PlayerInput.combine_pad(Vector2.ZERO, Vector2.ZERO, {}, {}, false, 0, true)
	assert_false(PlayerInput.autofire(idle, chef, st) & SimDefs.IN_LIGHT, "stick released: no throws")
	# Another button pauses it, so that button isn't overwritten in the buffer.
	st = {"t": 0, "quiet": 0}
	PlayerInput.autofire(aim | SimDefs.IN_SKILL1, chef, st)
	for i in PlayerInput.AUTO_QUIET:
		assert_false(PlayerInput.autofire(aim, chef, st) & SimDefs.IN_LIGHT, "quiet after Skill 1 (tick %d)" % i)
	assert_true(PlayerInput.autofire(aim, chef, st) & SimDefs.IN_LIGHT, "then it picks up again")
	# Only for fighters whose data asks for it.
	var cairn := sim.creatures[1]
	assert_eq(PlayerInput.autofire(aim, cairn, {"t": 0, "quiet": 0}), aim, "Cairn doesn't auto-fire")


func test_chef_cerebro_glides_while_he_throws() -> void:
	var sim := MatchFactory.versus("cerebro", "cairn")
	var chef := sim.creatures[0]
	sim.creatures[1].pos = chef.pos + Vector2(140, 0)
	var start := chef.pos
	var st := {"t": 0, "quiet": 0}
	var throws := 0
	for i in 90:
		# Left stick up, right stick at Cairn: walk one way, throw the other.
		var b := PlayerInput.combine_pad(Vector2.UP, Vector2.RIGHT, {}, {}, chef.state == CreatureSim.State.ATTACK, 0, true)
		b &= (1 << PlayerInput.PAD_T_SHIFT) - 1
		b = PlayerInput.autofire(b, chef, st)
		sim.step(PackedInt32Array([b, 0]))
		for e in sim.events:
			if String(e["type"]) == "projectile" and int(e["who"]) == 0:
				throws += 1
	assert_gt(float(throws), 3.0, "a stream of throws:")
	assert_lt(chef.pos.y, start.y - 40.0, "while gliding up the screen the whole time:")
	assert_gt(chef.facing.x, 0.9, "still facing the right stick's aim:")


## Mister Crease plays twin-stick like Chef Cerebro: the right stick flicks his Paper Cut
## darts, and a craft still folds and throws through the auto-fire (press, then press again).
func test_mister_crease_auto_flicks_and_still_folds_and_throws() -> void:
	var sim := MatchFactory.versus("crease", "cairn")
	var c := sim.creatures[0]
	sim.creatures[1].pos = c.pos + Vector2(140, 0)
	var start := c.pos
	var st := {"t": 0, "quiet": 0}
	var darts := 0
	var shuriken := false
	for i in 150:
		var press := {}
		if i == 60 or i == 100:  # Heavy: fold the shuriken, then throw it
			press = {"heavy": true}
		var b := PlayerInput.combine_pad(Vector2.UP, Vector2.RIGHT, {}, press, c.state == CreatureSim.State.ATTACK, 0, true)
		b &= (1 << PlayerInput.PAD_T_SHIFT) - 1
		b = PlayerInput.autofire(b, c, st)
		sim.step(PackedInt32Array([b, 0]))
		if c.move_id == "heavy":
			shuriken = true
		for e in sim.events:
			if String(e["type"]) == "projectile" and int(e["who"]) == 0 and i < 60:
				darts += 1
	assert_true(darts >= 3, "a stream of darts from the right stick alone (%d; three in the first second since the third dart recovers slower, Oct 2026 kit pass):" % darts)
	assert_lt(c.pos.y, start.y - 20.0, "while he walks the other way:")
	assert_gt(c.facing.x, 0.9, "facing the right stick's aim:")
	assert_true(shuriken, "the folded shuriken still comes out on the second press")
