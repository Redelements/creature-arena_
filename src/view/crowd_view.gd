class_name CrowdView
extends Node2D
## The crowd all round the stadium: the stands across the top, banked side stands left and
## right of the floor (the two sides' sections: red left, blue right) and low front rows
## under the front wall, their backs to the camera. Big moments raise excitement; more fans
## cheer and bounce, and camera flashes pop. A knockout makes the whole stadium jump (roar);
## every hit stands up a handful of fans in the stand nearest it (react).

const SHEET := preload("res://assets/sprites/crowd.png")
const W := 12
const H := 16
## Where the seats are, in step with tools/gen_arenas.py (_stands, _side_stands,
## _front_stands), which draws the steps and seat backs they sit on.
const TOP_ROWS := 3
const SIDE_RAIL := 4  ## the rail between a side wall and the first column of seats
const SIDE_COL_W := 13  ## one column of a side stand (a row of it, running up the screen)
const SIDE_FANS := 5  ## columns with fans in them; the art fades further ones into the dark
const SIDE_Y0 := 70
const SIDE_STEP := 12
const SIDE_AISLE := 9  ## every ninth place down a column is a stair
const FRONT_GAP := 2
const FRONT_STEP := 13
const FRONT_FANS := 2
const FRONT_CROP := 12  ## a front-row fan shows its top 12 px over its seat back
## How far past the arena's sides and front the camera may look when the fight nears an
## edge (main._cam_axis), so these stands come into shot.
const SHOW_SIDE := 64.0
const SHOW_FRONT := 32.0
## ...and above it: the two far tiers, the roof edge and a strip of sky (BackdropView).
const SHOW_TOP := 88.0
## Seats are grouped in blocks about this big, each its own canvas item: a picture change
## redraws only the blocks near the screen, and a hit's fans only their own block.
const BLOCK := 96.0
## One hit stands up this many fans, for this long, within this of the spot nearest it in
## its stand; at most REACT_CAP fans stand up in one tick (a crowded field lands several
## hits a tick).
const REACT_FANS := 6
const REACT_TICKS := 24
const REACT_R := 40.0
const REACT_CAP := 12
## Rows of the sheet built from crowd.png by swapping colours (no new art): the mixed crowd,
## red shirts, blue shirts (Hud.SIDE_COLORS), and the mixed crowd seen from behind.
enum Look { MIXED, RED, BLUE, BACK }
enum Stand { TOP, LEFT, RIGHT, FRONT }

var excitement := 0.1
var _tick := 0
var _roar := 0
var _flashes: Array[Dictionary] = []
var _flash_spots := PackedVector2Array()
var _blocks: Array[Block] = []
var _cols := {}  ## BLOCK-wide column of the world (x) -> the blocks reaching into it
## What the blocks were last checked against: the picture's key, the bounce, the part of
## the world near the screen (twice CULL_PAD round it, so a tick whose view is still well
## inside it, with the same key and bounce and no hit's fans changing, checks nothing).
var _checked_key := Vector3i(-1, -1, -1)
var _checked_lift := 0.0
var _checked_rect := Rect2()
var _dirty := true
var _active: Array[Block] = []  ## blocks with fans standing up for a hit
var _size := Vector2(SimDefs.ARENA_W, SimDefs.ARENA_H)
var _react_left := REACT_CAP
## Each block draws its fans sitting once, when it's made; the fans on their feet go on two
## layers over them (Block.standing, odd and even phases), redrawn when the picture's key
## (how many cheer, who, a roar) or the block's version (a hit's fans) changed since, and
## only once the block nears the screen (CULL_PAD): a big map's stands are mostly off
## screen, and a standing fan costs one sprite where redrawing everyone cost them all. The
## bounce moves a layer (its position), never redraws it.
const CULL_PAD := 32.0
const PHASES := 13
## The camera flashes, on a layer of their own over the seats: they pop on most ticks of
## a busy fight, and redrawing a few pixels is nothing next to redrawing the seats.
var _flash_layer: FlashLayer
var _drawn_flashes := false
static var _sheet: Texture2D


class FlashLayer extends Node2D:
	var crowd: CrowdView

	func _draw() -> void:
		crowd._draw_flashes(self)


## A group of seats: its fans sitting, drawn once, and `standing`, the ones on their feet.
class Block extends Node2D:
	var crowd: CrowdView
	var stand := 0
	var area := Rect2()
	var pos := PackedVector2Array()
	var frame := PackedInt32Array()  ## the variant's first frame (sitting; +1 standing)
	var look := PackedInt32Array()
	var phase := PackedInt32Array()
	var tint := PackedColorArray()
	var by_phase: Array[PackedInt32Array] = []  ## seat indices by phase (who cheers when)
	var dst: Array[Rect2] = []  ## where each fan goes, and their standing frame
	var src_up: Array[Rect2] = []
	var up_until := PackedInt32Array()  ## standing for a hit until this tick
	var reacting := PackedInt32Array()  ## the seats standing for a hit
	var ends := PackedInt32Array()  ## ticks when a hit's fans here sit down again
	var version := 0
	var drawn := Vector3i(-1, -1, -1)
	var drawn_version := -1
	var standing: Array[Standing] = []  ## the even phases' fans, the odd phases'

	func _draw() -> void:
		crowd._draw_sitting(self)


class Standing extends Node2D:
	var block: Block
	var parity := 0

	func _draw() -> void:
		block.crowd._draw_standing(block, self)


func _ready() -> void:
	_flash_layer = FlashLayer.new()
	_flash_layer.crowd = self
	add_child(_flash_layer)
	set_size(SimDefs.arena_size())


## Lays the seats round an arena `size` px big (a bigger map's is bigger): the top stand
## runs on past it for wide screens (ArenaView.MARGIN), the side stands down its sides and
## the front rows along its front. `teams`: the side stands wear the two sides' colours (a
## match of two sides; a Brawl of three or four keeps them mixed).
func set_size(size: Vector2, teams := true) -> void:
	_size = size
	for b in _blocks:
		remove_child(b)
		b.queue_free()
	_blocks.clear()
	_cols.clear()
	_dirty = true
	_active.clear()
	_flashes.clear()
	_flash_spots.clear()
	var by_key := {}
	var from := -int(ArenaView.MARGIN.x / 12.0)
	var to := int((size.x + ArenaView.MARGIN.x) / 12.0)
	for row in TOP_ROWS:
		for i in range(from, to):
			if posmod(i * 3 + row * 5, 11) == 0:
				continue  # leave a few empty seats
			var p := Vector2(2 + i * 12 + (row % 2) * 6, 1 + row * 14)
			_add_seat(by_key, Stand.TOP, p, posmod(i * 5 + row * 3, 4), Look.MIXED,
				posmod(i * 7 + row * 11, 13), Color.WHITE)
			_flash_spots.append(p)
	for side in 2:
		var stand := Stand.LEFT if side == 0 else Stand.RIGHT
		var look := (Look.RED if side == 0 else Look.BLUE) if teams else Look.MIXED
		for k in SIDE_FANS:
			var x: float = -SIDE_RAIL - (k + 1) * SIDE_COL_W + 1 if side == 0 \
				else size.x + SIDE_RAIL + k * SIDE_COL_W
			# the concourse's darkening going out (gen_arenas.py _side_and_front)
			var f := 1.0 - (SIDE_RAIL + k * SIDE_COL_W + 6.0) / 260.0
			var j := 0
			while true:
				var y := SIDE_Y0 + j * SIDE_STEP + side_dy(k)
				if y + H > size.y:
					break
				if j % SIDE_AISLE != SIDE_AISLE - 1 and posmod(j * 3 + k * 5 + side, 11) != 0:
					var p := Vector2(x, y)
					_add_seat(by_key, stand, p, posmod(j * 5 + k * 3 + side, 4), look,
						posmod(j * 7 + k * 11 + side * 5, 13), Color(f, f, f))
					_flash_spots.append(p)
				j += 1
	for r in FRONT_FANS:
		var y0 := size.y + FRONT_GAP + r * FRONT_STEP
		var f := 1.0 - (FRONT_GAP + r * FRONT_STEP + 8.0) / 260.0
		for i in range(from, to):
			if posmod(i * 5 + r * 7, 11) == 0:
				continue
			var p := Vector2(2 + i * 12 + (r % 2) * 6, y0 + 7 - FRONT_CROP)
			_add_seat(by_key, Stand.FRONT, p, posmod(i * 3 + r * 5, 4), Look.BACK,
				posmod(i * 7 + r * 5, 13), Color(f, f, f))
	for b in by_key.values():
		b.by_phase.resize(PHASES)
		for ph in PHASES:
			b.by_phase[ph] = PackedInt32Array()
		for i in b.pos.size():
			b.by_phase[b.phase[i]].append(i)
			var h := FRONT_CROP if b.look[i] == Look.BACK else H
			b.dst.append(Rect2(b.pos[i], Vector2(W, h)))
			b.src_up.append(Rect2((b.frame[i] + 1) * W, b.look[i] * H, W, h))
		for bx in range(floori(b.area.position.x / BLOCK), floori(b.area.end.x / BLOCK) + 1):
			if not _cols.has(bx):
				_cols[bx] = []
			_cols[bx].append(b)
		for parity in 2:
			var st := Standing.new()
			st.block = b
			st.parity = parity
			b.standing.append(st)
			b.add_child(st)
		_blocks.append(b)
		add_child(b)
	if _flash_layer != null:
		move_child(_flash_layer, -1)


## Column k of a side stand sits a little higher the further out it is (banked), staggered.
static func side_dy(k: int) -> int:
	return (k % 2) * 6 - k * 2


func _add_seat(by_key: Dictionary, stand: int, p: Vector2, variant: int, look: int, ph: int, tint: Color) -> void:
	var key := Vector3i(stand, floori(p.x / BLOCK), floori(p.y / BLOCK))
	var b: Block = by_key.get(key)
	if b == null:
		b = Block.new()
		b.crowd = self
		b.stand = stand
		b.area = Rect2(p, Vector2.ZERO)
		by_key[key] = b
	b.pos.append(p)
	b.frame.append(variant * 2)
	b.look.append(look)
	b.phase.append(ph)
	b.tint.append(tint)
	b.up_until.append(0)
	b.area = b.area.merge(Rect2(p - Vector2(0, 3), Vector2(W, H + 3)))


func cheer(amount: float) -> void:
	excitement = minf(1.0, excitement + amount)


## Everyone on their feet for `ticks` frames.
func roar(ticks: int) -> void:
	_roar = maxi(_roar, ticks)
	excitement = 1.0


## A hit at `pos` on the floor: up to `fans` fans in the stand nearest it stand up for a
## moment (REACT_TICKS), the ones nearest the spot facing it first.
func react(pos: Vector2, fans := REACT_FANS) -> void:
	fans = mini(fans, _react_left)
	if fans <= 0 or _blocks.is_empty():
		return
	var stand := Stand.TOP
	var spot := Vector2(pos.x, 22)
	var best := pos.y - 52.0
	if pos.x < best:
		best = pos.x
		stand = Stand.LEFT
		spot = Vector2(-SIDE_RAIL - SIDE_COL_W * 2, pos.y - 8)
	if _size.x - pos.x < best:
		best = _size.x - pos.x
		stand = Stand.RIGHT
		spot = Vector2(_size.x + SIDE_RAIL + SIDE_COL_W * 2, pos.y - 8)
	if _size.y - pos.y < best:
		stand = Stand.FRONT
		spot = Vector2(pos.x, _size.y + 8)
	var near: Array = []
	var reach := Rect2(spot, Vector2.ZERO).grow(REACT_R)
	for b in _blocks:
		if b.stand != stand or not b.area.intersects(reach):
			continue
		for i in b.pos.size():
			var d := (b.pos[i] + Vector2(W, H) * 0.5).distance_squared_to(spot)
			if d <= REACT_R * REACT_R and b.up_until[i] <= _tick:
				near.append([d, b, i])
	if near.is_empty():
		return
	near.sort_custom(func(a, c): return a[0] < c[0])
	var end := _tick + REACT_TICKS
	for n in mini(fans, near.size()):
		var b: Block = near[n][1]
		var i: int = near[n][2]
		if b.up_until[i] == 0 or not i in b.reacting:
			b.reacting.append(i)
		b.up_until[i] = end
		if b.ends.is_empty() or b.ends[b.ends.size() - 1] != end:
			b.ends.append(end)
			b.version += 1
			_dirty = true
			if not b in _active:
				_active.append(b)
		_react_left -= 1


func advance() -> void:
	_tick += 1
	_react_left = REACT_CAP
	excitement = maxf(0.1, excitement * 0.985)
	if _roar > 0:
		_roar -= 1
	# Camera flashes once the crowd gets excited.
	var chance := maxf(0.0, excitement - 0.35) * 0.9 + (0.5 if _roar > 0 else 0.0)
	while chance > 0.0:
		if randf() < chance and not _flash_spots.is_empty():
			var s := _flash_spots[randi() % _flash_spots.size()]
			_flashes.append({"pos": s + Vector2(randi_range(3, 8), randi_range(2, 6)), "t": 3})
		chance -= 1.0
	for f in _flashes:
		f["t"] = int(f["t"]) - 1
	_flashes = _flashes.filter(func(f): return int(f["t"]) > 0)
	# A hit's fans sitting down again.
	for k in range(_active.size() - 1, -1, -1):
		var b := _active[k]
		var sat := false
		while not b.ends.is_empty() and b.ends[0] <= _tick:
			b.ends.remove_at(0)
			b.version += 1
			sat = true
			_dirty = true
		if sat:
			var still := PackedInt32Array()
			for i in b.reacting:
				if b.up_until[i] > _tick:
					still.append(i)
			b.reacting = still
		if b.ends.is_empty():
			_active.remove_at(k)
	var cheering := 10 if _roar > 0 else int(excitement * 10.0)
	var key := Vector3i(cheering, _tick / 6, int(_roar > 0))
	var lift := -3.0 if _roar > 0 else -2.0
	var lift_even := lift if (_tick / 4) % 2 == 0 else 0.0
	var lift_odd := lift - lift_even
	var view := _view_rect()
	if _dirty or key != _checked_key or lift_even != _checked_lift 			or not _checked_rect.encloses(view.grow(CULL_PAD)):
		_dirty = false
		_checked_key = key
		_checked_lift = lift_even
		_checked_rect = view.grow(CULL_PAD * 2.0)
		var seen := _checked_rect
		for bx in range(floori(seen.position.x / BLOCK), floori(seen.end.x / BLOCK) + 1):
			for b: Block in _cols.get(bx, []):
				if not b.area.intersects(seen):
					continue
				if b.drawn != key or b.drawn_version != b.version:
					b.drawn = key
					b.drawn_version = b.version
					b.standing[0].queue_redraw()
					b.standing[1].queue_redraw()
				if b.standing[0].position.y != lift_even:
					b.standing[0].position.y = lift_even
					b.standing[1].position.y = lift_odd
	if _flash_layer != null and (_drawn_flashes or not _flashes.is_empty()):
		_drawn_flashes = not _flashes.is_empty()
		_flash_layer.queue_redraw()


## The part of this node's space on screen now.
func _view_rect() -> Rect2:
	if not is_inside_tree():
		return Rect2()
	return get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()


## Everyone in the block sitting (once): a standing fan is drawn over their own seat.
func _draw_sitting(b: Block) -> void:
	var t0 := PerfLog.now()
	var tex := sheet()
	for i in b.pos.size():
		var lk := b.look[i]
		var h := FRONT_CROP if lk == Look.BACK else H
		b.draw_texture_rect_region(tex, Rect2(b.pos[i], Vector2(W, h)), Rect2(b.frame[i] * W, lk * H, W, h), b.tint[i])
	PerfLog.since("crowd draw", t0)


## A block's fans on their feet, the phases of one parity: those cheering now, then any
## standing for a hit. (The layer's position is their bounce.)
func _draw_standing(b: Block, layer: Standing) -> void:
	var t0 := PerfLog.now()
	var tex := sheet()
	var cheering := 10 if _roar > 0 else int(excitement * 10.0)
	var t6 := _tick / 6
	for ph in range(layer.parity, PHASES, 2):
		if (t6 + ph) % 10 < cheering:
			for i in b.by_phase[ph]:
				layer.draw_texture_rect_region(tex, b.dst[i], b.src_up[i], b.tint[i])
	for i in b.reacting:
		var ph := b.phase[i]
		if ph % 2 == layer.parity and b.up_until[i] > _tick and (t6 + ph) % 10 >= cheering:
			layer.draw_texture_rect_region(tex, b.dst[i], b.src_up[i], b.tint[i])
	PerfLog.since("crowd draw", t0)


func _draw_flashes(ci: CanvasItem) -> void:
	for f in _flashes:
		var fp: Vector2 = f["pos"]
		var big := int(f["t"]) >= 3
		ci.draw_rect(Rect2(fp - Vector2(1, 1), Vector2(3, 3)) if big else Rect2(fp, Vector2(1, 1)), Color(1, 1, 0.92, 0.95))
		if big:
			ci.draw_rect(Rect2(fp - Vector2(3, 0), Vector2(7, 1)), Color(1, 1, 0.9, 0.5))
			ci.draw_rect(Rect2(fp - Vector2(0, 3), Vector2(1, 7)), Color(1, 1, 0.9, 0.5))


## crowd.png's eight frames (four fans, sitting and standing) in four looks (Look), built
## once by swapping colours: the shirts for the two sides' colours, and for the look from
## behind each head's skin for hair. Colours as tools/gen_sprites.py:fan draws them.
static func sheet() -> Texture2D:
	if _sheet != null:
		return _sheet
	var src := SHEET.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var fw := src.get_width()
	var out := Image.create(fw, H * 4, false, Image.FORMAT_RGBA8)
	var shirts := [Color8(196, 72, 72), Color8(70, 120, 190), Color8(220, 180, 60), Color8(90, 160, 110)]
	var skins := [Color8(232, 190, 150), Color8(190, 135, 95), Color8(140, 95, 65), Color8(245, 215, 180)]
	var hair := [Color8(60, 40, 30), Color8(28, 22, 20), Color8(120, 70, 36), Color8(150, 104, 56)]
	for lk in 4:
		for y in H:
			for x in fw:
				var c := src.get_pixel(x, y)
				var v := (x / W) / 2
				var standing := (x / W) % 2 == 1
				var lx := x % W
				if (lk == Look.RED or lk == Look.BLUE) and _same(c, shirts[v]):
					var team: Color = Hud.SIDE_COLORS[0 if lk == Look.RED else 1]
					c = [team.darkened(0.25), team.darkened(0.45), team.darkened(0.1), team.darkened(0.6)][v]
				elif lk == Look.BACK and _same(c, skins[v]) and y <= 8 and lx <= 8 \
						and (lx >= 3 or (lx == 2 and not standing)):
					c = hair[v]
				out.set_pixel(x, y + lk * H, c)
	_sheet = ImageTexture.create_from_image(out)
	return _sheet


static func _same(a: Color, b: Color) -> bool:
	return a.a > 0.5 and absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
