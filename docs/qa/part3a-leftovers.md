# Part 3a: 32 px migration leftovers (read-only sweep, 2026-10-29)

Swept src/, data/, tools/, tests/ for hardcoded 8 / 16 px values, old sprite references and
doc drift. Verdict: the migration is essentially complete. ArtScale (`PX_PER_UNIT 2`,
`CELL_PX 16`, `TILE_PX 32`) drives the arena tiles, crowd and overlays; every creature sheet is
a `_2x` sheet at ppu 2; every `res://assets/` path referenced from src/ and data/ exists.

## Follow-up (view)

| Where | What | Verdict |
| --- | --- | --- |
| src/view/arena_view.gd ~955-990, 976, 984, 1087 | 8 px slices of `assets/sprites/tiles.png` (176x8, 1x): the paint fallback used only when a map has no picture (`_art == null`). All six shipped maps have `arena_<id>.png`, so it is effectively dead. | retire or mark 1x on purpose (open question) |
| src/view/arena_view.gd 1152-1156, 1257 | procedural pit atlas, `Image.create(28, ...)`, one texel per unit: possibly a deliberate 1x look, possibly a missed 2x | playtest check (hand list) |
| assets/sprites/fx.png (64x48) | density not checked | unsure |

## Fine (units, not pixels)

- src/sim/sim_defs.gd:60-61 `CELL 8`, `GRID_X 16`; creature_sim.gd `FALL_DAMAGE 8`;
  match_sim.gd offsets 16: sim units, must not change.
- arena_view.gd:929-930 (wall 8); crowd_view.gd:22-66 (PPU, CELL_W 12, CELL_H 24, RISE 8,
  BLOCK 96, FRONT_CROP 14; consistent with crowd.png); creature_view.gd:54-56, 220-222 (frame
  48, origin 24,43); surge_aura.gd:37, 50 and light2d_view.gd:568, 636 (`fx_top` default 32,
  every fighter sets it); fx_view.gd:2012-2013 (scaled); wipe.gd:10 `CELL 24` (screen space).
- The 1x grid sheets (assets/sprites/<id>.png and `_down/_up/_n/_e`) are on disk but
  unreferenced; docs/SPRITES.md keeps them for `*_DENSITY=1` regeneration.

## Creature data (data/creatures/*.json; no data/sprites dir)

| Fighter | Side frame | Down / up frame | fx_top | radius |
| --- | --- | --- | --- | --- |
| barkley | 192 | 256x320 | 58 | 11 |
| cairn | 192 | origin only | 44 | 10 |
| cerebro | 256 | 224x256 | 42 | 11 |
| craglash | 192 | 256x320 | 72 | 12 |
| crease | 192 | origin only | 38 | 10 |
| culvert | 192 | origin only | 24 | 13 |
| digby | 256 | 224x256 | 28 | 9 |
| dummy | 192 | origin only | none | 10 |
| gillbert | 256 | 192x288 | 26 | 9 |
| hissy | 256 | 224x256 | 40 | 10 |
| pete | 256 | 224x256 | 40 | 9 |
| sno | 256 | 224x256 | 44 | 11 |

Unsure: a top-level `"frame": [0, 0]` in cairn.json and crease.json (leftover?); the dummy has
no `fx_top`. The body `radius` was never rescaled with the art (see part3b-shapes.md).

## Docs

- docs/MECHANICS.md:267 "CELL 8 px", "GRID_X 16": sim units, the "px" wording now misleads.
- docs/SPRITES.md:251 Craglash mane "71 px above his feet (fx_top)": JSON says 72, pre-2x text.
- README.md:381 "lights reach about 16 px", README.md:767 "32 px around the spot": sim units or
  screen px? (unsure)
