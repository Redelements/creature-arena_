class_name Ratings
extends RefCounted
## The dedicated server's book of ranked players and daily scores, kept in a JSON file.
## Ratings are Glicko (the 1995 version): a rating and a deviation that shrinks as a
## player plays and grows again while they're away, so a newcomer moves fast and a
## veteran slowly. Matchmaking pairs players whose ratings are within a band that
## widens the longer they wait. Daily scores keep each player's best per day. Players
## are known by the id their game made once (settings) and the name they typed; a home
## server trusts both. This never touches the simulation.

const START := 1500.0
const START_RD := 350.0
const MIN_RD := 50.0
const Q := 0.0057565  ## ln 10 / 400
const DRIFT := 35.0  ## deviation regained per day away (root-mean-square)
const BAND := 100.0  ## the rating gap matchmaking accepts straight away
const BAND_PER_10S := 50.0  ## and how much wider it gets per 10 s of waiting
const TOP := 10

var path := "user://ratings.json"
var persist := true  ## off in tests: nothing written
var players := {}  ## id -> {name, rating, rd, games, wins, last_ms}
var daily := {}  ## "YYYYMMDD" -> id -> {name, score}
var _loaded := false


func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not persist:
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		players = d.get("players", {})
		daily = d.get("daily", {})


func save() -> void:
	if not persist:
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"players": players, "daily": daily}, "\t"))


func player(id: String, name := "") -> Dictionary:
	_ensure()
	if not players.has(id):
		players[id] = {"name": name if name != "" else "Player", "rating": START, "rd": START_RD, "games": 0, "wins": 0,
			"last_ms": 0}
	elif name != "":
		players[id]["name"] = name
	return players[id]


func rating(id: String) -> float:
	return float(player(id)["rating"])


## The deviation now: grown by the time away since the last match (never past a newcomer's).
func deviation(id: String, now_ms: int) -> float:
	var p := player(id)
	var rd := float(p["rd"])
	var last := int(p["last_ms"])
	if last > 0 and now_ms > last:
		var days := float(now_ms - last) / 86400000.0
		rd = minf(START_RD, sqrt(rd * rd + DRIFT * DRIFT * days))
	return rd


static func _g(rd: float) -> float:
	return 1.0 / sqrt(1.0 + 3.0 * Q * Q * rd * rd / (PI * PI))


static func _expected(r: float, r_other: float, rd_other: float) -> float:
	return 1.0 / (1.0 + pow(10.0, -_g(rd_other) * (r - r_other) / 400.0))


## Records a finished match: `score_a` is 1 for an A win, 0.5 a draw, 0 a B win. Returns
## [{id, name, old, new, rd, games, wins}] for A then B.
func record(id_a: String, name_a: String, id_b: String, name_b: String, score_a: float, now_ms := 0) -> Array:
	_ensure()
	if now_ms <= 0:
		now_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var a := player(id_a, name_a)
	var b := player(id_b, name_b)
	var ra := float(a["rating"])
	var rb := float(b["rating"])
	var rda := deviation(id_a, now_ms)
	var rdb := deviation(id_b, now_ms)
	var out: Array = []
	for pair in [[a, ra, rda, rb, rdb, score_a], [b, rb, rdb, ra, rda, 1.0 - score_a]]:
		var p: Dictionary = pair[0]
		var r: float = pair[1]
		var rd: float = pair[2]
		var r2: float = pair[3]
		var rd2: float = pair[4]
		var s: float = pair[5]
		var g := _g(rd2)
		var e := _expected(r, r2, rd2)
		var d2 := 1.0 / (Q * Q * g * g * e * (1.0 - e))
		var new_r := r + Q / (1.0 / (rd * rd) + 1.0 / d2) * g * (s - e)
		var new_rd := maxf(MIN_RD, sqrt(1.0 / (1.0 / (rd * rd) + 1.0 / d2)))
		out.append({"id": "", "old": r, "new": new_r, "rd": new_rd})
		p["rating"] = new_r
		p["rd"] = new_rd
		p["games"] = int(p["games"]) + 1
		p["wins"] = int(p["wins"]) + (1 if s > 0.75 else 0)
		p["last_ms"] = now_ms
	out[0]["id"] = id_a
	out[0]["name"] = a["name"]
	out[1]["id"] = id_b
	out[1]["name"] = b["name"]
	for k in 2:
		var p: Dictionary = a if k == 0 else b
		out[k]["games"] = p["games"]
		out[k]["wins"] = p["wins"]
	save()
	return out


## Whether two players may be paired after waiting `waited_ms` (the longer of the two).
func band_ok(id_a: String, id_b: String, waited_ms: int) -> bool:
	return absf(rating(id_a) - rating(id_b)) <= band(waited_ms)


static func band(waited_ms: int) -> float:
	return BAND + BAND_PER_10S * float(waited_ms) / 10000.0


## A daily score: kept when it beats the player's best that day. Returns the rank (1 = top).
func submit_daily(date: int, id: String, name: String, score: int) -> int:
	_ensure()
	var key := str(date)
	if not daily.has(key):
		daily[key] = {}
	var day: Dictionary = daily[key]
	if not day.has(id) or int(day[id]["score"]) < score:
		day[id] = {"name": name if name != "" else "Player", "score": score}
		save()
	return rank(date, id)


func rank(date: int, id: String) -> int:
	var board := daily_board(date, 1 << 30)
	for i in board.size():
		if String(board[i]["id"]) == id:
			return i + 1
	return 0


## The day's top scores, best first: [{id, name, score}].
func daily_board(date: int, n := TOP) -> Array:
	_ensure()
	var day: Dictionary = daily.get(str(date), {})
	var rows: Array = []
	for id in day:
		rows.append({"id": id, "name": day[id]["name"], "score": int(day[id]["score"])})
	rows.sort_custom(func(x, y): return int(x["score"]) > int(y["score"]) or (int(x["score"]) == int(y["score"]) and String(x["id"]) < String(y["id"])))
	return rows.slice(0, n)
