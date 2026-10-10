class_name CreatureView
extends Node2D
## Shows one CreatureSim: picks the sprite frame from its state, flips it to face,
## and adds the hit flash, charge glow, invulnerability blink and falling shrink.
## Frame layout comes from the "sprite" block in the creature's JSON, so new art
## with the same layout drops in without code changes.

const FLASH_SHADER := preload("res://src/view/flash.gdshader")
const FALLBACK := {
	"run": "idle", "light": "idle", "heavy": "idle", "dodge": "idle",
	"hurt": "idle", "guard": "idle", "ko": "hurt",
}

var c: CreatureSim
var sprite := Sprite2D.new()
var layout: Dictionary
var frame_px := 48
var cols := 1
var origin := Vector2(24, 43)
var flip := false
var mat := ShaderMaterial.new()
var _show_shadow := true


func setup(creature: CreatureSim) -> void:
	c = creature
	layout = c.def.get("sprite", {})
	var tex: Texture2D = load(String(layout["path"]))
	frame_px = int(layout.get("frame", 48))
	cols = int(layout.get("cols", 1))
	var o: Array = layout.get("origin", [24, 43])
	origin = Vector2(float(o[0]), float(o[1]))
	sprite.texture = tex
	sprite.centered = false
	sprite.hframes = cols
	sprite.vframes = maxi(1, int(tex.get_height() / frame_px))
	mat.shader = FLASH_SHADER
	sprite.material = mat
	add_child(sprite)
	flip = c.facing.x < -0.1
	refresh()


func refresh() -> void:
	position = c.pos.round()
	if c.facing.x < -0.1:
		flip = true
	elif c.facing.x > 0.1:
		flip = false

	var pick := _pick()
	var anim := _anim(pick[0])
	var count := int(anim[2])
	var idx: int = pick[1] % count if pick[2] else mini(pick[1], count - 1)
	sprite.frame = int(anim[0]) * cols + int(anim[1]) + idx
	sprite.flip_h = flip
	var ox := float(frame_px) - origin.x if flip else origin.x
	sprite.position = Vector2(-ox, -origin.y)

	# Hit flash, or a warm pulse once the heavy is fully charged.
	var flash_amt := 0.0
	var flash_col := Color.WHITE
	if c.flash > 0:
		flash_amt = 1.0 if c.flash > 3 else 0.5
	elif c.is_full_charge():
		flash_col = Color(1.0, 0.82, 0.35)
		flash_amt = 0.55 if (c.anim_t / 4) % 2 == 0 else 0.15
		sprite.position.x += 1 if (c.anim_t / 2) % 2 == 0 else -1
	mat.set_shader_parameter("flash", flash_amt)
	mat.set_shader_parameter("flash_color", flash_col)

	# Falling shrinks and darkens the creature into the pit.
	var shade := 1.0
	if c.state == CreatureSim.State.FALLING:
		var p := float(c.state_t) / float(CreatureSim.FALL_TICKS)
		scale = Vector2.ONE * maxf(0.2, 1.0 - 0.8 * p)
		shade = 1.0 - 0.75 * p
	else:
		scale = Vector2.ONE
	var blink := c.invuln > 0 and (c.anim_t / 3) % 2 == 0
	modulate = Color(shade, shade, shade, 0.4 if blink else 1.0)

	var want_shadow := c.state != CreatureSim.State.FALLING
	if want_shadow != _show_shadow:
		_show_shadow = want_shadow
		queue_redraw()


func _draw() -> void:
	if not _show_shadow:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, c.radius + 3.0, Color(0, 0, 0, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Returns [animation name, frame index, loops?].
func _pick() -> Array:
	match c.state:
		CreatureSim.State.IDLE:
			return ["idle", c.anim_t / 10, true]
		CreatureSim.State.MOVE:
			return ["run", c.anim_t / 5, true]
		CreatureSim.State.ATTACK:
			return _attack_frame()
		CreatureSim.State.DODGE:
			var n := int(_anim("dodge")[2])
			var frames := maxi(1, int(c.def["dodge"]["frames"]))
			return ["dodge", c.state_t * n / frames, false]
		CreatureSim.State.GUARD:
			return ["guard", 1 if c.guard_hit > 0 else 0, false]
		CreatureSim.State.HITSTUN:
			return ["hurt", c.state_t / 4, true]
		CreatureSim.State.FALLING:
			return ["hurt", 0, false]
		CreatureSim.State.KO:
			return ["ko", c.state_t / 6, false]
	return ["idle", 0, true]


func _attack_frame() -> Array:
	var mv := c.move_def()
	var su := int(mv["startup"])
	var ac := int(mv["active"])
	var rc := int(mv["recovery"])
	var t := c.state_t
	if c.move_id == "heavy":
		if c.charging:
			return ["heavy", (c.anim_t / 6) % 2, false]
		if t <= su:
			return ["heavy", 2, false]
		if t <= su + ac:
			return ["heavy", 3, false]
		if t <= su + ac + 8:
			return ["heavy", 4, false]
		return ["heavy", 5, false]
	if t <= su:
		return ["light", 0, false]
	if t <= su + ac:
		return ["light", 1, false]
	if t <= su + ac + int(rc * 0.5):
		return ["light", 2, false]
	return ["light", 3, false]


func _anim(anim_name: String) -> Array:
	var anims: Dictionary = layout.get("anims", {})
	var n := anim_name
	while not anims.has(n) and FALLBACK.has(n):
		n = FALLBACK[n]
	return anims.get(n, [0, 0, 1])
