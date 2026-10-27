class_name CreditsScreen
extends UiScreen
## Settings > Credits: who made the game, the bought art and the free font it uses, and
## Godot Engine's copyright. Each row's credit shows in the panel on the right; pressing a
## row opens its full text (the licence terms, which files; Godot's MIT licence; the
## third-party notices of the libraries inside the engine) on a scrolling TextPage.
## LICENSES.md at the repo root says the same at length.

## id, the row, the panel's text, and the full page (Godot's pages are built at runtime).
const ENTRIES := [
	{"id": "game", "row": "Ready 4 Rambles",
		"short": "Made by Kevin (Redelements). The fighters, most of the arenas and effects, and all the sound and music are made by the game's own generators.",
		"full": "Ready 4 Rambles\nMade by Kevin (Redelements).\n\nThe fighters, most of the arenas and effects, the logo, and all the sound and music are made by the game's own generators (the scripts in tools/).\n\nThe bought art, the font and the engine are credited on the other rows."},
	{"id": "szadi", "row": "Szadi art",
		"short": "Art by Szadi art: ground tiles and arena pieces from RPG Fantasy Worlds Set 1 (the RPG Worlds bundle) and Fantasy Lands Warrior. szadiart.itch.io",
		"full": "Art by Szadi art\nszadiart.itch.io\n\nRPG Worlds bundle (RPG Fantasy Worlds Set 1) and Fantasy Lands Warrior, bought October 2026.\n\nUsed: the ground tiles, the crack and pit tiles and the arena pieces (boulders, tall grass) of the tiled arenas, cut from Set 1 and recoloured to the game's palette.\n\nLicence: commercial use, editing and selling works made with the art are allowed. Not allowed: reselling the art, original or modified, or using it in a logo, trademark or service mark. The cut files are not covered by the game's own terms and may not be reused."},
	{"id": "kiddolink", "row": "kiddolink",
		"short": "Hit and spell effects from VFX Complete Set Season 1 by kiddolink. kiddolink.itch.io",
		"full": "Effects by kiddolink\nkiddolink.itch.io/vfx-complete-set-season-1-pixel-art\n\nVFX Complete Set Season 1, bought October 2026.\n\nUsed: hit and spell effects, cut to the frames the game plays and recoloured to its palette.\n\nLicence (the itch.io page): commercial use and editing are allowed. Not allowed: reselling or redistributing the pack. The cut files are not covered by the game's own terms and may not be reused."},
	{"id": "font", "row": "m5x7 font",
		"short": "The pixel font m5x7 by Daniel Linssen, public domain (CC0). managore.itch.io/m5x7",
		"full": "Font: m5x7 by Daniel Linssen\nmanagore.itch.io/m5x7\n\nReleased into the public domain under CC0 1.0 Universal (assets/fonts/m5x7-LICENSE.txt). Thank you, Daniel."},
	{"id": "godot", "row": "Godot Engine", "short": "", "full": ""},
	{"id": "notices", "row": "Third-party notices", "short": "", "full": ""},
]

var _rows_by_id := {}


func _init() -> void:
	super()
	logo = true
	crumbs = ["SETTINGS"]
	title = "CREDITS"
	row_width = 150.0
	detail = true
	detail_width = 200.0
	blurb = "Who made the game, and the art, font and engine it is made with. Full licences: LICENSES.md"


func build() -> void:
	for e in ENTRIES:
		var id := String(e["id"])
		var b := add_button(String(e["row"]), func(): open_page(id), short_text(id))
		_rows_by_id[id] = b
	add_space(3)
	add_button("Back", back)


## The panel's text for a row.
static func short_text(id: String) -> String:
	match id:
		"godot":
			return "Made with Godot Engine (godotengine.org), MIT licence. %s Press for the licence." \
				% " ".join(godot_copyright())
		"notices":
			return "Godot Engine is built from %d libraries; their copyright lines and licences. Press to read." \
				% maxi(0, Engine.get_copyright_info().size() - 1)
	for e in ENTRIES:
		if String(e["id"]) == id:
			return String(e["short"])
	return ""


## A row's full page text.
static func full_text(id: String) -> String:
	match id:
		"godot":
			return "Godot Engine\ngodotengine.org/license\n\n" + Engine.get_license_text()
		"notices":
			return third_party_notices()
	for e in ENTRIES:
		if String(e["id"]) == id:
			return String(e["full"])
	return ""


## Godot's copyright lines, from the engine itself ("Copyright (c) 2014-present Godot
## Engine contributors (see AUTHORS.md)." and the one before it).
static func godot_copyright() -> PackedStringArray:
	var out := PackedStringArray()
	for line in Engine.get_license_text().split("\n"):
		if line.strip_edges().begins_with("Copyright"):
			out.append(line.strip_edges())
	return out


## Every component Godot is built from, its copyright and licence, then each licence's
## text: what the engine's licence asks a game to ship.
static func third_party_notices() -> String:
	var parts := PackedStringArray()
	parts.append("THIRD-PARTY NOTICES\n\nGodot Engine includes the following components, under the licences given in full below.\n")
	for comp in Engine.get_copyright_info():
		var lines := PackedStringArray([String(comp["name"])])
		for part in comp["parts"]:
			for c in part["copyright"]:
				lines.append("  (c) " + String(c))
			lines.append("  Licence: " + String(part["license"]))
		parts.append("\n".join(lines) + "\n")
	parts.append("\nLICENCE TEXTS\n")
	var info := Engine.get_license_info()
	for key in info:
		parts.append("--- %s ---\n\n%s\n" % [key, String(info[key])])
	return "\n".join(parts)


## Opens a row's full text.
func open_page(id: String) -> void:
	if stack == null:
		return
	var p := TextPage.new(String(_row_title(_rows_by_id[id])).to_upper(), full_text(id))
	p.crumbs = ["SETTINGS", "CREDITS"]
	stack.push(p)


## The row for `id` ("game", "szadi", "kiddolink", "font", "godot", "notices").
func row(id: String) -> Button:
	return _rows_by_id.get(id)
