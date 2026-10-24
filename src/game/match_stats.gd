class_name MatchStats
extends RefCounted
## What each fighter did in a match, counted from the sim's events (never by the sim):
## damage dealt, hits landed, knockouts, best combo, blocks, Surges. Main feeds it every
## event (`note`) and resets it when a match starts; the results screen reads `rows`.
## A KO goes to whoever last hurt the victim (poison and shatters included), so a fall
## after a hit counts for the hitter and a plain self-fall for nobody.

## fighter id -> {damage, hits, kos, combo, blocks, surges}
var rows := {}
var _last_hitter := {}  ## victim id -> the id that last hurt them


func reset() -> void:
	rows.clear()
	_last_hitter.clear()


func row(id: int) -> Dictionary:
	if not rows.has(id):
		rows[id] = {"damage": 0.0, "hits": 0, "kos": 0, "combo": 0, "blocks": 0, "surges": 0}
	return rows[id]


func note(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"hit":
			var a := int(e["attacker"])
			var r := row(a)
			r["damage"] += float(e["power"])
			r["hits"] += 1
			r["combo"] = maxi(int(r["combo"]), int(e.get("combo", 1)))
			_last_hitter[int(e["target"])] = a
		"poisoned", "shatter":
			var by := int(e.get("by", -1))
			if by >= 0:
				_last_hitter[int(e["who"])] = by
		"block":
			row(int(e["target"]))["blocks"] += 1
		"surge":
			row(int(e.get("who", 0)))["surges"] += 1
		"ko", "fall":
			var who := int(e.get("who", -1))
			if _last_hitter.has(who):
				var killer: int = _last_hitter[who]
				_last_hitter.erase(who)
				if killer != who:
					row(killer)["kos"] += 1


## How well a fighter did, for the team MVP: damage plus a bonus per KO, Surge and combo hit.
static func score(r: Dictionary) -> float:
	return float(r["damage"]) + 60.0 * int(r["kos"]) + 25.0 * int(r["surges"]) + 5.0 * int(r["combo"])
