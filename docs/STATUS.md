# Status: handoff snapshot

Stamped: 2026-10-27 20:06 UTC
Branch: crease-2x @ a6911e6
Trigger: phase

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Phase

Fighters at 2x density, **route A** (our own rig renders at 2 art px per 1x px). Pilot on
branch `crease-2x` (worktree `C:/Users/Kevin/dev/creature-arena-crease-2x`, off main cb968ed).
Local commits only: **never push, never merge** until Kevin decides.

Done (commit a6911e6 and after):

1. `tools/splat3d.py`: `configure(..., density=2)`. Scale and near zone x2, sample step /2,
   thresholds counted in pixels x2 through `S.px()` (seam and rim depths, normal blur, rim
   width; despeckle twice the passes). Outline stays 1 px, palette unchanged. At density 1
   every sheet is byte for byte as before (Crease 1x regenerated identically).
2. `tools/gen_crease.py`: `CREASE_DENSITY` (default 2; 1 rebuilds the 1x `crease*.png`, kept)
   and `CREASE_STYLE=a|bold` (bold default at 2x). Sheets `assets/sprites/crease_2x*.png`:
   side, down, up, down_side, up_side + `_n` + `_e` (side, down, down_side; the up views have
   no glow). 192 px frames, feet (96, 144), up views (96, 128); same rows, counts, timing.
3. Shading: tried (a) the 1x paper rules at 2x and (b) **bold**: three flat tones a face, a
   fold line only between faces of one tone, one dark ink (`INKS["ink"]`) round the whole
   silhouette. Shipped (b): (a)'s thin, material-coloured outline let the blue suit sink into
   dark ground at play zoom.
4. `data/creatures/crease.json`: every view `ppu` 2, frame 192, origin x2, portrait
   `[74, 70, 48, 64]`, `ko_fx` pieces x2, emissive paths. **NET_VERSION 46** (pilot; data_hash).
   sim-check unchanged `7a961fba…a8bf`. Full suite green after the art_scale pin fix.
5. `tools/anim_preview.py --compare <id> -|NEW.sprite.json [OUT] --old REF` (from the spike)
   and density-aware compare GIFs. Local `main` is stale: pass `--old cb968ed`.
6. Lighting High, Floodgate night, `--mode=48`: the 2x normal sheet lights correctly.

Gallery: `docs/pixellab/crease_route_a.png` (1x vs 2x for idle, run, flick, Surge at 1x/3x;
the two shading variants; Twin Keeps still beside the big tree at play zoom). GIFs:
`docs/pixellab/crease_route_a_{idle,run,flick}.gif`. Build for Kevin:
`C:/Users/Kevin/Downloads/Ready4Rambles-windows-crease-2x/` (exe + the gallery and GIFs).

## Decisions

- Route A is the fighter route. PixelLab animation (branch `crease-2x-spike`) was rejected:
  smeared edges, shapes wobbling between frames, invented props, no added detail.
- 2x defaults: density 2, bold shading, 1 px outline, step halved, `S.px()` thresholds.
- One NET_VERSION bump per PR; stacked PRs renumber on merge.

## Gate

**No fighter is rendered until Kevin says "run <fighter>" or "run all".** Then follow
`.claude/skills/fighter-2x/SKILL.md`, one fighter per branch `<fighter>-2x`, stacked off
`crease-2x`, in the order of `docs/plans/roster-2x.md`; stop at the first fighter that fails
its checks (anim_preview --check, tests, sim-check, VRAM budget).

## Open questions

- Kevin's verdict on the 2x Crease from the build (bold vs the 1x look; slimmer outline).
- Painter and custom renderers (Barkley, Gillbert, Craglash, Cairn, dummy, Cerebro, Hissy)
  need their own density switch before they can run (see the plan).

## Next step

Wait for Kevin's verdict and a "run <fighter>" / "run all"; then the skill, plan order.

## Files touched this session

tools/splat3d.py, tools/gen_crease.py, tools/anim_preview.py, tools/CLAUDE.md, docs/SPRITES.md,
data/creatures/crease.json, src/net/netplay.gd, tests/test_art_scale.gd,
assets/sprites/crease_2x*.png(+.import), docs/crease_2x_preview.png,
docs/crease_2x_views_preview.png, docs/pixellab/crease_route_a*, docs/STATUS.md,
.claude/skills/fighter-2x/SKILL.md, tools/twin_keeps_still.py, docs/plans/roster-2x.md.

Tooling: Godot `C:/Users/Kevin/dev/godot/Godot_v4.7.2-stable_win64_console.exe`; Python
`C:/Users/Kevin/dev/python/python.exe -I`; APPDATA for Godot runs
`C:/Users/Kevin/AppData/Local/Temp/claude/appdata_crease`. Crease 2x render: ~10 min.

## Context readings

| When | Reading |
|------|---------|
| (fill in) | |
