# tools: generators (not part of the game)

Godot ignores this folder (`.gdignore`). Run the scripts with Python 3 (Pillow and numpy for
sprites and audio). Each sprite generator writes `assets/sprites/<id>.png`, `<id>_down.png`,
`<id>_up.png` and a `docs/<id>_preview.png`; after regenerating, run `--import` or the game
keeps the old import cache. Sheet layouts: `docs/SPRITES.md`.

- `cut_vfx.py <packs dir>`: cuts the move effects out of kiddolink's VFX Complete Set S1
  (bought; never in the repo) into `assets/vfx/<name>.png` strips (96 px frames, ppu 2,
  palette-snapped) plus `manifest.json` with each effect's MoveFx defaults (`EFFECTS`); then
  `build_vfx.gd` (Godot, `--headless --script res://tools/build_vfx.gd` after `--import`)
  makes `assets/vfx/<name>_frames.tres` (SpriteFrames) and `<name>.tres` (`MoveFx`). Rerun both
  only when a cut changes; lasting tweaks go in `EFFECTS`, since a rebuild overwrites the `.tres`.
- `cut_tiles.py <packs dir> <set>`: cuts a tiled-arena set out of the bought packs (never in
  the repo) from the recipe `tile_recipes/<set>.json` (keys in its docstring: fills, blob
  terrains whose 16 side combinations are read off the art, animated translucent surfaces
  over a terrain (Set 1's water sheet over its river bed, alpha kept; fills, terrains and
  surfaces take a `tint`), pieces by kind, the overlay's cliff strips, decor sprites,
  animated strips) into `assets/tiles/<set>_*.png` plus
  `<set>_manifest.json` (the overlay ids `OVERLAY` that `ArenaView.OV_*` and `assets/README.md`
  name). Colours snapped to the palette. Then `build_tiles.gd [-- --set=<set>]` (Godot,
  `--headless --script res://tools/build_tiles.gd` after `--import`) makes
  `assets/tiles/<set>_ground.tres` (every terrain matched by sides, variants by probability),
  `<set>_overlay.tres` and every tiled arena's `assets/arenas/<id>.tscn` from its JSON `tiles`
  block (`ground`, `edge`, `grass`, `water`, `styles`, `decor`, `anim`, `markings`; its header
  explains each). Rerun both only when a cut or a map changes; the game and CI use the
  committed files. Szadi art's `hills2.png` draws its cliff ledge 16 px down the tile: the
  overlay's 16 px strips are cut from the rows it occupies. One recipe per pack family: a
  map names its set in `tiles.set`.
- `import_frames.py <id> [--view side]`: an artist's or PixelLab's frames
  (a drop zone `incoming/<id>/<view>/<anim>/<nn>.png` under `assets/sprites`, or strips, `frames.json` beside them
  with the canvas, the feet point, an integer export scale and the `ppu`; the spec is
  `docs/pixellab-spec.md`) into one of the game's sheets: palette-snapped (no dither, alpha
  hardened), downsampled by the scale, every frame padded to `--frame` (192) with the feet
  on `--origin` (96, 144), rows in the creature's `sprite.anims` order (a missing row stays
  blank and is reported), plus a `SpriteFrames` `.tres` and the `sprite` JSON block to paste
  (`ppu` 2). `--split <sheet>` cuts an existing sheet into that layout for a dry run, `--check
  <png>` compares the result pixel for pixel (the 1x Crease sheet rebuilds identically).
- `palette.py`: the master palette (hue lines, five-step ramps, outline inks; rules in its
  docstring and `docs/SPRITES.md`, "Palette"). `ramp(name, shift)`, `ramp_for(rgb)`,
  `ink_for`, `nearest` / `snap` (images, dithered) / `snap_ramp` (arena ramps);
  `python3 tools/palette.py` redraws `docs/palette.png`. Every fighter and the arenas use it:
  the splat3d rigs, Cerebro and Hissy (they call `S.shade`/`S.outline` on their own buffers),
  Barkley and Gillbert (through `shade2d.py`) and Craglash's 2D shader; only `gen_sprites.py`
  (tiles, crowd, effects) isn't ported. A new line or ramp goes at the end of `LINES` / `WINDOWS`;
  a line a fighter names but the arenas must not pick up goes in `NAMED_ONLY` (adding colours
  to the snap tables moves arena floor pixels on a rerun of `gen_arenas.py`).
- `shade2d.py`: splat3d's shading look for generators that paint flat 2D shapes per part
  (Barkley, Gillbert): `Materials(MAT)` from ramp names, then `shade(img, name)` (a height
  field from each shape's distance to its edge, the key light, rim light, lone-pixel
  cleanup), `groove(img, det, k)` (detail lines k ramp steps along), `outline` (each
  material's ink), `darken` (one step, the far limb), `stack(layers)` (back to front, an
  outline over a piece behind becomes its deep-step seam). Layers carry their material ids,
  outline ring and shading normals in `img.info`; `keep(new, old)` copies them onto a new
  Image (a layer rebuilt without it lights flat in the normal sheets). `normal_map(img)` packs
  a stacked frame's normals for `splat3d.finish_frame`.
- `splat3d.py`: the shared renderer (pose a 3D rig, sample parts as points, splat per view,
  ramp-shade from the master palette with a rim light, outline in each material's ink).
  Prefer this shape for new fighters, like `gen_digby.py`: `build(pose, view)`, a `MAT`
  table of palette ramp names, `ROWS` / `VIEW_ROWS`, pose functions;
  `python3 tools/gen_<id>.py inspect idle:0 run:2` previews frames.
  `write_sheets(..., normals=True)` also writes a normal sheet `<sheet>_n.png` beside each
  colour sheet (`normal_frame`: the shading's screen normal, smoothed per piece; packing in
  `docs/SPRITES.md`, "Normal sheets") and, when anything on it glows, an emissive sheet
  `<sheet>_e.png` ("Emissive sheets": `configure(emissive=...)` per material, `EMISSIVE_FN`
  for painted glow, `emissive_colours`; Surge eyes: `surge_eyes(id)`, `eye_part()`,
  `r["eye_px"]`, lit only in the Surge's rows, `ROW`); the colour sheets come out byte for
  byte the same.
  Every fighter generator writes both. The rule for any renderer: call
  `S.finish_frame(r, img)` on the finished frame (or with `normals=` ready-made) and build
  sheets with `S.collect` / save with `S.save_extras`; `collect` refuses a frame whose
  renderer never called it or whose normal frame covers other pixels. Crease passes one
  piece per flat face (folds stay sharp); Craglash draws each frame twice (`_with_normals`:
  a normal pass where `shade` paints the pillow normal and the colour-only steps are off).
  Check a change keeps the colour sheets identical: hash `assets/sprites/*.png` before and
  after regenerating.
- `gen_culvert.py`, `gen_digby.py`, `gen_pete.py`, `gen_sno.py`, `gen_crease.py`, `gen_cairn.py`,
  `gen_dummy.py`: splat3d rigs (Crease: faceted paper, 128x160 frames, `decorate` draws creases).
  Cairn's stones are rigid (no squash): `pack` and per-stone `off` / `tilt` carry the weight
  and the overlap; `decorate` paints his face and grain from stone-local coordinates (each
  stone's `local` is offset by 100 per stone, so one buffer tells the stones apart), and
  `python3 tools/gen_cairn.py kofx` prints `ko_fx.pieces` / `x_eyes` for `cairn.json` after
  the rig changes. The dummy is training equipment, not a creature (a sack on a spring).
- `gen_cerebro.py`, `gen_hissy.py`: point-sampling rigs with their own copy of splat3d's
  primitives, `Cam` and rasteriser, but splat3d's shading and outlines: `S.configure(MAT,
  ...)` with MAT on palette ramps, then `S.shade(r)` / `S.outline(r, img)` on their buffers,
  with `decorate`-style passes between (Cerebro: wrinkles, sunglasses, then the outline with
  no line at the stem, the flush, glow, smears; Hissy: the face texture). Cerebro's tools
  outline black via `outline_mats`; Hissy's silhouette is black (`S.INK` overridden). They
  import the palette as `PAL`: `P` is their pose constructor.
- `gen_barkley.py`, `gen_gillbert.py`, `gen_craglash.py`: older (Barkley/Gillbert project a
  3D rig per view and paint 2D shapes, shaded and outlined by `shade2d.py` from a `MAT`
  table of ramp names; detail colours in `C` come from those ramps; Craglash is a 2D IK puppet whose renderer rounds to whole pixels in
  `whole_pixels()`, so its poses may hold floats; it shades each layer from palette ramps
  with splat3d's steps and rim light (`shade`), draws outlines as per-material markers
  that `finish()` turns into ink on the silhouette and the deep step on seams, so every
  `render*` must end in `finish()`; its up/down sheets come from `VRig`, its
  diagonals from `DRig`, which turns the VRig's 3D reading 45 degrees: `docs/SPRITES.md`).
- `gen_sprites.py`: the small placeholder sheets (floor tiles, crowd, effects) and
  `docs/sprite_preview.png`. `gen_arenas.py`: each map's
  whole picture (stands on all sides: `_stands`, `_side_stands`, `_front_stands`, in step with
  `CrowdView`'s seats) plus its cracked and changed-piece floors (and `_crackmask`, the cracks
  alone, which the view lights as cracks spread and heal), the Caravan's wagon and the CTF flag (reads `data/arenas/<id>.json`;
  rerun after moving a piece or changing a map's `light`: pieces cast their shadows along it,
  `cast_shadows`, `CAST_HEIGHT`, kept in step with `ArenaView.CAST_HEIGHT` and `ShadowLayer.light_of`).
  Depth rules are in its docstring ("Depth"): the far-to-near gradient and the big floor
  features go through `floor_shift` (palette fine-line steps, applied right after the ground is
  painted, before details and the _alt copy), things with height get `faces` and
  `contact_shadow`. It also draws the foreground strips `arena_<id>_fore.png` / `_hang.png`
  (`fore_layers`, `FORE` per map; `FORE_GAP` / `FORE_H` / `HANG_TOP` / `HANG_H` in step with
  `ForeView`). `gen_audio.py`: placeholder
  SFX and music; names must match `data/audio.json`.
- `odin_perf.py`: frame pacing on an Android device over adb (the Odin 3): bakes the run's
  flags into the Android preset, exports a release APK (`--renderer mobile` tries Vulkan),
  plays a seeded fight with `--perf`, reads the report from logcat and the presents from
  SurfaceFlinger (`SCREEN` lines: what the screen showed, refreshes per frame, the queue's
  lag), and writes `build/perf/<label>.txt`. Put back `export_presets.cfg` and
  `project.godot` itself. Judge by the SCREEN lines: the CPU-side frame times look far worse
  than what's shown.
- `codebase_map.py`: writes the generated file list at the end of each area's `CLAUDE.md`;
  `--check` is the CI drift check. Standard library only.

Every character has three sheets with the same rows (side, facing down, facing up); all
generators draw all three. The diagonals (`down_side`, `up_side`: facing down-right and
up-right, `<id>_down_side.png`, `<id>_up_side.png`) are optional extra sheets: a splat3d
rig adds them to its `VIEWS` and the JSON's `"views"` (every fighter has
them, the dummy too; Craglash draws his with `DRig`), and `Cam` projects them; `write_sheets`, `inspect` and the `anim` previews draw every view in `VIEWS`. A
`build(pose, view)` branch on the view name (Pete's `_dollar`) needs a case for them.
Cerebro and Hissy have them too, through their own copies of `Cam` (the two diagonal
branches ported from splat3d; their `main`/`inspect` loop over `S.view_names(VIEWS)`);
Hissy's `CHEAT` dict turns her head per view (`side`, `down_side`).
Barkley and Gillbert have them too, from the same two projections in their own `Cam`; a
`self.view == "side"` / else branch in their painters treats the diagonals as head-on
unless it says otherwise (Gillbert's ring has its own diagonal case in `render`).

## Animation tools (the roster animation pass)

The recipe and why: `docs/SPRITES.md`, "Animation pass"; the plan:
`docs/anim_preview/roster_anim_plan.md`. Every generator, old rig or splat3d, uses the same
tools, so a fighter's pass is posing work only.

- **In-betweens and overlap** (`splat3d.py`, work on any generator's `Pose`, the older rigs
  import them without touching their renderers): `tween(a, b, t, arc_fields, arc, resolve,
  snap, **over)` lerps every number and every (nested) tuple or list of numbers, takes
  strings, bools, None and mismatched shapes from the nearer key, bows `arc_fields` (hands,
  paws) on a quadratic Bézier, and copies `a` before setting fields (constructors that
  derive fields, like Craglash's hip and head lift, aren't run twice). `snap` is for
  fields that must never blend: indices (Pete's `grip`, Barkley's `hold`), held props.
  `resolve(pose)` fills defaults first (Crease's `resolved`: None hands to where build()
  puts them). `tweener(...)` binds those for a generator; `ease`, `EASE_8` (eased 8-frame
  spacing), `cycle(key_fn or (A, B), spacing)`, `lag(frames, field, k, loop=True)` (overlap:
  the field from k frames earlier), `lag_at(frames, field, {frame: value})` (secondary keyed
  in an attack, held between keys).
- **Adapter**: each generator exposes `render_frame(pose, view)` -> one PIL frame and
  `frame_spec(view)` -> `{"w", "h", "origin"}` (splat3d rigs: `S.frame_adapter(SIDE, VIEWS,
  build, decorate)`), `ANIM_CYCLES` (idle and run cycle lengths in ticks), and optionally
  `CLIPS` (Crease's shows the format), `OLD_REF`, `ANIM_TICKS`.
- **`python3 tools/gen_<id>.py anim [--out DIR] [--old REF] [clip ...]`** (`anim_preview.py`):
  `docs/anim_preview/<id>_<clip>_1x.gif`, `_3x.gif`, `_compare_3x.gif` (the sheets at
  `OLD_REF` beside the new frames, the moments labelled), `<id>_idle_views_3x.gif`,
  `<id>_run_views_3x.gif` and `<id>_contact_sheet.png`. Without `CLIPS` it shows the idle,
  the run and every move with an `anim_at`, timed from the JSON. Use `--out` for a look
  that shouldn't land in `docs/`.
- **`python3 tools/anim_preview.py --check <id>`** (or `all`): the JSON's row table against
  `ROWS` / `VIEW_ROWS` (names, frame counts, columns), the sheet PNG sizes, idle and run
  cycles against `ANIM_CYCLES`, `step_frames`, every move's `anim_at` / `anim_charge` /
  `anim_from` / `anim_reel` frame, the dodge block's `anim_at`, `cut_in_frame`. Run it before a fighter's sheets and
  JSON change. `--selftest` runs the tools' own checks (tween, lag, lag_at, the check on
  toy data); there is no Python test runner in CI.

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `anim_preview.py` — Animation previews and the timeline check, shared by every sprite generator.
- `build_tiles.gd` — Builds the Godot TileSets and the tiled arenas' ground scenes from a cut set's manifest (assets/tiles/<set>_manifest.js…
- `build_vfx.gd` — Builds the SpriteFrames and MoveFx resources from assets/vfx/manifest.json (written by tools/cut_vfx.py from kiddolink'…
- `codebase_map.py` — Writes the generated file lists and checks the codebase map for drift.
- `cut_tiles.py` — Cuts a tile set for the tiled arenas out of the bought art packs, from a recipe.
- `cut_vfx.py` — Cuts the effects the game plays out of kiddolink's VFX Complete Set Season 1 (bought; the pack never enters this public…
- `gen_arenas.py` — Arena art: each map's whole backdrop as one picture, drawn by ArenaView under the floor's cracks, holes and pieces.
- `gen_audio.py` — Generate PLACEHOLDER sound effects and music for Ready 4 Rambles.
- `gen_barkley.py` — Barkley sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_cairn.py` — Cairn sprite sheets: a boxer made of stacked river stones, drawn as a posed 3D rig.
- `gen_cerebro.py` — Chef Cerebro sprite sheets: a floating brain who throws his kitchen with his mind.
- `gen_craglash.py` — Craglash sprite sheet, a pixel-art recreation of the artist's character sheet.
- `gen_crease.py` — Mister Crease sprite sheets: a pixel-art take on the concept art (an origami magician).
- `gen_culvert.py` — Culvert sprite sheets: the storm-drain toad, drawn as a posed 3D rig.
- `gen_digby.py` — Digby sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_dummy.py` — Training dummy sprite sheets: a stuffed sack on a spring stand, drawn as a posed 3D rig.
- `gen_gillbert.py` — Gillbert sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_hissy.py` — Hissy Fitz sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_logo.py` — The title wordmark: READY 4 / RAMBLES in the m5x7 pixel font, scaled up by whole pixels, filled with hard-edged gold ba…
- `gen_pete.py` — Sneaky Pete sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_sno.py` — Sno Mercy sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_sprites.py` — Generate the small placeholder sheets for Ready 4 Rambles: floor tiles, the crowd, effects.
- `import_frames.py` — Imports a folder of PNG frames (PixelLab's output, or any artist's) as one of the game's sprite sheets: quantized to th…
- `odin_perf.py` — Measure frame pacing on an Android device (the AYN Odin 3) over adb.
- `palette.py` — The master palette: one published set of colours for every fighter and arena.
- `seed_dressing.gd` — Seeds a map's hand-dressing scene (assets/arenas/<id>_dressing.tscn) from a first-draft spec, tools/dressing/<id>.json.
- `shade2d.py` — Master-palette shading for the 2D painters (Barkley's and Gillbert's rigs).
- `splat3d.py` — Shared renderer for the sheet-recreation sprite generators (tools/gen_digby.py and later).
- `write_status.py` — Stamps docs/STATUS.md with the time, branch and commit so a compaction never starts without a fresh marker.
<!-- END GENERATED -->
