# Art pipeline

## Scale and view
- Top-down. The sim works in units on 8-unit terrain cells; the screen draws 2 px a unit, so tiles are 32 px and
  fighter frames 96–128 px (`docs/plans/32px-migration.md`).
- Floor cracks and opens into pits from the terrain grid.
- Hits are circles on a flat floor.

## Licensed assets (do not swap without a decisions-log entry; full list and terms in `LICENSES.md`)
| Asset | Use | Licence |
|---|---|---|
| Szadi art — RPG Fantasy Worlds Set1 (32×32 painterly, from Halloween Sale 2026 RPG bundle) | Arena terrain (Stadium; other maps use other Szadi packs, `docs/asset-map.md`) | Commercial |
| kiddolink — VFX Complete Set Season 1 | Hit / skill VFX | Commercial |
| Szadi art — Fantasy Lands Warrior | The stadium crowd (`assets/sprites/crowd.png`); pose reference for fighters | Commercial |

## Fighter generation (own rig, route A)
- Tool: `tools/gen_<id>.py` per fighter, on the `tools/splat3d.py` rig (Barkley and Gillbert use the 2D painters
  with `tools/shade2d.py`). PixelLab was tried on Crease and dropped on 2026-10-27 (`docs/decisions.md`); the spike
  spec stays in `docs/pixellab-spec.md`.
- Style: master palette (`tools/palette.py`), chunky shading, drawn at 2 px a sim unit.
- Workflow:
  1. Artist supplies character concept + moveset (`docs/fighters/<name>.md`).
  2. Write or change the fighter's generator; it writes the side, down and up sheets (and diagonals, normals) to
     `assets/sprites/<id>*.png`, with layouts in `docs/SPRITES.md`.
  3. Point `sprite` in `data/creatures/<id>.json` at them (frame size, origin, `anims`, `views`), then re-import.
  4. If a frame is wrong, fix the generator and regenerate — do not hand-edit the PNG.
- Animation set per fighter: idle, run, one per move, dodge, hurt, guard, ko, victory (`docs/SPRITES.md`).

## Master palette
- The palette is code: `tools/palette.py` (the ramps, the inks, `snap` for pulling any colour onto it); the swatch
  is `docs/palette.png`.
- Rule for new colours: there aren't any. Every generator and cutter snaps to the palette; a new fighter picks
  ramps from it (`docs/SPRITES.md` "Palette" says how the ramps and inks are used). Adding a ramp is a decision
  for `docs/decisions.md` and touches every sheet.
