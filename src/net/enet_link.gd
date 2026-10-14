class_name EnetLink
extends NetLink
## Direct UDP between two machines, with Godot's built-in ENet. One player hosts on a
## port; the other connects to the host's address. Reliable messages go on channel 0,
## the input stream on channel 1 (unsequenced: a late packet still counts, since the
## rollback session sorts inputs by frame itself).
##
## The host must be reachable: on the same network, through a forwarded UDP port, or
## over a virtual LAN such as Tailscale. A relay or Steam's network removes that need
## later, behind the same NetLink interface.

const CH_CONTROL := 0
const CH_INPUT := 1
## Drop the connection after this long without hearing from the other side.
const TIMEOUT_MS := 5000


## ENet drops unreliable packets in bursts when the round trip wobbles ("throttling").
## The input stream is tiny and must keep flowing, so it's switched off.
static func tune(peer: ENetPacketPeer) -> void:
	peer.set_timeout(32, TIMEOUT_MS, TIMEOUT_MS)
	peer.throttle_configure(5000, 0, 0)

var _conn: ENetConnection = null
var _peer: ENetPacketPeer = null
var _hosting := false


func _init() -> void:
	realtime = true


## Waits for one player to connect on `port` (UDP).
func host(port: int) -> Error:
	_conn = ENetConnection.new()
	var err := _conn.create_host_bound("*", port, 1, 2)
	if err != OK:
		error = "Couldn't open UDP port %d (%s). Is another copy of the game hosting?" % [port, error_string(err)]
		status = Status.CLOSED
		return err
	_hosting = true
	status = Status.LISTENING
	return OK


## Connects to a host at `address` (an IP or a host name) and `port`.
func join(address: String, port: int) -> Error:
	_conn = ENetConnection.new()
	var err := _conn.create_host(1, 2)
	if err != OK:
		error = "Couldn't start networking (%s)" % error_string(err)
		status = Status.CLOSED
		return err
	_peer = _conn.connect_to_host(address, port, 2)
	if _peer == null:
		error = "Couldn't reach %s:%d" % [address, port]
		status = Status.CLOSED
		return ERR_CANT_CONNECT
	_peer.set_timeout(32, TIMEOUT_MS, TIMEOUT_MS)
	status = Status.CONNECTING
	return OK


func send(msg: Dictionary, reliable := false) -> void:
	if _peer == null or status != Status.CONNECTED:
		return
	var flags := ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNSEQUENCED
	_peer.send(CH_CONTROL if reliable else CH_INPUT, NetLink.encode(msg), flags)


func poll(wait_ms := 0) -> Array:
	var out: Array = []
	if _conn == null or status == Status.CLOSED or status == Status.IDLE:
		return out
	for i in 256:  # drain everything that's waiting
		var ev: Array = _conn.service(wait_ms if i == 0 else 0)
		var kind := int(ev[0])
		if kind == ENetConnection.EVENT_NONE:
			break
		var peer: ENetPacketPeer = ev[1]
		match kind:
			ENetConnection.EVENT_CONNECT:
				if _hosting and _peer != null and peer != _peer:
					peer.peer_disconnect()  # a match is two players: turn away a third
					continue
				_peer = peer
				tune(_peer)
				status = Status.CONNECTED
			ENetConnection.EVENT_DISCONNECT:
				if peer == _peer:
					status = Status.CLOSED
					if error == "":
						error = "The other player left or the connection dropped"
					_peer = null
			ENetConnection.EVENT_RECEIVE:
				var msg = NetLink.decode(peer.get_packet())
				if peer == _peer and msg != null:
					out.append(msg)
			ENetConnection.EVENT_ERROR:
				status = Status.CLOSED
				if error == "":
					error = "Network error"
	return out


func flush() -> void:
	if _conn != null and status != Status.CLOSED:
		_conn.flush()


func rtt_ms() -> float:
	if _peer == null:
		return 0.0
	return float(_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func close() -> void:
	if _peer != null and status == Status.CONNECTED:
		_peer.peer_disconnect()
		_conn.flush()
	if _conn != null:
		_conn.destroy()
	_conn = null
	_peer = null
	status = Status.CLOSED
