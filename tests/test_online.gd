extends TestCase
## Online play: two Netplay sessions talking over an in-memory link (with lag, jitter
## and loss) and over real UDP on this machine. Both machines must agree on every
## frame, and the session must set up, rematch, sync time, and end cleanly.

const TEAM_A := ["cairn"]
const TEAM_B := ["culvert"]


func _pair(lag := 0, jitter := 0, loss := 0.0) -> Array:
	var links := LoopLink.pair(lag, jitter, loss, 7)
	var host := Netplay.new()
	var guest := Netplay.new()
	host.host(0, TEAM_A, links[0])
	guest.join("loop", 0, TEAM_B, links[1])
	return [host, guest]


## Ticks both sides until `cond` holds. `inputs` gives each side's bits per tick.
func _run(nets: Array, ticks: int, cond: Callable = Callable(), inputs: Callable = Callable()) -> bool:
	for i in ticks:
		for side in 2:
			var bits := 0
			if inputs.is_valid():
				bits = int(inputs.call(side, i))
			(nets[side] as Netplay).tick(bits)
		if cond.is_valid() and cond.call():
			return true
	return not cond.is_valid()


func _playing(nets: Array) -> bool:
	return (nets[0] as Netplay).is_playing() and (nets[1] as Netplay).is_playing()


## Random held inputs, a new one every few ticks, from a seeded generator per side.
func _mash(seed_: int) -> Callable:
	var rngs := [RandomNumberGenerator.new(), RandomNumberGenerator.new()]
	rngs[0].seed = seed_
	rngs[1].seed = seed_ + 100
	var hold := [0, 0]
	return func(side: int, i: int) -> int:
		if i % 7 == 0:
			hold[side] = rngs[side].randi() & (SimDefs.IN_ALL & ~SimDefs.IN_TAG)
		return hold[side]


func test_handshake_starts_the_same_match_on_both_sides() -> void:
	var nets := _pair(2)
	assert_true(_run(nets, 200, func(): return _playing(nets)), "both sides start playing")
	var h: Netplay = nets[0]
	var g: Netplay = nets[1]
	assert_eq(h.game.teams, [TEAM_A, TEAM_B], "the host's teams:")
	assert_eq(g.game.teams, [TEAM_A, TEAM_B], "the guest's teams:")
	assert_eq(h.game.local_side, 0, "the host plays the left side:")
	assert_eq(g.game.local_side, 1, "the guest plays the right side:")
	assert_eq(h.game.input_delay, g.game.input_delay, "the same input delay:")
	assert_eq(h.game.duel.state_digest(), g.game.duel.state_digest(), "the same starting state:")


func test_a_laggy_lossy_match_stays_in_sync() -> void:
	var nets := _pair(4, 3, 0.15)
	_run(nets, 200, func(): return _playing(nets))
	_run(nets, 1500, Callable(), _mash(11))
	var h: OnlineMatch = (nets[0] as Netplay).game
	var g: OnlineMatch = (nets[1] as Netplay).game
	assert_eq(h.desync_frame, -1, "no desync on the host")
	assert_eq(g.desync_frame, -1, "no desync on the guest")
	assert_gt(float(h.digests_matched), 15.0, "fingerprints were compared all match long:")
	assert_gt(float(h.session.rollbacks), 0.0, "and the lag made it roll back")
	# Both confirmed the same inputs, and replaying them offline gives the same match.
	var ra := h.report()
	var rb := g.report()
	var n := mini((ra["frames"] as Array).size(), (rb["frames"] as Array).size())
	assert_gt(float(n), 1000.0, "most frames confirmed:")
	var offline := DuelSim.new(h.teams, DuelSim.rules_for(h.teams))
	for f in n:
		assert_eq(ra["frames"][f], rb["frames"][f], "frame %d inputs:" % f)
		if ra["frames"][f] != rb["frames"][f]:
			break
		offline.step(PackedInt32Array(ra["frames"][f]))
	var online := DuelSim.new(h.teams, DuelSim.rules_for(h.teams))
	for f in n:
		online.step(PackedInt32Array(rb["frames"][f]))
	assert_eq(offline.state_digest(), online.state_digest(), "replays of both logs agree:")


func test_a_desync_is_caught() -> void:
	var nets := _pair(1)
	_run(nets, 200, func(): return _playing(nets))
	_run(nets, 150, Callable(), _mash(3))
	# Something only one machine did (a bug in waiting): its fighter loses health.
	var g: OnlineMatch = (nets[1] as Netplay).game
	g.duel.active_creature(0).hp -= 5.0
	_run(nets, 400, Callable(), _mash(4))
	assert_gt(float((nets[0] as Netplay).game.desync_frame), 0.0, "the host notices")
	assert_gt(float(g.desync_frame), 0.0, "and so does the guest")


func test_a_slower_machine_is_waited_for() -> void:
	var nets := _pair(2)
	_run(nets, 200, func(): return _playing(nets))
	# The guest's machine misses one frame in eight (a slow PC); the host should hold
	# back now and then instead of racing ahead into deep rollbacks.
	var mash := _mash(5)
	for i in 1600:
		(nets[0] as Netplay).tick(mash.call(0, i))
		if i % 8 != 0:
			(nets[1] as Netplay).tick(mash.call(1, i))
	var h: OnlineMatch = (nets[0] as Netplay).game
	var g: OnlineMatch = (nets[1] as Netplay).game
	assert_gt(float(h.sync_waits), 20.0, "the host waits for the slower guest:")
	assert_lt(absf(float(h.session.frame - g.session.frame)), 8.0, "and they stay close:")
	assert_lt(float(h.session.max_rollback_seen), 9.0, "rollbacks stay short:")
	assert_eq(h.desync_frame, -1, "still in sync")


func test_rematch_starts_a_fresh_match_when_both_ask() -> void:
	var nets := _pair(2)
	_run(nets, 200, func(): return _playing(nets))
	_run(nets, 60, Callable(), _mash(8))
	var first: OnlineMatch = (nets[0] as Netplay).game
	(nets[0] as Netplay).request_rematch()
	_run(nets, 30)
	assert_true((nets[0] as Netplay).game == first, "one ask isn't enough")
	(nets[1] as Netplay).request_rematch()
	_run(nets, 30, func(): return (nets[0] as Netplay).game != first and (nets[1] as Netplay).game.id == (nets[0] as Netplay).game.id)
	var h: OnlineMatch = (nets[0] as Netplay).game
	var g: OnlineMatch = (nets[1] as Netplay).game
	assert_eq(h.id, 2, "a second match:")
	assert_eq(g.id, 2, "on both sides:")
	_run(nets, 300, Callable(), _mash(9))
	assert_eq(h.desync_frame, -1, "the rematch is in sync too")


func test_leaving_ends_the_session_for_the_other_player() -> void:
	var nets := _pair(1)
	_run(nets, 200, func(): return _playing(nets))
	(nets[1] as Netplay).leave()
	_run(nets, 10)
	assert_eq((nets[0] as Netplay).phase, Netplay.Phase.ENDED, "the host's session ends:")
	assert_true((nets[0] as Netplay).error.contains("left"), "and says why: " + (nets[0] as Netplay).error)


func test_a_different_build_is_refused() -> void:
	var links := LoopLink.pair()
	var host := Netplay.new()
	host.host(0, TEAM_A, links[0])
	links[1].send({"t": "hello", "v": Netplay.NET_VERSION, "data": "not-the-same", "team": TEAM_B}, true)
	for i in 5:
		host.tick(0)
	assert_eq(host.phase, Netplay.Phase.ENDED, "the host refuses:")
	var got: Array = []
	for i in 3:
		got.append_array(links[1].poll())
	var refused := false
	for m in got:
		if String(m.get("t", "")) == "reject":
			refused = true
	assert_true(refused, "and tells the other side why")


func test_an_unknown_fighter_is_refused() -> void:
	var links := LoopLink.pair()
	var host := Netplay.new()
	host.host(0, TEAM_A, links[0])
	links[1].send({"t": "hello", "v": Netplay.NET_VERSION, "data": Netplay.data_hash(), "team": ["not_a_fighter"]}, true)
	for i in 5:
		host.tick(0)
	assert_eq(host.phase, Netplay.Phase.ENDED, "the host refuses:")


func test_garbage_packets_are_ignored() -> void:
	assert_eq(NetLink.decode(PackedByteArray([1, 2, 3])), null, "too short:")
	assert_eq(NetLink.decode(var_to_bytes([1, 2, 3])), null, "not a dictionary:")
	var d = NetLink.decode(NetLink.encode({"t": "in"}))
	assert_eq(String(d["t"]), "in", "a real message decodes:")


func test_events_show_once_through_rollbacks() -> void:
	var nets := _pair(5, 2, 0.1)
	_run(nets, 200, func(): return _playing(nets))
	var mash := _mash(21)
	var seen := {}
	var dupes := 0
	for i in 900:
		for side in 2:
			(nets[side] as Netplay).tick(mash.call(side, i))
		for e in (nets[0] as Netplay).game.events:
			var key := "%d:%s:%s:%s" % [int(e["tick"]), String(e["type"]), str(e.get("attacker", "")), str(e.get("target", ""))]
			if seen.has(key):
				dupes += 1
			seen[key] = true
	assert_gt(float(seen.size()), 20.0, "plenty of events reached the views:")
	assert_eq(dupes, 0, "none of them twice:")


func test_over_real_udp_on_this_machine() -> void:
	var port := 20000 + (Time.get_ticks_usec() % 20000)
	var host := Netplay.new()
	var guest := Netplay.new()
	host.ping_wait_ms = 0  # both ends tick in this one loop: the host can't wait on a pong
	assert_true(host.host(port, TEAM_A), "host on UDP %d: %s" % [port, host.error])
	assert_true(guest.join("127.0.0.1", port, TEAM_B), "join: " + guest.error)
	var nets := [host, guest]
	var started := false
	for i in 600:
		host.tick(0)
		guest.tick(0)
		if _playing(nets):
			started = true
			break
		OS.delay_usec(2000)
	assert_true(started, "connected and started over UDP (%s / %s)" % [host.status, guest.status])
	if not started:
		host.leave()
		guest.leave()
		return
	var mash := _mash(2)
	for i in 900:
		host.tick(mash.call(0, i))
		guest.tick(mash.call(1, i))
		OS.delay_usec(300)
	assert_eq(host.game.desync_frame, -1, "no desync over UDP")
	assert_gt(float(host.game.digests_matched), 8.0, "fingerprints compared over UDP:")
	assert_gt(float(host.game.session.frame), 800.0, "the match ran:")
	guest.leave()
	for i in 200:
		host.tick(0)
		if host.phase == Netplay.Phase.ENDED:
			break
		OS.delay_usec(2000)
	assert_eq(host.phase, Netplay.Phase.ENDED, "the host sees the guest leave:")
	host.leave()


func test_a_long_burst_of_lost_packets_is_recovered() -> void:
	var links := LoopLink.pair(2, 0, 0.0, 7)
	var host := Netplay.new()
	var guest := Netplay.new()
	host.host(0, TEAM_A, links[0])
	guest.join("loop", 0, TEAM_B, links[1])
	var nets := [host, guest]
	_run(nets, 200, func(): return _playing(nets))
	_run(nets, 120, Callable(), _mash(6))
	# Half a second where no input packet gets through either way: far more than the
	# few inputs each packet repeats.
	for l in links:
		(l as LoopLink).loss = 1.0
	_run(nets, 30, Callable(), _mash(7))
	for l in links:
		(l as LoopLink).loss = 0.0
	var before := host.game.session.frame
	_run(nets, 300, Callable(), _mash(8))
	assert_gt(float(host.game.session.frame - before), 250.0, "the match carries on afterwards:")
	assert_gt(float(guest.game.session.confirmed_frame()), float(before), "the lost inputs were sent again:")
	assert_eq(host.game.desync_frame, -1, "still in sync")


func test_a_join_that_never_gets_through_says_no_answer() -> void:
	var links := LoopLink.pair()
	(links[0] as LoopLink).close()  # the connection fails before it's made
	var n := Netplay.new()
	n.join("kevarena.example.net", 7777, ["cairn"], links[1])
	n.tick(0)
	assert_eq(n.phase, Netplay.Phase.ENDED, "it gives up")
	assert_true(n.error.begins_with("No answer from kevarena.example.net:7777"),
		"and says so, not that another player left: " + n.error)


func test_the_host_picks_the_arena_and_both_build_it() -> void:
	var links := LoopLink.pair(1, 0, 0.0, 7)
	var host := Netplay.new()
	var guest := Netplay.new()
	host.arena_id = "quarry"
	guest.arena_id = "greenhouse"  # the guest's wish doesn't count
	host.host(0, TEAM_A, links[0])
	guest.join("loop", 0, TEAM_B, links[1])
	var nets := [host, guest]
	assert_true(_run(nets, 200, func(): return _playing(nets)), "both sides start playing")
	assert_eq(host.game.duel.sim.arena_id, "quarry", "the host's arena:")
	assert_eq(guest.game.duel.sim.arena_id, "quarry", "on the guest too:")
	assert_eq(guest.arena_id, "quarry", "and the guest knows it:")
	assert_eq(host.game.duel.sim.terrain.count(TerrainGrid.WALL), 2 * 2 * 26, "with Quarry's walls:")
	_run(nets, 600, Callable(), _mash(3))
	assert_eq(host.game.desync_frame, -1, "no desync on a map with walls")
	assert_eq(MatchFactory.arena, ArenaMap.DEFAULT, "the menu's arena is left alone")
