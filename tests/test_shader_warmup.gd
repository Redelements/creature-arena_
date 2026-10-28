extends TestCase
## The shader warm-up (ShaderWarmup): its list covers every material the game makes and
## every `.gdshader` in the project (so it can't drift from the views), it spreads its draws
## over frames (PER_FRAME a frame) and frees its viewport, it is never drawn on screen, it is off
## headless and with --no-warmup, and Vulkan's pipeline cache (the one Android keeps
## between launches) stays on.

## What makes a material or loads a shader in a script.
const MAKES := ["ShaderMaterial.new(", "CanvasItemMaterial.new(", "Shader.new(", ".gdshader\""]


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _files(dir: String, ext: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension() == ext:
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_files(dir.path_join(sub), ext, out)


func test_every_script_that_makes_a_material_is_a_source() -> void:
	var sources := {}
	for s in ShaderWarmup.SOURCES:
		sources[(s as Script).resource_path] = true
	var scripts: Array = []
	_files("res://src", "gd", scripts)
	_files("res://scenes", "gd", scripts)
	var makers := 0
	for path in scripts:
		if path == "res://src/view/shader_warmup.gd":
			continue
		var text := FileAccess.get_file_as_string(path)
		for pat in MAKES:
			if pat in text:
				makers += 1
				assert_true(sources.has(path), "%s makes a material (%s): give it warm_materials() and add it to ShaderWarmup.SOURCES" % [path, pat])
				break
	assert_gt(float(makers), 5.0, "the scan found the views that make materials:")
	for s in ShaderWarmup.SOURCES:
		var got: Array = (s as Script).call("warm_materials")
		assert_false(got.is_empty(), "%s warms something" % (s as Script).resource_path)
		for m in got:
			assert_true(m is Material, "%s gives materials" % (s as Script).resource_path)


func test_every_gdshader_is_warmed() -> void:
	var shaders: Array = []
	_files("res://", "gdshader", shaders)
	assert_gt(float(shaders.size()), 2.0, "found the project's shaders:")
	var warmed := {}
	for e in ShaderWarmup.collect():
		var m: Material = e["material"]
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			warmed[(m as ShaderMaterial).shader.resource_path] = true
	for path in shaders:
		assert_true(warmed.has(path), "%s is in the warm-up's list" % path)


func test_no_scene_or_resource_holds_a_material_it_misses() -> void:
	var res: Array = []
	for ext in ["tscn", "tres"]:
		_files("res://scenes", ext, res)
		_files("res://assets", ext, res)
	for path in res:
		var text := FileAccess.get_file_as_string(path)
		assert_false("type=\"ShaderMaterial\"" in text or "type=\"CanvasItemMaterial\"" in text,
			"%s holds a material: warm it too (ShaderWarmup.SOURCES only scans scripts)" % path)


func test_the_list_is_deduplicated_by_what_compiles() -> void:
	var list := ShaderWarmup.collect()
	var keys := {}
	for e in list:
		assert_false(keys.has(e["key"]), "%s once" % e["key"])
		keys[e["key"]] = true
	assert_true(keys.has("default"), "the default canvas material too")
	assert_true(keys.has("canvas_item:%d:0" % CanvasItemMaterial.BLEND_MODE_ADD), "additive (Glow, bloom, shafts)")
	assert_true(keys.has("canvas_item:%d:0" % CanvasItemMaterial.BLEND_MODE_MUL), "multiply (the night shade)")
	# FloorGlow's code shader is shared: the warm-up compiles the very one the game draws.
	var a := Light2DView.FloorGlow.make_material()
	var b := Light2DView.FloorGlow.new()
	assert_eq((b.material as ShaderMaterial).shader, a.shader, "one FloorGlow shader:")
	b.free()


func test_it_spreads_its_draws_over_frames_and_cleans_up() -> void:
	var w := ShaderWarmup.new()
	_root().add_child(w)
	var n := w.entries.size()
	assert_gt(float(n), 5.0, "materials to warm:")
	var vp: SubViewport = w.get_child(0)
	assert_true(vp.world_2d != _root().world_2d, "a canvas of its own (nothing on screen)")
	var draws := n * 2 * ShaderWarmup.KINDS.size()  # unlit and lit, every primitive kind
	assert_eq(w.draws.size(), draws, "draws:")
	var most := 0
	var steps := 0
	while not w.done and steps < 1000:
		w.step()
		if vp != null and is_instance_valid(vp):
			var cells := vp.get_children().filter(func(c): return c is ShaderWarmup.Cell and not c.is_queued_for_deletion())
			most = maxi(most, cells.size())
		steps += 1
	assert_true(w.done, "finished")
	assert_eq(w.drawn, draws, "every draw:")
	assert_eq(most, ShaderWarmup.PER_FRAME, "at most PER_FRAME draws a frame:")
	assert_eq(w.frames, ceili(float(draws) / ShaderWarmup.PER_FRAME), "spread over frames:")
	assert_true(w.summary().begins_with("%d materials, %d draws in " % [n, draws]), "the --perf summary: " + w.summary())

	assert_false(is_instance_valid(vp) and not vp.is_queued_for_deletion(), "its viewport goes")
	w.free()


func test_it_is_off_headless_and_with_no_warmup() -> void:
	assert_false(ShaderWarmup.wanted(PackedStringArray(), "headless"), "headless: no renderer")
	assert_true(ShaderWarmup.wanted(PackedStringArray(), "Windows"), "a real window")
	assert_false(ShaderWarmup.wanted(PackedStringArray(["--perf", "--no-warmup"]), "Windows"), "--no-warmup")


func test_the_vulkan_pipeline_cache_stays_on() -> void:
	# Android (Vulkan) keeps compiled pipelines in user:// between launches: only the first
	# launch after an install compiles, and the warm-up moves that to the title. Godot's own
	# shader cache stays off (project.godot: on GL Compatibility it breaks 2D lights).
	assert_true(bool(ProjectSettings.get_setting("rendering/rendering_device/pipeline_cache/enable", false)), "pipeline cache on")
	assert_false(bool(ProjectSettings.get_setting("rendering/shader_compiler/shader_cache/enabled", true)), "GLES3 shader cache off")
