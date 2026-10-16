class_name DiscordRpc
extends RefCounted
## Discord Rich Presence over the Discord app's local IPC: no plugin, no SDK.
##
## The Discord desktop app listens on `discord-ipc-0`..`9`: a named pipe on Windows, a
## Unix socket on Linux and macOS. A message is a frame: op (u32 little-endian), length
## (u32), then that many bytes of JSON. We send a handshake with the application id, wait
## for READY, then send SET_ACTIVITY whenever the activity changes (at most every
## SEND_GAP_MS, Discord's limit is 5 updates per 20 s). When the game quits the
## connection closes and Discord clears the status by itself.
##
## Everything here is best effort: no Discord, no connection, a closed pipe, all just
## mean nothing shows, and the next try is RETRY_MS later. `poll()` never blocks: reads
## happen only when bytes are waiting (a Windows pipe read would wait otherwise).

enum Op { HANDSHAKE, FRAME, CLOSE, PING, PONG }
enum State { OFF, CONNECTING, READY }

const RETRY_MS := 15000
const SEND_GAP_MS := 4000
## No answer this long after a frame that expects one: the app is gone or stuck.
const REPLY_TIMEOUT_MS := 8000
const PIPES := 10
const MAX_FRAME := 65536
## Close codes that retrying won't fix (4000 invalid client id).
const FATAL_CLOSE := [4000]

var client_id := ""
var state := State.OFF
var user_name := ""  ## the Discord account's name, from READY
var disabled := false  ## the app refused our client id: stop trying
var _file: FileAccess = null  ## Windows
var _sock: StreamPeerUDS = null  ## Linux / macOS
var _rx := PackedByteArray()
var _want := {}  ## the activity to show ({} clears it)
var _want_json := "{}"
var _shown_json := "{}"  ## what Discord was last sent (cleared on reconnect)
var _next_try := 0
var _next_send := 0
var _await_since := -1  ## when the frame we wait an answer to went out (-1: none)
var _nonce := 0


func _init(p_client_id: String) -> void:
	client_id = p_client_id


## What to show. Keys as in Discord's activity object (details, state, timestamps,
## assets...); {} clears the status. Sent on a later poll() once connected.
func set_activity(activity: Dictionary) -> void:
	var j := JSON.stringify(activity)
	if j != _want_json:
		_want = activity.duplicate(true)
		_want_json = j


## Call every frame: connects, reads answers, sends the activity when it changed.
func poll(now := Time.get_ticks_msec()) -> void:
	if disabled or client_id == "":
		return
	if state == State.OFF:
		if now >= _next_try:
			_next_try = now + RETRY_MS
			_connect(now)
		return
	if _await_since >= 0:
		_read()
		if state == State.OFF:
			return
		if _await_since >= 0 and now - _await_since > REPLY_TIMEOUT_MS:
			close()
			return
	if state == State.READY and _await_since < 0 and _want_json != _shown_json and now >= _next_send:
		_nonce += 1
		var activity = _want if not _want.is_empty() else null
		_send(Op.FRAME, {"cmd": "SET_ACTIVITY", "nonce": str(_nonce),
			"args": {"pid": OS.get_process_id(), "activity": activity}}, now)
		_shown_json = _want_json
		_next_send = now + SEND_GAP_MS


func close() -> void:
	if _file != null:
		_file.close()
	if _sock != null:
		_sock.disconnect_from_host()
	_file = null
	_sock = null
	_rx.clear()
	state = State.OFF
	_await_since = -1
	_shown_json = "{}"


func _connect(now: int) -> void:
	for i in PIPES:
		if OS.get_name() == "Windows":
			# FileAccess's pipe:// opens \\.\pipe\LOCAL\<name>, and creates the pipe when
			# nothing is there; "..\" steps out to Discord's, which must exist first or
			# we'd squat its name.
			if not FileAccess.file_exists("\\\\?\\pipe\\discord-ipc-%d" % i):
				continue
			_file = FileAccess.open("pipe://..\\discord-ipc-%d" % i, FileAccess.READ_WRITE)
			if _file == null:
				continue
		else:
			for path in _socket_paths(i):
				_sock = StreamPeerUDS.new()
				if _sock.connect_to_host(path) == OK:
					break
				_sock = null
			if _sock == null:
				continue
		state = State.CONNECTING
		_send(Op.HANDSHAKE, {"v": 1, "client_id": client_id}, now)
		if state != State.OFF:
			return


## Where discord-ipc-N may be: the runtime/temp dirs, plain, Flatpak or Snap.
static func _socket_paths(i: int) -> Array:
	var bases: Array = []
	for env in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"]:
		var v := OS.get_environment(env).trim_suffix("/")
		if v != "" and not (v in bases):
			bases.append(v)
	if not ("/tmp" in bases):
		bases.append("/tmp")
	var out: Array = []
	for b in bases:
		for sub in ["", "/app/com.discordapp.Discord", "/snap.discord", "/.flatpak/dev.vencord.Vesktop/xdg-run"]:
			if DirAccess.dir_exists_absolute(b + sub):
				out.append("%s%s/discord-ipc-%d" % [b, sub, i])
	return out


static func encode_frame(op: int, payload: Dictionary) -> PackedByteArray:
	var body := JSON.stringify(payload).to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, op)
	out.encode_u32(4, body.size())
	out.append_array(body)
	return out


## The whole frames at the front of `buf` and how many bytes they take:
## [[[op, payload], ...], used]. A partial frame at the end is left for later; a bad
## length gives op -1.
static func decode_frames(buf: PackedByteArray) -> Array:
	var frames: Array = []
	var at := 0
	while buf.size() - at >= 8:
		var op := buf.decode_u32(at)
		var n := buf.decode_u32(at + 4)
		if n > MAX_FRAME:
			return [[[-1, {}]], buf.size()]
		if buf.size() - at < 8 + n:
			break
		var parsed = JSON.parse_string(buf.slice(at + 8, at + 8 + n).get_string_from_utf8())
		frames.append([op, parsed if parsed is Dictionary else {}])
		at += 8 + n
	return [frames, at]


func _send(op: int, payload: Dictionary, now: int) -> void:
	var bytes := encode_frame(op, payload)
	var ok := true
	if _file != null:
		_file.store_buffer(bytes)
		ok = _file.get_error() == OK
	elif _sock != null:
		ok = _sock.put_data(bytes) == OK
	else:
		ok = false
	if not ok:
		close()
		return
	if op != Op.PONG:
		_await_since = now


func _read() -> void:
	if _file != null:
		var n := _file.get_length()  # bytes waiting in the pipe
		if n > 0:
			_rx.append_array(_file.get_buffer(n))
	elif _sock != null:
		_sock.poll()
		if _sock.get_status() != StreamPeerSocket.STATUS_CONNECTED:
			close()
			return
		var n := _sock.get_available_bytes()
		if n > 0:
			var got: Array = _sock.get_data(n)
			if int(got[0]) != OK:
				close()
				return
			_rx.append_array(got[1])
	var dec: Array = decode_frames(_rx)
	_rx = _rx.slice(int(dec[1]))
	for f in dec[0]:
		_handle(int(f[0]), f[1])
		if state == State.OFF:
			return


func _handle(op: int, msg: Dictionary) -> void:
	match op:
		Op.FRAME:
			_await_since = -1
			if msg.get("evt") == "READY":
				state = State.READY
				var data = msg.get("data")
				var user = data.get("user") if data is Dictionary else null
				if user is Dictionary:
					var name = user.get("global_name")
					user_name = String(name if name is String else user.get("username", ""))
			elif msg.get("evt") == "ERROR":
				push_warning("Discord status: %s" % str(msg.get("data", msg)))
		Op.PING:
			_send(Op.PONG, msg, Time.get_ticks_msec())
		Op.CLOSE:
			if int(msg.get("code", 0)) in FATAL_CLOSE:
				disabled = true
				push_warning("Discord status off: %s (check client_id in data/discord.json)" % str(msg.get("message", "")))
			close()
		_:
			close()  # a bad frame: start over
