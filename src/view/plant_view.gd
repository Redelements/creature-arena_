class_name PlantView
extends Node2D
## Barkley's plants on the floor, drawn from `MatchSim.plants` (src/sim/plants.gd): a sprout
## swaying on its dirt patch (a small HP bar over it only once it's hurt, a flash and a
## shiver when it's struck), the tree it grows into rising out of the ground and swaying,
## and the apple bobbing at the tree's foot. Views only read the sim.
##
## Two depths: this node lies on the floor, under the fighters (main adds it after the
## shadows), and draws the trees' shadows along the map's light; `stand` (main puts it among
## the y-sorted entities) holds one `Plant` node per plant standing on its feet, so a
## fighter behind a tree is drawn behind it, and a tree over a fighter the local team sees
## turns see-through (`COVER_ALPHA`). A plant hides from a viewer who can't see its spot
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
## Ticks a struck sprout flashes and shivers.
const FLASH_TICKS := 8
## How see-through a tree is while it stands over a fighter the local team sees.
const COVER_ALPHA := 0.5
const C_BAR_BACK := Color(0.05, 0.06, 0.05, 0.75)
const C_BAR := Color("28b450")
const C_BAR_LOW := Color("e8c060")

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
		n.position = ArtScale.snap(Vector2(pl["pos"]), PPU)
		n.visible = _seen(pl)
		if float(pl["hp"]) < n.hp_seen:
			n.flash = FLASH_TICKS
		n.hp_seen = float(pl["hp"])
		if n.flash > 0:
			n.flash -= 1
		var key := _key(pl, n)
		if key != n.key:
			n.key = key
			n.queue_redraw()
		if int(pl["stage"]) == Plants.TREE and n.visible:
			shadow_key.append([id, key[1], key[3]])
	if shadows != null:
		shadow_key.append(shadows.light)
	for id in _nodes.keys():
		if not live.has(id):
			(_nodes[id] as Node).queue_free()
			_nodes.erase(id)
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
		return [0, _frame(id, SPROUT_FRAMES, SPROUT_TPF), int(ceilf(float(pl["hp"]))), shake, n.flash > 0]
	var rise := _rise(pl)
	var bob := int(_t / 20.0 + id) % 2 if bool(pl["apple"]) else -1
	var glint := bool(pl["apple"]) and int(_t + id * 7) % 90 < 6
	var tint := weather.prop_tint(Vector2(pl["pos"])) if weather != null else Color.WHITE
	return [1, _frame(id, TREE_FRAMES, TREE_TPF), bob, rise, glint, _covers(pl), tint]


func _frame(id: int, frames: int, tpf: int) -> int:
	return int(_t / float(tpf) + id * 3) % frames


## 0..1: how far a new tree has risen out of the ground (whole pixels of its height).
func _rise(pl: Dictionary) -> float:
	var since := float(int(pl["age"]) - int(pl["grow"]))
	return clampf(roundf(since / RISE_TICKS * TREE_SIZE.y) / TREE_SIZE.y, 0.0, 1.0)


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
		if not n.visible or n.key.is_empty() or int(n.key[0]) != 1 or float(n.key[3]) < 1.0:
			continue
		var region := Rect2(int(n.key[1]) * TREE_SIZE.x, 0, TREE_SIZE.x, TREE_SIZE.y)
		ShadowLayer.draw_silhouette(self, TREE, region, TREE_FEET, false, n.position, light["cast"],
			float(light["alpha"]), Vector2.ONE / PPU)


## One plant, standing on its feet among the fighters.
class Plant extends Node2D:
	var view: PlantView
	var pl: Dictionary = {}
	var key: Array = []
	var hp_seen := 0.0
	var flash := 0

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
		draw_set_transform(Vector2(shake, 0), 0.0, Vector2.ONE / PPU)
		draw_texture_rect_region(SPROUT, Rect2(-SPROUT_FEET, SPROUT_SIZE),
			Rect2(frame * SPROUT_SIZE.x, 0, SPROUT_SIZE.x, SPROUT_SIZE.y), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
		if bool(key[5]):
			col.a = COVER_ALPHA
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
		var bob := int(key[2])
		if bob >= 0:
			var at := APPLE_AT + Vector2(0, -float(bob) * 0.5)
			draw_set_transform(at, 0.0, Vector2.ONE / PPU)
			draw_texture(APPLE, -APPLE_FEET)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if bool(key[4]):  # a glint on its shoulder now and then
				var g := at + Vector2(-1.5, -4.0)
				draw_rect(Rect2(g, Vector2(0.5, 0.5)), Color.WHITE)
				draw_rect(Rect2(g + Vector2(-0.5, 0.5), Vector2(1.5, 0.5)), Color(1, 1, 1, 0.6))
