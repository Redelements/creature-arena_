extends TestCase
## Touch fight controls (TouchPad, PlayerInput's Device.TOUCH, the overlay's redraw key),
## driven by synthetic InputEventScreenTouch / InputEventScreenDrag: each button's bits,
## the stick's 64 steps against SimDefs.move_from_bits, drag-to-aim firing on release with
## IN_AIM and cancelling when dragged back, two fingers at once, a lost touch letting go of
## everything, the wider touch aim assist, and the mirror for left hands.

const SCREEN := Vector2(480, 270)


func _pad() -> TouchPad:
	var p := TouchPad.new()
	p.layout(SCREEN)
	return p


func _down(p: TouchPad, i: int, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = true
	p.feed(e)


func _up(p: TouchPad, i: int, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = false
	p.feed(e)


func _drag(p: TouchPad, i: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = at
	p.feed(e)


## Bits over `n` ticks, ORed.
func _ticks(p: TouchPad, n: int) -> int:
	var out := 0
	for i in n:
		out |= p.bits()
	return out


func test_each_button_sends_its_bit_once_per_tap() -> void:
	var p := _pad()
	for b in ["light", "heavy", "skill_1", "skill_2", "surge", "dodge", "guard"]:
		var bit := int(TouchPad.BITS[b])
		_down(p, 1, p.center(b))
		_up(p, 1, p.center(b))  # down and up between two ticks: still one tick of it
		var first := p.bits()
		assert_true(first & bit, "%s: its bit on the tick after the tap (%d)" % [b, first])
		assert_eq(first & SimDefs.IN_ALL & ~bit, 0, "%s: no other button" % b)
		assert_eq(p.bits() & bit, 0, "%s: only one tick" % b)
		_ticks(p, 12)  # the aim hold runs out


func test_tag_shows_only_in_duel() -> void:
	var p := _pad()
	assert_false(p.buttons().has("tag"), "no Tag outside a Duel")
	p.show_tag = true
	p.layout(SCREEN)
	assert_true(p.buttons().has("tag"), "a Tag button in a Duel")
	_down(p, 1, p.center("tag"))
	assert_true(p.bits() & SimDefs.IN_TAG, "Tag presses IN_TAG")


func test_light_fires_on_the_touch_and_heavy_on_the_release() -> void:
	var p := _pad()
	_down(p, 1, p.center("light"))
	assert_true(p.bits() & SimDefs.IN_LIGHT, "Light: on the touch itself")
	_up(p, 1, p.center("light"))
	_down(p, 2, p.center("heavy"))
	assert_eq(_ticks(p, 3) & SimDefs.IN_HEAVY, 0, "Heavy waits: a tap or a drag?")
	_up(p, 2, p.center("heavy"))
	var b := p.bits()
	assert_true(b & SimDefs.IN_HEAVY, "fires on the release")
	assert_false(b & SimDefs.IN_AIM, "a tap: no exact aim (assist aims it)")


func test_guard_holds_while_the_finger_is_down() -> void:
	var p := _pad()
	_down(p, 1, p.center("guard"))
	for i in 30:
		assert_true(p.bits() & SimDefs.IN_GUARD, "guarding, tick %d" % i)
	_up(p, 1, p.center("guard"))
	assert_eq(p.bits() & SimDefs.IN_GUARD, 0, "let go")


func test_quick_retap_leaves_a_gap_so_the_sim_sees_two_presses() -> void:
	var p := _pad()
	_down(p, 1, p.center("light"))
	_up(p, 1, p.center("light"))
	assert_true(p.bits() & SimDefs.IN_LIGHT, "first press")
	_down(p, 1, p.center("light"))
	_up(p, 1, p.center("light"))
	assert_eq(p.bits() & SimDefs.IN_LIGHT, 0, "a gap tick (presses are edges)")
	assert_true(p.bits() & SimDefs.IN_LIGHT, "then the second press")


func test_stick_has_the_64_steps_of_move_from_bits() -> void:
	var p := _pad()
	var dirs := SimDefs.aim_dirs()
	var start := p.rest_spot() + Vector2(10, -20)
	for i in SimDefs.AIM_STEPS:
		_down(p, 0, start)
		assert_eq(p.stick_origin, start, "the stick floats to where the thumb lands")
		_drag(p, 0, start + dirs[i] * 25.0)
		var b := p.bits()
		assert_true(b & SimDefs.IN_MOVE, "step %d: a 360 move" % i)
		assert_true(SimDefs.move_from_bits(b).is_equal_approx(dirs[i]), "step %d: %s" % [i, SimDefs.move_from_bits(b)])
		_up(p, 0, start + dirs[i] * 25.0)
		assert_eq(p.bits(), 0, "step %d: let go, standing" % i)
		assert_eq(p.stick_knob, p.rest_spot(), "back at its rest spot")


func test_stick_dead_zone_and_reach_clamp() -> void:
	var p := _pad()
	var at := p.rest_spot()
	_down(p, 0, at)
	_drag(p, 0, at + Vector2(3, 0))
	assert_eq(p.bits(), 0, "inside the dead zone: no walk")
	_drag(p, 0, at + Vector2(200, 0))
	assert_near((p.stick_knob - at).length(), p.stick_radius(), 0.01, "the knob stops at its travel")
	assert_true(SimDefs.move_from_bits(p.bits()).x > 0.99, "walks right")


func test_stick_only_in_the_left_part_of_the_screen() -> void:
	var p := _pad()
	_down(p, 0, Vector2(SCREEN.x * 0.6, 200))
	assert_eq(p.stick_finger, -1, "the middle of the screen is not the stick")
	_down(p, 1, Vector2(40, 20))
	assert_eq(p.stick_finger, -1, "nor the top, under the fighter panels")
	_down(p, 2, Vector2(60, 200))
	assert_eq(p.stick_finger, 2, "the bottom left is")


func test_drag_off_aims_and_fires_on_release_with_exact_aim() -> void:
	var p := _pad()
	var c := p.center("skill_1")
	_down(p, 1, c)
	_drag(p, 1, c + Vector2(0, -60))  # up
	assert_eq(p.bits() & SimDefs.IN_ALL, 0, "aiming: nothing fires yet")
	var aim := p.aiming()
	assert_eq(String(aim.get("button", "")), "skill_1", "the overlay sees the aim")
	assert_false(bool(aim["cancel"]), "not cancelling")
	_up(p, 1, c + Vector2(0, -60))
	var b := p.bits()
	assert_true(b & SimDefs.IN_SKILL1, "fires on the release")
	assert_true(b & SimDefs.IN_AIM, "with an exact aim")
	assert_true(SimDefs.aim_from_bits(b).is_equal_approx(Vector2(0, -1)), "straight up: %s" % SimDefs.aim_from_bits(b))
	for i in TouchPad.AIM_HOLD - 1:
		var k := p.bits()
		assert_true(k & SimDefs.IN_AIM and not (k & SimDefs.IN_SKILL1), "the aim held for the buffer, tick %d" % i)
	assert_eq(p.bits(), 0, "then nothing")


func test_release_in_the_cancel_zone_cancels() -> void:
	var p := _pad()
	var z := p.cancel_center()
	for b in TouchPad.DRAG_BUTTONS:
		var c := p.center(b)
		_down(p, 1, c)
		_drag(p, 1, c + Vector2(-50, -20))
		assert_false(p.aiming().is_empty(), b + ": aiming")
		assert_false(bool(p.aiming()["cancel"]), b + ": not over the zone yet")
		_drag(p, 1, z + Vector2(3, -2))
		assert_true(bool(p.aiming().get("cancel", false)), b + ": over the zone shows cancel")
		_up(p, 1, z + Vector2(3, -2))
		assert_eq(_ticks(p, 15), 0, b + ": cancelled, nothing sent")


func test_release_outside_the_zone_fires_even_back_on_the_button() -> void:
	var p := _pad()
	var c := p.center("heavy")
	_down(p, 1, c)
	_drag(p, 1, c + Vector2(-50, 0))
	_drag(p, 1, p.cancel_center())  # over the zone...
	_drag(p, 1, c + Vector2(0, 50))  # ...and out again: aiming down now
	_up(p, 1, c + Vector2(0, 50))
	var b := p.bits()
	assert_true(b & SimDefs.IN_HEAVY and b & SimDefs.IN_AIM, "fires after all")
	assert_true(SimDefs.aim_from_bits(b).y > 0.99, "down")
	_ticks(p, 12)
	_down(p, 1, c)
	_drag(p, 1, c + Vector2(50, 0))
	_drag(p, 1, c + Vector2(4, 0))  # back onto the button is not a cancel any more
	_up(p, 1, c + Vector2(4, 0))
	b = p.bits()
	assert_true(b & SimDefs.IN_HEAVY and b & SimDefs.IN_AIM, "released on the button: fires (only the zone cancels)")


func test_cancel_zone_clear_of_the_buttons_and_pause_and_mirrored() -> void:
	for left in [false, true]:
		for s in TouchPad.SIZES.size():
			for tag in [false, true]:
				var p := TouchPad.new()
				p.left_handed = left
				p.size_step = s
				p.show_tag = tag
				p.layout(SCREEN)
				var z := p.cancel_center()
				assert_true(Rect2(Vector2.ZERO, SCREEN).has_point(z), "on screen")
				assert_true((z.x > SCREEN.x * 0.5) != left, "the buttons' side (left-handed: %s)" % left)
				for b in p.buttons():
					assert_gt(z.distance_to(p.center(b)), p.cancel_radius() + p.radius(b),
						"size %d tag %s left %s: clear of %s" % [s, tag, left, b])
	var r := _pad()
	var l := TouchPad.new()
	l.left_handed = true
	l.layout(SCREEN)
	assert_near(l.cancel_center().x, SCREEN.x - r.cancel_center().x, 0.01, "mirrored")
	_down(l, 1, l.center("skill_1"))
	_drag(l, 1, l.cancel_center())
	_up(l, 1, l.cancel_center())
	assert_eq(_ticks(l, 12), 0, "left-handed: its zone cancels")


func test_cancel_zone_is_not_a_button() -> void:
	var p := _pad()
	_down(p, 1, p.cancel_center())
	assert_eq(_ticks(p, 3), 0, "touching the zone with no drag does nothing")
	assert_eq(p.fingers_down(), 0, "and takes no finger")


func test_holding_a_charge_move_still_charges_it() -> void:
	var p := _pad()
	p.charges = {"heavy": true}
	var c := p.center("heavy")
	_down(p, 1, c)
	var first := -1
	for i in TouchPad.HOLD_TICKS + 20:
		if p.bits() & SimDefs.IN_HEAVY and first < 0:
			first = i
	assert_eq(first, TouchPad.HOLD_TICKS - 1, "starts once held still for HOLD_TICKS")
	assert_true(p.bits() & SimDefs.IN_HEAVY, "and holds (charging)")
	_drag(p, 1, c + Vector2(60, 0))
	var b := p.bits()
	assert_true(b & SimDefs.IN_HEAVY and b & SimDefs.IN_AIM, "dragging off aims the charge")
	_up(p, 1, c + Vector2(60, 0))
	assert_eq(p.bits() & SimDefs.IN_HEAVY, 0, "let go: the charge goes")


func test_a_skill_that_does_not_charge_waits_for_the_release() -> void:
	var p := _pad()
	p.charges = {"heavy": true}
	_down(p, 1, p.center("skill_2"))
	assert_eq(_ticks(p, 40) & SimDefs.IN_SKILL2, 0, "no charge: held, it still waits")


func test_tap_only_fires_every_button_on_the_touch() -> void:
	var p := _pad()
	p.tap_only = true
	var c := p.center("heavy")
	_down(p, 1, c)
	assert_true(p.bits() & SimDefs.IN_HEAVY, "on the touch")
	_drag(p, 1, c + Vector2(60, 0))
	var b := p.bits()
	assert_true(b & SimDefs.IN_HEAVY, "held (a charge charges)")
	assert_false(b & SimDefs.IN_AIM, "no drag aiming in tap only")
	assert_true(p.aiming().is_empty(), "nothing to draw")


func test_two_fingers_stick_and_button_at_once() -> void:
	var p := _pad()
	var at := p.rest_spot()
	_down(p, 0, at)
	_drag(p, 0, at + Vector2(0, 25))
	_down(p, 1, p.center("light"))
	var b := p.bits()
	assert_true(b & SimDefs.IN_LIGHT, "light")
	assert_true(SimDefs.move_from_bits(b).y > 0.99, "while walking down")
	_down(p, 2, p.center("guard"))
	b = p.bits()
	assert_true(b & SimDefs.IN_GUARD and b & SimDefs.IN_MOVE, "three fingers: guard and the stick")
	assert_eq(p.fingers_down(), 3, "three down")


func test_dodge_goes_the_sticks_last_way() -> void:
	var p := _pad()
	var at := p.rest_spot()
	_down(p, 0, at)
	_drag(p, 0, at + Vector2(-25, 0))
	p.bits()
	_up(p, 0, at + Vector2(-25, 0))
	assert_eq(p.bits(), 0, "standing")
	_down(p, 1, p.center("dodge"))
	var b := p.bits()
	assert_true(b & SimDefs.IN_DODGE, "dodge")
	assert_true(SimDefs.move_from_bits(b).x < -0.99, "left, the stick's last way")
	assert_eq(p.bits() & SimDefs.IN_MOVE, 0, "and no walk after it")


func test_lost_touch_releases_everything() -> void:
	var p := _pad()
	var at := p.rest_spot()
	_down(p, 0, at)
	_drag(p, 0, at + Vector2(25, 0))
	_down(p, 1, p.center("guard"))
	_down(p, 2, p.center("skill_1"))
	_drag(p, 2, p.center("skill_1") + Vector2(0, -50))
	assert_true(p.bits() & SimDefs.IN_GUARD, "guarding")
	p.release_all()  # the app paused, focus lost
	assert_eq(_ticks(p, 15), 0, "nothing held, nothing fired")
	assert_eq(p.fingers_down(), 0, "no fingers")
	assert_eq(p.stick_knob, p.rest_spot(), "stick at rest")
	# The lifts the system sends later (if any) do nothing either.
	_up(p, 2, p.center("skill_1") + Vector2(0, -50))
	assert_eq(_ticks(p, 3), 0, "a late lift fires nothing")


func test_a_cancelled_touch_event_fires_nothing() -> void:
	var p := _pad()
	var c := p.center("surge")
	_down(p, 1, c)
	_drag(p, 1, c + Vector2(0, -50))
	var e := InputEventScreenTouch.new()
	e.index = 1
	e.position = c + Vector2(0, -50)
	e.canceled = true
	p.feed(e)
	assert_eq(_ticks(p, 12), 0, "the system took the touch: no Surge")


func test_inactive_pad_ignores_new_touches() -> void:
	var p := _pad()
	p.active = false
	_down(p, 1, p.center("light"))
	_down(p, 0, p.rest_spot())
	assert_eq(_ticks(p, 3), 0, "menus: touches don't fight")
	assert_eq(p.fingers_down(), 0, "none taken")


func test_pause_button() -> void:
	var p := _pad()
	_down(p, 3, p.center("pause"))
	assert_false(p.pause_requested, "on the lift, not the touch")
	_up(p, 3, p.center("pause"))
	assert_true(p.pause_requested, "pause asked for")
	assert_eq(p.bits(), 0, "and no fight bits")


func test_left_handed_mirrors_the_layout() -> void:
	var r := _pad()
	var l := TouchPad.new()
	l.left_handed = true
	l.layout(SCREEN)
	for b in r.buttons():
		assert_near(l.center(b).x, SCREEN.x - r.center(b).x, 0.01, b + " mirrored")
		assert_near(l.center(b).y, r.center(b).y, 0.01, b + " same height")
	_down(l, 0, Vector2(SCREEN.x - 60, 200))
	assert_eq(l.stick_finger, 0, "the stick is on the right")


func test_sizes_scale_the_buttons() -> void:
	var radii := []
	for s in TouchPad.SIZES.size():
		var p := TouchPad.new()
		p.size_step = s
		p.layout(SCREEN)
		radii.append(p.radius("light"))
		for a in p.buttons():
			for b in p.buttons():
				if a < b:
					assert_gt(p.center(a).distance_to(p.center(b)), p.radius(a) + p.radius(b) - 0.01,
						"size %d: %s and %s don't overlap" % [s, a, b])
			var c := p.center(a)
			assert_true(Rect2(Vector2.ZERO, SCREEN).has_point(c), "size %d: %s on screen" % [s, a])
	assert_true(radii[0] < radii[1] and radii[1] < radii[2], "three sizes: %s" % [radii])


# ---------------------------------------------------------------- PlayerInput, the sim

func _touch_input() -> PlayerInput:
	var pin := PlayerInput.new()
	pin.pad_device = PlayerInput.NO_PAD
	pin.touch.layout(SCREEN)
	pin.device = PlayerInput.Device.TOUCH
	return pin


func test_note_event_switches_to_touch_and_back() -> void:
	var pin := PlayerInput.new()
	var t := InputEventScreenTouch.new()
	t.pressed = true
	pin.note_event(t)
	assert_eq(pin.device, PlayerInput.Device.TOUCH, "a touch")
	assert_eq(pin.label_set(), "touch", "touch prompts")
	var m := InputEventMouseButton.new()
	m.pressed = true
	m.device = InputEvent.DEVICE_ID_EMULATION
	pin.note_event(m)
	assert_eq(pin.device, PlayerInput.Device.TOUCH, "the touch's emulated click doesn't switch")
	var k := InputEventKey.new()
	k.pressed = true
	pin.note_event(k)
	assert_eq(pin.device, PlayerInput.Device.KEYBOARD, "a key hides touch")
	pin.note_event(t)
	var j := InputEventJoypadButton.new()
	j.pressed = true
	pin.note_event(j)
	assert_eq(pin.device, PlayerInput.Device.GAMEPAD, "a pad button hides touch")
	assert_true(pin.help_text().length() > 0 and PlayerInput.label_for("touch", "heavy") == "", "touch help, no key labels")


func test_tap_uses_the_wider_touch_assist_with_the_stick_held() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var foe := sim.creatures[1]
	foe.pos = me.pos + Vector2(60, 0)
	var pin := _touch_input()
	var p := pin.touch
	# Walking 20 degrees off the foe: the stick's 12 would miss, touch's 25 catches it.
	var walk := Vector2(cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)))
	_down(p, 0, p.rest_spot())
	_drag(p, 0, p.rest_spot() + walk * 25.0)
	_down(p, 1, p.center("light"))
	var b := pin.bits(sim, 0, Vector2.ZERO)
	assert_true(b & SimDefs.IN_LIGHT, "light")
	assert_true(b & SimDefs.IN_AIM, "assisted")
	assert_true(SimDefs.aim_from_bits(b).x > 0.99, "straight at the foe: %s" % SimDefs.aim_from_bits(b))
	var stick := PlayerInput.assist(SimDefs.move_bits(walk) | SimDefs.IN_LIGHT, me, foe)
	assert_false(stick & SimDefs.IN_AIM, "the pad's stick assist would not have")


func test_drag_aim_throws_the_move_that_way_in_the_sim() -> void:
	var sim := MatchFactory.training("cairn")
	var me := sim.creatures[0]
	var pin := _touch_input()
	var p := pin.touch
	var c := p.center("skill_1")
	_down(p, 1, c)
	_drag(p, 1, c + Vector2(0, 60))  # down, away from the dummy (no assist on an exact aim)
	for i in 3:
		sim.step(PackedInt32Array([pin.bits(sim, 0, Vector2.ZERO), 0]))
	assert_true(me.state != CreatureSim.State.ATTACK, "nothing yet while aiming")
	_up(p, 1, c + Vector2(0, 60))
	sim.step(PackedInt32Array([pin.bits(sim, 0, Vector2.ZERO), 0]))
	assert_eq(me.move_id, "skill_1", "Skill 1 thrown on the release")
	assert_true(me.facing.y > 0.99, "aimed down: %s" % me.facing)


func test_player_input_reset_lets_go() -> void:
	var pin := _touch_input()
	_down(pin.touch, 1, pin.touch.center("guard"))
	pin.reset()
	assert_eq(pin.touch.fingers_down(), 0, "a new match: no finger held over")


# ---------------------------------------------------------------- the overlay

func test_overlay_redraw_key_only_changes_with_what_it_draws() -> void:
	var o := TouchOverlay.new()
	o.pad = _pad()
	o.sim = MatchFactory.training("cairn")
	o.slot = 0
	var a := o._key()
	assert_eq(o._key(), a, "nothing changed: the same key (no redraw)")
	o.sim.step(PackedInt32Array([0, 0]))
	assert_eq(o._key(), a, "a quiet tick: still the same")
	_down(o.pad, 1, o.pad.center("light"))
	assert_true(o._key() != a, "a finger down: redraw")
	var b := o._key()
	o.sim.creatures[0].cooldowns["skill_1"] = int(o.sim.creatures[0].moves()["skill_1"].get("cooldown", 60))
	assert_true(o._key() != b, "a cooldown starting: redraw")
	o.free()


# ---------------------------------------------------------------- in the game

const TEST_SETTINGS := "user://test_touch.cfg"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _game(keep := false) -> Node:
	if not keep and FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	return g


func _tick(g: Node, n: int) -> void:
	for i in n:
		g._physics_process(1.0 / 60.0)


func _game_touch(g: Node, i: int, at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = pressed
	g._note_input(e)


func test_overlay_shows_on_a_touch_in_a_fight_and_hides_on_a_key() -> void:
	var g := _game()
	g._start_match(g.mode_index("Training: Cairn"))
	_tick(g, 5)
	assert_false(g.touch_overlay.visible, "hidden until a touch")
	var pad: TouchPad = g.player_input.touch
	_game_touch(g, 1, pad.center("light"), true)
	_tick(g, 1)
	assert_true(g.touch_overlay.visible, "a touch in a fight shows it")
	assert_true(g.hud.touch, "the HUD makes room")
	_game_touch(g, 1, pad.center("light"), false)
	_game_touch(g, 2, pad.center("guard"), true)
	_tick(g, 2)
	assert_true(g.sim.creatures[0].prev_buttons & SimDefs.IN_GUARD, "the touch reaches the sim")
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_X
	g._note_input(k)
	_tick(g, 1)
	assert_false(g.touch_overlay.visible, "a key hides it")
	assert_eq(pad.fingers_down(), 0, "and lets go of the fingers (no stuck guard)")
	g.free()


func test_focus_lost_lets_go_of_everything() -> void:
	var g := _game()
	g._start_match(g.mode_index("Training: Cairn"))
	_tick(g, 5)
	var pad: TouchPad = g.player_input.touch
	_game_touch(g, 2, pad.center("guard"), true)
	_tick(g, 2)
	assert_eq(pad.fingers_down(), 1, "guarding")
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_eq(pad.fingers_down(), 0, "focus out: let go")
	_tick(g, 2)
	assert_false(g.sim.creatures[0].prev_buttons & SimDefs.IN_GUARD, "no guard held")
	g.free()


func test_touch_settings_apply_and_are_kept() -> void:
	var g := _game()
	assert_eq(g.SETTING_PAGES["touch"], ["touch_opacity", "touch_size", "touch_hand", "touch_aim"], "the Touch page")
	assert_near(g.touch_overlay.opacity, 0.7, 0.001, "70% by default")
	g._set_setting("touch_opacity", 0)
	g._set_setting("touch_size", 2)
	g._set_setting("touch_hand", 1)
	g._set_setting("touch_aim", 1)
	g._save_settings()
	assert_near(g.touch_overlay.opacity, 0.3, 0.001, "opacity applied")
	assert_true(g.player_input.touch.left_handed and g.player_input.touch.tap_only, "hand and aim applied")
	g.free()
	var again := _game(true)
	var pad: TouchPad = again.player_input.touch
	assert_eq(pad.size_step, 2, "size kept")
	assert_true(pad.left_handed, "hand kept")
	assert_true(pad.tap_only, "aim style kept")
	assert_near(again.touch_overlay.opacity, 0.3, 0.001, "opacity kept")
	again.free()


func test_pause_button_pauses() -> void:
	var g := _game()
	g._start_match(g.mode_index("Training: Cairn"))
	_tick(g, 5)
	var pad: TouchPad = g.player_input.touch
	_game_touch(g, 3, pad.center("pause"), true)
	_game_touch(g, 3, pad.center("pause"), false)
	_tick(g, 1)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(g.paused, "the overlay's Pause pauses")
	g.free()
