extends TestCase
## The skirmisher below Rage (`CpuController._neutral_skirmish`, Gillbert at Normal): it keeps
## the poke band instead of walking into its own lights, casts its hook only down an open
## lane (another foe's body on the line before the mark: no cast, a sidestep off the line,
## `_lane_blocker` / `_lane_side`), marks the reachable foe with the shortest lights (the
## mage) over the nearest, and dives only on a foe that is stuck (`_foe_stuck`), never on one
## that merely has an empty stamina bar. Any CPU's hook (a shot that reels or pulls) skips a
## blocked lane too (`_neutral_kit`).

const NORMAL := 1


## A bare match: `spec` is [[id, team, pos], ...]; everyone faces right.
func _match(spec: Array) -> MatchSim:
	TeamIntent.reset()
	var m := MatchSim.new()
	for s in spec:
		var c := m.add_creature(MatchFactory.load_def(String(s[0])), s[2])
		c.team = int(s[1])
		c.facing = Vector2.RIGHT
	return m


## Steps `sim` with CPU `cpu` driving creature 0 and everyone else standing still, calling
## `each` (sim, tick) after every tick; stops early when `each` returns true.
func _play(sim: MatchSim, cpu: CpuController, ticks: int, each: Callable) -> void:
	for t in ticks:
		var inp := PackedInt32Array()
		inp.resize(sim.creatures.size())
		inp[0] = cpu.bits(sim)
		sim.step(inp)
		if each.call(sim, t):
			return


## The reels (Cast Line connecting) in this tick's events: target ids.
func _reeled(sim: MatchSim) -> Array:
	var out := []
	for e in sim.events:
		if String(e["type"]) == "reel" and int(e.get("attacker", -1)) == 0:
			out.append(int(e.get("target", -1)))
	return out


func test_a_tank_in_the_lane_is_not_hooked_and_he_steps_off_the_line() -> void:
	# Culvert stands square on the line to Crease. The hook would bite him first (and reel
	# Gillbert onto the tank): no cast into him; he moves off the line and hooks Crease.
	var sim := _match([["gillbert", 0, Vector2(150, 200)], ["culvert", 1, Vector2(240, 200)],
		["crease", 1, Vector2(330, 200)]])
	var cpu := CpuController.new(0, NORMAL, 3)
	var st := {"tank": false, "mage": false, "off": 0.0}  # (a lambda captures locals by value)
	_play(sim, cpu, 600, func(s: MatchSim, _t: int) -> bool:
		for who in _reeled(s):
			st["tank"] = bool(st["tank"]) or who == 1
			st["mage"] = bool(st["mage"]) or who == 2
		var g: CreatureSim = s.creatures[0]
		var line := (s.creatures[2].pos - g.pos).normalized()
		st["off"] = maxf(float(st["off"]), absf((s.creatures[1].pos - g.pos).cross(line)))
		return bool(st["mage"]))
	assert_false(bool(st["tank"]), "the tank in the lane is never hooked")
	assert_gt(float(st["off"]), 30.0, "he steps off the line until the tank is clear of it")
	assert_true(bool(st["mage"]), "and hooks the mage through the gap")


func test_the_lane_check_sees_the_body_on_the_line() -> void:
	var sim := _match([["gillbert", 0, Vector2(150, 200)], ["culvert", 1, Vector2(240, 210)],
		["crease", 1, Vector2(330, 200)]])
	var cpu := CpuController.new(0, NORMAL, 3)
	var g := sim.creatures[0]
	var tank := sim.creatures[1]
	var mage := sim.creatures[2]
	assert_eq(cpu._lane_blocker(sim, g, mage, mage.pos, "skill_2"), tank, "a body 10 px off the line blocks it:")
	assert_eq(cpu._lane_blocker(sim, g, tank, tank.pos, "skill_2"), null, "nothing in front of the tank:")
	tank.pos = Vector2(240, 270)
	assert_eq(cpu._lane_blocker(sim, g, mage, mage.pos, "skill_2"), null, "70 px off the line, open:")
	tank.pos = Vector2(380, 200)
	assert_eq(cpu._lane_blocker(sim, g, mage, mage.pos, "skill_2"), null, "behind the mark, open:")
	tank.pos = Vector2(240, 200)
	tank.root = 30
	assert_true(CpuController._better_mark(tank), "a rooted blocker is the better mark")


func test_an_open_lane_marks_the_mage_over_the_nearer_tank() -> void:
	# Both in range and both lanes open: the shortest lights (the back line) is the mark.
	var sim := _match([["gillbert", 0, Vector2(150, 200)], ["culvert", 1, Vector2(240, 150)],
		["crease", 1, Vector2(260, 250)]])
	var cpu := CpuController.new(0, NORMAL, 3)
	var g := sim.creatures[0]
	assert_eq(cpu._cast_mark(sim, g, "skill_2", [40, 200]), sim.creatures[2], "the mage, not the nearer tank:")
	var st := {"hooked": -1}
	_play(sim, cpu, 400, func(s: MatchSim, _t: int) -> bool:
		var r := _reeled(s)
		if not r.is_empty():
			st["hooked"] = int(r[0])
		return int(st["hooked"]) >= 0)
	assert_eq(int(st["hooked"]), 2, "the first hook goes to the mage:")


func test_with_an_open_lane_he_casts_from_the_band() -> void:
	var sim := _match([["gillbert", 0, Vector2(150, 200)], ["culvert", 1, Vector2(290, 200)]])
	var cpu := CpuController.new(0, NORMAL, 5)
	var st := {"from": -1.0}
	_play(sim, cpu, 400, func(s: MatchSim, _t: int) -> bool:
		var g: CreatureSim = s.creatures[0]
		if g.state == CreatureSim.State.ATTACK and g.move_id == "skill_2" and g.state_t == 1:
			st["from"] = g.pos.distance_to(s.creatures[1].pos)
		return float(st["from"]) >= 0.0)
	assert_gt(float(st["from"]), 80.0, "he casts from the band, well outside his lights")


func test_an_empty_stamina_bar_is_no_reason_to_dive() -> void:
	# A foe with no stamina can't dodge (the old Rage trigger), but it still walks and swings:
	# he keeps the band. The hook is kept on cooldown so only the walk is measured.
	var sim := _match([["gillbert", 0, Vector2(150, 200)], ["culvert", 1, Vector2(270, 200)]])
	var cpu := CpuController.new(0, NORMAL, 7)
	var st := {"closest": INF, "dived": false}
	_play(sim, cpu, 300, func(s: MatchSim, t: int) -> bool:
		s.creatures[1].stamina = 0.0
		s.creatures[0].cooldowns["skill_2"] = 60
		st["dived"] = bool(st["dived"]) or cpu._engage_t > 0
		if t > 60:
			st["closest"] = minf(float(st["closest"]), s.creatures[0].pos.distance_to(s.creatures[1].pos))
		return false)
	assert_false(bool(st["dived"]), "no dive")
	assert_gt(float(st["closest"]), 80.0, "he stays out in the band")


func test_a_rooted_foe_is_dived_on() -> void:
	var sim := _match([["gillbert", 0, Vector2(150, 200)], ["culvert", 1, Vector2(270, 200)]])
	var cpu := CpuController.new(0, NORMAL, 7)
	var st := {"closest": INF}
	_play(sim, cpu, 240, func(s: MatchSim, _t: int) -> bool:
		s.creatures[1].root = 30
		s.creatures[0].cooldowns["skill_2"] = 60
		st["closest"] = minf(float(st["closest"]), s.creatures[0].pos.distance_to(s.creatures[1].pos))
		return float(st["closest"]) < 45.0)
	assert_lt(float(st["closest"]), 45.0, "he goes in on a foe that can't move")


func test_a_tanks_hook_skips_a_blocked_lane_too() -> void:
	# Craglash's Mountain Maw (a pull) at a Normal tank: Cerebro on the line before Crease.
	# `_neutral_kit` never throws the hook at Crease through him.
	var sim := _match([["craglash", 0, Vector2(150, 200)], ["crease", 1, Vector2(290, 200)],
		["cerebro", 1, Vector2(220, 200)]])
	var cpu := CpuController.new(0, NORMAL, 9)
	var me := sim.creatures[0]
	var lined := 0
	for k in 200:
		cpu._out = 0
		cpu._prev = 0
		if cpu._neutral_kit(sim, me, sim.creatures[1], sim.creatures[1].pos - me.pos, 140.0, 40.0):
			lined += 1 if cpu._out & SimDefs.IN_SKILL2 else 0
	assert_eq(lined, 0, "no Maw thrown through Cerebro:")
	sim.creatures[2].pos = Vector2(220, 300)
	for k in 200:
		cpu._out = 0
		cpu._prev = 0
		if cpu._neutral_kit(sim, me, sim.creatures[1], sim.creatures[1].pos - me.pos, 140.0, 40.0):
			lined += 1 if cpu._out & SimDefs.IN_SKILL2 else 0
	assert_gt(lined, 0, "with the lane open it is")
