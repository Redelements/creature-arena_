class_name SimCheck
extends RefCounted
## Cross-platform determinism check. Plays a long seeded match of random button mashing
## (fighters start in reach, so it's full of hits, combos, Surges, pits and KOs) plus a
## Duel full of tags, and returns one exact fingerprint for both. CI runs it on the Linux and Windows builds:
## online play only works if every platform gets the same answer.
##   Ready4Rambles --headless -- --sim-check=SEED [--sim-check-out=PATH]


static func run(seed_: int, ticks := 6000) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var sim := MatchFactory.versus("cairn", "culvert")
	sim.creatures[0].pos = MatchFactory.SPAWN_LEFT + Vector2(50, 0)
	sim.creatures[1].pos = MatchFactory.SPAWN_LEFT + Vector2(75, 0)
	var hold := [0, 0]
	var left := [0, 0]
	for i in ticks:
		for p in 2:
			if left[p] <= 0:
				hold[p] = rng.randi() & SimDefs.IN_EVERYTHING
				left[p] = rng.randi_range(1, 20)
			left[p] -= 1
		sim.step(PackedInt32Array(hold))
		# Keep the fight going: refill health so it never ends in a KO stalemate.
		if i % 1200 == 1199:
			for c in sim.creatures:
				c.hp = c.max_hp
				if c.state == CreatureSim.State.KO:
					c.load_state(_revived(c))
	return (sim.state_digest() + _duel(seed_ + 1, ticks) + _quarry(seed_ + 2, ticks / 2)).sha256_text()


## A brawl on Quarry Bowl, so the walls (collision, bounces, shots stopped) are in the
## cross-platform check too.
static func _quarry(seed_: int, ticks: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var was := MatchFactory.arena
	MatchFactory.arena = "quarry"
	var sim := MatchFactory.versus("craglash", "hissy")
	MatchFactory.arena = was
	# Start against the left wall so the fight happens around it.
	sim.creatures[0].pos = sim.spawn(0) + Vector2(-60, 0)
	sim.creatures[1].pos = sim.spawn(0) + Vector2(-30, 10)
	var hold := [0, 0]
	for i in ticks:
		if i % 7 == 0:
			hold = [rng.randi() & SimDefs.IN_EVERYTHING, rng.randi() & SimDefs.IN_EVERYTHING]
		sim.step(PackedInt32Array(hold))
		if i % 1200 == 1199:
			for c in sim.creatures:
				c.hp = c.max_hp
				if c.state == CreatureSim.State.KO:
					c.load_state(_revived(c))
	return sim.state_digest()


## A Duel with random inputs, tags included.
static func _duel(seed_: int, ticks: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var d := DuelSim.new([["cairn", "culvert", "cairn"], ["culvert", "cairn", "culvert"]])
	d.sim.creatures[0].pos = MatchFactory.SPAWN_LEFT + Vector2(50, 0)
	d.sim.creatures[1].pos = MatchFactory.SPAWN_LEFT + Vector2(75, 0)
	var hold := [0, 0]
	for i in ticks:
		if i % 9 == 0:
			hold = [rng.randi() & SimDefs.IN_EVERYTHING, rng.randi() & SimDefs.IN_EVERYTHING]
		d.step(PackedInt32Array(hold))
	return d.state_digest()


static func _revived(c: CreatureSim) -> Dictionary:
	var st := c.save_state()
	st["state"] = CreatureSim.State.IDLE
	st["state_t"] = 0
	st["stun"] = 0
	return st
