class_name CreatureView
extends Node2D
## Shows one CreatureSim: picks the sprite frame from its state, flips it to face,
## and adds the hit flash, charge glow, invulnerability blink, launch height,
## squash and stretch, and falling shrink. Frame layout comes from the "sprite" block in the creature's JSON,
## and each move names its animation with "anim", so new art with the same layout
## drops in without code changes. A move can also give "anim_at": [[tick, frame], ...]
## to time its frames exactly (Barkley's spin and lob), and "view_lift" to raise the
## sprite off its shadow (Gillbert's leap).
##
## Views: fighters can face any of 8 ways. The "sprite" block is the side view (facing
## right, mirrored for left). Optional "views": {"up": {...}, "down": {...}} add sheets
## for facing up the screen (seen from behind) and down it (seen from the front), each
## with its own "path", "frame" (a size, or [width, height]), "origin" and "cols". They
## use the side sheet's row layout unless they list their own "anims"; animations named
## in "side_only" (say, a knockout that falls over sideways) always use the side sheet.
## Facing more up/down than sideways picks the up/down view; diagonals stay side-on.

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
var view := "side"  ## "side", "up" or "down": which sheet is showing
var mat := ShaderMaterial.new()
var _views := {}  ## view name -> {tex, size, cols, origin, anims}
var _cur: Dictionary = {}  ## the view whose sheet the sprite is showing
## Set by FxView when a death animation replaces the sprite (Cairn's stones scatter).
var ko_hidden := false
## Set by main when this fighter stands in front of a shorter one and covers it.
var see_through := false
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
	mat.shader = FLASH_SHADER
	sprite.material = mat
	sprite.centered = false
	add_child(pivot)
	pivot.add_child(sprite)
	rebind(creature)


## Shows a different creature in this slot (a Duel tag, or a new teammate entering).
func rebind(creature: CreatureSim) -> void:
	c = creature
	ko_hidden = false
	_prev_state = -1
	_prev_seg = -1
	_prev_flash = 0
	_sq = Vector2.ONE
	_sq_vel = Vector2.ZERO
	_shadow_r = -1.0
	layout = c.def.get("sprite", {})
	var side := _load_view(layout, layout, [])
	frame_px = int(side["size"].x)
	cols = int(side["cols"])
	origin = side["origin"]
	_views = {"side": side}
	var extra: Dictionary = layout.get("views", {})
	for vname in extra:
		_views[vname] = _load_view(extra[vname], layout, layout.get("side_only", []))
	_cur = {}
	view = "side"
	flip = c.facing.x < -0.1
	refresh()


static func _load_view(v: Dictionary, side: Dictionary, side_only: Array) -> Dictionary:
	var tex: Texture2D = load(String(v["path"]))
	var fr = v.get("frame", side.get("frame", 48))
	var size := Vector2(float(fr[0]), float(fr[1])) if fr is Array else Vector2(float(fr), float(fr))
	var o: Array = v.get("origin", side.get("origin", [24, 43]))
	var anims: Dictionary = v.get("anims", side.get("anims", {})).duplicate()
	for n in side_only:
		anims.erase(n)
	return {"tex": tex, "size": size, "cols": int(v.get("cols", side.get("cols", 1))),
		"origin": Vector2(float(o[0]), float(o[1])), "anims": anims}


## Whether this fighter has up/down art (otherwise vertical swings are drawn side-on).
func has_vertical_views() -> bool:
	return _views.has("up") or _views.has("down")


func _pick_view() -> String:
	var f := c.facing
	if absf(f.y) > absf(f.x) + 0.05:
		var want := "down" if f.y > 0.0 else "up"
		if _views.has(want):
			return want
	return "side"


func refresh() -> void:
	position = c.pos.round()
	if c.facing.x < -0.1:
		flip = true
	elif c.facing.x > 0.1:
		flip = false

	view = _pick_view()
	# Attacking toward the camera: draw over whoever is in front, so a swing that reaches
	# down the screen isn't hidden behind its target.
	z_index = 1 if c.state == CreatureSim.State.ATTACK and c.facing.y > 0.5 else 0
	var pick := _pick()
	var res := _resolve(pick[0])
	var v: Dictionary = res[0]
	var anim: Array = res[1]
	if v != _cur:
		_cur = v
		sprite.texture = v["tex"]
		sprite.hframes = int(v["cols"])
		sprite.vframes = maxi(1, int(v["tex"].get_height() / v["size"].y))
	var count := int(anim[2])
	var idx: int = pick[1] % count if pick[2] else clampi(pick[1], 0, count - 1)
	sprite.frame = int(anim[0]) * int(v["cols"]) + int(anim[1]) + idx
	sprite.flip_h = flip
	var o: Vector2 = v["origin"]
	var ox: float = v["size"].x - o.x if flip else o.x
	var lift := c.air_height()
	var leap := view_lift(c)
	if leap > 0.0:
		lift += leap
		z_index = 2  # high in the air: over everyone
	sprite.position = Vector2(-ox, -o.y)
	pivot.position = Vector2(0, -round(lift))
	if c.state == CreatureSim.State.CRUMPLE and c.stone <= 0:
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
		if c.poison > 0 and c.flash <= 2:
			flash_col = Color(0.6, 1.0, 0.35)  # a poison pulse
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
	elif c.is_armored():
		# Bedrock: a slow amber pulse while the armor holds.
		flash_col = Color(1.0, 0.72, 0.32)
		flash_amt = 0.22 if (c.anim_t / 6) % 2 == 0 else 0.08
	elif c.state == CreatureSim.State.ATTACK and c.move_type() == "surge" and c.state_t < 12:
		flash_col = Color(1.0, 0.9, 0.4)
		flash_amt = 0.6 if (c.anim_t / 2) % 2 == 0 else 0.25
	mat.set_shader_parameter("flash", flash_amt)
	mat.set_shader_parameter("flash_color", flash_col)
	# Stoneskin: a pale stone rim around the silhouette while the shield holds.
	var rim := 0.0
	if c.shield > 0.0 and c.state != CreatureSim.State.KO:
		rim = 0.75 + 0.2 * sin(c.anim_t * 0.15)
	mat.set_shader_parameter("rim", rim)
	# Petrified: grey stone until the statue shatters or wears off (flickering at the end).
	var stone := 0.0
	if c.stone > 0 and c.state != CreatureSim.State.KO:
		stone = 1.0 if c.stone > 20 or (c.anim_t / 3) % 2 == 0 else 0.5
	mat.set_shader_parameter("stone", stone)
	mat.set_shader_parameter("ice", c.stone_ice)

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
	var alpha := 0.4 if blink else (0.55 if see_through else 1.0)
	if c.stealth > 0:
		# Invisible (Tiptoe): only a faint shimmer gives him away.
		alpha = 0.12 + 0.06 * float((c.anim_t / 6) % 2)
	alpha *= blink_alpha(c)
	modulate = Color(shade, shade, shade, alpha)

	var r := -1.0
	if c.state != CreatureSim.State.FALLING and not ko_hidden:
		r = c.radius + 3.0 - minf(lift * 0.15, 4.0 if lift < 30.0 else 7.0)
	if absf(r - _shadow_r) > 0.25:
		_shadow_r = r
		queue_redraw()


## A teleporting dodge (Chef Cerebro): he fades out over the moment before the jump and
## flickers back in after it. 1 the rest of the time.
static func blink_alpha(cr: CreatureSim) -> float:
	if cr.state != CreatureSim.State.DODGE:
		return 1.0
	var bl: Dictionary = cr.def["dodge"].get("blink", {})
	if bl.is_empty():
		return 1.0
	var at := int(bl["at"])
	var t := cr.state_t
	if t < at:
		return lerpf(1.0, 0.2, clampf(float(t) / float(maxi(1, at)), 0.0, 1.0))
	return clampf(0.35 + float(t - at) * 0.16, 0.0, 1.0) if (t - at) % 2 == 0 or t - at > 4 else 0.15


## How high a move lifts the sprite off its shadow, from the move's "view_lift"
## ([[tick, height], ...], straight lines between): Gillbert's leap out of reach.
## Cosmetic only; the simulation's "leap" window is what makes him untouchable.
static func view_lift(cr: CreatureSim) -> float:
	if cr.state != CreatureSim.State.ATTACK or cr.windup_left > 0:
		return 0.0
	var keys: Array = cr.move_def().get("view_lift", [])
	if keys.is_empty():
		return 0.0
	var t := float(cr.state_t)
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var k := (t - float(a[0])) / maxf(1.0, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), k)
	return 0.0


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
## "side_*" always describe the side sheet (Cairn's scatter cuts its idle frame).
func snapshot() -> Dictionary:
	var v: Dictionary = _cur if not _cur.is_empty() else _views["side"]
	var vc := int(v["cols"])
	var size: Vector2 = v["size"]
	var col := sprite.frame % vc
	var row := sprite.frame / vc
	return {
		"tex": sprite.texture,
		"region": Rect2(col * size.x, row * size.y, size.x, size.y),
		"feet": position + pivot.position,
		"flip": flip,
		"origin": v["origin"],
		"frame_size": size,
		"side_tex": _views["side"]["tex"],
		"side_origin": origin,
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
			return ["run", c.anim_t / 4, true]  # legs keep up with the faster walk
		CreatureSim.State.ATTACK:
			return _attack_frame()
		CreatureSim.State.DODGE:
			var n := int(_anim("dodge")[2])
			var frames := maxi(1, int(c.def["dodge"]["frames"]))
			var bl: Dictionary = c.def["dodge"].get("blink", {})
			if not bl.is_empty() and n >= 4:
				# A teleport: gather, vanish, (the jump), flicker back in, settle.
				var at := int(bl["at"])
				var f := 0 if c.state_t < at - 2 else (1 if c.state_t < at else (2 if c.state_t < at + 4 else 3))
				return ["dodge", f, false]
			return ["dodge", c.state_t * n / frames, false]
		CreatureSim.State.GUARD:
			return ["guard", 1 if c.guard_hit > 0 else 0, false]
		CreatureSim.State.HITSTUN:
			return ["hurt", c.state_t / 4, true]
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

	if mv.has("charge_max") and c.charging:  # heavies: two charge frames while held
		return [name, (c.anim_t / 6) % 2, false]

	if mv.has("anim_reel") and c.reel_t > 0:  # being reeled in on the line (Cast Line)
		return [name, mini(int(mv["anim_reel"]), n - 1), false]

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
		return [name, mini(4 if t <= su + act + 8 else 5, n - 1), false]

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


## The frame count of an animation, from whichever sheet will show it.
func _anim(anim_name: String) -> Array:
	return _resolve(anim_name)[1]


## [view, [row, col, count]]: the current view's animation, or the side one when the
## view doesn't have it.
func _resolve(anim_name: String) -> Array:
	# Name it the way the side sheet does (fallbacks included), then use the current
	# view's version of that animation if it has one. A side-only knockout stays a
	# knockout instead of falling back to the view's hurt frames.
	var side: Dictionary = _views["side"]
	var n := _named(anim_name, side["anims"])
	var v: Dictionary = _views.get(view, side)
	if v["anims"].has(n):
		return [v, v["anims"][n]]
	return [side, side["anims"].get(n, [0, 0, 1])]


static func _named(anim_name: String, anims: Dictionary) -> String:
	var n := anim_name
	while not anims.has(n) and FALLBACK.has(n):
		n = FALLBACK[n]
	return n
