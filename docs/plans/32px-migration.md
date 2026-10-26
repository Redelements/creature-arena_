# 32 px art scale: audit and decision

Branch `proof/32px-szadi`, October 2026. The goal: ground tiles from Szadi art's RPG Worlds
Set 1 (32 px tiles), kiddolink's VFX Complete Set S1 (96 px effects) and PixelLab-regenerated
fighters, all at twice today's art density. This page records what the audit found and the
approach taken, so the choice isn't re-litigated and a later session knows where the
scale lives.

## What the audit found

### How the world is drawn today

- The sim works in "logical pixels": `SimDefs.CELL` 8 (one terrain cell), a stadium floor of
  84 x 36 cells, `VIEW_W/VIEW_H` 480 x 270 shown at a time.
- `project.godot` already runs a **960 x 540 viewport with stretch scale 2**, so one world
  unit is two viewport ("grid") pixels, and the canvas is 480 x 270 units. At a 1920 x 1080
  window `pixel_scale_factor` makes that 4 screen pixels per unit.
- Every sheet (fighters, arenas, `tiles.png`, `fx.png`, crowd) is drawn at **1 texture pixel
  per world unit**: `CreatureView` scales nothing, `ArenaView` draws the baked picture at
  `-MARGIN` 1:1, `tools/gen_arenas.py` bakes 8 px per cell. So today's art pixels are
  already 2 grid pixels wide; the 960 x 540 grid is half empty.
- Fighters are **not 16 px sprites**: frames are 96 to 128 px with 45 to 70 px bodies
  (Crease 96 px frames, feet at (48, 72)); a 16 px floor tile is 2 x 2 cells. A fighter stands
  about three tiles tall, where Szadi's Fantasy Lands Warrior (80 px frames) stands about
  1.5 of its 32 px tiles.
- There is no world root node: every world view hangs directly off `Main`, with the HUD,
  menus and touch overlay on `CanvasLayer`s (which ignore world transforms).

### Where the pixel numbers live

Centralised: only `SimDefs.CELL / GRID_X / GRID_Y / FRONT_WALL / VIEW_W / VIEW_H`,
`ArenaView.MARGIN` (copied into five views and `gen_arenas.py`), `CrowdView.SHOW_*`, and
`UiTheme`'s sizes. Everything else is a literal where it's used:

| Layer | Pixel-unit numbers | Shape |
| --- | --- | --- |
| `src/sim/` | ~22 named constants, ~135 literals / code defaults (reach, radii, knockback, projectile and hazard defaults, spawn insets, thresholds like `knock_vel.length_squared() < 0.0025`) | scattered; only grid maths goes through `CELL` |
| `data/creatures/*.json` | ~445 values: `speed`, `accel`, `radius`, `reach`, `hit_radius`, `knockback`, `lunge`, `dash.speed`, `projectile.*`, `zone.radius`, `terrain_*`, plus ~50 `ai` ranges | every fighter, every move |
| `data/rules/*.json`, `data/arenas/*.json` | ~50 rules values (shrine radius, hazard radii / speeds / pushes, pads, spawn spread, CTF pass range) + ~25 arena coordinates (`spawns`, `track`, `bases`, `shrines`) | cells (`pieces`, `size`, `rows`) would not change |
| `src/ai/` | ~100 literals in `cpu_controller.gd` (spacing bands, probes, kite ranges), `team_intent.gd` `NEAR_PX` 160 / `MARK_PX` 240, `nav_grid.gd` one 4 px sampler | scattered |
| `src/view/` | ~1,000 `Vector2`/`Rect2` literals and ~600 `draw_*` lines in world space (60% in `fx_view.gd`); ~250 whole-pixel `round()` sites | scattered |
| `src/game/main.gd` camera | `CAM_PAD`, `FOLLOW_R`, look-ahead, exchange and lead constants; zoom levels are unitless | one block |
| `src/ui/`, `src/input/touch_pad.gd`, HUD | canvas-unit layouts (screen space) | unchanged by a world-scale move |
| tests | ~30 test files pin world positions and reaches in px (`test_arena`, `test_vision`, `test_crossings`, `test_touch_targeting`, `test_ui` camera…) | scattered |

### What the netcode serializes

Nothing in px. Online peers exchange input bitmasks (buttons plus 64-step aim and move
indices), frame numbers, SHA-256 state digests every 60 frames, ping times, the data hash
and `NET_VERSION` (43), and voice codec bytes. Spectators and the Daily receive input logs
and replay them locally. `MatchSim.snapshot()` never leaves the machine. Replays
(`format 1`) store setup and inputs, with no version or data hash, so a sim change makes
old replays play back as a different fight without an error. Ratings and daily scores are
hp share and time.

So positions, speeds and radii have no wire meaning to preserve: the constraint is that
every build in a match must replay the same sim. Doubling sim constants would be exact in
floating point (x2 and `sqrt` scale exactly) **except** the places a length meets an
unscaled number: seeded `x % int(span)` draws for meteors and boulder lanes, the 4 px
shelter sampler, `resolve_body`'s 1..96 px search, and a dozen stop thresholds. Each of
those would change outcomes (not desync, but a different fight) unless scaled by hand.

## The decision: keep world units, change the art density

Two routes were weighed:

**(a) Double the constants.** `CELL` 16, every px number x2, viewport at 1:1. One world
unit = one art pixel for ever. Cost: ~150 code sites in the sim and CPU, ~550 data
values, ~1,500 view and test literals, the threshold list above, a `NET_VERSION` bump,
every balance pin re-measured. Estimate: 3 to 5 days, with a real chance of a missed
literal changing a fight quietly.

**(b) Keep the sim's units, draw art at 2 px per unit.** The grid is already 2 px per
unit: new art at 2 px per unit lands exactly on grid pixels when drawn at scale 0.5, and
old art keeps drawing at scale 1 (2 grid px per art px, as today). The sim, its data, the
CPU, the tests, the digests, the replays and the wire stay byte for byte the same. Cost: a
per-asset "pixels per unit" convention and a scale in the views that draw textures
(creature sprites, arena art, flipbooks, portraits, the select screen), the window
pixel-snapping rule, and the arena baker's output size. Estimate: about a day.

**Taken: (b).** `ArtScale.PX_PER_UNIT = 2` (`src/view/art_scale.gd`) is the one place the
density lives; `tests/test_art_scale.gd` pins it to the project's viewport and stretch
settings, the 16-grid-pixel cell and the 32 px tile. What the request called "tiles 16 to
32, cells 8 to 16, viewport doubled" all holds in grid pixels: a cell is 16 grid px, a Set 1
tile is 32 grid px (2 x 2 cells), and the viewport is 960 x 540. Nothing crossed the wire
differently, so no `NET_VERSION` bump is needed for the scale itself (new arena data still
moves the data hash as it always has).

Per-asset density:

- Fighter sheets: `sprite.ppu` in the creature JSON (default 1; a regenerated sheet says 2).
  `CreatureView` scales the sprite by `1 / ppu`; `origin`, `frame` and `portrait` stay in
  sheet pixels. Positions snap to `1 / ppu` units so 2x art never lands between its own
  pixels.
- Arena pictures: inferred from the texture (a picture `ppu` times the expected size is
  2x art). `gen_arenas.py` keeps its geometry in world units.
- Flipbook effects (`data/vfx.json`): `ppu` per effect; kiddolink's 96 px frames are 48
  units across at `ppu` 2, about one fighter.
- Tiles: a 32 px Set 1 tile covers 2 x 2 cells; the overlay layer works in 16 px (one cell)
  tiles.

Window snapping: `pixel_scale_factor` now keeps whole screen pixels per **grid** pixel (per
art pixel of 2x art), not per world unit. 1920 x 1080 and 3840 x 2160 are unchanged
(4 and 8 per unit); 1440 x 810 shows 2 per unit instead of 3 and 2560 x 1440 shows 4
instead of 5, so the HUD is a step smaller there and every art pixel is even.

## Proof

Crease's sheets upscaled 2x (nearest) and declared `ppu` 2 render the same picture as the
1x sheets at camera zoom 1: the silhouette's extents match to the pixel, every texel is
the same 4 x 4 screen-pixel block at 1920 x 1080 scale, and the full suite (1,174 tests)
passes unchanged. The one difference is the flash shader's rim (Surge ready, Stoneskin):
it is one texel thick (`TEXTURE_PIXEL_SIZE`), so on a 2x sheet it is one grid pixel instead
of two, in step with the finer outlines. Nothing in `data/` or `src/sim/` moved.

## What this changes in the plan

- Existing fighters don't get blockier: they already draw at 2 grid px per art px, and
  keep doing so until a sheet with `ppu` 2 replaces them. A regenerated fighter keeps its
  world size (the hit circles still match the art), so a 2x Crease needs a 192 px frame
  (96 x 2) for the same reach, or a tighter crop if PixelLab's canvas is smaller.
- The fighter-to-tile proportion (about three 32 px tiles tall) is today's look and stays.
  Szadi's sets are drawn for characters about 1.5 tiles tall; the Warrior reference poses
  are at that scale.
- Kiddolink effects at `ppu` 2 are fighter-sized, which fixes the "96 px effects too big
  for light hits" note from PR #231.
