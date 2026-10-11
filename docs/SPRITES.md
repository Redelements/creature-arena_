# Sprite sheet layouts

Use this as the spec for artists. If a replacement sheet keeps the same frame size and
row layout, it drops in with no code changes. If a layout does change, update the
`"sprite"` block in the creature's JSON file in `data/creatures/`; each move picks its
animation by name with its `"anim"` field.

![Current placeholder sheets](sprite_preview.png)

## Three directions per creature

Fighters face any of 8 ways, so every creature has **three sheets with the same rows**:

| Sheet | Shows | Used when facing |
| --- | --- | --- |
| `name.png` | the side, facing **right** (mirrored for left) | left, right and the four diagonals |
| `name_down.png` | the **front**, walking toward the camera | down the screen |
| `name_up.png` | the **back**, walking away from the camera | up the screen |

In the up and down sheets, "forward" is depth: a punch that reaches 20 px in front of
the feet on the side sheet should land about 20 px below the feet (front view) or above
them (back view), because that's where the hit lands in the game. Arms and heads that
reach away from the camera go behind the body.

Each view can have its own frame size and feet origin (`"views"` in the creature's JSON
`"sprite"` block). Animations listed in `"side_only"` (all three use it for the knockout,
which falls over sideways) always come from the side sheet, so those rows can stay empty
in the other two. Preview: [`sprite_views_preview.png`](sprite_views_preview.png) (Cairn
and Culvert, side/down/up), [`craglash_views_preview.png`](craglash_views_preview.png) and
[`barkley_views_preview.png`](barkley_views_preview.png) and
[`gillbert_views_preview.png`](gillbert_views_preview.png).

## Creatures — 48×48 frames, 6 columns

Creatures face **right**. Feet rest at the **origin** pixel (Culvert: x 21, y 43; Cairn:
x 22, y 43), which sits on the ground where the shadow is drawn. The game mirrors the
sprite to face left and raises it off its shadow when launched. Leave at least 1 px of
transparent margin on every side. Unused cells stay transparent.

Two effects read the art directly, so check them when sheets are replaced:

- **Cairn's knockout** slices idle frame 0 into horizontal bands, one per stone, and
  tumbles them separately. The band rows are `ko_fx.pieces` in `cairn.json` (head first),
  and `ko_fx.x_eyes` marks where the eyes are so they can be drawn as X's. If the final
  art moves the stones or the face, update those numbers.
- **Surge cut-ins** show one frame of the Surge animation enlarged, picked by
  `cut_in_frame` ([row, column]) in each creature's JSON.

How the game plays a move's frames: on 4-frame attacks, frame 0 is the windup, 1 the
strike, 2 the follow-through and 3 the recovery. Heavies use 6 frames: two charge frames
(alternating while held), rise, strike, follow-through and recovery.

### Culvert — 6 × 11 (288×528 px)

| Row | Animation | Frames | Notes |
| --- | --- | --- | --- |
| 0 | idle | 4 | breathing loop |
| 1 | run | 6 | loop |
| 2 | light | 4 | shared by Jab, Jab, Hook |
| 3 | heavy | 6 | Slam: charge A, charge B, leap, slam, impact, recover |
| 4 | dodge | 4 | roll |
| 5 | hurt | 2 | hitstun; frame 1 doubles as the crumple pose |
| 6 | guard | 2 | holding, blocking a hit |
| 7 | ko | 4 | collapse; frames 1–2 double as the knockdown pose |
| 8 | gulp | 4 | Gulp: open wide, lunge, swallowed (cheeks puffed), spit |
| 9 | runoff | 4 | Runoff: raise arm, slap the ground, hold, recover |
| 10 | storm | 6 | Storm Drain: crouch, leap, peak, slam, impact, recover |

### Cairn — 6 × 12 (288×576 px)

| Row | Animation | Frames | Notes |
| --- | --- | --- | --- |
| 0 | idle | 4 | bouncing guard stance |
| 1 | run | 6 | loop |
| 2 | jab | 4 | lead hand: Jab, Jab |
| 3 | power | 4 | rear hand: Cross, Hook |
| 4 | heavy | 6 | Haymaker: charge A, charge B, dip, uppercut, follow-through, recover |
| 5 | dodge | 4 | weave: the stones slide sideways |
| 6 | hurt | 2 | hitstun; frame 1 doubles as the crumple pose |
| 7 | guard | 2 | fists up, blocking a hit |
| 8 | ko | 4 | stack topples and scatters; frames 1–2 double as the knockdown pose |
| 9 | slip | 4 | Slip: weave low, deeper, counter cross, recover |
| 10 | rush | 4 | Rockslide Rush: lean in, dash, punch, recover |
| 11 | surge | 6 | Avalanche: flurry A, B, C (cycled), wind up, uppercut, recover |

Design note for Cairn: keep it **tall and stacked**. A round boulder with two arms would
read as an existing franchise creature.

### Craglash — 96×96 frames, 6 × 13 (576×1248 px)

Craglash is the first creature from the artist's character sheets. His sheet is a
pixel recreation of that sheet made by `tools/gen_craglash.py`, a small puppet rig
(torso, legs, arms, segmented neck, maned head) posed frame by frame, with the palette
sampled from the artwork. Big frames because the neck reaches far: the head is 50 px
in front of the feet on Boulder Lash and 75 px above them at the top of Avalanche Coil.
Feet at **x 34, y 90**. Any creature can use a bigger frame by setting `"frame"` in its
JSON; the game, the cut-in and the team select scale to it. His up and down sheets
(`craglash_down.png`, `craglash_up.png`) are **128×160** frames with the same rows minus
the knockout, feet at x 64, y 112 (down) and y 124 (up); the same rig draws them from
the front and from behind.

![Craglash sheet, 3x](craglash_preview.png)

| Row | Animation | Frames | Notes |
| --- | --- | --- | --- |
| 0 | idle | 4 | arms up, neck swaying |
| 1 | run | 6 | stomping walk cycle |
| 2 | claw | 4 | Rake (light 1): front claw wind, swipe, follow-through, recover |
| 3 | backhand | 4 | Backhand (light 2): the far arm swings across the body |
| 4 | headbutt | 4 | Headbutt (light 3) and Landslide Entry: neck pulls back, head snaps forward |
| 5 | stomp | 6 | Rockslide Stomp: charge A, charge B (foot raised), rise, stomp, impact, recover |
| 6 | lash | 6 | Boulder Lash: coil back ×3, full extension, retract, recover |
| 7 | bedrock | 4 | Bedrock: brace, rooted hold (cracks glowing), roar, stand |
| 8 | coil | 6 | Avalanche Coil: neck rises, hooks overhead ×2, crash, impact, recover |
| 9 | dodge | 4 | tuck, head pulled in low |
| 10 | hurt | 2 | recoil; frame 1 doubles as the crumple pose |
| 11 | guard | 2 | forearms crossed, head tucked behind them |
| 12 | ko | 4 | stagger, topple, down, neck stones scattered |

When the artist's final Craglash arrives, either keep this layout (then it drops in), or
change the `"sprite"` block in `data/creatures/craglash.json` to match theirs. Design
note: keep the neck as flat slabs rimmed in red rather than round grey boulders, so it
doesn't read as a chain of boulders from an existing franchise.

### Barkley — 96×96 frames, 8 × 13 (768×1248 px)

Barkley is the second creature from the artist's sheets. `tools/gen_barkley.py`
recreates him as a small **3D puppet** (a trunk that forks into two leg-trunks with
splayed roots, two long branch arms with twig fingers and leaf sprouts, a face with
small blue eyes and a long nose, a moss beard, and the log across his head with its
rings on the cut end), posed once and projected into all three sheets. That keeps the
views in step, including Timber Twister, where the whole tree turns on its roots. The
side sheet is a cheated 3/4 view: forward is drawn one to one so reach on screen
matches reach in the simulation, while his sideways span is turned toward the camera
so the arms and the log across his head still read. Feet at **x 40, y 90**. Up and down
sheets (`barkley_down.png`, `barkley_up.png`) are **128×160** with the same rows minus
the knockout, feet at x 64, y 112 (down) and y 124 (up). Eight columns because the
spin needs them; `"select_scale"` in the sprite block shrinks his portrait on the team
select (the log makes him tall for his frame).

![Barkley sheet, 3x](barkley_preview.png)

Facing down and up: [`barkley_views_preview.png`](barkley_views_preview.png).

| Row | Animation | Frames | Notes |
| --- | --- | --- | --- |
| 0 | idle | 4 | the sheet's pose: one arm low, one raised in a curl; slow sway |
| 1 | run | 6 | lumbering stride, arms swinging like boughs |
| 2 | twig | 4 | Twig Swipe (light 1): right arm whips across |
| 3 | bough | 4 | Bough Swing (light 2): left arm swings back the other way |
| 4 | logdrop | 4 | Log Drop (light 3) and Timber Drop: rear back, tip forward, bonk with the log |
| 5 | twister | 8 | Timber Twister: coil ×2 (charge), spin at 0°, 90°, 180°, 270°, slow, recover |
| 6 | grab | 6 | Branch Grab: wind back, reach, full extension ×2, reel in, recover |
| 7 | pinecone | 5 | Pinecone Bomb: pinecone in hand, overhead, throw, follow-through, recover |
| 8 | eruption | 6 | Root Eruption: arms up ×3 (leaves glowing), plunge into the floor ×2, recover |
| 9 | dodge | 4 | bow low under the swing |
| 10 | hurt | 2 | recoil; frame 1 doubles as the crumple pose |
| 11 | guard | 2 | branch arms crossed in front |
| 12 | ko | 4 | stagger, then topples over backward like a felled tree, roots torn up |

Moves time their frames with `"anim_at"` (`[[tick, frame], ...]` in the move's JSON),
so the spin and the lob play exactly in step with the hits. Design note: the log across
the head, the moss beard and the root feet are what make him read as Barkley; a round
tree body with leafy hands would drift toward existing franchise creatures.

### Gillbert — 128×128 frames, 8 × 13 (1024×1664 px)

Gillbert is the third creature from the artist's sheets. `tools/gen_gillbert.py` builds
him on Barkley's 3D approach: a fish body as a tube along a bendable spine (curl, arch,
side-to-side wiggle, roll onto his side), the red-and-white life ring split into the
half behind him and the half in front, fins, barbels, an orange eye on each side, the
line tangled round his body, and the **rod as its own rigid piece** with a position and
spin in every pose. A pose that tips his nose up lifts him so the tail stays on the floor.
He always wears the ring, and it is much bigger than he is thick (it shows above his back and
below his belly). Side-on its far half goes behind his body and its near half crosses in front,
kept wide enough to read however he turns; head-on or from behind he is split at the ring, so
the end nearer the camera is drawn over it and the far end under it. Feet (belly) at **x 70, y 112**; big frames because the rod flies out in front on Cast Line
and tumbles far behind on the run. Up and down sheets (`gillbert_down.png`,
`gillbert_up.png`) are **96×144**, feet at x 48, y 92 (down) and y 76 (up).

![Gillbert sheet, 3x](gillbert_preview.png)

Facing down and up: [`gillbert_views_preview.png`](gillbert_views_preview.png). The run in
all three views: [`gillbert_run.gif`](gillbert_run.gif).

| Row | Animation | Frames | Notes |
| --- | --- | --- | --- |
| 0 | idle | 4 | lying on his belly, gills working, tail flicking, a little twitch hop |
| 1 | run | 8 | a flop: curl, spring, arch in the air, nose down, slap, bounce, settle; the rod tumbles end over end behind |
| 2 | jab | 4 | Snout Jab (light 1): rear back, nose bonk ×2, recover |
| 3 | whip | 4 | Tail Whip (light 2): a half turn so the tail lashes across in front |
| 4 | flail | 6 | Rod Flail (light 3): the rod swings up on its line, over him and down in front |
| 5 | splash | 6 | Splash Zone: charge A, charge B (tail high), rise, slap, splash, recover |
| 6 | flopdash | 4 | Flop Dash: coil, launch, skid, recover |
| 7 | cast | 6 | Cast Line: rod back, over the top, thrown, follow-through without the rod (the game draws it in flight), being reeled in (shown while the line hauls him), recover |
| 8 | leap | 6 | The One That Got Away (and Splashdown from frame 3): crouch, spring, straight up, falling belly-first, belly-flop, recover; `"view_lift"` raises him off the screen |
| 9 | dodge | 4 | a sideways flip in a hop |
| 10 | hurt | 2 | recoil; frame 1 (on his side) doubles as the crumple pose |
| 11 | guard | 2 | curled up behind the life ring |
| 12 | ko | 4 | a last flop, then on his side with the rod across him |

Design note: the life ring, the barbels and the rod on its line are what make him read as
Gillbert, not as a fish from an existing franchise.

### Chef Cerebro — 128×128 frames, 8 × 13 (1024×1664 px)

Chef Cerebro is the fourth creature from the artist's sheets. `tools/gen_cerebro.py` uses
the same cameras as Barkley and Gillbert, but renders differently: every piece is sampled
as 3D points (the brain as ten overlapping lobe ellipsoids, the brain stems as tubes, the
blades and spatula head as flat plates, the mallet head as a box, the pan as a cylinder)
and splatted into a depth buffer. Each pixel is then shaded from its normal, outlined
where the silhouette ends and along every seam between pieces (which draws the lines
between the lobes, as on the sheet), and decorated in the brain's own coordinates: the
black half-moon sunglasses (turned out to the sides, so they read from the side and the
front), their bridge and arms, and a few wrinkle strokes on each lobe. Tools are outlined
in black and the brain in the sheet's dark maroon.

His kit, as drawn: the big chef's knife on the front stem, the navy spatula on the back
stem, and a dark brown pan on his back with the meat mallet standing in it; a thinner
third stem draws small knives and the mallet out of the pan. Feet at **x 62, y 100**. The
rig is modelled large and drawn at 0.72 scale (`SCALE`). Up and down sheets
(`cerebro_down.png`, `cerebro_up.png`) are **112×128**, feet at x 56, y 88 (down) and
y 76 (up).

![Chef Cerebro sheet, 3x](cerebro_preview.png)

Facing down and up: [`cerebro_views_preview.png`](cerebro_views_preview.png).

| Row | Animation | Frames | Notes |
| --- | --- | --- | --- |
| 0 | idle | 4 | settled on the floor, breathing, a glint across the sunglasses |
| 1 | run | 6 | an inchworm scoot on his stems: squash, stretch forward, hop, land |
| 2 | flick | 4 | Knife Flick (light 1): a small knife drawn from the pan, wound back, flicked; the game draws it in flight |
| 3 | flick2 | 4 | Backhand Flick (light 2): a sidearm throw across his body |
| 4 | toss | 5 | Mallet Toss (light 3): the mallet out of the pan, over his head, hurled; back in the pan |
| 5 | tenderize | 6 | Tenderize: charge A, charge B (mallet high), rise, pound, impact, recover; Order Up plays from frame 3 |
| 6 | cleaver | 6 | Cleaver Toss: the big knife back over his head, thrown, follow-through without it, a new one in hand |
| 7 | flipout | 6 | Flip Out: the spatula swings round low, slides under, scoops, carries over his head, recover |
| 8 | flurry | 6 | Knife Flurry: a fan of knives drawn, set, two alternating throws (looped while the stream flies), recover |
| 9 | dodge | 4 | a squashed roll onto his side and back |
| 10 | hurt | 2 | recoil, sunglasses knocked askew; frame 1 doubles as the crumple pose |
| 11 | guard | 2 | hunkered down behind the spatula, held up like a shield |
| 12 | ko | 4 | knocked back, tips over, deflates, sunglasses off |

Design note: the sunglasses, the brain stems holding kitchen tools and the pan on his
back are what make him read as Chef Cerebro. Name check before release: "Cerebro" is
also the name of a well-known comic-book device (see the PR notes).

### Hissy Fitz — 128×128 frames, 8 × 13 (1024×1664 px)

Hissy Fitz is the fifth creature from the artist's sheets. `tools/gen_hissy.py` renders
like Chef Cerebro's generator (3D points splatted into a depth buffer, three-tone shading,
outlines round the silhouette and along seams), with black outlines as on the sheet. The
rig: a big round head floating over the floor (she never touches it: the gloves stay up
in a guard under her chin, `NEAR_REST`/`FAR_REST`, everywhere but the knockout), nine spotted green hair snakes (each a
wavy tapered tube ending in a little head with eyes and a forked red tongue) fanned out
in a sunburst, two purple crystal earrings, and two more snakes from under her chin down
to the red boxing gloves. The face (big yellow slit eyes with blue eyeshadow and lashes,
a cocked brow, the lopsided zigzag grin) is painted once into a texture in the head's own
azimuth and elevation, so it wraps the round head in every view; in the side view her
head is turned a little toward the camera (`SIDE_CHEAT`), so both eyes and the grin read.
Expressions: grin, shout, gaze (glowing eyes), hurt, ko.

Feet at **x 64, y 104**, drawn at 0.72 scale. Up and down sheets (`hissy_down.png`,
`hissy_up.png`) are **112×128**, feet at x 56, y 104 (down) and y 92 (up).

![Hissy Fitz sheet, 3x](hissy_preview.png)

Facing down and up: [`hissy_views_preview.png`](hissy_views_preview.png).

| Row | Animation | Frames | Notes |
| --- | --- | --- | --- |
| 0 | idle | 4 | floating in place with her gloves up in guard: a slow bob, hair snakes swaying |
| 1 | run | 6 | gliding forward through the air, gloves up and weaving, hair streaming back |
| 2 | jab | 4 | Snake Jab (light 1): the near glove snaps out at head height |
| 3 | jab2 | 4 | Snake Jab (light 2): the far glove crosses in |
| 4 | lash | 5 | Hair Lash (light 3): she ducks, then the hair snakes whip forward and bite |
| 5 | uppercut | 6 | Coil Uppercut: charge A, charge B (glove coiled low), rise, uppercut, follow-through, recover; Hiss Off plays from frame 3 |
| 6 | spit | 5 | Venom Spit: rear back, front snakes drawn back, spit (a venom glob at their mouths), recover; the game draws the glob in flight |
| 7 | gaze | 4 | Stone Gaze: lean in; frames 1 and 2 alternate (glowing eyes, hair raised like a hood) while it lasts; recover |
| 8 | petrify | 6 | Petrify Punch: wind back, the haymaker held (eyes glowing), the punch at full stretch, follow-through, recover |
| 9 | dodge | 4 | the head drops between the gloves and rolls |
| 10 | hurt | 2 | recoil; frame 1 doubles as the crumple pose (frame 0 is the petrified statue's pose, tinted grey by `CreatureView`) |
| 11 | guard | 2 | gloves up in front of her face, snakes pulled in |
| 12 | ko | 4 | the head drops onto the gloves and tips over, hair limp, tongue out |

Design note: she must not read as Medusa from mythology-themed games or films: the boxing
gloves, the floating head, the earrings and the cartoon grin carry her look. Snakes for
hair is a myth motif anyone can use; the name and gloves are hers.

## Training dummy — 48×48 frames

4 columns × 2 rows. Row 0: idle, hurt A, hurt B, guard. Row 1: knock-over, 4 frames.

## Floor tiles — 8×8

One row of 10 tiles: 0–3 dirt variants, 4–7 cracked variants (each with a different
fracture direction), 8 pit with lit far rim, 9 deep pit.

## Crowd — 12×16

Four fan variants, two frames each (seated, cheering), in one row.

## Effects — 16×16

Row 0: hit spark, 4 frames. Row 1: dust puff, 4 frames (fading alpha). Row 2: Runoff
shockwave, 4 frames, facing right (mirrored when it travels left).

## Palette

The placeholders use a small hand-picked palette defined at the top of
`tools/gen_sprites.py`. The final art should use one published palette for the whole game.
