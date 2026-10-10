extends Node2D
## Training mode: Culvert vs. a training dummy.
##
## Each physics tick (60 Hz) this script reads input, steps the simulation once,
## then lets the views catch up. The simulation never touches nodes, so the same
## code runs headless in tests.
##
## Command-line options (after `--`):
##   --autoplay            play the scripted demo instead of reading input
##   --dummy-mode=N        0 stand, 1 guard, 2 walk, 3 dodge
##   --hitboxes            start with the hitbox overlay on
##   --shots=60,120        save screenshots at those ticks
##   --shot-dir=PATH       where screenshots go (default user://shots)
##   --quit-after=N        exit after N ticks

const DUMMY_MODES := ["Stand", "Guard", "Walk", "Dodge"]

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

var dummy_mode := 0
var shake := 0.0
var autoplay: AutoPlay = null
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
	hud = Hud.new()
	layer.add_child(hud)

	_parse_args()
	_reset()


func _reset() -> void:
	sim = MatchFactory.training()
	replay = Replay.new()
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
	hud.dummy_mode_name = DUMMY_MODES[dummy_mode]
	fx.clear()
	shake = 0.0


func _physics_process(_delta: float) -> void:
	var inputs := PackedInt32Array([_player_bits(), _dummy_bits()])
	replay.record(inputs)
	sim.step(inputs)
	for e in sim.events:
		_react(e)

	arena.refresh()
	crowd.advance()
	fx.advance()
	hud.advance()
	for v in views:
		v.refresh()
	if debug.visible:
		debug.queue_redraw()

	shake *= 0.82
	if shake > 0.3:
		camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)).round()
	else:
		camera.offset = Vector2.ZERO
	_capture()


func _player_bits() -> int:
	if autoplay != null:
		return autoplay.bits(sim.tick + 1)
	return Controls.read_bits()


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
			shake = maxf(shake, 1.5 + power * 0.25)
			crowd.cheer(0.12 + power * 0.02)
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
		"guard_break":
			crowd.cheer(0.3)
		"ko":
			shake = maxf(shake, 4.0)
			crowd.cheer(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_hitboxes"):
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
	elif event.is_action_pressed("reset"):
		_reset()
		hud.show_toast("Reset")
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = AutoPlay.new()
		elif a == "--hitboxes":
			debug.visible = true
		elif a.begins_with("--dummy-mode="):
			dummy_mode = clampi(int(a.get_slice("=", 1)), 0, DUMMY_MODES.size() - 1)
		elif a.begins_with("--shots="):
			for s in a.get_slice("=", 1).split(","):
				_shots[int(s)] = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.get_slice("=", 1)
		elif a.begins_with("--quit-after="):
			_quit_after = int(a.get_slice("=", 1))


func _capture() -> void:
	var t := sim.tick
	if _shots.has(t):
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		get_viewport().get_texture().get_image().save_png(_shot_dir.path_join("shot_%04d.png" % t))
	if _quit_after > 0 and t >= _quit_after:
		get_tree().quit()
