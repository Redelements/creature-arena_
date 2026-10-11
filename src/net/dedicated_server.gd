class_name DedicatedServer
extends Node
## The game run as a dedicated server: no window, no sound, just the network.
##
##   CreatureArena.x86_64 --headless -- --server[=PORT] [--max-players=N] [--net-delay=N]
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

var port := Netplay.DEFAULT_PORT
var hub := EnetHub.new()
var relay := RelayServer.new()
var _status_ms := 0
var _stopping := false


## Reads --server[=PORT], --max-players=N and --net-delay=N. Returns false if the
## command line doesn't ask for a server.
func configure(args: PackedStringArray) -> bool:
	var wanted := false
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
	if port <= 0 or port > 65535:
		port = Netplay.DEFAULT_PORT
	return wanted


func _ready() -> void:
	relay.on_log = _print
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
	_status_ms = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if _stopping:
		return
	for link in hub.poll():
		relay.add_client(link, (link as EnetHub.PeerLink).address)
	relay.tick()
	hub.flush()
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
	_print("server stopped")


func _print(s: String) -> void:
	print(_stamp() + s)


static func _stamp() -> String:
	return "[%s] " % Time.get_datetime_string_from_system(false, true)
