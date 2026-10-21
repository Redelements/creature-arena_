class_name FxView
extends Node2D
## Cosmetic effects. Two things drive them:
##
##   - Simulation events (hits, slams, grabs, falls, KOs...), passed in through spawn().
##   - A per-frame watch over every creature that notices move starts, strikes, charging,
##     dashes, Cairn's stones and knockouts. It reads the "fx" block of the move being
##     performed and the "ko_fx" block of the creature, both in data/creatures/*.json,
##     so a new creature gets effects by adding data, not code.
##
## Nothing here feeds back into the simulation, so it is free to use randomness, and
## replays and tests are unaffected. Effects draw in two layers: this node, above the
## fighters, and `ground` (an FxGround), below them.
##
## Move "fx" keys:
##   smear        "thrust" | "arc" | "rise" | "flurry"  a swipe drawn on each strike
##   size         smear scale (default 1)
##   charge       "pebbles" | "drips"                  while a heavy is held
##   afterimage   [from, to]   ghost trail during those ticks of the move
##   ghost_color  tint of the afterimages
##   trail        "gravel"     debris kicked up during the afterimage window
##   suction      true         air pulled into the mouth during startup
##   impact       "spire" | "geysers"                   on the move's last strike
##   speedlines   true         anime speed lines while the move is active
##   rain         true         a downpour and darkened arena
##   telegraph    true         marks where a leaping move will land
##   projectile   "wave"       draws the move's projectile as water
##   impact       also "lash" (stone chips), "quake" (a stomp's shockwave),
##                "avalanche" (boulders raining onto the strike), "leaves" (a burst of
##                leaves), "twister" (a gust of leaves on a spin's last hit), "roots"
##                (roots shooting up out of the floor in a ring on every hit)
##   charge       also "leaves": leaves gather and circle while the heavy is held
##   spin         true         leaves and wind arcs whirl around a spinning move
##   projectile   also "pinecone": a lobbed pinecone with a shadow and a landing mark
##   impact       also "splash" (a ring of water and drops), "droplets" (a small spray),
##                "bellyflop" (a huge splash where a leap comes down)
##   trail        also "splash": drops kicked up behind a dash
##   cast         true         a fishing line out to the thrown rod, then taut to whoever it
##                             hooked while it reels the attacker in to them
##   projectile   also "rod": a thrown rod spinning end over end
##   projectile   also "knife" (a small knife, point first), "mallet" and "cleaver" (spinning
##                end over end); the projectile's "move" picks which move's fx it uses
##   charge       also "psychic": violet sparks drawn in toward the brain while held
##   impact       also "tenderize": a mallet thump, meat-mallet tooth marks on the floor
##   flip         true         a spatula arc and "FLIP!" when the move's grab lands
##   chop         true         "CHOP CHOP!" when the move starts (Chef Cerebro's voice line)
##   telegraph_line true       a dotted line on the floor ahead, as far as the throw reaches
##   shout        {"text", "sound"}  a voice line over the head when the move starts
##   charge       also "venom": green venom drips and bubbles while the heavy is held
##   projectile   also "venom": a glob of green venom with a dripping trail
##   gaze         true         a glow in her eyes, and a faint beam to each foe it slows
##   impact       also "petrify": a ring of grey dust where the punch lands
##   charge       also "dirt": dirt kicked up behind while the heavy is held
##   impact       also "popup" (dirt bursting up where it hits) and "cavein" (the floor
##                caves in: rocks falling, dust, a shake)
##   flash        true         a blaze of light fanning out ahead (Headlamp Flash)
##   burrow       true         a dirt mound's trail of clods while the move tunnels
##   charge       also "coins": coins spilling from the bag while the heavy is held
##   impact       also "cash": coins and bills burst out where it hits
##   smoke        true         a puff of smoke as the move starts (and where a blink lands)
##   steal        true         coins fly from the foe to the attacker when it steals
##   impact       also "frost" (a puff of ice sparkles) and "blast" (a ring of ice bursting
##                out all round, shards and a shake)
##   charge       also "frost": icy mist swirling while the heavy is held
##   spray        true         a fan of ice shards over the move's cone
##   wave_cone    true         a fan of water over the move's cone (Runoff)
##   slush        true         a slushy trail behind a dash
##   syrup        true         a splash as the move's zone is left (the zone itself is drawn
##                             from sim.zones, as a syrup puddle)
## Creature "ko_fx" keys: style "scatter" (the sprite breaks into horizontal pieces that
## tumble across the floor: "pieces" [[y0, y1], ...] head first, in side-sheet frame
## pixels, from "frame" [row, col]; without "pieces", four even bands of the figure), "crack" (cracks, water gushing out, rubble), "crumble"
## (cracks, then the neck stones burst loose) or "timber" (a felled tree: "TIMBER!",
## leaves shaken loose, and a dust line where the trunk hits the floor) or "flop" (a
## last wet flop and a puddle) or "deflate" (the brain fizzles out with a puff of steam and
## its sunglasses skid away) or "hiss" (a last long hiss: green puffs and her hair
## snakes' venom dripping) or "dirt" (a puff of dust and clods as he flops over) or
## "cash" (the bag bursts: bills flutter down, coins roll away) or "melt" (he melts into a
## puddle of syrup and slush).
## Status drawn from creature state: Stoneskin plates while `shield` > 0, a rooted ring
## while armored, pebbles at the feet while slowed, a red "!" while taunted, and a pink
## down-arrow while tenderized (taking extra damage), green bubbles while poisoned,
## spinning stars while blinded, and rubble round the feet while rooted
## (a petrified statue's grey is CreatureView's shader).

const SHEET := preload("res://assets/sprites/fx.png")
const CARAVAN := preload("res://assets/sprites/caravan.png")  ## 4 frames of 48x40 (tools/gen_arenas.py)
const FLAG := preload("res://assets/sprites/flag.png")  ## 4 frames of 12x10 white cloth, tinted
const GRAVITY := 0.2
const FOREVER := 1.0e9

const C_OUTLINE := Color("1b1e26")
const C_WATER := Color("549cd0")
const C_WATER_L := Color("a8d6f0")
const C_FOAM := Color("e8f4fa")
const C_CON: Array[Color] = [Color("5d6470"), Color("8a909a"), Color("b8bcc2")]
const C_STONE: Array[Color] = [Color("706250"), Color("94846c"), Color("b2a38a")]
const C_STACK: Array[Color] = [Color("94846c"), Color("78818c"), Color("626876")]
const C_HEAD := Color("aea89d")
const C_PEBBLE: Array[Color] = [Color("605c56"), Color("827c74")]
const C_CRACK := Color("28221e")
const C_SPARK: Array[Color] = [Color("fff6d5"), Color("ffd04a"), Color("ff8a3a")]
const C_DIM := Color(0.02, 0.03, 0.07)
const C_PARRY := Color("9ee6ff")
const C_WARN := Color(1.0, 0.36, 0.28)
const C_GREY: Array[Color] = [Color("5a585c"), Color("7f7f7f"), Color("aaa8a6"), Color("cecccb")]
const C_CRAG: Array[Color] = [Color("8c4547"), Color("b5665f"), Color("d08c84")]
const C_AMBER := Color("ffc45c")
const C_TAUNT := Color("ff4a3a")
const C_LEAF: Array[Color] = [Color("16784a"), Color("28b450"), Color("96dcaa")]
const C_WOOD: Array[Color] = [Color("623736"), Color("804846"), Color("a0625c"), Color("b56664")]
const C_CONE: Array[Color] = [Color("603820"), Color("966034"), Color("c48c54")]
const C_PSY := Color("d58cff")
const C_TONGUE := Color("c45c6e")
const C_TONGUE_L := Color("e2828f")
## How high Chef Cerebro's thrown kitchen flies: from over his floating brain.
const THROW_Z := 18.0
const C_TENDER := Color("ff8fa3")
const C_MALLET: Array[Color] = [Color("8c4c48"), Color("b07a70")]
const C_BRAIN: Array[Color] = [Color("d6606a"), Color("f88686"), Color("ffb2aa")]
const C_VENOM: Array[Color] = [Color("3f8a2a"), Color("7fd64e"), Color("c8f59a")]
const C_GAZE := Color("fff27a")
const C_DIRT: Array[Color] = [Color("56391f"), Color("7a5634"), Color("9c744c")]
const C_LAMP := Color("fff6b0")
const C_GOLD: Array[Color] = [Color("c89a1e"), Color("f2c94c"), Color("fff0a0")]
const C_CASH: Array[Color] = [Color("3f8f3f"), Color("7fd67f")]
const C_ICE: Array[Color] = [Color("64bad0"), Color("a8eef8"), Color("f0fcff")]
const C_SYRUP: Array[Color] = [Color("f0d21e"), Color("e8303a"), Color("46c846")]
const C_BLEED: Array[Color] = [Color("7a0e1c"), Color("cc2a3a"), Color("ff7f86")]

## Asks AudioView for a sound that belongs to a timed effect (a KO scatter, geysers...).
signal cue(sound: String)

var sim: MatchSim
var views: Array = []  ## CreatureView per creature, same order as sim.creatures
var ground: FxGround
var time_scale := 1.0  ## main slows this for KO slow-motion; 0 holds everything still
var shake_out := 0.0  ## extra screen shake asked for by effects; main takes it each frame

var _parts: Array[Dictionary] = []
var _incoming: Array[Dictionary] = []
var _font: Font = ThemeDB.fallback_font
var _tick := 0
var _watch := {}
var _last_push := {}
var _dark := 0.0
var _rain := 0.0
var _slowed_text := {}
## Set by main: per side, {"color", "label"} for the marker over its fighter.
var side_marks: Array = []  ## creature id -> tick its last "SLOWED" call-out showed
## Set by main each tick (Vision): per fighter slot, true when the local team can't see
## it. Its bar, aim mark, telegraphs, status icons and particles aren't drawn, and its
## events show nothing unless someone seen was in them too. `viewer_team` is that team
## (-1: nobody's, everything shows); `vision` answers sight to points (projectiles).
var unseen: Array = []
var viewer_team := -1
var vision: Vision = null
## Slot -> the "lost" mark left where the local team last saw a fighter that went out of
## sight: a faint ring and a question mark for LOST_TICKS, gone if it's seen again.
var _lost := {}
var _was_hidden: Array = []
const LOST_TICKS := 60.0


func bind_ground(g: FxGround) -> void:
	ground = g
	ground.painter = _paint.bind(true)


func clear() -> void:
	_parts.clear()
	_lost.clear()
	_was_hidden = []
	_trail.clear()
	pads.clear()
	zone = {}
	_incoming.clear()
	_watch.clear()
	_last_push.clear()
	_dark = 0.0
	_rain = 0.0
	time_scale = 1.0
	shake_out = 0.0
	queue_redraw()


# ------------------------------------------------------------------ events

func spawn(e: Dictionary) -> void:
	if not _event_shown(e):
		return  # it happened out of the local team's sight
	var p: Vector2 = e["pos"]
	var power: float = e["power"]
	match String(e["type"]):
		"hit":
			var big := power >= 9.0 or bool(e.get("heavy", false))
			_add({"kind": "spark", "pos": p, "life": 12 if big else 8, "scale": 2.0 if big else 1.0})
			var push := _note_push(e)
			if big:
				_add({"kind": "lines", "pos": p, "life": 8, "size": 1.4 if power >= 14.0 else 1.0, "color": C_SPARK[0]})
			for i in (6 if big else 3):
				_px(p, push.rotated(randf_range(-0.7, 0.7)) * randf_range(1.2, 2.8), C_SPARK[randi() % 3], 12)
			var col := Color("ffe08a")
			if float(e.get("variety", 1.0)) >= 1.5:
				col = Color("ff9a5a")
			elif float(e.get("variety", 1.0)) > 1.0:
				col = Color("ffd166")
			if bool(e.get("stale", false)):
				col = Color("b8b8b8")
			_text(p + Vector2(0, -6), str(int(round(power))), col)
		"block":
			_add({"kind": "spark", "pos": p, "life": 6, "scale": 0.75})
			_add({"kind": "ring", "pos": p + Vector2(0, 4), "life": 8, "radius": 10.0, "color": Color("9ec5ff")})
			_text(p + Vector2(0, -6), "BLOCK", Color("9ec5ff"))
		"guard_break":
			_add({"kind": "lines", "pos": p + Vector2(0, -16), "life": 10, "size": 1.3, "color": Color("ff9a5a")})
			for i in 8:
				_px(p + Vector2(0, -16), Vector2.from_angle(randf() * TAU) * randf_range(1.0, 2.5), Color("9ec5ff"), 16)
			# Out of stamina ("drained"): the guard only drops, so it says why.
			_text(p + Vector2(0, -34), "EXHAUSTED" if bool(e.get("drained", false)) else "GUARD BREAK", Color("ff9a5a"))
		"slam":
			var full := power >= 1.0
			_add({"kind": "ring", "pos": p, "life": 18 if full else 12, "radius": 34.0 if full else 18.0})
			var n := 10 if full else 6
			for i in n:
				var a := TAU * i / n + randf() * 0.3
				var r := (22.0 if full else 12.0) + randf() * 6.0
				_dust(p + Vector2(cos(a), sin(a)) * r, Vector2(cos(a), sin(a) * 0.5 - 0.6) * 0.5)
			_slam_debris(p, full)
		"bounce":
			_add({"kind": "spark", "pos": p + Vector2(0, -12), "life": 8, "scale": 1.0})
			_add({"kind": "lines", "pos": p + Vector2(0, -12), "life": 6, "size": 0.8, "color": C_SPARK[0]})
			_dust(p, Vector2(0, -0.4))
		"fall":
			for i in 4:
				_dust(p + Vector2(randf_range(-8, 8), randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.5))
			_later(CreatureSim.FALL_TICKS - 6, _pit_plume.bind(p))
		"land", "dodge":
			_dust(p + Vector2(0, 1), Vector2(0, -0.3))
		"ko":
			var who := int(e.get("who", -1))
			var styled: bool = who >= 0 and who < sim.creatures.size() \
				and not sim.creatures[who].def.get("ko_fx", {}).is_empty()
			_add({"kind": "spark", "pos": p + Vector2(0, -16), "life": 16, "scale": 1.5 if styled else 2.5})
			_add({"kind": "lines", "pos": p + Vector2(0, -16), "life": 14, "size": 2.0, "color": Color.WHITE})
		"slip":
			_add({"kind": "ring", "pos": p + Vector2(0, 20), "life": 14, "radius": 24.0, "color": C_PARRY})
			_add({"kind": "lines", "pos": p, "life": 10, "size": 1.3, "color": C_PARRY})
			for i in 6:
				_px(p, Vector2.from_angle(randf() * TAU) * randf_range(1.0, 2.2), Color.WHITE, 12)
			_text(p, "SLIP!", C_PARRY)
		"swallow":
			_swallow_fx(e)
		"poop":
			_poop_fx(e)
		"grab":
			if bool(e.get("flip", false)):
				_flip_out(e)
				return
			_text(p, "GULP!", Color("b6f28a"))
			if int(e.get("attacker", -1)) >= 0:
				var a := sim.creatures[int(e["attacker"])]
				var mouth := a.pos - a.facing * 6.0
				for i in 14:
					var v := (-a.facing).rotated(randf_range(-0.6, 0.6)) * randf_range(0.8, 2.2)
					_drop(mouth, 10.0, v, randf_range(0.8, 2.2), true)
		"windup":
			_windup_tell(e)
		"tag":
			# A tag: the partner swaps in with a burst of dust and a call-out.
			_add({"kind": "ring", "pos": p, "life": 16, "radius": 30.0, "color": Color("9ee6ff")})
			_add({"kind": "lines", "pos": p + Vector2(0, -18), "life": 10, "size": 1.2, "color": Color("9ee6ff")})
			for i in 8:
				var a := TAU * i / 8.0
				_dust(p + Vector2(cos(a) * 10.0, sin(a) * 4.0), Vector2(cos(a), sin(a) * 0.5 - 0.5) * 0.6)
			var label := "TAG CANCEL!" if String(e.get("kind", "")) == "cancel" else "TAG!"
			_text(p + Vector2(0, -44), label, Color("9ee6ff"), 9)
		"enter":
			_add({"kind": "ring", "pos": p, "life": 20, "radius": 34.0, "color": Color("ffd166")})
			for i in 6:
				_dust(p + Vector2(randf_range(-10, 10), randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.5))
			_text(p + Vector2(0, -46), String(e.get("name", "")).to_upper() + " IN", Color("ffd166"), 9)
		"breakaway":
			_add({"kind": "ring", "pos": p + Vector2(0, 16), "life": 16, "radius": 30.0})
			_text(p + Vector2(0, -10), "BREAKAWAY", Color("c9a7ff"))
		"projectile":
			var thrower := _creature(int(e.get("who", -1)))
			if bool(e.get("lob", false)) or (thrower != null and not _owner_has_wave(thrower)):
				return  # a pinecone or a rod just leaves the hand; it's drawn in flight
			# Runoff leaves the hand: a slap of water.
			var owner := _owner_near(p)
			var at := p + (owner.facing * 14.0 if owner != null else Vector2.ZERO)
			for i in 10:
				_drop(at, 2.0, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.2), randf_range(1.5, 3.0), true)
			_add({"kind": "ripple", "pos": at, "life": 20, "radius": 20.0})
			for i in 3:
				_dust(at + Vector2(randf_range(-6, 6), randf_range(-2, 2)), Vector2(randf_range(-0.3, 0.3), -0.4))
		"projectile_end":
			var owner_c := _creature(int(e.get("who", -1)))
			if owner_c != null and _owner_has_venom(owner_c):
				_venom_splat(p, 10.0, 8 if power >= 1.0 else 5)
				return
			if owner_c != null and not _owner_has_wave(owner_c):
				if power >= 1.0:
					_add({"kind": "spark", "pos": p, "life": 8, "scale": 1.0})
				return
			var n := 12 if power >= 1.0 else 6
			for i in n:
				_drop(p, 3.0, Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.4), randf_range(1.0, 2.6), true)
			_add({"kind": "ripple", "pos": p, "life": 18, "radius": 16.0})
		"armor":
			var tgt := _creature(int(e.get("target", -1)))
			_add({"kind": "spark", "pos": p, "life": 6, "scale": 0.8})
			_add({"kind": "ring", "pos": p + Vector2(0, 8), "life": 9, "radius": 12.0, "color": C_AMBER})
			if tgt != null:
				for i in 4:
					_chunk(tgt.pos, _chest(tgt), _note_push(e).rotated(randf_range(-1.2, 1.2)) * randf_range(0.5, 1.2),
						randf_range(1.0, 2.0), 2.0, C_GREY[randi() % 3], 30.0)
			_text(p + Vector2(0, -6), str(int(round(power))) if power >= 0.5 else "ROOTED", C_AMBER)
		"shield_up":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				var at := c.pos + Vector2(0, -_chest(c))
				_add({"kind": "ring", "pos": c.pos, "life": 14, "radius": c.radius + 10.0, "color": C_GREY[3]})
				for i in 8:
					_px(at + Vector2.from_angle(TAU * i / 8.0) * 16.0, -Vector2.from_angle(TAU * i / 8.0) * 0.8,
						C_GREY[3], 14)
				_text(c.pos + Vector2(0, -_top(c) - 8), "STONESKIN", C_GREY[3], 7, 34.0)
		"shield_break":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				for i in 9:
					_chunk(c.pos, _chest(c) + randf_range(-6, 6), Vector2.from_angle(randf() * TAU) * randf_range(0.6, 1.8),
						randf_range(1.2, 2.4), randf_range(2.0, 3.0), C_GREY[randi() % 3], 40.0)
				_add({"kind": "lines", "pos": c.pos + Vector2(0, -_chest(c)), "life": 8, "size": 1.0, "color": C_GREY[3]})
				_text(c.pos + Vector2(0, -_top(c) - 8), "SHIELD BROKEN", C_GREY[2], 7, 34.0)
		"slow":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				for i in 4:
					_dust(c.pos + Vector2(randf_range(-8, 8), randf_range(-2, 2)), Vector2(randf_range(-0.3, 0.3), -0.3))
				if _tick - int(_slowed_text.get(c.id, -999)) > 45:  # once, not on every slowing hit
					_slowed_text[c.id] = _tick
					_text(c.pos + Vector2(0, -_top(c) - 14), "SLOWED", Color("b9c6d6"), 7, 40.0)
		"taunt":
			_add({"kind": "ring", "pos": p, "life": 14, "radius": 18.0, "color": C_TAUNT})
		"sink_warn", "sink":
			# Sinkhole: dust shakes off the doomed ring, then the ring drops in a cloud.
			var rect: Rect2 = e.get("rect", Rect2())
			var n := 10 if String(e["type"]) == "sink" else 5
			for i in n:
				var side := i % 4
				var f := float(i / 4) / float(maxi(1, n / 4))
				var q: Vector2
				match side:
					0: q = Vector2(rect.position.x + rect.size.x * f, rect.position.y)
					1: q = Vector2(rect.position.x + rect.size.x * f, rect.end.y)
					2: q = Vector2(rect.position.x, rect.position.y + rect.size.y * f)
					_: q = Vector2(rect.end.x, rect.position.y + rect.size.y * f)
				_add({"kind": "lines", "pos": q, "life": 14 if n > 5 else 8, "size": 1.3, "color": C_GREY[2]})
		"smash":
			# A charge breaks through rubble: a burst of grey chips.
			_add({"kind": "ring", "pos": p, "life": 10, "radius": 12.0, "color": C_GREY[2]})
			_add({"kind": "lines", "pos": p + Vector2(0, -8), "life": 12, "size": 1.4, "color": C_GREY[3]})
		"ram_wall":
			# Landslide Ram meets the arena wall: a jolt of dust and stone chips.
			_add({"kind": "ring", "pos": p, "life": 12, "radius": 14.0, "color": C_AMBER})
			_add({"kind": "lines", "pos": p + Vector2(0, -10), "life": 10, "size": 1.2, "color": C_AMBER})
		"roar":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				_add({"kind": "ring", "pos": c.pos, "life": 20, "radius": power, "color": C_TAUNT})
				_add({"kind": "ring", "pos": c.pos, "life": 14, "radius": power * 0.6, "color": C_AMBER})
				_add({"kind": "lines", "pos": c.pos + Vector2(c.facing.x * 12.0, -_top(c) + 10), "life": 12, "size": 1.3,
					"color": C_AMBER})
				_text(c.pos + Vector2(0, -_top(c) + 2), "BEDROCK!", C_AMBER, 9, 40.0)
				_slam_debris(c.pos, false)
				shake_out = maxf(shake_out, 2.0)
		"hook":
			# Gulp's tongue lands: it snaps back to Culvert, dragging the target along.
			var a := _creature(int(e.get("attacker", -1)))
			var tgt := _creature(int(e.get("target", -1)))
			if a != null and tgt != null:
				var from := tgt.pos + Vector2(0, -_chest(tgt))
				var to := a.pos + a.facing * 10.0 + Vector2(0, -_chest(a) + 2.0)
				_add({"kind": "streak", "a": from, "b": to, "life": 7, "color": C_TONGUE})
				_text(tgt.pos + Vector2(0, -_top(tgt) - 10), "HOOKED!", C_TONGUE_L, 8, 44.0)
				for i in 4:
					_px(from, (to - from).normalized() * randf_range(1.0, 2.0) + Vector2(randf_range(-0.5, 0.5), -0.5),
						C_TONGUE_L, 10)
		"pull":
			# Branch Grab snags: a streak back toward Barkley and a few leaves torn off.
			var a := _creature(int(e.get("attacker", -1)))
			var tgt := _creature(int(e.get("target", -1)))
			if a != null and tgt != null:
				var from := tgt.pos + Vector2(0, -_chest(tgt))
				var to := a.pos + Vector2(0, -_chest(a))
				for i in 5:
					var off := Vector2(randf_range(-4, 4), randf_range(-5, 5))
					_add({"kind": "streak", "a": from + off, "b": from.lerp(to, 0.5) + off, "life": 10,
						"color": Color(C_WOOD[3], 0.8)})
				_leaves(from, 6, 1.4)
				_text(from + Vector2(0, -14), "SNAG!", C_LEAF[2], 8, 34.0)
		"burst":
			_pinecone_burst(p, power)
		"reel":
			var a := _creature(int(e.get("attacker", -1)))
			var tgt := _creature(int(e.get("target", -1)))
			if a != null and tgt != null:
				var at := tgt.pos + Vector2(0, -_chest(tgt))
				_text(at + Vector2(0, -12), "HOOKED!", C_WATER_L, 8, 34.0)
				for i in 6:
					_drop(at + Vector2(0, 10), 10.0, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0),
						randf_range(1.0, 2.0), false)
		"tenderized":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				_text(c.pos + Vector2(0, -_top(c) - 14), "TENDERIZED", C_TENDER, 7, 44.0)
		"projectile_pierce":
			_add({"kind": "spark", "pos": p, "life": 6, "scale": 0.8})
		"punishable":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				_text(c.pos + Vector2(0, -_top(c) - 14), "OPEN!", Color("ffb347"), 8, 36.0)
		"freeze":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				_add({"kind": "ring", "pos": c.pos, "life": 18, "radius": c.radius + 18.0, "color": C_ICE[2]})
				for i in 12:
					_px(c.pos + Vector2(randf_range(-10, 10), -randf_range(4, _top(c))),
						Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.2), C_ICE[randi() % 3], 20)
				_text(c.pos + Vector2(0, -_top(c) - 14), "FROZEN!", C_ICE[1], 9, 50.0)
				shake_out = maxf(shake_out, 2.5)
		"zone":
			for i in 10:
				_drop(p, 6.0, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0), randf_range(0.8, 1.6), false,
					C_SYRUP[randi() % 3])
		"steal":
			var c := _creature(int(e.get("who", -1)))
			var by := _creature(int(e.get("by", -1)))
			if c != null and by != null:
				_text(c.pos + Vector2(0, -_top(c) - 14), "STOLEN!", C_GOLD[1], 8, 44.0)
				for i in 6:
					_add({"kind": "suck", "from": c.pos + Vector2(randf_range(-6, 6), -_chest(c) + randf_range(-6, 6)),
						"to": by.pos + Vector2(0, -_chest(by)), "life": 14, "color": C_GOLD[1]})
		"warp":
			# Chef Cerebro's teleport: his mind folds space; a flash where he left and
			# where he lands, with sparks drawn in and thrown out.
			var c := _creature(int(e.get("who", -1)))
			var lift := _chest(c) if c != null else 16.0
			var from: Vector2 = e.get("from", p)
			_warp_flash(from + Vector2(0, -lift), false)
			_warp_flash(p + Vector2(0, -lift), true)
			_add({"kind": "streak", "a": from + Vector2(0, -lift), "b": p + Vector2(0, -lift), "life": 5,
				"color": Color(C_PSY, 0.45)})
		"blink":
			_smoke(p, 8)
			var from: Vector2 = e.get("from", p)
			_smoke(from, 5)
		"blinded":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				_add({"kind": "lines", "pos": c.pos + Vector2(0, -_chest(c)), "life": 10, "size": 1.2, "color": C_LAMP})
				_text(c.pos + Vector2(0, -_top(c) - 14), "BLINDED", C_LAMP, 7, 44.0)
		"miss":
			_text(p + Vector2(0, -6), "MISS", Color("b8b8b8"), 8, 36.0)
			for i in 3:
				_px(p, Vector2.from_angle(randf() * TAU) * 0.8, Color("d8d8d8"), 10)
		"rooted":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				_text(c.pos + Vector2(0, 14), "ROOTED", C_DIRT[2], 7, 44.0)
		"poisoned":
			var c := _creature(int(e.get("who", -1)))
			if c != null and String(e.get("look", "")) == "bleed":
				# A paper cut (Paper Shuriken): a red spatter and the word, no venom.
				for i in 6:
					_drop(c.pos, _chest(c), Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0), randf_range(0.6, 1.4),
						false, C_BLEED[randi() % 2])
				_text(c.pos + Vector2(0, 14), "BLEEDING", C_BLEED[2], 7, 44.0)
			elif c != null:
				var stacks := int(e.get("stacks", 0))
				_venom_splat(c.pos, _chest(c), 10 if stacks <= 0 else 4 + 2 * stacks)
				# Under the feet, so it doesn't collide with a call-out over the attacker's head.
				# Frenzy stacks: the pips at its feet count them; words only for the first and the cap.
				var cap := int(_creature(int(e.get("by", -1))).def.get("venom_frenzy", {}).get("max_stacks", 5)) \
					if _creature(int(e.get("by", -1))) != null else 5
				if stacks <= 1:
					_text(c.pos + Vector2(0, 14), "POISONED", C_VENOM[2], 7, 44.0)
				elif stacks == cap:
					_text(c.pos + Vector2(0, 14), "POISON x%d!" % stacks, C_VENOM[1], 8, 44.0)
		"frenzy":
			# Hissy Fitz's Venom Frenzy starts: a hiss, a spray of venom, a call-out.
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				_venom_splat(c.pos, _chest(c), 16)
				_text(c.pos + Vector2(0, -_top(c) - 14), "VENOM FRENZY!", C_VENOM[1], 9, 50.0)
				_add({"kind": "ring", "pos": c.pos, "life": 16, "radius": 26.0, "color": C_VENOM[1]})
				_kick_view(c, Vector2(1.18, 0.86))
		"poison":
			var c := _creature(int(e.get("who", -1)))
			if c != null and String(e.get("look", "")) == "bleed":
				for i in 2:
					_drop(c.pos + Vector2(randf_range(-c.radius, c.radius), 0), randf_range(8.0, _chest(c)),
						Vector2(randf_range(-0.2, 0.2), 0), 0.0, false, C_BLEED[randi() % 2], Vector2(1, 2))
				_text(c.pos + Vector2(randf_range(-4, 4), -_top(c) - 4), str(snappedf(power, 0.1)).trim_suffix(".0"),
					C_BLEED[1], 7, 30.0)
			elif c != null:
				for i in 3:
					_bubble(c.pos + Vector2(randf_range(-c.radius, c.radius), 0), randf_range(6.0, _top(c) - 4.0))
				_text(c.pos + Vector2(randf_range(-4, 4), -_top(c) - 4), str(snappedf(power, 0.1)).trim_suffix(".0"),
					C_VENOM[1], 7, 30.0)
		"gaze":
			var c := _creature(int(e.get("who", -1)))
			var by := _creature(int(e.get("by", -1)))
			if c != null and by != null:
				var eyes := by.pos + Vector2(by.facing.x * 4.0, -_top(by) + 12.0)
				var at := c.pos + Vector2(0, -_chest(c))
				_add({"kind": "streak", "a": eyes, "b": at, "life": 8, "color": Color(C_GAZE, 0.55)})
				for i in 2:
					_px(at + Vector2(randf_range(-6, 6), randf_range(-8, 8)), Vector2(0, -0.2), C_GREY[3], 14)
				if power <= float(by.move_def().get("gaze", {}).get("min_mult", 0.0)) + 0.001 \
						and c.anim_t % 40 < 10:
					_text(c.pos + Vector2(0, -_top(c) - 14), "STONE COLD", C_GREY[3], 7, 30.0)
		"petrify":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				_add({"kind": "ring", "pos": c.pos, "life": 18, "radius": c.radius + 18.0, "color": C_GREY[3]})
				_add({"kind": "lines", "pos": c.pos + Vector2(0, -_chest(c)), "life": 12, "size": 1.4, "color": C_GREY[3]})
				for i in 10:
					_px(c.pos + Vector2(randf_range(-10, 10), -randf_range(4, _top(c))),
						Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.2), C_GREY[randi() % 4], 20)
				_text(c.pos + Vector2(0, -_top(c) - 14), "PETRIFIED!", C_GREY[3], 9, 50.0)
				shake_out = maxf(shake_out, 2.5)
		"shatter":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				var push := _note_push(e)
				for i in 12:
					var v := Vector2.from_angle(randf() * TAU) * randf_range(0.6, 2.0) + push * 0.6
					_chunk(c.pos, randf_range(4, _top(c)), v, randf_range(1.0, 2.4), randf_range(2.0, 3.5),
						C_ICE[randi() % 3] if bool(e.get("ice", false)) else C_GREY[randi() % 3], 50.0)
				for i in 5:
					_dust(c.pos + Vector2(randf_range(-10, 10), randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.4))
				_add({"kind": "lines", "pos": c.pos + Vector2(0, -_chest(c)), "life": 10, "size": 1.6, "color": Color.WHITE})
				_text(c.pos + Vector2(0, -_top(c) - 22), "SHATTER!", Color("ffd166"), 10, 50.0)
				shake_out = maxf(shake_out, 3.0)
		"land_hard":
			for i in 3:
				_dust(p + Vector2(randf_range(-6, 6), randf_range(-2, 2)), Vector2(randf_range(-0.3, 0.3), -0.4))


## A floating call-out (Combo Trials and drills: "CLEAR!", "DODGED!").
## Whether this fighter is drawn for the local team (Vision); everyone, with no local team.
func shown(c: CreatureSim) -> bool:
	if c == null:
		return true
	var i := c.id if c.id >= 0 and c.id < sim.creatures.size() and sim.creatures[c.id] == c \
		else sim.creatures.find(c)
	return i < 0 or i >= unseen.size() or not bool(unseen[i])


## Whether the local team has a clear line of sight to a point (a projectile, a lob's
## landing): fences and walls only.
func sight_to(p: Vector2) -> bool:
	return viewer_team < 0 or vision == null or vision.team_sight_to(sim, viewer_team, p)


## Event effects show when someone the local team sees took part (a hidden attacker's
## hit on a teammate still sparks). Shots, bursts and zones go by their spot instead.
const _EVENT_IDS := ["who", "attacker", "target", "by"]
func _event_shown(e: Dictionary) -> bool:
	if viewer_team < 0 or sim == null:
		return true
	var kind := String(e["type"])
	if kind in ["projectile_end", "projectile_pierce", "burst", "zone"]:
		return sight_to(Vector2(e["pos"]))
	var any := false
	for k in _EVENT_IDS:
		var v = e.get(k)
		if typeof(v) != TYPE_INT:
			continue  # ("by" is also a word in duel_over)
		var c := _creature(int(v))
		if c == null:
			continue
		any = true
		if shown(c):
			return true
	return not any


## Leaves a "lost" mark where a fighter went out of the local team's sight, and drops it
## once the fighter is seen again.
func _track_lost() -> void:
	var n := sim.creatures.size()
	if _was_hidden.size() != n:
		_was_hidden.resize(n)
		_was_hidden.fill(false)
	for i in n:
		var c := sim.creatures[i]
		var now := i < unseen.size() and bool(unseen[i])
		if now and not bool(_was_hidden[i]) and c.state != CreatureSim.State.KO and c.swallow_t <= 0:
			var mark := {"kind": "lost", "pos": c.pos, "life": LOST_TICKS, "top": _top(c), "r": c.radius}
			_lost[i] = mark
			_add(mark)
		elif not now and _lost.has(i):
			var mark: Dictionary = _lost[i]
			mark["life"] = 0.0
			_lost.erase(i)
		_was_hidden[i] = now


func callout(pos: Vector2, text: String, color: Color) -> void:
	_text(pos, text, color, 9, 60.0)


## A click marker for League-style orders: green for a move, red for an attack.
func ping(pos: Vector2, attack: bool) -> void:
	_add({"kind": "ping", "pos": pos, "life": 18, "attack": attack, "real": true})


# ------------------------------------------------------------------ per frame

func advance() -> void:
	_tick += 1
	var ts := time_scale
	if sim != null:
		_watch_all()
		_track_lost()
		if ts > 0.0:
			_projectile_spray()
	_parts.append_array(_incoming)
	_incoming.clear()

	var keep: Array[Dictionary] = []
	var ends: Array[Callable] = []
	for p in _parts:
		var dt: float = 1.0 if bool(p.get("real", false)) else ts
		if dt <= 0.0:
			keep.append(p)
			continue
		p["t"] = float(p["t"]) + dt
		if p.has("vz"):
			_physics(p, dt)
		elif p.has("orbit"):
			var oc := _creature(int(p["orbit"]))
			p["ang"] = float(p["ang"]) + float(p["spin"]) * dt
			if oc != null:
				var a := float(p["ang"])
				p["pos"] = oc.pos + Vector2(cos(a), sin(a) * 0.5) * float(p["r"])
		elif String(p["kind"]) == "px":
			p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * dt
			p["vel"] = Vector2(p["vel"]) + Vector2(0, 0.12 * dt)
		elif String(p["kind"]) == "emit":
			p["acc"] = float(p["acc"]) + dt
			while float(p["acc"]) >= float(p["every"]):
				p["acc"] = float(p["acc"]) - float(p["every"])
				var fn: Callable = p["fn"]
				fn.call(float(p["t"]) / float(p["life"]))
		if float(p["t"]) < float(p["life"]):
			keep.append(p)
		elif p.has("on_end"):
			ends.append(p["on_end"])
	_parts = keep
	for fn in ends:
		fn.call()
	_parts.append_array(_incoming)
	_incoming.clear()

	_dark = maxf(0.0, _dark - 0.01 * ts)
	_rain = maxf(0.0, _rain - ts)
	if _rain > 0.0:
		_dark = maxf(_dark, 0.35 * minf(1.0, _rain / 30.0))
	queue_redraw()
	if ground != null:
		ground.queue_redraw()


## Debris and water: a position on the floor plus a height `z` above it.
func _physics(p: Dictionary, dt: float) -> void:
	var vel: Vector2 = p["vel"]
	var z := float(p["z"]) + float(p["vz"]) * dt
	var vz := float(p["vz"]) - float(p.get("g", GRAVITY)) * dt
	var pos: Vector2 = p["pos"] + vel * dt
	if bool(p.get("walls", false)):
		var fr := (sim.floor_rect() if sim != null else SimDefs.floor_rect()).grow(-4.0)
		if pos.x < fr.position.x or pos.x > fr.end.x:
			vel.x = -vel.x * 0.5
			pos.x = clampf(pos.x, fr.position.x, fr.end.x)
		if pos.y < fr.position.y or pos.y > fr.end.y:
			vel.y = -vel.y * 0.5
			pos.y = clampf(pos.y, fr.position.y, fr.end.y)
	var grounded := false
	if z <= 0.0 and vz < 0.0:
		z = 0.0
		match String(p["kind"]):
			"drop":
				p["t"] = p["life"]
				if bool(p.get("pool", false)) and randf() < 0.3:
					_add({"kind": "puddle", "pos": pos, "radius": randf_range(1.5, 3.5), "ry": 0.45,
						"grow": 3.0, "life": 90.0, "fade": 40.0})
			_:
				if -vz > 0.9:
					vz = -vz * float(p.get("bounce", 0.35))
					vel *= 0.65
					p["vrot"] = float(p.get("vrot", 0.0)) * 0.6
					if float(p.get("size", 0.0)) >= 3.0 or p.has("piece"):
						_dust(pos, Vector2(randf_range(-0.2, 0.2), -0.3))
				else:
					vz = 0.0
					grounded = true
	elif z <= 0.0:
		grounded = true
	if grounded:
		vel *= pow(0.9, dt)
		if bool(p.get("roll", false)):
			var rot := float(p["rot"]) + vel.x * dt / float(p.get("radius", 5.0))
			if vel.length() < 0.35:
				# Rock back and forth, then settle on a flat side.
				var rest := roundf(rot / (PI * 0.5)) * PI * 0.5
				var vr := (float(p.get("vrot", 0.0)) + (rest - rot) * 0.12 * dt) * pow(0.86, dt)
				p["vrot"] = vr
				rot += vr * dt
			p["rot"] = rot
		elif p.has("rot"):
			var rot := float(p["rot"])
			p["rot"] = lerp_angle(rot, roundf(rot / PI) * PI, minf(1.0, 0.25 * dt))
		if vel.length() < 0.03:
			vel = Vector2.ZERO
	elif p.has("rot"):
		p["rot"] = float(p["rot"]) + float(p.get("vrot", 0.0)) * dt
	p["z"] = z
	p["vz"] = vz
	p["vel"] = vel
	p["pos"] = pos
	p["grounded"] = grounded


# ------------------------------------------------------------------ watching creatures

func _watch_all() -> void:
	for c in sim.creatures:
		var w: Dictionary = _watch.get(c.id, {})
		if not w.is_empty() and w.get("obj") != c:
			w = {}  # a different creature in this slot (Duel tag): start fresh
		if w.is_empty():
			w = {"serial": c.attack_serial, "seg": -1, "charging": false, "stack": c.stack,
				"state": c.state, "anim_t": c.anim_t, "obj": c}
			_watch[c.id] = w
		var ticked := c.anim_t != int(w["anim_t"])
		var attacking := c.state == CreatureSim.State.ATTACK
		var mv := c.move_def() if attacking else {}
		var fx: Dictionary = mv.get("fx", {})
		if not shown(c):
			# Out of the local team's sight: keep track, spawn nothing.
			w["serial"] = c.attack_serial
			w["charging"] = attacking and c.charging
			w["seg"] = c.active_seg() if attacking else -1
			w["stack"] = c.stack
			w["state"] = c.state
			w["anim_t"] = c.anim_t
			continue

		if attacking and c.attack_serial != int(w["serial"]):
			w["seg"] = -1
			_move_started(c, mv, fx)
		w["serial"] = c.attack_serial

		var charging := attacking and c.charging
		if charging and ticked:
			_charging(c, mv, fx)
		# A move that breaks guard only at a full charge: the red cue the moment it's full.
		if attacking and int(w.get("gb_serial", -1)) != c.attack_serial and CreatureView.full_charge_breaks_guard(c):
			w["gb_serial"] = c.attack_serial
			_guard_break_ready(c)
		elif bool(w["charging"]) and not charging and attacking:
			_charge_released(c, mv, fx)
		w["charging"] = charging

		var seg := c.active_seg()
		if seg >= 0 and seg != int(w["seg"]):
			_strike(c, mv, fx, seg)
		w["seg"] = seg if attacking else -1

		if attacking and ticked and not c.charging:
			_during_move(c, mv, fx)
		if c.state == CreatureSim.State.DODGE and ticked and c.state_t % 4 == 1 and not c.def["dodge"].has("blink"):
			_ghost(c, Color(0.75, 0.85, 1.0, 0.4), 10.0)
		if c.state == CreatureSim.State.AIRBORNE and ticked and c.air_t < c.air_total / 2 and c.anim_t % 2 == 0:
			_launch_streak(c)
		if c.stack != int(w["stack"]):
			_stack_changed(c, int(w["stack"]), attacking)
		w["stack"] = c.stack

		# Stoneskin glints now and then (the rim itself is CreatureView's shader).
		if c.shield > 0.0 and ticked and c.anim_t % 26 == 0 and c.state != CreatureSim.State.KO:
			var at := c.pos + Vector2(randf_range(-c.radius, c.radius), -randf_range(8.0, _top(c) - 8.0))
			_add({"kind": "glint", "pos": at, "life": 10, "color": C_GREY[3]})
		# Venom Frenzy: venom drips off her snakes the whole time.
		if c.frenzy_t > 0 and ticked and c.anim_t % 4 == 0 and c.state != CreatureSim.State.KO:
			var at := c.pos + Vector2(randf_range(-c.radius - 4, c.radius + 4), 0)
			_drop(at, randf_range(_top(c) * 0.5, _top(c)), Vector2(randf_range(-0.2, 0.2), 0), 0.0, false,
				C_VENOM[randi() % 2], Vector2(1, 2))
		# Poisoned: green bubbles rise off it now and then.
		if c.poison > 0 and ticked and c.anim_t % 9 == 0 and c.state != CreatureSim.State.KO:
			if c.poison_look == "bleed":
				_drop(c.pos + Vector2(randf_range(-c.radius * 0.6, c.radius * 0.6), 0), randf_range(10.0, _chest(c)),
					Vector2.ZERO, 0.0, false, C_BLEED[0], Vector2(1, 2))
			else:
				_bubble(c.pos + Vector2(randf_range(-c.radius, c.radius), 0), randf_range(4.0, _top(c)))
		if c.state == CreatureSim.State.KO and int(w["state"]) != CreatureSim.State.KO:
			_ko(c)
		w["state"] = c.state
		w["anim_t"] = c.anim_t


func _move_started(c: CreatureSim, mv: Dictionary, fx: Dictionary) -> void:
	if String(mv.get("type", "")) == "surge":
		_dark = maxf(_dark, 0.6)
	if bool(fx.get("burrow", false)):
		cue.emit("dig")
	if bool(fx.get("syrup", false)):
		cue.emit("slosh")
	if bool(fx.get("smoke", false)):
		_smoke(c.pos, 8)
		cue.emit("poof")
	var shout: Dictionary = fx.get("shout", {})
	if not shout.is_empty():
		_text(c.pos + Vector2(0, -_top(c) - 12), String(shout.get("text", "")), Color("ffd166"), 10, 60.0)
		if shout.has("sound"):
			cue.emit(String(shout["sound"]))
	if bool(fx.get("chop", false)):
		_text(c.pos + Vector2(0, -_top(c) - 12), "CHOP CHOP!", Color("ffd166"), 10, 60.0)
		cue.emit("chop_chop")
	if bool(fx.get("rain", false)):
		_rain = 130.0


func _charging(c: CreatureSim, mv: Dictionary, fx: Dictionary) -> void:
	var full := c.is_full_charge()
	match String(fx.get("charge", "")):
		"drips":
			if c.anim_t % (2 if full else 4) == 0:
				var at := c.pos + Vector2(randf_range(-11, 11), randf_range(-2, 2))
				_drop(at, randf_range(12, 20), Vector2.ZERO, 0.0, false)
			if c.anim_t % (8 if full else 14) == 0:
				_add({"kind": "ripple", "pos": c.pos + Vector2(0, 1), "life": 22, "radius": 22.0 if full else 16.0})
		"pebbles":
			if full and c.anim_t % 6 == 0:
				_dust(c.pos + Vector2(randf_range(-10, 10), randf_range(-2, 2)), Vector2(0, -0.4))
		"frost":
			# Icy mist swirling round him, thicker once fully wound.
			if c.anim_t % (2 if full else 4) == 0:
				var a := randf() * TAU
				_px(c.pos + Vector2(cos(a) * 16.0, sin(a) * 6.0 - _chest(c)), Vector2(-sin(a), cos(a) * 0.4) * 0.6,
					C_ICE[randi() % 3], 18)
		"coins":
			# Wound up: coins spill from the bag, more once fully wound.
			if c.anim_t % (3 if full else 6) == 0:
				_chunk(c.pos - c.facing * 6.0, randf_range(28, 40), Vector2(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3)),
					randf_range(0.5, 1.2), 1.5, C_GOLD[randi() % 3], 40.0)
		"dirt":
			# Digging in: dirt kicked up behind him, faster once fully wound.
			if c.anim_t % (2 if full else 4) == 0:
				var back := c.pos - c.facing * 6.0
				_chunk(back, 2.0, -c.facing.rotated(randf_range(-0.6, 0.6)) * randf_range(0.6, 1.4),
					randf_range(1.0, 2.2), randf_range(1.0, 2.0), C_DIRT[randi() % 3], 30.0)
		"venom":
			# Venom drips from the hair snakes' mouths, bubbling once fully wound.
			if c.anim_t % (3 if full else 6) == 0:
				var at := c.pos + Vector2(randf_range(-14, 14), randf_range(-2, 2))
				_drop(at, randf_range(_top(c) - 14.0, _top(c) - 4.0), Vector2.ZERO, 0.0, false, C_VENOM[randi() % 2 + 1])
			if full and c.anim_t % 5 == 0:
				_bubble(c.pos + Vector2(randf_range(-10, 10), 0), randf_range(10.0, _top(c)))
		"psychic":
			# Violet sparks drawn in toward the brain, faster once fully wound.
			if c.anim_t % (2 if full else 4) == 0:
				var at := c.pos + Vector2(0, -_chest(c))
				var from := at + Vector2.from_angle(randf() * TAU) * randf_range(18.0, 28.0)
				_add({"kind": "suck", "from": from, "to": at, "life": 10, "color": C_PSY})
			if full and c.anim_t % 10 == 0:
				_add({"kind": "ring", "pos": c.pos, "life": 12, "radius": 20.0, "color": C_PSY})
		"leaves":
			# Leaves drift in and circle him, faster once fully wound.
			if c.anim_t % (3 if full else 6) == 0:
				var a := randf() * TAU
				_add({"kind": "leaf", "pos": c.pos + Vector2(cos(a), sin(a) * 0.5) * 30.0, "z": randf_range(8, 30),
					"orbit": c.id, "ang": a, "r": 30.0, "spin": 0.12 if full else 0.06, "life": 26,
					"color": C_LEAF[randi() % 3]})


func _charge_released(c: CreatureSim, mv: Dictionary, fx: Dictionary) -> void:
	match String(fx.get("charge", "")):
		"pebbles":
			for pb in _pebbles(c, c.charge):
				var at: Vector2 = pb["ground"]
				var out := (at - c.pos).normalized()
				_chunk(at, float(pb["z"]), out * 0.8 + c.facing * 1.8, randf_range(0.8, 1.6), 2.0, C_PEBBLE[1], 30.0)
		"drips":
			for i in 8:
				_drop(c.pos, 14.0, Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.2), randf_range(1.0, 2.0), true)


func _strike(c: CreatureSim, mv: Dictionary, fx: Dictionary, seg: int) -> void:
	var segs: Array = mv.get("_segs", [])
	var last := seg == segs.size() - 1
	var size := float(fx.get("size", 1.0))
	match String(fx.get("smear", "")):
		"thrust":
			_smear_thrust(c, seg, size, 0.0)
		"arc":
			_smear_arc(c, seg, size)
		"rise":
			_smear_rise(c, seg, size)
		"flurry":
			if last:
				_smear_rise(c, seg, size * 1.3)
			else:
				_smear_thrust(c, seg, size, randf_range(-6.0, 6.0))
	if last:
		match String(fx.get("impact", "")):
			"spire":
				_spire(c.hit_center(seg), c.facing)
			"geysers":
				_geysers(c, mv)
			"lash":
				_lash_impact(c, seg)
			"quake":
				_quake(c, mv)
			"avalanche":
				_avalanche(c.hit_center(seg))
			"leaves":
				_leaves(c.hit_center(seg) + Vector2(0, -_chest(c) * 0.7), 8, 1.5)
			"splash":
				_splash(c.hit_center(seg), c.hit_radius(seg), false)
			"droplets":
				var at := c.hit_center(seg)
				for i in 6:
					_drop(at, randf_range(6, 14), c.facing.rotated(randf_range(-1.0, 1.0)) * randf_range(0.4, 1.2),
						randf_range(0.8, 1.8), true)
			"bellyflop":
				_splash(c.pos, c.hit_radius(seg), true)
			"twister":
				_twister_gust(c, mv)
			"tenderize":
				_tenderize(c, c.hit_center(seg), c.hit_radius(seg))
			"cash":
				_cash_burst(c.hit_center(seg) + Vector2(0, -_chest(c)), 10)
			"blast":
				_ice_blast(c.pos, c.hit_radius(seg))
			"popup":
				_dirt_burst(c.hit_center(seg), c.hit_radius(seg))
				cue.emit("pop")
			"cavein":
				_cave_in(c.hit_center(seg), c.hit_radius(seg))
			"petrify":
				var at := c.hit_center(seg)
				_add({"kind": "ring", "pos": at, "life": 14, "radius": c.hit_radius(seg) + 8.0, "color": C_GREY[2]})
				for i in 6:
					_dust(at + Vector2(randf_range(-8, 8), randf_range(-3, 3)), Vector2(randf_range(-0.5, 0.5), -0.4))
	if bool(fx.get("flash", false)):
		_headlamp(c, c.hit_radius(seg) + float(mv.get("reach", 0)))
	if String(fx.get("impact", "")) == "frost":
		var at := c.hit_center(seg) + Vector2(0, -_chest(c))
		for i in 5:
			_px(at, Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.2), C_ICE[1 + randi() % 2], 14)
	if bool(fx.get("spray", false)):
		_ice_spray(c, c.hit_radius(seg), float(mv.get("cone", 0.6)))
	if bool(fx.get("wave_cone", false)):
		_water_fan(c, c.hit_center(seg), c.hit_radius(seg), float(mv.get("cone", 0.6)))
	if String(fx.get("impact", "")) == "roots":
		_roots(c, c.hit_radius(seg), last)


func _during_move(c: CreatureSim, mv: Dictionary, fx: Dictionary) -> void:
	var t := c.state_t
	if fx.has("afterimage"):
		var win: Array = fx["afterimage"]
		if t >= int(win[0]) and t <= int(win[1]):
			if t % 3 == 0:
				_ghost(c, Color(String(fx.get("ghost_color", "#ffffff"))), 14.0)
			if String(fx.get("trail", "")) == "splash" and not c.connected:
				var back := c.pos - c.facing * 8.0 + Vector2(randf_range(-3, 3), randf_range(-2, 2))
				_drop(back, 2.0, -c.facing * randf_range(0.2, 0.7) + Vector2(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2)),
					randf_range(1.0, 2.0), true)
				if t % 3 == 0:
					_add({"kind": "puddle", "pos": back, "radius": randf_range(2.5, 4.5), "ry": 0.4, "grow": 3.0,
						"life": 70.0, "fade": 35.0})
			if String(fx.get("trail", "")) == "gravel" and not c.connected:
				var back := c.pos - c.facing * 7.0 + Vector2(randf_range(-4, 4), randf_range(-2, 2))
				_chunk(back, 1.0, -c.facing * randf_range(0.2, 0.8) + Vector2(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3)),
					randf_range(0.6, 1.5), randf_range(1.0, 2.0), C_PEBBLE[randi() % 2], 26.0)
				if t % 4 == 0:
					_dust(back, Vector2(-c.facing.x * 0.3, -0.3))
	if bool(fx.get("spin", false)) and not c.charging:
		var segs: Array = mv.get("_segs", [])
		if segs.size() > 0 and t >= int(segs[0]["at"]) - 2 and t <= int(segs[segs.size() - 1]["at"]) + 3:
			var r := c.hit_radius(segs.size() - 1)
			if t % 2 == 0:
				var a := randf() * TAU
				_add({"kind": "leaf", "pos": c.pos, "z": randf_range(10, 34), "orbit": c.id, "ang": a,
					"r": r * randf_range(0.6, 1.0), "spin": 0.35, "life": 14, "color": C_LEAF[randi() % 3]})
			if t % 4 == 0:
				_add({"kind": "whirl", "pos": c.pos + Vector2(0, -_chest(c) * 0.6), "life": 8, "radius": r,
					"start": randf() * TAU})
	var dsh: Dictionary = mv.get("dash", {})
	if bool(fx.get("slush", false)) and not dsh.is_empty() and t >= int(dsh["from"]) and t <= int(dsh["to"]):
		_px(c.pos - c.facing * 6.0 + Vector2(randf_range(-4, 4), -randf_range(0, 4)),
			-c.facing * randf_range(0.3, 0.9) + Vector2(0, -0.3), C_ICE[randi() % 3], 16)
		if t % 3 == 0:
			_add({"kind": "puddle", "pos": c.pos - c.facing * 4.0, "radius": randf_range(3.0, 4.5), "ry": 0.45,
				"grow": 2.0, "life": 90.0, "fade": 40.0, "color": Color(C_ICE[2], 0.55)})
	var lp: Dictionary = mv.get("leap", {})
	if bool(fx.get("burrow", false)) and not lp.is_empty() and t >= int(lp["from"]) and t <= int(lp["to"]):
		if t % 2 == 0:
			_chunk(c.pos + Vector2(randf_range(-6, 6), randf_range(-2, 2)), 3.0,
				Vector2(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3)) - c.facing * 0.4, randf_range(1.0, 2.0),
				randf_range(1.0, 2.0), C_DIRT[randi() % 3], 26.0)
		if t % 5 == 0:
			_dust(c.pos - c.facing * 6.0, Vector2(-c.facing.x * 0.3, -0.3))
			_add({"kind": "puddle", "pos": c.pos - c.facing * 4.0, "radius": randf_range(3.0, 4.5), "ry": 0.45,
				"grow": 2.0, "life": 90.0, "fade": 40.0, "color": Color(C_DIRT[0], 0.6)})
	var gz: Dictionary = mv.get("gaze", {})
	if bool(fx.get("gaze", false)) and not gz.is_empty() and t >= int(gz["from"]) and t <= int(gz["to"]) \
			and t % 3 == 0:
		var eyes := c.pos + Vector2(c.facing.x * 4.0, -_top(c) + 12.0)
		_add({"kind": "glint", "pos": eyes + Vector2(randf_range(-4, 4), randf_range(-2, 2)), "life": 6, "color": C_GAZE})
		if t % 12 == 0:
			_add({"kind": "ring", "pos": c.pos + c.facing * 20.0, "life": 14, "radius": 14.0,
				"color": Color(C_GAZE, 0.5)})
	if bool(fx.get("suction", false)) and t <= int(mv.get("startup", 0)) + int(mv.get("active", 0)):
		var mouth := c.pos + c.facing * 12.0 + Vector2(0, -_chest(c))
		for i in 2:
			var from := mouth + c.facing.rotated(randf_range(-1.0, 1.0)) * randf_range(16, 30) + Vector2(0, randf_range(-6, 6))
			_add({"kind": "suck", "from": from, "to": mouth, "life": 8})


# ------------------------------------------------------------------ smears

func _chest(c: CreatureSim) -> float:
	return float(c.def.get("fx_height", 16))


## How high a swing is drawn above the feet. A sideways swing sits at chest height, where
## the arms are, and that height doesn't change how far it looks like it reaches. A swing
## straight up or down is drawn at the feet instead: lifted, a downward swing would look
## a chest short of the hit circle and an upward one a chest past it, though every hit
## reaches the same distance in every direction.
func _swing_lift(c: CreatureSim, f: Vector2) -> float:
	return _chest(c) * absf(f.x)


func _top(c: CreatureSim) -> float:
	return float(c.def.get("fx_top", 32))


## A tapered streak behind the fist: thin at the shoulder, wide at the point of impact.
func _smear_thrust(c: CreatureSim, seg: int, size: float, dz: float) -> void:
	var f := _swing_dir(c)
	var up := Vector2(0, -_swing_lift(c, f) - c.air_height() + dz)
	var start := c.pos + f * 4.0 + up
	var end := c.pos + f * (c.seg_value(seg, "reach") + c.hit_radius(seg) * 0.5) + up
	var n := f.orthogonal()
	var w := 2.5 * size
	_add({"kind": "smear", "life": 6, "color": Color(1, 1, 1, 0.9),
		"pts": PackedVector2Array([start, end + n * w, end + f * 3.0 * size, end - n * w])})
	for side in [-1.0, 1.0]:
		var o: Vector2 = n * (w + 2.0) * side
		_add({"kind": "streak", "a": start + f * 6.0 + o, "b": end - f * 2.0 + o, "life": 5,
			"color": Color(1, 1, 1, 0.55)})


## A hook: a crescent sweeping around the front of the body.
func _smear_arc(c: CreatureSim, seg: int, size: float) -> void:
	var f := _swing_dir(c)
	var center := c.pos + Vector2(0, -_swing_lift(c, f) - c.air_height())
	var r := c.seg_value(seg, "reach") + 3.0 * size
	var a0 := f.angle()
	var sweep := -1.0 if f.x < 0.0 else 1.0
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var k := float(i) / steps
		var a := a0 + sweep * lerpf(-1.9, 0.6, k)
		var dir := Vector2(cos(a), sin(a))
		outer.append(center + dir * r)
		inner.append(center + dir * (r - lerpf(0.5, 5.0, k * k) * size))
	inner.reverse()
	outer.append_array(inner)
	_add({"kind": "smear", "life": 7, "color": Color(1, 1, 1, 0.85), "pts": outer})


## An uppercut: a vertical crescent rising in front of the body.
func _smear_rise(c: CreatureSim, seg: int, size: float) -> void:
	var side := -1.0 if c.facing.x < -0.1 else (1.0 if c.facing.x > 0.1 else (-1.0 if _flip(c) else 1.0))
	var r := 15.0 * size
	var center := c.pos + c.facing * c.seg_value(seg, "reach") * 0.4 + Vector2(-side * 4.0, -_chest(c) - c.air_height() - 4.0)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var k := float(i) / steps
		var a := lerpf(0.9, -1.7, k)  # from low in front, up and over the top
		var dir := Vector2(cos(a) * side, sin(a))
		outer.append(center + dir * r)
		inner.append(center + dir * (r - lerpf(0.5, 6.0, k) * size))
	inner.reverse()
	outer.append_array(inner)
	_add({"kind": "smear", "life": 8, "color": Color(1, 0.97, 0.88, 0.9), "pts": outer})


## Where a swing is drawn. Fighters with up/down art swing exactly where the hit goes;
## side-only art can't show a punch straight up or down, so it's drawn angled toward the
## side the sprite faces.
func _swing_dir(c: CreatureSim) -> Vector2:
	var f := c.facing
	if c.id < views.size() and views[c.id] != null and (views[c.id] as CreatureView).has_vertical_views():
		return f  # it has up/down art, so the swing goes where the hit goes
	if absf(f.x) < 0.1:
		return Vector2(-1.0 if _flip(c) else 1.0, f.y * 0.8).normalized()
	return f


func _flip(c: CreatureSim) -> bool:
	if c.id < views.size() and views[c.id] != null:
		return bool((views[c.id] as CreatureView).flip)
	return c.facing.x < 0.0


# ------------------------------------------------------------------ move effects

## A teleport flash: a psychic ring and sparks, pulled in where he vanishes (`arrive`
## false) and flung out where he appears.
func _warp_flash(at: Vector2, arrive: bool) -> void:
	_add({"kind": "ring", "pos": at, "life": 10 if arrive else 8, "radius": 16.0 if arrive else 10.0, "color": C_PSY})
	_add({"kind": "spark", "pos": at, "life": 6, "scale": 0.8 if arrive else 0.6})
	for i in 10:
		var d := Vector2.from_angle(TAU * i / 10.0 + randf() * 0.4)
		if arrive:
			_px(at + d * 3.0, d * randf_range(1.0, 1.8), C_PSY.lightened(0.3), 12)
		else:
			_add({"kind": "suck", "from": at + d * randf_range(12.0, 18.0), "to": at, "life": 6, "color": C_PSY})


func _ghost(c: CreatureSim, tint: Color, life: float) -> void:
	if c.id >= views.size() or views[c.id] == null:
		return
	var v: CreatureView = views[c.id]
	if v.ko_hidden:
		return
	var snap := v.snapshot()
	snap["kind"] = "ghost"
	snap["life"] = life
	snap["tint"] = tint
	_add(snap)


func _launch_streak(c: CreatureSim) -> void:
	var body := c.pos + Vector2(randf_range(-7, 7), -c.air_height() - randf_range(0, 6))
	_add({"kind": "streak", "a": body + Vector2(0, 6), "b": body + Vector2(0, 16), "life": 6,
		"color": Color(1, 1, 1, 0.6)})


func _slam_debris(p: Vector2, full: bool) -> void:
	for i in (10 if full else 5):
		var v := Vector2.from_angle(randf() * TAU) * randf_range(0.5, 1.8)
		_chunk(p + v * 3.0, 2.0, v, randf_range(1.6, 3.4), randf_range(2.0, 3.5), C_CON[randi() % 3], 55.0)
	# Cracks that run outward from the impact.
	var lines: Array = []
	for i in (7 if full else 4):
		var a := TAU * i / (7 if full else 4) + randf_range(-0.3, 0.3)
		var pts := PackedVector2Array([p])
		var cur := p
		for j in 4:
			a += randf_range(-0.5, 0.5)
			cur += Vector2(cos(a), sin(a) * 0.6) * randf_range(4.0, 8.0 if full else 5.0)
			pts.append(cur)
		lines.append(pts)
	_add({"kind": "decal", "lines": lines, "life": 80, "grow": 8.0, "fade": 30.0})
	shake_out = maxf(shake_out, 1.0)


func _spire(at: Vector2, facing: Vector2) -> void:
	_add({"kind": "spire", "pos": at, "life": 34, "h": 30.0, "w": 8.0, "front": true})
	_add({"kind": "spire", "pos": at - facing * 9.0 + Vector2(0, 2), "life": 30, "h": 18.0, "w": 6.0, "delay": 2.0})
	_add({"kind": "spire", "pos": at + facing.orthogonal() * 8.0, "life": 28, "h": 14.0, "w": 5.0, "delay": 3.0})
	for i in 8:
		_chunk(at, 4.0, Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.4), randf_range(1.8, 3.2),
			randf_range(2.0, 3.0), C_STONE[randi() % 3], 45.0)
	for i in 5:
		_dust(at + Vector2(randf_range(-8, 8), randf_range(-2, 2)), Vector2(randf_range(-0.4, 0.4), -0.6))
	_later(30.0, _spire_crumble.bind(at))
	shake_out = maxf(shake_out, 3.0)
	cue.emit("spire")


func _spire_crumble(at: Vector2) -> void:
	for i in 6:
		_chunk(at + Vector2(randf_range(-4, 4), 0), randf_range(6, 20), Vector2.from_angle(randf() * TAU) * 0.6,
			0.5, randf_range(2.0, 3.0), C_STONE[randi() % 3], 30.0)


## Boulder Lash: the head cracks into the target and chips fly off the tip.
func _lash_impact(c: CreatureSim, seg: int) -> void:
	var at := c.hit_center(seg) + c.facing * 6.0
	for i in 7:
		var v := c.facing.rotated(randf_range(-1.0, 1.0)) * randf_range(0.6, 1.8)
		_chunk(at, 22.0, v, randf_range(0.8, 2.0), randf_range(1.5, 2.5), C_GREY[randi() % 3], 40.0)
	_add({"kind": "ring", "pos": at, "life": 8, "radius": 10.0, "color": C_GREY[3]})
	_dust(at, Vector2(c.facing.x * 0.3, -0.4))
	cue.emit("lash")


## Rockslide Stomp: a shockwave rolls out from the stomping foot and the ground jumps.
func _quake(c: CreatureSim, mv: Dictionary) -> void:
	var r := float(mv.get("hit_radius", 24))
	var full := c.charge_ratio >= 1.0
	_add({"kind": "ring", "pos": c.pos, "life": 16, "radius": r + 6.0, "color": C_CRAG[2]})
	_add({"kind": "ring", "pos": c.pos, "life": 22, "radius": r + 18.0})
	for i in 12:
		var a := TAU * i / 12.0 + randf() * 0.3
		var at := c.pos + Vector2(cos(a), sin(a)) * (r - 4.0 + randf() * 6.0)
		_dust(at, Vector2(cos(a), sin(a) * 0.5 - 0.7) * 0.6)
		if i % 2 == 0:
			_chunk(at, 1.0, Vector2(cos(a), sin(a) * 0.5) * randf_range(0.3, 0.9), randf_range(1.6, 2.8),
				randf_range(2.0, 3.0), C_CRAG[randi() % 3] if i % 4 == 0 else C_GREY[randi() % 3], 45.0)
	_slam_debris(c.pos + c.facing * 6.0, full)
	shake_out = maxf(shake_out, 3.5 if full else 2.5)


## Avalanche Coil: boulders shaken loose by the crash rain down around it.
func _avalanche(at: Vector2) -> void:
	_add({"kind": "lines", "pos": at + Vector2(0, -10), "life": 12, "size": 2.0, "color": C_AMBER})
	for i in 14:
		var spot := at + Vector2(randf_range(-30, 30), randf_range(-12, 12))
		_chunk(spot, randf_range(40, 90), Vector2(randf_range(-0.2, 0.2), 0), -randf_range(0.5, 1.5),
			randf_range(2.5, 4.5), C_GREY[randi() % 3] if i % 3 else C_CRAG[randi() % 3], 70.0, true)
	for i in 10:
		var a := TAU * i / 10.0
		_dust(at + Vector2(cos(a) * 20.0, sin(a) * 8.0), Vector2(cos(a), sin(a) * 0.5 - 0.6) * 0.7)
	shake_out = maxf(shake_out, 6.0)
	cue.emit("avalanche")


## Storm Drain: water erupts from the ring of pits it leaves behind.
func _geysers(c: CreatureSim, mv: Dictionary) -> void:
	var ring: Dictionary = mv.get("terrain_ring", {"inner": 24, "outer": 40})
	var r := (float(ring["inner"]) + float(ring["outer"])) * 0.5
	var n := 8
	for i in n:
		var at := c.pos + Vector2.from_angle(TAU * i / n + 0.2) * r
		_later(randf_range(0.0, 6.0), _geyser_start.bind(at))
	shake_out = maxf(shake_out, 4.0)
	cue.emit("geysers")


func _geyser_start(at: Vector2) -> void:
	_add({"kind": "ripple", "pos": at, "life": 24, "radius": 14.0})
	_add({"kind": "emit", "life": 22, "every": 1.0, "acc": 0.0, "fn": _geyser_tick.bind(at)})


func _geyser_tick(k: float, at: Vector2) -> void:
	for j in 2:
		var col := C_FOAM if randf() < 0.3 else (C_WATER_L if randf() < 0.5 else C_WATER)
		_drop(at + Vector2(randf_range(-3, 3), randf_range(-1, 1)), 1.0,
			Vector2(randf_range(-0.35, 0.35), randf_range(-0.2, 0.2)), randf_range(3.4, 5.0) * (1.0 - k * 0.5), true, col,
			Vector2(2, 3) if randf() < 0.6 else Vector2(1, 2))


func _projectile_spray() -> void:
	for pr in sim.projectiles:
		if not _is_wave(pr):
			if _tick % 4 == 0 and not bool(pr.get("lob", false)) and _proj_kind(pr) == "venom":
				_drop(Vector2(pr["pos"]) - Vector2(pr["vel"]).normalized() * 3.0, 20.0, Vector2.ZERO, 0.0, false,
					C_VENOM[1])
			continue
		var pos: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		for i in 2:
			_drop(pos + Vector2(randf_range(-4, 4), randf_range(-2, 2)), randf_range(4, 9),
				vel * 0.25 + Vector2(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3)), randf_range(0.6, 1.6), false)
		if _tick % 3 == 0:
			_add({"kind": "puddle", "pos": pos - vel * 2.0, "radius": randf_range(3.0, 5.0), "ry": 0.4,
				"grow": 4.0, "life": 80.0, "fade": 40.0})


func _is_wave(pr: Dictionary) -> bool:
	return _owner_has_wave(sim.creatures[int(pr["owner"])])


func _owner_has_wave(owner: CreatureSim) -> bool:
	for mid in owner.moves():
		var mv: Dictionary = owner.moves()[mid]
		if mv.has("projectile") and String(mv.get("fx", {}).get("projectile", "")) == "wave":
			return true
	return false


func _owner_near(p: Vector2) -> CreatureSim:
	var best: CreatureSim = null
	var bd := INF
	for c in sim.creatures:
		var d := c.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = c
	return best


func _pit_plume(p: Vector2) -> void:
	for i in 9:
		var v := Vector2(randf_range(-0.35, 0.35), randf_range(-1.6, -0.8))
		_add({"kind": "dust", "pos": p + Vector2(randf_range(-6, 6), randf_range(-2, 2)), "vel": v, "life": 24})
	_add({"kind": "ring", "pos": p, "life": 14, "radius": 22.0})
	shake_out = maxf(shake_out, 2.5)
	cue.emit("land")


# ------------------------------------------------------------------ Barkley

## A puff of leaves: they flutter out, then drift down.
func _leaves(at: Vector2, n: int, speed: float) -> void:
	for i in n:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.0) * speed
		_add({"kind": "leaf", "pos": at + Vector2(0, 14), "z": 14.0, "vel": Vector2(v.x, v.y * 0.5), "vz": randf_range(0.6, 1.6),
			"g": 0.05, "life": randf_range(40, 70), "color": C_LEAF[randi() % 3], "rot": randf() * TAU,
			"vrot": randf_range(-0.3, 0.3), "bounce": 0.0})


## Timber Twister's last hit: a ring of wind and a gust of leaves thrown outward.
func _twister_gust(c: CreatureSim, mv: Dictionary) -> void:
	var r := float(mv.get("hit_radius", 24))
	_add({"kind": "ring", "pos": c.pos, "life": 14, "radius": r + 10.0, "color": C_LEAF[2]})
	_add({"kind": "ring", "pos": c.pos, "life": 20, "radius": r + 22.0})
	for i in 14:
		var a := TAU * i / 14.0
		var v := Vector2(cos(a), sin(a) * 0.5) * randf_range(1.2, 2.4)
		_add({"kind": "leaf", "pos": c.pos + v * 6.0, "z": randf_range(10, 28), "vel": v, "vz": randf_range(0.4, 1.2),
			"g": 0.05, "life": randf_range(40, 70), "color": C_LEAF[randi() % 3], "rot": randf() * TAU,
			"vrot": randf_range(-0.4, 0.4), "bounce": 0.0})
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		_dust(c.pos + Vector2(cos(a), sin(a)) * r * 0.8, Vector2(cos(a), sin(a) * 0.5 - 0.4) * 0.8)
	shake_out = maxf(shake_out, 2.0)
	cue.emit("twister")


## Root Eruption: roots punch up through the floor in a ring at the reach of each hit.
func _roots(c: CreatureSim, r: float, last: bool) -> void:
	var n := int(clampf(r / 4.5, 6.0, 14.0))
	var off := randf() * TAU
	for i in n:
		var a := off + TAU * i / n + randf_range(-0.15, 0.15)
		var at := c.pos + Vector2(cos(a), sin(a)) * r * randf_range(0.82, 1.0)
		var h := randf_range(12.0, 20.0) * (1.3 if last else 1.0)
		_add({"kind": "root", "pos": at, "life": 30 if last else 22, "h": h, "w": randf_range(2.5, 3.6),
			"lean": cos(a) * randf_range(0.2, 0.5), "delay": randf_range(0.0, 3.0), "front": sin(a) > 0.0})
		if i % 2 == 0:
			_chunk(at, 2.0, Vector2(cos(a), sin(a) * 0.5) * randf_range(0.3, 0.9), randf_range(1.2, 2.2),
				randf_range(1.5, 2.5), C_CON[randi() % 3], 40.0)
	_add({"kind": "ring", "pos": c.pos, "life": 12, "radius": r, "color": C_LEAF[1]})
	shake_out = maxf(shake_out, 4.0 if last else 2.0)
	if last:
		_leaves(c.pos + Vector2(0, -20), 10, 1.2)
		cue.emit("roots")


## Pinecone Bomb lands: scales and needles burst out of the spot.
func _pinecone_burst(at: Vector2, r: float) -> void:
	_add({"kind": "spark", "pos": at + Vector2(0, -6), "life": 10, "scale": 1.4})
	_add({"kind": "ring", "pos": at, "life": 14, "radius": r + 4.0, "color": C_CONE[2]})
	for i in 10:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(0.6, 1.8)
		_chunk(at, 4.0, Vector2(v.x, v.y * 0.5), randf_range(1.0, 2.4), randf_range(1.5, 2.5), C_CONE[randi() % 3], 36.0)
	for i in 8:
		var v := Vector2.from_angle(TAU * i / 8.0 + randf() * 0.4)
		_add({"kind": "streak", "a": at + Vector2(v.x, v.y * 0.5) * 4.0 + Vector2(0, -4),
			"b": at + Vector2(v.x, v.y * 0.5) * randf_range(12.0, 18.0) + Vector2(0, -6), "life": 8, "color": C_LEAF[1]})
	for i in 4:
		_dust(at + Vector2(randf_range(-6, 6), randf_range(-2, 2)), Vector2(randf_range(-0.4, 0.4), -0.5))
	_slam_debris(at, false)


## Gillbert's splashes: a ring of water, drops thrown up, and puddles left behind. A
## belly-flop is the same, much bigger, with a column of spray.
func _splash(at: Vector2, r: float, huge: bool) -> void:
	_add({"kind": "ripple", "pos": at, "life": 24 if huge else 18, "radius": r + (14.0 if huge else 6.0)})
	_add({"kind": "ring", "pos": at, "life": 14, "radius": r, "color": C_WATER_L})
	var n := 30 if huge else 14
	for i in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a) * 0.5) * randf_range(0.6, 2.2 if huge else 1.5)
		_drop(at + v * 3.0, 2.0, v, randf_range(1.5, 4.0 if huge else 2.6), true, Color(0, 0, 0, 0),
			Vector2(2, 2) if randf() < 0.4 else Vector2(1, 2))
	for i in (6 if huge else 3):
		_add({"kind": "puddle", "pos": at + Vector2(randf_range(-r, r) * 0.7, randf_range(-r, r) * 0.3),
			"radius": randf_range(4.0, 8.0 if huge else 6.0), "ry": 0.4, "grow": 4.0, "life": 140.0, "fade": 50.0})
	if huge:
		_add({"kind": "emit", "life": 14, "every": 1.0, "acc": 0.0, "fn": _spray_tick.bind(at)})
		_text(at + Vector2(0, -40), "SPLASH!", C_WATER_L, 10, 50.0)
		shake_out = maxf(shake_out, 6.0)
		cue.emit("bellyflop")
	else:
		shake_out = maxf(shake_out, 2.0)
		cue.emit("splash")


func _spray_tick(k: float, at: Vector2) -> void:
	for j in 3:
		var col := C_FOAM if randf() < 0.35 else (C_WATER_L if randf() < 0.5 else C_WATER)
		_drop(at + Vector2(randf_range(-6, 6), randf_range(-2, 2)), 2.0,
			Vector2(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3)), randf_range(3.5, 5.5) * (1.0 - k * 0.6), true, col,
			Vector2(2, 3) if randf() < 0.5 else Vector2(1, 2))


## Gillbert's knockout: one last wet flop and a puddle.
func _flop_ko(c: CreatureSim) -> void:
	for i in 10:
		_drop(c.pos, 6.0, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0), randf_range(0.8, 1.8), true)
	_add({"kind": "puddle", "pos": c.pos + Vector2(0, 2), "radius": 16.0, "ry": 0.35, "grow": 60.0, "life": FOREVER})
	cue.emit("flop")


## Cast Line: a taut line from his mouth to the thrown rod while it flies, then to
## whoever it hooked while he is reeled in to them.
func _draw_cast(ci: CanvasItem, c: CreatureSim, mv: Dictionary) -> void:
	var from := c.pos + c.facing * 10.0 + Vector2(0, -_chest(c) + 2.0)
	var end := Vector2.ZERO
	if c.reel_t > 0:
		var tgt := _creature(c.reel_to)
		if tgt == null:
			return
		end = tgt.pos + Vector2(0, -_chest(tgt))
	else:
		var found := false
		for pr in sim.projectiles:
			if int(pr["owner"]) == c.id and int(pr["serial"]) == c.attack_serial:
				end = Vector2(pr["pos"]) + Vector2(0, -10)
				found = true
		if not found:
			return
	ci.draw_line(from, end, Color(C_GREY[2], 0.9), 1.0)
	if c.reel_t > 0:
		# the hook in the catch, and the line twitching as it's wound in
		var hd := (end - from).normalized() if end.distance_squared_to(from) > 1.0 else c.facing
		ci.draw_line(end, end + hd * 2.0 + Vector2(0, 2), C_GREY[3], 1.0)
		ci.draw_line(end + hd * 2.0 + Vector2(0, 2), end + Vector2(0, 3), C_GREY[3], 1.0)
		if _tick % 3 == 0:
			var mid := from.lerp(end, randf_range(0.2, 0.8))
			_drop(mid + Vector2(0, 12), 12.0, Vector2(randf_range(-0.3, 0.3), 0.0), randf_range(0.2, 0.6), false)


## Tenderize: the mallet pounds the floor: a thump ring, dust, and the mallet's tooth
## marks left in the floor for a moment.
func _tenderize(c: CreatureSim, at: Vector2, r: float) -> void:
	_add({"kind": "ring", "pos": at, "life": 16, "radius": r, "color": C_TENDER})
	_add({"kind": "ring", "pos": at, "life": 10, "radius": r * 0.5, "color": Color.WHITE})
	for i in 8:
		var a := TAU * i / 8.0 + randf() * 0.3
		_dust(at + Vector2(cos(a), sin(a)) * r * 0.6, Vector2(cos(a), sin(a) * 0.5 - 0.5) * 0.5)
	for i in 6:
		var off := Vector2(randf_range(-r, r) * 0.5, randf_range(-r, r) * 0.25)
		_add({"kind": "puddle", "pos": at + off, "radius": 1.5, "ry": 1.0, "grow": 1.0, "life": 90.0, "fade": 40.0,
			"color": Color(0, 0, 0, 0.35)})
	_text(at + Vector2(0, -24), "THWACK!", C_TENDER, 8, 34.0)
	shake_out = maxf(shake_out, 2.5)
	cue.emit("thwack")


## Flip Out: the spatula's arc over his head, and the call-out.
func _flip_out(e: Dictionary) -> void:
	var a := _creature(int(e.get("attacker", -1)))
	if a == null:
		return
	var from := a.pos - a.facing * 22.0  # where the target was (he has already turned)
	var to := a.pos + a.facing * 26.0
	var pts := PackedVector2Array()
	for i in 13:
		var k := i / 12.0
		pts.append(from.lerp(to, k) + Vector2(0, -12.0 - sin(k * PI) * 34.0))
	_add({"kind": "streak", "a": pts[2], "b": pts[6], "life": 12, "color": Color(C_PSY, 0.8)})
	_add({"kind": "streak", "a": pts[6], "b": pts[10], "life": 12, "color": Color(C_PSY, 0.8)})
	_text(a.pos + Vector2(0, -_top(a) - 16), "FLIP!", Color("ffd166"), 9, 40.0)


## Gulp, held: the tongue snaps back with the foe on it and down it goes. Culvert puffs
## up with a mouthful.
func _swallow_fx(e: Dictionary) -> void:
	var a := _creature(int(e.get("attacker", -1)))
	if a == null:
		return
	_text(a.pos + Vector2(0, -_top(a) - 14), "GULP!", Color("b6f28a"), 9, 36.0)
	var mouth := a.pos + a.facing * 8.0 + Vector2(0, -10)
	for i in 8:
		_drop(mouth, 8.0, Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.2), randf_range(0.6, 1.6), true)
	_kick_view(a, Vector2(1.28, 0.82))


## ...and out the back end: a quick squat, a plop, a puff of dust, a whiff of stink lines
## and the swallowed fighter skidding out behind him.
func _poop_fx(e: Dictionary) -> void:
	var a := _creature(int(e.get("attacker", -1)))
	var at: Vector2 = e["pos"]
	if a != null:
		_kick_view(a, Vector2(1.3, 0.68))
		at = a.pos - a.facing * (a.radius + 4.0)
	for i in 10:
		var v := Vector2(randf_range(-0.9, 0.9), randf_range(-0.9, -0.2))
		if a != null:
			v += -a.facing * randf_range(0.3, 1.0)
		_add({"kind": "dust", "pos": at + Vector2(randf_range(-4, 4), randf_range(-2, 2)), "vel": v, "life": 26})
	for i in 3:  # stink lines, wafting up
		_later(0.05 * i, func(): _stink(at + Vector2(randf_range(-8, 8), -6)))
	_add({"kind": "ring", "pos": at, "life": 10, "radius": 12.0, "color": Color("a3824c")})
	var back := -a.facing if a != null else Vector2.LEFT
	_text(at + back * 18.0 + Vector2(0, -6), "PLOP!", Color("e0b36a"), 9, 40.0)  # low, clear of his bar
	shake_out = maxf(shake_out, 1.5)


func _stink(at: Vector2) -> void:
	for k in 4:
		_px(at + Vector2(sin(k * 1.4) * 2.0, -k * 2.0), Vector2(sin(k) * 0.15, -0.45), Color(0.62, 0.78, 0.32, 0.8), 34)


func _kick_view(c: CreatureSim, to: Vector2) -> void:
	for v in views:
		if v is CreatureView and (v as CreatureView).c == c:
			(v as CreatureView).kick(to)


## Chef Cerebro's knockout: the brain fizzles out with a puff of steam, and his
## sunglasses skid off across the floor.
func _deflate(c: CreatureSim) -> void:
	for i in 10:
		var at := c.pos + Vector2(randf_range(-10, 10), -randf_range(6, 20))
		_px(at, Vector2(randf_range(-0.3, 0.3), -randf_range(0.4, 0.9)), Color(1, 1, 1, 0.7), 30)
	for i in 6:
		_chunk(c.pos, 12.0, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0), randf_range(0.6, 1.4),
			2.0, C_BRAIN[randi() % 3], 40.0)
	var dir := -c.facing
	_chunk(c.pos + Vector2(0, -2), 10.0, dir * 1.6, 1.2, 3.0, Color("0c0c10"), 120.0)
	_text(c.pos + Vector2(0, -_top(c) - 6), "fzzt...", C_PSY, 7, 50.0)
	cue.emit("fizzle")


## Barkley's knockout: he topples like a felled tree.
func _timber(c: CreatureSim) -> void:
	_text(c.pos + Vector2(0, -_top(c) - 6), "TIMBER!", Color("ffd166"), 10, 70.0)
	_leaves(c.pos + Vector2(0, -_top(c) + 10), 12, 1.0)
	cue.emit("timber")


func _timber_land(c: CreatureSim, length: float) -> void:
	# The knockout art falls over backward, so the trunk lands behind where he faced.
	var back := Vector2(-1.0 if c.facing.x >= -0.1 else 1.0, 0.0)
	for i in 9:
		var k := lerpf(-0.35, 0.85, float(i) / 8.0)
		_dust(c.pos + back * length * k + Vector2(randf_range(-2, 2), randf_range(-2, 2)), Vector2(randf_range(-0.4, 0.4), -0.5))
	_leaves(c.pos + back * length * 0.8 + Vector2(0, -8), 8, 1.3)
	for i in 5:
		_chunk(c.pos + back * length * randf_range(-0.3, 0.8), 4.0, Vector2(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3)),
			randf_range(0.8, 1.6), 2.0, C_WOOD[randi() % 4], 50.0)
	shake_out = maxf(shake_out, 4.0)
	cue.emit("slam")


# ------------------------------------------------------------------ windup tells

## A raw big move is winding up: a glint over the head for the length of the windup,
## a ring at the feet, and a "!" when it can't be blocked.
func _windup_tell(e: Dictionary) -> void:
	var who := int(e.get("who", -1))
	if who < 0 or who >= sim.creatures.size():
		return
	var c := sim.creatures[who]
	var frames := float(e["power"])
	var tell := String(e.get("tell", "strong"))
	var red := tell in ["unblockable", "guard_break"]
	var col := CreatureView.TELL_RED if red else CreatureView.TELL_GOLD
	var head := c.pos + Vector2(0, -_top(c) - 9.0)
	_add({"kind": "glint", "pos": head, "life": frames + 2.0, "color": col})
	_add({"kind": "ring", "pos": c.pos, "life": frames, "radius": 22.0, "color": col})
	if red:
		_text(head + Vector2(10, -2), "!", col, 12, frames + 10.0)
		_text(head + Vector2(0, -12), "UNBLOCKABLE" if tell == "unblockable" else "GUARD BREAK", col, 6,
			frames + 10.0)


## A held move reached the full charge that makes it break guard (Sack Smack): the same
## red glint, ring and words as an unblockable windup, while the button stays held.
func _guard_break_ready(c: CreatureSim) -> void:
	var col := CreatureView.TELL_RED
	var head := c.pos + Vector2(0, -_top(c) - 9.0)
	_add({"kind": "glint", "pos": head, "life": 24.0, "color": col})
	_add({"kind": "ring", "pos": c.pos, "life": 18.0, "radius": 22.0, "color": col})
	_text(head + Vector2(10, -2), "!", col, 12, 34.0)
	_text(head + Vector2(0, -12), "GUARD BREAK", col, 6, 34.0)
	cue.emit("windup_red")


# ------------------------------------------------------------------ Cairn's stones

## Where the stones hover above Cairn's head, as [floor position, height].
func _stack_slots(c: CreatureSim, count: int) -> Array:
	var out: Array = []
	var z := _top(c) + 7.0 + c.air_height()
	for i in count:
		var x := (i - (count - 1) * 0.5) * 7.0
		var bob := sin((c.anim_t + i * 9) * 0.12) * 1.5
		out.append([c.pos + Vector2(x, 0), z + bob])
	return out


func _stack_changed(c: CreatureSim, before: int, attacking: bool) -> void:
	if c.state == CreatureSim.State.KO:
		return
	var max_n := int(c.def.get("stack", {}).get("max", 3))
	if c.stack > before:
		var slot: Array = _stack_slots(c, c.stack)[c.stack - 1]
		var sp: Vector2 = slot[0] + Vector2(0, -float(slot[1]))
		for i in 4:
			_px(sp, Vector2.from_angle(randf() * TAU) * 0.9, C_SPARK[0], 8)
		return
	# Spent on a Haymaker or Rush: the stones fly into the punch. Timed out: they drop.
	var slots := _stack_slots(c, before)
	for i in before:
		var at: Vector2 = slots[i][0]
		var z := float(slots[i][1])
		var col: Color = C_STACK[i % max_n]
		if attacking:
			_chunk(at, z, c.facing * 3.2 + Vector2(0, randf_range(-0.3, 0.3)), -0.6, 3.0, col, 12.0)
		else:
			_chunk(at, z, Vector2(randf_range(-0.3, 0.3), 0), 0.5, 3.0, col, 40.0)
	if attacking:
		var c_at := c.pos + Vector2(0, -_top(c))
		_add({"kind": "lines", "pos": c_at, "life": 8, "size": 0.8, "color": C_STONE[2]})


# ------------------------------------------------------------------ knockouts

func _ko(c: CreatureSim) -> void:
	var ko: Dictionary = c.def.get("ko_fx", {})
	match String(ko.get("style", "")):
		"scatter":
			_later(0.5, _scatter.bind(c))
		"crack":
			var ends := _crack_body(c, ko)
			_later(0.5, _gush.bind(c, ko, ends))
			_later(20.0, _rubble.bind(c))
		"crumble":
			_crack_body(c, ko)
			_later(14.0, _crumble.bind(c))
		"flop":
			_later(10.0, _flop_ko.bind(c))
		"deflate":
			_later(18.0, _deflate.bind(c))
		"hiss":
			_later(12.0, _hiss_ko.bind(c))
		"dirt":
			_later(10.0, _dirt_ko.bind(c))
		"cash":
			_later(10.0, _cash_ko.bind(c))
		"melt":
			_later(8.0, _melt_ko.bind(c))
		"timber":
			_timber(c)
			_later(16.0, _timber_land.bind(c, float(ko.get("length", 50))))


## Craglash: the stone neck comes apart and its pieces bounce away, then the body
## settles into rubble.
func _crumble(c: CreatureSim) -> void:
	var dir: Vector2 = _last_push.get(c.id, -c.facing)
	for i in 7:
		var v := dir.rotated(randf_range(-1.1, 1.1)) * randf_range(0.6, 1.8)
		_chunk(c.pos, randf_range(20, 36), v, randf_range(1.0, 2.2), randf_range(3.0, 4.0), C_GREY[randi() % 3],
			FOREVER, true)
	for i in 6:
		_chunk(c.pos, randf_range(6, 18), Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.2),
			randf_range(0.8, 1.8), randf_range(2.0, 3.0), C_CRAG[randi() % 3], FOREVER, true)
	for i in 8:
		_dust(c.pos + Vector2(randf_range(-14, 14), randf_range(-3, 3)), Vector2(randf_range(-0.5, 0.5), -0.4))
	_add({"kind": "ring", "pos": c.pos, "life": 16, "radius": 32.0})
	shake_out = maxf(shake_out, 3.0)
	cue.emit("stones_scatter")


## Cairn falls apart: each stone of the stack becomes its own piece and tumbles away
## from the final hit. The head rolls the farthest and wobbles to a stop.
func _scatter(c: CreatureSim) -> void:
	if c.id >= views.size() or views[c.id] == null:
		return
	var v: CreatureView = views[c.id]
	var snap := v.snapshot()
	v.ko_hidden = true
	var ko: Dictionary = c.def.get("ko_fx", {})
	var frame: Array = ko.get("frame", [0, 0])
	var fsize: Vector2 = snap["side_size"]
	var origin: Vector2 = snap["side_origin"]
	var flip := bool(snap["flip"])
	var dir: Vector2 = _last_push.get(c.id, -c.facing)
	var pieces: Array = ko.get("pieces", [])
	if pieces.is_empty():
		pieces = _scatter_bands(c, origin.y, fsize.y)
	for i in pieces.size():
		var y0 := int(pieces[i][0])
		var y1 := int(pieces[i][1])
		var zc := origin.y - (y0 + y1) * 0.5
		var head := i == 0
		var spread := dir.rotated(randf_range(-0.8, 0.8))
		var speed := randf_range(0.7, 1.6) + (1.3 if head else 0.0)
		_add({"kind": "chunk", "piece": true, "tex": snap["side_tex"], "flip": flip,
			"region": Rect2(int(frame[1]) * fsize.x, int(frame[0]) * fsize.y + y0, fsize.x, y1 - y0),
			"ox": origin.x, "band_c": (y0 + y1) * 0.5,
			"pos": c.pos + Vector2(randf_range(-2, 2), randf_range(-1, 1)), "z": zc,
			"vel": spread * speed, "vz": randf_range(1.0, 2.2) + zc * 0.025,
			"rot": 0.0, "vrot": randf_range(-0.25, 0.25), "bounce": 0.4,
			"roll": head, "radius": 6.0, "walls": true, "life": FOREVER,
			"x_eyes": ko.get("x_eyes", []) if head else []})
	for i in 5:
		_chunk(c.pos, randf_range(10, 22), Vector2.from_angle(randf() * TAU) * randf_range(0.5, 1.5),
			randf_range(1.0, 2.0), 2.0, C_PEBBLE[randi() % 2], FOREVER, true)
	for i in 6:
		_dust(c.pos + Vector2(randf_range(-10, 10), randf_range(-3, 3)), Vector2(randf_range(-0.5, 0.5), -0.4))
	_add({"kind": "ring", "pos": c.pos, "life": 16, "radius": 30.0})
	shake_out = maxf(shake_out, 3.0)
	cue.emit("stones_scatter")


## Scatter bands for a fighter whose ko_fx names no "pieces": four even bands from the
## top of the figure (`fx_top` above the feet) down to the feet, head first.
func _scatter_bands(c: CreatureSim, feet_y: float, frame_h: float) -> Array:
	var top := clampf(feet_y - _top(c) - 4.0, 0.0, feet_y)
	var bottom := minf(feet_y + 2.0, frame_h)
	var out: Array = []
	var n := 4
	for i in n:
		out.append([int(lerpf(top, bottom, float(i) / n)), int(lerpf(top, bottom, float(i + 1) / n))])
	return out


## Culvert's concrete cracks under the final blow. Returns the crack ends, where water
## will burst out, relative to the feet.
func _crack_body(c: CreatureSim, ko: Dictionary) -> Array:
	var body := Vector2(0, -float(ko.get("body_z", 12)))
	var rx := float(ko.get("body_rx", 13))
	var ry := float(ko.get("body_ry", 9))
	var lines: Array = []
	var ends: Array = []
	var n := int(ko.get("cracks", 5))
	for i in n:
		var a := TAU * i / n + randf_range(-0.3, 0.3)
		var cur := body + Vector2(randf_range(-2, 2), randf_range(-1, 1))
		var pts := PackedVector2Array([cur])
		for j in 3:
			a += randf_range(-0.6, 0.6)
			var nxt := cur + Vector2(cos(a), sin(a) * 0.8) * randf_range(3.0, 5.0)
			var rel := nxt - body
			if (rel.x * rel.x) / (rx * rx) + (rel.y * rel.y) / (ry * ry) > 1.0:
				break
			cur = nxt
			pts.append(cur)
		lines.append(pts)
		ends.append(cur)
	_add({"kind": "bodycrack", "id": c.id, "lines": lines, "life": 46, "grow": 14.0, "fade": 28.0, "real": true})
	cue.emit("crack")
	return ends


func _gush(c: CreatureSim, ko: Dictionary, ends: Array) -> void:
	var body_z := float(ko.get("body_z", 12))
	for i in 16:
		var e: Vector2 = ends[randi() % ends.size()]
		var d := (e + Vector2(0, body_z)).normalized()
		_drop(c.pos + Vector2(e.x, 0), -e.y, Vector2(d.x, d.y * 0.5) * randf_range(1.0, 2.2), randf_range(1.2, 2.6), true,
			Color(0, 0, 0, 0), Vector2(2, 2))
	_add({"kind": "puddle", "pos": c.pos + Vector2(0, 2), "radius": float(ko.get("puddle", 30)), "ry": 0.32,
		"grow": 100.0, "life": FOREVER})
	_add({"kind": "emit", "life": 80, "every": 1.0, "acc": 0.0, "fn": _gush_tick.bind(c, ends, body_z)})
	shake_out = maxf(shake_out, 2.5)
	cue.emit("water_gush")


## Water keeps pouring out of the cracks, weaker over time, lower as the body slumps.
func _gush_tick(k: float, c: CreatureSim, ends: Array, body_z: float) -> void:
	var sink := clampf(1.0 - c.state_t / 22.0, 0.4, 1.0)
	for j in 2:
		var e: Vector2 = ends[randi() % ends.size()]
		var d := (e + Vector2(0, body_z)).normalized()
		_drop(c.pos + Vector2(e.x * sink, randf_range(-1, 1)), maxf(2.0, -e.y * sink),
			Vector2(d.x, d.y * 0.5) * randf_range(0.4, 1.4), randf_range(0.5, 2.0) * (1.0 - k * 0.7), true)


func _rubble(c: CreatureSim) -> void:
	for i in 8:
		var v := Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5))
		_chunk(c.pos + Vector2(randf_range(-8, 8), randf_range(-2, 2)), randf_range(4, 12), v, randf_range(0.8, 1.8),
			randf_range(2.0, 4.0), C_CON[randi() % 3], FOREVER, true)
	for i in 5:
		_dust(c.pos + Vector2(randf_range(-12, 12), randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.4))


# ------------------------------------------------------------------ helpers

## Shaved Ice Spray: shards fanning out over the cone ahead.
func _ice_spray(c: CreatureSim, r: float, cone: float) -> void:
	var half := acos(clampf(cone, -1.0, 1.0))
	var head := c.pos + Vector2(0, -_top(c) + 8.0)
	for i in 14:
		var d := c.facing.rotated(randf_range(-half, half))
		_add({"kind": "streak", "a": head + d * 6.0, "b": head + d * r * randf_range(0.6, 1.1) + Vector2(0, 10),
			"life": 9, "color": Color(C_ICE[2], 0.9)})
		_px(head + d * 8.0, d * randf_range(1.2, 2.4), C_ICE[randi() % 3], 18)
	cue.emit("shards")


## Runoff: a sheet of water fanning out over the cone ahead, foam at its edge.
func _water_fan(c: CreatureSim, at: Vector2, r: float, cone: float) -> void:
	var half := acos(clampf(cone, -1.0, 1.0))
	var from := c.pos + Vector2(0, -6.0)
	for i in 18:
		var d := c.facing.rotated(randf_range(-half, half))
		var far := from + d * r * randf_range(0.5, 1.05)
		_add({"kind": "streak", "a": from + d * 8.0, "b": far, "life": 10,
			"color": Color(C_WATER_L if i % 3 else C_WATER, 0.85)})
		_add({"kind": "puddle", "pos": far, "radius": randf_range(3.0, 6.0), "ry": 0.5, "grow": 3.0,
			"life": 30.0, "fade": 20.0, "color": Color(C_WATER, 0.35)})
		_px(from + d * 10.0, d * randf_range(1.5, 3.0) + Vector2(0, -0.6), C_FOAM if i % 2 else C_WATER_L, 16)
	_add({"kind": "ring", "pos": at, "life": 10, "radius": r * 0.5, "color": Color(C_FOAM, 0.7)})
	cue.emit("wave")


## Flavor Blast: a ring of ice bursting out all around, shards and frost.
func _ice_blast(at: Vector2, r: float) -> void:
	_add({"kind": "ring", "pos": at, "life": 20, "radius": r + 8.0, "color": C_ICE[2]})
	_add({"kind": "ring", "pos": at, "life": 14, "radius": r * 0.6, "color": C_ICE[1]})
	_add({"kind": "puddle", "pos": at, "radius": r * 0.8, "ry": 1.0, "grow": 6.0, "life": 140.0, "fade": 60.0,
		"color": Color(C_ICE[2], 0.6)})
	for i in 16:
		var a := TAU * i / 16.0
		_chunk(at + Vector2(cos(a), sin(a) * 0.5) * 8.0, 4.0, Vector2(cos(a), sin(a) * 0.5) * randf_range(1.0, 2.2),
			randf_range(1.0, 2.2), randf_range(1.5, 2.5), C_ICE[randi() % 3], 40.0)
	shake_out = maxf(shake_out, 4.0)


## Sno Mercy melts: a spreading puddle of syrup and slush, a few last drips.
func _melt_ko(c: CreatureSim) -> void:
	_add({"kind": "puddle", "pos": c.pos, "radius": 10.0, "ry": 0.45, "grow": 12.0, "life": FOREVER, "fade": 1.0,
		"color": Color(C_SYRUP[0], 0.75)})
	_add({"kind": "puddle", "pos": c.pos + Vector2(4, 1), "radius": 6.0, "ry": 0.45, "grow": 8.0, "life": FOREVER,
		"fade": 1.0, "color": Color(C_ICE[2], 0.6)})
	for i in 8:
		_drop(c.pos + Vector2(randf_range(-8, 8), 0), randf_range(6, 20), Vector2.ZERO, 0.0, false, C_SYRUP[randi() % 3])
	cue.emit("melt")


## Syrup Slick puddles, from the simulation's zones: a sticky pool that fades as it dries.
func _draw_zones(ci: CanvasItem) -> void:
	for z in sim.zones:
		var at: Vector2 = z["pos"]
		var r := float(z["radius"])
		var a := clampf(float(z["ticks"]) / 40.0, 0.0, 1.0)
		ci.draw_set_transform(at.round(), 0.0, Vector2.ONE)
		ci.draw_circle(Vector2.ZERO, r, Color(C_SYRUP[0], 0.45 * a))
		ci.draw_circle(Vector2(-r * 0.3, -r * 0.1), r * 0.45, Color(C_SYRUP[1], 0.35 * a))
		ci.draw_circle(Vector2(r * 0.35, r * 0.15), r * 0.4, Color(C_SYRUP[2], 0.35 * a))
		ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1, 1, 1, 0.35 * a), 1.0)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if (_tick / 8) % 3 == 0:
			var hsh := int(at.x * 13.0 + at.y * 7.0 + _tick)
			var g := at + Vector2(float(hsh % int(r)) - r * 0.5, float((hsh / 7) % int(r * 0.5)) - r * 0.25)
			ci.draw_rect(Rect2(g.round(), Vector2.ONE), Color(1, 1, 1, 0.6 * a))


## A puff of smoke: dust clouds and grey wisps.
func _smoke(at: Vector2, n: int) -> void:
	for i in n:
		var a := TAU * i / n + randf() * 0.4
		_dust(at + Vector2(cos(a) * 6.0, sin(a) * 3.0 - 10.0), Vector2(cos(a), sin(a) * 0.5 - 0.3) * 0.5)
	for i in n:
		_px(at + Vector2(randf_range(-8, 8), -randf_range(4, 28)), Vector2(randf_range(-0.3, 0.3), -0.4), C_GREY[2], 18)


## Coins and bills bursting out of the bag.
func _cash_burst(at: Vector2, n: int) -> void:
	for i in n:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(0.5, 1.6)
		_chunk(at + Vector2(0, 10), 10.0, v, randf_range(1.2, 2.4), 1.5, C_GOLD[randi() % 3], 50.0)
	for i in n / 2:
		_px(at + Vector2(randf_range(-6, 6), randf_range(-6, 6)), Vector2(randf_range(-0.8, 0.8), randf_range(-1.2, -0.3)),
			C_CASH[randi() % 2], 30)
	cue.emit("coins")


## Sneaky Pete goes down and the bag bursts: bills flutter, coins roll away.
func _cash_ko(c: CreatureSim) -> void:
	_cash_burst(c.pos + Vector2(0, -10), 16)
	for i in 6:
		_chunk(c.pos, randf_range(4, 12), Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.2),
			randf_range(0.8, 1.6), 1.5, C_GOLD[randi() % 3], FOREVER, true)


## Dirt bursting up out of the floor (Pickaxe Pop-Up, Burrow's exit).
func _dirt_burst(at: Vector2, r: float) -> void:
	for i in 12:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.2)
		_chunk(at + v * 4.0, 2.0, v, randf_range(1.8, 3.2), randf_range(1.5, 3.0), C_DIRT[randi() % 3], 50.0)
	for i in 5:
		_dust(at + Vector2(randf_range(-r, r) * 0.6, randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.5))
	_add({"kind": "ring", "pos": at, "life": 14, "radius": r + 6.0, "color": C_DIRT[2]})
	_add({"kind": "puddle", "pos": at, "radius": r * 0.6, "ry": 0.45, "grow": 3.0, "life": 120.0, "fade": 50.0,
		"color": Color(C_DIRT[0], 0.7)})


## Cave-In: the floor gives way, rocks rain into the hole, dust rolls out.
func _cave_in(at: Vector2, r: float) -> void:
	_add({"kind": "ring", "pos": at, "life": 20, "radius": r + 10.0, "color": C_DIRT[2]})
	_add({"kind": "puddle", "pos": at, "radius": r * 0.9, "ry": 1.0, "grow": 6.0, "life": 160.0, "fade": 60.0,
		"color": Color(C_DIRT[0], 0.8)})
	for i in 14:
		var off := Vector2(randf_range(-r, r), randf_range(-r, r))
		_chunk(at + off, randf_range(30, 70), Vector2(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2)), 0.0,
			randf_range(2.0, 4.0), C_STONE[randi() % 3], 60.0)
	for i in 10:
		var a := TAU * i / 10.0
		_dust(at + Vector2(cos(a), sin(a)) * r * 0.8, Vector2(cos(a), sin(a) * 0.5) * 0.6)
	shake_out = maxf(shake_out, 4.0)
	cue.emit("cave_in")


## Headlamp Flash: a fan of light from the helmet across the reach.
func _headlamp(c: CreatureSim, reach: float) -> void:
	var head := c.pos + Vector2(c.facing.x * 8.0, -_top(c) + 6.0)
	for i in 7:
		var d := c.facing.rotated(randf_range(-0.5, 0.5))
		_add({"kind": "streak", "a": head + d * 4.0, "b": head + d * reach * randf_range(0.8, 1.2), "life": 10,
			"color": Color(C_LAMP, 0.85)})
	_add({"kind": "glint", "pos": head, "life": 10, "color": C_LAMP})
	_add({"kind": "lines", "pos": head + c.facing * 10.0, "life": 8, "size": 1.0, "color": C_LAMP})


## Digby goes down in a puff of dust, clods of dirt scattering.
func _dirt_ko(c: CreatureSim) -> void:
	for i in 8:
		_dust(c.pos + Vector2(randf_range(-12, 12), randf_range(-3, 3)), Vector2(randf_range(-0.5, 0.5), -0.4))
	for i in 8:
		_chunk(c.pos, randf_range(4, 14), Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.2),
			randf_range(1.0, 2.0), randf_range(1.5, 2.5), C_DIRT[randi() % 3], FOREVER, true)
	cue.emit("pop")


## Hissy Fitz goes down with a last long hiss: green puffs and venom dripping.
func _hiss_ko(c: CreatureSim) -> void:
	_text(c.pos + Vector2(0, -_top(c) - 6), "hssssss...", C_VENOM[2], 8, 70.0)
	for i in 8:
		_bubble(c.pos + Vector2(randf_range(-14, 14), 0), randf_range(4.0, 24.0))
	for i in 6:
		_drop(c.pos + Vector2(randf_range(-12, 12), randf_range(-2, 2)), randf_range(8, 20), Vector2.ZERO, 0.0, false,
			C_VENOM[1])
	cue.emit("hiss")


## A splash of venom: green drops flung out and a spreading green stain.
func _venom_splat(at: Vector2, z: float, n: int) -> void:
	for i in n:
		_drop(at, z, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.3), randf_range(0.8, 2.0), false,
			C_VENOM[randi() % 3])
	_add({"kind": "puddle", "pos": at, "radius": 4.0, "ry": 0.45, "grow": 4.0, "life": 70.0, "fade": 30.0,
		"color": Color(C_VENOM[0], 0.7)})


## A poison bubble: rises from `z` above `at`, wobbling, and pops.
func _bubble(at: Vector2, z: float) -> void:
	_add({"kind": "bubble", "pos": at, "z": z, "life": randf_range(18.0, 28.0), "r": randf_range(1.0, 2.2),
		"wob": randf() * TAU})


func _owner_has_venom(owner: CreatureSim) -> bool:
	var mvs := owner.moves()
	for m in mvs:
		var mv: Dictionary = mvs[m]
		if mv.has("projectile") and String(mv.get("fx", {}).get("projectile", "")) == "venom":
			return true
	return false


func _creature(i: int) -> CreatureSim:
	return sim.creatures[i] if i >= 0 and i < sim.creatures.size() else null


func _note_push(e: Dictionary) -> Vector2:
	var a := int(e.get("attacker", -1))
	var d := int(e.get("target", -1))
	if a < 0 or d < 0 or a >= sim.creatures.size() or d >= sim.creatures.size():
		return Vector2.RIGHT
	var push := sim.creatures[d].pos - sim.creatures[a].pos
	push = push.normalized() if push.length_squared() > 0.001 else sim.creatures[a].facing
	_last_push[d] = push
	return push


func _add(p: Dictionary) -> void:
	p["t"] = 0.0
	_incoming.append(p)


func _later(delay: float, fn: Callable) -> void:
	_add({"kind": "later", "life": maxf(0.01, delay), "on_end": fn})


func _dust(pos: Vector2, vel: Vector2) -> void:
	_add({"kind": "dust", "pos": pos, "vel": vel, "life": 16})


func _px(pos: Vector2, vel: Vector2, col: Color, life: float) -> void:
	_add({"kind": "px", "pos": pos, "vel": vel, "color": col, "life": life})


func _chunk(pos: Vector2, z: float, vel: Vector2, vz: float, size: float, col: Color, life: float,
		walls := false) -> void:
	_add({"kind": "chunk", "pos": pos, "z": z, "vel": vel, "vz": vz, "size": size, "color": col,
		"life": life, "rot": randf() * TAU, "vrot": randf_range(-0.4, 0.4), "bounce": 0.35, "walls": walls})


func _drop(pos: Vector2, z: float, vel: Vector2, vz: float, pool: bool, col := Color(0, 0, 0, 0),
		size := Vector2(1, 2)) -> void:
	if col.a == 0.0:
		col = C_WATER if randf() < 0.6 else C_WATER_L
	_add({"kind": "drop", "pos": pos, "z": z, "vel": vel, "vz": vz, "color": col, "life": 120.0, "pool": pool,
		"dsize": size})


func _text(pos: Vector2, text: String, color: Color, size := 8, life := 40.0) -> void:
	_add({"kind": "text", "pos": pos, "text": text, "color": color, "size": size, "life": life})


## Orbiting pebbles while Haymaker charges: more of them, higher, the longer it's held.
func _pebbles(c: CreatureSim, charge: int) -> Array:
	var cmax := float(c.move_def().get("charge_max", 30))
	var k := clampf(charge / cmax, 0.0, 1.0)
	var n := 1 + int(k * 4.0)
	var out: Array = []
	for i in n:
		var a := c.anim_t * 0.16 + TAU * i / n
		var z := 4.0 + 16.0 * k + sin(a * 1.7 + i) * 1.5
		var g := c.pos + Vector2(cos(a) * 15.0, sin(a) * 5.0)
		out.append({"ground": g, "z": z, "front": sin(a) > 0.0, "full": k >= 1.0})
	return out


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	_paint(self, false)


func _paint(ci: CanvasItem, floor_layer: bool) -> void:
	if floor_layer:
		if _dark > 0.0:
			ci.draw_rect(Rect2(-ArenaView.MARGIN, (sim.arena_size() if sim != null else SimDefs.arena_size()) + ArenaView.MARGIN * 2.0),
				Color(C_DIM, _dark))
		_draw_pads(ci)
		for p in _parts:  # flat things first, so debris sits on top of puddles and cracks
			if String(p["kind"]) in ["puddle", "decal", "ripple", "lost"]:
				_draw_part(ci, p)
		for p in _parts:
			var kind := String(p["kind"])
			if kind == "ghost" or (kind in ["spire", "root"] and not bool(p.get("front", false))):
				_draw_part(ci, p)
			elif p.has("vz") and float(p["z"]) > 1.0:
				_draw_shadow(ci, p)
			elif kind == "chunk" and bool(p.get("grounded", false)):
				_draw_part(ci, p)
		if sim != null:
			_draw_creature_extras(ci, true)
		return

	if sim != null:
		_draw_projectiles(ci)
	for p in _parts:
		var kind := String(p["kind"])
		if kind in ["puddle", "decal", "ripple", "ghost", "later", "emit", "lost"]:
			continue
		if p.has("orbit") and not shown(_creature(int(p["orbit"]))):
			continue  # circling a fighter the local team can't see
		if kind in ["spire", "root"] and not bool(p.get("front", false)):
			continue
		if kind == "chunk" and bool(p.get("grounded", false)):
			continue
		_draw_part(ci, p)
	if sim != null:
		_draw_creature_extras(ci, false)
		_draw_side_marks(ci)
	if _rain > 0.0:
		_draw_rain(ci)


func _alpha(p: Dictionary) -> float:
	var life := float(p["life"])
	var t := float(p["t"])
	if p.has("fade"):
		return clampf((life - t) / float(p["fade"]), 0.0, 1.0)
	return 1.0


func _draw_part(ci: CanvasItem, p: Dictionary) -> void:
	var t := float(p["t"])
	var life := float(p["life"])
	var k := clampf(t / life, 0.0, 1.0)
	match String(p["kind"]):
		"lost":
			# Where the local team last saw a fighter: a faint ring and a "?", fading.
			var pos: Vector2 = p["pos"]
			var a := 0.5 * (1.0 - k)
			ci.draw_arc(pos.round(), float(p["r"]) + 3.0, 0.0, TAU, 24, Color(C_WARN, a), 1.0)
			var q := (pos + Vector2(0, -float(p["top"]) * 0.6)).round()
			ci.draw_string_outline(_font, q + Vector2(-10, 0), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, 10, 2,
				Color(C_OUTLINE, a))
			ci.draw_string(_font, q + Vector2(-10, 0), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, 10, Color(C_WARN, a))
		"spark":
			var pos: Vector2 = p["pos"]
			var s: float = p["scale"]
			var frame := mini(int(k * 4.0), 3)
			var size := Vector2(16, 16) * s
			ci.draw_texture_rect_region(SHEET, Rect2((pos - size * 0.5).round(), size), Rect2(frame * 16, 0, 16, 16))
		"dust":
			var pos: Vector2 = p["pos"]
			var v: Vector2 = p["vel"]
			var frame := mini(int(k * 4.0), 3)
			ci.draw_texture_rect_region(SHEET, Rect2((pos + v * t - Vector2(8, 12)).round(), Vector2(16, 16)), Rect2(frame * 16, 16, 16, 16))
		"ping":
			var pos: Vector2 = p["pos"]
			var col := Color("ff5a5a") if bool(p["attack"]) else Color("7cf27c")
			col.a = 1.0 - k
			var r := lerpf(9.0, 3.0, k)
			ci.draw_arc(pos, r, 0.0, TAU, 20, col, 1.5)
			for ang in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
				var dir := Vector2.from_angle(ang)
				ci.draw_line(pos + dir * (r + 4.0), pos + dir * (r + 1.0), col, 1.0)
		"ring":
			var pos: Vector2 = p["pos"]
			var r := lerpf(4.0, float(p["radius"]), sqrt(k))
			var col: Color = p.get("color", Color(1.0, 0.92, 0.7))
			col.a = 1.0 - k
			ci.draw_arc(pos, r, 0.0, TAU, 40, col, 2.0)
		"ripple":
			var pos: Vector2 = p["pos"]
			var r := lerpf(3.0, float(p["radius"]), sqrt(k))
			ci.draw_arc(pos, r, 0.0, TAU, 32, Color(C_WATER_L, 0.8 * (1.0 - k)), 1.5)
		"text":
			var pos: Vector2 = p["pos"]
			var col: Color = p["color"]
			col.a = 1.0 - maxf(0.0, k - 0.6) / 0.4
			var at := pos + Vector2(-40, -t * 0.5)
			var fs: int = p["size"]
			ci.draw_string_outline(_font, at, String(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, 3, Color(0.1, 0.08, 0.1, col.a))
			ci.draw_string(_font, at, String(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, col)
		"glint":
			# A four-point star that flares and shrinks over the windup.
			var pos: Vector2 = Vector2(p["pos"]).round()
			var col: Color = p["color"]
			var r := 3.0 + 7.0 * sin(clampf(k * 1.4, 0.0, 1.0) * PI)
			var w := 1.5
			ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(w, -w),
				pos + Vector2(r, 0), pos + Vector2(w, w), pos + Vector2(0, r), pos + Vector2(-w, w),
				pos + Vector2(-r, 0), pos + Vector2(-w, -w)]), col)
			ci.draw_rect(Rect2(pos - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)
		"px":
			var col: Color = p["color"]
			col.a = 1.0 - k
			var pos: Vector2 = p["pos"]
			ci.draw_rect(Rect2(pos.round(), Vector2.ONE * (2.0 if k < 0.4 else 1.0)), col)
		"bubble":
			var at := Vector2(p["pos"]) + Vector2(sin(float(p["wob"]) + t * 0.35) * 1.5, -float(p["z"]) - t * 0.45)
			var r := float(p["r"])
			if k < 0.9:
				ci.draw_circle(at.round(), r + 1.0, Color(C_OUTLINE, 0.7))
				ci.draw_circle(at.round(), r, C_VENOM[1])
				ci.draw_rect(Rect2((at + Vector2(-r * 0.5, -r * 0.5)).round(), Vector2.ONE), C_VENOM[2])
			else:
				for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
					ci.draw_rect(Rect2((at + d * (r + 1.0)).round(), Vector2.ONE), C_VENOM[2])
		"streak":
			var col: Color = p["color"]
			col.a *= 1.0 - k
			ci.draw_line(p["a"], p["b"], col, 1.0)
		"suck":
			var a: Vector2 = p["from"]
			var b: Vector2 = p["to"]
			var sc: Color = p.get("color", Color.WHITE)
			ci.draw_line(a.lerp(b, k), a.lerp(b, minf(1.0, k + 0.35)), Color(sc, 0.7 * (1.0 - k * 0.5)), 1.0)
		"smear":
			var col: Color = p["color"]
			col.a *= pow(1.0 - k, 0.7)
			ci.draw_colored_polygon(p["pts"], col)
		"lines":
			var pos: Vector2 = p["pos"]
			var size := float(p["size"])
			var col: Color = p["color"]
			col.a = 1.0 - k
			for i in 8:
				var dir := Vector2.from_angle(TAU * i / 8.0 + 0.2)
				ci.draw_line(pos + dir * lerpf(5.0, 12.0, k) * size, pos + dir * lerpf(10.0, 20.0, k) * size, col, 1.0)
		"ghost":
			var tint: Color = p["tint"]
			tint.a *= 1.0 - k
			var feet: Vector2 = p["feet"]
			var origin: Vector2 = p["origin"]
			var size: Vector2 = p["frame_size"]
			ci.draw_set_transform(feet, 0.0, Vector2(-1.0 if bool(p["flip"]) else 1.0, 1.0))
			ci.draw_texture_rect_region(p["tex"], Rect2(-origin.x, -origin.y, size.x, size.y), p["region"], tint)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"chunk":
			_draw_chunk(ci, p)
		"drop":
			var col: Color = p["color"]
			var at := (Vector2(p["pos"]) + Vector2(0, -float(p["z"]))).round()
			ci.draw_rect(Rect2(at, p.get("dsize", Vector2(1, 2))), col)
		"puddle":
			var pos: Vector2 = p["pos"]
			var grow := clampf(t / float(p.get("grow", 1.0)), 0.0, 1.0)
			var r := float(p["radius"]) * (1.0 - pow(1.0 - grow, 2.0))
			if r < 0.5:
				return
			var a := 0.55 * _alpha(p)
			var ry := float(p["ry"])
			ci.draw_set_transform(pos, 0.0, Vector2(1.0, ry))
			if p.has("color"):  # a dark mark rather than water (Tenderize's tooth marks)
				var mc: Color = p["color"]
				ci.draw_circle(Vector2.ZERO, r, Color(mc, mc.a * _alpha(p)))
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				return
			ci.draw_circle(Vector2.ZERO, r, Color(C_WATER, a))
			if r > 6.0:
				ci.draw_arc(Vector2.ZERO, r * 0.7, PI * 1.1, PI * 1.5, 8, Color(C_WATER_L, a), 1.0 / ry)
				var gl := Vector2.from_angle(_tick * 0.03) * r * 0.5
				ci.draw_circle(gl, 1.0, Color(C_FOAM, a))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"decal":
			var grow := clampf(t / float(p["grow"]), 0.0, 1.0)
			var col := Color(C_CRACK, 0.85 * _alpha(p))
			for pts in p["lines"]:
				_draw_partial_line(ci, pts, grow, col)
		"spire":
			_draw_spire(ci, p)
		"root":
			_draw_root(ci, p)
		"leaf":
			var at := (Vector2(p["pos"]) + Vector2(0, -float(p.get("z", 0.0)))).round()
			var col: Color = p["color"]
			col.a = clampf((life - t) / 12.0, 0.0, 1.0)
			var flat := int(float(p.get("rot", t * 0.3)) * 2.0) % 2 == 0
			ci.draw_rect(Rect2(at, Vector2(2, 1) if flat else Vector2(1, 2)), col)
			ci.draw_rect(Rect2(at + (Vector2(2, 0) if flat else Vector2(0, 2)), Vector2.ONE), Color(C_LEAF[0], col.a))
		"whirl":
			# A curved gust of wind sweeping round a spin.
			var pos: Vector2 = p["pos"]
			var r := float(p["radius"])
			var a0 := float(p["start"]) + k * 2.5
			ci.draw_set_transform(pos, 0.0, Vector2(1.0, 0.45))
			ci.draw_arc(Vector2.ZERO, r, a0, a0 + 1.6, 12, Color(1, 1, 1, 0.55 * (1.0 - k)), 1.5 / 0.45)
			ci.draw_arc(Vector2.ZERO, r * 0.7, a0 + 2.6, a0 + 3.8, 10, Color(C_LEAF[2], 0.5 * (1.0 - k)), 1.0 / 0.45)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"bodycrack":
			if int(p["id"]) >= sim.creatures.size():
				return
			var c := sim.creatures[int(p["id"])]
			var base := c.pos.round()
			var grow := clampf(t / float(p["grow"]), 0.0, 1.0)
			var a := clampf((life - t) / (life - float(p["fade"])), 0.0, 1.0)
			for pts in p["lines"]:
				var moved := PackedVector2Array()
				for q in pts:
					moved.append(base + Vector2(q))
				_draw_partial_line(ci, moved, grow, Color(C_CRACK, a))
				if grow >= 1.0:
					ci.draw_rect(Rect2(moved[moved.size() - 1].round(), Vector2.ONE), Color(C_WATER_L, a))


func _draw_partial_line(ci: CanvasItem, pts: PackedVector2Array, grow: float, col: Color) -> void:
	var n := pts.size() - 1
	if n < 1:
		return
	var upto := grow * n
	for i in n:
		if i >= upto:
			break
		var b := pts[i + 1] if i + 1 <= upto else pts[i].lerp(pts[i + 1], upto - i)
		ci.draw_line(pts[i], b, col, 1.0)


func _draw_chunk(ci: CanvasItem, p: Dictionary) -> void:
	var at := (Vector2(p["pos"]) + Vector2(0, -float(p["z"]))).round()
	var a := 1.0
	var life := float(p["life"])
	if life < FOREVER:
		a = clampf((life - float(p["t"])) / 12.0, 0.0, 1.0)
	if bool(p.get("piece", false)):
		var region: Rect2 = p["region"]
		var h := region.size.y
		var ox := float(p["ox"])
		ci.draw_set_transform(at, float(p["rot"]), Vector2(-1.0 if bool(p["flip"]) else 1.0, 1.0))
		ci.draw_texture_rect_region(p["tex"], Rect2(-ox, -h * 0.5, region.size.x, h), region)
		var eyes: Array = p.get("x_eyes", [])
		var vel: Vector2 = p["vel"]
		if not eyes.is_empty() and bool(p.get("grounded", false)) and vel.length() < 0.15 \
				and absf(float(p.get("vrot", 0.0))) < 0.02:
			var bc := float(p["band_c"])
			for e in eyes:
				var ex := float(e[0]) - ox
				var ey := float(e[1]) - bc
				ci.draw_rect(Rect2(ex - 1, ey - 1, 3, 3), C_HEAD)
				ci.draw_line(Vector2(ex - 1, ey - 1), Vector2(ex + 2, ey + 2), C_OUTLINE, 1.0)
				ci.draw_line(Vector2(ex - 1, ey + 2), Vector2(ex + 2, ey - 1), C_OUTLINE, 1.0)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var s := float(p["size"])
	var col: Color = p["color"]
	col.a = a
	ci.draw_set_transform(at, float(p["rot"]), Vector2.ONE)
	ci.draw_rect(Rect2(-s * 0.5 - 0.5, -s * 0.4 - 0.5, s + 1.0, s * 0.8 + 1.0), Color(C_OUTLINE, a * 0.8))
	ci.draw_rect(Rect2(-s * 0.5, -s * 0.4, s, s * 0.8), col)
	if s >= 2.5:
		ci.draw_rect(Rect2(-s * 0.5, -s * 0.4, s, 1.0), Color(col.lightened(0.3), a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_shadow(ci: CanvasItem, p: Dictionary) -> void:
	var s := 2.0 if String(p["kind"]) == "drop" else (8.0 if bool(p.get("piece", false)) else float(p.get("size", 2.0)))
	var z := float(p["z"])
	var a := clampf(0.3 - z * 0.006, 0.08, 0.3)
	ci.draw_set_transform(Vector2(p["pos"]), 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, s * 0.6, Color(0, 0, 0, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_spire(ci: CanvasItem, p: Dictionary) -> void:
	var t := float(p["t"]) - float(p.get("delay", 0.0))
	if t < 0.0:
		return
	var life := float(p["life"]) - float(p.get("delay", 0.0))
	var rise := clampf(t / 4.0, 0.0, 1.0)
	var sink := clampf((life - t) / 8.0, 0.0, 1.0)
	var h := float(p["h"]) * (1.0 - pow(1.0 - rise, 3.0)) * sink
	if h < 5.0:
		return  # too short to draw as a shape without it folding over
	var w := float(p["w"])
	var b: Vector2 = Vector2(p["pos"]).round()
	ci.draw_set_transform(b, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, w + 2.0, Color(0, 0, 0, 0.3))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var outline := PackedVector2Array([b + Vector2(-w - 1, 1), b + Vector2(-w * 0.6, -h * 0.5),
		b + Vector2(-w * 0.2, -h * 0.62), b + Vector2(0, -h - 1), b + Vector2(w * 0.35, -h * 0.72),
		b + Vector2(w * 0.55, -h * 0.5), b + Vector2(w + 1, 1)])
	ci.draw_colored_polygon(outline, C_OUTLINE)
	var body := PackedVector2Array([b + Vector2(-w, 0), b + Vector2(-w * 0.6, -h * 0.5 + 1),
		b + Vector2(-w * 0.2, -h * 0.62 + 1), b + Vector2(0, -h), b + Vector2(w * 0.35, -h * 0.72 + 1),
		b + Vector2(w * 0.55, -h * 0.5 + 1), b + Vector2(w, 0)])
	ci.draw_colored_polygon(body, C_STONE[1])
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-w, 0), b + Vector2(-w * 0.6, -h * 0.5 + 1),
		b + Vector2(-w * 0.2, -h * 0.62 + 1), b + Vector2(0, -h), b + Vector2(-w * 0.15, 0)]), C_STONE[2])
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(w * 0.35, -h * 0.72 + 1),
		b + Vector2(w * 0.55, -h * 0.5 + 1), b + Vector2(w, 0), b + Vector2(w * 0.3, 0)]), C_STONE[0])


## A root shooting up out of the floor: a tapered, bending wooden spike with a dirt ring.
func _draw_root(ci: CanvasItem, p: Dictionary) -> void:
	var t := float(p["t"]) - float(p.get("delay", 0.0))
	if t < 0.0:
		return
	var life := float(p["life"]) - float(p.get("delay", 0.0))
	var rise := clampf(t / 3.0, 0.0, 1.0)
	var sink := clampf((life - t) / 8.0, 0.0, 1.0)
	var h := float(p["h"]) * (1.0 - pow(1.0 - rise, 3.0)) * sink
	if h < 2.0:
		return
	var w := float(p["w"])
	var lean := float(p["lean"])
	var b: Vector2 = Vector2(p["pos"]).round()
	ci.draw_set_transform(b, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, w + 2.5, Color(0, 0, 0, 0.35))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tip := b + Vector2(lean * h, -h)
	var mid := b + Vector2(lean * h * 0.3 + w * 0.4, -h * 0.55)
	var outline := PackedVector2Array([b + Vector2(-w - 1, 1), mid + Vector2(-w * 0.6 - 1, 0), tip + Vector2(0, -1),
		mid + Vector2(w * 0.6 + 1, 0), b + Vector2(w + 1, 1)])
	ci.draw_colored_polygon(outline, C_OUTLINE)
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-w, 0), mid + Vector2(-w * 0.6, 0), tip,
		mid + Vector2(w * 0.6, 0), b + Vector2(w, 0)]), C_WOOD[2])
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-w, 0), mid + Vector2(-w * 0.6, 0), tip,
		mid + Vector2(-w * 0.1, 0), b + Vector2(-w * 0.2, 0)]), C_WOOD[3])
	if h > 10.0:
		ci.draw_rect(Rect2((mid + Vector2(w * 0.3, 2)).round(), Vector2(2, 1)), C_LEAF[1])


func _draw_projectiles(ci: CanvasItem) -> void:
	for pr in sim.projectiles:
		var pp: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		if not shown(_creature(int(pr["owner"]))) and not sight_to(pp):
			continue  # thrown from out of sight and still behind the fence or wall
		if bool(pr.get("lob", false)):
			if _proj_kind(pr) == "crane_bundle":
				PaperFx.draw_bundle(ci, pr, _tick)
			else:
				_draw_pinecone(ci, pr)
			continue
		if not _is_wave(pr):
			match _proj_kind(pr):
				"knife":
					_draw_thrown_knife(ci, pr)
				"mallet", "cleaver":
					_draw_spinner(ci, pr, _proj_kind(pr))
				"venom":
					_draw_venom(ci, pr)
				"head":
					_draw_long_bite(ci, pr)
				"tongue":
					_draw_tongue(ci, pr)
				"dart":
					PaperFx.draw_dart(ci, pr, _tick)
				"shuriken":
					PaperFx.draw_thrown_shuriken(ci, pr, _tick)
				"crane":
					PaperFx.draw_thrown_crane(ci, pr, _tick)
				"frog":
					PaperFx.draw_frog_shot(ci, pr, _tick)
				_:
					_draw_thrown_rod(ci, pr)
			continue
		if _is_wave(pr):
			_draw_wave(ci, pp.round(), vel)
			continue
		var frame := (_tick / 4) % 4
		var w := -16.0 if vel.x < 0.0 else 16.0
		ci.draw_texture_rect_region(SHEET, Rect2(pp.round() + Vector2(-w * 0.5, -14), Vector2(w, 16)),
			Rect2(frame * 16, 32, 16, 16))


## Which "projectile" fx the move that threw this uses ("rod" when it can't tell).
func _proj_kind(pr: Dictionary) -> String:
	var owner := _creature(int(pr["owner"]))
	if owner == null or not pr.has("move"):
		return "rod"
	var mv: Dictionary = owner.moves().get(String(pr["move"]), {})
	return String(mv.get("fx", {}).get("projectile", "rod"))


## Gulp in flight: Culvert's tongue, stretched from his open mouth to a round tip, with
## a few drops flung off it.
func _draw_tongue(ci: CanvasItem, pr: Dictionary) -> void:
	var owner := _creature(int(pr["owner"]))
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var tip := pp + Vector2(0, -12)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 4.0, Color(0, 0, 0, 0.25))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if owner != null:
		var mouth := owner.pos + owner.facing * 10.0 + Vector2(0, -_chest(owner) + 2.0)
		var n := maxi(2, int(mouth.distance_to(tip) / 4.0))
		for i in n + 1:
			var k := float(i) / n
			var at := mouth.lerp(tip, k) + Vector2(0, sin(k * PI) * -3.0)
			var w := 3.0 - k * 0.8
			ci.draw_circle(at, w + 1.0, C_OUTLINE)
		for i in n + 1:
			var k := float(i) / n
			var at := mouth.lerp(tip, k) + Vector2(0, sin(k * PI) * -3.0)
			ci.draw_circle(at, 3.0 - k * 0.8, C_TONGUE)
		if (_tick / 2) % 2 == 0:
			ci.draw_rect(Rect2((mouth.lerp(tip, 0.6) + Vector2(0, -4)).round(), Vector2.ONE), C_TONGUE_L)
	ci.draw_circle(tip, 5.0, C_OUTLINE)
	ci.draw_circle(tip, 4.0, C_TONGUE)
	ci.draw_circle(tip + Vector2(-1, -1), 1.3, C_TONGUE_L)


## Mountain Maw in flight: Craglash's stone neck stretched out from his shoulders to the
## flying head, jaws open, slab by slab.
func _draw_long_bite(ci: CanvasItem, pr: Dictionary) -> void:
	var owner := _creature(int(pr["owner"]))
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var d: Vector2 = Vector2(pr["vel"]).normalized()
	var head := pp + Vector2(0, -18)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.28))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if owner != null:
		var root := owner.pos + Vector2(owner.facing.x * 6.0, -_top(owner) + 12.0)
		var n := maxi(2, int(root.distance_to(head) / 6.0))
		for i in n:
			var k := float(i) / n
			var at := root.lerp(head, k) + Vector2(0, sin(k * PI) * -6.0)
			var w := 3.5 - k
			ci.draw_rect(Rect2((at - Vector2(w + 1, w + 1)).round(), Vector2(w * 2 + 2, w * 2 + 2)), C_OUTLINE)
			ci.draw_rect(Rect2((at - Vector2(w, w)).round(), Vector2(w * 2, w * 2)), C_CRAG[(i % 2) + 1])
	# the head: a heavy stone block with its jaws wide, teeth showing
	var side := Vector2(-d.y, d.x) * 1.7
	d = d * 1.7  # the head is drawn bigger than the neck slabs
	var jaw := 4.0 + 1.5 * float((_tick / 3) % 2)
	var top := PackedVector2Array([head - d * 6.0 - side * 5.0, head + d * 7.0 - side * 1.0 - side * jaw * 0.5,
		head + d * 7.0 - side * 0.5, head - d * 6.0 + side * 1.0])
	var bot := PackedVector2Array([head - d * 6.0 + side * 1.5, head + d * 6.0 + side * jaw * 0.5,
		head + d * 6.0 + side * (jaw * 0.5 + 2.5), head - d * 6.0 + side * 5.0])
	for poly: PackedVector2Array in [top, bot]:
		var grown := PackedVector2Array()
		var c: Vector2 = (poly[0] + poly[1] + poly[2] + poly[3]) / 4.0
		for q in poly:
			grown.append(c + (q - c) * 1.25)
		ci.draw_colored_polygon(grown, C_OUTLINE)
		ci.draw_colored_polygon(poly, C_CRAG[1])
	for k in 3:
		var tooth := head + d * (1.0 + k * 2.2) - side * 0.3
		ci.draw_rect(Rect2(tooth.round(), Vector2.ONE), Color.WHITE)
	ci.draw_rect(Rect2((head - d * 2.5 - side * 3.0).round(), Vector2(2, 1)), C_AMBER)  # the eye


## Who's who, and how they're doing: a health bar over each fighter, League-style.
## Its colour says whose it is (`rel` in side_marks: "self" green, "ally" blue, "enemy"
## red; "side" uses the side colours, red left and blue right, when nobody here plays or
## two local players face each other). Ticks every 25 health, a pale trail that drains
## after a hit, a stone segment for a shield (Stoneskin), a thin Surge strip under it,
## and the player label (P1, CPU...) above. Hidden once knocked out; an invisible fighter
## (Tiptoe) shows his bar only to his own side, faintly.
const PLATE_W := 30.0
const PLATE_H := 3.0
const HP_TICK := 25.0
const REL_COLORS := {"self": Color("6fcf5a"), "ally": Color("4aa8ff"), "enemy": Color("e5534b")}
const C_TRAIL := Color("f4e6c8")
const C_SHIELD := Color("d8d4cc")
var _trail := {}  ## creature -> [trail hp, ticks to hold before draining, last hp]


## Team Deathmatch spawn pads (set by main): a ring on the floor in the team's colour, and
## the seconds until someone comes back on it. Drawn as a true circle, like every floor area.
## Each: {"pos": Vector2, "color": Color, "count": seconds (0: nobody waiting)}.
var pads: Array = []
## King of the Crater's zone (set by main): {"pos", "radius", "color"}; empty when none.
var zone := {}
## The Caravan (set by main): {"pos", "heading", "radius", "state" (-1 back, 0 still,
## 1 pushed, 2 contested), "team" (the attackers), "travel" (px moved, turns the wheels)};
## empty when none.
var caravan := {}
## Capture the Flag's flags (set by main): each {"pos", "team", "state" (TeamSim.FLAG_*),
## "lift" (px above the floor: over a carrier's head), "back" (0..1 of a dropped flag's
## return timer left)}.
var flags: Array = []
## Capture the Flag's shrines (set by main): each {"pos", "radius", "kind" (haste, might),
## "side" claiming (-1), "claim" (0..1), "rest" (seconds until ready, 0: ready)}.
var shrines: Array = []
const SHRINE_COLORS := {"haste": Color("6fe0ff"), "might": Color("ff9a3c")}


func _draw_pads(ci: CanvasItem) -> void:
	if not caravan.is_empty():
		_draw_caravan(ci)
	for s in shrines:
		_draw_shrine(ci, s)
	if not shrines.is_empty():
		_draw_buffs(ci)
	for f in flags:
		_draw_flag(ci, f)
	if not zone.is_empty():
		var at: Vector2 = zone["pos"]
		var col: Color = zone["color"]
		var r: float = float(zone["radius"]) + 1.5 * sin(float(_tick) * 0.1)
		ci.draw_circle(at, r, Color(col, 0.12))
		ci.draw_arc(at, r, 0.0, TAU, 48, Color(col, 0.8), 2.0)
		ci.draw_arc(at, r * 0.7, float(_tick) * 0.02, float(_tick) * 0.02 + TAU * 0.75, 36, Color(col, 0.35), 1.0)
	for pd in pads:
		var at: Vector2 = pd["pos"]
		var col: Color = pd["color"]
		var r := 16.0 + 1.0 * sin(float(_tick) * 0.08)
		ci.draw_circle(at, r, Color(col, 0.16))
		ci.draw_arc(at, r, 0.0, TAU, 32, Color(col, 0.75), 2.0)
		ci.draw_arc(at, r * 0.55, 0.0, TAU, 24, Color(col, 0.35), 1.0)
		var n := int(pd.get("count", 0))
		if n > 0:
			var txt := str(n)
			ci.draw_string_outline(_font, at + Vector2(-20, -10), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 12, 3, C_OUTLINE)
			ci.draw_string(_font, at + Vector2(-20, -10), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 12, col)


## The Caravan: its push radius on the floor (the attackers' colour while they push, gold
## when contested, grey rolling back), a shadow, the wagon facing the way it's headed with
## its wheels turning as it goes, and the attackers' flag on top.
func _draw_caravan(ci: CanvasItem) -> void:
	var at: Vector2 = caravan["pos"]
	var team := int(caravan.get("team", 0))
	var st := int(caravan.get("state", 0))
	var team_col: Color = Hud.SIDE_COLORS[clampi(team, 0, 1)]
	var col := team_col
	if st == 2:
		col = Color("e8c060")
	elif st == -1:
		col = Color(0.62, 0.62, 0.66)
	elif st == 0:
		col = Color(team_col, 0.55)
	var r := float(caravan.get("radius", 56))
	ci.draw_circle(at, r, Color(col, 0.08 if st == 0 else 0.13))
	var spin := float(_tick) * (0.05 if st == 1 else (-0.03 if st == -1 else 0.0))
	for k in 12:  # a dashed rim that turns the way the caravan is going
		var a0 := spin + k * TAU / 12.0
		ci.draw_arc(at, r, a0, a0 + TAU / 20.0, 6, Color(col, 0.85), 2.0)
	# the wagon
	var heading: Vector2 = caravan.get("heading", Vector2.RIGHT)
	var flip := heading.x < 0.0
	ci.draw_set_transform(at + Vector2(0, 1), 0.0, Vector2(1.0, 0.38))
	ci.draw_circle(Vector2.ZERO, 22.0, Color(0, 0, 0, 0.3))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var frame := int(float(caravan.get("travel", 0.0)) / 3.0) % 4
	var dst := Rect2(at - Vector2(24, 36), Vector2(48, 40))
	if flip:
		dst = Rect2(at + Vector2(24, -36), Vector2(-48, 40))
	ci.draw_texture_rect_region(CARAVAN, dst, Rect2(frame * 48, 0, 48, 40))
	# the attackers' flag on a pole above the cover
	var pole := at + Vector2(0, -34)
	ci.draw_line(pole, pole + Vector2(0, -12), Color("3a2a1a"), 1.0)
	var wave := sin(float(_tick) * 0.2) * 1.0
	var fl := PackedVector2Array([pole + Vector2(0, -12), pole + Vector2(9, -10 + wave), pole + Vector2(0, -7)])
	if flip:
		fl = PackedVector2Array([pole + Vector2(0, -12), pole + Vector2(-9, -10 + wave), pole + Vector2(0, -7)])
	ci.draw_colored_polygon(fl, team_col)


## A Capture the Flag flag: a pole and its cloth in the side's colour, waving; on its
## stand, over its carrier's head, or on the ground with a ring counting down its return.
func _draw_flag(ci: CanvasItem, f: Dictionary) -> void:
	var at: Vector2 = f["pos"]
	var col: Color = Hud.SIDE_COLORS[clampi(int(f["team"]), 0, 1)]
	var st := int(f["state"])
	var foot := at - Vector2(0, float(f.get("lift", 0.0)))
	if st != TeamSim.FLAG_CARRIED:
		var shadow := 5.0 if st != TeamSim.FLAG_THROWN else maxf(2.5, 5.0 - float(f.get("lift", 0.0)) * 0.06)
		ci.draw_set_transform(at + Vector2(1, 1), 0.0, Vector2(1.0, 0.4))
		ci.draw_circle(Vector2.ZERO, shadow, Color(0, 0, 0, 0.3))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if st == TeamSim.FLAG_THROWN:  # where it comes down: a ring on the floor in its colour
		ci.draw_arc(at, 9.0, 0.0, TAU, 24, Color(col, 0.5), 1.0)
	if st == TeamSim.FLAG_DROPPED:
		var left := clampf(float(f.get("back", 0.0)), 0.0, 1.0)
		ci.draw_arc(at, 11.0, -PI * 0.5, -PI * 0.5 + TAU * left, 32, Color(col, 0.85), 2.0)
		if (_tick / 10) % 2 == 0:
			ci.draw_arc(at, 14.0, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 1.0)
	var top := foot + Vector2(0, -20)
	ci.draw_line(foot, top, Color("2a1e14"), 2.0)
	ci.draw_circle(top, 1.5, Color("e8c060"))
	var frame := (_tick / 6) % 4
	ci.draw_texture_rect_region(FLAG, Rect2(top + Vector2(1, 0), Vector2(12, 10)), Rect2(frame * 12, 0, 12, 10), col.lightened(0.15))


## A shrine: a stone ring on the floor. Ready, it glows in its colour (haste blue, might
## orange) with its sign in the middle, and a claim fills round it in the claiming side's
## colour; resting, it's dim with the seconds left.
func _draw_shrine(ci: CanvasItem, s: Dictionary) -> void:
	var at: Vector2 = s["pos"]
	var r := float(s["radius"])
	var kind := String(s["kind"])
	var col: Color = SHRINE_COLORS.get(kind, Color.WHITE)
	var rest := int(s["rest"])
	ci.draw_arc(at, r, 0.0, TAU, 48, Color(0.1, 0.1, 0.12, 0.6), 3.0)
	if rest > 0:
		ci.draw_arc(at, r, 0.0, TAU, 48, Color(col, 0.25), 1.0)
		ci.draw_string_outline(_font, at + Vector2(-12, 3), str(rest), HORIZONTAL_ALIGNMENT_CENTER, 24, 7, 2, Color(C_OUTLINE, 0.7))
		ci.draw_string(_font, at + Vector2(-12, 3), str(rest), HORIZONTAL_ALIGNMENT_CENTER, 24, 7, Color(col, 0.6))
		return
	var glow := 0.5 + 0.5 * sin(float(_tick) * 0.12)
	ci.draw_circle(at, r, Color(col, 0.08 + 0.06 * glow))
	ci.draw_arc(at, r, 0.0, TAU, 48, Color(col, 0.7 + 0.3 * glow), 1.5)
	# The sign: haste is a double chevron, might a fist-like block.
	var sc := Color(col.lightened(0.3), 0.85)
	if kind == "haste":
		for dx in [-3.0, 2.0]:
			ci.draw_polyline(PackedVector2Array([at + Vector2(dx - 2, -4), at + Vector2(dx + 2, 0), at + Vector2(dx - 2, 4)]), sc, 1.5)
	else:
		ci.draw_rect(Rect2(at + Vector2(-4, -3), Vector2(8, 6)), sc)
		ci.draw_rect(Rect2(at + Vector2(-4, -5), Vector2(8, 1)), sc)
	var side := int(s["side"])
	var claim := clampf(float(s["claim"]), 0.0, 1.0)
	if side >= 0 and claim > 0.0:
		var sidec: Color = Hud.SIDE_COLORS[side]
		ci.draw_arc(at, r + 3.0, -PI * 0.5, -PI * 0.5 + TAU * claim, 48, Color(sidec, 0.95), 2.5)


## A shrine's buff on a fighter: a ring at its feet in the shrine's colour, a few sparks
## rising off it.
func _draw_buffs(ci: CanvasItem) -> void:
	for c in sim.creatures:
		if c.state == CreatureSim.State.KO or not shown(c):
			continue
		var cols: Array = []
		if c.haste > 0 and c.haste_mult > 1.0:
			cols.append(SHRINE_COLORS["haste"])
		if c.atk_buff > 0 and c.atk_mult > 1.0:
			cols.append(SHRINE_COLORS["might"])
		for k in cols.size():
			var col: Color = cols[k]
			var rr := float(c.radius) + 3.0 + 3.0 * k
			ci.draw_set_transform(c.pos, 0.0, Vector2(1.0, 0.45))
			ci.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 24, Color(col, 0.55), 1.0)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var ph := float((_tick + c.id * 13 + k * 7) % 30) / 30.0
			var sx := float(((c.id * 7 + _tick / 30 + k * 3) % 5) - 2) * 3.0
			ci.draw_rect(Rect2(c.pos + Vector2(sx, -4.0 - ph * 22.0), Vector2(1, 2)), Color(col, 0.8 * (1.0 - ph)))


## Who's who: a coloured marker over each side's fighter (red for the left side, P1;
## blue for the right, P2 or the CPU) with its label.
func _draw_side_marks(ci: CanvasItem) -> void:
	for i in mini(side_marks.size(), sim.creatures.size()):
		var c := sim.creatures[i]
		if c.state == CreatureSim.State.KO:
			_trail.erase(c)
			continue
		if c.swallow_t > 0:
			continue  # inside Culvert: nothing to show
		if not shown(c):
			continue  # out of the local team's sight (brush, a fence or a wall)
		var mk: Dictionary = side_marks[i]
		var rel := String(mk.get("rel", "side"))
		var alpha := 1.0
		if c.stealth > 0:
			if rel != "self" and rel != "ally":
				continue
			alpha = 0.45
		var col: Color = REL_COLORS.get(rel, mk["color"])
		var at := (c.pos + Vector2(0, -_top(c) - 8.0 - c.air_height() - CreatureView.view_lift(c))).round()
		_draw_plate(ci, c, at, col, alpha)
		var label := String(mk.get("label", ""))
		if label != "":
			var lc := Color(col, alpha)
			ci.draw_string_outline(_font, at + Vector2(-20, -3), label, HORIZONTAL_ALIGNMENT_CENTER, 41, 6, 2,
				Color(C_OUTLINE, alpha))
			ci.draw_string(_font, at + Vector2(-20, -3), label, HORIZONTAL_ALIGNMENT_CENTER, 41, 6, lc)


## The bar itself, centred on `at` (its top edge).
func _draw_plate(ci: CanvasItem, c: CreatureSim, at: Vector2, col: Color, alpha: float) -> void:
	var hp := clampf(c.hp, 0.0, c.max_hp)
	var shield := maxf(0.0, c.shield)
	# The bar holds the larger of full health and health + shield, so a shield never spills out.
	var span := maxf(c.max_hp, hp + shield)
	var x0 := at.x - PLATE_W * 0.5
	var y0 := at.y
	var trail := _trail_step(c, hp)
	ci.draw_rect(Rect2(x0 - 1, y0 - 1, PLATE_W + 2, PLATE_H + 4), Color(C_OUTLINE, 0.9 * alpha))
	ci.draw_rect(Rect2(x0, y0, PLATE_W, PLATE_H), Color(Hud.C_BAR_BG, alpha))
	var hw := roundf(PLATE_W * hp / span)
	var tw := roundf(PLATE_W * clampf(trail, hp, span) / span)
	if tw > hw:
		ci.draw_rect(Rect2(x0 + hw, y0, tw - hw, PLATE_H), Color(C_TRAIL, 0.85 * alpha))
	if hw > 0:
		ci.draw_rect(Rect2(x0, y0, hw, PLATE_H), Color(col, alpha))
		ci.draw_rect(Rect2(x0, y0, hw, 1), Color(col.lightened(0.35), alpha))  # a highlight along the top
	if shield > 0.0:
		var sw := maxf(1.0, roundf(PLATE_W * shield / span))
		ci.draw_rect(Rect2(x0 + hw, y0, minf(sw, PLATE_W - hw), PLATE_H), Color(C_SHIELD, alpha))
	# Ticks every 25 health, so a glance says how much is left.
	var t := HP_TICK
	while t < span - 0.5:
		var tx := x0 + roundf(PLATE_W * t / span)
		ci.draw_rect(Rect2(tx, y0, 1, PLATE_H - 1), Color(C_OUTLINE, 0.55 * alpha))
		t += HP_TICK
	# The Surge strip: yellow, flashing white once it's full.
	var e := clampf(c.energy / CreatureSim.MAX_ENERGY, 0.0, 1.0)
	var full := e >= 1.0
	var ecol := Color.WHITE if full and (_tick / 8) % 2 == 0 else Hud.C_ENERGY
	ci.draw_rect(Rect2(x0, y0 + PLATE_H + 1, roundf(PLATE_W * e), 1), Color(ecol, alpha))


## The pale chunk a hit just took: it waits a moment, then drains down to the health left.
func _trail_step(c: CreatureSim, hp: float) -> float:
	var t: Array = _trail.get(c, [hp, 0, hp])
	if hp < float(t[2]):
		t[1] = 18  # fresh damage: hold the trail a moment
	if hp >= float(t[0]):
		t[0] = hp  # healed or respawned: no trail
	elif int(t[1]) > 0:
		t[1] = int(t[1]) - 1
	else:
		t[0] = maxf(hp, float(t[0]) - c.max_hp * 0.012)
	t[2] = hp
	_trail[c] = t
	return float(t[0])


## Venom Spit in flight: a wobbling green glob at head height with drips behind it.
func _draw_venom(ci: CanvasItem, pr: Dictionary) -> void:
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var d: Vector2 = Vector2(pr["vel"]).normalized()
	var at := pp + Vector2(0, -20)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.25))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 3:
		var back := at - d * (4.0 + i * 3.5) + Vector2(0, float((i + _tick / 2) % 3) - 1.0)
		ci.draw_circle(back.round(), 1.6 - i * 0.4, Color(C_VENOM[1], 0.8 - i * 0.2))
	var wob := 1.0 + 0.15 * float((_tick / 3) % 2)
	ci.draw_set_transform(at, d.angle(), Vector2(1.25 * wob, 1.0 / wob))
	ci.draw_circle(Vector2.ZERO, 3.6, C_OUTLINE)
	ci.draw_circle(Vector2.ZERO, 2.7, C_VENOM[1])
	ci.draw_circle(Vector2(0.6, -0.9), 1.0, C_VENOM[2])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Chef Cerebro's thrown knives: flung by his mind from over his head, point first, in a
## violet glow with a psychic streak behind and a glint along the blade.
func _draw_thrown_knife(ci: CanvasItem, pr: Dictionary) -> void:
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var d: Vector2 = Vector2(pr["vel"]).normalized()
	var at := pp + Vector2(0, -THROW_Z)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 2.5, Color(0, 0, 0, 0.25))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_line(at - d * 14.0, at - d * 5.0, Color(C_PSY, 0.35), 2.0)
	var tip := at + d * 5.0
	var butt := at - d * 4.0
	ci.draw_line(butt - d, tip + d, Color(C_PSY, 0.55), 5.0)
	ci.draw_line(butt, tip, C_OUTLINE, 3.0)
	ci.draw_line(at - d * 1.0, tip, C_GREY[3], 1.0)
	ci.draw_line(butt, at - d * 1.0, Color("2a2628"), 1.0)
	if (_tick / 3) % 2 == 0:
		ci.draw_rect(Rect2((at + d * 2.0).round(), Vector2.ONE), Color.WHITE)


## The mallet and the cleaver in flight, spinning end over end in a violet glow (he
## throws with his mind).
func _draw_spinner(ci: CanvasItem, pr: Dictionary, kind: String) -> void:
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var at := pp + Vector2(0, -THROW_Z)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 4.0, Color(0, 0, 0, 0.28))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_circle(at, 10.0, Color(C_PSY, 0.16))
	var spin := -_tick * 0.8 if Vector2(pr["vel"]).x < 0.0 else _tick * 0.8
	var d := Vector2.from_angle(spin)
	var n := d.orthogonal()
	if kind == "mallet":
		var butt := at - d * 6.0
		var head := at + d * 5.0
		ci.draw_line(butt, head, C_OUTLINE, 3.0)
		ci.draw_line(butt, head, C_MALLET[1], 1.0)
		var quad := PackedVector2Array([head - n * 4.0 - d * 2.0, head + n * 4.0 - d * 2.0,
			head + n * 4.0 + d * 2.5, head - n * 4.0 + d * 2.5])
		ci.draw_colored_polygon(quad, C_MALLET[0])
		ci.draw_polyline(quad + PackedVector2Array([quad[0]]), C_OUTLINE, 1.0)
	else:
		# the big chef's knife: a long blade and a black handle
		var butt := at - d * 8.0
		var heel := at - d * 2.0
		var tip := at + d * 11.0
		ci.draw_line(butt, heel, C_OUTLINE, 4.0)
		ci.draw_line(butt, heel, Color("2a2628"), 2.0)
		var blade := PackedVector2Array([heel, heel + n * 4.5, tip + n * 1.0, tip, heel - n * 0.5])
		ci.draw_colored_polygon(blade, C_GREY[3])
		ci.draw_polyline(blade + PackedVector2Array([blade[0]]), C_OUTLINE, 1.0)
		ci.draw_line(heel + n * 0.5, tip, Color.WHITE, 1.0)
	# a psychic whoosh behind it
	var back: Vector2 = -Vector2(pr["vel"]).normalized()
	ci.draw_arc(at + back * 3.0, 9.0, back.angle() - 0.6, back.angle() + 0.6, 8, Color(C_PSY, 0.45), 1.0)


## Cast Line's rod in flight: it spins end over end on its line, flying at hip height.
func _draw_thrown_rod(ci: CanvasItem, pr: Dictionary) -> void:
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var at := pp + Vector2(0, -10)
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 4.0, Color(0, 0, 0, 0.28))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var d := Vector2.from_angle(_tick * 0.7) * 13.0
	var butt := at - d
	var tip := at + d
	ci.draw_line(butt, tip, C_OUTLINE, 4.0)
	ci.draw_line(butt, tip, C_WOOD[1], 2.0)
	ci.draw_line(butt, butt.lerp(tip, 0.22), C_OUTLINE, 5.0)
	ci.draw_line(butt, butt.lerp(tip, 0.22), Color("880015"), 3.0)
	var reel := butt.lerp(tip, 0.28)
	ci.draw_circle(reel, 2.5, C_OUTLINE)
	ci.draw_circle(reel, 1.6, C_GREY[1])


## Pinecone Bomb in flight: an arc over everyone, its shadow on the floor, and a ring
## where it will land.
func _draw_pinecone(ci: CanvasItem, pr: Dictionary) -> void:
	var pp: Vector2 = pr["pos"]
	var vel: Vector2 = pr["vel"]
	var total := float(pr["time"])
	var left := float(pr["life"])
	var k := clampf(1.0 - left / total, 0.0, 1.0)
	var land := pp + vel * left
	var pulse := 0.5 + 0.5 * sin(_tick * 0.7)
	ci.draw_arc(land, float(pr["burst"]), 0.0, TAU, 32, Color(C_CONE[2], 0.25 + 0.35 * pulse * k), 1.0)
	ci.draw_set_transform(land, 0.0, Vector2(1.0, 0.42))
	ci.draw_circle(Vector2.ZERO, lerpf(2.0, 6.0, k), Color(0, 0, 0, 0.25))
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.42))
	ci.draw_circle(Vector2.ZERO, 3.5, Color(0, 0, 0, 0.3))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var z := 12.0 + 4.0 * 26.0 * k * (1.0 - k)  # leaves the hand at about head height
	z *= 1.0 - k * 0.55
	var at := (pp + Vector2(0, -z)).round()
	var rot := _tick * 0.35
	ci.draw_set_transform(at, rot, Vector2.ONE)
	ci.draw_rect(Rect2(-3, -4, 6, 8), C_OUTLINE)
	ci.draw_rect(Rect2(-2, -3, 4, 6), C_CONE[1])
	ci.draw_rect(Rect2(-2, -2, 4, 1), C_CONE[0])
	ci.draw_rect(Rect2(-2, 1, 4, 1), C_CONE[0])
	ci.draw_rect(Rect2(-1, -3, 1, 1), C_CONE[2])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Runoff as a rolling wave: a low swell with a curling crest and foam.
func _draw_wave(ci: CanvasItem, p: Vector2, vel: Vector2) -> void:
	var dir := -1.0 if vel.x < 0.0 else 1.0
	var bob := sin(_tick * 0.5) * 1.0
	var h := 11.0 + bob
	ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.25))
	ci.draw_circle(Vector2(0, -1), 9.0, Color(C_WATER, 0.9))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pts := PackedVector2Array()
	pts.append(p + Vector2(-10 * dir, 1))
	pts.append(p + Vector2(-6 * dir, -h * 0.45))
	pts.append(p + Vector2(-1 * dir, -h * 0.85))
	pts.append(p + Vector2(3 * dir, -h))
	pts.append(p + Vector2(7 * dir, -h * 0.8))
	pts.append(p + Vector2(6 * dir, -h * 0.55))
	pts.append(p + Vector2(4 * dir, -h * 0.6))
	pts.append(p + Vector2(8 * dir, 1))
	if dir < 0.0:
		pts.reverse()
	ci.draw_colored_polygon(pts, C_WATER)
	ci.draw_line(p + Vector2(-5 * dir, -h * 0.45), p + Vector2(0, -h * 0.85), C_WATER_L, 1.0)
	ci.draw_line(p + Vector2(0, -h * 0.85), p + Vector2(3 * dir, -h), C_FOAM, 2.0)
	ci.draw_line(p + Vector2(3 * dir, -h), p + Vector2(7 * dir, -h * 0.8), C_FOAM, 1.0)
	for i in 3:
		var fx := p + Vector2((randf_range(-8, 8)), randf_range(-2, 1))
		ci.draw_rect(Rect2(fx.round(), Vector2.ONE), C_FOAM)


## Things drawn straight from creature state every frame: orbiting pebbles, Cairn's
## stones, the Storm Drain landing marker and Avalanche speed lines.
func _draw_creature_extras(ci: CanvasItem, floor_layer: bool) -> void:
	if floor_layer:
		_draw_zones(ci)
	for c in sim.creatures:
		if not shown(c):
			continue  # no aim mark, telegraph or status icons for a fighter out of sight
		var attacking := c.state == CreatureSim.State.ATTACK
		var mv := c.move_def() if attacking else {}
		var fx: Dictionary = mv.get("fx", {})

		if attacking and c.charging and String(fx.get("charge", "")) == "pebbles":
			for pb in _pebbles(c, c.charge):
				if bool(pb["front"]) == floor_layer:
					continue
				var at := (Vector2(pb["ground"]) + Vector2(0, -float(pb["z"]))).round()
				var col := C_PEBBLE[1]
				if bool(pb["full"]) and (c.anim_t / 3) % 2 == 0:
					col = Color(1.0, 0.86, 0.5)
				ci.draw_rect(Rect2(at - Vector2(2, 1), Vector2(4, 3)), C_OUTLINE)
				ci.draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), col)

		if floor_layer:
			if attacking and c.charging and bool(mv.get("projectile", {}).get("lob", false)):
				_draw_lob_mark(ci, c, mv)
			if attacking and bool(fx.get("telegraph", false)) and c.state_t <= int(mv.get("startup", 0)):
				_draw_telegraph(ci, c, mv)
			if attacking and bool(fx.get("telegraph_line", false)) and not c.charging \
					and c.state_t <= int(mv.get("startup", 0)) + 6:
				_draw_line_telegraph(ci, c)
			if c.is_armored():
				_draw_rooted(ci, c)
			if not (c.state in [CreatureSim.State.KO, CreatureSim.State.FALLING]) and not c.is_dummy:
				_draw_aim_mark(ci, c, attacking)
			continue

		if c.state != CreatureSim.State.KO:
			_draw_status(ci, c)

		var stack_def: Dictionary = c.def.get("stack", {})
		if not stack_def.is_empty() and c.stack > 0 and c.state != CreatureSim.State.KO:
			var slots := _stack_slots(c, c.stack)
			for i in slots.size():
				var at := (Vector2(slots[i][0]) + Vector2(0, -float(slots[i][1]))).round()
				ci.draw_set_transform(at, 0.0, Vector2(1.0, 0.7))
				ci.draw_circle(Vector2.ZERO, 3.4, C_OUTLINE)
				ci.draw_circle(Vector2.ZERO, 2.6, C_STACK[i % C_STACK.size()])
				ci.draw_circle(Vector2(-1, -1), 1.0, C_STACK[i % C_STACK.size()].lightened(0.35))
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if c.stack >= int(stack_def.get("max", 3)) and (c.anim_t / 6) % 2 == 0:
				var top := (c.pos + Vector2(0, -_top(c) - 7.0 - c.air_height() - 6.0)).round()
				ci.draw_rect(Rect2(top, Vector2.ONE), C_SPARK[0])

		if attacking and bool(fx.get("cast", false)):
			_draw_cast(ci, c, mv)

		if attacking and bool(fx.get("speedlines", false)):
			var segs: Array = mv.get("_segs", [])
			if segs.size() > 0:
				var last: Dictionary = segs[segs.size() - 1]
				if c.state_t >= int(mv.get("startup", 0)) and c.state_t <= int(last["at"]) + 6:
					var center := c.pos + Vector2(0, -_chest(c))
					for i in 30:
						var dir := Vector2.from_angle(randf() * TAU)
						var r0 := randf_range(80.0, 120.0)
						ci.draw_line(center + dir * r0, center + dir * (r0 + randf_range(60.0, 160.0)),
							Color(1, 1, 1, 0.22), 1.0)


func _draw_telegraph(ci: CanvasItem, c: CreatureSim, mv: Dictionary) -> void:
	var dash: Dictionary = mv.get("dash", {})
	var remaining := 0.0
	if not dash.is_empty():
		remaining = maxf(0.0, float(dash["to"]) - c.state_t) * float(dash["speed"])
	var land := c.pos + c.facing * (remaining + float(mv.get("reach", 0)))
	if dash.has("home"):
		# A homing leap: the mark follows the foe until the landing spot locks.
		var foe := sim.nearest_opponent(c)
		if foe != null and c.state_t <= int(dash["home"].get("until", 0)):
			land = foe.pos
		else:
			land = c.pos + c.facing * maxf(0.0, float(dash["to"]) - c.state_t) * c.home_speed
	var k := clampf(float(c.state_t) / maxf(1.0, float(mv.get("startup", 1))), 0.0, 1.0)
	var r := float(mv.get("hit_radius", 40))
	var pulse := 0.5 + 0.5 * sin(_tick * 0.6)
	ci.draw_arc(land, r, 0.0, TAU, 48, Color(C_WARN, 0.25 + 0.35 * pulse * k), 1.0)
	ci.draw_arc(land, r * k, 0.0, TAU, 40, Color(C_WARN, 0.35), 1.0)
	ci.draw_set_transform(land, 0.0, Vector2(1.0, 0.38))
	ci.draw_circle(Vector2.ZERO, lerpf(4.0, 16.0, k), Color(0, 0, 0, 0.35))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A small chevron on the floor where the fighter faces. Aiming is 360 degrees but the
## sprites have three views, so this shows the exact angle; it brightens while an attack
## is still being aimed.
func _draw_aim_mark(ci: CanvasItem, c: CreatureSim, attacking: bool) -> void:
	var f := c.facing
	var aiming := attacking and c.active_seg() < 0 and c.state_t <= int(c.move_def().get("startup", 0)) + 1
	var a := 0.75 if aiming else 0.3
	var tip := c.pos + f * (c.radius + 9.0)
	var base := c.pos + f * (c.radius + 4.0)
	var side := f.orthogonal() * 3.0
	var pts := PackedVector2Array([tip, base + side, base - side])
	ci.draw_colored_polygon(pts, Color(1, 1, 1, a * 0.8))
	ci.draw_polyline(PackedVector2Array([base + side, tip, base - side]), Color(0, 0, 0, a * 0.6), 1.0)

## A lob while it's held (Pinecone Bomb, Thousand Cranes): a ring on the floor where it
## will land, sliding out as the throw gets longer. Locked on (`MatchSim.lob_lock`: the
## aim points at a foe) it sits on them instead, brighter and doubled, ticked at four points.
func _draw_lob_mark(ci: CanvasItem, c: CreatureSim, mv: Dictionary) -> void:
	var pr: Dictionary = mv["projectile"]
	var off := float(pr.get("offset", 0))
	var dir := c.facing
	var k := clampf(float(c.charge) / maxf(1.0, float(mv.get("charge_max", 1))), 0.0, 1.0)
	var rng := lerpf(float(pr["range"]), float(pr.get("range_charged", pr["range"])), k)
	var locked: CreatureSim = sim.lob_lock(c, pr) if sim != null else null
	if locked != null:
		dir = (locked.pos - c.pos).normalized()
		rng = clampf(c.pos.distance_to(locked.pos) - off, float(pr["range"]),
			float(pr.get("range_charged", pr["range"])))
	var land := (c.pos + dir * (off + rng)).round()
	var r := float(pr.get("burst", 16))
	if pr.has("storm"):  # Thousand Cranes: the storm's own circle, the size it hits
		r = float((pr["storm"] as Dictionary).get("radius", 40))
	var pulse := 0.5 + 0.5 * sin(_tick * 0.5)
	if locked != null:
		ci.draw_arc(land, r, 0.0, TAU, 48, Color(C_AMBER, 0.65 + 0.3 * pulse), 2.0)
		ci.draw_arc(land, r - 4.0, 0.0, TAU, 48, Color(C_AMBER, 0.25 + 0.2 * pulse), 1.0)
		for q in 4:
			var u: Vector2 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][q]
			ci.draw_line(land + u * (r - 6.0), land + u * (r + 3.0), Color(C_AMBER, 0.9), 2.0)
	else:
		ci.draw_arc(land, r, 0.0, TAU, 32, Color(C_CONE[2], 0.45 + 0.35 * pulse), 1.0)
	ci.draw_circle(land, 2.0, Color(C_AMBER if locked != null else C_CONE[2], 0.7))
	var n := int(rng / 8.0)
	for i in n:
		var at := (c.pos + dir * (off + rng * (i + 0.5) / n)).round()
		ci.draw_rect(Rect2(at, Vector2.ONE), Color(C_AMBER if locked != null else C_CONE[2], 0.4))


## Knife Flurry: a dotted line along the floor as far as the knives will fly.
func _draw_line_telegraph(ci: CanvasItem, c: CreatureSim) -> void:
	var reach := c.move_range(c.move_id)
	var k := clampf(float(c.state_t + 4) / maxf(1.0, float(c.move_def().get("startup", 1))), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_tick * 0.6)
	var n := int(reach / 6.0)
	for i in n:
		if float(i) / n > k:
			break
		var at := (c.pos + c.facing * (c.radius + 4.0 + i * 6.0)).round()
		ci.draw_rect(Rect2(at - Vector2(1, 0), Vector2(3, 1)), Color(C_WARN, 0.35 + 0.35 * pulse))
	var end := (c.pos + c.facing * reach).round()
	ci.draw_arc(end, 5.0, 0.0, TAU, 16, Color(C_WARN, 0.3 + 0.4 * pulse * k), 1.0)


## Bedrock: a glowing ring where the feet are planted, cracks pulsing outward.
func _draw_rooted(ci: CanvasItem, c: CreatureSim) -> void:
	var pulse := 0.5 + 0.5 * sin(_tick * 0.4)
	ci.draw_set_transform(c.pos, 0.0, Vector2.ONE)
	ci.draw_arc(Vector2.ZERO, c.radius + 8.0 + pulse * 2.0, 0.0, TAU, 32, Color(C_AMBER, 0.55), 2.0)
	ci.draw_arc(Vector2.ZERO, c.radius + 15.0 + pulse * 3.0, 0.0, TAU, 32, Color(C_AMBER, 0.25), 1.0)
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(d * (c.radius + 4.0), d * (c.radius + 11.0 + pulse * 4.0), Color(C_AMBER, 0.6), 1.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Shield plates, slowed pebbles and the taunt mark, drawn over the creature.
func _draw_status(ci: CanvasItem, c: CreatureSim) -> void:
	if c.swallow_t > 0:
		return
	var lift := c.air_height()
	if c.poison_stacks > 0 and c.state != CreatureSim.State.KO:
		# Venom Frenzy's stacks: a row of green pips at its feet, one per stack.
		var w := c.poison_stacks * 4 - 1
		var x0 := roundf(c.pos.x - w * 0.5)
		for i in c.poison_stacks:
			var at := Vector2(x0 + i * 4, roundf(c.pos.y + 5.0))
			ci.draw_rect(Rect2(at - Vector2(1, 1), Vector2(5, 5)), C_OUTLINE)
			ci.draw_rect(Rect2(at, Vector2(3, 3)), C_VENOM[1] if (_tick / 8 + i) % 4 != 0 else C_VENOM[2])
	if c.slow > 0:
		for i in 3:
			var a := _tick * 0.12 + TAU * i / 3.0
			var at := (c.pos + Vector2(cos(a) * (c.radius + 2.0), sin(a) * 3.0 - 1.0)).round()
			ci.draw_rect(Rect2(at - Vector2(1, 1), Vector2(3, 2)), C_OUTLINE)
			ci.draw_rect(Rect2(at - Vector2(0, 1), Vector2(1, 1)), C_GREY[2])
	if c.taunt > 0 and (c.taunt > 30 or (_tick / 4) % 2 == 0):
		var top := (c.pos + Vector2(0, -_top(c) - 10.0 - lift)).round()
		_bang(ci, top)
	if c.blind > 0:
		# blinded: little stars circling the head
		for i in 3:
			var a := _tick * 0.15 + TAU * i / 3.0
			var at := (c.pos + Vector2(cos(a) * 7.0, -_top(c) - 2.0 - lift + sin(a) * 2.0)).round()
			ci.draw_rect(Rect2(at - Vector2(1, 0), Vector2(3, 1)), C_LAMP)
			ci.draw_rect(Rect2(at - Vector2(0, 1), Vector2(1, 3)), C_LAMP)
	if c.root > 0:
		# rooted: rubble heaped round the feet
		for i in 6:
			var a := TAU * i / 6.0 + 0.4
			var at := (c.pos + Vector2(cos(a) * (c.radius + 1.0), sin(a) * 3.0)).round()
			ci.draw_rect(Rect2(at - Vector2(2, 1), Vector2(4, 3)), C_OUTLINE)
			ci.draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), C_DIRT[1 + i % 2])
	if c.vuln > 0 and (c.vuln > 40 or (_tick / 4) % 2 == 0):
		# tenderized: a pink down-arrow bobbing over the head
		var bob := float((_tick / 8) % 2)
		var at := (c.pos + Vector2(c.radius + 4.0, -_top(c) - 4.0 - lift + bob)).round()
		ci.draw_rect(Rect2(at + Vector2(-1, -6), Vector2(3, 5)), C_OUTLINE)
		ci.draw_rect(Rect2(at + Vector2(0, -5), Vector2(1, 4)), C_TENDER)
		var tri := PackedVector2Array([at + Vector2(-3, -1), at + Vector2(4, -1), at + Vector2(0.5, 3)])
		ci.draw_colored_polygon(tri, C_OUTLINE)
		var tri2 := PackedVector2Array([at + Vector2(-2, -1), at + Vector2(3, -1), at + Vector2(0.5, 2)])
		ci.draw_colored_polygon(tri2, C_TENDER)


func _bang(ci: CanvasItem, at: Vector2) -> void:
	ci.draw_rect(Rect2(at + Vector2(-2, -9), Vector2(5, 8)), C_OUTLINE)
	ci.draw_rect(Rect2(at + Vector2(-2, 0), Vector2(5, 4)), C_OUTLINE)
	ci.draw_rect(Rect2(at + Vector2(-1, -8), Vector2(3, 6)), C_TAUNT)
	ci.draw_rect(Rect2(at + Vector2(-1, 1), Vector2(3, 2)), C_TAUNT)


func _draw_rain(ci: CanvasItem) -> void:
	var amount := minf(1.0, _rain / 30.0)
	var n := int(110 * amount)
	var col := Color(C_WATER_L, 0.45)
	for i in n:
		var x := fposmod(i * 37.7 + _tick * 2.4, 520.0) - 20.0
		var y := fposmod(i * 61.3 + i * i * 0.37 + _tick * 8.0, 300.0) - 15.0
		ci.draw_line(Vector2(x, y), Vector2(x - 2.0, y + 7.0), col, 1.0)
	var fr := sim.floor_rect() if sim != null else SimDefs.floor_rect()
	for i in n / 3:
		var hsh := i * 7919 + (_tick / 4) * 104729
		var sx := fr.position.x + float(hsh % int(fr.size.x))
		var sy := fr.position.y + float((hsh / 7) % int(fr.size.y))
		ci.draw_rect(Rect2(Vector2(sx, sy - 1), Vector2(1, 1)), Color(C_FOAM, 0.6))
		ci.draw_rect(Rect2(Vector2(sx - 1, sy), Vector2(3, 1)), Color(C_WATER_L, 0.5))
