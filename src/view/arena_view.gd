class_name ArenaView
extends Node2D
## Draws the stadium: stands, walls, and the breakable floor from the terrain grid.
## Redraws only the rows whose cells changed (BAND_ROWS).
## A map with its own art (assets/sprites/arena_<id>.png, tools/gen_arenas.py) draws that
## picture as the whole backdrop (stands, walls, floor, court lines, and the map's pieces
## as it starts). A cell whose piece has changed shows its piece of arena_<id>_alt.png
## (a smashed wall's rubble, flattened brush). A cracked cell shows
## its piece of arena_<id>_cracked.png (the same floor broken by one network of cracks, so
## a cracked patch joins up); pieces and pits are drawn on top as usual, each pit with a
## broken lip of floor where it meets solid ground.
## A hole in a map's bridge ("bridges"), or the bridge fallen in (its cells shallows),
## shows the river under it from the _alt picture, rather than a pit or the planks.
## A map without one is drawn from the tiles below.
## The art has the pieces' shadows cast along the map's light ("light", ShadowLayer.light_of).
## A piece that changes (a wall smashed, brush flattened, a bridge fallen) takes its shadow
## with it: a floor cell in the shadow of changing pieces shows the _alt picture (which has
## none of their shadows) once every piece shading it has changed (`_shade`).
##
## Pits have depth (`_paint_pit_cell`): a far wall under the lip, then dark going down in
## dithered whole-pixel steps, side walls lit or shaded by the map's light, a ragged lip of
## floor with pebbles round it, and a lit near edge. Chasms use a colder, deeper set with a
## little mist. Their tones are one small texture built per map (`_build_pit_tex`).
## The floor also moves (`refresh` → `_step_fx`, two layers of their own so the bands stay
## cached): a crack runs across its cell over a few ticks, spreading out from the blow, with
## a puff of dust (`_grow`, the under layer); a fresh pit breathes dust for a second or two
## and drops a pebble or two off its rim (`_motes`); a pit about to heal closes in from its
## rim, and knitting cracks glow faintly before the floor turns solid (`_heal_cells`,
## `_knit`, arena_<id>_crackmask.png), on the over layer.

const TILES := preload("res://assets/sprites/tiles.png")
## Arena map pieces (tools/gen_sprites.py tiles_sheet; its pit tiles 8, 9, 14, 15 are unused
## now that pits are drawn with depth).
const TILE_WALL_TOP := 10  # two variants
const TILE_WALL_FACE := 12
const TILE_FENCE := 13
const TILE_SHALLOWS := 16  # two variants
const TILE_BRUSH := 18  # two variants
const TILE_BRUSH_FLAT := 20
const TILE_RUBBLE_FLOOR := 21
## How each map's ground tints the dirt tiles (the map's "ground" key).
const GROUND_TINT := {
	"dirt": Color(1.0, 1.0, 1.0),
	"stone": Color(0.86, 0.86, 0.9),
	"concrete": Color(0.78, 0.82, 0.88),
	"grass": Color(0.84, 0.98, 0.72),
}
var ground := "dirt":
	set(v):
		if v != ground:
			ground = v
			_rebuild()

const C_BG := Color("1b1e26")
const C_STAND_A := Color("3a3f4e")
const C_STAND_B := Color("323645")
const C_RAIL := Color("23262f")
const C_WALL := Color("5d6470")
const C_WALL_TOP := Color("8a909a")
const C_WALL_DARK := Color("464c58")
const C_LINE := Color(1, 1, 1, 0.2)
## Over a cracked cell on a map with art but no cracked picture: a shade darker.
const C_CRACKED_SHADE := Color(0.18, 0.09, 0.04, 0.16)
## How far the stadium carries on past its walls, for when the camera pulls back and for
## wider (ultrawide) and taller (16:10) screens: they see more stands and wall.
const MARGIN := Vector2(400, 80)

var terrain: TerrainGrid
var _drawn_version := -1
## The map's id (its arena JSON "id"): picks its art, if it has any.
var arena_id := "":
	set(v):
		if v != arena_id:
			arena_id = v
			var path := "res://assets/sprites/arena_%s.png" % v
			_art = load(path) if v != "" and ResourceLoader.exists(path) else null
			var cpath := "res://assets/sprites/arena_%s_cracked.png" % v
			_art_cracked = load(cpath) if _art != null and ResourceLoader.exists(cpath) else null
			var apath := "res://assets/sprites/arena_%s_alt.png" % v
			_art_alt = load(apath) if _art != null and ResourceLoader.exists(apath) else null
			var mpath := "res://assets/sprites/arena_%s_crackmask.png" % v
			_mask = load(mpath) if _art != null and ResourceLoader.exists(mpath) else null
			_bridges = ArenaMap.bridge_rects(ArenaMap.get_map(v)) if v != "" else []
			var spath := "res://assets/arenas/%s.tscn" % v
			_scene = load(spath) if v != "" and ResourceLoader.exists(spath) else null
			var tset := String(ArenaMap.get_map(v).get("tiles", {}).get("set", "set1")) if v != "" else ""
			var opath := "res://assets/tiles/%s_overlay.tres" % tset
			_overlay_set = load(opath) if _scene != null and ResourceLoader.exists(opath) else null
			if _overlay_set != null:
				# The overlay tiles draw the cracks and pits; pieces of the old baked picture
				# (its cracks, its crack mask) would show through as a second style.
				_art_cracked = null
				_mask = null
			_markings = bool(ArenaMap.get_map(v).get("tiles", {}).get("markings", false)) if v != "" else false
			_rebuild()
var _art: Texture2D = null

# ---------------------------------------------------------------- tiled maps
## A map built from ground tiles instead of a baked picture (assets/arenas/<id>.tscn, made by
## tools/build_tiles.gd from a cut pack): its scene is instanced under the floor at
## 1 / ArtScale.PX_PER_UNIT scale (a 32 px tile is 2 x 2 cells), and the breaking ground is
## three TileMapLayers of 16 px overlay tiles (one a cell) set from the terrain: `_overlay`
## carries a cracked cell's crack (joined to its cracked or open neighbours) or a pit cell's
## far wall / floor by depth, `_edges` the floor's edge down a pit's sides and along its near
## rim, `_corners` the bit of lip where a pit turns round a solid diagonal cell. The ids are the overlay atlas's
## (assets/tiles/<set>_overlay.png, index = column + 8 * row; assets/README.md names them
## for the artist). The scene's "Pieces" layer loses a boulder whose wall is smashed and a
## tuft whose brush is flattened, and gets them back when the floor heals; its sprite
## pieces ("Brush" clumps, "Walls" runs and their "Rubble") swap the same way (`_sync_sprites`).
var _scene: PackedScene = null
var _overlay_set: TileSet = null
var _markings := false  ## the map's `tiles.markings`: court lines over the tiles (the Stadium)
var _tiles: Node2D = null
var _overlay: TileMapLayer = null
var _edges: TileMapLayer = null
var _corners: TileMapLayer = null
var _piece_cells := {}  ## the scene's pieces as built: tile -> [source, atlas coords]
## A raised-wall map (styles.wall "raised:<name>", RaisedTiles): the scene's "Raised" and
## "RaisedShadow" layers, their meta, and the map's wall cells; repainted round a smashed cell.
var _raised: TileMapLayer = null
var _raised_shadow: TileMapLayer = null
var _raised_info := {}
var _raised_walls := {}
const DRESS_PROPS := "Walls/Dressing/Props"  ## a map's hand-dressed props (`_dress_cells`)
const DRESS_CANOPIES := "Walls/Dressing/Canopies"  ## its tree crowns (`_adopt_canopies`)
## Tree crowns over the fighters (a map's dressing "Canopies": the mid-field groves, the
## crowns over the brush beds). Main's node above the fighters; they move into it at load
## (without one, as in tests, they stay in the ground scene). View only.
var overhead: Node2D = null
## Where the fighters the local team sees stand this tick (main, `canopy_watchers`): a crown
## over one of them fades to CANOPY_SEE so they read; never over a hidden foe.
var canopy_points: Array = []
var _canopies: Array = []  ## [node, world rect, brush cells under it (Rect2i)]
const CANOPY_SEE := 0.35  ## a crown's opacity over one of ours
const CANOPY_THIN := 0.6  ## over a bed whose brush is flattened under it
const CANOPY_FADE := 4.0  ## opacity a second, eased on the view clock (about 10 frames)
const OV_COLS := 8
const OV_CRACK := [0, 1, 2, 3]
const OV_WALL_TOP := 8
const OV_WALL_MID := 9
const OV_WALL_BOTTOM := 10
const OV_FLOOR := 11
const OV_CHASM_TOP := 12  ## the same four for a chasm, OV_CHASM_TOP + depth
const OV_EDGE_L := 16
const OV_EDGE_R := 17
const OV_EDGE_LR := 18
const OV_RIM := 19  ## the near rim; + 1 with the left side, + 2 the right, + 3 both
const OV_PHASE_B := 16  ## a pit tile in an odd column: the right half of the 32 px face
const OV_CRACK_JOIN := 32  ## + 1 left, 2 right, 4 top, 8 bottom: the sides a crack runs out of
const OV_CORNER := 48  ## + 1 top left, 2 top right, 4 bottom left, 8 bottom right


## Whether this map draws from ground tiles (no baked picture).
func tiled() -> bool:
	return _scene != null


## How far (world px) the tiles' bank reaches into the painted water (the scene's
## "WaterBank" layer, tools/tile_recipes `shores`: a side bank of 9 px at 2 a unit, its wet
## line and shade), 0 when the map draws no bank. WaterView keeps its foam clear of it.
const WATER_BANK := 7.0


func water_bank() -> float:
	if _tiles == null or _tiles.get_node_or_null("WaterBank") == null:
		return 0.0
	return WATER_BANK


## The overlay tile for a cell: a crack (running out of the sides in `joins`, 1 left, 2
## right, 4 top, 8 bottom, where its neighbours are cracked or open; alone, one of four by
## its hash), a pit's far wall or floor by how many open cells are above it (OV_WALL_TOP ..
## OV_FLOOR, or the chasm's; an odd column takes the face's other half), -1 for none.
static func overlay_tile(v: int, depth: int, chasm: bool, hash: int = 0, odd := false, joins := 0) -> int:
	if v == TerrainGrid.CRACKED:
		return OV_CRACK_JOIN + joins if joins > 0 else OV_CRACK[posmod(hash, OV_CRACK.size())]
	if TerrainGrid.is_pit(v):
		return (OV_CHASM_TOP if chasm else OV_WALL_TOP) + mini(depth, PIT_DEPTH_CELLS) + (OV_PHASE_B if odd else 0)
	return -1


## Whether overlay id `id` is a crack (alone or joined).
static func is_crack(id: int) -> bool:
	return id in OV_CRACK or (id > OV_CRACK_JOIN and id < OV_CRACK_JOIN + 16)


## The corner tile over a pit cell: a bit of lip at each corner whose diagonal neighbour is
## solid floor while the two cells between are open (the turn of a pit round a floor's
## corner, where the side and rim edges would leave a notch), -1 for none.
static func corner_tile(tl: bool, tr: bool, bl: bool, br: bool) -> int:
	var m := (1 if tl else 0) | (2 if tr else 0) | (4 if bl else 0) | (8 if br else 0)
	return OV_CORNER + m if m > 0 else -1


## The edge tile over a pit cell: the floor's edge down its left or right side and along
## its near rim (floor below it), -1 when every neighbour is open too.
static func edge_tile(left_open: bool, right_open: bool, below_open: bool) -> int:
	var sides := (0 if left_open else 1) | (0 if right_open else 2)
	if below_open:
		return [-1, OV_EDGE_L, OV_EDGE_R, OV_EDGE_LR][sides]
	return OV_RIM + sides


static func _ov_coords(id: int) -> Vector2i:
	return Vector2i(id % OV_COLS, id / OV_COLS)


func _build_tiles() -> void:
	_tiles = _scene.instantiate()
	_tiles.position = Vector2(SimDefs.GRID_X, SimDefs.GRID_Y)
	_tiles.scale = ArtScale.scale_of(ArtScale.PX_PER_UNIT)
	add_child(_tiles)
	move_child(_tiles, 0)
	_piece_cells.clear()
	var pieces := _tiles.get_node_or_null("Pieces") as TileMapLayer
	if pieces != null:
		for c in pieces.get_used_cells():
			_piece_cells[c] = [pieces.get_cell_source_id(c), pieces.get_cell_atlas_coords(c)]
	_raised = _tiles.get_node_or_null("Raised") as TileMapLayer
	_raised_shadow = _tiles.get_node_or_null("RaisedShadow") as TileMapLayer
	_raised_walls.clear()
	if _raised != null and _raised_shadow != null:
		_raised_info = _raised.get_meta("raised", {})
		for i in terrain.map_base.size():
			if terrain.map_base[i] == TerrainGrid.WALL:
				_raised_walls[Vector2i(i % terrain.cols, i / terrain.cols)] = true
	else:
		_raised = null
	_dress_cells()
	_adopt_canopies()
	for which in 3:
		var layer := TileMapLayer.new()
		layer.name = ["Overlay", "Edges", "Corners"][which]
		layer.tile_set = _overlay_set
		layer.position = _tiles.position
		layer.scale = _tiles.scale
		add_child(layer)
		if which == 0:
			_overlay = layer
		elif which == 1:
			_edges = layer
		else:
			_corners = layer


## The map's hand dressing (`tiles.dressing`, instanced by tools/build_tiles.gd as
## "Walls/Dressing"; assets/README.md "Dressing"): every prop under its "Props" whose feet (its
## position) stand on a blocking cell of the map (a wall, a fence) gets meta "cells", that cell
## and the blocking cells beside it its picture spans on that row, so `_sync_sprites` hides it
## while any is smashed, as it hides the wall sprites. Worked out here, not in the scene, so a
## prop nudged in the editor still falls with the wall it stands on. A prop on the floor keeps
## none (only flat ones stand there: tests/test_tiles_dressing.gd).
func _dress_cells() -> void:
	var props := _tiles.get_node_or_null(DRESS_PROPS)
	if props == null:
		return
	var cell_px := float(SimDefs.CELL * ArtScale.PX_PER_UNIT)
	for s in props.get_children():
		var n := s as Node2D
		if n == null:
			continue
		var foot := Vector2i(floori(n.position.x / cell_px), floori((n.position.y - 1.0) / cell_px))
		if not _blocks(foot):
			n.remove_meta("cells")
			continue
		var w := 0.0
		var left := n.position.x
		if n is Sprite2D:
			var sp := n as Sprite2D
			w = sp.region_rect.size.x if sp.region_enabled else float(sp.texture.get_width()) if sp.texture != null else 0.0
			left += sp.offset.x
		elif n is AnimatedSprite2D:
			var an := n as AnimatedSprite2D
			var tex := an.sprite_frames.get_frame_texture(an.animation, 0) if an.sprite_frames != null else null
			w = float(tex.get_width()) if tex != null else 0.0
			left += an.offset.x
		var x0 := foot.x
		var x1 := foot.x
		while x0 - 1 >= floori(left / cell_px) and _blocks(Vector2i(x0 - 1, foot.y)):
			x0 -= 1
		while x1 + 1 <= floori((left + w - 1.0) / cell_px) and _blocks(Vector2i(x1 + 1, foot.y)):
			x1 += 1
		n.set_meta("cells", Rect2i(x0, foot.y, x1 - x0 + 1, 1))


## The dressing's tree crowns (DRESS_CANOPIES): each crown standing on a blocking cell (a
## mid-field tree, its trunk among the props) gets meta "cells" like a prop and hides with
## that wall; one over a brush bed records the bed's cells under its picture, and thins while
## any is flattened. Then they move to `overhead`, above the fighters, keeping their place.
func _adopt_canopies() -> void:
	_canopies.clear()
	if overhead != null:
		for c in overhead.get_children():
			c.queue_free()
		overhead.position = _tiles.position
		overhead.scale = _tiles.scale
	var group := _tiles.get_node_or_null(DRESS_CANOPIES)
	if group == null:
		return
	var cell_px := float(SimDefs.CELL * ArtScale.PX_PER_UNIT)
	for n: Node in group.get_children():
		var a := n as AnimatedSprite2D
		if a == null or a.sprite_frames == null:
			continue
		var size := a.sprite_frames.get_frame_texture(a.animation, 0).get_size()
		var pic := Rect2(a.position + a.offset, size)  # scene px
		var world := Rect2(_tiles.position + pic.position / ArtScale.PX_PER_UNIT, size / ArtScale.PX_PER_UNIT)
		var foot := Vector2i(floori(a.position.x / cell_px), floori((a.position.y - 1.0) / cell_px))
		if _blocks(foot):
			a.set_meta("cells", Rect2i(foot, Vector2i.ONE))
		var under := Rect2i()
		var c0 := Vector2i(floori(pic.position.x / cell_px), floori((pic.position.y + pic.size.y * 0.3) / cell_px))
		var c1 := Vector2i(floori(pic.end.x / cell_px), floori(pic.end.y / cell_px))
		for cy in range(maxi(0, c0.y), mini(terrain.rows, c1.y + 1)):
			for cx in range(maxi(0, c0.x), mini(terrain.cols, c1.x + 1)):
				if terrain.map_base[cy * terrain.cols + cx] == TerrainGrid.BRUSH:
					under = Rect2i(cx, cy, 1, 1) if under.size == Vector2i.ZERO else under.merge(Rect2i(cx, cy, 1, 1))
		_canopies.append([a, world, under])
	if overhead != null:
		for e in _canopies:
			var a: Node2D = e[0]
			a.get_parent().remove_child(a)
			overhead.add_child(a)


## The world points a crown fades over: each fighter the local team sees (`unseen` false:
## its own fighters and teammates always, a foe only while Vision shows it anyway, so a crown
## over open floor never hides a fighter the brush wouldn't), at its feet and its middle. A
## hidden foe gives none, so a crown never gives one away. KO'd fighters neither.
## `viewer_team` is unused but kept so a caller states whose view this is.
static func canopy_watchers(sim: MatchSim, unseen: Array, _viewer_team: int) -> Array:
	var out: Array = []
	for i in sim.creatures.size():
		var c: CreatureSim = sim.creatures[i]
		if c.state == CreatureSim.State.KO or (i < unseen.size() and bool(unseen[i])):
			continue
		out.append(c.pos)
		out.append(c.pos - Vector2(0, float(c.def.get("fx_top", 32)) * 0.5))
	return out


## Eases every crown toward its opacity: CANOPY_SEE over one of ours, CANOPY_THIN over a
## flattened bed, else whole; a crown on a smashed wall is hidden by `_sync_sprites`.
func _fade_canopies(delta: float) -> void:
	for e in _canopies:
		var a: Node2D = e[0]
		if not is_instance_valid(a):
			continue
		var world: Rect2 = e[1]
		var target := 1.0
		var under: Rect2i = e[2]
		if under.size != Vector2i.ZERO and terrain != null:
			for cy in range(under.position.y, under.end.y):
				for cx in range(under.position.x, under.end.x):
					var i := cy * terrain.cols + cx
					if terrain.map_base[i] == TerrainGrid.BRUSH and terrain.cells[i] != terrain.map_base[i]:
						target = CANOPY_THIN
		for p in canopy_points:
			if world.has_point(p):
				target = CANOPY_SEE
				break
		a.modulate.a = move_toward(a.modulate.a, target, CANOPY_FADE * delta)


## How opaque a crown is now (tests, the fade).
func canopy_alpha(i: int) -> float:
	return (_canopies[i][0] as Node2D).modulate.a if i < _canopies.size() else 1.0


func canopy_count() -> int:
	return _canopies.size()


## The crowns' pictures in world px (GladeView lays its leaf shade and sun shafts under them).
func canopy_rects() -> Array:
	return _canopies.map(func(e): return e[1])


## Whether the map's own cell `c` blocks (a wall or a fence): where a dressing prop may stand.
func _blocks(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= terrain.cols or c.y >= terrain.rows:
		return false
	var v := terrain.map_base[c.y * terrain.cols + c.x]
	return v == TerrainGrid.WALL or v == TerrainGrid.FENCE


## Sets the overlay cells of rows row0..row1-1 from the terrain, and the pieces on them.
func _retile(row0: int, row1: int) -> void:
	if _overlay == null:
		return
	var cols := terrain.cols
	var per := ArtScale.TILE_CELLS
	var pieces := _tiles.get_node_or_null("Pieces") as TileMapLayer
	for cy in range(maxi(0, row0), mini(terrain.rows, row1)):
		for cx in cols:
			var i := cy * cols + cx
			var v := terrain.cells[i]
			var at := Vector2i(cx, cy)
			var pit := _pit_at(cx, cy)
			var id := -1
			if pit:
				id = overlay_tile(v, _pit_depth(cx, cy), v == TerrainGrid.CHASM, 0, cx % 2 == 1)
			elif v == TerrainGrid.CRACKED:
				var joins := (1 if _crack_link(cx - 1, cy, cx, cy) else 0) | (2 if _crack_link(cx, cy, cx + 1, cy) else 0) \
					| (4 if _crack_link(cx, cy - 1, cx, cy) else 0) | (8 if _crack_link(cx, cy, cx, cy + 1) else 0)
				id = overlay_tile(v, 0, false, _h(cx, cy, 3), false, joins)
			if id < 0:
				_overlay.erase_cell(at)
			else:
				_overlay.set_cell(at, 0, _ov_coords(id))
			var eid := edge_tile(_pit_at(cx - 1, cy), _pit_at(cx + 1, cy), _pit_at(cx, cy + 1)) if pit else -1
			if eid < 0:
				_edges.erase_cell(at)
			else:
				_edges.set_cell(at, 0, _ov_coords(eid))
			var kid := -1
			if pit:
				var l := _pit_at(cx - 1, cy)
				var r := _pit_at(cx + 1, cy)
				var u := _pit_at(cx, cy - 1)
				var d := _pit_at(cx, cy + 1)
				kid = corner_tile(l and u and not _pit_at(cx - 1, cy - 1), r and u and not _pit_at(cx + 1, cy - 1),
					l and d and not _pit_at(cx - 1, cy + 1), r and d and not _pit_at(cx + 1, cy + 1))
			if kid < 0:
				_corners.erase_cell(at)
			else:
				_corners.set_cell(at, 0, _ov_coords(kid))
		if pieces != null and cy % per == 0:
			_sync_pieces(pieces, cy / per)
	_sync_sprites(row0, row1)
	if _raised != null and not _raised_info.is_empty():
		# a face hangs up to "cells" cells over the wall's end, so a change reaches that far up
		var reach := int(_raised_info["cells"]) + 1
		RaisedTiles.paint(_raised, _raised_shadow, _raised_info, _raised_walls, _raised_up, row0 - reach, row1 + reach)


## Whether a map wall cell stands whole (drawn raised): not smashed, or rebuilt.
func _raised_up(c: Vector2i) -> bool:
	if not _raised_walls.has(c):
		return false
	var i := c.y * terrain.cols + c.x
	return terrain.cells[i] == terrain.map_base[i]


## The scene's sprite pieces, each with the cells it covers in its meta "cells": bush clumps
## ("Brush") and wall sprites ("Walls") show while every cell under them is still the map's
## own (brush standing, wall whole) and hide while any has changed (flattened by a dash,
## smashed), until the floor heals; a wall tile's rubble ("Rubble", meta "broken") shows
## exactly then.
func _sync_sprites(row0: int, row1: int) -> void:
	var groups: Array = []
	for node_name in ["Brush", "Walls", "Rubble", DRESS_PROPS]:
		var group := _tiles.get_node_or_null(node_name)
		if group != null:
			groups.append(group.get_children())
	groups.append(_canopies.map(func(e): return e[0]))  # the crowns, wherever they now hang
	for list: Array in groups:
		for s in list:
			if not is_instance_valid(s):
				continue
			if not s.has_meta("cells"):
				continue
			var cells: Rect2i = s.get_meta("cells")
			if cells.end.y <= row0 or cells.position.y >= row1:
				continue
			var whole := true
			for cy in range(cells.position.y, cells.end.y):
				for cx in range(cells.position.x, cells.end.x):
					if cx < 0 or cy < 0 or cx >= terrain.cols or cy >= terrain.rows:
						continue
					var i := cy * terrain.cols + cx
					if terrain.cells[i] != terrain.map_base[i]:
						whole = false
			s.visible = whole != bool(s.get_meta("broken", false))


## The scene's pieces on tile row `ty`: a boulder stays while every cell under it is still
## the map's wall, a tuft while its brush stands; otherwise the tile is cleared.
func _sync_pieces(pieces: TileMapLayer, ty: int) -> void:
	var per := ArtScale.TILE_CELLS
	for c: Vector2i in _piece_cells:
		if c.y != ty:
			continue
		var whole := true
		for dy in per:
			for dx in per:
				var cx := c.x * per + dx
				var cy := c.y * per + dy
				if cx < 0 or cy < 0 or cx >= terrain.cols or cy >= terrain.rows:
					continue
				var i := cy * terrain.cols + cx
				if terrain.cells[i] != terrain.map_base[i]:
					whole = false
		if whole:
			var was: Array = _piece_cells[c]
			pieces.set_cell(c, int(was[0]), was[1])
		else:
			pieces.erase_cell(c)
var _art_cracked: Texture2D = null
## The floor with its pieces changed (a smashed wall's rubble, flattened brush), if any.
var _art_alt: Texture2D = null
## The cracks of the _cracked picture alone, white on clear (lit as they spread and knit).
var _mask: Texture2D = null


## A picture's density (ArtScale.picture_ppu): 1 for the baked pictures as they are, 2 for
## one twice the size of the world it covers. The main picture covers the stadium and its
## margins; the cracked, alt and mask pictures cover the floor.
func _ppu(tex: Texture2D) -> int:
	if tex == null or terrain == null:
		return 1
	var units := terrain.arena_size() + MARGIN * 2.0 if tex == _art else terrain.floor_rect().size
	return ArtScale.picture_ppu(tex.get_size(), units)


## The source rect in `tex` for the world rect `at` whose picture starts at world `origin`.
func _src(tex: Texture2D, at: Rect2, origin: Vector2) -> Rect2:
	var k := float(_ppu(tex))
	return Rect2((at.position - origin) * k, at.size * k)


## The source rect for a floor cell in a floor-sized picture (cracked, alt, mask).
func _src_cell(tex: Texture2D, cx: int, cy: int) -> Rect2:
	var k := float(_ppu(tex)) * SimDefs.CELL
	return Rect2(cx * k, cy * k, k, k)


## The cells a floor picture's origin starts at (the floor's corner), as world units.
const FLOOR_ORIGIN := Vector2(SimDefs.GRID_X, SimDefs.GRID_Y)
## The map's bridges (cells), whose holes show the water in the _alt picture.
var _bridges: Array[Rect2i] = []
## How tall (px) the pieces that change are, as tools/gen_arenas.py casts their shadows
## (keep in step with CAST_HEIGHT there; taller only widens `_shade`, never wrong).
const CAST_HEIGHT := {TerrainGrid.WALL: 12.0, TerrainGrid.BRUSH: 6.0}
const BRIDGE_HEIGHT := 3.0
## Floor cell -> the cells of changing pieces whose shadow (in the art) falls on it.
var _shade := {}
## Row -> its cells in `_shade`.
var _shade_rows := {}
## How many rows a piece's shadow reaches above (x) and below (y) it.
var _shade_reach := Vector2i.ZERO


## A hole in a bridge or a fallen bridge, on a map whose _alt picture shows the water under it.
func _bridge_gone(cx: int, cy: int) -> bool:
	if _bridge_cells.is_empty():
		return false
	var i := cy * terrain.cols + cx
	if _bridge_cells[i] == 0:
		return false
	var v := terrain.cells[i]
	return v == TerrainGrid.HOLE or v == TerrainGrid.SHALLOWS


## 1 for each cell of a bridge (on a map with an _alt picture to show the water under it),
## so `_bridge_gone` is one lookup: the pits ask it of every neighbour.
var _bridge_cells := PackedByteArray()


func _build_bridge_cells() -> void:
	_bridge_cells = PackedByteArray()
	if _art_alt == null or _bridges.is_empty():
		return
	_bridge_cells.resize(terrain.cells.size())
	for r in _bridges:
		for cy in range(maxi(0, r.position.y), mini(terrain.rows, r.end.y)):
			for cx in range(maxi(0, r.position.x), mini(terrain.cols, r.end.x)):
				_bridge_cells[cy * terrain.cols + cx] = 1


func set_terrain(t: TerrainGrid) -> void:
	terrain = t
	_rebuild()


## The floor and the pits are drawn in bands of BAND_ROWS rows, each its own canvas item,
## so a cell that cracks, heals or breaks redraws only its band (and its neighbours',
## since a wall's face and a pit's rim look at the cells round them), not the whole map:
## a big map's full redraw costs a few milliseconds, a band's a fraction of one. Bands are
## full rows, drawn top to bottom, so everything overlaps exactly as one big drawing would.
const BAND_ROWS := 4


## One band of rows: `paint` draws rows row0..row1-1 onto it.
class Band extends Node2D:
	var paint: Callable
	var row0 := 0
	var row1 := 0
	var label := "arena draw"

	func _draw() -> void:
		var t0 := PerfLog.now()
		paint.call(self, row0, row1)
		PerfLog.since(label, t0)


var _floor_bands: Array[Band] = []
var _pit_bands: Array[Band] = []
var _marks: Band = null
## The moving floor (`_step_fx`): cracks running, over the floor bands and under the pits;
## pits closing, glowing cracks and dust, over the pits. They redraw only while busy.
var _under: Band = null
var _over: Band = null
## The dust over all of it: it moves every tick, so it is a layer of its own.
var _dust: Band = null
## The cells as the bands last drew them, to find the rows that changed.
var _seen := PackedByteArray()
## Bands waiting to be repainted. A change to the floor can dirty many at once (a slam's
## ring, a Sinkhole collapse) and each costs a fraction of a millisecond, so they're
## repainted a few per frame (`_process`) over at most SPREAD_FRAMES frames instead of
## all in the tick that changed them, which read as a hitch at high frame rates.
var _pending: Array[int] = []
const SPREAD_FRAMES := 4


## Starts the drawing over: a new terrain, map art or ground.
func _rebuild() -> void:
	queue_redraw()
	var old: Array = [_marks, _under, _over, _dust, _tiles, _overlay, _edges, _corners]
	old.append_array(_floor_bands)
	old.append_array(_pit_bands)
	for b in old:
		if b != null:
			# Out of the tree now: a freed band lingers to the end of the frame and would
			# still draw its old rows over the new terrain (a big map, then a smaller one).
			remove_child(b)
			b.queue_free()
	_floor_bands.clear()
	_pit_bands.clear()
	_pending.clear()
	_marks = null
	_under = null
	_over = null
	_dust = null
	_tiles = null
	_raised = null
	_raised_shadow = null
	_overlay = null
	_edges = null
	_corners = null
	_grow.clear()
	_settle.clear()
	_motes.clear()
	_knit.clear()
	_glowing.clear()
	_heal_cells.clear()
	_due.clear()
	_watch.clear()
	if terrain == null:
		return
	_build_bridge_cells()
	_build_pit_tex()
	if _scene != null and _overlay_set != null:
		_build_tiles()
	var bands := ceili(terrain.rows / float(BAND_ROWS))
	for k in bands:
		_floor_bands.append(_band(_paint_floor, k))
	_marks = _band(_paint_marks, 0)
	_under = _band(_paint_under, 0)
	_under.label = "pit fx under"
	if _overlay != null:
		# the breaking ground as tiles, where the pit bands would be
		move_child(_overlay, get_child_count() - 1)
		move_child(_edges, get_child_count() - 1)
		move_child(_corners, get_child_count() - 1)
	for k in bands:
		_pit_bands.append(_band(_paint_pit_band, k))
	_over = _band(_paint_over, 0)
	_over.label = "pit fx over"
	_dust = _band(_paint_dust, 0)
	_dust.label = "pit fx dust"
	_seen = terrain.cells.duplicate()
	_drawn_version = terrain.version
	for i in terrain.cells.size():
		if terrain.cells[i] != terrain.base[i]:
			_schedule(i)
	_build_shade()
	if _overlay != null:
		_retile(0, terrain.rows)


## Which floor cells lie in the shadow of pieces that can change (`_shade`): each such
## piece cell's shadow swept along the light, as the art casts it, with a pixel or two spare.
func _build_shade() -> void:
	_shade.clear()
	_shade_rows.clear()
	_shade_reach = Vector2i.ZERO
	if _art_alt == null or terrain == null:
		return
	var cast: Vector2 = ShadowLayer.light_of(ArenaMap.get_map(arena_id))["cast"]
	var cols := terrain.cols
	var casters := {}
	for i in terrain.map_base.size():
		var b := terrain.map_base[i]
		if CAST_HEIGHT.has(b):
			casters[i] = CAST_HEIGHT[b]
	for r in _bridges:
		for cy in range(r.position.y, r.end.y):
			for cx in range(r.position.x, r.end.x):
				if not casters.has(cy * cols + cx):
					casters[cy * cols + cx] = BRIDGE_HEIGHT
	var cell := float(SimDefs.CELL)
	for i: int in casters:
		var cx := i % cols
		var cy := i / cols
		var px := Rect2(cx * cell, cy * cell, cell, cell)
		var box := px.merge(Rect2(px.position + cast * float(casters[i]), px.size)).grow(2.0)
		var y0 := maxi(0, floori(box.position.y / cell))
		var y1 := mini(terrain.rows - 1, ceili(box.end.y / cell) - 1)
		var x0 := maxi(0, floori(box.position.x / cell))
		var x1 := mini(cols - 1, ceili(box.end.x / cell) - 1)
		_shade_reach = Vector2i(maxi(_shade_reach.x, cy - y0), maxi(_shade_reach.y, y1 - cy))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var p := y * cols + x
				if casters.has(p):
					continue
				if not _shade.has(p):
					_shade[p] = []
					if not _shade_rows.has(y):
						_shade_rows[y] = []
					_shade_rows[y].append(p)
				_shade[p].append(i)


## Whether a changing piece's cell has changed (its shadow gone with it).
func _piece_gone(i: int) -> bool:
	var b := terrain.map_base[i]
	if CAST_HEIGHT.has(b):
		return terrain.cells[i] != b
	return _bridge_gone(i % terrain.cols, i / terrain.cols)


## Floor cell `p` (in `_shade`) as the map made it, with every piece shading it changed: its
## piece of the _alt picture, which has the floor without their shadows.
func _unshaded(p: int) -> bool:
	if terrain.cells[p] != terrain.map_base[p]:
		return false
	for i: int in _shade[p]:
		if not _piece_gone(i):
			return false
	return true


func _band(paint: Callable, k: int) -> Band:
	var b := Band.new()
	b.paint = paint
	b.row0 = k * BAND_ROWS
	b.row1 = mini(terrain.rows, b.row0 + BAND_ROWS)
	add_child(b)
	return b


## Once a tick (main's _physics_process): repaint what changed, and step the moving floor.
func refresh() -> void:
	if terrain == null:
		return
	var t0 := PerfLog.now()
	_tick += 1
	if terrain.version != _drawn_version:
		_drawn_version = terrain.version
		if _seen.size() != terrain.cells.size():
			_rebuild()
			return
		_find_changes()
	_step_fx()
	PerfLog.since("floor refresh", t0)


## The rows whose cells changed since the bands last looked: their bands (and the ones
## round them: a wall's face, a pit's rim and depth, a piece's shadow look at the cells
## round them) go on `_pending`, and each changed cell may start something moving.
func _find_changes() -> void:
	var cols := terrain.cols
	var cells := terrain.cells
	var base := terrain.base
	var dirty := {}
	var fresh := {}  # cell -> 0 just cracked, 1 just opened
	for cy in terrain.rows:
		var a := cy * cols
		if cells.slice(a, a + cols) == _seen.slice(a, a + cols):
			continue
		for r in range(maxi(0, cy - 1 - _shade_reach.x), mini(terrain.rows, cy + 2 + PIT_DEPTH_CELLS + _shade_reach.y)):
			dirty[r / BAND_ROWS] = true
		for c0 in range(a, a + cols, SCAN_CHUNK):
			var c1 := mini(c0 + SCAN_CHUNK, a + cols)
			if cells.slice(c0, c1) == _seen.slice(c0, c1):
				continue
			for i in range(c0, c1):
				var v := cells[i]
				if v != _seen[i]:
					_cell_changed(i, _seen[i], v, fresh)
					if v != base[i]:
						_schedule(i)
	_seen = cells.duplicate()
	if not fresh.is_empty():
		_spread(fresh)
	for k in dirty:
		if not (k in _pending):
			_pending.append(k)
		if _overlay != null:
			_retile(k * BAND_ROWS, (k + 1) * BAND_ROWS)


## A few of the pending bands each frame (every band paints the floor as it is now, so a
## band that changed again meanwhile is still right).
func _process(_delta: float) -> void:
	if not _canopies.is_empty():
		_fade_canopies(_delta)
	if _pending.is_empty() and _settle.is_empty():
		return
	var n := maxi(1, ceili(_pending.size() / float(SPREAD_FRAMES))) if not _pending.is_empty() else 0
	for i in mini(n, _pending.size()):
		var k: int = _pending.pop_front()
		if k < _floor_bands.size():
			_floor_bands[k].queue_redraw()
			_pit_bands[k].queue_redraw()
	# A crack that finished running is drawn whole by the under layer until its band has
	# repainted with it (this frame, if its band just came off the list).
	if not _settle.is_empty():
		var gone: Array[int] = []
		for i: int in _settle:
			if not ((i / terrain.cols) / BAND_ROWS in _pending):
				gone.append(i)
		for i in gone:
			_settle.erase(i)
		if not gone.is_empty() and _under != null:
			_under.queue_redraw()


## The map's picture (null on a tiled map, whose brush is tiles): AmbientView sways pieces
## of it. A tiled map may still have the picture: it draws the stands round the floor.
func art() -> Texture2D:
	return null if _tiles != null else _art


## Under the bands: the map's art, or the stands and walls round a tiled floor.
func _draw() -> void:
	if terrain == null:
		return
	if _art != null:
		# at its own density: a 2x picture covers the same world at half scale
		draw_texture_rect(_art, Rect2(-MARGIN, _art.get_size() / float(_ppu(_art))), false)
		return
	var fr := terrain.floor_rect()
	var size := terrain.arena_size()
	var x0 := -MARGIN.x
	var w := size.x + MARGIN.x * 2.0
	var y0 := -MARGIN.y
	var h := size.y + MARGIN.y * 2.0

	# Stands behind the crowd (rising out of sight above), then the back wall.
	draw_rect(Rect2(x0, y0, w, h), C_BG)
	for i in range(-6, 4):
		draw_rect(Rect2(x0, i * 14, w, 14), C_STAND_A if posmod(i, 2) == 0 else C_STAND_B)
	draw_rect(Rect2(x0, 47, w, 2), C_RAIL)
	draw_rect(Rect2(x0, fr.position.y - 8, w, 8), C_WALL)
	draw_rect(Rect2(x0, fr.position.y - 8, w, 1), C_WALL_TOP)
	draw_rect(Rect2(x0, fr.position.y - 1, w, 1), C_WALL_DARK)

	# Side and front walls.
	draw_rect(Rect2(x0, fr.position.y, fr.position.x - x0, fr.size.y), C_WALL_DARK)
	draw_rect(Rect2(fr.end.x, fr.position.y, x0 + w - fr.end.x, fr.size.y), C_WALL_DARK)
	draw_rect(Rect2(fr.position.x - 1, fr.position.y, 1, fr.size.y), C_WALL)
	draw_rect(Rect2(fr.end.x, fr.position.y, 1, fr.size.y), C_WALL)
	draw_rect(Rect2(x0, fr.end.y, w, y0 + h - fr.end.y), C_WALL)
	draw_rect(Rect2(x0, fr.end.y, w, 1), C_WALL_TOP)


## A floor band: on a map with art, the cells that differ from it; else the floor tiles
## (intact and cracked cells, then the map's pieces that sit on them).
func _paint_floor(ci: CanvasItem, row0: int, row1: int) -> void:
	if _tiles != null:
		# The ground scene and the overlay tiles draw it all, except rubble the sim adds
		# where the map laid none (a Caravan rockslide): its heap is drawn here as on a map
		# with art, since the scene's pieces are only the map's own.
		for cy in range(row0, row1):
			for cx in terrain.cols:
				var i := cy * terrain.cols + cx
				if terrain.cells[i] == TerrainGrid.WALL and terrain.map_base[i] != TerrainGrid.WALL:
					_draw_rubble(ci, cx, cy)
		return
	if _art != null:
		_paint_changed(ci, row0, row1)
		return
	for cy in range(row0, row1):
		for cx in terrain.cols:
			var v := terrain.cells[cy * terrain.cols + cx]
			if TerrainGrid.is_pit(v):
				continue
			var idx := (cx * 7 + cy * 13 + (cx * cy) % 5) % 4
			var b := terrain.base[cy * terrain.cols + cx]
			match v:
				TerrainGrid.CRACKED:
					idx = TILE_RUBBLE_FLOOR if b == TerrainGrid.WALL else 4 + (cx * 13 + cy * 7 + cx * cy) % 4
				TerrainGrid.WALL:
					# The bottom row of a wall shows its face; the rest its rubble top.
					var below := terrain.cells[(cy + 1) * terrain.cols + cx] if cy + 1 < terrain.rows else TerrainGrid.INTACT
					idx = TILE_WALL_FACE if below != TerrainGrid.WALL else TILE_WALL_TOP + (cx + cy) % 2
				TerrainGrid.SHALLOWS:
					idx = TILE_SHALLOWS + (cx * 3 + cy * 5) % 2
			var plain := v == TerrainGrid.INTACT or v == TerrainGrid.CRACKED or v == TerrainGrid.BRUSH \
				or v == TerrainGrid.BRUSH_FLAT or v == TerrainGrid.FENCE
			ci.draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(idx * 8, 0, 8, 8),
				GROUND_TINT.get(ground, Color.WHITE) if plain else Color.WHITE)
			var over := -1
			match v:
				TerrainGrid.FENCE: over = TILE_FENCE
				TerrainGrid.BRUSH: over = TILE_BRUSH + (cx * 5 + cy * 3) % 2
				TerrainGrid.BRUSH_FLAT: over = TILE_BRUSH_FLAT
			if over >= 0:
				ci.draw_texture_rect_region(TILES, _cell_rect(cx, cy), Rect2(over * 8, 0, 8, 8))


## Court markings over a tiled floor (the art has its own), under the pits.
func _paint_marks(ci: CanvasItem, _row0: int, _row1: int) -> void:
	if (_tiles == null and _art != null) or (_tiles != null and not _markings):
		return
	var fr := terrain.floor_rect()
	var c := fr.get_center()
	if _tiles == null:
		ci.draw_rect(fr.grow(-4), C_LINE, false, 1.0)
		ci.draw_line(Vector2(c.x, fr.position.y + 4), Vector2(c.x, fr.end.y - 4), C_LINE, 1.0)
		ci.draw_arc(c, 34.0, 0.0, TAU, 48, C_LINE, 1.0)
		return
	# Chalk on the tiles, the baked Stadium's layout (tools/gen_arenas.py:_markings): the
	# boundary, a centre line broken at a double centre circle, corner arcs, the two sides'
	# starting brackets in their colours, and the eight-point emblem in faded gold.
	var box := fr.grow(-6)
	var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for k in 4:
		_chalk(ci, corners[k], corners[(k + 1) % 4])
	_chalk(ci, Vector2(c.x, box.position.y), Vector2(c.x, c.y - 34))
	_chalk(ci, Vector2(c.x, c.y + 34), Vector2(c.x, box.end.y))
	ci.draw_arc(c, 34.0, 0.0, TAU, 64, C_CHALK, 1.0)
	ci.draw_arc(c, 31.0, 0.0, TAU, 64, C_CHALK, 1.0)
	for k in 4:
		var corner := Vector2(box.position.x if k % 3 == 0 else box.end.x, box.position.y if k < 2 else box.end.y)
		ci.draw_arc(corner, 10.0, PI * 0.5 * k, PI * 0.5 * (k + 1), 10, C_CHALK, 1.0)
	for side in 2:
		var s := Vector2(c.x + (100.0 if side == 1 else -100.0), c.y + 4.0)
		var col: Color = C_START[side]
		for dx in [-1.0, 1.0]:
			for dy in [-1.0, 1.0]:
				var b := s + Vector2(dx * 9.0, dy * 7.0)
				ci.draw_line(b, b - Vector2(dx * 4.0, 0.0), col, 1.0)
				ci.draw_line(b, b - Vector2(0.0, dy * 3.0), col, 1.0)
	ci.draw_arc(c, 12.0, 0.0, TAU, 32, Color(C_CHALK, 0.5), 1.0)
	for k in 8:
		var ang := k * PI / 4.0
		var ln := 9.0 if k % 2 == 0 else 5.0
		ci.draw_line(c, c + Vector2(cos(ang), sin(ang)) * ln, C_EMBLEM, 1.0)


## A straight chalk line worn by play and re-chalked: short dashes whose strength varies by a
## fixed hash (a scuffed gap now and then), some with a faint older line a hair beside them.
func _chalk(ci: CanvasItem, a: Vector2, b: Vector2) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / CHALK_DASH))
	var side := (b - a).normalized().orthogonal() * 1.5
	for i in n:
		var k := posmod((i * 73856093) ^ (int(a.x) * 19349663) ^ (int(a.y + b.x) * 83492791), 97)
		var p0 := a.lerp(b, float(i) / n)
		var p1 := a.lerp(b, float(i + 1) / n)
		var s := 0.25 if k < 7 else 0.6 + 0.4 * float(k) / 96.0
		ci.draw_line(p0, p1, Color(C_CHALK, C_CHALK.a * s), 1.0)
		if k % 6 == 0:
			ci.draw_line(p0 + side, p1 + side, Color(C_CHALK, C_CHALK.a * 0.22), 1.0)


## Chalk and paint on a tiled floor's markings.
const CHALK_DASH := 6.0  ## units: a worn chalk line's dashes (`_chalk`)
const C_CHALK := Color(1.0, 0.98, 0.94, 0.62)
const C_START: Array[Color] = [Color8(236, 104, 92, 200), Color8(104, 150, 240, 200)]
const C_EMBLEM := Color8(226, 178, 70, 150)


## Whether the art already shows cell `i` as a chasm: only the map's own chasms are in the
## picture. A cell sunk during the match (Sinkhole's rings, the Floor of pits mutator) has
## `base` CHASM too, so it never heals, but it has to be drawn.
func _in_art(i: int) -> bool:
	return _tiles == null and _art != null and terrain.map_base[i] == TerrainGrid.CHASM


## A map with art: a crack mark on each cracked cell, the map's changed pieces (rubble,
## flattened brush), the river under a broken bridge. Pits come in the pit bands.
func _paint_changed(ci: CanvasItem, row0: int, row1: int) -> void:
	for cy in range(row0, row1):
		var a := cy * terrain.cols
		for p: int in _shade_rows.get(cy, []):  # floor out of the shadow of pieces that changed
			if _unshaded(p):
				ci.draw_texture_rect_region(_art_alt, _cell_rect(p - a, cy), _src_cell(_art_alt, p - a, cy))
		# The art already shows the floor and every piece as the map made it.
		if terrain.cells.slice(a, a + terrain.cols) == terrain.map_base.slice(a, a + terrain.cols):
			continue
		for cx in terrain.cols:
			var v := terrain.cells[a + cx]
			var b := terrain.map_base[a + cx]
			if v == b:
				continue
			var cell := _cell_rect(cx, cy)
			if (v == TerrainGrid.HOLE or v == TerrainGrid.SHALLOWS) and _bridge_gone(cx, cy):
				ci.draw_texture_rect_region(_art_alt, cell, _src_cell(_art_alt, cx, cy))  # the river under the broken bridge
				continue
			if TerrainGrid.is_pit(v):
				continue
			if v == TerrainGrid.WALL:  # rubble the map didn't put there: a Caravan rockslide
				_draw_rubble(ci, cx, cy)
				continue
			if (v == TerrainGrid.CRACKED and b == TerrainGrid.WALL) or v == TerrainGrid.BRUSH_FLAT:
				# a smashed wall's rubble, flattened brush: the map's changed-piece picture
				if _art_alt != null:
					ci.draw_texture_rect_region(_art_alt, cell, _src_cell(_art_alt, cx, cy))
				else:
					var t := TILE_RUBBLE_FLOOR if v == TerrainGrid.CRACKED else TILE_BRUSH_FLAT
					ci.draw_texture_rect_region(TILES, cell, Rect2(t * 8, 0, 8, 8))
			elif v == TerrainGrid.CRACKED:
				if _grow.has(a + cx):
					continue  # its crack is still running: the under layer draws it
				if _art_cracked != null:
					ci.draw_texture_rect_region(_art_cracked, cell, _src_cell(_art_cracked, cx, cy))
					if _glowing.has(a + cx):
						_glow(ci, cell, Color(C_GLOW, GLOW_BAND))
				else:
					ci.draw_rect(cell, C_CRACKED_SHADE)


## Rockslide rubble on a map with art: a heap of boulders, the same heap for the same
## cell (no randomness, so a redraw doesn't shuffle it), lit from the top left.
const C_RUBBLE: Array[Color] = [Color("3e3026"), Color("6a5442"), Color("846a52"), Color("a88e70")]


func _draw_rubble(ci: CanvasItem, cx: int, cy: int) -> void:
	var r := _cell_rect(cx, cy)
	ci.draw_rect(Rect2(r.position + Vector2(-1, 1), r.size + Vector2(2, 1)), Color(C_RUBBLE[0], 0.55))
	for k in 3:
		var off := Vector2(posmod(cx * 5 + cy * 3 + k * 7, 6) - 2.5, posmod(cx * 3 + cy * 11 + k * 5, 5) - 2.5)
		var rad := 3.2 + 0.8 * posmod(cx + cy * 2 + k, 3)
		var p := r.get_center() + off
		ci.draw_circle(p + Vector2(0.5, 1.0), rad, C_RUBBLE[0])
		ci.draw_circle(p, rad, C_RUBBLE[1 + posmod(cx + cy + k, 2)])
		ci.draw_circle(p - Vector2(rad, rad) * 0.35, rad * 0.45, C_RUBBLE[3])


func _cell_rect(cx: int, cy: int) -> Rect2:
	return Rect2(SimDefs.GRID_X + cx * SimDefs.CELL, SimDefs.GRID_Y + cy * SimDefs.CELL, SimDefs.CELL, SimDefs.CELL)


# ---------------------------------------------------------------- pits with depth

## The pit tones, by the map's ground (a chasm has its own): the floor's edge (`top`, two
## rows: turf on grass, the slab on concrete), the far wall (`hi`/`mid`/`lo`), then the dark
## going down (`g`, four steps to near-black) and the undercut under the lip.
const PIT_SOIL := {
	"top": [Color8(150, 108, 72), Color8(130, 93, 62)],
	"hi": Color8(140, 100, 66), "mid": Color8(116, 82, 55), "lo": Color8(94, 66, 44),
	"g": [Color8(58, 41, 29), Color8(40, 29, 21), Color8(26, 19, 15), Color8(14, 11, 9)],
	"under": Color8(24, 16, 12),
}
const PIT_STONE := {
	"top": [Color8(150, 144, 134), Color8(126, 120, 112)],
	"hi": Color8(132, 124, 114), "mid": Color8(108, 101, 93), "lo": Color8(88, 82, 76),
	"g": [Color8(54, 50, 47), Color8(37, 34, 32), Color8(24, 22, 21), Color8(13, 12, 12)],
	"under": Color8(20, 18, 17),
}
const PIT_CHASM := {
	"top": [Color8(104, 102, 124), Color8(84, 82, 104)],
	"hi": Color8(88, 86, 108), "mid": Color8(68, 66, 88), "lo": Color8(52, 51, 70),
	"g": [Color8(32, 32, 50), Color8(20, 20, 34), Color8(11, 11, 21), Color8(5, 5, 11)],
	"under": Color8(10, 9, 17), "mist": Color8(86, 92, 120),
}
## The top rows of a pit's far wall by ground: turf over the soil, a concrete slab.
const PIT_TOP := {
	"grass": [Color8(70, 104, 48), Color8(54, 80, 40)],
	"concrete": [Color8(156, 158, 162), Color8(120, 122, 128)],
}
## Rows of the far wall under the lip (the corner of a side wall runs this far down too).
const WALL_H := 6
## A pit's depth tones run over this many cells down from its far wall (then stay black).
const PIT_DEPTH_CELLS := 3
## The atlas (`_pit_tex`, 28 x 32): hole and chasm insides 8 px wide, one 8 px slice per
## cell down from the far wall; then 3 px side walls: hole left, hole right, chasm left,
## chasm right. A side wall's outer column is the edge against the floor.
const AX_CHASM := 8.0
const AX_SIDE_HOLE := 16.0
const AX_SIDE_CHASM := 22.0
const C_FLOOR_BIT := Color8(150, 110, 76)  ## a lip's floor on a map without art
const C_NEAR_LIT := Color(1.0, 0.93, 0.78)
const C_PEBBLE := Color8(122, 106, 88)
const C_PEBBLE_LIT := Color8(178, 160, 136)
const C_PEBBLE_SHADOW := Color(0.0, 0.0, 0.0, 0.42)

var _pit_tex: ImageTexture = null
## The way the map's light travels (unit), and how strong its shadows are.
var _light := Vector2(0.25, 0.97)
var _light_alpha := 0.32
## How lit the near edge of a pit is (the floor's broken edge, facing into the light).
var _near_lit := 0.5
## The undercut tones and a hole's first dark, cached from the palettes.
var _hole_under := PIT_SOIL["under"] as Color
var _chasm_under := PIT_CHASM["under"] as Color
var _hole_dark := PIT_SOIL["g"][0] as Color


func _pit_pal(chasm: bool) -> Dictionary:
	if chasm:
		return PIT_CHASM
	var pal: Dictionary = (PIT_STONE if ground == "stone" else PIT_SOIL).duplicate()
	if PIT_TOP.has(ground):
		pal["top"] = PIT_TOP[ground]
	return pal


static func _dim(c: Color, f: float) -> Color:
	return Color(minf(c.r * f, 1.0), minf(c.g * f, 1.0), minf(c.b * f, 1.0), c.a)


## Whether a whole-pixel checker picks the first of two tones (the dither between steps).
static func _chk(x: int, y: int) -> bool:
	return (x + y) % 2 == 0


## The inside of a pit at `y` px down from its far lip: the undercut, the far wall (the
## floor's edge, then strata), then the dark in dithered steps; a chasm's mist hangs part way.
func _pit_px(x: int, y: int, pal: Dictionary, f: float, chasm: bool) -> Color:
	var g: Array = pal["g"]
	var c: Color
	match y:
		0: return pal["under"]
		1: return _dim(pal["top"][0], f)
		2: return _dim(pal["top"][1], f)
		3: return _dim(pal["hi"] if x % 4 == 1 else pal["mid"], f)
		4: return _dim(pal["mid"] if _chk(x, y) else pal["lo"], f)
		5: return _dim(pal["lo"], f)
		6: return _dim(pal["lo"], f) if _chk(x, y) else g[0]
	if y <= 8:
		c = g[0]
	elif y == 9:
		c = g[0] if _chk(x, y) else g[1]
	elif y <= 11:
		c = g[1]
	elif y == 12:
		c = g[1] if _chk(x, y) else g[2]
	elif y <= 15:
		c = g[2]
	elif y == 16:
		c = g[2] if _chk(x, y) else g[3]
	else:
		c = g[3]
	if chasm and y >= 11 and y <= 14 and (x * 5 + y * 3) % 9 == 0:
		c = pal["mist"]
	return c


## A side wall `k` px in from the floor's edge, `y` px down: the same rock fading to dark
## more slowly than the floor of the pit; its inner column is ragged into the inside.
func _side_px(k: int, y: int, pal: Dictionary, f: float) -> Color:
	if y == 0:
		return pal["under"]
	if k == 2 and (y * 5) % 7 >= 3:
		return Color(0, 0, 0, 0)
	var g: Array = pal["g"]
	var tones: Array = [pal["mid"], pal["lo"], g[0], g[1], g[2]]
	var step := mini((y - 3) / 6, 4) if y >= 3 else 0
	var c: Color = tones[step]
	if y >= 9 and (y - 3) % 6 == 0 and step > 0 and not _chk(k, y):
		c = tones[step - 1]  # the dither row between steps
	return _dim(c, f)


## The pit tones for this map: its ground, shaded by its light. The far wall faces the
## camera, so it is in shade when the light comes from the top (every map so far); a side
## wall facing the light is lit, the other shaded.
func _build_pit_tex() -> void:
	var l: Dictionary = ShadowLayer.light_of(ArenaMap.get_map(arena_id) if arena_id != "" else {})
	var cast: Vector2 = l["cast"]
	_light = cast.normalized() if cast.length() > 0.001 else Vector2.DOWN
	_light_alpha = float(l["alpha"])
	var a := _light_alpha
	var d := _light
	_near_lit = 0.12 + 0.3 * maxf(0.0, d.y)
	var f_far := 1.0 - 0.9 * a * maxf(0.0, d.y) + 0.3 * maxf(0.0, -d.y)
	# the wall on a pit's left faces right (+x): lit by a light travelling left
	var f_left := clampf(1.0 + 0.45 * maxf(0.0, -d.x) - 0.9 * a * maxf(0.0, d.x), 0.6, 1.3)
	var f_right := clampf(1.0 + 0.45 * maxf(0.0, d.x) - 0.9 * a * maxf(0.0, -d.x), 0.6, 1.3)
	var img := Image.create(28, PIT_DEPTH_CELLS * SimDefs.CELL + SimDefs.CELL, false, Image.FORMAT_RGBA8)
	for chasm: bool in [false, true]:
		var pal := _pit_pal(chasm)
		var bx := int(AX_CHASM) if chasm else 0
		var sx := int(AX_SIDE_CHASM if chasm else AX_SIDE_HOLE)
		for y in img.get_height():
			for x in 8:
				img.set_pixel(bx + x, y, _pit_px(x, y, pal, f_far, chasm))
			for k in 3:
				img.set_pixel(sx + k, y, _side_px(k, y, pal, f_left))
				img.set_pixel(sx + 5 - k, y, _side_px(k, y, pal, f_right))
	_pit_tex = ImageTexture.create_from_image(img)
	_hole_under = _pit_pal(false)["under"]
	_hole_dark = _pit_pal(false)["g"][0]


## A pit band: holes and chasms over everything else, so they cut through the markings,
## each with its lip and the pebbles round it.
func _paint_pit_band(ci: CanvasItem, row0: int, row1: int) -> void:
	if _tiles != null:
		return  # the overlay tiles are the pits
	var cols := terrain.cols
	for cy in range(row0, row1):
		for cx in cols:
			var i := cy * cols + cx
			var v := terrain.cells[i]
			if not TerrainGrid.is_pit(v) or (v == TerrainGrid.CHASM and _in_art(i)) or _bridge_gone(cx, cy):
				continue
			_paint_pit_cell(ci, cx, cy, v == TerrainGrid.CHASM)


## Whether cell (cx, cy) is open (a pit, not the river under a broken bridge). Off the
## grid counts as floor, so a pit at the edge gets its walls.
func _pit_at(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= terrain.cols or cy >= terrain.rows:
		return false
	return TerrainGrid.is_pit(terrain.cells[cy * terrain.cols + cx]) and not _bridge_gone(cx, cy)


## Whether cell (cx, cy) is cracked or open: a crack can run on into it.
func _broken_at(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= terrain.cols or cy >= terrain.rows:
		return false
	return terrain.cells[cy * terrain.cols + cx] == TerrainGrid.CRACKED or _pit_at(cx, cy)


## Whether a crack runs across the side between cells a and b (b right of or below a): both
## broken, and the side's own hash says so (CRACK_LINK in 100), the same seen from either
## cell. Every side of a cracked patch linked would draw a net; a few read as fissures.
func _crack_link(ax: int, ay: int, bx: int, by: int) -> bool:
	if not (_broken_at(ax, ay) and _broken_at(bx, by)):
		return false
	return _h(ax, ay, 5 if bx > ax else 6) % 100 < CRACK_LINK
const CRACK_LINK := 34


## How many open cells there are straight above (0: the far wall is this cell's).
func _pit_depth(cx: int, cy: int) -> int:
	var d := 0
	while d < PIT_DEPTH_CELLS and _pit_at(cx, cy - d - 1):
		d += 1
	return d


## A small fixed hash, so a lip's ragged bits and pebbles stay put through every redraw.
static func _h(cx: int, cy: int, k: int) -> int:
	return posmod((cx * 73856093) ^ (cy * 19349663) ^ (k * 83492791), 1021)


func _paint_pit_cell(ci: CanvasItem, cx: int, cy: int, chasm: bool) -> void:
	var r := _cell_rect(cx, cy)
	var d := _pit_depth(cx, cy)
	var sy := float(d * SimDefs.CELL)
	ci.draw_texture_rect_region(_pit_tex, r, Rect2(AX_CHASM if chasm else 0.0, sy, 8, 8))
	var sx := AX_SIDE_CHASM if chasm else AX_SIDE_HOLE
	var n_solid := d == 0
	var s_solid := not _pit_at(cx, cy + 1)
	var w_solid := not _pit_at(cx - 1, cy)
	var e_solid := not _pit_at(cx + 1, cy)
	# Side walls; under the corner of floor up and to the side, that floor's side wall runs on
	# down into this cell as far as the far wall reaches.
	if w_solid:
		ci.draw_texture_rect_region(_pit_tex, Rect2(r.position, Vector2(3, 8)), Rect2(sx, sy, 3, 8))
	elif not n_solid and not _pit_at(cx - 1, cy - 1):
		ci.draw_texture_rect_region(_pit_tex, Rect2(r.position, Vector2(3, WALL_H)), Rect2(sx, sy, 3, WALL_H))
	if e_solid:
		ci.draw_texture_rect_region(_pit_tex, Rect2(r.end.x - 3, r.position.y, 3, 8), Rect2(sx + 3, sy, 3, 8))
	elif not n_solid and not _pit_at(cx + 1, cy - 1):
		ci.draw_texture_rect_region(_pit_tex, Rect2(r.end.x - 3, r.position.y, 3, WALL_H), Rect2(sx + 3, sy, 3, WALL_H))
	var under := _chasm_under if chasm else _hole_under
	# The far lip: bits of the floor breaking off over the wall, dark under them, pebbles on it.
	if n_solid:
		for k in 1 + _h(cx, cy, 1) % 2:
			var x := float(_h(cx, cy, 2 + k) % 7)
			var w := 1.0 + _h(cx, cy, 4 + k) % 2
			_floor_bit(ci, cx, cy - 1, Rect2(r.position.x + x, r.position.y, w, 1))
			ci.draw_rect(Rect2(r.position.x + x, r.position.y + 1, w, 1), under)
		_pebbles(ci, cx, cy, 10, Vector2(r.position.x, r.position.y - 2))
	# The near edge: the floor in front breaks off ragged, its broken top lit.
	if s_solid:
		var lit := Color(C_NEAR_LIT, _near_lit)
		var bottom := r.end.y - 1
		_floor_bit(ci, cx, cy + 1, Rect2(r.position.x, bottom, 8, 1))
		ci.draw_rect(Rect2(r.position.x, bottom, 8, 1), lit)
		var x := float(_h(cx, cy, 6) % 6)
		var w := 2.0 + _h(cx, cy, 7) % 2
		_floor_bit(ci, cx, cy + 1, Rect2(r.position.x + x, bottom - 1, w, 1))
		ci.draw_rect(Rect2(r.position.x + x, bottom - 1, w, 1), lit)
		_pebbles(ci, cx, cy, 20, Vector2(r.position.x, r.end.y + 1))
	# The sides: a bit of floor jutting out over the wall.
	for side: int in [-1, 1]:
		if not (w_solid if side < 0 else e_solid):
			continue
		var x := r.position.x if side < 0 else r.end.x - 1
		var y := float(2 + _h(cx, cy, 8 + side) % 4)
		_floor_bit(ci, cx + side, cy, Rect2(x, r.position.y + y, 1, 1 + _h(cx, cy, 9 + side) % 2))
		if _h(cx, cy, 12 + side) % 3 == 0:
			_pebbles(ci, cx, cy, 30 + side, Vector2(x - 2.0 if side < 0 else x + 2.0, r.position.y + 1.0), true)


## A pixel or two of the floor next to a pit, drawn over the pit's edge: its own picture
## (cracked if it is), so the lip breaks off the same ground.
func _floor_bit(ci: CanvasItem, ncx: int, ncy: int, at: Rect2) -> void:
	if _art == null:
		ci.draw_rect(at, C_FLOOR_BIT * GROUND_TINT.get(ground, Color.WHITE))
		return
	if ncx >= 0 and ncy >= 0 and ncx < terrain.cols and ncy < terrain.rows and _art_cracked != null:
		var ni := ncy * terrain.cols + ncx
		if terrain.cells[ni] == TerrainGrid.CRACKED and terrain.map_base[ni] != TerrainGrid.WALL and not _grow.has(ni):
			ci.draw_texture_rect_region(_art_cracked, at, _src(_art_cracked, at, FLOOR_ORIGIN))
			return
	ci.draw_texture_rect_region(_art, at, _src(_art, at, -MARGIN))


## Loose pebbles on a pit's rim (0 to 2, fixed per cell), each lit on the side the light
## comes from with its shadow cast the other way. `at` is the left of the row they sit on;
## `one` puts a single pebble right there.
func _pebbles(ci: CanvasItem, cx: int, cy: int, salt: int, at: Vector2, one := false) -> void:
	var count := 1 if one else _h(cx, cy, salt) % 3
	var shx := signf(_light.x) if absf(_light.x) > 0.3 else 0.0
	for k in count:
		var p := at if one else at + Vector2(1 + _h(cx, cy, salt + 1 + k) % 6, -(k % 2))
		var big := _h(cx, cy, salt + 3 + k) % 2 == 0
		ci.draw_rect(Rect2(p + Vector2(shx, 1), Vector2(2 if big else 1, 1)), C_PEBBLE_SHADOW)
		if big:
			var lit_x := 0.0 if _light.x >= 0.0 else 1.0
			ci.draw_rect(Rect2(p, Vector2(2, 1)), C_PEBBLE)
			ci.draw_rect(Rect2(p + Vector2(lit_x, 0), Vector2(1, 1)), C_PEBBLE_LIT)
		else:
			ci.draw_rect(Rect2(p, Vector2(1, 1)), C_PEBBLE_LIT)


# ---------------------------------------------------------------- the floor moving

## A crack runs across its cell in this many ticks (2 px a tick)...
const GROW_STEPS := 4
## ...starting later the farther it is from the middle of the blow (px a tick), at most this late.
const SPREAD_SPEED := 14.0
const GROW_DELAY_MAX := 4
## A pit starts closing this many ticks before it heals (in three steps), and cracked floor
## starts glowing as long before it turns solid; a pit that just healed to cracks glows for KNIT_TICKS.
const HEAL_SHOW := 36
const KNIT_TICKS := 18
## How often (ticks) the healing clocks are looked at.
const HEAL_LOOK := 3
const GLOW_A: Array[float] = [0.22, 0.38, 0.55]
const GLOW_BAND := 0.4
const C_GLOW := Color(1.0, 0.9, 0.62)
const C_CRACK_TIP := Color(1.0, 0.95, 0.82)
const MOTE_CAP := 96
const MOTE_CULL := 16.0
## The over layer redraws only every few ticks, so it draws farther past the screen edge.
const OVER_CULL := 48.0
## Dust tones by ground (light to faint), and a chasm's cold breath.
const DUST := {
	"dirt": [Color8(222, 190, 148), Color8(192, 158, 120), Color8(164, 132, 100)],
	"stone": [Color8(208, 202, 192), Color8(176, 170, 162), Color8(148, 142, 136)],
	"concrete": [Color8(214, 216, 220), Color8(182, 184, 190), Color8(152, 154, 160)],
	"grass": [Color8(212, 192, 150), Color8(180, 160, 122), Color8(150, 132, 102)],
}
const DUST_CHASM: Array[Color] = [Color8(170, 178, 204), Color8(134, 142, 170), Color8(104, 110, 140)]
const MOTE_ALPHA: Array[float] = [0.7, 0.45, 0.25]
enum Mote { PIT_DUST, PUFF, PEBBLE, CHASM_DUST }

var _tick := 0
## Cells whose crack is running: cell -> Vector2i(start tick, side it runs in from:
## 0 left, 1 right, 2 top, 3 bottom, 4 out from the middle).
var _grow := {}
## Cells whose crack has run, drawn whole until their band repaints with them.
var _settle := {}
## [x, y, vx, vy, age, life, kind, phase]
var _motes: Array = []
## Hole cells that just healed to cracks: cell -> tick.
var _knit := {}
## Pits about to heal (closing in), each as cell * 4 + its step (1 to 3), sorted (so by cell).
var _heal_cells := PackedInt32Array()
## Cracked cells about to turn solid: their band paints the cracks lit (C_GLOW, GLOW_BAND).
## A band repaints when one starts and when it heals, so the glow costs no redraw per tick.
var _glowing := {}
var _heal_key := 0
var _over_busy := false
var _dust_drawn := false
## When to look at a damaged cell's healing clock next: tick -> its cells, each due when its
## clock would reach HEAL_SHOW (a clock that was set back in the meantime is put off again),
## so a tick looks at the few cells near healing, not every damaged one.
var _due := {}
## The cells whose clock is within HEAL_SHOW of healing.
var _watch := {}
## Scratch marks for `_spread` (1: new this tick, 2: put in a patch).
var _mark := PackedByteArray()
## Cells a changed row is compared in (a native slice compare skips the unchanged ones).
const SCAN_CHUNK := 16
var _rng := RandomNumberGenerator.new()


func _queue_band(i: int) -> void:
	var k := (i / terrain.cols) / BAND_ROWS
	if not (k in _pending):
		_pending.append(k)


func _schedule(i: int) -> void:
	var at := _tick + maxi(1, terrain.timers[i] - HEAL_SHOW)
	if not _due.has(at):
		_due[at] = PackedInt32Array()
	_due[at].append(i)


func _cell_changed(i: int, was: int, v: int, fresh: Dictionary) -> void:
	_grow.erase(i)
	_settle.erase(i)
	_knit.erase(i)
	_glowing.erase(i)
	var cx := i % terrain.cols
	var cy := i / terrain.cols
	if v == TerrainGrid.CRACKED and was == TerrainGrid.INTACT and terrain.map_base[i] == TerrainGrid.INTACT:
		fresh[i] = 0
	elif TerrainGrid.is_pit(v) and not TerrainGrid.is_pit(was) and not _bridge_gone(cx, cy) \
			and not (v == TerrainGrid.CHASM and _in_art(i)):
		fresh[i] = 1
	elif was == TerrainGrid.HOLE and v == TerrainGrid.CRACKED:
		_knit[i] = _tick


## New cracks and pits come in patches (one blow each): a crack starts running later the
## farther it is from its patch's middle, in from the side facing it, so the patch spreads
## outward; each new pit breathes dust.
func _spread(fresh: Dictionary) -> void:
	var cols := terrain.cols
	var size := terrain.cells.size()
	if _mark.size() != size:
		_mark.resize(size)
	_mark.fill(0)
	for c: int in fresh:
		_mark[c] = 1
	for s: int in fresh:
		if _mark[s] != 1:
			continue
		var patch := PackedInt32Array([s])
		_mark[s] = 2
		var q := 0
		while q < patch.size():
			var c := patch[q]
			q += 1
			var x := c % cols
			if x > 0 and _mark[c - 1] == 1:
				_mark[c - 1] = 2
				patch.append(c - 1)
			if x < cols - 1 and _mark[c + 1] == 1:
				_mark[c + 1] = 2
				patch.append(c + 1)
			if c >= cols and _mark[c - cols] == 1:
				_mark[c - cols] = 2
				patch.append(c - cols)
			if c + cols < size and _mark[c + cols] == 1:
				_mark[c + cols] = 2
				patch.append(c + cols)
		var mid := Vector2.ZERO
		for c in patch:
			mid += Vector2(c % cols, c / cols)
		mid /= float(patch.size())
		for c in patch:
			if fresh[c] == 1:
				_pit_dust(c)
				continue
			if _art_cracked == null:
				continue
			var off := Vector2(c % cols, c / cols) - mid
			var delay := mini(GROW_DELAY_MAX, int(off.length() * SimDefs.CELL / SPREAD_SPEED))
			var side := 4
			if off.length() >= 0.75:
				if absf(off.x) > absf(off.y):
					side = 0 if off.x > 0.0 else 1
				else:
					side = 2 if off.y > 0.0 else 3
			_grow[c] = Vector2i(_tick + delay, side)


func _add_mote(x: float, y: float, vx: float, vy: float, life: int, kind: int) -> void:
	if _motes.size() >= MOTE_CAP:
		return
	_motes.append([x, y, vx, vy, 0, life, kind, _rng.randf() * TAU])


## A fresh pit: a mote or two of dust rising out of it, a pebble off its far lip.
func _pit_dust(i: int) -> void:
	if _motes.size() >= MOTE_CAP:
		return
	var r := _cell_rect(i % terrain.cols, i / terrain.cols)
	var chasm := terrain.cells[i] == TerrainGrid.CHASM
	if _rng.randf() < 0.8:
		_add_mote(r.position.x + _rng.randi_range(0, 7), r.position.y + _rng.randi_range(1, 6),
			_rng.randf_range(-0.04, 0.04), -_rng.randf_range(0.25, 0.45), _rng.randi_range(50, 100),
			Mote.CHASM_DUST if chasm else Mote.PIT_DUST)
	if not _pit_at(i % terrain.cols, i / terrain.cols - 1) and _rng.randf() < 0.6:
		_add_mote(r.position.x + _rng.randi_range(1, 6), r.position.y, 0.0, 0.5, _rng.randi_range(6, 10), Mote.PEBBLE)


## A crack starting to run: a little puff where it breaks out.
func _crack_puff(i: int, side: int) -> void:
	if _motes.size() >= MOTE_CAP:
		return
	var r := _cell_rect(i % terrain.cols, i / terrain.cols)
	var dirs := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2.ZERO]
	var d: Vector2 = dirs[side]
	for k in 1 + int(_rng.randf() < 0.4):
		_add_mote(r.position.x + _rng.randi_range(1, 6), r.position.y + _rng.randi_range(2, 6),
			d.x * 0.3 + _rng.randf_range(-0.15, 0.15), -_rng.randf_range(0.1, 0.3), _rng.randi_range(10, 16), Mote.PUFF)


## How far a cell about to heal is along (1 to 3), from its healing clock.
static func _heal_step(t: int) -> int:
	return 1 + (HEAL_SHOW - clampi(t, 0, HEAL_SHOW)) * 3 / (HEAL_SHOW + 1)


func _step_fx() -> void:
	if _under == null:
		return
	# cracks running
	if not _grow.is_empty():
		var done: Array[int] = []
		for i: int in _grow:
			var g: Vector2i = _grow[i]
			var age := _tick - g.x
			if age == 0:
				_crack_puff(i, g.y)
			if age >= GROW_STEPS:
				done.append(i)
		for i in done:
			_grow.erase(i)
			_settle[i] = true
			var k := (i / terrain.cols) / BAND_ROWS
			if not (k in _pending):
				_pending.push_front(k)
		_under.queue_redraw()
	# dust
	var j := 0
	while j < _motes.size():
		var m: Array = _motes[j]
		m[4] += 1
		if m[4] >= m[5]:
			_motes[j] = _motes[_motes.size() - 1]
			_motes.pop_back()
			continue
		m[0] += m[2]
		m[1] += m[3]
		if m[6] == Mote.PUFF:
			m[2] *= 0.85
		j += 1
	if not _motes.is_empty() or _dust_drawn:
		_dust.queue_redraw()
	_dust_drawn = not _motes.is_empty()
	# healing: a step lasts HEAL_SHOW / 3 ticks, so every third tick is soon enough to look
	if _tick % HEAL_LOOK != 0:
		return
	_heal_cells.clear()
	var key := 0
	var timers := terrain.timers
	var cells := terrain.cells
	var base := terrain.base
	for at in range(_tick - HEAL_LOOK + 1, _tick + 1):
		if not _due.has(at):
			continue
		for i in _due[at]:
			if cells[i] != base[i]:
				if timers[i] > HEAL_SHOW:
					_schedule(i)
				else:
					_watch[i] = true
		_due.erase(at)
	if not _watch.is_empty():
		var off: Array[int] = []
		for i: int in _watch:
			var t := timers[i]
			var v := cells[i]
			if v == base[i] or t > HEAL_SHOW:
				off.append(i)
				continue
			if v == TerrainGrid.HOLE:
				if not _bridge_gone(i % terrain.cols, i / terrain.cols):
					var code := i * 4 + _heal_step(t)
					_heal_cells.append(code)
					key = key * 31 + code
			elif v == TerrainGrid.CRACKED and not _glowing.has(i) and base[i] == TerrainGrid.INTACT \
					and terrain.map_base[i] == TerrainGrid.INTACT:
				_glowing[i] = true  # its band repaints with the cracks lit
				_queue_band(i)
		for i in off:
			_watch.erase(i)
			if _glowing.has(i):
				_glowing.erase(i)
				_queue_band(i)
			if cells[i] != base[i]:
				_schedule(i)
	if not _knit.is_empty():
		var old: Array[int] = []
		for i: int in _knit:
			var age: int = _tick - _knit[i]
			if age >= KNIT_TICKS:
				old.append(i)
			else:
				key = key * 31 + i * 4 + age * 3 / KNIT_TICKS
		for i in old:
			_knit.erase(i)
	_heal_cells.sort()
	var busy := not _heal_cells.is_empty() or not _knit.is_empty()
	if key != _heal_key or (_over_busy and not busy):
		_over.queue_redraw()
	_heal_key = key
	_over_busy = busy


## The cracked picture over `at` (the floor broken), or the plain one on a map without it.
func _cracked_piece(ci: CanvasItem, at: Rect2) -> void:
	if _art_cracked != null:
		ci.draw_texture_rect_region(_art_cracked, at, _src(_art_cracked, at, FLOOR_ORIGIN))
	elif _art != null:
		ci.draw_texture_rect_region(_art, at, _src(_art, at, -MARGIN))
	else:
		ci.draw_rect(at, C_FLOOR_BIT * GROUND_TINT.get(ground, Color.WHITE))


## The cracks inside `at` lit up in `col` (nothing on a map without a crack mask).
func _glow(ci: CanvasItem, at: Rect2, col: Color) -> void:
	if _mask != null:
		ci.draw_texture_rect_region(_mask, at, _src(_mask, at, FLOOR_ORIGIN), col)


## Under the pits: cracks running across their cells, their tips lit.
func _paint_under(ci: CanvasItem, _row0: int, _row1: int) -> void:
	var view := FxView._view_rect(ci, MOTE_CULL)
	for i: int in _settle:
		var r := _cell_rect(i % terrain.cols, i / terrain.cols)
		if view.intersects(r):
			_cracked_piece(ci, r)
	for i: int in _grow:
		var g: Vector2i = _grow[i]
		var age := _tick - g.x
		if age < 0:
			continue
		var r := _cell_rect(i % terrain.cols, i / terrain.cols)
		if not view.intersects(r):
			continue
		var s := mini(age + 1, GROW_STEPS)
		var w := float(s * 2)
		var clip: Rect2
		var tip: Rect2
		match g.y:
			0:
				clip = Rect2(r.position, Vector2(w, 8))
				tip = Rect2(r.position.x + w - 1, r.position.y, 1, 8)
			1:
				clip = Rect2(r.end.x - w, r.position.y, w, 8)
				tip = Rect2(clip.position, Vector2(1, 8))
			2:
				clip = Rect2(r.position, Vector2(8, w))
				tip = Rect2(r.position.x, r.position.y + w - 1, 8, 1)
			3:
				clip = Rect2(r.position.x, r.end.y - w, 8, w)
				tip = Rect2(clip.position, Vector2(8, 1))
			_:
				clip = Rect2(r.get_center() - Vector2(w, w) * 0.5, Vector2(w, w))
				tip = clip
		_cracked_piece(ci, clip)
		if s < GROW_STEPS:
			_glow(ci, tip, Color(C_CRACK_TIP, 0.8 if g.y < 4 else 0.45))


## Over the pits: pits closing in from their rims and knitting cracks glowing before they
## heal (redrawn only when one of them moves on a step).
func _paint_over(ci: CanvasItem, _row0: int, _row1: int) -> void:
	if _tiles != null:
		return  # a tiled map's pits close as overlay tiles: no baked picture to creep in
	var view := FxView._view_rect(ci, OVER_CULL)
	# Pits side by side in a row at the same step close in one go: a run of far rims, a run
	# of near rims (`_run`, `_flush`).
	var runs: Array = [[Rect2(), -2, 0, RUN_FAR], [Rect2(), -2, 0, RUN_NEAR]]
	var cols := terrain.cols
	for code in _heal_cells:  # in order, so a row's cells come together
		var i := code >> 2
		var cx := i % cols
		var cy := i / cols
		var r := Rect2(SimDefs.GRID_X + cx * SimDefs.CELL, SimDefs.GRID_Y + cy * SimDefs.CELL, SimDefs.CELL, SimDefs.CELL)
		if not view.intersects(r):
			continue
		var s := code & 3
		# the floor's edge creeping in over the pit, s px, its new lip dark (far) or lit (near)
		var fs := float(s)
		if not _pit_at(cx, cy - 1):
			_run(ci, runs[0], i, cx, s, Rect2(r.position, Vector2(8, fs)))
		if not _pit_at(cx, cy + 1):
			_run(ci, runs[1], i, cx, s, Rect2(r.position.x, r.end.y - fs, 8, fs))
		for side: int in [-1, 1]:
			if _pit_at(cx + side, cy):
				continue
			var strip := Rect2(r.position.x if side < 0 else r.end.x - fs, r.position.y, fs, 8)
			_cracked_piece(ci, strip)
			_glow(ci, strip, Color(C_GLOW, GLOW_A[s - 1]))
	for run: Array in runs:
		_flush(ci, run)
	for i: int in _knit:
		var r := _cell_rect(i % terrain.cols, i / terrain.cols)
		if view.intersects(r):
			var step := 2 - mini(2, (_tick - int(_knit[i])) * 3 / KNIT_TICKS)
			_glow(ci, r, Color(C_GLOW, GLOW_A[step]))


enum { RUN_FAR, RUN_NEAR }


## Adds cell `i`'s piece `at` to a run ([rect, last cell, step, kind]) if it carries the run
## on along the row at the same step; else draws the run so far and starts a new one.
func _run(ci: CanvasItem, run: Array, i: int, cx: int, s: int, at: Rect2) -> void:
	if i == int(run[1]) + 1 and s == int(run[2]) and cx > 0:
		var rect: Rect2 = run[0]
		rect.size.x += at.size.x
		run[0] = rect
	else:
		_flush(ci, run)
		run[0] = at
		run[2] = s
	run[1] = i


func _flush(ci: CanvasItem, run: Array) -> void:
	if int(run[1]) < 0:
		return
	var at: Rect2 = run[0]
	var glow := Color(C_GLOW, GLOW_A[int(run[2]) - 1])
	match int(run[3]):
		RUN_FAR:
			_cracked_piece(ci, at)
			_glow(ci, at, glow)
			ci.draw_rect(Rect2(at.position.x, at.end.y, at.size.x, 1), _hole_under)
		RUN_NEAR:
			_cracked_piece(ci, at)
			_glow(ci, at, glow)
			ci.draw_rect(Rect2(at.position, Vector2(at.size.x, 1)), Color(C_NEAR_LIT, _near_lit))
	run[1] = -2


## Dust rising from fresh pits and puffing off running cracks, pebbles dropping in.
func _paint_dust(ci: CanvasItem, _row0: int, _row1: int) -> void:
	var view := FxView._view_rect(ci, MOTE_CULL)
	var dust: Array = DUST.get(ground, DUST["dirt"])
	for m: Array in _motes:
		var p := Vector2(floorf(m[0]), floorf(m[1]))
		if not view.has_point(p):
			continue
		var life_share := float(m[4]) / float(m[5])
		var step := 0 if life_share < 0.4 else (1 if life_share < 0.75 else 2)
		match int(m[6]):
			Mote.PEBBLE:
				ci.draw_rect(Rect2(p, Vector2(1, 1)), C_PEBBLE if m[4] < 3 else _hole_dark)
			Mote.PUFF:
				ci.draw_rect(Rect2(p, Vector2(1, 1)), Color(dust[step], MOTE_ALPHA[step]))
			_:
				var cols: Array = DUST_CHASM if int(m[6]) == Mote.CHASM_DUST else dust
				p.x += roundf(sin(float(m[4]) * 0.09 + float(m[7])))  # a slow sway, whole pixels
				var w := 2.0 if life_share < 0.2 else 1.0
				ci.draw_rect(Rect2(p, Vector2(w, 1)), Color(cols[step], MOTE_ALPHA[step]))
