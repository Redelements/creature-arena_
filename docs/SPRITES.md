# Sprite sheet layouts

Use this as the spec for artists. If a replacement sheet keeps the same frame size and
row layout, it drops in with no code changes. If a layout does change, update the
`"sprite"` block in the creature's JSON file in `data/creatures/`; each move picks its
animation by name with its `"anim"` field.

![Current placeholder sheets](sprite_preview.png)

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
JSON; the game, the cut-in and the team select scale to it.

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
