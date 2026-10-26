extends TestCase
## Flipbook hit effects (FlipbookView, data/vfx.json): every strip the data names is there and
## the size the data says, every move key names a real fighter's move, a listed move's hit
## plays its effect (and an unlisted one doesn't), the pool never grows, and the effect runs
## out on FxView's clock.


func _data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FlipbookView.PATH))


func test_every_strip_matches_its_data() -> void:
	var effects: Dictionary = _data()["effects"]
	assert_gt(effects.size(), 0, "effects listed")
	for name in effects:
		var e: Dictionary = effects[name]
		var tex: Texture2D = load(FlipbookView.DIR + String(name) + ".png")
		assert_true(tex != null, "strip for " + String(name))
		if tex == null:
			continue
		assert_eq(tex.get_width(), int(e["frames"]) * int(e["size"][0]), String(name) + " width = frames x frame width")
		assert_eq(tex.get_height(), int(e["size"][1]), String(name) + " height")


func test_every_move_key_names_a_real_move() -> void:
	var d := _data()
	for key in d["moves"]:
		var parts := String(key).split("/")
		assert_eq(parts.size(), 2, "key is <fighter>/<slot>: " + String(key))
		var def: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MatchFactory.CREATURE_DIR + parts[0] + ".json"))
		assert_true(def.get("moves", {}).has(parts[1]), String(key) + " is a move")
		assert_true(d["effects"].has(String(d["moves"][key]["effect"])), String(key) + "'s effect exists")


## Mashes light for fighter 0 next to fighter 1 until a hit lands; spawns its events.
func _first_hit(a: String, b: String) -> FxView:
	var sim := MatchFactory.versus(a, b)
	var fx := FxView.new()
	fx.sim = sim
	fx.unseen = [false, false]
	sim.creatures[1].pos = sim.creatures[0].pos + Vector2(24, 0)
	sim.creatures[0].facing = Vector2.RIGHT
	for i in 120:
		sim.step(PackedInt32Array([SimDefs.IN_LIGHT if i % 2 == 0 else 0, 0]))
		var hit := false
		for e in sim.events:
			if e["type"] == "hit":
				fx.spawn(e)
				hit = true
		if hit:
			break
	return fx


func test_a_listed_move_plays_its_flipbook() -> void:
	var fx := _first_hit("digby", "dummy")
	assert_eq(fx.flip.playing(), 1, "Digby's Claw Swipe plays slash_claws")
	for i in 60:
		fx.advance()
	assert_eq(fx.flip.playing(), 0, "and it runs out")
	fx.free()


func test_an_unlisted_move_plays_none() -> void:
	var fx := _first_hit("cairn", "dummy")
	assert_eq(fx.flip.playing(), 0, "Cairn's Jab has no flipbook")
	fx.free()


func test_the_pool_is_capped() -> void:
	var sim := MatchFactory.versus("digby", "dummy")
	var a: CreatureSim = sim.creatures[0]
	a.state = CreatureSim.State.ATTACK
	a.move_id = "light_1"
	var fb := FlipbookView.new()
	for i in FlipbookView.CAP * 3:
		assert_true(fb.hit(a, Vector2(i, 0)), "replaces the burst")
	assert_eq(fb.playing(), FlipbookView.CAP, "no more than CAP at once")
	fb.free()
