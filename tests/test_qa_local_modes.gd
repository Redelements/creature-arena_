extends TestCase
## QA part 6a (2026-10-29): the local modes, 55 Brawl, 56-59 the 2v2 local team modes, 60-62 the
## 4v4 co-op modes, driven through Main like a table of friends would: seats and sides, the
## pick, the HUD and camera with four people, pause and a pad unplugged, co-op CPUs, the match
## to its result, Rematch x3, the main menu and a different mode, and no voice offline.
## Report: docs/qa/part6a-local-modes.md.

const MAIN := preload("res://src/game/main.gd")
const TEST_SETTINGS := "user://test_qa_local_modes.cfg"
const BRAWL := 55
const LOCAL_MODES := [55, 56, 57, 58, 59, 60, 61, 62]
const LABELS := {55: "Brawl", 56: "Team battle: 2v2 local", 57: "Team Deathmatch: 2v2 local",
	58: "Sinkhole: 2v2 local", 59: "King of the Crater: 2v2 local", 60: "Team battle: 4v4 co-op vs CPU",
	61: "Team Deathmatch: 4v4 co-op vs CPU", 62: "Capture the Flag: 4v4 co-op vs CPU"}
const HURRY_AT := 400
const HURRY_LEFT := 90
const BUDGET := 14000
var _overtime_ticks := 0


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _press(action: String) -> void:
	for down in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		_root().push_input(ev)


func _game(locals := 4, cpu_vs_cpu := false) -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	Progress.reset_for_tests("user://test_progress_qa_local_%d.json" % Time.get_ticks_usec())
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	g._skip_select = true
	g._cli_locals = locals
	g._cpu_vs_cpu = cpu_vs_cpu
	g.level = 1
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)
		g._process(1.0 / 60.0)


func _leftovers(g: Node) -> String:
	var out: Array = []
	if not g.fx.flags.is_empty():
		out.append("flags %d" % g.fx.flags.size())
	if not g.fx.shrines.is_empty():
		out.append("shrines %d" % g.fx.shrines.size())
	if not g.fx.caravan.is_empty():
		out.append("caravan")
	if not g.fx.wanted.is_empty():
		out.append("wanted %d" % g.fx.wanted.size())
	return ", ".join(out)


func _hurry(g: Node) -> void:
	if g.flow != g.Flow.FIGHT:
		return
	if g.team_battle != null:
		var tb = g.team_battle
		if tb.overtime and _overtime_ticks >= 1800:
			tb.overtime = false
			tb.score[0] = int(tb.score[0]) + 1
			tb.timer = 1
		tb.timer = mini(tb.timer, HURRY_LEFT)
	elif g.brawl != null:
		g.brawl.timer = mini(g.brawl.timer, HURRY_LEFT)
	else:
		g.timer = mini(g.timer, HURRY_LEFT)


func _play_to_over(g: Node, label: String) -> bool:
	var fought := 0
	_overtime_ticks = 0
	for t in BUDGET:
		_tick(g, 1)
		if g.flow == g.Flow.FIGHT:
			fought += 1
			_overtime_ticks = _overtime_ticks + 1 if g.team_battle != null and g.team_battle.overtime else 0
			if fought >= HURRY_AT and fought % 60 == 0:
				_hurry(g)
		if g.flow == g.Flow.MATCH_OVER and g.ui.is_open():
			return true
	fail("%s never reached its results in %d ticks (flow %d)" % [label, BUDGET, g.flow])
	return false


func _load_count(g: Node) -> Array:
	return [g.get_child_count(), g.find_children("*", "Timer", true, false).size(),
		g.find_children("*", "AudioStreamPlayer", true, false).size()
		+ g.find_children("*", "AudioStreamPlayer2D", true, false).size(), _root().get_child_count()]


# ---------------------------------------------------------------- 0: the indices

func test_the_indices_this_file_uses_are_still_those_modes() -> void:
	for m in LABELS:
		assert_eq(String(MAIN.MODES[m]["label"]), String(LABELS[m]), "MODES[%d]" % m)
	assert_eq(MAIN.mode_index("Brawl"), BRAWL, "the Brawl label is mode 55")


# ---------------------------------------------------------------- 1: setup

## 2, 3 and 4 people in every local mode: the slot of each seat, its side, and one input each.
func test_seats_get_slots_and_sides_in_every_local_mode() -> void:
	for m in LOCAL_MODES:
		for n in [2, 3, 4]:
			var g := _game(n)
			g._start_match(m)
			var label := "%s, %d people" % [LABELS[m], n]
			assert_eq(g.seats.humans, n, label + ": seats")
			var slots: Array = g.local_slots()
			assert_eq(slots.size(), n, label + ": local slots " + str(slots))
			var seen := {}
			var inputs := {}
			for s in slots:
				var side: int = g.sides[s]
				assert_false(seen.has(side), label + ": one slot per seat")
				seen[side] = true
				if side != g.Side.PLAYER:
					inputs[g._local_input(side).get_instance_id()] = true
			assert_eq(inputs.size(), n - 1, label + ": each seat past player 1 has its own PlayerInput")
			var cfg: Dictionary = MAIN.MODES[m]
			var teams: Array = slots.map(func(s): return g.sim.creatures[s].team)
			match String(cfg.get("seating", "ffa")):
				"coop":
					for t in teams:
						assert_eq(t, 0, label + ": everyone on side 0")
					assert_eq(g.sim.creatures.size(), 8, label + ": 4 v 4")
					for i in 8:
						if not (i in slots):
							assert_eq(g.sides[i], g.Side.CPU, label + ": the rest are CPUs")
				"teams":
					for s in slots:
						var seat: int = MAIN.LOCAL_SIDES.find(g.sides[s])
						assert_eq(g.sim.creatures[s].team, seat % 2, label + ": seat %d alternates sides" % seat)
					assert_eq(g.sim.creatures.size(), 4, label + ": 2 v 2")
					for i in 4:
						if not (i in slots):
							assert_eq(g.sides[i], g.Side.CPU, label + ": a CPU fills the rest")
				_:
					var all := {}
					for i in g.sim.creatures.size():
						all[g.sim.creatures[i].team] = true
					assert_eq(all.size(), 4, label + ": a Brawl has four teams of one")
					assert_eq(slots, range(n), label + ": humans first, CPUs after")
			g.free()


## The join screen with four pads: one cursor per seat on the pick, all four pick at once.
func test_four_seats_pick_at_once_with_a_cursor_each() -> void:
	for m in [BRAWL, 56, 60]:
		var g := _game(1)
		g._skip_select = false
		g._start_match(m)
		assert_true(g.ui.top() is SeatScreen, str(LABELS[m]) + ": the join screen")
		_press("ui_accept")
		for d in [0, 1, 2]:
			g.seats.claim(d)
		assert_eq(g.seats.joined(), 4, str(LABELS[m]) + ": four seated")
		_press("ui_accept")
		assert_true(g.ui.top() is CharacterSelect, str(LABELS[m]) + ": the pick")
		var cs: CharacterSelect = g.ui.top()
		assert_eq(cs.players, 4, "a picker a seat")
		assert_eq(cs.cursor.size(), cs.columns, "a cursor per column")
		assert_gt(float(cs.columns), 3.0, "four columns in " + str(LABELS[m]))
		for p in 4:
			cs.pick(p, true)
		assert_true(cs.is_done(), "all four picked at once")
		cs._process(CharacterSelect.START_DELAY + 0.1)
		assert_eq(g.local_slots().size(), 4, str(LABELS[m]) + ": four people play")
		g.free()


func test_one_pad_cannot_hold_two_seats() -> void:
	var s := LocalSeats.new()
	s.begin(4)
	assert_eq(s.claim(3), 0, "the first press is player 1's")
	assert_eq(s.claim(3), 0, "the same pad again keeps its seat")
	assert_eq(s.joined(), 1, "no second seat from the same pad")
	assert_eq(s.claim(4), 1, "")
	assert_eq(s.claim(4), 1, "")
	assert_eq(s.claim(3), 0, "")
	assert_eq(s.joined(), 2, "still two")
	for k in 4:
		for j in range(k + 1, 4):
			if s.device_of(k) >= 0 and s.device_of(j) >= 0:
				assert_true(s.device_of(k) != s.device_of(j), "seats %d and %d differ" % [k, j])
	assert_eq(s.holder_of(4), 1, "")


# ---------------------------------------------------------------- 2: in the match

func test_hud_panels_for_four_people_are_disjoint_and_fit() -> void:
	for m in LOCAL_MODES:
		var g := _game(4)
		g._start_match(m)
		_tick(g, 5)
		var plan: Dictionary = g.hud.panel_plan()
		var seen := {}
		for col in 2:
			for key in ["panels", "cards"]:
				for s in plan[key][col]:
					assert_false(seen.has(s), "%s: slot %d is drawn once" % [LABELS[m], s])
					seen[s] = true
		for s in g.local_slots():
			assert_true(seen.has(s), "%s: seat slot %d has a panel" % [LABELS[m], s])
		assert_lt(g.hud.panels_height(), float(g.get_viewport().get_visible_rect().size.y) * 0.6,
			str(LABELS[m]) + ": the panels leave most of the screen")
		g.free()


func test_the_camera_keeps_every_standing_human_in_shot() -> void:
	for m in LOCAL_MODES:
		var g := _game(4)
		g._start_match(m)
		_tick(g, 420)
		var z: float = g.camera.zoom.x
		var half: Vector2 = g.get_viewport().get_visible_rect().size * 0.5 / z
		var c: Vector2 = g.camera.get_screen_center_position()
		var view := Rect2(c - half, half * 2.0)
		for s in g.local_slots():
			var cr: CreatureSim = g.sim.creatures[s]
			if cr.state == CreatureSim.State.KO:
				continue
			assert_true(view.has_point(cr.pos), "%s: human slot %d at %s inside %s" % [LABELS[m], s, str(cr.pos), str(view)])
		g.free()


func test_pause_and_a_pad_unplugged_mid_match() -> void:
	for m in [BRAWL, 56, 62]:
		var g := _game(4)
		g._start_match(m)
		_tick(g, 200)
		assert_eq(g.flow, g.Flow.FIGHT, "")
		var label: String = LABELS[m]
		for k in [1, 2, 3]:
			g.seats.inputs[k].pad_device = 4 + k
		g._open_pause()
		assert_true(g.paused and g.ui.top() is PauseScreen, label + ": paused")
		var t0: int = g.sim.tick
		_tick(g, 30)
		assert_eq(g.sim.tick, t0, label + ": nothing moves while paused")
		g._close_ui()
		g.paused = false
		_tick(g, 10)
		assert_gt(float(g.sim.tick), float(t0), label + ": and Resume runs again")
		var ev := InputEventJoypadButton.new()
		ev.device = 6
		ev.button_index = JOY_BUTTON_START
		ev.pressed = true
		assert_eq(g.seats.owner_of_event(ev), 2, label + ": that Start is player 3's")
		for k in [1, 2, 3]:
			var dev: int = 4 + k
			g._on_pad_changed(dev, false)
			assert_true(g.paused, label + ": seat %d lost its pad: paused" % k)
			assert_eq(g.seats.device_of(k), PlayerInput.NO_PAD, "")
			g._close_ui()
			g.paused = false
			g._on_pad_changed(dev + 10, true)
			assert_false(g.paused, label + ": a pad plugged in never pauses")
			assert_true(g.seats.device_of(k) >= 0, label + ": seat %d has a pad again" % k)
			g.seats.inputs[k].pad_device = dev
		_tick(g, 60)
		g.free()


# ---------------------------------------------------------------- 3: co-op CPUs

func test_coop_cpus_are_foes_at_the_chosen_level_and_never_target_a_teammate() -> void:
	for m in [60, 61, 62]:
		for locals in [2, 4]:
			var g := _game(locals)
			g.level = 2
			g._start_match(m)
			var label := "%s, %d people" % [LABELS[m], locals]
			var cpu_n := 0
			for i in g.sim.creatures.size():
				var cr: CreatureSim = g.sim.creatures[i]
				if g.sides[i] == g.Side.CPU:
					cpu_n += 1
					assert_eq((g.cpus[i] as CpuController).level, 2, label + ": slot %d's level" % i)
				else:
					assert_eq(cr.team, 0, label + ": humans on side 0")
			assert_eq(cpu_n, 8 - locals, label + ": CPU count")
			for i in range(4, 8):
				assert_eq(g.sim.creatures[i].team, 1, label + ": the CPU side")
			for t in 900:
				_tick(g, 1)
				if t % 15 != 0:
					continue
				for i in g.sim.creatures.size():
					if g.cpus[i] == null:
						continue
					var cpu: CpuController = g.cpus[i]
					var me: CreatureSim = g.sim.creatures[i]
					var foe := cpu._pick_target(g.sim, me)
					if foe != null:
						assert_true(me.is_foe(foe), label + ": slot %d picked teammate %d" % [i, foe.id])
					if cpu._target != null:
						assert_true(me.is_foe(cpu._target), label + ": slot %d kept a teammate" % i)
			g.free()


# ---------------------------------------------------------------- 4 and 5: the match, rematch, menu

func test_each_mode_plays_to_results_listing_everyone_and_leaves_nothing() -> void:
	var g := _game(4, true)
	g._open_menu()
	_tick(g, 60)
	var base := _load_count(g)
	for m in LOCAL_MODES:
		var label: String = LABELS[m]
		g._start_match(m)
		if not _play_to_over(g, label):
			g._open_menu()
			continue
		var rows: Array = g.results_data()["rows"]
		assert_eq(rows.size(), g.sim.creatures.size(), label + ": every fighter has a results row")
		var ids := {}
		for r in rows:
			ids[int(r["id"])] = true
		assert_eq(ids.size(), rows.size(), label + ": distinct rows")
		assert_false(g.ui.top().find_children("*", "ResultsPanel", true, false).is_empty(), label + ": the results panel is up")
		g._back_to_row()
		_tick(g, 60)
		assert_eq(_leftovers(g), "", label + ": mode objects after the menu")
		assert_eq(_load_count(g), base, label + ": nodes, timers, audio players, root children after return")
	g.free()


func test_rematch_three_times_then_other_modes_without_a_restart() -> void:
	var g := _game(4, true)
	g._open_menu()
	_tick(g, 60)
	var base := _load_count(g)
	for m in [55, 62, 56]:
		var label: String = LABELS[m]
		g._start_match(m)
		var ids: Array = []
		var sides_then: Array = []
		for round in 4:
			if not _play_to_over(g, "%s round %d" % [label, round]):
				break
			if round == 0:
				for c in g.sim.creatures:
					ids.append(String(c.def["id"]))
				sides_then = g.sides.duplicate()
			if round == 3:
				break
			(g.ui.top().rows()[0] as Control).grab_focus()
			assert_eq((_root().gui_get_focus_owner() as Button).text, "Rematch", label)
			_press("ui_accept")
			assert_eq(g.mode, m, label + ": same mode")
			assert_false(g.ui.top() is CharacterSelect or g.ui.top() is SeatScreen, label + ": no seats/pick again")
			var again: Array = []
			for c in g.sim.creatures:
				again.append(String(c.def["id"]))
			assert_eq(again, ids, label + ": same fighters, rematch %d" % (round + 1))
			assert_eq(g.sides, sides_then, label + ": same seats and sides")
		g._open_menu()
		_tick(g, 60)
		assert_eq(_leftovers(g), "", label + ": nothing left behind the menu")
	assert_eq(_load_count(g), base, "after three modes and nine rematches: the same nodes and players")
	g.free()


# ---------------------------------------------------------------- 6: voice offline

func test_no_voice_in_local_modes() -> void:
	for m in LOCAL_MODES:
		var g := _game(4)
		g._start_match(m)
		_tick(g, 120)
		var v: VoiceView = g.voice_view
		assert_true(v != null, "")
		assert_false(v.sending, str(LABELS[m]) + ": not sending")
		assert_false(v._capturing, str(LABELS[m]) + ": no capture")
		assert_true(v._capture == null and v._mic == null, str(LABELS[m]) + ": no mic player or capture effect")
		assert_true(v._players.is_empty(), str(LABELS[m]) + ": no speaker players")
		assert_true(v.heard.is_empty(), "")
		assert_eq(g.netplay, null, "no netplay")
		g.free()
