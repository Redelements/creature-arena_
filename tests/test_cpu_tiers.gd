extends TestCase
## The CPU difficulty table (`CpuController.LEVELS`): Normal sits strictly between Easy
## and Hard on every knob (the Oct 2026 nerf: no knob where Normal equals Hard), the knobs
## every tier reads are present on every row, and a kiting mage leads its shots by its
## tier's `lead` (Easy none, Hard and Rage in full). Numbers: docs/plans/cpu-tiers.md.

const KNOBS := ["reaction", "defend", "combo", "mistake", "breakaway", "aggression", "think", "gap", "lead"]


func test_every_tier_has_every_knob() -> void:
	for row in CpuController.LEVELS:
		for k in KNOBS:
			assert_true((row as Dictionary).has(k), "%s has %s" % [row["name"], k])


func test_normal_sits_strictly_between_easy_and_hard() -> void:
	var easy: Dictionary = CpuController.LEVELS[0]
	var normal: Dictionary = CpuController.LEVELS[1]
	var hard: Dictionary = CpuController.LEVELS[2]
	for k in KNOBS:
		var e := float(easy[k])
		var n := float(normal[k])
		var h := float(hard[k])
		var lo := minf(e, h)
		var hi := maxf(e, h)
		assert_true(n > lo and n < hi, "%s: Normal %.2f strictly between Easy %.2f and Hard %.2f" % [k, n, e, h])


func test_hard_is_at_least_as_sharp_as_normal_and_rage_as_hard() -> void:
	# Lower reaction and think and mistake are sharper; the rest higher.
	for k in KNOBS:
		var sign := -1.0 if k in ["reaction", "think", "mistake"] else 1.0
		var n := float(CpuController.LEVELS[1][k]) * sign
		var h := float(CpuController.LEVELS[2][k]) * sign
		var r := float(CpuController.LEVELS[3][k]) * sign
		assert_true(h >= n, "%s: Hard at least Normal" % k)
		assert_true(r >= h, "%s: Rage at least Hard" % k)


func test_a_kiting_mage_leads_its_shots_by_its_tier() -> void:
	# The lead is read off the tier row (it was a hard-coded 0.5 for Normal, 1.0 above).
	assert_near(float(CpuController.LEVELS[0]["lead"]), 0.0, 0.001, "Easy throws straight (8-way, no lead):")
	assert_near(float(CpuController.LEVELS[2]["lead"]), 1.0, 0.001, "Hard leads in full:")
	assert_near(float(CpuController.LEVELS[3]["lead"]), 1.0, 0.001, "Rage leads in full:")
	var cpu := CpuController.new(0, 1, 7)
	assert_near(float(cpu.p["lead"]), float(CpuController.LEVELS[1]["lead"]), 0.001, "a Normal controller carries its row's lead:")
