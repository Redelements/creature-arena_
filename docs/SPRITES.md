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
