extends TestCase
## Which HUD panels show: your own side's in the modes with several fighters a side,
## both in a 1v1, everyone's when nobody at the screen is playing (a replay).

const SIX := [["cairn", "culvert", "craglash"], ["culvert", "cairn", "barkley"]]


func _hud_team(per_side: int, tags: Array, focus := 0) -> Hud:
	var t := TeamSim.new(SIX, per_side)
	var h := Hud.new()
	h.sim = t.sim
	h.team = t
	h.focus = focus
	h.resize_slots(t.sim.creatures.size())
	for i in t.sim.creatures.size():
		h.tags[i] = tags[i] if i < tags.size() else "CPU"
	return h


func _flat(a: Array) -> Array:
	var out := []
	for x in a:
		out.append_array(x)
	return out


func test_team_battle_shows_only_your_side() -> void:
	for n in [2, 3, 4]:
		if n == 4:
			continue  # SIX has three a side; 4v4 is the same code path
		var h := _hud_team(n, ["P1"])
		var plan := h.panel_plan()
		assert_eq(int(plan["panel"][0]), 0, "%dv%d: your panel:" % [n, n])
		assert_eq(int(plan["panel"][1]), -1, "no enemy panel")
		assert_eq(plan["cards"][0].size(), n - 1, "your teammates are cards")
		assert_eq(plan["cards"][1].size(), 0, "no enemy cards")
		h.free()


func test_two_locals_on_different_sides_each_keep_a_panel() -> void:
	var h := _hud_team(2, [])
	var other := -1
	for i in h.sim.creatures.size():
		if h.sim.creatures[i].team == 1:
			other = i
			break
	h.tags[0] = "P1"
	h.tags[other] = "P2"
	var plan := h.panel_plan()
	assert_eq(int(plan["panel"][0]), 0, "player one:")
	assert_eq(int(plan["panel"][1]), other, "player two:")
	assert_eq(plan["cards"][0].size(), 1, "and a card for each side's other fighter")
	assert_eq(plan["cards"][1].size(), 1)
	h.free()


func test_two_locals_on_one_side_second_is_a_card() -> void:
	var h := _hud_team(2, ["P1", "P2"])
	var plan := h.panel_plan()
	assert_eq(int(plan["panel"][0]), 0)
	assert_true(plan["cards"][0].has(1), "player two is a card")
	assert_eq(int(plan["panel"][1]), -1, "enemy hidden")
	assert_eq(plan["cards"][1].size(), 0)
	h.free()


func test_spectators_and_replays_see_both_sides() -> void:
	var h := _hud_team(2, ["WATCHING", "WATCHING", "WATCHING", "WATCHING"])
	var plan := h.panel_plan()
	assert_eq(int(plan["panel"][0]), 0, "the focus's panel")
	assert_eq(_flat(plan["cards"]).size(), 3, "everyone else a card, both sides")
	h.free()


func test_brawl_shows_locals_only() -> void:
	var b := BrawlSim.new(["cairn", "culvert", "craglash", "barkley"], {}, {}, 3)
	var h := Hud.new()
	h.sim = b.sim
	h.brawl = b
	h.resize_slots(4)
	h.tags = ["P1", "CPU", "P2", "CPU"]
	var plan := h.panel_plan()
	assert_eq(int(plan["panel"][0]), 0, "player one")
	assert_eq(int(plan["panel"][1]), 2, "player two keeps a panel")
	assert_eq(_flat(plan["cards"]).size(), 0, "CPU foes are not shown")
	h.tags = ["P1", "P2", "CPU", "CPU"]
	plan = h.panel_plan()
	assert_eq(int(plan["panel"][0]), 0)
	assert_eq(plan["cards"][0], [1], "a second local on the same column is a card")
	assert_eq(int(plan["panel"][1]), -1)
	h.free()


func test_duel_hides_the_enemy_side_and_one_v_one_shows_both() -> void:
	var d := DuelSim.new([["cairn", "culvert"], ["culvert", "cairn"]])
	var h := Hud.new()
	h.sim = d.sim
	h.duel = d
	h.tags = ["P1", "CPU"]
	var plan := h.panel_plan()
	assert_eq(plan["panel"], [0, -1], "duel: yours only")
	h.tags = ["REPLAY", "REPLAY"]
	assert_eq(h.panel_plan()["panel"], [0, 1], "replay: both")
	h.duel = null
	h.tags = ["P1", "CPU"]
	assert_eq(h.panel_plan()["panel"], [0, 1], "a plain 1v1 keeps both panels")
	h.free()
