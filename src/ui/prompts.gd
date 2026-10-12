class_name Prompts
extends RefCounted
## Button hints for whichever device the player used last: "A select   B back" on a
## controller, "Enter select   Esc back" on the keyboard (where the mouse works too).

const PAD := {
	"move": "Stick / D-pad move",
	"select": "A select",
	"back": "B back",
	"change": "Left/Right change",
	"resume": "Start resume",
	"rematch": "A rematch",
	"leave": "B leave",
}
const KEYS := {
	"move": "Arrows move",
	"select": "Enter / click select",
	"back": "Esc back",
	"change": "Left/Right change",
	"resume": "Esc resume",
	"rematch": "Enter rematch",
	"leave": "Esc leave",
}


static func line(gamepad: bool, items: Array) -> String:
	var words: Dictionary = PAD if gamepad else KEYS
	var out := PackedStringArray()
	for item in items:
		out.append(String(words.get(item, item)))
	return "     ".join(out)
