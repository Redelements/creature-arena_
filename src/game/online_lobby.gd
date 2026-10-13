class_name OnlineLobby
extends UiScreen
## The online screen: pick your fighter, then play on the game's server (Settings > Game
## > Online server): Quick match pairs you with whoever is waiting; Create room gives you
## a short code for a friend, who types it under Join room, and the server pairs the two
## of you. "More" opens the rest: host a match yourself, or join a host or another server
## by address. While connecting it shows what's happening and only Cancel works.
##
## The text boxes are real LineEdits (caret, selection, clipboard; the on-screen
## keyboard where the platform has one). The last few addresses joined are one press away.

signal server_join_pressed(fighter: String, room: String)
signal host_pressed(fighter: String)
signal join_pressed(fighter: String, address: String, port: int, room: String)
signal cancelled

const C_BAD := Color("ff8a7a")
const MAX_RECENT := 3
## Room codes: four characters that can't be mixed up when read out (no 0/O, 1/I/L).
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 4
const MAX_CODE := 12
const HOST_HELP := "They join your address: the 192.168... one at home; online, forward UDP 7777 or use Tailscale"
const FIELD_HELP := "A host's address, or another server's (add /room to meet a friend there)"
const CODE_HELP := "Type the code your friend got from Create room, then Enter"
const NO_SERVER := "No server set: add one in Settings > Game > Online server, or use More"

var fighter := "cairn"
var address := ""
var recent: Array = []
## The server Quick match and rooms use ("" if none is set).
var server := ""
## The room this player is joining (shown while connecting), and whether they made it.
var room_code := ""
var room_created := false
## Set by main from the Netplay session: what's happening, and whether it went wrong.
var status := "":
	set(v):
		status = v
		_refresh_status()
var status_bad := false:
	set(v):
		status_bad = v
		_refresh_status()
var busy := false:  ## connecting (or hosting): only Cancel works
	set(v):
		busy = v
		_refresh_busy()
var hosting_port := 0:
	set(v):
		hosting_port = v
		_refresh_status()
var more_shown := false

var field: LineEdit  ## the address box (under More)
var code_field: LineEdit
var _preview: FighterPreview
var _fighter_row: OptionRow
var _quick: Button
var _create: Button
var _join_room: Button
var _more: Button
var _host: Button
var _join: Button
var _back: Button
var _recent_rows: Array = []
var _status_label: Label
var _room_label: Label
var _addr_label: Label


func _init(p_fighter := "cairn", p_address := "", p_recent: Array = [], p_server := "") -> void:
	super()
	fighter = p_fighter if p_fighter in MatchFactory.FIGHTERS else "cairn"
	address = p_address
	recent = p_recent.slice(0, MAX_RECENT)
	server = p_server.strip_edges()
	title = "ONLINE  1 v 1"
	subtitle = ("Server: " + server) if server != "" else "No server set (Settings > Game)"
	row_width = 250.0
	dim = 0.9
	hints = ["move", "change", "select", "back"]
	more_shown = server == ""


func build() -> void:
	_preview = FighterPreview.new()
	_preview.custom_minimum_size = Vector2(row_width, 26)
	_preview.zoom = 0.5
	_preview.fighter = fighter
	_list.add_child(_preview)
	var names: Array = []
	for id in MatchFactory.FIGHTERS:
		names.append(String(MatchFactory.load_def(id).get("name", id)))
	_fighter_row = add_option("Fighter", names, MatchFactory.FIGHTERS.find(fighter), _on_fighter,
		"Who you play")
	_quick = add_button("Quick match", quick_match, "Play whoever is waiting on the server")
	_create = add_button("Create room", create_room, "Get a code to give a friend: you'll play each other")
	code_field = LineEdit.new()
	code_field.placeholder_text = "Friend's room code"
	code_field.max_length = MAX_CODE
	code_field.text_submitted.connect(func(_t): join_room(code_field.text))
	add_row(code_field, CODE_HELP)
	_join_room = add_button("Join room", func(): join_room(code_field.text), "Join the room code above")
	_more = add_button("", toggle_more, "Host a match yourself, or join a host or another server by address")
	_host = add_button("Host a match", func(): host_pressed.emit(fighter), HOST_HELP)
	field = LineEdit.new()
	field.text = address
	field.placeholder_text = "Address to join, e.g. 192.168.1.20 or game.example.net/kev"
	field.max_length = 80
	field.text_changed.connect(func(t: String): address = t)
	field.text_submitted.connect(func(_t): _try_join(address))
	add_row(field, FIELD_HELP)
	_join = add_button("Join", func(): _try_join(address), "Connect to the address above")
	for a in recent:
		var r := add_button("Join  " + String(a), func(): _use_recent(String(a)), "Joined before")
		_recent_rows.append(r)
	add_space(4)
	_back = add_button("Back", back)
	_status_label = add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
	_room_label = add_text("", UiTheme.SIZE_HEADING, UiTheme.C_TEXT)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_addr_label = add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_TEXT)
	_show_more(more_shown)
	_refresh_status()


func back() -> void:
	cancelled.emit()


func set_gamepad(on: bool) -> void:
	super(on)
	var deck := "Steam Deck: Steam + X opens the keyboard.   "
	if field != null:
		describe(field, deck + FIELD_HELP if on else FIELD_HELP)
	if code_field != null:
		describe(code_field, deck + CODE_HELP if on else CODE_HELP)


## Plays whoever is waiting on the server.
func quick_match() -> void:
	if busy or not _have_server():
		return
	room_code = ""
	room_created = false
	server_join_pressed.emit(fighter, "")


## Makes a room code and waits there for a friend.
func create_room() -> void:
	if busy or not _have_server():
		return
	room_code = make_code()
	room_created = true
	server_join_pressed.emit(fighter, room_code)


## Joins a friend's room.
func join_room(text: String) -> void:
	if busy or not _have_server():
		return
	var code := clean_code(text)
	if code == "":
		status_bad = true
		status = "Type your friend's room code first"
		code_field.grab_focus()
		return
	code_field.text = code
	room_code = code
	room_created = false
	server_join_pressed.emit(fighter, code)


## Swaps the server rows for the rest (host, join by address) and back. One set at a
## time keeps the column on screen.
func toggle_more() -> void:
	_show_more(not more_shown)
	(_host if more_shown else _quick).grab_focus()


func _show_more(on: bool) -> void:
	more_shown = on
	_more.text = "Back to Quick match and rooms" if on else "More: host, or join by address"
	describe(_more, "Play on the server: Quick match, or a room with a friend" if on else
		"Host a match yourself, or join a host or another server by address")
	for c in [_host, field, _join] + _recent_rows:
		(c as Control).visible = on
	for c in [_quick, _create, code_field, _join_room]:
		(c as Control).visible = not on
	link_focus()


func _have_server() -> bool:
	if server != "":
		return true
	status_bad = true
	status = NO_SERVER
	return false


func _on_fighter(i: int) -> void:
	fighter = MatchFactory.FIGHTERS[i]
	_preview.fighter = fighter


func _use_recent(a: String) -> void:
	address = a
	field.text = a
	_try_join(a)


func _try_join(text: String) -> void:
	if busy:
		return
	var parsed := parse_address(text)
	if String(parsed[0]) == "":
		status_bad = true
		status = "Type the host's address first (for example 192.168.1.20)"
		field.grab_focus()
		return
	room_code = ""
	room_created = false
	join_pressed.emit(fighter, String(parsed[0]), int(parsed[1]), String(parsed[2]))


func _refresh_status() -> void:
	if _status_label == null:
		return
	_status_label.text = status
	_status_label.add_theme_color_override("font_color", C_BAD if status_bad else UiTheme.C_ACCENT)
	var show_room := busy and room_code != ""
	_room_label.text = ("Room code  " + room_code) if show_room else ""
	if show_room and room_created:
		_room_label.text += "\nTell your friend: Join room, then this code"
	var addrs := Netplay.local_addresses()
	_addr_label.text = ("Your addresses:  " + ("  ".join(addrs) if not addrs.is_empty() else "(none found)")) \
		if busy and hosting_port > 0 else ""
	# Empty lines take no room, so the column stays on screen; a message or the room code
	# takes the fighter picture's place.
	for l in [_status_label, _room_label, _addr_label]:
		(l as Label).visible = (l as Label).text != ""
	_preview.visible = _room_label.text == "" and status == ""


## While connecting only Cancel works: the other rows step aside for what's happening.
func _refresh_busy() -> void:
	if _back == null:
		return
	if busy:
		for c in [_fighter_row, _quick, _create, code_field, _join_room, _more, _host, field, _join] + _recent_rows:
			var ctl := c as Control
			ctl.visible = false
			ctl.focus_mode = Control.FOCUS_NONE
	else:
		for c in [_fighter_row, _quick, _create, code_field, _join_room, _more, _host, field, _join] + _recent_rows:
			(c as Control).focus_mode = Control.FOCUS_ALL
		_fighter_row.visible = true
		_more.visible = true
		_show_more(more_shown)
	field.editable = not busy
	code_field.editable = not busy
	_back.text = "Cancel" if busy else "Back"
	link_focus()
	if busy:
		_back.grab_focus()
	_refresh_status()


## A new room code, e.g. "KX7P". Not part of any match, so plain randomness is fine.
static func make_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := ""
	for i in CODE_LENGTH:
		out += CODE_CHARS[rng.randi_range(0, CODE_CHARS.length() - 1)]
	return out


## What a player typed as a room code, tidied: letters and digits only, upper case.
static func clean_code(text: String) -> String:
	var out := ""
	for ch in text.strip_edges().to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out.left(MAX_CODE)


## "1.2.3.4", "1.2.3.4:7000", "my-pc.lan", "[::1]:7777" -> [host, port, room].
## A dedicated server's address can end in /ROOM ("game.example.net/kev") to be paired
## with whoever types the same room.
static func parse_address(text: String) -> Array:
	var t := text.strip_edges()
	var room := ""
	var slash := t.find("/")
	if slash >= 0:
		room = t.substr(slash + 1).strip_edges()
		t = t.substr(0, slash).strip_edges()
	var port := Netplay.DEFAULT_PORT
	if t.begins_with("["):  # [IPv6]:port
		var end := t.find("]")
		if end > 0:
			if t.substr(end + 1).begins_with(":"):
				port = int(t.substr(end + 2))
			t = t.substr(1, end - 1)
	elif t.count(":") == 1:
		port = int(t.get_slice(":", 1))
		t = t.get_slice(":", 0)
	if port <= 0 or port > 65535:
		port = Netplay.DEFAULT_PORT
	return [t, port, room]
