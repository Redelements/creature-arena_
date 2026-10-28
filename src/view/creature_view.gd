class_name CreatureView
extends Node2D
## Shows one CreatureSim: picks the sprite frame from its state, flips it to face,
## and adds the hit flash, charge glow, invulnerability blink, launch height,
## squash and stretch, and falling shrink. Frame layout comes from the "sprite" block in the creature's JSON,
## and each move names its animation with "anim", so new art with the same layout
## drops in without code changes. A move can also give "anim_at": [[tick, frame], ...]
## to time its frames exactly (Barkley's spin and lob), "anim_charge" for the frames looped
## while a charge is held, and "view_lift" to raise the sprite off its shadow (Gillbert's
## leap). The sprite block's "idle_ticks" and "run_ticks" set how long each idle and run
## frame shows (10 and 4 unless given). The dodge block's "anim_at" times the dodge's frames
## the same way (Mind Blink's 8).
##
## Views: fighters can face any of 8 ways. The "sprite" block is the side view (facing
## right, mirrored for left). Optional "views" add sheets: "up" (facing up the screen,
## seen from behind), "down" (facing down it, seen from the front), and the diagonals
## "down_side" (facing down-right, a front three-quarter view) and "up_side" (facing
## up-right, a back three-quarter view), both mirrored for down-left and up-left like the
## side sheet. Each has its own "path", "frame" (a size, or [width, height]), "origin" and
## "cols", and uses the side sheet's row layout unless it lists its own "anims"; animations
## named in "side_only" (say, a knockout that falls over sideways) always use the side sheet.
## `_pick_view`: the facing's 8 sectors of 45 degrees, each centred on a direction, pick
## side / down_side / down / up_side / up. A fighter without the sheet a sector wants keeps
## the older rule (more up/down than sideways by 0.05: up/down, else side), so fighters
## without diagonal sheets draw the diagonals side-on, as they always have.
##
## Normal sheets: a view whose sheet has a `<sheet>_n.png` beside it (or a "normal" path in
## its block) shows through a CanvasTexture with that normal map, so Light2DView's lights
## shade it per pixel (Settings > Video > Lighting): while such a sheet shows, the sprite's
## `light_mask` is Light2DView.FIGHTER_MASK. A sheet without normals keeps the default mask,
## which no light uses, so a fighter without normal sheets draws exactly as before.
##
## Emissive sheets: a view whose sheet has a `<sheet>_e.png` beside it (or an "emissive" path
## in its block; RGB the colour a pixel gives off, A how strongly, docs/SPRITES.md) draws it
## as a layer over the sprite (`emit`, `_sync_emit`), untouched by the lights and the night's
## tint, so the glowing parts stay bright in the dark; BloomView blooms it (`emit_frame`).
## Lighting Off (`emissive_on`) and fighters without the sheet draw exactly as before.

var sun_bit := 0  ## Light2DView's sun for this fighter (set_sun_bit)
const FLASH_SHADER := preload("res://src/view/flash.gdshader")
## Windup tell colors: red means it can't be blocked, so get out of the way or hit first.
const TENDER_PINK := Color(1.0, 0.55, 0.66)
const SLOW_BLUE := Color(0.62, 0.85, 1.0)
const TELL_RED := Color(1.0, 0.22, 0.18)
const TELL_GOLD := Color(1.0, 0.8, 0.3)
const FALLBACK := {
	"run": "idle", "light": "idle", "jab": "light", "power": "jab", "heavy": "light",
	"dodge": "idle", "hurt": "idle", "guard": "idle", "ko": "hurt",
}

var c: CreatureSim
var sprite := Sprite2D.new()
var layout: Dictionary
var frame_px := 48  ## the side frame's width, in sheet pixels
var cols := 1
var origin := Vector2(24, 43)
## The side sheet's density (ArtScale: texture pixels per world unit; the sprite block's
## "ppu", 1 unless given). A 2x sheet draws at half scale, on half-unit positions, so each
## of its pixels is one grid pixel. Frame sizes, origins and portraits stay in sheet pixels.
var ppu := 1
var flip := false
var view := "side"  ## "side", "up", "down", "down_side" or "up_side": which sheet is showing
var mat := ShaderMaterial.new()
var _views := {}  ## view name -> {tex, size, cols, origin, anims}
var _cur: Dictionary = {}  ## the view whose sheet the sprite is showing
## Set by FxView when a death animation replaces the sprite (Cairn's stones scatter).
var ko_hidden := false
## Set by main when this fighter stands in front of a shorter one and covers it.
var see_through := false
## Set by main when the local team can't see this fighter (Vision: brush, a fence or a
## wall in the way): not drawn at all, shadow included.
var out_of_sight := false
## The victory pose (main sets it once the round or match is won with this fighter still
## standing): a fighter whose sheet has a "victory" animation plays it instead of idling.
var victory := false:
	set(v):
		if v and not victory:
			_victory_t = 0
		victory = v
var _victory_t := 0
## Idle variety: a sheet with an "idle_alt" animation plays it once after the fighter has
## stood in IDLE for the sprite block's "idle_alt_after" ticks (default 300), then goes back to
## the idle and counts again. `_still` counts ticks of standing; `_alt_t` runs while it plays
## (-1: not playing). Anything but a plain idle (moving, attacking, hurt, victory, the arena
## intro) resets both.
const IDLE_ALT_AFTER := 300
var _still := 0
var _alt_t := -1
## The arena intro (main, ArenaIntro): the sim waits before its first tick, so the idle plays
## on this clock instead of the sim's (-1: the sim's), and `intro_pose()` gives a white pop.
var intro_clock := -1
var _intro_flash := 0
## The shadow (ShadowLayer draws it, `draw_shadow`): its size (1 on the floor, smaller up in
## the air) and how strong it is (0: none, falling into a pit or gone in a death animation;
## faint while hidden in the brush or invisible).
var shadow_size := 1.0
var shadow_fade := 1.0
## Squash and stretch: the sprite scales around its feet on a damped spring, so a
## landing squashes it flat and it wobbles back.
var pivot := Node2D.new()
var _sq := Vector2.ONE
var _sq_vel := Vector2.ZERO
var _prev_state := -1
var _prev_seg := -1
var _prev_flash := 0
## Set by FxView on a light hit: the hit flash stays a half tint instead of a full white.
var soft_flash := false
## Which palette the fighter wears (Progress): a hue turn applied by the flash shader.
const PALETTE_HUES := [0.0, 0.3, 0.55, 0.8]
var palette := 0:
	set(v):
		palette = v
		if sprite != null and sprite.material != null:
			(sprite.material as ShaderMaterial).set_shader_parameter("hue", PALETTE_HUES[clampi(v, 0, PALETTE_HUES.size() - 1)])
## The power-up aura while the Surge is ready: one layer behind the sprite, one in front.
var aura := SurgeAura.new()
var aura_front := SurgeAura.new()

const RIM_STONE := Color(0.85, 0.85, 0.88)
## Settings > Accessibility > Fighter outlines: the colour of this fighter's marker (main sets it
## each tick from `FxView.mark_color`), drawn round the silhouette by Team.
var outline_color := Color.WHITE

## Emissive sheets: the glowing parts of the frame showing now, drawn over the sprite at their
## own colour (`_sync_emit`); none while no `_e.png` shows or Lighting is Off (`emissive_on`).
var emit := Sprite2D.new()
var emit_mat := ShaderMaterial.new()
## Main sets it from Settings > Video > Lighting: Off draws no emissive layer (the game before it).
static var emissive_on := true


## The fighter sheets the views alive now hold (`sheet_report`, `--print-vram`).
static var _live: Array[WeakRef] = []


func setup(creature: CreatureSim) -> void:
	_live = _live.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	_live.append(weakref(self))
	mat.shader = FLASH_SHADER
	sprite.material = mat
	sprite.centered = false
	emit_mat.shader = FLASH_SHADER  # the same hit flash, stone and palette as the sprite
	emit.material = emit_mat
	emit.centered = false
	emit.visible = false
	add_child(pivot)
	aura_front.front = true
	aura.twin = aura_front
	pivot.add_child(aura)
	pivot.add_child(sprite)
	pivot.add_child(emit)
	pivot.add_child(aura_front)
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
	layout = c.def.get("sprite", {})
	_load_views()
	view = "side"
	flip = c.facing.x < -0.1
	aura.bind(c)
	aura_front.bind(c)
	refresh()


## Loads every sheet of the fighter's sprite block (the side sheet and each of its "views"):
## all at once, so the first turn to a new facing never waits on a load.
func _load_views() -> void:
	var side := _load_view(layout, layout, [])
	frame_px = int(side["size"].x)
	cols = int(side["cols"])
	origin = side["origin"]
	ppu = int(side["ppu"])
	_views = {"side": side}
	var extra: Dictionary = layout.get("views", {})
	for vname in extra:
		_views[vname] = _load_view(extra[vname], layout, layout.get("side_only", []))
	_cur = {}
	emit.texture = null


static func _load_view(v: Dictionary, side: Dictionary, side_only: Array) -> Dictionary:
	var path := String(v["path"])
	var npath := String(v.get("normal", path.get_basename() + "_n.png"))
	var epath := String(v.get("emissive", path.get_basename() + "_e.png"))
	var tex: Texture2D = PackedSheet.load_sheet(path)
	var lit: Texture2D = tex
	var emit_tex: Texture2D = null
	if lit_sheets:  # Lighting Off loads neither: nothing would use them
		var ntex := _sheet_beside(tex, npath, false)
		if ntex != null:
			var ct := CanvasTexture.new()
			ct.diffuse_texture = (tex as PackedSheet).held() if tex is PackedSheet else tex
			ct.normal_texture = (ntex as PackedSheet).held() if ntex is PackedSheet else ntex
			ct.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			lit = (tex as PackedSheet).with_texture(ct) if tex is PackedSheet else ct
		emit_tex = _sheet_beside(tex, epath, true)
	var fr = v.get("frame", side.get("frame", 48))
	var size := Vector2(float(fr[0]), float(fr[1])) if fr is Array else Vector2(float(fr), float(fr))
	var o: Array = v.get("origin", side.get("origin", [24, 43]))
	var anims: Dictionary = v.get("anims", side.get("anims", {})).duplicate()
	for n in side_only:
		anims.erase(n)
	return {"tex": tex, "lit": lit, "size": size, "cols": int(v.get("cols", side.get("cols", 1))),
		"origin": Vector2(float(o[0]), float(o[1])), "anims": anims, "emit": emit_tex,
		"ppu": ArtScale.ppu_of(v, ArtScale.ppu_of(side))}


## A normal or emissive sheet for colour sheet `tex` (grid path `path`), or null: its packed copy
## in the colour sheet's layout when the colour sheet is packed, else the sheet itself
## (`load_emissive`). The emissive layer is its own sprite, so a grid emissive sheet (a test's
## fixture) still lines up over a packed colour sheet (`grid_ok`); a normal sheet shares the
## colour sheet's texture coordinates and must be packed with it.
static func _sheet_beside(tex: Texture2D, path: String, grid_ok: bool) -> Texture2D:
	if tex is PackedSheet:
		var pp := PackedSheet.packed_path(path)
		if ResourceLoader.exists(pp):
			return (tex as PackedSheet).with_texture(load(pp))
		if not grid_ok:
			if ResourceLoader.exists(path):
				push_warning("%s: no packed copy (python3 tools/pack_sheets.py): drawn without normals" % path)
			return null
	return load_emissive(path)


## Lighting Off: no normal or emissive sheets loaded (main sets it with the tier). A change
## reloads every live view's sheets, so turning Lighting on mid-match brings them back.
static var lit_sheets := true


static func set_lit_sheets(on: bool) -> void:
	if on == lit_sheets:
		return
	lit_sheets = on
	for w in _live:
		var cv: CreatureView = w.get_ref()
		if cv != null and is_instance_valid(cv) and cv.c != null:
			cv._load_views()


## The fighter sheets loaded by the views alive now: how many colour, normal and emissive
## sheets and their size in MB as Godot holds them (`--print-vram`, tests/test_vram.gd).
static func sheet_report() -> String:
	var st := sheet_stats()
	return "fighter sheets: %d colour %.1f MB, %d normal %.1f MB, %d emissive %.1f MB" % [
		st["colour"], st["colour_mb"], st["normal"], st["normal_mb"], st["emit"], st["emit_mb"]]


## [count and MB] of each kind of sheet the live views hold, each texture counted once.
static func sheet_stats() -> Dictionary:
	var seen := {}
	var st := {"colour": 0, "colour_mb": 0.0, "normal": 0, "normal_mb": 0.0, "emit": 0, "emit_mb": 0.0}
	var alive: Array[WeakRef] = []
	for w in _live:
		var cv: CreatureView = w.get_ref()
		if cv == null or not is_instance_valid(cv):
			continue
		alive.append(w)
		for v in cv._views.values():
			var kinds := {"colour": v.get("tex"), "emit": v.get("emit")}
			var lt = v.get("lit")
			if lt is PackedSheet:
				lt = (lt as PackedSheet).draw_tex
			if lt is CanvasTexture:
				kinds["normal"] = (lt as CanvasTexture).normal_texture
			for k in kinds:
				var t: Texture2D = kinds[k]
				if t is PackedSheet:
					t = (t as PackedSheet).held()
				if t == null or seen.has(t.get_rid()):
					continue
				seen[t.get_rid()] = true
				st[k] += 1
				st[k + "_mb"] += texture_bytes(t) / 1048576.0
	_live = alive
	return st


## The bytes a texture takes in video memory (its image's data size, mipmaps included).
static func texture_bytes(t: Texture2D) -> int:
	var img := t.get_image()
	return img.get_data_size() if img != null else t.get_width() * t.get_height() * 4


## A view's emissive (or normal) sheet (`<sheet>_e.png`, or its block's "emissive"), or null: an imported
## resource, else a PNG outside res:// read straight from disk (a test's fixture in user://).
static func load_emissive(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	if not path.begins_with("res://") and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


## Whether this fighter has up/down art (otherwise vertical swings are drawn side-on).
## The diagonal sheets don't count: FxView's swing already follows a diagonal facing.
func has_vertical_views() -> bool:
	return _views.has("up") or _views.has("down")


## tan(22.5) and tan(67.5): the edges of the 45-degree sectors round the diagonals.
const TAN_22 := 0.41421356
const TAN_67 := 2.41421356


func _pick_view() -> String:
	return pick_view(c.facing, _views)


## The sheet for a facing, from the views a fighter has (static, so tests can sweep it).
## The 8 sectors: within 22.5 degrees of straight up or down, the up/down view; within
## 22.5 degrees of a diagonal, down_side or up_side; otherwise the side view. A sector
## whose sheet the fighter lacks falls back to the older rule below, so a fighter with
## only side, up and down picks exactly what it always has.
static func pick_view(f: Vector2, views: Dictionary) -> String:
	var ax := absf(f.x)
	var ay := absf(f.y)
	var want := "side"
	if ay > ax * TAN_67:
		want = "down" if f.y > 0.0 else "up"
	elif ay > ax * TAN_22:
		want = "down_side" if f.y > 0.0 else "up_side"
	if views.has(want):
		return want
	if ay > ax + 0.05:
		var vert := "down" if f.y > 0.0 else "up"
		if views.has(vert):
			return vert
	return "side"


func refresh() -> void:
	if intro_clock >= 0:
		intro_clock += 1
	_update_idle_alt()
	if c.facing.x < -0.1:
		flip = true
	elif c.facing.x > 0.1:
		flip = false

	view = _pick_view()
	# Depth is the floor position alone (the entities node y-sorts by feet): whoever stands
	# further down the screen is nearer the camera and drawn in front, attacking or not.
	# A swing aimed down at someone in front is drawn behind them, as it would be seen;
	# its hit spark and smear (FxView) still show over both.
	z_index = 0
	var pick := _pick()
	var res := _resolve(pick[0])
	var v: Dictionary = res[0]
	var anim: Array = res[1]
	if v != _cur:
		_cur = v
		sprite.texture = v["lit"]
		sprite.light_mask = (Light2DView.FIGHTER_MASK | sun_bit) if lit() else 1
		sprite.hframes = int(v["cols"])
		sprite.vframes = maxi(1, int(v["tex"].get_height() / v["size"].y))
		sprite.scale = ArtScale.scale_of(int(v["ppu"]))
	var vppu := int(v["ppu"])
	position = ArtScale.snap(c.pos, vppu)
	var count := int(anim[2])
	var idx: int = pick[1] % count if pick[2] else clampi(pick[1], 0, count - 1)
	sprite.frame = int(anim[0]) * int(v["cols"]) + int(anim[1]) + idx
	if sprite.flip_h != flip:
		sprite.flip_h = flip  # (a Sprite2D redraws on every set)
	var o: Vector2 = v["origin"]
	var ox: float = v["size"].x - o.x if flip else o.x
	var lift := c.air_height()
	var leap := view_lift(c)
	if leap > 0.0:
		lift += leap
		z_index = 2  # high in the air: over everyone
	sprite.position = Vector2(-ox, -o.y) / float(vppu)
	pivot.position = Vector2(0, -ArtScale.snapf(lift, vppu))
	if c.state == CreatureSim.State.CRUMPLE and c.stone <= 0:
		pivot.position.x += 1 if (c.anim_t / 4) % 2 == 0 else -1
		pivot.position.y += 1
	elif c.state == CreatureSim.State.KO and c.state_t <= 1:
		# Held on the finishing blow: tremble before the death animation plays.
		pivot.position.x += 1 if Engine.get_physics_frames() % 2 == 0 else -1
	_update_squash()
	pivot.scale = _sq
	if ko_hidden and c.state != CreatureSim.State.KO:
		ko_hidden = false  # back up (a Team Deathmatch respawn): the death animation is over
	pivot.visible = not ko_hidden
	visible = c.swallow_t <= 0 and not out_of_sight  # swallowed (Culvert's Gulp): inside him, shadow and all

	# Hit flash, or a warm pulse once the heavy is fully charged or a Surge starts.
	var flash_amt := 0.0
	var flash_col := Color.WHITE
	if c.flash == 0:
		soft_flash = false
	if c.flash > 0:
		flash_amt = 1.0 if (c.flash > 3 and not soft_flash) else 0.5
		if c.poison > 0 and c.flash <= 2:
			flash_col = Color(0.6, 1.0, 0.35)  # a poison pulse
	elif c.is_winding_up():
		var tell := String(c.move_def().get("tell", "strong"))
		flash_col = TELL_RED if tell in ["unblockable", "guard_break"] else TELL_GOLD
		flash_amt = 0.7 if (Engine.get_physics_frames() / 3) % 2 == 0 else 0.3
		# Lean back into the windup.
		pivot.position.x += 1.0 if flip else -1.0
	elif full_charge_breaks_guard(c) and c.state_t <= int(c.move_def().get("startup", 0)):
		# Held to the full charge that breaks guard (Sack Smack): a red pulse until it lands.
		flash_col = TELL_RED
		flash_amt = 0.7 if (Engine.get_physics_frames() / 3) % 2 == 0 else 0.3
		pivot.position.x += 1 if (c.anim_t / 2) % 2 == 0 else -1
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
	elif c.vuln > 0 and c.state != CreatureSim.State.KO:
		# Tenderized: a slow pink pulse over the sprite while it takes extra damage.
		flash_col = TENDER_PINK
		flash_amt = 0.12 + 0.14 * (0.5 + 0.5 * sin(c.anim_t * 0.12))
	elif c.slow > 0 and c.state != CreatureSim.State.KO:
		flash_col = SLOW_BLUE
		flash_amt = 0.14
	if _intro_flash > 0:
		flash_amt = 1.0 if _intro_flash > 4 else 0.45
		flash_col = Color.WHITE
		_intro_flash -= 1
	mat.set_shader_parameter("flash", flash_amt)
	mat.set_shader_parameter("flash_color", flash_col)
	# Stoneskin: a pale stone rim around the silhouette while the shield holds. Otherwise,
	# with the Surge ready, a rim in the fighter's aura colour.
	aura.step()
	var rim := 0.0
	var rim_col := RIM_STONE
	if c.shield > 0.0 and c.state != CreatureSim.State.KO:
		rim = 0.75 + 0.2 * sin(c.anim_t * 0.15)
	elif aura.rim() > 0.0:
		rim = aura.rim()
		rim_col = aura.rim_color()
	mat.set_shader_parameter("rim", rim)
	mat.set_shader_parameter("rim_color", rim_col)
	_apply_outline()
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
		# Invisible (Tiptoe): foes don't draw him at all (main hides him, `out_of_sight`);
		# he and his team see a ghost so they can follow him.
		alpha = 0.4 + 0.08 * float((c.anim_t / 6) % 2)
	elif c.covered:
		alpha = minf(alpha, 0.45)  # in the brush: a shape in the leaves
	alpha *= blink_alpha(c)
	modulate = Color(shade, shade, shade, alpha)
	_sync_emit()

	# The shadow shrinks and fades as the fighter goes up; a fighter hidden in the brush or
	# invisible leaves only as faint a shadow as its sprite (it mustn't give them away).
	shadow_fade = 0.0
	if c.state != CreatureSim.State.FALLING and not ko_hidden:
		shadow_size = maxf(0.45, 1.0 - lift * 0.011)
		shadow_fade = maxf(0.4, 1.0 - lift * 0.009) * blink_alpha(c)
		if c.stealth > 0 or c.covered:
			shadow_fade *= minf(1.0, alpha * 1.5)


## Settings > Accessibility > Fighter outlines, on the flash shader. Only round a fighter that
## is fully shown: one the local team can't see isn't drawn at all (`out_of_sight`), and one
## in the brush or invisible (a faint shape, or a ghost only its own team sees) gets none, so
## an outline never gives anyone away. None once knocked out either.
func _apply_outline() -> void:
	var st := Accessibility.outline_style()
	var on := not st.is_empty() and outline_allowed()
	mat.set_shader_parameter("outline", float(st.get("alpha", 1.0)) if on else 0.0)
	if not on:
		return
	var outer = st["outer"]
	mat.set_shader_parameter("outline_outer", outline_color if outer == null else outer)
	var inner = st["inner"]
	mat.set_shader_parameter("outline_inner", Color(0, 0, 0, 0) if inner == null else inner)


## Whether this fighter may wear an outline now (see `_apply_outline`).
func outline_allowed() -> bool:
	return visible and not out_of_sight and not ko_hidden and c.state != CreatureSim.State.KO \
		and c.stealth <= 0 and not c.covered and c.swallow_t <= 0


## The creature's move breaks guard only at a full charge ("hold": {"guard_break": true},
## Sack Smack), and it was charged full (still held at the top, or released there): the
## red guard-break cue. Any move whose "hold" sets guard_break gets it.
static func full_charge_breaks_guard(cr: CreatureSim) -> bool:
	if cr.state != CreatureSim.State.ATTACK:
		return false
	if not (cr.is_full_charge() or (not cr.charging and cr.charge_ratio >= 1.0)):
		return false
	var mv := cr.move_def()
	return bool(mv.get("hold", {}).get("guard_break", false)) and not bool(mv.get("guard_break", false))


## A teleporting dodge (Chef Cerebro): he fades out over the moment before the jump and
## flickers back in after it, except on the blink's "solid" ticks ([from, to), the flash
## frames), drawn at full strength. 1 the rest of the time.
static func blink_alpha(cr: CreatureSim) -> float:
	if cr.state != CreatureSim.State.DODGE:
		return 1.0
	var bl: Dictionary = cr.def["dodge"].get("blink", {})
	if bl.is_empty():
		return 1.0
	var at := int(bl["at"])
	var t := cr.state_t
	var solid: Array = bl.get("solid", [])
	if solid.size() == 2 and t >= int(solid[0]) and t < int(solid[1]):
		return 1.0
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


## The intro's beat on this fighter: a white flash and a stretch up, and the victory
## pose where the sheet has one (main clears `victory` when the round starts).
func intro_pose() -> void:
	_intro_flash = 8
	_kick(Vector2(0.84, 1.2))
	if _layout_has("victory"):
		victory = true


## A squash or stretch started from outside (FxView, on an event: Culvert's gulp).
func kick(to: Vector2) -> void:
	_kick(to)


## The emissive layer follows the sprite exactly (frame, flip, place) with its own sheet, over
## it and outside every light and tint (the sprite's `self_modulate` is the night's dark, not
## the layer's): a glowing part stays its own colour at night. It takes the sprite's flash,
## stone and palette, so a hit flash or Petrify covers it too.
func _sync_emit() -> void:
	var tex: Texture2D = _cur.get("emit") if emissive_on else null
	if tex == null:
		emit.visible = false
		return
	emit.visible = true
	if emit.texture != tex:
		emit.texture = tex
		emit.hframes = sprite.hframes
		emit.vframes = sprite.vframes
	emit.frame = sprite.frame
	if emit.flip_h != sprite.flip_h:
		emit.flip_h = sprite.flip_h
	emit.position = sprite.position
	emit.scale = sprite.scale
	for k in ["flash", "flash_color", "stone", "ice", "hue"]:
		emit_mat.set_shader_parameter(k, mat.get_shader_parameter(k))


## Whether an emissive sheet is showing now (BloomView blooms it).
func emitting() -> bool:
	return emit.visible and emit.texture != null and pivot.visible


## The emissive frame showing now, for BloomView: {tex, region, xform (the sprite's world
## transform, mirrored when flipped)}; empty when none shows.
func emit_frame() -> Dictionary:
	if not emitting():
		return {}
	var size: Vector2 = _cur["size"]
	var vc := int(_cur["cols"])
	var region := Rect2((emit.frame % vc) * size.x, (emit.frame / vc) * size.y, size.x, size.y)
	var xf := emit.get_global_transform() if emit.is_inside_tree() else emit.transform
	if emit.flip_h:
		xf = xf * Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(size.x, 0))
	return {"tex": emit.texture, "region": region, "xform": xf, "size": size}


## Light2DView: this fighter's own sun's light-mask bit (0: none), kept on the sprite while a
## sheet with normals shows.
func set_sun_bit(b: int) -> void:
	sun_bit = b
	if sprite != null:
		sprite.light_mask = (Light2DView.FIGHTER_MASK | sun_bit) if lit() else 1


## Whether the sheet showing now has normals (the lights shade it; WeatherView dims it by day).
func lit() -> bool:
	return not _cur.is_empty() and _cur["lit"] != _cur["tex"]


## The colour sheet showing now (the sprite's texture may be a CanvasTexture with its normals).
func sheet() -> Texture2D:
	return _cur.get("tex", sprite.texture)


## What the sprite looks like right now, for afterimages and death animations.
## "side_*" always describe the side sheet (Cairn's scatter cuts its idle frame).
func snapshot() -> Dictionary:
	var v: Dictionary = _cur if not _cur.is_empty() else _views["side"]
	var vc := int(v["cols"])
	var size: Vector2 = v["size"]
	var col := sprite.frame % vc
	var row := sprite.frame / vc
	return {
		"tex": v["tex"],
		"region": Rect2(col * size.x, row * size.y, size.x, size.y),
		"feet": position + pivot.position,
		"flip": flip,
		"origin": v["origin"],
		"frame_size": size,
		"side_tex": _views["side"]["tex"],
		"side_origin": origin,
		"side_size": _views["side"]["size"],
		"frame_px": frame_px,
		"ppu": int(v["ppu"]),
		"side_ppu": ppu,
	}


## What the shadow looks like (ShadowLayer redraws it only when this changes; moving
## doesn't): the frame, facing, squash, size and strength.
func shadow_key() -> Array:
	return [sheet(), sprite.frame, flip, (_sq * shadow_size).snapped(Vector2(0.02, 0.02)),
		snappedf(shadow_fade, 0.02), pivot.position.x]


## Draws this fighter's shadow onto `ci` (a ShadowLayer caster standing at its feet, on the
## floor under everyone): the frame showing now as a silhouette from the feet along the light,
## squashing with it.
func draw_shadow(ci: CanvasItem, cast: Vector2, alpha: float) -> void:
	if _cur.is_empty() or shadow_fade <= 0.0:
		return
	var size: Vector2 = _cur["size"]
	var vc := int(_cur["cols"])
	var region := Rect2((sprite.frame % vc) * size.x, (sprite.frame / vc) * size.y, size.x, size.y)
	# A faint contact mark under the feet first, so a floater's floor spot (Chef Cerebro, whose
	# silhouette only starts well above the floor) still reads where it stands.
	var a := alpha * shadow_fade
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.38))
	ci.draw_circle(Vector2.ZERO, c.radius * 0.8 * shadow_size, Color(0, 0, 0, a * 0.45))
	# A 2x sheet's rows are half a unit tall: the silhouette shrinks with the sprite.
	# A packed sheet: the frame's own packed rect (one lookup, not one a row).
	var pc := PackedSheet.piece(sheet(), region, _cur["origin"])
	if pc["region"].size.x <= 0.0:
		return
	ShadowLayer.draw_silhouette(ci, pc["tex"], pc["region"], pc["origin"], flip,
		Vector2(pivot.position.x, 0.0), cast, a, _sq * shadow_size / float(int(_cur["ppu"])))


## Counts the stand-still for the idle variety, one step a tick (see `_alt_t`).
func _update_idle_alt() -> void:
	if c.state != CreatureSim.State.IDLE or victory or intro_clock >= 0 or not _layout_has("idle_alt"):
		_still = 0
		_alt_t = -1
		return
	if _alt_t >= 0:
		_alt_t += 1
		if _alt_t >= int(_anim("idle_alt")[2]) * maxi(1, int(layout.get("idle_ticks", 10))):
			_alt_t = -1
			_still = 0
		return
	_still += 1
	if _still > int(layout.get("idle_alt_after", IDLE_ALT_AFTER)):
		_alt_t = 0


## The victory animation's frame: the first frame (getting ready), then frames 1..n-3 in
## a loop for a while (the celebration), then the last two (the finish, held).
func _victory_frame() -> int:
	var n := int(_anim("victory")[2])
	_victory_t += 1
	var t := _victory_t
	if n < 4:
		return mini(t / 10, n - 1)
	if t < 12:
		return 0
	var loop_n := n - 3
	if t < 12 + 96:
		return 1 + ((t - 12) / 6) % loop_n
	return n - 2 if t < 12 + 96 + 14 else n - 1


## Returns [animation name, frame index, loops?].
func _pick() -> Array:
	if victory and (c.state == CreatureSim.State.IDLE or c.state == CreatureSim.State.MOVE) 			and _layout_has("victory"):
		return ["victory", _victory_frame(), false]
	match c.state:
		CreatureSim.State.IDLE:
			if _alt_t >= 0:
				return ["idle_alt", _alt_t / maxi(1, int(layout.get("idle_ticks", 10))), false]
			var clock := intro_clock if intro_clock >= 0 else c.anim_t
			return ["idle", clock / maxi(1, int(layout.get("idle_ticks", 10))), true]
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


## The frame count of an animation, from whichever sheet will show it.
func _anim(anim_name: String) -> Array:
	return _resolve(anim_name)[1]


func _layout_has(anim_name: String) -> bool:
	return (_views["side"]["anims"] as Dictionary).has(anim_name)


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
