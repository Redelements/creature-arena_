class_name ServerBeacon
extends RefCounted
## A dedicated server's answer to "is there a Ready 4 Rambles server on this network?".
##
## Players at the server's own house can't always reach it by its public name: many
## routers won't loop their public address back inside. So before joining, the game
## broadcasts a small question on the local network (LanFinder) and a server that hears
## it answers with its game port, and the game joins that local address instead.
##
## It listens on UDP game port + 1 (7778 by default), separate from the game's own port.
## The firewall only needs to let it in from the local network:
##   sudo ufw allow from 192.168.0.0/24 to any port 7778 proto udp

## The question and answer (JSON), so nothing else on the network is mistaken for one.
## They keep the game's old name, so servers and games from before the rename still
## find each other.
const ASK := "creature-arena?"
const ANSWER := "creature-arena"
## Anything longer than this isn't a question; it's dropped unread.
const MAX_PACKET := 256
## Questions answered per poll at most, so a flood can't stall the server loop.
const MAX_PER_POLL := 32

var port := 0  ## the port it listens on (game port + 1)
var game_port := Netplay.DEFAULT_PORT
var error := ""
var answered := 0

var _udp := PacketPeerUDP.new()


## Starts listening on game_port + 1. Returns false (with `error`) if that port is taken.
func listen(p_game_port: int) -> bool:
	game_port = p_game_port
	port = discovery_port(p_game_port)
	if _udp.bind(port, "*") != OK:
		error = "Couldn't open UDP port %d for finding the server on the local network" % port
		return false
	return true


## Answers any questions that have arrived. Call it every loop.
func poll() -> void:
	if not _udp.is_bound():
		return
	var n := 0
	while _udp.get_available_packet_count() > 0 and n < MAX_PER_POLL:
		n += 1
		var m := read(_udp.get_packet())
		if String(m.get("t", "")) != ASK:
			continue
		_udp.set_dest_address(_udp.get_packet_ip(), _udp.get_packet_port())
		_udp.put_packet(JSON.stringify({"t": ANSWER, "v": Netplay.NET_VERSION, "port": game_port,
			"data": Netplay.data_hash()}).to_utf8_buffer())
		answered += 1


func close() -> void:
	_udp.close()


## A question or answer, or {} for anything else (quietly: the network carries other things).
static func read(pkt: PackedByteArray) -> Dictionary:
	if pkt.is_empty() or pkt.size() > MAX_PACKET:
		return {}
	var j := JSON.new()
	if j.parse(pkt.get_string_from_utf8()) != OK or not (j.data is Dictionary):
		return {}
	return j.data


## Where a server on `game_port` listens for the question.
static func discovery_port(p_game_port: int) -> int:
	return p_game_port + 1 if p_game_port < 65535 else p_game_port - 1
