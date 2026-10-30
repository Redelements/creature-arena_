class_name Fighter3D
extends Node3D
## A fighter as a fixed-Y billboard Sprite3D driven by a CreatureSim (view pick and frame
## arithmetic ported from src/view/creature_view.gd).

const TAN_22 := 0.41421356
const TAN_67 := 2.41421356
const FALLBACK := {
	"run": "idle", "light": "idle", "jab": "light", "power": "jab", "heavy": "light",
	"dodge": "idle", "hurt": "idle", "guard": "idle", "ko": "hurt",
}
const VIEW_FILES := {
	"side": "digby_2x.png", "down": "digby_2x_down.png", "up": "digby_2x_up.png",
	"down_side": "digby_2x_down_side.png", "up_side": "digby_2x_up_side.png",
}

var sprite := Sprite3D.new()
var def: Dictionary
var layout: Dictionary
var views := {}  ## name -> {tex, size Vector2, origin Vector2, cols, anims}
var sheet_set := "orig"
var flip := false
var view := "side"
var last_frame := 0
var c: CreatureSim


func _init(p_def: Dictionary) -> void:
	def = p_def
	layout = def["sprite"]
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.pixel_size = 0.5
	sprite.shaded = true
	sprite.centered = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(sprite)
	_load_views("orig")
	_apply_view("side")


func set_sheets(which: String) -> void:
	if which == sheet_set:
		return
	if which == "pitched":
		for f in VIEW_FILES.values():
			if not FileAccess.file_exists("res://assets/sprites/pitched/" + String(f)):
				print("spike: pitched sheets missing")
				return
	_load_views(which)
	_apply_view(view)


func _load_views(which: String) -> void:
	sheet_set = which
	var dir := "res://assets/sprites/" if which == "orig" else "res://assets/sprites/pitched/"
	views.clear()
	var fs := int(layout["frame"])
	views["side"] = _mk(dir + VIEW_FILES["side"], Vector2(fs, fs), layout["origin"], layout["anims"])
	for k in layout.get("views", {}):
		var v: Dictionary = layout["views"][k]
		var fr: Array = v["frame"]
		views[k] = _mk(dir + VIEW_FILES[k], Vector2(fr[0], fr[1]), v["origin"], v.get("anims", {}))


func _mk(path: String, size: Vector2, origin: Array, anims: Dictionary) -> Dictionary:
	var tex := _tex(path)
	return {"tex": tex, "size": size, "origin": Vector2(origin[0], origin[1]),
		"cols": int(tex.get_width() / size.x), "rows": int(tex.get_height() / size.y), "anims": anims}


func _apply_view(name: String) -> void:
	view = name
	var v: Dictionary = views[name]
	sprite.texture = v["tex"]
	sprite.hframes = v["cols"]
	sprite.vframes = v["rows"]
	_set_offset(v)


func _set_offset(v: Dictionary) -> void:
	var o: Vector2 = v["origin"]
	var half: Vector2 = v["size"] * 0.5
	var ox: float = (half.x - o.x)
	if flip:
		ox = -ox
	sprite.offset = Vector2(ox, o.y - half.y)  # Sprite3D offset is y-up


static var _cache := {}


## The grid PNGs are import-skipped (importer="skip"), so load() cannot see them: read the files.
static func _tex(path: String) -> Texture2D:
	if not _cache.has(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		_cache[path] = ImageTexture.create_from_image(img) if img != null else null
	return _cache[path]


static func pick_view(f: Vector2, vs: Dictionary) -> String:
	var ax := absf(f.x)
	var ay := absf(f.y)
	var want := "side"
	if ay > ax * TAN_67:
		want = "down" if f.y > 0.0 else "up"
	elif ay > ax * TAN_22:
		want = "down_side" if f.y > 0.0 else "up_side"
	if vs.has(want):
		return want
	if ay > ax + 0.05:
		var vert := "down" if f.y > 0.0 else "up"
		if vs.has(vert):
			return vert
	return "side"


## The sim facing as the camera sees it (sim +y = down the screen). Yaw 0 gives the facing back.
func facing_for_camera(facing: Vector2, cam: Camera3D) -> Vector2:
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var f3 := Vector3(facing.x, 0, facing.y)
	return Vector2(f3.dot(right), -f3.dot(fwd))


func sync(sim_c: CreatureSim, cam: Camera3D) -> void:
	c = sim_c
	var f := facing_for_camera(c.facing, cam)
	if f.x < -0.1:
		flip = true
	elif f.x > 0.1:
		flip = false
	var vn := pick_view(f, views)
	var pick := _pick()
	var res := _resolve(pick[0], vn)
	var v: Dictionary = res[0]
	var anim: Array = res[1]
	if vn != view or v["tex"] != sprite.texture:
		_apply_view(vn)
	# an animation the view lacks is drawn from the side sheet
	if v != views[vn]:
		view = vn
		sprite.texture = v["tex"]
		sprite.hframes = v["cols"]
		sprite.vframes = v["rows"]
	_set_offset(v)
	sprite.flip_h = flip
	var count := int(anim[2])
	var idx: int = pick[1] % count if pick[2] else clampi(pick[1], 0, count - 1)
	last_frame = int(anim[0]) * int(v["cols"]) + int(anim[1]) + idx
	sprite.frame = last_frame
	position = Vector3(c.pos.x, c.air_height(), c.pos.y)


static func _named(anim_name: String, anims: Dictionary) -> String:
	var n := anim_name
	while not anims.has(n) and FALLBACK.has(n):
		n = FALLBACK[n]
	return n


func _anim(anim_name: String) -> Array:
	return _resolve(anim_name, view)[1]


func _layout_has(anim_name: String) -> bool:
	return (views["side"]["anims"] as Dictionary).has(anim_name)


func _resolve(anim_name: String, vn: String) -> Array:
	var side: Dictionary = views["side"]
	var n := _named(anim_name, side["anims"])
	var v: Dictionary = views.get(vn, side)
	if v["anims"].has(n):
		return [v, v["anims"][n]]
	return [side, side["anims"].get(n, [0, 0, 1])]


## Returns [animation name, frame index, loops?].
func _pick() -> Array:
	match c.state:
		CreatureSim.State.IDLE:
			return ["idle", c.anim_t / maxi(1, int(layout.get("idle_ticks", 10))), true]
		CreatureSim.State.MOVE:
			# legs keep up with the faster walk
			return ["run", c.anim_t / maxi(1, int(layout.get("run_ticks", 4))), true]
		CreatureSim.State.ATTACK:
			return _attack_frame()
		CreatureSim.State.DODGE:
			var n := int(_anim("dodge")[2])
			var frames := maxi(1, int(c.def["dodge"]["frames"]))
			if c.def["dodge"].has("anim_at"):  # an explicit timeline, as a move's anim_at
				var fa := 0
				for pair in c.def["dodge"]["anim_at"]:
					if c.state_t >= int(pair[0]):
						fa = int(pair[1])
				return ["dodge", mini(fa, n - 1), false]
			var bl: Dictionary = c.def["dodge"].get("blink", {})
			if not bl.is_empty() and n >= 4:
				# A teleport: gather, vanish, (the jump), flicker back in, settle.
				var at := int(bl["at"])
				var f := 0 if c.state_t < at - 2 else (1 if c.state_t < at else (2 if c.state_t < at + 4 else 3))
				return ["dodge", f, false]
			return ["dodge", c.state_t * n / frames, false]
		CreatureSim.State.GUARD:
			if c.guard_hit <= 0:
				return ["guard", 0, false]
			# A blocked hit: frame 1 on impact, then the shiver and the re-set across the
			# 10 ticks of guard_hit when the sheet has them (the reactions pass gives 4).
			var gn := int(_anim("guard")[2])
			if gn <= 2:
				return ["guard", 1, false]
			var el := 10 - c.guard_hit
			return ["guard", 1 + mini(gn - 2, el * (gn - 1) / 10), false]
		CreatureSim.State.HITSTUN:
			# Recoil, deepest point, settle; a long stun holds the last frame instead of
			# flinching again every 16 ticks.
			return ["hurt", mini(c.state_t / 4, int(_anim("hurt")[2]) - 1), true]
		CreatureSim.State.CRUMPLE:
			return ["hurt", 0 if c.stone > 0 else 1, false]  # a statue: caught mid-flinch
		CreatureSim.State.AIRBORNE:
			return ["hurt", 0 if c.air_t < c.air_total / 2 else 1, false]
		CreatureSim.State.KNOCKDOWN:
			if c.stun <= 8:
				return ["hurt", 0, false]  # getting up
			return ["ko", 1 if c.state_t < 5 else 2, false]
		CreatureSim.State.FALLING:
			return ["hurt", 0, false]
		CreatureSim.State.KO:
			return ["ko", c.state_t / 6, false]
	return ["idle", 0, true]


## Maps the current tick of a move onto its animation: windup frames during startup,
## the strike frame while active, then follow-through and recovery.
func _attack_frame() -> Array:
	var mv := c.move_def()
	var name := String(mv.get("anim", "light"))
	var n := int(_anim(name)[2])
	var t := c.state_t
	var su := int(mv.get("startup", 0))
	var segs: Array = mv.get("_segs", [])
	var length := int(mv.get("length", 1))

	if mv.has("charge_max") and c.charging:  # heavies: charge frames looping while held
		var ch: Array = mv.get("anim_charge", [0, 2, 6])  # [first frame, frames, ticks each]
		return [name, mini(int(ch[0]) + (c.anim_t / maxi(1, int(ch[2]))) % maxi(1, int(ch[1])), n - 1), false]

	if mv.has("anim_reel") and c.reel_t > 0:  # being reeled in on the line (Cast Line)
		return [name, mini(int(mv["anim_reel"]), n - 1), false]

	if mv.has("fold_of"):  # a fold step: its timeline is the move's "fold" -> "anim_at"
		var fd: Dictionary = c.moves()[String(mv["fold_of"])].get("fold", {})
		if fd.has("anim_at"):
			var ff := 0
			for pair in fd["anim_at"]:
				if t >= int(pair[0]):
					ff = int(pair[1])
			return [name, mini(ff, n - 1), false]

	if mv.has("anim_at"):  # an explicit timeline: [[tick, frame], ...], each from its tick on
		var f := 0
		for pair in mv["anim_at"]:
			if t >= int(pair[0]):
				f = int(pair[1])
		return [name, mini(f, n - 1), false]

	if mv.has("charge_max"):  # then rise, strike, follow, recover
		if t <= su:
			return [name, mini(2, n - 1), false]
		var act := int(mv.get("active", 1))
		if t <= su + act:
			return [name, mini(3, n - 1), false]
		# The follow-through holds a third of the recovery (at least 8 ticks), so a slow
		# heavy (Craglash's Stomp) doesn't snap to its last frame early.
		var follow := maxi(8, (length - su - act) / 3)
		return [name, mini(4 if t <= su + act + follow else 5, n - 1), false]

	if mv.has("armor"):  # Bedrock: brace, hold (roaring as it sets), then stand
		var ar: Dictionary = mv["armor"]
		if t < int(ar["from"]):
			return [name, 0, false]
		if t <= int(ar["to"]):
			if t < int(ar["from"]) + 14:
				return [name, mini(2, n - 1), false]
			return [name, mini(1 + (t / 10) % 2, n - 1), false]
		return [name, n - 1, false]

	if mv.has("counter"):  # Slip: weave while the window is open, then recover
		var w: Dictionary = mv["counter"]
		if t <= int(w["to"]):
			return [name, 0 if t < int(w["from"]) + 4 else 1, false]
		return [name, n - 1, false]

	if mv.has("anim_from"):  # a follow-up that reuses the tail of another animation
		var a0 := int(mv["anim_from"])
		var act_end := su + int(mv.get("active", 1))
		return [name, a0 if t <= act_end + 2 else n - 1, false]

	if segs.size() > 1:  # multi-hit: cycle the flurry frames, then the finisher
		var last: Dictionary = segs[segs.size() - 1]
		var at_last := int(last["at"])
		if t < at_last - 8:
			return [name, (t / 3) % maxi(1, n - 3), true]
		if t < at_last:
			return [name, n - 3, false]
		if t < at_last + int(last["active"]) + 8:
			return [name, n - 2, false]
		return [name, n - 1, false]

	var first_at := int(segs[0]["at"]) if segs.size() > 0 else su + 1
	var active := int(segs[0]["active"]) if segs.size() > 0 else 4
	var wind := maxi(1, n - 3)
	if t < first_at:
		return [name, mini(wind - 1, t * wind / maxi(1, first_at)), false]
	if t < first_at + active:
		return [name, n - 3, false]
	var rec_start := first_at + active
	var rec_len := maxi(1, length - rec_start)
	return [name, n - 2 if t - rec_start < rec_len / 2 else n - 1, false]


## Whether the frame showing now draws no head: the sprite block's "headless" {anim: [frames]}
## (Craglash's Mountain Maw, lash 5-7: FxView draws his head on, from "neck_end").
