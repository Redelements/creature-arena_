extends TestCase
## The Surge-ready signal: the simulation says when a meter fills, every fighter has its
## own aura while it's full (with a burst the moment it fills), and the sound depends on
## whose side it is.

const MOTES := ["pebbles", "embers", "drops", "leaves", "bubbles", "rings", "wisps", "clods",
	"glints", "flakes"]


func _ready_events(sim: MatchSim) -> Array:
	return sim.events.filter(func(e): return String(e["type"]) == "surge_ready")


func test_the_sim_says_once_when_a_meter_fills() -> void:
	var sim := MatchFactory.versus("cairn", "sno")
	var a := sim.creatures[0]
	sim.events.clear()
	sim.gain_energy(a, 60.0)
	assert_eq(_ready_events(sim).size(), 0, "not full yet: nothing")
	sim.gain_energy(a, 60.0)
	var got := _ready_events(sim)
	assert_eq(got.size(), 1, "it fills: one event")
	assert_near(a.energy, CreatureSim.MAX_ENERGY, 0.001, "capped at full:")
	if got.size() == 1:
		assert_eq(int(got[0]["who"]), a.id, "whose meter:")
		assert_eq(int(got[0]["team"]), a.team, "and their side:")
	sim.events.clear()
	sim.gain_energy(a, 30.0)
	assert_eq(_ready_events(sim).size(), 0, "already full: no repeat")
	a.energy = 0.0
	sim.gain_energy(a, 100.0)
	assert_eq(_ready_events(sim).size(), 1, "spent and filled again: a new one")


func test_landing_hits_fills_the_meter_and_signals_in_a_real_fight() -> void:
	var sim := MatchFactory.versus("cairn", "culvert")
	var a := sim.creatures[0]
	a.energy = CreatureSim.MAX_ENERGY - 1.0
	sim.creatures[1].pos = a.pos + Vector2(26, 0)
	var seen := false
	for i in 40:
		sim.step(PackedInt32Array([SimDefs.IN_LIGHT if i % 6 == 0 else 0, 0]))
		if not _ready_events(sim).is_empty():
			seen = true
			break
	assert_true(seen, "a jab tops the meter up and the event comes out")


func test_every_fighter_has_an_aura_of_its_own() -> void:
	var looks := {}
	for id in MatchFactory.FIGHTERS:
		var au: Dictionary = MatchFactory.load_def(id).get("surge_aura", {})
		assert_false(au.is_empty(), id + " has a surge_aura")
		var cols: Array = au.get("colors", [])
		assert_eq(cols.size(), 3, id + " has outer, inner and core colours:")
		assert_true(String(au.get("motes", "")) in MOTES, id + " has a known kind of mote: " + str(au.get("motes")))
		var key := "%s|%s" % [str(cols), String(au.get("motes", ""))]
		assert_false(looks.has(key), "%s looks different from %s" % [id, looks.get(key, "")])
		looks[key] = id


func _view(id: String) -> CreatureView:
	var sim := MatchFactory.training(id)
	var v := CreatureView.new()
	v.setup(sim.creatures[0])
	return v


func test_the_aura_lights_up_with_a_burst_when_the_meter_fills() -> void:
	for id in MatchFactory.FIGHTERS:
		var v := _view(id)
		var c := v.c
		c.shield = 0.0  # Craglash's Stoneskin rim would win (its own test below)
		v.refresh()
		assert_false(v.aura.lit, id + ": no aura with an empty meter")
		assert_eq(v.mat.get_shader_parameter("rim"), 0.0, id + ": and no rim:")
		c.energy = CreatureSim.MAX_ENERGY
		v.refresh()
		assert_true(v.aura.lit and v.aura_front.lit, id + ": full: the aura is on, both layers")
		assert_eq(v.aura.burst_t, 1, id + ": with a burst starting:")
		assert_gt(float(v.mat.get_shader_parameter("rim")), 0.5, id + ": and a glowing rim:")
		var rc: Color = v.mat.get_shader_parameter("rim_color")
		assert_true(rc.is_equal_approx(v.aura.rim_color()), id + ": in its own colour")
		for i in SurgeAura.BURST_TICKS + 2:
			v.refresh()
		assert_eq(v.aura.burst_t, -1, id + ": the burst ends")
		assert_true(v.aura.lit, id + ": the aura stays while the Surge is ready")
		c.energy = 0.0  # spent on the Surge
		v.refresh()
		assert_false(v.aura.lit, id + ": spent: the aura goes")
		v.free()


func test_arriving_powered_up_glows_without_a_burst() -> void:
	var sim := MatchFactory.training("sno")
	sim.creatures[0].energy = CreatureSim.MAX_ENERGY
	var v := CreatureView.new()
	v.setup(sim.creatures[0])
	assert_true(v.aura.lit, "already full: lit")
	assert_eq(v.aura.burst_t, -1, "but no burst (that's for filling it in front of you)")
	v.free()


func test_no_aura_once_knocked_out() -> void:
	var v := _view("cairn")
	v.c.energy = CreatureSim.MAX_ENERGY
	v.refresh()
	v.c.state = CreatureSim.State.KO
	v.refresh()
	assert_false(v.aura.lit, "knocked out: no aura")
	v.free()


func test_stoneskin_keeps_its_stone_rim_over_the_aura() -> void:
	var v := _view("craglash")
	v.c.energy = CreatureSim.MAX_ENERGY
	v.c.shield = 10.0
	v.refresh()
	var rc: Color = v.mat.get_shader_parameter("rim_color")
	assert_true(rc.is_equal_approx(CreatureView.RIM_STONE), "the shield's rim shows while it holds")
	v.free()


func test_your_side_and_theirs_get_different_sounds() -> void:
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = "user://test_settings_surge.cfg"
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	g._start_match(1)  # you vs the CPU
	assert_true(g.is_local_team(g.sim.creatures[0].team), "the player's side is yours")
	assert_false(g.is_local_team(g.sim.creatures[1].team), "the CPU's is the other side")
	var data = JSON.parse_string(FileAccess.get_file_as_string(AudioView.DATA_PATH))
	for n in ["surge_ready_ally", "surge_ready_foe"]:
		assert_true((data["sounds"] as Dictionary).has(n), n + " is listed")
		assert_true(ResourceLoader.exists(String(data["sounds"][n]["file"])), n + " has its file")
	assert_true(String(data["sounds"]["surge_ready_ally"]["file"]) != String(data["sounds"]["surge_ready_foe"]["file"]),
		"two different sounds")
	g.free()
