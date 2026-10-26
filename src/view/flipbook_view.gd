class_name FlipbookView
extends Node2D
## Flipbook hit effects: hand-drawn frame strips (assets/sprites/vfx/<name>.png, cut from
## kiddolink's VFX pack by tools/cut_packs.py) played where a move lands, from the view-only
## data file data/vfx.json (not read by the sim, not in the online data hash):
##
##   "effects": {name: {"frames": n, "size": [w, h], "ticks": per frame}}   one strip each,
##              frames side by side, the effect's middle at the frame's middle
##   "moves":   {"<fighter id>/<move slot>": {"effect": name, "flip": "face" (mirror when the
##              attacker faces left), "lift": px up from the hit point, "replace": true (FxView
##              skips its own burst for that hit; its pixels, flash and shake stay)}}
##
## FxView owns it (a child, so it draws over the sparks) and calls `hit` from `_hit_sparks`:
## an event FxView hides (an unseen fighter's) never gets here. Drawn whole-pixel at 1:1 (no
## scaling, no rotation), so the strips sit on the game's pixel grid. A fixed pool of CAP
## slots in packed arrays: nothing is allocated per hit or per frame; the oldest slot is
## reused when all are busy. Steps on FxView's clock (`advance(dt)`: KO slow motion slows it,
## a freeze holds it) and redraws only while something plays.

const PATH := "res://data/vfx.json"
const DIR := "res://assets/sprites/vfx/"
const CAP := 24

var _names: Array[String] = []        ## effect index -> name
var _tex: Array[Texture2D] = []
var _frames := PackedInt32Array()
var _size: Array[Vector2] = []
var _ticks := PackedFloat32Array()
var _moves := {}                      ## "id/slot" -> [effect index, flip by facing, lift, replace]

var _kind := PackedInt32Array()       ## per slot: effect index, -1 free
var _pos := PackedVector2Array()
var _t := PackedFloat32Array()
var _mirror := PackedByteArray()
var _next := 0
var _live := 0


func _init() -> void:
	_kind.resize(CAP)
	_kind.fill(-1)
	_pos.resize(CAP)
	_t.resize(CAP)
	_mirror.resize(CAP)
	_load()


func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return
	var effects: Dictionary = d.get("effects", {})
	for name in effects:
		var e: Dictionary = effects[name]
		var tex: Texture2D = load(DIR + String(name) + ".png")
		if tex == null:
			continue
		_names.append(String(name))
		_tex.append(tex)
		_frames.append(int(e.get("frames", 1)))
		var sz: Array = e.get("size", [tex.get_width(), tex.get_height()])
		_size.append(Vector2(float(sz[0]), float(sz[1])))
		_ticks.append(maxf(1.0, float(e.get("ticks", 3))))
	var moves: Dictionary = d.get("moves", {})
	for key in moves:
		var m: Dictionary = moves[key]
		var k := _names.find(String(m.get("effect", "")))
		if k >= 0:
			_moves[String(key)] = [k, String(m.get("flip", "")) == "face", float(m.get("lift", 0.0)),
				bool(m.get("replace", true))]


## The entry for a fighter's move ("id/slot"), or null: whether this hit plays a flipbook.
func entry_for(c: CreatureSim) -> Variant:
	if c == null or c.state != CreatureSim.State.ATTACK:
		return null
	return _moves.get(String(c.def.get("id", "")) + "/" + c.move_id)


## Plays the attacker's move's effect at the hit point `p`. Returns whether FxView should skip
## its own burst (the entry's "replace").
func hit(a: CreatureSim, p: Vector2) -> bool:
	var m = entry_for(a)
	if m == null:
		return false
	var i := _next
	_next = (_next + 1) % CAP
	if _kind[i] < 0:
		_live += 1
	_kind[i] = m[0]
	_pos[i] = (p - Vector2(0.0, m[2])).round()
	_t[i] = 0.0
	_mirror[i] = 1 if bool(m[1]) and a.facing.x < 0.0 else 0
	queue_redraw()
	return bool(m[3])


func advance(dt: float) -> void:
	if _live == 0 or dt <= 0.0:
		return
	for i in CAP:
		var k := _kind[i]
		if k < 0:
			continue
		_t[i] += dt
		if _t[i] >= _frames[k] * _ticks[k]:
			_kind[i] = -1
			_live -= 1
	queue_redraw()


func clear() -> void:
	_kind.fill(-1)
	_live = 0
	queue_redraw()


func playing() -> int:
	return _live


func _draw() -> void:
	if _live == 0:
		return
	for i in CAP:
		var k := _kind[i]
		if k < 0:
			continue
		var frame := mini(int(_t[i] / _ticks[k]), _frames[k] - 1)
		var sz: Vector2 = _size[k]
		var src := Rect2(frame * sz.x, 0.0, sz.x, sz.y)
		var half := (sz * 0.5).floor()
		if _mirror[i] == 1:
			draw_set_transform(_pos[i], 0.0, Vector2(-1.0, 1.0))
		else:
			draw_set_transform(_pos[i], 0.0, Vector2.ONE)
		draw_texture_rect_region(_tex[k], Rect2(-half, sz), src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
