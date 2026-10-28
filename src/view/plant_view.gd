class_name PlantView
extends Node2D
## Barkley's plants on the floor, drawn from `MatchSim.plants` (src/sim/plants.gd): a sprout
## pushing up out of the floor as the seed's burst clears and swaying on its dirt patch (a small HP bar over it only once it's hurt, a flash and a
## shiver when it's struck), the tree it grows into rising out of the ground and swaying,
## and the apple bobbing at the tree's foot. A plant gone from the match (a spent tree, a
## sprung sprout) sinks back into the floor over a few ticks. Views only read the sim.
##
## Two depths: this node lies on the floor, under the fighters (main adds it after the
## shadows), and draws the trees' shadows along the map's light; `stand` (main puts it among
## the y-sorted entities) holds one `Plant` node per plant standing on its feet, so a
## fighter behind a tree is drawn behind it, and a tree over a fighter the local team sees
## fades see-through (`COVER_ALPHA`, over `COVER_EASE` ticks). A plant hides from a viewer who can't see its spot
## (`FxView.sight_to`) unless it's their side's. The art is assets/props/ (tools/cut_props.py,
## ppu 2: 2 texture pixels a unit); the effects round it (seed, grow, apple, eaten) are
## `fx_view.gd:_plant_event`.

const SPROUT := preload("res://assets/props/barkley_sprout.png")
const TREE := preload("res://assets/props/barkley_tree.png")
const APPLE := preload("res://assets/props/apple.png")
const PPU := 2
## Frame size, feet (texture px) and ticks a frame: tools/cut_props.py's manifest.
const SPROUT_SIZE := Vector2(32, 32)
const SPROUT_FEET := Vector2(16, 28)
const SPROUT_FRAMES := 4
const SPROUT_TPF := 10
const TREE_SIZE := Vector2(104, 120)
const TREE_FEET := Vector2(52, 114)
const TREE_FRAMES := 12
const TREE_TPF := 7
const APPLE_FEET := Vector2(4, 9)
## The apple sits on the floor at the trunk's foot, a little in front and to the side.
const APPLE_AT := Vector2(7, 2)
## Ticks a new tree takes to rise out of the ground.
const RISE_TICKS := 16.0
## A new sprout pushes up out of the floor as the seed's burst clears: it waits
## SPROUT_DELAY ticks, then rises over SPROUT_RISE.
const SPROUT_DELAY := 10.0
const SPROUT_RISE := 10.0
## Ticks a plant that's gone takes to sink back into the floor: a spent tree (its apple
## eaten or spoiled) and a sprung sprout (it snaps shut on the foe). A killed sprout
## goes at once, under its burst of leaves.
const TREE_SINK := 14
const SPROUT_SINK := 6
## Ticks the see-through takes to fade in or out as a fighter steps behind a tree.
const COVER_EASE := 6.0
## Ticks a struck sprout flashes and shivers.
const FLASH_TICKS := 8
## How see-through a tree is while it stands over a fighter the local team sees.
const COVER_ALPHA := 0.5
const C_BAR_BACK := Color(0.05, 0.06, 0.05, 0.75)
const C_BAR := Color("28b450")
const C_BAR_LOW := Color("e8c060")
## The apple's light rim (one texture pixel round it), so it reads on any floor.
const C_APPLE_RIM := Color(1.0, 0.96, 0.82, 0.7)

var sim: MatchSim
var fx: FxView
var weather: WeatherView
## The fighters' shadow layer: its `light` (the map's, as the time of day sets it) casts the trees'.
var shadows: ShadowLayer
var stand := Node2D.new()
var _nodes := {}  ## plant id -> Plant
var _t := 0.0
var _shadow_key: Array = []


func _init() -> void:
	stand.y_sort_enabled = true
	stand.name = "Plants"


func clear() -> void:
	for id in _nodes:
		(_nodes[id] as Node).queue_free()
	_nodes.clear()
	_shadow_key = []
	queue_redraw()


## One tick: a node for each plant (made, moved, dropped), redrawn when its look changes.
func advance() -> void:
	if sim == null:
		if not _nodes.is_empty():
			clear()
		return
	_t += fx.time_scale if fx != null else 1.0
	var live := {}
	var shadow_key: Array = []
	for pl in sim.plants:
		var id := int(pl["id"])
		live[id] = true
		var n: Plant = _nodes.get(id)
		if n == null:
			n = Plant.new()
			n.view = self
			n.hp_seen = float(pl["hp"])
			stand.add_child(n)
			_nodes[id] = n
		n.pl = pl
		n.dying = -1
		n.position = ArtScale.snap(Vector2(pl["pos"]), PPU)
		n.visible = _seen(pl)
		if float(pl["hp"]) < n.hp_seen:
			n.flash = FLASH_TICKS
		n.hp_seen = float(pl["hp"])
		if n.flash > 0:
			n.flash -= 1
		var want := 1.0 if int(pl["stage"]) == Plants.TREE and _covers(pl) else 0.0
		n.cover = move_toward(n.cover, want, 1.0 / COVER_EASE)
		var key := _key(pl, n)
		if key != n.key:
			n.key = key
			n.queue_redraw()
		if int(pl["stage"]) == Plants.TREE and n.visible:
			shadow_key.append([id, key[1], key[3]])
	if shadows != null:
		shadow_key.append(shadows.light)
	for id in _nodes.keys():
		if live.has(id):
			continue
		# Gone from the match: sink back into the floor for a few ticks, then go.
		var n: Plant = _nodes[id]
		if n.dying < 0:
			n.sink = _sink_ticks(n)
			n.dying = n.sink
		n.dying -= 1
		var behind := 1.0 if int(n.pl["stage"]) == Plants.TREE and _covers(n.pl) else 0.0
		n.cover = move_toward(n.cover, behind, 1.0 / COVER_EASE)
		if n.dying <= 0:
			n.queue_free()
			_nodes.erase(id)
			continue
		var key := _key(n.pl, n)
		if key != n.key:
			n.key = key
			n.queue_redraw()
		if int(n.pl["stage"]) == Plants.TREE and n.visible:
			shadow_key.append([id, key[1], key[3]])
	if shadow_key != _shadow_key:
		_shadow_key = shadow_key
		queue_redraw()


## Whether the local team sees this plant: always its own side's, else where they have
## a line of sight to it (walls and fences block it, like a projectile).
func _seen(pl: Dictionary) -> bool:
	if fx == null or fx.viewer_team < 0 or int(pl["team"]) == fx.viewer_team:
		return true
	return fx.sight_to(Vector2(pl["pos"]))


func _key(pl: Dictionary, n: Plant) -> Array:
	var id := int(pl["id"])
	if int(pl["stage"]) == Plants.PLANT:
		var shake := 0 if n.flash <= 0 else (1 if n.flash % 4 < 2 else -1)
		var up := _rise(pl, n, SPROUT_FEET.y, SPROUT_DELAY, SPROUT_RISE, 0)
		return [0, _frame(id, SPROUT_FRAMES, SPROUT_TPF), int(ceilf(float(pl["hp"]))), shake, n.flash > 0, up]
	var rise := _rise(pl, n, TREE_FEET.y, 0.0, RISE_TICKS, int(pl["grow"]))
	var bob := int(_t / 20.0 + id) % 2 if bool(pl["apple"]) else -1
	var glint := bool(pl["apple"]) and int(_t + id * 7) % 90 < 6
	var tint := weather.prop_tint(Vector2(pl["pos"])) if weather != null else Color.WHITE
	var cover := roundf(n.cover * COVER_EASE) / COVER_EASE
	return [1, _frame(id, TREE_FRAMES, TREE_TPF), bob if n.dying < 0 else -1, rise, glint, cover, tint, n.flash > 0,
		int(ceilf(float(pl["hp"])))]


func _frame(id: int, frames: int, tpf: int) -> int:
	return int(_t / float(tpf) + id * 3) % frames


## 0..1: how far a plant stands out of the ground, in whole pixels of its `rows`: rising
## `ticks` long from `delay` ticks after `from` (its age when it took this stage), or
## sinking back while it's gone.
func _rise(pl: Dictionary, n: Plant, rows: float, delay: float, ticks: float, from: int) -> float:
	var k := float(int(pl["age"]) - from) - delay
	k = k / ticks if n.dying < 0 else float(n.dying) / float(maxi(1, n.sink))
	return clampf(roundf(k * rows) / rows, 0.0, 1.0)


static var _rim: Texture2D


## The apple's shape in white (its rim is drawn from it), made once.
static func apple_rim() -> Texture2D:
	if _rim == null:
		var img := APPLE.get_image()
		img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if img.get_pixel(x, y).a > 0.5 else 0.0))
		_rim = ImageTexture.create_from_image(img)
	return _rim


## Ticks a plant just gone from the match takes to sink away (0: at once).
func _sink_ticks(n: Plant) -> int:
	if n.key.is_empty():
		return 0
	if int(n.key[0]) == 1:
		return TREE_SINK
	return SPROUT_SINK if float(n.pl.get("hp", 0.0)) > 0.0 else 0


## Whether the tree stands in front of a fighter the local team sees (their feet just north
## of its foot, under its crown): then it's drawn see-through.
func _covers(pl: Dictionary) -> bool:
	var at: Vector2 = pl["pos"]
	var half := TREE_SIZE.x * 0.5 / PPU
	var tall := TREE_SIZE.y / PPU
	for c in sim.creatures:
		if c.state == CreatureSim.State.KO or (fx != null and not fx.shown(c)):
			continue
		var d := c.pos - at
		if d.y < 0.0 and d.y > -tall * 0.8 and absf(d.x) < half:
			return true
	return false


## The trees' shadows on the floor, along the map's light (as a fighter's or the wagon's).
func _draw() -> void:
	if sim == null:
		return
	var light: Dictionary = shadows.light if shadows != null else ShadowLayer.light_of(sim.arena)
	for id in _nodes:
		var n: Plant = _nodes[id]
		if not n.visible or n.key.is_empty() or int(n.key[0]) != 1 or float(n.key[3]) <= 0.0:
			continue
		# a rising (or sinking) tree casts only the part of it out of the ground
		var rise := float(n.key[3])
		var rows := TREE_SIZE.y if rise >= 1.0 else roundf(TREE_FEET.y * rise)
		var feet := TREE_FEET if rise >= 1.0 else Vector2(TREE_FEET.x, rows)
		var region := Rect2(int(n.key[1]) * TREE_SIZE.x, 0, TREE_SIZE.x, rows)
		ShadowLayer.draw_silhouette(self, TREE, region, feet, false, n.position, light["cast"],
			float(light["alpha"]), Vector2.ONE / PPU)


## One plant, standing on its feet among the fighters.
class Plant extends Node2D:
	var view: PlantView
	var pl: Dictionary = {}
	var key: Array = []
	var hp_seen := 0.0
	var flash := 0
	var cover := 0.0  ## 0..1, eased: how see-through the tree is
	var dying := -1  ## ticks left sinking away once gone from the match (-1: still in it)
	var sink := 0  ## the ticks that sinking takes

	func _draw() -> void:
		if key.is_empty():
			return
		if int(key[0]) == 0:
			_draw_sprout()
		else:
			_draw_tree()

	func _draw_sprout() -> void:
		var frame := int(key[1])
		var shake := float(int(key[3])) * 0.5
		var col := Color(1.7, 1.7, 1.5) if bool(key[4]) else Color.WHITE
		var up := float(key[5])
		draw_set_transform(Vector2(shake, 0), 0.0, Vector2.ONE / PPU)
		var src := Rect2(frame * SPROUT_SIZE.x, 0, SPROUT_SIZE.x, SPROUT_SIZE.y)
		if up >= 1.0:
			draw_texture_rect_region(SPROUT, Rect2(-SPROUT_FEET, SPROUT_SIZE), src, col)
		else:
			# pushing up out of the floor (or snapping back down): its top `up` shows
			var rows := roundf(SPROUT_FEET.y * up)
			if rows > 0.0:
				draw_texture_rect_region(SPROUT, Rect2(-SPROUT_FEET.x, -rows, SPROUT_SIZE.x, rows),
					Rect2(src.position, Vector2(SPROUT_SIZE.x, rows)), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if up < 1.0:
			return
		var hp := float(pl.get("hp", 0.0))
		var hp_max := maxf(1.0, float(pl.get("hp_max", 1.0)))
		if hp < hp_max:
			# a tiny bar over the leaves: 12 units, 1 tall, on a dark backing
			var w := 12.0
			var y := -SPROUT_SIZE.y / PPU + 1.0
			draw_rect(Rect2(-w * 0.5 - 0.5, y - 0.5, w + 1.0, 2.0), C_BAR_BACK)
			var k := clampf(hp / hp_max, 0.0, 1.0)
			draw_rect(Rect2(-w * 0.5, y, roundf(w * k * PPU) / PPU, 1.0), C_BAR if k > 0.4 else C_BAR_LOW)

	func _draw_tree() -> void:
		var frame := int(key[1])
		var rise := float(key[3])
		var col: Color = key[6]
		if bool(key[7]):
			col = Color(1.7, 1.7, 1.5)  # struck: a flash, like the sprout's
		col.a = lerpf(1.0, COVER_ALPHA, float(key[5]))
		var src := Rect2(frame * TREE_SIZE.x, 0, TREE_SIZE.x, TREE_SIZE.y)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / PPU)
		if rise < 1.0:
			# rising out of the ground: the top `rise` of it shows, standing on the feet line
			var rows := roundf(TREE_FEET.y * rise)
			if rows > 0.0:
				draw_texture_rect_region(TREE, Rect2(-TREE_FEET.x, -rows, TREE_SIZE.x, rows),
					Rect2(src.position, Vector2(TREE_SIZE.x, rows)), col)
		else:
			draw_texture_rect_region(TREE, Rect2(-TREE_FEET, TREE_SIZE), src, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if rise >= 1.0 and dying < 0:
			var hp := float(pl.get("hp", 0.0))
			var hp_max := maxf(1.0, float(pl.get("hp_max", 1.0)))
			if hp < hp_max:
				# a short bar across the trunk's foot, like the sprout's
				var w := 16.0
				var y := -10.0
				draw_rect(Rect2(-w * 0.5 - 0.5, y - 0.5, w + 1.0, 2.0), C_BAR_BACK)
				var k := clampf(hp / hp_max, 0.0, 1.0)
				draw_rect(Rect2(-w * 0.5, y, roundf(w * k * PPU) / PPU, 1.0), C_BAR if k > 0.4 else C_BAR_LOW)
		var bob := int(key[2])
		if bob >= 0:
			var at := APPLE_AT + Vector2(0, -float(bob) * 0.5)
			draw_set_transform(at, 0.0, Vector2.ONE / PPU)
			var rim := PlantView.apple_rim()
			for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_texture(rim, -APPLE_FEET + d, C_APPLE_RIM)
			draw_texture(APPLE, -APPLE_FEET)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if bool(key[4]):  # a glint on its shoulder now and then
				var g := at + Vector2(-1.5, -4.0)
				draw_rect(Rect2(g, Vector2(0.5, 0.5)), Color.WHITE)
				draw_rect(Rect2(g + Vector2(-0.5, 0.5), Vector2(1.5, 0.5)), Color(1, 1, 1, 0.6))
