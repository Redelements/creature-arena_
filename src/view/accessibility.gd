class_name Accessibility
extends RefCounted
## Accessibility options (Settings > Accessibility; `--a11y=teams,outlines,markers` for a
## session), all off by default and all views only: nothing here reaches the sim.
##
## - Team colours: every marker that says whose side someone is on (the bars over the
##   fighters, the HUD panels and cards, spawn pads, the Crater's zone, flags, the caravan's
##   strip, off-screen arrows, the results table, the pick screen) reads its colour through
##   `side_color`, `brawl_color`, `rel_color` or `neutral_color`, never a constant, so
##   switching to the colour-safe set (data/accessibility.json `teams.colour_safe`, Okabe &
##   Ito's palette) changes them all at once.
## - Fighter outlines: a 1 texel ring round each fighter's silhouette (flash.gdshader's
##   `outline_*`), in its marker colour (Team) or white round a black edge (High contrast).
##   CreatureView draws it only on a sprite that is fully shown: never for a fighter hidden
##   from the local team (it isn't drawn at all), in the brush or invisible.
## - Hit markers: hit sparks, damage numbers and the struck fighter's flash, from the
##   `hit_markers` block (`marker(key)`): bigger, outlined sparks, bigger numbers with a
##   thicker outline and a drop shadow, and the full white flash on every hit.

const PATH := "res://data/accessibility.json"
enum Teams { DEFAULT, SAFE }
enum Outlines { OFF, TEAM, HIGH_CONTRAST }
enum Markers { DEFAULT, HIGH_CONTRAST }
const TEAM_NAMES := ["Default", "Colour-safe"]
const OUTLINE_NAMES := ["Off", "Team", "High contrast"]
const MARKER_NAMES := ["Default", "High contrast"]
const TEAM_SETS := ["default", "colour_safe"]

## The saved choices (Settings), and this session's `--a11y` ones that win over them until the
## row is changed (`cli`: option -> index).
static var teams_saved := 0
static var outlines_saved := 0
static var markers_saved := 0
static var cli := {}

static var _data := {}
static var _sets := []  ## per TEAM_SETS: {"sides": [Color], "brawl": [Color], "self", "ally", "enemy", "neutral"}


static func teams() -> int:
	return int(cli.get("teams", teams_saved))


static func outlines() -> int:
	return int(cli.get("outlines", outlines_saved))


static func markers() -> int:
	return int(cli.get("markers", markers_saved))


## The options a `--a11y=` value turns on: "teams,outlines,markers" (any of them; "all"
## for every one); an outline word may say which: "outlines=team".
static func parse_flag(value: String) -> Dictionary:
	var out := {}
	for w in value.split(",", false):
		var word := w.strip_edges().to_lower()
		var arg := ""
		if "=" in word:
			arg = word.get_slice("=", 1)
			word = word.get_slice("=", 0)
		if word == "all":
			out = {"teams": Teams.SAFE, "outlines": Outlines.HIGH_CONTRAST, "markers": Markers.HIGH_CONTRAST}
			continue
		match word:
			"teams":
				out["teams"] = Teams.SAFE
			"outlines":
				out["outlines"] = Outlines.TEAM if arg == "team" else Outlines.HIGH_CONTRAST
			"markers":
				out["markers"] = Markers.HIGH_CONTRAST
	return out


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_data = d if d is Dictionary else {}
		_sets = []
		var teams_d: Dictionary = _data.get("teams", {})
		for id in TEAM_SETS:
			var s: Dictionary = teams_d.get(id, teams_d.get("default", {}))
			var e := {"sides": _colors(s.get("sides", ["#ff5a5a", "#5aa0ff"])),
				"brawl": _colors(s.get("brawl", ["#ff5a5a", "#5aa0ff", "#6fd66f", "#ffd166"]))}
			for k in ["self", "ally", "enemy", "neutral"]:
				e[k] = Color(String(s.get(k, "#ffffff")))
			_sets.append(e)
	return _data


static func _colors(a: Array) -> Array:
	var out: Array = []
	for h in a:
		out.append(Color(String(h)))
	return out


## The colour set in use (or set `which`: 0 default, 1 colour-safe).
static func team_set(which := -1) -> Dictionary:
	data()
	return _sets[clampi(teams() if which < 0 else which, 0, _sets.size() - 1)]


## A side's colour (team 0 left / red, team 1 right / blue); clamped, so any team number works.
static func side_color(side: int, which := -1) -> Color:
	var a: Array = team_set(which)["sides"]
	return a[clampi(side, 0, a.size() - 1)]


## A Brawl fighter's own colour, by slot.
static func brawl_color(slot: int, which := -1) -> Color:
	var a: Array = team_set(which)["brawl"]
	return a[posmod(slot, a.size())]


## A fighter's colour from this screen's point of view (main's `_relation`): "self", "ally",
## "enemy"; anything else ("side") is `fallback` (its side's or Brawl colour).
static func rel_color(rel: String, fallback: Color, which := -1) -> Color:
	var s := team_set(which)
	return s[rel] if rel in ["self", "ally", "enemy"] else fallback


## Nobody's: an unclaimed zone or flag.
static func neutral_color(which := -1) -> Color:
	return team_set(which)["neutral"]


## The outline style in use: {} when off, else {"outer": Color or null (the fighter's marker
## colour), "inner": Color or null (none), "alpha"}.
static func outline_style() -> Dictionary:
	var o := outlines()
	if o == Outlines.OFF:
		return {}
	var d: Dictionary = data().get("outlines", {}).get("team" if o == Outlines.TEAM else "high_contrast", {})
	var outer := String(d.get("outer", "team"))
	var inner := String(d.get("inner", ""))
	return {"outer": null if outer == "team" else Color(outer), "inner": null if inner == "" else Color(inner),
		"alpha": float(d.get("alpha", 1.0))}


## One value of the hit-marker style in use (`hit_markers.default` / `.high_contrast`).
static func marker(key: String, fallback = null):
	var block: Dictionary = data().get("hit_markers", {}).get("high_contrast" if markers() == Markers.HIGH_CONTRAST else "default", {})
	return block.get(key, fallback)
