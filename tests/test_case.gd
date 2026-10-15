class_name TestCase
extends RefCounted
## Minimal assertion helpers for the headless test runner (tests/run_tests.gd).
## Each test file extends this; every method named test_* is run on a fresh instance.

var errors: Array[String] = []


func fail(msg: String) -> void:
	errors.append(msg)


func assert_true(cond: bool, msg := "expected true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg := "expected false") -> void:
	if cond:
		fail(msg)


func assert_eq(actual, expected, msg := "") -> void:
	if actual != expected:
		fail("%s expected %s, got %s" % [msg, str(expected), str(actual)])


func assert_near(actual: float, expected: float, tol := 0.01, msg := "") -> void:
	if absf(actual - expected) > tol:
		fail("%s expected %.3f (±%.3f), got %.3f" % [msg, expected, tol, actual])


func assert_lt(actual: float, limit: float, msg := "") -> void:
	if not actual < limit:
		fail("%s expected < %s, got %s" % [msg, str(limit), str(actual)])


func assert_gt(actual: float, limit: float, msg := "") -> void:
	if not actual > limit:
		fail("%s expected > %s, got %s" % [msg, str(limit), str(actual)])


# ---------------------------------------------------------------- sim helpers

## Steps the match `ticks` times with fixed inputs for player 0 and player 1.
func run(sim: MatchSim, p0: int, ticks: int, p1 := 0) -> void:
	for i in ticks:
		sim.step(PackedInt32Array([p0, p1]))


## Presses a button for one tick, then idles for `wait` ticks.
func tap(sim: MatchSim, p0: int, wait: int, p1 := 0) -> void:
	run(sim, p0, 1, p1)
	run(sim, 0, wait, p1)


## Runs until `cond` is true or `limit` ticks pass. Returns whether it became true.
func run_until(sim: MatchSim, cond: Callable, limit: int, p0 := 0, p1 := 0) -> bool:
	for i in limit:
		sim.step(PackedInt32Array([p0, p1]))
		if cond.call():
			return true
	return false


## Damage from "hit" events this tick, from attacker `a` to target `d`.
func hit_damage(sim: MatchSim, a: int, d: int) -> float:
	var total := 0.0
	for e in sim.events:
		if e["type"] == "hit" and int(e["attacker"]) == a and int(e["target"]) == d:
			total += float(e["power"])
	return total


## Plays a combo route for creature `atk` against the other creature, like a player
## would: mashes each step's button until the expected move starts, then moves on.
## `steps` is a list of [input bit, expected move id]. `other` is the defender's input.
## Returns the total combo damage dealt, once the defender has recovered.
## Steps are [bit, move] or [bit, move, ticks to hold it once it starts].
func route(sim: MatchSim, atk: int, steps: Array, other := 0) -> float:
	var a := sim.creatures[atk]
	var d := sim.creatures[1 - atk]
	var dealt := 0.0
	for s in steps:
		var bit: int = s[0]
		var expect: String = s[1]
		var serial := a.attack_serial
		var started := false
		var press := true
		for i in 120:
			var inputs := [0, 0]
			inputs[atk] = bit if press else 0
			inputs[1 - atk] = other
			sim.step(PackedInt32Array(inputs))
			dealt += hit_damage(sim, atk, 1 - atk)
			press = not press
			if a.attack_serial != serial and a.move_id == expect:
				started = true
				# [bit, move, ticks]: keep the button held that long (a charged Runoff).
				for k in (int(s[2]) if s.size() > 2 else 0):
					var held := [0, 0]
					held[atk] = bit
					held[1 - atk] = other
					sim.step(PackedInt32Array(held))
					dealt += hit_damage(sim, atk, 1 - atk)
				break
		if not started:
			fail("route never reached %s (in %s, state %d; target combo %d, state %d)"
				% [expect, a.move_id, a.state, d.combo_hits, d.state])
			return dealt
	for i in 240:
		sim.step(PackedInt32Array([0, 0]))
		dealt += hit_damage(sim, atk, 1 - atk)
		if a.state != CreatureSim.State.ATTACK and not d.is_stunned():
			break
	return dealt
