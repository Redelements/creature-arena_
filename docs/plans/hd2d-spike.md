# HD-2D spike: Digby on Stadium

Branch `spike/hd2d`. An isolated Godot 4.7 mini-project under `spike/hd2d/` (Forward+) that
puts the real Stadium floor on a tilted 3D plane with Digby as a billboard, runs the real
`MatchSim`, and answers: would an HD-2D (Octopath-style) presentation work for Ready 4
Rambles, and what would it cost us? The main project is not touched.

## Current state

- Step: 0 (plan) written. Next: Step 1 (mini-project, floor, camera).
- Branch `spike/hd2d` from `origin/main` fa7724b. Nothing outside `spike/` and
  `docs/plans/` is modified.
- Checkpoint for a resume: this file; `spike/hd2d/CHECKPOINT.md` only if a run had to stop early.

## Summary for the team

(Filled in at the end of Step 6.)

## Facts the spike is built on (from the read-first list)

- Sim units: the Stadium floor is `GRID_COLS * CELL` x `GRID_ROWS * CELL` = 672 x 288 units
  at origin (`GRID_X`, `GRID_Y`) = (16, 64); stands sit 64 units above the floor's top edge,
  a 14-unit front wall below. The screen draws 2 px a unit (`ArtScale`), so the floor picture
  is 1344 x 576 px and a 32 px Szadi tile is 16 units (two 8-unit cells). The sim ticks at 60.
- `assets/arenas/stadium.tscn` (TileMapLayers Ground/Grass/Water/Pieces + Brush/Rubble/Walls/
  Decor/Anim) references `assets/tiles/set1_ground.tres` and `stadium_dressing.tscn`, which
  adds `set1_cells.tres`; the two tilesets use `set1_ground.png`, `set1_pieces.png`,
  `set1_scatter.png`. `ArenaView._build_tiles` instances the scene at (GRID_X, GRID_Y) scaled
  by `ArtScale.scale_of(2)` (0.5), so tile pixels are half-units.
- Stands/backdrop art: `assets/sprites/arena_stadium_{sky,far,hang,fore}.png` (1504 px wide),
  `arena_stadium.png` (the old whole picture), `crowd.png` (`BackdropView`, `CrowdView`).
- Digby's sheets (`data/creatures/digby.json` `sprite`): grid sheets `assets/sprites/digby_2x.png`
  (side, 256 x 256 frames, 12 columns, 15 rows, origin [128, 200]), `_down` / `_up` (224 x 256,
  origin [112, 200] / [112, 180]), `_down_side` / `_up_side` (256 x 256, origin [128, 200] /
  [128, 180]); each with `_n` (normal) and `_e` (emissive) sheets. `ppu` 2: one sheet pixel is
  half a unit. The game loads the packed copies (`assets/sprites/packed/`), the spike uses the
  grid sheets directly (a plain `Sprite3D` with `hframes`/`vframes`), so no `PackedSheet` port.
- Anims: `anims.<name> = [row, first column, count]`; `idle_ticks` 8, `run_ticks` 2;
  `CreatureView._pick()` maps state to `[anim, frame, loops]`, `pick_view(facing, views)`
  picks the sheet by 8 sectors of 45 degrees (`TAN_22`/`TAN_67`), `flip_h` for facing.x < 0.
- `tools/splat3d.py` `Cam`: not a real camera. Each view is a cheated orthographic projection
  (`P`: side `x = fwd - 0.5 lat`, `y = -up + 0.18 lat + 0.06 fwd`; down/up `y = -up +/- depth_y(fwd)`
  with the floor depth flattened by `depth_y`; the diagonals rotate the floor 45 degrees) plus a
  `cam` vector for lighting (`screen_dir`). There is no pitch parameter: "pitch" for the re-render
  means a real elevation term, `y = -up * cos(p) + floor_depth * sin(p)` where floor_depth is the
  toward-camera floor axis of that view, replacing the flattening of `depth_y` (side view: the
  `0.18 lat` shear is its stand-in today).
- The sim (`src/sim/`) depends only on `SimDefs`, its own classes, `MatchFactory` (`src/game/`,
  reads `data/creatures/<id>.json`), `data/rules/*.json`, `data/arenas/*.json`. The CPU
  (`src/ai/`) adds `PlayerInput` (`src/input/`, which reads `InputMap` actions from
  project.godot's `[input]` section), `NavGrid`, `TeamIntent`, `Vision`, `RandomNumberGenerator`.
- Stadium light: `light.dir` [0.25, 1.0], shadow `length` 0.38 (short, nearly straight down),
  sun colour #f4f6ff energy 0.6; grade tint #f2f5ff, vignette 0.22.
- Godot on this machine: `C:\Users\Kevin\dev\godot\Godot_v4.7.2-stable_win64_console.exe`;
  Python with Pillow + numpy: `C:\Users\Kevin\dev\python\python.exe`. Forward+ needs a window
  (Vulkan), so screenshots run windowed, not `--headless`.

## Steps

### Step 1 — mini-project, floor and camera (Sonnet)
- `spike/hd2d/project.godot`: Godot 4.7, Forward+ (`renderer/rendering_method="forward_plus"`),
  1920 x 1080 window, the main project's `[input]` section copied so `PlayerInput` works.
- Mirror the main layout under `spike/hd2d/` so copied `res://` paths resolve unchanged:
  `assets/arenas/stadium.tscn` + `stadium_dressing.tscn`, `assets/tiles/set1_{ground,cells}.tres`
  + the three PNGs, Digby's 15 grid sheets, the stadium backdrop PNGs + `crowd.png`,
  `data/arenas/stadium.json`, `data/creatures/digby.json` + `dummy.json`, `data/rules/*.json`.
  `src/sim/` copied (symlinks need a privilege on Windows; copy and log it), plus
  `src/game/match_factory.gd`, `src/ai/`, `src/input/player_input.gd` (+ whatever those need to
  parse; `tools/build_tiles.gd` is not needed, the scenes are already built).
- `scenes/spike.tscn`: a `SubViewport` 1344 x 576, nearest filter, transparent off, holding the
  stadium scene at scale 0.5 (as `_build_tiles`); its texture on a horizontal `PlaneMesh`
  672 x 288 world units centred on the floor's centre, sim x -> x, sim y -> z (the stands at
  -z, the front edge at +z), unshaded off so lights hit it. Vertical quads behind the far edge
  for sky/far/hang/fore in their 2D stacking order.
- `Camera3D` pitched 35 degrees down, FOV 30, auto-framed so the floor fills the view. Keys:
  `O` orthographic toggle, `P` cycles pitch 25/35/45, `H` prints the key list.

### Step 2 — environment (Sonnet)
- `WorldEnvironment`: glow on, SSAO on, ACES tonemap, ambient from `grade.tint`; `CameraAttributesPractical` with DOF far on the stands; `DirectionalLight3D` with shadows, direction from `light.dir` + `length`; two warm `OmniLight3D`s at the floodlight posts.
- Keys `1` glow, `2` SSAO, `3` DOF, `4` shadows (the mobile-profile test), `M` all four off/on.

### Step 3 — Digby (Sonnet)
- `Sprite3D`, `FIXED_Y` billboard, `ALPHA_CUT_DISCARD` (casts shadows), nearest filter,
  `pixel_size` 0.5 (ppu 2 -> 1 sheet px = 0.5 unit, so Digby keeps his size against the floor),
  offset so the sheet origin sits at the sprite's base.
- `src/fighter3d.gd`: `pick_view` and `_pick` ported from `creature_view.gd`; the facing is
  first expressed relative to the camera's floor-projected forward (camera yaw 0 -> identity).
- `src/spike.gd` driver: `MatchFactory.versus("digby", "digby")`, P2 a `CpuController`
  (Normal); P1 keyboard through `PlayerInput` if it runs without `main.gd`, else CPU vs CPU
  (logged). Stepped at 60 Hz in `_physics_process`; sprite at `(pos.x, air_height(), pos.y)`.

### Step 4 — the real test
- 4a (Sonnet) `spike/hd2d/tools/gen_digby_pitched.py`: the generator with a `PITCH` (degrees)
  parameter added to a copied `Cam`, writes the five views + `_n` + `_e` at the same frame
  sizes and origins to `spike/hd2d/assets/sprites/pitched/`. Key `R` swaps sheets live.
- 4b (main session) normal-mapped fighter: `QuadMesh` + `ShaderMaterial` sampling albedo /
  `_n` / `_e` by frame index, lit by the `DirectionalLight3D`; key `N` toggles Sprite3D / quad.
  Time box ~2 h of agent work; over it -> stretch, logged.
- 4c (Sonnet) height preview: three `BoxMesh`es with a keeps wall tile, one sunken quad as a
  chasm. Key `T` shows/hides them.

### Step 5 — QC (Haiku runs, main session fixes)
The list from the brief; results logged below under "QC results".

### Step 6 — evidence (Haiku captures)
Key `F12` writes `spike/hd2d/shots/<name>.png`; CLI `--shots=a,b,c,d` runs the four captures
and the 10 s frame-time averages unattended. `current.png` from the main project's training
mode (Digby, Stadium) for the side by side.

## Go / no-go checklist

| Item | Result |
| --- | --- |
| Fighter readability (silhouette, facing, frame changes at 35 degrees) | |
| Floor circles / pit readability under tilt | |
| Tile seams at the floor edges | |
| Perf: frame time full post vs mobile profile | |
| Shadow lands under the sprite | |
| Determinism unchanged (600 ticks twice) | |

## What a go commits us to

- **Forward+ on desktop.** The main project is GL Compatibility (`project.godot`); glow, SSAO,
  DOF and shadow-casting billboards need Forward+ (or Mobile). Every view shader
  (`flash.gdshader`, `bloom.gdshader`, the 2D lights) is re-checked on the new renderer; the
  CI determinism run is unaffected (the sim never touches the renderer) but `tests/test_vram.gd`
  budgets and `--print-vram` move.
- **Replacing `bloom_view` / `grade_view` / `weather_view` with a `WorldEnvironment`.** Glow,
  tonemap and the per-arena tint become environment settings driven by the same JSON keys
  (`grade`, `light`, weather.json); rain/fog/snow become 3D particles or a screen-space pass.
- **Porting or viewport-projecting `fx_view._draw()`.** Everything drawn on the floor today
  (range rings, zones, shrines, flags, the caravan track, hit sparks, smears) is a 2D `_draw`.
  Two routes: draw it into the floor SubViewport (floor-locked effects project for free, but
  anything that should stand up, like a smear, lies flat) or port each effect to 3D. Likely both:
  floor layer in the viewport, airborne effects as billboards.
- **Mouse aim via a floor-plane raycast.** `PlayerInput` turns the cursor into a world point
  with the 2D camera; in 3D it is `Camera3D.project_ray_origin/normal` intersected with the
  y = 0 plane, then into sim units. Touch and gamepad are unchanged (no screen point).
- **Re-rendering the roster at the new angle.** Every fighter's five views (and the 2D painters,
  Barkley and Gillbert) re-rendered with the pitched `Cam`; the diagonal views' 45-degree floor
  turn and `depth_y` flattening must agree with the real camera. Portraits and `select_scale`
  re-checked.
- **A stripped mobile profile for Google Play.** Mobile renderer, no SSAO, no DOF, glow maybe,
  shadows at low resolution or baked; the spike's keys 1-4 are that profile's test. The Odin
  holds 120 Hz today on GL; that is re-measured.
- Not in the brief but implied: `main_camera.gd` (lead, clash, settle), the HUD's world-anchored
  pointers, the arena intro, and every `tests/test_*.gd` that reads `CreatureView` positions.

## Decisions

- D0. `docs/autonomy-log.md` is not written: the brief forbids changes outside `spike/` and
  `docs/plans/`, so this file is the run log the `autonomous-complete` skill asks for.
  The start tag `autonomy-start-20261030-*` is local only.
- D1. `git fetch`/`push` to GitHub are the only network calls (the push is required by the brief).
- D2. The grid sheets (`digby_2x*.png`) are copied, not the packed ones: a `Sprite3D` needs a
  grid texture and `PackedSheet` is a 2D-only `Texture2D`.
- D3. `src/sim/` is copied, not symlinked (Windows symlinks need Developer Mode; a copy is
  what the brief allows when symlinks break import). The copy is verified identical by `diff`.
- D4. "MatchFactory.training, Digby vs CPU Digby": training gives Digby vs the dummy, so the
  driver uses `MatchFactory.versus("digby", "digby")` with a `CpuController` on P2 (a training
  flag has no bearing on the view). If `src/ai/` does not run standalone, P2 stands idle.

## QC results

(Step 5.)

## Evidence

(Step 6: shots, frame times.)

## Incomplete / stretch

(none yet)
