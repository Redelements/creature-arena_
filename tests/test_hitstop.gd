extends TestCase
## Hitstop: with two on the field a hit freezes the whole match (as it always has); on a
## crowded field (2 v 2 and up, a Brawl of three or four) only the attacker and the target
## freeze, a shot only its target, everyone else keeps moving, presses during the freeze
## are buffered, and a knockout neither freezes nor slows the match. All of it rolls back.

const L := SimDefs.IN_LIGHT
const D := SimDefs.IN_DODGE
const ACTION_BIT := {"skill_1": SimDefs.IN_SKILL1, "skill_2": SimDefs.IN_SKILL2, "heavy": SimDefs.IN_HEAVY}


## A bare crowded match: `spec` is [[id, team, pos], ...]; everyone faces right.
func _crowd(spec: Array) -> MatchSim:
	var m := MatchSim.new()
	for s in spec:
		var c := m.add_creature(MatchFactory.load_def(String(s[0])), s[2])
		c.team = int(s[1])
		c.facing = Vector2.RIGHT
	m.freeze_all = false
	return m


## Cairn (slot 0) a jab away from Culvert (slot 1), two more far off (slots 2, 3).
func _melee() -> MatchSim:
	var m := _crowd([["cairn", 0, Vector2(200, 164)], ["culvert", 1, Vector2(200, 164)],
		["barkley", 0, Vector2(400, 100)], ["sno", 1, Vector2(400, 228)]])
	var c0 := m.creatures[0]
	var c1 := m.creatures[1]
	c1.pos = c0.pos + Vector2(c0.radius + c1.radius + 2.0, 0)
	return m


func _ins(n: int, bits := {}) -> PackedInt32Array:
	var ins := PackedInt32Array()
	ins.resize(n)
	for k in bits:
		ins[int(k)] = int(bits[k])
	return ins


## Steps until a hit on `target` lands (returns the tick it did, -1 if none in `limit`).
func _until_hit(m: MatchSim, ins: PackedInt32Array, target: int, limit := 60) -> int:
	for i in limit:
		m.step(ins if i == 0 else _ins(m.creatures.size()))
		for e in m.events:
			if e["type"] == "hit" and int(e["target"]) == target:
				return i
	return -1


func test_with_two_on_the_field_a_hit_still_freezes_the_match() -> void:
	var m := MatchFactory.versus("cairn", "culvert")
	assert_true(m.freeze_all, "a 1v1 freezes all")
	m.creatures[1].pos = m.creatures[0].pos + Vector2(m.creatures[0].radius + m.creatures[1].radius + 2.0, 0)
	assert_true(_until_hit(m, _ins(2, {0: L}), 1) >= 0, "the jab lands")
	assert_gt(m.hitstop, 0, "the match freezes")
	assert_eq(m.creatures[0].hitstop, 0, "nobody carries their own:")
	assert_eq(m.creatures[1].hitstop, 0, "")


func test_a_crowded_field_freezes_only_the_two_involved() -> void:
	var m := _melee()
	assert_true(_until_hit(m, _ins(4, {0: L}), 1) >= 0, "the jab lands")
	var c := m.creatures
	assert_eq(m.hitstop, 0, "the match doesn't freeze:")
	assert_gt(c[0].hitstop, 0, "the attacker holds")
	assert_gt(c[1].hitstop, 0, "the target holds")
	assert_eq(c[2].hitstop, 0, "a teammate across the map doesn't:")
	assert_eq(c[3].hitstop, 0, "nor the other foe:")
	# While the two hold, the others walk on and the two stay put (a jab is no_flinch, so
	# the target's clock is the thing to watch, not its knockback).
	var p0 := c[0].pos
	var p1 := c[1].pos
	var p2 := c[2].pos
	var t0 := c[0].anim_t
	var t1 := c[1].anim_t
	var held := c[1].hitstop
	for i in held:
		m.step(_ins(4, {2: SimDefs.IN_RIGHT}))
	assert_gt(c[2].pos.distance_to(p2), 1.0, "slot 2 kept walking")
	assert_near(c[0].pos.x, p0.x, 0.001, "the attacker didn't move:")
	assert_near(c[1].pos.x, p1.x, 0.001, "nor the target:")
	assert_eq(c[0].anim_t, t0, "the attacker's clock stood still:")
	assert_eq(c[1].anim_t, t1, "and the target's:")
	assert_eq(c[1].hitstop, 0, "the hold is over")
	m.step(_ins(4))
	assert_eq(c[0].anim_t, t0 + 1, "then the attacker's clock runs again:")
	assert_eq(c[1].anim_t, t1 + 1, "and the target's:")


func test_a_press_during_the_hold_is_buffered() -> void:
	var m := _melee()
	assert_true(_until_hit(m, _ins(4, {0: L}), 1) >= 0, "the jab lands")
	var cairn := m.creatures[0]
	assert_gt(cairn.hitstop, 1, "held for more than a tick")
	m.step(_ins(4))  # release
	m.step(_ins(4, {0: L}))  # press again mid-hold
	assert_eq(cairn.buffered, "light", "the press is kept:")
	var second := run_until(m, func(): return cairn.move_id == "light_2", 40)
	assert_true(second, "and the second light comes out after the hold")


func test_a_shot_holds_only_its_target() -> void:
	var def := MatchFactory.load_def("hissy")
	var shot := ""
	for mid in ["skill_1", "skill_2", "heavy"]:
		if (def["moves"][mid] as Dictionary).has("projectile"):
			shot = mid
			break
	assert_true(shot != "", "Hissy has a shot")
	var m := _crowd([["hissy", 0, Vector2(200, 164)], ["cairn", 1, Vector2(270, 164)],
		["barkley", 0, Vector2(400, 60)], ["sno", 1, Vector2(400, 260)]])
	assert_true(_until_hit(m, _ins(4, {0: int(ACTION_BIT[shot])}), 1, 90) >= 0, "the shot lands")
	assert_gt(m.creatures[1].hitstop, 0, "the target holds")
	assert_eq(m.creatures[0].hitstop, 0, "the thrower doesn't:")
	assert_eq(m.hitstop, 0, "nor the match:")


func test_a_knockout_on_a_crowded_field_freezes_nobody() -> void:
	var m := _melee()
	m.creatures[1].hp = 1.0
	assert_true(_until_hit(m, _ins(4, {0: L}), 1) >= 0, "the jab lands")
	assert_eq(m.creatures[1].state, CreatureSim.State.KO, "and knocks out:")
	assert_eq(m.ko_freeze, 0, "no KO freeze:")
	assert_eq(m.slowmo, 0, "no slow motion:")
	var two := MatchFactory.versus("cairn", "culvert")
	two.creatures[1].pos = two.creatures[0].pos + Vector2(two.creatures[0].radius + two.creatures[1].radius + 2.0, 0)
	two.creatures[1].hp = 1.0
	assert_true(_until_hit(two, _ins(2, {0: L}), 1) >= 0, "")
	assert_gt(two.ko_freeze, 0, "with two on the field a KO still freezes")
	assert_gt(two.slowmo, 0, "and slows")


func test_the_modes_set_the_flag() -> void:
	assert_false(TeamSim.new([["cairn", "culvert"], ["culvert", "cairn"]], 2).sim.freeze_all, "2 v 2")
	assert_true(TeamSim.new([["cairn"], ["culvert"]], 1).sim.freeze_all, "1 v 1 team")
	assert_false(BrawlSim.new(["cairn", "culvert", "sno"]).sim.freeze_all, "a Brawl of three")
	assert_true(DuelSim.new([["cairn", "culvert"], ["culvert", "cairn"]]).sim.freeze_all, "a tag Duel")


func test_the_hold_rolls_back_exactly() -> void:
	var m := _melee()
	assert_true(_until_hit(m, _ins(4, {0: L}), 1) >= 0, "")
	var snap := m.snapshot()
	var at := m.state_digest()
	for i in 30:
		m.step(_ins(4, {0: L, 2: SimDefs.IN_RIGHT}))
	var end := m.state_digest()
	m.restore(snap)
	assert_eq(m.state_digest(), at, "restored mid-hold:")
	for i in 30:
		m.step(_ins(4, {0: L, 2: SimDefs.IN_RIGHT}))
	assert_eq(m.state_digest(), end, "re-simulated the same:")
