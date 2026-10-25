class_name DedicatedServer
extends Node
## The game run as a dedicated server: no window, no sound, just the network.
##
##   CreatureArena.x86_64 --headless -- --server[=PORT] [--max-players=N] [--net-delay=N]
##       [--cpu-fill=SECONDS] [--room-fill=SECONDS] [--cpu-level=0..3] [--ready=SECONDS]
##       [--max-per-ip=N] [--ranked-same-ip] [--reset-player=ID]
##
## --max-per-ip caps connections from one address (default 6, 0: no limit).
## --ranked-same-ip lets two games behind one address play each other ranked (a LAN
## party; off by default, so nobody farms rating against themselves).
## --reset-player=ID forgets the secret bound to that player id in ratings.json (they
## lost their settings or moved computers: their next ranked game or Daily binds the
## new one, rating and scores kept), then exits without serving. Stop the server first.
## Team battles (2v2, 3v3) that have waited --cpu-fill seconds in Quick match (default
## 20) or --room-fill in a room (default 45) start with CPUs in the empty slots (0:
## never); --cpu-level is how well they play (0 Easy, 1 Normal, 2 Hard, 3 Rage).
## --ready is how long players have to accept a match found (default 15).
##
## Players pick "Online" > Join and type the server's address (add /room to meet a
## friend there). Everything it does is printed, one line per event, for the console
## or the system log (journalctl). Ctrl+C or `systemctl stop` ends it at once (Godot
## doesn't hand scripts those signals): players in a match see the connection drop
## within EnetLink.TIMEOUT_MS, so restart it between matches (the log shows when).

const STATUS_EVERY_MS := 10 * 60 * 1000
## Each loop sleeps this long (Godot's low-processor sleep): about a thousand loops a
## second, so a packet waits at most a millisecond to be relayed, at a few percent of
## one CPU core when idle.
const LOOP_SLEEP_USEC := 1000
## Connections at once from one address (--max-per-ip; 0: no limit): a household behind
## one router can still bring a 2 v 2 and spectators.
const DEFAULT_MAX_PER_IP := 6

var port := Netplay.DEFAULT_PORT
var hub := EnetHub.new()
var relay := RelayServer.new()
## Answers players on the server's own network who look for it (see ServerBeacon).
var beacon := ServerBeacon.new()
var _status_ms := 0
var _stopping := false
var _reset_ids: Array = []  ## --reset-player: forget these ids' keys, then exit


## Reads --server[=PORT], --max-players=N and --net-delay=N. Returns false if the
## command line doesn't ask for a server.
func configure(args: PackedStringArray) -> bool:
	var wanted := false
	relay.save_replays = true  # every match's replay, for the Replay theater
	relay.ratings.persist = true  # ranked ratings and daily scores, in user://ratings.json
	relay.realtime = true  # the limits run on the wall clock (the referee never runs ahead of it)
	relay.max_per_ip = DEFAULT_MAX_PER_IP
	for a in args:
		if a == "--server":
			wanted = true
		elif a.begins_with("--server="):
			wanted = true
			port = int(a.get_slice("=", 1))
		elif a.begins_with("--max-players="):
			relay.max_players = clampi(int(a.get_slice("=", 1)), 2, 1000)
		elif a.begins_with("--net-delay="):
			relay.forced_delay = clampi(int(a.get_slice("=", 1)), 0, 8)
		elif a.begins_with("--cpu-fill="):
			relay.cpu_fill_ms = maxi(0, int(a.get_slice("=", 1))) * 1000
		elif a.begins_with("--room-fill="):
			relay.room_fill_ms = maxi(0, int(a.get_slice("=", 1))) * 1000
		elif a.begins_with("--cpu-level="):
			relay.cpu_level = clampi(int(a.get_slice("=", 1)), 0, CpuController.LEVELS.size() - 1)
		elif a.begins_with("--ready="):
			relay.ready_ms = clampi(int(a.get_slice("=", 1)), 3, 120) * 1000
		elif a.begins_with("--max-per-ip="):
			relay.max_per_ip = clampi(int(a.get_slice("=", 1)), 0, 1000)
		elif a == "--ranked-same-ip":
			relay.ranked_same_ip = true
		elif a.begins_with("--reset-player="):
			_reset_ids.append(a.get_slice("=", 1).strip_edges().to_lower())
	if port <= 0 or port > 65535:
		port = Netplay.DEFAULT_PORT
	return wanted


func _ready() -> void:
	relay.on_log = _print
	if not _reset_ids.is_empty():
		for id in _reset_ids:
			if relay.ratings.reset_key(id):
				_print("player %s reset: their next ranked game or Daily binds a new secret" % id)
			else:
				_print("player %s has no secret bound in %s: nothing to reset" % [id, relay.ratings.path])
		_stopping = true
		get_tree().quit()
		return
	# Headless mode's own idle sleep is about 7 ms a loop, which would hold every packet
	# back that long; a 1 ms sleep keeps the relay quick and the CPU nearly idle.
	Engine.max_fps = 0
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = LOOP_SLEEP_USEC
	# Allow a few connections beyond the limit, so a full server can say it's full.
	if hub.listen(port, relay.max_players + 4) != OK:
		printerr(_stamp() + hub.error)
		get_tree().quit(1)
		return
	_print("Creature Arena server on UDP port %d (protocol %d, game data %s), up to %d players" % [
		port, Netplay.NET_VERSION, Netplay.data_hash(), relay.max_players])
	var addrs := Netplay.local_addresses()
	if not addrs.is_empty():
		_print("players on this network join %s:%d" % [addrs[0], port])
	if beacon.listen(port):
		_print("games on this network find the server by itself (UDP port %d; allow it in the firewall)" % beacon.port)
	else:
		_print(beacon.error + ": players here must join by address")
	_status_ms = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if _stopping:
		return
	for link in hub.poll():
		relay.add_client(link, (link as EnetHub.PeerLink).address)
	relay.tick()
	hub.flush()
	beacon.poll()
	var now := Time.get_ticks_msec()
	if now - _status_ms >= STATUS_EVERY_MS:
		_status_ms = now
		_print("%d players connected, %d matches running, %d finished so far" % [relay.player_count(),
			relay.games.size(), relay.matches_finished])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop()


## Says goodbye to every player and closes the port.
func stop() -> void:
	if _stopping:
		return
	_stopping = true
	relay.shutdown()
	hub.close()
	beacon.close()
	_print("server stopped")


func _print(s: String) -> void:
	print(_stamp() + s)


static func _stamp() -> String:
	return "[%s] " % Time.get_datetime_string_from_system(false, true)
