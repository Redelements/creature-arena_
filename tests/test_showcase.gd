extends TestCase
## Every showcase must play through with real inputs: if tuning breaks a combo or a
## counter shown in a demo, this says which step.


func _play(name: String) -> Dictionary:
	var sc := Showcase.new(name)
	var sim := sc.build()
	var log := {"grabbed": [false, false], "hit": [0, 0], "ko": [false, false], "parts": [], "staggered": 0}
	for i in range(2, sim.creatures.size()):  # a script's "extra" fighters
		log["grabbed"].append(false)
		log["hit"].append(0)
		log["ko"].append(false)
	for i in 5000:
		if sc.finished:
			break
		sim.step(sc.inputs(sim))
		for e in sim.events:
			log["parts"].append([sc.part, String(e["type"]), int(e.get("target", e.get("who", -1)))])
			match String(e["type"]):
				"grab", "swallow":
					log["grabbed"][int(e["target"])] = true
				"hit":
					log["hit"][int(e["target"])] += 1
					if bool(e.get("stagger_if", false)):
						log["staggered"] += 1
				"ko":
					log["ko"][int(e["who"])] = true
	assert_true(sc.finished, "%s showcase should finish" % name)
	assert_eq(sc.failed, "", "%s showcase:" % name)
	log["sim"] = sim
	return log


func test_cairn_showcase_plays_through_to_a_knockout() -> void:
	var r := _play("cairn")
	assert_true(r["ko"][1], "the last Avalanche should knock Culvert out")
	assert_false(r["ko"][0], "Cairn stays up")


func test_culvert_showcase_plays_through_to_a_knockout() -> void:
	var r := _play("culvert")
	assert_true(r["grabbed"][1], "Gulp should swallow Cairn")
	assert_true(r["ko"][1], "Storm Drain should finish Cairn")


func test_counterplay_showcase_answers_every_big_move() -> void:
	var r := _play("counterplay")
	var on_cairn := 0
	var punished := [0, 0, 0]
	var blocked := false
	for ev in r["parts"]:
		var part := int(ev[0])
		var kind := String(ev[1])
		var target := int(ev[2])
		if part < 2 and target == 0 and kind in ["hit", "grab"]:
			on_cairn += 1
		if kind in ["hit", "grab"] and target == (1 if part == 0 else 0):
			punished[part] += 1
		if part == 2 and kind == "block" and target == 1:
			blocked = true
	assert_eq(on_cairn, 0, "rolling through Gulp and dodging Storm Drain should avoid all damage:")
	assert_gt(float(punished[0]), 3.0, "the Gulp whiff punish should land")
	assert_true(blocked, "Culvert should block the raw Rush")
	assert_gt(float(punished[2]), 2.0, "the block punish should land")


func test_craglash_showcase_plays_through_to_a_knockout() -> void:
	var r := _play("craglash")
	var armored := false
	for ev in r["parts"]:
		if int(ev[0]) == 2 and String(ev[1]) == "armor" and int(ev[2]) == 0:
			armored = true
	assert_true(armored, "Cairn's jab should hit Bedrock's armor")
	assert_true(r["ko"][1], "the Stomp and Charge out of Bedrock should finish Cairn")
	assert_false(r["ko"][0], "Craglash stays up")


func test_barkley_showcase_plays_through_to_a_knockout() -> void:
	var r := _play("barkley")
	var pulls := 0
	var bursts := 0
	for ev in r["parts"]:
		if String(ev[1]) == "pull":
			pulls += 1
		if String(ev[1]) == "burst":
			bursts += 1
	assert_eq(pulls, 2, "Branch Grab should snag Cairn in both parts:")
	assert_eq(bursts, 1, "one Pinecone Bomb:")
	assert_true(r["ko"][1], "Root Eruption should finish Cairn")
	assert_false(r["ko"][0], "Barkley stays up")


func test_gillbert_showcase_plays_through_to_a_knockout() -> void:
	var r := _play("gillbert")
	var reels := 0
	for ev in r["parts"]:
		if String(ev[1]) == "reel":
			reels += 1
	assert_eq(reels, 1, "Cast Line should hook Cairn and reel Gillbert in:")
	assert_true(r["ko"][1], "The One That Got Away should finish Cairn")
	assert_false(r["ko"][0], "Gillbert stays up")


func test_cerebro_showcase_plays_through_to_a_knockout() -> void:
	var r := _play("cerebro")
	var flips := 0
	for ev in r["parts"]:
		if String(ev[1]) == "grab":
			flips += 1
	assert_eq(flips, 1, "Flip Out should throw Cairn over his head:")
	assert_gt(int(r["staggered"]), 0, "the Mallet Toss staggers the tenderized Cairn")
	assert_true(r["ko"][1], "Knife Flurry should finish Cairn")
	assert_false(r["ko"][0], "Chef Cerebro stays up")


func test_hissy_showcase_plays_through_to_a_knockout() -> void:
	var r := _play("hissy")
	var kinds := {}
	for ev in r["parts"]:
		kinds[String(ev[1])] = true
	for k in ["gaze", "poisoned", "petrify", "shatter"]:
		assert_true(kinds.has(k), "the showcase should show %s" % k)
	assert_true(r["ko"][1], "the shattering combo should finish Cairn")
	assert_false(r["ko"][0], "Hissy Fitz stays up")


func test_angles_showcase_lands_up_and_down() -> void:
	var r := _play("angles")
	var hits := [0, 0, 0, 0, 0]
	for ev in r["parts"]:
		if String(ev[1]) == "hit":
			hits[int(ev[0])] += 1
	assert_gt(float(hits[0]), 2.0, "Craglash's combo facing down should land")
	assert_gt(float(hits[1]), 1.0, "Craglash's combo facing up should land")
	assert_gt(float(hits[2]), 4.0, "Cairn's combo from above should land")
	assert_gt(float(hits[3]), 0.0, "Mountain Maw straight down should land")
	assert_gt(float(hits[4]), 1.0, "a combo that turns down mid-way should land")


func test_twinstick_showcase_strafes_and_lands_off_angle() -> void:
	var r := _play("twinstick")
	var hits := [0, 0, 0]
	for ev in r["parts"]:
		if String(ev[1]) == "hit" and int(ev[2]) == 1:
			hits[int(ev[0])] += 1
	assert_eq(hits[0], 0, "strafing doesn't attack")
	assert_gt(float(hits[1]), 0.0, "the off-angle Landslide Charge should land")
	assert_gt(float(hits[2]), 1.0, "the string after circling should land")


func test_digby_showcase_plays_through_to_a_knockout() -> void:
	var r := _play("digby")
	var kinds := {}
	for ev in r["parts"]:
		kinds[String(ev[1])] = true
	for k in ["blinded", "miss", "rooted"]:
		assert_true(kinds.has(k), "the showcase should show %s" % k)
	assert_true(r["ko"][1], "Cave-In should finish Cairn")
	assert_false(r["ko"][0], "Digby stays up")


func test_pete_showcase_plays_through_to_a_knockout() -> void:
	var r := _play("pete")
	var kinds := {}
	for ev in r["parts"]:
		kinds[String(ev[1])] = true
	for k in ["stealth", "steal", "blink"]:
		assert_true(kinds.has(k), "the showcase should show %s" % k)
	assert_true(r["ko"][1], "The Big Heist should finish Cairn")
	assert_false(r["ko"][0], "Sneaky Pete stays up")


func test_sno_showcase_plays_through_to_a_knockout() -> void:
	var r := _play("sno")
	var kinds := {}
	for ev in r["parts"]:
		kinds[String(ev[1])] = true
	for k in ["zone", "slow", "freeze", "shatter"]:
		assert_true(kinds.has(k), "the showcase should show %s" % k)
	assert_true(r["ko"][1], "the shattering combo should finish Cairn")
	assert_false(r["ko"][0], "Sno Mercy stays up")


func test_crease_showcase_plays_through_and_the_frogs_connect() -> void:
	var r := _play("crease")
	var frog_hits := 0
	var kinds := {}
	for ev in r["parts"]:
		kinds[String(ev[1])] = true
		if int(ev[0]) == 2 and String(ev[1]) == "hit" and int(ev[2]) == 1:
			frog_hits += 1
	assert_gt(float(frog_hits), 0.0, "a Paper Frog should hit Cairn in the frog part")
	for k in ["fold", "projectile", "storm"]:
		assert_true(kinds.has(k), "the showcase should show %s" % k)
	assert_false(r["ko"][0], "Mister Crease stays up")


func test_crease_storm_trailer_beat_hits_all_three_foes() -> void:
	var r := _play("crease_storm")
	var kinds := {}
	for ev in r["parts"]:
		kinds[String(ev[1])] = true
	assert_true(kinds.has("storm"), "Thousand Cranes should make a storm")
	for i in [1, 2, 3]:
		assert_gt(float(r["hit"][i]), 0.0, "the storm should hit bunched foe %d" % i)
	assert_eq(int(r["hit"][0]), 0, "Mister Crease is not hit")


func test_pete_flank_trailer_beat_robs_cerebro_past_the_tank() -> void:
	var r := _play("pete_flank")
	var kinds := {}
	for ev in r["parts"]:
		kinds[String(ev[1])] = true
	for k in ["stealth", "steal", "blink"]:
		assert_true(kinds.has(k), "the flank should show %s" % k)
	assert_true(r["ko"][1], "The Big Heist should finish Chef Cerebro")
	assert_eq(int(r["hit"][2]), 0, "Pete goes round the tank, never through him")
	var sim: MatchSim = r["sim"]
	assert_gt(sim.creatures[0].pos.x, sim.creatures[1].pos.x, "Pete ends up behind Cerebro")


func test_maw_hit_showcase_hits_craglash_while_his_head_flies() -> void:
	# The beat for Mountain Maw's headless hurt rows (hurt_nohead): Cairn's jab must land on
	# Craglash while his head projectile is still out.
	var sc := Showcase.new("maw_hit")
	var sim := sc.build()
	var mid_flight := false
	for i in 2000:
		if sc.finished:
			break
		sim.step(sc.inputs(sim))
		for e in sim.events:
			if String(e["type"]) == "hit" and int(e.get("target", -1)) == 0:
				for pr in sim.projectiles:
					if int(pr["owner"]) == 0:
						mid_flight = true
	assert_true(sc.finished, "maw_hit showcase should finish")
	assert_eq(sc.failed, "", "maw_hit showcase:")
	assert_true(mid_flight, "Cairn should hit Craglash while his head flies")
