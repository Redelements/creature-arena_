extends TestCase
## Directional art: every fighter has up and down sheets, and the view follows facing.

func _view(id: String) -> CreatureView:
	var sim := MatchFactory.training(id)
	var v := CreatureView.new()
	v.setup(sim.creatures[0])
	return v


func test_every_fighter_has_up_and_down_sheets_with_the_side_rows() -> void:
	for id in MatchFactory.FIGHTERS:
		var sp: Dictionary = MatchFactory.load_def(id)["sprite"]
		var views: Dictionary = sp.get("views", {})
		for name in ["up", "down"]:
			assert_true(views.has(name), "%s needs a %s view" % [id, name])
			var v: Dictionary = views.get(name, {})
			var tex: Texture2D = load(String(v["path"]))
			var fr = v.get("frame", sp["frame"])
			var h := float(fr[1]) if fr is Array else float(fr)
			var rows := 0
			for a in sp["anims"]:
				if not (a in sp.get("side_only", [])):
					rows = maxi(rows, int(sp["anims"][a][0]) + 1)
			assert_true(tex.get_height() >= rows * h, "%s %s sheet has every row" % [id, name])


func test_facing_picks_the_view() -> void:
	for id in MatchFactory.FIGHTERS:
		var v := _view(id)
		var c := v.c
		c.facing = Vector2.DOWN
		v.refresh()
		assert_eq(v.view, "down", "%s facing down:" % id)
		c.facing = Vector2.UP
		v.refresh()
		assert_eq(v.view, "up", "%s facing up:" % id)
		c.facing = Vector2(1, 1).normalized()
		v.refresh()
		assert_eq(v.view, "side", "%s on a diagonal stays side-on:" % id)
		c.facing = Vector2.LEFT
		v.refresh()
		assert_eq(v.view, "side", "%s facing left:" % id)
		assert_true(v.sprite.flip_h, "%s mirrored to face left" % id)
		v.free()


func test_side_only_animations_use_the_side_sheet() -> void:
	var v := _view("craglash")
	var c := v.c
	c.facing = Vector2.DOWN
	c.state = CreatureSim.State.KO
	v.refresh()
	assert_eq(v.view, "down")
	assert_eq(v.sprite.texture.resource_path, String(c.def["sprite"]["path"]), "a knockout falls over side-on:")
	c.state = CreatureSim.State.IDLE
	v.refresh()
	assert_true(v.sprite.texture.resource_path.ends_with("_down.png"), "idle facing down uses the front sheet")
	v.free()


func test_attacking_down_the_screen_never_draws_over_the_fighter_in_front() -> void:
	# The one further down the screen is nearer the camera: drawn in front even while the
	# one behind punches down at them (y-sorting by feet, nothing on top).
	var v := _view("craglash")
	var c := v.c
	c.facing = Vector2.DOWN
	c.state = CreatureSim.State.ATTACK
	c.move_id = "light_1"
	v.refresh()
	assert_eq(v.z_index, 0, "a downward punch stays in depth order:")
	v.free()


func test_idle_alt_plays_once_after_standing_still_and_resets_on_movement() -> void:
	var v := _view("crease")
	var c := v.c
	assert_true(v._layout_has("idle_alt"), "crease has an idle_alt row")
	var after := int(v.layout.get("idle_alt_after", CreatureView.IDLE_ALT_AFTER))
	var ticks := int(v.layout.get("idle_ticks", 10)) * int(v._anim("idle_alt")[2])
	c.state = CreatureSim.State.IDLE
	v._still = 0
	v._alt_t = -1
	for i in range(after):
		v.refresh()
	assert_eq(v._pick()[0], "idle", "still idling just before the wait is up:")
	v.refresh()
	assert_eq(v._pick()[0], "idle_alt", "the fidget starts after the wait:")
	assert_eq(int(v._pick()[1]), 0, "from its first frame:")
	for i in range(ticks - 1):
		v.refresh()
	assert_eq(v._pick()[0], "idle_alt", "it plays to its last tick:")
	v.refresh()
	assert_eq(v._pick()[0], "idle", "then back to the idle:")
	for i in range(after):
		v.refresh()
	assert_eq(v._pick()[0], "idle", "and the count restarts:")
	v.refresh()
	assert_eq(v._pick()[0], "idle_alt", "so it plays again after another wait:")
	c.state = CreatureSim.State.MOVE
	v.refresh()
	assert_eq(v._pick()[0], "run", "moving interrupts it:")
	c.state = CreatureSim.State.IDLE
	for i in range(after):
		v.refresh()
	assert_eq(v._pick()[0], "idle", "and the wait starts over:")
	v.free()


func test_fighter_without_idle_alt_never_fidgets() -> void:
	var v := _view("cairn")
	v.c.state = CreatureSim.State.IDLE
	if v._layout_has("idle_alt"):
		v.free()
		return
	for i in range(CreatureView.IDLE_ALT_AFTER * 3):
		v.refresh()
	assert_eq(v._pick()[0], "idle", "no row, no fidget:")
	v.free()
