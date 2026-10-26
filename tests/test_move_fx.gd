extends TestCase
## Hand-drawn move effects (MoveFx resources, MoveFxView under FxView): every resource the
## cut made loads with its frames, a move's `fx.move_fx` line plays it on the tick the sim's
## hitbox goes live (the strike from the move's own `startup`), mirrored when the attacker
## faces left, riding with the fighter when it follows and staying put when it doesn't,
## stepping its frame on FxView's clock (a freeze holds it), and a lob's burst plays its
## effect where the lob landed.

const DIR := "res://assets/vfx/"


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR + "manifest.json"))


func test_every_cut_effect_has_its_resources() -> void:
	var man := _manifest()
	assert_true(man["effects"].has("slash_claws") and man["effects"].has("impact_burst")
		and man["effects"].has("fire_burst") and man["effects"].has("aura_buff"), "a slash, a hit, a fire, an aura")
	for name in man["effects"]:
		var e: Dictionary = man["effects"][name]
		var fx = load(DIR + String(name) + ".tres")
		assert_true(fx is MoveFx, "%s.tres is a MoveFx" % name)
		if not fx is MoveFx:
			continue
		assert_eq(fx.frame_count(), int(e["frames"]), "%s: frames as cut" % name)
		assert_eq(fx.ppu, 2, "%s: 2x art" % name)
		var tex: Texture2D = load(DIR + String(name) + ".png")
		assert_eq(tex.get_width(), int(e["frames"]) * int(e["size"]), "%s: the strip is frames x 96" % name)
		assert_eq(fx.on, String(e["on"]), "%s: spawns on %s" % [name, e["on"]])
		assert_eq(fx.life(), int(e["frames"]) * fx.ticks_per_frame if not fx.loop else fx.loop_ticks, "%s: life" % name)


func test_frame_at_follows_the_ticks_and_loops_only_when_told() -> void:
	var fx: MoveFx = load(DIR + "slash_claws.tres")
	assert_eq(fx.frame_at(0.0), 0)
	assert_eq(fx.frame_at(fx.ticks_per_frame - 0.5), 0, "the first frame holds for its ticks")
	assert_eq(fx.frame_at(fx.ticks_per_frame), 1)
	assert_eq(fx.frame_at(1000.0), fx.frame_count() - 1, "a one-shot holds its last frame")
	var aura: MoveFx = load(DIR + "aura_buff.tres")
	assert_true(aura.loop and aura.follow, "the aura loops and rides with its fighter")
	assert_eq(aura.frame_at(aura.ticks_per_frame * aura.frame_count()), 0, "a loop wraps")


## A sim with `a` next to a dummy facing `dir`, and an FxView over it.
func _setup(a: String, dir: Vector2) -> Array:
	var sim := MatchFactory.versus(a, "dummy")
	var fx := FxView.new()
	fx.sim = sim
	fx.unseen = [false, false]
	sim.creatures[1].pos = sim.creatures[0].pos + dir * 24.0
	sim.creatures[0].facing = dir
	return [sim, fx]


## The playing slot of the effect spawned `on` (the hit's impact and the strike's slash can
## share a tick), or [].
func _slot(fx: FxView, on: String) -> Array:
	for s in fx.move_fx.slots():
		if (s[0] as MoveFx).on == on:
			return s
	return []


func _step(sim: MatchSim, fx: FxView, bits: int) -> void:
	sim.step(PackedInt32Array([bits, 0]))
	for e in sim.events:
		fx.spawn(e)
	fx.advance()


func test_the_slash_spawns_on_the_strike_tick_from_the_moves_own_data() -> void:
	var pair := _setup("digby", Vector2.RIGHT)
	var sim: MatchSim = pair[0]
	var fx: FxView = pair[1]
	var c: CreatureSim = sim.creatures[0]
	var mv: Dictionary = c.def["moves"]["light_1"]
	assert_true(str(mv["fx"].get("move_fx", "")).contains("slash_claws.tres"), "Claw Swipe names the slash in one line")
	var spawned_at := -1
	var slot: Array = []
	var impact := false
	for i in 40:
		_step(sim, fx, SimDefs.IN_LIGHT if i == 0 else 0)
		if not _slot(fx, "strike").is_empty() and spawned_at < 0:
			spawned_at = c.state_t
			slot = _slot(fx, "strike")
			assert_eq(c.move_id, "light_1", "during the Claw Swipe")
			assert_eq(c.active_seg(), 0, "the tick the hitbox went live")
		for s in fx.move_fx.slots():
			if (s[0] as MoveFx).on == "hit":
				impact = true
	assert_eq(spawned_at, int(mv["startup"]) + 1, "spawned on startup + 1, the sim's first active tick")
	assert_true(impact, "the hit it landed played the impact burst (the second entry of the list)")
	assert_false(bool(slot[2]), "facing right: not mirrored")
	var f: MoveFx = slot[0]
	assert_true(f.follow, "the slash rides with Digby")
	var at: Vector2 = slot[1]
	assert_near(at.x, c.hit_center(0).x + f.offset.x, 0.6, "ahead of him by the offset, at the strike's centre")
	fx.free()


func test_facing_left_mirrors_and_a_follower_moves_with_its_fighter() -> void:
	var pair := _setup("digby", Vector2.LEFT)
	var sim: MatchSim = pair[0]
	var fx: FxView = pair[1]
	var c: CreatureSim = sim.creatures[0]
	for i in 40:
		_step(sim, fx, SimDefs.IN_LIGHT if i == 0 else 0)
		if not _slot(fx, "strike").is_empty():
			break
	var slot := _slot(fx, "strike")
	assert_false(slot.is_empty(), "the slash plays")
	assert_true(bool(slot[2]), "facing left: mirrored")
	var before: Vector2 = slot[1]
	assert_lt(before.x, c.pos.x, "and on his left")
	c.pos += Vector2(0, 10)
	fx.move_fx.advance(1.0)
	var after: Vector2 = _slot(fx, "strike")[1]
	assert_near(after.y - before.y, 10.0, 0.6, "a follower moves with its fighter")
	fx.free()


func test_a_freeze_holds_the_frame_and_the_effect_runs_out_on_the_clock() -> void:
	var pair := _setup("digby", Vector2.RIGHT)
	var sim: MatchSim = pair[0]
	var fx: FxView = pair[1]
	for i in 40:
		_step(sim, fx, SimDefs.IN_LIGHT if i == 0 else 0)
		if not _slot(fx, "strike").is_empty():
			break
	var f: MoveFx = _slot(fx, "strike")[0]
	assert_eq(int(_slot(fx, "strike")[3]), 0, "the first frame on spawn")
	fx.move_fx.advance(0.0)
	fx.move_fx.advance(0.0)
	assert_eq(int(_slot(fx, "strike")[3]), 0, "a freeze (time scale 0) holds it")
	for i in f.ticks_per_frame:
		fx.move_fx.advance(1.0)
	assert_eq(int(_slot(fx, "strike")[3]), 1, "one frame per ticks_per_frame ticks")
	for i in maxi(f.life(), (load(DIR + "impact_burst.tres") as MoveFx).life()):
		fx.move_fx.advance(1.0)
	assert_eq(fx.move_fx.playing(), 0, "and they run out")
	fx.free()


func test_a_world_space_effect_stays_where_it_spawned() -> void:
	var sim := MatchFactory.versus("barkley", "dummy")
	var fx := FxView.new()
	fx.sim = sim
	fx.unseen = [false, false]
	var c: CreatureSim = sim.creatures[0]
	var burst: MoveFx = load(DIR + "fire_burst.tres")
	assert_false(burst.follow, "a burst stays put")
	var mv: Dictionary = c.def["moves"]["skill_2"]
	assert_true(String(mv["fx"].get("move_fx", "")).ends_with("fire_burst.tres"), "Pinecone Bomb names the fire")
	var seen := false
	for i in 240:
		sim.step(PackedInt32Array([SimDefs.IN_SKILL2 if i == 0 else 0, 0]))
		for e in sim.events:
			fx.spawn(e)
			if e["type"] == "burst":
				seen = true
				assert_eq(fx.move_fx.playing(), 1, "the fire plays on the burst")
				var at: Vector2 = fx.move_fx.slots()[0][1]
				assert_near(at.x, Vector2(e["pos"]).x + burst.offset.x, 0.6, "where the pinecone landed")
				c.pos += Vector2(30, 0)
				fx.move_fx.advance(1.0)
				assert_near(fx.move_fx.slots()[0][1].x, at.x, 0.6, "and stays when Barkley moves")
		fx.advance()
		if seen:
			break
	assert_true(seen, "the pinecone burst")
	fx.free()


func test_an_unwired_move_plays_nothing() -> void:
	var pair := _setup("cairn", Vector2.RIGHT)
	var sim: MatchSim = pair[0]
	var fx: FxView = pair[1]
	for i in 30:
		_step(sim, fx, SimDefs.IN_LIGHT if i == 0 else 0)
	assert_eq(fx.move_fx.playing(), 0, "Cairn's Jab has no move_fx")
	fx.free()
