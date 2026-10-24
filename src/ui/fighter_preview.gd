class_name FighterPreview
extends Control
## A fighter's idle animation, standing on the bottom-centre of this control, at 60
## frames a second of real time whatever the screen's frame rate.

var fighter := "":
	set(v):
		fighter = v
		_def = MatchFactory.load_def(v) if v != "" else {}
		var sp: Dictionary = _def.get("sprite", {})
		_tex = load(String(sp["path"])) if sp.has("path") else null
		queue_redraw()
var face_left := false
## Scale on top of the sheet's own "select_scale".
var zoom := 1.0
## "victory" plays the fighter's victory pose (the sheet's "victory" row, restarting when
## the preview is shown); a sheet without one, or any other value, shows the idle.
var anim := "idle"

var _def := {}
var _tex: Texture2D = null
var _time := 0.0


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var sp: Dictionary = _def["sprite"]
	var fsz = sp.get("frame", 48)  # a size, or [width, height]
	var fpx := float(fsz[0]) if fsz is Array else float(fsz)
	var fh := float(fsz[1]) if fsz is Array else fpx
	var o: Array = sp.get("origin", [24, 43])
	var anims: Dictionary = sp.get("anims", {})
	var idle: Array = anims.get("idle", [0, 0, 1])
	var tick := int(_time * 60.0 + 1e-6)
	var frame := int(idle[1]) + (tick / maxi(1, int(sp.get("idle_ticks", 10)))) % maxi(1, int(idle[2]))
	if anim == "victory" and anims.has("victory"):
		idle = anims["victory"]
		frame = int(idle[1]) + victory_frame(tick, int(idle[2]))
	var region := Rect2(frame * fpx, int(idle[0]) * fh, fpx, fh)
	var k := float(sp.get("select_scale", minf(1.0, 55.0 / fpx))) * zoom
	draw_set_transform(Vector2(size.x * 0.5, size.y), 0.0, Vector2(-k if face_left else k, k))
	draw_texture_rect_region(_tex, Rect2(-float(o[0]), -float(o[1]), fpx, fh), region)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The victory row's frame at `t` ticks: the same timing as CreatureView._victory_frame
## (getting ready, a loop, then the finish held).
static func victory_frame(t: int, n: int) -> int:
	if n < 4:
		return mini(t / 10, n - 1)
	if t < 12:
		return 0
	var loop_n := n - 3
	if t < 12 + 96:
		return 1 + ((t - 12) / 6) % loop_n
	return n - 2 if t < 12 + 96 + 14 else n - 1


## Whether this fighter's sheet has a victory pose.
func has_victory() -> bool:
	return _def.get("sprite", {}).get("anims", {}).has("victory")
