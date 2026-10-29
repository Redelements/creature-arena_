extends TestCase
## Rollback fuzz: snapshot()/restore()/state_digest() across every mode, with every arena
## hazard on (tidal wave, meteor shower, rolling boulder, fault line, applied the way the
## game does: MatchSim.apply_mutators with the match seed), shrines on wherever the mode's
## rules can take them, and the Brawl crown. Normal CPUs drive some slots; the others mash
## random input bitmasks from a test-side seeded PRNG (never randomness in the sim).
##
## Each match: step it; at random ticks take snapshot() and state_digest(); keep stepping K
## ticks (recording every input); then restore() and check the digest is the one at the
## snapshot, re-step the same K inputs and check the digest matches the first time; then do
## it again from the same snapshot (a snapshot must survive being restored and re-stepped,
## as real rollbacks restore one snapshot many times). At the end a second, fresh match fed
## the same inputs from tick 0 with no rollbacks must match at every snapshot tick and at the
## end, so a field that is mutated but never snapshotted (or never hashed) shows up.
## Each mode asserts its own events happened (a respawn, a shrine claim, a crown change, a
## caravan checkpoint, a flag capture, every hazard striking...) so the fuzz is not vacuous.
##
## To reach all that in a short run the test (not the game) brings things forward: the
## hazards' first warnings at 3-9 s and then at most every 14 s, shrines ready at 8 s and
## quick to claim, the Glass cannon mutator for quicker KOs, a faster caravan with nearer
## checkpoints, Capture the Flag carriers at full speed. None of that touches what is saved.
## A digest failure is a real rollback bug (state missed by snapshot/restore/state_digest, or a
## CreatureSim var missing from STATE_FIELDS); a "never reached" failure is coverage only: a
## change in how matches play moved the events, so retune that mode's ticks or rules here.
##
## Default: one seed a mode at the tick counts below, plus up to EXTRA_SEEDS more while a
## wanted event is still missing (about 30-40 s in all, for CI). TEST_FUZZ_LONG=1 (an
## environment variable) is the deep soak: ten times the seeds and ten times the ticks.
##   TEST_ONLY=rollback_fuzz godot --headless --path . --script res://tests/run_tests.gd
##   TEST_FUZZ_LONG=1 TEST_ONLY=rollback_fuzz godot --headless --path . --script res://tests/run_tests.gd

const HAZARDS := ["tidal_wave", "meteor_shower", "rolling_boulder", "fault_line"]
## Shrines for a team mode whose rules leave them out (as tests/bench_modes.gd --shrines=on).
const SHRINES_ON := {"kinds": ["haste", "might"]}
## Over every mode's shrines (its own, or SHRINES_ON): ready soon, quick to claim, drawing
## the CPU from anywhere, so a short fuzz claims some.
const SHRINES_SOON := {"first_seconds": 8, "claim_seconds": 1, "cooldown_seconds": 15, "cpu_range": 4000, "cpu_engaged": 0}
## On top of the hazards in every mode: the Glass cannon mutator (data/rules/mutators.json),
## so knockouts (and the respawns, rounds, tags and crowns behind them) come within a short run.
const GLASS := {"damage_mult": 1.5}
const NORMAL := 1  # Normal CPUs (never Rage)
## Seeds a mode may add past the ones asked for while a wanted event hasn't happened yet.
const EXTRA_SEEDS := 2


func _long() -> bool:
	return OS.get_environment("TEST_FUZZ_LONG") not in ["", "0"]


func _seeds() -> int:
	return 10 if _long() else 1


func _scale() -> int:
	return 10 if _long() else 1


## Every mutator in data/rules/mutators.json stacked (Chaos Cup's table, all of it).
func _all_mutators() -> Dictionary:
	var f := FileAccess.open("res://data/rules/mutators.json", FileAccess.READ)
	var table: Dictionary = JSON.parse_string(f.get_as_text())
	var keys: Array = table.keys()
	keys.sort()
	var m := {}
	for k in keys:
		if String(k).begins_with("_"):
			continue
		MatchSim.merge_mutator(m, table[k])
	return m


## Brings the hazards forward so a short match (a team wiped in 30 s) still sees every one:
## the first warnings at 3, 5, 7 and 9 s, then every HAZARD_EVERY s at most. Only the
## schedule moves; the definitions are copies, never the shared table.
const HAZARD_EVERY := 14


func _hurry_hazards(sim: MatchSim) -> void:
	for k in sim.hazards.size():
		var st: Dictionary = sim.hazards[k]
		var id := String(st["id"])
		var d: Dictionary = (sim.hazard_defs[id] as Dictionary).duplicate(true)
		d["every_seconds"] = mini(int(d.get("every_seconds", 30)), HAZARD_EVERY)
		sim.hazard_defs[id] = d
		st["next"] = Hazards.ticks_of(3 + 2 * k)


func _fighters(s: int, n: int) -> Array:
	var out: Array = []
	for k in n:
		out.append(MatchFactory.FIGHTERS[(s * 5 + k * 3) % MatchFactory.FIGHTERS.size()])
	return out


## Builds one mode's match exactly the same way every call. Returns [game, over_phase].
func _build(cfg: Dictionary, s: int) -> Array:
	var kind := String(cfg["kind"])
	var n := int(cfg["size"])
	var hz := GLASS.duplicate()
	hz["damage_mult"] = float(cfg.get("glass", hz["damage_mult"]))  # (an entry may hit harder still)
	hz["hazards"] = HAZARDS.duplicate()
	match kind:
		"duel":
			var ids := _fighters(s, n * 2)
			var teams := [ids.slice(0, n), ids.slice(n)]
			var d := DuelSim.new(teams, DuelSim.rules_for(teams))
			d.sim.apply_mutators(hz, s)
			_hurry_hazards(d.sim)
			if d.rounds_to_win() > 1:
				d._fresh = d.snapshot()  # every round starts from the hazards' start too
			return [d, DuelSim.Phase.OVER]
		"team":
			var rid := String(cfg.get("rules", ""))
			var rules := TeamSim.load_rules() if rid == "" else TeamSim.rules_by_id(rid)
			if not rules.has("shrines"):
				rules["shrines"] = SHRINES_ON.duplicate(true)
			if not rules.has("ctf"):  # (Capture the Flag's CPUs keep their own shrine plan)
				(rules["shrines"] as Dictionary).merge(SHRINES_SOON, true)
			rules.merge(cfg.get("set", {}), true)  # (test tuning so objectives come sooner)
			var ids := _fighters(s, n * 2)
			var t := TeamSim.new([ids.slice(0, n), ids.slice(n)], n, rules, s)
			t.sim.apply_mutators(hz, s)  # (the game: main.gd _new_sim, Arena options > Hazards)
			_hurry_hazards(t.sim)
			return [t, TeamSim.Phase.OVER]
		_:
			var muts := _all_mutators() if bool(cfg.get("chaos", false)) else hz
			var rules := BrawlSim.load_rules()
			(rules["shrines"] as Dictionary).merge(SHRINES_SOON, true)
			var b := BrawlSim.new(_fighters(s, n), rules, muts, s)
			_hurry_hazards(b.sim)
			return [b, BrawlSim.Phase.OVER]


## The slots that mash random input (the rest are Normal CPUs): one, and one on the other
## side too in a team of three or more (unless the mode asks for one: "mashers": 1).
func _random_slots(cfg: Dictionary, s: int, slots: int) -> Array:
	var n := int(cfg["size"])
	if String(cfg["kind"]) != "team" or n < 3 or int(cfg.get("mashers", 2)) < 2:
		return [s % slots]
	return [s % n, n + (s + 1) % n]


func _fuzz(cfg: Dictionary) -> void:
	var counts := {}
	var started := Time.get_ticks_msec()
	var rollbacks := 0
	var ticks := 0
	var s := 1
	# The seeds asked for, then (if some wanted event hasn't happened yet) up to EXTRA_SEEDS
	# more, so a small change in how a match plays doesn't leave the fuzz short of coverage.
	while s <= _seeds() or (s <= _seeds() + EXTRA_SEEDS and not _missing(cfg, counts).is_empty()):
		var r := _run(cfg, s, int(cfg["ticks"]) * _scale(), counts)
		if r < 0:
			return  # (failed: the failure says where)
		rollbacks += r
		ticks += int(cfg["ticks"]) * _scale()
		s += 1
	var ms := Time.get_ticks_msec() - started
	if OS.get_environment("TEST_QUIET") in ["", "0"]:
		var shown: Array = []
		for k in cfg["want"]:
			shown.append("%s %d" % [k, int(counts.get(k, 0))])
		for h in HAZARDS:
			shown.append("%s %d" % [h, int(counts.get("hz:" + h, 0))])
		print("    fuzz %s: %d seeds, %d ticks at most, %d rollbacks, %d ms; %s" % [cfg["name"], s - 1, ticks, rollbacks, ms,
			", ".join(shown)])
	for k in _missing(cfg, counts):
		fail("%s: the fuzz never reached a \"%s\" event in %d seeds (coverage: retune the mode's ticks or rules here)" % [
			cfg["name"], k.trim_prefix("hz:"), s - 1])


## The wanted events (and "hz:<id>" hazard strikes) not counted yet.
func _missing(cfg: Dictionary, counts: Dictionary) -> Array:
	var out: Array = []
	for k in cfg["want"]:
		if int(counts.get(k, 0)) <= 0:
			out.append(String(k))
	for h in HAZARDS:
		if int(counts.get("hz:" + h, 0)) <= 0:
			out.append("hz:" + h)
	return out


## One seeded match: returns the number of rollbacks checked, or -1 on a mismatch.
func _run(cfg: Dictionary, s: int, n_ticks: int, counts: Dictionary) -> int:
	var built := _build(cfg, s)
	var game: Object = built[0]
	var over := int(built[1])
	var sim: MatchSim = game.sim
	var slots := sim.creatures.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * s + String(cfg["name"]).hash()
	var mashers := _random_slots(cfg, s, slots)
	var cpus: Array = []
	for i in slots:
		var cpu: CpuController = null
		if not (i in mashers):
			cpu = CpuController.new(i, NORMAL, 1000 * s + i)
			if game is DuelSim:
				cpu.duel = game
		cpus.append(cpu)
	var hold: Array = []
	var left: Array = []
	hold.resize(slots)
	hold.fill(0)
	left.resize(slots)
	left.fill(0)
	var inputs: Array[PackedInt32Array] = []
	var checks := {}  # tick -> the digest there, for the fresh replay
	var snap := {}
	var snap_t := -1
	var snap_digest := ""
	var back := 0
	var next_snap := rng.randi_range(30, 300)
	var rollbacks := 0
	var t := 0
	while t < n_ticks:
		if t == next_snap and snap_t < 0:
			snap = game.snapshot()
			snap_t = t
			snap_digest = game.state_digest()
			checks[t] = snap_digest
			# Mostly rollback-sized windows, sometimes a long one (through a respawn, a round...).
			back = rng.randi_range(1, 12) if rng.randf() < 0.7 else rng.randi_range(13, 240)
		var ins := PackedInt32Array()
		for i in slots:
			if cpus[i] != null:
				ins.append((cpus[i] as CpuController).bits(sim))
			else:
				if int(left[i]) <= 0:
					# Half the time every bit a coin flip, else sparser (a quarter), so the
					# masher is also caught standing, walking and guarding (a tag, a shrine).
					hold[i] = rng.randi() & SimDefs.IN_EVERYTHING
					if rng.randf() < 0.5:
						hold[i] = int(hold[i]) & rng.randi()
					left[i] = rng.randi_range(1, 20)
				left[i] = int(left[i]) - 1
				ins.append(int(hold[i]))
		inputs.append(ins)
		game.step(ins)
		t += 1
		for e in sim.events:
			var ty := String(e["type"])
			counts[ty] = int(counts.get(ty, 0)) + 1
			if ty == "hazard_strike":
				var key := "hz:" + String(e.get("hazard", ""))
				counts[key] = int(counts.get(key, 0)) + 1
		var done := int(game.phase) == over
		if snap_t >= 0 and (t - snap_t >= back or done or t >= n_ticks):
			var want: String = game.state_digest()
			for again in 2:
				game.restore(snap)
				if game.state_digest() != snap_digest:
					fail("%s seed %d: restore() at tick %d (pass %d) does not give back the state snapshotted there" % [
						cfg["name"], s, snap_t, again + 1])
					return -1
				for k in range(snap_t, t):
					game.step(inputs[k])
				if game.state_digest() != want:
					fail("%s seed %d: re-stepping ticks %d-%d after restore() (pass %d) gives a different state" % [
						cfg["name"], s, snap_t, t, again + 1])
					return -1
			rollbacks += 1
			snap_t = -1
			snap = {}
			next_snap = t + rng.randi_range(20, 400)
		if done:
			break
	checks[t] = game.state_digest()
	# The same match again from tick 0, the same inputs, no rollbacks.
	var fresh: Object = _build(cfg, s)[0]
	for k in inputs.size():
		if checks.has(k) and fresh.state_digest() != checks[k]:
			fail("%s seed %d: a fresh replay differs from the rolled-back match at tick %d (state missed by snapshot/restore before it)" % [
				cfg["name"], s, k])
			return -1
		fresh.step(inputs[k])
	if fresh.state_digest() != checks[inputs.size()]:
		fail("%s seed %d: a fresh replay differs from the rolled-back match at the end (tick %d)" % [cfg["name"], s, inputs.size()])
		return -1
	return rollbacks


func test_1v1_rounds() -> void:
	_fuzz({"name": "1v1 rounds", "kind": "duel", "size": 1, "ticks": 3000, "want": ["ko", "round_start"]})


func test_duel_3v3_tag() -> void:
	# "glass" 2.5 since the Oct 29 Normal nerf: a Normal CPU against a masher took more than the
	# duel's 180 s to a first KO at the shared 1.5 (the long soak saw 8 KOs in 10 full matches).
	# 3.0 since the Oct 29 Craglash tune (a sturdier tank lead outlasted the 6000 ticks at 2.5).
	_fuzz({"name": "Duel 3v3", "kind": "duel", "size": 3, "ticks": 6000, "glass": 3.0, "want": ["ko", "enter"]})


func test_team_2v2() -> void:
	_fuzz({"name": "Team 2v2", "kind": "team", "size": 2, "ticks": 2400, "want": ["ko", "shrine"]})


func test_team_3v3() -> void:
	_fuzz({"name": "Team 3v3", "kind": "team", "size": 3, "ticks": 2400, "want": ["ko", "shrine"]})


func test_team_deathmatch() -> void:
	_fuzz({"name": "Team Deathmatch 3v3", "kind": "team", "rules": "deathmatch", "size": 3, "ticks": 2400,
		"want": ["ko", "respawn", "shrine"]})


func test_sinkhole() -> void:
	_fuzz({"name": "Sinkhole 3v3", "kind": "team", "rules": "sinkhole", "size": 3, "ticks": 2400,
		"want": ["sink", "shrine"]})


func test_king_of_the_crater() -> void:
	_fuzz({"name": "King of the Crater 2v2", "kind": "team", "rules": "crater", "size": 2, "ticks": 2400,
		"want": ["zone_move", "shrine", "shrine_boost", "respawn"]})


func test_brawl_4_crown() -> void:
	_fuzz({"name": "Brawl 4", "kind": "brawl", "size": 4, "ticks": 2400, "want": ["ko", "crown", "shrine"]})


func test_chaos_cup() -> void:
	_fuzz({"name": "Chaos Cup", "kind": "brawl", "size": 4, "chaos": true, "ticks": 2400, "want": ["ko", "crown", "shrine"]})


func test_caravan() -> void:
	_fuzz({"name": "Caravan 2v2", "kind": "team", "rules": "caravan", "size": 2, "ticks": 2400,
		"set": {"push_speed": 0.8, "checkpoints": [0.12, 0.3]}, "want": ["checkpoint", "rockslide", "shrine"]})


func test_ctf_3v3() -> void:
	_fuzz({"name": "Capture the Flag 3v3", "kind": "team", "rules": "ctf", "size": 3, "ticks": 2400, "mashers": 1, "set": {"carry_slow": 1.0, "defenders": 0},
		"want": ["flag_take", "capture"]})


func test_ctf_4v4() -> void:
	_fuzz({"name": "Capture the Flag 4v4", "kind": "team", "rules": "ctf", "size": 4, "ticks": 2400, "mashers": 1, "set": {"carry_slow": 1.0},
		"want": ["flag_take", "capture", "respawn", "shrine"]})
