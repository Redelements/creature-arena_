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
