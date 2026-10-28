class_name CrowdView
extends Node2D
## The crowd all round the stadium: the stands across the top, banked side stands left and
## right of the floor (the two sides' sections: red left, blue right) and low front rows
## under the front wall, their backs to the camera. Big moments raise excitement; more fans
## cheer and bounce, and camera flashes pop. A knockout makes the whole stadium jump (roar);
## every hit stands up a handful of fans in the stand nearest it (react).
##
## The fans are Szadi art's Warrior (tools/cut_crowd.py writes crowd.png from the pack): an
## army in many armour colours, red in the left side stand and blue in the right (the two
## sides' sections), the neutral stands a spread of greens, golds, purples, browns, steel and
## teal. Each sheet row is one fan variant (a facing, a colour set, skin and hair), baked:
## columns 0-3 sitting (the idle's breath poses), 4 on their feet cheering. Over a waterfall (Twin
## Keeps) two of them raise beer mugs (`set_size` `toasts`).

const SHEET := preload("res://assets/sprites/crowd.png")
## The seat a fan sits in, units (react's spot, the side stands' spacing, the blocks).
const W := 12
const H := 16
## The sheet: 2x art (ArtScale.PX_PER_UNIT texture px a unit), a cell a fan, CELL_W x CELL_H
## units, drawn RISE above its seat so the hips sit on the seat and a cheer has headroom.
const PPU := ArtScale.PX_PER_UNIT
const CELL_W := 12
const CELL_H := 24
const RISE := 8
const POSES := 4  ## sitting columns, the idle's breath poses (the toast's four poses)
const COL_CHEER := 4  ## the column of a fan on their feet
## The sheet's rows, in tools/cut_crowd.py GROUPS order: [first row, count] per group.
const ROWS_FRONT := Vector2i(0, 16)  ## facing the floor: the top stands
const ROWS_RED := Vector2i(16, 8)  ## the left stand's red side, facing right
const ROWS_BLUE := Vector2i(24, 8)  ## the right stand's blue side, facing left
const ROWS_MIXED_R := Vector2i(32, 8)  ## the left stand in a Brawl
const ROWS_MIXED_L := Vector2i(40, 8)  ## the right stand in a Brawl
const ROWS_BACK := Vector2i(48, 8)  ## the front rows, from behind
const MUG_ROW := 56  ## the two toasting fans, left then right
const SHEET_ROWS := 58
## The seated fans breathe without a redraw: a block's fans sit on BREATHS layers (by
## phase), each drawn once in its own idle pose, that rise half a unit (one art px) and
## settle every BREATH_TICKS, each layer and block on its own beat.
const BREATHS := 3
const BREATH_TICKS := 40
const BREATH_POSE := [0, 1, 2]  ## each beat's sheet column (idle frames 0, 2, 5)
const MUG_TICKS := 8  ## a toast's pose
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
const FRONT_CROP := 14  ## a front-row fan shows its top 14 units over its seat back
const BACK_SRC_Y := 13  ## ...the cell's rows from here (px): a little air, the head, shoulders
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
## Which colours a fan wears: the mixed crowd, the two sides' (red armour
## left, blue right, baked into the sheet: the colour-safe team set leaves them), and the mixed crowd seen from behind.
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
## The blocks near the screen (the last culling pass): the ones whose fans breathe.
var _near: Array[Block] = []
## The toasting fans over a waterfall: [seat position, sheet row] each, on a layer of their own.
var _mugs: Array = []
var _mug_layer: MugLayer
var _mug_col := -1


class MugLayer extends Node2D:
	var crowd: CrowdView

	func _draw() -> void:
		crowd._draw_mugs(self)


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
	var row := PackedInt32Array()  ## the fan's sheet row (their variant)
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
	var seated: Array[Seated] = []  ## the fans sitting, a layer per breath beat
	var offset := 0  ## this block's beat against its neighbours'


## A block's fans sitting, those of one breath beat (`part`, their phase % BREATHS), drawn
## once in that beat's idle pose; its position is their breath.
class Seated extends Node2D:
	var block: Block
	var part := 0

	func _draw() -> void:
		block.crowd._draw_sitting(block, self)


class Standing extends Node2D:
	var block: Block
	var parity := 0

	func _draw() -> void:
		block.crowd._draw_standing(block, self)


func _ready() -> void:
	_mug_layer = MugLayer.new()
	_mug_layer.crowd = self
	add_child(_mug_layer)
	_flash_layer = FlashLayer.new()
	_flash_layer.crowd = self
	add_child(_flash_layer)
	set_size(SimDefs.arena_size())


## Lays the seats round an arena `size` px big (a bigger map's is bigger): the top stand
## runs on past it for wide screens (ArenaView.MARGIN), the side stands down its sides and
## the front rows along its front. `teams`: the side stands wear the two sides' colours (a
## match of two sides; a Brawl of three or four keeps them mixed). `toasts`: world x of a
## waterfall under the top stand (`toasts_for`): the two seats over it in the lowest row
## get the fans raising beer mugs.
func set_size(size: Vector2, teams := true, toasts := PackedFloat32Array()) -> void:
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
	_near.clear()
	_mugs.clear()
	_mug_col = -1
	var by_key := {}
	var from := -int(ArenaView.MARGIN.x / 12.0)
	var to := int((size.x + ArenaView.MARGIN.x) / 12.0)
	# the toasters' seats: the pair in the lowest row whose middles straddle the waterfall
	var toast_seats := {}
	var low := TOP_ROWS - 1
	for x in toasts:
		var i0 := floori((x - 8.0 - (low % 2) * 6) / 12.0)
		toast_seats[i0] = MUG_ROW
		toast_seats[i0 + 1] = MUG_ROW + 1
	for row in TOP_ROWS:
		for i in range(from, to):
			var p := Vector2(2 + i * 12 + (row % 2) * 6, 1 + row * 14)
			if row == low and toast_seats.has(i):
				_mugs.append([p, toast_seats[i]])
				_flash_spots.append(p)
				continue
			if posmod(i * 3 + row * 5, 11) == 0:
				continue  # leave a few empty seats
			_add_seat(by_key, Stand.TOP, p, _pick(ROWS_FRONT, i * 5 + row * 3), Look.MIXED,
				posmod(i * 7 + row * 11, 13), Color.WHITE)
			_flash_spots.append(p)
	for side in 2:
		var stand := Stand.LEFT if side == 0 else Stand.RIGHT
		var look := (Look.RED if side == 0 else Look.BLUE) if teams else Look.MIXED
		var rows: Vector2i = (ROWS_RED if side == 0 else ROWS_BLUE) if teams \
			else (ROWS_MIXED_R if side == 0 else ROWS_MIXED_L)
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
					_add_seat(by_key, stand, p, _pick(rows, j * 5 + k * 3 + side * 7), look,
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
			_add_seat(by_key, Stand.FRONT, p, _pick(ROWS_BACK, i * 3 + r * 5), Look.BACK,
				posmod(i * 7 + r * 5, 13), Color(f, f, f))
	for b in by_key.values():
		b.by_phase.resize(PHASES)
		for ph in PHASES:
			b.by_phase[ph] = PackedInt32Array()
		for i in b.pos.size():
			b.by_phase[b.phase[i]].append(i)
			b.dst.append(fan_dst(b.pos[i], b.look[i]))
			b.src_up.append(fan_src(b.row[i], COL_CHEER, b.look[i]))
		b.offset = posmod(_blocks.size() * 17, BREATH_TICKS * 2)
		for part in BREATHS:
			var se := Seated.new()
			se.block = b
			se.part = part
			b.seated.append(se)
			b.add_child(se)
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
	if _mug_layer != null:
		move_child(_mug_layer, -1)
		_mug_layer.queue_redraw()
	if _flash_layer != null:
		move_child(_flash_layer, -1)


## Column k of a side stand sits a little higher the further out it is (banked), staggered.
static func side_dy(k: int) -> int:
	return (k % 2) * 6 - k * 2


## A variant row of a group, `n` (the seat's own number) hashed into it: neighbours differ.
static func _pick(rows: Vector2i, n: int) -> int:
	var h := ((n + 1013) * 0x9E3779B1) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	return rows.x + (h ^ (h >> 12)) % rows.y


## Where a fan's cell goes over its seat at `p`: its rise above the seat; from behind, only
## the window over the seat back (FRONT_CROP).
static func fan_dst(p: Vector2, look: int) -> Rect2:
	if look == Look.BACK:
		return Rect2(p, Vector2(CELL_W, FRONT_CROP))
	return Rect2(p - Vector2(0, RISE), Vector2(CELL_W, CELL_H))


## The sheet's rect for a fan: their row, a column (a breath pose or COL_CHEER).
static func fan_src(row: int, col: int, look: int) -> Rect2:
	var cell := Vector2(CELL_W, CELL_H) * PPU
	if look == Look.BACK:
		return Rect2(col * cell.x, row * cell.y + BACK_SRC_Y, cell.x, FRONT_CROP * PPU)
	return Rect2(Vector2(col, row) * cell, cell)


## The world x of each waterfall in an arena's tiles (`anim` entries of kind "waterfall",
## Twin Keeps), where two fans in the stand above it raise their mugs. The view reads the
## arena's data and never writes it.
static func toasts_for(arena: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var tiles: Dictionary = arena.get("tiles", {})
	for e in tiles.get("anim", []):
		if String(e.get("kind", "")) != "waterfall":
			continue
		if e.has("pos"):
			out.append(SimDefs.GRID_X + float(e["pos"][0]))
		elif e.has("at"):
			out.append(SimDefs.GRID_X + (float(e["at"][0]) + 0.5) * ArtScale.TILE_PX / PPU)
	return out


func _add_seat(by_key: Dictionary, stand: int, p: Vector2, row: int, look: int, ph: int, tint: Color) -> void:
	var key := Vector3i(stand, floori(p.x / BLOCK), floori(p.y / BLOCK))
	var b: Block = by_key.get(key)
	if b == null:
		b = Block.new()
		b.crowd = self
		b.stand = stand
		b.area = Rect2(p, Vector2.ZERO)
		by_key[key] = b
	b.pos.append(p)
	b.row.append(row)
	b.look.append(look)
	b.phase.append(ph)
	b.tint.append(tint)
	b.up_until.append(0)
	b.area = b.area.merge(Rect2(p - Vector2(0, RISE + 3), Vector2(W, CELL_H + 3)))


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
		_near.clear()
		for bx in range(floori(seen.position.x / BLOCK), floori(seen.end.x / BLOCK) + 1):
			for b: Block in _cols.get(bx, []):
				if not b.area.intersects(seen) or b in _near:
					continue
				_near.append(b)
				if b.drawn != key or b.drawn_version != b.version:
					b.drawn = key
					b.drawn_version = b.version
					b.standing[0].queue_redraw()
					b.standing[1].queue_redraw()
				if b.standing[0].position.y != lift_even:
					b.standing[0].position.y = lift_even
					b.standing[1].position.y = lift_odd
	# The seated fans breathing: each layer near the screen on its own beat (a move, no redraw).
	for b in _near:
		for se in b.seated:
			var y := -0.5 if ((_tick + b.offset + se.part * 27) / BREATH_TICKS) % 2 == 0 else 0.0
			if se.position.y != y:
				se.position.y = y
	# The toasting fans: a pose every MUG_TICKS, clinking on their feet in a roar.
	if not _mugs.is_empty() and _mug_layer != null:
		var col := (_tick / MUG_TICKS) % POSES
		if _roar > 0:
			col = COL_CHEER if (_tick / 4) % 2 == 0 else 2
		if col != _mug_col:
			_mug_col = col
			_mug_layer.queue_redraw()
	if _flash_layer != null and (_drawn_flashes or not _flashes.is_empty()):
		_drawn_flashes = not _flashes.is_empty()
		_flash_layer.queue_redraw()


## The part of this node's space on screen now.
func _view_rect() -> Rect2:
	if not is_inside_tree():
		return Rect2()
	return get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()


## The block's fans of one breath beat sitting (once): a standing fan is drawn over their
## own seat.
func _draw_sitting(b: Block, layer: Seated) -> void:
	var t0 := PerfLog.now()
	var tex := sheet()
	for i in b.pos.size():
		if b.phase[i] % BREATHS == layer.part:
			layer.draw_texture_rect_region(tex, b.dst[i], fan_src(b.row[i], BREATH_POSE[layer.part], b.look[i]), b.tint[i])
	PerfLog.since("crowd draw", t0)


## The two fans over a waterfall, their mugs up (_mug_col: the toast's pose).
func _draw_mugs(ci: CanvasItem) -> void:
	var tex := sheet()
	for m in _mugs:
		ci.draw_texture_rect_region(tex, fan_dst(m[0], Look.MIXED), fan_src(m[1], maxi(0, _mug_col), Look.MIXED))


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


## crowd.png as a texture (tools/cut_crowd.py bakes every variant: nothing to build here).
static func sheet() -> Texture2D:
	return SHEET
