extends TestCase
## League-style mouse orders and gamepad aiming, driven without real devices.

const NONE := {}


func _held(names: Array) -> Dictionary:
	var d := {}
	for n in names:
		d[n] = true
	return d


## Steps the match with the player (side 0) driven by MouseOrders.
func _drive(sim: MatchSim, mo: MouseOrders, cursor: Vector2, held: Dictionary, pressed: Dictionary,
		ticks := 1, p1 := 0) -> void:
	for i in ticks:
		var me := sim.creatures[0]
		var b := mo.bits(me, sim.nearest_opponent(me), cursor, held, pressed if i == 0 else NONE)
		sim.step(PackedInt32Array([b, p1]))


func test_right_click_walks_to_the_spot_and_stops() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var mo := MouseOrders.new()
	var target := Vector2(120, 120)
	_drive(sim, mo, target, _held(["move"]), _held(["move"]))
	_drive(sim, mo, Vector2(400, 230), NONE, NONE, 120)  # cursor wanders off; the order stands
	assert_lt(me.pos.distance_to(target), 4.0, "arrived:")
	assert_true(mo.dest == Vector2.INF, "order finished")
	_drive(sim, mo, Vector2(400, 230), NONE, NONE, 10)
	assert_lt(me.pos.distance_to(target), 4.0, "stays put:")


func test_holding_right_click_steers() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var mo := MouseOrders.new()
	_drive(sim, mo, Vector2(300, 100), _held(["move"]), _held(["move"]))
	_drive(sim, mo, Vector2(60, 220), _held(["move"]), NONE, 60)
	assert_lt(me.pos.x, 170.0, "followed the cursor left:")
	assert_gt(me.pos.y, 164.0, "and down:")


func test_right_click_opponent_auto_attacks() -> void:
	var sim := MatchFactory.training("cairn")
	var dummy := sim.creatures[1]
	var mo := MouseOrders.new()
	_drive(sim, mo, dummy.pos + Vector2(0, -12), _held(["move"]), _held(["move"]))
	assert_true(mo.chase, "attack order")
	_drive(sim, mo, Vector2(10, 10), NONE, NONE, 150)
	assert_lt(dummy.hp, dummy.max_hp - 5.0, "walked over and kept hitting:")


func test_abilities_aim_at_the_cursor() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var me := sim.creatures[0]
	sim.creatures[1].pos = Vector2(400, 220)
	var mo := MouseOrders.new()
	assert_true(me.facing.x > 0.0, "starts facing right")
	_drive(sim, mo, me.pos + Vector2(-60, 0), _held(["skill_2"]), _held(["skill_2"]))
	assert_eq(me.move_id, "skill_2", "Rush:")
	assert_true(me.facing.x < -0.9, "Rush aimed left at the cursor")


func test_charged_heavy_follows_the_cursor() -> void:
	var sim := MatchFactory.versus("culvert", "cairn")
	var me := sim.creatures[0]
	sim.creatures[1].pos = Vector2(400, 220)
	var mo := MouseOrders.new()
	_drive(sim, mo, me.pos + Vector2(40, 0), _held(["heavy"]), _held(["heavy"]))
	assert_true(me.charging, "charging")
	_drive(sim, mo, me.pos + Vector2(0, -50), _held(["heavy"]), NONE, 10)
	assert_true(me.facing.y < -0.9, "slam aimed up while charging")


func test_dodge_rolls_toward_the_cursor() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var mo := MouseOrders.new()
	var start := me.pos
	_drive(sim, mo, me.pos + Vector2(0, 60), _held(["dodge"]), _held(["dodge"]))
	assert_eq(me.state, CreatureSim.State.DODGE, "rolling:")
	_drive(sim, mo, me.pos, NONE, NONE, 20)
	assert_gt(me.pos.y - start.y, 25.0, "rolled down:")


func test_s_stops() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var mo := MouseOrders.new()
	_drive(sim, mo, Vector2(450, 100), _held(["move"]), _held(["move"]))
	_drive(sim, mo, Vector2(450, 100), NONE, NONE, 10)
	_drive(sim, mo, Vector2(450, 100), _held(["stop"]), _held(["stop"]))
	var p := me.pos
	_drive(sim, mo, Vector2(450, 100), NONE, NONE, 30)
	assert_lt(me.pos.distance_to(p), 4.0, "stopped (only sliding to a halt):")


func test_dodge_plus_guard_is_a_breakaway() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var me := sim.creatures[0]
	me.energy = 80.0
	me.combo_hits = 3
	me.enter_hitstun(30, Vector2.ZERO)
	var mo := MouseOrders.new()
	_drive(sim, mo, me.pos, _held(["guard", "dodge"]), _held(["dodge"]))
	assert_eq(me.state, CreatureSim.State.IDLE, "broke free:")
	assert_near(me.energy, 30.0, 0.001, "energy spent:")


func test_gamepad_right_stick_aims_attacks() -> void:
	var held := {"light": true}
	var pressed := {"light": true}
	var out := PlayerInput.combine_pad(Vector2(1, 0), Vector2(0, -1), held, pressed, false, 0)
	var bits := out & 0xFFFF
	assert_true(bits & SimDefs.IN_LIGHT, "light pressed")
	assert_true(bits & SimDefs.IN_UP, "aimed up with the right stick")
	assert_false(bits & SimDefs.IN_RIGHT, "not the movement direction")
	assert_eq(out >> 16, MouseOrders.AIM_HOLD, "keeps aiming for the buffer window:")


func test_gamepad_without_aim_uses_the_left_stick() -> void:
	var out := PlayerInput.combine_pad(Vector2(-1, 0), Vector2.ZERO, {}, {"skill_1": true}, false, 0)
	var bits := out & 0xFFFF
	assert_true(bits & SimDefs.IN_SKILL1, "skill pressed")
	assert_true(bits & SimDefs.IN_LEFT, "goes the way you move")


func test_cursor_over_creature() -> void:
	var sim := MatchFactory.training("cairn")
	var d := sim.creatures[1]
	assert_true(MouseOrders.is_on_creature(d, d.pos + Vector2(0, -20)), "on the body")
	assert_false(MouseOrders.is_on_creature(d, d.pos + Vector2(40, 0)), "beside it")
