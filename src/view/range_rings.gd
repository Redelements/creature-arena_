class_name RangeRings
extends Node2D
## "Range rings" (Settings > Controls, or F7 in a fight): thin floor rings that show where
## an attack really reaches, so a whiff reads as out of range. A readability aid, not the
## F1 overlay: no labels, no state, one colour per fighter.
##
## - A move's active segment: a ring centred on `hit_center(seg)`, radius
##   `hit_radius(seg) + BODY_PAD` (where a foe's centre has to be; the sim adds the foe's
##   own radius, BODY_PAD is a standard body). It fades over FADE_TICKS once the segment
##   ends. Each segment of a multi-hit move gets its own.
## - A projectile: `radius + BODY_PAD` around it; a lob (it only hits when it bursts):
##   `burst + BODY_PAD` around where it will land.
## - A very faint ring of each fighter's own `radius` under its feet.
## Nothing shows for a fighter the local team can't see (FxView.shown: brush, walls,
## fences), nor a shot or a lob's landing spot out of its line of sight (FxView.sight_to),
## so the rings never give a hidden foe away.
## True circles on the floor (no y squash), so the reach reads the same in every
## direction. Reads the sim, never writes it; main calls advance() each tick and sits it
## under the fighters.

const BODY_PAD := 10.0
const FADE_TICKS := 6
const ALPHA := 0.8
const PROJ_ALPHA := 0.55
const BODY_ALPHA := 0.3
const WIDTH := 1.0
## The fighter's colour, lightened so it reads on dirt, grass and concrete alike, over a
## faint dark stroke one pixel wider.
const LIGHTEN := 0.35
const SHADOW := Color(0, 0, 0, 0.3)

var sim: MatchSim
## Main's relation per creature ("self", "ally", "enemy", "side"): a stealthed foe's body
## ring stays hidden like its overhead bar.
var rel: Array = []
## Main's FxView, for what the local team sees (null: everything shows).
var fx: FxView = null
var _rings := {}  ## "id:seg" -> {center, radius, color, age (ticks since it ended)}


func set_sim(s: MatchSim) -> void:
	sim = s
	_rings.clear()
	queue_redraw()


## One tick: rings for the segments active now, older ones fade.
func advance() -> void:
	if sim == null:
		return
	var live := {}
	for c in sim.creatures:
		var seg := c.active_seg()
		if seg < 0:
			continue
		var key := "%d:%d" % [c.id, seg]
		live[key] = true
		_rings[key] = {"center": c.hit_center(seg), "radius": c.hit_radius(seg) + BODY_PAD,
			"color": colour_of(c), "age": 0}
	for key in _rings.keys():
		if live.has(key):
			continue
		_rings[key]["age"] = int(_rings[key]["age"]) + 1
		if int(_rings[key]["age"]) > FADE_TICKS:
			_rings.erase(key)
	queue_redraw()


static func colour_of(c: CreatureSim) -> Color:
	return Color(String(c.def.get("fx_color", "#ffcf3f"))).lightened(LIGHTEN)


## The rings to draw now, as [center, radius, color]: what _draw uses, and what tests read.
func rings() -> Array:
	var out: Array = []
	if sim == null:
		return out
	for c in sim.creatures:
		if c.state == CreatureSim.State.KO or _hidden(c):
			continue
		out.append([c.pos, c.radius, Color(colour_of(c), BODY_ALPHA)])
	for key in _rings:
		var r: Dictionary = _rings[key]
		var who := int(String(key).get_slice(":", 0))
		if who < sim.creatures.size() and _hidden(sim.creatures[who]):
			continue
		var fade := 1.0 - float(r["age"]) / float(FADE_TICKS + 1)
		out.append([r["center"], r["radius"], Color(r["color"], ALPHA * fade)])
	for pr in sim.projectiles:
		var owner_id := int(pr.get("owner", 0))
		var col := colour_of(sim.creatures[owner_id]) if owner_id < sim.creatures.size() else Color.WHITE
		if bool(pr.get("lob", false)):
			var fr := SimDefs.floor_rect()  # a lob stops at the wall (MatchSim._step_projectiles)
			var land: Vector2 = (Vector2(pr["pos"]) + Vector2(pr["vel"]) * float(pr["life"])).clamp(
				fr.position + Vector2(4, 4), fr.end - Vector2(4, 4))
			if fx == null or fx.sight_to(land):
				out.append([land, float(pr.get("burst", 0.0)) + BODY_PAD, Color(col, PROJ_ALPHA)])
		elif fx == null or fx.sight_to(pr["pos"]):
			out.append([pr["pos"], float(pr["radius"]) + BODY_PAD, Color(col, PROJ_ALPHA)])
	return out


func _hidden(c: CreatureSim) -> bool:
	if fx != null and not fx.shown(c):
		return true
	if c.stealth <= 0:
		return false
	var r := String(rel[c.id]) if c.id < rel.size() else "side"
	return r != "self" and r != "ally"


func _draw() -> void:
	for r in rings():
		var radius := float(r[1])
		var col: Color = r[2]
		var points := maxi(24, int(radius * 0.75))
		draw_arc(r[0], radius, 0.0, TAU, points, Color(SHADOW, SHADOW.a * col.a), WIDTH + 1.0, false)
		draw_arc(r[0], radius, 0.0, TAU, points, col, WIDTH, false)
