class_name DailyClient
extends RefCounted
## A short connection to the dedicated server outside any match: sends a Daily
## Challenge replay to be scored and ranked, or asks for the day's top ten. Says hello
## like a player (so the version and data checks apply), then one request, then
## waits for the answer. `tick()` every frame until `done`. The hello carries the
## player's id and secret (Netplay.secret): the board comes back as {name, score},
## with `you: true` on this player's row.

const TIMEOUT_TICKS := 60 * 12

var link: NetLink
var done := false
var ok := false
var error := ""
var score := 0
var rank := 0
var board: Array = []
var _request := {}
var _said_hello := false
var _t := 0


## Sends the day's replay (a Replay dictionary with its setup) for `fighter` on `date`.
static func submit(address: String, port: int, date: int, fighter: String, replay: Dictionary,
		p_link: NetLink = null) -> DailyClient:
	var c := DailyClient.new()
	c._request = {"t": "daily", "date": date, "fighter": fighter, "replay": replay}
	c._open(address, port, p_link)
	return c


## Asks for the day's top ten.
static func fetch_board(address: String, port: int, date: int, p_link: NetLink = null) -> DailyClient:
	var c := DailyClient.new()
	c._request = {"t": "board", "date": date}
	c._open(address, port, p_link)
	return c


func _open(address: String, port: int, p_link: NetLink) -> void:
	if p_link != null:
		link = p_link
		return
	var e := EnetLink.new()
	if e.join(address, port) != OK:
		_fail(e.error)
		return
	link = e


func _fail(msg: String) -> void:
	done = true
	ok = false
	error = msg
	if link != null:
		link.close()


func tick() -> void:
	if done or link == null:
		return
	_t += 1
	if link.status == NetLink.Status.CLOSED:
		_fail(link.error if link.error != "" else "Connection lost")
		return
	if link.status == NetLink.Status.CONNECTED and not _said_hello:
		_said_hello = true
		link.send({"t": "hello", "v": Netplay.NET_VERSION, "data": Netplay.data_hash(),
			"team": [String(_request.get("fighter", MatchFactory.FIGHTERS[0]))], "submit": true,
			"id": Netplay.player_id, "secret": Netplay.secret(), "name": Netplay.player_name}, true)
		link.send(_request, true)
		link.flush()
	for m in link.poll():
		match String(m.get("t", "")):
			"reject":
				_fail(String(m.get("msg", "Refused")))
				return
			"daily_ok":
				ok = true
				score = NetLink.int_of(m.get("score", 0))
				rank = NetLink.int_of(m.get("rank", 0))
				board = clean_board(m.get("board", []))
				done = true
				link.close()
				return
			"daily_board":
				ok = true
				board = clean_board(m.get("board", []))
				done = true
				link.close()
				return
	if _t > TIMEOUT_TICKS:
		_fail("No answer from the server")
	link.flush()


## The most rows of a board this client keeps (the server sends the top few).
const MAX_BOARD := 100


## A board as the server sent it, made safe to show: rows that are dictionaries, a
## clean name and a whole-number score each, at most MAX_BOARD of them.
static func clean_board(b) -> Array:
	var out: Array = []
	if not (b is Array):
		return out
	for row in b:
		if out.size() >= MAX_BOARD:
			break
		if row is Dictionary:
			var r: Dictionary = (row as Dictionary).duplicate()
			r["name"] = Netplay.clean_name(str(r.get("name", "Player")))
			r["score"] = NetLink.int_of(r.get("score", 0))
			out.append(r)
	return out
