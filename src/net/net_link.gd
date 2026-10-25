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
## The biggest packet this end takes, in bytes (0: any size, and no other limit). A
## bigger one closes the link before it's decoded: no honest peer sends one. The server
## sets it per player (RelayServer: EnetHub.MAX_PACKET_BYTES until hello, SMALL_PACKET
## after it unless it's a Daily submission).
var max_packet := 0
## With `max_packet` set, packets over SMALL_PACKET this end still takes (a Daily
## submission's one replay); past that, a big packet closes the link like an oversized one.
var big_left := 1
## Every player's message is far smaller (an input packet is a few hundred bytes).
const SMALL_PACKET := 8 * 1024


## Whether a packet of `size` bytes may be decoded (see max_packet, big_left); counts it.
func admit(size: int) -> bool:
	if max_packet <= 0:
		return true
	if size > max_packet:
		return false
	if size > SMALL_PACKET:
		if big_left <= 0:
			return false
		big_left -= 1
	return true


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
	if bytes.size() < 4 or (bytes.decode_u32(0) & 0xFF) != TYPE_DICTIONARY:
		return null
	if _skip(bytes, 0, 0) < 0:
		return null  # malformed: refused before Godot's decoder sees it (which would log errors)
	var v = bytes_to_var(bytes)
	return v if v is Dictionary else null


## Containers nested deeper than this are refused (no message comes near it).
const MAX_DEPTH := 16
const _FLAG_64 := 1 << 16
const _TYPED_NONE := 0
const _TYPED_BUILTIN := 1


## Walks one encoded Variant at `at` (Godot's binary format, as var_to_bytes writes it)
## and returns the offset just past it, or -1 if it's malformed, truncated, too deep or
## of a type messages never carry (objects, callables, vectors...). Nothing is built,
## so a hostile packet costs only the walk. Strings must be valid UTF-8. `want`: the
## type a typed container's element must be (-1: any).
static func _skip(b: PackedByteArray, at: int, depth: int, want := -1) -> int:
	var n := b.size()
	if at + 4 > n:
		return -1
	var header := b.decode_u32(at)
	var type := header & 0xFF
	if want >= 0 and type != want:
		return -1
	at += 4
	match type:
		TYPE_NIL:
			return at
		TYPE_BOOL:
			return at + 4 if at + 4 <= n else -1
		TYPE_INT, TYPE_FLOAT:
			var w := 8 if header & _FLAG_64 else 4
			return at + w if at + w <= n else -1
		TYPE_STRING, TYPE_STRING_NAME:
			return _skip_string(b, at)
		TYPE_ARRAY:
			if depth >= MAX_DEPTH:
				return -1
			var of := _container_type(b, at, (header >> 16) & 3)
			if of < -1:
				return -1
			if of >= 0:
				at += 4
			if at + 4 > n:
				return -1
			var count := b.decode_u32(at) & 0x7FFFFFFF
			at += 4
			if count > n - at:  # every element takes at least 4 bytes
				return -1
			for i in count:
				at = _skip(b, at, depth + 1, of)
				if at < 0:
					return -1
			return at
		TYPE_DICTIONARY:
			if depth >= MAX_DEPTH:
				return -1
			var keys := _container_type(b, at, (header >> 16) & 3)
			if keys < -1:
				return -1
			if keys >= 0:
				at += 4
			var values := _container_type(b, at, (header >> 18) & 3)
			if values < -1:
				return -1
			if values >= 0:
				at += 4
			if at + 4 > n:
				return -1
			var count := b.decode_u32(at) & 0x7FFFFFFF
			at += 4
			if count > (n - at) / 8:
				return -1
			for i in count * 2:
				at = _skip(b, at, depth + 1, keys if i % 2 == 0 else values)
				if at < 0:
					return -1
			return at
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
				TYPE_PACKED_FLOAT64_ARRAY:
			if at + 4 > n:
				return -1
			var count := b.decode_u32(at)
			at += 4
			var w := 1
			if type == TYPE_PACKED_INT32_ARRAY or type == TYPE_PACKED_FLOAT32_ARRAY:
				w = 4
			elif type == TYPE_PACKED_INT64_ARRAY or type == TYPE_PACKED_FLOAT64_ARRAY:
				w = 8
			if count > 0x7FFFFFFF or count * w > n - at:
				return -1
			var size := count * w
			if type == TYPE_PACKED_BYTE_ARRAY:
				size += (4 - size % 4) % 4
				if size > n - at:
					return -1
			return at + size
		TYPE_PACKED_STRING_ARRAY:
			if at + 4 > n:
				return -1
			var count := b.decode_u32(at)
			at += 4
			if count > (n - at) / 4:
				return -1
			for i in count:
				at = _skip_string(b, at)
				if at < 0:
					return -1
			return at
	return -1


## A typed container's element type, read at `at` (4 bytes) when `kind` says it's typed:
## -1 untyped (nothing to read), the built-in type, or -2 for anything else (a class or
## script type, or nonsense): refused.
static func _container_type(b: PackedByteArray, at: int, kind: int) -> int:
	if kind == _TYPED_NONE:
		return -1
	if kind != _TYPED_BUILTIN or at + 4 > b.size():
		return -2
	var t := b.decode_u32(at)
	return t if t < TYPE_MAX and t != TYPE_NIL and t != TYPE_OBJECT else -2


static func _skip_string(b: PackedByteArray, at: int) -> int:
	var n := b.size()
	if at + 4 > n:
		return -1
	var slen := b.decode_u32(at)
	at += 4
	if slen > n - at:
		return -1
	var pad := (4 - slen % 4) % 4
	if slen + pad > n - at or not _utf8_ok(b, at, at + slen):
		return -1
	return at + slen + pad


## Strict UTF-8 (no overlongs, surrogates or code points past U+10FFFF), so the
## decoder never complains about a string.
static func _utf8_ok(b: PackedByteArray, from: int, to: int) -> bool:
	var i := from
	while i < to:
		var c := b[i]
		if c < 0x80:
			i += 1
			continue
		var more := 0
		var lo := 0x80
		var hi := 0xBF
		if c >= 0xC2 and c <= 0xDF:
			more = 1
		elif c >= 0xE0 and c <= 0xEF:
			more = 2
			if c == 0xE0:
				lo = 0xA0
			elif c == 0xED:
				hi = 0x9F
		elif c >= 0xF0 and c <= 0xF4:
			more = 3
			if c == 0xF0:
				lo = 0x90
			elif c == 0xF4:
				hi = 0x8F
		else:
			return false
		if i + more >= to:
			return false
		for k in more:
			var d := b[i + 1 + k]
			if k == 0 and (d < lo or d > hi):
				return false
			if k > 0 and (d < 0x80 or d > 0xBF):
				return false
		i += more + 1
	return true
