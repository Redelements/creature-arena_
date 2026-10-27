extends SceneTree
## Seeds a map's hand-dressing scene (assets/arenas/<id>_dressing.tscn) from a first-draft
## spec, tools/dressing/<id>.json. After that the SCENE is the source: open it in the Godot
## editor and nudge, add or delete props, paint paths and detail with its TileMapLayers.
## tools/build_tiles.gd only instances it (map key `tiles.dressing`), so a rebuild of the
## ground scene never touches it. This tool refuses to overwrite an existing scene unless
## given --force, which throws every hand edit away.
##
## Run from the repo root, after the set is cut and imported:
##   godot --headless --path . --script res://tools/seed_dressing.gd -- --map=twin_keeps [--force]
##
## The scene it writes (scene px: 2 a unit, the ground scene's own space; assets/README.md
## "Dressing"):
##   Dressing   Node2D, y-sorted (it sits in the ground scene's y-sorted Walls)
##     Paths    TileMapLayer, <set>_ground.tres: the "path" terrain (worn dirt), 32 px tiles
##     Flat     Node2D: flat decals (cobble patches, ragged dirt and grass patches), feet at pos
##     Detail   TileMapLayer, <set>_cells.tres: small flat sprites a cell each (moss, leaves,
##              stepping stones, flowers, lily pads), the scatter atlas's slots
##     Props    Node2D, y-sorted: props standing on wall or fence cells, each a Sprite2D or
##              AnimatedSprite2D whose position is its feet (it sorts and hides by them; the
##              picture is drawn `lift` higher by its offset) with a "Shadow" child
## The three flat parts sort at y 0, under every wall sprite.
##
## Spec keys (units from the floor's top-left corner, cells 8 units, tiles 2 x 2 cells):
##   scene   the scene to write; set: the cut set (default "keeps"); map: the arena id, whose
##           cells keep the detail flat (lily pads on water, the rest on plain floor only)
##   mirror  {"width": units, "swap": {"from": "to", ...}}: every entry is also placed mirrored
##           left to right (x -> width - x, flipped), its kind's name with each swap applied
##           (the left keep's red cloth becomes the right keep's blue); "solo": true opts out
##   paths   [[tx, ty, w, h], ...]: tile rects painted with the path terrain, joined
##   flat    [{kind, pos, flip}]: decor (manifest "decor") laid flat, feet at pos
##   detail  [{kind, cells: [[cx, cy], ...]} | {kind, clump: [cx, cy], n, r, seed}]: scatter
##           sprites (manifest "scatter" kinds) on single cells, or n of them in a clump of
##           radius r cells round a cell; a kind's look per cell by a fixed hash
##   props   [{kind, pos, lift, flip, shadow, stack}]: decor or anim (manifest "decor" /
##           "anim") with feet at pos (on a wall or fence cell), drawn `lift` units higher;
##           `shadow` false for none (a piece up on a wall's top); `stack` k sorts it k
##           hundredths of a px after the piece it stands on

const TILES_DIR := "res://assets/tiles/"
const SRC_SCATTER := 0  ## build_tiles.gd: the scatter sprites in <set>_cells.tres
const SCATTER_ALTS := 8
const PPU := 2.0  ## ArtScale.PX_PER_UNIT
const CELL := 8.0  ## SimDefs.CELL
const SHADOW_SHIFT := 2.0  ## px a contact shadow leans right, away from the maps' top-left light


func _init() -> void:
	var id := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			id = a.trim_prefix("--map=")
		elif a == "--force":
			force = true
	var spec := _json("res://tools/dressing/%s.json" % id)
	if spec.is_empty():
		push_error("no spec tools/dressing/%s.json" % id)
		quit(1)
		return
	var path := String(spec.get("scene", "res://assets/arenas/%s_dressing.tscn" % id))
	if FileAccess.file_exists(path) and not force:
		push_error("%s exists: it is the source now (edit it in the editor); --force reseeds and loses every hand edit" % path)
		quit(1)
		return
	var root := seed_scene(spec)
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, path)
	if err != OK:
		push_error("could not save %s: %d" % [path, err])
		quit(1)
		return
	print("wrote %s: %d path tiles, %d flat, %d detail, %d props" % [path,
		(root.get_node("Paths") as TileMapLayer).get_used_cells().size(), root.get_node("Flat").get_child_count(),
		(root.get_node("Detail") as TileMapLayer).get_used_cells().size(), root.get_node("Props").get_child_count()])
	root.free()
	quit(0)


static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func _h(x: int, y: int, k: int) -> int:
	return posmod((x * 73856093) ^ (y * 19349663) ^ (k * 83492791), 1021)


## Every entry of `list` and, with a `mirror`, its mirrored twin (`twin` makes one).
static func _both(list: Array, spec: Dictionary, twin: Callable) -> Array:
	var out: Array = []
	for e: Dictionary in list:
		out.append(e)
		if spec.has("mirror") and not bool(e.get("solo", false)):
			out.append(twin.call(e))
	return out


static func _swap(kind: String, spec: Dictionary) -> String:
	var sw: Dictionary = spec.get("mirror", {}).get("swap", {})
	for k in sw:
		if kind.contains(String(k)):
			return kind.replace(String(k), String(sw[k]))
	return kind


static func _mirror_entry(e: Dictionary, spec: Dictionary) -> Dictionary:
	var w := float(spec["mirror"]["width"])
	var m := e.duplicate(true)
	m["kind"] = _swap(String(e["kind"]), spec)
	if e.has("pos"):
		m["pos"] = [w - float(e["pos"][0]), float(e["pos"][1])]
	m["flip"] = not bool(e.get("flip", false))
	var cols := int(w / CELL)
	if e.has("cells"):
		m["cells"] = (e["cells"] as Array).map(func(c): return [cols - 1 - int(c[0]), int(c[1])])
	if e.has("clump"):
		m["clump"] = [cols - 1 - int(e["clump"][0]), int(e["clump"][1])]
		m["seed"] = int(e.get("seed", 0)) + 500
	return m


## The whole dressing scene from a spec, in memory.
static func seed_scene(spec: Dictionary) -> Node2D:
	var set_name := String(spec.get("set", "keeps"))
	var man := _json(TILES_DIR + set_name + "_manifest.json")
	var grid: TerrainGrid = null  # the map's cells: detail only where it lies flat
	if spec.has("map"):
		var map := ArenaMap.get_map(String(spec["map"]))
		var size := ArenaMap.size_of(map)
		grid = TerrainGrid.new(size.x, size.y)
		grid.load_map(map)
	var root := Node2D.new()
	root.name = "Dressing"
	root.y_sort_enabled = true
	root.set_meta("doc", "Hand dressing (tools/seed_dressing.gd seeded it; edit it here). Props: position = feet on a wall or fence cell, offset draws the picture higher; flat parts sort at y 0. assets/README.md \"Dressing\".")

	# paths: the path terrain over the tile rects, joined
	var paths := TileMapLayer.new()
	paths.name = "Paths"
	paths.tile_set = load(TILES_DIR + set_name + "_ground.tres")
	root.add_child(paths)
	paths.owner = root
	var cells: Array[Vector2i] = []
	var mw := int(float(spec.get("mirror", {}).get("width", 0)) / (CELL * 2.0))
	for r in spec.get("paths", []):
		for ty in range(int(r[1]), int(r[1]) + int(r[3])):
			for tx in range(int(r[0]), int(r[0]) + int(r[2])):
				for c in ([Vector2i(tx, ty), Vector2i(mw - 1 - tx, ty)] if mw > 0 else [Vector2i(tx, ty)]):
					if not c in cells:
						cells.append(c)
	var ts: TileSet = paths.tile_set
	for i in ts.get_terrains_count(0):
		if ts.get_terrain_name(0, i) == "path" and not cells.is_empty():
			paths.set_cells_terrain_connect(cells, 0, i, false)

	# flat decals
	var flat := Node2D.new()
	flat.name = "Flat"
	root.add_child(flat)
	flat.owner = root
	var mir := func(e): return _mirror_entry(e, spec)
	for e in _both(spec.get("flat", []), spec, mir):
		var d: Dictionary = man.get("decor", {}).get(String(e["kind"]), {})
		if d.is_empty():
			push_warning("no decor " + String(e["kind"]))
			continue
		var f := _sprite(e, d, root, 0.0)
		f.name = "%s_%d" % [String(e["kind"]), flat.get_child_count()]
		flat.add_child(f)
		f.owner = root

	# detail: scatter sprites a cell each
	var detail := TileMapLayer.new()
	detail.name = "Detail"
	detail.tile_set = load(TILES_DIR + set_name + "_cells.tres")
	root.add_child(detail)
	detail.owner = root
	var kinds: Dictionary = man.get("scatter", {}).get("kinds", {})
	var per := int(man.get("scatter", {}).get("slot", 32)) / int(CELL * PPU)
	for e in _both(spec.get("detail", []), spec, mir):
		var slots: Array = kinds.get(String(e["kind"]), [])
		if slots.is_empty():
			push_warning("no scatter kind " + String(e["kind"]))
			continue
		var at: Array = e.get("cells", [])
		if e.has("clump"):
			at = _clump(e)
		for c in at:
			var v := Vector2i(int(c[0]), int(c[1]))
			if grid != null and not _flat_ok(String(e["kind"]), v, grid):
				continue
			var slot: Array = slots[_h(v.x, v.y, 7) % slots.size()]
			detail.set_cell(v, SRC_SCATTER, Vector2i(int(slot[0]), int(slot[1])) * per, _h(v.x, v.y, 9) % SCATTER_ALTS)

	# props, y-sorted by their feet among the wall sprites
	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	root.add_child(props)
	props.owner = root
	var frames := {}
	for e in _both(spec.get("props", []), spec, mir):
		var kind := String(e["kind"])
		var lift := float(e.get("lift", 0.0))
		var n: Node2D
		var w := 0.0
		if man.get("decor", {}).has(kind):
			var d: Dictionary = man["decor"][kind]
			n = _sprite(e, d, root, lift)
			w = float(d["size"][0])
		elif man.get("anim", {}).has(kind):
			var a: Dictionary = man["anim"][kind]
			n = _anim(e, a, frames, lift)
			w = float(a["frame"][0])
		else:
			push_warning("no decor or anim " + kind)
			continue
		n.position.y += 0.01 * float(e.get("stack", 0))
		n.name = "%s_%d" % [kind, props.get_child_count()]
		props.add_child(n)
		n.owner = root
		if bool(e.get("shadow", true)):
			_shadow(n, man, w * float(e.get("shadow_w", 0.85)), lift, root)
	return root


## A decor sprite with its feet at the entry's pos (scene px), drawn `lift` units higher.
static func _sprite(e: Dictionary, d: Dictionary, root: Node, lift: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(TILES_DIR + String(d["source"]))
	s.centered = false
	var flip := bool(e.get("flip", false))
	s.flip_h = flip
	var size := Vector2(float(d["size"][0]), float(d["size"][1]))
	var feet := Vector2(float(d["feet"][0]), float(d["feet"][1]))
	if flip:
		feet.x = size.x - feet.x
	s.position = Vector2(float(e["pos"][0]), float(e["pos"][1])) * PPU
	s.offset = -feet - Vector2(0.0, lift * PPU)
	s.set_meta("kind", String(e["kind"]))
	return s


## An animated piece (manifest anim) with its feet at pos, the frames shared per kind, each
## starting on its own frame so neighbours don't flicker in step.
static func _anim(e: Dictionary, a: Dictionary, cache: Dictionary, lift: float) -> AnimatedSprite2D:
	var kind := String(e["kind"])
	if not cache.has(kind):
		var tex: Texture2D = load(TILES_DIR + String(a["source"]))
		var sf := SpriteFrames.new()
		sf.set_animation_speed("default", float(a["fps"]))
		var fw := int(a["frame"][0])
		var fh := int(a["frame"][1])
		for k in int(a["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(k * fw, 0, fw, fh)
			sf.add_frame("default", at)
		cache[kind] = sf
	var s := AnimatedSprite2D.new()
	s.sprite_frames = cache[kind]
	s.centered = false
	s.autoplay = "default"
	s.frame = _h(int(e["pos"][0]), int(e["pos"][1]), 5) % int(a["frames"])
	var flip := bool(e.get("flip", false))
	s.flip_h = flip
	var feet := Vector2(float(a["feet"][0]), float(a["feet"][1]))
	if flip:
		feet.x = float(a["frame"][0]) - feet.x
	s.position = Vector2(float(e["pos"][0]), float(e["pos"][1])) * PPU
	s.offset = -feet - Vector2(0.0, lift * PPU)
	s.set_meta("kind", kind)
	return s


## A contact shadow under a prop: the set's shadow ellipse nearest `w` px wide, behind it.
static func _shadow(n: Node2D, man: Dictionary, w: float, lift: float, root: Node) -> void:
	var sh: Dictionary = man.get("shadows", {})
	if sh.is_empty():
		return
	var best: Array = sh["boxes"][0]
	for b in sh["boxes"]:
		if absf(float(b[2]) - w) < absf(float(best[2]) - w):
			best = b
	var s := Sprite2D.new()
	s.name = "Shadow"
	s.texture = load(TILES_DIR + String(sh["source"]))
	s.region_enabled = true
	s.region_rect = Rect2(float(best[0]), float(best[1]), float(best[2]), float(best[3]))
	s.centered = true
	s.position = Vector2(SHADOW_SHIFT, -lift * PPU - 1.0)
	s.show_behind_parent = true
	n.add_child(s)
	s.owner = root


## Whether a detail sprite of `kind` may lie on cell `c`: lily pads on the water, everything
## else on plain floor (never on a wall, fence, chasm, brush bed or the water).
static func _flat_ok(kind: String, c: Vector2i, grid: TerrainGrid) -> bool:
	if not grid.in_bounds(c):
		return false
	return grid.get_base(c) == (TerrainGrid.SHALLOWS if kind == "lily" else TerrainGrid.INTACT)


## The cells of a clump: n cells within r of its middle, picked by a fixed hash.
static func _clump(e: Dictionary) -> Array:
	var mid := Vector2i(int(e["clump"][0]), int(e["clump"][1]))
	var r := int(e.get("r", 2))
	var n := int(e.get("n", 4))
	var k := int(e.get("seed", 0))
	var pool: Array = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r + r:
				pool.append(Vector2i(mid.x + dx, mid.y + dy))
	pool.sort_custom(func(p, q): return _h(p.x, p.y, 11 + k) < _h(q.x, q.y, 11 + k))
	return pool.slice(0, mini(n, pool.size())).map(func(p): return [p.x, p.y])
