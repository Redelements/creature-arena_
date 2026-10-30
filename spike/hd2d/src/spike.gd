extends Node3D
## HD-2D spike, steps 1-2: Stadium floor on a 3D plane, backdrop strips, camera, environment.
## World: sim x -> x, sim y -> z, y up. Floor x [16,688], z [64,352].

const FLOOR_SIZE := Vector2(672, 288)
const CENTER := Vector3(352, 0, 208)
const FOV := 30.0
const PITCHES := [25.0, 35.0, 45.0]

var pitch_deg := 35.0
var ortho := false
var cam: Camera3D
var env: Environment
var attrs: CameraAttributesPractical
var sun: DirectionalLight3D
var dist := 0.0
var glow_on := true
var ssao_on := true
var dof_on := true
var shadows_on := true
var _shot_frame := -1
var _shot_name := ""
var _shot_n := 0
var _shot_pending := false


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
		elif a == "--no-glow":
			glow_on = false
		elif a == "--no-ssao":
			ssao_on = false
		elif a == "--no-dof":
			dof_on = false
		elif a == "--no-shadows":
			shadows_on = false
		elif a == "--mobile":
			glow_on = false
			ssao_on = false
			dof_on = false
			shadows_on = false
	_build_floor()
	_build_backdrop()
	_build_env()
	_build_lights()
	cam = Camera3D.new()
	cam.fov = FOV
	cam.far = 3000.0
	cam.near = 1.0
	add_child(cam)
	cam.current = true
	frame_camera(pitch_deg)
	_apply_toggles()
	print("spike: ready (pitch %d, fov %d, ortho %s)" % [int(pitch_deg), int(FOV), "on" if ortho else "off"])


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
	var need_w := FLOOR_SIZE.x * 0.5 * 1.04 / (tan_h * aspect)
	var need_h := FLOOR_SIZE.y * sin(pr) * 0.5 * 1.04 / tan_h
	dist = maxf(need_w, need_h)
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = maxf(FLOOR_SIZE.x * 1.04 / aspect, FLOOR_SIZE.y * sin(pr) * 1.04)
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = FOV
	cam.position = CENTER + back * dist
	cam.rotation = Vector3(-pr, 0, 0)
	attrs.dof_blur_far_distance = cam.position.distance_to(Vector3(352, 0, 64)) + 20.0


func _apply_toggles() -> void:
	env.glow_enabled = glow_on
	env.ssao_enabled = ssao_on
	attrs.dof_blur_far_enabled = dof_on
	sun.shadow_enabled = shadows_on


func print_state() -> void:
	print("state: pitch %d ortho %s glow %s ssao %s dof %s shadows %s dist %.1f" % [
		int(pitch_deg), ortho, glow_on, ssao_on, dof_on, shadows_on, dist])


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
			print("keys: O ortho, P pitch, 1 glow, 2 ssao, 3 dof, 4 shadows, M mobile profile, F12 screenshot")
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
	if _shot_frame >= 0 and not _shot_pending and Engine.get_process_frames() >= _shot_frame:
		_shot_pending = true
		_save_shot(_shot_name)


func _save_shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://shots")
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % n)
	print("spike: saved shots/%s.png" % n)
	if _shot_frame >= 0:
		get_tree().quit()
