class_name HeightPreview
extends Node3D
## Step 4c: a height preview. Three wall-textured blocks and a sunken chasm on the floor.
## Real version: the chasm would be a hole in the floor mesh (or a stencil), not a cover box.

const TILE_PATH := "res://assets/tiles/keeps_wall_castle.png"
const CELL := Rect2i(41, 30, 32, 32)  ## solid brick face (picked by eye from a 3x preview)
const DARK := Color("2a2420")


func _ready() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(TILE_PATH))
	var tex: ImageTexture = null
	if img != null:
		tex = ImageTexture.create_from_image(img.get_region(CELL))
	else:
		push_warning("height preview: wall tile missing")
	_box(Vector3(64, 24, 16), Vector3(320, 12, 120), tex, 1.0)
	_box(Vector3(16, 32, 16), Vector3(200, 16, 150), tex, 1.0)
	_box(Vector3(48, 8, 16), Vector3(520, 4, 150), tex, 1.0)
	# chasm: sunk plane, four pit walls, cover box over the floor
	var dm := StandardMaterial3D.new()
	dm.albedo_color = DARK
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(48, 32)
	pl.mesh = pm
	pl.material_override = dm
	pl.position = Vector3(352, -12, 290)
	add_child(pl)
	var cover := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(48, 0.2, 32)
	cover.mesh = cb
	cover.material_override = dm
	cover.position = Vector3(352, 0.1, 290)
	cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cover)
	for s in [[Vector3(48, 12, 1), Vector3(352, -6, 274.5)], [Vector3(48, 12, 1), Vector3(352, -6, 305.5)],
			[Vector3(1, 12, 32), Vector3(327.5, -6, 290)], [Vector3(1, 12, 32), Vector3(376.5, -6, 290)]]:
		_box(s[0], s[1], tex, 0.45, false)
	print("spike: height preview built (tile %s, cell %s, %s)" % [TILE_PATH, CELL, "tex ok" if tex else "NO TEX"])


func _box(size: Vector3, pos: Vector3, tex: Texture2D, shade: float, cast := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(shade, shade, shade)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(size.x / 16.0, size.y / 16.0, 1.0)
	m.uv1_triplanar = false
	m.roughness = 1.0
	m.metallic_specular = 0.0
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
