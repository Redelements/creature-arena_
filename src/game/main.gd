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
##   --time=ID             time of day for offline matches this session: random, day, sunset,
##                         night (data/weather.json; a choice the arena doesn't allow falls back:
##                         night is the Floodgate's only)
##   --weather=ID          weather for offline matches this session: random, clear, rain, fog,
##                         wind, snow
##   --autoplay            training demo: the player side follows a scripted routine
##   --dummy-mode=N        0 stand, 1 guard, 2 walk, 3 dodge
##   --training-flags=no_cooldowns,full_energy  training options on (pause > Training options)
##   --training-screen=pause|options|fighters  open the training pause menu, its Training
##                         options page or the Change fighter grid once training starts (captures)
##   --hitboxes            start with the hitbox overlay on
##   --intro / --no-intro  force the arena intro on / off (default: it plays before offline
##                         matches started from the menu; off headless and for a --mode,
##                         --showcase or --autoplay start, so captures and tests keep their timing)
##   --range-rings         start with the range rings on (Settings > Controls; F7 in a fight)
##   --shots=60,120        save screenshots at those frame numbers
##   --shot-dir=PATH       where screenshots go (default user://shots)
##   --cam=X,Y[,ZOOM]      hold the camera on this world spot (and zoom), still clamped to the
##                         arena and its stands: for screenshots of the edges
##   --cam-lead=0|1 --cam-clash=0|1 --cam-settle=0|1  camera behaviour off / on (Normal) for
##                         this session, not saved (also low|normal|high; Settings > Video > Camera)
##   --quit-after=N        exit after N frames
##   --lighting=off|low|high  real 2D lights this session, not saved (Settings > Video >
##                         Lighting otherwise; Light2DView, BloomView)
##   --a11y=teams,outlines,markers  Settings > Accessibility this session, not saved: colour-safe
##                         team colours, fighter outlines (High contrast; `outlines=team` for
##                         Team), high-contrast hit markers; any of them, or `all`
##   --print-vram=N        print the texture memory Godot reports (and the fighter sheets
##                         loaded, CreatureView.sheet_report) at frame N (budget checks)
##   --perf                log frame and tick times during fights; on quit, prints the
##                         percentiles, the 1% and 0.1% lows, missed frames and the worst
##                         second, and saves them to user://perf.txt
##   --fight-fps=N         the fight frame cap this session, not saved (Settings > Video >
##                         Fight frame rate otherwise): 120 on the Odin for perf runs
##   --fps-pacing=cap|vsync  vsync (the default on mobile): vsync paces a fight cap at or
##                         over the screen's refresh rate instead of the frame limiter (pace_cap)
##   --cpu-threads=off     CPU players think one after another on the main thread
##                         (default: together on the worker threads; same answers)
##   --cpu-think=threads|gap  where the next tick's CPU thinking runs at 120 fps and up: the
##                         worker threads, or the main thread in the frame between ticks
##                         (default gap on mobile, threads elsewhere; same answers)
##   --layout=league|classic  keyboard layout (saved in the menu otherwise)
##   --pad-layout=standard|twinstick  controller layout (saved in Settings otherwise)
##   --touch-demo[=left]   play a recorded touch script into the touch controls (training as
##                         Cairn unless --mode is given; =left mirrors them): overlay captures
##   --showcase=NAME       play one scripted demo on a loop: cairn, culvert, craglash, barkley, gillbert,
##                         cerebro, cleaver (the Cleaver Toss bounce), hissy, digby, pete, sno, angles, twinstick or counterplay
##   --teams=a,b,c:d,e,f   Duel / 2-player teams (default cerebro,gillbert,barkley:culvert,cerebro,craglash)
##   --pick                show the team pick screen even with --mode
##   --cpu-vs-cpu          every player side is played by the CPU (demos, captures)
##   --mutators=a,b        these mutators (data/rules/mutators.json ids: tidal_wave,
##                         meteor_shower, low_gravity...) on every offline match this session
##                         (over Arena options > Hazards); Chaos Cup plays them instead of its draw
##   --view-team=N         show the match as team N sees it (brush, fences, walls hide
##                         foes), even with nobody playing here (captures of --cpu-vs-cpu)
##   --menu=PAGE           open a menu page: main, single, single:<group>, look (Time and weather), settings, game, video, audio, accessibility, controls,
##                         remap:classic|league|gamepad, credits, credits:<row> (game, szadi,
##                         kiddolink, font, godot, notices) (captures)
##   --online-host[=PORT]  host an online 1v1 straight away (UDP, default port 7777)
##   --online-join=ADDR[:PORT][/ROOM]  join one, or a dedicated server (ROOM: meet a friend there)
##   --online-watch=ADDR[:PORT][/ROOM] watch a server's match (a room's, from match to match)
##   --server[=PORT]       run as a dedicated server (with --headless); --max-players=N
##   --fighter=ID          your fighter online
##   --online-size=N       with --online-join to a server: 2, 3 or 4 asks for a 2v2 / 3v3 / 4v4 (4: Capture the Flag)
##   --net-lag=N --net-loss=F   hold back / drop the input stream (feel rollback on a LAN)
##   --net-delay=N         force the input delay (frames) instead of picking it from the ping
##   --voice=off|ptt|open  voice chat off / push to talk / open mic this session, not saved
##                         (Settings > Audio > Voice chat otherwise)
##   --voice-test=tone     online: send a 220 Hz tone instead of the microphone (open mic,
##                         always held) and log "voice: sent N" and "voice: heard slot ..."
##                         once a second: two processes test the voice path on one machine
##                         (run them in real time: with --fixed-fps game time outruns the
##                         clock, the tone comes faster than it plays and the queue drops)
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
## The Settings pages and their rows, in order (see _setting()); "#Name" is a heading.
const SETTING_PAGES := {
	"game": ["level", "intros", "rumble", "shake", "discord", "server", "delay"],
	"video": ["fullscreen", "wide", "vsync", "fps", "glow", "lighting", "font", "perf_overlay", "#Camera", "cam_lead", "cam_clash", "cam_settle"],
	"accessibility": ["a11y_teams", "a11y_outlines", "a11y_markers"],
	"audio": ["vol_Master", "vol_Music", "vol_Effects", "vol_Menu", "#Voice chat", "voice", "voice_hear", "mic", "mic_test", "vol_Voice"],
	"touch": ["touch_opacity", "touch_size", "touch_hand", "touch_aim", "#Targeting", "touch_priority", "touch_chase"],
}
## Settings > Controls > Touch: how see-through the touch controls are.
const TOUCH_OPACITY := [0.3, 0.5, 0.7, 0.9]
const TOUCH_OPACITY_DEFAULT := 2
const SHAKE_CHOICES := [["Full", 1.0], ["Reduced", 0.5], ["Off", 0.0]]
const VOLUME_NAMES := {"Master": "Master volume", "Music": "Music", "Effects": "Sound effects",
	"Menu": "Menu sounds", "Voice": "Voice volume"}
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
		"desc": "A Brawl with three random mutators stacked on: low gravity, Surge rush, a floor of pits, haste, glass cannon, a tidal wave, a meteor shower, a rolling boulder, a fault line"},
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
const ROUND_TICKS := 120 * 60  ## two minutes since fighters have double health (Oct 2026; was 90 s)
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
## On a phone or a handheld (Android) fights default to 60 (Kevin's call, Oct 2026: not
## every phone holds 120). The Odin 3 holds 120 when picked in Settings > Video (Vulkan, CPU
## thinking between ticks, vsync pacing: one frame held in 76 s of 4v4 CTF).
const DEFAULT_FPS_MOBILE := 60


## The fight frame rate to start with: `mobile` is the platform's (a test passes its own).
static func default_fps(mobile := OS.has_feature("mobile")) -> int:
	return DEFAULT_FPS_MOBILE if mobile else DEFAULT_FPS


## Glow starts on, except on a phone or handheld (weaker GPUs; it can be turned on).
static func default_glow(mobile := OS.has_feature("mobile")) -> bool:
	return not mobile


## Lighting (Light2DView.Tier) starts High on a desktop, Low on a phone or handheld.
static func default_lighting(mobile := OS.has_feature("mobile")) -> int:
	return Light2DView.Tier.LOW if mobile else Light2DView.Tier.HIGH
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
## Camera behaviour (Settings > Video > Camera), each Off / Low / Normal / High (an index
## into these tables; `--cam-lead=` / `--cam-clash=` / `--cam-settle=` for a session).
## All of it eases the camera's target once a tick; nothing reads or writes sim state but
## the fighters' positions, facing, last input bits and the events.
const CAM_LEVELS := ["Off", "Low", "Normal", "High"]
const CAM_DEFAULT := 2
## Aim lead: the camera leans toward where the viewed fighter aims (its IN_AIM angle, else
## its facing) by AIM_LEAD px (y x AIM_LEAD_Y: the screen is wider than tall). An aim
## within AIM_DEAD_DOT (about 20 degrees) of the one held doesn't move it (mouse and stick
## wobble); it eases toward a new aim at AIM_EASE_IN and back toward nothing at AIM_EASE_OUT.
const AIM_LEAD := [0.0, 8.0, 14.0, 22.0]
const AIM_LEAD_Y := 0.75
const AIM_DEAD_DOT := 0.94
const AIM_EASE_IN := 0.05
const AIM_EASE_OUT := 0.025
## Clash reaction: a heavy hit (CLASH_HEAVY of the full push), a guard break or a Surge's
## hit punches in by CLASH_PUSH (x the zoom) and leans CLASH_SHIFT px toward the impact,
## eased in at CLASH_IN, held CLASH_HOLD ticks, eased out at CLASH_OUT. Never on top of the
## exchange push-in (the larger of the two counts, not the sum), never past EXCHANGE_PAD,
## and not for the hit that knocks someone out (the KO push-in owns that moment).
const CLASH_PUSH := [0.0, 0.04, 0.07, 0.11]
const CLASH_SHIFT := [0.0, 4.0, 8.0, 12.0]
const CLASH_HEAVY := 0.6
const CLASH_HOLD := 8
const CLASH_IN := 0.35
const CLASH_OUT := 0.08
## Settle: after SETTLE_AFTER ticks with nothing happening (no buttons or moves pressed,
## nobody moving or out of IDLE, no hits, no push-in), the camera only follows what drifts
## more than SETTLE_DEAD px from where it was held, drifting there at SETTLE_DRIFT a tick
## (normally 0.1), and changes zoom only past SETTLE_ZOOM_DEAD (still pulling back quickly
## so nobody leaves the shot). Anything at all puts the normal rules back on the next tick.
const SETTLE_AFTER := 60
const SETTLE_DEAD := [0.0, 8.0, 14.0, 22.0]
const SETTLE_DRIFT := [0.0, 0.04, 0.03, 0.02]
const SETTLE_ZOOM_DEAD := 0.04
const SETTLE_ZOOM_EASE := 0.03
## Input bits that count as "something happening" for Settle (every button and a move;
## not the aim angle alone, which a mouse sends all the time: the aim lead's dead zone
## decides when an aim counts).
const CAM_ACT_BITS := SimDefs.IN_ALL | SimDefs.IN_MOVE

var sim: MatchSim
var _cam_zoom := 0.0  ## eased toward a zoom that fits the fighters (0: snap on the next frame)
var cam_lead := CAM_DEFAULT  ## Settings > Video > Aim lead (a CAM_LEVELS index)
var cam_clash := CAM_DEFAULT  ## Settings > Video > Clash reaction
var cam_settle := CAM_DEFAULT  ## Settings > Video > Settle
var _cam_cli := {}  ## --cam-lead= and the like: this session only, never saved
var _cam_aim := Vector2.ZERO  ## the aim lead, eased
var _cam_aim_dir := Vector2.ZERO  ## the aim the lead holds (changes only past the dead zone)
var _cam_off := Vector2.ZERO  ## the whole offset from _cam_follow this tick (leads + clash), cut to the room
var _cam_zclash := 1.0  ## the clash push-in's zoom factor this tick
var _clash := 0.0  ## the clash reaction, 0..1, eased
var _clash_want := 0.0
var _clash_hold := 0
var _clash_pos := Vector2.ZERO
var _cam_idle := 0  ## ticks with nothing happening (Settle)
var _settle_mid := Vector2.ZERO  ## Settle's held target (moved only past SETTLE_DEAD)
var _settle_fit := 0.0  ## and its held zoom (moved only past SETTLE_ZOOM_DEAD)
var cam_ctl := MainCamera.new(self)  ## the camera's per-tick work (main_camera.gd); its state stays here
var replay: Replay
## Where F6 saves and the Replay theater looks (a test points it at a folder not made yet,
## as on a fresh install). It may not exist: `Replay.save` makes it.
var replays_dir := "user://replays"
var arena: ArenaView
var crowd: CrowdView
var backdrop: BackdropView
var fore: ForeView  ## the near layer over the fighters: front rail and fans, what hangs at the back
var furniture: FurnitureView
var entities: Node2D
var views: Array[CreatureView] = []
var fx: FxView
var fx_ground: FxGround
var water: WaterView
var ambient: AmbientView
var wear: FloorWear
var shadows: ShadowLayer
## Time of day and weather (WeatherView, data/weather.json): views only, never the sim.
var weather: WeatherView
## The Single player menu's Time / Weather: an id or "random" (saved; `--time=` / `--weather=`
## override them for the session).
var time_choice := WeatherView.RANDOM
var weather_choice := WeatherView.RANDOM
## Arena options > Hazards: the arena hazards switched on (Hazards ids), saved under
## `game/hazards`. Off by default. On every offline match but the Daily, ladders, coaches,
## showcases, replays and the menu background (`_session_mutators`). Chaos Cup ignores
## them: its draw can always pick a hazard (`_chaos_table`).
var hazards_on: Array = []
var _look_cli := {}
var _look := {}  ## this match's look (kept across its rounds)
var _look_fresh := true  ## a new match: pick the look again
var _menu_bg := false  ## the menu's background fight is being set up
## Glow (Settings > Video): light pools on the floor and halos over the effects (LightView).
var glow_floor: LightView
var glow_halo: LightView
var glow := default_glow()
## Lighting (Settings > Video): real 2D lights on the fighters and, High, the night's lamps and
## bloom (Light2DView, BloomView). `--lighting=` overrides it for the session.
var light2d: Light2DView
var light_floor: Light2DView.FloorGlow
var canopies: Node2D  ## tree crowns over the fighters (ArenaView.overhead)
var glade: GladeView  ## leaf shade, shafts, fireflies, smoke round a map's trees and keeps
var plants: PlantView  ## Barkley's sprouts, trees and apples (the trees' shadows here, the plants among the fighters)
var light_lamps: Light2DView.FloorGlow  ## the arena's lamps by day and at sunset (Light2DView.lamp_glow)
var light_lamps_b: Light2DView.FloorGlow  ## the other half of them (Light2DView.lamp_glow_b)
var bloom: BloomView
var lighting := default_lighting()
var _lighting_cli := -1
var _lit_look: Dictionary = {}  ## this match's time and weather (Lighting re-applies it)
var audio: AudioView
## Proximity voice chat's microphone and speakers (online only; Settings > Audio).
var voice_view: VoiceView
var voice_mode: int = VoiceChat.Mode.PUSH_TO_TALK  ## the saved setting (audio/voice_mode)
var mic_device := ""  ## the saved microphone (audio/mic_device; "" the system's default)
## Settings > Audio > Hear voices from (audio/voice_hear): 0 Everyone, 1 Rooms and friends
## (a server Quick match or ranked match starts with everyone muted: `_apply_voice_hear`).
const VOICE_HEAR := ["Everyone", "Rooms and friends"]
var voice_hear := 0
var _voice_cli := -1  ## --voice=: this session's mode, never saved (-1: the setting)
var _voice_test := false  ## --voice-test=tone
var voice_ctl := MainVoice.new(self)  ## voice chat's glue (main_voice.gd)
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
## --menu=PAGE: open a menu page on start (captures): single, single:<group>, settings, game, video, audio, accessibility, controls, credits[:row].
var _menu_arg := ""
var args_ctl := MainArgs.new(self)  ## the command line (main_args.gd)
var _setting_rows := {}  ## Settings key -> its OptionRow, while the page is open
var _match_over_status: Label = null
var _recent_servers: Array = []
var fullscreen := false
var fight_fps := default_fps()
## Where settings are kept (tests point it elsewhere, so they never touch the player's).
var settings_path := SETTINGS_PATH
var settings_ctl := MainSettings.new(self)  ## Settings: the pages, each row's value and change, the file (main_settings.gd)
var vsync := true
## Wider-than-16:9 screens (ultrawide, 16:10): fill them with more stadium, or keep 16:9
## with bars.
var wide_fill := true
var rumble := true
var shake_scale := 1.0  ## screen shake: 1 full, 0.5 reduced, 0 off
var range_rings := false  ## floor rings showing each attack's real reach (Settings > Controls)
## Settings > Game > Match intros: the arena intro before an offline match (ArenaIntro).
var match_intros := true
## --intro (1) / --no-intro (-1); 0: the default (see _intro_wanted).
var _intro_arg := 0
## The match was started from the command line (--mode, --showcase, --autoplay): no intro
## unless --intro, so captures keep their frame numbers.
var _cli_start := false
## The arena intro playing now (null: none). The sim is not stepped while it plays.
var intro: ArenaIntro = null
var _screen_layer: CanvasLayer
var rings: RangeRings
## The frame-rate overlay (Settings > Video, F9): PerfOverlay.Mode, over everything.
var perf_overlay: PerfOverlay
var paper: PaperFx
var discord_status := true  ## show what you play on your Discord profile (Settings)
var discord: DiscordRpc = null  ## null: off, headless, or no client id in data/discord.json
var presence: Presence = null
## Off for captures and headless runs, which must not be slowed to real time.
var _fps_caps := true
var _fight_fps_cli := 0  ## --fight-fps=N: this session's fight cap (0: the setting's)
var _fps_pacing := "vsync" if OS.has_feature("mobile") else "cap"  ## --fps-pacing=cap|vsync (pace_cap)
var _refresh := -1.0  ## the screen's refresh rate, -1 until read (_refresh_rate)
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
var grade: GradeView
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
var _arena_row: Control = null  ## the Single player hub's Arena row (its description follows the hazards)
## `--mutators=a,b`: these mutators (data/rules/mutators.json ids, merged) on every offline
## match this session (Chaos Cup plays them instead of its draw), and their names.
var _forced_mutators := {}
var _forced_names: Array = []
var _replay_frames: Array = []
var _replay_watched := {}  ## that replay's setup (a training one's mid-recording option changes)
var _rules_id := ""
var _teams: Array = DEFAULT_TEAMS.duplicate(true)
var _skip_select := false
var _cpu_vs_cpu := false
## What each fighter did this match, counted from the events (results screen).
var stats := MatchStats.new()
var wipe: Wipe
## Ticks since the last press while the title waits; at ATTRACT_AT a CPU-vs-CPU demo plays.
var _idle_t := 0
var _attract := false
var _attract_focus: Control
var _attract_ui: Control
var _attract_hint: Label
var show_ctl := MainPresentation.new(self)  ## title attract, wipes, the arena intro, results (main_presentation.gd)
var _wipe_cat := -1  ## the kind of screen last tick (0 menus, 1 fight, 2 match over)
var _ticks_run := 0
## ~20 s idle on the title before the attract demo starts.
const ATTRACT_AT := 1200
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
## --touch-demo: a recorded touch script played into the touch controls.
var touch_demo: TouchDemo = null
## The touch controls on screen (player 1's PlayerInput.touch), shown while touch is the
## device in a fight.
var touch_overlay: TouchOverlay
var touch_opacity := TOUCH_OPACITY_DEFAULT
var touch_left := false  ## Settings > Controls > Touch > Hand (saved)
var _touch_demo_left := false  ## --touch-demo=left: mirrored this session only
var touch_ctl := MainTouch.new(self)  ## the touch controls' glue (main_touch.gd)
var frame_count := 0
var _shots := {}
var _shot_dir := "user://shots"
var _cam_force := Vector3.ZERO  ## --cam=x,y,zoom: the camera held here (screenshots)
var _quit_after := 0
var _print_vram_at := 0  ## --print-vram=N: print texture memory at frame N
## The CPUs' inputs for this tick are worked out (_think_cpus) and wait in last_bits.
var _cpus_thought := false
## The next tick's CPU thinking, set going at the end of a tick (_think_ahead) so it runs
## on the worker threads while the frame is drawn; -1 when none is running. _cpu_ahead is
## the match and tick it read: the next tick takes its answers only if it steps that same
## match from that same tick. On with a screen (the headless tests think in the tick).
var _cpu_task := -1
var _cpu_ahead: Array = []
var _cpus_early := false
## Where the next tick's CPU thinking runs: "threads" (the worker threads, while the frame
## draws) or "gap" (on the main thread, in the next frame that steps no tick: at 120 fps
## every other frame is nearly empty). Gap is the default on mobile: Android keeps the
## game's thread on the two fast cores, and the worker threads thinking there took them
## from it for up to 16 ms at a time (Odin 3 trace, Oct 2026). `--cpu-think=threads|gap`.
var cpu_think := "gap" if OS.has_feature("mobile") else "threads"
## Gap mode: the match and tick the CPUs should think ahead from in the next tickless frame.
var _cpu_gap: Array = []
var _gap_physics_frame := -1  ## the tick count and frame when _cpu_gap was set
var _gap_process_frame := -1
## Gap mode's time budget (µs): CPUs think one by one in the gap until it is spent; the
## rest think in the tick. A slow decision then splits over both frames instead of
## making one of them miss the screen (9-10 ms of thinking on the Odin 3 at worst).
var gap_budget_us := 4000
var _gap_done := 0  ## how many of _cpu_list() the gap thought for (_cpu_ahead's tick)
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
var online_ctl := MainOnline.new(self)  ## the online flow (main_online.gd)
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
## The tick a round ended on and the player's health share then ([] before one ends).
var _round_end: Array = []
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
	if args_ctl._run_sim_check() or args_ctl._run_server():
		return
	_fit_window()
	_apply_pixel_scale()
	get_window().size_changed.connect(_apply_pixel_scale)
	get_window().size_changed.connect(func(): _refresh = -1.0)
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

	backdrop = BackdropView.new()  # the sky and the far tiers, sliding less than the camera (parallax)
	add_child(backdrop)
	arena = ArenaView.new()
	add_child(arena)
	crowd = CrowdView.new()
	furniture = FurnitureView.new()  # floodlights, flags, the scoreboard, sponsor boards (arena JSON "furniture")
	furniture.backdrop = backdrop
	add_child(furniture)
	add_child(crowd)
	wear = FloorWear.new()  # scratches, gouges, craters, prints: the floor remembers, under everything
	add_child(wear)
	weather = WeatherView.new()
	add_child(weather.shade)  # the time of day's tint over the floor, crowd and wear, under the floor effects
	fx_ground = FxGround.new()
	add_child(fx_ground)
	water = WaterView.new()  # living water over the shallows, under the fighters
	add_child(water)
	ambient = AmbientView.new()  # a map's ambient life (arena JSON "ambient"): panes, sway, motes, butterflies
	add_child(ambient)
	glade = GladeView.new()  # leaf shade, sun shafts, fireflies, smoke, spray (arena JSON "ambient.glades"; Twin Keeps)
	add_child(glade)
	shadows = ShadowLayer.new()  # the fighters' shadows, on the floor under everyone
	shadows.views = views
	add_child(shadows)
	plants = PlantView.new()  # Barkley's plants: their shadows on the floor; `stand` goes among the fighters
	plants.weather = weather
	plants.shadows = shadows
	add_child(plants)
	add_child(weather.ground)  # fog bands, rain splashes: over the shadows, under the fighters
	glow_floor = LightView.new()  # light pools on the floor, over the shadows, under the fighters
	add_child(glow_floor)
	light_floor = Light2DView.FloorGlow.new()  # the fight's real lights on the floor (Lighting), at the pools' depth
	add_child(light_floor)
	light_lamps = Light2DView.FloorGlow.new(Light2DView.LAMP_GLOW_MASK)  # an arena's lamps by day (Twin Keeps' torches)
	add_child(light_lamps)
	light_lamps_b = Light2DView.FloorGlow.new(Light2DView.LAMP_GLOW_MASK_B)  # every other one (15 lights an item)
	add_child(light_lamps_b)
	rings = RangeRings.new()
	rings.visible = false
	rings.fx = fx  # what the local team can see (Vision): no rings for a hidden foe
	add_child(rings)  # on the floor, under the fighters
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	entities.add_child(plants.stand)  # y-sorted with the fighters: behind a tree is behind it
	canopies = Node2D.new()  # tree crowns over the fighters (a map's dressing; ArenaView.overhead fades them over our own)
	add_child(canopies)
	arena.overhead = canopies
	fore = ForeView.new()  # the nearest fans and a rail at the front, hangings at the back: over the fighters, faster than the floor
	add_child(fore)
	weather.views = views
	add_child(weather)  # rain, snow, blown debris: over the fighters, under telegraphs and health bars
	fx = FxView.new()
	fx.bind_ground(fx_ground)
	fx.wear = wear
	add_child(fx)
	paper = PaperFx.new()  # Mister Crease's sheets, crafts and storms, over the fighters
	paper.fx = fx
	add_child(paper)
	glow_floor.fx = fx
	glow_halo = LightView.new()  # the same lights as halos, over the effects
	glow_halo.halo = true
	glow_halo.source = glow_floor
	add_child(glow_halo)
	_apply_glow()
	light2d = Light2DView.new()  # real 2D lights (Lighting): only fighter sprites and the night shade take them
	light2d.fx = fx
	light2d.floor_glow = light_floor
	light2d.lamp_glow = light_lamps
	light2d.lamp_glow_b = light_lamps_b
	light2d.views = views  # each seen fighter's own sun
	add_child(light2d)
	bloom = BloomView.new()  # half-size bloom of the bright things, added onto the screen layer
	bloom.glow = glow_floor
	bloom.light2d = light2d
	bloom.fx = fx
	bloom.water = water
	add_child(bloom)
	audio = AudioView.new()
	add_child(audio)
	fx.cue.connect(audio.play)
	voice_view = VoiceView.new()
	add_child(voice_view)
	debug = DebugView.new()
	debug.visible = false
	add_child(debug)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_screen_layer = layer
	letterbox = Letterbox.new()  # first on the screen layer: under the flash, the fade and the HUD
	grade = GradeView.new()  # the map's tint and vignette (arena JSON "grade"): under everything on the screen layer
	layer.add_child(grade)
	layer.move_child(grade, 0)
	layer.add_child(bloom.out)  # over the grade, under the letterbox and the HUD
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
	touch_overlay = TouchOverlay.new()  # over the HUD, under the menus
	touch_overlay.pad = player_input.touch
	touch_overlay.target = player_input.target
	touch_overlay.hud = hud  # its portrait pictures
	touch_overlay.visible = false
	layer.add_child(touch_overlay)
	var top := CanvasLayer.new()
	top.layer = 30  # over the menus (ScreenStack is 20)
	add_child(top)
	_attract_ui = Control.new()
	_attract_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_attract_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attract_ui.visible = false
	top.add_child(_attract_ui)
	var mark := TextureRect.new()
	mark.texture = load(UiScreen.LOGO_PATH) as Texture2D
	mark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	mark.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mark.anchor_left = 0.0
	mark.anchor_right = 1.0
	mark.offset_left = 0.0
	mark.offset_right = 0.0
	mark.offset_top = 22.0
	mark.offset_bottom = 86.0
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attract_ui.add_child(mark)
	_attract_hint = Label.new()
	_attract_hint.text = "PRESS ANY BUTTON"
	_attract_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_attract_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_attract_hint.offset_top = -26.0
	_attract_hint.offset_bottom = -8.0
	_attract_hint.add_theme_font_override("font", UiTheme.font())
	_attract_hint.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.SIZE_BIG))
	_attract_hint.add_theme_color_override("font_color", UiTheme.C_TEXT)
	_attract_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_attract_hint.add_theme_constant_override("outline_size", UiTheme.outline(UiTheme.px(UiTheme.SIZE_BIG)))
	_attract_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attract_ui.add_child(_attract_hint)
	wipe = Wipe.new()
	top.add_child(wipe)
	perf_overlay = PerfOverlay.new()
	top.add_child(perf_overlay)
	_row_choice.resize(MENU_ROWS.size())
	_row_choice.fill(0)
	for pin in [player2_input, player3_input, player4_input]:
		(pin as PlayerInput).keyboard = false
		(pin as PlayerInput).pad_device = PlayerInput.NO_PAD

	settings_ctl._load_settings()
	if UiTheme.smooth:
		ui.restyle()  # the menu theme was built before the saved Text font was read
	var start_mode := args_ctl._parse_args()
	_cli_start = start_mode >= 0
	_apply_device()
	_apply_discord()
	_apply_range_rings()
	touch_ctl._apply_touch()
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
		online_ctl._open_lobby()
		if _net_args.has("host"):
			online_ctl._net_host(_online_fighter)
		else:
			_pending_watch = bool(_net_args.get("watch", false))
			var parsed := OnlineLobby.parse_address(String(_net_args["join"]))
			var size := int(_net_args.get("size", 0 if String(parsed[2]) != "" else 1))
			online_ctl._net_join(_online_fighter, String(parsed[0]), int(parsed[1]), String(parsed[2]), true, size)


# ------------------------------------------------------------------ flow

## The title menu, over a CPU match that plays behind it. `page` opens "single" or
## "settings" on top of it; `focus` is the title row to land on ("online" after leaving
## an online match).
func _open_menu(page := "", focus := "") -> void:
	show_ctl._stop_attract()
	hud.banner_hidden = false
	_close_ui()
	online_ctl._end_online()
	flow = Flow.MENU
	flow_t = 0
	_end_showcase()
	_end_duel()
	_end_coach()
	hud.visible = true
	hud.menu_visible = true
	audio.play_music("menu")
	_menu_background()
	var land := focus if focus != "" else ("settings" if page in SETTING_PAGES or page == "controls" or page.begins_with("remap:") \
		or page.begins_with("credits") else page)
	var t := TitleScreen.new(land)
	t.single_pressed.connect(_open_single)
	t.online_pressed.connect(func(): _start_match(ONLINE_MODE))
	t.settings_pressed.connect(settings_ctl._open_settings)
	t.exit_pressed.connect(func(): get_tree().quit())
	ui.push(t)
	if page.begins_with("single:"):  # a Single player page, for captures: --menu=single:team
		_open_single()
		_open_single_group(page.get_slice(":", 1))
		return
	match page:
		"single":
			_open_single()
		"look":  # the Time and Weather page, for captures
			_open_single()
			_open_look_page()
		"settings":
			settings_ctl._open_settings()
		"game", "video", "audio", "accessibility":
			settings_ctl._open_settings()
			settings_ctl._open_settings_page(page)
		"controls":
			settings_ctl._open_settings()
			settings_ctl._open_controls()
		"touch":
			settings_ctl._open_settings()
			settings_ctl._open_controls()
			settings_ctl._open_settings_page("touch")
		"credits":
			settings_ctl._open_settings()
			settings_ctl._open_credits()
		"credits:game", "credits:szadi", "credits:kiddolink", "credits:font", "credits:godot", "credits:notices":
			settings_ctl._open_settings()
			settings_ctl._open_credits()
			(ui.top() as CreditsScreen).open_page(page.get_slice(":", 1))
		"remap:classic", "remap:league", "remap:gamepad":  # captures of a Remap page
			settings_ctl._open_settings()
			settings_ctl._open_controls()
			settings_ctl._open_remap(page.get_slice(":", 1))


## A CPU-vs-CPU match behind the menus (restarted now and then; the screens stay).
func _menu_background(demo := false) -> void:
	_menu_bg = true
	var a := "cairn"
	var b := "culvert"
	if demo:  # the attract demo: two different fighters each time round
		var pool: Array = MatchFactory.FIGHTERS
		var ia: int = (seed_base * 7 + 3) % pool.size()
		var ib: int = (ia + 1 + seed_base % (pool.size() - 1)) % pool.size()
		a = String(pool[ia])
		b = String(pool[ib])
	_new_sim(MatchFactory.versus(a, b), [Side.CPU, Side.CPU])
	_menu_bg = false
	hud.timer_ticks = -1
	hud.banner = ""
	hud.banner_sub = ""


# ------------------------------------------------------------------ wipes and attract

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
			func(i: int): _set_arena(ArenaMap.IDS[i]), _arena_desc())
		_arena_row = arena_row
		arena_row.activates = true
		arena_row.activated.connect(func():
			ui.notify_chosen()
			_open_look_page())
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
	scr.row_width = 226.0
	scr.row_gap = 2
	scr.detail = true
	scr.detail_width = 170.0  # room for a card's facts on one line (tests/test_ui_fit.gd)
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
						settings_ctl._save_settings(), desc)
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


## Enter on the Arena row: Arena options, a page with the Time and Weather options (looks
## only) and the Hazards (how the match plays): the hub has no room for more rows.
func _open_look_page() -> void:
	var scr := UiScreen.new()
	scr.logo = true
	scr.crumbs = ["SINGLE PLAYER"]
	scr.title = "ARENA OPTIONS"
	scr.row_width = 236.0
	scr.detail = true
	scr.blurb = "Time and weather change how offline matches look; hazards change how they play"
	scr.hints = ["move", "change", "back"]
	scr.builder = func(p: UiScreen):
		p.add_heading("Time and weather")
		_add_look_rows(p)
		p.add_space(2)
		p.add_heading("Hazards")
		_add_hazard_rows(p)
		p.add_space(4)
		p.add_button("Back", p.back)
	scr.backed.connect(func():  # the hub's Arena row says what's on
		if _arena_row != null and is_instance_valid(_arena_row) and _arena_row.get_parent() != null:
			var hub := ui.screens[ui.screens.size() - 2] as UiScreen if ui.screens.size() >= 2 else null
			if hub != null:
				hub.describe(_arena_row, _arena_desc()))
	ui.push(scr)


## One On/Off row per hazard in data/rules/hazards.json (a new hazard gets its row).
func _add_hazard_rows(s: UiScreen) -> void:
	for id in Hazards.ids():
		var hid := String(id)
		var d: Dictionary = Hazards.table()[hid]
		var desc := "%s. Changes how the match plays: on in every offline match (not the Daily, Arcade, Gauntlet or online). Chaos Cup can always draw it" \
			% String(d.get("desc", Hazards.name_of(hid)))
		s.add_option(Hazards.name_of(hid), ["Off", "On"], 1 if hid in hazards_on else 0,
			func(i: int): _set_hazard(hid, i == 1), desc)


func _set_hazard(id: String, on: bool) -> void:
	if on and not (id in hazards_on):
		hazards_on.append(id)
	elif not on:
		hazards_on.erase(id)
	hazards_on.sort()
	settings_ctl._save_settings()


## The Arena row's description: what it does, and the hazards that are on.
func _arena_desc() -> String:
	var out := "Where every match is fought. Left/Right: the map. Enter: Arena options (time, weather, hazards)"
	if not hazards_on.is_empty():
		out += ". Hazards: " + ", ".join(hazards_on.map(func(h): return Hazards.name_of(String(h))))
	return out


## The mutators a new offline match `s` gets from this session: `--mutators` if given, else
## the Arena options' hazards. Never for the Daily, a ladder's stage, coaches, showcases,
## a replay, the menu background, online or a match that already has its own (Chaos Cup).
func _session_mutators(s: MatchSim) -> Dictionary:
	if not s.mutators.is_empty() or s.tick != 0 or online != null or watch != null or _menu_bg \
			or showcase != null or coach != null or mode == REPLAY_MODE:
		return {}
	if not _forced_mutators.is_empty():
		return _forced_mutators
	if arcade != null or hazards_on.is_empty():
		return {}
	return {"hazards": hazards_on.duplicate()}


## "Hazards: Tidal wave, Meteor shower" for a match's opening banner ("" without any).
func _hazard_line() -> String:
	var hz: Array = sim.mutators.get("hazards", []) if sim != null else []
	if hz.is_empty():
		return ""
	return "Hazards: " + ", ".join(hz.map(func(h): return Hazards.name_of(String(h))))


## The Time and Weather options: Random (one the map allows) or a preset.
func _add_look_rows(s: UiScreen) -> void:
	for kind in ["times", "weathers"]:
		var ids: Array = [WeatherView.RANDOM] + (WeatherView.time_ids() if kind == "times" else WeatherView.weather_ids())
		var names: Array = []
		for id in ids:
			names.append("Random" if id == WeatherView.RANDOM else WeatherView.name_of(kind, String(id)))
		var cur := time_choice if kind == "times" else weather_choice
		var label := "Time" if kind == "times" else "Weather"
		var desc := ("Day, sunset or night: how the match looks, never how it plays. Night is on the Floodgate only; other maps play day. Random: one the map allows"
			if kind == "times" else
			"Clear, rain, fog, wind or snow: looks only. Random: one the map allows; one the map doesn't allow plays clear. Online is always day and clear")
		s.add_option(label, names, maxi(0, ids.find(cur)), func(i: int): _set_look_choice(kind, String(ids[i])), desc)


func _set_look_choice(kind: String, id: String) -> void:
	if kind == "times":
		time_choice = id
	else:
		weather_choice = id
	_look_cli.erase("time" if kind == "times" else "weather")
	settings_ctl._save_settings()


## The look of the match `s` is starting: day + clear online, while watching a room and
## for the menu's background fight; a replay's recorded one; else the menu's choice
## (or the command line's) within what the arena allows, kept across a match's rounds.
func _match_look(s: MatchSim) -> Dictionary:
	if online != null or watch != null or _menu_bg:
		return WeatherView.default_look()
	if mode == REPLAY_MODE:
		var rl = _replay_watched.get("look", {})
		return rl if rl is Dictionary and not (rl as Dictionary).is_empty() else WeatherView.default_look()
	var aid := String(s.arena.get("id", ""))
	if _look_fresh or _look.is_empty() or String(_look.get("arena", "")) != aid:
		_look = WeatherView.resolve(s.arena, String(_look_cli.get("time", time_choice)),
			String(_look_cli.get("weather", weather_choice)))
		_look["arena"] = aid
		_look_fresh = false
	return {"time": _look["time"], "weather": _look["weather"]}


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
				var facts := ["First to %d KOs; respawns" % int(t[clampi(size, 0, t.size() - 1)]),
					clock + ", then sudden death"]
				if int(rules.get("spree_at", 0)) > 0:
					facts.append("%d KOs: a spree; end it for +%d" % [int(rules["spree_at"]), int(rules.get("shutdown_cap", 3))])
				return facts
			"crater":
				return ["Hold the zone %d s in all" % (int(rules.get("score_to_win", 3600)) / 60),
					"It moves, breaking the floor", clock]
			"ctf":
				return ["First to %d captures" % int(rules.get("captures_to_win", 3)),
					"Score with your flag home", clock + ", then sudden death"]
			"caravan":
				return ["2 rounds of %s, sides swap" % _mmss(int(float(rules.get("round_seconds", 120)) * 60)),
					"Checkpoints: +%d s, rockslide" % int(rules.get("checkpoint_seconds", 30)),
					"Faster or further push wins"]
			"sinkhole":
				return ["One life; a fall is a KO",
					"A ring falls every %d s, up to %d" % [int(rules.get("shrink_every", 300)) / 60, int(rules.get("max_rings", 14))],
					clock + ", most health wins"]
		return ["One life each, no respawns", clock + ", most health wins"]
	if cfg.get("duel", false):
		var d := DuelSim.load_rules()
		var n := int(d.get("team_size", 3))
		return ["%d v %d tag, the bench heals" % [n, n], "Clock %s" % _mmss(int(float(d.get("time_seconds", 180)) * 60)),
			"Two players on one screen" if two else "You pick both teams"]
	if cfg.get("brawl", false):
		var b := BrawlSim.load_rules()
		var out := ["%d fighters, one life each" % BrawlSim.MAX_PLAYERS,
			"Clock %s, healthiest wins" % _mmss(int(float(b.get("time_seconds", 120)) * 60))]
		if bool(b.get("crown", false)):
			out.append("First KO: the crown, a tie-break")
		if cfg.get("chaos", false):
			out.append("Three mutators each match")
		return out
	if cfg.get("arcade", false):
		return ["%d stages, a 3v3 Duel last" % Arcade.STAGES, "The boss team is a level up", "Clears unlock palettes"]
	if cfg.get("gauntlet", false):
		return ["Endless waves; health carries", "Up a level every %d waves" % Gauntlet.WAVES_PER_LEVEL,
			"Your best is kept"]
	if cfg.get("daily", false):
		return ["One seed a day, for everyone", "%d mutators on the fight" % Daily.PICKS,
			"Clock %s, health + time score" % _mmss(Daily.FIGHT_TICKS)]
	if cfg.get("trials", false):
		return ["One route at a time, demoed", "Land it to clear it"]
	if cfg.has("drill"):
		return ["Red tell: roll away, or hit first", "Gold tell: guard"]
	if cfg.get("training", false):
		return ["A dummy: stand, guard, dodge", "Pause menu: training options"]
	if cfg.get("showcase", false):
		return ["Every fighter's kit, scripted", "Esc comes back here"]
	if cfg.has("left") or cfg.get("versus2p", false):
		var out := ["Best of %d, rounds of %s" % [WINS_NEEDED * 2 - 1, _mmss(ROUND_TICKS)],
			"K.O., or more health left at time"]
		if two:
			out.append("Two players on one screen")
		elif Side.PLAYER in cfg.get("sides", []):
			out.append("CPU at the Settings level")
		else:
			out.append("CPU vs CPU, Settings level")
		return out
	return []


## The arena offline matches play on (the menu's choice is saved with the settings;
## `--arena=ID` only lasts the session).
var _arena_saved := ArenaMap.DEFAULT


func _set_arena(id: String) -> void:
	if id in ArenaMap.IDS:
		MatchFactory.arena = id
		_arena_saved = id
		settings_ctl._save_settings()


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


## In main_settings.gd (tests and other scripts call it here).
func _open_credits() -> void:
	settings_ctl._open_credits()


## In main_settings.gd (tests and other scripts call it here).
func _open_settings_page(page: String) -> void:
	settings_ctl._open_settings_page(page)


## In main_settings.gd (tests and other scripts call it here).
func _refresh_mic_test() -> void:
	settings_ctl._refresh_mic_test()


## In main_settings.gd (tests and other scripts call it here).
static func default_server() -> String:
	return MainSettings.default_server()


## In main_settings.gd (tests and other scripts call it here).
func online_server() -> String:
	return settings_ctl.online_server()


## In main_settings.gd (tests and other scripts call it here).
func _open_controls() -> void:
	settings_ctl._open_controls()


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
	_ko_by_hazard = ""
	_hazard_hit_now.clear()
	_arcade_cleared = false
	if not (keep_teams and m == mode):
		_training_fighter = ""  # a swapped fighter lasts until you leave training
	mode = m
	_look_fresh = true  # a new match: a new look
	wins = [0, 0]
	_carried_energy = [-1.0, -1.0]
	round_num = 1
	hud.menu_visible = false
	settings_ctl._save_settings()
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
		online_ctl._open_lobby()
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
	if not keep_teams:
		show_ctl._maybe_intro()


## Modes that open the pick screen first.
func _has_pick(cfg: Dictionary) -> bool:
	return cfg.get("duel", false) or cfg.get("versus2p", false) or cfg.has("team") or cfg.get("brawl", false)


func _on_teams_chosen(teams: Array) -> void:
	_close_ui()
	hud.visible = true
	_teams = teams
	audio.play("ui_select", 0.0, 1.0, true)
	_start_round()
	show_ctl._maybe_intro()


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
		var end_tick := int(_round_end[0]) if _round_end.size() == 2 else sim.tick
		var end_share := float(_round_end[1]) if _round_end.size() == 2 else share
		var score := d.score_fight(won, end_share, end_tick)
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
			online_ctl._net_daily_submit(d)
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
		if arcade is Arcade:
			show_ctl._maybe_intro()  # a new opponent up the ladder (not each Gauntlet wave)
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
	team_battle = TeamSim.new(_teams, per_side, rules, seed_base)  # (the seed: the Crater shrine's draws; a replay keeps it as mut_seed)
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
	if not _forced_mutators.is_empty():
		muts = _forced_mutators.duplicate(true)
		_chaos_names = ", ".join(_forced_names)
	elif cfg.get("chaos", false):
		var table := _chaos_table()
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
			MatchSim.merge_mutator(muts, table[k])
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


## Chaos Cup's pool: every mutator, the hazards included whatever Arena options says (its
## On/Off rows govern the normal modes only; Kevin's ruling, Oct 2026).
func _chaos_table() -> Dictionary:
	return Daily.mutator_table()


func _brawl_flow() -> void:
	hud.timer_ticks = maxi(brawl.timer, 0)
	match brawl.phase:
		BrawlSim.Phase.INTRO:
			var t := brawl.phase_t
			hud.banner = ("CHAOS CUP" if _chaos_names != "" else "BRAWL") if t < 60 else "FIGHT!"
			var plain := "Free-for-all   ·   last one standing"
			if _hazard_line() != "":
				plain += "   ·   " + _hazard_line()
			hud.banner_sub = (_chaos_names if _chaos_names != "" else plain) if t < 60 else ""
			if t == 2 or t == 60:
				audio.play("round_start", 0.0, 0.75 if t == 2 else 1.0)
		BrawlSim.Phase.FIGHT:
			hud.banner = ""
			hud.banner_sub = ""
			_update_zone()  # the shrines
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
					hud.banner_sub = _draw_reason()
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
		var dir := DirAccess.open(replays_dir) if DirAccess.dir_exists_absolute(replays_dir) else null
		if dir != null:
			for f in dir.get_files():
				if f.ends_with(".json"):
					files.append(f)
		files.sort()
		files.reverse()
		if files.is_empty():
			s.add_text("No replays yet. Press F6 during a fight to save one.")
		for f in files.slice(0, 20):
			var path: String = replays_dir.path_join(String(f))
			s.add_button(_replay_label(path), func(): _play_replay(path), "Watch it")
		s.add_space(4)
		s.add_button("Back", s.back)
	ui.push(scr)


func _replay_label(path: String) -> String:
	var stamp := path.get_file().trim_prefix("replay_").trim_suffix(".json").replace("T", " ")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > Replay.MAX_FILE_BYTES:
		return stamp
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or not (d.get("setup") is Dictionary):
		return stamp
	var st: Dictionary = d["setup"]
	if ReplayBuilder.unsupported(st) == ReplayBuilder.DAMAGED:
		return stamp + "   (damaged)"
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
			fx.pads.append({"pos": team_battle.pad_point(side, k), "color": Accessibility.side_color(side), "side": side, "count": 0})


## King of the Crater: the zone on the floor, in the holder's colour. Also every mode's
## shrines (`_shrine_marks`) and Capture the Flag's flags.
func _update_zone() -> void:
	fx.flags = []
	fx.shrines = _shrine_marks()
	fx.wanted = _wanted_marks()
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
		"color": Accessibility.side_color(holder) if holder >= 0 else Accessibility.neutral_color()}


## Who is wanted, for FxView's marks over their heads: per slot {} or {"kind": "spree",
## "level"} (Team Deathmatch) / {"kind": "crown"} (a Brawl's crown holder).
func _wanted_marks() -> Array:
	var out: Array = []
	if sim == null:
		return out
	for i in sim.creatures.size():
		out.append(_wanted(i))
	return out


func _wanted(i: int) -> Dictionary:
	if team_battle != null and team_battle.sim == sim and team_battle.spree:
		var lv := team_battle.spree_level(i)
		if lv > 0:
			return {"kind": "spree", "level": lv}
	elif brawl != null and brawl.sim == sim and brawl.crown_on and brawl.crown == i:
		return {"kind": "crown"}
	return {}


## Team Deathmatch's spree and shutdown, and the Brawl crown: the toasts.
func _wanted_toast(e: Dictionary) -> void:
	var who := int(e.get("who", -1))
	var name := _fighter_word(who)
	match String(e["type"]):
		"spree":
			var lv := int(e.get("level", 1))
			hud.show_toast("%s IS ON A SPREE" % name if lv <= 1 else "%s: %d KOs IN A ROW" % [name, int(e.get("kos", 0))])
		"shutdown":
			hud.show_toast("SHUTDOWN! +%d  ·  %s STOPS %s" % [int(e.get("bonus", 0)), name, _fighter_word(int(e.get("victim", -1)))])
		"crown":
			if who < 0:
				hud.show_toast("THE CROWN IS LOOSE  ·  NEXT KO TAKES IT")
			elif int(e.get("from", -1)) >= 0:
				hud.show_toast("%s TAKES THE CROWN FROM %s" % [name, _fighter_word(int(e.get("from", -1)))])
			else:
				hud.show_toast("%s TAKES THE CROWN" % name)


## A fighter's name in capitals for a toast ("?" for no one).
func _fighter_word(slot: int) -> String:
	if slot < 0 or sim == null or slot >= sim.creatures.size():
		return "?"
	return String(sim.creatures[slot].def.get("name", "?")).to_upper()


## The match's shrines for FxView (any mode with them): where, what, who is claiming it
## and in what colour (a side's, or a Brawl fighter's), how far, the seconds until it's
## ready and, in the last `announce_seconds`, how far it has charged (0..1).
func _shrine_marks() -> Array:
	var out: Array = []
	if sim == null or sim.shrines.is_empty():
		return out
	var soon := float(Shrines.ticks_of(sim.shrine_rules.get("announce_seconds", 10)))
	for i in sim.shrines.size():
		var st: Array = sim.shrines[i]
		var team := int(st[0])
		var rest := int(st[2])
		out.append({"pos": Shrines.pos(sim, i), "radius": Shrines.radius(sim, i), "kind": Shrines.kind(sim, i),
			"side": team, "claim_color": _team_color(team),
			"claim": float(st[1]) / maxf(1.0, float(Shrines.claim_ticks(sim))), "rest": ceili(rest / 60.0),
			"charge": clampf(1.0 - float(rest) / soon, 0.0, 1.0) if rest > 0 and soon > 0.0 and rest <= int(soon) else 0.0})
	return out


## A team's colour: a Brawl fighter's own, else its side's.
func _team_color(team: int) -> Color:
	if team < 0:
		return Color.WHITE
	if brawl != null and brawl.sim == sim:
		return Accessibility.brawl_color(team)
	return Accessibility.side_color(clampi(team, 0, 1))


## A team's name for a toast: RED / BLUE, or a Brawl fighter's name.
func _team_word(team: int) -> String:
	if brawl != null and brawl.sim == sim and team >= 0 and team < sim.creatures.size():
		return String(sim.creatures[team].def.get("name", "?")).to_upper()
	return ["RED", "BLUE"][clampi(team, 0, 1)]


## Every mode's shrine toasts: the announcement, ready, a claim, and the Crater's permanent
## buff (who got which, or that a fighter at the cap only denied it).
func _shrine_toast(e: Dictionary) -> void:
	var kind := String(e.get("kind", "")).to_upper()
	if kind == "BOOST":
		kind = "POWER"
	match String(e["type"]):
		"shrine_soon": hud.show_toast("SHRINE IN %d  ·  %s" % [ceili(int(e.get("ticks", 600)) / 60.0), kind])
		"shrine_ready": hud.show_toast("THE %s SHRINE IS READY" % kind)
		"shrine":
			if kind != "POWER":  # (a permanent-buff claim names the buff instead: shrine_boost)
				hud.show_toast("%s CLAIMS THE %s SHRINE" % [_team_word(int(e.get("team", 0))), kind])
		"shrine_boost":
			var who := int(e.get("who", -1))
			var name := String(sim.creatures[who].def.get("name", "?")).to_upper() if who >= 0 and who < sim.creatures.size() else "?"
			if bool(e.get("capped", false)):
				hud.show_toast("%s HAS %d BUFFS: SHRINE DENIED" % [name, int(e.get("count", 0))])
			else:
				hud.show_toast("%s  %s" % [name, String(e.get("text", ""))])


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
			elif team_battle.ctf:
				what = "CAPTURE THE FLAG"
			_update_zone()  # flags, the caravan and shrines show from the start
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
			if _hazard_line() != "":
				sub += "   ·   " + _hazard_line()
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
						"flag_land", "bridge_fall", "bridge_strain", "bridge_up"]:
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
				hud.banner_sub = _draw_reason() if w < 0 else _over_reason()


## An arena hazard is coming (a mutator's, Hazards): the wave's banner names the edge it
## comes from and what to do; a meteor shower, a boulder and a fault line get a toast.
func _hazard_warn(e: Dictionary) -> void:
	match String(e.get("shape", "")):
		"wave":
			var side := int(e.get("side", 0))
			hud.moment("TIDAL WAVE!", "FROM THE %s  -  GET BEHIND THE RUBBLE" % String(Hazards.SIDE_NAMES[clampi(side, 0, 3)]).to_upper(),
				Color("6fb8f0"))
		"boulder":
			hud.show_toast("BOULDERS!  STEP ASIDE OR HEAVY ONE BACK")
		"fault":
			hud.show_toast("FAULT LINE!  GET OFF THE CRACK BEFORE IT SPLITS")
		_:
			hud.show_toast("METEOR SHOWER!  STAY OUT OF THE SHADOWS")


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
				hud.alert(Accessibility.side_color(side))
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
			hud.moment("%s CAPTURES!" % whose, "%d  -  %d" % [int(sc[0]), int(sc[1])], Accessibility.side_color(side))
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
			int(row["stops"])], Accessibility.side_color(c.team)])
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
				hud.banner_sub = _draw_reason() if duel.winner < 0 else _over_reason()


## How the last fight ended (the sim's `by`: ko, time, score, hold, capture, caravan),
## as the line under the winner on the final banner.
var _over_by := ""
## What knocked out the last fighter to go down: "" (a fighter's hit, a fall) or an arena
## hazard's shape ("meteors", "wave"), so a draw can say so (`_draw_reason`).
var _ko_by_hazard := ""
var _hazard_hit_now := {}  ## who an arena hazard last struck (slot -> [tick, its shape])
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


## Why a match ended with nobody winning, for the line under "DRAW" (a draw must always
## say why): level at time (on health, or on the mode's score), or everyone down at once,
## which an arena hazard can do (the last ones caught by one meteor: `_ko_by_hazard`).
func _draw_reason() -> String:
	match _over_by:
		"ko":
			if _ko_by_hazard == "meteors":
				return "Double K.O.  -  a meteor took the last ones down"
			if _ko_by_hazard == "wave":
				return "Double K.O.  -  the wave took the last ones down"
			if _ko_by_hazard == "boulder":
				return "Double K.O.  -  the boulder took the last ones down"
			return "Double K.O.  -  nobody left standing"
		"time":
			var r := _over_reason()
			if r == "" or r.ends_with("more health left"):
				return "Time: level on health"
			return r.replace("Time: ", "Time, level: ")
	var other := _over_reason()
	return other if other != "" else "Nobody won"


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
	_hazard_hit_now.clear()  # (event ticks start again with a new sim)
	sim = s
	hud.banner_hidden = false
	if not _menu_bg and round_num <= 1:
		stats.reset()
	_cam_zoom = 0.0  # frame the new fight straight away
	_cam_lead = Vector2.ZERO
	_cam_prev = []
	_cam_push = 0.0
	_exchange_t = 0
	_exchange_hits = 0
	_cam_aim = Vector2.ZERO
	_cam_aim_dir = Vector2.ZERO
	_cam_off = Vector2.ZERO
	_cam_zclash = 1.0
	_clash = 0.0
	_clash_want = 0.0
	_clash_hold = 0
	_cam_idle = 0
	_settle_fit = 0.0
	_surge_bars = 0
	show_ctl._drop_intro()
	if letterbox != null:
		letterbox.clear()
	sides = p_sides.duplicate()
	while sides.size() < sim.creatures.size():
		sides.append(Side.CPU)  # a team battle's other slots
	if _cpu_vs_cpu:
		for i in sides.size():
			if sides[i] in LOCAL_SIDES:
				sides[i] = Side.CPU
	var session := _session_mutators(s)
	if not session.is_empty():
		s.apply_mutators(session, seed_base)  # --mutators, or Arena options > Hazards
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
	crowd.set_size(sim.arena_size(), two_sides, CrowdView.toasts_for(sim.arena))
	backdrop.set_map(arena.arena_id, sim.arena_size())
	fore.set_map(arena.arena_id, sim.arena_size())
	furniture.hud = hud
	furniture.set_arena(sim.arena, sim.arena_size())
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
	water.set_sim(sim, arena.water_bank(), ArtScale.TILE_CELLS)  # after arena.set_terrain: the bank is the tiles'
	wear.set_sim(sim)
	water.fx = fx
	ambient.set_sim(sim, arena.art())
	ambient.fx = fx
	glade.fx = fx
	glade.set_sim(sim, arena.canopy_rects())
	glade.hud_rects = _hud_corners()
	var look := _match_look(s)
	_lit_look = look.duplicate()
	_light_look()
	weather.apply(sim, look, shadows, ambient, water)
	light2d.apply(sim, look, shadows.light.get("cast", Vector2.DOWN))
	furniture.set_lit(light2d.lamp_heads())  # the lamp heads of lit lamps glow (after set_arena)
	grade.apply(sim.arena, weather.grade_scale())
	replay.setup["look"] = look.duplicate()  # cosmetic: the replay looks the same
	paper.set_sim(sim)
	hud.sim = sim
	fx.sim = sim
	fx.clear()
	plants.sim = sim
	plants.fx = fx
	plants.clear()
	fx.views = views
	bloom.views = views
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
		var mark_col: Color = Accessibility.brawl_color(i) if brawl != null and brawl.sim == s \
			else Accessibility.side_color(clampi(sim.creatures[i].team, 0, 1))
		fx.side_marks.append({"color": mark_col, "label": label, "rel": _relation(i),
			"brawl": i if brawl != null and brawl.sim == s else -1, "team": sim.creatures[i].team})

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
	if bloom != null:
		bloom.frame(get_viewport())
	if netplay != null and netplay.link != null and netplay.link.realtime:
		netplay.pump()
	voice_ctl._voice_step(_delta)
	_think_in_gap()
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
	_ticks_run += 1
	show_ctl._wipe_step()
	touch_ctl._touch_step()
	if paused:
		_capture()
		return  # frozen behind the pause menu: nothing steps, the picture holds
	if intro != null:
		show_ctl._intro_step()
		perf_overlay.tick(Time.get_ticks_usec() - tick_start)
		_capture()
		return  # the arena intro: the sim waits at its first tick, the views play it
	flow_t += 1
	if _finder != null:
		online_ctl._finder_step()
	if _daily_client != null:
		online_ctl._daily_step()
	var live := flow == Flow.FIGHT or flow == Flow.MENU
	var offline := false
	var events: Array = sim.events
	if online != null:
		# Online: the rollback session steps the duel (maybe several frames, maybe none
		# while it waits); the views get only the events they haven't shown yet.
		live = flow == Flow.FIGHT or flow == Flow.MATCH_OVER
		netplay.tick(_side_bits(online.local_slot, live and not ui.is_open()))
		events = online.events
		online_ctl._online_status()
	elif watch != null:
		# Watching: the referee's copy steps on confirmed inputs only (maybe several
		# frames a tick, maybe none); its events are the ones to show.
		live = flow == Flow.FIGHT or flow == Flow.MATCH_OVER
		netplay.tick(0)
		if netplay.watch != null and netplay.watch != watch and netplay.phase == Netplay.Phase.PLAYING:
			online_ctl._start_watching()  # the next match (a rematch, or the room's next): follow it
		events = watch.events
		if netplay.phase == Netplay.Phase.ENDED and flow == Flow.FIGHT:
			flow = Flow.MATCH_OVER
			flow_t = 0
			hud.banner = "THE MATCH ENDED"
			hud.banner_sub = netplay.status
		online_ctl._watch_room_status()
	elif netplay != null and online_ctl._connecting_step():
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
	var t_v := t_fx
	arena.refresh()
	PerfLog.since("adv arena", t_v)
	t_v = PerfLog.now()
	water.advance()
	PerfLog.since("adv water", t_v)
	t_v = PerfLog.now()
	ambient.advance()
	glade.advance()
	PerfLog.since("adv ambient", t_v)
	t_v = PerfLog.now()
	weather.advance()
	PerfLog.since("adv weather", t_v)
	t_v = PerfLog.now()
	wear.advance()
	PerfLog.since("adv wear", t_v)
	t_v = PerfLog.now()
	crowd.advance()
	PerfLog.since("adv crowd", t_v)
	t_v = PerfLog.now()
	fx.advance()
	plants.advance()
	PerfLog.since("adv fx", t_v)
	PerfLog.since("fx advance", t_fx)
	light2d.advance()  # after the effects: it reads their particles
	if glow:
		if light2d.tier == Light2DView.Tier.OFF:
			glow_floor.advance()  # Lighting Off: Glow gathers its own, as before
		else:
			glow_floor.show_lights(light2d.gathered, light2d.pools)  # the pools the real lights left
		glow_halo.queue_redraw()
	bloom.advance()
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
		views[i].outline_color = fx.mark_color(i)
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
	cam_ctl._update_camera()
	cam_ctl._update_letterbox()
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
				_menu_background(_attract)
			show_ctl._attract_step()
		Flow.INTRO:
			if arcade != null:
				hud.banner = arcade.stage_label() if flow_t < 60 else "FIGHT!"
				hud.banner_sub = arcade.versus_label() if flow_t < 60 else ""
			else:
				hud.banner = "ROUND %d" % round_num if flow_t < 60 else "FIGHT!"
				hud.banner_sub = _hazard_line() if flow_t < 60 else ""
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
				show_ctl._show_match_over()
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
	# The Daily scores the round as it ends (the server's Daily.Verify stops here too).
	_round_end = [sim.tick, clampf(sim.creatures[0].hp / sim.creatures[0].max_hp, 0.0, 1.0)]
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
	_cpu_gap = []
	_join_cpus()
	if not live:
		return
	if ahead.size() == 2 and ahead[0] == sim and ahead[1] == sim.tick:
		var list := _cpu_list()
		if _gap_done > 0 and _gap_done < list.size():  # the gap's budget ran out: the rest now
			var t0 := PerfLog.now()
			for k in range(_gap_done, list.size()):
				(list[k] as CpuController).bits(sim)
			PerfLog.since("cpus after gap", t0)
		_gap_done = 0
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
	if _gap_thinking():
		_cpu_gap = [sim, sim.tick]  # _think_in_gap, in the next frame without a tick
		_gap_physics_frame = Engine.get_physics_frames()
		_gap_process_frame = Engine.get_process_frames()  # this frame steps the tick: not here
		return
	_gap_done = 0
	_cpu_ahead = [sim, sim.tick]
	_cpu_task = CpuController.think_start(list, sim)


## Gap thinking needs a frame between ticks: a fight cap of at least twice the tick rate.
func _gap_thinking() -> bool:
	if cpu_think != "gap":
		return false
	var cap := Engine.max_fps
	return cap == 0 or cap >= 2 * Engine.physics_ticks_per_second


## Every frame (_process): in gap mode, a frame that stepped no tick since the last one
## works out the next tick's CPU inputs here, one CPU after another on this thread. The
## tick takes them only if it steps that same match from that same tick (_think_cpus);
## if no such frame came first, the tick thinks for itself, as before.
func _think_in_gap() -> void:
	if _cpu_gap.is_empty() or Engine.get_physics_frames() != _gap_physics_frame \
			or Engine.get_process_frames() == _gap_process_frame:
		return
	var ahead := _cpu_gap
	_cpu_gap = []
	if ahead[0] != sim or ahead[1] != sim.tick:
		return
	var t0 := PerfLog.now()
	var start := Time.get_ticks_usec()
	var list := _cpu_list()
	CpuController.prepare(sim)
	_gap_done = 0
	for c in list:
		(c as CpuController).bits(sim)
		_gap_done += 1
		if Time.get_ticks_usec() - start >= gap_budget_us:
			break
	PerfLog.since("cpus in gap", t0)
	_cpu_ahead = ahead


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
## walls; a foe in stealth, Tiptoe, is fully invisible to them), after noting this tick's
## hits. Views and the camera skip them.
func _update_vision(events: Array) -> void:
	vision.observe(events)
	var team := _viewer_team()
	_hidden.resize(sim.creatures.size())
	for i in sim.creatures.size():
		var c: CreatureSim = sim.creatures[i]
		_hidden[i] = team >= 0 and ((c.stealth > 0 and c.team != team) or not vision.team_sees(sim, team, c))
	fx.unseen = _hidden
	fx.viewer_team = team
	arena.canopy_points = ArenaView.canopy_watchers(sim, _hidden, team)


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
	if flow != Flow.MENU:
		stats.note(e)
		if String(e["type"]) in ["shrine_soon", "shrine_ready", "shrine", "shrine_boost"]:
			_shrine_toast(e)
		elif String(e["type"]) in ["spree", "shutdown", "crown"]:
			_wanted_toast(e)
	fx.spawn(e)
	light2d.on_event(e)  # a big hit's or a Surge's flash of light (Lighting Low / High)
	audio.on_event(e)
	var power: float = e["power"]
	_rumble(e)
	match String(e["type"]):
		"hit":
			shake = maxf(shake, 1.5 + power * 0.2)
			crowd.cheer(0.1 + power * 0.015)
			if fx._event_shown(e):  # (fans near a hidden fighter's hit would give it away)
				crowd.react(Vector2(e["pos"]), 4 + mini(4, int(power * 0.25)))
				cam_ctl._note_exchange()
				var kind := cam_ctl._hit_kind(e)
				if kind == "heavy" or kind == "surge":
					cam_ctl._note_clash(Vector2(e["pos"]), 1.0 if kind == "surge" else CLASH_HEAVY)
		"block":
			shake = maxf(shake, 1.0)
			cam_ctl._note_exchange()
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
			if String(e["type"]) == "guard_break" and fx._event_shown(e):
				cam_ctl._note_clash(Vector2(e["pos"]), 1.0)
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
		"spree":
			crowd.cheer(0.4)
		"shutdown", "crown":
			crowd.cheer(0.8)
			audio.play("round_start", -4.0, 1.3)
		"respawn":
			audio.play("warp", -4.0, 0.9)  # back on the pad
		"overtime":
			audio.play("round_start")
			crowd.cheer(0.6)
		"checkpoint", "caravan_done":
			audio.play("round_start", -3.0, 1.2)
			crowd.cheer(0.7)
		"hazard_warn":
			_hazard_warn(e)
		"hazard_hit":
			_hazard_hit_now[int(e.get("who", -1))] = [int(e.get("tick", 0)), String(e.get("shape", ""))]
		"hazard_strike":
			if String(e.get("shape", "")) == "wave":
				shake = maxf(shake, 4.0)
				crowd.roar(50)
			else:
				shake = maxf(shake, 3.0 if bool(e.get("big", false)) else 1.5)
				crowd.cheer(0.15)
		"hazard_reverse":
			shake = maxf(shake, 3.0)
			crowd.roar(40)  # someone hit a boulder back
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
		"shrine_soon":
			audio.play("chill", -9.0, 0.8)
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
			var hz: Array = _hazard_hit_now.get(int(e.get("who", -1)), [])
			_ko_by_hazard = String(hz[1]) if not hz.is_empty() and int(hz[0]) == int(e.get("tick", -1)) else ""
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


## In main_camera.gd (tests and other scripts call it here).
func _update_camera() -> void:
	cam_ctl._update_camera()


## In main_camera.gd (tests and other scripts call it here).
static func snap_cam(pos: Vector2, px: float) -> Vector2:
	return MainCamera.snap_cam(pos, px)


## In main_camera.gd (tests and other scripts call it here).
static func ko_push(t: int) -> float:
	return MainCamera.ko_push(t)


## In main_camera.gd (tests and other scripts call it here).
func _update_letterbox() -> void:
	cam_ctl._update_letterbox()


# ------------------------------------------------------------------ arena intro

## Big maps: arrows at the screen's edge toward objectives out of shot (the caravan, the
## flags). Screen = (world - camera) x zoom + half the screen.
func _update_pointers(view: Vector2) -> void:
	var out: Array = []
	var playing := sim != null and showcase == null
	if playing and ((team_battle != null and team_battle.sim == sim) or (brawl != null and brawl.sim == sim)):
		var targets := _wanted_pointers()
		if team_battle != null and team_battle.caravan:
			targets.append([team_battle.caravan_pos(), Accessibility.side_color(team_battle.cv_attacker()), "CARAVAN"])
		if team_battle != null and team_battle.ctf:
			for side in 2:
				var word: String = ["FLAG", "TAKEN", "DROPPED", "LOOSE"][clampi(int(team_battle.flag_state[side]), 0, 3)]
				targets.append([team_battle.flag_pos[side], Accessibility.side_color(side), word])
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


## The wanted fighters' off-screen arrows: a Team Deathmatch spree for the other team (both
## teams' when nobody here plays), a Brawl's crown holder for everyone but its wearer. Never
## one the local team can't see (brush, stealth): the arrow would give it away.
func _wanted_pointers() -> Array:
	var out: Array = []
	var mine := _viewer_team()
	for i in sim.creatures.size():
		var w := _wanted(i)
		var c := sim.creatures[i]
		if w.is_empty() or c.state == CreatureSim.State.KO or _is_hidden(i) or (mine >= 0 and c.team == mine):
			continue
		if String(w["kind"]) == "crown":
			out.append([c.pos, Color("ffd84a"), "CROWN"])
		else:
			out.append([c.pos, Color("ff7a3a"), "SPREE"])
	return out


## In main_camera.gd (tests and other scripts call it here).
func _frame_fight(view: Vector2, size: Vector2) -> void:
	cam_ctl._frame_fight(view, size)


## In main_camera.gd (tests and other scripts call it here).
static func clash_zoom(amt: float, push: float, exchange: float, cap: float) -> float:
	return MainCamera.clash_zoom(amt, push, exchange, cap)


## In main_camera.gd (tests and other scripts call it here).
func _note_clash(pos: Vector2, amt: float) -> void:
	cam_ctl._note_clash(pos, amt)


## In main_camera.gd (tests and other scripts call it here).
static func cam_level_arg(v: String) -> int:
	return MainCamera.cam_level_arg(v)


## In main_camera.gd (tests and other scripts call it here).
func cam_level(key: String) -> int:
	return cam_ctl.cam_level(key)


## In main_camera.gd (tests and other scripts call it here).
func _aim_fighters(anchor: int) -> Array:
	return cam_ctl._aim_fighters(anchor)


## In main_camera.gd (tests and other scripts call it here).
func _note_exchange() -> void:
	cam_ctl._note_exchange()


## In main_camera.gd (tests and other scripts call it here).
static func _lead_room(lead: Vector2, follow: Vector2, tight: Rect2, half: Vector2) -> Vector2:
	return MainCamera._lead_room(lead, follow, tight, half)


## In main_camera.gd (tests and other scripts call it here).
static func _cam_axis(v: float, half: float, arena: float, lo := 0.0, hi := 0.0) -> float:
	return MainCamera._cam_axis(v, half, arena, lo, hi)


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if show_ctl._attract_pressed(event):
		show_ctl._end_attract()
		get_viewport().set_input_as_handled()  # the press only wakes the title
		return
	if not (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative == Vector2.ZERO):
		_idle_t = 0
	if wipe != null and wipe.active() and MainPresentation._skips_intro(event):
		wipe.finish()  # (the press still does what it does)
	if intro != null and MainPresentation._skips_intro(event):
		show_ctl._end_intro()
		get_viewport().set_input_as_handled()  # the press only skips (Esc doesn't also pause)
		return
	var touch := event is InputEventScreenTouch or event is InputEventScreenDrag
	if not (event is InputEventMouseMotion) and not touch:
		_join_cpus()  # a press may change the match (a reset, a swap) while the CPUs read it
	touch_ctl._note_input(event)


## In main_touch.gd (tests and other scripts call it here).
func _note_input(event: InputEvent) -> void:
	touch_ctl._note_input(event)


## In main_touch.gd (tests and other scripts call it here).
func _apply_touch() -> void:
	touch_ctl._apply_touch()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute_music"):  # (typing in a text box never gets here)
		var muted := audio.toggle_music()
		_toast("Music off (M to turn on)" if muted else "Music on")
		settings_ctl._save_settings()
		if _setting_rows.has("vol_Music"):
			var now := settings_ctl._setting("vol_Music")
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
		settings_ctl._set_setting("perf_overlay", (perf_overlay.mode + 1) % PerfOverlay.MODE_NAMES.size())
		_toast("Performance overlay: " + PerfOverlay.MODE_NAMES[perf_overlay.mode])
	elif _range_rings_pressed(event):
		settings_ctl._set_setting("range_rings", 0 if range_rings else 1)
		_toast("Range rings " + ("on" if range_rings else "off"))
	elif event.is_action_pressed("debug_dummy_mode") and coach is ComboTrials:
		coach.replay_demo()
	elif event.is_action_pressed("reset") and coach is ComboTrials:
		coach.skip(1)
	elif _change_fighter_pressed(event) and in_training():
		_open_fighter_swap()
	elif event.is_action_pressed("debug_dummy_mode"):
		settings_ctl._set_setting("dummy_mode", (dummy_mode + 1) % DUMMY_MODES.size())
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
	var path := replays_dir.path_join("replay_%s.json" % stamp)
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
## it can't (`_open_online_pause`).
func _open_pause() -> void:
	if online != null or watch != null:  # a spectated room keeps going too
		voice_ctl._open_online_pause()
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
		settings_ctl._add_setting_row(s, "no_cooldowns")
		settings_ctl._add_setting_row(s, "full_energy")
		settings_ctl._add_setting_row(s, "dummy_mode")
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


## In main_settings.gd (tests and other scripts call it here).
func _setting(key: String) -> Dictionary:
	return settings_ctl._setting(key)


## In main_settings.gd (tests and other scripts call it here).
func _set_setting(key: String, i: int) -> void:
	settings_ctl._set_setting(key, i)


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


## The engine's frame cap for a fight cap of `cap` fps on a screen of `refresh` Hz. With
## `pacing` "vsync" (the default on mobile, --fps-pacing), vsync on and a cap at or over
## the screen's rate: no cap (0), vsync paces each frame. The Odin 3's panel runs at
## 121.7 Hz: a limiter at 120 fell 1.7 frames a second short, each one a frame shown twice
## (Vulkan, Oct 2026; GL's deeper queue hid it). PC keeps the limiter.
static func pace_cap(cap: int, refresh: float, vsync_on: bool, pacing := "cap") -> int:
	if pacing == "vsync" and vsync_on and refresh > 0.0 and cap >= roundi(refresh) - 1:
		return 0
	return cap


## The screen's refresh rate, read once (and again when the window changes size or screen).
func _refresh_rate() -> float:
	if _refresh < 0.0:
		_refresh = DisplayServer.screen_get_refresh_rate() if DisplayServer.get_name() != "headless" else 0.0
	return _refresh


func _apply_frame_rate() -> void:
	var menus := in_menus()
	# The character select reads each player's stick itself (two cursors).
	menu_stick.enabled = (menus or ui.is_open()) and not (ui.top() is CharacterSelect)
	if _fps_caps:
		var cap := MENU_FPS if menus else pace_cap(_fight_fps_cli if _fight_fps_cli > 0 else fight_fps,
			_refresh_rate(), vsync, _fps_pacing)
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
## per grid pixel (a 2x sheet's art pixel; base.x / VIEW_W = ArtScale.PX_PER_UNIT of them a
## canvas unit) once the window has two or more of them, so 2x art never draws uneven; below
## that (1440 x 810: 1.5 a grid pixel) whole screen pixels per canvas unit, as the older 1x
## sheets want, so a window that can't fit two keeps its size. At least 1. 0 for a size or
## base of nothing.
static func pixel_scale_factor(size: Vector2, base: Vector2) -> float:
	if base.x <= 0.0 or base.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return 0.0
	var grid := minf(size.x / base.x, size.y / base.y)  # screen px per grid px, unsnapped
	var per_unit := base.x / SimDefs.VIEW_W  # grid px per canvas unit (2)
	var grid_px := floorf(grid + 0.001)
	var unit_px := grid_px * per_unit if grid_px >= 2.0 else maxf(1.0, floorf(grid * per_unit + 0.001))
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


# ------------------------------------------------------------------ voice chat

## In main_voice.gd (tests and other scripts call it here).
func voice_mode_now() -> int:
	return voice_ctl.voice_mode_now()


## In main_voice.gd (tests and other scripts call it here).
func _voice_arg(a: String) -> void:
	voice_ctl._voice_arg(a)


## In main_voice.gd (tests and other scripts call it here).
func _apply_voice() -> void:
	voice_ctl._apply_voice()


## In main_voice.gd (tests and other scripts call it here).
func _apply_voice_hear() -> void:
	voice_ctl._apply_voice_hear()


## In main_voice.gd (tests and other scripts call it here).
func voice_rows() -> Array:
	return voice_ctl.voice_rows()


## In main_voice.gd (tests and other scripts call it here).
func mic_choices() -> Array:
	return voice_ctl.mic_choices()


## In main_voice.gd (tests and other scripts call it here).
func _apply_mic() -> void:
	voice_ctl._apply_mic()


## In main_voice.gd (tests and other scripts call it here).
func _voice_step(delta: float) -> void:
	voice_ctl._voice_step(delta)


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


## The Lighting tier in force: `--lighting=` this session, else the setting.
func lighting_tier() -> int:
	return _lighting_cli if _lighting_cli >= 0 else lighting


## Tells the lights, the bloom and the weather the tier (before WeatherView.apply: the night's
## lamps replace its baked pools in High; the sun dims the fighters' shade side).
func _light_look() -> void:
	var t := lighting_tier()
	light2d.tier = t
	bloom.set_on(t == Light2DView.Tier.HIGH)
	CreatureView.emissive_on = t != Light2DView.Tier.OFF
	CreatureView.set_lit_sheets(t != Light2DView.Tier.OFF)  # Off: no normal or emissive sheets loaded
	_apply_glow()  # High: the bloom stands in for Glow's halos
	var time := String(_lit_look.get("time", "day"))
	weather.lamp_lights = sim != null and t == Light2DView.Tier.HIGH and Light2DView.lamps_on(sim.arena, time)
	var sd := Light2DView.sun_at(sim.arena if sim != null else {}, time, String(_lit_look.get("weather", "clear")), t)
	weather.fighter_scale = float(sd.get("shade", 1.0))
	if glade != null:
		glade.set_look(time, t)


## The HUD's corners and bottom line in screen px (the fighter plates top left and right,
## the score at the top middle, the key help along the bottom): GladeView spawns nothing
## under them.
func _hud_corners() -> Array:
	var v := get_viewport_rect().size
	return [Rect2(0, 0, v.x * 0.35, v.y * 0.29), Rect2(v.x * 0.75, 0, v.x * 0.25, v.y * 0.2),
		Rect2(v.x * 0.38, 0, v.x * 0.24, v.y * 0.13), Rect2(0, v.y * 0.95, v.x, v.y * 0.05)]


## Lighting changed (Settings > Video): re-apply this match's look with the new tier.
func _apply_lighting() -> void:
	if light2d == null:
		return
	_light_look()
	if sim != null and not _lit_look.is_empty():
		weather.apply(sim, _lit_look, shadows, ambient, water)
		grade.apply(sim.arena, weather.grade_scale())
		light2d.apply(sim, _lit_look, shadows.light.get("cast", Vector2.DOWN))
		furniture.set_lit(light2d.lamp_heads())


## Glow on or off: off hides both layers and stops gathering lights (no cost at all). With
## Lighting High the halos stay hidden: the bloom draws the same lights' glow.
func _apply_glow() -> void:
	for g in [glow_floor, glow_halo]:
		if g != null:
			g.visible = glow
			if not glow:
				g.clear()
	if glow_halo != null and light2d != null and lighting_tier() == Light2DView.Tier.HIGH:
		glow_halo.visible = false


## In main_settings.gd (tests and other scripts call it here).
func _save_settings() -> void:
	settings_ctl._save_settings()


# ------------------------------------------------------------------ online

## Each frame while looking: once it's done, join the server it found nearby, or the
## public address.
## The server's public name gets no answer, and it didn't answer on this network either.
## At the server's house that's usually the server's own setup; anywhere else, the
## server is down or its port isn't forwarded.
const HOME_HINT := "No answer. At the server's house: update it and allow UDP 7778. Away: is UDP 7777 forwarded?"


## In main_online.gd (tests and other scripts call it here).
func _leave_online() -> void:
	online_ctl._leave_online()


## In main_online.gd (tests and other scripts call it here).
func _leave_to_lobby() -> void:
	online_ctl._leave_to_lobby()


# ------------------------------------------------------------------ online rooms
# A room on the server lasts between matches: after one, Next match opens the room's
# page with the fighter select over it; everyone locks in, and the server starts the
# next match (the session stays up throughout). See RelayServer's Room.

## In main_online.gd (tests and other scripts call it here).
func _room_code() -> String:
	return online_ctl._room_code()


## In main_online.gd (tests and other scripts call it here).
func _room_next() -> void:
	online_ctl._room_next()


## In main_presentation.gd (tests and other scripts call it here).
func results_data() -> Dictionary:
	return show_ctl.results_data()


## In main_online.gd (tests and other scripts call it here).
func _write_net_report(keep := false) -> void:
	online_ctl._write_net_report(keep)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_print_perf()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android's Back (gesture or key): the same as Esc, so it never closes the game.
		var ev := InputEventAction.new()
		ev.action = "pause"
		ev.pressed = true
		Input.parse_input_event(ev)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if player_input != null:
			player_input.touch.release_all()  # a lost touch: no finger stays down
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		player_input.touch.release_all()
		_print_perf(true)
		# Switched away on a phone: an offline fight waits under the pause menu.
		if online == null and showcase == null and not paused and not ui.is_open() \
				and not (flow in [Flow.MENU, Flow.SELECT, Flow.LOBBY, Flow.MATCH_OVER]):
			_open_pause()
	elif what == NOTIFICATION_PREDELETE:
		_join_cpus()


## Prints the --perf report and saves it as user://perf.txt (a player's build has no
## console to print to). `keep`: the app went to the background (a player's session on a
## phone ends there, not with a quit): report what was logged so far and carry on logging.
func _print_perf(keep := false) -> void:
	if _perf != null:
		var text := "PERF setup: vsync %s, fight cap %d (setting %d, --fight-fps %d), engine cap %d, pacing %s, cpu think %s, screen %.2f Hz, %s\n" % [
			"on" if vsync else "off", _fight_fps_cli if _fight_fps_cli > 0 else fight_fps, fight_fps, _fight_fps_cli,
			Engine.max_fps, _fps_pacing, cpu_think, _refresh_rate(), RenderingServer.get_current_rendering_method()]
		text += _perf.report(Engine.max_fps if Engine.max_fps > 0 else maxi(60, roundi(_refresh_rate())))
		for line in text.split("\n"):
			print(line)  # a line at a time: Android's log cuts one long message short
		var f := FileAccess.open("user://perf.txt", FileAccess.WRITE)
		if f != null:
			f.store_string(text + "\n")
			f.close()
		if not keep:
			_perf = null


func _capture() -> void:
	var t := frame_count
	if _shots.has(t):
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		get_viewport().get_texture().get_image().save_png(_shot_dir.path_join("shot_%04d.png" % t))
	if _print_vram_at > 0 and t == _print_vram_at:
		print("VRAM frame %d, lighting %s: textures %.1f MB, video %.1f MB; %s" % [t,
			["off", "low", "high"][lighting_tier()],
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			CreatureView.sheet_report()])
	if _quit_after > 0 and t >= _quit_after:
		online_ctl._write_net_report()
		_print_perf()
		get_tree().quit()
