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
##   --pad-layout=standard|twinstick  controller layout (saved in the menu otherwise)
##   --showcase=NAME       play one scripted demo on a loop: cairn, culvert, craglash or counterplay
##   --teams=a,b,c:d,e,f   Duel / 2-player teams (default craglash,cairn,culvert:culvert,cairn,craglash)
##   --pick                show the team pick screen even with --mode
##   --cpu-vs-cpu          every player side is played by the CPU (demos, captures)

enum Flow { MENU, INTRO, FIGHT, ROUND_OVER, MATCH_OVER, SELECT }
enum Side { PLAYER, CPU, DUMMY, SCRIPT, PLAYER2 }

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
]
## The menu. MODES indexes stay stable for --mode=N; rows with choices pick one of
## several modes with left/right.
const MENU_ROWS := [
	{"label": "Duel: you vs CPU  (3v3 tag)", "modes": [6]},
	{"label": "Duel: 2 players", "modes": [7]},
	{"label": "Versus: 2 players", "modes": [8]},
	{"label": "Versus CPU", "modes": [0, 1, 12], "choices": ["as Cairn", "as Culvert", "as Craglash"]},
	{"label": "Combo Trials", "modes": [9]},
	{"label": "Reaction Drill", "modes": [10, 11], "choices": ["read Culvert", "read Cairn"]},
	{"label": "Training", "modes": [3, 4, 13], "choices": ["Cairn", "Culvert", "Craglash"]},
	{"label": "Watch", "modes": [5, 2], "choices": ["combo showcases", "CPU vs CPU"]},
]
const DEFAULT_TEAMS := [["craglash", "cairn", "culvert"], ["culvert", "cairn", "craglash"]]
const LEVEL_NAMES := ["Easy", "Normal", "Hard"]
const DUMMY_MODES := ["Stand", "Guard", "Walk", "Dodge"]
const ROUND_TICKS := 90 * 60
const WINS_NEEDED := 2
const INTRO_TICKS := 90
const ROUND_OVER_TICKS := 210
const SETTINGS_PATH := "user://settings.cfg"
const MENU_Y0 := 88.0
const MENU_DY := 13.0
# Knockouts: the simulation itself freezes and then runs at half speed (MatchSim's
# ko_freeze / slowmo, so online peers agree); the camera pushes in on the loser.
const KO_ZOOM := 1.45
const SHOWCASE_ZOOM := 1.9

var sim: MatchSim
var _cam_zoom := 0.0  ## showcase/coach zoom, eased toward a fit of both fighters
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
var menu_index := 0
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
## Combo Trials or a Reaction Drill: drives the partner and judges the player.
var coach = null
var _row_choice: Array = []
var team_select: TeamSelect
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


func _ready() -> void:
	if _run_sim_check():
		return
	Controls.setup()
	camera = Camera2D.new()
	camera.position = Vector2(SimDefs.VIEW_W, SimDefs.VIEW_H) * 0.5
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
	flash_rect.size = Vector2(SimDefs.VIEW_W, SimDefs.VIEW_H)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.size = Vector2(SimDefs.VIEW_W, SimDefs.VIEW_H)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade_rect)
	hud = Hud.new()
	layer.add_child(hud)
	hud.menu_y0 = MENU_Y0
	hud.menu_dy = MENU_DY
	team_select = TeamSelect.new()
	team_select.visible = false
	layer.add_child(team_select)
	team_select.chosen.connect(_on_teams_chosen)
	team_select.cancelled.connect(_open_menu)
	player2_input.keyboard = false
	player2_input.pad_device = PlayerInput.NO_PAD

	_load_settings()
	var start_mode := _parse_args()
	_apply_device()
	_open_menu()  # also starts the background match the pick screen sits on
	if start_mode >= 0:
		_start_match(start_mode)


# ------------------------------------------------------------------ flow

func _open_menu() -> void:
	flow = Flow.MENU
	flow_t = 0
	_end_showcase()
	_end_duel()
	_end_coach()
	team_select.close()
	hud.visible = true
	audio.play_music("menu")
	# A CPU-vs-CPU match plays behind the menu.
	_new_sim(MatchFactory.versus("cairn", "culvert"), [Side.CPU, Side.CPU])
	hud.timer_ticks = -1
	hud.banner = ""
	hud.menu_visible = true
	_refresh_menu()


func _refresh_menu() -> void:
	var items: Array[String] = []
	if _row_choice.size() != MENU_ROWS.size():
		_row_choice.resize(MENU_ROWS.size())
		_row_choice.fill(0)
	for r in MENU_ROWS.size():
		var row: Dictionary = MENU_ROWS[r]
		var label := String(row["label"])
		if row.has("choices"):
			label += ":  < %s >" % String(row["choices"][_row_choice[r]])
		items.append(label)
	items.append("CPU level:  < %s >" % LEVEL_NAMES[level])
	items.append("Keyboard:  < %s >" % PlayerInput.LAYOUT_NAMES[player_input.layout])
	items.append("Controller:  < %s >" % PlayerInput.PAD_LAYOUT_NAMES[player_input.pad_layout])
	hud.menu_items = items
	hud.menu_index = menu_index
	hud.menu_footer = "Xbox controller works any time. Twin-stick: the right stick aims 360 and holds your facing."


## `keep_teams`: a rematch with the same teams (no pick screen).
func _start_match(m: int, keep_teams := false) -> void:
	mode = m
	wins = [0, 0]
	round_num = 1
	hud.menu_visible = false
	_save_settings()
	var cfg: Dictionary = MODES[m]
	var two_players: bool = Side.PLAYER2 in cfg.get("sides", [])
	_assign_devices(two_players)
	if (cfg.get("duel", false) or cfg.get("versus2p", false)) and not keep_teams and not _skip_select:
		flow = Flow.SELECT
		flow_t = 0
		hud.visible = false
		var size := int(DuelSim.load_rules().get("team_size", 3)) if cfg.get("duel", false) else 1
		var labels := ["PLAYER 1", "PLAYER 2" if two_players else "CPU"]
		team_select.open("DUEL" if cfg.get("duel", false) else "VERSUS", size, labels, _teams)
		return
	_start_round()


func _on_teams_chosen(teams: Array) -> void:
	team_select.close()
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
	if hud != null:
		hud.duel = null
		hud.wins_needed = WINS_NEEDED


func _duel_flow() -> void:
	hud.timer_ticks = maxi(duel.timer, 0)
	match duel.phase:
		DuelSim.Phase.INTRO:
			var t := duel.phase_t
			hud.banner = "DUEL" if t < 60 else "FIGHT!"
			hud.banner_sub = "3 v 3  -  tag with %s" % player_input.label("tag") if t < 60 else ""
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
				else:
					hud.banner = "%s WINS!" % _side_name(duel.winner)
				hud.banner_sub = "Enter / A: rematch     Esc / View: menu"


func _side_name(i: int) -> String:
	match sides[i]:
		Side.PLAYER:
			return "PLAYER 1"
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
	sides = p_sides.duplicate()
	if _cpu_vs_cpu:
		for i in 2:
			if sides[i] == Side.PLAYER or sides[i] == Side.PLAYER2:
				sides[i] = Side.CPU
	replay = Replay.new()
	cpus = [null, null]
	for i in 2:
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
	for i in 2:
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
	flow_t += 1
	var live := flow == Flow.FIGHT or flow == Flow.MENU
	var inputs := PackedInt32Array([_side_bits(0, live), _side_bits(1, live)])
	if showcase != null and flow == Flow.FIGHT:
		inputs = showcase.inputs(sim)
	elif coach != null and flow == Flow.FIGHT:
		inputs = coach.inputs(_side_bits(0, true))
	if flow == Flow.FIGHT:
		replay.record(inputs)
	if duel != null:
		duel.step(inputs)
	else:
		sim.step(inputs)
	for e in sim.events:
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
	camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)).round() if shake > 0.3 else Vector2.ZERO
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
				var keep := menu_index
				_open_menu()
				menu_index = keep
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
					hud.banner_sub = "Enter / A: rematch     Esc / View: menu"
				else:
					round_num += 1
					_start_round()
		Flow.MATCH_OVER:
			if duel != null:
				hud.timer_ticks = maxi(duel.timer, 0)
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
			hud.cut_in(sim.creatures[who], who, String(e.get("name", "Surge")))
		"duel_over":
			crowd.roar(150)
		"ko":
			shake = maxf(shake, 5.0)
			crowd.cheer(1.0)
			_flash(Color.WHITE, 0.6)
			if not MODES[mode].get("training", false) or flow == Flow.MENU:
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
	var size := Vector2(SimDefs.VIEW_W, SimDefs.VIEW_H)
	var base_z := 1.0
	var base_focus := size * 0.5
	var ko_focus := _ko_focus
	if (showcase != null or coach != null) and sim != null and sim.creatures.size() >= 2:
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
	var half := size * 0.5 / z
	camera.zoom = Vector2(z, z)
	camera.position = focus.clamp(half, size - half)


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	var before := player_input.label_set()
	player_input.note_event(event)
	if player_input.label_set() != before:
		_apply_device()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute_music"):
		var muted := audio.toggle_music()
		hud.show_toast("Music off (M to turn on)" if muted else "Music on")
		_save_settings()
		return
	if flow == Flow.SELECT:
		if team_select.handle(event) and flow == Flow.SELECT:
			audio.play("ui_move", 0.0, 1.0, true)
		return
	if flow == Flow.MENU:
		var before := [menu_index, level, player_input.layout, _row_choice.duplicate()]
		_menu_input(event)
		if flow != Flow.MENU:
			audio.play("ui_select", 0.0, 1.0, true)
		elif [menu_index, level, player_input.layout, _row_choice] != before:
			audio.play("ui_move", 0.0, 1.0, true)
		return
	if event.is_action_pressed("menu_back"):
		_open_menu()
	elif flow == Flow.MATCH_OVER and event.is_action_pressed("menu_confirm"):
		seed_base += 1
		_start_match(mode, true)
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


func _menu_input(event: InputEvent) -> void:
	var count := MENU_ROWS.size() + 3
	# Mouse: hover to highlight, click to choose.
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed):
		var p: Vector2 = get_global_mouse_position()
		var row := int(floor((p.y - (MENU_Y0 - MENU_DY + 4.0)) / MENU_DY))
		if p.x >= 130.0 and p.x <= 350.0 and row >= 0 and row < count:
			menu_index = row
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				if row < MENU_ROWS.size():
					_start_row(row)
					return
				_change_option(row, 1)
		_refresh_menu()
		return
	if event.is_action_pressed("ui_down"):
		menu_index = (menu_index + 1) % count
	elif event.is_action_pressed("ui_up"):
		menu_index = (menu_index + count - 1) % count
	elif event.is_action_pressed("ui_left"):
		_change_option(menu_index, -1)
	elif event.is_action_pressed("ui_right"):
		_change_option(menu_index, 1)
	elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("ui_accept"):
		if menu_index < MENU_ROWS.size():
			_start_row(menu_index)
			return
		_change_option(menu_index, 1)
	elif event.is_action_pressed("menu_back"):
		get_tree().quit()
		return
	else:
		return
	_refresh_menu()


## Left/right on the CPU level or keyboard layout rows.
func _start_row(row: int) -> void:
	var r: Dictionary = MENU_ROWS[row]
	_start_match(int(r["modes"][_row_choice[row] if row < _row_choice.size() else 0]))


func _change_option(row: int, dir: int) -> void:
	if row < MENU_ROWS.size():
		var r: Dictionary = MENU_ROWS[row]
		if r.has("choices"):
			var n: int = (r["choices"] as Array).size()
			_row_choice[row] = (int(_row_choice[row]) + dir + n) % n
	elif row == MENU_ROWS.size():
		level = (level + dir + LEVEL_NAMES.size()) % LEVEL_NAMES.size()
		_save_settings()
	elif row == MENU_ROWS.size() + 1:
		var i := PlayerInput.LAYOUTS.find(player_input.layout)
		player_input.layout = PlayerInput.LAYOUTS[(i + PlayerInput.LAYOUTS.size() + dir) % PlayerInput.LAYOUTS.size()]
		_save_settings()
		_apply_device()
	elif row == MENU_ROWS.size() + 2:
		var n := PlayerInput.PAD_LAYOUTS.size()
		var i := PlayerInput.PAD_LAYOUTS.find(player_input.pad_layout)
		_set_pad_layout(PlayerInput.PAD_LAYOUTS[(i + n + dir) % n])
		_save_settings()
		_apply_device()
	_refresh_menu()


## Both players' controllers use the same layout.
func _set_pad_layout(lay: String) -> void:
	player_input.pad_layout = lay
	player2_input.pad_layout = lay


## Updates prompts, help text and the mouse cursor for the current device and layout.
func _apply_device() -> void:
	for i in 2:
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
	hud.help_text = player_input.help_text()
	if player_input.device == PlayerInput.Device.GAMEPAD:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.set_default_cursor_shape(
			Input.CURSOR_CROSS if player_input.layout == "league" and flow != Flow.MENU else Input.CURSOR_ARROW)


## Controller rumble: a light buzz when you land a hit, a heavier one when you get hit.
func _rumble(e: Dictionary) -> void:
	if player_input.device != PlayerInput.Device.GAMEPAD or flow != Flow.FIGHT:
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
	if cfg.load(SETTINGS_PATH) == OK:
		var lay := String(cfg.get_value("input", "layout", "league"))
		if lay in PlayerInput.LAYOUTS:
			player_input.layout = lay
		var pad := String(cfg.get_value("input", "pad_layout", "standard"))
		if pad in PlayerInput.PAD_LAYOUTS:
			_set_pad_layout(pad)
		level = clampi(int(cfg.get_value("game", "level", level)), 0, LEVEL_NAMES.size() - 1)
		audio.set_music_muted(bool(cfg.get_value("audio", "music_muted", false)))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "layout", player_input.layout)
	cfg.set_value("input", "pad_layout", player_input.pad_layout)
	cfg.set_value("game", "level", level)
	cfg.set_value("audio", "music_muted", audio.music_muted)
	cfg.save(SETTINGS_PATH)


## --sim-check=SEED: print (and optionally write) the determinism fingerprint, then quit.
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


func _capture() -> void:
	var t := frame_count
	if _shots.has(t):
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		get_viewport().get_texture().get_image().save_png(_shot_dir.path_join("shot_%04d.png" % t))
	if _quit_after > 0 and t >= _quit_after:
		get_tree().quit()
