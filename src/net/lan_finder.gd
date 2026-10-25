class_name LanFinder
extends RefCounted
## Looks for a Creature Arena dedicated server on this computer's own network, so a
## player at the server's house joins it directly (see ServerBeacon for why).
##
##   var f := LanFinder.new()
##   f.start(7777)            # broadcasts the question a few times
##   ...each frame: if f.poll(): use f.found ({address, port}) or, if empty, the public name
##
## It gives up after WAIT_MS with nothing found, which is the usual case away from home.

const WAIT_MS := 600
const RESEND_MS := 150

## The server that answered: {"address", "port"}; empty if none did (yet).
var found := {}
var done := false

var _udp := PacketPeerUDP.new()
var _target := "255.255.255.255"
var _port := 0
var _start_ms := 0
var _sent_ms := 0


## Starts asking for a server whose game port is `game_port`. `target` is the broadcast
## address (tests ask 127.0.0.1).
func start(game_port: int, target := "255.255.255.255") -> void:
	_target = target
	_port = ServerBeacon.discovery_port(game_port)
	_udp.set_broadcast_enabled(true)
	if _udp.bind(0) != OK:
		done = true  # no network: go straight to the public name
		return
	_start_ms = Time.get_ticks_msec()
	_ask()


## Reads answers. Returns true once it's finished (found one, or gave up).
func poll() -> bool:
	if done:
		return true
	while _udp.get_available_packet_count() > 0:
		var m := ServerBeacon.read(_udp.get_packet())
		var ip := _udp.get_packet_ip()
		# Only a server running this very build: anyone on a shared network can answer,
		# and an answer from another version (or a stranger) would send this player there
		# instead of to the public name.
		if not accepts(m):
			continue
		var p := NetLink.int_of(m.get("port", 0))
		if ip == "" or p <= 0 or p > 65535:
			continue
		found = {"address": ip, "port": p, "v": int(m.get("v", -1))}
		_finish()
		return true
	var now := Time.get_ticks_msec()
	if now - _start_ms >= WAIT_MS:
		_finish()
	elif now - _sent_ms >= RESEND_MS:
		_ask()
	return done


## Whether a beacon's answer is from a server of this build: the same NET_VERSION and the
## same game data (Netplay.data_hash). JSON numbers arrive as floats.
static func accepts(m: Dictionary) -> bool:
	return str(m.get("t", "")) == ServerBeacon.ANSWER \
		and NetLink.int_of(m.get("v", -1), -1) == Netplay.NET_VERSION \
		and typeof(m.get("data")) == TYPE_STRING and String(m["data"]) == Netplay.data_hash()


func cancel() -> void:
	_finish()


func _ask() -> void:
	_sent_ms = Time.get_ticks_msec()
	_udp.set_dest_address(_target, _port)
	_udp.put_packet(JSON.stringify({"t": ServerBeacon.ASK, "v": Netplay.NET_VERSION}).to_utf8_buffer())


func _finish() -> void:
	done = true
	_udp.close()
