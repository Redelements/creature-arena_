extends Node3D
## HD-2D spike, steps 1-2: Stadium floor on a 3D plane, backdrop strips, camera, environment.
## World: sim x -> x, sim y -> z, y up. Floor x [16,688], z [64,352].

const FLOOR_SIZE := Vector2(672, 288)
const CENTER := Vector3(352, 0, 208)
const FOV := 30.0
const PITCHES := [25.0, 35.0, 45.0]

var pitch_deg := 35.0
var ortho := false
var lit_on := false  ## Step 4b: fighters on the normal-mapped quad instead of the Sprite3D
var pitched_on := false  ## Step 4a: the sheets re-rendered at the camera's pitch
var height_on := false  ## Step 4c: walls and a chasm
var height: HeightPreview
const SidesS := preload("res://src/sides.gd")
var sides: SidesS
var sides_mode := "stands"
var frame_set := false
var fore_on := false  ## --fore shows the front rail strip (hidden by default)
var cam: Camera3D
var env: Environment
var attrs: CameraAttributesPractical
var sun: DirectionalLight3D
var dist := 0.0
var frame_w := 672.0  ## the floor width the camera frames; narrower follows the fighters (Z)
var target := CENTER  ## what the camera looks at
var glow_on := true
var ssao_on := true
var dof_on := true
var shadows_on := true
var _shot_frame := -1
var _shot_name := ""
var _shot_n := 0
var _shot_pending := false
var sim: MatchSim
var fighters: Array = []
var cpus: Array = [null, null]
var pin: PlayerInput
var run_ticks := -1
var cpu_vs_cpu := false
var facing_test := false
var toggle_test := false  ## QC: press every toggle key twice from code, then quit
var perf := false  ## evidence: the average frame time over 10 s of the match, printed once
var _key_script: Array = []  ## [tick, keycode] pairs from --keys
var _rec_name := ""
var _rec_start := 0
var _rec_end := 0
var _rec_every := 3
var _rec_last := -1
var _rec_n := 0
var _perf_frames := 0
var _perf_t0 := 0.0
var _perf_open := false
var _gpu_ms := 0.0
var _cpu_ms := 0.0
var _perf_n := 0
var determinism := false
var anim_log := false
var seed_base := 1
var _quit_after_shot := false


func _ready() -> void:
	Controls.setup()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-at="):
			var p: PackedStringArray = a.substr(10).split(":")
			_shot_frame = int(p[0])
			_shot_name = p[1] if p.size() > 1 else "shot"
		elif a.begins_with("--pitch="):
			pitch_deg = float(a.substr(8))
		elif a == "--ortho":
			ortho = true
		elif a == "--height":
			height_on = true
		elif a == "--lit":
			lit_on = true
		elif a == "--pitched":
			pitched_on = true
		elif a == "--no-glow":
			glow_on = false
		elif a == "--no-ssao":
			ssao_on = false
		elif a == "--no-dof":
			dof_on = false
		elif a == "--no-shadows":
			shadows_on = false
		elif a.begins_with("--run="):
			run_ticks = int(a.substr(6))
		elif a == "--cpu-vs-cpu":
			cpu_vs_cpu = true
		elif a.begins_with("--seed="):
			seed_base = int(a.substr(7))
		elif a == "--facing-test":
			facing_test = true
		elif a == "--determinism":
			determinism = true
		elif a.begins_with("--frame="):
			frame_w = float(a.substr(8))
			frame_set = true
		elif a.begins_with("--keys="):
			# a key script: tick:KEY pairs, e.g. 180:P,360:O (pressed through the key handler)
			for pair in a.substr(7).split(","):
				var kp: PackedStringArray = pair.split(":")
				if kp.size() == 2:
					_key_script.append([int(kp[0]), OS.find_keycode_from_string(kp[1])])
		elif a.begins_with("--rec="):
			# frames for a clip: NAME:START:END:EVERY ticks, 640 x 360 PNGs in shots/rec/NAME/
			var rp: PackedStringArray = a.substr(6).split(":")
			_rec_name = rp[0]
			_rec_start = int(rp[1])
			_rec_end = int(rp[2])
			_rec_every = maxi(1, int(rp[3]))
		elif a == "--toggle-test":
			toggle_test = true
		elif a == "--perf":
			perf = true
		elif a.begins_with("--sides="):
			sides_mode = a.substr(8)
		elif a == "--fore":
			fore_on = true
		elif a == "--anim-log":
			anim_log = true
		elif a == "--mobile":
			glow_on = false
			ssao_on = false
			dof_on = false
			shadows_on = false
	if sides_mode != "none" and not frame_set:
		frame_w = 900.0  # wide enough to show the side dressing
	_build_floor()
	_build_backdrop()
	_build_env()
	_build_lights()
	sides = SidesS.new()
	sides.mode = sides_mode
	add_child(sides)
	height = HeightPreview.new()
	add_child(height)
	height.visible = height_on
	cam = Camera3D.new()
	cam.fov = FOV
	cam.far = 3000.0
	cam.near = 1.0
	add_child(cam)
	cam.current = true
	frame_camera(pitch_deg)
	_apply_toggles()
	Engine.physics_ticks_per_second = SimDefs.TICK_RATE
	_start_match()
	print("spike: ready (pitch %d, fov %d, ortho %s)" % [int(pitch_deg), int(FOV), "on" if ortho else "off"])


func _new_cpu(i: int) -> CpuController:
	return CpuController.new(i, 1, seed_base * 101 + i * 7 + i)  # level 1 = Normal


func _start_match() -> void:
	if determinism:
		_run_determinism()
		return
	sim = MatchFactory.versus("digby", "digby")
	var def: Dictionary = sim.creatures[0].def
	for i in 2:
		var f := Fighter3D.new(def)
		add_child(f)
		fighters.append(f)
	_apply_fighter_modes()
	cpus[1] = _new_cpu(1)
	if cpu_vs_cpu:
		cpus[0] = _new_cpu(0)
	else:
		pin = PlayerInput.new()
		pin.layout = "classic"
		print("spike: P1 is keyboard (PlayerInput, classic layout)")
	if facing_test:
		_run_facing_test()
		return
	_sync_all()


func _sync_all() -> void:
	for i in 2:
		(fighters[i] as Fighter3D).sync(sim.creatures[i], cam)


func _mouse_world() -> Vector2:
	var m := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(m)
	var d := cam.project_ray_normal(m)
	if absf(d.y) < 0.0001:
		return Vector2.ZERO
	var t := -o.y / d.y
	var h := o + d * t
	return Vector2(h.x, h.z)


## Every toggle key pressed twice (P three times, to come back round), through the same
## handler a real key press reaches; the state line after each shows it flipped and flipped back.
func _run_toggle_test() -> void:
	var keys := [KEY_O, KEY_O, KEY_P, KEY_P, KEY_P, KEY_1, KEY_1, KEY_2, KEY_2, KEY_3, KEY_3,
		KEY_4, KEY_4, KEY_M, KEY_M, KEY_N, KEY_N, KEY_R, KEY_R, KEY_T, KEY_T, KEY_S, KEY_S, KEY_S]
	for k in keys:
		var e := InputEventKey.new()
		e.keycode = k
		e.pressed = true
		print("spike: press %s" % OS.get_keycode_string(k))
		_unhandled_input(e)
	print("spike: toggle test done")


## Frames and wall time from the match's first second to its eleventh, printed once.
func _perf_tick() -> void:
	if sim.tick == 60:
		_perf_t0 = Time.get_ticks_usec() / 1000.0
		_perf_frames = Engine.get_frames_drawn()
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		_perf_open = true
	elif sim.tick == 660:
		_perf_open = false
		var ms := Time.get_ticks_usec() / 1000.0 - _perf_t0
		var n := Engine.get_frames_drawn() - _perf_frames
		print("spike: perf %d frames in %.0f ms: %.2f ms a frame (%.0f fps) lit %s mobile %s" % [
			n, ms, ms / maxf(1.0, n), 1000.0 * n / maxf(1.0, ms), lit_on,
			not (glow_on or ssao_on or dof_on or shadows_on)])
		print("spike: render time over %d frames: gpu %.2f ms, cpu %.2f ms a frame (RenderingServer measured)" % [
			_perf_n, _gpu_ms / maxf(1.0, _perf_n), _cpu_ms / maxf(1.0, _perf_n)])


## One sample of the main viewport's measured render time a drawn frame while the window is open.
func _perf_sample() -> void:
	if not _perf_open:
		return
	var rid := get_viewport().get_viewport_rid()
	_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_perf_n += 1


func _run_facing_test() -> void:
	var dirs := [["right", Vector2(1, 0)], ["down-right", Vector2(1, 1)], ["down", Vector2(0, 1)],
		["down-left", Vector2(-1, 1)], ["left", Vector2(-1, 0)], ["up-left", Vector2(-1, -1)],
		["up", Vector2(0, -1)], ["up-right", Vector2(1, -1)]]
	var f: Fighter3D = fighters[0]
	for d in dirs:
		var v: Vector2 = (d[1] as Vector2).normalized()
		sim.creatures[0].facing = v
		f.flip = false  # (the dead band keeps the last flip; start clean per direction)
		f.sync(sim.creatures[0], cam)
		print("spike: facing (%.2f, %.2f) %s -> view %s flip %s" % [v.x, v.y, d[0], f.view, f.flip])
	get_tree().quit()


func _bits(i: int) -> int:
	if cpus[i] != null:
		return (cpus[i] as CpuController).bits(sim)
	return pin.bits(sim, i, _mouse_world())


func _physics_process(_d: float) -> void:
	if sim == null or facing_test or determinism:
		return
	var inputs := PackedInt32Array([_bits(0), _bits(1)])
	sim.step(inputs)
	_sync_all()
	if frame_w < FLOOR_SIZE.x:
		var mid: Vector2 = (sim.creatures[0].pos + sim.creatures[1].pos) * 0.5
		target = Vector3(mid.x, 0, mid.y)
		frame_camera(pitch_deg)
	for ks in _key_script:
		if int(ks[0]) == sim.tick:
			var e := InputEventKey.new()
			e.keycode = ks[1]
			e.pressed = true
			print("spike: key %s at tick %d" % [OS.get_keycode_string(ks[1]), sim.tick])
			_unhandled_input(e)
	if toggle_test and sim.tick == 60:
		_run_toggle_test()
	if perf:
		_perf_tick()
	if anim_log and sim.tick <= 600 and sim.tick % 30 == 0:
		var f: Fighter3D = fighters[0]
		print("spike: t=%d p1 state=%s view=%s frame=%d" % [sim.tick, CreatureSim.State.keys()[sim.creatures[0].state], f.view, f.last_frame])
	if run_ticks >= 0 and sim.tick >= run_ticks and _shot_frame < 0:
		get_tree().quit()


## Plays two CPU-vs-CPU matches; returns {pos, digest, first_diff info} data for compare.
func _play(ticks: int, with_view: bool) -> Array:
	var s := MatchFactory.versus("digby", "digby")
	var cs := [CpuController.new(0, 1, seed_base * 101), CpuController.new(1, 1, seed_base * 101 + 8)]
	var fs: Array = []
	if with_view:
		for i in 2:
			var f := Fighter3D.new(s.creatures[0].def)
			add_child(f)
			fs.append(f)
	var trace: Array = []
	for t in ticks:
		s.step(PackedInt32Array([cs[0].bits(s), cs[1].bits(s)]))
		if with_view:
			for i in 2:
				(fs[i] as Fighter3D).sync(s.creatures[i], cam)
		trace.append([s.creatures[0].pos, s.creatures[1].pos])
	for f in fs:
		f.queue_free()
	return [trace, s.state_digest()]


func _cmp(a: Array, b: Array, label: String) -> void:
	var n: int = a[0].size()
	for t in n:
		if a[0][t] != b[0][t]:
			print("spike: determinism MISMATCH (%s) first differing tick %d" % [label, t + 1])
			return
	if a[1] != b[1]:
		print("spike: determinism MISMATCH (%s) digest differs, positions equal" % label)
		return
	print("spike: determinism OK (%s) %d ticks, digest %s" % [label, n, str(a[1]).md5_text().substr(0, 8)])


func _run_determinism() -> void:
	_cmp(_play(600, false), _play(600, false), "no view x2")
	_cmp(_play(600, true), _play(600, false), "view synced vs not")
	get_tree().quit()


func _build_floor() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1344, 576)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.disable_3d = true
	add_child(vp)
	var tiles := (load("res://assets/arenas/stadium.tscn") as PackedScene).instantiate()
	vp.add_child(tiles)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = FLOOR_SIZE
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = vp.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	m.metallic_specular = 0.0
	mi.material_override = m
	mi.position = CENTER
	add_child(mi)


func _strip(path: String, region_h: float, bottom_y: float, z: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = load(path)
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, 1504, region_h)
	s.pixel_size = 1.0
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.position = Vector3(-400.0 + 752.0, bottom_y + region_h * 0.5, z)
	add_child(s)
	return s


func _build_backdrop() -> void:
	# main picture rows 0..144 sit above the far edge (2D y -80..64)
	_strip("res://assets/sprites/arena_stadium.png", 144, 0.0, 64.0)
	# far: first row at main row FAR_TOP (43) -> 101 above the edge; 102 tall
	_strip("res://assets/sprites/arena_stadium_far.png", 102, 101.0 - 102.0, 60.0)
	# sky: starts SKY_UP (112) above the main picture's top (144 above the edge); 173 tall
	_strip("res://assets/sprites/arena_stadium_sky.png", 173, 144.0 + 112.0 - 173.0, 56.0)
	# hang: top at 2D y -60 (124 above the edge), 56 tall, just in front of the stands
	_strip("res://assets/sprites/arena_stadium_hang.png", 56, 124.0 - 56.0, 62.0)
	# fore: front wall at the near edge, nearest fans' heads, 72 tall, facing the camera
	var f := _strip("res://assets/sprites/arena_stadium_fore.png", 72, 0.0, 354.0)
	f.position.y = 72.0 * 0.5 - 8.0
	f.visible = fore_on


func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("05070d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f2f5ff")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.5
	attrs = CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_transition = 60.0
	attrs.dof_blur_amount = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	we.camera_attributes = attrs
	add_child(we)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.light_color = Color("f4f6ff")
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 1500.0
	add_child(sun)
	sun.look_at(Vector3(0.25, -2.71, 1.0), Vector3.UP)
	for x in [76.0, 628.0]:
		var o := OmniLight3D.new()
		o.light_color = Color("ffd2a0")
		o.light_energy = 1.5
		o.omni_range = 260.0
		o.position = Vector3(x, 70, 84)
		add_child(o)


func frame_camera(p: float) -> void:
	pitch_deg = p
	var pr := deg_to_rad(p)
	var back := Vector3(0, sin(pr), cos(pr))
	var tan_h := tan(deg_to_rad(FOV) * 0.5)
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / vs.y
	var fh := frame_w * FLOOR_SIZE.y / FLOOR_SIZE.x
	var need_w := frame_w * 0.5 * 1.04 / (tan_h * aspect)
	var need_h := fh * sin(pr) * 0.5 * 1.04 / tan_h
	dist = maxf(need_w, need_h)
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = maxf(frame_w * 1.04 / aspect, fh * sin(pr) * 1.04)
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = FOV
	cam.position = target + back * dist
	cam.rotation = Vector3(-pr, 0, 0)
	attrs.dof_blur_far_distance = cam.position.distance_to(Vector3(352, 0, 64)) + 20.0


func _apply_toggles() -> void:
	env.glow_enabled = glow_on
	env.ssao_enabled = ssao_on
	attrs.dof_blur_far_enabled = dof_on
	sun.shadow_enabled = shadows_on


func print_state() -> void:
	print("state: pitch %d ortho %s glow %s ssao %s dof %s shadows %s lit %s sheets %s height %s frame %d dist %.1f sides %s fore %s" % [
		int(pitch_deg), ortho, glow_on, ssao_on, dof_on, shadows_on, lit_on,
		"pitched" if pitched_on else "orig", height_on, int(frame_w), dist, sides.mode, fore_on])


## Step 4 toggles on both fighters: the lit quad (N) and the pitched sheets (R).
func _apply_fighter_modes() -> void:
	for f in fighters:
		(f as Fighter3D).set_lit(lit_on)
		(f as Fighter3D).set_sheets("pitched" if pitched_on else "orig")
	if pitched_on and fighters.size() > 0 and (fighters[0] as Fighter3D).sheet_set != "pitched":
		pitched_on = false


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_O:
			ortho = not ortho
			frame_camera(pitch_deg)
		KEY_P:
			var i: int = PITCHES.find(pitch_deg)
			frame_camera(PITCHES[(i + 1) % PITCHES.size()])
		KEY_H:
			print("keys: O ortho, P pitch, 1 glow, 2 ssao, 3 dof, 4 shadows, M mobile profile, Z frame width (whole floor / 900 / 400 / 260, following the fight), N lit quad / Sprite3D, R pitched / original sheets, S side dressing (none / stands / hills), T height preview, F12 screenshot")
		KEY_Z:
			var widths := [672.0, 900.0, 400.0, 260.0]
			var wi: int = widths.find(frame_w)
			frame_w = widths[(wi + 1) % widths.size()]
			if frame_w >= FLOOR_SIZE.x:
				target = CENTER
			frame_camera(pitch_deg)
		KEY_N:
			lit_on = not lit_on
			_apply_fighter_modes()
		KEY_S:
			sides.next_mode()
		KEY_T:
			height_on = not height_on
			height.visible = height_on
		KEY_R:
			pitched_on = not pitched_on
			_apply_fighter_modes()
		KEY_1:
			glow_on = not glow_on
		KEY_2:
			ssao_on = not ssao_on
		KEY_3:
			dof_on = not dof_on
		KEY_4:
			shadows_on = not shadows_on
		KEY_M:
			var any := glow_on or ssao_on or dof_on or shadows_on
			glow_on = not any
			ssao_on = not any
			dof_on = not any
			shadows_on = not any
		KEY_F12:
			_shot_n += 1
			_save_shot("shot_%d" % _shot_n)
			return
		_:
			return
	_apply_toggles()
	print_state()


func _process(_d: float) -> void:
	_perf_sample()
	if _rec_name != "" and sim != null and sim.tick >= _rec_start and sim.tick <= _rec_end \
			and sim.tick != _rec_last and (sim.tick - _rec_start) % _rec_every == 0:
		_rec_last = sim.tick
		_rec_frame()
	var now := sim.tick if sim != null else Engine.get_process_frames()  # (ticks once a match runs)
	if _shot_frame >= 0 and not _shot_pending and now >= _shot_frame:
		_shot_pending = true
		_save_shot(_shot_name)


## One frame of a clip, scaled to 640 x 360 (--rec; tools/make_gifs.py assembles them).
func _rec_frame() -> void:
	await RenderingServer.frame_post_draw
	var dir := "res://shots/rec/%s" % _rec_name
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	img.save_png("%s/%04d.png" % [dir, _rec_n])
	_rec_n += 1
	if _rec_n == 1 or sim.tick >= _rec_end:
		print("spike: rec %s frame %d at tick %d" % [_rec_name, _rec_n, sim.tick])


func _save_shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://shots")
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % n)
	print("spike: saved shots/%s.png" % n)
	if _shot_frame >= 0:
		get_tree().quit()
