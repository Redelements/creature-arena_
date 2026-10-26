class_name Ratings
extends RefCounted
## The dedicated server's book of ranked players and daily scores, kept in a JSON file.
## Ratings are Glicko (the 1995 version): a rating and a deviation that shrinks as a
## player plays and grows again while they're away, so a newcomer moves fast and a
## veteran slowly. Matchmaking pairs players whose ratings are within a band that
## widens the longer they wait. Daily scores keep each player's best per day, for the
## last DAILY_DAYS days. Players are known by the id their game made once (settings)
## and the name they typed; the id is proven by a secret the game also made once and
## never shows: the book keeps only a hash of id and secret (`keys`), bound the first
## time the id is used with a secret (ids from before secrets keep their history and
## are bound to the first install that claims them). Ids are never sent to other
## players. This never touches the simulation.
##
## The file is written whole to a temporary file and then renamed over the old one (the
## old one kept as .bak), so a crash mid-write never loses it; a file that exists but
## can't be read is moved aside (and logged), never silently replaced.

const START := 1500.0
const START_RD := 350.0
const MIN_RD := 50.0
const Q := 0.0057565  ## ln 10 / 400
const DRIFT := 35.0  ## deviation regained per day away (root-mean-square)
const BAND := 100.0  ## the rating gap matchmaking accepts straight away
const BAND_PER_10S := 50.0  ## and how much wider it gets per 10 s of waiting
const TOP := 10
## Days of Daily scores kept (older days are dropped when a new day's first score comes
## in), and the most players one day's board holds.
const DAILY_DAYS := 60
const DAILY_ROWS := 5000
## Answers of check_key.
enum Key { UNKNOWN, OK, WRONG }

var path := "user://ratings.json"
var persist := true  ## off in tests: nothing written
var players := {}  ## id -> {name, rating, rd, games, wins, last_ms}
var daily := {}  ## "YYYYMMDD" -> id -> {name, score}
var keys := {}  ## id -> key_of(id, the player's secret)
var _loaded := false
## Where loud messages go (the server's log); they're printed to stderr too.
var on_log := Callable()


func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not persist:
		return
	var d = _read(path)
	if d == null and FileAccess.file_exists(path):
		# There, but not readable: never overwrite it. Move it aside and say so loudly.
		var aside := "%s.corrupt-%d" % [path, int(Time.get_unix_time_from_system())]
		DirAccess.rename_absolute(path, aside)
		_shout("RATINGS FILE UNREADABLE: %s moved to %s; trying the backup" % [path, aside])
	if d == null and FileAccess.file_exists(path + ".bak"):
		d = _read(path + ".bak")
		if d != null:
			_shout("ratings restored from %s.bak (the last good save before)" % path)
	if d == null:
		return
	players = _dict(d.get("players"))
	daily = _dict(d.get("daily"))
	keys = _dict(d.get("keys"))


## The book in `file`, or null when it's missing or not a book.
static func _read(file: String) -> Variant:
	if not FileAccess.file_exists(file):
		return null
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return null
	var json := JSON.new()  # (not parse_string: a bad file is reported here, not as an engine error)
	if json.parse(f.get_as_text()) != OK:
		return null
	return json.data if json.data is Dictionary else null


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


func _shout(msg: String) -> void:
	printerr(msg)
	if on_log.is_valid():
		on_log.call(msg)


## Writes the book: whole to path.tmp, the old file copied to path.bak, then the
## temporary file renamed over it (a rename is all or nothing).
func save() -> void:
	if not persist:
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_shout("ratings not saved: can't write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify({"players": players, "daily": daily, "keys": keys}, "\t"))
	var err := f.get_error()
	f.close()
	if err != OK:
		_shout("ratings not saved: writing %s failed (%s)" % [tmp, error_string(err)])
		DirAccess.remove_absolute(tmp)
		return
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		_shout("ratings not saved: renaming %s failed (%s)" % [tmp, error_string(err)])


## The hash the book keeps for a player's id and secret.
static func key_of(id: String, secret: String) -> String:
	# The salt keeps the game's old name: changing it would change every player's key.
	return ("creature-arena|%s|%s" % [id, secret]).sha256_text()


## Whether `key` (key_of) proves `id`: Key.OK, Key.WRONG, or Key.UNKNOWN (no key bound
## yet: the first to use the id binds one).
func check_key(id: String, key: String) -> int:
	_ensure()
	if not keys.has(id):
		return Key.UNKNOWN
	return Key.OK if String(keys[id]) == key else Key.WRONG


## Binds `key` to `id` if nothing is bound yet. True when `key` is the id's key now.
func bind_key(id: String, key: String) -> bool:
	_ensure()
	if id == "" or key == "":
		return false
	if keys.has(id):
		return String(keys[id]) == key
	keys[id] = key
	save()
	return true


## Whether the book holds anything under `id` (a rating or a kept Daily score).
func has_history(id: String) -> bool:
	_ensure()
	if players.has(id):
		return true
	for day in daily.values():
		if day is Dictionary and (day as Dictionary).has(id):
			return true
	return false


## Forgets a player's key (the server's --reset-player): their next game binds a new one.
func reset_key(id: String) -> bool:
	_ensure()
	if not keys.has(id):
		return false
	keys.erase(id)
	save()
	return true


## A player's book entry if there is one, without making one ({} if none).
func peek(id: String) -> Dictionary:
	_ensure()
	return players.get(id, {})


func player(id: String, name := "") -> Dictionary:
	_ensure()
	if not players.has(id):
		players[id] = {"name": name if name != "" else "Player", "rating": START, "rd": START_RD, "games": 0, "wins": 0,
			"last_ms": 0}
	elif name != "":
		players[id]["name"] = name
	return players[id]


## A player's rating (a newcomer's START when the book has none: asking adds nobody).
func rating(id: String) -> float:
	return float(peek(id).get("rating", START))


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


## A daily score: kept when it beats the player's best that day. Returns the rank (1 = top;
## 0 when a full day's board has no room for it). A new day drops the days more than
## DAILY_DAYS before it; a full day keeps only scores that beat its lowest.
func submit_daily(date: int, id: String, name: String, score: int) -> int:
	_ensure()
	var key := str(date)
	if not daily.has(key):
		daily[key] = {}
		_prune_days(date)
	var day: Dictionary = daily[key]
	if not day.has(id) and day.size() >= DAILY_ROWS:
		var low_id := ""
		var low := 1 << 30
		for other in day:
			if int(day[other]["score"]) < low:
				low = int(day[other]["score"])
				low_id = other
		if score <= low:
			return 0
		day.erase(low_id)
	if not day.has(id) or int(day[id]["score"]) < score:
		day[id] = {"name": name if name != "" else "Player", "score": score}
		save()
	return rank(date, id)


## Drops Daily days more than DAILY_DAYS before `date` (and any key that then proves
## nothing: no rating, no kept score).
func _prune_days(date: int) -> void:
	var keep := date_days(date) - DAILY_DAYS
	var dropped := false
	for k in daily.keys():
		var day := date_days(int(k)) if String(k).is_valid_int() else -1
		if day < 0 or day < keep:
			daily.erase(k)
			dropped = true
	if dropped:
		for id in keys.keys():
			if not has_history(id):
				keys.erase(id)


## A YYYYMMDD date as days since 1 January 1970, or -1 when it isn't a real date
## (2000 to 9999).
static func date_days(date: int) -> int:
	var y := date / 10000
	var m := (date / 100) % 100
	var d := date % 100
	if y < 2000 or y > 9999 or m < 1 or m > 12 or d < 1:
		return -1
	var leap := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
	var lengths := [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if d > int(lengths[m - 1]):
		return -1
	return int(Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": d,
		"hour": 0, "minute": 0, "second": 0})) / 86400


func rank(date: int, id: String) -> int:
	var rows := _day_rows(date)
	for i in rows.size():
		if String(rows[i]["id"]) == id:
			return i + 1
	return 0


func _day_rows(date: int) -> Array:
	_ensure()
	var day = daily.get(str(date), {})
	var rows: Array = []
	if not (day is Dictionary):
		return rows
	for id in day:
		rows.append({"id": id, "name": day[id]["name"], "score": int(day[id]["score"])})
	rows.sort_custom(func(x, y): return int(x["score"]) > int(y["score"]) or (int(x["score"]) == int(y["score"]) and String(x["id"]) < String(y["id"])))
	return rows


## The day's top scores, best first: [{name, score}], the row of `me` (an id) marked
## `you: true`. Ids are never on it: they stay between each player and the server.
func daily_board(date: int, n := TOP, me := "") -> Array:
	var out: Array = []
	for row in _day_rows(date).slice(0, n):
		var r := {"name": row["name"], "score": row["score"]}
		if me != "" and String(row["id"]) == me:
			r["you"] = true
		out.append(r)
	return out
