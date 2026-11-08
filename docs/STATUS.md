# Status: handoff snapshot

Stamped: 2026-11-08
Branch: cairn-rework (PR pending)
Trigger: Cairn cut-out extended to every row and view

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Current state

Cairn's look is five approved stills (`assets/sprites/source/cairn_cutout/`), animated as a
cut-out (decisions 2026-11-08, `docs/SPRITES.md` "Cut-out"). The rig `tools/gen_cairn.py` is only
the pose source; it does not draw the sheets.

Done (Nov 8):
- Kevin approved the side idle + jab ("looks great") and asked for every animation in this style
  and the health bar lifted off his face.
- `fx_top` 44 -> 56 (the still is 54.5 units tall; the bar sat across his face). `ko_fx` bands and
  eye spot re-measured on the still; HUD `portrait` moved to the head. NET_VERSION 76 -> 77
  (`cairn.json` is in the data hash; no sim change).
- `tools/gen_cairn_cutout.py` now draws all 15 rows of all five views (`--views all --live`;
  `ko` side-only). New: head swings about the neck when the rig turns it 4 degrees or more
  (hurt, ko, idle_alt); arm bones stretch up to 1.3 before the glove is held back; a glove that
  travels past `GLOVE_SNAP` lands on the rig's absolute glove (the hit circle); gloves scale with
  depth toward the camera (`GLOVE_GROW`, 0.7..1.5); facing the camera or away the arm parts follow
  the rig's projection (`TRANSLATED_ARMS`); a part whose covering neighbour moves `REVEAL` px away
  takes its `_complete` image. `cairn_cutout_parts.py`: a glove box keeps no stone pixels.
- Clean-up pass (Kevin: after-image outline between animations, stones cut into squares): the
  hidden-surface fills are now ellipses fitted to each stone's visible pixels, shaded like the
  painted stones, ring-trimmed beside painted ink, alpha 254 so the renderer can ink the frame's
  outer edge once (`_fit_ellipse`, `_stone`, `CAPS` in `cairn_cutout_parts.py`).
- Idle 0 still rebuilds every still exactly; idle frames 1-7 match the approved sheet except a
  24 px far-glove fill on frames 2-3. Six cut-out checks pass; packed sheets verified;
  `anim_preview --check cairn` ok; showcase screenshots clean.
- Windows build for Kevin: `C:\Users\Kevin\Downloads\CreatureArena-windows-cairn-rework\CreatureArena.exe`.
  Review media: session scratchpad `cairn/cutout/review2/` (`<view>-sheet.png`, GIFs per row).

Next:
1. Kevin plays the build and judges every move in every direction; rulings wanted on the limits
   below.
2. Open the PR from `cairn-rework` (full suite + smoke were running at the stamp); server rebuild
   after merge (NET 77).
3. Known limits to put to Kevin: no blink / expression (one painted head per view: a second head
   still would give blinks and the x-eyes); a punch facing the camera is the glove growing and
   dropping toward the hips (the rig's camera); the knockout row lays the stones in a line (the
   game scatters him from idle 0 anyway); the far arm's painted reach is 27 px, so the cross and
   uppercut stretch the stones 1.3x and still stop short of the rig's glove by a few px.

Commands: `tools/CLAUDE.md` (cut-out bullet): the runpy wrapper, `--views all --live`, then
`pack_sheets.py cairn`, `--import`.
