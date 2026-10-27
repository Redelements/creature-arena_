# Mister Crease

Origami paper magician. The team wants him to be a standout — treat polish and feel as a
priority, not just correctness.

## Identity
- **Sheet type:** Flying
- **One-line concept:** A folded-paper magician who shapes and throws origami constructs
- **Design owner:** artist (concept + moveset), Kevin (implementation)
- **Status:** implemented
- **Named in README, not in data:** the dodge is "Paper Plane"; the passive is "Paper Stock" (`sheets`)

## Class contract
- Must never feel like: a bruiser — low durability, wins through range, zoning and burst windows, and wins the plain brawl against an assassin that engages openly

## Where the rest lives
- Numbers, moves, frame data, CPU routes: `data/creatures/crease.json` (keys in `docs/MECHANICS.md`)
- The kit in words, the class and counterplay: `README.md`, "### Mister Crease"
- Sheets: `tools/gen_crease.py`, layouts in `docs/SPRITES.md`

## Art notes
- Pose reference: Szadi art "Fantasy Lands Warrior" (reference only; `docs/pixellab-spec.md`)
- Art status: generated

## Open questions
- Final moveset from the artist: the implemented kit came first; check it against the artist's doc
- What makes him "special" mechanically: Paper Stock (`sheets`: fold, then use) is in; is that it?

## Changelog
- 2026-10-27 — created from the decisions log (bundle), filled from the code
