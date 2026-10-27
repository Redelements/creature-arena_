extends TestCase
## Twin Keeps alive (GladeView, the arena JSON `ambient.glades`; AmbientView's butterflies):
## leaf shade under the crowns that follows the Lighting tier (none Off, still on Low), sun
## shafts by day, fireflies and a warm glow at sunset only, leaves off the crowns, smoke off
## the lamps, spray at the waterfall, ripples; nothing spawns under the HUD or on a wall or
## fence; the red keep's side wears red, the blue keep's blue.

const MAP := "twin_keeps"


func _setup() -> Array:
	var was: String = MatchFactory.arena
	MatchFactory.arena = MAP
	var sim := MatchFactory.versus("cairn", "culvert")
	MatchFactory.arena = was
	var v := ArenaView.new()
	v.ground = "grass"
	v.arena_id = MAP
	v.set_terrain(sim.terrain)
	var g := GladeView.new()
	g.set_sim(sim, v.canopy_rects())
	for c in sim.creatures:
		c.pos = Vector2(-900, -900)  # out of the way: nothing scatters
	return [sim, v, g]


func _free(r: Array) -> void:
	(r[1] as ArenaView).free()
	(r[2] as GladeView).free()


func test_fireflies_come_out_at_sunset_only() -> void:
	var r := _setup()
	var g: GladeView = r[2]
	g.set_look("day", Light2DView.Tier.HIGH)
	assert_eq(g.firefly_count(), 0, "none by day")
	g.set_look("sunset", Light2DView.Tier.HIGH)
	assert_gt(g.firefly_count(), 8, "a swarm round the glades at sunset")
	g.set_look("sunset", Light2DView.Tier.OFF)
	assert_gt(g.firefly_count(), 0, "critters, not light: still there with Lighting Off")
	g.set_look("day", Light2DView.Tier.LOW)
	assert_eq(g.firefly_count(), 0, "and gone again by day")
	_free(r)


func test_nothing_spawns_under_the_hud_or_on_a_wall_or_fence() -> void:
	var r := _setup()
	var sim: MatchSim = r[0]
	var v: ArenaView = r[1]
	var g: GladeView = r[2]
	var crowns := v.canopy_rects()
	g.hud_rects = [crowns[0].grow(30.0), crowns[1].grow(30.0)]  # out of a tree, world px are screen px
	g.set_look("sunset", Light2DView.Tier.HIGH)
	for i in 900:
		g.advance()
	assert_gt(g.firefly_count(), 0, "fireflies out")
	var spots: Array = g.fireflies() + g.leaves()
	assert_gt(spots.size(), g.firefly_count(), "and leaves falling from the crowns")
	var t := sim.terrain
	for p: Vector2 in spots:
		assert_false(g.under_hud(p), "nothing under the HUD: %s" % p)
		var c := Vector2i(floori((p.x - SimDefs.GRID_X) / SimDefs.CELL), floori((p.y - SimDefs.GRID_Y) / SimDefs.CELL))
		var b := t.map_base[c.y * t.cols + c.x]
		assert_true(b != TerrainGrid.WALL and b != TerrainGrid.FENCE, "nothing on a wall or fence: %s" % c)
	assert_gt(g.smoke_count(), 0, "smoke off the lamps")
	_free(r)


func test_the_leaf_shade_follows_the_lighting_tier() -> void:
	var r := _setup()
	var g: GladeView = r[2]
	g.set_look("day", Light2DView.Tier.HIGH)
	assert_gt(g.pool_count(), 20, "dappled shade under the crowns on High")
	g.set_look("day", Light2DView.Tier.LOW)
	assert_gt(g.pool_count(), 0, "still there on Low (it just doesn't drift)")
	g.set_look("day", Light2DView.Tier.OFF)
	assert_eq(g.pool_count(), 0, "none with Lighting Off")
	_free(r)


func test_the_red_keep_wears_red_and_the_blue_keep_blue() -> void:
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles/keeps_manifest.json"))
	var per := 2
	var kinds: Dictionary = man["scatter"]["kinds"]
	var red: Array = kinds["flowers_red"].map(func(a): return Vector2i(int(a[0]), int(a[1])) * per)
	var blue: Array = kinds["flowers_blue"].map(func(a): return Vector2i(int(a[0]), int(a[1])) * per)
	var d: Node = (load("res://assets/arenas/twin_keeps_dressing.tscn") as PackedScene).instantiate()
	var detail := d.get_node("Detail") as TileMapLayer
	var n_red := 0
	var n_blue := 0
	for c in detail.get_used_cells():
		var at := detail.get_cell_atlas_coords(c)
		if at in red:
			n_red += 1
			assert_lt(c.x, 75, "red flowers on the red (left) keep's half: %s" % c)
		elif at in blue:
			n_blue += 1
			assert_gt(c.x, 74, "blue flowers on the blue (right) keep's half: %s" % c)
	assert_gt(n_red, 20, "red flowers round the red keep (%d)" % n_red)
	assert_eq(n_red, n_blue, "as many blue round the blue keep")
	# the cloth and flags follow the braziers: red left, blue right; the middle wears none
	for p: Node2D in d.get_node("Props").get_children():
		var k := String(p.get_meta("kind", ""))
		var x := p.position.x / 2.0
		if k.ends_with("_red"):
			assert_lt(x, 600.0, "%s on the red keep's side" % p.name)
		elif k.ends_with("_blue"):
			assert_gt(x, 600.0, "%s on the blue keep's side" % p.name)
		if k.ends_with("_red") or k.ends_with("_blue"):
			assert_true(x < 460.0 or x > 740.0, "%s: the middle stays neutral" % p.name)
	assert_true(Light2DView.lamps_by_day(ArenaMap.get_map(MAP), "day"), "the red keep's braziers stay red (test_tiles_keeps)")
	d.free()
