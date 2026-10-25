class_name Showcase
extends RefCounted
## Scripted demos that show each fighter's whole kit, and how to answer the big moves.
##   godot --path . -- --showcase=cairn | culvert | craglash | barkley | gillbert | cerebro | hissy | digby | pete | sno | counterplay
## Both fighters are driven by input bitmasks, exactly like players: each "press" step
## mashes its button until that move actually starts, so the combos shown are real
## inputs through the real rules. tests/test_showcase.gd plays every script headless.
##
## Steps (one at a time, in order):
##   wait t               do nothing for t ticks
##   press who bit move   mash `bit` until `who` starts `move` (aim: also hold toward the foe;
##                        hold: also hold "up", "down", "left" or "right"; aim_at: aim
##                        exactly at the other fighter, 360 degrees; strafe: and face it)
##   walk who hold t      hold a direction for t ticks (aim_at / strafe as above)
##   together bits        press [left, right] on the same tick
##   dodge who dir        roll "away" from, "through", or "flank" (up and toward) the other fighter
##   guard who            hold guard until an attack is blocked
##   approach who         walk until in jab range, lined up horizontally
##   until cond           wait for "settled" (both free) or "move:<side>:<id>"
##   place                fade out, repair the floor, put both back at the start, fade in
##                        ("dir": "right" | "up" | "down" puts the right-hand fighter
##                        beside, above or below the left one, facing each other;
##                        "face" turns the left one some other way; "angle" puts the
##                        right-hand fighter at that many degrees, 0 = right, 90 = below;
##                        "restock": true refills Paper Stock sheets, like the energy a
##                        script starts with)
## "part" switches the caption line, "show" highlights an item on it.

const L := SimDefs.IN_LIGHT
const H := SimDefs.IN_HEAVY
const D := SimDefs.IN_DODGE
const S1 := SimDefs.IN_SKILL1
const S2 := SimDefs.IN_SKILL2
const SU := SimDefs.IN_SURGE
const FADE := 14
const HOLD_BITS := {"up": SimDefs.IN_UP, "down": SimDefs.IN_DOWN, "left": SimDefs.IN_LEFT,
	"right": SimDefs.IN_RIGHT}
## A little left of the floor's centre.
const START_X := SimDefs.GRID_X + SimDefs.GRID_COLS * SimDefs.CELL * 0.5 - 30.0
const START_Y := SimDefs.GRID_Y + SimDefs.GRID_ROWS * SimDefs.CELL * 0.5

const SCRIPTS := {
	"cairn": {
		"left": "cairn", "right": "culvert", "energy": [100, 0], "gap": 2.0, "hp": [-1, 120],
		"title": "CAIRN  -  FULL KIT",
		"captions": [
			["Slip counter", "Jab", "Jab", "Cross", "Hook", "Haymaker"],
			["Jab", "Jab", "Cross", "Haymaker", "Rockslide Rush", "Avalanche"],
		],
		"steps": [
			{"do": "wait", "t": 45, "part": 0},
			{"do": "together", "bits": [S1, L], "show": 0},
			{"do": "until", "cond": "move:0:slip_counter"},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 3},
			{"do": "press", "who": 0, "bit": L, "move": "light_4", "show": 4},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 30},
			{"do": "place", "part": 1},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 3},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 4},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 6},
		],
	},
	"culvert": {
		"left": "culvert", "right": "cairn", "energy": [100, 0], "gap": 64.0, "hp": [-1, 100],
		"title": "CULVERT  -  FULL KIT",
		"captions": [
			["Gulp tapped: the tongue hooks from range", "and hauls them in", "Jab", "Jab", "Runoff tapped: a shove"],
			["Jab", "Jab", "Gulp held: swallowed... and out the back end"],
			["Jab", "Jab", "Hook", "Slam", "Runoff (held)", "Storm Drain"],
		],
		"steps": [
			{"do": "wait", "t": 45, "part": 0},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 0},
			{"do": "wait", "t": 30, "show": 1},
			{"do": "until", "cond": "free:0"},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "aim": true, "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 3},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 4},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 1, "gap": 2.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "charge": 24, "show": 2},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40, "show": 3},
			{"do": "place", "part": 2, "gap": 2.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 3},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "charge": 18, "show": 4},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 6},
		],
	},
	"craglash": {
		"left": "craglash", "right": "cairn", "energy": [100, 0], "gap": 2.0, "hp": [-1, 60],
		"title": "CRAGLASH  -  FULL KIT",
		"captions": [
			["Stoneskin (shown on his health bar)", "Mountain Maw: an unblockable hook from far away",
				"Hauled in and crumpled", "Rake (one at a time: 2 s cooldown)", "Rockslide Stomp", "Landslide Charge"],
			["Landslide Ram: his roll is a shoulder charge", "It hits, stops, and the Rake links",
				"Into the wall: it cracks the floor"],
			["Bedrock (Surge): armor, and the taunted are dragged in", "Jabs only chip him",
				"Any attack answers out of it: Rockslide Stomp", "Landslide Charge: a short stun"],
		],
		"steps": [
			{"do": "wait", "t": 50, "part": 0, "show": 0},
			{"do": "place", "part": 0, "gap": 100.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 1},
			{"do": "wait", "t": 30, "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 3},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 4},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 1, "gap": 60.0},
			{"do": "wait", "t": 20},
			{"do": "dodge", "who": 0, "dir": "through", "show": 0},
			{"do": "wait", "t": 8, "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_1"},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 30},
			{"do": "place", "part": 1, "gap": 60.0},
			{"do": "walk", "who": 0, "hold": "left", "t": 60, "show": 2},
			{"do": "wait", "t": 70},
			{"do": "dodge", "who": 0, "dir": "away"},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 2, "gap": 70.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 0},
			{"do": "wait", "t": 90},
			{"do": "press", "who": 1, "bit": L, "move": "light_1", "show": 1},
			{"do": "wait", "t": 40},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 2},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 3},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 120},
		],
	},
	"barkley": {
		"left": "barkley", "right": "cairn", "energy": [100, 0], "gap": 22.0, "hp": [-1, 100],
		"title": "BARKLEY  -  FULL KIT",
		"captions": [
			["Branch Grab: pulls in", "Twig Swipe", "Bough Swing", "Log Drop", "Timber Twister", "Pinecone Bomb"],
			["Twig", "Bough", "Log Drop", "Timber Twister", "Branch Grab", "Root Eruption"],
		],
		"steps": [
			{"do": "wait", "t": 45, "part": 0},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 0},
			{"do": "until", "cond": "free:0"},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 3},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 4},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 1, "gap": 2.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 3},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 4},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 6},
		],
	},
	"gillbert": {
		"left": "gillbert", "right": "cairn", "energy": [100, 0], "gap": 80.0, "hp": [-1, 75],
		"title": "GILLBERT  -  FULL KIT",
		"captions": [
			["Cast Line: throws the rod, reels him in", "Snout Jab", "Tail Whip", "Rod Flail", "Splash Zone",
				"Flop Dash"],
			["Jab", "Whip", "Rod Flail", "Splash Zone", "Flop Dash", "The One That Got Away"],
		],
		"steps": [
			{"do": "wait", "t": 45, "part": 0},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 0},
			{"do": "until", "cond": "free:0"},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 3},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 4},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 1, "gap": 2.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 3},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 4},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 6},
		],
	},
	"cerebro": {
		"left": "cerebro", "right": "cairn", "energy": [100, 0], "gap": 86.0, "hp": [-1, 70],
		"title": "CHEF CEREBRO  -  FULL KIT",
		"captions": [
			["From range:", "Knife Flick", "Backhand Flick", "Mallet Toss", "Cleaver Toss"],
			["Dodge: he teleports", "away", "and back"],
			["Up close:", "Flick", "Flick", "Mallet", "Tenderize (softens them up)", "Cleaver Toss"],
			["Flick", "Flick", "Mallet", "Flip Out", "Knife Flurry"],
		],
		"steps": [
			{"do": "wait", "t": 45, "part": 0, "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 3},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 4},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40, "part": 1, "show": 0},
			{"do": "dodge", "who": 0, "dir": "up", "show": 1},
			{"do": "wait", "t": 50},
			{"do": "dodge", "who": 0, "dir": "down", "show": 2},
			{"do": "wait", "t": 50},
			{"do": "place", "part": 2, "gap": 2.0},
			{"do": "wait", "t": 20, "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 3},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 4},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 3, "gap": 2.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 3},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 4},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 5},
		],
	},
	"hissy": {
		"left": "hissy", "right": "cairn", "energy": [100, 0], "gap": 70.0, "hp": [-1, 85],
		"title": "HISSY FITZ  -  FULL KIT",
		"captions": [
			["Stone Gaze: slows whoever looks at her", "Cairn walks in, slowed", "Snake Jab", "Snake Jab",
				"Hair Lash"],
			["Jab", "Jab", "Lash", "Coil Uppercut", "Venom Spit (poison)", "Petrify Punch",
				"Shatter the statue: Jab", "Jab", "Lash", "Coil Uppercut"],
		],
		"steps": [
			{"do": "wait", "t": 40, "part": 0},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 0},
			{"do": "wait", "t": 30},
			{"do": "approach", "who": 1, "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 3},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 4},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 1, "gap": 2.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 3},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 4},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 5},
			{"do": "until", "cond": "free:0"},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 6},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 7},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 8},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 9},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 10},
		],
	},
	"digby": {
		"left": "digby", "right": "cairn", "energy": [100, 0], "gap": 30.0, "hp": [-1, 65],
		"title": "DIGBY  -  FULL KIT",
		"captions": [
			["Headlamp Flash: Cairn is blinded", "His next jab misses", "Claw Swipe", "Claw Swipe",
				"Pickaxe Swing", "Pickaxe Pop-Up"],
			["Burrow: tunnels under, out of reach", "Pops up under Cairn"],
			["Swipe", "Swipe", "Pickaxe", "Pop-Up", "Cave-In: rooted in place"],
		],
		"steps": [
			{"do": "wait", "t": 40, "part": 0},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 0},
			{"do": "until", "cond": "free:0"},
			{"do": "approach", "who": 1, "show": 1},
			{"do": "press", "who": 1, "bit": L, "move": "light_1"},
			{"do": "until", "cond": "free:1"},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 3},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 4},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 5},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 1, "gap": 96.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 0},
			{"do": "wait", "t": 46, "show": 1},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 30},
			{"do": "place", "part": 2, "gap": 2.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 3},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 4},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 5},
		],
	},
	"pete": {
		"left": "pete", "right": "cairn", "energy": [100, 0], "gap": 100.0, "hp": [-1, 60],
		"title": "SNEAKY PETE  -  FULL KIT",
		"captions": [
			["Tiptoe: invisible and quick", "Sneaks right up", "Sucker Punch", "Cheap Shot", "Bag Swing",
				"Sack Smack", "Pickpocket: steals his power"],
			["The Big Heist: vanishes...", "...and robs him from behind"],
		],
		"steps": [
			{"do": "wait", "t": 40, "part": 0},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 0},
			{"do": "until", "cond": "free:0"},
			{"do": "approach", "who": 0, "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 3},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 4},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 5},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 6},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 1, "gap": 60.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 0},
			{"do": "wait", "t": 24, "show": 1},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 2},
		],
	},
	"crease": {
		"left": "crease", "right": "cairn", "energy": [100, 0], "gap": 110.0, "hp": [-1, 140],
		"title": "MISTER CREASE  -  FULL KIT",
		"captions": [
			["Paper Stock: three sheets", "Fold a Crane", "Fold a Shuriken", "Fold a Frog", "All three in hand"],
			["Paper Cut", "Paper Cut", "Paper Cut", "Paper Shuriken: a bleeding cut", "Paper Crane: it homes in"],
			["Paper Frog: three frogs, shove and slow", "Paper Plane: glide away"],
			["Thousand Cranes: a storm of paper"],
		],
		"steps": [
			{"do": "wait", "t": 45, "part": 0, "show": 0},
			{"do": "press", "who": 0, "bit": S1, "move": "fold_skill_1", "show": 1},
			{"do": "until", "cond": "free:0"},
			{"do": "press", "who": 0, "bit": H, "move": "fold_heavy", "show": 2},
			{"do": "until", "cond": "free:0"},
			{"do": "press", "who": 0, "bit": S2, "move": "fold_skill_2", "show": 3},
			{"do": "until", "cond": "free:0"},
			{"do": "wait", "t": 50, "show": 4},
			{"do": "place", "part": 1, "gap": 80.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 3},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 4},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 50},
			{"do": "place", "part": 2, "gap": 120.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 0},
			{"do": "until", "cond": "free:0"},
			{"do": "wait", "t": 10},
			{"do": "dodge", "who": 0, "dir": "away", "show": 1},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 30},
			{"do": "place", "part": 3, "gap": 100.0, "restock": true},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 0},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 170},
		],
	},
	"sno": {
		"left": "sno", "right": "cairn", "energy": [100, 0], "gap": 30.0, "hp": [-1, 108],
		"title": "SNO MERCY  -  FULL KIT",
		"captions": [
			["Syrup Slick: a sticky puddle", "Cairn wades in, slowed", "Cold Cross", "Cold Cross", "Brain Freeze",
				"Shaved Ice Spray", "Slush Slide"],
			["Jab", "Cross", "Brain Freeze", "Shaved Ice", "Flavor Blast: frozen solid", "Shatter the ice: jab",
				"Cross", "Brain Freeze", "Shaved Ice"],
		],
		"steps": [
			{"do": "wait", "t": 40, "part": 0},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 0},
			{"do": "until", "cond": "free:0"},
			{"do": "approach", "who": 1, "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 3},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 4},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 5},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 6},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 1, "gap": 2.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 0, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 3},
			{"do": "press", "who": 0, "bit": SU, "move": "surge", "show": 4},
			{"do": "until", "cond": "free:0"},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 5},
			{"do": "press", "who": 0, "bit": L, "move": "light_1"},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 8},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 150, "show": 9},
		],
	},
	"angles": {
		"left": "craglash", "right": "cairn", "energy": [100, 0], "gap": 4.0, "dir": "down",
		"title": "ALL ANGLES  -  FIGHTING UP AND DOWN",
		"captions": [
			["Facing down: Rake", "Rockslide Stomp", "Landslide Charge"],
			["Facing up: Rake", "Landslide Charge"],
			["Cairn from above: Jab", "Jab", "Cross", "Hook", "Haymaker"],
			["Mountain Maw (the hook), straight at the camera"],
			["Combos steer: Rake to the right", "turn down: Rockslide Stomp"],
		],
		"steps": [
			{"do": "wait", "t": 40, "part": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "show": 1},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 2},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 30},
			{"do": "place", "part": 1, "dir": "up"},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "show": 1},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 30},
			{"do": "place", "part": 2, "dir": "up"},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 1, "bit": L, "move": "light_1", "show": 0},
			{"do": "press", "who": 1, "bit": L, "move": "light_2", "show": 1},
			{"do": "press", "who": 1, "bit": L, "move": "light_3", "show": 2},
			{"do": "press", "who": 1, "bit": L, "move": "light_4", "show": 3},
			{"do": "press", "who": 1, "bit": H, "move": "heavy", "show": 4},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 30},
			{"do": "place", "part": 3, "dir": "down", "gap": 18.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 0},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 60},
			{"do": "place", "part": 4, "dir": "down", "face": "right"},
			{"do": "wait", "t": 30},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "hold": "right", "show": 0},
			{"do": "press", "who": 0, "bit": H, "move": "heavy", "hold": "down", "show": 1},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 70},
		],
	},
	"twinstick": {
		"left": "craglash", "right": "cairn", "energy": [0, 0], "gap": 30.0,
		"title": "TWIN-STICK  -  360 AIM AND STRAFE",
		"captions": [
			["Strafe: back off while facing Cairn"],
			["360 aim: Landslide Charge at an odd angle"],
			["Circle and keep facing", "Rake", "Landslide Charge"],
		],
		"steps": [
			{"do": "wait", "t": 30, "part": 0},
			{"do": "walk", "who": 0, "hold": "left", "strafe": true, "t": 50, "show": 0},
			{"do": "walk", "who": 0, "hold": "up", "strafe": true, "t": 30},
			{"do": "wait", "t": 20},
			{"do": "place", "part": 1, "angle": 22.0, "gap": 32.0},
			{"do": "wait", "t": 20},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "aim_at": true, "show": 0},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40},
			{"do": "place", "part": 2, "angle": -60.0, "gap": 4.0},
			{"do": "wait", "t": 20},
			{"do": "walk", "who": 0, "hold": "left", "strafe": true, "t": 12, "show": 0},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "aim_at": true, "show": 1},
			{"do": "press", "who": 0, "bit": S1, "move": "skill_1", "aim_at": true, "show": 2},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 60},
		],
	},
	"counterplay": {
		"left": "cairn", "right": "culvert", "energy": [0, 100], "gap": 2.0,
		"title": "COUNTERPLAY  -  READ THE WINDUP",
		"captions": [
			["Raw Gulp winds up red: unblockable", "Roll through it", "Punish: Jab, Jab, Cross, Rush"],
			["Storm Drain cut-in", "Roll into his side lane, then punish", "No damage taken"],
			["Raw Rush glows gold: blockable", "Guard it", "Punish: Jab, Jab, held Gulp"],
		],
		"steps": [
			{"do": "wait", "t": 45, "part": 0},
			{"do": "press", "who": 1, "bit": S1, "move": "skill_1", "show": 0},
			{"do": "wait", "t": 12},  # about a human reaction time
			{"do": "dodge", "who": 0, "dir": "through", "show": 1},
			{"do": "until", "cond": "free:0"},
			{"do": "press", "who": 0, "bit": L, "move": "light_1", "aim": true, "show": 2},
			{"do": "press", "who": 0, "bit": L, "move": "light_2"},
			{"do": "press", "who": 0, "bit": L, "move": "light_3"},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2"},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 40, "show": 3},
			{"do": "place", "part": 1, "gap": 22.0},
			{"do": "wait", "t": 25},
			{"do": "press", "who": 1, "bit": SU, "move": "surge", "show": 0},
			{"do": "wait", "t": 24},  # the freeze (23) plus a tick: i-frames cover the hit, the roll ends in his side lane
			{"do": "dodge", "who": 0, "dir": "flank", "show": 1},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 50, "show": 2},
			{"do": "place", "part": 2, "gap": 34.0},
			{"do": "wait", "t": 25},
			{"do": "press", "who": 0, "bit": S2, "move": "skill_2", "show": 0},
			{"do": "wait", "t": 9},
			{"do": "guard", "who": 1, "show": 1},
			{"do": "press", "who": 1, "bit": L, "move": "light_1", "show": 2},
			{"do": "press", "who": 1, "bit": L, "move": "light_2"},
			{"do": "press", "who": 1, "bit": S1, "move": "skill_1", "charge": 24},
			{"do": "until", "cond": "settled"},
			{"do": "wait", "t": 60, "show": 3},
		],
	},
}

var name := ""
var script_def: Dictionary
var step := 0
var finished := false
var failed := ""  ## set when a step couldn't complete, for tests
var part := 0
var show := -1
var fade := 0.0  ## 0..1 black overlay for scene changes

var _t := 0
var _serial := -1
var _phase := 0


static func names() -> Array:
	return SCRIPTS.keys()


## A named showcase, or a script built on the fly (Combo Trials make their demos this way).
func _init(p_name: String, p_def: Dictionary = {}) -> void:
	name = p_name
	script_def = p_def if not p_def.is_empty() else SCRIPTS[p_name]


## The match this showcase starts from: two fighters close together, centre stage.
func build() -> MatchSim:
	var sim := MatchFactory.versus(String(script_def["left"]), String(script_def["right"]))
	_place(sim, float(script_def.get("gap", 2.0)), String(script_def.get("dir", "right")))
	var energy: Array = script_def.get("energy", [0, 0])
	var hp: Array = script_def.get("hp", [-1, -1])
	for i in 2:
		sim.creatures[i].energy = float(energy[i])
		if float(hp[i]) > 0.0:
			sim.creatures[i].hp = float(hp[i])
	return sim


func title() -> String:
	return String(script_def["title"])


func caption_items() -> Array:
	var caps: Array = script_def["captions"]
	return caps[clampi(part, 0, caps.size() - 1)]


## Inputs for both fighters this tick. Call once per simulation step.
func inputs(sim: MatchSim) -> PackedInt32Array:
	var out := PackedInt32Array([0, 0])
	var steps: Array = script_def["steps"]
	if finished or step >= steps.size():
		finished = true
		return out
	var s: Dictionary = steps[step]
	if s.has("part") and _t == 0 and _phase == 0:
		part = int(s["part"])
		show = -1
	if s.has("show"):
		show = int(s["show"])
	_t += 1
	var done := false
	match String(s["do"]):
		"wait":
			done = _t >= int(s["t"])
		"together":
			var b: Array = s["bits"]
			out[0] = int(b[0])
			out[1] = int(b[1])
			done = true
		"press":
			var who := int(s["who"])
			var c := sim.creatures[who]
			if _t == 1:
				_serial = c.attack_serial
			if c.attack_serial != _serial and c.move_id == String(s["move"]):
				# "charge": keep the button held this many ticks into the move (a held Gulp).
				if int(s.get("charge", 0)) > _phase:
					_phase += 1
					out[who] = int(s["bit"]) | _aim_bits(sim, who, s)
				else:
					done = true
			else:
				var bits := int(s["bit"]) if _t % 2 == 1 else 0
				if bool(s.get("aim", false)):
					bits |= _toward(sim, who)
				if s.has("hold"):
					bits |= HOLD_BITS[String(s["hold"])]
				bits |= _aim_bits(sim, who, s)
				out[who] = bits
				if _t > 150:
					_fail("never started %s (in %s, state %d)" % [s["move"], c.move_id, c.state])
					done = true
		"walk":
			var who := int(s["who"])
			out[who] = int(HOLD_BITS.get(String(s.get("hold", "")), 0)) | _aim_bits(sim, who, s)
			done = _t >= int(s["t"])
		"dodge":
			var who := int(s["who"])
			var c := sim.creatures[who]
			var o := sim.creatures[1 - who]
			var away := (c.pos - o.pos).normalized()
			var dir := -away if String(s["dir"]) == "through" else away
			if String(s["dir"]) == "flank":
				dir = (-away + Vector2(0, -1)).normalized()  # up and toward him: lands in his side lane
			if HOLD_BITS.has(String(s["dir"])):
				dir = SimDefs.dir_from_bits(HOLD_BITS[String(s["dir"])])
			out[who] = D | SimDefs.bits_from_dir(dir)
			done = true
		"guard":
			var who := int(s["who"])
			out[who] = SimDefs.IN_GUARD
			done = sim.creatures[who].guard_hit > 0
			if _t > 120:
				_fail("nothing was blocked")
				done = true
		"approach":
			var who := int(s["who"])
			var c := sim.creatures[who]
			var o := sim.creatures[1 - who]
			var d := o.pos - c.pos
			var reach := c.radius + o.radius + 4.0
			if absf(d.y) > 3.0:
				out[who] = SimDefs.bits_from_dir(Vector2(0, signf(d.y)))
			elif absf(d.x) > reach:
				out[who] = SimDefs.bits_from_dir(Vector2(signf(d.x), 0))
			else:
				done = true
			if _t > 300:
				_fail("couldn't reach the other fighter")
				done = true
		"until":
			done = _check(sim, String(s["cond"]))
			if _t > 600:
				_fail("timed out waiting for " + String(s["cond"]))
				done = true
		"place":
			# Fade to black, reset positions, fade back in.
			if _t <= FADE:
				fade = float(_t) / FADE
			elif _t == FADE + 1:
				_place(sim, float(s.get("gap", script_def.get("gap", 2.0))), String(s.get("dir", "right")),
					float(s.get("angle", NAN)))
				if s.has("face"):
					sim.creatures[0].facing = SimDefs.dir_from_bits(HOLD_BITS[String(s["face"])])
				if bool(s.get("restock", false)):
					for c in sim.creatures:
						c.sheets = int(c.def.get("sheets", {}).get("max", 0))
				# Repair the floor so leftover pits don't swallow anyone.
				sim.terrain.cells.fill(0)
				sim.terrain.timers.fill(0)
				sim.terrain.version += 1
				fade = 1.0
			elif _t <= FADE * 2 + 1:
				fade = 1.0 - float(_t - FADE - 1) / FADE
			else:
				fade = 0.0
				done = true
	if done:
		step += 1
		_t = 0
		_phase = 0
		if step >= steps.size():
			finished = true
	return out


func _check(sim: MatchSim, cond: String) -> bool:
	if sim.hitstop > 0 and not cond.begins_with("move:"):
		return false
	if cond == "settled":
		return _free(sim.creatures[0]) and _free(sim.creatures[1])
	if cond.begins_with("free:"):
		return _free(sim.creatures[int(cond.get_slice(":", 1))])
	if cond.begins_with("move:"):
		var c := sim.creatures[int(cond.get_slice(":", 1))]
		return c.state == CreatureSim.State.ATTACK and c.move_id == cond.get_slice(":", 2)
	return true


## Not attacking, stunned, down, airborne, falling or rolling (a KO counts as done).
func _free(c: CreatureSim) -> bool:
	if c.state == CreatureSim.State.KO:
		return true
	return c.state in [CreatureSim.State.IDLE, CreatureSim.State.MOVE, CreatureSim.State.GUARD] \
		and c.invuln == 0


func _toward(sim: MatchSim, who: int) -> int:
	var d := sim.creatures[1 - who].pos - sim.creatures[who].pos
	return SimDefs.bits_from_dir(d.normalized())


## The exact aim (and strafe) bits a step asks for: at the other fighter, 360 degrees.
func _aim_bits(sim: MatchSim, who: int, s: Dictionary) -> int:
	if not (bool(s.get("aim_at", false)) or bool(s.get("strafe", false))):
		return 0
	var b := SimDefs.aim_bits(sim.creatures[1 - who].pos - sim.creatures[who].pos)
	if bool(s.get("strafe", false)):
		b |= SimDefs.IN_STRAFE
	return b


func _place(sim: MatchSim, gap: float, dir := "right", angle := NAN) -> void:
	var a := sim.creatures[0]
	var b := sim.creatures[1]
	var d := {"right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}.get(dir, Vector2.RIGHT) as Vector2
	if not is_nan(angle):
		d = Vector2.from_angle(deg_to_rad(angle))
	a.pos = Vector2(START_X, START_Y if d.y >= 0.0 else START_Y + 30.0)
	b.pos = a.pos + d * (a.radius + b.radius + gap)
	a.facing = SimDefs.aim_from_bits(SimDefs.aim_bits(d))  # one of the 64 aim directions
	b.facing = SimDefs.aim_from_bits(SimDefs.aim_bits(-d))
	for c in [a, b]:
		c.knock_vel = Vector2.ZERO
		c.walk_vel = Vector2.ZERO


func _fail(msg: String) -> void:
	if failed == "":
		failed = "step %d: %s" % [step, msg]
	push_warning("Showcase %s: %s" % [name, failed])
