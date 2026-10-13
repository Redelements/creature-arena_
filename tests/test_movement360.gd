extends TestCase
## 360-degree movement and uniform reach: the left stick walks and aims any way it
## points, and every hit reaches the same distance in every direction.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY


func test_move_bits_round_trip_any_angle() -> void:
	for deg in [0, 13, 30, 47, 90, 128, 200, 333]:
		var v := Vector2.from_angle(deg_to_rad(float(deg)))
		var b := SimDefs.move_bits(v)
		assert_true(b & SimDefs.IN_MOVE, "move angle set at %d°" % deg)
		assert_gt(SimDefs.move_from_bits(b).dot(v), 0.996, "within 3 degrees at %d°:" % deg)
		assert_true(b & (SimDefs.IN_UP | SimDefs.IN_DOWN | SimDefs.IN_LEFT | SimDefs.IN_RIGHT),
			"the rough direction bits come along at %d°" % deg)
	assert_eq(SimDefs.move_bits(Vector2.ZERO), 0, "no stick, no bits:")
	# Old 8-way input (WASD, replays) still walks.
	assert_eq(SimDefs.move_from_bits(SimDefs.IN_RIGHT), Vector2.RIGHT)


func test_the_left_stick_walks_at_its_exact_angle() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var me := sim.creatures[0]
	var stick := Vector2.from_angle(deg_to_rad(30.0))  # between right and down-right
	var out := PlayerInput.combine_pad(stick, Vector2.ZERO, {}, {}, false, 0, false)
	var start := me.pos
	run(sim, out, 40)
	var went := (me.pos - start).normalized()
	assert_gt(went.dot(stick), 0.996, "walked at 30 degrees, not 0 or 45:")
	assert_gt(me.facing.dot(stick), 0.996, "and faces that way:")


func test_attacks_without_an_aim_go_where_the_left_stick_points() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var me := sim.creatures[0]
	var stick := Vector2.from_angle(deg_to_rad(-60.0))
	var b := SimDefs.move_bits(stick) | L
	run(sim, b, 1)
	assert_eq(me.state, CreatureSim.State.ATTACK, "jab thrown")
	assert_gt(me.facing.dot(stick), 0.996, "the jab goes at -60 degrees:")


## Whether `atk`'s move from `bit`, thrown at a dummy `gap` px away along `dir`, connects.
func _connects(atk: String, dir: Vector2, gap: float, bit: int) -> bool:
	var sim := MatchFactory.versus(atk, "dummy")
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	a.pos = SimDefs.floor_rect().get_center() - dir * 20.0
	a.facing = dir
	d.pos = a.pos + dir * gap
	var b := bit | SimDefs.aim_bits(dir)
	for i in 50:
		sim.step(PackedInt32Array([b if i == 0 else 0, 0]))
		for e in sim.events:
			if String(e["type"]) in ["hit", "block", "armor"] and int(e.get("attacker", -1)) == 0:
				return true
	return false


## The furthest gap (to 1/8 px) the move connects at along `dir`.
func _reach(atk: String, dir: Vector2, bit: int) -> float:
	var lo := 10.0
	var hi := 110.0
	if not _connects(atk, dir, lo, bit):
		return 0.0
	while hi - lo > 0.125:
		var mid := (lo + hi) * 0.5
		if _connects(atk, dir, mid, bit):
			lo = mid
		else:
			hi = mid
	return lo


func test_every_hit_reaches_the_same_distance_in_every_direction() -> void:
	var checked := 0
	for atk in MatchFactory.FIGHTERS:
		var def := MatchFactory.load_def(atk)
		for pair in [["light_1", L], ["heavy", H]]:
			var mv: Dictionary = def["moves"][pair[0]]
			if mv.has("projectile") or mv.has("dash") or mv.has("leap"):
				continue  # thrown or travelling: covered by their own tests
			checked += 1
			var side := _reach(atk, Vector2.RIGHT, int(pair[1]))
			assert_gt(side, 10.0, "%s %s connects sideways:" % [atk, pair[0]])
			for deg in [45, 90, 135, 180, 225, 270, 315]:
				var r := _reach(atk, Vector2.from_angle(deg_to_rad(float(deg))), int(pair[1]))
				assert_near(r, side, 0.5, "%s %s at %d° vs sideways:" % [atk, pair[0], deg])
	assert_gt(float(checked), 12.0, "moves measured:")
