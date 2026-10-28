extends TestCase
## Directional art: every fighter has up and down sheets, and the view follows facing: the
## 8 sectors pick side / down_side / down / up_side / up, a fighter without the diagonal
## sheets keeps the older choice exactly, and the diagonals mirror for down-left and up-left.

func _view(id: String) -> CreatureView:
	var sim := MatchFactory.training(id)
	var v := CreatureView.new()
	v.setup(sim.creatures[0])
	return v


func test_every_fighter_has_up_and_down_sheets_with_the_side_rows() -> void:
	for id in MatchFactory.FIGHTERS:
		var sp: Dictionary = MatchFactory.load_def(id)["sprite"]
		var views: Dictionary = sp.get("views", {})
		for name in ["up", "down", "down_side", "up_side"]:
			if name.ends_with("_side") and not views.has(name):
				continue  # the diagonals are optional (side-on until the fighter's round)
			assert_true(views.has(name), "%s needs a %s view" % [id, name])
			var v: Dictionary = views.get(name, {})
			var tex: Texture2D = PackedSheet.load_sheet(String(v["path"]))
			assert_true(tex != null, "%s %s sheet loads" % [id, name])
			if tex == null:
				continue
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
		var diag := "down_side" if v._views.has("down_side") else "side"
		assert_eq(v.view, diag, "%s on a diagonal:" % id)
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
	assert_eq(PackedSheet.path_of(v.sheet()), String(c.def["sprite"]["path"]), "a knockout falls over side-on:")
	c.state = CreatureSim.State.IDLE
	v.refresh()
	assert_true(PackedSheet.path_of(v.sheet()).ends_with("_down.png"), "idle facing down uses the front sheet")
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
	# The training dummy (every fighter has an idle_alt row now, Cairn included).
	var v := CreatureView.new()
	v.setup(MatchFactory.training("cairn").creatures[1])
	assert_eq(String(v.c.def["id"]), "dummy", "the training sim's second creature is the dummy:")
	v.c.state = CreatureSim.State.IDLE
	if v._layout_has("idle_alt"):
		v.free()
		return
	for i in range(CreatureView.IDLE_ALT_AFTER * 3):
		v.refresh()
	assert_eq(v._pick()[0], "idle", "no row, no fidget:")
	v.free()


## Today's rule, before the diagonal sheets: more up/down than sideways by 0.05 picks
## up/down (when the fighter has it), anything else the side.
static func _old_pick(f: Vector2, views: Dictionary) -> String:
	if absf(f.y) > absf(f.x) + 0.05:
		var want := "down" if f.y > 0.0 else "up"
		if views.has(want):
			return want
	return "side"


func _facing(deg: float) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg)))  # y down the screen


func test_eight_sectors_pick_the_five_views() -> void:
	var all := {"side": 1, "down": 1, "up": 1, "down_side": 1, "up_side": 1}
	# The centre of each sector and 20 degrees either side, inside its 45.
	var centres := {0.0: "side", 45.0: "down_side", 90.0: "down", 135.0: "down_side", 180.0: "side",
		225.0: "up_side", 270.0: "up", 315.0: "up_side"}
	for deg in centres:
		for off in [-20.0, 0.0, 20.0]:
			assert_eq(CreatureView.pick_view(_facing(deg + off), all), centres[deg],
				"facing %d degrees:" % int(deg + off))
	# The edges, 22.5 degrees off a diagonal.
	assert_eq(CreatureView.pick_view(_facing(22.0), all), "side")
	assert_eq(CreatureView.pick_view(_facing(23.0), all), "down_side")
	assert_eq(CreatureView.pick_view(_facing(67.0), all), "down_side")
	assert_eq(CreatureView.pick_view(_facing(68.0), all), "down")
	assert_eq(CreatureView.pick_view(_facing(-68.0), all), "up")
	assert_eq(CreatureView.pick_view(_facing(-23.0), all), "up_side")
	assert_eq(CreatureView.pick_view(Vector2.ZERO, all), "side", "no facing: side-on")


func test_fighters_without_diagonal_sheets_pick_what_they_always_did() -> void:
	var three := {"side": 1, "down": 1, "up": 1}
	var side_only := {"side": 1}
	var half := {"side": 1, "down": 1, "up": 1, "down_side": 1}  # no up_side: that sector falls back
	for i in 720:
		var f := _facing(i * 0.5)
		assert_eq(CreatureView.pick_view(f, three), _old_pick(f, three), "three views at %.1f:" % (i * 0.5))
		assert_eq(CreatureView.pick_view(f, side_only), "side", "side only at %.1f:" % (i * 0.5))
		if f.y < 0.0:
			assert_eq(CreatureView.pick_view(f, half), _old_pick(f, half), "no up_side at %.1f:" % (i * 0.5))
	# And every real fighter without the diagonals, through the view itself.
	for id in MatchFactory.FIGHTERS:
		var v := _view(id)
		if v._views.has("down_side") or v._views.has("up_side"):
			v.free()
			continue
		for i in 64:
			v.c.facing = _facing(i * 360.0 / 64.0 + 0.3)
			v.refresh()
			assert_eq(v.view, _old_pick(v.c.facing, v._views), "%s at step %d:" % [id, i])
		v.free()


func test_diagonals_mirror_for_the_left() -> void:
	var v := _view("pete")
	var c := v.c
	assert_true(v._views.has("down_side") and v._views.has("up_side"), "pete has the diagonal sheets")
	var cases := [
		[Vector2(1, 1), "down_side", false], [Vector2(-1, 1), "down_side", true],
		[Vector2(1, -1), "up_side", false], [Vector2(-1, -1), "up_side", true],
	]
	for k in cases:
		c.facing = (k[0] as Vector2).normalized()
		v.refresh()
		assert_eq(v.view, k[1], "facing %s:" % k[0])
		assert_eq(v.sprite.flip_h, k[2], "facing %s mirrored:" % k[0])
		assert_true(PackedSheet.path_of(v.sheet()).ends_with("_%s.png" % k[1]), "facing %s shows its sheet" % k[0])
	# A side-only knockout still falls over side-on from a diagonal.
	c.facing = Vector2(1, 1).normalized()
	c.state = CreatureSim.State.KO
	v.refresh()
	assert_eq(PackedSheet.path_of(v.sheet()), String(c.def["sprite"]["path"]), "a knockout stays on the side sheet:")
	v.free()
