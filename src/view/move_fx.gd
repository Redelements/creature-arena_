class_name MoveFx
extends Resource
## One hand-drawn effect attached to a move: which frames play, where they appear and
## when. A move gets one with one line in its JSON `fx` block:
##
##   "move_fx": "res://assets/vfx/slash_claws.tres"         (or a list of them; an entry can
##                                                         also be {"path": ..., "scale": 0.6, ...}:
##                                                         from_entry)
##
## View only: the sim never reads it. Made by tools/build_vfx.gd from assets/vfx/manifest.json
## (tools/cut_vfx.py cuts the frames from kiddolink's pack at ArtScale ppu 2), editable in the
## editor like any resource. MoveFxView plays them, one AnimatedSprite2D each, stepping the
## frame from the sim tick (hitstop, slow motion and rollback keep it in step).

## The frames (a SpriteFrames with one animation, `animation`).
@export var frames: SpriteFrames
@export var animation: StringName = &"default"
## Ticks each frame shows.
@export_range(1, 30) var ticks_per_frame := 3
## Texture pixels per world unit of the frames (ArtScale: 2 for the 32 px scale).
@export_range(1, 2) var ppu := 2
## When it spawns:
##   "strike"          the tick the move's hitbox goes live (its active frame, from the
##                     same `startup` / `hits[]` data the sim hits with; once per strike)
##   "start"           the move's first tick
##   "tick"            the move's tick `at` (state_t)
##   "hit"             each hit the move lands, at the hit point
##   "projectile"      the shot leaves the hand (`projectile` event)
##   "projectile_end"  the shot ends (`projectile_end` event: it hit something or ran out)
##   "burst"           a lob landing (its `burst` event, or `storm` for a lob that leaves one)
@export_enum("strike", "start", "tick", "hit", "projectile", "projectile_end", "burst") var on := "strike"
## For "tick": the move tick to spawn on.
@export var at := 0
## Where it appears, in world units: x along the facing (ahead), y up the screen (so -14 is
## 14 above the feet). For "strike" it is measured from the strike's centre, for "hit",
## "projectile", "projectile_end" and "burst" from the event's spot, else from the fighter.
@export var offset := Vector2.ZERO
## True: it rides with the fighter who spawned it (its offset kept); false: it stays where
## it spawned (world space).
@export var follow := false
## Mirror it when the fighter faces left.
@export var flip_with_facing := true
## Loop the frames; `loop_ticks` is how long it plays then (0: for the move's length).
@export var loop := false
@export var loop_ticks := 0
## Drawn scale on top of the ppu (1: as cut).
@export var scale := 1.0
## The scale when the move came out of a full charge (its "hold" values: Runoff's wave);
## 0 keeps `scale`.
@export var scale_held := 0.0


## How many ticks it plays: every frame once, or the loop's length.
func life(move_length: int = 0) -> int:
	if loop:
		return loop_ticks if loop_ticks > 0 else maxi(1, move_length)
	return frame_count() * ticks_per_frame


func frame_count() -> int:
	if frames == null or not frames.has_animation(animation):
		return 0
	return frames.get_frame_count(animation)


## The frame showing `t` ticks in (0 for the first), on this resource's clock.
func frame_at(t: float) -> int:
	var n := frame_count()
	if n <= 0:
		return 0
	var k := int(t / float(maxi(1, ticks_per_frame)))
	return posmod(k, n) if loop else mini(k, n - 1)


## Keys a move's `fx.move_fx` entry may set over the resource's own (a Dictionary entry:
## {"path": "res://assets/vfx/<name>.tres", "on": "hit", "scale": 0.6, ...}), so one cut
## serves many moves with their own hook, size and spot.
const OVERRIDES := ["on", "at", "offset", "follow", "flip_with_facing", "loop", "loop_ticks", "scale",
	"scale_held", "ticks_per_frame"]


## The MoveFx one `fx.move_fx` entry names: a path, or {"path": ..., <OVERRIDES>...} (a copy of
## the resource with those keys set; its frames shared). Null when the path isn't a MoveFx.
static func from_entry(v) -> MoveFx:
	var path := String(v.get("path", "")) if v is Dictionary else String(v)
	var r = load(path) if path != "" and ResourceLoader.exists(path) else null
	if not r is MoveFx:
		return null
	if not v is Dictionary:
		return r
	var f: MoveFx = (r as MoveFx).duplicate()
	for k in OVERRIDES:
		if not (v as Dictionary).has(k):
			continue
		var x = v[k]
		match k:
			"offset":
				f.offset = Vector2(float(x[0]), float(x[1]))
			"on":
				f.on = String(x)
			"follow", "flip_with_facing", "loop":
				f.set(k, bool(x))
			"scale", "scale_held":
				f.set(k, float(x))
			_:
				f.set(k, int(x))
	return f
