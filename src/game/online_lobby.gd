class_name OnlineLobby
extends UiScreen
## The online screen: pick your fighter, then host a match, or join a host or a
## dedicated server by address. While hosting it lists this computer's addresses for the
## other player; while connecting it shows what's happening and only Cancel works.
##
## The address is a real text box (caret, selection, clipboard; the on-screen keyboard
## where the platform has one). The last few addresses joined are one press away.

signal host_pressed(fighter: String)
signal join_pressed(fighter: String, address: String, port: int, room: String)
signal cancelled

const C_BAD := Color("ff8a7a")
const MAX_RECENT := 3
const HOST_HELP := "They join your address: the 192.168... one at home; online, forward UDP 7777 or use Tailscale"
const FIELD_HELP := "A host's address, or a dedicated server's (add /room to meet a friend there)"

var fighter := "cairn"
var address := ""
var recent: Array = []
## Set by main from the Netplay session: what's happening, and whether it went wrong.
var status := "":
	set(v):
		status = v
		_refresh_status()
var status_bad := false:
	set(v):
		status_bad = v
		_refresh_status()
var busy := false:  ## hosting or connecting: only Cancel works
	set(v):
		busy = v
		_refresh_busy()
var hosting_port := 0:
	set(v):
		hosting_port = v
		_refresh_status()

var field: LineEdit
var _preview: FighterPreview
var _fighter_row: OptionRow
var _host: Button
var _join: Button
var _back: Button
var _recent_rows: Array = []
var _status_label: Label
var _addr_label: Label


func _init(p_fighter := "cairn", p_address := "", p_recent: Array = []) -> void:
	super()
	fighter = p_fighter if p_fighter in MatchFactory.FIGHTERS else "cairn"
	address = p_address
	recent = p_recent.slice(0, MAX_RECENT)
	title = "ONLINE  1 v 1"
	subtitle = "Host a match, or join a host or a server by address"
	row_width = 250.0
	dim = 0.9
	hints = ["move", "change", "select", "back"]


func build() -> void:
	_preview = FighterPreview.new()
	_preview.custom_minimum_size = Vector2(row_width, 34)
	_preview.zoom = 0.6
	_preview.fighter = fighter
	_list.add_child(_preview)
	var names: Array = []
	for id in MatchFactory.FIGHTERS:
		names.append(String(MatchFactory.load_def(id).get("name", id)))
	_fighter_row = add_option("Fighter", names, MatchFactory.FIGHTERS.find(fighter), _on_fighter,
		"Who you play")
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
	_addr_label = add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_TEXT)
	_refresh_status()


func back() -> void:
	cancelled.emit()


func set_gamepad(on: bool) -> void:
	super(on)
	if field != null:
		describe(field, "Steam Deck: Steam + X opens the keyboard.   " + FIELD_HELP if on else FIELD_HELP)


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
	join_pressed.emit(fighter, String(parsed[0]), int(parsed[1]), String(parsed[2]))


func _refresh_status() -> void:
	if _status_label == null:
		return
	_status_label.text = status
	_status_label.add_theme_color_override("font_color", C_BAD if status_bad else UiTheme.C_ACCENT)
	var addrs := Netplay.local_addresses()
	_addr_label.text = ("Your addresses:  " + ("  ".join(addrs) if not addrs.is_empty() else "(none found)")) \
		if busy and hosting_port > 0 else ""


## While hosting or connecting only Cancel works.
func _refresh_busy() -> void:
	if _back == null:
		return
	for c in [_fighter_row, _host, field, _join] + _recent_rows:
		var ctl := c as Control
		ctl.focus_mode = Control.FOCUS_NONE if busy else Control.FOCUS_ALL
		ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE if busy else Control.MOUSE_FILTER_STOP
		ctl.modulate.a = 0.45 if busy else 1.0
	field.editable = not busy
	_back.text = "Cancel" if busy else "Back"
	link_focus()
	if busy:
		_back.grab_focus()
	_refresh_status()


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
