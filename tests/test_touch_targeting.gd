extends TestCase
## Touch target lock (TouchTarget, through PlayerInput's touch path): a tap picks a foe by
## each priority and aims at it after; the lock drops on a knockout, out of range and out
## of sight (brush, through Vision), and never picks a hidden foe; enemy portraits lock
## the foe tapped; Capture the Flag's objective is the foe carrying our flag; the Light
## chase walks into reach and hits, the stick held away beats it, and it never walks into
## a chasm (round a gap when there is one, else it stops at the edge).

const SCREEN := Vector2(480, 270)


func _touch_input() -> PlayerInput:
	var pin := PlayerInput.new()
	pin.pad_device = PlayerInput.NO_PAD
	pin.touch.layout(SCREEN)
	pin.device = PlayerInput.Device.TOUCH
	return pin


func _down(p: TouchPad, i: int, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = true
	p.feed(e)


func _up(p: TouchPad, i: int, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = false
	p.feed(e)


func _drag(p: TouchPad, i: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = at
	p.feed(e)


func _tap(p: TouchPad, b: String) -> void:
	_down(p, 1, p.center(b))
	_up(p, 1, p.center(b))


## Steps a 1v1 sim with player 0 on touch for `n` ticks; true if it ever fell or stood
## over a pit.
func _play(sim: MatchSim, pin: PlayerInput, n: int, watch_pits := false) -> bool:
	var me := sim.creatures[0]
	var fell := false
	for i in n:
		sim.step(PackedInt32Array([pin.bits(sim, 0, Vector2.ZERO), 0]))
		if watch_pits and (me.state == CreatureSim.State.FALLING
				or TerrainGrid.is_pit(sim.terrain.get_cell(sim.terrain.world_to_cell(me.pos)))):
			fell = true
	return fell


## Me (slot 0) and three foes, placed by hand on open floor: A dead ahead (right) but
## further, B close behind, C further still with little health.
func _crowd() -> Dictionary:
	var t := TeamSim.new([["cairn", "culvert"], ["culvert", "cairn"]], 2)
	var sim := t.sim
	var me := sim.creatures[0]
	var foes: Array = []
	for i in sim.creatures.size():
		if me.is_foe(sim.creatures[i]):
			foes.append(i)
	var mate := -1
	for i in sim.creatures.size():
		if i != 0 and not me.is_foe(sim.creatures[i]):
			mate = i
	me.pos = Vector2(250, 200)
	me.facing = Vector2.RIGHT
	sim.creatures[mate].pos = Vector2(250, 330)
	sim.creatures[foes[0]].pos = Vector2(320, 205)  # A: ahead, 70 away
	sim.creatures[foes[1]].pos = Vector2(215, 190)  # B: behind, 36 away
	return {"sim": sim, "a": foes[0], "b": foes[1]}


func test_pick_by_each_priority() -> void:
	var d := _crowd()
	var sim: MatchSim = d["sim"]
	var a := int(d["a"])
	var b := int(d["b"])
	assert_eq(TouchTarget.pick(sim, 0, [], TouchTarget.Priority.AIM, Vector2.RIGHT), a,
		"closest to aim: the one ahead, though further")
	assert_eq(TouchTarget.pick(sim, 0, [], TouchTarget.Priority.AIM, Vector2.LEFT), b,
		"aimed the other way: the one behind")
	assert_eq(TouchTarget.pick(sim, 0, [], TouchTarget.Priority.AIM, Vector2.UP), b,
		"nobody in the cone: the nearest")
	assert_eq(TouchTarget.pick(sim, 0, [], TouchTarget.Priority.NEAREST, Vector2.RIGHT), b, "nearest")
	sim.creatures[a].hp = 10.0
	assert_eq(TouchTarget.pick(sim, 0, [], TouchTarget.Priority.LOWEST_HP, Vector2.LEFT), a, "lowest health")
	var hid := []
	hid.resize(sim.creatures.size())
	hid.fill(false)
	hid[b] = true
	assert_eq(TouchTarget.pick(sim, 0, hid, TouchTarget.Priority.NEAREST, Vector2.RIGHT), a,
		"a hidden foe is never picked, even the nearest")
	sim.creatures[a].pos = Vector2(250 + TouchTarget.LOCK_RANGE + 20, 200)
	assert_eq(TouchTarget.pick(sim, 0, hid, TouchTarget.Priority.NEAREST, Vector2.RIGHT), -1,
		"too far and hidden: nobody")


func test_tap_locks_and_later_taps_aim_at_the_lock() -> void:
	var d := _crowd()
	var sim: MatchSim = d["sim"]
	var a := int(d["a"])
	var b := int(d["b"])
	var pin := _touch_input()
	pin.target.chase_on = false
	_tap(pin.touch, "light")
	var bits := pin.bits(sim, 0, Vector2.ZERO)
	assert_eq(pin.target.lock, a, "Light tap (aiming right by facing) locks the one ahead")
	assert_true(bits & SimDefs.IN_AIM, "aimed exactly")
	assert_eq(SimDefs.aim_index(SimDefs.aim_from_bits(bits)), SimDefs.aim_index(sim.creatures[a].pos - sim.creatures[0].pos),
		"at the locked foe")
	for i in 20:
		pin.bits(sim, 0, Vector2.ZERO)
	sim.creatures[0].facing = Vector2.LEFT  # turned toward B: the lock is sticky
	_tap(pin.touch, "skill_2")
	bits = pin.bits(sim, 0, Vector2.ZERO)
	assert_true(bits & SimDefs.IN_SKILL2, "a tap-cast")
	assert_eq(pin.target.lock, a, "still on A")
	assert_eq(SimDefs.aim_index(SimDefs.aim_from_bits(bits)), SimDefs.aim_index(sim.creatures[a].pos - sim.creatures[0].pos),
		"the tap-cast aims at the lock")
	assert_true(b != a, "")


func test_drag_aim_overrides_the_lock() -> void:
	var d := _crowd()
	var sim: MatchSim = d["sim"]
	var pin := _touch_input()
	pin.target.chase_on = false
	pin.target.lock = int(d["a"])
	var p := pin.touch
	var c := p.center("skill_1")
	_down(p, 1, c)
	_drag(p, 1, c + Vector2(0, 60))  # down
	pin.bits(sim, 0, Vector2.ZERO)
	_up(p, 1, c + Vector2(0, 60))
	var bits := pin.bits(sim, 0, Vector2.ZERO)
	assert_true(bits & SimDefs.IN_SKILL1, "thrown")
	assert_true(SimDefs.aim_from_bits(bits).y > 0.99, "where the finger said, not at the lock")
	assert_eq(pin.target.lock, int(d["a"]), "the lock stays for later")


func test_lock_drops_on_ko_range_and_sight() -> void:
	for why in ["ko", "range", "hidden"]:
		var sim := MatchFactory.training("cairn")
		var me := sim.creatures[0]
		var foe := sim.creatures[1]
		me.pos = Vector2(200, 200)
		foe.pos = Vector2(300, 200)
		var pin := _touch_input()
		pin.target.chase_on = false
		_tap(pin.touch, "light")
		pin.bits(sim, 0, Vector2.ZERO)
		assert_eq(pin.target.lock, 1, why + ": locked")
		match why:
			"ko":
				foe.state = CreatureSim.State.KO
			"range":
				foe.pos = me.pos + Vector2(TouchTarget.LOCK_RANGE + 10, 0)
			"hidden":
				pin.touch_hidden = [false, true]
		var bits := pin.bits(sim, 0, Vector2.ZERO)
		assert_eq(pin.target.lock, -1, why + ": the lock drops")
		assert_false(bits & SimDefs.IN_AIM, why + ": and nothing aims at it any more")


func test_brush_hides_the_lock_through_vision() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var foe := sim.creatures[1]
	me.pos = Vector2(150, 200)
	foe.pos = Vector2(290, 200)
	var pin := _touch_input()
	pin.target.chase_on = false
	var vision := Vision.new()
	var seen := func() -> Array:
		return [false, not vision.team_sees(sim, me.team, foe)]
	pin.touch_hidden = seen.call()
	_tap(pin.touch, "light")
	pin.bits(sim, 0, Vector2.ZERO)
	assert_eq(pin.target.lock, 1, "seen: locked")
	var c := sim.terrain.world_to_cell(foe.pos)
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			sim.terrain.set_cell(c + Vector2i(dx, dy), TerrainGrid.BRUSH)
	sim.step(PackedInt32Array([0, 0]))  # the sim notes who stands in brush (covered)
	pin.touch_hidden = seen.call()
	assert_true(bool(pin.touch_hidden[1]), "the foe in the brush is hidden from us")
	pin.bits(sim, 0, Vector2.ZERO)
	assert_eq(pin.target.lock, -1, "the lock drops: it would give the hidden foe away")
	_tap(pin.touch, "light")
	var bits := pin.bits(sim, 0, Vector2.ZERO)
	assert_eq(pin.target.lock, -1, "and a tap won't pick it")
	assert_false(bits & SimDefs.IN_AIM, "nothing aims at where it hides")
	assert_false(pin.target.lock_on(sim, 0, 1, pin.touch_hidden), "nor a portrait")


func test_portrait_tap_locks_that_foe() -> void:
	var d := _crowd()
	var sim: MatchSim = d["sim"]
	var a := int(d["a"])
	var b := int(d["b"])
	var pin := _touch_input()
	var p := pin.touch
	p.set_picks([a, b], false)
	assert_true(p.portrait_center(b) != Vector2.INF, "B has a portrait")
	_down(p, 2, p.portrait_center(b))
	_up(p, 2, p.portrait_center(b))
	pin.bits(sim, 0, Vector2.ZERO)
	assert_eq(pin.target.lock, b, "B locked from its portrait")
	assert_eq(p.fingers_down(), 0, "a portrait takes no finger")
	for k in p.pick_entries().size():
		for btn in p.buttons():
			assert_gt(p.pick_center(k).distance_to(p.center(btn)), TouchPad.PICK_R + p.radius(btn),
				"portrait %d clear of %s" % [k, btn])


func test_ctf_objective_is_the_foe_carrying_our_flag() -> void:
	var t := TeamSim.new([["cairn"], ["culvert"]], 1, TeamSim.load_rules(TeamSim.CTF_PATH))
	var me := t.sim.creatures[0]
	var foe := t.sim.creatures[1]
	assert_eq(TouchTarget.ctf_objective(t, me), -1, "our flag is home: no objective")
	t.flag_carrier[me.team] = foe.id
	assert_eq(TouchTarget.ctf_objective(t, me), 1, "the foe carrying our flag")
	var plain := TeamSim.new([["cairn"], ["culvert"]], 1)
	assert_eq(TouchTarget.ctf_objective(plain, plain.sim.creatures[0]), -1, "not Capture the Flag: none")
	var pad := TouchPad.new()
	pad.layout(SCREEN)
	pad.set_picks([], true)
	_down(pad, 3, pad.pick_center(0))
	assert_true(pad.objective_requested, "the objective button asks for it")


func test_chase_walks_into_reach_and_hits() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var foe := sim.creatures[1]
	me.pos = Vector2(180, 200)
	foe.pos = Vector2(310, 200)
	var pin := _touch_input()
	_tap(pin.touch, "light")
	var first := pin.bits(sim, 0, Vector2.ZERO)
	assert_true(pin.target.chasing, "out of reach, in range: a chase")
	assert_false(first & SimDefs.IN_LIGHT, "no light thrown at thin air")
	sim.step(PackedInt32Array([first, 0]))
	_play(sim, pin, 150)
	assert_lt(me.pos.distance_to(foe.pos), MouseOrders.chase_reach(me, foe) + 12.0, "walked up to it:")
	assert_lt(foe.hp, foe.max_hp, "and hit it:")
	assert_false(pin.target.chasing, "the chase is over")


func test_chase_off_just_aims() -> void:
	var sim := MatchFactory.training("cairn")
	sim.creatures[0].pos = Vector2(180, 200)
	sim.creatures[1].pos = Vector2(310, 200)
	var pin := _touch_input()
	pin.target.chase_on = false
	_tap(pin.touch, "light")
	var bits := pin.bits(sim, 0, Vector2.ZERO)
	assert_false(pin.target.chasing, "Chase target off")
	assert_true(bits & SimDefs.IN_LIGHT, "the light comes out where you stand")


func test_stick_held_away_beats_the_chase() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	me.pos = Vector2(250, 200)
	sim.creatures[1].pos = Vector2(360, 200)
	var pin := _touch_input()
	var p := pin.touch
	_tap(p, "light")
	sim.step(PackedInt32Array([pin.bits(sim, 0, Vector2.ZERO), 0]))
	assert_true(pin.target.chasing, "chasing")
	_play(sim, pin, 10)
	_down(p, 0, p.rest_spot())
	_drag(p, 0, p.rest_spot() + Vector2(-25, 0))  # away from the foe
	var x := me.pos.x
	_play(sim, pin, 20)
	assert_false(pin.target.chasing, "the stick ended the chase")
	assert_lt(me.pos.x, x - 20.0, "and walked away, no rubber band:")
	# Pushed toward the foe the stick just walks, the chase goes on.
	_up(p, 0, p.rest_spot() + Vector2(-25, 0))
	_play(sim, pin, 15)
	_tap(p, "light")
	_play(sim, pin, 1)
	assert_true(pin.target.chasing, "chasing again")
	_down(p, 0, p.rest_spot())
	_drag(p, 0, p.rest_spot() + Vector2(25, 2))
	_play(sim, pin, 5)
	assert_true(pin.target.chasing, "the stick toward it doesn't end it")


## A chasm band from top to bottom between me and the foe: there's no way round, so the
## chase stops at the edge and never walks in.
func test_chase_never_walks_into_a_chasm() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var foe := sim.creatures[1]
	me.pos = Vector2(200, 200)
	foe.pos = Vector2(330, 200)
	var t := sim.terrain
	for cy in t.rows:
		for x in [260, 268, 276]:
			t.sink(Vector2i(t.world_to_cell(Vector2(x, 0)).x, cy))
	var pin := _touch_input()
	_tap(pin.touch, "light")
	var fell := _play(sim, pin, 260, true)
	assert_false(fell, "never stepped into the chasm")
	assert_lt(me.pos.x, 262.0, "stayed on our side:")
	assert_eq(foe.hp, foe.max_hp, "and couldn't hit")


## The same band with a gap: the chase goes round through it (the nav grid's path) and
## hits, still never over a pit.
func test_chase_goes_round_a_chasm() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var foe := sim.creatures[1]
	me.pos = Vector2(200, 200)
	foe.pos = Vector2(320, 200)
	var t := sim.terrain
	var gap0 := t.world_to_cell(Vector2(0, 236)).y
	var gap1 := t.world_to_cell(Vector2(0, 268)).y
	for cy in t.rows:
		if cy >= gap0 and cy <= gap1:
			continue
		for x in [260, 268]:
			t.sink(Vector2i(t.world_to_cell(Vector2(x, 0)).x, cy))
	var pin := _touch_input()
	_tap(pin.touch, "light")
	var fell := _play(sim, pin, 239, true)
	assert_false(fell, "never over a pit")
	assert_gt(me.pos.x, 270.0, "came through the gap:")
	assert_lt(foe.hp, foe.max_hp, "and hit:")


func test_reset_clears_the_lock() -> void:
	var pin := _touch_input()
	pin.target.lock = 1
	pin.target.chasing = true
	pin.reset()
	assert_eq(pin.target.lock, -1, "a new match: no lock carried over")
	assert_false(pin.target.chasing, "nor a chase")
