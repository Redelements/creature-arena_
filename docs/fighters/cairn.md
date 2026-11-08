# Cairn

## Identity
- **Sheet type:** hand-drawn (Kevin's concept, `docs/fighters/cairn_concept.png`), cleaned to pixel art with SpriteCook, animated on our own rig
- **One-line concept:** Stacked-stone boxer with a moai head
- **Design owner:** Kevin (concept and implementation)
- **Status:** implemented; visual rework in progress (Nov 2026)

## Class contract
- Must never feel like: a stat check: wins by reading the foe (footsies, a counter, a guard break), never by tankiness or by reach

## Where the rest lives
- Numbers, moves, frame data, CPU routes: `data/creatures/cairn.json` (keys in `docs/MECHANICS.md`)
- The kit in words, the class and counterplay: `README.md`, "### Cairn"
- Sheets: `tools/gen_cairn.py`, layouts in `docs/SPRITES.md`

## Art notes
- Pose reference: `docs/fighters/cairn_concept.png` (Nov 2026, the official look): a moai head in profile (long nose, heavy brow), a red headband with two tails, rounded grey stones stacked into shoulders, chest, hips and pebble legs, red boxing gloves, a red cloth tied on the rear arm, thick black outlines
- Art status: rework on branch `cairn-rework`; the shipped sheets are still the old rig (round pale head, white-taped fists)
- Knockout: the gloves stay on their arms (Kevin, 2026-11-07)

## Open questions
-

## Changelog
- 2026-10-27 — created
- 2026-11-07 — visual rework to Kevin's hand-drawn concept
