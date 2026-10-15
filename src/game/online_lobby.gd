class_name OnlineLobby
extends UiScreen
## The online screen, in pages:
##
##   Online       Quick match / Rooms / More / Back
##   Quick match  1 v 1 / 2 v 2 / 3 v 3       (whoever is waiting on the game's server)
##   Rooms        size, Create room, a friend's code, Join room
##   More         Host a match, join a host or another server by address, recent ones
##
## Whatever is chosen, the character select tiles come next (`solo`: just your fighter),
## then the search starts: the server is Settings > Game > Online server. While
## searching only Cancel works; it stops the search and comes back here. Back on a page
## goes up to the first one, and from there leaves.
##
## The text boxes are real LineEdits (caret, selection, clipboard; the on-screen
## keyboard where the platform has one). The last few addresses joined are one press away.

## `size`: players per side (1 to 3); 0 when joining a friend's room (it has its own).
signal server_join_pressed(fighter: String, room: String, size: int)
signal host_pressed(fighter: String)
signal join_pressed(fighter: String, address: String, port: int, room: String)
## Back from the first page: leave the online screen.
signal cancelled
## Cancel while searching (or hosting): stop, and stay here.
signal search_cancelled

enum Page { MAIN, QUICK, ROOMS, MORE }

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
const SIZE_NAMES := ["1 v 1", "Duel 3v3 tag", "2 v 2", "3 v 3"]
## Each size name's players per side and fighters per player.
const SIZE_OF := [1, 1, 2, 3]
const TAG_OF := [1, 3, 1, 1]
const PAGE_TITLES := ["", "QUICK MATCH", "ROOMS", "MORE"]

var fighter := "cairn"
var address := ""
var recent: Array = []
## The server Quick match and rooms use ("" if none is set).
var server := ""
## The room this player is joining (shown while connecting), and whether they made it.
var room_code := ""
var room_created := false
## Players per side for a room this player makes (1 to 3), and for the room shown.
var room_size := 1
var room_tag := 1  ## fighters per player in a room you make (3: a tag Duel)
## The team rules for 2 v 2 and 3 v 3 (TeamSim.RULE_IDS) and the fighters picked
## (one, or three for a tag Duel).
var rules_id := ""
var team: Array = []
var _rules_row: OptionRow
var _room_rules_row: OptionRow
var _watch_any: Button
var _watch_room: Button
## The next server join is to watch, not play (main reads and clears it).
var watch_next := false
## What the search is for ("Quick match  2 v 2"), shown under the status while busy.
var searching_for := ""
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
var page: Page = Page.MAIN
## The More page is up (kept for callers that only care about that one).
var more_shown := false
## The pick screen, while it's up.
var picker: CharacterSelect = null

var field: LineEdit  ## the address box (under More)
var code_field: LineEdit
var _page_label: Label
var _quick_page: Button
var _rooms_page: Button
var _quick: Button
var _quick2: Button
var _quick3: Button
var _size_row: OptionRow
var _quick_tag: Button
var _create: Button
var _join_room: Button
var _more: Button
var _host: Button
var _join: Button
var _back: Button
var _recent_rows: Array = []
var _status_label: Label
var _who_label: Label
var _room_label: Label
var _addr_label: Label


func _init(p_fighter := "cairn", p_address := "", p_recent: Array = [], p_server := "") -> void:
	super()
	fighter = p_fighter if p_fighter in MatchFactory.FIGHTERS else "cairn"
	address = p_address
	recent = p_recent.slice(0, MAX_RECENT)
	server = p_server.strip_edges()
	title = "ONLINE"
	subtitle = ("Server: " + server) if server != "" else "No server set (Settings > Game)"
	row_width = 250.0
	# Compact rows, like Single player: the More page and its recent servers fit.
	row_height = 13.0
	row_font = 8
	row_gap = 1
	dim = 0.9
	hints = ["move", "change", "select", "back"]
	page = Page.MAIN if server != "" else Page.MORE


func build() -> void:
	_page_label = add_text("", UiTheme.SIZE_HEADING, UiTheme.C_ACCENT)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The first page.
	_quick_page = add_button("Quick match", func(): open_page(Page.QUICK),
		"Play whoever is waiting on the server: 1 v 1, 2 v 2 or 3 v 3")
	_rooms_page = add_button("Rooms", func(): open_page(Page.ROOMS),
		"Play with friends: make a room and share its code, or join theirs")
	_more = add_button("More: host, or join by address", func(): open_page(Page.MORE),
		"Host a match yourself, or join a host or another server by address")
	# Quick match.
	_quick = add_button("1 v 1", func(): quick_match(1), "Play whoever is waiting on the server")
	_quick2 = add_button("2 v 2", func(): quick_match(2),
		"Teams of two: starts when four players are waiting (CPUs fill in after a while)")
	_quick3 = add_button("3 v 3", func(): quick_match(3),
		"Teams of three: starts when six players are waiting (CPUs fill in after a while)")
	_quick_tag = add_button("Duel 3v3 tag", func(): quick_match(1, 3),
		"Three fighters each, tag them in and out: the launch mode, online")
	_watch_any = add_button("Watch a match", func(): watch(""), "Spectate whatever is on the server right now")
	_rules_row = add_option("Team rules", TeamSim.RULE_NAMES, 0, func(i: int):
			rules_id = TeamSim.RULE_IDS[i]
			if _room_rules_row != null:
				_room_rules_row.set_values(TeamSim.RULE_NAMES, i),
		"For 2 v 2 and 3 v 3 (and rooms of those sizes): the plain battle, deathmatch, Sinkhole, Crater or Showtime")
	# Rooms.
	_size_row = add_option("Room size", SIZE_NAMES, _size_index(room_size, room_tag), func(i: int):
			room_size = SIZE_OF[i]
			room_tag = TAG_OF[i],
		"How many a side in a room you create (a tag Duel is three fighters each)")
	_room_rules_row = add_option("Team rules", TeamSim.RULE_NAMES, 0, func(i: int):
			rules_id = TeamSim.RULE_IDS[i]
			_rules_row.set_values(TeamSim.RULE_NAMES, i),
		"For a 2 v 2 or 3 v 3 room: the plain battle, deathmatch, Sinkhole, Crater or Showtime")
	_create = add_button("Create room", create_room, "Get a code to give your friends: the room starts once it's full")
	code_field = LineEdit.new()
	code_field.placeholder_text = "Friend's room code"
	code_field.max_length = MAX_CODE
	code_field.text_submitted.connect(func(_t): join_room(code_field.text))
	add_row(code_field, CODE_HELP)
	_join_room = add_button("Join room", func(): join_room(code_field.text), "Join the room code above")
	_watch_room = add_button("Watch room", func(): watch(clean_code(code_field.text)), "Spectate the match in the room code above")
	# More.
	_host = add_button("Host a match", host, HOST_HELP)
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
	_who_label = add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_TEXT)
	_room_label = add_text("", UiTheme.SIZE_HEADING, UiTheme.C_TEXT)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_addr_label = add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_TEXT)
	for l in [_status_label, _who_label]:
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_show_page(page)
	_refresh_status()


## Back: Cancel while searching; on a page, up to the first one; there, leave.
func back() -> void:
	if busy:
		search_cancelled.emit()
	elif page != Page.MAIN and server != "":
		var from := page
		open_page(Page.MAIN)
		match from:
			Page.QUICK:
				_quick_page.grab_focus()
			Page.ROOMS:
				_rooms_page.grab_focus()
			Page.MORE:
				_more.grab_focus()
	else:
		cancelled.emit()


func set_gamepad(on: bool) -> void:
	super(on)
	var deck := "Steam Deck: Steam + X opens the keyboard.   "
	if field != null:
		describe(field, deck + FIELD_HELP if on else FIELD_HELP)
	if code_field != null:
		describe(code_field, deck + CODE_HELP if on else CODE_HELP)


## Shows one page's rows and focuses the first of them.
func open_page(p: Page) -> void:
	if busy:
		return
	_show_page(p)
	var r := rows()
	if not r.is_empty():
		(r[0] as Control).grab_focus()


## Kept for the More page's old toggle: swaps between More and the first page.
func toggle_more() -> void:
	open_page(Page.MAIN if page == Page.MORE and server != "" else Page.MORE)


# ------------------------------------------------------------------ choices
# Each one picks the fighter first (the tiles), then starts the search.

static func _size_index(size: int, tag: int) -> int:
	for i in SIZE_NAMES.size():
		if SIZE_OF[i] == size and TAG_OF[i] == tag:
			return i
	return 0


## Plays whoever is waiting on the server for the same size (players per side) and
## fighters per player (3: a tag Duel), under the Team rules row for team sizes.
func quick_match(size := 1, tag := 1) -> void:
	if busy or not _have_server():
		return
	size = clampi(size, 1, 3)
	var name: String = SIZE_NAMES[_size_index(size, tag)]
	_pick_then("QUICK MATCH  " + name,
		"Next: the server looks for players. Accept when the match is found.", func():
			room_code = ""
			room_created = false
			searching_for = "Quick match  " + name
			server_join_pressed.emit(fighter, "", size), tag)


## Makes a room code and waits there for a friend.
func create_room() -> void:
	if busy or not _have_server():
		return
	var name: String = SIZE_NAMES[_size_index(room_size, room_tag)]
	_pick_then("NEW ROOM  " + name,
		"Next: you get a code for your friends. It starts once the room is full.", func():
			room_code = make_code()
			room_created = true
			searching_for = "Room  " + name
			server_join_pressed.emit(fighter, room_code, room_size), room_tag)


## Spectates: the room's match, or (no code) whatever is on.
func watch(code: String) -> void:
	if busy or not _have_server():
		return
	watch_next = true
	room_code = code
	room_created = false
	searching_for = "Watching " + (("room " + code) if code != "" else "the server's match")
	server_join_pressed.emit(fighter, code, 0)


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
	_pick_then("ROOM  " + code, "Next: you join your friend's room.", func():
		room_code = code
		room_created = false
		searching_for = "Room " + code
		server_join_pressed.emit(fighter, code, 0))


## Hosts a match on this machine (More).
func host() -> void:
	if busy:
		return
	_pick_then("HOST A MATCH", "Next: wait here for a player to join your address.", func():
		room_code = ""
		room_created = false
		searching_for = "Hosting"
		host_pressed.emit(fighter))


## The fighter was picked (from the tiles, or a test): remembered for next time.
func use_fighter(id: String) -> void:
	if id in MatchFactory.FIGHTERS:
		fighter = id


## A team of `n` starting with the fighter, the roster filling the rest.
func _padded(n: int) -> Array:
	var out: Array = [fighter]
	for f in MatchFactory.FIGHTERS:
		if out.size() >= n:
			break
		if not (f in out):
			out.append(f)
	return out


## Opens the tiles for one fighter, then runs `then`. Backing out of them changes nothing.
func _pick_then(heading: String, info: String, then: Callable, tag := 1) -> void:
	status = ""
	status_bad = false
	if stack == null:
		team = [fighter] if tag <= 1 else _padded(tag)
		then.call()  # no screen stack (a bare test): keep the fighter we have
		return
	var p := CharacterSelect.new()
	p.solo = true
	p.solo_heading = heading
	p.solo_info = info
	p.done_text = "LOCKED IN"
	p.setup("ONLINE", tag, ["YOU", "NEXT"], false, [team if team.size() == tag else _padded(tag), []])
	p.chosen.connect(func(teams: Array):
		picker = null
		if stack != null and stack.top() == p:
			stack.pop()
		team = (teams[0] as Array).duplicate()
		use_fighter(String(team[0]))
		then.call())
	p.cancelled.connect(func():
		picker = null
		if stack != null and stack.top() == p:
			stack.pop())
	picker = p
	stack.push(p)


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
	_pick_then("JOIN  " + String(parsed[0]), "Next: you connect to that address.", func():
		room_code = ""
		room_created = false
		searching_for = "Joining " + String(parsed[0])
		join_pressed.emit(fighter, String(parsed[0]), int(parsed[1]), String(parsed[2])))


func _have_server() -> bool:
	if server != "":
		return true
	status_bad = true
	status = NO_SERVER
	return false


# ------------------------------------------------------------------ showing

func _page_rows(p: Page) -> Array:
	match p:
		Page.MAIN:
			return [_quick_page, _rooms_page, _more]
		Page.QUICK:
			return [_quick, _quick_tag, _quick2, _quick3, _rules_row, _watch_any]
		Page.ROOMS:
			return [_size_row, _room_rules_row, _create, code_field, _join_room, _watch_room]
		_:
			return [_host, field, _join] + _recent_rows


func _all_rows() -> Array:
	return _page_rows(Page.MAIN) + _page_rows(Page.QUICK) + _page_rows(Page.ROOMS) + _page_rows(Page.MORE)


func _show_page(p: Page) -> void:
	page = p
	more_shown = p == Page.MORE
	var on := _page_rows(p)
	for c in _all_rows():
		(c as Control).visible = c in on and not busy
	_page_label.text = PAGE_TITLES[p] if not busy else ""
	_page_label.visible = _page_label.text != ""
	link_focus()


func _refresh_status() -> void:
	if _status_label == null:
		return
	_status_label.text = status
	_status_label.add_theme_color_override("font_color", C_BAD if status_bad else UiTheme.C_ACCENT)
	var nm := String(MatchFactory.load_def(fighter).get("name", fighter))
	_who_label.text = ("%s   ·   %s" % [nm, searching_for] if searching_for != "" else nm) if busy else ""
	var show_room := busy and room_code != ""
	_room_label.text = ("Room code  " + room_code) if show_room else ""
	if show_room and room_created:
		_room_label.text += ("  (%s)" % SIZE_NAMES[_size_index(room_size, room_tag)]) if room_size > 1 or room_tag > 1 else ""
		_room_label.text += "\nTell your friend%s: Join room, then this code" % ("s" if room_size > 1 else "")
	var addrs := Netplay.local_addresses()
	_addr_label.text = ("Your addresses:  " + ("  ".join(addrs) if not addrs.is_empty() else "(none found)")) \
		if busy and hosting_port > 0 else ""
	# Empty lines take no room, so the column stays on screen.
	for l in [_status_label, _who_label, _room_label, _addr_label]:
		(l as Label).visible = (l as Label).text != ""


## While searching only Cancel works: the other rows step aside for what's happening.
func _refresh_busy() -> void:
	if _back == null:
		return
	for c in _all_rows():
		(c as Control).focus_mode = Control.FOCUS_NONE if busy else Control.FOCUS_ALL
	if not busy:
		searching_for = ""
	_show_page(page)
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
