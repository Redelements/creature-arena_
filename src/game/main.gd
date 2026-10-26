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
##   --menu=PAGE           open a menu page: main, single, single:<group>, look (Time and weather), settings, game, video, audio, controls,
##                         remap:classic|league|gamepad (captures)
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
var frame_count := 0
var _shots := {}
var _shot_dir := "user://shots"
var _cam_force := Vector3.ZERO  ## --cam=x,y,zoom: the camera held here (screenshots)
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
	if _run_sim_check() or _run_server():
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
	shadows = ShadowLayer.new()  # the fighters' shadows, on the floor under everyone
	shadows.views = views
	add_child(shadows)
	add_child(weather.ground)  # fog bands, rain splashes: over the shadows, under the fighters
	glow_floor = LightView.new()  # light pools on the floor, over the shadows, under the fighters
	add_child(glow_floor)
	light_floor = Light2DView.FloorGlow.new()  # the fight's real lights on the floor (Lighting), at the pools' depth
	add_child(light_floor)
	rings = RangeRings.new()
	rings.visible = false
	rings.fx = fx  # what the local team can see (Vision): no rings for a hidden foe
	add_child(rings)  # on the floor, under the fighters
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
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

	_load_settings()
	if UiTheme.smooth:
		ui.restyle()  # the menu theme was built before the saved Text font was read
	var start_mode := _parse_args()
	_cli_start = start_mode >= 0
	_apply_device()
	_apply_discord()
	_apply_range_rings()
	_apply_touch()
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
	_stop_attract()
	hud.banner_hidden = false
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
		"look":  # the Time and Weather page, for captures
			_open_single()
			_open_look_page()
		"settings":
			_open_settings()
		"game", "video", "audio":
			_open_settings()
			_open_settings_page(page)
		"controls":
			_open_settings()
			_open_controls()
		"touch":
			_open_settings()
			_open_controls()
			_open_settings_page("touch")
		"remap:classic", "remap:league", "remap:gamepad":  # captures of a Remap page
			_open_settings()
			_open_controls()
			_open_remap(page.get_slice(":", 1))


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

## What kind of screen `f` is, for the wipes: 0 menus, 1 a fight, 2 the match over.
static func _screen_kind(f: Flow) -> int:
	if f == Flow.MENU or f == Flow.SELECT or f == Flow.LOBBY:
		return 0
	return 2 if f == Flow.MATCH_OVER else 1


## Each tick: a wipe steps (and ends under a pause), and a change between menus, a fight
## and back starts one. Into the match-over screen there is none: the results screen has
## its own when it comes up. Never in the first half second, so captures keep their frames.
func _wipe_step() -> void:
	if wipe == null:
		return
	if paused:
		wipe.finish()
	else:
		wipe.advance()
	var kind := _screen_kind(flow)
	if _wipe_cat >= 0 and kind != _wipe_cat and kind != 2 and _ticks_run > 30:
		wipe.start()
	_wipe_cat = kind


func _attract_pressed(event: InputEvent) -> bool:
	if not _attract:
		return false
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) > 0.6
	return _skips_intro(event)


## On the bare title: count idle ticks, then start the demo.
func _attract_step() -> void:
	if _attract:
		_attract_hint.visible = (flow_t / 30) % 3 != 2  # blinks: two thirds on, a third off
		return
	var on_title := ui.screens.size() == 1 and ui.top() is TitleScreen and not paused and intro == null
	if not on_title:
		_idle_t = 0
		return
	_idle_t += 1
	if _idle_t >= ATTRACT_AT:
		_start_attract()


func _start_attract() -> void:
	_attract = true
	_idle_t = 0
	_attract_focus = get_viewport().gui_get_focus_owner()
	ui.visible = false
	_attract_ui.visible = true
	seed_base += 1
	_menu_ko_t = 0
	_menu_background(true)
	flow_t = 0
	wipe.start()


## Back to the title: the screen and its focus where they were.
func _end_attract() -> void:
	if not _attract:
		return
	_stop_attract()
	hud.menu_visible = true
	_menu_background()
	flow_t = 0
	_idle_t = 0
	wipe.start()
	if _attract_focus != null and is_instance_valid(_attract_focus):
		_attract_focus.grab_focus()
	_attract_focus = null


## The demo's own screens off (the title, or a match, takes over).
func _stop_attract() -> void:
	_attract = false
	_idle_t = 0
	if ui != null:
		ui.visible = true
	if _attract_ui != null:
		_attract_ui.visible = false


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
	_save_settings()


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
	_save_settings()


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
		s.add_card("Audio", "Master, music, sound effects, menu sounds, voice chat",
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
		"audio": "Volumes and voice chat", "touch": "The on-screen stick and buttons (they show when you touch the screen in a fight)"}.get(page, "")
	scr.hints = ["move", "change", "back"]
	scr.builder = func(s: UiScreen):
		for key in SETTING_PAGES[page]:
			if key == "server":
				_add_server_row(s)
			elif key.begins_with("#"):
				s.add_heading(key.substr(1))
			elif key == "mic_test":
				_add_mic_test_row(s)
			else:
				_add_setting_row(s, key)
		s.add_space(4)
		s.add_button("Back", s.back)
	scr.backed.connect(func():
		_setting_rows.clear()
		if voice_view != null:
			voice_view.test_stop())
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


## Settings > Audio > Test microphone: Enter records a few seconds with a live level bar,
## then plays them back (VoiceView.test_start); `_voice_step` keeps the row current.
func _add_mic_test_row(s: UiScreen) -> OptionRow:
	var o := s.add_option("Test microphone", [voice_view.test_text()], 0, func(_i): pass,
		"Press, say a few words, and hear them played back. The bar shows how loud the microphone hears you. Nothing heard: pick another Microphone, or allow the game to use it in your system settings")
	o.activates = true
	o.bar = voice_view.test_level
	o.activated.connect(func():
		_apply_mic()
		voice_view.test_start()
		_refresh_mic_test())
	_setting_rows["mic_test"] = o
	return o


func _refresh_mic_test() -> void:
	var o: OptionRow = _setting_rows.get("mic_test")
	if o == null or voice_view == null:
		return
	var t := voice_view.test_text()
	if o.values.size() != 1 or String(o.values[0]) != t:
		o.set_values([t], 0)
	if not is_equal_approx(o.bar, voice_view.test_level):
		o.bar = voice_view.test_level
		o.queue_redraw()


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
		s.add_button("Touch controls", func(): _open_settings_page("touch"),
			"The on-screen stick and buttons: how see-through, how big, which hand, how to aim")
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
	if not keep_teams:
		_maybe_intro()


## Modes that open the pick screen first.
func _has_pick(cfg: Dictionary) -> bool:
	return cfg.get("duel", false) or cfg.get("versus2p", false) or cfg.has("team") or cfg.get("brawl", false)


func _on_teams_chosen(teams: Array) -> void:
	_close_ui()
	hud.visible = true
	_teams = teams
	audio.play("ui_select", 0.0, 1.0, true)
	_start_round()
	_maybe_intro()


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
		if arcade is Arcade:
			_maybe_intro()  # a new opponent up the ladder (not each Gauntlet wave)
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
			fx.pads.append({"pos": team_battle.pad_point(side, k), "color": Hud.SIDE_COLORS[side], "count": 0})


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
		"color": Hud.SIDE_COLORS[holder] if holder >= 0 else Color("e8d8a0")}


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
		return Hud.BRAWL_COLORS[team % Hud.BRAWL_COLORS.size()]
	return Hud.SIDE_COLORS[clampi(team, 0, 1)]


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
	_drop_intro()
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
	crowd.set_size(sim.arena_size(), two_sides)
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
	water.set_sim(sim)
	wear.set_sim(sim)
	water.fx = fx
	ambient.set_sim(sim, arena.art())
	ambient.fx = fx
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
	if bloom != null:
		bloom.frame(get_viewport())
	if netplay != null and netplay.link != null and netplay.link.realtime:
		netplay.pump()
	_voice_step(_delta)
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
	_wipe_step()
	_touch_step()
	if paused:
		_capture()
		return  # frozen behind the pause menu: nothing steps, the picture holds
	if intro != null:
		_intro_step()
		perf_overlay.tick(Time.get_ticks_usec() - tick_start)
		_capture()
		return  # the arena intro: the sim waits at its first tick, the views play it
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
	var t_v := t_fx
	arena.refresh()
	PerfLog.since("adv arena", t_v)
	t_v = PerfLog.now()
	water.advance()
	PerfLog.since("adv water", t_v)
	t_v = PerfLog.now()
	ambient.advance()
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
				_menu_background(_attract)
			_attract_step()
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
				_note_exchange()
				var kind := _hit_kind(e)
				if kind == "heavy" or kind == "surge":
					_note_clash(Vector2(e["pos"]), 1.0 if kind == "surge" else CLASH_HEAVY)
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
			if String(e["type"]) == "guard_break" and fx._event_shown(e):
				_note_clash(Vector2(e["pos"]), 1.0)
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


func _update_camera() -> void:
	var size := sim.arena_size() if sim != null else SimDefs.arena_size()  # the whole stadium
	var view := get_viewport().get_visible_rect().size  # the screen (wider on ultrawide)
	var base_z := 1.0
	var base_focus := size * 0.5
	var ko_focus := _ko_focus
	if intro != null:
		base_z = intro.zoom
		base_focus = intro.focus
	elif sim != null and showcase == null and coach == null:
		_frame_fight(view, size)
		base_z = _cam_zoom * _cam_zclash
		base_focus = _cam_follow + _cam_off
	elif (showcase != null or coach != null) and sim != null and sim.creatures.size() >= 2:
		var a := sim.creatures[0].pos
		var b := sim.creatures[1].pos
		# A showcase's extra fighters (the cleaver's second foe) are framed too.
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		for i in range(2, sim.creatures.size()):
			lo = lo.min(sim.creatures[i].pos)
			hi = hi.max(sim.creatures[i].pos)
		# Fighters stacked up and down the screen: aim a little higher and zoom out to
		# keep both (and their heads) in shot.
		var dy := hi.y - lo.y
		var mid := (lo + hi) * 0.5 + Vector2(0, -8 - minf(dy, 40.0) * 0.3)
		_cam_follow = mid if _cam_follow == Vector2.ZERO else _cam_follow.lerp(mid, 0.12)
		var fit := lerpf(SHOWCASE_ZOOM, 1.3, clampf(dy / 40.0, 0.0, 1.0))
		_cam_zoom = fit if _cam_zoom <= 0.0 else lerpf(_cam_zoom, fit, 0.08)
		base_z = _cam_zoom
		base_focus = _cam_follow
		ko_focus = _ko_pos + Vector2(0, -16)  # no K.O. banner in a showcase
	if _cam_force != Vector3.ZERO:
		base_focus = Vector2(_cam_force.x, _cam_force.y)
		if _cam_force.z > 0.0:
			base_z = _cam_force.z
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
	var pos := Vector2(_cam_axis(focus.x, half.x, size.x, CrowdView.SHOW_SIDE, CrowdView.SHOW_SIDE),
		_cam_axis(focus.y, half.y, size.y, CrowdView.SHOW_TOP, CrowdView.SHOW_FRONT))
	# Whole screen pixels: a still thing on the floor moves a whole pixel at a time as the
	# camera pans, never resampled at a new phase (no shimmer).
	camera.position = snap_cam(pos, z * maxf(1.0, float(get_window().size.x) / maxf(view.x, 1.0)))
	_update_pointers(view)


## A camera position on the screen's pixel grid: `px` screen pixels per world unit (the
## zoom x the window's pixels per canvas unit).
static func snap_cam(pos: Vector2, px: float) -> Vector2:
	if px <= 0.0:
		return pos
	return (pos * px).round() / px


## How far into the KO push-in the camera is, 0..1, `t` ticks after the knockout: held
## still for the freeze's first beat, then eased in and out (smoothstep) so the push
## reads as a deliberate move rather than a snap; held, then eased back out.
static func ko_push(t: int) -> float:
	var k_in := clampf(float(t - KO_PUSH_DELAY) / KO_PUSH_IN, 0.0, 1.0)
	var k_out := clampf(float(t - KO_HOLD_UNTIL) / KO_PUSH_OUT, 0.0, 1.0)
	return smoothstep(0.0, 1.0, k_in) * (1.0 - smoothstep(0.0, 1.0, k_out))


## The letterbox: in for a knockout's push-in (until it starts easing back), a Surge's
## freeze and its cut-in (held until the cut-in is gone, which outlasts the freeze), and the
## arena intro; out otherwise. Not over the title's background match.
func _update_letterbox() -> void:
	if _surge_bars > 0:
		_surge_bars -= 1
	var ko := _ko_cam_t >= 0 and _ko_cam_t < KO_HOLD_UNTIL
	letterbox.shown = (flow != Flow.MENU or _attract) and (ko or _surge_bars > 0 or hud.cutting_in() or intro != null)
	letterbox.advance()


# ------------------------------------------------------------------ arena intro

## Whether a match starting now gets the arena intro: offline matches against the CPU or
## local players, with Settings > Game > Match intros on. Never online (both peers must
## start the sim on the same tick, and a watcher follows the server's), in a replay,
## training, trials, drills or showcases, or behind the menu. Headless runs and command-line
## starts skip it unless --intro (tests and captures keep their frame numbers).
func _intro_wanted() -> bool:
	if _intro_arg < 0 or not match_intros:
		return false
	if _intro_arg == 0 and (DisplayServer.get_name() == "headless" or _cli_start or autoplay != null):
		return false
	if sim == null or online != null or watch != null or netplay != null or _replaying():
		return false
	if showcase != null or coach != null or sim.training or MODES[mode].get("training", false):
		return false
	return flow == Flow.INTRO or flow == Flow.FIGHT


## Starts the arena intro for the match just set up, if it gets one. The sim stays at its
## first tick until the intro ends (or a press skips it); then the round goes on exactly as
## it would have without it.
func _maybe_intro() -> void:
	if not _intro_wanted():
		return
	_drop_intro()
	intro = ArenaIntro.new()
	intro.sim = sim
	intro.arena_name = String(sim.arena.get("name", ArenaMap.name_of(sim.arena_id)))
	intro.subtitle = _intro_subtitle()
	intro.groups = _intro_groups()
	_screen_layer.add_child(intro)
	_screen_layer.move_child(intro, hud.get_index())  # over the letterbox and the flash, under the HUD
	hud.cinema = true
	hud.banner = ""
	hud.banner_sub = ""
	for v in views:
		v.intro_clock = 0
	crowd.roar(90)
	audio.play("crowd_roar")


## What the arena's card says under its name: the mode.
func _intro_subtitle() -> String:
	var cfg: Dictionary = MODES[mode]
	if arcade != null:
		return arcade.stage_label()
	if team_battle != null:
		var what := "KING OF THE CRATER" if team_battle.crater else ("SINKHOLE" if team_battle.sinkhole else
			("TEAM DEATHMATCH" if team_battle.deathmatch else ("CARAVAN" if team_battle.caravan else
			("CAPTURE THE FLAG" if team_battle.ctf else "TEAM BATTLE"))))
		return "%s   %d v %d" % [what, team_battle.size, team_battle.size]
	if duel != null:
		return "DUEL   %d v %d" % [(duel.teams[0] as Array).size(), (duel.teams[1] as Array).size()]
	if brawl != null:
		return "CHAOS CUP" if _chaos_names != "" else "BRAWL"
	return "VERSUS" if cfg.get("versus2p", false) else "1 v 1"


## The intro's beats: one per fighter in a 1v1, one per team in a team battle or a Duel
## (introduced together), and one for everyone in a Brawl.
func _intro_groups() -> Array:
	var out: Array = []
	var n := sim.creatures.size()
	if brawl != null:
		var names: Array = []
		var all: Array = []
		for i in n:
			names.append(String(sim.creatures[i].def.get("name", "?")).to_upper())
			all.append(i)
		return [{"slots": all, "side": 0, "color": Hud.C_ACCENT, "tag": "FREE-FOR-ALL",
			"name": "%d FIGHTERS" % n, "lines": ["  ·  ".join(names)]}]
	if team_battle != null or duel != null:
		for side in 2:
			var slots: Array = []
			var names: Array = []
			for i in n:
				if sim.creatures[i].team == side:
					slots.append(i)
			if duel != null:
				for id in duel.teams[side]:
					names.append(String(MatchFactory.load_def(String(id)).get("name", id)).to_upper())
			else:
				for i in slots:
					names.append(String(sim.creatures[i].def.get("name", "?")).to_upper())
			var you := false
			for i in slots:
				you = you or (i < sides.size() and sides[i] in LOCAL_SIDES)
			out.append({"slots": slots, "side": side, "color": Hud.SIDE_COLORS[side],
				"tag": "YOUR TEAM" if you else "CPU TEAM",
				"name": ["RED TEAM", "BLUE TEAM"][side], "lines": ["  ·  ".join(names)]})
		return out
	for i in mini(n, 2):
		var d: Dictionary = sim.creatures[i].def
		var bits := PackedStringArray()
		for k in ["role", "affinity"]:
			var v = d.get(k)
			if v != null and String(v) != "" and String(v) != "none":
				bits.append(String(v).capitalize())
		var lines: Array = []
		if String(d.get("title", "")) != "":
			lines.append(String(d["title"]))
		lines.append("  ·  ".join(bits))
		out.append({"slots": [i], "side": i, "color": Hud.SIDE_COLORS[i], "tag": _side_name(i),
			"name": String(d.get("name", "?")).to_upper(), "lines": lines})
	return out


## One tick of the intro: only views move (the sim is not stepped, no events, no CPUs).
func _intro_step() -> void:
	var view := get_viewport().get_visible_rect().size
	var g := intro.advance(view, sim.arena_size())
	if g >= 0:
		for i in intro.groups[g]["slots"]:
			if int(i) < views.size():
				views[int(i)].intro_pose()
		crowd.cheer(0.5)
		audio.play("round_start", -6.0, 1.25)
	if intro.t == ArenaIntro.CARD_IN + 3:
		audio.play("slam", -6.0, 0.8)
		shake = maxf(shake, 2.0)
	arena.refresh()
	water.advance()
	ambient.advance()
	weather.advance()
	wear.advance()
	crowd.advance()
	fx.advance()
	hud.advance()
	for v in views:
		v.refresh()
	shake *= 0.82
	_update_camera()
	_update_letterbox()
	var sh := shake * shake_scale
	camera.offset = Vector2.ZERO if sh <= 0.3 else Vector2(randf_range(-sh, sh), randf_range(-sh, sh)).round()
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - 0.04)
	if intro.finished():
		_end_intro()


## The intro is over (or skipped): the fight camera eases on from where the intro left
## it, the HUD comes back, and the round's banners start on the next tick.
func _end_intro() -> void:
	if intro == null:
		return
	_cam_zoom = intro.zoom
	_cam_follow = intro.focus
	_cam_lead = Vector2.ZERO
	_cam_aim = Vector2.ZERO
	_cam_off = Vector2.ZERO
	_drop_intro()


## Takes the intro off without touching the camera (a new match, the menu).
func _drop_intro() -> void:
	if intro == null:
		return
	intro.queue_free()
	intro = null
	hud.cinema = false
	for v in views:
		v.intro_clock = -1
		v.victory = false


## Big maps: arrows at the screen's edge toward objectives out of shot (the caravan, the
## flags). Screen = (world - camera) x zoom + half the screen.
func _update_pointers(view: Vector2) -> void:
	var out: Array = []
	var playing := sim != null and showcase == null
	if playing and ((team_battle != null and team_battle.sim == sim) or (brawl != null and brawl.sim == sim)):
		var targets := _wanted_pointers()
		if team_battle != null and team_battle.caravan:
			targets.append([team_battle.caravan_pos(), Hud.SIDE_COLORS[team_battle.cv_attacker()], "CARAVAN"])
		if team_battle != null and team_battle.ctf:
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
	var busy := _cam_push > 0.0 or _clash > 0.0 or _clash_hold > 0 or _ko_cam_t >= 0 or _exchange_t > 0
	for i in n:
		var c := sim.creatures[i]
		var moved := c.pos - _cam_prev[i]
		_cam_prev[i] = c.pos
		if c.state != CreatureSim.State.KO:  # (Settle: is anything happening?)
			busy = busy or moved.length_squared() > 0.04 or c.state != CreatureSim.State.IDLE \
				or (c.prev_buttons & CAM_ACT_BITS) != 0
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
	var room_cap := minf(view.x / (tight.size.x + EXCHANGE_PAD.x * 2.0), view.y / (tight.size.y + EXCHANGE_PAD.y * 2.0 + 24.0))
	var mid := box.get_center()
	# Aim lead: where the viewed fighter aims, held through the dead zone.
	var aim := _aim_now(anchor) if cam_level("cam_lead") > 0 else Vector2.ZERO
	if aim == Vector2.ZERO:
		_cam_aim_dir = Vector2.ZERO
	elif _cam_aim_dir == Vector2.ZERO or aim.dot(_cam_aim_dir) < AIM_DEAD_DOT * aim.length() * _cam_aim_dir.length():
		_cam_aim_dir = aim
		busy = true
	_cam_idle = 0 if busy else _cam_idle + 1
	var settle := cam_level("cam_settle")
	var settled := settle > 0 and _cam_idle >= SETTLE_AFTER
	if _cam_zoom <= 0.0:
		_cam_zoom = fit
		_cam_follow = mid
		_cam_lead = Vector2.ZERO
		_cam_aim = Vector2.ZERO
	elif settled:
		# Nothing happening: the target is held where it was when things went quiet, and
		# moves only when the live one gets past the dead zone; the camera drifts to it.
		if _cam_idle == SETTLE_AFTER or _settle_fit <= 0.0:
			_settle_mid = mid
			_settle_fit = fit
		if mid.distance_to(_settle_mid) > float(SETTLE_DEAD[settle]):
			_settle_mid = mid
		if absf(fit / _settle_fit - 1.0) > SETTLE_ZOOM_DEAD:
			_settle_fit = fit
		_cam_follow = _cam_follow.lerp(_settle_mid, float(SETTLE_DRIFT[settle]))
		if fit < _cam_zoom:
			_cam_zoom = lerpf(_cam_zoom, fit, 0.12)  # (never holds anyone out of shot)
		else:
			_cam_zoom = lerpf(_cam_zoom, minf(_settle_fit, fit), SETTLE_ZOOM_EASE)
		_cam_lead = _cam_lead.lerp(lead.limit_length(LEAD_MAX), LEAD_EASE)
	else:
		# Pull back quickly (nobody leaves the shot), push in gently.
		_cam_zoom = lerpf(_cam_zoom, fit, 0.12 if fit < _cam_zoom else 0.03)
		_cam_follow = _cam_follow.lerp(mid, 0.1)
		_cam_lead = _cam_lead.lerp(lead.limit_length(LEAD_MAX), LEAD_EASE)
	var aim_want := _cam_aim_dir * Vector2(1.0, AIM_LEAD_Y) * float(AIM_LEAD[cam_level("cam_lead")])
	_cam_aim = _cam_aim.lerp(aim_want, AIM_EASE_IN if aim_want.length() >= _cam_aim.length() else AIM_EASE_OUT)
	if _cam_aim.length_squared() < 0.0025:
		_cam_aim = Vector2.ZERO
	# Clash reaction: eased toward the strength asked for while it's held.
	if _clash_hold > 0:
		_clash_hold -= 1
	else:
		_clash_want = 0.0
	if _ko_cam_t >= 0:  # the KO push-in owns the moment
		_clash_want = 0.0
		_clash_hold = 0
	_clash = lerpf(_clash, _clash_want, CLASH_IN if _clash_want > _clash else CLASH_OUT)
	if _clash < 0.01:
		_clash = 0.0
	_cam_zclash = clash_zoom(_clash, CLASH_PUSH[cam_level("cam_clash")], EXCHANGE_PUSH * _cam_push,
		room_cap / maxf(_cam_zoom, 0.01))
	var clash_off: Vector2 = (_clash_pos - _cam_follow).limit_length(CLASH_SHIFT[cam_level("cam_clash")]) * _clash
	_cam_lead = _lead_room(_cam_lead, _cam_follow, tight, view * 0.5 / _cam_zoom)
	_cam_off = _lead_room(_cam_lead + _cam_aim + clash_off, _cam_follow, tight, view * 0.5 / (_cam_zoom * _cam_zclash))


## The clash push-in's zoom factor: `amt` (0..1) of `push`, not on top of the exchange
## push-in already in the fit (`exchange`, its share: the larger counts, not the sum), and
## never past `cap` (the factor that still leaves EXCHANGE_PAD round the fighters).
static func clash_zoom(amt: float, push: float, exchange: float, cap: float) -> float:
	if amt <= 0.0 or push <= 0.0:
		return 1.0
	var f := (1.0 + maxf(exchange, push * amt)) / (1.0 + exchange)
	return clampf(f, 1.0, maxf(1.0, cap))


## A heavy hit, a guard break or a Surge's hit at `pos` in shot: the clash reaction,
## `amt` of the full push-in (see CLASH_*).
func _note_clash(pos: Vector2, amt: float) -> void:
	if cam_level("cam_clash") <= 0 or _ko_cam_t >= 0:
		return
	_clash_want = maxf(_clash_want if _clash_hold > 0 else 0.0, amt)
	_clash_hold = CLASH_HOLD
	_clash_pos = pos
	_cam_idle = 0


## What kind of move a `hit` event came from ("light", "heavy", "skill", "surge"; "" when
## the attacker has already moved on, as after a shot): the event says only `heavy`, so the
## attacker's move is read (never written).
func _hit_kind(e: Dictionary) -> String:
	if not bool(e.get("heavy", false)):
		return "light"
	var a := int(e.get("attacker", -1))
	if a < 0 or a >= sim.creatures.size():
		return ""
	return sim.creatures[a].move_type()


## A --cam-lead= / --cam-clash= / --cam-settle= value as a CAM_LEVELS index: 0 / off,
## 1 / on / normal, low, high; -1 for anything else.
static func cam_level_arg(v: String) -> int:
	match v.to_lower():
		"0", "off":
			return 0
		"1", "on", "normal":
			return CAM_DEFAULT
		"low":
			return 1
		"high":
			return 3
	return -1


## A camera behaviour's level (CAM_LEVELS index): the command line's for this session,
## else the setting.
func cam_level(key: String) -> int:
	return clampi(int(_cam_cli.get(key, get(key))), 0, CAM_LEVELS.size() - 1)


## Whose aim the camera leads with: the players here (online, the local slot); with
## nobody here playing (watching, a replay, CPU vs CPU) the fighter the HUD follows. On
## a big map, only the followed player (`anchor`).
func _aim_fighters(anchor: int) -> Array:
	var n := sim.creatures.size()
	if anchor >= 0:
		return [anchor]
	if online != null:
		return [online.local_slot] if online.local_slot < n else []
	var out := []
	for k in mini(sides.size(), n):
		if sides[k] in LOCAL_SIDES:
			out.append(k)
	if out.is_empty() and hud.focus < n:
		out.append(hud.focus)
	return out


## The aim the camera leads toward this tick: the average of the aim fighters' aims (two
## players here aiming apart cancel out), nothing while knocked out or falling.
func _aim_now(anchor: int) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for k in _aim_fighters(anchor):
		if _is_hidden(k):
			continue
		var d := aim_dir_of(sim.creatures[k])
		if d != Vector2.ZERO:
			sum += d
			count += 1
	if count == 0:
		return Vector2.ZERO
	sum /= count
	return sum if sum.length() > 0.3 else Vector2.ZERO


## One fighter's aim, read from the sim (never written): its exact aim angle when its last
## input carried one (twin-stick, mouse), else the way it faces.
static func aim_dir_of(c: CreatureSim) -> Vector2:
	if c.state == CreatureSim.State.KO or c.state == CreatureSim.State.FALLING:
		return Vector2.ZERO
	if c.prev_buttons & SimDefs.IN_AIM:
		return SimDefs.aim_from_bits(c.prev_buttons)
	return c.facing.normalized() if c.facing != Vector2.ZERO else Vector2.ZERO


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
	if _attract_pressed(event):
		_end_attract()
		get_viewport().set_input_as_handled()  # the press only wakes the title
		return
	if not (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative == Vector2.ZERO):
		_idle_t = 0
	if wipe != null and wipe.active() and _skips_intro(event):
		wipe.finish()  # (the press still does what it does)
	if intro != null and _skips_intro(event):
		_end_intro()
		get_viewport().set_input_as_handled()  # the press only skips (Esc doesn't also pause)
		return
	var touch := event is InputEventScreenTouch or event is InputEventScreenDrag
	if not (event is InputEventMouseMotion) and not touch:
		_join_cpus()  # a press may change the match (a reset, a swap) while the CPUs read it
	_note_input(event)


## One event for player 1's devices: which device is in use (the prompts and the touch
## controls follow it), and the screen's touches for the touch pad.
func _note_input(event: InputEvent) -> void:
	var before := player_input.label_set()
	player_input.note_event(event)
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		player_input.touch.feed(event)
	if player_input.label_set() != before:
		_apply_device()


## Once a tick (also while paused): the touch pad's state and the overlay. Touches start
## fingers only in a fight with a player here; anything else, or another device, lets go
## of every finger. A tap on the overlay's Pause is the Pause button.
func _touch_step() -> void:
	var pad := player_input.touch
	var here := online != null or sides.has(Side.PLAYER)
	var fighting := flow == Flow.FIGHT and here and not paused and not ui.is_open() and intro == null \
			and showcase == null and autoplay == null and not _replaying() and watch == null
	pad.active = fighting
	if touch_demo != null and fighting:
		for ev in touch_demo.step(pad):
			_note_input(ev)
	var vs := get_viewport_rect().size
	var tag := duel != null
	if pad.show_tag != tag or pad.screen() != vs:
		pad.show_tag = tag
		pad.layout(vs)
	var on := player_input.device == PlayerInput.Device.TOUCH
	if (not fighting or not on) and pad.fingers_down() > 0:
		pad.release_all()
	touch_overlay.visible = fighting and on
	touch_overlay.sim = sim
	touch_overlay.slot = hud.focus
	hud.touch = touch_overlay.visible
	_touch_targets()
	if pad.pause_requested:
		pad.pause_requested = false
		if fighting:
			var ev := InputEventAction.new()  # the same as Esc or Start
			ev.action = "pause"
			ev.pressed = true
			Input.parse_input_event(ev)


## The target lock's view of the match: who the local team can't see (never locked or
## shown), the enemy portraits (foes it could lock, seen and on screen; none with one foe)
## and Capture the Flag's objective button (the foe carrying our flag).
func _touch_targets() -> void:
	var pad := player_input.touch
	player_input.touch_hidden = _hidden
	touch_overlay.unseen = _hidden
	var picks: Array = []
	var objective := false
	var me_idx: int = hud.focus
	if touch_overlay.visible and me_idx >= 0 and me_idx < sim.creatures.size():
		var me: CreatureSim = sim.creatures[me_idx]
		var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
		var foes := 0
		for i in sim.creatures.size():
			if not me.is_foe(sim.creatures[i]):
				continue
			foes += 1
			if view.has_point(sim.creatures[i].pos) and TouchTarget.can_lock(sim, me_idx, i, _hidden):
				picks.append(i)
		if foes < 2:
			picks = []  # one foe: a tap already finds it
		objective = team_battle != null and team_battle.ctf
		if pad.objective_requested:
			var o := TouchTarget.ctf_objective(team_battle, me)
			if o >= 0:
				pad.lock_request = o
	pad.objective_requested = false
	pad.set_picks(picks, objective)


## Settings > Controls > Touch into the touch pad and the overlay.
func _apply_touch() -> void:
	touch_overlay.opacity = float(TOUCH_OPACITY[clampi(touch_opacity, 0, TOUCH_OPACITY.size() - 1)])
	player_input.touch.left_handed = touch_left or _touch_demo_left
	player_input.touch.layout(player_input.touch.screen())


## Any button skips the arena intro: a key, a controller button, a mouse click.
static func _skips_intro(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	return (event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventAction) and event.pressed


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
		_open_online_pause()
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
		"touch_opacity":
			var ops: Array = []
			for o in TOUCH_OPACITY:
				ops.append("%d%%" % roundi(float(o) * 100.0))
			return {"label": "Opacity", "values": ops, "index": touch_opacity,
				"desc": "How see-through the touch stick and buttons are"}
		"touch_size":
			return {"label": "Button size", "values": TouchPad.SIZE_NAMES, "index": player_input.touch.size_step,
				"desc": "Bigger buttons are easier to hit and cover more of the fight"}
		"touch_hand":
			return {"label": "Hand", "values": ["Right-handed", "Left-handed"],
				"index": 1 if touch_left else 0,
				"desc": "Left-handed: the buttons on the left and the stick on the right"}
		"touch_priority":
			return {"label": "Lock on", "values": TouchTarget.PRIORITY_NAMES, "index": int(player_input.target.priority),
				"desc": "Which foe a tap locks onto: the one nearest where you point, the nearest, or the one with the least health. Tap a portrait to pick one yourself"}
		"touch_chase":
			return {"label": "Chase target", "values": ["Off", "On"], "index": 1 if player_input.target.chase_on else 0,
				"desc": "Tap Light with your target out of reach and you walk to it (round pits and walls), then hit. The stick always wins"}
		"touch_aim":
			return {"label": "Aiming", "values": TouchPad.AIM_STYLES, "index": 1 if player_input.touch.tap_only else 0,
				"desc": "Tap + drag: tap fires (aimed for you), drag Heavy, Skills or Surge off the button to aim and let go to throw. Tap only: every button fires on the touch"}
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
		"intros":
			return {"label": "Match intros", "values": ["Off", "On"], "index": 1 if match_intros else 0,
				"desc": "Before an offline match: a fly-over of the arena and each side's entrance (any button skips it)"}
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
		"glow":
			return {"label": "Glow", "values": ["Off", "On"], "index": 1 if glow else 0,
				"desc": "Glowing things (auras, sparks, flashes, shots) light the floor around them. Off for weaker devices"}
		"lighting":
			return {"label": "Lighting", "values": ["Off", "Low", "High"], "index": lighting,
				"desc": "Real light on the fighters (sun, auras, flashes); High adds the Floodgate's night lamps and bloom. Lower for weaker devices"}
		"font":
			return {"label": "Text font", "values": ["Pixel", "Smooth"], "index": 1 if UiTheme.smooth else 0,
				"desc": "The menus and the HUD: the pixel font, or the smooth font from before"}
		"cam_lead":
			return {"label": "Aim lead", "values": CAM_LEVELS, "index": cam_lead,
				"desc": "The camera leans a little toward where you aim, so you see more of the floor in front of you"}
		"cam_clash":
			return {"label": "Clash reaction", "values": CAM_LEVELS, "index": cam_clash,
				"desc": "A heavy hit, a guard break or a Surge's hit: the camera punches in for a moment"}
		"cam_settle":
			return {"label": "Settle", "values": CAM_LEVELS, "index": cam_settle,
				"desc": "When nothing is happening, the camera holds still instead of hunting. Higher: stiller"}
		"voice":
			var talk := Controls.binding_text("lol_talk" if player_input.layout == "league" else "kb_talk",
				"league" if player_input.layout == "league" else "classic")
			return {"label": "Voice chat", "values": VoiceChat.MODE_NAMES, "index": voice_mode_now(),
				"desc": "Online: talk to players near your fighter (teammates always faintly). Push to talk holds %s. Voice isn't encrypted: treat it like a phone call on open Wi-Fi. Open mic sends any sound above a whisper, TV included; push to talk is the safer default" % talk}
		"voice_hear":
			return {"label": "Hear voices from", "values": VOICE_HEAR, "index": voice_hear,
				"desc": "Everyone: anyone in your match. Rooms and friends: Quick match and ranked strangers start muted; unmute them from the pause menu"}
		"mic":
			var mics := mic_choices()
			return {"label": "Microphone", "values": mics, "index": maxi(0, mics.find(mic_device)),
				"desc": "Which microphone voice chat listens to"}
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
			"intros":
				match_intros = i == 1
			"rumble":
				rumble = i == 1
				if rumble and player_input.device == PlayerInput.Device.GAMEPAD:
					Input.start_joy_vibration(player_input.pad_id, 0.4, 0.4, 0.2)  # feel it
			"shake":
				shake_scale = float(SHAKE_CHOICES[clampi(i, 0, SHAKE_CHOICES.size() - 1)][1])
			"range_rings":
				range_rings = i == 1
				_apply_range_rings()
			"touch_opacity":
				touch_opacity = clampi(i, 0, TOUCH_OPACITY.size() - 1)
				_apply_touch()
			"touch_size":
				player_input.touch.size_step = clampi(i, 0, TouchPad.SIZES.size() - 1)
				_apply_touch()
			"touch_hand":
				touch_left = i == 1
				_apply_touch()
			"touch_aim":
				player_input.touch.tap_only = i == 1
			"touch_priority":
				player_input.target.priority = clampi(i, 0, TouchTarget.PRIORITY_NAMES.size() - 1) as TouchTarget.Priority
			"touch_chase":
				player_input.target.chase_on = i == 1
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
			"cam_lead", "cam_clash", "cam_settle":
				set(key, clampi(i, 0, CAM_LEVELS.size() - 1))
				_cam_cli.erase(key)  # (the menu outranks a command-line value from here on)
			"perf_overlay":
				perf_overlay.mode = clampi(i, 0, PerfOverlay.MODE_NAMES.size() - 1) as PerfOverlay.Mode
			"voice":
				voice_mode = clampi(i, 0, VoiceChat.MODE_NAMES.size() - 1)
				_voice_cli = -1  # (the menu outranks --voice from here on)
				_apply_voice()
			"voice_hear":
				voice_hear = clampi(i, 0, VOICE_HEAR.size() - 1)
			"mic":
				var mics := mic_choices()
				mic_device = String(mics[clampi(i, 0, mics.size() - 1)])
				_apply_mic()
			"glow":
				glow = i == 1
				_apply_glow()
			"lighting":
				lighting = clampi(i, 0, 2)
				_lighting_cli = -1
				_apply_lighting()
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

## The voice chat mode this session: --voice-test (open mic), else --voice, else the setting.
func voice_mode_now() -> int:
	if _voice_test:
		return VoiceChat.Mode.OPEN_MIC
	return _voice_cli if _voice_cli >= 0 else voice_mode


## --voice=off|ptt|open (this session's mode, never saved) and --voice-test=tone.
func _voice_arg(a: String) -> void:
	if a.begins_with("--voice="):
		var vm := ["off", "ptt", "open"].find(a.get_slice("=", 1))
		if vm >= 0:
			_voice_cli = vm
	elif a == "--voice-test=tone":
		_voice_test = true
		voice_view.tone = true
	_apply_voice()


## The session's voice chat follows the setting (a new Netplay, a change mid-match).
func _apply_voice() -> void:
	var m := voice_mode_now()
	if netplay != null and netplay.voice != null:
		netplay.voice.mode = m
	if m != VoiceChat.Mode.OFF:
		VoiceView.ask_permission()


## Settings > Audio > Hear voices from, at a Netplay's first match: "Rooms and friends"
## starts a server Quick match or ranked match (no room code: strangers) with everyone
## muted; a room or a direct host / join starts unmuted. Once per Netplay, so a rematch
## keeps what the player chose in the pause menu since.
func _apply_voice_hear() -> void:
	if netplay == null or netplay.voice == null or netplay.has_meta("voice_hear_applied"):
		return
	netplay.set_meta("voice_hear_applied", true)
	netplay.voice.mute_all = voice_hear == 1 and netplay.via_server and netplay.room == ""


## Online (playing or watching): the pause menu over a match that keeps going (never
## `paused`; your fighter stands still while it's open): Resume, Voice chat, and Leave
## match (or Stop watching), which asks first.
func _open_online_pause() -> void:
	var playing := online != null
	var p := PauseScreen.new(false, "")
	p.subtitle = "The match keeps going while this is open"
	p.quit_text = "Leave match" if playing else "Stop watching"
	p.quit_question = "Leave the match?" if playing else "Stop watching?"
	p.quit_note = "The match keeps going while this is open."
	p.quit_yes = "Leave"
	p.quit_no = "Stay"
	if netplay != null and netplay.voice != null:
		p.extras = [["Voice chat", _open_voice_screen, "Mute players, everyone, or your own mic"]]
	p.quit_requested.connect(func(): _leave_online())
	ui.push(p)


## The voice screen's player rows: every other human in the match on now (not a CPU, not
## this player), each {"label": "<name> · <fighter>", "slot": slot}. The name is the
## server's (VoiceChat.names), else "Player N".
func voice_rows() -> Array:
	var out: Array = []
	if netplay == null or netplay.voice == null:
		return out
	var game = null
	var players := 0
	var cpu: Dictionary = {}
	var me := -1
	if online != null:
		game = online.game_sim()
		players = online.players
		cpu = online.cpu_slots
		me = online.local_slot
	elif watch != null:
		game = watch.duel
		players = watch.players
		cpu = watch.cpus
	else:
		return out
	for slot in players:
		if slot == me or cpu.has(slot):
			continue
		var who := Netplay.clean_name(netplay.voice.name_of(slot)).strip_edges()
		if who == "":
			who = "Player %d" % (slot + 1)
		var c := VoiceView.fighter(game, slot)
		var fighter := String(c.def.get("name", "")) if c != null else ""
		out.append({"label": "%s · %s" % [who, fighter] if fighter != "" else who, "slot": slot})
	return out


## Pause > Voice chat: Mute everyone, Mute my mic (players only, voice on), a Hearing /
## Muted row per other player (VoiceChat.set_muted: by name for the session too), and the
## Voice chat mode setting. Straight onto `netplay.voice`; the match keeps going.
func _open_voice_screen() -> void:
	if netplay == null or netplay.voice == null:
		return
	var scr := UiScreen.new()
	scr.title = "VOICE CHAT"
	scr.subtitle = "The match keeps going while this is open"
	scr.row_width = 236.0
	scr.hints = ["move", "change", "back"]
	scr.builder = func(s: UiScreen):
		var chat: VoiceChat = netplay.voice
		s.add_option("Mute everyone", ["Off", "On"], 1 if chat.mute_all else 0,
			func(i: int): chat.mute_all = i == 1,
			"Hear nobody in this match. Your own mic still works")
		if online != null and voice_mode_now() != VoiceChat.Mode.OFF:
			s.add_option("Mute my mic", ["Off", "On"], 1 if chat.mic_muted else 0,
				func(i: int): chat.mic_muted = i == 1,
				"Send nothing, whatever you press. Push to talk already only sends while the key is held")
		for r in voice_rows():
			var slot := int(r["slot"])
			s.add_option(String(r["label"]), ["Hearing", "Muted"], 1 if chat.is_muted(slot) else 0,
				func(i: int): chat.set_muted(slot, i == 1),
				"Muted: you hear nothing from this player, for the rest of this session")
		_add_setting_row(s, "voice").changed.connect(func(_i): _reopen_voice_screen.call_deferred())
		s.add_space(4)
		s.add_button("Back", s.back)
	scr.backed.connect(func(): _setting_rows.erase("voice"))
	ui.push(scr)


## The voice screen again after the mode changed (Mute my mic shows only with voice on),
## focused on the mode row.
func _reopen_voice_screen() -> void:
	var top := ui.top()
	if top == null or top.title != "VOICE CHAT":
		return
	ui.pop()
	_open_voice_screen()
	var row: Control = _setting_rows.get("voice")
	if row != null:
		row.grab_focus()


## Settings > Audio > Microphone's choices: the system's input devices.
func mic_choices() -> Array:
	var out: Array = Array(AudioServer.get_input_device_list())
	if out.is_empty():
		out = ["Default"]
	return out


func _apply_mic() -> void:
	if mic_device != "" and mic_device in AudioServer.get_input_device_list():
		AudioServer.input_device = mic_device


## Push to talk: the talk key of the keyboard layout in use, or the controller's.
func _talk_held() -> bool:
	if _voice_test:
		return true
	var kb := "lol_talk" if player_input.layout == "league" else "kb_talk"
	return Input.is_action_pressed(kb) or Input.is_action_pressed("pad_talk")


## Every rendered frame: the microphone in and the voices out during an online match or
## a watched one (VoiceView), and the HUD's MIC light and speaker icons.
func _voice_step(delta: float) -> void:
	if voice_view == null or hud == null:
		return
	var game = null
	var slot := -1
	if netplay != null and online != null:
		game = online.game_sim()
		slot = online.local_slot
	elif netplay != null and watch != null:
		game = watch.duel
	_refresh_mic_test()
	voice_view.frame(netplay if game != null else null, game, slot,
		camera.get_screen_center_position() if camera != null else Vector2.ZERO, _talk_held(), delta)
	hud.mic_on = voice_view.sending
	hud.mic_missing = voice_view.mic_missing and slot >= 0 and voice_mode_now() != VoiceChat.Mode.OFF
	var chat: VoiceChat = netplay.voice if netplay != null and game != null and slot >= 0 else null
	hud.mic_muted = chat != null and chat.mic_muted and voice_mode_now() != VoiceChat.Mode.OFF
	hud.voice_muted = chat != null and chat.mute_all
	hud.speaking = voice_view.heard
	if fx != null:
		fx.speaking = voice_view.heard


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
	_apply_glow()  # High: the bloom stands in for Glow's halos
	var time := String(_lit_look.get("time", "day"))
	weather.lamp_lights = sim != null and t == Light2DView.Tier.HIGH and Light2DView.lamps_on(sim.arena, time)
	var sd := Light2DView.sun_at(sim.arena if sim != null else {}, time, String(_lit_look.get("weather", "clear")), t)
	weather.fighter_scale = float(sd.get("shade", 1.0))


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
		Netplay.player_secret = String(cfg.get_value("online", "secret", ""))
		Netplay.player_name = Netplay.clean_name(String(cfg.get_value("online", "name", "Player")))
		if Netplay.player_name == "":
			Netplay.player_name = "Player"
		var tc := String(cfg.get_value("game", "time", WeatherView.RANDOM))
		time_choice = tc if tc == WeatherView.RANDOM or tc in WeatherView.time_ids() else WeatherView.RANDOM
		var wc := String(cfg.get_value("game", "weather", WeatherView.RANDOM))
		weather_choice = wc if wc == WeatherView.RANDOM or wc in WeatherView.weather_ids() else WeatherView.RANDOM
		hazards_on = []
		var known := Hazards.ids()
		for h in cfg.get_value("game", "hazards", []):
			if String(h) in known and not (String(h) in hazards_on):
				hazards_on.append(String(h))
		hazards_on.sort()
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
		match_intros = bool(cfg.get_value("game", "intros", true))
		discord_status = bool(cfg.get_value("game", "discord", true))
		shake_scale = float(cfg.get_value("game", "shake", 1.0))
		range_rings = bool(cfg.get_value("game", "range_rings", false))
		touch_opacity = clampi(int(cfg.get_value("touch", "opacity", TOUCH_OPACITY_DEFAULT)), 0, TOUCH_OPACITY.size() - 1)
		player_input.touch.size_step = clampi(int(cfg.get_value("touch", "size", 1)), 0, TouchPad.SIZES.size() - 1)
		touch_left = bool(cfg.get_value("touch", "left_handed", false))
		player_input.touch.tap_only = bool(cfg.get_value("touch", "tap_only", false))
		player_input.target.priority = clampi(int(cfg.get_value("touch", "priority", 0)), 0,
			TouchTarget.PRIORITY_NAMES.size() - 1) as TouchTarget.Priority
		player_input.target.chase_on = bool(cfg.get_value("touch", "chase", true))
		for k in MatchSim.TRAINING_FLAGS:
			training_opts[k] = bool(cfg.get_value("training", k, false))
		dummy_mode = clampi(int(cfg.get_value("training", "dummy_mode", 0)), 0, DUMMY_MODES.size() - 1)
		Controls.apply_overrides(cfg.get_value("controls", "bindings", {}))
		var fps := int(cfg.get_value("video", "fight_fps", default_fps()))
		fight_fps = fps if fps in FPS_CHOICES else default_fps()
		UiTheme.smooth = String(cfg.get_value("video", "font", "pixel")) == "smooth"
		glow = bool(cfg.get_value("video", "glow", default_glow()))
		_apply_glow()
		lighting = clampi(int(cfg.get_value("video", "lighting", default_lighting())), 0, 2)
		for k in ["cam_lead", "cam_clash", "cam_settle"]:
			set(k, clampi(int(cfg.get_value("video", k, CAM_DEFAULT)), 0, CAM_LEVELS.size() - 1))
		perf_overlay.mode = clampi(int(cfg.get_value("video", "perf_overlay", 0)), 0,
			PerfOverlay.MODE_NAMES.size() - 1) as PerfOverlay.Mode
		voice_mode = clampi(int(cfg.get_value("audio", "voice_mode", VoiceChat.Mode.PUSH_TO_TALK)), 0,
			VoiceChat.MODE_NAMES.size() - 1)
		mic_device = String(cfg.get_value("audio", "mic_device", ""))
		voice_hear = clampi(int(cfg.get_value("audio", "voice_hear", 0)), 0, VOICE_HEAR.size() - 1)
		_apply_mic()
		var saved_rows = cfg.get_value("game", "row_choice", {})
		if saved_rows is Dictionary:
			for r in MENU_ROWS.size():
				var lbl := String(MENU_ROWS[r]["label"])
				if saved_rows.has(lbl) and MENU_ROWS[r].has("choices"):
					_row_choice[r] = clampi(int(saved_rows[lbl]), 0, (MENU_ROWS[r]["choices"] as Array).size() - 1)
	# After everything is loaded: saving here first would write defaults over it.
	# The secret proves the id is this install's to a server (never shown or sent to
	# another player); made with the id, or once for an id from before secrets.
	if Netplay.player_id.length() < 8 or not Netplay.valid_secret(Netplay.player_secret):
		if Netplay.player_id.length() < 8:
			Netplay.player_id = Netplay.make_player_id()
		if not Netplay.valid_secret(Netplay.player_secret):
			Netplay.player_secret = Netplay.make_secret()
		_save_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "layout", player_input.layout)
	cfg.set_value("input", "pad_layout", player_input.pad_layout)
	cfg.set_value("game", "level", level)
	cfg.set_value("game", "arena", _arena_saved)
	cfg.set_value("game", "time", time_choice)
	cfg.set_value("game", "weather", weather_choice)
	cfg.set_value("game", "hazards", hazards_on)
	cfg.set_value("online", "delay", input_delay)
	cfg.set_value("online", "id", Netplay.player_id)
	cfg.set_value("online", "secret", Netplay.player_secret)
	cfg.set_value("online", "name", Netplay.player_name)
	cfg.set_value("audio", "music_muted", audio.music_muted)
	cfg.set_value("audio", "voice_mode", voice_mode)
	cfg.set_value("audio", "voice_hear", voice_hear)
	cfg.set_value("audio", "mic_device", mic_device)
	cfg.set_value("online", "fighter", _online_fighter)
	cfg.set_value("online", "address", _online_address)
	cfg.set_value("online", "server", _online_server)
	cfg.set_value("online", "recent", _recent_servers)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "fight_fps", fight_fps)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "wide_fill", wide_fill)
	cfg.set_value("video", "perf_overlay", perf_overlay.mode)
	for k in ["cam_lead", "cam_clash", "cam_settle"]:
		cfg.set_value("video", k, int(get(k)))
	cfg.set_value("video", "glow", glow)
	cfg.set_value("video", "lighting", lighting)
	cfg.set_value("video", "font", "smooth" if UiTheme.smooth else "pixel")
	cfg.set_value("game", "rumble", rumble)
	cfg.set_value("game", "intros", match_intros)
	cfg.set_value("game", "shake", shake_scale)
	cfg.set_value("game", "range_rings", range_rings)
	cfg.set_value("touch", "opacity", touch_opacity)
	cfg.set_value("touch", "size", player_input.touch.size_step)
	cfg.set_value("touch", "left_handed", touch_left)
	cfg.set_value("touch", "tap_only", player_input.touch.tap_only)
	cfg.set_value("touch", "priority", int(player_input.target.priority))
	cfg.set_value("touch", "chase", player_input.target.chase_on)
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
		elif a == "--intro":
			_intro_arg = 1
		elif a == "--no-intro":
			_intro_arg = -1
		elif a == "--range-rings":
			range_rings = true
		elif a.begins_with("--lighting="):
			_lighting_cli = ["off", "low", "high"].find(a.get_slice("=", 1))
		elif a.begins_with("--mode="):
			start = clampi(int(a.get_slice("=", 1)), 0, MODES.size() - 1)
			_skip_select = true  # straight into the match with the default teams
		elif a == "--pick":
			pick = true
		elif a == "--cpu-vs-cpu":
			_cpu_vs_cpu = true
		elif a.begins_with("--mutators="):
			var table := Daily.mutator_table()
			_forced_mutators = {}
			_forced_names = []
			for id in a.get_slice("=", 1).split(",", false):
				if table.has(id):
					MatchSim.merge_mutator(_forced_mutators, table[id])
					_forced_names.append(String(table[id].get("name", id)))
				else:
					push_warning("--mutators: no mutator '%s' (data/rules/mutators.json)" % id)
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
		elif a.begins_with("--fight-fps="):
			_fight_fps_cli = maxi(0, int(a.get_slice("=", 1)))
		elif a.begins_with("--fps-pacing="):
			_fps_pacing = a.get_slice("=", 1)
		elif a.begins_with("--cpu-threads="):
			CpuController.threaded = a.get_slice("=", 1) != "off"
		elif a.begins_with("--cpu-think="):
			cpu_think = a.get_slice("=", 1)
		elif a.begins_with("--arena="):
			var ar := a.get_slice("=", 1)
			if ar in ArenaMap.IDS:
				MatchFactory.arena = ar
		elif a.begins_with("--time="):
			var tid := a.get_slice("=", 1)
			if tid == WeatherView.RANDOM or tid in WeatherView.time_ids():
				_look_cli["time"] = tid
		elif a.begins_with("--weather="):
			var wid := a.get_slice("=", 1)
			if wid == WeatherView.RANDOM or wid in WeatherView.weather_ids():
				_look_cli["weather"] = wid
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
		elif a.begins_with("--cam="):
			var cp := a.get_slice("=", 1).split(",")
			_cam_force = Vector3(float(cp[0]), float(cp[1]), float(cp[2]) if cp.size() > 2 else 0.0)
		elif a.begins_with("--cam-lead=") or a.begins_with("--cam-clash=") or a.begins_with("--cam-settle="):
			var lv := cam_level_arg(a.get_slice("=", 1))
			if lv >= 0:
				_cam_cli[a.get_slice("=", 0).trim_prefix("--").replace("-", "_")] = lv
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
			if page in ["main", "single", "look", "settings", "game", "video", "audio", "controls", "touch"] or page.begins_with("single:") \
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
		elif a.begins_with("--voice"):
			_voice_arg(a)
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
		elif a == "--touch-demo" or a.begins_with("--touch-demo="):
			touch_demo = TouchDemo.new()
			if a.get_slice("=", 1) == "left":
				touch_demo.mirror = true
				_touch_demo_left = true  # this session only (not saved)
	if touch_demo != null and start < 0:
		start = 3  # training as Cairn: a dummy to aim at
		_skip_select = true
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
		Netplay.player_name = Netplay.clean_name(t)
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
	_apply_voice()
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
			var row: Dictionary = c.board[i] if c.board[i] is Dictionary else {}
			lines.append("%d. %s%s  %d" % [i + 1, Netplay.clean_name(String(row.get("name", ""))),
				" (you)" if row.get("you", false) == true else "", int(row.get("score", 0))])
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
	_apply_voice()
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
	_apply_voice()  # (on Android: asks for the microphone at the first match with voice on)
	_apply_voice_hear()  # (strangers start muted with Hear voices from: Rooms and friends)
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
	if netplay.in_room() and netplay.room_watchers > 0:  # watchers hear voice only in rooms (the server's rule)
		hud.net_info += "   %d WATCHING (THEY HEAR VOICE)" % netplay.room_watchers
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


## The results screen's data: who won (and the pose), each fighter's stats from the
## events, and in a team mode the MVP. Capture the Flag adds caps, returns and stops.
func results_data() -> Dictionary:
	var rows: Array = []
	var winner: CreatureSim = null
	for c in sim.creatures:
		if _won_standing(c):
			winner = c
			break
	var ctf := team_battle != null and team_battle.ctf
	var best := -1
	var best_score := -1.0
	var win_team := winner.team if winner != null else -1
	if win_team < 0 and team_battle != null and team_battle.winner in [0, 1]:
		win_team = team_battle.winner  # a flag or time win: nobody "stands over" every foe
	elif win_team < 0 and duel != null and duel.winner in [0, 1]:
		win_team = duel.winner
	for c in sim.creatures:
		if c.is_dummy:
			continue
		var st: Dictionary = stats.row(c.id)
		var row := {"id": c.id, "name": String(c.def.get("name", "?")), "team": c.team, "stats": st, "extra": []}
		var sc := MatchStats.score(st)
		if ctf:
			var cs: Dictionary = _ctf_stats.get(c.id, {}) if _ctf_stats_for == team_battle else {}
			row["extra"] = [int(cs.get("caps", 0)), int(cs.get("rets", 0)), int(cs.get("stops", 0))]
			sc += 120.0 * int(cs.get("caps", 0)) + 40.0 * (int(cs.get("rets", 0)) + int(cs.get("stops", 0)))
		rows.append(row)
		if (win_team < 0 or c.team == win_team) and sc > best_score:
			best_score = sc
			best = c.id
	# The pose: in a team battle the winning side's MVP; else whoever stands; else the first
	# of the winning side. (No pose when nobody won.)
	var pose: CreatureSim = winner
	if team_battle != null and win_team >= 0:
		pose = null
		for c in sim.creatures:
			if c.id == best:
				pose = c
		if pose == null:
			winner = null
	if pose == null and win_team >= 0:
		for c in sim.creatures:
			if c.team == win_team and not c.is_dummy:
				pose = c
				break
	var title := hud.banner if hud.banner != "" else "MATCH OVER"
	var col: Color = Hud.SIDE_COLORS[win_team] if win_team in [0, 1] else UiTheme.C_ACCENT
	return {
		"title": title, "sub": hud.banner_sub, "color": col,
		"fighter": String(pose.def.get("id", "")) if pose != null else "",
		"mvp": best if team_battle != null and best_score > 0.0 else -1,
		"extra": ["CAP", "RET", "STOP"] if ctf else [],
		"rows": rows,
	}


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
	var results := online == null and watch == null and not (_replaying() or mode == REPLAY_MODE)
	if results:  # the results screen: the stats panel, then the same buttons
		scr.dim = 0.62
		scr.column_shift = 0.0
		scr.row_width = 200.0
		wipe.start()
	scr.builder = func(s: UiScreen):
		if sim != null and not _replaying() and mode != REPLAY_MODE and showcase == null and coach == null:
			s.add_text("F6  save this fight's replay", UiTheme.SIZE_HINT, UiTheme.C_DIM)
		for line in ([] if results else _ctf_summary()):
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
			s.add_panel(ResultsPanel.new(results_data()))
			s.add_space(8.0)
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
	if results:
		hud.banner_hidden = true  # the panel says it


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
	if voice_view != null:
		voice_view.stop()
	if hud != null:
		hud.net_info = ""
		hud.mic_on = false
		hud.mic_missing = false


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
	if _quit_after > 0 and t >= _quit_after:
		_write_net_report()
		_print_perf()
		get_tree().quit()
