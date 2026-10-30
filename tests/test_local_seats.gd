extends TestCase
## The seat table (LocalSeats): who gets which controller at a match's start, a pad
## unplugged and plugged back mid-match, whose pad an event is, and the per-controller
## reading that follows the gamepad remaps (PlayerInput.pad_map).


func _seats() -> LocalSeats:
	return LocalSeats.new()


func test_solo_player_1_listens_to_any_pad_and_the_keyboard() -> void:
	var s := _seats()
	assert_eq(s.assign(1, [0, 1]), "", "nobody missing")
	assert_eq(s.device_of(0), PlayerInput.ANY_PAD, "any pad")
	assert_true(s.inputs[0].keyboard, "and the keyboard")
	for k in [1, 2, 3]:
		assert_eq(s.device_of(k), PlayerInput.NO_PAD, "seat %d empty" % k)
		assert_false(s.inputs[k].keyboard, "seats 2-4 never have the keyboard")
	assert_eq(s.seat_of_device(7), 0, "any pad is player 1's")


func test_a_pad_each_gives_everyone_one_in_order() -> void:
	var s := _seats()
	assert_eq(s.assign(3, [4, 5, 6]), "", "")
	assert_eq(s.device_of(0), 4, "player 1 the first pad")
	assert_true(s.inputs[0].keyboard, "and still the keyboard")
	assert_eq(s.device_of(1), 5, "")
	assert_eq(s.device_of(2), 6, "")
	assert_eq(s.device_of(3), PlayerInput.NO_PAD, "nobody in seat 4")
	assert_eq(s.seat_of_device(6), 2, "")
	assert_eq(s.seat_of_device(9), -1, "a pad nobody plays on")
	assert_true(s.seated(2), "")
	assert_false(s.seated(3), "")


func test_one_pad_short_player_1_takes_the_keyboard() -> void:
	var s := _seats()
	assert_eq(s.assign(2, [3]), "", "two people, one pad: nobody missing")
	assert_eq(s.device_of(0), PlayerInput.NO_PAD, "player 1 on keyboard and mouse")
	assert_true(s.inputs[0].keyboard, "")
	assert_eq(s.device_of(1), 3, "player 2 the pad")
	assert_eq(s.seat_of_device(3), 1, "")
	assert_eq(s.seat_of_device(8), -1, "player 1 isn't on any pad now")


func test_missing_controllers_are_asked_for() -> void:
	var s := _seats()
	assert_eq(s.assign(3, []), "Connect 2 controllers for players 2-3", "")
	assert_eq(_seats().assign(2, []), "Connect 1 controller for players 2", "")
	assert_eq(_seats().assign(4, [1]), "Connect 2 controllers for players 2-4", "")
	assert_false(s.seated(1), "")


func test_a_pad_plugged_in_later_fills_the_empty_seat() -> void:
	var s := _seats()
	s.assign(3, [0])
	assert_eq(s.device_of(1), 0, "")
	assert_eq(s.device_of(2), PlayerInput.NO_PAD, "")
	assert_eq(s.pad_found(1, "guid-b"), 2, "the waiting seat")
	assert_eq(s.device_of(2), 1, "")
	assert_eq(s.pad_found(2, "guid-c"), -1, "nobody else is waiting")


func test_an_unplugged_pad_frees_its_seat_and_the_same_pad_takes_it_back() -> void:
	var s := _seats()
	s.assign(3, [0, 1, 2], {0: "g0", 1: "g1", 2: "g2"})
	s.inputs[2]._pad_prev = {"guard": true}
	assert_eq(s.pad_lost(2), 2, "player 3 lost theirs")
	assert_eq(s.device_of(2), PlayerInput.NO_PAD, "")
	assert_true(s.inputs[2]._pad_prev.is_empty(), "nothing stays held")
	assert_eq(s.pad_lost(2), -1, "already gone")
	assert_eq(s.pad_lost(9), -1, "a pad nobody held")
	assert_eq(s.pad_lost(1), 1, "player 2 too")
	# Player 3's pad comes back first, under a new id: it goes to seat 3 by GUID, not to the
	# first waiting seat.
	assert_eq(s.pad_found(5, "g2"), 2, "the same pad, its own seat")
	assert_eq(s.device_of(2), 5, "")
	assert_eq(s.pad_found(6, "other"), 1, "an unknown pad takes the first seat still waiting")
	assert_eq(s.device_of(1), 6, "")
	assert_true(s.lost.is_empty(), "")


func test_player_1_loses_their_pad_and_keeps_the_keyboard() -> void:
	var s := _seats()
	s.assign(2, [0, 1])
	assert_eq(s.pad_lost(0), 0, "")
	assert_eq(s.device_of(0), PlayerInput.NO_PAD, "")
	assert_true(s.inputs[0].keyboard, "the keyboard still plays")
	assert_true(s.seated(0), "")
	assert_eq(s.pad_found(0, ""), 0, "")


func test_events_belong_to_the_seat_holding_the_pad() -> void:
	var s := _seats()
	s.assign(2, [0, 1])
	var jb := InputEventJoypadButton.new()
	jb.device = 1
	jb.button_index = JOY_BUTTON_START
	jb.pressed = true
	assert_eq(s.owner_of_event(jb), 1, "player 2's Start")
	jb.device = 0
	assert_eq(s.owner_of_event(jb), 0, "")
	jb.device = 3
	assert_eq(s.owner_of_event(jb), -1, "a pad nobody plays on")
	var key := InputEventKey.new()
	key.pressed = true
	assert_eq(s.owner_of_event(key), 0, "the keyboard is player 1's")
	assert_eq(s.note_event(jb), -1, "nobody takes it")
	jb.device = 1
	assert_eq(s.note_event(jb), 1, "")
	assert_eq(s.inputs[1].pad_id, 1, "player 2 noted their pad")
	assert_eq(s.rumble_device(1), 1, "and it's the one to rumble")
	assert_eq(s.rumble_device(0), -1, "player 1 hasn't touched a pad")
	s.note_event(key)
	assert_eq(s.rumble_device(0), -1, "")


func test_pad_map_follows_the_gamepad_remaps() -> void:
	Controls.setup()
	var map := PlayerInput.pad_map()
	assert_eq((map["light"]["buttons"] as Array), [JOY_BUTTON_A], "A is light by default")
	assert_eq((map["skill_2"]["buttons"] as Array), [JOY_BUTTON_B], "")
	assert_eq((map["surge"]["axes"] as Array), [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], "RT is surge")
	assert_eq((map["tag"]["axes"] as Array), [[JOY_AXIS_TRIGGER_LEFT, 1.0]], "")
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	Controls.rebind("gamepad", "pad_light", b)
	map = PlayerInput.pad_map()
	assert_eq((map["light"]["buttons"] as Array), [JOY_BUTTON_B], "light is B now")
	assert_eq((map["skill_2"]["buttons"] as Array), [JOY_BUTTON_A], "and skill 2 took A (a swap)")
	Controls.reset("gamepad")
	map = PlayerInput.pad_map()
	assert_eq((map["light"]["buttons"] as Array), [JOY_BUTTON_A], "back to the default")
	assert_false(PlayerInput.pad_action_held(0, map["light"]), "no controller 0 here: nothing held")
