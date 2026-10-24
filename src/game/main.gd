extends Node2D
## Scene flow: menu, versus rounds against the CPU (or CPU vs CPU), and training.
##
## Each physics tick (60 Hz) this script gathers one input bitmask per fighter (from the
## keyboard/gamepad, a CPU controller or the training dummy), steps the simulation
## once, then lets the views catch up. The simulation never touches nodes, so the same
## code runs headless in tests.
##
## Command-line options (after `--`):
##   --mode=N              skip the menu: 0 Cairn vs CPU, 1 Culvert vs CPU, 2 CPU vs CPU,
##                         3 training as Cairn, 4 training as Culvert
##   --level=N             CPU level: 0 Easy, 1 Normal, 2 Hard
##   --seed=N              CPU random seed
##   --arena=ID            the arena map for offline matches (stadium, quarry, floodgate,
##                         greenhouse; data/arenas/)
##   --autoplay            training demo: the player side follows a scripted routine
##   --dummy-mode=N        0 stand, 1 guard, 2 walk, 3 dodge
##   --training-flags=no_cooldowns,full_energy  training options on (pause > Training options)
##   --training-screen=pause|options|fighters  open the training pause menu, its Training
##                         options page or the Change fighter grid once training starts (captures)
##   --hitboxes            start with the hitbox overlay on
##   --range-rings         start with the range rings on (Settings > Controls; F7 in a fight)
##   --shots=60,120        save screenshots at those frame numbers
##   --shot-dir=PATH       where screenshots go (default user://shots)
##   --quit-after=N        exit after N frames
##   --perf                log frame and tick times during fights; on quit, prints the
##                         percentiles and saves them to user://perf.txt
##   --cpu-threads=off     CPU players think one after another on the main thread
##                         (default: together on the worker threads; same answers)
##   --layout=league|classic  keyboard layout (saved in the menu otherwise)
##   --pad-layout=standard|twinstick  controller layout (saved in Settings otherwise)
##   --showcase=NAME       play one scripted demo on a loop: cairn, culvert, craglash, barkley, gillbert,
##                         cerebro, hissy, digby, pete, sno, angles, twinstick or counterplay
##   --teams=a,b,c:d,e,f   Duel / 2-player teams (default cerebro,gillbert,barkley:culvert,cerebro,craglash)
##   --pick                show the team pick screen even with --mode
##   --cpu-vs-cpu          every player side is played by the CPU (demos, captures)
##   --view-team=N         show the match as team N sees it (brush, fences, walls hide
##                         foes), even with nobody playing here (captures of --cpu-vs-cpu)
##   --menu=PAGE           open a menu page: main, single, single:<group>, settings, game, video, audio, controls,
##                         remap:classic|league|gamepad (captures)
##   --online-host[=PORT]  host an online 1v1 straight away (UDP, default port 7777)
##   --online-join=ADDR[:PORT][/ROOM]  join one, or a dedicated server (ROOM: meet a friend there)
##   --online-watch=ADDR[:PORT][/ROOM] watch a server's match (a room's, from match to match)
##   --server[=PORT]       run as a dedicated server (with --headless); --max-players=N
##   --fighter=ID          your fighter online
##   --online-size=N       with --online-join to a server: 2, 3 or 4 asks for a 2v2 / 3v3 / 4v4 (4: Capture the Flag)
##   --net-lag=N --net-loss=F   hold back / drop the input stream (feel rollback on a LAN)
##   --net-delay=N         force the input delay (frames) instead of picking it from the ping
##   --net-report=PATH     write the online match's report (inputs, state fingerprints) on exit; after a
##                         rematch or a room's next match, each earlier one is kept as PATH_m<n>.json
##   --net-no-pick[=N]     with --cpu-vs-cpu: don't lock in for a 1v1 rematch (the first N, or every
##                         one), so the pick's countdown locks the last fighter in (tests, captures)

enum Flow { MENU, INTRO, FIGHT, ROUND_OVER, MATCH_OVER, SELECT, LOBBY }
enum Side { PLAYER, CPU, DUMMY, SCRIPT, PLAYER2, REMOTE, PLAYER3, PLAYER4, REPLAY }
const LOCAL_SIDES := [Side.PLAYER, Side.PLAYER2, Side.PLAYER3, Side.PLAYER4]

const MODES := [
	{"label": "Cairn  vs  CPU Culvert", "left": "cairn", "right": "culvert", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Culvert  vs  CPU Cairn", "left": "culvert", "right": "cairn", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Watch: CPU vs CPU", "left": "cairn", "right": "culvert", "sides": [Side.CPU, Side.CPU]},
	{"label": "Training: Cairn", "left": "cairn", "training": true},
	{"label": "Training: Culvert", "left": "culvert", "training": true},
	{"label": "Watch: combo showcases", "showcase": true},
	{"label": "Duel: you vs CPU  (3v3 tag)", "duel": true, "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Duel: 2 players  (3v3 tag)", "duel": true, "sides": [Side.PLAYER, Side.PLAYER2]},
	{"label": "Versus: 2 players", "versus2p": true, "sides": [Side.PLAYER, Side.PLAYER2]},
	{"label": "Combo Trials", "trials": true, "sides": [Side.PLAYER, Side.SCRIPT]},
	{"label": "Reaction Drill: read Culvert", "drill": "culvert", "sides": [Side.PLAYER, Side.SCRIPT]},
	{"label": "Reaction Drill: read Cairn", "drill": "cairn", "sides": [Side.PLAYER, Side.SCRIPT]},
	{"label": "Craglash  vs  CPU Cairn", "left": "craglash", "right": "cairn", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Training: Craglash", "left": "craglash", "training": true},
	{"label": "Barkley  vs  CPU Craglash", "left": "barkley", "right": "craglash", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Training: Barkley", "left": "barkley", "training": true},
	{"label": "Gillbert  vs  CPU Barkley", "left": "gillbert", "right": "barkley", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Training: Gillbert", "left": "gillbert", "training": true},
	{"label": "Chef Cerebro  vs  CPU Gillbert", "left": "cerebro", "right": "gillbert", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Training: Chef Cerebro", "left": "cerebro", "training": true},
	{"label": "Online 1v1", "online": true},
	{"label": "Hissy Fitz  vs  CPU Chef Cerebro", "left": "hissy", "right": "cerebro", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Training: Hissy Fitz", "left": "hissy", "training": true},
	{"label": "Digby  vs  CPU Hissy Fitz", "left": "digby", "right": "hissy", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Training: Digby", "left": "digby", "training": true},
	{"label": "Sneaky Pete  vs  CPU Digby", "left": "pete", "right": "digby", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Training: Sneaky Pete", "left": "pete", "training": true},
	{"label": "Sno Mercy  vs  CPU Sneaky Pete", "left": "sno", "right": "pete", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Training: Sno Mercy", "left": "sno", "training": true},
	{"label": "Team battle: 2v2 vs CPU", "team": 2, "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Team battle: 3v3 vs CPU", "team": 3, "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Team Deathmatch: 2v2 vs CPU", "team": 2, "deathmatch": true, "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Team Deathmatch: 3v3 vs CPU", "team": 3, "deathmatch": true, "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Sinkhole: 1v1 vs CPU", "team": 1, "rules": "sinkhole", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Sinkhole: 2v2 vs CPU", "team": 2, "rules": "sinkhole", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Sinkhole: 3v3 vs CPU", "team": 3, "rules": "sinkhole", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "King of the Crater: 1v1 vs CPU", "team": 1, "rules": "crater", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "King of the Crater: 2v2 vs CPU", "team": 2, "rules": "crater", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "King of the Crater: 3v3 vs CPU", "team": 3, "rules": "crater", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Arcade", "arcade": true, "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Gauntlet", "gauntlet": true, "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Daily Challenge", "daily": true, "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Brawl: 2 players", "brawl": true, "sides": [Side.PLAYER, Side.PLAYER2, Side.CPU, Side.CPU]},
	{"label": "Brawl: 3 players", "brawl": true, "sides": [Side.PLAYER, Side.PLAYER2, Side.PLAYER3, Side.CPU]},
	{"label": "Brawl: 4 players", "brawl": true, "sides": [Side.PLAYER, Side.PLAYER2, Side.PLAYER3, Side.PLAYER4]},
	{"label": "Brawl: you vs 3 CPUs", "brawl": true, "sides": [Side.PLAYER, Side.CPU, Side.CPU, Side.CPU]},
	{"label": "Chaos Cup", "brawl": true, "chaos": true, "sides": [Side.PLAYER, Side.CPU, Side.CPU, Side.CPU]},
	{"label": "Replay", "replay": true, "sides": []},
	{"label": "Mister Crease  vs  CPU Chef Cerebro", "left": "crease", "right": "cerebro", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Training: Mister Crease", "left": "crease", "training": true},
	{"label": "Caravan: 2v2 vs CPU", "team": 2, "rules": "caravan", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Caravan: 3v3 vs CPU", "team": 3, "rules": "caravan", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Capture the Flag: 3v3 vs CPU", "team": 3, "rules": "ctf", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Capture the Flag: 4v4 vs CPU", "team": 4, "rules": "ctf", "sides": [Side.PLAYER, Side.CPU]},
]
const REPLAY_MODE := 47
## The menus (src/ui screens): the title menu opens Single player (MENU_ROWS), the online
## screen, or Settings. MODES indexes stay stable for --mode=N; rows with choices pick
## one of several modes with Left/Right.
## The Settings pages and their rows, in order (see _setting()).
const SETTING_PAGES := {
	"game": ["level", "rumble", "shake", "discord", "server", "delay"],
	"video": ["fullscreen", "wide", "vsync", "fps", "font", "perf_overlay"],
	"audio": ["vol_Master", "vol_Music", "vol_Effects", "vol_Menu"],
}
const SHAKE_CHOICES := [["Full", 1.0], ["Reduced", 0.5], ["Off", 0.0]]
const VOLUME_NAMES := {"Master": "Master volume", "Music": "Music", "Effects": "Sound effects",
	"Menu": "Menu sounds"}
## Volume steps in Settings (10 steps of 10%).
const VOLUME_STEP := 0.1
const ONLINE_MODE := 20
## Single player is a hub of pages; every MENU_ROWS entry names its page by "group".
const MENU_GROUPS := [
	{"id": "cpu", "title": "Fight the CPU", "sub": "Versus rounds as any fighter, or a 3v3 tag Duel",
		"desc": "The classic fights against the CPU at the level set in Settings"},
	{"id": "team", "title": "Team battles", "sub": "Six modes from 1v1 to 4v4, CPU teammates beside you",
		"desc": "Everyone on the field at once; pick the rules and the team size"},
	{"id": "challenge", "title": "Challenges", "sub": "Arcade, Gauntlet, the Daily, Combo Trials, Reaction Drills",
		"desc": "Runs and lessons with something to clear or beat"},
	{"id": "brawl", "title": "Brawl", "sub": "Free-for-all for up to four, and the Chaos Cup",
		"desc": "Four fighters, one life each, CPUs in the empty seats"},
	{"id": "local", "title": "Two players", "sub": "Duel or Versus on one screen (Brawl seats up to four)",
		"desc": "A second controller for player 2"},
	{"id": "practice", "title": "Practice and watch", "sub": "Training dummy, showcases, your saved replays",
		"desc": "Learn a fighter, or sit back"},
]
const MENU_ROWS := [
	{"label": "Duel: you vs CPU  (3v3 tag)", "group": "cpu", "modes": [6], "desc": "Teams of three; tag fighters in and out"},
	{"label": "Duel: 2 players", "group": "local", "modes": [7], "desc": "Teams of three, two players on one screen"},
	{"label": "Team battle vs CPU", "group": "team", "modes": [29, 30], "choices": ["2 v 2", "3 v 3"],
		"desc": "Everyone on the field at once, CPU teammates beside you. Left/Right: team size"},
	{"label": "Team Deathmatch vs CPU", "group": "team", "modes": [31, 32], "choices": ["2 v 2", "3 v 3"],
		"desc": "Unlimited respawns: first team to 12 KOs (15 in 3 v 3) wins. Left/Right: team size"},
	{"label": "Sinkhole vs CPU", "group": "team", "modes": [33, 34, 35], "choices": ["1 v 1", "2 v 2", "3 v 3"],
		"desc": "The floor falls away from the edges into a chasm, and falling in is a KO. Last one standing. Left/Right: team size"},
	{"label": "King of the Crater vs CPU", "group": "team", "modes": [36, 37, 38], "choices": ["1 v 1", "2 v 2", "3 v 3"],
		"desc": "Hold the zone while it moves and the ground round it breaks. 60 s held wins. Left/Right: team size"},
	{"label": "Capture the Flag vs CPU", "group": "team", "modes": [52, 53], "choices": ["3 v 3", "4 v 4"],
		"desc": "Take their flag from their keep and bring it home while yours is safe. First to 3 captures. Left/Right: team size"},
	{"label": "Caravan vs CPU", "group": "team", "modes": [51, 50], "choices": ["3 v 3", "2 v 2"],
		"desc": "Escort the caravan down the pass; then defend while they push. Faster finish or further push wins. Left/Right: team size"},
	{"label": "Brawl", "group": "brawl", "modes": [45, 42, 43, 44], "choices": ["you vs 3 CPUs", "2 players", "3 players", "4 players"],
		"desc": "Free-for-all, four fighters, one life each; CPUs fill the empty seats. Left/Right: how many play"},
	{"label": "Chaos Cup", "group": "brawl", "modes": [46],
		"desc": "A Brawl with three random mutators stacked on: low gravity, Surge rush, a floor of pits, haste, glass cannon"},
	{"label": "Replay theater", "group": "practice", "screen": "replays", "desc": "Watch the fights you saved with F6"},
	{"label": "Versus: 2 players", "group": "local", "modes": [8], "desc": "One fighter each, two players on one screen"},
	{"label": "Versus CPU", "group": "cpu", "modes": [0, 1, 12, 14, 16, 18, 21, 23, 25, 27, 48],
		"desc": "Best of three rounds against the CPU. Left/Right: your fighter",
		"choices": ["as Cairn", "as Culvert", "as Craglash", "as Barkley", "as Gillbert", "as Chef Cerebro",
			"as Hissy Fitz", "as Digby", "as Sneaky Pete", "as Sno Mercy", "as Mister Crease"]},
	{"label": "Arcade", "group": "challenge", "modes": [39], "fighter_choice": true,
		"desc": "Five fights up the roster, then a boss team in a 3v3 Duel. Clears unlock palettes (F5 in a fight). Left/Right: your fighter",
		"choices": ["as Cairn", "as Culvert", "as Craglash", "as Barkley", "as Gillbert", "as Chef Cerebro",
			"as Hissy Fitz", "as Digby", "as Sneaky Pete", "as Sno Mercy", "as Mister Crease"]},
	{"label": "Gauntlet", "group": "challenge", "modes": [40], "fighter_choice": true,
		"desc": "Endless waves, harder every two, your health carrying over. How many can you clear? Left/Right: your fighter",
		"choices": ["as Cairn", "as Culvert", "as Craglash", "as Barkley", "as Gillbert", "as Chef Cerebro",
			"as Hissy Fitz", "as Digby", "as Sneaky Pete", "as Sno Mercy", "as Mister Crease"]},
	{"label": "Daily Challenge", "group": "challenge", "modes": [41], "fighter_choice": true,
		"desc": "Today's fight, the same for everyone: a seeded opponent and two mutators. Score by health left and time to spare. Left/Right: your fighter",
		"choices": ["as Cairn", "as Culvert", "as Craglash", "as Barkley", "as Gillbert", "as Chef Cerebro",
			"as Hissy Fitz", "as Digby", "as Sneaky Pete", "as Sno Mercy", "as Mister Crease"]},
	{"label": "Combo Trials", "group": "challenge", "modes": [9], "desc": "Learn the combos, one at a time"},
	{"label": "Reaction Drill", "group": "challenge", "modes": [10, 11], "choices": ["read Culvert", "read Cairn"],
		"desc": "Block or dodge what the opponent throws at you"},
	{"label": "Training", "group": "practice", "modes": [3, 4, 13, 15, 17, 19, 22, 24, 26, 28, 49],
		"desc": "Practise on a dummy. Pause for training options and Change fighter. Left/Right: your fighter",
		"choices": ["Cairn", "Culvert", "Craglash", "Barkley", "Gillbert", "Chef Cerebro", "Hissy Fitz", "Digby",
			"Sneaky Pete", "Sno Mercy", "Mister Crease"]},
	{"label": "Watch", "group": "practice", "modes": [5, 2], "choices": ["combo showcases", "CPU vs CPU"],
		"desc": "Sit back: scripted showcases or the CPU against itself"},
]
const DEFAULT_TEAMS := [["cerebro", "gillbert", "barkley"], ["culvert", "cerebro", "craglash"]]
const LEVEL_NAMES := ["Easy", "Normal", "Hard", "Rage"]
const DUMMY_MODES := ["Stand", "Guard", "Walk", "Dodge"]
const ROUND_TICKS := 90 * 60
const WINS_NEEDED := 2
const INTRO_TICKS := 90
const ROUND_OVER_TICKS := 210
## The match-over choices come up this long after the winner's banner.
const MATCH_OVER_MENU_AT := 40
const SETTINGS_PATH := "user://settings.cfg"
## Frame rate caps. Menus always draw at 60 (nothing in them moves faster, and it keeps
## the PC cool); fights draw at the player's choice, 144 unless changed (0: no cap). The
## game itself always runs 60 steps a second; a higher frame rate shows each one sooner.
const MENU_FPS := 60
const FPS_CHOICES := [60, 120, 144, 165, 240, 0]
const DEFAULT_FPS := 144
## On a phone or a handheld (Android) fights default to 60: on the Odin 3 the release build
## holds 60 without a dropped frame, while at 120 every other frame carries a tick that
## doesn't fit the 8 ms, so it stutters. The setting still offers the higher rates.
const DEFAULT_FPS_MOBILE := 60


## The fight frame rate to start with: `mobile` is the platform's (a test passes its own).
static func default_fps(mobile := OS.has_feature("mobile")) -> int:
	return DEFAULT_FPS_MOBILE if mobile else DEFAULT_FPS
# Knockouts: the simulation itself freezes and then runs at half speed (MatchSim's
# ko_freeze / slowmo, so online peers agree); the camera pushes in on the loser.
const KO_ZOOM := 1.45
const SHOWCASE_ZOOM := 1.9
## Room the fight camera leaves around the fighters (sides, top and bottom).
const CAM_PAD := Vector2(72, 40)
## On a map bigger than the stadium (Caravan, Capture the Flag) the camera follows the
## local player and whoever is within this of them, never pulling back past FOLLOW_ZOOM.
const FOLLOW_R := 230.0
const FOLLOW_ZOOM := 0.8
## Watching a big map with nobody here playing: as far back as this at most.
const BIG_MAP_MIN_ZOOM := 0.5
## The KO push-in, in ticks from the knockout: a beat held on the impact (the freeze),
## a slow ease in, held through the slow motion, then eased back out.
const KO_PUSH_DELAY := 6
const KO_PUSH_IN := 34
const KO_HOLD_UNTIL := 120
const KO_PUSH_OUT := 40
## Look-ahead: the camera leads toward where the action is going. An attacker leads along
## its facing (LEAD_ATTACK px); anyone moving fast (a dash, a launch, a knockback) leads
## along its motion, LEAD_PER_SPEED px for every px a tick. All of it together is held
## to LEAD_MAX and eased in at LEAD_EASE a tick, and never pushes a fighter closer than
## LEAD_KEEP to the screen's edge.
const LEAD_ATTACK := 10.0
const LEAD_PER_SPEED := 4.0
const LEAD_MIN_SPEED := 1.5  ## px a tick: slower than this (a walk) leads nothing
const LEAD_MAX := 22.0
const LEAD_EASE := 0.06
const LEAD_KEEP := Vector2(28, 20)
## Exchanges: when everyone in shot is within EXCHANGE_SPAN of each other and hits or blocks
## land (EXCHANGE_HITS of them, each within EXCHANGE_HOLD ticks of the last: a trade, not
## one poke), the camera pushes in by up to EXCHANGE_PUSH (x the fitted zoom), easing in at
## EXCHANGE_IN and back out at EXCHANGE_OUT a tick, so a trade tightens the shot without
## pumping on every hit. EXCHANGE_HOLD ticks after the last hit it lets go. The push never
## leaves less room round the fighters than EXCHANGE_PAD.
const EXCHANGE_SPAN := Vector2(150, 90)
const EXCHANGE_PUSH := 0.12
const EXCHANGE_IN := 0.025
const EXCHANGE_OUT := 0.012
const EXCHANGE_HOLD := 70
const EXCHANGE_HITS := 3
const EXCHANGE_PAD := Vector2(48, 28)

var sim: MatchSim
var _cam_zoom := 0.0  ## eased toward a zoom that fits the fighters (0: snap on the next frame)
var replay: Replay
var arena: ArenaView
var crowd: CrowdView
var entities: Node2D
var views: Array[CreatureView] = []
var fx: FxView
var fx_ground: FxGround
var water: WaterView
var wear: FloorWear
var shadows: ShadowLayer
var audio: AudioView
var debug: DebugView
var hud: Hud
var camera: Camera2D
var flash_rect: ColorRect
var fade_rect: ColorRect

var flow: Flow = Flow.MENU
var flow_t := 0
var mode := 0
var level := 1
var sides: Array = [Side.PLAYER, Side.CPU]
var cpus: Array = [null, null]
var round_num := 1
## The ladder in progress (Arcade, Gauntlet or Daily; null outside them) and its
## fighter; the CPU level a stage asks for (-1: the Settings level).
var arcade: Ladder = null
var _arcade_fighter := "cairn"
var _cpu_level_override := -1
var wins := [0, 0]
## Each side's Surge meter at the end of the last offline round (-1: none), carried into the
## next round of a Versus match when data/rules/energy.json says so; cleared on a new match.
var _carried_energy := [-1.0, -1.0]
var timer := ROUND_TICKS
var seed_base := 1
## --menu=PAGE: open a menu page on start (captures): single, single:<group>, settings, game, video, audio, controls.
var _menu_arg := ""
var _setting_rows := {}  ## Settings key -> its OptionRow, while the page is open
var _match_over_status: Label = null
var _recent_servers: Array = []
var fullscreen := false
var fight_fps := default_fps()
## Where settings are kept (tests point it elsewhere, so they never touch the player's).
var settings_path := SETTINGS_PATH
var vsync := true
## Wider-than-16:9 screens (ultrawide, 16:10): fill them with more stadium, or keep 16:9
## with bars.
var wide_fill := true
var rumble := true
var shake_scale := 1.0  ## screen shake: 1 full, 0.5 reduced, 0 off
var range_rings := false  ## floor rings showing each attack's real reach (Settings > Controls)
var rings: RangeRings
## The frame-rate overlay (Settings > Video, F9): PerfOverlay.Mode, over everything.
var perf_overlay: PerfOverlay
var paper: PaperFx
var discord_status := true  ## show what you play on your Discord profile (Settings)
var discord: DiscordRpc = null  ## null: off, headless, or no client id in data/discord.json
var presence: Presence = null
## Off for captures and headless runs, which must not be slowed to real time.
var _fps_caps := true
var menu_stick: MenuStick
## Menu screens on Godot's UI system (the pause menu; more to come).
var ui: ScreenStack
## The match is frozen behind the pause menu.
var paused := false
var _menu_ko_t := 0

var player_input := PlayerInput.new()
var dummy_mode := 0
## Training options (pause > Training options; saved under [training]): the sim flags
## every training match starts with (MatchSim.TRAINING_FLAGS).
var training_opts := {"no_cooldowns": false, "full_energy": false}
## The fighter picked with Change fighter: training rebuilds with it (Restart, F4) until
## you leave training ("" = the mode's own).
var _training_fighter := ""
var _training_screen_arg := ""  ## --training-screen=pause|options|fighters
var _swap_fade := 0.0  ## the black fade after a fighter swap, 1 → 0
var shake := 0.0
var shake_dir := Vector2.ZERO  ## the last hit's push direction: the shake leans along it
var _ko_cam_t := -1
var _ko_focus := Vector2.ZERO
var _ko_pos := Vector2.ZERO
var _cam_follow := Vector2.ZERO
var _cam_lead := Vector2.ZERO  ## the look-ahead, eased; added to _cam_follow
var _cam_prev: PackedVector2Array = []  ## each fighter's position last tick (its motion)
var _cam_push := 0.0  ## the exchange push-in, 0..1, eased
var _exchange_t := 0  ## ticks left since the last hit or block in shot
var _exchange_hits := 0  ## hits and blocks in the exchange so far
var _surge_bars := 0  ## ticks left of a Surge freeze's letterbox
var letterbox: Letterbox
var showcase: Showcase = null
var duel: DuelSim = null
## A team battle (2v2, 3v3): every creature on the field, one per slot (TeamSim).
var team_battle: TeamSim = null
## Combo Trials or a Reaction Drill: drives the partner and judges the player.
var coach = null
var _row_choice: Array = []
var player2_input := PlayerInput.new()
var player3_input := PlayerInput.new()
var player4_input := PlayerInput.new()
## A Brawl in progress (null outside one), its Chaos Cup mutator names for the banner,
## and a replay being watched (its frames feed every REPLAY side).
var brawl: BrawlSim = null
var _chaos_names := ""
var _replay_frames: Array = []
var _replay_watched := {}  ## that replay's setup (a training one's mid-recording option changes)
var _rules_id := ""
var _teams: Array = DEFAULT_TEAMS.duplicate(true)
var _skip_select := false
var _cpu_vs_cpu := false
## --view-team=N: whose eyes the screen uses when nobody plays here (-1: everyone's).
var _view_team_arg := -1
## Who the local team can see (Vision), fed from the events the views are shown, and
## which fighter slots are hidden from it this tick (true: not drawn at all).
var vision := Vision.new()
var _hidden: Array = []
var _showcase_list: Array = []
var _showcase_arg := ""  ## --showcase=NAME: loop just that one
var _showcase_i := 0
var _showcase_end_t := 0
var autoplay: AutoPlay = null
var frame_count := 0
var _shots := {}
var _shot_dir := "user://shots"
var _quit_after := 0
## The CPUs' inputs for this tick are worked out (_think_cpus) and wait in last_bits.
var _cpus_thought := false
## The next tick's CPU thinking, set going at the end of a tick (_think_ahead) so it runs
## on the worker threads while the frame is drawn; -1 when none is running. _cpu_ahead is
## the match and tick it read: the next tick takes its answers only if it steps that same
## match from that same tick. On with a screen (the headless tests think in the tick).
var _cpu_task := -1
var _cpu_ahead: Array = []
var _cpus_early := false
## Frame and tick times (--perf), printed on quit.
var _perf: PerfLog = null

# Online
var netplay: Netplay = null
var online: OnlineMatch = null  ## the online match being shown
var lobby: OnlineLobby
## The Match found screen while the server's ready check is on.
var _ready_screen: ReadyCheck = null
## Accept matches found without asking (command-line joins, --cpu-vs-cpu).
var _auto_accept := false
var _online_fighter := "cairn"
var _online_address := ""
## Settings > Game > Online server: the server Quick match and rooms use ("" = the
## game's own, from data/online.json).
var _online_server := ""
## Looking for the server on this network before joining it (see LanFinder), and the
## join to make when it's done: [fighter, host, port, room].
var _finder: LanFinder = null
var _finder_join: Array = []
## The team (one fighter, or three for a tag Duel) and team rules the next server join
## takes, from the lobby.
var _pending_team: Array = []
var _pending_rules := ""
## Spectating an online match: the referee's copy netplay keeps (null otherwise), and
## whether the next server join is to watch.
var watch: Referee = null
var _pending_watch := false
## Online input delay: -1 picks it from the ping, else that many frames (matches you
## host or join directly; the server picks its own). Saved with the settings.
var input_delay := -1
var _pending_ranked := false
## A Daily score on its way to the server, or the board on its way back.
var _daily_client: DailyClient = null
var _daily_sent_toast := ""
var _rb_seen := 0
var _rb_rate := 0
var _rb_t := 0
## Where the look-up asks (tests ask this machine instead of the whole network).
var finder_target := "255.255.255.255"
## The last look-up found nothing nearby, so a failed join can say what to check at home.
var _home_missed := false
var _net_args := {}  ## from the command line: host / join / lag / delay / report
var _net_end_t := 0
## A room on the server: whether this player made it (the online screen then says
## who to tell), and the between-matches screens (the room page and its fighter select).
var _room_made := false
var _room_screen: UiScreen = null
var _room_status_label: Label = null
var _room_picker: CharacterSelect = null
## A 1v1 rematch outside a room is picking (Quick match, ranked, direct): the room's
## page and fighter select are up for it (see _open_rematch_pick).
var _rematch_page := false
## --net-no-pick: how many more 1v1 rematch picks the --cpu-vs-cpu demo leaves to the
## countdown instead of locking in.
var _net_no_pick := 0
## How many of the online match's slots were shown as the server's CPU.
var _cpu_shown := 0


func _ready() -> void:
	if _run_sim_check() or _run_server():
		return
	_fit_window()
	_apply_pixel_scale()
	get_window().size_changed.connect(_apply_pixel_scale)
	Controls.setup()
	_cpus_early = DisplayServer.get_name() != "headless"
	_fps_caps = DisplayServer.get_name() != "headless" and not ("--fixed-fps" in OS.get_cmdline_args()) \
		and not ("--write-movie" in OS.get_cmdline_args())
	menu_stick = MenuStick.new()
	add_child(menu_stick)
	ui = ScreenStack.new()
	add_child(ui)
	ui.moved.connect(func(): audio.play("ui_move", 0.0, 1.0, true))
	ui.chosen.connect(func(): audio.play("ui_select", 0.0, 1.0, true))
	camera = Camera2D.new()
	camera.position = SimDefs.arena_size() * 0.5
	add_child(camera)
	camera.make_current()

	arena = ArenaView.new()
	add_child(arena)
	crowd = CrowdView.new()
	add_child(crowd)
	wear = FloorWear.new()  # scratches, gouges, craters, prints: the floor remembers, under everything
	add_child(wear)
	fx_ground = FxGround.new()
	add_child(fx_ground)
	water = WaterView.new()  # living water over the shallows, under the fighters
	add_child(water)
	shadows = ShadowLayer.new()  # the fighters' shadows, on the floor under everyone
	shadows.views = views
	add_child(shadows)
	rings = RangeRings.new()
	rings.visible = false
	rings.fx = fx  # what the local team can see (Vision): no rings for a hidden foe
	add_child(rings)  # on the floor, under the fighters
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	fx = FxView.new()
	fx.bind_ground(fx_ground)
	fx.wear = wear
	add_child(fx)
	paper = PaperFx.new()  # Mister Crease's sheets, crafts and storms, over the fighters
	paper.fx = fx
	add_child(paper)
	audio = AudioView.new()
	add_child(audio)
	fx.cue.connect(audio.play)
	debug = DebugView.new()
	debug.visible = false
	add_child(debug)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	letterbox = Letterbox.new()  # first on the screen layer: under the flash, the fade and the HUD
	layer.add_child(letterbox)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 0.95, 0.75, 0.0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade_rect)
	hud = Hud.new()
	layer.add_child(hud)
	var top := CanvasLayer.new()
	top.layer = 30  # over the menus (ScreenStack is 20)
	add_child(top)
	perf_overlay = PerfOverlay.new()
	top.add_child(perf_overlay)
	_row_choice.resize(MENU_ROWS.size())
	_row_choice.fill(0)
	for pin in [player2_input, player3_input, player4_input]:
		(pin as PlayerInput).keyboard = false
		(pin as PlayerInput).pad_device = PlayerInput.NO_PAD

	_load_settings()
	if UiTheme.smooth:
		ui.restyle()  # the menu theme was built before the saved Text font was read
	var start_mode := _parse_args()
	_apply_device()
	_apply_discord()
	_apply_range_rings()
	_open_menu(_menu_arg)  # also starts the background match the pick screen sits on
	if start_mode >= 0:
		_start_match(start_mode)
		if in_training():
			match _training_screen_arg:
				"pause":
					_open_pause()
				"options":
					_open_pause()
					_open_training_options()
				"fighters":
					_open_fighter_swap()
	if _net_args.has("host") or _net_args.has("join"):
		_auto_accept = true  # started from the command line: no one to ask
		_open_lobby()
		if _net_args.has("host"):
			_net_host(_online_fighter)
		else:
			_pending_watch = bool(_net_args.get("watch", false))
			var parsed := OnlineLobby.parse_address(String(_net_args["join"]))
			var size := int(_net_args.get("size", 0 if String(parsed[2]) != "" else 1))
			_net_join(_online_fighter, String(parsed[0]), int(parsed[1]), String(parsed[2]), true, size)


# ------------------------------------------------------------------ flow

## The title menu, over a CPU match that plays behind it. `page` opens "single" or
## "settings" on top of it; `focus` is the title row to land on ("online" after leaving
## an online match).
func _open_menu(page := "", focus := "") -> void:
	_close_ui()
	_end_online()
	flow = Flow.MENU
	flow_t = 0
	_end_showcase()
	_end_duel()
	_end_coach()
	hud.visible = true
	hud.menu_visible = true
	audio.play_music("menu")
	_menu_background()
	var land := focus if focus != "" else ("settings" if page in SETTING_PAGES or page == "controls" or page.begins_with("remap:") else page)
	var t := TitleScreen.new(land)
	t.single_pressed.connect(_open_single)
	t.online_pressed.connect(func(): _start_match(ONLINE_MODE))
	t.settings_pressed.connect(_open_settings)
	t.exit_pressed.connect(func(): get_tree().quit())
	ui.push(t)
	if page.begins_with("single:"):  # a Single player page, for captures: --menu=single:team
		_open_single()
		_open_single_group(page.get_slice(":", 1))
		return
	match page:
		"single":
			_open_single()
		"settings":
			_open_settings()
		"game", "video", "audio":
			_open_settings()
			_open_settings_page(page)
		"controls":
			_open_settings()
			_open_controls()
		"remap:classic", "remap:league", "remap:gamepad":  # captures of a Remap page
			_open_settings()
			_open_controls()
			_open_remap(page.get_slice(":", 1))


## A CPU-vs-CPU match behind the menus (restarted now and then; the screens stay).
func _menu_background() -> void:
	_new_sim(MatchFactory.versus("cairn", "culvert"), [Side.CPU, Side.CPU])
	hud.timer_ticks = -1
	hud.banner = ""
	hud.banner_sub = ""


## Single player: every mode against the CPU, training, trials and local 2-player. Rows
## with choices pick the fighter (or drill) with Left/Right; Enter starts.
func _open_single() -> void:
	var scr := UiScreen.new()
	scr.title = "SINGLE PLAYER"  # no logo: six cards and the arena row fill the screen
	scr.row_width = 240.0
	scr.row_gap = 2
	scr.detail = true
	scr.blurb = "Fight the CPU, train, take on Combo Trials, or play 2 players on one screen"
	scr.hints = ["move", "change", "select", "back"]
	scr.builder = func(s: UiScreen):
		var maps: Array = []
		for id in ArenaMap.IDS:
			maps.append(ArenaMap.name_of(id))
		var arena_row := s.add_option("Arena", maps, maxi(0, ArenaMap.IDS.find(MatchFactory.arena)),
			func(i: int): _set_arena(ArenaMap.IDS[i]), "Where every match is fought. Left/Right: the map")
		var arena_card := s.card(arena_row)
		if arena_card != null:
			arena_card.picture = _arena_picture(MatchFactory.arena)
			arena_row.changed.connect(func(i: int): arena_card.picture = _arena_picture(ArenaMap.IDS[i]))
		s.add_space(2)
		for g in MENU_GROUPS:
			var gid := String(g["id"])
			s.add_card(String(g["title"]), String(g["sub"]), func(): _open_single_group(gid), String(g["desc"]))
		s.add_space(3)
		s.add_button("Back", s.back)
	ui.push(scr)


## One page of Single player: the rows of a MENU_GROUPS entry. Rows with choices pick
## the fighter (or size) with Left/Right; Enter starts.
func _open_single_group(gid: String, focus_row := -1) -> void:
	var group := {}
	for g in MENU_GROUPS:
		if String(g["id"]) == gid:
			group = g
	var scr := UiScreen.new()
	scr.logo = true
	scr.crumbs = ["SINGLE PLAYER"]
	scr.title = String(group.get("title", "")).to_upper()
	scr.row_width = 236.0
	scr.row_gap = 2
	scr.detail = true
	scr.blurb = String(group.get("desc", ""))
	scr.hints = ["move", "change", "select", "back"]
	scr.builder = func(s: UiScreen):
		for r in MENU_ROWS.size():
			var row: Dictionary = MENU_ROWS[r]
			if String(row.get("group", "")) != gid:
				continue
			var desc := String(row.get("desc", ""))
			if row.has("choices"):
				var o := s.add_option(String(row["label"]), row["choices"], int(_row_choice[r]),
					func(i: int):
						_row_choice[r] = i
						_save_settings(), desc)
				if r == focus_row:
					s.default_focus = o
				o.activates = true
				o.activated.connect(func():
					ui.notify_chosen()
					_start_row(r))
				var oc := s.card(o)
				if oc != null:
					_fill_card(oc, r, int(_row_choice[r]))
					o.changed.connect(func(i: int): _fill_card(oc, r, i))
			else:
				var b := s.add_button(String(row["label"]), func(): _start_row(r), desc)
				if r == focus_row:
					s.default_focus = b
				var bc := s.card(b)
				if bc != null:
					_fill_card(bc, r, 0)
		s.add_space(3)
		s.add_button("Back", s.back)
	ui.push(scr)


## A row's card in the panel: the fighter the row's choice names, and the mode's facts
## read from the rules it plays by (never typed into the menu, so they can't drift).
func _fill_card(card: DetailCard, r: int, choice: int) -> void:
	var row: Dictionary = MENU_ROWS[r]
	if not row.has("modes"):
		return
	var cfg: Dictionary = MODES[int(row["modes"][0 if row.get("fighter_choice", false) else choice])]
	var fighter := ""
	if row.get("fighter_choice", false):
		fighter = MatchFactory.FIGHTERS[clampi(choice, 0, MatchFactory.FIGHTERS.size() - 1)]
	elif cfg.has("left") and (cfg.get("training", false) or Side.PLAYER in cfg.get("sides", [])):
		fighter = String(cfg["left"])
	card.fighter = fighter
	card.facts = _mode_facts(row, cfg)


## A picture of an arena for the menu (its floor art), if it has one.
func _arena_picture(id: String) -> Texture2D:
	var path := "res://assets/sprites/arena_%s.png" % id
	return load(path) if ResourceLoader.exists(path) else null


## Ticks as m:ss.
static func _mmss(ticks: int) -> String:
	var s := ticks / 60
	return "%d:%02d" % [s / 60, s % 60]


## Three lines at most, the numbers from the rules files and the code that plays them.
func _mode_facts(row: Dictionary, cfg: Dictionary) -> Array:
	var two: bool = Side.PLAYER2 in cfg.get("sides", [])
	if cfg.has("team"):
		var size := int(cfg["team"])
		var kind := String(cfg.get("rules", "deathmatch" if cfg.get("deathmatch", false) else ""))
		var rules := TeamSim.rules_by_id(kind)
		var clock := "Clock %s" % _mmss(int(float(rules.get("time_seconds", 150)) * 60))
		match kind:
			"deathmatch":
				var t: Array = rules.get("score_to_win", [8, 8, 12, 15])
				return ["First to %d KOs, unlimited respawns" % int(t[clampi(size, 0, t.size() - 1)]),
					clock + ", then sudden death"]
			"crater":
				return ["Hold the zone %d s in all" % (int(rules.get("score_to_win", 3600)) / 60),
					"It moves, and the floor round it breaks", clock]
			"ctf":
				return ["First to %d captures" % int(rules.get("captures_to_win", 3)),
					"Your flag must be home to score", clock + ", then sudden death"]
			"caravan":
				return ["Two rounds of %s, one side escorting" % _mmss(int(float(rules.get("round_seconds", 120)) * 60)),
					"A checkpoint adds %d s and a rockslide" % int(rules.get("checkpoint_seconds", 30)),
					"Faster finish or further push wins"]
			"sinkhole":
				return ["One life each: the chasm is a KO",
					"A ring falls every %d s, up to %d" % [int(rules.get("shrink_every", 300)) / 60, int(rules.get("max_rings", 14))],
					clock + ": more health left wins"]
		return ["One life each, no respawns", clock + ": more health left wins"]
	if cfg.get("duel", false):
		var d := DuelSim.load_rules()
		var n := int(d.get("team_size", 3))
		return ["%d v %d: tag in and out, the bench heals" % [n, n], "Clock %s" % _mmss(int(float(d.get("time_seconds", 180)) * 60)),
			"Two players on one screen" if two else "You pick both teams"]
	if cfg.get("brawl", false):
		var b := BrawlSim.load_rules()
		var out := ["%d fighters, one life each" % BrawlSim.MAX_PLAYERS,
			"Clock %s: the healthiest wins" % _mmss(int(float(b.get("time_seconds", 120)) * 60))]
		if cfg.get("chaos", false):
			out.append("Three mutators, drawn each match")
		return out
	if cfg.get("arcade", false):
		return ["%d stages, the last a 3v3 Duel" % Arcade.STAGES, "The boss team fights one level up", "Clears unlock palettes"]
	if cfg.get("gauntlet", false):
		return ["Endless waves, health carrying over", "Harder every %d waves, up to Rage" % Gauntlet.WAVES_PER_LEVEL,
			"Your best is kept"]
	if cfg.get("daily", false):
		return ["Today's seed: the same for everyone", "%d mutators on the fight" % Daily.PICKS,
			"Clock %s: health and time left score" % _mmss(Daily.FIGHT_TICKS)]
	if cfg.get("trials", false):
		return ["One route at a time, with a demo", "Land it to clear it"]
	if cfg.has("drill"):
		return ["Red tell: roll away, or hit first", "Gold tell: guard"]
	if cfg.get("training", false):
		return ["A dummy that stands, guards, walks or dodges", "Pause for no cooldowns, full Surge, Change fighter"]
	if cfg.get("showcase", false):
		return ["Every fighter's kit, scripted", "Esc comes back here"]
	if cfg.has("left") or cfg.get("versus2p", false):
		var out := ["Best of %d, rounds of %s" % [WINS_NEEDED * 2 - 1, _mmss(ROUND_TICKS)],
			"K.O., or more health left at time"]
		if two:
			out.append("Two players on one screen")
		elif Side.PLAYER in cfg.get("sides", []):
			out.append("The CPU at the level in Settings")
		else:
			out.append("The CPU against itself, at the level in Settings")
		return out
	return []


## The arena offline matches play on (the menu's choice is saved with the settings;
## `--arena=ID` only lasts the session).
var _arena_saved := ArenaMap.DEFAULT


func _set_arena(id: String) -> void:
	if id in ArenaMap.IDS:
		MatchFactory.arena = id
		_arena_saved = id
		_save_settings()


## Where the last Single player row was started from, so leaving a match lands back on
## that page and row instead of the title.
var _row_from := {}


## Back from a match (or its pick screen): the Single player page and row it started
## from, else the title.
func _back_to_row() -> void:
	if _row_from.is_empty():
		_open_menu()
		return
	_open_menu("single")
	_open_single_group(String(_row_from["group"]), int(_row_from["row"]))


func _start_row(row: int) -> void:
	var r: Dictionary = MENU_ROWS[row]
	_row_from = {"group": String(r.get("group", "")), "row": row} if r.has("group") else {}
	if r.has("screen"):
		_open_replays()
		return
	if r.get("fighter_choice", false):
		_arcade_fighter = MatchFactory.FIGHTERS[clampi(int(_row_choice[row]), 0, MatchFactory.FIGHTERS.size() - 1)]
		_start_match(int(r["modes"][0]))
		return
	_start_match(int(r["modes"][_row_choice[row] if row < _row_choice.size() else 0]))


## Settings: four pages, like most games: Game, Video, Audio, Controls.
func _open_settings() -> void:
	var scr := UiScreen.new()
	scr.logo = true
	scr.title = "SETTINGS"
	scr.row_width = 230.0
	scr.detail = true
	scr.blurb = "CPU level, keyboard layout, volume, fullscreen, frame rate"
	scr.builder = func(s: UiScreen):
		s.add_card("Game", "CPU level, rumble, screen shake, online server, input delay",
			func(): _open_settings_page("game"), "How the game plays and where it plays online")
		s.add_card("Video", "Fullscreen, wide screens, vsync, frame rate",
			func(): _open_settings_page("video"), "The screen and the frame rate")
		s.add_card("Audio", "Master, music, sound effects, menu sounds",
			func(): _open_settings_page("audio"), "Volumes")
		s.add_card("Controls", "Keyboard and controller layouts; remap keys and buttons",
			_open_controls, "Who presses what")
		s.add_space(3)
		s.add_button("Back", s.back)
	ui.push(scr)


## One Settings page: each row's values and description come from _setting(); a change
## goes through _set_setting() and is saved at once.
func _open_settings_page(page: String) -> void:
	var scr := UiScreen.new()
	scr.logo = true
	scr.crumbs = ["SETTINGS"]
	scr.title = page.to_upper()
	scr.row_width = 236.0
	scr.detail = true
	scr.blurb = {"game": "How the game plays and where it plays online", "video": "The screen and the frame rate",
		"audio": "Volumes"}.get(page, "")
	scr.hints = ["move", "change", "back"]
	scr.builder = func(s: UiScreen):
		for key in SETTING_PAGES[page]:
			if key == "server":
				_add_server_row(s)
			else:
				_add_setting_row(s, key)
		s.add_space(4)
		s.add_button("Back", s.back)
	scr.backed.connect(func(): _setting_rows.clear())
	ui.push(scr)


## Rebuild an open Settings page in place (its rows carry their own font sizes), with
## the row that changed focused again: Text font swaps every size on the page.
func _reopen_settings_page(page: String, key: String) -> void:
	var top := ui.top()
	if top == null or top.title != page.to_upper():
		return
	ui.pop()
	_open_settings_page(page)
	var row: Control = _setting_rows.get(key)
	if row != null:
		row.grab_focus()


func _add_setting_row(s: UiScreen, key: String) -> OptionRow:
	var info := _setting(key)
	var o := s.add_option(String(info["label"]), info["values"], int(info["index"]), func(_i): pass,
		String(info["desc"]))
	o.wrap = bool(info.get("wrap", true))
	o.bar = float(info.get("bar", -1.0))
	o.changed.connect(func(i: int):
		_set_setting(key, i)
		var now := _setting(key)
		o.set_values(now["values"], int(now["index"]))
		o.bar = float(now.get("bar", -1.0)))
	_setting_rows[key] = o
	return o


## Settings > Game > Online server: a text box, saved as it's typed. Empty means the
## game's own server.
func _add_server_row(s: UiScreen) -> LineEdit:
	var f := LineEdit.new()
	f.text = _online_server
	f.placeholder_text = "Online server: " + default_server()
	f.max_length = 80
	f.text_changed.connect(func(t: String):
		_online_server = t.strip_edges()
		_save_settings())
	s.add_row(f, "Where Quick match and rooms play. Leave it empty for %s" % default_server())
	s.entitle(f, "Online server")
	return f


## The game's own server, from data/online.json.
static func default_server() -> String:
	var f := FileAccess.open("res://data/online.json", FileAccess.READ)
	if f == null:
		return ""
	var d = JSON.parse_string(f.get_as_text())
	return String(d.get("server", "")).strip_edges() if d is Dictionary else ""


## The server Quick match and rooms use: the player's, or the game's own.
func online_server() -> String:
	return _online_server if _online_server != "" else default_server()


## Controls: the keyboard layout, and remapping for each keyboard layout and the controller.
func _open_controls() -> void:
	var scr := UiScreen.new()
	scr.logo = true
	scr.crumbs = ["SETTINGS"]
	scr.title = "CONTROLS"
	scr.row_width = 236.0
	scr.detail = true
	scr.blurb = "Who presses what"
	scr.hints = ["move", "change", "select", "back"]
	scr.builder = func(s: UiScreen):
		_add_setting_row(s, "layout")
		_add_setting_row(s, "pad_layout")
		_add_setting_row(s, "range_rings")
		s.add_button("Remap controller", func(): _open_remap("gamepad"), "Change which button does what")
		s.add_button("Remap Classic keyboard", func(): _open_remap("classic"), "WASD + J K U I O, or your own keys")
		s.add_button("Remap League-style keyboard", func(): _open_remap("league"),
			"Mouse to move and aim; Q W E R, or your own keys")
		s.add_button("Reset all controls", func():
			var c := ConfirmScreen.new("Reset every key and button?", "Back to the game's defaults.", "Reset", "Cancel")
			c.answered.connect(func(yes: bool):
				if yes:
					Controls.reset()
					_save_settings()
					_apply_device()
					_toast("Controls reset"))
			ui.push(c), "Put every key and button back")
		s.add_space(4)
		s.add_button("Back", s.back)
	scr.backed.connect(func(): _setting_rows.clear())
	ui.push(scr)


func _open_remap(group: String) -> void:
	var r := RemapScreen.new(group)
	r.changed.connect(func():
		_save_settings()
		_apply_device())  # the prompts and help show the new keys
	ui.push(r)


## The MODES index of the mode with this label (-1: none). Tests and code that start a
## mode by name use it, so removing a mode doesn't shift them.
static func mode_index(label: String) -> int:
	for i in MODES.size():
		if String(MODES[i]["label"]) == label:
			return i
	return -1


## `keep_teams`: a rematch with the same teams (no pick screen).
func _start_match(m: int, keep_teams := false) -> void:
	_close_ui()
	_over_by = ""
	_arcade_cleared = false
	if not (keep_teams and m == mode):
		_training_fighter = ""  # a swapped fighter lasts until you leave training
	mode = m
	wins = [0, 0]
	_carried_energy = [-1.0, -1.0]
	round_num = 1
	hud.menu_visible = false
	_save_settings()
	var cfg: Dictionary = MODES[m]
	_cpu_level_override = -1
	if cfg.get("arcade", false):
		if arcade == null or not keep_teams:
			arcade = Arcade.new(_arcade_fighter, level, seed_base)
	elif cfg.get("gauntlet", false):
		arcade = Gauntlet.new(_arcade_fighter, seed_base)
	elif cfg.get("daily", false):
		arcade = Daily.new(_arcade_fighter)
	else:
		arcade = null
	if cfg.get("online", false):
		_open_lobby()
		return
	var two_players: bool = Side.PLAYER2 in cfg.get("sides", [])
	_assign_devices(_humans(cfg))
	if _has_pick(cfg) and not keep_teams and not _skip_select:
		flow = Flow.SELECT
		flow_t = 0
		hud.visible = false
		var size := int(DuelSim.load_rules().get("team_size", 3)) if cfg.get("duel", false) else 1
		var labels := ["PLAYER 1", "PLAYER 2" if two_players else "CPU"]
		var title := "DUEL" if cfg.get("duel", false) else "VERSUS"
		if cfg.get("brawl", false):  # one pick per human seat; the other seats fill from the roster
			title = "CHAOS CUP" if cfg.get("chaos", false) else "BRAWL"
			labels = ["PLAYER 1", "PLAYER 2" if two_players else "CPU"]
		if cfg.has("team"):
			size = int(cfg["team"])
			labels = ["YOU + CPU", "CPU TEAM"]
			var kind := String(cfg.get("rules", "deathmatch" if cfg.get("deathmatch", false) else ""))
			title = {"sinkhole": "SINKHOLE  %d v %d", "crater": "KING OF THE CRATER  %d v %d",
				"deathmatch": "TEAM DEATHMATCH  %d v %d", "caravan": "CARAVAN  %d v %d",
				"ctf": "CAPTURE THE FLAG  %d v %d"}.get(kind, "TEAM BATTLE  %d v %d") % [size, size]
		var pick := CharacterSelect.new()
		pick.setup(title, size, labels, two_players, _padded_teams(size) if cfg.has("team") else _teams)
		pick.p1_keyboard = player_input.keyboard
		pick.p1_pad = player_input.pad_device
		pick.p2_pad = player2_input.pad_device
		pick.chosen.connect(_on_teams_chosen)
		pick.cancelled.connect(_back_to_row)
		ui.push(pick)
		return
	_start_round()


## Modes that open the pick screen first.
func _has_pick(cfg: Dictionary) -> bool:
	return cfg.get("duel", false) or cfg.get("versus2p", false) or cfg.has("team") or cfg.get("brawl", false)


func _on_teams_chosen(teams: Array) -> void:
	_close_ui()
	hud.visible = true
	_teams = teams
	audio.play("ui_select", 0.0, 1.0, true)
	_start_round()


## How many people play at this machine in a mode.
func _humans(cfg: Dictionary) -> int:
	var n := 0
	for s in cfg.get("sides", []):
		if s in LOCAL_SIDES:
			n += 1
	return n


func _local_input(side: int) -> PlayerInput:
	match side:
		Side.PLAYER2: return player2_input
		Side.PLAYER3: return player3_input
		Side.PLAYER4: return player4_input
	return player_input


## Local players: with a controller each, everyone gets one (player 1 keeps the
## keyboard too); one short, player 1 uses keyboard and mouse and the controllers go
## to players 2 and up; fewer than that and someone is asked to plug one in.
func _assign_devices(humans: int) -> void:
	var pads := Input.get_connected_joypads()
	player_input.keyboard = true
	player_input.pad_device = PlayerInput.ANY_PAD
	var others: Array[PlayerInput] = [player2_input, player3_input, player4_input]
	for pin in others:
		pin.pad_device = PlayerInput.NO_PAD
	if humans <= 1:
		return
	var need := humans - 1
	var first := 0
	if pads.size() >= humans:
		player_input.pad_device = pads[0]
		first = 1
	else:
		player_input.pad_device = PlayerInput.NO_PAD
	for k in need:
		if first + k < pads.size():
			others[k].pad_device = pads[first + k]
	if pads.size() < need:
		hud.show_toast("Connect %d controller%s for players %s" % [need - pads.size(), "" if need - pads.size() == 1 else "s",
			"2-%d" % humans if humans > 2 else "2"])


func _start_round() -> void:
	audio.play_music("fight")
	var cfg: Dictionary = MODES[mode]
	_end_duel()
	_end_coach()
	if arcade != null:
		_start_arcade_stage()
		return
	if cfg.get("duel", false):
		_start_duel()
		return
	if cfg.has("team"):
		_start_team(int(cfg["team"]), "deathmatch" if cfg.get("deathmatch", false) else String(cfg.get("rules", "")))
		return
	if cfg.get("brawl", false):
		_start_brawl(cfg)
		return
	if cfg.get("trials", false):
		coach = ComboTrials.new(Callable(player_input, "label"))
		_start_coach("%s watch the demo again    %s next trial    Esc menu" % [
			Controls.binding_text("debug_dummy_mode", "classic"), Controls.binding_text("reset", "classic")])
		return
	if cfg.has("drill"):
		coach = ReactionDrill.new(String(cfg["drill"]), seed_base)
		_start_coach("Red: roll away (or hit first)    Gold: guard    Esc menu")
		return
	if cfg.get("showcase", false):
		if _showcase_list.is_empty():
			_showcase_list = [_showcase_arg] if _showcase_arg != "" else Showcase.names()
		_showcase_i = 0
		_start_showcase()
		return
	if cfg.get("training", false):
		var t := MatchFactory.training(training_fighter())
		t.set_training_flags(training_opts)
		_new_sim(t, [Side.PLAYER, Side.DUMMY])
		hud.timer_ticks = -1
		hud.banner = ""
		flow = Flow.FIGHT
		flow_t = 0
		return
	if cfg.get("versus2p", false):
		_new_sim(MatchFactory.versus(String(_teams[0][0]), String(_teams[1][0])), cfg["sides"])
	else:
		_new_sim(MatchFactory.versus(String(cfg["left"]), String(cfg["right"])), cfg["sides"])
	if MatchSim.energy_carries():
		for i in 2:
			if float(_carried_energy[i]) >= 0.0:
				sim.creatures[i].energy = minf(float(_carried_energy[i]), CreatureSim.MAX_ENERGY)
		# The replay rebuilds the round with the meters it started with.
		if replay != null and replay.setup is Dictionary:
			replay.setup["energy"] = [sim.creatures[0].energy, sim.creatures[1].energy]
	timer = ROUND_TICKS
	hud.timer_ticks = timer
	hud.wins = wins
	flow = Flow.INTRO
	flow_t = 0


## Arcade: one stage of the ladder. Stages 1-5 are a single round against one
## opponent; the sixth is a 3v3 Duel against the boss team, one CPU level up.
func _start_arcade_stage() -> void:
	_end_duel()
	_end_coach()
	_cpu_level_override = arcade.stage_level()
	if arcade.is_boss():
		_teams = [arcade.player_team(), arcade.boss_team()]
		_start_duel()
		return
	var stage_sim := MatchFactory.versus(arcade.fighter, arcade.opponent())
	if arcade is Daily:
		stage_sim = (arcade as Daily).build()
	elif not arcade.mutators().is_empty():
		stage_sim.apply_mutators(arcade.mutators(), seed_base)
	_new_sim(stage_sim, [Side.PLAYER, Side.CPU])
	if arcade is Daily:
		cpus[1] = (arcade as Daily).cpu()  # the day's CPU, the same for everyone
	if arcade.carried_hp() >= 0.0:
		sim.creatures[0].hp = minf(arcade.carried_hp(), sim.creatures[0].max_hp)
	hud.wins_needed = 1
	timer = ROUND_TICKS
	hud.timer_ticks = timer
	hud.wins = wins
	flow = Flow.INTRO
	flow_t = 0


## The round or Duel just ended in the Arcade: on to the next stage, the clear, or
## game over. Returns true when it moved the flow on.
func _arcade_result(won: bool) -> bool:
	if arcade == null:
		return false
	var me := sim.creatures[0]
	var share := clampf(me.hp / me.max_hp, 0.0, 1.0)
	if arcade is Daily:
		# One fight, scored, saved with its replay so the score can be checked.
		var d := arcade as Daily
		var score := d.score_fight(won, share, sim.tick)
		var best := Progress.record_daily(d.date, score)
		var path := "user://daily/daily_%d.json" % d.date
		DirAccess.make_dir_recursive_absolute("user://daily")
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"date": d.date, "fighter": d.fighter, "score": score,
				"replay": replay.to_dict()}))
		flow = Flow.MATCH_OVER
		flow_t = 0
		hud.banner = "SCORE  %d" % score if won else "NO SCORE"
		hud.banner_sub = ("A new best for today!" if best and won else
			("Today's best: %d" % Progress.daily_best(d.date)) if won else "Win the fight to score")
		if won and score > 0:
			_net_daily_submit(d)
		return true
	if not won:
		flow = Flow.MATCH_OVER
		flow_t = 0
		var lb := arcade.lost_banner()
		hud.banner = String(lb[0])
		hud.banner_sub = String(lb[1])
		return true
	if arcade.stage_won(me.hp):
		wins = [0, 0]
		round_num = 1
		_start_arcade_stage()
		return true
	# The boss is down: the Arcade is cleared on this level.
	_arcade_cleared = true
	var new_best := Progress.record_clear(arcade.fighter, arcade.level)
	flow = Flow.MATCH_OVER
	flow_t = 0
	hud.banner = "ARCADE CLEAR!"
	hud.banner_sub = ("New palette unlocked: F5 in a fight to wear it" if new_best
		else "Cleared on %s" % CpuController.LEVELS[arcade.level]["name"])
	audio.play("round_end")
	return true


## Duel: the rules (intro, tags, swaps, timer, winner) all run inside DuelSim; this
## only shows them.
func _start_duel() -> void:
	var cfg: Dictionary = MODES[mode]
	duel = DuelSim.new(_teams)
	_new_sim(duel.sim, cfg["sides"])
	for i in 2:
		if cpus[i] != null:
			(cpus[i] as CpuController).duel = duel
	hud.duel = duel
	hud.timer_ticks = duel.timer
	hud.wins = [0, 0]
	hud.wins_needed = 0
	hud.banner = ""
	flow = Flow.FIGHT
	flow_t = 0


## Team battle: like a Duel, the rules (intro, KOs, timer, winner) run inside TeamSim.
## You play the first fighter of the left team; CPUs play everyone else.
func _start_team(per_side: int, rules_id := "") -> void:
	_teams = _padded_teams(per_side)
	_rules_id = rules_id
	var rules := TeamSim.rules_by_id(rules_id)
	team_battle = TeamSim.new(_teams, per_side, rules)
	var s: Array = [Side.PLAYER]
	for i in range(1, team_battle.slot_count()):
		s.append(Side.CPU)
	_new_sim(team_battle.sim, s)
	hud.team = team_battle
	hud.focus = 0
	hud.timer_ticks = team_battle.timer
	hud.wins = [0, 0]
	hud.wins_needed = 0
	hud.banner = ""
	_show_pads()
	flow = Flow.FIGHT
	flow_t = 0


## Brawl: four fighters (the teams' first picks, then the roster), each on their own;
## Chaos Cup stacks three mutators drawn by the seed.
func _start_brawl(cfg: Dictionary) -> void:
	var ids: Array = []
	for side in _teams:
		for id in side:
			if not (String(id) in ids):
				ids.append(String(id))
	for f in MatchFactory.FIGHTERS:
		if ids.size() >= BrawlSim.MAX_PLAYERS:
			break
		if not (f in ids):
			ids.append(f)
	ids = ids.slice(0, BrawlSim.MAX_PLAYERS)
	var muts := {}
	_chaos_names = ""
	if cfg.get("chaos", false):
		var table := Daily.mutator_table()
		var keys: Array = table.keys()
		keys.sort()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_base
		for i in range(keys.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = keys[i]
			keys[i] = keys[j]
			keys[j] = t
		var names: Array = []
		for k in keys.slice(0, 3):
			for key in table[k]:
				if key != "name":
					muts[key] = table[k][key]
			names.append(String(table[k].get("name", k)))
		_chaos_names = ", ".join(names)
	brawl = BrawlSim.new(ids, {}, muts, seed_base)
	_new_sim(brawl.sim, cfg["sides"])
	hud.brawl = brawl
	hud.focus = 0
	hud.timer_ticks = brawl.timer
	hud.wins = [0, 0]
	hud.wins_needed = 0
	hud.banner = ""
	flow = Flow.FIGHT
	flow_t = 0


func _brawl_flow() -> void:
	hud.timer_ticks = maxi(brawl.timer, 0)
	match brawl.phase:
		BrawlSim.Phase.INTRO:
			var t := brawl.phase_t
			hud.banner = ("CHAOS CUP" if _chaos_names != "" else "BRAWL") if t < 60 else "FIGHT!"
			hud.banner_sub = (_chaos_names if _chaos_names != "" else "Free-for-all   ·   last one standing") if t < 60 else ""
			if t == 2 or t == 60:
				audio.play("round_start", 0.0, 0.75 if t == 2 else 1.0)
		BrawlSim.Phase.FIGHT:
			hud.banner = ""
			hud.banner_sub = ""
		BrawlSim.Phase.OVER:
			if brawl.phase_t == 1:
				hud.banner = "K.O." if brawl.timer > 0 else "TIME"
				hud.banner_sub = ""
			if brawl.phase_t >= int(brawl.rules.get("over_ticks", 150)):
				flow = Flow.MATCH_OVER
				flow_t = 0
				var w := brawl.winner
				if w < 0:
					hud.banner = "DRAW"
				else:
					hud.banner = "%s WINS!" % String(sim.creatures[w].def["name"]).to_upper()
					hud.banner_sub = ("%s   ·   %s" % [_side_name(w), _over_reason()]) if sides[w] in LOCAL_SIDES 						else _over_reason()


# ------------------------------------------------------------------ replay theater

## The saved replays, newest first: pick one to watch.
func _open_replays() -> void:
	var scr := UiScreen.new()
	scr.logo = true
	scr.title = "REPLAY THEATER"
	scr.row_width = 280.0
	scr.row_height = 13.0
	scr.row_font = 7
	scr.row_gap = 1
	scr.hints = ["move", "select", "back"]
	scr.builder = func(s: UiScreen):
		var files: Array = []
		var dir := DirAccess.open("user://replays")
		if dir != null:
			for f in dir.get_files():
				if f.ends_with(".json"):
					files.append(f)
		files.sort()
		files.reverse()
		if files.is_empty():
			s.add_text("No replays yet. Press F6 during a fight to save one.")
		for f in files.slice(0, 20):
			var path: String = "user://replays/" + String(f)
			s.add_button(_replay_label(path), func(): _play_replay(path), "Watch it")
		s.add_space(4)
		s.add_button("Back", s.back)
	ui.push(scr)


func _replay_label(path: String) -> String:
	var stamp := path.get_file().trim_prefix("replay_").trim_suffix(".json").replace("T", " ")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return stamp
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or not (d.get("setup") is Dictionary):
		return stamp
	var st: Dictionary = d["setup"]
	var names: Array = []
	for id in st.get("ids", []):
		names.append(String(MatchFactory.load_def(String(id)).get("name", id)))
	return "%s   %s   %s" % [stamp.left(16), String(st.get("kind", "versus")), " v ".join(names)]


## Watches a replay: the match it was recorded on is rebuilt and every side plays its
## recorded inputs. Ends when the inputs run out.
func _play_replay(path: String) -> void:
	var rep := Replay.load_file(path)
	if rep == null or not (rep.setup is Dictionary):
		_toast("That replay can't be played (no setup saved with it)")
		return
	var why := ReplayBuilder.unsupported(rep.setup)
	if why != "":
		_toast(why)
		return
	_close_ui()
	mode = REPLAY_MODE
	wins = [0, 0]
	round_num = 1
	hud.menu_visible = false
	hud.visible = true
	arcade = null
	_cpu_level_override = -1
	_end_duel()
	_end_coach()
	var built := ReplayBuilder.build(rep.setup)
	var game = built["game"]
	var s: Array = []
	for i in (built["sim"] as MatchSim).creatures.size():
		s.append(Side.REPLAY)
	_replay_frames = rep.frames
	_replay_watched = rep.setup
	if game is DuelSim:
		duel = game
		_new_sim(duel.sim, s)
		hud.duel = duel
		hud.timer_ticks = duel.timer
	elif game is TeamSim:
		team_battle = game
		_new_sim(team_battle.sim, s)
		hud.team = team_battle
		hud.focus = 0
		hud.timer_ticks = team_battle.timer
		_show_pads()
	elif game is BrawlSim:
		brawl = game
		_chaos_names = ""
		_new_sim(brawl.sim, s)
		hud.brawl = brawl
		hud.focus = 0
		hud.timer_ticks = brawl.timer
	else:
		_new_sim(built["sim"], s)
		timer = ROUND_TICKS
		hud.timer_ticks = timer
		flow = Flow.INTRO
		flow_t = 0
		hud.wins = wins
		audio.play_music("fight")
		return
	hud.wins = [0, 0]
	hud.wins_needed = 0
	hud.banner = ""
	flow = Flow.FIGHT
	flow_t = 0
	audio.play_music("fight")


func _replaying() -> bool:
	return mode == REPLAY_MODE and not _replay_frames.is_empty()


## Team Deathmatch: one spawn pad per fighter slot, against its team's side wall.
func _show_pads() -> void:
	fx.pads = []
	fx.zone = {}
	fx.caravan = {}
	if team_battle == null or not team_battle.deathmatch or team_battle.caravan or team_battle.ctf:
		return  # the Caravan's attackers respawn where the push has got to; CTF's at their keep
	for side in 2:
		for k in team_battle.size:
			fx.pads.append({"pos": team_battle.pad_point(side, k), "color": Hud.SIDE_COLORS[side], "count": 0})


## King of the Crater: the zone on the floor, in the holder's colour.
func _update_zone() -> void:
	fx.flags = []
	fx.shrines = []
	if team_battle != null and team_battle.ctf:
		for side in 2:
			var st := int(team_battle.flag_state[side])
			var lift := 0.0
			if st == TeamSim.FLAG_CARRIED:
				var c := sim.creatures[int(team_battle.flag_carrier[side])]
				lift = float(c.def.get("fx_top", 32)) + c.air_height() + 2.0
			elif st == TeamSim.FLAG_THROWN:
				var k := clampf(float(team_battle.flag_ft[side]) / float(team_battle.flag_fn[side]), 0.0, 1.0)
				var from := float(sim.creatures[int(team_battle.flag_by[side])].def.get("fx_top", 32)) * (1.0 - k)
				lift = from + 4.0 * k * (1.0 - k) * minf(48.0, 8.0 + float(team_battle.flag_fn[side]) * 1.2)
			fx.flags.append({"pos": team_battle.flag_pos[side], "team": side, "state": st, "lift": lift,
				"back": float(team_battle.flag_t[side]) / maxf(1.0, float(team_battle.rules.get("return_seconds", 12)) * 60.0)})
		fx.shrines = []
		for i in team_battle.shrines.size():
			var st: Array = team_battle.shrines[i]
			fx.shrines.append({"pos": team_battle.shrine_pos(i), "radius": team_battle.shrine_radius(i),
				"kind": team_battle.shrine_kind(i), "side": int(st[0]),
				"claim": float(st[1]) / maxf(1.0, float(team_battle.shrine_claim_ticks())), "rest": ceili(int(st[2]) / 60.0)})
		fx.zone = {}
		return
	if team_battle != null and team_battle.caravan:
		var was: Dictionary = fx.caravan
		var at := team_battle.caravan_pos()
		var travel := float(was.get("travel", 0.0))
		if not was.is_empty():
			travel += Vector2(was["pos"]).distance_to(at)
		fx.caravan = {"pos": at, "heading": team_battle.caravan_heading(), "radius": float(team_battle.rules.get("radius", 56)),
			"state": team_battle.cv_state, "team": team_battle.cv_attacker(), "travel": travel,
			"healing": team_battle.members(team_battle.cv_attacker()).filter(func(c): return team_battle.escort_healing(c)).map(func(c): return c.id)}
		fx.zone = {}
		return
	if team_battle == null or not team_battle.crater or sim.zone_r <= 0.0:
		fx.zone = {}
		return
	var holder := team_battle.zone_holder()
	fx.zone = {"pos": sim.zone_pos, "radius": sim.zone_r,
		"color": Hud.SIDE_COLORS[holder] if holder >= 0 else Color("e8d8a0")}


## Each pad's countdown: the seconds until the fighter whose pad it is comes back.
func _update_pads() -> void:
	if fx.pads.is_empty() or team_battle == null:
		return
	var k := [0, 0]
	for slot in team_battle.slot_count():
		var c := sim.creatures[slot]
		var idx: int = c.team * team_battle.size + int(k[c.team])
		k[c.team] += 1
		if idx < fx.pads.size():
			var t := int(team_battle.respawn_t[slot])
			fx.pads[idx]["count"] = ceili(t / 60.0) if t > 0 else 0
	var me := sides.find(Side.PLAYER)
	hud.respawn_in = ceili(int(team_battle.respawn_t[me]) / 60.0) if me >= 0 and int(team_battle.respawn_t[me]) > 0 else -1


## The picked teams, topped up from DEFAULT_TEAMS so each side has `per_side` fighters.
func _padded_teams(per_side: int) -> Array:
	var out: Array = []
	for side in 2:
		var t: Array = (_teams[side] as Array).duplicate() if side < _teams.size() else []
		var k := 0
		while t.size() < per_side:
			t.append(DEFAULT_TEAMS[side][k % DEFAULT_TEAMS[side].size()])
			k += 1
		out.append(t.slice(0, maxi(per_side, 1)))
	return out


func _team_flow() -> void:
	hud.timer_ticks = maxi(team_battle.timer, 0)
	match team_battle.phase:
		TeamSim.Phase.INTRO:
			var t := team_battle.phase_t
			var what := "KING OF THE CRATER" if team_battle.crater \
				else ("SINKHOLE" if team_battle.sinkhole else ("TEAM DEATHMATCH" if team_battle.deathmatch else "TEAM BATTLE"))
			if team_battle.caravan:
				what = "CARAVAN: ROUND %d" % (team_battle.cv_round + 1)
				_update_zone()
			elif team_battle.ctf:
				what = "CAPTURE THE FLAG"
				_update_zone()
			hud.banner = (("ONLINE " + what) if online != null else what) if t < 60 else "FIGHT!"
			var sub := "%d v %d" % [team_battle.size, team_battle.size]
			if team_battle.ctf:
				sub += "   ·   bring their flag to yours: first to %d" % team_battle.score_to_win()
			elif team_battle.caravan:
				var att := team_battle.cv_attacker()
				sub += "   ·   %s escorts the caravan to the %s end" % [["Red", "Blue"][att], ["blue", "red"][att]]
			elif team_battle.crater:
				sub += "   ·   hold the zone %d s" % (team_battle.score_to_win() / 60)
			elif team_battle.deathmatch:
				sub += "   ·   first to %d KOs" % team_battle.score_to_win()
			elif team_battle.sinkhole:
				sub += "   ·   the edge falls in, the chasm is a KO"
			hud.banner_sub = sub if t < 60 else ""
			if t == 2 or t == 60:
				audio.play("round_start", 0.0, 0.75 if t == 2 else 1.0)
			if t == 60:  # your class's perk in this mode, as the fight starts
				var me := sides.find(Side.PLAYER) if online == null else online.local_slot
				if me >= 0 and team_battle.perk_text(sim.creatures[me]) != "":
					var c := sim.creatures[me]
					hud.show_toast("%s PERK: %s" % [TeamSim.role_of(c).to_upper(), team_battle.perk_text(c).to_upper()])
		TeamSim.Phase.FIGHT:
			_update_pads()
			_update_zone()
			for e in sim.events:
				if e["type"] == "sink_warn":
					hud.show_toast("THE EDGE IS FALLING")
				elif e["type"] == "zone_move":
					hud.show_toast("THE CRATER MOVED")
				elif e["type"] == "checkpoint":
					hud.show_toast("CHECKPOINT  +%d s" % int(team_battle.rules.get("checkpoint_seconds", 30)))
				elif e["type"] == "rockslide":
					hud.show_toast("ROCKSLIDE!  DIG THROUGH IT, OR SMASH IT WITH A CHARGE")
				elif e["type"] == "rubble_clear":
					hud.show_toast("THE ROAD IS CLEAR")
				elif e["type"] in ["flag_take", "flag_drop", "flag_return", "capture", "flag_fumble", "flag_pass",
						"flag_land", "shrine", "shrine_ready", "bridge_fall", "bridge_strain", "bridge_up"]:
					_ctf_toast(e)
			if team_battle.overtime and team_battle.timer > -90:
				hud.banner = "SUDDEN DEATH"
				hud.banner_sub = "Next capture wins" if team_battle.ctf 					else ("First alone in the zone wins" if team_battle.crater else "Next KO wins")
			else:
				hud.banner = ""
				hud.banner_sub = ""
		TeamSim.Phase.OVER:
			_update_pads()
			hud.respawn_in = -1
			if team_battle.phase_t == 1:
				if team_battle.deathmatch:
					hud.banner = "GAME!" if team_battle.timer > 0 or team_battle.overtime else "TIME"
					hud.banner_sub = "%s  -  %s" % [team_battle.score_text(0), team_battle.score_text(1)]
				else:
					hud.banner = "K.O." if team_battle.timer > 0 else "TIME"
					hud.banner_sub = ""
			if team_battle.phase_t >= int(team_battle.rules.get("over_ticks", 150)):
				flow = Flow.MATCH_OVER
				flow_t = 0
				var w := team_battle.winner
				var me := sides.find(Side.PLAYER)
				if w < 0:
					hud.banner = "DRAW"
				elif me >= 0:
					hud.banner = "YOUR TEAM WINS!" if sim.creatures[me].team == w else "YOUR TEAM LOSES"
				else:
					hud.banner = "%s TEAM WINS!" % ("RED" if w == 0 else "BLUE")
				hud.banner_sub = _over_reason()


## Capture the Flag: what each play says at the bottom of the screen; the local team's
## flag being taken also flashes the screen's edge red, and the local carrier is told how
## to pass.
func _ctf_toast(e: Dictionary) -> void:
	var side := int(e.get("team", 0))
	var whose: String = ["RED", "BLUE"][clampi(side, 0, 1)]
	var other: String = ["BLUE", "RED"][clampi(side, 0, 1)]
	var me := sides.find(Side.PLAYER) if online == null else online.local_slot
	match String(e["type"]):
		"flag_take":
			if bool(e.get("catch", false)):
				hud.show_toast("CAUGHT!  %s HAS THE %s FLAG" % [other, whose])
			else:
				hud.show_toast("%s FLAG TAKEN" % whose)
			if is_local_team(side) and (me < 0 or sim.creatures[me].team == side):
				hud.alert(Hud.SIDE_COLORS[side])
				hud.show_toast("YOUR FLAG IS TAKEN!  GET IT BACK")
			elif me >= 0 and int(e.get("who", -1)) == me:
				var key := String(hud.tag_labels[me]) if me < hud.tag_labels.size() else ""
				hud.show_toast("YOU HAVE THE FLAG  ·  RUN IT HOME" + ("  ·  %s: PASS" % key if key != "" else ""))
		"flag_drop": hud.show_toast("%s FLAG DROPPED" % whose)
		"flag_land": hud.show_toast("%s FLAG ON THE GROUND" % whose)
		"flag_fumble": hud.show_toast("FUMBLE!  THE %s FLAG IS LOOSE" % whose)
		"flag_pass": hud.show_toast("%s PASSES" % other)
		"flag_return":
			hud.show_toast("INTERCEPTED!  %s FLAG HOME" % whose if bool(e.get("intercept", false)) else "%s FLAG RETURNED" % whose)
		"capture":
			hud.show_toast("%s CAPTURES!" % whose)
			var sc: Array = e.get("score", [0, 0])
			hud.moment("%s CAPTURES!" % whose, "%d  -  %d" % [int(sc[0]), int(sc[1])], Hud.SIDE_COLORS[side])
		"shrine":
			hud.show_toast("%s CLAIMS THE %s SHRINE" % [whose, String(e.get("kind", "")).to_upper()])
		"shrine_ready": hud.show_toast("THE %s SHRINE IS READY" % String(e.get("kind", "")).to_upper())
		"bridge_strain": hud.show_toast("THE BRIDGE IS CRACKING")
		"bridge_fall": hud.show_toast("THE BRIDGE IS DOWN!")
		"bridge_up": hud.show_toast("THE BRIDGE IS BACK")


## Capture the Flag's end-of-match line per fighter (view-side, from the events):
## captures, returns (interceptions too) and stops (carriers knocked out or made to fumble).
var _ctf_stats := {}
var _ctf_stats_for: TeamSim = null


func _count_ctf(e: Dictionary) -> void:
	if team_battle == null or not team_battle.ctf:
		return
	if _ctf_stats_for != team_battle:
		_ctf_stats = {}
		_ctf_stats_for = team_battle
	var add := func(who: int, key: String):
		if who >= 0:
			var row: Dictionary = _ctf_stats.get(who, {"caps": 0, "rets": 0, "stops": 0})
			row[key] = int(row[key]) + 1
			_ctf_stats[who] = row
	match String(e["type"]):
		"capture": add.call(int(e.get("who", -1)), "caps")
		"flag_return": add.call(int(e.get("who", -1)), "rets")
		"flag_drop", "flag_fumble": add.call(int(e.get("by", -1)), "stops")


## The match's most valuable player and everyone's line, for the match-over screen.
func _ctf_summary() -> Array:
	var lines: Array = []
	if team_battle == null or not team_battle.ctf or sim == null:
		return lines
	var best := -1
	var best_v := 0
	for c in sim.creatures:
		var row: Dictionary = _ctf_stats.get(c.id, {"caps": 0, "rets": 0, "stops": 0}) if _ctf_stats_for == team_battle else {"caps": 0, "rets": 0, "stops": 0}
		var v := int(row["caps"]) * 3 + int(row["rets"]) + int(row["stops"])
		if v > best_v:
			best_v = v
			best = c.id
		lines.append(["%s   %d cap  %d ret  %d stop" % [String(c.def.get("name", "?")), int(row["caps"]), int(row["rets"]),
			int(row["stops"])], Hud.SIDE_COLORS[c.team]])
	if best >= 0:
		var c := sim.creatures[best]
		lines.push_front(["MVP  %s  (%s)" % [String(c.def.get("name", "?")).to_upper(), ["RED", "BLUE"][c.team]], UiTheme.C_ACCENT])
	return lines


func _start_coach(help: String) -> void:
	_new_sim(coach.build(), MODES[mode]["sides"])
	hud.timer_ticks = -1
	hud.banner = ""
	hud.caption_title = coach.title
	hud.caption_items = coach.caption_items
	hud.caption_index = coach.caption_index
	hud.show_help = true
	hud.help_text = help
	flow = Flow.FIGHT
	flow_t = 0


func _end_coach() -> void:
	if coach == null:
		return
	coach = null
	hud.caption_title = ""
	hud.banner = ""
	_apply_device()


## After each step: let the coach judge, then show what it wants shown.
func _coach_step() -> void:
	coach.after_step()
	if coach.sim != sim:  # a new trial or drill set built a fresh match
		_new_sim(coach.sim, MODES[mode]["sides"])
	if coach.reset_view:
		coach.reset_view = false
		fx.clear()
		_ko_cam_t = -1
	for c in coach.callouts:
		fx.callout(c[0], String(c[1]), c[2])
	coach.callouts.clear()
	hud.caption_title = coach.title
	hud.caption_items = coach.caption_items
	hud.caption_index = coach.caption_index
	if coach is ReactionDrill and coach.phase == ReactionDrill.Phase.DONE:
		hud.banner = coach.banner
		hud.banner_sub = "Average reaction: %s" % String(coach.caption_items[3]).trim_prefix("Avg reaction ")
	else:
		hud.banner = ""
		hud.banner_sub = ""


func _end_duel() -> void:
	duel = null
	team_battle = null
	brawl = null
	_replay_frames = []
	if hud != null:
		hud.duel = null
		hud.team = null
		hud.brawl = null
		hud.wins_needed = WINS_NEEDED


func _duel_flow() -> void:
	hud.timer_ticks = maxi(duel.timer, 0)
	var rounds := duel.rounds_to_win() > 1
	if rounds:
		hud.wins = duel.round_wins
		hud.wins_needed = duel.rounds_to_win()
	match duel.phase:
		DuelSim.Phase.INTRO:
			var t := duel.phase_t
			hud.banner = ("ONLINE DUEL" if online != null else "DUEL") if t < 60 else "FIGHT!"
			if rounds and t < 60:
				hud.banner = "ROUND %d" % duel.round_num
				var lead := maxi(duel.round_wins[0], duel.round_wins[1])
				hud.banner_sub = "FINAL ROUND" if lead == duel.rounds_to_win() - 1 and 					duel.round_wins[0] == duel.round_wins[1] else "Best of %d" % (duel.rounds_to_win() * 2 - 1)
			elif rounds:
				hud.banner_sub = ""
			elif (duel.teams[0] as Array).size() > 1:
				hud.banner_sub = "%d v %d  -  tag with %s" % [duel.teams[0].size(), duel.teams[1].size(),
					player_input.label("tag")] if t < 60 else ""
			else:
				hud.banner_sub = "1 v 1" if t < 60 else ""
			if arcade != null and t < 60:  # the Arcade's boss stage: which stage, against whom
				hud.banner = arcade.stage_label()
				hud.banner_sub = arcade.versus_label()
			if t == 2 or t == 60:
				audio.play("round_start", 0.0, 0.75 if t == 2 else 1.0)
		DuelSim.Phase.FIGHT, DuelSim.Phase.SWAP:
			hud.banner = ""
			hud.banner_sub = ""
		DuelSim.Phase.ROUND_OVER, DuelSim.Phase.OVER:
			if duel.phase_t == 1:
				hud.banner = "K.O." if duel.timer > 0 else "TIME"
				hud.banner_sub = ""
				if rounds:
					var w := duel.round_winner
					hud.banner_sub = "%s takes the round" % String(duel.active_creature(w).def["name"]) 						if w >= 0 else "Draw"
					crowd.cheer(1.0)
			if duel.phase == DuelSim.Phase.ROUND_OVER:
				return
			if duel.phase_t >= int(duel.rules.get("over_ticks", 150)):
				if _arcade_result(duel.winner == 0):
					return
				flow = Flow.MATCH_OVER
				flow_t = 0
				if duel.winner < 0:
					hud.banner = "DRAW"
				elif online != null:
					hud.banner = "YOU WIN!" if duel.winner == online.local_side else "YOU LOSE"
				else:
					hud.banner = "%s WINS!" % _side_name(duel.winner)
				hud.banner_sub = _over_reason()


## How the last fight ended (the sim's `by`: ko, time, score, hold, capture, caravan),
## as the line under the winner on the final banner.
var _over_by := ""
## The Arcade run just ended in a clear (the match-over menu offers a new run, not a retry).
var _arcade_cleared := false


func _over_reason() -> String:
	var tb := team_battle
	var scores := ""
	if tb != null and tb.deathmatch:
		var a := tb.score_text(0)
		var b := tb.score_text(1)
		if tb.caravan:
			scores = ("Faster finish" if int(tb.cv_time[0]) >= 0 or int(tb.cv_time[1]) >= 0 else "Pushed further") 				+ ":  %s - %s" % [a, b]
		elif tb.ctf:
			scores = "Captures  %s - %s" % [a, b]
		elif tb.crater:
			scores = "Zone time  %s s - %s s" % [a, b]
		else:
			scores = "Score  %s - %s" % [a, b]
	match _over_by:
		"ko":
			return "K.O."
		"time":
			return ("Time: " + scores) if scores != "" else "Time: more health left"
		"score", "hold", "capture":
			return ("Sudden death: " if tb != null and tb.overtime else "") + scores
		"caravan":
			return scores
	return ""


func _side_name(i: int) -> String:
	if watch != null and i < sim.creatures.size():
		return String(sim.creatures[i].def.get("name", "?")).to_upper()
	match sides[i]:
		Side.PLAYER:
			return "YOU" if online != null else "PLAYER 1"
		Side.REMOTE:
			return "OPPONENT"
		Side.PLAYER2:
			return "PLAYER 2"
		Side.PLAYER3:
			return "PLAYER 3"
		Side.PLAYER4:
			return "PLAYER 4"
		Side.CPU:
			return "CPU"
		Side.REPLAY:
			return "REPLAY"
	return "SIDE %d" % (i + 1)


## Scripted demos: both sides follow a Showcase, with captions naming each move.
func _start_showcase() -> void:
	showcase = Showcase.new(String(_showcase_list[_showcase_i % _showcase_list.size()]))
	_new_sim(showcase.build(), [Side.SCRIPT, Side.SCRIPT])
	_showcase_end_t = 0
	_cam_follow = Vector2.ZERO
	_cam_zoom = 0.0
	hud.timer_ticks = -1
	hud.banner = ""
	hud.show_help = false
	hud.caption_title = showcase.title()
	hud.caption_items = showcase.caption_items()
	hud.caption_index = -1
	flow = Flow.FIGHT
	flow_t = 0


func _end_showcase() -> void:
	_showcase_list = []
	if showcase == null:
		return
	showcase = null
	hud.caption_title = ""
	hud.show_help = true
	fade_rect.color.a = 0.0


func _new_sim(s: MatchSim, p_sides: Array) -> void:
	_join_cpus()  # the CPUs may still be reading the old match
	sim = s
	_cam_zoom = 0.0  # frame the new fight straight away
	_cam_lead = Vector2.ZERO
	_cam_prev = []
	_cam_push = 0.0
	_exchange_t = 0
	_exchange_hits = 0
	_surge_bars = 0
	if letterbox != null:
		letterbox.clear()
	sides = p_sides.duplicate()
	while sides.size() < sim.creatures.size():
		sides.append(Side.CPU)  # a team battle's other slots
	if _cpu_vs_cpu:
		for i in sides.size():
			if sides[i] in LOCAL_SIDES:
				sides[i] = Side.CPU
	replay = Replay.new()
	replay.setup = _replay_setup(s)
	cpus = []
	cpus.resize(sides.size())
	hud.resize_slots(sides.size())
	for i in sides.size():
		if sides[i] == Side.CPU:
			cpus[i] = CpuController.new(i, _cpu_level_override if _cpu_level_override >= 0 else level,
				seed_base * 101 + round_num * 7 + i)
	arena.ground = String(sim.arena.get("ground", "dirt"))
	arena.arena_id = String(sim.arena.get("id", ""))
	shadows.light = ShadowLayer.light_of(sim.arena)
	var two_sides := true  # (a Brawl of three or four has no sides for the stands to take)
	for c in sim.creatures:
		two_sides = two_sides and c.team >= 0 and c.team <= 1
	crowd.set_size(sim.arena_size(), two_sides)
	arena.set_terrain(sim.terrain)
	for v in views:
		v.queue_free()
	views.clear()
	for c in sim.creatures:
		var v := CreatureView.new()
		entities.add_child(v)
		v.setup(c)
		if c.id < sides.size() and sides[c.id] == Side.PLAYER:
			v.palette = Progress.palette(String(c.def.get("id", "")))
		views.append(v)
	debug.sim = sim
	rings.set_sim(sim)
	water.set_sim(sim)
	wear.set_sim(sim)
	water.fx = fx
	paper.set_sim(sim)
	hud.sim = sim
	fx.sim = sim
	fx.clear()
	fx.views = views
	vision.clear()
	_hidden = []
	fx.vision = vision
	_ko_cam_t = -1
	hud.dummy_mode_name = DUMMY_MODES[dummy_mode]
	hud.mutator_text = "  ·  ".join(Daily.mutator_names(sim.mutators).map(func(n): return String(n).to_upper()))
	# Red for the left side (P1), blue for the right (P2 or the CPU): a marker over each
	# fighter and a stripe on its health panel.
	fx.side_marks = []
	for i in mini(sides.size(), sim.creatures.size()):
		var label := ""
		match sides[i]:
			Side.PLAYER:
				label = "P1"
			Side.PLAYER2:
				label = "P2"
			Side.PLAYER3:
				label = "P3"
			Side.PLAYER4:
				label = "P4"
			Side.CPU:
				label = "CPU"
			Side.REMOTE:
				label = "ONLINE"
			Side.REPLAY:
				label = "REPLAY"
			Side.SCRIPT:
				label = ""
		if sim.creatures[i].is_dummy:
			label = ""
		var mark_col: Color = Hud.BRAWL_COLORS[i % Hud.BRAWL_COLORS.size()] if brawl != null and brawl.sim == s \
			else Hud.SIDE_COLORS[clampi(sim.creatures[i].team, 0, 1)]
		fx.side_marks.append({"color": mark_col, "label": label, "rel": _relation(i)})
	rings.rel = fx.side_marks.map(func(m): return m["rel"])
	for i in sides.size():
		match sides[i]:
			Side.PLAYER:
				hud.tags[i] = "P1"
			Side.CPU:
				hud.tags[i] = "CPU " + LEVEL_NAMES[level]
				hud.key_labels[i] = ["", "", ""]
			Side.SCRIPT:
				hud.tags[i] = "DEMO"
				hud.key_labels[i] = ["", "", ""]
			Side.PLAYER2:
				hud.tags[i] = "P2"
			Side.PLAYER3:
				hud.tags[i] = "P3"
			Side.PLAYER4:
				hud.tags[i] = "P4"
			Side.REMOTE:
				hud.tags[i] = "ONLINE"
				hud.key_labels[i] = ["", "", ""]
			Side.REPLAY:
				hud.tags[i] = "REPLAY"
				hud.key_labels[i] = ["", "", ""]
			_:
				hud.tags[i] = ""
	shake = 0.0
	for pin in [player_input, player2_input, player3_input, player4_input]:
		(pin as PlayerInput).reset()
	_apply_device()


## What this match is, saved with its replay so ReplayBuilder can rebuild it.
func _replay_setup(s: MatchSim) -> Dictionary:
	var ids: Array = []
	for c in s.creatures:
		ids.append(String(c.def.get("id", "")))
	var st := {"kind": "versus", "ids": ids, "arena": s.arena_id, "mutators": s.mutators.duplicate(),
		"mut_seed": (arcade as Daily).date if arcade is Daily else seed_base}
	if duel != null and duel.sim == s:
		st["kind"] = "duel"
		st["teams"] = _teams.duplicate(true)
	elif team_battle != null and team_battle.sim == s:
		st["kind"] = "team"
		st["teams"] = _teams.duplicate(true)
		st["size"] = team_battle.size
		st["rules"] = _rules_id
	elif brawl != null and brawl.sim == s:
		st["kind"] = "brawl"
	elif s.training:
		st["kind"] = "training"
		st["training_flags"] = s.training_flags.duplicate()
		st["flag_changes"] = []  # options changed mid-recording (_apply_training_opts)
	return st


## Every rendered frame: on a real connection, read the network now rather than at the
## next tick, so the other player's inputs (and pongs) are in hand the moment they land.
func _process(_delta: float) -> void:
	if _perf != null:
		PerfLog.mark()
		_perf.frame(flow == Flow.FIGHT and not paused)
	if netplay != null and netplay.link != null and netplay.link.realtime:
		netplay.pump()
	if discord != null:
		if Engine.get_process_frames() % 30 == 0:
			discord.set_activity(presence.activity(self))
		discord.poll()


func _physics_process(_delta: float) -> void:
	if sim == null:
		return  # quitting after --sim-check
	var tick_start := Time.get_ticks_usec()
	PerfLog.mark()
	_join_cpus()
	frame_count += 1
	_apply_frame_rate()
	if paused:
		_capture()
		return  # frozen behind the pause menu: nothing steps, the picture holds
	flow_t += 1
	if _finder != null:
		_finder_step()
	if _daily_client != null:
		_daily_step()
	var live := flow == Flow.FIGHT or flow == Flow.MENU
	var offline := false
	var events: Array = sim.events
	if online != null:
		# Online: the rollback session steps the duel (maybe several frames, maybe none
		# while it waits); the views get only the events they haven't shown yet.
		live = flow == Flow.FIGHT or flow == Flow.MATCH_OVER
		netplay.tick(_side_bits(online.local_slot, live and not ui.is_open()))
		events = online.events
		_online_status()
	elif watch != null:
		# Watching: the referee's copy steps on confirmed inputs only (maybe several
		# frames a tick, maybe none); its events are the ones to show.
		live = flow == Flow.FIGHT or flow == Flow.MATCH_OVER
		netplay.tick(0)
		if netplay.watch != null and netplay.watch != watch and netplay.phase == Netplay.Phase.PLAYING:
			_start_watching()  # the next match (a rematch, or the room's next): follow it
		events = watch.events
		if netplay.phase == Netplay.Phase.ENDED and flow == Flow.FIGHT:
			flow = Flow.MATCH_OVER
			flow_t = 0
			hud.banner = "THE MATCH ENDED"
			hud.banner_sub = netplay.status
		_watch_room_status()
	elif netplay != null and _connecting_step():
		events = online.events  # the online match began this frame: its session steps it
	else:
		offline = true
		var inputs := PackedInt32Array()
		var t_cpu := PerfLog.now()
		_think_cpus(live)
		PerfLog.since("cpus", t_cpu)
		for i in sides.size():
			inputs.append(_side_bits(i, live))
		_cpus_thought = false
		if showcase != null and flow == Flow.FIGHT:
			inputs = showcase.inputs(sim)
		elif coach != null and flow == Flow.FIGHT:
			inputs = coach.inputs(_side_bits(0, true))
		if flow == Flow.FIGHT or flow == Flow.INTRO:
			# The intro too: the sim idles through it, and a replay side reads its frame by
			# sim.tick, so a Versus round's recording has to start where the sim does.
			replay.record(inputs)
		if _replaying() and sim.training:
			ReplayBuilder.apply_flag_changes(sim, _replay_watched, sim.tick)
		var t_sim := PerfLog.now()
		if duel != null:
			duel.step(inputs)
		elif team_battle != null:
			team_battle.step(inputs)
		elif brawl != null:
			brawl.step(inputs)
		else:
			sim.step(inputs)
		PerfLog.since("sim", t_sim)
		events = sim.events
	var t_ev := PerfLog.now()
	_update_vision(events)
	PerfLog.since("vision", t_ev)
	t_ev = PerfLog.now()
	for e in events:
		_react(e)
	PerfLog.since("events", t_ev)
	if coach != null and flow == Flow.FIGHT:
		_coach_step()
	# A Duel tag or a new teammate: show whoever is in each slot now.
	for i in views.size():
		if views[i].c != sim.creatures[i]:
			views[i].rebind(sim.creatures[i])
	audio.watch(sim)
	# Effects freeze with the KO freeze and slow down with the slow motion.
	fx.time_scale = 0.0 if sim.ko_freeze > 0 else (0.5 if sim.slowmo > 0 else 1.0)
	audio.sfx_enabled = flow != Flow.MENU
	_update_flow()
	if showcase != null:
		hud.caption_items = showcase.caption_items()
		hud.caption_index = showcase.show
		fade_rect.color.a = showcase.fade
	elif _swap_fade > 0.0:
		_swap_fade = maxf(0.0, _swap_fade - 1.0 / 16.0)  # a fighter swap fades in from black
		fade_rect.color.a = _swap_fade

	var t_fx := PerfLog.now()
	arena.refresh()
	water.advance()
	wear.advance()
	crowd.advance()
	fx.advance()
	PerfLog.since("fx advance", t_fx)
	var t_views := PerfLog.now()
	paper.advance(events)
	hud.advance()
	if rings.visible:
		rings.advance()
	var deciding := flow == Flow.ROUND_OVER or flow == Flow.MATCH_OVER or _sim_decided()
	for i in views.size():
		views[i].victory = deciding and _won_standing(sim.creatures[i])
		views[i].out_of_sight = _is_hidden(i)
		views[i].see_through = _hides_someone(views[i].c)
		views[i].refresh()
	if debug.visible:
		debug.queue_redraw()
	PerfLog.since("views advance", t_views)

	shake = maxf(shake, fx.shake_out)
	fx.shake_out = 0.0
	if fx.shake_dir != Vector2.ZERO:
		shake_dir = fx.shake_dir
		fx.shake_dir = Vector2.ZERO
	if fx.flash_out > 0.0:
		_flash(Color(1, 0.95, 0.75), fx.flash_out)
		fx.flash_out = 0.0
	if sim.ko_freeze <= 0:
		shake *= 0.82
	var t_cam := PerfLog.now()
	_update_camera()
	_update_letterbox()
	PerfLog.since("camera", t_cam)
	var sh := shake * shake_scale
	if sh <= 0.3:
		shake_dir = Vector2.ZERO
		camera.offset = Vector2.ZERO
	elif shake_dir != Vector2.ZERO:  # a hit: most of it along the push, a little across
		camera.offset = (shake_dir * sh * randf_range(-1.0, 1.0) + shake_dir.orthogonal() * sh * randf_range(-0.3, 0.3)).round()
	else:
		camera.offset = Vector2(randf_range(-sh, sh), randf_range(-sh, sh)).round()
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - 0.04)
	if offline and (flow == Flow.FIGHT or flow == Flow.MENU):
		_think_ahead()
	if _perf != null:
		_perf.tick(flow == Flow.FIGHT, Time.get_ticks_usec() - tick_start)
	perf_overlay.tick(Time.get_ticks_usec() - tick_start)
	_capture()


func _update_flow() -> void:
	match flow:
		Flow.MENU:
			# Restart the background match a little after it ends.
			if _ko_side() != -2:
				_menu_ko_t += 1
			if _menu_ko_t > 150 or flow_t > ROUND_TICKS:
				_menu_ko_t = 0
				seed_base += 1
				_menu_background()
		Flow.INTRO:
			if arcade != null:
				hud.banner = arcade.stage_label() if flow_t < 60 else "FIGHT!"
				hud.banner_sub = arcade.versus_label() if flow_t < 60 else ""
			else:
				hud.banner = "ROUND %d" % round_num if flow_t < 60 else "FIGHT!"
				hud.banner_sub = ""
			if flow_t == 2 or flow_t == 60:
				audio.play("round_start", 0.0, 0.75 if flow_t == 2 else 1.0)
			if flow_t >= INTRO_TICKS:
				hud.banner = ""
				flow = Flow.FIGHT
				flow_t = 0
		Flow.FIGHT:
			if _replaying() and sim.tick >= _replay_frames.size() and (duel != null or team_battle != null or brawl != null):
				flow = Flow.MATCH_OVER
				flow_t = 0
				hud.banner = "END OF REPLAY"
				hud.banner_sub = ""
				return
			if duel != null:
				_duel_flow()
				return
			if team_battle != null:
				_team_flow()
				return
			if brawl != null:
				_brawl_flow()
				return
			if coach != null:
				return
			if showcase != null:
				if showcase.finished:
					_showcase_end_t += 1
					if _showcase_end_t > 20:
						_showcase_i += 1
						_start_showcase()
				return
			if MODES[mode].get("training", false):
				return
			timer -= 1
			hud.timer_ticks = maxi(timer, 0)
			var ko := _ko_side()
			if ko != -2 or timer <= 0 or (_replaying() and sim.tick >= _replay_frames.size()):
				_end_round(ko)
		Flow.ROUND_OVER:
			if flow_t >= ROUND_OVER_TICKS:
				if _replaying():
					flow = Flow.MATCH_OVER
					flow_t = 0
					hud.banner = "END OF REPLAY"
					hud.banner_sub = ""
					return
				var needed := 1 if arcade != null else WINS_NEEDED
				if wins[0] >= needed or wins[1] >= needed:
					if _arcade_result(wins[0] >= needed):
						return
					flow = Flow.MATCH_OVER
					flow_t = 0
					var w := 0 if wins[0] >= needed else 1
					hud.banner = "%s WINS!" % String(sim.creatures[w].def["name"]).to_upper()
					hud.banner_sub = _over_reason()
				else:
					round_num += 1
					_start_round()
		Flow.MATCH_OVER:
			if duel != null:
				hud.timer_ticks = maxi(duel.timer, 0)
			elif team_battle != null:
				hud.timer_ticks = maxi(team_battle.timer, 0)
			if flow_t == MATCH_OVER_MENU_AT and not ui.is_open():
				_show_match_over()
			if sides[0] == Side.CPU and sides[1] == Side.CPU and flow_t > 240:
				seed_base += 1
				_start_match(mode)


## -2: nobody is down. 0 or 1: that side was knocked out. -1: both.
func _ko_side() -> int:
	var k0 := sim.creatures[0].state == CreatureSim.State.KO
	var k1 := sim.creatures[1].state == CreatureSim.State.KO
	if k0 and k1:
		return -1
	if k0:
		return 0
	if k1:
		return 1
	return -2


func _end_round(ko: int) -> void:
	_carried_energy = [sim.creatures[0].energy, sim.creatures[1].energy]
	flow = Flow.ROUND_OVER
	flow_t = 0
	audio.play("round_end")
	var winner := -1
	if ko == 0:
		winner = 1
	elif ko == 1:
		winner = 0
	elif ko == -2:
		var r0 := sim.creatures[0].hp / sim.creatures[0].max_hp
		var r1 := sim.creatures[1].hp / sim.creatures[1].max_hp
		winner = 0 if r0 > r1 else (1 if r1 > r0 else -1)
	if winner >= 0:
		wins[winner] += 1
	hud.wins = wins
	_over_by = "ko" if ko != -2 else "time"
	hud.banner = "K.O." if ko != -2 else "TIME"
	hud.banner_sub = "%s takes the round" % String(sim.creatures[winner].def["name"]) if winner >= 0 else "Draw"
	crowd.cheer(1.0)


func _side_bits(i: int, live: bool) -> int:
	if not live:
		return 0
	match sides[i]:
		Side.PLAYER:
			if autoplay != null:
				return autoplay.bits(sim.tick + 1)
			var b := player_input.bits(sim, i, get_global_mouse_position())
			var ping: Dictionary = player_input.orders.ping
			if not ping.is_empty():
				fx.ping(ping["pos"], bool(ping["attack"]))
			return b
		Side.PLAYER2, Side.PLAYER3, Side.PLAYER4:
			return _local_input(sides[i]).bits(sim, i, Vector2.ZERO)
		Side.REPLAY:
			var t := sim.tick
			if t < _replay_frames.size() and i < (_replay_frames[t] as PackedInt32Array).size():
				return (_replay_frames[t] as PackedInt32Array)[i]
			return 0
		Side.REMOTE:
			return 0  # arrives over the network
		Side.CPU:
			if _cpus_thought:
				return (cpus[i] as CpuController).last_bits
			return (cpus[i] as CpuController).bits(sim)
		Side.DUMMY:
			return _dummy_bits()
	return 0


## Every CPU side chooses this tick's input at once, spread over the worker threads
## (CpuController.think_all); _side_bits then hands out the answers. Usually they were
## worked out while the last frame drew (_think_ahead), from this very match and tick.
func _think_cpus(live: bool) -> void:
	var ahead := _cpu_ahead
	_cpu_ahead = []
	_join_cpus()
	if not live:
		return
	if ahead.size() == 2 and ahead[0] == sim and ahead[1] == sim.tick:
		_cpus_thought = true
		return
	CpuController.think_all(_cpu_list(), sim)
	_cpus_thought = true


func _cpu_list() -> Array:
	var list: Array = []
	for i in mini(sides.size(), cpus.size()):
		if sides[i] == Side.CPU and cpus[i] != null:
			list.append(cpus[i])
	return list


## At the end of a tick: the CPUs start on the next tick's inputs now, on the worker
## threads, so their thinking overlaps the whole gap to the next tick instead of adding
## to it. _join_cpus waits for them at the next tick (_physics_process), or sooner when
## something could change the match before then: a press or a click (_input; mouse
## motion never touches the match), a training option, a fighter swap, a new match.
## Joining once the frame was drawn, as before, gave them only the draw's millisecond or
## two: a slow think (an A* replan) then stalled the frame. Something that changes the
## match between ticks (a training reset) leaves the CPUs one tick behind it, as a
## player would be.
func _think_ahead() -> void:
	if not _cpus_early or not CpuController.threaded:
		return
	var list := _cpu_list()
	if list.is_empty():
		return
	_cpu_ahead = [sim, sim.tick]
	_cpu_task = CpuController.think_start(list, sim)


func _join_cpus() -> void:
	if _cpu_task >= 0:
		var t0 := PerfLog.now()
		CpuController.think_wait(_cpu_task)
		_cpu_task = -1
		PerfLog.since("cpus wait", t0)


## Simple behaviours for the training dummy, picked with F2.
func _dummy_bits() -> int:
	var p := sim.creatures[0]
	var d := sim.creatures[1]
	match dummy_mode:
		1:
			return SimDefs.IN_GUARD
		2:
			return SimDefs.IN_LEFT if (sim.tick / 90) % 2 == 0 else SimDefs.IN_RIGHT
		3:
			# Roll away the moment the player commits to an attack.
			if p.state == CreatureSim.State.ATTACK and p.state_t == 1 and not p.charging:
				var away := (d.pos - p.pos).normalized()
				return SimDefs.IN_DODGE | SimDefs.bits_from_dir(Vector2(away.x, away.y + 0.5))
	return 0


## Whose fighter slot `i` is, from this machine's point of view, for its health bar
## colour: "self" (played here), "ally" (on that player's team), "enemy", or "side" when
## nobody here plays or local players are on both sides (local versus): then the bars
## use the side colours.
func _relation(i: int) -> String:
	var local_teams := {}
	for k in mini(sides.size(), sim.creatures.size()):
		if sides[k] in LOCAL_SIDES:
			local_teams[sim.creatures[k].team] = true
	if local_teams.size() != 1:
		return "side"
	if i < sides.size() and sides[i] in LOCAL_SIDES:
		return "self"
	return "ally" if local_teams.has(sim.creatures[i].team) else "enemy"


## The team whose eyes the screen uses: the one team the players here are on (online,
## the local slot's). -1 when there isn't exactly one (CPU vs CPU, replays, watching
## online, two local players on opposite sides): then everyone is shown, brush or not.
func _viewer_team() -> int:
	var local_teams := {}
	for k in mini(sides.size(), sim.creatures.size()):
		if sides[k] in LOCAL_SIDES:
			local_teams[sim.creatures[k].team] = true
	if local_teams.size() == 1:
		return int(local_teams.keys()[0])
	if local_teams.is_empty() and _view_team_arg >= 0:
		return _view_team_arg
	return -1


## Works out which fighters the local team can't see this tick (Vision: brush, fences,
## walls), after noting this tick's hits. Views and the camera skip them.
func _update_vision(events: Array) -> void:
	vision.observe(events)
	var team := _viewer_team()
	_hidden.resize(sim.creatures.size())
	for i in sim.creatures.size():
		_hidden[i] = team >= 0 and not vision.team_sees(sim, team, sim.creatures[i])
	fx.unseen = _hidden
	fx.viewer_team = team


func _is_hidden(i: int) -> bool:
	return i < _hidden.size() and bool(_hidden[i])


## Whether `team` is a side someone at this machine plays (or plays alongside, in a team
## battle). With nobody playing here (CPU vs CPU), the left side counts as "yours".
func is_local_team(team: int) -> bool:
	var any := false
	for i in mini(sides.size(), sim.creatures.size()):
		if sides[i] in LOCAL_SIDES:
			any = true
			if sim.creatures[i].team == team:
				return true
	return not any and team == 0


func _react(e: Dictionary) -> void:
	_count_ctf(e)
	fx.spawn(e)
	audio.on_event(e)
	var power: float = e["power"]
	_rumble(e)
	match String(e["type"]):
		"hit":
			shake = maxf(shake, 1.5 + power * 0.2)
			crowd.cheer(0.1 + power * 0.015)
			if fx._event_shown(e):  # (fans near a hidden fighter's hit would give it away)
				crowd.react(Vector2(e["pos"]), 4 + mini(4, int(power * 0.25)))
				_note_exchange()
		"block":
			shake = maxf(shake, 1.0)
			_note_exchange()
		"slam":
			shake = maxf(shake, 4.0 if power >= 1.0 else 2.0)
			crowd.cheer(0.3 if power >= 1.0 else 0.05)
		"bounce":
			shake = maxf(shake, 2.5)
			crowd.cheer(0.2)
		"fall":
			crowd.cheer(0.5)
		"guard_break", "breakaway", "slip":
			crowd.cheer(0.3)
		"surge":
			crowd.cheer(0.6)
			if not bool(e.get("freeze", true)):
				# A crowded field doesn't stop for it: no cut-in or flash, just the caster's
				# own call-out and windup (fx_view).
				shake = maxf(shake, 1.5)
				return
			_flash(Color(1, 0.95, 0.75), 0.55)
			shake = maxf(shake, 3.0)
			_surge_bars = maxi(_surge_bars, sim.hitstop)  # the letterbox holds for the freeze
			var who := int(e.get("who", 0))
			hud.cut_in(sim.creatures[who], clampi(sim.creatures[who].team, 0, 1), String(e.get("name", "Surge")))
		"score":
			crowd.cheer(0.5)
		"respawn":
			audio.play("warp", -4.0, 0.9)  # back on the pad
		"overtime":
			audio.play("round_start")
			crowd.cheer(0.6)
		"checkpoint", "caravan_done":
			audio.play("round_start", -3.0, 1.2)
			crowd.cheer(0.7)
		"rockslide":
			audio.play("cave_in")
			shake = maxf(shake, 5.0)
			crowd.roar(40)
		"rubble_clear":
			audio.play("stones_scatter", -2.0)
			crowd.cheer(0.4)
		"capture":
			audio.play("round_start", 0.0, 1.3)
			crowd.roar(90)
			_flash(Color(1, 0.92, 0.6), 0.45)
			shake = maxf(shake, 4.0)
		"flag_take":
			audio.play("grab", -2.0, 1.2)
			crowd.cheer(0.8 if bool(e.get("catch", false)) else 0.5)
			if team_battle != null and is_local_team(int(e.get("team", 0))):
				audio.play("windup_red", -2.0, 0.8)  # the alarm: it's ours
		"flag_fumble":
			audio.play("pop", 0.0, 0.9)
			crowd.cheer(0.7)
			shake = maxf(shake, 2.5)
		"flag_pass":
			audio.play("knife_throw", -3.0, 0.8)
		"flag_land":
			audio.play("land", -4.0, 1.2)
		"shrine":
			audio.play("surge_ready_ally" if is_local_team(int(e.get("team", 0))) else "surge_ready_foe")
			crowd.cheer(0.5)
		"shrine_ready":
			audio.play("chill", -6.0, 1.2)
		"bridge_strain":
			audio.play("crack", 0.0, 0.7)
		"bridge_fall":
			audio.play("cave_in")
			shake = maxf(shake, 6.0)
			crowd.roar(60)
		"bridge_up":
			audio.play("dig", -3.0, 0.8)
		"flag_drop", "flag_return":
			audio.play("warp", -4.0, 1.1)
			crowd.cheer(0.3)
		"surge_ready":
			# One sound when your side powers up, another when the other side does.
			var mine := is_local_team(int(e.get("team", 0)))
			audio.play("surge_ready_ally" if mine else "surge_ready_foe")
			crowd.cheer(0.15)
		"duel_over":
			_over_by = String(e.get("by", ""))
			crowd.roar(150)
		"round_start":
			# A Duel's next round: everyone is back at the start, so drop old effects.
			fx.clear()
			_ko_cam_t = -1
		"ko":
			shake = maxf(shake, 5.0)
			crowd.cheer(1.0)
			_flash(Color.WHITE, 0.6)
			var finish := team_battle == null or team_battle.phase == TeamSim.Phase.OVER
			if finish and (not MODES[mode].get("training", false) or flow == Flow.MENU):
				_ko_cam_t = 0
				# Frame the loser in the lower third, clear of the K.O. banner.
				_ko_focus = Vector2(e["pos"]) + Vector2(0, -64)
				_ko_pos = Vector2(e["pos"])
				crowd.roar(150)


func _flash(col: Color, amount: float) -> void:
	flash_rect.color = Color(col, maxf(flash_rect.color.a, amount))


## Pushes in on a knocked-out fighter, holds through the slow motion, then eases back.
## Showcases also follow the two fighters up close, so every tell is easy to see.
## Whether `c` stands in front of another fighter and covers it (a tall fighter facing
## up at a short one): then it's drawn see-through so the one behind stays readable.
func _hides_someone(c: CreatureSim) -> bool:
	if c.state == CreatureSim.State.KO:
		return false
	var top := c.pos.y - float(c.def.get("fx_top", 32)) - 6.0  # head and mane included
	for k in sim.creatures.size():
		var o := sim.creatures[k]
		if o == c or o.state in [CreatureSim.State.KO, CreatureSim.State.FALLING] or _is_hidden(k):
			continue  # (nobody turns see-through for a foe the local team can't see)
		if o.pos.y >= c.pos.y or absf(c.pos.x - o.pos.x) > c.radius + 6.0:
			continue
		# How much of the one behind is inside our height on screen.
		var o_feet := o.pos.y - o.air_height()
		var o_top := o_feet - float(o.def.get("fx_top", 32))
		var covered := minf(o_feet, c.pos.y) - maxf(o_top, top)
		if covered > (o_feet - o_top) * 0.5:
			return true
	return false


func _update_camera() -> void:
	var size := sim.arena_size() if sim != null else SimDefs.arena_size()  # the whole stadium
	var view := get_viewport().get_visible_rect().size  # the screen (wider on ultrawide)
	var base_z := 1.0
	var base_focus := size * 0.5
	var ko_focus := _ko_focus
	if sim != null and showcase == null and coach == null:
		_frame_fight(view, size)
		base_z = _cam_zoom
		base_focus = _cam_follow + _cam_lead
	elif (showcase != null or coach != null) and sim != null and sim.creatures.size() >= 2:
		var a := sim.creatures[0].pos
		var b := sim.creatures[1].pos
		# Fighters stacked up and down the screen: aim a little higher and zoom out to
		# keep both (and their heads) in shot.
		var dy := absf(a.y - b.y)
		var mid := (a + b) * 0.5 + Vector2(0, -8 - minf(dy, 40.0) * 0.3)
		_cam_follow = mid if _cam_follow == Vector2.ZERO else _cam_follow.lerp(mid, 0.12)
		var fit := lerpf(SHOWCASE_ZOOM, 1.3, clampf(dy / 40.0, 0.0, 1.0))
		_cam_zoom = fit if _cam_zoom <= 0.0 else lerpf(_cam_zoom, fit, 0.08)
		base_z = _cam_zoom
		base_focus = _cam_follow
		ko_focus = _ko_pos + Vector2(0, -16)  # no K.O. banner in a showcase
	var z := base_z
	var focus := base_focus
	if _ko_cam_t >= 0:
		_ko_cam_t += 1
		var amt := ko_push(_ko_cam_t)
		var k_out := clampf(float(_ko_cam_t - KO_HOLD_UNTIL) / KO_PUSH_OUT, 0.0, 1.0)
		z = lerpf(base_z, maxf(base_z, KO_ZOOM), amt)
		focus = base_focus.lerp(ko_focus, amt)
		if k_out >= 1.0:
			_ko_cam_t = -1
	var half := view * 0.5 / z
	camera.zoom = Vector2(z, z)
	# Near an edge the shot may run a little past it, into the side stands and front rows.
	camera.position = Vector2(_cam_axis(focus.x, half.x, size.x, CrowdView.SHOW_SIDE, CrowdView.SHOW_SIDE),
		_cam_axis(focus.y, half.y, size.y, 0.0, CrowdView.SHOW_FRONT))
	_update_pointers(view)


## How far into the KO push-in the camera is, 0..1, `t` ticks after the knockout: held
## still for the freeze's first beat, then eased in and out (smoothstep) so the push
## reads as a deliberate move rather than a snap; held, then eased back out.
static func ko_push(t: int) -> float:
	var k_in := clampf(float(t - KO_PUSH_DELAY) / KO_PUSH_IN, 0.0, 1.0)
	var k_out := clampf(float(t - KO_HOLD_UNTIL) / KO_PUSH_OUT, 0.0, 1.0)
	return smoothstep(0.0, 1.0, k_in) * (1.0 - smoothstep(0.0, 1.0, k_out))


## The letterbox: in for a knockout's push-in (until it starts easing back) and a Surge's
## freeze, out otherwise. Not over the title's background match.
func _update_letterbox() -> void:
	if _surge_bars > 0:
		_surge_bars -= 1
	var ko := _ko_cam_t >= 0 and _ko_cam_t < KO_HOLD_UNTIL
	letterbox.shown = flow != Flow.MENU and (ko or _surge_bars > 0)
	letterbox.advance()


## Big maps: arrows at the screen's edge toward objectives out of shot (the caravan, the
## flags). Screen = (world - camera) x zoom + half the screen.
func _update_pointers(view: Vector2) -> void:
	var out: Array = []
	if team_battle != null and sim != null and showcase == null:
		var targets: Array = []
		if team_battle.caravan:
			targets.append([team_battle.caravan_pos(), Hud.SIDE_COLORS[team_battle.cv_attacker()], "CARAVAN"])
		if team_battle.ctf:
			for side in 2:
				var word: String = ["FLAG", "TAKEN", "DROPPED", "LOOSE"][clampi(int(team_battle.flag_state[side]), 0, 3)]
				targets.append([team_battle.flag_pos[side], Hud.SIDE_COLORS[side], word])
		var z := camera.zoom.x
		var inner := Rect2(Vector2(24, 52), view - Vector2(48, 76))
		for t in targets:
			var s: Vector2 = (Vector2(t[0]) - camera.position) * z + view * 0.5
			if Rect2(Vector2.ZERO, view).grow(-8.0).has_point(s):
				continue
			var mid := view * 0.5
			var d := (s - mid).normalized()
			# where the line from the middle toward it leaves the inner box
			var k := INF
			if absf(d.x) > 0.001:
				k = minf(k, ((inner.end.x if d.x > 0.0 else inner.position.x) - mid.x) / d.x)
			if absf(d.y) > 0.001:
				k = minf(k, ((inner.end.y if d.y > 0.0 else inner.position.y) - mid.y) / d.y)
			out.append({"pos": mid + d * k, "dir": d, "color": t[1], "label": t[2]})
	hud.pointers = out


## A fight: keeps every fighter in shot, heads included, with room around them. Close
## together the camera sits at the normal 1x; as they spread out it pulls back, as far as
## showing the whole stadium. A foe hidden from the local team (brush, a wall) is left
## out, or the zoom would give it away. On top of that fit: the look-ahead (`_cam_lead`,
## toward where the action is going) and the exchange push-in (`_cam_push`).
func _frame_fight(view: Vector2, size: Vector2) -> void:
	var box := Rect2()
	var any := false
	var big := size.x > SimDefs.ARENA_W * 1.15 or size.y > SimDefs.ARENA_H * 1.15
	var anchor := _cam_anchor() if big else -1
	var n := sim.creatures.size()
	if _cam_prev.size() != n:
		_cam_prev.resize(n)
		for i in n:
			_cam_prev[i] = sim.creatures[i].pos
	var lead := Vector2.ZERO
	for i in n:
		var c := sim.creatures[i]
		var moved := c.pos - _cam_prev[i]
		_cam_prev[i] = c.pos
		if i != anchor and c.state == CreatureSim.State.KO and _ko_cam_t < 0:
			continue
		if _is_hidden(i):
			continue
		if anchor >= 0 and i != anchor and c.pos.distance_to(sim.creatures[anchor].pos) > FOLLOW_R:
			continue
		var body := Rect2(c.pos - Vector2(0, float(c.def.get("fx_top", 32)) + c.air_height()), Vector2.ZERO)
		body = body.expand(c.pos)
		box = body if not any else box.merge(body)
		any = true
		if anchor < 0 or i == anchor:  # a big map leads with the player it follows
			lead += _lead_of(c, moved)
	if not any:
		return
	var tight := box  # the fighters alone, heads to feet
	box = box.grow_individual(CAM_PAD.x, CAM_PAD.y + 24.0, CAM_PAD.x, CAM_PAD.y)  # the HUD sits up top
	var whole := minf(view.x / size.x, view.y / size.y)  # zoom that shows the whole stadium
	var least := minf(whole, 1.0)
	if anchor >= 0:
		least = FOLLOW_ZOOM
	elif big:
		least = maxf(least, BIG_MAP_MIN_ZOOM)
	var fit := clampf(minf(view.x / box.size.x, view.y / box.size.y), least, 1.0)
	# An exchange up close: push in a little, never past the tighter EXCHANGE_PAD room.
	if _exchange_t > 0:
		_exchange_t -= 1
		if _exchange_t == 0:
			_exchange_hits = 0
	var close := tight.size.x <= EXCHANGE_SPAN.x and tight.size.y <= EXCHANGE_SPAN.y
	var want := 1.0 if close and _exchange_hits >= EXCHANGE_HITS else 0.0
	_cam_push = lerpf(_cam_push, want, EXCHANGE_IN if want > _cam_push else EXCHANGE_OUT)
	if _cam_push < 0.002:
		_cam_push = 0.0
	if _cam_push > 0.0:
		var room := tight.grow_individual(EXCHANGE_PAD.x, EXCHANGE_PAD.y + 24.0, EXCHANGE_PAD.x, EXCHANGE_PAD.y)
		var cap := minf(view.x / room.size.x, view.y / room.size.y)
		fit = clampf(fit * (1.0 + EXCHANGE_PUSH * _cam_push), fit, maxf(fit, cap))
	var mid := box.get_center()
	if _cam_zoom <= 0.0:
		_cam_zoom = fit
		_cam_follow = mid
		_cam_lead = Vector2.ZERO
	else:
		# Pull back quickly (nobody leaves the shot), push in gently.
		_cam_zoom = lerpf(_cam_zoom, fit, 0.12 if fit < _cam_zoom else 0.03)
		_cam_follow = _cam_follow.lerp(mid, 0.1)
		_cam_lead = _cam_lead.lerp(lead.limit_length(LEAD_MAX), LEAD_EASE)
	_cam_lead = _lead_room(_cam_lead, _cam_follow, tight, view * 0.5 / _cam_zoom)


## A hit or block landed in shot: the exchange goes on (see EXCHANGE_HITS).
func _note_exchange() -> void:
	_exchange_t = EXCHANGE_HOLD
	_exchange_hits += 1


## What one fighter adds to the look-ahead: along its facing while it attacks, along its
## motion while it moves fast (a dash, a launch, knockback; `moved` is its step this tick).
func _lead_of(c: CreatureSim, moved: Vector2) -> Vector2:
	if c.state == CreatureSim.State.KO or c.state == CreatureSim.State.FALLING:
		return Vector2.ZERO
	var l := Vector2.ZERO
	if c.state == CreatureSim.State.ATTACK and c.facing != Vector2.ZERO:
		l += c.facing.normalized() * LEAD_ATTACK
	var sp := moved.length()
	if sp >= LEAD_MIN_SPEED and sp < 40.0:  # (a jump of more is a warp or a respawn)
		l += moved / sp * minf(sp * LEAD_PER_SPEED, LEAD_MAX)
	return l


## The look-ahead cut back so the shot (`half` its size, centred on `follow` + the lead)
## still holds `tight`, the fighters, with LEAD_KEEP to spare. It only ever shrinks the
## lead toward nothing, never adds any.
static func _lead_room(lead: Vector2, follow: Vector2, tight: Rect2, half: Vector2) -> Vector2:
	var c0 := tight.get_center()
	var spare := (half - tight.size * 0.5 - LEAD_KEEP).max(Vector2.ZERO)
	var lo := c0 - spare - follow
	var hi := c0 + spare - follow - Vector2(0, 24)  # heads stay clear of the HUD up top
	return Vector2(clampf(lead.x, minf(lo.x, 0.0), maxf(hi.x, 0.0)),
		clampf(lead.y, minf(lo.y, 0.0), maxf(hi.y, 0.0)))


## Whose fighter a big map's camera follows: the one player here (online, the local
## slot). -1 with nobody here playing, or players here on both sides.
func _cam_anchor() -> int:
	if online != null:
		return online.local_slot
	var found := -1
	for k in mini(sides.size(), sim.creatures.size()):
		if sides[k] in LOCAL_SIDES:
			if found >= 0:
				return -1
			found = k
	return found


## Keeps the arena filling the screen along one axis, the view allowed `lo` / `hi` past its
## start and end (into the stands); when the screen shows more than that (an ultrawide's
## width), the view stays centred on it and the stadium fills the rest.
static func _cam_axis(v: float, half: float, arena: float, lo := 0.0, hi := 0.0) -> float:
	if half * 2.0 >= arena + lo + hi:
		return (arena + hi - lo) * 0.5
	return clampf(v, half - lo, arena + hi - half)


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		_join_cpus()  # a press may change the match (a reset, a swap) while the CPUs read it
	var before := player_input.label_set()
	player_input.note_event(event)
	if player_input.label_set() != before:
		_apply_device()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute_music"):  # (typing in a text box never gets here)
		var muted := audio.toggle_music()
		_toast("Music off (M to turn on)" if muted else "Music on")
		_save_settings()
		if _setting_rows.has("vol_Music"):
			var now := _setting("vol_Music")
			(_setting_rows["vol_Music"] as OptionRow).set_values(now["values"], int(now["index"]))
		return
	if flow == Flow.MATCH_OVER and event.is_action_pressed("save_replay") and not _replaying() and sim != null:
		_save_replay()  # the fight just finished (the match-over menu has the other keys)
		return
	if ui.is_open():
		return  # the screen on top has the input
	if flow == Flow.MENU or flow == Flow.SELECT or flow == Flow.LOBBY or flow == Flow.MATCH_OVER:
		return  # their screens take the input
	if event.is_action_pressed("pause") and showcase != null:
		_back_to_row()  # a demo: straight back to the row it came from
	elif event.is_action_pressed("pause"):
		_open_pause()
	elif event.is_action_pressed("debug_hitboxes"):
		debug.visible = not debug.visible
		debug.queue_redraw()
	elif event.is_action_pressed("debug_perf"):
		_set_setting("perf_overlay", (perf_overlay.mode + 1) % PerfOverlay.MODE_NAMES.size())
		_toast("Performance overlay: " + PerfOverlay.MODE_NAMES[perf_overlay.mode])
	elif _range_rings_pressed(event):
		_set_setting("range_rings", 0 if range_rings else 1)
		_toast("Range rings " + ("on" if range_rings else "off"))
	elif event.is_action_pressed("debug_dummy_mode") and coach is ComboTrials:
		coach.replay_demo()
	elif event.is_action_pressed("reset") and coach is ComboTrials:
		coach.skip(1)
	elif _change_fighter_pressed(event) and in_training():
		_open_fighter_swap()
	elif event.is_action_pressed("debug_dummy_mode"):
		_set_setting("dummy_mode", (dummy_mode + 1) % DUMMY_MODES.size())
		hud.show_toast("Dummy: " + DUMMY_MODES[dummy_mode])
	elif event.is_action_pressed("debug_help"):
		hud.show_help = not hud.show_help
	elif event.is_action_pressed("palette") and sim != null and flow == Flow.FIGHT:
		var me := sides.find(Side.PLAYER)
		if me >= 0 and me < views.size():
			var id := String(sim.creatures[me].def.get("id", ""))
			var n := Progress.palettes_unlocked(id)
			var i := Progress.next_palette(id)
			(views[me] as CreatureView).palette = i
			hud.show_toast("Palette %d of %d" % [i + 1, n] + ("" if n > 1 else "   ·   clear the Arcade to unlock more"))
	elif event.is_action_pressed("save_replay"):
		_save_replay()
	elif event.is_action_pressed("reset") and MODES[mode].get("training", false):
		_start_round()
		hud.show_toast("Reset")


## F6: save the fight so far (or just finished) to the Replay theater.
func _save_replay() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://replays/replay_%s.json" % stamp
	if online != null:
		# Online: the confirmed inputs (what both machines agreed on), with the setup.
		replay = Replay.new()
		replay.setup = online.setup_dict()
		for row in online.confirmed_rows():
			replay.record(row)
	elif watch != null:
		replay = Replay.new()
		replay.setup = watch.setup_dict()
		for row in watch.log:
			replay.record(row)
	if replay.save(path) == OK:
		hud.show_toast("Replay saved: %d ticks" % replay.frames.size())
		print("Replay saved to ", ProjectSettings.globalize_path(path))
	else:
		hud.show_toast("Could not save replay")


## Back in a menu: Esc, B or View.
static func _back_pressed(event: InputEvent) -> bool:
	return event.is_action_pressed("menu_back") or event.is_action_pressed("ui_cancel")


## Start / Esc / View in a fight. Offline the match freezes behind the pause menu; online
## it can't, so it asks whether to leave while the match carries on (your fighter stands
## still meanwhile).
func _open_pause() -> void:
	if online != null or watch != null:  # a spectated room keeps going too
		var c := ConfirmScreen.new("Leave the match?" if online != null else "Stop watching?",
			"The match keeps going while this is open.", "Leave", "Stay")
		c.answered.connect(func(yes: bool): if yes: _leave_online())
		ui.push(c)
		return
	paused = true
	if _replaying():  # a saved fight: nothing to restart, so Resume / Replay theater / Main menu
		var rp := PauseScreen.new(false, "")
		rp.quit_text = "Main menu"
		rp.extras = [["Replay theater", func():
			_close_ui()
			_open_menu("single")
			_open_replays(), "Pick another saved fight"]]
		rp.resumed.connect(func(): paused = false)
		rp.quit_requested.connect(func():
			_close_ui()
			_open_menu())
		ui.push(rp)
		return
	var p := PauseScreen.new(true, player_input.help_text().replace("   ", "\n").replace("  ", "\n") + _tools_help())
	if in_training():
		p.extras = [["Change fighter", _open_fighter_swap, "Swap your fighter here: the dummy, arena and options stay"],
			["Training options", _open_training_options, "No cooldowns, Surge always full, what the dummy does"]]
	if arcade is Gauntlet:  # Restart is a whole new run, from wave 1
		var waves := (arcade as Gauntlet).waves()
		p.restart_question = "Start a new run from wave 1?"
		p.restart_note = ("This run ends here at %d wave%s cleared; your best is kept." % [waves, "" if waves == 1 else "s"]) 			if waves > 0 else "The run so far is lost."
	p.resumed.connect(func(): paused = false)
	p.restart_requested.connect(func():
		_record_gauntlet_best()
		_close_ui()
		seed_base += 1
		_start_match(mode, true))
	p.quit_requested.connect(func():
		_record_gauntlet_best()
		_close_ui()
		_back_to_row())
	ui.push(p)


## A Gauntlet run left before it was lost (pause Restart or Quit) still counts its waves.
func _record_gauntlet_best() -> void:
	if arcade is Gauntlet and (arcade as Gauntlet).waves() > 0:
		Progress.record_gauntlet(arcade.fighter, (arcade as Gauntlet).waves())


func _close_ui() -> void:
	ui.clear()
	paused = false


# ------------------------------------------------------------------ training

## A training match played here (not a replay of one, not online).
func in_training() -> bool:
	return mode < MODES.size() and MODES[mode].get("training", false) and online == null and watch == null \
		and sim != null and sim.training


## The fighter training builds: the one picked with Change fighter, else the mode's.
func training_fighter() -> String:
	if _training_fighter != "":
		return _training_fighter
	return String(MODES[mode].get("left", "cairn")) if mode < MODES.size() else "cairn"


## Change fighter (pause menu, or the change-fighter key): the pick screen's tiles, one
## fighter for you. Back returns to where it was opened from.
func _open_fighter_swap() -> void:
	if not in_training():
		return
	paused = true
	var p := CharacterSelect.new()
	p.solo = true
	p.solo_heading = "TRAINING"
	p.solo_info = "Swaps your fighter in place. The dummy, the arena and your training options stay."
	p.done_text = "SWAP!"
	p.setup("CHANGE FIGHTER", 1, ["YOU", "NEXT"], false, [[String(sim.creatures[0].def.get("id", ""))], []])
	p.p1_keyboard = player_input.keyboard
	p.p1_pad = player_input.pad_device
	p.chosen.connect(func(teams: Array): change_training_fighter(String(teams[0][0])))
	p.cancelled.connect(func():
		if ui.top() == p:
			ui.pop()
		if not ui.is_open():
			paused = false)
	ui.push(p)


## Swaps the player's fighter in place: training is rebuilt with `id`, keeping the dummy
## mode, the arena and the training options, and a short fade covers the cut. Restart
## and F4 keep it until you leave training.
func change_training_fighter(id: String) -> void:
	_join_cpus()
	if not in_training() or not (id in MatchFactory.FIGHTERS):
		return
	_training_fighter = id
	_close_ui()
	_start_round()
	_swap_fade = 1.0
	fade_rect.color.a = 1.0
	hud.show_toast("Now playing " + String(MatchFactory.load_def(id).get("name", id)))


## Pause > Training options: the sim's training flags and the dummy's behaviour.
func _open_training_options() -> void:
	var scr := UiScreen.new()
	scr.crumbs = ["PAUSED"]
	scr.title = "TRAINING OPTIONS"
	scr.row_width = 220.0
	scr.detail = true
	scr.blurb = "No cooldowns, Surge always full, what the dummy does"
	scr.hints = ["move", "change", "back"]
	scr.builder = func(s: UiScreen):
		_add_setting_row(s, "no_cooldowns")
		_add_setting_row(s, "full_energy")
		_add_setting_row(s, "dummy_mode")
		s.add_space(4)
		s.add_button("Back", s.back)
	scr.backed.connect(func(): _setting_rows.clear())
	ui.push(scr)


## Puts the training options on the match being played (a replay being recorded notes
## the change at this frame, so it plays back the same).
func _apply_training_opts() -> void:
	_join_cpus()
	if not in_training():
		return
	if not sim.set_training_flags(training_opts):
		return
	if replay != null and replay.setup is Dictionary and String(replay.setup.get("kind", "")) == "training":
		var changes: Array = replay.setup.get("flag_changes", [])
		changes.append([replay.frames.size(), bool(training_opts["no_cooldowns"]), bool(training_opts["full_energy"])])
		replay.setup["flag_changes"] = changes


## The change-fighter key of the player's own controls (like `_range_rings_pressed`).
func _change_fighter_pressed(event: InputEvent) -> bool:
	var kb := "lol_change_fighter" if player_input.layout == "league" else "kb_change_fighter"
	return event.is_action_pressed(kb) or event.is_action_pressed("pad_change_fighter")


## A Settings row: its label, values (shown), current index, a description, and for a
## volume its bar.
func _setting(key: String) -> Dictionary:
	if key.begins_with("vol_"):
		var bus := key.trim_prefix("vol_")
		var v := audio.volume(bus)
		var vals: Array = ["Off"]
		for i in range(1, 11):
			vals.append("%d%%" % (i * 10))
		var idx := clampi(roundi(v / VOLUME_STEP), 0, 10)
		if bus == "Music" and audio.music_muted and idx > 0:
			vals[idx] = "muted (M)"
		return {"label": VOLUME_NAMES[bus], "values": vals, "index": idx, "bar": v, "wrap": false,
			"desc": "Left/Right sets it.  M mutes the music any time"}
	match key:
		"level":
			return {"label": "CPU level", "values": LEVEL_NAMES, "index": level, "desc": "How hard the CPU fights. Rage: absurdly good, and plays each fighter by its class"}
		"delay":
			return {"label": "Online input delay", "values": ["Auto", "1 frame", "2 frames", "3 frames"],
				"index": clampi(input_delay + 1, 0, 3),
				"desc": "Frames between a press and the move online. Auto picks from the ping; more means fewer rollbacks. For matches you host or join directly (the server sets its own)"}
		"layout":
			var names: Array = []
			for l in PlayerInput.LAYOUTS:
				names.append(PlayerInput.LAYOUT_NAMES[l])
			return {"label": "Keyboard", "values": names, "index": PlayerInput.LAYOUTS.find(player_input.layout),
				"desc": "League-style: mouse to move, QWER.  Classic: WASD and J K U I O"}
		"pad_layout":
			var pads: Array = []
			for l in PlayerInput.PAD_LAYOUTS:
				pads.append(PlayerInput.PAD_LAYOUT_NAMES[l])
			return {"label": "Controller", "values": pads,
				"index": maxi(0, PlayerInput.PAD_LAYOUTS.find(player_input.pad_layout)),
				"desc": "Twin-stick: the right stick aims 360 degrees and holds your facing while you walk"}
		"fullscreen":
			return {"label": "Fullscreen", "values": ["Off", "On"], "index": 1 if fullscreen else 0,
				"desc": "Fill the screen"}
		"wide":
			return {"label": "Wide screens", "values": ["16:9 with bars", "Fill"], "index": 1 if wide_fill else 0,
				"desc": "Ultrawide and 16:10: show more of the stadium, or keep a 16:9 picture"}
		"vsync":
			return {"label": "Vsync", "values": ["Off", "On"], "index": 1 if vsync else 0,
				"desc": "On: no tearing, and the screen's refresh rate caps the frame rate"}
		"range_rings":
			return {"label": "Range rings", "values": ["Off", "On"], "index": 1 if range_rings else 0,
				"desc": "Show each attack's real hit area on the floor"}
		"no_cooldowns":
			return {"label": "No cooldowns", "values": ["Off", "On"], "index": 1 if training_opts["no_cooldowns"] else 0,
				"desc": "Every move and the dodge are always ready, and your stamina stays full"}
		"full_energy":
			return {"label": "Surge always full", "values": ["Off", "On"], "index": 1 if training_opts["full_energy"] else 0,
				"desc": "Your Surge meter stays full: throw the Surge as often as you like"}
		"dummy_mode":
			return {"label": "Dummy", "values": DUMMY_MODES, "index": dummy_mode,
				"desc": "What the dummy does (F2 cycles it in a fight)"}
		"rumble":
			return {"label": "Controller rumble", "values": ["Off", "On"], "index": 1 if rumble else 0,
				"desc": "A buzz when you land a hit or get hit"}
		"discord":
			return {"label": "Discord status", "values": ["Off", "On"], "index": 1 if discord_status else 0,
				"desc": "Show what you're playing on your Discord profile (with the Discord app open)"}
		"shake":
			var names: Array = []
			var idx := 0
			for i in SHAKE_CHOICES.size():
				names.append(SHAKE_CHOICES[i][0])
				if is_equal_approx(float(SHAKE_CHOICES[i][1]), shake_scale):
					idx = i
			return {"label": "Screen shake", "values": names, "index": idx,
				"desc": "How much the camera shakes on big hits"}
		"fps":
			var vals: Array = []
			for f in FPS_CHOICES:
				vals.append("Unlimited" if int(f) == 0 else "%d fps" % int(f))
			return {"label": "Fight frame rate", "values": vals, "index": maxi(0, FPS_CHOICES.find(fight_fps)),
				"desc": "Menus always run at 60 fps; this sets fights (up to your screen's refresh rate)"}
		"font":
			return {"label": "Text font", "values": ["Pixel", "Smooth"], "index": 1 if UiTheme.smooth else 0,
				"desc": "The menus and the HUD: the pixel font, or the smooth font from before"}
		"perf_overlay":
			return {"label": "Performance overlay", "values": PerfOverlay.MODE_NAMES, "index": perf_overlay.mode,
				"desc": "The frame rate in a corner; with the graph, the last few seconds of frame times (F9 in a fight)"}
	return {"label": key, "values": [""], "index": 0, "desc": ""}


func _set_setting(key: String, i: int) -> void:
	if key.begins_with("vol_"):
		var bus := key.trim_prefix("vol_")
		var v := clampf(i * VOLUME_STEP, 0.0, 1.0)
		audio.set_volume(bus, v)
		if bus == "Music" and v > 0.0 and audio.music_muted:
			audio.set_music_muted(false)  # turning the music up unmutes it
		# Let the player hear the new level (the music is already playing).
		if bus == "Effects":
			audio.preview("hit_light", "Effects")
		elif bus != "Music":
			audio.preview("ui_select", "Menu")
	else:
		match key:
			"level":
				level = clampi(i, 0, LEVEL_NAMES.size() - 1)
			"delay":
				input_delay = clampi(i, 0, 3) - 1
			"layout":
				player_input.layout = PlayerInput.LAYOUTS[clampi(i, 0, PlayerInput.LAYOUTS.size() - 1)]
				_apply_device()
			"pad_layout":
				_set_pad_layout(PlayerInput.PAD_LAYOUTS[clampi(i, 0, PlayerInput.PAD_LAYOUTS.size() - 1)])
				_apply_device()
			"fullscreen":
				fullscreen = i == 1
				_apply_fullscreen()
			"wide":
				wide_fill = i == 1
				_apply_aspect()
			"vsync":
				vsync = i == 1
				_apply_vsync()
			"rumble":
				rumble = i == 1
				if rumble and player_input.device == PlayerInput.Device.GAMEPAD:
					Input.start_joy_vibration(player_input.pad_id, 0.4, 0.4, 0.2)  # feel it
			"shake":
				shake_scale = float(SHAKE_CHOICES[clampi(i, 0, SHAKE_CHOICES.size() - 1)][1])
			"range_rings":
				range_rings = i == 1
				_apply_range_rings()
			"no_cooldowns", "full_energy":
				training_opts[key] = i == 1
				_apply_training_opts()
			"dummy_mode":
				dummy_mode = clampi(i, 0, DUMMY_MODES.size() - 1)
				hud.dummy_mode_name = DUMMY_MODES[dummy_mode]
			"discord":
				discord_status = i == 1
				_apply_discord()
			"fps":
				fight_fps = int(FPS_CHOICES[clampi(i, 0, FPS_CHOICES.size() - 1)])
			"perf_overlay":
				perf_overlay.mode = clampi(i, 0, PerfOverlay.MODE_NAMES.size() - 1) as PerfOverlay.Mode
			"font":
				if UiTheme.smooth != (i == 1):
					UiTheme.smooth = i == 1
					ui.restyle()
					_reopen_settings_page.call_deferred("video", "font")
	_save_settings()


## A short message: over the screens when one is open, else in the HUD.
func _toast(msg: String) -> void:
	if ui.is_open():
		ui.toast(msg)
	else:
		hud.show_toast(msg)


## Menus draw at MENU_FPS, fights at the player's setting; only menus read the stick
## as menu presses.
func in_menus() -> bool:
	return flow == Flow.MENU or flow == Flow.SELECT or flow == Flow.LOBBY


func _apply_frame_rate() -> void:
	var menus := in_menus()
	# The character select reads each player's stick itself (two cursors).
	menu_stick.enabled = (menus or ui.is_open()) and not (ui.top() is CharacterSelect)
	if _fps_caps:
		var cap := MENU_FPS if menus else fight_fps
		if Engine.max_fps != cap:
			Engine.max_fps = cap


## The pixel grid. project.godot draws on a 960 x 540 base (`viewport_width/height`) with a
## content scale of 2 (`window/stretch/scale`): one canvas unit is two grid pixels, so the
## world, the camera (zoom 1 shows a 480 x 270 view, as before) and every layout keep their
## numbers, while the pixel font (UiTheme) is drawn on the finer grid. The window's scale is
## snapped down to a whole number of screen pixels per canvas unit (3 at 1440 x 810, 4 at
## 1920 x 1080, 5 at 2560 x 1440): a fighter's pixels and 2x text are always whole screen
## pixels and never wobble between sizes. The edge left over shows a little more of the
## stadium (aspect expand), never a black bar. Text one grid pixel per glyph pixel is exact
## only when the window is a whole multiple of 960 x 540 (1920 x 1080, 3840 x 2160).
func _apply_pixel_scale() -> void:
	if DisplayServer.get_name() == "headless":
		return  # no screen (tests, servers): the project's scale 2 keeps the canvas in 480 x 270 units
	var win := get_window()
	var factor := pixel_scale_factor(Vector2(win.size), Vector2(win.content_scale_size))
	if factor > 0.0 and not is_equal_approx(win.content_scale_factor, factor):
		win.content_scale_factor = factor


## The content scale factor for a window `size` over the `base` grid: whole screen pixels
## per canvas unit (base.x / VIEW_W grid pixels: 2), at least 1. 0 for a size or base of nothing.
static func pixel_scale_factor(size: Vector2, base: Vector2) -> float:
	if base.x <= 0.0 or base.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return 0.0
	var grid := minf(size.x / base.x, size.y / base.y)  # screen px per grid px, unsnapped
	var unit_px := maxf(1.0, floorf(grid * base.x / SimDefs.VIEW_W + 0.001))  # per canvas unit
	return unit_px / grid


## A windowed start opens at 1920 x 1080 (project.godot), where every text size is whole
## screen pixels. On a screen too small for that window, it opens at the biggest whole
## multiple of 480 x 270 that fits instead (1440 x 810 on a 1080p screen). A window that
## fits (any size given with `--resolution`) and fullscreen are left alone.
func _fit_window() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("mobile"):
		return
	var win := get_window()
	if win.mode != Window.MODE_WINDOWED:
		return
	var room := Vector2(DisplayServer.screen_get_usable_rect(win.current_screen).size) - Vector2(16, 48)  # frame, title bar
	if win.size.x <= room.x and win.size.y <= room.y:
		return
	var units := floori(minf(room.x / SimDefs.VIEW_W, room.y / SimDefs.VIEW_H))
	win.size = Vector2i(maxi(units, 2) * SimDefs.VIEW_W, maxi(units, 2) * SimDefs.VIEW_H)
	win.move_to_center()


func _apply_aspect() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if wide_fill \
		else Window.CONTENT_SCALE_ASPECT_KEEP


func _apply_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


## Both players' controllers use the same layout.
## Connects to the Discord app (Rich Presence) or drops the connection, which clears the
## status. Never in headless runs (tests, servers) or without a client id.
func _apply_discord() -> void:
	var want := discord_status and DisplayServer.get_name() != "headless"
	if want and discord == null:
		var conf := Presence.load_config()
		if String(conf.get("client_id", "")) == "":
			return
		discord = DiscordRpc.new(String(conf["client_id"]))
		presence = Presence.new(conf)
		discord.set_activity(presence.activity(self))
	elif not want and discord != null:
		discord.close()
		discord = null


## Shows or hides the range rings to match the setting (fresh rings when they come on).
func _apply_range_rings() -> void:
	if rings == null:
		return
	rings.visible = range_rings
	if range_rings and sim != null:
		rings.set_sim(sim)
		rings.advance()


## The range rings key of the player's own controls: the keyboard layout in use, or the
## controller (no button until one is picked in Remap controller).
func _range_rings_pressed(event: InputEvent) -> bool:
	var kb := "lol_range_rings" if player_input.layout == "league" else "kb_range_rings"
	return event.is_action_pressed(kb) or event.is_action_pressed("pad_range_rings")


## The pause menu's Controls page: the fight tools after the moves.
func _tools_help() -> String:
	var out := ""
	var key := player_input.label("range_rings")
	if key != "" and key != "-":
		out += "\n%s range rings" % key
	var swap := player_input.label("change_fighter")
	if in_training() and swap != "" and swap != "-":
		out += "\n%s change fighter" % swap
	if player_input.device != PlayerInput.Device.GAMEPAD:
		out += "\nF9 performance overlay"
	return out


## A Duel, team battle or Brawl decided (its own phase says so; main's flow stays FIGHT).
func _sim_decided() -> bool:
	if duel != null:
		return duel.phase == DuelSim.Phase.OVER or duel.phase == DuelSim.Phase.ROUND_OVER
	if team_battle != null:
		return team_battle.phase == TeamSim.Phase.OVER
	if brawl != null:
		return brawl.phase == BrawlSim.Phase.OVER
	return false


## The victory pose: still on its feet with every foe knocked out (a time-out has none).
func _won_standing(c: CreatureSim) -> bool:
	if c.state == CreatureSim.State.KO or c.is_dummy:
		return false
	var foes := 0
	for o in sim.creatures:
		if c.is_foe(o) and not o.is_dummy:
			foes += 1
			if o.state != CreatureSim.State.KO:
				return false
	return foes > 0


func _set_pad_layout(lay: String) -> void:
	player_input.pad_layout = lay
	player2_input.pad_layout = lay


## Updates prompts, help text and the mouse cursor for the current device and layout.
func _apply_device() -> void:
	hud.resize_slots(sides.size())
	for i in sides.size():
		var pin: PlayerInput = null
		if sides[i] in LOCAL_SIDES:
			pin = _local_input(sides[i])
		if pin != null:
			hud.key_labels[i] = [pin.label("heavy"), pin.label("skill_1"), pin.label("skill_2")]
			hud.surge_labels[i] = pin.label("surge")
			hud.tag_labels[i] = pin.label("tag")
		else:
			hud.key_labels[i] = ["", "", ""]
			hud.surge_labels[i] = ""
			hud.tag_labels[i] = ""
	var ctf := team_battle != null and team_battle.ctf
	hud.help_text = player_input.help_text(team_battle == null or ctf)
	if ctf:  # Capture the Flag: Tag passes the flag
		var tk := player_input.label("tag")
		hud.help_text = hud.help_text.replace("%s tag" % tk, "%s pass" % tk)
	var pad := player_input.device == PlayerInput.Device.GAMEPAD
	hud.gamepad = pad
	ui.set_gamepad(pad)
	if player_input.device == PlayerInput.Device.GAMEPAD:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.set_default_cursor_shape(
			Input.CURSOR_CROSS if player_input.layout == "league" and flow != Flow.MENU else Input.CURSOR_ARROW)


## Controller rumble: a light buzz when you land a hit, a heavier one when you get hit.
func _rumble(e: Dictionary) -> void:
	if not rumble or player_input.device != PlayerInput.Device.GAMEPAD or flow != Flow.FIGHT:
		return
	var me := sides.find(Side.PLAYER)
	if me < 0:
		return
	match String(e["type"]):
		"hit":
			if int(e["target"]) == me:
				Input.start_joy_vibration(player_input.pad_id, 0.4, 0.6, 0.18)
			elif int(e["attacker"]) == me:
				Input.start_joy_vibration(player_input.pad_id, 0.3, 0.0 if float(e["power"]) < 9.0 else 0.4, 0.08)
		"surge":
			if int(e.get("who", -1)) == me:
				Input.start_joy_vibration(player_input.pad_id, 0.5, 0.5, 0.4)
		"slam":
			Input.start_joy_vibration(player_input.pad_id, 0.2, 0.5 if float(e["power"]) >= 1.0 else 0.2, 0.15)
		"ko":
			Input.start_joy_vibration(player_input.pad_id, 0.8, 0.8, 0.5)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		var lay := String(cfg.get_value("input", "layout", "league"))
		if lay in PlayerInput.LAYOUTS:
			player_input.layout = lay
		var pad := String(cfg.get_value("input", "pad_layout", "standard"))
		if pad in PlayerInput.PAD_LAYOUTS:
			_set_pad_layout(pad)
		level = clampi(int(cfg.get_value("game", "level", level)), 0, LEVEL_NAMES.size() - 1)
		input_delay = clampi(int(cfg.get_value("online", "delay", -1)), -1, 3)
		Netplay.player_id = String(cfg.get_value("online", "id", ""))
		Netplay.player_name = String(cfg.get_value("online", "name", "Player")).strip_edges().left(16)
		if Netplay.player_name == "":
			Netplay.player_name = "Player"
		var ar := String(cfg.get_value("game", "arena", MatchFactory.arena))
		if ar in ArenaMap.IDS:
			_arena_saved = ar
			if MatchFactory.arena == ArenaMap.DEFAULT:  # no --arena flag
				MatchFactory.arena = ar
		audio.set_music_muted(bool(cfg.get_value("audio", "music_muted", false)))
		_online_fighter = String(cfg.get_value("online", "fighter", _online_fighter))
		if not (_online_fighter in MatchFactory.FIGHTERS):
			_online_fighter = "cairn"
		_online_address = String(cfg.get_value("online", "address", ""))
		_online_server = String(cfg.get_value("online", "server", "")).strip_edges()
		_recent_servers = Array(cfg.get_value("online", "recent", []))
		for bus in AudioView.DEFAULT_VOLUMES:
			audio.set_volume(bus, float(cfg.get_value("audio", "volume_" + String(bus).to_lower(),
				AudioView.DEFAULT_VOLUMES[bus])))
		fullscreen = bool(cfg.get_value("video", "fullscreen", false))
		if fullscreen:
			_apply_fullscreen()
		vsync = bool(cfg.get_value("video", "vsync", true))
		_apply_vsync()
		wide_fill = bool(cfg.get_value("video", "wide_fill", true))
		_apply_aspect()
		rumble = bool(cfg.get_value("game", "rumble", true))
		discord_status = bool(cfg.get_value("game", "discord", true))
		shake_scale = float(cfg.get_value("game", "shake", 1.0))
		range_rings = bool(cfg.get_value("game", "range_rings", false))
		for k in MatchSim.TRAINING_FLAGS:
			training_opts[k] = bool(cfg.get_value("training", k, false))
		dummy_mode = clampi(int(cfg.get_value("training", "dummy_mode", 0)), 0, DUMMY_MODES.size() - 1)
		Controls.apply_overrides(cfg.get_value("controls", "bindings", {}))
		var fps := int(cfg.get_value("video", "fight_fps", default_fps()))
		fight_fps = fps if fps in FPS_CHOICES else default_fps()
		UiTheme.smooth = String(cfg.get_value("video", "font", "pixel")) == "smooth"
		perf_overlay.mode = clampi(int(cfg.get_value("video", "perf_overlay", 0)), 0,
			PerfOverlay.MODE_NAMES.size() - 1) as PerfOverlay.Mode
		var saved_rows = cfg.get_value("game", "row_choice", {})
		if saved_rows is Dictionary:
			for r in MENU_ROWS.size():
				var lbl := String(MENU_ROWS[r]["label"])
				if saved_rows.has(lbl) and MENU_ROWS[r].has("choices"):
					_row_choice[r] = clampi(int(saved_rows[lbl]), 0, (MENU_ROWS[r]["choices"] as Array).size() - 1)
	# After everything is loaded: saving here first would write defaults over it.
	if Netplay.player_id.length() < 8:
		Netplay.player_id = Netplay.make_player_id()
		_save_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "layout", player_input.layout)
	cfg.set_value("input", "pad_layout", player_input.pad_layout)
	cfg.set_value("game", "level", level)
	cfg.set_value("game", "arena", _arena_saved)
	cfg.set_value("online", "delay", input_delay)
	cfg.set_value("online", "id", Netplay.player_id)
	cfg.set_value("online", "name", Netplay.player_name)
	cfg.set_value("audio", "music_muted", audio.music_muted)
	cfg.set_value("online", "fighter", _online_fighter)
	cfg.set_value("online", "address", _online_address)
	cfg.set_value("online", "server", _online_server)
	cfg.set_value("online", "recent", _recent_servers)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "fight_fps", fight_fps)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "wide_fill", wide_fill)
	cfg.set_value("video", "perf_overlay", perf_overlay.mode)
	cfg.set_value("video", "font", "smooth" if UiTheme.smooth else "pixel")
	cfg.set_value("game", "rumble", rumble)
	cfg.set_value("game", "shake", shake_scale)
	cfg.set_value("game", "range_rings", range_rings)
	for k in MatchSim.TRAINING_FLAGS:
		cfg.set_value("training", k, bool(training_opts.get(k, false)))
	cfg.set_value("training", "dummy_mode", dummy_mode)
	cfg.set_value("game", "discord", discord_status)
	var rows := {}
	for r in MENU_ROWS.size():
		if MENU_ROWS[r].has("choices") and r < _row_choice.size():
			rows[String(MENU_ROWS[r]["label"])] = int(_row_choice[r])
	cfg.set_value("game", "row_choice", rows)
	cfg.set_value("controls", "bindings", Controls.overrides())
	for bus in AudioView.DEFAULT_VOLUMES:
		cfg.set_value("audio", "volume_" + String(bus).to_lower(), audio.volume(bus))
	cfg.save(settings_path)


## --sim-check=SEED: print (and optionally write) the determinism fingerprint, then quit.
## --server[=PORT]: run as a dedicated server (see DedicatedServer) instead of the game.
func _run_server() -> bool:
	var server := DedicatedServer.new()
	if not server.configure(OS.get_cmdline_user_args()):
		return false
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	add_child(server)
	return true


func _run_sim_check() -> bool:
	var seed_ := -1
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sim-check="):
			seed_ = int(a.get_slice("=", 1))
		elif a.begins_with("--sim-check-out="):
			out = a.get_slice("=", 1)
	if seed_ < 0:
		return false
	var digest := SimCheck.run(seed_)
	print("SIMCHECK ", digest)
	if out != "":
		# Use an absolute path: an exported game resolves relative ones inside its package.
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(digest)
			f.close()
		else:
			printerr("Could not write ", out, " (use an absolute path)")
	get_tree().quit()
	return true


func _parse_args() -> int:
	var start := -1
	var pick := false
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = AutoPlay.new()
			start = 4
		elif a == "--hitboxes":
			debug.visible = true
		elif a == "--range-rings":
			range_rings = true
		elif a.begins_with("--mode="):
			start = clampi(int(a.get_slice("=", 1)), 0, MODES.size() - 1)
			_skip_select = true  # straight into the match with the default teams
		elif a == "--pick":
			pick = true
		elif a == "--cpu-vs-cpu":
			_cpu_vs_cpu = true
		elif a.begins_with("--view-team="):
			_view_team_arg = int(a.get_slice("=", 1))
		elif a.begins_with("--teams="):
			# --teams=cairn,culvert,cairn:culvert,cairn,culvert
			var halves := a.get_slice("=", 1).split(":")
			if halves.size() == 2:
				_teams = [Array(halves[0].split(",")), Array(halves[1].split(","))]
		elif a.begins_with("--level="):
			level = clampi(int(a.get_slice("=", 1)), 0, LEVEL_NAMES.size() - 1)
		elif a.begins_with("--seed="):
			seed_base = int(a.get_slice("=", 1))
		elif a == "--perf":
			_perf = PerfLog.new()
			PerfLog.current = _perf
			_perf.measure(get_viewport().get_viewport_rid())
		elif a.begins_with("--cpu-threads="):
			CpuController.threaded = a.get_slice("=", 1) != "off"
		elif a.begins_with("--arena="):
			var ar := a.get_slice("=", 1)
			if ar in ArenaMap.IDS:
				MatchFactory.arena = ar
		elif a.begins_with("--dummy-mode="):
			dummy_mode = clampi(int(a.get_slice("=", 1)), 0, DUMMY_MODES.size() - 1)
		elif a.begins_with("--training-flags="):
			var on := a.get_slice("=", 1).split(",")
			for k in MatchSim.TRAINING_FLAGS:
				training_opts[k] = k in on
		elif a.begins_with("--training-screen="):
			_training_screen_arg = a.get_slice("=", 1)
		elif a.begins_with("--shots="):
			for s in a.get_slice("=", 1).split(","):
				_shots[int(s)] = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.get_slice("=", 1)
		elif a.begins_with("--quit-after="):
			_quit_after = int(a.get_slice("=", 1))
		elif a.begins_with("--showcase="):
			var sc := a.get_slice("=", 1)
			if sc in Showcase.names():
				_showcase_arg = sc
			for i in MODES.size():
				if MODES[i].get("showcase", false):
					start = i
		elif a == "--online-host" or a.begins_with("--online-host="):
			_net_args["host"] = int(a.get_slice("=", 1)) if a.contains("=") else Netplay.DEFAULT_PORT
		elif a.begins_with("--online-join="):
			_net_args["join"] = a.get_slice("=", 1)
		elif a.begins_with("--online-watch="):
			_net_args["join"] = a.get_slice("=", 1)
			_net_args["watch"] = true
		elif a.begins_with("--menu="):
			var page := a.get_slice("=", 1)
			if page in ["main", "single", "settings", "game", "video", "audio", "controls"] or page.begins_with("single:") \
					or page in ["remap:classic", "remap:league", "remap:gamepad"]:
				_menu_arg = "" if page == "main" else page
		elif a.begins_with("--fighter="):
			var f := a.get_slice("=", 1)
			if f in MatchFactory.FIGHTERS:
				_online_fighter = f
				_arcade_fighter = f
		elif a.begins_with("--net-lag="):
			_net_args["lag"] = int(a.get_slice("=", 1))
		elif a.begins_with("--net-loss="):
			_net_args["loss"] = float(a.get_slice("=", 1))
		elif a.begins_with("--online-size="):
			_net_args["size"] = clampi(int(a.get_slice("=", 1)), 1, TeamSim.MOST_PER_SIDE)
		elif a.begins_with("--net-delay="):
			_net_args["delay"] = int(a.get_slice("=", 1))
		elif a.begins_with("--net-report="):
			_net_args["report"] = a.get_slice("=", 1)
		elif a == "--net-no-pick" or a.begins_with("--net-no-pick="):
			_net_no_pick = int(a.get_slice("=", 1)) if a.contains("=") else 1 << 30
		elif a.begins_with("--layout="):
			var lay := a.get_slice("=", 1)
			if lay in PlayerInput.LAYOUTS:
				player_input.layout = lay
		elif a.begins_with("--pad-layout="):
			var pl := a.get_slice("=", 1)
			if pl in PlayerInput.PAD_LAYOUTS:
				_set_pad_layout(pl)
	if pick:
		_skip_select = false
	return start


# ------------------------------------------------------------------ online

func _open_lobby() -> void:
	_end_online()
	_push_lobby()


## The online screen, over whatever plays behind it (the session, if any, is kept).
func _push_lobby() -> void:
	flow = Flow.LOBBY
	flow_t = 0
	hud.menu_visible = false
	hud.visible = false
	_close_ui()
	lobby = OnlineLobby.new(_online_fighter, _online_address, _recent_servers, online_server())
	lobby.server_join_pressed.connect(_net_join_server)
	lobby.board_pressed.connect(_net_daily_board)
	lobby.name_changed.connect(func(t: String):
		Netplay.player_name = t.strip_edges().left(16) if t.strip_edges() != "" else "Player"
		_save_settings())
	lobby.host_pressed.connect(_net_host)
	lobby.join_pressed.connect(_net_join_typed)
	lobby.cancelled.connect(_leave_online)
	lobby.search_cancelled.connect(_cancel_search)
	ui.push(lobby)


## Cancel while searching or hosting: stop, and stay on the online screen.
func _cancel_search() -> void:
	_close_ready_check()
	if _finder != null:
		_finder.cancel()
		_finder = null
	if netplay != null:
		netplay.leave()
		netplay = null
	if lobby != null:
		lobby.busy = false
		lobby.hosting_port = 0
		lobby.status_bad = false
		lobby.status = "Stopped searching"


## Builds the network link, with the --net-lag / --net-loss wrapper if asked for.
func _make_link(host_port: int, address := "", port := 0) -> NetLink:
	var e := EnetLink.new()
	var err := e.host(host_port) if address == "" else e.join(address, port)
	if err != OK:
		return e  # Netplay reports e.error
	if int(_net_args.get("lag", 0)) > 0 or float(_net_args.get("loss", 0.0)) > 0.0:
		return LagLink.new(e, int(_net_args.get("lag", 0)), float(_net_args.get("loss", 0.0)))
	return e


func _net_host(fighter: String) -> void:
	_online_fighter = fighter
	_save_settings()
	netplay = Netplay.new()
	netplay.forced_delay = int(_net_args.get("delay", input_delay))
	netplay.arena_id = MatchFactory.arena
	var port := int(_net_args.get("host", Netplay.DEFAULT_PORT))
	var link := _make_link(port)
	if link.status == NetLink.Status.CLOSED:
		lobby.status = link.error
		lobby.status_bad = true
		netplay = null
		return
	netplay.host(port, [fighter], link)
	lobby.busy = true
	lobby.hosting_port = port
	_lobby_status()


## Quick match (room "") or a room, on the online server; `size` players per side (0:
## the room's own). At the server's own house its public name may not work (many
## routers don't loop it back inside), so this first looks for it on the local network
## for a moment, then joins whichever it found.
func _net_join_server(fighter: String, room: String, size := 1, server := "") -> void:
	var parsed := OnlineLobby.parse_address(server if server != "" else online_server())
	if String(parsed[0]) == "":
		lobby.status = OnlineLobby.NO_SERVER
		lobby.status_bad = true
		return
	_online_fighter = fighter
	_pending_team = lobby.team.duplicate() if lobby != null and lobby.team.size() > 1 else [fighter]
	_pending_rules = lobby.rules_id if lobby != null else ""
	_pending_watch = lobby != null and lobby.watch_next
	_pending_ranked = lobby != null and lobby.ranked_next
	if lobby != null:
		lobby.watch_next = false
		lobby.ranked_next = false
	_save_settings()
	_finder = LanFinder.new()
	_finder.start(int(parsed[1]), finder_target)
	_finder_join = [fighter, String(parsed[0]), int(parsed[1]), room, size]
	lobby.busy = true
	lobby.hosting_port = 0
	lobby.status_bad = false
	lobby.status = "Looking for the server..."


## Each frame while looking: once it's done, join the server it found nearby, or the
## public address.
## The server's public name gets no answer, and it didn't answer on this network either.
## At the server's house that's usually the server's own setup; anywhere else, the
## server is down or its port isn't forwarded.
const HOME_HINT := "No answer. At the server's house: update it and allow UDP 7778. Away: is UDP 7777 forwarded?"


func _finder_step() -> void:
	if not _finder.poll():
		return
	var f := _finder.found
	var j := _finder_join
	_finder = null
	_home_missed = f.is_empty()
	if lobby == null:
		return
	if f.is_empty():
		_net_join(String(j[0]), String(j[1]), int(j[2]), String(j[3]), false, int(j[4]))
	else:
		_net_join(String(j[0]), String(f["address"]), int(f["port"]), String(j[3]), false, int(j[4]))


## The day's top ten from the server, shown in the lobby's status.
func _net_daily_board() -> void:
	if lobby == null:
		return
	var parsed := OnlineLobby.parse_address(online_server())
	if String(parsed[0]) == "":
		lobby.status = OnlineLobby.NO_SERVER
		lobby.status_bad = true
		return
	_daily_client = DailyClient.fetch_board(String(parsed[0]), int(parsed[1]), Daily.today())
	lobby.status = "Asking the server for today's scores..."
	lobby.status_bad = false


## After a Daily fight: the replay goes to the configured server to be scored there.
func _net_daily_submit(d: Daily) -> void:
	var parsed := OnlineLobby.parse_address(online_server())
	if String(parsed[0]) == "":
		return
	_daily_client = DailyClient.submit(String(parsed[0]), int(parsed[1]), d.date, d.fighter, replay.to_dict())
	_daily_sent_toast = "Daily score sent to the server..."
	hud.show_toast(_daily_sent_toast)


func _daily_step() -> void:
	_daily_client.tick()
	if not _daily_client.done:
		return
	var c := _daily_client
	_daily_client = null
	if c.rank > 0 or (c.ok and c.score > 0):
		_toast("Daily score %d: #%d today" % [c.score, c.rank] if c.ok else c.error)
	elif c.ok and lobby != null:
		var lines: Array = []
		for i in c.board.size():
			lines.append("%d. %s  %d" % [i + 1, String(c.board[i]["name"]), int(c.board[i]["score"])])
		lobby.status = "Today's Daily top 10:  " + ("   ".join(lines) if not lines.is_empty() else "nobody yet")
		lobby.status_bad = false
	elif not c.ok:
		_toast(c.error)


## Join by a typed (or recent) address. The online server's own name goes through the
## local look-up too, so it works at home.
func _net_join_typed(fighter: String, address: String, port: int, room := "") -> void:
	var srv := OnlineLobby.parse_address(online_server())
	if address.to_lower() == String(srv[0]).to_lower() and address != "":
		_online_address = lobby.address if lobby.address != "" else address
		_remember_server(_online_address)
		_net_join_server(fighter, room, 0 if room != "" else 1, "%s:%d" % [address, port])
		return
	_net_join(fighter, address, port, room, true, 0 if room != "" else 1)


func _net_join(fighter: String, address: String, port: int, room := "", remember := true, size := 1) -> void:
	_online_fighter = fighter
	if remember:
		_home_missed = false
		_online_address = lobby.address if lobby.address != "" else address
		_remember_server(_online_address)
	_save_settings()
	netplay = Netplay.new()
	netplay.forced_delay = int(_net_args.get("delay", input_delay))
	netplay.arena_id = MatchFactory.arena
	var link := _make_link(0, address, port)
	if link.status == NetLink.Status.CLOSED:
		lobby.busy = false
		lobby.status = link.error
		lobby.status_bad = true
		netplay = null
		return
	netplay.room = room
	netplay.team_size = size
	netplay.rules_id = TeamSim.rules_for_size(_pending_rules, size) if size > 1 else ""
	netplay.ranked = _pending_ranked and size == 1
	_pending_ranked = false
	netplay.auto_ready = _auto_accept or _cpu_vs_cpu
	var team: Array = _pending_team if not _pending_team.is_empty() and String(_pending_team[0]) == fighter else [fighter]
	_pending_team = []
	if _pending_watch:
		_pending_watch = false
		netplay.spectate(address, port, room, link)
	else:
		netplay.join(address, port, team, link)
	lobby.busy = true
	lobby.hosting_port = 0
	_lobby_status()


## Connecting: keeps the network moving behind the lobby. Returns true if the online
## match started just now; only its rollback session may step it, never the menu's loop
## (a step outside it would put this machine one frame off the other and the server).
func _connecting_step() -> bool:
	netplay.tick(0)
	_lobby_status()
	return online != null


## While connecting: show what's happening, and start the match once it's agreed.
func _lobby_status() -> void:
	if netplay == null:
		return
	lobby.status = netplay.status
	lobby.status_bad = netplay.phase == Netplay.Phase.ENDED and not netplay.declined
	if netplay.phase == Netplay.Phase.ENDED:
		_close_ready_check()
		if _home_missed and netplay.error.begins_with("No answer"):
			lobby.status = HOME_HINT
		lobby.busy = false
		netplay = null
		return
	if netplay.is_playing() or netplay.is_watching():
		_start_online_match()
		return
	_ready_check_step()


## The server's ready check: Match found opens over the online screen (with a sound and
## a nudge from the taskbar, in case the player looked away), shows the countdown, and
## closes again if the match falls through.
func _ready_check_step() -> void:
	if netplay.match_found and _ready_screen == null:
		var what := lobby.searching_for if lobby.searching_for != "" else "Online"
		_ready_screen = ReadyCheck.new(what, lobby.fighter)
		_ready_screen.set_total(netplay.found_secs)
		_ready_screen.accepted.connect(func():
			if netplay != null:
				netplay.accept_match())
		_ready_screen.declined.connect(func():
			if netplay != null:
				netplay.decline_match()
				_lobby_status())
		ui.push(_ready_screen)
		audio.play("round_start", 0.0, 1.0, true)
		if not DisplayServer.window_is_focused():
			DisplayServer.window_request_attention()
	elif not netplay.match_found and _ready_screen != null:
		_close_ready_check()
	if _ready_screen != null:
		_ready_screen.update(netplay.seconds_left(), netplay.accepted, netplay.accepted_have,
			netplay.found_players, netplay.found_need)


func _close_ready_check() -> void:
	if _ready_screen != null and is_instance_valid(_ready_screen) and ui.top() == _ready_screen:
		ui.pop()
	_ready_screen = null


## Watching a match on the server: the referee's copy is the match; every side is
## remote and nobody here presses anything.
func _start_watching() -> void:
	watch = netplay.watch
	online = null
	_close_ui()
	_ready_screen = null
	lobby = null
	hud.visible = true
	hud.menu_visible = false
	audio.play_music("fight")
	_end_duel()
	var s: Array = []
	s.resize(watch.players)
	s.fill(Side.REMOTE)
	if watch.duel is TeamSim:
		team_battle = watch.duel
		_rules_id = watch.rules
		_new_sim(team_battle.sim, s)
		hud.team = team_battle
		hud.focus = 0
		hud.timer_ticks = team_battle.timer
		_show_pads()
	else:
		duel = watch.duel
		_new_sim(duel.sim, s)
		hud.duel = duel
		hud.timer_ticks = duel.timer
	for i in sides.size():
		hud.tags[i] = "WATCHING"
	hud.wins = [0, 0]
	hud.wins_needed = 0
	hud.banner = ""
	flow = Flow.FIGHT
	flow_t = 0
	_net_end_t = 0


func _start_online_match() -> void:
	if netplay.watch != null:
		_start_watching()
		return
	online = netplay.game
	if lobby != null:
		_room_made = lobby.room_created
	_close_ui()  # the lobby (and Match found), a match-over screen on a rematch, or a room's select
	_ready_screen = null
	_room_screen = null
	_room_picker = null
	_rematch_page = false
	lobby = null
	hud.visible = true
	hud.menu_visible = false
	audio.play_music("fight")
	_end_duel()
	var s: Array = []
	s.resize(online.players)
	s.fill(Side.REMOTE)
	s[online.local_slot] = Side.PLAYER
	if online.team != null:
		# A team battle: every slot is a player somewhere; this one is ours.
		team_battle = online.team
		_rules_id = netplay.rules_id
		_new_sim(team_battle.sim, s)
		hud.team = team_battle
		hud.focus = online.local_slot
		hud.timer_ticks = team_battle.timer
		_show_pads()
		_cpu_shown = 0
		_show_cpu_slots()
	else:
		duel = online.duel
		_new_sim(duel.sim, s)
		for i in 2:
			if cpus[i] != null:
				(cpus[i] as CpuController).duel = duel
		hud.duel = duel
		hud.timer_ticks = duel.timer
	hud.wins = [0, 0]
	hud.wins_needed = 0
	hud.banner = ""
	flow = Flow.FIGHT
	flow_t = 0
	_net_end_t = 0


## During an online match: rematches, the connection's health, and how it ended.
func _online_status() -> void:
	if netplay.phase == Netplay.Phase.HANDSHAKE:
		_back_to_room_wait()  # the other player left the room: wait there for someone new
		return
	if netplay.game != online and netplay.is_playing():
		_write_net_report(true)
		_start_online_match()  # a rematch began, or the room's next match
		return
	# Ranked: after the result the other player going back to the online screen isn't a
	# disconnection; the result stays up until this player goes back too.
	var after_ranked := netplay.ranked and flow == Flow.MATCH_OVER and not _rematch_page
	if netplay.phase == Netplay.Phase.ENDED:
		_net_end_t += 1
		if _net_end_t == 1:
			_write_net_report()
			hud.net_info = ""
			if _rematch_page:
				_rematch_ended(netplay.error)
			elif not after_ranked:
				hud.banner = "DISCONNECTED"
				hud.banner_sub = netplay.error
		if after_ranked and _match_over_status != null and is_instance_valid(_match_over_status):
			_match_over_status.text = netplay.error
		elif _net_end_t > 240:
			if _rematch_page:
				_leave_to_lobby()
			else:
				_leave_online()
		return
	if netplay.rematch_pick() and not _rematch_page:
		_open_rematch_pick()  # both asked for a rematch: pick for it
	if netplay.in_room() or _rematch_page:
		_room_step()
	elif _cpu_vs_cpu and online.players == 2 and flow == Flow.MATCH_OVER and flow_t == MATCH_OVER_MENU_AT + 120 \
			and not netplay.rematch_local:
		netplay.request_rematch()  # demos and captures: on to the rematch (and its pick) by itself
	var g := online
	if g.cpu_slots.size() != _cpu_shown:
		_show_cpu_slots()
		hud.show_toast("A player left: a CPU plays for them")
	_rb_t += 1
	if _rb_t >= 60:
		_rb_rate = g.session.rollbacks - _rb_seen
		_rb_seen = g.session.rollbacks
		_rb_t = 0
	hud.net_info = "PING %d ms   DELAY %d   ROLLBACKS %d/s (MAX %d)   %s" % [roundi(netplay.ping_ms), g.input_delay,
		_rb_rate, g.session.max_rollback_seen, ArenaMap.name_of(g.arena_id).to_upper()]
	if g.desync_frame >= 0:
		hud.net_info = "DESYNC at frame %d: report saved   " % g.desync_frame + hud.net_info
	var waiting := "WAITING FOR PLAYERS" if g.players > 2 else "WAITING FOR OPPONENT"
	if g.waiting_ticks > 30 and flow == Flow.FIGHT:
		hud.banner = waiting
		hud.banner_sub = "Connection hiccup..."
	elif hud.banner == waiting:
		hud.banner = ""
		hud.banner_sub = ""
	if flow == Flow.MATCH_OVER and _match_over_status != null and is_instance_valid(_match_over_status):
		var others := g.players - 1 - g.cpu_slots.size()
		var asked := netplay.rematch_asked.size()
		if netplay.in_room():
			_match_over_status.text = _room_summary()
		elif g.players > 2 and (netplay.rematch_local or asked > 0):
			_match_over_status.text = "Rematch: %d of %d asked" % [asked + (1 if netplay.rematch_local else 0),
				others + 1]
		else:
			var lines := PackedStringArray()
			if not netplay.last_rating.is_empty():
				var lr := netplay.last_rating
				lines.append("Rating %d -> %d (%+d)   ·   %d games, %d won" % [roundi(float(lr["old"])),
					roundi(float(lr["new"])), roundi(float(lr["new"]) - float(lr["old"])), int(lr["games"]), int(lr["wins"])])
			if netplay.rematch_local:
				lines.append("Waiting for the other player...")
			elif netplay.rematch_remote:
				lines.append("The other player wants a rematch!")
			_match_over_status.text = "\n".join(lines)


## Online team battle: slots the server's CPU plays say so on their card and marker.
func _show_cpu_slots() -> void:
	_cpu_shown = online.cpu_slots.size()
	for slot in online.cpu_slots:
		if int(slot) < hud.tags.size():
			hud.tags[int(slot)] = "CPU"
		if int(slot) < fx.side_marks.size():
			fx.side_marks[int(slot)]["label"] = "CPU"


func _leave_online() -> void:
	_write_net_report()
	if netplay != null:
		netplay.leave()
	_end_online()
	_open_menu("", "online")


## Leave the match (or room) for the online screen, to search again from there.
func _leave_to_lobby() -> void:
	_write_net_report()
	if netplay != null:
		netplay.leave()
	_open_menu("", "online")
	_open_lobby()


# ------------------------------------------------------------------ online rooms
# A room on the server lasts between matches: after one, Next match opens the room's
# page with the fighter select over it; everyone locks in, and the server starts the
# next match (the session stays up throughout). See RelayServer's Room.

## The room's code as players read it.
func _room_code() -> String:
	return netplay.room.to_upper() if netplay != null else ""


## The other player left a 1v1 room: back to the online screen, still in the room and
## waiting there (the session is kept), with the code to hand out again.
func _back_to_room_wait() -> void:
	var n := netplay
	var fighters := n.my_team.duplicate()
	_write_net_report()
	netplay = null  # kept through the menu's reset below
	_open_menu("", "online")
	_push_lobby()
	netplay = n
	lobby.use_fighter(String(fighters[0]))
	lobby.team = fighters
	lobby.room_code = _room_code()
	lobby.room_created = _room_made
	lobby.room_tag = fighters.size()
	lobby.searching_for = "Room " + _room_code()
	lobby.busy = true
	_lobby_status()


## Next match: this player goes to the room's fighter select (the server hears they're
## picking); the finished match keeps stepping behind it until the next one starts.
func _room_next() -> void:
	if netplay == null or not netplay.in_room() or netplay.phase != Netplay.Phase.PLAYING:
		return
	netplay.request_next()
	_close_ui()  # the match-over screen
	_open_room_screen()
	_open_room_picker()


## Both players asked for a 1v1 rematch outside a room (Quick match, ranked, direct):
## the same page and fighter select a room uses between matches, with the last pick
## ready to lock in again (or Same again on the page). The finished match keeps
## stepping behind it until the rematch starts.
func _open_rematch_pick() -> void:
	_rematch_page = true
	_close_ui()  # the match-over screen
	_open_room_screen()
	_open_room_picker()


## Same again: the last pick, locked in at once.
func _rematch_same_again() -> void:
	if netplay != null and not netplay.pick_all_locked:
		netplay.send_pick(netplay.my_team.duplicate())


## The other player left during the rematch's pick: say so, then back to the online
## screen (by itself after a few seconds, as when someone leaves a Quick match).
func _rematch_ended(why: String) -> void:
	_close_ui()
	_room_screen = null
	_room_picker = null
	var scr := UiScreen.new()
	scr.title = "REMATCH"
	scr.subtitle = why if why != "" else "The rematch is off"
	scr.dim = 0.75
	scr.row_width = 200.0
	scr.builder = func(s: UiScreen):
		s.add_button("Back to online", _leave_to_lobby, "Search again from the online screen")
	scr.on_back = _leave_to_lobby
	ui.push(scr)


## The room's page between matches: its code (press to copy), who has locked in, and
## Pick your fighter / Leave room. The fighter select opens over it. A 1v1 rematch's
## pick uses it too (no code; Same again locks the last pick in at once).
func _open_room_screen() -> void:
	var scr := UiScreen.new()
	scr.title = "REMATCH" if _rematch_page else "ROOM " + _room_code()
	scr.subtitle = "Pick your fighter" + ("s" if netplay.my_team.size() > 1 else "") if _rematch_page else "Next match"
	scr.dim = 0.75
	scr.row_width = 200.0
	scr.builder = func(s: UiScreen):
		if _rematch_page:
			var same := s.add_button("Same again", _rematch_same_again, "Lock in the same fighter" + (
				"s" if netplay.my_team.size() > 1 else "") + " for the rematch")
			s.add_button("Pick your fighter", _open_room_picker, "Lock in a fighter (or the same one) for the rematch")
			s.add_button("Leave", _leave_to_lobby, "Back to the online screen; the rematch is off for both")
			_room_status_label = s.add_text(_room_summary(true), UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
			s.default_focus = same
			return
		s.add_row(RoomCodeButton.new(_room_code()), "Copy the code to send to a friend")
		var pick := s.add_button("Pick your fighter", _open_room_picker, "Lock in a fighter (or the same one) for the next match")
		s.add_button("Leave room", _leave_to_lobby, "Back to the online screen; the room carries on without you")
		_room_status_label = s.add_text(_room_summary(true), UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
		s.default_focus = pick
	scr.on_back = _leave_to_lobby
	_room_screen = scr
	ui.push(scr)


## The room's fighter select (just yours: `solo`), with who has locked in beside it.
func _open_room_picker() -> void:
	if netplay == null or (_room_picker != null and is_instance_valid(_room_picker)) or \
			(_rematch_page and netplay.pick_all_locked):
		return
	var p := CharacterSelect.new()
	p.solo = true
	p.solo_heading = "REMATCH" if _rematch_page else "ROOM " + _room_code()
	p.solo_info = _room_summary(true)
	p.done_text = "LOCKED IN"
	var team := netplay.my_team.duplicate()
	p.setup("REMATCH" if _rematch_page else "NEXT MATCH", team.size(), ["YOU", "OPPONENT" if _rematch_page else "ROOM"],
		false, [team, []])
	p.chosen.connect(func(teams: Array):
		_room_picker = null
		if ui.top() == p:
			ui.pop()
		var picked: Array = (teams[0] as Array).duplicate()
		_online_fighter = String(picked[0])
		_save_settings()
		if netplay != null:
			netplay.send_pick(picked))
	p.cancelled.connect(func():
		_room_picker = null
		if ui.top() == p:
			ui.pop())
	_room_picker = p
	ui.push(p)
	if _cpu_vs_cpu and _rematch_page and _net_no_pick > 0:
		_net_no_pick -= 1  # --net-no-pick: leave it to the countdown
	elif _cpu_vs_cpu:
		# Demos and captures: the CPU "picks" the next fighter along.
		var next: Array = []
		for f in team:
			next.append(MatchFactory.FIGHTERS[(MatchFactory.FIGHTERS.find(String(f)) + 1) % MatchFactory.FIGHTERS.size()])
		p.chosen.emit([next, []])


## Who's in the room and who has locked in (`lines`: one per player, for the select's
## panel and the room page); otherwise one line for the match-over screen.
func _room_summary(lines := false) -> String:
	if netplay == null:
		return ""
	if _rematch_page:
		return _rematch_summary(lines)
	var who: Array = netplay.room_players
	var locked := who.filter(func(p): return bool(p["locked"])).size()
	if lines:
		var out := PackedStringArray()
		for p in who:
			out.append("%s: %s" % [p["name"], "locked in" if p["locked"] else "picking..."])
		if netplay.room_watchers > 0:
			out.append("%d watching" % netplay.room_watchers)
		return "\n".join(out)
	match netplay.room_state:
		"select":
			return "Picking fighters for the next match: %d of %d locked in" % [locked, who.size()]
		"waiting":
			return "Waiting for a player: room code " + _room_code()
	return ""


## A 1v1 rematch's pick: this player's state and the opponent's ("Opponent is
## choosing..." or "Opponent locked in": their fighter stays hidden until the match
## starts), and the seconds left before the last picks are locked in.
func _rematch_summary(lines := false) -> String:
	var who: Array = netplay.room_players
	var me := netplay.local_slot
	if who.size() != 2 or me < 0 or me > 1:
		return "Waiting for your opponent..."
	var them := "Opponent locked in" if bool((who[1 - me] as Dictionary)["locked"]) else "Opponent is choosing..."
	var mine := "You: locked in" if bool((who[me] as Dictionary)["locked"]) else "You: picking..."
	if netplay.pick_all_locked:  # both in: the fighters show for the last seconds
		them = "Opponent: " + _fighter_name(String((who[1 - me] as Dictionary)["fighter"]))
		mine = "You: " + _fighter_name(String((who[me] as Dictionary)["fighter"]))
	if not lines:
		return them
	var out := PackedStringArray([mine, them])
	var left := _pick_countdown()
	if left != "":
		out.append(left)
	if netplay.room_watchers > 0:
		out.append("%d watching" % netplay.room_watchers)
	return "\n".join(out)


static func _fighter_name(id: String) -> String:
	return String(MatchFactory.load_def(id).get("name", id)) if id in MatchFactory.FIGHTERS else id


## The rematch pick's countdown as a line ("" when there's none, as in a room).
func _pick_countdown() -> String:
	if netplay == null or netplay.pick_secs <= 0.0:
		return ""
	return "Starts in %d s" % ceili(netplay.pick_seconds_left())


## Each tick in a room: keep the room page and the select's panel up to date (and, with
## --cpu-vs-cpu, go on to the next match by itself).
func _room_step() -> void:
	if _room_status_label != null and is_instance_valid(_room_status_label):
		var t := _room_summary(true)
		if netplay.picked:
			t = ("Locked in. Waiting for your opponent...\n" if _rematch_page else "Locked in. Waiting for the others...\n") + t
		_room_status_label.text = t
	if _room_picker != null and is_instance_valid(_room_picker):
		_room_picker.set_solo_info(_room_summary(true))
	if _cpu_vs_cpu and netplay.in_room() and flow == Flow.MATCH_OVER and flow_t == MATCH_OVER_MENU_AT + 120 \
			and not netplay.picking:
		_room_next()


## A spectator in a room: the match-over screen says what the room is doing (picking,
## or waiting for a player); a player leaving mid-match ends the view of that match.
func _watch_room_status() -> void:
	if (netplay.room == "" and netplay.room_state != "select") or netplay.phase == Netplay.Phase.ENDED:
		if flow == Flow.MATCH_OVER and _match_over_status != null and is_instance_valid(_match_over_status) \
				and netplay.phase == Netplay.Phase.ENDED:
			_match_over_status.text = netplay.status
		return
	if netplay.room != "" and netplay.room_state == "waiting" and flow == Flow.FIGHT:
		flow = Flow.MATCH_OVER
		flow_t = 0
		hud.banner = "A PLAYER LEFT"
		hud.banner_sub = ""
	if flow == Flow.MATCH_OVER and _match_over_status != null and is_instance_valid(_match_over_status):
		match netplay.room_state:
			"select":
				_match_over_status.text = "Players are picking fighters for the %s (%d of %d locked in)" % [
					"next match" if netplay.room != "" else "rematch",
					netplay.room_players.filter(func(p): return bool(p["locked"])).size(), netplay.room_players.size()]
				if netplay.pick_all_locked and netplay.room_players.size() == 2:
					_match_over_status.text = "Rematch: %s vs %s" % [
						_fighter_name(String(netplay.room_players[0]["fighter"])),
						_fighter_name(String(netplay.room_players[1]["fighter"]))]
				var left := _pick_countdown()
				if left != "":
					_match_over_status.text += "\n" + left
			"waiting":
				_match_over_status.text = "Waiting for a player to join room " + _room_code()
			_:
				_match_over_status.text = ""


## The address just joined goes to the top of the recent list (kept short).
func _remember_server(addr: String) -> void:
	addr = addr.strip_edges()
	if addr == "":
		return
	_recent_servers.erase(addr)
	_recent_servers.push_front(addr)
	_recent_servers = _recent_servers.slice(0, OnlineLobby.MAX_RECENT)


## After a match: Rematch, Change fighters (modes with a pick screen) or Main menu;
## online, Rematch or Leave, with what the other player is doing. It sits low so the
## winner's banner stays in view. Back = Main menu / Leave.
func _show_match_over() -> void:
	var scr := UiScreen.new()
	scr.dim = 0.35
	scr.column_shift = 52.0
	scr.row_width = 170.0
	scr.hints = ["move", "select", "back"]
	var cfg: Dictionary = MODES[mode]
	scr.builder = func(s: UiScreen):
		if sim != null and not _replaying() and mode != REPLAY_MODE and showcase == null and coach == null:
			s.add_text("F6  save this fight's replay", UiTheme.SIZE_HINT, UiTheme.C_DIM)
		for line in _ctf_summary():
			s.add_text(String(line[0]), UiTheme.SIZE_HINT + (2 if line[1] == UiTheme.C_ACCENT else 0), line[1])
		if online != null and netplay.in_room():
			s.add_button("Next match", _room_next, "Pick a fighter (or keep yours) for the next match in this room")
			s.add_button("Leave room", _leave_to_lobby, "Back to the online screen; the room carries on without you")
			s.add_row(RoomCodeButton.new(_room_code()), "Copy the code to send to a friend")
			_match_over_status = s.add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
			s.on_back = _leave_to_lobby
		elif online != null:
			# A 1v1 rematch picks fighters first (both players, once both ask); a team
			# battle starts again with the same ones. Ranked rates every game.
			var again := s.add_button("Rematch", func(): pass, "Play again; once both ask, you both pick fighters"
				if online.players == 2 else "Play again; it starts when everyone asks")
			var asked := func():
				again.disabled = true
				again.text = "Rematch asked"
			again.pressed.connect(func():
				netplay.request_rematch()
				asked.call())
			if netplay.rematch_local:
				asked.call()
			if netplay.ranked:
				s.add_button("Back to online", _leave_to_lobby, "Search again from the online screen")
			s.add_button("Leave", _leave_online, "Back to the title menu")
			_match_over_status = s.add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
			s.on_back = _leave_to_lobby if netplay.ranked else _leave_online
		elif watch != null:
			s.add_button("Leave", _leave_online, "Back to the title menu")
			if netplay != null and netplay.room != "":
				s.add_row(RoomCodeButton.new(_room_code()), "Copy the code to send to a friend")
			# What's next: the players picking, a rematch, or the match ending.
			_match_over_status = s.add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
			s.on_back = _leave_online
		elif _replaying() or mode == REPLAY_MODE:
			s.add_button("Replay theater", func():
				_open_menu("single")
				_open_replays(), "Pick another")
			s.add_button("Main menu", func(): _open_menu(), "Back to the title menu")
			s.on_back = func(): _open_menu()
		else:
			if arcade != null and arcade.can_retry() and not _arcade_cleared:
				s.add_button("Retry the stage", func():
					_close_ui()
					wins = [0, 0]
					round_num = 1
					_start_arcade_stage(), "The same stage again")
			elif arcade != null:
				s.add_button("Play again" if arcade is Daily else "New run", func():
					seed_base += 1
					_start_match(mode), "Today's fight again" if arcade is Daily else "A fresh run from the start")
			else:
				s.add_button("Rematch", func():
					seed_base += 1
					_start_match(mode, true), "The same fighters again")
			if _has_pick(cfg) and not _skip_select:
				s.add_button("Change fighters", func(): _start_match(mode), "Back to the pick screen")
			s.add_button("Main menu", _back_to_row, "Back to where you picked this mode")
			s.on_back = _back_to_row
	ui.push(scr)


func _end_online() -> void:
	if _finder != null:
		_finder.cancel()
	_finder = null
	_ready_screen = null
	_room_screen = null
	_room_picker = null
	_rematch_page = false
	netplay = null
	online = null
	watch = null
	if hud != null:
		hud.net_info = ""


## --net-report=PATH: the match's inputs and state fingerprints as JSON, so two
## machines' reports can be compared (or a desync replayed). Also written on a desync.
## PATH always holds the latest match (its number and teams are in it); `keep` (a
## rematch or a room's next match is starting) also keeps the finished one beside it as
## PATH_m<n>.json, so a run of several matches leaves every match's fighters and inputs.
func _write_net_report(keep := false) -> void:
	if online == null:
		return
	var path := String(_net_args.get("report", ""))
	if path == "" and online.desync_frame < 0:
		return
	if path == "":
		DirAccess.make_dir_recursive_absolute("user://desyncs")
		path = "user://desyncs/desync_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
		keep = false
	var text := JSON.stringify(online.report())
	var paths := [path]
	if keep:
		paths.append("%s_m%d.%s" % [path.get_basename(), online.id, path.get_extension() if path.get_extension() != "" else "json"])
	for p in paths:
		var f := FileAccess.open(String(p), FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_print_perf()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android's Back (gesture or key): the same as Esc, so it never closes the game.
		var ev := InputEventAction.new()
		ev.action = "pause"
		ev.pressed = true
		Input.parse_input_event(ev)
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		# Switched away on a phone: an offline fight waits under the pause menu.
		if online == null and showcase == null and not paused and not ui.is_open() \
				and not (flow in [Flow.MENU, Flow.SELECT, Flow.LOBBY, Flow.MATCH_OVER]):
			_open_pause()
	elif what == NOTIFICATION_PREDELETE:
		_join_cpus()


## Prints the --perf report and saves it as user://perf.txt (a player's build has no
## console to print to).
func _print_perf() -> void:
	if _perf != null:
		var text := _perf.report()
		print(text)
		var f := FileAccess.open("user://perf.txt", FileAccess.WRITE)
		if f != null:
			f.store_string(text + "\n")
			f.close()
		_perf = null


func _capture() -> void:
	var t := frame_count
	if _shots.has(t):
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		get_viewport().get_texture().get_image().save_png(_shot_dir.path_join("shot_%04d.png" % t))
	if _quit_after > 0 and t >= _quit_after:
		_write_net_report()
		_print_perf()
		get_tree().quit()
