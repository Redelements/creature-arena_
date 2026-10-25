extends TestCase
## The dedicated server under hostile clients: random and mutated messages from
## connections in every state (never said hello, waiting, watching, sending a Daily
## score, seated in a CPU-filled room match), random bytes into the decoder, while an
## honest 1v1 and an honest spectator play on through the same server. Driven exactly
## as DedicatedServer does (RelayServer.add_client + tick()), over in-memory links that
## encode and decode every message as the wire does. Seeded, so a failure replays.
##
## It pins: no script or engine errors (the runner counts them), no server loop over
## TICK_BUDGET_MS, bounded server and referee state, the referee never ahead of the
## match's clock, and the honest match unharmed: the referee's rows are exactly what the
## honest players confirmed, nobody desyncs, the spectator agrees, and it finishes with
## the same winner everywhere.
##
## Longer local run: FUZZ_TICKS=20000 FUZZ_SEEDS=10 (defaults 3000 and 3: about 90k
## hostile messages, HOSTILE_PER_TICK a tick).

const HOSTILE_PER_TICK := 10
## The most one server loop may take. A loop is about a millisecond on the real server;
## this is generous for slow CI machines and a debug build.
const TICK_BUDGET_MS := 100
## How long an honest match may take to finish once the fuzzing stops.
const FINISH_TICKS := 20000

## A hostile connection: what it does, its end of the link, what it learned.
class Hostile:
	var role := ""  ## "silent", "lobby", "watch", "submit", "seat"
	var link: LoopLink
	var n := 0  ## the match number it last heard in "start"
	var sent_bytes := 0
	var got_bytes := 0
	var reconnects := 0


var rng := RandomNumberGenerator.new()
var server: RelayServer
var hostiles: Array = []
var corpus: Array = []  ## real messages honest clients sent, to mutate
var sent := 0
var worst_tick_ms := 0
var server_us := 0  ## time spent in server.tick(), honest clients and the hostiles
var honest_us := 0
var hostile_us := 0


func _ticks() -> int:
	var v := OS.get_environment("FUZZ_TICKS")
	return int(v) if v.is_valid_int() else 3000


func _seeds() -> int:
	var v := OS.get_environment("FUZZ_SEEDS")
	return int(v) if v.is_valid_int() else 3


func _hello(extra := {}) -> Dictionary:
	var h := {"t": "hello", "v": Netplay.NET_VERSION, "data": Netplay.data_hash(),
		"team": [MatchFactory.FIGHTERS[rng.randi_range(0, MatchFactory.FIGHTERS.size() - 1)]]}
	h.merge(extra, true)
	return h


func _connect(h: Hostile) -> void:
	var links := LoopLink.pair(0, 0, 0.0, rng.randi())
	server.add_client(links[0], "fuzz%d:%d" % [hostiles.find(h), h.reconnects])
	h.link = links[1]
	h.reconnects += 1
	h.n = 0
	match h.role:
		"lobby":
			_send(h, _hello())
		"watch":
			_send(h, _hello({"watch": true}))
		"submit":
			_send(h, _hello({"submit": true, "id": "%016x" % rng.randi(), "name": "fuzz"}))
		"seat":
			_send(h, _hello({"room": "fz", "size": 2}))


## Connections whose traffic is weighed (in or out of a match, the rest hear its inputs).
func _counted(h: Hostile) -> bool:
	return h.role != "watch" and h.role != "seat"


func _send(h: Hostile, m: Dictionary, reliable := true) -> void:
	if _counted(h):
		h.sent_bytes += NetLink.encode(m).size()
	h.link.send(m, reliable)
	sent += 1


# ------------------------------------------------------------------ values

var int_pool: Array = []


## Edge values, and frames around where the first match's referee is (set each tick).
func _set_int_pool() -> void:
	var f := 0
	if not server.games.is_empty():
		f = ((server.games[0] as RelayServer.Game).referee as Referee).frame
	int_pool = [-1, 0, 1, 2, 599, 600, 601, 2147483647, -2147483648, -9223372036854775807 - 1, 1 << 62,
		f, f + 1, f + 60, f + 119, f + 121, f + 600, f - 1, f - 240, 20261025, 99999999]


func _int() -> int:
	return int(int_pool[rng.randi_range(0, int_pool.size() - 1)]) if rng.randf() < 0.8 else rng.randi_range(-1000, 100000)


func _string() -> String:
	match rng.randi_range(0, 6):
		0:
			return ""
		1:
			return "x".repeat(rng.randi_range(1, 10000))
		2:
			return char(0x202e) + "evil" + char(0x200b) + char(1) + "\n\r"  # bidi, zero width, control
		3:
			return "caf" + char(0xe9) + " " + char(0x2603) + " " + char(0x1f600)
		4:
			return String(MatchFactory.FIGHTERS[rng.randi_range(0, MatchFactory.FIGHTERS.size() - 1)])
		5:
			return ["hello", "in", "dg", "pick", "daily", "board", "ctf", "team", "stadium", "fz"][rng.randi_range(0, 9)]
	return "%x" % rng.randi()


func _val(depth := 0) -> Variant:
	match rng.randi_range(0, 13 if depth < 3 else 6):
		0:
			return null
		1:
			return rng.randf() < 0.5
		2, 3:
			return _int()
		4:
			return [NAN, INF, -INF, -0.0, 0.5, 1e300][rng.randi_range(0, 5)]
		5:
			return _string()
		6:
			return Vector2(1, 2) if rng.randf() < 0.5 else Color(1, 0, 0)
		7:
			var a := PackedInt32Array()
			a.resize(rng.randi_range(0, 200) if rng.randf() < 0.9 else rng.randi_range(0, 5000))
			for i in mini(a.size(), 64):
				a[i] = _int()
			return a
		8:
			var a := PackedFloat32Array()
			a.resize(rng.randi_range(0, 9))
			return a
		9:
			var a := PackedByteArray()
			a.resize(rng.randi_range(0, 3000))
			return a
		10:
			var a: Array = []
			for i in rng.randi_range(0, 8 if rng.randf() < 0.9 else 3000):
				a.append(_val(depth + 1) if i < 8 else rng.randi())
			return a
		11:
			var d := {}
			for i in rng.randi_range(0, 5):
				d[_string() if rng.randf() < 0.7 else _int()] = _val(depth + 1)
			return d
		12:
			var deep: Array = []
			var cur := deep
			for i in rng.randi_range(1, 60):
				var nxt: Array = []
				cur.append(nxt)
				cur = nxt
			return deep
	return {"frames": _frames()}


## A Daily replay's frames: sometimes plausible, mostly not.
func _frames() -> Variant:
	match rng.randi_range(0, 5):
		0:
			return _int()
		1:
			return [_int()]
		2:
			var rows: Array = []
			for i in rng.randi_range(0, 400):
				rows.append([rng.randi() & 0xFFFF, rng.randi() & 0xFFFF])
			return rows
		3:
			var rows: Array = []
			for i in rng.randi_range(0, 50):
				rows.append([_val(2), _val(2), _val(2)])
			return rows
		4:
			return [PackedInt32Array([1, 2]), "x", null]
	return _val(1)


const TYPES := ["hello", "pong", "ping", "ready", "daily", "board", "in", "dg", "rematch", "next", "pick", "bye"]
const FIELDS := {
	"hello": ["v", "data", "team", "room", "size", "rules", "arena", "id", "name", "ranked", "submit", "watch"],
	"pong": ["n"], "ping": ["n"], "ready": [], "daily": ["date", "fighter", "replay"], "board": ["date"],
	"in": ["n", "first", "inputs", "ack", "f", "adv", "advs"], "dg": ["n", "f", "d"], "rematch": [], "next": [],
	"pick": ["team"], "bye": [],
}


func _message(h: Hostile) -> Dictionary:
	var roll := rng.randf()
	var m := {}
	if roll < 0.6 and not corpus.is_empty():
		# A real message with one to three fields changed (or gone).
		m = (corpus[rng.randi_range(0, corpus.size() - 1)] as Dictionary).duplicate(true)
		if m.has("n") and h.n > 0 and rng.randf() < 0.7:
			m["n"] = h.n  # aimed at the match it's in
		for k in rng.randi_range(1, 3):
			var keys: Array = m.keys()
			var t = m.get("t")
			var fields: Array = FIELDS.get(t, []) if t is String else []
			var key = fields[rng.randi_range(0, fields.size() - 1)] if not fields.is_empty() and rng.randf() < 0.7 \
				else (keys[rng.randi_range(0, keys.size() - 1)] if not keys.is_empty() else "x")
			if rng.randf() < 0.15:
				m.erase(key)
			else:
				m[key] = _val()
	elif roll < 0.9:
		var t: String = TYPES[rng.randi_range(0, TYPES.size() - 1)]
		if t == "bye" and rng.randf() < 0.8:
			t = "in"  # leaving is rare, or nobody would stay connected long
		m["t"] = t
		for k in FIELDS[t]:
			if rng.randf() < 0.7:
				m[k] = _val()
		if t == "daily" and rng.randf() < 0.5:
			m["replay"] = {"frames": _frames(), "setup": _val(1)}
		if (t == "in" or t == "dg") and rng.randf() < 0.6:
			m["n"] = h.n
			if t == "in":
				var ins := PackedInt32Array()
				ins.resize(rng.randi_range(1, 60))
				ins.fill(SimDefs.IN_LIGHT)
				m["inputs"] = ins
				m["first"] = _int()
	else:
		m = {"t": _val(1)} if rng.randf() < 0.7 else {"x": _val(1)}
	return m


## The hostile reads what came in (bytes counted) and plays along where it must: a
## seated hostile answers pings and the ready check, and remembers its match number.
func _hostile_read(h: Hostile) -> void:
	for m in h.link.poll():
		if m == null:
			continue
		if _counted(h):
			h.got_bytes += NetLink.encode(m).size()
		var t = m.get("t")
		if t == "start":
			h.n = int(m.get("n", 0))
		elif h.role == "seat" and t == "ping":
			_send(h, {"t": "pong", "n": m.get("n", 0)})
		elif h.role == "seat" and t == "found":
			_send(h, {"t": "ready"})


func _fuzz_tick() -> void:
	var t0 := Time.get_ticks_usec()
	_set_int_pool()
	for h: Hostile in hostiles:
		if h.link.status == NetLink.Status.CLOSED:
			_connect(h)  # dropped (or refused): it comes straight back
		_hostile_read(h)
	for k in HOSTILE_PER_TICK:
		var h: Hostile = hostiles[rng.randi_range(0, hostiles.size() - 1)]
		if h.link.status == NetLink.Status.CLOSED:
			continue
		if h.role == "silent":
			continue  # never says anything
		_send(h, _message(h), rng.randf() < 0.5)
		if h.role == "seat" and rng.randf() < 0.3:
			# The fast-forward: inputs as far ahead as the server will take.
			var ins := PackedInt32Array()
			ins.resize(60)
			var g: RelayServer.Game = _game_of("fz")
			if g != null:
				_send(h, {"t": "in", "n": h.n, "first": g.referee.frame + rng.randi_range(0, 600), "inputs": ins,
					"ack": -1, "f": 0, "adv": 0.0}, false)
	hostile_us += Time.get_ticks_usec() - t0


func _game_of(room: String) -> RelayServer.Game:
	for g: RelayServer.Game in server.games:
		if g.room == room:
			return g
	return null


## Ticks the honest clients and the server once; times the server.
func _step(honest: Array, cpus: Array) -> void:
	var t0 := Time.get_ticks_usec()
	for k in honest.size():
		var n: Netplay = honest[k]
		var bits := 0
		if k < cpus.size() and n.game != null:
			bits = (cpus[k] as CpuController).bits(n.game.game_sim().sim)
		n.tick(bits)
	var t := Time.get_ticks_usec()
	honest_us += t - t0
	server.tick()
	server_us += Time.get_ticks_usec() - t
	var ms := (Time.get_ticks_usec() - t) / 1000
	worst_tick_ms = maxi(worst_tick_ms, ms)


func _check_bounds(msg: String) -> bool:
	var ok := true
	ok = ok and server.clients.size() <= server.max_players
	ok = ok and server.games.size() <= maxi(1, server.clients.size())
	ok = ok and server.checks.size() <= maxi(1, server.clients.size())
	ok = ok and server.rooms.size() <= maxi(1, server.clients.size())
	ok = ok and server.log_lines.size() <= 200
	ok = ok and server.ratings.daily.size() <= 200
	for g: RelayServer.Game in server.games:
		var r: Referee = g.referee
		for p in r.players:
			ok = ok and (r._inputs[p] as Dictionary).size() <= Referee.MAX_AHEAD + Referee.MAX_PACKET_INPUTS + 8
			ok = ok and (r._theirs[p] as Dictionary).size() <= 65
		ok = ok and r._mine.size() <= 8
		ok = ok and r.frame <= server._clock_frame(g) + RelayServer.AHEAD_STEP_FRAMES + 1
		ok = ok and r.log.size() <= Referee.MAX_MATCH_FRAMES
	if not ok:
		assert_true(false, msg + ": server state out of bounds (clients %d, games %d, rooms %d)" % [
			server.clients.size(), server.games.size(), server.rooms.size()])
	return ok


func _run_seed(seed_: int) -> void:
	rng.seed = seed_
	hostiles.clear()
	corpus.clear()
	sent = 0
	worst_tick_ms = 0
	server_us = 0
	honest_us = 0
	hostile_us = 0
	server = RelayServer.new()
	server.rematch_locked_ms = 0
	server.room_fill_ms = 1  # the hostile's room fills with CPUs at once
	server.cpu_level = 0
	_set_int_pool()
	# The honest pair and a spectator.
	var la := LoopLink.pair(1, 0, 0.0, seed_ + 1)
	var lb := LoopLink.pair(1, 0, 0.0, seed_ + 2)
	var lw := LoopLink.pair(1, 0, 0.0, seed_ + 3)
	(la[0] as LoopLink).keep_heard = true  # what an honest client sends: the corpus
	server.add_client(la[0], "honest:1")
	server.add_client(lb[0], "honest:2")
	var a := Netplay.new()
	var b := Netplay.new()
	a.auto_ready = true
	b.auto_ready = true
	a.join("server", 0, ["cairn"], la[1])
	b.join("server", 0, ["sno"], lb[1])
	var cpus := [CpuController.new(0, 3, seed_), CpuController.new(1, 3, seed_ + 7)]
	var honest := [a, b]
	for i in 300:
		_step(honest, [])
		if a.is_playing() and b.is_playing():
			break
	assert_true(a.is_playing() and b.is_playing(), "seed %d: the honest pair starts" % seed_)
	cpus[0] = CpuController.new(a.game.local_slot, 3, seed_)
	cpus[1] = CpuController.new(b.game.local_slot, 3, seed_ + 7)
	server.add_client(lw[0], "honest:3")
	var w := Netplay.new()
	w.spectate("server", 0, "", lw[1])
	honest.append(w)
	for i in 60:
		_step(honest, cpus)
	assert_true(w.is_watching(), "seed %d: the spectator is on" % seed_)
	var g: RelayServer.Game = server.games[0]
	for m in (la[0] as LoopLink).heard:
		if m is Dictionary:
			corpus.append(m)
	corpus.append(_hello({"room": "x", "size": 2, "rules": "ctf", "arena": "stadium", "name": "n", "id": "abcdef0123456789"}))
	corpus.append({"t": "daily", "date": 20261025, "fighter": "cairn", "replay": {"frames": [[0, 0], [1, 1]]}})
	corpus.append({"t": "board", "date": 20261025})
	corpus.append({"t": "pick", "team": ["cairn"]})
	corpus.append({"t": "dg", "n": 1, "f": 60, "d": "abc"})
	(la[0] as LoopLink).keep_heard = false
	# The hostiles.
	for role in ["silent", "lobby", "lobby", "watch", "submit", "seat"]:
		var h := Hostile.new()
		h.role = role
		hostiles.append(h)
		_connect(h)
	var mem0 := OS.get_static_memory_usage()
	var ticks := _ticks()
	var t0 := Time.get_ticks_msec()
	for i in ticks:
		_fuzz_tick()
		_step(honest, cpus)
		if i % 50 == 0 and not _check_bounds("seed %d tick %d" % [seed_, i]):
			break
		if i % 500 == 250:
			# A burst: one of them floods (and is dropped for it).
			var h: Hostile = hostiles[1]
			if h.link.status != NetLink.Status.CLOSED:
				for k in RelayServer.MSG_BURST + 20:
					_send(h, {"t": "ping", "n": k}, true)
	var fuzz_ms := Time.get_ticks_msec() - t0
	print("    seed %d: server %d ms, honest clients %d ms, hostiles %d ms" % [seed_, server_us / 1000, honest_us / 1000,
		hostile_us / 1000])
	_check_bounds("seed %d end" % seed_)
	assert_true(worst_tick_ms <= TICK_BUDGET_MS, "seed %d: the slowest server loop took %d ms" % [seed_, worst_tick_ms])
	var grew := (OS.get_static_memory_usage() - mem0) / (1024 * 1024)
	assert_true(grew < 64, "seed %d: memory grew %d MB" % [seed_, grew])
	for h: Hostile in hostiles:
		if _counted(h):
			assert_true(h.got_bytes <= h.sent_bytes * 4 + 64 * 1024,
				"seed %d: a %s connection got %d bytes for %d sent" % [seed_, h.role, h.got_bytes, h.sent_bytes])
	# The honest match, unharmed: no desync anywhere, the referee's rows exactly what
	# the players confirmed (nobody else's inputs got in), the spectator agreeing.
	assert_true(server.games.has(g), "seed %d: the honest match is still on" % seed_)
	for i in FINISH_TICKS:
		if g.referee.winner != -2 and a.game.winner() != -2 and b.game.winner() != -2:
			break
		_step(honest, cpus)
	assert_eq(a.game.desync_frame, -1, "seed %d: no desync for A" % seed_)
	assert_eq(b.game.desync_frame, -1, "seed %d: no desync for B" % seed_)
	assert_eq(g.referee.desync, [-1, -1], "seed %d: the referee agrees with both:" % seed_)
	var checked := 0
	for f in mini(g.referee.log.size(), 100000):
		if a.game.input_log.has(f):
			if PackedInt32Array(a.game.input_log[f]) != (g.referee.log[f] as PackedInt32Array):
				assert_true(false, "seed %d: frame %d was refereed as %s but the players pressed %s" % [seed_, f,
					str(g.referee.log[f]), str(a.game.input_log[f])])
				break
			checked += 1
	assert_gt(float(checked), 1000.0, "seed %d: frames compared with the referee" % seed_)
	var at := -1
	for f in a.game.final_digests:
		if w.watch != null and w.watch.digest_at(int(f)) != "":
			at = maxi(at, int(f))
	assert_true(at > 0, "seed %d: the spectator shares a fingerprint frame" % seed_)
	if at > 0:
		assert_eq(w.watch.digest_at(at), String(a.game.final_digests[at]), "seed %d: the spectator agrees:" % seed_)
	assert_true(g.referee.winner != -2, "seed %d: the match finished" % seed_)
	assert_eq(a.game.winner(), g.referee.winner, "seed %d: A's winner is the referee's:" % seed_)
	assert_eq(b.game.winner(), g.referee.winner, "seed %d: B's winner is the referee's:" % seed_)
	print("    seed %d: %d hostile messages over %d ticks in %d ms, slowest server loop %d ms, %d reconnects, match over at frame %d" % [
		seed_, sent, ticks, fuzz_ms, worst_tick_ms, hostiles.reduce(func(s, h): return s + h.reconnects, 0),
		g.referee.finished_at])


func test_hostile_clients_never_break_the_server_or_an_honest_match() -> void:
	for s in _seeds():
		_run_seed(20261025 + s * 1009)


func test_random_and_mutated_bytes_decode_quietly() -> void:
	rng.seed = 77
	var real: Array = [
		NetLink.encode({"t": "in", "n": 3, "first": 10, "inputs": PackedInt32Array([1, 2, 3]), "ack": 2, "f": 9,
			"adv": 0.5, "advs": PackedFloat32Array([0.0, 1.0])}),
		NetLink.encode({"t": "hello", "v": 1, "data": "abc", "team": ["cairn"], "room": "kev", "watch": false}),
		NetLink.encode({"t": "start", "log": [PackedInt32Array([1, 2]), PackedInt32Array([3, 4])], "teams": [["a"], ["b"]]}),
		NetLink.encode({"t": "daily", "replay": {"frames": [[1, 2], [3, 4]], "setup": {"ids": ["cairn"]}}}),
	]
	for m in real:
		assert_true(NetLink.decode(m) is Dictionary, "a real message decodes")
	var worst := 0
	var dicts := 0
	var runs := 6000
	for i in runs:
		var b: PackedByteArray
		var kind := i % 4
		if kind == 0:
			b = PackedByteArray()
			b.resize(rng.randi_range(0, 65536) if rng.randf() < 0.1 else rng.randi_range(0, 512))
			for k in b.size():
				b[k] = rng.randi() & 255
			if b.size() >= 4 and rng.randf() < 0.7:
				b.encode_u32(0, TYPE_DICTIONARY)
		else:
			b = (real[rng.randi_range(0, real.size() - 1)] as PackedByteArray).duplicate()
			if kind == 1:
				for k in rng.randi_range(1, 4):
					b[rng.randi_range(0, b.size() - 1)] = rng.randi() & 255
			elif kind == 2:
				b = b.slice(0, rng.randi_range(0, b.size()))
			else:
				b.encode_u32(rng.randi_range(0, (b.size() - 4) / 4) * 4,
					[0x7FFFFFFF, 0xFFFFFFFF, 0x80000000, 1 << 20, rng.randi()][rng.randi_range(0, 4)])
		var t := Time.get_ticks_usec()
		var v = NetLink.decode(b)
		worst = maxi(worst, Time.get_ticks_usec() - t)
		if v != null:
			assert_true(v is Dictionary, "only Dictionaries come out")
			dicts += 1
	assert_true(worst < 50000, "no packet takes long to refuse: worst %d us" % worst)
	print("    %d packets decoded quietly (%d were Dictionaries), worst %d us" % [runs, dicts, worst])
