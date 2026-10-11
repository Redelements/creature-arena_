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
