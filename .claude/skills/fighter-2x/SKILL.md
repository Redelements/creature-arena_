---
name: fighter-2x
description: Re-renders one fighter's sheets at 2x density with our own rig (route A) and switches the game to them. Use for "render <fighter> at 2x", "fighter 2x", "roster 2x", "run <fighter>" after Kevin's go. One invocation per fighter name; never without Kevin's "run <fighter>" or "run all" (docs/STATUS.md, Gate).
---

# Fighter at 2x (route A)

Plan and order: `docs/plans/roster-2x.md`. Specs, not restated here: `docs/SPRITES.md`
(palette, outlines, views, normal/emissive sheets, Crease's 2x note) and
`docs/pixellab-spec.md` section 2 (frame, feet, `"ppu": 2`). Branch `<id>-2x`, stacked off the
previous fighter's branch (first: `crease-2x`). Python `python -I`, Godot as in `docs/STATUS.md`.

**Defaults that worked (Crease, Oct 27):** density 2 through `splat3d.configure(density=2)`
(scale x2, near x2, sample step halved, pixel thresholds through `S.px()`), outline 1 px,
palette unchanged, **bold** shading: three flat tones a face, one dark ink round the silhouette.

0. **Stop check.** The generator must have a density switch. splat3d rigs that call
   `S.configure` + `S.write_sheets` (culvert, cairn, dummy, digby, pete, sno): add an env var
   `<ID>_DENSITY` (default 2, `1` = the 1x sheets byte for byte), `_frame()` doubling `SIDE` /
   `VIEWS`, `density=` in `configure`, `S.px()` on any pixel constant in `decorate`, like
   `gen_crease.py`. Own rasterisers (cerebro, hissy: local `SCALE`/`STEP`), shade2d painters
   (barkley, gillbert) and custom renderers (craglash's `VRig`/`DRig`): if the generator or
   `tools/shade2d.py` has no density option yet, **stop and say so**; that is its own PR.
1. Hash the 1x sheets; `<ID>_DENSITY=1 python -I tools/gen_<id>.py`; hashes must not change.
2. Shading look: render idle:0 with the generator's look and a bold variant
   (`python -I tools/gen_<id>.py inspect idle:0`, `INSPECT_OUT=`), pick at play zoom, say why.
3. `python -I tools/gen_<id>.py` (density 2): `assets/sprites/<id>_2x[_view].png` + `_n` + `_e`
   for side, down, up, down_side, up_side (the rig renders every view; no rotation tool),
   frames and origins doubled; same rows, counts, timing. Keep the 1x files. Copy each 1x
   `_n`/`_e` `.import` onto the 2x one (VRAM-compressed, normal_map), keep its own uid, `--import`.
4. `python -I tools/sprite_2x.py <id>`: every view `ppu` 2, path `_2x`, frame/origin/portrait
   and `ko_fx` pieces doubled (idempotent; `--check`). Check `fx_top`, `cut_in_frame` and
   effect offsets in the JSON stay in world units.
5. `python -I tools/anim_preview.py --check <id>`;
   `python -I tools/anim_preview.py --compare <id> - docs/pixellab/<id> --old <main sha>`
   (local `main` may be stale: use the PR base's sha), keep idle/run/one move as
   `<id>_route_a_<anim>.gif`.
6. Twin Keeps shot (command in `tools/fighter_2x_gallery.py`'s docstring, teams without
   `<id>`), then `python -I tools/fighter_2x_gallery.py <id> --old <sha> --shot <png>
   --extra <variants png>` -> `docs/pixellab/<id>/<id>_route_a.png`, `<id>_twin_keeps.png`.
   Look at the shrunk pictures yourself.
7. Tests: `TEST_ONLY=views,art_scale,<id>,light2d`, then the full suite; fix pins on the
   fighter's frame or ppu. `--sim-check=20261010` must not change. Smoke `--mode=<its vs CPU>`;
   Floodgate `--time=night --lighting=high` shot for the normal sheet.
8. NET_VERSION +1 in `src/net/netplay.gd` ("<n>: <Fighter> at 2x density (sprite blocks,
   data_hash)"): one bump per PR; stacked PRs renumber on merge. `docs/SPRITES.md` note,
   `python -I tools/codebase_map.py --check`, `docs/STATUS.md` + `tools/write_status.py
   --trigger phase`. Commit; PR only when Kevin says.

**Don't:** animate with PixelLab (`animate-with-text-v3` / `animate-with-skeleton-v3` at 192 px
from a 2x-upscaled reference gave smeared edges, wobbling shapes, invented props, no added
detail; branch `crease-2x-spike`, `docs/pixellab-spec.md` section 10 there,
`docs/pixellab/crease_2x_*.gif`). Never animate a reference with generative tools. Don't upscale
1x sheets. Don't widen the outline past 1 px.

Verified: 2026-10-27, dry run on Crease: `CREASE_DENSITY=2 gen_crease.py` re-rendered all 13 sheets byte for byte
(git status clean); `sprite_2x.py crease` left the switched JSON unchanged, and on main's 1x JSON
produced the committed sprite block and `ko_fx` (emissive keys aside); the gallery script rebuilt the pilot gallery.
