class_name MoveFxView
extends Node2D
## Plays the MoveFx of moves (hand-drawn frames, assets/vfx/*.tres): a fixed pool of
## AnimatedSprite2D children, each told its frame every sim tick (never autoplaying, so
## hitstop, KO slow motion and a rollback keep the effect in step with the fight), drawn at
## 1 / ppu so a 96 px frame is 48 units, culled off screen like the rest of FxView.
##
## FxView owns it (a child, drawn over the sparks) and calls in from the same places it
## draws its own effects: `on_start` / `on_strike` / `on_tick` from its move watching (the
## strike is the tick the sim's hitbox goes live, `CreatureSim.active_seg`), `on_shot` and
## `on_event` from `spawn` for hits, shots and bursts. A shot's end or burst comes after the
## move is over, so the move a fighter last threw from is remembered (`_shot_move`). An
## effect that `follow`s rides with its fighter; one that doesn't stays where it spawned.
## Mirrored with the facing when the resource says so.

const CAP := 32

var _sprites: Array[AnimatedSprite2D] = []
var _fx: Array = []        ## per slot: the MoveFx, or null when free
var _t := PackedFloat32Array()
var _life := PackedFloat32Array()
var _who: Array = []       ## per slot: the CreatureSim it follows, or null
var _base := PackedVector2Array()  ## the spawn point (world), or the follow offset
var _flip := PackedByteArray()
var _next := 0
var _live := 0
## "fighter id/move slot" -> Array[MoveFx], loaded once.
var _cache := {}
## creature id -> the move it last threw a shot from (for the shot's end and burst).
var _shot_move := {}


func _init() -> void:
	_fx.resize(CAP)
	_who.resize(CAP)
	_t.resize(CAP)
	_life.resize(CAP)
	_base.resize(CAP)
	_flip.resize(CAP)
	for i in CAP:
		var s := AnimatedSprite2D.new()
		s.visible = false
		s.centered = true
		add_child(s)
		_sprites.append(s)


## The MoveFx a move's `fx.move_fx` names (one entry or a list; an entry is a path or a
## {"path", overrides} Dictionary: MoveFx.from_entry), loaded once per move.
func effects_of(c: CreatureSim, move_id: String) -> Array:
	if c == null or move_id == "":
		return []
	var key := String(c.def.get("id", "")) + "/" + move_id
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var mv: Dictionary = c.moves().get(move_id, {})
	var v = mv.get("fx", {}).get("move_fx")
	var paths: Array = v if v is Array else ([v] if v != null else [])
	for p in paths:
		var r := MoveFx.from_entry(p)
		if r != null:
			out.append(r)
		else:
			push_warning("%s: move_fx %s is not a MoveFx" % [key, p])
	_cache[key] = out
	return out


func _length(c: CreatureSim, move_id: String) -> int:
	return int(c.moves().get(move_id, {}).get("length", 0))


## The move's first tick.
func on_start(c: CreatureSim) -> void:
	for f in effects_of(c, c.move_id):
		if f.on == "start":
			_spawn(f, c, c.pos, _length(c, c.move_id))


## The tick strike `seg` goes live (FxView's `_strike`): the hitbox's centre.
func on_strike(c: CreatureSim, seg: int) -> void:
	for f in effects_of(c, c.move_id):
		if f.on == "strike":
			_spawn(f, c, c.hit_center(seg), _length(c, c.move_id))


## Each tick of the move (FxView's `_during_move`).
func on_tick(c: CreatureSim) -> void:
	for f in effects_of(c, c.move_id):
		if f.on == "tick" and c.state_t == f.at:
			_spawn(f, c, c.pos, _length(c, c.move_id))


## A shot leaves `c`'s hand at `p`: remembers the move for its end, plays "projectile" effects.
func on_shot(c: CreatureSim, p: Vector2) -> void:
	_shot_move[c.id] = c.move_id
	on_event("projectile", c, p)


## A "hit" of the move `c` is in, or a "projectile_end" / "burst" of its last shot, at `p`.
func on_event(kind: String, c: CreatureSim, p: Vector2) -> void:
	var move_id := c.move_id
	if kind == "projectile_end" or kind == "burst":
		move_id = String(_shot_move.get(c.id, c.move_id))
	for f in effects_of(c, move_id):
		if f.on == kind:
			_spawn(f, c, p, _length(c, move_id))


## An effect that isn't a move's (an event's: a seed planted, an apple eaten), at `at`;
## with `who` it can follow them and mirror with their facing, as the resource says.
func play(f: MoveFx, at: Vector2, who: CreatureSim = null) -> void:
	if f != null:
		_spawn(f, who, at, 0)


func _spawn(f: MoveFx, c: CreatureSim, at: Vector2, move_length: int) -> void:
	if f.frame_count() <= 0:
		return
	var i := _next
	_next = (_next + 1) % CAP
	if _fx[i] == null:
		_live += 1
	var flip := c != null and f.flip_with_facing and c.facing.x < 0.0
	var held := c != null and f.scale_held > 0.0 and c.charge_ratio >= 1.0
	var k := f.scale_held if held else f.scale
	# A held one grows from the same spot: its offset scales with it.
	var off := Vector2(-f.offset.x if flip else f.offset.x, f.offset.y) * (k / f.scale if held and f.scale > 0.0 else 1.0)
	var follow := c != null and f.follow
	_fx[i] = f
	_t[i] = 0.0
	_life[i] = float(f.life(move_length))
	_flip[i] = 1 if flip else 0
	_who[i] = c if follow else null
	_base[i] = (at - c.pos + off) if follow else (at + off)
	var s := _sprites[i]
	s.sprite_frames = f.frames
	s.animation = f.animation
	s.flip_h = flip
	s.scale = ArtScale.scale_of(f.ppu) * k
	s.frame = 0
	s.visible = true
	_place(i)


func _place(i: int) -> void:
	var s := _sprites[i]
	var f: MoveFx = _fx[i]
	var p: Vector2 = _base[i]
	if _who[i] != null:
		p += (_who[i] as CreatureSim).pos
	s.position = ArtScale.snap(p, f.ppu)


## One sim tick of `dt` (FxView's time scale: 0 in a freeze, less than 1 in slow motion).
func advance(dt: float) -> void:
	if _live == 0:
		return
	var view := FxView._view_rect(self, FxView.CULL_PAD)
	for i in CAP:
		var f: MoveFx = _fx[i]
		if f == null:
			continue
		if dt > 0.0:
			_t[i] += dt
		if _t[i] >= _life[i] or (_who[i] != null and not is_instance_valid(_who[i])):
			_fx[i] = null
			_who[i] = null
			_sprites[i].visible = false
			_live -= 1
			continue
		_place(i)
		var s := _sprites[i]
		s.frame = f.frame_at(_t[i])
		s.visible = view.has_point(s.position)


func clear() -> void:
	for i in CAP:
		_fx[i] = null
		_who[i] = null
		_sprites[i].visible = false
	_live = 0
	_shot_move.clear()


func playing() -> int:
	return _live


## For tests: the slots playing, as [MoveFx, position, flipped, frame].
func slots() -> Array:
	var out: Array = []
	for i in CAP:
		if _fx[i] != null:
			out.append([_fx[i], _sprites[i].position, _flip[i] == 1, _sprites[i].frame])
	return out
