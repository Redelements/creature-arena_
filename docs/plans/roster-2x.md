# Roster at 2x density (route A)

Mister Crease is the pilot (branch `crease-2x`, `docs/pixellab/crease_route_a.png`). This plan
takes the other nine fighters (and the training dummy) to 2x the same way: our own rigs
rendered at density 2, bold shading, through the **fighter-2x** skill
(`.claude/skills/fighter-2x/SKILL.md`). PixelLab animation was tried and rejected
(`crease-2x-spike`); nothing here uses generative tools.

**Gate:** nothing below is rendered until Kevin says "run <fighter>" or "run all".

Every rig renders all five sheets itself (side, down, up, down_side, up_side; the CLAUDE.md
rule of three sheets plus the diagonals), so no rotation tool is needed at any step.

## The order (easiest first; fewest rows breaks ties)

Rows and frames from each `data/creatures/<id>.json` `sprite.anims`; every fighter has the
four extra views. Frames at 1x -> 2x. VRAM is the fighter's sheets as Godot holds them
today: colour sheets lossless (RGBA8, 4 B/px), normal and emissive sheets VRAM-compressed
(about 1 B/px); 2x is four times that. Render time: Crease took 2 min at 1x and about 10 min
at 2x (five sheets with normals), so roughly 5x a generator's 1x time.

| # | Fighter | Generator / renderer | Density option | Rows / frames | Frames 1x -> 2x | VRAM 1x -> 2x | Render 2x |
|---|---------|----------------------|----------------|---------------|-----------------|---------------|-----------|
| 1 | Culvert | `gen_culvert.py`, splat3d | covered: add `CULVERT_DENSITY` + `_frame()` | 14 / 118 | 96 -> 192 | 42 -> 167 MB | ~8 min |
| 2 | Sno Mercy | `gen_sno.py`, splat3d | covered (no decorate) | 15 / 126 | 128 (views 112x128) -> 256 | 80 -> 321 MB | ~10 min |
| 3 | Cairn | `gen_cairn.py`, splat3d, rigid stones | covered | 15 / 130 | 96 -> 192 | 44 -> 177 MB | ~8 min |
| 4 | Digby | `gen_digby.py`, splat3d | covered (no decorate) | 15 / 130 | 128 (112x128) -> 256 | 80 -> 321 MB | ~10 min |
| 5 | Sneaky Pete | `gen_pete.py`, splat3d | covered (no decorate) | 15 / 130 | 128 (112x128) -> 256 | 78 -> 311 MB | ~10 min |
| 6 | Hissy Fitz | `gen_hissy.py`, own rasteriser + `S.shade`/`S.outline` | **needs work**: its own `SCALE`/`STEP`/near | 15 / 126 | 128 (112x128) -> 256 | 71 -> 284 MB | ~12 min |
| 7 | Chef Cerebro | `gen_cerebro.py`, own rasteriser + gyri, decals, glow, smears, flash | **needs work**: own `SCALE`/`STEP`, painted strokes in px | 15 / 130 | 128 (112x128) -> 256 | 76 -> 304 MB | ~12 min |
| 8 | Barkley | `gen_barkley.py`, shade2d painter | **needs work**: `shade2d.py` has no density; shapes painted at pixel coordinates | 15 / 132 | 96, views 128x160 -> 192, 256x320 | 88 -> 353 MB | ~10 min |
| 9 | Gillbert | `gen_gillbert.py`, shade2d painter | **needs work**: as Barkley | 15 / 136 | 128, views 96x144 / 128x144 -> 256, 192x288 / 256x288 | 105 -> 421 MB | ~10 min |
| 10 | Craglash | `gen_craglash.py`, custom 2D shader (`VRig`, `DRig`, `_with_normals`) | **needs work**: the largest; every draw in pixel units | 16 / 136 | 96, views 128x160 -> 192, 256x320 | 95 -> 378 MB | ~15 min |
| note | Training dummy | `gen_dummy.py`, splat3d | covered | 6 / 32 | 96 -> 192 | 11 -> 42 MB | ~3 min |

"Covered" means the generator calls `S.configure` and `S.write_sheets`, so the density option
in `tools/splat3d.py` applies once the generator adds its env var and doubles `SIDE`/`VIEWS`
(the skill's step 0, as `gen_crease.py` does). Hissy and Cerebro keep their own copies of the
rasteriser (they still call `S.shade`/`S.outline`, which already read the density); Barkley and
Gillbert paint 2D shapes through `tools/shade2d.py`; Craglash draws per pixel in his own shader.
For those five the density option is its own PR before the fighter can run; the skill stops
there. Biggest jobs: **Craglash** (custom renderer) and the **shade2d pair** (one `shade2d`
density option serves both).

## Per fighter: what needs care at 2x

- **Culvert:** concrete grain flecks are hashed per pixel (`decorate`): at 2x they halve in
  size; hash on 2x2 blocks (`S.px`) so the grain reads the same. Emissive eyes (`min_level`
  2). `ko_fx` "crack" keys are world units (unchanged).
- **Sno:** syrup and the Surge's blast glow (emissive sheets on most rows); `ko_fx` "melt"
  is drawn by FxView (unchanged).
- **Cairn:** `ko_fx` "scatter" `pieces` are sheet-pixel bands: `tools/sprite_2x.py` doubles
  them (as for Crease). Face and grain come from stone-local coordinates (scale with density).
- **Digby, Pete:** plain rigs; Pete's bag and Digby's claws are rig pieces. Check `cut_in_frame`
  stays a [row, col] index.
- **Hissy:** painted face texture and snake-hair eyes (`face_px`, `eye_px`) in pixel units.
- **Cerebro:** painted gyri, glow rays, motion smears and the flash burst (`flash_burst`,
  `smears`) are drawn in pixels: each needs `S.px()`; tool outlines (`outline_mats`).
- **Barkley:** `ko_fx` "timber" `length` (FxView's falling trunk) is world units; tall
  128x160 views. Leaves are painted shapes: their size must double, not their count.
- **Gillbert:** the rod trails off-frame in the diagonals (origin cheats in `VIEWS`); 2x
  view frames 192x288 and 256x288.
- **Craglash:** neck stones, the Rake and the Bedrock Surge glow; `ko_fx` "crumble".
- Every fighter: the Surge eyes (emissive, `S.surge_eyes`), `fx_top` (world units, keep),
  the HUD portrait (`sprite_2x.py` doubles it; `Hud._portrait_info` clamps it to
  `PORT_W * ppu`), the select screen (`select_scale` is divided by `ppu` already).

**256 px frames.** `CreatureView`, `Hud` (portrait and Surge cut-in) and the select screen
read the frame size from the JSON and divide by `ppu`; nothing assumes 96 or 128.
`tests/test_art_scale.gd` covers a 2x crop; add a 256 px case with the first 128 px fighter.
The largest 2x sheet (Craglash's views, 3072 x 5120) is under the 8192 px texture limit of the
Odin 3.

## VRAM: flag before more than two or three fighters

4v4 texture memory was about 790 MB after the normal sheets. Crease at 2x went from about 50 to
**201 MB**. Eight different fighters at 2x in a 4v4 (the eight largest) is about **2.7 GB**,
and the whole roster at 2x about 3.2 GB, against about 0.8 GB at 1x. That is too much for
the Odin 3 and heavy for desktop. Before fighter 3 runs, one of these must land (its own PR):

1. **Trim the frames** (largest saving, lossless): most of a 192/256 px frame is empty.
   Pack each sheet's frames tight with a per-frame offset table (an atlas plus offsets in the
   sprite block), or at least crop each row to its bounding box. Expected 2-3x saving.
2. **VRAM-compress the colour sheets** (BPTC on desktop, ASTC on Android: 4x saving): lossy;
   check that the 1 px outline and the flat tones survive (they may not at 4x4 blocks).
3. Dropping the 1x sheets saves build size only: once a JSON names the 2x sheets the 1x ones
   are never loaded.

This is a stop condition in the run protocol: a fighter that pushes a 4v4 past the agreed
budget stops the run.

## Run protocol (Kevin)

- One fighter per branch `<fighter>-2x`, PRs stacked: the first off `crease-2x`, each next off
  the previous fighter's branch.
- Each PR description carries the preview GIFs (`docs/pixellab/<id>/<id>_route_a_*.gif`) and
  the gallery with the Twin Keeps still, and says what to try in the build.
- NET_VERSION: one bump per PR; renumber as they merge.
- **Stop at the first fighter that fails a check** instead of continuing: `anim_preview.py
  --check`, the tests (`TEST_ONLY=views,art_scale,<id>,light2d`, then the full suite),
  `--sim-check=20261010` unchanged, the VRAM budget. Report and wait for Kevin.
