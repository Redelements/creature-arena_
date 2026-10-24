# tools: generators (not part of the game)

Godot ignores this folder (`.gdignore`). Run the scripts with Python 3 (Pillow and numpy for
sprites and audio). Each sprite generator writes `assets/sprites/<id>.png`, `<id>_down.png`,
`<id>_up.png` and a `docs/<id>_preview.png`; after regenerating, run `--import` or the game
keeps the old import cache. Sheet layouts: `docs/SPRITES.md`.

- `splat3d.py`: the shared renderer (pose a 3D rig, sample parts as points, splat per view,
  shade in three tones, outline). Prefer this shape for new fighters, like `gen_digby.py`:
  `build(pose, view)`, a palette, `ROWS` / `VIEW_ROWS`, pose functions;
  `python3 tools/gen_<id>.py inspect idle:0 run:2` previews frames.
- `gen_culvert.py`, `gen_digby.py`, `gen_pete.py`, `gen_sno.py`, `gen_crease.py`: splat3d rigs
  (Crease: faceted paper, 128x160 frames, `decorate` draws creases).
- `gen_cerebro.py`, `gen_hissy.py`: point-sampling rigs with their own copy of the splat code.
- `gen_barkley.py`, `gen_gillbert.py`, `gen_craglash.py`: older (Barkley/Gillbert project a
  3D rig per view; Craglash is a 2D IK puppet whose renderer rounds to whole pixels in
  `whole_pixels()`, so its poses may hold floats).
- `gen_sprites.py`: placeholders (Cairn, dummy, tiles, crowd). `gen_arenas.py`: each map's
  whole picture (stands on all sides: `_stands`, `_side_stands`, `_front_stands`, in step with
  `CrowdView`'s seats) plus its cracked and changed-piece floors (and `_crackmask`, the cracks
  alone, which the view lights as cracks spread and heal), the Caravan's wagon and the CTF flag (reads `data/arenas/<id>.json`;
  rerun after moving a piece or changing a map's `light`: pieces cast their shadows along it,
  `cast_shadows`, `CAST_HEIGHT`, kept in step with `ArenaView.CAST_HEIGHT` and `ShadowLayer.light_of`). `gen_audio.py`: placeholder
  SFX and music; names must match `data/audio.json`.
- `codebase_map.py`: writes the generated file list at the end of each area's `CLAUDE.md`;
  `--check` is the CI drift check. Standard library only.

Every character has three sheets with the same rows (side, facing down, facing up); all
generators draw all three. The diagonals (`down_side`, `up_side`: facing down-right and
up-right, `<id>_down_side.png`, `<id>_up_side.png`) are optional extra sheets: a splat3d
rig adds them to its `VIEWS` and the JSON's `"views"` (Pete, Culvert, Digby, Sno and Crease have them), and `Cam` projects
them; `write_sheets`, `inspect` and the `anim` previews draw every view in `VIEWS`. A
`build(pose, view)` branch on the view name (Pete's `_dollar`) needs a case for them.

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
- `codebase_map.py` — Writes the generated file lists and checks the codebase map for drift.
- `gen_arenas.py` — Arena art: each map's whole backdrop as one picture, drawn by ArenaView under the floor's cracks, holes and pieces.
- `gen_audio.py` — Generate PLACEHOLDER sound effects and music for Creature Arena.
- `gen_barkley.py` — Barkley sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_cerebro.py` — Chef Cerebro sprite sheets: a floating brain who throws his kitchen with his mind.
- `gen_craglash.py` — Craglash sprite sheet, a pixel-art recreation of the artist's character sheet.
- `gen_crease.py` — Mister Crease sprite sheets: a pixel-art take on the concept art (an origami magician).
- `gen_culvert.py` — Culvert sprite sheets: the storm-drain toad, drawn as a posed 3D rig.
- `gen_digby.py` — Digby sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_gillbert.py` — Gillbert sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_hissy.py` — Hissy Fitz sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_logo.py` — The title wordmark: CREATURE / ARENA in the m5x7 pixel font, scaled up by whole pixels, filled with hard-edged gold ban…
- `gen_pete.py` — Sneaky Pete sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_sno.py` — Sno Mercy sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_sprites.py` — Generate placeholder pixel-art sprite sheets for Creature Arena.
- `splat3d.py` — Shared renderer for the sheet-recreation sprite generators (tools/gen_digby.py and later).
<!-- END GENERATED -->
