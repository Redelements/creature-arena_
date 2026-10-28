extends TestCase
## The Stadium's hand dressing (assets/arenas/stadium_dressing.tscn; assets/README.md
## "Dressing"): floor only, since the map has no wall or fence cells for a prop to stand on.
## Ragged darker, paler and damp dirt patches, worn lanes and dust round the starting marks,
## pebbles and the odd dried sprig, all flat, on plain floor and clear of the court lines.

const BT := preload("res://tools/build_tiles.gd")
const MAP := "stadium"
const DRESSING := "res://assets/arenas/stadium_dressing.tscn"
const GROUND := "res://assets/arenas/stadium.tscn"
const LAYERS := ["DirtDark", "DirtDry", "Damp", "Paths"]


func _grid() -> TerrainGrid:
	var map := ArenaMap.get_map(MAP)
	var size := ArenaMap.size_of(map)
	var grid := TerrainGrid.new(size.x, size.y)
	grid.load_map(map)
	return grid


func test_the_ground_scene_instances_the_dressing() -> void:
	assert_eq(String(ArenaMap.get_map(MAP)["tiles"].get("dressing", "")), DRESSING, "the map names its dressing scene")
	var root: Node = (load(GROUND) as PackedScene).instantiate()
	var d := root.get_node_or_null("Walls/Dressing") as Node2D
	assert_true(d != null, "the built scene carries the dressing")
	assert_eq(d.scene_file_path, DRESSING, "as an instance of the hand-edited scene, not a copy")
	for n in LAYERS + ["Flat", "Detail"]:
		assert_eq((d.get_node(n) as Node2D).position, Vector2.ZERO, "%s sorts at y 0, under everything" % n)
	root.free()


func test_floor_only_and_flat() -> void:
	var grid := _grid()
	var d: Node = (load(DRESSING) as PackedScene).instantiate()
	assert_eq(d.get_node("Props").get_child_count(), 0, "no props: nothing stands on the floor")
	assert_eq(d.get_node("Canopies").get_child_count(), 0, "nothing hangs over it")
	for n in LAYERS:
		var layer := d.get_node(n) as TileMapLayer
		assert_true(layer.get_used_cells().size() >= 8, "%s laid (%d tiles)" % [n, layer.get_used_cells().size()])
		for t in layer.get_used_cells():
			for dy in 2:
				for dx in 2:
					assert_eq(grid.get_base(t * 2 + Vector2i(dx, dy)), TerrainGrid.INTACT, "%s tile on the floor: %s" % [n, t])
	var detail := d.get_node("Detail") as TileMapLayer
	assert_true(detail.get_used_cells().size() >= 30, "pebbles and sprigs (%d)" % detail.get_used_cells().size())
	for c in detail.get_used_cells():
		assert_eq(grid.get_base(c), TerrainGrid.INTACT, "detail on plain floor: %s" % c)
		assert_false(BT.near_marks(c, grid), "detail clear of the court lines: %s" % c)
	d.free()


func test_the_lanes_run_between_the_marks_and_the_centre() -> void:
	var paths := (load(DRESSING) as PackedScene).instantiate()
	var used: Array = (paths.get_node("Paths") as TileMapLayer).get_used_cells()
	# tiles of 16 units: the starting marks at x 15 and 27, the centre at 21, all on row 8-9
	for t in [Vector2i(15, 8), Vector2i(18, 8), Vector2i(21, 9), Vector2i(24, 8), Vector2i(27, 9)]:
		assert_true(t in used, "worn ground at tile %s" % t)
	paths.free()
