# HD-2D spike: Digby on Stadium

Branch `spike/hd2d`. An isolated Godot 4.7 mini-project under `spike/hd2d/` (Forward+) that
puts the real Stadium floor on a tilted 3D plane with Digby as a billboard, runs the real
`MatchSim`, and answers: would an HD-2D (Octopath-style) presentation work for Ready 4
Rambles, and what would it cost us? The main project is not touched.

## Current state

- DONE (Oct 30 2026). All six steps built, QC'd and captured; branch `spike/hd2d` pushed, no PR.
  Nothing outside `spike/` and `docs/plans/` was modified. Run it: `Godot --path spike/hd2d`
  (Forward+, a window), `H` lists the keys; unattended flags are under Evidence.
- Verdict: see the summary. The spike proves the technical route (the sim untouched, the
  real tiles and sheets on a tilted floor, cheap on desktop); the open costs are the view port.

## Summary for the team

**What was built.** A standalone Godot 4.7 project at `spike/hd2d/` on Forward+: the real
Stadium tile scene rendered into a SubViewport and laid on a 3D floor plane (1 sim unit =
1 world unit), the stands/sky/roof/front-rail pictures as vertical planes behind and before
it, a 35-degree camera (FOV 30; orthographic and 25/45-degree pitches on keys), a
WorldEnvironment (ACES, glow, SSAO, far DOF on the stands, a DirectionalLight3D from the
map's `light` block with shadows, two warm omni lights), and Digby as a fixed-Y billboard
driven by the unmodified `MatchSim` (Digby vs a Normal CPU Digby, or keyboard P1 on the
Classic layout with mouse aim through a floor-plane raycast). On top: a normal-mapped quad
version of the fighter lit by the scene (`fighter_lit.gdshader`, key N), Digby's five
sheets re-rendered with the rig's camera pitched 35 degrees (key R), and a height preview
of keep-wall blocks and a chasm (key T). Screenshots: `spike/hd2d/shots/` (`a_perspective`,
`b_ortho`, `c_pitched`, `d_mobile`, `e_lit`, `f_height`, `a2_fight` / `c2_fight_pitched` /
`e2_fight_lit` framed on the fight, `current.png` from today's game).

**What held up.** Zero errors or warnings on every run. The sim stays deterministic with
the view attached (same digest over 600 ticks with and without syncing). Facing picks the
right sheet in all 8 sectors, frames advance through idle/run/attack/guard/hurt, Digby's
feet sit on the floor with a shadow under him, the floor is the right way round, no seams,
no z-fighting, no pink materials. Every toggle flips and back from code.

**What it looks like.** Framed on the fight (360 units wide, as the game's camera does)
Digby is as readable as today: same silhouette, crisp, with a soft contact shadow. The
pitched re-render reads as the same character seen from a little higher (more back and
tail, a rounder head); it is a taste call, not a fix the spike needed. The per-pixel lit
quad is indistinguishable from the Sprite3D under the Stadium's near-vertical sun (the
spike proves the plumbing, not the payoff: a lower sun or coloured omni lights would show
it). Framed on the whole floor the fighters are small (about 60 px tall at 1080p). The
floor under perspective loses pixel-perfection: its texels are no longer whole screen
pixels and shrink toward the far edge. A pit seen from 35 degrees shows only its far wall,
so the height preview's chasm reads as a flat dark patch; a real pit needs a lit far wall
and a true hole in the floor mesh. The sides of the floor end in black: the side stands
would have to be built as geometry or planes (today they are part of the 2D picture).

**Cost.** Desktop GPU time is a non-issue (RTX 4090 at 1080p: 0.39 ms a frame full post,
0.16 ms with glow/SSAO/DOF/shadows off; the lit quads cost nothing measurable). Mobile is
unmeasured; scaled by a typical phone GPU the full post would miss 60 fps and the stripped
profile might hold it. The real cost is the view port listed under "What a go commits us to":
Forward+ (every 2D shader and the 2D lights re-done), `fx_view._draw()` and every
floor-drawn effect (rings, zones, shrines, flags, tracks, sparks, smears) either projected
through the floor viewport or ported to 3D, the camera (lead/clash/settle), mouse aim,
weather, the HUD's world anchors, the arena intro, the side stands and the roof as 3D,
every map's walls and pits as geometry, the roster re-rendered (about 4 minutes a fighter
with the pitched rig; Barkley and Gillbert are 2D painters and need their own answer), and
a mobile profile. Estimate: weeks, not days, and it reopens the visual plan that just closed.

**Recommendation: no-go for the current release; keep the branch as a reference.** The
route works and nothing in the sim or data stands in its way, so it can be picked up later
as a presentation layer for a sequel or a big update. If the team wants the look now, the
next spike should be the expensive unknown, not more of this one: port the floor effects
(FxView) through the viewport on one busy mode (Capture the Flag on Twin Keeps) and the
2D camera's behaviour onto the Camera3D, then re-judge with a playtest.

**Decisions** are listed under "Decisions" below (D0-D13); **incomplete** items under
"Incomplete / stretch".

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
| Fighter readability (silhouette, facing, frame changes at 35 degrees) | PASS at the game's fight framing (`a2_fight.png`: 360 units wide); the whole-floor framing (`a_perspective.png`) is too small to fight in, as the 2D game's whole-floor view would be. Billboards stay upright and do not look like paper at 35 degrees; the pitched sheets are a taste call |
| Floor circles / pit readability under tilt | PARTIAL: the floor's own markings (worn patches, court lines) read well and sit in perspective for free; a pit shows only its far wall and the preview's reads as a flat patch (needs a lit far wall + a real hole). Range rings and zones were not drawn (they are FxView, not ported) |
| Tile seams at the floor edges | PASS (edge strips, 1:1) |
| Perf: full post vs mobile profile | PASS on desktop: GPU 0.39 ms vs 0.16 ms a frame at 1080p on an RTX 4090 (DOF 0.08, glow 0.06, SSAO 0.03, shadows 0.02 of it); frame rate is capped at 300 by the machine in both. Mobile not measured |
| Shadow lands under the sprite | PASS (soft, a little toward +x +z as `light.dir` says) |
| Determinism unchanged (600 ticks twice) | PASS (digest 6a7e528a with and without the view) |

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
- D5. The main `project.godot` has no `[input]` section (`Controls`, `src/game/controls.gd`,
  builds the InputMap in code), so the spike copies all of `src/input/`, `controls.gd` and
  `perf_log.gd` (needed by `PlayerInput` and `CpuController`) and calls Controls' setup from
  its own `_ready`. No stubs were needed in the end.
- D6. The Digby grid PNGs are import-skipped in the main project (`importer="skip"`, their
  `.import` files came with the copy), so `load()` cannot see them: `Fighter3D._tex` reads
  them with `Image.load_from_file` into an `ImageTexture`. Fine for a spike; the real game
  loads packed sheets.
- D7. Step 3's agent reported the R key wired; it was not (no `KEY_R` in spike.gd). Wired in
  Step 4b together with N, as `_apply_fighter_modes`.
- D8. The lit quad's pivot (frame centre to feet) is a shader uniform added in billboard
  space, not a node offset, so it would still be right at any camera yaw.
- D9. Step 4b took well under its 2 h box (the shader compiled first time; the Sprite3D and
  quad renders differ only at the fighters' pixels). With the Stadium's near-vertical sun
  (`light.length` 0.38) the per-pixel shading is subtle; a lower sun would show it more.
- D10. The Haiku capture of `current.png` first ran on the session's saved arena (Floodgate,
  rain, night); it was redone with `--arena=stadium --weather=clear --time=day` so the side
  by side is like for like.
- D11. A fight-framing camera (`--frame=W`, key Z, follows the two fighters' midpoint) was
  added beyond the brief: at the whole-floor framing the fighters are too small to judge
  readability, and the game's own camera frames the fight.
- D12. `--perf` reports `RenderingServer.viewport_get_measured_render_time_gpu/cpu` as well
  as wall clock, because the wall clock sits at a 300 fps cap on this machine.
- D13. The shots `qc_z1/qc_z2` (duplicates of `f_height` one tick apart) were not committed;
  the `.import` files Godot writes for shots are ignored.

## QC results (Step 5)

| Check | Result | How |
| --- | --- | --- |
| Scene loads with zero errors / warnings, no missing resources | PASS | every run's log grepped: 0 ERROR / SCRIPT ERROR / WARNING (only the Vulkan driver info line and Godot's own shutdown noise: "Unreferenced static string", "RID allocations leaked at exit") |
| Floor right-side up, not mirrored | PASS | the three worn-dirt patches sit on the row nearer the camera, the cobbled corners at the far edge (Step 1 shot; checked again in the Step 4b crop) |
| Digby's feet on the floor, no float / sink | PASS | Step 3 and 4b crops: feet on the dirt, shadow under him; the Sprite3D offset is `(half - origin)` with y up, the quad's pivot the same as a shader uniform |
| Facing: the right sheet in all 8 sectors | PASS | `--facing-test`: right/left side (flip for left), down-right / down-left down_side, up-right / up-left up_side, down, up |
| Frame index advances across idle / run / attack | PASS | `--anim-log`: idle frames 1, 2; attack 79, 87; guard 132; hurt 121 over 600 ticks |
| Shadow cast, lands under the sprite | PASS | a soft shadow under both fighters, a little toward +x +z as `light.dir` says; the quad casts too (`cull_disabled`, alpha scissor) |
| Every toggle flips and back without errors | PASS | `--toggle-test`: O, P x3, 1, 2, 3, 4, M, N, R, T each pressed through the key handler; 21 state lines, 0 errors |
| Sim deterministic, view does not leak | PASS | `--determinism`: 600 ticks twice, digest 6a7e528a both; again with the view synced on one run only: same digest |
| No pink materials | PASS | by eye on the Step 1, 3, 4b and 4c shots |
| No z-fighting floor vs chasm cover | PASS | two shots one tick apart (`--height`): 321 pixels differ, all in the fighters' box (x 1014-1145, y 485-557); 0 in the lower floor where the chasm cover sits |
| No tile seams at the floor edges | PASS | 1:1 strips of the left (x 37), right (x 1881), far (y 342) and near (y 651) edges: the dirt_edge band and the cobbled corners, no gaps or doubled lines; the floor ends in empty black at the sides because the spike has no side stands (set dressing, not a seam) |
| Pixel art under perspective | NOTE | the floor's 1344 px texture spans ~1844 screen px at the near edge and fewer at the far edge: texels are no longer whole screen pixels and vary in size up the floor (the current game draws at an integer scale). Expect shimmer on camera moves with nearest filtering; a go would need either a texel-snapped camera, linear filtering with a resolve, or accepting it as the HD-2D look (Octopath accepts it) |
| Chasm reads as a hole | KNOWN ISSUE | from a 35-degree camera on the near side only the far pit wall can show; the preview's pit walls are unshaded dark, so the pit reads as a flat dark patch. A real pit needs a lit far wall (and a true hole in the floor mesh), see go/no-go |

## Evidence

Shots in `spike/hd2d/shots/` (1920 x 1080, tick 300 of the seed-7 CPU match unless noted):

| File | What |
| --- | --- |
| `a_perspective.png` | (a) perspective, full post, whole floor |
| `a2_fight.png` | (a) framed 360 units on the fight (`--frame=360`, key Z) |
| `b_ortho.png` | (b) orthographic |
| `c_pitched.png`, `c2_fight_pitched.png` | (c) the re-rendered (pitched) sheets |
| `d_mobile.png` | (d) mobile profile: glow, SSAO, DOF, shadows off |
| `e_lit.png`, `e2_fight_lit.png` | the normal-mapped quad |
| `f_height.png` | the height preview (walls, pillar, step, chasm) |
| `current.png` | today's game: Training: Digby on the Stadium, clear day (3440 x 1440) |
| `step1_*`, `step2_*`, `step3_*`, `step4*` | the per-step checks |

Frame times (10 s of the match from tick 60, `--perf --disable-vsync`, RTX 4090, 1920 x 1080):

| Profile | Wall clock | GPU render | CPU render |
| --- | --- | --- | --- |
| Full post (a) | 3.33 ms a frame (300 fps, the machine's cap) | 0.39 ms | 0.09 ms |
| Mobile profile (d) | 3.33 ms (same cap) | 0.16 ms | 0.05 ms |
| Lit quads | 3.33 ms | 0.39 ms | 0.09 ms |
| Orthographic | 3.33 ms | 0.39 ms | 0.09 ms |
| Fight framing 360 | 3.33 ms | 0.41 ms | 0.09 ms |
| no glow / no SSAO / no DOF / no shadows | 3.33 ms | 0.33 / 0.36 / 0.31 / 0.37 ms | |

Unattended flags: `--cpu-vs-cpu --seed=N --run=TICKS --shot-at=TICK:NAME --perf --frame=W
--pitch=D --ortho --lit --pitched --height --mobile --no-glow --no-ssao --no-dof --no-shadows
--facing-test --determinism --anim-log --toggle-test`. A run quits after `--run` ticks or its
shot (Godot's `--quit-after` hangs this project).

## Incomplete / stretch

- Mobile frame time: not measured (no device run; the brief forbids touching the main project's
  export setup and the spike has no Android preset).
- Live keyboard play (P1 on the Classic layout) was wired but never pressed by a person; the
  key toggles were driven from code (`--toggle-test`).
- The chasm's far wall is unshaded, so the pit does not read as deep; the side stands are missing.
- Range rings, zones and every FxView effect: out of scope by the brief, and the biggest
  unknown of a go.
- Wall-clock frame rate is capped at 300 fps on this machine even with `--disable-vsync`
  (likely the driver); GPU render time was measured instead.
