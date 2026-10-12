extends TestCase
## Menus and the analog stick: one flick is one press, holding repeats at a steady pace,
## diagonals move one way, and none of it (nor the menu animations) depends on the
## frame rate.


## Presses from holding `v` for `seconds` at `fps`.
func _hold(stick: MenuStick, v: Vector2, seconds: float, fps: float) -> Array:
	var out: Array = []
	for i in roundi(seconds * fps):
		out.append_array(stick.step(v, 1.0 / fps))
	return out


func test_a_flick_is_one_press() -> void:
	var stick := MenuStick.new()
	var got: Array = []
	# The stick swings out through every value on the way (each used to count as a press).
	for x in [0.2, 0.4, 0.55, 0.65, 0.8, 0.95, 1.0, 0.9, 0.5, 0.2, 0.0]:
		got.append_array(stick.step(Vector2(0, x), 1.0 / 60.0))
	assert_eq(got, ["ui_down"], "one press:")
	stick.free()


func test_holding_repeats_at_a_steady_pace() -> void:
	var stick := MenuStick.new()
	var got := _hold(stick, Vector2(0, -1), 1.0, 60.0)
	# One at once, the first repeat at 0.4 s, then one every 0.11 s up to 1 s.
	var want := 1 + 1 + int((1.0 - MenuStick.FIRST_REPEAT) / MenuStick.REPEAT)
	assert_eq(got.size(), want, "presses in a second held:")
	assert_eq(got[0], "ui_up", "")
	assert_eq(_hold(stick, Vector2(0, -1), 0.0, 60.0).size(), 0, "")
	stick.free()


func test_the_frame_rate_doesnt_change_anything() -> void:
	var counts: Array = []
	for fps in [60.0, 144.0, 240.0]:
		var stick := MenuStick.new()
		counts.append(_hold(stick, Vector2(1, 0.1), 1.5, fps).size())
		stick.free()
	assert_eq(counts[0], counts[1], "60 and 144 fps:")
	assert_eq(counts[0], counts[2], "60 and 240 fps:")


func test_a_diagonal_moves_one_way() -> void:
	var stick := MenuStick.new()
	var got := _hold(stick, Vector2(0.7, 0.75), 0.2, 60.0)
	assert_eq(got, ["ui_down"], "the stronger axis only:")
	stick.free()


func test_wobbling_at_the_edge_doesnt_repress() -> void:
	var stick := MenuStick.new()
	var got: Array = []
	for i in 20:  # hovering around the press point, for less than the repeat delay
		got.append_array(stick.step(Vector2(0.55 + 0.1 * float(i % 2), 0), 1.0 / 60.0))
	assert_eq(got, ["ui_right"], "pressed once:")
	stick.free()


func test_off_means_quiet() -> void:
	var stick := MenuStick.new()
	stick.enabled = false
	stick._process(0.016)
	assert_eq(stick.held, Vector2i.ZERO, "nothing held while a fight is on")
	stick.free()


func test_the_stick_is_out_of_the_built_in_menu_actions() -> void:
	Controls.setup()
	for action in Controls.UI_DIRECTIONS:
		var stick_events := 0
		var others := 0
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadMotion:
				stick_events += 1
			else:
				others += 1
		assert_eq(stick_events, 0, "%s has no stick binding:" % action)
		assert_gt(float(others), 0.0, "%s keeps its keys and d-pad" % action)


func test_menu_screens_animate_by_time() -> void:
	var a := TeamSelect.new()
	a.visible = true
	for i in 144:
		a._process(1.0 / 144.0)
	var b := TeamSelect.new()
	b.visible = true
	for i in 60:
		b._process(1.0 / 60.0)
	assert_eq(a._tick, b._tick, "a second at 144 fps = a second at 60:")
	assert_eq(b._tick, 60, "")
	var l := OnlineLobby.new()
	l.visible = true
	for i in 240:
		l._process(1.0 / 240.0)
	assert_eq(l._tick, 60, "the online screen too:")
	a.free()
	b.free()
	l.free()
