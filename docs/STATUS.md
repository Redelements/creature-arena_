# Status: handoff snapshot

Stamped: 2026-10-30 (QA pass branch, before push)
Branch: qa/full-pass-2026-10-29 (from origin/main fa7724b, after #328)
Trigger: end of the autonomous QA run

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Current state

The autonomous QA pass (co-op / multiplayer modes + a general sweep) is on branch
`qa/full-pass-2026-10-29`, pushed for review, **no PR by Kevin's instruction**. The report is
`docs/qa/qa-report-2026-10-29.md` (findings, decisions, open questions, the hand-playtest
list); per-part notes beside it in `docs/qa/`.

What changed on the branch (behavioural, needs Kevin's review before merging):

- **Mode objects leaked between matches** (Part 1): after CTF / Caravan / Brawl the menu
  background and the next 1v1 kept drawing flags, shrine pads, the wagon and wanted marks.
  `FxView.clear()` now resets every mode array; a replay seek rebuilds the marks.
  `tests/test_mode_objects.gd` pins it (every offline mode's object set from the rules files).
- **Pit falls by footprint** (Part 2): a fighter falls, and a walk stops, only when half its
  body circle (nine fixed points) is over pit cells; `data/rules/falls.json` (`fall_fraction`
  0.5, `fall_radius_mult` 1.0; 0 = the old centre-point rule). Chasm vs hole decided by the
  footprint too; off-grid points clamped. Sim, walking guard, blinks and the CPU share one
  function. One-cell cracks are now walkable; 1-2 cell holes drop nobody. Fingerprint
  `--sim-check=20261010` is now `31bf3294…`. `tests/test_pit_footprint.gd`.
- **Twin Keeps**: the two mid-field wall pillars hidden under tree crowns (and the four trees
  on them) are gone; tile scene rebuilt. `tests/test_occluded_pieces.gd` pins every map.
- **NET_VERSION 76** (falls.json in data_hash, the Twin Keeps map): server rebuild after the
  merge (`/opt/creature-arena/update.sh`), plus the one still owed from #324.
- New tests: spawns (Part 5), local modes 55-62 (Part 6a), menus (Part 8); `tools/run_tests.sh`
  / `.ps1` run the whole verification set (Part 9).

No bugs found in: spawn fairness (no overlaps, no push-apart needed), local co-op modes,
online 1v1 and 2v2 on localhost (no desync), menus (no blockers), class smoke (no stalls).

## Owed / next

- Kevin: read the report's **Open questions** (shrines in Brawl / Crater on 1v1 maps; fighter
  radius vs 2x art; fall rule defaults and walkable cracks; the Twin Keeps trees; Gillbert 87% /
  Cairn 12% in the smoke bench; "Floor of pits" mutator defanged by the fall rule; who may pause
  in local play) and the **Playtest by hand** list, then decide whether to open the PR.
- If the fall rule is accepted: a `docs/decisions.md` entry (not written yet, by design).
- Server: `update.sh` after the merge (NET 76).
- Leftovers: `docs/open-items.md` "Local play"; the report's "Found, not fixed".

## Agent worktrees

`.claude/worktrees/agent-a167e74aa811ffd70` (Parts 1 and 6a) and
`.claude/worktrees/agent-a2ae7dfca45cf537a` (Part 2) hold the merged sub-branches
`qa/p1-mode-leak`, `qa/p6a-local`, `qa/p2-pit-footprint`; keep them until the branch merges
(they can be resumed for follow-ups), then `git worktree remove`.
