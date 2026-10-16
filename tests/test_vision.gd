extends TestCase
## Vision: brush hides a fighter from the other team (not from itself or its allies)
## unless they're close, it attacks, or it was just in a hit; fences and walls block the
## line of sight (a smashed wall doesn't); nobody's hidden when nobody here plays; the
## camera doesn't frame a hidden foe; the CPU goes by where it last saw a foe.


func _with(pieces: Array, left := "cairn", right := "culvert") -> MatchSim:
	var sim := MatchFactory.versus(left, right)
	sim.terrain.load_map({"pieces": pieces})
	return sim


func _cell(sim: MatchSim, x: int, y: int) -> Vector2:
	return sim.terrain.cell_center(Vector2i(x, y))


const BRUSH := {"kind": "brush", "rect": [40, 14, 8, 8]}


# ------------------------------------------------------------------ brush

func test_brush_hides_a_fighter_from_the_other_team_but_not_from_its_own() -> void:
	var sim := _with([BRUSH])
	var hider := sim.creatures[0]
	var foe := sim.creatures[1]
	hider.pos = _cell(sim, 43, 17)
	foe.pos = _cell(sim, 20, 17)
	run(sim, 0, 1)
	assert_true(hider.covered, "standing in the brush")
	var v := Vision.new()
	assert_false(v.team_sees(sim, foe.team, hider), "the other team can't see him")
	assert_false(v.can_see(sim, foe, hider), "nor can the foe himself")
	assert_true(v.team_sees(sim, hider.team, hider), "his own team can")
	assert_true(v.can_see(sim, hider, hider), "he can see himself")
	assert_true(v.can_see(sim, hider, foe), "and he sees out of the brush")
	# A teammate across the floor still sees him.
	var ally := sim.add_creature(MatchFactory.load_def("sno"), _cell(sim, 70, 30))
	ally.team = hider.team
	assert_true(v.can_see(sim, ally, hider), "an ally sees him from anywhere")


func test_close_up_he_is_seen() -> void:
	var sim := _with([BRUSH])
	var hider := sim.creatures[0]
	var foe := sim.creatures[1]
	hider.pos = _cell(sim, 43, 17)
	foe.pos = hider.pos + Vector2(Vision.HIDE_RANGE + 6.0, 0)
	run(sim, 0, 1)
	var v := Vision.new()
	assert_false(v.team_sees(sim, foe.team, hider), "just out of range: hidden")
	foe.pos = hider.pos + Vector2(Vision.HIDE_RANGE - 4.0, 0)
	assert_true(v.team_sees(sim, foe.team, hider), "within %.0f px: seen" % Vision.HIDE_RANGE)
	# Two foes in the same patch see each other once they're that close.
	foe.pos = hider.pos + Vector2(0, 20)
	run(sim, 0, 1)
	assert_true(foe.covered and hider.covered, "both in the brush")
	assert_true(v.can_see(sim, hider, foe) and v.can_see(sim, foe, hider), "and they see each other")


func test_attacking_gives_him_away_from_the_first_startup_frame() -> void:
	var sim := _with([BRUSH])
	var hider := sim.creatures[0]
	var foe := sim.creatures[1]
	hider.pos = _cell(sim, 43, 17)
	foe.pos = _cell(sim, 15, 17)
	run(sim, 0, 1)
	var v := Vision.new()
	assert_false(v.team_sees(sim, foe.team, hider), "hidden while still")
	run(sim, SimDefs.IN_LIGHT, 1)
	assert_eq(hider.state, CreatureSim.State.ATTACK, "he's swinging")
	assert_true(hider.state_t <= 1, "from the start of the swing")
	assert_true(v.team_sees(sim, foe.team, hider), "a swing gives him away")


func test_a_hit_reveals_him_for_half_a_second() -> void:
	var sim := _with([BRUSH])
	var hider := sim.creatures[0]
	var foe := sim.creatures[1]
	hider.pos = _cell(sim, 43, 17)
	foe.pos = _cell(sim, 15, 17)
	run(sim, 0, 1)
	var v := Vision.new()
	assert_false(v.team_sees(sim, foe.team, hider), "hidden")
	# A thrown hit lands on him (any hit: landed or taken, a block too).
	v.observe([{"type": "hit", "tick": sim.tick, "attacker": foe.id, "target": hider.id}])
	assert_true(v.team_sees(sim, foe.team, hider), "the hit gives him away")
	run(sim, 0, Vision.REVEAL_TICKS)
	assert_eq(hider.state, CreatureSim.State.IDLE, "(the test hit didn't stun him)")
	assert_true(v.team_sees(sim, foe.team, hider), "for %d ticks" % Vision.REVEAL_TICKS)
	run(sim, 0, 1)
	assert_false(v.team_sees(sim, foe.team, hider), "then he's gone again")
	# Landing one counts the same way.
	v.observe([{"type": "block", "tick": sim.tick, "attacker": hider.id, "target": foe.id}])
	assert_true(v.team_sees(sim, foe.team, hider), "a blocked hit he threw gives him away too")
	# Events whose "by" isn't a fighter don't confuse it.
	v.observe([{"type": "duel_over", "tick": sim.tick + 100, "winner": 0, "by": "ko"}])


func test_real_sim_hits_carry_the_tick() -> void:
	var sim := _with([])
	var a := sim.creatures[0]
	var d := sim.creatures[1]
	a.pos = _cell(sim, 40, 17)
	d.pos = a.pos + Vector2(22, 0)
	a.facing = Vector2.RIGHT
	var hit := {}
	for i in 30:
		run(sim, SimDefs.IN_LIGHT if i == 0 else 0, 1)
		for e in sim.events:
			if String(e["type"]) == "hit":
				hit = e
		if not hit.is_empty():
			break
	assert_false(hit.is_empty(), "the jab lands")
	assert_eq(int(hit.get("tick", -1)), sim.tick, "hit events say when")
	var v := Vision.new()
	v.observe([hit])
	assert_eq(v.clash_tick(a), sim.tick, "the attacker was in a hit")
	assert_eq(v.clash_tick(d), sim.tick, "so was the target")


# ------------------------------------------------------------------ line of sight

func test_fences_and_walls_block_sight_and_a_smashed_wall_doesnt() -> void:
	for kind in ["fence", "wall"]:
		var sim := _with([{"kind": kind, "rect": [40, 10, 1, 22]}])
		var a := sim.creatures[0]
		var b := sim.creatures[1]
		a.pos = _cell(sim, 30, 17)
		b.pos = _cell(sim, 50, 17)
		run(sim, 0, 1)
		var v := Vision.new()
		assert_false(v.team_sees(sim, a.team, b), "a %s in the way: unseen" % kind)
		assert_false(v.team_sees(sim, b.team, a), "both ways (%s)" % kind)
		b.pos = _cell(sim, 50, 1)
		assert_true(v.team_sees(sim, a.team, b), "round the end of the %s: seen" % kind)
	var sim := _with([{"kind": "wall", "rect": [40, 4, 1, 28]}])
	var a := sim.creatures[0]
	var b := sim.creatures[1]
	a.pos = _cell(sim, 30, 17)
	b.pos = _cell(sim, 50, 17)
	sim.terrain.smash(Vector2i(40, 17))
	assert_true(Vision.clear_line(sim.terrain, a.pos, b.pos), "through the smashed gap: seen")
	assert_true(Vision.new().team_sees(sim, a.team, b), "(team vision too)")


func test_chasms_shallows_holes_and_brush_dont_block_sight() -> void:
	for kind in ["chasm", "shallows", "brush"]:
		var sim := _with([{"kind": kind, "rect": [38, 4, 4, 28]}])
		assert_true(Vision.clear_line(sim.terrain, _cell(sim, 30, 17), _cell(sim, 50, 17)),
			"sight crosses %s" % kind)
	var sim := _with([])
	sim.terrain.damage_rect(_cell(sim, 40, 17), 6, 6, 2)
	assert_true(Vision.clear_line(sim.terrain, _cell(sim, 30, 17), _cell(sim, 50, 17)), "and holes")


func test_the_line_walk_is_cell_exact() -> void:
	var sim := _with([{"kind": "fence", "rect": [40, 17, 1, 1]}])
	var t := sim.terrain
	assert_false(Vision.clear_line(t, _cell(sim, 30, 17), _cell(sim, 50, 17)), "straight through the post")
	assert_true(Vision.clear_line(t, _cell(sim, 30, 16), _cell(sim, 50, 16)), "a row above: clear")
	assert_false(Vision.clear_line(t, _cell(sim, 35, 12), _cell(sim, 45, 22)), "diagonally through it")
	assert_true(Vision.clear_line(t, _cell(sim, 35, 14), _cell(sim, 45, 24)), "a diagonal beside it: clear")
	assert_false(Vision.clear_line(t, _cell(sim, 35, 13), _cell(sim, 45, 23)), "one grazing its corner: blocked")
	assert_false(Vision.clear_line(t, _cell(sim, 40, 5), _cell(sim, 40, 30)), "straight down through it")
	# Two posts touching only at a corner: no peeking between them.
	var sim2 := _with([{"kind": "wall", "rect": [40, 17, 1, 1]}, {"kind": "wall", "rect": [41, 16, 1, 1]}])
	assert_false(Vision.clear_line(sim2.terrain, _cell(sim2, 37, 20), _cell(sim2, 44, 13)),
		"not through the gap at the corner")
	# The cells the two stand in don't count (a ghost dash stood in a fence).
	assert_true(Vision.clear_line(t, _cell(sim, 40, 17), _cell(sim, 50, 17)), "standing in the fence")
	# The same answer from either end, and on the same cell.
	assert_eq(Vision.clear_line(t, _cell(sim, 50, 20), _cell(sim, 31, 14)),
		Vision.clear_line(t, _cell(sim, 31, 14), _cell(sim, 50, 20)), "symmetric")
	assert_true(Vision.clear_line(t, _cell(sim, 30, 17), _cell(sim, 30, 17)), "same cell")


# ------------------------------------------------------------------ the screen

func _game() -> Node:
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = "user://test_settings_vision.cfg"
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	return g


## Puts brush on the floor and the CPU (slot 1) in it, far from slot 0.
func _hide_slot_1(g: Node) -> void:
	var sim: MatchSim = g.sim
	sim.terrain.load_map({"pieces": [BRUSH]})
	g.vision.clear()
	sim.creatures[0].pos = _cell(sim, 12, 17)
	sim.creatures[1].pos = _cell(sim, 43, 17)
	sim.step(PackedInt32Array([0, 0]))
	g._update_vision([])


func test_the_screen_hides_a_foe_in_brush_from_the_player_only() -> void:
	var g := _game()
	g._start_match(0)  # Cairn vs CPU
	_hide_slot_1(g)
	assert_true(g.sim.creatures[1].covered, "the CPU is in the brush")
	assert_false(g._is_hidden(0), "you always see yourself")
	assert_true(g._is_hidden(1), "the CPU in the brush is hidden from you")
	assert_false(g.fx.shown(g.sim.creatures[1]), "no bar, aim mark or particles for it")
	# Its dust and dodges don't show; a hit on you from it does.
	assert_false(g.fx._event_shown({"type": "dodge", "pos": Vector2.ZERO, "power": 0.0, "who": 1}), "its dodge")
	assert_true(g.fx._event_shown({"type": "hit", "pos": Vector2.ZERO, "power": 1.0, "attacker": 1, "target": 0}),
		"its hit on you")
	assert_true(g.fx._event_shown({"type": "duel_over", "pos": Vector2.ZERO, "power": 1.0, "winner": 0, "by": "ko"}),
		"match events")
	# Your own fighter in the brush stays on your screen (faint).
	g.sim.creatures[0].pos = _cell(sim_of(g), 41, 15)
	g.sim.creatures[1].pos = _cell(sim_of(g), 12, 17)
	g.sim.step(PackedInt32Array([0, 0]))
	g._update_vision([])
	assert_true(g.sim.creatures[0].covered, "you're in the brush now")
	assert_false(g._is_hidden(0), "and still on your screen")
	assert_false(g._is_hidden(1), "the CPU in the open is seen")
	g.free()


func sim_of(g: Node) -> MatchSim:
	return g.sim


func test_nobody_is_hidden_when_nobody_here_plays() -> void:
	var g := _game()
	g._start_match(2)  # CPU vs CPU
	_hide_slot_1(g)
	assert_true(g.sim.creatures[1].covered, "a CPU is in the brush")
	assert_eq(g._viewer_team(), -1, "no viewer team")
	assert_false(g._is_hidden(1), "watching, everyone is shown")
	g.free()
	# Local versus: players on both sides, so nobody is hidden either.
	var g2 := _game()
	g2._start_match(8)
	g2._on_teams_chosen([["cairn"], ["sno"]])
	_hide_slot_1(g2)
	assert_eq(g2._viewer_team(), -1, "two local players on opposite sides")
	assert_false(g2._is_hidden(1), "both are shown")
	g2.free()


func test_the_camera_leaves_a_hidden_foe_out_of_the_shot() -> void:
	var g := _game()
	g._start_match(0)
	_hide_slot_1(g)
	var view := Vector2(1440, 810)
	var size := SimDefs.arena_size()
	g._cam_zoom = 0.0
	g._frame_fight(view, size)
	var hidden_mid: Vector2 = g._cam_follow
	assert_near(hidden_mid.x, g.sim.creatures[0].pos.x, 1.0, "framed on you alone:")
	# Out of the brush, the camera frames both.
	g.sim.creatures[1].pos = _cell(g.sim, 60, 17)
	g.sim.step(PackedInt32Array([0, 0]))
	g._update_vision([])
	assert_false(g._is_hidden(1), "seen now")
	g._cam_zoom = 0.0
	g._frame_fight(view, size)
	assert_gt(g._cam_follow.x, hidden_mid.x + 40.0, "framing both:")
	g.free()


# ------------------------------------------------------------------ the CPU

func test_the_cpu_loses_a_foe_behind_a_wall_and_aims_where_it_last_saw_it() -> void:
	var sim := _with([{"kind": "wall", "rect": [40, 4, 2, 28]}])
	var cpu := CpuController.new(1, 1, 3)
	var me := sim.creatures[1]
	var foe := sim.creatures[0]
	me.pos = _cell(sim, 30, 17)
	foe.pos = _cell(sim, 36, 10)
	run(sim, 0, 1)
	cpu.bits(sim)
	var seen_at := foe.pos
	assert_eq(cpu._seen(foe), seen_at, "in the open, it sees the foe:")
	foe.pos = _cell(sim, 46, 17)
	run(sim, 0, 1)
	cpu.bits(sim)
	assert_false(Vision.clear_line(sim.terrain, me.pos, foe.pos), "the wall is in the way")
	assert_eq(cpu._seen(foe), seen_at, "behind the wall it goes by where it last saw it:")
	assert_false(cpu._sees(foe), "out of sight")
	assert_eq(cpu._aim_point(me, foe), seen_at, "and aims there, not at the foe:")
	# Round the end of the wall, it sees again.
	me.pos = _cell(sim, 41, 2)
	run(sim, 0, 1)
	cpu.bits(sim)
	assert_eq(cpu._seen(foe), foe.pos, "a clear line again: seen:")


func test_the_cpu_picks_targets_by_what_its_team_can_see() -> void:
	var sim := _with([{"kind": "wall", "rect": [40, 4, 2, 28]}], "cairn", "culvert")
	var me := sim.creatures[1]
	var near := sim.creatures[0]
	var other := sim.add_creature(MatchFactory.load_def("sno"), _cell(sim, 12, 17))
	other.team = near.team
	var cpu := CpuController.new(1, 1, 3)
	me.pos = _cell(sim, 30, 17)
	near.pos = _cell(sim, 5, 30)  # seen far away first
	run(sim, 0, 1)
	cpu.bits(sim)
	near.pos = _cell(sim, 45, 17)  # now just behind the wall, nearer than the other
	run(sim, 0, 1)
	cpu.bits(sim)
	assert_false(cpu._sees(near), "the near one is behind the wall")
	assert_eq(cpu._nearest_known(sim, me), other, "so it goes for the one it can see")


func test_a_cpu_sees_what_its_teammates_see() -> void:
	var sim := _with([{"kind": "wall", "rect": [40, 4, 2, 28]}])
	var me := sim.creatures[1]
	var foe := sim.creatures[0]
	var mate := sim.add_creature(MatchFactory.load_def("sno"), _cell(sim, 55, 17))
	mate.team = me.team
	me.pos = _cell(sim, 30, 17)
	foe.pos = _cell(sim, 48, 17)
	run(sim, 0, 1)
	var cpu := CpuController.new(1, 1, 3)
	cpu.bits(sim)
	assert_false(Vision.clear_line(sim.terrain, me.pos, foe.pos), "a wall between it and the foe")
	assert_true(cpu._sees(foe), "but its teammate sees the foe, so it does too")
	assert_eq(cpu._seen(foe), foe.pos, "where it really is:")


func test_a_team_with_nobody_standing_sees_everyone() -> void:
	var sim := _with([BRUSH])
	var hider := sim.creatures[0]
	var foe := sim.creatures[1]
	hider.pos = _cell(sim, 43, 17)
	foe.pos = _cell(sim, 15, 17)
	run(sim, 0, 1)
	var v := Vision.new()
	assert_false(v.team_sees(sim, foe.team, hider), "hidden while the foe stands")
	foe.state = CreatureSim.State.KO
	assert_true(v.team_sees(sim, foe.team, hider), "knocked out (waiting to respawn): the screen shows everyone")
	assert_false(v.can_see(sim, foe, hider), "though the knocked-out fighter itself sees nothing")
