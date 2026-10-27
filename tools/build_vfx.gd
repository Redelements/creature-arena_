extends SceneTree
## Builds the SpriteFrames and MoveFx resources from assets/vfx/manifest.json (written by
## tools/cut_vfx.py from kiddolink's pack).
##
## Run from the repo root, after `--import` (the strips must be imported):
##   godot --headless --path . --script res://tools/build_vfx.gd
##
## Writes, per effect `name`:
##   assets/vfx/<name>_frames.tres   a SpriteFrames with one animation "default": one
##                                   AtlasTexture per 96 px frame of the strip
##   assets/vfx/<name>.tres          a MoveFx pointing at it, with the manifest's defaults
##                                   (on, offset, follow, flip, ticks per frame, loop); edit
##                                   it in the editor afterwards if a move wants otherwise;
##                                   a rerun overwrites it, so put lasting tweaks in the
##                                   manifest (tools/cut_vfx.py EFFECTS)
## Rerun after a cut changes; the game and CI use the saved files.

const DIR := "res://assets/vfx/"


func _init() -> void:
	var f := FileAccess.open(DIR + "manifest.json", FileAccess.READ)
	var man = JSON.parse_string(f.get_as_text()) if f != null else null
	if typeof(man) != TYPE_DICTIONARY:
		push_error("no manifest at " + DIR)
		quit(1)
		return
	var effects: Dictionary = man["effects"]
	for name in effects:
		var e: Dictionary = effects[name]
		var tex: Texture2D = load(DIR + String(name) + ".png")
		var size := int(e["size"])
		var frames := SpriteFrames.new()
		if not frames.has_animation(&"default"):
			frames.add_animation(&"default")
		frames.set_animation_loop(&"default", bool(e.get("loop", false)))
		frames.set_animation_speed(&"default", 60.0 / float(e.get("ticks_per_frame", 3)))
		for k in int(e["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(k * size, 0, size, size)
			frames.add_frame(&"default", at)
		var fpath := DIR + String(name) + "_frames.tres"
		_save(frames, fpath)
		var fx := MoveFx.new()
		fx.frames = frames
		fx.animation = &"default"
		fx.ticks_per_frame = int(e.get("ticks_per_frame", 3))
		fx.ppu = int(man.get("ppu", 2))
		fx.on = String(e.get("on", "strike"))
		fx.at = int(e.get("at", 0))
		var off: Array = e.get("offset", [0, 0])
		fx.offset = Vector2(float(off[0]), float(off[1]))
		fx.follow = bool(e.get("follow", false))
		fx.flip_with_facing = bool(e.get("flip_with_facing", true))
		fx.loop = bool(e.get("loop", false))
		fx.loop_ticks = int(e.get("loop_ticks", 0))
		fx.scale = float(e.get("scale", 1.0))
		_save(fx, DIR + String(name) + ".tres")
		print("built ", name, ": ", int(e["frames"]), " frames, on ", fx.on)
	quit(0)


static func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("could not save %s: %d" % [path, err])
	res.take_over_path(path)
