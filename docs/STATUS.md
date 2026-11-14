# Status: handoff snapshot

Stamped: 2026-11-14 08:20 UTC
Branch: craglash-cutout (from main @ a49edb1)
Trigger: phase end

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Current state

Craglash has a new look: a skeleton cut from five stills Kevin supplied (decisions 2026-11-14,
plan and limits in `docs/plans/craglash-cutout.md`). `tools/gen_craglash_cutout.py` draws every
row of all five views; `tools/gen_craglash.py` is the pose source only.

Done:
- Stills converted to game size and the master palette (`assets/sprites/source/craglash_cutout/`).
- Cuts follow the art's lines (watershed from seeds); skeleton as Kevin drew it (spine, collar,
  shoulder line, a joint per neck stone); he approved the skeleton, the side idle and the Rake.
- Rake and backhand hit with a full lunge and an extended arm; clean-up pass on every frame.
- All rows, all views, Mountain Maw's head and slab rows, normals from the painted shading, eye
  glow on the Surge row. `craglash.json` fx_top / portrait / neck_end; NET_VERSION 78.
- Checks: `--check` (each view's idle 0 is its still), no frame in pieces or on a frame edge,
  packed sheets verified, `anim_preview --check craglash`, showcases craglash and angles and a
  smoke run without script errors. Full suite: only the two progression tests that need a
  network failed in the cloud session.

Next:
1. Kevin reviews the other four views and the side rows beyond idle and the Rake (review sheets
   and GIFs were sent in chat); fix what he sends back.
2. Server rebuild after merge (NET 78).
3. Owners' ruling on AI-made stills before release.

Commands: `python3 tools/gen_craglash_cutout.py --views all --check --rows <rows>`, then
`python3 tools/pack_sheets.py craglash` and `--import`. `--parts` rewrites the part PNGs and
`skeleton-<view>.png`; `--keys` prints the JSON keys; `--scan <rows>` lists turns per frame.
