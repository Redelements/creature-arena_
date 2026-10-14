class_name NetLink
extends RefCounted
## A connection to the other player, carrying small Dictionary messages. Online play
## (Netplay) only talks to this interface, so the transport underneath can change
## (direct UDP today; a relay server or Steam later) without touching anything else.
##
## Two kinds of send: `reliable` for setup and control messages (they arrive, in
## order), and unreliable for the per-frame input packets (they may be lost or late;
## every packet repeats the last few inputs, so that costs nothing).

enum Status { IDLE, LISTENING, CONNECTING, CONNECTED, CLOSED }

var status: Status = Status.IDLE
## Why the link closed or failed, for the player.
var error := ""
## A real transport (ENet): it may be polled any number of times a frame, as often as
## the game renders, and `poll(wait_ms)` can block for a moment waiting for a packet.
## The in-memory test links count polls as ticks, so they stay once a tick.
var realtime := false


func send(_msg: Dictionary, _reliable := false) -> void:
	pass


## Everything that arrived since the last call. Once a tick, or as often as you like on
## a `realtime` link; `wait_ms` (realtime only) blocks up to that long for something to
## arrive, for timing a ping precisely.
func poll(_wait_ms := 0) -> Array:
	return []


## Sends whatever is queued right away (instead of waiting for the next poll).
func flush() -> void:
	pass


## The transport's own estimate of the round trip, in milliseconds (0 if unknown).
func rtt_ms() -> float:
	return 0.0


func close() -> void:
	status = Status.CLOSED


func is_open() -> bool:
	return status == Status.CONNECTED


static func encode(msg: Dictionary) -> PackedByteArray:
	return var_to_bytes(msg)


## Decodes a packet from the network. Anything that isn't a plain Dictionary (a
## corrupt or hostile packet) is dropped: objects are never decoded.
static func decode(bytes: PackedByteArray) -> Variant:
	if bytes.size() < 4:
		return null
	var v = bytes_to_var(bytes)
	return v if v is Dictionary else null
