extends Node3D
## Side dressing beside the floor. Modes: none, stands (tilted side-stand pictures + fans), hills (mounds, trees).

const MODES := ["none", "stands", "hills"]
const GRASS_CELL := Rect2i(96, 96, 32, 32)  ## plain green cell of set1_ground.png (picked by eye)
const TREE_FRAME := Rect2i(0, 0, 160, 106)  ## first of 5 frames of the 800 x 106 canopy strip
const TILT := 30.0
var mode := "stands"
var stands: Node3D
var hills: Node3D


static func load_tex(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func _ready() -> void:
	stands = Node3D.new()
	hills = Node3D.new()
	add_child(stands)
	add_child(hills)
	_build_stands()
	_build_hills()
	set_mode(mode)


func set_mode(m: String) -> void:
	mode = m
	stands.visible = m == "stands"
	hills.visible = m == "hills"


func next_mode() -> void:
	set_mode(MODES[(MODES.find(mode) + 1) % MODES.size()])


func _build_stands() -> void:
	var pic := load_tex("res://assets/sprites/arena_stadium.png")
	var crowd := load_tex("res://assets/sprites/crowd.png")
	var ct: ImageTexture = ImageTexture.create_from_image(crowd)
	# near stands: picture rows 432..526 as a plane falling away from the floor's near edge
	var nm := StandardMaterial3D.new()
	nm.albedo_texture = ImageTexture.create_from_image(pic.get_region(Rect2i(0, 432, 1504, 94)))
	nm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	nm.roughness = 1.0
	nm.metallic_specular = 0.0
	var piv := Node3D.new()
	piv.position = Vector3(352, 0, 352)
	piv.rotation = Vector3(deg_to_rad(TILT), 0, 0)
	stands.add_child(piv)
	var np := MeshInstance3D.new()
	var npm := PlaneMesh.new()
	npm.size = Vector2(1504, 94)
	np.mesh = npm
	np.material_override = nm
	np.position = Vector3(0, 0, 47)
	piv.add_child(np)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color8(14, 38, 28)
	dm.roughness = 1.0
	dm.metallic_specular = 0.0
	var dg := MeshInstance3D.new()
	var dpm := PlaneMesh.new()
	dpm.size = Vector2(2400, 800)
	dg.mesh = dpm
	dg.material_override = dm
	dg.position = Vector3(352, -47.5, 560)  # at the strip's lower edge (it drops 47), not -0.4, or the plane would hide it
	stands.add_child(dg)
	for side in [-1, 1]:
		var rect := Rect2i(0, 144, 416, 288) if side < 0 else Rect2i(1088, 144, 416, 288)
		var tex := ImageTexture.create_from_image(pic.get_region(rect))
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.roughness = 1.0
		m.metallic_specular = 0.0
		var root := Node3D.new()
		var inner_x := 16.0 if side < 0 else 688.0
		root.position = Vector3(inner_x, 0, 0)
		stands.add_child(root)
		var tilt := Node3D.new()
		tilt.rotation = Vector3(0, 0, deg_to_rad(TILT) * side)
		root.add_child(tilt)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(416, 288)
		mi.mesh = pm
		mi.material_override = m
		mi.position = Vector3(208.0 * side, 0, 208)
		tilt.add_child(mi)
		# fans on the seat bank: 6 rows of 24
		var row0 := 16 if side < 0 else 24
		for r in 6:
			var d := 14.0 + r * 15.0  # distance up the slope from the inner edge
			for i in 24:
				var s := Sprite3D.new()
				s.texture = ct
				s.region_enabled = true
				var col: int = (i * 7 + r * 3) % 3  # three sitting columns of the sheet
				var row: int = row0 + (i * 5 + r * 3) % 8
				s.region_rect = Rect2(col * 24, row * 48, 24, 48)
				s.pixel_size = 0.5
				s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
				s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
				var z := 64.0 + 6.0 + i * 12.0
				s.position = Vector3(side * d * cos(deg_to_rad(TILT)), d * sin(deg_to_rad(TILT)) + 4.0, z)
				root.add_child(s)


func _grass_material() -> StandardMaterial3D:
	var img := load_tex("res://assets/tiles/set1_ground.png")
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img.get_region(GRASS_CELL))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = true
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.0 / 16.0, 1.0 / 16.0, 1.0 / 16.0)
	m.roughness = 1.0
	m.metallic_specular = 0.0
	return m


func _build_hills() -> void:
	var gm := _grass_material()
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2400, 1400)
	g.mesh = pm
	g.material_override = gm
	g.position = Vector3(352, -0.2, 300)
	hills.add_child(g)
	var tree_img := load_tex("res://assets/tiles/grassland_anim_tree_canopy.png")
	var tree_tex := ImageTexture.create_from_image(tree_img)
	# [centre x, z, radius, height scale, tree dx, dz]
	for h in [[-70.0, 190.0, 80.0, 0.3, -6.0, -6.0], [775.0, 185.0, 85.0, 0.3, 8.0, 4.0],
			[-40.0, 315.0, 55.0, 0.35, -5.0, 3.0]]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = h[2]
		sm.height = h[2] * 2.0
		sm.radial_segments = 48
		sm.rings = 24
		mi.mesh = sm
		mi.material_override = gm
		mi.scale = Vector3(1, h[3], 1)
		mi.position = Vector3(h[0], 0, h[1])
		hills.add_child(mi)
		var dx: float = h[4]
		var dz: float = h[5]
		var top: float = h[2] * h[3] * sqrt(maxf(0.0, 1.0 - (dx * dx + dz * dz) / (h[2] * h[2])))
		_tree(tree_tex, Vector3(h[0] + dx, top - 1.0, h[1] + dz))
	_tree(tree_tex, Vector3(-115, 0, 100))
	_tree(tree_tex, Vector3(800, 0, 310))
	_tree(tree_tex, Vector3(120, 0, 420))
	_tree(tree_tex, Vector3(600, 0, 440))


## A trunk (a brown cylinder) with the canopy sprite on top; ~90 units tall in all.
func _tree(tex: Texture2D, feet: Vector3) -> void:
	var tm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 4.0
	cm.height = 30.0
	tm.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("4a3322")
	bm.roughness = 1.0
	tm.material_override = bm
	tm.position = feet + Vector3(0, 13.0, 0)
	hills.add_child(tm)
	var s := Sprite3D.new()
	s.texture = tex
	s.region_enabled = true
	s.region_rect = Rect2(TREE_FRAME)
	s.pixel_size = 0.6
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.position = feet + Vector3(0, 24.0 + 106.0 * 0.6 * 0.5, 0)
	hills.add_child(s)
