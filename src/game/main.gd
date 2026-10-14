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
##   --autoplay            training demo: the player side follows a scripted routine
##   --dummy-mode=N        0 stand, 1 guard, 2 walk, 3 dodge
##   --hitboxes            start with the hitbox overlay on
##   --shots=60,120        save screenshots at those frame numbers
##   --shot-dir=PATH       where screenshots go (default user://shots)
##   --quit-after=N        exit after N frames
##   --layout=league|classic  keyboard layout (saved in the menu otherwise)
##   --pad-layout=standard|twinstick  controller layout (saved in Settings otherwise)
##   --showcase=NAME       play one scripted demo on a loop: cairn, culvert, craglash, barkley, gillbert,
##                         cerebro, hissy, digby, pete, sno, angles, twinstick or counterplay
##   --teams=a,b,c:d,e,f   Duel / 2-player teams (default cerebro,gillbert,barkley:culvert,cerebro,craglash)
##   --pick                show the team pick screen even with --mode
##   --cpu-vs-cpu          every player side is played by the CPU (demos, captures)
##   --menu=PAGE           open the menu on main, single or settings (captures)
##   --online-host[=PORT]  host an online 1v1 straight away (UDP, default port 7777)
##   --online-join=ADDR[:PORT][/ROOM]  join one, or a dedicated server (ROOM: meet a friend there)
##   --server[=PORT]       run as a dedicated server (with --headless); --max-players=N
##   --fighter=ID          your fighter online
##   --online-size=N       with --online-join to a server: 2 or 3 asks for a 2v2 / 3v3
##   --net-lag=N --net-loss=F   hold back / drop the input stream (feel rollback on a LAN)
##   --net-delay=N         force the input delay (frames) instead of picking it from the ping
##   --net-report=PATH     write the online match's report (inputs, state fingerprints) on exit

enum Flow { MENU, INTRO, FIGHT, ROUND_OVER, MATCH_OVER, SELECT, LOBBY }
enum Side { PLAYER, CPU, DUMMY, SCRIPT, PLAYER2, REMOTE }

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
]
## The menus (src/ui screens): the title menu opens Single player (MENU_ROWS), the online
## screen, or Settings. MODES indexes stay stable for --mode=N; rows with choices pick
## one of several modes with Left/Right.
## The Settings pages and their rows, in order (see _setting()).
const SETTING_PAGES := {
	"game": ["level", "rumble", "shake", "server"],
	"video": ["fullscreen", "wide", "vsync", "fps"],
	"audio": ["vol_Master", "vol_Music", "vol_Effects", "vol_Menu"],
}
const SHAKE_CHOICES := [["Full", 1.0], ["Reduced", 0.5], ["Off", 0.0]]
const VOLUME_NAMES := {"Master": "Master volume", "Music": "Music", "Effects": "Sound effects",
	"Menu": "Menu sounds"}
## Volume steps in Settings (10 steps of 10%).
const VOLUME_STEP := 0.1
const ONLINE_MODE := 20
const MENU_ROWS := [
	{"label": "Duel: you vs CPU  (3v3 tag)", "modes": [6], "desc": "Teams of three; tag fighters in and out"},
	{"label": "Duel: 2 players", "modes": [7], "desc": "Teams of three, two players on one screen"},
	{"label": "Team battle vs CPU", "modes": [29, 30], "choices": ["2 v 2", "3 v 3"],
		"desc": "Everyone on the field at once, CPU teammates beside you. Left/Right: team size"},
	{"label": "Versus: 2 players", "modes": [8], "desc": "One fighter each, two players on one screen"},
	{"label": "Versus CPU", "modes": [0, 1, 12, 14, 16, 18, 21, 23, 25, 27],
		"desc": "Best of three rounds against the CPU. Left/Right: your fighter",
		"choices": ["as Cairn", "as Culvert", "as Craglash", "as Barkley", "as Gillbert", "as Chef Cerebro",
			"as Hissy Fitz", "as Digby", "as Sneaky Pete", "as Sno Mercy"]},
	{"label": "Combo Trials", "modes": [9], "desc": "Learn the combos, one at a time"},
	{"label": "Reaction Drill", "modes": [10, 11], "choices": ["read Culvert", "read Cairn"],
		"desc": "Block or dodge what the opponent throws at you"},
	{"label": "Training", "modes": [3, 4, 13, 15, 17, 19, 22, 24, 26, 28],
		"desc": "Practise on a dummy (F2 changes what it does). Left/Right: your fighter",
		"choices": ["Cairn", "Culvert", "Craglash", "Barkley", "Gillbert", "Chef Cerebro", "Hissy Fitz", "Digby",
			"Sneaky Pete", "Sno Mercy"]},
	{"label": "Watch", "modes": [5, 2], "choices": ["combo showcases", "CPU vs CPU"],
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
# Knockouts: the simulation itself freezes and then runs at half speed (MatchSim's
# ko_freeze / slowmo, so online peers agree); the camera pushes in on the loser.
const KO_ZOOM := 1.45
const SHOWCASE_ZOOM := 1.9
## Room the fight camera leaves around the fighters (sides, top and bottom).
const CAM_PAD := Vector2(72, 40)

var sim: MatchSim
var _cam_zoom := 0.0  ## eased toward a zoom that fits the fighters (0: snap on the next frame)
var replay: Replay
var arena: ArenaView
var crowd: CrowdView
var entities: Node2D
var views: Array[CreatureView] = []
var fx: FxView
var fx_ground: FxGround
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
var wins := [0, 0]
var timer := ROUND_TICKS
var seed_base := 1
## --menu=PAGE: open "single" or "settings" on start (captures).
var _menu_arg := ""
var _setting_rows := {}  ## Settings key -> its OptionRow, while the page is open
var _match_over_status: Label = null
var _recent_servers: Array = []
var fullscreen := false
var fight_fps := DEFAULT_FPS
## Where settings are kept (tests point it elsewhere, so they never touch the player's).
var settings_path := SETTINGS_PATH
var vsync := true
## Wider-than-16:9 screens (ultrawide, 16:10): fill them with more stadium, or keep 16:9
## with bars.
var wide_fill := true
var rumble := true
var shake_scale := 1.0  ## screen shake: 1 full, 0.5 reduced, 0 off
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
var shake := 0.0
var _ko_cam_t := -1
var _ko_focus := Vector2.ZERO
var _ko_pos := Vector2.ZERO
var _cam_follow := Vector2.ZERO
var showcase: Showcase = null
var duel: DuelSim = null
## A team battle (2v2, 3v3): every creature on the field, one per slot (TeamSim).
var team_battle: TeamSim = null
## Combo Trials or a Reaction Drill: drives the partner and judges the player.
var coach = null
var _row_choice: Array = []
var player2_input := PlayerInput.new()
var _teams: Array = DEFAULT_TEAMS.duplicate(true)
var _skip_select := false
var _cpu_vs_cpu := false
var _showcase_list: Array = []
var _showcase_arg := ""  ## --showcase=NAME: loop just that one
var _showcase_i := 0
var _showcase_end_t := 0
var autoplay: AutoPlay = null
var frame_count := 0
var _shots := {}
var _shot_dir := "user://shots"
var _quit_after := 0

# Online
var netplay: Netplay = null
var online: OnlineMatch = null  ## the online match being shown
var lobby: OnlineLobby
var _online_fighter := "cairn"
var _online_address := ""
## Settings > Game > Online server: the server Quick match and rooms use ("" = the
## game's own, from data/online.json).
var _online_server := ""
## Looking for the server on this network before joining it (see LanFinder), and the
## join to make when it's done: [fighter, host, port, room].
var _finder: LanFinder = null
var _finder_join: Array = []
## Where the look-up asks (tests ask this machine instead of the whole network).
var finder_target := "255.255.255.255"
## The last look-up found nothing nearby, so a failed join can say what to check at home.
var _home_missed := false
var _net_args := {}  ## from the command line: host / join / lag / delay / report
var _net_end_t := 0
## How many of the online match's slots were shown as the server's CPU.
var _cpu_shown := 0


func _ready() -> void:
	if _run_sim_check() or _run_server():
		return
	Controls.setup()
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
	fx_ground = FxGround.new()
	add_child(fx_ground)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	fx = FxView.new()
	fx.bind_ground(fx_ground)
	add_child(fx)
	audio = AudioView.new()
	add_child(audio)
	fx.cue.connect(audio.play)
	debug = DebugView.new()
	debug.visible = false
	add_child(debug)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
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
	_row_choice.resize(MENU_ROWS.size())
	_row_choice.fill(0)
	player2_input.keyboard = false
	player2_input.pad_device = PlayerInput.NO_PAD

	_load_settings()
	var start_mode := _parse_args()
	_apply_device()
	_open_menu(_menu_arg)  # also starts the background match the pick screen sits on
	if start_mode >= 0:
		_start_match(start_mode)
	if _net_args.has("host") or _net_args.has("join"):
		_open_lobby()
		if _net_args.has("host"):
			_net_host(_online_fighter)
		else:
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
	var land := focus if focus != "" else ("settings" if page in SETTING_PAGES or page == "controls" else page)
	var t := TitleScreen.new(land)
	t.single_pressed.connect(_open_single)
	t.online_pressed.connect(func(): _start_match(ONLINE_MODE))
	t.settings_pressed.connect(_open_settings)
	t.exit_pressed.connect(func(): get_tree().quit())
	ui.push(t)
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
	scr.logo = true
	scr.title = "SINGLE PLAYER"
	scr.row_width = 250.0
	scr.row_height = 13.0
	scr.row_font = 8
	scr.row_gap = 1
	scr.hints = ["move", "change", "select", "back"]
	scr.builder = func(s: UiScreen):
		for r in MENU_ROWS.size():
			var row: Dictionary = MENU_ROWS[r]
			var desc := String(row.get("desc", ""))
			if row.has("choices"):
				var o := s.add_option(String(row["label"]), row["choices"], int(_row_choice[r]),
					func(i: int): _row_choice[r] = i, desc)
				o.activates = true
				o.activated.connect(func():
					ui.notify_chosen()
					_start_row(r))
			else:
				s.add_button(String(row["label"]), func(): _start_row(r), desc)
		s.add_space(4)
		s.add_button("Back", s.back)
	ui.push(scr)


func _start_row(row: int) -> void:
	var r: Dictionary = MENU_ROWS[row]
	_start_match(int(r["modes"][_row_choice[row] if row < _row_choice.size() else 0]))


## Settings: four pages, like most games: Game, Video, Audio, Controls.
func _open_settings() -> void:
	var scr := UiScreen.new()
	scr.logo = true
	scr.title = "SETTINGS"
	scr.row_width = 200.0
	scr.builder = func(s: UiScreen):
		s.add_button("Game", func(): _open_settings_page("game"),
				"CPU level, controller rumble, screen shake, online server")
		s.add_button("Video", func(): _open_settings_page("video"), "Fullscreen, wide screens, vsync, frame rate")
		s.add_button("Audio", func(): _open_settings_page("audio"), "Volume for the music, effects and menus")
		s.add_button("Controls", _open_controls, "Keyboard and controller layouts; remap keys and buttons")
		s.add_space(4)
		s.add_button("Back", s.back)
	ui.push(scr)


## One Settings page: each row's values and description come from _setting(); a change
## goes through _set_setting() and is saved at once.
func _open_settings_page(page: String) -> void:
	var scr := UiScreen.new()
	scr.logo = true
	scr.title = "SETTINGS  -  " + page.to_upper()
	scr.row_width = 270.0
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
	scr.title = "SETTINGS  -  CONTROLS"
	scr.row_width = 250.0
	scr.hints = ["move", "change", "select", "back"]
	scr.builder = func(s: UiScreen):
		_add_setting_row(s, "layout")
		_add_setting_row(s, "pad_layout")
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


## `keep_teams`: a rematch with the same teams (no pick screen).
func _start_match(m: int, keep_teams := false) -> void:
	_close_ui()
	mode = m
	wins = [0, 0]
	round_num = 1
	hud.menu_visible = false
	_save_settings()
	var cfg: Dictionary = MODES[m]
	if cfg.get("online", false):
		_open_lobby()
		return
	var two_players: bool = Side.PLAYER2 in cfg.get("sides", [])
	_assign_devices(two_players)
	if _has_pick(cfg) and not keep_teams and not _skip_select:
		flow = Flow.SELECT
		flow_t = 0
		hud.visible = false
		var size := int(DuelSim.load_rules().get("team_size", 3)) if cfg.get("duel", false) else 1
		var labels := ["PLAYER 1", "PLAYER 2" if two_players else "CPU"]
		var title := "DUEL" if cfg.get("duel", false) else "VERSUS"
		if cfg.has("team"):
			size = int(cfg["team"])
			labels = ["YOU + CPU", "CPU TEAM"]
			title = "TEAM BATTLE  %d v %d" % [size, size]
		var pick := CharacterSelect.new()
		pick.setup(title, size, labels, two_players, _padded_teams(size) if cfg.has("team") else _teams)
		pick.p1_keyboard = player_input.keyboard
		pick.p1_pad = player_input.pad_device
		pick.p2_pad = player2_input.pad_device
		pick.chosen.connect(_on_teams_chosen)
		pick.cancelled.connect(func(): _open_menu("single"))
		ui.push(pick)
		return
	_start_round()


## Modes that open the pick screen first.
func _has_pick(cfg: Dictionary) -> bool:
	return cfg.get("duel", false) or cfg.get("versus2p", false) or cfg.has("team")


func _on_teams_chosen(teams: Array) -> void:
	_close_ui()
	hud.visible = true
	_teams = teams
	audio.play("ui_select", 0.0, 1.0, true)
	_start_round()


## Local 2-player: with two controllers each player gets one (player 1 keeps the
## keyboard too); with one, player 1 uses keyboard and mouse and player 2 the controller.
func _assign_devices(two_players: bool) -> void:
	var pads := Input.get_connected_joypads()
	player_input.keyboard = true
	player_input.pad_device = PlayerInput.ANY_PAD
	player2_input.pad_device = PlayerInput.NO_PAD
	if not two_players:
		return
	if pads.size() >= 2:
		player_input.pad_device = pads[0]
		player2_input.pad_device = pads[1]
	elif pads.size() == 1:
		player_input.pad_device = PlayerInput.NO_PAD
		player2_input.pad_device = pads[0]
	else:
		hud.show_toast("Connect a controller for player 2")


func _start_round() -> void:
	audio.play_music("fight")
	var cfg: Dictionary = MODES[mode]
	_end_duel()
	_end_coach()
	if cfg.get("duel", false):
		_start_duel()
		return
	if cfg.has("team"):
		_start_team(int(cfg["team"]))
		return
	if cfg.get("trials", false):
		coach = ComboTrials.new(Callable(player_input, "label"))
		_start_coach("F2 watch the demo again    F4 next trial    Esc menu")
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
		_new_sim(MatchFactory.training(String(cfg["left"])), [Side.PLAYER, Side.DUMMY])
		hud.timer_ticks = -1
		hud.banner = ""
		flow = Flow.FIGHT
		flow_t = 0
		return
	if cfg.get("versus2p", false):
		_new_sim(MatchFactory.versus(String(_teams[0][0]), String(_teams[1][0])), cfg["sides"])
	else:
		_new_sim(MatchFactory.versus(String(cfg["left"]), String(cfg["right"])), cfg["sides"])
	timer = ROUND_TICKS
	hud.timer_ticks = timer
	hud.wins = wins
	flow = Flow.INTRO
	flow_t = 0


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
func _start_team(per_side: int) -> void:
	_teams = _padded_teams(per_side)
	team_battle = TeamSim.new(_teams, per_side)
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
	flow = Flow.FIGHT
	flow_t = 0


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
			hud.banner = ("ONLINE TEAM BATTLE" if online != null else "TEAM BATTLE") if t < 60 else "FIGHT!"
			hud.banner_sub = "%d v %d" % [team_battle.size, team_battle.size] if t < 60 else ""
			if t == 2 or t == 60:
				audio.play("round_start", 0.0, 0.75 if t == 2 else 1.0)
		TeamSim.Phase.FIGHT:
			hud.banner = ""
			hud.banner_sub = ""
		TeamSim.Phase.OVER:
			if team_battle.phase_t == 1:
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
				hud.banner_sub = ""


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
	if hud != null:
		hud.duel = null
		hud.team = null
		hud.wins_needed = WINS_NEEDED


func _duel_flow() -> void:
	hud.timer_ticks = maxi(duel.timer, 0)
	match duel.phase:
		DuelSim.Phase.INTRO:
			var t := duel.phase_t
			hud.banner = ("ONLINE DUEL" if online != null else "DUEL") if t < 60 else "FIGHT!"
			if (duel.teams[0] as Array).size() > 1:
				hud.banner_sub = "%d v %d  -  tag with %s" % [duel.teams[0].size(), duel.teams[1].size(),
					player_input.label("tag")] if t < 60 else ""
			else:
				hud.banner_sub = "1 v 1" if t < 60 else ""
			if t == 2 or t == 60:
				audio.play("round_start", 0.0, 0.75 if t == 2 else 1.0)
		DuelSim.Phase.FIGHT, DuelSim.Phase.SWAP:
			hud.banner = ""
			hud.banner_sub = ""
		DuelSim.Phase.OVER:
			if duel.phase_t == 1:
				hud.banner = "K.O." if duel.timer > 0 else "TIME"
				hud.banner_sub = ""
			if duel.phase_t >= int(duel.rules.get("over_ticks", 150)):
				flow = Flow.MATCH_OVER
				flow_t = 0
				if duel.winner < 0:
					hud.banner = "DRAW"
				elif online != null:
					hud.banner = "YOU WIN!" if duel.winner == online.local_side else "YOU LOSE"
				else:
					hud.banner = "%s WINS!" % _side_name(duel.winner)
				hud.banner_sub = ""


func _side_name(i: int) -> String:
	match sides[i]:
		Side.PLAYER:
			return "YOU" if online != null else "PLAYER 1"
		Side.REMOTE:
			return "OPPONENT"
		Side.PLAYER2:
			return "PLAYER 2"
		Side.CPU:
			return "CPU"
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
	sim = s
	_cam_zoom = 0.0  # frame the new fight straight away
	sides = p_sides.duplicate()
	while sides.size() < sim.creatures.size():
		sides.append(Side.CPU)  # a team battle's other slots
	if _cpu_vs_cpu:
		for i in sides.size():
			if sides[i] == Side.PLAYER or sides[i] == Side.PLAYER2:
				sides[i] = Side.CPU
	replay = Replay.new()
	cpus = []
	cpus.resize(sides.size())
	hud.resize_slots(sides.size())
	for i in sides.size():
		if sides[i] == Side.CPU:
			cpus[i] = CpuController.new(i, level, seed_base * 101 + round_num * 7 + i)
	arena.set_terrain(sim.terrain)
	for v in views:
		v.queue_free()
	views.clear()
	for c in sim.creatures:
		var v := CreatureView.new()
		entities.add_child(v)
		v.setup(c)
		views.append(v)
	debug.sim = sim
	hud.sim = sim
	fx.sim = sim
	fx.clear()
	fx.views = views
	_ko_cam_t = -1
	hud.dummy_mode_name = DUMMY_MODES[dummy_mode]
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
			Side.CPU:
				label = "CPU"
			Side.REMOTE:
				label = "ONLINE"
			Side.SCRIPT:
				label = ""
		if sim.creatures[i].is_dummy:
			label = ""
		fx.side_marks.append({"color": Hud.SIDE_COLORS[clampi(sim.creatures[i].team, 0, 1)], "label": label})
	for i in sides.size():
		match sides[i]:
			Side.PLAYER:
				hud.tags[i] = "P1"
			Side.CPU:
				hud.tags[i] = "CPU " + LEVEL_NAMES[level]
				hud.key_labels[i] = ["", ""]
			Side.SCRIPT:
				hud.tags[i] = "DEMO"
				hud.key_labels[i] = ["", ""]
			Side.PLAYER2:
				hud.tags[i] = "P2"
			Side.REMOTE:
				hud.tags[i] = "ONLINE"
				hud.key_labels[i] = ["", ""]
			_:
				hud.tags[i] = ""
	shake = 0.0
	player_input.reset()
	player2_input.reset()
	_apply_device()


func _physics_process(_delta: float) -> void:
	if sim == null:
		return  # quitting after --sim-check
	frame_count += 1
	_apply_frame_rate()
	if paused:
		_capture()
		return  # frozen behind the pause menu: nothing steps, the picture holds
	flow_t += 1
	if _finder != null:
		_finder_step()
	var live := flow == Flow.FIGHT or flow == Flow.MENU
	var events: Array = sim.events
	if online != null:
		# Online: the rollback session steps the duel (maybe several frames, maybe none
		# while it waits); the views get only the events they haven't shown yet.
		live = flow == Flow.FIGHT or flow == Flow.MATCH_OVER
		netplay.tick(_side_bits(online.local_slot, live and not ui.is_open()))
		events = online.events
		_online_status()
	elif netplay != null and _connecting_step():
		events = online.events  # the online match began this frame: its session steps it
	else:
		var inputs := PackedInt32Array()
		for i in sides.size():
			inputs.append(_side_bits(i, live))
		if showcase != null and flow == Flow.FIGHT:
			inputs = showcase.inputs(sim)
		elif coach != null and flow == Flow.FIGHT:
			inputs = coach.inputs(_side_bits(0, true))
		if flow == Flow.FIGHT:
			replay.record(inputs)
		if duel != null:
			duel.step(inputs)
		elif team_battle != null:
			team_battle.step(inputs)
		else:
			sim.step(inputs)
		events = sim.events
	for e in events:
		_react(e)
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

	arena.refresh()
	crowd.advance()
	fx.advance()
	hud.advance()
	for v in views:
		v.see_through = _hides_someone(v.c)
		v.refresh()
	if debug.visible:
		debug.queue_redraw()

	shake = maxf(shake, fx.shake_out)
	fx.shake_out = 0.0
	if sim.ko_freeze <= 0:
		shake *= 0.82
	_update_camera()
	var sh := shake * shake_scale
	camera.offset = Vector2(randf_range(-sh, sh), randf_range(-sh, sh)).round() if sh > 0.3 else Vector2.ZERO
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - 0.04)
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
			hud.banner = "ROUND %d" % round_num if flow_t < 60 else "FIGHT!"
			if flow_t == 2 or flow_t == 60:
				audio.play("round_start", 0.0, 0.75 if flow_t == 2 else 1.0)
			hud.banner_sub = ""
			if flow_t >= INTRO_TICKS:
				hud.banner = ""
				flow = Flow.FIGHT
				flow_t = 0
		Flow.FIGHT:
			if duel != null:
				_duel_flow()
				return
			if team_battle != null:
				_team_flow()
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
			if ko != -2 or timer <= 0:
				_end_round(ko)
		Flow.ROUND_OVER:
			if flow_t >= ROUND_OVER_TICKS:
				if wins[0] >= WINS_NEEDED or wins[1] >= WINS_NEEDED:
					flow = Flow.MATCH_OVER
					flow_t = 0
					var w := 0 if wins[0] >= WINS_NEEDED else 1
					hud.banner = "%s WINS!" % String(sim.creatures[w].def["name"]).to_upper()
					hud.banner_sub = ""
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
		Side.PLAYER2:
			return player2_input.bits(sim, i, Vector2.ZERO)
		Side.REMOTE:
			return 0  # arrives over the network
		Side.CPU:
			return (cpus[i] as CpuController).bits(sim)
		Side.DUMMY:
			return _dummy_bits()
	return 0


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


func _react(e: Dictionary) -> void:
	fx.spawn(e)
	audio.on_event(e)
	var power: float = e["power"]
	_rumble(e)
	match String(e["type"]):
		"hit":
			shake = maxf(shake, 1.5 + power * 0.2)
			crowd.cheer(0.1 + power * 0.015)
		"block":
			shake = maxf(shake, 1.0)
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
			_flash(Color(1, 0.95, 0.75), 0.55)
			shake = maxf(shake, 3.0)
			crowd.cheer(0.6)
			var who := int(e.get("who", 0))
			hud.cut_in(sim.creatures[who], clampi(sim.creatures[who].team, 0, 1), String(e.get("name", "Surge")))
		"duel_over":
			crowd.roar(150)
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
	for o in sim.creatures:
		if o == c or o.state in [CreatureSim.State.KO, CreatureSim.State.FALLING]:
			continue
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
	var size := SimDefs.arena_size()  # the whole stadium
	var view := get_viewport().get_visible_rect().size  # the screen (wider on ultrawide)
	var base_z := 1.0
	var base_focus := size * 0.5
	var ko_focus := _ko_focus
	if sim != null and showcase == null and coach == null:
		_frame_fight(view, size)
		base_z = _cam_zoom
		base_focus = _cam_follow
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
		var t := float(_ko_cam_t)
		var k_in := clampf(t / 12.0, 0.0, 1.0)
		var k_out := clampf((t - 120.0) / 40.0, 0.0, 1.0)
		var amt := (1.0 - pow(1.0 - k_in, 3.0)) * (1.0 - k_out * k_out * (3.0 - 2.0 * k_out))
		z = lerpf(base_z, maxf(base_z, KO_ZOOM), amt)
		focus = base_focus.lerp(ko_focus, amt)
		if k_out >= 1.0:
			_ko_cam_t = -1
	var half := view * 0.5 / z
	camera.zoom = Vector2(z, z)
	camera.position = Vector2(_cam_axis(focus.x, half.x, size.x), _cam_axis(focus.y, half.y, size.y))


## A fight: keeps every fighter in shot, heads included, with room around them. Close
## together the camera sits at the normal 1x; as they spread out it pulls back, as far as
## showing the whole stadium.
func _frame_fight(view: Vector2, size: Vector2) -> void:
	var box := Rect2()
	var any := false
	for c in sim.creatures:
		if c.state == CreatureSim.State.KO and _ko_cam_t < 0:
			continue
		var body := Rect2(c.pos - Vector2(0, float(c.def.get("fx_top", 32)) + c.air_height()), Vector2.ZERO)
		body = body.expand(c.pos)
		box = body if not any else box.merge(body)
		any = true
	if not any:
		return
	box = box.grow_individual(CAM_PAD.x, CAM_PAD.y + 24.0, CAM_PAD.x, CAM_PAD.y)  # the HUD sits up top
	var whole := minf(view.x / size.x, view.y / size.y)  # zoom that shows the whole stadium
	var fit := clampf(minf(view.x / box.size.x, view.y / box.size.y), minf(whole, 1.0), 1.0)
	var mid := box.get_center()
	if _cam_zoom <= 0.0:
		_cam_zoom = fit
		_cam_follow = mid
	else:
		# Pull back quickly (nobody leaves the shot), push in gently.
		_cam_zoom = lerpf(_cam_zoom, fit, 0.12 if fit < _cam_zoom else 0.03)
		_cam_follow = _cam_follow.lerp(mid, 0.1)


## Keeps the arena filling the screen along one axis; when the screen shows more than
## the arena (an ultrawide's width), the arena stays centred and the stadium fills the rest.
static func _cam_axis(v: float, half: float, arena: float) -> float:
	if half * 2.0 >= arena:
		return arena * 0.5
	return clampf(v, half, arena - half)


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
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
	if ui.is_open():
		return  # the screen on top has the input
	if flow == Flow.MENU or flow == Flow.SELECT or flow == Flow.LOBBY or flow == Flow.MATCH_OVER:
		return  # their screens take the input
	if event.is_action_pressed("pause") and showcase != null:
		_open_menu()  # a demo: straight back
	elif event.is_action_pressed("pause"):
		_open_pause()
	elif event.is_action_pressed("debug_hitboxes"):
		debug.visible = not debug.visible
		debug.queue_redraw()
	elif event.is_action_pressed("debug_dummy_mode") and coach is ComboTrials:
		coach.replay_demo()
	elif event.is_action_pressed("reset") and coach is ComboTrials:
		coach.skip(1)
	elif event.is_action_pressed("debug_dummy_mode"):
		dummy_mode = (dummy_mode + 1) % DUMMY_MODES.size()
		hud.dummy_mode_name = DUMMY_MODES[dummy_mode]
		hud.show_toast("Dummy: " + DUMMY_MODES[dummy_mode])
	elif event.is_action_pressed("debug_help"):
		hud.show_help = not hud.show_help
	elif event.is_action_pressed("save_replay"):
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		var path := "user://replays/replay_%s.json" % stamp
		if replay.save(path) == OK:
			hud.show_toast("Replay saved: %d ticks" % replay.frames.size())
			print("Replay saved to ", ProjectSettings.globalize_path(path))
		else:
			hud.show_toast("Could not save replay")
	elif event.is_action_pressed("reset") and MODES[mode].get("training", false):
		_start_round()
		hud.show_toast("Reset")


## Back in a menu: Esc, B or View.
static func _back_pressed(event: InputEvent) -> bool:
	return event.is_action_pressed("menu_back") or event.is_action_pressed("ui_cancel")


## Start / Esc / View in a fight. Offline the match freezes behind the pause menu; online
## it can't, so it asks whether to leave while the match carries on (your fighter stands
## still meanwhile).
func _open_pause() -> void:
	if online != null:
		var c := ConfirmScreen.new("Leave the match?", "The match keeps going while this is open.", "Leave", "Stay")
		c.answered.connect(func(yes: bool): if yes: _leave_online())
		ui.push(c)
		return
	paused = true
	var p := PauseScreen.new(true, player_input.help_text().replace("   ", "\n").replace("  ", "\n"))
	p.resumed.connect(func(): paused = false)
	p.restart_requested.connect(func():
		_close_ui()
		seed_base += 1
		_start_match(mode, true))
	p.quit_requested.connect(func():
		_close_ui()
		_open_menu())
	ui.push(p)


func _close_ui() -> void:
	ui.clear()
	paused = false


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
		"rumble":
			return {"label": "Controller rumble", "values": ["Off", "On"], "index": 1 if rumble else 0,
				"desc": "A buzz when you land a hit or get hit"}
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
			"fps":
				fight_fps = int(FPS_CHOICES[clampi(i, 0, FPS_CHOICES.size() - 1)])
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
func _set_pad_layout(lay: String) -> void:
	player_input.pad_layout = lay
	player2_input.pad_layout = lay


## Updates prompts, help text and the mouse cursor for the current device and layout.
func _apply_device() -> void:
	hud.resize_slots(sides.size())
	for i in sides.size():
		var pin: PlayerInput = null
		if sides[i] == Side.PLAYER:
			pin = player_input
		elif sides[i] == Side.PLAYER2:
			pin = player2_input
		if pin != null:
			hud.key_labels[i] = [pin.label("skill_1"), pin.label("skill_2")]
			hud.surge_labels[i] = pin.label("surge")
			hud.tag_labels[i] = pin.label("tag")
		else:
			hud.key_labels[i] = ["", ""]
			hud.surge_labels[i] = ""
			hud.tag_labels[i] = ""
	hud.help_text = player_input.help_text(team_battle == null)
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
		shake_scale = float(cfg.get_value("game", "shake", 1.0))
		Controls.apply_overrides(cfg.get_value("controls", "bindings", {}))
		var fps := int(cfg.get_value("video", "fight_fps", DEFAULT_FPS))
		fight_fps = fps if fps in FPS_CHOICES else DEFAULT_FPS


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "layout", player_input.layout)
	cfg.set_value("input", "pad_layout", player_input.pad_layout)
	cfg.set_value("game", "level", level)
	cfg.set_value("audio", "music_muted", audio.music_muted)
	cfg.set_value("online", "fighter", _online_fighter)
	cfg.set_value("online", "address", _online_address)
	cfg.set_value("online", "server", _online_server)
	cfg.set_value("online", "recent", _recent_servers)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "fight_fps", fight_fps)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "wide_fill", wide_fill)
	cfg.set_value("game", "rumble", rumble)
	cfg.set_value("game", "shake", shake_scale)
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
		elif a.begins_with("--mode="):
			start = clampi(int(a.get_slice("=", 1)), 0, MODES.size() - 1)
			_skip_select = true  # straight into the match with the default teams
		elif a == "--pick":
			pick = true
		elif a == "--cpu-vs-cpu":
			_cpu_vs_cpu = true
		elif a.begins_with("--teams="):
			# --teams=cairn,culvert,cairn:culvert,cairn,culvert
			var halves := a.get_slice("=", 1).split(":")
			if halves.size() == 2:
				_teams = [Array(halves[0].split(",")), Array(halves[1].split(","))]
		elif a.begins_with("--level="):
			level = clampi(int(a.get_slice("=", 1)), 0, LEVEL_NAMES.size() - 1)
		elif a.begins_with("--seed="):
			seed_base = int(a.get_slice("=", 1))
		elif a.begins_with("--dummy-mode="):
			dummy_mode = clampi(int(a.get_slice("=", 1)), 0, DUMMY_MODES.size() - 1)
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
		elif a.begins_with("--menu="):
			var page := a.get_slice("=", 1)
			if page in ["main", "single", "settings", "game", "video", "audio", "controls"]:
				_menu_arg = "" if page == "main" else page
		elif a.begins_with("--fighter="):
			var f := a.get_slice("=", 1)
			if f in MatchFactory.FIGHTERS:
				_online_fighter = f
		elif a.begins_with("--net-lag="):
			_net_args["lag"] = int(a.get_slice("=", 1))
		elif a.begins_with("--net-loss="):
			_net_args["loss"] = float(a.get_slice("=", 1))
		elif a.begins_with("--online-size="):
			_net_args["size"] = clampi(int(a.get_slice("=", 1)), 1, 3)
		elif a.begins_with("--net-delay="):
			_net_args["delay"] = int(a.get_slice("=", 1))
		elif a.begins_with("--net-report="):
			_net_args["report"] = a.get_slice("=", 1)
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
	flow = Flow.LOBBY
	flow_t = 0
	hud.menu_visible = false
	hud.visible = false
	_close_ui()
	lobby = OnlineLobby.new(_online_fighter, _online_address, _recent_servers, online_server())
	lobby.server_join_pressed.connect(_net_join_server)
	lobby.host_pressed.connect(_net_host)
	lobby.join_pressed.connect(_net_join_typed)
	lobby.cancelled.connect(_leave_online)
	ui.push(lobby)


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
	netplay.forced_delay = int(_net_args.get("delay", -1))
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
	netplay.forced_delay = int(_net_args.get("delay", -1))
	var link := _make_link(0, address, port)
	if link.status == NetLink.Status.CLOSED:
		lobby.busy = false
		lobby.status = link.error
		lobby.status_bad = true
		netplay = null
		return
	netplay.room = room
	netplay.team_size = size
	netplay.join(address, port, [fighter], link)
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
	lobby.status_bad = netplay.phase == Netplay.Phase.ENDED
	if netplay.phase == Netplay.Phase.ENDED:
		if _home_missed and netplay.error.begins_with("No answer"):
			lobby.status = HOME_HINT
		lobby.busy = false
		netplay = null
		return
	if netplay.is_playing():
		_start_online_match()


func _start_online_match() -> void:
	online = netplay.game
	_close_ui()  # the lobby, or a match-over screen on a rematch
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
		_new_sim(team_battle.sim, s)
		hud.team = team_battle
		hud.focus = online.local_slot
		hud.timer_ticks = team_battle.timer
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
	if netplay.game != online and netplay.is_playing():
		_write_net_report()
		_start_online_match()  # a rematch began
		return
	if netplay.phase == Netplay.Phase.ENDED:
		_net_end_t += 1
		if _net_end_t == 1:
			_write_net_report()
			hud.banner = "DISCONNECTED"
			hud.banner_sub = netplay.error
			hud.net_info = ""
		if _net_end_t > 240:
			_leave_online()
		return
	var g := online
	if g.cpu_slots.size() != _cpu_shown:
		_show_cpu_slots()
		hud.show_toast("A player left: a CPU plays for them")
	hud.net_info = "PING %d ms   DELAY %d   ROLLBACK %d" % [roundi(netplay.ping_ms), g.input_delay,
		g.session.max_rollback_seen]
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
		if g.players > 2 and (netplay.rematch_local or asked > 0):
			_match_over_status.text = "Rematch: %d of %d asked" % [asked + (1 if netplay.rematch_local else 0),
				others + 1]
		elif netplay.rematch_local:
			_match_over_status.text = "Waiting for the other player..."
		elif netplay.rematch_remote:
			_match_over_status.text = "The other player wants a rematch!"


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
		if online != null:
			var again := s.add_button("Rematch", func(): pass, "Play again; it starts when everyone asks")
			again.pressed.connect(func():
				netplay.request_rematch()
				again.disabled = true
				again.text = "Rematch asked")
			s.add_button("Leave", _leave_online, "Back to the title menu")
			_match_over_status = s.add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
			s.on_back = _leave_online
		else:
			s.add_button("Rematch", func():
				seed_base += 1
				_start_match(mode, true), "The same fighters again")
			if _has_pick(cfg) and not _skip_select:
				s.add_button("Change fighters", func(): _start_match(mode), "Back to the pick screen")
			s.add_button("Main menu", func(): _open_menu(), "Back to the title menu")
			s.on_back = func(): _open_menu()
	ui.push(scr)


func _end_online() -> void:
	if _finder != null:
		_finder.cancel()
	_finder = null
	netplay = null
	online = null
	if hud != null:
		hud.net_info = ""


## --net-report=PATH: the match's inputs and state fingerprints as JSON, so two
## machines' reports can be compared (or a desync replayed). Also written on a desync.
func _write_net_report() -> void:
	if online == null:
		return
	var path := String(_net_args.get("report", ""))
	if path == "" and online.desync_frame < 0:
		return
	if path == "":
		DirAccess.make_dir_recursive_absolute("user://desyncs")
		path = "user://desyncs/desync_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(online.report()))
		f.close()


func _capture() -> void:
	var t := frame_count
	if _shots.has(t):
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		get_viewport().get_texture().get_image().save_png(_shot_dir.path_join("shot_%04d.png" % t))
	if _quit_after > 0 and t >= _quit_after:
		_write_net_report()
		get_tree().quit()
