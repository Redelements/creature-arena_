# Sprite sheet layouts

Use this as the spec for artists. If a replacement sheet keeps the same frame size and
row layout, it drops in with no code changes. If a layout does change, update the
`"sprite"` block in the creature's JSON file in `data/creatures/`.

![Current placeholder sheets](sprite_preview.png)

## Creatures — 48×48 frames

Creatures face **right**. Feet rest at the **origin** pixel (Culvert: x 21, y 43), which
sits on the ground where the creature's shadow is drawn. The game mirrors the sprite to
face left. Leave at least 1 px of transparent margin on every side.

| Row | Animation | Frames | Notes |
| --- | --- | --- | --- |
| 0 | idle | 4 | breathing loop, ~10 ticks a frame |
| 1 | run | 6 | loop, ~5 ticks a frame |
| 2 | light | 4 | windup, strike, follow-through, recover (shared by all three combo hits) |
| 3 | heavy | 6 | charge A, charge B (alternate while held), leap, slam, impact, recover |
| 4 | dodge | 4 | roll; plays once across the 20-tick dodge |
| 5 | hurt | 2 | loop while in hitstun |
| 6 | guard | 2 | holding, blocking a hit |
| 7 | ko | 4 | collapse; holds the last frame |

Culvert's sheet is 6 columns × 8 rows (288×384 px). Unused cells stay transparent.

## Training dummy — 48×48 frames

4 columns × 2 rows. Row 0: idle, hurt A, hurt B, guard. Row 1: knock-over, 4 frames.

## Floor tiles — 8×8

One row of 10 tiles: 0–3 dirt variants, 4–7 cracked variants (each with a different
fracture direction), 8 pit with lit far rim, 9 deep pit.

## Crowd — 12×16

Four fan variants, two frames each (seated, cheering), in one row.

## Effects — 16×16

Row 0: hit spark, 4 frames. Row 1: dust puff, 4 frames (fading alpha).

## Palette

The placeholders use a small hand-picked palette defined at the top of
`tools/gen_sprites.py`. The final art should use one published palette for the whole game.
