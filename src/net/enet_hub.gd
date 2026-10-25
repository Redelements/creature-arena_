class_name EnetHub
extends RefCounted
## The dedicated server's side of ENet: one UDP port, many players. Each player who
## connects becomes a NetLink of its own (a PeerLink), so the relay talks to every
## player exactly the way a game talks to its one opponent. Same channels as EnetLink:
## reliable control messages on 0, the unsequenced input stream on 1.

## The biggest packet any player may send, in bytes, before RelayServer narrows it
## (a full-length Daily replay is about 140 KB). ENet itself takes up to 32 MB; anything
## over the link's `max_packet` closes that player's connection undecoded.
const MAX_PACKET_BYTES := 256 * 1024
## New connections one address may open a minute (0: any); past it they're cut at once,
## before anything they send is read. Reconnecting after a dropped game takes one.
var connects_per_minute := 30

var error := ""
var port := 0
var _conn: ENetConnection = null
var _links := {}  ## ENetPacketPeer -> PeerLink
var _connects := {}  ## address -> [msec of each recent connection]


## One connected player.
class PeerLink:
	extends NetLink
	var peer: ENetPacketPeer
	var address := ""
	var _hub: EnetHub
	var _inbox: Array = []

	func _init(p_hub: EnetHub, p_peer: ENetPacketPeer) -> void:
		_hub = p_hub
		peer = p_peer
		address = "%s:%d" % [peer.get_remote_address(), peer.get_remote_port()]
		status = Status.CONNECTED
		max_packet = EnetHub.MAX_PACKET_BYTES

	func send(msg: Dictionary, reliable := false) -> void:
		if status != Status.CONNECTED:
			return
		var flags := ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNSEQUENCED
		peer.send(EnetLink.CH_CONTROL if reliable else EnetLink.CH_INPUT, NetLink.encode(msg), flags)

	## What arrived for this player since the last call (the hub gathers it).
	func poll(_wait_ms := 0) -> Array:
		var out := _inbox
		_inbox = []
		return out

	func flush() -> void:
		_hub.flush()

	func rtt_ms() -> float:
		if status != Status.CONNECTED:
			return 0.0
		return float(peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

	func close() -> void:
		if status == Status.CONNECTED:
			peer.peer_disconnect_later()  # after anything still queued, such as a goodbye
		status = Status.CLOSED


## Opens the UDP port for up to `max_players` connections at once.
func listen(p_port: int, max_players: int) -> Error:
	port = p_port
	_conn = ENetConnection.new()
	var err := _conn.create_host_bound("*", port, max_players, 2)
	if err != OK:
		error = "Couldn't open UDP port %d (%s). Is another server or game using it?" % [port, error_string(err)]
		_conn = null
		return err
	return OK


## Services the network: routes packets to their players' links and returns the links
## of players who connected since the last call. `wait_ms` lets an idle server sleep
## until a packet arrives instead of spinning.
func poll(wait_ms := 0) -> Array:
	var fresh: Array = []
	if _conn == null:
		return fresh
	for i in 512:
		var ev: Array = _conn.service(wait_ms if i == 0 else 0)
		var kind := int(ev[0])
		if kind == ENetConnection.EVENT_NONE:
			break
		var peer: ENetPacketPeer = ev[1]
		match kind:
			ENetConnection.EVENT_CONNECT:
				if not _may_connect(peer.get_remote_address()):
					peer.peer_disconnect_now()
					continue
				EnetLink.tune(peer)
				var l := PeerLink.new(self, peer)
				_links[peer] = l
				fresh.append(l)
			ENetConnection.EVENT_DISCONNECT:
				if _links.has(peer):
					var l: PeerLink = _links[peer]
					if l.status != NetLink.Status.CLOSED:
						l.status = NetLink.Status.CLOSED
						l.error = "disconnected"
					_links.erase(peer)
			ENetConnection.EVENT_RECEIVE:
				var bytes := peer.get_packet()
				var l: PeerLink = _links.get(peer)
				if l == null or l.status != NetLink.Status.CONNECTED:
					continue
				if not l.admit(bytes.size()):
					l.error = "sent a packet too big (%d bytes)" % bytes.size()
					l.close()  # never decoded
					continue
				var msg = NetLink.decode(bytes)
				if msg != null:
					l._inbox.append(msg)
			ENetConnection.EVENT_ERROR:
				error = "Network error"
	return fresh


## Counts a new connection from `host`; false once it has opened connects_per_minute
## in the last minute.
func _may_connect(host: String) -> bool:
	if connects_per_minute <= 0:
		return true
	var now := Time.get_ticks_msec()
	if _connects.size() > 4096:
		_connects.clear()  # a flood of addresses: forget them rather than grow
	var recent: Array = (_connects.get(host, []) as Array).filter(func(t): return now - int(t) < 60000)
	if recent.size() >= connects_per_minute:
		_connects[host] = recent
		return false
	recent.append(now)
	_connects[host] = recent
	return true


func flush() -> void:
	if _conn != null:
		_conn.flush()


## Says goodbye to everyone and closes the port.
func close() -> void:
	if _conn == null:
		return
	for l in _links.values():
		(l as PeerLink).close()
	_conn.flush()
	_conn.destroy()
	_conn = null
	_links.clear()
