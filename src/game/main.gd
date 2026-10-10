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

enum Flow { MENU, INTRO, FIGHT, ROUND_OVER, MATCH_OVER }
enum Side { PLAYER, CPU, DUMMY }

const MODES := [
	{"label": "Cairn  vs  CPU Culvert", "left": "cairn", "right": "culvert", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Culvert  vs  CPU Cairn", "left": "culvert", "right": "cairn", "sides": [Side.PLAYER, Side.CPU]},
	{"label": "Watch: CPU vs CPU", "left": "cairn", "right": "culvert", "sides": [Side.CPU, Side.CPU]},
	{"label": "Training: Cairn", "left": "cairn", "training": true},
	{"label": "Training: Culvert", "left": "culvert", "training": true},
]
const LEVEL_NAMES := ["Easy", "Normal", "Hard"]
const DUMMY_MODES := ["Stand", "Guard", "Walk", "Dodge"]
const ROUND_TICKS := 90 * 60
const WINS_NEEDED := 2
const INTRO_TICKS := 90
const ROUND_OVER_TICKS := 160

var sim: MatchSim
var replay: Replay
var arena: ArenaView
var crowd: CrowdView
var entities: Node2D
var views: Array[CreatureView] = []
var fx: FxView
var debug: DebugView
var hud: Hud
var camera: Camera2D
var flash_rect: ColorRect

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

var dummy_mode := 0
var shake := 0.0
var autoplay: AutoPlay = null
var frame_count := 0
var _shots := {}
var _shot_dir := "user://shots"
var _quit_after := 0


func _ready() -> void:
	Controls.setup()
	camera = Camera2D.new()
	camera.position = Vector2(SimDefs.VIEW_W, SimDefs.VIEW_H) * 0.5
	add_child(camera)
	camera.make_current()

	arena = ArenaView.new()
	add_child(arena)
	crowd = CrowdView.new()
	add_child(crowd)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	fx = FxView.new()
	add_child(fx)
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
	hud = Hud.new()
	layer.add_child(hud)

	var start_mode := _parse_args()
	if start_mode >= 0:
		_start_match(start_mode)
	else:
		_open_menu()


# ------------------------------------------------------------------ flow

func _open_menu() -> void:
	flow = Flow.MENU
	flow_t = 0
	# A CPU-vs-CPU match plays behind the menu.
	_new_sim(MatchFactory.versus("cairn", "culvert"), [Side.CPU, Side.CPU])
	hud.timer_ticks = -1
	hud.banner = ""
	hud.menu_visible = true
	_refresh_menu()


func _refresh_menu() -> void:
	var items: Array[String] = []
	for m in MODES:
		items.append(String(m["label"]))
	items.append("CPU level:  < %s >" % LEVEL_NAMES[level])
	hud.menu_items = items
	hud.menu_index = menu_index
	hud.menu_footer = "Cairn: fast counter-puncher, builds stones with lights.   Culvert: grabs, shockwaves, pits."


func _start_match(m: int) -> void:
	mode = m
	wins = [0, 0]
	round_num = 1
	hud.menu_visible = false
	_start_round()


func _start_round() -> void:
	var cfg: Dictionary = MODES[mode]
	if cfg.get("training", false):
		_new_sim(MatchFactory.training(String(cfg["left"])), [Side.PLAYER, Side.DUMMY])
		hud.timer_ticks = -1
		hud.banner = ""
		flow = Flow.FIGHT
		flow_t = 0
		return
	_new_sim(MatchFactory.versus(String(cfg["left"]), String(cfg["right"])), cfg["sides"])
	timer = ROUND_TICKS
	hud.timer_ticks = timer
	hud.wins = wins
	flow = Flow.INTRO
	flow_t = 0


func _new_sim(s: MatchSim, p_sides: Array) -> void:
	sim = s
	sides = p_sides.duplicate()
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
	hud.dummy_mode_name = DUMMY_MODES[dummy_mode]
	for i in 2:
		match sides[i]:
			Side.PLAYER:
				hud.tags[i] = "P1"
				hud.key_labels[i] = ["U", "I"]
			Side.CPU:
				hud.tags[i] = "CPU " + LEVEL_NAMES[level]
				hud.key_labels[i] = ["", ""]
			_:
				hud.tags[i] = ""
	shake = 0.0


func _physics_process(_delta: float) -> void:
	frame_count += 1
	flow_t += 1
	var live := flow == Flow.FIGHT or flow == Flow.MENU
	var inputs := PackedInt32Array([_side_bits(0, live), _side_bits(1, live)])
	if flow == Flow.FIGHT:
		replay.record(inputs)
	sim.step(inputs)
	for e in sim.events:
		_react(e)
	_update_flow()

	arena.refresh()
	crowd.advance()
	fx.advance()
	hud.advance()
	for v in views:
		v.refresh()
	if debug.visible:
		debug.queue_redraw()

	shake *= 0.82
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
			hud.banner_sub = ""
			if flow_t >= INTRO_TICKS:
				hud.banner = ""
				flow = Flow.FIGHT
				flow_t = 0
		Flow.FIGHT:
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
					hud.banner_sub = "Enter: rematch     Esc: menu"
				else:
					round_num += 1
					_start_round()
		Flow.MATCH_OVER:
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
			return Controls.read_bits()
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
	var power: float = e["power"]
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
			flash_rect.color.a = 0.55
			shake = maxf(shake, 3.0)
			crowd.cheer(0.6)
		"ko":
			shake = maxf(shake, 4.0)
			crowd.cheer(1.0)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if flow == Flow.MENU:
		_menu_input(event)
		return
	if event.is_action_pressed("menu_back"):
		_open_menu()
	elif flow == Flow.MATCH_OVER and event.is_action_pressed("menu_confirm"):
		seed_base += 1
		_start_match(mode)
	elif event.is_action_pressed("debug_hitboxes"):
		debug.visible = not debug.visible
		debug.queue_redraw()
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
	var count := MODES.size() + 1
	if event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		menu_index = (menu_index + 1) % count
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		menu_index = (menu_index + count - 1) % count
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		level = maxi(0, level - 1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		level = mini(LEVEL_NAMES.size() - 1, level + 1)
	elif event.is_action_pressed("menu_confirm"):
		if menu_index < MODES.size():
			_start_match(menu_index)
			return
		level = (level + 1) % LEVEL_NAMES.size()
	elif event.is_action_pressed("menu_back"):
		get_tree().quit()
		return
	else:
		return
	_refresh_menu()


func _parse_args() -> int:
	var start := -1
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = AutoPlay.new()
			start = 4
		elif a == "--hitboxes":
			debug.visible = true
		elif a.begins_with("--mode="):
			start = clampi(int(a.get_slice("=", 1)), 0, MODES.size() - 1)
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
	return start


func _capture() -> void:
	var t := frame_count
	if _shots.has(t):
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		get_viewport().get_texture().get_image().save_png(_shot_dir.path_join("shot_%04d.png" % t))
	if _quit_after > 0 and t >= _quit_after:
		get_tree().quit()
