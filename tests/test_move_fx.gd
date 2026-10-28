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
	for want in ["slash_claws", "slash_white", "hit_star_cyan", "impact_burst", "boom_star", "dust_burst",
			"water_fountain", "ice_nova", "spark_fan", "venom_crackle"]:
		assert_true(man["effects"].has(want), "cut: " + want)
	assert_false(man["effects"].has("fire_burst"), "no fighter breathes fire: the fire burst is gone")
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
		assert_eq(fx.scale, float(e.get("scale", 1.0)), "%s: scale as cut" % name)
	var star: MoveFx = load(DIR + "hit_star_cyan.tres")
	assert_lt(star.scale, 0.75, "the light-hit star is drawn small")


func test_frame_at_follows_the_ticks_and_loops_only_when_told() -> void:
	var fx: MoveFx = load(DIR + "slash_claws.tres")
	assert_eq(fx.frame_at(0.0), 0)
	assert_eq(fx.frame_at(fx.ticks_per_frame - 0.5), 0, "the first frame holds for its ticks")
	assert_eq(fx.frame_at(fx.ticks_per_frame), 1)
	assert_eq(fx.frame_at(1000.0), fx.frame_count() - 1, "a one-shot holds its last frame")
	var aura: MoveFx = fx.duplicate()  # no looping cut is wired today; a looped copy of the slash
	aura.loop = true
	aura.loop_ticks = 90
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
	assert_true(impact, "the hit it landed played the light-hit star (the second entry of the list)")
	assert_true(str(mv["fx"].get("move_fx", "")).contains("hit_star_cyan.tres"), "a light hit plays the small star, not the loud burst")
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
	for i in maxi(f.life(), (load(DIR + "hit_star_cyan.tres") as MoveFx).life()):
		fx.move_fx.advance(1.0)
	assert_eq(fx.move_fx.playing(), 0, "and they run out")
	fx.free()


func test_a_world_space_effect_stays_where_it_spawned() -> void:
	var sim := MatchFactory.versus("barkley", "dummy")
	var fx := FxView.new()
	fx.sim = sim
	fx.unseen = [false, false]
	var c: CreatureSim = sim.creatures[0]
	var mv: Dictionary = c.def["moves"]["skill_2"]
	var burst := MoveFx.from_entry(mv["fx"].get("move_fx"))
	assert_true(burst != null and burst.frames == (load(DIR + "boom_star.tres") as MoveFx).frames,
		"Pinecone Bomb names the grey star burst, not fire")
	assert_false(burst.follow, "a burst stays put")
	assert_lt(burst.scale, 0.75, "drawn at 0.7")
	var seen := false
	for i in 240:
		sim.step(PackedInt32Array([SimDefs.IN_SKILL2 if i == 0 else 0, 0]))
		for e in sim.events:
			fx.spawn(e)
			if e["type"] == "burst":
				seen = true
				assert_eq(fx.move_fx.playing(), 1, "the star plays on the burst")
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


## Every creature file's `fx.move_fx` entries, as [fighter id, move slot, move, entry].
func _wired() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://data/creatures/")
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var def: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures/" + f))
		for slot in def.get("moves", {}):
			var mv: Dictionary = def["moves"][slot]
			var v = mv.get("fx", {}).get("move_fx")
			if v == null:
				continue
			for e in (v if v is Array else [v]):
				out.append([String(def.get("id", f)), String(slot), mv, e])
	return out


func test_every_wired_effect_resolves_and_its_hook_can_fire() -> void:
	var wired := _wired()
	var fighters := {}
	for w in wired:
		fighters[w[0]] = true
	assert_gt(fighters.size(), 10, "every fighter (the ten and Cairn) has hand-drawn effects")
	for w in wired:
		var who := "%s %s" % [w[0], w[1]]
		var mv: Dictionary = w[2]
		var f := MoveFx.from_entry(w[3])
		assert_true(f != null, who + ": the entry names a built MoveFx")
		if f == null:
			continue
		assert_gt(f.frame_count(), 0, who + ": with frames")
		var strikes: bool = int(mv.get("active", 0)) > 0 or mv.has("hits")
		var shot: Dictionary = mv.get("projectile", {})
		match f.on:
			"strike":
				assert_true(strikes, who + ": a strike effect on a move with a hitbox")
			"hit":
				# a shot's hits are its move's hits too (FxView passes them on while the
				# thrower is still in the move: Knife Flurry's fire pops)
				assert_true(strikes or not shot.is_empty(), who + ": a hit effect on a move that can hit")
			"projectile", "projectile_end":
				assert_false(shot.is_empty(), who + ": a %s effect on a move that throws" % f.on)
			"burst":
				assert_true(bool(shot.get("lob", false)), who + ": a burst effect on a lob")
			"tick":
				var length := int(mv.get("length", int(mv.get("startup", 0)) + int(mv.get("active", 0))
					+ int(mv.get("recovery", 0))))
				assert_true(f.at > 0 and f.at < length, who + ": its tick %d inside the move (%d)" % [f.at, length])
		if w[1].begins_with("light_"):
			assert_true(f.scale <= 0.7, who + ": a light's effect is small (scale %.2f)" % f.scale)
			assert_true(f.ticks_per_frame <= 2, who + ": and quick (%d ticks a frame)" % f.ticks_per_frame)


func test_an_entry_overrides_the_resource_and_shares_its_frames() -> void:
	var base: MoveFx = load(DIR + "dust_burst.tres")
	var f := MoveFx.from_entry({"path": DIR + "dust_burst.tres", "on": "tick", "at": 9, "scale": 1.4,
		"offset": [3, -21], "follow": true, "flip_with_facing": true, "ticks_per_frame": 2})
	assert_eq(f.on, "tick")
	assert_eq(f.at, 9)
	assert_near(f.scale, 1.4)
	assert_eq(f.offset, Vector2(3, -21))
	assert_true(f.follow and f.flip_with_facing)
	assert_eq(f.ticks_per_frame, 2)
	assert_true(f.frames == base.frames, "the frames are shared, not copied")
	assert_eq(base.on, "strike", "the resource itself is untouched")
	assert_near(base.scale, 1.0)
	assert_true(MoveFx.from_entry(DIR + "dust_burst.tres") == base, "a plain path is the resource")
	assert_true(MoveFx.from_entry({"path": DIR + "nope.tres"}) == null, "a missing path is null")


func test_a_storm_lob_plays_its_burst_effects_where_it_lands() -> void:
	var sim := MatchFactory.versus("crease", "dummy")
	var fx := FxView.new()
	fx.sim = sim
	fx.unseen = [false, false]
	var c: CreatureSim = sim.creatures[0]
	c.move_id = "surge"
	var at := c.pos + Vector2(60, 0)
	fx.move_fx.on_shot(c, c.pos)
	c.move_id = ""
	fx.spawn({"type": "storm", "pos": at, "power": 40.0, "who": c.id, "ticks": 120})
	assert_eq(fx.move_fx.playing(), 2, "Thousand Cranes lands: smoke and a ring")
	for s in fx.move_fx.slots():
		assert_near((s[1] as Vector2).x, at.x + (s[0] as MoveFx).offset.x, 0.6, "where the cranes landed")
	fx.free()
