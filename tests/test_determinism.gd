extends TestCase
## The simulation must be deterministic: same inputs, same match, every time.
## This is what makes replays, regression tests and (later) rollback netcode possible.

const TICKS := 1800  # 30 seconds of play


## Mashes random buttons, holding each combination for a random 1-20 ticks.
func _random_inputs(seed_: int, n: int) -> Array[PackedInt32Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var frames: Array[PackedInt32Array] = []
	var hold := [0, 0]
	var left := [0, 0]
	for i in n:
		var f := PackedInt32Array()
		for p in 2:
			if left[p] <= 0:
				hold[p] = rng.randi() & SimDefs.IN_EVERYTHING
				left[p] = rng.randi_range(1, 20)
			left[p] -= 1
			f.append(hold[p])
		frames.append(f)
	return frames


func _play(frames: Array[PackedInt32Array]) -> MatchSim:
	var sim := MatchFactory.versus("cairn", "culvert")
	for f in frames:
		sim.step(f)
	return sim


func test_same_inputs_produce_the_same_match() -> void:
	var frames := _random_inputs(1234, TICKS)
	var a := MatchFactory.versus("cairn", "culvert")
	var b := MatchFactory.versus("cairn", "culvert")
	# Start them in reach of each other so random mashing reliably lands hits.
	for sim in [a, b]:
		sim.creatures[0].pos = Vector2(220, 164)
		sim.creatures[1].pos = Vector2(245, 164)
	for i in frames.size():
		a.step(frames[i])
		b.step(frames[i])
		if i % 60 == 0 and a.state_hash() != b.state_hash():
			fail("diverged at tick %d" % i)
			return
	assert_eq(a.state_hash(), b.state_hash(), "final hash:")
	var total_hp := a.creatures[0].hp + a.creatures[1].hp
	var max_hp := a.creatures[0].max_hp + a.creatures[1].max_hp
	assert_lt(total_hp, max_hp, "random mashing should land at least one hit:")


func test_different_inputs_produce_a_different_match() -> void:
	var a := _play(_random_inputs(1, TICKS))
	var b := _play(_random_inputs(2, TICKS))
	assert_true(a.state_hash() != b.state_hash(), "different seeds should differ")


func test_replay_survives_a_save_and_load_round_trip() -> void:
	var frames := _random_inputs(99, TICKS)
	var rec := Replay.new()
	var live := MatchFactory.versus("cairn", "culvert")
	for f in frames:
		rec.record(f)
		live.step(f)
	var parsed = JSON.parse_string(JSON.stringify(rec.to_dict()))
	var loaded := Replay.from_dict(parsed)
	assert_eq(loaded.frames.size(), frames.size(), "frame count:")
	assert_eq(loaded.play(MatchFactory.versus("cairn", "culvert")), live.state_hash(), "replayed hash:")


func test_replay_file_on_disk() -> void:
	var rec := Replay.new()
	for f in _random_inputs(7, 600):
		rec.record(f)
	var path := "user://test_replays/round_trip.json"
	assert_eq(rec.save(path), OK, "save:")
	var loaded := Replay.load_file(path)
	assert_true(loaded != null, "load:")
	if loaded != null:
		assert_eq(loaded.play(MatchFactory.versus()), rec.play(MatchFactory.versus()), "file replay hash:")
