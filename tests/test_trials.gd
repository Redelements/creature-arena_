extends TestCase
## Combo Trials and Reaction Drills: every trial in data/trials.json can be cleared
## with real inputs, a wrong move fails, and answering tells correctly in a drill
## scores clean reps while ignoring them doesn't.

const ACTION_BIT := ComboTrials.ACTION_BIT


## Plays the current trial like a player: watch the demo, then perform the route.
func _attempt(t: ComboTrials, wrong_first := false) -> String:
	var sim := t.sim
	var r := t.route()
	var step := 0
	var press := false
	var serial := -1
	for i in 3000:
		var bits := 0
		if t.phase == ComboTrials.Phase.PLAY:
			var a := sim.creatures[0]
			if serial < 0:
				serial = a.attack_serial
			if a.attack_serial != serial:
				serial = a.attack_serial
				if step < r.size() and a.move_id == String(r[step][1]):
					step += 1
			if step < r.size():
				var want := String(r[step][0])
				if wrong_first and step == 0:
					want = "heavy"
				if bool(t.trial().get("partner_jab", false)) and step == 0:
					# Slip just as the partner's jab starts.
					var partner := sim.creatures[1]
					if partner.state == CreatureSim.State.ATTACK and partner.state_t <= 1:
						bits = ACTION_BIT[want]
				else:
					press = not press
					bits = ACTION_BIT[want] if press else 0
		sim.step(t.inputs(bits))
		t.after_step()
		if t.phase == ComboTrials.Phase.RESULT:
			return t.banner
	return "TIMEOUT"


func test_every_trial_can_be_cleared() -> void:
	var t := ComboTrials.new()
	assert_gt(float(t.trials.size()), 5.0, "trials loaded")
	for i in t.trials.size():
		t.index = i
		t.build()
		var result := _attempt(t)
		assert_eq(result, "CLEAR!", "trial %d (%s):" % [i + 1, String(t.trial()["name"])])


func test_a_wrong_move_fails_the_attempt() -> void:
	var t := ComboTrials.new()
	t.index = 0
	t.build()
	var result := _attempt(t, true)
	assert_true(result.begins_with("WRONG MOVE"), "pressing heavy first should fail, got " + result)


## Answers each tell the way the drill teaches: roll away from red, guard gold.
func _drill(set_name: String, answer: bool) -> ReactionDrill:
	var d := ReactionDrill.new(set_name, 5)
	var sim := d.build()
	var react_at := -1
	var tell := ""
	for i in 20000:
		if d.phase == ReactionDrill.Phase.DONE:
			break
		var bits := 0
		for e in sim.events:
			if String(e["type"]) == "windup" and int(e.get("who", -1)) == 1:
				tell = String(e.get("tell", ""))
				react_at = sim.tick + 12  # a human-ish 12 frames later
		if answer and react_at >= 0 and sim.tick >= react_at and d.phase == ReactionDrill.Phase.ATTACK:
			if tell in ["unblockable", "guard_break"]:
				bits = SimDefs.IN_DODGE | SimDefs.IN_LEFT if sim.tick == react_at else SimDefs.IN_LEFT
			else:
				bits = SimDefs.IN_GUARD
		if d.phase != ReactionDrill.Phase.ATTACK:
			react_at = -1
		sim.step(d.inputs(bits))
		d.after_step()
	return d


func test_answering_every_tell_goes_clean() -> void:
	for set_name in ["culvert", "cairn"]:
		var d := _drill(set_name, true)
		assert_eq(d.phase, ReactionDrill.Phase.DONE, "%s drill finished:" % set_name)
		assert_eq(d.clean, ReactionDrill.REPS, "%s drill, all reps clean:" % set_name)
		assert_false(d.reactions.is_empty(), "reaction times recorded")


func test_ignoring_the_tells_gets_hit() -> void:
	var d := _drill("culvert", false)
	assert_lt(float(d.clean), ReactionDrill.REPS * 0.5, "standing still should fail most reps")
