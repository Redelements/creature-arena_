extends TestCase
## Fight sounds fade with distance (AudioView): every placed sound plays from an
## AudioStreamPlayer2D at its event's spot with the ONE shared "falloff" block of
## data/audio.json (max_distance, attenuation, panning_strength), heard from AudioView's
## AudioListener2D (the current listener, moved by `set_listener`); the crowd and the
## match-wide stingers stay unplaced; FxView's timed sounds carry their spot; and
## proximity voice chat fades by the same curve (Godot's 2D one) with its team floor.


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## The shared block as data/audio.json writes it, read here on its own.
func _block() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(AudioView.DATA_PATH))
	assert_true(data is Dictionary and data.get("falloff") is Dictionary, "data/audio.json has a falloff block")
	return data["falloff"] if data is Dictionary else {}


func _view() -> AudioView:
	var av := AudioView.new()
	_root().add_child(av)
	return av


func test_placed_sounds_use_the_shared_falloff_and_the_listener() -> void:
	var fo := _block()
	var av := _view()
	assert_eq(_root().get_viewport().get_audio_listener_2d(), av.listener, "AudioView's listener is the current one:")
	av.set_listener(Vector2(100, 100))
	assert_eq(av.listener.global_position, Vector2(100, 100), "the listener moves:")
	var near := av.play_at("hit_light", Vector2(100, 100))
	var far := av.play_at("hit_heavy", Vector2(100, 100) + Vector2(float(fo["max_distance"]) * 2.0, 0))
	for p in [near, far]:
		assert_true(p is AudioStreamPlayer2D, "a placed sound takes a 2D player")
		if p == null:
			continue
		assert_near(p.max_distance, float(fo["max_distance"]), 0.001, "max_distance from the shared block:")
		assert_near(p.attenuation, float(fo["attenuation"]), 0.001, "attenuation from the shared block:")
		assert_near(p.panning_strength, float(fo["panning_strength"]), 0.001, "panning from the shared block:")
		assert_eq(p.bus, &"Effects", "on the Effects bus (its Settings slider):")
	if near != null and far != null:
		assert_true(near != far, "two sounds, two players")
		assert_eq(near.global_position, Vector2(100, 100), "the near one at its spot:")
		assert_near(far.global_position.distance_to(av.listener.global_position), float(fo["max_distance"]) * 2.0,
			0.001, "the far one past max_distance:")
	assert_eq(AudioView.falloff_gain(0.0), 1.0, "full at the listener")
	assert_eq(AudioView.falloff_gain(float(fo["max_distance"]) * 2.0), 0.0, "silent past max_distance")
	# Every 2D player in the pool, not just the ones taken, wears the same falloff.
	assert_eq(av._players.size(), AudioView.VOICES, "the placed pool:")
	for p in av._players:
		assert_near(p.max_distance, float(fo["max_distance"]), 0.001, "pool max_distance:")
		assert_near(p.attenuation, float(fo["attenuation"]), 0.001, "pool attenuation:")
	av.free()


func test_a_hit_plays_where_it_lands_and_the_crowd_everywhere() -> void:
	var av := _view()
	var before := av._next
	av.on_event({"type": "hit", "pos": Vector2(320, 40), "power": 4.0, "tick": 1})
	assert_eq(av._next, (before + 1) % AudioView.VOICES, "the hit took one placed player:")
	assert_eq(av._players[before].global_position, Vector2(320, 40), "at the hit's spot:")
	var placed := av._next
	av.on_event({"type": "ko", "pos": Vector2(10, 10), "power": 1.0, "tick": 2})
	assert_eq(av._next, placed, "the KO sting and the crowd's roar are not placed:")
	av.on_event({"type": "hazard_warn", "pos": Vector2(10, 10), "power": 1.0, "tick": 3, "shape": "wave"})
	assert_eq(av._next, placed, "a hazard's warning reaches everyone:")
	av.free()


func test_effect_cues_carry_their_spot() -> void:
	var args := []
	for sig in (load("res://src/view/fx_view.gd") as Script).get_script_signal_list():
		if String(sig["name"]) == "cue":
			args = sig["args"]
	assert_eq(args.size(), 2, "FxView.cue(sound, at):")
	if args.size() == 2:
		assert_eq(int(args[1]["type"]), TYPE_VECTOR2, "its second argument is the world spot:")


func test_voice_fades_by_the_same_curve() -> void:
	var fo := _block()
	var most := float(fo["max_distance"])
	var att := float(fo["attenuation"])
	for d in [most * 0.1, most * 0.4, most * 0.8]:
		var godot := pow(1.0 - d / most, att)  # AudioStreamPlayer2D: pow(1 - dist / max_distance, attenuation)
		assert_near(VoiceChat.gain_for(d, false), godot, 0.0001, "a voice %d px away, as a fight sound:" % int(d))
		assert_near(AudioView.falloff_gain(d), godot, 0.0001, "falloff_gain at %d:" % int(d))
	assert_eq(VoiceChat.gain_for(most, false), 0.0, "a foe's voice is silent at max_distance")
	var team_floor := float(VoiceChat.data().get("team_floor", 0.25))
	assert_near(VoiceChat.gain_for(most * 2.0, true), team_floor, 0.0001, "a teammate keeps the team floor:")
	assert_near(VoiceChat.gain_for(most * 0.1, true), maxf(team_floor, pow(0.9, att)), 0.0001, "a near teammate, the curve:")
