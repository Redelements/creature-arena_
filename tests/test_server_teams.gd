extends TestCase
## Team battles online (2v2, 3v3) through the dedicated server: grouping by size and
## room, slots and sides, every player's machine and the referee staying in sync under
## lag, rematches, and a player leaving.

const FIGHTERS := ["cairn", "culvert", "sno", "barkley", "gillbert", "craglash"]


## A server and one player per entry of `sizes` (players per side each asks for),
## joined over in-memory links. `rooms[i]` puts player i in a room.
func _setup(sizes: Array, rooms: Array = [], lag := 0, jitter := 0, loss := 0.0) -> Array:
	var server := RelayServer.new()
	var nets: Array = []
	for i in sizes.size():
		var links := LoopLink.pair(lag, jitter, loss, 5 + i * 13)
		server.add_client(links[0], "test:%d" % i)
		var n := Netplay.new()
		n.team_size = int(sizes[i])
		if i < rooms.size():
			n.room = String(rooms[i])
		n.join("server", 0, [FIGHTERS[i % FIGHTERS.size()]], links[1])
		nets.append(n)
	return [server, nets]


func _run(server: RelayServer, nets: Array, ticks: int, cond: Callable = Callable(), mash := -1) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(mash, 0)
	var hold: Array = []
	hold.resize(nets.size())
	hold.fill(0)
	for i in ticks:
		for k in nets.size():
			if mash >= 0 and (i + k) % 7 == 0:
				hold[k] = rng.randi() & (SimDefs.IN_ALL & ~SimDefs.IN_TAG)
			(nets[k] as Netplay).tick(int(hold[k]))
		server.tick()
		if cond.is_valid() and cond.call():
			return true
	return not cond.is_valid()


func _all_playing(nets: Array) -> bool:
	for n in nets:
		if not (n as Netplay).is_playing():
			return false
	return true


func test_four_players_asking_for_2v2_start_one_team_battle() -> void:
	var s := _setup([2, 2, 2, 2])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	assert_true(_run(server, nets, 300, func(): return _all_playing(nets)), "all four start")
	assert_eq(server.games.size(), 1, "one match on the server:")
	var slots := {}
	var per_side := [0, 0]
	for n: Netplay in nets:
		assert_eq(n.game.size, 2, "a 2v2:")
		assert_true(n.game.team != null, "a team battle, not a Duel")
		assert_eq(n.game.teams, (nets[0] as Netplay).game.teams, "everyone has the same teams:")
		assert_eq(n.game.input_delay, (nets[0] as Netplay).game.input_delay, "and the same delay:")
		slots[n.game.local_slot] = true
		per_side[n.game.local_side] += 1
		# Each plays their own fighter, in their own slot.
		var me: CreatureSim = n.game.team.sim.creatures[n.game.local_slot]
		assert_eq(String(me.def["id"]), String(n.my_team[0]), "your slot is your fighter:")
		assert_eq(me.team, n.game.local_side, "on your side:")
	assert_eq(slots.size(), 4, "four different slots:")
	assert_eq(per_side, [2, 2], "two a side:")


func test_three_asking_for_2v2_wait_and_say_how_many() -> void:
	var s := _setup([2, 2, 2])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	_run(server, nets, 200)
	assert_eq(server.games.size(), 0, "no match with three:")
	var a: Netplay = nets[0]
	assert_true(a.status.contains("3 of 4"), "they're told how many are here: " + a.status)


func test_quick_match_keeps_sizes_apart() -> void:
	var s := _setup([1, 2, 1, 2])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	_run(server, nets, 300, func(): return (nets[0] as Netplay).is_playing() and (nets[2] as Netplay).is_playing())
	assert_true((nets[0] as Netplay).is_playing() and (nets[2] as Netplay).is_playing(), "the two 1v1 players play")
	assert_eq((nets[0] as Netplay).game.size, 1, "a 1v1:")
	assert_false((nets[1] as Netplay).is_playing(), "the 2v2 players keep waiting")
	assert_false((nets[3] as Netplay).is_playing(), "")


func test_a_room_takes_its_size_from_whoever_made_it() -> void:
	# The friend who made the room asked for 3v3; the others join by code (size 0).
	var s := _setup([3, 0, 0, 0, 0, 0], ["kx7p", "kx7p", "kx7p", "kx7p", "kx7p", "kx7p"])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	assert_true(_run(server, nets, 400, func(): return _all_playing(nets)), "all six start")
	assert_eq((nets[0] as Netplay).game.size, 3, "a 3v3:")
	assert_eq((nets[0] as Netplay).game.local_side, 0, "the room's maker on the left")
	assert_eq((nets[1] as Netplay).game.local_side, 1, "the first friend in faces them")


func test_a_laggy_3v3_stays_in_sync_and_the_referee_agrees() -> void:
	var s := _setup([3, 3, 3, 3, 3, 3], [], 3, 2, 0.1)
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	assert_true(_run(server, nets, 400, func(): return _all_playing(nets)), "all six start")
	_run(server, nets, 1200, Callable(), 17)
	for n: Netplay in nets:
		assert_eq(n.game.desync_frame, -1, "no desync for slot %d" % n.game.local_slot)
		assert_gt(float(n.game.digests_matched), 20.0, "slot %d compared fingerprints:" % n.game.local_slot)
	var ref: Referee = (server.games[0] as RelayServer.Game).referee
	assert_eq(ref.desync, [-1, -1, -1, -1, -1, -1], "the referee agrees with everyone:")
	assert_gt(float(ref.frame), 1000.0, "its copy kept up:")
	# Everyone's match was in exactly the same state at the same frame.
	var at := OnlineMatch.DIGEST_EVERY * 10
	var d0 := String((nets[0] as Netplay).game.final_digests.get(at, ""))
	assert_true(d0 != "", "a fingerprint at frame %d" % at)
	for n: Netplay in nets:
		assert_eq(String(n.game.final_digests.get(at, "")), d0, "slot %d at frame %d:" % [n.game.local_slot, at])


func test_rematch_starts_when_everyone_asks() -> void:
	var s := _setup([2, 2, 2, 2])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	_run(server, nets, 300, func(): return _all_playing(nets))
	var first: OnlineMatch = (nets[0] as Netplay).game
	for k in 3:
		first = (nets[0] as Netplay).game
		(nets[k] as Netplay).game.team.phase = TeamSim.Phase.OVER  # skip to the end
		(nets[k] as Netplay).request_rematch()
	_run(server, nets, 60)
	assert_eq((nets[0] as Netplay).game, first, "three of four asking isn't enough")
	assert_true((nets[3] as Netplay).rematch_remote, "the fourth hears the others want one")
	(nets[3] as Netplay).request_rematch()
	_run(server, nets, 60, func(): return (nets[0] as Netplay).game != first)
	assert_true((nets[0] as Netplay).game != first, "all four asked: a new match")
	assert_eq((nets[0] as Netplay).game.id, 2, "match 2:")


func test_one_player_leaving_ends_it_for_everyone() -> void:
	var s := _setup([2, 2, 2, 2])
	var server: RelayServer = s[0]
	var nets: Array = s[1]
	_run(server, nets, 300, func(): return _all_playing(nets))
	(nets[2] as Netplay).leave()
	_run(server, nets, 60)
	for k in [0, 1, 3]:
		var n: Netplay = nets[k]
		assert_eq(n.phase, Netplay.Phase.ENDED, "player %d's session ended:" % k)
		assert_eq(n.error, "A player left the match", "and says why:")
	assert_eq(server.games.size(), 0, "the server dropped the match:")
	assert_eq(server.player_count(), 0, "and everyone in it:")
