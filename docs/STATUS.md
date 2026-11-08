# Status: handoff snapshot

Stamped: 2026-11-08
Branch: codex/cairn-cutout-animation (same HEAD line as `cairn-rework`'s successor; base f91d274), local commits only, nothing pushed
Trigger: Kevin's Cairn redesign; cut-out animation of his approved stills

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Current state

Cairn's look is five approved stills (`assets/sprites/source/cairn_cutout/`), animated as a
cut-out (decision 2026-11-08, `docs/SPRITES.md` "Cut-out"). The rig `tools/gen_cairn.py` is only
the pose source; it does not draw the sheets.

Done:
- Idle frame 0 rebuilds the still exactly in all five views (`tools/test_cairn_cutout.py`, 6 checks pass).
  The old failures were the renderer's placement (rounded pivots) and hidden fills that weren't
  limited to areas under later parts; the test's premise was right.
- Side view `idle` (8) and `jab` (8) are drawn from the parts and live in `cairn_2x.png` / `_n`
  (flat normals; emissive empty), packed, imported. Every other row and the four other views are
  still the OLD stacked-stones sheets (he changes look between rows; expected, temporary).
- Jab glove centre vs the rig: the MOVEMENT from idle 0 is within 0.5 px on every frame; the
  absolute position sits (-5.5, -10.5) px off because the still's guard is tighter and its body
  slimmer than the rig's.
- Arm: two-bone solve (shoulder and glove from the rig, painted bone lengths, elbow below);
  upper arm and forearm rotate, everything else is whole-pixel translation.

Next (Kevin to judge first):
1. His verdict on the idle/jab feel (GIFs in the session scratchpad `cairn/cutout/`, Windows build in
   `Downloads/CreatureArena-windows-cairn-rework/`).
2. Then the other rows of the side view (power, hook, heavy, hurt, guard, ko ...), then the four
   other views. KO needs the old `ko_fx` slices re-measured (`gen_cairn.py kofx` is rig-based).
3. Open: a second painted head for blinks/fidgets (idle has no blink), how much arm rotation reads
   well, the cloth wrap on the forearm (it turns with the forearm), the far arm's hidden stub.

Commands: see `tools/CLAUDE.md` (cut-out bullet) for the sys.path wrapper; `--live` rebuilds the
side sheets, then `pack_sheets.py cairn`, `--import`.
