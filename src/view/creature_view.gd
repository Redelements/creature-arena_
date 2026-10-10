class_name CreatureView
extends Node2D
## Shows one CreatureSim: picks the sprite frame from its state, flips it to face,
## and adds the hit flash, charge glow, invulnerability blink, launch height,
## squash and stretch, and falling shrink. Frame layout comes from the "sprite" block in the creature's JSON,
## and each move names its animation with "anim", so new art with the same layout
## drops in without code changes.

const FLASH_SHADER := preload("res://src/view/flash.gdshader")
## Windup tell colors: red means it can't be blocked, so get out of the way or hit first.
const TELL_RED := Color(1.0, 0.22, 0.18)
const TELL_GOLD := Color(1.0, 0.8, 0.3)
const FALLBACK := {
	"run": "idle", "light": "idle", "jab": "light", "power": "jab", "heavy": "light",
	"dodge": "idle", "hurt": "idle", "guard": "idle", "ko": "hurt",
}

var c: CreatureSim
var sprite := Sprite2D.new()
var layout: Dictionary
var frame_px := 48
var cols := 1
var origin := Vector2(24, 43)
var flip := false
var mat := ShaderMaterial.new()
## Set by FxView when a death animation replaces the sprite (Cairn's stones scatter).
var ko_hidden := false
var _shadow_r := -1.0
## Squash and stretch: the sprite scales around its feet on a damped spring, so a
## landing squashes it flat and it wobbles back.
var pivot := Node2D.new()
var _sq := Vector2.ONE
var _sq_vel := Vector2.ZERO
var _prev_state := -1
var _prev_seg := -1
var _prev_flash := 0


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
	add_child(pivot)
	pivot.add_child(sprite)
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
	var idx: int = pick[1] % count if pick[2] else clampi(pick[1], 0, count - 1)
	sprite.frame = int(anim[0]) * cols + int(anim[1]) + idx
	sprite.flip_h = flip
	var ox := float(frame_px) - origin.x if flip else origin.x
	var lift := c.air_height()
	sprite.position = Vector2(-ox, -origin.y)
	pivot.position = Vector2(0, -round(lift))
	if c.state == CreatureSim.State.CRUMPLE:
		pivot.position.x += 1 if (c.anim_t / 4) % 2 == 0 else -1
		pivot.position.y += 1
	elif c.state == CreatureSim.State.KO and c.state_t <= 1:
		# Held on the finishing blow: tremble before the death animation plays.
		pivot.position.x += 1 if Engine.get_physics_frames() % 2 == 0 else -1
	_update_squash()
	pivot.scale = _sq
	pivot.visible = not ko_hidden

	# Hit flash, or a warm pulse once the heavy is fully charged or a Surge starts.
	var flash_amt := 0.0
	var flash_col := Color.WHITE
	if c.flash > 0:
		flash_amt = 1.0 if c.flash > 3 else 0.5
	elif c.is_winding_up():
		var tell := String(c.move_def().get("tell", "strong"))
		flash_col = TELL_RED if tell in ["unblockable", "guard_break"] else TELL_GOLD
		flash_amt = 0.7 if (Engine.get_physics_frames() / 3) % 2 == 0 else 0.3
		# Lean back into the windup.
		pivot.position.x += 1.0 if flip else -1.0
	elif c.is_full_charge():
		flash_col = Color(1.0, 0.82, 0.35)
		flash_amt = 0.55 if (c.anim_t / 4) % 2 == 0 else 0.15
		pivot.position.x += 1 if (c.anim_t / 2) % 2 == 0 else -1
	elif c.state == CreatureSim.State.ATTACK and c.move_type() == "surge" and c.state_t < 12:
		flash_col = Color(1.0, 0.9, 0.4)
		flash_amt = 0.6 if (c.anim_t / 2) % 2 == 0 else 0.25
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
	# A cracked Culvert greys out as it settles into rubble.
	if c.state == CreatureSim.State.KO and String(c.def.get("ko_fx", {}).get("style", "")) == "crack":
		shade = lerpf(1.0, 0.72, clampf(float(c.state_t - 12) / 20.0, 0.0, 1.0))
	var blink := c.invuln > 0 and c.state != CreatureSim.State.ATTACK and (c.anim_t / 3) % 2 == 0
	modulate = Color(shade, shade, shade, 0.4 if blink else 1.0)

	var r := -1.0
	if c.state != CreatureSim.State.FALLING and not ko_hidden:
		r = c.radius + 3.0 - minf(lift * 0.15, 4.0)
	if absf(r - _shadow_r) > 0.25:
		_shadow_r = r
		queue_redraw()


## Kicks the squash spring on landings, launches, hits, strikes and dodges.
func _update_squash() -> void:
	var st := int(c.state)
	var S := CreatureSim.State
	if st != _prev_state:
		if st == S.AIRBORNE:
			_kick(Vector2(0.8, 1.25))
		elif _prev_state == S.AIRBORNE or (_prev_state == S.FALLING and st != S.KO):
			_kick(Vector2(1.35, 0.7))
		elif st == S.DODGE:
			_kick(Vector2(1.18, 0.84))
		elif st == S.KO and _prev_state != S.AIRBORNE:
			_kick(Vector2(1.2, 0.82))
	if c.flash > _prev_flash:
		_kick(Vector2(1.14, 0.88))
	var seg := c.active_seg()
	if seg >= 0 and seg != _prev_seg:
		var heavy := c.move_type() != "light"
		_kick(Vector2(1.14, 0.88) if heavy else Vector2(1.06, 0.95))
	_prev_seg = seg
	_prev_state = st
	_prev_flash = c.flash

	# Holding a heavy squats lower the longer it charges.
	var rest := Vector2.ONE
	if c.charging and c.state == S.ATTACK:
		var k := float(c.charge) / maxf(1.0, float(c.move_def().get("charge_max", 1)))
		rest = Vector2(1.0 + 0.08 * k, 1.0 - 0.08 * k)
	_sq_vel += (rest - _sq) * 0.32
	_sq_vel *= 0.62
	_sq += _sq_vel


func _kick(to: Vector2) -> void:
	_sq = to
	_sq_vel = Vector2.ZERO


## What the sprite looks like right now, for afterimages and death animations.
func snapshot() -> Dictionary:
	var col := sprite.frame % cols
	var row := sprite.frame / cols
	return {
		"tex": sprite.texture,
		"region": Rect2(col * frame_px, row * frame_px, frame_px, frame_px),
		"feet": position + pivot.position,
		"flip": flip,
		"origin": origin,
		"frame_px": frame_px,
	}


func _draw() -> void:
	if _shadow_r <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, _shadow_r, Color(0, 0, 0, 0.32))
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
		CreatureSim.State.CRUMPLE:
			return ["hurt", 1, false]
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

	if mv.has("charge_max"):  # heavies: two charge frames, then rise, strike, follow, recover
		if c.charging:
			return [name, (c.anim_t / 6) % 2, false]
		if t <= su:
			return [name, mini(2, n - 1), false]
		var act := int(mv.get("active", 1))
		if t <= su + act:
			return [name, mini(3, n - 1), false]
		return [name, mini(4 if t <= su + act + 8 else 5, n - 1), false]

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


func _anim(anim_name: String) -> Array:
	var anims: Dictionary = layout.get("anims", {})
	var n := anim_name
	while not anims.has(n) and FALLBACK.has(n):
		n = FALLBACK[n]
	return anims.get(n, [0, 0, 1])
