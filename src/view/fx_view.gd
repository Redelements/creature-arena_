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
##   shout        {"text", "sound"}  a voice line when the move starts: the sound at once, the words
##                once a Surge's freeze is over, over his head to his back, or under his feet when
##                the HUD or the crowded-field Surge name is up there (`_shout_now`)
##   projectile   also "fire": a looping comet fireball (assets/vfx/fireball.png) turned along its flight
##   prop         "pan"        a cast-iron pan held where the shots leave, a flame licking out of it
##                             while they fly (Chef Cerebro's Surge)
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
##   spark        "light" | "heavy" | "skill" | "surge"  the hit-spark shape (default: the move's type)
##   spark_color  colour of a skill's burst (default: ghost_color, else amber)
##   decal        "scratch" | "gouge" | "drag" | "crater_s" | "crater_l" | "clod" | "mallet" | "none"  the lasting
##                floor mark (FloorWear) this move leaves: on its hits (scratch, gouge, crater), on its last strike
##                (clod, mallet, crater) or along its dash (drag). Default by attack type: light scratches, heavy
##                gouges, surge craters; impact popup/tenderize/cavein leave clods/mallet marks/a crater; a dash
##                with trail "gravel" (or burrow) drags a line. Slams and hard landings crater; wet, slushy and
##                sticky footprints follow shallows, slush-footed fighters and syrup (all in the _wear_* functions)
## Creature sprite keys read here: "step" ("slush" for slush puffs), "step_frames" (run frames
## where a foot lands; default the first and the middle one).
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
## Status drawn from creature state (`_draw_status`; every layer skips a fighter `shown` hides):
##   shield       Stoneskin plates (and CreatureView's pale rim)   armored  amber ring
##   rooted       roots curling over the feet                          taunted  red "!" and a dotted red tether to the taunter
##   poisoned     green bubbles, a row of pips per Frenzy stack    blinded  small yellow stars circling the head
##   stunned      (crumpled) little birds circling the head        slowed   pebbles at the feet, icy motes trailing, a cool tint
##   tenderized   pink down-arrow, plus CreatureView's slow pink pulse on the sprite
##   frozen       an ice block round the sprite: faceted outline, glints, cracks as it ends
##   petrified    CreatureView's grey shader, cracks over it as it ends (dust ring on the shatter)
##   pickpocket   gold glints on the thief while the stolen might lasts; coins drift from
##                the victim to the thief while the victim is weakened
## Mountain Maw (fx "projectile": "head"): Craglash's own head and stone neck from his sheet, `_draw_long_bite`.
## Projectile polish (every thrown thing, from `PROJ_STYLE` by its "projectile" kind; a move's fx overrides):
##   trail_color  colour of the 3 whole-pixel afterimages behind a shot (default by kind)
##   trail_z      height of the trail above the floor in px; negative: no trail (default by kind)
##   land_mark    "scuff" | "stuck" | "splat" | "mallet" | "none"  the lasting floor mark (FloorWear) where a shot
##                that hit nothing ends (default by kind); every shot also has a small shadow in its draw
## Wall reactions (the sim's "bounce" event, `_wall_reaction`): dust, a white flash on the wall face, falling rubble and,
## on the arena's boundary wall, cracks that spread and fade over 10 to 20 s (`wallmark`, at most WALL_MARK_CAP);
## bigger knockback is a bigger splat; a rubble wall (Quarry) gets the burst only. A shot stopped by a rubble wall
## puffs dust and chips there too.

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
## Chef Cerebro's Surge fire (kiddolink FI cuts, tools/cut_vfx.py, ppu 2): the fireball each shot
## is drawn as (`_draw_fireball`), the flame licking out of his pan, and the pan itself (Szadi
## FL Houses, tools/cut_pan.py) he holds while the move plays (`_draw_held_pan`, fx.prop "pan").
const FIREBALL := preload("res://assets/vfx/fireball.png")
const PAN_FLAME := preload("res://assets/vfx/flame_column.png")
const PAN := preload("res://assets/sprites/pan.png")
const VFX_FRAME := 96.0  ## a kiddolink frame, px
const FIRE_HEAD := Vector2(70, 47)  ## the fireball's head in its frame: on the shot's spot
const FIRE_FRAMES := 12
const FIRE_SCALE := 0.75  ## on top of the ppu: 27 units nose to tail
const FLAME_FRAMES := 12
const FLAME_BASE := Vector2(48, 79)  ## the flame's foot in its frame: in the pan
const FLAME_SCALE := 0.4
const PAN_DISH := Vector2(15, 5)  ## the dish's centre in pan.png (the handle is to its left)
const C_TENDER := Color("ff8fa3")
const C_MALLET: Array[Color] = [Color("8c4c48"), Color("b07a70")]
const C_BRAIN: Array[Color] = [Color("d6606a"), Color("f88686"), Color("ffb2aa")]
const C_VENOM: Array[Color] = [Color("3f8a2a"), Color("7fd64e"), Color("c8f59a")]
const C_GAZE := Color("fff27a")
const C_DIRT: Array[Color] = [Color("56391f"), Color("7a5634"), Color("9c744c")]
const C_LAMP := Color("fff6b0")
const C_GOLD: Array[Color] = [Color("c89a1e"), Color("f2c94c"), Color("fff0a0")]
const C_CASH: Array[Color] = [Color("3f8f3f"), Color("7fd67f")]
const C_BIRD := Color("cfe6ff")
const C_BIRD_BEAK := Color("ffa63a")
const C_SLOW_MOTE := Color("bfe4f5")
const C_COIN: Array[Color] = [Color("a8781a"), Color("f2c94c"), Color("fff0a0")]
const C_ICE: Array[Color] = [Color("64bad0"), Color("a8eef8"), Color("f0fcff")]
const C_SYRUP: Array[Color] = [Color("f0d21e"), Color("e8303a"), Color("46c846")]
const C_BLEED: Array[Color] = [Color("7a0e1c"), Color("cc2a3a"), Color("ff7f86")]

## Asks AudioView for a sound that belongs to a timed effect (a KO scatter, geysers...).
signal cue(sound: String)

var sim: MatchSim
var views: Array = []  ## CreatureView per creature, same order as sim.creatures
var ground: FxGround
var wear: FloorWear  ## the floor's lasting marks (scratches, craters, prints); set by main
var time_scale := 1.0  ## main slows this for KO slow-motion; 0 holds everything still
var shake_out := 0.0  ## extra screen shake asked for by effects; main takes it each frame
var shake_dir := Vector2.ZERO  ## the last hit's push direction; main biases the shake along it
var flash_out := 0.0  ## a screen flash asked for (a Surge hit); main takes it each frame

var _parts: Array[Dictionary] = []
var _incoming: Array[Dictionary] = []
var _font: Font:  ## the pixel font (or the smooth one, Settings > Video); sizes through UiTheme.px
	get: return UiTheme.font()
var _tick := 0
var _watch := {}
var _last_push := {}
## Damage numbers: the running number on each target (a flurry merges into one), and when a
## statue last shattered, so its bonus hit gets an accent.
var _dmg_run := {}
var _shatter_seen := {}
## (Every root, Barkley's or Cave-In's, draws the same curling roots: Kevin's ruling, Oct 27.)
## creature id -> the FxView tick its leafy root took hold (the roots grow in from it).
var _root_t := {}
var _n_dmg := 0
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


## Projectile style by the move's fx.projectile kind: [trail colour, trail height (negative: none), landing mark].
const PROJ_STYLE := {
	"knife": [Color("d58cff"), THROW_Z, "stuck"], "cleaver": [Color("d58cff"), THROW_Z, "stuck"],
	"mallet": [Color("d58cff"), THROW_Z, "mallet"], "rod": [Color("e6d2b0"), 10.0, "scuff"],
	"venom": [Color("7fd64e"), 20.0, "splat"], "dart": [Color("f6f4ec"), 18.0, "scuff"],
	"shuriken": [Color("ff9a2e"), 18.0, "stuck"], "crane": [Color("f6f4ec"), 20.0, "none"],
	"frog": [Color("f6f4ec"), -1.0, "none"], "head": [Color("b5665f"), -1.0, "none"],
	"tongue": [Color("c45c6e"), -1.0, "none"], "wave": [Color("a8d6f0"), -1.0, "none"],
	"pinecone": [Color("c48c54"), -1.0, "none"], "crane_bundle": [Color("f6f4ec"), -1.0, "none"],
	"fire": [Color("ff9a3a"), -1.0, "none"],
}
const TRAIL_STEPS := 3
const TRAIL_ALPHA: Array[float] = [0.62, 0.42, 0.26]
const WALL_MARK_CAP := 24
var _pstyles := {}  ## "owner/move" -> {kind, color, z, mark}
var _proj_prev: Array = []  ## last tick's shots: [owner, pos, vel, style], to tell what a projectile_end was
var _wall_marks: Array = []
## Hand-drawn move effects (a move's `fx.move_fx`, MoveFx resources): a child, so they draw
## over the sparks; fed from the same places the sparks come from and stepped on this clock.
var move_fx := MoveFxView.new()


func _init() -> void:
	add_child(move_fx)


func bind_ground(g: FxGround) -> void:
	ground = g
	ground.painter = _paint.bind(true)


func clear() -> void:
	if wear != null:
		wear.clear()
	_parts.clear()
	_lost.clear()
	_was_hidden = []
	_trail.clear()
	# Every mode object main hands in goes with the match, or the next one (a 1v1, the menu
	# background) drew the last CTF's flags and shrines: main writes them back each tick of
	# a team or Brawl fight (`_show_pads`, `_update_zone`).
	pads.clear()
	zone = {}
	caravan = {}
	flags = []
	shrines = []
	wanted = []
	_incoming.clear()
	_watch.clear()
	_last_push.clear()
	_dmg_run.clear()
	_shatter_seen.clear()
	_root_t.clear()
	_pstyles.clear()
	_proj_prev.clear()
	_maw.clear()
	_wall_marks.clear()
	_shouts.clear()
	move_fx.clear()
	_dark = 0.0
	_rain = 0.0
	time_scale = 1.0
	shake_out = 0.0
	shake_dir = Vector2.ZERO
	flash_out = 0.0
	queue_redraw()


# ------------------------------------------------------------------ events

func spawn(e: Dictionary) -> void:
	if not _event_shown(e):
		return  # it happened out of the local team's sight
	var p: Vector2 = e["pos"]
	var power: float = e["power"]
	match String(e["type"]):
		"hit":
			var push := _note_push(e)
			_hit_sparks(e, p, push)
			var atk := _creature(int(e.get("attacker", -1)))
			if atk != null and atk.state == CreatureSim.State.ATTACK:
				# on the target's body: lifted with it when it's juggled or thrown
				var tgt := _creature(int(e.get("target", -1)))
				move_fx.on_event("hit", atk, p - Vector2(0, tgt.air_height() if tgt != null else 0.0))
			var col := Color("ffe08a")
			if float(e.get("variety", 1.0)) >= 1.5:
				col = Color("ff9a5a")
			elif float(e.get("variety", 1.0)) > 1.0:
				col = Color("ffd166")
			if bool(e.get("stale", false)):
				col = Color("b8b8b8")
			_damage_number(e, p, col)
			_wear_hit(e, push)
			if bool(e.get("stagger_if", false)):
				# A no_flinch hit that staggered because the target was set up (stagger_if).
				var c := _creature(int(e.get("target", -1)))
				if c != null:
					_text(c.pos + Vector2(0, -_top(c) * 0.5), "STAGGERED!", C_TENDER, 7, 40.0)  # mid-body: TENDERIZED is above
		"block":
			_block_feedback(e, p)
		"guard_break":
			_guard_break_feedback(e, p)
		"hazard_strike", "hazard_hit", "hazard_shelter", "hazard_pickup", "hazard_pickup_gone", "hazard_reverse", "hazard_end", "hazard_ricochet":
			_hazard_event(e, p)
		"slam":
			var full := power >= 1.0
			_add({"kind": "ring", "pos": p, "life": 18 if full else 12, "radius": 34.0 if full else 18.0})
			var n := 10 if full else 6
			for i in n:
				var a := TAU * i / n + randf() * 0.3
				var r := (22.0 if full else 12.0) + randf() * 6.0
				_dust(p + Vector2(cos(a), sin(a)) * r, Vector2(cos(a), sin(a) * 0.5 - 0.6) * 0.5)
			_slam_debris(p, full)
			_wear_mark("crater_l" if full else "crater_s", p)
		"bounce":
			_add({"kind": "spark", "pos": p + Vector2(0, -12), "life": 8, "scale": 1.0})
			_add({"kind": "lines", "pos": p + Vector2(0, -12), "life": 6, "size": 0.8, "color": C_SPARK[0]})
			_landing_puff(p, 2)
			_wall_reaction(e, p, power)
		"fall":
			for i in 4:
				_dust(p + Vector2(randf_range(-8, 8), randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.5))
			_later(CreatureSim.FALL_TICKS - 6, _pit_plume.bind(p))
		"land":
			if _tick != _hard_tick:  # a hard landing already puffed this tick
				_landing_puff(p, 1)
		"dodge":
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
			if thrower != null:
				move_fx.on_shot(thrower, p)
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
			if owner_c != null:
				move_fx.on_event("projectile_end", owner_c, p)
				_maw_end(owner_c, p)
			_land_mark(p, power)
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
			var bomber := _creature(int(e.get("who", -1)))
			if bomber != null:
				move_fx.on_event("burst", bomber, p)
			_pinecone_burst(p, power)
		"storm":
			# a lob that leaves a storm (Thousand Cranes) lands: its "burst" move effects play there
			var stormer := _creature(int(e.get("who", -1)))
			if stormer != null:
				move_fx.on_event("burst", stormer, p)
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
		"projectile_bounce":
			_add({"kind": "spark", "pos": p, "life": 8, "scale": 1.0})
			_add({"kind": "ring", "pos": p, "life": 8, "radius": 10.0})
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
				_root_t[c.id] = _tick
				# under the feet, drifting only a little, so it never crosses the roots
				_text(c.pos + Vector2(0, 19), "ROOTED", C_LEAF[2], 7, 44.0, 80.0, 0.15)
				move_fx.play(_plant_fx("root"), c.pos, c)
		"seed", "plant_grow", "apple", "plant_hit", "plant_root", "apple_eaten", "apple_spoiled", "plant_gone":
			_plant_event(e, p)
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
			_shatter_seen[int(e.get("who", -1))] = _tick
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
				_add({"kind": "ring", "pos": c.pos, "life": 16, "radius": c.radius + 14.0,
					"color": C_ICE[2] if bool(e.get("ice", false)) else C_GREY[3]})
				_text(c.pos + Vector2(0, -_top(c) - 22), "SHATTER!", Color("ffd166"), 10, 50.0)
				shake_out = maxf(shake_out, 3.0)
		"land_hard":
			_hard_tick = _tick
			_landing_puff(p, 2)
			_wear_mark("crater_s", p)


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
	if kind in ["projectile_end", "projectile_pierce", "projectile_bounce", "burst", "zone", "seed", "plant_grow",
			"apple", "plant_hit", "plant_gone"]:
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
	var t0 := PerfLog.now()
	if sim != null:
		_watch_all()
		_track_lost()
		move_fx.advance(ts)
		_shout_now()
		if ts > 0.0:
			_projectile_spray()
			if not sim.hazards.is_empty():
				_hazard_spray()
		_snap_projectiles()
	PerfLog.since("fx watch", t0)
	t0 = PerfLog.now()
	_parts.append_array(_incoming)
	_incoming.clear()
	PerfLog.count("fx parts", _parts.size())

	var keep: Array[Dictionary] = []
	var ends: Array[Callable] = []
	_n_puff = 0
	_n_dmg = 0
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
			if String(p["kind"]) == "puff":
				_n_puff += 1
			elif String(p["kind"]) == "dmg":
				_n_dmg += 1
		elif p.has("on_end"):
			ends.append(p["on_end"])
	_parts = keep
	PerfLog.since("fx parts loop", t0)
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
	_update_maws()


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
		if c.state == CreatureSim.State.DODGE and ticked and c.state_t % 3 == 0 and c.def["dodge"].has("ram"):
			_wear_mark("drag", c.pos - c.facing * 4.0, c.facing)  # Landslide Ram digs in
		if c.state == CreatureSim.State.AIRBORNE and ticked and c.air_t < c.air_total / 2 and c.anim_t % 2 == 0:
			_launch_streak(c)
		_footstep(c, w, ticked)
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
	move_fx.on_start(c)
	if String(mv.get("type", "")) == "surge":
		if sim.freeze_all:
			_dark = maxf(_dark, 0.6)
		else:
			# No freeze or cut-in on a crowded field: the Surge's name over the caster.
			_text(c.pos + Vector2(0, -_top(c) - 22), String(mv.get("name", "SURGE")).to_upper(),
				Color("ffd166"), 10, 60.0, 220.0)
	if bool(fx.get("burrow", false)):
		cue.emit("dig")
		_wear_mark("clod", c.pos)
	if bool(fx.get("syrup", false)):
		cue.emit("slosh")
	if bool(fx.get("smoke", false)):
		_smoke(c.pos, 8)
		cue.emit("poof")
	var shout: Dictionary = fx.get("shout", {})
	if not shout.is_empty():
		# The voice starts with the move; the words wait out a Surge's freeze (the cut-in
		# banner covers the field until then) and then hang over his head (`_shout_now`).
		# (on a crowded field the Surge's name is over his head already: the words go under him)
		var named := String(mv.get("type", "")) == "surge" and not sim.freeze_all
		_shouts.append([c.id, String(shout.get("text", "")), named])
		if shout.has("sound"):
			cue.emit(String(shout["sound"]))
	if bool(fx.get("chop", false)):
		_text(c.pos + Vector2(0, -_top(c) - 12), "CHOP CHOP!", Color("ffd166"), 10, 60.0)
		cue.emit("chop_chop")
	if bool(fx.get("rain", false)):
		_rain = 130.0


## The voice lines waiting for the Surge freeze to end: [creature id, text, under him]. Drawn over
## everything else in the layer (the foe's health bar, hit sparks), kept on screen.
var _shouts: Array = []
const SHOUT_BACK := 36.0


func _shout_now() -> void:
	if _shouts.is_empty() or sim.hitstop > 0:
		return
	for s in _shouts:
		var c := _creature(int(s[0]))
		if c != null:
			# over his head, a little to his back: off the shots and the foe he's facing
			var back := -signf(c.facing.x) * SHOUT_BACK if absf(c.facing.x) > 0.01 else 0.0
			_add({"kind": "text", "pos": c.pos + Vector2(back, -_top(c) - 12), "text": String(s[1]),
				"color": Color("ffd166"), "size": 10, "life": 70.0, "width": 180.0, "on_screen": true,
				"low": c.pos + Vector2(back, 6), "went_low": bool(s[2])})
	_shouts.clear()


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
	move_fx.on_strike(c, seg)
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
		_wear_strike(c, fx, seg)
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
	move_fx.on_tick(c)
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
	_wear_drag(c, fx, dsh, t)
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
	var ring: Dictionary = mv.get("terrain_ring", {})
	if ring.is_empty():
		return
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


## The hand-drawn effects round Barkley's plants (assets/vfx cuts, each sized and set on
## the floor here: a GROUND cut's art stands about 15.5 units under its centre at scale 1).
const PLANT_FX := {
	"seed": {"path": "res://assets/vfx/dust_poof.tres", "scale": 0.45, "offset": [0, -5]},
	"seed_leaf": {"path": "res://assets/vfx/leaf_swirl.tres", "scale": 0.55, "offset": [0, -5]},
	"grow": {"path": "res://assets/vfx/leaf_swirl.tres", "scale": 1.4, "offset": [0, -14]},
	"grow_dust": {"path": "res://assets/vfx/dust_burst.tres", "scale": 0.8, "offset": [0, -12]},
	"apple": {"path": "res://assets/vfx/hit_star_cyan.tres", "scale": 0.4, "offset": [0, 0]},
	"eaten": {"path": "res://assets/vfx/heal_beam.tres", "scale": 0.8, "offset": [0, -12], "follow": true},
	"spoiled": {"path": "res://assets/vfx/wisp_purple.tres", "scale": 0.6, "offset": [0, -9]},
	"killed": {"path": "res://assets/vfx/leaf_swirl.tres", "scale": 0.8, "offset": [0, -8]},
	"killed_dust": {"path": "res://assets/vfx/dust_poof.tres", "scale": 0.5, "offset": [0, -6]},
	"root": {"path": "res://assets/vfx/leaf_swirl.tres", "scale": 0.8, "offset": [0, -8], "follow": true},
}
const C_APPLE := Color("d6262a")
var _plant_fx_cache := {}


func _plant_fx(name: String) -> MoveFx:
	if not _plant_fx_cache.has(name):
		_plant_fx_cache[name] = MoveFx.from_entry(PLANT_FX[name])
	return _plant_fx_cache[name]


## A seed planted, a sprout struck, grown or sprung, an apple borne, eaten or spoiled
## (src/sim/plants.gd's events; the plants themselves are PlantView's).
func _plant_event(e: Dictionary, p: Vector2) -> void:
	var c := _creature(int(e.get("who", -1)))
	match String(e["type"]):
		"seed":
			move_fx.play(_plant_fx("seed"), p)
			move_fx.play(_plant_fx("seed_leaf"), p)
			_leaves(p + Vector2(0, -14), 4, 0.6)
		"plant_grow":
			move_fx.play(_plant_fx("grow_dust"), p)
			move_fx.play(_plant_fx("grow"), p)
			_leaves(p + Vector2(0, -24), 12, 1.3)
			for i in 6:
				_dust(p + Vector2(randf_range(-12, 12), randf_range(-3, 3)), Vector2(randf_range(-0.5, 0.5), -0.3))
		"apple":
			var at := p + PlantView.APPLE_AT + Vector2(0, -3)
			move_fx.play(_plant_fx("apple"), at)
			_text(p + Vector2(0, -64), "APPLE!", C_APPLE.lightened(0.25), 7, 40.0)
		"plant_hit":
			_leaves(p + Vector2(0, -14), 3, 0.7)
			_px(p + Vector2(0, -6), Vector2(randf_range(-0.6, 0.6), -0.8), C_LEAF[2], 10)
		"plant_root":
			if c != null:
				_leaves(c.pos + Vector2(0, -14), 6, 1.0)
				# the sprout snaps shut: short roots whip up round the feet
				for i in 5:
					var a := TAU * i / 5.0 + randf_range(-0.3, 0.3)
					_add({"kind": "root", "pos": c.pos + Vector2(cos(a) * (c.radius + 3.0), sin(a) * (c.radius + 3.0) * 0.5),
						"life": 16, "h": randf_range(5.0, 8.0), "w": randf_range(1.4, 2.0), "lean": -cos(a) * 0.4,
						"delay": randf_range(0.0, 2.0), "front": sin(a) > 0.0})
		"apple_eaten":
			if c != null:
				move_fx.play(_plant_fx("eaten"), c.pos, c)
				_text(c.pos + Vector2(0, -_top(c) - 14), "+%d" % roundi(float(e["power"])), C_LEAF[2], 8, 44.0)
				for i in 4:
					_add({"kind": "heal", "pos": c.pos + Vector2(randf_range(-8, 8), -_top(c) * randf_range(0.3, 0.8)),
						"vel": Vector2(0, -0.5), "life": 30})
		"apple_spoiled":
			if c != null:
				move_fx.play(_plant_fx("spoiled"), c.pos)
				_text(c.pos + Vector2(0, -_top(c) - 14), "SPOILED", Color("b48ad0"), 7, 40.0)
				for i in 5:
					_px(c.pos + Vector2(randf_range(-6, 6), -randf_range(2, 10)), Vector2(randf_range(-0.4, 0.4), -0.5),
						Color("6a3a5a"), 18)
		"plant_gone":
			var how := String(e.get("how", ""))
			if how == "sprung":
				_leaves(p + Vector2(0, -8), 5, 0.8)  # the sprout snaps down (PlantView)
			elif how == "eaten" or how == "spoiled":
				# the spent tree sinks back into the floor (PlantView): its crown sheds leaves
				_leaves(p + Vector2(0, -40), 14, 0.9)
				for i in 5:
					_dust(p + Vector2(randf_range(-14, 14), randf_range(-3, 3)), Vector2(randf_range(-0.4, 0.4), -0.3))
			if how == "killed":
				move_fx.play(_plant_fx("killed_dust"), p)
				move_fx.play(_plant_fx("killed"), p)
				_leaves(p + Vector2(0, -14), 10, 1.4)
				for i in 4:
					_chunk(p, randf_range(2, 8), Vector2.from_angle(randf() * TAU) * randf_range(0.5, 1.2),
						randf_range(0.8, 1.6), randf_range(1.5, 2.5), C_WOOD[randi() % 3], 40.0)


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
	var n := int(clampf(r / 4.5, 6.0, 22.0))
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
	var sppu := int(snap.get("side_ppu", 1))  # the bands and `pieces` are sheet pixels
	var dir: Vector2 = _last_push.get(c.id, -c.facing)
	var pieces: Array = ko.get("pieces", [])
	if pieces.is_empty():
		pieces = _scatter_bands(c, origin.y, fsize.y, sppu)
	for i in pieces.size():
		var y0 := int(pieces[i][0])
		var y1 := int(pieces[i][1])
		var zc := (origin.y - (y0 + y1) * 0.5) / float(sppu)
		var head := i == 0
		var spread := dir.rotated(randf_range(-0.8, 0.8))
		var speed := randf_range(0.7, 1.6) + (1.3 if head else 0.0)
		_add({"kind": "chunk", "piece": true, "tex": snap["side_tex"], "flip": flip, "ppu": sppu,
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
func _scatter_bands(c: CreatureSim, feet_y: float, frame_h: float, sppu := 1) -> Array:
	var top := clampf(feet_y - (_top(c) + 4.0) * sppu, 0.0, feet_y)
	var bottom := minf(feet_y + 2.0 * sppu, frame_h)
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


## How a hit looks, by attack type: light a few pixels, heavy a radial burst, skill a
## burst in the move's colour, surge the heavy burst and a screen flash. Light and skill
## sparks fan along the push (attacker to target). A move's fx "spark" overrides the type.
func _hit_sparks(e: Dictionary, p: Vector2, push: Vector2) -> void:
	var power: float = e["power"]
	var a := _creature(int(e.get("attacker", -1)))
	var d := _creature(int(e.get("target", -1)))
	var fx: Dictionary = {}
	if a != null and a.state == CreatureSim.State.ATTACK:
		fx = a.move_def().get("fx", {})
	# (the event's own "type" is "hit"; the move's type is on the attacker)
	var kind := String(fx.get("spark", a.move_type() if a != null and a.state == CreatureSim.State.ATTACK else ""))
	if not kind in ["light", "heavy", "skill", "surge"]:
		kind = "heavy" if bool(e.get("heavy", false)) else "light"
	var dir_a := push.angle()
	var col: Color = C_SPARK[0]
	var n := 3
	var spread := 0.7
	var r1 := 8.0
	var ln := 3.0
	var life := 5.0
	var width := 1.0
	match kind:
		"heavy", "surge":
			n = 7 if kind == "surge" or power >= 14.0 else 6
			spread = PI
			r1 = 20.0 if kind == "surge" else 16.0
			ln = 6.0
			life = 8.0
			width = 2.0
		"skill":
			col = Color(fx.get("spark_color", fx.get("ghost_color", C_AMBER)))
			col.a = 1.0
			n = 5
			spread = 2.4
			r1 = 13.0
			ln = 5.0
			life = 7.0
	var angs: Array = []
	var lens: Array = []
	for i in n:
		var t := (float(i) + 0.5) / n * 2.0 - 1.0
		angs.append(dir_a + t * spread + randf_range(-0.12, 0.12))
		lens.append(ln * randf_range(0.7, 1.3))
	# Settings > Accessibility > Hit markers: bigger rays with a dark outline (data/accessibility.json)
	var sk := float(Accessibility.marker("spark_scale", 1.0))
	if sk != 1.0:
		r1 *= sk
		for i in lens.size():
			lens[i] = float(lens[i]) * sk
	width += float(Accessibility.marker("spark_width_add", 0))
	_add({"kind": "burst", "pos": p, "life": life, "angs": angs, "lens": lens, "r0": 2.0, "r1": r1,
		"width": width, "color": col, "edge": float(Accessibility.marker("spark_outline_width", 0)),
		"edge_color": Color(String(Accessibility.marker("spark_outline", "#000000")))})
	match kind:
		"light":
			for i in 2:
				_px(p, push.rotated(randf_range(-0.6, 0.6)) * randf_range(1.0, 2.0), C_SPARK[randi() % 3], 6)
			if d != null and d.id < views.size():
				views[d.id].soft_flash = not bool(Accessibility.marker("full_flash", false))
		"heavy", "surge":
			var big := kind == "surge" and not surge_small_hit(a, power)
			_add({"kind": "spark", "pos": p, "life": 8, "scale": (2.2 if big else 1.6) * sk})
			for i in 5:
				_px(p, push.rotated(randf_range(-0.7, 0.7)) * randf_range(1.2, 2.8), C_SPARK[randi() % 3], 12)
			if big:
				flash_out = 0.3
		"skill":
			_add({"kind": "spark", "pos": p, "life": 7, "scale": 1.2 * sk})
			for i in 4:
				_px(p, push.rotated(randf_range(-0.9, 0.9)) * randf_range(1.0, 2.4), col, 10)
	if push.length_squared() > 0.001:
		shake_dir = push  # main leans the camera shake along it


## A small hit of a multi-hit Surge (a volley of shots, or several strike segments) below
## Light2DView.FLASH_HIT_MIN: one of Cooking with Fire's eight fireballs, not its finisher.
## These spark like a heavy and skip the screen flash (and Light2DView's big Surge flash):
## eight of them stacked bleach the whole screen and hide the fight.
static func surge_small_hit(a: CreatureSim, power: float) -> bool:
	if a == null or a.state != CreatureSim.State.ATTACK or power >= Light2DView.FLASH_HIT_MIN:
		return false
	var mv := a.move_def()
	var vol: Dictionary = mv.get("projectile", {}).get("volley", {})
	return int(vol.get("count", 1)) > 1 or (mv.get("_segs", []) as Array).size() > 1


const STEP_CAP := 48  ## puffs alive at once; past it footsteps are skipped
var _n_puff := 0
var _hard_tick := -1
const C_DUST: Dictionary = {
	"dirt": [Color("a07c54"), Color("c4a276"), Color("dcc29a")],
	"stone": [Color("94846c"), Color("b2a38a"), Color("cfc3ae")],
	"concrete": [Color("8a909a"), Color("b8bcc2"), Color("dde0e4")],
	"grass": [Color("28b450"), Color("5cd072"), Color("96dcaa")],
	"water": [Color("549cd0"), Color("a8d6f0"), Color("e8f4fa")],
	"slush": [Color("a8eef8"), Color("f0fcff"), Color("d6e6ee")],
}


## What the floor under `pos` throws up: "water" in shallows, else the sprite's own "step"
## ("slush"), else the arena's ground (dirt, stone, concrete, grass).
func _floor_kind(c: CreatureSim, pos: Vector2) -> String:
	var tg := sim.terrain
	if tg.get_cell(tg.world_to_cell(pos)) == TerrainGrid.SHALLOWS:
		return "water"
	var own := String(c.def.get("sprite", {}).get("step", "")) if c != null else ""
	if own != "":
		return own
	var g := String(sim.arena.get("ground", "dirt"))
	return g if C_DUST.has(g) else "dirt"


## A puff on the floor layer. `size` 0 a footstep, 1 a landing, 2 a hard landing or bounce.
func _floor_puff(pos: Vector2, kind: String, size: int, dir := Vector2.ZERO) -> void:
	if _n_puff >= STEP_CAP:
		return
	var n: int = [5, 8, 12][size]
	var spread: float = [5.0, 9.0, 14.0][size]
	var lifts := kind == "water" or kind == "grass"
	var bits: Array = []
	for i in n:
		var a := randf() * TAU
		var r := randf_range(0.3, 1.0) * spread
		var v := Vector2(cos(a), sin(a) * 0.5) * randf_range(0.04, 0.12) * (1.0 + size) - dir * 0.05
		var vy := v.y - (randf_range(0.25, 0.7) if lifts else randf_range(0.05, 0.2))
		bits.append([cos(a) * r * 0.4, sin(a) * r * 0.2 - 1.0, v.x, vy,
			2.0 if size > 0 or randf() < 0.7 else 1.0, randi() % 3])
	_n_puff += 1
	_add({"kind": "puff", "pos": pos, "life": 14.0 + 5.0 * size, "bits": bits, "cols": C_DUST[kind],
		"g": 0.05 if lifts else 0.0})


func _landing_puff(p: Vector2, size: int) -> void:
	if sim == null or not _view_rect(self, CULL_PAD).has_point(p):
		return
	_floor_puff(p, _floor_kind(null, p), size)


## Dust at a runner's feet on the frames where a foot lands.
func _footstep(c: CreatureSim, w: Dictionary, ticked: bool) -> void:
	if c.state != CreatureSim.State.MOVE:
		w["step"] = -1
		return
	if not ticked:
		return
	var sp: Dictionary = c.def.get("sprite", {})
	var run: Array = sp.get("anims", {}).get("run", [])
	if run.size() < 3:
		return
	var frames := int(run[2])
	var frame := (c.anim_t / maxi(1, int(sp.get("run_ticks", 4)))) % maxi(1, frames)
	var last := int(w.get("step", -1))
	if frame == last:
		return
	w["step"] = frame
	if last < 0:
		return  # the first frame after starting to run isn't a footfall
	var contact: Array = sp.get("step_frames", [0, frames / 2])
	if not frame in contact:
		return
	if not _view_rect(self, CULL_PAD).has_point(c.pos):
		return
	var kind := _floor_kind(c, c.pos)
	_floor_puff(c.pos + Vector2(-c.facing.x * 3.0, 1.0), kind, 0, c.facing)
	_wear_step(c, w, kind, frame)


# ------------------------------------------------------------------ floor wear
# What leaves a mark on the floor (FloorWear draws and stores them). A move's `fx.decal`
# overrides: "scratch" | "gouge" | "drag" | "crater_s" | "crater_l" | "clod" | "mallet" |
# "none". Defaults: a light hit on a grounded foe scratches, a heavy gouges, a surge
# craters; impact "popup" leaves clods, "tenderize" mallet marks, "cavein" a big crater;
# a dash with trail "gravel" (or fx.burrow) drags a line; slams and hard landings crater.

func _wear_mark(kind: String, pos: Vector2, dir := Vector2.RIGHT) -> void:
	if wear != null and sim != null and _view_rect(self, CULL_PAD).has_point(pos):
		wear.mark(kind, pos, dir)


const WEAR_IMPACT := {"popup": "clod", "tenderize": "mallet", "cavein": "crater_l"}


func _wear_hit(e: Dictionary, push: Vector2) -> void:
	var a := _creature(int(e.get("attacker", -1)))
	var d := _creature(int(e.get("target", -1)))
	if a == null or d == null:
		return
	var fx: Dictionary = a.move_def().get("fx", {})
	var kind := String(fx.get("decal", ""))
	if kind == "":
		if WEAR_IMPACT.has(String(fx.get("impact", ""))):
			return  # the strike leaves its own mark
		match a.move_type():
			"light":
				kind = "" if d.is_airborne() else "scratch"
			"heavy":
				kind = "gouge"
			"surge":
				kind = "crater_s"
	if kind != "" and kind != "none":
		_wear_mark(kind, d.pos, push)


## The last strike of a move: the floor marks of its `impact`, or its own `fx.decal`.
func _wear_strike(c: CreatureSim, fx: Dictionary, seg: int) -> void:
	var kind := String(fx.get("decal", WEAR_IMPACT.get(String(fx.get("impact", "")), "")))
	if kind == "" or kind == "none":
		return
	_wear_mark(kind, c.pos if bool(fx.get("burrow", false)) else c.hit_center(seg), c.facing)


## A dash drags a line behind it when it kicks up gravel, burrows, or says `decal: "drag"`.
func _wear_drag(c: CreatureSim, fx: Dictionary, dsh: Dictionary, t: int) -> void:
	if wear == null or dsh.is_empty() or t % 3 != 0 or t < int(dsh["from"]) or t > int(dsh["to"]):
		return
	var kind := String(fx.get("decal", ""))
	if kind == "" and (String(fx.get("trail", "")) == "gravel" or bool(fx.get("burrow", false))):
		kind = "drag"
	if kind == "drag":
		_wear_mark("drag", c.pos - c.facing * 4.0, c.facing)


## Footprints that last a few seconds: after wading (wet), in a syrup puddle (sticky), and
## the slush a fighter whose sprite `step` is "slush" tracks.
func _wear_step(c: CreatureSim, w: Dictionary, kind: String, frame: int) -> void:
	if wear == null:
		return
	var foot := ""
	if kind == "water":
		w["wet"] = 5
	elif _in_syrup(c.pos):
		foot = "print_syrup"
		w["wet"] = 0
	elif kind == "slush":
		foot = "print_slush"
	elif int(w.get("wet", 0)) > 0:
		w["wet"] = int(w["wet"]) - 1
		foot = "print_wet"
	if foot == "":
		return
	var side := Vector2(-c.facing.y, c.facing.x) * (2.0 if frame % 2 == 0 else -2.0)
	_wear_mark(foot, c.pos + side + Vector2(0, 1), c.facing)


func _in_syrup(pos: Vector2) -> bool:
	for z in sim.zones:
		if Vector2(z["pos"]).distance_to(pos) <= float(z["radius"]):
			return true
	return false


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


## `width`: the box the text is centred in (longer text is clipped).
## A word that rises `rise` units a tick as it fades.
func _text(pos: Vector2, text: String, color: Color, size := 8, life := 40.0, width := 80.0, rise := 0.5) -> void:
	_add({"kind": "text", "pos": pos, "text": text, "color": color, "size": size, "life": life, "width": width,
		"rise": rise})


# --- damage numbers, block sparks and the guard break ------------------------------------
# All stepped on the 60 Hz tick, whole pixels, no tweening: a number pops one font step up
# for a few ticks and settles, rises in 1 px steps and fades in quarters. A flurry on one
# target merges into a running total instead of piling up.
const DMG_CAP := 24
const DMG_MERGE := 26  ## ticks a number stays open for the next hit on the same target
const C_SHIELD_RIM := Color("cfe4ff")
const C_SHIELD_FILL := Color("4f7fd6")
const C_SHIELD_DARK := Color("27407a")


## The size ladder is design sizes that UiTheme.px maps to distinct font steps; Settings >
## Accessibility > Hit markers adds `number_size_add` to every step.
func _dmg_size(total: float, kind: String) -> int:
	var sz := 8
	if kind == "surge":
		sz = 16
	elif kind == "heavy" or kind == "skill" or total >= 12.0:
		sz = 12
	return sz + int(Accessibility.marker("number_size_add", 0))


func _dmg_open(run) -> bool:
	return run != null and float(run["t"]) <= DMG_MERGE and float(run["life"]) > float(run["t"])


## Numbers sit over the target's head (the status callouts' height), never on the body.
func _num_anchor(tgt: int, fallback: Vector2) -> Vector2:
	var c := _creature(tgt)
	if c == null:
		return fallback + Vector2(0, -6)
	return c.pos + Vector2(0, -_top(c) - 19.0)


func _damage_number(e: Dictionary, hit_pos: Vector2, col: Color) -> void:
	var tgt := int(e.get("target", -1))
	var pos := _num_anchor(tgt, hit_pos)
	var a := _creature(int(e.get("attacker", -1)))
	var kind := "light"
	if a != null and a.state == CreatureSim.State.ATTACK:
		kind = a.move_type()
	if not kind in ["light", "heavy", "skill", "surge"]:
		kind = "heavy" if bool(e.get("heavy", false)) else "light"
	var power := float(e["power"])
	var stale := bool(e.get("stale", false))
	if not stale:
		if kind == "surge":
			col = col.lerp(Color("ff6a2c"), 0.7)
		elif kind == "heavy":
			col = col.lerp(Color("ff9a4a"), 0.55)
	# An accent when the hit carried a bonus: a statue shattering, or a sneak attack.
	var accent := ""
	if int(_shatter_seen.get(tgt, -99)) >= _tick - 1:
		accent = "shatter"
		col = Color("c8f4ff")
	elif a != null and float(a.def.get("ambush", 1.0)) > 1.0 and (a.ambush_t > 0 or a.ambush_serial == a.attack_serial):
		accent = "ambush"
		col = Color("e59bff")
	var run = _dmg_run.get(tgt)
	if _dmg_open(run):
		run["total"] = float(run["total"]) + power
		run["hits"] = int(run["hits"]) + 1
		run["pop_at"] = run["t"]
		run["pos"] = pos
		run["life"] = float(run["t"]) + 34.0
		run["size"] = maxi(int(run["size"]), _dmg_size(float(run["total"]), kind))
		if not stale:
			run["color"] = col
		if accent != "":
			run["accent"] = accent
		run["text"] = _dmg_text(run)
		return
	if _n_dmg >= DMG_CAP:
		return
	var p := {"kind": "dmg", "tgt": tgt, "pos": pos, "total": power, "hits": 1, "pop_at": 0.0, "size": _dmg_size(power, kind),
		"color": col, "accent": accent, "life": 40.0}
	p["text"] = _dmg_text(p)
	_add(p)
	_dmg_run[tgt] = p
	_n_dmg += 1


func _dmg_text(p: Dictionary) -> String:
	var s := str(int(round(float(p["total"]))))
	if String(p["accent"]) != "":
		s += "!"
	return s


func _draw_damage_number(ci: CanvasItem, p: Dictionary) -> void:
	var t := float(p["t"])
	var size := int(p["size"])
	if t - float(p["pop_at"]) < 3.0:
		# One font step up for a moment, then settle (16 and 20 are the same pixel step).
		size += 10 if size >= 16 and not UiTheme.smooth else 4
	var rise := int(minf(t, 16.0) / 2.0)
	var left := float(p["life"]) - t
	var col: Color = p["color"]
	col.a = 1.0 if left > 12.0 else ceilf(left / 12.0 * 4.0) / 4.0
	var fs := UiTheme.px(size)
	var at := (_num_anchor(int(p["tgt"]), Vector2(p["pos"]) + Vector2(0, 6)) + Vector2(-40.0, -rise)).round()
	var txt := String(p["text"])
	var ow := UiTheme.outline(fs) + 1 + int(Accessibility.marker("number_outline_add", 0))
	var sh: Array = Accessibility.marker("number_shadow", [0, 0])
	if int(sh[0]) != 0 or int(sh[1]) != 0:  # a drop shadow (Hit markers: High contrast)
		var sc := Color(Color(String(Accessibility.marker("number_shadow_color", "#000000"))), col.a)
		var sat := at + Vector2(float(sh[0]), float(sh[1]))
		ci.draw_string_outline(_font, sat, txt, HORIZONTAL_ALIGNMENT_CENTER, 80.0, fs, ow, sc)
		ci.draw_string(_font, sat, txt, HORIZONTAL_ALIGNMENT_CENTER, 80.0, fs, sc)
	ci.draw_string_outline(_font, at, txt, HORIZONTAL_ALIGNMENT_CENTER, 80.0, fs, ow, Color(0.1, 0.08, 0.1, col.a))
	ci.draw_string(_font, at, txt, HORIZONTAL_ALIGNMENT_CENTER, 80.0, fs, col)


## A blocked hit: a shield spark on the guard side (a block costs stamina, no health).
func _block_feedback(e: Dictionary, p: Vector2) -> void:
	var push := _note_push(e)
	var d := _creature(int(e.get("target", -1)))
	var side := -push  # toward the attacker: where the shield takes it
	var at := (d.pos if d != null else p) + side * 13.0 + Vector2(0, -14)
	_add({"kind": "shield", "pos": at, "life": 10, "scale": 2, "crack": 0.0})
	for i in 4:
		_px(at + side * 2.0, side.rotated(randf_range(-1.1, 1.1)) * randf_range(0.8, 1.8), C_SHIELD_RIM, 8)


## A guard break: the shield flashes, cracks across, then bursts into shards. "drained"
## (stamina ran out) is the same graphic with its own word.
func _guard_break_feedback(e: Dictionary, p: Vector2) -> void:
	var c := _creature(int(e.get("who", -1)))
	var base := (c.pos if c != null else p)
	var at := base + Vector2(0, -26)
	_add({"kind": "shield", "pos": at, "life": 16, "scale": 3, "crack": 1.0, "shake": true})
	_later(16.0, func(): _shield_burst(at))
	_text(base + Vector2(0, -48), "EXHAUSTED" if bool(e.get("drained", false)) else "GUARD BREAK", Color("ff9a5a"))


func _shield_burst(at: Vector2) -> void:
	_add({"kind": "lines", "pos": at, "life": 8, "size": 1.0, "color": C_SHIELD_RIM})
	for i in 10:
		var ang := TAU * i / 10.0 + randf() * 0.5
		var v := Vector2.from_angle(ang) * randf_range(0.8, 1.9) + Vector2(0, -0.5)
		_add({"kind": "shard", "pos": at + Vector2.from_angle(ang) * 3.0, "vel": v, "life": 26.0,
			"color": C_SHIELD_RIM if i % 3 == 0 else (C_SHIELD_FILL if i % 3 == 1 else C_SHIELD_DARK), "shape": i})


func _draw_shield_part(ci: CanvasItem, p: Dictionary) -> void:
	var t := float(p["t"])
	var s := int(p["scale"])
	var pos: Vector2 = p["pos"]
	if bool(p.get("shake", false)) and t > 3.0:
		pos += Vector2(int(t) % 2 * 2 - 1, (int(t) / 2) % 2 * 2 - 1)
	pos = pos.round()
	var rim := C_SHIELD_RIM
	var fill := C_SHIELD_FILL
	if t < 2.0:  # the impact flash
		rim = Color.WHITE
		fill = Color("cfe4ff")
	var cr := float(p["crack"])
	var k := t / float(p["life"])
	var a := 1.0 if k < 0.7 else (0.66 if k < 0.85 else 0.33)
	if cr <= 0.0:
		a = 1.0 if k < 0.5 else 0.5
	rim.a = a
	fill.a = a
	_shield_shape(ci, pos, s, rim, fill)
	if cr > 0.0:
		var segs := [Vector2(0, -4), Vector2(-1, -2), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 3), Vector2(0, 4)]
		var shown_n := mini(segs.size() - 1, 1 + int(k * 7.0))
		var dark := Color(0.08, 0.1, 0.18, a)
		for i in shown_n:
			var a0: Vector2 = segs[i] * s
			var a1: Vector2 = segs[i + 1] * s
			ci.draw_line(pos + a0, pos + a1, dark, 1.0)
			if i == 2 and shown_n > 3:  # a branch
				ci.draw_line(pos + a1, pos + a1 + Vector2(3, 1) * s, dark, 1.0)


## A heater shield of rects: rows top to bottom, rim on the edges, a lit centre line.
func _shield_shape(ci: CanvasItem, pos: Vector2, s: int, rim: Color, fill: Color) -> void:
	const ROWS := [9, 9, 9, 9, 7, 7, 5, 3, 1]
	var top := -4 * s
	for i in ROWS.size():
		var w: int = ROWS[i]
		var y := pos.y + top + i * s
		var x := pos.x - (w * s) / 2
		if i == 0 or i == ROWS.size() - 1:
			ci.draw_rect(Rect2(x, y, w * s, s), rim)
			continue
		ci.draw_rect(Rect2(x, y, w * s, s), fill)
		ci.draw_rect(Rect2(x, y, s, s), rim)
		ci.draw_rect(Rect2(x + (w - 1) * s, y, s, s), rim)
	ci.draw_rect(Rect2(pos.x, pos.y + top + s, s, 5 * s), rim)


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
	var t0 := PerfLog.now()
	_draw_now()
	PerfLog.since("fx draw", t0)


func _draw_now() -> void:
	_paint(self, false)


## Culling: on a big map most of the field is off screen, so nothing is drawn unless it
## is within these pads of the view. Particles are centred on `pos` and reach at most a
## smear's or a burst ring's length; a fighter's extras include telegraphs that can reach
## into view from well outside it, so they get a wider margin.
const CULL_PAD := 160.0
const CULL_PAD_FIGHTER := 320.0


## The part of `ci`'s space on screen, grown by `pad`; everything when there's no screen.
## Where a text box `w` wide at `at` (its baseline's left end) stays whole on screen: clear of
## the side edges, and when it would rise under the HUD's top bars (the top 15% of the view;
## a close camera puts heads up there) it goes to the part's `low` spot instead, under his
## feet, where it doesn't sit on the health bars either, and stays there (no jumping back).
static func _keep_on_screen(ci: CanvasItem, p: Dictionary, at: Vector2, w: float, fs: int) -> Vector2:
	if not ci.is_inside_tree():
		return at
	var v := _view_rect(ci, 0.0)
	if p.has("low") and (bool(p.get("went_low", false)) or at.y - float(fs) < v.position.y + v.size.y * 0.15):
		p["went_low"] = true
		at = Vector2(p["low"]) + Vector2(-w * 0.5, float(fs))
	var x := clampf(at.x, v.position.x + 2.0, maxf(v.position.x + 2.0, v.end.x - w - 2.0))
	var y := minf(at.y, v.end.y - v.size.y * 0.12)  # over the caption bar at the bottom
	return Vector2(x, y).round()


static func _view_rect(ci: CanvasItem, pad: float) -> Rect2:
	if not ci.is_inside_tree():
		return Rect2(-1e9, -1e9, 2e9, 2e9)
	return (ci.get_global_transform_with_canvas().affine_inverse() * ci.get_viewport_rect()).grow(pad)


## Whether the particle is near enough the screen to draw (one without a `pos` always is).
static func _in_view(p: Dictionary, view: Rect2) -> bool:
	var pos = p.get("pos")
	return pos == null or view.has_point(pos)


func _paint(ci: CanvasItem, floor_layer: bool) -> void:
	var view := _view_rect(ci, CULL_PAD)
	if floor_layer:
		if _dark > 0.0:
			ci.draw_rect(Rect2(-ArenaView.MARGIN, (sim.arena_size() if sim != null else SimDefs.arena_size()) + ArenaView.MARGIN * 2.0),
				Color(C_DIM, _dark))
		_draw_pads(ci)
		if sim != null and not sim.hazards.is_empty():
			_draw_hazards_floor(ci)
		# One pass sorts them: flat things first, so debris sits on top of puddles and
		# cracks. (A big break throws ~400 pieces; two passes of string lists cost ms.)
		var later: Array[Dictionary] = []
		for p in _parts:
			if not _in_view(p, view):
				continue
			var kind := String(p["kind"])
			if FLAT_KINDS.has(kind):
				_draw_part(ci, p)
			elif kind == "ghost" or (UNDER_KINDS.has(kind) and not bool(p.get("front", false))) \
					or (p.has("vz") and float(p["z"]) > 1.0) or (kind == "chunk" and bool(p.get("grounded", false))):
				later.append(p)
		for p in later:
			var kind := String(p["kind"])
			if kind == "ghost" or (UNDER_KINDS.has(kind) and not bool(p.get("front", false))):
				_draw_part(ci, p)
			elif p.has("vz") and float(p["z"]) > 1.0:
				_draw_shadow(ci, p)
			else:
				_draw_part(ci, p)
		if sim != null:
			_draw_creature_extras(ci, true)
		return

	if sim != null:
		_draw_projectiles(ci)
		if not sim.hazards.is_empty():
			_draw_hazards_top(ci)
	for p in _parts:
		var kind := String(p["kind"])
		if kind in ["puddle", "decal", "ripple", "ghost", "later", "emit", "lost", "wallmark", "wallflash"]:
			continue
		if not _in_view(p, view):
			continue
		if p.has("orbit") and not shown(_creature(int(p["orbit"]))):
			continue  # circling a fighter the local team can't see
		if kind in ["spire", "root"] and not bool(p.get("front", false)):
			continue
		if kind == "chunk" and bool(p.get("grounded", false)):
			continue
		if bool(p.get("on_screen", false)):
			continue  # a voice line: drawn last, below
		_draw_part(ci, p)
	if sim != null:
		_draw_creature_extras(ci, false)
		_draw_side_marks(ci)
	for p in _parts:
		if bool(p.get("on_screen", false)):
			_draw_part(ci, p)
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
			ci.draw_string_outline(_font, q + Vector2(-10, 0), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, UiTheme.px(10), 1,
				Color(C_OUTLINE, a))
			ci.draw_string(_font, q + Vector2(-10, 0), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, UiTheme.px(10), Color(C_WARN, a))
		"spark":
			var pos: Vector2 = p["pos"]
			var s: float = p["scale"]
			var frame := mini(int(k * 4.0), 3)
			var size := Vector2(16, 16) * s
			ci.draw_texture_rect_region(SHEET, Rect2((pos - size * 0.5).round(), size), Rect2(frame * 16, 0, 16, 16))
		"heal":  # the Caravan's escort healing: a small green cross rising, fading
			var at: Vector2 = (Vector2(p["pos"]) + Vector2(p["vel"]) * t).round()
			var col := Color("7ee07a", 1.0 - k)
			ci.draw_rect(Rect2(at + Vector2(-1, -3), Vector2(2, 6)), col)
			ci.draw_rect(Rect2(at + Vector2(-3, -1), Vector2(6, 2)), col)
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
			var w := float(p.get("width", 80.0))
			var at := pos + Vector2(-w * 0.5, -roundf(t * float(p.get("rise", 0.5)) * 2.0) * 0.5)
			var fs := UiTheme.px(int(p["size"]))
			if bool(p.get("on_screen", false)):
				at = _keep_on_screen(ci, p, at, w, fs)
			ci.draw_string_outline(_font, at, String(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, w, fs, UiTheme.outline(fs) + 1, Color(0.1, 0.08, 0.1, col.a))
			ci.draw_string(_font, at, String(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)
		"dmg":
			_draw_damage_number(ci, p)
		"shield":
			_draw_shield_part(ci, p)
		"shard":
			var sp: Vector2 = (Vector2(p["pos"]) + Vector2(p["vel"]) * t + Vector2(0, 0.06 * t * t)).round()
			var sc: Color = p["color"]
			sc.a = 1.0 if k < 0.65 else (0.66 if k < 0.82 else 0.33)
			var q := int(p["shape"])
			ci.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -3 - q % 2), sp + Vector2(3 + q % 2, 2), sp + Vector2(-3, 2 + q % 3)]), sc)
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
		"puff":  # footstep / landing dust on the floor layer: a few drifting pixels
			var g := float(p["g"])
			for b in p["bits"]:
				var at: Vector2 = Vector2(p["pos"]) + Vector2(b[0], b[1]) + Vector2(b[2], b[3]) * t + Vector2(0, g * t * t * 0.5)
				var pc: Color = p["cols"][int(b[5])]
				pc.a = clampf(2.0 * (1.0 - k), 0.0, 1.0)
				ci.draw_rect(Rect2(at.round(), Vector2.ONE * (float(b[4]) if k < 0.6 else maxf(1.0, float(b[4]) - 1.0))), pc)
		"burst":  # hit-spark rays, snapped to whole pixels
			var bc: Color = p["color"]
			var bpos: Vector2 = p["pos"]
			var r0 := float(p["r0"])
			var r1 := float(p["r1"])
			var bw := float(p["width"])
			bc.a *= 1.0 - k * k
			var edge := float(p.get("edge", 0.0))
			for pass_i in (2 if edge > 0.0 else 1):  # a dark outline under the rays first (Hit markers: High contrast)
				var outline_pass := pass_i == 0 and edge > 0.0
				var lc: Color = Color(p["edge_color"], bc.a) if outline_pass else bc
				var lw := bw + edge if outline_pass else bw
				var bi := 0
				for a in p["angs"]:
					var d := Vector2.from_angle(a)
					var base := lerpf(r0, r1, sqrt(k))
					var ln := float(p["lens"][bi]) * (1.0 - k)
					var s0 := (bpos + d * base).round()
					var s1 := (bpos + d * (base + maxf(1.0, ln))).round()
					if outline_pass:  # the outline reaches past both ends too
						s0 = (s0 - d * edge * 0.5).round()
						s1 = (s1 + d * edge * 0.5).round()
					ci.draw_line(s0, s1, lc, lw)
					bi += 1
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
			var gs := ArtScale.scale_of(int(p.get("ppu", 1)))  # sheet pixels to world units
			ci.draw_set_transform(feet, 0.0, Vector2(-gs.x if bool(p["flip"]) else gs.x, gs.y))
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
		"wallmark":
			_draw_wallmark(ci, p)
		"wallflash":
			_draw_wallflash(ci, p)
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
		var ps := ArtScale.scale_of(int(p.get("ppu", 1)))  # sheet pixels to world units
		ci.draw_set_transform(at, float(p["rot"]), Vector2(-ps.x if bool(p["flip"]) else ps.x, ps.y))
		ci.draw_texture_rect_region(p["tex"], Rect2(-ox, -h * 0.5, region.size.x, h), region)
		var eyes: Array = p.get("x_eyes", [])
		var vel: Vector2 = p["vel"]
		if not eyes.is_empty() and bool(p.get("grounded", false)) and vel.length() < 0.15 \
				and absf(float(p.get("vrot", 0.0))) < 0.02:
			var bc := float(p["band_c"])
			var k := float(p.get("ppu", 1))  # the X's in sheet pixels: as big in the world at any ppu
			for e in eyes:
				var ex := float(e[0]) - ox
				var ey := float(e[1]) - bc
				ci.draw_rect(Rect2(ex - k, ey - k, 3 * k, 3 * k), C_HEAD)
				ci.draw_line(Vector2(ex - k, ey - k), Vector2(ex + 2 * k, ey + 2 * k), C_OUTLINE, k)
				ci.draw_line(Vector2(ex - k, ey + 2 * k), Vector2(ex + 2 * k, ey - k), C_OUTLINE, k)
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


## The kinds drawn flat on the floor before anything else, and those that stand under the
## fighters unless marked "front" (_paint's floor pass).
const FLAT_KINDS := {"puddle": true, "decal": true, "ripple": true, "lost": true, "puff": true,
	"wallmark": true, "wallflash": true}
const UNDER_KINDS := {"spire": true, "root": true}


func _draw_shadow(ci: CanvasItem, p: Dictionary) -> void:
	var s := 2.0 if String(p["kind"]) == "drop" else (8.0 if bool(p.get("piece", false)) else float(p.get("size", 2.0)))
	var z := float(p["z"])
	var a := clampf(0.3 - z * 0.006, 0.08, 0.3)
	# An ellipse 1.2 s wide and 0.48 s tall, as a texture: one batched quad instead of a
	# transform, a tessellated circle and a transform back (3 commands that break batching).
	var r := s * 0.6
	var size := Vector2(r * 2.0, r * 0.8)
	ci.draw_texture_rect(_shadow_tex(r), Rect2(Vector2(p["pos"]) - size * 0.5, size), false, Color(0, 0, 0, a))


## A white ellipse of radius `r` (squashed to 0.4 tall), rasterised at 4 texels a canvas
## unit, hard-edged like draw_circle; one per radius, kept.
static var _shadows := {}


static func _shadow_tex(r: float) -> Texture2D:
	var key := snappedf(r, 0.25)
	if _shadows.has(key):
		return _shadows[key]
	var w := maxi(2, ceili(key * 2.0 * 4.0))
	var h := maxi(1, ceili(key * 0.8 * 4.0))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := (x + 0.5) / w * 2.0 - 1.0
			var dy := (y + 0.5) / h * 2.0 - 1.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_shadows[key] = tex
	return tex


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
	var view := _view_rect(ci, CULL_PAD)
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
			_draw_trail(ci, pr, _proj_style(pr), view)
			match _proj_kind(pr):
				"knife":
					_draw_thrown_knife(ci, pr)
				"fire":
					_draw_fireball(ci, pr)
				"mallet", "cleaver":
					_draw_spinner(ci, pr, _proj_kind(pr))
				"venom":
					_draw_venom(ci, pr)
				"head":
					pass  # Mountain Maw: drawn with Craglash's sprite (_draw_long_bite)
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
	return String(_proj_style(pr)["kind"])


## A shot's look data, worked out once per owner and move: its kind, trail colour and height,
## and landing mark (the move's fx keys over PROJ_STYLE).
func _proj_style(pr: Dictionary) -> Dictionary:
	var key := "%d/%s" % [int(pr["owner"]), String(pr.get("move", ""))]
	if _pstyles.has(key):
		return _pstyles[key]
	var kind := "rod"
	var fx := {}
	var owner := _creature(int(pr["owner"]))
	if owner != null and pr.has("move"):
		fx = owner.moves().get(String(pr["move"]), {}).get("fx", {})
		kind = String(fx.get("projectile", "rod"))
	var base: Array = PROJ_STYLE.get(kind, [Color("e8e4d8"), 12.0, "scuff"])
	var st := {"kind": kind, "color": base[0], "z": float(base[1]), "mark": String(base[2])}
	if fx.has("trail_color"):
		st["color"] = Color(String(fx["trail_color"]))
	if fx.has("trail_z"):
		st["z"] = float(fx["trail_z"])
	if fx.has("land_mark"):
		st["mark"] = String(fx["land_mark"])
	_pstyles[key] = st
	return st


## Whole-pixel afterimages along the path a shot just flew (it moves in a straight line, so
## its last positions are `pos - vel * k`): three squares fading back, spaced about 5 px.
func _draw_trail(ci: CanvasItem, pr: Dictionary, st: Dictionary, view: Rect2) -> void:
	var z := float(st["z"])
	var pp: Vector2 = pr["pos"]
	if z < 0.0 or not view.has_point(pp):
		return
	var vel: Vector2 = pr["vel"]
	var sp := vel.length()
	if sp < 0.5:
		return
	var gap := float(maxi(1, roundi(5.0 / sp)))
	var col: Color = st["color"]
	for i in TRAIL_STEPS:
		var at := (pp - vel * gap * float(i + 1) + Vector2(0, -z)).round()
		var s := 3.0 if i == 0 else 2.0
		ci.draw_rect(Rect2(at - Vector2.ONE, Vector2(s, s)), Color(col, TRAIL_ALPHA[i]))


func _snap_projectiles() -> void:
	_proj_prev.clear()
	for pr in sim.projectiles:
		if not bool(pr.get("lob", false)):
			_proj_prev.append([int(pr["owner"]), pr["pos"], pr["vel"], _proj_style(pr)])


## Where a shot ends: a puff, and for one that hit nothing a lasting mark on the floor (its
## `land_mark`). Told apart from the last tick's shots by owner and where it should have got to.
func _land_mark(p: Vector2, power: float) -> void:
	if sim == null or not _view_rect(self, CULL_PAD).has_point(p):
		return
	var best := -1
	var bd := 1600.0
	for i in _proj_prev.size():
		var q: Array = _proj_prev[i]
		var d := (Vector2(q[1]) + Vector2(q[2])).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return
	var q: Array = _proj_prev[best]
	var st: Dictionary = q[3]
	var vel: Vector2 = q[2]
	_proj_prev.remove_at(best)
	var cell := sim.terrain.world_to_cell(p)
	if power >= 1.0 and TerrainGrid.blocks_shot(sim.terrain.get_cell(cell)):
		_wall_burst(p, vel.normalized(), 0, p)  # a rubble wall took it: dust and chips
		return
	if power < 1.0:
		_dust(p, Vector2(0, -0.3))
	var mark := String(st["mark"])
	if mark != "none" and (power < 1.0 or mark == "splat"):
		_wear_mark(mark, p, vel)


# ------------------------------------------------------------------ wall reactions

## A body knocked into the boundary wall or a rubble wall: dust, a white flash, chips, and on
## the boundary wall cracks that stay a while. Bigger knockback, bigger splat.
func _wall_reaction(e: Dictionary, p: Vector2, power: float) -> void:
	var c := _creature(int(e.get("who", -1)))
	if c == null or sim == null or not _view_rect(self, CULL_PAD).has_point(p):
		return
	var tier := 0 if power < 4.0 else (1 if power < 8.0 else 2)
	var lo := c.floor_min()
	var hi := c.floor_max()
	var n := Vector2.ZERO
	var edge := false
	if p.x <= lo.x + 1.0:
		n = Vector2.LEFT
		edge = true
	elif p.x >= hi.x - 1.0:
		n = Vector2.RIGHT
		edge = true
	elif p.y <= lo.y + 1.0:
		n = Vector2.UP
		edge = true
	elif p.y >= hi.y - 1.0:
		n = Vector2.DOWN
		edge = true
	else:
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var v := sim.terrain.get_cell(sim.terrain.world_to_cell(p + d * (c.radius + 2.0)))
			if TerrainGrid.blocks_body(v):
				n = d
				break
	if n == Vector2.ZERO:
		return
	var q := p + n * (c.radius if n.x != 0.0 else 0.0)
	_wall_burst(q, n, tier, q + Vector2(0, -8))
	if edge:
		_wall_crack(q, n, tier)


## Dust blowing off a wall, chips falling and a white flash on the face at `face`.
func _wall_burst(q: Vector2, n: Vector2, tier: int, face: Vector2) -> void:
	var pal: Array[Color] = C_STONE if String(sim.arena.get("ground", "dirt")) in ["dirt", "grass"] else C_CON
	for i in 3 + tier * 3:
		var side := n.orthogonal() * randf_range(-0.5, 0.5)
		_dust(face + n.orthogonal() * randf_range(-5.0, 5.0) * (1 + tier) - n * 2.0,
			-n * randf_range(0.2, 0.6) + side + Vector2(0, randf_range(-0.5, -0.1)))
	for i in 3 + tier * 3:
		_chunk(q - n * 2.0, randf_range(6.0, 16.0), -n * randf_range(0.1, 0.5) + n.orthogonal() * randf_range(-0.3, 0.3),
			randf_range(0.3, 1.0), randf_range(2.0, 3.0), pal[randi() % 3], 50.0)
	_add({"kind": "wallflash", "pos": face, "life": 6, "tier": tier, "real": true})


## Cracks spreading on the boundary wall face at `q`, fading over 10 to 20 s. Skipped when one
## is already fresh there (a combo into the same spot); the oldest goes past the cap.
func _wall_crack(q: Vector2, n: Vector2, tier: int) -> void:
	var at := (q + (Vector2(0, -10) if n.y <= 0.0 else Vector2(0, 5))).round()
	for m in _wall_marks:
		if float(m["t"]) < 40.0 and float(m["t"]) < float(m["life"]) and Vector2(m["pos"]).distance_to(at) < 5.0:
			return
	var lines: Array = []
	for i in 3 + tier * 2:
		var a := randf() * TAU
		var pts := PackedVector2Array([Vector2.ZERO])
		var cur := Vector2.ZERO
		for j in 2 + tier:
			a += randf_range(-0.7, 0.7)
			var step := randf_range(2.0, 3.5 + tier * 1.2)
			cur += Vector2(roundf(cos(a) * step), roundf(sin(a) * step * 0.8))
			pts.append(cur)
		lines.append(pts)
	var mark := {"kind": "wallmark", "pos": at, "life": float(randi_range(600, 1200)), "lines": lines, "tier": tier,
		"light": n.y < 0.0, "real": true}
	_add(mark)
	_wall_marks.append(mark)
	while _wall_marks.size() > WALL_MARK_CAP:
		var old: Dictionary = _wall_marks.pop_front()
		old["life"] = 0.0
	_wall_marks = _wall_marks.filter(func(m): return float(m["t"]) < float(m["life"]))


func _draw_wallmark(ci: CanvasItem, p: Dictionary) -> void:
	var t := float(p["t"])
	var f := t / float(p["life"])
	var a := 1.0
	for i in FloorWear.FADE_AT.size():
		if f >= FloorWear.FADE_AT[i]:
			a = FloorWear.FADE_A[i]
	var at := Vector2(p["pos"]) + Vector2(0.5, 0.5)
	var grow := clampf(t / 8.0, 0.0, 1.0)
	var light := bool(p.get("light", false))  # the dark stands wall takes pale cracks
	var main := Color("e0d8cc") if light else C_CRACK
	var edge := Color(C_CRACK, 0.16 * 5.0) if light else Color(1, 1, 1, 0.16)
	ci.draw_rect(Rect2(at + Vector2(-1.5, -1.5), Vector2(3, 3)), Color(main, 0.9 * a))
	for pts: PackedVector2Array in p["lines"]:
		var shifted := PackedVector2Array()
		var lit := PackedVector2Array()
		for q in pts:
			shifted.append(at + q)
			lit.append(at + q + Vector2(1, 1))
		_draw_partial_line(ci, shifted, grow, Color(main, 0.9 * a))
		_draw_partial_line(ci, lit, grow, Color(edge, edge.a * a))
	if int(p["tier"]) >= 2:
		ci.draw_rect(Rect2(at + Vector2(-2.5, -2.5), Vector2(5, 5)), Color(C_CRACK, 0.35 * a))


func _draw_wallflash(ci: CanvasItem, p: Dictionary) -> void:
	var step := mini(int(float(p["t"])), 5)
	var tier := int(p["tier"])
	var w := 8.0 + tier * 4.0
	var h := 6.0 + tier * 3.0
	var at := (Vector2(p["pos"]) - Vector2(w, h) * 0.5).round()
	var alpha: Array[float] = [0.9, 0.75, 0.55, 0.38, 0.22, 0.1]
	ci.draw_rect(Rect2(at, Vector2(w, h)), Color(1, 1, 1, alpha[step]))


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


## Mountain Maw (a sprite block with "neck_end": Craglash): his own head flies on his own
## stone neck. While the sprite shows a headless frame (its "headless" list: lash 5-7, the
## neck stretched to "neck_end" with an end stone and no head), this draws the rest:
## the neck's stones (the sheet's maw_slab row, one every MAW_SLAB px at full thickness, on
## a slight arc that leaves the sprite's neck along "neck_dir") out to the head (maw_head:
## jaws open, then shut, every 4 ticks of the flight, by the projectile's own life so a
## rollback replays it), which rides the projectile from the neck's end and drops a little
## toward the bite. When the projectile ends the head holds through his hitstop (a bite's
## freeze), then snaps home along the chain in MAW_SNAP ticks, jaws shut, the stones
## vanishing behind it; whenever a headless
## frame shows and no head of his flies, his head sits on the neck's end, so he is never
## headless on screen. The sprite's frames 8-11 (head attached) take over from tick 48.
## Hit mid-flight: while the head is out (flying, or snapping home after a flight that ended
## with him in a reaction), `head_out` on his view swaps his hurt and guard rows for their
## headless twins (hurt_nohead, guard_nohead: the neck stretched to the same neck_end), so the
## chain carries on from his neck as in the throw. The head and chain are drawn only while
## the sprite shows a headless frame: in any other row (a knockdown or knockout, a dodge,
## idle after a short stun) the flying head is not drawn and his sprite keeps its own.
##
## Drawn on two children of his CreatureView (`_update_maws`), with his material, light
## mask, modulate and the sprite's weather tint, so the chain flashes, turns to stone,
## changes palette, darkens at night and hides with him, and y-sorts with him. Facing down, down-right or sideways the chain is in front of
## his body (it comes toward the camera); facing up or up-right it is behind it.
const MAW_SNAP := 5  ## ticks for the head to snap home
## The reactions whose rows have a headless twin (hurt_nohead, guard_nohead, ko_nohead): a head
## that came home during one stays on that twin's neck until the state ends.
const MAW_HOLD := [CreatureSim.State.HITSTUN, CreatureSim.State.GUARD,
	CreatureSim.State.CRUMPLE, CreatureSim.State.AIRBORNE, CreatureSim.State.FALLING, CreatureSim.State.KNOCKDOWN]
const MAW_KO_BURST := 18  ## the ko row's frame 3 (6 ticks a frame): the neck bursts, the head is down
const MAW_SLAB := 5.0  ## px between the chain's stones (the rig's SLAB_SPACING)
const MAW_DROP := 14.0  ## how far the head drops toward the bite...
const MAW_DROP_RUN := 60.0  ## ...over this much of its flight
## creature id -> {"serial", "rel" (the head from the neck's end), "vel", "tick", "off" (the
## projectile's offset), "flying", "react" (a snap back that started outside his Maw)}: the
## last flight seen
var _maw := {}


## Gives each view whose sprite block has "neck_end" its two maw layers and redraws them.
func _update_maws() -> void:
	if sim == null:
		return
	for v in views:
		if v == null or not (v as CreatureView).layout.has("neck_end"):
			continue
		var cv: CreatureView = v
		cv.head_out = _maw_out(cv.c)
		var back := cv.get_node_or_null("MawBack") as Node2D
		if back == null:
			back = _maw_layer(cv, "MawBack", false)
			cv.add_child(back)
			cv.move_child(back, 0)  # before the pivot: behind the sprite
			cv.add_child(_maw_layer(cv, "MawFront", true))
		var fr := cv.get_node("MawFront") as Node2D
		for n: Node2D in [back, fr]:
			n.light_mask = cv.sprite.light_mask  # lit like the sprite (its normals come with the sheet)
			n.self_modulate = cv.sprite.self_modulate  # and tinted like it (WeatherView: the night, the weather)
			n.queue_redraw()


func _maw_layer(cv: CreatureView, node_name: String, front: bool) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.material = cv.mat
	n.draw.connect(func() -> void: _draw_long_bite(n, cv, front))
	return n


## Whether `c`'s head is off his neck now (his head projectile flies, or a snap back that began
## outside his Maw is running), recording the flight while it lasts so `_maw_end` can snap
## the head home from where it was even when he is no longer throwing.
func _maw_out(c: CreatureSim) -> bool:
	if c == null:
		return false
	var pr := _maw_projectile(c)
	if not pr.is_empty():
		var fwd := Vector2(pr["vel"]).normalized()
		var off := float(c.moves().get(String(pr.get("move", "")), {}).get("projectile", {}).get("offset", 16))
		_maw[c.id] = {"serial": int(pr["serial"]), "vel": pr["vel"], "tick": sim.tick, "off": off, "flying": true,
			"rel": _maw_rel(fwd, maxf(0.0, (Vector2(pr["pos"]) - c.pos).dot(fwd) - off))}
		return true
	var m: Dictionary = _maw.get(c.id, {})
	if not bool(m.get("react", false)):
		return false
	if sim.tick < int(m["tick"]) + MAW_SNAP:
		return true
	# Home on the headless twin: it stays to the end of the reaction (the head on the neck's
	# end), so the head never jumps onto the hurt or guard pose's own head spot; a knockout
	# holds it until the neck bursts (ko frame 3), where the ko row's head lies on the floor.
	if c.state in MAW_HOLD or (c.state == CreatureSim.State.KO and c.state_t < MAW_KO_BURST):
		return true
	m["react"] = false
	return false


## Where the head is from the neck's end, `s` px along the flight `fwd`.
static func _maw_rel(fwd: Vector2, s: float) -> Vector2:
	return fwd * s + Vector2(0, minf(s, MAW_DROP_RUN) / MAW_DROP_RUN * MAW_DROP)


## His head projectile in flight, or {}.
func _maw_projectile(c: CreatureSim) -> Dictionary:
	for pr in sim.projectiles:
		if int(pr["owner"]) == c.id and _proj_kind(pr) == "head":
			return pr
	return {}


## What to draw for `c` now, in his view's local space: {} for nothing, else "home" (the
## neck's end), "dir" (the neck's direction there), "head", "open", "vel", "front", "flying".
func _maw_state(c: CreatureSim, cv: CreatureView) -> Dictionary:
	var ends: Dictionary = cv.layout.get("neck_end", {})
	var sv := cv.sheet_view()  # a side-only row (ko_nohead) facing down still ends on the side sheet's neck
	if not ends.has(sv):
		return {}
	var sx := -1.0 if cv.flip else 1.0
	var e: Array = ends[sv]
	var nd: Array = cv.layout.get("neck_dir", {}).get(sv, [1, 0])
	var home := cv.pivot.position + Vector2(float(e[0]) * sx, float(e[1]))
	var out := {"home": home, "dir": Vector2(float(nd[0]) * sx, float(nd[1])), "head": home, "open": false,
		"vel": Vector2(sx, 0), "front": not sv in ["up", "up_side"], "flying": false}
	if not cv.headless():
		return {}  # his sprite has its own head showing: draw no other
	var pr := _maw_projectile(c)
	if not pr.is_empty():
		var vel: Vector2 = pr["vel"]
		var fwd := vel.normalized()
		var off := float(c.moves().get(String(pr.get("move", "")), {}).get("projectile", {}).get("offset", 16))
		var rel := _maw_rel(fwd, maxf(0.0, (Vector2(pr["pos"]) - c.pos).dot(fwd) - off))
		var flown := int(pr.get("life_total", pr["life"])) - int(pr["life"])
		out["head"] = home + rel
		out["open"] = (flown / 4) % 2 == 0
		out["vel"] = vel
		out["flying"] = true
		out["floor"] = Vector2(pr["pos"]) - cv.position
		return out
	var m: Dictionary = _maw.get(c.id, {})
	if not m.is_empty() and not bool(m.get("flying", false)) 			and (bool(m.get("react", false)) or int(m["serial"]) == c.attack_serial):
		# the snap back: slow to start, fast home, keyed on the sim's tick
		var u := clampf(float(sim.tick - int(m["tick"])) / MAW_SNAP, 0.0, 1.0)
		out["head"] = home + Vector2(m["rel"]) * (1.0 - u * u)
		out["vel"] = m["vel"]
	return out


## The projectile ended (hit or not): where his head was, so the snap back starts there even
## when it bit on its first tick and was never drawn in flight.
func _maw_end(c: CreatureSim, p: Vector2) -> void:
	if sim == null or not c.def.get("sprite", {}).has("neck_end"):
		return
	var mv := c.move_def() if c.state == CreatureSim.State.ATTACK else {}
	if String(mv.get("fx", {}).get("projectile", "")) != "head":
		# hit (or otherwise out of his Maw) while the head flew: snap it home from where it
		# was, onto the headless reaction row his view shows while head_out
		var last: Dictionary = _maw.get(c.id, {})
		if not bool(last.get("flying", false)):
			return
		var lf := Vector2(last["vel"]).normalized()
		_maw[c.id] = {"serial": -1, "react": true, "vel": last["vel"], "off": last["off"],
			"rel": _maw_rel(lf, maxf(0.0, (p - c.pos).dot(lf) - float(last["off"]))),
			"tick": sim.tick + maxi(sim.hitstop, c.hitstop)}
		return
	var fwd := c.facing.normalized()
	var off := float(mv.get("projectile", {}).get("offset", 16))
	# a bite holds through his hitstop (the impact's freeze), then the head snaps home
	_maw[c.id] = {"serial": c.attack_serial, "rel": _maw_rel(fwd, maxf(0.0, (p - c.pos).dot(fwd) - off)),
		"vel": c.facing, "tick": sim.tick + maxi(sim.hitstop, c.hitstop)}


## One maw layer of `cv` (front or back): the shadow, the chain's stones, then the head.
func _draw_long_bite(ci: Node2D, cv: CreatureView, front: bool) -> void:
	var c := cv.c
	if sim == null or c == null or not cv.pivot.visible:
		return
	var st := _maw_state(c, cv)
	if st.is_empty() or bool(st["front"]) != front:
		return
	var home: Vector2 = st["home"]
	var tip: Vector2 = st["head"]
	if bool(st["flying"]):
		var fl: Vector2 = st["floor"]
		ci.draw_set_transform(fl.round(), 0.0, Vector2(1.0, 0.4))
		ci.draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.28))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var span := home.distance_to(tip)
	if span > MAW_SLAB + 2.0:
		# a quadratic arc leaving the sprite's neck along neck_dir, a stone every MAW_SLAB px
		# from the neck's end stone up to the head
		var ctrl := home + Vector2(st["dir"]) * minf(span * 0.3, 14.0)
		var n := 24
		var pts := PackedVector2Array()
		for i in n + 1:
			var k := float(i) / n
			pts.append(home.lerp(ctrl, k).lerp(ctrl.lerp(tip, k), k))
		var stones: Array = []
		var acc := 0.0
		var next := MAW_SLAB
		var stop := span - 4.0
		for i in n:
			var seg := pts[i].distance_to(pts[i + 1])
			while seg > 0.0 and next <= acc + seg and next <= stop:
				stones.append([pts[i].lerp(pts[i + 1], (next - acc) / seg), pts[i + 1] - pts[i]])
				next += MAW_SLAB
			acc += seg
		if not front:
			stones.reverse()  # going away from the camera: the nearer stones over the further
		for sd in stones:
			var t: Vector2 = sd[1]
			var k := int(roundf(fposmod(rad_to_deg(t.angle()), 180.0) / 18.0)) % 10
			_maw_piece(ci, cv, "maw_slab", k, sd[0], false, 0.0)
	var rot := 0.0
	if cv.sheet_view() == "side":
		var vel: Vector2 = st["vel"]
		rot = atan2(vel.y, absf(vel.x)) * (-1.0 if cv.flip else 1.0)  # along the flight
	_maw_piece(ci, cv, "maw_head", 0 if bool(st["open"]) else 1, tip, cv.flip, rot)


## Frame `idx` of `anim` (drawn on the sheet with its middle at the neck's end) with that
## middle at `at`, mirrored by `flip`, turned by `rot`.
func _maw_piece(ci: CanvasItem, cv: CreatureView, anim: String, idx: int, at: Vector2, flip: bool, rot: float) -> void:
	var fp := cv.frame_piece(anim, idx)
	if fp.is_empty():
		return
	var e: Array = cv.layout["neck_end"].get(cv.sheet_view(), [0, 0])
	var ppu := int(fp["ppu"])
	var mid: Vector2 = Vector2(fp["origin"]) + Vector2(float(e[0]), float(e[1])) * float(ppu)
	var gs := ArtScale.scale_of(ppu)
	ci.draw_set_transform(ArtScale.snap(at, ppu), rot, Vector2(-gs.x if flip else gs.x, gs.y))
	ci.draw_texture_rect_region(fp["tex"], Rect2(-mid, fp["size"]), fp["region"])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Who's who, and how they're doing: a health bar over each fighter, League-style.
## Its colour says whose it is (`rel` in side_marks: "self" green, "ally" blue, "enemy"
## red; "side" uses the side colours, red left and blue right, when nobody here plays or
## two local players face each other; all from `Accessibility`, so Settings > Accessibility
## > Team colours swaps them, `mark_color`). Ticks every 25 health, a pale trail that drains
## after a hit, a stone segment for a shield (Stoneskin), a thin Surge strip under it,
## and the player label (P1, CPU...) above. Hidden once knocked out; an invisible fighter
## (Tiptoe) shows his bar only to his own side, faintly.
const PLATE_W := 30.0
const PLATE_H := 3.0
const HP_TICK := 25.0
const C_TRAIL := Color("f4e6c8")
const C_SHIELD := Color("d8d4cc")
var _trail := {}  ## creature -> [trail hp, ticks to hold before draining, last hp]


## Slot `i`'s marker colour now (its bar, its label, its Team outline): by `rel`, else its
## Brawl colour, else its side's; read live, so a Team colours change shows at once.
func mark_color(i: int) -> Color:
	if i < 0 or i >= side_marks.size():
		return Color.WHITE
	var mk: Dictionary = side_marks[i]
	var b := int(mk.get("brawl", -1))
	var fallback: Color = Accessibility.brawl_color(b) if b >= 0 \
		else (Accessibility.side_color(int(mk["team"])) if mk.has("team") else Color(mk.get("color", Color.WHITE)))
	return Accessibility.rel_color(String(mk.get("rel", "side")), fallback)


## Team Deathmatch spawn pads (set by main): a ring on the floor in the team's colour, and
## the seconds until someone comes back on it. Drawn as a true circle, like every floor area.
## Each: {"pos": Vector2, "color": Color, "count": seconds (0: nobody waiting)}.
var pads: Array = []
## King of the Crater's zone (set by main): {"pos", "radius", "color"}; empty when none.
var zone := {}
## The Caravan (set by main): {"pos", "heading", "radius", "state" (-1 back, 0 still,
## 1 pushed, 2 contested, 3 digging through a rockslide), "team" (the attackers), "travel"
## (px moved, turns the wheels), "healing" (ids of the escort healing)}; empty when none.
var caravan := {}
## Capture the Flag's flags (set by main): each {"pos", "team", "state" (TeamSim.FLAG_*),
## "lift" (px above the floor: over a carrier's head), "back" (0..1 of a dropped flag's
## return timer left)}.
var flags: Array = []
## The match's shrines (set by main, any mode with them): each {"pos", "radius", "kind"
## (haste, might), "side" claiming (-1), "claim_color" (its colour), "claim" (0..1), "rest"
## (seconds until ready, 0: ready), "charge" (0..1 through the last seconds before it's
## ready, 0 otherwise)}.
var shrines: Array = []
## Who is wanted (set by main): per slot {} or {"kind": "spree", "level"} (Team Deathmatch)
## or {"kind": "crown"} (the Brawl crown), drawn over the health bar (`_draw_wanted`).
var wanted: Array = []
## Voice chat: creature slots speaking now -> level (VoiceView.heard): a speaker icon by
## their name plate.
var speaking := {}
const CROWN_GOLD := Color("ffd84a")
const CROWN_SHADE := Color("c08a1c")
const SPREE_HOT := Color("ff7a3a")
const SPREE_CORE := Color("ffe08a")
const SPREE_DEEP := Color("d8361f")
## The spree flame, two frames (o outline, d deep red, r orange, y the hot core).
const FLAME := [
	["....o....", "...odo...", "...orro..", "..ordro.o", "..orrroro", ".odrrrrro", ".orryrrro",
		"odryyyrro", "orryyyyro", "orryyyyro", ".orryyro.", "..odrro..", "...ooo..."],
	["...o.....", "..odo....", "..orro...", "o.ordro..", "ororrro..", "orrrrrdo.", "orrryrro.",
		"orryyyrdo", "orryyyyro", "orryyyyro", ".orryyro.", "..orrdo..", "...ooo..."],
]
const SHRINE_COLORS := {"haste": Color("6fe0ff"), "might": Color("ff9a3c"), "boost": Color("ffd84a")}
## The Crater shrine's permanent buffs, one pip each under a fighter's health bar.
const BOOST_COLORS := {"damage": Color("ff7a4a"), "speed": Color("6fe0ff"), "hp": Color("7ae07a"),
	"regen": Color("ffd84a")}


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
		var col: Color = Accessibility.side_color(int(pd["side"])) if pd.has("side") else pd["color"]
		var r := 16.0 + 1.0 * sin(float(_tick) * 0.08)
		ci.draw_circle(at, r, Color(col, 0.16))
		ci.draw_arc(at, r, 0.0, TAU, 32, Color(col, 0.75), 2.0)
		ci.draw_arc(at, r * 0.55, 0.0, TAU, 24, Color(col, 0.35), 1.0)
		var n := int(pd.get("count", 0))
		if n > 0:
			var txt := str(n)
			ci.draw_string_outline(_font, at + Vector2(-20, -10), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, UiTheme.px(12), 2, C_OUTLINE)
			ci.draw_string(_font, at + Vector2(-20, -10), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, UiTheme.px(12), col)


## The Caravan: its push radius on the floor (the attackers' colour while they push, gold
## when contested, grey rolling back), a shadow, the wagon facing the way it's headed with
## its wheels turning as it goes, and the attackers' flag on top.
func _draw_caravan(ci: CanvasItem) -> void:
	var at: Vector2 = caravan["pos"]
	var team := int(caravan.get("team", 0))
	var st := int(caravan.get("state", 0))
	var team_col: Color = Accessibility.side_color(clampi(team, 0, 1))
	var col := team_col
	if st == 2:
		col = Color("e8c060")
	elif st == -1:
		col = Color(0.62, 0.62, 0.66)
	elif st == 0:
		col = Color(team_col, 0.55)
	elif st == 3:
		col = Color("d08a40")  # digging through rubble
	var r := float(caravan.get("radius", 56))
	ci.draw_circle(at, r, Color(col, 0.08 if st == 0 else 0.13))
	var spin := float(_tick) * (0.05 if st == 1 else (-0.03 if st == -1 else (0.012 if st == 3 else 0.0)))
	if st == 3 and _tick % 6 == 0:  # dust where it's digging
		var front: Vector2 = at + Vector2(caravan.get("heading", Vector2.RIGHT)) * 22.0
		_dust(front + Vector2(randf_range(-8, 8), randf_range(-6, 6)), Vector2(randf_range(-0.4, 0.4), -0.3))
	for id in caravan.get("healing", []):  # the escort healing: small crosses rising off them
		var c := _creature(int(id))
		if c != null and shown(c) and (_tick + int(id) * 11) % 20 == 0:
			_add({"kind": "heal", "pos": c.pos + Vector2(randf_range(-6, 6), -_top(c) * 0.5), "vel": Vector2(0, -0.5),
				"life": 30})
	for k in 12:  # a dashed rim that turns the way the caravan is going
		var a0 := spin + k * TAU / 12.0
		ci.draw_arc(at, r, a0, a0 + TAU / 20.0, 6, Color(col, 0.85), 2.0)
	# the wagon
	var heading: Vector2 = caravan.get("heading", Vector2.RIGHT)
	var flip := heading.x < 0.0
	var frame := int(float(caravan.get("travel", 0.0)) / 3.0) % 4
	var light := ShadowLayer.light_of(sim.arena if sim != null else {})  # its shadow along the map's light
	ShadowLayer.draw_silhouette(ci, CARAVAN, Rect2(frame * 48, 0, 48, 40), Vector2(24, 36), flip, at,
		light["cast"], float(light["alpha"]))
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
	var col: Color = Accessibility.side_color(clampi(int(f["team"]), 0, 1))
	var st := int(f["state"])
	var foot := at - Vector2(0, float(f.get("lift", 0.0)))
	if st != TeamSim.FLAG_CARRIED:  # the pole's and the cloth's shadow along the map's light
		var k := 1.0 if st != TeamSim.FLAG_THROWN else maxf(0.5, 1.0 - float(f.get("lift", 0.0)) * 0.012)
		var light := ShadowLayer.light_of(sim.arena if sim != null else {})
		var cast: Vector2 = light["cast"] * k
		var a := float(light["alpha"]) * k
		ci.draw_line(at.round(), (at + cast * 20.0).round(), Color(0, 0, 0, a), 1.0)
		ShadowLayer.draw_silhouette(ci, FLAG, Rect2((_tick / 6) % 4 * 12, 0, 12, 10), Vector2(-1, 20), false, at,
			light["cast"], a, Vector2(k, k))
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
## orange) with its sign in the middle, and a claim fills round it in the claiming team's
## colour; resting, it's dim with the seconds left. In its last seconds before it's ready
## it charges up: a ring fills round it clockwise, a light swells inside and four motes
## spiral in, quicker as it nears (true circles on the floor).
func _draw_shrine(ci: CanvasItem, s: Dictionary) -> void:
	var at: Vector2 = s["pos"]
	var r := float(s["radius"])
	var kind := String(s["kind"])
	var col: Color = SHRINE_COLORS.get(kind, Color.WHITE)
	var rest := int(s["rest"])
	ci.draw_arc(at, r, 0.0, TAU, 48, Color(0.1, 0.1, 0.12, 0.6), 3.0)
	if rest > 0:
		ci.draw_arc(at, r, 0.0, TAU, 48, Color(col, 0.25), 1.0)
		var charge := float(s.get("charge", 0.0))
		if charge > 0.0:
			var beat := 0.5 + 0.5 * sin(float(_tick) * (0.15 + 0.35 * charge))
			ci.draw_circle(at, r * (0.25 + 0.75 * charge), Color(col, 0.05 + 0.10 * charge * beat))
			ci.draw_arc(at, r + 3.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, Color(col, 0.55 + 0.4 * beat), 2.0)
			for k in 4:
				var a := float(k) * TAU / 4.0 + float(_tick) * (0.04 + 0.1 * charge)
				var d := r * (1.6 - 0.6 * charge)
				ci.draw_rect(Rect2((at + Vector2(cos(a), sin(a)) * d).floor(), Vector2(2, 2)), Color(col.lightened(0.3), 0.5 + 0.5 * charge))
		ci.draw_string_outline(_font, at + Vector2(-12, 3), str(rest), HORIZONTAL_ALIGNMENT_CENTER, 24, UiTheme.px(7), 1, Color(C_OUTLINE, 0.7))
		ci.draw_string(_font, at + Vector2(-12, 3), str(rest), HORIZONTAL_ALIGNMENT_CENTER, 24, UiTheme.px(7), Color(col, 0.6))
		return
	var glow := 0.5 + 0.5 * sin(float(_tick) * 0.12)
	ci.draw_circle(at, r, Color(col, 0.08 + 0.06 * glow))
	ci.draw_arc(at, r, 0.0, TAU, 48, Color(col, 0.7 + 0.3 * glow), 1.5)
	# The sign: haste is a double chevron, might a fist-like block, a permanent buff a plus.
	var sc := Color(col.lightened(0.3), 0.85)
	if kind == "boost":
		ci.draw_rect(Rect2(at + Vector2(-1, -5), Vector2(3, 11)), sc)
		ci.draw_rect(Rect2(at + Vector2(-5, -1), Vector2(11, 3)), sc)
	elif kind == "haste":
		for dx in [-3.0, 2.0]:
			ci.draw_polyline(PackedVector2Array([at + Vector2(dx - 2, -4), at + Vector2(dx + 2, 0), at + Vector2(dx - 2, 4)]), sc, 1.5)
	else:
		ci.draw_rect(Rect2(at + Vector2(-4, -3), Vector2(8, 6)), sc)
		ci.draw_rect(Rect2(at + Vector2(-4, -5), Vector2(8, 1)), sc)
	var side := int(s["side"])
	var claim := clampf(float(s["claim"]), 0.0, 1.0)
	if side >= 0 and claim > 0.0:
		var sidec: Color = s.get("claim_color", Accessibility.side_color(clampi(side, 0, 1)))
		ci.draw_circle(at, r * claim, Color(sidec, 0.16))  # the claim floods the floor from the middle
		ci.draw_arc(at, r + 3.0, 0.0, TAU, 48, Color(0.1, 0.1, 0.12, 0.5), 4.0)
		ci.draw_arc(at, r + 3.0, -PI * 0.5, -PI * 0.5 + TAU * claim, 48, Color(sidec, 0.95), 3.0)


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
	var view := _view_rect(ci, CULL_PAD)
	for i in mini(side_marks.size(), sim.creatures.size()):
		var c := sim.creatures[i]
		if c.state == CreatureSim.State.KO:
			_trail.erase(c)
			continue
		if not view.has_point(c.pos):
			continue  # off screen (a big map)
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
		var col := mark_color(i)
		var at := (c.pos + Vector2(0, -_top(c) - 8.0 - c.air_height() - CreatureView.view_lift(c))).round()
		_draw_plate(ci, c, at, col, alpha)
		if not c.boost_ids.is_empty():
			_draw_boost_pips(ci, c, at, alpha)
		if i < wanted.size() and not (wanted[i] as Dictionary).is_empty():
			_draw_wanted(ci, wanted[i], at + Vector2(0, -10 if String(mk.get("label", "")) != "" else -2), alpha)
		var label := String(mk.get("label", ""))
		if label != "":
			var lc := Color(col, alpha)
			ci.draw_string_outline(_font, at + Vector2(-20, -3), label, HORIZONTAL_ALIGNMENT_CENTER, 41, UiTheme.px(6), 1,
				Color(C_OUTLINE, alpha))
			ci.draw_string(_font, at + Vector2(-20, -3), label, HORIZONTAL_ALIGNMENT_CENTER, 41, UiTheme.px(6), lc)
		if speaking.has(i):
			var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.px(6)).x if label != "" else 0.0
			VoiceView.draw_glyph(ci, at + Vector2(roundf(lw * 0.5) + 3.0, -5.0 if label != "" else -3.0),
				float(speaking[i]), Color(col, alpha))


## A wanted fighter's mark, its bottom at `at` (over the bar and its label): a gold crown
## (the Brawl crown), or a flame with a pip a spree level (Team Deathmatch). Whole pixels,
## a dark outline so it reads on any floor.
func _draw_wanted(ci: CanvasItem, w: Dictionary, at: Vector2, alpha: float) -> void:
	var o := Color(C_OUTLINE, 0.9 * alpha)
	var x := roundf(at.x)
	var y := roundf(at.y)
	if String(w.get("kind", "")) == "crown":
		# A three-pointed crown, 11 x 8: points, then the band.
		var bob := float((_tick / 20) % 2)  # a one-pixel bob, so it catches the eye
		var b := y - 1.0 - bob
		ci.draw_rect(Rect2(x - 6, b - 4, 13, 5), o)
		ci.draw_rect(Rect2(x - 6, b - 9, 3, 6), o)
		ci.draw_rect(Rect2(x - 1, b - 10, 3, 7), o)
		ci.draw_rect(Rect2(x + 4, b - 9, 3, 6), o)
		ci.draw_rect(Rect2(x - 5, b - 3, 11, 3), Color(CROWN_GOLD, alpha))
		ci.draw_rect(Rect2(x - 5, b - 1, 11, 1), Color(CROWN_SHADE, alpha))
		ci.draw_rect(Rect2(x - 5, b - 8, 1, 5), Color(CROWN_GOLD, alpha))
		ci.draw_rect(Rect2(x, b - 9, 1, 6), Color(CROWN_GOLD, alpha))
		ci.draw_rect(Rect2(x + 5, b - 8, 1, 5), Color(CROWN_GOLD, alpha))
		ci.draw_rect(Rect2(x - 4, b - 5, 9, 2), Color(CROWN_GOLD, alpha))
		ci.draw_rect(Rect2(x - 1, b - 2, 2, 1), Color("ff5a5a", alpha))  # a jewel
		return
	# A flame (FLAME: 9 x 13 pixel art, two frames that flicker), and a pip a spree level beside it.
	var lv := clampi(int(w.get("level", 1)), 1, 3)
	var rows: Array = FLAME[(_tick / 8) % FLAME.size()]
	var top := y - float(rows.size())
	var cols := {"o": o, "r": Color(SPREE_HOT, alpha), "d": Color(SPREE_DEEP, alpha), "y": Color(SPREE_CORE, alpha)}
	for r in rows.size():
		var row: String = rows[r]
		for k in row.length():
			var ch := row[k]
			if cols.has(ch):
				ci.draw_rect(Rect2(x - 4.0 + k, top + r, 1, 1), cols[ch])
	for k in lv:
		var px := x + 7.0 + 5.0 * k
		ci.draw_rect(Rect2(px - 1, y - 6, 5, 5), o)
		ci.draw_rect(Rect2(px, y - 5, 3, 3), Color(SPREE_HOT, alpha))


## The Crater shrine's permanent buffs: a pip each, in the buff's colour, under the bar.
func _draw_boost_pips(ci: CanvasItem, c: CreatureSim, at: Vector2, alpha: float) -> void:
	var n := c.boost_ids.size()
	var x0 := at.x - float(n) * 3.0 + 1.0
	var y := at.y + float(PLATE_H) + 4.0
	for k in n:
		var pc: Color = BOOST_COLORS.get(String(c.boost_ids[k]), Color.WHITE)
		ci.draw_rect(Rect2(Vector2(x0 + 6.0 * k - 1.0, y - 1.0), Vector2(6, 6)), Color(C_OUTLINE, 0.9 * alpha))
		ci.draw_rect(Rect2(Vector2(x0 + 6.0 * k, y), Vector2(4, 4)), Color(pc, alpha))


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


## Chef Cerebro's Surge shots: a looping comet fireball (kiddolink FI r2) turned along its
## flight, mirrored rather than upside down when it flies left, with a small shadow below.
func _draw_fireball(ci: CanvasItem, pr: Dictionary) -> void:
	var pp: Vector2 = Vector2(pr["pos"]).round()
	var vel: Vector2 = pr["vel"]
	ci.draw_set_transform(pp, 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.25))
	var at := ArtScale.snap(pp + Vector2(0, -THROW_Z), 2)
	var s := ArtScale.scale_of(2).x * FIRE_SCALE
	# each shot starts its own loop (life counts down; 240 keeps it positive)
	var frame := posmod((240 - int(pr.get("life", 0))) / 2, FIRE_FRAMES)
	ci.draw_set_transform(at, vel.angle(), Vector2(s, -s if vel.x < 0.0 else s))
	ci.draw_texture_rect_region(FIREBALL, Rect2(-FIRE_HEAD, Vector2(VFX_FRAME, VFX_FRAME)),
		Rect2(frame * VFX_FRAME, 0, VFX_FRAME, VFX_FRAME))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Chef Cerebro's cast-iron pan while a move with fx.prop "pan" plays (his Surge): held where
## its shots leave (the projectile's `offset` ahead, THROW_Z up), turned along his aim with the
## handle back toward him, a flame licking out of it while the shots fly, fading in and out.
func _draw_held_pan(ci: CanvasItem, c: CreatureSim, mv: Dictionary) -> void:
	var p: Dictionary = mv.get("projectile", {})
	var vol: Dictionary = p.get("volley", {})
	var every := maxi(1, int(vol.get("every", 1)))
	var start := int(mv.get("startup", 0))
	var firing := start + int(vol.get("count", 1)) * every
	var length := int(mv.get("length", firing + 20))
	var t := c.state_t
	var a := clampf(minf(float(t + 1) / 3.0, float(length - t) / 8.0), 0.0, 1.0)
	if a <= 0.0:
		return
	var d := c.facing.normalized() if c.facing.length() > 0.01 else Vector2.RIGHT
	var dish := ArtScale.snap(c.pos + d * float(p.get("offset", 16)) + Vector2(0, -THROW_Z), 2)
	if t >= start and t < firing and (t - start) % every == 0:
		dish -= d.round()  # a little kick back on each shot
	var flip := d.x < 0.0
	ci.draw_set_transform(dish, d.angle(), Vector2(1.0, -1.0 if flip else 1.0))
	ci.draw_texture(PAN, -PAN_DISH, Color(1, 1, 1, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if t >= start - 3 and t < firing + 6:
		var fs := ArtScale.scale_of(2).x * FLAME_SCALE
		var frame := posmod(t / 2, FLAME_FRAMES)
		ci.draw_set_transform(dish + Vector2(0, 1), 0.0, Vector2(-fs if flip else fs, fs))
		ci.draw_texture_rect_region(PAN_FLAME, Rect2(-FLAME_BASE, Vector2(VFX_FRAME, VFX_FRAME)),
			Rect2(frame * VFX_FRAME, 0, VFX_FRAME, VFX_FRAME), Color(1, 1, 1, a))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	# The spinning rod sweeps about the hit's size (its radius widens along the flight).
	var d := Vector2.from_angle(_tick * 0.7) * maxf(13.0, float(pr.get("radius", 0.0)) * 0.8)
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
	var view := _view_rect(ci, CULL_PAD_FIGHTER)
	for c in sim.creatures:
		if not shown(c):
			continue  # no aim mark, telegraph or status icons for a fighter out of sight
		if not view.has_point(c.pos):
			continue  # far off screen: even its telegraphs can't reach the view
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
			if c.root > 0 and c.swallow_t <= 0:
				_draw_leaf_roots(ci, c, false)
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

		if attacking and String(fx.get("prop", "")) == "pan":
			_draw_held_pan(ci, c, mv)

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
	for seg in mv.get("_segs", []):  # the widest hit of the move (a Surge may grow per segment)
		r = maxf(r, float(seg.get("hit_radius", 0.0)))
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


## Rooted by Barkley: roots curled over the feet, drawn in the 32 px grid (half a unit a
## pixel), a leaf on every other one that flickers. They push up over ROOT_GROW ticks from
## the `rooted` event and sink back over the root's last ROOT_SINK. `front`: the near half
## of the ring (over the fighter), else the far half (the floor pass, behind the legs).
const ROOT_MARKS := 6
const ROOT_GROW := 6.0
const ROOT_SINK := 8.0
## One root in grid pixels, curling right (mirrored for the ones on the right of the
## feet, so each curls in over them): [x, y, w, h, colour], 0 = wood, 1 = light wood.
const ROOT_SHAPE := [[0, -7, 2, 7, 0], [1, -9, 3, 2, 0], [3, -7, 1, 2, 0], [0, -7, 1, 5, 1]]
const ROOT_TALL := 9.0


func _draw_leaf_roots(ci: CanvasItem, c: CreatureSim, front: bool) -> void:
	var grow := clampf((_tick - int(_root_t.get(c.id, _tick - 99))) / ROOT_GROW, 0.0, 1.0)
	var k := minf(grow, clampf(c.root / ROOT_SINK, 0.0, 1.0))
	var sink := roundf(ROOT_TALL * (1.0 - k))  # grid pixels still under the floor
	if sink >= ROOT_TALL:
		return
	for i in ROOT_MARKS:
		var a := TAU * i / ROOT_MARKS + 0.4
		if (sin(a) > 0.0) != front:
			continue
		var base := ArtScale.snap(c.pos + Vector2(cos(a) * (c.radius + 1.0), sin(a) * 3.0), 2)
		var flip := cos(a) > 0.0  # right of the feet: curl left, in over them
		ci.draw_set_transform(base, 0.0, Vector2(-0.5 if flip else 0.5, 0.5))
		for pass_i in 2:
			for r in ROOT_SHAPE:
				var y0 := float(r[1]) + sink
				var y1 := minf(y0 + float(r[3]), 0.0)
				if y1 <= y0:
					continue
				var rect := Rect2(float(r[0]), y0, float(r[2]), y1 - y0)
				if pass_i == 0:
					ci.draw_rect(rect.grow(1.0), C_OUTLINE)
				else:
					ci.draw_rect(rect, C_WOOD[2] if int(r[4]) == 1 else C_WOOD[1])
		if i % 2 == 0 and sink <= 0.0:
			ci.draw_rect(Rect2(-2, -11, 2, 2).grow(1.0), C_OUTLINE)
			ci.draw_rect(Rect2(-2, -11, 2, 2), C_LEAF[1 + (i + _tick / 12) % 2])
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	if c.slow > 0 or c.carry_mult < 1.0:  # slowed, or weighed down by a flag it carries
		for i in 3:
			var a := _tick * 0.12 + TAU * i / 3.0
			var at := (c.pos + Vector2(cos(a) * (c.radius + 2.0), sin(a) * 3.0 - 1.0)).round()
			ci.draw_rect(Rect2(at - Vector2(1, 1), Vector2(3, 2)), C_OUTLINE)
			ci.draw_rect(Rect2(at - Vector2(0, 1), Vector2(1, 1)), C_GREY[2])
		_draw_slow_motes(ci, c)
	if c.stone > 0:
		_draw_statue(ci, c, lift)
	elif c.state == CreatureSim.State.CRUMPLE and c.stun > 0:
		_draw_birdies(ci, c, lift)
	if c.taunt > 0:
		_draw_tether(ci, c)
	if c.atk_buff > 0 and c.atk_mult > 1.0:
		_draw_glints(ci, c, lift)
	elif c.atk_buff > 0 and c.atk_mult < 1.0:
		_draw_stolen_coins(ci, c, lift)
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
		_draw_leaf_roots(ci, c, true)  # the near ones over the feet (the far ones: the floor pass)
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

## Frozen: an ice block round the sprite (a faceted outline, a pale fill, glints that twinkle);
## petrified: just the cracks. Both crack up more and more as the last 40 ticks run out.
func _draw_statue(ci: CanvasItem, c: CreatureSim, lift: float) -> void:
	var top := _top(c)
	var hw := c.radius + 4.0
	var base := c.pos + Vector2(0, 2.0 - lift)
	var ice := c.stone_ice
	if ice:
		var pts := PackedVector2Array([
			Vector2(-hw, 0), Vector2(-hw - 1, -top * 0.3), Vector2(-hw + 2, -top * 0.85),
			Vector2(-hw * 0.4, -top - 3), Vector2(hw * 0.4, -top - 3), Vector2(hw - 2, -top * 0.85),
			Vector2(hw + 1, -top * 0.3), Vector2(hw, 0)])
		for i in pts.size():
			pts[i] = (base + pts[i]).round()
		ci.draw_colored_polygon(pts, Color(C_ICE[1], 0.3))
		var ring := pts.duplicate()
		ring.append(pts[0])
		ci.draw_polyline(ring, Color(C_ICE[2], 0.9), 1.0)
		ci.draw_polyline(PackedVector2Array([ring[1] + Vector2(2, 0), ring[3] + Vector2(0, 2)]), Color(C_ICE[1], 0.5), 1.0)
		ci.draw_polyline(PackedVector2Array([ring[6] - Vector2(2, 0), ring[4] + Vector2(0, 2)]), Color(C_ICE[0], 0.5), 1.0)
		for k in 2:
			var ph := (_tick + c.id * 11 + k * 17) % 40
			if ph < 6:
				var gp := (base + Vector2(float((c.id * 5 + k * 7 + _tick / 40 * 3) % 9 - 4) * hw * 0.2,
					-top * (0.25 + 0.5 * k))).round()
				var ga := 1.0 - absf(ph - 3.0) / 3.0
				ci.draw_rect(Rect2(gp - Vector2(2, 0), Vector2(5, 1)), Color(1, 1, 1, ga))
				ci.draw_rect(Rect2(gp - Vector2(0, 2), Vector2(1, 5)), Color(1, 1, 1, ga))
	if c.stone < 40:
		var n := 1 + (40 - c.stone) / 10
		var col := Color(C_ICE[2], 0.95) if ice else C_CRACK
		for i in n:
			var x0 := (float((i * 5 + c.id * 3) % 9) - 4.0) * hw * 0.2
			var y0 := -top * (0.15 + 0.2 * float(i % 4))
			var p0 := (base + Vector2(x0, y0)).round()
			ci.draw_polyline(PackedVector2Array([p0, p0 + Vector2(2, -3), p0 + Vector2(-1, -5), p0 + Vector2(2, -8)]), col, 1.0)


## Stunned (crumpled): little birds circling over the head, wide and slow.
func _draw_birdies(ci: CanvasItem, c: CreatureSim, lift: float) -> void:
	for i in 3:
		var a := _tick * 0.1 + TAU * i / 3.0
		var at := (c.pos + Vector2(cos(a) * 10.0, -_top(c) * 0.85 - lift + sin(a) * 3.0)).round()
		var dirx := -1.0 if sin(a) > 0.0 else 1.0  # moving left along the near side
		var flap := (_tick / 4 + i) % 2
		ci.draw_rect(Rect2(at + Vector2(-2, -1), Vector2(5, 3)), C_OUTLINE)
		ci.draw_rect(Rect2(at + Vector2(-1, 0), Vector2(3, 1)), C_BIRD)
		ci.draw_rect(Rect2(at + Vector2(0, -1 if flap == 0 else 1), Vector2(1, 1)), C_BIRD)
		ci.draw_rect(Rect2(at + Vector2(dirx * 2.0, 0), Vector2.ONE), C_BIRD_BEAK)


## Taunted: a dotted red tether from its feet to the one it is being dragged toward.
func _draw_tether(ci: CanvasItem, c: CreatureSim) -> void:
	var t := c.taunter(sim)
	if t == null or not shown(t):
		return
	var d := t.pos - c.pos
	var dist := d.length()
	if dist < 20.0:
		return
	var u := d / dist
	var a := 0.55 if (c.taunt > 30 or (_tick / 4) % 2 == 0) else 0.25
	var k := 0
	var s := c.radius + 6.0 + float(_tick % 8)  # marching toward the taunter
	while s < dist - t.radius - 4.0 and k < 40:
		ci.draw_rect(Rect2((c.pos + u * s).round(), Vector2.ONE), Color(C_TAUNT, a))
		s += 8.0
		k += 1


## Slowed: icy motes shed behind it (opposite its walk; drifting up when it stands still).
func _draw_slow_motes(ci: CanvasItem, c: CreatureSim) -> void:
	var back := -c.walk_vel.normalized() if c.walk_vel.length() > 0.1 else Vector2(0, -0.4)
	for i in 3:
		var ph := float((_tick + i * 9 + c.id * 5) % 27) / 27.0
		var jitter := float((i * 7 + c.id * 3) % 5 - 2)
		var at := (c.pos + back * (3.0 + ph * 12.0) + Vector2(jitter, -1.0 - ph * 3.0)).round()
		ci.draw_rect(Rect2(at, Vector2(2, 2) if ph < 0.6 else Vector2.ONE), Color(C_SLOW_MOTE, 0.9 * (1.0 - ph)))


## Pickpocket, the thief: gold glints twinkling over the stolen might.
func _draw_glints(ci: CanvasItem, c: CreatureSim, lift: float) -> void:
	var ph := (_tick + c.id * 9) % 24
	if ph >= 7:
		return
	var a := 1.0 - absf(ph - 3.0) / 3.5
	var at := (c.pos + Vector2(float((_tick / 24 * 5 + c.id) % 11 - 5) * 1.5,
		-_top(c) * (0.35 + 0.12 * float((_tick / 24) % 5)) - lift)).round()
	ci.draw_rect(Rect2(at - Vector2(2, 0), Vector2(5, 1)), Color(C_COIN[2], a))
	ci.draw_rect(Rect2(at - Vector2(0, 2), Vector2(1, 5)), Color(C_COIN[2], a))
	ci.draw_rect(Rect2(at, Vector2.ONE), Color(1, 1, 1, a))


## Pickpocket, the victim: coins drift off it toward the thief while its power is stolen.
func _draw_stolen_coins(ci: CanvasItem, c: CreatureSim, lift: float) -> void:
	var thief: CreatureSim = null
	var best := 1.0e9
	for o in sim.creatures:
		if o.team != c.team and o.atk_buff > 0 and o.atk_mult > 1.0 and o.state != CreatureSim.State.KO:
			var dd := o.pos.distance_squared_to(c.pos)
			if dd < best:
				best = dd
				thief = o
	if thief == null:
		return
	var from := c.pos + Vector2(0, -_chest(c) - lift)
	var to := thief.pos + Vector2(0, -_chest(thief) - thief.air_height())
	for i in 2:
		var ph := float((_tick + i * 15 + c.id * 4) % 30) / 30.0
		var at := from.lerp(to, ph) + Vector2(0, -sin(ph * PI) * 6.0)
		var ar := at.round()
		ci.draw_rect(Rect2(ar - Vector2(2, 2), Vector2(4, 4)), C_OUTLINE)
		ci.draw_rect(Rect2(ar - Vector2(1, 1), Vector2(2, 2)), C_COIN[1] if (_tick / 3 + i) % 2 == 0 else C_COIN[2])


func _bang(ci: CanvasItem, at: Vector2) -> void:
	ci.draw_rect(Rect2(at + Vector2(-2, -9), Vector2(5, 8)), C_OUTLINE)
	ci.draw_rect(Rect2(at + Vector2(-2, 0), Vector2(5, 4)), C_OUTLINE)
	ci.draw_rect(Rect2(at + Vector2(-1, -8), Vector2(3, 6)), C_TAUNT)
	ci.draw_rect(Rect2(at + Vector2(-1, 1), Vector2(3, 2)), C_TAUNT)


func _draw_rain(ci: CanvasItem) -> void:
	# the same streaks and splashes as the Rain weather (WeatherView), over the view
	var amount := minf(1.0, _rain / 30.0)
	var n := int(110 * amount)
	var view := _view_rect(ci, 0.0)
	if view.size.x > 1e8:
		view = Rect2(Vector2.ZERO, Vector2(480, 270))  # headless: no screen
	WeatherView.rain_streaks(ci, view, n, _tick)
	var fr := sim.floor_rect() if sim != null else SimDefs.floor_rect()
	WeatherView.rain_splashes(ci, fr, n / 3, _tick)


# ------------------------------------------------------------------ arena hazards
# (Hazards in src/sim/hazards.gd: a mutator's tidal wave and meteor shower.) Read from the
# sim's hazard state every frame; the events add the one-off bursts.

const C_SWELL := Color("2f6fa8")
const C_SAFE := Color("9cf0c0")
const C_METEOR: Array[Color] = [Color("3a2420"), Color("8a4a2a"), Color("ff7a2a"), Color("ffd27a")]
## The way a meteor falls on screen (from the upper right), and how long its streak shows.
const METEOR_FALL := Vector2(-0.42, 1.0)
const METEOR_STREAK_TICKS := 22
var _walls_at := PackedVector2Array()  ## centres of every rubble cell (for the shelter lanes)
var _walls_ver := -1


## Floor layer: the swell on the wave's edge and the calm lane behind each rubble block
## while it warns, the water behind the front while it runs, meteor shadows (true circles
## growing as they fall, ringed at their full reach), and the cores' glow.
func _draw_hazards_floor(ci: CanvasItem) -> void:
	var fr := sim.floor_rect()
	var w := Hazards.wave_now(sim)
	if not w.is_empty():
		var side := int(w["side"])
		var d: Dictionary = w["def"]
		if int(w["phase"]) == Hazards.WARN:
			var total := float(maxi(1, Hazards.ticks_of(d.get("warn_seconds", 3))))
			var k := clampf(1.0 - float(w["left"]) / total, 0.0, 1.0)
			var depth := roundf(8.0 + 30.0 * k + 2.0 * sin(float(_tick) * 0.25))
			_shelter_lanes(ci, w["dir"], d, k)
			_wave_band(ci, fr, side, 0.0, depth, Color(C_SWELL, 0.3 + 0.3 * k))
			_wave_band(ci, fr, side, maxf(0.0, depth - 6.0), depth, Color(C_WATER, 0.45 + 0.3 * k))
			_wave_foam(ci, fr, side, depth, 0.55 + 0.4 * k)
			_wave_arrows(ci, fr, side, depth + 10.0, k)
		else:
			var front := float(w["front"])
			_wave_band(ci, fr, side, 0.0, front, Color(C_SWELL, 0.4))
			_wave_band(ci, fr, side, maxf(0.0, front - 22.0), front, Color(C_WATER, 0.5))
	_draw_puddles(ci)
	for m in Hazards.meteors_now(sim):
		var left := int(m["land"]) - sim.tick
		var warn := int(m["warn"])
		if left > warn:
			continue
		var k := 1.0 - float(left) / float(maxi(1, warn))
		var at: Vector2 = m["pos"]
		var r := float(m["radius"])
		var big := bool(m["big"])
		ci.draw_circle(at, r * (0.2 + 0.8 * k), Color(0, 0, 0, 0.12 + 0.3 * k))
		var blink := 1.0 if left > 20 else (1.0 if (_tick / 3) % 2 == 0 else 0.45)
		var col: Color = C_WARN if big else C_METEOR[2]
		ci.draw_arc(at, r, 0.0, TAU, 48, Color(col, (0.35 + 0.55 * k) * blink), 2.0 if big else 1.0)
		if big:
			ci.draw_arc(at, r - 4.0, 0.0, TAU, 40, Color(col, 0.3 * k * blink), 1.0)
	for pk in sim.hazard_pickups:
		var at: Vector2 = pk["pos"]
		var g := 0.5 + 0.5 * sin(float(_tick) * 0.15)
		var fading := int(pk["until"]) - sim.tick < 120 and (_tick / 6) % 2 == 1
		var a := 0.5 if fading else 1.0
		ci.draw_circle(at, float(pk["radius"]) + 4.0 + 2.0 * g, Color(C_METEOR[2], (0.14 + 0.1 * g) * a))
		ci.draw_arc(at, float(pk["radius"]), 0.0, TAU, 28, Color(C_METEOR[3], 0.75 * a), 1.0)
	for b in Hazards.boulders_now(sim):
		_boulder_lane(ci, fr, b)
	for f in Hazards.faults_now(sim):
		_fault_floor(ci, f)


## Over the fighters: the wave's crest at its front, falling meteors (a rock and its fiery
## streak, the last METEOR_STREAK_TICKS before it lands), and each core's ember.
func _draw_hazards_top(ci: CanvasItem) -> void:
	var fr := sim.floor_rect()
	var w := Hazards.wave_now(sim)
	if not w.is_empty() and int(w["phase"]) == Hazards.ACTIVE:
		_wave_crest(ci, fr, int(w["side"]), float(w["front"]))
	for m in Hazards.meteors_now(sim):
		var left := int(m["land"]) - sim.tick
		if left > METEOR_STREAK_TICKS:
			continue
		var at: Vector2 = m["pos"]
		var fall := METEOR_FALL.normalized()
		var rock := (at - fall * float(left) * 9.0).round()
		var big := bool(m["big"])
		var rr := 5.0 if big else 3.0
		ci.draw_line(rock, rock - fall * (rr * 7.0), Color(C_METEOR[2], 0.45), rr * 1.6)
		ci.draw_line(rock, rock - fall * (rr * 4.0), Color(C_METEOR[3], 0.8), rr * 0.9)
		ci.draw_circle(rock, rr + 1.0, C_METEOR[0])
		ci.draw_circle(rock, rr, C_METEOR[1])
		ci.draw_circle(rock + Vector2(-1, -1), rr * 0.45, C_METEOR[3])
	for pk in sim.hazard_pickups:
		var at: Vector2 = pk["pos"]
		var bob := roundf(sin(float(_tick) * 0.1) * 1.5)
		var o := at + Vector2(0, -5 + bob)
		ci.draw_circle(o, 4.0, C_METEOR[0])
		ci.draw_circle(o, 3.0, C_METEOR[2])
		ci.draw_circle(o + Vector2(-1, -1), 1.5, C_METEOR[3])
		if (_tick / 4) % 5 == 0:
			ci.draw_rect(Rect2((o + Vector2(3, -4)).round(), Vector2.ONE), C_FOAM)
	for b in Hazards.boulders_now(sim):
		if int(b["phase"]) == Hazards.ACTIVE:
			_boulder_ball(ci, b)


# The rolling boulder and the fault line (shapes "boulder", "fault").
const C_BOULDER: Array[Color] = [Color("2e2620"), Color("5a4a3c"), Color("85715c"), Color("b39c80")]
const C_SENT := Color("ffd27a")  ## a boulder someone sent back: its rim
const C_FAULT := Color("1a1210")
const C_FAULT_GLOW := Color("ff8a3a")
const BOULDER_PATH := 220.0  ## how far ahead a turned boulder's way is drawn (px)
var _fault_last := {"axis": 0, "cells": PackedInt32Array()}  ## the open fault seen last tick (its closing dust)


## A boulder's lane on the floor: while it warns, a band its width across the whole floor
## (flashing faster as it nears), its edges dashed and chevrons marching the way it will
## roll; while it rolls, the band ahead of it, fainter, and its shadow (a true circle).
func _boulder_lane(ci: CanvasItem, fr: Rect2, b: Dictionary) -> void:
	var r := float(b["radius"])
	var side := int(b["side"])
	var dir: Vector2 = b["dir"]
	var lane := float(b["lane"])
	var band: Rect2 = Rect2(fr.position.x, fr.position.y + lane - r, fr.size.x, r * 2.0) if side < 2 \
		else Rect2(fr.position.x + lane - r, fr.position.y, r * 2.0, fr.size.y)
	var warn := int(b["phase"]) == Hazards.WARN
	var col := C_WARN if int(b["by"]) < 0 else C_SENT
	if warn:
		var total := float(maxi(1, Hazards.ticks_of((b["def"] as Dictionary).get("warn_seconds", 1.5))))
		var k := clampf(1.0 - float(b["left"]) / total, 0.0, 1.0)
		var period := 10 if k < 0.6 else 5
		var lit := (_tick / period) % 2 == 0
		ci.draw_rect(band, Color(col, (0.1 + 0.14 * k) * (1.0 if lit else 0.6)))
		_lane_edges(ci, band, side, Color(col, 0.5 + 0.4 * k))
		_lane_chevrons(ci, band, dir, Color(col, 0.45 + 0.4 * k), 0.0)
	else:
		var at: Vector2 = b["pos"]
		if int(b["turned"]) < 0:
			# Still on its first lane: only the part ahead of it.
			var ahead := band
			if dir.x > 0.0:
				ahead = Rect2(Vector2(at.x, band.position.y), Vector2(maxf(0.0, band.end.x - at.x), band.size.y))
			elif dir.x < 0.0:
				ahead = Rect2(band.position, Vector2(maxf(0.0, at.x - band.position.x), band.size.y))
			elif dir.y > 0.0:
				ahead = Rect2(Vector2(band.position.x, at.y), Vector2(band.size.x, maxf(0.0, band.end.y - at.y)))
			else:
				ahead = Rect2(band.position, Vector2(band.size.x, maxf(0.0, at.y - band.position.y)))
			ci.draw_rect(ahead, Color(col, 0.08))
			_lane_edges(ci, ahead, side, Color(col, 0.3))
		else:
			_boulder_path(ci, fr, b, col)
		ci.draw_circle(at, r, Color(0, 0, 0, 0.28))
		ci.draw_circle(at, r * 0.7, Color(0, 0, 0, 0.12))


## A boulder that has turned (a ricochet, a wall, a send-back): its way ahead as two dashed
## edges a boulder wide, fading out over BOULDER_PATH px; for `preview_ticks` after the
## turn, bold and blinking with an arrow off the ball, so the new way reads at once.
func _boulder_path(ci: CanvasItem, fr: Rect2, b: Dictionary, col: Color) -> void:
	var r := float(b["radius"])
	var at: Vector2 = b["pos"]
	var dir: Vector2 = b["dir"]
	var across := Vector2(-dir.y, dir.x)
	var since := sim.tick - int(b["turned"])
	var fresh := since < int((b["def"] as Dictionary).get("preview_ticks", 30))
	var a := (0.75 if (_tick / 4) % 2 == 0 else 0.45) if fresh else 0.25
	# Dashed edges, marching along, fading out over BOULDER_PATH px ahead.
	var s := r * 0.5 + float(_tick % 12)
	while s < BOULDER_PATH:
		var p := at + dir * s
		if not fr.grow(r).has_point(p):
			break
		var fade := 1.0 - s / BOULDER_PATH
		for e in [-1.0, 1.0]:
			var q: Vector2 = p + across * r * float(e)
			ci.draw_line(q.round(), (q + dir * 6.0).round(), Color(col, a * fade), 2.0)
		s += 12.0
	if fresh:
		var tip := at + dir * (r + 30.0)
		var base := at + dir * (r + 6.0)
		ci.draw_line(base.round(), tip.round(), Color(col, 0.9), 3.0)
		ci.draw_polyline(PackedVector2Array([(tip - dir * 9.0 + across * 7.0).round(), tip.round(),
			(tip - dir * 9.0 - across * 7.0).round()]), Color(col, 0.95), 3.0)


## A lane's two long edges, dashed, the dashes marching.
func _lane_edges(ci: CanvasItem, band: Rect2, side: int, col: Color) -> void:
	var off := float(_tick % 8)
	if side < 2:
		var x := band.position.x - 8.0 + off
		while x < band.end.x:
			var x0 := maxf(x, band.position.x)
			var x1 := minf(x + 4.0, band.end.x)
			if x1 > x0:
				ci.draw_rect(Rect2(x0, band.position.y, x1 - x0, 1.0), col)
				ci.draw_rect(Rect2(x0, band.end.y - 1.0, x1 - x0, 1.0), col)
			x += 8.0
	else:
		var y := band.position.y - 8.0 + off
		while y < band.end.y:
			var y0 := maxf(y, band.position.y)
			var y1 := minf(y + 4.0, band.end.y)
			if y1 > y0:
				ci.draw_rect(Rect2(band.position.x, y0, 1.0, y1 - y0), col)
				ci.draw_rect(Rect2(band.end.x - 1.0, y0, 1.0, y1 - y0), col)
			y += 8.0


## Chevrons down the middle of a lane, pointing (and marching) along `dir`.
func _lane_chevrons(ci: CanvasItem, band: Rect2, dir: Vector2, col: Color, _phase: float) -> void:
	var across := Vector2(-dir.y, dir.x)
	var mid := band.get_center()
	var span := band.size.x if dir.y == 0.0 else band.size.y
	var step := 40.0
	var start := -span * 0.5 + float((_tick * 2) % int(step))
	var u := start
	while u < span * 0.5:
		var p := (mid + dir * u).round()
		var w := minf(band.size.x, band.size.y) * 0.3
		ci.draw_polyline(PackedVector2Array([p - dir * 4.0 + across * w, p + dir * 3.0, p - dir * 4.0 - across * w]), col, 2.0)
		u += step


## The boulder itself, a ball standing on its shadow: a dark rim, a lit cap, and marks on
## its face that roll the way it goes (the turn is worked out from where it is: looks only).
func _boulder_ball(ci: CanvasItem, b: Dictionary) -> void:
	var r := float(b["radius"])
	var at: Vector2 = b["pos"]
	var dir: Vector2 = b["dir"]
	var c := (at + Vector2(0, -r * 0.85)).round()
	ci.draw_circle(c, r + 1.0, C_BOULDER[0])
	ci.draw_circle(c, r, C_BOULDER[1])
	ci.draw_circle(c + Vector2(-r * 0.15, -r * 0.2), r * 0.78, C_BOULDER[2])
	ci.draw_circle(c + Vector2(-r * 0.35, -r * 0.42), r * 0.3, C_BOULDER[3])
	var roll := (at.x + at.y) / r  # the turn, from how far it has come
	var face := dir if dir.y == 0.0 else Vector2(0, dir.y * 0.6)
	for i in 3:
		var ph := roll + TAU * float(i) / 3.0
		var s := sin(ph)
		if cos(ph) < 0.0:
			continue  # round the back
		var p := c + face * s * r * 0.7 + Vector2(-face.y, face.x) * (float(i) - 1.0) * r * 0.35
		ci.draw_rect(Rect2(p.round() - Vector2(2, 1), Vector2(4, 2)), C_BOULDER[0])
		ci.draw_rect(Rect2(p.round() - Vector2(1, 2), Vector2(2, 1)), Color(C_BOULDER[0], 0.7))
	if int(b["by"]) >= 0:
		ci.draw_arc(c, r + 2.0, 0.0, TAU, 32, Color(C_SENT, 0.85 if (_tick / 3) % 2 == 0 else 0.5), 2.0)


## A fault line: while it warns, a crack that runs out along the strip from its middle
## (dark, with a hot glow in it that flickers faster near the end) over a faint band of its
## cells; open, the chasm is the floor's own pit look (ArenaView), and in its last second
## the edges glow as it grinds shut.
func _fault_floor(ci: CanvasItem, f: Dictionary) -> void:
	var t := sim.terrain
	var warn := int(f["phase"]) == Hazards.WARN
	var cells: PackedInt32Array = f["cells"] if warn else f["open"]
	if cells.is_empty():
		return
	var axis := int(f["axis"])
	if warn:
		var k := clampf(1.0 - float(f["left"]) / float(maxi(1, int(f["warn"]))), 0.0, 1.0)
		var blink := 1.0 if k < 0.75 or (_tick / 3) % 2 == 0 else 0.5
		for i in cells:
			ci.draw_rect(t.cell_rect(Vector2i(i % t.cols, i / t.cols)), Color(C_WARN, (0.06 + 0.16 * k) * blink))
		var line := _fault_line(f)
		var n := line.size()
		var half := int(ceil(float(n) * 0.5 * minf(1.0, k * 1.6)))
		var mid := n / 2
		var lo := maxi(0, mid - half)
		var hi := mini(n - 1, mid + half)
		if hi > lo:
			var seg := line.slice(lo, hi + 1)
			ci.draw_polyline(seg, C_FAULT, 3.0)
			ci.draw_polyline(seg, Color(C_FAULT_GLOW, (0.3 + 0.6 * k) * blink), 1.0)
			# Hairline branches off it every few cells.
			for j in range(lo, hi, 5):
				var p := seg[j - lo]
				var out := Vector2(3, 2) if axis == 0 else Vector2(2, 3)
				if (j / 5) % 2 == 1:
					out = -out
				ci.draw_line(p, p + out * (1.0 + k), C_FAULT, 1.0)
	else:
		var left := int(f["heal"]) - sim.tick
		if left > 60:
			return
		var k := 1.0 - float(left) / 60.0
		var g := 0.3 + 0.45 * k
		for i in cells:
			var rc := t.cell_rect(Vector2i(i % t.cols, i / t.cols))
			ci.draw_rect(rc, Color(C_FAULT_GLOW, g * (1.0 if (_tick / 4 + i) % 3 == 0 else 0.7)))
			ci.draw_rect(rc.grow(-2.0 - 2.0 * k), Color(C_FAULT, 0.5))  # the gap narrowing


## The middle of a fault's strip, one point a cell down its length (ragged by a pixel).
func _fault_line(f: Dictionary) -> PackedVector2Array:
	var t := sim.terrain
	var axis := int(f["axis"])
	var sums := {}
	for i in (f["cells"] as PackedInt32Array):
		var c := Vector2i(i % t.cols, i / t.cols)
		var k := c.y if axis == 0 else c.x
		var at := t.cell_center(c)
		var acc: Vector3 = sums.get(k, Vector3.ZERO)
		sums[k] = acc + Vector3(at.x, at.y, 1.0)
	var keys := sums.keys()
	keys.sort()
	var out := PackedVector2Array()
	for k in keys:
		var acc: Vector3 = sums[k]
		var p := Vector2(acc.x, acc.y) / acc.z
		var jag := float(posmod(int(k) * 7, 3) - 1)
		out.append((p + (Vector2(jag, 0) if axis == 0 else Vector2(0, jag))).round())
	return out


## A band of the floor between `s0` and `s1` px downstream of the wave's edge.
func _wave_band(ci: CanvasItem, fr: Rect2, side: int, s0: float, s1: float, col: Color) -> void:
	if s1 <= s0:
		return
	var r: Rect2
	match side:
		0: r = Rect2(fr.position.x + s0, fr.position.y, s1 - s0, fr.size.y)
		1: r = Rect2(fr.end.x - s1, fr.position.y, s1 - s0, fr.size.y)
		2: r = Rect2(fr.position.x, fr.position.y + s0, fr.size.x, s1 - s0)
		_: r = Rect2(fr.position.x, fr.end.y - s1, fr.size.x, s1 - s0)
	ci.draw_rect(r, col)


## A point `s` px downstream of the wave's edge, `u` px along it.
static func _wave_at(fr: Rect2, side: int, s: float, u: float) -> Vector2:
	match side:
		0: return Vector2(fr.position.x + s, fr.position.y + u)
		1: return Vector2(fr.end.x - s, fr.position.y + u)
		2: return Vector2(fr.position.x + u, fr.position.y + s)
	return Vector2(fr.position.x + u, fr.end.y - s)


## A ragged line of foam along the swell's lip.
func _wave_foam(ci: CanvasItem, fr: Rect2, side: int, s: float, a: float) -> void:
	var span := fr.size.y if side < 2 else fr.size.x
	var u := 0.0
	while u < span:
		var jag := float(posmod(int(u) * 7 + _tick / 4, 5)) - 2.0
		var p := _wave_at(fr, side, s + jag, u).round()
		ci.draw_rect(Rect2(p, Vector2(2, 2) if side < 2 else Vector2(3, 2)), Color(C_FOAM, a))
		u += 3.0


## Chevrons on the floor pointing the way the wave will go, flashing.
func _wave_arrows(ci: CanvasItem, fr: Rect2, side: int, s: float, k: float) -> void:
	if (_tick / 8) % 2 == 1:
		return
	var span := fr.size.y if side < 2 else fr.size.x
	var dir := Hazards.wave_dir(side)
	var across := Vector2(-dir.y, dir.x)
	var n := maxi(2, int(span / 72.0))
	for i in n:
		var u := span * (float(i) + 0.5) / float(n)
		var p := _wave_at(fr, side, s, u).round()
		var col := Color(C_WATER_L, 0.5 + 0.4 * k)
		ci.draw_polyline(PackedVector2Array([p - dir * 4.0 + across * 5.0, p + dir * 2.0, p - dir * 4.0 - across * 5.0]), col, 2.0)


## While a wave warns: the calm water behind every rubble block (where it can't reach),
## so where to stand reads at a glance.
func _shelter_lanes(ci: CanvasItem, dir: Vector2, d: Dictionary, k: float) -> void:
	if _walls_ver != sim.terrain.version:
		_walls_ver = sim.terrain.version
		_walls_at = PackedVector2Array()
		var t := sim.terrain
		for i in t.cells.size():
			if t.cells[i] == TerrainGrid.WALL:
				_walls_at.append(t.cell_center(Vector2i(i % t.cols, i / t.cols)))
	var depth := float((d.get("shelter", {}) as Dictionary).get("depth", 48))
	var half := SimDefs.CELL * 0.5
	var col := Color(C_SAFE, 0.1 + 0.12 * k)
	var wide := half if dir.x == 0.0 else 0.0
	var tall := half if dir.y == 0.0 else 0.0
	for at in _walls_at:
		var r := Rect2(at + dir * half, Vector2.ZERO).expand(at + dir * (half + depth - 8.0))
		ci.draw_rect(r.grow_individual(wide, tall, wide, tall), col)


## The wave's front: a rolling wall of water with a white crest, a few px tall.
func _wave_crest(ci: CanvasItem, fr: Rect2, side: int, front: float) -> void:
	var span := fr.size.y if side < 2 else fr.size.x
	var u := 0.0
	while u < span:
		var p := _wave_at(fr, side, front, u)
		var h := 10.0 + float(posmod(int(u) * 5 + _tick, 7))
		if side < 2:  # across the screen: the wall stands up from the floor along the front
			var back := -Hazards.wave_dir(side).x
			ci.draw_rect(Rect2(p.x + minf(0.0, back * 12.0), p.y - h * 0.5, 12.0, h * 0.5 + 1.0), Color(C_WATER, 0.6))
			ci.draw_rect(Rect2(p.x - 3.0, p.y - h, 6.0, h), Color(C_WATER, 0.85))
			ci.draw_rect(Rect2(p.x - 3.0, p.y - h, 6.0, 2.0), C_FOAM)
			ci.draw_rect(Rect2(p.x - 3.0 - back * 3.0, p.y - h * 0.5, 2.0, 2.0), Color(C_FOAM, 0.8))
		else:
			ci.draw_rect(Rect2(p.x, p.y - h, 4.0, h), Color(C_WATER, 0.75))
			ci.draw_rect(Rect2(p.x, p.y - h, 4.0, 2.0), C_FOAM)
		u += 4.0


## The wave's puddles (the cells it turned to shallows): a wash of water over them, in
## runs along each row, fading out over their last second. WaterView adds the ripples.
func _draw_puddles(ci: CanvasItem) -> void:
	var t := sim.terrain
	for st in sim.hazards:
		var cells: PackedInt32Array = st.get("puddles", PackedInt32Array())
		if cells.is_empty():
			continue
		var left := int(st["dry"]) - sim.tick
		var col := Color(C_WATER, 0.34 * clampf(float(left) / 60.0, 0.0, 1.0))
		var run_start := -1
		var prev := -2
		for k in cells.size() + 1:
			var i := cells[k] if k < cells.size() else -10
			var live := k < cells.size() and t.cells[i] == TerrainGrid.SHALLOWS
			if live and i == prev + 1 and i % t.cols != 0:
				prev = i
				continue
			if run_start >= 0:
				var a := t.cell_rect(Vector2i(run_start % t.cols, run_start / t.cols))
				ci.draw_rect(Rect2(a.position, Vector2(float(prev - run_start + 1) * SimDefs.CELL, SimDefs.CELL)), col)
			run_start = i if live else -1
			prev = i if live else -2


## Spray off the running wave's front, a few drops a tick.
func _hazard_spray() -> void:
	for f in Hazards.faults_now(sim):
		if int(f["phase"]) == Hazards.ACTIVE:
			_fault_last = {"axis": f["axis"], "cells": f["open"]}
	# Dust kicked up behind a rolling boulder; grit rumbling at a lane's edge while it warns.
	for b in Hazards.boulders_now(sim):
		var r := float(b["radius"])
		var dir: Vector2 = b["dir"]
		var at: Vector2 = b["pos"]
		if int(b["phase"]) == Hazards.ACTIVE:
			if _tick % 2 == 0:
				var back := at - dir * r * 0.8 + Vector2(-dir.y, dir.x) * randf_range(-r, r) * 0.7
				_dust(back, -dir * randf_range(0.2, 0.6) + Vector2(0, -0.25))
			if _tick % 5 == 0:
				_px(at - dir * r + Vector2(randf_range(-4, 4), -2), -dir * 0.6 + Vector2(0, -0.8), C_DIRT[randi() % 3], 18)
		elif _tick % 4 == 0:
			var edge: Vector2 = b["start"] + dir * r
			_px(edge + Vector2(-dir.y, dir.x) * randf_range(-r, r) + Vector2(0, -randf_range(0, 6)),
				Vector2(randf_range(-0.3, 0.3), -0.6), C_DIRT[randi() % 3], 16)
	var w := Hazards.wave_now(sim)
	if w.is_empty() or int(w["phase"]) != Hazards.ACTIVE:
		return
	var fr := sim.floor_rect()
	var side := int(w["side"])
	var span := fr.size.y if side < 2 else fr.size.x
	var dir: Vector2 = w["dir"]
	for i in 4:
		var p := _wave_at(fr, side, float(w["front"]), randf() * span)
		_drop(p, randf_range(6.0, 14.0), dir * randf_range(0.8, 2.0) + Vector2(randf_range(-0.4, 0.4), 0),
			randf_range(0.5, 1.8), false)


func _hazard_event(e: Dictionary, p: Vector2) -> void:
	match String(e["type"]):
		"hazard_strike":
			if String(e.get("shape", "")) == "meteors":
				var r := float(e.get("radius", 28))
				_add({"kind": "ring", "pos": p, "life": 14, "radius": r, "color": C_METEOR[2]})
				_dirt_burst(p, r * 0.6)
				for i in 10:
					var v := Vector2.from_angle(randf() * TAU) * randf_range(0.8, 2.4)
					_px(p + Vector2(0, -2), v + Vector2(0, -1.2), C_SPARK[randi() % 3], randf_range(14.0, 26.0))
				if bool(e.get("big", false)):
					_cave_in(p, 12.0)
				shake_out = maxf(shake_out, 4.0 if bool(e.get("big", false)) else 2.0)
				if bool(e.get("core", false)):
					_add({"kind": "ring", "pos": p, "life": 24, "radius": 12.0, "color": C_METEOR[3]})
			elif String(e.get("shape", "")) == "boulder":
				_smoke(p, 5)
				shake_out = maxf(shake_out, 2.0)
			elif String(e.get("shape", "")) == "fault":
				for f in Hazards.faults_now(sim):
					var line := _fault_line({"axis": f["axis"], "cells": f["open"]})
					for j in range(0, line.size(), 3):
						_dust(line[j], Vector2(randf_range(-0.6, 0.6), -0.4))
						_chunk(line[j], randf_range(4, 10), Vector2(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3)),
							randf_range(1.0, 2.0), randf_range(1.5, 2.5), C_DIRT[randi() % 3], 40.0)
				shake_out = maxf(shake_out, 5.0)
			else:
				shake_out = maxf(shake_out, 3.0)
		"hazard_ricochet":
			# Stone on stone (or on a wall): a white-hot spark burst and chips at the point of contact.
			var at := p + Vector2(0, -float(e.get("power", 18.0)) * 0.85)
			_add({"kind": "ring", "pos": at, "life": 10, "radius": 14.0, "color": C_SPARK[0]})
			for i in 12:
				_px(at, Vector2.from_angle(randf() * TAU) * randf_range(1.2, 3.0), C_SPARK[randi() % 3], randf_range(12.0, 20.0))
			for i in 4:
				_chunk(at, randf_range(4, 10), Vector2.from_angle(randf() * TAU) * randf_range(0.6, 1.4),
					randf_range(1.0, 2.0), 2.0, C_BOULDER[1 + randi() % 3], 40.0)
			if int(e.get("other", -1)) >= 0:
				_text(at + Vector2(0, -16), "CLACK!", C_SPARK[0], 8, 30.0)
			shake_out = maxf(shake_out, 2.5)
		"hazard_reverse":
			_add({"kind": "ring", "pos": p + Vector2(0, -12), "life": 16, "radius": 26.0, "color": C_SENT})
			for i in 10:
				_px(p + Vector2(0, -12), Vector2.from_angle(randf() * TAU) * randf_range(1.0, 2.4), C_SPARK[randi() % 3], 20)
			_text(p + Vector2(0, -40), "SENT BACK!", C_SENT, 9, 50.0)
			shake_out = maxf(shake_out, 4.0)
		"hazard_end":
			match String(e.get("shape", "")):
				"boulder":
					var r := float(e.get("power", 18.0))
					if String(e.get("how", "")) == "pit":
						_cave_in(p, r * 0.6)
					elif String(e.get("how", "")) == "wall":
						for i in 12:
							_chunk(p + Vector2(0, -r), randf_range(6, 16), Vector2.from_angle(randf() * TAU) * randf_range(0.6, 1.8),
								randf_range(1.5, 3.0), randf_range(2.0, 4.0), C_BOULDER[1 + randi() % 3], 60.0)
						_smoke(p, 6)
						shake_out = maxf(shake_out, 3.0)
				"fault":  # it grinds shut: dust all along where it was
					var line := _fault_line(_fault_last)
					for j in range(0, line.size(), 4):
						_dust(line[j], Vector2(randf_range(-0.4, 0.4), -0.3))
					shake_out = maxf(shake_out, 2.0)
		"hazard_hit":
			var c := _creature(int(e.get("who", -1)))
			var at := c.pos if c != null else p
			var dmg := float(e.get("damage", 0.0))
			if String(e.get("shape", "")) == "wave":
				_splash(at, 8.0, false)
				if dmg > 0.0:
					_text(at + Vector2(0, -30), "%d" % roundi(dmg), C_WATER_L, 9)
			elif dmg > 0.0:
				_text(at + Vector2(0, -30), "%d" % roundi(dmg), C_METEOR[3], 9)
		"hazard_shelter":
			var c := _creature(int(e.get("who", -1)))
			if c != null:
				_text(c.pos + Vector2(0, -34), "SHELTERED", C_SAFE, 7, 45.0)
		"hazard_pickup":
			var c := _creature(int(e.get("who", -1)))
			_add({"kind": "ring", "pos": p, "life": 18, "radius": 16.0, "color": C_METEOR[3]})
			for i in 8:
				_px(p, Vector2.from_angle(TAU * i / 8.0) * 1.6 + Vector2(0, -0.8), C_METEOR[2 + i % 2], 22.0)
			if c != null:
				_text(c.pos + Vector2(0, -34), "MIGHT!" if String(e.get("kind", "")) != "haste" else "HASTE!", C_METEOR[3], 9, 60.0)
		"hazard_pickup_gone":
			_smoke(p, 4)
